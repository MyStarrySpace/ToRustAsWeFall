extends Node

## Focused structural, gating, branch, and duration audit for Endo's Junction long-form pass.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_endo_junction_longform.tscn

const PREVIEW_SCENE := preload("res://scenes/fragments/endo_junction_stretch_preview.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	EventLog.print_events = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	var preview := await _spawn_preview()
	var chunk: Node = preview.find_child("Chunk_endo_junction_stretch", true, false) if preview != null else null
	_check(chunk != null, "Endo Junction boots in its shared playable preview")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return
	_verify_duration(chunk)
	_verify_environment(preview, chunk)
	_verify_initial_and_safe_gates(preview, chunk)
	_verify_direct_tradeoff(preview, chunk)
	await _dispose(preview)
	_finish()


func _spawn_preview() -> Node:
	var preview := PREVIEW_SCENE.instantiate()
	preview.set("suppress_scene_change", true)
	get_tree().root.add_child(preview)
	for _frame in range(14):
		await get_tree().process_frame
	return preview


func _verify_duration(chunk: Node) -> void:
	print("\n=== Endo Junction geometric duration contract ===")
	var contract: Dictionary = chunk.call("get_playtime_contract")
	var shortest := float(contract.get("modeled_shortest_first_clear_seconds", 0.0))
	var clean := float(contract.get("modeled_clean_first_clear_seconds", 0.0))
	var active := float(contract.get("modeled_meaningful_active_seconds", 0.0))
	var ratio := float(contract.get("modeled_active_ratio", 0.0))
	var sprint_lower_bound := float(contract.get("modeled_theoretical_full_sprint_seconds", 0.0))
	var field_route := float(contract.get("shortest_field_route_meters", 0.0))
	_check(float(contract.get("target_seconds_min", 0.0)) == 75.0
		and float(contract.get("target_seconds_max", 0.0)) == 150.0,
		"the compact quality pass owns a no-padding 75-to-150-second target")
	_check(shortest >= 75.0 and shortest <= 150.0,
		"shortest successful first clear is inside target (%.1fs)" % shortest)
	_check(clean >= 75.0 and clean <= 150.0,
		"health-preserving clean route is inside target (%.1fs)" % clean)
	_check(active >= 70.0 and ratio >= 0.70,
		"the model is meaningful traversal/work, not padding (%.1fs active, %.1f%%)" % [active, ratio * 100.0])
	_check(sprint_lower_bound >= 50.0 and sprint_lower_bound <= 150.0,
		"the impossible continuous-sprint bound still prices the authored work (%.1fs)" % sprint_lower_bound)
	_check(field_route >= 55.0,
		"exact shortest-path search prices the cross-lane specialist circuit (%.1fm)" % field_route)
	_check(int(contract.get("mandatory_action_count_clean", 0)) == 11
		and int(contract.get("mandatory_timed_action_count_clean", 0)) == 9
		and int(contract.get("station_marked_timed_action_count_clean", 0)) == 10,
		"clean first-clear is eleven active inputs instead of a twenty-seven-stop checklist")
	_check(int(contract.get("mandatory_field_evidence_count", 0)) == 3,
		"one non-repeating read from each specialist is mandatory")
	_check(int(contract.get("decision_count", 0)) == 2
		and int(contract.get("branch_variant_count", 0)) == 4,
		"the crossing and pulse prediction remain meaningful branch points")
	_check(str(contract.get("timing_basis", "")).contains("no dialogue, idle, failure, or reset time counted"),
		"the contract explicitly excludes dialogue, idle, and failure padding")
	print("  INFO: shortest %.1fs | clean %.1fs | full-sprint bound %.1fs | active %.1f%% | field route %.1fm | safe route %.1fm" % [
		shortest, clean, sprint_lower_bound, ratio * 100.0, field_route, float(contract.get("safe_route_meters", 0.0)),
	])


func _verify_environment(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction building-quality construction ===")
	var field_root := chunk.find_child("EndoJunctionFieldwork", true, false)
	var field_sites := chunk.find_children("EndoJunctionField_*", "Interactable", true, false)
	var frames := chunk.find_children("EndoJunctionFieldFrame_*", "Node3D", true, false)
	var lights := chunk.find_children("EndoJunctionFieldLight_*", "OmniLight3D", true, false)
	var datums := chunk.find_children("EndoJunctionDatum_*", "MeshInstance3D", true, false)
	var authored_set := chunk.find_child("EndoJunctionAuthoredPulseCircuit", true, false)
	var cadence_player := chunk.find_child("CircuitAnimation", true, false) as AnimationPlayer
	_check(field_root != null and authored_set != null,
		"the pulse junction is a dedicated reusable scene asset, not seven generated posts")
	_check(cadence_player != null and cadence_player.has_animation("cadence"),
		"the pressure and root response are authored as a visible AnimationPlayer cadence")
	_check(field_sites.size() == 7,
		"three evidence objects, two predictions, and two physical executions are real Interactables")
	_check(frames.size() == 1 and lights.size() == 1,
		"the single reasoning beat has one measured hall and one landmark light")
	_check(datums.size() == 9,
		"continuous emissive datums show the evidence chain and both predicted outcomes")
	var decoration := chunk.find_child("LevelDecoration", true, false)
	var audit: Dictionary = decoration.get_meta("decoration_audit", {}) if decoration != null else {}
	_check(decoration != null and not audit.is_empty(),
		"the expanded corridor also uses the shared building-quality decoration pass")
	_check(int(audit.get("stations", 0)) >= 8,
		"shared facade decoration spans the compact 114m shell (%d measured bays)" % int(audit.get("stations", 0)))
	_check(int(audit.get("instances", 0)) >= 150,
		"deterministic facade density supports the authored route (%d instances)" % int(audit.get("instances", 0)))

	var role_counts := {"aster": 0, "peris": 0, "endo": 0}
	var timed := 0
	var outlined := 0
	var registered := 0
	var gs = preview.get("_game_state")
	for site in field_sites:
		var role := str(site.get("required_character"))
		if role_counts.has(role):
			role_counts[role] += 1
		if int(site.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed += 1
		if site.get("_outline_target") != null:
			outlined += 1
		var data_id := str(site.get("data_id"))
		if gs != null and data_id != "" and gs.has_interactable(data_id):
			var registered_spec: Dictionary = gs.get_interactable(data_id)
			if str(registered_spec.get("required_character", "")) == role:
				registered += 1
	_check(timed == 7, "all circuit stations are click-gated timed actions")
	_check(outlined == 7, "all circuit stations outline their authored object assemblies")
	_check(registered == 7, "all specialist requirements are authoritative in GameState")
	_check(int(role_counts["aster"]) == 1 and int(role_counts["peris"]) == 3 and int(role_counts["endo"]) == 3,
		"the causal chain gives every specialist a distinct load-bearing read")

	var legacy_nodes := [
		chunk.find_child("EndoJunctionReadInteractable", true, false),
		chunk.find_child("EndoJunctionRouteMarkInteractable", true, false),
		chunk.find_child("EndoJunctionCacheInteractable", true, false),
		chunk.find_child("EndoJunctionSafeRouteInteractable", true, false),
		chunk.find_child("EndoJunctionDirectRouteInteractable", true, false),
		chunk.find_child("EndoJunctionShortcutInteractable", true, false),
		chunk.find_child("EndoJunctionShelterInteractable", true, false),
	]
	var legacy_timed := 0
	var legacy_outlined := 0
	for node in legacy_nodes:
		if node != null and int(node.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			legacy_timed += 1
		if node != null and node.get("_outline_target") != null:
			legacy_outlined += 1
	_check(legacy_timed == 6 and legacy_outlined == 7,
		"the original junction keeps its instant click read while all six physical work stations are timed and all seven are outlined")


func _verify_initial_and_safe_gates(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction evidence, planning, and execution gates ===")
	var field_sites: Dictionary = chunk.get("_field_sites")
	var initially_enabled := 0
	for site in field_sites.values():
		if site.is_interaction_enabled():
			initially_enabled += 1
	_check(initially_enabled == 0, "fieldwork stays locked until the first crossing resolves")

	_move_and_call(preview, chunk, "endo", chunk.JUNCTION_POS, "read_junction", "Endo reads the junction")
	_move_and_call(preview, chunk, "aster", chunk.GUIDE_MARK_POS, "mark_safe_route", "Aster marks the safe ledge")
	preview.call("headless_select_character", "endo")
	preview.call("headless_set_character_position", "endo", chunk.SAFE_LEDGE_POS)
	_check(not bool(chunk.call("commit_safe_route")),
		"the route cannot abandon the only food cache")
	_move_and_call(preview, chunk, "endo", chunk.FORAGE_CACHE_POS, "collect_forage", "Endo recovers the cache")
	_move_and_call(preview, chunk, "endo", chunk.SAFE_LEDGE_POS, "commit_safe_route", "Endo commits the clean crossing")
	_check(str((chunk.call("get_preview_state") as Dictionary).get("fieldwork", {}).get("phase", "")) == "pulse",
		"crossing starts the pulse circuit")

	var operation_order := ["pulse"]
	for operation_id in operation_order:
		var operation: Dictionary = chunk.FIELD_OPERATIONS[operation_id]
		for choice_id in operation.get("choices", []):
			_check(not field_sites[str(choice_id)].is_interaction_enabled(),
				"%s planning stays locked before evidence" % operation_id)

		var first_evidence_id := str(operation.get("evidence", [])[0])
		var first_spec: Dictionary = chunk.FIELD_SITES[first_evidence_id]
		var first_site: Node = field_sites[first_evidence_id]
		var wrong := "aster" if str(first_spec.get("role", "")) != "aster" else "peris"
		first_site.set("active_character", wrong)
		first_site.call("_trigger", false)
		var rejected_state: Dictionary = chunk.call("get_preview_state")
		var rejected_evidence: Dictionary = (rejected_state.get("fieldwork", {}) as Dictionary).get("completed_evidence", {})
		_check(not bool((rejected_evidence.get(operation_id, {}) as Dictionary).get(first_evidence_id, false)),
			"%s rejects the wrong specialist without consuming work" % first_evidence_id)

		for evidence_id_variant in operation.get("evidence", []):
			_complete_site(preview, chunk, str(evidence_id_variant))
		for choice_id in operation.get("choices", []):
			_check(field_sites[str(choice_id)].is_interaction_enabled(),
				"%s unlocks both predictions after three distinct reads" % operation_id)
		var committed_choice := str(operation.get("presented_choice", ""))
		_complete_site(preview, chunk, committed_choice)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(committed_choice, ""))
		_check(field_sites[resolution_id].is_interaction_enabled(),
			"%s requires its chosen spatial execution station" % operation_id)
		_complete_site(preview, chunk, resolution_id)

	var state: Dictionary = chunk.call("get_preview_state")
	var field_state: Dictionary = state.get("fieldwork", {})
	_check(int(field_state.get("operation_count", 0)) == 1 and str(field_state.get("phase", "")) == "complete",
		"the one causal circuit gates fieldwork completion")
	_check(str((field_state.get("effects", {}) as Dictionary).get("conduit_mode", "")) == "living_root_buffer"
		and bool((field_state.get("effects", {}) as Dictionary).get("pulse_resolved", false)),
		"the successful intervention persists as a visible quiet-lane state")
	_check((field_state.get("findings", []) as Array).size() == 5,
		"the clean path records three reads, one prediction, and one observed consequence")

	_move_and_call(preview, chunk, "endo", chunk.SHORTCUT_LOCK_POS, "unlock_shortcut", "Endo opens the return grate")
	preview.call("headless_select_character", "aster")
	preview.call("headless_set_character_position", "aster", chunk.SHELTER_POS)
	_check(not bool(chunk.call("reach_shelter")),
		"one character entering Shelter 1 cannot trigger a proximity-only night skip")
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) != "complete" and not bool(state.get("shelter_rested", false)),
		"the incomplete party leaves the long-form route active")
	var atp_before := {}
	for char_id in ["aster", "peris", "endo"]:
		preview.call("headless_set_character_position", char_id, chunk.SHELTER_POS)
		atp_before[char_id] = float(preview.call("get_preview_character_stat", char_id, "atp"))
	_check(bool(chunk.call("reach_shelter")),
		"the full conscious party can spend resources to rest at Shelter 1")
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "complete"
		and bool(state.get("shelter_rested", false)),
		"the long-form clean route reaches the original completion contract")
	for char_id in ["aster", "peris", "endo"]:
		_check(is_equal_approx(
			float(preview.call("get_preview_character_stat", char_id, "atp")),
			float(atp_before[char_id]) - chunk.SHELTER_ATP_COST
		), "%s pays one ATP for the authored first night" % char_id.capitalize())


func _verify_direct_tradeoff(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction direct-route tradeoff ===")
	chunk.call("reset_preview_state")
	_move_and_call(preview, chunk, "endo", chunk.JUNCTION_POS, "read_junction", "direct route still begins with Endo's read")
	preview.call("headless_select_character", "aster")
	preview.call("headless_set_character_position", "aster", chunk.RISKY_BLOOM_POS)
	_check(not bool(chunk.call("commit_direct_route")),
		"direct route also preserves the mandatory food preparation")
	_move_and_call(preview, chunk, "endo", chunk.FORAGE_CACHE_POS, "collect_forage", "direct route recovers the cache")
	chunk.call("_clear_dialogue")
	_move_and_call(preview, chunk, "aster", chunk.RISKY_BLOOM_POS, "commit_direct_route", "party cuts the direct bloom")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("route_choice", "")) == "direct"
		and float(state.get("direct_damage_total", 0.0)) > 0.0
		and float(state.get("party_min_hp", 0.0)) > 0.0,
		"direct stays shorter and recoverable but spends real health")
	preview.call("headless_select_character", "endo")
	preview.call("headless_set_character_position", "endo", chunk.SHORTCUT_LOCK_POS)
	_check(not bool(chunk.call("unlock_shortcut")),
		"the risky crossing cannot skip the active pulse circuit")


func _move_and_call(preview: Node, chunk: Node, character_id: String, position: Vector3,
		method_name: String, label: String) -> void:
	preview.call("headless_select_character", character_id)
	preview.call("headless_set_character_position", character_id, position)
	_check(bool(chunk.call(method_name)), label)


func _complete_site(preview: Node, chunk: Node, site_id: String) -> void:
	var spec: Dictionary = chunk.FIELD_SITES[site_id]
	var role := str(spec.get("role", ""))
	preview.call("headless_select_character", role)
	preview.call("headless_set_character_position", role, spec.get("pos", Vector3.ZERO))
	_check(bool(chunk.call("complete_field_site", site_id)), "%s completes %s" % [role.capitalize(), site_id])


func _dispose(preview: Node) -> void:
	if preview != null and is_instance_valid(preview):
		preview.set_process(false)
		preview.set_physics_process(false)
		if preview.has_method("_teardown_sequence"):
			preview.call("_teardown_sequence")
		preview.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nEndo Junction long-form verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nEndo Junction long-form verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
