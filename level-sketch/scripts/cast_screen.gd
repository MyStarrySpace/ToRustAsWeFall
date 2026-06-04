extends Control

## The Cast: enable/disable the playable characters. Aster + Peris are permanent (the
## minimum pair). Disabling a character removes its capabilities from the full-party route —
## the live banner shows when you've dropped the combat specialist (so redirect / gauntlet /
## exploit beats fall to the harder Aster+Peris path). Saves to user://roster.json.

var _enabled: Array = []
var _status: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_enabled = CharacterRoster.load_enabled()
	_build_ui()
	if "--shot" in OS.get_cmdline_user_args():
		_capture_preview()


func _capture_preview() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://cast_preview.png")
	get_tree().quit()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 10
	col.offset_bottom = -10
	add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var title := Label.new()
	title.text = "Cast — enable / disable characters"
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var back := Button.new()
	back.text = "◂ Editor"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	top.add_child(back)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0, 28)
	col.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	for c in CharacterRoster.CHARACTERS:
		cards.add_child(_character_card(c))

	_refresh_status()


func _character_card(c: Dictionary) -> PanelContainer:
	var id := str(c["id"])
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(c["color"]) * 0.7
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var toggle := CheckButton.new()
	toggle.button_pressed = _enabled.has(id)
	toggle.focus_mode = Control.FOCUS_NONE
	if CharacterRoster.always_on(id):
		toggle.button_pressed = true
		toggle.disabled = true
		toggle.tooltip_text = "Permanent — the minimum pair never leaves."
	else:
		toggle.toggled.connect(_on_toggle.bind(id))
	header.add_child(toggle)
	var name_lbl := Label.new()
	name_lbl.text = "%s" % str(c["name"])
	name_lbl.add_theme_color_override("font_color", Color(c["color"]))
	name_lbl.add_theme_font_size_override("font_size", 18)
	header.add_child(name_lbl)
	var cell_lbl := Label.new()
	cell_lbl.text = "%s · %s" % [str(c["cell"]), str(c["class"])]
	cell_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.74))
	header.add_child(cell_lbl)
	if CharacterRoster.always_on(id):
		var perm := Label.new()
		perm.text = "  permanent"
		perm.add_theme_color_override("font_color", Color(0.55, 0.62, 0.7))
		header.add_child(perm)

	var role := Label.new()
	role.text = str(c["role"])
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	box.add_child(role)

	var caps := Label.new()
	caps.text = "Capabilities:  " + ", ".join(c["capabilities"])
	caps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caps.add_theme_color_override("font_color", Color(0.62, 0.78, 0.7))
	box.add_child(caps)

	var ability_strs := []
	for a in c["abilities"]:
		ability_strs.append("%s (%s)" % [str(a["name"]), str(a["desc"])])
	var abil := Label.new()
	abil.text = "Abilities:  " + " · ".join(ability_strs)
	abil.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	abil.add_theme_color_override("font_color", Color(0.78, 0.72, 0.6))
	box.add_child(abil)

	return panel


func _on_toggle(pressed: bool, id: String) -> void:
	if pressed and not _enabled.has(id):
		_enabled.append(id)
	elif not pressed:
		_enabled.erase(id)
	CharacterRoster.save_enabled(_enabled)
	_refresh_status()


func _refresh_status() -> void:
	var party := []
	for c in CharacterRoster.CHARACTERS:
		if _enabled.has(str(c["id"])) or CharacterRoster.always_on(str(c["id"])):
			party.append(str(c["name"]))
	var combat := CharacterRoster.has_combat(_enabled)
	var combat_note := "[color=#7ed08a]combat specialist enabled — full-party route available[/color]" if combat \
		else "[color=#f0b060]no combat specialist — redirect / gauntlet / exploit beats fall to the Aster+Peris route[/color]"
	_status.text = "[b]Party:[/b] %s    ·    %s" % [", ".join(party), combat_note]
