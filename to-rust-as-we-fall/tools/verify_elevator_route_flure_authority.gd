extends SceneTree

## Lower-route exploit regression. Elevator owns learned route facts and crossing history; the
## reusable Flure owns the only active phase/deadline. Both same-presenter rollback and a fresh
## scene must reconstruct that relationship without granting a free window or retaining future risk.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var elevator := await _spawn_elevator()
	_prepare_route(elevator)

	# First prove that optional Peris knowledge is retractable. The discarded future may register
	# cautious-grid risk, but a save from before the read must remove those cells and the overlay.
	var before_peris := _json_round_trip(elevator.build_save_snapshot())
	elevator._set_elevator_overlay_state("peris", true)
	check(bool(elevator._route_reads_resolved.get("peris", false)),
		"Peris's overlay commits exact-footprint knowledge")
	check(_all_route_risk_cells_present(elevator),
		"learned footprint knowledge registers cautious-grid risk")
	elevator.apply_save_snapshot(before_peris)
	check(not bool(elevator._route_reads_resolved.get("peris", false))
			and not bool(elevator._elevator_overlay_states.get("peris", false)),
		"same-presenter rollback retracts future route knowledge and overlay state")
	check(_all_route_risk_cells_absent(elevator),
		"same-presenter rollback retracts future cautious-grid risk")

	# Relearn, light one physical source, and save after only Aster has crossed its first beat.
	elevator._set_elevator_overlay_state("peris", true)
	var flure := elevator._route_flure_interactables[0] as Flure
	var activated := _trigger_flure(elevator, flure)
	var activation_report := flure.get_last_activation_report() if flure != null else {}
	check(activated,
		"the first physical Flure commits a complete linked-pack window (%s)" \
			% str(activation_report))
	var source_state: Dictionary = flure.get_effect_state()
	var source_deadline := float(source_state.get("end_tick", -1.0))
	var source_start := float(source_state.get("start_tick", -1.0))
	check(str(source_state.get("phase", "")) == Flure.PHASE_ACTIVE
			and source_deadline > elevator._scheduler.get_current_tick(),
		"Flure publishes the active phase and absolute deadline")
	_cross_first_beat(elevator, "aster", -4.0)
	var safe_position: Vector3 = elevator.ROUTE_READ_ASTER_POS
	_set_character_position(elevator, "aster", safe_position)
	elevator.headless_advance(1.0, 0.05)
	var midpoint := _json_round_trip(elevator.build_save_snapshot())
	var route_record: Dictionary = elevator._game_state.get_world_state(
		elevator.ELEVATOR_RUNTIME_AUTHORITY_KEY, {})
	var progress: Dictionary = route_record.get("route_progress", {}) as Dictionary
	check(int(route_record.get("version", 0)) == 5
			and str(route_record.get("contract", "")) == "elevator_runtime/v5",
		"route history uses the v5 Elevator runtime contract")
	check(not progress.has("phase") and not progress.has("end_tick")
			and not progress.has("route_flures_activated")
			and not progress.has("route_flure_end_ticks"),
		"Elevator authority stores no parallel Flure phase or deadline")
	check(_partial_first_beat_matches(elevator, source_start),
		"midpoint records Aster's exact source window without inventing Peris's crossing")
	check(elevator._route_flure_activation_counts[0] == 1
			and elevator._route_wasted_flure_windows == 0,
		"midpoint history counts one live source without charging an unfinished window")

	# Let the discarded future close the source and record an outside-window trailer.
	var remaining := source_deadline - float(elevator._scheduler.get_current_tick())
	elevator.headless_advance(maxf(0.0, remaining) + 0.02, 0.01)
	check(not elevator._route_flure_source_is_active(0)
			and elevator._route_wasted_flure_windows == 1,
		"the source deadline closes one unused window in the discarded future")
	elevator._set_elevator_overlay_state("peris", false)
	_cross_first_beat(elevator, "peris", -4.0)
	check(elevator._route_beats_crossed[0] and not elevator._route_flure_window_used(0),
		"a trailer outside the same source window earns no mastery credit")

	# Retire the discarded future's whole streamed presenter as ordinary Junction progression
	# does. Same-node rollback must rebuild the chunk and still retract every future fact.
	elevator._retire_lower_route_runtime()
	elevator._unload_chunk("below")
	elevator._enemies.clear()
	check(not elevator._chunks.has("below"),
		"the discarded future can retire the presenter that owned the active source")

	# Roll back onto the same scene after its source callback and local future both completed.
	elevator.apply_save_snapshot(midpoint)
	check(_restored_midpoint_matches(elevator, source_deadline, source_start),
		"same-presenter load restores source, knowledge, risk, and partial crossing")
	elevator.on_game_state_snapshot_restored()
	elevator.on_game_state_snapshot_restored()
	_verify_saved_deadline(elevator, source_deadline, "same-presenter")
	_teardown(elevator)

	# A disk load has no useful scene-local future. It must derive the same presentation and observer
	# solely from GameState plus the saved route-history record.
	var fresh := await _spawn_elevator()
	var hidden_prewarm := _finish_hidden_below_prewarm(fresh)
	check(hidden_prewarm != null and not hidden_prewarm.visible
			and hidden_prewarm.process_mode == Node.PROCESS_MODE_DISABLED,
		"fresh regression begins with a completed but unrevealed lower-route prewarm")
	fresh.apply_save_snapshot(midpoint)
	check(_restored_midpoint_matches(fresh, source_deadline, source_start),
		"fresh scene restores source, knowledge, risk, and partial crossing")
	var restored_chunk := fresh._chunks.get("below") as Node3D
	check(restored_chunk != null and restored_chunk.visible
			and restored_chunk.process_mode != Node.PROCESS_MODE_DISABLED,
		"saved active topology reveals a completed inert prewarm during reconstruction")
	var status := fresh._route_flure_status(0) as Label3D
	check(status != null and "PULLING" in status.text,
		"fresh presentation derives its countdown from the active Flure source")
	fresh.on_game_state_snapshot_restored()
	fresh.on_game_state_snapshot_restored()
	_verify_saved_deadline(fresh, source_deadline, "fresh-scene")
	_teardown(fresh)

	print("ELEVATOR ROUTE FLURE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _trigger_flure(elevator: Node, flure: Flure) -> bool:
	if flure == null:
		return false
	elevator._game_state.command_stop("peris")
	elevator._game_state.snap_character_to("peris", flure.get_source_data_position())
	flure.active_character = "peris"
	return bool(flure.call("_trigger", false))


func _spawn_elevator() -> Node:
	var elevator := ElevatorScene.instantiate()
	elevator.suppress_scene_change = true
	root.add_child(elevator)
	for _frame in range(8):
		await process_frame
	_clear_sequence_runtime(elevator)
	return elevator


func _prepare_route(elevator: Node) -> void:
	# A normal run constructs this chunk dormant above the bridge, then reveals it before
	# the fall. Reproduce both seams explicitly: merely calling _load_chunk can return the
	# already-complete but still-hidden stream root, and dormant fauna do not enter
	# GameState until a lower-deck party member approaches their cohort.
	elevator.reveal_chunk("below")
	for member_id in ["aster", "peris"]:
		elevator._game_state.set_character_level(member_id, elevator.LEVEL_LOWER)
		elevator._game_state.restore_character(member_id)
		_set_character_position(
			elevator,
			member_id,
			elevator.ROUTE_READ_ASTER_POS if member_id == "aster" \
				else elevator.ROUTE_READ_PERIS_POS
		)
	var first_flure_position: Vector3 = elevator._route_flure_position(0)
	_set_character_position(elevator, "peris", first_flure_position)
	elevator._activate_below_fauna()
	_set_character_position(elevator, "peris", elevator.ROUTE_READ_PERIS_POS)
	elevator._unlock_elevator_overlays()
	elevator._route_reads_resolved["aster"] = true
	elevator._start_route_choice()
	elevator._publish_elevator_runtime_authority()


func _finish_hidden_below_prewarm(elevator: Node) -> Node3D:
	if elevator._chunk_streams.has("below"):
		elevator._run_chunk_stream_steps("below", 9999)
	return elevator._chunks.get("below") as Node3D


func _cross_first_beat(elevator: Node, member_id: String, z: float) -> void:
	var threshold: float = elevator.FORK_POS.x + float(elevator.ROUTE_BEAT_OFFSETS[0]) \
		+ elevator.ROUTE_BEAT_CLEARANCE_OFFSET
	_set_character_position(
		elevator, member_id, Vector3(threshold + 0.5, elevator.BELOW_Y, z))
	elevator._update_route_course_progress()


func _partial_first_beat_matches(elevator: Node, source_start: float) -> bool:
	return elevator._route_beat_character_lanes[0].has("aster") \
		and not elevator._route_beat_character_lanes[0].has("peris") \
		and is_equal_approx(float(
			elevator._route_beat_character_window_sources[0].get("aster", -1.0)
		), source_start)


func _restored_midpoint_matches(
		elevator: Node, source_deadline: float, source_start: float) -> bool:
	var state: Dictionary = elevator._route_flure_effect_state(0)
	return str(state.get("phase", "")) == Flure.PHASE_ACTIVE \
		and is_equal_approx(float(state.get("end_tick", -1.0)), source_deadline) \
		and bool(elevator._route_reads_resolved.get("peris", false)) \
		and bool(elevator._elevator_overlay_states.get("peris", false)) \
		and _all_route_risk_cells_present(elevator) \
		and _partial_first_beat_matches(elevator, source_start) \
		and elevator._route_flure_activation_counts[0] == 1 \
		and elevator._route_wasted_flure_windows == 0


func _verify_saved_deadline(
		elevator: Node, source_deadline: float, lifecycle: String) -> void:
	var remaining := source_deadline - float(elevator._scheduler.get_current_tick())
	elevator.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(elevator._route_flure_source_is_active(0)
			and elevator._route_wasted_flure_windows == 0,
		"%s load cannot close or charge the window before its source deadline" % lifecycle)
	elevator.headless_advance(0.02, 0.01)
	check(not elevator._route_flure_source_is_active(0)
			and elevator._route_wasted_flure_windows == 1,
		"%s load closes and charges the unused source window exactly once" % lifecycle)
	elevator.headless_advance(0.25, 0.05)
	check(elevator._route_wasted_flure_windows == 1,
		"%s duplicate restore hooks cannot duplicate the close accounting" % lifecycle)


func _all_route_risk_cells_present(elevator: Node) -> bool:
	if elevator._iron_route_risk_cells.is_empty():
		return false
	for cell in elevator._iron_route_risk_cells:
		if not elevator._grid.is_cell_risky(cell):
			return false
	return true


func _all_route_risk_cells_absent(elevator: Node) -> bool:
	if not elevator._iron_route_risk_cells.is_empty():
		return false
	for patch_v in elevator._iron_patches:
		var patch := patch_v as Dictionary
		var pos: Vector3 = patch.get("pos", Vector3.ZERO)
		var size: Vector3 = patch.get("size", Vector3.ZERO)
		var min_cell: Vector2i = elevator._grid.world_to_grid(
			Vector3(pos.x - size.x * 0.5, 0.0, pos.z - size.z * 0.5))
		var max_cell: Vector2i = elevator._grid.world_to_grid(
			Vector3(pos.x + size.x * 0.5, 0.0, pos.z + size.z * 0.5))
		for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
			for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
				if elevator._grid.is_cell_risky(Vector2i(x, z)):
					return false
	return true


func _set_character_position(elevator: Node, member_id: String, position: Vector3) -> void:
	elevator._game_state.command_stop(member_id)
	elevator._game_state.snap_character_to(member_id, position)
	var character_node := elevator.get_game_state_character_node(member_id) as Node3D
	if character_node != null:
		character_node.global_position = position


func _clear_sequence_runtime(elevator: Node) -> void:
	elevator._scheduler.clear()
	elevator._scheduler.resume()
	if elevator._dialogue != null and elevator._dialogue.has_method("clear"):
		elevator._dialogue.clear()
	if elevator._tutorial_prompt != null:
		elevator._tutorial_prompt.hide_prompt()


func _teardown(elevator: Node) -> void:
	if elevator.has_method("_teardown_sequence"):
		elevator._teardown_sequence()
	elevator.free()


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
