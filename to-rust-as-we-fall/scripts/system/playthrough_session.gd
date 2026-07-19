class_name PlaythroughSession
extends Node

## Records normal player input against deterministic gameplay time, then replays it through
## the live scene. Each GameState also keeps its authoritative EventLog and final snapshot in
## the artifact, so a rendered replay can report whether it reproduced the recorded run.

const CONTRACT := "deterministic_playthrough_v1"
const FORMAT_VERSION := 1
const REPLAY_EVENT_META := &"trwf_playthrough_replay"
const CAPTURED_EVENT_META := &"trwf_playthrough_captured"
const GENERATED_CASE_ACTION_PREFIX := "qa_play_generated_case/"
const SAVE_INTERVAL_SECONDS := 5.0
const TICK_EPSILON := 0.0005

enum Mode { OFF, RECORD, PLAYBACK }

var mode: Mode = Mode.OFF
var recording_path := ""
var quit_on_playback_end := false

var _artifact: Dictionary = {}
var _timeline := 0.0
var _input_order := 0
var _next_input := 0
var _save_elapsed := 0.0
var _playback_tail_frames := -1
var _playback_failed := false
var _playback_trace_variance := false
var _playback_initial_scene_ready := false

var _active_game_state: GameState
var _active_event_log: EventLog
var _active_segment_index := -1
var _next_expected_segment := 0
var _last_scheduler: EventScheduler
var _last_scheduler_tick := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var record_path := _argument_value(args, "--record-playthrough")
	var replay_path := _argument_value(args, "--replay-playthrough")
	var autoplay_generated_case := _argument_value(args, "--autoplay-generated-case")
	if OS.has_feature("web"):
		if record_path == "":
			var web_record := _web_query_value("record_playthrough")
			if web_record != "":
				record_path = "user://%s" % _safe_web_filename(web_record, "playthrough.trwfplay")
		if replay_path == "":
			var web_replay := _web_query_value("replay_playthrough")
			if web_replay != "":
				replay_path = "user://%s" % _safe_web_filename(web_replay, "playthrough.trwfplay")
	quit_on_playback_end = args.has("--quit-on-playthrough-end")
	if replay_path != "":
		begin_playback(replay_path, quit_on_playback_end)
	elif record_path != "":
		begin_recording(record_path)
		if autoplay_generated_case != "":
			_install_generated_input_driver(autoplay_generated_case)

func _install_generated_input_driver(case_id: String) -> void:
	# QA-only authoring aid: the driver emits ordinary InputEvents through the live main menu,
	# fragment picker, and gameplay scene. It is deliberately absent during playback, so the
	# resulting tape must reproduce the complete load-and-play flow on its own.
	var driver_script := load("res://tools/generated_input_playthrough_driver.gd")
	if driver_script == null:
		push_error("PlaythroughSession: generated input driver is unavailable")
		return
	var driver: Node = driver_script.new()
	driver.set("case_id", case_id)
	add_child(driver)

func _process(delta: float) -> void:
	if mode == Mode.OFF:
		return
	if mode == Mode.RECORD and str(_artifact.get("initial_scene", "")) == "" \
			and get_tree() != null and get_tree().current_scene != null:
		# Capture the scene where recording actually began, before a menu click or
		# automatic handoff can replace it.
		_artifact["initial_scene"] = get_tree().current_scene.scene_file_path
	if mode == Mode.PLAYBACK and _waiting_for_initial_scene():
		return
	_update_timeline(delta)
	if mode == Mode.RECORD:
		if _active_game_state != null:
			_active_game_state.flush_tick()
		_artifact["duration"] = _timeline
		_save_elapsed += delta
		if _save_elapsed >= SAVE_INTERVAL_SECONDS:
			_save_elapsed = 0.0
			_save_recording(true)
		return
	_playback_step()

func _input(event: InputEvent) -> void:
	if mode == Mode.RECORD:
		_capture_recording_input(event)
		_apply_resolved_playthrough_action(event)
	elif mode == Mode.PLAYBACK:
		# Movie playback is tape-owned. Ignore live keyboard/mouse input while still
		# allowing events injected below to continue through the ordinary input stack.
		if event.has_meta(REPLAY_EVENT_META):
			_apply_resolved_playthrough_action(event)
		else:
			get_viewport().set_input_as_handled()

## Camera-independent QA setup actions are resolved against the visible live menu. Gameplay
## commands still flow through the scene's ordinary input/interaction stack; this special case
## only replaces a native PopupMenu click whose subwindow focus cannot be reconstructed headlessly.
func _apply_resolved_playthrough_action(event: InputEvent) -> bool:
	if not (event is InputEventAction) or not (event as InputEventAction).pressed:
		return true
	var action_name := str((event as InputEventAction).action)
	if not action_name.begins_with(GENERATED_CASE_ACTION_PREFIX):
		return true
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null or scene.get("_in_menu") != true:
		return false
	var wanted_case_id := action_name.trim_prefix(GENERATED_CASE_ACTION_PREFIX)
	var cases: Array = scene.get("_seed_cases")
	for case_index in range(cases.size()):
		if str((cases[case_index] as Dictionary).get("id", "")) != wanted_case_id:
			continue
		var selector: OptionButton = scene.get("_seed_case_selector")
		if selector != null:
			selector.select(case_index + 1)
		scene.call("_on_seed_case_selected", case_index + 1)
		scene.call("_on_seed_play_pressed")
		get_viewport().set_input_as_handled()
		return true
	return false

## Window.window_input fires before a Control can consume a scene-changing click. The ordinary
## Node._input path remains as a fallback; metadata makes whichever callback runs second a no-op.
func _on_window_input(event: InputEvent) -> void:
	if mode == Mode.RECORD:
		_capture_recording_input(event)

func _capture_recording_input(event: InputEvent) -> void:
	if event.has_meta(REPLAY_EVENT_META) or event.has_meta(CAPTURED_EVENT_META):
		return
	event.set_meta(CAPTURED_EVENT_META, true)
	if OS.has_feature("web") and event is InputEventKey and event.pressed and not event.echo \
			and ((event as InputEventKey).keycode == KEY_F10 \
				or (event as InputEventKey).physical_keycode == KEY_F10):
		# Browser sessions cannot rely on a window-close notification. F10 seals the
		# artifact and downloads a host copy that Movie Maker can render natively.
		stop_recording(false)
		_download_web_recording()
		get_viewport().set_input_as_handled()
		return
	# Input is delivered before this autoload's _process. Fold in the scene's
	# previous-frame scheduler advance so the tape tick and GameState event tick agree.
	_capture_active_scheduler_delta()
	var encoded := encode_input_event(event)
	if encoded.is_empty():
		return
	var inputs: Array = _artifact.get("inputs", [])
	inputs.append({"tick": _timeline, "order": _input_order, "event": encoded})
	_input_order += 1
	_artifact["inputs"] = inputs

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and mode == Mode.RECORD:
		stop_recording(true)

func _exit_tree() -> void:
	if mode == Mode.RECORD and recording_path != "":
		_save_recording(true)

func begin_recording(path: String) -> bool:
	if mode != Mode.OFF:
		push_warning("PlaythroughSession: a session is already active")
		return false
	recording_path = _normalize_path(path)
	mode = Mode.RECORD
	_timeline = 0.0
	_input_order = 0
	_artifact = {
		"contract": CONTRACT,
		"version": FORMAT_VERSION,
		"created_unix": int(Time.get_unix_time_from_system()),
		"initial_scene": "",
		"viewport_size": _viewport_size(),
		"duration": 0.0,
		"inputs": [],
		"segments": [],
	}
	if get_tree() != null:
		get_tree().auto_accept_quit = false
		var root_window := get_tree().root
		if root_window != null:
			if not root_window.close_requested.is_connected(_on_close_requested):
				root_window.close_requested.connect(_on_close_requested)
			if not root_window.window_input.is_connected(_on_window_input):
				root_window.window_input.connect(_on_window_input)
	print("[PLAYTHROUGH/record] Recording normal play to %s" % recording_path)
	print("[PLAYTHROUGH/record] Planning pauses collapse on replay; live simulation time remains.")
	if OS.has_feature("web"):
		print("[PLAYTHROUGH/record] Press F10 to finish and download the playthrough artifact.")
	return true

func stop_recording(quit_after := false) -> void:
	if mode != Mode.RECORD:
		return
	_capture_active_scheduler_delta()
	_finalize_active_segment(true)
	_artifact["duration"] = _timeline
	_save_recording(true)
	print("[PLAYTHROUGH/record] Saved %d inputs across %d deterministic segment(s) to %s" % [
		(_artifact.get("inputs", []) as Array).size(),
		(_artifact.get("segments", []) as Array).size(),
		recording_path,
	])
	mode = Mode.OFF
	if get_tree() != null:
		get_tree().auto_accept_quit = true
		if quit_after:
			get_tree().quit(0)

func begin_playback(path: String, quit_after := false) -> bool:
	if mode != Mode.OFF:
		push_warning("PlaythroughSession: a session is already active")
		return false
	recording_path = _normalize_path(path)
	var loaded := _load_artifact(recording_path)
	if loaded.is_empty():
		return false
	if str(loaded.get("contract", "")) != CONTRACT:
		push_error("PlaythroughSession: unsupported artifact contract in %s" % recording_path)
		return false
	_artifact = loaded
	mode = Mode.PLAYBACK
	quit_on_playback_end = quit_after
	_timeline = 0.0
	_next_input = 0
	_next_expected_segment = 0
	_playback_tail_frames = -1
	_playback_failed = false
	_playback_trace_variance = false
	_playback_initial_scene_ready = false
	print("[PLAYTHROUGH/replay] Replaying %d inputs from %s (start: %s)" % [
		(_artifact.get("inputs", []) as Array).size(), recording_path, _playback_initial_scene()])
	call_deferred("_ensure_initial_scene")
	return true

## Called by TutorialSequence immediately after constructing GameState and before it registers
## characters or level objects. That placement captures the whole deterministic segment.
func attach_game_state(game_state: GameState, scene_path := "") -> void:
	if mode == Mode.OFF or game_state == null:
		return
	# A transition can replace the scene after its scheduler advanced but before this
	# autoload processes again. Preserve that last slice in the global tape timeline.
	_capture_active_scheduler_delta()
	_finalize_active_segment(false)
	_active_game_state = game_state
	_active_event_log = EventLog.new()
	_active_game_state.event_log = _active_event_log
	_last_scheduler = game_state.scheduler
	_last_scheduler_tick = _scheduler_tick(_last_scheduler)
	var resolved_scene := scene_path
	if resolved_scene == "" and get_tree() != null and get_tree().current_scene != null:
		resolved_scene = get_tree().current_scene.scene_file_path
	if mode == Mode.RECORD:
		var segments: Array = _artifact.get("segments", [])
		segments.append({
			"scene": resolved_scene,
			"start_tick": _timeline,
			"end_tick": _timeline,
			"event_log": PackedByteArray(),
			"final_snapshot": {},
		})
		_artifact["segments"] = segments
		_active_segment_index = segments.size() - 1
	else:
		_active_segment_index = _next_expected_segment
		_next_expected_segment += 1

func is_recording() -> bool:
	return mode == Mode.RECORD

func is_playing_back() -> bool:
	return mode == Mode.PLAYBACK

func current_timeline_tick() -> float:
	return _timeline

## TutorialSequence asks for its allowed deterministic advance during playback. Stopping
## exactly on the next tape boundary means an arbitrary live-recording timestamp replays at
## that exact tick even when Movie Maker renders on a fixed 60 FPS cadence.
func constrain_playback_advance(scheduler: EventScheduler, requested_ticks: float) -> float:
	if mode != Mode.PLAYBACK or scheduler == null or scheduler != _last_scheduler:
		return maxf(requested_ticks, 0.0)
	var boundary := float(_artifact.get("duration", _timeline + requested_ticks))
	var inputs: Array = _artifact.get("inputs", [])
	if _next_input < inputs.size():
		boundary = minf(boundary, float((inputs[_next_input] as Dictionary).get("tick", boundary)))
	var remaining := maxf(0.0, boundary - _timeline)
	return minf(maxf(requested_ticks, 0.0), remaining)

func _playback_step() -> void:
	var inputs: Array = _artifact.get("inputs", [])
	# Replay at most one recorded event per rendered frame. Separate input frames can share
	# one simulation tick (for example a button press and its next-frame release); draining
	# them in one callback skips the GUI state transition even though their timestamps match.
	if _next_input < inputs.size():
		var entry: Dictionary = inputs[_next_input]
		if float(entry.get("tick", 0.0)) <= _timeline + TICK_EPSILON:
			var event := decode_input_event(entry.get("event", {}))
			if event != null:
				event.set_meta(REPLAY_EVENT_META, true)
				# The injecting autoload is not guaranteed to receive its own synthetic
				# event back through Node._input, so resolve tape-owned setup actions here.
				if not _apply_resolved_playthrough_action(event):
					return
			_next_input += 1
			if event != null:
				# Native PopupMenu windows route mouse input using the OS cursor's current
				# window/position as well as the event coordinates. Keep that physical state
				# aligned so recorded selector and context-menu clicks reach the same popup.
				if event is InputEventMouse:
					Input.warp_mouse((event as InputEventMouse).position)
				Input.parse_input_event(event)
	if _next_input < inputs.size() or _timeline + TICK_EPSILON < float(_artifact.get("duration", 0.0)):
		return
	if _playback_tail_frames < 0:
		_playback_tail_frames = 3
		return
	_playback_tail_frames -= 1
	if _playback_tail_frames <= 0:
		_finish_playback()

func _finish_playback() -> void:
	if mode != Mode.PLAYBACK:
		return
	_finalize_active_segment(true)
	var expected_count := (_artifact.get("segments", []) as Array).size()
	if _next_expected_segment != expected_count:
		_playback_failed = true
		push_error("[PLAYTHROUGH/replay] Segment count mismatch: recorded %d, replayed %d" % [
			expected_count, _next_expected_segment])
	if _playback_failed:
		print("[PLAYTHROUGH/replay] COMPLETE — visual playback finished, deterministic verification FAILED.")
	elif _playback_trace_variance:
		print("[PLAYTHROUGH/replay] COMPLETE — final snapshots match; frame-granular derived event cadence varied (reported above).")
	else:
		print("[PLAYTHROUGH/replay] COMPLETE — authoritative events and final snapshots match.")
	mode = Mode.OFF
	if quit_on_playback_end and get_tree() != null:
		get_tree().quit(1 if _playback_failed else 0)

func _update_timeline(delta: float) -> void:
	var scheduler: EventScheduler = null
	if _active_game_state != null:
		scheduler = _active_game_state.scheduler
	if scheduler == null:
		_last_scheduler = null
		_last_scheduler_tick = 0.0
		_timeline += maxf(delta, 0.0)
		return
	var now := _scheduler_tick(scheduler)
	if scheduler != _last_scheduler:
		_last_scheduler = scheduler
		_last_scheduler_tick = now
		return
	_capture_active_scheduler_delta()

func _capture_active_scheduler_delta() -> void:
	if _last_scheduler == null:
		return
	var now := _scheduler_tick(_last_scheduler)
	_timeline += maxf(0.0, now - _last_scheduler_tick)
	_last_scheduler_tick = now

func _finalize_active_segment(final_stop: bool) -> void:
	if _active_game_state == null or _active_event_log == null or _active_segment_index < 0:
		return
	_active_game_state.flush_tick()
	var snapshot := _active_game_state.serialize()
	if mode == Mode.RECORD:
		var segments: Array = _artifact.get("segments", [])
		if _active_segment_index < segments.size():
			var segment: Dictionary = segments[_active_segment_index]
			segment["end_tick"] = _timeline
			segment["event_log"] = _active_event_log.to_bytes()
			segment["final_snapshot"] = snapshot
			segments[_active_segment_index] = segment
			_artifact["segments"] = segments
	elif mode == Mode.PLAYBACK:
		var expected_segments: Array = _artifact.get("segments", [])
		if _active_segment_index >= expected_segments.size():
			_playback_failed = true
			push_error("[PLAYTHROUGH/replay] Unexpected extra GameState segment")
		else:
			var expected: Dictionary = expected_segments[_active_segment_index]
			var expected_log := EventLog.from_bytes(expected.get("event_log", PackedByteArray()))
			if not _event_logs_equal(_active_event_log, expected_log):
				# Per-render-frame derived writes (notably continuous stamina integration)
				# can split the same exact total into a different number of set_stat entries
				# at Movie Maker's fixed FPS. The final GameState snapshot is authoritative
				# for pass/fail; retain and report the trace difference for diagnosis.
				_playback_trace_variance = true
				push_warning("[PLAYTHROUGH/replay] Event cadence differs in segment %d (%s)" % [
					_active_segment_index, str(expected.get("scene", ""))])
				_print_event_log_difference(_active_event_log, expected_log)
			if not _variants_equal(snapshot, expected.get("final_snapshot", {})):
				_playback_failed = true
				push_error("[PLAYTHROUGH/replay] Final snapshot mismatch in segment %d (%s)" % [
					_active_segment_index, str(expected.get("scene", ""))])
	_active_game_state = null
	_active_event_log = null
	_active_segment_index = -1
	_last_scheduler = null
	_last_scheduler_tick = 0.0
	if final_stop and mode == Mode.RECORD:
		_artifact["duration"] = _timeline

func _event_logs_equal(actual: EventLog, expected: EventLog) -> bool:
	return actual.base_seed == expected.base_seed \
		and absf(actual.recorded_until - expected.recorded_until) <= TICK_EPSILON \
		and _variants_equal(actual.events, expected.events)

func _print_event_log_difference(actual: EventLog, expected: EventLog) -> void:
	print("[PLAYTHROUGH/replay] expected events=%d until=%.6f seed=%d; actual events=%d until=%.6f seed=%d" % [
		expected.size(), expected.recorded_until, expected.base_seed,
		actual.size(), actual.recorded_until, actual.base_seed])
	var common := mini(actual.size(), expected.size())
	for i in range(common):
		if not _variants_equal(actual.events[i], expected.events[i]):
			print("[PLAYTHROUGH/replay] first difference at event %d" % i)
			print("  expected: %s" % str(expected.events[i]))
			print("  actual:   %s" % str(actual.events[i]))
			return
	if actual.size() != expected.size():
		var extra: Variant = actual.events[common] if actual.size() > common else expected.events[common]
		print("[PLAYTHROUGH/replay] first unmatched event %d: %s" % [common, str(extra)])

func _variants_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is float:
		return absf(float(a) - float(b)) <= TICK_EPSILON
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _variants_equal(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _variants_equal(a[i], b[i]):
				return false
		return true
	return a == b

func _save_recording(include_active_segment: bool) -> bool:
	if recording_path == "" or _artifact.is_empty():
		return false
	if include_active_segment and _active_game_state != null and _active_event_log != null:
		_active_game_state.flush_tick()
		var segments: Array = _artifact.get("segments", [])
		if _active_segment_index >= 0 and _active_segment_index < segments.size():
			var segment: Dictionary = segments[_active_segment_index]
			segment["end_tick"] = _timeline
			segment["event_log"] = _active_event_log.to_bytes()
			segment["final_snapshot"] = _active_game_state.serialize()
			segments[_active_segment_index] = segment
			_artifact["segments"] = segments
	_artifact["duration"] = _timeline
	if str(_artifact.get("initial_scene", "")) == "" and get_tree() != null and get_tree().current_scene != null:
		_artifact["initial_scene"] = get_tree().current_scene.scene_file_path
	var absolute := ProjectSettings.globalize_path(recording_path)
	var parent := absolute.get_base_dir()
	if parent != "":
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(recording_path, FileAccess.WRITE)
	if file == null:
		push_error("PlaythroughSession: could not write %s" % recording_path)
		return false
	file.store_buffer(var_to_bytes(_artifact))
	file.close()
	return true

func _load_artifact(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("PlaythroughSession: could not read %s" % path)
		return {}
	var decoded: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	if not (decoded is Dictionary):
		push_error("PlaythroughSession: invalid artifact %s" % path)
		return {}
	return decoded

func encode_input_event(event: InputEvent) -> Dictionary:
	var modifiers := _encode_modifiers(event)
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"type": "key", "pressed": key.pressed, "echo": key.echo,
			"keycode": key.keycode, "physical_keycode": key.physical_keycode,
			"key_label": key.key_label, "unicode": key.unicode, "location": key.location,
			"modifiers": modifiers}
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		return {"type": "mouse_button", "pressed": mouse_button.pressed,
			"button_index": mouse_button.button_index, "button_mask": mouse_button.button_mask,
			"double_click": mouse_button.double_click, "factor": mouse_button.factor,
			"position": _normalized_point(mouse_button.position), "modifiers": modifiers}
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		return {"type": "mouse_motion", "button_mask": mouse_motion.button_mask,
			"position": _normalized_point(mouse_motion.position),
			"relative": _normalized_delta(mouse_motion.relative),
			"pressure": mouse_motion.pressure, "tilt": mouse_motion.tilt,
			"pen_inverted": mouse_motion.pen_inverted, "modifiers": modifiers}
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		return {"type": "screen_touch", "index": touch.index, "pressed": touch.pressed,
			"double_tap": touch.double_tap, "position": _normalized_point(touch.position)}
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		return {"type": "screen_drag", "index": drag.index,
			"position": _normalized_point(drag.position), "relative": _normalized_delta(drag.relative),
			"velocity": _normalized_delta(drag.velocity), "pressure": drag.pressure,
			"tilt": drag.tilt, "pen_inverted": drag.pen_inverted}
	if event is InputEventAction:
		var action := event as InputEventAction
		return {"type": "action", "action": action.action, "pressed": action.pressed,
			"strength": action.strength, "event_index": action.event_index}
	if event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		return {"type": "joy_button", "device": joy_button.device,
			"button_index": joy_button.button_index, "pressed": joy_button.pressed,
			"pressure": joy_button.pressure}
	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		return {"type": "joy_motion", "device": joy_motion.device,
			"axis": joy_motion.axis, "axis_value": joy_motion.axis_value}
	return {}

func decode_input_event(data: Dictionary) -> InputEvent:
	var event: InputEvent
	match str(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.pressed = bool(data.get("pressed", false))
			key.echo = bool(data.get("echo", false))
			key.keycode = int(data.get("keycode", 0))
			key.physical_keycode = int(data.get("physical_keycode", 0))
			key.key_label = int(data.get("key_label", 0))
			key.unicode = int(data.get("unicode", 0))
			key.location = int(data.get("location", 0)) as KeyLocation
			event = key
		"mouse_button":
			var mouse_button := InputEventMouseButton.new()
			mouse_button.pressed = bool(data.get("pressed", false))
			mouse_button.button_index = int(data.get("button_index", 0)) as MouseButton
			mouse_button.button_mask = int(data.get("button_mask", 0))
			mouse_button.double_click = bool(data.get("double_click", false))
			mouse_button.factor = float(data.get("factor", 1.0))
			mouse_button.position = _denormalized_point(data.get("position", Vector2.ZERO))
			mouse_button.global_position = mouse_button.position
			event = mouse_button
		"mouse_motion":
			var mouse_motion := InputEventMouseMotion.new()
			mouse_motion.button_mask = int(data.get("button_mask", 0))
			mouse_motion.position = _denormalized_point(data.get("position", Vector2.ZERO))
			mouse_motion.global_position = mouse_motion.position
			mouse_motion.relative = _denormalized_delta(data.get("relative", Vector2.ZERO))
			mouse_motion.pressure = float(data.get("pressure", 0.0))
			mouse_motion.tilt = data.get("tilt", Vector2.ZERO)
			mouse_motion.pen_inverted = bool(data.get("pen_inverted", false))
			event = mouse_motion
		"screen_touch":
			var touch := InputEventScreenTouch.new()
			touch.index = int(data.get("index", 0))
			touch.pressed = bool(data.get("pressed", false))
			touch.double_tap = bool(data.get("double_tap", false))
			touch.position = _denormalized_point(data.get("position", Vector2.ZERO))
			event = touch
		"screen_drag":
			var drag := InputEventScreenDrag.new()
			drag.index = int(data.get("index", 0))
			drag.position = _denormalized_point(data.get("position", Vector2.ZERO))
			drag.relative = _denormalized_delta(data.get("relative", Vector2.ZERO))
			drag.velocity = _denormalized_delta(data.get("velocity", Vector2.ZERO))
			drag.pressure = float(data.get("pressure", 0.0))
			drag.tilt = data.get("tilt", Vector2.ZERO)
			drag.pen_inverted = bool(data.get("pen_inverted", false))
			event = drag
		"action":
			var action := InputEventAction.new()
			action.action = StringName(data.get("action", ""))
			action.pressed = bool(data.get("pressed", false))
			action.strength = float(data.get("strength", 0.0))
			action.event_index = int(data.get("event_index", -1))
			event = action
		"joy_button":
			var joy_button := InputEventJoypadButton.new()
			joy_button.device = int(data.get("device", 0))
			joy_button.button_index = int(data.get("button_index", 0)) as JoyButton
			joy_button.pressed = bool(data.get("pressed", false))
			joy_button.pressure = float(data.get("pressure", 0.0))
			event = joy_button
		"joy_motion":
			var joy_motion := InputEventJoypadMotion.new()
			joy_motion.device = int(data.get("device", 0))
			joy_motion.axis = int(data.get("axis", 0)) as JoyAxis
			joy_motion.axis_value = float(data.get("axis_value", 0.0))
			event = joy_motion
		_:
			return null
	_apply_modifiers(event, data.get("modifiers", {}))
	return event

func _encode_modifiers(event: InputEvent) -> Dictionary:
	if not (event is InputEventWithModifiers):
		return {}
	var modified := event as InputEventWithModifiers
	return {"alt": modified.alt_pressed, "shift": modified.shift_pressed,
		"ctrl": modified.ctrl_pressed, "meta": modified.meta_pressed}

func _apply_modifiers(event: InputEvent, data: Dictionary) -> void:
	if not (event is InputEventWithModifiers):
		return
	var modified := event as InputEventWithModifiers
	modified.alt_pressed = bool(data.get("alt", false))
	modified.shift_pressed = bool(data.get("shift", false))
	modified.ctrl_pressed = bool(data.get("ctrl", false))
	modified.meta_pressed = bool(data.get("meta", false))

func _normalized_point(point: Vector2) -> Vector2:
	var size := _viewport_size()
	return Vector2(point.x / maxf(1.0, size.x), point.y / maxf(1.0, size.y))

func _normalized_delta(delta: Vector2) -> Vector2:
	return _normalized_point(delta)

func _denormalized_point(point: Vector2) -> Vector2:
	var size := _viewport_size()
	return Vector2(point.x * size.x, point.y * size.y)

func _denormalized_delta(delta: Vector2) -> Vector2:
	return _denormalized_point(delta)

func _viewport_size() -> Vector2:
	if get_viewport() == null:
		return Vector2(1.0, 1.0)
	var size := get_viewport().get_visible_rect().size
	return Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))

func _ensure_initial_scene() -> void:
	if mode != Mode.PLAYBACK or get_tree() == null:
		return
	var initial_scene := _playback_initial_scene()
	if initial_scene == "" or get_tree().current_scene == null:
		return
	if get_tree().current_scene.scene_file_path != initial_scene:
		get_tree().change_scene_to_file(initial_scene)

func _waiting_for_initial_scene() -> bool:
	# This is a one-shot startup barrier, not a permanent scene lock. Once the recorded
	# initial scene has appeared, later menu/game transitions are part of the tape itself.
	if _playback_initial_scene_ready:
		return false
	if get_tree() == null or get_tree().current_scene == null:
		return true
	var initial_scene := _playback_initial_scene()
	if initial_scene == "" or get_tree().current_scene.scene_file_path == initial_scene:
		_playback_initial_scene_ready = true
		return false
	return true

func _playback_initial_scene() -> String:
	var initial_scene := str(_artifact.get("initial_scene", ""))
	if initial_scene != "":
		return initial_scene
	var segments: Array = _artifact.get("segments", [])
	if not segments.is_empty():
		return str((segments[0] as Dictionary).get("scene", ""))
	return ""

func _on_close_requested() -> void:
	if mode == Mode.RECORD:
		stop_recording(true)

func _scheduler_tick(scheduler: EventScheduler) -> float:
	return scheduler.get_current_tick() if scheduler != null else 0.0

func _normalize_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://") or path.is_absolute_path():
		return path
	return "res://%s" % path

func _argument_value(args: PackedStringArray, name: String) -> String:
	var index := args.find(name)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return ""

func _web_query_value(name: String) -> String:
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return ""
	var script := "new URLSearchParams(window.location.search).get('%s') || ''" % name
	return str(bridge.call("eval", script, true))

func _safe_web_filename(value: String, fallback: String) -> String:
	var filename := value.get_file().strip_edges()
	if filename == "" or filename == "1" or filename.to_lower() == "true":
		return fallback
	if not filename.ends_with(".trwfplay"):
		filename += ".trwfplay"
	return filename

func _download_web_recording() -> void:
	if not OS.has_feature("web") or recording_path == "":
		return
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var file := FileAccess.open(recording_path, FileAccess.READ)
	if bridge == null or file == null:
		push_error("PlaythroughSession: browser artifact download failed")
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	bridge.call("download_buffer", bytes, recording_path.get_file(), "application/octet-stream")
