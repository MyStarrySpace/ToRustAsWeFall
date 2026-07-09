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

func get_scene_title() -> String:
	return "Set Pieces — crawl / rotate / water"

func get_scene_help() -> String:
	return "Push the wheel to line up the bent pipe, crawl it east. Crawl the wall pipe north to reach the water valve. Set the water to MID so the floats bridge the basin; set HIGH to drown the penned threat. Reach the northeast pad."

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
	}

func get_grid_data() -> Dictionary:
	var bridge: Array = []
	for c in BRIDGE_CELLS:
		bridge.append([int((c as Vector2i).x), int((c as Vector2i).y)])
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0], "cell_size": 1.0, "width": 30, "height": 17,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [15.9, 9.9]},     # yard WEST (spawn, wheel)
			{"min": [18.0, 1.0], "max": [28.9, 8.9]},    # yard EAST (basin approach)
			{"min": [1.0, 13.0], "max": [28.9, 15.9]},   # north strip (valve, exit)
			{"min": [26.0, 9.0], "max": [27.9, 11.9]},   # the sunken PEN (enemy shelf)
		],
		"walkable_cells": bridge,                        # float bridge — blocked until MID
	}

func _build_chunk() -> void:
	_add_floor(self, Vector3(15.0, 0.0, 8.5), Vector3(30.0, 0.1, 17.0), Color(0.085, 0.09, 0.11))
	_add_label(self, "SET PIECES", Vector3(15.0, 3.4, 0.6), Color(0.9, 0.85, 0.6))
	_build_walls()
	_build_crawl_pipe()
	_build_rotating_hub()
	_build_basin()
	_add_light(self, Vector3(8.0, 5.0, 6.0), Color(1.0, 0.95, 0.85), 1.1, 18.0)
	_add_light(self, Vector3(23.0, 5.0, 11.0), Color(0.8, 0.92, 1.0), 1.1, 16.0)
	_add_light(self, Vector3(14.0, 5.0, 14.0), Color(1.0, 0.95, 0.85), 0.9, 14.0)

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
	var ia_s := _add_interactable(self, "PipeMouthSouth", "Crawl through the wall pipe", Vector3(4.5, 0.5, 8.2),
		"CRAWL IN", "", 1.0, false, 1.4, Interactable.InteractableType.INSPECTION, true)
	ia_s.interacted.connect(func() -> void: _start_crawl(ia_s, [Vector3(4.5, 0.0, 9.2), Vector3(4.5, 0.0, 13.8)]))
	var ia_n := _add_interactable(self, "PipeMouthNorth", "Crawl through the wall pipe", Vector3(4.5, 0.5, 13.8),
		"CRAWL IN", "", 1.0, false, 1.4, Interactable.InteractableType.INSPECTION, true)
	ia_n.interacted.connect(func() -> void: _start_crawl(ia_n, [Vector3(4.5, 0.0, 12.8), Vector3(4.5, 0.0, 8.2)]))

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
	var ia_w := _add_interactable(self, "HubMouthWest", "Crawl the aligned pipe", Vector3(15.0, 0.5, 5.5),
		"CRAWL IN", "", 1.0, false, 1.3, Interactable.InteractableType.INSPECTION, true)
	ia_w.interacted.connect(func() -> void: _start_crawl(ia_w, [Vector3(15.4, 0.0, 5.5), Vector3(19.2, 0.0, 5.5)]))
	var ia_e := _add_interactable(self, "HubMouthEast", "Crawl the aligned pipe", Vector3(19.0, 0.5, 5.5),
		"CRAWL IN", "", 1.0, false, 1.3, Interactable.InteractableType.INSPECTION, true)
	ia_e.interacted.connect(func() -> void: _start_crawl(ia_e, [Vector3(18.6, 0.0, 5.5), Vector3(14.8, 0.0, 5.5)]))
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

# --- runtime state (lazy: needs the host's game_state/grid/scheduler) --------------------------

func _ensure_runtime() -> void:
	if _runtime_ready:
		return
	var gs = _get_game_state()
	if gs == null or gs.grid == null or _get_scheduler() == null:
		return
	_runtime_ready = true
	_apply_bridge_blockers()
	# the PEN enemy — roams its shelf; drowns at HIGH
	var enemy = EnemyScript.new()
	enemy.name = "PenLurker"
	enemy.position = Vector3(27.0, 0.0, 10.5)
	enemy.move_speed = 1.3
	enemy.detection_range = 3.5
	enemy.char_id = "pen_lurker"
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	gs.register_character(enemy.char_id, enemy.position, enemy.move_speed,
		{"detection_range": float(enemy.detection_range)})
	enemy.activate()
	enemy.set_roam(Vector3(27.0, 0.0, 10.5), 0.9)
	_pen_enemy = enemy

func reset_preview_state() -> void:
	_water_level = LEVEL_LOW
	_pending_level = -1
	_hub_rot = 0
	_crawling.clear()
	_apply_hub_visual(false)
	_refresh_hub_mouths()
	_apply_water_visual()
	if _runtime_ready:
		_apply_bridge_blockers()

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

func _start_crawl(ia: Area3D, waypoints: Array) -> void:
	var id := str(ia.active_character)
	if id == "":
		id = str(_get_active_character())
	if id == "" or _crawling.get(id, false):
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null or not gs.characters.has(id):
		return
	_crawling[id] = true
	var prior := 2.6
	var cd: Variant = gs.characters.get(id)
	if cd is Dictionary and (cd as Dictionary).has("move_speed"):
		prior = float((cd as Dictionary)["move_speed"])
	gs.command_stop(id)
	gs.set_character_concealment(id, gs.CONCEAL_FULL)   # concealed while inside the tube
	gs.change_move_speed(id, CRAWL_SPEED)
	# an AUTHORED timed path — the pipe interior deliberately ignores the grid (the wall cells stay
	# blocked; the crawl is the only way through). Tick-interpolated, so it fast-forwards and replays
	# like every other move; the trigger re-derives it on replay.
	var path: Array[Vector3] = [gs.get_position(id) as Vector3]
	var total := 0.0
	for wp in waypoints:
		total += path[path.size() - 1].distance_to(wp as Vector3)
		path.append(wp as Vector3)
	gs._start_movement(id, path)
	sched.schedule_after(total / CRAWL_SPEED + 0.1, func() -> void: _end_crawl(id, prior), "crawl_%s" % id)

func _end_crawl(id: String, prior_speed: float) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.change_move_speed(id, prior_speed)
	gs.set_character_concealment(id, gs.CONCEAL_NONE)
	_crawling.erase(id)

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
		"complete": complete,
	}
