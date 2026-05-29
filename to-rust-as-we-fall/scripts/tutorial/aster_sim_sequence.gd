@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Aster simulation tutorial: movement, interaction, ATP, Ron, Tag Day.

var _has_moved := false
var _has_drunk := false

var _ron
var _terminal  # Forecasting terminal interactable.
var _drink_machine  # Drink machine interactable.
var _hud  # GameHUD with ATP bar and portrait.

# Terminal screen-focus cinematic (click the terminal → camera frames the
# screen, the low-fi screen swaps for a detailed readout, then the beat ends).
const TERMINAL_FOCUS_DURATION := 3.0
const TERMINAL_FOCUS_OFFSET := Vector3(0.0, 1.3, 3.0)
var _terminal_screen_world := Vector3.ZERO
var _terminal_screen_lowfi: MeshInstance3D
var _terminal_screen_detail: Node3D
var _terminal_prev_camera_offset := Vector3.ZERO
var _terminal_prev_camera_target: Node3D

# Exploration beat (post-drink, pre-Tag-Day)
@export var show_graybox_room := true
@export var show_high_res_room := false
var _explore_hallway_gate  # Interactable at hallway exit
const EXPLORE_MIN_TIME := 12.0  # scheduler ticks before the hallway gate unlocks
var _explore_gate_unlocked := false
var _explore_gate_fired := false
const HALLWAY_EXIT_CELL := Vector2i(16, 4)  # right edge of the room, just inside the wall border

# Grid system
var _grid: GridWorld
var _renderer: GridRenderer

var _data_displays: Array[MeshInstance3D] = []

const PLACEMENT_ROOT := "ScenePlacement"
const OUTLINE_TARGET_SCRIPT := preload("res://scripts/game/objects/outline_surface_target.gd")

# Start below max ATP so the drink refill is visible.
const ATP_START := 6.0
const ATP_MAX := GameState.ATP_MAX_PIPS

# --- Virtual overrides ---

func _build_scene() -> void:
	_apply_high_res_room_visibility()
	_build_environment()
	_build_decorations()
	_build_terminal()
	_build_drink_machine()

func _build_characters() -> void:
	var in_game := not Engine.is_editor_hint()

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = _placement_or_grid("AsterStart", Vector2i(3, 4), 0.5)
	if in_game:
		_player.grid_world = _grid
	chars.add_child(_player)

	_ron = _create_npc("Ron", Color(0.7, 0.6, 0.45))
	_ron.display_name = "RON"
	_ron.position = _placement_or_grid("RonStart", Vector2i(2, 6), 0.0)
	if in_game:
		_ron.grid_world = _grid
	chars.add_child(_ron)

	if in_game:
		_setup_game_camera(_player, Vector3(0, 8, 6))

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, _player.move_speed, {"atp": ATP_START})
	_register_gs_character("ron", _ron, _ron.move_speed)

func _setup_ui() -> void:
	# Only the ATP bar is active in this tutorial beat.
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/ui/game_hud.gd"))
	add_child(_hud)
	_hud.add_stat_bar("atp", Color(0.3, 0.7, 0.4), ATP_MAX, ATP_START)
	_hud.bind_game_state(_game_state, "aster")

func _begin() -> void:
	_enable_outline_preview()
	_connect_outline_feedback_sources(self)
	_start_fade_in()

func _enable_outline_preview() -> void:
	if not OUTLINE_POST_PROCESS_ENABLED:
		show_high_res_room = false
		_apply_high_res_room_visibility()
	_set_imported_outline_preview_enabled(OUTLINE_POST_PROCESS_ENABLED)
	if find_child("AsterSimRoomOutlinePreview", true, false) != null:
		_perception_mode = "outline"
		return
	_setup_perception("outline", _player)

func _set_imported_outline_preview_enabled(enabled: bool) -> void:
	for preview in find_children("AsterSimRoomOutlinePreview", "MeshInstance3D", true, false):
		if preview is MeshInstance3D:
			(preview as MeshInstance3D).visible = enabled

func _on_process(_delta: float, _spd: float) -> void:
	# GameHud handles ATP updates.
	_update_fades()
	_update_show_terminal()

	for i in range(_data_displays.size()):
		var d := _data_displays[i]
		d.position.y = 1.8 + sin(Time.get_ticks_msec() * 0.001 + i * 1.5) * 0.08  # @rendering_only: data display bobbing
		d.rotation.y += _delta * 0.15

func _get_speed_recipients() -> Array:
	var recipients := []
	if _terminal:
		recipients.append(_terminal)
	if _drink_machine:
		recipients.append(_drink_machine)
	return recipients

func _placement_node(marker_name: String) -> Node3D:
	var root := get_node_or_null(PLACEMENT_ROOT)
	if root == null:
		return null
	return root.find_child(marker_name, true, false) as Node3D

func _placement_or_position(marker_name: String, fallback_position: Vector3) -> Vector3:
	var marker := _placement_node(marker_name)
	return marker.global_position if marker != null else fallback_position

func _placement_or_grid(marker_name: String, fallback_cell: Vector2i, y: float = 0.0) -> Vector3:
	var fallback := _grid.grid_to_world(fallback_cell)
	fallback.y = y
	return _placement_or_position(marker_name, fallback)

func _local_for_parent(parent: Node3D, global_position: Vector3) -> Vector3:
	return parent.to_local(global_position) if parent != null else global_position

func _apply_high_res_room_visibility() -> void:
	var high_res_scene := find_child("AsterRoom", true, false) as Node3D
	if high_res_scene != null:
		high_res_scene.visible = show_high_res_room
		var high_res_room := high_res_scene.find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		for light in high_res_scene.find_children("*", "Light3D", true, false):
			if light is Light3D:
				(light as Light3D).visible = show_high_res_room
	else:
		var high_res_room := find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		var high_res_spot := find_child("SpotLight3D", true, false) as Light3D
		if high_res_spot != null:
			high_res_spot.visible = show_high_res_room

func _create_graybox_outline_target(
		parent: Node3D,
		target_name: String,
		center: Vector3,
		size: Vector3,
		meshes: Array,
		element_id: String,
		radius: float = 1.0
	) -> Node3D:
	var target := StaticBody3D.new()
	target.name = target_name
	target.set_script(OUTLINE_TARGET_SCRIPT)
	target.position = center
	target.set("outline_highlight_radius", radius)
	target.set("outline_highlight_extents", size * 0.5)
	target.set("outline_highlight_height", 0.0)
	target.set("selected_feedback_duration", 3.0)
	target.set("hover_object_outline_width", 0.08)
	target.set("selected_object_outline_width", 0.12)
	target.set("selected_object_glow_strength", 3.8)
	target.set("selected_particle_count", 180)
	target.set("outline_particles_enabled", true)
	target.set("outline_particles_per_mesh", 220)
	target.set_meta("room_element_id", element_id)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	target.add_child(collision_shape)
	parent.add_child(target)

	for mesh in meshes:
		if mesh is MeshInstance3D:
			target.call("register_highlight_mesh", mesh)
	if not Engine.is_editor_hint():
		_connect_outline_feedback_source(target)
	return target

func _set_room_target_interaction_delegate(target: Node, delegate: Node) -> void:
	if target != null and delegate != null and target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", delegate)

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.0)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.05, 0.03, 0.01), 2.0)

func _update_show_terminal() -> void:
	if _current_step == "show_terminal" and not _has_moved and _player.is_moving():
		_has_moved = true
		_terminal.hide_tutorial_label()

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_current_step = "fade_in"
	_player.set_move_enabled(false)
	_fade_from(Color(0, 0, 0, 1), 2.5, _start_working, "working")

func _start_working() -> void:
	_current_step = "working"
	_scheduler.schedule_after(7.0, _start_ron_approaches, "ron_approaches")

func _start_ron_approaches() -> void:
	_current_step = "ron_approaches"
	_hide_thought()
	_ron.walk_to(_player.global_position + Vector3(1.5, 0, 0.5))
	_scheduler.schedule_after(3.0, _start_ron_greeting, "ron_greeting")

func _start_ron_greeting() -> void:
	_current_step = "ron_greeting"
	_ron.stop()
	DialogueData.say_to(_dialogue, "aster_sim.ron.greeting")
	DialogueData.say_to(_dialogue, "aster_sim.ron.name")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_show_terminal, "show_terminal"),
		CONNECT_ONE_SHOT
	)

func _start_show_terminal() -> void:
	_current_step = "show_terminal"
	if _terminal and _terminal.has_method("set_interaction_enabled"):
		_terminal.set_interaction_enabled(true)
	_terminal.show_tutorial_label()
	_player.set_move_enabled(true)
	# Terminal interaction triggers _on_terminal_interacted (signal-driven)

func _on_terminal_interacted() -> void:
	if _current_step != "show_terminal":
		return
	_scheduler.cancel_tag("drink_redirect")
	_start_terminal_focus()

# Click the terminal → frame the screen, swap in the detailed readout, hold a
# beat, then continue. Scheduler-driven so it runs headless and respects F.
func _start_terminal_focus() -> void:
	_current_step = "terminal_focus"
	_player.set_move_enabled(false)
	_begin_terminal_screen_focus()
	_scheduler.schedule_after(TERMINAL_FOCUS_DURATION, _end_terminal_focus, "terminal_focus")

func _end_terminal_focus() -> void:
	_end_terminal_screen_focus()
	_player.set_move_enabled(true)
	_start_terminal_data()

func _begin_terminal_screen_focus() -> void:
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = false
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = true
	if _camera != null:
		_terminal_prev_camera_offset = _camera.follow_offset
		_terminal_prev_camera_target = _camera.target
		_camera.follow_offset = TERMINAL_FOCUS_OFFSET
		_camera.lock_to(_terminal_screen_world)

func _end_terminal_screen_focus() -> void:
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = false
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = true
	if _camera != null:
		_camera.follow_offset = _terminal_prev_camera_offset
		_camera.target = _terminal_prev_camera_target
		_camera.unlock()

func _start_terminal_data() -> void:
	_current_step = "terminal_data"
	_scheduler.schedule_after(0.75, _start_ron_drinks, "ron_drinks")

func _start_ron_drinks() -> void:
	_current_step = "ron_drinks"
	_scheduler.schedule_after(0.0, _start_walk_to_drink, "walk_to_drink")

func _start_walk_to_drink() -> void:
	_current_step = "walk_to_drink"
	if _drink_machine and _drink_machine.has_method("set_interaction_enabled"):
		_drink_machine.set_interaction_enabled(true)
	_drink_machine.show_tutorial_label()
	# Hint if the player skips the drink too long.
	_scheduler.schedule_after(8.0, _show_drink_redirect, "drink_redirect")

func _show_drink_redirect() -> void:
	if not _has_drunk and _current_step == "walk_to_drink":
		_show_thought(DialogueData.text("aster_sim.drink_redirect.thought"))

func _on_drink_interacted() -> void:
	if _has_drunk:
		return
	if _current_step != "walk_to_drink":
		return
	_has_drunk = true
	_scheduler.cancel_tag("drink_redirect")
	_start_drink()

func _start_drink() -> void:
	_current_step = "drink"
	_game_state.set_stat("aster", "atp", ATP_MAX)
	_hide_thought()
	_scheduler.schedule_after(2.0, _start_ron_move_fast, "ron_move_fast")

func _start_ron_move_fast() -> void:
	_current_step = "ron_move_fast"
	var hallway_world := _grid.grid_to_world(HALLWAY_EXIT_CELL)
	if _ron and _ron.has_method("walk_to"):
		_ron.walk_to(_placement_or_position(
			"RonExitTarget",
			Vector3(hallway_world.x - 1.0, 0.0, hallway_world.z)
	))
	DialogueData.say_to(_dialogue, "aster_sim.ron.move_fast")
	_dialogue_chain([
		"aster_sim.ron.drinks",
		"aster_sim.ron.lighting",
		"aster_sim.aster.lighting",
		"aster_sim.ron.tag_day_jobs",
	], func(): _scheduler.schedule_after(0, _start_explore_workspace, "explore_workspace"))

func _start_explore_workspace() -> void:
	_current_step = "explore_workspace"
	# Time-lock the hallway for a short exploration beat.
	_build_exploration_objects()
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	_scheduler.schedule_after(EXPLORE_MIN_TIME, _unlock_exploration_gate, "explore_gate_unlock")

func _unlock_exploration_gate() -> void:
	_explore_gate_unlocked = true
	if _explore_hallway_gate and _explore_hallway_gate.has_method("show_tutorial_label"):
		_explore_hallway_gate.show_tutorial_label()

func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_start_tag_notify()

func _start_tag_notify() -> void:
	_current_step = "tag_notify"
	DialogueData.say_to(_dialogue, "aster_sim.device.tag_verify")
	DialogueData.say_to(_dialogue, "aster_sim.ron.tag_notify")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_walk_to_exit, "walk_to_exit"),
		CONNECT_ONE_SHOT
	)

func _start_walk_to_exit() -> void:
	_current_step = "walk_to_exit"
	DialogueData.say_to(_dialogue, "aster_sim.tag_routine")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_transition_out, "transition_out"),
		CONNECT_ONE_SHOT
	)

func _start_transition_out() -> void:
	_current_step = "transition_out"
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_current_step = "complete"
	_change_scene_or_record("res://scenes/tutorial/peris_sim.tscn")

# --- Environment ---

func _build_environment() -> void:
	# Load grid from level data
	_grid = GridWorld.new()
	_grid.load_from_json("res://data/levels/aster_sim.json")

	# Grid renderer creates floor collision and tile meshes.
	_renderer = GridRenderer.new()
	_renderer.name = "Environment"
	var warm_colors := {
		GridWorld.Tile.FLOOR: Color(0.12, 0.1, 0.08),
		GridWorld.Tile.WALL: Color(0.15, 0.12, 0.1),
		GridWorld.Tile.FLORA: Color(0.1, 0.18, 0.1),
		GridWorld.Tile.IRON_BLOOM: Color(0.25, 0.1, 0.05),
		GridWorld.Tile.SHELTER: Color(0.1, 0.12, 0.2),
		GridWorld.Tile.TERMINAL: Color(0.1, 0.15, 0.18),
		GridWorld.Tile.FOOD: Color(0.1, 0.16, 0.1),
	}
	_renderer.setup(_grid, {"colors": warm_colors})
	add_child(_renderer)
	_apply_graybox_visibility()

	var env_node := _renderer
	var use_imported_room_lighting := show_high_res_room and not show_graybox_room

	# Floating data motes.
	var player_start := _placement_or_grid("DataMotesCenter", Vector2i(3, 4), 1.8)
	var data_display_meshes: Array = []
	for i in range(3):
		var angle := i * TAU / 3.0
		var pos := Vector3(player_start.x + cos(angle) * 1.5, 1.8, player_start.z + sin(angle) * 1.5)
		var display := _create_holo_display(pos)
		env_node.add_child(display)
		_data_displays.append(display)
		data_display_meshes.append(display)
	_create_graybox_outline_target(env_node, "RoomTargetDataDisplays",
		player_start, Vector3(3.8, 1.4, 3.8), data_display_meshes, "data_displays", 1.9)

	# Drink machine.
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	if not drink_cells.is_empty():
		var drink_world := _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)
		_add_drink_machine_visual(env_node, drink_world)

	if not use_imported_room_lighting:
		_ensure_directional_light(env_node)

		_ensure_omni_light(
			env_node,
			"DeskLight",
			_placement_or_position("DeskLight", Vector3(player_start.x, 2.5, player_start.z)),
			Color(0.9, 0.75, 0.5),
			2.0,
			6.0
		)

		_ensure_omni_light(
			env_node,
			"DataLight",
			_placement_or_position("DataLight", Vector3(player_start.x, 2.0, player_start.z)),
			Color(0.3, 0.6, 0.8),
			1.0,
			4.0
		)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK if use_imported_room_lighting else Color(0.06, 0.05, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK if use_imported_room_lighting else Color(0.4, 0.35, 0.28)
	env.ambient_light_energy = 0.0 if use_imported_room_lighting else 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	we.environment = env
	env_node.add_child(we)

func _apply_graybox_visibility() -> void:
	if show_graybox_room:
		return
	for child in _renderer.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

func _ensure_directional_light(parent: Node3D) -> DirectionalLight3D:
	var scene_light := _placement_node("WarmDirectionalLight") as DirectionalLight3D
	if scene_light != null:
		return scene_light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "WarmDirectionalLight"
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_color = Color(0.95, 0.85, 0.7)
	dir_light.light_energy = 0.7
	dir_light.shadow_enabled = true
	parent.add_child(dir_light)
	return dir_light

func _ensure_omni_light(
		parent: Node3D,
		light_name: String,
		fallback_position: Vector3,
		light_color: Color,
		light_energy: float,
		omni_range: float
	) -> OmniLight3D:
	var scene_light := _placement_node(light_name) as OmniLight3D
	if scene_light != null:
		return scene_light
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _local_for_parent(parent, fallback_position)
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = omni_range
	parent.add_child(light)
	return light

func _add_desk(parent: Node3D, pos: Vector3) -> void:
	var meshes: Array = []
	# Desktop surface
	var desk := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(2.0, 0.08, 1.0)
	desk.mesh = db
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.18, 0.14, 0.1)
	dm.roughness = 0.3
	desk.material_override = dm
	desk.position = pos + Vector3(0, 0.75, 0)
	parent.add_child(desk)
	meshes.append(desk)

	for x in [-0.8, 0.8]:
		for z in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.75, 0.06)
			leg.mesh = lb
			leg.material_override = dm
			leg.position = pos + Vector3(x, 0.375, z)
			parent.add_child(leg)
			meshes.append(leg)

	# Chair.
	var chair := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.25
	cm.height = 0.08
	chair.mesh = cm
	var chair_mat := StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.2, 0.15, 0.12)
	chair.material_override = chair_mat
	chair.position = pos + Vector3(0, 0.5, -0.7)
	parent.add_child(chair)
	meshes.append(chair)

	_create_graybox_outline_target(parent, "RoomTargetDesk",
		pos + Vector3(0.0, 0.75, -0.1), Vector3(2.4, 1.2, 1.8), meshes, "desk", 1.45)

func _create_holo_display(pos: Vector3) -> MeshInstance3D:
	var display := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.8, 0.5, 0.02)
	display.mesh = pb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.3, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.4, 0.55)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	display.material_override = mat
	display.position = pos
	return display

func _add_drink_machine_visual(parent: Node3D, pos: Vector3) -> void:
	var meshes: Array = []
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.8, 1.8, 0.6)
	body.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.18, 0.15)
	body.material_override = bm
	body.position = pos + Vector3(0, 0.9, 0)
	parent.add_child(body)
	meshes.append(body)

	var screen := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.5, 0.3, 0.02)
	screen.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.2, 0.5, 0.3, 0.9)
	sm.emission_enabled = true
	sm.emission = Color(0.15, 0.4, 0.25)
	sm.emission_energy_multiplier = 1.0
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = sm
	screen.position = pos + Vector3(0, 1.4, -0.32)
	parent.add_child(screen)
	meshes.append(screen)

	var lbl := Label3D.new()
	lbl.text = "DRINKS"
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.4, 0.7, 0.5, 0.7)
	lbl.position = pos + Vector3(0, 1.75, -0.32)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

	_create_graybox_outline_target(parent, "RoomTargetDrinkMachine",
		pos + Vector3(0.0, 0.95, 0.0), Vector3(1.2, 2.1, 1.0), meshes, "drink_machine", 1.2)

# --- Decorations ---

func _build_decorations() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	# Astrocyte process fibers branch across the ceiling,
	# representing the star-shaped processes astrocytes extend through tissue
	var fiber_color := Color(0.12, 0.25, 0.35, 0.6)
	var fiber_mat := StandardMaterial3D.new()
	fiber_mat.albedo_color = fiber_color
	fiber_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fiber_mat.emission_enabled = true
	fiber_mat.emission = Color(0.08, 0.18, 0.28)
	fiber_mat.emission_energy_multiplier = 0.6
	var player_start := _placement_or_grid("DataMotesCenter", Vector2i(3, 4), 1.8)
	for i in range(7):
		var angle := i * TAU / 7.0 + 0.3
		var length := 2.5 + fmod(i * 1.7, 1.5)
		var fiber := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.04
		cm.height = length
		fiber.mesh = cm
		fiber.material_override = fiber_mat
		fiber.position = Vector3(
			player_start.x + cos(angle) * 1.0,
			2.7,
			player_start.z + sin(angle) * 1.0
		)
		fiber.rotation = Vector3(0, angle, PI / 2.0 + (i % 3) * 0.15)
		env_node.add_child(fiber)

	# Nutrient conduits.
	var conduit_mat := StandardMaterial3D.new()
	conduit_mat.albedo_color = Color(0.15, 0.3, 0.2, 0.7)
	conduit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	conduit_mat.emission_enabled = true
	conduit_mat.emission = Color(0.1, 0.25, 0.15)
	conduit_mat.emission_energy_multiplier = 1.0
	var conduit1 := MeshInstance3D.new()
	var cc1 := CylinderMesh.new()
	cc1.top_radius = 0.06
	cc1.bottom_radius = 0.06
	cc1.height = 14.0
	conduit1.mesh = cc1
	conduit1.material_override = conduit_mat
	conduit1.position = Vector3(5, 2.6, _grid.height * _grid.cell_size - 0.3)
	conduit1.rotation.z = PI / 2.0
	env_node.add_child(conduit1)
	var conduit2 := MeshInstance3D.new()
	var cc2 := CylinderMesh.new()
	cc2.top_radius = 0.05
	cc2.bottom_radius = 0.05
	cc2.height = 7.0
	conduit2.mesh = cc2
	conduit2.material_override = conduit_mat
	conduit2.position = Vector3(0.3, 2.4, 4.5)
	conduit2.rotation.x = PI / 2.0
	env_node.add_child(conduit2)

	# Neurotransmitter readout panels.
	var panel_data := [
		{"pos": Vector3(1.5, 1.6, 0.35), "text": "GABA  42.1", "color": Color(0.2, 0.5, 0.3)},
		{"pos": Vector3(3.5, 1.8, 0.35), "text": "GLU   18.7", "color": Color(0.5, 0.35, 0.2)},
		{"pos": Vector3(5.5, 1.5, 0.35), "text": "K+   4.2mM", "color": Color(0.3, 0.3, 0.55)},
	]
	for pd in panel_data:
		var panel := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(1.0, 0.5, 0.02)
		panel.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.05, 0.08, 0.1, 0.85)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.emission_enabled = true
		pm.emission = pd.color * 0.4
		pm.emission_energy_multiplier = 0.8
		panel.material_override = pm
		panel.position = pd.pos
		env_node.add_child(panel)
		var lbl := Label3D.new()
		lbl.text = pd.text
		lbl.font_size = 28
		lbl.pixel_size = 0.008
		lbl.modulate = Color(pd.color, 0.7)
		lbl.position = pd.pos + Vector3(0, 0, -0.02)
		env_node.add_child(lbl)

	# Calcium wave floor strips.
	var wave_mat := StandardMaterial3D.new()
	wave_mat.albedo_color = Color(0.1, 0.2, 0.3, 0.3)
	wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_mat.emission_enabled = true
	wave_mat.emission = Color(0.08, 0.15, 0.25)
	wave_mat.emission_energy_multiplier = 0.5
	wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(4):
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(8.0 + i * 2.0, 0.005, 0.04)
		strip.mesh = sb
		strip.material_override = wave_mat
		strip.position = Vector3(4.0 + i * 0.5, 0.01, 2.0 + i * 1.5)
		strip.rotation.y = 0.1 * i
		env_node.add_child(strip)

# --- Terminal Interactable ---

func _build_terminal() -> void:
	var term_cells := _grid.find_tiles(GridWorld.Tile.TERMINAL)
	var term_pos := Vector3(3, 0, 0)
	if not term_cells.is_empty():
		term_pos = _placement_or_grid("TerminalAnchor", term_cells[0], 0.0)

	if not Engine.is_editor_hint():
		_terminal = preload("res://scenes/game/interactable.tscn").instantiate()
		_terminal.name = "Terminal"
		_terminal.description = "Forecasting Terminal"
		_terminal.apply_interactable_spec("aster.terminal")
		_terminal.position = _local_for_parent(self, _placement_or_position("TerminalInteract", term_pos + Vector3(0, 0.8, 0)))
		add_child(_terminal)
		_terminal.interacted.connect(_on_terminal_interacted)
		_set_room_target_interaction_delegate(find_child("RoomTargetDataDisplays", true, false), _terminal)

	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		_add_desk(env_node, term_pos)
		_set_room_target_interaction_delegate(find_child("RoomTargetDesk", true, false), _terminal)
		_terminal_screen_world = term_pos + Vector3(0, 1.5, 0)
		var display := _create_holo_display(_terminal_screen_world)
		env_node.add_child(display)
		_data_displays.append(display)
		_terminal_screen_lowfi = display
		_terminal_screen_detail = _create_terminal_screen_detail(_terminal_screen_world)
		env_node.add_child(_terminal_screen_detail)

## The detailed screen shown while the terminal is in focus. Placeholder art:
## a brighter framed panel plus a forecast readout, swapped in for the low-fi
## holo display when the player checks the terminal.
func _create_terminal_screen_detail(world_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TerminalScreenDetail"
	root.position = world_pos
	root.visible = false

	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.05)
	panel.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.10, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.34, 0.5)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = mat
	root.add_child(panel)

	var readout := Label3D.new()
	# @placeholder: stand-in forecast readout until the screen art lands.
	readout.text = "FORECAST // BARRIER INTEGRITY\nSECTOR 07   98.2%   NOMINAL\nSECTOR 12   41.6%   WATCH\nTRANSFER LOAD       STABLE"
	readout.font_size = 26
	readout.pixel_size = 0.0038
	readout.modulate = Color(0.6, 0.85, 1.0)
	readout.outline_modulate = Color(0, 0, 0, 0.6)
	readout.outline_size = 6
	readout.position = Vector3(0, 0, 0.02)
	root.add_child(readout)
	return root

# --- Drink Machine Interactable ---

func _build_drink_machine() -> void:
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	var machine_pos := Vector3(8, 0, -3)
	if not drink_cells.is_empty():
		machine_pos = _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)

	if not Engine.is_editor_hint():
		_drink_machine = preload("res://scenes/game/interactable.tscn").instantiate()
		_drink_machine.name = "DrinkMachine"
		_drink_machine.description = "Drink Machine"
		_drink_machine.apply_interactable_spec("aster.drink_machine")
		_drink_machine.position = _local_for_parent(self, _placement_or_position("DrinkMachineInteract", machine_pos + Vector3(0, 0.9, 0)))
		add_child(_drink_machine)
		_drink_machine.interacted.connect(_on_drink_interacted)
		_set_room_target_interaction_delegate(find_child("RoomTargetDrinkMachine", true, false), _drink_machine)

# --- Exploration objects (post-drink, pre-Tag-Day) ---

func _build_exploration_objects() -> void:
	if Engine.is_editor_hint():
		return
	var env: Node3D = _renderer if _renderer else self
	_build_glass_bead_game(env)
	_build_painting_panel(env, Vector2i(6, 1), Vector2i(6, 3), "macabre_teal",
		Color(0.15, 0.38, 0.42), "aster.sim_expand.painting_1.line")
	_build_painting_panel(env, Vector2i(11, 1), Vector2i(11, 3), "hunter_ash",
		Color(0.4, 0.3, 0.18), "aster.sim_expand.painting_2.line")
	_build_awards_shelf(env)
	_build_jstore_shelf(env)
	_build_hallway_exit(env)

func _build_glass_bead_game(parent: Node3D) -> void:
	var bead_cell := Vector2i(7, 5)
	var world := _placement_or_grid("GlassBeadAnchor", bead_cell, 0.0)
	var meshes: Array = []
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.4
	bm.height = 0.12
	base.mesh = bm
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.08, 0.12)
	base_mat.metallic = 0.5
	base_mat.roughness = 0.3
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.15, 0.2, 0.35)
	base_mat.emission_energy_multiplier = 0.4
	base.material_override = base_mat
	base.position = world + Vector3(0, 0.55, 0)
	parent.add_child(base)
	meshes.append(base)
	for i in range(8):
		var bead := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		bead.mesh = sm
		var bead_mat := StandardMaterial3D.new()
		bead_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.8)
		bead_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bead_mat.emission_enabled = true
		bead_mat.emission = Color(0.5, 0.7, 1.0)
		bead_mat.emission_energy_multiplier = 1.2
		bead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bead.material_override = bead_mat
		var angle := i * TAU / 8.0
		bead.position = world + Vector3(cos(angle) * 0.25, 0.9 + sin(angle * 2.0) * 0.08, sin(angle) * 0.25)
		parent.add_child(bead)
		meshes.append(bead)
	var target := _create_graybox_outline_target(parent, "RoomTargetGlassBeadGame",
		world + Vector3(0.0, 0.75, 0.0), Vector3(1.2, 1.1, 1.2), meshes, "glass_bead_game", 1.0)
	var zone := _make_exploration_zone(
		parent, _local_for_parent(parent, _placement_or_position("GlassBeadZoneMarker", world)),
		"GlassBeadZone",
		"aster.sim_expand.glass_bead.line",
		1.4, 0.6
	)
	_set_room_target_interaction_delegate(target, zone)

func _build_painting_panel(parent: Node3D, canvas_cell: Vector2i, zone_cell: Vector2i, zone_name: String, palette: Color, line_key: String) -> void:
	var marker_prefix := _exploration_marker_prefix(zone_name)
	var canvas_world := _placement_or_grid(marker_prefix + "Canvas", canvas_cell, 0.0)
	var panel := MeshInstance3D.new()
	var qb := BoxMesh.new()
	qb.size = Vector3(1.4, 1.0, 0.06)
	panel.mesh = qb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = palette
	pm.roughness = 0.7
	panel.material_override = pm
	# Canvas frame.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.5, 1.1, 0.04)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.06, 0.07)
	frame.material_override = fm
	panel.position = canvas_world + Vector3(0, 1.8, 0.02)
	frame.position = canvas_world + Vector3(0, 1.8, 0.0)
	parent.add_child(frame)
	parent.add_child(panel)
	var target_name := "RoomTarget%sPainting" % marker_prefix
	var target := _create_graybox_outline_target(parent, target_name,
		canvas_world + Vector3(0.0, 1.8, 0.03), Vector3(1.8, 1.35, 0.35), [frame, panel],
		"%s_painting" % zone_name, 0.95)
	var zone_world := _placement_or_grid(marker_prefix + "ZoneMarker", zone_cell, 0.0)
	var zone := _make_exploration_zone(parent, _local_for_parent(parent, zone_world), zone_name + "Zone",
		line_key, 1.4, 0.6)
	_set_room_target_interaction_delegate(target, zone)

func _build_awards_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 2)
	var world := _placement_or_grid("AwardsShelf", shelf_cell, 0.0)
	var meshes: Array = []
	var shelf := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.25, 0.6, 2.0)
	shelf.mesh = sb
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
	shelf_mat.roughness = 0.4
	shelf.material_override = shelf_mat
	shelf.position = world + Vector3(0.6, 1.3, 0)
	parent.add_child(shelf)
	meshes.append(shelf)
	# Plaques.
	for i in range(6):
		var plaque := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.08, 0.22, 0.18)
		plaque.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.55, 0.45, 0.18) if i % 2 == 0 else Color(0.65, 0.65, 0.68)
		pm.metallic = 0.6
		pm.roughness = 0.3
		plaque.material_override = pm
		plaque.position = world + Vector3(0.5, 1.35, -0.7 + i * 0.28)
		parent.add_child(plaque)
		meshes.append(plaque)
	var target := _create_graybox_outline_target(parent, "RoomTargetAwardsShelf",
		world + Vector3(0.55, 1.3, 0.0), Vector3(1.0, 1.2, 2.35), meshes, "awards_shelf", 1.35)
	# Two approach zones.
	var center_zone := _make_exploration_zone(parent, _local_for_parent(parent, _placement_or_position("AwardsCenterZoneMarker", world + Vector3(0, 0, -0.4))),
		"AwardsCenterZone",
		"aster.sim_expand.awards.line",
		0.9, 0.6)
	_make_exploration_zone(parent, _local_for_parent(parent, _placement_or_position("AwardsJournalismZoneMarker", world + Vector3(0, 0, 0.6))),
		"AwardsJournalismZone",
		"aster.sim_expand.awards.journalism_line",
		0.9, 0.6)
	_set_room_target_interaction_delegate(target, center_zone)

func _build_jstore_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 5)
	var world := _placement_or_grid("JStoreShelf", shelf_cell, 0.0)
	var meshes: Array = []
	var shelf := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.25, 1.0, 2.0)
	shelf.mesh = sb
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
	shelf.material_override = shelf_mat
	shelf.position = world + Vector3(0.6, 1.1, 0)
	parent.add_child(shelf)
	meshes.append(shelf)
	# J-store spines.
	var spine_colors := [
		Color(0.15, 0.2, 0.35),
		Color(0.35, 0.18, 0.15),
		Color(0.18, 0.3, 0.2),
		Color(0.3, 0.25, 0.15),
		Color(0.2, 0.2, 0.3),
		Color(0.3, 0.2, 0.25),
	]
	for i in range(10):
		var spine := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.05, 0.4, 0.15)
		spine.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = spine_colors[i % spine_colors.size()]
		spine.material_override = pm
		spine.position = world + Vector3(0.5, 0.9, -0.9 + i * 0.18)
		parent.add_child(spine)
		meshes.append(spine)
	# Empty mugs.
	for i in range(12):
		var mug := MeshInstance3D.new()
		var mb := CylinderMesh.new()
		mb.top_radius = 0.05
		mb.bottom_radius = 0.05
		mb.height = 0.1
		mug.mesh = mb
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.25, 0.2, 0.18)
		mug.material_override = mm
		var row := i / 6
		var col := i % 6
		mug.position = world + Vector3(0.5, 1.7, -0.7 + col * 0.22 + row * 0.05)
		parent.add_child(mug)
		meshes.append(mug)
	var target := _create_graybox_outline_target(parent, "RoomTargetJStoreShelf",
		world + Vector3(0.55, 1.15, 0.0), Vector3(1.0, 1.8, 2.35), meshes, "jstore_shelf", 1.45)
	var main_zone := _make_exploration_sequence_zone(parent, _local_for_parent(parent, _placement_or_position("JStoreMainZoneMarker", world + Vector3(0, 0, -0.4))),
		"JStoreMainZone",
		[
			"aster.sim_expand.bookshelf.line",
			"aster.sim_expand.bookshelf.articles_line",
		],
		0.9, 0.6)
	_set_room_target_interaction_delegate(target, main_zone)

func _build_hallway_exit(parent: Node3D) -> void:
	var world := _placement_or_grid("HallwayExit", HALLWAY_EXIT_CELL, 0.0)
	# Archway frame.
	var arch := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.2, 2.8, 1.2)
	arch.mesh = ab
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.12, 0.1, 0.08)
	arch.material_override = am
	arch.position = world + Vector3(0.6, 1.4, 0)
	parent.add_child(arch)
	_ensure_omni_light(
		parent,
		"HallwayExitLight",
		_placement_or_position("HallwayExitLight", world + Vector3(1.1, 1.8, 0)),
		Color(1.0, 0.85, 0.6),
		1.4,
		4.0
	)
	# Reuses Interactable plumbing for the timed gate.
	var gate := _create_interactable(parent, _local_for_parent(parent, world), "HallwayGate", 2.2, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "aster.hallway_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_hallway_gate = gate

func _exploration_marker_prefix(zone_name: String) -> String:
	match zone_name:
		"macabre_teal":
			return "MacabreTeal"
		"hunter_ash":
			return "HunterAsh"
		_:
			return zone_name
