class_name GameSettings
extends Node

## Global player settings (autoload `Settings`). Holds accessibility options —
## text speed today, more later — persisted to user://settings.cfg. Consumers
## read the scales and fall back to defaults when this autoload is absent (a
## scene run standalone or a headless test that didn't load the autoload).

const CONFIG_PATH := "user://settings.cfg"
const RALLY_HOLD_MIN := 0.20
const RALLY_HOLD_MAX := 1.20
const RALLY_HOLD_DEFAULT := 0.45
## Six stable character columns, two direct abilities each. The action identities stay fixed when
## party members or context-specific ability names change. Project defaults form the right-hand
## UIOP[] / JKL;'\\ bank, while this settings layer keeps every slot player-remappable.
const PARTY_ABILITY_ACTIONS := [
	["party_slot_1_ability_1", "party_slot_1_ability_2"],
	["party_slot_2_ability_1", "party_slot_2_ability_2"],
	["party_slot_3_ability_1", "party_slot_3_ability_2"],
	["party_slot_4_ability_1", "party_slot_4_ability_2"],
	["party_slot_5_ability_1", "party_slot_5_ability_2"],
	["party_slot_6_ability_1", "party_slot_6_ability_2"],
]

## Gameplay presets are ordinary settings configurations, not alternate level data.
## The generated stretch receives one of these dictionaries at load time, so changing
## the mode never changes its spec, seed, geometry, hazards, or authored rewards.
const GAME_MODE_NEUTRAL := "neutral"
const GAME_MODE_EXPEDITION := "expedition"
const GAME_MODE_SCARCITY := "scarcity"
const GAME_MODE_IDS := [GAME_MODE_NEUTRAL, GAME_MODE_EXPEDITION, GAME_MODE_SCARCITY]
const FOOD_TEST_NEUTRAL := "neutral"
const FOOD_TEST_EXPEDITION := "return_loop"
const FOOD_TEST_SCARCITY := "scarcity"
const FOOD_TEST_BY_GAME_MODE := {
	GAME_MODE_NEUTRAL: FOOD_TEST_NEUTRAL,
	GAME_MODE_EXPEDITION: FOOD_TEST_EXPEDITION,
	GAME_MODE_SCARCITY: FOOD_TEST_SCARCITY,
}
const GAME_MODE_BY_FOOD_TEST := {
	FOOD_TEST_NEUTRAL: GAME_MODE_NEUTRAL,
	FOOD_TEST_EXPEDITION: GAME_MODE_EXPEDITION,
	FOOD_TEST_SCARCITY: GAME_MODE_SCARCITY,
}
const GAME_MODE_LABELS := {
	GAME_MODE_NEUTRAL: "Neutral",
	GAME_MODE_EXPEDITION: "Expedition",
	GAME_MODE_SCARCITY: "Scarcity",
}
const GAME_MODE_DESCRIPTIONS := {
	GAME_MODE_NEUTRAL: "Canonical ATP economy: exploration is free; carried lysate restores ATP when endocytosed.",
	GAME_MODE_EXPEDITION: "Zero-drain experimental control: physical lysate and shelter rules match Scarcity, without its clock.",
	GAME_MODE_SCARCITY: "Experimental: after movement begins, each character loses 1 ATP every 60 seconds. At zero ATP, later ticks deal 5 HP damage; WRAP can absorb it.",
}
const GAME_MODE_CHUNK_CONFIGS := {
	GAME_MODE_NEUTRAL: {
		"game_mode": GAME_MODE_NEUTRAL,
		"food_test": "neutral",
	},
	GAME_MODE_EXPEDITION: {
		"game_mode": GAME_MODE_EXPEDITION,
		"food_test": "return_loop",
	},
	GAME_MODE_SCARCITY: {
		"game_mode": GAME_MODE_SCARCITY,
		"food_test": "scarcity",
		"food_test_settings": {
			"drain_interval_seconds": 60.0,
			"drain_atp": 1.0,
			"zero_atp_hp_drain": 5.0,
		},
	},
}

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
## When true, non-acknowledge dialogue lines advance on their own after a reading
## beat. Default false: every line waits for a click (or data-layer advance), so
## the dialogue is click-driven unless the player opts into auto-advance.
var auto_advance_dialogue: bool = false
## How long COMMAND must be held before it becomes a whole-party rally instead of a normal click.
## The deliberately broad range supports both twitchy mouse players and touch/accessibility use.
var rally_hold_duration: float = RALLY_HOLD_DEFAULT
## Accessibility: hit feedback intensity. Screen shake and the red damage flash
## can each be disabled without losing the rest of the hit language (opacity
## blink, portrait pulse, offscreen alert bubbles stay on — they carry the
## information; shake/flash carry only the punch).
var screen_shake_enabled: bool = true
var damage_flash_enabled: bool = true
## Accessibility: how the on-screen touch SHIFT button behaves. False (default) =
## tap-to-toggle (a sticky latch consumed by the next action tap — one-finger play);
## true = a held button (the modifier lasts exactly while the finger is down).
var touch_shift_hold: bool = false

func set_screen_shake_enabled(on: bool) -> void:
	screen_shake_enabled = on
	save_settings()
	changed.emit()

func set_damage_flash_enabled(on: bool) -> void:
	damage_flash_enabled = on
	save_settings()
	changed.emit()

func set_touch_shift_hold(hold: bool) -> void:
	if hold == touch_shift_hold:
		return
	touch_shift_hold = hold
	save_settings()
	changed.emit()

func is_touch_shift_hold() -> bool:
	return touch_shift_hold
## The selected gameplay configuration. It is applied when entering/restarting a
## generated stretch rather than hot-swapping the economy underneath a live run.
var game_mode: String = GAME_MODE_NEUTRAL
var _input_binding_overrides: Dictionary = {}
var _config_path: String = CONFIG_PATH

## Tests and standalone tools can supply an isolated path; the autoload keeps using user://settings.cfg.
func _init(config_path_override: String = CONFIG_PATH) -> void:
	_config_path = config_path_override

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

# --- Auto-advance ---

func set_auto_advance_dialogue(enabled: bool) -> void:
	if enabled == auto_advance_dialogue:
		return
	auto_advance_dialogue = enabled
	save_settings()
	changed.emit()

func is_auto_advance_dialogue() -> bool:
	return auto_advance_dialogue

# --- Gameplay mode ---

func set_game_mode(mode_id: String) -> void:
	var canonical := canonical_game_mode(mode_id)
	if canonical == game_mode:
		return
	game_mode = canonical
	save_settings()
	changed.emit()

func get_game_mode() -> String:
	return game_mode

static func canonical_game_mode(mode_id: String) -> String:
	var normalized := mode_id.strip_edges().to_lower()
	return normalized if normalized in GAME_MODE_IDS else GAME_MODE_NEUTRAL

static func game_mode_label(mode_id: String) -> String:
	var canonical := canonical_game_mode(mode_id)
	return str(GAME_MODE_LABELS.get(canonical, "Neutral"))

static func game_mode_description(mode_id: String) -> String:
	var canonical := canonical_game_mode(mode_id)
	return str(GAME_MODE_DESCRIPTIONS.get(canonical, ""))

## Normalize the compatibility-era game_mode/food_test pair at the runtime boundary.
## game_mode is authoritative when both are supplied because it is the player-facing
## setting; a lone legacy food_test is still mapped to its canonical mode. This keeps
## the displayed profile and active mechanics from ever disagreeing.
static func normalize_generated_play_config(config: Dictionary, fallback_mode := GAME_MODE_NEUTRAL) -> Dictionary:
	var normalized := config.duplicate(true)
	var mode := canonical_game_mode(str(normalized.get("game_mode", fallback_mode)))
	if not normalized.has("game_mode") and normalized.has("food_test"):
		mode = str(GAME_MODE_BY_FOOD_TEST.get(
			str(normalized.get("food_test", FOOD_TEST_NEUTRAL)).strip_edges().to_lower(),
			canonical_game_mode(fallback_mode)
		))
	normalized["game_mode"] = mode
	normalized["food_test"] = str(FOOD_TEST_BY_GAME_MODE.get(mode, FOOD_TEST_NEUTRAL))
	if mode != GAME_MODE_SCARCITY:
		normalized.erase("food_test_settings")
	return normalized

## Per-chunk projection of the selected gameplay preset. Keeping this mapping in
## Settings makes the mode a configuration while the level remains mode-agnostic.
func chunk_config_overrides(chunk_name: String) -> Dictionary:
	if chunk_name != "generated_stretch":
		return {}
	var raw: Variant = GAME_MODE_CHUNK_CONFIGS.get(game_mode, GAME_MODE_CHUNK_CONFIGS[GAME_MODE_NEUTRAL])
	return (raw as Dictionary).duplicate(true)

# --- Controls ---

func set_rally_hold_duration(seconds: float) -> void:
	var clamped := clampf(seconds, RALLY_HOLD_MIN, RALLY_HOLD_MAX)
	if is_equal_approx(clamped, rally_hold_duration):
		return
	rally_hold_duration = clamped
	save_settings()
	changed.emit()

func get_rally_hold_duration() -> float:
	return rally_hold_duration

static func party_ability_actions() -> Array[String]:
	var actions: Array[String] = []
	for column in PARTY_ABILITY_ACTIONS:
		for action in column:
			actions.append(str(action))
	return actions

func rebind_keyboard_action(action: String, key_event: InputEventKey) -> bool:
	if not InputMap.has_action(action):
		return false
	var replacement := key_event.duplicate() as InputEventKey
	replacement.pressed = false
	replacement.echo = false
	var previous := _primary_keyboard_event(action)
	var conflict := _find_keyboard_conflict(action, replacement)
	_replace_keyboard_event(action, replacement)
	_record_keyboard_override(action)
	if conflict != "":
		if previous != null:
			_replace_keyboard_event(conflict, previous)
		else:
			_replace_keyboard_event(conflict, null)
		_record_keyboard_override(conflict)
	save_settings()
	changed.emit()
	return true

func clear_keyboard_action(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	_replace_keyboard_event(action, null)
	_record_keyboard_override(action)
	save_settings()
	changed.emit()
	return true

func _primary_keyboard_event(action: String) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).duplicate() as InputEventKey
	return null

func _replace_keyboard_event(action: String, replacement: InputEventKey) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey:
			InputMap.action_erase_event(action, existing)
	if replacement != null:
		InputMap.action_add_event(action, replacement)

func _find_keyboard_conflict(excluded_action: String, candidate: InputEventKey) -> String:
	for raw_action in InputMap.get_actions():
		var action := str(raw_action)
		if action == excluded_action or action.begins_with("ui_"):
			continue
		var existing := _primary_keyboard_event(action)
		if existing != null and _same_key_chord(existing, candidate):
			return action
	return ""

func _same_key_chord(a: InputEventKey, b: InputEventKey) -> bool:
	var a_code := a.physical_keycode if a.physical_keycode != KEY_NONE else a.keycode
	var b_code := b.physical_keycode if b.physical_keycode != KEY_NONE else b.keycode
	return (a_code == b_code and a.alt_pressed == b.alt_pressed and a.shift_pressed == b.shift_pressed
		and a.ctrl_pressed == b.ctrl_pressed and a.meta_pressed == b.meta_pressed)

func _record_keyboard_override(action: String) -> void:
	var event := _primary_keyboard_event(action)
	if event == null:
		_input_binding_overrides[action] = {"unbound": true}
		return
	_input_binding_overrides[action] = {
		"physical_keycode": int(event.physical_keycode),
		"keycode": int(event.keycode),
		"alt": event.alt_pressed,
		"shift": event.shift_pressed,
		"ctrl": event.ctrl_pressed,
		"meta": event.meta_pressed,
	}

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
	# Keep settings owned by other systems/mods when updating our known values.
	if FileAccess.file_exists(_config_path):
		cfg.load(_config_path)
	cfg.set_value("accessibility", "text_speed", text_speed)
	cfg.set_value("accessibility", "auto_advance_dialogue", auto_advance_dialogue)
	cfg.set_value("accessibility", "screen_shake", screen_shake_enabled)
	cfg.set_value("accessibility", "damage_flash", damage_flash_enabled)
	cfg.set_value("accessibility", "touch_shift_hold", touch_shift_hold)
	cfg.set_value("gameplay", "mode", game_mode)
	cfg.set_value("controls", "rally_hold_duration", rally_hold_duration)
	for action in _input_binding_overrides:
		cfg.set_value("input_bindings", str(action), _input_binding_overrides[action])
	cfg.save(_config_path)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) != OK:
		return
	text_speed = clampi(
		int(_config_value(cfg, "accessibility", "text_speed", TextSpeed.NORMAL)),
		0,
		TextSpeed.size() - 1
	)
	auto_advance_dialogue = bool(
		_config_value(cfg, "accessibility", "auto_advance_dialogue", false)
	)
	screen_shake_enabled = bool(
		_config_value(cfg, "accessibility", "screen_shake", true)
	)
	damage_flash_enabled = bool(
		_config_value(cfg, "accessibility", "damage_flash", true)
	)
	touch_shift_hold = bool(
		_config_value(cfg, "accessibility", "touch_shift_hold", false)
	)
	game_mode = canonical_game_mode(str(
		_config_value(cfg, "gameplay", "mode", GAME_MODE_NEUTRAL)
	))
	rally_hold_duration = clampf(
		float(_config_value(
			cfg,
			"controls",
			"rally_hold_duration",
			RALLY_HOLD_DEFAULT
		)),
		RALLY_HOLD_MIN,
		RALLY_HOLD_MAX
	)
	_input_binding_overrides.clear()
	if not cfg.has_section("input_bindings"):
		return
	for action in cfg.get_section_keys("input_bindings"):
		var spec = cfg.get_value("input_bindings", action, {})
		if not spec is Dictionary or not InputMap.has_action(action):
			continue
		_input_binding_overrides[action] = (spec as Dictionary).duplicate(true)
		if bool(spec.get("unbound", false)):
			_replace_keyboard_event(action, null)
			continue
		var event := InputEventKey.new()
		event.physical_keycode = int(spec.get("physical_keycode", 0))
		event.keycode = int(spec.get("keycode", 0))
		event.alt_pressed = bool(spec.get("alt", false))
		event.shift_pressed = bool(spec.get("shift", false))
		event.ctrl_pressed = bool(spec.get("ctrl", false))
		event.meta_pressed = bool(spec.get("meta", false))
		_replace_keyboard_event(action, event)

static func _config_value(
	cfg: ConfigFile,
	section: String,
	key: String,
	fallback: Variant
) -> Variant:
	# ConfigFile.get_value() reports a noisy missing-section error even when a
	# fallback is supplied, so guard both the section and key explicitly.
	if not cfg.has_section_key(section, key):
		return fallback
	return cfg.get_value(section, key)

# --- Static fallbacks for consumers (degrade gracefully without the autoload) ---

## Resolve the live Settings autoload, or null if it isn't registered.
static func resolve(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null("Settings")
