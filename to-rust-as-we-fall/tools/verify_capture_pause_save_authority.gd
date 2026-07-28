extends SceneTree

## Engram captures autosave while their modal capture pause is active. Exercise the same
## SaveManager.build_save_payload -> TutorialSequence.apply_save_snapshot seam to prove that the
## modal pause is excluded from persistence without erasing a real pre-existing gameplay pause.

const TutorialSequenceScript := preload("res://scripts/tutorial/tutorial_sequence.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	check(save_manager != null, "SaveManager autoload is available")
	if save_manager == null:
		_finish()
		return

	_verify_transient_capture_pause(save_manager)
	_verify_genuine_gameplay_pause(save_manager)
	_finish()


func _verify_transient_capture_pause(save_manager: Node) -> void:
	var source: Node = _make_sequence()
	source._scheduler.advance_ticks(12.5)
	# Engram capture and the open overlay can nest the same modal pause contract.
	source.set_capture_pause(true)
	source.set_capture_pause(true)
	check(source._scheduler.is_paused(), "capture modal pauses the live gameplay scheduler")

	var payload: Dictionary = _json_round_trip(
		save_manager.build_save_payload(source, "capture")
	)
	var saved_scheduler: Dictionary = payload.get("scene_state", {}).get("scheduler", {})
	check(not bool(saved_scheduler.get("paused", true)),
		"capture autosave excludes transient modal pause")
	check(is_equal_approx(float(saved_scheduler.get("current_tick", -1.0)), 12.5),
		"capture autosave preserves the exact gameplay clock")
	check(source._scheduler.is_paused(),
		"snapshot normalization does not unpause the live capture")

	var loaded: Node = _make_sequence()
	loaded.apply_save_snapshot(payload.get("scene_state", {}))
	check(not loaded._scheduler.is_paused(),
		"capture autosave reloads with gameplay running")
	loaded._scheduler.advance_ticks(0.5)
	check(is_equal_approx(loaded._scheduler.get_current_tick(), 13.0),
		"capture-loaded scheduler can advance immediately")

	source.set_capture_pause(false)
	check(source._scheduler.is_paused(), "inner capture release keeps the outer modal pause")
	source.set_capture_pause(false)
	check(not source._scheduler.is_paused(), "outer capture release restores live gameplay")
	source.free()
	loaded.free()


func _verify_genuine_gameplay_pause(save_manager: Node) -> void:
	var source: Node = _make_sequence()
	source._scheduler.advance_ticks(4.0)
	source._scheduler.pause()
	source.set_capture_pause(true)
	var payload: Dictionary = _json_round_trip(
		save_manager.build_save_payload(source, "capture")
	)
	var saved_scheduler: Dictionary = payload.get("scene_state", {}).get("scheduler", {})
	check(bool(saved_scheduler.get("paused", false)),
		"capture autosave preserves a genuine pre-existing gameplay pause")

	var loaded: Node = _make_sequence()
	loaded.apply_save_snapshot(payload.get("scene_state", {}))
	check(loaded._scheduler.is_paused(), "genuine gameplay pause round-trips through load")
	loaded._scheduler.advance_ticks(1.0)
	check(is_equal_approx(loaded._scheduler.get_current_tick(), 4.0),
		"loaded gameplay pause still blocks authoritative time")
	loaded._scheduler.resume()
	loaded._scheduler.advance_ticks(1.0)
	check(is_equal_approx(loaded._scheduler.get_current_tick(), 5.0),
		"loaded gameplay pause remains explicitly resumable")

	source.set_capture_pause(false)
	check(source._scheduler.is_paused(),
		"closing capture does not erase the source gameplay pause")
	source.free()
	loaded.free()


func _make_sequence() -> Node:
	var sequence: Node = TutorialSequenceScript.new()
	sequence._scheduler = EventScheduler.new()
	sequence._game_state = GameState.new()
	sequence._game_state.scheduler = sequence._scheduler
	return sequence


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("CAPTURE PAUSE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
