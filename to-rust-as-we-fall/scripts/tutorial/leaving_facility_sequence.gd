@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

## Iron spill tutorial: routing, pressure, Endo join, first shelter rest.

var _routing_mode := "safe"
var _sector_gates_open: Array[bool] = [false, false, false]
var _sector_route_choices: Array[String] = ["", "", ""]
var _sector_gate_visuals: Array[MeshInstance3D] = []
var _sector_route_interactables: Array = []
var _field_site_interactables: Array = []
var _field_protocol_progress: Array[int] = [0, 0, 0]
var _field_protocol_ready: Array[bool] = [false, false, false]
var _field_completed_site_ids: Array[String] = []
var _cache_interactable
var _cache_mesh: Node3D
var _cache_item_id := ""
var _cache_collected := false
var _resource_decision := ""
var _recover_interactable
var _shield_interactable
var _lookout_interactable
var _lookout_surveyed := false
var _third_sector_shielded := false
var _iron_damage_total := 0.0
var _iron_exposure_seconds := 0.0
var _sectors_entered: Array[String] = []

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

# Corridor runs along +X.  The authored route is 210 m from the facility lip to
# Shelter 1.  It is deliberately split into three different iron problems rather
# than stretched with slower movement or timer gates.
const EXIT_POS := Vector3(0, 0, 0)
const IRON_1_POS := Vector3(32, 0, 0)
const SAFE_1_WAYPOINT := Vector3(32, 0, -11)
const SAFE_1_END := Vector3(48, 0, 0)
const MIDPOINT := Vector3(69, 0, 0)
const IRON_2_POS := Vector3(91, 0, -1)
const SAFE_2_WAYPOINT := Vector3(91, 0, 11)
const SAFE_2_END := Vector3(114, 0, 0)
const IRON_3_POS := Vector3(151, 0, 1)
const SAFE_3_WAYPOINT := Vector3(151, 0, -11)
const SAFE_3_END := Vector3(177, 0, 0)
const SHELTER_POS := Vector3(210, 0, 0)

const CORRIDOR_X_MIN := -4.0
const CORRIDOR_X_MAX := 218.0
const CORRIDOR_HALF_WIDTH := 15.0
const CORRIDOR_LENGTH := CORRIDOR_X_MAX - CORRIDOR_X_MIN
const CACHE_POS := Vector3(65, 0, 11.5)
const RESOURCE_MANIFOLD_POS := Vector3(123, 0, 6.5)
const LOOKOUT_POS := Vector3(129, 0, -11.5)
const IRON_DAMAGE_PER_SEC := 1.7
const SCOUTED_DAMAGE_MULTIPLIER := 0.55
const ROUTE_REGROUP_RADIUS := 8.0
const FIELD_ROLE_RADIUS := 9.0
const FIELD_SITE_WORK_SECONDS := 8.0
const MODELED_FIXED_TRANSITION_SECONDS := 12.5

# Each sector owns one recoverable risk field and a route seal.  Cautious routing
# pays the longer marked detour; direct routing crosses the field and pays HP.
# The seal has a station on both lanes, so the chosen route is an authored action,
# not merely a HUD label.
const IRON_SECTORS := [
	{
		"id": "bleedway",
		"label": "I / BLEEDWAY",
		"center": IRON_1_POS,
		"half_size": Vector2(8.0, 5.5),
		"safe_waypoint": SAFE_1_WAYPOINT,
		"safe_station": Vector3(45, 0, -11),
		"direct_station": Vector3(45, 0, 0),
		"gate_x": 48.0,
		"risk_penalty": 20.0,
	},
	{
		"id": "sump",
		"label": "II / FERRIC SUMP",
		"center": IRON_2_POS,
		"half_size": Vector2(10.0, 7.0),
		"safe_waypoint": SAFE_2_WAYPOINT,
		"safe_station": Vector3(111, 0, 11),
		"direct_station": Vector3(111, 0, 0),
		"gate_x": 114.0,
		"risk_penalty": 24.0,
	},
	{
		"id": "lattice",
		"label": "III / IRON LATTICE",
		"center": IRON_3_POS,
		"half_size": Vector2(12.0, 6.0),
		"safe_waypoint": SAFE_3_WAYPOINT,
		"safe_station": Vector3(174, 0, -11),
		"direct_station": Vector3(174, 0, 0),
		"gate_x": 177.0,
		"risk_penalty": 28.0,
	},
]

# Each iron seal is preceded by an ordered five-station field protocol. The
# stations alternate across the full corridor width: the route becomes a spatial
# read-and-repair problem instead of a long empty walk. Aster issues each click,
# while the named party specialist must physically reach their station before
# its work can resolve. Only the current station is enabled, so the authored
# traversal below is also the honest shortest first-clear route.
const FIELD_PROTOCOLS := [
	{
		"id": "bleedway_stabilization",
		"label": "BLEEDWAY STABILIZATION",
		"sites": [
			{"id": "bleedway_datum", "pos": Vector3(10, 0, -10), "role": "aster", "verb": "TRACE DATUM", "color": Color(0.30, 0.66, 0.92)},
			{"id": "bleedway_runoff", "pos": Vector3(18, 0, 10), "role": "peris", "verb": "SAMPLE RUNOFF", "color": Color(0.84, 0.58, 0.24)},
			{"id": "bleedway_conduit", "pos": Vector3(27, 0, -10), "role": "endo", "verb": "BRACE CONDUIT", "color": Color(0.38, 0.72, 0.55)},
			{"id": "bleedway_filter", "pos": Vector3(36, 0, 10), "role": "peris", "verb": "PACK FILTER", "color": Color(0.84, 0.58, 0.24)},
			{"id": "bleedway_relay", "pos": Vector3(43, 0, -10), "role": "aster", "verb": "ALIGN RELAY", "color": Color(0.30, 0.66, 0.92)},
		],
	},
	{
		"id": "sump_recovery",
		"label": "FERRIC SUMP RECOVERY",
		"sites": [
			{"id": "sump_grate", "pos": Vector3(57, 0, 10), "role": "endo", "verb": "LIFT GRATE", "color": Color(0.38, 0.72, 0.55)},
			{"id": "sump_deposit", "pos": Vector3(68, 0, -10), "role": "peris", "verb": "READ DEPOSIT", "color": Color(0.84, 0.58, 0.24)},
			{"id": "sump_bus", "pos": Vector3(80, 0, 10), "role": "aster", "verb": "PATCH BUS", "color": Color(0.30, 0.66, 0.92)},
			{"id": "sump_vent", "pos": Vector3(94, 0, -10), "role": "endo", "verb": "VENT SUMP", "color": Color(0.38, 0.72, 0.55)},
			{"id": "sump_flow", "pos": Vector3(106, 0, 10), "role": "peris", "verb": "VERIFY FLOW", "color": Color(0.84, 0.58, 0.24)},
		],
	},
	{
		"id": "lattice_isolation",
		"label": "IRON LATTICE ISOLATION",
		"sites": [
			{"id": "lattice_map", "pos": Vector3(121, 0, -10), "role": "aster", "verb": "MAP LATTICE", "color": Color(0.30, 0.66, 0.92)},
			{"id": "lattice_spine", "pos": Vector3(132, 0, 10), "role": "endo", "verb": "GROUND SPINE", "color": Color(0.38, 0.72, 0.55)},
			{"id": "lattice_seam", "pos": Vector3(145, 0, -10), "role": "peris", "verb": "TREAT SEAM", "color": Color(0.84, 0.58, 0.24)},
			{"id": "lattice_shunt", "pos": Vector3(158, 0, 10), "role": "aster", "verb": "TUNE SHUNT", "color": Color(0.30, 0.66, 0.92)},
			{"id": "lattice_bypass", "pos": Vector3(169, 0, -10), "role": "endo", "verb": "LOCK BYPASS", "color": Color(0.38, 0.72, 0.55)},
		],
	},
]
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
	var environment := get_node_or_null("Environment") as Node3D
	if environment != null:
		# Keep the shared quality pass, but measure it against the rebuilt route
		# rather than the original 50 m prototype corridor.
		LevelDecoratorScript.decorate_profile(environment, "leaving_facility", {
			"x0": CORRIDOR_X_MIN,
			"x1": CORRIDOR_X_MAX,
			"width": CORRIDOR_HALF_WIDTH * 2.0,
			"spacing": 11.5,
			"floor_tint": Color(0.19, 0.20, 0.22),
			"wall_tint": Color(0.25, 0.21, 0.19),
			"landmark_lights": true,
		})

## The corridor floor (222x30, world X[-4,218] Z[-15,15]) is one open plane.
## Iron cells remain walkable risk; only the three authored route seals block progress.
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = Vector3(CORRIDOR_X_MIN, 0.0, -CORRIDOR_HALF_WIDTH)
	_grid.create_room(int(CORRIDOR_LENGTH), int(CORRIDOR_HALF_WIDTH * 2.0), false)
	for sector in IRON_SECTORS:
		var center: Vector3 = sector["center"]
		var half_size: Vector2 = sector["half_size"]
		_grid.set_world_region_risk(
			Vector2(center.x - half_size.x, center.z - half_size.y),
			Vector2(center.x + half_size.x, center.z + half_size.y),
			float(sector["risk_penalty"]), true)
	# A route seal after each field makes the three crossings distinct decisions.
	# Five central cells reopen when either the safe or direct station is worked.
	for sector in IRON_SECTORS:
		_set_gate_grid_open(float(sector["gate_x"]), false)

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
		_bind_camera_to_level_bounds(_grid, 2.0)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, GameState.WALK_SPEED, {"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX})
	_register_gs_character("peris", _peris, 2.5, {"hp": GameState.HP_MAX, "stamina": GameState.STAMINA_MAX})
	_register_gs_character("endo", _endo, 2.5, {"hp": GameState.HP_MAX})
	_game_state.set_route_mode(true)
	_build_route_gameplay()

func _setup_ui() -> void:
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("hp", Color(0.7, 0.3, 0.25), GameState.HP_MAX, GameState.HP_MAX)
	_hud.show_center_camera_button("P")
	if _camera != null and not _hud.center_camera_requested.is_connected(_recenter_party_camera):
		_hud.center_camera_requested.connect(_recenter_party_camera)
	# Bind after _game_state exists; route guards still own toggles.

func _recenter_party_camera() -> void:
	if _camera == null:
		return
	var centroid := Vector3.ZERO
	var visible_count := 0
	for character in [_player, _peris, _endo]:
		if is_instance_valid(character) and character.visible:
			centroid += character.global_position
			visible_count += 1
	if visible_count > 0:
		_camera.recenter_on(centroid / float(visible_count))

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

# --- Route gameplay ---

func _build_route_gameplay() -> void:
	var environment := get_node_or_null("Environment") as Node3D
	if environment == null:
		return
	_sector_route_interactables.clear()
	_field_site_interactables.clear()
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var safe_station := _create_interactable(
			environment, sector["safe_station"], "Sector%dSafeStation" % (sector_index + 1),
			2.0, 3.5, "REGROUP / WORK SAFE SEAL", false, Interactable.InteractableType.TIMED_ACTION)
		safe_station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		safe_station.interacted.connect(
			Callable(self, "_on_sector_route_station_completed").bind(sector_index, "safe"))
		safe_station.interaction_requested.connect(
			Callable(self, "_on_route_station_requested").bind("safe"))
		_add_route_station_mesh(safe_station, Color(0.22, 0.58, 0.42), "SAFE")
		var direct_station := _create_interactable(
			environment, sector["direct_station"], "Sector%dDirectStation" % (sector_index + 1),
			2.0, 2.0, "REGROUP / FORCE DIRECT SEAL", false, Interactable.InteractableType.TIMED_ACTION)
		direct_station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		direct_station.interacted.connect(
			Callable(self, "_on_sector_route_station_completed").bind(sector_index, "direct"))
		direct_station.interaction_requested.connect(
			Callable(self, "_on_route_station_requested").bind("direct"))
		_add_route_station_mesh(direct_station, Color(0.72, 0.24, 0.08), "DIRECT")
		_sector_route_interactables.append([safe_station, direct_station])
		# The seal is the protocol's final decision, not a shortcut around its
		# fieldwork. The low-level commit method stays callable for deterministic
		# compatibility tests, while real clicks arrive through the guarded wrapper.
		safe_station.set_interaction_enabled(false)
		direct_station.set_interaction_enabled(false)

	_build_field_protocol_interactables(environment)

	_cache_interactable = _create_interactable(
		environment, CACHE_POS, "LeavingFacilityCache", 2.0, 2.5, "SALVAGE LYSATE",
		false, Interactable.InteractableType.TIMED_ACTION)
	_cache_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_cache_interactable.interacted.connect(_on_cache_collected)
	_cache_mesh = _add_route_station_mesh(_cache_interactable, Color(0.67, 0.55, 0.25), "CACHE")

	_recover_interactable = _create_interactable(
		environment, RESOURCE_MANIFOLD_POS + Vector3(-1.8, 0, 0), "LysateRecoverStation",
		1.8, 1.5, "METABOLIZE", true, Interactable.InteractableType.TIMED_ACTION)
	_recover_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_recover_interactable.interacted.connect(Callable(self, "_resolve_resource_decision").bind("recover"))
	_add_route_station_mesh(_recover_interactable, Color(0.48, 0.7, 0.35), "RECOVER")
	_recover_interactable.set_interaction_enabled(false)

	_shield_interactable = _create_interactable(
		environment, RESOURCE_MANIFOLD_POS + Vector3(1.8, 0, 0), "LysateShieldStation",
		1.8, 1.5, "PRIME SHUNT", true, Interactable.InteractableType.TIMED_ACTION)
	_shield_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_shield_interactable.interacted.connect(Callable(self, "_resolve_resource_decision").bind("shield"))
	_add_route_station_mesh(_shield_interactable, Color(0.28, 0.62, 0.7), "SHIELD")
	_shield_interactable.set_interaction_enabled(false)

	_lookout_interactable = _create_interactable(
		environment, LOOKOUT_POS, "IronLookoutSurvey", 2.0, 3.0, "SURVEY LATTICE",
		true, Interactable.InteractableType.TIMED_ACTION)
	_lookout_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_lookout_interactable.interacted.connect(_on_lookout_surveyed)
	_add_route_station_mesh(_lookout_interactable, Color(0.36, 0.68, 0.74), "LOOKOUT")

func _build_field_protocol_interactables(environment: Node3D) -> void:
	for sector_index in range(FIELD_PROTOCOLS.size()):
		var protocol: Dictionary = FIELD_PROTOCOLS[sector_index]
		var sector_sites: Array = []
		var sites: Array = protocol["sites"]
		for site_index in range(sites.size()):
			var site: Dictionary = sites[site_index]
			var role := str(site["role"])
			var verb := str(site["verb"])
			var station := _create_interactable(
				environment,
				site["pos"],
				"Sector%dProtocol%d" % [sector_index + 1, site_index + 1],
				2.0,
				FIELD_SITE_WORK_SECONDS,
				"%s / %s" % [role.to_upper(), verb],
				false,
				Interactable.InteractableType.TIMED_ACTION
			)
			station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
			station.set("description", "%s: %s" % [role.capitalize(), verb.to_lower()])
			station.set_meta("field_site_id", str(site["id"]))
			station.set_meta("field_role", role)
			station.interacted.connect(
				Callable(self, "_on_field_site_completed").bind(sector_index, site_index))
			station.interaction_requested.connect(
				Callable(self, "_on_field_site_requested").bind(sector_index, site_index))
			var assembly := _add_route_station_mesh(
				station, site["color"], "%s %d" % [role.to_upper(), site_index + 1])
			_add_field_station_detail(assembly, role, site_index)
			station.set_interaction_enabled(false)
			sector_sites.append(station)
		_field_site_interactables.append(sector_sites)
	_activate_field_protocol(0)

func _add_field_station_detail(assembly: Node3D, role: String, site_index: int) -> void:
	# Distinct silhouettes let the player read who owns the next task before the
	# label is legible: Aster gets a data vane, Peris sample wells, Endo a brace.
	var detail_mat := StandardMaterial3D.new()
	detail_mat.albedo_color = Color(0.17, 0.19, 0.21)
	detail_mat.metallic = 0.55
	detail_mat.roughness = 0.42
	if role == "aster":
		var vane := MeshInstance3D.new()
		vane.name = "DataVane"
		var vane_mesh := BoxMesh.new()
		vane_mesh.size = Vector3(0.08, 0.82, 0.62)
		vane.mesh = vane_mesh
		vane.material_override = detail_mat
		vane.position = Vector3(0, 1.25, 0)
		vane.rotation.y = float(site_index) * 0.16
		assembly.add_child(vane)
	elif role == "peris":
		for well_index in range(3):
			var well := MeshInstance3D.new()
			well.name = "SampleWell%d" % well_index
			var well_mesh := CylinderMesh.new()
			well_mesh.top_radius = 0.10
			well_mesh.bottom_radius = 0.13
			well_mesh.height = 0.38 + 0.08 * well_index
			well.mesh = well_mesh
			well.material_override = detail_mat
			well.position = Vector3(-0.24 + well_index * 0.24, 1.20, 0)
			assembly.add_child(well)
	else:
		for side_index in range(2):
			var side := -1.0 if side_index == 0 else 1.0
			var brace := MeshInstance3D.new()
			brace.name = "LoadBrace%d" % (side_index + 1)
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.12, 0.75, 0.12)
			brace.mesh = brace_mesh
			brace.material_override = detail_mat
			brace.position = Vector3(side * 0.31, 1.18, 0)
			brace.rotation.z = side * 0.32
			assembly.add_child(brace)

func _add_route_station_mesh(interactable: Node3D, color: Color, station_label: String) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "%sAssembly" % station_label.capitalize()
	interactable.add_child(assembly)
	var plinth := MeshInstance3D.new()
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 0.42
	plinth_mesh.bottom_radius = 0.58
	plinth_mesh.height = 0.85
	plinth.mesh = plinth_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.45)
	mat.metallic = 0.35
	mat.roughness = 0.62
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	plinth.material_override = mat
	plinth.position.y = 0.43
	assembly.add_child(plinth)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.68, 0.16, 0.52)
	plate.mesh = plate_mesh
	plate.material_override = mat
	plate.position = Vector3(0, 0.95, 0)
	assembly.add_child(plate)
	var label := Label3D.new()
	label.text = station_label
	label.font_size = 28
	label.pixel_size = 0.009
	label.modulate = color.lightened(0.25)
	label.outline_modulate = Color(0.025, 0.025, 0.03, 0.95)
	label.outline_size = 9
	label.position = Vector3(0, 1.48, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	assembly.add_child(label)
	# Route gameplay is built before the shared outline manager exists. Bind on
	# the deferred frame so every visible station still gets object-level hover
	# and click feedback through the common tutorial outline system.
	call_deferred("_bind_route_station_outline", interactable, assembly, station_label)
	return assembly

func _bind_route_station_outline(interactable: Node3D, assembly: Node3D, station_label: String) -> void:
	if not is_instance_valid(interactable) or not is_instance_valid(assembly):
		return
	var target := _outline_object_meshes(
		interactable, "%sOutline" % station_label.capitalize(),
		_collect_mesh_instances(assembly), "leaving_facility.%s" % station_label.to_lower(), 0.8)
	_set_room_target_interaction_delegate(target, interactable)

func _activate_field_protocol(sector_index: int) -> void:
	if sector_index < 0 or sector_index >= _field_site_interactables.size():
		return
	if _field_protocol_ready[sector_index]:
		return
	var site_index := _field_protocol_progress[sector_index]
	var sector_sites: Array = _field_site_interactables[sector_index]
	if site_index < 0 or site_index >= sector_sites.size():
		return
	var station: Node = sector_sites[site_index]
	station.set_interaction_enabled(true)
	station.call_deferred("show_tutorial_label")
	if _hud != null:
		var protocol: Dictionary = FIELD_PROTOCOLS[sector_index]
		var site: Dictionary = (protocol["sites"] as Array)[site_index]
		_hud.show_message("%s %d/%d: %s needs to %s." % [
			str(protocol["label"]), site_index + 1, sector_sites.size(),
			str(site["role"]).capitalize(), str(site["verb"]).to_lower()], 3.2)

func _on_field_site_requested(
		_target: Node,
		world_position: Vector3,
		sector_index: int,
		site_index: int
	) -> void:
	if sector_index < 0 or sector_index >= FIELD_PROTOCOLS.size():
		return
	var sites: Array = FIELD_PROTOCOLS[sector_index]["sites"]
	if site_index < 0 or site_index >= sites.size():
		return
	var role := str((sites[site_index] as Dictionary)["role"])
	if _game_state != null and role != "aster":
		# The specialist walks to a free side of the instrument while Aster's
		# shared interaction controller approaches the click point itself.
		var side := -1.0 if site_index % 2 == 0 else 1.0
		_game_state.command_move_to_pos(role, world_position + Vector3(0, 0, side * 1.25))

func _on_field_site_completed(sector_index: int, site_index: int) -> void:
	if sector_index < 0 or sector_index >= FIELD_PROTOCOLS.size():
		return
	if _field_protocol_ready[sector_index] or site_index != _field_protocol_progress[sector_index]:
		return
	var sites: Array = FIELD_PROTOCOLS[sector_index]["sites"]
	if site_index < 0 or site_index >= sites.size():
		return
	var site: Dictionary = sites[site_index]
	var role := str(site["role"])
	var site_pos: Vector3 = site["pos"]
	if _game_state == null or _game_state.get_position(role).distance_to(site_pos) > FIELD_ROLE_RADIUS:
		if _hud != null:
			_hud.show_message("%s must reach the marked instrument before the work can resolve." % role.capitalize(), 2.4)
		return

	var station: Node = (_field_site_interactables[sector_index] as Array)[site_index]
	station.set_interaction_enabled(false)
	_field_completed_site_ids.append(str(site["id"]))
	_field_protocol_progress[sector_index] += 1
	_set_field_station_completed_visual(station, role)
	if _field_protocol_progress[sector_index] < sites.size():
		_activate_field_protocol(sector_index)
		return

	_field_protocol_ready[sector_index] = true
	for seal_station in _sector_route_interactables[sector_index]:
		seal_station.set_interaction_enabled(true)
		seal_station.call_deferred("show_tutorial_label")
	if _hud != null:
		_hud.show_message("%s complete. Regroup and choose SAFE or DIRECT at the seal." % str(FIELD_PROTOCOLS[sector_index]["label"]), 3.4)

func _set_field_station_completed_visual(station: Node, role: String) -> void:
	if station == null:
		return
	for label_node in station.find_children("*", "Label3D", true, false):
		var label := label_node as Label3D
		label.text = "DONE / %s" % role.to_upper()
		label.modulate = Color(0.38, 0.63, 0.47, 0.72)

func _on_sector_route_station_completed(sector_index: int, route_choice: String) -> void:
	if sector_index < 0 or sector_index >= _field_protocol_ready.size():
		return
	if not _field_protocol_ready[sector_index]:
		if _hud != null:
			_hud.show_message("Finish this sector's five field stations before working the seal.", 2.5)
		return
	_on_sector_route_committed(sector_index, route_choice)

func _set_gate_grid_open(gate_x: float, opened: bool) -> void:
	if _grid == null:
		return
	var gate_cell := _grid.world_to_grid(Vector3(gate_x, 0, 0))
	if not opened:
		for z in range(_grid.height):
			_grid.set_tile(gate_cell.x, z, GridWorld.Tile.WALL)
		return
	# Keep the sector bulkheads in place and open only the marked central seal.
	for dz in range(-3, 4):
		_grid.set_tile(gate_cell.x, gate_cell.y + dz, GridWorld.Tile.FLOOR)

func _on_route_station_requested(_target: Node, world_position: Vector3, route_choice: String) -> void:
	# The generic interaction controller may have issued its first path during the
	# same click. Re-issue it after applying this station's route mode so the path
	# to SAFE really detours and the path to DIRECT really crosses the risk field.
	_apply_routing_mode(route_choice, false)
	if _game_state != null:
		_game_state.command_move_to_pos("aster", world_position)

func _on_sector_route_committed(sector_index: int, route_choice: String) -> void:
	# Low-level state mutation intentionally remains available to deterministic
	# test drivers. Player clicks use _on_sector_route_station_completed, which
	# enforces the full field protocol before it reaches this method.
	if sector_index < 0 or sector_index >= _sector_gates_open.size():
		return
	if _sector_gates_open[sector_index]:
		return
	var station_pos: Vector3 = IRON_SECTORS[sector_index]["safe_station" if route_choice == "safe" else "direct_station"]
	var missing_party: Array[String] = []
	for char_id in ["aster", "peris", "endo"]:
		if _game_state.get_position(char_id).distance_to(station_pos) > ROUTE_REGROUP_RADIUS:
			missing_party.append(char_id.capitalize())
	if not missing_party.is_empty():
		if _hud != null:
			_hud.show_message("The seal needs the whole party. Regroup with %s." % ", ".join(missing_party), 2.3)
		return
	_sector_gates_open[sector_index] = true
	_sector_route_choices[sector_index] = route_choice
	_apply_routing_mode(route_choice, false)
	_set_gate_grid_open(float(IRON_SECTORS[sector_index]["gate_x"]), true)
	for interactable in _sector_route_interactables[sector_index]:
		if interactable != null:
			interactable.set_interaction_enabled(false)
	if sector_index < _sector_gate_visuals.size() and _sector_gate_visuals[sector_index] != null:
		_sector_gate_visuals[sector_index].visible = false
	if _hud != null:
		_hud.show_message("%s seal opened via %s route." % [
			str(IRON_SECTORS[sector_index]["label"]), route_choice.to_upper()], 2.0)
	if sector_index + 1 < FIELD_PROTOCOLS.size():
		_activate_field_protocol(sector_index + 1)

func _on_cache_collected() -> void:
	if _cache_collected:
		return
	_cache_item_id = _game_state.spawn_item("lysate", CACHE_POS, {
		"display_name": "Iron-route Lysate",
		"visual_color": Color(0.72, 0.64, 0.34),
		"atp_restore": 2.0,
	})
	if not _game_state.pick_up_item("aster", _cache_item_id):
		_game_state.remove_item(_cache_item_id)
		_cache_item_id = ""
		if _hud != null:
			_hud.show_message("Aster needs a free hand for the lysate.", 1.8)
		return
	_cache_collected = true
	if _cache_mesh != null:
		_cache_mesh.visible = false
	_cache_interactable.set_interaction_enabled(false)
	for decision in [_recover_interactable, _shield_interactable]:
		decision.set_interaction_enabled(true)
		decision.call_deferred("show_tutorial_label")
	if _hud != null:
		_hud.show_message("Lysate secured: metabolize it now, or prime the Iron Lattice shunt.", 3.2)

func _resolve_resource_decision(decision: String) -> void:
	if _resource_decision != "":
		return
	if _cache_item_id == "" or not _game_state.items.has(_cache_item_id):
		if _hud != null:
			_hud.show_message("The manifold needs the side-cache lysate.", 1.8)
		return
	var item: Dictionary = _game_state.items[_cache_item_id]
	if str(item.get("holder", "")) != "aster":
		if _hud != null:
			_hud.show_message("Aster must be carrying the lysate.", 1.8)
		return
	_resource_decision = decision
	_game_state.remove_item(_cache_item_id)
	_cache_item_id = ""
	if decision == "recover":
		_game_state.adjust_stat("aster", "hp", 24.0)
		_game_state.adjust_stat("aster", "stamina", 20.0)
		if _hud != null:
			_hud.show_message("Aster metabolizes the lysate: health and stamina restored.", 2.4)
	else:
		_third_sector_shielded = true
		_clear_sector_risk(2)
		if _hud != null:
			_hud.show_message("Lysate floods the shunt. The Iron Lattice direct line is cold.", 2.6)
	for interactable in [_recover_interactable, _shield_interactable]:
		interactable.set_interaction_enabled(false)

func _clear_sector_risk(sector_index: int) -> void:
	if _grid == null or sector_index < 0 or sector_index >= IRON_SECTORS.size():
		return
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var center: Vector3 = sector["center"]
	var half_size: Vector2 = sector["half_size"]
	var a := _grid.world_to_grid(Vector3(center.x - half_size.x, 0, center.z - half_size.y))
	var b := _grid.world_to_grid(Vector3(center.x + half_size.x, 0, center.z + half_size.y))
	for z in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			_grid.clear_cell_risk(Vector2i(x, z))

func _on_lookout_surveyed() -> void:
	if _lookout_surveyed:
		return
	_lookout_surveyed = true
	_lookout_interactable.set_interaction_enabled(false)
	if _hud != null:
		_hud.show_message("Lookout mapped: Iron Lattice exposure reduced by 45%.", 2.5)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"facility_exit": EXIT_POS,
		"sector_1_iron": IRON_1_POS,
		"sector_1_safe": SAFE_1_WAYPOINT,
		"sector_1_gate": Vector3(float(IRON_SECTORS[0]["gate_x"]), 0, 0),
		"side_cache": CACHE_POS,
		"sector_2_iron": IRON_2_POS,
		"sector_2_safe": SAFE_2_WAYPOINT,
		"sector_2_gate": Vector3(float(IRON_SECTORS[1]["gate_x"]), 0, 0),
		"resource_manifold": RESOURCE_MANIFOLD_POS,
		"lookout": LOOKOUT_POS,
		"sector_3_iron": IRON_3_POS,
		"sector_3_safe": SAFE_3_WAYPOINT,
		"sector_3_gate": Vector3(float(IRON_SECTORS[2]["gate_x"]), 0, 0),
		"shelter": SHELTER_POS,
	}
	var protocol_anchors := {}
	for protocol in FIELD_PROTOCOLS:
		var site_anchors := {}
		for site in protocol["sites"]:
			site_anchors[str(site["id"])] = site["pos"]
		protocol_anchors[str(protocol["id"])] = site_anchors
	anchors["field_protocols"] = protocol_anchors
	return anchors

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	state.merge({
		"routing_mode": _routing_mode,
		"route_cautious": _game_state.is_route_cautious() if _game_state != null else true,
		"sector_gates_open": _sector_gates_open.duplicate(),
		"sector_route_choices": _sector_route_choices.duplicate(),
		"field_protocol_progress": _field_protocol_progress.duplicate(),
		"field_protocol_ready": _field_protocol_ready.duplicate(),
		"field_completed_site_ids": _field_completed_site_ids.duplicate(),
		"field_protocol_count": FIELD_PROTOCOLS.size(),
		"mandatory_field_site_count": _mandatory_field_site_count(),
		"sectors_entered": _sectors_entered.duplicate(),
		"cache_collected": _cache_collected,
		"cache_item_id": _cache_item_id,
		"resource_decision": _resource_decision,
		"lookout_surveyed": _lookout_surveyed,
		"third_sector_shielded": _third_sector_shielded,
		"iron_damage_total": _iron_damage_total,
		"iron_exposure_seconds": _iron_exposure_seconds,
		"authored_route_meters": SHELTER_POS.x - EXIT_POS.x,
		"sector_count": IRON_SECTORS.size(),
		"optional_branch_count": 2,
		"route_regroup_radius": ROUTE_REGROUP_RADIUS,
	}, true)
	return state

func _mandatory_field_site_count() -> int:
	var count := 0
	for protocol in FIELD_PROTOCOLS:
		count += (protocol["sites"] as Array).size()
	return count

func _mandatory_field_work_seconds() -> float:
	return float(_mandatory_field_site_count()) * FIELD_SITE_WORK_SECONDS

func _modeled_field_route_meters(route_choice := "direct") -> float:
	var total := 0.0
	var cursor := EXIT_POS
	for sector_index in range(FIELD_PROTOCOLS.size()):
		var protocol: Dictionary = FIELD_PROTOCOLS[sector_index]
		for site in protocol["sites"]:
			var site_pos: Vector3 = site["pos"]
			total += cursor.distance_to(site_pos)
			cursor = site_pos
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var station_pos: Vector3 = sector["safe_station" if route_choice == "safe" else "direct_station"]
		total += cursor.distance_to(station_pos)
		cursor = station_pos
		var gate_pos := Vector3(float(sector["gate_x"]), 0, 0)
		total += cursor.distance_to(gate_pos)
		cursor = gate_pos
	total += cursor.distance_to(SHELTER_POS)
	return total

func get_playtime_contract() -> Dictionary:
	# Lower-bound first-clear model. It includes only authored movement, real timed
	# work, and fixed transitions; dialogue reading time is deliberately excluded.
	# The sprint allowance uses the live full-stamina economy (100 / 15 s drain at
	# 6 m/s = 40 m). Everything after that is priced at the live 3 m/s walk speed.
	var direct_field_route_meters := _modeled_field_route_meters("direct")
	var safe_field_route_meters := _modeled_field_route_meters("safe")
	var run_drain := 15.0
	if _game_state != null:
		run_drain = maxf(0.001, float(_game_state.run_stamina_drain_per_sec))
	var sprint_seconds_available := GameState.STAMINA_MAX / run_drain
	var sprint_distance := minf(direct_field_route_meters, sprint_seconds_available * GameState.RUN_SPEED)
	var traversal_seconds := (
		sprint_distance / GameState.RUN_SPEED
		+ (direct_field_route_meters - sprint_distance) / GameState.WALK_SPEED
	)
	var field_work_seconds := _mandatory_field_work_seconds()
	var direct_seal_work_seconds := float(IRON_SECTORS.size()) * 2.0
	var mandatory_interaction_seconds := field_work_seconds + direct_seal_work_seconds
	var active_seconds := traversal_seconds + mandatory_interaction_seconds
	var modeled_total_seconds := active_seconds + MODELED_FIXED_TRANSITION_SECONDS
	return {
		"target_minutes": Vector2(4.0, 6.0),
		"target_first_clear_seconds": Vector2(240.0, 360.0),
		"modeled_shortest_clean_first_clear_seconds": modeled_total_seconds,
		"modeled_meaningful_active_seconds": active_seconds,
		"meaningful_active_seconds": active_seconds,
		"total_play_seconds": modeled_total_seconds,
		"modeled_active_ratio": active_seconds / modeled_total_seconds,
		"modeled_traversal_seconds": traversal_seconds,
		"modeled_mandatory_interaction_seconds": mandatory_interaction_seconds,
		"modeled_field_work_seconds": field_work_seconds,
		"modeled_direct_seal_work_seconds": direct_seal_work_seconds,
		"modeled_fixed_transition_seconds": MODELED_FIXED_TRANSITION_SECONDS,
		"dialogue_seconds_in_model": 0.0,
		"idle_padding_seconds": 0.0,
		"model_basis": "shortest ordered direct protocol route; one full stamina bar; dialogue excluded",
		"critical_route_meters": SHELTER_POS.x - EXIT_POS.x,
		"shortest_field_route_meters": direct_field_route_meters,
		"safe_field_route_estimate_meters": safe_field_route_meters,
		"direct_route_estimate_meters": direct_field_route_meters,
		"sprint_distance_allowance_meters": sprint_distance,
		"mandatory_field_protocols": FIELD_PROTOCOLS.size(),
		"mandatory_field_actions": _mandatory_field_site_count(),
		"mandatory_seal_actions": IRON_SECTORS.size(),
		"mandatory_route_actions": _mandatory_field_site_count() + IRON_SECTORS.size(),
		"mandatory_party_regroups": IRON_SECTORS.size(),
		"optional_branches": ["lysate_cache", "iron_lookout"],
		"resource_choices": ["recover_now", "shield_iron_lattice"],
		"route_choices_per_sector": ["safe", "direct"],
		"decision_count": IRON_SECTORS.size() + 1,
		"branch_count": IRON_SECTORS.size() + 2,
	}

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
		if not _hud.routing_toggled.is_connected(_on_routing_toggled):
			_hud.routing_toggled.connect(_on_routing_toggled)
		_hud.show_run_toggle(false)
		if not _hud.run_toggled.is_connected(_on_run_toggled):
			_hud.run_toggled.connect(_on_run_toggled)
		_hud.show_message(
			"Reach Shelter 1. Follow each numbered field protocol, then regroup and choose SAFE or DIRECT at its seal.",
			6.0
		)
		# Registration activates the first station before the HUD exists; repeat its
		# actionable assignment once play and input are live.
		_activate_field_protocol(0)
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
	# The REAL rest mechanism: the shelter zone is here, the clock is past nightfall, and
	# bedding Aster down triggers the night skip (which heals and lands the clock on dawn).
	var aster_pos := _game_state.get_position("aster")
	_game_state.add_shelter_region(
		Vector2(aster_pos.x - 3.0, aster_pos.z - 3.0), Vector2(aster_pos.x + 3.0, aster_pos.z + 3.0))
	_game_state.set_game_clock(_game_day, 0.55)
	# BOTH dawn paths arm (first one wins; _start_dawn re-entry is step-guarded): the night skip
	# fires only when EVERY conscious character sleeps — Endo at full HP can't rest, so the skip
	# may never come and the narrative beat must still reach dawn (the contract driver caught the
	# deadlock when only the rest-refused branch had the fallback).
	_game_state.night_skipped.connect(
		func(_day): _scheduler.schedule_after(0.5, _start_dawn, "dawn"), CONNECT_ONE_SHOT)
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_dawn, "dawn"),
		CONNECT_ONE_SHOT
	)
	_game_state.command_rest("aster")

func _start_dawn() -> void:
	if _current_step != "first_rest":
		return
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

func _on_run_toggled(_running: bool) -> void:
	_toggle_run()

func _on_routing_toggled(mode: String) -> void:
	_apply_routing_mode(mode, true)

func _apply_routing_mode(mode: String, announce := false) -> void:
	_routing_mode = "direct" if mode == "direct" else "safe"
	if _game_state != null:
		_game_state.set_route_mode(_routing_mode == "safe")
	if _hud != null:
		_hud.set_routing_mode(_routing_mode)
		if announce:
			var explanation := "marked detours avoid recoverable iron" if _routing_mode == "safe" else "short lines cross iron and cost party health"
			_hud.show_message("%s routing: %s." % [_routing_mode.capitalize(), explanation], 2.2)

func _toggle_routing() -> void:
	_apply_routing_mode("direct" if _routing_mode == "safe" else "safe", true)

# --- Iron damage ---

func _check_iron_damage(game_delta: float) -> void:
	var aster_pos := _game_state.get_position("aster")
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		var center: Vector3 = sector["center"]
		var half_size: Vector2 = sector["half_size"]
		var sector_active := false
		if abs(aster_pos.x - center.x) <= half_size.x + 2.0 and not _sectors_entered.has(str(sector["id"])):
			_sectors_entered.append(str(sector["id"]))
			if _hud != null:
				_hud.show_message("%s: SAFE follows the outer beacons; DIRECT crosses the iron." % str(sector["label"]), 3.0)
		for char_id in ["aster", "peris", "endo"]:
			var pos := _game_state.get_position(char_id)
			if abs(pos.x - center.x) > half_size.x or abs(pos.z - center.z) > half_size.y:
				continue
			if sector_index == 2 and _third_sector_shielded:
				continue
			sector_active = true
			var multiplier := SCOUTED_DAMAGE_MULTIPLIER if sector_index == 2 and _lookout_surveyed else 1.0
			if char_id == "endo":
				multiplier *= 1.15
			var damage := IRON_DAMAGE_PER_SEC * multiplier * game_delta
			_game_state.adjust_stat(char_id, "hp", -damage)
			_iron_damage_total += damage
			_iron_exposure_seconds += game_delta
		if sector_active and sector_index < _iron_lights.size():
			var light := _iron_lights[sector_index]
			light.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.01) * 1.5  # @rendering_only — iron light pulse

# --- Environment ---

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(CORRIDOR_LENGTH, 0.1, CORRIDOR_HALF_WIDTH * 2.0)
	ground.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.1, 0.1, 0.12)
	ground.material_override = gm
	ground.position = Vector3((CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5, -0.05, 0)
	env.add_child(ground)

	var fbody := StaticBody3D.new()
	fbody.position = Vector3((CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5, -0.01, 0)
	fbody.collision_layer = 1
	fbody.collision_mask = 0
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(CORRIDOR_LENGTH, 0.02, CORRIDOR_HALF_WIDTH * 2.0)
	fcol.shape = fshape
	fbody.add_child(fcol)
	env.add_child(fbody)

	var wc := Color(0.13, 0.12, 0.14)
	var corridor_center_x := (CORRIDOR_X_MIN + CORRIDOR_X_MAX) * 0.5
	_add_wall(env, Vector3(corridor_center_x, 1.5, -CORRIDOR_HALF_WIDTH), Vector3(CORRIDOR_LENGTH, 3, 0.3), wc)
	_add_wall(env, Vector3(corridor_center_x, 1.5, CORRIDOR_HALF_WIDTH), Vector3(CORRIDOR_LENGTH, 3, 0.3), wc)
	_add_wall(env, Vector3(CORRIDOR_X_MIN, 1.5, 0), Vector3(0.4, 3, CORRIDOR_HALF_WIDTH * 2.0), Color(0.08, 0.08, 0.1))

	_add_shelter(env, SHELTER_POS)
	for sector_index in range(IRON_SECTORS.size()):
		var sector: Dictionary = IRON_SECTORS[sector_index]
		_add_iron_patch(env, sector["center"], sector["half_size"], str(sector["label"]))
		_add_detour_markers(env, sector["center"], sector["safe_waypoint"], 7)
		_add_detour_markers(env, sector["safe_waypoint"], sector["safe_station"], 7)
		_add_sector_gate_visual(env, sector_index)
		_add_sector_identity(env, sector_index)
	_add_side_branch_markers(env)
	_add_protocol_measurement_datums(env)

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
		# WebGL's linear lighting renders the old dusk floor almost black. Keep the
		# atmosphere, but preserve enough fill to read route seams and interactables.
		_world_environment.ambient_light_energy = lerpf(0.58, 0.40, dusk_blend)
		_world_environment.glow_intensity = lerpf(0.22, 0.34, dusk_blend)
		_dir_light.light_color = Color(0.7, 0.73, 0.78).lerp(Color(0.92, 0.52, 0.24), dusk_blend)
		_dir_light.light_energy = lerpf(0.86, 0.42, dusk_blend)
		return

	var night_blend := clampf((normalized - DayNightCycleScript.NIGHT_START) / DayNightCycleScript.SEGMENT_SPAN, 0.0, 1.0)
	_world_environment.background_color = Color(0.03, 0.03, 0.05).lerp(Color(0.01, 0.012, 0.02), night_blend)
	_world_environment.ambient_light_color = Color(0.12, 0.14, 0.2).lerp(Color(0.05, 0.06, 0.09), night_blend)
	_world_environment.ambient_light_energy = lerpf(0.24, 0.12, night_blend)
	_world_environment.glow_intensity = lerpf(0.32, 0.14, night_blend)
	_dir_light.light_color = Color(0.24, 0.34, 0.54).lerp(Color(0.1, 0.14, 0.26), night_blend)
	_dir_light.light_energy = lerpf(0.22, 0.08, night_blend)

func _add_iron_patch(parent: Node3D, pos: Vector3, half_size := Vector2(2.0, 2.0), sector_label := "Fe") -> void:
	var patch := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(half_size.x * 2.0, 0.02, half_size.y * 2.0)
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
	light.omni_range = maxf(7.0, minf(14.0, maxf(half_size.x, half_size.y) + 2.0))
	parent.add_child(light)
	_iron_lights.append(light)

	var lbl := Label3D.new()
	lbl.text = sector_label
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.1, 0.5)
	lbl.position = pos + Vector3(0, 0.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)

func _add_sector_gate_visual(parent: Node3D, sector_index: int) -> void:
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var gate_x := float(sector["gate_x"])
	# Side pylons frame the only traversable opening. The gate panel is visual;
	# GridWorld owns the actual seal so headless and rendered play agree.
	_add_wall(parent, Vector3(gate_x, 1.45, -9.2), Vector3(0.45, 2.9, 11.6), Color(0.11, 0.1, 0.1))
	_add_wall(parent, Vector3(gate_x, 1.45, 9.2), Vector3(0.45, 2.9, 11.6), Color(0.11, 0.1, 0.1))
	var panel := MeshInstance3D.new()
	panel.name = "SectorGate%d" % (sector_index + 1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.38, 2.5, 6.0)
	panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.12, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.2, 0.04)
	mat.emission_energy_multiplier = 0.25
	panel.material_override = mat
	panel.position = Vector3(gate_x, 1.25, 0)
	parent.add_child(panel)
	_sector_gate_visuals.append(panel)

func _add_sector_identity(parent: Node3D, sector_index: int) -> void:
	var sector: Dictionary = IRON_SECTORS[sector_index]
	var center: Vector3 = sector["center"]
	# Each sector receives a different floor datum, so its route problem reads at
	# camera height before the player reaches the damaging material.
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(float((sector["half_size"] as Vector2).x * 2.0 + 12.0), 0.012, 1.0 + sector_index * 0.35)
	band.mesh = band_mesh
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = [
		Color(0.24, 0.11, 0.055),
		Color(0.18, 0.14, 0.07),
		Color(0.22, 0.08, 0.045),
	][sector_index]
	band.material_override = band_mat
	band.position = center + Vector3(0, 0.012, 0)
	parent.add_child(band)
	var label := Label3D.new()
	label.text = str(sector["label"])
	label.font_size = 42
	label.pixel_size = 0.008
	label.modulate = Color(0.93, 0.52, 0.22, 0.9)
	label.position = Vector3(center.x - float((sector["half_size"] as Vector2).x) - 3.0, 2.25, -CORRIDOR_HALF_WIDTH + 0.35)
	parent.add_child(label)

func _add_protocol_measurement_datums(parent: Node3D) -> void:
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.17, 0.36, 0.34, 0.78)
	grid_mat.emission_enabled = true
	grid_mat.emission = Color(0.08, 0.28, 0.25)
	grid_mat.emission_energy_multiplier = 0.42
	grid_mat.roughness = 0.68
	var link_mat := StandardMaterial3D.new()
	link_mat.albedo_color = Color(0.36, 0.27, 0.12, 0.82)
	link_mat.emission_enabled = true
	link_mat.emission = Color(0.42, 0.22, 0.06)
	link_mat.emission_energy_multiplier = 0.34
	link_mat.roughness = 0.74
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.16, 0.19, 0.20)
	arch_mat.metallic = 0.45
	arch_mat.roughness = 0.52

	for sector_index in range(FIELD_PROTOCOLS.size()):
		var protocol: Dictionary = FIELD_PROTOCOLS[sector_index]
		var sites: Array = protocol["sites"]
		var first_pos: Vector3 = (sites[0] as Dictionary)["pos"]
		var last_pos: Vector3 = (sites[sites.size() - 1] as Dictionary)["pos"]
		var grid_x0 := first_pos.x - 3.0
		var grid_x1 := last_pos.x + 3.0
		for lane_index in range(3):
			var lane_z := -10.0 + lane_index * 10.0
			_add_floor_measure_strip(
				parent,
				"FieldGridSector%dLane%d" % [sector_index + 1, lane_index + 1],
				Vector3((grid_x0 + grid_x1) * 0.5, 0.019, lane_z),
				Vector3(grid_x1 - grid_x0, 0.012, 0.10),
				grid_mat
			)
		for site_index in range(sites.size()):
			var site: Dictionary = sites[site_index]
			var pos: Vector3 = site["pos"]
			_add_floor_measure_strip(
				parent,
				"FieldDatumSector%dSite%d" % [sector_index + 1, site_index + 1],
				Vector3(pos.x, 0.021, 0),
				Vector3(0.13, 0.014, 25.5),
				grid_mat
			)
			var measure_label := Label3D.new()
			measure_label.name = "FieldMeasureLabelSector%dSite%d" % [sector_index + 1, site_index + 1]
			measure_label.text = "%03d m  /  %s-%d" % [int(pos.x), str(protocol["id"]).to_upper(), site_index + 1]
			measure_label.font_size = 24
			measure_label.pixel_size = 0.0065
			measure_label.modulate = Color(0.49, 0.78, 0.70, 0.84)
			measure_label.outline_modulate = Color(0.02, 0.03, 0.035, 0.95)
			measure_label.outline_size = 7
			measure_label.position = Vector3(pos.x, 0.055, -13.2)
			measure_label.rotation_degrees.x = -90.0
			parent.add_child(measure_label)
			if site_index > 0:
				var previous: Vector3 = (sites[site_index - 1] as Dictionary)["pos"]
				_add_floor_link(
					parent,
					"FieldLinkSector%dSegment%d" % [sector_index + 1, site_index],
					previous,
					pos,
					link_mat
				)
		_add_protocol_arch(parent, sector_index, grid_x0 - 0.8, "Entry", arch_mat)
		_add_protocol_arch(parent, sector_index, grid_x1 + 0.8, "Exit", arch_mat)

func _add_floor_measure_strip(
		parent: Node3D,
		strip_name: String,
		pos: Vector3,
		size: Vector3,
		material: Material
	) -> void:
	var strip := MeshInstance3D.new()
	strip.name = strip_name
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = size
	strip.mesh = strip_mesh
	strip.material_override = material
	strip.position = pos
	parent.add_child(strip)

func _add_floor_link(
		parent: Node3D,
		link_name: String,
		from_pos: Vector3,
		to_pos: Vector3,
		material: Material
	) -> void:
	var delta := to_pos - from_pos
	var link := MeshInstance3D.new()
	link.name = link_name
	var link_mesh := BoxMesh.new()
	link_mesh.size = Vector3(delta.length(), 0.016, 0.16)
	link.mesh = link_mesh
	link.material_override = material
	link.position = from_pos.lerp(to_pos, 0.5) + Vector3(0, 0.024, 0)
	link.rotation.y = -atan2(delta.z, delta.x)
	parent.add_child(link)

func _add_protocol_arch(
		parent: Node3D,
		sector_index: int,
		x_pos: float,
		suffix: String,
		material: Material
	) -> void:
	var arch := Node3D.new()
	arch.name = "ProtocolArchSector%d%s" % [sector_index + 1, suffix]
	arch.position.x = x_pos
	parent.add_child(arch)
	for side in [-1.0, 1.0]:
		var upright := MeshInstance3D.new()
		var upright_mesh := BoxMesh.new()
		upright_mesh.size = Vector3(0.24, 2.7, 0.36)
		upright.mesh = upright_mesh
		upright.material_override = material
		upright.position = Vector3(0, 1.35, side * 13.4)
		arch.add_child(upright)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.28, 0.24, 27.1)
	beam.mesh = beam_mesh
	beam.material_override = material
	beam.position = Vector3(0, 2.64, 0)
	arch.add_child(beam)
	var arch_label := Label3D.new()
	arch_label.text = "%s / %s" % [str(FIELD_PROTOCOLS[sector_index]["label"]), suffix.to_upper()]
	arch_label.font_size = 29
	arch_label.pixel_size = 0.007
	arch_label.modulate = Color(0.68, 0.76, 0.70, 0.82)
	arch_label.outline_modulate = Color(0.02, 0.025, 0.03, 0.95)
	arch_label.outline_size = 8
	arch_label.position = Vector3(0, 2.35, -7.0)
	arch.add_child(arch_label)

func _add_side_branch_markers(parent: Node3D) -> void:
	for branch in [
		{"pos": CACHE_POS, "text": "SIDE CACHE / LYSATE"},
		{"pos": LOOKOUT_POS, "text": "IRON LOOKOUT"},
	]:
		var pos: Vector3 = branch["pos"]
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(4.0, 0.014, 0.22)
		stripe.mesh = stripe_mesh
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.24, 0.44, 0.31)
		stripe_mat.emission_enabled = true
		stripe_mat.emission = Color(0.12, 0.34, 0.2)
		stripe_mat.emission_energy_multiplier = 0.55
		stripe.material_override = stripe_mat
		stripe.position = Vector3(pos.x, 0.015, pos.z)
		parent.add_child(stripe)
		var label := Label3D.new()
		label.text = str(branch["text"])
		label.font_size = 30
		label.pixel_size = 0.007
		label.modulate = Color(0.58, 0.86, 0.67, 0.88)
		label.position = pos + Vector3(0, 1.8, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

func _add_detour_markers(parent: Node3D, iron_pos: Vector3, waypoint: Vector3, count: int) -> void:
	for i in range(count):
		var t := float(i) / float(count - 1) if count > 1 else 0.5
		var pos := iron_pos.lerp(waypoint, t)
		var marker := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(0.6, 0.015, 0.6)
		marker.mesh = mb
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.18, 0.58, 0.36)
		mm.emission_enabled = true
		mm.emission = Color(0.12, 0.48, 0.28)
		mm.emission_energy_multiplier = 1.1
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	ac.height = SHELTER_POS.x - EXIT_POS.x + 2.0
	artery.mesh = ac
	artery.material_override = pipe_mat
	artery.position = Vector3((SHELTER_POS.x + EXIT_POS.x) * 0.5, 2.7, -5.0)
	artery.rotation.z = PI / 2.0
	env_node.add_child(artery)
	# Branching capillaries
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.2, 0.1, 0.07)
	for i in range(24):
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.04
		cc.bottom_radius = 0.06
		cc.height = 3.0 + fmod(i * 1.3, 2.0)
		cap.mesh = cc
		cap.material_override = cap_mat
		cap.position = Vector3(3.0 + i * 8.6, 2.7, -5.0)
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
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x, IRON_3_POS.x]:
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
				side * (CORRIDOR_HALF_WIDTH - 0.2)
			)
			env_node.add_child(nodule)

	# Support struts.
	var strut_mat := StandardMaterial3D.new()
	strut_mat.albedo_color = Color(0.1, 0.1, 0.12)
	for i in range(24):
		var strut := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.1, 2.5, 0.1)
		strut.mesh = sb
		strut.material_override = strut_mat
		strut.position = Vector3(5.0 + i * 8.8, 1.5, -CORRIDOR_HALF_WIDTH + 0.2)
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
		SAFE_3_WAYPOINT + Vector3(-2, 0, 0),
		SAFE_3_WAYPOINT,
		SAFE_3_WAYPOINT + Vector3(2, 0, 0),
	]
	for bpos in beacon_positions:
		var beacon := MeshInstance3D.new()
		var bsp := SphereMesh.new()
		bsp.radius = 0.16
		bsp.height = 0.28
		beacon.mesh = bsp
		beacon.material_override = beacon_mat
		beacon.position = bpos + Vector3(0, 0.15, 0)
		env_node.add_child(beacon)

	# A repeated overhead datum makes the 210 m run measurable at a glance and
	# supplies WebGL-safe local fill. The fixtures are rendering-only and stay
	# above every route, so decoration never changes navigation or interaction.
	var work_light_mat := StandardMaterial3D.new()
	work_light_mat.albedo_color = Color(0.55, 0.31, 0.16)
	work_light_mat.emission_enabled = true
	work_light_mat.emission = Color(0.95, 0.55, 0.25)
	work_light_mat.emission_energy_multiplier = 1.6
	work_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var work_light_index := 0
	var work_x := 10.0
	while work_x < SHELTER_POS.x - 4.0:
		var fixture := MeshInstance3D.new()
		fixture.name = "RouteWorkFixture%d" % work_light_index
		var fixture_mesh := BoxMesh.new()
		fixture_mesh.size = Vector3(1.7, 0.10, 0.34)
		fixture.mesh = fixture_mesh
		fixture.material_override = work_light_mat
		fixture.position = Vector3(work_x, 2.72, 0.0)
		env_node.add_child(fixture)

		var work_light := OmniLight3D.new()
		work_light.name = "RouteWorkLight%d" % work_light_index
		work_light.position = Vector3(work_x, 2.45, 0.0)
		work_light.light_color = Color(0.94, 0.58, 0.31)
		work_light.light_energy = 1.15
		work_light.omni_range = 12.5
		work_light.shadow_enabled = false
		work_light.distance_fade_enabled = true
		work_light.distance_fade_begin = 20.0
		work_light.distance_fade_length = 10.0
		env_node.add_child(work_light)
		work_light_index += 1
		work_x += 18.0

	# The side lanes sit outside the centerline fixtures' useful WebGL range.
	# Give each decision station and optional branch its own readable beacon.
	var lane_light_index := 0
	var lane_light_positions: Array[Vector3] = [CACHE_POS, LOOKOUT_POS]
	for sector in IRON_SECTORS:
		lane_light_positions.append(sector["safe_station"] as Vector3)
	for lane_pos in lane_light_positions:
		var lane_light := OmniLight3D.new()
		lane_light.name = "RouteLaneLight%d" % lane_light_index
		lane_light.position = lane_pos + Vector3(0, 2.1, 0)
		lane_light.light_color = Color(0.34, 0.76, 0.49)
		lane_light.light_energy = 1.05
		lane_light.omni_range = 7.5
		lane_light.shadow_enabled = false
		env_node.add_child(lane_light)
		lane_light_index += 1

	# Warning signage along the corridor
	var signs := [
		{"pos": Vector3(20, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "I / BLEEDWAY"},
		{"pos": Vector3(76, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "II / FERRIC SUMP"},
		{"pos": Vector3(134, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "III / IRON LATTICE"},
		{"pos": Vector3(198, 1.8, -CORRIDOR_HALF_WIDTH + 0.2), "text": "SHELTER 1  >"},
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
	for iron_x in [IRON_1_POS.x, IRON_2_POS.x, IRON_3_POS.x]:
		for j in range(3):
			var stain := MeshInstance3D.new()
			var stb := BoxMesh.new()
			stb.size = Vector3(1.5 + j * 0.5, 0.003, 1.0 + j * 0.3)
			stain.mesh = stb
			stain.material_override = stain_mat
			stain.position = Vector3(iron_x + j * 1.5 - 1.0, 0.005, 2.0 - j * 1.5)
			stain.rotation.y = j * 0.4
			env_node.add_child(stain)
