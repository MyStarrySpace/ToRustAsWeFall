extends CanvasLayer

## Minimal tutorial prompt — shows a key binding hint, no labels or arrows.
## Appears when an action becomes available, fades when used or dismissed.

var _label: Label
var _tween: Tween

func _ready() -> void:
	layer = 12
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.0))
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_top = -60
	_label.offset_bottom = -30
	_label.offset_left = -200
	_label.offset_right = 200
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func show_prompt(text: String, duration := 0.0) -> void:
	_label.text = text
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.75, 0.4)
	if duration > 0:
		_tween.tween_interval(duration)
		_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.0, 0.6)

func hide_prompt() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.0, 0.4)
