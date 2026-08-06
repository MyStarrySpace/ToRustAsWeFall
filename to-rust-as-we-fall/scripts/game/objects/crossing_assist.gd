class_name CrossingAssist
extends Interactable

## The PERFECT-LAUNCH read — the Balancing Basin's RESOURCE branch (docs/BALANCING_BASIN.md).
## An authored console at a crossing lip: the required character logs the read, pays STAMINA
## from the closed bar, and the selected group is HELD at the lip and LAUNCHED on the exact
## commit of the target water state — the full window, no manual timing. Scoped to the NEXT
## window only (perfection without foresight); a cooldown prices repeat reads; a read that
## cannot pay simply fails (no charge, no arm). Extracted from the wash relay FlowTerminal
## grammar (hold-at-lip, depart-on-the-beat): the hold and the launch are ordinary logged
## movement commands, so an assisted crossing replays exactly.

signal read_logged(launch_tick: float)
signal read_refused(reason: String)
signal staging_started()
signal crossing_launched()

const LAUNCH_SETTLE_DELAY := 0.05   # launch just after the commit so the maps have flipped
const STAGING_POLL_INTERVAL := 0.1
const STAGING_ARRIVAL_EPSILON := 0.2
const PHASE_IDLE := "idle"
const PHASE_STAGING := "staging"
const PHASE_ARMED := "armed"

var _gs = null
var _basin_tag := "basin"
var _basin_resolver := Callable()
var _group_provider := Callable()
var _party_provider := Callable()
var _extra_pre_trigger_validator := Callable()
var _lip := Vector3.ZERO
var _dest := Vector3.ZERO
var _target_state := 1
var _stamina_cost := 25.0
var _cooldown := 10.0
var _tag := "crossing_assist"
var _cooldown_until := -1.0
var _armed_launch_tick := -1.0
var _armed_ids: Array = []
var _staging_destinations: Array[Vector3] = []
var _payer_id := ""
var _phase := PHASE_IDLE
var _screen_mat: StandardMaterial3D = null
var _prepared_read: Dictionary = {}

## Configure BEFORE adding to the tree. All policy is data: the lip (hold point), the dest,
## the basin (by tag), the target state, and the two prices (stamina + cooldown).
func configure(gs, spec: Dictionary) -> void:
	_gs = gs
	position = spec.get("pos", Vector3.ZERO)
	_lip = spec.get("lip", position)
	_dest = spec.get("dest", position)
	_basin_tag = str(spec.get("basin_tag", "basin"))
	_target_state = int(spec.get("target_state", 1))
	_stamina_cost = maxf(0.0, float(spec.get("stamina_cost", 25.0)))
	_cooldown = maxf(0.0, float(spec.get("cooldown", 10.0)))
	_tag = str(spec.get("tag", "assist_%s" % _basin_tag))
	required_character = str(spec.get("required_character", "aster"))
	interaction_radius = float(spec.get("radius", 1.4))
	description = str(spec.get("desc", "Log the rota and cross on the beat"))
	tutorial_label = str(spec.get("label", "LOG THE ROTA"))
	interactable_type = InteractableType.INSPECTION
	# The console's group contract is trigger authority, not a side effect of the
	# `interacted` signal. Rejecting here gives the exact clicked object a red
	# result receipt before any Rally, stamina, or cooldown mutation can occur.
	super.set_pre_trigger_validator(_validate_read_trigger)
	if not interacted.is_connected(_on_read):
		interacted.connect(_on_read)

func set_basin_resolver(resolver: Callable) -> void:
	_basin_resolver = resolver

func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

## The complete roster presented as playable by the current host. Collective
## CrossingAssist actions may use exactly this roster or no roster at all.
func set_party_provider(provider: Callable) -> void:
	_party_provider = provider

## Preserve the kit-owned atomic group gate if a scenario adds another guard.
func set_pre_trigger_validator(validator: Callable) -> void:
	_extra_pre_trigger_validator = validator
	super.set_pre_trigger_validator(_validate_read_trigger)

## CrossingAssist owns the final semantic result: `interacted` only means the
## generic trigger boundary accepted, while staging may still atomically fail.
## Disconnect the base auto-success bridge and publish one exact green/red pulse
## after the assist itself has accepted or refused the transaction.
func set_outline_target(target) -> void:
	super.set_outline_target(target)
	var success_bridge := Callable(self, "_on_visual_interaction_succeeded")
	var rejection_bridge := Callable(self, "_on_visual_interaction_rejected")
	if interacted.is_connected(success_bridge):
		interacted.disconnect(success_bridge)
	if interaction_rejected.is_connected(rejection_bridge):
		interaction_rejected.disconnect(rejection_bridge)

func is_read_armed() -> bool:
	return _phase == PHASE_ARMED and _armed_launch_tick >= 0.0

func is_staging() -> bool:
	return _phase == PHASE_STAGING

func get_read_phase() -> String:
	return _phase

func get_staging_destinations() -> Array[Vector3]:
	return _staging_destinations.duplicate()

func cooldown_remaining() -> float:
	var sched = _scheduler_ref()
	if sched == null or _cooldown_until < 0.0:
		return 0.0
	return maxf(0.0, _cooldown_until - float(sched.get_current_tick()))

func reset_assist() -> void:
	var sched = _scheduler_ref()
	if sched != null:
		sched.cancel_tag(_tag + "_launch")
		sched.cancel_tag(_tag + "_staging")
	_cooldown_until = -1.0
	_armed_launch_tick = -1.0
	_armed_ids.clear()
	_staging_destinations.clear()
	_payer_id = ""
	_phase = PHASE_IDLE
	_prepared_read.clear()
	_set_screen_phase(PHASE_IDLE)

func _ready() -> void:
	super._ready()
	_build_visual()
	call_deferred("_wire_console_outline")

func _on_read() -> void:
	var prepared := _prepared_read
	_prepared_read = {}
	if prepared.is_empty() or _gs == null:
		_reject_trigger("no basin")
		return
	var sched: Variant = prepared.get("scheduler")
	var now := float(prepared.get("now", -1.0))
	var actor := str(prepared.get("actor", ""))
	var group_ids: Array = (prepared.get("group_ids", []) as Array).duplicate()
	var staging_destinations: Array[Vector3] = []
	for destination_v in prepared.get("staging_destinations", []) as Array:
		if destination_v is Vector3:
			staging_destinations.append(destination_v as Vector3)
	var staging_route_constraint := (prepared.get(
		"staging_route_constraint", {}) as Dictionary).duplicate(true)
	if sched == null or actor == "" or group_ids.is_empty() \
			or group_ids.size() != staging_destinations.size() \
			or staging_route_constraint.is_empty():
		_reject_trigger("no basin")
		return
	# The lip move is one transaction. Only a production Rally accepted for the exact selected
	# full presented roster may debit stamina or start cooldown; route/busy refusal is visible and free. The
	# mechanism's permanent-hold mask constrains starts, path cells, waits, edges, and diagonal
	# support cells. A balcony-to-lip route that exists only across MID floats therefore refuses.
	var staged_count := int(_gs.command_rally_members(
		group_ids, _lip, "", staging_route_constraint))
	if staged_count != group_ids.size():
		_reject_trigger("unsafe staging route")
		return
	_gs.adjust_stat(actor, "stamina", -_stamina_cost)
	_cooldown_until = now + _cooldown
	_armed_ids = group_ids
	_staging_destinations = staging_destinations
	_payer_id = actor
	_armed_launch_tick = -1.0
	_phase = PHASE_STAGING
	_set_screen_phase(PHASE_STAGING)
	play_interaction_result(true)
	staging_started.emit()
	sched.cancel_tag(_tag + "_staging")
	sched.schedule_after(STAGING_POLL_INTERVAL, _poll_staging, _tag + "_staging")


## Read-only trigger preflight. Every collective prerequisite is checked before
## Interactable emits `interacted`, so an incomplete selection cannot debit a
## stat, begin a move, write a Rally event, or masquerade as target success.
func _validate_read_trigger(source: Node, trigger_actor: String) -> bool:
	_prepared_read.clear()
	if source != self:
		return _reject_trigger("no basin")
	if _extra_pre_trigger_validator.is_valid() \
			and not bool(_extra_pre_trigger_validator.call(source, trigger_actor)):
		return _reject_trigger("interaction unavailable")
	var sched = _scheduler_ref()
	var basin: Variant = _resolve_basin()
	if sched == null or basin == null or _gs == null:
		return _reject_trigger("no basin")
	var now := float(sched.get_current_tick())
	if required_character != "" and trigger_actor != "" \
			and trigger_actor != required_character:
		return _reject_trigger("wrong character")
	if _phase == PHASE_STAGING:
		return _reject_trigger("already staging")
	if _phase == PHASE_ARMED:
		return _reject_trigger("already armed")
	if _cooldown_until > now:
		return _reject_trigger("cooldown")
	var actor := required_character if required_character != "" else trigger_actor
	var selected_ids := _selected_group_ids()
	var party_ids := _presented_party_ids()
	if party_ids.is_empty() or not _same_roster(selected_ids, party_ids):
		return _reject_trigger("full party not selected")
	# The presented roster order is canonical for formation slots and receipts;
	# selection order is not allowed to change the collective verb's membership.
	var group_ids := party_ids
	# The assist is a timed crossing, not a rescue from the flooded floor. Charging
	# while one member is still below makes the advertised launch silently strand
	# them at the next rise. Require the visible prerequisite first.
	if not _group_is_staged_on_lip_level(group_ids):
		return _reject_trigger("group not staged")
	for group_id_v in group_ids:
		if not bool(_gs.can_accept_move_command(str(group_id_v))):
			return _reject_trigger("route or busy")
	if float(_gs.get_stat(actor, "stamina")) < _stamina_cost:
		return _reject_trigger("stamina")
	# Prove a target state exists before moving anyone. Its launch tick is chosen
	# only after the full roster physically reaches the lip.
	if float(basin.call("next_state_tick", _target_state)) < 0.0:
		return _reject_trigger("no window")
	var staging_destinations: Array[Vector3] = _gs.compute_rally_destinations(
		group_ids, _lip)
	if not _staging_destinations_are_stable(
			basin, group_ids, staging_destinations):
		return _reject_trigger("unsafe staging route")
	var staging_route_constraint := _stable_hold_route_constraint(basin)
	if staging_route_constraint.is_empty():
		return _reject_trigger("unsafe staging route")
	_prepared_read = {
		"scheduler": sched,
		"now": now,
		"actor": actor,
		"group_ids": group_ids.duplicate(),
		"staging_destinations": staging_destinations.duplicate(),
		"staging_route_constraint": staging_route_constraint.duplicate(true),
	}
	return true


func _reject_trigger(reason: String) -> bool:
	_prepared_read.clear()
	read_refused.emit(reason)
	play_interaction_result(false)
	return false

func _poll_staging() -> void:
	if _phase != PHASE_STAGING:
		return
	var sched = _scheduler_ref()
	if sched == null or _gs == null:
		_abort_staging("no basin")
		return
	for member_index in range(_armed_ids.size()):
		var id := str(_armed_ids[member_index])
		if not _gs.characters.has(id) or _gs.is_downed(id) \
				or _gs.is_external_traversal_active(id):
			_abort_staging("group unavailable")
			return
		var destination: Vector3 = _staging_destinations[member_index]
		var arrived: bool = not bool(_gs.is_moving(id)) \
			and _gs.get_position(id).distance_to(destination) <= STAGING_ARRIVAL_EPSILON \
			and int(_gs.get_character_level(id)) == _gs.grid.level_for_y(destination.y)
		if arrived:
			continue
		# A member that is neither travelling nor at their exact staging slot means the accepted
		# Rally was interrupted. Do not keep a paid invisible promise alive indefinitely.
		if not _gs.is_moving(id):
			_abort_staging("staging interrupted")
			return
		sched.schedule_after(STAGING_POLL_INTERVAL, _poll_staging, _tag + "_staging")
		return
	_arm_next_window()

func _arm_next_window() -> void:
	var sched = _scheduler_ref()
	var basin: Variant = _resolve_basin()
	if sched == null or basin == null:
		_abort_staging("no basin")
		return
	var launch_tick := float(basin.call("next_state_tick", _target_state))
	if launch_tick < 0.0:
		_abort_staging("no window")
		return
	_armed_launch_tick = launch_tick
	_phase = PHASE_ARMED
	sched.cancel_tag(_tag + "_staging")
	sched.cancel_tag(_tag + "_launch")
	sched.schedule_after(maxf(0.0, launch_tick - float(sched.get_current_tick())) \
		+ LAUNCH_SETTLE_DELAY, _launch, _tag + "_launch")
	_set_screen_phase(PHASE_ARMED)
	read_logged.emit(launch_tick)

func _abort_staging(reason: String) -> void:
	var sched = _scheduler_ref()
	if sched != null:
		sched.cancel_tag(_tag + "_staging")
		sched.cancel_tag(_tag + "_launch")
	# The console failed to buy a launch after accepting the staging move. Return the closed-bar
	# price and cooldown in the same visible refusal transition.
	if _gs != null and _payer_id != "" and _gs.characters.has(_payer_id):
		_gs.adjust_stat(_payer_id, "stamina", _stamina_cost)
	_cooldown_until = -1.0
	_armed_launch_tick = -1.0
	_armed_ids.clear()
	_staging_destinations.clear()
	_payer_id = ""
	_phase = PHASE_IDLE
	_set_screen_phase(PHASE_IDLE)
	read_refused.emit(reason)

func _launch() -> void:
	_armed_launch_tick = -1.0
	_phase = PHASE_IDLE
	_set_screen_phase(PHASE_IDLE)
	if _gs == null:
		return
	var ids := _armed_ids.duplicate()
	_armed_ids.clear()
	_staging_destinations.clear()
	_payer_id = ""
	# Launch the roster that bought the assist, never a silently filtered subset. A member that
	# became busy/downed makes the whole production Rally refuse with visible feedback.
	var launched_count := int(_gs.command_rally_members(ids, _dest))
	if launched_count != ids.size():
		read_refused.emit("launch route or busy")
		return
	crossing_launched.emit()

func _selected_group_ids() -> Array:
	var ids: Array = []
	if _group_provider.is_valid():
		var provided: Variant = _group_provider.call()
		if provided is Array:
			ids = (provided as Array).duplicate()
	return _unique_ids(ids)


func _presented_party_ids() -> Array:
	var ids: Array = []
	if _party_provider.is_valid():
		var provided: Variant = _party_provider.call()
		if provided is Array:
			ids = (provided as Array).duplicate()
	elif _gs != null and _gs.has_method("get_party"):
		ids = _gs.get_party()
	return _unique_ids(ids)


func _unique_ids(ids: Array) -> Array:
	var unique_ids: Array = []
	for raw_id in ids:
		var id := str(raw_id)
		if id != "" and not unique_ids.has(id):
			unique_ids.append(id)
	return unique_ids


func _same_roster(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for id_v in first:
		if not second.has(str(id_v)):
			return false
	return true

func _group_is_staged_on_lip_level(ids: Array) -> bool:
	if _gs == null or _gs.grid == null or ids.is_empty():
		return false
	var lip_level: int = _gs.grid.level_for_y(_lip.y)
	for id_v in ids:
		var id := str(id_v)
		if not _gs.characters.has(id) or _gs.is_downed(id) \
				or int(_gs.get_character_level(id)) != lip_level:
			return false
	return true

func _staging_destinations_are_stable(
		basin: Variant, ids: Array, destinations: Array[Vector3]) -> bool:
	if _gs == null or _gs.grid == null or ids.is_empty() or ids.size() != destinations.size():
		return false
	var lip_level: int = _gs.grid.level_for_y(_lip.y)
	var occupied_cells: Dictionary = {}
	for destination in destinations:
		var level: int = _gs.grid.level_for_y(destination.y)
		var cell: Vector2i = _gs.grid.world_to_grid(destination)
		if level != lip_level or occupied_cells.has(cell):
			return false
		occupied_cells[cell] = true
		if basin.has_method("is_stable_hold_position") \
				and not bool(basin.call("is_stable_hold_position", destination, level)):
			return false
	return true


## Build the narrow serializable allow-list consumed by the generic Rally planner. BasinWater owns
## the permanence predicate; CrossingAssist merely projects it over the lip-level graph footprint.
func _stable_hold_route_constraint(basin: Variant) -> Dictionary:
	if _gs == null or _gs.grid == null or basin == null \
			or not basin.has_method("is_stable_hold_position"):
		return {}
	var lip_level: int = _gs.grid.level_for_y(_lip.y)
	var cells: Array = []
	for z in range(_gs.grid.height):
		for x in range(_gs.grid.width):
			var cell := Vector2i(x, z)
			var position: Vector3 = _gs.grid.grid_to_world(cell, lip_level)
			if bool(basin.call("is_stable_hold_position", position, lip_level)):
				cells.append([x, z])
	if cells.is_empty():
		return {}
	return {
		"schema": GameState.RALLY_ALLOWED_CELLS_SCHEMA,
		"level": lip_level,
		"cells": cells,
	}

func _resolve_basin() -> Variant:
	if not _basin_resolver.is_valid():
		return null
	return _basin_resolver.call(_basin_tag)

func _scheduler_ref():
	if _gs != null and _gs.get("scheduler") != null:
		return _gs.get("scheduler")
	return null

# --- visuals (cosmetic; a pedestal console whose screen lights while a read is armed) ---

var _pedestal: MeshInstance3D = null
var _screen: MeshInstance3D = null

func _build_visual() -> void:
	if _pedestal != null:
		return
	_pedestal = MeshInstance3D.new()
	_pedestal.name = "ConsolePedestal"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 1.0, 0.4)
	_pedestal.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.2)
	_pedestal.material_override = pmat
	_pedestal.position = Vector3(0.0, 0.5, 0.0)
	add_child(_pedestal)
	_screen = MeshInstance3D.new()
	_screen.name = "ConsoleScreen"
	var sm := BoxMesh.new()
	sm.size = Vector3(0.42, 0.3, 0.06)
	_screen.mesh = sm
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.08, 0.12, 0.1)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.36, 0.91, 0.5)
	_screen_mat.emission_energy_multiplier = 0.4
	_screen.material_override = _screen_mat
	_screen.position = Vector3(0.0, 1.1, -0.14)
	_screen.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	add_child(_screen)

func _set_screen_phase(phase: String) -> void:
	if _screen_mat == null:
		return
	match phase:
		PHASE_STAGING:
			_screen_mat.emission = Color(1.0, 0.62, 0.14)
			_screen_mat.emission_energy_multiplier = 1.25
		PHASE_ARMED:
			_screen_mat.emission = Color(0.36, 0.91, 0.5)
			_screen_mat.emission_energy_multiplier = 1.6
		_:
			_screen_mat.emission = Color(0.36, 0.91, 0.5)
			_screen_mat.emission_energy_multiplier = 0.4

func _wire_console_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _pedestal == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_pedestal, _screen],
		"crossing_assist", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

func _exit_tree() -> void:
	var sched = _scheduler_ref()
	if sched != null:
		sched.cancel_tag(_tag + "_launch")
		sched.cancel_tag(_tag + "_staging")
