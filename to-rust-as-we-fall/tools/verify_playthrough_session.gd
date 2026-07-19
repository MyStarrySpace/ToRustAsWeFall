extends Node

var _failures := 0

class TapeReceiver extends Node:
	var game_state: GameState

	func _input(event: InputEvent) -> void:
		if game_state != null and event is InputEventKey and event.pressed \
				and (event as InputEventKey).physical_keycode == KEY_Q:
			game_state.set_world_state("tape_received", true)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var session := PlaythroughSession.new()
	add_child(session)
	await get_tree().process_frame

	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.pressed = true
	key.shift_pressed = true
	var decoded_key := session.decode_input_event(session.encode_input_event(key)) as InputEventKey
	_check(decoded_key != null and decoded_key.physical_keycode == KEY_Q and decoded_key.pressed,
		"keyboard input round-trips")
	_check(decoded_key != null and decoded_key.shift_pressed, "input modifiers round-trip")

	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	mouse.position = Vector2(320.0, 180.0)
	var decoded_mouse := session.decode_input_event(session.encode_input_event(mouse)) as InputEventMouseButton
	_check(decoded_mouse != null and decoded_mouse.button_index == MOUSE_BUTTON_RIGHT,
		"mouse button input round-trips")
	_check(decoded_mouse != null and decoded_mouse.position.distance_to(mouse.position) < 0.01,
		"normalized pointer coordinates round-trip")

	var artifact_path := "user://verify_playthrough_session.trwfplay"
	_check(session.begin_recording(artifact_path), "recording starts")
	session.set_process(false)
	var scheduler := EventScheduler.new()
	var game_state := GameState.new()
	game_state.scheduler = scheduler
	var receiver := TapeReceiver.new()
	receiver.game_state = game_state
	add_child(receiver)
	session.attach_game_state(game_state, "res://tools/verify_playthrough_session.gd")
	game_state.register_character("aster", Vector3.ZERO)
	scheduler.advance_ticks(1.25)
	Input.parse_input_event(key)
	await get_tree().process_frame
	session.stop_recording(false)
	var file := FileAccess.open(artifact_path, FileAccess.READ)
	var artifact: Variant = bytes_to_var(file.get_buffer(file.get_length())) if file != null else null
	if file != null:
		file.close()
	_check(artifact is Dictionary and str(artifact.get("contract", "")) == PlaythroughSession.CONTRACT,
		"artifact contract is written")
	_check(artifact is Dictionary and (artifact.get("segments", []) as Array).size() == 1,
		"authoritative GameState segment is embedded")
	if artifact is Dictionary and not (artifact.get("segments", []) as Array).is_empty():
		var segment: Dictionary = (artifact.get("segments", []) as Array)[0]
		var log := EventLog.from_bytes(segment.get("event_log", PackedByteArray()))
		_check(log.size() == 2 and log.recorded_until >= 1.25,
			"segment contains setup, replayed command, and exact tail tick")

	var playback := PlaythroughSession.new()
	add_child(playback)
	await get_tree().process_frame
	playback.set_process(false)
	_check(playback.begin_playback(artifact_path, false), "playback starts")
	var replay_scheduler := EventScheduler.new()
	var replay_state := GameState.new()
	replay_state.scheduler = replay_scheduler
	receiver.game_state = replay_state
	playback.attach_game_state(replay_state, "res://tools/verify_playthrough_session.gd")
	replay_state.register_character("aster", Vector3.ZERO)
	var allowed := playback.constrain_playback_advance(replay_scheduler, 2.0)
	_check(absf(allowed - 1.25) < 0.0001, "fixed-frame playback stops on the exact input tick")
	replay_scheduler.advance_ticks(allowed)
	playback._process(0.0)
	await get_tree().process_frame
	_check(bool(replay_state.get_world_state("tape_received", false)),
		"playback injects the recorded input through the live scene")
	for _i in range(5):
		playback._process(0.0)
	_check(not playback._playback_failed, "authoritative events and final snapshot verify")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(artifact_path))
	print("[PLAYTHROUGH_VERIFY] %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
