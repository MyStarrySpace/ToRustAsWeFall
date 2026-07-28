extends Node

## Focused deterministic recording/playback and autonomous camera-policy verification.
##
## Run this Node-backed verifier through its scene (not `--script`, which expects a
## SceneTree/MainLoop script and will only load this resource before idling):
##   ../Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     res://tools/verify_playthrough_session.tscn

var _failures := 0
var _checks := 0

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
	_check(not session.is_autonomous_input_session(), "manual input ownership is the default")
	var legacy_autonomous := {
		"inputs": [{"event": {
			"type": "action", "action": "qa_world_interaction/legacy_target"
		}}]
	}
	_check(session._resolve_artifact_input_owner(legacy_autonomous) \
			== PlaythroughSession.INPUT_OWNER_GENERATED_AUTOPILOT,
		"legacy autonomous tapes recover their input ownership")
	var explicitly_manual := legacy_autonomous.duplicate(true)
	explicitly_manual["input_owner"] = PlaythroughSession.INPUT_OWNER_MANUAL
	_check(session._resolve_artifact_input_owner(explicitly_manual) \
			== PlaythroughSession.INPUT_OWNER_MANUAL,
		"explicit manual ownership wins over legacy semantic-action inference")
	var legacy_policy := session._resolve_artifact_camera_input_policy(
		legacy_autonomous,
		PlaythroughSession.INPUT_OWNER_GENERATED_AUTOPILOT
	)
	_check(not bool(legacy_policy.get(
		PlaythroughSession.CAMERA_POLICY_AMBIENT_MOUSE_CONTROLS, true
	)), "legacy autonomous tapes derive stable ambient-mouse policy")

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
	_check(session.begin_recording(
		artifact_path, PlaythroughSession.INPUT_OWNER_GENERATED_AUTOPILOT
	), "recording starts")
	_check(session.is_autonomous_input_session(), "autonomous input ownership is active while recording")
	_check(not session.ambient_mouse_camera_controls_enabled(),
		"autonomous recording exposes its persisted stable-camera policy")
	# Freeze recorder process time before awaiting camera readiness; this harness advances only its
	# explicit EventScheduler so the recorded input boundary remains exactly 1.25.
	session.set_process(false)
	var camera_target := Node3D.new()
	add_child(camera_target)
	var camera = preload("res://scripts/ui/game_camera.gd").new()
	camera.target = camera_target
	add_child(camera)
	await get_tree().process_frame
	camera.set_process(false)
	_check(camera.are_mouse_camera_controls_enabled(),
		"manual/off autoload policy retains desktop mouse camera controls")
	camera.sync_playthrough_input_policy(session)
	_check(not camera.are_mouse_camera_controls_enabled(),
		"autonomous recording policy disables desktop mouse camera controls")
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
	_check(camera.are_mouse_camera_controls_enabled(),
		"ending autonomous recording automatically restores mouse camera controls")
	var file := FileAccess.open(artifact_path, FileAccess.READ)
	var artifact: Variant = bytes_to_var(file.get_buffer(file.get_length())) if file != null else null
	if file != null:
		file.close()
	_check(artifact is Dictionary and str(artifact.get("contract", "")) == PlaythroughSession.CONTRACT,
		"artifact contract is written")
	_check(artifact is Dictionary and str(artifact.get("input_owner", "")) \
			== PlaythroughSession.INPUT_OWNER_GENERATED_AUTOPILOT,
		"autonomous input ownership is stored in the artifact")
	var artifact_camera_policy: Dictionary = artifact.get(
		PlaythroughSession.CAMERA_POLICY_KEY, {}
	) if artifact is Dictionary else {}
	_check(not bool(artifact_camera_policy.get(
		PlaythroughSession.CAMERA_POLICY_AMBIENT_MOUSE_CONTROLS, true
	)), "ambient mouse camera policy is stored in the artifact")
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
	_check(playback.is_autonomous_input_session(),
		"autonomous input ownership survives playback loading")
	_check(not playback.ambient_mouse_camera_controls_enabled(),
		"ambient mouse camera policy round-trips into playback")
	camera.sync_playthrough_input_policy(playback)
	_check(not camera.are_mouse_camera_controls_enabled(),
		"autonomous playback reapplies the recorded camera policy")
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
	_check(camera.are_mouse_camera_controls_enabled(),
		"ending autonomous playback automatically restores mouse camera controls")

	camera.enable_free_look()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	camera.call("_unhandled_input", middle)
	_check(camera.get("_panning") == true, "manual camera can begin middle-drag")
	camera.set_mouse_camera_controls_enabled(false)
	_check(not camera.are_mouse_camera_controls_enabled(),
		"autonomous camera policy disables desktop mouse controls")
	_check(camera.get("_panning") == false,
		"entering autonomous policy clears an ambient drag already in progress")
	_check(camera.is_free_look(), "mouse suppression preserves keyboard free-look")
	var zoom_before := float(camera.get("_view_zoom"))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	camera.call("_unhandled_input", wheel)
	_check(absf(float(camera.get("_view_zoom")) - zoom_before) < 0.0001,
		"disabled mouse camera ignores wheel zoom")
	camera.call("_unhandled_input", middle)
	_check(camera.get("_panning") == false, "disabled mouse camera cannot begin drag-pan")
	Input.warp_mouse(Vector2.ZERO)
	await get_tree().process_frame
	var pan_before: Vector3 = camera.get("_pan_offset")
	camera.call("_process", 0.5)
	_check((camera.get("_pan_offset") as Vector3).distance_to(pan_before) < 0.0001,
		"disabled mouse camera ignores edge-scroll cursor position")
	var q_key := InputEventKey.new()
	q_key.physical_keycode = KEY_Q
	q_key.pressed = true
	_check(q_key.is_action("camera_rotate_left"), "Q remains mapped to keyboard camera rotation")
	var yaw_before := float(camera.get("_view_yaw"))
	Input.action_press("camera_rotate_left")
	camera.call("_process", 0.25)
	Input.action_release("camera_rotate_left")
	_check(float(camera.get("_view_yaw")) > yaw_before,
		"mouse suppression leaves Q/E keyboard rotation active")
	camera.set_mouse_camera_controls_enabled(true)
	var manual_zoom_before := float(camera.get("_view_zoom"))
	wheel.set_meta(PlaythroughSession.REPLAY_EVENT_META, true)
	camera.call("_unhandled_input", wheel)
	_check(float(camera.get("_view_zoom")) < manual_zoom_before,
		"explicitly replayed human mouse input remains available under the manual artifact policy")
	Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(artifact_path))
	print("[PLAYTHROUGH_VERIFY] %s (%d checks)" % [
		"PASS" if _failures == 0 else "FAIL (%d)" % _failures,
		_checks,
	])
	get_tree().quit(0 if _failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
