extends Node

## Focused structural, gameplay-gate, and honest-duration audit for Leaving Facility.
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
	var prejoin: Dictionary = sequence.headless_get_state()
	_check(not bool(prejoin.get("endo_registered", true))
		and not bool(prejoin.get("endo_visible", true))
		and not sequence._sector_route_interactables[0][0].is_interaction_enabled(),
		"Endo and full-party route work remain absent before the authored join")
	sequence._scheduler.clear()
	sequence._begin_endo_join_wait()
	sequence._scheduler.advance_ticks(sequence.ENDO_JOIN_DELAY + 0.001)
	_check(bool(sequence.headless_get_state().get("endo_present", false)),
		"the authored join admits Endo before long-form route verification")

	_verify_duration_contract(sequence)
	_verify_route_choice_structure(sequence)
	_verify_sequential_route_access(sequence)
	_verify_optional_discoveries(sequence)
	_verify_quality_language(sequence)

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
	var route := float(contract.get("shortest_route_meters", 0.0))
	print("  route: %.3f m" % route)
	print("  traversal: %.3f s" % traversal)
	print("  mandatory interaction: %.3f s" % interaction)
	print("  meaningful active: %.3f s" % active)
	print("  shortest clean first clear: %.3f s (%.2f min)" % [total, total / 60.0])
	print("  active ratio: %.2f%%" % (ratio * 100.0))

	_check(target.is_equal_approx(Vector2(75.0, 120.0)),
		"contract records the shorter physical-route first-clear target")
	_check(total >= target.x and total <= target.y,
		"modeled shortest clean first clear lands inside its honest target (%.3f s)" % total)
	_check(active >= 60.0,
		"the route still carries a substantive traversal beat (%.3f s)" % active)
	_check(ratio >= 0.75,
		"meaningful active ratio clears 75%% (%.2f%%)" % (ratio * 100.0))
	_check(route >= 209.0,
		"the authored corridor, not replacement chores, carries spatial play (%.3f m)" % route)
	_check(is_equal_approx(active, traversal + interaction),
		"active total separates and exactly sums traversal plus seal work")
	_check(float(contract.get("dialogue_seconds_in_model", -1.0)) == 0.0,
		"dialogue reading time is excluded from the lower-bound model")
	_check(float(contract.get("idle_padding_seconds", -1.0)) == 0.0,
		"the model contains no idle padding")
	_check(int(contract.get("mandatory_seal_actions", 0)) == 3
		and int(contract.get("mandatory_route_actions", 0)) == 3,
		"only the three physical seal choices are mandatory")
	_check(not contract.has("mandatory_field_actions")
		and not contract.has("mandatory_field_protocols"),
		"the removed field checklist cannot re-enter through pacing metadata")
	_check(float(contract.get("sprint_distance_allowance_meters", 0.0)) >= 39.9,
		"shortest model grants the live full-stamina sprint allowance")
	_check(float(contract.get("safe_route_estimate_meters", 0.0)) > route + 12.0,
		"SAFE remains a distinct longer geometric route than DIRECT")
	_check(int(contract.get("decision_count", 0)) == 3
		and int(contract.get("branch_count", 0)) == 5,
		"the contract counts three route choices plus two optional discoveries")


func _verify_route_choice_structure(sequence: Node) -> void:
	print("\n=== Leaving Facility physical route choices ===")
	var safe_stations: Array[Node] = sequence.find_children("Sector*SafeStation", "Interactable", true, false)
	var direct_stations: Array[Node] = sequence.find_children("Sector*DirectStation", "Interactable", true, false)
	_check(safe_stations.size() == 3 and direct_stations.size() == 3,
		"each iron field has one SAFE and one DIRECT seal station")
	var timed_count := 0
	var outlined_count := 0
	for station in safe_stations + direct_stations:
		if int(station.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_count += 1
		if station.get("_outline_target") != null:
			outlined_count += 1
	_check(timed_count == 6,
		"all route decisions are click-gated physical work actions")
	_check(outlined_count == 6,
		"every route decision binds visible geometry to shared outline feedback")
	_check(sequence.find_children("Sector*Protocol*", "Interactable", true, false).is_empty(),
		"the invented fifteen-station field checklist is absent")
	_check(sequence.find_child("LysateRecoverStation", true, false) == null
		and sequence.find_child("LysateShieldStation", true, false) == null,
		"lysate has no invented recovery or shield manifold")


func _verify_sequential_route_access(sequence: Node) -> void:
	print("\n=== Leaving Facility reachable seal progression ===")
	for sector_index in range(3):
		var expected_available := sector_index == 0
		for seal in sequence._sector_route_interactables[sector_index]:
			_check(seal.is_interaction_enabled() == expected_available,
				"sector %d seal availability matches physical reachability" % (sector_index + 1))

	sequence.set_preview_character_position("aster", sequence.EXIT_POS)
	sequence.set_preview_character_position("peris", sequence.EXIT_POS)
	sequence.set_preview_character_position("endo", sequence.EXIT_POS)
	_check(not _trigger_route_source(sequence, 0, "direct", "aster"),
		"the exact first station rejects a remote selected portrait")
	_check(not bool((sequence.headless_get_state()["sector_gates_open"] as Array)[0]),
		"the first seal refuses to leave the party behind")

	for sector_index in range(3):
		var direct_station: Vector3 = sequence.IRON_SECTORS[sector_index]["direct_station"]
		for character_id in ["aster", "peris", "endo"]:
			sequence.set_preview_character_position(character_id, direct_station)
		_check(_trigger_route_source(sequence, sector_index, "direct", "aster"),
			"sector %d accepts its exact nearby DIRECT station receipt" % (sector_index + 1))
		sequence._scheduler.advance_ticks(sequence.SECTOR_GATE_OPEN_DURATION + 0.001)
		sequence._update_sector_gate_visuals()
		_check(bool((sequence.headless_get_state()["sector_gates_open"] as Array)[sector_index]),
			"the chosen seal opens sector %d at its visible lift endpoint" % (sector_index + 1))
		for seal in sequence._sector_route_interactables[sector_index]:
			_check(not seal.is_interaction_enabled(),
				"the used sector %d seal pair retires" % (sector_index + 1))
		if sector_index + 1 < 3:
			for next_seal in sequence._sector_route_interactables[sector_index + 1]:
				_check(next_seal.is_interaction_enabled(),
					"opening sector %d exposes the next physical route choice" % (sector_index + 1))

	_check((sequence.headless_get_state()["sector_gates_open"] as Array).count(true) == 3,
		"all three seals open without abstract prerequisite actions")


func _verify_optional_discoveries(sequence: Node) -> void:
	print("\n=== Leaving Facility optional discoveries ===")
	var hp_before := float(sequence._game_state.get_stat("aster", "hp"))
	var stamina_before := float(sequence._game_state.get_stat("aster", "stamina"))
	sequence.set_preview_character_position("aster", sequence.CACHE_POS)
	_check(_trigger_source(sequence._cache_interactable, "aster"),
		"the exact nearby cache source accepts Aster's receipt")
	var state: Dictionary = sequence.headless_get_state()
	var item_id := str(state.get("cache_item_id", ""))
	_check(bool(state.get("cache_collected", false)) and item_id != "",
		"the side cache creates a real carried lysate item")
	_check(sequence._game_state.items.has(item_id)
		and str((sequence._game_state.items[item_id] as Dictionary).get("holder", "")) == "aster",
		"the salvaged lysate remains in Aster's hand for later canonical use")
	_check(is_equal_approx(float(sequence._game_state.get_stat("aster", "hp")), hp_before)
		and is_equal_approx(float(sequence._game_state.get_stat("aster", "stamina")), stamina_before),
		"salvage itself does not heal or restore stamina")
	sequence.set_preview_character_position("aster", sequence.LOOKOUT_POS)
	_check(_trigger_source(sequence._lookout_interactable, "aster"),
		"the exact nearby lookout source accepts Aster's receipt")
	_check(bool(sequence.headless_get_state().get("lookout_surveyed", false)),
		"Aster's contextual lookout survey remains available")


func _verify_quality_language(sequence: Node) -> void:
	print("\n=== Leaving Facility quality language ===")
	_check(sequence.find_child("LevelDecoration", true, false) != null,
		"route choices remain inside the shared building-quality decoration pass")
	_check(sequence.find_children("FieldGridSector*", "MeshInstance3D", true, false).is_empty()
		and sequence.find_children("FieldDatumSector*", "MeshInstance3D", true, false).is_empty()
		and sequence.find_children("ProtocolArchSector*", "Node3D", true, false).is_empty(),
		"the removed checklist's floor datums and protocol arches are absent")
	_check(sequence.find_children("RouteWorkLight*", "OmniLight3D", true, false).size() >= 10,
		"the corridor retains its readable repeated work lights")
	_check(sequence.find_children("RouteLaneLight*", "OmniLight3D", true, false).size() == 5,
		"safe stations and optional branches retain local lane lights")
	var anchors: Dictionary = sequence.headless_get_anchor_positions()
	_check(anchors.has("side_cache") and anchors.has("lookout")
		and not anchors.has("field_protocols") and not anchors.has("resource_manifold"),
		"QA anchors expose the real discoveries without removed checklist/manifold state")
	_check(int(sequence.headless_get_state().get("optional_branch_count", 0)) == 2,
		"the lysate cache and iron lookout discoveries remain intact")


func _finish() -> void:
	if _failures.is_empty():
		print("\nLeaving Facility long-form verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nLeaving Facility long-form verification: %d FAILED" % _failures.size())
		get_tree().quit(1)


func _trigger_route_source(
		sequence: Node,
		sector_index: int,
		route_choice: String,
		actor: String
	) -> bool:
	var source: Node = sequence._sector_route_interactables[sector_index][
		0 if route_choice == "safe" else 1]
	return _trigger_source(source, actor)


func _trigger_source(source: Node, actor: String) -> bool:
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))
