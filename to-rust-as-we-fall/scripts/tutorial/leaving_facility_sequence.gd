extends Node3D

## Leaving the facility — iron spill tutorial.
## Aster and Peris forced out. Endo joins at the exit.
## Teaches safe/direct routing, time pressure, first shelter rest.
## No UI text, popups, or prompts. The environment teaches.

enum Phase {
	FADE_IN,            # Transition from Peris's sim
	FACILITY_EXIT,      # Aster and Peris at the facility exit
	ENDO_JOINS,         # Endo appears, joins the party
	FIRST_CORRIDOR,     # Player clicks destination — safe mode routes around iron spill
	SAFE_ROUTE_LESSON,  # Characters take the long way. Player absorbs the detour.
	DUSK_APPROACHES,    # Time bar appears. Endo mentions shelter. Urgency.
	SECOND_IRON,        # Another iron patch. Safe detour is very long. Choice moment.
	REACH_SHELTER,      # Characters arrive at shelter
	FIRST_REST,         # Rest mechanic — night skip
	DAWN,               # Day 2 begins
	COMPLETE,
}

var _phase: Phase = Phase.FADE_IN
var _phase_timer := 0.0
var _phase_started := false
var _player_clicked_destination := false
var _reached_midpoint := false
var _reached_shelter := false
var _routing_mode := "safe"  # "safe" or "direct"

var _player  # Aster (player-controlled)
var _peris   # Peris (follows Aster)
var _endo    # Endo (joins at exit)
var _camera
var _dialogue
var _fade_rect: ColorRect
var _time_bar: ProgressBar
var _time_label: Label
var _time_bar_container: Control
var _routing_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _iron_lights: Array[OmniLight3D] = []

var _game_time := 0.3  # Start in afternoon — dusk is coming
var _hp := 100.0

# --- Layout ---
# Corridor runs along +X. Two routes at each iron patch.
const EXIT_POS := Vector3(0, 0, 0)
const IRON_1_POS := Vector3(12, 0, 0)       # First iron spill on main path
const SAFE_1_WAYPOINT := Vector3(12, 0, -6)  # Safe detour goes around
const SAFE_1_END := Vector3(18, 0, 0)
const MIDPOINT := Vector3(22, 0, 0)
const IRON_2_POS := Vector3(30, 0, 0)        # Second iron spill
const SAFE_2_WAYPOINT := Vector3(30, 0, -8)  # Much longer safe detour
const SAFE_2_END := Vector3(38, 0, 0)
const SHELTER_POS := Vector3(42, 0, 0)

func _ready() -> void:
	_build_environment()
	_build_characters()
	_build_ui()
	_set_phase(Phase.FADE_IN)

func _process(delta: float) -> void:
	_phase_timer += delta

	# Time advances during outdoor phases
	if _phase >= Phase.FIRST_CORRIDOR and _phase < Phase.FIRST_REST:
		_game_time += delta * 0.008  # Slow enough to feel pressure but allow play
		_update_time_display()

	# Iron damage when standing on iron
	if _phase >= Phase.FIRST_CORRIDOR and _phase < Phase.REACH_SHELTER:
		_check_iron_damage(delta)

	# Peris follows Aster (loose follow)
	if _peris and _player and _phase >= Phase.FIRST_CORRIDOR:
		var follow_dist: float = _player.global_position.distance_to(_peris.global_position)
		if follow_dist > 2.5 and not _peris.is_moving() if _peris.has_method("is_moving") else false:
			_peris.walk_to(_player.global_position + Vector3(-1.2, 0, 0.8))

	# Endo follows too
	if _endo and _endo.visible and _player and _phase >= Phase.FIRST_CORRIDOR:
		var endo_dist: float = _player.global_position.distance_to(_endo.global_position)
		if endo_dist > 3.0:
			_endo.walk_to(_player.global_position + Vector3(-1.2, 0, -0.8))

	match _phase:
		Phase.FADE_IN: _process_fade_in(delta)
		Phase.FACILITY_EXIT: _process_facility_exit(delta)
		Phase.ENDO_JOINS: _process_endo_joins(delta)
		Phase.FIRST_CORRIDOR: _process_first_corridor(delta)
		Phase.SAFE_ROUTE_LESSON: _process_safe_route(delta)
		Phase.DUSK_APPROACHES: _process_dusk(delta)
		Phase.SECOND_IRON: _process_second_iron(delta)
		Phase.REACH_SHELTER: _process_reach_shelter(delta)
		Phase.FIRST_REST: _process_first_rest(delta)
		Phase.DAWN: _process_dawn(delta)

func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_timer = 0.0
	_phase_started = false

func _enter_phase() -> void:
	_phase_started = true

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		# Tab to toggle safe/direct
		if kc == KEY_TAB and _phase >= Phase.DUSK_APPROACHES:
			_toggle_routing()

# --- Phases ---

func _process_fade_in(delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_fade_rect.color = Color(0.03, 0.03, 0.04, 1)
		_player.set_move_enabled(false)

	var alpha := 1.0 - clampf(_phase_timer / 2.0, 0.0, 1.0)
	_fade_rect.color.a = alpha
	if _phase_timer > 2.5:
		_set_phase(Phase.FACILITY_EXIT)

func _process_facility_exit(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		DialogueData.say_to(_dialogue, "facility.exit_narration")
	if _phase_timer > 3.5:
		_set_phase(Phase.ENDO_JOINS)

func _process_endo_joins(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_endo.visible = true
		_endo.walk_to(EXIT_POS + Vector3(1.5, 0, -0.8))
		DialogueData.say_to(_dialogue, "facility.endo_appears")
		DialogueData.say_to(_dialogue, "facility.endo.shelters")
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.FIRST_CORRIDOR), CONNECT_ONE_SHOT
		)

func _process_first_corridor(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_player.set_move_enabled(true)

	# Detect when player clicks toward the iron spill area
	var player_x: float = _player.global_position.x
	if player_x > IRON_1_POS.x - 3.0 and not _player_clicked_destination:
		_player_clicked_destination = true
		# In safe mode, auto-route around the iron
		# The player sees the detour happen
		DialogueData.say_to(_dialogue, "facility.endo.iron_warn")
		_set_phase(Phase.SAFE_ROUTE_LESSON)

func _process_safe_route(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# The safe route goes around — the player watches the detour

	var player_x: float = _player.global_position.x
	if player_x > MIDPOINT.x - 1.0:
		_reached_midpoint = true
		_set_phase(Phase.DUSK_APPROACHES)

func _process_dusk(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Time bar appears
		_time_bar_container.visible = true
		_game_time = 0.4  # Push toward dusk
		DialogueData.say_to(_dialogue, "facility.endo.dusk")
		_routing_label.visible = true
		_hp_bar.visible = true
		_hp_label.visible = true

	if _phase_timer > 4.0:
		_set_phase(Phase.SECOND_IRON)

func _process_second_iron(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# The choice: safe (very long detour) or direct (through iron)
		# No prompt — just the visible iron patch and the time bar ticking

	var player_x: float = _player.global_position.x
	if player_x > SHELTER_POS.x - 2.0:
		_set_phase(Phase.REACH_SHELTER)

func _process_reach_shelter(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_player.set_move_enabled(false)
		DialogueData.say_to(_dialogue, "facility.endo.shelter")

	if _phase_timer > 2.5:
		_set_phase(Phase.FIRST_REST)

func _process_first_rest(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		# Night falls
		_game_time = 0.55
		_update_time_display()
		DialogueData.say_to(_dialogue, "facility.night_narration")
		DialogueData.say_to(_dialogue, "facility.endo.rest")
		# Heal
		_hp = 100.0
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.DAWN), CONNECT_ONE_SHOT
		)

func _process_dawn(_delta: float) -> void:
	if not _phase_started:
		_enter_phase()
		_game_time = 0.05
		_update_time_display()
		DialogueData.say_to(_dialogue, "facility.dawn")
		_dialogue.dialogue_finished.connect(
			func(): _set_phase(Phase.COMPLETE), CONNECT_ONE_SHOT
		)

# --- Routing ---

func _toggle_routing() -> void:
	if _routing_mode == "safe":
		_routing_mode = "direct"
		_routing_label.text = "DIRECT"
		_routing_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.2, 0.8))
	else:
		_routing_mode = "safe"
		_routing_label.text = "SAFE"
		_routing_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.4, 0.8))

# --- Iron damage ---

func _check_iron_damage(delta: float) -> void:
	var px: float = _player.global_position.x
	var pz: float = _player.global_position.z
	var on_iron := false

	# Iron patch 1: around IRON_1_POS, 3 tiles wide
	if abs(px - IRON_1_POS.x) < 2.0 and abs(pz - IRON_1_POS.z) < 2.0:
		on_iron = true
	# Iron patch 2: around IRON_2_POS, 3 tiles wide
	if abs(px - IRON_2_POS.x) < 2.0 and abs(pz - IRON_2_POS.z) < 2.0:
		on_iron = true

	if on_iron:
		_hp = maxf(0, _hp - 4.0 * delta)
		_hp_bar.value = _hp
		# Visual feedback — iron light pulses
		for light in _iron_lights:
			light.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.01) * 1.5

func _update_time_display() -> void:
	_time_bar.value = _game_time * 100.0
	var tod_label: String
	if _game_time < 0.15: tod_label = "Morning"
	elif _game_time < 0.3: tod_label = "Afternoon"
	elif _game_time < 0.4: tod_label = "Evening"
	elif _game_time < 0.5: tod_label = "Dusk"
	else: tod_label = "NIGHT"
	_time_label.text = "Day 1  %s" % tod_label
	_time_label.add_theme_color_override("font_color",
		Color(0.8, 0.2, 0.15) if _game_time >= 0.5
		else Color(0.7, 0.5, 0.2) if _game_time >= 0.4
		else Color(0.5, 0.5, 0.55)
	)

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	# Ground — long corridor floor
	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(50, 0.1, 16)
	ground.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.1, 0.1, 0.12)
	ground.material_override = gm
	ground.position = Vector3(22, -0.05, 0)
	env.add_child(ground)

	# Floor collision
	var fbody := StaticBody3D.new()
	fbody.position = Vector3(22, -0.01, 0)
	fbody.collision_layer = 1  # Ground
	fbody.collision_mask = 0
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(50, 0.02, 16)
	fcol.shape = fshape
	fbody.add_child(fcol)
	env.add_child(fbody)

	# Corridor walls
	var wc := Color(0.13, 0.12, 0.14)
	_add_wall(env, Vector3(22, 1.5, -8), Vector3(50, 3, 0.3), wc)
	_add_wall(env, Vector3(22, 1.5, 8), Vector3(50, 3, 0.3), wc)

	# Facility door (behind player)
	_add_wall(env, Vector3(-2, 1.5, 0), Vector3(0.4, 3, 16), Color(0.08, 0.08, 0.1))

	# Shelter structure at the end
	_add_shelter(env, SHELTER_POS)

	# Iron spill patches — visible orange-brown discoloration
	_add_iron_patch(env, IRON_1_POS)
	_add_iron_patch(env, IRON_2_POS)

	# Safe detour paths — slightly lighter floor sections showing the alternate route
	_add_detour_markers(env, IRON_1_POS, SAFE_1_WAYPOINT, 4)
	_add_detour_markers(env, IRON_2_POS, SAFE_2_WAYPOINT, 6)

	# Corridor lighting — dimmer than facility, exterior feel
	var dir := DirectionalLight3D.new()
	dir.rotation_degrees = Vector3(-50, 20, 0)
	dir.light_color = Color(0.6, 0.55, 0.5)
	dir.light_energy = 0.5
	dir.shadow_enabled = true
	env.add_child(dir)

	# World environment — cooler, more exposed
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.28, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.3
	we.environment = e
	env.add_child(we)

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

func _add_iron_patch(parent: Node3D, pos: Vector3) -> void:
	# Orange-brown floor discoloration
	var patch := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(4, 0.02, 4)
	patch.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.15, 0.05)
	pm.emission_enabled = true
	pm.emission = Color(0.25, 0.08, 0.02)
	pm.emission_energy_multiplier = 0.4
	patch.material_override = pm
	patch.position = pos + Vector3(0, 0.01, 0)
	parent.add_child(patch)

	# Iron glow light
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.5, 0)
	light.light_color = Color(0.7, 0.25, 0.05)
	light.light_energy = 2.0
	light.omni_range = 4.0
	parent.add_child(light)
	_iron_lights.append(light)

	# "Fe" label (visible through Aster's data lens)
	var lbl := Label3D.new()
	lbl.text = "Fe"
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.1, 0.5)
	lbl.position = pos + Vector3(0, 0.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

func _add_detour_markers(parent: Node3D, iron_pos: Vector3, waypoint: Vector3, count: int) -> void:
	# Subtle floor markers showing the safe route exists
	for i in range(count):
		var t := float(i) / float(count - 1) if count > 1 else 0.5
		var pos := iron_pos.lerp(waypoint, t)
		var marker := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(0.6, 0.015, 0.6)
		marker.mesh = mb
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.14, 0.14, 0.16)
		marker.material_override = mm
		marker.position = pos + Vector3(0, 0.005, 0)
		parent.add_child(marker)

func _add_shelter(parent: Node3D, pos: Vector3) -> void:
	# Shelter structure — a recessed alcove with a warm light
	_add_wall(parent, pos + Vector3(0, 1.0, -2.5), Vector3(3, 2, 0.2), Color(0.14, 0.13, 0.12))
	_add_wall(parent, pos + Vector3(0, 1.0, 2.5), Vector3(3, 2, 0.2), Color(0.14, 0.13, 0.12))
	_add_wall(parent, pos + Vector3(1.5, 1.0, 0), Vector3(0.2, 2, 5), Color(0.14, 0.13, 0.12))
	# Ceiling
	_add_wall(parent, pos + Vector3(0, 2.0, 0), Vector3(3, 0.15, 5), Color(0.12, 0.11, 0.1))

	# Warm interior light
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.5, 0)
	light.light_color = Color(0.8, 0.6, 0.35)
	light.light_energy = 2.5
	light.omni_range = 5.0
	parent.add_child(light)

	# Shelter label
	var lbl := Label3D.new()
	lbl.text = "SHELTER"
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.4, 0.5, 0.7, 0.6)
	lbl.position = pos + Vector3(0, 2.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

# --- Characters ---

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_char("Aster", Color(0.29, 0.62, 1.0), true)
	_player.position = EXIT_POS + Vector3(1, 0.5, 0)
	chars.add_child(_player)

	# Peris (follows)
	_peris = Node3D.new()
	_peris.name = "Peris"
	_peris.set_script(preload("res://scripts/game/npc.gd"))
	_peris.display_name = "PERIS"
	_peris.color = Color(1.0, 0.67, 0.27)
	_peris.position = EXIT_POS + Vector3(0, 0, 1)
	chars.add_child(_peris)

	# Endo (hidden until joins)
	_endo = Node3D.new()
	_endo.name = "Endo"
	_endo.set_script(preload("res://scripts/game/npc.gd"))
	_endo.display_name = "ENDO"
	_endo.color = Color(0.4, 0.67, 0.53)
	_endo.position = EXIT_POS + Vector3(3, 0, -2)
	_endo.visible = false
	chars.add_child(_endo)

	# Camera
	var cam := Camera3D.new()
	cam.name = "GameCamera"
	cam.set_script(preload("res://scripts/game/game_camera.gd"))
	add_child(cam)
	_camera = cam
	_camera.target = _player
	_camera.follow_offset = Vector3(0, 10, 8)
	_camera.set_pan_enabled(false)

func _create_char(char_name: String, color: Color, is_player: bool) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = char_name

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.25
	cs.height = 1.0
	col.shape = cs
	col.position.y = 0.5
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.position.y = 0.5
	body.add_child(mesh)

	var label := Label3D.new()
	label.name = "Label3D"
	label.text = char_name.to_upper()
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = Color(color, 0.8)
	label.position.y = 1.3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(label)

	# Collision layer 2 (characters), mask 2 (other characters only)
	body.collision_layer = 2
	body.collision_mask = 2

	if is_player:
		body.set_script(preload("res://scripts/game/player.gd"))
		body.color = color
	return body

# --- UI ---

func _build_ui() -> void:
	# Dialogue
	var dlg := CanvasLayer.new()
	dlg.name = "DialogueBox"
	dlg.set_script(preload("res://scripts/game/dialogue_box.gd"))
	add_child(dlg)
	_dialogue = dlg

	# Fade overlay
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.03, 0.03, 0.04, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)

	# HUD layer
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	# Time bar — top center (hidden until DUSK_APPROACHES)
	_time_bar_container = HBoxContainer.new()
	_time_bar_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_bar_container.offset_top = 10
	_time_bar_container.offset_left = -120
	_time_bar_container.offset_right = 120
	_time_bar_container.offset_bottom = 30
	_time_bar_container.add_theme_constant_override("separation", 8)
	_time_bar_container.visible = false
	hud.add_child(_time_bar_container)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_time_label.custom_minimum_size.x = 80
	_time_bar_container.add_child(_time_label)

	_time_bar = ProgressBar.new()
	_time_bar.min_value = 0
	_time_bar.max_value = 100
	_time_bar.value = _game_time * 100
	_time_bar.show_percentage = false
	_time_bar.custom_minimum_size = Vector2(120, 12)
	var tb_bg := StyleBoxFlat.new()
	tb_bg.bg_color = Color(0.08, 0.08, 0.1)
	tb_bg.set_corner_radius_all(2)
	_time_bar.add_theme_stylebox_override("background", tb_bg)
	var tb_fill := StyleBoxFlat.new()
	tb_fill.bg_color = Color(0.7, 0.5, 0.2)
	tb_fill.set_corner_radius_all(2)
	_time_bar.add_theme_stylebox_override("fill", tb_fill)
	_time_bar_container.add_child(_time_bar)

	# Routing mode indicator — bottom left (hidden until DUSK)
	_routing_label = Label.new()
	_routing_label.text = "SAFE"
	_routing_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_routing_label.offset_left = 16
	_routing_label.offset_bottom = -16
	_routing_label.offset_top = -36
	_routing_label.add_theme_font_size_override("font_size", 13)
	_routing_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.4, 0.8))
	_routing_label.visible = false
	hud.add_child(_routing_label)

	# HP bar — top right (hidden until DUSK)
	var hp_container := HBoxContainer.new()
	hp_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hp_container.offset_left = -170
	hp_container.offset_top = 10
	hp_container.offset_right = -12
	hp_container.offset_bottom = 28
	hp_container.add_theme_constant_override("separation", 8)
	hud.add_child(hp_container)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3, 0.8))
	_hp_label.custom_minimum_size.x = 60
	_hp_label.text = "HP 100%"
	_hp_label.visible = false
	hp_container.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(80, 12)
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.08, 0.08, 0.1)
	hp_bg.set_corner_radius_all(2)
	_hp_bar.add_theme_stylebox_override("background", hp_bg)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.7, 0.3, 0.25)
	hp_fill.set_corner_radius_all(2)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	_hp_bar.visible = false
	hp_container.add_child(_hp_bar)
