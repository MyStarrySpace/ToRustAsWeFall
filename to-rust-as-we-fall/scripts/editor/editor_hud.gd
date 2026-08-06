extends CanvasLayer

@onready var grid_map: GridMap
@onready var editor: Node

var _palette_buttons: Array[Button] = []
@onready var _info_label: Label = $InfoLabel
@onready var _rotation_label: Label = $Palette/RotationLabel
@onready var _plan_selector: OptionButton = $PlanBrowserPanel/PlanBrowser/PlanSelector
@onready var _plan_title_label: Label = $PlanBrowserPanel/PlanBrowser/PlanTitle
@onready var _plan_slot_label: Label = $PlanBrowserPanel/PlanBrowser/PlanSlot
@onready var _plan_help_label: Label = $PlanBrowserPanel/PlanBrowser/PlanHelp
@onready var _plan_visibility_button: Button = $PlanBrowserPanel/PlanBrowser/PlanButtons/PlanVisibilityButton
@onready var _generation_tier_selector: OptionButton = $PlanBrowserPanel/PlanBrowser/TierRow/GenerationTierSelector
@onready var _generation_seed_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/TierRow/GenerationSeedEdit
@onready var _generation_slot_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/SlotRow/GenerationSlotEdit
@onready var _generation_entry_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/SlotRow/GenerationEntryEdit
@onready var _generation_exit_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/SlotRow/GenerationExitEdit
@onready var _generation_allowed_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/GenerationAllowedEdit
@onready var _generation_blocked_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/GenerationBlockedEdit
@onready var _generation_required_edit: LineEdit = $PlanBrowserPanel/PlanBrowser/GenerationRequiredEdit
@onready var _generation_status_label: Label = $PlanBrowserPanel/PlanBrowser/GenerationStatus

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
	# This authored HUD is also loaded directly by the scene-integrity gate. In that
	# context its parent is the root Window rather than LevelEditor, so it has no
	# GridMap or editor signals to bind. Treat the standalone load as an inert visual
	# fixture instead of dereferencing a fake editor host every frame.
	grid_map = editor.get_node_or_null("GridMap") as GridMap if editor != null else null
	if grid_map == null:
		set_process(false)
		return

	_bind_authored_ui()

	# Connect to editor signals
	editor.block_changed.connect(_on_block_changed)
	editor.orientation_changed.connect(_on_orientation_changed)
	if editor.has_signal("plan_changed"):
		editor.plan_changed.connect(_on_plan_changed)
	if editor.has_signal("plan_visibility_changed"):
		editor.plan_visibility_changed.connect(_on_plan_visibility_changed)

func _bind_authored_ui() -> void:
	for i in range(BLOCK_LABELS.size()):
		var btn := get_node("Palette/Block%d" % (i + 1)) as Button
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
		_palette_buttons.append(btn)
	_highlight_selected(0)
	_bind_plan_browser_ui()

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

func _bind_plan_browser_ui() -> void:
	if editor.has_method("get_editor_plan_entries"):
		var entries: Array = editor.call("get_editor_plan_entries")
		for entry in entries:
			if entry is Dictionary:
				_plan_selector.add_item(str((entry as Dictionary).get("title", "Plan")), int((entry as Dictionary).get("index", 0)))
	_plan_selector.item_selected.connect(func(index: int) -> void:
		if editor.has_method("show_plan_scene"):
			editor.call("show_plan_scene", index)
	)
	var previous_button := $PlanBrowserPanel/PlanBrowser/PlanButtons/PlanPreviousButton as Button
	previous_button.pressed.connect(func() -> void:
		if editor.has_method("cycle_plan_scene"):
			editor.call("cycle_plan_scene", -1)
	)
	var next_button := $PlanBrowserPanel/PlanBrowser/PlanButtons/PlanNextButton as Button
	next_button.pressed.connect(func() -> void:
		if editor.has_method("cycle_plan_scene"):
			editor.call("cycle_plan_scene", 1)
	)
	_plan_visibility_button.pressed.connect(func() -> void:
		if editor.has_method("toggle_plan_visibility"):
			editor.call("toggle_plan_visibility")
	)
	var focus_button := $PlanBrowserPanel/PlanBrowser/PlanButtons/PlanFocusButton as Button
	focus_button.pressed.connect(func() -> void:
		if editor.has_method("focus_active_plan"):
			editor.call("focus_active_plan")
	)
	_bind_generation_controls()
	_on_plan_changed({"loaded": false})

func _bind_generation_controls() -> void:
	for tier in ["teaching", "standard", "hard", "setpiece"]:
		_generation_tier_selector.add_item(tier)
	var generate_button := $PlanBrowserPanel/PlanBrowser/GeneratorActions/GenerationButton as Button
	generate_button.pressed.connect(_on_generate_stretch_pressed)
	var save_button := $PlanBrowserPanel/PlanBrowser/GeneratorActions/GenerationSaveButton as Button
	save_button.pressed.connect(_on_save_generated_stretch_pressed)

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
