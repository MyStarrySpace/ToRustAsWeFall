extends SceneTree

## Same-presenter rollback regression for Elevator's streamed lower route. This deliberately lets the
## future timeline finish the wreckage gate and unload `below`, then loads a midpoint snapshot. The
## earlier topology and exact authoritative deadline must return without a free completion.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var elevator := ElevatorScene.instantiate()
	elevator.suppress_scene_change = true
	root.add_child(elevator)
	for _frame in range(8):
		await process_frame
	_clear_sequence_runtime(elevator)
	elevator._load_chunk("below")
	elevator._enter_step("route_choice")
	for member_id in ["aster", "peris"]:
		elevator._game_state.set_character_level(member_id, elevator.LEVEL_LOWER)
		elevator._game_state.restore_character(member_id)

	# Cadenced damage is part of the same exploit class: a load must not restart the interval or
	# preserve damage from the discarded future.
	var iron_center: Vector3 = (elevator._iron_patches[0] as Dictionary).get("pos", Vector3.ZERO)
	_set_character_position(elevator, "aster", iron_center)
	var safe_pos := iron_center + Vector3(0.0, 0.0, 6.0)
	_set_character_position(elevator, "peris", safe_pos)
	elevator._iron_hazard_tick_armed = false
	elevator._iron_hazard_next_tick = -1.0
	elevator._arm_iron_hazard_tick()
	elevator.headless_advance(0.2, 0.05)
	var iron_snapshot := _json_round_trip(elevator.build_save_snapshot())
	var saved_hp: float = float(elevator._game_state.get_stat("aster", "hp"))
	var iron_deadline := float(elevator._game_state.get_world_state(
		elevator.ELEVATOR_RUNTIME_AUTHORITY_KEY, {}).get("iron_next_tick", -1.0))
	elevator.headless_advance(0.3, 0.05)
	check(elevator._game_state.get_stat("aster", "hp") < saved_hp,
		"the discarded future applies its scheduled iron hit")
	elevator.apply_save_snapshot(iron_snapshot)
	check(is_equal_approx(elevator._game_state.get_stat("aster", "hp"), saved_hp),
		"loading retracts damage that occurred after the save")
	var iron_remaining: float = iron_deadline - float(elevator._scheduler.get_current_tick())
	elevator.headless_advance(maxf(0.0, iron_remaining - 0.01), 0.01)
	check(is_equal_approx(elevator._game_state.get_stat("aster", "hp"), saved_hp),
		"iron cannot hit before the saved absolute cadence deadline")
	elevator.headless_advance(0.02, 0.01)
	check(elevator._game_state.get_stat("aster", "hp") < saved_hp,
		"iron hits once the saved remainder elapses")

	# Move out before exercising the cooperative gate so hazard cadence cannot cloud the result.
	_set_character_position(elevator, "aster", safe_pos + Vector3(0.0, 0.0, -1.0))
	var anchor: Vector3 = elevator._wreckage_interaction_anchor()
	elevator._arm_wreckage_gate(false)
	check(not elevator._on_wreckage_interacted(),
		"a direct wreckage owner callback has no exact-source receipt and is inert")
	elevator._wreckage_interactable.emit_signal("interacted")
	check(str(elevator._wreckage_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED,
		"a manually emitted wreckage signal cannot counterfeit source acceptance")
	elevator._wreckage_interactable.set("active_character", "aster")
	check(not bool(elevator._wreckage_interactable.call("_trigger", false)),
		"a remote selected portrait cannot accept the exact wreckage source")
	_set_character_position(elevator, "aster", anchor + Vector3(0.0, 0.0, -0.8))
	_set_character_position(elevator, "peris", anchor + Vector3(0.0, 0.0, 0.8))
	elevator._wreckage_interactable.set("active_character", "peris")
	var accepted_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, actor: String) -> void:
		if data_id == str(elevator._wreckage_interactable.get("data_id")) \
				and actor == "peris" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _json_round_trip(elevator.build_save_snapshot())
	elevator._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(bool(elevator._wreckage_interactable.call("_trigger", false)),
		"the exact nearby wreckage source accepts the cooperative attempt")
	var source_gate: PartyGate3D = elevator._wreckage_gate as PartyGate3D
	var opening: Dictionary = source_gate.get_authority_state()
	check(str(opening.get("phase", "")) == PartyGate3D.PHASE_OPENING,
		"the paired lift commits an in-progress authoritative phase")
	elevator.headless_advance(0.4, 0.05)
	var gate_snapshot := _json_round_trip(elevator.build_save_snapshot())
	var saved_tick: float = float(elevator._scheduler.get_current_tick())
	var gate_deadline := float(source_gate.get_authority_state().get("end_tick", -1.0))
	check((gate_snapshot.get("elevator_presenters", {}) as Dictionary).get(
		"active_chunks", []).has("below"),
		"the save records which streamed gameplay presenter owns the phase")

	# Let the future finish. Its completion unloads the very chunk the save needs.
	elevator.headless_advance(maxf(0.0, gate_deadline - saved_tick) + 0.05, 0.05)
	check(str(elevator._current_step) == "junction_arrive" and not elevator._chunks.has("below"),
		"the future timeline reaches Junction and retires the lower-route presenter")

	elevator.apply_save_snapshot(gate_snapshot)
	var restored_gate: PartyGate3D = elevator._wreckage_gate as PartyGate3D
	var restored: Dictionary = restored_gate.get_authority_state()
	check(str(elevator._current_step) == "route_choice" and elevator._chunks.has("below")
			and not elevator._chunks.has("junction"),
		"same-instance rollback reconstructs the saved level topology")
	check(restored_gate != source_gate and str(restored.get("phase", "")) == PartyGate3D.PHASE_OPENING,
		"the rebuilt gate attaches to the saved midpoint instead of inheriting OPEN")
	check(is_equal_approx(float(restored.get("end_tick", -1.0)), gate_deadline),
		"the rebuilt gate keeps the original absolute completion deadline")

	var remaining: float = gate_deadline - float(elevator._scheduler.get_current_tick())
	elevator.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(str(elevator._current_step) == "route_choice",
		"rollback cannot skip the remaining cooperative-lift time")
	elevator.headless_advance(0.02, 0.01)
	check(str(elevator._current_step) == "junction_arrive",
		"the rebuilt gate advances exactly after the saved remainder")
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the exact wreckage acceptance boundary can be saved before PartyGate ownership")
	elevator.apply_save_snapshot(accepted_snapshot)
	check(str(elevator._current_step) == "route_choice"
			and str(elevator._wreckage_gate.get_authority_state().get("phase", "")) \
				== PartyGate3D.PHASE_CLOSED
			and elevator._wreckage_interactable.is_interaction_enabled(),
		"same-presenter accepted-before-owner restore rearms without manufacturing a lift")

	if elevator.has_method("_teardown_sequence"):
		elevator._teardown_sequence()
	elevator.free()

	# A disk load constructs a fresh scene, so prove the same artifact attaches without relying on
	# any scene-local values retained by the original instance.
	var fresh := ElevatorScene.instantiate()
	fresh.suppress_scene_change = true
	root.add_child(fresh)
	for _frame in range(8):
		await process_frame
	_clear_sequence_runtime(fresh)
	fresh.apply_save_snapshot(gate_snapshot)
	var fresh_gate: PartyGate3D = fresh._wreckage_gate as PartyGate3D
	var fresh_gate_state: Dictionary = fresh_gate.get_authority_state()
	check(str(fresh._current_step) == "route_choice" and fresh._chunks.has("below")
			and str(fresh_gate_state.get("phase", "")) == PartyGate3D.PHASE_OPENING,
		"a fresh scene attaches the streamed gate presenter to the saved midpoint")
	check(is_equal_approx(float(fresh_gate_state.get("end_tick", -1.0)), gate_deadline),
		"fresh-scene load preserves the same absolute gate deadline")
	var fresh_remaining: float = gate_deadline - float(fresh._scheduler.get_current_tick())
	fresh.headless_advance(maxf(0.0, fresh_remaining - 0.01), 0.01)
	check(str(fresh._current_step) == "route_choice",
		"fresh-scene load cannot complete before the saved remainder")
	fresh.headless_advance(0.02, 0.01)
	check(str(fresh._current_step) == "junction_arrive",
		"fresh-scene load completes exactly once at the saved deadline")
	fresh.apply_save_snapshot(accepted_snapshot)
	check(str(fresh._current_step) == "route_choice"
			and str(fresh._wreckage_gate.get_authority_state().get("phase", "")) \
				== PartyGate3D.PHASE_CLOSED
			and fresh._wreckage_interactable.is_interaction_enabled(),
		"fresh accepted-before-owner restore also rearms without granting clearance")
	if fresh.has_method("_teardown_sequence"):
		fresh._teardown_sequence()
	fresh.free()
	print("ELEVATOR RUNTIME SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _clear_sequence_runtime(elevator: Node) -> void:
	elevator._scheduler.clear()
	elevator._scheduler.resume()
	if elevator._dialogue != null and elevator._dialogue.has_method("clear"):
		elevator._dialogue.clear()
	if elevator._tutorial_prompt != null:
		elevator._tutorial_prompt.hide_prompt()


func _set_character_position(elevator: Node, character_id: String, position: Vector3) -> void:
	elevator._game_state.command_stop(character_id)
	elevator._game_state.snap_character_to(character_id, position)
	var character_node: Node3D = elevator.get_game_state_character_node(character_id)
	if character_node != null:
		character_node.global_position = position


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
