extends SceneTree

## Focused structural and authored-path verification for Mother Flure.
## The 5-8 minute band is a human first-clear playtest target; this verifier
## refuses to make an honest mechanical workload pass it by inventing reasoning.
##
## Run with:
##   godot --headless --path . --script \
##     res://tools/verify_mother_flure_quality_extension.gd

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


func _drive_source(preview: Node, source: Node, actor: String) -> bool:
	if not is_instance_valid(source):
		return false
	preview.headless_select_character(actor)
	preview.headless_set_character_position(actor, (source as Node3D).global_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _drive_terminal(
	preview: Node, chunk: Node, terminal_id: String
) -> bool:
	return _drive_source(
		preview, chunk._terminal_interactables.get(terminal_id), "aster"
	)


func _drive_portal(preview: Node, chunk: Node) -> bool:
	var source: Node = (
		chunk._portal_entry_interactable
		if str(chunk.get_preview_state().get("peris_remote_terminal", "")) == ""
		else chunk._portal_return_interactable
	)
	return _drive_source(preview, source, "peris")


func _drive_root(
	preview: Node, chunk: Node, root_id: String, direction: int
) -> bool:
	return _drive_source(
		preview,
		chunk._root_control_interactables.get(
			chunk._root_control_key(root_id, direction)
		),
		"peris"
	)


func _execute_root_move(preview: Node, chunk: Node, move: Dictionary) -> bool:
	if not _drive_terminal(preview, chunk, str(move.get("terminal", ""))):
		return false
	if not _drive_portal(preview, chunk):
		return false
	preview.headless_advance(chunk.PORTAL_TRANSIT_SECONDS + 0.01, 0.05)
	if not _drive_root(
		preview,
		chunk,
		str(move.get("root", "")),
		int(move.get("direction", 0))
	):
		return false
	preview.headless_advance(5.5, 0.05)
	if not bool(chunk.get_preview_state().get("portal_open", false)):
		if not _drive_terminal(preview, chunk, str(move.get("terminal", ""))):
			return false
	if not _drive_portal(preview, chunk):
		return false
	preview.headless_advance(chunk.PORTAL_TRANSIT_SECONDS + 0.01, 0.05)
	return str(chunk.get_preview_state().get("peris_remote_terminal", "")) == ""


func _move_character(preview: Node, character_id: String, destination: Vector3) -> bool:
	preview.headless_select_character(character_id)
	if not bool(preview.headless_move_character(character_id, destination, false)):
		return false
	var movement: Dictionary = preview.headless_get_character_movement_info(character_id)
	preview.headless_advance(float(movement.get("duration", 0.0)) + 0.1, 0.05)
	return not bool(preview.headless_is_character_moving(character_id))


func _move_caretaker_route(
	preview: Node,
	chunk: Node,
	from: Vector3,
	destination: Vector3
) -> bool:
	for waypoint in chunk.get_caretaker_carry_route(from, destination):
		if not _move_character(preview, "endo", Vector3(waypoint)):
			return false
	return true


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

	_verify_honest_contract(chunk)
	_verify_environment_and_causal_evidence(chunk)
	_verify_interaction_structure(chunk)
	await _verify_canonical_solve(preview, chunk)
	await _verify_wrong_repair_recovery(preview, chunk)

	await _dispose(preview)
	_finish()


func _verify_honest_contract(chunk: Node) -> void:
	print("\n=== Mother Flure honest workload contract ===")
	var contract: Dictionary = chunk.get_playtime_contract()
	var mechanical := float(contract.get("modeled_mechanical_workload_seconds", -1.0))
	var category_total := 0.0
	for seconds in (contract.get("category_seconds", {}) as Dictionary).values():
		category_total += float(seconds)
	_check(float(contract.get("human_first_clear_target_min_seconds", 0.0)) == 300.0
		and float(contract.get("human_first_clear_target_max_seconds", 0.0)) == 480.0,
		"5-8 minutes is retained as the human first-clear playtest target")
	_check(str(contract.get("human_first_clear_target_basis", "")) == "playtest_only",
		"the target is explicitly playtest-only rather than an analyzer claim")
	_check(mechanical > 0.0 and mechanical < 300.0,
		"the deterministic model reports its actual sub-five-minute mechanical workload (%.1fs)" % mechanical)
	_check(is_equal_approx(float(contract.get("modeled_first_clear_seconds", -2.0)), mechanical)
		and is_equal_approx(float(contract.get("meaningful_active_seconds", -3.0)), mechanical)
		and is_equal_approx(float(contract.get("total_play_seconds", -4.0)), mechanical),
		"mechanical, active, and elapsed totals share one unfabricated duration")
	_check(is_equal_approx(category_total, mechanical),
		"named mechanical categories sum exactly to the reported workload")
	_check(float(contract.get("modeled_reasoning_seconds", -1.0)) == 0.0
		and float(contract.get("hard_idle_lock_seconds", -1.0)) == 0.0
		and float(contract.get("root_settle_seconds_counted", -1.0)) == 0.0,
		"the model invents no reasoning, idle, dialogue, or root-settle padding")
	_check(int(contract.get("mandatory_diagnostic_clicks", -1)) == 0
		and int(contract.get("mandatory_care_node_clicks", -1)) == 0,
		"removed evidence checklists and care chores contribute zero clicks")
	_check(int(contract.get("branch_count", 0)) == chunk.REPAIR_POINT_ORDER.size(),
		"the three physical repair hypotheses remain the modeled branch set")
	print("  INFO: %.1fs mechanical workload; 300-480s remains a human observation target" % mechanical)


func _verify_environment_and_causal_evidence(chunk: Node) -> void:
	print("\n=== Mother Flure environment and causal evidence ===")
	_check(chunk.BOARD_ROWS.size() == 6 and chunk.BOARD_CELL_SIZE > 0.0,
		"the canonical board remains a 6x6 spatial system")
	_check(chunk._roots.size() == chunk.ROOT_ORDER.size() and chunk._roots.size() == 10,
		"all ten authored roots remain on the board")
	var board_valid := true
	for root_id in chunk.ROOT_ORDER:
		var root_state: Dictionary = chunk._roots.get(root_id, {})
		board_valid = board_valid and root_state.get("node") is MeshInstance3D
		board_valid = board_valid and root_state.get("swarm_node") is MeshInstance3D
		for cell in chunk._root_cells(root_state):
			board_valid = board_valid and cell.x >= 0 and cell.x < 6 and cell.y >= 0 and cell.y < 6
	_check(board_valid,
		"root bodies and their delayed siderophore mats occupy valid board cells")
	_check(chunk.ROOT_SWARM_LAG > 0.0
		and chunk.ROOT_SWARM_DURATION > 0.0
		and chunk.ROOT_HAZARD_DAMAGE > 0.0,
		"the siderophore-follow movement hazard remains authored and damaging")

	var evidence: Node = chunk.get_node_or_null("MotherPhysicalRepairEvidence")
	_check(evidence != null, "the chamber owns a physical repair-evidence hierarchy")
	_check(evidence != null and int(evidence.get_meta("clicks_required", -1)) == 0
		and evidence.find_children("*", "Interactable", true, false).is_empty(),
		"freight, wear, and caretaker evidence requires no extra verb or click")
	for evidence_name in [
		"FreightWearNorth", "FreightWearCenter", "FreightWearSouth",
		"CenterSocketWearNorth", "CenterSocketWearSouth",
		"EdgeReliefDustSeal", "BloomBypassRootFilm",
		"CaretakerTorqueGauge", "CaretakerCenterBrace",
	]:
		_check(evidence != null and evidence.get_node_or_null(evidence_name) != null,
			"%s communicates the repair model in physical space" % evidence_name)

	var decoration: Node = chunk.get_node_or_null("MotherFlureDecoration")
	_check(decoration != null, "the chamber retains its dedicated decoration hierarchy")
	var audit: Dictionary = decoration.get_meta("decoration_audit", {}) if decoration != null else {}
	_check(int(audit.get("instances", 0)) >= 150 and int(audit.get("lights", 0)) >= 12,
		"the facade, trusses, gutters, conduits, and nave retain their authored density")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		"the decoration remains collision-free and does not obstruct navigation")
	for family in ["WallBays", "CeilingTrusses", "BoardGutters", "ServiceConduits", "MotherNave"]:
		_check(decoration != null and decoration.get_node_or_null(family) != null,
			"the %s decoration family remains present" % family)


func _verify_interaction_structure(chunk: Node) -> void:
	print("\n=== Mother Flure canonical interaction structure ===")
	_check(not chunk.has_method("inspect_diagnostic")
		and not chunk.has_method("prime_care_node")
		and chunk.find_child("*DiagnosticInteractable", true, false) == null
		and chunk.find_child("*CareInteractable", true, false) == null,
		"the six-read checklist and choose-three care circuit are absent")
	var state: Dictionary = chunk.get_preview_state()
	_check(not state.has("diagnostics_completed")
		and not state.has("care_nodes_primed")
		and not state.has("care_circuit_ready"),
		"removed chores no longer leak into the public preview state")

	var term_alpha: Node = chunk.find_child("*AlphaInteractable", true, false)
	var term_beta: Node = chunk.find_child("*BetaInteractable", true, false)
	var term_gamma: Node = chunk.find_child("*GammaInteractable", true, false)
	_check(term_alpha != null
		and int(term_alpha.get("interactable_type")) == Interactable.InteractableType.INSPECTION,
		"the first portal terminal preserves click-arrival onboarding")
	_check(term_beta != null and term_gamma != null
		and int(term_beta.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and int(term_gamma.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"the later portal controls remain deliberate terminal actions")
	_check(int(chunk._portal_entry_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and int(chunk._portal_return_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"both portal directions retain calibrated crossing interactions")
	_check(ItemData.get_hand_slots("mother_gear") == 2
		and not ItemData.can_endocytose("mother_gear"),
		"Mother Gear remains a physical two-hand carry object")
	_check(chunk._repair_interactables.size() == 3,
		"all three spatial repair hypotheses remain available")
	for repair_id in chunk.REPAIR_POINT_ORDER:
		var repair: Node = chunk._repair_interactables.get(repair_id)
		_check(repair is Interactable
			and str(repair.get("required_character")) == "endo"
			and int(repair.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
			"%s is an Endo-operated physical mount" % repair_id)
	_check(chunk._mother_interactable is Interactable
		and str(chunk._mother_interactable.get("required_character")) == "peris"
		and int(chunk._mother_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"Peris's final tending remains a visible authored interaction")
	_check(chunk._exit_interactable is Interactable
		and int(chunk._exit_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION
		and is_equal_approx(float(chunk._exit_interactable.get("dwell_time")), chunk.EXIT_HANDOFF_SECONDS),
		"the Rings handoff remains the visible final interaction")
	_check(not _interactable_enabled(chunk._mother_interactable)
		and not _interactable_enabled(chunk._exit_interactable),
		"tending and exit begin sealed behind their actual causal prerequisites")


func _verify_canonical_solve(preview: Node, chunk: Node) -> void:
	print("\n=== Mother Flure canonical solve ===")
	for move_index in range(3):
		_check(_execute_root_move(preview, chunk, chunk.CLEAN_ROOT_MOVES[move_index]),
			"root move %d completes through terminal, portal, and service bay" % (move_index + 1))
		if move_index == 1:
			preview.headless_select_character("endo")
			preview.headless_set_character_position("endo", chunk.GEAR_POS)
			_check(_drive_source(preview, chunk._gear_interactable, "endo"),
				"Endo lifts the two-hand gear once the west pocket is open")
	var state: Dictionary = chunk.get_preview_state()
	_check((state.get("terminal_readings_seen", []) as Array).size() == 3,
		"using the three portal controls naturally exposes all live readings")
	_check(str(state.get("diagnosis", "")).contains("center spindle"),
		"the live readings converge with the physical wear on the center hypothesis")
	var endo_hp_before_carry := float(preview.get_preview_character_stat("endo", "hp"))
	_check(_move_caretaker_route(
		preview, chunk, chunk.GEAR_POS,
		chunk._repair_point_position("load_regulator")),
		"Endo can follow the south caretaker pass to the repair array")
	_check(float(preview.get_preview_character_stat("endo", "hp")) == endo_hp_before_carry,
		"the marked carry pass avoids the live siderophore mats without immunity")
	_check(_interactable_enabled(chunk._repair_interactables["load_regulator"]),
		"an open carry lane and held gear enable repair without a checklist gate")
	_check(_drive_source(
		preview, chunk._repair_interactables["load_regulator"], "endo"),
		"the load regulator accepts the Mother Gear")
	_check(not _interactable_enabled(chunk._mother_interactable),
		"the correct repair alone does not bypass the still-blocked mother lane")
	for move_index in range(3, chunk.CLEAN_ROOT_MOVES.size()):
		_check(_execute_root_move(preview, chunk, chunk.CLEAN_ROOT_MOVES[move_index]),
			"root move %d completes the east-side unwind" % (move_index + 1))
	state = chunk.get_preview_state()
	_check(bool(state.get("mother_lane_clear", false)),
		"the canonical 6x6 solution clears the mother lane end to end")
	_check(_interactable_enabled(chunk._mother_interactable),
		"correct repair plus a clear lane immediately enables Peris's tend—no chores")
	_check(_drive_source(preview, chunk._mother_interactable, "peris"),
		"Peris tends Mother Flure directly once the causal prerequisites hold")
	state = chunk.get_preview_state()
	_check(bool(state.get("mother_tended", false))
		and str(state.get("route_phase", "")) == "opening"
		and str(state.get("rings_gate_phase", "")) == chunk.RINGS_GATE_PHASE_OPENING
		and not bool(state.get("exit_open", true))
		and not bool(state.get("complete", true)),
		"tending produces the bloom reveal and starts—but does not skip—the physical Rings opening")
	var bloom_bright := true
	for material in chunk._mother_bloom_materials:
		bloom_bright = bloom_bright and material.emission_energy_multiplier >= 0.9
	_check(bloom_bright, "Mother's authored blooms visibly brighten after Peris tends her")
	_check(not _interactable_enabled(chunk._exit_interactable),
		"the Rings handoff stays disabled while its membrane is moving")
	_check(not _drive_source(preview, chunk._exit_interactable, "peris"),
		"the opening membrane cannot be treated as an already-open handoff")
	preview.headless_advance(chunk.RINGS_GATE_OPEN_SECONDS + 0.01, 0.05)
	state = chunk.get_preview_state()
	_check(str(state.get("route_phase", "")) == "handoff"
		and str(state.get("rings_gate_phase", "")) == chunk.RINGS_GATE_PHASE_OPEN
		and bool(state.get("exit_open", false))
		and _interactable_enabled(chunk._exit_interactable),
		"the visible Rings handoff enables only after the membrane reaches its open endpoint")
	_check(not chunk.complete_exit_handoff(),
		"the opened handoff still cannot be completed remotely from Mother Flure")
	for exit_entry in [
		["aster", Vector3(-0.8, 0.0, 0.0)],
		["peris", Vector3.ZERO],
		["endo", Vector3(0.8, 0.0, 0.0)],
	]:
		preview.headless_set_character_position(
			str(exit_entry[0]), chunk.EXIT_POS + Vector3(exit_entry[1])
		)
	_check(_drive_source(preview, chunk._exit_interactable, "aster"),
		"the gathered conscious party can operate the reachable Rings handoff")
	state = chunk.get_preview_state()
	_check(bool(state.get("complete", false))
		and bool(state.get("exit_reached", false))
		and not bool(state.get("exit_open", true))
		and not _interactable_enabled(chunk._exit_interactable),
		"the final state exposes and seals the common chunk-completion contract")


func _verify_wrong_repair_recovery(preview: Node, chunk: Node) -> void:
	print("\n=== Mother Flure recoverable wrong hypothesis ===")
	chunk.reset_preview_state()
	for character_id in ["aster", "peris", "endo"]:
		preview.headless_set_character_position(character_id, Vector3(chunk.SPAWNS[character_id]))
		preview.set_preview_character_stat(character_id, "hp", 100.0)
	for move_index in range(3):
		_check(_execute_root_move(preview, chunk, chunk.CLEAN_ROOT_MOVES[move_index]),
			"recovery setup root move %d completes" % (move_index + 1))
		if move_index == 1:
			preview.headless_select_character("endo")
			preview.headless_set_character_position("endo", chunk.GEAR_POS)
			_check(_drive_source(preview, chunk._gear_interactable, "endo"),
				"the recovery run lifts the Mother Gear")
	var recovery_hp_before_carry := float(preview.get_preview_character_stat("endo", "hp"))
	_check(_move_caretaker_route(
		preview, chunk, chunk.GEAR_POS,
		chunk._repair_point_position("edge_relief")),
		"Endo can carry the gear safely to the wrong repair hypothesis")
	_check(_drive_source(preview, chunk._repair_interactables["edge_relief"], "endo"),
		"the plausible edge-relief misconception commits and visibly rejects")
	var state: Dictionary = chunk.get_preview_state()
	var item_id := str(state.get("gear_item", ""))
	var item_state: Dictionary = preview.get_preview_item_state(item_id)
	var recovery_position := Vector3(item_state.get("position", Vector3.ZERO))
	_check(not bool(state.get("gear_installed", true))
		and (state.get("repair_attempts", []) as Array).has("edge_relief")
		and str(item_state.get("location", "")) == "ground"
		and recovery_position.distance_to(chunk.HIDE_SPOT_POS) <= 4.0,
		"failure falsifies the edge hypothesis and kicks the gear to the caretaker alcove")
	_check(_move_caretaker_route(
		preview, chunk, chunk._repair_point_position("edge_relief"),
		recovery_position),
		"the same physical pass reaches the rejected gear at the caretaker alcove")
	_check(float(preview.get_preview_character_stat("endo", "hp")) == recovery_hp_before_carry,
		"wrong-repair recovery stays safe through route knowledge, not immunity")
	_check(_drive_source(preview, chunk._gear_interactable, "endo"),
		"Endo can recover the rejected gear without a reset")
	_check(_execute_root_move(preview, chunk, {
		"terminal": "term_alpha",
		"root": "spine_gate",
		"direction": -1,
	}), "the party can reopen the carry lane changed by the rejected mount")
	_check(_move_caretaker_route(
		preview, chunk, recovery_position,
		chunk._repair_point_position("load_regulator")),
		"Endo can carry the recovered gear back to the center mount")
	_check(_interactable_enabled(chunk._repair_interactables["load_regulator"])
		and _drive_source(
			preview, chunk._repair_interactables["load_regulator"], "endo"),
		"the same run recovers to the evidence-supported load-regulator repair")


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
