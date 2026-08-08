class_name CrawlTunnel
extends Interactable

## A CRAWL MOUTH: a squeeze-through passage (wall pipe, vent, burrow) whose interior deliberately
## ignores the grid — the wall cells stay blocked; the crawl is the only way through. Click it and
## the activating member walks up, drops to a crawl (slow, CONCEAL_FULL — you are inside the tube),
## and follows the AUTHORED waypoint path out the far mouth. Tick-interpolated, so it fast-forwards
## and replays like every other move.
##
## GROUP ENTRY works like a PortalPad crossing: when the activator belongs to the current selection
## (the loader installs a group provider), the whole selection queues through — members line up at
## the mouth, enter ONE AT A TIME (a spacing gap keeps them single-file inside the tube), and each
## walks off to its own arrival slot on the far side so the exit never stacks. An activator outside
## the selection crawls alone.

signal crawl_started(who: String)
signal crawl_finished(who: String)
signal group_crawl_finished(ids: Array)
signal refused

const ENTRY_SPACING := 1.6          # in-tube distance kept between members (drives the entry gap)
const QUEUE_SLOT_GAP := 0.9         # line-up spacing outside the mouth
const ARRIVAL_RING_RADIUS := 1.6    # the walk-off fan past the exit mouth
const CRAWL_AUTHORITY_VERSION := 2
const LEGACY_CRAWL_AUTHORITY_VERSION := 1
const CRAWL_AUTHORITY_PREFIX := "runtime:crawl_tunnel:"
const APPROACH_EPSILON := 0.2
const TRAVERSAL_PHASE_RESERVED := "reserved"
const TRAVERSAL_PHASE_EFFECTS_PENDING := "effects_pending"
const TRAVERSAL_PHASE_CARRYING := "carrying"
const TRAVERSAL_PHASE_FINISHING := "finishing"

@export var crawl_speed := 0.9

var _gs
var _waypoints: Array[Vector3] = []
var _data_authored := false
var _mouth_data := Vector3.ZERO
var _data_waypoints: Array[Vector3] = []
var _group_provider: Callable = Callable()
var _queue: Array = []
var _queue_arrivals: Array = []
var _queue_i := 0
var _restore_speeds := {}           # char_id -> pre-crawl move speed
var _live_tags := {}                # every scheduler tag this tunnel has armed (cancelled on exit)
var _crawl_phases := {}             # stable phase key -> kind/actor/slot/absolute deadline
var _restoring_crawl_authority := false
var _source_receipt_pending := {}
var _activation_receipt := {}
var _receipt_seq := 0
var _crawl_traversals := {}         # char_id -> saved reservation/path/effect transaction
var _traversal_signal_gs = null
var _local_acceptance_in_progress := false

## Configure BEFORE adding to the tree. `waypoints` is the tube interior from just inside THIS
## mouth to the far exit (world space); the crawler's own position is prepended at entry time.
func configure(gs, mouth_world: Vector3, waypoints: Array, radius := 1.4, speed := 0.9) -> void:
	_data_authored = false
	_gs = gs
	position = mouth_world
	_waypoints.clear()
	for wp in waypoints:
		_waypoints.append(wp as Vector3)
	interaction_radius = radius
	crawl_speed = speed
	interactable_type = InteractableType.INSPECTION
	one_shot = false
	set_pre_trigger_validator(_validate_crawl_source_receipt)
	_connect_traversal_signals()
	if description == "":
		description = "Crawl through"
	if tutorial_label == "":
		tutorial_label = "CRAWL"

## Data-coordinate authoring for warped levels. Movement remains canonical in GameState space; the mouth,
## queue, arrival fan, and hover geometry are projected through the coord map only for presentation.
func configure_data(gs, mouth_data: Vector3, waypoints_data: Array, radius := 1.4, speed := 0.9) -> void:
	configure(gs, mouth_data, waypoints_data, radius, speed)
	_data_authored = true
	_mouth_data = mouth_data
	_data_waypoints.clear()
	for wp in waypoints_data:
		_data_waypoints.append(wp as Vector3)
	set_meta("flat_authored_position", mouth_data)
	if _gs != null and _gs.coord_map != null:
		position = _gs.coord_map.to_world(mouth_data)

func get_data_mouth() -> Vector3:
	return _mouth_data if _data_authored else position

func get_data_waypoints() -> Array:
	return _data_waypoints.duplicate() if _data_authored else _waypoints.duplicate()

func _movement_waypoints() -> Array[Vector3]:
	return _data_waypoints if _data_authored else _waypoints

func _render_waypoints() -> Array[Vector3]:
	if not _data_authored or _gs == null or _gs.coord_map == null:
		return _waypoints
	var out: Array[Vector3] = []
	for wp in _data_waypoints:
		out.append(_gs.coord_map.to_world(wp))
	return out

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	super._ready()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)
	_connect_traversal_signals()

func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

func is_group_crawl_active() -> bool:
	return not _queue.is_empty()

## Optional activation gate, checked at interaction time: a Callable returning false refuses
## the whole activation (nothing consumed; `refused` is emitted so the host can say why). The
## lockout barricade uses it for the pair boost -- a two-person move needs two people.
var requirement: Callable = Callable()

## The grid level the crawler stands on when it emerges (-1 = keep the entry level). A gangway
## that carries you from a deck down through a building sets 0 so the exit snaps to the ground
## plane (set_character_level is logged — replay-safe like the rest of the crawl).
@export var exit_level := -1

## Whether the authored transit hides its rider (a crawl tube = CONCEAL_FULL; an open resource
## belt = exposed the whole ride). Subclasses flip it.
@export var conceal_riders := true

func _trigger(play_feedback := true) -> bool:
	if requirement.is_valid() and not bool(requirement.call()):
		refused.emit()
		return false
	# Unbound scene interactables still use Interactable's local acceptance guards. Keep a
	# synchronous-only proof around its interacted emission; a direct method call has no such proof.
	_local_acceptance_in_progress = true
	var accepted := super._trigger(play_feedback)
	_local_acceptance_in_progress = false
	if not accepted and not _source_receipt_pending.is_empty():
		_source_receipt_pending.clear()
		_publish_crawl_authority()
	return accepted


func _validate_crawl_source_receipt(source: Node, actor_value: String) -> bool:
	if source != self or _gs == null or _gs.scheduler == null:
		return false
	var actor := str(actor_value)
	if not _actor_can_actuate(actor) or not _actor_at_mouth(actor):
		return false
	if not _source_receipt_pending.is_empty() or not _queue.is_empty() \
			or not _crawl_traversals.is_empty() \
			or not _activation_receipt.is_empty() or _has_subclass_pending_activation():
		return false
	var group := _group_for(actor)
	if group.is_empty() or str(group[0]) != actor:
		return false
	var expected_trigger_count := -1
	if _uses_bound_source_authority():
		expected_trigger_count = int(
			_gs.get_interactable(data_id).get("trigger_count", 0)) + 1
	_receipt_seq += 1
	_source_receipt_pending = {
		"source_id": _crawl_source_id(),
		"actor": actor,
		"group": group.duplicate(),
		"accepted_tick": float(_gs.scheduler.get_current_tick()),
		"nonce": _receipt_seq,
		"expected_trigger_count": expected_trigger_count,
		"phase": "source_reserved",
	}
	# GameState.trigger_interactable emits synchronously. The exact source/body/proximity receipt
	# must already exist if a save is captured from that accepted-trigger signal.
	_publish_crawl_authority()
	return true


func _on_interacted() -> void:
	if _source_receipt_pending.is_empty():
		return
	var receipt: Dictionary = _source_receipt_pending.duplicate(true)
	_source_receipt_pending.clear()
	if not _receipt_matches_source(receipt):
		_publish_crawl_authority()
		return
	if not _uses_bound_source_authority() and _local_acceptance_in_progress:
		receipt["local_accepted"] = true
	if not _accept_interaction_receipt(receipt):
		_publish_crawl_authority()


func _accept_interaction_receipt(receipt: Dictionary) -> bool:
	return _commit_group_crawl_from_receipt(
		(receipt.get("group", []) as Array).duplicate(), receipt)


func _has_subclass_pending_activation() -> bool:
	return false


func _actor_can_actuate(actor: String) -> bool:
	if actor == "" or _gs == null or not _gs.characters.has(actor) or _gs.is_downed(actor):
		return false
	if _gs.has_method("is_external_traversal_active") \
			and _gs.is_external_traversal_active(actor):
		return false
	if _gs.has_method("is_endocytosing") and _gs.is_endocytosing(actor):
		return false
	if _gs.has_method("is_dodging") and _gs.is_dodging(actor):
		return false
	if _gs.has_method("is_knocked_down") and _gs.is_knocked_down(actor):
		return false
	if _gs.has_method("is_dragging") and _gs.is_dragging(actor):
		return false
	return not _gs.is_moving(actor)


func _actor_at_mouth(actor: String) -> bool:
	if _gs == null or not _gs.characters.has(actor):
		return false
	var body: Vector3 = _gs.get_position(actor)
	var mouth := get_data_mouth()
	return Vector2(body.x - mouth.x, body.z - mouth.z).length() \
		<= interaction_radius + APPROACH_EPSILON \
		and absf(body.y - mouth.y) <= maxf(1.5, interaction_radius)


func _crawl_source_id() -> String:
	var stable_id := data_id if data_id != "" else interactable_id
	if stable_id == "" and is_inside_tree():
		stable_id = str(get_path())
	return stable_id


func _receipt_matches_source(receipt: Dictionary) -> bool:
	var actor := str(receipt.get("actor", ""))
	var group: Array = receipt.get("group", [])
	return str(receipt.get("source_id", "")) == _crawl_source_id() \
		and int(receipt.get("nonce", 0)) > 0 \
		and int(receipt.get("expected_trigger_count", -1)) != 0 \
		and actor != "" and not group.is_empty() and str(group[0]) == actor


func _uses_bound_source_authority() -> bool:
	return _gs != null and data_id != "" and _gs.has_method("has_interactable") \
			and _gs.has_interactable(data_id)


func _connect_traversal_signals() -> void:
	if _traversal_signal_gs == _gs:
		return
	_disconnect_traversal_signals()
	_traversal_signal_gs = _gs
	if _traversal_signal_gs == null:
		return
	if _traversal_signal_gs.has_signal("external_traversal_finished") \
			and not _traversal_signal_gs.external_traversal_finished.is_connected(
				_on_crawl_external_finished):
		_traversal_signal_gs.external_traversal_finished.connect(_on_crawl_external_finished)
	if _traversal_signal_gs.has_signal("external_traversal_cancelled") \
			and not _traversal_signal_gs.external_traversal_cancelled.is_connected(
				_on_crawl_external_cancelled):
		_traversal_signal_gs.external_traversal_cancelled.connect(_on_crawl_external_cancelled)


func _disconnect_traversal_signals() -> void:
	if _traversal_signal_gs == null or not is_instance_valid(_traversal_signal_gs):
		_traversal_signal_gs = null
		return
	if _traversal_signal_gs.has_signal("external_traversal_finished") \
			and _traversal_signal_gs.external_traversal_finished.is_connected(
				_on_crawl_external_finished):
		_traversal_signal_gs.external_traversal_finished.disconnect(_on_crawl_external_finished)
	if _traversal_signal_gs.has_signal("external_traversal_cancelled") \
			and _traversal_signal_gs.external_traversal_cancelled.is_connected(
				_on_crawl_external_cancelled):
		_traversal_signal_gs.external_traversal_cancelled.disconnect(_on_crawl_external_cancelled)
	_traversal_signal_gs = null


func _on_crawl_external_finished(actor: String, traversal_id: StringName) -> void:
	if not _crawl_traversals.has(actor):
		return
	var transaction: Dictionary = _crawl_traversals[actor]
	if str(transaction.get("traversal_id", "")) != String(traversal_id):
		return
	_finish_crawl_transaction(actor, false)


func _on_crawl_external_cancelled(
		actor: String, traversal_id: StringName, _reason: StringName
	) -> void:
	if not _crawl_traversals.has(actor):
		return
	var transaction: Dictionary = _crawl_traversals[actor]
	if str(transaction.get("traversal_id", "")) != String(traversal_id):
		return
	_finish_crawl_transaction(actor, true)


func _retire_activation_if_idle() -> void:
	if _queue.is_empty() and _crawl_traversals.is_empty() and _restore_speeds.is_empty():
		_activation_receipt.clear()


func _has_matching_crawl_traversal(actor: String, traversal_id: String) -> bool:
	if _gs == null or not _gs.has_method("is_external_traversal_active") \
			or not _gs.is_external_traversal_active(actor):
		return false
	var state: Dictionary = _gs.get_external_traversal_state(actor)
	return str(state.get("traversal_id", "")) == traversal_id


func _portable_path(path: Array[Vector3]) -> Array:
	var out: Array = []
	for point in path:
		out.append(_vec3_to_data(point))
	return out

## Who a click sends through: the selection with the activator leading when the activator belongs
## to it; otherwise just the activator (solo semantics).
func _group_for(activator: String) -> Array:
	var sel: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if _gs != null and _gs.characters.has(cid) and not _gs.is_downed(cid) and not sel.has(cid):
				sel.append(cid)
	if activator != "" and sel.has(activator):
		sel.erase(activator)
		sel.push_front(activator)
		return sel
	if activator != "":
		return [activator]
	return sel

## Line-up slots outside the mouth: single file back along the approach direction (away from the
## tube), each snapped walkable. Deterministic — tests and any future ghost preview read this.
func compute_queue_slots(ids: Array) -> Array:
	var out: Array = []
	var into := _tube_dir()
	for i in range(ids.size()):
		var pos := global_position - into * (QUEUE_SLOT_GAP * float(i + 1))
		pos.y = global_position.y
		out.append(_snap_walkable(pos))
	return out

## Walk-off fan past the exit mouth, pointing onward along the tube's final direction, so nobody
## parks on the far mouth and the next crawler always has a clear exit.
func compute_group_arrivals(ids: Array) -> Array:
	var out: Array = []
	var render_waypoints := _render_waypoints()
	if render_waypoints.is_empty():
		return out
	var exit_pos := render_waypoints[render_waypoints.size() - 1]
	var onward := _exit_dir()
	var base_angle := atan2(onward.z, onward.x)
	for i in range(ids.size()):
		var ang := base_angle + (float(i) - (float(ids.size()) - 1.0) * 0.5) * 0.9
		var pos := exit_pos + Vector3(cos(ang), 0.0, sin(ang)) * ARRIVAL_RING_RADIUS
		pos.y = exit_pos.y
		out.append(_snap_walkable(pos))
	return out

## This helper intentionally has no consequence authority. A crawl may begin only from this exact
## Interactable's accepted source/body/proximity receipt; arbitrary IDs cannot remotely enter.
func start_group_crawl(ids: Array) -> bool:
	if ids.is_empty():
		return false
	return false


## Queue the receipt's group through: everyone lines up, then members enter one at a time with an
## in-tube spacing gap. All timing rides the gameplay scheduler (pause/fast-forward safe).
func _commit_group_crawl_from_receipt(ids: Array, receipt: Dictionary) -> bool:
	if _gs == null or ids.is_empty() or not _queue.is_empty() \
			or not _crawl_traversals.is_empty() or not _receipt_matches_source(receipt) \
			or not _receipt_was_accepted(receipt):
		return false
	if ids != (receipt.get("group", []) as Array):
		return false
	_queue = ids.duplicate()
	_queue_arrivals = compute_group_arrivals(ids)
	_queue_i = 0
	_activation_receipt = receipt.duplicate(true)
	_activation_receipt["phase"] = "queue_committed"
	_publish_crawl_authority()
	var slots := compute_queue_slots(ids)
	for i in range(1, ids.size()):
		var cid := str(ids[i])
		if _gs.characters.has(cid) and not _gs.is_downed(cid):
			_gs.command_move_to_pos(cid, _to_data(slots[mini(i - 1, slots.size() - 1)]))
	_enter_next()
	return true

func _enter_next() -> void:
	if _gs == null or _queue_i >= _queue.size():
		var done := _queue.duplicate()
		_queue.clear()
		_queue_i = 0
		_retire_activation_if_idle()
		_publish_crawl_authority()
		if not done.is_empty():
			group_crawl_finished.emit(done)
		return
	var who := str(_queue[_queue_i])
	var slot_index := _queue_i
	_queue_i += 1
	_publish_crawl_authority()
	if not _gs.characters.has(who) or _gs.is_downed(who):
		refused.emit()
		_enter_next()
		return
	# Walk this member to the mouth, crawl when the walk plan ends, and stagger the NEXT entry by
	# the in-tube spacing so the tube stays single-file.
	var sched = _gs.scheduler
	if sched == null:
		refused.emit()
		_enter_next()
		return
	var wait := 0.05
	if not _actor_at_mouth(who):
		if not bool(_gs.command_move_to_pos(who, _to_data(global_position))):
			# A failed approach is a visible refusal. A minimal-wait fallback here would convert an
			# unreachable or action-locked remote body into an in-tube crawler.
			refused.emit()
			_enter_next()
			return
	if _gs.has_method("get_plan_end_tick"):
		var end_tick: float = _gs.get_plan_end_tick(who)
		if end_tick >= 0.0:
			wait = maxf(wait, end_tick - sched.get_current_tick() + 0.05)
	_schedule_crawl_phase("begin", sched.get_current_tick() + wait, who, slot_index)

## Drop the receipt-owned body into the tube. The complete path/deadline/effect policy is published
## before GameState can emit movement/external-start or concealment-derived detection signals.
func _begin_crawl(who: String, slot_index: int, receipt_nonce := -1) -> bool:
	if _gs == null or not _gs.characters.has(who) or _gs.is_downed(who) \
			or not _actor_at_mouth(who) \
			or int(_activation_receipt.get("nonce", -1)) != receipt_nonce \
			or not _queue.has(who) or _crawl_traversals.has(who):
		refused.emit()
		return false
	var data_path: Array[Vector3] = [_gs.get_position(who)]
	for waypoint in _movement_waypoints():
		data_path.append(waypoint)
	var render_path: Array[Vector3] = [
		_gs.get_render_position(who)
			if _gs.has_method("get_render_position") else _gs.get_position(who)
	]
	for waypoint in _render_waypoints():
		render_path.append(waypoint)
	if data_path.size() < 2 or render_path.size() != data_path.size():
		refused.emit()
		return false
	var total := 0.0
	for i in range(1, data_path.size()):
		total += data_path[i - 1].distance_to(data_path[i])
	if total <= 0.01 or _gs.scheduler == null:
		refused.emit()
		return false
	var prior := 2.6
	var cd: Variant = _gs.characters.get(who)
	if cd is Dictionary and (cd as Dictionary).has("move_speed"):
		prior = float((cd as Dictionary)["move_speed"])
	var prior_concealment := int(_gs.get_character_concealment(who)) \
		if _gs.has_method("get_character_concealment") else 0
	var now := float(_gs.scheduler.get_current_tick())
	var duration := total / maxf(0.1, crawl_speed)
	var traversal_id := StringName(
		"crawl_tunnel/%s/%s/%d" % [_crawl_source_id(), who, receipt_nonce])
	_crawl_traversals[who] = {
		"phase": TRAVERSAL_PHASE_RESERVED,
		"traversal_id": String(traversal_id),
		"actor": who,
		"slot": slot_index,
		"receipt_nonce": receipt_nonce,
		"start_tick": now,
		"end_tick": now + duration,
		"data_path": _portable_path(data_path),
		"render_path": _portable_path(render_path),
		"prior_speed": prior,
		"prior_concealment": prior_concealment,
		"crawl_speed": crawl_speed,
		"conceal_rider": conceal_riders,
	}
	_restore_speeds[who] = prior
	_publish_crawl_authority()
	var accepted := bool(_gs.command_external_path_traversal(
		who, traversal_id, data_path, render_path, duration, &"locked")) \
		if _gs.has_method("command_external_path_traversal") else false
	if not accepted and _has_matching_crawl_traversal(who, String(traversal_id)):
		accepted = true
	if not accepted:
		_crawl_traversals.erase(who)
		_restore_speeds.erase(who)
		_publish_crawl_authority()
		refused.emit()
		return false
	if _crawl_traversals.has(who):
		var transaction: Dictionary = _crawl_traversals[who]
		transaction["phase"] = TRAVERSAL_PHASE_EFFECTS_PENDING
		_crawl_traversals[who] = transaction
		_publish_crawl_authority()
		_apply_crawl_entry_effects(who)
	return true


func _apply_crawl_entry_effects(who: String) -> void:
	if not _crawl_traversals.has(who) or _gs == null or not _gs.characters.has(who):
		return
	var transaction: Dictionary = _crawl_traversals[who]
	var phase := str(transaction.get("phase", ""))
	if phase not in [TRAVERSAL_PHASE_RESERVED, TRAVERSAL_PHASE_EFFECTS_PENDING]:
		return
	if bool(transaction.get("conceal_rider", false)) \
			and _gs.has_method("set_character_concealment"):
		_gs.set_character_concealment(who, _gs.CONCEAL_FULL)
	_gs.change_move_speed(who, float(transaction.get("crawl_speed", crawl_speed)))
	if not _crawl_traversals.has(who):
		return
	transaction = _crawl_traversals[who]
	transaction["phase"] = TRAVERSAL_PHASE_CARRYING
	_crawl_traversals[who] = transaction
	_publish_crawl_authority()
	crawl_started.emit(who)


func _finish_crawl_transaction(who: String, cancelled := false) -> void:
	if not _crawl_traversals.has(who) or _gs == null:
		return
	var transaction: Dictionary = _crawl_traversals[who]
	if str(transaction.get("phase", "")) != TRAVERSAL_PHASE_FINISHING:
		transaction["phase"] = TRAVERSAL_PHASE_FINISHING
		transaction["cancelled"] = cancelled
		_crawl_traversals[who] = transaction
		_publish_crawl_authority()
	if _gs.characters.has(who):
		_gs.change_move_speed(who, float(transaction.get("prior_speed", 2.6)))
		if _gs.has_method("set_character_concealment"):
			_gs.set_character_concealment(
				who, int(transaction.get("prior_concealment", _gs.CONCEAL_NONE)))
		if not cancelled and exit_level >= 0 and _gs.has_method("set_character_level"):
			_gs.set_character_level(who, exit_level)
	var slot_index := int(transaction.get("slot", -1))
	var has_arrival := slot_index >= 0 and slot_index < _queue_arrivals.size()
	var arrival: Vector3 = _queue_arrivals[slot_index] if has_arrival else Vector3.ZERO
	_crawl_traversals.erase(who)
	_restore_speeds.erase(who)
	if _queue.is_empty() and _crawl_traversals.is_empty():
		_queue_arrivals.clear()
	_retire_activation_if_idle()
	_publish_crawl_authority()
	if cancelled:
		refused.emit()
		return
	crawl_finished.emit(who)
	# Clear the exit mouth only after the canonical authored path reached its far endpoint.
	if has_arrival and _gs.characters.has(who) and not _gs.is_downed(who):
		_gs.command_move_to_pos(who, _to_data(arrival))

func _tube_dir() -> Vector3:
	var render_waypoints := _render_waypoints()
	if render_waypoints.is_empty():
		return Vector3.FORWARD
	var into := render_waypoints[0] - global_position
	into.y = 0.0
	return into.normalized() if into.length() > 0.01 else Vector3.FORWARD

func _exit_dir() -> Vector3:
	var render_waypoints := _render_waypoints()
	if render_waypoints.size() >= 2:
		var d := render_waypoints[render_waypoints.size() - 1] - render_waypoints[render_waypoints.size() - 2]
		d.y = 0.0
		if d.length() > 0.01:
			return d.normalized()
	return _tube_dir()

func _snap_walkable(pos: Vector3) -> Vector3:
	if _gs != null and _gs.grid != null and _gs.grid.has_method("nearest_walkable_world"):
		if _data_authored and _gs.coord_map != null:
			var data_pos: Vector3 = _gs.coord_map.to_data(pos)
			data_pos = _gs.grid.nearest_walkable_world(data_pos)
			return _gs.coord_map.to_world(data_pos)
		var snapped_pos: Vector3 = _gs.grid.nearest_walkable_world(pos)
		snapped_pos.y = pos.y
		return snapped_pos
	return pos

func _to_data(world_pos: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(world_pos)
	return world_pos

func _tag() -> String:
	return "crawl_tunnel_" + str(name)

func _entry_tag(who: String) -> String:
	return _tag() + "_enter_" + who


func _crawl_authority_key() -> String:
	var stable_id := data_id if data_id != "" else interactable_id
	if stable_id == "" and is_inside_tree():
		stable_id = str(get_path())
	return CRAWL_AUTHORITY_PREFIX + stable_id if stable_id != "" else ""


func _crawl_authority_payload() -> Dictionary:
	var arrivals: Array = []
	for arrival in _queue_arrivals:
		arrivals.append(_vec3_to_data(arrival as Vector3))
	return {
		"version": CRAWL_AUTHORITY_VERSION,
		"queue": _queue.duplicate(),
		"queue_arrivals": arrivals,
		"queue_index": _queue_i,
		"restore_speeds": _restore_speeds.duplicate(true),
		"phases": _crawl_phases.duplicate(true),
		"source_receipt_pending": _source_receipt_pending.duplicate(true),
		"activation_receipt": _activation_receipt.duplicate(true),
		"receipt_seq": _receipt_seq,
		"traversals": _crawl_traversals.duplicate(true),
	}


func _publish_crawl_authority() -> void:
	if _restoring_crawl_authority or _gs == null \
			or not _gs.has_method("set_world_state"):
		return
	var key := _crawl_authority_key()
	if key != "":
		_gs.set_world_state(key, _crawl_authority_payload())


func _crawl_phase_key(kind: String, who: String) -> String:
	return kind + (":" + who if who != "" else "")


func _crawl_phase_tag(kind: String, who: String) -> String:
	match kind:
		"begin": return _entry_tag(who)
		"next": return _tag() + "_next"
		"end": return _tag() + "_end_" + who
	return _tag() + "_" + kind + "_" + who


func _schedule_crawl_phase(
		kind: String, absolute_tick: float, who := "", slot_index := -1
	) -> void:
	if _gs == null or _gs.scheduler == null:
		return
	var sched = _gs.scheduler
	var key := _crawl_phase_key(kind, who)
	var tag := _crawl_phase_tag(kind, who)
	var deadline := maxf(float(sched.get_current_tick()) + 0.000001, absolute_tick)
	sched.cancel_tag(tag)
	_live_tags[tag] = true
	_crawl_phases[key] = {
		"kind": kind,
		"who": who,
		"slot": slot_index,
		"deadline": deadline,
		"receipt_nonce": int(_activation_receipt.get("nonce", -1)),
	}
	_publish_crawl_authority()
	sched.schedule_at(deadline, _run_crawl_phase.bind(key, deadline), tag)


func _run_crawl_phase(key: String, expected_deadline: float) -> void:
	if not _crawl_phases.has(key):
		return
	var phase: Dictionary = _crawl_phases[key]
	if not is_equal_approx(float(phase.get("deadline", -1.0)), expected_deadline):
		return
	_crawl_phases.erase(key)
	var kind := str(phase.get("kind", ""))
	var who := str(phase.get("who", ""))
	var slot := int(phase.get("slot", -1))
	var receipt_nonce := int(phase.get(
		"receipt_nonce", _activation_receipt.get("nonce", -1)))
	match kind:
		"begin":
			if _begin_crawl(who, slot, receipt_nonce) \
					and _gs != null and _gs.scheduler != null:
				_schedule_crawl_phase(
					"next",
					_gs.scheduler.get_current_tick() + ENTRY_SPACING / maxf(0.1, crawl_speed))
			else:
				_enter_next()
		"next":
			_enter_next()
		"end":
			_finish_crawl_transaction(who, false)
		_:
			_run_custom_crawl_phase(kind, who, slot)


## Subclasses with another committed phase (for example AlignmentCrossing's predicted window)
## override this hook while retaining the same serialized phase/deadline registry.
func _run_custom_crawl_phase(_kind: String, _who: String, _slot: int) -> void:
	_publish_crawl_authority()


## Rebuild the callback heap after a save replaces GameState. Absence is authoritative: loading a
## pre-entry snapshot clears a later queue instead of leaving the tunnel occupied forever.
func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	if _gs == null:
		return
	_restoring_crawl_authority = true
	if _gs.scheduler != null:
		for tag in _live_tags.keys():
			_gs.scheduler.cancel_tag(str(tag))
	_live_tags.clear()
	_queue.clear()
	_queue_arrivals.clear()
	_queue_i = 0
	_restore_speeds.clear()
	_crawl_phases.clear()
	_source_receipt_pending.clear()
	_activation_receipt.clear()
	_crawl_traversals.clear()
	var key := _crawl_authority_key()
	var saved: Variant = _gs.get_world_state(key, {}) if key != "" \
			and _gs.has_method("get_world_state") else {}
	if saved is Dictionary and int(saved.get("version", 0)) in [
			LEGACY_CRAWL_AUTHORITY_VERSION, CRAWL_AUTHORITY_VERSION]:
		var saved_version := int(saved.get("version", 0))
		for who_v in (saved.get("queue", []) as Array):
			_queue.append(str(who_v))
		for arrival_v in (saved.get("queue_arrivals", []) as Array):
			_queue_arrivals.append(_vec3_from_data(arrival_v))
		_queue_i = clampi(int(saved.get("queue_index", 0)), 0, _queue.size())
		for who_v in (saved.get("restore_speeds", {}) as Dictionary).keys():
			_restore_speeds[str(who_v)] = float(saved.restore_speeds[who_v])
		if saved_version >= CRAWL_AUTHORITY_VERSION:
			_source_receipt_pending = (
				saved.get("source_receipt_pending", {}) as Dictionary).duplicate(true)
			_activation_receipt = (
				saved.get("activation_receipt", {}) as Dictionary).duplicate(true)
			_receipt_seq = maxi(_receipt_seq, int(saved.get("receipt_seq", 0)))
			for actor_v in (saved.get("traversals", {}) as Dictionary).keys():
				var transaction_v: Variant = (saved.get("traversals", {}) as Dictionary)[actor_v]
				if transaction_v is Dictionary:
					_crawl_traversals[str(actor_v)] = (
						transaction_v as Dictionary).duplicate(true)
		var phases: Dictionary = saved.get("phases", {})
		for phase_key_v in phases.keys():
			var phase: Dictionary = phases[phase_key_v]
			_schedule_crawl_phase(
				str(phase.get("kind", "")),
				float(phase.get("deadline", 0.0)),
				str(phase.get("who", "")),
				int(phase.get("slot", -1)))
	_restoring_crawl_authority = false
	_connect_traversal_signals()
	_reconcile_crawl_authority()


func _reconcile_crawl_authority() -> void:
	if _restoring_crawl_authority or _gs == null:
		return
	if not _source_receipt_pending.is_empty():
		if _source_receipt_was_accepted():
			var receipt: Dictionary = _source_receipt_pending.duplicate(true)
			_source_receipt_pending.clear()
			if _activation_receipt.is_empty() and _receipt_matches_source(receipt):
				_accept_interaction_receipt(receipt)
			else:
				_publish_crawl_authority()
		else:
			# A save may be captured from publication of the provisional receipt itself, before
			# Interactable accepts. It owns no consequence and must not block the mouth after load.
			_source_receipt_pending.clear()
			_publish_crawl_authority()
	var actors := _crawl_traversals.keys()
	actors.sort()
	for actor_v in actors:
		var actor := str(actor_v)
		if not _crawl_traversals.has(actor):
			continue
		var transaction: Dictionary = _crawl_traversals[actor]
		var phase := str(transaction.get("phase", ""))
		var traversal_id := str(transaction.get("traversal_id", ""))
		var has_traversal := _has_matching_crawl_traversal(actor, traversal_id)
		match phase:
			TRAVERSAL_PHASE_RESERVED:
				if has_traversal:
					transaction["phase"] = TRAVERSAL_PHASE_EFFECTS_PENDING
					_crawl_traversals[actor] = transaction
					_publish_crawl_authority()
					_apply_crawl_entry_effects(actor)
				else:
					_resume_reserved_crawl(actor, transaction)
			TRAVERSAL_PHASE_EFFECTS_PENDING:
				if has_traversal:
					_apply_crawl_entry_effects(actor)
				else:
					_finish_crawl_transaction(actor, true)
			TRAVERSAL_PHASE_CARRYING:
				if not has_traversal:
					_reconcile_finished_or_cancelled_crawl(actor, transaction)
			TRAVERSAL_PHASE_FINISHING:
				_finish_crawl_transaction(
					actor, bool(transaction.get("cancelled", false)))


func _source_receipt_was_accepted() -> bool:
	return _receipt_was_accepted(_source_receipt_pending)


func _receipt_was_accepted(receipt: Dictionary) -> bool:
	if not _uses_bound_source_authority():
		return bool(receipt.get("local_accepted", false))
	var spec: Dictionary = _gs.get_interactable(data_id)
	return int(spec.get("trigger_count", 0)) \
			== int(receipt.get("expected_trigger_count", -1)) \
		and String(spec.get("last_trigger_character", "")) \
			== str(receipt.get("actor", ""))


func _resume_reserved_crawl(actor: String, transaction: Dictionary) -> void:
	if not _gs.characters.has(actor) or _gs.scheduler == null:
		_finish_crawl_transaction(actor, true)
		return
	var now := float(_gs.scheduler.get_current_tick())
	var end_tick := float(transaction.get("end_tick", now))
	var data_path := _path_from_portable(transaction.get("data_path", []))
	var render_path := _path_from_portable(transaction.get("render_path", []))
	if data_path.size() < 2 or render_path.size() != data_path.size() \
			or now >= end_tick:
		_reconcile_finished_or_cancelled_crawl(actor, transaction)
		return
	# A reservation without a GameState traversal can only be a save from the authority publication
	# immediately before command_external_path_traversal. Its body is still at path[0].
	if not _gs.get_position(actor).is_equal_approx(data_path[0]):
		_finish_crawl_transaction(actor, true)
		return
	var traversal_id := StringName(str(transaction.get("traversal_id", "")))
	var accepted := bool(_gs.command_external_path_traversal(
		actor,
		traversal_id,
		data_path,
		render_path,
		maxf(0.000001, end_tick - now),
		&"locked"))
	if not accepted and not _has_matching_crawl_traversal(actor, String(traversal_id)):
		_finish_crawl_transaction(actor, true)
		return
	if _crawl_traversals.has(actor):
		transaction = _crawl_traversals[actor]
		transaction["phase"] = TRAVERSAL_PHASE_EFFECTS_PENDING
		_crawl_traversals[actor] = transaction
		_publish_crawl_authority()
		_apply_crawl_entry_effects(actor)


func _reconcile_finished_or_cancelled_crawl(actor: String, transaction: Dictionary) -> void:
	var data_path := _path_from_portable(transaction.get("data_path", []))
	var destination: Vector3 = data_path[data_path.size() - 1] \
		if not data_path.is_empty() else Vector3.INF
	var arrived: bool = _gs.characters.has(actor) and destination.is_finite() \
		and _gs.get_position(actor).is_equal_approx(destination) \
		and (_gs.scheduler == null or float(_gs.scheduler.get_current_tick()) \
			>= float(transaction.get("end_tick", INF)) - 0.000001)
	_finish_crawl_transaction(actor, not arrived)


func _path_from_portable(raw: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not raw is Array:
		return out
	for value in raw as Array:
		if not value is Array or (value as Array).size() < 3:
			return []
		var point := _vec3_from_data(value)
		if not point.is_finite():
			return []
		out.append(point)
	return out


static func _vec3_to_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _vec3_from_data(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _exit_tree() -> void:
	if _gs != null and _gs.scheduler != null:
		for tag in _live_tags.keys():
			_gs.scheduler.cancel_tag(tag)
	_live_tags.clear()
	_disconnect_traversal_signals()
