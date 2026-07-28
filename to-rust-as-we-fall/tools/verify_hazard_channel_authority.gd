extends SceneTree

## Mid-phase save/load regression for the reusable cadence kit. This exercises production-shaped
## scheduler clear + clock restore + GameState replacement, then asks each presenter to reattach.

const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const ChannelScript := preload("res://scripts/game/objects/channel.gd")

var _checks := 0
var _failures := 0


class SweepEnemyStub:
	extends RefCounted
	signal died()
	var state: GameState
	var character_id := ""
	var damage_calls := 0
	var damage_total := 0.0
	var stun_calls := 0
	var last_stun := 0.0
	var stunned := false

	func _init(source_state: GameState, source_id: String) -> void:
		state = source_state
		character_id = source_id

	func take_damage(amount: float) -> void:
		damage_calls += 1
		damage_total += amount
		state.adjust_stat(character_id, "hp", -amount)
		if not is_alive():
			died.emit()

	func is_alive() -> bool:
		return float(state.get_stat(character_id, "hp")) > 0.0

	func get_hp() -> float:
		return float(state.get_stat(character_id, "hp"))

	func stun(duration: float) -> void:
		stun_calls += 1
		last_stun = duration
		stunned = true

	func is_stunned() -> bool:
		return stunned


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_hazard_field()
	_verify_channel_strict_future_boundary()
	_verify_channel()
	_verify_channel_traversal_started_atomicity()
	_verify_channel_party_impact_signal_atomicity()
	_verify_channel_enemy_death_signal_atomicity()
	print("HAZARD/CHANNEL AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_hazard_field() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := _state_with_aster(source_scheduler)
	var before_field_existed := _capture(source_scheduler, source_state)
	var source_bites := [0]
	var source = HazardFieldScript.new()
	root.add_child(source)
	source.setup(source_state, source_scheduler, Vector2(-2.0, -2.0), Vector2(2.0, 2.0),
		["aster"], {"dps_tick": 10.0, "interval": 4.0, "tag": "authority_hazard",
			"on_bite": func(_id): source_bites[0] += 1})
	source.set_active(true)
	source_scheduler.advance_ticks(1.5)
	var active_midpoint := _capture(source_scheduler, source_state)
	var active_record: Dictionary = source_state.get_world_state(source.authority_state_key(), {})
	check(bool(active_record.get("active", false))
			and is_equal_approx(float(active_record.get("next_bite_tick", -1.0)), 4.0),
		"HazardField stores its active phase and absolute bite deadline in GameState")

	var loaded_scheduler := EventScheduler.new()
	var loaded_state := _state_with_aster(loaded_scheduler)
	var loaded_bites := [0]
	var loaded = HazardFieldScript.new()
	root.add_child(loaded)
	# Deliberately wrong fresh defaults prove that the saved phase contract, not reconstruction order,
	# controls the already-committed bite.
	loaded.setup(loaded_state, loaded_scheduler, Vector2(-2.0, -2.0), Vector2(2.0, 2.0),
		["aster"], {"dps_tick": 1.0, "interval": 30.0, "tag": "authority_hazard",
			"on_bite": func(_id): loaded_bites[0] += 1})
	_apply_capture(loaded_scheduler, loaded_state, loaded, active_midpoint)
	check(loaded.is_active()
			and is_equal_approx(float(loaded.get_state().get("next_bite_in", -1.0)), 2.5),
		"active HazardField restores the exact midpoint remainder")
	loaded_scheduler.advance_ticks(2.49)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 100.0)
			and loaded_bites[0] == 0,
		"restored HazardField cannot bite before the saved deadline")
	loaded_scheduler.advance_ticks(0.01)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 90.0)
			and loaded_bites[0] == 1,
		"restored HazardField bites exactly once at the original deadline")

	# Run ahead, then load the earlier midpoint back into the SAME presenter. A stale later callback
	# must be retracted and the earlier HP/deadline must become true again.
	loaded_scheduler.advance_ticks(4.0)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 80.0)
			and loaded_bites[0] == 2,
		"live HazardField keeps one recurring cadence before rollback")
	var bites_before_rollback := int(loaded_bites[0])
	_apply_capture(loaded_scheduler, loaded_state, loaded, active_midpoint)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 100.0)
			and is_equal_approx(float(loaded.get_state().get("next_bite_in", -1.0)), 2.5),
		"loading an earlier HazardField save retracts later damage and timing")
	loaded_scheduler.advance_ticks(2.5)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 90.0)
			and loaded_bites[0] == bites_before_rollback + 1,
		"earlier rollback leaves one, not duplicated, HazardField callback")

	loaded.set_active(false)
	var inactive_capture := _capture(loaded_scheduler, loaded_state)
	loaded.set_active(true)
	loaded_scheduler.advance_ticks(4.0)
	_apply_capture(loaded_scheduler, loaded_state, loaded, inactive_capture)
	var hp_while_inactive := float(loaded_state.get_stat("aster", "hp"))
	loaded_scheduler.advance_ticks(20.0)
	check(not loaded.is_active()
			and is_equal_approx(loaded_state.get_stat("aster", "hp"), hp_while_inactive),
		"an inactive saved HazardField stays inactive with no stale bite callback")

	# The field is spawned only after the thermal mistake in production. Loading a save from before
	# it existed must retract the later node-local active bit even though no authority key exists yet.
	_apply_capture(source_scheduler, source_state, source, before_field_existed)
	var hp_before_absent_advance := float(source_state.get_stat("aster", "hp"))
	source_scheduler.advance_ticks(12.0)
	check(not source.is_active()
			and is_equal_approx(source_state.get_stat("aster", "hp"), hp_before_absent_advance),
		"loading before a HazardField existed retracts the later activation instead of preserving it")

	source.free()
	loaded.free()


func _verify_channel_strict_future_boundary() -> void:
	var scheduler := EventScheduler.new()
	scheduler.advance_ticks(4.1)
	var channel = ChannelScript.new()
	channel.set("_scheduler", scheduler)
	channel.set("_sweep_epoch", 0.1)
	check(is_equal_approx(float(channel.call("_next_sweep_from_epoch")), 4.6),
		"Channel fractional sweep epoch reconstructs the next strict-future poll, not now")
	channel.free()


func _verify_channel() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := _state_with_channel_actors(source_scheduler)
	var source_counts := {"party": 0, "enemy": 0}
	var source_foe := SweepEnemyStub.new(source_state, "wash_enemy")
	var source = ChannelScript.new()
	source.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "authority_channel")
	root.add_child(source)
	_wire_sweep(source, source_state, source_counts, source_foe)
	source.start(source_scheduler, source_state)
	source_scheduler.advance_ticks(0.01)
	check(source.is_flooding() and _water_visible(source),
		"Channel onset makes the physical current visible before it can catch a body")
	source_scheduler.advance_ticks(0.05)
	var party_start: Dictionary = source_state.get_external_traversal_state("aster")
	var enemy_start: Dictionary = source_state.get_external_traversal_state("wash_enemy")
	check(str(party_start.get("traversal_id", "")) == "channel_sweep/authority_channel/aster"
			and str(enemy_start.get("traversal_id", "")) ==
				"channel_sweep/authority_channel/wash_enemy",
		"party and a resolved enemy in the wet strip enter explicit channel-owned traversals")
	check(not source_state.is_external_traversal_active("peris")
			and not source_state.is_external_traversal_active("bystander")
			and source_state.get_position("peris").is_equal_approx(Vector3(5.0, 0.0, 0.0))
			and source_state.get_position("bystander").is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"spatial selection excludes an outside party member and an unresolved bystander in the strip")
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and is_equal_approx(source_state.get_stat("wash_enemy", "hp"), 100.0)
			and source_counts.party == 0 and source_counts.enemy == 0,
		"the catch poll owns movement but applies no early party or enemy consequence")

	# Poll spam while the current owns the bodies must neither restart progress nor queue impacts.
	source.call("_sweep_poll")
	check((source.get_state().get("active_sweeps", {}) as Dictionary).size() == 2
			and is_equal_approx(float(source_state.get_external_traversal_state("aster").get(
				"progress", -1.0)), 0.0),
		"repeated catch polling cannot duplicate or restart a channel-owned carry")

	source_scheduler.advance_ticks(0.5)
	check(source_state.get_position("aster").is_equal_approx(Vector3(3.0, 0.0, 0.0))
			and source_state.get_position("wash_enemy").is_equal_approx(Vector3(3.0, 0.0, 1.0)),
		"halfway through the carry both authoritative bodies are physically halfway downstream")
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and is_equal_approx(source_state.get_stat("wash_enemy", "hp"), 100.0),
		"mid-carry state has neither reached the destination nor paid the arrival consequence")
	var carry_midpoint := _capture(source_scheduler, source_state)
	source_scheduler.advance_ticks(0.49)
	check(source_state.get_position("aster").x < 6.0
			and is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and source_counts.party == 0,
		"the visible carry cannot damage or commit its destination before impact")
	source_scheduler.advance_ticks(0.01)
	check(source_state.get_position("aster").is_equal_approx(Vector3(6.0, 0.0, 0.0))
			and is_equal_approx(source_state.get_stat("aster", "hp"), 94.0)
			and source_counts.party == 1,
		"party damage and bookkeeping commit exactly once at visible arrival")
	check(source_state.get_position("wash_enemy").is_equal_approx(Vector3(6.0, 0.0, 1.0))
			and is_equal_approx(source_state.get_stat("wash_enemy", "hp"), 88.0)
			and source_foe.damage_calls == 1 and is_equal_approx(source_foe.damage_total, 12.0)
			and source_foe.stun_calls == 1 and is_equal_approx(source_foe.last_stun, 2.5)
			and source_counts.enemy == 1,
		"enemy damage, tumble, and bookkeeping commit exactly once at its arrival")
	source_scheduler.advance_ticks(0.5)
	check(source_counts.party == 1 and source_counts.enemy == 1,
		"later flood polls cannot repeat either completed impact inside its refractory window")

	# Same-presenter rollback reconstructs the midpoint, including spatial progress and pending policy.
	var party_before_same := int(source_counts.party)
	var enemy_before_same := int(source_counts.enemy)
	_apply_capture(source_scheduler, source_state, source, carry_midpoint)
	check(source_state.get_position("aster").is_equal_approx(Vector3(3.0, 0.0, 0.0))
			and is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and (source.get_state().get("active_sweeps", {}) as Dictionary).size() == 2,
		"same-presenter restore retracts arrival and recovers exact midpoint ownership")
	source_scheduler.advance_ticks(0.5)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 94.0)
			and is_equal_approx(source_state.get_stat("wash_enemy", "hp"), 88.0)
			and source_counts.party == party_before_same + 1
			and source_counts.enemy == enemy_before_same + 1,
		"same-presenter midpoint restore produces one impact per body, never zero or two")

	# A fresh presenter is deliberately wired with wrong current defaults. The already-committed
	# traversal must retain the damage/stun policy captured when the source current caught it.
	var loaded_scheduler := EventScheduler.new()
	var loaded_state := _state_with_channel_actors(loaded_scheduler)
	var loaded_counts := {"party": 0, "enemy": 0}
	var loaded_foe := SweepEnemyStub.new(loaded_state, "wash_enemy")
	var loaded = ChannelScript.new()
	loaded.configure(0.0, 2.0, 2.0, 20.0, 5.0, 10.0, "authority_channel")
	root.add_child(loaded)
	_wire_sweep(loaded, loaded_state, loaded_counts, loaded_foe,
		{"party_hp": 1.0, "enemy_damage": 1.0, "enemy_stun": 0.25})
	loaded.start(loaded_scheduler, loaded_state)
	_apply_capture(loaded_scheduler, loaded_state, loaded, carry_midpoint)
	check(loaded.is_flooding() and _water_visible(loaded)
			and loaded_state.get_position("aster").is_equal_approx(Vector3(3.0, 0.0, 0.0)),
		"fresh reconstruction restores the wet presenter and exact midpoint position")
	loaded_scheduler.advance_ticks(0.499)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 100.0)
			and loaded_counts.party == 0 and loaded_counts.enemy == 0,
		"fresh midpoint reconstruction cannot resolve either impact early")
	loaded_scheduler.advance_ticks(0.001)
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 94.0)
			and is_equal_approx(loaded_state.get_stat("wash_enemy", "hp"), 88.0)
			and loaded_counts.party == 1 and loaded_counts.enemy == 1
			and is_equal_approx(loaded_foe.damage_total, 12.0)
			and is_equal_approx(loaded_foe.last_stun, 2.5),
		"fresh reconstruction resolves saved impact policy exactly once, not fresh defaults")

	_verify_channel_absence_restore()
	_verify_channel_frame_invariance()
	source.free()
	loaded.free()


func _verify_channel_traversal_started_atomicity() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := _state_with_channel_party(source_scheduler)
	var source_counts := {"party": 0, "enemy": 0}
	var source_foe := SweepEnemyStub.new(source_state, "aster")
	var source = ChannelScript.new()
	source.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "signal_start_channel")
	root.add_child(source)
	_wire_sweep(source, source_state, source_counts, source_foe)
	var signal_capture := {"snapshot": {}}
	source_state.external_traversal_started.connect(
		func(id: String, _traversal: Dictionary) -> void:
			if id == "aster" and (signal_capture.get("snapshot", {}) as Dictionary).is_empty():
				signal_capture["snapshot"] = _capture(source_scheduler, source_state)
	)
	source.start(source_scheduler, source_state)
	source_scheduler.advance_ticks(0.061)
	var started_capture: Dictionary = signal_capture.get("snapshot", {})
	var captured_record := _channel_record_from_capture(
		started_capture, source.authority_state_key())
	var captured_sweeps: Dictionary = captured_record.get("active_sweeps", {})
	var captured_aster: Dictionary = captured_sweeps.get("aster", {})
	check(not started_capture.is_empty()
			and str(captured_aster.get("phase", "")) == "reserved"
			and float(captured_record.get("next_sweep_tick", -1.0)) > 0.061,
		"external_traversal_started sees a pre-published reservation and continuing sweep cadence")

	# Roll the same presenter back after command_external_traversal returned. The reservation and the
	# GameState traversal are paired by ID, so two restore notifications can only promote one carry.
	_apply_capture(source_scheduler, source_state, source, started_capture)
	source.on_game_state_snapshot_restored()
	var same_sweeps: Dictionary = source.get_state().get("active_sweeps", {})
	check(source_state.is_external_traversal_active("aster")
			and same_sweeps.size() == 1
			and str((same_sweeps.get("aster", {}) as Dictionary).get("phase", "")) == "carrying",
		"same presenter restores a start-signal reservation into exactly one owned carry")
	var same_count_before := int(source_counts.party)
	source_scheduler.advance_ticks(1.0)
	check(source_state.get_position("aster").is_equal_approx(Vector3(6.0, 0.0, 0.0))
			and is_equal_approx(source_state.get_stat("aster", "hp"), 94.0)
			and int(source_counts.party) == same_count_before + 1
			and (source.get_state().get("active_sweeps", {}) as Dictionary).is_empty(),
		"same-presenter start-signal restore produces one arrival and one impact")
	source_scheduler.advance_ticks(4.95)
	check(source.is_flooding()
			and float(source.get_state().get("next_onset_tick", -1.0)) > 6.011,
		"same-presenter start-signal restore leaves the recurring Channel cadence active")

	var loaded_scheduler := EventScheduler.new()
	var loaded_state := _state_with_channel_party(loaded_scheduler)
	var loaded_counts := {"party": 0, "enemy": 0}
	var loaded_foe := SweepEnemyStub.new(loaded_state, "aster")
	var loaded = ChannelScript.new()
	loaded.configure(0.0, 2.0, 2.0, 30.0, 10.0, 9.0, "signal_start_channel")
	root.add_child(loaded)
	_wire_sweep(loaded, loaded_state, loaded_counts, loaded_foe, {"party_hp": 1.0})
	loaded.start(loaded_scheduler, loaded_state)
	_apply_capture(loaded_scheduler, loaded_state, loaded, started_capture)
	loaded.on_game_state_snapshot_restored()
	check(loaded_state.is_external_traversal_active("aster")
			and (loaded.get_state().get("active_sweeps", {}) as Dictionary).size() == 1,
		"fresh presenter restores the start-signal snapshot without duplicating its traversal")
	loaded_scheduler.advance_ticks(1.0)
	check(loaded_state.get_position("aster").is_equal_approx(Vector3(6.0, 0.0, 0.0))
			and is_equal_approx(loaded_state.get_stat("aster", "hp"), 94.0)
			and int(loaded_counts.party) == 1,
		"fresh start-signal reconstruction preserves the reserved impact policy exactly once")
	loaded_scheduler.advance_ticks(4.95)
	check(loaded.is_flooding()
			and float(loaded.get_state().get("next_onset_tick", -1.0)) > 6.011,
		"fresh start-signal reconstruction preserves the authored recurring cadence")
	source.free()
	loaded.free()


func _verify_channel_party_impact_signal_atomicity() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := _state_with_channel_party(source_scheduler)
	var source_counts := {"party": 0, "enemy": 0}
	var source_foe := SweepEnemyStub.new(source_state, "aster")
	var source = ChannelScript.new()
	source.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "signal_stat_channel")
	root.add_child(source)
	_wire_sweep(source, source_state, source_counts, source_foe)
	var signal_capture := {"snapshot": {}}
	source_state.stat_changed.connect(
		func(id: String, stat: String, value: float) -> void:
			if id == "aster" and stat == "hp" and is_equal_approx(value, 94.0) \
					and (signal_capture.get("snapshot", {}) as Dictionary).is_empty():
				signal_capture["snapshot"] = _capture(source_scheduler, source_state)
	)
	source.start(source_scheduler, source_state)
	source_scheduler.advance_ticks(1.061)
	var impact_capture: Dictionary = signal_capture.get("snapshot", {})
	var captured_record := _channel_record_from_capture(
		impact_capture, source.authority_state_key())
	var captured_aster: Dictionary = (captured_record.get(
		"active_sweeps", {}) as Dictionary).get("aster", {})
	check(not impact_capture.is_empty()
			and str(captured_aster.get("phase", "")) == "party_damage_committing"
			and is_equal_approx(_capture_stat(impact_capture, "aster", "hp"), 94.0),
		"first party stat signal sees the saved impact transaction and its applied HP edge")

	var source_callbacks_before := int(source_counts.party)
	_apply_capture(source_scheduler, source_state, source, impact_capture)
	var callbacks_after_first_restore := int(source_counts.party)
	source.on_game_state_snapshot_restored()
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 94.0)
			and callbacks_after_first_restore == source_callbacks_before + 1
			and int(source_counts.party) == callbacks_after_first_restore
			and (source.get_state().get("active_sweeps", {}) as Dictionary).is_empty(),
		"same presenter reconciles a stat-signal save once and a second restore is idempotent")
	source_scheduler.advance_ticks(4.95)
	check(source.is_flooding(),
		"party stat-signal reconciliation does not retract the Channel cadence")

	var loaded_scheduler := EventScheduler.new()
	var loaded_state := _state_with_channel_party(loaded_scheduler)
	var loaded_counts := {"party": 0, "enemy": 0}
	var loaded_foe := SweepEnemyStub.new(loaded_state, "aster")
	var loaded = ChannelScript.new()
	loaded.configure(0.0, 2.0, 2.0, 30.0, 10.0, 9.0, "signal_stat_channel")
	root.add_child(loaded)
	_wire_sweep(loaded, loaded_state, loaded_counts, loaded_foe, {"party_hp": 1.0})
	loaded.start(loaded_scheduler, loaded_state)
	var loaded_stat_signals := [0]
	loaded_state.stat_changed.connect(
		func(id: String, stat: String, _value: float) -> void:
			if id == "aster" and stat == "hp":
				loaded_stat_signals[0] += 1
	)
	_apply_capture(loaded_scheduler, loaded_state, loaded, impact_capture)
	loaded.on_game_state_snapshot_restored()
	check(is_equal_approx(loaded_state.get_stat("aster", "hp"), 94.0)
			and loaded_stat_signals[0] == 0
			and int(loaded_counts.party) == 1
			and (loaded.get_state().get("active_sweeps", {}) as Dictionary).is_empty(),
		"fresh presenter recognizes the captured party hit and cannot charge it twice")
	loaded_scheduler.advance_ticks(4.95)
	check(loaded.is_flooding(),
		"fresh party impact reconstruction retains the next authored wet phase")
	source.free()
	loaded.free()


func _verify_channel_enemy_death_signal_atomicity() -> void:
	var source_scheduler := EventScheduler.new()
	var source_state := _state_with_channel_enemy(source_scheduler)
	var source_counts := {"party": 0, "enemy": 0}
	var source_foe := SweepEnemyStub.new(source_state, "wash_enemy")
	var source = ChannelScript.new()
	source.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "signal_death_channel")
	root.add_child(source)
	_wire_sweep(source, source_state, source_counts, source_foe)
	var signal_capture := {"snapshot": {}}
	source_foe.died.connect(
		func() -> void:
			if (signal_capture.get("snapshot", {}) as Dictionary).is_empty():
				signal_capture["snapshot"] = _capture(source_scheduler, source_state)
	)
	source.start(source_scheduler, source_state)
	source_scheduler.advance_ticks(1.061)
	var death_capture: Dictionary = signal_capture.get("snapshot", {})
	var captured_record := _channel_record_from_capture(
		death_capture, source.authority_state_key())
	var captured_enemy: Dictionary = (captured_record.get(
		"active_sweeps", {}) as Dictionary).get("wash_enemy", {})
	check(not death_capture.is_empty()
			and str(captured_enemy.get("phase", "")) == "enemy_damage_committing"
			and is_equal_approx(_capture_stat(death_capture, "wash_enemy", "hp"), 0.0),
		"enemy death signal sees an explicit committing receipt paired with the lethal HP result")

	var damage_calls_before := source_foe.damage_calls
	var callbacks_before := int(source_counts.enemy)
	_apply_capture(source_scheduler, source_state, source, death_capture)
	var callbacks_after_first_restore := int(source_counts.enemy)
	source.on_game_state_snapshot_restored()
	check(is_equal_approx(source_state.get_stat("wash_enemy", "hp"), 0.0)
			and source_foe.damage_calls == damage_calls_before
			and source_foe.stun_calls == 0
			and callbacks_after_first_restore == callbacks_before + 1
			and int(source_counts.enemy) == callbacks_after_first_restore,
		"same presenter neither repeats lethal damage nor stuns a dead body across two restores")
	source_scheduler.advance_ticks(4.95)
	check(source.is_flooding(),
		"enemy death-signal reconciliation leaves subsequent Channel cycles scheduled")

	var loaded_scheduler := EventScheduler.new()
	var loaded_state := _state_with_channel_enemy(loaded_scheduler)
	var loaded_counts := {"party": 0, "enemy": 0}
	var loaded_foe := SweepEnemyStub.new(loaded_state, "wash_enemy")
	var loaded_deaths := [0]
	loaded_foe.died.connect(func() -> void: loaded_deaths[0] += 1)
	var loaded = ChannelScript.new()
	loaded.configure(0.0, 2.0, 2.0, 30.0, 10.0, 9.0, "signal_death_channel")
	root.add_child(loaded)
	_wire_sweep(loaded, loaded_state, loaded_counts, loaded_foe,
		{"enemy_damage": 1.0, "enemy_stun": 9.0})
	loaded.start(loaded_scheduler, loaded_state)
	_apply_capture(loaded_scheduler, loaded_state, loaded, death_capture)
	loaded.on_game_state_snapshot_restored()
	check(is_equal_approx(loaded_state.get_stat("wash_enemy", "hp"), 0.0)
			and loaded_foe.damage_calls == 0 and loaded_deaths[0] == 0
			and loaded_foe.stun_calls == 0 and int(loaded_counts.enemy) == 1,
		"fresh presenter consumes the saved lethal receipt without a second hit, death, or stun")
	loaded_scheduler.advance_ticks(4.95)
	check(loaded.is_flooding(),
		"fresh enemy death reconstruction preserves the recurring current")
	source.free()
	loaded.free()


func _state_with_aster(scheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("aster", Vector3.ZERO, 3.0, {"hp": 100.0, "stamina": 100.0})
	return state


func _state_with_channel_actors(scheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("aster", Vector3.ZERO, 3.0, {"hp": 100.0, "stamina": 100.0})
	state.register_character("peris", Vector3(5.0, 0.0, 0.0), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	state.register_character("wash_enemy", Vector3(0.0, 0.0, 1.0), 3.0, {"hp": 100.0})
	state.register_character("bystander", Vector3(0.0, 0.0, -1.0), 3.0, {"hp": 100.0})
	return state


func _state_with_channel_party(scheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("aster", Vector3.ZERO, 3.0, {"hp": 100.0, "stamina": 100.0})
	state.register_character("peris", Vector3(5.0, 0.0, 0.0), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	return state


func _state_with_channel_enemy(scheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("wash_enemy", Vector3.ZERO, 3.0, {"hp": 10.0})
	return state


func _wire_sweep(channel, state: GameState, counters: Dictionary, foe: SweepEnemyStub,
		overrides: Dictionary = {}) -> void:
	var opts := {
		"party_hp": 6.0,
		"enemy_damage": 12.0,
		"enemy_stun": 2.5,
		"refractory": 4.0,
		"travel_speed": 6.0,
		"min_travel_duration": 0.45,
		"enemy_resolver": func(id: String):
			return foe if id == "wash_enemy" else null,
		"on_swept": func(_id: String): counters.party = int(counters.party) + 1,
		"on_enemy_swept": func(_id: String): counters.enemy = int(counters.enemy) + 1,
	}
	opts.merge(overrides, true)
	channel.set_sweep(state, ["aster", "peris"],
		func(_id: String, position: Vector3) -> Vector3:
			return Vector3(6.0, 0.0, position.z), opts)


func _verify_channel_absence_restore() -> void:
	var scheduler := EventScheduler.new()
	var state := _state_with_channel_actors(scheduler)
	var before_channel_existed := _capture(scheduler, state)
	var counters := {"party": 0, "enemy": 0}
	var foe := SweepEnemyStub.new(state, "wash_enemy")
	var channel = ChannelScript.new()
	channel.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "absent_channel")
	root.add_child(channel)
	_wire_sweep(channel, state, counters, foe)
	channel.start(scheduler, state)
	scheduler.advance_ticks(0.061)
	check(state.is_external_traversal_active("aster")
			and (channel.get_state().get("active_sweeps", {}) as Dictionary).size() == 2,
		"absence fixture first proves later channel carries really exist")
	_apply_capture(scheduler, state, channel, before_channel_existed)
	var hp_after_restore := float(state.get_stat("aster", "hp"))
	scheduler.advance_ticks(12.0)
	check(not channel.is_flooding() and not _water_visible(channel)
			and not state.is_external_traversal_active("aster")
			and is_equal_approx(state.get_stat("aster", "hp"), hp_after_restore)
			and counters.party == 0 and counters.enemy == 0,
		"loading before Channel authority existed retracts cadence, carries, and pending impacts")
	check(state.get_world_state(channel.authority_state_key(), null) == null,
		"absence restore does not recreate the missing authority record as a side effect")
	channel.free()


func _verify_channel_frame_invariance() -> void:
	var coarse := _run_channel_projection([1.2])
	var fine_steps: Array = []
	for _i in range(120):
		fine_steps.append(0.01)
	var fine := _run_channel_projection(fine_steps)
	check((coarse.aster_position as Vector3).is_equal_approx(fine.aster_position as Vector3)
			and (coarse.enemy_position as Vector3).is_equal_approx(fine.enemy_position as Vector3)
			and is_equal_approx(float(coarse.aster_hp), float(fine.aster_hp))
			and is_equal_approx(float(coarse.enemy_hp), float(fine.enemy_hp))
			and coarse.party_impacts == fine.party_impacts
			and coarse.enemy_impacts == fine.enemy_impacts,
		"one coarse scheduler advance and many fine advances produce identical sweep outcomes")


func _run_channel_projection(steps: Array) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := _state_with_channel_actors(scheduler)
	var counters := {"party": 0, "enemy": 0}
	var foe := SweepEnemyStub.new(state, "wash_enemy")
	var channel = ChannelScript.new()
	channel.configure(0.0, 2.0, 2.0, 6.0, 2.0, 0.0, "frame_channel")
	root.add_child(channel)
	_wire_sweep(channel, state, counters, foe)
	channel.start(scheduler, state)
	for delta_v in steps:
		scheduler.advance_ticks(float(delta_v))
	var result := {
		"aster_position": state.get_position("aster"),
		"enemy_position": state.get_position("wash_enemy"),
		"aster_hp": state.get_stat("aster", "hp"),
		"enemy_hp": state.get_stat("wash_enemy", "hp"),
		"party_impacts": int(counters.party),
		"enemy_impacts": int(counters.enemy),
	}
	channel.free()
	return result


func _capture(scheduler, state: GameState) -> Dictionary:
	return _json_round_trip({
		"scheduler": scheduler.serialize(),
		"game_state": state.serialize(),
	})


func _channel_record_from_capture(capture: Dictionary, key: String) -> Dictionary:
	var game_state: Dictionary = capture.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var value: Variant = world_state.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _capture_stat(capture: Dictionary, id: String, stat: String) -> float:
	var game_state: Dictionary = capture.get("game_state", {})
	var characters: Dictionary = game_state.get("characters", {})
	var character: Dictionary = characters.get(id, {})
	var stats: Dictionary = character.get("stats", {})
	return float(stats.get(stat, -1.0))


func _apply_capture(scheduler, state: GameState, presenter, capture: Dictionary) -> void:
	scheduler.clear()
	scheduler.deserialize(capture.get("scheduler", {}))
	state.deserialize(capture.get("game_state", {}))
	presenter.on_game_state_snapshot_restored()


func _water_visible(channel) -> bool:
	var water := channel.get_node_or_null("Water") as MeshInstance3D
	return water != null and water.visible


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
