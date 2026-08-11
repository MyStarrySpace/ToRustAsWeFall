extends CanvasLayer
class_name GameOverOverlay

## The screen that announces a death, and the only place the game can tell the player what to do
## about it. In story mode a death is recoverable -- resting restores the roster, and the level can
## be taken again -- so this screen carries the epitaph, the standing of what was lost, and the
## control that acts on it.
##
## The overlay only ASKS. `reset_requested` is answered by the host sequence, which owns scene
## changes and teardown; nothing here reloads anything itself.

signal reset_requested

## What the player stands to lose by taking the level again. Early on this is nothing, which is
## exactly what makes the reset the right move -- a scene with real losses sets its own line.
const DEFAULT_GUIDANCE := "Nothing is lost yet."

@onready var _epitaph: Label = $Label
@onready var _guidance: Label = $Guidance
@onready var _reset_button: Button = $ResetButton

func _ready() -> void:
	# The pause menu pauses the whole tree. A death screen that stops with it offers a button the
	# player cannot press, which is a dead end wearing a control.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_button.pressed.connect(_on_reset_pressed)
	_reset_button.grab_focus()

func set_epitaph(text: String) -> void:
	_epitaph.text = text

func set_guidance(text: String) -> void:
	_guidance.text = text

## Fades the whole screen up together. The caller schedules WHEN death is announced; the reveal
## itself is cosmetic and rides a tween bound to this node, so it dies with the scene.
func reveal(duration: float = 2.0) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	for node in [_epitaph, _guidance, _reset_button]:
		node.modulate.a = 0.0
		tween.tween_property(node, "modulate:a", 1.0, duration)

func _on_reset_pressed() -> void:
	reset_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		reset_requested.emit()
