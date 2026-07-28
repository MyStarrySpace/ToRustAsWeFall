extends SceneTree

## Elevator Junction shelter-rest authority regression:
## - exact authored shelter + exact conscious trio, with no hidden guard bodies;
## - canonical delivered water and one atomic ATP payment per party member;
## - coherent saves at COMMITTING, night-clock, and first ATP signal boundaries;
## - deterministic same/fresh reconstruction of the absolute night-watch deadline.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")
const EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_static_guardrails()
	await _verify_guard_retirement()

	var source := await _spawn_elevator()
	var water_item_id := _stage_ready_party(source, 8.0)
	check(water_item_id != "" and source._junction_party_can_commit_rest(),
		"fixture owns one settled exact trio and Endo's canonical delivered water")

	_verify_side_effect_free_preflight(source, water_item_id)
	water_item_id = _stage_ready_party(source, 8.0)
	var ready_capture := _capture(source)

	var committing_box := {"snapshot": {}}
	var committing_callback: Callable = func(key: String, value: Variant) -> void:
		if key != source.JUNCTION_REST_AUTHORITY_KEY or not value is Dictionary \
				or not (committing_box["snapshot"] as Dictionary).is_empty():
			return
		if str((value as Dictionary).get("phase", "")) \
				== source.JUNCTION_REST_PHASE_COMMITTING:
			committing_box["snapshot"] = _capture(source)
	var clock_box := {"snapshot": {}}
	var clock_callback: Callable = func(_day: int, _time: float) -> void:
		if (clock_box["snapshot"] as Dictionary).is_empty():
			clock_box["snapshot"] = _capture(source)
	var stat_box := {"snapshot": {}}
	var stat_callback: Callable = func(character_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and character_id in source.JUNCTION_REST_PARTY \
				and (stat_box["snapshot"] as Dictionary).is_empty():
			stat_box["snapshot"] = _capture(source)
	var lifecycle := {"started": 0, "stopped": 0, "nights": 0}
	var started_callback: Callable = func(_character_id: String) -> void:
		lifecycle["started"] = int(lifecycle["started"]) + 1
	var stopped_callback: Callable = func(_character_id: String) -> void:
		lifecycle["stopped"] = int(lifecycle["stopped"]) + 1
	var night_callback: Callable = func(_day: int) -> void:
		lifecycle["nights"] = int(lifecycle["nights"]) + 1
	source._game_state.world_state_changed.connect(committing_callback)
	source._game_state.game_clock_changed.connect(clock_callback)
	source._game_state.stat_changed.connect(stat_callback)
	source._game_state.rest_started.connect(started_callback)
	source._game_state.rest_stopped.connect(stopped_callback)
	source._game_state.night_skipped.connect(night_callback)
	# Isolate the transaction trace from fixture construction. Interactive scenes normally attach
	# this log through the playthrough session; the focused script supplies the same canonical sink.
	source._game_state.event_log = EventLog.new()
	var event_start := _event_count(source)
	check(source._start_night_watch(),
		"the exact settled trio commits the canonical junction rest transaction")
	source._game_state.world_state_changed.disconnect(committing_callback)
	source._game_state.game_clock_changed.disconnect(clock_callback)
	source._game_state.stat_changed.disconnect(stat_callback)

	var committing_capture: Dictionary = committing_box["snapshot"] as Dictionary
	var clock_capture: Dictionary = clock_box["snapshot"] as Dictionary
	var stat_capture: Dictionary = stat_box["snapshot"] as Dictionary
	check(not committing_capture.is_empty() \
			and _snapshot_all_atp(committing_capture, 8.0) \
			and _snapshot_item_held(committing_capture, water_item_id, "endo") \
			and _snapshot_day(committing_capture) == 1,
		"COMMITTING publication is a coherent pre-water/pre-payment save boundary")
	check(not clock_capture.is_empty() \
			and _snapshot_all_atp(clock_capture, 8.0) \
			and _snapshot_item_held(clock_capture, water_item_id, "endo") \
			and is_equal_approx(_snapshot_time(clock_capture), source.JUNCTION_REST_NIGHT_TIME),
		"night-clock feedback still owns a pending transaction with water and ATP intact")
	check(not stat_capture.is_empty() \
			and _snapshot_all_atp(stat_capture, 7.0) \
			and not _snapshot_has_item(stat_capture, water_item_id) \
			and _snapshot_day(stat_capture) == 2 \
			and _snapshot_resting_count(stat_capture) == 0,
		"the first ATP signal observes only consumed water and the complete paid dawn")
	check(_all_atp(source, 7.0) and not source._game_state.items.has(water_item_id) \
			and source._game_state.get_game_day() == 2 \
			and is_equal_approx(source._game_state.get_time_of_day(), GameState.DAWN_TIME),
		"live authority consumes one water, charges all three once, and reaches canonical dawn")
	check(int(lifecycle["started"]) == 3 and int(lifecycle["stopped"]) == 3 \
			and int(lifecycle["nights"]) == 1,
		"one atomic rest emits one complete trio lifecycle and one night skip")
	var transaction_event_kinds := _event_kinds(source, event_start)
	var expected_transaction_tail: Array[StringName] = [
			GameEvent.KIND_SET_WORLD_STATE,
			GameEvent.KIND_SET_GAME_CLOCK,
			GameEvent.KIND_REMOVE_ITEM,
			GameEvent.KIND_PARTY_REST,
			GameEvent.KIND_SET_WORLD_STATE,
	]
	var transaction_tail: Array = transaction_event_kinds.slice(
		maxi(0, transaction_event_kinds.size() - expected_transaction_tail.size()))
	check(transaction_tail == expected_transaction_tail \
			and transaction_event_kinds.count(GameEvent.KIND_REMOVE_ITEM) == 1 \
			and transaction_event_kinds.count(GameEvent.KIND_PARTY_REST) == 1,
		"event log records semantic precommit, night, water, one party batch, then paid watch: %s" \
			% str(transaction_event_kinds))

	var authority: Dictionary = source._junction_rest_authority_state()
	var deadline := float(authority.get("dawn_deadline", -1.0))
	check(str(authority.get("phase", "")) == source.JUNCTION_REST_PHASE_NIGHT_WATCH \
			and bool(authority.get("water_consumed", false)) \
			and bool(authority.get("cost_applied", false)) \
			and deadline > source._scheduler.get_current_tick(),
		"paid authority owns an absolute, still-pending night-watch deadline")
	source._scheduler.advance_ticks(3.15)
	var midpoint_capture := _capture(source)
	check(str(source._current_step) == "night_watch" \
			and source._monster_eyes.size() == 12 \
			and not source._drink_mesh.visible,
		"midpoint presentation derives deterministic eyes and consumed-water absence")
	_advance_to_just_before(source, deadline)
	check(str(source._current_step) == "night_watch",
		"live night watch cannot complete before its saved deadline")
	source._scheduler.advance_ticks(EPSILON + 0.001)
	check(str(source._current_step) == "dawn" \
			and str(source._junction_rest_authority_state().get("phase", "")) \
				== source.JUNCTION_REST_PHASE_COMPLETE,
		"live night watch completes once at the absolute deadline")

	# Roll the completed presenter back to the paid midpoint. Repeated attachment must replace,
	# rather than multiply, every derived eye and deadline callback.
	source.apply_save_snapshot(midpoint_capture)
	var same_authority: Dictionary = source._junction_rest_authority_state()
	check(str(source._current_step) == "night_watch" \
			and source._monster_eyes.size() == 12 and _all_atp(source, 7.0) \
			and not source._game_state.items.has(water_item_id),
		"same-presenter rollback retracts dawn to the exact paid night midpoint")
	var same_pending := int(source._scheduler.pending_count())
	var same_events := _event_count(source)
	source.on_game_state_snapshot_restored()
	source.on_game_state_snapshot_restored()
	check(source._scheduler.pending_count() == same_pending \
			and source._monster_eyes.size() == 12,
		"repeated midpoint attachment keeps one deadline and one deterministic eye set")
	check(_event_count(source) == same_events,
		"repeated midpoint attachment emits no rest, water, clock, or story command")
	_advance_across(source, float(same_authority.get("dawn_deadline", -1.0)))
	check(str(source._current_step) == "dawn" and _all_atp(source, 7.0),
		"same presenter resumes only the remaining watch and never pays twice")

	var fresh_midpoint := await _spawn_elevator()
	fresh_midpoint.apply_save_snapshot(midpoint_capture)
	var fresh_authority: Dictionary = fresh_midpoint._junction_rest_authority_state()
	check(str(fresh_midpoint._current_step) == "night_watch" \
			and fresh_midpoint._monster_eyes.size() == 12 \
			and _all_atp(fresh_midpoint, 7.0) \
			and not fresh_midpoint._game_state.items.has(water_item_id),
		"fresh presenter reconstructs the identical paid night midpoint")
	_advance_across(fresh_midpoint, float(fresh_authority.get("dawn_deadline", -1.0)))
	check(str(fresh_midpoint._current_step) == "dawn" \
			and _all_atp(fresh_midpoint, 7.0),
		"fresh presenter reaches the same endpoint without duplicating cost")

	await _verify_signal_time_restores(committing_capture, clock_capture, stat_capture, water_item_id)

	# A same-presenter rollback before the semantic commit retracts cost, consumed water, night,
	# presentation, and the discarded future deadline together.
	source.apply_save_snapshot(ready_capture)
	check(str(source._current_step) == "endo_delivered" \
			and _all_atp(source, 8.0) \
			and source._game_state.items.has(water_item_id) \
			and source._endo_holds_drink() \
			and source._monster_eyes.is_empty(),
		"precommit rollback restores delivered water and retracts the whole paid future")
	source._scheduler.advance_ticks(source.JUNCTION_REST_WATCH_SECONDS + 0.2)
	check(str(source._current_step) == "endo_delivered" and _all_atp(source, 8.0),
		"precommit rollback retains no stale dawn callback")

	await _destroy_elevator(fresh_midpoint)
	await _destroy_elevator(source)
	print("ELEVATOR JUNCTION REST AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_side_effect_free_preflight(elevator: Node, water_item_id: String) -> void:
	var outside: Vector3 = elevator.JUNCTION_SHELTER_CENTER + Vector3(
		elevator.JUNCTION_SHELTER_HALF_SIZE.x + 1.0, 0.0, 0.0)
	elevator._game_state.snap_character_to("aster", outside)
	var event_count := _event_count(elevator)
	var day: int = elevator._game_state.get_game_day()
	var time: float = elevator._game_state.get_time_of_day()
	check(not elevator._start_night_watch() \
			and _event_count(elevator) == event_count \
			and _all_atp(elevator, 8.0) \
			and elevator._game_state.items.has(water_item_id) \
			and elevator._game_state.get_game_day() == day \
			and is_equal_approx(elevator._game_state.get_time_of_day(), time),
		"one body outside exact shelter geometry is rejected without side effects")

	_stage_ready_party(elevator, 8.0)
	elevator._game_state.down_character("peris")
	event_count = _event_count(elevator)
	check(not elevator._start_night_watch() \
			and _event_count(elevator) == event_count \
			and _all_atp_except_downed(elevator, 8.0) \
			and elevator._game_state.items.has(water_item_id),
		"a downed party member is rejected before water, clock, or any valid member's ATP changes")
	elevator._game_state.restore_character("peris")
	elevator._game_state.set_stat("peris", "hp", GameState.HP_MAX)

	_stage_ready_party(elevator, 8.0)
	elevator._game_state.register_character(
		"hidden_proxy", elevator.JUNCTION_SHELTER_CENTER, 1.0, {"hp": 1.0})
	event_count = _event_count(elevator)
	check(not elevator._start_night_watch() \
			and _event_count(elevator) == event_count \
			and elevator._game_state.items.has(water_item_id),
		"an extra hidden GameState body cannot be ignored by the all-conscious rest contract")
	elevator._game_state.unregister_character("hidden_proxy")


func _verify_signal_time_restores(
		committing_capture: Dictionary,
		clock_capture: Dictionary,
		stat_capture: Dictionary,
		water_item_id: String) -> void:
	var precommit := await _spawn_elevator()
	precommit.apply_save_snapshot(committing_capture)
	check(_all_atp(precommit, 8.0) and precommit._endo_holds_drink() \
			and str(precommit._junction_rest_authority_state().get("phase", "")) \
				== precommit.JUNCTION_REST_PHASE_COMMITTING,
		"fresh COMMITTING load preserves the pre-payment world until derived work resumes")
	precommit._scheduler.advance_ticks(0.002)
	check(_all_atp(precommit, 7.0) and not precommit._game_state.items.has(water_item_id) \
			and precommit._game_state.get_game_day() == 2,
		"fresh COMMITTING load performs exactly one whole transaction")

	var clock_signal := await _spawn_elevator()
	clock_signal.apply_save_snapshot(clock_capture)
	check(_all_atp(clock_signal, 8.0) and clock_signal._endo_holds_drink() \
			and is_equal_approx(
				clock_signal._game_state.get_time_of_day(), clock_signal.JUNCTION_REST_NIGHT_TIME),
		"fresh clock-signal load recognizes night as a pending, unpaid transaction")
	clock_signal._scheduler.advance_ticks(0.002)
	check(_all_atp(clock_signal, 7.0) \
			and not clock_signal._game_state.items.has(water_item_id),
		"clock-signal restore resumes one water/cost batch rather than replaying the invitation")

	var stat_signal := await _spawn_elevator()
	var restore_feedback := {"stats": 0, "rests": 0, "nights": 0}
	stat_signal._game_state.stat_changed.connect(
		func(_id: String, _stat: String, _value: float):
			restore_feedback["stats"] = int(restore_feedback["stats"]) + 1)
	stat_signal._game_state.rest_started.connect(
		func(_id: String): restore_feedback["rests"] = int(restore_feedback["rests"]) + 1)
	stat_signal._game_state.night_skipped.connect(
		func(_day: int): restore_feedback["nights"] = int(restore_feedback["nights"]) + 1)
	stat_signal.apply_save_snapshot(stat_capture)
	check(_all_atp(stat_signal, 7.0) \
			and not stat_signal._game_state.items.has(water_item_id) \
			and int(restore_feedback["stats"]) == 0 \
			and int(restore_feedback["rests"]) == 0 \
			and int(restore_feedback["nights"]) == 0 \
			and not stat_signal._drink_mesh.visible,
		"fresh ATP-signal restore neither repays nor re-emits and projects consumed water")
	var signal_authority: Dictionary = stat_signal._junction_rest_authority_state()
	_advance_across(stat_signal, float(signal_authority.get("dawn_deadline", -1.0)))
	check(str(stat_signal._current_step) == "dawn" and _all_atp(stat_signal, 7.0),
		"ATP-signal save resumes only its remaining presentation deadline")

	await _destroy_elevator(precommit)
	await _destroy_elevator(clock_signal)
	await _destroy_elevator(stat_signal)


func _verify_guard_retirement() -> void:
	var elevator := await _spawn_elevator()
	var before := _capture(elevator)
	elevator._retire_elevator_guards()
	check(not elevator._game_state.characters.has("eu1") \
			and not elevator._game_state.characters.has("eu2") \
			and not elevator._escort_1.visible and not elevator._escort_2.visible,
		"bridge retirement removes guard bodies from authority instead of only hiding them")
	var after := _capture(elevator)
	elevator.apply_save_snapshot(before)
	check(elevator._game_state.characters.has("eu1") \
			and elevator._game_state.characters.has("eu2") \
			and elevator._escort_1.visible and elevator._escort_2.visible,
		"same-presenter rollback before collapse restores roster and guard presenters together")
	elevator.apply_save_snapshot(after)
	check(not elevator._game_state.characters.has("eu1") \
			and not elevator._game_state.characters.has("eu2") \
			and not elevator._escort_1.visible and not elevator._escort_2.visible,
		"same-presenter forward restore retracts both hidden guard bodies again")
	var fresh := await _spawn_elevator()
	fresh.apply_save_snapshot(after)
	check(not fresh._game_state.characters.has("eu1") \
			and not fresh._game_state.characters.has("eu2") \
			and not fresh._escort_1.visible and not fresh._escort_2.visible,
		"fresh post-collapse load contains no invisible guard participants")
	await _destroy_elevator(fresh)
	await _destroy_elevator(elevator)


func _stage_ready_party(elevator: Node, atp: float) -> String:
	elevator._load_chunk("junction")
	elevator._retire_elevator_guards()
	var source_position: Vector3 = elevator._junction_anchor_position(
		"DrinkPickup", elevator.JUNCTION_SHELTER_CENTER)
	if not elevator._game_state.characters.has("endo"):
		elevator._endo.global_position = source_position
		elevator._register_gs_character("endo", elevator._endo, 2.5, {
			"hp": GameState.HP_MAX,
			"stamina": GameState.STAMINA_MAX,
			"atp": atp,
		})
		elevator._set_endo_presenter_present(true)
	var positions := {
		"aster": elevator.JUNCTION_SHELTER_CENTER + Vector3(-0.65, 0.0, -0.55),
		"peris": elevator.JUNCTION_SHELTER_CENTER + Vector3(0.65, 0.0, 0.55),
		"endo": elevator.JUNCTION_SHELTER_CENTER + Vector3(-0.65, 0.0, 0.55),
	}
	for character_id in elevator.JUNCTION_REST_PARTY:
		if elevator._game_state.is_downed(character_id):
			elevator._game_state.restore_character(character_id)
		elevator._game_state.command_stop(character_id)
		elevator._game_state.set_character_level(character_id, elevator.LEVEL_LOWER)
		elevator._game_state.snap_character_to(character_id, positions[character_id])
		elevator._game_state.set_stat(character_id, "hp", GameState.HP_MAX)
		elevator._game_state.set_stat(character_id, "stamina", GameState.STAMINA_MAX)
		elevator._game_state.set_stat(character_id, "atp", atp)
	var water_item_id := str(elevator._ensure_endo_drink_item())
	if water_item_id != "" and elevator._game_state.items.has(water_item_id) \
			and str((elevator._game_state.items[water_item_id] as Dictionary).get(
				"location", "")) == "ground":
		elevator._game_state.snap_character_to("endo", elevator._endo_drink_ground_position())
		elevator._game_state.pick_up_item("endo", water_item_id)
		elevator._game_state.snap_character_to("endo", positions["endo"])
	elevator._current_step = "endo_delivered"
	elevator._endo_delivery_dialogue_started = false
	elevator._sync_endo_drink_presenter()
	return water_item_id


func _spawn_elevator() -> Node:
	var elevator := ElevatorScene.instantiate()
	elevator.suppress_scene_change = true
	root.add_child(elevator)
	for _frame in range(8):
		await process_frame
	elevator.set_process(false)
	elevator.set_physics_process(false)
	elevator._scheduler.clear()
	elevator._scheduler.resume()
	elevator._ui_scheduler.clear()
	elevator._ui_scheduler.resume()
	if elevator._dialogue != null and elevator._dialogue.has_method("clear"):
		elevator._dialogue.clear()
	return elevator


func _static_guardrails() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/tutorial/elevator_sequence.gd")
	check("command_party_rest(JUNCTION_REST_PARTY)" in source \
			and "remove_item(water_item_id)" in source,
		"source guard: night uses canonical water consumption and one atomic party-rest command")
	check("_junction_roster_is_exact_party" in source \
			and "JUNCTION_SHELTER_HALF_SIZE" in source,
		"source guard: exact roster and authored shelter geometry gate the consequence")
	check("schedule_after(2.0, _start_night_watch" not in source \
			and "schedule_after(8.0, _start_dawn" not in source,
		"source guard: dialogue-relative anonymous timers no longer own night or dawn")
	check("_game_state.unregister_character(guard_id)" in source,
		"source guard: collapsed elevator guards cannot remain invisible GameState bodies")


func _capture(elevator: Node) -> Dictionary:
	return _json_round_trip(elevator.build_save_snapshot())


func _snapshot_all_atp(snapshot: Dictionary, expected: float) -> bool:
	var characters := (snapshot.get("game_state", {}) as Dictionary).get(
		"characters", {}) as Dictionary
	for character_id in ["aster", "peris", "endo"]:
		var stats := (characters.get(character_id, {}) as Dictionary).get(
			"stats", {}) as Dictionary
		if not is_equal_approx(float(stats.get("atp", -999.0)), expected):
			return false
	return true


func _snapshot_has_item(snapshot: Dictionary, item_id: String) -> bool:
	return ((snapshot.get("game_state", {}) as Dictionary).get(
		"items", {}) as Dictionary).has(item_id)


func _snapshot_item_held(snapshot: Dictionary, item_id: String, holder: String) -> bool:
	var items := (snapshot.get("game_state", {}) as Dictionary).get("items", {}) as Dictionary
	if not items.has(item_id):
		return false
	var item := items[item_id] as Dictionary
	return str(item.get("location", "")) == "hand" and str(item.get("holder", "")) == holder


func _snapshot_day(snapshot: Dictionary) -> int:
	var clock := (snapshot.get("game_state", {}) as Dictionary).get(
		"clock_state", {}) as Dictionary
	return int(clock.get("day", -1))


func _snapshot_time(snapshot: Dictionary) -> float:
	var clock := (snapshot.get("game_state", {}) as Dictionary).get(
		"clock_state", {}) as Dictionary
	return float(clock.get("time", -1.0))


func _snapshot_resting_count(snapshot: Dictionary) -> int:
	return ((snapshot.get("game_state", {}) as Dictionary).get(
		"resting", {}) as Dictionary).size()


func _all_atp(elevator: Node, expected: float) -> bool:
	for character_id in elevator.JUNCTION_REST_PARTY:
		if not is_equal_approx(elevator._game_state.get_stat(character_id, "atp"), expected):
			return false
	return true


func _all_atp_except_downed(elevator: Node, expected: float) -> bool:
	return is_equal_approx(elevator._game_state.get_stat("aster", "atp"), expected) \
		and is_equal_approx(elevator._game_state.get_stat("peris", "atp"), expected) \
		and is_equal_approx(elevator._game_state.get_stat("endo", "atp"), expected)


func _event_count(elevator: Node) -> int:
	return elevator._game_state.event_log.events.size() \
		if elevator._game_state.event_log != null else 0


func _event_kinds(elevator: Node, start_index: int) -> Array[StringName]:
	var result: Array[StringName] = []
	if elevator._game_state.event_log == null:
		return result
	for index in range(start_index, elevator._game_state.event_log.events.size()):
		result.append(StringName(str(
			(elevator._game_state.event_log.events[index] as Dictionary).get("kind", ""))))
	return result


func _advance_to_just_before(elevator: Node, deadline: float) -> void:
	var remaining := deadline - float(elevator._scheduler.get_current_tick())
	elevator._scheduler.advance_ticks(maxf(0.0, remaining - EPSILON))


func _advance_across(elevator: Node, deadline: float) -> void:
	_advance_to_just_before(elevator, deadline)
	elevator._scheduler.advance_ticks(EPSILON + 0.001)


func _destroy_elevator(elevator: Node) -> void:
	if elevator != null and is_instance_valid(elevator):
		if elevator.has_method("_teardown_sequence"):
			elevator._teardown_sequence()
		elevator.free()
	await process_frame


func _json_round_trip(value: Variant) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		push_error("  FAIL: %s" % label)
