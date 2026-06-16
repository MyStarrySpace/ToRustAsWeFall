@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const FloraMemorySystem = preload("res://scripts/system/simulation/flora_memory_system.gd")

## Act 1 chunk sequence: Channels, Stacks, Rings, Lockout.

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _endo: CharacterBody3D
var _active_character := "aster"
var _channels_ferrolure: MeshInstance3D
var _channels_ferrolure_light: OmniLight3D
var _channels_flow_strips: Array[MeshInstance3D] = []
var _channels_flush_swarm_units: Array[Dictionary] = []
var _channels_run_lure_mesh: MeshInstance3D
var _channels_run_lure_light: OmniLight3D
var _channels_run_lure_interactable
var _channels_hide_spot: Node3D
var _channels_swarm_units: Array[Dictionary] = []
var _channels_window_lanes: Dictionary = {}
var _channels_active_window_lane := ""
var _channels_shortcut_gate_mesh: MeshInstance3D
var _channels_shortcut_gate_collision: CollisionShape3D
var _channels_shortcut_light: OmniLight3D
var _channels_run_lure_active := false
var _channels_run_lure_expire_tick := -1.0
var _channels_party_hidden := false
var _channels_encounter_resetting := false
var _channels_flow_power := 0.0
var _channels_flush_state := ""
var _channels_flush_timer := 0.0
var _channels_shortcut_unlocked := false
var _channels_party_recuperated := false
var _channels_shelter_reached := false

const STACKS_SUPPORT_LOG_KEY := "stacks_support_team_log"
var _stacks_signal_interactable
var _stacks_terminal_interactable
var _stacks_workspace_interactable
var _stacks_support_log_entry_id := -1
var _stacks_support_log_presented := false
var _stacks_signal_interacted := false
var _stacks_terminal_interacted := false
var _stacks_archive_interacted := false
var _stacks_audit_flags_found := false

@export var start_chunk := ""

# Iron hazard zones
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0

# HP
var _aster_hp := 100.0
var _peris_hp := 100.0

# Naturalizers (lockout chase)
var _naturalizers: Array[Node3D] = []

# Overlay + flora state
var _overlay_ui: CanvasLayer
var _overlay_buttons: Dictionary = {}
var _overlay_note_label: Label
var _overlay_status_label: Label
var _overlay_note_timer := 0.0
var _overlay_states := {
	"aster": true,
	"peris": true,
}
var _flora_overlay_root: Node3D
var _flora_marker_nodes: Dictionary = {}
var _flora_nodes: Dictionary = {}
var _flora_system := FloraMemorySystem.new()

const FLORA_SMELL_RADIUS := 2.25

# Linear progression along +X.
const CHANNELS_START := Vector3(0, 0, 0)
const CHANNELS_END := Vector3(228, 0, 0)
const CHANNELS_MEMORY_TRIGGER_X := 54.0
const CHANNELS_BODY_POS := Vector3(74.0, 0.5, -3.0)
const CHANNELS_WINDOW_ONE_STAGE_POS := Vector3(104.0, 0.5, -2.0)
const CHANNELS_WINDOW_ONE_LURE_POS := Vector3(110.0, 0.5, -13.0)
const CHANNELS_WINDOW_ONE_CURTAIN_POS := Vector3(122.0, 0.6, -1.0)
const CHANNELS_WINDOW_ONE_GOAL_POS := Vector3(132.0, 0.5, 0.0)
const CHANNELS_WINDOW_ONE_DURATION := 13.5
const CHANNELS_FERROLURE_TRIGGER_X := 146.0
const CHANNELS_FERROLURE_POS := Vector3(156.0, 0.5, 9.0)
const CHANNELS_FLUSH_SWARM_POS := Vector3(162.0, 0.6, 8.8)
const CHANNELS_FLUSH_SWARM_OFFSETS := [-1.6, -0.8, 0.0, 0.8, 1.6]
const CHANNELS_WINDOW_TWO_STAGE_POS := Vector3(166.0, 0.5, 2.0)
const CHANNELS_WINDOW_TWO_LURE_POS := Vector3(170.0, 0.5, 13.0)
const CHANNELS_WINDOW_TWO_CURTAIN_POS := Vector3(179.0, 0.6, 1.0)
const CHANNELS_WINDOW_TWO_GOAL_POS := Vector3(184.0, 0.5, 0.0)
const CHANNELS_WINDOW_TWO_DURATION := 9.5
const CHANNELS_ENCOUNTER_TRIGGER_X := 192.0
const CHANNELS_ENCOUNTER_ENTRY_POS := Vector3(194.0, 0.5, 3.0)
const CHANNELS_RUN_LURE_POS := Vector3(198.0, 0.5, 1.5)
const CHANNELS_HIDE_SPOT_POS := Vector3(204.0, 0.5, -10.0)
const CHANNELS_SWARM_CLUSTER_X := 211.0
const CHANNELS_SWARM_DETECT_RADIUS := 2.2
const CHANNELS_SWARM_SPEED := 1.7
const CHANNELS_RUN_LURE_DURATION := 20.0
const CHANNELS_SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]
const CHANNELS_WINDOW_CURTAIN_OFFSETS := [-4.0, -2.0, 0.0, 2.0, 4.0]
const CHANNELS_WINDOW_DETECT_RADIUS := 3.0
const CHANNELS_WINDOW_PERIODIC_CHANNELS := 3
const CHANNELS_WINDOW_FLOW_PERIOD := 6.0
const CHANNELS_WINDOW_FLOOD_DURATION := 4.0
const CHANNELS_WINDOW_SWARM_SPEED := 3.6
const CHANNELS_WINDOW_SWARM_DELAY := 0.12
const CHANNELS_WINDOW_SWARM_WASH_SPEED := 8.6
const CHANNELS_WINDOW_CHANNEL_WASH_RADIUS := 1.9
const CHANNELS_WINDOW_CHANNEL_T_VALUES := [0.30, 0.48, 0.66]
const CHANNELS_WINDOW_SWARM_OFFSETS := [-1.4, -0.7, 0.0, 0.7, 1.4]
const CHANNELS_SHORTCUT_BRANCH_POS := Vector3(186.0, 0.5, 6.0)
const CHANNELS_SHORTCUT_GATE_POS := Vector3(186.0, 0.5, 10.4)
const CHANNELS_SHELTER_POS := Vector3(216.0, 0.5, 12.0)
const CHANNELS_REST_ATP := 8.0
const CHANNELS_MAX_HP := 100.0
const STACKS_START := Vector3(240, 0, 0)
const STACKS_END := Vector3(460, 0, 0)
const RINGS_START := Vector3(480, 0, 0)
const RINGS_END := Vector3(680, 0, 0)
const LOCKOUT_START := Vector3(700, 0, 0)
const LOCKOUT_BOUNDARY := Vector3(780, 0, 0)

# --- Per-chunk grids ---
# act1 CUTS between chunks (each loads as the previous unloads), so only one chunk is live at a time.
# Each gets its own OPEN GridWorld over its corridor footprint (a generous bounding rect from its
# START..END span); the active grid swaps in when its chunk loads. Movement is then cell-based +
# cooperative per chunk, without a single impractical world-spanning grid.
const CHUNK_GRIDS := {
	"channels": {"origin": Vector3(-6, 0, -16), "size": Vector2i(242, 32)},   # X[-6,236]
	"stacks": {"origin": Vector3(234, 0, -16), "size": Vector2i(232, 32)},    # X[234,466]
	"rings": {"origin": Vector3(474, 0, -16), "size": Vector2i(212, 32)},     # X[474,686]
	"lockout": {"origin": Vector3(694, 0, -16), "size": Vector2i(92, 32)},    # X[694,786]
}
var _grid: GridWorld

## Build + activate the named chunk's OPEN grid, swapping it in as the live grid. The party re-derives
## its cells on the new grid (derived state); only one chunk grid is live at a time (act1 cuts between).
func _activate_chunk_grid(chunk_name: String) -> void:
	var spec = CHUNK_GRIDS.get(chunk_name)
	if spec == null or _game_state == null:
		return
	var size: Vector2i = spec["size"]
	_grid = GridWorld.new()
	_grid.origin = spec["origin"]
	_grid.create_room(size.x, size.y, false)
	_game_state.grid = _grid
	for node in [_aster_node, _peris_node, _endo]:
		if node != null and "grid_world" in node:
			node.grid_world = _grid
	for id in _game_state.characters.keys():
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(_game_state.get_position(id))

# --- Chunk dispatch ---

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"channels": _build_channels_chunk(parent)
		"stacks": _build_stacks_chunk(parent)
		"rings": _build_rings_chunk(parent)
		"lockout": _build_lockout_chunk(parent)

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.2, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.2
	we.environment = e
	env.add_child(we)
	_load_chunk("channels")

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = CHANNELS_START + Vector3(1, 0.5, 0)
	chars.add_child(_player)
	_aster_node = _player

	# Peris
	_peris_node = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_peris_node.position = CHANNELS_START + Vector3(0, 0.5, 1)
	chars.add_child(_peris_node)

	# Endo joins during the Channels encounter.
	_endo = _create_player_character("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = CHANNELS_START + Vector3(-1, 0.5, 0)
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8), true)

func _register_characters() -> void:
	_activate_chunk_grid("channels")  # the live grid for the opening chunk
	_register_gs_character("aster", _aster_node, 3.0, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("peris", _peris_node, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("endo", _endo, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})

func _setup_ui() -> void:
	_build_overlay_ui()
	_flora_overlay_root = Node3D.new()
	_flora_overlay_root.name = "FloraOverlayRoot"
	add_child(_flora_overlay_root)
	_apply_overlay_visibility()
	_select_character("aster")

func _begin() -> void:
	_player.set_move_enabled(false)
	if start_chunk != "":
		_load_chunk(start_chunk)
		_player.set_move_enabled(true)
		match start_chunk:
			"channels":
				_player.global_position = CHANNELS_START + Vector3(5, 0.5, 0)
				_start_channels_enter()
			"stacks":
				_player.global_position = STACKS_START + Vector3(5, 0.5, 0)
				_start_stacks_enter()
			"rings":
				_player.global_position = RINGS_START + Vector3(5, 0.5, 0)
				_start_rings_enter()
			"lockout":
				_player.global_position = LOCKOUT_START + Vector3(5, 0.5, 0)
				_start_lockout_approach()
		return
	_fade_from(Color(0.02, 0.02, 0.03, 1), 2.5, _start_channels_enter, "channels_enter")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_F1:
				_toggle_overlay("aster")
			KEY_F2:
				_toggle_overlay("peris")

func _on_process(delta: float, spd: float) -> void:
	var channels_script_locked := _current_step in [
		"channels_window_one_intro",
		"channels_window_one_activate",
		"channels_window_one_cross",
		"channels_window_one_reset",
		"channels_window_two_intro",
		"channels_window_two_activate",
		"channels_window_two_cross",
		"channels_window_two_reset",
		"channels_encounter_intro",
		"channels_encounter_activate",
		"channels_encounter_hide",
		"channels_encounter_run",
		"channels_encounter_reset",
		"channels_memory",
		"channels_corpse",
		"channels_ferrolure",
		"channels_shelter",
	]

	# Iron patch damage
	for pair in [["aster", _aster_node], ["peris", _peris_node]]:
		var cid: String = pair[0]
		var cnode: Node3D = pair[1]
		if not cnode:
			continue
		var hp: float = _aster_hp if cid == "aster" else _peris_hp
		if hp <= 0:
			continue
		var cpos := cnode.global_position
		for patch in _iron_patches:
			var ppos: Vector3 = patch.pos
			var psz: Vector3 = patch.size
			if absf(cpos.x - ppos.x) < psz.x / 2.0 and absf(cpos.z - ppos.z) < psz.z / 2.0:
				var dmg := IRON_DAMAGE_PER_SEC * delta * spd
				if cid == "aster":
					_aster_hp = maxf(0.0, _aster_hp - dmg)
				else:
					_peris_hp = maxf(0.0, _peris_hp - dmg)
				break

	_update_channels_encounter(delta, spd)
	_update_channels_ferrolure_flush(delta, spd)
	_update_channels_window_puzzles(delta, spd)
	_update_overlay_note(delta)
	_update_flora_system()

	# Followers trail the leader outside cutscenes.
	if not channels_script_locked:
		var leader := _get_character_node(_active_character)
		for pair in [
			["aster", _aster_node, Vector3(-1.2, 0, 0.8)],
			["peris", _peris_node, Vector3(-1.2, 0, 1.2)],
			["endo", _endo, Vector3(-1.2, 0, -0.8)],
		]:
			var cid: String = pair[0]
			var cnode: CharacterBody3D = pair[1]
			var offset: Vector3 = pair[2]
			if cid == _active_character or cnode == null or not cnode.visible or not _game_state.characters.has(cid):
				continue
			var dist := cnode.global_position.distance_to(leader.global_position)
			if dist > 3.0 and not _game_state.is_moving(cid):
				_game_state.command_move_to_pos(cid, leader.global_position + offset)

	# Position gates
	if _current_step == "channels_to_memory":
		if _game_state.get_position("aster").x > CHANNELS_MEMORY_TRIGGER_X:
			_start_channels_memory()

	if _current_step == "channels_to_ferrolure":
		if _game_state.get_position("aster").x > CHANNELS_FERROLURE_TRIGGER_X:
			_start_channels_ferrolure()

	if _current_step == "channels_to_encounter":
		if _game_state.get_position("aster").x > CHANNELS_ENCOUNTER_TRIGGER_X:
			_start_channels_encounter_intro()

	if _current_step == "channels_explore":
		if _game_state.get_position("aster").x > CHANNELS_END.x - 5.0:
			_start_stacks_enter()

	if _current_step == "stacks_explore":
		if _game_state.get_position("aster").x > STACKS_END.x - 5.0:
			_start_rings_enter()

	if _current_step == "rings_explore":
		if _game_state.get_position("aster").x > RINGS_END.x - 5.0:
			_start_lockout_approach()

	# Lockout chase: Naturalizers walk toward party, stop at boundary
	if _current_step == "lockout_chase":
		for nk in _naturalizers:
			if is_instance_valid(nk):
				var nk_pos := nk.global_position
				var aster_pos := _aster_node.global_position
				# Stop at the unserviced boundary.
				if aster_pos.x < LOCKOUT_START.x - 10.0:
					_start_lockout_exile()
					break

# --- Step functions ---

func _get_character_node(id: String) -> CharacterBody3D:
	match id:
		"aster":
			return _aster_node
		"peris":
			return _peris_node
		"endo":
			return _endo
		_:
			return null

func _set_interactable_active_character(id: String) -> void:
	for node in find_children("*", "", true, false):
		if node.has_signal("interacted") and node.has_method("get_dwell_progress"):
			node.set("active_character", id)

func _select_character(id: String) -> void:
	var next := _get_character_node(id)
	if next == null:
		return
	for cid in ["aster", "peris", "endo"]:
		var node := _get_character_node(cid)
		if node:
			node.set_move_enabled(cid == id)
	_player = next
	_active_character = id
	_set_interactable_active_character(id)
	match id:
		"aster":
			_focus_aster_view()
		"peris":
			_focus_peris_view()
		"endo":
			_focus_endo_view()

func _focus_aster_view() -> void:
	if _camera:
		_camera.target = _aster_node
	_apply_overlay_visibility()

func _focus_peris_view() -> void:
	if _camera:
		_camera.target = _peris_node
	_apply_overlay_visibility()

func _focus_endo_view() -> void:
	if _camera:
		_camera.target = _endo
	_apply_overlay_visibility()

func _build_overlay_ui() -> void:
	_overlay_ui = CanvasLayer.new()
	_overlay_ui.name = "Act1OverlayUI"
	_overlay_ui.layer = 12
	add_child(_overlay_ui)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.offset_left = -360
	margin.offset_top = 12
	margin.offset_right = -12
	margin.offset_bottom = 220
	_overlay_ui.add_child(margin)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.03, 0.04, 0.88)
	panel_style.border_color = Color(0.16, 0.16, 0.2, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons)

	_add_overlay_button(buttons, "aster", "Aster Data  F1", Color(0.29, 0.62, 1.0))
	_add_overlay_button(buttons, "peris", "Peris Flora  F2", Color(1.0, 0.67, 0.27))

	_overlay_note_label = Label.new()
	_overlay_note_label.add_theme_font_size_override("font_size", 11)
	_overlay_note_label.add_theme_color_override("font_color", Color(0.92, 0.76, 0.58))
	_overlay_note_label.modulate.a = 0.0
	vbox.add_child(_overlay_note_label)

	_overlay_status_label = Label.new()
	_overlay_status_label.add_theme_font_size_override("font_size", 11)
	_overlay_status_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	_overlay_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_status_label.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_overlay_status_label)

	_update_overlay_status({})

func _add_overlay_button(parent: HBoxContainer, overlay_id: String, text: String, color: Color) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	var normal := StyleBoxFlat.new()
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal.duplicate())
	button.add_theme_stylebox_override("pressed", normal.duplicate())
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func() -> void:
		_toggle_overlay(overlay_id)
	)
	parent.add_child(button)
	_overlay_buttons[overlay_id] = {
		"button": button,
		"color": color,
	}
	_refresh_overlay_button(overlay_id)

func _toggle_overlay(overlay_id: String) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = not bool(_overlay_states[overlay_id])
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()
	_show_overlay_note("%s overlay %s" % [overlay_id.capitalize(), "ON" if bool(_overlay_states[overlay_id]) else "OFF"])

func _refresh_overlay_button(overlay_id: String) -> void:
	if not _overlay_buttons.has(overlay_id):
		return
	var info: Dictionary = _overlay_buttons[overlay_id]
	var button: Button = info.get("button")
	var color: Color = info.get("color", Color.WHITE)
	var enabled := bool(_overlay_states.get(overlay_id, false))
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
	var hover: StyleBoxFlat = button.get_theme_stylebox("hover")
	var pressed: StyleBoxFlat = button.get_theme_stylebox("pressed")
	if enabled:
		normal.bg_color = Color(color, 0.18)
		normal.border_color = Color(color, 0.7)
		hover.bg_color = Color(color, 0.24)
		hover.border_color = Color(color, 0.85)
		pressed.bg_color = Color(color, 0.32)
		pressed.border_color = Color(color, 0.95)
		button.add_theme_color_override("font_color", Color(color, 0.95))
	else:
		normal.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		normal.border_color = Color(color, 0.28)
		hover.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		hover.border_color = Color(color, 0.45)
		pressed.bg_color = Color(0.11, 0.11, 0.13, 0.95)
		pressed.border_color = Color(color, 0.55)
		button.add_theme_color_override("font_color", Color(color, 0.6))

func _show_overlay_note(text: String, duration := 2.2) -> void:
	if _overlay_note_label == null:
		return
	_overlay_note_label.text = text
	_overlay_note_label.modulate.a = 0.95
	_overlay_note_timer = duration

func _update_overlay_note(delta: float) -> void:
	if _overlay_note_timer <= 0.0 or _overlay_note_label == null:
		return
	_overlay_note_timer = maxf(0.0, _overlay_note_timer - delta)
	if _overlay_note_timer <= 0.0:
		_overlay_note_label.modulate.a = 0.0

func _apply_overlay_visibility() -> void:
	if bool(_overlay_states.get("aster", false)):
		_setup_perception("data", _aster_node)
	else:
		if _perception_quad:
			_perception_quad.visible = false

func _update_overlay_status(snapshot: Dictionary) -> void:
	if _overlay_status_label == null:
		return
	var lines: Array[String] = [
		"Aster data: %s" % ("ON" if bool(_overlay_states.get("aster", false)) else "OFF"),
		"Peris flora: %s" % ("ON" if bool(_overlay_states.get("peris", false)) else "OFF"),
	]
	if bool(_overlay_states.get("peris", false)):
		if snapshot.is_empty():
			lines.append("")
			lines.append("Peris flora network is idle.")
		else:
			var relational: Dictionary = snapshot.get("relational", {})
			var words: Dictionary = snapshot.get("layer_words", {})
			lines.append("")
			lines.append("Network: %s" % ("bright" if bool(snapshot.get("window_active", false)) else "dormant"))
			if bool(snapshot.get("window_active", false)):
				lines.append("Read window: %.0fs" % float(snapshot.get("time_remaining", 0.0)))
			lines.append("Species: %s" % str(words.get("species", "clear")))
			lines.append("Health: %s" % str(words.get("health", "steady")))
			lines.append("Context: %s" % str(words.get("context", "readable")))
			lines.append("Direction: %s" % str(words.get("direction", "precise")))
			lines.append("Memory: %s" % str(words.get("memory", "anchored")))
			var scent := str(relational.get("scent", "none"))
			if scent == "none":
				lines.append("Forget-me-nots: scentless")
			elif scent == "flicker":
				lines.append("Forget-me-nots: flicker")
			else:
				lines.append("Forget-me-nots: %s" % scent)
	else:
		lines.append("")
		lines.append("Peris overlay hidden.")
	_overlay_status_label.text = "\n".join(lines)

func _update_flora_system() -> void:
	var current_tick := _scheduler.get_current_tick()
	var zone := _current_flora_zone()
	_flora_system.set_stage(_current_flora_stage())

	if zone != "":
		for node_id in _flora_nodes.keys():
			var info: Dictionary = _flora_nodes[node_id]
			if str(info.get("zone", "")) != zone:
				continue
			var pos: Vector3 = info.get("position", Vector3.ZERO)
			if _peris_node and _peris_node.visible and _peris_node.global_position.distance_to(pos) <= FLORA_SMELL_RADIUS:
				if _flora_system.can_activate_node(node_id, current_tick):
					var read := _flora_system.start_read(node_id, current_tick)
					if bool(read.get("started", false)):
						_show_overlay_note(str(read.get("message", "")))

	var snapshot := _flora_system.get_overlay_snapshot(current_tick, zone)
	_update_overlay_status(snapshot)
	_update_flora_markers(snapshot)

func _update_flora_markers(snapshot: Dictionary) -> void:
	for marker_id in _flora_marker_nodes.keys():
		var marker: Label3D = _flora_marker_nodes[marker_id]
		if marker:
			marker.visible = false

	if not bool(_overlay_states.get("peris", false)):
		return

	var clues: Array = snapshot.get("visible_clues", [])
	for clue_data in clues:
		var clue: Dictionary = clue_data
		var marker := _get_flora_marker(str(clue.get("id", "")))
		var signal_type := str(clue.get("signal_type", "memory"))
		var certainty := float(clue.get("certainty", 0.6))
		marker.position = clue.get("display_pos", Vector3.ZERO) + Vector3(0.0, 2.2, 0.0)
		marker.text = str(clue.get("signal_label", "")).to_upper()
		marker.modulate = Color(_flora_signal_color(signal_type), 0.2 + certainty * 0.75)
		marker.visible = true

func _get_flora_marker(id: String) -> Label3D:
	if _flora_marker_nodes.has(id):
		return _flora_marker_nodes[id]
	var marker := Label3D.new()
	marker.name = "FloraMarker_%s" % id
	marker.font_size = 28
	marker.pixel_size = 0.008
	marker.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.visible = false
	_flora_overlay_root.add_child(marker)
	_flora_marker_nodes[id] = marker
	return marker

func _flora_signal_color(signal_type: String) -> Color:
	match signal_type:
		"threat":
			return Color(0.92, 0.46, 0.32)
		"hazard", "iron":
			return Color(0.94, 0.64, 0.28)
		"resource", "cache":
			return Color(0.56, 0.84, 0.56)
		"relationship":
			return Color(0.6, 0.76, 0.95)
		_:
			return Color(1.0, 0.77, 0.42)

func _current_flora_zone() -> String:
	if _current_step.begins_with("channels"):
		return "channels"
	if _current_step.begins_with("stacks"):
		return "stacks"
	if _current_step.begins_with("rings"):
		return "rings"
	return ""

func _current_flora_stage() -> int:
	if _current_step.begins_with("channels"):
		return FloraMemorySystem.Stage.EARLY
	if _current_step.begins_with("stacks"):
		return FloraMemorySystem.Stage.MID
	if _current_step in ["rings_enter", "rings_client"]:
		return FloraMemorySystem.Stage.LATE_MID
	if _current_step.begins_with("rings") or _current_step.begins_with("lockout"):
		return FloraMemorySystem.Stage.LATE
	return FloraMemorySystem.Stage.EARLY

func get_capture_context() -> Dictionary:
	var zone_label := _capture_zone_label()
	var sub_location := _humanize_capture_token(_current_step)
	return {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "",
		"timestamp_label": "Act 1 / Day 1",
		"location": zone_label,
		"sub_location": sub_location,
		"trigger_type": "manual",
		"trigger_context": _current_step if _current_step != "" else "manual_capture",
		"position": _player.global_position if _player != null else Vector3.ZERO,
		"caption": "%s, Day 1" % zone_label,
	}

func build_save_snapshot() -> Dictionary:
	var snapshot := super.build_save_snapshot()
	snapshot["act1"] = {
		"active_character": _active_character,
		"overlay_states": _overlay_states.duplicate(true),
		"stacks_state": {
			"support_log_entry_id": _stacks_support_log_entry_id,
			"support_log_presented": _stacks_support_log_presented,
			"signal_interacted": _stacks_signal_interacted,
			"terminal_interacted": _stacks_terminal_interacted,
			"archive_interacted": _stacks_archive_interacted,
			"audit_flags_found": _stacks_audit_flags_found,
		},
	}
	return snapshot

func apply_save_snapshot(data: Dictionary) -> void:
	super.apply_save_snapshot(data)
	var act1_data: Dictionary = data.get("act1", {})
	if act1_data.has("overlay_states"):
		_overlay_states = act1_data.get("overlay_states", {}).duplicate(true)
		for overlay_id in _overlay_buttons.keys():
			_refresh_overlay_button(overlay_id)
		_apply_overlay_visibility()
	var active_character := str(act1_data.get("active_character", _active_character))
	if active_character != "":
		_select_character(active_character)
	var stacks_state: Dictionary = act1_data.get("stacks_state", {})
	_stacks_support_log_entry_id = int(stacks_state.get("support_log_entry_id", _stacks_support_log_entry_id))
	_stacks_support_log_presented = bool(stacks_state.get("support_log_presented", _stacks_support_log_presented))
	_stacks_signal_interacted = bool(stacks_state.get("signal_interacted", _stacks_signal_interacted))
	_stacks_terminal_interacted = bool(stacks_state.get("terminal_interacted", _stacks_terminal_interacted))
	_stacks_archive_interacted = bool(stacks_state.get("archive_interacted", _stacks_archive_interacted))
	_stacks_audit_flags_found = bool(stacks_state.get("audit_flags_found", _stacks_audit_flags_found))

func _capture_zone_label() -> String:
	if _current_step.begins_with("channels"):
		return "Perivascular Channels"
	if _current_step.begins_with("stacks"):
		return "Processing Stacks"
	if _current_step.begins_with("rings"):
		return "Residential Rings"
	if _current_step.begins_with("lockout"):
		return "Lockout Corridor"
	return "Act 1"

func _add_flora_node(parent: Node3D, id: String, species: String, zone: String, pos: Vector3, signal_type: String, signal_label: String, signal_pos: Vector3, color: Color, relationship_strength := 0.55, extra: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.name = "Flora_%s" % id
	root.position = pos
	parent.add_child(root)

	for i in range(3):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = 0.42 + float(i) * 0.08
		stem.mesh = stem_mesh
		var stem_mat := StandardMaterial3D.new()
		stem_mat.albedo_color = color.darkened(0.45)
		stem.material_override = stem_mat
		stem.position = Vector3(-0.18 + float(i) * 0.18, 0.2, -0.05 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.015
		bloom_mesh.height = 0.22 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_mat := StandardMaterial3D.new()
		bloom_mat.albedo_color = color
		bloom_mat.emission_enabled = true
		bloom_mat.emission = color
		bloom_mat.emission_energy_multiplier = 0.25
		bloom.material_override = bloom_mat
		bloom.position = Vector3(-0.18 + float(i) * 0.18, 0.48 + float(i) * 0.09, -0.05 + sin(float(i)) * 0.08)
		root.add_child(bloom)

	_flora_nodes[id] = {
		"zone": zone,
		"position": pos,
		"node": root,
	}
	_flora_system.register_node(id, {
		"species": species,
		"zone": zone,
		"position": pos,
		"signal_type": signal_type,
		"signal_label": signal_label,
		"signal_pos": signal_pos,
		"relationship_strength": relationship_strength,
		"tended": bool(extra.get("tended", false)),
		"childhood_species": bool(extra.get("childhood_species", false)),
		"role": str(extra.get("role", "sensor")),
		"forget_me_not": bool(extra.get("forget_me_not", false)),
	})

func _wait_for_arrivals(ids: Array[String], next_func: Callable, tag: String) -> void:
	var poll: Callable
	poll = func() -> void:
		for id in ids:
			if _game_state.is_moving(id):
				_scheduler.schedule_after(0.1, poll, tag)
				return
		_scheduler.schedule_after(0.0, next_func, tag)
	_scheduler.schedule_after(0.0, poll, tag)

func _move_party_and_continue(destinations: Dictionary, next_func: Callable, tag: String) -> void:
	var ids: Array[String] = []
	for id in destinations.keys():
		ids.append(id)
		_game_state.command_move_to_pos(id, destinations[id])
	_wait_for_arrivals(ids, next_func, tag)

func _set_channels_ferrolure_active(active: bool) -> void:
	if _channels_ferrolure:
		var mat := _channels_ferrolure.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.4 if active else 0.25
	if _channels_ferrolure_light:
		_channels_ferrolure_light.light_energy = 2.0 if active else 0.45

func _set_channels_flow_power(power: float) -> void:
	_channels_flow_power = clampf(power, 0.0, 1.0)
	for strip in _channels_flow_strips:
		if strip == null:
			continue
		var mat := strip.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.15, 0.2).lerp(Color(0.16, 0.24, 0.34), _channels_flow_power)
			mat.emission_energy_multiplier = lerpf(0.3, 1.35, _channels_flow_power)

func _channels_window_branch_direction(stage_pos: Vector3, lure_pos: Vector3) -> Vector3:
	var branch := lure_pos - stage_pos
	branch.y = 0.0
	if branch.length() <= 0.001:
		return Vector3.FORWARD
	return branch.normalized()

func _channels_window_cross_direction(branch_dir: Vector3) -> Vector3:
	return Vector3(-branch_dir.z, 0.0, branch_dir.x).normalized()

func _channels_window_add_wrapped_interval(intervals: Array, start: float, duration: float, period: float) -> void:
	var wrapped_start := fposmod(start, period)
	var end := wrapped_start + duration
	if end <= period:
		intervals.append({"start": wrapped_start, "end": end})
		return
	intervals.append({"start": wrapped_start, "end": period})
	intervals.append({"start": 0.0, "end": end - period})

func _channels_window_offset_washes(lane: Dictionary, flow_offset: float) -> bool:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var local_phase := fposmod(
			flow_offset
			+ float(channel.get("contact_time", 0.0))
			+ float(channel.get("phase_offset", 0.0)),
			period
		)
		if local_phase < flood_duration:
			return true
	return false

func _channels_window_wash_analysis(lane: Dictionary, sample_count := 72) -> Dictionary:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	var intervals: Array = []
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var start := -float(channel.get("contact_time", 0.0)) - float(channel.get("phase_offset", 0.0))
		_channels_window_add_wrapped_interval(intervals, start, flood_duration, period)
	intervals.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))
	var merged: Array = []
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if merged.is_empty():
			merged.append(interval.duplicate(true))
			continue
		var current: Dictionary = merged[merged.size() - 1]
		if float(interval.get("start", 0.0)) <= float(current.get("end", 0.0)) + 0.0001:
			current["end"] = maxf(float(current.get("end", 0.0)), float(interval.get("end", 0.0)))
			merged[merged.size() - 1] = current
			continue
		merged.append(interval.duplicate(true))
	var largest_gap := period
	if not merged.is_empty():
		largest_gap = 0.0
		for i in range(merged.size()):
			var current: Dictionary = merged[i]
			var next: Dictionary = merged[(i + 1) % merged.size()]
			var gap := float(next.get("start", 0.0)) - float(current.get("end", 0.0))
			if i == merged.size() - 1:
				gap = float(next.get("start", 0.0)) + period - float(current.get("end", 0.0))
			largest_gap = maxf(largest_gap, gap)
	var failed_offsets: Array = []
	for i in range(maxi(1, sample_count)):
		var offset := period * float(i) / float(maxi(1, sample_count))
		if not _channels_window_offset_washes(lane, offset):
			failed_offsets.append(offset)
	return {
		"guaranteed": largest_gap <= 0.0001 and failed_offsets.is_empty(),
		"coverage_gap": maxf(0.0, largest_gap),
		"sample_count": maxi(1, sample_count),
		"failed_offsets": failed_offsets,
	}

func _channels_window_local_phase(current_tick: float, lane: Dictionary, channel: Dictionary) -> float:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	return fposmod(
		current_tick
		+ float(lane.get("flow_offset", 0.0))
		+ float(channel.get("phase_offset", 0.0)),
		period
	)

func _channels_window_channel_level(local_phase: float, flood_duration: float, period: float) -> float:
	if local_phase < flood_duration:
		var flood_t := clampf(local_phase / maxf(flood_duration, 0.001), 0.0, 1.0)
		return 0.68 + 0.32 * sin(PI * flood_t)
	var cooldown_t := clampf((local_phase - flood_duration) / maxf(period - flood_duration, 0.001), 0.0, 1.0)
	return lerpf(0.28, 0.08, cooldown_t)

func _add_channels_window_bridge_segment(parent: Node3D, name: String, from_pos: Vector3, to_pos: Vector3) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.45, 0.18, maxf(0.8, from_pos.distance_to(to_pos) + 0.35))
	segment.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.48, 0.3, 0.12)
	mat.emission_energy_multiplier = 0.15
	segment.material_override = mat
	segment.position = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.72, 0.0)
	segment.look_at_from_position(segment.position, to_pos + Vector3(0.0, 0.72, 0.0), Vector3.UP, true)
	parent.add_child(segment)
	return segment

func _reset_channels_window_swarm(lane: Dictionary) -> Dictionary:
	lane["swarm_state"] = "idle"
	lane["washed_channel_index"] = -1
	lane["swarm_start_tick"] = -1.0
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "idle"
		unit["path_index"] = 0
		unit["wash_vector"] = Vector3.ZERO
		var node: MeshInstance3D = unit.get("node")
		if is_instance_valid(node):
			node.visible = true
			node.scale = Vector3.ONE
			node.position = unit.get("base_pos", node.position)
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	return lane

func _trigger_channels_window_swarm_wash(window_id: String, lane: Dictionary, channel_index: int, current_tick: float) -> Dictionary:
	var branch_dir: Vector3 = lane.get("branch_dir", Vector3.FORWARD)
	var cross_dir: Vector3 = lane.get("cross_dir", Vector3.RIGHT)
	lane["swarm_state"] = "washing"
	lane["washed_channel_index"] = channel_index
	lane["swarm_start_tick"] = current_tick
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "wash"
		unit["wash_vector"] = branch_dir * CHANNELS_WINDOW_SWARM_WASH_SPEED + cross_dir * (CHANNELS_WINDOW_SWARM_OFFSETS[i] * 0.65)
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	_channels_window_lanes[window_id] = lane
	return lane

func _set_channels_shortcut_unlocked(unlocked: bool) -> void:
	_channels_shortcut_unlocked = unlocked
	if _channels_shortcut_gate_collision:
		_channels_shortcut_gate_collision.disabled = unlocked
	if _channels_shortcut_gate_mesh:
		_channels_shortcut_gate_mesh.visible = not unlocked
	if _channels_shortcut_light:
		_channels_shortcut_light.light_color = Color(0.88, 0.72, 0.44) if unlocked else Color(0.34, 0.42, 0.54)
		_channels_shortcut_light.light_energy = 2.0 if unlocked else 0.8

func _recuperate_channels_party() -> void:
	_channels_party_recuperated = true
	_aster_hp = CHANNELS_MAX_HP
	_peris_hp = CHANNELS_MAX_HP
	for char_id in ["aster", "peris", "endo"]:
		if _game_state == null or not _game_state.characters.has(char_id):
			continue
		var stats: Dictionary = _game_state.characters[char_id].stats
		stats["hp"] = CHANNELS_MAX_HP
		stats["atp"] = CHANNELS_REST_ATP

func _start_channels_ferrolure_flush() -> void:
	_channels_flush_state = "pull"
	_channels_flush_timer = 0.0
	_set_channels_flow_power(0.55)
	for i in range(_channels_flush_swarm_units.size()):
		var unit := _channels_flush_swarm_units[i]
		unit["state"] = "pull"
		unit["active"] = true
		if unit.get("node") != null:
			unit["node"].visible = true
		_channels_flush_swarm_units[i] = unit

func _update_channels_ferrolure_flush(delta: float, spd: float) -> void:
	if _channels_flush_state == "":
		if _channels_flow_power > 0.001:
			_set_channels_flow_power(maxf(0.0, _channels_flow_power - delta * spd * 0.5))
		return

	_channels_flush_timer += delta * spd
	match _channels_flush_state:
		"pull":
			_set_channels_flow_power(0.7 + 0.25 * absf(sin(_channels_flush_timer * 3.2)))
			for i in range(_channels_flush_swarm_units.size()):
				var unit := _channels_flush_swarm_units[i]
				if not bool(unit.get("active", false)):
					continue
				var node: MeshInstance3D = unit.get("node")
				if node == null:
					continue
				var target := CHANNELS_FERROLURE_POS + Vector3(0.45 * CHANNELS_FLUSH_SWARM_OFFSETS[i], 0.15, -0.4)
				node.position = node.position.move_toward(target, delta * spd * 3.2)
			if _channels_flush_timer >= 1.1:
				_channels_flush_state = "wash"
				_channels_flush_timer = 0.0
		"wash":
			_set_channels_flow_power(1.0)
			for i in range(_channels_flush_swarm_units.size()):
				var unit := _channels_flush_swarm_units[i]
				if not bool(unit.get("active", false)):
					continue
				var node: MeshInstance3D = unit.get("node")
				if node == null:
					continue
				node.position.x += delta * spd * 7.5
				node.position.y = maxf(0.18, node.position.y - delta * spd * 0.35)
				node.scale = node.scale.lerp(Vector3.ONE * 0.4, clampf(delta * spd * 2.5, 0.0, 1.0))
			if _channels_flush_timer >= 1.1:
				_channels_flush_state = "cooldown"
				_channels_flush_timer = 0.0
		"cooldown":
			_set_channels_flow_power(maxf(0.0, 0.9 - _channels_flush_timer * 1.5))
			if _channels_flush_timer >= 0.6:
				for i in range(_channels_flush_swarm_units.size()):
					var unit := _channels_flush_swarm_units[i]
					var node: MeshInstance3D = unit.get("node")
					if node:
						node.visible = false
						node.scale = Vector3.ONE
						node.position = unit.get("base_pos", node.position)
					unit["active"] = false
					unit["state"] = ""
					_channels_flush_swarm_units[i] = unit
				_channels_flush_state = ""
				_channels_flush_timer = 0.0
				_set_channels_flow_power(0.25)

func _set_channels_run_lure_active(active: bool) -> void:
	_channels_run_lure_active = active
	if _channels_run_lure_mesh:
		var mat := _channels_run_lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.0 if active else 0.35
	if _channels_run_lure_light:
		_channels_run_lure_light.light_energy = 2.4 if active else 0.5

func _show_marker(pos: Vector3, text: String, tint := Color(0.4, 0.7, 0.5, 0.75)) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = tint
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	var env: Node = find_child("Environment", false, false)
	if env:
		env.add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	if env == null:
		return
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _get_channels_window_party_positions(window_id: String) -> Dictionary:
	match window_id:
		"window_one":
			return {
				"aster": CHANNELS_WINDOW_ONE_STAGE_POS,
				"peris": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		"window_two":
			return {
				"aster": CHANNELS_WINDOW_TWO_STAGE_POS,
				"peris": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		_:
			return {}

func _channels_window_step_name(window_id: String, suffix: String) -> String:
	return "channels_%s_%s" % [window_id, suffix]

func _set_channels_window_lane_active(window_id: String, active: bool) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["lure_active"] = active
	var lure_mesh = lane.get("lure_mesh")
	if is_instance_valid(lure_mesh):
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.9 if active else 0.35
	var lure_light = lane.get("lure_light")
	if is_instance_valid(lure_light):
		lure_light.light_energy = 2.1 if active else 0.45
	_channels_window_lanes[window_id] = lane

func _reset_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _scheduler:
		_scheduler.cancel_tag("channels_%s_expire" % window_id)
		_scheduler.cancel_tag("channels_%s_retry" % window_id)
	_set_channels_window_lane_active(window_id, false)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "idle"
	lane["safe_until_tick"] = -1.0
	lane["last_outcome"] = ""
	lane["flow_offset"] = 0.0
	var curtain_nodes: Array = lane.get("curtain_nodes", [])
	var curtain_pos: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
	for i in range(curtain_nodes.size()):
		var node = curtain_nodes[i]
		if is_instance_valid(node):
			node.position = curtain_pos + Vector3(0, 0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
	if lane.has("interactable"):
		var interactable = lane["interactable"]
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.show_tutorial_label()
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _begin_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if not _enter_step(_channels_window_step_name(window_id, "activate")):
		return
	_channels_active_window_lane = window_id
	_select_character("aster")
	_player.set_move_enabled(true)
	_reset_channels_window_lane(window_id)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "activate"
	_channels_window_lanes[window_id] = lane
	_clear_markers()
	_show_marker(lane["lure_pos"] + Vector3(0, 2.0, 0), "LURE", Color(0.76, 0.46, 0.2, 0.85))
	_show_marker(lane["goal_pos"] + Vector3(0, 2.0, 0), "CROSS", Color(0.36, 0.74, 0.88, 0.85))
	_tutorial_prompt.show_prompt("Hold at the lure, then cross before the channel fills again")

func _on_channels_window_lure_activated(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if bool(lane.get("lure_active", false)):
		return
	_set_channels_window_lane_active(window_id, true)
	lane = _channels_window_lanes[window_id]
	lane["phase"] = "cross"
	var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
	lane["safe_until_tick"] = current_tick + float(lane.get("safe_duration", 0.0))
	lane["swarm_state"] = "advancing"
	lane["swarm_start_tick"] = current_tick
	lane["washed_channel_index"] = -1
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "advance"
		unit["path_index"] = 1
		unit["wash_vector"] = Vector3.ZERO
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	_channels_window_lanes[window_id] = lane
	_enter_step(_channels_window_step_name(window_id, "cross"))
	if lane.has("interactable"):
		var interactable = lane["interactable"]
		if is_instance_valid(interactable):
			interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt("Move. The corridor stays clear only while the lure holds")
	_scheduler.cancel_tag("channels_%s_expire" % window_id)
	_scheduler.schedule_after(float(lane.get("safe_duration", 0.0)), func():
		_on_channels_window_lure_expired(window_id)
	, "channels_%s_expire" % window_id)

func _on_channels_window_lure_expired(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step != _channels_window_step_name(window_id, "cross"):
		return
	_set_channels_window_lane_active(window_id, false)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["safe_until_tick"] = -1.0
	_channels_window_lanes[window_id] = lane
	_fail_channels_window_lane(window_id, "window_closed")

func _fail_channels_window_lane(window_id: String, reason: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if str(lane.get("phase", "")) == "failed":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	lane["phase"] = "failed"
	lane["last_outcome"] = reason
	_channels_window_lanes[window_id] = lane
	_tutorial_prompt.show_prompt("Too slow. The Techos spill back into the lane.")
	_clear_markers()
	_show_marker(lane["curtain_pos"] + Vector3(0, 2.0, 0), "BLOCKED", Color(0.86, 0.28, 0.22, 0.88))
	_scheduler.schedule_after(1.0, func():
		_restart_channels_window_lane(window_id)
	, "channels_%s_retry" % window_id)

func _restart_channels_window_lane(window_id: String) -> void:
	if not _enter_step(_channels_window_step_name(window_id, "reset")):
		return
	var party_positions := _get_channels_window_party_positions(window_id)
	_move_party_and_continue(party_positions, func():
		_begin_channels_window_lane(window_id)
	, "channels_%s_reset_move" % window_id)

func _complete_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "safe"
	lane["last_outcome"] = "success"
	lane["safe_until_tick"] = -1.0
	_channels_window_lanes[window_id] = lane
	_channels_active_window_lane = ""
	_set_channels_window_lane_active(window_id, false)
	_scheduler.cancel_tag("channels_%s_expire" % window_id)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	match window_id:
		"window_one":
			_start_channels_to_ferrolure()
		"window_two":
			_start_channels_to_encounter()

func _update_channels_window_puzzles(delta: float, spd: float) -> void:
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
		var flow_period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
		var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
		var periodic_channels: Array = lane.get("periodic_channels", [])
		for i in range(periodic_channels.size()):
			var channel: Dictionary = periodic_channels[i]
			var local_phase := _channels_window_local_phase(current_tick, lane, channel)
			var level := _channels_window_channel_level(local_phase, flood_duration, flow_period)
			channel["local_phase"] = local_phase
			channel["level"] = level
			channel["flooded"] = local_phase < flood_duration
			var water = channel.get("water")
			var water_height := -0.22
			var water_scale := maxf(0.08, level)
			if is_instance_valid(water):
				water.scale = Vector3(1.0, water_scale, 1.0)
				water.position.y = -0.42 + water.scale.y * 0.46
				water_height = water.position.y
				var water_mat := water.material_override as StandardMaterial3D
				if water_mat:
					water_mat.emission_energy_multiplier = lerpf(0.2, 1.3, level)
			var foam = channel.get("foam")
			if is_instance_valid(foam):
				foam.position.y = water_height + 0.42 * water_scale
				foam.visible = bool(channel.get("flooded", false))
				var foam_mat := foam.material_override as StandardMaterial3D
				if foam_mat:
					foam_mat.albedo_color.a = 0.35 + 0.45 * level
					foam_mat.emission_energy_multiplier = lerpf(0.08, 0.48, level)
			var light = channel.get("light")
			if is_instance_valid(light):
				light.light_energy = lerpf(0.2, 1.15, level)
			periodic_channels[i] = channel
		lane["periodic_channels"] = periodic_channels

		var swarm_state := str(lane.get("swarm_state", "idle"))
		var swarm_path: Array = lane.get("swarm_path", [])
		var channel_contact_map: Dictionary = lane.get("channel_contact_map", {})
		var swarm_units: Array = lane.get("swarm_units", [])
		if swarm_state == "advancing":
			var wash_triggered := false
			var wash_channel_index := -1
			var all_lured := not swarm_units.is_empty()
			for i in range(swarm_units.size()):
				var unit: Dictionary = swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					swarm_units[i] = unit
					continue
				if current_tick < float(lane.get("swarm_start_tick", -1.0)) + float(unit.get("delay", 0.0)):
					all_lured = false
					swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					swarm_units[i] = unit
					continue
				var path_index := int(unit.get("path_index", 0))
				if path_index >= swarm_path.size():
					unit["state"] = "lured"
					swarm_units[i] = unit
					continue
				all_lured = false
				var target: Vector3 = swarm_path[path_index]
				node.position = node.position.move_toward(target, delta * spd * CHANNELS_WINDOW_SWARM_SPEED)
				if node.position.distance_to(target) <= 0.08:
					if channel_contact_map.has(path_index):
						var candidate_channel_index := int(channel_contact_map[path_index])
						if candidate_channel_index >= 0 and candidate_channel_index < periodic_channels.size():
							var contact_channel: Dictionary = periodic_channels[candidate_channel_index]
							if bool(contact_channel.get("flooded", false)):
								wash_triggered = true
								wash_channel_index = candidate_channel_index
					unit["path_index"] = path_index + 1
					if int(unit.get("path_index", 0)) >= swarm_path.size():
						unit["state"] = "lured"
				swarm_units[i] = unit
				if wash_triggered:
					break
			lane["swarm_units"] = swarm_units
			if wash_triggered:
				lane = _trigger_channels_window_swarm_wash(window_id, lane, wash_channel_index, current_tick)
				periodic_channels = lane.get("periodic_channels", periodic_channels)
				swarm_units = lane.get("swarm_units", swarm_units)
			elif all_lured:
				lane["swarm_state"] = "escaped"
		elif swarm_state == "washing":
			var washed_count := 0
			for i in range(swarm_units.size()):
				var unit: Dictionary = swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					washed_count += 1
					swarm_units[i] = unit
					continue
				var wash_vector: Vector3 = unit.get("wash_vector", Vector3.ZERO)
				node.position += wash_vector * delta * spd
				node.position.y -= delta * spd * 1.6
				node.scale = node.scale.move_toward(Vector3.ONE * 0.28, delta * spd * 1.2)
				if current_tick - float(lane.get("swarm_start_tick", current_tick)) >= 1.1 + float(unit.get("delay", 0.0)) * 0.5:
					node.visible = false
					unit["state"] = "washed"
					washed_count += 1
				swarm_units[i] = unit
			lane["swarm_units"] = swarm_units
			if washed_count >= swarm_units.size() and not swarm_units.is_empty():
				lane["swarm_state"] = "washed"

		var curtain_nodes: Array = lane.get("curtain_nodes", [])
		var curtain_pos: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
		var attract_pos: Vector3 = lane.get("attract_pos", curtain_pos)
		var lure_active: bool = bool(lane.get("lure_active", false))
		for i in range(curtain_nodes.size()):
			var node = curtain_nodes[i]
			if not is_instance_valid(node):
				continue
			var base_target := curtain_pos + Vector3(0, 0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
			var active_target := attract_pos + Vector3(0.35 * CHANNELS_WINDOW_CURTAIN_OFFSETS[i], 0.0, 0.7 * CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
			var target: Vector3 = active_target if lure_active else base_target
			node.position = node.position.move_toward(target, delta * spd * 6.0)

		if _channels_active_window_lane != window_id:
			_channels_window_lanes[window_id] = lane
			continue
		if _current_step != _channels_window_step_name(window_id, "cross"):
			_channels_window_lanes[window_id] = lane
			continue

		var goal_pos: Vector3 = lane.get("goal_pos", Vector3.ZERO)
		var curtain_anchor: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
		if _player.global_position.distance_to(goal_pos) <= 2.6:
			_complete_channels_window_lane(window_id)
			return
		if float(lane.get("safe_until_tick", -1.0)) >= 0.0 and _scheduler.get_current_tick() >= float(lane.get("safe_until_tick", -1.0)):
			_fail_channels_window_lane(window_id, "window_closed")
			return
		if not bool(lane.get("lure_active", false)) and _player.global_position.distance_to(curtain_anchor) <= CHANNELS_WINDOW_DETECT_RADIUS:
			_fail_channels_window_lane(window_id, "blocked_lane")
			return
		_channels_window_lanes[window_id] = lane

func _reset_channels_encounter_nodes() -> void:
	_clear_markers()
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	_channels_party_hidden = false
	_channels_encounter_resetting = false
	if is_instance_valid(_channels_run_lure_interactable):
		_channels_run_lure_interactable.reset()
		_channels_run_lure_interactable.show_tutorial_label()
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["x"] = CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i]
		unit["target_x"] = unit["x"]
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

func _begin_channels_encounter() -> void:
	if not _enter_step("channels_encounter_activate"):
		return
	_select_character("endo")
	_reset_channels_encounter_nodes()
	_show_marker(CHANNELS_RUN_LURE_POS + Vector3(0, 2.0, 0), "LURE", Color(0.75, 0.45, 0.2, 0.8))
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "HIDE", Color(0.35, 0.75, 0.55, 0.8))
	_show_marker(CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0), "SHELTER", Color(0.8, 0.72, 0.45, 0.85))
	_tutorial_prompt.show_prompt("Move Endo to the lure and hold position")
	_player.set_move_enabled(true)

func _on_channels_run_lure_activated() -> void:
	if _channels_run_lure_active or _current_step not in ["channels_encounter_activate", "channels_encounter_hide"]:
		return
	_set_channels_run_lure_active(true)
	_channels_run_lure_expire_tick = _scheduler.get_current_tick() + CHANNELS_RUN_LURE_DURATION
	_enter_step("channels_encounter_hide")
	if _channels_run_lure_interactable:
		_channels_run_lure_interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt("Hide until the swarm commits")
	_scheduler.cancel_tag("channels_run_lure_expire")
	_scheduler.schedule_after(CHANNELS_RUN_LURE_DURATION, _on_channels_run_lure_expired, "channels_run_lure_expire")

func _on_channels_run_lure_expired() -> void:
	if _current_step not in ["channels_encounter_hide", "channels_encounter_run"]:
		return
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	if _channels_party_hidden:
		_enter_step("channels_encounter_run")
		_tutorial_prompt.show_prompt("Run for shelter")
	else:
		_fail_channels_encounter("lure_expired_exposed")

func _fail_channels_encounter(reason: String) -> void:
	if _channels_encounter_resetting or _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	_channels_encounter_resetting = true
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_tutorial_prompt.show_prompt("The swarm catches the movement. Try again.")
	_clear_markers()
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "CAUGHT", Color(0.85, 0.28, 0.22, 0.85))
	_scheduler.schedule_after(1.0, func():
		_restart_channels_encounter(reason)
	, "channels_encounter_retry")

func _restart_channels_encounter(_reason: String) -> void:
	if not _enter_step("channels_encounter_reset"):
		return
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_reset_move")

func _complete_channels_encounter() -> void:
	if _current_step == "channels_shelter":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_scheduler.cancel_tag("channels_run_lure_expire")
	_start_channels_shelter()

func _update_channels_encounter(delta: float, spd: float) -> void:
	if _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	var target_x := CHANNELS_SWARM_CLUSTER_X
	if _channels_run_lure_active:
		target_x = CHANNELS_RUN_LURE_POS.x
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["target_x"] = target_x + CHANNELS_SWARM_OFFSETS[i]
		var dx: float = unit["target_x"] - unit["x"]
		unit["x"] += signf(dx) * minf(absf(dx), CHANNELS_SWARM_SPEED * delta * spd)
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

	var hide_reached: bool = _player.global_position.distance_to(CHANNELS_HIDE_SPOT_POS) <= 2.3
	if hide_reached != _channels_party_hidden:
		_channels_party_hidden = hide_reached
		if _channels_party_hidden and _current_step == "channels_encounter_hide":
			_tutorial_prompt.show_prompt("Wait for the lure to burn out")

	if _current_step == "channels_encounter_run" and _player.global_position.distance_to(CHANNELS_SHELTER_POS) <= 3.0:
		_complete_channels_encounter()
		return

	if _channels_party_hidden:
		return

	var visible_x: float = _player.global_position.x
	for unit in _channels_swarm_units:
		if absf(unit["x"] - visible_x) <= CHANNELS_SWARM_DETECT_RADIUS:
			_fail_channels_encounter("detected")
			return

func _start_channels_enter() -> void:
	if not _enter_step("channels_enter"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_dialogue_chain([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	], func(): _scheduler.schedule_after(0.5, _start_channels_to_memory, "channels_to_memory"))

func _start_channels_to_memory() -> void:
	if not _enter_step("channels_to_memory"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_memory() -> void:
	if not _enter_step("channels_memory"):
		return
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_focus_peris_view()
	_move_party_and_continue({
		"peris": CHANNELS_BODY_POS + Vector3(-1.0, 0.0, 1.1),
		"aster": CHANNELS_BODY_POS + Vector3(-3.0, 0.0, 0.4),
		"endo": CHANNELS_BODY_POS + Vector3(-4.2, 0.0, -0.8),
	}, func():
		_dialogue_chain([
			"channels.narration.memory",
			"channels.peris.know_place",
			"channels.aster.not_here",
			"channels.peris.saw_it",
			"channels.narration.leads",
		], func(): _scheduler.schedule_after(0.5, _start_channels_corpse, "channels_corpse"))
	, "channels_memory_move")

func _start_channels_to_ferrolure() -> void:
	if not _enter_step("channels_to_ferrolure"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_window_intro(window_id: String) -> void:
	var intro_step := _channels_window_step_name(window_id, "intro")
	if not _enter_step(intro_step):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

	var dialogue_keys: Array = []
	match window_id:
		"window_one":
			dialogue_keys = [
				"channels.narration.window_one",
				"channels.endo.window_one",
			]
		"window_two":
			dialogue_keys = [
				"channels.narration.window_two",
				"channels.peris.window_two",
			]
		_:
			return

	_move_party_and_continue(_get_channels_window_party_positions(window_id), func():
		_dialogue_chain(dialogue_keys, func():
			_scheduler.schedule_after(0.35, func():
				_begin_channels_window_lane(window_id)
			, "channels_%s_begin" % window_id)
		)
	, "channels_%s_intro_move" % window_id)

func _start_channels_corpse() -> void:
	if not _enter_step("channels_corpse"):
		return
	_focus_aster_view()
	_dialogue_chain([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.aster.report",
		"channels.peris.smell",
		"channels.peris.clients",
		"channels.aster.lysate",
		"channels.peris.people",
		"channels.aster.hungry",
		"channels.aster.downgrade",
	], func():
		_scheduler.schedule_after(0.5, func():
			_start_channels_window_intro("window_one")
		, "channels_window_one_intro")
	)

func _start_channels_ferrolure() -> void:
	if not _enter_step("channels_ferrolure"):
		return
	_select_character("aster")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_set_channels_ferrolure_active(false)
	_move_party_and_continue({
		"peris": CHANNELS_FERROLURE_POS + Vector3(-0.8, 0.0, 0.6),
		"aster": CHANNELS_FERROLURE_POS + Vector3(-2.5, 0.0, -0.3),
		"endo": CHANNELS_FERROLURE_POS + Vector3(-3.6, 0.0, 1.2),
	}, func():
		_dialogue_chain([
			"channels.narration.flora",
			"channels.aster.lure",
			"channels.peris.signals",
			"channels.peris.pause",
		], func():
			_set_channels_ferrolure_active(true)
			_start_channels_ferrolure_flush()
			_dialogue_chain([
				"channels.peris.touch",
				"channels.peris.always",
			], func():
				_scheduler.schedule_after(2.0, func():
					_set_channels_ferrolure_active(false)
					_start_channels_window_intro("window_two")
				, "channels_window_two_intro")
			)
		)
	, "channels_ferrolure_move")

func _start_channels_to_encounter() -> void:
	if not _enter_step("channels_to_encounter"):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_encounter_intro() -> void:
	if not _enter_step("channels_encounter_intro"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_intro_move")

func _start_channels_shelter() -> void:
	if not _enter_step("channels_shelter"):
		return
	_channels_shelter_reached = true
	_recuperate_channels_party()
	_set_channels_shortcut_unlocked(true)
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	_game_state.command_stop("endo")
	_move_party_and_continue({
		"aster": CHANNELS_SHELTER_POS + Vector3(-1.8, 0.0, -1.2),
		"peris": CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		"endo": CHANNELS_SHELTER_POS + Vector3(-0.3, 0.0, -0.2),
	}, func():
		_dialogue_chain([
			"channels.narration.shelter",
			"channels.endo.door",
			"channels.narration.recuperate",
			"channels.narration.shortcut",
		], func(): _scheduler.schedule_after(0.5, _start_channels_explore, "channels_explore"))
	, "channels_shelter_move")

func _start_channels_explore() -> void:
	if not _enter_step("channels_explore"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Stacks ---

func _clear_channels_runtime_state() -> void:
	_channels_flow_strips.clear()
	_channels_flush_swarm_units.clear()
	_channels_window_lanes.clear()
	_channels_active_window_lane = ""
	_channels_flow_power = 0.0
	_channels_flush_state = ""
	_iron_patches.clear()

func _reset_stacks_runtime_state() -> void:
	_stacks_support_log_entry_id = -1
	_stacks_support_log_presented = false
	_stacks_signal_interacted = false
	_stacks_terminal_interacted = false
	_stacks_archive_interacted = false
	_stacks_audit_flags_found = false
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.reset()
		_stacks_signal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.reset()
		_stacks_terminal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.reset()
		_stacks_workspace_interactable.hide_tutorial_label()

func _ensure_stacks_support_log_entry() -> Dictionary:
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal == null:
		return {}
	var context := {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "maintenance_shift",
		"timestamp_label": "147 cycles ago",
		"location": "Processing Stacks",
		"sub_location": "Support Team Thread",
		"trigger_type": "story",
		"trigger_context": "support_team_log",
		"position": Vector3(STACKS_START.x + 88.0, 0.5, 0.0),
		"caption": "Maintenance thread surfaced from the old support logs",
	}
	var title := DialogueData.text("stacks.engram.support_log.title")
	var body := DialogueData.text("stacks.engram.support_log.body")
	return journal.ensure_story_log_entry(
		STACKS_SUPPORT_LOG_KEY,
		title,
		body,
		context,
		{
			"caption": "Support team maintenance log",
			"trigger_context": "support_team_log",
			"attached_data": {
				"channel": "#ependyma-core",
			},
		}
	)

func trigger_stacks_support_log() -> void:
	_present_stacks_support_log()

func close_stacks_engram_overlay() -> void:
	if _engram_overlay != null and _engram_overlay.visible:
		_engram_overlay.close_overlay()

func _present_stacks_support_log() -> void:
	var entry := _ensure_stacks_support_log_entry()
	_stacks_support_log_presented = not entry.is_empty()
	_stacks_support_log_entry_id = int(entry.get("id", -1))
	if _engram_overlay == null:
		_scheduler.schedule_after(0.1, _start_stacks_terminal, "terminal")
		return
	if not _engram_overlay.overlay_closed.is_connected(_on_stacks_support_log_closed):
		_engram_overlay.overlay_closed.connect(_on_stacks_support_log_closed, CONNECT_ONE_SHOT)
	_engram_overlay.open_overlay_for_entry(_stacks_support_log_entry_id)
	show_capture_message("Engram surfaced a maintenance log. J or Esc closes it.")

func _on_stacks_support_log_closed() -> void:
	if _current_step == "stacks_enter":
		_scheduler.schedule_after(0.1, _start_stacks_terminal, "terminal")

func _start_stacks_enter() -> void:
	_enter_step("stacks_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("stacks")
	_unload_chunk("channels")
	_activate_chunk_grid("stacks")  # swap the live grid to the stacks footprint
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	_select_character("aster")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.enter",
		"stacks.aster.cores",
		"stacks.peris.noisy",
		"stacks.narration.network_address",
		"stacks.aster.know_number",
	], func(): _present_stacks_support_log())

func _start_stacks_terminal() -> void:
	if not _enter_step("stacks_terminal"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the terminal")
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.reset()
		_stacks_terminal_interactable.show_tutorial_label()

func _start_stacks_signal() -> void:
	if not _enter_step("stacks_signal"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the custom sensor wall")
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.reset()
		_stacks_signal_interactable.show_tutorial_label()

func trigger_stacks_terminal(play_dialogue := false) -> void:
	if _current_step != "stacks_terminal" or _stacks_terminal_interacted:
		return
	_stacks_terminal_interacted = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_stacks_signal()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.aster.support_team",
		"stacks.aster.drink_machine",
		"stacks.peris.priorities",
		"stacks.narration.cleaned_terminal",
		"stacks.aster.cleaner_than_place",
		"stacks.aster.simplodrink",
		"stacks.peris.miss_machine",
		"stacks.aster.expectation",
	], func(): _scheduler.schedule_after(0.2, _start_stacks_signal, "signal"))

func trigger_stacks_signal(play_dialogue := false) -> void:
	if _current_step != "stacks_signal" or _stacks_signal_interacted:
		return
	_stacks_signal_interacted = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_stacks_archive()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.instrumented_lane",
		"stacks.aster.nonstandard",
		"stacks.aster.metrics",
		"stacks.peris.damn_cooler",
		"stacks.aster.cooling_part",
		"stacks.peris.meaning",
		"stacks.aster.standardization",
	], func(): _scheduler.schedule_after(0.2, _start_stacks_archive, "archive"))

func _start_stacks_archive() -> void:
	if not _enter_step("stacks_archive"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the tuned workspace")
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.reset()
		_stacks_workspace_interactable.show_tutorial_label()

func trigger_stacks_archive(play_dialogue := false) -> void:
	if _current_step != "stacks_archive" or _stacks_archive_interacted:
		return
	_stacks_archive_interacted = true
	_stacks_audit_flags_found = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_stacks_explore()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.workspace",
		"stacks.aster.pull_archive",
		"stacks.aster.ghost_ids",
		"stacks.peris.fake_permissions",
		"stacks.aster.security_patch",
		"stacks.aster.not_the_type",
		"stacks.aster.right",
	], func(): _scheduler.schedule_after(0.2, _start_stacks_explore, "explore"))

func _start_stacks_explore() -> void:
	_enter_step("stacks_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Rings ---

func _start_rings_enter() -> void:
	_enter_step("rings_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("rings")
	_unload_chunk("stacks")
	_activate_chunk_grid("rings")  # swap the live grid to the rings footprint
	_dialogue_chain([
		"ring.entry.narration",
		"ring.entry.aster.home",
		"ring.entry.aster.machine",
		"ring.entry.peris.quiet",
		"ring.entry.endo.wall_touch",
		"ring.scatter.peris.notice",
		"ring.scatter.aster.continue",
	], func(): _scheduler.schedule_after(3.0, _start_rings_client, "client"))

func _start_rings_client() -> void:
	_enter_step("rings_client")
	_dialogue_chain([
		"ring.marco.entry.narration",
		"ring.marco.entry.marco.warn",
		"ring.marco.entry.peris.name",
		"ring.marco.entry.marco.correct",
		"ring.marco.warn.jeopardize",
		"ring.marco.warn.c_suite",
		"ring.marco.peris.wellness_start",
		"ring.marco.peris.silence",
		"ring.marco.peris.apology",
		"ring.marco.exit.marco.brief",
		"ring.marco.exit.narration",
		"ring.after_marco.aster.weird",
		"ring.after_marco.peris.quiet",
		"ring.after_marco.aster.move_on",
		"ring.after_marco.endo.watch",
	], func(): _scheduler.schedule_after(3.0, _start_endo_departs, "endo_departs"))

func _start_endo_departs() -> void:
	_enter_step("endo_departs")
	_dialogue_chain([
		"ring.departure.narration",
		"ring.departure.aster.question",
		"ring.departure.peris.read",
		"ring.departure.endo.turn",
		"ring.departure.aster.delayed",
		"ring.departure.peris.explain",
		"ring.departure.aster.but",
		"ring.departure.peris.look",
		"ring.departure.aster.settle",
		"ring.departure.narration.closing",
	], func():
		# Endo walks back and fades out
		_endo.visible = false
		if _game_state.characters.has("endo"):
			_game_state.command_stop("endo")
		_scheduler.schedule_after(2.0, _start_rings_explore, "explore")
	)

func _start_rings_explore() -> void:
	_enter_step("rings_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Lockout ---

func _start_lockout_approach() -> void:
	_enter_step("lockout_approach")
	_tutorial_prompt.hide_prompt()
	_load_chunk("lockout")
	_unload_chunk("rings")
	_activate_chunk_grid("lockout")  # swap the live grid to the lockout footprint
	_dialogue_chain([
		"lockout.approach.narration",
		"lockout.approach.aster.confident",
	], func(): _scheduler.schedule_after(1.0, _start_lockout_rejected, "rejected"))

func _start_lockout_rejected() -> void:
	_enter_step("lockout_rejected")
	_dialogue_chain([
		"lockout.approach.panel_reject",
		"lockout.approach.aster.glitch",
		"lockout.approach.aster.retry",
		"lockout.approach.aster.confused",
		"lockout.escalate.aster.hack",
		"lockout.escalate.hack_block",
		"lockout.escalate.aster.recog",
		"lockout.escalate.aster.try_again",
		"lockout.escalate.peris.quiet",
		"lockout.escalate.peris_approaches",
		"lockout.escalate.aster.notices",
		"lockout.escalate.peris.dont",
	], func(): _scheduler.schedule_after(1.0, _start_lockout_chase, "chase"))

func _start_lockout_chase() -> void:
	_enter_step("lockout_chase")
	_dialogue_chain([
		"lockout.dispatch.narration",
		"lockout.dispatch.aster.frozen",
		"lockout.dispatch.peris.hears",
		"lockout.dispatch.aster.pulled",
		"lockout.dispatch.peris.no",
		"lockout.dispatch.narration.start_chase",
		"lockout.chase.aster.lost",
		"lockout.chase.peris.listen",
	], func():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Run!")
	)
	_spawn_lockout_naturalizers()

func _start_lockout_exile() -> void:
	_enter_step("lockout_exile")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	# Stop Naturalizers
	for i in range(_naturalizers.size()):
		if _game_state.characters.has("nk_%d" % i):
			_game_state.command_stop("nk_%d" % i)
	_dialogue_chain([
		"lockout.chase.narration.boundary",
		"lockout.standoff.narration",
		"lockout.standoff.aster.try",
		"lockout.standoff.peris.back",
		"lockout.standoff.aster.cant_answer",
		"lockout.standoff.narration.silence",
		"lockout.aftermath.aster.watch",
		"lockout.aftermath.peris.answer",
		"lockout.aftermath.aster.sit",
		"lockout.aftermath.peris.sit",
		"lockout.aftermath.peris.ask_word",
		"lockout.aftermath.aster.fugacity",
		"lockout.aftermath.aster.clarify",
		"lockout.aftermath.peris.pressure",
		"lockout.aftermath.aster.laugh",
		"lockout.aftermath.peris.soft",
		"lockout.aftermath.narration.close",
	], func(): _scheduler.schedule_after(2.0, _complete, "complete"))

func _spawn_lockout_naturalizers() -> void:
	_clear_lockout_runtime_state()
	var chars := find_child("Characters", false, false)
	if chars == null:
		return
	for i in range(3):
		var nk := _create_npc("NK-%d" % (i + 1), Color(0.7, 0.7, 0.75))
		nk.position = LOCKOUT_BOUNDARY + Vector3(-2 + i * 2, 0.5, 0)
		chars.add_child(nk)
		_register_gs_character("nk_%d" % i, nk, 1.5)
		_game_state.command_move_to_pos("nk_%d" % i, _aster_node.global_position)
		_naturalizers.append(nk)

func _clear_lockout_runtime_state() -> void:
	for i in range(_naturalizers.size()):
		var nk := _naturalizers[i]
		if is_instance_valid(nk):
			nk.queue_free()
		if _game_state != null:
			var nk_id := "nk_%d" % i
			if _game_state.characters.has(nk_id):
				_game_state.unregister_character(nk_id)
	_naturalizers.clear()

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	# Cosmetic fade; the scene hand-off rides the scheduler so fast-forward (and the
	# headless playthrough, which never advances tweens) reaches it at the same tick.
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.02, 0.02, 0.03, 1.0), 2.0)
	_scheduler.schedule_after(2.0, func():
		_change_scene_or_record("res://scenes/tutorial/leaving_facility.tscn")
	, "complete_handoff")

# --- Chunk builders ---

func _build_channels_window_lane(
	parent: Node3D,
	window_id: String,
	stage_pos: Vector3,
	lure_pos: Vector3,
	curtain_pos: Vector3,
	goal_pos: Vector3,
	safe_duration: float
) -> void:
	var lane_root := Node3D.new()
	lane_root.name = "ChannelsWindowLane_%s" % window_id
	parent.add_child(lane_root)

	var side_sign := signf(lure_pos.z - stage_pos.z)
	var branch_dir := _channels_window_branch_direction(stage_pos, lure_pos)
	var cross_dir := _channels_window_cross_direction(branch_dir)
	var lane_floor_center := Vector3((stage_pos.x + goal_pos.x) * 0.5, -0.04, stage_pos.z)
	var lane_floor_size := Vector3(absf(goal_pos.x - stage_pos.x) + 8.0, 0.08, 7.0)
	_add_corridor_section(parent, lane_floor_center, lane_floor_size, Color(0.07, 0.085, 0.1))

	var lure_branch_center := Vector3((stage_pos.x + lure_pos.x) * 0.5, -0.04, (stage_pos.z + lure_pos.z) * 0.5)
	var lure_branch_size := Vector3(absf(lure_pos.x - stage_pos.x) + 5.0, 0.08, absf(lure_pos.z - stage_pos.z) + 4.0)
	_add_corridor_section(parent, lure_branch_center, lure_branch_size, Color(0.06, 0.075, 0.09))

	var stage_ring := MeshInstance3D.new()
	stage_ring.name = "ChannelsWindowStage_%s" % window_id
	var stage_ring_mesh := CylinderMesh.new()
	stage_ring_mesh.top_radius = 1.35
	stage_ring_mesh.bottom_radius = 1.35
	stage_ring_mesh.height = 0.04
	stage_ring.mesh = stage_ring_mesh
	var stage_ring_mat := StandardMaterial3D.new()
	stage_ring_mat.albedo_color = Color(0.18, 0.24, 0.3)
	stage_ring_mat.emission_enabled = true
	stage_ring_mat.emission = Color(0.18, 0.32, 0.46)
	stage_ring_mat.emission_energy_multiplier = 0.45
	stage_ring.material_override = stage_ring_mat
	stage_ring.position = stage_pos + Vector3(0.0, 0.03, 0.0)
	lane_root.add_child(stage_ring)

	var goal_beacon := MeshInstance3D.new()
	goal_beacon.name = "ChannelsWindowGoal_%s" % window_id
	var goal_beacon_mesh := CylinderMesh.new()
	goal_beacon_mesh.top_radius = 0.65
	goal_beacon_mesh.bottom_radius = 0.65
	goal_beacon_mesh.height = 0.12
	goal_beacon.mesh = goal_beacon_mesh
	var goal_beacon_mat := StandardMaterial3D.new()
	goal_beacon_mat.albedo_color = Color(0.3, 0.48, 0.56)
	goal_beacon_mat.emission_enabled = true
	goal_beacon_mat.emission = Color(0.32, 0.64, 0.76)
	goal_beacon_mat.emission_energy_multiplier = 0.5
	goal_beacon.material_override = goal_beacon_mat
	goal_beacon.position = goal_pos + Vector3(0.0, 0.06, 0.0)
	lane_root.add_child(goal_beacon)

	var goal_light := OmniLight3D.new()
	goal_light.position = goal_pos + Vector3(0.0, 1.6, 0.0)
	goal_light.light_color = Color(0.36, 0.78, 0.92)
	goal_light.light_energy = 1.4
	goal_light.omni_range = 8.0
	lane_root.add_child(goal_light)

	var lure_root := Node3D.new()
	lure_root.name = "ChannelsWindowLure_%s" % window_id
	lure_root.position = lure_pos
	lane_root.add_child(lure_root)

	var lure_stem := MeshInstance3D.new()
	var lure_stem_mesh := CylinderMesh.new()
	lure_stem_mesh.top_radius = 0.08
	lure_stem_mesh.bottom_radius = 0.12
	lure_stem_mesh.height = 0.95
	lure_stem.mesh = lure_stem_mesh
	var lure_stem_mat := StandardMaterial3D.new()
	lure_stem_mat.albedo_color = Color(0.24, 0.28, 0.18)
	lure_stem.material_override = lure_stem_mat
	lure_stem.position = Vector3(0.0, 0.48, 0.0)
	lure_root.add_child(lure_stem)

	var lure_mesh := MeshInstance3D.new()
	var lure_bulb_mesh := SphereMesh.new()
	lure_bulb_mesh.radius = 0.34
	lure_bulb_mesh.height = 0.68
	lure_mesh.mesh = lure_bulb_mesh
	var lure_mat := StandardMaterial3D.new()
	lure_mat.albedo_color = Color(0.56, 0.34, 0.16)
	lure_mat.emission_enabled = true
	lure_mat.emission = Color(0.82, 0.46, 0.18)
	lure_mat.emission_energy_multiplier = 0.35
	lure_mesh.material_override = lure_mat
	lure_mesh.position = Vector3(0.0, 1.0, 0.0)
	lure_root.add_child(lure_mesh)

	var lure_light := OmniLight3D.new()
	lure_light.position = Vector3(0.0, 1.1, 0.0)
	lure_light.light_color = Color(0.92, 0.5, 0.2)
	lure_light.light_energy = 0.45
	lure_light.omni_range = 7.5
	lure_root.add_child(lure_light)

	var lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	lure_interactable.name = "ChannelsWindowInteract_%s" % window_id
	lure_interactable.description = "Ferrolure"
	lure_interactable.required_character = "aster"
	lure_interactable.one_shot = false
	lure_interactable.dwell_time = 1.6
	lure_interactable.tutorial_label = "HOLD"
	lure_interactable.position = lure_pos
	lure_interactable.interacted.connect(_on_channels_window_lure_activated.bind(window_id))
	parent.add_child(lure_interactable)

	var curtain_nodes: Array = []
	for i in range(CHANNELS_WINDOW_CURTAIN_OFFSETS.size()):
		var curtain := MeshInstance3D.new()
		curtain.name = "ChannelsWindowCurtain_%s_%d" % [window_id, i]
		var curtain_mesh := SphereMesh.new()
		curtain_mesh.radius = 0.36
		curtain_mesh.height = 0.72
		curtain.mesh = curtain_mesh
		var curtain_mat := StandardMaterial3D.new()
		curtain_mat.albedo_color = Color(0.2, 0.14, 0.08)
		curtain_mat.emission_enabled = true
		curtain_mat.emission = Color(0.7, 0.24, 0.08)
		curtain_mat.emission_energy_multiplier = 0.55
		curtain.material_override = curtain_mat
		curtain.position = curtain_pos + Vector3(0.0, 0.0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
		parent.add_child(curtain)
		curtain_nodes.append(curtain)

	var corpse_nodes: Array = []
	var corpse_center := stage_pos - branch_dir * 5.8 - cross_dir * 1.6
	var corpse_offsets := [
		Vector3.ZERO,
		cross_dir * 1.55 - branch_dir * 0.85,
		cross_dir * -1.35 + branch_dir * 0.75,
	]
	for i in range(corpse_offsets.size()):
		var corpse := MeshInstance3D.new()
		corpse.name = "ChannelsWindowCorpse_%s_%d" % [window_id, i]
		var corpse_mesh := CapsuleMesh.new()
		corpse_mesh.radius = 0.22 + 0.03 * float(i)
		corpse_mesh.height = 1.0 + 0.1 * float(i)
		corpse.mesh = corpse_mesh
		var corpse_mat := StandardMaterial3D.new()
		corpse_mat.albedo_color = Color(0.18, 0.16, 0.15).lerp(Color(0.24, 0.18, 0.16), float(i) * 0.2)
		corpse_mat.roughness = 0.95
		corpse.material_override = corpse_mat
		corpse.position = corpse_center + corpse_offsets[i] + Vector3(0.0, 0.28, 0.0)
		corpse.rotation_degrees = Vector3(88.0, 24.0 * float(i), 80.0 - 8.0 * float(i))
		lane_root.add_child(corpse)
		corpse_nodes.append(corpse)

	var bridge_points: Array = []
	var channel_specs: Array = []
	var channel_lateral_offsets := [-1.25, 1.3, -0.95]
	var swarm_start_pos := corpse_center + branch_dir * 0.95 + cross_dir * 0.15
	bridge_points.append(swarm_start_pos)
	bridge_points.append(stage_pos - branch_dir * 1.4 - cross_dir * 1.1)
	for i in range(CHANNELS_WINDOW_PERIODIC_CHANNELS):
		var t := float(CHANNELS_WINDOW_CHANNEL_T_VALUES[i])
		var lateral := float(channel_lateral_offsets[i % channel_lateral_offsets.size()])
		var approach := stage_pos.lerp(lure_pos, maxf(0.08, t - 0.055)) + cross_dir * (lateral * 0.72)
		var channel_pos := stage_pos.lerp(lure_pos, t) + cross_dir * lateral
		var exit := stage_pos.lerp(lure_pos, minf(0.9, t + 0.055)) + cross_dir * (-lateral * 0.42)
		if bridge_points[bridge_points.size() - 1].distance_to(approach) > 0.3:
			bridge_points.append(approach)
		bridge_points.append(channel_pos)
		channel_specs.append({
			"position": channel_pos,
			"path_index": bridge_points.size() - 1,
		})
		bridge_points.append(exit)
	bridge_points.append(lure_pos + branch_dir * 0.35 + cross_dir * 0.45)

	var bridge_segments: Array = []
	for i in range(bridge_points.size() - 1):
		bridge_segments.append(_add_channels_window_bridge_segment(
			lane_root,
			"ChannelsWindowBridge_%s_%d" % [window_id, i],
			bridge_points[i],
			bridge_points[i + 1]
		))

	var path_distances: Array = []
	var path_distance := 0.0
	for i in range(bridge_points.size()):
		if i == 0:
			path_distances.append(0.0)
			continue
		path_distance += bridge_points[i - 1].distance_to(bridge_points[i])
		path_distances.append(path_distance)

	var periodic_channels: Array = []
	var channel_contact_map := {}
	var flow_period := CHANNELS_WINDOW_FLOW_PERIOD
	var desired_spacing := flow_period / float(CHANNELS_WINDOW_PERIODIC_CHANNELS)
	for i in range(channel_specs.size()):
		var spec: Dictionary = channel_specs[i]
		var channel_root := Node3D.new()
		channel_root.name = "ChannelsWindowChannel_%s_%d" % [window_id, i]
		channel_root.position = spec.get("position", Vector3.ZERO)
		channel_root.look_at_from_position(channel_root.position, channel_root.position + cross_dir, Vector3.UP, true)
		lane_root.add_child(channel_root)

		var trench := MeshInstance3D.new()
		var trench_mesh := BoxMesh.new()
		trench_mesh.size = Vector3(2.6, 0.32, 5.8)
		trench.mesh = trench_mesh
		var trench_mat := StandardMaterial3D.new()
		trench_mat.albedo_color = Color(0.07, 0.1, 0.12)
		trench_mat.roughness = 0.92
		trench.material_override = trench_mat
		trench.position = Vector3(0.0, 0.12, 0.0)
		channel_root.add_child(trench)

		var water := MeshInstance3D.new()
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(1.65, 1.0, 5.1)
		water.mesh = water_mesh
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.08, 0.16, 0.24)
		water_mat.emission_enabled = true
		water_mat.emission = Color(0.14, 0.42, 0.65)
		water_mat.emission_energy_multiplier = 0.3
		water.material_override = water_mat
		water.position = Vector3(0.0, -0.22, 0.0)
		water.scale = Vector3.ONE
		channel_root.add_child(water)

		var foam := MeshInstance3D.new()
		var foam_mesh := BoxMesh.new()
		foam_mesh.size = Vector3(1.7, 0.08, 5.2)
		foam.mesh = foam_mesh
		var foam_mat := StandardMaterial3D.new()
		foam_mat.albedo_color = Color(0.54, 0.7, 0.78, 0.8)
		foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam_mat.emission_enabled = true
		foam_mat.emission = Color(0.42, 0.78, 0.9)
		foam_mat.emission_energy_multiplier = 0.18
		foam.material_override = foam_mat
		foam.position = Vector3(0.0, 0.1, 0.0)
		channel_root.add_child(foam)

		var channel_light := OmniLight3D.new()
		channel_light.position = Vector3(0.0, 1.0, 0.0)
		channel_light.light_color = Color(0.24, 0.58, 0.8)
		channel_light.light_energy = 0.35
		channel_light.omni_range = 5.0
		channel_root.add_child(channel_light)

		var contact_path_index := int(spec.get("path_index", 0))
		var contact_time := float(path_distances[contact_path_index]) / CHANNELS_WINDOW_SWARM_SPEED
		var desired_start := fposmod(float(i) * desired_spacing, flow_period)
		var phase_offset := fposmod(-contact_time - desired_start, flow_period)
		periodic_channels.append({
			"index": i,
			"position": spec.get("position", Vector3.ZERO),
			"path_index": contact_path_index,
			"contact_time": contact_time,
			"phase_offset": phase_offset,
			"root": channel_root,
			"water": water,
			"foam": foam,
			"light": channel_light,
			"level": 0.0,
			"flooded": false,
			"local_phase": 0.0,
		})
		channel_contact_map[contact_path_index] = i

	var swarm_units: Array = []
	for i in range(CHANNELS_WINDOW_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "ChannelsWindowSwarm_%s_%d" % [window_id, i]
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.28
		swarm_mesh.height = 0.56
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.32, 0.19, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.86, 0.3, 0.08)
		swarm_mat.emission_energy_multiplier = 0.4
		swarm.material_override = swarm_mat
		var base_pos: Vector3 = (
			swarm_start_pos
			+ cross_dir * (CHANNELS_WINDOW_SWARM_OFFSETS[i] * 0.65)
			+ branch_dir * (0.22 * float(i % 2) - 0.28)
		)
		swarm.position = base_pos
		lane_root.add_child(swarm)
		swarm_units.append({
			"node": swarm,
			"base_pos": base_pos,
			"delay": float(i) * CHANNELS_WINDOW_SWARM_DELAY,
			"path_index": 1,
			"state": "idle",
			"wash_vector": Vector3.ZERO,
		})

	var attract_pos := curtain_pos + Vector3(0.0, 0.0, side_sign * 9.0)
	var lane := {
		"stage_pos": stage_pos,
		"lure_pos": lure_pos,
		"goal_pos": goal_pos,
		"curtain_pos": curtain_pos,
		"attract_pos": attract_pos,
		"safe_duration": safe_duration,
		"curtain_nodes": curtain_nodes,
		"lure_mesh": lure_mesh,
		"lure_light": lure_light,
		"interactable": lure_interactable,
		"phase": "idle",
		"safe_until_tick": -1.0,
		"last_outcome": "",
		"lure_active": false,
		"branch_dir": branch_dir,
		"cross_dir": cross_dir,
		"swarm_start_pos": swarm_start_pos,
		"swarm_path": bridge_points,
		"channel_contact_map": channel_contact_map,
		"flow_period": flow_period,
		"flood_duration": CHANNELS_WINDOW_FLOOD_DURATION,
		"flow_offset": 0.0,
		"periodic_channels": periodic_channels,
		"bridge_segments": bridge_segments,
		"corpse_nodes": corpse_nodes,
		"swarm_units": swarm_units,
		"swarm_state": "idle",
		"swarm_start_tick": -1.0,
		"washed_channel_index": -1,
		"wash_analysis": {},
	}
	lane["wash_analysis"] = _channels_window_wash_analysis(lane)
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _build_channels_chunk(parent: Node3D) -> void:
	var sx := CHANNELS_START.x
	var length := CHANNELS_END.x - CHANNELS_START.x
	var width := 50.0
	var floor_color := Color(0.06, 0.08, 0.1)
	var wall_color := Color(0.08, 0.08, 0.1)
	_channels_flow_strips.clear()
	_channels_flush_swarm_units.clear()
	_channels_window_lanes.clear()
	_channels_active_window_lane = ""
	_channels_shortcut_unlocked = false
	_channels_party_recuperated = false
	_channels_shelter_reached = false
	_channels_flush_state = ""
	_channels_flush_timer = 0.0
	_channels_flow_power = 0.0

	# Main corridor ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Outer walls
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, -width / 2.0), Vector3(length, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, width / 2.0), Vector3(length, 3, 0.3), wall_color)

	# Flowing water channels along the main path (blue-tinted strips)
	for i in range(6):
		var water := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(length * 0.8, 0.02, 2.0)
		water.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.15, 0.2)
		wm.emission_enabled = true
		wm.emission = Color(0.05, 0.08, 0.12)
		wm.emission_energy_multiplier = 0.3
		water.material_override = wm
		water.position = Vector3(sx + length / 2.0, 0.01, -15.0 + i * 6.0)
		parent.add_child(water)
		_channels_flow_strips.append(water)

	# Side branches (3 alcoves off the main path for exploration)
	for i in range(3):
		var branch_x: float = sx + 50.0 + i * 60.0
		var branch_z: float = -width / 2.0 + 5.0 if i % 2 == 0 else width / 2.0 - 5.0
		var branch_sign: float = 1.0 if branch_z > 0 else -1.0
		# Alcove floor
		_add_corridor_section(parent, Vector3(branch_x, -0.04, branch_z + branch_sign * 10.0), Vector3(15, 0.08, 12), Color(0.05, 0.06, 0.08))
		# Alcove walls
		_add_wall(parent, Vector3(branch_x - 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)
		_add_wall(parent, Vector3(branch_x + 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)

	# Stagnant pools with iron deposits (multiple, spread out)
	for i in range(4):
		var sp_x: float = sx + 40.0 + i * 50.0
		var sp_z: float = 8.0 + randf_range(-3, 3) if i % 2 == 0 else -8.0 + randf_range(-3, 3)  # @rendering_only — sandbox debris scatter
		var sp_pos := Vector3(sp_x, 0.02, sp_z)
		var sp_size := Vector3(8, 0.04, 6)
		var stagnant := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = sp_size
		stagnant.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.12, 0.06)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.06, 0.02)
		sm.emission_energy_multiplier = 0.2
		stagnant.material_override = sm
		stagnant.position = sp_pos
		parent.add_child(stagnant)
		_iron_patches.append({"pos": sp_pos, "size": sp_size})

	# Body in the drainage path grounds both the memory beat and the harvest beat.
	var body := MeshInstance3D.new()
	body.name = "ChannelsBody"
	var corpse_mesh := CapsuleMesh.new()
	corpse_mesh.radius = 0.28
	corpse_mesh.height = 1.3
	body.mesh = corpse_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.18, 0.16)
	body_mat.roughness = 0.9
	body.material_override = body_mat
	body.position = CHANNELS_BODY_POS
	body.rotation_degrees = Vector3(0, 0, 88)
	parent.add_child(body)

	for i in range(2):
		var memory_body := MeshInstance3D.new()
		var memory_mesh := CapsuleMesh.new()
		memory_mesh.radius = 0.22
		memory_mesh.height = 1.1
		memory_body.mesh = memory_mesh
		var memory_mat := StandardMaterial3D.new()
		memory_mat.albedo_color = Color(0.16, 0.18, 0.22)
		memory_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		memory_mat.albedo_color.a = 0.45
		memory_body.material_override = memory_mat
		memory_body.position = Vector3(sx + 48.0 + i * 14.0, 0.38, -10.0 + i * 6.0)
		memory_body.rotation_degrees = Vector3(0, 0, 90)
		parent.add_child(memory_body)

	# Second ferrolure: dormant until Peris tends it in the coda beat.
	var ferrolure_root := Node3D.new()
	ferrolure_root.name = "SecondFerrolure"
	ferrolure_root.position = CHANNELS_FERROLURE_POS
	parent.add_child(ferrolure_root)

	var ferrolure_stem := MeshInstance3D.new()
	var ferrolure_stem_mesh := CylinderMesh.new()
	ferrolure_stem_mesh.top_radius = 0.08
	ferrolure_stem_mesh.bottom_radius = 0.12
	ferrolure_stem_mesh.height = 1.0
	ferrolure_stem.mesh = ferrolure_stem_mesh
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.18, 0.24, 0.18)
	ferrolure_stem.material_override = stem_mat
	ferrolure_stem.position = Vector3(0, 0.5, 0)
	ferrolure_root.add_child(ferrolure_stem)

	_channels_ferrolure = MeshInstance3D.new()
	var ferrolure_bulb_mesh := SphereMesh.new()
	ferrolure_bulb_mesh.radius = 0.35
	ferrolure_bulb_mesh.height = 0.7
	_channels_ferrolure.mesh = ferrolure_bulb_mesh
	var ferrolure_mat := StandardMaterial3D.new()
	ferrolure_mat.albedo_color = Color(0.22, 0.35, 0.25)
	ferrolure_mat.emission_enabled = true
	ferrolure_mat.emission = Color(0.2, 0.55, 0.32)
	ferrolure_mat.emission_energy_multiplier = 0.25
	_channels_ferrolure.material_override = ferrolure_mat
	_channels_ferrolure.position = Vector3(0, 1.05, 0)
	ferrolure_root.add_child(_channels_ferrolure)

	_channels_ferrolure_light = OmniLight3D.new()
	_channels_ferrolure_light.position = Vector3(0, 1.0, 0)
	_channels_ferrolure_light.light_color = Color(0.32, 0.7, 0.45)
	_channels_ferrolure_light.light_energy = 0.45
	_channels_ferrolure_light.omni_range = 8.0
	ferrolure_root.add_child(_channels_ferrolure_light)
	_set_channels_ferrolure_active(false)
	_set_channels_flow_power(0.25)

	for i in range(CHANNELS_FLUSH_SWARM_OFFSETS.size()):
		var flush_swarm := MeshInstance3D.new()
		flush_swarm.name = "ChannelsFlushSwarm_%d" % i
		var flush_mesh := SphereMesh.new()
		flush_mesh.radius = 0.22
		flush_mesh.height = 0.45
		flush_swarm.mesh = flush_mesh
		var flush_mat := StandardMaterial3D.new()
		flush_mat.albedo_color = Color(0.22, 0.18, 0.12)
		flush_mat.emission_enabled = true
		flush_mat.emission = Color(0.72, 0.32, 0.1)
		flush_mat.emission_energy_multiplier = 0.55
		flush_swarm.material_override = flush_mat
		flush_swarm.position = CHANNELS_FLUSH_SWARM_POS + Vector3(CHANNELS_FLUSH_SWARM_OFFSETS[i], 0.0, sin(float(i) * 1.4) * 0.8)
		parent.add_child(flush_swarm)
		_channels_flush_swarm_units.append({
			"node": flush_swarm,
			"base_pos": flush_swarm.position,
			"active": true,
			"state": "",
		})

	_build_channels_window_lane(
		parent,
		"window_one",
		CHANNELS_WINDOW_ONE_STAGE_POS,
		CHANNELS_WINDOW_ONE_LURE_POS,
		CHANNELS_WINDOW_ONE_CURTAIN_POS,
		CHANNELS_WINDOW_ONE_GOAL_POS,
		CHANNELS_WINDOW_ONE_DURATION
	)
	_build_channels_window_lane(
		parent,
		"window_two",
		CHANNELS_WINDOW_TWO_STAGE_POS,
		CHANNELS_WINDOW_TWO_LURE_POS,
		CHANNELS_WINDOW_TWO_CURTAIN_POS,
		CHANNELS_WINDOW_TWO_GOAL_POS,
		CHANNELS_WINDOW_TWO_DURATION
	)

	# Encounter lure: Endo uses this to pull the swarm away from the shelter route.
	var run_lure_root := Node3D.new()
	run_lure_root.name = "EncounterFerrolure"
	run_lure_root.position = CHANNELS_RUN_LURE_POS
	parent.add_child(run_lure_root)

	var run_lure_stem := MeshInstance3D.new()
	var run_lure_stem_mesh := CylinderMesh.new()
	run_lure_stem_mesh.top_radius = 0.09
	run_lure_stem_mesh.bottom_radius = 0.13
	run_lure_stem_mesh.height = 1.1
	run_lure_stem.mesh = run_lure_stem_mesh
	var run_lure_stem_mat := StandardMaterial3D.new()
	run_lure_stem_mat.albedo_color = Color(0.25, 0.28, 0.18)
	run_lure_stem.material_override = run_lure_stem_mat
	run_lure_stem.position = Vector3(0, 0.55, 0)
	run_lure_root.add_child(run_lure_stem)

	_channels_run_lure_mesh = MeshInstance3D.new()
	var run_lure_bulb := SphereMesh.new()
	run_lure_bulb.radius = 0.4
	run_lure_bulb.height = 0.8
	_channels_run_lure_mesh.mesh = run_lure_bulb
	var run_lure_mat := StandardMaterial3D.new()
	run_lure_mat.albedo_color = Color(0.55, 0.34, 0.12)
	run_lure_mat.emission_enabled = true
	run_lure_mat.emission = Color(0.8, 0.4, 0.15)
	run_lure_mat.emission_energy_multiplier = 0.35
	run_lure_mat.metallic = 0.15
	_channels_run_lure_mesh.material_override = run_lure_mat
	_channels_run_lure_mesh.position = Vector3(0, 1.1, 0)
	run_lure_root.add_child(_channels_run_lure_mesh)

	_channels_run_lure_light = OmniLight3D.new()
	_channels_run_lure_light.position = Vector3(0, 1.2, 0)
	_channels_run_lure_light.light_color = Color(0.9, 0.45, 0.18)
	_channels_run_lure_light.light_energy = 0.5
	_channels_run_lure_light.omni_range = 8.0
	run_lure_root.add_child(_channels_run_lure_light)
	_set_channels_run_lure_active(false)

	_channels_run_lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_channels_run_lure_interactable.name = "EncounterFerrolureInteract"
	_channels_run_lure_interactable.description = "Ferrolure"
	_channels_run_lure_interactable.required_character = "endo"
	_channels_run_lure_interactable.one_shot = false
	_channels_run_lure_interactable.dwell_time = 2.0
	_channels_run_lure_interactable.tutorial_label = "HOLD"
	_channels_run_lure_interactable.position = CHANNELS_RUN_LURE_POS
	parent.add_child(_channels_run_lure_interactable)
	_channels_run_lure_interactable.interacted.connect(_on_channels_run_lure_activated)

	# Hide alcove near the shelter route.
	_channels_hide_spot = Node3D.new()
	_channels_hide_spot.name = "ChannelsHideSpot"
	_channels_hide_spot.position = CHANNELS_HIDE_SPOT_POS
	parent.add_child(_channels_hide_spot)
	_add_corridor_section(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, -0.04, CHANNELS_HIDE_SPOT_POS.z), Vector3(10, 0.08, 8), Color(0.05, 0.05, 0.07))
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, 1.5, CHANNELS_HIDE_SPOT_POS.z + 4.0), Vector3(10, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x - 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x + 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)

	# Swarm cluster guarding the stretch before the shelter.
	_channels_swarm_units.clear()
	for i in range(CHANNELS_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "ChannelsSwarm_%d" % i
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.3
		swarm_mesh.height = 0.6
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.15, 0.12, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.45, 0.2, 0.06)
		swarm_mat.emission_energy_multiplier = 0.6
		swarm.material_override = swarm_mat
		swarm.position = Vector3(CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i], 0.6, 0.5 + sin(float(i)) * 1.2)
		parent.add_child(swarm)
		_channels_swarm_units.append({
			"node": swarm,
			"x": swarm.position.x,
			"target_x": swarm.position.x,
		})

	# Shelter alcove at the far end of the zone.
	_add_corridor_section(parent, Vector3(CHANNELS_SHELTER_POS.x, -0.04, CHANNELS_SHELTER_POS.z), Vector3(16, 0.08, 10), Color(0.07, 0.07, 0.08))
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x, 1.5, CHANNELS_SHELTER_POS.z + 5.0), Vector3(16, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x - 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x + 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	var shelter_door := MeshInstance3D.new()
	shelter_door.name = "ChannelsShelterDoor"
	var shelter_door_mesh := BoxMesh.new()
	shelter_door_mesh.size = Vector3(2.4, 2.6, 0.18)
	shelter_door.mesh = shelter_door_mesh
	var shelter_door_mat := StandardMaterial3D.new()
	shelter_door_mat.albedo_color = Color(0.22, 0.2, 0.18)
	shelter_door.material_override = shelter_door_mat
	shelter_door.position = CHANNELS_SHELTER_POS + Vector3(0, 1.25, -4.8)
	parent.add_child(shelter_door)
	var shelter_light := OmniLight3D.new()
	shelter_light.position = CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0)
	shelter_light.light_color = Color(0.85, 0.68, 0.42)
	shelter_light.light_energy = 2.1
	shelter_light.omni_range = 12.0
	parent.add_child(shelter_light)

	var shelter_label := Label3D.new()
	shelter_label.name = "ChannelsShelterLabel"
	shelter_label.text = "SHELTER"
	shelter_label.font_size = 28
	shelter_label.pixel_size = 0.008
	shelter_label.modulate = Color(0.92, 0.78, 0.52, 0.85)
	shelter_label.outline_modulate = Color(0, 0, 0, 0.45)
	shelter_label.outline_size = 8
	shelter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shelter_label.position = CHANNELS_SHELTER_POS + Vector3(0, 2.6, 0)
	parent.add_child(shelter_label)

	_add_flora_node(
		parent,
		"channels_memory_reed",
		"Memory Reed",
		"channels",
		CHANNELS_BODY_POS + Vector3(-2.2, 0.0, 1.2),
		"memory",
		"client trace",
		CHANNELS_BODY_POS + Vector3(-0.6, 0.0, 0.2),
		Color(0.86, 0.68, 0.38),
		0.76,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_lumivine",
		"Lumivine",
		"channels",
		CHANNELS_FERROLURE_POS + Vector3(1.8, 0.0, -1.1),
		"iron",
		"iron bloom",
		CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(3.0, 0.0, -0.6),
		Color(0.48, 0.88, 0.58),
		0.84,
		{"tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"channels_shortcut_vine",
		"Shelter Vine",
		"channels",
		CHANNELS_SHORTCUT_BRANCH_POS + Vector3(1.2, 0.0, 2.6),
		"resource",
		"warm shelter trace",
		CHANNELS_SHELTER_POS + Vector3(0.8, 0.0, 0.4),
		Color(0.72, 0.88, 0.52),
		0.68,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_forget_me_not",
		"Forget-Me-Not",
		"channels",
		CHANNELS_SHELTER_POS + Vector3(-2.6, 0.0, 1.7),
		"relationship",
		"Aster",
		CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)

	# Shortcut branch: visible from the outer path, locked from this side until the shelter is reached.
	_add_corridor_section(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x, -0.04, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(6, 0.08, 12), Color(0.055, 0.06, 0.075))
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x - 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x + 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_corridor_section(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, -0.04, CHANNELS_SHELTER_POS.z), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 0.08, 6), Color(0.06, 0.065, 0.08))
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z - 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z + 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)

	_channels_shortcut_gate_mesh = MeshInstance3D.new()
	_channels_shortcut_gate_mesh.name = "ChannelsShortcutGate"
	var shortcut_gate_mesh := BoxMesh.new()
	shortcut_gate_mesh.size = Vector3(6.0, 2.6, 0.18)
	_channels_shortcut_gate_mesh.mesh = shortcut_gate_mesh
	var shortcut_gate_mat := StandardMaterial3D.new()
	shortcut_gate_mat.albedo_color = Color(0.22, 0.26, 0.3)
	shortcut_gate_mat.metallic = 0.2
	shortcut_gate_mat.roughness = 0.7
	_channels_shortcut_gate_mesh.material_override = shortcut_gate_mat
	_channels_shortcut_gate_mesh.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 1.25, 0)
	parent.add_child(_channels_shortcut_gate_mesh)

	var shortcut_gate_body := StaticBody3D.new()
	shortcut_gate_body.name = "ChannelsShortcutGateBody"
	shortcut_gate_body.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 1.25, 0)
	var shortcut_gate_shape := CollisionShape3D.new()
	var shortcut_gate_box := BoxShape3D.new()
	shortcut_gate_box.size = Vector3(6.0, 2.6, 0.2)
	shortcut_gate_shape.shape = shortcut_gate_box
	shortcut_gate_body.add_child(shortcut_gate_shape)
	parent.add_child(shortcut_gate_body)
	_channels_shortcut_gate_collision = shortcut_gate_shape

	_channels_shortcut_light = OmniLight3D.new()
	_channels_shortcut_light.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 2.0, 0.8)
	parent.add_child(_channels_shortcut_light)
	_set_channels_shortcut_unlocked(false)

	var shortcut_table := MeshInstance3D.new()
	var shortcut_table_mesh := BoxMesh.new()
	shortcut_table_mesh.size = Vector3(2.0, 0.18, 1.0)
	shortcut_table.mesh = shortcut_table_mesh
	var shortcut_table_mat := StandardMaterial3D.new()
	shortcut_table_mat.albedo_color = Color(0.28, 0.24, 0.2)
	shortcut_table.material_override = shortcut_table_mat
	shortcut_table.position = CHANNELS_SHELTER_POS + Vector3(-2.8, 0.85, 1.4)
	parent.add_child(shortcut_table)

	var shortcut_bowl := MeshInstance3D.new()
	var shortcut_bowl_mesh := SphereMesh.new()
	shortcut_bowl_mesh.radius = 0.22
	shortcut_bowl_mesh.height = 0.16
	shortcut_bowl.mesh = shortcut_bowl_mesh
	var shortcut_bowl_mat := StandardMaterial3D.new()
	shortcut_bowl_mat.albedo_color = Color(0.7, 0.58, 0.4)
	shortcut_bowl.material_override = shortcut_bowl_mat
	shortcut_bowl.position = CHANNELS_SHELTER_POS + Vector3(-2.5, 1.03, 1.35)
	parent.add_child(shortcut_bowl)

	var shelter_heater := MeshInstance3D.new()
	var shelter_heater_mesh := BoxMesh.new()
	shelter_heater_mesh.size = Vector3(0.8, 0.9, 0.5)
	shelter_heater.mesh = shelter_heater_mesh
	var shelter_heater_mat := StandardMaterial3D.new()
	shelter_heater_mat.albedo_color = Color(0.34, 0.22, 0.14)
	shelter_heater_mat.emission_enabled = true
	shelter_heater_mat.emission = Color(0.95, 0.46, 0.18)
	shelter_heater_mat.emission_energy_multiplier = 0.35
	shelter_heater.material_override = shelter_heater_mat
	shelter_heater.position = CHANNELS_SHELTER_POS + Vector3(3.4, 0.45, 2.0)
	parent.add_child(shelter_heater)

	# Lighting spans the corridor.
	for i in range(5):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 45.0, 2.5, 0)
		light.light_color = Color(0.2, 0.25, 0.4)
		light.light_energy = 1.5
		light.omni_range = 20.0
		parent.add_child(light)

	# Warm lights near stagnant zones
	for i in range(3):
		var sl := OmniLight3D.new()
		sl.position = Vector3(sx + 50.0 + i * 60.0, 2.0, 12.0 if i % 2 == 0 else -12.0)
		sl.light_color = Color(0.5, 0.25, 0.1)
		sl.light_energy = 1.0
		sl.omni_range = 8.0
		parent.add_child(sl)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"channels_body": CHANNELS_BODY_POS,
		"channels_window_one_stage": CHANNELS_WINDOW_ONE_STAGE_POS,
		"channels_window_one_lure": CHANNELS_WINDOW_ONE_LURE_POS,
		"channels_window_one_curtain": CHANNELS_WINDOW_ONE_CURTAIN_POS,
		"channels_window_one_goal": CHANNELS_WINDOW_ONE_GOAL_POS,
		"channels_ferrolure": CHANNELS_FERROLURE_POS,
		"channels_window_two_stage": CHANNELS_WINDOW_TWO_STAGE_POS,
		"channels_window_two_lure": CHANNELS_WINDOW_TWO_LURE_POS,
		"channels_window_two_curtain": CHANNELS_WINDOW_TWO_CURTAIN_POS,
		"channels_window_two_goal": CHANNELS_WINDOW_TWO_GOAL_POS,
		"channels_run_lure": CHANNELS_RUN_LURE_POS,
		"channels_encounter_entry": CHANNELS_ENCOUNTER_ENTRY_POS,
		"channels_hide_spot": CHANNELS_HIDE_SPOT_POS,
		"channels_shelter": CHANNELS_SHELTER_POS,
		"channels_shortcut_gate": CHANNELS_SHORTCUT_GATE_POS,
		"channels_shortcut_branch": CHANNELS_SHORTCUT_BRANCH_POS,
		"stacks_signal_wall": _stacks_signal_interactable.global_position if is_instance_valid(_stacks_signal_interactable) else Vector3(STACKS_START.x + 96.0, 1.0, -16.9),
		"stacks_terminal": _stacks_terminal_interactable.global_position if is_instance_valid(_stacks_terminal_interactable) else Vector3(STACKS_START.x + 88.0, 1.0, 0.0),
		"stacks_workspace": _stacks_workspace_interactable.global_position if is_instance_valid(_stacks_workspace_interactable) else Vector3(STACKS_START.x + 165.0, 1.0, -10.0),
		"stacks_drink_machine": Vector3(STACKS_START.x + 132.0, 0.9, 14.0),
		"rings_client_bloom": _flora_nodes["rings_client_bloom"].get("position", Vector3(RINGS_START.x + 76.0, 0.0, -8.0)) if _flora_nodes.has("rings_client_bloom") else Vector3(RINGS_START.x + 76.0, 0.0, -8.0),
		"rings_forget_me_not": _flora_nodes["rings_forget_me_not"].get("position", Vector3(RINGS_START.x + 116.0, 0.0, 13.8)) if _flora_nodes.has("rings_forget_me_not") else Vector3(RINGS_START.x + 116.0, 0.0, 13.8),
		"rings_doorvine": _flora_nodes["rings_doorvine"].get("position", Vector3(RINGS_START.x + 156.0, 0.0, 8.5)) if _flora_nodes.has("rings_doorvine") else Vector3(RINGS_START.x + 156.0, 0.0, 8.5),
		"lockout_access_panel": LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0.0),
		"lockout_escape_trigger": Vector3(LOCKOUT_START.x - 11.0, 0.5, 0.0),
	}
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		anchors["channels_%s_swarm_start" % window_id] = lane.get("swarm_start_pos", Vector3.ZERO)
	return anchors

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	var atp := {}
	var lane_state := {}
	var journal: Node = get_node_or_null("/root/EngramJournal")
	var support_log: Dictionary = {}
	var flora_state := _flora_system.get_debug_state(
		_scheduler.get_current_tick() if _scheduler else 0.0,
		_current_flora_zone()
	)
	flora_state["visible_clue_count"] = int(flora_state.get("visible_clues", []).size())
	if _game_state:
		for char_id in ["aster", "peris", "endo"]:
			if _game_state.characters.has(char_id):
				atp[char_id] = float(_game_state.characters[char_id].stats.get("atp", 0.0))
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var channel_states: Array = []
		var visible_swarm_units := 0
		var washed_swarm_units := 0
		var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
		for channel_variant in lane.get("periodic_channels", []):
			var channel: Dictionary = channel_variant
			channel_states.append({
				"position": channel.get("position", Vector3.ZERO),
				"contact_time": float(channel.get("contact_time", 0.0)),
				"phase_offset": float(channel.get("phase_offset", 0.0)),
				"local_phase": float(channel.get("local_phase", _channels_window_local_phase(current_tick, lane, channel))),
				"level": float(channel.get("level", 0.0)),
				"flooded": bool(channel.get("flooded", false)),
			})
		for unit_variant in lane.get("swarm_units", []):
			var unit: Dictionary = unit_variant
			var node = unit.get("node")
			if is_instance_valid(node) and node.visible:
				visible_swarm_units += 1
			if str(unit.get("state", "")) == "washed":
				washed_swarm_units += 1
		lane_state[window_id] = {
			"phase": str(lane.get("phase", "")),
			"last_outcome": str(lane.get("last_outcome", "")),
			"lure_active": bool(lane.get("lure_active", false)),
			"safe_until_tick": float(lane.get("safe_until_tick", -1.0)),
			"flow_offset": float(lane.get("flow_offset", 0.0)),
			"periodic_channel_count": int(lane.get("periodic_channels", []).size()),
			"bridge_segment_count": int(lane.get("bridge_segments", []).size()),
			"corpse_count": int(lane.get("corpse_nodes", []).size()),
			"swarm_unit_count": int(lane.get("swarm_units", []).size()),
			"visible_swarm_units": visible_swarm_units,
			"washed_swarm_units": washed_swarm_units,
			"swarm_state": str(lane.get("swarm_state", "")),
			"washed_channel_index": int(lane.get("washed_channel_index", -1)),
			"wash_analysis": lane.get("wash_analysis", {}),
			"channels": channel_states,
		}
	if journal != null:
		if _stacks_support_log_entry_id != -1:
			support_log = journal.get_entry(_stacks_support_log_entry_id)
		if support_log.is_empty():
			support_log = journal.get_entry_by_story_key(STACKS_SUPPORT_LOG_KEY)
	state["active_character"] = _active_character
	state["channels_active_window_lane"] = _channels_active_window_lane
	state["channels_shortcut_unlocked"] = _channels_shortcut_unlocked
	state["channels_party_recuperated"] = _channels_party_recuperated
	state["channels_shelter_reached"] = _channels_shelter_reached
	state["channels_flow_power"] = _channels_flow_power
	state["channels_flush_state"] = _channels_flush_state
	state["channels_window_lanes"] = lane_state
	state["channels_run_lure_active"] = _channels_run_lure_active
	state["channels_party_hidden"] = _channels_party_hidden
	state["channels_hp"] = {
		"aster": _aster_hp,
		"peris": _peris_hp,
	}
	state["channels_atp"] = atp
	state["overlay_states"] = _overlay_states.duplicate(true)
	state["stacks"] = {
		"support_log_presented": _stacks_support_log_presented,
		"signal_interacted": _stacks_signal_interacted,
		"terminal_interacted": _stacks_terminal_interacted,
		"archive_interacted": _stacks_archive_interacted,
		"audit_flags_found": _stacks_audit_flags_found,
		"engram": {
			"entry_count": journal.get_entry_count() if journal != null else 0,
			"story_key": str(support_log.get("story_key", "")),
			"overlay_visible": _engram_overlay != null and _engram_overlay.visible,
		},
	}
	state["rings"] = {
		"endo_visible": _endo != null and _endo.visible,
		"peris_overlay_enabled": bool(_overlay_states.get("peris", false)),
	}
	state["lockout"] = {
		"naturalizer_count": _naturalizers.size(),
		"boundary_crossed": _aster_node != null and _aster_node.global_position.x < LOCKOUT_START.x - 10.0,
	}
	state["flora"] = flora_state
	return state

func headless_select_character(char_id: String) -> void:
	_select_character(char_id)

func headless_set_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = enabled
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	var node := _get_character_node(char_id)
	if node == null:
		return
	if _game_state and _game_state.characters.has(char_id):
		_game_state.command_stop(char_id)
		_game_state.characters[char_id].position = pos
	node.global_position = pos

# Shared front-half of every prepare_*_fragment entry point: wipe the transient UI/scheduler
# state and (for the chunked fragments) swap the live chunk in. channels passes "" because it is
# the always-loaded base chunk, driven by window lanes rather than a load/unload.
func _begin_fragment_prep(chunk_name: String) -> void:
	if _dialogue and _dialogue.has_method("clear"):
		_dialogue.clear()
	if _scheduler:
		_scheduler.clear()
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	if chunk_name != "":
		_swap_to_chunk(chunk_name)

# Load the named chunk and unload every other act1 chunk so only one is live (act1 cuts between
# chunks). Unloading an already-unloaded chunk is a no-op, so this is safe from any starting state.
func _swap_to_chunk(chunk_name: String) -> void:
	_load_chunk(chunk_name)
	for other in CHUNK_GRIDS.keys():
		if other != chunk_name:
			_unload_chunk(other)

# Halt the whole party so a fragment can reposition them cleanly.
func _stop_party() -> void:
	if _game_state == null:
		return
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

func prepare_channels_fragment() -> void:
	_begin_fragment_prep("")
	_channels_active_window_lane = ""
	for window_id in _channels_window_lanes.keys():
		_reset_channels_window_lane(window_id)
	_reset_channels_encounter_nodes()
	_stop_party()
	_current_step = ""
	_select_character("aster")
	_player.set_move_enabled(true)

func prepare_stacks_fragment(mode: String = "engram") -> void:
	_begin_fragment_prep("stacks")
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal != null:
		journal.reset_state(false)
	_select_character("aster")
	_player.global_position = STACKS_START + Vector3(5.0, 0.5, 0.0)
	_player.set_move_enabled(true)
	match mode:
		"signal":
			_start_stacks_signal()
		"terminal":
			_start_stacks_terminal()
		"archive":
			_start_stacks_archive()
		"explore":
			_start_stacks_explore()
		_:
			_enter_step("stacks_enter")
			_player.set_move_enabled(false)

func prepare_rings_fragment(mode: String = "client") -> void:
	_begin_fragment_prep("rings")
	_clear_lockout_runtime_state()
	_endo.visible = true
	_stop_party()
	headless_set_character_position("aster", RINGS_START + Vector3(8.0, 0.5, 0.0))
	headless_set_character_position("peris", RINGS_START + Vector3(6.5, 0.5, 2.0))
	headless_set_character_position("endo", RINGS_START + Vector3(5.0, 0.5, -1.8))
	requested_scene_change = ""
	match mode:
		"explore":
			_endo.visible = false
			_select_character("aster")
			_start_rings_explore()
		_:
			_select_character("peris")
			_enter_step("rings_client")
			_player.set_move_enabled(true)

func prepare_lockout_fragment(mode: String = "chase") -> void:
	_begin_fragment_prep("lockout")
	_clear_lockout_runtime_state()
	_endo.visible = true
	_stop_party()
	headless_set_character_position("aster", LOCKOUT_BOUNDARY + Vector3(-7.5, 0.5, 0.0))
	headless_set_character_position("peris", LOCKOUT_BOUNDARY + Vector3(-9.0, 0.5, 1.4))
	headless_set_character_position("endo", LOCKOUT_BOUNDARY + Vector3(-10.5, 0.5, -1.4))
	requested_scene_change = ""
	_select_character("aster")
	match mode:
		"approach":
			_enter_step("lockout_approach")
			_player.set_move_enabled(false)
		"rejected":
			_enter_step("lockout_rejected")
			_player.set_move_enabled(false)
		_:
			_enter_step("lockout_chase")
			_player.set_move_enabled(true)
			_tutorial_prompt.show_prompt("Run!")
			_spawn_lockout_naturalizers()

func start_channels_window_puzzle(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	prepare_channels_fragment()
	var party_positions := _get_channels_window_party_positions(window_id)
	for char_id in party_positions.keys():
		headless_set_character_position(char_id, party_positions[char_id])
	_begin_channels_window_lane(window_id)

func activate_channels_window_lure(window_id: String) -> void:
	_on_channels_window_lure_activated(window_id)

func set_channels_window_flow_offset(window_id: String, offset: float) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["flow_offset"] = offset
	_channels_window_lanes[window_id] = lane

func get_channels_window_wash_analysis(window_id: String) -> Dictionary:
	if not _channels_window_lanes.has(window_id):
		return {}
	return _channels_window_lanes[window_id].get("wash_analysis", {})

func _build_stacks_chunk(parent: Node3D) -> void:
	var sx := STACKS_START.x
	var length := 220.0
	var width := 40.0
	var floor_color := Color(0.05, 0.05, 0.06)
	var wall_color := Color(0.07, 0.07, 0.09)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Dense rack grid creates corridors.
	for row in range(5):
		for col in range(12):
			var rack := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(1.0, 3.0, 5.0)
			rack.mesh = rb
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.06, 0.06, 0.08)
			rm.metallic = 0.3
			rack.material_override = rm
			rack.position = Vector3(sx + 15 + col * 16.0, 1.5, -12.0 + row * 6.0)
			parent.add_child(rack)

	# Terminal interactable (midway through the stacks)
	var terminal = preload("res://scenes/game/interactable.tscn").instantiate()
	terminal.name = "DataTerminal"
	terminal.description = "Maintenance Terminal"
	terminal.dialogue_box = _dialogue
	terminal.active_character = "aster"
	terminal.one_shot = true
	terminal.dwell_time = 1.3
	terminal.position = Vector3(sx + length * 0.4, 1.0, 0)
	terminal.tutorial_label = "READ"
	terminal.interacted.connect(trigger_stacks_terminal.bind(true))
	parent.add_child(terminal)
	_stacks_terminal_interactable = terminal

	# Sensor panels and cable bundles - the space reads as maintained instead of abandoned.
	for x_offset in [72.0, 84.0, 108.0]:
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(3.4, 2.2, 0.16)
		panel.mesh = panel_mesh
		var panel_mat := StandardMaterial3D.new()
		panel_mat.albedo_color = Color(0.08, 0.1, 0.12)
		panel_mat.emission_enabled = true
		panel_mat.emission = Color(0.18, 0.34, 0.42)
		panel_mat.emission_energy_multiplier = 0.35
		panel.material_override = panel_mat
		panel.position = Vector3(sx + x_offset, 1.8, -width / 2.0 + 1.4)
		parent.add_child(panel)

		var cable := MeshInstance3D.new()
		var cable_mesh := CylinderMesh.new()
		cable_mesh.top_radius = 0.08
		cable_mesh.bottom_radius = 0.08
		cable_mesh.height = 4.8
		cable.mesh = cable_mesh
		var cable_mat := StandardMaterial3D.new()
		cable_mat.albedo_color = Color(0.16, 0.18, 0.2)
		cable.material_override = cable_mat
		cable.rotation_degrees.z = 90.0
		cable.position = Vector3(sx + x_offset + 1.5, 2.8, -width / 2.0 + 2.4)
		parent.add_child(cable)

	# Tuned signal lane - one wall reads as custom instrumentation instead of stock hardware.
	var signal_strip := MeshInstance3D.new()
	var signal_strip_mesh := BoxMesh.new()
	signal_strip_mesh.size = Vector3(7.0, 0.03, 1.6)
	signal_strip.mesh = signal_strip_mesh
	var signal_strip_mat := StandardMaterial3D.new()
	signal_strip_mat.albedo_color = Color(0.16, 0.14, 0.08)
	signal_strip_mat.emission_enabled = true
	signal_strip_mat.emission = Color(0.42, 0.3, 0.14)
	signal_strip_mat.emission_energy_multiplier = 0.25
	signal_strip.material_override = signal_strip_mat
	signal_strip.position = Vector3(sx + 96.0, 0.03, -width / 2.0 + 3.7)
	parent.add_child(signal_strip)

	var signal_panel := MeshInstance3D.new()
	var signal_panel_mesh := BoxMesh.new()
	signal_panel_mesh.size = Vector3(6.2, 2.5, 0.18)
	signal_panel.mesh = signal_panel_mesh
	var signal_panel_mat := StandardMaterial3D.new()
	signal_panel_mat.albedo_color = Color(0.11, 0.11, 0.09)
	signal_panel_mat.emission_enabled = true
	signal_panel_mat.emission = Color(0.46, 0.34, 0.16)
	signal_panel_mat.emission_energy_multiplier = 0.55
	signal_panel.material_override = signal_panel_mat
	signal_panel.position = Vector3(sx + 96.0, 1.85, -width / 2.0 + 1.32)
	parent.add_child(signal_panel)

	for i in range(4):
		var meter := MeshInstance3D.new()
		var meter_mesh := BoxMesh.new()
		meter_mesh.size = Vector3(0.45, 1.4 + 0.18 * float(i % 2), 0.08)
		meter.mesh = meter_mesh
		var meter_mat := StandardMaterial3D.new()
		meter_mat.albedo_color = Color(0.12, 0.16, 0.14)
		meter_mat.emission_enabled = true
		meter_mat.emission = Color(0.52, 0.74, 0.28) if i < 2 else Color(0.8, 0.62, 0.24)
		meter_mat.emission_energy_multiplier = 0.6
		meter.material_override = meter_mat
		meter.position = signal_panel.position + Vector3(-1.8 + float(i) * 1.2, -0.15 + 0.08 * float(i % 2), 0.12)
		parent.add_child(meter)

	var signal_light := OmniLight3D.new()
	signal_light.position = Vector3(sx + 96.0, 2.2, -13.8)
	signal_light.light_color = Color(0.46, 0.34, 0.18)
	signal_light.light_energy = 1.1
	signal_light.omni_range = 7.0
	parent.add_child(signal_light)

	var signal_wall = preload("res://scenes/game/interactable.tscn").instantiate()
	signal_wall.name = "SignalWall"
	signal_wall.description = "Custom Sensor Wall"
	signal_wall.dialogue_box = _dialogue
	signal_wall.active_character = "aster"
	signal_wall.one_shot = true
	signal_wall.dwell_time = 1.3
	signal_wall.position = Vector3(sx + 96.0, 1.0, -16.9)
	signal_wall.tutorial_label = "PARSE"
	signal_wall.interacted.connect(trigger_stacks_signal.bind(true))
	parent.add_child(signal_wall)
	_stacks_signal_interactable = signal_wall

	# Myke's elegant workspace - deeper in, off the main path
	var elegant_light := OmniLight3D.new()
	elegant_light.position = Vector3(sx + length * 0.75, 2.0, -10)
	elegant_light.light_color = Color(0.42, 0.3, 0.2)
	elegant_light.light_energy = 1.5
	elegant_light.omni_range = 9.0
	parent.add_child(elegant_light)

	var work_table := MeshInstance3D.new()
	var work_table_mesh := BoxMesh.new()
	work_table_mesh.size = Vector3(3.2, 0.18, 1.6)
	work_table.mesh = work_table_mesh
	var work_table_mat := StandardMaterial3D.new()
	work_table_mat.albedo_color = Color(0.24, 0.2, 0.16)
	work_table.material_override = work_table_mat
	work_table.position = Vector3(sx + length * 0.75, 0.95, -10.0)
	parent.add_child(work_table)

	var notebook := MeshInstance3D.new()
	var notebook_mesh := BoxMesh.new()
	notebook_mesh.size = Vector3(0.55, 0.04, 0.8)
	notebook.mesh = notebook_mesh
	var notebook_mat := StandardMaterial3D.new()
	notebook_mat.albedo_color = Color(0.82, 0.78, 0.66)
	notebook.material_override = notebook_mat
	notebook.rotation_degrees.y = 18.0
	notebook.position = work_table.position + Vector3(0.6, 0.13, -0.2)
	parent.add_child(notebook)

	var workspace = preload("res://scenes/game/interactable.tscn").instantiate()
	workspace.name = "SupportWorkspace"
	workspace.description = "Support Workspace"
	workspace.dialogue_box = _dialogue
	workspace.active_character = "aster"
	workspace.one_shot = true
	workspace.dwell_time = 1.3
	workspace.position = Vector3(sx + length * 0.75, 1.0, -10.0)
	workspace.tutorial_label = "TRACE"
	workspace.interacted.connect(trigger_stacks_archive.bind(true))
	parent.add_child(workspace)
	_stacks_workspace_interactable = workspace

	var drink := MeshInstance3D.new()
	var drink_mesh := BoxMesh.new()
	drink_mesh.size = Vector3(1.1, 1.9, 0.9)
	drink.mesh = drink_mesh
	var drink_mat := StandardMaterial3D.new()
	drink_mat.albedo_color = Color(0.14, 0.18, 0.2)
	drink_mat.emission_enabled = true
	drink_mat.emission = Color(0.1, 0.18, 0.24)
	drink_mat.emission_energy_multiplier = 0.42
	drink.material_override = drink_mat
	drink.position = Vector3(sx + length * 0.6, 0.95, width / 2.0 - 3.0)
	parent.add_child(drink)

	# Cold lighting spans the corridor.
	for i in range(6):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 35.0, 4.0, 0)
		light.light_color = Color(0.2, 0.2, 0.3)
		light.light_energy = 2.0
		light.omni_range = 20.0
		parent.add_child(light)

	_add_flora_node(
		parent,
		"stacks_terminal_bloom",
		"Duct Bloom",
		"stacks",
		Vector3(sx + length * 0.4, 0.0, 3.2),
		"cache",
		"terminal cache",
		Vector3(sx + length * 0.4, 0.0, 0.0),
		Color(0.72, 0.88, 0.54),
		0.58
	)
	_add_flora_node(
		parent,
		"stacks_archive_vine",
		"Archive Vine",
		"stacks",
		Vector3(sx + length * 0.75, 0.0, -8.2),
		"resource",
		"warm archive trace",
		Vector3(sx + length * 0.75, 0.0, -10.0),
		Color(0.88, 0.78, 0.46),
		0.7,
		{"tended": true}
	)

func _build_rings_chunk(parent: Node3D) -> void:
	var sx := RINGS_START.x
	var length := 200.0
	var width := 50.0
	var floor_color := Color(0.12, 0.11, 0.1)
	var wall_color := Color(0.15, 0.14, 0.12)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner residential walls.
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, -width / 2.0), Vector3(length, 4, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, width / 2.0), Vector3(length, 4, 0.3), wall_color)

	# Warm residential lighting.
	for i in range(8):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 15 + i * 25.0, 3.5, 0)
		light.light_color = Color(0.8, 0.6, 0.4)
		light.light_energy = 2.5
		light.omni_range = 18.0
		parent.add_child(light)

	# Simulation bay windows (glowing rectangles along the north wall)
	for i in range(10):
		var bay := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(5, 2.0, 0.1)
		bay.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		bm.emission_enabled = true
		bm.emission = Color(0.3, 0.25, 0.15)
		bm.emission_energy_multiplier = 0.5
		bay.material_override = bm
		bay.position = Vector3(sx + 10 + i * 18.0, 1.8, -width / 2.0 + 0.2)
		parent.add_child(bay)

	# Apartment doors along the south wall (some sealed, one ajar)
	for i in range(8):
		var door := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(2.0, 2.5, 0.1)
		door.mesh = db
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.18, 0.16, 0.14)
		door.material_override = dm
		door.position = Vector3(sx + 20 + i * 22.0, 1.25, width / 2.0 - 0.2)
		parent.add_child(door)

	# Client interactable (Peris tries to talk)
	var client := preload("res://scenes/game/interactable.tscn").instantiate()
	client.name = "ClientNPC"
	client.description = "Former Client"
	client.dialogue_key = "ring.marco.entry.marco.warn"
	client.dialogue_box = _dialogue
	client.active_character = "peris"
	client.one_shot = true
	client.dwell_time = 1.0
	client.position = Vector3(sx + length * 0.4, 0.5, -5)
	add_child(client)

	# Drink machine set dressing.
	var drink := MeshInstance3D.new()
	var drb := BoxMesh.new()
	drb.size = Vector3(1.0, 1.8, 0.8)
	drink.mesh = drb
	var drm := StandardMaterial3D.new()
	drm.albedo_color = Color(0.15, 0.18, 0.2)
	drm.emission_enabled = true
	drm.emission = Color(0.1, 0.15, 0.2)
	drm.emission_energy_multiplier = 0.3
	drink.material_override = drm
	drink.position = Vector3(sx + length * 0.6, 0.9, width / 2.0 - 2.0)
	parent.add_child(drink)

	_add_flora_node(
		parent,
		"rings_client_bloom",
		"Client Bloom",
		"rings",
		Vector3(sx + length * 0.38, 0.0, -8.0),
		"memory",
		"client trace",
		Vector3(sx + length * 0.4, 0.0, -5.0),
		Color(0.95, 0.74, 0.44),
		0.82,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"rings_forget_me_not",
		"Forget-Me-Not",
		"rings",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		"relationship",
		"Aster",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"rings_doorvine",
		"Doorvine",
		"rings",
		Vector3(sx + length * 0.78, 0.0, 8.5),
		"resource",
		"occupied warmth",
		Vector3(sx + length * 0.8, 0.0, 10.0),
		Color(0.72, 0.88, 0.58),
		0.52
	)

func _build_lockout_chunk(parent: Node3D) -> void:
	var sx := LOCKOUT_START.x
	var length := 80.0  # Shorter — this is an event, not an exploration area
	var width := 20.0
	var floor_color := Color(0.1, 0.1, 0.12)
	var wall_color := Color(0.12, 0.12, 0.14)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner boundary walls.
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Progressive lighting: dim at entry, bright at boundary (approaching civilization)
	for i in range(4):
		var light := OmniLight3D.new()
		var t: float = float(i) / 3.0
		light.position = Vector3(sx + 10.0 + i * 20.0, 3.0, 0)
		light.light_color = Color(0.3 + t * 0.3, 0.3 + t * 0.2, 0.35 + t * 0.25)
		light.light_energy = 1.0 + t * 2.0
		light.omni_range = 12.0 + t * 6.0
		parent.add_child(light)

	# Access panel visual (at the boundary)
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 1.5, 1.0)
	panel.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.14, 0.18)
	pm.emission_enabled = true
	pm.emission = Color(0.1, 0.15, 0.25)
	pm.emission_energy_multiplier = 0.8
	panel.material_override = pm
	panel.position = LOCKOUT_BOUNDARY + Vector3(-0.5, 0.75, 0)
	parent.add_child(panel)

	# Access panel interactable
	var access := preload("res://scenes/game/interactable.tscn").instantiate()
	access.name = "AccessPanel"
	access.description = "Access Panel"
	access.dialogue_key = "lockout.approach.panel_reject"
	access.dialogue_box = _dialogue
	access.active_character = "aster"
	access.one_shot = true
	access.dwell_time = 1.5
	access.position = LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0)
	add_child(access)
