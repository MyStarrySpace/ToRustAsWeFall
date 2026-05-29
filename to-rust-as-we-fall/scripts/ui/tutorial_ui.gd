class_name TutorialUI
extends Node

## Shared UI container for tutorial scenes: dialogue, fades, thoughts, and
## transient action prompts.

var _label: Label
var _prompt_layer: CanvasLayer
var _prompt_tween: Tween

func _ready() -> void:
	_setup_prompt()

func show_prompt(text: String, duration := 0.0) -> void:
	_setup_prompt()
	_label.text = text
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.75, 0.4)
	if duration > 0.0:
		_prompt_tween.tween_interval(duration)
		_prompt_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.0, 0.6)

func hide_prompt() -> void:
	_setup_prompt()
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_label, "theme_override_colors/font_color:a", 0.0, 0.4)

func _setup_prompt() -> void:
	if _label != null:
		return
	_prompt_layer = get_node_or_null("TutorialPrompt") as CanvasLayer
	if _prompt_layer == null:
		_prompt_layer = CanvasLayer.new()
		_prompt_layer.name = "TutorialPrompt"
		add_child(_prompt_layer)
	_prompt_layer.layer = 12

	_label = Label.new()
	_label.name = "PromptLabel"
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
	_prompt_layer.add_child(_label)
