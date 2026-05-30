extends CanvasLayer

## Esc-toggled pause menu. Pause view: Resume / Settings. Settings view holds the
## accessibility options (text speed today, room to grow). Self-contained: it
## listens for ui_cancel even while the tree is paused, pauses gameplay while
## open, and reads/writes the Settings autoload. Drop one into any scene.

signal opened()
signal closed()

# Mirrors GameSettings.TextSpeed order (SLOW, NORMAL, FAST, INSTANT).
const SPEED_LABELS := ["Slow", "Normal", "Fast", "Instant"]

var _dim: ColorRect
var _pause_view: Control
var _settings_view: Control
var _speed_buttons: Array[Button] = []
var _is_open := false

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_pause_view = _build_pause_view()
	add_child(_pause_view)

	_settings_view = _build_settings_view()
	_settings_view.visible = false
	add_child(_settings_view)

func _build_pause_view() -> Control:
	var view := _make_view("Paused")
	var vbox: VBoxContainer = view.get_meta("vbox")

	var resume := _menu_button("Resume")
	resume.pressed.connect(close)
	vbox.add_child(resume)

	var settings_btn := _menu_button("Settings")
	settings_btn.pressed.connect(_show_settings)
	vbox.add_child(settings_btn)

	var hint := _hint_label("Esc to resume")
	vbox.add_child(hint)
	return view

func _build_settings_view() -> Control:
	var view := _make_view("Settings")
	var vbox: VBoxContainer = view.get_meta("vbox")

	var group := Label.new()
	group.text = "Accessibility"
	group.add_theme_font_size_override("font_size", 12)
	group.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.85))
	vbox.add_child(group)

	var speed_label := Label.new()
	speed_label.text = "Text Speed"
	speed_label.add_theme_font_size_override("font_size", 14)
	speed_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	vbox.add_child(speed_label)

	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 6)
	seg.alignment = BoxContainer.ALIGNMENT_CENTER
	for preset in range(SPEED_LABELS.size()):
		var btn := _menu_button(SPEED_LABELS[preset])
		btn.custom_minimum_size.x = 78
		btn.pressed.connect(_on_speed_pressed.bind(preset))
		seg.add_child(btn)
		_speed_buttons.append(btn)
	vbox.add_child(seg)

	var back := _menu_button("Back")
	back.pressed.connect(_show_pause)
	vbox.add_child(back)
	return view

# --- Open / close / navigation ---

func toggle() -> void:
	if _is_open:
		if _settings_view.visible:
			_show_pause()
		else:
			close()
	else:
		open()

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_show_pause()
	_refresh_speed_buttons()
	visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	get_tree().paused = false
	closed.emit()

func is_open() -> bool:
	return _is_open

func _exit_tree() -> void:
	# Never leave the tree paused if we're freed (e.g. scene change) while open.
	if _is_open and is_inside_tree():
		get_tree().paused = false

func _show_pause() -> void:
	_pause_view.visible = true
	_settings_view.visible = false

func _show_settings() -> void:
	_refresh_speed_buttons()
	_pause_view.visible = false
	_settings_view.visible = true

func _on_speed_pressed(preset: int) -> void:
	var settings := _settings()
	if settings != null and settings.has_method("set_text_speed"):
		settings.call("set_text_speed", preset)
	_refresh_speed_buttons()

func _refresh_speed_buttons() -> void:
	var active := 1  # Normal fallback
	var settings := _settings()
	if settings != null and "text_speed" in settings:
		active = int(settings.text_speed)
	for i in range(_speed_buttons.size()):
		_style_button(_speed_buttons[i], i == active)

func _settings() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Settings")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		if is_inside_tree():
			get_viewport().set_input_as_handled()

# --- UI builders ---

func _make_view(title: String) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.06, 0.97)
	style.border_color = Color(0.3, 0.34, 0.42, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	center.set_meta("vbox", vbox)
	return center

func _menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	_style_button(btn, false)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _style_button(btn: Button, active: bool) -> void:
	var color := Color(0.45, 0.65, 0.9) if active else Color(0.6, 0.62, 0.68)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.22, 0.95) if active else Color(0.07, 0.075, 0.09, 0.95)
	style.border_color = Color(color, 0.8 if active else 0.4)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.border_color = Color(color, 0.9)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color(color, 1.0 if active else 0.8))

func _hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
