extends SceneTree

## Mid-dialogue and mid-delay regression for Act 1's linear campaign hand-offs. The gameplay
## scheduler deliberately does not serialize Callables, so these edges must remain named portable
## continuations owned by TutorialSequence.

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const LEAVING_FACILITY_PATH := "res://scenes/tutorial/leaving_facility.tscn"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_verify_source_contract()
	await _verify_optional_one_shot_presenter_restore()
	await _verify_lockout_dialogue_midpoint()
	await _verify_final_handoff_midpoint()
	print("ACT1 LINEAR CONTINUATIONS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_contract() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/tutorial/act1_sequence.gd")
	var anonymous_callbacks := 0
	var relative_callbacks := 0
	for raw_line in source.split("\n"):
		var code := _strip_comment_and_strings(str(raw_line))
		anonymous_callbacks += code.count("func(")
		relative_callbacks += code.count("schedule_after(")
	check(anonymous_callbacks == 0,
		"Act 1 has no anonymous dialogue-to-gameplay or scene-handoff callback")
	check(relative_callbacks == 1
			and "func _arm_channels_formation_poll" in source,
		"the only relative callback left is the saved Channels formation poll")
	check("_schedule_portable_method(0.2, _start_lockout_chase" in source
			and "_schedule_portable_method(1.0, _start_stacks_enter" in source
			and "_schedule_portable_method(2.0, _handoff_to_leaving_facility" in source,
		"campaign chase, level handoff, and scene handoff publish named deadlines")
	check("_start_channels_window_one_intro" in source
			and "_start_channels_window_two_intro" in source
			and "_begin_channels_window_one" in source
			and "_begin_channels_window_two" in source,
		"parameterized Channels windows use stable no-argument continuation endpoints")
	check("ACT1_SNAPSHOT_CHUNKS" in source
			and "_prepare_act1_chunks_for_snapshot(data)" in source
			and "ACT1_CAMPAIGN_AUTHORITY_KEY" in source,
		"fresh loads reconstruct their level presenter before campaign authority attaches")
	check("func _restore_stacks_optional_interactables" in source
			and "func _restore_rings_trace_interactables" in source
			and "func _restore_sequence_one_shot_presenter" in source,
		"optional one-shot observations derive their used/available presenter from saved truth")
	check("set_pre_trigger_validator(" in source
			and "_validate_act1_stacks_shelter_trigger" in source,
		"Act 1 Stacks validates exact party-rest truth before consuming its one-shot")


func _verify_optional_one_shot_presenter_restore() -> void:
	var stacks := await _spawn_sequence()
	stacks.prepare_stacks_fragment("bank")
	var terminal = stacks._stacks_terminal_interactable
	check(is_instance_valid(terminal) and terminal.is_interaction_enabled(),
		"Stacks exposes its unread terminal observation")
	var stacks_before := _json_round_trip(stacks.build_save_snapshot())
	stacks._game_state.command_stop("aster")
	stacks.headless_set_character_position("aster", terminal.global_position)
	stacks._select_character("aster")
	terminal.active_character = "aster"
	check(terminal._trigger(false) and stacks._stacks_terminal_interacted,
		"physical terminal interaction commits the saved observation")
	var stacks_after := _json_round_trip(stacks.build_save_snapshot())
	stacks.apply_save_snapshot(stacks_before)
	check(not stacks._stacks_terminal_interacted
			and terminal.is_interaction_enabled()
			and not terminal._used,
		"same-presenter rollback retracts a discarded optional one-shot use")

	var stacks_fresh := await _spawn_sequence()
	stacks_fresh.apply_save_snapshot(stacks_after)
	var fresh_terminal = stacks_fresh._stacks_terminal_interactable
	check(stacks_fresh._stacks_terminal_interacted
			and is_instance_valid(fresh_terminal)
			and not fresh_terminal.is_interaction_enabled()
			and fresh_terminal.get_action_verb() == "",
		"fresh Stacks load cannot advertise an already-read dead interaction")
	await _dispose(stacks)
	await _dispose(stacks_fresh)

	var shelter := await _spawn_sequence()
	shelter.prepare_stacks_fragment("shelter")
	var rest = shelter._stacks_shelter_interactable
	check(is_instance_valid(rest) and rest.is_interaction_enabled(),
		"resolved Stacks exposes the authored shelter action")
	for character_id in shelter.CHANNELS_PARTY_IDS:
		shelter._game_state.command_stop(character_id)
		shelter._game_state.set_stat(character_id, "hp", 50.0)
		shelter._game_state.set_stat(character_id, "atp", 4.0)
	shelter.headless_set_character_position(
		"peris", shelter.STACKS_SHELTER_POS + Vector3(0.4, 0.0, 0.0))
	shelter.headless_set_character_position(
		"endo", shelter.STACKS_SHELTER_POS + Vector3(-0.4, 0.0, 0.0))
	shelter.headless_set_character_position(
		"aster", shelter.STACKS_SHELTER_POS + Vector3(10.0, 0.0, 0.0))
	rest.active_character = "peris"
	var rest_signals := {"value": 0}
	rest.interacted.connect(func() -> void:
		rest_signals.value = int(rest_signals.value) + 1)
	check(not rest._trigger(false)
			and not rest._used
			and rest.is_interaction_enabled()
			and int(rest_signals.value) == 0
			and shelter._stacks_rest_phase == "ready",
		"a remote Aster is rejected before Stacks consumes or signals its shelter one-shot")
	shelter.headless_set_character_position(
		"aster", shelter.STACKS_SHELTER_POS + Vector3(0.0, 0.0, 0.5))
	check(rest._trigger(false)
			and rest._used
			and int(rest_signals.value) == 1
			and shelter._stacks_rest_phase == "rested",
		"the exact conscious trio commits the canonical Stacks rest exactly once")
	await _dispose(shelter)

	var rings := await _spawn_sequence()
	rings.prepare_rings_fragment("client")
	var trace = rings._rings_trace_interactables.get("client_bloom")
	check(is_instance_valid(trace) and trace.is_interaction_enabled(),
		"Rings exposes its unread physical trace")
	var rings_before := _json_round_trip(rings.build_save_snapshot())
	rings._game_state.command_stop("peris")
	rings.headless_set_character_position("peris", trace.global_position)
	rings._select_character("peris")
	trace.active_character = "peris"
	check(trace._trigger(false)
			and bool(rings._rings_trace_seen.get("client_bloom", false)),
		"physical Rings trace interaction commits its saved observation")
	var rings_after := _json_round_trip(rings.build_save_snapshot())
	rings.apply_save_snapshot(rings_before)
	check(not bool(rings._rings_trace_seen.get("client_bloom", false))
			and trace.is_interaction_enabled()
			and not trace._used,
		"same-presenter Rings rollback re-arms the physically unread trace")

	var rings_fresh := await _spawn_sequence()
	rings_fresh.apply_save_snapshot(rings_after)
	var fresh_trace = rings_fresh._rings_trace_interactables.get("client_bloom")
	check(bool(rings_fresh._rings_trace_seen.get("client_bloom", false))
			and is_instance_valid(fresh_trace)
			and not fresh_trace.is_interaction_enabled()
			and fresh_trace.get_action_verb() == "",
		"fresh Rings load presents a read trace as spent instead of as a no-op")
	await _dispose(rings)
	await _dispose(rings_fresh)


func _verify_lockout_dialogue_midpoint() -> void:
	var source := await _spawn_sequence()
	source._start_lockout_approach()
	source._cancel_portable_continuation()
	source._restore_dialogue_presenter_from_snapshot({})
	source._start_lockout_rejected()
	source._dialogue.advance_ui_time(0.06)
	var snapshot := _json_round_trip(source.build_save_snapshot())
	var saved_continuation: Dictionary = snapshot.get("portable_continuation", {})
	var saved_dialogue: Dictionary = snapshot.get("dialogue", {})
	var campaign: Dictionary = source._game_state.get_world_state(
		source.ACT1_CAMPAIGN_AUTHORITY_KEY, {})
	check(str(saved_continuation.get("kind", "")) == "dialogue_chain"
			and str(saved_continuation.get("owner_step", "")) == "lockout_rejected"
			and str(saved_continuation.get("next_method", "")) == "_queue_lockout_chase",
		"the rejection dialogue saves its exact named chase successor")
	check(bool(campaign.get("lockout_chase_active", false))
			and bool(campaign.get("lockout_rejection_presented", false))
			and not bool(campaign.get("lockout_dispatch_presented", true)),
		"GameState owns the exact campaign phase while rejection dialogue is active")
	var active_chunks: Array = (snapshot.get("act1_presenters", {}) as Dictionary).get(
		"active_chunks", [])
	check(active_chunks.has("lockout_chase_campaign") and not active_chunks.has("channels"),
		"the save names the physical chase presenter instead of the discarded prior level")

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	source.apply_save_snapshot(snapshot)
	for pair in [["same", source], ["fresh", fresh]]:
		var label := str(pair[0])
		var sequence: Node = pair[1]
		var restored: Dictionary = sequence._portable_continuation
		var restored_dialogue: Dictionary = sequence._dialogue.snapshot_state()
		check(str(restored.get("next_method", "")) == "_queue_lockout_chase"
				and str(restored.get("owner_step", "")) == "lockout_rejected"
				and sequence._lockout_chase_active
				and is_instance_valid(sequence._lockout_chase_chunk)
				and sequence._chunks.has("lockout_chase_campaign")
				and not sequence._chunks.has("channels"),
			"%s presenter restores one rejection-to-chase continuation" % label)
		check(sequence._channels_window_lanes.is_empty()
				and sequence._channels_channel_entries.is_empty()
				and not sequence._channels_kit_active,
			"%s presenter retracts every discarded Channels runtime presenter" % label)
		check(str(restored_dialogue.get("current_text", ""))
				== str(saved_dialogue.get("current_text", ""))
				and is_equal_approx(
					float(restored_dialogue.get("displayed_chars", -1.0)),
					float(saved_dialogue.get("displayed_chars", -2.0))),
			"%s presenter restores the exact active dialogue position" % label)
		_finish_dialogue(sequence)
		sequence._scheduler.advance_ticks(sequence.PORTABLE_CONTINUATION_EPSILON * 1.25)
		var queued: Dictionary = sequence._portable_continuation
		check(str(sequence._current_step) == "lockout_rejected"
				and str(queued.get("kind", "")) == "method_delay"
				and str(queued.get("next_method", "")) == "_start_lockout_chase",
			"%s presenter converts the completed dialogue into one portable chase delay" % label)
		var deadline := float(queued.get("deadline", -1.0))
		sequence._scheduler.advance_ticks(
			maxf(0.0, deadline - float(sequence._scheduler.get_current_tick()) - 0.0005))
		check(str(sequence._current_step) == "lockout_rejected",
			"%s presenter cannot begin the chase before its saved deadline" % label)
		sequence._scheduler.advance_ticks(0.001)
		check(str(sequence._current_step) == "lockout_chase"
				and sequence._lockout_chase_active
				and sequence._naturalizers.is_empty(),
			"%s presenter begins the physical hosted chase once at its deadline" % label)
		var chased: Dictionary = sequence._game_state.get_world_state(
			sequence.ACT1_CAMPAIGN_AUTHORITY_KEY, {})
		check(bool(chased.get("lockout_dispatch_presented", false)),
			"%s presenter commits the one-shot dispatch before pursuit signals" % label)

	await _dispose(source)
	await _dispose(fresh)


func _verify_final_handoff_midpoint() -> void:
	var source := await _spawn_sequence()
	source._complete()
	var started: Dictionary = source._portable_continuation
	check(str(started.get("kind", "")) == "method_delay"
			and str(started.get("owner_step", "")) == "complete"
			and str(started.get("next_method", "")) == "_handoff_to_leaving_facility",
		"Act 1 completion publishes the scene handoff instead of an opaque callback")
	source.headless_advance(0.8, 0.1)
	var snapshot := _json_round_trip(source.build_save_snapshot())
	var deadline := float((snapshot.get("portable_continuation", {}) as Dictionary).get(
		"deadline", -1.0))
	source.headless_advance(1.3, 0.1)
	check(str(source.requested_scene_change) == LEAVING_FACILITY_PATH,
		"the discarded future reaches Leaving Facility")

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	source.apply_save_snapshot(snapshot)
	for pair in [["same", source], ["fresh", fresh]]:
		var label := str(pair[0])
		var sequence: Node = pair[1]
		check(str(sequence.requested_scene_change) == ""
				and str(sequence._portable_continuation.get("next_method", ""))
					== "_handoff_to_leaving_facility",
			"%s presenter retracts the discarded handoff and restores its named future" % label)
		var remaining := deadline - float(sequence._scheduler.get_current_tick())
		sequence._scheduler.advance_ticks(maxf(0.0, remaining - 0.0005))
		check(str(sequence.requested_scene_change) == "",
			"%s presenter cannot change scene before the original deadline" % label)
		sequence._scheduler.advance_ticks(0.001)
		check(str(sequence.requested_scene_change) == LEAVING_FACILITY_PATH,
			"%s presenter performs the scene handoff once at the saved deadline" % label)

	await _dispose(source)
	await _dispose(fresh)


func _finish_dialogue(sequence: Node) -> void:
	var safety := 0
	while sequence._dialogue.is_active() and safety < 128:
		sequence._dialogue.request_advance()
		safety += 1
	check(safety < 128 and not sequence._dialogue.is_active(),
		"the restored dialogue reaches its portable completion seam")


func _spawn_sequence() -> Node:
	var sequence := ACT1_SCENE.instantiate()
	sequence.start_chunk = "channels"
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._ui_scheduler.clear()
	sequence._ui_scheduler.resume()
	sequence._cancel_portable_continuation()
	sequence._restore_dialogue_presenter_from_snapshot({})
	sequence.requested_scene_change = ""
	return sequence


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.free()
	await process_frame


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _strip_comment_and_strings(line: String) -> String:
	var out := ""
	var in_string := false
	var escaped := false
	for i in range(line.length()):
		var ch := line[i]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue
		if ch == "\"":
			in_string = true
		elif ch == "#":
			break
		else:
			out += ch
	return out


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
