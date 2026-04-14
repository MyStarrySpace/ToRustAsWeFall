extends CanvasLayer

const SurvivalStats = preload("res://scripts/game/survival_stats.gd")

## Unified game HUD. Sequences configure which elements are visible.
## Matches the React prototype layout: stat bars left, controls center,
## abilities right, time bar top, messages top-center.

signal run_toggled(is_running: bool)
signal routing_toggled(mode: String)
signal ability_pressed(ability_name: String)
signal pause_toggled(is_paused: bool)
signal character_selection_changed(selected_ids: Array)

var _bottom_panel: PanelContainer
var _stat_section: VBoxContainer
var _control_section: HBoxContainer
var _ability_section: VBoxContainer
var _time_container: HBoxContainer
var _time_label: Label
var _time_bar: ProgressBar
var _message_label: Label
var _message_timer := 0.0

# Control buttons
var _run_button: Button
var _routing_button: Button
var _pause_button: Button
var _run_active := false
var _routing_mode := "safe"
var _paused := false

# Tracked state
var _stat_bars: Dictionary = {}
var _abilities: Dictionary = {}

# Character portraits
var _portrait_section: HBoxContainer
var _portraits: Dictionary = {}  # id -> {card, style, name_label, display_name, color, stat_bars, alert, status}
var _selected_characters: Array[String] = []
var _active_portrait := ""
var _multi_select := false

func _ready() -> void:
	layer = 10
	_build_bottom_bar()
	_build_time_bar()
	_build_message_area()

func _process(delta: float) -> void:
	if _message_timer > 0:
		_message_timer -= delta
		if _message_timer <= 0:
			_message_label.modulate.a = 0.0

func _build_bottom_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -64
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	_bottom_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.92)
	style.border_color = Color(0.15, 0.15, 0.2, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	_bottom_panel.add_theme_stylebox_override("panel", style)
	margin.add_child(_bottom_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_panel.add_child(hbox)

	# Far left: character portraits
	_portrait_section = HBoxContainer.new()
	_portrait_section.add_theme_constant_override("separation", 4)
	_portrait_section.visible = false
	hbox.add_child(_portrait_section)

	# Left: stat bars
	_stat_section = VBoxContainer.new()
	_stat_section.add_theme_constant_override("separation", 3)
	_stat_section.custom_minimum_size.x = 160
	hbox.add_child(_stat_section)

	# Center: control buttons
	_control_section = HBoxContainer.new()
	_control_section.add_theme_constant_override("separation", 6)
	_control_section.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_control_section)

	# Right: ability buttons
	_ability_section = VBoxContainer.new()
	_ability_section.add_theme_constant_override("separation", 4)
	_ability_section.custom_minimum_size.x = 140
	hbox.add_child(_ability_section)

func _build_time_bar() -> void:
	_time_container = HBoxContainer.new()
	_time_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_container.offset_top = 10
	_time_container.offset_left = -140
	_time_container.offset_right = 140
	_time_container.offset_bottom = 30
	_time_container.add_theme_constant_override("separation", 8)
	_time_container.visible = false
	add_child(_time_container)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_time_label.custom_minimum_size.x = 90
	_time_container.add_child(_time_label)

	_time_bar = ProgressBar.new()
	_time_bar.min_value = 0
	_time_bar.max_value = 100
	_time_bar.show_percentage = false
	_time_bar.custom_minimum_size = Vector2(140, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.08)
	bg.set_corner_radius_all(2)
	_time_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.7, 0.5, 0.2)
	fill.set_corner_radius_all(2)
	_time_bar.add_theme_stylebox_override("fill", fill)
	_time_container.add_child(_time_bar)

func _build_message_area() -> void:
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.offset_top = 40
	_message_label.offset_left = -300
	_message_label.offset_right = 300
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 12)
	_message_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	_message_label.modulate.a = 0.0
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message_label)

# --- Stat Bars ---

func add_stat_bar(stat_name: String, color: Color, max_val: float, initial: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(color, 0.8))
	label.custom_minimum_size.x = 65
	label.text = _format_stat_label(stat_name, initial, max_val)
	row.add_child(label)

	if stat_name.to_lower() == "atp":
		var pip_info := _make_pip_strip(int(SurvivalStats.ATP_MAX_PIPS), Vector2(8, 10), color, Color(0.06, 0.06, 0.08))
		row.add_child(pip_info["box"])
		_stat_section.add_child(row)
		_stat_bars[stat_name] = {
			"row": row,
			"label": label,
			"type": "pips",
			"max": SurvivalStats.ATP_MAX_PIPS,
			"color": color,
			"pip_info": pip_info,
		}
		_set_pip_strip_value(pip_info, SurvivalStats.normalize_atp(initial))
		return

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max_val
	bar.value = initial
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(80, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.08)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

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
		_set_pip_strip_value(info.get("pip_info", {}), SurvivalStats.normalize_atp(value))
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
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(80, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.9)
	style.border_color = Color(color, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = display_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 1)
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stats_box)

	var stat_bars := {}
	for stat_def in [["hp", "HP", Color(0.7, 0.3, 0.25)], ["atp", "ATP", Color(0.3, 0.6, 0.35)], ["sta", "STA", Color(0.3, 0.5, 0.7)]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var lbl := Label.new()
		lbl.text = stat_def[1]
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
		lbl.custom_minimum_size.x = 18
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)

		if stat_def[0] == "atp":
			var pip_info := _make_pip_strip(int(SurvivalStats.ATP_MAX_PIPS), Vector2(4, 3), stat_def[2], Color(0.05, 0.05, 0.06))
			var pip_box: HBoxContainer = pip_info["box"]
			pip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pip_box)
			stats_box.add_child(row)
			stat_bars[stat_def[0]] = {
				"type": "pips",
				"pip_info": pip_info,
			}
			_set_pip_strip_value(pip_info, SurvivalStats.ATP_MAX_PIPS)
			continue

		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = 100
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(45, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.05, 0.06)
		bg.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = stat_def[2]
		fill.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)

		stats_box.add_child(row)
		stat_bars[stat_def[0]] = {
			"type": "bar",
			"bar": bar,
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
	}

	if _active_portrait == "":
		set_active_portrait(id)

func set_active_portrait(id: String) -> void:
	if not _portraits.has(id):
		return
	var prev := _active_portrait
	_active_portrait = id
	if _portraits[id].alert:
		set_portrait_alert(id, false)
	_style_all_portraits()
	if prev != id:
		character_selection_changed.emit(get_selected_ids())

func get_selected_ids() -> Array:
	if _multi_select:
		return _selected_characters.duplicate()
	return [_active_portrait] if _active_portrait != "" else []

func set_portrait_stat(id: String, stat_name: String, value: float) -> void:
	if not _portraits.has(id):
		return
	var bars: Dictionary = _portraits[id].stat_bars
	if bars.has(stat_name):
		var info: Variant = bars[stat_name]
		if info is Dictionary and info.get("type", "") == "pips":
			_set_pip_strip_value(info.get("pip_info", {}), SurvivalStats.normalize_atp(value))
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

func set_portrait_status(id: String, status: String) -> void:
	if not _portraits.has(id):
		return
	_portraits[id].status = status
	_update_portrait_name(id)
	_style_portrait(id)

func get_next_portrait_id(current_id: String) -> String:
	var ids := _portraits.keys()
	if ids.size() <= 1:
		return current_id
	var idx := ids.find(current_id)
	return ids[(idx + 1) % ids.size()]

func remove_portrait(id: String) -> void:
	if not _portraits.has(id):
		return
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
		return "ATP  %s" % SurvivalStats.atp_text(value)
	if max_val == 100.0:
		return "%s  %d%%" % [stat_name.to_upper(), int(value)]
	return "%s  %d" % [stat_name.to_upper(), int(value)]

func _make_pip_strip(count: int, pip_size: Vector2, color: Color, off_color: Color) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var pips: Array[ColorRect] = []
	for _i in range(count):
		var pip := ColorRect.new()
		pip.custom_minimum_size = pip_size
		pip.color = off_color
		box.add_child(pip)
		pips.append(pip)
	return {
		"box": box,
		"pips": pips,
		"color": color,
		"off_color": off_color,
		"max": float(count),
	}

func _set_pip_strip_value(pip_info: Dictionary, value: float) -> void:
	var max_count := int(pip_info.get("max", 0.0))
	var filled := int(clampf(roundf(value), 0.0, float(max_count)))
	var color: Color = pip_info.get("color", Color.WHITE)
	var off_color: Color = pip_info.get("off_color", Color(0.05, 0.05, 0.06))
	var pips: Array = pip_info.get("pips", [])
	for i in range(pips.size()):
		var pip: ColorRect = pips[i]
		pip.color = color if i < filled else off_color

# --- Control Buttons ---

func show_run_toggle(initial_running := false) -> void:
	_run_active = initial_running
	_run_button = _make_control_button(
		"RUN  Z" if _run_active else "WALK  Z",
		Color(0.3, 0.5, 0.7)
	)
	_run_button.pressed.connect(_on_run_pressed)
	_control_section.add_child(_run_button)
	_style_run_button()

func set_run_mode(is_running: bool) -> void:
	_run_active = is_running
	_style_run_button()

func _on_run_pressed() -> void:
	_run_active = not _run_active
	_style_run_button()
	run_toggled.emit(_run_active)

func _style_run_button() -> void:
	if not _run_button:
		return
	_run_button.text = "RUN  Z" if _run_active else "WALK  Z"
	var style: StyleBoxFlat = _run_button.get_theme_stylebox("normal")
	if _run_active:
		style.bg_color = Color(0.08, 0.12, 0.2, 0.9)
		style.border_color = Color(0.3, 0.5, 0.8, 0.6)
		_run_button.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	else:
		style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		style.border_color = Color(0.2, 0.2, 0.25, 0.4)
		_run_button.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))

func show_routing_toggle(initial_mode := "safe") -> void:
	_routing_mode = initial_mode
	_routing_button = _make_control_button("SAFE  Tab", Color(0.3, 0.6, 0.4))
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
		_routing_button.text = "SAFE  Tab"
		var style: StyleBoxFlat = _routing_button.get_theme_stylebox("normal")
		style.bg_color = Color(0.04, 0.1, 0.06, 0.9)
		style.border_color = Color(0.2, 0.5, 0.3, 0.5)
		_routing_button.add_theme_color_override("font_color", Color(0.3, 0.7, 0.4))
	else:
		_routing_button.text = "DIRECT  Tab"
		var style: StyleBoxFlat = _routing_button.get_theme_stylebox("normal")
		style.bg_color = Color(0.12, 0.04, 0.04, 0.9)
		style.border_color = Color(0.5, 0.2, 0.15, 0.5)
		_routing_button.add_theme_color_override("font_color", Color(0.8, 0.3, 0.2))

func show_pause_toggle(initial_paused := false) -> void:
	_paused = initial_paused
	_pause_button = _make_control_button(
		"PAUSED  Space" if _paused else "PAUSE  Space",
		Color(0.6, 0.5, 0.3)
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
	_pause_button.text = "PAUSED  Space" if _paused else "PAUSE  Space"
	var style: StyleBoxFlat = _pause_button.get_theme_stylebox("normal")
	if _paused:
		style.bg_color = Color(0.15, 0.1, 0.03, 0.9)
		style.border_color = Color(0.7, 0.5, 0.2, 0.6)
		_pause_button.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	else:
		style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		style.border_color = Color(0.3, 0.25, 0.15, 0.4)
		_pause_button.add_theme_color_override("font_color", Color(0.5, 0.4, 0.3))

# --- Abilities ---

func add_ability(id: String, display_name: String, keybind: String, color: Color) -> void:
	var btn := _make_control_button("%s  %s" % [display_name, keybind], color)
	btn.pressed.connect(func(): ability_pressed.emit(id))
	_ability_section.add_child(btn)
	_abilities[id] = {
		"button": btn,
		"display_name": display_name,
		"keybind": keybind,
		"color": color,
		"state": "ready",
		"remaining": 0.0,
	}

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
			btn.text = "%s  %s" % [ab.display_name, ab.keybind]

func _style_ability_button(id: String) -> void:
	var ab: Dictionary = _abilities[id]
	var btn: Button = ab.button
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal")
	match ab.state:
		"active":
			style.bg_color = Color(ab.color.darkened(0.5), 0.9)
			style.border_color = Color(ab.color, 0.7)
			btn.add_theme_color_override("font_color", Color(ab.color, 0.95))
		"cooldown":
			style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
			style.border_color = Color(ab.color, 0.2)
			btn.add_theme_color_override("font_color", Color(ab.color, 0.35))
		"queued":
			style.bg_color = Color(ab.color.darkened(0.6), 0.9)
			style.border_color = Color(ab.color, 0.8)
			btn.add_theme_color_override("font_color", Color(ab.color, 0.9))
		"disabled":
			style.bg_color = Color(0.05, 0.05, 0.06, 0.9)
			style.border_color = Color(0.12, 0.12, 0.15, 0.3)
			btn.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
		_:  # ready
			style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
			style.border_color = Color(ab.color, 0.4)
			btn.add_theme_color_override("font_color", Color(ab.color, 0.7))

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
	_message_label.text = text
	_message_label.modulate.a = 0.85
	_message_timer = duration

# --- Helpers ---

func _make_control_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
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
	btn.add_theme_color_override("font_color", Color(color, 0.7))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn
