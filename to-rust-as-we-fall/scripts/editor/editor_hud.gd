extends CanvasLayer

@onready var grid_map: GridMap
@onready var editor: Node3D

var _palette_buttons: Array[Button] = []
var _info_label: Label
var _rotation_label: Label
var _plan_selector: OptionButton
var _plan_title_label: Label
var _plan_slot_label: Label
var _plan_help_label: Label
var _plan_visibility_button: Button
var _generation_tier_selector: OptionButton
var _generation_seed_edit: LineEdit
var _generation_slot_edit: LineEdit
var _generation_entry_edit: LineEdit
var _generation_exit_edit: LineEdit
var _generation_allowed_edit: LineEdit
var _generation_blocked_edit: LineEdit
var _generation_required_edit: LineEdit
var _generation_status_label: Label

const BLOCK_LABELS: Array[String] = [
	"1: Wall", "2: Floor", "3: Pipe (auto)", "4: Flora",
	"5: Iron Bloom", "6: Terminal", "7: Shelter", "8: Membrane"
]

const BLOCK_COLORS: Array[Color] = [
	Color(0.45, 0.35, 0.28),
	Color(0.25, 0.25, 0.28),
	Color(0.3, 0.6, 0.55),
	Color(0.2, 0.65, 0.4),
	Color(0.7, 0.3, 0.1),
	Color(0.15, 0.4, 0.6),
	Color(0.25, 0.35, 0.6),
	Color(0.55, 0.4, 0.48),
]

const ROTATION_LABELS: Array[String] = ["0°", "90°", "180°", "270°"]

func _ready() -> void:
	editor = get_parent()
	grid_map = editor.get_node("GridMap")

	_build_ui()

	# Connect to editor signals
	editor.block_changed.connect(_on_block_changed)
	editor.orientation_changed.connect(_on_orientation_changed)
	if editor.has_signal("plan_changed"):
		editor.plan_changed.connect(_on_plan_changed)
	if editor.has_signal("plan_visibility_changed"):
		editor.plan_visibility_changed.connect(_on_plan_visibility_changed)

func _build_ui() -> void:
	# Controls info, top left.
	_info_label = Label.new()
	_info_label.position = Vector2(12, 12)
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.85))
	_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_info_label)

	# Palette, bottom of screen.
	var palette_container := VBoxContainer.new()
	palette_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	palette_container.position = Vector2(12, -12)
	palette_container.offset_top = -300
	palette_container.offset_bottom = -12
	add_child(palette_container)

	var title := Label.new()
	title.text = "BLOCKS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	palette_container.add_child(title)

	for i in range(BLOCK_LABELS.size()):
		var btn := Button.new()
		btn.text = BLOCK_LABELS[i]
		btn.custom_minimum_size = Vector2(140, 28)
		btn.add_theme_font_size_override("font_size", 12)

		# Style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.85)
		style.border_color = BLOCK_COLORS[i].darkened(0.3)
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", style)

		var style_hover := style.duplicate()
		style_hover.bg_color = Color(0.18, 0.18, 0.2, 0.9)
		style_hover.border_color = BLOCK_COLORS[i]
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed := style.duplicate()
		style_pressed.bg_color = BLOCK_COLORS[i].darkened(0.5)
		style_pressed.border_color = BLOCK_COLORS[i].lightened(0.2)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		var idx := i
		btn.pressed.connect(func(): editor.select_block(idx))
		palette_container.add_child(btn)
		_palette_buttons.append(btn)

	# Rotation indicator
	_rotation_label = Label.new()
	_rotation_label.add_theme_font_size_override("font_size", 12)
	_rotation_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	palette_container.add_child(_rotation_label)

	_highlight_selected(0)
	_build_plan_browser_ui()

func _process(_delta: float) -> void:
	var cell_count := grid_map.get_used_cells().size()
	var rot_idx: int = editor._rotation_index
	_info_label.text = "Left-click: Place | Right-click: Erase\n"
	_info_label.text += "Middle/Right-drag: Orbit | Shift+Mid: Pan | Scroll: Zoom\n"
	_info_label.text += "1-8: Select block | Q/E: Cycle | R: Rotate\n"
	_info_label.text += "P: Toggle plan | [/]: Cycle plan | F: Focus plan\n"
	_info_label.text += "\nBlocks: %d" % cell_count

	_rotation_label.text = "R: Rotate [%s]" % ROTATION_LABELS[rot_idx]

func _highlight_selected(index: int) -> void:
	for i in range(_palette_buttons.size()):
		var btn := _palette_buttons[i]
		if i == index:
			var active := StyleBoxFlat.new()
			active.bg_color = BLOCK_COLORS[i].darkened(0.5)
			active.border_color = BLOCK_COLORS[i].lightened(0.3)
			active.set_border_width_all(2)
			active.set_corner_radius_all(3)
			active.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", active)
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			var inactive := StyleBoxFlat.new()
			inactive.bg_color = Color(0.12, 0.12, 0.14, 0.85)
			inactive.border_color = BLOCK_COLORS[i].darkened(0.3)
			inactive.set_border_width_all(2)
			inactive.set_corner_radius_all(3)
			inactive.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", inactive)
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))

func _on_block_changed(index: int) -> void:
	_highlight_selected(index)

func _on_orientation_changed(_rot: int) -> void:
	pass  # Rotation label updates in _process

func _build_plan_browser_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "PlanBrowserPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -380.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.offset_bottom = 520.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.1, 0.88)
	style.border_color = Color(0.32, 0.36, 0.42, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var container := VBoxContainer.new()
	container.name = "PlanBrowser"
	container.add_theme_constant_override("separation", 6)
	panel.add_child(container)

	var title := Label.new()
	title.text = "SCENE PLANS / GRAYBOXES"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8))
	container.add_child(title)

	_plan_selector = OptionButton.new()
	_plan_selector.name = "PlanSelector"
	_plan_selector.custom_minimum_size = Vector2(340, 30)
	if editor.has_method("get_editor_plan_entries"):
		var entries: Array = editor.call("get_editor_plan_entries")
		for entry in entries:
			if entry is Dictionary:
				_plan_selector.add_item(str((entry as Dictionary).get("title", "Plan")), int((entry as Dictionary).get("index", 0)))
	_plan_selector.item_selected.connect(func(index: int) -> void:
		if editor.has_method("show_plan_scene"):
			editor.call("show_plan_scene", index)
	)
	container.add_child(_plan_selector)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	container.add_child(button_row)

	var previous_button := Button.new()
	previous_button.name = "PlanPreviousButton"
	previous_button.text = "<"
	previous_button.tooltip_text = "Previous plan"
	previous_button.custom_minimum_size = Vector2(34, 28)
	previous_button.pressed.connect(func() -> void:
		if editor.has_method("cycle_plan_scene"):
			editor.call("cycle_plan_scene", -1)
	)
	button_row.add_child(previous_button)

	var next_button := Button.new()
	next_button.name = "PlanNextButton"
	next_button.text = ">"
	next_button.tooltip_text = "Next plan"
	next_button.custom_minimum_size = Vector2(34, 28)
	next_button.pressed.connect(func() -> void:
		if editor.has_method("cycle_plan_scene"):
			editor.call("cycle_plan_scene", 1)
	)
	button_row.add_child(next_button)

	_plan_visibility_button = Button.new()
	_plan_visibility_button.name = "PlanVisibilityButton"
	_plan_visibility_button.text = "Hide"
	_plan_visibility_button.tooltip_text = "Show or hide the loaded plan graybox"
	_plan_visibility_button.custom_minimum_size = Vector2(78, 28)
	_plan_visibility_button.pressed.connect(func() -> void:
		if editor.has_method("toggle_plan_visibility"):
			editor.call("toggle_plan_visibility")
	)
	button_row.add_child(_plan_visibility_button)

	var focus_button := Button.new()
	focus_button.name = "PlanFocusButton"
	focus_button.text = "Focus"
	focus_button.tooltip_text = "Center the camera on the loaded plan"
	focus_button.custom_minimum_size = Vector2(78, 28)
	focus_button.pressed.connect(func() -> void:
		if editor.has_method("focus_active_plan"):
			editor.call("focus_active_plan")
	)
	button_row.add_child(focus_button)

	_plan_title_label = Label.new()
	_plan_title_label.name = "PlanTitle"
	_plan_title_label.add_theme_font_size_override("font_size", 14)
	_plan_title_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	container.add_child(_plan_title_label)

	_plan_slot_label = Label.new()
	_plan_slot_label.name = "PlanSlot"
	_plan_slot_label.add_theme_font_size_override("font_size", 11)
	_plan_slot_label.add_theme_color_override("font_color", Color(0.66, 0.76, 0.86))
	_plan_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_slot_label.custom_minimum_size = Vector2(340, 0)
	container.add_child(_plan_slot_label)

	_plan_help_label = Label.new()
	_plan_help_label.name = "PlanHelp"
	_plan_help_label.add_theme_font_size_override("font_size", 11)
	_plan_help_label.add_theme_color_override("font_color", Color(0.72, 0.73, 0.78))
	_plan_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_help_label.custom_minimum_size = Vector2(340, 80)
	container.add_child(_plan_help_label)

	_build_generation_controls(container)
	_on_plan_changed({"loaded": false})

func _build_generation_controls(container: VBoxContainer) -> void:
	var divider := HSeparator.new()
	container.add_child(divider)

	var title := Label.new()
	title.text = "GENERATOR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8))
	container.add_child(title)

	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 6)
	container.add_child(tier_row)
	tier_row.add_child(_make_generation_label("Tier"))
	_generation_tier_selector = OptionButton.new()
	_generation_tier_selector.name = "GenerationTierSelector"
	_generation_tier_selector.custom_minimum_size = Vector2(132, 28)
	for tier in ["teaching", "standard", "hard", "setpiece"]:
		_generation_tier_selector.add_item(tier)
	tier_row.add_child(_generation_tier_selector)

	_generation_seed_edit = _make_generation_line_edit("GenerationSeedEdit", "1701", Vector2(86, 28))
	tier_row.add_child(_make_generation_label("Seed"))
	tier_row.add_child(_generation_seed_edit)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	container.add_child(slot_row)
	_generation_slot_edit = _make_generation_line_edit("GenerationSlotEdit", "generated_editor_stretch", Vector2(148, 28))
	_generation_entry_edit = _make_generation_line_edit("GenerationEntryEdit", "shelter_1", Vector2(82, 28))
	_generation_exit_edit = _make_generation_line_edit("GenerationExitEdit", "shelter_2", Vector2(82, 28))
	slot_row.add_child(_generation_slot_edit)
	slot_row.add_child(_generation_entry_edit)
	slot_row.add_child(_generation_exit_edit)

	_generation_allowed_edit = _make_generation_line_edit("GenerationAllowedEdit", "allowed flora/enemy/structure/archetype", Vector2(340, 26))
	_generation_blocked_edit = _make_generation_line_edit("GenerationBlockedEdit", "blocked flora/enemy/structure/archetype", Vector2(340, 26))
	_generation_required_edit = _make_generation_line_edit("GenerationRequiredEdit", "required flora/enemy/structure/archetype", Vector2(340, 26))
	container.add_child(_generation_allowed_edit)
	container.add_child(_generation_blocked_edit)
	container.add_child(_generation_required_edit)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	container.add_child(action_row)
	var generate_button := Button.new()
	generate_button.name = "GenerationButton"
	generate_button.text = "Generate"
	generate_button.tooltip_text = "Generate and show a stretch plan from the current settings"
	generate_button.custom_minimum_size = Vector2(104, 28)
	generate_button.pressed.connect(_on_generate_stretch_pressed)
	action_row.add_child(generate_button)

	var save_button := Button.new()
	save_button.name = "GenerationSaveButton"
	save_button.text = "Save"
	save_button.tooltip_text = "Save the last generated stretch spec"
	save_button.custom_minimum_size = Vector2(74, 28)
	save_button.pressed.connect(_on_save_generated_stretch_pressed)
	action_row.add_child(save_button)

	_generation_status_label = Label.new()
	_generation_status_label.name = "GenerationStatus"
	_generation_status_label.add_theme_font_size_override("font_size", 11)
	_generation_status_label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.78))
	_generation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_generation_status_label.custom_minimum_size = Vector2(340, 32)
	container.add_child(_generation_status_label)

func _make_generation_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.64, 0.68, 0.74))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _make_generation_line_edit(node_name: String, placeholder: String, size: Vector2) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = size
	edit.add_theme_font_size_override("font_size", 11)
	return edit

func _on_generate_stretch_pressed() -> void:
	if editor == null or not editor.has_method("generate_stretch_plan"):
		_set_generation_status("Generator API unavailable.")
		return
	var settings := _build_generation_settings()
	var spec: Dictionary = editor.call("generate_stretch_plan", settings)
	if not bool(spec.get("success", false)):
		var validation: Dictionary = spec.get("validation", {})
		_set_generation_status("Generation failed: %s" % ", ".join(_string_array(validation.get("errors", []))))
		return
	if editor.has_method("show_generated_stretch"):
		editor.call("show_generated_stretch", spec)
	_set_generation_status("Showing %s." % str(spec.get("id", "generated stretch")))

func _on_save_generated_stretch_pressed() -> void:
	if editor == null or not editor.has_method("get_generation_state") or not editor.has_method("save_generated_stretch"):
		_set_generation_status("Save API unavailable.")
		return
	var state: Dictionary = editor.call("get_generation_state")
	var spec: Dictionary = state.get("last_spec", {})
	if spec.is_empty() and editor.has_method("generate_stretch_plan"):
		spec = editor.call("generate_stretch_plan", _build_generation_settings())
	var path: String = editor.call("save_generated_stretch", spec)
	_set_generation_status("Saved %s." % path if path != "" else "Nothing saved.")

func _build_generation_settings() -> Dictionary:
	var seed := 1701
	var seed_text := _generation_seed_edit.text.strip_edges() if _generation_seed_edit != null else ""
	if seed_text.is_valid_int():
		seed = int(seed_text)
	var tier := "teaching"
	if _generation_tier_selector != null and _generation_tier_selector.selected >= 0:
		tier = _generation_tier_selector.get_item_text(_generation_tier_selector.selected)
	var slot_id := _generation_slot_edit.text.strip_edges() if _generation_slot_edit != null else ""
	if slot_id == "":
		slot_id = "generated_editor_%d" % seed
	var entry_id := _generation_entry_edit.text.strip_edges() if _generation_entry_edit != null else "shelter_1"
	var exit_id := _generation_exit_edit.text.strip_edges() if _generation_exit_edit != null else "shelter_2"
	return {
		"id": slot_id,
		"title": slot_id.replace("_", " ").capitalize(),
		"seed": seed,
		"complexity_tier": tier,
		"limitations": {
			"allowed": _parse_generation_limits(_generation_allowed_edit.text if _generation_allowed_edit != null else ""),
			"blocked": _parse_generation_limits(_generation_blocked_edit.text if _generation_blocked_edit != null else ""),
			"required": _parse_generation_limits(_generation_required_edit.text if _generation_required_edit != null else ""),
		},
		"world_slot": {
			"slot_id": slot_id,
			"act": 1,
			"region": "Generated",
			"entry_shelter_id": entry_id,
			"exit_shelter_id": exit_id,
			"entry_anchor": "entry",
			"exit_anchor": "exit_shelter",
			"canonical_party": ["aster", "peris", "endo"],
			"preview_party_preset": "full_party_full_health",
		},
	}

func _parse_generation_limits(raw: String) -> Dictionary:
	var result := {
		"flora": [],
		"enemies": [],
		"structures": [],
		"archetypes": [],
	}
	var palette := {}
	if editor != null and editor.has_method("get_generation_palette"):
		palette = editor.call("get_generation_palette")
	for token in raw.split(",", false):
		_append_generation_limit_token(result, str(token).strip_edges().to_lower(), palette)
	return result

func _append_generation_limit_token(result: Dictionary, token: String, palette: Dictionary) -> void:
	if token == "":
		return
	var category := ""
	var value := token
	if token.contains(":"):
		var parts := token.split(":", false, 1)
		category = _canonical_generation_category(str(parts[0]).strip_edges())
		value = str(parts[1]).strip_edges()
	else:
		category = _infer_generation_category(value, palette)
	if category == "" or value == "":
		return
	if not result.has(category):
		result[category] = []
	if not (result[category] as Array).has(value):
		(result[category] as Array).append(value)

func _canonical_generation_category(raw: String) -> String:
	match raw:
		"flora", "plant", "plants":
			return "flora"
		"enemy", "enemies":
			return "enemies"
		"structure", "structures":
			return "structures"
		"archetype", "archetypes":
			return "archetypes"
		_:
			return ""

func _infer_generation_category(value: String, palette: Dictionary) -> String:
	for category in ["flora", "enemies", "structures", "archetypes"]:
		var values: Array = palette.get(category, [])
		if values.has(value):
			return category
	return ""

func _set_generation_status(text: String) -> void:
	if _generation_status_label != null:
		_generation_status_label.text = text

func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			result.append(str(value))
	return result

func _on_plan_changed(state: Dictionary) -> void:
	if _plan_title_label == null:
		return

	var active_index := int(state.get("active_plan_index", -1))
	if _plan_selector != null and active_index >= 0 and active_index < _plan_selector.item_count:
		_plan_selector.select(active_index)

	var loaded := bool(state.get("loaded", false))
	if not loaded:
		_plan_title_label.text = "No plan loaded"
		_plan_slot_label.text = ""
		_plan_help_label.text = ""
		return

	_plan_title_label.text = str(state.get("active_plan_title", "Plan"))
	var slot: Dictionary = state.get("world_slot", {})
	if slot.size() > 0:
		_plan_slot_label.text = "Slot: %s\n%s -> %s" % [
			str(slot.get("slot_id", "")),
			str(slot.get("entry_shelter_id", slot.get("entry_anchor", ""))),
			str(slot.get("exit_shelter_id", slot.get("exit_anchor", ""))),
		]
	else:
		_plan_slot_label.text = "Anchors: %d" % int(state.get("anchor_count", 0))
	_plan_help_label.text = str(state.get("help", ""))
	_on_plan_visibility_changed(bool(state.get("visible", true)))

func _on_plan_visibility_changed(visible: bool) -> void:
	if _plan_visibility_button != null:
		_plan_visibility_button.text = "Hide" if visible else "Show"
