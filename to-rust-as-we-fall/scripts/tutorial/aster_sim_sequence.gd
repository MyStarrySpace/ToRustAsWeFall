extends Node3D

## Aster's simulation tutorial. Teaches movement, interaction, ATP.
## Establishes Aster's character, introduces Ron, ends with Tag Day notification.
##
## Event-driven: uses EventScheduler instead of phase-timer dispatch.
## Each step is a function that does its work and schedules the next event.

var _scheduler: EventScheduler
var _current_step := ""  ## Replaces Phase enum — SimRunner string-matches this
var _has_moved := false
var _has_drunk := false
var _fade_start_tick := 0.0  ## For continuous fade interpolation

var _player
var _camera
var _dialogue
var _tutorial_prompt
var _ron
var _terminal  # Interactable — forecasting terminal
var _drink_machine  # Interactable — drink machine
var _atp_bar: ProgressBar
var _atp_label: Label
var _fade_rect: ColorRect
var _thought_label: Label  # Aster's inner thoughts

# Grid system
var _grid: GridWorld
var _renderer: GridRenderer

# Central data authority
var _game_state: GameState

# Environment
var _data_displays: Array[MeshInstance3D] = []

# ATP simulation
var _atp := 72.0  # Start slightly below max to show the bar clearly
const ATP_MAX := 100.0

func _ready() -> void:
	_scheduler = EventScheduler.new()
	_build_environment()
	_build_characters()
	_build_terminal()
	_build_drink_machine()
	_build_ui()
	_start_fade_in()

func _process(delta: float) -> void:
	# Fast-forward control: hold X for 10x speed
	var spd := 10.0 if Input.is_key_pressed(KEY_X) else 1.0
	_scheduler.set_speed(spd)
	_dialogue.speed_multiplier = spd
	_terminal.speed_multiplier = spd
	_drink_machine.speed_multiplier = spd

	# Advance scheduler (converts real delta to ticks via speed)
	_scheduler.advance(delta)

	# Advance GameState (NPC movement at speed)
	_game_state.tick(delta * spd)

	# Per-frame visual updates
	_update_atp_display()
	_update_fades()
	_update_show_terminal()

	# Animate floating data displays
	for i in range(_data_displays.size()):
		var d := _data_displays[i]
		d.position.y = 1.8 + sin(Time.get_ticks_msec() * 0.001 + i * 1.5) * 0.08
		d.rotation.y += delta * 0.15

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	var elapsed := _scheduler.get_current_tick() - _fade_start_tick
	if _current_step == "fade_in":
		var alpha := 1.0 - clampf(elapsed / 2.0, 0.0, 1.0)
		_fade_rect.color.a = alpha
	elif _current_step == "transition_out":
		var alpha := clampf(elapsed / 2.0, 0.0, 1.0)
		_fade_rect.color = Color(0.05, 0.03, 0.01, alpha)

func _update_show_terminal() -> void:
	if _current_step == "show_terminal" and not _has_moved and _player.is_moving():
		_has_moved = true
		_terminal.hide_tutorial_label()

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_current_step = "fade_in"
	_fade_rect.color = Color(0, 0, 0, 1)
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _start_working, "working")

func _start_working() -> void:
	_current_step = "working"
	_show_thought(DialogueData.text("aster_sim.working.thought"))
	_scheduler.schedule_after(4.0, _start_ron_approaches, "ron_approaches")

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
	DialogueData.say_to(_dialogue, "aster_sim.aster.forecast")
	DialogueData.say_to(_dialogue, "aster_sim.aster.show")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_show_terminal, "show_terminal"),
		CONNECT_ONE_SHOT
	)

func _start_show_terminal() -> void:
	_current_step = "show_terminal"
	_terminal.show_tutorial_label()
	_player.set_move_enabled(true)
	# Terminal interaction triggers _on_terminal_interacted (signal-driven)

func _on_terminal_interacted() -> void:
	if _current_step == "show_terminal" or _current_step == "terminal_data":
		_scheduler.cancel_tag("drink_redirect")  # Clean up any pending
		_start_terminal_data()

func _start_terminal_data() -> void:
	_current_step = "terminal_data"
	DialogueData.say_to(_dialogue, "aster_sim.system.cleaned")
	_scheduler.schedule_after(3.0, _start_ron_drinks, "ron_drinks")

func _start_ron_drinks() -> void:
	_current_step = "ron_drinks"
	DialogueData.say_to(_dialogue, "aster_sim.ron.drinks")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_walk_to_drink, "walk_to_drink"),
		CONNECT_ONE_SHOT
	)

func _start_walk_to_drink() -> void:
	_current_step = "walk_to_drink"
	_drink_machine.show_tutorial_label()
	# Redirect hint if player hasn't drunk after 8 seconds
	_scheduler.schedule_after(8.0, _show_drink_redirect, "drink_redirect")

func _show_drink_redirect() -> void:
	if not _has_drunk and _current_step == "walk_to_drink":
		_show_thought(DialogueData.text("aster_sim.drink_redirect.thought"))

func _on_drink_interacted() -> void:
	if _has_drunk:
		return
	_has_drunk = true
	_scheduler.cancel_tag("drink_redirect")
	_start_drink()

func _start_drink() -> void:
	_current_step = "drink"
	_atp = ATP_MAX
	_hide_thought()
	_scheduler.schedule_after(2.0, _start_ron_move_fast, "ron_move_fast")

func _start_ron_move_fast() -> void:
	_current_step = "ron_move_fast"
	DialogueData.say_to(_dialogue, "aster_sim.ron.move_fast")
	_scheduler.schedule_after(3.0, _start_tag_notify, "tag_notify")

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
	get_tree().change_scene_to_file("res://scenes/tutorial/tag_day.tscn")

# --- Thoughts (Aster's inner monologue) ---

func _show_thought(text: String) -> void:
	_thought_label.text = text
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.7, 0.5)

func _hide_thought() -> void:
	var tween := create_tween()
	tween.tween_property(_thought_label, "modulate:a", 0.0, 0.5)

func _update_atp_display() -> void:
	_atp_bar.value = _atp
	_atp_label.text = "ATP  %d%%" % int(_atp)

# --- Environment ---

func _build_environment() -> void:
	# Load grid from level data
	_grid = GridWorld.new()
	_grid.load_from_json("res://data/levels/aster_sim.json")

	# Grid renderer — creates floor collision + tile meshes
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

	# Decorative elements on top of grid
	var env_node := _renderer

	# Floating data motes near Aster's starting area
	var player_start := _grid.grid_to_world(Vector2i(3, 4))
	for i in range(3):
		var angle := i * TAU / 3.0
		var pos := Vector3(player_start.x + cos(angle) * 1.5, 1.8, player_start.z + sin(angle) * 1.5)
		var display := _create_holo_display(pos)
		env_node.add_child(display)
		_data_displays.append(display)

	# Drink machine visual — position derived from grid
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	if not drink_cells.is_empty():
		var drink_world := _grid.grid_to_world(drink_cells[0])
		_add_drink_machine_visual(env_node, drink_world)

	# Warm ambient lighting
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_color = Color(0.95, 0.85, 0.7)
	dir_light.light_energy = 0.7
	dir_light.shadow_enabled = true
	env_node.add_child(dir_light)

	# Warm point light near desk
	var desk_light := OmniLight3D.new()
	desk_light.position = Vector3(player_start.x, 2.5, player_start.z)
	desk_light.light_color = Color(0.9, 0.75, 0.5)
	desk_light.light_energy = 2.0
	desk_light.omni_range = 6.0
	env_node.add_child(desk_light)

	# Cyan accent light on data displays
	var data_light := OmniLight3D.new()
	data_light.position = Vector3(player_start.x, 2.0, player_start.z)
	data_light.light_color = Color(0.3, 0.6, 0.8)
	data_light.light_energy = 1.0
	data_light.omni_range = 4.0
	env_node.add_child(data_light)

	# World environment — warm simulation
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.35, 0.28)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	we.environment = env
	env_node.add_child(we)

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	parent.add_child(m)

func _add_desk(parent: Node3D, pos: Vector3) -> void:
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

	# Legs
	for x in [-0.8, 0.8]:
		for z in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.75, 0.06)
			leg.mesh = lb
			leg.material_override = dm
			leg.position = pos + Vector3(x, 0.375, z)
			parent.add_child(leg)

	# Chair (simple cylinder)
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
	# Body
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.8, 1.8, 0.6)
	body.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.18, 0.15)
	body.material_override = bm
	body.position = pos + Vector3(0, 0.9, 0)
	parent.add_child(body)

	# Screen glow
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

	# Label
	var lbl := Label3D.new()
	lbl.text = "DRINKS"
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.4, 0.7, 0.5, 0.7)
	lbl.position = pos + Vector3(0, 1.75, -0.32)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

# --- Characters ---

func _build_characters() -> void:
	# Create GameState — central data authority
	_game_state = GameState.new()
	_game_state.grid = _grid

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Player (Aster) — position derived from grid (cell 3,4 = near flora)
	_player = _create_player()
	var player_world := _grid.grid_to_world(Vector2i(3, 4))
	_player.position = Vector3(player_world.x, 0.5, player_world.z)
	_player.grid_world = _grid
	_player.game_state = _game_state
	_player.char_id = "aster"
	# Collision layer 2 (characters), mask 2 (other characters only)
	_player.collision_layer = 2
	_player.collision_mask = 2
	chars.add_child(_player)

	# Register Aster in GameState
	_game_state.register_character("aster", _player.position, _player.move_speed, {"atp": _atp})

	# Ron — approaches from behind/side (cell 2,6)
	_ron = Node3D.new()
	_ron.name = "Ron"
	_ron.set_script(preload("res://scripts/game/npc.gd"))
	_ron.display_name = "RON"
	_ron.color = Color(0.7, 0.6, 0.45)
	var ron_world := _grid.grid_to_world(Vector2i(2, 6))
	_ron.position = Vector3(ron_world.x, 0, ron_world.z)
	_ron.grid_world = _grid
	chars.add_child(_ron)

	# Camera
	var cam := Camera3D.new()
	cam.name = "GameCamera"
	cam.set_script(preload("res://scripts/game/game_camera.gd"))
	add_child(cam)
	_camera = cam
	_camera.target = _player
	_camera.follow_offset = Vector3(0, 8, 6)
	_camera.set_pan_enabled(false)

func _create_player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "Aster"

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.25
	cs.height = 1.0
	col.shape = cs
	col.position.y = 0.5
	player.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.position.y = 0.5
	player.add_child(mesh)

	var label := Label3D.new()
	label.name = "Label3D"
	label.text = "ASTER"
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = Color(0.29, 0.62, 1.0, 0.8)
	label.position.y = 1.3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player.add_child(label)

	player.set_script(preload("res://scripts/game/player.gd"))
	return player

# --- Terminal Interactable ---

func _build_terminal() -> void:
	# Derive terminal position from grid tile type
	var term_cells := _grid.find_tiles(GridWorld.Tile.TERMINAL)
	var term_pos := Vector3(3, 0, 0)
	if not term_cells.is_empty():
		term_pos = _grid.grid_to_world(term_cells[0])

	_terminal = Area3D.new()
	_terminal.name = "Terminal"
	_terminal.set_script(preload("res://scripts/game/interactable.gd"))
	_terminal.description = "Forecasting Terminal"
	_terminal.one_shot = true
	_terminal.dwell_time = 1.0
	_terminal.tutorial_label = "Click"
	_terminal.position = term_pos + Vector3(0, 0.8, 0)
	_terminal.collision_layer = 4  # Interactables
	_terminal.collision_mask = 2   # Detect characters

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	_terminal.add_child(col)

	add_child(_terminal)
	_terminal.interacted.connect(_on_terminal_interacted)

	# Terminal visual — desk with floating screen
	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		_add_desk(env_node, term_pos)
		var display := _create_holo_display(term_pos + Vector3(0, 1.5, 0))
		env_node.add_child(display)
		_data_displays.append(display)

# --- Drink Machine Interactable ---

func _build_drink_machine() -> void:
	# Derive drink machine position from grid tile type
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	var machine_pos := Vector3(8, 0, -3)
	if not drink_cells.is_empty():
		machine_pos = _grid.grid_to_world(drink_cells[0])

	_drink_machine = Area3D.new()
	_drink_machine.name = "DrinkMachine"
	_drink_machine.set_script(preload("res://scripts/game/interactable.gd"))
	_drink_machine.description = "Drink Machine"
	_drink_machine.one_shot = true
	_drink_machine.tutorial_label = DialogueData.text("aster_sim.drink_label")
	_drink_machine.position = machine_pos + Vector3(0, 0.9, 0)
	_drink_machine.collision_layer = 4  # Interactables
	_drink_machine.collision_mask = 2   # Detect characters

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	_drink_machine.add_child(col)

	add_child(_drink_machine)
	_drink_machine.interacted.connect(_on_drink_interacted)

# --- UI ---

func _build_ui() -> void:
	# Dialogue box
	var dlg := CanvasLayer.new()
	dlg.name = "DialogueBox"
	dlg.set_script(preload("res://scripts/game/dialogue_box.gd"))
	add_child(dlg)
	_dialogue = dlg

	# Tutorial prompt
	var tp := CanvasLayer.new()
	tp.name = "TutorialPrompt"
	tp.set_script(preload("res://scripts/game/tutorial_prompt.gd"))
	add_child(tp)
	_tutorial_prompt = tp

	# Fade overlay
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)

	# ATP bar — top right
	var atp_layer := CanvasLayer.new()
	atp_layer.layer = 10
	add_child(atp_layer)

	var atp_container := HBoxContainer.new()
	atp_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	atp_container.offset_left = -180
	atp_container.offset_top = 12
	atp_container.offset_right = -12
	atp_container.offset_bottom = 32
	atp_container.add_theme_constant_override("separation", 8)
	atp_layer.add_child(atp_container)

	_atp_label = Label.new()
	_atp_label.add_theme_font_size_override("font_size", 12)
	_atp_label.add_theme_color_override("font_color", Color(0.3, 0.7, 0.4, 0.8))
	_atp_label.custom_minimum_size.x = 70
	atp_container.add_child(_atp_label)

	_atp_bar = ProgressBar.new()
	_atp_bar.min_value = 0
	_atp_bar.max_value = ATP_MAX
	_atp_bar.value = _atp
	_atp_bar.show_percentage = false
	_atp_bar.custom_minimum_size = Vector2(90, 16)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.08, 0.1)
	bar_style.set_corner_radius_all(2)
	_atp_bar.add_theme_stylebox_override("background", bar_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.6, 0.35)
	fill_style.set_corner_radius_all(2)
	_atp_bar.add_theme_stylebox_override("fill", fill_style)
	atp_container.add_child(_atp_bar)

	# Thought display (Aster's inner monologue — italic, center screen)
	var thought_layer := CanvasLayer.new()
	thought_layer.layer = 11
	add_child(thought_layer)
	_thought_label = Label.new()
	_thought_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thought_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_thought_label.offset_top = 50
	_thought_label.offset_left = -300
	_thought_label.offset_right = 300
	_thought_label.add_theme_font_size_override("font_size", 14)
	_thought_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_thought_label.modulate.a = 0.0
	_thought_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thought_layer.add_child(_thought_label)
