extends SceneTree

## Focused canonical-core, structure, and honest mechanical-work verification for
## the Inflammashunt. The canonical spec's 7-9 minute first-play figure is a
## human playtest goal: reasoning, exploration, and recoverable experiments are
## player-dependent. This probe therefore reports production-backed mechanical
## workload without inventing a duration floor or appending solved-state work.
##
## Run:
##   godot --headless --path . --script res://tools/verify_inflammashunt_longform.gd

const CORE_ACTIONS := [
	["DrainageValve", "aster"],
	["CharDepositA", "myke"],
	["CharDepositB", "myke"],
	["RootTendril", "peris"],
	["DeviceHousing", "aster"],
]
const ROUTE_OBSERVATIONS := [
	["AsterLogTerminal", "aster"],
	["PipeDiagram", "aster"],
	["DeadRootNetwork", "peris"],
	["LivingJunction", "peris"],
	["GrateObservation", "myke"],
	["DeviceGap", "myke"],
]
const ROLE_WALK_SPEEDS := {"aster": 3.2, "peris": 3.0, "myke": 3.1}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


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
	_check(chunk != null, "the Inflammashunt builds in the production preview host")
	if chunk != null:
		_verify_canonical_structure(chunk)
		_verify_efficiency_measurement_and_solve(chunk, preview)

	await _dispose(preview)
	_finish()


func _verify_canonical_structure(chunk: Node) -> void:
	print("\n=== Inflammashunt canonical structure ===")
	_check(chunk.get_node_or_null("CommissioningGallery") == null,
		"there is no uncited post-solve commissioning gallery")
	_check(chunk.find_children("Commissioning*", "", true, false).is_empty(),
		"there are no commissioning stations after the catalyst housing")

	var grid: Dictionary = chunk.get_grid_data()
	_check(int(grid.get("width", 0)) == 40,
		"the authoritative grid ends with the canonical junction instead of a 225m tail")
	var origin: Array = grid.get("origin", [0.0, 0.0, 0.0])
	var cell_size := float(grid.get("cell_size", 0.0))
	var max_walkable_x := -INF
	for cell_variant in grid.get("walkable_cells", []) as Array:
		var cell: Array = cell_variant
		max_walkable_x = maxf(max_walkable_x,
			float(origin[0]) + (float(cell[0]) + 0.5) * cell_size)
	_check(max_walkable_x < float(chunk.JCT_X1),
		"walkable cells stop inside the canonical junction (max x %.2f)" % max_walkable_x)

	var east_wall_closed := false
	var furthest_floor_edge := -INF
	for wall_variant in chunk.fragment.walls:
		var wall: Dictionary = wall_variant
		var wall_pos: Vector3 = wall.get("pos", Vector3.ZERO)
		var wall_size: Vector3 = wall.get("size", Vector3.ZERO)
		if absf(wall_pos.x - 55.9) < 0.05 and wall_size.z >= 18.0:
			east_wall_closed = true
	for floor_variant in chunk.fragment.floors:
		var floor_spec: Dictionary = floor_variant
		var floor_pos: Vector3 = floor_spec.get("pos", Vector3.ZERO)
		var floor_size: Vector3 = floor_spec.get("size", Vector3.ZERO)
		furthest_floor_edge = maxf(furthest_floor_edge, floor_pos.x + floor_size.x * 0.5)
	_check(east_wall_closed, "a continuous east wall closes the catalyst junction")
	_check(furthest_floor_edge <= float(chunk.JCT_X1) + 0.01,
		"authored floor geometry ends at the junction (east edge %.2f)" % furthest_floor_edge)

	for spec_variant in ROUTE_OBSERVATIONS + CORE_ACTIONS:
		var spec: Array = spec_variant
		_check(chunk.find_child(str(spec[0]), true, false) != null,
			"canonical interactable %s exists" % str(spec[0]))


func _verify_efficiency_measurement_and_solve(chunk: Node, preview: Node) -> void:
	print("\n=== Inflammashunt route efficiency and five-step solve ===")
	_check(is_equal_approx(float(chunk._valve_it.dwell_time), 14.0),
		"without route information the valve is a 14-second hold")
	_trigger(chunk, "DeviceHousing", "aster")
	_check(not bool(chunk.device_retrieved) and not bool(chunk.housing_unlocked),
		"an early housing attempt is harmless and does not skip the causal chain")

	for spec_variant in ROUTE_OBSERVATIONS:
		var spec: Array = spec_variant
		_trigger(chunk, str(spec[0]), str(spec[1]))
	var state: Dictionary = chunk.headless_get_state()
	var all_info := true
	for flag in state.get("route_info", {}) as Dictionary:
		all_info = all_info and bool((state["route_info"] as Dictionary)[flag])
	_check(all_info, "all six route observations remain informative but optional")
	_check(is_equal_approx(float(chunk._valve_it.dwell_time), 2.5)
		and is_equal_approx(float(chunk._root_it.dwell_time), 2.5),
		"route information shortens work instead of gating the solution")

	var measurement := _measure_core_mechanical_work(chunk)
	print("  INFO: aggregate route %.2fm / %.2f person-seconds" % [
		float(measurement["aggregate_route_meters"]),
		float(measurement["aggregate_traversal_person_seconds"]),
	])
	print("  INFO: observations %.2fs + informed causal actions %.2fs = %.2fs authored dwell" % [
		float(measurement["observation_dwell_seconds"]),
		float(measurement["informed_core_dwell_seconds"]),
		float(measurement["authored_dwell_seconds"]),
	])
	print("  INFO: this is mechanical workload, not a fabricated first-clear duration")
	_check(str(measurement.get("measurement_kind", "")) ==
			"aggregate_mechanical_workload_not_first_clear_elapsed",
		"the timing report explicitly distinguishes workload from player-dependent playtime")
	_check(float(measurement["aggregate_route_meters"]) > 100.0
		and float(measurement["aggregate_traversal_person_seconds"]) > 30.0,
		"the report is backed by the authored routes and role speeds")
	_check(float(measurement["uninformed_core_dwell_seconds"]) >
			float(measurement["informed_core_dwell_seconds"]) + 30.0,
		"reconnaissance provides a large, measurable efficiency advantage")
	_check(int(measurement["route_observation_count"]) == 6
		and int(measurement["causal_action_count"]) == 5,
		"the measured core is six observations plus the canonical five causal actions")
	_check(float(measurement["authored_dwell_seconds"]) < 60.0,
		"the verifier does not pad the solved core toward the 7-9 minute playtest goal")

	for spec_variant in CORE_ACTIONS:
		var spec: Array = spec_variant
		_trigger(chunk, str(spec[0]), str(spec[1]))
		match str(spec[0]):
			"DrainageValve":
				_check(chunk.water_phase == "flowing"
						and chunk.char_a_state == "dry" and chunk.char_b_state == "dry",
					"the valve starts visible flow without remotely wetting either deposit")
				preview.headless_advance(chunk.WATER_FLOW_DURATION + 0.01, 0.1)
				_check(chunk.char_a_state == "damp" and chunk.char_b_state == "damp",
					"arriving water dampens both char deposits")
			"CharDepositB":
				_check(chunk.char_a_state == "cleared" and chunk.char_b_state == "cleared",
					"both damp deposits scrape clean")
			"RootTendril":
				_check(chunk.root_state == "connecting" and not bool(chunk.housing_unlocked),
					"tending begins visible filament growth without unlocking the housing early")
				preview.headless_advance(chunk.ROOT_CONNECT_DURATION + 0.01, 0.1)
				_check(chunk.root_state == "connected" and bool(chunk.housing_unlocked),
					"completed filaments unlock the housing")
			"DeviceHousing":
				_check(chunk.housing_state == "opening" and not bool(chunk.device_retrieved),
					"the housing lid must physically open before retrieval")
				preview.headless_advance(chunk.HOUSING_OPEN_DURATION + 0.01, 0.1)

	state = chunk.headless_get_state()
	_check(bool(state.get("device_retrieved", false)),
		"water, clean, clean, tend, open retrieves the Resolution Catalyst")
	_check(str(state.get("current_step", "")) == "complete"
		and str(chunk._phase) == "complete",
		"catalyst retrieval completes the level when the lid finishes opening")
	preview.headless_advance(20.0, 0.1)
	_check(str(chunk.headless_get_state().get("current_step", "")) == "complete",
		"elapsed time cannot append post-solve chores or undo completion")


func _measure_core_mechanical_work(chunk: Node) -> Dictionary:
	var spawns: Dictionary = chunk.get_spawn_positions()
	var route_meters := 0.0
	var traversal_person_seconds := 0.0

	var aster_points: Array = [
		spawns.get("aster", Vector3.ZERO),
		_position(chunk, "AsterLogTerminal"),
		_position(chunk, "PipeDiagram"),
		_position(chunk, "DrainageValve"),
		_position(chunk, "DeviceHousing"),
	]
	var peris_points: Array = [
		spawns.get("peris", Vector3.ZERO),
		_position(chunk, "DeadRootNetwork"),
		_position(chunk, "LivingJunction"),
		_position(chunk, "RootTendril"),
	]
	for route in [
		{"points": aster_points, "speed": ROLE_WALK_SPEEDS["aster"]},
		{"points": peris_points, "speed": ROLE_WALK_SPEEDS["peris"]},
	]:
		var result := _route_measure(route["points"] as Array, float(route["speed"]))
		route_meters += float(result["meters"])
		traversal_person_seconds += float(result["seconds"])

	var crawl_in: Node = chunk.find_child("MykeCrawlIn", true, false)
	var crawl_out: Node = chunk.find_child("MykeCrawlOut", true, false)
	var myke_normal_a: Array = [
		spawns.get("myke", Vector3.ZERO),
		_position(chunk, "MykeCrawlIn"),
	]
	var myke_crawl_a: Array = [_position(chunk, "MykeCrawlIn")]
	myke_crawl_a.append_array(crawl_in.get_data_waypoints())
	var myke_normal_b: Array = [
		myke_crawl_a[-1],
		_position(chunk, "GrateObservation"),
		_position(chunk, "DeviceGap"),
		_position(chunk, "MykeCrawlOut"),
	]
	var myke_crawl_b: Array = [_position(chunk, "MykeCrawlOut")]
	myke_crawl_b.append_array(crawl_out.get_data_waypoints())
	var myke_normal_c: Array = [
		myke_crawl_b[-1],
		_position(chunk, "CharDepositA"),
		_position(chunk, "CharDepositB"),
	]
	for route in [
		{"points": myke_normal_a, "speed": ROLE_WALK_SPEEDS["myke"]},
		{"points": myke_crawl_a, "speed": float(crawl_in.crawl_speed)},
		{"points": myke_normal_b, "speed": ROLE_WALK_SPEEDS["myke"]},
		{"points": myke_crawl_b, "speed": float(crawl_out.crawl_speed)},
		{"points": myke_normal_c, "speed": ROLE_WALK_SPEEDS["myke"]},
	]:
		var result := _route_measure(route["points"] as Array, float(route["speed"]))
		route_meters += float(result["meters"])
		traversal_person_seconds += float(result["seconds"])

	var observation_dwell := 0.0
	for spec_variant in ROUTE_OBSERVATIONS:
		var spec: Array = spec_variant
		var interactable: Node = chunk.find_child(str(spec[0]), true, false)
		observation_dwell += float(interactable.dwell_time)
	var informed_core_dwell := float(chunk.HOLDS["valve"][0]) 		+ float(chunk.HOLDS["char_a"][0]) + float(chunk.HOLDS["char_b"][0]) 		+ float(chunk.HOLDS["root"][0]) + float(chunk._housing_it.dwell_time)
	var uninformed_core_dwell := float(chunk.HOLDS["valve"][1]) 		+ float(chunk.HOLDS["char_a"][1]) + float(chunk.HOLDS["char_b"][1]) 		+ float(chunk.HOLDS["root"][1]) + float(chunk._housing_it.dwell_time)
	return {
		"measurement_kind": "aggregate_mechanical_workload_not_first_clear_elapsed",
		"aggregate_route_meters": route_meters,
		"aggregate_traversal_person_seconds": traversal_person_seconds,
		"observation_dwell_seconds": observation_dwell,
		"informed_core_dwell_seconds": informed_core_dwell,
		"uninformed_core_dwell_seconds": uninformed_core_dwell,
		"authored_dwell_seconds": observation_dwell + informed_core_dwell,
		"route_observation_count": ROUTE_OBSERVATIONS.size(),
		"causal_action_count": CORE_ACTIONS.size(),
	}


func _route_measure(points: Array, speed: float) -> Dictionary:
	var meters := 0.0
	for index in range(1, points.size()):
		var from_point: Vector3 = points[index - 1]
		var to_point: Vector3 = points[index]
		meters += Vector2(to_point.x - from_point.x, to_point.z - from_point.z).length()
	return {"meters": meters, "seconds": meters / maxf(speed, 0.001)}


func _position(chunk: Node, node_name: String) -> Vector3:
	var node := chunk.find_child(node_name, true, false) as Node3D
	return node.position if node != null else Vector3.ZERO


func _trigger(chunk: Node, node_name: String, role: String) -> bool:
	var interactable: Node = chunk.find_child(node_name, true, false)
	if interactable == null:
		_check(false, "%s exists" % node_name)
		return false
	interactable.set("active_character", role)
	interactable.call("_trigger", false)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _dispose(preview: Node) -> void:
	if preview != null and is_instance_valid(preview):
		if preview.has_method("_teardown_sequence"):
			preview._teardown_sequence()
		preview.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nInflammashunt canonical-core verification: ALL PASSED")
		quit(0)
	else:
		print("\nInflammashunt canonical-core verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		quit(1)
