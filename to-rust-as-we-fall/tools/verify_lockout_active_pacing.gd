extends SceneTree

## Focused Lockout regression for the physical chase that remains after the synthetic
## rally course was removed. Run with:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_lockout_active_pacing.gd

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	var packed := load("res://scenes/fragments/fragment_preview.tscn") as PackedScene
	_check(packed != null, "the shared fragment preview scene loads")
	if packed == null:
		_finish()
		return
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "lockout_chase")
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	var chunk: Node = preview.get("_active_chunk")
	_check(chunk != null, "the Lockout chase builds in the real playable preview host")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return

	_verify_structure(chunk)
	_verify_no_synthetic_pacing(chunk)
	await _verify_physical_flow(preview, chunk)

	await _dispose(preview)
	_finish()


func _verify_structure(chunk: Node) -> void:
	print("\n=== Lockout physical chase structure ===")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(chunk.find_children("LockoutRally*", "", true, false).is_empty(),
		"no synthetic rally nodes are present")
	_check(not chunk.has_method("get_lockout_driver_hooks")
		and not state.has("rally_phase")
		and not state.has("rally_completed_stages")
		and not state.has("rally_completed_actions")
		and not state.has("rally_choices"),
		"no rally driver or progress surface survives")

	for node_name in ["BoundaryScanner", "ServiceDoor", "ClamberBarricade",
			"SealPadIn", "SealPadOut", "TyregChoice", "EndoWall"]:
		_check(chunk.find_child(node_name, true, false) != null,
			"physical chase object %s exists" % node_name)

	var audit: Dictionary = chunk.call("get_decoration_audit")
	_check(chunk.find_child("LevelDecoration", true, false) != null and not audit.is_empty(),
		"Lockout retains the shared deterministic decoration pass")
	_check(str(audit.get("contract_id", "")) == "authored_level_decoration_v1"
		and str(audit.get("program", "")) == "boundary",
		"decoration retains the institutional boundary grammar")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		"decoration cannot alter the chase grid or physical gates")


func _verify_no_synthetic_pacing(chunk: Node) -> void:
	print("\n=== Lockout pacing authority ===")
	_check(not chunk.has_method("get_playtime_contract"),
		"Lockout makes no synthetic first-clear duration claim")
	var source := FileAccess.get_file_as_string(
		"res://scripts/fragments/chunks/lockout_chase_chunk.gd")
	for retired_key in ["rally_stage_count", "mandatory_pair_checks",
			"mandatory_specialist_actions", "mandatory_strategy_choices",
			"mandatory_branch_actions", "shortest_rally_route_meters",
			"shortest_rally_route_seconds", "rally_route_breakdown", "driver_hooks"]:
		_check(not source.contains(retired_key),
			"retired pacing field %s is absent" % retired_key)
	_check(source.contains("physical chase systems rather than adding mandatory interaction checklists")
		or not source.contains("required_first_clear_seconds"),
		"human playtesting, not a duration quota, owns future Lockout pacing work")


func _verify_physical_flow(preview: Node, chunk: Node) -> void:
	print("\n=== Lockout scanner, checkpoints, and pair-at-wall gate ===")
	chunk.call("set_pursuit_start_deferred", true)
	var scanner: Node = chunk.find_child("BoundaryScanner", true, false)
	var game_state = preview.call("get_preview_game_state")
	_check(scanner != null and game_state != null,
		"scanner and GameState are available for the focused flow")
	if scanner == null or game_state == null:
		return

	_check(not bool((chunk.call("get_preview_state") as Dictionary).get("chase_started", false)),
		"the chase is quiet before tags are presented")
	preview.call("headless_select_character", "aster")
	var scanner_position: Vector3 = game_state.get_interactable(
		str(scanner.get("data_id"))).get("position", (scanner as Node3D).position)
	game_state.snap_character_to("aster", scanner_position)
	scanner.set("active_character", "aster")
	_check(bool(scanner.call("_trigger", false)),
		"nearby Aster presents tags through the exact scanner")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(bool(state.get("chase_started", false))
		and str(state.get("gantry_phase", "")) == "falling"
		and not bool(state.get("bridge_down", true)),
		"the boundary scanner starts the chase and commits the physical gantry fall")
	game_state.scheduler.advance_ticks(float(chunk.GANTRY_FALL_SECS))
	chunk.call("headless_process", 0.0)
	state = chunk.call("get_preview_state")
	_check(str(state.get("gantry_phase", "")) == "bridged"
		and bool(state.get("bridge_down", false)),
		"the trench opens only when the falling span reaches both lips")

	# Every checkpoint advances only when both living members physically cross its marker.
	chunk.set("_checkpoint_x", -1.0)
	game_state.restore_character("aster")
	game_state.restore_character("peris")
	var previous_checkpoint := -1.0
	for checkpoint_variant in chunk.CHECKPOINTS:
		var checkpoint := float(checkpoint_variant)
		game_state.snap_character_to("aster", Vector3(checkpoint + 1.0, 0.0, -1.0))
		game_state.snap_character_to("peris", Vector3(checkpoint - 1.0, 0.0, 1.0))
		chunk.call("_advance_checkpoint", game_state)
		_check(is_equal_approx(float(chunk.get("_checkpoint_x")), previous_checkpoint),
			"one runner cannot claim checkpoint %.0f" % checkpoint)
		game_state.snap_character_to("peris", Vector3(checkpoint + 1.0, 0.0, 1.0))
		chunk.call("_advance_checkpoint", game_state)
		_check(is_equal_approx(float(chunk.get("_checkpoint_x")), checkpoint),
			"the intact pair claims checkpoint %.0f" % checkpoint)
		previous_checkpoint = checkpoint

	# A from-the-top reset re-arms the scanner instead of preserving a spent one-shot.
	chunk.set("_checkpoint_x", -1.0)
	chunk.call("_restart_fragment")
	await process_frame
	state = chunk.call("get_preview_state")
	_check(not bool(state.get("chase_started", true))
		and bool(scanner.call("is_interaction_enabled")),
		"a full reset quiets the chase and re-arms the scanner")
	game_state.snap_character_to("aster", scanner_position)
	scanner.set("active_character", "aster")
	_check(bool(scanner.call("_trigger", false)),
		"reset run again consumes the nearby scanner source")
	state = chunk.call("get_preview_state")
	_check(bool(state.get("chase_started", false)),
		"presenting tags after reset starts the chase again")
	_check(chunk.find_children("LockoutRally*", "", true, false).is_empty(),
		"resetting and restarting cannot regenerate synthetic rally nodes")

	# Endo's wall checks physical party presence, not deleted checklist progress.
	var wall_rest: Node = chunk.find_child("EndoWall", true, false)
	_check(wall_rest != null, "Endo's wall rest exists")
	if wall_rest == null:
		return
	for character_id in ["aster", "peris"]:
		game_state.restore_character(character_id)
	var wall_source_pos: Vector3 = chunk.call("_fragment_source_data_position", wall_rest)
	game_state.snap_character_to("aster", wall_source_pos)
	game_state.snap_character_to("peris", Vector3(float(chunk.WALL_X) - 20.0, 0.0, 1.0))
	wall_rest.set("active_character", "aster")
	wall_rest.call("_trigger", false)
	_check(not bool((chunk.call("get_preview_state") as Dictionary).get("complete", false)),
		"one runner at the wall cannot complete the chase")
	game_state.snap_character_to("peris", Vector3(float(chunk.WALL_X) + 2.0, 0.0, 1.0))
	wall_rest.set("active_character", "aster")
	wall_rest.call("_trigger", false)
	_check(bool((chunk.call("get_preview_state") as Dictionary).get("complete", false)),
		"both living runners at Endo's wall complete the chase without rally progress")


func _dispose(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nLOCKOUT PHYSICAL CHASE VERIFICATION: PASS")
		quit(0)
	else:
		push_error("LOCKOUT PHYSICAL CHASE VERIFICATION: %d failure(s)" % _failures.size())
		quit(1)
