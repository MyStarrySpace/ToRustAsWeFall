extends SceneTree

## Regression for Leaving Facility's linear narrative seams. EventScheduler intentionally does not
## serialize Callables, so these pauses/dialogue hand-offs must survive through TutorialSequence's
## named portable-continuation record instead of silently stalling or skipping on load.

const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")
const EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var script_text := FileAccess.get_file_as_string(
		"res://scripts/tutorial/leaving_facility_sequence.gd")
	check("func(): _scheduler.schedule_after(0, _start_first_corridor" not in script_text
			and "schedule_after(4.0, _start_second_iron" not in script_text
			and "schedule_after(2.5, _start_first_rest" not in script_text
			and "func(): _current_step = \"complete\"" not in script_text,
		"Leaving Facility has no heap-only linear story hand-off")
	await _verify_dusk_delay()
	await _verify_shelter_and_dawn_chain()
	print("LEAVING FACILITY CONTINUATION AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_dusk_delay() -> void:
	var source := await _spawn_sequence()
	_join_endo(source)
	source._start_dusk_approaches()
	source._scheduler.advance_ticks(1.25)
	var snapshot := _capture(source)
	var saved := snapshot.get("portable_continuation", {}) as Dictionary
	check(str(saved.get("kind", "")) == "method_delay"
			and str(saved.get("next_method", "")) == "_start_second_iron"
			and is_equal_approx(
				float(saved.get("deadline", -1.0)) - float(saved.get("start_tick", -1.0)),
				4.0),
		"dusk publishes the second iron hand-off with its exact absolute deadline")

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	var deadline := float(saved.get("deadline", -1.0))
	_advance_to_just_before(fresh, deadline)
	check(str(fresh._current_step) == "dusk_approaches",
		"fresh dusk load cannot expose Shelter 1 one tick early")
	fresh._scheduler.advance_ticks(EPSILON + 0.001)
	check(str(fresh._current_step) == "second_iron"
			and fresh._shelter_interactable.is_interaction_enabled(),
		"fresh dusk load exposes Shelter 1 once at the saved endpoint")
	fresh._scheduler.advance_ticks(5.0)
	check(str(fresh._current_step) == "second_iron",
		"discarded dusk callbacks cannot advance the restored story twice")

	await _dispose(source)
	await _dispose(fresh)


func _verify_shelter_and_dawn_chain() -> void:
	var source := await _spawn_sequence()
	_join_endo(source)
	_prepare_party_at_shelter(source)
	source._current_step = "second_iron"
	source._project_leaving_sources()
	source._shelter_interactable.set("active_character", "aster")
	check(bool(source._shelter_interactable.call("_trigger", false)),
		"the exact nearby shelter source commits the continuation fixture")
	source._scheduler.advance_ticks(source.SHELTER_GATE_OPEN_DURATION + 0.001)
	check(str(source._current_step) == "reach_shelter",
		"the real party gate enters the saved pre-rest hand-off")
	source._scheduler.advance_ticks(0.7)
	var snapshot := _capture(source)
	var saved := snapshot.get("portable_continuation", {}) as Dictionary
	check(str(saved.get("kind", "")) == "method_delay"
			and str(saved.get("next_method", "")) == "_start_first_rest"
			and is_equal_approx(
				float(saved.get("deadline", -1.0)) - float(saved.get("start_tick", -1.0)),
				2.5),
		"settled shelter party publishes the exact pre-rest deadline")

	var fresh := await _spawn_sequence()
	fresh.apply_save_snapshot(snapshot)
	check(str(fresh._current_step) == "reach_shelter"
			and not fresh._player.is_move_enabled(),
		"fresh pre-rest load preserves the settled phase and disabled movement")
	var rest_deadline := float(saved.get("deadline", -1.0))
	_advance_to_just_before(fresh, rest_deadline)
	check(str(fresh._shelter_rest_authority_state().get("phase", "")) \
			== fresh.SHELTER_REST_PHASE_IDLE,
		"fresh pre-rest load cannot charge ATP or skip night one tick early")
	fresh._scheduler.advance_ticks(EPSILON + 0.001)
	var pending: Dictionary = fresh._shelter_rest_authority_state()
	check(str(pending.get("phase", "")) == fresh.SHELTER_REST_PHASE_DAWN_PENDING
			and bool(pending.get("cost_applied", false)),
		"saved pre-rest endpoint commits one canonical party rest")

	var dawn_deadline := float(pending.get("dawn_deadline", -1.0))
	_advance_to_just_before(fresh, dawn_deadline)
	check(str(fresh._current_step) == "first_rest",
		"paid shelter future cannot start dawn dialogue early")
	fresh._scheduler.advance_ticks(EPSILON + 0.001)
	var dawn_record: Dictionary = fresh._portable_continuation
	check(str(fresh._current_step) == "dawn"
			and str(dawn_record.get("kind", "")) == "dialogue_chain"
			and str(dawn_record.get("next_method", "")) == "_complete_facility_sequence",
		"dawn completion is owned by a saved named dialogue continuation")

	var dawn_snapshot := _capture(fresh)
	var dawn_fresh := await _spawn_sequence()
	dawn_fresh.apply_save_snapshot(dawn_snapshot)
	check(str(dawn_fresh._current_step) == "dawn"
			and dawn_fresh._dialogue.is_active(),
		"fresh dawn load restores its active line before completion")
	dawn_fresh._dialogue.emit_signal("dialogue_finished")
	dawn_fresh._scheduler.advance_ticks(0.002)
	check(str(dawn_fresh._current_step) == "complete",
		"restored dawn line reaches complete exactly once")
	dawn_fresh._scheduler.advance_ticks(2.0)
	check(str(dawn_fresh._current_step) == "complete",
		"restored dawn completion leaves no duplicate future")

	await _dispose(source)
	await _dispose(fresh)
	await _dispose(dawn_fresh)


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
	sequence._dialogue.clear()
	sequence._cancel_portable_continuation()


func _prepare_party_at_shelter(sequence: Node) -> void:
	var offsets := {
		"aster": Vector3(-0.6, 0.0, 0.0),
		"peris": Vector3(0.6, 0.0, 0.6),
		"endo": Vector3(0.6, 0.0, -0.6),
	}
	for char_id in sequence.PARTY_IDS:
		if sequence._game_state.is_downed(char_id):
			sequence._game_state.restore_character(char_id)
		sequence.set_preview_character_position(
			char_id, sequence.SHELTER_POS + offsets[char_id])
		sequence._game_state.set_stat(char_id, "hp", GameState.HP_MAX)
		sequence._game_state.set_stat(char_id, "stamina", GameState.STAMINA_MAX)
		sequence._game_state.set_stat(char_id, "atp", 8.0)


func _advance_to_just_before(sequence: Node, deadline: float) -> void:
	var remaining := deadline - float(sequence._scheduler.get_current_tick())
	sequence._scheduler.advance_ticks(maxf(0.0, remaining - EPSILON))


func _capture(sequence: Node) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(sequence.build_save_snapshot()))
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
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
