extends SceneTree

## A cadenced hazard beat is one cohort transaction, not three unrelated synchronous stat calls.
## These regressions save from the first body's stat_changed signal, after canonical HP has changed
## but before the reusable object can finish its loop. Same/fresh restoration must preserve the
## first payment, finish the other two once, and retain the cadence deadline reserved at beat start.

const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const GridRiskFieldScript := preload("res://scripts/game/objects/grid_risk_field.gd")
const IDS := ["aster", "peris", "endo"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_verify_hazard_field_batch()
	_verify_grid_risk_field_batch()
	print("HAZARD BATCH SIGNAL ATOMICITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_hazard_field_batch() -> void:
	var scheduler := EventScheduler.new()
	var state := _hazard_state(scheduler)
	var callback_count := [0]
	var seam := {"capture": {}}
	var source = HazardFieldScript.new()
	root.add_child(source)
	source.setup(
		state,
		scheduler,
		Vector2(-2.0, -2.0),
		Vector2(2.0, 2.0),
		IDS,
		{
			"dps_tick": 10.0,
			"interval": 4.0,
			"tag": "batch_signal_hazard",
			"on_bite": func(_id: String): callback_count[0] += 1,
		}
	)
	source.set_active(true)
	var capture_handler := func(_id: String, stat: String, _value: float) -> void:
		if stat != "hp" or not (seam.capture as Dictionary).is_empty():
			return
		seam.capture = _capture(scheduler, state)
		# Fan-out must use the cohort sampled before this first observable signal. Moving later
		# bodies now cannot erase their already-reserved contact.
		state.snap_character_to("peris", Vector3(20.0, 0.0, 20.0))
		state.snap_character_to("endo", Vector3(22.0, 0.0, 22.0))
	state.stat_changed.connect(capture_handler)
	scheduler.advance_ticks(4.0)
	state.stat_changed.disconnect(capture_handler)

	var capture: Dictionary = seam.capture
	var record := _authority_record(capture, source.authority_state_key())
	var batch: Dictionary = record.get("pending_batch", {})
	var targets: Array = batch.get("targets", [])
	check(
		targets.size() == 3
			and bool((targets[0] as Dictionary).get("damage_committed", false))
			and not bool((targets[1] as Dictionary).get("damage_committed", true))
			and not bool((targets[2] as Dictionary).get("damage_committed", true)),
		"HazardField first-signal save owns the exact three-body cohort and per-target progress"
	)
	check(
		is_equal_approx(float(record.get("next_bite_tick", -1.0)), 8.0)
			and is_equal_approx(float(batch.get("next_bite_tick", -1.0)), 8.0),
		"HazardField publishes the following absolute cadence deadline before fan-out"
	)
	check(
		_hp_is(state, [90.0, 90.0, 90.0]) and callback_count[0] == 3,
		"HazardField completes its pre-sampled cohort even if the first signal moves later bodies"
	)

	var same_signals := [0]
	state.stat_changed.connect(func(_id: String, stat: String, _value: float) -> void:
		if stat == "hp":
			same_signals[0] += 1
	)
	_apply_capture(scheduler, state, source, capture)
	source.on_game_state_snapshot_restored()
	check(
		_hp_is(state, [90.0, 100.0, 100.0]) and same_signals[0] == 0,
		"HazardField same-presenter restore (including restore twice) emits no damage"
	)
	var callbacks_before_same: int = int(callback_count[0])
	scheduler.advance_ticks(0.001)
	check(
		_hp_is(state, [90.0, 90.0, 90.0])
			and same_signals[0] == 2
			and callback_count[0] == callbacks_before_same + 3,
		"HazardField same-presenter reconciliation skips the paid body and finishes two unpaid bodies once"
	)
	check(
		is_equal_approx(float(source.get_state().get("next_bite_tick", -1.0)), 8.0),
		"HazardField same-presenter reconciliation preserves the reserved next deadline"
	)
	scheduler.advance_ticks(3.998)
	check(
		_hp_is(state, [90.0, 90.0, 90.0]),
		"HazardField reconciled cohort cannot start its following beat early"
	)
	scheduler.advance_ticks(0.001)
	check(
		_hp_is(state, [80.0, 80.0, 80.0]),
		"HazardField following beat still charges every exposed body exactly once"
	)

	var fresh_scheduler := EventScheduler.new()
	var fresh_state := _hazard_state(fresh_scheduler)
	fresh_scheduler.deserialize(capture.get("scheduler", {}))
	fresh_state.deserialize(capture.get("game_state", {}))
	var fresh_callbacks := [0]
	var fresh = HazardFieldScript.new()
	root.add_child(fresh)
	fresh.setup(
		fresh_state,
		fresh_scheduler,
		Vector2(-2.0, -2.0),
		Vector2(2.0, 2.0),
		IDS,
		{
			"dps_tick": 1.0,
			"interval": 30.0,
			"tag": "batch_signal_hazard",
			"restore_existing_authority": true,
			"on_bite": func(_id: String): fresh_callbacks[0] += 1,
		}
	)
	var fresh_signals := [0]
	fresh_state.stat_changed.connect(func(_id: String, stat: String, _value: float) -> void:
		if stat == "hp":
			fresh_signals[0] += 1
	)
	fresh.on_game_state_snapshot_restored()
	check(
		_hp_is(fresh_state, [90.0, 100.0, 100.0]) and fresh_signals[0] == 0,
		"HazardField fresh reconstruction and repeated restore remain side-effect free"
	)
	fresh_scheduler.advance_ticks(0.001)
	check(
		_hp_is(fresh_state, [90.0, 90.0, 90.0])
			and fresh_signals[0] == 2
			and fresh_callbacks[0] == 3,
		"HazardField fresh reconstruction resumes the exact unpaid suffix and callbacks once"
	)
	check(
		is_equal_approx(float(fresh.get_state().get("next_bite_tick", -1.0)), 8.0),
		"HazardField fresh reconstruction retains saved cadence rather than fresh defaults"
	)

	source.free()
	fresh.free()


func _verify_grid_risk_field_batch() -> void:
	var grid := _make_grid()
	var scheduler := EventScheduler.new()
	var state := _grid_state(scheduler, grid)
	var callback_count := [0]
	var seam := {"capture": {}}
	var source = GridRiskFieldScript.new()
	root.add_child(source)
	source.setup(
		state,
		scheduler,
		grid,
		[{"cell": [2, 1], "penalty": 5.0}],
		IDS,
		{
			"tag": "batch_signal_grid",
			"interval": 2.0,
			"damage_rate_scale": 1.0,
			"active": true,
			"on_bite": func(_id, _damage, _cell, _penalty): callback_count[0] += 1,
		}
	)
	var capture_handler := func(_id: String, stat: String, _value: float) -> void:
		if stat != "hp" or not (seam.capture as Dictionary).is_empty():
			return
		seam.capture = _capture(scheduler, state)
		state.snap_character_to("peris", grid.grid_to_world(Vector2i(0, 0)))
		state.snap_character_to("endo", grid.grid_to_world(Vector2i(0, 1)))
	state.stat_changed.connect(capture_handler)
	scheduler.advance_ticks(2.0)
	state.stat_changed.disconnect(capture_handler)

	var capture: Dictionary = seam.capture
	var record := _authority_record(capture, source.authority_state_key())
	var batch: Dictionary = record.get("pending_batch", {})
	var targets: Array = batch.get("targets", [])
	var contacts: Dictionary = record.get("contact_ticks", {})
	check(
		targets.size() == 3
			and bool((targets[0] as Dictionary).get("damage_committed", false))
			and not bool((targets[1] as Dictionary).get("damage_committed", true))
			and not bool((targets[2] as Dictionary).get("damage_committed", true)),
		"GridRiskField first-signal save owns the exact three-body cohort and per-target progress"
	)
	check(
		is_equal_approx(float(record.get("damage_total", -1.0)), 10.0)
			and int(contacts.get("aster", 0)) == 1
			and int(contacts.get("peris", 0)) == 0
			and int(contacts.get("endo", 0)) == 0,
		"GridRiskField publishes first-target contact bookkeeping before its stat signal"
	)
	check(
		is_equal_approx(float(record.get("next_tick", -1.0)), 4.0)
			and is_equal_approx(float(batch.get("next_tick", -1.0)), 4.0),
		"GridRiskField publishes the following absolute cadence deadline before fan-out"
	)
	check(
		_hp_is(state, [90.0, 90.0, 90.0])
			and callback_count[0] == 3
			and is_equal_approx(float(source.get_state().get("damage_total", -1.0)), 30.0),
		"GridRiskField completes its pre-sampled cohort and exact contact accounting"
	)

	var same_signals := [0]
	state.stat_changed.connect(func(_id: String, stat: String, _value: float) -> void:
		if stat == "hp":
			same_signals[0] += 1
	)
	_apply_capture(scheduler, state, source, capture)
	source.on_game_state_snapshot_restored()
	check(
		_hp_is(state, [90.0, 100.0, 100.0]) and same_signals[0] == 0,
		"GridRiskField same-presenter restore (including restore twice) emits no damage"
	)
	var callbacks_before_same: int = int(callback_count[0])
	scheduler.advance_ticks(0.001)
	var same_state: Dictionary = source.get_state()
	var same_contacts: Dictionary = same_state.get("contact_ticks", {})
	check(
		_hp_is(state, [90.0, 90.0, 90.0])
			and same_signals[0] == 2
			and callback_count[0] == callbacks_before_same + 3
			and is_equal_approx(float(same_state.get("damage_total", -1.0)), 30.0)
			and int(same_contacts.get("aster", 0)) == 1
			and int(same_contacts.get("peris", 0)) == 1
			and int(same_contacts.get("endo", 0)) == 1,
		"GridRiskField same-presenter reconciliation has no duplicate damage or contact receipt"
	)
	check(
		is_equal_approx(float(same_state.get("next_tick", -1.0)), 4.0),
		"GridRiskField same-presenter reconciliation preserves the reserved next deadline"
	)
	scheduler.advance_ticks(1.998)
	check(
		_hp_is(state, [90.0, 90.0, 90.0]),
		"GridRiskField reconciled cohort cannot start its following beat early"
	)
	scheduler.advance_ticks(0.002)
	check(
		_hp_is(state, [80.0, 80.0, 80.0]),
		"GridRiskField following beat still charges every exposed body exactly once"
	)

	var fresh_grid := _make_grid()
	var fresh_scheduler := EventScheduler.new()
	var fresh_state := _grid_state(fresh_scheduler, fresh_grid)
	fresh_scheduler.deserialize(capture.get("scheduler", {}))
	fresh_state.deserialize(capture.get("game_state", {}))
	var fresh_callbacks := [0]
	var fresh = GridRiskFieldScript.new()
	root.add_child(fresh)
	fresh.setup(
		fresh_state,
		fresh_scheduler,
		fresh_grid,
		[{"cell": [0, 0], "penalty": 1.0}],
		["aster"],
		{
			"tag": "batch_signal_grid",
			"interval": 30.0,
			"damage_rate_scale": 0.1,
			"active": false,
			"restore_existing_authority": true,
			"on_bite": func(_id, _damage, _cell, _penalty): fresh_callbacks[0] += 1,
		}
	)
	var fresh_signals := [0]
	fresh_state.stat_changed.connect(func(_id: String, stat: String, _value: float) -> void:
		if stat == "hp":
			fresh_signals[0] += 1
	)
	fresh.on_game_state_snapshot_restored()
	check(
		_hp_is(fresh_state, [90.0, 100.0, 100.0]) and fresh_signals[0] == 0,
		"GridRiskField fresh reconstruction and repeated restore remain side-effect free"
	)
	fresh_scheduler.advance_ticks(0.001)
	var fresh_record: Dictionary = fresh.get_state()
	var fresh_contacts: Dictionary = fresh_record.get("contact_ticks", {})
	check(
		_hp_is(fresh_state, [90.0, 90.0, 90.0])
			and fresh_signals[0] == 2
			and fresh_callbacks[0] == 3
			and is_equal_approx(float(fresh_record.get("damage_total", -1.0)), 30.0)
			and int(fresh_contacts.get("aster", 0)) == 1
			and int(fresh_contacts.get("peris", 0)) == 1
			and int(fresh_contacts.get("endo", 0)) == 1,
		"GridRiskField fresh reconstruction resumes saved damage, callbacks, and receipts once"
	)
	check(
		is_equal_approx(float(fresh_record.get("next_tick", -1.0)), 4.0),
		"GridRiskField fresh reconstruction retains saved cadence rather than fresh defaults"
	)

	source.free()
	fresh.free()


func _hazard_state(scheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	for id in IDS:
		state.register_character(id, Vector3.ZERO, 3.0, {"hp": 100.0, "stamina": 100.0})
	return state


func _grid_state(scheduler, grid: GridWorld) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.grid = grid
	var position := grid.grid_to_world(Vector2i(2, 1))
	for id in IDS:
		state.register_character(id, position, 3.0, {"hp": 100.0, "stamina": 100.0})
	return state


func _make_grid() -> GridWorld:
	var grid := GridWorld.new()
	grid.create_room(8, 5)
	return grid


func _hp_is(state: GameState, expected: Array) -> bool:
	for idx in range(IDS.size()):
		if not is_equal_approx(float(state.get_stat(IDS[idx], "hp")), float(expected[idx])):
			return false
	return true


func _capture(scheduler, state: GameState) -> Dictionary:
	return _json_round_trip({
		"scheduler": scheduler.serialize(),
		"game_state": state.serialize(),
	})


func _apply_capture(scheduler, state: GameState, presenter, capture: Dictionary) -> void:
	scheduler.clear()
	scheduler.deserialize(capture.get("scheduler", {}))
	state.deserialize(capture.get("game_state", {}))
	presenter.on_game_state_snapshot_restored()


func _authority_record(capture: Dictionary, key: String) -> Dictionary:
	var game_state: Dictionary = capture.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	return world_state.get(key, {}) as Dictionary


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
