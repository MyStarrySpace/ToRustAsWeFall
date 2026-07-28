extends SceneTree

## Focused exploit regression for the Elevator bridge collapse. Covers absence rollback, the armed
## warning, exact in-flight party progress, endpoint-only topology, landed recovery, fresh presenters,
## and idempotent restore without replaying gameplay effects.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := await _spawn_elevator()
	_stage_intact_bridge(source)
	var absence_snapshot := _json_round_trip(source.build_save_snapshot())
	check(_bridge_record(absence_snapshot).is_empty(),
		"a pre-collapse snapshot has no invented bridge future")

	# Discard a future that has already entered the fall. Absence must restore the intact upper
	# topology and cannot retain either rider or a scene callback from that discarded future.
	source._start_bridge_collapse()
	source.headless_advance(source.BRIDGE_COLLAPSE_ARM_SECONDS + 0.05, 0.01)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_FALLING,
		"the discarded future reaches the authoritative falling phase")
	source.apply_save_snapshot(absence_snapshot)
	check(source._bridge_collapse_phase() == ""
			and not source._game_state.is_external_traversal_active("aster")
			and not source._game_state.is_external_traversal_active("peris"),
		"absence rollback retracts the phase and both saved riders")
	check(_party_level_is(source, source.LEVEL_UPPER) and _bridge_topology_intact(source),
		"absence rollback restores upper party placement and intact topology")

	# Save during the warning phase. The exact absolute deadline must survive both a future rollback
	# and a repeated restore hook without accumulating another callback.
	source._start_bridge_collapse()
	source.headless_advance(0.25, 0.01)
	var armed_snapshot := _json_round_trip(source.build_save_snapshot())
	var armed_record := _bridge_record(armed_snapshot)
	var armed_deadline := float(armed_record.get("phase_deadline", -1.0))
	check(str(armed_record.get("phase", "")) == source.BRIDGE_COLLAPSE_PHASE_ARMED,
		"warning midpoint serializes an explicit armed phase")
	source.headless_advance(2.0, 0.02)
	source.apply_save_snapshot(armed_snapshot)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_ARMED
			and _party_level_is(source, source.LEVEL_UPPER)
			and _bridge_topology_intact(source),
		"same-presenter rollback restores the warning instead of granting a fall/landing")
	var pending_after_first_armed_restore: int = source._scheduler.pending_count()
	var events_after_first_armed_restore := _event_count(source)
	source.on_game_state_snapshot_restored()
	check(source._scheduler.pending_count() == pending_after_first_armed_restore,
		"repeating armed restore keeps exactly one derived callback")
	check(_event_count(source) == events_after_first_armed_restore,
		"repeating armed restore emits no gameplay event")
	var armed_remaining := armed_deadline - float(source._scheduler.get_current_tick())
	source.headless_advance(maxf(0.0, armed_remaining - 0.01), 0.01)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_ARMED,
		"warning cannot finish before its saved absolute deadline")
	source.headless_advance(0.02, 0.01)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_FALLING
			and source._game_state.is_external_traversal_active("aster")
			and source._game_state.is_external_traversal_active("peris"),
		"the warning begins both authoritative riders at its deadline")

	# Save partway through the physical drop. GameState owns exact rider progress; the sequence record
	# owns the matching landing deadline and still-intact gameplay topology.
	source.headless_advance(0.37, 0.01)
	var source_aster_state: Dictionary = source._game_state.get_external_traversal_state("aster")
	var source_peris_state: Dictionary = source._game_state.get_external_traversal_state("peris")
	var falling_snapshot := _json_round_trip(source.build_save_snapshot())
	var falling_record := _bridge_record(falling_snapshot)
	var falling_deadline := float(falling_record.get("phase_deadline", -1.0))
	check(str(falling_record.get("phase", "")) == source.BRIDGE_COLLAPSE_PHASE_FALLING,
		"fall midpoint serializes the scene phase and deadline")
	check(_bridge_topology_intact(source),
		"starting cosmetic debris does not prematurely remove bridge topology")

	source.headless_advance(2.0, 0.02)
	source.apply_save_snapshot(falling_snapshot)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_FALLING
			and _bridge_topology_intact(source),
		"same-presenter rollback returns to an in-flight fall with intact pre-endpoint topology")
	check(_same_traversal_readback(
		source._game_state.get_external_traversal_state("aster"), source_aster_state)
			and _same_traversal_readback(
				source._game_state.get_external_traversal_state("peris"), source_peris_state),
		"same-presenter rollback restores exact rider progress and render position")
	var restored_aster_render: Vector3 = source._game_state.get_external_traversal_state(
		"aster").get("render_position", Vector3.INF)
	check(source._aster_node.global_position.is_equal_approx(restored_aster_render),
		"the scene body attaches to GameState's exact saved in-flight position")
	var pending_after_first_fall_restore: int = source._scheduler.pending_count()
	var events_after_first_fall_restore := _event_count(source)
	source.on_game_state_snapshot_restored()
	source.on_game_state_snapshot_restored()
	check(source._scheduler.pending_count() == pending_after_first_fall_restore,
		"repeating fall restore does not duplicate landing callbacks")
	check(_event_count(source) == events_after_first_fall_restore,
		"fall restore is observational and emits no traversal/event-log command")

	var fall_remaining := falling_deadline - float(source._scheduler.get_current_tick())
	source.headless_advance(maxf(0.0, fall_remaining - 0.01), 0.01)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_FALLING
			and _party_level_is(source, source.LEVEL_UPPER)
			and _bridge_topology_intact(source),
		"one tick before landing, riders remain in flight and bridge topology remains intact")
	source.headless_advance(0.02, 0.01)
	check(source._bridge_collapse_phase() == source.BRIDGE_COLLAPSE_PHASE_LANDED
			and _party_level_is(source, source.LEVEL_LOWER),
		"the exact endpoint commits both lower-level riders and the landed phase")
	check(not _bridge_topology_intact(source),
		"bridge collision and upper path topology retire only at the physical endpoint")
	var landed_snapshot := _json_round_trip(source.build_save_snapshot())
	var landed_record := _bridge_record(landed_snapshot)
	var recovery_deadline := float(landed_record.get("phase_deadline", -1.0))

	# A fresh process/presenter must attach to the same mid-fall record, including exact progress.
	var fresh_fall := await _spawn_elevator()
	fresh_fall.apply_save_snapshot(falling_snapshot)
	check(fresh_fall._bridge_collapse_phase() == fresh_fall.BRIDGE_COLLAPSE_PHASE_FALLING
			and fresh_fall._game_state.is_external_traversal_active("aster")
			and _bridge_topology_intact(fresh_fall),
		"fresh presenter attaches to the saved falling phase without completing it")
	check(_same_traversal_readback(
		fresh_fall._game_state.get_external_traversal_state("aster"), source_aster_state),
		"fresh presenter restores the same exact in-flight rider progress")
	var fresh_fall_remaining := falling_deadline - float(fresh_fall._scheduler.get_current_tick())
	fresh_fall.headless_advance(maxf(0.0, fresh_fall_remaining - 0.01), 0.01)
	check(fresh_fall._bridge_collapse_phase() == fresh_fall.BRIDGE_COLLAPSE_PHASE_FALLING,
		"fresh presenter cannot land before the saved deadline")
	fresh_fall.headless_advance(0.02, 0.01)
	check(fresh_fall._bridge_collapse_phase() == fresh_fall.BRIDGE_COLLAPSE_PHASE_LANDED
			and _party_level_is(fresh_fall, fresh_fall.LEVEL_LOWER)
			and not _bridge_topology_intact(fresh_fall),
		"fresh presenter commits the same endpoint once at the same deadline")
	await _destroy_elevator(fresh_fall)

	# Landed recovery is itself a saved phase. Loading it cannot skip directly to Fallen, and calling
	# the attachment hook twice cannot duplicate the transition or re-run landing effects.
	var fresh_landed := await _spawn_elevator()
	fresh_landed.apply_save_snapshot(landed_snapshot)
	check(fresh_landed._bridge_collapse_phase() == fresh_landed.BRIDGE_COLLAPSE_PHASE_LANDED
			and str(fresh_landed._current_step) == "bridge_collapse"
			and _party_level_is(fresh_landed, fresh_landed.LEVEL_LOWER)
			and not _bridge_topology_intact(fresh_landed),
		"fresh landed presenter restores committed topology without skipping recovery")
	var landed_pending: int = fresh_landed._scheduler.pending_count()
	var landed_events := _event_count(fresh_landed)
	fresh_landed.on_game_state_snapshot_restored()
	fresh_landed.on_game_state_snapshot_restored()
	check(fresh_landed._scheduler.pending_count() == landed_pending,
		"repeating landed restore retains one recovery callback")
	check(_event_count(fresh_landed) == landed_events,
		"repeating landed restore does not replay landing effects")
	var recovery_remaining := recovery_deadline - float(fresh_landed._scheduler.get_current_tick())
	fresh_landed.headless_advance(maxf(0.0, recovery_remaining - 0.01), 0.01)
	check(str(fresh_landed._current_step) == "bridge_collapse",
		"landed recovery cannot complete before its saved deadline")
	fresh_landed.headless_advance(0.02, 0.01)
	check(str(fresh_landed._current_step) == "fallen"
			and fresh_landed._bridge_collapse_phase() == fresh_landed.BRIDGE_COLLAPSE_PHASE_COMPLETE,
		"recovery advances once and records the completed collapse phase at its deadline")
	await _destroy_elevator(fresh_landed)

	# Fresh absence is construction truth too, not merely a same-instance cleanup trick.
	var fresh_absent := await _spawn_elevator()
	fresh_absent.apply_save_snapshot(absence_snapshot)
	check(fresh_absent._bridge_collapse_phase() == ""
			and _party_level_is(fresh_absent, fresh_absent.LEVEL_UPPER)
			and _bridge_topology_intact(fresh_absent),
		"fresh absence restore builds only the intact pre-collapse world")
	await _destroy_elevator(fresh_absent)

	await _destroy_elevator(source)
	print("ELEVATOR BRIDGE COLLAPSE SAVE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_elevator() -> Node:
	var elevator := ElevatorScene.instantiate()
	elevator.suppress_scene_change = true
	root.add_child(elevator)
	for _frame in range(8):
		await process_frame
	_clear_sequence_runtime(elevator)
	return elevator


func _stage_intact_bridge(elevator: Node) -> void:
	elevator._load_chunk("bridge")
	elevator._load_chunk("below")
	elevator._unlock_upper_exit_footprint()
	for character_id in ["aster", "peris"]:
		elevator._game_state.command_stop(character_id)
		elevator._game_state.set_character_level(character_id, elevator.LEVEL_UPPER)
		var z := -0.35 if character_id == "aster" else 0.35
		elevator._game_state.snap_character_to(
			character_id, Vector3(elevator.BRIDGE_COLLAPSE_X + 1.0, 0.0, z))
		var node: Node3D = elevator.get_game_state_character_node(character_id)
		if node != null:
			node.global_position = Vector3(
				elevator.BRIDGE_COLLAPSE_X + 1.0, 0.5, z)
	elevator._current_step = "bridge"
	elevator._bridge_collapse_authority.clear()
	elevator._commit_bridge_collapse_topology(false)
	elevator._publish_elevator_runtime_authority()


func _clear_sequence_runtime(elevator: Node) -> void:
	elevator._scheduler.clear()
	elevator._scheduler.resume()
	if elevator._dialogue != null and elevator._dialogue.has_method("clear"):
		elevator._dialogue.clear()
	if elevator._tutorial_prompt != null:
		elevator._tutorial_prompt.hide_prompt()


func _bridge_record(snapshot: Dictionary) -> Dictionary:
	var game_state: Dictionary = snapshot.get("game_state", {}) as Dictionary
	var world_state: Dictionary = game_state.get("world_state", {}) as Dictionary
	var runtime: Dictionary = world_state.get(
		"runtime:elevator_sequence:hazards_and_wreckage", {}) as Dictionary
	return (runtime.get("bridge_collapse", {}) as Dictionary).duplicate(true)


func _party_level_is(elevator: Node, level: int) -> bool:
	return elevator._game_state.get_character_level("aster") == level \
		and elevator._game_state.get_character_level("peris") == level


func _bridge_topology_intact(elevator: Node) -> bool:
	var chunk := elevator._chunks.get("bridge") as Node3D
	if chunk == null:
		return false
	var floor := chunk.find_child("BridgeFloor", false, false) as Node3D
	if floor == null:
		return false
	for collision_name in [
			"BridgeDeckCollision", "BridgeRailCollisionL", "BridgeRailCollisionR"]:
		var body := floor.get_node_or_null(collision_name) as CollisionObject3D
		if body == null or body.collision_layer != 1:
			return false
	var cell: Vector2i = elevator._grid.world_to_grid(
		Vector3(elevator.BRIDGE_COLLAPSE_X, 0.0, 0.0))
	return elevator._grid.is_cell_allowed_on_level(cell, elevator.LEVEL_UPPER)


func _same_traversal_readback(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return is_equal_approx(float(a.get("progress", -1.0)), float(b.get("progress", -2.0))) \
		and (a.get("data_position", Vector3.INF) as Vector3).is_equal_approx(
			b.get("data_position", Vector3(-INF, -INF, -INF)) as Vector3) \
		and (a.get("render_position", Vector3.INF) as Vector3).is_equal_approx(
			b.get("render_position", Vector3(-INF, -INF, -INF)) as Vector3) \
		and is_equal_approx(float(a.get("remaining", -1.0)), float(b.get("remaining", -2.0)))


func _event_count(elevator: Node) -> int:
	return elevator._game_state.event_log.events.size() \
		if elevator._game_state.event_log != null else 0


func _destroy_elevator(elevator: Node) -> void:
	if elevator != null and is_instance_valid(elevator):
		if elevator.has_method("_teardown_sequence"):
			elevator._teardown_sequence()
		elevator.free()
	await process_frame


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
