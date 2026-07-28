extends SceneTree

## Focused structural/playability check for the rebuilt Leaving Facility route.
## Run:
##   godot --headless --path . --script res://tools/verify_leaving_facility_extension.gd

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)

func _path_length(path: Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += (path[index] as Vector3).distance_to(path[index - 1] as Vector3)
	return total

func _run() -> void:
	var packed := load("res://scenes/tutorial/leaving_facility.tscn") as PackedScene
	_check(packed != null, "Leaving Facility scene loads")
	if packed == null:
		quit(1)
		return
	var sequence := packed.instantiate()
	root.add_child(sequence)
	for _frame in range(5):
		await process_frame

	var contract: Dictionary = sequence.get_playtime_contract()
	var anchors: Dictionary = sequence.headless_get_anchor_positions()
	var state: Dictionary = sequence.headless_get_state()
	_check(not bool(state.get("endo_registered", true))
		and not bool(state.get("endo_visible", true))
		and not sequence._sector_route_interactables[0][0].is_interaction_enabled(),
		"Endo and full-party route work are absent before the authored join")
	sequence._scheduler.clear()
	sequence._begin_endo_join_wait()
	sequence._scheduler.advance_ticks(sequence.ENDO_JOIN_DELAY + 0.001)
	state = sequence.headless_get_state()
	_check(bool(state.get("endo_present", false)) and bool(state.get("endo_in_party", false)),
		"the authored join admits Endo before full-party route testing")
	_check(float(contract.get("critical_route_meters", 0.0)) >= 160.0,
		"critical route is at least 160 authored meters")
	_check(float(contract.get("critical_route_meters", 999.0)) <= 220.0,
		"critical route stays inside the 220 meter brief")
	_check(int(state.get("sector_count", 0)) == 3, "three distinct iron sectors are registered")
	_check(int(state.get("optional_branch_count", 0)) == 2, "cache and lookout branches are registered")
	_check(sequence.find_children("RouteWorkLight*", "OmniLight3D", true, false).size() >= 10,
		"the long route has a repeated readable work-light datum")
	_check(sequence.find_children("RouteLaneLight*", "OmniLight3D", true, false).size() == 5,
		"each safe station and optional branch has a local lane light")
	_check(sequence._world_environment != null and sequence._world_environment.ambient_light_energy >= 0.35,
		"evening route lighting preserves WebGL floor readability")
	_check(sequence._hud != null and sequence._hud.get("_center_button") != null,
		"the corridor HUD exposes a camera recenter control")
	sequence.set_preview_character_position("aster", Vector3(0, 0, 0))
	sequence.set_preview_character_position("peris", Vector3(6, 0, 0))
	sequence.set_preview_character_position("endo", Vector3(12, 0, 0))
	sequence._camera.unlock()
	sequence._recenter_party_camera()
	var party_pan: Vector3 = sequence._camera.get("_pan_offset")
	var party_centroid := Vector3.ZERO
	var visible_party_count := 0
	for character in [sequence._player, sequence._peris, sequence._endo]:
		if is_instance_valid(character) and character.visible:
			party_centroid += character.global_position
			visible_party_count += 1
	party_centroid /= float(visible_party_count)
	var expected_party_pan: Vector3 = party_centroid - sequence._camera.target.global_position
	expected_party_pan.y = 0.0
	_check(party_pan.is_equal_approx(expected_party_pan),
		"camera recenter frames the visible party centroid instead of Aster alone")
	DialogueData.load_dir("res://data/dialogue/en/")
	for dialogue_key in [
		"facility.endo.shelters",
		"facility.endo.iron_warn",
		"facility.endo.dusk",
		"facility.endo.shelter",
		"facility.endo.rest",
		"facility.dawn",
	]:
		var authored_line := DialogueData.get_line(dialogue_key)
		_check(authored_line.text.strip_edges() != "" and not authored_line.text.begins_with("[MISSING:"),
			"authored export-safe dialogue exists: %s" % dialogue_key)
	_check((anchors["shelter"] as Vector3).x - (anchors["facility_exit"] as Vector3).x >= 200.0,
		"shelter is spatially separated from the facility exit")
	var route_station: Node = sequence.find_child("Sector1SafeStation", true, false)
	_check(route_station is Interactable and int(route_station.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"route seals are click-gated timed work actions")
	_check(route_station != null and route_station.get("_outline_target") != null,
		"route stations bind visible geometry to shared outline feedback")
	var route_labels := route_station.find_children("*", "Label3D", true, false) if route_station != null else []
	_check(not route_labels.is_empty() and (route_labels[0] as Label3D).outline_size >= 8,
		"SAFE and DIRECT station labels have a high-contrast world-space outline")
	_check(route_station != null and route_station.is_interaction_enabled(),
		"the first reachable route seal is immediately available")
	_check(not sequence._sector_route_interactables[1][0].is_interaction_enabled()
		and not sequence._sector_route_interactables[2][0].is_interaction_enabled(),
		"later seal labels stay dormant until their geometry is reachable")
	_check(sequence.find_children("Sector*Protocol*", "Interactable", true, false).is_empty(),
		"no mandatory field-checklist interactables remain")

	var grid: GridWorld = sequence._grid
	_check(grid != null and grid.risk_cells.size() > 400,
		"iron fields are real GridWorld risk, not painted-only decoration")
	sequence._on_route_station_requested(null, anchors["sector_1_iron"], "direct")
	_check(not sequence._game_state.is_route_cautious(),
		"the DIRECT station changes authoritative route planning before traversal")
	sequence._on_route_station_requested(null, anchors["sector_1_safe"], "safe")
	_check(sequence._game_state.is_route_cautious(),
		"the SAFE station changes authoritative route planning before traversal")
	sequence._on_sector_route_committed(0, "direct")
	_check(not bool((sequence.headless_get_state()["sector_gates_open"] as Array)[0]),
		"a route seal refuses to abandon party members behind the crossing")
	for sector_index in range(3):
		var station_pos: Vector3 = sequence.IRON_SECTORS[sector_index]["direct_station"]
		sequence.set_preview_character_position("aster", station_pos)
		sequence.set_preview_character_position("peris", station_pos + Vector3(-1.0, 0, 1.0))
		sequence.set_preview_character_position("endo", station_pos + Vector3(-1.0, 0, -1.0))
		_check(_trigger_route_source(sequence, sector_index, "direct", "aster"),
			"sector %d accepts its exact nearby DIRECT station receipt" % (sector_index + 1))
		sequence._scheduler.advance_ticks(sequence.SECTOR_GATE_OPEN_DURATION + 0.001)
		sequence._update_sector_gate_visuals()
		if sector_index + 1 < 3:
			_check(sequence._sector_route_interactables[sector_index + 1][0].is_interaction_enabled()
				and sequence._sector_route_interactables[sector_index + 1][1].is_interaction_enabled(),
				"opening sector %d exposes the next SAFE/DIRECT decision" % (sector_index + 1))
	state = sequence.headless_get_state()
	_check((state["sector_gates_open"] as Array).count(true) == 3,
		"working the three route stations opens all three data-layer seals")

	var start := grid.world_to_grid(anchors["facility_exit"])
	var finish := grid.world_to_grid(anchors["shelter"])
	var direct_path: Array = grid.find_path(start, finish, {}, false)
	var safe_path: Array = grid.find_path(start, finish, {}, true)
	var direct_meters := _path_length(direct_path)
	var safe_meters := _path_length(safe_path)
	_check(not direct_path.is_empty() and not safe_path.is_empty(),
		"both direct and safe routes remain traversable")
	_check(safe_meters > direct_meters + 12.0,
		"safe routing takes a material detour (%.1f m vs %.1f m)" % [safe_meters, direct_meters])
	var hp_before_iron: float = sequence._game_state.get_stat("aster", "hp")
	sequence.set_preview_character_position("aster", anchors["sector_1_iron"])
	sequence._current_step = "first_corridor"
	sequence._start_iron_hazard_cadence()
	sequence._scheduler.advance_ticks(sequence.IRON_DAMAGE_INTERVAL + 0.001)
	_check(sequence._game_state.get_stat("aster", "hp") < hp_before_iron,
		"direct iron exposure changes authoritative party HP on the fixed scheduler cadence")

	state = sequence.headless_get_state()
	var source_cache_item_id := str(state.get("cache_item_id", ""))
	_check(not bool(state.get("cache_collected", true))
		and str(state.get("cache_phase", "")) == sequence.CACHE_PHASE_AVAILABLE
		and bool(state.get("cache_item_at_source", false))
		and source_cache_item_id != "",
		"side cache exposes one real source-tagged lysate before interaction")
	sequence.set_preview_character_position("aster", sequence.CACHE_POS)
	sequence._cache_interactable.active_character = "aster"
	var hp_before_cache: float = sequence._game_state.get_stat("aster", "hp")
	var stamina_before_cache: float = sequence._game_state.get_stat("aster", "stamina")
	_check(_trigger_source(sequence._cache_interactable, "aster"),
		"the exact nearby cache source accepts Aster's receipt")
	state = sequence.headless_get_state()
	var cache_item_id := str(state.get("cache_item_id", ""))
	_check(bool(state.get("cache_collected", false)) and cache_item_id == source_cache_item_id,
		"side cache transfers the pre-existing lysate instead of creating one on success")
	_check(sequence._game_state.items.has(cache_item_id)
		and str((sequence._game_state.items[cache_item_id] as Dictionary).get("holder", "")) == "aster",
		"the exact lysate remains carried for later endocytosis or shelter use")
	_check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), hp_before_cache)
		and is_equal_approx(sequence._game_state.get_stat("aster", "stamina"), stamina_before_cache),
		"salvaging lysate does not directly heal HP or stamina")
	_check(sequence.find_child("LysateRecoverStation", true, false) == null
		and sequence.find_child("LysateShieldStation", true, false) == null,
		"the invented lysate recovery/shield manifold is absent")

	# Information changes the player's model, not the hazard's physical output. Compare the same
	# body in the same third-sector position for one exact cadence tick on either side of the survey.
	sequence.set_preview_character_position("aster", anchors["sector_3_iron"])
	sequence._game_state.set_stat("aster", "hp", 100.0)
	var hp_before_unsurveyed: float = sequence._game_state.get_stat("aster", "hp")
	sequence._apply_iron_damage_tick()
	var unsurveyed_damage: float = hp_before_unsurveyed - sequence._game_state.get_stat("aster", "hp")
	sequence._game_state.set_stat("aster", "hp", 100.0)
	_check(not sequence._on_lookout_surveyed(),
		"a direct lookout owner callback has no exact-source receipt")
	sequence._lookout_interactable.set("active_character", "aster")
	sequence._lookout_interactable.emit_signal("interacted")
	_check(not bool(sequence.headless_get_state().get("lookout_surveyed", false)),
		"a manually emitted lookout signal cannot counterfeit acceptance")
	_check(not bool(sequence._lookout_interactable.call("_trigger", false)),
		"a remote selected portrait cannot survey the exact lookout source")
	sequence.set_preview_character_position("aster", sequence.LOOKOUT_POS)
	_check(_trigger_source(sequence._lookout_interactable, "aster"),
		"the exact nearby lookout source accepts Aster's receipt")
	_check(bool(sequence.headless_get_state().get("lookout_surveyed", false)),
		"lookout survey records the revealed cadence")
	sequence.set_preview_character_position("aster", anchors["sector_3_iron"])
	var hp_before_surveyed: float = sequence._game_state.get_stat("aster", "hp")
	sequence._apply_iron_damage_tick()
	var surveyed_damage: float = hp_before_surveyed - sequence._game_state.get_stat("aster", "hp")
	_check(is_equal_approx(surveyed_damage, unsurveyed_damage) and surveyed_damage > 0.0,
		"surveying information does not magically reduce identical iron exposure")

	sequence.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Leaving Facility extension verification: ALL PASSED")
		quit(0)
	else:
		print("Leaving Facility extension verification: %d FAILED" % _failures.size())
		quit(1)


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
