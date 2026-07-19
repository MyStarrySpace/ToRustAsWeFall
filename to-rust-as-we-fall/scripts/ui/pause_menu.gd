extends CanvasLayer

## Esc-toggled pause menu. Pause view: Resume / Settings. Settings view holds the
## accessibility options (text speed today, room to grow). Self-contained: it
## listens for ui_cancel even while the tree is paused, pauses gameplay while
## open, and reads/writes the Settings autoload. Drop one into any scene.

signal opened()
signal closed()

# Mirrors GameSettings.TextSpeed order (SLOW, NORMAL, FAST, INSTANT).
const SPEED_LABELS := ["Slow", "Normal", "Fast", "Instant"]
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _dim: ColorRect = $Dim
@onready var _pause_view: Control = $PauseView
@onready var _settings_view: Control = $SettingsView
var _speed_buttons: Array[Button] = []
var _game_mode_buttons: Dictionary = {}
@onready var _rally_hold_slider: HSlider = $SettingsView/Panel/Content/RallyRow/Slider
@onready var _rally_hold_value: Label = $SettingsView/Panel/Content/RallyRow/Value
var _refreshing_controls := false
var _ability_binding_buttons: Dictionary = {}
@onready var _binding_hint: Label = $SettingsView/Panel/Content/BindingHint
var _listening_action := ""
var _is_open := false

func _ready() -> void:
	_speed_buttons = [
		$SettingsView/Panel/Content/SpeedButtons/Slow,
		$SettingsView/Panel/Content/SpeedButtons/Normal,
		$SettingsView/Panel/Content/SpeedButtons/Fast,
		$SettingsView/Panel/Content/SpeedButtons/Instant,
	]
	for preset in range(_speed_buttons.size()):
		_speed_buttons[preset].pressed.connect(_on_speed_pressed.bind(preset))
	_game_mode_buttons = {
		GameSettings.GAME_MODE_NEUTRAL: $SettingsView/Panel/Content/ModeButtons/Neutral,
		GameSettings.GAME_MODE_EXPEDITION: $SettingsView/Panel/Content/ModeButtons/Expedition,
		GameSettings.GAME_MODE_SCARCITY: $SettingsView/Panel/Content/ModeButtons/Scarcity,
	}
	for raw_mode_id in _game_mode_buttons:
		var mode_id := str(raw_mode_id)
		var mode_button: Button = _game_mode_buttons[mode_id]
		mode_button.tooltip_text = GameSettings.game_mode_description(mode_id)
		mode_button.pressed.connect(_on_game_mode_pressed.bind(mode_id))
	_rally_hold_slider.min_value = GameSettings.RALLY_HOLD_MIN
	_rally_hold_slider.max_value = GameSettings.RALLY_HOLD_MAX
	_rally_hold_slider.value_changed.connect(_on_rally_hold_duration_changed)
	for party_slot in range(GameSettings.PARTY_ABILITY_ACTIONS.size()):
		var actions: Array = GameSettings.PARTY_ABILITY_ACTIONS[party_slot]
		for ability_slot in range(actions.size()):
			var action := str(actions[ability_slot])
			var button := get_node("SettingsView/Panel/Content/BindingGrid/Char%d/Ability%d" % [
				party_slot + 1, ability_slot + 1]) as Button
			button.pressed.connect(_begin_binding_capture.bind(action))
			_ability_binding_buttons[action] = button
	$PauseView/Panel/Content/ResumeButton.pressed.connect(close)
	$PauseView/Panel/Content/RestartButton.pressed.connect(_restart_scene)
	$PauseView/Panel/Content/SettingsButton.pressed.connect(_show_settings)
	$PauseView/Panel/Content/MainMenuButton.pressed.connect(_return_to_main_menu)
	$SettingsView/Panel/Content/BackButton.pressed.connect(_show_pause)
	for button_node in find_children("*", "Button", true, false):
		_style_button(button_node as Button, false)
	visible = false

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
	_refresh_game_mode_buttons()
	_refresh_rally_hold_control()
	_refresh_ability_binding_buttons()
	visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_cancel_binding_capture()
	visible = false
	get_tree().paused = false
	closed.emit()

func _restart_scene() -> void:
	# Scene changes do not implicitly clear SceneTree.paused. Unpause first so the
	# replacement scene always starts live, including fragment-picker reloads.
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("prepare_scene_restart"):
		current_scene.call("prepare_scene_restart")
	close()
	get_tree().reload_current_scene()

func _return_to_main_menu() -> void:
	close()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func is_open() -> bool:
	return _is_open

func _exit_tree() -> void:
	# Never leave the tree paused if we're freed (e.g. scene change) while open.
	if _is_open and is_inside_tree():
		get_tree().paused = false

func _show_pause() -> void:
	_cancel_binding_capture()
	_pause_view.visible = true
	_settings_view.visible = false

func _show_settings() -> void:
	_refresh_speed_buttons()
	_refresh_game_mode_buttons()
	_refresh_rally_hold_control()
	_refresh_ability_binding_buttons()
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

func _on_game_mode_pressed(mode_id: String) -> void:
	var settings := _settings()
	if settings != null and settings.has_method("set_game_mode"):
		settings.call("set_game_mode", mode_id)
	_refresh_game_mode_buttons()

func _refresh_game_mode_buttons() -> void:
	var active := GameSettings.GAME_MODE_NEUTRAL
	var settings := _settings()
	if settings != null and settings.has_method("get_game_mode"):
		active = str(settings.call("get_game_mode"))
	for raw_mode_id in _game_mode_buttons:
		var mode_id := str(raw_mode_id)
		_style_button(_game_mode_buttons[mode_id], mode_id == active)

func _on_rally_hold_duration_changed(seconds: float) -> void:
	if _refreshing_controls:
		return
	var settings := _settings()
	if settings != null and settings.has_method("set_rally_hold_duration"):
		settings.call("set_rally_hold_duration", seconds)
	_refresh_rally_hold_control()

func _refresh_rally_hold_control() -> void:
	if _rally_hold_slider == null:
		return
	var seconds := GameSettings.RALLY_HOLD_DEFAULT
	var settings := _settings()
	if settings != null and settings.has_method("get_rally_hold_duration"):
		seconds = float(settings.call("get_rally_hold_duration"))
	_refreshing_controls = true
	_rally_hold_slider.value = seconds
	_refreshing_controls = false
	if _rally_hold_value != null:
		_rally_hold_value.text = "%.2f s" % seconds

func _begin_binding_capture(action: String) -> void:
	_listening_action = action
	_refresh_ability_binding_buttons()
	if _binding_hint != null:
		var parts := action.split("_")
		var slot := int(parts[2]) if parts.size() > 2 else 0
		var ability := int(parts[4]) if parts.size() > 4 else 0
		_binding_hint.text = "CHAR %d · ABILITY %d: press a key, Delete to unbind, or Esc to cancel." % [slot, ability]

func _cancel_binding_capture() -> void:
	_listening_action = ""
	_refresh_ability_binding_buttons()
	if _binding_hint != null:
		_binding_hint.text = "Click a slot, then press a key. Conflicting gameplay bindings are swapped."

func _refresh_ability_binding_buttons() -> void:
	for raw_action in _ability_binding_buttons.keys():
		var action := str(raw_action)
		var button: Button = _ability_binding_buttons[action]
		var parts := action.split("_")
		var ability := int(parts[4]) if parts.size() > 4 else 0
		var binding := InputHints.label_for_action(action, "UNBOUND")
		button.text = "A%d  %s" % [ability, binding]
		_style_button(button, action == _listening_action)

func _input(event: InputEvent) -> void:
	if _listening_action == "" or not _is_open or not _settings_view.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	var code := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if code == KEY_ESCAPE:
		_cancel_binding_capture()
	elif code in [KEY_DELETE, KEY_BACKSPACE]:
		var settings := _settings()
		if settings != null and settings.has_method("clear_keyboard_action"):
			settings.call("clear_keyboard_action", _listening_action)
		_cancel_binding_capture()
	elif code not in [KEY_NONE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		var settings := _settings()
		if settings != null and settings.has_method("rebind_keyboard_action"):
			settings.call("rebind_keyboard_action", _listening_action, key_event)
		_cancel_binding_capture()
	if is_inside_tree():
		get_viewport().set_input_as_handled()

func _settings() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Settings")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		if is_inside_tree():
			get_viewport().set_input_as_handled()

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
