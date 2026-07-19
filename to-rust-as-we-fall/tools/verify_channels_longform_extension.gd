extends Node

## Focused structural, gameplay-gate, and duration audit for the long-form Channels pass.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_channels_longform_extension.tscn

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")

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
	var act1 := await _spawn_channels()
	if act1 == null:
		_failures.append("Act 1 Channels instance boots")
		_finish()
		return
	_verify_structure_and_duration(act1)
	_verify_operation_gates(act1)
	_verify_optional_exploration(act1)
	await _dispose(act1)
	_finish()


func _spawn_channels() -> Node:
	var act1 := ACT1_SCENE.instantiate()
	act1.set("start_chunk", "channels")
	act1.set("suppress_scene_change", true)
	get_tree().root.add_child(act1)
	for _frame in range(10):
		await get_tree().process_frame
	return act1


func _verify_structure_and_duration(act1: Node) -> void:
	print("\n=== Channels long-form structure and duration ===")
	var field_root := act1.find_child("ChannelsFieldwork", true, false)
	_check(field_root != null, "Channels owns a dedicated long-form fieldwork layer")
	_check(act1.find_children("ChannelsField_*", "Interactable", true, false).size() == 52,
		"30 evidence sites, 12 decisions, 4 branch executions, and 6 optional findings are real Interactables")
	_check(act1.find_children("ChannelsFieldFrame_*", "Node3D", true, false).size() == 6,
		"all six operations have measured structural frames")
	_check(act1.find_children("ChannelsFieldLight_*", "OmniLight3D", true, false).size() == 6,
		"each operation has a WebGL-safe authored landmark light")
	var landmark_root := act1.find_child("ChannelsOperationLandmarks", true, false)
	_check(landmark_root != null, "Channels owns a dedicated operation-landmark layer")
	_check(act1.find_children("ChannelsLandmarkRoom_*", "Node3D", true, false).size() == 6,
		"all six operations have a distinct macro-scale hydraulic landmark")
	_check(act1.find_children("ChannelsLandmarkWater_*", "MeshInstance3D", true, false).size() >= 12,
		"operation landmarks visibly connect the main race to local basins")
	_check(act1.find_children("ChannelsLandmarkSilhouette_*", "MeshInstance3D", true, false).size() >= 24,
		"operation landmarks carry substantial, differentiated silhouettes")
	_check(act1.find_children("ChannelsLandmarkLabel_*", "Label3D", true, false).size() == 6,
		"each hydraulic room names its operation at landmark scale")
	_check(landmark_root == null or landmark_root.find_children("*", "CollisionShape3D", true, false).is_empty(),
		"macro landmarks preserve the authored traversal and interaction clearance")
	_check(act1.find_children("ChannelsFieldDatum_*", "MeshInstance3D", true, false).size() >= 46,
		"continuous emissive measurement datums connect evidence and decision branches")
	_check(act1.find_child("LevelDecoration", true, false) != null,
		"the fieldwork remains inside the shared building-quality LevelDecorator pass")

	var role_counts := {"aster": 0, "peris": 0, "endo": 0}
	var timed_actions := 0
	var outlined := 0
	var registered_roles := 0
	var routed_requests := 0
	for node in act1.find_children("ChannelsField_*", "Interactable", true, false):
		var role := str(node.get("required_character"))
		if role_counts.has(role):
			role_counts[role] += 1
		if int(node.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_actions += 1
		if node.get("_outline_target") != null:
			outlined += 1
		if node.interaction_requested.get_connections().size() >= 2:
			routed_requests += 1
		var data_id := str(node.get("data_id"))
		if data_id != "" and act1._game_state.has_interactable(data_id):
			var registered: Dictionary = act1._game_state.get_interactable(data_id)
			if str(registered.get("required_character", "")) == role:
				registered_roles += 1
	_check(timed_actions == 52, "every field station is a click-gated timed action")
	_check(outlined == 52, "every visible field instrument binds object-level outline feedback")
	_check(registered_roles == 52, "every specialist requirement is authoritative in GameState (got %d/52)" % registered_roles)
	_check(routed_requests == 52, "every station routes its specialist and regroups the party through the shared controller")
	_check(int(role_counts["aster"]) >= 12 and int(role_counts["peris"]) >= 12 and int(role_counts["endo"]) >= 10,
		"fieldwork distributes substantive reads across Aster, Peris, and Endo")

	var contract: Dictionary = act1.get_channels_playtime_contract()
	var first_clear := float(contract.get("modeled_first_clear_seconds", 0.0))
	var meaningful_active := float(contract.get("meaningful_active_seconds", 0.0))
	var route_meters := float(contract.get("shortest_field_route_meters", 0.0))
	var active_ratio := float(contract.get("modeled_active_ratio", 0.0))
	_check(first_clear >= 1200.0, "modeled shortest first clear reaches twenty minutes (%.1fs)" % first_clear)
	_check(first_clear <= 1800.0, "modeled shortest first clear stays inside thirty minutes (%.1fs)" % first_clear)
	_check(meaningful_active >= 1200.0,
		"meaningful active play itself reaches the canonical twenty-minute floor (%.1fs)" % meaningful_active)
	_check(route_meters >= 1100.0, "exact shortest-route search still yields a substantive field route (%.1fm)" % route_meters)
	_check(active_ratio >= 0.70, "modeled meaningful-active ratio clears the pacing floor (%.1f%%)" % (active_ratio * 100.0))
	_check(int(contract.get("mandatory_operation_count", 0)) == 6, "the contract measures all six operations")
	_check(int(contract.get("mandatory_evidence_count", 0)) == 30, "the contract measures thirty unique evidence actions")
	_check(int(contract.get("mandatory_resolution_action_count", 0)) == 2,
		"both consequential resource branches require a distinct execution action")
	_check(int(contract.get("decision_count", 0)) >= 6, "at least six planning/timing decisions remain in the first clear")
	_check(int(contract.get("branch_count", 0)) >= 3, "recovery and pressure tradeoffs exceed the three-branch target")
	print("  INFO: modeled first clear %.1fs, active %.1f%%, exact field route %.1fm" % [
		first_clear, active_ratio * 100.0, route_meters,
	])


func _verify_operation_gates(act1: Node) -> void:
	print("\n=== Channels evidence and decision gates ===")
	act1._scheduler.clear()
	act1._dialogue.clear()
	var operation_order := ["intake", "memory", "harvest", "relay", "signal", "escape"]
	for operation_id in operation_order:
		act1._scheduler.clear()
		act1._dialogue.clear()
		act1._start_channels_field_operation(operation_id)
		var operation: Dictionary = act1.CHANNELS_FIELD_OPERATIONS[operation_id]
		_check(str(act1._current_step) == str(operation.get("step", "")),
			"%s enters its own player-controlled step" % operation_id)
		var evidence: Array = operation.get("evidence", [])
		var choices: Array = operation.get("choices", [])
		for choice_id in choices:
			var early_choice: Node = act1._channels_field_sites[str(choice_id)]
			_check(not early_choice.is_interaction_enabled(),
				"%s choice stays disabled before evidence" % operation_id)

		# GameState, not just the view, rejects the wrong specialist at the first site.
		var first_id := str(evidence[0])
		var first_site: Node = act1._channels_field_sites[first_id]
		var first_spec: Dictionary = act1.CHANNELS_FIELD_SITES[first_id]
		var required := str(first_spec.get("role", ""))
		var wrong := "peris" if required != "peris" else "aster"
		first_site.set("active_character", wrong)
		first_site.call("_trigger", false)
		var phase_state: Dictionary = (act1.headless_get_state().get("channels_fieldwork", {}) as Dictionary)
		var completed_by_operation: Dictionary = phase_state.get("completed_evidence", {})
		_check(not bool((completed_by_operation.get(operation_id, {}) as Dictionary).get(first_id, false)),
			"%s rejects the wrong specialist without consuming evidence" % first_id)

		for evidence_id_variant in evidence:
			var evidence_id := str(evidence_id_variant)
			var site: Node = act1._channels_field_sites[evidence_id]
			var spec: Dictionary = act1.CHANNELS_FIELD_SITES[evidence_id]
			site.set("active_character", str(spec.get("role", "")))
			site.call("_trigger", false)
		for choice_id in choices:
			var unlocked_choice: Node = act1._channels_field_sites[str(choice_id)]
			_check(unlocked_choice.is_interaction_enabled(),
				"%s unlocks decisions only after all five distinct reads" % operation_id)

		var valid_choices: Array = operation.get("valid_choices", [])
		var invalid_choice := ""
		for choice_id in choices:
			if not valid_choices.has(choice_id):
				invalid_choice = str(choice_id)
				break
		if invalid_choice != "":
			var invalid_site: Node = act1._channels_field_sites[invalid_choice]
			invalid_site.set("active_character", str(act1.CHANNELS_FIELD_SITES[invalid_choice].get("role", "")))
			invalid_site.call("_trigger", false)
			_check(str(act1._channels_field_phase) == operation_id,
				"%s keeps an evidence-conflicting answer in the operation" % operation_id)
			_check(int(act1._channels_field_attempts.get(operation_id, 0)) == 1,
				"%s records the rejected inference without adding a wait/reset timer" % operation_id)

		var valid_choice := str(valid_choices[0])
		var valid_site: Node = act1._channels_field_sites[valid_choice]
		valid_site.set("active_character", str(act1.CHANNELS_FIELD_SITES[valid_choice].get("role", "")))
		valid_site.call("_trigger", false)
		var resolution_sites: Dictionary = operation.get("resolution_sites", {})
		if resolution_sites.has(valid_choice):
			var pending_state: Dictionary = (act1.headless_get_state().get("channels_fieldwork", {}) as Dictionary)
			_check(not bool((pending_state.get("operations_completed", {}) as Dictionary).get(operation_id, false)),
				"%s does not resolve from a menu choice alone" % operation_id)
			var resolution_id := str(resolution_sites[valid_choice])
			var resolution_site: Node = act1._channels_field_sites[resolution_id]
			_check(resolution_site.is_interaction_enabled(),
				"%s opens its chosen spatial execution branch" % operation_id)
			resolution_site.set("active_character", str(act1.CHANNELS_FIELD_SITES[resolution_id].get("role", "")))
			resolution_site.call("_trigger", false)
		var field_state: Dictionary = (act1.headless_get_state().get("channels_fieldwork", {}) as Dictionary)
		_check(bool((field_state.get("operations_completed", {}) as Dictionary).get(operation_id, false)),
			"%s resolves through a supported evidence decision" % operation_id)
		_check(str((field_state.get("choices", {}) as Dictionary).get(operation_id, "")) == valid_choice,
			"%s preserves its committed outcome" % operation_id)

	var final_field_state: Dictionary = (act1.headless_get_state().get("channels_fieldwork", {}) as Dictionary)
	_check(int(final_field_state.get("operation_count", 0)) == 6,
		"all six long-form operations are independently completion-gated")
	_check(int(final_field_state.get("decision_count", 0)) == 6,
		"the completed play path records six explicit field decisions")
	_check(str((final_field_state.get("choices", {}) as Dictionary).get("harvest", "")) == "harvest_reserve",
		"the harvest resource allocation survives later operations")
	_check(str((final_field_state.get("choices", {}) as Dictionary).get("relay", "")) == "relay_pressure",
		"the relay pressure tradeoff survives later operations")


func _verify_optional_exploration(act1: Node) -> void:
	print("\n=== Channels optional return reads ===")
	act1._scheduler.clear()
	act1._dialogue.clear()
	act1._start_channels_explore()
	var optional_nodes := []
	for site_id in act1.CHANNELS_OPTIONAL_SITES.keys():
		var site: Node = act1._channels_field_sites[str(site_id)]
		optional_nodes.append(site)
		_check(site.is_interaction_enabled(), "%s opens only in post-shelter exploration" % site_id)
	var first_optional: Node = optional_nodes[0]
	var optional_id := str(act1.CHANNELS_OPTIONAL_SITES.keys()[0])
	first_optional.set("active_character", str(act1.CHANNELS_OPTIONAL_SITES[optional_id].get("role", "")))
	first_optional.call("_trigger", false)
	var state: Dictionary = (act1.headless_get_state().get("channels_fieldwork", {}) as Dictionary)
	_check(int(state.get("optional_count", 0)) == 1,
		"optional exploration records a finding without gating the Stacks exit")
	_check(str(act1._current_step) == "channels_explore", "an optional read leaves campaign progression under player control")


func _dispose(act1: Node) -> void:
	if act1 != null and is_instance_valid(act1):
		act1.set_process(false)
		act1.set_physics_process(false)
		if act1.has_method("_teardown_sequence"):
			act1._teardown_sequence()
		act1.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("Channels long-form extension verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("Channels long-form extension verification: %d FAILED" % _failures.size())
		get_tree().quit(1)
