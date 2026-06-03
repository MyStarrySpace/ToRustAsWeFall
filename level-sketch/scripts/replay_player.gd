extends Control

## Replay viewer: pick a generated stretch, watch the party execute a solution on the
## grid, scrub the timeline, and flip between the full-party (spotlight) and Aster+Peris
## (shadow) solutions to see the same level solved two different ways. Self-contained —
## builds its own world/camera/UI and reads the bundled res://samples/*.json replays.

const CONTROLS_BAR := 132.0  # reserve room so the level frames clear of the top/bottom panels

var _world: Node2D
var _camera: CameraRig
var _view: ReplayView

var _data := ReplayData.new()
var _samples: Array = []
var _solution_index := 0
var _time := 0.0
var _playing := false
var _duration := 0.0

var _sample_picker: OptionButton
var _solution_bar: HBoxContainer
var _solution_group := ButtonGroup.new()
var _play_btn: Button
var _scrub: HSlider
var _caption: Label
var _time_label: Label
var _title_label: Label
var _suppress_scrub := false

# Touch / mouse camera state.
var _touches: Dictionary = {}
var _pan_last := Vector2.ZERO
var _pan_valid := false
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_world()
	_build_ui()
	_samples = ReplayData.list_samples()
	_populate_samples()
	if not _samples.is_empty():
		_load_sample(0)
	if "--shot" in OS.get_cmdline_user_args():
		_capture_preview()


# DEV-ONLY preview capture (run the replay scene with `-- --shot`): seek partway into
# the first solution and save a screenshot so the renderer can be eyeballed.
func _capture_preview() -> void:
	_time = _duration * 0.55
	_sync(false)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://replay_preview.png")
	get_tree().quit()


func _process(delta: float) -> void:
	if _playing and _duration > 0.0:
		_time = minf(_time + delta, _duration)
		_sync(true)
		if _time >= _duration:
			_playing = false
			_play_btn.text = "▶  Play"


# ------------------------------------------------------------------- World setup

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "ReplayWorld"
	add_child(_world)
	_view = ReplayView.new()
	_view.name = "ReplayView"
	_world.add_child(_view)
	_camera = CameraRig.new()
	_camera.name = "ReplayCamera"
	_world.add_child(_camera)
	_camera.make_current()


# --------------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReplayUI"
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# Top bar: sample picker, title, solution toggles, back-to-editor.
	var top := _panel(ui)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 6
	top.offset_bottom = 98
	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 6)
	top.add_child(top_v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top_v.add_child(row)
	_sample_picker = OptionButton.new()
	_sample_picker.custom_minimum_size = Vector2(280, 0)
	_sample_picker.item_selected.connect(_on_sample_selected)
	row.add_child(_sample_picker)
	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.88, 0.95))
	row.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_button(row, "Recenter", _fit_camera)
	_button(row, "◂ Editor", func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

	# Solution toggles (spotlight / shadow), filled in per loaded replay.
	_solution_bar = HBoxContainer.new()
	_solution_bar.add_theme_constant_override("separation", 6)
	top_v.add_child(_solution_bar)

	# Bottom bar: caption + transport + scrub.
	var bottom := _panel(ui)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_top = -118
	bottom.offset_bottom = -10
	var bottom_v := VBoxContainer.new()
	bottom_v.add_theme_constant_override("separation", 6)
	bottom.add_child(bottom_v)
	_caption = Label.new()
	_caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.6))
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_v.add_child(_caption)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	bottom_v.add_child(transport)
	_play_btn = _button(transport, "▶  Play", _toggle_play)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.01
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.custom_minimum_size = Vector2(0, 36)
	_scrub.value_changed.connect(_on_scrub_changed)
	transport.add_child(_scrub)
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(96, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.84))
	transport.add_child(_time_label)


func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.92)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ Sample load

func _populate_samples() -> void:
	_sample_picker.clear()
	for s in _samples:
		var tier := str(s.get("tier", ""))
		var label := str(s.get("title", s.get("id", "")))
		if tier != "":
			label = "%s  ·  %s" % [label, tier]
		_sample_picker.add_item(label)


func _on_sample_selected(index: int) -> void:
	_load_sample(index)


func _load_sample(index: int) -> void:
	if index < 0 or index >= _samples.size():
		return
	if not _data.load_path(str(_samples[index].get("path", ""))):
		return
	_sample_picker.selected = index
	_view.set_replay(_data)
	_title_label.text = _data.region()
	_build_solution_toggles()
	_solution_index = 0
	_view.set_solution_index(0)
	_duration = _data.duration(0)
	_time = 0.0
	_playing = false
	_play_btn.text = "▶  Play"
	_scrub.max_value = maxf(0.001, _duration)
	_fit_camera()
	_sync(false)


func _build_solution_toggles() -> void:
	for child in _solution_bar.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "Solve as:"
	label.add_theme_color_override("font_color", Color(0.66, 0.74, 0.8))
	_solution_bar.add_child(label)
	var solutions := _data.solutions()
	for i in range(solutions.size()):
		var s: Dictionary = solutions[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _solution_group
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(s.get("label", "Solution %d" % i))
		if not bool(s.get("solvable", false)):
			b.text += "  (blocked)"
		b.button_pressed = i == 0
		b.pressed.connect(_on_solution_selected.bind(i))
		_solution_bar.add_child(b)


func _on_solution_selected(index: int) -> void:
	_solution_index = index
	_view.set_solution_index(index)
	_duration = _data.duration(index)
	_scrub.max_value = maxf(0.001, _duration)
	_time = minf(_time, _duration)
	_sync(false)


# --------------------------------------------------------------------- Transport

func _toggle_play() -> void:
	if _duration <= 0.0:
		return
	if not _playing and _time >= _duration:
		_time = 0.0
	_playing = not _playing
	_play_btn.text = "❚❚  Pause" if _playing else "▶  Play"


func _on_scrub_changed(value: float) -> void:
	if _suppress_scrub:
		return
	_time = clampf(value, 0.0, _duration)
	_playing = false
	_play_btn.text = "▶  Play"
	_sync(false)


func _sync(update_scrub: bool) -> void:
	_view.set_time(_time)
	if update_scrub:
		_suppress_scrub = true
		_scrub.value = _time
		_suppress_scrub = false
	var frame := _data.frame_at(_solution_index, _time)
	_caption.text = str(frame.get("caption", ""))
	# A genuinely later-stage (stage-ahead) mastery move reads in violet; a same-stage
	# expert move reads in teal; ordinary beats stay gold.
	var color := Color(0.92, 0.86, 0.6)
	if bool(frame.get("stage_ahead", false)):
		color = Color(0.80, 0.66, 0.96)
	elif bool(frame.get("expert", false)):
		color = Color(0.55, 0.82, 0.85)
	_caption.add_theme_color_override("font_color", color)
	_time_label.text = "%4.1f / %4.1f" % [_time, _duration]


func _fit_camera() -> void:
	if _view == null:
		return
	var size := _view.level_size()
	var vp := get_viewport_rect().size
	vp.y = maxf(1.0, vp.y - CONTROLS_BAR * 2.0)
	var zx := vp.x / maxf(1.0, size.x)
	var zy := vp.y / maxf(1.0, size.y)
	var z := clampf(minf(zx, zy) * 0.92, CameraRig.ZOOM_MIN, CameraRig.ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	_camera.global_position = _view.level_center()


# ------------------------------------------------------------------------- Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pan_valid = false
		_pinch_dist = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_update_camera_gesture()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_at(event.position, 1.0 / 1.1)


func _update_camera_gesture() -> void:
	if _touches.size() == 1:
		var p: Vector2 = _touches.values()[0]
		if _pan_valid:
			_camera.pan_screen(p - _pan_last)
		_pan_last = p
		_pan_valid = true
	elif _touches.size() >= 2:
		var keys := _touches.keys()
		var a: Vector2 = _touches[keys[0]]
		var b: Vector2 = _touches[keys[1]]
		var mid := (a + b) * 0.5
		var dist := a.distance_to(b)
		if _pinch_dist > 0.0:
			if dist > 0.0:
				_camera.zoom_at(mid, dist / _pinch_dist)
			_camera.pan_screen(mid - _pinch_mid)
		_pinch_mid = mid
		_pinch_dist = dist
		_pan_valid = false
