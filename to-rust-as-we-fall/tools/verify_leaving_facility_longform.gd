extends Node

## Focused structural, gameplay-gate, and honest-duration audit for the
## long-form Leaving Facility pass.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_leaving_facility_longform.tscn

const LEAVING_SCENE := preload("res://scenes/tutorial/leaving_facility.tscn")

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
	var sequence := LEAVING_SCENE.instantiate()
	sequence.set("suppress_scene_change", true)
	get_tree().root.add_child(sequence)
	for _frame in range(10):
		await get_tree().process_frame

	_verify_duration_contract(sequence)
	_verify_fieldwork_structure(sequence)
	_verify_sequential_protocol_gate(sequence)
	_verify_measurement_language(sequence)

	sequence.queue_free()
	await get_tree().process_frame
	_finish()


func _verify_duration_contract(sequence: Node) -> void:
	print("\n=== Leaving Facility honest first-clear model ===")
	var contract: Dictionary = sequence.get_playtime_contract()
	var target: Vector2 = contract.get("target_first_clear_seconds", Vector2.ZERO)
	var total := float(contract.get("modeled_shortest_clean_first_clear_seconds", 0.0))
	var active := float(contract.get("modeled_meaningful_active_seconds", 0.0))
	var ratio := float(contract.get("modeled_active_ratio", 0.0))
	var traversal := float(contract.get("modeled_traversal_seconds", 0.0))
	var interaction := float(contract.get("modeled_mandatory_interaction_seconds", 0.0))
	var route := float(contract.get("shortest_field_route_meters", 0.0))
	print("  route: %.3f m" % route)
	print("  traversal: %.3f s" % traversal)
	print("  mandatory interaction: %.3f s" % interaction)
	print("  meaningful active: %.3f s" % active)
	print("  shortest clean first clear: %.3f s (%.2f min)" % [total, total / 60.0])
	print("  active ratio: %.2f%%" % (ratio * 100.0))

	_check(target.is_equal_approx(Vector2(240.0, 360.0)),
		"contract matches the central 4-6 minute first-clear target")
	_check(total >= target.x and total <= target.y,
		"modeled shortest clean first clear lands inside target (%.3f s)" % total)
	_check(active >= 240.0,
		"the target is met by meaningful traversal and click-gated work alone (%.3f s)" % active)
	_check(ratio >= 0.70,
		"meaningful active ratio clears 70%% (%.2f%%)" % (ratio * 100.0))
	_check(route >= 380.0,
		"ordered field route contributes substantial spatial play (%.3f m)" % route)
	_check(is_equal_approx(active, traversal + interaction),
		"active total separates and exactly sums traversal plus interaction")
	_check(float(contract.get("dialogue_seconds_in_model", -1.0)) == 0.0,
		"dialogue reading time is excluded from the lower-bound model")
	_check(float(contract.get("idle_padding_seconds", -1.0)) == 0.0,
		"the model contains no idle padding")
	_check(int(contract.get("mandatory_field_actions", 0)) == 15
		and int(contract.get("mandatory_seal_actions", 0)) == 3,
		"model prices fifteen field actions and three final seal actions")
	_check(float(contract.get("sprint_distance_allowance_meters", 0.0)) >= 39.9,
		"shortest model grants the live full-stamina sprint allowance")
	_check(float(contract.get("safe_field_route_estimate_meters", 0.0)) > route,
		"SAFE remains a distinct longer geometric route than the fastest DIRECT clear")
	_check(int(contract.get("decision_count", 0)) >= 2
		and int(contract.get("branch_count", 0)) >= 1,
		"the standardized contract exposes its route/resource decisions and branches")


func _verify_fieldwork_structure(sequence: Node) -> void:
	print("\n=== Leaving Facility fieldwork structure ===")
	var stations: Array[Node] = sequence.find_children("Sector*Protocol*", "Interactable", true, false)
	_check(stations.size() == 15,
		"three five-station protocols exist as real Interactables")
	var role_counts := {"aster": 0, "peris": 0, "endo": 0}
	var timed_count := 0
	var eight_second_count := 0
	var outlined_count := 0
	var routed_request_count := 0
	for station in stations:
		var role := str(station.get_meta("field_role", ""))
		if role_counts.has(role):
			role_counts[role] += 1
		if int(station.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_count += 1
		if is_equal_approx(float(station.get("dwell_time")), sequence.FIELD_SITE_WORK_SECONDS):
			eight_second_count += 1
		if station.get("_outline_target") != null:
			outlined_count += 1
		if station.interaction_requested.get_connections().size() >= 2:
			routed_request_count += 1
	_check(role_counts == {"aster": 5, "peris": 5, "endo": 5},
		"Aster, Peris, and Endo each own five specialist tasks")
	_check(timed_count == 15 and eight_second_count == 15,
		"all field tasks are click-gated eight-second work actions")
	_check(outlined_count == 15,
		"every field instrument binds visible geometry to shared outline feedback")
	_check(routed_request_count == 15,
		"every field click routes its named specialist toward the instrument")
	_check(sequence.find_children("DataVane", "MeshInstance3D", true, false).size() == 5,
		"Aster tasks use a distinct data-vane silhouette")
	_check(sequence.find_children("SampleWell*", "MeshInstance3D", true, false).size() == 15,
		"Peris tasks use readable three-well sampling assemblies")
	_check(sequence.find_children("LoadBrace*", "MeshInstance3D", true, false).size() == 10,
		"Endo tasks use paired structural braces")


func _verify_sequential_protocol_gate(sequence: Node) -> void:
	print("\n=== Leaving Facility sequential gameplay gate ===")
	var initial_state: Dictionary = sequence.headless_get_state()
	_check(initial_state.get("field_protocol_progress", []) == [0, 0, 0],
		"field protocols begin with no credited work")
	var enabled_initial := 0
	for sector_sites in sequence._field_site_interactables:
		for station in sector_sites:
			if station.is_interaction_enabled():
				enabled_initial += 1
	_check(enabled_initial == 1
		and sequence._field_site_interactables[0][0].is_interaction_enabled(),
		"only the first authored field station is initially actionable")
	var seals_initially_locked := true
	for seal_pair in sequence._sector_route_interactables:
		for seal in seal_pair:
			if seal.is_interaction_enabled():
				seals_initially_locked = false
	_check(seals_initially_locked,
		"all route seals begin locked behind their field protocols")

	# A callback alone is insufficient: the named role must physically be there.
	sequence.set_preview_character_position("aster", sequence.EXIT_POS)
	sequence._on_field_site_completed(0, 0)
	_check((sequence.headless_get_state().get("field_protocol_progress", []) as Array)[0] == 0,
		"field work refuses to resolve while its named specialist is absent")

	for sector_index in range(sequence.FIELD_PROTOCOLS.size()):
		var protocol: Dictionary = sequence.FIELD_PROTOCOLS[sector_index]
		var sites: Array = protocol["sites"]
		for site_index in range(sites.size()):
			var site: Dictionary = sites[site_index]
			var pos: Vector3 = site["pos"]
			var role := str(site["role"])
			sequence.set_preview_character_position("aster", pos)
			sequence.set_preview_character_position(role, pos + Vector3(0, 0, 0.6))
			sequence._on_field_site_completed(sector_index, site_index)
			var progress: Array = sequence.headless_get_state().get("field_protocol_progress", [])
			_check(int(progress[sector_index]) == site_index + 1,
				"%s credits ordered station %d/%d" % [str(protocol["label"]), site_index + 1, sites.size()])
			if site_index + 1 < sites.size():
				_check(sequence._field_site_interactables[sector_index][site_index + 1].is_interaction_enabled(),
					"completing station %d exposes only the next ordered task" % (site_index + 1))

		_check(bool(sequence.headless_get_state().get("field_protocol_ready", [])[sector_index]),
			"%s unlocks its final route decision" % str(protocol["label"]))
		_check(sequence._sector_route_interactables[sector_index][0].is_interaction_enabled()
			and sequence._sector_route_interactables[sector_index][1].is_interaction_enabled(),
			"both SAFE and DIRECT remain available after protocol completion")
		var direct_station: Vector3 = sequence.IRON_SECTORS[sector_index]["direct_station"]
		for character_id in ["aster", "peris", "endo"]:
			sequence.set_preview_character_position(character_id, direct_station)
		sequence._on_sector_route_station_completed(sector_index, "direct")
		_check(bool(sequence.headless_get_state().get("sector_gates_open", [])[sector_index]),
			"working the chosen seal opens sector %d in authoritative GridWorld state" % (sector_index + 1))
		if sector_index + 1 < sequence.FIELD_PROTOCOLS.size():
			_check(sequence._field_site_interactables[sector_index + 1][0].is_interaction_enabled(),
				"opening a seal exposes the next sector's first field station")

	var final_state: Dictionary = sequence.headless_get_state()
	_check((final_state.get("field_protocol_ready", []) as Array).count(true) == 3,
		"all three protocols reach ready state")
	_check((final_state.get("field_completed_site_ids", []) as Array).size() == 15,
		"all fifteen unique field-site completions are recorded")
	_check((final_state.get("sector_gates_open", []) as Array).count(true) == 3,
		"all three seals open only after substantive field play")


func _verify_measurement_language(sequence: Node) -> void:
	print("\n=== Leaving Facility building-quality measurement language ===")
	_check(sequence.find_children("FieldGridSector*", "MeshInstance3D", true, false).size() == 9,
		"each sector has three continuous floor-grid lane datums")
	_check(sequence.find_children("FieldDatumSector*", "MeshInstance3D", true, false).size() == 15,
		"every worksite has a full-width measurement cross-line")
	_check(sequence.find_children("FieldLinkSector*", "MeshInstance3D", true, false).size() == 12,
		"emissive route links connect each ordered field sequence")
	_check(sequence.find_children("FieldMeasureLabelSector*", "Label3D", true, false).size() == 15,
		"all worksite datums carry exact meter and station labels")
	_check(sequence.find_children("ProtocolArchSector*", "Node3D", true, false).size() == 6,
		"entry and exit measurement arches frame every protocol bay")
	_check(sequence.find_child("LevelDecoration", true, false) != null,
		"fieldwork remains inside the shared building-quality decoration pass")
	var anchors: Dictionary = sequence.headless_get_anchor_positions()
	_check((anchors.get("field_protocols", {}) as Dictionary).size() == 3,
		"headless anchors expose all three spatial protocols for QA integration")
	_check(int(sequence.headless_get_state().get("optional_branch_count", 0)) == 2,
		"the lysate cache and iron lookout discoveries remain intact")


func _finish() -> void:
	if _failures.is_empty():
		print("\nLeaving Facility long-form verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nLeaving Facility long-form verification: %d FAILED" % _failures.size())
		get_tree().quit(1)
