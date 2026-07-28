extends SceneTree

## Midpoint save/load and rollback exploit regression for PartyGate3D. The gate must retain its
## absolute opening deadline, remain physically blocked until that deadline, and invalidate callbacks
## from a discarded timeline.

const GateScene := preload("res://scenes/tutorial/elevator_wreckage_gate.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scheduler := EventScheduler.new()
	var grid := _make_grid()
	var game_state := GameState.new()
	game_state.scheduler = scheduler
	game_state.grid = grid
	game_state.event_log = EventLog.new()

	var gate := GateScene.instantiate() as PartyGate3D
	gate.authority_id = "verify_midpoint_gate"
	gate.opening_duration = 4.0
	gate.position = Vector3(11.0, 0.0, 11.0)
	root.add_child(gate)
	await process_frame
	var anchor := gate.get_interaction_anchor()
	game_state.register_character("aster", anchor + Vector3(0.0, 0.0, -0.7), 3.0,
		{"hp": 100.0, "narrative_available": true})
	game_state.register_character("peris", anchor + Vector3(0.0, 0.0, 0.7), 3.0,
		{"hp": 100.0, "narrative_available": true})
	gate.setup(game_state, grid, 0, ["aster", "peris"])
	await process_frame

	var authority_key := gate.authority_state_key()
	check(authority_key == "gameplay:party_gate:verify_midpoint_gate",
		"authored identity produces a stable, instance-independent key")
	check(str(gate.get_authority_state().get("phase", "")) == "closed"
			and _owned_blocker_count(grid, gate) > 0,
		"the initial authoritative CLOSED phase owns navigation blockers")
	var blocker := gate.get_node_or_null("RubbleBlocker/BlockerShape") as CollisionShape3D
	check(blocker != null and not blocker.disabled,
		"the initial CLOSED phase owns physical collision")

	var closed_scheduler := _json_round_trip(scheduler.serialize())
	var closed_state := _json_round_trip(game_state.serialize())
	var opened_count := [0]
	gate.opened.connect(func(): opened_count[0] += 1)
	var host_context := {"route": "safe", "commit_order": 2}
	check(gate.begin_open(host_context), "the ready pair commits one authoritative opening window")
	var committed := gate.get_authority_state()
	check(str(committed.get("contract", "")) == "party_gate_3d/v1"
			and str(committed.get("phase", "")) == "opening"
			and is_equal_approx(float(committed.get("start_tick", -1.0)), 0.0)
			and is_equal_approx(float(committed.get("end_tick", -1.0)), 4.0)
			and committed.get("context", {}) == host_context,
		"GameState records the full absolute opening interval and host context at commitment")
	check(not gate.commit_open(), "the public commit seam cannot skip the saved delay")

	scheduler.advance_ticks(1.5)
	game_state.flush_tick()
	var midpoint_scheduler := _json_round_trip(scheduler.serialize())
	var midpoint_state := _json_round_trip(game_state.serialize())
	check(gate.state == PartyGate3D.State.OPENING and _owned_blocker_count(grid, gate) > 0,
		"the gate remains physically blocked at the midpoint")
	var replayed := GameState.replay(
		EventLog.from_bytes(game_state.event_log.to_bytes()), null)
	var replayed_gate: Dictionary = replayed.get_world_state(authority_key, {})
	check(str(replayed_gate.get("phase", "")) == "opening"
			and is_equal_approx(float(replayed_gate.get("end_tick", -1.0)), 4.0)
			and replayed_gate.get("context", {}) == host_context,
		"event replay reconstructs the same midpoint commitment and context without a gate node")

	# Production order: clear opaque Callables, restore scheduler clock, replace GameState, then notify
	# presenters. The deadline must remain tick 4.0 rather than restarting four seconds from tick 1.5.
	scheduler.clear()
	scheduler.deserialize(midpoint_scheduler)
	game_state.deserialize(midpoint_state)
	gate.on_game_state_snapshot_restored()
	await process_frame
	var restored := gate.get_authority_state()
	check(gate.state == PartyGate3D.State.OPENING
			and is_equal_approx(float(restored.get("end_tick", -1.0)), 4.0)
			and _owned_blocker_count(grid, gate) > 0 and not blocker.disabled,
		"midpoint load rebuilds OPENING collision/navigation from GameState")
	scheduler.advance_ticks(2.49)
	await process_frame
	check(gate.state == PartyGate3D.State.OPENING and opened_count[0] == 0,
		"the restored gate cannot open before its original deadline")
	scheduler.advance_ticks(0.01)
	await process_frame
	check(gate.state == PartyGate3D.State.OPEN and opened_count[0] == 1,
		"the restored gate opens exactly once after only the saved remainder")
	var open_context: Dictionary = gate.get_authority_state().get("context", {})
	check(str(open_context.get("route", "")) == "safe"
			and int(open_context.get("commit_order", -1)) == 2,
		"OPEN preserves the exact host context committed with OPENING")
	check(blocker.disabled and _owned_blocker_count(grid, gate) == 0,
		"OPEN reconstructs collision and navigation as passable")

	# Roll back to the pre-commit snapshot. The now-discarded tick-4 callback must not reopen the gate.
	scheduler.clear()
	scheduler.deserialize(closed_scheduler)
	game_state.deserialize(closed_state)
	gate.on_game_state_snapshot_restored()
	await process_frame
	check(gate.state == PartyGate3D.State.CLOSED and not blocker.disabled
			and _owned_blocker_count(grid, gate) > 0,
		"rollback reconstructs the closed barrier immediately")
	scheduler.advance_ticks(10.0)
	await process_frame
	check(gate.state == PartyGate3D.State.CLOSED and opened_count[0] == 1,
		"a stale callback from the discarded opening timeline cannot reopen the gate")

	gate.free()
	print("PARTY GATE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _make_grid() -> GridWorld:
	var grid := GridWorld.new()
	grid.create_room(24, 24, false)
	return grid


func _owned_blocker_count(grid: GridWorld, gate: PartyGate3D) -> int:
	var owner := str(gate.get("_dynamic_blocker_id"))
	var count := 0
	for value in grid.dynamic_blockers.values():
		if str(value) == owner:
			count += 1
	return count


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
