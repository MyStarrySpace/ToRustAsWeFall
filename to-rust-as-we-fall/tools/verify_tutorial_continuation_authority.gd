extends SceneTree

## Focused regression for the base TutorialSequence continuation contract. EventScheduler snapshots
## retain clock policy but deliberately drop Callables, so fades and dialogue chains must carry a
## stable self-method/deadline record through the production save API.

const TutorialSequenceScript := preload("res://scripts/tutorial/tutorial_sequence.gd")
const DIALOGUE_BOX_SCENE := preload("res://scenes/ui/dialogue_box.tscn")


class FakeDialogue:
	extends Node

	signal dialogue_finished()

	var active := false
	var shown: Array[String] = []

	func say(_text: String, _speaker := "", _style := "normal", _wait := false) -> void:
		active = true
		shown.append(_text)

	func finish_line() -> void:
		if not active:
			return
		active = false
		dialogue_finished.emit()

	func is_active() -> bool:
		return active

	func advance_ui_time(_delta_ticks: float) -> void:
		pass

	func clear() -> void:
		active = false
		shown.clear()

	func snapshot_state() -> Dictionary:
		return {"version": 1, "active": active, "shown": shown.duplicate()}

	func restore_state(snapshot: Dictionary) -> bool:
		if int(snapshot.get("version", 0)) != 1:
			clear()
			return false
		active = bool(snapshot.get("active", false))
		shown.assign(snapshot.get("shown", []))
		return true


class ContinuationSequence:
	extends TutorialSequence

	var fade_completions := 0
	var dialogue_completions := 0
	var delayed_completions := 0

	func _ready() -> void:
		# The fixture installs the exact minimal infrastructure below; do not boot a full tutorial scene.
		pass

	func setup_for_test() -> void:
		_scheduler = EventScheduler.new()
		_ui_scheduler = EventScheduler.new()
		_game_state = GameState.new()
		_game_state.scheduler = _scheduler
		_fade_rect = ColorRect.new()
		_dialogue = FakeDialogue.new()
		add_child(_fade_rect)
		add_child(_dialogue)

	func start_fade() -> void:
		_current_step = "portable_fade"
		_fade_from(Color(0.08, 0.12, 0.18, 1.0), 4.0, _finish_test_fade, "test_fade")

	func _finish_test_fade() -> void:
		fade_completions += 1
		_current_step = "after_fade"

	func start_dialogue() -> void:
		_current_step = "portable_dialogue"
		_dialogue_chain(
			["aster_sim.ron.greeting", "aster_sim.ron.name"],
			_finish_test_dialogue,
			1.5
		)

	func _finish_test_dialogue() -> void:
		dialogue_completions += 1
		_current_step = "after_dialogue"

	func start_delayed_method() -> void:
		_current_step = "portable_method_delay"
		_schedule_portable_method(3.0, _finish_test_delay, "test_method_delay")

	func _finish_test_delay() -> void:
		delayed_completions += 1
		_current_step = "after_method_delay"


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	DialogueData.load_dir("res://data/dialogue/en/")
	await _verify_fade_restore()
	await _verify_method_delay_restore()
	await _verify_dialogue_delay_and_line_restore()
	await _verify_dialogue_box_state_round_trip()
	print("TUTORIAL CONTINUATION AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_fade_restore() -> void:
	var source := ContinuationSequence.new()
	source.setup_for_test()
	root.add_child(source)
	source.start_fade()
	source._scheduler.advance_ticks(1.0)
	var snapshot := _json_round_trip(source.build_save_snapshot())
	check(
		str(snapshot.get("portable_continuation", {}).get("kind", "")) == "fade_from",
		"mid-fade save carries a stable continuation record"
	)

	var loaded := ContinuationSequence.new()
	loaded.setup_for_test()
	root.add_child(loaded)
	loaded.start_fade() # discarded fresh-scene callback must not survive the load
	loaded.apply_save_snapshot(snapshot)
	check(
		is_equal_approx(loaded._fade_rect.color.a, 0.75),
		"fresh presenter derives the saved fade progress from the absolute clock"
	)
	loaded._scheduler.advance_ticks(2.999)
	check(loaded.fade_completions == 0, "restored fade cannot finish before its original deadline")
	loaded._scheduler.advance_ticks(0.002)
	check(
		loaded.fade_completions == 1 and loaded._current_step == "after_fade",
		"restored fade invokes its named continuation exactly once"
	)
	loaded._scheduler.advance_ticks(5.0)
	check(loaded.fade_completions == 1, "restored fade leaves no duplicate callback")

	source.queue_free()
	loaded.queue_free()
	await process_frame


func _verify_method_delay_restore() -> void:
	var source := ContinuationSequence.new()
	source.setup_for_test()
	root.add_child(source)
	source.start_delayed_method()
	source._scheduler.advance_ticks(1.0)
	var snapshot := _json_round_trip(source.build_save_snapshot())
	var saved: Dictionary = snapshot.get("portable_continuation", {})
	check(
		str(saved.get("kind", "")) == "method_delay"
			and str(saved.get("next_method", "")) == "_finish_test_delay"
			and is_equal_approx(float(saved.get("deadline", -1.0)), 3.0),
		"linear delayed hand-off saves its named method and absolute deadline"
	)

	var loaded := ContinuationSequence.new()
	loaded.setup_for_test()
	root.add_child(loaded)
	loaded.start_delayed_method() # create a discarded future to prove load cancels it
	loaded.apply_save_snapshot(snapshot)
	loaded._scheduler.advance_ticks(1.999)
	check(loaded.delayed_completions == 0,
		"restored delayed hand-off cannot finish before its saved deadline")
	loaded._scheduler.advance_ticks(0.002)
	check(
		loaded.delayed_completions == 1 and loaded._current_step == "after_method_delay",
		"restored delayed hand-off invokes the named method exactly once"
	)
	loaded._scheduler.advance_ticks(5.0)
	check(loaded.delayed_completions == 1,
		"restored delayed hand-off leaves no discarded or duplicate callback")

	source.queue_free()
	loaded.queue_free()
	await process_frame


func _verify_dialogue_delay_and_line_restore() -> void:
	var source := ContinuationSequence.new()
	source.setup_for_test()
	root.add_child(source)
	source.start_dialogue()
	var source_dialogue := source._dialogue as FakeDialogue
	check(source_dialogue.active, "source dialogue chain presents its first line")
	source_dialogue.finish_line()
	source._scheduler.advance_ticks(0.5)
	var delay_snapshot := _json_round_trip(source.build_save_snapshot())
	check(
		str(delay_snapshot.get("portable_continuation", {}).get("phase", "")) == "delay",
		"inter-line delay is explicit portable authority"
	)

	var loaded_delay := ContinuationSequence.new()
	loaded_delay.setup_for_test()
	root.add_child(loaded_delay)
	loaded_delay.start_dialogue()
	loaded_delay.apply_save_snapshot(delay_snapshot)
	var loaded_dialogue := loaded_delay._dialogue as FakeDialogue
	loaded_delay._scheduler.advance_ticks(0.999)
	check(not loaded_dialogue.active, "loaded chain preserves the remaining inter-line delay")
	loaded_delay._scheduler.advance_ticks(0.002)
	check(loaded_dialogue.active, "loaded chain presents the next line at the saved deadline")
	var line_snapshot := _json_round_trip(loaded_delay.build_save_snapshot())

	var loaded_line := ContinuationSequence.new()
	loaded_line.setup_for_test()
	root.add_child(loaded_line)
	loaded_line.apply_save_snapshot(line_snapshot)
	var restored_dialogue := loaded_line._dialogue as FakeDialogue
	check(restored_dialogue.active, "fresh load restores the active dialogue line")
	restored_dialogue.finish_line()
	loaded_line._scheduler.advance_ticks(0.002)
	check(
		loaded_line.dialogue_completions == 1 and loaded_line._current_step == "after_dialogue",
		"the restored line still reaches its one named story continuation"
	)
	loaded_line._scheduler.advance_ticks(5.0)
	check(loaded_line.dialogue_completions == 1, "restored dialogue completion cannot fire twice")

	source.queue_free()
	loaded_delay.queue_free()
	loaded_line.queue_free()
	await process_frame


func _verify_dialogue_box_state_round_trip() -> void:
	var source = DIALOGUE_BOX_SCENE.instantiate()
	root.add_child(source)
	await process_frame
	source.say("A portable line that is still being typed.", "Tester", "data", true)
	source.advance_ui_time(0.25)
	var snapshot: Dictionary = _json_round_trip(source.snapshot_state())
	var displayed_before := float(snapshot.get("displayed_chars", -1.0))

	var loaded = DIALOGUE_BOX_SCENE.instantiate()
	root.add_child(loaded)
	await process_frame
	check(loaded.restore_state(snapshot), "dialogue box accepts its versioned state")
	var restored: Dictionary = loaded.snapshot_state()
	check(
		bool(restored.get("active", false))
			and str(restored.get("current_text", "")) == str(snapshot.get("current_text", ""))
			and is_equal_approx(float(restored.get("displayed_chars", -2.0)), displayed_before),
		"dialogue box preserves the exact active line and typewriter position"
	)

	source.queue_free()
	loaded.queue_free()
	await process_frame


func _json_round_trip(snapshot: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
