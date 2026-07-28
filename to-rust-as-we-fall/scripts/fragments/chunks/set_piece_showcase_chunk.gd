extends "res://scripts/scene_chunks/scene_chunk.gd"

## SET PIECE SHOWCASE — interactive gameplay geometry prototypes (docs/SET_PIECES.md, director
## 2026-07-09). Three set pieces, each a CONTROL + an EFFECT, interleaved per the archetypes grammar
## (a piece's control is separated from its effect by parts of OTHER pieces):
##
##   A) CRAWL PIPE — two mouths; click one, the character ducks in, crawls concealed through the
##      tube and exits at the far mouth. The pipe is the ONLY crossing of the north wall — and the
##      WATER VALVE lives on the far side.
##   B) ROTATING PIPE — a bent pipe hub crossing the yard divider; PUSH the wheel to rotate it 90
##      degrees; only when the bend lines up with the two fixed stubs does its crawl route open.
##   C) WATER BASIN — the valve cycles the water LOW -> MID -> HIGH. Water is never walkable. Two
##      FLOATS ride the surface and bridge the basin ONLY at MID; the sunken east pen holds a
##      roaming enemy — raise the water to HIGH and it drowns.
##
## All logic rides the scheduler (level commits, crawl legs, the drown) — fast-forward invariant,
## replay-safe. Visual motion is derived presentation; topology and payload positions read the saved
## scheduler-owned phase at every tick.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")
const WaterTexV0 := preload("res://resources/models/channels/channels_water_v0.png")
const Lattice := preload("res://scripts/generation/lattice_builder.gd")

const PARTY_IDS: Array = ["peris", "aster", "endo"]

# Water levels: the basin's LOGICAL tiers. Heights are visual; the RULES are per-tier.
const LEVEL_LOW := 0
const LEVEL_MID := 1
const LEVEL_HIGH := 2
const WATER_Y := [0.18, 0.78, 1.38]
const LEVEL_NAMES := ["LOW", "MID", "HIGH"]
const FILL_TIME := 1.4          # scheduler beat between pushing the valve and the level committing
const CRAWL_SPEED := 0.9
const HUB_ALIGNED_ROT := 1      # pushes needed from the start orientation
const HUB_ROTATE_TIME := 0.4

# Bridge cells (the float columns) — walkable ONLY at MID
const BRIDGE_CELLS: Array = [
	Vector2i(22, 9), Vector2i(22, 10), Vector2i(22, 11), Vector2i(22, 12),
	Vector2i(23, 9), Vector2i(23, 10), Vector2i(23, 11), Vector2i(23, 12),
]

# Set piece D: STRUCTURAL WEAKNESS (the building->puzzle hook, docs/SET_PIECES.md). A generated
# honeyframe slab with a WEAK POINT: pry the loose strut (north side) -> the south facade CRUMBLES —
# the debris kills whatever roams beneath AND fills the trench into a shortcut (combat + traversal).
const TRENCH_CELLS: Array = [Vector2i(24, 3), Vector2i(25, 3), Vector2i(26, 3), Vector2i(27, 3)]
const RUBBLE_OPEN: Array = [Vector2i(25, 3), Vector2i(26, 3)]   # the cells the rubble fills
const CRUMBLE_DELAY := 0.9
const KILL_MIN := Vector2(24.4, 1.2)   # the debris field (XZ) — decided at the commit tick
const KILL_MAX := Vector2(26.6, 3.6)

# Set piece E: the IRON-LOAD MAGNET HOIST (docs/SET_PIECES.md proposal 2, Hypelines idiom). A trolley
# rides an overhead rail across a canal; the electromagnet lifts IRON — the bridge PLATE, or the
# iron-laden scrap swarm. Drop the plate over the canal to cross — but living scraps EAT an
# unattended plate (canon: they strip iron from fixtures), so the traversal DECAYS unless the swarm
# is dealt with first: pin it under the magnet and drop it in the canal.
const CANAL_CELLS: Array = [Vector2i(14, 19), Vector2i(15, 19), Vector2i(16, 19)]
const STATION_X: Array = [10.5, 15.5, 21.5]   # trolley stops: 0=plate store, 1=the gap, 2=scrap pen
const HOIST_Z := 19.5
const RAIL_Y := 3.4
const PLATE_APPROACH_SPEED := 1.6             # visible east-bank walk to the plate
const PLATE_STRIP_TIME := 4.0                 # one contacting scrap consumes a full plate in 4s
const PLATE_CONTACT_X := 16.55                # eastern lip of the placed 2.9wu plate
const PLATE_CONTACT_TOLERANCE := 0.5
const PIN_RADIUS := 2.6   # the magnet's grab disc covers the pen (both scraps' roam range)
const TROLLEY_TRAVEL_TIME := 0.5
const MAGNET_OPERATION_TIME := 0.4
const MAGNET_HELD_Y := RAIL_Y - 1.1
const CONTROL_POSITION_TOLERANCE := 0.05

# Scheduler snapshots deliberately omit Callables. This one portable record is therefore the
# gameplay truth for every chunk-owned mechanism phase; the meshes/tweens below are presenters.
const SET_PIECE_AUTHORITY_VERSION := 5
const SET_PIECE_AUTHORITY_PREFIX := "runtime:set_piece_showcase:"

var _runtime_ready := false
var _water_level := LEVEL_LOW
var _pending_level := -1
var _hub_rot := 0
var _hub_phase := "idle"                  # idle | rotating
var _hub_origin_rot := 0
var _hub_target_rot := 0
var _hub_rotation_started_at := -1.0
var _hub_rotation_deadline := -1.0
var _hub_node: Node3D = null
var _hub_wheel: Interactable = null
var _water_valve: Interactable = null
var _water_plane: MeshInstance3D = null
var _floats: Array = []
var _pen_enemy: Node = null
var _crawling: Dictionary = {}          # char_id -> true while inside a pipe
var _mouth_nodes: Dictionary = {}       # name -> Area3D (for enabling the hub route)
var _slab_enemy: Node = null
var _slab_intact := true
var _slab_node: Node3D = null
var _slab_strut: Interactable = null
var _slab_meshes: Array = []            # facade meshes hidden on crumble
var _rubble: Node3D = null              # the debris pile revealed on crumble
var _trolley: Node3D = null
var _plate: Node3D = null
var _crumbs: Node3D = null              # what's left of an eaten plate
var _plate_strip_feedback: Node3D = null # sparks derived from authoritative contact + progress
var _trolley_station := 0
var _trolley_phase := "idle"             # idle | travelling
var _trolley_origin_station := 0
var _trolley_target_station := 0
var _trolley_travel_started_at := -1.0
var _trolley_travel_deadline := -1.0
var _hoist_switch: Interactable = null
var _hoist_lever: Interactable = null
var _magnet_carrying := ""              # "" | "plate" | "swarm"
var _plate_state := "stored"            # stored | held | placed | eaten
var _plate_station := 0                  # grounded plate location; meaningful while stored/placed
var _magnet_phase := "idle"             # idle | lifting_plate | lifting_swarm | dropping_plate | dropping_swarm
var _magnet_phase_started_at := -1.0
var _magnet_phase_deadline := -1.0
var _scraps: Array = []                 # the iron-laden swarm (enemy nodes)
var _pinned: Array = []                 # scrap ids held under the charged magnet
var _basin_fill_deadline := -1.0
var _slab_fall_started_at := -1.0
var _slab_crumble_deadline := -1.0
var _plate_approach_ids: Array[String] = []
var _plate_strip_ids: Array[String] = []
var _plate_integrity := 1.0
var _plate_strip_started_at := -1.0
var _plate_strip_deadline := -1.0
var _plate_strip_interrupt_reason := ""
var _plate_signal_game_state = null
var _set_piece_authority_initialized := false
var _restoring_set_piece_authority := false
var _visual_tweens: Array = []

func get_scene_title() -> String:
	return "Set Pieces — crawl / rotate / water"

func get_scene_help() -> String:
	return "Push the wheel to line up the bent pipe, crawl it east. Crawl the wall pipe north to reach the water valve. Set the water to MID so the floats bridge the basin; set HIGH to drown the penned threat. Pry the loose strut behind the cracked slab — the facade falls on whatever lurks beneath and its rubble fills the trench. At the hoist: drop the iron plate over the canal to cross — but living scraps EAT it; pin the swarm under the magnet and drop it in the canal first. Reach the northeast pad."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return {
		"peris": Vector3(4.5, 0.0, 3.5),
		"aster": Vector3(6.5, 0.0, 3.5),
		"endo": Vector3(8.5, 0.0, 3.5),
	}

func get_preview_anchors() -> Dictionary:
	return {
		"spawn": Vector3(4.5, 0.0, 3.5),
		"wheel": Vector3(14.0, 0.0, 5.5),
		"hub_west": Vector3(15.2, 0.0, 5.5),
		"hub_east": Vector3(18.8, 0.0, 5.5),
		"pipe_south": Vector3(4.5, 0.0, 8.6),
		"pipe_north": Vector3(4.5, 0.0, 13.4),
		"valve": Vector3(7.5, 0.0, 14.5),
		"bridge_south": Vector3(22.5, 0.0, 8.5),
		"bridge_north": Vector3(22.5, 0.0, 13.5),
		"pen_rim": Vector3(26.5, 0.0, 8.5),
		"exit": Vector3(27.5, 0.0, 15.0),
		"hoist_switch": Vector3(9.0, 0.0, 18.0),
		"hoist_lever": Vector3(12.0, 0.0, 18.0),
		"hoist_west": Vector3(12.5, 0.0, 19.5),
		"hoist_east": Vector3(18.5, 0.0, 19.5),
		"scrap_pen": Vector3(21.5, 0.0, 19.5),
	}

func get_grid_data() -> Dictionary:
	var extra: Array = []
	for c in BRIDGE_CELLS:
		extra.append([int((c as Vector2i).x), int((c as Vector2i).y)])
	for c2 in CANAL_CELLS:
		extra.append([int((c2 as Vector2i).x), int((c2 as Vector2i).y)])
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0], "cell_size": 1.0, "width": 30, "height": 23,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [15.9, 9.9]},     # yard WEST (spawn, wheel)
			{"min": [18.0, 1.0], "max": [28.9, 8.9]},    # yard EAST (basin approach)
			{"min": [1.0, 13.0], "max": [28.9, 15.9]},   # north strip (valve, exit)
			{"min": [26.0, 9.0], "max": [27.9, 11.9]},   # the sunken PEN (enemy shelf)
			{"min": [10.0, 16.0], "max": [11.9, 16.9]},  # doorway from the north strip to the hoist
			{"min": [6.0, 17.0], "max": [13.9, 21.9]},   # hoist WEST bank (lever, plate store)
			{"min": [17.0, 17.0], "max": [25.9, 21.9]},  # hoist EAST bank (scrap pen, cache)
		],
		"walkable_cells": extra,                         # float bridge + canal crossing — gated
	}

func _build_chunk() -> void:
	_add_floor(self, Vector3(15.0, 0.0, 11.5), Vector3(30.0, 0.1, 23.0), Color(0.085, 0.09, 0.11))
	_add_label(self, "SET PIECES", Vector3(15.0, 3.4, 0.6), Color(0.9, 0.85, 0.6))
	_build_walls()
	_build_crawl_pipe()
	_build_rotating_hub()
	_build_basin()
	_build_weak_slab()
	_build_magnet_hoist()
	_add_light(self, Vector3(8.0, 5.0, 6.0), Color(1.0, 0.95, 0.85), 1.1, 18.0)
	_add_light(self, Vector3(23.0, 5.0, 11.0), Color(0.8, 0.92, 1.0), 1.1, 16.0)
	_add_light(self, Vector3(14.0, 5.0, 14.0), Color(1.0, 0.95, 0.85), 0.9, 14.0)
	_add_light(self, Vector3(15.0, 5.5, 19.5), Color(1.0, 0.9, 0.8), 1.0, 16.0)

# --- geometry --------------------------------------------------------------------------------

func _build_walls() -> void:
	var wallc := Color(0.30, 0.32, 0.36)
	# the NORTH WALL band (z 10..12) — crossed only by the crawl pipe and the basin
	_add_box(self, Vector3(9.5, 1.1, 11.5), Vector3(19.0, 2.2, 3.0), wallc, Color.BLACK, 0.0, "NorthWallWest")
	_add_box(self, Vector3(29.0, 1.1, 11.5), Vector3(2.0, 2.2, 3.0), wallc, Color.BLACK, 0.0, "NorthWallEast")
	# the YARD DIVIDER (x 16..17) — crossed only by the rotating hub
	_add_box(self, Vector3(17.0, 1.1, 5.0), Vector3(2.0, 2.2, 10.0), wallc, Color.BLACK, 0.0, "YardDivider")
	# perimeter suggestion (low kerbs, purely visual)
	_add_box(self, Vector3(15.0, 0.25, 0.35), Vector3(30.0, 0.5, 0.7), wallc * 0.8)
	_add_box(self, Vector3(15.0, 0.25, 16.65), Vector3(30.0, 0.5, 0.7), wallc * 0.8)

func _pipe_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.40, 0.34)
	m.metallic = 0.55
	m.roughness = 0.6
	return m

func _add_pipe_segment(parent: Node3D, from: Vector3, to: Vector3, radius: float, pname: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = from.distance_to(to)
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _pipe_material()
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var axis := (to - from).normalized()
	if absf(axis.dot(Vector3.UP)) < 0.999:
		var side := axis.cross(Vector3.UP).normalized()
		mi.global_transform.basis = Basis(side, axis, side.cross(axis))
	return mi

func _add_pipe_mouth(parent: Node3D, pos: Vector3, axis: Vector3, mname: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mname
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.86
	mi.mesh = tm
	var m := _pipe_material()
	m.albedo_color = Color(0.28, 0.45, 0.42)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.9, 0.6)
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	if absf(axis.dot(Vector3.UP)) < 0.999:
		var side := axis.cross(Vector3.UP).normalized()
		mi.global_transform.basis = Basis(side, axis, side.cross(axis))
	return mi

# A) the CRAWL PIPE through the north wall at x=4.5
func _build_crawl_pipe() -> void:
	var south := Vector3(4.5, 0.75, 8.9)
	var north := Vector3(4.5, 0.75, 13.1)
	_add_pipe_segment(self, south, north, 0.75, "CrawlPipe")
	_add_pipe_mouth(self, south, Vector3(0, 0, 1), "CrawlPipeMouthS")
	_add_pipe_mouth(self, north, Vector3(0, 0, 1), "CrawlPipeMouthN")
	_add_crawl_tunnel("PipeMouthSouth", "Crawl through the wall pipe", Vector3(4.5, 0.5, 8.2),
		[Vector3(4.5, 0.0, 9.2), Vector3(4.5, 0.0, 13.8)], 1.4)
	_add_crawl_tunnel("PipeMouthNorth", "Crawl through the wall pipe", Vector3(4.5, 0.5, 13.8),
		[Vector3(4.5, 0.0, 12.8), Vector3(4.5, 0.0, 8.2)], 1.4)

# B) the ROTATING PIPE hub through the yard divider at z=5.5
func _build_rotating_hub() -> void:
	_hub_node = Node3D.new()
	_hub_node.name = "RotatingHub"
	add_child(_hub_node)
	_hub_node.position = Vector3(17.0, 0.75, 5.5)
	# a BENT pipe (L): when rotated to alignment its two openings face the fixed W/E stubs
	_add_pipe_segment(_hub_node, Vector3(-1.0, 0.0, 0.0), Vector3(0.15, 0.0, 0.0), 0.7, "HubArmA")
	_add_pipe_segment(_hub_node, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 0.15), 0.7, "HubArmB")
	var elbow := MeshInstance3D.new()
	elbow.name = "HubElbow"
	var sm := SphereMesh.new()
	sm.radius = 0.78
	sm.height = 1.56
	elbow.mesh = sm
	elbow.material_override = _pipe_material()
	_hub_node.add_child(elbow)
	_hub_rot = 0
	_apply_hub_visual(false)
	# fixed stubs either side of the divider
	_add_pipe_segment(self, Vector3(15.4, 0.75, 5.5), Vector3(16.0, 0.75, 5.5), 0.72, "HubStubW")
	_add_pipe_segment(self, Vector3(18.0, 0.75, 5.5), Vector3(18.6, 0.75, 5.5), 0.72, "HubStubE")
	_add_pipe_mouth(self, Vector3(15.4, 0.75, 5.5), Vector3(1, 0, 0), "HubMouthWRing")
	_add_pipe_mouth(self, Vector3(18.6, 0.75, 5.5), Vector3(1, 0, 0), "HubMouthERing")
	# the PUSH WHEEL (the control — you push the thing that rotates)
	_hub_wheel = _add_interactable(self, "HubWheel", "Push the wheel to rotate the pipe", Vector3(14.0, 0.5, 5.5),
		"PUSH", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var wmesh := MeshInstance3D.new()
	var tw := TorusMesh.new()
	tw.inner_radius = 0.30
	tw.outer_radius = 0.48
	wmesh.mesh = tw
	var wm := _pipe_material()
	wm.albedo_color = Color(0.6, 0.5, 0.25)
	wmesh.material_override = wm
	wmesh.rotation_degrees = Vector3(0, 0, 90)
	wmesh.position = Vector3(0, 0.55, 0)
	_hub_wheel.add_child(wmesh)
	_outline_interactable_child(_hub_wheel, wmesh, "HubWheel", 1.5)
	_configure_set_piece_control(_hub_wheel, "wheel", _on_wheel_pushed)
	# the hub's own crawl mouths — enabled only when ALIGNED
	var ia_w := _add_crawl_tunnel("HubMouthWest", "Crawl the aligned pipe", Vector3(15.0, 0.5, 5.5),
		[Vector3(15.4, 0.0, 5.5), Vector3(19.2, 0.0, 5.5)], 1.3)
	var ia_e := _add_crawl_tunnel("HubMouthEast", "Crawl the aligned pipe", Vector3(19.0, 0.5, 5.5),
		[Vector3(18.6, 0.0, 5.5), Vector3(14.8, 0.0, 5.5)], 1.3)
	_mouth_nodes["HubMouthWest"] = ia_w
	_mouth_nodes["HubMouthEast"] = ia_e
	_refresh_hub_mouths()

# C) the WATER BASIN + floats + pen + valve
func _build_basin() -> void:
	var rimc := Color(0.24, 0.27, 0.30)
	# basin rim walls (the west/east flanks that force the float crossing)
	_add_box(self, Vector3(19.0, 0.9, 11.0), Vector3(2.0, 1.8, 4.0), rimc, Color.BLACK, 0.0, "BasinRimW")
	_add_box(self, Vector3(25.0, 0.9, 11.0), Vector3(2.0, 1.8, 4.0), rimc, Color.BLACK, 0.0, "BasinRimMid")
	# basin floor (sunken look)
	_add_box(self, Vector3(23.5, -0.12, 11.0), Vector3(9.0, 0.2, 4.2), Color(0.12, 0.13, 0.15), Color.BLACK, 0.0, "BasinFloor")
	# the PEN shelf (lower ground the enemy roams; submerges at HIGH)
	_add_box(self, Vector3(27.0, 0.06, 10.5), Vector3(2.0, 0.3, 3.0), Color(0.18, 0.19, 0.20), Color.BLACK, 0.0, "PenShelf")
	_add_label(self, "PEN", Vector3(27.0, 2.2, 10.5), Color(0.9, 0.5, 0.4))
	# WATER plane (visual; the logical water is the level tier)
	_water_plane = MeshInstance3D.new()
	_water_plane.name = "BasinWater"
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 0.14, 4.0)
	_water_plane.mesh = bm
	var wmat := ShaderMaterial.new()
	wmat.shader = WaterShader
	wmat.set_shader_parameter("water_tex", WaterTexV0)
	wmat.render_priority = 127
	_water_plane.material_override = wmat
	add_child(_water_plane)
	_water_plane.position = Vector3(24.0, float(WATER_Y[LEVEL_LOW]), 11.0)
	# FLOATS: two platforms riding the water; they bridge the basin at MID
	for fz in [10.0, 12.0]:
		var fl := MeshInstance3D.new()
		fl.name = "Float%d" % int(fz)
		var fm := BoxMesh.new()
		fm.size = Vector3(1.9, 0.28, 1.9)
		fl.mesh = fm
		var flm := StandardMaterial3D.new()
		flm.albedo_color = Color(0.55, 0.45, 0.28)
		flm.roughness = 0.85
		fl.material_override = flm
		add_child(fl)
		fl.position = Vector3(23.0, float(WATER_Y[LEVEL_LOW]) + 0.14, float(fz))
		_floats.append(fl)
	# the VALVE console — NORTH side (reachable only through the crawl pipe: the grammar demo)
	_water_valve = _add_interactable(self, "WaterValve", "Cycle the basin water level", Vector3(7.5, 0.5, 14.5),
		"VALVE", "", 1.0, true, 1.6, Interactable.InteractableType.INSPECTION, false)
	var vmesh := _add_box(_water_valve, Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.5), Color(0.2, 0.4, 0.5), Color(0.3, 0.85, 1.0), 0.9)
	_outline_interactable_child(_water_valve, vmesh, "WaterValve", 1.6)
	_configure_set_piece_control(_water_valve, "valve", _on_valve_used)
	_add_label(self, "WATER VALVE", Vector3(7.5, 2.6, 14.5), Color(0.5, 0.9, 1.0))
	# exit pad
	_add_box(self, Vector3(27.5, 0.06, 15.0), Vector3(1.6, 0.12, 1.6), Color(0.25, 0.5, 0.3), Color(0.3, 1.0, 0.5), 0.8, "ExitPad")
	_add_label(self, "EXIT", Vector3(27.5, 1.6, 15.0), Color(0.5, 1.0, 0.6))

# D) the STRUCTURAL WEAKNESS: a generated honeyframe slab, a crack marker, a pry point, a trench
func _build_weak_slab() -> void:
	var slab := Node3D.new()
	slab.name = "WeakSlab"
	add_child(slab)
	slab.position = Vector3(25.5, 0.0, 4.6)
	_slab_node = slab
	var body := _add_box(slab, Vector3(0, 1.6, 0), Vector3(2.2, 3.2, 1.0), Color(0.34, 0.36, 0.40), Color.BLACK, 0.0, "SlabBody")
	_slab_meshes.append(body)
	# the generated facade: a mini S_A/S_B honeyframe wrapping the slab (the building IS the set piece)
	var built: Dictionary = Lattice.honeyframe(Vector3(2.4, 3.2, 1.2), {"crown": false, "base": false, "cell_size": 0.8, "rib_radius": 0.07})
	for pair in [["frame", Color(0.72, 0.69, 0.58)], ["glass", Color(1.0, 0.72, 0.36)]]:
		var mesh: Variant = built.get(str((pair as Array)[0]))
		if mesh == null or (mesh as ArrayMesh).get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Slab%s" % str((pair as Array)[0]).capitalize()
		mi.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = (pair as Array)[1] as Color
		m.vertex_color_use_as_albedo = str((pair as Array)[0]) == "glass"
		m.emission_enabled = str((pair as Array)[0]) == "glass"
		if m.emission_enabled:
			m.emission = Color(1.0, 0.72, 0.36)
			m.emission_energy_multiplier = 0.9
		slab.add_child(mi)
		_slab_meshes.append(mi)
	# the WEAK-POINT tell: a dark-red crack gem on the south face, present from first sight
	var crack := _add_box(slab, Vector3(0.2, 2.4, -0.68), Vector3(0.5, 0.35, 0.08), Color(0.3, 0.08, 0.06), Color(0.85, 0.15, 0.1), 0.9, "CrackTell")
	_slab_meshes.append(crack)
	_add_label(self, "WEAK", Vector3(25.5, 3.9, 4.6), Color(0.95, 0.45, 0.35))
	# the TRENCH the rubble will fill (blocked cells at z=3, visual channel)
	_add_box(self, Vector3(26.0, -0.14, 3.5), Vector3(4.0, 0.24, 1.0), Color(0.10, 0.11, 0.13), Color.BLACK, 0.0, "Trench")
	# the PRY point — NORTH side (the control behind the slab; the effect falls south: the grammar)
	_slab_strut = _add_interactable(self, "LooseStrut", "Pry the loose strut", Vector3(25.5, 0.5, 5.8),
		"PRY", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var smesh := _add_box(_slab_strut, Vector3(0, 0.9, 0), Vector3(0.22, 1.8, 0.22), Color(0.5, 0.42, 0.3), Color(0.9, 0.6, 0.2), 0.5)
	_outline_interactable_child(_slab_strut, smesh, "LooseStrut", 1.5)
	_configure_set_piece_control(_slab_strut, "strut", _on_strut_pried)
	# the rubble pile (hidden until the crumble) — covers the kill field + fills the trench cells
	_rubble = Node3D.new()
	_rubble.name = "RubblePile"
	add_child(_rubble)
	_rubble.position = Vector3(25.5, 0.0, 2.6)
	var rk := [Vector3(-0.6, 0.25, 0.3), Vector3(0.5, 0.2, 0.8), Vector3(0.1, 0.45, -0.2), Vector3(-0.3, 0.2, 1.1), Vector3(0.7, 0.3, -0.5)]
	for ri in range(rk.size()):
		_add_box(_rubble, rk[ri] as Vector3, Vector3(0.9 - 0.08 * float(ri), 0.5, 0.8), Color(0.30, 0.30, 0.33), Color.BLACK, 0.0, "Rubble%d" % ri)
	_rubble.visible = false

func _on_strut_pried(source: Node = null) -> bool:
	if not _set_piece_control_receipt_pending(source, "strut"):
		return false
	var sched = _get_scheduler()
	if sched == null:
		_rearm_set_piece_control(source)
		return false
	_slab_fall_started_at = float(sched.get_current_tick())
	_slab_crumble_deadline = _slab_fall_started_at + CRUMBLE_DELAY
	_apply_slab_presenter()
	_publish_set_piece_authority()
	_schedule_set_piece_deadline(
		_slab_crumble_deadline, _commit_crumble, _set_piece_tag("slab_crumble")
	)
	_refresh_mechanism_controls()
	return true

func _commit_crumble() -> void:
	if not _slab_intact:
		_slab_fall_started_at = -1.0
		_slab_crumble_deadline = -1.0
		_publish_set_piece_authority()
		return
	_slab_fall_started_at = -1.0
	_slab_crumble_deadline = -1.0
	_slab_intact = false
	var gs = _get_game_state()
	# the debris field resolves NOW, at the commit tick (analytic, never per-frame sampled)
	if _slab_enemy != null and is_instance_valid(_slab_enemy) and _slab_enemy.is_alive():
		var ep: Vector3 = gs.get_position(_slab_enemy.char_id) if gs != null else Vector3.ZERO
		if ep.x > KILL_MIN.x and ep.x < KILL_MAX.x and ep.z > KILL_MIN.y and ep.z < KILL_MAX.y:
			if gs != null:
				gs.command_stop(_slab_enemy.char_id)
			_slab_enemy.take_damage(float(_slab_enemy.max_hp))
	# the rubble fills the trench — a shortcut opens, and the slab's own footprint clears (traversal
	# from the same strike that killed)
	_apply_slab_blockers()
	_apply_slab_presenter()
	_publish_set_piece_authority()

# E) the IRON-LOAD MAGNET HOIST: rail + trolley over a canal, a plate the swarm can EAT
func _build_magnet_hoist() -> void:
	_add_label(self, "MAGNET HOIST", Vector3(15.0, 4.6, 17.2), Color(0.95, 0.8, 0.5))
	# the CANAL (impassable water channel between the banks)
	_add_box(self, Vector3(15.5, -0.14, 19.5), Vector3(3.2, 0.24, 5.0), Color(0.10, 0.12, 0.15), Color.BLACK, 0.0, "HoistCanal")
	# rail posts + the overhead rail beam
	for px in [8.0, 23.0]:
		_add_box(self, Vector3(px, RAIL_Y * 0.5, HOIST_Z), Vector3(0.3, RAIL_Y, 0.3), Color(0.30, 0.30, 0.34))
	_add_box(self, Vector3(15.5, RAIL_Y, HOIST_Z), Vector3(16.0, 0.24, 0.4), Color(0.36, 0.35, 0.38), Color.BLACK, 0.0, "HoistRail")
	# the TROLLEY + electromagnet. Its saved origin/target/deadline own transit; the node samples that
	# phase for presentation and the stable station changes only when the trolley arrives.
	_trolley = Node3D.new()
	_trolley.name = "HoistTrolley"
	add_child(_trolley)
	_trolley.position = Vector3(float(STATION_X[0]), RAIL_Y - 0.3, HOIST_Z)
	var tb := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(1.0, 0.4, 0.7)
	tb.mesh = tbm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.5, 0.42, 0.3)
	tmat.metallic = 0.5
	tb.material_override = tmat
	_trolley.add_child(tb)
	var mag := MeshInstance3D.new()
	mag.name = "Magnet"
	var mm := CylinderMesh.new()
	mm.top_radius = 0.42
	mm.bottom_radius = 0.5
	mm.height = 0.35
	mag.mesh = mm
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.65, 0.2, 0.15)
	mmat.emission_enabled = true
	mmat.emission = Color(0.9, 0.3, 0.2)
	mmat.emission_energy_multiplier = 0.0     # lights up while charged (cosmetic)
	mag.material_override = mmat
	mag.position = Vector3(0, -0.5, 0)
	_trolley.add_child(mag)
	# the iron PLATE, stored on the west bank under station 0
	_plate = Node3D.new()
	_plate.name = "IronPlate"
	add_child(_plate)
	_plate.position = Vector3(float(STATION_X[0]), 0.12, HOIST_Z)
	var pm := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(2.9, 0.16, 1.2)
	pm.mesh = pbm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.42, 0.38, 0.34)
	pmat.metallic = 0.7
	pmat.roughness = 0.5
	pm.material_override = pmat
	_plate.add_child(pm)
	# what the swarm leaves of it
	_crumbs = Node3D.new()
	_crumbs.name = "PlateCrumbs"
	add_child(_crumbs)
	_crumbs.position = Vector3(15.5, 0.0, 19.5)
	for ci in range(4):
		_add_box(_crumbs, Vector3(-1.0 + 0.7 * float(ci), 0.06, -0.3 + 0.25 * float(ci % 2)),
			Vector3(0.35, 0.1, 0.3), Color(0.35, 0.30, 0.26))
	_crumbs.visible = false
	# Contact produces a shower of hot iron flecks while the plate visibly loses material. The
	# feedback is presentation only: its visibility and plate scale are sampled from the saved strip
	# phase, so pause, replay, and a fresh presenter show the same causal midpoint.
	_plate_strip_feedback = Node3D.new()
	_plate_strip_feedback.name = "PlateStripSparks"
	_plate_strip_feedback.position = Vector3(PLATE_CONTACT_X, 0.22, HOIST_Z)
	add_child(_plate_strip_feedback)
	for spark_index in range(5):
		var spark := MeshInstance3D.new()
		var spark_mesh := BoxMesh.new()
		spark_mesh.size = Vector3(0.07, 0.07, 0.18)
		spark.mesh = spark_mesh
		var spark_mat := StandardMaterial3D.new()
		spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark_mat.albedo_color = Color(1.0, 0.45, 0.08)
		spark_mat.emission_enabled = true
		spark_mat.emission = Color(1.0, 0.18, 0.02)
		spark_mat.emission_energy_multiplier = 2.0
		spark.material_override = spark_mat
		spark.position = Vector3(
			-0.16 + float(spark_index % 3) * 0.14,
			float(spark_index % 2) * 0.11,
			-0.38 + float(spark_index) * 0.19
		)
		spark.rotation.z = deg_to_rad(-35.0 + float(spark_index) * 17.0)
		_plate_strip_feedback.add_child(spark)
	_plate_strip_feedback.visible = false
	# CONTROLS on the west bank: the track switch + the charge lever
	_hoist_switch = _add_interactable(self, "HoistSwitch", "Shunt the trolley to the next station", Vector3(9.0, 0.5, 18.0),
		"SHUNT", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var swm := _add_box(_hoist_switch, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4), Color(0.3, 0.35, 0.45), Color(0.4, 0.7, 1.0), 0.6)
	_outline_interactable_child(_hoist_switch, swm, "HoistSwitch", 1.5)
	_configure_set_piece_control(_hoist_switch, "hoist_switch", _on_hoist_shunt)
	_hoist_lever = _add_interactable(self, "HoistLever", "Charge / discharge the magnet", Vector3(12.0, 0.5, 18.0),
		"CHARGE", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var lvm := _add_box(_hoist_lever, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4), Color(0.45, 0.3, 0.25), Color(1.0, 0.45, 0.25), 0.6)
	_outline_interactable_child(_hoist_lever, lvm, "HoistLever", 1.5)
	_configure_set_piece_control(_hoist_lever, "hoist_lever", _on_hoist_lever)
	# the east-bank payoff pad
	_add_box(self, Vector3(24.5, 0.06, 20.5), Vector3(1.4, 0.12, 1.4), Color(0.4, 0.35, 0.2), Color(1.0, 0.8, 0.3), 0.7, "CachePad")
	_add_label(self, "CACHE", Vector3(24.5, 1.5, 20.5), Color(1.0, 0.85, 0.45))

func _on_hoist_shunt(source: Node = null) -> bool:
	if not _set_piece_control_receipt_pending(source, "hoist_switch"):
		return false
	var sched = _get_scheduler()
	if sched == null:
		_rearm_set_piece_control(source)
		return false
	var target_station := (_trolley_station + 1) % STATION_X.size()
	if not _begin_pinned_payload_transit(target_station):
		_rearm_set_piece_control(source)
		return false
	_trolley_phase = "travelling"
	_trolley_origin_station = _trolley_station
	_trolley_target_station = target_station
	_trolley_travel_started_at = float(sched.get_current_tick())
	_trolley_travel_deadline = _trolley_travel_started_at + TROLLEY_TRAVEL_TIME
	_refresh_mechanism_controls()
	_publish_set_piece_authority()
	_schedule_set_piece_deadline(
		_trolley_travel_deadline, _commit_trolley_arrival, _set_piece_tag("trolley_travel")
	)
	_apply_hoist_presenter()
	_rearm_set_piece_control(source)
	return true

func _commit_trolley_arrival() -> void:
	if _trolley_phase != "travelling":
		_trolley_travel_deadline = -1.0
		_publish_set_piece_authority()
		return
	_trolley_station = _trolley_target_station
	_trolley_phase = "idle"
	_trolley_origin_station = _trolley_station
	_trolley_target_station = _trolley_station
	_trolley_travel_started_at = -1.0
	_trolley_travel_deadline = -1.0
	_settle_pinned_payload_at_station()
	_apply_hoist_presenter()
	_refresh_mechanism_controls()
	_publish_set_piece_authority()

func _on_hoist_lever(source: Node = null) -> bool:
	if not _set_piece_control_receipt_pending(source, "hoist_lever"):
		return false
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		_rearm_set_piece_control(source)
		return false
	if _magnet_carrying == "":
		# CHARGE begins a saved lift. The payload becomes carried only when it physically reaches
		# the magnet, so a halfway save reconstructs a halfway lift rather than granting the result.
		if _plate_state == "stored" and _plate_station == _trolley_station:
			_begin_magnet_phase("lifting_plate")
		elif _trolley_station == 2 and _begin_swarm_lift():
			_begin_magnet_phase("lifting_swarm")
	else:
		# DISCHARGE is also a saved fall. Canal topology and damage commit only on impact.
		if _magnet_carrying == "plate":
			_begin_magnet_phase("dropping_plate")
		elif _magnet_carrying == "swarm" and _begin_swarm_drop():
			_begin_magnet_phase("dropping_swarm")
	if _magnet_phase == "idle":
		_rearm_set_piece_control(source)
		return false
	_set_magnet_glow(true)
	_refresh_mechanism_controls()
	_apply_hoist_presenter()
	_publish_set_piece_authority()
	_schedule_set_piece_deadline(
		_magnet_phase_deadline, _commit_magnet_operation, _set_piece_tag("magnet_operation")
	)
	_rearm_set_piece_control(source)
	return true

func _begin_magnet_phase(phase: String) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	_magnet_phase = phase
	_magnet_phase_started_at = float(sched.get_current_tick())
	_magnet_phase_deadline = _magnet_phase_started_at + MAGNET_OPERATION_TIME

func _begin_swarm_lift() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	var station := Vector3(float(STATION_X[_trolley_station]), 0.0, HOIST_Z)
	# A scrap already walking toward or chewing the bridge is not immune to the hoist. Explicitly
	# interrupt only bodies still inside the magnet's real disc; the following lift then owns their
	# new traversal from that exact analytic position.
	_interrupt_plate_pressure_under_magnet(station)
	var candidates: Array = []
	for sc in _scraps:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		var char_id := str(sc.char_id)
		if not gs.characters.has(char_id) or gs.is_external_traversal_active(char_id):
			continue
		var sp: Vector3 = gs.get_position(char_id)
		if Vector2(sp.x, sp.z).distance_to(Vector2(station.x, station.z)) < PIN_RADIUS:
			candidates.append(sc)
	if candidates.is_empty():
		return false
	_pinned.clear()
	var started_ids: Array[String] = []
	for slot in range(candidates.size()):
		var sc = candidates[slot]
		var char_id := str(sc.char_id)
		var destination := _pinned_payload_anchor(_trolley_station, slot, true)
		gs.command_stop(char_id)
		var accepted := bool(gs.command_external_traversal(
			char_id,
			_hoist_payload_traversal_id(char_id),
			destination,
			gs.get_render_position(char_id),
			destination,
			MAGNET_OPERATION_TIME,
			&"locked"
		))
		if not accepted:
			for started_id in started_ids:
				gs.cancel_external_traversal(started_id, &"hoist_lift_rejected")
			_pinned.clear()
			return false
		started_ids.append(char_id)
		_pinned.append(sc)
	return true

func _begin_swarm_drop() -> bool:
	var gs = _get_game_state()
	if gs == null or _pinned.is_empty():
		return false
	var live_payload: Array = []
	for sc in _pinned:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		if not gs.characters.has(sc.char_id) or gs.is_external_traversal_active(sc.char_id):
			return false
		live_payload.append(sc)
	if live_payload.is_empty():
		return false
	var started_ids: Array[String] = []
	for slot in range(live_payload.size()):
		var sc = live_payload[slot]
		var char_id := str(sc.char_id)
		var destination := _pinned_payload_anchor(_trolley_station, slot, false)
		if _trolley_station == 1:
			destination.y = -0.7
		var accepted := bool(gs.command_external_traversal(
			char_id,
			_hoist_payload_traversal_id(char_id),
			destination,
			gs.get_render_position(char_id),
			destination,
			MAGNET_OPERATION_TIME,
			&"locked"
		))
		if not accepted:
			for started_id in started_ids:
				gs.cancel_external_traversal(started_id, &"hoist_drop_rejected")
			return false
		started_ids.append(char_id)
	return true

func _commit_magnet_operation() -> void:
	var completed_phase := _magnet_phase
	_magnet_phase = "idle"
	_magnet_phase_started_at = -1.0
	_magnet_phase_deadline = -1.0
	match completed_phase:
		"lifting_plate":
			if _plate_state == "stored" and _plate_station == _trolley_station:
				_plate_state = "held"
				_magnet_carrying = "plate"
		"lifting_swarm":
			_pinned = _live_pinned_payload()
			if not _pinned.is_empty():
				_magnet_carrying = "swarm"
				_settle_pinned_payload_at_station()
		"dropping_plate":
			if _magnet_carrying == "plate":
				_plate_station = _trolley_station
				_plate_state = "placed" if _trolley_station == 1 else "stored"
				_magnet_carrying = ""
				_apply_canal_blockers()
				if _plate_state == "placed":
					_begin_plate_scrap_approaches()
		"dropping_swarm":
			var gs = _get_game_state()
			if _magnet_carrying == "swarm" and gs != null:
				if _trolley_station == 1:
					for sc in _pinned:
						if sc != null and is_instance_valid(sc) and sc.is_alive():
							gs.command_stop(sc.char_id)
							sc.take_damage(float(sc.max_hp))
				else:
					for sc in _pinned:
						if sc != null and is_instance_valid(sc) and sc.is_alive():
							sc.global_position = gs.get_position(sc.char_id)
							sc.set_roam(gs.get_position(sc.char_id), 1.2)
			_pinned.clear()
			_magnet_carrying = ""
	_set_magnet_glow(_magnet_carrying != "" or _magnet_phase != "idle")
	_apply_hoist_presenter()
	_refresh_mechanism_controls()
	_publish_set_piece_authority()

func _live_pinned_payload() -> Array:
	var live: Array = []
	for sc in _pinned:
		if sc != null and is_instance_valid(sc) and sc.is_alive():
			live.append(sc)
	return live

func _pinned_payload_anchor(station: int, slot: int, held: bool) -> Vector3:
	return Vector3(
		float(STATION_X[station]) + float(slot) * 0.4 - 0.2,
		MAGNET_HELD_Y if held else 0.0,
		HOIST_Z + 0.3
	)

func _begin_pinned_payload_transit(target_station: int) -> bool:
	if _magnet_carrying != "swarm":
		return true
	var gs = _get_game_state()
	if gs == null:
		return false
	var live_payload: Array = []
	for sc in _pinned:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		if not gs.characters.has(sc.char_id) or gs.is_external_traversal_active(sc.char_id):
			return false
		live_payload.append(sc)
	var started_ids: Array[String] = []
	for slot in range(live_payload.size()):
		var sc = live_payload[slot]
		var char_id := str(sc.char_id)
		var data_destination := _pinned_payload_anchor(target_station, slot, true)
		var render_origin: Vector3 = gs.get_render_position(char_id)
		var accepted := bool(gs.command_external_traversal(
			char_id,
			_hoist_payload_traversal_id(char_id),
			data_destination,
			render_origin,
			data_destination,
			TROLLEY_TRAVEL_TIME,
			&"locked"
		))
		if not accepted:
			for started_id in started_ids:
				gs.cancel_external_traversal(started_id, &"hoist_commit_rejected")
			return false
		started_ids.append(char_id)
	return true

func _settle_pinned_payload_at_station() -> void:
	if _magnet_carrying != "swarm":
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for slot in range(_pinned.size()):
		var sc = _pinned[slot]
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		var anchor := _pinned_payload_anchor(_trolley_station, slot, true)
		sc.global_position = anchor
		sc.set_roam(anchor, 0.05)

func _hoist_payload_traversal_id(char_id: String) -> StringName:
	return StringName("set_piece_hoist_%s_%s" % [absi(set_piece_authority_key().hash()), char_id])

func _cancel_pinned_payload_transits(reason: StringName) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for sc in _pinned:
		if sc == null or not is_instance_valid(sc):
			continue
		var char_id := str(sc.char_id)
		var state: Dictionary = gs.get_external_traversal_state(char_id)
		if state.get("traversal_id", &"") == _hoist_payload_traversal_id(char_id):
			gs.cancel_external_traversal(char_id, reason)

func _begin_plate_scrap_approaches() -> void:
	if _plate_state != "placed":
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var changed := false
	for sc in _scraps:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		var char_id := str(sc.char_id)
		if _plate_approach_ids.has(char_id) or _plate_strip_ids.has(char_id) \
				or _pinned.has(sc) or gs.is_external_traversal_active(char_id):
			continue
		# A lure, fight, or stun is a real competing cause. The plate may recruit only an ambient
		# scrap; once that other state ends, the ordinary process reconciliation can try again.
		if str(sc.get_state()) not in ["idle", "roam"]:
			continue
		# Cancel ambient wandering before the resource target owns a locked, saved movement leg.
		sc._change_state("idle")
		var contact := _plate_contact_for_scrap(char_id)
		var origin: Vector3 = gs.get_render_position(char_id)
		var duration := maxf(0.15, origin.distance_to(contact) / PLATE_APPROACH_SPEED)
		var accepted := bool(gs.command_external_traversal(
			char_id,
			_plate_approach_traversal_id(char_id),
			contact,
			origin,
			contact,
			duration,
			&"locked"
		))
		if accepted:
			_plate_approach_ids.append(char_id)
			changed = true
	if changed:
		_plate_strip_interrupt_reason = ""
		_apply_hoist_presenter()
		_publish_set_piece_authority()

func _plate_contact_for_scrap(char_id: String) -> Vector3:
	var z_offset := -0.34 if char_id == "scrap_a" else 0.34
	return Vector3(PLATE_CONTACT_X, 0.0, HOIST_Z + z_offset)

func _scrap_home_position(char_id: String) -> Vector3:
	return Vector3(21.2, 0.0, 19.2) if char_id == "scrap_a" \
		else Vector3(22.0, 0.0, 20.0)

func _plate_approach_traversal_id(char_id: String) -> StringName:
	return StringName("set_piece_plate_strip_%s_%s" % [
		absi(set_piece_authority_key().hash()), char_id
	])

func _on_plate_external_traversal_finished(
		char_id: String, traversal_id: StringName
	) -> void:
	if traversal_id != _plate_approach_traversal_id(char_id) \
			or not _plate_approach_ids.has(char_id):
		return
	_plate_approach_ids.erase(char_id)
	var gs = _get_game_state()
	var sc = _scrap_for_id(char_id)
	var contact := _plate_contact_for_scrap(char_id)
	if _plate_state == "placed" and gs != null and sc != null and sc.is_alive() \
			and str(sc.get_state()) == "idle" \
			and gs.get_position(char_id).distance_to(contact) <= PLATE_CONTACT_TOLERANCE:
		_add_plate_stripper(char_id)
	else:
		_plate_strip_interrupt_reason = "missed_contact"
		_apply_hoist_presenter()
		_publish_set_piece_authority()

func _on_plate_external_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if traversal_id != _plate_approach_traversal_id(char_id):
		return
	_plate_approach_ids.erase(char_id)
	_plate_strip_interrupt_reason = str(reason)
	_apply_hoist_presenter()
	_publish_set_piece_authority()

func _on_plate_scrap_movement_started(char_id: String) -> void:
	if _plate_strip_ids.has(char_id):
		_remove_plate_stripper(char_id, "moved_away")

func _on_plate_scrap_died(char_id: String) -> void:
	var gs = _get_game_state()
	if gs != null:
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if traversal.get("traversal_id", &"") == _plate_approach_traversal_id(char_id):
			gs.cancel_external_traversal(char_id, &"stripper_died")
	if _plate_strip_ids.has(char_id):
		_remove_plate_stripper(char_id, "stripper_died")

func _add_plate_stripper(char_id: String) -> void:
	if _plate_strip_ids.has(char_id):
		return
	_freeze_plate_strip_progress()
	_plate_strip_ids.append(char_id)
	_plate_strip_interrupt_reason = ""
	_rearm_plate_strip_deadline()
	_apply_hoist_presenter()
	_publish_set_piece_authority()

func _remove_plate_stripper(char_id: String, reason: String) -> void:
	if not _plate_strip_ids.has(char_id):
		return
	_freeze_plate_strip_progress()
	_plate_strip_ids.erase(char_id)
	_plate_strip_interrupt_reason = reason
	_rearm_plate_strip_deadline()
	_apply_hoist_presenter()
	_publish_set_piece_authority()

func _freeze_plate_strip_progress() -> void:
	_plate_integrity = _current_plate_integrity()
	_plate_strip_started_at = -1.0
	_plate_strip_deadline = -1.0
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_set_piece_tag("plate_strip"))

func _rearm_plate_strip_deadline() -> void:
	if _plate_state != "placed" or _plate_strip_ids.is_empty() or _plate_integrity <= 0.0:
		_plate_strip_started_at = -1.0
		_plate_strip_deadline = -1.0
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_plate_strip_started_at = float(sched.get_current_tick())
	# Each contacting scrap strips at the same visible rate. Two bodies therefore halve the
	# remaining interval, and removing one freezes the exact stock before the slower phase resumes.
	_plate_strip_deadline = _plate_strip_started_at \
		+ _plate_integrity * PLATE_STRIP_TIME / float(_plate_strip_ids.size())
	_schedule_set_piece_deadline(
		_plate_strip_deadline, _commit_plate_strip, _set_piece_tag("plate_strip")
	)

func _current_plate_integrity() -> float:
	if _plate_strip_started_at < 0.0 or _plate_strip_ids.is_empty():
		return clampf(_plate_integrity, 0.0, 1.0)
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else _plate_strip_started_at
	var elapsed := maxf(0.0, now - _plate_strip_started_at)
	var spent := elapsed * float(_plate_strip_ids.size()) / PLATE_STRIP_TIME
	return clampf(_plate_integrity - spent, 0.0, 1.0)

func _commit_plate_strip() -> void:
	if _plate_state != "placed":
		_freeze_plate_strip_progress()
		_publish_set_piece_authority()
		return
	# A callback may share a tick with death, lure movement, or magnet capture. Contact is checked
	# again at the consequence boundary; a stale remote eater can never remove topology.
	var valid_ids: Array[String] = []
	for char_id in _plate_strip_ids:
		if _plate_stripper_has_contact(char_id):
			valid_ids.append(char_id)
	if valid_ids.size() != _plate_strip_ids.size():
		_freeze_plate_strip_progress()
		_plate_strip_ids = valid_ids
		_plate_strip_interrupt_reason = "contact_broken"
		_rearm_plate_strip_deadline()
		_apply_hoist_presenter()
		_publish_set_piece_authority()
		return
	_plate_integrity = _current_plate_integrity()
	if _plate_integrity > 0.0001:
		_rearm_plate_strip_deadline()
		_publish_set_piece_authority()
		return
	_plate_integrity = 0.0
	_plate_strip_started_at = -1.0
	_plate_strip_deadline = -1.0
	_plate_state = "eaten"
	_cancel_plate_scrap_approaches(&"plate_consumed")
	for char_id in _plate_strip_ids:
		var sc = _scrap_for_id(char_id)
		var gs = _get_game_state()
		if sc != null and sc.is_alive() and gs != null:
			sc.set_roam(gs.get_position(char_id), 1.2)
	_plate_strip_ids.clear()
	_apply_hoist_presenter()
	_apply_canal_blockers()
	_publish_set_piece_authority()

func _plate_stripper_has_contact(char_id: String) -> bool:
	var gs = _get_game_state()
	var sc = _scrap_for_id(char_id)
	if gs == null or sc == null or not sc.is_alive() or _pinned.has(sc) \
			or str(sc.get_state()) != "idle" or gs.is_external_traversal_active(char_id):
		return false
	return gs.get_position(char_id).distance_to(
		_plate_contact_for_scrap(char_id)) <= PLATE_CONTACT_TOLERANCE

func _scrap_for_id(char_id: String):
	for sc in _scraps:
		if sc != null and is_instance_valid(sc) and str(sc.char_id) == char_id:
			return sc
	return null

func _interrupt_plate_pressure_under_magnet(station: Vector3) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for sc in _scraps:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		var char_id := str(sc.char_id)
		var pos: Vector3 = gs.get_position(char_id)
		if Vector2(pos.x, pos.z).distance_to(Vector2(station.x, station.z)) >= PIN_RADIUS:
			continue
		if _plate_strip_ids.has(char_id):
			_remove_plate_stripper(char_id, "magnet_capture")
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if traversal.get("traversal_id", &"") == _plate_approach_traversal_id(char_id):
			gs.cancel_external_traversal(char_id, &"magnet_capture")

func _cancel_plate_scrap_approaches(reason: StringName) -> void:
	var gs = _get_game_state()
	if gs == null:
		_plate_approach_ids.clear()
		return
	for char_id in _plate_approach_ids.duplicate():
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if traversal.get("traversal_id", &"") == _plate_approach_traversal_id(char_id):
			gs.cancel_external_traversal(char_id, reason)
	_plate_approach_ids.clear()

func _reconcile_plate_scrap_pressure() -> void:
	if _plate_state != "placed":
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in _plate_approach_ids.duplicate():
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if traversal.get("traversal_id", &"") != _plate_approach_traversal_id(char_id):
			_plate_approach_ids.erase(char_id)
			_plate_strip_interrupt_reason = "approach_interrupted"
	for char_id in _plate_strip_ids.duplicate():
		if not _plate_stripper_has_contact(char_id):
			_remove_plate_stripper(char_id, "contact_broken")
	_begin_plate_scrap_approaches()

func _any_scrap_alive() -> bool:
	for sc in _scraps:
		if sc != null and is_instance_valid(sc) and sc.is_alive():
			return true
	return false

func _set_magnet_glow(on: bool) -> void:
	if _trolley == null:
		return
	var mag: Variant = _trolley.find_child("Magnet", true, false)
	if mag != null and (mag as MeshInstance3D).material_override is StandardMaterial3D:
		((mag as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 1.4 if on else 0.0

func _apply_canal_blockers() -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for c in CANAL_CELLS:
		if _plate_state == "placed":
			gs.grid.remove_dynamic_blocker(c as Vector2i)
		else:
			gs.grid.add_dynamic_blocker(c as Vector2i, "hoist_canal")

# --- runtime state (lazy: needs the host's game_state/grid/scheduler) --------------------------

func _ensure_runtime() -> void:
	if _runtime_ready:
		return
	var gs = _get_game_state()
	if gs == null or gs.grid == null or _get_scheduler() == null:
		return
	_runtime_ready = true
	_apply_bridge_blockers()
	_apply_slab_blockers()
	_apply_canal_blockers()
	# WATER is see-over terrain: it blocks movement (WALL tiles / dynamic blockers) but never sight —
	# an enemy across the basin or canal can still spot you at range
	for wx in range(20, 28):
		for wz in range(9, 13):
			if not gs.grid.is_walkable(wx, wz):
				gs.grid.add_sight_transparent(Vector2i(wx, wz))
	for cc in CANAL_CELLS:
		gs.grid.add_sight_transparent(cc as Vector2i)
	for cx2 in range(14, 17):
		for cz2 in range(17, 22):
			gs.grid.add_sight_transparent(Vector2i(cx2, cz2))
	# the PEN enemy — roams its shelf; drowns at HIGH (sees ACROSS the water it stands in)
	_pen_enemy = _spawn_lurker("pen_lurker", "PenLurker", Vector3(27.0, 0.0, 10.5), 0.9, 3.5)
	# the SLAB enemy — roams beneath the weak facade; the intact slab BLOCKS its line of sight
	_slab_enemy = _spawn_lurker("slab_lurker", "SlabLurker", Vector3(25.5, 0.0, 2.2), 0.7, 4.0)
	# the SCRAP swarm — iron-laden strippers roaming the hoist's east bank (they eat placed plates);
	# short-sighted fodder, but the canal doesn't hide you from them (water is see-over)
	_scraps = [
		_spawn_lurker("scrap_a", "ScrapA", Vector3(21.2, 0.0, 19.2), 1.1, 2.8),
		_spawn_lurker("scrap_b", "ScrapB", Vector3(22.0, 0.0, 20.0), 1.1, 2.8),
	]
	_bind_plate_scrap_signals()
	for sc in _scraps:
		var died_callback := _on_plate_scrap_died.bind(str(sc.char_id))
		if not sc.died.is_connected(died_callback):
			sc.died.connect(died_callback)
	_initialize_or_restore_set_piece_authority()

func _spawn_lurker(id: String, node_name: String, anchor: Vector3, roam_r: float, detect := 3.5) -> Node:
	var gs = _get_game_state()
	var enemy = EnemyScript.new()
	enemy.name = node_name
	enemy.position = anchor
	enemy.move_speed = 1.3
	enemy.detection_range = detect
	enemy.char_id = id
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	# A fresh presenter may be attached to an already-deserialized GameState. Never replace that
	# authoritative character merely because its visual enemy node has just been constructed.
	if not gs.characters.has(enemy.char_id):
		gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	else:
		enemy.position = gs.get_position(enemy.char_id)
	enemy.activate()
	if not enemy._has_saved_enemy_authority():
		enemy.set_roam(anchor, roam_r)
	return enemy

func _bind_plate_scrap_signals() -> void:
	var gs = _get_game_state()
	if _plate_signal_game_state == gs:
		return
	_unbind_plate_scrap_signals()
	_plate_signal_game_state = gs
	if gs == null:
		return
	if not gs.external_traversal_finished.is_connected(
			_on_plate_external_traversal_finished):
		gs.external_traversal_finished.connect(_on_plate_external_traversal_finished)
	if not gs.external_traversal_cancelled.is_connected(
			_on_plate_external_traversal_cancelled):
		gs.external_traversal_cancelled.connect(_on_plate_external_traversal_cancelled)
	if not gs.movement_started.is_connected(_on_plate_scrap_movement_started):
		gs.movement_started.connect(_on_plate_scrap_movement_started)

func _unbind_plate_scrap_signals() -> void:
	if _plate_signal_game_state == null:
		return
	if _plate_signal_game_state.external_traversal_finished.is_connected(
			_on_plate_external_traversal_finished):
		_plate_signal_game_state.external_traversal_finished.disconnect(
			_on_plate_external_traversal_finished)
	if _plate_signal_game_state.external_traversal_cancelled.is_connected(
			_on_plate_external_traversal_cancelled):
		_plate_signal_game_state.external_traversal_cancelled.disconnect(
			_on_plate_external_traversal_cancelled)
	if _plate_signal_game_state.movement_started.is_connected(
			_on_plate_scrap_movement_started):
		_plate_signal_game_state.movement_started.disconnect(_on_plate_scrap_movement_started)
	_plate_signal_game_state = null

func _apply_slab_blockers() -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for c in TRENCH_CELLS:
		if _slab_intact or not RUBBLE_OPEN.has(c):
			gs.grid.add_dynamic_blocker(c as Vector2i, "trench")
		else:
			gs.grid.remove_dynamic_blocker(c as Vector2i)
	for sc in [Vector2i(24, 4), Vector2i(25, 4), Vector2i(26, 4)]:
		if _slab_intact:
			gs.grid.add_dynamic_blocker(sc, "weak_slab")
			gs.grid.add_sight_blocker(sc)     # the intact facade blocks LINE OF SIGHT too —
		else:                                 # crumbling it opens the sightline both ways
			gs.grid.remove_dynamic_blocker(sc)
			gs.grid.clear_sight_blocker(sc)

func reset_preview_state() -> void:
	_cancel_set_piece_callbacks()
	_kill_visual_tweens()
	_cancel_pinned_payload_transits(&"hoist_reset")
	_cancel_plate_scrap_approaches(&"plate_reset")
	_water_level = LEVEL_LOW
	_pending_level = -1
	_basin_fill_deadline = -1.0
	_hub_rot = 0
	_hub_phase = "idle"
	_hub_origin_rot = 0
	_hub_target_rot = 0
	_hub_rotation_started_at = -1.0
	_hub_rotation_deadline = -1.0
	_crawling.clear()
	_slab_intact = true
	_slab_fall_started_at = -1.0
	_slab_crumble_deadline = -1.0
	if _slab_node != null:
		_slab_node.rotation = Vector3.ZERO
	for m in _slab_meshes:
		if m != null and is_instance_valid(m):
			(m as Node3D).visible = true
	if _rubble != null:
		_rubble.visible = false
	_trolley_station = 0
	_trolley_phase = "idle"
	_trolley_origin_station = 0
	_trolley_target_station = 0
	_trolley_travel_started_at = -1.0
	_trolley_travel_deadline = -1.0
	_magnet_carrying = ""
	_plate_state = "stored"
	_plate_station = 0
	_magnet_phase = "idle"
	_magnet_phase_started_at = -1.0
	_magnet_phase_deadline = -1.0
	_plate_approach_ids.clear()
	_plate_strip_ids.clear()
	_plate_integrity = 1.0
	_plate_strip_started_at = -1.0
	_plate_strip_deadline = -1.0
	_plate_strip_interrupt_reason = ""
	for sc in _scraps:
		if sc != null and is_instance_valid(sc) and sc.is_alive():
			var home := _scrap_home_position(str(sc.char_id))
			sc.re_post(home)
			sc.set_roam(home, 1.1)
	_pinned.clear()
	if _trolley != null:
		_trolley.position.x = float(STATION_X[0])
	if _plate != null:
		_plate.visible = true
		_plate.position = Vector3(float(STATION_X[0]), 0.12, HOIST_Z)
	if _crumbs != null:
		_crumbs.visible = false
	_set_magnet_glow(false)
	_reset_set_piece_controls()
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_refresh_mechanism_controls()
	_apply_water_visual(false)
	if _runtime_ready:
		_apply_bridge_blockers()
		_apply_slab_blockers()
		_apply_canal_blockers()
	_publish_set_piece_authority()

func _process(_delta: float) -> void:
	_ensure_runtime()
	_reconcile_plate_scrap_pressure()
	_update_transit_presenters()

func headless_process(_delta: float) -> void:
	_ensure_runtime()
	_reconcile_plate_scrap_pressure()
	_update_transit_presenters()

# --- exact physical control authority ---------------------------------------------------------

## Set-piece controls are intentionally one-shot at the Interactable layer even when the mechanism
## itself is repeatable. A successful trigger therefore leaves a synchronous, actor-specific receipt;
## the consequence callback consumes that receipt and then explicitly re-arms the physical control.
## Calling one of the handlers, emitting `interacted`, or changing the selected portrait cannot stand
## in for a body that actually reached and used the authored wheel/valve/lever.
func _configure_set_piece_control(
	control: Node, action_id: String, callback: Callable
) -> void:
	if not is_instance_valid(control):
		return
	control.set_pre_trigger_validator(
		_validate_set_piece_control_trigger.bind(action_id, control))
	control.interacted.connect(callback.bind(control))


func _validate_set_piece_control_trigger(
	source: Node,
	actor: String,
	action_id: String,
	expected_source: Node
) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and source == _set_piece_control_for_action(action_id) \
		and _set_piece_interaction_actor_ready_at(source, actor) \
		and _set_piece_control_action_ready(action_id)


func _set_piece_control_receipt_pending(source: Node, action_id: String) -> bool:
	if not is_instance_valid(source) or source != _set_piece_control_for_action(action_id):
		return false
	var actor := str(source.get("active_character"))
	return _validate_set_piece_control_trigger(source, actor, action_id, source) \
		and _set_piece_consumed_source_receipt(source, actor)


func _set_piece_consumed_source_receipt(source: Node, actor: String) -> bool:
	if not is_instance_valid(source) or str(source.get("active_character")) != actor \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and bool(spec.get("triggered", false)) \
		and not bool(spec.get("enabled", true)) \
		and str(spec.get("last_trigger_character", "")) == actor \
		and int(spec.get("trigger_count", 0)) > 0


func _set_piece_interaction_actor_ready_at(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor not in PARTY_IDS or not gs.characters.has(actor) \
			or not gs.is_narratively_available(actor) or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor) \
			or gs.is_pushing(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := _set_piece_control_data_position(source)
	var actor_position: Vector3 = gs.get_position(actor)
	var radius := float(source.get("interaction_radius")) + CONTROL_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius


func _set_piece_control_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get(
			"position", Vector3.ZERO)
		if saved_position is Vector3:
			return saved_position
	var world_position := (source as Node3D).global_position \
		if source is Node3D else Vector3.ZERO
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(world_position)
	return world_position


func _set_piece_control_action_ready(action_id: String) -> bool:
	if _get_scheduler() == null:
		return false
	match action_id:
		"wheel":
			return _hub_phase == "idle"
		"valve":
			return _pending_level < 0
		"strut":
			return _slab_intact and _slab_crumble_deadline < 0.0
		"hoist_switch":
			return _trolley_phase == "idle" and _magnet_phase == "idle" \
				and _hoist_payload_can_shunt()
		"hoist_lever":
			return _trolley_phase == "idle" and _magnet_phase == "idle" \
				and _hoist_magnet_has_action()
	return false


func _hoist_payload_can_shunt() -> bool:
	if _magnet_carrying != "swarm":
		return true
	var gs = _get_game_state()
	if gs == null:
		return false
	var found_live := false
	for sc in _pinned:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive():
			continue
		found_live = true
		if not gs.characters.has(str(sc.char_id)) \
				or gs.is_external_traversal_active(str(sc.char_id)):
			return false
	return found_live


func _hoist_magnet_has_action() -> bool:
	if _magnet_carrying == "plate":
		return true
	var gs = _get_game_state()
	if _magnet_carrying == "swarm":
		if gs == null:
			return false
		var found_payload := false
		for sc in _pinned:
			if sc == null or not is_instance_valid(sc) or not sc.is_alive():
				continue
			found_payload = true
			if not gs.characters.has(str(sc.char_id)) \
					or gs.is_external_traversal_active(str(sc.char_id)):
				return false
		return found_payload
	if _plate_state == "stored" and _plate_station == _trolley_station:
		return true
	if _trolley_station != 2 or gs == null:
		return false
	var station := Vector3(float(STATION_X[_trolley_station]), 0.0, HOIST_Z)
	for sc in _scraps:
		if sc == null or not is_instance_valid(sc) or not sc.is_alive() \
				or not gs.characters.has(str(sc.char_id)):
			continue
		var char_id := str(sc.char_id)
		var position: Vector3 = gs.get_position(char_id)
		if Vector2(position.x, position.z).distance_to(
				Vector2(station.x, station.z)) >= PIN_RADIUS:
			continue
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		if not gs.is_external_traversal_active(char_id) \
				or traversal.get("traversal_id", &"") \
					== _plate_approach_traversal_id(char_id):
			return true
	return false


func _set_piece_control_for_action(action_id: String) -> Node:
	match action_id:
		"wheel":
			return _hub_wheel
		"valve":
			return _water_valve
		"strut":
			return _slab_strut
		"hoist_switch":
			return _hoist_switch
		"hoist_lever":
			return _hoist_lever
	return null


func _rearm_set_piece_control(source: Node) -> void:
	if is_instance_valid(source) and source.has_method("reset"):
		source.reset()
	_refresh_mechanism_controls()


func _reset_set_piece_controls() -> void:
	for source in [
		_hub_wheel, _water_valve, _slab_strut, _hoist_switch, _hoist_lever,
	]:
		if is_instance_valid(source) and source.has_method("reset"):
			source.reset()
	_refresh_mechanism_controls()


## A save taken from GameState's synchronous `interactable_triggered` signal contains an accepted
## source receipt but no mechanism commitment yet. Restoring that seam must offer the same action
## again; a genuinely committed phase instead projects the control's disabled/used truth.
func _normalize_set_piece_control_receipts() -> void:
	var gs = _get_game_state()
	for source in [
		_hub_wheel, _water_valve, _slab_strut, _hoist_switch, _hoist_lever,
	]:
		_ensure_set_piece_control_registry_shape(source)
	for action_id in ["wheel", "valve", "hoist_switch", "hoist_lever"]:
		var source := _set_piece_control_for_action(action_id)
		if not is_instance_valid(source):
			continue
		var data_id := str(source.get("data_id"))
		var triggered := bool(gs.get_interactable(data_id).get("triggered", false)) \
			if gs != null and data_id != "" and gs.has_interactable(data_id) else false
		if triggered or bool(source.get("_used")):
			source.reset()
	if is_instance_valid(_slab_strut):
		if _slab_intact and _slab_crumble_deadline < 0.0:
			var strut_id := str(_slab_strut.get("data_id"))
			var stale_strut_receipt := bool(gs.get_interactable(strut_id).get(
				"triggered", false)) if gs != null and strut_id != "" \
				and gs.has_interactable(strut_id) else false
			if stale_strut_receipt or bool(_slab_strut.get("_used")):
				_slab_strut.reset()
		elif _slab_strut.has_method("restore_one_shot_presenter"):
			_slab_strut.restore_one_shot_presenter(true, false)
	_refresh_mechanism_controls()


## Versions 2-5 authored the cycling controls as non-one-shots. Their mechanism world-state remains
## valid, but that old registry shape cannot produce a consumable source receipt. Re-register only
## the same physical id/spec as receipt-producing; preserve its monotonic trigger history while the
## mechanism authority above decides whether the presenter is currently enabled.
func _ensure_set_piece_control_registry_shape(source: Node) -> void:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return
	var spec: Dictionary = gs.get_interactable(data_id)
	if bool(spec.get("one_shot", false)):
		return
	spec["id"] = data_id
	spec["one_shot"] = true
	spec["enabled"] = true
	gs.register_interactable(spec)
	source.set("one_shot", true)

# --- set piece B: rotation ---------------------------------------------------------------------

func _on_wheel_pushed(source: Node = null) -> bool:
	if not _set_piece_control_receipt_pending(source, "wheel"):
		return false
	var sched = _get_scheduler()
	if sched == null:
		_rearm_set_piece_control(source)
		return false
	_hub_phase = "rotating"
	_hub_origin_rot = _hub_rot
	_hub_target_rot = (_hub_rot + 1) % 4
	_hub_rotation_started_at = float(sched.get_current_tick())
	_hub_rotation_deadline = _hub_rotation_started_at + HUB_ROTATE_TIME
	_refresh_hub_mouths()
	_refresh_mechanism_controls()
	_publish_set_piece_authority()
	_schedule_set_piece_deadline(
		_hub_rotation_deadline, _commit_hub_rotation, _set_piece_tag("hub_rotation")
	)
	_apply_hub_visual(false)
	_rearm_set_piece_control(source)
	return true

func _commit_hub_rotation() -> void:
	if _hub_phase != "rotating":
		_hub_rotation_deadline = -1.0
		_publish_set_piece_authority()
		return
	_hub_rot = _hub_target_rot
	_hub_phase = "idle"
	_hub_origin_rot = _hub_rot
	_hub_target_rot = _hub_rot
	_hub_rotation_started_at = -1.0
	_hub_rotation_deadline = -1.0
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_refresh_mechanism_controls()
	_publish_set_piece_authority()

func _hub_aligned() -> bool:
	return _hub_phase == "idle" and _hub_rot == HUB_ALIGNED_ROT

func _apply_hub_visual(_animate: bool) -> void:
	if _hub_node == null:
		return
	var origin_angle := _hub_angle_for_rot(_hub_rot)
	var target_angle := origin_angle
	if _hub_phase == "rotating":
		origin_angle = _hub_angle_for_rot(_hub_origin_rot)
		target_angle = _hub_angle_for_rot(_hub_target_rot)
	_hub_node.rotation.y = lerp_angle(origin_angle, target_angle, _hub_rotation_progress())

func _hub_angle_for_rot(rot: int) -> float:
	return deg_to_rad(-90.0 * float(rot) + 45.0)

func _hub_rotation_progress() -> float:
	if _hub_phase != "rotating":
		return 1.0
	return _phase_progress(_hub_rotation_started_at, _hub_rotation_deadline)

func _refresh_hub_mouths() -> void:
	for mname in _mouth_nodes.keys():
		var ia = _mouth_nodes[mname]
		if ia != null and is_instance_valid(ia):
			ia.set_interaction_enabled(_hub_aligned())

func _refresh_mechanism_controls() -> void:
	if _hub_wheel != null and is_instance_valid(_hub_wheel):
		_hub_wheel.set_interaction_enabled(_hub_phase == "idle")
	if _water_valve != null and is_instance_valid(_water_valve):
		_water_valve.set_interaction_enabled(_pending_level < 0)
	if _slab_strut != null and is_instance_valid(_slab_strut):
		_slab_strut.set_interaction_enabled(
			_slab_intact and _slab_crumble_deadline < 0.0)
	var hoist_idle := _trolley_phase == "idle" and _magnet_phase == "idle"
	if _hoist_switch != null and is_instance_valid(_hoist_switch):
		_hoist_switch.set_interaction_enabled(hoist_idle)
	if _hoist_lever != null and is_instance_valid(_hoist_lever):
		_hoist_lever.set_interaction_enabled(hoist_idle)

# --- set pieces A/B: the crawl -----------------------------------------------------------------

## Place a CrawlTunnel mouth (the reusable squeeze-through object). It owns the crawl mechanics —
## conceal + slow + authored path + PORTAL-STYLE group queueing (the whole selection lines up and
## enters one by one). The chunk just tracks who's inside for get_preview_state.
func _add_crawl_tunnel(tunnel_name: String, description: String, mouth: Vector3,
		waypoints: Array, radius: float) -> CrawlTunnel:
	var ct := CrawlTunnel.new()
	ct.name = tunnel_name
	ct.description = description
	ct.tutorial_label = "CRAWL IN"
	ct.configure(_get_game_state(), mouth, waypoints, radius, CRAWL_SPEED)
	ct.set_group_provider(_selected_party_ids)
	add_child(ct)
	_register_interactable(ct)
	ct.crawl_started.connect(func(who: String) -> void: _crawling[who] = true)
	ct.crawl_finished.connect(func(who: String) -> void: _crawling.erase(who))
	_auto_outline_interactable(ct, self, mouth, radius)
	if "_outline_target" in ct and ct.get("_outline_target") == null:
		call_deferred("_auto_outline_interactable", ct, self, mouth, radius)
	return ct

## The host's live selection (the crawl group provider — a click queues whoever is selected).
func _selected_party_ids() -> Array:
	if host != null and host.has_method("get_preview_selected_characters"):
		return host.call("get_preview_selected_characters")
	return []

# --- set piece C: the water level ----------------------------------------------------------------

func _on_valve_used(source: Node = null) -> bool:
	if not _set_piece_control_receipt_pending(source, "valve"):
		return false
	var sched = _get_scheduler()
	if sched == null:
		_rearm_set_piece_control(source)
		return false
	_pending_level = (_water_level + 1) % 3
	_basin_fill_deadline = float(sched.get_current_tick()) + FILL_TIME
	_publish_set_piece_authority()
	_schedule_set_piece_deadline(
		_basin_fill_deadline, _commit_level, _set_piece_tag("basin_fill")
	)
	_rearm_set_piece_control(source)
	return true

func _commit_level() -> void:
	if _pending_level < 0:
		_basin_fill_deadline = -1.0
		_publish_set_piece_authority()
		return
	_water_level = _pending_level
	_pending_level = -1
	_basin_fill_deadline = -1.0
	_refresh_mechanism_controls()
	_apply_water_visual()
	_apply_bridge_blockers()
	# the DROWN rule: at HIGH the pen shelf submerges (decided here, at the commit tick — analytic)
	if _water_level == LEVEL_HIGH and _pen_enemy != null and is_instance_valid(_pen_enemy) and _pen_enemy.is_alive():
		var gs = _get_game_state()
		if gs != null:
			gs.command_stop(_pen_enemy.char_id)
		_pen_enemy.take_damage(float(_pen_enemy.max_hp))
	_publish_set_piece_authority()

func _apply_water_visual(animate := true) -> void:
	var y := float(WATER_Y[_water_level])
	if _water_plane != null:
		if animate:
			var tw := _new_visual_tween()
			tw.tween_property(_water_plane, "position:y", y, 0.5)
		else:
			_water_plane.position.y = y
	for fl in _floats:
		if fl != null and is_instance_valid(fl):
			if animate:
				var tw2 := _new_visual_tween()
				tw2.tween_property(fl, "position:y", y + 0.14, 0.5)
			else:
				fl.position.y = y + 0.14

func _apply_bridge_blockers() -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for c in BRIDGE_CELLS:
		var cell := c as Vector2i
		if _water_level == LEVEL_MID:
			gs.grid.remove_dynamic_blocker(cell)
		else:
			gs.grid.add_dynamic_blocker(cell, "basin_water")

# --- portable mechanism authority ---------------------------------------------------------------

func set_piece_authority_key() -> String:
	var stable_id := chunk_name if chunk_name != "" else "set_piece_showcase"
	return SET_PIECE_AUTHORITY_PREFIX + stable_id

func _set_piece_authority_state() -> Dictionary:
	var pinned_ids: Array = []
	for sc in _pinned:
		if sc != null and is_instance_valid(sc):
			pinned_ids.append(str(sc.char_id))
	return {
		"version": SET_PIECE_AUTHORITY_VERSION,
		"water_level": _water_level,
		"pending_level": _pending_level,
		"basin_fill_deadline": _basin_fill_deadline,
		"hub_rot": _hub_rot,
		"hub_phase": _hub_phase,
		"hub_origin_rot": _hub_origin_rot,
		"hub_target_rot": _hub_target_rot,
		"hub_rotation_started_at": _hub_rotation_started_at,
		"hub_rotation_deadline": _hub_rotation_deadline,
		"slab_intact": _slab_intact,
		"slab_fall_started_at": _slab_fall_started_at,
		"slab_crumble_deadline": _slab_crumble_deadline,
		"trolley_station": _trolley_station,
		"trolley_phase": _trolley_phase,
		"trolley_origin_station": _trolley_origin_station,
		"trolley_target_station": _trolley_target_station,
		"trolley_travel_started_at": _trolley_travel_started_at,
		"trolley_travel_deadline": _trolley_travel_deadline,
		"magnet_carrying": _magnet_carrying,
		"plate_state": _plate_state,
		"plate_station": _plate_station,
		"magnet_phase": _magnet_phase,
		"magnet_phase_started_at": _magnet_phase_started_at,
		"magnet_phase_deadline": _magnet_phase_deadline,
		"pinned_ids": pinned_ids,
		"plate_approach_ids": _plate_approach_ids.duplicate(),
		"plate_strip_ids": _plate_strip_ids.duplicate(),
		"plate_integrity": _plate_integrity,
		"plate_strip_started_at": _plate_strip_started_at,
		"plate_strip_deadline": _plate_strip_deadline,
		"plate_strip_interrupt_reason": _plate_strip_interrupt_reason,
	}

func _publish_set_piece_authority() -> void:
	if _restoring_set_piece_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(set_piece_authority_key(), _set_piece_authority_state())

func _initialize_or_restore_set_piece_authority() -> void:
	if _set_piece_authority_initialized:
		return
	_set_piece_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(set_piece_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if raw is Dictionary and int(raw.get("version", 0)) in [2, 3, 4, SET_PIECE_AUTHORITY_VERSION]:
		_restore_set_piece_authority(raw)
	else:
		_publish_set_piece_authority()

## Called by TutorialSequence after it clears opaque scheduler Callables and installs a snapshot.
## Restore is idempotent: old callbacks/tweens are retracted, topology is rebuilt, and each pending
## consequence gets exactly one callback at its original absolute tick.
func on_game_state_snapshot_restored() -> void:
	_cancel_set_piece_callbacks()
	_kill_visual_tweens()
	if not _runtime_ready:
		_set_piece_authority_initialized = false
		return
	_set_piece_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(set_piece_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary \
			or int(raw.get("version", 0)) not in [2, 3, 4, SET_PIECE_AUTHORITY_VERSION]:
		_retract_set_piece_to_defaults()
		_publish_set_piece_authority()
		return
	_restore_set_piece_authority(raw)

func _restore_set_piece_authority(saved: Dictionary) -> void:
	_restoring_set_piece_authority = true
	_cancel_set_piece_callbacks()
	_kill_visual_tweens()
	_crawling.clear()
	_water_level = clampi(int(saved.get("water_level", LEVEL_LOW)), LEVEL_LOW, LEVEL_HIGH)
	_pending_level = int(saved.get("pending_level", -1))
	if _pending_level < LEVEL_LOW or _pending_level > LEVEL_HIGH:
		_pending_level = -1
	_basin_fill_deadline = float(saved.get("basin_fill_deadline", -1.0)) \
		if _pending_level >= 0 else -1.0
	_hub_rot = posmod(int(saved.get("hub_rot", 0)), 4)
	_hub_phase = str(saved.get("hub_phase", "idle"))
	if _hub_phase == "rotating":
		_hub_origin_rot = posmod(int(saved.get("hub_origin_rot", _hub_rot)), 4)
		_hub_target_rot = posmod(int(saved.get(
			"hub_target_rot", (_hub_origin_rot + 1) % 4)), 4)
		_hub_rotation_started_at = float(saved.get("hub_rotation_started_at", -1.0))
		_hub_rotation_deadline = float(saved.get("hub_rotation_deadline", -1.0))
		if _hub_target_rot != (_hub_origin_rot + 1) % 4 \
				or _hub_rotation_deadline <= _hub_rotation_started_at:
			_hub_phase = "idle"
		else:
			_hub_rot = _hub_origin_rot
	if _hub_phase != "rotating":
		_hub_phase = "idle"
		_hub_origin_rot = _hub_rot
		_hub_target_rot = _hub_rot
		_hub_rotation_started_at = -1.0
		_hub_rotation_deadline = -1.0
	_slab_intact = bool(saved.get("slab_intact", true))
	_slab_crumble_deadline = float(saved.get("slab_crumble_deadline", -1.0)) \
		if _slab_intact else -1.0
	_slab_fall_started_at = float(saved.get("slab_fall_started_at",
		_slab_crumble_deadline - CRUMBLE_DELAY)) if _slab_crumble_deadline >= 0.0 else -1.0
	if _slab_fall_started_at >= _slab_crumble_deadline:
		_slab_fall_started_at = _slab_crumble_deadline - CRUMBLE_DELAY
	_trolley_station = clampi(int(saved.get("trolley_station", 0)), 0, STATION_X.size() - 1)
	_trolley_phase = str(saved.get("trolley_phase", "idle"))
	if _trolley_phase == "travelling":
		_trolley_origin_station = clampi(int(saved.get(
			"trolley_origin_station", _trolley_station)), 0, STATION_X.size() - 1)
		_trolley_target_station = clampi(int(saved.get(
			"trolley_target_station", (_trolley_origin_station + 1) % STATION_X.size()
		)), 0, STATION_X.size() - 1)
		_trolley_travel_started_at = float(saved.get("trolley_travel_started_at", -1.0))
		_trolley_travel_deadline = float(saved.get("trolley_travel_deadline", -1.0))
		if _trolley_target_station != (_trolley_origin_station + 1) % STATION_X.size() \
				or _trolley_travel_deadline <= _trolley_travel_started_at:
			_trolley_phase = "idle"
		else:
			_trolley_station = _trolley_origin_station
	if _trolley_phase != "travelling":
		_trolley_phase = "idle"
		_trolley_origin_station = _trolley_station
		_trolley_target_station = _trolley_station
		_trolley_travel_started_at = -1.0
		_trolley_travel_deadline = -1.0
	_magnet_carrying = str(saved.get("magnet_carrying", ""))
	if _magnet_carrying not in ["", "plate", "swarm"]:
		_magnet_carrying = ""
	_plate_state = str(saved.get("plate_state", "stored"))
	if _plate_state not in ["stored", "held", "placed", "eaten"]:
		_plate_state = "stored"
	_plate_station = clampi(int(saved.get(
		"plate_station", 1 if _plate_state in ["placed", "eaten"] else 0
	)), 0, STATION_X.size() - 1)
	_magnet_phase = str(saved.get("magnet_phase", "idle"))
	if _magnet_phase not in [
		"idle", "lifting_plate", "lifting_swarm", "dropping_plate", "dropping_swarm"
	]:
		_magnet_phase = "idle"
	_magnet_phase_started_at = float(saved.get("magnet_phase_started_at", -1.0))
	_magnet_phase_deadline = float(saved.get("magnet_phase_deadline", -1.0))
	if _magnet_phase != "idle" and _magnet_phase_deadline <= _magnet_phase_started_at:
		_magnet_phase = "idle"
	if _magnet_phase == "idle":
		_magnet_phase_started_at = -1.0
		_magnet_phase_deadline = -1.0
	if _magnet_carrying == "plate":
		_plate_state = "held"
	elif _plate_state == "held" and _magnet_phase != "dropping_plate":
		_plate_state = "stored"
	var saved_version := int(saved.get("version", 0))
	_plate_approach_ids.clear()
	_plate_strip_ids.clear()
	_plate_integrity = clampf(float(saved.get("plate_integrity", 1.0)), 0.0, 1.0)
	_plate_strip_started_at = float(saved.get("plate_strip_started_at", -1.0))
	_plate_strip_deadline = float(saved.get("plate_strip_deadline", -1.0))
	_plate_strip_interrupt_reason = str(saved.get("plate_strip_interrupt_reason", ""))
	if saved_version == SET_PIECE_AUTHORITY_VERSION and _plate_state == "placed":
		for approach_variant in saved.get("plate_approach_ids", []) as Array:
			var approach_id := str(approach_variant)
			var approach_state: Dictionary = _get_game_state().get_external_traversal_state(
				approach_id)
			if _scrap_for_id(approach_id) != null and approach_state.get(
					"traversal_id", &"") == _plate_approach_traversal_id(approach_id):
				_plate_approach_ids.append(approach_id)
		for strip_variant in saved.get("plate_strip_ids", []) as Array:
			var strip_id := str(strip_variant)
			if _scrap_for_id(strip_id) != null and not _plate_approach_ids.has(strip_id):
				_plate_strip_ids.append(strip_id)
	if _plate_state != "placed" or _plate_strip_ids.is_empty() \
			or _plate_strip_deadline <= _plate_strip_started_at:
		_plate_strip_started_at = -1.0
		_plate_strip_deadline = -1.0
	_pinned.clear()
	var pinned_ids: Array = saved.get("pinned_ids", []) as Array
	if _magnet_carrying == "swarm" or _magnet_phase in ["lifting_swarm", "dropping_swarm"]:
		for sc in _scraps:
			if sc != null and is_instance_valid(sc) and pinned_ids.has(str(sc.char_id)):
				_pinned.append(sc)
		if _pinned.is_empty():
			if _magnet_carrying == "swarm":
				_magnet_carrying = ""
			_magnet_phase = "idle"
			_magnet_phase_started_at = -1.0
			_magnet_phase_deadline = -1.0

	_normalize_set_piece_control_receipts()
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_refresh_mechanism_controls()
	_apply_water_visual(false)
	_apply_slab_presenter()
	_apply_hoist_presenter()
	_set_magnet_glow(_magnet_carrying != "" or _magnet_phase != "idle")
	_apply_bridge_blockers()
	_apply_slab_blockers()
	_apply_canal_blockers()
	_restoring_set_piece_authority = false

	if _basin_fill_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_basin_fill_deadline, _commit_level, _set_piece_tag("basin_fill")
		)
	if _slab_crumble_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_slab_crumble_deadline, _commit_crumble, _set_piece_tag("slab_crumble")
		)
	if _plate_strip_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_plate_strip_deadline, _commit_plate_strip, _set_piece_tag("plate_strip")
		)
	elif _plate_state == "placed" and _plate_approach_ids.is_empty():
		# Version 4 carried only a remote disappearance deadline. Migrating it deliberately starts
		# the truthful physical cause from the restored scrap positions instead of honoring that lie.
		call_deferred("_begin_plate_scrap_approaches")
	if _hub_rotation_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_hub_rotation_deadline, _commit_hub_rotation, _set_piece_tag("hub_rotation")
		)
	if _trolley_travel_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_trolley_travel_deadline, _commit_trolley_arrival, _set_piece_tag("trolley_travel")
		)
	if _magnet_phase_deadline >= 0.0:
		_schedule_set_piece_deadline(
			_magnet_phase_deadline, _commit_magnet_operation, _set_piece_tag("magnet_operation")
		)

func _retract_set_piece_to_defaults() -> void:
	_restoring_set_piece_authority = true
	_crawling.clear()
	_water_level = LEVEL_LOW
	_pending_level = -1
	_basin_fill_deadline = -1.0
	_hub_rot = 0
	_hub_phase = "idle"
	_hub_origin_rot = 0
	_hub_target_rot = 0
	_hub_rotation_started_at = -1.0
	_hub_rotation_deadline = -1.0
	_slab_intact = true
	_slab_fall_started_at = -1.0
	_slab_crumble_deadline = -1.0
	_trolley_station = 0
	_trolley_phase = "idle"
	_trolley_origin_station = 0
	_trolley_target_station = 0
	_trolley_travel_started_at = -1.0
	_trolley_travel_deadline = -1.0
	_magnet_carrying = ""
	_plate_state = "stored"
	_plate_station = 0
	_magnet_phase = "idle"
	_magnet_phase_started_at = -1.0
	_magnet_phase_deadline = -1.0
	_plate_approach_ids.clear()
	_plate_strip_ids.clear()
	_plate_integrity = 1.0
	_plate_strip_started_at = -1.0
	_plate_strip_deadline = -1.0
	_plate_strip_interrupt_reason = ""
	_pinned.clear()
	_normalize_set_piece_control_receipts()
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_refresh_mechanism_controls()
	_apply_water_visual(false)
	_apply_slab_presenter()
	_apply_hoist_presenter()
	_apply_bridge_blockers()
	_apply_slab_blockers()
	_apply_canal_blockers()
	_restoring_set_piece_authority = false

func _apply_slab_presenter() -> void:
	if _slab_node != null and is_instance_valid(_slab_node):
		_slab_node.rotation.x = lerpf(0.0, -PI * 0.5, _slab_fall_progress())
	for mesh in _slab_meshes:
		if mesh != null and is_instance_valid(mesh):
			(mesh as Node3D).visible = _slab_intact
	if _rubble != null:
		_rubble.visible = not _slab_intact

func _apply_hoist_presenter() -> void:
	var trolley_x := _trolley_presenter_x()
	if _trolley != null:
		_trolley.position.x = trolley_x
	if _plate != null:
		_plate.visible = _plate_state != "eaten"
		var integrity := _current_plate_integrity() if _plate_state == "placed" else 1.0
		# The walkable footprint remains truthful until failure; thinning and fallen flecks show the
		# stock draining without visually claiming that half-open topology already exists.
		_plate.scale = Vector3(1.0, maxf(0.18, integrity), 1.0)
		var grounded := Vector3(float(STATION_X[_plate_station]), 0.12, HOIST_Z)
		var held := Vector3(trolley_x, MAGNET_HELD_Y, HOIST_Z)
		match _magnet_phase:
			"lifting_plate":
				_plate.position = grounded.lerp(held, _magnet_phase_progress())
			"dropping_plate":
				var landing := Vector3(float(STATION_X[_trolley_station]), 0.12, HOIST_Z)
				_plate.position = held.lerp(landing, _magnet_phase_progress())
			_:
				_plate.position = held if _plate_state == "held" else grounded
	if _crumbs != null:
		_crumbs.visible = _plate_state == "eaten" \
			or (_plate_state == "placed" and _current_plate_integrity() < 0.7)
	if _plate_strip_feedback != null:
		_plate_strip_feedback.visible = _plate_state == "placed" \
			and not _plate_strip_ids.is_empty()
		_plate_strip_feedback.rotation.y = (1.0 - _current_plate_integrity()) * TAU * 2.0
	_set_magnet_glow(_magnet_carrying != "" or _magnet_phase != "idle")

func _update_transit_presenters() -> void:
	if _hub_phase == "rotating":
		_apply_hub_visual(false)
	if _trolley_phase == "travelling":
		_apply_hoist_presenter()
	if _magnet_phase != "idle":
		_apply_hoist_presenter()
	if _plate_strip_started_at >= 0.0:
		_apply_hoist_presenter()
	if _slab_intact and _slab_crumble_deadline >= 0.0:
		_apply_slab_presenter()

func _trolley_presenter_x() -> float:
	if _trolley_phase != "travelling":
		return float(STATION_X[_trolley_station])
	return lerpf(
		float(STATION_X[_trolley_origin_station]),
		float(STATION_X[_trolley_target_station]),
		_trolley_travel_progress()
	)

func _trolley_travel_progress() -> float:
	if _trolley_phase != "travelling":
		return 1.0
	return _phase_progress(_trolley_travel_started_at, _trolley_travel_deadline)

func _magnet_phase_progress() -> float:
	if _magnet_phase == "idle":
		return 1.0
	return _phase_progress(_magnet_phase_started_at, _magnet_phase_deadline)

func _slab_fall_progress() -> float:
	if not _slab_intact:
		return 1.0
	if _slab_crumble_deadline < 0.0:
		return 0.0
	return _phase_progress(_slab_fall_started_at, _slab_crumble_deadline)

func _phase_progress(started_at: float, deadline: float) -> float:
	if deadline <= started_at:
		return 1.0
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else started_at
	return clampf((now - started_at) / (deadline - started_at), 0.0, 1.0)

func _phase_remaining(deadline: float) -> float:
	if deadline < 0.0:
		return 0.0
	var sched = _get_scheduler()
	var now := float(sched.get_current_tick()) if sched != null else deadline
	return maxf(0.0, deadline - now)

func _schedule_set_piece_deadline(deadline: float, callback: Callable, tag: String) -> void:
	var sched = _get_scheduler()
	if sched == null or deadline < 0.0:
		return
	sched.cancel_tag(tag)
	var now := float(sched.get_current_tick())
	sched.schedule_at(maxf(now, deadline), callback, tag)

func _cancel_set_piece_callbacks() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	for suffix in [
		"basin_fill", "slab_crumble", "plate_strip", "hub_rotation", "trolley_travel",
		"magnet_operation"
	]:
		sched.cancel_tag(_set_piece_tag(suffix))

func _set_piece_tag(suffix: String) -> String:
	return "set_piece_%s_%s" % [absi(set_piece_authority_key().hash()), suffix]

func _new_visual_tween() -> Tween:
	var tween := create_tween()
	_visual_tweens.append(tween)
	tween.finished.connect(_on_visual_tween_finished.bind(tween), CONNECT_ONE_SHOT)
	return tween

func _on_visual_tween_finished(tween: Tween) -> void:
	_visual_tweens.erase(tween)

func _kill_visual_tweens() -> void:
	var active := _visual_tweens.duplicate()
	_visual_tweens.clear()
	for tween in active:
		if tween != null and tween.is_valid():
			tween.kill()

func _exit_tree() -> void:
	_cancel_set_piece_callbacks()
	_kill_visual_tweens()
	_unbind_plate_scrap_signals()

# --- state for tests / overlay -------------------------------------------------------------------

func get_preview_state() -> Dictionary:
	var complete := false
	var gs = _get_game_state()
	if gs != null:
		for id in PARTY_IDS:
			if gs.characters.has(id) and (gs.get_position(id) as Vector3).distance_to(Vector3(27.5, 0.0, 15.0)) < 1.4:
				complete = true
	return {
		"hub_rot": _hub_rot,
		"hub_phase": _hub_phase,
		"hub_target_rot": _hub_target_rot,
		"hub_rotation_progress": _hub_rotation_progress(),
		"hub_rotation_remaining": _phase_remaining(_hub_rotation_deadline),
		"hub_aligned": _hub_aligned(),
		"hub_wheel_enabled": _hub_wheel != null and is_instance_valid(_hub_wheel) \
			and _hub_wheel.is_interaction_enabled(),
		"water_level": _water_level,
		"water_name": str(LEVEL_NAMES[_water_level]),
		"filling": _pending_level >= 0,
		"basin_fill_deadline": _basin_fill_deadline,
		"bridge_open": _water_level == LEVEL_MID,
		"pen_alive": _pen_enemy != null and is_instance_valid(_pen_enemy) and _pen_enemy.is_alive(),
		# Derived from each CrawlTunnel's authoritative queue/occupancy; the signal cache is only a
		# cheap live overlay hint and is intentionally not a second saved truth.
		"crawling": _any_crawl_occupants(),
		"slab_intact": _slab_intact,
		"slab_phase": "standing" if _slab_intact and _slab_crumble_deadline < 0.0 \
			else ("falling" if _slab_intact else "settled"),
		"slab_fall_started_at": _slab_fall_started_at,
		"slab_crumble_deadline": _slab_crumble_deadline,
		"slab_fall_progress": _slab_fall_progress(),
		"slab_angle": _slab_node.rotation.x if _slab_node != null else 0.0,
		"slab_enemy_alive": _slab_enemy != null and is_instance_valid(_slab_enemy) and _slab_enemy.is_alive(),
		"trolley_station": _trolley_station,
		"trolley_phase": _trolley_phase,
		"trolley_target_station": _trolley_target_station,
		"trolley_travel_progress": _trolley_travel_progress(),
		"trolley_travel_remaining": _phase_remaining(_trolley_travel_deadline),
		"trolley_x": _trolley_presenter_x(),
		"hoist_switch_enabled": _hoist_switch != null and is_instance_valid(_hoist_switch) \
			and _hoist_switch.is_interaction_enabled(),
		"hoist_lever_enabled": _hoist_lever != null and is_instance_valid(_hoist_lever) \
			and _hoist_lever.is_interaction_enabled(),
		"magnet_carrying": _magnet_carrying,
		"magnet_phase": _magnet_phase,
		"magnet_phase_progress": _magnet_phase_progress(),
		"magnet_phase_remaining": _phase_remaining(_magnet_phase_deadline),
		"plate": _plate_state,
		"plate_station": _plate_station,
		"plate_position": _plate.position if _plate != null else Vector3.ZERO,
		"plate_strip_phase": _plate_strip_phase(),
		"plate_approachers": _plate_approach_ids.duplicate(),
		"plate_strippers": _plate_strip_ids.duplicate(),
		"plate_integrity": _current_plate_integrity(),
		"plate_strip_progress": 1.0 - _current_plate_integrity(),
		"plate_strip_started_at": _plate_strip_started_at,
		"plate_strip_deadline": _plate_strip_deadline,
		"plate_strip_remaining": _phase_remaining(_plate_strip_deadline),
		"plate_strip_interrupt_reason": _plate_strip_interrupt_reason,
		"pinned": _pinned.size(),
		"scraps_alive": _scrap_alive_count(),
		"canal_open": _plate_state == "placed",
		"complete": complete,
	}

func _plate_strip_phase() -> String:
	if _plate_state == "eaten":
		return "eaten"
	if _plate_state != "placed":
		return "idle"
	if not _plate_strip_ids.is_empty():
		return "stripping"
	if not _plate_approach_ids.is_empty():
		return "approaching"
	return "interrupted" if not _plate_strip_interrupt_reason.is_empty() else "awaiting"

func _scrap_alive_count() -> int:
	var n := 0
	for sc in _scraps:
		if sc != null and is_instance_valid(sc) and sc.is_alive():
			n += 1
	return n

func _any_crawl_occupants() -> bool:
	for node in find_children("*", "", true, false):
		if node is CrawlTunnel and node.has_method("is_group_crawl_active") \
				and bool(node.call("is_group_crawl_active")):
			return true
	return not _crawling.is_empty()
