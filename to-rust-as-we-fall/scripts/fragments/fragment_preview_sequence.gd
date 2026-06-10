extends "res://scripts/tutorial/tutorial_sequence.gd"

const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")
const GameHUDScript = preload("res://scripts/ui/game_hud.gd")
const ItemData = preload("res://scripts/game/objects/item_data.gd")
const PERCEPTION_STACK_SHADER := preload("res://resources/perception_stack.gdshader")

const STACKS_CHUNK_SCENE := preload("res://scenes/fragments/chunks/stacks_fragment_chunk.tscn")
const RINGS_CHUNK_SCENE := preload("res://scenes/fragments/chunks/rings_fragment_chunk.tscn")
const LOCKOUT_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lockout_fragment_chunk.tscn")
const OVERLAY_LAB_CHUNK_SCENE := preload("res://scenes/fragments/chunks/overlay_lab_chunk.tscn")
const MOTHER_FERROLURE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/mother_ferrolure_chunk.tscn")
const SURVIVAL_RANGE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/survival_range_chunk.tscn")
const CHANNELS_RHYTHM_CHUNK_SCENE := preload("res://scenes/fragments/chunks/channels_rhythm_chunk.tscn")
const CHANNELS_HIDE_WINDOW_CHUNK_SCENE := preload("res://scenes/fragments/chunks/channels_hide_window_chunk.tscn")
const ENDO_JUNCTION_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn")
const GENERATED_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const REFUGE_RUN_CHUNK_SCENE := preload("res://scenes/fragments/chunks/refuge_run_chunk.tscn")
const LURE_RELAY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lure_relay_chunk.tscn")
const SHOWCASE_GALLERY_CHUNK_SCENE := preload("res://scenes/fragments/chunks/showcase_gallery_chunk.tscn")

# chunk name -> packed scene. The single lookup that replaced the old per-name match (and the reason
# we no longer need one *_preview.tscn per chunk: one scene reads this registry and picks at runtime).
const CHUNK_SCENES := {
	"stacks": STACKS_CHUNK_SCENE,
	"rings": RINGS_CHUNK_SCENE,
	"lockout": LOCKOUT_CHUNK_SCENE,
	"overlay_lab": OVERLAY_LAB_CHUNK_SCENE,
	"mother_ferrolure": MOTHER_FERROLURE_CHUNK_SCENE,
	"survival_range": SURVIVAL_RANGE_CHUNK_SCENE,
	"channels_rhythm": CHANNELS_RHYTHM_CHUNK_SCENE,
	"channels_hide_window": CHANNELS_HIDE_WINDOW_CHUNK_SCENE,
	"endo_junction_stretch": ENDO_JUNCTION_STRETCH_CHUNK_SCENE,
	"generated_stretch": GENERATED_STRETCH_CHUNK_SCENE,
	"refuge_run": REFUGE_RUN_CHUNK_SCENE,
	"lure_relay": LURE_RELAY_CHUNK_SCENE,
	"showcase_gallery": SHOWCASE_GALLERY_CHUNK_SCENE,
}

# The fragment menu, in display order. Each entry is a runnable preview: an id, the chunk it loads, a
# display title, and an optional chunk config (the generated-stretch entries reuse one chunk with
# different spec specs). This list REPLACES the 14 near-identical *_preview.tscn files — the single
# fragment_preview.tscn boots into a picker built from these, and tests/tools select by id.
const PREVIEW_ENTRIES := [
	{"id": "stacks", "chunk": "stacks", "title": "Stacks Fragment Lab"},
	{"id": "rings", "chunk": "rings", "title": "Rings Fragment Lab"},
	{"id": "lockout", "chunk": "lockout", "title": "Lockout Fragment Lab"},
	{"id": "overlay_lab", "chunk": "overlay_lab", "title": "Overlay Lab"},
	{"id": "mother_ferrolure", "chunk": "mother_ferrolure", "title": "Mother Flure"},
	{"id": "lure_relay", "chunk": "lure_relay", "title": "Ferrolure Relay"},
	{"id": "channels_rhythm", "chunk": "channels_rhythm", "title": "Channels Rhythm Lane"},
	{"id": "channels_hide_window", "chunk": "channels_hide_window", "title": "Channels Hide Window"},
	{"id": "survival_range", "chunk": "survival_range", "title": "Shelter-To-Shelter Range"},
	{"id": "refuge_run", "chunk": "refuge_run", "title": "Refuge Run"},
	{"id": "showcase_gallery", "chunk": "showcase_gallery", "title": "Showcase Gallery"},
	{"id": "endo_junction_stretch", "chunk": "endo_junction_stretch", "title": "Endo's Junction to Shelter 1"},
	{"id": "generated_stretch", "chunk": "generated_stretch", "title": "Generated Stretch",
		"config": {"spec_path": "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"}},
	{"id": "generated_chain_nested_poc", "chunk": "generated_stretch", "title": "Generated Chain/Nested POC",
		"config": {"spec_path": "res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json"}},
	{"id": "generated_random_walk_poc", "chunk": "generated_stretch", "title": "Generated Random Walk POC",
		"config": {"spec_path": "res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json"}},
]

## The menu entry for an id (or {} if none).
static func get_preview_entry(entry_id: String) -> Dictionary:
	for entry in PREVIEW_ENTRIES:
		if String(entry.get("id", "")) == entry_id:
			return entry
	return {}

const CHARACTER_IDS := ["aster", "peris", "endo"]
const CHARACTER_DISPLAY_NAMES := {
	"aster": "Aster",
	"peris": "Peris",
	"endo": "Endo",
}
const CHARACTER_COLORS := {
	"aster": Color(0.29, 0.62, 1.0),
	"peris": Color(1.0, 0.67, 0.27),
	"endo": Color(0.4, 0.72, 0.55),
}
const CHARACTER_SPEEDS := {
	"aster": 3.2,
	"peris": 3.0,
	"endo": 2.8,
}
const DEFAULT_SPAWNS := {
	"aster": Vector3(4.0, 0.5, 0.0),
	"peris": Vector3(2.0, 0.5, 1.8),
	"endo": Vector3(0.0, 0.5, -1.8),
}

const ABILITY_KEYCODES := {
	"Q": KEY_Q,
	"W": KEY_W,
	"E": KEY_E,
	"Z": KEY_Z,
	"X": KEY_X,
	"V": KEY_V,
}
const PREVIEW_GUI_CONTRACT_ID := "fragment_preview_shared_gui_v1"
const GAME_HUD_SCRIPT_PATH := "res://scripts/ui/game_hud.gd"
const PREVIEW_CONTROL_HELP := "Click move  WASD/middle-drag pan  1-3 focus  Ctrl+1-3 multi-select  C cycle  Z/X abilities  V drop  T transfer  B retrieve  F1-F3 overlays  O drawer  Tab route  G dodge  Space pause  R reload"
const PREVIEW_INVENTORY_CONTROL_HELP := "Controls: Z/X abilities  V drop  T transfer  B retrieve"
# The canonical per-ability key/owner bindings now live in data/abilities/en/abilities.xlsx (the
# "bindings" sheet), read via AbilityData.binding(id) — see _apply_canonical_main_ability_binding.

const DEFAULT_HP := 100.0
const DEFAULT_STAMINA := 100.0
const DEFAULT_ATP := GameState.ATP_MAX_PIPS
const DEFAULT_DAY := 1
const DEFAULT_TIME := 0.28
const DEFAULT_DAY_DURATION_SECONDS := DayNightCycleScript.DEFAULT_DAY_DURATION_SECONDS
const DEFAULT_NIGHT_DURATION_SECONDS := DayNightCycleScript.DEFAULT_NIGHT_DURATION_SECONDS
const STAMINA_DRAIN := 18.0
const STAMINA_REGEN := 10.0

# The chunk this preview loads. A string (it's the serializable handle the data layer needs — the
# puzzle JSON, the --preview=<id> CLI arg, and test .set() all key on it), but constrained to the
# registry by an inspector dropdown + load-time validation. Keep this list == CHUNK_SCENES.keys()
# (the --test-fragment-preview-registry test enforces it). Empty = the picker (preview_menu).
@export_enum("stacks", "rings", "lockout", "overlay_lab", "mother_ferrolure", "survival_range",
	"channels_rhythm", "channels_hide_window", "endo_junction_stretch", "generated_stretch",
	"refuge_run", "lure_relay", "showcase_gallery") var preview_chunk := "stacks"
@export var scene_title_override := ""
@export var preview_chunk_config: Dictionary = {}
## When true, boot into a fragment PICKER instead of loading a chunk directly. The single
## fragment_preview.tscn sets this; selecting an entry loads it, and reloading (R) returns here.
## A `--preview=<id>` command-line arg (or a preset preview_chunk) skips the menu and loads directly.
@export var preview_menu := false

var _characters: Dictionary = {}
var _character_state: Dictionary = {}
var _ability_defs: Dictionary = {}
var _ability_runtime: Dictionary = {}
var _ability_order: Array[String] = []

var _hud
var _active_char_id := ""
var _selected_char_ids: Array[String] = []
var _run_active := false
var _routing_mode := "safe"
## Preview-only toggle (G): when true the party can dodge-roll, so enemy strikes auto-evade. Off by
## default — dodge isn't unlocked in every chunk, so attacks land. A chunk may default it on via
## preview_dodge_unlocked().
var _preview_dodge_unlocked := false
var _preview_interactables: Array = []
var _active_chunk: Node3D
var _preview_day := DEFAULT_DAY
var _preview_time := DEFAULT_TIME
var _preview_clock_running := true
var _preview_show_time := true
var _preview_cycle = DayNightCycleScript.new()
var _preview_environment: Environment
var _preview_directional_light: DirectionalLight3D
var _suppress_hud_character_signal := false

var _overlay_states := {
	"aster": true,
	"peris": true,
	"endo": true,
}
var _overlay_buttons: Dictionary = {}
var _overlay_panel_content: VBoxContainer
var _overlay_panel_status_label: Label
var _overlay_panel_collapse_button: Button
var _overlay_panel_collapsed := false
var _overlay_panel_margin: MarginContainer
var _overlay_stack_quad: MeshInstance3D
var _overlay_stack_material: ShaderMaterial
var _inventory_panel_label: Label
var _inventory_panel_title: Label
var _preview_item_nodes: Dictionary = {}

var _preview_layer: CanvasLayer
var _menu_panel: PanelContainer
var _in_menu := false
var _title_label: Label
var _help_label: Label
var _note_label: Label
var _note_default := ""
var _note_timer := 0.0

func _get_chunk_scene(chunk_name: String) -> PackedScene:
	return CHUNK_SCENES.get(chunk_name, null)

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.035, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.27, 0.32)
	environment.ambient_light_energy = 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	world_environment.environment = environment
	env.add_child(world_environment)
	_preview_environment = environment

	var preview_sun := DirectionalLight3D.new()
	preview_sun.name = "PreviewSun"
	preview_sun.rotation_degrees = Vector3(-54.0, 28.0, 0.0)
	preview_sun.light_color = Color(0.82, 0.78, 0.74)
	preview_sun.light_energy = 0.75
	preview_sun.shadow_enabled = true
	env.add_child(preview_sun)
	_preview_directional_light = preview_sun
	_apply_preview_lighting()

func _build_characters() -> void:
	var characters_root := Node3D.new()
	characters_root.name = "Characters"
	add_child(characters_root)

	for char_id in CHARACTER_IDS:
		var node := _create_player_character(CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		node.position = DEFAULT_SPAWNS[char_id]
		characters_root.add_child(node)
		_characters[char_id] = node

	_player = _characters["aster"]
	if not Engine.is_editor_hint():
		# Free-look on by default in the preview — you're here to inspect a chunk, so WASD / right-drag
		# pan the camera around it (click recenters on the active character).
		_setup_game_camera(_player, Vector3(0, 12, 9), true)

func _register_characters() -> void:
	for char_id in CHARACTER_IDS:
		var character_node: Node3D = _characters[char_id]
		_register_gs_character(char_id, character_node, CHARACTER_SPEEDS[char_id], {
			"hp": DEFAULT_HP,
			"stamina": DEFAULT_STAMINA,
			"atp": DEFAULT_ATP,
		})
		if character_node != null and character_node.has_method("bind_interaction_root"):
			character_node.call("bind_interaction_root", self)

func _setup_ui() -> void:
	_build_preview_ui()
	_build_game_hud()
	_connect_preview_item_signals()
	_initialize_default_character_state()
	_apply_selection_state(["aster"], "aster")

func _begin() -> void:
	# A command-line `--preview=<id>` always wins (headless tests / `godot ... -- --preview=lure_relay`).
	var cli_id := _cli_preview_id()
	if cli_id != "":
		_apply_preview_entry(get_preview_entry(cli_id))
	elif preview_menu:
		_show_fragment_menu()
		return
	_begin_chunk()

## Build (or load) the chunk named by preview_chunk and wire up the party/UI around it.
func _begin_chunk() -> void:
	_in_menu = false
	if _menu_panel != null:
		_menu_panel.visible = false
	# Fail LOUD on a typo'd id — otherwise _load_chunk silently builds an empty placeholder chunk and
	# the preview looks "booted but blank". The registry is the allow-list.
	if not CHUNK_SCENES.has(preview_chunk):
		push_error("fragment_preview: unknown chunk '%s'. Valid: %s" % [preview_chunk, ", ".join(CHUNK_SCENES.keys())])
		show_preview_message("Unknown fragment '%s' — see CHUNK_SCENES." % preview_chunk, 6.0)
	set_preview_step(preview_chunk)
	_active_chunk = _load_chunk(preview_chunk)
	_connect_outline_feedback_sources(self)
	_apply_chunk_runtime_preset()
	if _active_chunk != null and _active_chunk.has_method("reset_preview_state"):
		_active_chunk.call("reset_preview_state")
	_apply_chunk_navigation_graph()
	_apply_chunk_metadata()
	_position_party_for_chunk()
	_apply_chunk_party_presence()
	# Dodge defaults to the chunk's declaration (off unless a chunk unlocks it). Toggle live with G.
	if _active_chunk != null and _active_chunk.has_method("preview_dodge_unlocked"):
		_preview_dodge_unlocked = bool(_active_chunk.call("preview_dodge_unlocked"))
	_apply_dodge_setting()
	_select_character(_default_chunk_character())
	_refresh_preview_items()
	_refresh_inventory_panel()
	_tutorial_prompt.show_prompt("Click to move")
	show_preview_message("Preview booted with full HP, stamina, and ATP.", 2.0)

# --- Fragment picker (replaces the per-chunk *_preview.tscn files) ---

## Read a `--preview=<id>` (or `--preview <id>`) user arg, if present.
func _cli_preview_id() -> String:
	var cli: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(cli.size()):
		var a := String(cli[i])
		if a.begins_with("--preview="):
			return a.substr("--preview=".length())
		if a == "--preview" and i + 1 < cli.size():
			return String(cli[i + 1])
	return ""

## Point the preview at a menu entry (chunk + title + config) before loading it.
func _apply_preview_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	preview_chunk = String(entry.get("chunk", preview_chunk))
	scene_title_override = String(entry.get("title", scene_title_override))
	preview_chunk_config = (entry.get("config", {}) as Dictionary).duplicate(true)

## Build and show the picker: one button per PREVIEW_ENTRIES row. Selecting one loads that fragment.
func _show_fragment_menu() -> void:
	_in_menu = true
	if _menu_panel == null:
		_build_fragment_menu()
	_menu_panel.visible = true
	if _title_label != null:
		_title_label.text = "Fragment Preview"
	if _help_label != null:
		_help_label.text = "Pick a fragment to preview  ·  R reloads back to this list"

func _build_fragment_menu() -> void:
	if _preview_layer == null:
		return
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "FragmentMenu"
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_menu_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)
	var heading := Label.new()
	heading.text = "Select a fragment"
	heading.add_theme_font_size_override("font_size", 20)
	col.add_child(heading)
	for entry in PREVIEW_ENTRIES:
		var button := Button.new()
		button.text = String(entry.get("title", entry.get("id", "?")))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_menu_entry_pressed.bind(entry))
		col.add_child(button)
	_preview_layer.add_child(_menu_panel)

func _on_menu_entry_pressed(entry: Dictionary) -> void:
	_apply_preview_entry(entry)
	_begin_chunk()

func _configure_loaded_chunk(chunk: Node3D, chunk_name: String) -> void:
	if chunk_name != preview_chunk:
		return
	if chunk != null and chunk.has_method("configure_chunk"):
		chunk.call("configure_chunk", preview_chunk_config)

func _apply_chunk_navigation_graph() -> void:
	if _game_state == null:
		return
	# A chunk exposing get_grid_data() routes on the unified grid (cells + per-cell risk) — the
	# preferred representation. The nav-graph hook below remains only for not-yet-migrated chunks.
	if _active_chunk != null and _active_chunk.has_method("get_grid_data"):
		var grid_data: Variant = _active_chunk.call("get_grid_data")
		if grid_data is Dictionary and not (grid_data as Dictionary).is_empty():
			_game_state.grid = GridWorld.from_data(grid_data as Dictionary)
			_game_state.clear_navigation_graph()
			return
	if _active_chunk != null and _active_chunk.has_method("get_navigation_graph_data"):
		var data: Variant = _active_chunk.call("get_navigation_graph_data")
		if data is Dictionary and not (data as Dictionary).is_empty():
			_game_state.set_navigation_data(data as Dictionary)
			return
	_game_state.clear_navigation_graph()

func _compute_speed() -> float:
	if _scheduler != null and _scheduler.is_paused():
		return 0.0
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	for interactable in _preview_interactables:
		if interactable != null and is_instance_valid(interactable):
			interactable.active_character = _active_char_id

	if _preview_clock_running and spd > 0.0:
		_advance_preview_clock(delta * spd)
	_update_stamina(delta, spd)
	_update_ability_timers(delta, spd)
	_update_overlay_runtime(delta)
	_refresh_overlay_panel_status()
	_refresh_inventory_panel()

	if _note_timer > 0.0:
		_note_timer = maxf(0.0, _note_timer - delta)
		if _note_timer <= 0.0 and _note_label != null:
			_note_label.text = _note_default

func _get_speed_recipients() -> Array:
	return _preview_interactables

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_O:
				_toggle_overlay_panel()
			KEY_TAB:
				_on_routing_toggled("direct" if _routing_mode == "safe" else "safe")
			KEY_C:
				_cycle_character()
			KEY_Z:
				if not _activate_keybound_preview_ability(KEY_Z):
					_toggle_run()
			KEY_SPACE:
				_toggle_pause()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_F1:
				_toggle_overlay("aster")
			KEY_F2:
				_toggle_overlay("peris")
			KEY_F3:
				_toggle_overlay("endo")
			KEY_X:
				if not _activate_keybound_preview_ability(KEY_X):
					_consume_active_item()
			KEY_V:
				_drop_active_item()
			KEY_T:
				_transfer_active_item()
			KEY_B:
				_exocytose_active_item()
			KEY_G:
				_preview_dodge_unlocked = not _preview_dodge_unlocked
				_apply_dodge_setting()
				show_preview_message("Dodge roll: %s" % ("ENABLED" if _preview_dodge_unlocked else "locked"), 1.4)
			KEY_1:
				if key_event.ctrl_pressed or key_event.shift_pressed:
					_toggle_character_selected("aster")
				else:
					_select_character("aster")
			KEY_2:
				if key_event.ctrl_pressed or key_event.shift_pressed:
					_toggle_character_selected("peris")
				else:
					_select_character("peris")
			KEY_3:
				if key_event.ctrl_pressed or key_event.shift_pressed:
					_toggle_character_selected("endo")
				else:
					_select_character("endo")
			_:
				_activate_keybound_preview_ability(key_event.keycode)

func register_preview_interactable(interactable: Node) -> void:
	if _preview_interactables.has(interactable):
		return
	_preview_interactables.append(interactable)
	interactable.dialogue_box = _dialogue
	interactable.active_character = _active_char_id
	_connect_interactable_outline_feedback(interactable)
	for char_id in CHARACTER_IDS:
		var character_node: Node = _characters.get(char_id, null)
		if character_node != null and character_node.has_method("bind_interaction_target"):
			character_node.call("bind_interaction_target", interactable)

func get_preview_dialogue_box() -> Node:
	return _dialogue

func get_preview_engram_overlay() -> Node:
	return _engram_overlay

func get_preview_active_character() -> String:
	return _active_char_id

func get_preview_selected_characters() -> Array:
	return _selected_char_ids.duplicate()

func get_preview_scheduler_tick() -> float:
	return _scheduler.get_current_tick() if _scheduler != null else 0.0

func get_preview_character_move_speed(char_id: String, running := false) -> float:
	var base_speed: float = float(CHARACTER_SPEEDS.get(char_id, 3.0))
	if not running:
		return base_speed
	if not _characters.has(char_id):
		return base_speed
	var node: Node = _characters[char_id]
	if node != null:
		var run_speed: Variant = node.get("run_speed")
		if run_speed != null:
			return float(run_speed)
	return base_speed

func spawn_preview_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if _game_state == null:
		return ""
	var item_id := _game_state.spawn_item(item_type, position, properties)
	_ensure_preview_item_node(item_id)
	_refresh_inventory_panel()
	return item_id

func remove_preview_item(item_id: String) -> void:
	if _game_state == null:
		return
	_game_state.remove_item(item_id)
	if _preview_item_nodes.has(item_id):
		var node: Node3D = _preview_item_nodes[item_id]
		if node != null:
			node.queue_free()
		_preview_item_nodes.erase(item_id)
	_refresh_inventory_panel()

func get_preview_item_state(item_id: String) -> Dictionary:
	if _game_state == null or not _game_state.items.has(item_id):
		return {}
	return (_game_state.items[item_id] as Dictionary).duplicate(true)

func get_preview_hand_items(char_id: String) -> Array:
	if _game_state == null:
		return []
	return _game_state.get_hand_items(char_id)

func get_preview_hand_slots(char_id: String) -> Array:
	if _game_state == null:
		return []
	return _game_state.get_hand_slots(char_id)

func get_preview_internal_items(char_id: String) -> Array:
	if _game_state == null:
		return []
	return _game_state.get_internal_items(char_id)

func get_preview_collection_items() -> Array:
	if _game_state == null:
		return []
	return _game_state.collection.duplicate()

func get_preview_item_display_name(item_id: String, char_id := "") -> String:
	if _game_state == null or not _game_state.items.has(item_id):
		return item_id
	var item: Dictionary = _game_state.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	var display_names: Dictionary = properties.get("display_names_by_character", {})
	if char_id != "" and display_names.has(char_id):
		return str(display_names.get(char_id, item_id))
	if properties.has("display_name"):
		return str(properties.get("display_name", item_id))
	return ItemData.get_display_name(str(item.get("type", item_id)))

func pick_up_preview_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var picked := _game_state.pick_up_item(char_id, item_id)
	if picked:
		show_preview_message("%s picked up %s." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 1.2)
	_refresh_inventory_panel()
	return picked

func drop_preview_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var dropped := _game_state.drop_item(char_id, item_id)
	if dropped:
		show_preview_message("%s dropped %s." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 1.2)
	_refresh_inventory_panel()
	return dropped

func transfer_preview_item(from_id: String, to_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var transferred := _game_state.transfer_item(from_id, to_id, item_id)
	if transferred:
		show_preview_message("%s handed %s to %s." % [
			CHARACTER_DISPLAY_NAMES.get(from_id, from_id.capitalize()),
			get_preview_item_display_name(item_id, to_id),
			CHARACTER_DISPLAY_NAMES.get(to_id, to_id.capitalize()),
		], 1.3)
	_refresh_inventory_panel()
	return transferred

func endocytose_preview_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var started := _game_state.endocytose_item(char_id, item_id)
	if started:
		set_preview_character_status(char_id, "consuming")
		show_preview_message("%s starts consuming %s." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 1.4)
	_refresh_inventory_panel()
	return started

func exocytose_preview_item(char_id: String, item_id: String) -> bool:
	if _game_state == null:
		return false
	var exocytosed := _game_state.exocytose_item(char_id, item_id)
	if exocytosed:
		show_preview_message("%s retrieves %s." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 1.4)
	_refresh_inventory_panel()
	return exocytosed

func get_preview_character_position(char_id: String) -> Vector3:
	if not _characters.has(char_id):
		return Vector3.ZERO
	return (_characters[char_id] as CharacterBody3D).global_position

func get_preview_character_stat(char_id: String, stat_name: String) -> float:
	if not _character_state.has(char_id):
		return 0.0
	return float(_character_state[char_id].get(_normalize_stat_name(stat_name), 0.0))

func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if not _character_state.has(char_id):
		return

	var normalized := _normalize_stat_name(stat_name)
	var previous_value := float(_character_state[char_id].get(normalized, 0.0))
	match normalized:
		"hp":
			_character_state[char_id][normalized] = clampf(value, 0.0, DEFAULT_HP)
		"sta":
			_character_state[char_id][normalized] = clampf(value, 0.0, DEFAULT_STAMINA)
		"atp":
			_character_state[char_id][normalized] = GameState.clamp_atp(value)
		_:
			return

	_update_character_in_game_state(char_id)
	_sync_character_hud(char_id)
	if normalized == "hp" and previous_value > 0.0 and float(_character_state[char_id].get("hp", 0.0)) <= 0.0:
		_ensure_valid_selection()

func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	set_preview_character_stat(char_id, stat_name, get_preview_character_stat(char_id, stat_name) + delta)

func set_preview_character_status(char_id: String, status: String) -> void:
	if not _character_state.has(char_id):
		return
	_character_state[char_id]["status"] = status
	_sync_character_hud(char_id)

func set_preview_character_visible(char_id: String, visible: bool) -> void:
	if not _character_state.has(char_id) or not _characters.has(char_id):
		return
	_character_state[char_id]["visible"] = visible
	_characters[char_id].visible = visible
	if not visible:
		_characters[char_id].set_move_enabled(false)
	_sync_character_hud(char_id)
	if not visible:
		_ensure_valid_selection()

func show_preview_message(text: String, duration := 2.0) -> void:
	if _hud != null:
		_hud.show_message(text, duration)

func set_preview_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	_set_runtime_ability_state(ability_id, state, remaining)

func get_preview_routing_mode() -> String:
	return _routing_mode

func set_preview_step(step: String) -> void:
	_current_step = step

func show_preview_note(text: String, duration := 3.0) -> void:
	if _note_label == null:
		return
	_note_label.text = text
	_note_timer = maxf(0.0, duration)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := DEFAULT_SPAWNS.duplicate(true)
	if _active_chunk != null and _active_chunk.has_method("get_preview_anchors"):
		anchors.merge(_active_chunk.call("get_preview_anchors"), true)
	return anchors

func headless_get_state() -> Dictionary:
	var state := {
		"preview_chunk": preview_chunk,
		"preview_party_preset": _preview_party_preset(),
		"world_slot": _active_world_slot(),
		"current_step": _current_step,
		"active_character": _active_char_id,
		"selected_characters": _selected_char_ids.duplicate(),
		"routing_mode": _routing_mode,
		"run_active": _run_active,
		"paused": _scheduler.is_paused() if _scheduler else false,
		"scheduler_tick": _scheduler.get_current_tick() if _scheduler else 0.0,
		"day": _preview_day,
		"time": _preview_time,
		"time_phase": _preview_cycle.get_phase_name(_preview_time),
		"clock": {
			"running": _preview_clock_running,
			"show_time": _preview_show_time,
			"phase": _preview_cycle.get_phase_name(_preview_time),
			"phase_duration_seconds": _preview_cycle.get_phase_duration_seconds(_preview_time),
			"phase_elapsed_seconds": _preview_cycle.get_phase_elapsed_seconds(_preview_time),
			"phase_remaining_seconds": _preview_cycle.get_seconds_until_next_phase(_preview_time),
			"cycle_elapsed_seconds": _preview_cycle.get_cycle_elapsed_seconds(_preview_time),
			"cycle_duration_seconds": _preview_cycle.get_cycle_duration_seconds(),
			"day_duration_seconds": _preview_cycle.day_duration_seconds,
			"night_duration_seconds": _preview_cycle.night_duration_seconds,
		},
		"overlay_states": _overlay_states.duplicate(true),
		"enabled_overlays": _get_enabled_overlays(),
		"active_overlay": _get_live_overlay_id(),
		"overlay_vision_sources": _get_overlay_vision_source_state(),
		"overlay_panel_collapsed": _overlay_panel_collapsed,
		"ui": _get_preview_ui_state(),
		"inventory": {
			"collection": get_preview_collection_items(),
			"endocytosing": {},
		},
		"navigation": _game_state.get_navigation_state() if _game_state != null else {},
		"characters": {},
		"character_stats": {},
		"abilities": {},
	}

	for char_id in CHARACTER_IDS:
		state["characters"][char_id] = get_preview_character_position(char_id)
		state["character_stats"][char_id] = _character_state.get(char_id, {}).duplicate(true)
		state["inventory"][char_id] = {
			"hands": get_preview_hand_items(char_id),
			"hand_slots": get_preview_hand_slots(char_id),
			"internal": get_preview_internal_items(char_id),
		}
		state["inventory"]["endocytosing"][char_id] = _game_state.is_endocytosing(char_id) if _game_state != null else false

	for ability_id in _ability_order:
		var ability_def: Dictionary = _ability_defs.get(ability_id, {})
		var ability_runtime: Dictionary = _ability_runtime.get(ability_id, {})
		state["abilities"][ability_id] = {
			"display_name": str(ability_def.get("display_name", ability_id.to_upper())),
			"keybind": str(ability_def.get("keybind", "")),
			"keycode": int(ability_def.get("keycode", 0)),
			"state": str(ability_runtime.get("base_state", "ready")),
			"remaining": float(ability_runtime.get("remaining", 0.0)),
			"owner": str(ability_def.get("owner", "")),
		}

	if _active_chunk != null and _active_chunk.has_method("get_preview_state"):
		state["chunk"] = _active_chunk.call("get_preview_state")

	return state

func _get_preview_ui_state() -> Dictionary:
	var hud_contract := {}
	if _hud != null and _hud.has_method("get_hud_contract"):
		hud_contract = _hud.call("get_hud_contract")
	return {
		"contract_id": PREVIEW_GUI_CONTRACT_ID,
		"hud_script": GAME_HUD_SCRIPT_PATH,
		"shared_hud": _hud != null and _hud.get_script() == GameHUDScript,
		"controls": PREVIEW_CONTROL_HELP,
		"inventory_controls": PREVIEW_INVENTORY_CONTROL_HELP,
		"ability_keymap": _get_canonical_main_ability_keymap(),
		"hud": hud_contract,
	}

func _get_canonical_main_ability_keymap() -> Dictionary:
	var keymap := {}
	for ability_id in AbilityData.ABILITY_ORDER:
		var binding := AbilityData.binding(ability_id)
		if binding.is_empty():
			continue
		keymap[ability_id] = {
			"owner": str(binding.get("owner", "")),
			"keybind": str(binding.get("keybind", "")),
			"keycode": int(binding.get("keycode", 0)),
		}
	return keymap

func _active_world_slot() -> Dictionary:
	if _active_chunk != null and _active_chunk.has_method("get_world_slot"):
		var slot: Variant = _active_chunk.call("get_world_slot")
		if slot is Dictionary:
			return (slot as Dictionary).duplicate(true)
	return {}

func _preview_party_preset() -> String:
	var slot := _active_world_slot()
	return str(slot.get("preview_party_preset", "full_party_full_health"))

func headless_select_character(char_id: String) -> void:
	_select_character(char_id)

func headless_set_selected_characters(char_ids: Array) -> void:
	var preferred_active := str(char_ids[0]) if char_ids.size() > 0 else ""
	_apply_selection_state(char_ids, preferred_active)

func headless_move_character(char_id: String, pos: Vector3, running := false) -> bool:
	if _game_state == null or not _game_state.characters.has(char_id):
		return false
	_game_state.change_move_speed(char_id, get_preview_character_move_speed(char_id, running))
	return _game_state.command_move_to_pos(char_id, pos)

func headless_is_character_moving(char_id: String) -> bool:
	if _game_state == null:
		return false
	return _game_state.is_moving(char_id)

func headless_get_character_movement_info(char_id: String) -> Dictionary:
	if _game_state == null or not _game_state.characters.has(char_id):
		return {"moving": false}
	var ch: Dictionary = _game_state.characters[char_id]
	var speed := float(ch.get("move_speed", get_preview_character_move_speed(char_id, false)))
	var walk_speed := get_preview_character_move_speed(char_id, false)
	var running := speed > walk_speed + 0.05
	var movement: Variant = ch.get("movement", null)
	if not (movement is Dictionary):
		return {
			"moving": false,
			"speed": speed,
			"running": running,
			"locomotion": "idle",
		}
	var path: Array = (movement as Dictionary).get("path", [])
	return {
		"moving": true,
		"duration": float(movement.get("duration", 0.0)),
		"total_distance": float(movement.get("total_distance", 0.0)),
		"start_tick": float(movement.get("start_tick", 0.0)),
		"speed": speed,
		"running": running,
		"locomotion": "run" if running else "walk",
		"path_count": path.size(),
		"path": _serialize_vector3_path(path),
	}

func headless_activate_ability(ability_id: String) -> bool:
	if not _ability_defs.has(ability_id):
		return false
	var before: Dictionary = _ability_runtime.get(ability_id, {}).duplicate(true)
	_activate_preview_ability(ability_id)
	return before != _ability_runtime.get(ability_id, {})

func headless_set_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = enabled
	_refresh_overlay_button(overlay_id)
	_refresh_active_overlay()
	_refresh_overlay_panel_status()

func headless_set_routing_mode(mode: String) -> void:
	_on_routing_toggled(mode)

func headless_set_preview_time(day: int, time_of_day: float) -> void:
	_preview_day = maxi(day, 1)
	_preview_time = clampf(float(time_of_day), 0.0, 1.0)
	_sync_preview_time_presentation()

func headless_set_preview_clock_running(enabled: bool) -> void:
	_preview_clock_running = enabled

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	if not _characters.has(char_id):
		return
	if _game_state != null and _game_state.characters.has(char_id):
		_game_state.command_stop(char_id)
		_game_state.characters[char_id].position = pos
	if _characters[char_id] != null:
		_characters[char_id].global_position = pos

func headless_call_chunk(method_name: String, args: Array = []) -> Variant:
	if _active_chunk == null or not _active_chunk.has_method(method_name):
		return null
	return _active_chunk.callv(method_name, args)

func _serialize_vector3_path(path: Array) -> Array:
	var result := []
	for point in path:
		if point is Vector3:
			result.append([point.x, point.y, point.z])
	return result

func set_preview_character_position(char_id: String, pos: Vector3) -> void:
	headless_set_character_position(char_id, pos)

func _headless_sync_runtime(delta: float) -> void:
	for char_id in CHARACTER_IDS:
		var node: CharacterBody3D = _characters.get(char_id, null)
		if node != null and node.has_method("_physics_process"):
			node._physics_process(delta)
	if _active_chunk != null and _active_chunk.has_method("headless_process"):
		_active_chunk.call("headless_process", delta)

func _build_preview_ui() -> void:
	_preview_layer = CanvasLayer.new()
	_preview_layer.layer = 13
	add_child(_preview_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.offset_bottom = 118
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	_preview_layer.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.028, 0.036, 0.82)
	style.border_color = Color(0.14, 0.16, 0.2, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	box.add_child(_title_label)

	_help_label = Label.new()
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.add_theme_font_size_override("font_size", 11)
	_help_label.add_theme_color_override("font_color", Color(0.66, 0.7, 0.76))
	box.add_child(_help_label)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.add_theme_font_size_override("font_size", 11)
	_note_label.add_theme_color_override("font_color", Color(0.82, 0.76, 0.62))
	box.add_child(_note_label)

	_build_inventory_panel()
	_build_overlay_stack()
	_build_overlay_panel()

func _build_inventory_panel() -> void:
	# Sits just above the bottom HUD bar (the character details), not floating top-left. The HUD
	# bar is 64px tall; offset up past it so carry/consume reads as part of the character row.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.offset_left = 12
	margin.offset_right = 320
	margin.offset_top = -288
	margin.offset_bottom = -72
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_preview_layer.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.028, 0.034, 0.9)
	style.border_color = Color(0.17, 0.21, 0.25, 0.54)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_inventory_panel_title = Label.new()
	_inventory_panel_title.text = "CARRY / CONSUME"
	_inventory_panel_title.add_theme_font_size_override("font_size", 12)
	_inventory_panel_title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	box.add_child(_inventory_panel_title)

	_inventory_panel_label = Label.new()
	_inventory_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_panel_label.custom_minimum_size = Vector2(260, 0)
	_inventory_panel_label.add_theme_font_size_override("font_size", 11)
	_inventory_panel_label.add_theme_color_override("font_color", Color(0.74, 0.77, 0.82))
	box.add_child(_inventory_panel_label)
	_refresh_inventory_panel()

const OVERLAY_PANEL_TOP := 12.0
const OVERLAY_PANEL_EXPANDED_BOTTOM := 260.0
const OVERLAY_PANEL_COLLAPSED_BOTTOM := 56.0  # header-only height when collapsed

func _build_overlay_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.offset_left = -364
	margin.offset_top = OVERLAY_PANEL_TOP
	margin.offset_right = -12
	margin.offset_bottom = OVERLAY_PANEL_EXPANDED_BOTTOM
	# The PanelContainer fills the margin's rect, so a fixed height keeps the dark window full-size
	# even when the content is hidden. Shrink the margin itself on collapse (see _set_overlay_panel_collapsed).
	_overlay_panel_margin = margin
	_preview_layer.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.038, 0.9)
	style.border_color = Color(0.17, 0.19, 0.24, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title := Label.new()
	title.text = "OVERLAY STACK"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.88, 0.9, 0.94))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_overlay_panel_collapse_button = Button.new()
	_overlay_panel_collapse_button.text = "HIDE  O"
	_overlay_panel_collapse_button.add_theme_font_size_override("font_size", 10)
	_overlay_panel_collapse_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_panel_collapse_button.pressed.connect(_toggle_overlay_panel)
	header.add_child(_overlay_panel_collapse_button)

	_overlay_panel_content = VBoxContainer.new()
	_overlay_panel_content.add_theme_constant_override("separation", 6)
	box.add_child(_overlay_panel_content)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.62, 0.68, 0.74))
	hint.text = "Click a selected portrait to swap the primary view. Ctrl-click portraits or Ctrl+1-3 adds and removes party members. Overlays stack together instead of following the primary portrait."
	_overlay_panel_content.add_child(hint)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_overlay_panel_content.add_child(buttons)

	_add_overlay_toggle_button(buttons, "aster", "Aster Data  F1", CHARACTER_COLORS["aster"])
	_add_overlay_toggle_button(buttons, "peris", "Peris Flora  F2", CHARACTER_COLORS["peris"])
	_add_overlay_toggle_button(buttons, "endo", "Endo Survival  F3", CHARACTER_COLORS["endo"])

	_overlay_panel_status_label = Label.new()
	_overlay_panel_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_panel_status_label.custom_minimum_size = Vector2(320, 0)
	_overlay_panel_status_label.add_theme_font_size_override("font_size", 11)
	_overlay_panel_status_label.add_theme_color_override("font_color", Color(0.74, 0.76, 0.8))
	_overlay_panel_content.add_child(_overlay_panel_status_label)
	_refresh_overlay_panel_status()

func _build_overlay_stack() -> void:
	if _overlay_stack_quad != null:
		return
	_overlay_stack_quad = MeshInstance3D.new()
	_overlay_stack_quad.name = "PreviewOverlayQuad"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_overlay_stack_quad.mesh = quad
	_overlay_stack_quad.extra_cull_margin = 10000.0
	_overlay_stack_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_overlay_stack_material = ShaderMaterial.new()
	_overlay_stack_material.shader = PERCEPTION_STACK_SHADER
	_overlay_stack_material.render_priority = 126
	_overlay_stack_quad.material_override = _overlay_stack_material
	_overlay_stack_quad.visible = false
	add_child(_overlay_stack_quad)
	_sync_overlay_stack()

func _add_overlay_toggle_button(parent: VBoxContainer, overlay_id: String, label: String, color: Color) -> void:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 11)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func() -> void:
		_toggle_overlay(overlay_id)
	)
	parent.add_child(button)
	_overlay_buttons[overlay_id] = {
		"button": button,
		"label": label,
		"color": color,
	}
	_refresh_overlay_button(overlay_id)

func _color_with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func _toggle_overlay(overlay_id: String) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = not bool(_overlay_states[overlay_id])
	_refresh_overlay_button(overlay_id)
	_refresh_active_overlay()
	_refresh_overlay_panel_status()
	show_preview_message("%s overlay %s." % [_overlay_display_name(overlay_id), "ON" if bool(_overlay_states[overlay_id]) else "OFF"], 1.2)

func _refresh_overlay_button(overlay_id: String) -> void:
	if not _overlay_buttons.has(overlay_id):
		return
	var info: Dictionary = _overlay_buttons[overlay_id]
	var button: Button = info.get("button")
	var color: Color = info.get("color", Color.WHITE)
	var enabled := bool(_overlay_states.get(overlay_id, false))
	var state_label := "ON" if enabled else "OFF"
	button.text = "%s  %s" % [str(info.get("label", overlay_id)), state_label]

	var normal := StyleBoxFlat.new()
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate()
	var pressed := normal.duplicate()
	if enabled:
		normal.bg_color = _color_with_alpha(color, 0.18)
		normal.border_color = _color_with_alpha(color, 0.7)
		hover.bg_color = _color_with_alpha(color, 0.24)
		hover.border_color = _color_with_alpha(color, 0.84)
		pressed.bg_color = _color_with_alpha(color, 0.32)
		pressed.border_color = _color_with_alpha(color, 0.95)
		button.add_theme_color_override("font_color", _color_with_alpha(color, 0.95))
	else:
		normal.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		normal.border_color = _color_with_alpha(color, 0.28)
		hover.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		hover.border_color = _color_with_alpha(color, 0.45)
		pressed.bg_color = Color(0.11, 0.11, 0.13, 0.95)
		pressed.border_color = _color_with_alpha(color, 0.55)
		button.add_theme_color_override("font_color", _color_with_alpha(color, 0.62))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

func _refresh_all_overlay_buttons() -> void:
	for overlay_id in _overlay_buttons.keys():
		_refresh_overlay_button(str(overlay_id))

func _toggle_overlay_panel() -> void:
	_set_overlay_panel_collapsed(not _overlay_panel_collapsed)

func _set_overlay_panel_collapsed(collapsed: bool) -> void:
	_overlay_panel_collapsed = collapsed
	if _overlay_panel_content != null:
		_overlay_panel_content.visible = not collapsed
	# Shrink the margin itself to the header height — hiding the content alone leaves the
	# PanelContainer filling the fixed margin rect, so the dark window stays full-size.
	if _overlay_panel_margin != null:
		_overlay_panel_margin.offset_bottom = OVERLAY_PANEL_COLLAPSED_BOTTOM if collapsed else OVERLAY_PANEL_EXPANDED_BOTTOM
	if _overlay_panel_collapse_button != null:
		_overlay_panel_collapse_button.text = "SHOW  O" if collapsed else "HIDE  O"

func _refresh_overlay_panel_status() -> void:
	if _overlay_panel_status_label == null:
		return
	var selected_names: Array[String] = []
	for char_id in _selected_char_ids:
		selected_names.append(str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())))

	var lines: Array[String] = []
	lines.append("Selected: %s" % (", ".join(selected_names) if not selected_names.is_empty() else "none"))
	lines.append("Primary: %s" % (CHARACTER_DISPLAY_NAMES.get(_active_char_id, _active_char_id.capitalize()) if _active_char_id != "" else "none"))
	for overlay_id in CHARACTER_IDS:
		var state_label := "ON" if bool(_overlay_states.get(overlay_id, false)) else "OFF"
		lines.append("%s: %s" % [_overlay_display_name(overlay_id), state_label])
		if state_label == "ON" and _active_chunk != null and _active_chunk.has_method("get_preview_overlay_status"):
			for status_line in _active_chunk.call("get_preview_overlay_status", overlay_id, get_preview_scheduler_tick()):
				lines.append("  %s" % str(status_line))
	lines.append("Active overlays combine automatically; you do not need to swap portraits to read them together.")
	_overlay_panel_status_label.text = "\n".join(lines)
	_refresh_all_overlay_buttons()

func _overlay_display_name(overlay_id: String) -> String:
	match overlay_id:
		"aster":
			return "Aster data"
		"peris":
			return "Peris flora"
		"endo":
			return "Endo survival"
		_:
			return overlay_id.capitalize()

func _get_enabled_overlays() -> Array[String]:
	var enabled: Array[String] = []
	for overlay_id in CHARACTER_IDS:
		if bool(_overlay_states.get(overlay_id, false)):
			enabled.append(overlay_id)
	return enabled

func _get_live_overlay_id() -> String:
	var enabled := _get_enabled_overlays()
	return enabled[0] if not enabled.is_empty() else ""

func _refresh_active_overlay() -> void:
	# Standalone previews keep the base sequence perception pass disabled and
	# drive their own stackable fullscreen overlays instead.
	_set_perception_mode("")
	_perception_target = null
	_update_overlay_runtime(0.0)

func _update_survival_overlay() -> void:
	pass

func _update_overlay_runtime(delta: float) -> void:
	_sync_overlay_stack()
	if _active_chunk != null and _active_chunk.has_method("update_preview_overlay_states"):
		_active_chunk.call("update_preview_overlay_states", _overlay_states, get_preview_scheduler_tick(), delta)
	_refresh_preview_items()

func _sync_overlay_stack() -> void:
	if _overlay_stack_material == null or _overlay_stack_quad == null:
		return

	var vision_positions := _get_overlay_vision_positions()
	var data_enabled := bool(_overlay_states.get("aster", false)) and not vision_positions.is_empty()
	var fog_enabled := bool(_overlay_states.get("peris", false)) and not vision_positions.is_empty()
	_overlay_stack_quad.visible = data_enabled or fog_enabled

	var source_0 := _overlay_vision_source_at(vision_positions, 0)
	var source_1 := _overlay_vision_source_at(vision_positions, 1)
	var source_2 := _overlay_vision_source_at(vision_positions, 2)
	var source_count := mini(vision_positions.size(), CHARACTER_IDS.size())

	_overlay_stack_material.set_shader_parameter("data_enabled", data_enabled)
	_overlay_stack_material.set_shader_parameter("data_character_pos", source_0)
	_overlay_stack_material.set_shader_parameter("data_vision_count", source_count)
	_overlay_stack_material.set_shader_parameter("data_vision_pos_1", source_1)
	_overlay_stack_material.set_shader_parameter("data_vision_pos_2", source_2)
	_overlay_stack_material.set_shader_parameter("data_blackout_pos", Vector3(0.0, 0.0, -9999.0))
	_overlay_stack_material.set_shader_parameter("data_blackout_radius", 0.0)
	_overlay_stack_material.set_shader_parameter("fog_enabled", fog_enabled)
	_overlay_stack_material.set_shader_parameter("fog_character_pos", source_0)
	_overlay_stack_material.set_shader_parameter("fog_vision_count", source_count)
	_overlay_stack_material.set_shader_parameter("fog_vision_pos_1", source_1)
	_overlay_stack_material.set_shader_parameter("fog_vision_pos_2", source_2)

func _get_overlay_vision_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for char_id in CHARACTER_IDS:
		if not _characters.has(char_id) or _characters[char_id] == null:
			continue
		if not _character_is_visible(char_id):
			continue
		var character_node := _characters[char_id] as CharacterBody3D
		if character_node == null:
			continue
		positions.append(character_node.global_position + Vector3(0.0, 1.0, 0.0))
	return positions

func _get_overlay_vision_source_state() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for char_id in CHARACTER_IDS:
		if not _characters.has(char_id) or _characters[char_id] == null:
			continue
		if not _character_is_visible(char_id):
			continue
		var character_node := _characters[char_id] as CharacterBody3D
		if character_node == null:
			continue
		sources.append({
			"character_id": char_id,
			"position": character_node.global_position + Vector3(0.0, 1.0, 0.0),
		})
	return sources

func _overlay_vision_source_at(positions: Array[Vector3], index: int) -> Vector3:
	if index >= 0 and index < positions.size():
		return positions[index]
	if not positions.is_empty():
		return positions[0]
	return Vector3(0.0, 0.0, -9999.0)

func _connect_preview_item_signals() -> void:
	if _game_state == null:
		return
	if not _game_state.item_picked_up.is_connected(_on_preview_item_changed):
		_game_state.item_picked_up.connect(_on_preview_item_changed)
	if not _game_state.item_dropped.is_connected(_on_preview_item_changed):
		_game_state.item_dropped.connect(_on_preview_item_changed)
	if not _game_state.item_transferred.is_connected(_on_preview_item_transferred):
		_game_state.item_transferred.connect(_on_preview_item_transferred)
	if not _game_state.item_endocytosed.is_connected(_on_preview_item_endocytosed):
		_game_state.item_endocytosed.connect(_on_preview_item_endocytosed)
	if not _game_state.item_exocytosed.is_connected(_on_preview_item_changed):
		_game_state.item_exocytosed.connect(_on_preview_item_changed)

func _on_preview_item_changed(_char_id: String, _item_id: String) -> void:
	_refresh_inventory_panel()

func _on_preview_item_transferred(_from_id: String, _to_id: String, _item_id: String) -> void:
	_refresh_inventory_panel()

func _on_preview_item_endocytosed(char_id: String, item_id: String, effect: String) -> void:
	_sync_character_from_game_state(char_id)
	if effect == "digest":
		set_preview_character_status(char_id, "")
	elif effect == "stun_self":
		set_preview_character_status(char_id, "stunned")
	elif effect == "self_damage":
		set_preview_character_status(char_id, "hurt")
	else:
		set_preview_character_status(char_id, "")
	_refresh_inventory_panel()
	if effect == "digest":
		show_preview_note("%s digested %s and restored ATP." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 3.2)
	elif effect == "store":
		show_preview_note("%s stored %s internally." % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), get_preview_item_display_name(item_id, char_id)], 3.2)
	elif effect == "stun_self":
		show_preview_note("%s consumed something that should have stayed out of their body." % CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), 3.2)
	elif effect == "self_damage":
		show_preview_note("%s took internal damage from what they consumed." % CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize()), 3.2)

func _ensure_preview_item_node(item_id: String) -> void:
	if _preview_item_nodes.has(item_id):
		return
	if _game_state == null or not _game_state.items.has(item_id):
		return
	var item: Dictionary = _game_state.items[item_id]
	var item_type := str(item.get("type", ""))
	var properties: Dictionary = item.get("properties", {})

	var root := Node3D.new()
	root.name = "PreviewItem_%s" % item_id

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _build_preview_item_mesh(str(properties.get("visual_kind", item_type)))
	var material := StandardMaterial3D.new()
	material.albedo_color = properties.get("visual_color", _preview_item_color(item_type))
	material.emission_enabled = true
	material.emission = material.albedo_color.lightened(0.08)
	material.emission_energy_multiplier = 0.24
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

	var label := Label3D.new()
	label.name = "Label"
	label.pixel_size = 0.0075
	label.font_size = 24
	label.position = Vector3(0.0, 0.65, 0.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	add_child(root)
	_preview_item_nodes[item_id] = root

func _build_preview_item_mesh(visual_kind: String) -> Mesh:
	match visual_kind:
		"gear", "mother_gear":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.34
			torus.outer_radius = 0.58
			torus.rings = 18
			torus.ring_segments = 12
			return torus
		"seed":
			var sphere := SphereMesh.new()
			sphere.radius = 0.18
			sphere.height = 0.36
			return sphere
		"component":
			var box := BoxMesh.new()
			box.size = Vector3(0.34, 0.34, 0.34)
			return box
		_:
			var blob := SphereMesh.new()
			blob.radius = 0.24
			blob.height = 0.48
			return blob

func _preview_item_color(item_type: String) -> Color:
	match item_type:
		"lysate":
			return Color(0.78, 0.68, 0.42)
		"seed":
			return Color(0.56, 0.82, 0.48)
		"cure_component":
			return Color(0.62, 0.82, 0.95)
		"mother_gear":
			return Color(0.84, 0.7, 0.44)
		_:
			return Color(0.78, 0.78, 0.82)

func _refresh_preview_items() -> void:
	if _game_state == null:
		return
	for item_id in _game_state.items.keys():
		_ensure_preview_item_node(str(item_id))

	var existing_ids := _preview_item_nodes.keys().duplicate()
	for raw_id in existing_ids:
		var item_id := str(raw_id)
		if not _game_state.items.has(item_id):
			var stale_node: Node3D = _preview_item_nodes[item_id]
			if stale_node != null:
				stale_node.queue_free()
			_preview_item_nodes.erase(item_id)
			continue

		var item: Dictionary = _game_state.items[item_id]
		var root: Node3D = _preview_item_nodes[item_id]
		if root == null:
			continue
		var label: Label3D = root.get_node("Label")
		label.text = get_preview_item_display_name(item_id, str(item.get("holder", ""))).to_upper()
		var occurrence_count := 0
		var slot_index := -1
		if str(item.get("holder", "")) != "" and _game_state.characters.has(str(item.get("holder", ""))):
			var slots: Array = _game_state.get_hand_slots(str(item.get("holder", "")))
			for i in range(slots.size()):
				if slots[i] == item_id:
					occurrence_count += 1
					if slot_index == -1:
						slot_index = i

		match str(item.get("location", "ground")):
			"ground":
				root.visible = true
				root.global_position = Vector3(item.position.x, 0.42, item.position.z)
				label.visible = true
			"hand":
				root.visible = true
				var holder_id := str(item.get("holder", ""))
				var char_pos := get_preview_character_position(holder_id)
				var offset := Vector3(0.0, 1.02, 0.38)
				if occurrence_count >= 2:
					offset = Vector3(0.0, 1.08, 0.46)
				elif slot_index == 0:
					offset = Vector3(-0.34, 0.98, 0.3)
				elif slot_index == 1:
					offset = Vector3(0.34, 0.98, 0.3)
				root.global_position = char_pos + offset
				label.visible = false
			_:
				root.visible = false

func _refresh_inventory_panel() -> void:
	if _inventory_panel_label == null:
		return
	var lines: Array[String] = []
	lines.append(PREVIEW_INVENTORY_CONTROL_HELP)
	for char_id in CHARACTER_IDS:
		var slot_names: Array[String] = []
		for slot in get_preview_hand_slots(char_id):
			slot_names.append("-" if slot == null else get_preview_item_display_name(str(slot), char_id))
		var internal_names: Array[String] = []
		for item_id in get_preview_internal_items(char_id):
			internal_names.append(get_preview_item_display_name(str(item_id), char_id))
		var status := ""
		if _game_state != null and _game_state.is_endocytosing(char_id):
			status = "  |  consuming"
		lines.append("%s  L:%s  R:%s  In:%s%s" % [
			str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())).to_upper(),
			slot_names[0] if slot_names.size() > 0 else "-",
			slot_names[1] if slot_names.size() > 1 else "-",
			", ".join(internal_names) if not internal_names.is_empty() else "-",
			status,
		])

	var active_item := _get_primary_held_item(_active_char_id)
	if active_item != "":
		lines.append("Active hold: %s" % get_preview_item_display_name(active_item, _active_char_id))
	else:
		lines.append("Active hold: -")

	var collection_names: Array[String] = []
	for item_id in get_preview_collection_items():
		collection_names.append(get_preview_item_display_name(str(item_id)))
	lines.append("Collection: %s" % (", ".join(collection_names) if not collection_names.is_empty() else "-"))
	_inventory_panel_label.text = "\n".join(lines)

func _get_primary_held_item(char_id: String) -> String:
	var held := get_preview_hand_items(char_id)
	return str(held[0]) if held.size() > 0 else ""

func _consume_active_item() -> void:
	if _active_char_id == "":
		return
	var item_id := _get_primary_held_item(_active_char_id)
	if item_id == "":
		show_preview_message("No held item to consume.", 1.1)
		return
	if not endocytose_preview_item(_active_char_id, item_id):
		show_preview_message("That item cannot be consumed here.", 1.2)

func _drop_active_item() -> void:
	if _active_char_id == "":
		return
	var item_id := _get_primary_held_item(_active_char_id)
	if item_id == "":
		show_preview_message("No held item to drop.", 1.1)
		return
	if not drop_preview_item(_active_char_id, item_id):
		show_preview_message("Couldn't drop that item right now.", 1.2)

func _transfer_active_item() -> void:
	if _active_char_id == "":
		return
	var item_id := _get_primary_held_item(_active_char_id)
	if item_id == "":
		show_preview_message("No held item to transfer.", 1.1)
		return
	var target_id := ""
	var best_distance := INF
	for char_id in _selected_char_ids:
		if char_id == _active_char_id or not _character_is_available(char_id):
			continue
		var dist := get_preview_character_position(_active_char_id).distance_to(get_preview_character_position(char_id))
		if dist < best_distance:
			best_distance = dist
			target_id = char_id
	if target_id == "":
		for char_id in CHARACTER_IDS:
			if char_id == _active_char_id or not _character_is_available(char_id):
				continue
			var dist := get_preview_character_position(_active_char_id).distance_to(get_preview_character_position(char_id))
			if dist < best_distance:
				best_distance = dist
				target_id = char_id
	if target_id == "" or not transfer_preview_item(_active_char_id, target_id, item_id):
		show_preview_message("No nearby teammate can take that item.", 1.2)

func _exocytose_active_item() -> void:
	if _active_char_id == "":
		return
	var internal := get_preview_internal_items(_active_char_id)
	if internal.is_empty():
		show_preview_message("No internal item to retrieve.", 1.1)
		return
	if not exocytose_preview_item(_active_char_id, str(internal[0])):
		show_preview_message("Couldn't retrieve that item right now.", 1.2)

func _build_game_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(GameHUDScript)
	add_child(_hud)

	_hud.add_stat_bar("hp", Color(0.72, 0.3, 0.26), DEFAULT_HP, DEFAULT_HP)
	_hud.add_stat_bar("sta", Color(0.3, 0.52, 0.72), DEFAULT_STAMINA, DEFAULT_STAMINA)
	_hud.add_stat_bar("atp", Color(0.34, 0.62, 0.38), DEFAULT_ATP, DEFAULT_ATP)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false, "")
	_hud.show_routing_toggle(_routing_mode)
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.run_toggled.connect(_on_run_toggled)
	_hud.routing_toggled.connect(_on_routing_toggled)
	_hud.ability_pressed.connect(_on_ability_pressed)

	for char_id in CHARACTER_IDS:
		_hud.add_portrait(char_id, CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		_hud.set_portrait_stat(char_id, "hp", DEFAULT_HP)
		_hud.set_portrait_stat(char_id, "sta", DEFAULT_STAMINA)
		_hud.set_portrait_stat(char_id, "atp", DEFAULT_ATP)

	_hud.set_multi_select_enabled(true)
	_hud.character_selection_changed.connect(_on_character_selected)
	_hud.show_time(DEFAULT_DAY, DEFAULT_TIME)

func _initialize_default_character_state() -> void:
	# Previews always start from a clean full-stats GameState. This clears
	# any running flags, cancels drain ticks, and resets HP/stamina/ATP for
	# every registered character. Local _character_state then mirrors it.
	if _game_state != null:
		_game_state.reset_characters_to_full()
	_character_state.clear()
	for char_id in CHARACTER_IDS:
		_character_state[char_id] = {
			"hp": DEFAULT_HP,
			"sta": DEFAULT_STAMINA,
			"atp": DEFAULT_ATP,
			"status": "",
			"visible": true,
		}
		if _characters.has(char_id):
			_characters[char_id].visible = true
			_characters[char_id].set_running(false)
			_characters[char_id].set_move_enabled(false)
		_update_character_in_game_state(char_id)
		_sync_character_hud(char_id)
	_run_active = false

func _apply_chunk_runtime_preset() -> void:
	var chunk_character_state := {}
	var chunk_time_state := {}
	var chunk_abilities: Array = []

	if _active_chunk != null:
		if _active_chunk.has_method("get_preview_character_state"):
			chunk_character_state = _active_chunk.call("get_preview_character_state")
		if _active_chunk.has_method("get_preview_time_state"):
			chunk_time_state = _active_chunk.call("get_preview_time_state")
		if _active_chunk.has_method("get_preview_abilities"):
			chunk_abilities = _active_chunk.call("get_preview_abilities")

	_preview_day = DEFAULT_DAY
	_preview_time = DEFAULT_TIME
	_preview_clock_running = true
	_preview_show_time = true
	_preview_cycle.configure(DEFAULT_DAY_DURATION_SECONDS, DEFAULT_NIGHT_DURATION_SECONDS)
	_routing_mode = "safe"
	_note_default = ""

	_apply_preview_time_state(chunk_time_state)

	for char_id in CHARACTER_IDS:
		if chunk_character_state.has(char_id):
			_apply_character_override(char_id, chunk_character_state[char_id])

	_configure_preview_abilities(chunk_abilities)
	_refresh_overlay_panel_status()
	_refresh_active_overlay()

func _apply_preview_time_state(state: Dictionary) -> void:
	_preview_clock_running = bool(state.get("advance_time", true))
	_preview_show_time = bool(state.get("show_time", true))
	_preview_cycle.configure(
		float(state.get("day_duration_seconds", DEFAULT_DAY_DURATION_SECONDS)),
		float(state.get("night_duration_seconds", DEFAULT_NIGHT_DURATION_SECONDS))
	)
	if state.is_empty():
		_preview_day = DEFAULT_DAY
		_preview_time = DEFAULT_TIME
	else:
		_preview_day = maxi(int(state.get("day", DEFAULT_DAY)), 1)
		_preview_time = clampf(float(state.get("time", DEFAULT_TIME)), 0.0, 1.0)
		_routing_mode = str(state.get("routing_mode", _routing_mode))
		if state.has("note_default"):
			_note_default = str(state.get("note_default", ""))

	_sync_preview_time_presentation()

	if _hud != null:
		_hud.set_routing_mode(_routing_mode)

	if state.has("message"):
		show_preview_message(str(state.get("message", "")), float(state.get("message_duration", 2.0)))
	if state.has("note"):
		show_preview_note(str(state.get("note", "")), float(state.get("note_duration", 3.5)))

func _advance_preview_clock(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	var next_clock: Dictionary = _preview_cycle.advance(_preview_day, _preview_time, delta_seconds)
	var next_day := int(next_clock.get("day", _preview_day))
	var next_time := float(next_clock.get("time", _preview_time))
	if next_day == _preview_day and absf(next_time - _preview_time) <= 0.0001:
		return
	_preview_day = next_day
	_preview_time = next_time
	_sync_preview_time_presentation()

func _sync_preview_time_presentation() -> void:
	if _hud != null:
		if _preview_show_time:
			_hud.show_time(_preview_day, _preview_time)
		else:
			_hud.hide_time()
	_apply_preview_lighting()

func _apply_preview_lighting() -> void:
	if _preview_environment == null or _preview_directional_light == null:
		return

	var normalized := clampf(_preview_time, 0.0, 1.0)
	if normalized < DayNightCycleScript.NIGHT_START:
		var dusk_blend := clampf(normalized / DayNightCycleScript.NIGHT_START, 0.0, 1.0)
		_preview_environment.background_color = Color(0.035, 0.05, 0.075).lerp(Color(0.14, 0.09, 0.06), dusk_blend)
		_preview_environment.ambient_light_color = Color(0.3, 0.36, 0.48).lerp(Color(0.5, 0.33, 0.24), dusk_blend)
		_preview_environment.ambient_light_energy = lerpf(0.62, 0.34, dusk_blend)
		_preview_environment.glow_intensity = lerpf(0.18, 0.28, dusk_blend)
		_preview_directional_light.light_color = Color(0.84, 0.9, 0.98).lerp(Color(0.97, 0.53, 0.26), dusk_blend)
		_preview_directional_light.light_energy = lerpf(1.0, 0.38, dusk_blend)
		return

	var night_blend := clampf((normalized - DayNightCycleScript.NIGHT_START) / DayNightCycleScript.SEGMENT_SPAN, 0.0, 1.0)
	_preview_environment.background_color = Color(0.015, 0.02, 0.035).lerp(Color(0.005, 0.008, 0.015), night_blend)
	_preview_environment.ambient_light_color = Color(0.11, 0.14, 0.21).lerp(Color(0.04, 0.06, 0.1), night_blend)
	_preview_environment.ambient_light_energy = lerpf(0.18, 0.08, night_blend)
	_preview_environment.glow_intensity = lerpf(0.24, 0.12, night_blend)
	_preview_directional_light.light_color = Color(0.22, 0.34, 0.58).lerp(Color(0.1, 0.16, 0.3), night_blend)
	_preview_directional_light.light_energy = lerpf(0.18, 0.06, night_blend)

func _apply_character_override(char_id: String, override: Dictionary) -> void:
	if not _character_state.has(char_id):
		return

	if override.has("hp"):
		_character_state[char_id]["hp"] = clampf(float(override.get("hp", DEFAULT_HP)), 0.0, DEFAULT_HP)
	if override.has("sta"):
		_character_state[char_id]["sta"] = clampf(float(override.get("sta", DEFAULT_STAMINA)), 0.0, DEFAULT_STAMINA)
	if override.has("stamina"):
		_character_state[char_id]["sta"] = clampf(float(override.get("stamina", DEFAULT_STAMINA)), 0.0, DEFAULT_STAMINA)
	if override.has("atp"):
		_character_state[char_id]["atp"] = GameState.clamp_atp(float(override.get("atp", DEFAULT_ATP)))
	if override.has("status"):
		_character_state[char_id]["status"] = str(override.get("status", ""))
	if override.has("visible"):
		_character_state[char_id]["visible"] = bool(override.get("visible", true))

	if _characters.has(char_id):
		_characters[char_id].visible = bool(_character_state[char_id].get("visible", true))

	_update_character_in_game_state(char_id)
	_sync_character_hud(char_id)

## The three party abilities' fallback content + mechanics, sourced from the abilities xlsx (the "default"
## context for the content; the bindings sheet for owner/keybind/color/atp_cost/status/deltas). A chunk's
## get_preview_abilities() overrides the content per scenario.
func _build_default_ability_definitions() -> Dictionary:
	var defs := {}
	for ability_id in ["aster_focus", "peris_tune", "endo_patch"]:
		var d := {"id": ability_id}
		d.merge(AbilityData.get_ability("default." + ability_id), true)  # display_name, duration, cooldown, message, note
		d = _apply_canonical_main_ability_binding(ability_id, d)         # owner, keybind, keycode, color, atp_cost, status, deltas
		defs[ability_id] = d
	return defs

func _configure_preview_abilities(chunk_abilities: Array) -> void:
	_ability_defs.clear()
	_ability_runtime.clear()
	_ability_order.clear()

	var default_defs := _build_default_ability_definitions()
	for ability_id in ["aster_focus", "peris_tune", "endo_patch"]:
		var def: Dictionary = default_defs[ability_id].duplicate(true)
		def = _apply_canonical_main_ability_binding(ability_id, def)
		_ability_defs[ability_id] = def
		_ability_order.append(ability_id)

	for entry in chunk_abilities:
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		var ability_id := str(entry_dict.get("id", ""))
		if ability_id == "":
			continue
		var merged: Dictionary = _ability_defs.get(ability_id, {}).duplicate(true)
		merged.merge(entry_dict, true)
		merged = _apply_canonical_main_ability_binding(ability_id, merged)
		_ability_defs[ability_id] = merged
		if not _ability_order.has(ability_id):
			_ability_order.append(ability_id)

	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs[ability_id]
		_ability_runtime[ability_id] = {
			"base_state": str(ability.get("initial_state", "ready")),
			"remaining": float(ability.get("initial_remaining", 0.0)),
		}
		if _hud != null:
			_hud.add_ability(
				ability_id,
				str(ability.get("display_name", ability_id.to_upper())),
				str(ability.get("keybind", "")),
				ability.get("color", Color(0.7, 0.7, 0.75))
			)

	_refresh_ability_display()

## Apply an ability's MECHANICS from the abilities xlsx bindings sheet (owner / keybind / keycode / color /
## atp_cost / active_status / deltas) — the canonical, per-ability_id values that don't change per context.
func _apply_canonical_main_ability_binding(ability_id: String, ability: Dictionary) -> Dictionary:
	var binding := AbilityData.binding(ability_id)
	if binding.is_empty():
		return ability
	ability["owner"] = str(binding.get("owner", ability.get("owner", "")))
	ability["keybind"] = str(binding.get("keybind", ability.get("keybind", "")))
	ability["keycode"] = int(binding.get("keycode", ability.get("keycode", 0)))
	for k in ["color", "atp_cost", "active_status", "sta_delta", "hp_delta"]:
		if binding.has(k):
			ability[k] = binding[k]
	return ability

func _apply_chunk_metadata() -> void:
	var title := scene_title_override
	if title == "":
		title = preview_chunk.capitalize() + " Fragment"
		if _active_chunk != null and _active_chunk.has_method("get_scene_title"):
			title = str(_active_chunk.call("get_scene_title"))

	var help := ""
	if _active_chunk != null and _active_chunk.has_method("get_scene_help"):
		help = str(_active_chunk.call("get_scene_help"))

	var ability_hints: Array[String] = []
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		var owner := str(ability.get("owner", ""))
		var keybind := str(ability.get("keybind", ""))
		var display := str(ability.get("display_name", ability_id.to_upper()))
		if owner != "" and keybind != "":
			ability_hints.append("%s:%s %s" % [CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()), keybind, display])

	var controls := PREVIEW_CONTROL_HELP
	if not ability_hints.is_empty():
		controls += "  " + "  ".join(ability_hints)

	if _title_label != null:
		_title_label.text = title
	if _help_label != null:
		_help_label.text = help + "\n" + controls if help != "" else controls

	if _note_default == "":
		_note_default = "All three characters start topped off. Run drains stamina and abilities spend ATP."
	if _note_label != null and _note_timer <= 0.0:
		_note_label.text = _note_default

func _position_party_for_chunk() -> void:
	var positions := DEFAULT_SPAWNS.duplicate(true)
	if _active_chunk != null and _active_chunk.has_method("get_spawn_positions"):
		positions.merge(_active_chunk.call("get_spawn_positions"), true)

	for char_id in CHARACTER_IDS:
		if positions.has(char_id):
			headless_set_character_position(char_id, positions[char_id])

## Honour a chunk's PartyPresence node (if any): hide absent members so they
## can't be selected or moved. No node / empty map => keep the full roster.
func _apply_chunk_party_presence() -> void:
	if _active_chunk == null or not _active_chunk.has_method("get_party_presence"):
		return
	var presence: Variant = _active_chunk.call("get_party_presence")
	if not (presence is Dictionary) or (presence as Dictionary).is_empty():
		return
	for char_id in CHARACTER_IDS:
		if (presence as Dictionary).has(char_id):
			set_preview_character_visible(char_id, bool((presence as Dictionary)[char_id]))

func _default_chunk_character() -> String:
	var default_id := "aster"
	if _active_chunk != null and _active_chunk.has_method("get_default_character"):
		default_id = str(_active_chunk.call("get_default_character"))
	if _character_is_available(default_id):
		return default_id
	for char_id in CHARACTER_IDS:
		if _character_is_available(char_id):
			return char_id
	return "aster"

func _cycle_character() -> void:
	if _active_char_id == "":
		_select_character(_default_chunk_character())
		return

	var cycle_ids: Array[String] = _selected_char_ids.duplicate()
	if cycle_ids.size() <= 1:
		cycle_ids.clear()
		for char_id in CHARACTER_IDS:
			if _character_is_available(char_id):
				cycle_ids.append(char_id)
	if cycle_ids.size() <= 1:
		return

	var start_index := cycle_ids.find(_active_char_id)
	for offset in range(1, cycle_ids.size() + 1):
		var next_id: String = cycle_ids[(start_index + offset) % cycle_ids.size()]
		if _character_is_available(next_id):
			_select_character(next_id)
			return

func _toggle_pause() -> void:
	_on_pause_toggled(not (_scheduler != null and _scheduler.is_paused()))

func _toggle_run() -> void:
	_on_run_toggled(not _run_active)

func _select_character(char_id: String) -> void:
	if not _characters.has(char_id):
		return
	if not _character_is_available(char_id):
		return
	var next_selected: Array = [char_id]
	if _selected_char_ids.has(char_id):
		next_selected = _selected_char_ids.duplicate()
	_apply_selection_state(next_selected, char_id)

func _toggle_character_selected(char_id: String) -> void:
	if not _characters.has(char_id) or not _character_is_available(char_id):
		return
	var next_selected := _selected_char_ids.duplicate()
	if next_selected.has(char_id):
		if next_selected.size() <= 1:
			show_preview_message("Keep one character selected.", 1.1)
			return
		next_selected.erase(char_id)
	else:
		next_selected.append(char_id)
	var preferred_active := _active_char_id
	if not next_selected.has(preferred_active) and not next_selected.is_empty():
		preferred_active = next_selected[0]
	_apply_selection_state(next_selected, preferred_active)

func _apply_selection_state(selected_ids: Array, preferred_active := "") -> void:
	var sanitized := _sanitize_selected_ids(selected_ids)
	if sanitized.is_empty():
		var fallback := preferred_active
		if fallback == "" or not _character_is_available(fallback):
			fallback = _active_char_id if _character_is_available(_active_char_id) else _default_chunk_character()
		if fallback == "":
			return
		sanitized = [fallback]

	var next_active := preferred_active
	if next_active == "" or not sanitized.has(next_active):
		next_active = sanitized[0]

	var selection_changed := _selected_char_ids != sanitized
	_selected_char_ids = sanitized
	if _active_char_id != next_active:
		_set_active_character(next_active)
	else:
		_sync_active_stat_panel()
		_refresh_ability_display()
		_refresh_active_overlay()

	if _hud != null:
		_sync_hud_selection()
	if selection_changed:
		var selected_names: Array[String] = []
		for char_id in _selected_char_ids:
			selected_names.append(str(CHARACTER_DISPLAY_NAMES.get(char_id, char_id.capitalize())))
		show_preview_message("Selected: %s" % ", ".join(selected_names), 1.1)
	# Re-wire click-to-move for the new selection (party move when >1 selected). Runs on EVERY
	# selection change, including adding a member while the active stays put (where _set_active_character
	# early-returns and would otherwise leave group_move stale).
	_apply_group_control()
	_refresh_overlay_panel_status()
	_update_survival_overlay()

func _set_active_character(char_id: String) -> void:
	if _active_char_id == char_id:
		return

	if _active_char_id != "" and _characters.has(_active_char_id):
		var previous: CharacterBody3D = _characters[_active_char_id]
		previous.set_move_enabled(false)
		previous.set_running(false)
		if _game_state != null and _game_state.characters.has(_active_char_id):
			_game_state.change_move_speed(_active_char_id, CHARACTER_SPEEDS[_active_char_id])

	_active_char_id = char_id
	_player = _characters[char_id]
	_sync_character_move_enabled()
	if _camera != null:
		_camera.target = _player

	_apply_active_run_state()
	_sync_active_stat_panel()
	_refresh_ability_display()
	_refresh_active_overlay()

	for interactable in _preview_interactables:
		if interactable != null and is_instance_valid(interactable):
			interactable.active_character = _active_char_id

	if _active_chunk != null and _active_chunk.has_method("on_preview_character_selected"):
		_active_chunk.call("on_preview_character_selected", char_id)

func _sync_character_move_enabled() -> void:
	for char_id in CHARACTER_IDS:
		var character_node = _characters.get(char_id, null)
		if character_node != null and character_node.has_method("set_move_enabled"):
			character_node.call("set_move_enabled", char_id == _active_char_id)

## Push the dodge-roll setting onto every party member's stats. Off (the default) means enemy strikes
## land; on means they can auto-evade. Derived preview state — set from a toggle, not the data log.
func _apply_dodge_setting() -> void:
	if _game_state == null:
		return
	for char_id in CHARACTER_IDS:
		if _game_state.characters.has(char_id):
			var st: Dictionary = _game_state.characters[char_id].stats
			st["dodge_unlocked"] = _preview_dodge_unlocked
			st["auto_dodge"] = _preview_dodge_unlocked

## Wire click-to-move for the current selection. With more than one selected, the party moves as one:
## the active character's controller issues a spread party move (set_party + group_move on the active
## node only), and the others are carried by that move, not their own clicks. Single select: just the
## active character moves. Mirrors the elevator's _apply_character_control_selection.
func _apply_group_control() -> void:
	var group_control := _selected_char_ids.size() > 1
	if group_control and _game_state != null:
		_game_state.set_party(_selected_char_ids.duplicate())
	for char_id in CHARACTER_IDS:
		var node = _characters.get(char_id, null)
		if node == null:
			continue
		var is_active: bool = char_id == _active_char_id
		if node.has_method("set_move_enabled"):
			node.call("set_move_enabled", is_active)
		if "group_move" in node:
			node.set("group_move", group_control and is_active)

func _sanitize_selected_ids(selected_ids: Array) -> Array[String]:
	var sanitized: Array[String] = []
	for raw_id in selected_ids:
		var char_id := str(raw_id)
		if not CHARACTER_IDS.has(char_id):
			continue
		if not _character_is_available(char_id):
			continue
		if sanitized.has(char_id):
			continue
		sanitized.append(char_id)
	return sanitized

func _sync_hud_selection() -> void:
	if _hud == null:
		return
	_suppress_hud_character_signal = true
	_hud.set_selected_portraits(_selected_char_ids)
	if _active_char_id != "":
		_hud.set_active_portrait(_active_char_id, true)
	_suppress_hud_character_signal = false

func _ensure_valid_selection() -> void:
	var sanitized := _sanitize_selected_ids(_selected_char_ids)
	var preferred_active := _active_char_id
	if preferred_active == "" or not _character_is_available(preferred_active):
		preferred_active = sanitized[0] if not sanitized.is_empty() else ""
	_apply_selection_state(sanitized, preferred_active)

func _apply_active_run_state() -> void:
	if _active_char_id == "" or not _characters.has(_active_char_id):
		return
	if get_preview_character_stat(_active_char_id, "sta") <= 0.0:
		_run_active = false

	var active_node: CharacterBody3D = _characters[_active_char_id]
	active_node.set_running(_run_active)
	if _game_state != null and _game_state.characters.has(_active_char_id):
		var target_speed: float = active_node.run_speed if _run_active else float(CHARACTER_SPEEDS[_active_char_id])
		_game_state.change_move_speed(_active_char_id, target_speed)
	if _hud != null:
		_hud.set_run_mode(_run_active)

func _on_run_toggled(is_running: bool) -> void:
	_run_active = is_running and _character_is_available(_active_char_id) and get_preview_character_stat(_active_char_id, "sta") > 0.0
	_apply_active_run_state()

func _on_pause_toggled(is_paused: bool) -> void:
	if _scheduler == null:
		return
	if is_paused:
		_scheduler.pause()
	else:
		_scheduler.resume()
	if _hud != null:
		_hud.set_paused(_scheduler.is_paused())

func _on_routing_toggled(mode: String) -> void:
	_routing_mode = "direct" if mode == "direct" else "safe"
	if _hud != null:
		_hud.set_routing_mode(_routing_mode)
	show_preview_message("Routing: %s" % _routing_mode.to_upper(), 1.2)
	if _active_chunk != null and _active_chunk.has_method("on_preview_routing_changed"):
		_active_chunk.call("on_preview_routing_changed", _routing_mode)

func _on_character_selected(selected_ids: Array) -> void:
	if _suppress_hud_character_signal:
		return
	var preferred_active := str(selected_ids[0]) if selected_ids.size() > 0 else ""
	_apply_selection_state(selected_ids, preferred_active)

func _on_ability_pressed(ability_id: String) -> void:
	_activate_preview_ability(ability_id)

func _activate_preview_ability(ability_id: String) -> void:
	if not _ability_defs.has(ability_id) or not _ability_runtime.has(ability_id):
		return

	var ability: Dictionary = _ability_defs[ability_id]
	var runtime: Dictionary = _ability_runtime[ability_id]
	var owner := str(ability.get("owner", ""))

	if owner != "" and owner != _active_char_id:
		show_preview_message("%s is not active." % CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()), 1.1)
		return
	if owner != "" and not _character_is_available(owner):
		show_preview_message("%s is unavailable." % CHARACTER_DISPLAY_NAMES.get(owner, owner.capitalize()), 1.1)
		return
	if str(runtime.get("base_state", "ready")) != "ready":
		return

	var atp_cost := float(ability.get("atp_cost", 0.0))
	var stamina_cost := float(ability.get("stamina_cost", 0.0))
	if owner != "" and get_preview_character_stat(owner, "atp") < atp_cost:
		show_preview_message("Not enough ATP.", 1.1)
		return
	if owner != "" and get_preview_character_stat(owner, "sta") < stamina_cost:
		show_preview_message("Not enough stamina.", 1.1)
		return

	if owner != "" and atp_cost > 0.0:
		adjust_preview_character_stat(owner, "atp", -atp_cost)
	if owner != "" and stamina_cost > 0.0:
		adjust_preview_character_stat(owner, "sta", -stamina_cost)

	var result := {}
	if _active_chunk != null and _active_chunk.has_method("handle_preview_ability"):
		result = _active_chunk.call("handle_preview_ability", ability_id, ability)
	if not (result is Dictionary):
		result = {}

	var combined: Dictionary = ability.duplicate(true)
	combined.merge(result, true)
	_apply_preview_ability_result(owner, combined)

	var duration := float(combined.get("duration", 0.0))
	var cooldown := float(combined.get("cooldown", 0.0))
	var next_state := str(combined.get("state", ""))
	if next_state == "":
		next_state = "active" if duration > 0.0 else ("cooldown" if cooldown > 0.0 else "ready")
	var remaining := float(combined.get("remaining", duration if next_state == "active" else cooldown))
	_set_runtime_ability_state(ability_id, next_state, remaining)

func _apply_preview_ability_result(owner: String, combined: Dictionary) -> void:
	var message := str(combined.get("message", ""))
	if message != "":
		show_preview_message(message, float(combined.get("message_duration", 1.8)))

	var note := str(combined.get("note", ""))
	if note != "":
		show_preview_note(note, float(combined.get("note_duration", 3.5)))

	if owner != "":
		var hp_delta := float(combined.get("hp_delta", 0.0))
		var sta_delta := float(combined.get("sta_delta", combined.get("stamina_delta", 0.0)))
		var atp_delta := float(combined.get("atp_delta", 0.0))
		if hp_delta != 0.0:
			adjust_preview_character_stat(owner, "hp", hp_delta)
		if sta_delta != 0.0:
			adjust_preview_character_stat(owner, "sta", sta_delta)
		if atp_delta != 0.0:
			adjust_preview_character_stat(owner, "atp", atp_delta)

	if combined.has("characters"):
		var characters: Dictionary = combined.get("characters", {})
		for char_id in characters.keys():
			var entry: Dictionary = characters[char_id]
			if entry.has("hp"):
				set_preview_character_stat(char_id, "hp", float(entry.get("hp", DEFAULT_HP)))
			if entry.has("sta"):
				set_preview_character_stat(char_id, "sta", float(entry.get("sta", DEFAULT_STAMINA)))
			if entry.has("stamina"):
				set_preview_character_stat(char_id, "sta", float(entry.get("stamina", DEFAULT_STAMINA)))
			if entry.has("atp"):
				set_preview_character_stat(char_id, "atp", float(entry.get("atp", DEFAULT_ATP)))
			if entry.has("hp_delta"):
				adjust_preview_character_stat(char_id, "hp", float(entry.get("hp_delta", 0.0)))
			if entry.has("sta_delta"):
				adjust_preview_character_stat(char_id, "sta", float(entry.get("sta_delta", 0.0)))
			if entry.has("stamina_delta"):
				adjust_preview_character_stat(char_id, "sta", float(entry.get("stamina_delta", 0.0)))
			if entry.has("atp_delta"):
				adjust_preview_character_stat(char_id, "atp", float(entry.get("atp_delta", 0.0)))
			if entry.has("status"):
				set_preview_character_status(char_id, str(entry.get("status", "")))
			if entry.has("visible"):
				set_preview_character_visible(char_id, bool(entry.get("visible", true)))

	if combined.has("routing_mode"):
		_on_routing_toggled(str(combined.get("routing_mode", _routing_mode)))
	if combined.has("time_state") and combined.get("time_state") is Dictionary:
		_apply_preview_time_state(combined.get("time_state", {}))

func _set_runtime_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	if not _ability_runtime.has(ability_id):
		return

	var previous_state := str(_ability_runtime[ability_id].get("base_state", "ready"))
	var ability: Dictionary = _ability_defs.get(ability_id, {})
	var owner := str(ability.get("owner", ""))
	var active_status := str(ability.get("active_status", ""))

	_ability_runtime[ability_id]["base_state"] = state
	_ability_runtime[ability_id]["remaining"] = maxf(0.0, remaining)

	if owner != "":
		if state == "active" and active_status != "":
			set_preview_character_status(owner, active_status)
		elif previous_state == "active" and active_status != "" and str(_character_state.get(owner, {}).get("status", "")) == active_status:
			set_preview_character_status(owner, "")

	_refresh_ability_display(ability_id)

func _update_ability_timers(delta: float, spd: float) -> void:
	if spd <= 0.0:
		return

	for ability_id in _ability_order:
		if not _ability_runtime.has(ability_id):
			continue
		var runtime: Dictionary = _ability_runtime[ability_id]
		var state := str(runtime.get("base_state", "ready"))
		if state not in ["active", "cooldown"]:
			continue
		var remaining := maxf(0.0, float(runtime.get("remaining", 0.0)) - delta * spd)
		runtime["remaining"] = remaining
		_ability_runtime[ability_id] = runtime
		if remaining > 0.0:
			_refresh_ability_display(ability_id)
			continue

		var cooldown := float(_ability_defs.get(ability_id, {}).get("cooldown", 0.0))
		if state == "active" and cooldown > 0.0:
			_set_runtime_ability_state(ability_id, "cooldown", cooldown)
		else:
			_set_runtime_ability_state(ability_id, "ready", 0.0)

func _refresh_ability_display(ability_id := "") -> void:
	if _hud == null:
		return

	var ids: Array[String] = []
	if ability_id == "":
		for current_id in _ability_order:
			ids.append(current_id)
	else:
		ids.append(String(ability_id))
	for current_id in ids:
		if not _ability_defs.has(current_id) or not _ability_runtime.has(current_id):
			continue

		var ability: Dictionary = _ability_defs[current_id]
		var runtime: Dictionary = _ability_runtime[current_id]
		var owner := str(ability.get("owner", ""))
		var display_state := str(runtime.get("base_state", "ready"))
		var display_remaining := float(runtime.get("remaining", 0.0))

		if owner != "":
			if not _character_is_available(owner) or owner != _active_char_id:
				display_state = "disabled"
				display_remaining = 0.0
			elif display_state == "ready":
				var atp_cost := float(ability.get("atp_cost", 0.0))
				var stamina_cost := float(ability.get("stamina_cost", 0.0))
				if get_preview_character_stat(owner, "atp") < atp_cost or get_preview_character_stat(owner, "sta") < stamina_cost:
					display_state = "disabled"
					display_remaining = 0.0

		_hud.set_ability_state(current_id, display_state, display_remaining)

func _get_ability_for_keycode(keycode: int) -> String:
	var fallback := ""
	for ability_id in _ability_order:
		var ability: Dictionary = _ability_defs.get(ability_id, {})
		var mapped_keycode := int(ability.get("keycode", 0))
		if mapped_keycode == 0:
			var keybind := str(ability.get("keybind", "")).to_upper()
			mapped_keycode = int(ABILITY_KEYCODES.get(keybind, 0))
		if mapped_keycode == keycode:
			if str(ability.get("owner", "")) == _active_char_id:
				return ability_id
			if fallback == "":
				fallback = ability_id
	return fallback

func _activate_keybound_preview_ability(keycode: int) -> bool:
	var ability_id := _get_ability_for_keycode(keycode)
	if ability_id == "":
		return false
	_activate_preview_ability(ability_id)
	return true

func _update_stamina(delta: float, spd: float) -> void:
	if _active_char_id == "" or not _character_state.has(_active_char_id):
		return
	if spd <= 0.0:
		return

	var current_stamina := get_preview_character_stat(_active_char_id, "sta")
	var next_stamina := current_stamina
	var moving := false
	if _game_state != null and _game_state.characters.has(_active_char_id):
		moving = _game_state.is_moving(_active_char_id)

	if _run_active and moving:
		next_stamina -= STAMINA_DRAIN * delta * spd
		if next_stamina <= 0.0:
			next_stamina = 0.0
			if _run_active:
				_run_active = false
				_apply_active_run_state()
				show_preview_message("Stamina exhausted.", 1.2)
	elif moving:
		next_stamina += STAMINA_REGEN * 0.35 * delta * spd
	else:
		next_stamina += STAMINA_REGEN * delta * spd

	if absf(next_stamina - current_stamina) > 0.001:
		set_preview_character_stat(_active_char_id, "sta", next_stamina)

func _update_character_in_game_state(char_id: String) -> void:
	if _game_state == null or not _game_state.characters.has(char_id):
		return
	var runtime_char: Dictionary = _game_state.characters[char_id]
	var stats: Dictionary = runtime_char.get("stats", {}).duplicate(true)
	stats["hp"] = float(_character_state.get(char_id, {}).get("hp", DEFAULT_HP))
	stats["stamina"] = float(_character_state.get(char_id, {}).get("sta", DEFAULT_STAMINA))
	stats["atp"] = float(_character_state.get(char_id, {}).get("atp", DEFAULT_ATP))
	runtime_char["stats"] = stats

func _sync_character_from_game_state(char_id: String) -> void:
	if _game_state == null or not _game_state.characters.has(char_id) or not _character_state.has(char_id):
		return
	var runtime_char: Dictionary = _game_state.characters[char_id]
	var stats: Dictionary = runtime_char.get("stats", {})
	_character_state[char_id]["hp"] = float(stats.get("hp", DEFAULT_HP))
	_character_state[char_id]["sta"] = float(stats.get("stamina", DEFAULT_STAMINA))
	_character_state[char_id]["atp"] = float(stats.get("atp", DEFAULT_ATP))
	_sync_character_hud(char_id)

func _sync_character_hud(char_id: String) -> void:
	if _hud == null or not _character_state.has(char_id):
		return

	var state: Dictionary = _character_state[char_id]
	_hud.set_portrait_stat(char_id, "hp", float(state.get("hp", DEFAULT_HP)))
	_hud.set_portrait_stat(char_id, "sta", float(state.get("sta", DEFAULT_STAMINA)))
	_hud.set_portrait_stat(char_id, "atp", float(state.get("atp", DEFAULT_ATP)))

	var display_status := str(state.get("status", ""))
	if not bool(state.get("visible", true)):
		display_status = "offline"
	elif float(state.get("hp", 0.0)) <= 0.0 and display_status == "":
		display_status = "downed"
	_hud.set_portrait_status(char_id, display_status)
	_hud.set_portrait_alert(char_id, float(state.get("hp", DEFAULT_HP)) <= 35.0 or float(state.get("sta", DEFAULT_STAMINA)) <= 20.0)

	if char_id == _active_char_id:
		_sync_active_stat_panel()
	_refresh_overlay_panel_status()
	_update_survival_overlay()

func _sync_active_stat_panel() -> void:
	if _hud == null or _active_char_id == "" or not _character_state.has(_active_char_id):
		return
	var state: Dictionary = _character_state[_active_char_id]
	_hud.set_stat("hp", float(state.get("hp", DEFAULT_HP)))
	_hud.set_stat("sta", float(state.get("sta", DEFAULT_STAMINA)))
	_hud.set_stat("atp", float(state.get("atp", DEFAULT_ATP)))
	_update_survival_overlay()

func _normalize_stat_name(stat_name: String) -> String:
	match stat_name.strip_edges().to_lower():
		"hp", "health":
			return "hp"
		"sta", "stamina":
			return "sta"
		"atp":
			return "atp"
		_:
			return stat_name.strip_edges().to_lower()

func _character_is_visible(char_id: String) -> bool:
	if not _character_state.has(char_id):
		return false
	return bool(_character_state[char_id].get("visible", true))

func _character_is_available(char_id: String) -> bool:
	if not _character_state.has(char_id):
		return false
	return _character_is_visible(char_id) and float(_character_state[char_id].get("hp", 0.0)) > 0.0
