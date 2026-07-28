extends SceneTree

## A runner owns one stamina cadence whether RUN is enabled before or after movement begins.
## The latter used to rebuild movement, arm one callback there, then arm a second callback in
## set_running(), doubling the configured drain and making input order change the economy.

var _checks := 0
var _failures := 0


func _init() -> void:
	var before := _make_runner(true)
	var after := _make_runner(false)
	after.gs.set_running("runner", true)

	check(int((before.gs._running["runner"] as Dictionary).get("tick_handle", 0)) > 0,
		"run-before-move owns one armed cadence")
	check(int((after.gs._running["runner"] as Dictionary).get("tick_handle", 0)) > 0,
		"move-before-run owns one armed cadence after speed rebuild")

	_advance_ten_ticks(before.scheduler)
	_advance_ten_ticks(after.scheduler)
	var expected: float = 100.0 - float(before.gs.run_stamina_drain_per_sec)
	check(is_equal_approx(before.gs.get_stat("runner", "stamina"), expected),
		"run-before-move drains exactly the configured one-second budget")
	check(is_equal_approx(after.gs.get_stat("runner", "stamina"), expected),
		"move-before-run cannot double the configured drain")
	check(is_equal_approx(before.gs.get_stat("runner", "stamina"),
		after.gs.get_stat("runner", "stamina")),
		"input order has no effect on stamina economy")

	var toggled := _make_runner(false)
	toggled.gs.set_running("runner", true)
	toggled.scheduler.advance_ticks(0.2501)
	var after_two_ticks: float = toggled.gs.get_stat("runner", "stamina")
	toggled.gs.set_running("runner", false)
	toggled.gs.set_running("runner", true)
	toggled.scheduler.advance_ticks(0.1001)
	check(is_equal_approx(
		after_two_ticks - toggled.gs.get_stat("runner", "stamina"),
		toggled.gs.run_stamina_drain_per_sec * GameState.RUN_TICK_INTERVAL),
		"off/on while moving re-arms one, not two, drain callbacks")

	var snapshot_scheduler := _json_round_trip(toggled.scheduler.serialize())
	var snapshot_state := _json_round_trip(toggled.gs.serialize())
	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(snapshot_scheduler)
	var loaded := GameState.new()
	loaded.scheduler = loaded_scheduler
	loaded.deserialize(snapshot_state)
	var loaded_before := loaded.get_stat("runner", "stamina")
	loaded_scheduler.advance_ticks(0.1001)
	check(is_equal_approx(
		loaded_before - loaded.get_stat("runner", "stamina"),
		loaded.run_stamina_drain_per_sec * GameState.RUN_TICK_INTERVAL),
		"fresh restore also re-arms exactly one running cadence")

	print("RUNNING CADENCE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _make_runner(run_first: bool) -> Dictionary:
	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler
	gs.register_character("runner", Vector3.ZERO, GameState.WALK_SPEED, {
		"hp": 100.0, "stamina": 100.0, "atp": 8.0,
	})
	if run_first:
		gs.set_running("runner", true)
	check(gs.command_move_to_pos("runner", Vector3(120.0, 0.0, 0.0)),
		"fixture commits its long movement")
	return {"scheduler": scheduler, "gs": gs}


func _advance_ten_ticks(scheduler: EventScheduler) -> void:
	for _i in range(10):
		scheduler.advance_ticks(0.1001)


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
