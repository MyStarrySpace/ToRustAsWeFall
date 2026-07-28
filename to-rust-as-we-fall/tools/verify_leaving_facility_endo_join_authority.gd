extends SceneTree

## Focused authority regression for Leaving Facility's delayed Endo entrance.
## Run:
##   ..\Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_leaving_facility_endo_join_authority.gd

const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)


func _run() -> void:
	EventLog.print_events = false
	var source: Node = await _spawn_sequence()
	var gs: GameState = source._game_state
	var initial: Dictionary = source.headless_get_state()
	check(str((initial.get("endo_join_authority", {}) as Dictionary).get("phase", ""))
			== source.ENDO_JOIN_PHASE_ABSENT,
		"fresh story authority starts with Endo absent")
	check(not gs.characters.has("endo") and not gs.get_party().has("endo"),
		"the prebuilt Endo presenter is not registered or in the party before the join")
	check(not source._endo.visible and source._endo.process_mode == Node.PROCESS_MODE_DISABLED,
		"the absent Endo presenter is hidden and inert")
	check(not source._sector_route_interactables[0][0].is_interaction_enabled(),
		"route work stays dormant until the authored full roster exists")

	var first_station: Vector3 = source.IRON_SECTORS[0]["direct_station"]
	source.set_preview_character_position("aster", first_station)
	source.set_preview_character_position("peris", first_station + Vector3(0.0, 0.0, 0.8))
	source._on_sector_route_committed(0, "direct")
	check(str(source._sector_gates[0].get_authority_state().get("phase", ""))
			== PartyGate3D.PHASE_CLOSED,
		"an absent hidden Endo cannot satisfy the whole-party route mechanism")
	source._current_step = "first_corridor"
	source.set_preview_character_position("aster", Vector3(20.0, 0.0, 0.0))
	source._update_npc_follow()
	check(not gs.characters.has("endo") and not gs.is_moving("endo"),
		"NPC follow cannot turn the hidden presenter into a pre-join participant")

	# Commit the authored delay and save in its middle. The record owns the exact
	# deadline; the callback heap is deliberately discarded by the production loader.
	source._current_step = "facility_exit"
	source._begin_endo_join_wait()
	var pending: Dictionary = source._endo_join_authority_state()
	var pending_deadline := float(pending.get("deadline", -1.0))
	source._scheduler.advance_ticks(1.25)
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	check(str(pending.get("phase", "")) == source.ENDO_JOIN_PHASE_PENDING
			and pending_deadline > float(source._scheduler.get_current_tick()),
		"the delayed entrance is authoritative from commitment, before Endo exists")
	check(not gs.characters.has("endo") and not source._endo.visible,
		"mid-delay Endo contributes neither roster presence nor presentation")

	var loaded: Node = await _spawn_sequence()
	loaded.apply_save_snapshot(midpoint_snapshot)
	var loaded_pending: Dictionary = loaded._endo_join_authority_state()
	check(str(loaded_pending.get("phase", "")) == loaded.ENDO_JOIN_PHASE_PENDING
			and is_equal_approx(float(loaded_pending.get("deadline", -1.0)), pending_deadline),
		"fresh-presenter load restores the exact pending join deadline")
	check(not loaded._game_state.characters.has("endo")
			and not loaded._game_state.get_party().has("endo")
			and not loaded._endo.visible,
		"a pending save reloads with no Endo fog, party, or visible body")
	var remaining := pending_deadline - float(loaded._scheduler.get_current_tick())
	loaded._scheduler.advance_ticks(maxf(0.0, remaining - 0.001))
	check(not loaded._game_state.characters.has("endo"),
		"the restored entrance cannot register Endo before its saved endpoint")
	var joined_signal := {
		"snapshot": {},
		"body_present": false,
		"party_present": false,
	}
	var joined_signal_callback: Callable = func(key: String, value: Variant) -> void:
		if key != loaded.ENDO_JOIN_AUTHORITY_KEY or not value is Dictionary \
				or str((value as Dictionary).get("phase", "")) != loaded.ENDO_JOIN_PHASE_JOINED \
				or not (joined_signal.get("snapshot", {}) as Dictionary).is_empty():
			return
		joined_signal["body_present"] = loaded._game_state.characters.has("endo")
		joined_signal["party_present"] = loaded._game_state.get_party().has("endo")
		joined_signal["snapshot"] = _json_round_trip(loaded.build_save_snapshot())
	loaded._game_state.world_state_changed.connect(joined_signal_callback)
	loaded._scheduler.advance_ticks(0.002)
	loaded._game_state.world_state_changed.disconnect(joined_signal_callback)
	var joined: Dictionary = loaded.headless_get_state()
	check(str((joined.get("endo_join_authority", {}) as Dictionary).get("phase", ""))
			== loaded.ENDO_JOIN_PHASE_JOINED,
		"the saved endpoint commits the authored join phase")
	check(loaded._game_state.characters.has("endo")
			and loaded._game_state.get_party().has("endo")
			and bool(joined.get("endo_present", false)),
		"only the committed join registers Endo and admits him to the party")
	check(loaded._endo.visible and loaded._endo.process_mode != Node.PROCESS_MODE_DISABLED,
		"the Endo presenter derives visibility and activity from joined roster truth")
	var joined_signal_snapshot: Dictionary = joined_signal.get("snapshot", {}) as Dictionary
	var joined_signal_game_state: Dictionary = joined_signal_snapshot.get("game_state", {}) as Dictionary
	check(not joined_signal_snapshot.is_empty()
			and bool(joined_signal.get("body_present", false))
			and bool(joined_signal.get("party_present", false))
			and (joined_signal_game_state.get("characters", {}) as Dictionary).has("endo")
			and (joined_signal_game_state.get("party", []) as Array).has("endo"),
		"the exact JOINED publication boundary already owns Endo's body and party membership")
	check(loaded._sector_route_interactables[0][0].is_interaction_enabled(),
		"the first route decision appears only after the full roster joins")

	var joined_snapshot := _json_round_trip(loaded.build_save_snapshot())
	var joined_fresh: Node = await _spawn_sequence()
	joined_fresh.apply_save_snapshot(joined_snapshot)
	check(joined_fresh._endo_is_authoritatively_joined()
			and joined_fresh._endo.visible
			and joined_fresh._game_state.characters.has("endo"),
		"a fresh presenter derives post-join presence from the saved story record and roster")
	check(joined_fresh._game_state.is_moving("endo") == loaded._game_state.is_moving("endo")
			and joined_fresh._game_state.get_render_position("endo").is_equal_approx(
				loaded._game_state.get_render_position("endo")),
		"post-join reload preserves Endo's authoritative movement midpoint")

	# Roll the already-joined presenter back to its earlier snapshot. Deserialize
	# replaces the roster; the authority hook must also retract the visible future.
	joined_fresh.apply_save_snapshot(midpoint_snapshot)
	check(not joined_fresh._game_state.characters.has("endo")
			and not joined_fresh._game_state.get_party().has("endo")
			and not joined_fresh._endo.visible
			and joined_fresh._endo.process_mode == Node.PROCESS_MODE_DISABLED,
		"same-presenter rollback removes every future Endo participation surface")

	await _verify_event_replay()
	_end_sequence(source)
	_end_sequence(loaded)
	_end_sequence(joined_fresh)
	await process_frame
	print("LEAVING FACILITY ENDO JOIN AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_event_replay() -> void:
	var sequence: Node = await _spawn_sequence()
	var log := EventLog.new()
	sequence._game_state.event_log = log
	sequence._current_step = "facility_exit"
	sequence._begin_endo_join_wait()
	var deadline := float(sequence._endo_join_authority_state().get("deadline", -1.0))
	sequence._scheduler.advance_ticks(sequence.ENDO_JOIN_DELAY + 0.001)
	sequence._game_state.flush_tick()

	var prefix := EventLog.new()
	for event_v in log.events:
		var event := event_v as Dictionary
		if float(event.get("tick", 0.0)) >= deadline:
			break
		prefix.append(event.duplicate(true))
	prefix.recorded_until = maxf(0.0, deadline - 0.001)
	var replay_before := GameState.replay(prefix, sequence._grid)
	var replay_before_join: Variant = replay_before.get_world_state(
		sequence.ENDO_JOIN_AUTHORITY_KEY, null)
	check(replay_before_join is Dictionary
			and str((replay_before_join as Dictionary).get("phase", ""))
				== sequence.ENDO_JOIN_PHASE_PENDING
			and not replay_before.characters.has("endo"),
		"event replay before the endpoint contains pending story truth but no Endo body")

	var replay_after := GameState.replay(log, sequence._grid)
	var replay_after_join: Variant = replay_after.get_world_state(
		sequence.ENDO_JOIN_AUTHORITY_KEY, null)
	check(replay_after_join is Dictionary
			and str((replay_after_join as Dictionary).get("phase", ""))
				== sequence.ENDO_JOIN_PHASE_JOINED
			and replay_after.characters.has("endo")
			and replay_after.get_party().has("endo"),
		"full event replay reconstructs the same joined story phase and roster")
	_end_sequence(sequence)


func _spawn_sequence() -> Node:
	var sequence := LeavingFacilityScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(3):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._ui_scheduler.clear()
	sequence._ui_scheduler.resume()
	return sequence


func _end_sequence(sequence: Node) -> void:
	if not is_instance_valid(sequence):
		return
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.free()


func _json_round_trip(value: Variant) -> Dictionary:
	var text := JSON.stringify(value)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}
