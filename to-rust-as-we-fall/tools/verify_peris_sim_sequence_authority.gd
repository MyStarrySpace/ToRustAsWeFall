extends SceneTree

## Mid-phase save/load regression for Peris's two-visit progression and canonical
## Wrap tutorial. Run with Godot 4.6.1:
##   ..\Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_peris_sim_sequence_authority.gd

const PerisScene := preload("res://scenes/tutorial/peris_sim.tscn")

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
	_verify_source_contract()
	await _verify_visit_and_exploration_authority()
	await _verify_wrap_phase_authority()
	print("PERIS SIM SEQUENCE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_contract() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/tutorial/peris_sim_sequence.gd")
	check("func(" not in source,
		"Peris Sim has no anonymous story, scheduler, interaction, HUD, or tween callback")
	check("_show_exploration_highlight_hint" in source
			and "_on_hud_ability_pressed" in source
			and "_on_strike_warning_interacted" in source,
		"room presentation observers use stable named endpoints")


func _verify_visit_and_exploration_authority() -> void:
	var source := await _spawn_sequence(1)
	var initial := source._peris_authority_state() as Dictionary
	check(int(initial.get("version", 0)) == source.PERIS_AUTHORITY_VERSION
			and int(initial.get("visit_phase", 0)) == 1,
		"first visit publishes a versioned portable record instead of process-static truth")
	check(str(initial.get("phase", "")) == source.PERIS_PHASE_FADE_FIRST
			and source._scheduler.pending_count() == 1,
		"first-visit fade has one authoritative absolute-deadline continuation")

	_source_advance_to_phase(source, source.PERIS_PHASE_EXPLORATION)
	source._on_care_context_zone_interacted("plant", "fern")
	source._on_care_context_zone_interacted("wellness", "wellness")
	var saved_position: Vector3 = source._game_state.get_position("peris")
	var capture := _json_round_trip(source.build_save_snapshot())
	var saved := source._peris_authority_state() as Dictionary
	var saved_exploration := saved.get("exploration", {}) as Dictionary
	check(str(saved.get("phase", "")) == source.PERIS_PHASE_EXPLORATION
			and bool(saved_exploration.get("gate_unlocked", false))
			and int((saved_exploration.get("zone_visits", {}) as Dictionary).get("fern", 0)) == 1,
		"exploration authority stores the gate and optional observation provenance")

	# Same-presenter rollback retracts a later gate fire and dialogue phase.
	source._on_exploration_gate_interacted()
	check(str(source._peris_authority_state().get("phase", ""))
			== source.PERIS_PHASE_FIRST_DIALOGUE,
		"the physical logbook interaction commits the next phase")
	source.apply_save_snapshot(capture)
	check(str(source._current_step) == "workspace"
			and str(source._peris_authority_state().get("phase", ""))
				== source.PERIS_PHASE_EXPLORATION
			and not source._explore_gate_fired,
		"same-presenter load retracts the post-save dialogue future")
	check(source._game_state.get_position("peris").distance_to(saved_position) < 0.001
			and source._player.is_move_enabled(),
		"exploration restore preserves Peris's physical position and input gate")

	var loaded := await _spawn_sequence(1)
	loaded.apply_save_snapshot(capture)
	var loaded_exploration := (loaded._peris_authority_state().get(
		"exploration", {}) as Dictionary)
	check(str(loaded._current_step) == "workspace"
			and loaded._explore_gate_unlocked and not loaded._explore_gate_fired,
		"fresh presenter reconstructs the active exploration gate")
	check(int((loaded_exploration.get("zone_visits", {}) as Dictionary).get("fern", 0)) == 1
			and bool((loaded_exploration.get("room_reads", {}) as Dictionary).get(
				"wellness", false)),
		"fresh exploration restore keeps observation counts without rebuilding a checklist")

	var second := await _spawn_sequence(2)
	var second_authority := second._peris_authority_state() as Dictionary
	check(int(second_authority.get("visit_phase", 0)) == 2
			and str(second_authority.get("phase", "")) == second.PERIS_PHASE_FADE_SECOND,
		"second visit is instance-owned and encoded in its portable authority record")
	check(source._visit_phase == 1 and loaded._visit_phase == 1 and second._visit_phase == 2,
		"concurrent Peris presenters do not leak visit phase through process-static state")
	var legacy_second := await _spawn_sequence_by_instance_visit(2)
	check(legacy_second.start_phase == 0 and legacy_second._visit_phase == 2
			and int(legacy_second._peris_authority_state().get("visit_phase", 0)) == 2,
		"instance visit override remains compatible with existing sequence drivers")
	_source_advance_to_phase(legacy_second, legacy_second.PERIS_PHASE_ATTACK_DIALOGUE)
	check(legacy_second._dialogue.is_active(),
		"instance visit override reaches the second-visit attack dialogue")

	await _dispose(source)
	await _dispose(loaded)
	await _dispose(second)
	await _dispose(legacy_second)


func _verify_wrap_phase_authority() -> void:
	var source := await _spawn_sequence(2)
	_isolate_wrap_prompt(source)
	var prompt_capture := _json_round_trip(source.build_save_snapshot())
	var prompt_loaded := await _spawn_sequence(2)
	prompt_loaded.apply_save_snapshot(prompt_capture)
	check(str(prompt_loaded._current_step) == "protect_prompt"
			and prompt_loaded._is_paused and not prompt_loaded._player.is_move_enabled(),
		"fresh load reconstructs the paused Wrap prompt")

	source._on_protect_pressed()
	var queued_capture := _json_round_trip(source.build_save_snapshot())
	var queued_loaded := await _spawn_sequence(2)
	queued_loaded.apply_save_snapshot(queued_capture)
	check(str(queued_loaded._peris_authority_state().get("phase", ""))
			== queued_loaded.PERIS_PHASE_WRAP_QUEUED
			and str(queued_loaded._current_step) == "run_prompt",
		"queued Wrap input survives a fresh presenter without auto-casting")

	source._toggle_run()
	var targeting_capture := _json_round_trip(source.build_save_snapshot())
	var targeting_loaded := await _spawn_sequence(2)
	targeting_loaded.apply_save_snapshot(targeting_capture)
	check(str(targeting_loaded._peris_authority_state().get("phase", ""))
			== targeting_loaded.PERIS_PHASE_WRAP_TARGETING
			and str(targeting_loaded._player.get("_click_mode")) == "select",
		"target-selection mode is rebuilt from authority")

	source._start_confirm_protect()
	var targeted_capture := _json_round_trip(source.build_save_snapshot())
	var targeted_loaded := await _spawn_sequence(2)
	targeted_loaded.apply_save_snapshot(targeted_capture)
	check(str(targeted_loaded._peris_authority_state().get("phase", ""))
			== targeted_loaded.PERIS_PHASE_WRAP_TARGETED
			and targeted_loaded._protect_queued,
		"confirmed Wrap target remains an explicit committed phase")

	# Capture inside queue-pending publication, before GameState has installed the
	# derived queued ability. Loading must issue the already-committed command once.
	var pending_capture := {}
	var capture_pending := func(key: String, value: Variant):
		if key == source.PERIS_AUTHORITY_KEY and value is Dictionary \
				and str((value as Dictionary).get("phase", "")) \
					== source.PERIS_PHASE_WRAP_QUEUE_PENDING \
				and pending_capture.is_empty():
			pending_capture.assign(_json_round_trip(source.build_save_snapshot()))
	source._game_state.world_state_changed.connect(capture_pending)
	source._start_executing()
	if source._game_state.world_state_changed.is_connected(capture_pending):
		source._game_state.world_state_changed.disconnect(capture_pending)
	check(not pending_capture.is_empty()
			and not bool(((pending_capture.get("game_state", {}) as Dictionary).get(
				"queued_canonical_abilities", {}) as Dictionary).has("peris")),
		"signal-time save observes queue-pending before derived GameState work exists")
	var pending_loaded := await _spawn_sequence(2)
	pending_loaded.apply_save_snapshot(pending_capture)
	check(pending_loaded._game_state.has_queued_ability("peris")
			and str(pending_loaded._peris_authority_state().get("phase", ""))
				== pending_loaded.PERIS_PHASE_WRAP_APPROACH,
		"fresh queue-pending load reconstructs one canonical queued ability")

	var approach_capture := _json_round_trip(source.build_save_snapshot())
	var approach_position: Vector3 = source._game_state.get_position("peris")
	var approach_stamina: float = source._game_state.get_stat("peris", "stamina")
	var approach_loaded := await _spawn_sequence(2)
	approach_loaded.apply_save_snapshot(approach_capture)
	check(approach_loaded._game_state.has_queued_ability("peris")
			and approach_loaded._game_state.is_moving("peris")
			and approach_loaded._game_state.get_position("peris").distance_to(
				approach_position) < 0.001,
		"fresh approach load preserves the exact in-flight movement and queue")

	var cast_capture := {}
	var capture_cast := func(key: String, value: Variant):
		if key == approach_loaded.PERIS_AUTHORITY_KEY and value is Dictionary \
				and str((value as Dictionary).get("phase", "")) \
					== approach_loaded.PERIS_PHASE_WRAP_CAST \
				and cast_capture.is_empty():
			cast_capture.assign(_json_round_trip(approach_loaded.build_save_snapshot()))
	approach_loaded._game_state.world_state_changed.connect(capture_cast)
	_source_advance_to_phase(approach_loaded, approach_loaded.PERIS_PHASE_AFTERMATH)
	if approach_loaded._game_state.world_state_changed.is_connected(capture_cast):
		approach_loaded._game_state.world_state_changed.disconnect(capture_cast)
	check(not cast_capture.is_empty(),
		"signal-time save captures the explicit cast phase before aftermath")
	var cast_stamina: float = approach_loaded._game_state.get_stat("peris", "stamina")
	check(approach_loaded._game_state.get_damage_shield("monos") > 0.0
			and cast_stamina <= approach_stamina \
				- CanonicalCharacterAbility.STAMINA_COST_BY_ABILITY["wrap"] + 0.001,
		"canonical Wrap pays stamina once and creates the real Monos shield")

	var cast_loaded := await _spawn_sequence(2)
	cast_loaded.apply_save_snapshot(cast_capture)
	check(str(cast_loaded._peris_authority_state().get("phase", ""))
			in [cast_loaded.PERIS_PHASE_WRAP_CAST, cast_loaded.PERIS_PHASE_AFTERMATH]
			and cast_loaded._game_state.get_damage_shield("monos") > 0.0
			and is_equal_approx(
				cast_loaded._game_state.get_stat("peris", "stamina"), cast_stamina),
		"fresh cast load preserves the paid shield and re-arms resolution")
	cast_loaded.headless_advance(0.01, 0.01)
	check(str(cast_loaded._peris_authority_state().get("phase", ""))
			== cast_loaded.PERIS_PHASE_AFTERMATH,
		"restored cast advances exactly once into aftermath")

	var aftermath_capture := _json_round_trip(approach_loaded.build_save_snapshot())
	var aftermath_loaded := await _spawn_sequence(2)
	aftermath_loaded.apply_save_snapshot(aftermath_capture)
	check(str(aftermath_loaded._current_step) == "aftermath"
			and aftermath_loaded._dialogue.is_active(),
		"fresh aftermath load reconstructs its continuation instead of losing a Callable")
	_finish_active_dialogue(aftermath_loaded)
	check(str(aftermath_loaded._peris_authority_state().get("phase", ""))
			== aftermath_loaded.PERIS_PHASE_EFFICIENCY_LOG,
		"restored aftermath reaches the next authoritative beat")

	await _dispose(source)
	await _dispose(prompt_loaded)
	await _dispose(queued_loaded)
	await _dispose(targeting_loaded)
	await _dispose(targeted_loaded)
	await _dispose(pending_loaded)
	await _dispose(approach_loaded)
	await _dispose(cast_loaded)
	await _dispose(aftermath_loaded)


func _isolate_wrap_prompt(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._ui_scheduler.clear()
	sequence._ui_scheduler.resume()
	sequence._clear_peris_authority_callbacks()
	sequence._visit_phase = 2
	sequence._start_protect_prompt()


func _source_advance_to_phase(sequence: Node, expected_phase: String) -> void:
	var safety := 0
	while str(sequence._peris_authority_state().get("phase", "")) != expected_phase \
			and safety < 1000:
		if sequence._scheduler.pending_count() > 0:
			sequence._scheduler.pop_next()
		else:
			sequence.headless_advance(0.05, 0.05)
		safety += 1
	check(safety < 1000, "authority reaches phase '%s'" % expected_phase)


func _finish_active_dialogue(sequence: Node) -> void:
	var safety := 0
	while sequence._dialogue.is_active() and safety < 200:
		sequence._dialogue.advance_ui_time(16.0)
		if float(sequence._dialogue.get("_displayed_chars")) \
				>= float(str(sequence._dialogue.get("_current_text")).length()):
			sequence._dialogue.request_advance()
		safety += 1


func _spawn_sequence(visit: int) -> Node:
	var sequence := PerisScene.instantiate()
	sequence.start_phase = visit
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(5):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
	return sequence


func _spawn_sequence_by_instance_visit(visit: int) -> Node:
	var sequence := PerisScene.instantiate()
	sequence._visit_phase = visit
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(5):
		await process_frame
	sequence.set_process(false)
	sequence.set_physics_process(false)
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
