extends CanvasLayer

## Bottom-of-screen dialogue display with typewriter effect.
## Supports speaker labels, text queuing, and style variants.

@export var chars_per_second := 30.0
@export var default_hold_time := 2.0

## External speed multiplier (set by sequence for fast-forward). Default 1.0.
var speed_multiplier := 1.0

var _queue: Array[Dictionary] = []
var _current_text := ""
var _displayed_chars := 0.0
var _hold_timer := 0.0
var _active := false
var _waiting_for_input := false
var _style := "normal"  # "normal", "poem", "data", "fragment"

var _panel: PanelContainer
var _speaker_label: Label
var _text_label: RichTextLabel
var _continue_hint: Label

signal dialogue_finished()
signal line_displayed(text: String)

func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	# Full-width bottom panel
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -120
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	_panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.04, 0.92)
	panel_style.border_color = Color(0.15, 0.15, 0.2, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(2)
	panel_style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 12)
	_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.8))
	vbox.add_child(_speaker_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.add_theme_font_size_override("normal_font_size", 15)
	_text_label.add_theme_color_override("default_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(_text_label)

	_continue_hint = Label.new()
	_continue_hint.text = ""
	_continue_hint.add_theme_font_size_override("font_size", 11)
	_continue_hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 0.6))
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_continue_hint)

func _process(delta: float) -> void:
	if not _active:
		return

	if _displayed_chars < _current_text.length():
		# Typewriter effect
		var spd := chars_per_second
		if _style == "fragment":
			spd *= 0.4  # Slower for fragmenting speech
		elif _style == "poem":
			spd *= 0.7  # Measured pace for poetry
		_displayed_chars += spd * speed_multiplier * delta
		var count := mini(int(_displayed_chars), _current_text.length())
		_text_label.text = _current_text.substr(0, count)
		if count >= _current_text.length():
			line_displayed.emit(_current_text)
			if _waiting_for_input:
				# Auto-advance wait_for_input lines when fast-forwarding
				if speed_multiplier > 2.0:
					_hold_timer = 0.3 / speed_multiplier
				else:
					_continue_hint.text = "[click to continue]"
			else:
				_hold_timer = default_hold_time
	elif _waiting_for_input:
		# Auto-advance when fast-forwarding
		if speed_multiplier > 2.0:
			_hold_timer -= delta * speed_multiplier
			if _hold_timer <= 0:
				_advance()
	else:
		_hold_timer -= delta * speed_multiplier
		if _hold_timer <= 0:
			_advance()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _displayed_chars < _current_text.length():
				# Skip typewriter — show full text
				_displayed_chars = _current_text.length()
				_text_label.text = _current_text
				line_displayed.emit(_current_text)
				if _waiting_for_input:
					_continue_hint.text = "[click to continue]"
				else:
					_hold_timer = default_hold_time * 0.5
				if is_inside_tree():
					get_viewport().set_input_as_handled()
			elif _waiting_for_input:
				_advance()
				if is_inside_tree():
					get_viewport().set_input_as_handled()

func _advance() -> void:
	if _queue.is_empty():
		_active = false
		_panel.visible = false
		dialogue_finished.emit()
		return
	_show_next()

func _show_next() -> void:
	var entry: Dictionary = _queue.pop_front()
	_current_text = entry.get("text", "")
	_style = entry.get("style", "normal")
	_waiting_for_input = entry.get("wait_for_input", false)
	_displayed_chars = 0.0
	_hold_timer = 0.0
	_continue_hint.text = ""

	var speaker: String = entry.get("speaker", "")
	_speaker_label.text = speaker
	_speaker_label.visible = speaker != ""
	_text_label.text = ""

	# Style the panel based on type
	var panel_style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	match _style:
		"poem":
			_text_label.add_theme_color_override("default_color", Color(0.6, 0.6, 0.65))
			panel_style.border_color = Color(0.2, 0.15, 0.1, 0.4)
			_speaker_label.add_theme_color_override("font_color", Color(0.5, 0.4, 0.35, 0.6))
		"fragment":
			_text_label.add_theme_color_override("default_color", Color(0.5, 0.45, 0.4, 0.8))
			panel_style.border_color = Color(0.25, 0.1, 0.08, 0.4)
		"data":
			_text_label.add_theme_color_override("default_color", Color(0.3, 0.5, 0.7))
			panel_style.border_color = Color(0.1, 0.2, 0.35, 0.5)
			_speaker_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.7, 0.6))
		_:
			_text_label.add_theme_color_override("default_color", Color(0.75, 0.75, 0.8))
			panel_style.border_color = Color(0.15, 0.15, 0.2, 0.6)
			_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.8))

	_panel.visible = true
	_active = true

# --- Public API ---

## Queue a single line of dialogue
func say(text: String, speaker := "", style := "normal", wait := false) -> void:
	_queue.append({
		"text": text,
		"speaker": speaker,
		"style": style,
		"wait_for_input": wait,
	})
	if not _active:
		_show_next()

## Queue multiple lines
func say_sequence(lines: Array[Dictionary]) -> void:
	for line in lines:
		_queue.append(line)
	if not _active:
		_show_next()

## Force clear
func clear() -> void:
	_queue.clear()
	_active = false
	_panel.visible = false

func is_active() -> bool:
	return _active
