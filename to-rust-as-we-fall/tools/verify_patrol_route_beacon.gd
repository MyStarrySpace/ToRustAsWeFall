extends SceneTree

## Focused save/restore proof for PatrolRouteBeacon. The fixture uses real Enemy presenters and
## GameState movements, while the TypedTerminal receipt is reproduced at its documented boundary.

const BeaconScript := preload("res://scripts/game/objects/patrol_route_beacon.gd")
const BEACON_ID := "verify_archive_patrol"
const SOURCE_ID := "typed_terminal:verify_spoof"
const SOURCE_KEY := "gameplay:typed_terminal:verify_spoof"

var checks := 0
var failures := 0
var scheduler: EventScheduler
var game_state: GameState
var host: Node3D
var beacon
var guard_a: Enemy
var guard_b: Enemy
var routes: Array[Dictionary]
var baseline_a: Array[Vector3]
var baseline_b: Array[Vector3]
var seam_state := {}
var seam_scheduler := {}
var reset_seam_state := {}
var reset_seam_scheduler := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _build_fixture()
	_verify_exact_receipt_gate()
	_verify_committed_leg_handoff()
	_verify_signal_time_restore()
	_verify_completed_restore_idempotence()
	_verify_authoritative_reset()
	print("PATROL ROUTE BEACON: %d checks, %d failures" % [checks, failures])
	host.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _build_fixture() -> void:
	scheduler = EventScheduler.new()
	game_state = GameState.new()
	game_state.scheduler = scheduler
	game_state.grid = GridWorld.new()
	game_state.grid.create_room(20, 12, true)
	var actor_pos := _cell(2, 2)
	var guard_a_pos := _cell(4, 3)
	var guard_b_pos := _cell(4, 7)
	game_state.register_character("aster", actor_pos, 3.0, {"hp": 100.0})
	game_state.register_character("guard_a", guard_a_pos, 2.0, {"hp": 50.0})
	game_state.register_character("guard_b", guard_b_pos, 2.0, {"hp": 50.0})
	host = Node3D.new()
	root.add_child(host)
	guard_a = _make_enemy("guard_a")
	guard_b = _make_enemy("guard_b")
	host.add_child(guard_a)
	host.add_child(guard_b)
	await process_frame
	guard_a.activate()
	guard_b.activate()
	baseline_a = [_cell(12, 3), _cell(4, 3)]
	baseline_b = [guard_b_pos, _cell(12, 7)]
	guard_a.configure_patrol(baseline_a)
	guard_a.begin_home_behavior()
	guard_b.configure_patrol(baseline_b)
	guard_b.begin_home_behavior()
	routes = [
		{
			"enemy_id": "guard_a",
			"route_id": "archive_service_loop_a",
			"points": [_cell(12, 5), _cell(16, 5)],
		},
		{
			"enemy_id": "guard_b",
			"route_id": "archive_service_loop_b",
			"points": [_cell(12, 9), _cell(16, 9)],
		},
	]
	beacon = BeaconScript.new()
	host.add_child(beacon)
	check(beacon.configure(game_state, BEACON_ID, routes),
		"configures stable alternate routes without a chunk consequence")
	check(beacon.bind_enemy(guard_a) and beacon.bind_enemy(guard_b),
		"binds both real Enemy presenters by stable char id")
	game_state.register_interactable({
		"id": SOURCE_ID,
		"position": actor_pos,
		"one_shot": true,
		"required_character": "aster",
		"radius": 1.5,
		"enabled": true,
	})
	game_state.world_state_changed.connect(_capture_transaction_seam)


func _verify_exact_receipt_gate() -> void:
	var forged := _command()
	check(not beacon.can_accept_terminal_command(forged),
		"a dictionary without a consumed physical source cannot reroute patrols")
	check(game_state.trigger_interactable(SOURCE_ID, "aster"),
		"fixture consumes the exact nearby one-shot terminal source")
	var wrong := _command()
	wrong["subtype"] = "signal"
	game_state.set_world_state(SOURCE_KEY, {
		"contract": "typed_terminal/v1",
		"command": wrong,
	})
	check(not beacon.can_accept_terminal_command(wrong),
		"signal/lure cannot impersonate the credential/reroute receiver contract")
	var command := _command()
	game_state.set_world_state(SOURCE_KEY, {
		"contract": "typed_terminal/v1",
		"command": command,
	})
	check(beacon.can_accept_terminal_command(command),
		"exact source, actor, trigger count, position, tick, subtype, and effect are accepted")


func _verify_committed_leg_handoff() -> void:
	var command := _command()
	check(game_state.is_moving("guard_a"), "guard A begins with a committed baseline leg")
	check(not game_state.is_moving("guard_b"), "guard B begins between authored legs")
	check(beacon.accept_terminal_command(command),
		"credential spoof commits one complete patrol consequence")
	var state: Dictionary = beacon.get_state()
	check(str(state.get("contract", "")) == "patrol_route_beacon/v1"
			and state.get("phase") == "route_applied",
		"QA state exposes a stable contract and applied phase")
	check(_handoff("guard_a") == "pending" and _handoff("guard_b") == "applied",
		"moving guard waits while stationary guard changes immediately")
	check(_enemy_points("guard_a") == _portable_points(baseline_a),
		"credential spoof does not cancel guard A's committed movement leg")
	check(_enemy_points("guard_b") == _route_points("guard_b"),
		"stationary guard receives its exact authored alternate route")
	var authority := game_state.get_world_state(beacon.authority_state_key(), {}) as Dictionary
	check(authority.get("actor") == "aster"
			and (authority.get("receipt_provenance", {}) as Dictionary).get("source_id") == SOURCE_ID
			and (authority.get("baseline_routes", []) as Array).size() == 2,
		"authority stores actor, terminal provenance, alternate routes, and reset baselines")
	check(not seam_state.is_empty()
			and _route_points_from_state(seam_state, "guard_a") == _portable_points(baseline_a),
		"signal-time snapshot exists before any enemy consequence mutates")
	scheduler.advance_ticks(3.99)
	check(_handoff("guard_a") == "pending",
		"alternate route cannot take ownership before the baseline arrival")
	scheduler.advance_ticks(0.01)
	check(_handoff("guard_a") == "applied"
			and _enemy_points("guard_a") == _route_points("guard_a"),
		"arrival commits and applies the alternate route exactly at the leg boundary")
	check(not beacon.accept_terminal_command(command),
		"spent command cannot duplicate an already-applied assignment")


func _verify_signal_time_restore() -> void:
	scheduler.clear()
	scheduler.deserialize(seam_scheduler)
	game_state.deserialize(seam_state)
	guard_a.on_game_state_snapshot_restored()
	guard_b.on_game_state_snapshot_restored()
	check(beacon.on_game_state_snapshot_restored(),
		"signal-time restore reconciles all currently eligible targets")
	beacon.on_game_state_snapshot_restored()
	check(_handoff("guard_a") == "pending"
			and _enemy_points("guard_a") == _portable_points(baseline_a),
		"restore preserves the still-committed baseline leg without early reroute")
	check(_handoff("guard_b") == "applied"
			and _enemy_points("guard_b") == _route_points("guard_b"),
		"restore repairs the missing stationary-target consequence")
	scheduler.advance_ticks(4.0)
	check(_handoff("guard_a") == "applied"
			and _enemy_points("guard_a") == _route_points("guard_a"),
		"restored pending handoff applies once when the original leg arrives")


func _verify_completed_restore_idempotence() -> void:
	var saved_scheduler := _round_trip(scheduler.serialize())
	var saved_state := _round_trip(game_state.serialize())
	guard_a.configure_patrol([_cell(3, 10), _cell(5, 10)])
	guard_a.begin_home_behavior()
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	game_state.deserialize(saved_state)
	guard_a.on_game_state_snapshot_restored()
	guard_b.on_game_state_snapshot_restored()
	var patrol_entries_before := int(Enemy.CALLS.get("enter_patrol", 0))
	beacon.on_game_state_snapshot_restored()
	beacon.on_game_state_snapshot_restored()
	check(_enemy_points("guard_a") == _route_points("guard_a")
			and _enemy_points("guard_b") == _route_points("guard_b"),
		"completed save restores both alternate routes from GameState truth")
	check(int(Enemy.CALLS.get("enter_patrol", 0)) == patrol_entries_before,
		"repeated attachment does not restart an already-authoritative patrol")


func _verify_authoritative_reset() -> void:
	check(beacon.reset_assignment(&"focused_checkpoint"),
		"public checkpoint reset accepts the applied assignment")
	var reset_state: Dictionary = beacon.get_state()
	check(reset_state.get("phase") == "reset"
			and reset_state.get("reset_reason") == "focused_checkpoint",
		"reset remains an inspectable authoritative phase")
	check(_enemy_points("guard_a") == _portable_points(baseline_a)
			and _enemy_points("guard_b") == _portable_points(baseline_b),
		"reset restores both original patrols through Enemy public APIs")
	check(not reset_seam_state.is_empty(),
		"reset publication snapshot exists before original patrols are restored")
	guard_a.configure_patrol(_vectors_for_route("guard_a"))
	guard_a.begin_home_behavior()
	scheduler.clear()
	scheduler.deserialize(reset_seam_scheduler)
	game_state.deserialize(reset_seam_state)
	guard_a.on_game_state_snapshot_restored()
	guard_b.on_game_state_snapshot_restored()
	check(beacon.on_game_state_snapshot_restored(),
		"torn reset restores every baseline consequence")
	var entries_before := int(Enemy.CALLS.get("enter_patrol", 0))
	beacon.on_game_state_snapshot_restored()
	check(_enemy_points("guard_a") == _portable_points(baseline_a)
			and _enemy_points("guard_b") == _portable_points(baseline_b),
		"repeated reset attachment keeps exact baseline patrols")
	check(int(Enemy.CALLS.get("enter_patrol", 0)) == entries_before,
		"repeated reset attachment does not restart baseline patrols")


func _make_enemy(enemy_id: String) -> Enemy:
	var enemy := Enemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = game_state
	enemy.move_speed = 2.0
	enemy.detection_range = 0.0
	enemy.set_detection_targets([])
	return enemy


func _command() -> Dictionary:
	var source := game_state.get_interactable(SOURCE_ID)
	var pos: Vector3 = source.get("position", game_state.get_position("aster"))
	return {
		"family": "terminal",
		"subtype": "credential",
		"effect": "reroute",
		"source_id": SOURCE_ID,
		"source_authority_key": SOURCE_KEY,
		"source_trigger_count": int(source.get("trigger_count", 0)),
		"actor": "aster",
		"source_position": [pos.x, pos.y, pos.z],
		"accepted_tick": scheduler.get_current_tick(),
	}


func _capture_transaction_seam(key: String, value: Variant) -> void:
	if key != beacon.authority_state_key() or not value is Dictionary:
		return
	var record := value as Dictionary
	if record.get("phase") == "route_applied" and seam_state.is_empty():
		seam_scheduler = _round_trip(scheduler.serialize())
		seam_state = _round_trip(game_state.serialize())
	elif record.get("phase") == "reset" and reset_seam_state.is_empty():
		reset_seam_scheduler = _round_trip(scheduler.serialize())
		reset_seam_state = _round_trip(game_state.serialize())


func _cell(x: int, z: int) -> Vector3:
	return game_state.grid.grid_to_world(Vector2i(x, z))


func _handoff(enemy_id: String) -> String:
	var saved := game_state.get_world_state(beacon.authority_state_key(), {}) as Dictionary
	for route in saved.get("applied_routes", []) as Array:
		if str(route.get("enemy_id", "")) == enemy_id:
			return str(route.get("handoff", ""))
	return ""


func _enemy_points(enemy_id: String) -> Array:
	var saved := game_state.get_world_state("runtime:enemy:" + enemy_id, {}) as Dictionary
	return (saved.get("patrol_waypoints", []) as Array).duplicate(true)


func _route_points(enemy_id: String) -> Array:
	for route in routes:
		if str(route.get("enemy_id", "")) == enemy_id:
			return _portable_points(route.get("points", []))
	return []


func _vectors_for_route(enemy_id: String) -> Array[Vector3]:
	for route in routes:
		if str(route.get("enemy_id", "")) == enemy_id:
			var output: Array[Vector3] = []
			output.assign(route.get("points", []))
			return output
	return []


func _portable_points(points: Array) -> Array:
	var output: Array = []
	for value in points:
		var point := value as Vector3
		output.append([point.x, point.y, point.z])
	return output


func _route_points_from_state(snapshot: Dictionary, enemy_id: String) -> Array:
	var world := snapshot.get("world_state", {}) as Dictionary
	var enemy := world.get("runtime:enemy:" + enemy_id, {}) as Dictionary
	return (enemy.get("patrol_waypoints", []) as Array).duplicate(true)


func _round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
		return
	failures += 1
	push_error("FAIL: %s" % label)
