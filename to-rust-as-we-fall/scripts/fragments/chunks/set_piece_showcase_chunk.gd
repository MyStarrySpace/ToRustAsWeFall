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
## replay-safe. Visual motion (water/float/hub tweens) is cosmetic only.

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
const PLATE_EAT_TIME := 7.0                   # living scraps strip a placed plate in this long
const PIN_RADIUS := 2.6   # the magnet's grab disc covers the pen (both scraps' roam range)

var _runtime_ready := false
var _water_level := LEVEL_LOW
var _pending_level := -1
var _hub_rot := 0
var _hub_node: Node3D = null
var _water_plane: MeshInstance3D = null
var _floats: Array = []
var _pen_enemy: Node = null
var _crawling: Dictionary = {}          # char_id -> true while inside a pipe
var _mouth_nodes: Dictionary = {}       # name -> Area3D (for enabling the hub route)
var _slab_enemy: Node = null
var _slab_intact := true
var _slab_meshes: Array = []            # facade meshes hidden on crumble
var _rubble: Node3D = null              # the debris pile revealed on crumble
var _trolley: Node3D = null
var _plate: Node3D = null
var _crumbs: Node3D = null              # what's left of an eaten plate
var _trolley_station := 0
var _magnet_carrying := ""              # "" | "plate" | "swarm"
var _plate_state := "stored"            # stored | held | placed | eaten
var _scraps: Array = []                 # the iron-laden swarm (enemy nodes)
var _pinned: Array = []                 # scrap ids held under the charged magnet

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
	var wheel := _add_interactable(self, "HubWheel", "Push the wheel to rotate the pipe", Vector3(14.0, 0.5, 5.5),
		"PUSH", "", 1.0, false, 1.5, Interactable.InteractableType.INSPECTION, false)
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
	wheel.add_child(wmesh)
	_outline_interactable_child(wheel, wmesh, "HubWheel", 1.5)
	wheel.interacted.connect(_on_wheel_pushed)
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
	var valve := _add_interactable(self, "WaterValve", "Cycle the basin water level", Vector3(7.5, 0.5, 14.5),
		"VALVE", "", 1.0, false, 1.6, Interactable.InteractableType.INSPECTION, false)
	var vmesh := _add_box(valve, Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.5), Color(0.2, 0.4, 0.5), Color(0.3, 0.85, 1.0), 0.9)
	_outline_interactable_child(valve, vmesh, "WaterValve", 1.6)
	valve.interacted.connect(_on_valve_used)
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
	var strut := _add_interactable(self, "LooseStrut", "Pry the loose strut", Vector3(25.5, 0.5, 5.8),
		"PRY", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var smesh := _add_box(strut, Vector3(0, 0.9, 0), Vector3(0.22, 1.8, 0.22), Color(0.5, 0.42, 0.3), Color(0.9, 0.6, 0.2), 0.5)
	_outline_interactable_child(strut, smesh, "LooseStrut", 1.5)
	strut.interacted.connect(_on_strut_pried)
	# the rubble pile (hidden until the crumble) — covers the kill field + fills the trench cells
	_rubble = Node3D.new()
	_rubble.name = "RubblePile"
	add_child(_rubble)
	_rubble.position = Vector3(25.5, 0.0, 2.6)
	var rk := [Vector3(-0.6, 0.25, 0.3), Vector3(0.5, 0.2, 0.8), Vector3(0.1, 0.45, -0.2), Vector3(-0.3, 0.2, 1.1), Vector3(0.7, 0.3, -0.5)]
	for ri in range(rk.size()):
		_add_box(_rubble, rk[ri] as Vector3, Vector3(0.9 - 0.08 * float(ri), 0.5, 0.8), Color(0.30, 0.30, 0.33), Color.BLACK, 0.0, "Rubble%d" % ri)
	_rubble.visible = false

func _on_strut_pried() -> void:
	if not _slab_intact:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.schedule_after(CRUMBLE_DELAY, _commit_crumble, "slab_crumble")

func _commit_crumble() -> void:
	if not _slab_intact:
		return
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
	for m in _slab_meshes:
		if m != null and is_instance_valid(m):
			(m as Node3D).visible = false
	if _rubble != null:
		_rubble.visible = true

# E) the IRON-LOAD MAGNET HOIST: rail + trolley over a canal, a plate the swarm can EAT
func _build_magnet_hoist() -> void:
	_add_label(self, "MAGNET HOIST", Vector3(15.0, 4.6, 17.2), Color(0.95, 0.8, 0.5))
	# the CANAL (impassable water channel between the banks)
	_add_box(self, Vector3(15.5, -0.14, 19.5), Vector3(3.2, 0.24, 5.0), Color(0.10, 0.12, 0.15), Color.BLACK, 0.0, "HoistCanal")
	# rail posts + the overhead rail beam
	for px in [8.0, 23.0]:
		_add_box(self, Vector3(px, RAIL_Y * 0.5, HOIST_Z), Vector3(0.3, RAIL_Y, 0.3), Color(0.30, 0.30, 0.34))
	_add_box(self, Vector3(15.5, RAIL_Y, HOIST_Z), Vector3(16.0, 0.24, 0.4), Color(0.36, 0.35, 0.38), Color.BLACK, 0.0, "HoistRail")
	# the TROLLEY + electromagnet (cosmetic mover; the STATION index is the logic)
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
	# CONTROLS on the west bank: the track switch + the charge lever
	var sw := _add_interactable(self, "HoistSwitch", "Shunt the trolley to the next station", Vector3(9.0, 0.5, 18.0),
		"SHUNT", "", 1.0, false, 1.5, Interactable.InteractableType.INSPECTION, false)
	var swm := _add_box(sw, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4), Color(0.3, 0.35, 0.45), Color(0.4, 0.7, 1.0), 0.6)
	_outline_interactable_child(sw, swm, "HoistSwitch", 1.5)
	sw.interacted.connect(_on_hoist_shunt)
	var lv := _add_interactable(self, "HoistLever", "Charge / discharge the magnet", Vector3(12.0, 0.5, 18.0),
		"CHARGE", "", 1.0, false, 1.5, Interactable.InteractableType.INSPECTION, false)
	var lvm := _add_box(lv, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4), Color(0.45, 0.3, 0.25), Color(1.0, 0.45, 0.25), 0.6)
	_outline_interactable_child(lv, lvm, "HoistLever", 1.5)
	lv.interacted.connect(_on_hoist_lever)
	# the east-bank payoff pad
	_add_box(self, Vector3(24.5, 0.06, 20.5), Vector3(1.4, 0.12, 1.4), Color(0.4, 0.35, 0.2), Color(1.0, 0.8, 0.3), 0.7, "CachePad")
	_add_label(self, "CACHE", Vector3(24.5, 1.5, 20.5), Color(1.0, 0.85, 0.45))

func _on_hoist_shunt() -> void:
	_trolley_station = (_trolley_station + 1) % STATION_X.size()
	if _trolley != null:
		var tw := create_tween()
		tw.tween_property(_trolley, "position:x", float(STATION_X[_trolley_station]), 0.5)
	if _magnet_carrying == "plate" and _plate != null:
		var tw2 := create_tween()
		tw2.tween_property(_plate, "position:x", float(STATION_X[_trolley_station]), 0.5)

func _on_hoist_lever() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	if _magnet_carrying == "":
		# CHARGE: grab whatever iron sits under the trolley
		if _trolley_station == 0 and _plate_state == "stored":
			_magnet_carrying = "plate"
			_plate_state = "held"
			if _plate != null:
				var tw := create_tween()
				tw.tween_property(_plate, "position:y", RAIL_Y - 1.1, 0.4)
			_set_magnet_glow(true)
		elif _trolley_station == 2:
			var station := Vector3(float(STATION_X[2]), 0.0, HOIST_Z)
			for sc in _scraps:
				if sc != null and is_instance_valid(sc) and sc.is_alive():
					var sp: Vector3 = gs.get_position(sc.char_id)
					if Vector2(sp.x, sp.z).distance_to(Vector2(station.x, station.z)) < PIN_RADIUS:
						_pinned.append(sc)
						gs.command_stop(sc.char_id)
						gs.snap_character_to(sc.char_id, station + Vector3(float(_pinned.size()) * 0.4 - 0.6, 0.0, 0.3))
						sc.set_roam(gs.get_position(sc.char_id), 0.05)   # held under the magnet
			if not _pinned.is_empty():
				_magnet_carrying = "swarm"
				_set_magnet_glow(true)
	else:
		# DISCHARGE at the current station
		if _magnet_carrying == "plate":
			if _trolley_station == 1:
				_plate_state = "placed"
				if _plate != null:
					var tw3 := create_tween()
					tw3.tween_property(_plate, "position", Vector3(15.5, 0.12, HOIST_Z), 0.4)
				_apply_canal_blockers()
				# living scraps strip an unattended plate — the traversal DECAYS (analytic commit)
				if _any_scrap_alive():
					sched.schedule_after(PLATE_EAT_TIME, _commit_plate_eat, "plate_eat")
			else:
				_plate_state = "stored"
				if _plate != null:
					var tw4 := create_tween()
					tw4.tween_property(_plate, "position", Vector3(float(STATION_X[0]), 0.12, HOIST_Z), 0.4)
		elif _magnet_carrying == "swarm":
			if _trolley_station == 1:
				for sc in _pinned:
					if sc != null and is_instance_valid(sc) and sc.is_alive():
						gs.command_stop(sc.char_id)
						sc.take_damage(float(sc.max_hp))   # dropped into the canal
			else:
				for sc2 in _pinned:
					if sc2 != null and is_instance_valid(sc2) and sc2.is_alive():
						sc2.set_roam(gs.get_position(sc2.char_id), 1.2)
			_pinned.clear()
		_magnet_carrying = ""
		_set_magnet_glow(false)

func _commit_plate_eat() -> void:
	if _plate_state != "placed" or not _any_scrap_alive():
		return
	_plate_state = "eaten"
	if _plate != null:
		_plate.visible = false
	if _crumbs != null:
		_crumbs.visible = true
	_apply_canal_blockers()

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
	gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
		{"detection_range": float(enemy.detection_range)})
	enemy.activate()
	enemy.set_roam(anchor, roam_r)
	return enemy

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
	_water_level = LEVEL_LOW
	_pending_level = -1
	_hub_rot = 0
	_crawling.clear()
	_slab_intact = true
	for m in _slab_meshes:
		if m != null and is_instance_valid(m):
			(m as Node3D).visible = true
	if _rubble != null:
		_rubble.visible = false
	_trolley_station = 0
	_magnet_carrying = ""
	_plate_state = "stored"
	_pinned.clear()
	if _trolley != null:
		_trolley.position.x = float(STATION_X[0])
	if _plate != null:
		_plate.visible = true
		_plate.position = Vector3(float(STATION_X[0]), 0.12, HOIST_Z)
	if _crumbs != null:
		_crumbs.visible = false
	_set_magnet_glow(false)
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_apply_water_visual()
	if _runtime_ready:
		_apply_bridge_blockers()
		_apply_slab_blockers()
		_apply_canal_blockers()

func _process(delta: float) -> void:
	_ensure_runtime()

func headless_process(_delta: float) -> void:
	_ensure_runtime()

# --- set piece B: rotation ---------------------------------------------------------------------

func _on_wheel_pushed() -> void:
	_hub_rot = (_hub_rot + 1) % 4
	_apply_hub_visual(true)
	_refresh_hub_mouths()

func _hub_aligned() -> bool:
	return _hub_rot == HUB_ALIGNED_ROT

func _apply_hub_visual(animate: bool) -> void:
	if _hub_node == null:
		return
	var target := deg_to_rad(-90.0 * float(_hub_rot) + 45.0)   # rot 1 lines the bend W<->E
	if animate:
		var tw := create_tween()
		tw.tween_property(_hub_node, "rotation:y", target, 0.4)
	else:
		_hub_node.rotation.y = target

func _refresh_hub_mouths() -> void:
	for mname in _mouth_nodes.keys():
		var ia = _mouth_nodes[mname]
		if ia != null and is_instance_valid(ia):
			ia.set_interaction_enabled(_hub_aligned())

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

func _on_valve_used() -> void:
	if _pending_level >= 0:
		return   # mid-fill; the valve re-arms on commit
	var sched = _get_scheduler()
	if sched == null:
		return
	_pending_level = (_water_level + 1) % 3
	sched.schedule_after(FILL_TIME, _commit_level, "basin_fill")

func _commit_level() -> void:
	if _pending_level < 0:
		return
	_water_level = _pending_level
	_pending_level = -1
	_apply_water_visual()
	_apply_bridge_blockers()
	# the DROWN rule: at HIGH the pen shelf submerges (decided here, at the commit tick — analytic)
	if _water_level == LEVEL_HIGH and _pen_enemy != null and is_instance_valid(_pen_enemy) and _pen_enemy.is_alive():
		var gs = _get_game_state()
		if gs != null:
			gs.command_stop(_pen_enemy.char_id)
		_pen_enemy.take_damage(float(_pen_enemy.max_hp))

func _apply_water_visual() -> void:
	var y := float(WATER_Y[_water_level])
	if _water_plane != null:
		var tw := create_tween()
		tw.tween_property(_water_plane, "position:y", y, 0.5)
	for fl in _floats:
		if fl != null and is_instance_valid(fl):
			var tw2 := create_tween()
			tw2.tween_property(fl, "position:y", y + 0.14, 0.5)

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
		"hub_aligned": _hub_aligned(),
		"water_level": _water_level,
		"water_name": str(LEVEL_NAMES[_water_level]),
		"filling": _pending_level >= 0,
		"bridge_open": _water_level == LEVEL_MID,
		"pen_alive": _pen_enemy != null and is_instance_valid(_pen_enemy) and _pen_enemy.is_alive(),
		"crawling": _crawling.size() > 0,
		"slab_intact": _slab_intact,
		"slab_enemy_alive": _slab_enemy != null and is_instance_valid(_slab_enemy) and _slab_enemy.is_alive(),
		"trolley_station": _trolley_station,
		"magnet_carrying": _magnet_carrying,
		"plate": _plate_state,
		"scraps_alive": _scrap_alive_count(),
		"canal_open": _plate_state == "placed",
		"complete": complete,
	}

func _scrap_alive_count() -> int:
	var n := 0
	for sc in _scraps:
		if sc != null and is_instance_valid(sc) and sc.is_alive():
			n += 1
	return n
