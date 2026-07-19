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
	_check(float(contract.get("target_seconds_min", 0.0)) == 180.0
		and float(contract.get("target_seconds_max", 0.0)) == 300.0,
		"the chunk owns the central three-to-five-minute target")
	_check(shortest >= 180.0 and shortest <= 300.0,
		"shortest successful first clear is inside target (%.1fs)" % shortest)
	_check(clean >= 180.0 and clean <= 300.0,
		"health-preserving clean route is inside target (%.1fs)" % clean)
	_check(active >= 170.0 and ratio >= 0.70,
		"the model is meaningful traversal/work, not padding (%.1fs active, %.1f%%)" % [active, ratio * 100.0])
	_check(sprint_lower_bound >= 180.0 and sprint_lower_bound <= 300.0,
		"even an impossible continuous 6m/s sprint lower bound remains in target (%.1fs)" % sprint_lower_bound)
	_check(field_route >= 250.0,
		"exact shortest-path search yields a substantive three-loop field route (%.1fm)" % field_route)
	_check(int(contract.get("mandatory_action_count_clean", 0)) == 27
		and int(contract.get("mandatory_timed_action_count_clean", 0)) == 25
		and int(contract.get("station_marked_timed_action_count_clean", 0)) == 26,
		"clean first-clear measures 27 active inputs; Focus has 25 timed stations and physical marking has 26")
	_check(int(contract.get("mandatory_field_evidence_count", 0)) == 15,
		"fifteen non-repeating specialist reads are mandatory")
	_check(int(contract.get("decision_count", 0)) == 4
		and int(contract.get("branch_variant_count", 0)) == 16,
		"one route and three resource plans preserve sixteen valid outcomes")
	_check(str(contract.get("timing_basis", "")).contains("no dialogue, idle, or reset time counted"),
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
	_check(field_root != null, "three field loops live in a dedicated authored construction layer")
	_check(field_sites.size() == 27,
		"15 evidence, six plans, and six branch executions are real Interactables")
	_check(frames.size() == 3 and lights.size() == 3,
		"each operation has a measured portal hall and WebGL-safe landmark light")
	_check(datums.size() == 33,
		"continuous emissive measurement datums show every evidence and branch route")
	var decoration := chunk.find_child("LevelDecoration", true, false)
	var audit: Dictionary = decoration.get_meta("decoration_audit", {}) if decoration != null else {}
	_check(decoration != null and not audit.is_empty(),
		"the expanded corridor also uses the shared building-quality decoration pass")
	_check(int(audit.get("stations", 0)) >= 20,
		"shared facade decoration spans the full 284m shell (%d measured bays)" % int(audit.get("stations", 0)))
	_check(int(audit.get("instances", 0)) >= 400,
		"deterministic facade density supports the long route (%d instances)" % int(audit.get("instances", 0)))

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
	_check(timed == 27, "all field stations are click-gated timed actions")
	_check(outlined == 27, "all field stations bind their visible constructed object outline")
	_check(registered == 27, "all specialist requirements are authoritative in GameState")
	_check(int(role_counts["aster"]) >= 6 and int(role_counts["peris"]) >= 9 and int(role_counts["endo"]) >= 9,
		"fieldwork distributes substantive roles across Aster, Peris, and Endo")

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
	_check(str((chunk.call("get_preview_state") as Dictionary).get("fieldwork", {}).get("phase", "")) == "conduit",
		"crossing starts the conduit loop")

	var operation_order := ["conduit", "signal", "approach"]
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
				"%s unlocks both valid plans after five distinct reads" % operation_id)
		var committed_choice := str(operation.get("choices", [])[0])
		_complete_site(preview, chunk, committed_choice)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(committed_choice, ""))
		_check(field_sites[resolution_id].is_interaction_enabled(),
			"%s requires its chosen spatial execution station" % operation_id)
		_complete_site(preview, chunk, resolution_id)

	var state: Dictionary = chunk.call("get_preview_state")
	var field_state: Dictionary = state.get("fieldwork", {})
	_check(int(field_state.get("operation_count", 0)) == 3 and str(field_state.get("phase", "")) == "complete",
		"all three operations independently gate fieldwork completion")
	_check(str((field_state.get("effects", {}) as Dictionary).get("conduit_mode", "")) == "dry_service_brace"
		and str((field_state.get("effects", {}) as Dictionary).get("signal_mode", "")) == "living_memory"
		and str((field_state.get("effects", {}) as Dictionary).get("entry_mode", "")) == "warm_recovery",
		"the three committed resource outcomes persist to the refuge")
	_check((field_state.get("findings", []) as Array).size() == 21,
		"the completed path records fifteen reads, three plans, and three executions")

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
		"the risky crossing cannot skip the three active field loops")


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
