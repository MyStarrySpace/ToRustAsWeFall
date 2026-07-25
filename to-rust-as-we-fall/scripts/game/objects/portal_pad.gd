class_name PortalPad
extends Interactable

## A PORTAL PAD: the in-world, clickable realization of a "portal" (GDD: the teleport network that eliminates
## backtracking). The abstract zone-graph EDGE is the `Portal` RefCounted data class; THIS is the physical pad a
## member steps onto. Click it and the activating member (whoever arrives first) steps through to the paired
## destination — bidirectional (place two pointed at each other) and reusable, so a member can return.
## Only the one who activated it crosses; it never moves the whole party.
##
## Self-contained + reusable like Flure: owns its glow visual, its outline/hover wiring (consistent highlight), and
## its teleport logic. A fragment composes it (place + give it a destination); a level builder will too.
##
## GROUP CROSSING: when the ACTIVATOR belongs to the current selection (the loader installs a
## group provider), the whole selection QUEUES through — one member at a time, each teleporting and
## then walking OFF the receiving pad to its own arrival slot so the next can step in. Hovering the
## pad previews GHOSTS standing on those final slots; compute_group_arrivals is the ONE function
## both the ghosts and the committed queue read, so the preview cannot lie. An activator outside
## the selection crosses alone (the original solo semantics).

signal stepped_through(who: String, dest: Vector3)
signal group_crossing_finished(ids: Array)
signal group_crossing_cancelled(ids: Array, reason: StringName)

const GROUP_CLEAR_GAP := 0.15        # breath between one member clearing the pad and the next stepping in
const ARRIVAL_RING_RADIUS := 1.7     # the walk-off fan on the far side
const STATE_CONTRACT := "portal_pad/v2"
const LEGACY_STATE_CONTRACT := "portal_pad/v1"
const PHASE_IDLE := "idle"
const PHASE_CROSSING := "crossing"
const HOP_PHASE_RESERVED := "reserved"
const HOP_POSITION_EPSILON := 0.35
const SOURCE_POSITION_EPSILON := 0.5
const TRIGGER_RECEIPT_POSITION_EPSILON := 0.05

@export var glow_color := Color(0.55, 0.42, 0.98)
@export var glow_radius := 0.5
## Stable authored identity. When omitted, configure derives one from name + canonical endpoints.
@export var authority_id := ""

var _gs   # GameState (Interactable keeps its own _game_state for data binding; we hold our own for the teleport)
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _dest := Vector3.ZERO
var _data_authored := false
var _source_data := Vector3.ZERO
var _dest_data := Vector3.ZERO
var _group_provider: Callable = Callable()   # -> Array of selected char ids (the loader installs it)
# Compatibility/debug mirrors rebuilt from the authority record; gameplay never branches on them.
var _queue: Array = []
var _queue_arrivals: Array = []
var _queue_i := 0
var _ghosts: Array = []
var _resolved_authority_id := ""
## Ephemeral capability opened only around Interactable._trigger(). The prevalidator fills the
## exact source/body receipt; interacted consumes it in the same synchronous stack frame.
var _portal_trigger_open := false
var _portal_trigger_dispatch_serial := 0
var _pending_trigger_receipt: Dictionary = {}
var _portal_extra_pre_trigger_validator := Callable()

## Configure BEFORE adding to the tree. `dest_world` is the paired portal's position this one sends you to.
func configure(gs, world_pos: Vector3, dest_world: Vector3, radius := 1.2,
		color := Color(0.55, 0.42, 0.98)) -> void:
	_cancel_authoritative_callbacks()
	_pending_trigger_receipt.clear()
	_portal_trigger_open = false
	_data_authored = false
	_gs = gs
	position = world_pos
	_dest = dest_world
	_source_data = world_pos
	_dest_data = dest_world
	interaction_radius = radius
	glow_color = color
	interactable_type = InteractableType.INSPECTION
	one_shot = false   # reusable: step through, and back
	description = "Step through"
	tutorial_label = "PORTAL"
	_resolved_authority_id = _resolve_authority_id(world_pos, dest_world)
	super.set_pre_trigger_validator(_validate_portal_trigger)
	_ensure_authority_record()
	_restore_authoritative_runtime()

## Configure in GameState data coordinates while allowing the pad, destination, ghosts, and hover fan to
## render through a later-installed coord map. The canonical destination never becomes a warped world point,
## so a portal authored before the environment model loads cannot double-convert its arrival.
func configure_data(gs, source_data: Vector3, dest_data: Vector3, radius := 1.2,
		color := Color(0.55, 0.42, 0.98)) -> void:
	configure(gs, source_data, dest_data, radius, color)
	_data_authored = true
	_source_data = source_data
	_dest_data = dest_data
	var saved := _authority_or_default()
	saved["source_data"] = GameEvent.v3_to_arr(source_data)
	saved["destination_data"] = GameEvent.v3_to_arr(dest_data)
	_publish_authority(saved)
	set_meta("flat_authored_position", source_data)
	if _gs != null and _gs.coord_map != null:
		position = _gs.coord_map.to_world(source_data)

func get_data_source() -> Vector3:
	return _source_data if _data_authored else position

func get_data_destination() -> Vector3:
	return _dest_data if _data_authored else _destination_data()

func _destination_world() -> Vector3:
	if _data_authored and _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(_dest_data)
	return _dest_data if _data_authored else _dest

func _destination_data() -> Vector3:
	if _data_authored:
		return _dest_data
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(_dest)
	return _dest

func _arrival_world_to_data(world: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(world)
	return world

func _snap_arrival_world(world: Vector3) -> Vector3:
	if _gs == null or _gs.grid == null:
		return world
	var data: Vector3 = _gs.coord_map.to_data(world) if _gs.coord_map != null else world
	var level := 0
	if int(_gs.grid.get("level_count")) > 1 and _gs.grid.has_method("level_for_y"):
		level = int(_gs.grid.level_for_y(data.y))
	var cell: Vector2i = _gs.grid.nearest_walkable_cell(
		_gs.grid.world_to_grid(data), level)
	data = _gs.grid.grid_to_world(cell, level)
	return _gs.coord_map.to_world(data) if _gs.coord_map != null else data

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_glow = _build_glow()
	super._ready()
	_wire_outline()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)
	_restore_authoritative_runtime()

func _build_glow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	var sph := SphereMesh.new()
	sph.radius = glow_radius
	sph.height = glow_radius * 2.0
	mi.mesh = sph
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = glow_color * 0.5
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow_color
	_glow_mat.emission_energy_multiplier = 0.8
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, 0.6, 0.0)
	add_child(mi)
	return mi

func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _glow == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_glow], "portal", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target is Node3D and _glow is Node3D:
		(target as Node3D).global_position = (_glow as Node3D).global_position
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

## A STUNNED portal refuses all transit until the stun expires (the Hushbloom portal-stun — the
## chase framework's expert-solution mechanic: sealing both of an offshoot's portals makes it a
## locked pocket). Pure tick check; the glow dims while sealed.
var _stunned_until := -1.0 # compatibility/read cache; GameState owns the deadline

func stun(duration: float) -> void:
	if _gs == null or _gs.scheduler == null or duration <= 0.0:
		return
	var saved := _authority_or_default()
	saved["stunned_until_tick"] = float(_gs.scheduler.get_current_tick()) + duration
	_publish_authority(saved)
	_rearm_authoritative_callbacks(saved)

func is_stunned() -> bool:
	if _gs == null or _gs.scheduler == null:
		return false
	var saved := get_authority_state()
	return float(_gs.scheduler.get_current_tick()) \
			< float(saved.get("stunned_until_tick", -1.0))

func _refresh_stun_visual() -> void:
	_apply_stun_visual()

func _trigger(play_feedback := true) -> bool:
	if _portal_trigger_open:
		return false
	_portal_trigger_dispatch_serial += 1
	_portal_trigger_open = true
	_pending_trigger_receipt.clear()
	var accepted := super._trigger(play_feedback)
	# `interacted` is synchronous. Anything left here belongs to a rejected/stale attempt and must
	# not become a reusable capability for a later direct callback.
	_pending_trigger_receipt.clear()
	_portal_trigger_open = false
	return accepted


func _validate_portal_trigger(source: Node, actor: String) -> bool:
	_pending_trigger_receipt.clear()
	if not _portal_trigger_open or source != self or actor.is_empty() \
			or _gs == null or _gs.scheduler == null or is_stunned() \
			or is_group_crossing_active() or not _body_parked_at_source(actor):
		return false
	var group := _group_for(actor)
	if group.is_empty() or str(group[0]) != actor or not _all_bodies_parked_at_source(group):
		return false
	if _portal_extra_pre_trigger_validator.is_valid() \
			and not bool(_portal_extra_pre_trigger_validator.call(source, actor)):
		return false
	var source_positions := {}
	for id_variant in group:
		var id := str(id_variant)
		source_positions[id] = GameEvent.v3_to_arr(_gs.get_position(id))
	_pending_trigger_receipt = {
		"dispatch_serial": _portal_trigger_dispatch_serial,
		"source_key": authority_state_key(),
		"actor": actor,
		"group": group.duplicate(),
		"source_data": GameEvent.v3_to_arr(get_data_source()),
		"source_positions": source_positions,
		"accepted_tick": float(_gs.scheduler.get_current_tick()),
		"consumed": false,
	}
	return true


## Scenario policy may narrow portal eligibility, but it cannot replace the reusable object's exact
## physical source receipt.
func set_pre_trigger_validator(validator: Callable) -> void:
	_portal_extra_pre_trigger_validator = validator
	super.set_pre_trigger_validator(_validate_portal_trigger)


func _on_interacted() -> void:
	if not _portal_trigger_open or _pending_trigger_receipt.is_empty():
		return
	var receipt := _pending_trigger_receipt.duplicate(true)
	# Consume before publishing or snapping. Re-entrant/stale callbacks in this same signal fan-out
	# see no capability, while saved authority retains only the historical paid receipt.
	_pending_trigger_receipt.clear()
	_commit_triggered_transit(receipt)

## The loader hands the pad a way to read the CURRENT selection, so a click can move the party.
func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

## Who a click sends through: the selection with the activator leading, when the activator belongs
## to it; otherwise just the activator (solo semantics — the wash-intro one-at-a-time teach).
func _group_for(activator: String) -> Array:
	var sel: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if not cid.is_empty() and not sel.has(cid):
				sel.append(cid)
	if activator != "" and sel.has(activator):
		sel.erase(activator)
		sel.push_front(activator)
		return sel
	if activator != "":
		return [activator]
	return sel

## The far-side arrival slots — a walk-off fan pointing AWAY along the travel direction so nobody
## parks on the receiving pad. Pure + deterministic: hover ghosts and the committed queue both read
## THIS, so the preview always matches the crossing.
func compute_group_arrivals(ids: Array) -> Array:
	var out: Array = []
	var dest_world := _destination_world()
	var away := dest_world - global_position
	away.y = 0.0
	var base_angle := atan2(away.z, away.x) if away.length() > 0.01 else 0.0
	for i in range(ids.size()):
		var ang := base_angle + (float(i) - (float(ids.size()) - 1.0) * 0.5) * 0.9
		var pos := dest_world + Vector3(cos(ang), 0.0, sin(ang)) * ARRIVAL_RING_RADIUS
		pos.y = dest_world.y
		pos = _snap_arrival_world(pos)
		out.append(pos)
	return out

## Retired compatibility seam. A list of ids is not an accepted physical source-pad interaction.
func step_group_through(_ids: Array) -> bool:
	return false


## Both solo and selected-group interaction enter this one saved queue/hop transaction. The method
## accepts only the ephemeral receipt minted by this pad's currently executing Interactable trigger.
func _commit_triggered_transit(receipt: Dictionary) -> bool:
	if not _portal_trigger_open or receipt.is_empty() or is_stunned():
		return false
	if _gs == null or _gs.scheduler == null \
			or int(receipt.get("dispatch_serial", -1)) != _portal_trigger_dispatch_serial \
			or str(receipt.get("source_key", "")) != authority_state_key() \
			or bool(receipt.get("consumed", true)) \
			or str(_authority_or_default().get("phase", PHASE_IDLE)) == PHASE_CROSSING:
		return false
	var receipt_group_v: Variant = receipt.get("group", [])
	if not (receipt_group_v is Array):
		return false
	var normalized: Array = []
	var seen := {}
	for id_variant in receipt_group_v as Array:
		var id := str(id_variant)
		if id.is_empty() or seen.has(id) or not _gs.characters.has(id) or _gs.is_downed(id):
			return false
		seen[id] = true
		normalized.append(id)
	if normalized.is_empty() or str(normalized[0]) != str(receipt.get("actor", "")) \
			or not _trigger_receipt_matches_live_bodies(receipt, normalized):
		return false
	var source_receipts := (
		receipt.get("source_positions", {}) as Dictionary
	).duplicate(true)
	var arrivals_data: Array = []
	for arrival_variant in compute_group_arrivals(normalized):
		arrivals_data.append(GameEvent.v3_to_arr(
			_arrival_world_to_data(arrival_variant as Vector3)))
	var saved := _authority_or_default()
	var trigger_serial := int(saved.get("trigger_serial", 0)) + 1
	receipt["serial"] = trigger_serial
	receipt["consumed"] = true
	receipt["consumed_tick"] = float(_gs.scheduler.get_current_tick())
	saved["phase"] = PHASE_CROSSING
	saved["queue"] = normalized
	saved["arrivals_data"] = arrivals_data
	saved["next_index"] = 0
	saved["next_hop_tick"] = float(_gs.scheduler.get_current_tick())
	saved["hop"] = {}
	saved["source_receipts"] = source_receipts
	saved["trigger_serial"] = trigger_serial
	saved["trigger_receipt"] = receipt.duplicate(true)
	_publish_authority(saved)
	_hop_next()
	return true


func _trigger_receipt_matches_live_bodies(receipt: Dictionary, ids: Array) -> bool:
	var positions_v: Variant = receipt.get("source_positions", {})
	if not (positions_v is Dictionary):
		return false
	var positions := positions_v as Dictionary
	for id_variant in ids:
		var id := str(id_variant)
		if not positions.has(id) or not _body_parked_at_source(id):
			return false
		var accepted_position := _v3_from_value(positions.get(id, []))
		if _planar_distance(_gs.get_position(id), accepted_position) \
				> TRIGGER_RECEIPT_POSITION_EPSILON:
			return false
	return true

func _hop_next() -> void:
	_cancel_hop_callback()
	if _gs == null or _gs.scheduler == null:
		return
	var saved := get_authority_state()
	if str(saved.get("phase", PHASE_IDLE)) != PHASE_CROSSING:
		return
	var reserved := _valid_hop_reservation(saved)
	if not reserved.is_empty():
		_resume_reserved_hop(saved, reserved)
		return
	var queue: Array = (saved.get("queue", []) as Array).duplicate()
	var arrivals: Array = (saved.get("arrivals_data", []) as Array).duplicate(true)
	var index := int(saved.get("next_index", 0))
	if index >= queue.size():
		var done := queue.duplicate()
		saved["phase"] = PHASE_IDLE
		saved["queue"] = []
		saved["arrivals_data"] = []
		saved["next_index"] = 0
		saved["next_hop_tick"] = -1.0
		saved["hop"] = {}
		_publish_authority(saved)
		if not done.is_empty():
			group_crossing_finished.emit(done)
		return
	if arrivals.size() != queue.size():
		arrivals.clear()
		for arrival_variant in compute_group_arrivals(queue):
			arrivals.append(GameEvent.v3_to_arr(
				_arrival_world_to_data(arrival_variant as Vector3)))
		saved["arrivals_data"] = arrivals.duplicate(true)
	var who := str(queue[index])
	# A queued member is not a remote teleport token. Until its hop is reserved, its
	# canonical body must remain parked on this exact source pad; moving away cancels
	# the uncommitted tail instead of cashing an old selection in from across the room.
	if not _body_parked_at_source(who):
		cancel_group_crossing(&"portal_source_occupancy_lost")
		return
	var slot_data := _v3_from_value(arrivals[index])
	var serial := int(saved.get("hop_serial", 0)) + 1
	var source_data: Vector3 = _gs.get_position(who) \
		if _gs.characters.has(who) else get_data_source()
	var destination_data := _v3_from_value(saved.get(
		"destination_data", GameEvent.v3_to_arr(_destination_data())))
	var reservation := {
		"phase": HOP_PHASE_RESERVED,
		"serial": serial,
		"index": index,
		"who": who,
		"source_data": GameEvent.v3_to_arr(source_data),
		"destination_data": GameEvent.v3_to_arr(destination_data),
		"arrival_data": GameEvent.v3_to_arr(slot_data),
		"reserved_at": float(_gs.scheduler.get_current_tick()),
	}
	# Claim this queue position before teleporting. The reservation is the missing
	# half of that early index commit: a pre-snap save still knows exactly which
	# body, destination, and walk-off command must be realized.
	saved["next_index"] = index + 1
	saved["next_hop_tick"] = float(_gs.scheduler.get_current_tick())
	saved["hop_serial"] = serial
	saved["hop"] = reservation
	_publish_authority(saved)

	# A listener may synchronously roll back/cancel from the reservation signal.
	# Only execute if this exact transaction is still the authoritative one.
	var current := get_authority_state()
	var current_reservation := _valid_hop_reservation(current)
	if _same_hop_reservation(current_reservation, reservation):
		_resume_reserved_hop(current, current_reservation)


func _resume_reserved_hop(saved: Dictionary, reservation: Dictionary) -> void:
	_cancel_hop_callback()
	if _gs == null or _gs.scheduler == null \
			or str(saved.get("phase", PHASE_IDLE)) != PHASE_CROSSING \
			or not _same_hop_reservation(_valid_hop_reservation(saved), reservation):
		return
	var who := str(reservation.get("who", ""))
	var destination_data := _v3_from_value(reservation.get("destination_data", []))
	var arrival_data := _v3_from_value(reservation.get("arrival_data", []))
	var body_exists: bool = _gs.characters.has(who) and not _gs.is_downed(who)
	var already_teleported: bool = body_exists \
		and _reserved_hop_is_physically_applied(reservation)
	if body_exists and not already_teleported:
		_gs.command_stop(who)
		# Portal semantics remain an instantaneous topology hop. Only the far-side
		# pad-clear is ordinary movement.
		_gs.snap_character_to(who, destination_data)
		_gs.command_move_to_pos(who, arrival_data)
		stepped_through.emit(who, destination_data)

	# A stepped_through listener may load/cancel synchronously. Never let this
	# discarded stack frame overwrite the newly restored transaction.
	var current := get_authority_state()
	var current_reservation := _valid_hop_reservation(current)
	if not _same_hop_reservation(current_reservation, reservation):
		return
	if _gs.characters.has(who) and not _gs.is_downed(who) \
			and not _reserved_hop_is_physically_applied(current_reservation):
		return
	_finalize_reserved_hop(current, current_reservation)


func _finalize_reserved_hop(saved: Dictionary, reservation: Dictionary) -> void:
	if _gs == null or _gs.scheduler == null:
		return
	var who := str(reservation.get("who", ""))
	var wait := GROUP_CLEAR_GAP
	if _gs.has_method("get_plan_end_tick") and _gs.characters.has(who):
		var end_tick: float = _gs.get_plan_end_tick(who)
		if end_tick >= 0.0:
			wait = maxf(
				GROUP_CLEAR_GAP,
				end_tick - float(_gs.scheduler.get_current_tick()) + GROUP_CLEAR_GAP)
	saved["hop"] = {}
	saved["next_hop_tick"] = float(_gs.scheduler.get_current_tick()) + wait
	_publish_authority(saved)
	_rearm_hop_callback(saved)


func _valid_hop_reservation(saved: Dictionary) -> Dictionary:
	var hop_v: Variant = saved.get("hop", {})
	if not (hop_v is Dictionary):
		return {}
	var hop := (hop_v as Dictionary).duplicate(true)
	if str(hop.get("phase", "")) != HOP_PHASE_RESERVED:
		return {}
	var queue_v: Variant = saved.get("queue", [])
	if not (queue_v is Array):
		return {}
	var queue := queue_v as Array
	var index := int(hop.get("index", -1))
	if index < 0 or index >= queue.size() \
			or str(hop.get("who", "")) != str(queue[index]) \
			or int(saved.get("next_index", -1)) != index + 1 \
			or int(hop.get("serial", 0)) <= 0:
		return {}
	return hop


func _same_hop_reservation(left: Dictionary, right: Dictionary) -> bool:
	return not left.is_empty() and not right.is_empty() \
			and int(left.get("serial", -1)) == int(right.get("serial", -2)) \
			and int(left.get("index", -1)) == int(right.get("index", -2)) \
			and str(left.get("who", "")) == str(right.get("who", "__missing__"))


func _reserved_hop_is_physically_applied(reservation: Dictionary) -> bool:
	var who := str(reservation.get("who", ""))
	if _gs == null or not _gs.characters.has(who):
		return false
	var current: Vector3 = _gs.get_position(who)
	var source := _v3_from_value(reservation.get("source_data", []))
	var destination := _v3_from_value(reservation.get("destination_data", []))
	var arrival := _v3_from_value(reservation.get("arrival_data", []))
	if _gs.has_method("get_destination"):
		var planned: Vector3 = _gs.get_destination(who)
		# A REJECTED walk-off (the arrival slot snapped somewhere unreachable, so the
		# move plan doesn't exist) must not block finalization forever: the hop itself is
		# applied the moment the body stands at the destination (or arrival). Otherwise a
		# reserved hop wedges at index 0 and the rest of the queue never crosses.
		if not planned.is_finite():
			return _planar_distance(current, destination) <= HOP_POSITION_EPSILON \
				or _planar_distance(current, arrival) <= HOP_POSITION_EPSILON
		if _planar_distance(planned, arrival) <= HOP_POSITION_EPSILON \
				and (_planar_distance(current, destination) <= HOP_POSITION_EPSILON \
					or _planar_distance(current, arrival) <= HOP_POSITION_EPSILON \
					or _planar_distance(current, source) > HOP_POSITION_EPSILON):
			return true
	return false


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _body_parked_at_source(who: String) -> bool:
	if _gs == null or who.is_empty() or not _gs.characters.has(who) \
			or _gs.is_downed(who) or _gs.is_moving(who) \
			or (_gs.has_method("is_external_traversal_active") \
				and bool(_gs.is_external_traversal_active(who))):
		return false
	for method_name in [
		"is_knocked_down",
		"is_dodging",
		"is_endocytosing",
		"is_resting",
		"is_field_restoring",
	]:
		if _gs.has_method(method_name) and bool(_gs.call(method_name, who)):
			return false
	if _gs.has_method("is_narratively_available") \
			and not bool(_gs.is_narratively_available(who)):
		return false
	return _planar_distance(_gs.get_position(who), get_data_source()) \
		<= interaction_radius + SOURCE_POSITION_EPSILON


func _all_bodies_parked_at_source(ids: Array) -> bool:
	for id_variant in ids:
		if not _body_parked_at_source(str(id_variant)):
			return false
	return not ids.is_empty()

func _hop_tag() -> String:
	return "portal_hop_%s" % str(absi(authority_state_key().hash()))


## Stable GameState namespace used by save/load and rollback. Endpoint data is part of the derived
## fallback identity so two same-named pads in different places cannot share a queue accidentally.
func authority_state_key() -> String:
	var resolved := _resolved_authority_id
	if resolved.is_empty():
		resolved = authority_id.strip_edges()
	if resolved.is_empty():
		resolved = str(name) if not str(name).is_empty() else "unconfigured"
	return "gameplay:portal_pad:%s" % resolved


func get_authority_state() -> Dictionary:
	if _gs == null or not _gs.has_method("get_world_state"):
		return {}
	var value: Variant = _gs.get_world_state(authority_state_key(), {})
	if not (value is Dictionary):
		return {}
	var saved := (value as Dictionary).duplicate(true)
	var contract := str(saved.get("contract", ""))
	if contract not in [STATE_CONTRACT, LEGACY_STATE_CONTRACT] \
			or str(saved.get("authority_id", "")) != _resolved_authority_id:
		return {}
	# v1 queue records had no in-flight reservation. Their next_index already
	# described fully completed hops, so they migrate safely with no owed hop.
	if contract == LEGACY_STATE_CONTRACT:
		saved["contract"] = STATE_CONTRACT
		saved["hop"] = {}
		saved["hop_serial"] = int(saved.get("hop_serial", 0))
	return saved


func get_transit_state() -> Dictionary:
	var saved := _authority_or_default()
	var now := float(_gs.scheduler.get_current_tick()) \
			if _gs != null and _gs.scheduler != null else 0.0
	saved["next_hop_in"] = maxf(0.0, float(saved.get("next_hop_tick", now)) - now) \
			if str(saved.get("phase", PHASE_IDLE)) == PHASE_CROSSING else 0.0
	saved["stun_remaining"] = maxf(
		0.0, float(saved.get("stunned_until_tick", -1.0)) - now)
	return saved


func is_group_crossing_active() -> bool:
	return str(_authority_or_default().get("phase", PHASE_IDLE)) == PHASE_CROSSING


## Mechanism-owned transit for non-click actors such as pursuers. Unlike the legacy instant player
## hop, this commits a locked GameState traversal with a real interval, so saves, targeting, replay,
## and rendering all observe the same in-flight body. The caller may request the reverse endpoint,
## but cannot start a transit unless the body has physically reached that end of this portal.
func begin_external_transit(
		who: String,
		traversal_id: StringName,
		duration: float,
		reverse := false
	) -> bool:
	if _gs == null or _gs.scheduler == null or is_stunned() or is_group_crossing_active() \
			or duration <= 0.0 or not _gs.characters.has(who) or _gs.is_downed(who) \
			or _gs.is_external_traversal_active(who):
		return false
	var source_data: Vector3 = get_data_destination() if reverse else get_data_source()
	var destination_data: Vector3 = get_data_source() if reverse else get_data_destination()
	var current_data: Vector3 = _gs.get_position(who)
	var planar_gap := Vector2(current_data.x - source_data.x,
		current_data.z - source_data.z).length()
	if planar_gap > interaction_radius + 0.5:
		return false
	var destination_render: Vector3 = destination_data
	if _gs.coord_map != null and _gs.coord_map.has_method("to_world"):
		destination_render = _gs.coord_map.to_world(destination_data)
	var accepted := bool(_gs.command_external_traversal(
		who, traversal_id, destination_data, _gs.get_render_position(who),
		destination_render, duration, &"locked"))
	if accepted:
		stepped_through.emit(who, destination_data)
	return accepted


## An explicit rollback cancels only members that have not committed yet. Characters already snapped
## through retain their separately-authoritative movement; rollback never creates a second reality.
func cancel_group_crossing(reason: StringName = &"portal_queue_cancelled") -> bool:
	var saved := get_authority_state()
	if str(saved.get("phase", PHASE_IDLE)) != PHASE_CROSSING:
		return false
	var cancelled_ids: Array = (saved.get("queue", []) as Array).slice(
		int(saved.get("next_index", 0)))
	saved["phase"] = PHASE_IDLE
	saved["queue"] = []
	saved["arrivals_data"] = []
	saved["next_index"] = 0
	saved["next_hop_tick"] = -1.0
	saved["hop"] = {}
	_publish_authority(saved)
	_cancel_hop_callback()
	group_crossing_cancelled.emit(cancelled_ids, reason)
	return true


## Called by the production snapshot loader after it clears opaque scheduler Callables and replaces
## GameState. The stored absolute deadlines are rearmed once; no member already counted is repeated.
func on_game_state_snapshot_restored() -> void:
	_restore_authoritative_runtime()


func _default_authority_record() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_IDLE,
		"source_data": GameEvent.v3_to_arr(get_data_source()),
		"destination_data": GameEvent.v3_to_arr(get_data_destination()),
		"queue": [],
		"arrivals_data": [],
		"next_index": 0,
		"next_hop_tick": -1.0,
		"hop_serial": 0,
		"hop": {},
		"source_receipts": {},
		"trigger_serial": 0,
		"trigger_receipt": {},
		"stunned_until_tick": -1.0,
	}


func _authority_or_default() -> Dictionary:
	var saved := get_authority_state()
	return _default_authority_record() if saved.is_empty() else saved


func _ensure_authority_record() -> void:
	if _gs == null or _resolved_authority_id.is_empty() or not get_authority_state().is_empty():
		return
	_publish_authority(_default_authority_record())


func _publish_authority(saved: Dictionary) -> void:
	if _gs == null or not _gs.has_method("set_world_state"):
		return
	saved["contract"] = STATE_CONTRACT
	saved["authority_id"] = _resolved_authority_id
	_gs.set_world_state(authority_state_key(), saved.duplicate(true))
	_hydrate_runtime_cache(saved)
	_apply_stun_visual()


func _restore_authoritative_runtime() -> void:
	_cancel_authoritative_callbacks()
	_pending_trigger_receipt.clear()
	_portal_trigger_open = false
	_ensure_authority_record()
	var saved := _authority_or_default()
	_hydrate_runtime_cache(saved)
	_apply_stun_visual()
	_rearm_authoritative_callbacks(saved)


func _hydrate_runtime_cache(saved: Dictionary) -> void:
	_queue = (saved.get("queue", []) as Array).duplicate()
	_queue_i = int(saved.get("next_index", 0))
	_queue_arrivals.clear()
	for value in (saved.get("arrivals_data", []) as Array):
		_queue_arrivals.append(_arrival_data_to_world(_v3_from_value(value)))
	_stunned_until = float(saved.get("stunned_until_tick", -1.0))


func _rearm_authoritative_callbacks(saved: Dictionary) -> void:
	_cancel_authoritative_callbacks()
	_rearm_hop_callback(saved)
	if _gs == null or _gs.scheduler == null:
		return
	var stun_until := float(saved.get("stunned_until_tick", -1.0))
	if stun_until > float(_gs.scheduler.get_current_tick()):
		_gs.scheduler.schedule_at(stun_until, _refresh_stun_visual, _stun_tag())


func _rearm_hop_callback(saved: Dictionary) -> void:
	_cancel_hop_callback()
	if _gs == null or _gs.scheduler == null \
			or str(saved.get("phase", PHASE_IDLE)) != PHASE_CROSSING:
		return
	var next_tick := float(saved.get("next_hop_tick", -1.0))
	var now := float(_gs.scheduler.get_current_tick())
	# Never execute an owed teleport from inside restore/configure. Restoration
	# reconstructs one derived wake-up; the gameplay scheduler performs the hop.
	_gs.scheduler.schedule_at(maxf(now, next_tick), _hop_next, _hop_tag())


func _cancel_hop_callback() -> void:
	if _gs != null and _gs.scheduler != null:
		_gs.scheduler.cancel_tag(_hop_tag())


func _cancel_authoritative_callbacks() -> void:
	if _gs == null or _gs.scheduler == null:
		return
	_gs.scheduler.cancel_tag(_hop_tag())
	_gs.scheduler.cancel_tag(_stun_tag())


func _apply_stun_visual() -> void:
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 0.08 if is_stunned() else 1.6


func _stun_tag() -> String:
	return "%s_stun" % _hop_tag()


func _resolve_authority_id(source_data: Vector3, destination_data: Vector3) -> String:
	var explicit := authority_id.strip_edges()
	if not explicit.is_empty():
		return explicit
	var node_id := str(name).strip_edges()
	if node_id.is_empty():
		node_id = "portal_pad"
	return "%s@%s>%s" % [
		node_id,
		_vector_signature(source_data),
		_vector_signature(destination_data),
	]


func _vector_signature(value: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [value.x, value.y, value.z]


func _v3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return GameEvent.arr_to_v3(value as Array)
	return Vector3.ZERO


func _arrival_data_to_world(data: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(data)
	return data

# --- Hover ghosts: the party's FINAL positions on the far side, before anyone commits. ---

func set_hover_feedback(active: bool) -> void:
	super.set_hover_feedback(active)
	_update_ghosts(active)

func _update_ghosts(show_ghosts: bool) -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
	if not show_ghosts or _gs == null:
		return
	var ids: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if _gs.characters.has(cid) and not _gs.is_downed(cid) and not ids.has(cid):
				ids.append(cid)
	if ids.is_empty() and active_character != "" and _gs.characters.has(str(active_character)):
		ids = [str(active_character)]
	if ids.is_empty() or not _all_bodies_parked_at_source(ids):
		return
	var slots := compute_group_arrivals(ids)
	for i in range(slots.size()):
		var ghost := MeshInstance3D.new()
		ghost.name = "PortalGhost_%d" % i
		var cap := CapsuleMesh.new()
		cap.radius = 0.32
		cap.height = 1.15
		ghost.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = glow_color
		m.emission_energy_multiplier = 0.6
		ghost.material_override = m
		add_child(ghost)
		ghost.global_position = (slots[i] as Vector3) + Vector3(0.0, 0.6, 0.0)
		_ghosts.append(ghost)

func _exit_tree() -> void:
	_pending_trigger_receipt.clear()
	_portal_trigger_open = false
	_cancel_authoritative_callbacks()

## Retired compatibility seam. Even a gathered actor must consume this pad's exact Interactable
## trigger; callers cannot mint a portal hop by invoking a public helper.
func step_through() -> bool:
	return false
