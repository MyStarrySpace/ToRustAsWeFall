extends SceneTree

## Focused regression for Tag Day's portable escort and post-escort callbacks.
## Run:
##   ../Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_tag_day_escort_callback_authority.gd

const TagDayScene := preload("res://scenes/tutorial/tag_day.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_checkpoint_prelude()
	await _verify_escort_two_latch()
	await _verify_callback_deadlines()
	print("TAG DAY ESCORT/CALLBACK AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_checkpoint_prelude() -> void:
	var source: Node = await _spawn_sequence()
	if source == null:
		return
	var script_text := FileAccess.get_file_as_string(
		"res://scripts/tutorial/tag_day_sequence.gd")
	check("_scheduler.schedule_after(2.0, func()" not in script_text
			and "func(): _scheduler.schedule_after(1.5" not in script_text
			and "schedule_after(3.0, _start_naturalizers_grip" not in script_text,
		"checkpoint prelude has no anonymous or heap-only causal continuation")

	# The initial checkpoint pause is a real linear phase even though the opening ID line is
	# presentation. Loading it into a fresh sequence must retain its original absolute endpoint.
	var initial: Dictionary = source._portable_continuation.duplicate(true)
	check(str(source._current_step) == "arrive"
			and str(initial.get("kind", "")) == "method_delay"
			and str(initial.get("next_method", "")) == "_start_checkpoint_conversation",
		"checkpoint arrival publishes its named conversation hand-off")
	source.headless_advance(0.7, 0.05)
	var arrival_snapshot := _json_round_trip(source.build_save_snapshot())
	var arrival_deadline := float(
		(arrival_snapshot.get("portable_continuation", {}) as Dictionary).get("deadline", -1.0))
	var fresh_arrival: Node = await _spawn_sequence()
	if fresh_arrival != null:
		fresh_arrival.apply_save_snapshot(arrival_snapshot)
		var remaining := arrival_deadline - float(fresh_arrival._scheduler.get_current_tick())
		fresh_arrival.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
		check(str(fresh_arrival._portable_continuation.get("next_method", "")) \
				== "_start_checkpoint_conversation",
			"fresh arrival load cannot start the conversation one tick early")
		fresh_arrival.headless_advance(0.02, 0.01)
		check(str(fresh_arrival._portable_continuation.get("kind", "")) == "dialogue_chain"
				and str(fresh_arrival._portable_continuation.get("next_method", "")) \
				== "_finish_checkpoint_conversation",
			"saved arrival endpoint reconstructs the named checkpoint conversation")
		await _discard(fresh_arrival)

	# The failed scan's three-second reaction window used to exist only as a scheduler Callable.
	# Prove that both its exact deadline and its physical Naturalizer approach survive a fresh load.
	source._scheduler.clear()
	source._dialogue.clear()
	source._start_citizen_scan()
	source.headless_advance(1.0, 0.05)
	var scan_snapshot := _json_round_trip(source.build_save_snapshot())
	var scan_record := scan_snapshot.get("portable_continuation", {}) as Dictionary
	check(str(scan_record.get("kind", "")) == "method_delay"
			and str(scan_record.get("next_method", "")) == "_start_naturalizers_grip",
		"failed scan publishes its named physical-reaction hand-off")
	var fresh_scan: Node = await _spawn_sequence()
	if fresh_scan != null:
		fresh_scan.apply_save_snapshot(scan_snapshot)
		var remaining := float(scan_record.get("deadline", -1.0)) \
			- float(fresh_scan._scheduler.get_current_tick())
		fresh_scan.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
		check(str(fresh_scan._current_step) == "citizen_scan"
				and not fresh_scan._game_state.is_moving("nk1")
				and not fresh_scan._game_state.is_moving("nk2"),
			"fresh scan load cannot move either Naturalizer before the saved endpoint")
		fresh_scan.headless_advance(0.02, 0.01)
		check(str(fresh_scan._current_step) == "naturalizers_grip"
				and fresh_scan._game_state.is_moving("nk1")
				and fresh_scan._game_state.is_moving("nk2"),
			"saved scan endpoint commits both real Naturalizer approaches")
		await _discard(fresh_scan)

	await _discard(source)


func _verify_escort_two_latch() -> void:
	var source: Node = await _spawn_sequence()
	if source == null:
		return
	_prepare_for_grip(source)
	_start_corridor(source)
	var committed: Dictionary = source._escort_authority_state()
	check(str(committed.get("phase", "")) == source.ESCORT_PHASE_CORRIDOR,
		"corridor begins as an explicit saved escort phase")
	check(_same_members(committed.get("actors", []), ["citizen", "nk1", "nk2"]),
		"escort authority names the three gameplay actors")
	var operations := committed.get("accepted_movement_ops", {}) as Dictionary
	var endpoints := committed.get("endpoints", {}) as Dictionary
	var contracts_complete := true
	for actor_id in ["citizen", "nk1", "nk2"]:
		var operation := operations.get(actor_id, {}) as Dictionary
		contracts_complete = contracts_complete \
			and bool(operation.get("accepted", false)) \
			and str(operation.get("actor_id", "")) == actor_id \
			and str(operation.get("kind", "")) == "walk_path" \
			and operation.get("endpoint", []) == endpoints.get(actor_id, null)
	check(contracts_complete,
		"each accepted GameState path has a durable actor receipt and endpoint")

	# Presentation-first: finishing the poem is only one latch. The three still-moving
	# bodies must remain in the corridor, including after a fresh-presenter load.
	source._on_poem_finished()
	var presentation_first: Dictionary = source._escort_authority_state()
	check(bool(presentation_first.get("presentation_complete", false))
			and str(source._current_step) == "corridor_walk",
		"presentation completion alone cannot advance the escort")
	source.headless_advance(7.0, 0.05)
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var midpoint_tick := float(source._scheduler.get_current_tick())
	var midpoint_positions := {}
	for actor_id in ["citizen", "nk1", "nk2"]:
		midpoint_positions[actor_id] = source._game_state.get_position(actor_id)

	var fresh: Node = await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		var restored: Dictionary = fresh._escort_authority_state()
		var positions_match := true
		for actor_id in ["citizen", "nk1", "nk2"]:
			positions_match = positions_match and fresh._game_state.get_position(actor_id) \
				.distance_to(midpoint_positions[actor_id]) < 0.01
		check(str(restored.get("phase", "")) == fresh.ESCORT_PHASE_CORRIDOR \
				and bool(restored.get("presentation_complete", false)) \
				and is_equal_approx(float(fresh._scheduler.get_current_tick()), midpoint_tick) \
				and positions_match,
			"fresh load restores the presentation latch and all three path midpoints")
		var final_tick := _latest_plan_end(fresh)
		var remaining := final_tick - float(fresh._scheduler.get_current_tick())
		fresh.headless_advance(maxf(0.0, remaining - 0.02), 0.02)
		check(str(fresh._current_step) == "corridor_walk",
			"saved physical arrivals cannot cash out one tick early")
		fresh.headless_advance(0.05, 0.01)
		var joined: Dictionary = fresh._escort_authority_state()
		check(str(joined.get("phase", "")) == fresh.ESCORT_PHASE_JOINED \
				and str(fresh._current_step) == "fragments",
			"the final required physical arrival joins the completed presentation")

		# Same-presenter rewind must retract the joined future without reissuing paths.
		fresh.apply_save_snapshot(midpoint_snapshot)
		var projection: Dictionary = fresh._game_state.serialize()
		fresh.on_game_state_snapshot_restored()
		check(str(fresh._current_step) == "corridor_walk"
				and fresh._game_state.serialize() == projection,
			"same-presenter rollback is idempotent and does not synthesize movement")
		await _discard(fresh)

	# Physical-first: hold the presentation deadline beyond all three endpoints.
	var physical_first: Node = await _spawn_sequence()
	if physical_first != null:
		_prepare_for_grip(physical_first)
		_start_corridor(physical_first)
		var held: Dictionary = physical_first._escort_authority_state()
		var path_end := _latest_plan_end(physical_first)
		held["presentation_deadline"] = path_end + 2.0
		held["presentation_complete"] = false
		held["presentation_completed_at"] = -1.0
		physical_first._publish_escort_authority(held)
		physical_first._clear_dialogue_presenter()
		physical_first._arm_corridor_presentation_from_authority(false)
		physical_first.headless_advance(
			path_end - float(physical_first._scheduler.get_current_tick()) + 0.02, 0.02)
		var waiting: Dictionary = physical_first._escort_authority_state()
		check(str(waiting.get("phase", "")) == physical_first.ESCORT_PHASE_CORRIDOR \
				and float(waiting.get("physical_completed_at", -1.0)) >= 0.0 \
				and not bool(waiting.get("presentation_complete", false)),
			"all three physical arrivals alone cannot skip the presentation latch")
		physical_first.headless_advance(1.9, 0.05)
		check(str(physical_first._current_step) == "corridor_walk",
			"presentation deadline retains its exact remaining window")
		physical_first.headless_advance(0.2, 0.02)
		check(str(physical_first._current_step) == "fragments",
			"saved presentation endpoint joins already-complete physical arrivals")
		await _discard(physical_first)

	await _discard(source)


func _verify_callback_deadlines() -> void:
	var source: Node = await _spawn_sequence()
	if source == null:
		return
	_prepare_for_grip(source)
	_start_corridor(source)
	source._on_poem_finished()
	var plan_end := _latest_plan_end(source)
	source.headless_advance(
		plan_end - float(source._scheduler.get_current_tick()) + 0.05, 0.02)
	check(str(source._current_step) == "fragments",
		"callback verification begins from the completed two-latch escort")

	# Neutralization's fade/whimper boundary is scheduler-authoritative.
	source._on_bang()
	var neutralization: Dictionary = source._callback_authority_state()
	var neutralization_deadline := float(neutralization.get("deadline", -1.0))
	source.headless_advance(0.9, 0.05)
	var neutralization_snapshot := _json_round_trip(source.build_save_snapshot())
	var fresh: Node = await _spawn_sequence()
	if fresh == null:
		await _discard(source)
		return
	fresh.apply_save_snapshot(neutralization_snapshot)
	var restored_neutralization: Dictionary = fresh._callback_authority_state()
	check(str(restored_neutralization.get("phase", "")) \
			== fresh.CALLBACK_PHASE_NEUTRALIZATION \
			and is_equal_approx(float(restored_neutralization.get("deadline", -1.0)),
				neutralization_deadline),
		"fresh load preserves the neutralization-to-whimper absolute deadline")
	var neutralization_remaining := neutralization_deadline \
		- float(fresh._scheduler.get_current_tick())
	fresh.headless_advance(maxf(0.0, neutralization_remaining - 0.02), 0.01)
	check(str(fresh._callback_authority_state().get("phase", "")) \
		== fresh.CALLBACK_PHASE_NEUTRALIZATION,
		"neutralization cannot enter whimper before its saved endpoint")
	fresh.headless_advance(0.04, 0.01)
	check(str(fresh._callback_authority_state().get("phase", "")) \
		== fresh.CALLBACK_PHASE_WHIMPER,
		"saved neutralization endpoint reconstructs the whimper phase")

	# Resolve each dialogue presentation, save its explicit post-presentation hold,
	# and prove the next phase waits for that exact saved deadline.
	fresh._on_whimper_presentation_finished()
	await _verify_phase_boundary(
		fresh, fresh.CALLBACK_PHASE_WHIMPER, fresh.CALLBACK_PHASE_LOCKDOWN,
		fresh.WHIMPER_POST_SECONDS, "whimper")
	fresh._on_lockdown_presentation_finished()
	await _verify_phase_boundary(
		fresh, fresh.CALLBACK_PHASE_LOCKDOWN, fresh.CALLBACK_PHASE_RETURN_FOCUS,
		fresh.LOCKDOWN_POST_SECONDS, "lockdown")
	await _verify_phase_boundary(
		fresh, fresh.CALLBACK_PHASE_RETURN_FOCUS, fresh.CALLBACK_PHASE_ASTER_SCAN,
		fresh.RETURN_FOCUS_SECONDS, "return focus")
	fresh._on_aster_scan_presentation_finished()
	await _verify_phase_boundary(
		fresh, fresh.CALLBACK_PHASE_ASTER_SCAN, fresh.CALLBACK_PHASE_CLEARANCE,
		fresh.ASTER_SCAN_POST_SECONDS, "Aster scan")
	await _verify_phase_boundary(
		fresh, fresh.CALLBACK_PHASE_CLEARANCE, fresh.CALLBACK_PHASE_COMPLETE,
		fresh.CLEARANCE_SECONDS, "clearance")
	check(str(fresh.requested_scene_change) == "res://scenes/tutorial/elevator.tscn",
		"clearance completion requests the authored elevator transition exactly once")

	await _discard(fresh)
	await _discard(source)


func _verify_phase_boundary(
	sequence: Node,
	phase: String,
	next_phase: String,
	expected_duration: float,
	label: String
) -> void:
	var authority: Dictionary = sequence._callback_authority_state()
	var deadline := float(authority.get("deadline", -1.0))
	var started_at := float(authority.get("started_at", -1.0))
	var presentation_completed_at := float(authority.get(
		"presentation_completed_at", started_at))
	var deadline_anchor := presentation_completed_at \
		if presentation_completed_at >= 0.0 else started_at
	var remaining := deadline - float(sequence._scheduler.get_current_tick())
	check(str(authority.get("phase", "")) == phase \
			and is_equal_approx(deadline - deadline_anchor, expected_duration) \
			and remaining > 0.0 \
			and remaining <= expected_duration + 0.000001,
		"%s publishes its exact saved phase deadline" % label)
	var snapshot := _json_round_trip(sequence.build_save_snapshot())
	sequence.apply_save_snapshot(snapshot)
	sequence.headless_advance(maxf(0.0, remaining - 0.02), 0.01)
	check(str(sequence._callback_authority_state().get("phase", "")) == phase,
		"%s cannot advance one tick before its saved deadline" % label)
	sequence.headless_advance(0.04, 0.01)
	check(str(sequence._callback_authority_state().get("phase", "")) == next_phase,
		"%s advances once at its saved deadline" % label)


func _prepare_for_grip(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._current_step = "citizen_scan"


func _start_corridor(sequence: Node) -> void:
	sequence._start_naturalizers_grip()
	var elapsed := 0.0
	while str(sequence._current_step) != "corridor_walk" and elapsed < 12.0:
		sequence.headless_advance(0.05, 0.05)
		elapsed += 0.05
	check(str(sequence._current_step) == "corridor_walk",
		"physical formation reaches the corridor authority phase")


func _latest_plan_end(sequence: Node) -> float:
	var result := float(sequence._scheduler.get_current_tick())
	for actor_id in ["citizen", "nk1", "nk2"]:
		result = maxf(result, float(sequence._game_state.get_plan_end_tick(actor_id)))
	return result


func _same_members(raw: Variant, expected: Array) -> bool:
	if not (raw is Array) or (raw as Array).size() != expected.size():
		return false
	for member_v in expected:
		if not (raw as Array).has(member_v):
			return false
	return true


func _spawn_sequence() -> Node:
	var sequence: Node = TagDayScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	if sequence._game_state == null:
		check(false, "Tag Day sequence instantiates")
		await _discard(sequence)
		return null
	sequence.set_process(false)
	return sequence


func _json_round_trip(snapshot: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.has_method("_teardown_sequence"):
			node._teardown_sequence()
		node.queue_free()
		await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
