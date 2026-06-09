@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")

## Iron spill tutorial: routing, pressure, Endo join, first shelter rest.

var _routing_mode := "safe"

var _peris
var _endo
var _hud  # GameHUD
var _iron_lights: Array[OmniLight3D] = []
var _dir_light: DirectionalLight3D
var _world_environment: Environment

var _game_day := 1
var _game_time := 0.3
var _game_clock = DayNightCycleScript.new()
# HP and running live in GameState.

# Corridor runs along +X.
const EXIT_POS := Vector3(0, 0, 0)
const IRON_1_POS := Vector3(12, 0, 0)
const SAFE_1_WAYPOINT := Vector3(12, 0, -6)
const SAFE_1_END := Vector3(18, 0, 0)
const MIDPOINT := Vector3(22, 0, 0)
const IRON_2_POS := Vector3(30, 0, 0)
const SAFE_2_WAYPOINT := Vector3(30, 0, -8)
const SAFE_2_END := Vector3(38, 0, 0)
const SHELTER_POS := Vector3(42, 0, 0)
var _grid: GridWorld
const OUTDOOR_STEPS := [
	"first_corridor",
	"safe_route_lesson",
	"dusk_approaches",
	"second_iron",
	"reach_shelter",
]

# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()
	_build_decorations()

## The corridor floor (50x16, world X[-3,47] Z[-8,8]) as a single-level open plane — iron spills are
## damage zones, not walls, so the grid stays open and the party routes on it cooperatively.
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = Vector3(-3.0, 0.0, -8.0)
	_grid.create_room(50, 16, false)

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = EXIT_POS + Vector3(1, 0.5, 0)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars.add_child(_player)

	# Peris (follows)
	_peris = _create_npc("Peris", Color(1.0, 0.67, 0.27))
	_peris.position = EXIT_POS + Vector3(0, 0, 1)
	if not Engine.is_editor_hint():
		_peris.grid_world = _grid
	chars.add_child(_peris)

	# Endo (hidden until joins)
	_endo = _create_npc("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = EXIT_POS + Vector3(3, 0, -2)
	_endo.visible = false
	if not Engine.is_editor_hint():
		_endo.grid_world = _grid
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8), true)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, GameState.WALK_SPEED, {"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX})
	_register_gs_character("peris", _peris, 2.5, {"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX})
	_register_gs_character("endo", _endo, 2.5, {"hp": GameState.HP_MAX})

func _setup_ui() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "GameHUD"
	_hud.set_script(preload("res://scripts/ui/game_hud.gd"))
	add_child(_hud)
	_hud.add_stat_bar("hp", Color(0.7, 0.3, 0.25), GameState.HP_MAX, GameState.HP_MAX)
	# Bind after _game_state exists; route guards still own toggles.

func _begin() -> void:
	if _hud:
		_hud.bind_game_state(_game_state, "aster", false)
	_set_game_time(_game_day, _game_time, false)
	_start_fade_in()

func _on_process(delta: float, spd: float) -> void:
	# Time advances during outdoor phases
	var outdoor := OUTDOOR_STEPS.has(_current_step)
	if outdoor:
		_advance_game_clock(delta * spd)

	# Iron damage when standing on iron
	if outdoor and _current_step != "reach_shelter":
		_check_iron_damage(delta * spd)

	# NPC follow behavior
	_update_npc_follow()

	# Per-frame visual updates
	_update_fades()

	# Position-based step triggers
	if _current_step == "first_corridor":
		var px: float = _game_state.get_position("aster").x
		if px > IRON_1_POS.x - 3.0:
			DialogueData.say_to(_dialogue, "facility.endo.iron_warn")
			_start_safe_route_lesson()
	elif _current_step == "safe_route_lesson":
		var px: float = _game_state.get_position("aster").x
		if px > MIDPOINT.x - 1.0:
			_start_dusk_approaches()
	elif _current_step == "second_iron":
		var px: float = _game_state.get_position("aster").x
		if px > SHELTER_POS.x - 2.0:
			_start_reach_shelter()

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.0)
	elif _current_step == "dawn":
		pass  # No fade

func _update_npc_follow() -> void:
	if _current_step in ["first_corridor", "safe_route_lesson", "dusk_approaches", "second_iron"]:
		var aster_pos := _game_state.get_position("aster")
		# Peris follows
		var peris_pos := _game_state.get_position("peris")
		if aster_pos.distance_to(peris_pos) > 2.5 and not _game_state.is_moving("peris"):
			_game_state.command_move_to_pos("peris", aster_pos + Vector3(-1.2, 0, 0.8))
		# Endo follows
		var endo_pos := _game_state.get_position("endo")
		if aster_pos.distance_to(endo_pos) > 3.0 and not _game_state.is_moving("endo"):
			_game_state.command_move_to_pos("endo", aster_pos + Vector3(-1.2, 0, -0.8))

# --- Input ---

# Route (Tab) and run (Z) arrive as HUD signals (routing_toggled / run_toggled)
# mapped from the input map by GameHUD — wired in _start_first_corridor.

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_current_step = "fade_in"
	_fade_from(Color(0.03, 0.03, 0.04, 1), 2.5, _start_facility_exit, "facility_exit")
	_player.set_move_enabled(false)

func _start_facility_exit() -> void:
	_current_step = "facility_exit"
	var orig_offset: Vector3 = _camera.follow_offset
	var t := create_tween()
	t.tween_property(_camera, "follow_offset", orig_offset + Vector3(3, 0, 0), 1.5)
	t.tween_interval(0.5)
	t.tween_property(_camera, "follow_offset", orig_offset, 1.0)
	_scheduler.schedule_after(3.5, _start_endo_joins, "endo_joins")

func _start_endo_joins() -> void:
	_current_step = "endo_joins"
	_endo.visible = true
	_game_state.command_move_to_pos("endo", EXIT_POS + Vector3(1.5, 0, -0.8))
	DialogueData.say_to(_dialogue, "facility.endo.shelters")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_first_corridor, "first_corridor"),
		CONNECT_ONE_SHOT
	)

func _start_first_corridor() -> void:
	_current_step = "first_corridor"
	_player.set_move_enabled(true)
	if _hud:
		_hud.show_routing_toggle("safe")
		_hud.routing_toggled.connect(func(mode: String): _routing_mode = mode)
		_hud.show_run_toggle(false)
		_hud.run_toggled.connect(func(running: bool): _toggle_run())
		_hud.highlight_held.connect(_on_highlight_held)  # hold SHIFT: reveal all interactables
	_set_game_time(_game_day, _game_time, true)

func _start_safe_route_lesson() -> void:
	_current_step = "safe_route_lesson"

func _start_dusk_approaches() -> void:
	_current_step = "dusk_approaches"
	_set_game_time(_game_day, 0.4, true)
	DialogueData.say_to(_dialogue, "facility.endo.dusk")
	_scheduler.schedule_after(4.0, _start_second_iron, "second_iron")

func _start_second_iron() -> void:
	_current_step = "second_iron"

func _start_reach_shelter() -> void:
	_current_step = "reach_shelter"
	_player.set_move_enabled(false)
	DialogueData.say_to(_dialogue, "facility.endo.shelter")
	_scheduler.schedule_after(2.5, _start_first_rest, "first_rest")

func _start_first_rest() -> void:
	_current_step = "first_rest"
	_set_game_time(_game_day, 0.55, true)
	# Night transition: dim world, pulse iron threat
	var t := create_tween()
	t.tween_property(_dir_light, "light_energy", 0.05, 1.5)
	for light in _iron_lights:
		var lt := create_tween()
		lt.set_loops(3)
		lt.tween_property(light, "light_energy", 3.5, 0.8)
		lt.tween_property(light, "light_energy", 1.5, 0.8)
	DialogueData.say_to(_dialogue, "facility.endo.rest")
	_game_state.set_stat("aster", "hp", GameState.HP_MAX)
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_dawn, "dawn"),
		CONNECT_ONE_SHOT
	)

func _start_dawn() -> void:
	_current_step = "dawn"
	_set_game_time(_game_day + 1, 0.05, true)
	DialogueData.say_to(_dialogue, "facility.dawn")
	_dialogue.dialogue_finished.connect(
		func(): _current_step = "complete",
		CONNECT_ONE_SHOT
	)

# --- Routing ---

func _toggle_run() -> void:
	if _game_state == null:
		return
	_game_state.toggle_running("aster")

func _toggle_routing() -> void:
	_routing_mode = "direct" if _routing_mode == "safe" else "safe"
	if _hud:
		_hud.set_routing_mode(_routing_mode)

# --- Iron damage ---

func _check_iron_damage(game_delta: float) -> void:
	var pos := _game_state.get_position("aster")
	var on_iron := false
	if abs(pos.x - IRON_1_POS.x) < 2.0 and abs(pos.z - IRON_1_POS.z) < 2.0:
		on_iron = true
	if abs(pos.x - IRON_2_POS.x) < 2.0 and abs(pos.z - IRON_2_POS.z) < 2.0:
		on_iron = true
	if on_iron:
		_game_state.adjust_stat("aster", "hp", -4.0 * game_delta)
		for light in _iron_lights:
			light.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.01) * 1.5  # @rendering_only — iron light pulse

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(50, 0.1, 16)
	ground.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.1, 0.1, 0.12)
	ground.material_override = gm
	ground.position = Vector3(22, -0.05, 0)
	env.add_child(ground)

	var fbody := StaticBody3D.new()
	fbody.position = Vector3(22, -0.01, 0)
	fbody.collision_layer = 1
	fbody.collision_mask = 0
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(50, 0.02, 16)
	fcol.shape = fshape
	fbody.add_child(fcol)
	env.add_child(fbody)

	var wc := Color(0.13, 0.12, 0.14)
	_add_wall(env, Vector3(22, 1.5, -8), Vector3(50, 3, 0.3), wc)
	_add_wall(env, Vector3(22, 1.5, 8), Vector3(50, 3, 0.3), wc)
	_add_wall(env, Vector3(-2, 1.5, 0), Vector3(0.4, 3, 16), Color(0.08, 0.08, 0.1))

	_add_shelter(env, SHELTER_POS)
	_add_iron_patch(env, IRON_1_POS)
	_add_iron_patch(env, IRON_2_POS)
	_add_detour_markers(env, IRON_1_POS, SAFE_1_WAYPOINT, 4)
	_add_detour_markers(env, IRON_2_POS, SAFE_2_WAYPOINT, 6)

	_dir_light = DirectionalLight3D.new()
	_dir_light.rotation_degrees = Vector3(-50, 20, 0)
	_dir_light.light_color = Color(0.6, 0.55, 0.5)
	_dir_light.light_energy = 0.5
	_dir_light.shadow_enabled = true
	env.add_child(_dir_light)

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
	_world_environment = e
	_apply_time_of_day_visuals()

func _advance_game_clock(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	var next_clock: Dictionary = _game_clock.advance(_game_day, _game_time, delta_seconds)
	_game_day = int(next_clock.get("day", _game_day))
	_game_time = float(next_clock.get("time", _game_time))
	_sync_game_time_display()

func _set_game_time(day: int, time_of_day: float, show_time := true) -> void:
	_game_day = maxi(day, 1)
	_game_time = clampf(float(time_of_day), 0.0, 1.0)
	if _hud != null:
		if show_time:
			_hud.show_time(_game_day, _game_time)
		else:
			_hud.hide_time()
	_apply_time_of_day_visuals()

func _sync_game_time_display() -> void:
	if _hud != null:
		_hud.set_time(_game_day, _game_time)
	_apply_time_of_day_visuals()

func _apply_time_of_day_visuals() -> void:
	if _dir_light == null or _world_environment == null:
		return

	var normalized := clampf(_game_time, 0.0, 1.0)
	if normalized < DayNightCycleScript.NIGHT_START:
		var dusk_blend := clampf(normalized / DayNightCycleScript.NIGHT_START, 0.0, 1.0)
		_world_environment.background_color = Color(0.06, 0.07, 0.09).lerp(Color(0.12, 0.08, 0.06), dusk_blend)
		_world_environment.ambient_light_color = Color(0.32, 0.34, 0.38).lerp(Color(0.42, 0.31, 0.23), dusk_blend)
		_world_environment.ambient_light_energy = lerpf(0.48, 0.26, dusk_blend)
		_world_environment.glow_intensity = lerpf(0.22, 0.34, dusk_blend)
		_dir_light.light_color = Color(0.7, 0.73, 0.78).lerp(Color(0.92, 0.52, 0.24), dusk_blend)
		_dir_light.light_energy = lerpf(0.72, 0.24, dusk_blend)
		return

	var night_blend := clampf((normalized - DayNightCycleScript.NIGHT_START) / DayNightCycleScript.SEGMENT_SPAN, 0.0, 1.0)
	_world_environment.background_color = Color(0.03, 0.03, 0.05).lerp(Color(0.01, 0.012, 0.02), night_blend)
	_world_environment.ambient_light_color = Color(0.12, 0.14, 0.2).lerp(Color(0.05, 0.06, 0.09), night_blend)
	_world_environment.ambient_light_energy = lerpf(0.16, 0.06, night_blend)
	_world_environment.glow_intensity = lerpf(0.32, 0.14, night_blend)
	_dir_light.light_color = Color(0.24, 0.34, 0.54).lerp(Color(0.1, 0.14, 0.26), night_blend)
	_dir_light.light_energy = lerpf(0.14, 0.04, night_blend)

func _add_iron_patch(parent: Node3D, pos: Vector3) -> void:
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

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.5, 0)
	light.light_color = Color(0.7, 0.25, 0.05)
	light.light_energy = 2.0
	light.omni_range = 4.0
	parent.add_child(light)
	_iron_lights.append(light)

	var lbl := Label3D.new()
	lbl.text = "Fe"
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.1, 0.5)
	lbl.position = pos + Vector3(0, 0.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

func _add_detour_markers(parent: Node3D, iron_pos: Vector3, waypoint: Vector3, count: int) -> void:
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
	_add_wall(parent, pos + Vector3(0, 1.0, -2.5), Vector3(3, 2, 0.2), Color(0.14, 0.13, 0.12))
	_add_wall(parent, pos + Vector3(0, 1.0, 2.5), Vector3(3, 2, 0.2), Color(0.14, 0.13, 0.12))
	_add_wall(parent, pos + Vector3(1.5, 1.0, 0), Vector3(0.2, 2, 5), Color(0.14, 0.13, 0.12))
	_add_wall(parent, pos + Vector3(0, 2.0, 0), Vector3(3, 0.15, 5), Color(0.12, 0.11, 0.1))

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.5, 0)
	light.light_color = Color(0.8, 0.6, 0.35)
	light.light_energy = 2.5
	light.omni_range = 5.0
	parent.add_child(light)

	var lbl := Label3D.new()
	lbl.text = "SHELTER"
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.4, 0.5, 0.7, 0.6)
	lbl.position = pos + Vector3(0, 2.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

# --- Decorations ---

func _build_decorations() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	# Exposed vasculature.
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.18, 0.1, 0.08)
	pipe_mat.roughness = 0.6
	# Main artery along the corridor
	var artery := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.15
	ac.bottom_radius = 0.15
	ac.height = 44.0
	artery.mesh = ac
	artery.material_override = pipe_mat
	artery.position = Vector3(22, 2.7, -2.0)
	artery.rotation.z = PI / 2.0
	env_node.add_child(artery)
	# Branching capillaries
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.2, 0.1, 0.07)
	for i in range(8):
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.04
		cc.bottom_radius = 0.06
		cc.height = 3.0 + fmod(i * 1.3, 2.0)
		cap.mesh = cc
		cap.material_override = cap_mat
		cap.position = Vector3(3.0 + i * 5.0, 2.7, -2.0)
		cap.rotation.x = PI / 2.0
		cap.rotation.z = 0.3 * (1 if i % 2 == 0 else -1)
		env_node.add_child(cap)

	# Iron deposit growths.
	var rust_mat := StandardMaterial3D.new()
	rust_mat.albedo_color = Color(0.4, 0.15, 0.05)
	rust_mat.emission_enabled = true
	rust_mat.emission = Color(0.2, 0.06, 0.02)
	rust_mat.emission_energy_multiplier = 0.3
	rust_mat.roughness = 0.9
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x]:
		for j in range(5):
			var nodule := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.08 + fmod(j * 0.7, 0.12)
			sp.height = sp.radius * 1.6
			nodule.mesh = sp
			nodule.material_override = rust_mat
			var side := 1.0 if j % 2 == 0 else -1.0
			nodule.position = Vector3(
				iron_x - 1.5 + j * 0.8,
				0.3 + fmod(j * 0.5, 0.6),
				side * 7.8
			)
			env_node.add_child(nodule)

	# Support struts.
	var strut_mat := StandardMaterial3D.new()
	strut_mat.albedo_color = Color(0.1, 0.1, 0.12)
	for i in range(6):
		var strut := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.1, 2.5, 0.1)
		strut.mesh = sb
		strut.material_override = strut_mat
		strut.position = Vector3(5.0 + i * 7.0, 1.5, -7.8)
		strut.rotation.z = 0.2
		env_node.add_child(strut)

	# Emergency route beacons.
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.2, 0.4, 0.3)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.15, 0.35, 0.2)
	beacon_mat.emission_energy_multiplier = 1.5
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var beacon_positions := [
		SAFE_1_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_1_WAYPOINT,
		SAFE_1_WAYPOINT + Vector3(2, 0, 0),
		SAFE_2_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_2_WAYPOINT,
		SAFE_2_WAYPOINT + Vector3(2, 0, 0),
	]
	for bpos in beacon_positions:
		var beacon := MeshInstance3D.new()
		var bsp := SphereMesh.new()
		bsp.radius = 0.08
		beacon.mesh = bsp
		beacon.material_override = beacon_mat
		beacon.position = bpos + Vector3(0, 0.15, 0)
		env_node.add_child(beacon)

	# Warning signage along the corridor
	var signs := [
		{"pos": Vector3(8, 1.8, -7.8), "text": "CAUTION: Fe CONTAMINATION"},
		{"pos": Vector3(26, 1.8, -7.8), "text": "CAUTION: Fe CONTAMINATION"},
		{"pos": Vector3(38, 1.8, -7.8), "text": "SHELTER  →"},
	]
	for s in signs:
		var sign_bg := MeshInstance3D.new()
		var sgb := BoxMesh.new()
		sgb.size = Vector3(2.4, 0.5, 0.02)
		sign_bg.mesh = sgb
		var sgm := StandardMaterial3D.new()
		sgm.albedo_color = Color(0.12, 0.08, 0.03)
		sign_bg.material_override = sgm
		sign_bg.position = s.pos
		env_node.add_child(sign_bg)
		var lbl := Label3D.new()
		lbl.text = s.text
		lbl.font_size = 24
		lbl.pixel_size = 0.008
		lbl.modulate = Color(0.8, 0.4, 0.15, 0.8)
		lbl.position = s.pos + Vector3(0, 0, -0.02)
		env_node.add_child(lbl)

	# Degradation marks.
	var stain_mat := StandardMaterial3D.new()
	stain_mat.albedo_color = Color(0.06, 0.05, 0.04)
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x]:
		for j in range(3):
			var stain := MeshInstance3D.new()
			var stb := BoxMesh.new()
			stb.size = Vector3(1.5 + j * 0.5, 0.003, 1.0 + j * 0.3)
			stain.mesh = stb
			stain.material_override = stain_mat
			stain.position = Vector3(iron_x + j * 1.5 - 1.0, 0.005, 2.0 - j * 1.5)
			stain.rotation.y = j * 0.4
			env_node.add_child(stain)
