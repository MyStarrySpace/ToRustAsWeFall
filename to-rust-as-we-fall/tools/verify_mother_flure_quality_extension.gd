extends SceneTree

## Focused structural, pacing, and full authored-path verification for Mother
## Flure. Run with:
##   godot --headless --path . --script res://tools/verify_mother_flure_quality_extension.gd

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _interactable_enabled(interactable: Node) -> bool:
	return interactable != null and bool(interactable.get("interaction_enabled"))


func _execute_root_move(preview: Node, chunk: Node, move: Dictionary) -> bool:
	preview.headless_select_character("aster")
	if not chunk.activate_terminal(str(move.get("terminal", ""))):
		return false
	preview.headless_select_character("peris")
	if not chunk.use_portal():
		return false
	if not chunk.activate_fragment_move(str(move.get("root", "")), int(move.get("direction", 0))):
		return false
	preview.headless_advance(5.5, 0.05)
	if not bool(chunk.get_preview_state().get("portal_open", false)):
		preview.headless_select_character("aster")
		if not chunk.activate_terminal(str(move.get("terminal", ""))):
			return false
		preview.headless_select_character("peris")
	return chunk.use_portal()


func _run() -> void:
	var packed := load("res://scenes/fragments/fragment_preview.tscn") as PackedScene
	_check(packed != null, "the shared fragment preview scene loads")
	if packed == null:
		_finish()
		return
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "mother_flure")
	root.add_child(preview)
	for _frame in range(8):
		await process_frame
	var chunk: Node = preview.find_child("Chunk_mother_flure", true, false)
	_check(chunk != null, "the Mother Flure chunk builds in the real preview host")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return

	print("\n=== Mother Flure pacing evidence ===")
	var contract: Dictionary = chunk.get_playtime_contract()
	var modeled_seconds := float(contract.get("modeled_first_clear_seconds", 0.0))
	_check(float(contract.get("required_first_clear_seconds", 0.0)) == 300.0,
		"the explicit first-clear floor is five minutes")
	_check(float(contract.get("target_max_seconds", 0.0)) == 480.0,
		"the explicit first-clear ceiling is eight minutes")
	_check(modeled_seconds >= 300.0 and modeled_seconds <= 480.0,
		"the geometry-and-work model lands inside the 5-8 minute band (%.1fs)" % modeled_seconds)
	_check(float(contract.get("modeled_meaningful_active_seconds", 0.0)) == modeled_seconds,
		"every modeled second is traversal or click-gated work")
	_check(float(contract.get("hard_idle_lock_seconds", -1.0)) == 0.0
		and float(contract.get("root_settle_seconds_counted", -1.0)) == 0.0,
		"dialogue, waiting, and root-settle animation contribute no claimed playtime")
	_check(float(contract.get("controlled_traversal_meters", 0.0)) >= 600.0,
		"the three-role route contains a materially long controlled traversal")
	_check(float(contract.get("modeled_interaction_work_seconds", 0.0)) >= 100.0,
		"the solve includes over 100 seconds of distinct interaction work")
	_check(int(contract.get("decision_count", 0)) >= 4
		and int(contract.get("branch_count", 0)) >= 7,
		"repair, care-route, board, and resource decisions expose real branches")
	var manifest_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/pacing/level_targets.json"))
	var manifest: Dictionary = manifest_variant if manifest_variant is Dictionary else {}
	var target: Dictionary = LevelPacingContract.target_by_id(manifest, "mother_flure")
	var pacing_report := LevelPacingContract.analyze(
		target,
		contract,
		manifest.get("rules", {}) as Dictionary
	)
	_check(bool(pacing_report.get("passed", false)),
		"the authored route passes the canonical Mother Flure pacing contract")
	print("  INFO: modeled clean first clear %.1fs across %.1fm" % [
		modeled_seconds,
		float(contract.get("controlled_traversal_meters", 0.0)),
	])

	print("\n=== Mother Flure environment quality ===")
	var decoration: Node = chunk.get_node_or_null("MotherFlureDecoration")
	_check(decoration != null, "the chamber owns a dedicated decoration hierarchy")
	var audit: Dictionary = decoration.get_meta("decoration_audit", {}) if decoration != null else {}
	_check(int(audit.get("instances", 0)) >= 150,
		"facade rhythm, trusses, gutters, conduits, and nave contribute at least 150 authored meshes")
	_check(int(audit.get("lights", 0)) >= 12,
		"repeated truss work lights keep the long chamber readable")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		"the decoration pass is explicitly collision-free")
	for family in ["WallBays", "CeilingTrusses", "BoardGutters", "ServiceConduits", "MotherNave"]:
		_check(decoration != null and decoration.get_node_or_null(family) != null,
			"the %s decoration family is present" % family)

	print("\n=== Mother Flure authored interaction path ===")
	_check(chunk._diagnostic_interactables.size() == 6,
		"six spatial evidence stations divide the diagnosis across all three roles")
	var role_counts := {"aster": 0, "peris": 0, "endo": 0}
	for diagnostic_id in chunk.DIAGNOSTIC_ORDER:
		var diagnostic: Node = chunk._diagnostic_interactables.get(diagnostic_id)
		_check(diagnostic is Interactable,
			"%s is a real Interactable" % diagnostic_id)
		if diagnostic == null:
			continue
		var required_character := str(diagnostic.get("required_character"))
		role_counts[required_character] = int(role_counts.get(required_character, 0)) + 1
		_check(int(diagnostic.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
			"%s is click-gated work rather than proximity dwell" % diagnostic_id)
		_check(is_equal_approx(float(diagnostic.get("dwell_time")), chunk.DIAGNOSTIC_WORK_SECONDS),
			"%s uses the authored evidence-review duration" % diagnostic_id)
		_check(diagnostic.get("_outline_target") != null,
			"%s binds its visible apparatus to outline feedback" % diagnostic_id)
	for character_id in ["aster", "peris", "endo"]:
		_check(int(role_counts.get(character_id, 0)) == 2,
			"%s owns exactly two diagnosis stations" % character_id.capitalize())

	_check(chunk._care_node_interactables.size() == 4,
		"four spatial capillary nodes support the choose-three care route")
	for node_id in chunk.CARE_NODE_ORDER:
		var care_node: Node = chunk._care_node_interactables.get(node_id)
		_check(care_node is Interactable
			and int(care_node.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
			and str(care_node.get("required_character")) == "peris",
			"%s is Peris-only click-gated care work" % node_id)
		_check(care_node != null and care_node.get("_outline_target") != null,
			"%s binds its visible root crown to outline feedback" % node_id)

	var term_alpha: Node = chunk.find_child("*AlphaInteractable", true, false)
	var term_beta: Node = chunk.find_child("*BetaInteractable", true, false)
	var term_gamma: Node = chunk.find_child("*GammaInteractable", true, false)
	_check(term_alpha != null and int(term_alpha.get("interactable_type")) == Interactable.InteractableType.INSPECTION,
		"the first terminal preserves the shared click-arrival onboarding contract")
	_check(term_beta != null and term_gamma != null
		and int(term_beta.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and int(term_gamma.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"the later terminal reconstructions are deliberate work actions")
	_check(int(chunk._portal_entry_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and int(chunk._portal_return_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"both portal directions require click-gated calibration")
	_check(int(chunk._gear_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and int(chunk._mother_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"gear lifting and final tending are substantive work interactions")
	_check(chunk._exit_interactable is Interactable
		and int(chunk._exit_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and is_equal_approx(float(chunk._exit_interactable.get("dwell_time")), chunk.EXIT_HANDOFF_SECONDS)
		and chunk._exit_interactable.get("_outline_target") != null,
		"the Rings handoff is a visible click-gated exit interaction")
	_check(not _interactable_enabled(chunk._exit_interactable),
		"the level exit stays sealed before Mother Flure is stabilized")

	var repair_positions: Array[Vector3] = []
	for repair_id in chunk.REPAIR_POINT_ORDER:
		repair_positions.append(chunk._repair_point_position(repair_id))
	var repair_targets_separated := true
	for first_index in range(repair_positions.size()):
		for second_index in range(first_index + 1, repair_positions.size()):
			repair_targets_separated = repair_targets_separated \
				and repair_positions[first_index].distance_to(repair_positions[second_index]) >= 5.0
	_check(repair_targets_separated,
		"the three repair click targets are spatially distinct instead of stacked")
	var repair_service_clear := true
	for repair_position in repair_positions:
		for terminal_id in chunk.TERMINAL_ORDER:
			var service_roots: Array = chunk.TERMINAL_SERVICES.get(terminal_id, [])
			for root_index in range(service_roots.size()):
				var row_position: Vector3 = chunk._service_row_position(terminal_id, root_index, service_roots.size())
				for direction in [-1, 1]:
					var bud_position := row_position + Vector3(-1.55 if direction < 0 else 1.55, 0.14, -0.48)
					repair_service_clear = repair_service_clear and repair_position.distance_to(bud_position) >= 3.5
	_check(repair_service_clear,
		"repair mounts no longer overlap the remote service-bay root controls")
	var floor_half_extents: Vector3 = Vector3(chunk.FLOOR_SIZE) * 0.5
	_check(absf(chunk.EXIT_POS.x - chunk.FLOOR_CENTER.x) <= floor_half_extents.x - chunk.EXIT_INTERACTION_RADIUS
		and absf(chunk.EXIT_POS.z - chunk.FLOOR_CENTER.z) <= floor_half_extents.z - chunk.EXIT_INTERACTION_RADIUS,
		"the Rings handoff interaction radius sits fully inside the playable chamber floor")

	# All six observations are genuinely required by the visible mount path.
	preview.headless_select_character("endo")
	_check(not chunk.install_gear_from_interaction("load_regulator"),
		"the visible repair path refuses an uninvestigated guess")
	for terminal_id in chunk.TERMINAL_ORDER:
		preview.headless_select_character("aster")
		_check(chunk.activate_terminal(terminal_id), "%s exposes its evidence pair" % terminal_id)
	preview.headless_select_character("peris")
	_check(not chunk.inspect_diagnostic("service_manifest"),
		"the wrong perspective cannot satisfy Aster's manifest read")
	for diagnostic_id in chunk.DIAGNOSTIC_ORDER:
		var def: Dictionary = chunk.DIAGNOSTIC_DEFS[diagnostic_id]
		preview.headless_select_character(str(def.get("character", "")))
		_check(chunk.inspect_diagnostic(diagnostic_id), "%s records its intended role read" % diagnostic_id)
	var state: Dictionary = chunk.get_preview_state()
	_check(bool(state.get("diagnosis_ready_for_repair", false))
		and int((state.get("diagnostics_completed", []) as Array).size()) == 6,
		"all six field reads unlock a stable repair diagnosis")

	# Execute the board's existing deterministic clean solution, but commit the
	# repair and final tend through the new authored gates.
	for move_index in range(3):
		_check(_execute_root_move(preview, chunk, chunk.CLEAN_ROOT_MOVES[move_index]),
			"root move %d completes through terminal, portal, and service bay" % (move_index + 1))
		if move_index == 1:
			preview.headless_select_character("endo")
			preview.headless_set_character_position("endo", chunk.GEAR_POS)
			_check(chunk.pick_up_gear(), "Endo lifts the two-hand gear after the west pocket opens")
	preview.headless_select_character("endo")
	preview.headless_set_character_position("endo", chunk._repair_point_position("load_regulator"))
	_check(_interactable_enabled(chunk._repair_interactables["load_regulator"]),
		"carrying the gear after six reads enables the repair choices")
	_check(chunk.install_gear_from_interaction("load_regulator"),
		"the diagnosed load-regulator interaction accepts the gear")
	for move_index in range(3, chunk.CLEAN_ROOT_MOVES.size()):
		_check(_execute_root_move(preview, chunk, chunk.CLEAN_ROOT_MOVES[move_index]),
			"root move %d completes the east-side unwind" % (move_index + 1))
	state = chunk.get_preview_state()
	_check(bool(state.get("mother_lane_clear", false)),
		"the original 6x6 board still clears end to end")
	_check(not _interactable_enabled(chunk._mother_interactable),
		"the mother remains gated until Peris chooses a care route")
	var first_care_id := str(chunk.CARE_NODE_ORDER[0])
	preview.headless_select_character("endo")
	_check(not chunk.prime_care_node(first_care_id),
		"Endo cannot substitute for Peris at a capillary node")
	preview.headless_select_character("peris")
	for node_index in range(chunk.CARE_NODE_REQUIRED_COUNT):
		var node_id := str(chunk.CARE_NODE_ORDER[node_index])
		preview.headless_set_character_position("peris", Vector3(chunk.CARE_NODE_DEFS[node_id].get("position", Vector3.ZERO)))
		_check(chunk.prime_care_node(node_id), "%s joins the clean capillary circuit" % node_id)
	state = chunk.get_preview_state()
	_check(bool(state.get("care_circuit_ready", false))
		and int((state.get("care_nodes_primed", []) as Array).size()) == 3,
		"any three capillary nodes complete the care route")
	_check(not _interactable_enabled(chunk._care_node_interactables[chunk.CARE_NODE_ORDER[3]]),
		"the unused fourth node stays a real route branch rather than mandatory busywork")
	_check(_interactable_enabled(chunk._mother_interactable),
		"the choose-three circuit enables the final tend interaction")
	preview.headless_set_character_position("peris", chunk.MOTHER_POS)
	_check(chunk.tend_mother_from_interaction(),
		"Peris stabilizes the mother through the fully authored path")
	state = chunk.get_preview_state()
	_check(bool(state.get("mother_tended", false))
		and str(state.get("route_phase", "")) == "handoff"
		and bool(state.get("exit_open", false))
		and not bool(state.get("complete", true)),
		"stabilizing Mother Flure opens a handoff without prematurely completing the level")
	_check(_interactable_enabled(chunk._exit_interactable),
		"the common exit gate becomes interactable only after the tend resolves")
	_check(not chunk.complete_exit_handoff(),
		"the exit state cannot be completed remotely from the mother interaction")
	preview.headless_set_character_position("peris", chunk.EXIT_POS)
	_check(chunk.complete_exit_handoff(),
		"a character can reach and operate the visible Rings handoff")
	state = chunk.get_preview_state()
	_check(str(state.get("route_phase", "")) == "complete"
		and bool(state.get("complete", false))
		and bool(state.get("exit_reached", false))
		and not bool(state.get("exit_open", true)),
		"the final chunk state exposes the common completion/exit contract")
	_check(not _interactable_enabled(chunk._exit_interactable),
		"the handoff disables after completion")

	await _dispose(preview)
	_finish()


func _dispose(preview: Node) -> void:
	if preview != null and is_instance_valid(preview):
		if preview.has_method("_teardown_sequence"):
			preview._teardown_sequence()
		preview.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nMother Flure quality extension verification: ALL PASSED")
		quit(0)
	else:
		print("\nMother Flure quality extension verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		quit(1)
