class_name GameSettings
extends Node

## Global player settings (autoload `Settings`). Holds accessibility options —
## text speed today, more later — persisted to user://settings.cfg. Consumers
## read the scales and fall back to defaults when this autoload is absent (a
## scene run standalone or a headless test that didn't load the autoload).

const CONFIG_PATH := "user://settings.cfg"

enum TextSpeed { SLOW, NORMAL, FAST, INSTANT }

## Typewriter chars-per-second multiplier and reading-beat multiplier per preset.
const TEXT_SPEED_CPS := {
	TextSpeed.SLOW: 0.6,
	TextSpeed.NORMAL: 1.0,
	TextSpeed.FAST: 1.8,
	TextSpeed.INSTANT: 1000.0,
}
const TEXT_SPEED_HOLD := {
	TextSpeed.SLOW: 1.5,
	TextSpeed.NORMAL: 1.0,
	TextSpeed.FAST: 0.6,
	TextSpeed.INSTANT: 0.25,
}

signal changed()

var text_speed: int = TextSpeed.NORMAL

func _ready() -> void:
	# Settings must apply even while the rest of the scene is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

# --- Text speed ---

func set_text_speed(preset: int) -> void:
	var clamped := clampi(preset, 0, TextSpeed.size() - 1)
	if clamped == text_speed:
		return
	text_speed = clamped
	save_settings()
	changed.emit()

func text_cps_scale() -> float:
	return float(TEXT_SPEED_CPS.get(text_speed, 1.0))

func text_hold_scale() -> float:
	return float(TEXT_SPEED_HOLD.get(text_speed, 1.0))

static func text_speed_label(preset: int) -> String:
	match preset:
		TextSpeed.SLOW: return "Slow"
		TextSpeed.NORMAL: return "Normal"
		TextSpeed.FAST: return "Fast"
		TextSpeed.INSTANT: return "Instant"
	return "Normal"

# --- Persistence ---

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "text_speed", text_speed)
	cfg.save(CONFIG_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	text_speed = clampi(int(cfg.get_value("accessibility", "text_speed", TextSpeed.NORMAL)), 0, TextSpeed.size() - 1)

# --- Static fallbacks for consumers (degrade gracefully without the autoload) ---

## Resolve the live Settings autoload, or null if it isn't registered.
static func resolve(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null("Settings")
