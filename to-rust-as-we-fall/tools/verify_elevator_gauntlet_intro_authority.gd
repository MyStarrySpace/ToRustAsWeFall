extends SceneTree

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source := await _spawn_gauntlet_sequence()
	var targets: Dictionary = source._gauntlet_intro_targets()
	var first_flure: Flure = source._gauntlet_flure_interactables[0]
	source._game_state.command_stop("aster")
	source._game_state.snap_character_to("aster", targets["aster"] + Vector3(-1.0, 0.0, 0.0))
	source._gauntlet_intro_authority["next_retry_tick"] = source._scheduler.get_current_tick()
	source._issue_next_gauntlet_intro_move()
	check(bool((source._gauntlet_intro_authority.get(
		"accepted_commands", {}) as Dictionary).get("aster", false)),
		"formation authority records the canonical command acceptance result instead of assuming success")

	source._finish_gauntlet_intro()
	_settle_member(source, "aster", targets["aster"])
	source._update_gauntlet_intro_formation()
	var partial: Dictionary = source._gauntlet_intro_authority
	check(str(partial.get("phase", "")) == source.GAUNTLET_INTRO_PHASE_ASSEMBLING,
		"finished briefing plus one body cannot arm the gauntlet")
	check(not first_flure.is_interaction_enabled() and _first_pack_is_inert(source),
		"the Flure and first pack stay inert during partial formation")

	_settle_member(source, "peris", targets["peris"])
	source._update_gauntlet_intro_formation()
	check(str(source._gauntlet_intro_authority.get("phase", "")) \
		== source.GAUNTLET_INTRO_PHASE_ASSEMBLING,
		"Aster and Peris cannot abandon Endo at the briefing boundary")
	var midpoint_capture := _capture(source)

	_settle_member(source, "endo", targets["endo"])
	source._update_gauntlet_intro_formation()
	check(str(source._gauntlet_intro_authority.get("phase", "")) \
		== source.GAUNTLET_INTRO_PHASE_READY,
		"all three conscious settled bodies commit the formation endpoint")
	check(first_flure.is_interaction_enabled() and not _first_pack_is_inert(source),
		"the committed endpoint arms the Flure and its real linked pack together")

	await _apply_capture(source, midpoint_capture)
	first_flure = source._gauntlet_flure_interactables[0]
	check(str(source._gauntlet_intro_authority.get("phase", "")) \
		== source.GAUNTLET_INTRO_PHASE_ASSEMBLING,
		"same-presenter rollback retracts the discarded ready future")
	check(not first_flure.is_interaction_enabled() and _first_pack_is_inert(source),
		"rollback reconstructs the inert partial-formation presentation")
	check(source._game_state.get_position("endo").distance_to(targets["endo"]) \
		> source.GAUNTLET_INTRO_ARRIVAL_RADIUS,
		"rollback restores Endo before the missing physical endpoint")

	var fresh := await _spawn_gauntlet_sequence()
	await _apply_capture(fresh, midpoint_capture)
	check(str(fresh._gauntlet_intro_authority.get("phase", "")) \
		== fresh.GAUNTLET_INTRO_PHASE_ASSEMBLING,
		"a fresh presenter restores the same partial formation")
	var fresh_targets: Dictionary = fresh._gauntlet_intro_targets()
	_settle_member(fresh, "endo", fresh_targets["endo"])
	fresh._update_gauntlet_intro_formation()
	check(str(fresh._gauntlet_intro_authority.get("phase", "")) \
		== fresh.GAUNTLET_INTRO_PHASE_READY,
		"fresh restore commits only after the remaining body truly arrives")

	var corrupt := midpoint_capture.duplicate(true)
	var corrupt_game_state: Dictionary = corrupt.get("game_state", {})
	var world_state: Dictionary = corrupt_game_state.get("world_state", {})
	var outer: Dictionary = world_state.get(source.ELEVATOR_RUNTIME_AUTHORITY_KEY, {})
	var intro: Dictionary = (outer.get("gauntlet_intro", {}) as Dictionary).duplicate(true)
	var encoded_targets: Dictionary = (intro.get("targets", {}) as Dictionary).duplicate(true)
	encoded_targets["endo"] = [999.0, 0.0, 999.0]
	intro["targets"] = encoded_targets
	outer["gauntlet_intro"] = intro
	world_state[source.ELEVATOR_RUNTIME_AUTHORITY_KEY] = outer
	corrupt_game_state["world_state"] = world_state
	corrupt["game_state"] = corrupt_game_state
	await _apply_capture(source, corrupt)
	check(str(source._gauntlet_intro_authority.get("phase", "")) \
		== source.GAUNTLET_INTRO_PHASE_ASSEMBLING \
		and not bool(source._gauntlet_intro_authority.get("presentation_complete", true)),
		"malformed formation context fails closed and replays the briefing")
	check(GameEvent.arr_to_v3(
		(source._gauntlet_intro_authority.get("targets", {}) as Dictionary).get("endo", [])
	).distance_to(targets["endo"]) < 0.001,
		"malformed targets cannot turn the save into a movement teleport")

	await _dispose(source)
	await _dispose(fresh)
	print("ELEVATOR GAUNTLET INTRO AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_gauntlet_sequence() -> Node:
	var sequence := ElevatorScene.instantiate()
	sequence.suppress_scene_change = true
	sequence.start_chunk = "gauntlet"
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence._reset_endo_entry_dialogue_for_restore()
	if not sequence._game_state.characters.has("endo"):
		sequence._set_endo_presenter_present(true)
		sequence._endo.global_position = sequence._endo_entry_destination()
		sequence._register_gs_character("endo", sequence._endo, 2.5, {
			"hp": sequence.PARTY_MAX_HP,
			"stamina": GameState.STAMINA_MAX,
			"atp": GameState.ATP_MAX_PIPS,
		})
	var targets: Dictionary = sequence._gauntlet_intro_targets()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var target: Vector3 = targets[member_id]
		var approach := target + Vector3(-2.0, 0.0, 0.0)
		sequence._game_state.command_stop(member_id)
		sequence._game_state.set_character_level(member_id, sequence.LEVEL_LOWER)
		sequence._game_state.snap_character_to(member_id, approach)
	sequence._start_gauntlet()
	sequence._reset_endo_entry_dialogue_for_restore()
	return sequence


func _settle_member(sequence: Node, member_id: String, target: Vector3) -> void:
	sequence._gauntlet_intro_authority["next_retry_tick"] = \
		sequence._scheduler.get_current_tick()
	sequence._issue_next_gauntlet_intro_move()
	sequence._game_state.command_stop(member_id)
	sequence._game_state.snap_character_to(member_id, target)


func _first_pack_is_inert(sequence: Node) -> bool:
	for enemy_v in sequence._gauntlet_enemy_groups.get(0, []):
		var enemy := enemy_v as Enemy
		if is_instance_valid(enemy) and not enemy._detection_targets.is_empty():
			return false
	return true


func _capture(sequence: Node) -> Dictionary:
	return _json_round_trip({
		"scheduler": sequence._scheduler.serialize(),
		"game_state": sequence._game_state.serialize(),
		"step": sequence._current_step,
	})


func _apply_capture(sequence: Node, capture: Dictionary) -> void:
	sequence._scheduler.clear()
	sequence._scheduler.deserialize(capture.get("scheduler", {}))
	sequence._game_state.deserialize(capture.get("game_state", {}))
	sequence._current_step = str(capture.get("step", "gauntlet"))
	_notify_snapshot_restored(sequence)
	for _frame in range(3):
		await process_frame


func _notify_snapshot_restored(node: Node) -> void:
	if node.has_method("on_game_state_snapshot_restored"):
		node.call("on_game_state_snapshot_restored")
	for child in node.get_children():
		_notify_snapshot_restored(child)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		sequence.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
