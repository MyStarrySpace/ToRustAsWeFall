extends Node

## Focused structural, pacing-analyzer, normal-input, and branch audit for Stacks and Rings.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_stacks_rings_longform.tscn

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const PacingContract := preload("res://scripts/generation/level_pacing_contract.gd")
const MANIFEST_PATH := "res://data/pacing/level_targets.json"

var _failures: Array[String] = []
var _manifest: Dictionary = {}


func _ready() -> void:
	EventLog.print_events = false
	_manifest = _load_manifest()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _run() -> void:
	if _manifest.is_empty():
		_failures.append("pacing manifest loads")
		_finish()
		return
	await _verify_district("stacks")
	await _verify_district("rings")
	_finish()


func _verify_district(district: String) -> void:
	var act1 := await _spawn_act1(district)
	_check(act1 != null, "%s boots in the Act 1 campaign host" % district.capitalize())
	if act1 == null:
		return
	_verify_contract(act1, district)
	_verify_structure(act1, district)
	_verify_gates_and_branches(act1, district)
	await _dispose(act1)


func _spawn_act1(district: String) -> Node:
	var act1 := ACT1_SCENE.instantiate()
	act1.set("start_chunk", district)
	act1.set("suppress_scene_change", true)
	get_tree().root.add_child(act1)
	for _frame in range(14):
		await get_tree().process_frame
	return act1


func _verify_contract(act1: Node, district: String) -> void:
	print("\n=== %s standardized pacing contract ===" % district.capitalize())
	var contract: Dictionary = act1.call("get_%s_playtime_contract" % district)
	var target: Dictionary = PacingContract.target_by_id(_manifest, district)
	var report: Dictionary = PacingContract.analyze(target, contract, _manifest.get("rules", {}))
	var active := float(contract.get("meaningful_active_seconds", 0.0))
	var total := float(contract.get("total_play_seconds", 0.0))
	var ratio := active / maxf(total, 0.001)
	_check(bool(report.get("passed", false)),
		"%s passes the shared analyzer (%s)" % [district.capitalize(), str(report.get("errors", []))])
	_check(active >= 240.0 and active <= 360.0,
		"meaningful active play is inside 240-360s (%.1fs)" % active)
	_check(total >= 240.0 and total <= 360.0,
		"elapsed first clear is inside 240-360s (%.1fs)" % total)
	_check(ratio >= 0.70,
		"active ratio clears 70%% (%.1f%%)" % (ratio * 100.0))
	_check(float(contract.get("max_dead_gap_seconds", 99.0)) <= 5.0,
		"maximum dead gap stays at or below five seconds")
	_check(float(contract.get("max_single_mode_seconds", 99.0)) <= 45.0,
		"maximum uninterrupted mode stays at or below 45 seconds")
	var categories: Dictionary = contract.get("category_seconds", {})
	var category_sum := 0.0
	var maximum_category := 0.0
	for value in categories.values():
		category_sum += float(value)
		maximum_category = maxf(maximum_category, float(value))
	_check(absf(category_sum - active) <= 0.01,
		"category totals exactly equal meaningful active play")
	_check(maximum_category <= 120.0,
		"no activity category exceeds 120s (max %.1fs)" % maximum_category)
	_check(int(contract.get("decision_count", 0)) >= 2
		and int(contract.get("branch_count", 0)) >= 2,
		"at least two decisions and two persistent branches remain")
	_check(int(contract.get("mandatory_field_evidence_count", 0)) == 12
		and int(contract.get("mandatory_field_action_count", 0)) == 16,
		"contract measures twelve reads and sixteen total field actions")
	_check(str(contract.get("timing_basis", "")).contains("dialogue presentation is inactive"),
		"passive presentation cannot satisfy the active-play floor")
	print("  INFO: active %.1fs | elapsed %.1fs | ratio %.1f%% | legacy route %.1fm | field route %.1fm | field work %.1fs" % [
		active, total, ratio * 100.0,
		float(contract.get("legacy_route_meters", 0.0)),
		float(contract.get("field_route_meters", 0.0)),
		float(contract.get("field_work_seconds", 0.0)),
	])


func _verify_structure(act1: Node, district: String) -> void:
	print("\n=== %s fieldwork construction ===" % district.capitalize())
	var prefix := district.capitalize()
	var chunk := act1.find_child("Chunk_%s" % district, true, false)
	var field_root := act1.find_child("%sFieldwork" % prefix, true, false)
	var sites := act1.find_children("%sField_*" % prefix, "Interactable", true, false)
	var frames := act1.find_children("%sFieldFrame_*" % prefix, "Node3D", true, false)
	var lights := act1.find_children("%sFieldLight_*" % prefix, "OmniLight3D", true, false)
	var datums := act1.find_children("%sFieldDatum_*" % prefix, "MeshInstance3D", true, false)
	_check(chunk != null and field_root != null,
		"%s owns a dedicated fieldwork layer inside its campaign chunk" % prefix)
	_check(sites.size() == 20,
		"twelve evidence, four plans, and four executions are real Interactables")
	_check(frames.size() == 2 and lights.size() == 2,
		"two measured operation frames each carry a WebGL-safe landmark light")
	_check(datums.size() == 24,
		"twenty-four deterministic route datums expose every evidence and branch line")
	_check(chunk != null and chunk.find_child("LevelDecoration", true, false) != null,
		"fieldwork remains inside the shared building-quality decoration pass")

	var timed := 0
	var outlined := 0
	var routed := 0
	var registered := 0
	var gs = act1.get("_game_state")
	var role_counts := {"aster": 0, "peris": 0, "endo": 0}
	for site in sites:
		if int(site.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed += 1
		if site.get("_outline_target") != null:
			outlined += 1
		if site.interaction_requested.get_connections().size() >= 2:
			routed += 1
		var role := str(site.get("required_character"))
		if role_counts.has(role):
			role_counts[role] += 1
		var data_id := str(site.get("data_id"))
		if gs != null and data_id != "" and gs.has_interactable(data_id):
			var registered_spec: Dictionary = gs.get_interactable(data_id)
			if str(registered_spec.get("required_character", "")) == role:
				registered += 1
	_check(timed == 20, "every district field station is a click-gated timed action")
	_check(outlined == 20, "every station binds its visible constructed-object outline")
	_check(routed == 20, "every click uses the normal movement request and party regroup path")
	_check(registered == 20, "all specialist gates are authoritative in GameState")
	if district == "stacks":
		_check(int(role_counts["aster"]) >= 6 and int(role_counts["peris"]) >= 5 and int(role_counts["endo"]) >= 5,
			"Stacks gives all three specialists substantive work")
	else:
		_check(int(role_counts["aster"]) >= 9 and int(role_counts["peris"]) >= 9 and int(role_counts["endo"]) == 0,
			"Rings preserves Endo's departure while Aster and Peris share the residential work")


func _verify_gates_and_branches(act1: Node, district: String) -> void:
	print("\n=== %s evidence and branch gates ===" % district.capitalize())
	var operations: Dictionary = act1.STACKS_FIELD_OPERATIONS if district == "stacks" else act1.RINGS_FIELD_OPERATIONS
	var specs: Dictionary = act1.STACKS_FIELD_SITES if district == "stacks" else act1.RINGS_FIELD_SITES
	var site_nodes: Dictionary = act1.get("_stacks_field_sites") if district == "stacks" else act1.get("_rings_field_sites")
	var operation_order := ["identity", "egress"] if district == "stacks" else ["residence", "boundary"]
	act1.call("_start_district_field_operation", district, operation_order[0])

	for operation_index in range(operation_order.size()):
		var operation_id: String = operation_order[operation_index]
		var operation: Dictionary = operations[operation_id]
		var state: Dictionary = act1.call("headless_get_state")
		var district_state: Dictionary = state.get(district, {})
		var field_state: Dictionary = district_state.get("fieldwork", {})
		_check(str(field_state.get("phase", "")) == operation_id,
			"%s enters its own player-controlled operation" % operation_id)
		for choice_id in operation.get("choices", []):
			_check(not site_nodes[str(choice_id)].is_interaction_enabled(),
				"%s plans stay locked before evidence" % operation_id)

		var first_id := str(operation.get("evidence", [])[0])
		var first_spec: Dictionary = specs[first_id]
		var wrong := "peris" if str(first_spec.get("role", "")) != "peris" else "aster"
		act1.call("headless_select_character", wrong)
		site_nodes[first_id].call("_trigger", false)
		state = act1.call("headless_get_state")
		field_state = (state.get(district, {}) as Dictionary).get("fieldwork", {})
		_check(not bool(((field_state.get("completed_evidence", {}) as Dictionary).get(operation_id, {}) as Dictionary).get(first_id, false)),
			"%s rejects the wrong specialist without consuming evidence" % first_id)

		for evidence_id_variant in operation.get("evidence", []):
			var evidence_id := str(evidence_id_variant)
			var spec: Dictionary = specs[evidence_id]
			act1.call("headless_select_character", str(spec.get("role", "")))
			site_nodes[evidence_id].call("_trigger", false)
		for choice_id in operation.get("choices", []):
			_check(site_nodes[str(choice_id)].is_interaction_enabled(),
				"%s unlocks both plans only after six reads" % operation_id)

		var choice_index := operation_index % 2
		var choice_id := str(operation.get("choices", [])[choice_index])
		var choice_spec: Dictionary = specs[choice_id]
		act1.call("headless_select_character", str(choice_spec.get("role", "")))
		site_nodes[choice_id].call("_trigger", false)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
		_check(site_nodes[resolution_id].is_interaction_enabled(),
			"%s requires the selected spatial execution branch" % operation_id)
		var resolution_spec: Dictionary = specs[resolution_id]
		act1.call("headless_select_character", str(resolution_spec.get("role", "")))
		site_nodes[resolution_id].call("_trigger", false)

	var state: Dictionary = act1.call("headless_get_state")
	var field_state: Dictionary = (state.get(district, {}) as Dictionary).get("fieldwork", {})
	_check(int(field_state.get("operation_count", 0)) == 2
		and int(field_state.get("decision_count", 0)) == 2,
		"both operations and both explicit decisions persist")
	_check((field_state.get("choices", {}) as Dictionary).size() == 2
		and (field_state.get("effects", {}) as Dictionary).size() >= 3,
		"both branch selections persist through their physical executions")
	_check(str(state.get("current_step", "")) == "%s_explore" % district,
		"second execution rejoins the preserved district transition")
	var snapshot: Dictionary = act1.call("build_save_snapshot")
	var district_snapshot: Dictionary = (snapshot.get("act1", {}) as Dictionary).get("%s_state" % district, {})
	_check((district_snapshot.get("field_choices", {}) as Dictionary).size() == 2
		and (district_snapshot.get("field_effects", {}) as Dictionary).size() >= 3,
		"branch choices and consequences survive the save snapshot")


func _dispose(act1: Node) -> void:
	if act1 != null and is_instance_valid(act1):
		act1.set_process(false)
		act1.set_physics_process(false)
		if act1.has_method("_teardown_sequence"):
			act1.call("_teardown_sequence")
		act1.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nStacks/Rings long-form verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nStacks/Rings long-form verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
