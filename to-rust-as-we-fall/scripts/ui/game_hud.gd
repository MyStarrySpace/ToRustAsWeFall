extends CanvasLayer

## Unified game HUD. Sequences configure which elements are visible.
## Matches the React prototype layout: stat bars left, controls center,
## abilities right, time bar top, messages top-center.

const HUD_CONTRACT_ID := "shared_game_hud_v1"
const HUD_SCRIPT_PATH := "res://scripts/ui/game_hud.gd"
const InputGlyphScene := preload("res://scenes/ui/input_glyph.tscn")
const ControlButtonScene := preload("res://scenes/ui/hud_control_button.tscn")
const StatRowScene := preload("res://scenes/ui/hud_stat_row.tscn")
const PortraitScene := preload("res://scenes/ui/hud_portrait.tscn")
const PipStripScene := preload("res://scenes/ui/hud_pip_strip.tscn")
const PipScene := preload("res://scenes/ui/hud_pip.tscn")
const HandChipScene := preload("res://scenes/ui/hud_hand_chip.tscn")
const AbilityColumnScene := preload("res://scenes/ui/hud_ability_column.tscn")
const MAX_ABILITY_COLUMNS := 6
const ABILITIES_PER_CHARACTER := 2
const BOTTOM_BAR_COLLAPSED_HEIGHT := 64.0
const BOTTOM_BAR_DRAWER_HEIGHT := 126.0

signal run_toggled(is_running: bool)
signal routing_toggled(mode: String)
signal ability_pressed(ability_name: String)
signal pause_toggled(is_paused: bool)
signal character_selection_changed(selected_ids: Array)
## Emitted while the player holds (true) / releases (false) the highlight action (SHIFT):
## reveal every interactable at once. A hold, so it carries both edges, unlike the toggles.
signal highlight_held(active: bool)
## Emitted when the player asks to recenter the camera on the party (button or the camera_center key).
## Momentary, like an ability press — carries no state.
signal center_camera_requested()
## A positional-work badge (plate, lever, channel, etc.) was clicked. Locking is deliberately
## separate from portrait selection: it only excludes this holder from whole-party rally commands.
signal portrait_hold_lock_changed(character_id: String, locked: bool)

@onready var _bottom_panel: PanelContainer = $BottomMargin/BottomPanel
@onready var _bottom_margin: MarginContainer = $BottomMargin
@onready var _stat_section: VBoxContainer = $BottomMargin/BottomPanel/BottomRow/StatSection
@onready var _control_section: HBoxContainer = $BottomMargin/BottomPanel/BottomRow/ControlSection
@onready var _ability_section: VBoxContainer = $BottomMargin/BottomPanel/BottomRow/AbilitySection
@onready var _ability_drawer_toggle: Button = $BottomMargin/BottomPanel/BottomRow/AbilitySection/AbilityDrawerToggle
@onready var _ability_drawer_scroll: ScrollContainer = $BottomMargin/BottomPanel/BottomRow/AbilitySection/AbilityDrawerScroll
@onready var _ability_drawer_columns: HBoxContainer = $BottomMargin/BottomPanel/BottomRow/AbilitySection/AbilityDrawerScroll/AbilityColumns
var _ability_drawer_expanded := true
var _ability_columns: Dictionary = {}
var _ability_column_serial := 0
var _ordered_sections: Array[Control] = []
@onready var _hands_section: HBoxContainer = $BottomMargin/BottomPanel/BottomRow/HandsSection
var _section_separators: Array[VSeparator] = []
@onready var _time_container: HBoxContainer = $TimeContainer
@onready var _time_label: Label = $TimeContainer/TimeLabel
@onready var _time_bar: ProgressBar = $TimeContainer/TimeBar
@onready var _message_backing: PanelContainer = $MessageBacking
@onready var _message_label: Label = $MessageLabel
var _message_timer := 0.0
var _message_generation := 0
var _message_tween: Tween

# Control buttons
var _run_button: Button
var _routing_button: Button
var _pause_button: Button
var _center_button: Button
var _run_active := false
var _run_keybind := "R"
var _routing_mode := "safe"
var _paused := false

# Tracked state
var _stat_bars: Dictionary = {}
var _abilities: Dictionary = {}
var _atp_pip_subdivisions := 1

# Character portraits
@onready var _portrait_section: HBoxContainer = $BottomMargin/BottomPanel/BottomRow/PortraitSection
var _portraits: Dictionary = {}  # id -> {card, style, name_label, display_name, color, stat_bars, alert, status}
var _portrait_damage_tweens: Dictionary = {}
var _selected_characters: Array[String] = []
var _active_portrait := ""
var _multi_select := false

## Optional GameState binding for stats and run-state UI.
## Scenes can pass auto_toggle_running=false to handle run_toggled manually.
var _game_state: GameState = null
var _game_state_char_id := ""
var _auto_toggle_running := true

func _ready() -> void:
	_bind_authored_layout()

func _process(delta: float) -> void:
	if _message_timer > 0:
		_message_timer -= delta
		if _message_timer <= 0:
			_fade_message(_message_generation)

## Keyboard input becomes the SAME intent as a HUD button: input actions map to
## the existing signals, so sequences only ever listen to run_toggled /
## pause_toggled / routing_toggled / ability_pressed, never raw keycodes.
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return  # the pause menu owns input while it's open
	if event.is_action_pressed("pause") and _pause_button != null:
		_on_pause_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run") and _run_button != null:
		_on_run_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("route") and _routing_button != null:
		_on_routing_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_center") and _center_button != null:
		_on_center_camera_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("highlight"):
		highlight_held.emit(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("highlight"):
		highlight_held.emit(false)
		get_viewport().set_input_as_handled()
	else:
		# Abilities may supply an action distinct from their data id. The same live action feeds the
		# InputGlyph and this dispatch path, so rebinding never leaves the button and keyboard divergent.
		for id in _abilities.keys():
			var ability: Dictionary = _abilities[id]
			var action := str(ability.get("input_action", ""))
			if action == "" and InputMap.has_action(id):
				action = id
			if action != "" and InputMap.has_action(action) and event.is_action_pressed(action):
				ability_pressed.emit(id)
				get_viewport().set_input_as_handled()
				return

func get_hud_contract() -> Dictionary:
	var stat_names: Array[String] = []
	for stat_name in _stat_bars.keys():
		stat_names.append(str(stat_name))
	stat_names.sort()

	var portrait_ids: Array[String] = []
	for portrait_id in _portraits.keys():
		portrait_ids.append(str(portrait_id))
	portrait_ids.sort()

	var ability_contracts := {}
	for ability_id in _abilities.keys():
		var ability: Dictionary = _abilities[ability_id]
		var button: Button = ability.get("button", null)
		ability_contracts[ability_id] = {
			"display_name": str(ability.get("display_name", "")),
			"keybind": str(ability.get("keybind", "")),
			"input_action": str(ability.get("input_action", "")),
			"state": str(ability.get("state", "ready")),
			"button_text": button.text if button != null else "",
			"owner": str(ability.get("owner", "")),
			"owner_display": str(ability.get("owner_display", "")),
			"party_slot": int(ability.get("party_slot", -1)),
			"ability_slot": int(ability.get("ability_slot", -1)),
		}

	return {
		"contract_id": HUD_CONTRACT_ID,
		"script": HUD_SCRIPT_PATH,
		"stats": stat_names,
		"portraits": portrait_ids,
		"abilities": ability_contracts,
		"run_keybind": _run_keybind,
		"routing_keybind": InputHints.label_for_action("route", "Tab"),
		"pause_keybind": InputHints.label_for_action("pause", "Space"),
		"center_keybind": InputHints.label_for_action("camera_center", "Home"),
		"time_visible": _time_container.visible if _time_container != null else false,
		"multi_select_enabled": _multi_select,
		"atp_pip_subdivisions": _atp_pip_subdivisions,
		"ability_drawer": get_ability_drawer_state(),
	}

## Scarcity uses real half-ATP values, so its strip exposes two ticks per action pip.
## Other modes keep the quieter eight-pip presentation. Existing strip dictionaries
## are rebuilt in place so stat/portrait bindings remain valid across chunk reloads.
func set_atp_pip_subdivisions(subdivisions: int) -> void:
	var next := clampi(subdivisions, 1, 4)
	if next == _atp_pip_subdivisions:
		return
	_atp_pip_subdivisions = next
	for stat_name in _stat_bars.keys():
		var info: Dictionary = _stat_bars[stat_name]
		if str(info.get("type", "")) == "pips":
			_rebuild_pip_strip(info.get("pip_info", {}), next)
	for portrait_id in _portraits.keys():
		var bars: Dictionary = _portraits[portrait_id].stat_bars
		var atp_info: Dictionary = bars.get("atp", {})
		if str(atp_info.get("type", "")) == "pips":
			_rebuild_pip_strip(atp_info.get("pip_info", {}), next)

func _bind_authored_layout() -> void:
	_apply_control_button_style(_ability_drawer_toggle, Color(0.45, 0.62, 0.76))
	_ability_drawer_toggle.pressed.connect(toggle_ability_drawer)
	_ordered_sections = [_portrait_section, _stat_section, _hands_section, _control_section, _ability_section]
	_section_separators = [
		$BottomMargin/BottomPanel/BottomRow/Separator1,
		$BottomMargin/BottomPanel/BottomRow/Separator2,
		$BottomMargin/BottomPanel/BottomRow/Separator3,
		$BottomMargin/BottomPanel/BottomRow/Separator4,
	]
	for section in _ordered_sections:
		section.child_entered_tree.connect(func(_n): _refresh_sections())
		section.child_exiting_tree.connect(func(_n): _refresh_sections())
	_ability_drawer_expanded = not DisplayServer.is_touchscreen_available()
	_refresh_ability_drawer()
	_refresh_sections()

## Show a section only when it has content, and a separator only between two
## visible groups. Keeps the bottom bar from reserving empty columns.
func _refresh_sections() -> void:
	var seen_visible := false
	for i in range(_ordered_sections.size()):
		var section: Control = _ordered_sections[i]
		var has_content := section.get_child_count() > 0
		if section == _ability_section:
			has_content = not _abilities.is_empty()
		# The portrait section manages its own visibility (multi-select scenes).
		if section != _portrait_section:
			section.visible = has_content
		var section_visible := section.visible and has_content
		if i > 0:
			var sep: VSeparator = _section_separators[i - 1]
			sep.visible = section_visible and seen_visible
		if section_visible:
			seen_visible = true

# --- Stat Bars ---

func add_stat_bar(stat_name: String, color: Color, max_val: float, initial: float) -> void:
	var row := StatRowScene.instantiate() as HBoxContainer
	var label := row.get_node("Label") as Label
	label.add_theme_color_override("font_color", Color(color, 0.8))
	label.text = _format_stat_label(stat_name, initial, max_val)
	var bar := row.get_node("Bar") as ProgressBar
	var pip_mount := row.get_node("PipMount") as HBoxContainer

	if stat_name.to_lower() == "atp":
		bar.visible = false
		pip_mount.visible = true
		var pip_info := _make_pip_strip(int(GameState.ATP_MAX_PIPS), Vector2(8, 10), color, Color(0.06, 0.06, 0.08))
		pip_mount.add_child(pip_info["box"])
		_stat_section.add_child(row)
		_stat_bars[stat_name] = {
			"row": row,
			"label": label,
			"type": "pips",
			"max": GameState.ATP_MAX_PIPS,
			"color": color,
			"pip_info": pip_info,
		}
		_set_pip_strip_value(pip_info, GameState.normalize_atp(initial))
		return

	bar.min_value = 0
	bar.max_value = max_val
	bar.value = initial
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = color

	_stat_section.add_child(row)
	_stat_bars[stat_name] = {
		"row": row,
		"bar": bar,
		"label": label,
		"type": "bar",
		"max": max_val,
		"color": color,
	}

func set_stat(stat_name: String, value: float) -> void:
	if not _stat_bars.has(stat_name):
		return
	var info: Dictionary = _stat_bars[stat_name]
	var max_val: float = float(info.get("max", 100.0))
	var label: Label = info.get("label")
	label.text = _format_stat_label(stat_name, value, max_val)
	if str(info.get("type", "")) == "pips":
		_set_pip_strip_value(info.get("pip_info", {}), GameState.normalize_atp(value))
		return
	var bar: ProgressBar = info.get("bar")
	bar.value = value
	# Color shift when low
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	var ratio := value / max_val if max_val > 0 else 0.0
	if ratio < 0.3:
		fill.bg_color = Color(0.7, 0.3, 0.2)
	elif ratio < 0.6:
		fill.bg_color = Color(0.7, 0.55, 0.2)
	else:
		fill.bg_color = info.get("color", Color.WHITE)

# --- Character Portraits ---

func add_portrait(id: String, display_name: String, color: Color) -> void:
	var card := PortraitScene.instantiate() as PanelContainer
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = Color(color, 0.3)
	var name_label := card.get_node("Content/NameLabel") as Label
	name_label.text = display_name.to_upper()
	name_label.add_theme_color_override("font_color", color)
	var hold_button := card.get_node("Content/HoldButton") as Button
	hold_button.name = "HoldBadge_%s" % id
	hold_button.pressed.connect(_on_portrait_hold_pressed.bind(id))
	var hp_bar := card.get_node("Content/Stats/HP/Bar") as ProgressBar
	var sta_bar := card.get_node("Content/Stats/STA/Bar") as ProgressBar
	var atp_mount := card.get_node("Content/Stats/ATP/PipMount") as HBoxContainer
	var atp_pips := _make_pip_strip(
		int(GameState.ATP_MAX_PIPS), Vector2(4, 3), Color(0.3, 0.6, 0.35), Color(0.05, 0.05, 0.06))
	atp_mount.add_child(atp_pips["box"])
	_set_pip_strip_value(atp_pips, GameState.ATP_MAX_PIPS)
	var stat_bars := {
		"hp": {"type": "bar", "bar": hp_bar},
		"atp": {"type": "pips", "pip_info": atp_pips},
		"sta": {"type": "bar", "bar": sta_bar},
	}

	card.gui_input.connect(_on_portrait_input.bind(id))
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	_portrait_section.add_child(card)
	_portrait_section.visible = true

	_portraits[id] = {
		"card": card,
		"style": style,
		"name_label": name_label,
		"display_name": display_name,
		"color": color,
		"stat_bars": stat_bars,
		"alert": false,
		"status": "",
		"hold_button": hold_button,
		"hold_info": {},
		"hold_locked": false,
	}
	_ensure_ability_owner_column(id, display_name, -1, color, true)

	if _active_portrait == "":
		set_active_portrait(id)

func set_multi_select_enabled(enabled: bool) -> void:
	if _multi_select == enabled:
		return
	_multi_select = enabled
	if _multi_select:
		if _selected_characters.is_empty() and _active_portrait != "":
			_selected_characters = [_active_portrait]
	else:
		_selected_characters.clear()
	_style_all_portraits()
	character_selection_changed.emit(get_selected_ids())

func set_selected_portraits(ids: Array) -> void:
	var next_selected: Array[String] = []
	for raw_id in ids:
		var id := str(raw_id)
		if not _portraits.has(id) or next_selected.has(id):
			continue
		next_selected.append(id)

	if _multi_select:
		if next_selected.is_empty() and _active_portrait != "":
			next_selected = [_active_portrait]
		if not next_selected.is_empty() and not next_selected.has(_active_portrait):
			_active_portrait = next_selected[0]
	else:
		_selected_characters.clear()
		_style_all_portraits()
		return

	if _selected_characters == next_selected:
		_style_all_portraits()
		return

	_selected_characters = next_selected
	_style_all_portraits()
	character_selection_changed.emit(get_selected_ids())

func toggle_portrait_selected(id: String) -> void:
	if not _portraits.has(id):
		return
	if not _multi_select:
		set_active_portrait(id)
		return

	var next_selected := _selected_characters.duplicate()
	if next_selected.has(id):
		if next_selected.size() <= 1:
			return
		next_selected.erase(id)
		if _active_portrait == id:
			_active_portrait = next_selected[0]
	else:
		next_selected.append(id)

	_selected_characters = next_selected
	_style_all_portraits()
	character_selection_changed.emit(get_selected_ids())

func set_active_portrait(id: String, preserve_multi_selection := false) -> void:
	if not _portraits.has(id):
		return
	var prev := _active_portrait
	var prev_selected := _selected_characters.duplicate()
	_active_portrait = id
	if _multi_select:
		if preserve_multi_selection:
			if not _selected_characters.has(id):
				_selected_characters.append(id)
		else:
			_selected_characters = [id]
	if _portraits[id].alert:
		set_portrait_alert(id, false)
	_style_all_portraits()
	if prev != id or prev_selected != _selected_characters:
		character_selection_changed.emit(get_selected_ids())

func get_selected_ids() -> Array:
	if _multi_select:
		var selected := _selected_characters.duplicate()
		if _active_portrait != "" and selected.has(_active_portrait):
			selected.erase(_active_portrait)
			selected.push_front(_active_portrait)
		return selected
	return [_active_portrait] if _active_portrait != "" else []

## Every portrait id the HUD shows — i.e. the selectable party. The SelectionController uses this to
## know which world characters a marquee / click can pick.
func get_portrait_ids() -> Array:
	return _portraits.keys()

func set_portrait_stat(id: String, stat_name: String, value: float) -> void:
	if not _portraits.has(id):
		return
	var bars: Dictionary = _portraits[id].stat_bars
	if bars.has(stat_name):
		var info: Variant = bars[stat_name]
		if info is Dictionary and info.get("type", "") == "pips":
			_set_pip_strip_value(info.get("pip_info", {}), GameState.normalize_atp(value))
		elif info is Dictionary and info.get("type", "") == "bar":
			var bar: ProgressBar = info.get("bar")
			bar.value = value
		elif info is ProgressBar:
			info.value = value

func set_portrait_alert(id: String, alert: bool) -> void:
	if not _portraits.has(id):
		return
	_portraits[id].alert = alert
	_update_portrait_name(id)
	_style_portrait(id)

## A transient "!" bubble above a portrait — the OFFSCREEN alert surface (a
## struck member you can't see = red; the first enemy spotted while your view
## is elsewhere = yellow). Pop, hold, fade, free — never persistent state.
func show_portrait_alert_bubble(id: String, color: Color) -> void:
	if not _portraits.has(id):
		return
	var card: Control = _portraits[id].card
	var old := card.get_node_or_null("AlertBubble")
	if old != null:
		old.queue_free()
	var bubble := preload("res://scenes/ui/portrait_alert_bubble.tscn").instantiate() as Label
	bubble.add_theme_color_override("font_color", color)
	bubble.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bubble.position = Vector2(card.size.x * 0.5 - 6.0, -26.0)
	bubble.scale = Vector2.ONE * 0.2
	bubble.pivot_offset = Vector2(6.0, 24.0)
	card.add_child(bubble)
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "scale", Vector2.ONE, 0.14) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.35)
	tw.tween_callback(bubble.queue_free)

## Brief, source-agnostic damage acknowledgement. The world owns WHAT hurt; the HUD only makes the affected
## portrait unmistakable, then restores the exact selection/status styling that preceded the pulse.
func pulse_portrait_damage(id: String) -> void:
	if not _portraits.has(id):
		return
	var previous: Tween = _portrait_damage_tweens.get(id)
	if previous != null and previous.is_valid():
		previous.kill()
	_style_portrait(id)
	var card: Control = _portraits[id].card
	var resting_modulate := card.modulate
	card.modulate = Color(1.0, 0.3, 0.22, 1.0)
	var tween := create_tween()
	tween.tween_property(card, "modulate", resting_modulate, 0.32)
	_portrait_damage_tweens[id] = tween

func set_portrait_status(id: String, status: String) -> void:
	if not _portraits.has(id):
		return
	_portraits[id].status = status
	_update_portrait_name(id)
	_style_portrait(id)
	if status == "downed":
		set_portrait_hold_state(id, {})
	else:
		_refresh_portrait_hold_badge(id)

## Report or clear the character's current positional work. This is generic on purpose: chunks can
## provide {control_id, kind, label, ...} for plates today and future held/channelled jobs tomorrow.
## A changed/cleared control automatically drops the old rally lock so it cannot leak to a new task.
func set_portrait_hold_state(id: String, hold_info: Dictionary) -> void:
	if not _portraits.has(id):
		return
	var portrait: Dictionary = _portraits[id]
	var previous: Dictionary = portrait.get("hold_info", {})
	var previous_control := str(previous.get("control_id", ""))
	var next_info := hold_info.duplicate(true)
	var next_control := str(next_info.get("control_id", ""))
	var had_lock := bool(portrait.get("hold_locked", false))
	if next_info.is_empty() or previous_control != next_control:
		portrait["hold_locked"] = false
	portrait["hold_info"] = next_info
	_portraits[id] = portrait
	_refresh_portrait_hold_badge(id)
	if had_lock and not bool(portrait.get("hold_locked", false)):
		portrait_hold_lock_changed.emit(id, false)

func set_portrait_hold_locked(id: String, locked: bool) -> void:
	if not _portraits.has(id):
		return
	var portrait: Dictionary = _portraits[id]
	var hold_info: Dictionary = portrait.get("hold_info", {})
	var next_locked := locked and not hold_info.is_empty() and str(portrait.get("status", "")) != "downed"
	if bool(portrait.get("hold_locked", false)) == next_locked:
		_refresh_portrait_hold_badge(id)
		return
	portrait["hold_locked"] = next_locked
	_portraits[id] = portrait
	_refresh_portrait_hold_badge(id)
	portrait_hold_lock_changed.emit(id, next_locked)

func get_hold_locked_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in _portraits.keys():
		var id := str(raw_id)
		var portrait: Dictionary = _portraits[id]
		if (bool(portrait.get("hold_locked", false))
				and not (portrait.get("hold_info", {}) as Dictionary).is_empty()
				and str(portrait.get("status", "")) != "downed"):
			ids.append(id)
	return ids

func get_portrait_hold_state(id: String) -> Dictionary:
	if not _portraits.has(id):
		return {}
	var portrait: Dictionary = _portraits[id]
	var result: Dictionary = (portrait.get("hold_info", {}) as Dictionary).duplicate(true)
	if result.is_empty():
		return result
	result["locked"] = bool(portrait.get("hold_locked", false))
	return result

func _on_portrait_hold_pressed(id: String) -> void:
	if not _portraits.has(id):
		return
	set_portrait_hold_locked(id, not bool(_portraits[id].get("hold_locked", false)))

func _refresh_portrait_hold_badge(id: String) -> void:
	if not _portraits.has(id):
		return
	var portrait: Dictionary = _portraits[id]
	var button: Button = portrait.get("hold_button", null)
	if button == null:
		return
	var hold_info: Dictionary = portrait.get("hold_info", {})
	var active := not hold_info.is_empty() and str(portrait.get("status", "")) != "downed"
	if not active and bool(portrait.get("hold_locked", false)):
		portrait["hold_locked"] = false
		_portraits[id] = portrait
	button.visible = active
	if not active:
		return
	var locked := bool(portrait.get("hold_locked", false))
	var label := str(hold_info.get("label", "HOLD"))
	button.text = "LOCKED" if locked else label.to_upper().left(10)
	button.tooltip_text = (
		"Locked at %s. Click to include this character in whole-party rallies again." % label
		if locked
		else "Holding %s. Click to keep this character here during whole-party rallies." % label
	)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.08, 0.03, 0.96) if locked else Color(0.05, 0.14, 0.12, 0.92)
	style.border_color = Color(1.0, 0.56, 0.22, 0.9) if locked else Color(0.35, 0.9, 0.7, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", style.border_color)

func get_next_portrait_id(current_id: String) -> String:
	var ids := _portraits.keys()
	if ids.size() <= 1:
		return current_id
	var idx := ids.find(current_id)
	return ids[(idx + 1) % ids.size()]

func remove_portrait(id: String) -> void:
	if not _portraits.has(id):
		return
	if _ability_columns.has(id):
		var ability_column: Dictionary = _ability_columns[id]
		if bool(ability_column.get("portrait_backed", false)):
			var column_control: Control = ability_column.get("container", null)
			if column_control != null:
				column_control.visible = false
	_portraits[id].card.queue_free()
	_portraits.erase(id)
	_selected_characters.erase(id)
	if _active_portrait == id:
		_active_portrait = _portraits.keys()[0] if _portraits.size() > 0 else ""
		_style_all_portraits()
	if _portraits.size() == 0:
		_portrait_section.visible = false

func _on_portrait_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if _multi_select and (mouse_event.ctrl_pressed or mouse_event.shift_pressed):
			toggle_portrait_selected(id)
		elif _multi_select and _selected_characters.has(id):
			set_active_portrait(id, true)
		elif _multi_select:
			set_selected_portraits([id])
			set_active_portrait(id, true)
		else:
			set_active_portrait(id)

func _update_portrait_name(id: String) -> void:
	var p: Dictionary = _portraits[id]
	var text: String = str(p.display_name).to_upper()
	match p.status:
		"downed":
			text += "  X"
		"resting":
			text += "  zzz"
		"attacking":
			text += "  !"
		"dragging":
			text += "  ~"
		"":
			if p.alert and id != _active_portrait:
				text += "  !"
		_:
			text += "  " + p.status
	p.name_label.text = text

func _style_all_portraits() -> void:
	for id in _portraits:
		_style_portrait(id)

func _style_portrait(id: String) -> void:
	var p: Dictionary = _portraits[id]
	var is_active := id == _active_portrait and not _multi_select
	var is_selected := id in _selected_characters and _multi_select
	var style: StyleBoxFlat = p.style
	var color: Color = p.color

	if is_active:
		style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		style.border_color = Color(color, 0.7)
		style.set_border_width_all(2)
		p.name_label.add_theme_color_override("font_color", color)
		p.card.modulate.a = 1.0
	elif is_selected:
		style.bg_color = Color(0.1, 0.1, 0.02, 0.95)
		style.border_color = Color(0.9, 0.8, 0.3, 0.7)
		style.set_border_width_all(2)
		p.name_label.add_theme_color_override("font_color", color)
		p.card.modulate.a = 1.0
	else:
		style.bg_color = Color(0.07, 0.07, 0.09, 0.9)
		style.border_color = Color(color, 0.3)
		style.set_border_width_all(1)
		p.name_label.add_theme_color_override("font_color", Color(color, 0.6))
		p.card.modulate.a = 0.7

	if p.alert and not is_active:
		style.bg_color = Color(0.12, 0.12, 0.04, 0.95)
		p.card.modulate.a = 1.0

	match p.status:
		"downed":
			p.name_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25))
		"resting":
			p.name_label.add_theme_color_override("font_color", Color(0.3, 0.7, 0.4))
		"attacking":
			style.bg_color = Color(0.15, 0.04, 0.04, 0.95)
			p.name_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))

func _format_stat_label(stat_name: String, value: float, max_val: float) -> String:
	if stat_name.to_lower() == "atp":
		return "ATP  %s" % GameState.atp_text(value)
	if max_val == 100.0:
		return "%s  %d%%" % [stat_name.to_upper(), int(value)]
	return "%s  %d" % [stat_name.to_upper(), int(value)]

func _make_pip_strip(count: int, pip_size: Vector2, color: Color, off_color: Color) -> Dictionary:
	var box := PipStripScene.instantiate() as HBoxContainer
	var info := {
		"box": box,
		"pips": [] as Array[ColorRect],
		"color": color,
		"off_color": off_color,
		"max": float(count),
		"base_pip_size": pip_size,
		"subdivisions": _atp_pip_subdivisions,
		"value": 0.0,
	}
	_rebuild_pip_strip(info, _atp_pip_subdivisions)
	return info

func _rebuild_pip_strip(pip_info: Dictionary, subdivisions: int) -> void:
	var box: HBoxContainer = pip_info.get("box", null)
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var logical_max := int(pip_info.get("max", 0.0))
	var base_size: Vector2 = pip_info.get("base_pip_size", Vector2(4, 3))
	var sub_size := Vector2(maxf(1.0, base_size.x / float(subdivisions)), base_size.y)
	var off_color: Color = pip_info.get("off_color", Color(0.05, 0.05, 0.06))
	var pips: Array[ColorRect] = []
	for _i in range(logical_max * subdivisions):
		var pip := PipScene.instantiate() as ColorRect
		pip.custom_minimum_size = sub_size
		pip.color = off_color
		box.add_child(pip)
		pips.append(pip)
	pip_info["pips"] = pips
	pip_info["subdivisions"] = subdivisions
	_set_pip_strip_value(pip_info, float(pip_info.get("value", 0.0)))

func _set_pip_strip_value(pip_info: Dictionary, value: float) -> void:
	pip_info["value"] = value
	var subdivisions := int(pip_info.get("subdivisions", 1))
	var max_count := int(pip_info.get("max", 0.0)) * subdivisions
	var filled := int(clampf(roundf(value * float(subdivisions)), 0.0, float(max_count)))
	var color: Color = pip_info.get("color", Color.WHITE)
	var off_color: Color = pip_info.get("off_color", Color(0.05, 0.05, 0.06))
	var pips: Array = pip_info.get("pips", [])
	for i in range(pips.size()):
		var pip: ColorRect = pips[i]
		pip.color = color if i < filled else off_color

# --- Control Buttons ---

func show_run_toggle(initial_running := false, keybind := "") -> void:
	_run_active = initial_running
	# Derive the shown key from the live "run" input map so the label is never a stale literal — rebinding
	# the action (it lives on its OWN key, NOT an ability key) re-labels every scene automatically.
	_run_keybind = str(keybind) if str(keybind) != "" else InputHints.label_for_action("run", "R")
	_run_button = _make_control_button(_run_button_label(), Color(0.3, 0.5, 0.7), "run", _run_keybind)
	_run_button.pressed.connect(_on_run_pressed)
	_control_section.add_child(_run_button)
	_style_run_button()

func set_run_mode(is_running: bool) -> void:
	_run_active = is_running
	_style_run_button()

func _on_run_pressed() -> void:
	if _game_state != null and _auto_toggle_running and _game_state_char_id != "":
		_game_state.toggle_running(_game_state_char_id)
		return
	_run_active = not _run_active
	_style_run_button()
	run_toggled.emit(_run_active)

## Bind this HUD to a GameState so the run toggle and stat bars route through
## the central authority. `char_id` is the character whose stats drive the
## bars (usually the player character in single-character scenes). Pass
## auto_toggle_running=false to keep run_toggled signal-based (for tutorial
## scenes that veto the flip per-step and call set_running manually).
func bind_game_state(game_state: GameState, char_id: String, auto_toggle_running: bool = true) -> void:
	if _game_state != null:
		if _game_state.stat_changed.is_connected(_on_gs_stat_changed):
			_game_state.stat_changed.disconnect(_on_gs_stat_changed)
		if _game_state.running_changed.is_connected(_on_gs_running_changed):
			_game_state.running_changed.disconnect(_on_gs_running_changed)
		for pair in [["item_picked_up", _on_gs_item_pair], ["item_dropped", _on_gs_item_pair],
				["item_exocytosed", _on_gs_item_pair], ["item_endocytosed", _on_gs_item_triple],
				["item_transferred", _on_gs_item_triple]]:
			if _game_state.is_connected(pair[0], pair[1]):
				_game_state.disconnect(pair[0], pair[1])
	_game_state = game_state
	_game_state_char_id = char_id
	_auto_toggle_running = auto_toggle_running
	if _game_state != null:
		_game_state.stat_changed.connect(_on_gs_stat_changed)
		_game_state.running_changed.connect(_on_gs_running_changed)
		_game_state.item_picked_up.connect(_on_gs_item_pair)
		_game_state.item_dropped.connect(_on_gs_item_pair)
		_game_state.item_exocytosed.connect(_on_gs_item_pair)
		_game_state.item_endocytosed.connect(_on_gs_item_triple)
		_game_state.item_transferred.connect(_on_gs_item_triple)
		refresh_hands()
		# Prime the UI from current GameState values so the bars show real
		# numbers even before the first change signal.
		for stat_name in _stat_bars.keys():
			var internal := _hud_stat_name_to_gs(stat_name)
			if internal != "":
				set_stat(stat_name, _game_state.get_stat(char_id, internal))
		set_run_mode(_game_state.is_running(char_id))

## Unbind from GameState on teardown so signals don't fire on freed HUDs.
func unbind_game_state() -> void:
	bind_game_state(null, "")

func _on_gs_item_pair(_char_id: String, _item_id: String) -> void:
	refresh_hands()

func _on_gs_item_triple(_a: String, _b: String, _c: String) -> void:
	refresh_hands()

## Rebuild the bound character's hand-slot chips from GameState (one chip per HELD slot; a
## two-handed item shows once). Empty hands leave the section childless, so it auto-hides.
func refresh_hands() -> void:
	if _hands_section == null:
		return
	for child in _hands_section.get_children():
		child.queue_free()
	if _game_state == null or _game_state_char_id == "" or not _game_state.characters.has(_game_state_char_id):
		return
	var hands: Array = _game_state.characters[_game_state_char_id].get("hands", [null, null])
	var shown := {}
	for slot in hands:
		if slot == null or shown.has(slot):
			continue
		shown[slot] = true
		var item: Dictionary = _game_state.items.get(slot, {})
		var chip := HandChipScene.instantiate() as PanelContainer
		var label := chip.get_node("Label") as Label
		label.text = str(item.get("type", "item")).replace("_", " ").to_upper()
		chip.tooltip_text = "Held: %s" % str(item.get("type", slot))
		_hands_section.add_child(chip)

func _on_gs_stat_changed(char_id: String, stat: String, value: float) -> void:
	if char_id != _game_state_char_id:
		return
	var hud_name := _gs_stat_name_to_hud(stat)
	if hud_name != "" and _stat_bars.has(hud_name):
		set_stat(hud_name, value)
	if _portraits.has(char_id):
		set_portrait_stat(char_id, stat, value)

func _on_gs_running_changed(char_id: String, running: bool) -> void:
	if char_id != _game_state_char_id:
		return
	set_run_mode(running)

## HUD stat-bar IDs are short ("sta", "hp", "atp"); GameState uses full names.
static func _hud_stat_name_to_gs(hud_name: String) -> String:
	match hud_name:
		"sta": return "stamina"
		"hp": return "hp"
		"atp": return "atp"
	return ""

static func _gs_stat_name_to_hud(gs_name: String) -> String:
	match gs_name:
		"stamina": return "sta"
		"hp": return "hp"
		"atp": return "atp"
	return ""

func _style_run_button() -> void:
	if not _run_button:
		return
	_run_button.text = _run_button_label()
	var style: StyleBoxFlat = _run_button.get_theme_stylebox("normal")
	if _run_active:
		style.bg_color = Color(0.08, 0.12, 0.2, 0.9)
		style.border_color = Color(0.3, 0.5, 0.8, 0.6)
		_run_button.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	else:
		style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		style.border_color = Color(0.2, 0.2, 0.25, 0.4)
		_run_button.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))

func _run_button_label() -> String:
	return "RUN" if _run_active else "WALK"

func show_routing_toggle(initial_mode := "safe") -> void:
	_routing_mode = initial_mode
	_routing_button = _make_control_button("SAFE", Color(0.3, 0.6, 0.4), "route", "Tab")
	_routing_button.pressed.connect(_on_routing_pressed)
	_control_section.add_child(_routing_button)
	_style_routing_button()

func set_routing_mode(mode: String) -> void:
	_routing_mode = mode
	_style_routing_button()

func _on_routing_pressed() -> void:
	_routing_mode = "direct" if _routing_mode == "safe" else "safe"
	_style_routing_button()
	routing_toggled.emit(_routing_mode)

func _style_routing_button() -> void:
	if not _routing_button:
		return
	if _routing_mode == "safe":
		_routing_button.text = "SAFE"
		var style: StyleBoxFlat = _routing_button.get_theme_stylebox("normal")
		style.bg_color = Color(0.04, 0.1, 0.06, 0.9)
		style.border_color = Color(0.2, 0.5, 0.3, 0.5)
		_routing_button.add_theme_color_override("font_color", Color(0.3, 0.7, 0.4))
	else:
		_routing_button.text = "DIRECT"
		var style: StyleBoxFlat = _routing_button.get_theme_stylebox("normal")
		style.bg_color = Color(0.12, 0.04, 0.04, 0.9)
		style.border_color = Color(0.5, 0.2, 0.15, 0.5)
		_routing_button.add_theme_color_override("font_color", Color(0.8, 0.3, 0.2))

func show_pause_toggle(initial_paused := false) -> void:
	_paused = initial_paused
	_pause_button = _make_control_button(
		"PAUSED" if _paused else "PAUSE",
		Color(0.6, 0.5, 0.3),
		"pause",
		"Space"
	)
	_pause_button.pressed.connect(_on_pause_pressed)
	_control_section.add_child(_pause_button)
	_style_pause_button()

func set_paused(is_paused: bool) -> void:
	_paused = is_paused
	_style_pause_button()

func _on_pause_pressed() -> void:
	_paused = not _paused
	_style_pause_button()
	pause_toggled.emit(_paused)

func _style_pause_button() -> void:
	if not _pause_button:
		return
	_pause_button.text = "PAUSED" if _paused else "PAUSE"
	var style: StyleBoxFlat = _pause_button.get_theme_stylebox("normal")
	if _paused:
		style.bg_color = Color(0.15, 0.1, 0.03, 0.9)
		style.border_color = Color(0.7, 0.5, 0.2, 0.6)
		_pause_button.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	else:
		style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		style.border_color = Color(0.3, 0.25, 0.15, 0.4)
		_pause_button.add_theme_color_override("font_color", Color(0.5, 0.4, 0.3))

## Add a momentary "center camera on the party" button to the controls section. Opt-in per scene —
## a scene calls this alongside show_pause_toggle/show_run_toggle. Key and click share one handler.
func show_center_camera_button(keybind := "P") -> void:
	_center_button = _make_control_button("CENTER", Color(0.4, 0.6, 0.72), "camera_center", str(keybind))
	_center_button.pressed.connect(_on_center_camera_pressed)
	_control_section.add_child(_center_button)

func _on_center_camera_pressed() -> void:
	center_camera_requested.emit()

# --- Abilities ---

## The drawer is expanded on desktop and collapsed on touchscreens by default. Hosts may override that
## decision without knowing anything about its controls (useful for tutorials and saved UI preferences).
func set_ability_drawer_expanded(expanded: bool) -> void:
	_ability_drawer_expanded = expanded
	_refresh_ability_drawer()

func toggle_ability_drawer() -> bool:
	set_ability_drawer_expanded(not _ability_drawer_expanded)
	return _ability_drawer_expanded

func get_ability_drawer_expanded() -> bool:
	return _ability_drawer_expanded

func get_ability_drawer_state() -> Dictionary:
	var columns: Array = []
	for owner_id in _sorted_ability_owner_ids():
		var info: Dictionary = _ability_columns[owner_id]
		var container: Control = info.get("container", null)
		if container == null or not container.visible:
			continue
		columns.append({
			"owner": owner_id,
			"display_name": str(info.get("display_name", "")),
			"party_slot": int(info.get("party_slot", -1)),
			"ability_ids": (info.get("ability_ids", []) as Array).duplicate(),
		})
	return {
		"expanded": _ability_drawer_expanded,
		"max_columns": MAX_ABILITY_COLUMNS,
		"rows_per_column": ABILITIES_PER_CHARACTER,
		"overflow_strategy": "horizontal_scroll",
		"scroll_view_width": _ability_drawer_scroll.size.x if _ability_drawer_scroll != null else 0.0,
		"content_width": _ability_drawer_columns.size.x if _ability_drawer_columns != null else 0.0,
		"columns": columns,
	}

func _refresh_ability_drawer() -> void:
	if _ability_drawer_scroll != null:
		_ability_drawer_scroll.visible = _ability_drawer_expanded
		if _ability_drawer_columns != null:
			_ability_drawer_columns.visible = true
	elif _ability_drawer_columns != null:
		_ability_drawer_columns.visible = _ability_drawer_expanded
	if _ability_drawer_toggle != null:
		_ability_drawer_toggle.text = "ABILITIES  HIDE" if _ability_drawer_expanded else "ABILITIES  SHOW"
		_ability_drawer_toggle.tooltip_text = (
			"Collapse the party ability drawer."
			if _ability_drawer_expanded
			else "Show the party's direct ability buttons."
		)
	if _bottom_margin != null:
		var drawer_open := _ability_drawer_expanded and not _abilities.is_empty()
		_bottom_margin.offset_top = -(BOTTOM_BAR_DRAWER_HEIGHT if drawer_open else BOTTOM_BAR_COLLAPSED_HEIGHT)
	if not _ordered_sections.is_empty():
		_refresh_sections()

func _sync_ability_portrait_columns() -> void:
	for raw_id in _portraits.keys():
		var portrait_id := str(raw_id)
		var portrait: Dictionary = _portraits[portrait_id]
		_ensure_ability_owner_column(
			portrait_id,
			str(portrait.get("display_name", portrait_id.capitalize())),
			-1,
			portrait.get("color", Color(0.55, 0.62, 0.7)),
			true
		)

func _infer_ability_owner(ability_id: String) -> String:
	var normalized := ability_id.to_lower()
	for raw_id in _portraits.keys():
		var portrait_id := str(raw_id)
		var prefix := portrait_id.to_lower()
		if normalized == prefix or normalized.begins_with(prefix + "_") or normalized.begins_with(prefix + "."):
			return portrait_id
	if _active_portrait != "":
		return _active_portrait
	if _game_state_char_id != "":
		return _game_state_char_id
	return "party"

func _next_ability_party_slot(requested: int) -> int:
	var used := {}
	for info_value in _ability_columns.values():
		var info: Dictionary = info_value
		used[int(info.get("party_slot", -1))] = true
	if requested >= 0 and requested < MAX_ABILITY_COLUMNS and not used.has(requested):
		return requested
	for slot in range(MAX_ABILITY_COLUMNS):
		if not used.has(slot):
			return slot
	return -1

func _ensure_ability_owner_column(
	owner_id: String,
	owner_display: String,
	party_slot: int,
	color: Color,
	portrait_backed := false
) -> Dictionary:
	if _ability_drawer_columns == null or owner_id == "":
		return {}
	if _ability_columns.has(owner_id):
		var existing: Dictionary = _ability_columns[owner_id]
		var existing_label: Label = existing.get("label", null)
		if owner_display != "":
			existing["display_name"] = owner_display
			if existing_label != null:
				existing_label.text = owner_display.to_upper()
		if party_slot >= 0 and party_slot < MAX_ABILITY_COLUMNS:
			existing["party_slot"] = party_slot
		existing["portrait_backed"] = bool(existing.get("portrait_backed", false)) or portrait_backed
		var existing_container: Control = existing.get("container", null)
		if existing_container != null:
			existing_container.visible = true
		_ability_columns[owner_id] = existing
		_sort_ability_columns()
		return existing
	if _ability_columns.size() >= MAX_ABILITY_COLUMNS:
		push_warning("GameHUD supports at most %d ability-owner columns; ignoring '%s'." % [MAX_ABILITY_COLUMNS, owner_id])
		return {}
	var resolved_party_slot := _next_ability_party_slot(party_slot)
	if resolved_party_slot < 0:
		return {}
	var resolved_display := owner_display.strip_edges()
	if resolved_display == "":
		resolved_display = owner_id.replace("_", " ").capitalize()
	var column := AbilityColumnScene.instantiate() as VBoxContainer
	column.name = "AbilityColumn_%s" % owner_id
	var label := column.get_node("OwnerLabel") as Label
	label.text = resolved_display.to_upper()
	label.add_theme_color_override("font_color", Color(color, 0.78))
	var slot_buttons: Array[Button] = []
	var ability_ids: Array[String] = []
	for ability_slot in range(ABILITIES_PER_CHARACTER):
		var placeholder := _make_empty_ability_button(ability_slot)
		column.add_child(placeholder)
		slot_buttons.append(placeholder)
		ability_ids.append("")
	_ability_drawer_columns.add_child(column)
	_ability_column_serial += 1
	var info := {
		"container": column,
		"label": label,
		"display_name": resolved_display,
		"party_slot": resolved_party_slot,
		"serial": _ability_column_serial,
		"slot_buttons": slot_buttons,
		"ability_ids": ability_ids,
		"portrait_backed": portrait_backed,
	}
	_ability_columns[owner_id] = info
	_sort_ability_columns()
	return info

func _make_empty_ability_button(slot: int) -> Button:
	var button := _make_control_button("EMPTY", Color(0.22, 0.24, 0.29))
	button.name = "EmptyAbility_%d" % slot
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(108.0, 27.0)
	button.tooltip_text = "No direct ability assigned to slot %d." % (slot + 1)
	var disabled_style := (button.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
	disabled_style.bg_color = Color(0.035, 0.038, 0.05, 0.72)
	disabled_style.border_color = Color(0.16, 0.17, 0.21, 0.4)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_disabled_color", Color(0.3, 0.31, 0.35))
	return button

func _sorted_ability_owner_ids() -> Array[String]:
	var owners: Array[String] = []
	for raw_id in _ability_columns.keys():
		owners.append(str(raw_id))
	owners.sort_custom(func(a: String, b: String) -> bool:
		var ai: Dictionary = _ability_columns[a]
		var bi: Dictionary = _ability_columns[b]
		var a_slot := int(ai.get("party_slot", MAX_ABILITY_COLUMNS))
		var b_slot := int(bi.get("party_slot", MAX_ABILITY_COLUMNS))
		if a_slot != b_slot:
			return a_slot < b_slot
		return int(ai.get("serial", 0)) < int(bi.get("serial", 0))
	)
	return owners

func _sort_ability_columns() -> void:
	if _ability_drawer_columns == null:
		return
	var index := 0
	for owner_id in _sorted_ability_owner_ids():
		var column: Control = (_ability_columns[owner_id] as Dictionary).get("container", null)
		if column == null:
			continue
		_ability_drawer_columns.move_child(column, index)
		index += 1

func _choose_ability_slot(column_info: Dictionary, requested: int) -> int:
	var ability_ids: Array = column_info.get("ability_ids", [])
	if requested >= ABILITIES_PER_CHARACTER:
		push_warning("Ability slots are zero-based 0..%d; got %d." % [ABILITIES_PER_CHARACTER - 1, requested])
		return -1
	if requested >= 0 and str(ability_ids[requested]) == "":
		return requested
	for slot in range(ABILITIES_PER_CHARACTER):
		if str(ability_ids[slot]) == "":
			return slot
	return -1

## Backward-compatible first five arguments; the optional metadata places this direct action in one of
## six party columns and one of two zero-based rows. Without owner metadata, portrait-id prefixes are inferred.
func clear_abilities() -> void:
	# Preview chunks can be regenerated in place. Ability ownership belongs to the
	# current chunk, so remove both the registry and its generated columns before
	# registering the next contract.
	_abilities.clear()
	_ability_columns.clear()
	_ability_column_serial = 0
	if _ability_drawer_columns != null:
		for child in _ability_drawer_columns.get_children():
			_ability_drawer_columns.remove_child(child)
			child.queue_free()
	_sync_ability_portrait_columns()
	_refresh_ability_drawer()


func add_ability(
	id: String,
	display_name: String,
	keybind: String,
	color: Color,
	input_action := "",
	owner := "",
	owner_display := "",
	party_slot := -1,
	ability_slot := -1
) -> void:
	if _abilities.has(id):
		push_warning("GameHUD ability '%s' is already registered." % id)
		return
	var resolved_action := str(input_action)
	if resolved_action == "" and InputMap.has_action(id):
		resolved_action = id
	var resolved_keybind := (
		InputHints.label_for_action(resolved_action, keybind)
		if resolved_action != ""
		else keybind
	)
	_sync_ability_portrait_columns()
	var resolved_owner := str(owner).strip_edges()
	if resolved_owner == "":
		resolved_owner = _infer_ability_owner(id)
	var resolved_owner_display := str(owner_display).strip_edges()
	if resolved_owner_display == "" and _portraits.has(resolved_owner):
		resolved_owner_display = str((_portraits[resolved_owner] as Dictionary).get("display_name", ""))
	var column_info := _ensure_ability_owner_column(
		resolved_owner,
		resolved_owner_display,
		int(party_slot),
		color,
		_portraits.has(resolved_owner)
	)
	if column_info.is_empty():
		return
	var resolved_ability_slot := _choose_ability_slot(column_info, int(ability_slot))
	if resolved_ability_slot < 0:
		push_warning("Ability owner '%s' already has two direct abilities; ignoring '%s'." % [resolved_owner, id])
		return
	var btn := _make_control_button(display_name, color, resolved_action, resolved_keybind)
	btn.name = "Ability_%s" % id
	btn.custom_minimum_size.y = 27.0
	btn.pressed.connect(func(): ability_pressed.emit(id))
	var slot_buttons: Array = column_info.get("slot_buttons", [])
	var placeholder: Button = slot_buttons[resolved_ability_slot]
	var column: VBoxContainer = column_info.get("container", null)
	var insert_index := placeholder.get_index()
	column.remove_child(placeholder)
	placeholder.queue_free()
	column.add_child(btn)
	column.move_child(btn, insert_index)
	slot_buttons[resolved_ability_slot] = btn
	var column_ability_ids: Array = column_info.get("ability_ids", [])
	column_ability_ids[resolved_ability_slot] = id
	column_info["slot_buttons"] = slot_buttons
	column_info["ability_ids"] = column_ability_ids
	_ability_columns[resolved_owner] = column_info
	_abilities[id] = {
		"button": btn,
		"display_name": display_name,
		"keybind": resolved_keybind,
		"input_action": resolved_action,
		"color": color,
		"state": "ready",
		"remaining": 0.0,
		"owner": resolved_owner,
		"owner_display": str(column_info.get("display_name", resolved_owner_display)),
		"party_slot": int(column_info.get("party_slot", -1)),
		"ability_slot": resolved_ability_slot,
	}
	_style_ability_button(id)
	_refresh_ability_drawer()

func set_ability_state(id: String, state: String, remaining: float = 0.0) -> void:
	if not _abilities.has(id):
		return
	var ab: Dictionary = _abilities[id]
	ab.state = state
	ab.remaining = remaining
	_update_ability_label(id)
	_style_ability_button(id)

func _update_ability_label(id: String) -> void:
	var ab: Dictionary = _abilities[id]
	var btn: Button = ab.button
	match ab.state:
		"active":
			btn.text = "%s  %ds" % [ab.display_name, ceili(ab.remaining)]
		"cooldown":
			btn.text = "%s  (%ds)" % [ab.display_name, ceili(ab.remaining)]
		"queued":
			btn.text = "%s  >>>" % ab.display_name
		_:
			btn.text = ab.display_name

func _style_ability_button(id: String) -> void:
	var ab: Dictionary = _abilities[id]
	var btn: Button = ab.button
	btn.disabled = ab.state == "disabled"
	var style_name := "disabled" if btn.disabled else "normal"
	var style: StyleBoxFlat = btn.get_theme_stylebox(style_name)
	var font_color := Color(ab.color, 0.7)
	match ab.state:
		"active":
			style.bg_color = Color(ab.color.darkened(0.5), 0.9)
			style.border_color = Color(ab.color, 0.7)
			font_color = Color(ab.color, 0.95)
		"cooldown":
			style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
			style.border_color = Color(ab.color, 0.2)
			font_color = Color(ab.color, 0.35)
		"queued":
			style.bg_color = Color(ab.color.darkened(0.6), 0.9)
			style.border_color = Color(ab.color, 0.8)
			font_color = Color(ab.color, 0.9)
		"disabled":
			style.bg_color = Color(0.05, 0.05, 0.06, 0.9)
			style.border_color = Color(0.12, 0.12, 0.15, 0.3)
			font_color = Color(0.25, 0.25, 0.3)
		_:  # ready
			style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
			style.border_color = Color(ab.color, 0.4)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)

# --- Time Bar ---

func show_time(day: int, time_of_day: float) -> void:
	_time_container.visible = true
	set_time(day, time_of_day)

func set_time(day: int, time_of_day: float) -> void:
	_time_bar.value = time_of_day * 100.0
	var tod: String
	if time_of_day < 0.15: tod = "Morning"
	elif time_of_day < 0.3: tod = "Afternoon"
	elif time_of_day < 0.4: tod = "Evening"
	elif time_of_day < 0.5: tod = "Dusk"
	else: tod = "NIGHT"
	_time_label.text = "Day %d  %s" % [day, tod]
	# Color shift
	var fill: StyleBoxFlat = _time_bar.get_theme_stylebox("fill")
	if time_of_day >= 0.5:
		_time_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.15))
		fill.bg_color = Color(0.5, 0.15, 0.1)
	elif time_of_day >= 0.4:
		_time_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.2))
		fill.bg_color = Color(0.7, 0.4, 0.15)
	else:
		_time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		fill.bg_color = Color(0.7, 0.5, 0.2)

func hide_time() -> void:
	_time_container.visible = false

# --- Messages ---

func show_message(text: String, duration := 2.0) -> void:
	_message_generation += 1
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()

	_message_label.text = text
	_message_timer = duration
	_message_label.modulate.a = 0.2
	_message_backing.modulate.a = 0.0
	_set_message_drop(-6.0)

	var generation := _message_generation
	_message_tween = create_tween().set_parallel(true)
	_message_tween.tween_property(_message_label, "modulate:a", 0.92, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_message_tween.tween_property(_message_backing, "modulate:a", 0.86, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_message_tween.tween_method(_set_message_drop, -6.0, 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.finished.connect(func() -> void:
		if generation == _message_generation:
			_message_tween = null
	)

func _fade_message(generation: int) -> void:
	if generation != _message_generation:
		return
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween().set_parallel(true)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_message_tween.tween_property(_message_backing, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_message_tween.tween_method(_set_message_drop, 0.0, -2.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_message_tween.finished.connect(func() -> void:
		if generation != _message_generation:
			return
		_message_label.modulate.a = 0.0
		_message_backing.modulate.a = 0.0
		_message_tween = null
	)

func _set_message_drop(offset: float) -> void:
	_message_backing.offset_top = 34.0 + offset
	_message_backing.offset_bottom = 68.0 + offset
	_message_label.offset_top = 40.0 + offset
	_message_label.offset_bottom = 66.0 + offset

# --- Helpers ---

func _make_control_button(
	text: String,
	color: Color,
	input_action: String = "",
	fallback_keybind: String = ""
) -> Button:
	var btn := ControlButtonScene.instantiate() as Button
	btn.text = text
	_apply_control_button_style(btn, color, input_action, fallback_keybind)
	return btn

func _apply_control_button_style(
	btn: Button,
	color: Color,
	input_action: String = "",
	fallback_keybind: String = ""
) -> void:
	btn.add_theme_font_size_override("font_size", 11)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
	style.border_color = Color(color, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", style)
	# Hover
	var hover := style.duplicate()
	hover.border_color = Color(color, 0.6)
	btn.add_theme_stylebox_override("hover", hover)
	# Pressed
	var pressed := style.duplicate()
	pressed.bg_color = Color(color, 0.15)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := style.duplicate()
	disabled.bg_color = Color(0.045, 0.045, 0.055, 0.82)
	disabled.border_color = Color(color, 0.18)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color(color, 0.7))
	btn.add_theme_color_override("font_disabled_color", Color(color, 0.3))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if input_action != "" or fallback_keybind != "":
		var glyph := InputGlyphScene.instantiate() as InputGlyph
		if input_action != "":
			glyph.configure_action(input_action, fallback_keybind)
		else:
			glyph.configure_key_label(fallback_keybind)
		glyph.attach_to_button(btn)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.x = maxf(btn.custom_minimum_size.x, 56.0 + glyph.custom_minimum_size.x)
		for state in ["normal", "hover", "pressed"]:
			var state_style := btn.get_theme_stylebox(state) as StyleBoxFlat
			if state_style != null:
				state_style.content_margin_right = glyph.custom_minimum_size.x + 12.0
