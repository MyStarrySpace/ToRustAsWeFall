extends SceneTree

## Naturalizer's hesitation scan is a gameplay clock layered over Enemy's FSM. EventScheduler save
## data contains only the clock, so these checks prove that both its context and one recurring
## callback are reconstructed from stable GameState authority after same-node and fresh-scene loads.

const NAT_ID := "authority_naturalizer"
const BASE_SPEED := 4.0
const ZONE_POS := Vector3.ZERO
const ZONE_RADIUS := 2.0

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_absence_retracts_future_hesitation()
	var fixture := await _build_mid_hesitation_snapshot()
	await _verify_same_node_midpoint_rollback(fixture)
	await _verify_fresh_presenter_midpoint_restore(fixture)
	await _discard_context(fixture)
	print("NATURALIZER SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_absence_retracts_future_hesitation() -> void:
	var context := await _make_context("future_naturalizer", false)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var naturalizer: Naturalizer = context.naturalizer
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	check(not state.world_state.has(naturalizer._naturalizer_authority_key()),
		"pre-activation snapshot contains no invented Naturalizer phase")

	naturalizer.activate()
	naturalizer.add_hesitation_zone(ZONE_POS, ZONE_RADIUS)
	scheduler.advance_ticks(Naturalizer.HESITATION_POLL)
	check(naturalizer.is_hesitating(), "future hesitation can engage before rollback")

	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	naturalizer.on_game_state_snapshot_restored()
	check(not naturalizer.is_hesitating() and naturalizer._hesitation_zones.is_empty()
			and naturalizer._hesitation_poll_deadline < 0.0,
		"authority absence retracts future zones, phase, and deadline")
	check(scheduler.pending_count() == 0,
		"authority absence leaves no orphan recurring poll")
	check(is_equal_approx(float(state.characters["future_naturalizer"].move_speed), BASE_SPEED),
		"rollback retains the snapshot's movement speed without a synthetic correction")
	await _discard_context(context)


func _build_mid_hesitation_snapshot() -> Dictionary:
	var context := await _make_context(NAT_ID, true)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var naturalizer: Naturalizer = context.naturalizer
	naturalizer.add_hesitation_zone(ZONE_POS, ZONE_RADIUS)
	scheduler.advance_ticks(Naturalizer.HESITATION_POLL)
	scheduler.advance_ticks(0.05)
	check(naturalizer.is_hesitating()
			and is_equal_approx(float(state.characters[NAT_ID].move_speed),
				BASE_SPEED * Naturalizer.HESITATION_FACTOR),
		"fixture reaches the live hesitation phase before saving")
	var authority: Dictionary = state.get_world_state(
		naturalizer._naturalizer_authority_key(), {})
	check(bool(authority.get("hesitating", false))
			and (authority.get("hesitation_zones", []) as Array).size() == 1,
		"stable authority records hesitation and its causal zone")
	check(is_equal_approx(float(authority.get("next_poll_tick", -1.0)), 0.8),
		"recurring scan commits its absolute next poll tick")
	context["saved_scheduler"] = _json_round_trip(scheduler.serialize())
	context["saved_state"] = _json_round_trip(state.serialize())
	return context


func _verify_same_node_midpoint_rollback(context: Dictionary) -> void:
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var naturalizer: Naturalizer = context.naturalizer
	var log: EventLog = context.log
	# Let the future leave the zone and clear hesitation, then replace it with the earlier snapshot.
	state.snap_character_to(NAT_ID, Vector3(10.0, 0.0, 0.0))
	scheduler.advance_ticks(0.35)
	check(not naturalizer.is_hesitating(),
		"future poll clears hesitation before same-node rollback")

	scheduler.clear()
	scheduler.deserialize(context.saved_scheduler)
	state.deserialize(context.saved_state)
	# This focused harness restores the state snapshot without replacing the production replay log.
	# Drop future branch events so new post-load commands remain monotonic from the restored clock.
	log.clear()
	var events_before_restore := log.size()
	naturalizer.on_game_state_snapshot_restored()
	naturalizer.on_game_state_snapshot_restored()
	check(naturalizer.is_hesitating() and naturalizer._hesitation_zones.size() == 1,
		"same-node rollback restores the midpoint phase and zone")
	check(is_equal_approx(naturalizer._hesitation_poll_deadline, 0.8),
		"same-node rollback restores the original absolute cadence")
	check(scheduler.pending_count() == 1,
		"idempotent same-node restore arms exactly one recurring callback")
	check(log.size() == events_before_restore,
		"same-node restoration emits no synthetic gameplay commands")

	state.snap_character_to(NAT_ID, Vector3(10.0, 0.0, 0.0))
	var events_before_poll := log.size()
	var remaining := naturalizer._hesitation_poll_deadline \
		- float(scheduler.get_current_tick())
	scheduler.advance_ticks(remaining - 0.001)
	check(naturalizer.is_hesitating(),
		"same-node hesitation cannot clear before the saved poll tick")
	scheduler.advance_ticks(0.001)
	check(not naturalizer.is_hesitating()
			and is_equal_approx(float(state.characters[NAT_ID].move_speed), BASE_SPEED),
		"same-node scan evaluates once at the exact saved tick")
	check(_count_new_events(log, events_before_poll, GameEvent.KIND_CHANGE_SPEED) == 1
			and _count_new_events(log, events_before_poll, GameEvent.KIND_SET_WORLD_STATE) == 1
			and scheduler.pending_count() == 1,
		"same-node cadence emits one speed change, one authority update, and one next poll")
	var authority: Dictionary = state.get_world_state(
		naturalizer._naturalizer_authority_key(), {})
	check(is_equal_approx(float(authority.get("next_poll_tick", -1.0)), 1.2),
		"same-node recurrence advances from the restored deadline")


func _verify_fresh_presenter_midpoint_restore(fixture: Dictionary) -> void:
	var scheduler := EventScheduler.new()
	scheduler.deserialize(fixture.saved_scheduler)
	var state := GameState.new()
	state.scheduler = scheduler
	state.deserialize(fixture.saved_state)
	var log := EventLog.new()
	state.event_log = log
	var host := Node3D.new()
	host.name = "FreshNaturalizerHost"
	root.add_child(host)
	var naturalizer := Naturalizer.new()
	naturalizer.name = NAT_ID
	naturalizer.char_id = NAT_ID
	naturalizer.game_state = state
	naturalizer.move_speed = BASE_SPEED
	naturalizer.detection_range = 0.0
	naturalizer.set_detection_targets([])
	host.add_child(naturalizer)
	await process_frame
	naturalizer.activate()
	naturalizer.on_game_state_snapshot_restored()
	# The actual lockout scene wires its authored zone after activation. On load this is a duplicate of
	# saved authority and must not restart the 0.8-second deadline from the current 0.45-second tick.
	naturalizer.add_hesitation_zone(ZONE_POS, ZONE_RADIUS)
	check(naturalizer.is_hesitating() and naturalizer._hesitation_zones.size() == 1,
		"fresh presenter restores hesitation and de-duplicates authored zone wiring")
	check(is_equal_approx(naturalizer._hesitation_poll_deadline, 0.8),
		"fresh presenter preserves the original absolute poll deadline")
	check(scheduler.pending_count() == 1,
		"fresh activation plus attachment pass arms exactly one callback")
	check(log.is_empty(), "fresh restoration emits no synthetic gameplay command")

	state.snap_character_to(NAT_ID, Vector3(10.0, 0.0, 0.0))
	var events_before_poll := log.size()
	var remaining := naturalizer._hesitation_poll_deadline \
		- float(scheduler.get_current_tick())
	scheduler.advance_ticks(remaining - 0.001)
	check(naturalizer.is_hesitating(),
		"fresh hesitation remains active until the saved deadline")
	scheduler.advance_ticks(0.001)
	check(not naturalizer.is_hesitating()
			and is_equal_approx(float(state.characters[NAT_ID].move_speed), BASE_SPEED),
		"fresh presenter evaluates at the same exact cadence")
	check(_count_new_events(log, events_before_poll, GameEvent.KIND_CHANGE_SPEED) == 1
			and _count_new_events(log, events_before_poll, GameEvent.KIND_SET_WORLD_STATE) == 1
			and scheduler.pending_count() == 1,
		"fresh cadence produces one consequence, one authority update, and one successor")
	host.queue_free()
	await process_frame


func _make_context(naturalizer_id: String, activate_now: bool) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	var log := EventLog.new()
	state.event_log = log
	state.register_character(naturalizer_id, Vector3.ZERO, BASE_SPEED,
		{"detection_range": 0.0})
	var host := Node3D.new()
	host.name = "NaturalizerHost_%s" % naturalizer_id
	root.add_child(host)
	var naturalizer := Naturalizer.new()
	naturalizer.name = naturalizer_id
	naturalizer.char_id = naturalizer_id
	naturalizer.game_state = state
	naturalizer.move_speed = BASE_SPEED
	naturalizer.detection_range = 0.0
	naturalizer.set_detection_targets([])
	host.add_child(naturalizer)
	await process_frame
	if activate_now:
		naturalizer.activate()
	return {
		"scheduler": scheduler,
		"state": state,
		"naturalizer": naturalizer,
		"host": host,
		"log": log,
	}


func _discard_context(context: Dictionary) -> void:
	var host: Node = context.get("host")
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _count_new_events(log: EventLog, from_index: int, kind: StringName) -> int:
	var count := 0
	for index in range(from_index, log.events.size()):
		if StringName(log.events[index].get("kind", &"")) == kind:
			count += 1
	return count


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
