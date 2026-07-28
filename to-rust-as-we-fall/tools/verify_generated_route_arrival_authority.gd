extends SceneTree

## Focused receipt/lifecycle regression for ordinary generated-route movement.
##
## Route progress belongs to the canonical GameState arrival signal plus exact
## source/destination validation. A teleported or merely rendered presenter must
## not advance it, and replacing GameState during load must move the one signal
## subscription to the restored authority object.

const CHUNK_SCENE := preload(
	"res://scenes/fragments/chunks/generated_stretch_chunk.tscn"
)
const SPEC_PATH := (
	"res://data/generated_stretches/generated_sample_teaching_first_fork.json"
)


class RouteHost:
	extends ChunkHostStub

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(
		char_id: String, stat_name: String, value: float
	) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(
		char_id: String, stat_name: String, delta: float
	) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var spec := _route_fixture_spec()
	check(not spec.is_empty(), "route authority fixture loads")
	if spec.is_empty():
		_finish()
		return
	var pair := await _boot_pair(spec)
	var host: RouteHost = pair.host
	var chunk: Node = pair.chunk
	var callback := Callable(chunk, "_on_generated_character_arrived")

	chunk.call("on_game_state_snapshot_restored")
	chunk.call("on_game_state_snapshot_restored")
	check(
		_route_connection_count(host.game_state, callback) == 1,
		"construction and repeated restore keep exactly one live arrival subscription"
	)

	var route_0 := chunk.call("_find_route", "main_00_01") as Dictionary
	var route_1 := chunk.call("_find_route", "main_01_02") as Dictionary
	var route_2 := chunk.call("_find_route", "main_02_03") as Dictionary
	var route_3 := chunk.call("_find_route", "main_03_04") as Dictionary
	var route_0_from := _surface_point(route_0, "from")
	var route_0_to := _surface_point(route_0, "to")
	var route_1_to := _surface_point(route_1, "to")
	var route_2_to := _surface_point(route_2, "to")
	var route_3_to := _surface_point(route_3, "to")

	host.game_state.snap_character_to("aster", route_0_to)
	chunk.call("_process", 0.0)
	await process_frame
	check(
		not _activated(chunk, "main_00_01"),
		"snap and render polling at a destination cannot forge route arrival"
	)

	host.game_state.snap_character_to("aster", route_0_from)
	check(
		_move_character(host, "aster", route_0_to)
		and _activated(chunk, "main_00_01"),
		"ordinary movement arrival commits the exact physically reached route"
	)
	var runtime_key := str(chunk.call("_generated_runtime_authority_key"))
	var route_record := host.game_state.get_world_state(runtime_key, {}) as Dictionary
	check(
		(route_record.get("activated_routes", []) as Array).count("main_00_01") == 1,
		"live arrival publishes one durable route receipt before returning"
	)

	# node_01 is a real lysate source. Even if another caller forges the public
	# arrival signal with the body at the endpoint, source readiness still rejects
	# its outgoing route. (The actual navigation topology also blocks this lane.)
	host.game_state.snap_character_to("aster", route_1_to)
	host.game_state.character_arrived.emit("aster")
	check(
		not _activated(chunk, "main_01_02"),
		"destination arrival cannot bypass an actionable uncompleted source"
	)
	host.game_state.snap_character_to("aster", route_0_to)
	check(
		bool(chunk.call("_headless_activate_generated_node", "node_01"))
			and (chunk.get("_completed_nodes") as Array).has("node_01"),
		"the actionable source becomes ready only through its exact physical receipt"
	)

	var saved_state := _json_round_trip(host.game_state.serialize())
	var old_state = host.game_state
	var replacement := GameState.new()
	replacement.scheduler = host.scheduler
	replacement.grid = host.grid
	replacement.deserialize(saved_state)
	host.game_state = replacement
	chunk.call("on_game_state_snapshot_restored")
	chunk.call("on_game_state_snapshot_restored")
	check(
		not old_state.character_arrived.is_connected(callback)
		and _route_connection_count(replacement, callback) == 1,
		"GameState replacement disconnects stale authority and reconnects restored authority once"
	)
	check(
		_activated(chunk, "main_00_01")
			and not _activated(chunk, "main_01_02"),
		"fresh authority restore preserves the exact committed and blocked route set"
	)

	# The exact source receipt was part of the snapshot. Move over the next
	# physically open layout segment; this proves the replacement GameState,
	# rather than the discarded object, now drives play.
	replacement.snap_character_to("aster", route_1_to)
	check(
		_move_character(host, "aster", route_2_to)
		and _activated(chunk, "main_02_03")
		and (chunk.get("_activated_routes") as Array).count("main_02_03") == 1,
		"ordinary movement continues through the replacement authority exactly once"
	)

	replacement.register_character("route_outsider", route_2_to, 3.0)
	check(
		_move_character(host, "route_outsider", route_3_to)
		and not _activated(chunk, "main_03_04"),
		"arrival from a body outside the active party cannot commit a party route"
	)

	chunk.detach_chunk_host()
	check(
		not replacement.character_arrived.is_connected(callback),
		"chunk detach removes the live route-arrival subscription"
	)
	host.queue_free()
	await process_frame
	_finish()


func _route_fixture_spec() -> Dictionary:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var spec := (parsed as Dictionary).duplicate(true)
	spec["id"] = "generated_route_arrival_authority_fixture"
	spec["title"] = "Generated Route Arrival Authority Fixture"
	return spec


func _boot_pair(spec: Dictionary) -> Dictionary:
	var host := RouteHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({
		"spec": spec,
		"spiral": false,
		"branches": false,
		"game_mode": "neutral",
		"food_test": "neutral",
	})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _move_character(host: RouteHost, actor: String, target: Vector3) -> bool:
	if not host.game_state.command_move_to_pos(actor, target):
		return false
	for _attempt in range(12):
		if not bool(host.game_state.is_moving(actor)):
			return _reached(host, actor, target)
		var now := float(host.scheduler.get_current_tick())
		var end_tick := float(host.game_state.get_plan_end_tick(actor))
		if end_tick < now:
			return false
		host.scheduler.advance_ticks(maxf(0.000001, end_tick - now))
	return not bool(host.game_state.is_moving(actor)) and _reached(host, actor, target)


func _reached(host: RouteHost, actor: String, target: Vector3) -> bool:
	if not host.game_state.characters.has(actor):
		return false
	var actual: Vector3 = host.game_state.get_position(actor)
	if host.grid == null:
		return actual.distance_to(target) <= 0.05
	var level := int(host.game_state.get_character_level(actor))
	var target_cell: Vector2i = host.grid.nearest_walkable_cell(
		host.grid.world_to_grid(target), level
	)
	return host.grid.world_to_grid(actual) == target_cell


func _surface_point(route: Dictionary, key: String) -> Vector3:
	var raw: Variant = (route.get("surface", {}) as Dictionary).get(key, [])
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(
			float((raw as Array)[0]),
			float((raw as Array)[1]),
			float((raw as Array)[2])
		)
	return Vector3.INF


func _activated(chunk: Node, route_id: String) -> bool:
	return (chunk.get("_activated_routes") as Array).has(route_id)


func _route_connection_count(gs: GameState, callback: Callable) -> int:
	var count := 0
	for connection_v in gs.character_arrived.get_connections():
		if connection_v is Dictionary \
				and (connection_v as Dictionary).get("callable", Callable()) == callback:
			count += 1
	return count


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	print(
		"GENERATED ROUTE ARRIVAL AUTHORITY: %d/%d checks passed"
		% [_checks - _failures, _checks]
	)
	quit(0 if _failures == 0 else 1)
