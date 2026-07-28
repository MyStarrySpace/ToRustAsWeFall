extends SceneTree

## Focused regression for Aster Sim's linear story hand-offs. EventScheduler intentionally drops
## opaque Callables from saves, so every causal delay/dialogue edge must be a named portable
## continuation while the eight-second drink reminder remains presentation-only.
##
## Run:
##   ..\Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_aster_linear_continuations.gd

const AsterSimScene := preload("res://scenes/tutorial/aster_sim.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_verify_source_contract()
	await _verify_method_delay_handoff(
		"_start_working", "working",
		"_start_ron_warp_in", "ron_warp_in",
		0.5
	)
	await _verify_method_delay_handoff(
		"_start_ron_warp_in", "ron_warp_in",
		"_start_ron_approaches", "ron_approaches",
		1.3
	)
	await _verify_dialogue_handoff(
		"_start_ron_drinks", "ron_drinks",
		["_start_walk_to_drink", "walk_to_drink"],
		["aster_sim.ron.drinks"]
	)
	await _verify_dialogue_handoff(
		"_start_ron_move_fast", "ron_move_fast",
		["_start_explore_workspace", "explore_workspace"],
		[
			"aster_sim.ron.move_fast",
			"aster_sim.ron.lighting",
			"aster_sim.aster.lighting",
			"aster_sim.ron.tag_day_jobs",
		]
	)
	await _verify_dialogue_handoff(
		"_start_tag_notify", "tag_notify",
		["_start_walk_to_exit", "walk_to_exit"],
		["aster_sim.device.tag_verify", "aster_sim.ron.tag_notify"]
	)
	await _verify_dialogue_handoff(
		"_start_walk_to_exit", "walk_to_exit",
		["_start_transition_out", "transition_out"],
		["aster_sim.tag_routine"]
	)
	print("ASTER LINEAR CONTINUATIONS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_contract() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/tutorial/aster_sim_sequence.gd"
	)
	check(
		"_schedule_portable_method(0.5, _start_ron_warp_in, \"ron_warp_in\")" in source
			and "_schedule_portable_method(1.3, _start_ron_approaches, \"ron_approaches\")"
				in source,
		"working and warp hand-offs use named portable method delays"
	)
	check(
		"_scheduler.schedule_after(0.5, _start_ron_warp_in" not in source
			and "_scheduler.schedule_after(1.3, _start_ron_approaches" not in source,
		"the two causal intro delays no longer live only in the scheduler heap"
	)
	check(
		"dialogue_finished.connect(" not in source
			and "func(): _scheduler.schedule_after" not in source,
		"Aster Sim has no anonymous dialogue-to-gameplay continuation"
	)
	var gameplay_delay_lines: Array[String] = []
	for raw_line in source.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.begins_with("_scheduler.schedule_after("):
			gameplay_delay_lines.append(line)
	check(
		gameplay_delay_lines.size() == 1
			and "_show_drink_redirect" in gameplay_delay_lines[0],
		"the only remaining gameplay-lane delay is the non-gating drink reminder"
	)


func _verify_method_delay_handoff(
		start_method: String,
		owner_step: String,
		next_method: String,
		successor_step: String,
		delay: float
	) -> void:
	var source := await _spawn_sequence()
	source.call(start_method)
	var started_at := float(source._scheduler.get_current_tick())
	var initial: Dictionary = source._portable_continuation.duplicate(true)
	check(
		str(initial.get("kind", "")) == "method_delay"
			and str(initial.get("owner_step", "")) == owner_step
			and str(initial.get("next_method", "")) == next_method
			and is_equal_approx(float(initial.get("start_tick", -1.0)), started_at)
			and is_equal_approx(float(initial.get("deadline", -1.0)), started_at + delay),
		"%s publishes one named method and exact absolute deadline" % owner_step
	)
	source.headless_advance(delay * 0.4, minf(0.02, delay * 0.2))
	var capture := _json_round_trip(source.build_save_snapshot())
	var saved: Dictionary = capture.get("portable_continuation", {})
	var saved_deadline := float(saved.get("deadline", -1.0))
	var saved_serial := int(saved.get("serial", 0))

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(capture)
	source.apply_save_snapshot(capture)
	for pair in [["same", source], ["fresh", fresh]]:
		var label := str(pair[0])
		var sequence: Node = pair[1]
		var restored: Dictionary = sequence._portable_continuation
		check(
			str(restored.get("kind", "")) == "method_delay"
				and str(restored.get("owner_step", "")) == owner_step
				and str(restored.get("next_method", "")) == next_method
				and is_equal_approx(float(restored.get("deadline", -1.0)), saved_deadline),
			"%s-presenter %s restore keeps the original method deadline" % [label, owner_step]
		)
		var remaining := saved_deadline - float(sequence._scheduler.get_current_tick())
		sequence._scheduler.advance_ticks(maxf(0.0, remaining - 0.0005))
		check(
			str(sequence._current_step) == owner_step,
			"%s-presenter %s restore cannot advance before the saved deadline" % [
				label, owner_step,
			]
		)
		sequence._scheduler.advance_ticks(0.001)
		check(
			str(sequence._current_step) == successor_step,
			"%s-presenter %s restore advances at the saved deadline" % [label, owner_step]
		)
		if successor_step == "ron_warp_in":
			var successor: Dictionary = sequence._portable_continuation
			check(
				int(successor.get("serial", 0)) > saved_serial
					and str(successor.get("next_method", "")) == "_start_ron_approaches",
				"%s-presenter working callback is retired before the warp continuation is armed"
					% label
			)
		else:
			var ron: Dictionary = sequence._sequence_authority_section("ron")
			check(
				(sequence._portable_continuation as Dictionary).is_empty()
					and str(ron.get("phase", "")) == sequence.RON_PHASE_APPROACHING
					and (ron.get("operations", []) as Array).size() == 1,
				"%s-presenter warp callback commits one physical Ron approach" % label
			)
		var stable_serial := int(sequence._portable_continuation.get("serial", 0))
		sequence.headless_advance(0.05, 0.01)
		check(
			str(sequence._current_step) == successor_step
				and int(sequence._portable_continuation.get("serial", 0)) == stable_serial,
			"%s-presenter %s restore leaves no duplicate callback" % [label, owner_step]
		)

	await _dispose(source)
	await _dispose(fresh)


func _verify_dialogue_handoff(
		start_method: String,
		owner_step: String,
		successor: Array,
		expected_keys: Array
	) -> void:
	var source := await _spawn_sequence()
	_seed_passed_intro_authority(source)
	source.call(start_method)
	source._dialogue.advance_ui_time(0.07)
	var capture := _json_round_trip(source.build_save_snapshot())
	var saved_continuation: Dictionary = capture.get("portable_continuation", {})
	var saved_dialogue: Dictionary = capture.get("dialogue", {})
	check(
		str(saved_continuation.get("kind", "")) == "dialogue_chain"
			and str(saved_continuation.get("owner_step", "")) == owner_step
			and str(saved_continuation.get("next_method", "")) == str(successor[0])
			and (saved_continuation.get("keys", []) as Array) == expected_keys,
		"%s dialogue saves its ordered lines and named successor" % owner_step
	)

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(capture)
	source.apply_save_snapshot(capture)
	for pair in [["same", source], ["fresh", fresh]]:
		var label := str(pair[0])
		var sequence: Node = pair[1]
		var restored: Dictionary = sequence._portable_continuation
		var restored_dialogue: Dictionary = sequence._dialogue.snapshot_state()
		check(
			str(restored.get("kind", "")) == "dialogue_chain"
				and str(restored.get("owner_step", "")) == owner_step
				and str(restored.get("next_method", "")) == str(successor[0]),
			"%s-presenter %s restore keeps one named dialogue continuation" % [
				label, owner_step,
			]
		)
		check(
			str(restored_dialogue.get("current_text", ""))
					== str(saved_dialogue.get("current_text", ""))
				and is_equal_approx(
					float(restored_dialogue.get("displayed_chars", -1.0)),
					float(saved_dialogue.get("displayed_chars", -2.0))
				),
			"%s-presenter %s restore preserves the exact active line position" % [
				label, owner_step,
			]
		)

		_finish_dialogue_to_completion_pending(sequence)
		var pending: Dictionary = sequence._portable_continuation
		var dispatch_tick := float(sequence._scheduler.get_current_tick())
		check(
			str(sequence._current_step) == owner_step
				and str(pending.get("phase", "")) == "complete_pending"
				and is_equal_approx(float(pending.get("deadline", -1.0)), dispatch_tick),
			"%s-presenter %s completion records its exact dispatch seam" % [
				label, owner_step,
			]
		)
		sequence._scheduler.advance_ticks(sequence.PORTABLE_CONTINUATION_EPSILON * 0.5)
		check(
			str(sequence._current_step) == owner_step,
			"%s-presenter %s cannot dispatch before its portable epsilon" % [
				label, owner_step,
			]
		)
		sequence._scheduler.advance_ticks(sequence.PORTABLE_CONTINUATION_EPSILON * 0.75)
		check(
			str(sequence._current_step) == str(successor[1]),
			"%s-presenter %s dispatches its named successor exactly once" % [
				label, owner_step,
			]
		)
		_verify_successor_authority(sequence, owner_step, int(pending.get("serial", 0)))

	await _dispose(source)
	await _dispose(fresh)


func _finish_dialogue_to_completion_pending(sequence: Node) -> void:
	var safety := 0
	while sequence._dialogue.is_active() and safety < 96:
		sequence._dialogue.request_advance()
		safety += 1
	check(
		safety < 96 and not sequence._dialogue.is_active(),
		"%s dialogue reaches its portable completion seam" % str(sequence._current_step)
	)


func _verify_successor_authority(
		sequence: Node,
		owner_step: String,
		retired_serial: int
	) -> void:
	var successor_step := str(sequence._current_step)
	var successor_portable: Dictionary = sequence._portable_continuation
	if successor_step == "walk_to_exit":
		check(
			str(successor_portable.get("kind", "")) == "dialogue_chain"
				and str(successor_portable.get("next_method", "")) == "_start_transition_out"
				and int(successor_portable.get("serial", 0)) > retired_serial,
			"%s retires its chain before arming the exit dialogue" % owner_step
		)
	elif successor_step == "transition_out":
		var transition: Dictionary = sequence._sequence_authority_section("transition")
		check(
			successor_portable.is_empty()
				and str(transition.get("phase", "")) == sequence.TRANSITION_PHASE_FADING
				and is_equal_approx(
					float(transition.get("deadline", -1.0)),
					float(transition.get("started_at", -1.0)) + sequence.TRANSITION_DURATION
				),
			"exit dialogue hands off to one authoritative transition deadline"
		)
	else:
		check(
			successor_portable.is_empty(),
			"%s retires its dialogue continuation before %s begins" % [
				owner_step, successor_step,
			]
		)
	var stable_step := successor_step
	var stable_serial := int(successor_portable.get("serial", 0))
	var transition_started := float(
		sequence._sequence_authority_section("transition").get("started_at", -1.0)
	)
	sequence._scheduler.advance_ticks(0.02)
	check(
		str(sequence._current_step) == stable_step
			and int(sequence._portable_continuation.get("serial", 0)) == stable_serial
			and is_equal_approx(
				float(sequence._sequence_authority_section("transition").get(
					"started_at", -1.0)),
				transition_started
			),
		"%s leaves no discarded or duplicate causal callback" % owner_step
	)


func _seed_passed_intro_authority(sequence: Node) -> void:
	var now := float(sequence._scheduler.get_current_tick())
	var endpoint: Vector3 = sequence._ron_approach_endpoint()
	var ron := sequence._baseline_ron_authority() as Dictionary
	ron["phase"] = sequence.RON_PHASE_COMPLETE
	ron["started_at"] = now
	ron["arrived_at"] = now
	ron["completed_at"] = now
	ron["endpoint"] = sequence._authority_v3_data(endpoint)
	ron["operation_counter"] = 1
	ron["operations"] = [{
		"operation_id": "test_intro_approach:1",
		"actor_id": "ron",
		"kind": "move_to_pos",
		"accepted": true,
		"rejection": "",
		"committed_at": now,
		"endpoint": sequence._authority_v3_data(endpoint),
	}]
	sequence._publish_sequence_authority_section("ron", ron)

	var terminal := sequence._baseline_terminal_authority() as Dictionary
	terminal["phase"] = sequence.TERMINAL_PHASE_COMPLETE
	terminal["started_at"] = now
	terminal["tutorial_complete"] = true
	sequence._publish_sequence_authority_section("terminal", terminal)


func _spawn_sequence() -> Node:
	var sequence := AsterSimScene.instantiate()
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
	sequence._cancel_portable_continuation()
	sequence._clear_dialogue_presenter_for_restore()
	return sequence


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.free()
	await process_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
