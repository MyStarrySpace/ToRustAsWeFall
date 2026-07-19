class_name TutorialUI
extends Node

## Shared UI container for tutorial scenes: dialogue, fades, thoughts, and
## transient action prompts.

var _label: Label
var _prompt_layer: CanvasLayer
var _prompt_row: HBoxContainer
var _prompt_glyph: InputGlyph
var _prompt_tween: Tween

func _ready() -> void:
	_setup_prompt()

func show_prompt(text: String, duration := 0.0) -> void:
	var legacy_action_prompt := _resolve_legacy_action_prompt(text)
	if not legacy_action_prompt.is_empty():
		show_action_prompt(
			legacy_action_prompt.action,
			legacy_action_prompt.text,
			duration,
			legacy_action_prompt.fallback
		)
		return
	_setup_prompt()
	_label.text = text
	_prompt_glyph.visible = false
	_animate_prompt(duration)

## Older scenes sent control names as prose before action glyphs existed. Resolve the two shared
## movement/interaction forms here so those prompts follow a rebind without every sequence carrying
## its own compatibility logic. New prompts should call show_action_prompt() directly.
static func _resolve_legacy_action_prompt(text: String) -> Dictionary:
	if text.begins_with("Click to move"):
		return {
			"action": &"command",
			"text": text.trim_prefix("Click "),
			"fallback": "RMB",
		}
	if text.begins_with("[Interact]"):
		var prompt_text := text.trim_prefix("[Interact]").strip_edges()
		if prompt_text.begins_with("—"):
			prompt_text = prompt_text.trim_prefix("—").strip_edges()
		elif prompt_text.begins_with("-"):
			prompt_text = prompt_text.trim_prefix("-").strip_edges()
		return {
			"action": &"command",
			"text": prompt_text,
			"fallback": "RMB",
		}
	return {}

## Composite prompt for a real InputMap action. The same action drives both gameplay and artwork,
## so changing a mouse button or key in settings cannot leave this prompt lying about the control.
func show_action_prompt(
	action: StringName,
	text: String,
	duration := 0.0,
	fallback_label := ""
) -> void:
	_setup_prompt()
	_prompt_glyph.configure_action(action, fallback_label)
	_prompt_glyph.visible = true
	_label.text = text
	_animate_prompt(duration)

func _animate_prompt(duration: float) -> void:
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_row.modulate.a = 0.0
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_row, "modulate:a", 0.85, 0.4)
	if duration > 0.0:
		_prompt_tween.tween_interval(duration)
		_prompt_tween.tween_property(_prompt_row, "modulate:a", 0.0, 0.6)

func hide_prompt() -> void:
	_setup_prompt()
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_row, "modulate:a", 0.0, 0.4)

func _setup_prompt() -> void:
	if _label != null:
		return
	_prompt_layer = get_node("TutorialPrompt") as CanvasLayer
	_prompt_row = get_node("TutorialPrompt/PromptRow") as HBoxContainer
	_prompt_glyph = get_node("TutorialPrompt/PromptRow/PromptGlyph") as InputGlyph
	_label = get_node("TutorialPrompt/PromptRow/PromptLabel") as Label
