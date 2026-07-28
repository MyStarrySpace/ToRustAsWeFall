extends SceneTree

## Exact-source receipt regression for Elevator's two story interactions that are created only
## during their active beat. Wreckage/PartyGate coverage lives in
## verify_elevator_runtime_save_authority.gd.
##
## Run:
##   godot --headless --path . --script res://tools/verify_elevator_interaction_receipt_authority.gd

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_aster_wake_receipt()
	await _verify_collapsed_bridge_receipt()
	print("ELEVATOR INTERACTION RECEIPT AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_aster_wake_receipt() -> void:
	var source: Node = await _spawn_sequence()
	source._enter_step("approach_aster")
	source._ensure_aster_wake_interactable()
	source._project_elevator_source(source.ELEVATOR_SOURCE_WAKE)
	var interactable: Node = source._aster_wake_interactable
	var source_position: Vector3 = source._elevator_source_data_position(interactable)

	check(not source._on_aster_wake_interacted()
			and source._current_step == "approach_aster",
		"a direct Aster-wake owner callback has no receipt and is inert")
	interactable.set("active_character", "peris")
	interactable.emit_signal("interacted")
	check(source._current_step == "approach_aster",
		"a manually emitted wake signal cannot counterfeit source acceptance")
	_set_character_position(source, "peris", source_position + Vector3(12.0, 0.0, 0.0))
	check(not bool(interactable.call("_trigger", false))
			and source._current_step == "approach_aster",
		"a remote selected Peris portrait cannot wake Aster")

	_set_character_position(source, "peris", source_position)
	var accepted_box := {"snapshot": {}}
	var source_committed_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, actor: String) -> void:
		if data_id == str(interactable.get("data_id")) and actor == "peris" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _capture(source)
	var capture_source_committed := func(key: String, _value: Variant) -> void:
		if key == source.ELEVATOR_SOURCE_AUTHORITY_KEY \
				and (source_committed_box.get("snapshot", {}) as Dictionary).is_empty():
			source_committed_box["snapshot"] = _capture(source)
	source._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	source._game_state.world_state_changed.connect(capture_source_committed)
	check(bool(interactable.call("_trigger", false))
			and source._current_step == "wake_aster",
		"nearby canonical Peris can wake Aster through the exact registered source")
	if source._game_state.world_state_changed.is_connected(capture_source_committed):
		source._game_state.world_state_changed.disconnect(capture_source_committed)
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the wake source acceptance boundary is saveable before its story owner runs")
	var source_committed_snapshot: Dictionary = source_committed_box.get(
		"snapshot", {}) as Dictionary
	check(not source_committed_snapshot.is_empty(),
		"the consumed wake receipt is saveable before its story owner runs")

	source.apply_save_snapshot(accepted_snapshot)
	check(source._current_step == "approach_aster"
			and is_instance_valid(source._aster_wake_interactable)
			and source._aster_wake_interactable.is_interaction_enabled()
			and _receipt_is_burned(source, source.ELEVATOR_SOURCE_WAKE),
		"same-presenter accepted-before-owner restore burns the edge without waking Aster")
	source.apply_save_snapshot(source_committed_snapshot)
	check(source._current_step == "approach_aster"
			and source._aster_wake_interactable.is_interaction_enabled()
			and _receipt_is_burned(source, source.ELEVATOR_SOURCE_WAKE),
		"same-presenter source-committed restore rearms without reusing the wake receipt")

	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(accepted_snapshot)
	check(fresh._current_step == "approach_aster"
			and is_instance_valid(fresh._aster_wake_interactable)
			and fresh._aster_wake_interactable.is_interaction_enabled()
			and _receipt_is_burned(fresh, fresh.ELEVATOR_SOURCE_WAKE),
		"fresh accepted-before-owner restore also rearms without manufacturing wake progress")
	fresh.apply_save_snapshot(source_committed_snapshot)
	check(fresh._current_step == "approach_aster"
			and fresh._aster_wake_interactable.is_interaction_enabled()
			and _receipt_is_burned(fresh, fresh.ELEVATOR_SOURCE_WAKE),
		"fresh source-committed restore also rearms without manufacturing wake progress")
	var fresh_position: Vector3 = fresh._elevator_source_data_position(
		fresh._aster_wake_interactable)
	_set_character_position(fresh, "peris", fresh_position)
	fresh._aster_wake_interactable.set("active_character", "peris")
	check(bool(fresh._aster_wake_interactable.call("_trigger", false))
			and fresh._current_step == "wake_aster",
		"a newer wake receipt remains usable after the orphan edge is burned")

	await _dispose(source)
	await _dispose(fresh)


func _verify_collapsed_bridge_receipt() -> void:
	var source: Node = await _spawn_sequence("route")
	for actor in ["aster", "peris"]:
		source._game_state.set_character_level(actor, source.LEVEL_LOWER)
	source._enter_step("climb_attempt")
	source._ensure_climb_interactable()
	source._project_elevator_source(source.ELEVATOR_SOURCE_COLLAPSE)
	var interactable: Node = source._climb_interactable
	var source_position: Vector3 = source._elevator_source_data_position(interactable)

	check(not source._on_climb_prompt_interacted()
			and source._current_step == "climb_attempt",
		"a direct collapsed-bridge owner callback has no receipt and is inert")
	interactable.set("active_character", "aster")
	interactable.emit_signal("interacted")
	check(source._current_step == "climb_attempt",
		"a manually emitted climb signal cannot counterfeit source acceptance")
	_set_character_position(source, "aster", source_position + Vector3(12.0, 0.0, 0.0))
	check(not bool(interactable.call("_trigger", false))
			and source._current_step == "climb_attempt",
		"a remote selected Aster portrait cannot inspect the collapsed bridge")

	_set_character_position(source, "aster", source_position)
	var accepted_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, actor: String) -> void:
		if data_id == str(interactable.get("data_id")) and actor == "aster" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _capture(source)
	source._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(bool(interactable.call("_trigger", false))
			and source._current_step == "climb_inspected",
		"a nearby canonical body can inspect the collapse through its exact source")
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the collapse source acceptance boundary is saveable before its story owner runs")

	source.apply_save_snapshot(accepted_snapshot)
	check(source._current_step == "climb_attempt"
			and is_instance_valid(source._climb_interactable)
			and source._climb_interactable.is_interaction_enabled()
			and _receipt_is_burned(source, source.ELEVATOR_SOURCE_COLLAPSE),
		"same-presenter accepted-before-owner restore burns the edge without skipping the inspection")

	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(accepted_snapshot)
	check(fresh._current_step == "climb_attempt"
			and is_instance_valid(fresh._climb_interactable)
			and fresh._climb_interactable.is_interaction_enabled()
			and _receipt_is_burned(fresh, fresh.ELEVATOR_SOURCE_COLLAPSE),
		"fresh accepted-before-owner restore rebuilds the lower source without granting progress")
	var fresh_position: Vector3 = fresh._elevator_source_data_position(
		fresh._climb_interactable)
	_set_character_position(fresh, "peris", fresh_position)
	fresh._climb_interactable.set("active_character", "peris")
	check(bool(fresh._climb_interactable.call("_trigger", false))
			and fresh._current_step == "climb_inspected",
		"a newer collapse receipt remains usable after the orphan edge is burned")

	await _dispose(source)
	await _dispose(fresh)


func _receipt_is_burned(sequence: Node, action_id: String) -> bool:
	var data_id: String = str(sequence._elevator_source_data_id(action_id))
	if data_id == "" or not sequence._game_state.has_interactable(data_id):
		return false
	var trigger_count := int(sequence._game_state.get_interactable(data_id).get(
		"trigger_count", -1))
	return trigger_count > 0 and trigger_count == int(
		sequence._elevator_source_committed_counts.get(action_id, -1))


func _spawn_sequence(start_chunk := "") -> Node:
	var sequence := ElevatorScene.instantiate()
	sequence.suppress_scene_change = true
	sequence.start_chunk = start_chunk
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	if sequence._dialogue != null and sequence._dialogue.has_method("clear"):
		sequence._dialogue.clear()
	if sequence._tutorial_prompt != null:
		sequence._tutorial_prompt.hide_prompt()
	return sequence


func _set_character_position(sequence: Node, actor: String, position: Vector3) -> void:
	sequence.set_preview_character_position(actor, position)
	var actor_node: Node3D = sequence.get_game_state_character_node(actor)
	if actor_node != null:
		actor_node.global_position = position


func _capture(sequence: Node) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(
		sequence.build_save_snapshot()))
	return parsed as Dictionary if parsed is Dictionary else {}


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.free()
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
