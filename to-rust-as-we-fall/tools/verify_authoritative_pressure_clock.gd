extends SceneTree

## Mid-interval save/load exploit regression for the scarcity clock. Reloading must not grant a
## fresh interval, duplicate a callback, or forget accumulated evidence.

const ClockScript := preload("res://scripts/system/simulation/atp_scarcity_clock.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := GameState.new()
	source_state.scheduler = source_scheduler
	source_state.register_character("aster", Vector3.ZERO, 3.0, {"atp": 4.0, "hp": 100.0})
	var source = ClockScript.new()
	source.configure(source_scheduler, source_state, ["aster"], {
		"drain_interval_seconds": 10.0,
		"drain_atp": 1.0,
		"zero_atp_hp_drain": 5.0,
	}, "authority_clock")
	check(source.begin(), "source clock begins")
	source_scheduler.advance_ticks(3.0)
	# The GameState record was published when the interval was armed, not polled every frame.
	# Its absolute deadline must still yield the correct remainder at the later save tick.
	var saved := _json_round_trip(source_state.get_world_state(source.authority_state_key(), {}))
	check(is_equal_approx(float(saved.get("next_tick", -1.0)), 10.0),
		"GameState owns the absolute pressure deadline")

	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.advance_ticks(3.0)
	var loaded_state := GameState.new()
	loaded_state.scheduler = loaded_scheduler
	loaded_state.register_character("aster", Vector3.ZERO, 3.0, {"atp": 4.0, "hp": 100.0})
	var loaded = ClockScript.new()
	loaded.configure(loaded_scheduler, loaded_state, ["aster"], {
		"drain_interval_seconds": 60.0,
		"drain_atp": 0.5,
	}, "wrong_fresh_defaults")
	loaded_state.set_world_state(loaded.authority_state_key(), saved)
	check(loaded.restore_from_authority(), "JSON GameState record restores onto a fresh scheduler")
	var restored := loaded.snapshot()
	check(bool(restored.get("started", false)) and bool(restored.get("armed", false))
			and is_equal_approx(float(restored.get("next_drain_in", -1.0)), 7.0),
		"restored clock preserves active ownership and remaining time")
	loaded_scheduler.advance_ticks(6.99)
	check(is_equal_approx(loaded_state.get_stat("aster", "atp"), 4.0),
		"restored pressure cannot fire before the saved deadline")
	loaded_scheduler.advance_ticks(0.01)
	check(is_equal_approx(loaded_state.get_stat("aster", "atp"), 3.0),
		"restored pressure fires once at the original deadline")
	check(int(loaded.snapshot().get("ticks", 0)) == 1,
		"restore neither duplicates nor forgets pressure evidence")

	var stopped_snapshot := loaded.snapshot()
	loaded.stop()
	stopped_snapshot = _json_round_trip(loaded.snapshot())
	var stopped_scheduler := EventScheduler.new()
	var stopped_state := GameState.new()
	stopped_state.scheduler = stopped_scheduler
	stopped_state.register_character("aster", Vector3.ZERO, 3.0, {"atp": 3.0, "hp": 100.0})
	var stopped = ClockScript.new()
	stopped.configure(stopped_scheduler, stopped_state, ["aster"])
	check(stopped.restore(stopped_snapshot) and not stopped.is_armed(),
		"a stopped saved clock remains stopped after load")
	stopped_scheduler.advance_ticks(120.0)
	check(is_equal_approx(stopped_state.get_stat("aster", "atp"), 3.0),
		"stopped restoration cannot leave a stale drain callback")

	print("AUTHORITATIVE PRESSURE CLOCK: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


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
