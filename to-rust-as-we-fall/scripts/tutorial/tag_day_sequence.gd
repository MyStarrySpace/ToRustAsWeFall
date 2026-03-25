@tool
extends Node3D

## Tag Day tutorial sequence. Builds the checkpoint environment and drives
## the scripted events: queue, citizen failure, naturalizer grip, corridor
## walk with Eliot poem, WASD camera pan, neutralization, Aster's clearance.
##
## Event-driven: uses EventScheduler instead of phase-timer dispatch.
## Each step is a function that does its work and schedules the next event.

var _scheduler: EventScheduler
var _current_step := ""

var _player  # CharacterBody3D + player.gd
var _camera  # Camera3D + game_camera.gd
var _dialogue  # CanvasLayer + dialogue_box.gd
var _tutorial_prompt  # CanvasLayer + tutorial_prompt.gd
var _data_overlay: CanvasLayer
var _queue_npcs: Array = []
var _citizen  # Node3D + npc.gd
var _naturalizer_1  # Node3D + npc.gd
var _naturalizer_2  # Node3D + npc.gd
var _scan_station_light: OmniLight3D
var _adjacent_station_light: OmniLight3D

# Queue positions (checkpoint corridor runs along +X)
const QUEUE_START := Vector3(0, 0, 0)
const QUEUE_SPACING := 1.8
const STATION_POS := Vector3(12, 0, 0)
const ADJ_STATION_POS := Vector3(12, 0, -4)

# Naturalizer standing positions (visible from start, flanking the doorway)
const NK_STAND_POS_1 := Vector3(13.2, 0, -5.5)
const NK_STAND_POS_2 := Vector3(14.8, 0, -5.5)

# Corridor waypoints
const CORRIDOR_ENTRANCE := Vector3(14, 0, -8)
const CORRIDOR_A_END := Vector3(14, 0, -16)
const CORRIDOR_B_END := Vector3(24, 0, -17)
const CORRIDOR_C_END := Vector3(24, 0, -25)
const CORRIDOR_D_END := Vector3(19, 0, -27)
const DEAD_END := Vector3(17, 0, -28)

# Base NPC walk speed (modified by fast-forward)
const BASE_NPC_SPEED := 2.0

func _ready() -> void:
	if Engine.is_editor_hint():
		for child in get_children().duplicate():
			child.free()
	_build_environment()
	_build_corridor()
	_build_characters()
	if Engine.is_editor_hint():
		return
	_scheduler = EventScheduler.new()
	_build_ui()
	_start_arrive()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Speed control: hold F for 10x
	var spd := 10.0 if Input.is_key_pressed(KEY_F) else 1.0
	_scheduler.set_speed(spd)
	_dialogue.speed_multiplier = spd

	# Advance scheduler
	_scheduler.advance(delta)

	# Scale NPC movement speeds
	_citizen.move_speed = BASE_NPC_SPEED * spd
	_naturalizer_1.move_speed = BASE_NPC_SPEED * spd
	_naturalizer_2.move_speed = BASE_NPC_SPEED * spd
	for npc in _queue_npcs:
		npc.move_speed = BASE_NPC_SPEED * spd

	# Station light pulse fade
	if _adjacent_station_light.light_energy > 2.1:
		_adjacent_station_light.light_energy = lerpf(
			_adjacent_station_light.light_energy, 2.0, 3.0 * delta
		)

# --- Event-driven steps ---

func _start_arrive() -> void:
	_current_step = "arrive"
	_player.set_move_enabled(false)
	var queue_back := QUEUE_START + Vector3(-QUEUE_SPACING, 0, 0)
	_player.walk_to(queue_back)
	_player.auto_path_complete.connect(_on_arrive_complete, CONNECT_ONE_SHOT)
	DialogueData.say_to(_dialogue, "tag_day.checkpoint_id")

func _on_arrive_complete() -> void:
	_scheduler.schedule_after(0, _start_queue_wait, "queue_wait")

func _start_queue_wait() -> void:
	_current_step = "queue_wait"
	_shuffle_queue_forward()
	_scheduler.schedule_after(4.0, _start_citizen_fails, "citizen_fails")

func _start_citizen_fails() -> void:
	_current_step = "citizen_fails"
	_adjacent_station_light.light_color = Color(0.8, 0.1, 0.05)
	_adjacent_station_light.light_energy = 6.0
	DialogueData.say_to(_dialogue, "tag_day.scan_failed")
	_scheduler.schedule_after(3.0, _start_poem_and_drag, "poem_and_drag")

func _start_poem_and_drag() -> void:
	_current_step = "poem_and_drag"

	# Naturalizers grip the citizen
	DialogueData.say_to(_dialogue, "tag_day.naturalizers_grip")

	# Naturalizers walk to citizen
	_naturalizer_1.walk_to(ADJ_STATION_POS + Vector3(0, 0, -0.6))
	_naturalizer_2.walk_to(ADJ_STATION_POS + Vector3(0, 0, 0.6))

	# After 1.5s: start poem and begin corridor walk simultaneously
	_scheduler.schedule_after(1.5, _begin_corridor_walk, "corridor_walk")

	# Aster advances toward station area
	_player.set_move_enabled(false)
	_player.walk_to(STATION_POS + Vector3(-1.5, 0, 0))

func _begin_corridor_walk() -> void:
	# Queue the poem lines
	DialogueData.say_sequence_to(_dialogue, "tag_day.poem.")

	# Citizen walks the corridor path
	var citizen_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE,
		CORRIDOR_A_END,
		CORRIDOR_B_END,
		CORRIDOR_C_END,
		CORRIDOR_D_END,
		DEAD_END,
	]
	_citizen.walk_path(citizen_path)

	# Naturalizers walk alongside with offsets
	var nk1_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0, 0, -0.6),
		CORRIDOR_A_END + Vector3(0, 0, -0.6),
		CORRIDOR_B_END + Vector3(-0.6, 0, 0),
		CORRIDOR_C_END + Vector3(-0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, -0.6),
		DEAD_END + Vector3(-0.6, 0, 0),
	]
	_naturalizer_1.walk_path(nk1_path)

	var nk2_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0, 0, 0.6),
		CORRIDOR_A_END + Vector3(0, 0, 0.6),
		CORRIDOR_B_END + Vector3(0.6, 0, 0),
		CORRIDOR_C_END + Vector3(0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, 0.6),
		DEAD_END + Vector3(0.6, 0, 0),
	]
	_naturalizer_2.walk_path(nk2_path)

	# When citizen reaches the corridor doorway (waypoint 0), show WASD prompt
	_citizen.waypoint_reached.connect(_on_citizen_waypoint, CONNECT_DEFERRED)

	# When poem finishes, queue the fragments
	_dialogue.dialogue_finished.connect(_on_poem_finished, CONNECT_ONE_SHOT)

func _on_citizen_waypoint(index: int) -> void:
	if index == 0 and _current_step == "poem_and_drag":
		_start_pan_prompt()

func _start_pan_prompt() -> void:
	_current_step = "pan_prompt"
	# Enable camera pan so the player can follow the corridor walk
	_camera.set_pan_enabled(true)
	_camera.set_wasd_pan_enabled(true)
	_camera.max_pan_distance = 40.0
	_tutorial_prompt.show_prompt("WASD — pan camera")

func _on_poem_finished() -> void:
	_start_fragments()

func _start_fragments() -> void:
	_current_step = "fragments"
	_tutorial_prompt.hide_prompt()
	DialogueData.say_sequence_to(_dialogue, "tag_day.fragment.")
	_dialogue.dialogue_finished.connect(_on_fragments_finished, CONNECT_ONE_SHOT)

func _on_fragments_finished() -> void:
	_scheduler.schedule_after(0, _start_neutralization, "neutralization")

func _start_neutralization() -> void:
	_current_step = "neutralization"
	_citizen.stop()
	_naturalizer_1.stop()
	_naturalizer_2.stop()
	# Disconnect waypoint signal
	if _citizen.waypoint_reached.is_connected(_on_citizen_waypoint):
		_citizen.waypoint_reached.disconnect(_on_citizen_waypoint)
	# Fade the citizen out
	_scheduler.schedule_after(1.0, func(): _citizen.fade_out(2.0), "citizen_fade")
	_scheduler.schedule_after(3.5, _start_return_focus, "return_focus")

func _start_return_focus() -> void:
	_current_step = "return_focus"
	DialogueData.say_to(_dialogue, "tag_day.no_field")
	# Disable pan, return camera to Aster
	_camera.set_wasd_pan_enabled(false)
	_camera.set_pan_enabled(false)
	_camera.max_pan_distance = 15.0
	_scheduler.schedule_after(3.0, _start_aster_scans, "aster_scans")

func _start_aster_scans() -> void:
	_current_step = "aster_scans"
	_player.walk_to(STATION_POS)
	_player.auto_path_complete.connect(_on_aster_at_station, CONNECT_ONE_SHOT)

func _on_aster_at_station() -> void:
	_scan_station_light.light_color = Color(0.2, 0.5, 0.9)
	_scan_station_light.light_energy = 4.0
	DialogueData.say_to(_dialogue, "tag_day.scan_passed")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_clearance, "clearance"),
		CONNECT_ONE_SHOT
	)

func _start_clearance() -> void:
	_current_step = "clearance"
	_scan_station_light.light_color = Color(0.15, 0.4, 0.85)
	_scan_station_light.light_energy = 3.0
	DialogueData.say_to(_dialogue, "tag_day.clearance")
	_dialogue.dialogue_finished.connect(_on_sequence_complete, CONNECT_ONE_SHOT)

func _on_sequence_complete() -> void:
	_current_step = "complete"
	get_tree().change_scene_to_file("res://scenes/tutorial/peris_sim.tscn")

# --- Queue ---

func _shuffle_queue_forward() -> void:
	for i in range(_queue_npcs.size()):
		var npc: Node3D = _queue_npcs[i]
		var target_x := STATION_POS.x - ((_queue_npcs.size() - 1 - i) * QUEUE_SPACING)
		npc.walk_to(Vector3(target_x, 0, 0))
	var player_x := STATION_POS.x - (_queue_npcs.size() * QUEUE_SPACING)
	_player.walk_to(Vector3(player_x, 0, 0))

# --- Environment Build ---

func _build_environment() -> void:
	var env_node := Node3D.new()
	env_node.name = "Environment"
	add_child(env_node)

	# Floor
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(32, 0.1, 16)
	floor_mesh.mesh = floor_box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.08, 0.08, 0.1)
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(12, -0.05, -2)
	env_node.add_child(floor_mesh)

	# Floor collision for click-to-move
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(12, -0.01, -2)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(32, 0.02, 16)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	env_node.add_child(floor_body)

	# Walls — main room with doorway opening at x=13-15, z=-8
	# Back wall left segment (x=-4 to x=13)
	_add_wall(env_node, Vector3(4.5, 1.5, -8), Vector3(17, 3, 0.3))
	# Back wall right segment (x=15 to x=28)
	_add_wall(env_node, Vector3(21.5, 1.5, -8), Vector3(13, 3, 0.3))
	# Front wall
	_add_wall(env_node, Vector3(12, 1.5, 6), Vector3(32, 3, 0.3))
	# Left wall
	_add_wall(env_node, Vector3(-4, 1.5, -2), Vector3(0.3, 3, 14))
	# Right wall
	_add_wall(env_node, Vector3(28, 1.5, -2), Vector3(0.3, 3, 14))

	# Scan station booths
	_add_booth(env_node, STATION_POS, "7-B.1")
	_add_booth(env_node, ADJ_STATION_POS, "7-B.2")

	# Queue lane markers
	for i in range(6):
		var marker := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.05, 0.02, 1.2)
		marker.mesh = line
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.15, 0.15, 0.2)
		marker.material_override = line_mat
		marker.position = Vector3(STATION_POS.x - i * QUEUE_SPACING, 0.01, 0)
		env_node.add_child(marker)

	# Ceiling panels
	for i in range(4):
		var ceiling_light := MeshInstance3D.new()
		var cl_box := BoxMesh.new()
		cl_box.size = Vector3(4, 0.05, 1.5)
		ceiling_light.mesh = cl_box
		var cl_mat := StandardMaterial3D.new()
		cl_mat.albedo_color = Color(0.6, 0.6, 0.65)
		cl_mat.emission_enabled = true
		cl_mat.emission = Color(0.5, 0.5, 0.55)
		cl_mat.emission_energy_multiplier = 0.5
		ceiling_light.material_override = cl_mat
		ceiling_light.position = Vector3(3 + i * 7, 2.95, -1)
		env_node.add_child(ceiling_light)

	# Clinical fluorescent directional light
	var dir_light := DirectionalLight3D.new()
	dir_light.transform = Transform3D(
		Basis(Vector3(1, 0, 0), -PI / 3.0),
		Vector3(0, 8, 0)
	)
	dir_light.light_color = Color(0.75, 0.75, 0.8)
	dir_light.light_energy = 0.6
	dir_light.shadow_enabled = true
	env_node.add_child(dir_light)

	# Ambient fill
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.1
	world_env.environment = env
	env_node.add_child(world_env)

	# Station lights
	_scan_station_light = OmniLight3D.new()
	_scan_station_light.position = STATION_POS + Vector3(0, 2, 0)
	_scan_station_light.light_color = Color(0.3, 0.3, 0.35)
	_scan_station_light.light_energy = 1.5
	_scan_station_light.omni_range = 4.0
	env_node.add_child(_scan_station_light)

	_adjacent_station_light = OmniLight3D.new()
	_adjacent_station_light.position = ADJ_STATION_POS + Vector3(0, 2, 0)
	_adjacent_station_light.light_color = Color(0.3, 0.3, 0.35)
	_adjacent_station_light.light_energy = 1.5
	_adjacent_station_light.omni_range = 4.0
	env_node.add_child(_adjacent_station_light)

# --- Corridor Build ---

func _build_corridor() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	var floor_color := Color(0.06, 0.06, 0.08)
	var wall_color := Color(0.12, 0.12, 0.15)

	# Segment A: straight away from doorway (x=13-15, z=-8 to z=-16)
	_add_corridor_floor(env_node, Vector3(14, -0.05, -12), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(14, -0.01, -12), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(12.85, 1.5, -12), Vector3(0.3, 3, 8))  # Left wall
	_add_wall(env_node, Vector3(15.15, 1.5, -12), Vector3(0.3, 3, 8))  # Right wall

	# Segment B: turn right (x=15-25, z=-16 to z=-18)
	_add_corridor_floor(env_node, Vector3(20, -0.05, -17), Vector3(10, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(20, -0.01, -17), Vector3(10, 0.02, 2))
	_add_wall(env_node, Vector3(20, 1.5, -15.85), Vector3(10, 3, 0.3))  # Near wall
	_add_wall(env_node, Vector3(20, 1.5, -18.15), Vector3(10, 3, 0.3))  # Far wall

	# Segment C: turn away again (x=23-25, z=-18 to z=-26)
	_add_corridor_floor(env_node, Vector3(24, -0.05, -22), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(24, -0.01, -22), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(22.85, 1.5, -22), Vector3(0.3, 3, 8))  # Left wall
	_add_wall(env_node, Vector3(25.15, 1.5, -22), Vector3(0.3, 3, 8))  # Right wall

	# Segment D: turn left into dead-end (x=16-23, z=-26 to z=-28)
	_add_corridor_floor(env_node, Vector3(19.5, -0.05, -27), Vector3(7, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(19.5, -0.01, -27), Vector3(7, 0.02, 2))
	_add_wall(env_node, Vector3(19.5, 1.5, -25.85), Vector3(7, 3, 0.3))  # Near wall
	_add_wall(env_node, Vector3(19.5, 1.5, -28.15), Vector3(7, 3, 0.3))  # Far wall

	# Dead end alcove (x=16-18, z=-28 to z=-30)
	_add_corridor_floor(env_node, Vector3(17, -0.05, -29), Vector3(2, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(17, -0.01, -29), Vector3(2, 0.02, 2))
	_add_wall(env_node, Vector3(15.85, 1.5, -29), Vector3(0.3, 3, 2))   # Left wall
	_add_wall(env_node, Vector3(18.15, 1.5, -29), Vector3(0.3, 3, 2))   # Right wall
	_add_wall(env_node, Vector3(17, 1.5, -30.15), Vector3(2, 3, 0.3))   # Back wall

	# Corridor ceiling panels (dimmer emission than main room)
	_add_corridor_ceiling(env_node, Vector3(14, 2.95, -12), Vector3(1.5, 0.05, 3), 0.3)
	_add_corridor_ceiling(env_node, Vector3(20, 2.95, -17), Vector3(4, 0.05, 1.5), 0.2)
	_add_corridor_ceiling(env_node, Vector3(24, 2.95, -22), Vector3(1.5, 0.05, 3), 0.15)
	_add_corridor_ceiling(env_node, Vector3(17, 2.95, -28), Vector3(1.5, 0.05, 1.5), 0.1)

	# Corridor lights — progressively dimmer and redder
	_add_corridor_light(env_node, Vector3(14, 2.5, -12), 0.8, Color(0.3, 0.2, 0.15))
	_add_corridor_light(env_node, Vector3(20, 2.5, -17), 0.6, Color(0.25, 0.15, 0.1))
	_add_corridor_light(env_node, Vector3(24, 2.5, -22), 0.4, Color(0.2, 0.12, 0.08))
	_add_corridor_light(env_node, Vector3(17, 2.5, -29), 0.3, Color(0.15, 0.08, 0.05))

func _add_corridor_floor(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

func _add_corridor_collision(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)

func _add_corridor_ceiling(parent: Node3D, pos: Vector3, size: Vector3, emission_energy: float) -> void:
	var ceiling := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = size
	ceiling.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.5, 0.5, 0.55)
	cm.emission_enabled = true
	cm.emission = Color(0.4, 0.4, 0.45)
	cm.emission_energy_multiplier = emission_energy
	ceiling.material_override = cm
	ceiling.position = pos
	parent.add_child(ceiling)

func _add_corridor_light(parent: Node3D, pos: Vector3, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	parent.add_child(light)

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.15)
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

func _add_booth(parent: Node3D, pos: Vector3, label_text: String) -> void:
	for z_off in [-0.6, 0.6]:
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.15, 2.5, 0.15)
		pillar.mesh = pbox
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.18, 0.18, 0.22)
		pillar.material_override = pmat
		pillar.position = pos + Vector3(0, 1.25, z_off)
		parent.add_child(pillar)

	var bar := MeshInstance3D.new()
	var barmesh := BoxMesh.new()
	barmesh.size = Vector3(0.15, 0.15, 1.35)
	bar.mesh = barmesh
	var barmat := StandardMaterial3D.new()
	barmat.albedo_color = Color(0.18, 0.18, 0.22)
	bar.material_override = barmat
	bar.position = pos + Vector3(0, 2.5, 0)
	parent.add_child(bar)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	lbl.position = pos + Vector3(0, 2.2, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

# --- Character Build ---

func _build_characters() -> void:
	var chars_node := Node3D.new()
	chars_node.name = "Characters"
	add_child(chars_node)

	# Player (Aster)
	_player = _create_player()
	_player.position = Vector3(-3, 0.5, 0)
	chars_node.add_child(_player)

	# Queue NPCs (citizens ahead of Aster)
	for i in range(4):
		var npc := _create_npc("CZN-%03d" % (400 + i), Color(0.4, 0.4, 0.45))
		npc.position = Vector3(STATION_POS.x - (3 - i) * QUEUE_SPACING, 0, 0)
		chars_node.add_child(npc)
		_queue_npcs.append(npc)

	# The citizen who will fail (at adjacent station)
	_citizen = _create_npc("CZN-217", Color(0.5, 0.45, 0.4))
	_citizen.position = ADJ_STATION_POS
	chars_node.add_child(_citizen)

	# Naturalizers (visible from start, standing near the back wall)
	_naturalizer_1 = _create_npc("NK-01", Color(0.85, 0.85, 0.88))
	_naturalizer_1.position = NK_STAND_POS_1
	chars_node.add_child(_naturalizer_1)

	_naturalizer_2 = _create_npc("NK-02", Color(0.85, 0.85, 0.88))
	_naturalizer_2.position = NK_STAND_POS_2
	chars_node.add_child(_naturalizer_2)

	# Camera (gameplay only)
	if not Engine.is_editor_hint():
		var cam := Camera3D.new()
		cam.name = "GameCamera"
		cam.set_script(preload("res://scripts/game/game_camera.gd"))
		add_child(cam)
		_camera = cam
		_camera.target = _player
		_camera.follow_offset = Vector3(0, 10, 7)
		_camera.set_pan_enabled(false)

func _create_player() -> CharacterBody3D:
	var player := preload("res://scenes/game/player_character.tscn").instantiate()
	player.name = "Aster"
	player.color = Color(0.29, 0.62, 1.0)
	player.get_node("Label3D").text = "ASTER"
	player.get_node("Label3D").modulate = Color(0.29, 0.62, 1.0, 0.8)
	return player

func _create_npc(npc_name: String, npc_color: Color) -> Node3D:
	var npc := Node3D.new()
	npc.name = npc_name.replace("-", "_")
	npc.set_script(preload("res://scripts/game/npc.gd"))
	npc.display_name = npc_name
	npc.color = npc_color
	return npc

# --- UI Build ---

func _build_ui() -> void:
	var ui := preload("res://scenes/game/tutorial_ui.tscn").instantiate()
	add_child(ui)
	_dialogue = ui.get_node("DialogueBox")
	_tutorial_prompt = ui.get_node("TutorialPrompt")

	# Data overlay
	_data_overlay = CanvasLayer.new()
	_data_overlay.layer = 9
	add_child(_data_overlay)

	var data_label := Label.new()
	data_label.text = "CHECKPOINT 7-B  //  ATMOSPHERIC Fe: 12.4 ppb  //  TAG QUEUE: ACTIVE"
	data_label.add_theme_font_size_override("font_size", 11)
	data_label.add_theme_color_override("font_color", Color(0.25, 0.4, 0.6, 0.5))
	data_label.position = Vector2(12, 8)
	_data_overlay.add_child(data_label)

	var data_label2 := Label.new()
	data_label2.text = "AST-PERCEPT: DATA-MAP  //  STRUCT: GEOMETRY  //  BIO: DATAPOINT"
	data_label2.add_theme_font_size_override("font_size", 10)
	data_label2.add_theme_color_override("font_color", Color(0.2, 0.35, 0.5, 0.35))
	data_label2.position = Vector2(12, 24)
	_data_overlay.add_child(data_label2)
