extends SceneTree

## Focused structural, canonical pacing, and normal-input-gate verification for
## the long-form Inflammashunt. Run with:
##   godot --headless --path . --script res://tools/verify_inflammashunt_longform.gd
##
## This deliberately uses one real fragment-preview instance and no screenshots,
## render readbacks, or duplicate live scenes, keeping the dummy renderer out of
## the verification path while retaining GameState's authoritative input guards.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _trigger(chunk: Node, node_name: String, role: String) -> bool:
	var interactable: Node = chunk.find_child(node_name, true, false)
	if interactable == null:
		_check(false, "%s exists" % node_name)
		return false
	interactable.set("active_character", role)
	interactable.call("_trigger", false)
	return true


func _is_enabled(node: Node) -> bool:
	return node != null and bool(node.get("interaction_enabled"))


func _run() -> void:
	var packed := load("res://scenes/fragments/fragment_preview.tscn") as PackedScene
	_check(packed != null, "the shared fragment preview scene loads")
	if packed == null:
		_finish()
		return
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "inflammashunt")
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	var chunk: Node = preview.find_child("Chunk_inflammashunt", true, false)
	_check(chunk != null, "the Inflammashunt chunk builds in the real preview host")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return

	_verify_canonical_pacing(chunk)
	_verify_environment_and_interactables(chunk, preview)
	_verify_authored_gate_playthrough(chunk, preview)

	await _dispose(preview)
	_finish()


func _verify_canonical_pacing(chunk: Node) -> void:
	print("\n=== Inflammashunt canonical meaningful-active pacing ===")
	var contract: Dictionary = chunk.get_playtime_contract()
	var active := float(contract.get("meaningful_active_seconds", 0.0))
	var total := float(contract.get("total_play_seconds", 0.0))
	var route := float(contract.get("critical_route_meters", 0.0))
	var traversal := float(contract.get("modeled_traversal_seconds", 0.0))
	var work := float(contract.get("modeled_interaction_work_seconds", 0.0))
	print("  INFO: route %.3fm, traversal %.3fs, click-gated work %.3fs" % [route, traversal, work])
	print("  INFO: meaningful active %.3fs, total %.3fs, active ratio %.2f%%" % [
		active, total, 100.0 * float(contract.get("active_ratio", 0.0))])
	print("  INFO: categories %s" % str(contract.get("category_seconds", {})))
	_check(active >= 420.0 and active <= 540.0,
		"meaningful active play lands in the explicit 7-9 minute band (%.3fs)" % active)
	_check(is_equal_approx(active, traversal + work),
		"active play is exactly authored traversal plus click-gated work")
	_check(float(contract.get("active_ratio", 0.0)) >= 0.70,
		"the active ratio clears the canonical 70% floor")
	_check(float(contract.get("max_dead_gap_seconds", INF)) <= 5.0,
		"the route contains no dead gap over five seconds")
	_check(float(contract.get("max_single_mode_seconds", INF)) <= 45.0,
		"no uninterrupted traversal or work mode exceeds 45 seconds")
	_check(float(contract.get("dialogue_seconds_in_model", -1.0)) == 0.0
		and float(contract.get("idle_padding_seconds", -1.0)) == 0.0
		and float(contract.get("platform_fallback_seconds", -1.0)) == 0.0,
		"dialogue, idle padding, and platform fallbacks contribute no claimed duration")
	_check(int(contract.get("decision_count", 0)) >= 5
		and int(contract.get("branch_count", 0)) >= 3,
		"the standardized decision and branch floors are exceeded")
	var category_sum := 0.0
	for category_name in (contract.get("category_seconds", {}) as Dictionary):
		var seconds := float((contract["category_seconds"] as Dictionary)[category_name])
		category_sum += seconds
		_check(seconds <= 210.0,
			"%s stays below the 210-second category cap (%.3fs)" % [category_name, seconds])
	_check(absf(category_sum - active) <= maxf(0.5, active * 0.005),
		"mutually exclusive pacing categories sum to meaningful active play")

	var manifest_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/pacing/level_targets.json"))
	var manifest: Dictionary = manifest_variant if manifest_variant is Dictionary else {}
	var target := LevelPacingContract.target_by_id(manifest, "inflammashunt")
	var report := LevelPacingContract.analyze(target, contract,
		manifest.get("rules", {}) as Dictionary)
	if not bool(report.get("passed", false)):
		print("  INFO: analyzer errors %s" % str(report.get("errors", [])))
	_check(bool(report.get("passed", false)),
		"LevelPacingContract.analyze passes the production Inflammashunt metrics")


func _verify_environment_and_interactables(chunk: Node, preview: Node) -> void:
	print("\n=== Inflammashunt building-quality gallery ===")
	var gallery: Node = chunk.get_node_or_null("CommissioningGallery")
	_check(gallery != null, "the commissioning run owns a dedicated environment hierarchy")
	var environment_audit: Dictionary = gallery.get_meta("environment_audit", {}) if gallery != null else {}
	_check(int(environment_audit.get("protocol_frames", 0)) == 4,
		"four measured protocol frames divide the service spine")
	_check(int(environment_audit.get("station_count", 0)) == 37,
		"the gallery audit covers all 37 authored stations")
	_check(int(environment_audit.get("measurement_datums", 0)) >= 23,
		"continuous and transverse measurement datums establish scale")
	_check(int(environment_audit.get("collision_shapes", -1)) == 0
		and bool(environment_audit.get("deterministic", false)),
		"gallery dressing is deterministic and explicitly collision-free")
	for family in ["ProtocolFrames", "MeasurementDatums", "CommissioningInstruments"]:
		_check(gallery != null and gallery.get_node_or_null(family) != null,
			"the %s hierarchy is present" % family)
	for protocol_index in range(4):
		_check(chunk.find_child("ProtocolFrame_%02d_*" % (protocol_index + 1), true, false) != null,
			"protocol frame %d has measured columns, beam, label, and light" % (protocol_index + 1))

	var decoration: Node = chunk.get_node_or_null("LevelDecoration")
	var decoration_audit: Dictionary = chunk.get_decoration_audit()
	_check(decoration != null, "the shared building-quality LevelDecorator pass is present")
	_check(int(decoration_audit.get("instances", 0)) >= 180,
		"facade, hydraulic services, trim, wear, and datums contribute a dense authored field")
	_check(int(decoration_audit.get("collision_shapes", -1)) == 0
		and str(decoration_audit.get("clearance", "")) == "surface_only_no_obstacles",
		"LevelDecorator adds no route collision")
	var grid: Dictionary = chunk.get_grid_data()
	_check(int(grid.get("width", 0)) == 150,
		"the unified grid spans the full 225m authored branch")
	var extraction_cell := Vector2i(int(floor(chunk.EXTRACTION_POS.x / 1.5)),
		int(floor((chunk.EXTRACTION_POS.z + 16.5) / 1.5)))
	var extraction_walkable := false
	for cell_variant in grid.get("walkable_cells", []) as Array:
		var cell: Array = cell_variant
		if int(cell[0]) == extraction_cell.x and int(cell[1]) == extraction_cell.y:
			extraction_walkable = true
			break
	_check(extraction_walkable, "the extraction cradle sits on authoritative walkable grid data")

	var sites: Array = chunk.find_children("Commissioning_*", "Interactable", true, false)
	_check(sites.size() == 37, "37 commissioning objects are real Interactables")
	var timed_count := 0
	var outlined_count := 0
	var authoritative_roles := 0
	var initially_disabled := 0
	for site in sites:
		if int(site.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_count += 1
		if site.get("_outline_target") != null:
			outlined_count += 1
		var data_id := str(site.get("data_id"))
		if data_id != "" and preview._game_state.has_interactable(data_id):
			var registered: Dictionary = preview._game_state.get_interactable(data_id)
			if str(registered.get("required_character", "")) == str(site.get("required_character")):
				authoritative_roles += 1
		if not _is_enabled(site):
			initially_disabled += 1
	_check(timed_count == 37, "every new player action is click-gated TIMED_ACTION work")
	_check(outlined_count == 37, "every station outlines its visible apparatus")
	_check(authoritative_roles == 37, "every specialist role is authoritative in GameState")
	_check(initially_disabled == 37, "commissioning cannot start before catalyst retrieval")
	var clean_plan: Array = chunk.get_commissioning_clean_action_plan()
	_check(clean_plan.size() == 29,
		"the clean route contains 20 reads, four decisions, four executions, and extraction")
	var clean_requires_myke := false
	for action_variant in clean_plan:
		if str((action_variant as Dictionary)["role"]) == "myke":
			clean_requires_myke = true
	_check(not clean_requires_myke,
		"Aster+Peris can complete the commissioning shadow route without Myke")
	_check(str(chunk._commissioning_sites["buffer_dry_burn_lane"].get("required_character")) == "myke"
		and str(chunk._commissioning_sites["buffer_wet_lane"].get("required_character")) == "aster",
		"Myke's burn lane and the shadow pair's wet lane remain genuinely distinct branches")


func _verify_authored_gate_playthrough(chunk: Node, preview: Node) -> void:
	print("\n=== Inflammashunt authored normal-input gate path ===")
	for read in [
		["AsterLogTerminal", "aster"], ["PipeDiagram", "aster"],
		["DeadRootNetwork", "peris"], ["LivingJunction", "peris"],
		["GrateObservation", "myke"], ["DeviceGap", "myke"],
	]:
		_trigger(chunk, str(read[0]), str(read[1]))
	for action in [
		["DrainageValve", "aster"], ["CharDepositA", "myke"],
		["CharDepositB", "myke"], ["RootTendril", "peris"],
		["DeviceHousing", "aster"],
	]:
		_trigger(chunk, str(action[0]), str(action[1]))
	var state: Dictionary = chunk.headless_get_state()
	_check(bool(state.get("device_retrieved", false)),
		"the original informed water-clean-clean-tend-open solve still retrieves the device")
	_check(not bool(state.get("commissioning_complete", true))
		and str(state.get("commissioning_phase", "")) == "coolant",
		"retrieval opens the first commissioning loop rather than falsely completing the level")
	_check(_is_enabled(chunk._commissioning_sites["coolant_inlet_trace"]),
		"only the first ordered evidence station lights after retrieval")
	_check(not _is_enabled(chunk._commissioning_sites["coolant_root_sample"])
		and not _is_enabled(chunk._commissioning_sites["return_capillary_sample"]),
		"later evidence and protocols remain state-gated")

	# Advancing gameplay time cannot make work happen on headless, desktop, or web.
	preview.headless_advance(20.0, 0.1)
	state = chunk.headless_get_state()
	_check((state.get("commissioning_completed_actions", []) as Array).is_empty()
		and str(state.get("commissioning_phase", "")) == "coolant",
		"twenty idle seconds produce no auto-completion or platform fallback")

	for protocol_id_variant in chunk.COMMISSIONING_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		var protocol: Dictionary = chunk.COMMISSIONING_PROTOCOLS[protocol_id]
		var evidence: Array = protocol["evidence"]
		for evidence_index in range(evidence.size()):
			var site_spec: Dictionary = evidence[evidence_index]
			var site_id := str(site_spec["id"])
			var site: Node = chunk._commissioning_sites[site_id]
			_check(_is_enabled(site), "%s becomes the one ordered evidence gate" % site_id)
			if evidence_index == 0:
				var before_count := (chunk.headless_get_state().get("commissioning_completed_actions", []) as Array).size()
				var wrong_role := "peris" if str(site_spec["role"]) != "peris" else "aster"
				site.set("active_character", wrong_role)
				site.call("_trigger", false)
				_check((chunk.headless_get_state().get("commissioning_completed_actions", []) as Array).size() == before_count,
					"%s rejects the wrong specialist in GameState" % site_id)
			_trigger(chunk, "Commissioning_%s" % site_id, str(site_spec["role"]))
		var choices: Array = protocol["choices"]
		_check(_is_enabled(chunk._commissioning_sites[str((choices[0] as Dictionary)["id"])])
			and _is_enabled(chunk._commissioning_sites[str((choices[1] as Dictionary)["id"])]),
			"%s exposes both strategies only after all five reads" % protocol_id)
		var chosen_id := str(chunk.COMMISSIONING_CLEAN_CHOICES[protocol_id])
		var other_id := ""
		for choice_variant in choices:
			var candidate := str((choice_variant as Dictionary)["id"])
			if candidate != chosen_id:
				other_id = candidate
		var chosen: Node = chunk._commissioning_sites[chosen_id]
		_trigger(chunk, "Commissioning_%s" % chosen_id, str(chosen.get("required_character")))
		_check(not _is_enabled(chunk._commissioning_sites[other_id]),
			"%s commits one spatial branch and disables the unused strategy" % protocol_id)
		var resolution_spec: Dictionary = (protocol["resolutions"] as Dictionary)[chosen_id]
		var resolution_id := str(resolution_spec["id"])
		_check(_is_enabled(chunk._commissioning_sites[resolution_id]),
			"%s enables its branch-specific execution rig" % chosen_id)
		_trigger(chunk, "Commissioning_%s" % resolution_id, str(resolution_spec["role"]))
		_check(bool((chunk.headless_get_state().get("commissioning_resolved", {}) as Dictionary).get(protocol_id, false)),
			"%s records a completed support loop" % protocol_id)

	_check(_is_enabled(chunk._extraction_it),
		"all four executions enable the final extraction cradle")
	_check(not bool(chunk.headless_get_state().get("commissioning_complete", true)),
		"the final carry remains a substantive action, not an automatic epilogue")
	_trigger(chunk, "Commissioning_extraction_cradle", "aster")
	state = chunk.headless_get_state()
	_check(bool(state.get("commissioning_complete", false))
		and str(state.get("current_step", "")) == "complete",
		"seating the catalyst completes the long-form level")
	_check((state.get("commissioning_completed_actions", []) as Array).size() == 29,
		"all 29 unique commissioning actions are recorded")
	_check((state.get("commissioning_choices", {}) as Dictionary).size() == 4,
		"all four evidence-backed strategy decisions persist in final state")


func _dispose(preview: Node) -> void:
	if preview != null and is_instance_valid(preview):
		if preview.has_method("_teardown_sequence"):
			preview._teardown_sequence()
		preview.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nInflammashunt long-form verification: ALL PASSED")
		quit(0)
	else:
		print("\nInflammashunt long-form verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		quit(1)
