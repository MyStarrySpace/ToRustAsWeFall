extends SceneTree

## Leaving Facility Shelter 1 authority regression:
## - exact full-conscious-party PartyGate rather than Aster's arrival;
## - side-effect-free malformed/downed/insufficient preflight;
## - one replayable GameState party-rest batch;
## - signal-time saves before payment and during ATP feedback;
## - same/fresh reconstruction of the saved absolute dawn deadline.

const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")
const EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source := await _spawn_sequence()
	_join_endo(source)
	_prepare_party(source, 8.0)

	_verify_party_gate(source)
	_verify_batch_preflight(source)
	_prepare_party(source, 8.0)
	source._current_step = "reach_shelter"
	# This snapshot is the deliberately inert pre-rest baseline. The focused continuation
	# verifier separately proves that an ordinary reach_shelter save resumes its named hand-off.
	source._cancel_portable_continuation()
	var ready_capture := _capture(source)

	var committing_box: Dictionary = {"snapshot": {}}
	var committing_callback: Callable = func(key: String, value: Variant) -> void:
		if key != source.SHELTER_REST_AUTHORITY_KEY or not value is Dictionary \
				or not (committing_box.get("snapshot", {}) as Dictionary).is_empty():
			return
		if str((value as Dictionary).get("phase", "")) \
				== source.SHELTER_REST_PHASE_COMMITTING:
			committing_box["snapshot"] = _capture(source)
	var signal_box: Dictionary = {"snapshot": {}}
	var stat_callback: Callable = func(char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and char_id in source.PARTY_IDS \
				and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(source)
	var rest_signals := {"started": 0, "stopped": 0, "nights": 0}
	var rest_started_callback: Callable = func(_char_id: String) -> void:
		rest_signals["started"] = int(rest_signals["started"]) + 1
	var rest_stopped_callback: Callable = func(_char_id: String) -> void:
		rest_signals["stopped"] = int(rest_signals["stopped"]) + 1
	var night_callback: Callable = func(_day: int) -> void:
		rest_signals["nights"] = int(rest_signals["nights"]) + 1
	source._game_state.world_state_changed.connect(committing_callback)
	source._game_state.stat_changed.connect(stat_callback)
	source._game_state.rest_started.connect(rest_started_callback)
	source._game_state.rest_stopped.connect(rest_stopped_callback)
	source._game_state.night_skipped.connect(night_callback)
	source._start_first_rest()
	source._game_state.world_state_changed.disconnect(committing_callback)
	source._game_state.stat_changed.disconnect(stat_callback)

	var committing_capture: Dictionary = committing_box.get("snapshot", {}) as Dictionary
	var signal_capture: Dictionary = signal_box.get("snapshot", {}) as Dictionary
	check(not committing_capture.is_empty() and _snapshot_party_atp(committing_capture, 8.0) \
			and _snapshot_clock_day(committing_capture) == 1,
		"COMMITTING publication is a coherent pre-payment save boundary")
	check(not signal_capture.is_empty() and _snapshot_party_atp(signal_capture, 7.0) \
			and _snapshot_clock_day(signal_capture) == 2 \
			and _snapshot_resting_count(signal_capture) == 0,
		"the first ATP signal can observe only the complete paid dawn, never a charged prefix")
	check(_all_atp(source._game_state, 7.0) and source._game_state.get_game_day() == 2 \
			and is_equal_approx(source._game_state.get_time_of_day(), GameState.DAWN_TIME),
		"the live party batch charges all three once and lands on canonical dawn")
	check(int(rest_signals["started"]) == 3 and int(rest_signals["stopped"]) == 3 \
			and int(rest_signals["nights"]) == 1,
		"the atomic night emits one complete trio lifecycle and one skip")
	var pending: Dictionary = source._shelter_rest_authority_state()
	var deadline := float(pending.get("dawn_deadline", -1.0))
	check(str(pending.get("phase", "")) == source.SHELTER_REST_PHASE_DAWN_PENDING \
			and bool(pending.get("cost_applied", false)) and deadline > source._scheduler.get_current_tick(),
		"paid shelter authority owns a future absolute dawn presentation deadline")
	var pending_capture := _capture(source)
	_advance_to_just_before(source, deadline)
	check(source._current_step == "first_rest",
		"the authoritative dawn presentation cannot finish before its saved deadline")
	source._scheduler.advance_ticks(EPSILON + 0.001)
	check(source._current_step == "dawn" \
			and str(source._shelter_rest_authority_state().get("phase", "")) \
				== source.SHELTER_REST_PHASE_COMPLETE,
		"crossing the deadline completes the saved shelter-rest phase exactly once")

	var precommit_fresh := await _spawn_sequence()
	precommit_fresh.apply_save_snapshot(committing_capture)
	check(_all_atp(precommit_fresh._game_state, 8.0) \
			and precommit_fresh._current_step == "first_rest",
		"fresh COMMITTING load preserves the pre-payment world before derived work runs")
	precommit_fresh._scheduler.advance_ticks(0.002)
	check(_all_atp(precommit_fresh._game_state, 7.0) \
			and precommit_fresh._game_state.get_game_day() == 2,
		"fresh COMMITTING load resumes one canonical whole-party transaction")

	var signal_fresh := await _spawn_sequence()
	var restore_counts := {"stats": 0, "rests": 0, "nights": 0}
	signal_fresh._game_state.stat_changed.connect(
		func(_id: String, _stat: String, _value: float): restore_counts["stats"] += 1)
	signal_fresh._game_state.rest_started.connect(
		func(_id: String): restore_counts["rests"] += 1)
	signal_fresh._game_state.night_skipped.connect(
		func(_day: int): restore_counts["nights"] += 1)
	signal_fresh.apply_save_snapshot(signal_capture)
	check(_all_atp(signal_fresh._game_state, 7.0) \
			and signal_fresh._game_state.get_game_day() == 2 \
			and int(restore_counts["stats"]) == 0 and int(restore_counts["rests"]) == 0 \
			and int(restore_counts["nights"]) == 0,
		"fresh signal-time restore neither repays, recharges, nor re-emits the night")
	var signal_authority: Dictionary = signal_fresh._shelter_rest_authority_state()
	_advance_across(signal_fresh, float(signal_authority.get("dawn_deadline", -1.0)))
	check(signal_fresh._current_step == "dawn" and _all_atp(signal_fresh._game_state, 7.0),
		"signal-time save resumes only its remaining dawn presentation")

	var pending_fresh := await _spawn_sequence()
	pending_fresh.apply_save_snapshot(pending_capture)
	var fresh_pending: Dictionary = pending_fresh._shelter_rest_authority_state()
	check(str(fresh_pending.get("phase", "")) == pending_fresh.SHELTER_REST_PHASE_DAWN_PENDING \
			and _all_atp(pending_fresh._game_state, 7.0),
		"fresh paid save reconstructs the portable dawn-pending phase")
	_advance_across(pending_fresh, float(fresh_pending.get("dawn_deadline", -1.0)))
	check(pending_fresh._current_step == "dawn",
		"fresh paid save completes at the original absolute deadline")

	# Roll the already-completed presenter back before the rest transaction. The party has physically
	# settled, but this deliberately inert fixture owns neither payment nor a named hand-off.
	source.apply_save_snapshot(ready_capture)
	check(source._current_step == "reach_shelter" and _all_atp(source._game_state, 8.0) \
			and str(source._shelter_rest_authority_state().get("phase", "")) \
				== source.SHELTER_REST_PHASE_IDLE,
		"same-presenter rollback retracts dawn, cost, and completion together")
	source._scheduler.advance_ticks(_shelter_dawn_delay_plus_margin(source))
	check(source._current_step == "reach_shelter" and _all_atp(source._game_state, 8.0),
		"rolled-back presenter retains no discarded-future dawn callback")

	await _verify_batch_replay()
	await _dispose(source)
	await _dispose(precommit_fresh)
	await _dispose(signal_fresh)
	await _dispose(pending_fresh)
	print("LEAVING FACILITY SHELTER AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_party_gate(sequence: Node) -> void:
	sequence._current_step = "second_iron"
	sequence._project_leaving_sources()
	check(not sequence._on_shelter_settle_requested(),
		"a direct shelter owner callback has no exact-source receipt and is inert")
	sequence._shelter_interactable.emit_signal("interacted")
	check(str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED,
		"a manually emitted shelter signal cannot counterfeit source acceptance")
	sequence.set_preview_character_position("aster", sequence.SHELTER_POS)
	sequence.set_preview_character_position("peris", sequence.SHELTER_POS + Vector3(-10.0, 0.0, 0.0))
	sequence.set_preview_character_position("endo", sequence.SHELTER_POS + Vector3(-12.0, 0.0, 0.0))
	check(not _trigger_shelter_source(sequence, "aster"),
		"the exact shelter source rejects a remote/incomplete party receipt")
	check(str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED and sequence._current_step == "second_iron",
		"Aster alone cannot turn endpoint proximity into shelter completion")

	_prepare_party(sequence, 8.0)
	var accepted_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, actor: String) -> void:
		if data_id == str(sequence._shelter_interactable.get("data_id")) \
				and actor == "aster" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _capture(sequence)
	sequence._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(_trigger_shelter_source(sequence, "aster"),
		"the exact shelter source accepts a nearby complete party receipt")
	check(str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_OPENING,
		"the complete trio commits a saved PartyGate settle window")
	sequence.set_preview_character_position("peris", sequence.SHELTER_POS + Vector3(-8.0, 0.0, 0.0))
	sequence._scheduler.advance_ticks(sequence.SHELTER_GATE_OPEN_DURATION + 0.001)
	check(str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED and sequence._current_step == "second_iron",
		"leaving during the settle window falsifies completion and remains retryable")
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the exact shelter acceptance boundary can be saved before PartyGate ownership")
	sequence.apply_save_snapshot(accepted_snapshot)
	check(str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
			== PartyGate3D.PHASE_CLOSED
			and sequence._current_step == "second_iron"
			and sequence._shelter_interactable.is_interaction_enabled(),
		"accepted-before-owner restore rearms the shelter without manufacturing settle progress")

	_prepare_party(sequence, 8.0)
	check(_trigger_shelter_source(sequence, "peris"),
		"the rearmed exact shelter source accepts the complete retry")
	sequence._scheduler.advance_ticks(sequence.SHELTER_GATE_OPEN_DURATION + 0.001)
	check(sequence._current_step == "reach_shelter" \
			and str(sequence._shelter_party_gate.get_authority_state().get("phase", "")) \
				== PartyGate3D.PHASE_OPEN,
		"only a complete trio still present at the endpoint enters the rest beat")
	sequence._cancel_portable_continuation()


func _trigger_shelter_source(sequence: Node, actor: String) -> bool:
	sequence._shelter_interactable.set("active_character", actor)
	return bool(sequence._shelter_interactable.call("_trigger", false))


func _verify_batch_preflight(sequence: Node) -> void:
	_prepare_party(sequence, 8.0)
	sequence._game_state.set_game_clock(1, 0.55)
	var before := _party_atp(sequence._game_state)
	check(not sequence._game_state.command_party_rest(["aster", "aster", "endo"]) \
			and _party_atp(sequence._game_state) == before,
		"duplicate malformed roster is rejected without ATP or rest mutation")
	check(not sequence._game_state.command_party_rest(["aster", "peris", "missing"]) \
			and _party_atp(sequence._game_state) == before,
		"missing member is rejected without charging a valid prefix")
	sequence._game_state.down_character("peris")
	check(not sequence._game_state.command_party_rest(sequence.PARTY_IDS) \
			and _party_atp(sequence._game_state) == before,
		"downed roster is rejected before any member pays")
	sequence._game_state.restore_character("peris")
	sequence.set_preview_character_position("peris", sequence.SHELTER_POS + Vector3(0.6, 0.0, 0.6))
	check(sequence._game_state.can_party_rest(sequence.PARTY_IDS),
		"a fully recovered full-ATP trio may still commit to canonical night rest")


func _verify_batch_replay() -> void:
	var sequence := await _spawn_sequence()
	_join_endo(sequence)
	_prepare_party(sequence, 8.0)
	sequence._game_state.set_game_clock(1, 0.55)
	var log := EventLog.new()
	sequence._game_state.event_log = log
	check(sequence._game_state.command_party_rest(sequence.PARTY_IDS),
		"canonical party batch accepts the replay fixture")
	sequence._game_state.flush_tick()
	var replayed := GameState.replay(log, sequence._grid)
	# The isolated log begins after scene registration, so replay needs the same baseline setup.
	# Verify the command itself is one event here; full story replay already covers registration order.
	check(log.events.size() == 1 \
			and StringName(log.events[0].get("kind", &"")) == GameEvent.KIND_PARTY_REST \
			and (log.events[0].get("payload", {}) as Dictionary).get("char_ids", []) \
				== sequence.PARTY_IDS,
		"party rest records one canonical batch event rather than three prefix-visible commands")
	# Keep the replay object live through dispatch; a no-baseline log must fail closed rather than mint state.
	check(replayed.characters.is_empty(),
		"a malformed replay without its roster baseline cannot mint a paid party")
	await _dispose(sequence)


func _spawn_sequence() -> Node:
	var sequence := LeavingFacilityScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(5):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._ui_scheduler.clear()
	sequence._ui_scheduler.resume()
	return sequence


func _join_endo(sequence: Node) -> void:
	sequence._current_step = "facility_exit"
	sequence._begin_endo_join_wait()
	sequence._scheduler.advance_ticks(sequence.ENDO_JOIN_DELAY + 0.001)
	sequence._scheduler.clear()
	sequence._scheduler.resume()


func _prepare_party(sequence: Node, atp: float) -> void:
	var offsets := {
		"aster": Vector3(-0.6, 0.0, 0.0),
		"peris": Vector3(0.6, 0.0, 0.6),
		"endo": Vector3(0.6, 0.0, -0.6),
	}
	for char_id in sequence.PARTY_IDS:
		if sequence._game_state.is_downed(char_id):
			sequence._game_state.restore_character(char_id)
		sequence.set_preview_character_position(char_id, sequence.SHELTER_POS + offsets[char_id])
		sequence._game_state.set_stat(char_id, "hp", GameState.HP_MAX)
		sequence._game_state.set_stat(char_id, "stamina", GameState.STAMINA_MAX)
		sequence._game_state.set_stat(char_id, "atp", atp)


func _capture(sequence: Node) -> Dictionary:
	return _json_round_trip(sequence.build_save_snapshot())


func _snapshot_party_atp(snapshot: Dictionary, expected: float) -> bool:
	var chars := (snapshot.get("game_state", {}) as Dictionary).get("characters", {}) as Dictionary
	for char_id in ["aster", "peris", "endo"]:
		var stats := (chars.get(char_id, {}) as Dictionary).get("stats", {}) as Dictionary
		if not is_equal_approx(float(stats.get("atp", -999.0)), expected):
			return false
	return true


func _snapshot_clock_day(snapshot: Dictionary) -> int:
	var clock := (snapshot.get("game_state", {}) as Dictionary).get("clock_state", {}) as Dictionary
	return int(clock.get("day", -1))


func _snapshot_resting_count(snapshot: Dictionary) -> int:
	return ((snapshot.get("game_state", {}) as Dictionary).get("resting", {}) as Dictionary).size()


func _party_atp(gs: GameState) -> Array[float]:
	return [gs.get_stat("aster", "atp"), gs.get_stat("peris", "atp"), gs.get_stat("endo", "atp")]


func _all_atp(gs: GameState, expected: float) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not is_equal_approx(gs.get_stat(char_id, "atp"), expected):
			return false
	return true


func _advance_to_just_before(sequence: Node, deadline: float) -> void:
	var remaining := deadline - float(sequence._scheduler.get_current_tick())
	sequence._scheduler.advance_ticks(maxf(0.0, remaining - EPSILON))


func _advance_across(sequence: Node, deadline: float) -> void:
	_advance_to_just_before(sequence, deadline)
	sequence._scheduler.advance_ticks(EPSILON + 0.001)


func _shelter_dawn_delay_plus_margin(sequence: Node) -> float:
	return sequence.SHELTER_DAWN_DELAY + 0.1


func _json_round_trip(value: Variant) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.free()
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		push_error("  FAIL: %s" % label)
