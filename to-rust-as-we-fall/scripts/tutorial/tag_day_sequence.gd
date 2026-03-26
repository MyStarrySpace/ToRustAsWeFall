@tool
extends TutorialSequence

## Tag Day tutorial sequence. Builds the checkpoint environment and drives
## the scripted events: queue, citizen failure, naturalizer grip, corridor
## walk with Eliot poem, WASD camera pan, neutralization, Aster's clearance.

var _data_overlay: CanvasLayer
var _bystanders: Array = []
var _citizen  # Node3D + npc.gd — at device to Aster's right
var _naturalizer_1  # Node3D + npc.gd
var _naturalizer_2  # Node3D + npc.gd
var _citizen_light: OmniLight3D  # Light above citizen's device

# Psy-Knapse device positions — row along +X, everyone at their own device
const DEVICE_SPACING := 2.2
const ASTER_DEVICE_POS := Vector3(6, 0, 0)
const CITIZEN_DEVICE_POS := Vector3(6 + DEVICE_SPACING, 0, 0)  # To Aster's right

# Naturalizer standing positions (near the back wall, out of the way)
const NK_STAND_POS_1 := Vector3(13.2, 0, -5.5)
const NK_STAND_POS_2 := Vector3(14.8, 0, -5.5)

# Corridor waypoints
const CORRIDOR_ENTRANCE := Vector3(14, 0, -8)
const CORRIDOR_A_END := Vector3(14, 0, -16)
const CORRIDOR_B_END := Vector3(24, 0, -17)
const CORRIDOR_C_END := Vector3(24, 0, -25)
const CORRIDOR_D_END := Vector3(19, 0, -27)
const DEAD_END := Vector3(17, 0, -28)

const BASE_NPC_SPEED := 2.0

# --- Virtual overrides ---

func _build_scene() -> void:
	_build_environment()
	_build_corridor()

func _build_characters() -> void:
	var chars_node := Node3D.new()
	chars_node.name = "Characters"
	add_child(chars_node)

	# Aster at his Psy-Knapse device
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = ASTER_DEVICE_POS + Vector3(0, 0.5, 0)
	chars_node.add_child(_player)

	# Citizen (CZN-217) at the device to Aster's right
	_citizen = _create_npc("CZN-217", Color(0.5, 0.45, 0.4))
	_citizen.position = CITIZEN_DEVICE_POS
	chars_node.add_child(_citizen)

	# Other citizens at their own devices (further right)
	for i in range(3):
		var npc := _create_npc("CZN-%03d" % (400 + i), Color(0.4, 0.4, 0.45))
		npc.position = CITIZEN_DEVICE_POS + Vector3((i + 1) * DEVICE_SPACING, 0, 0)
		chars_node.add_child(npc)
		_bystanders.append(npc)

	# Naturalizers standing near the back wall
	_naturalizer_1 = _create_npc("NK-01", Color(0.85, 0.85, 0.88))
	_naturalizer_1.position = NK_STAND_POS_1
	chars_node.add_child(_naturalizer_1)

	_naturalizer_2 = _create_npc("NK-02", Color(0.85, 0.85, 0.88))
	_naturalizer_2.position = NK_STAND_POS_2
	chars_node.add_child(_naturalizer_2)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 7))

func _register_characters() -> void:
	_register_gs_character("aster", _player, 3.0)
	_register_gs_character("citizen", _citizen, BASE_NPC_SPEED)

	for i in range(_bystanders.size()):
		var id := "czn_%d" % (400 + i)
		_register_gs_character(id, _bystanders[i], BASE_NPC_SPEED)

	_register_gs_character("nk1", _naturalizer_1, BASE_NPC_SPEED)
	_register_gs_character("nk2", _naturalizer_2, BASE_NPC_SPEED)

func _setup_ui() -> void:
	# Aster's data-view perception (managed by base class)
	_setup_perception("data", _player)

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

func _begin() -> void:
	_start_arrive()

# --- Event-driven steps ---

func _start_arrive() -> void:
	_enter_step("arrive")
	_player.set_move_enabled(false)
	_game_state.character_arrived.connect(_on_character_arrived)
	DialogueData.say_to(_dialogue, "tag_day.checkpoint_id")
	# Citizen murmurs the nursery rhyme, then scan triggers
	_scheduler.schedule_after(2.0, func():
		_dialogue_chain(
			["tag_day.murmur.01", "tag_day.murmur.02"],
			func(): _scheduler.schedule_after(1.5, _start_citizen_scan, "citizen_scan")
		)
	, "murmur")

func _on_character_arrived(id: String) -> void:
	if id == "citizen" and _current_step in ["corridor_walk", "pan_prompt", "fragments"]:
		_scheduler.schedule_after(0, _start_neutralization, "neutralization")

func _start_citizen_scan() -> void:
	_enter_step("citizen_scan")
	# The citizen's device scan fails
	_citizen_light.light_color = Color(0.8, 0.1, 0.05)
	_citizen_light.light_energy = 6.0
	DialogueData.say_to(_dialogue, "tag_day.scan_failed")
	_scheduler.schedule_after(3.0, _start_naturalizers_grip, "nk_grip")

func _start_naturalizers_grip() -> void:
	_enter_step("naturalizers_grip")
	# Naturalizers approach deliberately (slower than default)
	_game_state.change_move_speed("nk1", 1.5)
	_game_state.change_move_speed("nk2", 1.5)
	_game_state.command_move_to_pos("nk1", CITIZEN_DEVICE_POS + Vector3(0, 0, -0.6))
	_game_state.command_move_to_pos("nk2", CITIZEN_DEVICE_POS + Vector3(0, 0, 0.6))
	# Wait for enforcers to reach the citizen (~4s at speed 2.0) before walking
	_scheduler.schedule_after(5.0, _begin_corridor_walk, "corridor_walk")
	# Report label appears above the escort during the walk
	_scheduler.schedule_after(10.0, _show_report_label, "report_label")

func _show_report_label() -> void:
	var lbl := Label3D.new()
	lbl.name = "ReportLabel"
	lbl.text = "REPORT FILED  |  CAUSE: MENTAL INSTABILITY"
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.2, 0.0)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_naturalizer_1.add_child(lbl)
	lbl.position = Vector3(0, 2.0, 0)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.9, 1.0)
	tween.tween_interval(8.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0)

func _begin_corridor_walk() -> void:
	_enter_step("corridor_walk")

	# Snap all three into formation at citizen's device before walking.
	# Prevents enforcers from getting ahead if the grip movement was incomplete.
	_game_state.command_stop("citizen")
	_game_state.command_stop("nk1")
	_game_state.command_stop("nk2")
	_citizen.global_position = Vector3(CITIZEN_DEVICE_POS.x, 0, CITIZEN_DEVICE_POS.z)
	_naturalizer_1.global_position = CITIZEN_DEVICE_POS + Vector3(0, 0, -0.6)
	_naturalizer_2.global_position = CITIZEN_DEVICE_POS + Vector3(0, 0, 0.6)

	# Walk speed paced so they arrive near the dead end around the BANG line.
	# Path from device to dead end is ~52 units; poem + fragments ≈ 120s → speed ~0.45
	_game_state.change_move_speed("citizen", 0.45)
	_game_state.change_move_speed("nk1", 0.45)
	_game_state.change_move_speed("nk2", 0.45)

	var citizen_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE, CORRIDOR_A_END, CORRIDOR_B_END,
		CORRIDOR_C_END, CORRIDOR_D_END, DEAD_END,
	]
	_game_state.command_walk_path("citizen", citizen_path)

	var nk1_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0, 0, -0.6),
		CORRIDOR_A_END + Vector3(0, 0, -0.6),
		CORRIDOR_B_END + Vector3(-0.6, 0, 0),
		CORRIDOR_C_END + Vector3(-0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, -0.6),
		DEAD_END + Vector3(-0.6, 0, 0),
	]
	_game_state.command_walk_path("nk1", nk1_path)

	var nk2_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0, 0, 0.6),
		CORRIDOR_A_END + Vector3(0, 0, 0.6),
		CORRIDOR_B_END + Vector3(0.6, 0, 0),
		CORRIDOR_C_END + Vector3(0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, 0.6),
		DEAD_END + Vector3(0.6, 0, 0),
	]
	_game_state.command_walk_path("nk2", nk2_path)

	# Shadow stanzas — spaced out
	_dialogue.default_hold_time = 4.0
	DialogueData.say_sequence_to(_dialogue, "tag_day.poem.")
	_scheduler.schedule_after(2.0, _start_pan_prompt, "pan_prompt")
	_dialogue.dialogue_finished.connect(_on_poem_finished, CONNECT_ONE_SHOT)

	# Enforcer banter — interlaced with the poem, visible if the player pans.
	# Appears while WASD prompt is showing, before the F fast-forward prompt.
	_scheduler.schedule_after(4.0, func(): _show_nk_chat(_naturalizer_1, DialogueData.text("tag_day.nk_chat.01")), "nk_chat1")
	_scheduler.schedule_after(8.0, func(): _show_nk_chat(_naturalizer_2, DialogueData.text("tag_day.nk_chat.02")), "nk_chat2")
	_scheduler.schedule_after(13.0, func(): _show_nk_chat(_naturalizer_1, DialogueData.text("tag_day.nk_chat.03")), "nk_chat3")
	_scheduler.schedule_after(18.0, func(): _show_nk_chat(_naturalizer_2, DialogueData.text("tag_day.nk_chat.04")), "nk_chat4")

func _show_nk_chat(nk: Node3D, text: String) -> void:
	var old := nk.find_child("ChatLabel", false, false)
	if old:
		old.queue_free()
	var lbl := Label3D.new()
	lbl.name = "ChatLabel"
	lbl.text = text
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.7, 0.7, 0.75, 0.0)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nk.add_child(lbl)
	lbl.position = Vector3(0, 1.8, 0)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.85, 0.4)
	tween.tween_interval(5.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tween.tween_callback(lbl.queue_free)

func _start_pan_prompt() -> void:
	_enter_step("pan_prompt")
	_camera.set_pan_enabled(true)
	_camera.set_wasd_pan_enabled(true)
	_camera.max_pan_distance = 40.0
	_tutorial_prompt.show_prompt("WASD — pan camera")
	# F prompt appears after the enforcer banter wraps up (~20s into the walk)
	_scheduler.schedule_after(20.0, _show_fastforward_prompt, "ff_prompt")

func _show_fastforward_prompt() -> void:
	_tutorial_prompt.show_prompt("F — fast-forward time")

func _on_poem_finished() -> void:
	_start_fragments()

func _start_fragments() -> void:
	_enter_step("fragments")
	_tutorial_prompt.hide_prompt()
	_dialogue.default_hold_time = 2.5
	# Stuttering prayer fragments with gaps, then "world ends" x3, then bang
	_dialogue_chain([
		"tag_day.fragment.01", "tag_day.fragment.02", "tag_day.fragment.03",
		"tag_day.fragment.04", "tag_day.fragment.05", "tag_day.fragment.06",
		"tag_day.fragment.07",
	], _on_bang, 1.5)

func _on_bang() -> void:
	_camera.shake(0.5, 3.0)
	_dialogue.clear()
	_scheduler.schedule_after(2.5, _fragment_whimper, "whimper")

func _fragment_whimper() -> void:
	DialogueData.say_to(_dialogue, "tag_day.fragment.08")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(1.0, _start_neutralization, "neutralization")
	, CONNECT_ONE_SHOT)

func _start_neutralization() -> void:
	if not _enter_step("neutralization"):
		return
	_game_state.command_stop("citizen")
	_game_state.command_stop("nk1")
	_game_state.command_stop("nk2")
	_scheduler.schedule_after(1.0, func(): _citizen.fade_out(2.0), "citizen_fade")
	_scheduler.schedule_after(3.0, _start_lockdown, "lockdown")

func _start_lockdown() -> void:
	_enter_step("lockdown")
	_citizen_light.light_energy = 4.0
	_camera.shake(0.15, 8.0)
	_dialogue_chain(
		["tag_day.lockdown", "tag_day.groan", "tag_day.report_blocked"],
		func(): _scheduler.schedule_after(1.5, _start_return_focus, "return_focus")
	)

func _start_return_focus() -> void:
	_enter_step("return_focus")
	_camera.set_wasd_pan_enabled(false)
	_camera.set_pan_enabled(false)
	_camera.max_pan_distance = 15.0
	# Citizen's light dims back down
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	_scheduler.schedule_after(2.0, _start_aster_scans, "aster_scans")

func _start_aster_scans() -> void:
	_current_step = "aster_scans"
	# Aster's device scans him — blue light at his position
	_citizen_light.light_color = Color(0.2, 0.5, 0.9)
	_citizen_light.light_energy = 4.0
	_citizen_light.position = ASTER_DEVICE_POS + Vector3(0, 2, 0)
	DialogueData.say_to(_dialogue, "tag_day.scan_passed")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(0.5, _start_blue_transition, "blue_transition")
	, CONNECT_ONE_SHOT)

func _start_blue_transition() -> void:
	_enter_step("clearance")
	_citizen_light.light_color = Color(0.15, 0.4, 0.85)
	_citizen_light.light_energy = 6.0
	_dialogue.default_hold_time = 2.0
	# Screen fades to blue — transition to Peris
	_fade_rect.color = Color(0.1, 0.2, 0.5, 0.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 2.0)
	tween.tween_callback(_on_sequence_complete)

func _on_sequence_complete() -> void:
	_enter_step("complete")
	get_tree().change_scene_to_file("res://scenes/tutorial/peris_sim.tscn")


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
	_add_wall(env_node, Vector3(4.5, 1.5, -8), Vector3(17, 3, 0.3))
	_add_wall(env_node, Vector3(21.5, 1.5, -8), Vector3(13, 3, 0.3))
	_add_wall(env_node, Vector3(12, 1.5, 6), Vector3(32, 3, 0.3))
	_add_wall(env_node, Vector3(-4, 1.5, -2), Vector3(0.3, 3, 14))
	_add_wall(env_node, Vector3(28, 1.5, -2), Vector3(0.3, 3, 14))

	# Psy-Knapse devices — row of stations, one per citizen
	for i in range(5):
		var dev_pos := ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING, 0, 0)
		_add_booth(env_node, dev_pos, "PSY-%d" % (i + 1))

	# Floor lane dividers between devices
	for i in range(6):
		var marker := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.05, 0.02, 1.2)
		marker.mesh = line
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.15, 0.15, 0.2)
		marker.material_override = line_mat
		marker.position = ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING + DEVICE_SPACING * 0.5, 0.01, 0)
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

	# Verification sign
	var overhead := MeshInstance3D.new()
	var oh_box := BoxMesh.new()
	oh_box.size = Vector3(3, 0.1, 0.6)
	overhead.mesh = oh_box
	var oh_mat := StandardMaterial3D.new()
	oh_mat.albedo_color = Color(0.15, 0.15, 0.2)
	oh_mat.emission_enabled = true
	oh_mat.emission = Color(0.1, 0.12, 0.2)
	oh_mat.emission_energy_multiplier = 0.3
	overhead.material_override = oh_mat
	var sign_x := ASTER_DEVICE_POS.x + 2.0 * DEVICE_SPACING
	overhead.position = Vector3(sign_x, 2.6, 0)
	env_node.add_child(overhead)
	var sign_lbl := Label3D.new()
	sign_lbl.text = "TAG DAY  //  VERIFICATION  7-B"
	sign_lbl.font_size = 32
	sign_lbl.pixel_size = 0.008
	sign_lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	sign_lbl.position = Vector3(sign_x, 2.6, -0.04)
	env_node.add_child(sign_lbl)

	# Light above citizen's device (used for scan result + lockdown)
	_citizen_light = OmniLight3D.new()
	_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	_citizen_light.omni_range = 4.0
	env_node.add_child(_citizen_light)

# --- Corridor Build ---

func _build_corridor() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	var floor_color := Color(0.06, 0.06, 0.08)

	# Segment A: straight away from doorway (x=13-15, z=-8 to z=-16)
	_add_corridor_floor(env_node, Vector3(14, -0.05, -12), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(14, -0.01, -12), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(12.85, 1.5, -12), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(15.15, 1.5, -12), Vector3(0.3, 3, 8))

	# Segment B: turn right (x=15-25, z=-16 to z=-18)
	_add_corridor_floor(env_node, Vector3(20, -0.05, -17), Vector3(10, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(20, -0.01, -17), Vector3(10, 0.02, 2))
	_add_wall(env_node, Vector3(20, 1.5, -15.85), Vector3(10, 3, 0.3))
	_add_wall(env_node, Vector3(20, 1.5, -18.15), Vector3(10, 3, 0.3))

	# Segment C: turn away again (x=23-25, z=-18 to z=-26)
	_add_corridor_floor(env_node, Vector3(24, -0.05, -22), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(24, -0.01, -22), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(22.85, 1.5, -22), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(25.15, 1.5, -22), Vector3(0.3, 3, 8))

	# Segment D: turn left into dead-end (x=16-23, z=-26 to z=-28)
	_add_corridor_floor(env_node, Vector3(19.5, -0.05, -27), Vector3(7, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(19.5, -0.01, -27), Vector3(7, 0.02, 2))
	_add_wall(env_node, Vector3(19.5, 1.5, -25.85), Vector3(7, 3, 0.3))
	_add_wall(env_node, Vector3(19.5, 1.5, -28.15), Vector3(7, 3, 0.3))

	# Dead end alcove (x=16-18, z=-28 to z=-30)
	_add_corridor_floor(env_node, Vector3(17, -0.05, -29), Vector3(2, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(17, -0.01, -29), Vector3(2, 0.02, 2))
	_add_wall(env_node, Vector3(15.85, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(18.15, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(17, 1.5, -30.15), Vector3(2, 3, 0.3))

	# Corridor ceiling panels
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
