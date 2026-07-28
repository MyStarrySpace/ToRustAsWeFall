extends SceneTree

## Adversarial regression for the Aster-sim choreography that used to be owned by
## fixed delays and view-local callbacks.
## Run:
##   ..\Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_aster_sim_sequence_authority.gd

const AsterSimScene := preload("res://scenes/tutorial/aster_sim.tscn")

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
	await _verify_ron_approach_authority()
	await _verify_terminal_focus_authority()
	await _verify_transition_authority()
	print("ASTER SIM SEQUENCE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_ron_approach_authority() -> void:
	var source := await _spawn_sequence()
	var gs: GameState = source._game_state
	# A temporary action lock makes GameState reject Ron's first authored move.
	# The receipt must say so; a timer must not silently greet anyway.
	gs._knocked_down["ron"] = {"end_tick": 9999.0, "handle": 0}
	source._start_ron_approaches()
	var rejected: Dictionary = source._sequence_authority_section("ron")
	var rejected_ops := rejected.get("operations", []) as Array
	check(str(rejected.get("phase", "")) == source.RON_PHASE_APPROACHING,
		"a rejected Ron move leaves the intro at its physical approach phase")
	check(rejected_ops.size() == 1
			and not bool((rejected_ops[0] as Dictionary).get("accepted", true)),
		"the movement authority records the rejected command instead of assuming success")
	source.headless_advance(0.8, 0.05)
	check(str(source._current_step) == "ron_approaches",
		"elapsed wall time cannot substitute for Ron's rejected arrival")

	gs._knocked_down.erase("ron")
	source.headless_advance(source.RON_APPROACH_RETRY_SECONDS + 0.05, 0.05)
	var accepted: Dictionary = source._sequence_authority_section("ron")
	var accepted_ops := accepted.get("operations", []) as Array
	check(not accepted_ops.is_empty()
			and bool((accepted_ops[-1] as Dictionary).get("accepted", false))
			and gs.is_moving("ron"),
		"releasing the lock reissues and records a real accepted GameState move")

	var first_motion := gs.get_position("ron")
	source.headless_advance(0.12, 0.04)
	var partial := gs.get_position("ron")
	check(partial.distance_to(first_motion) > 0.01
			and str(source._current_step) == "ron_approaches",
		"partial physical progress is visible but cannot satisfy the greeting latch")
	gs.command_stop("ron")
	var interrupted_position := gs.get_position("ron")
	source.headless_advance(0.05, 0.05)
	var interrupted: Dictionary = source._sequence_authority_section("ron")
	check(str(interrupted.get("phase", "")) == source.RON_PHASE_APPROACHING
			and not (interrupted.get("interruptions", []) as Array).is_empty(),
		"stopping Ron early records an interruption and blocks continuation")
	check(gs.get_position("ron").distance_to(interrupted_position) < 0.001,
		"interruption handling does not snap Ron to the authored endpoint")
	source.headless_advance(source.RON_APPROACH_RETRY_SECONDS + 0.05, 0.05)
	check(gs.is_moving("ron") and str(source._current_step) == "ron_approaches",
		"an interrupted approach safely reissues rather than force-completing")

	# Save during the reissued move. GameState owns the movement remainder; the
	# sequence record owns which accepted operation and endpoint it must satisfy.
	source.headless_advance(0.15, 0.05)
	var saved_midpoint := gs.get_position("ron")
	var midpoint_capture := _json_round_trip(source.build_save_snapshot())
	var loaded := await _spawn_sequence()
	loaded.apply_save_snapshot(midpoint_capture)
	var loaded_record: Dictionary = loaded._sequence_authority_section("ron")
	check(str(loaded_record.get("phase", "")) == loaded.RON_PHASE_APPROACHING
			and loaded._game_state.is_moving("ron"),
		"fresh load reconstructs the accepted in-flight approach")
	check(loaded._game_state.get_position("ron").distance_to(saved_midpoint) < 0.001,
		"loading an approach preserves its exact midpoint instead of teleporting")
	check(str(loaded._current_step) == "ron_approaches",
		"a midpoint save cannot jump directly to Ron's greeting")

	var safety := 0
	while str(loaded._sequence_authority_section("ron").get("phase", "")) \
			== loaded.RON_PHASE_APPROACHING and safety < 400:
		loaded.headless_advance(0.05, 0.05)
		safety += 1
	var arrived: Dictionary = loaded._sequence_authority_section("ron")
	var endpoint: Vector3 = loaded._authority_v3(arrived.get("endpoint", null))
	check(str(arrived.get("phase", "")) == loaded.RON_PHASE_GREETING
			and loaded._ron_has_accepted_approach_receipt(arrived)
			and not loaded._game_state.is_moving("ron")
			and loaded._game_state.get_position("ron").distance_to(endpoint)
				<= loaded.RON_APPROACH_ARRIVAL_RADIUS,
		"only Ron's settled body at the saved endpoint opens the greeting")

	# A missing record paired with a future-looking greeting step is untrusted.
	# Reload must preserve Ron's physical midpoint and replay the approach.
	var missing := midpoint_capture.duplicate(true)
	var missing_game_state := missing.get("game_state", {}) as Dictionary
	var missing_world := missing_game_state.get("world_state", {}) as Dictionary
	missing_world.erase(source.SEQUENCE_AUTHORITY_KEY)
	missing_game_state["world_state"] = missing_world
	missing["game_state"] = missing_game_state
	missing["current_step"] = "ron_greeting"
	var repaired := await _spawn_sequence()
	repaired.apply_save_snapshot(_json_round_trip(missing))
	var repaired_record: Dictionary = repaired._sequence_authority_section("ron")
	check(str(repaired_record.get("phase", "")) == repaired.RON_PHASE_APPROACHING
			and str(repaired._current_step) == "ron_approaches",
		"missing Ron authority fails closed to a new physical approach")
	check(repaired._game_state.get_position("ron").distance_to(saved_midpoint) < 0.001,
		"repairing missing authority does not edit Ron's saved position")

	await _dispose(source)
	await _dispose(loaded)
	await _dispose(repaired)


func _verify_terminal_focus_authority() -> void:
	# Contract drivers and deterministic replay may jump exactly from scheduled
	# endpoint to endpoint with pop_next(), so chained authority must survive that
	# execution mode as well as ordinary incremental advance.
	var popped := await _spawn_sequence()
	_prepare_terminal_source(popped)
	popped._start_terminal_focus()
	check(str(popped._sequence_authority_section("terminal").get("phase", ""))
			== popped.TERMINAL_PHASE_IDLE,
		"retired terminal-focus helper is inert without a physical receipt")
	check(_trigger_terminal(popped),
		"pop-next fixture begins from the exact terminal source")
	popped._scheduler.pop_next()
	check(str(popped._sequence_authority_section("terminal").get("phase", ""))
			== popped.TERMINAL_PHASE_SETTLING,
		"terminal focus endpoint enters the settle phase under pop-next execution")
	check(popped._scheduler.pending_count() > 0,
		"terminal focus endpoint leaves one settle callback visible to pop-next drivers")
	popped._scheduler.pop_next()
	check(str(popped._current_step) == "ron_drinks",
		"pop-next execution crosses the saved settle endpoint without stalling")
	await _dispose(popped)

	var source := await _spawn_sequence()
	_prepare_terminal_source(source)
	source._camera.follow_offset = Vector3(-7.25, 9.5, 4.75)
	source._camera.set("_pan_offset", Vector3(1.25, 0.0, -0.75))
	source._camera.set("_view_yaw", 0.35)
	source._camera.set("_view_zoom", 1.25)
	source._on_terminal_interacted()
	source._terminal.interacted.emit()
	check(str(source._sequence_authority_section("terminal").get("phase", ""))
			== source.TERMINAL_PHASE_IDLE,
		"direct and manually emitted terminal callbacks cannot begin a read")
	source.set_preview_character_position("aster", Vector3.ZERO)
	source._terminal.active_character = "aster"
	check(not bool(source._terminal.call("_trigger", false)),
		"a remote selected Aster cannot read the terminal")
	source.set_preview_character_position("aster", source._terminal.global_position)
	source._terminal.active_character = "ron"
	check(not bool(source._terminal.call("_trigger", false)),
		"the nearby wrong body cannot read Aster's terminal")
	source._terminal.active_character = "aster"
	check(bool(source._terminal.call("_trigger", false)),
		"the exact terminal accepts nearby action-free Aster")
	source.headless_advance(1.25, 0.05)
	var focus_record: Dictionary = source._sequence_authority_section("terminal")
	check(str(focus_record.get("source_data_id", ""))
			== source.ASTER_TERMINAL_SOURCE_ID
			and int(focus_record.get("source_trigger_count", 0)) == 1,
		"terminal phase preserves its exact monotonic source receipt")
	var focus_deadline := float(focus_record.get("deadline", -1.0))
	var focus_capture := _json_round_trip(source.build_save_snapshot())
	var saved_aster_position: Vector3 = source._game_state.get_position("aster")

	var loaded := await _spawn_sequence()
	loaded.apply_save_snapshot(focus_capture)
	var loaded_focus: Dictionary = loaded._sequence_authority_section("terminal")
	check(str(loaded_focus.get("phase", "")) == loaded.TERMINAL_PHASE_ACTIVE
			and is_equal_approx(float(loaded_focus.get("deadline", -1.0)), focus_deadline),
		"terminal focus reload preserves its exact absolute deadline")
	check(loaded._terminal_focus_active and loaded._camera.is_locked()
			and not loaded._player.is_move_enabled(),
		"active focus reconstructs the screen camera and input lock")
	check(loaded._game_state.get_position("aster").distance_to(saved_aster_position) < 0.001,
		"restoring camera focus never teleports Aster")

	var remaining := focus_deadline - float(loaded._scheduler.get_current_tick())
	loaded.headless_advance(maxf(0.0, remaining - 0.001), 0.05)
	check(str(loaded._sequence_authority_section("terminal").get("phase", ""))
			== loaded.TERMINAL_PHASE_ACTIVE,
		"terminal focus cannot complete before its saved endpoint")
	loaded.headless_advance(0.002, 0.001)
	var settling: Dictionary = loaded._sequence_authority_section("terminal")
	check(str(settling.get("phase", "")) == loaded.TERMINAL_PHASE_SETTLING
			and str(loaded._current_step) == "terminal_data",
		"the focus endpoint enters an explicit saved settle phase")
	check(not loaded._terminal_focus_active and not loaded._camera.is_locked()
			and loaded._player.is_move_enabled()
			and loaded._camera.follow_offset.distance_to(Vector3(-7.25, 9.5, 4.75)) < 0.001
			and (loaded._camera.get("_pan_offset") as Vector3).distance_to(
				Vector3(1.25, 0.0, -0.75)) < 0.001
			and is_equal_approx(float(loaded._camera.get("_view_yaw")), 0.35)
			and is_equal_approx(float(loaded._camera.get("_view_zoom")), 1.25),
		"focus completion restores the saved camera framing and input state")

	loaded.headless_advance(0.17, 0.01)
	var settle_capture := _json_round_trip(loaded.build_save_snapshot())
	var settle_deadline := float(
		loaded._sequence_authority_section("terminal").get("deadline", -1.0))
	var settle_loaded := await _spawn_sequence()
	settle_loaded.apply_save_snapshot(settle_capture)
	var settle_remaining := settle_deadline - float(settle_loaded._scheduler.get_current_tick())
	settle_loaded.headless_advance(maxf(0.0, settle_remaining - 0.001), 0.01)
	check(str(settle_loaded._current_step) == "terminal_data",
		"mid-settle reload consumes the saved remainder rather than completing instantly")
	settle_loaded.headless_advance(0.002, 0.001)
	check(str(settle_loaded._current_step) == "ron_drinks"
			and str(settle_loaded._sequence_authority_section("terminal").get("phase", ""))
				== settle_loaded.TERMINAL_PHASE_COMPLETE,
		"the exact settle endpoint advances once and retires its callback phase")

	# An edited deadline/camera payload cannot manufacture an already-complete read.
	var malformed := focus_capture.duplicate(true)
	var malformed_game_state := malformed.get("game_state", {}) as Dictionary
	var malformed_world := malformed_game_state.get("world_state", {}) as Dictionary
	var outer := malformed_world.get(source.SEQUENCE_AUTHORITY_KEY, {}) as Dictionary
	var terminal := (outer.get("terminal", {}) as Dictionary).duplicate(true)
	terminal["deadline"] = float(terminal.get("started_at", 0.0))
	terminal["return_camera"] = {"target_id": "aster"}
	outer["terminal"] = terminal
	malformed_world[source.SEQUENCE_AUTHORITY_KEY] = outer
	malformed_game_state["world_state"] = malformed_world
	malformed["game_state"] = malformed_game_state
	var malformed_loaded := await _spawn_sequence()
	malformed_loaded.apply_save_snapshot(_json_round_trip(malformed))
	var repaired: Dictionary = malformed_loaded._sequence_authority_section("terminal")
	check(str(repaired.get("phase", "")) == malformed_loaded.TERMINAL_PHASE_IDLE
			and int(repaired.get("source_trigger_count", 0)) == 1,
		"malformed focus authority burns its source edge without granting a read")
	check(not malformed_loaded._camera.is_locked()
			and malformed_loaded._player.is_move_enabled()
			and str(malformed_loaded._current_step) == "show_terminal"
			and malformed_loaded._terminal.is_interaction_enabled(),
		"malformed focus authority fails closed to the physical terminal")

	await _verify_terminal_accepted_source_seam()

	await _dispose(source)
	await _dispose(loaded)
	await _dispose(settle_loaded)
	await _dispose(malformed_loaded)


func _verify_terminal_accepted_source_seam() -> void:
	var same := await _spawn_sequence()
	_prepare_terminal_source(same)
	var callback := Callable(same, "_on_terminal_interacted")
	if same._terminal.interacted.is_connected(callback):
		same._terminal.interacted.disconnect(callback)
	check(_trigger_terminal(same),
		"fixture captures an accepted terminal edge before its owner callback")
	var seam_snapshot := _json_round_trip(same.build_save_snapshot())
	same._terminal.interacted.connect(callback)
	check(str(same._sequence_authority_section("terminal").get("phase", ""))
			== same.TERMINAL_PHASE_IDLE,
		"accepted terminal edge alone does not reveal the monitor")

	same.apply_save_snapshot(seam_snapshot)
	var same_terminal: Dictionary = same._sequence_authority_section("terminal")
	check(str(same_terminal.get("phase", "")) == same.TERMINAL_PHASE_IDLE
			and int(same_terminal.get("source_trigger_count", 0)) == 1
			and same._terminal.is_interaction_enabled(),
		"same-presenter restore burns but rearms the accepted terminal edge")
	same._terminal.active_character = "aster"
	var same_retriggered := bool(same._terminal.call("_trigger", false))
	check(same_retriggered
			and str(same._sequence_authority_section("terminal").get("phase", ""))
				== same.TERMINAL_PHASE_ACTIVE,
		"same presenter needs a second exact terminal receipt")

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(seam_snapshot)
	var fresh_terminal: Dictionary = fresh._sequence_authority_section("terminal")
	check(str(fresh_terminal.get("phase", "")) == fresh.TERMINAL_PHASE_IDLE
			and int(fresh_terminal.get("source_trigger_count", 0)) == 1
			and fresh._terminal.is_interaction_enabled(),
		"fresh presenter burns and rearms the same accepted terminal edge")
	fresh._terminal.active_character = "aster"
	var fresh_retriggered := bool(fresh._terminal.call("_trigger", false))
	check(fresh_retriggered
			and str(fresh._sequence_authority_section("terminal").get("phase", ""))
				== fresh.TERMINAL_PHASE_ACTIVE,
		"fresh presenter also requires a new exact terminal receipt")

	await _dispose(same)
	await _dispose(fresh)


func _verify_transition_authority() -> void:
	var source := await _spawn_sequence()
	source._current_step = "walk_to_exit"
	source._player.set_move_enabled(true)
	source._camera.follow_offset = Vector3(-5.0, 8.25, 6.5)
	source._camera.set("_pan_offset", Vector3(-0.5, 0.0, 1.25))
	source._camera.set("_view_yaw", -0.4)
	source._camera.set("_view_zoom", 1.4)
	source._start_transition_out()
	source.headless_advance(1.0, 0.05)
	var transition: Dictionary = source._sequence_authority_section("transition")
	var deadline := float(transition.get("deadline", -1.0))
	var expected_alpha: float = source._fade_rect.color.a
	var saved_position: Vector3 = source._game_state.get_position("aster")
	var capture := _json_round_trip(source.build_save_snapshot())

	var loaded := await _spawn_sequence()
	loaded.apply_save_snapshot(capture)
	var loaded_transition: Dictionary = loaded._sequence_authority_section("transition")
	check(str(loaded_transition.get("phase", "")) == loaded.TRANSITION_PHASE_FADING
			and is_equal_approx(float(loaded_transition.get("deadline", -1.0)), deadline),
		"transition reload preserves the exact fade deadline")
	check(str(loaded._current_step) == "transition_out"
			and not loaded._player.is_move_enabled()
			and loaded.requested_scene_change == "",
		"mid-transition load restores its input lock without requesting the next scene early")
	check(absf(loaded._fade_rect.color.a - expected_alpha) < 0.02
			and loaded._camera.follow_offset.distance_to(Vector3(-5.0, 8.25, 6.5)) < 0.001
			and (loaded._camera.get("_pan_offset") as Vector3).distance_to(
				Vector3(-0.5, 0.0, 1.25)) < 0.001
			and is_equal_approx(float(loaded._camera.get("_view_yaw")), -0.4)
			and is_equal_approx(float(loaded._camera.get("_view_zoom")), 1.4),
		"mid-transition load reconstructs fade progress and camera framing")
	check(loaded._game_state.get_position("aster").distance_to(saved_position) < 0.001,
		"transition reconstruction leaves authoritative character position untouched")

	var remaining := deadline - float(loaded._scheduler.get_current_tick())
	loaded.headless_advance(maxf(0.0, remaining - 0.001), 0.05)
	check(loaded.requested_scene_change == ""
			and str(loaded._current_step) == "transition_out",
		"the restored transition cannot change scenes before its saved endpoint")
	loaded.headless_advance(0.002, 0.001)
	check(loaded.requested_scene_change == "res://scenes/tutorial/peris_sim.tscn"
			and str(loaded._current_step) == "complete"
			and str(loaded._sequence_authority_section("transition").get("phase", ""))
				== loaded.TRANSITION_PHASE_COMPLETE,
		"the saved endpoint commits one explicit complete phase and scene handoff")

	var completed_capture := _json_round_trip(loaded.build_save_snapshot())
	var completed_loaded := await _spawn_sequence()
	completed_loaded.apply_save_snapshot(completed_capture)
	check(str(completed_loaded._current_step) == "complete"
			and completed_loaded.requested_scene_change \
				== "res://scenes/tutorial/peris_sim.tscn"
			and not completed_loaded._player.is_move_enabled()
			and completed_loaded._camera.follow_offset.distance_to(
				Vector3(-5.0, 8.25, 6.5)) < 0.001,
		"a committed transition load reconstructs its final camera/input presenter")

	var malformed := capture.duplicate(true)
	var malformed_game_state := malformed.get("game_state", {}) as Dictionary
	var malformed_world := malformed_game_state.get("world_state", {}) as Dictionary
	var outer := malformed_world.get(source.SEQUENCE_AUTHORITY_KEY, {}) as Dictionary
	var broken_transition := (outer.get("transition", {}) as Dictionary).duplicate(true)
	broken_transition["deadline"] = float(broken_transition.get("started_at", 0.0)) - 10.0
	outer["transition"] = broken_transition
	malformed_world[source.SEQUENCE_AUTHORITY_KEY] = outer
	malformed_game_state["world_state"] = malformed_world
	malformed["game_state"] = malformed_game_state
	malformed["current_step"] = "complete"
	malformed["requested_scene_change"] = "res://scenes/tutorial/peris_sim.tscn"
	var repaired := await _spawn_sequence()
	repaired.apply_save_snapshot(_json_round_trip(malformed))
	var repaired_transition: Dictionary = repaired._sequence_authority_section("transition")
	check(str(repaired_transition.get("phase", "")) == repaired.TRANSITION_PHASE_FADING
			and str(repaired._current_step) == "transition_out"
			and repaired.requested_scene_change == "",
		"malformed transition authority fails closed instead of retaining a future scene request")
	check(float(repaired_transition.get("deadline", -1.0))
			- float(repaired._scheduler.get_current_tick())
			>= repaired.TRANSITION_DURATION - 0.001
			and repaired._fade_rect.color.a <= 0.001,
		"fail-closed transition repair replays the complete fade rather than instant-completing")

	await _dispose(source)
	await _dispose(loaded)
	await _dispose(completed_loaded)
	await _dispose(repaired)


func _prepare_terminal_source(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._current_step = "show_terminal"
	sequence._player.set_move_enabled(true)
	sequence._set_aster_source_projection(sequence._terminal, true)
	sequence.set_preview_character_position(
		"aster", sequence._terminal.global_position)
	sequence._terminal.active_character = "aster"


func _trigger_terminal(sequence: Node) -> bool:
	sequence._terminal.active_character = "aster"
	return bool(sequence._terminal.call("_trigger", false))


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
