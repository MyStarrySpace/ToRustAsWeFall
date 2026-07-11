extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## BOSS PIECES — the two mega-landmark boss encounters as a walkable look-dev gallery (GDD 11):
##   LOCA'S WATCHTOWER (Act 1/2 boundary) — the survey-built tower staged on a rock crag with the
##   switchback approach and the ACT I BELOW / ACT II AHEAD marker (boss plate: reference-images/
##   bosses/locas_watchtower.png). The mountain is the landmark; the tower is the punctuation.
##   THE PARANUCLEUS (Act 2/3 boundary) — the ophanim wheel aggregate over the engulfed NUTECH
##   facility (plate: reference-images/bosses/paranucleus.png). Every wheel TURNS in its own
##   plane, out of phase — cosmetic per-frame motion; the ring table guarantees no alignment
##   can make them touch. Hazy gray/purple light marks its region (the amyloid signature).
## N reseeds both pieces (seeded variants of the tower + a re-jittered wheel fan).

const Paranucleus := preload("res://scripts/generation/paranucleus_builder.gd")
const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")

const TOWER_X := -17.0
const PARA_X := 13.0
const CRAG_H := 3.4
const CRAG_R := 7.6

const PARA_ORBIT_RADIUS := 14.0   # approach distance where the flat-image register takes over
const PARA_ORBIT_EXIT := 16.5     # hysteresis: leave a little further out than you entered

var _seed := 0
var _wheels: Array = []   # [{node, spin}] — the ophanim pivots
var _para_center := Vector3.ZERO   # the shared wheel center (world) — the orbit pivot
var _orbit_on := false

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])

func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "Boss Pieces — Watchtower + Paranucleus"

func _build_chunk() -> void:
	fragment = _boss_fragment()
	super._build_chunk()
	_wheels.clear()
	_build_watchtower_staging()
	_build_paranucleus()

func _process(delta: float) -> void:
	for w in _wheels:
		var wd := w as Dictionary
		var nd := wd["node"] as Node3D
		if is_instance_valid(nd):
			nd.rotate_object_local(Vector3(0, 0, 1), float(wd["spin"]) * delta)
	_update_paranucleus_register()

## The Paranucleus camera REGISTER (director, 2026-07-11 — the Monument Valley aspect): inside the
## approach radius the level reads as a FLAT IMAGE — the camera flips to an orthographic ORBIT
## between four authored snap vantages (Q/E steps between them), zoom scales the picture, and
## panning is just looking closer at it (no parallax). Leaving restores the gameplay follow
## camera. Rendering-only: the flip reads the follow target's render position and mutates no game
## state — 1x and 10x play identically underneath it.
func _update_paranucleus_register() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("enter_ortho_orbit"):
		return
	var t: Node3D = cam.get("target")
	if t == null or not is_instance_valid(t):
		return
	var d := Vector2(t.global_position.x - PARA_X, t.global_position.z).length()
	if not _orbit_on and d < PARA_ORBIT_RADIUS:
		_orbit_on = true
		cam.call("enter_ortho_orbit", _para_center, [0.0, PI * 0.5, PI, PI * 1.5],
			{"dist": 40.0, "base_size": 24.0, "elev": 0.5})
	elif _orbit_on and d > PARA_ORBIT_EXIT:
		_orbit_on = false
		cam.call("exit_ortho_orbit")

## The crag + switchback approach + the act marker, with the survey-built tower on the summit.
func _build_watchtower_staging() -> void:
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the crag: a stepped lathe (radii as fractions of CRAG_H), boulders scattered at its foot
	var rows := [[0.0, CRAG_R / CRAG_H], [0.30, CRAG_R * 0.93 / CRAG_H], [0.58, CRAG_R * 0.82 / CRAG_H],
		[0.84, CRAG_R * 0.72 / CRAG_H], [1.0, CRAG_R * 0.68 / CRAG_H]]
	BaseShape._rings_loft(rock, Vector3.ZERO, CRAG_H, rows, 14)
	for b in range(6):
		var ba := TAU * (0.13 + float(b) / 6.0)
		var br := CRAG_R * (1.02 + 0.10 * BaseShape._h01(float(_seed * 31 + b) + 3.0))
		var bs := 0.5 + 0.7 * BaseShape._h01(float(_seed * 31 + b) + 9.0)
		BaseShape._emit_box_st(rock, Vector3(cos(ba) * br, bs * 0.45, sin(ba) * br), Vector3(bs, bs * 0.5, bs * 0.8))
	# the switchback approach: two flights + a turn landing on the crag's front face
	var f1_a := Vector3(-5.4, 0.10, CRAG_R * 0.94)
	var f1_b := Vector3(3.6, 1.75, CRAG_R * 0.82)
	var f2_a := Vector3(3.6, 1.75, CRAG_R * 0.70)
	var f2_b := Vector3(-2.6, CRAG_H, CRAG_R * 0.56)
	for fl in [[f1_a, f1_b], [f2_a, f2_b]]:
		var a := (fl as Array)[0] as Vector3
		var c := (fl as Array)[1] as Vector3
		var mid := (a + c) * 0.5
		var run := c - a
		var u := run.normalized()
		var n := Vector3(0, 0, 1)
		var v := u.cross(n).normalized() * -1.0
		BaseShape._emit_oriented_box_st(rock, mid, u, v, n, Vector3(run.length() * 0.5 + 0.3, 0.09, 0.55))
	BaseShape._emit_box_st(rock, Vector3(3.6, 1.66, CRAG_R * 0.76), Vector3(0.9, 0.09, 0.9))
	rock.generate_normals()
	var rock_root := Node3D.new()
	rock_root.name = "WatchtowerCrag"
	rock_root.position = Vector3(TOWER_X, 0, 0)
	add_child(rock_root)
	_add_lattice_mesh(rock_root, "Crag", rock.commit(),
		_tinted_tile_material("facility_metal", Color(0.24, 0.25, 0.28)))
	# blue trail posts up the flights (the plate's cold checkpoint lights)
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	for fl2 in [[f1_a, f1_b], [f2_a, f2_b]]:
		var a2 := (fl2 as Array)[0] as Vector3
		var c2 := (fl2 as Array)[1] as Vector3
		for t in range(4):
			var p := a2.lerp(c2, (float(t) + 0.5) / 4.0) + Vector3(0, 0.42, 0.62)
			BaseShape._emit_box_st(posts, p, Vector3(0.05, 0.42, 0.05))
			BaseShape._emit_box_st(posts, p + Vector3(0, 0.48, 0), Vector3(0.08, 0.08, 0.08))
	posts.generate_normals()
	var postm := StandardMaterial3D.new()
	postm.albedo_color = Color(0.10, 0.18, 0.26)
	postm.emission_enabled = true
	postm.emission = Color(0.45, 0.80, 1.0)
	postm.emission_energy_multiplier = 2.0
	_add_lattice_mesh(rock_root, "TrailPosts", posts.commit(), postm)
	# the act marker at the trail base (the plate's ACT I BELOW / ACT II AHEAD pylon)
	var marker := SurfaceTool.new()
	marker.begin(Mesh.PRIMITIVE_TRIANGLES)
	BaseShape._emit_box_st(marker, Vector3(0, 1.1, 0), Vector3(0.16, 1.1, 0.16))
	BaseShape._emit_box_st(marker, Vector3(0, 1.62, 0.02), Vector3(0.62, 0.30, 0.06))
	BaseShape._emit_box_st(marker, Vector3(0, 0.92, 0.02), Vector3(0.62, 0.30, 0.06))
	BaseShape._emit_box_st(marker, Vector3(0, 2.32, 0), Vector3(0.10, 0.24, 0.10))
	marker.generate_normals()
	var marker_root := Node3D.new()
	marker_root.name = "ActMarker"
	marker_root.position = Vector3(TOWER_X - 6.6, 0, CRAG_R + 1.6)
	add_child(marker_root)
	_add_lattice_mesh(marker_root, "MarkerBody", marker.commit(),
		_tinted_tile_material("facility_metal", Color(0.30, 0.33, 0.38)))
	_add_boss_label(marker_root, "ACT I BELOW", Vector3(0, 1.62, 0.14), Color(0.55, 0.80, 1.0), 30)
	_add_boss_label(marker_root, "ACT II AHEAD", Vector3(0, 0.92, 0.14), Color(0.55, 0.80, 1.0), 30)
	# the tower itself: the survey-built landmark on the summit
	_spawn_landmark_building({"kind": "locas_watchtower", "pos": Vector3(TOWER_X, CRAG_H, 0),
		"spec_seed": _seed})
	_add_boss_label(self, "LOCA'S WATCHTOWER — ACT 1 BOSS", Vector3(TOWER_X, CRAG_H + 15.6, 0),
		Color(0.62, 0.82, 1.0), 52)

## The ophanim aggregate: per-wheel pivots (basis from the ring table) so each wheel turns in its
## own plane; the pink-red core; the engulfed NUTECH fragments with their legible boards.
func _build_paranucleus() -> void:
	var spec: Dictionary = Paranucleus.generate(_seed)
	var problems: Array = Paranucleus.validate(spec)
	for p in problems:
		push_warning("BossShowcase: %s" % str(p))
	var built: Dictionary = Paranucleus.build(spec)
	var root := Node3D.new()
	root.name = "Paranucleus"
	root.position = Vector3(PARA_X, 0, 0)
	add_child(root)
	var bonem := StandardMaterial3D.new()
	bonem.albedo_color = Color(0.87, 0.84, 0.79)   # bone-white, catching the purple light
	bonem.roughness = 0.86
	var lavm := StandardMaterial3D.new()
	lavm.albedo_color = Color(0.70, 0.63, 0.80)    # the pale-lavender understrands
	lavm.roughness = 0.9
	var origin := built["origin"] as Vector3
	_para_center = root.position + origin   # the orbit pivot: the shared wheel center, world frame
	for r_v in (built["rings"] as Array):
		var rd := r_v as Dictionary
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % _wheels.size()
		pivot.position = origin
		pivot.basis = rd["basis"] as Basis
		root.add_child(pivot)
		_add_lattice_mesh(pivot, "Bone", rd["bone"], bonem)
		_add_lattice_mesh(pivot, "Lav", rd["lav"], lavm)
		_wheels.append({"node": pivot, "spin": float(rd["spin"])})
	var corem := StandardMaterial3D.new()
	corem.albedo_color = Color(0.42, 0.10, 0.16)
	corem.emission_enabled = true
	corem.emission = Color(1.0, 0.42, 0.50)   # the map's ONLY pink-red saturation (GDD 4.5)
	corem.emission_energy_multiplier = 3.0
	var core_holder := Node3D.new()
	core_holder.name = "CoreHolder"
	core_holder.position = origin
	root.add_child(core_holder)
	_add_lattice_mesh(core_holder, "Core", built["core"], corem)
	_add_lattice_mesh(root, "Nutech", built["nutech"],
		_tinted_tile_material("facility_metal", Color(0.46, 0.48, 0.50)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.10)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "NutechDark", built["dark"], dark)
	var signm := StandardMaterial3D.new()
	signm.albedo_color = Color(0.78, 0.80, 0.78)
	signm.emission_enabled = true
	signm.emission = Color(0.95, 0.97, 0.94)   # the gate board — still powered
	signm.emission_energy_multiplier = 1.2
	_add_lattice_mesh(root, "NutechSigns", built["signs"], signm)
	# the legible offices: REAL surveyed nutech_facility instances scaled into their envelopes
	for slot_v in (built["building_slots"] as Array):
		var slot := (slot_v as Dictionary).duplicate()
		slot["pos"] = root.position + (slot["pos"] as Vector3)
		_spawn_landmark_building(slot)
	for sp_v in (built["sign_positions"] as Array):
		var sp := sp_v as Dictionary
		_add_boss_label(root, "NUTECH", (sp["pos"] as Vector3), Color(0.16, 0.18, 0.20), 34)
	_add_boss_label(self, "THE PARANUCLEUS — ACT 2 BOSS",
		Vector3(PARA_X, (built["origin"] as Vector3).y * 2.1, 0), Color(0.82, 0.72, 0.92), 52)

## A sized label riding the shared _add_label (the base already owns the Label3D idiom).
func _add_boss_label(parent: Node3D, text: String, pos: Vector3, col: Color, size: int) -> void:
	var lbl := _add_label(parent, text, pos, col)
	lbl.font_size = size
	lbl.pixel_size = 0.006
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["seed"] = _seed
	st["wheels"] = _wheels.size()
	return st

func _boss_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "boss_showcase_%d" % _seed
	frag.title = "Boss Pieces — Watchtower + Paranucleus"
	frag.help = "The two mega-landmark boss encounters. Walk the ground; compare to the boss plates."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var w := 38
	var h := 20
	frag.floors = [{
		"pos": Vector3(-2.0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.11, 0.10, 0.13), "tile": "deck_metal",
	}]
	var origin_x := -2.0 - w * cs * 0.5
	var origin_z := -h * cs * 0.5
	var blocked := {}
	for z in range(h):
		for x in range(w):
			var wx := origin_x + (float(x) + 0.5) * cs
			var wz := origin_z + (float(z) + 0.5) * cs
			# the crag disc + the paranucleus facility apron are staging, not floor
			if Vector2(wx - TOWER_X, wz).length() < CRAG_R + 1.2:
				blocked[Vector2i(x, z)] = true
			if absf(wx - PARA_X) < 7.2 and absf(wz) < 5.4:
				blocked[Vector2i(x, z)] = true
	var cells: Array = []
	for z2 in range(h):
		for x2 in range(w):
			if not blocked.has(Vector2i(x2, z2)):
				cells.append([x2, z2])
	frag.grid = {
		"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [origin_x, 0.0, origin_z], "width": w, "height": h,
		"walkable_cells": cells,
	}
	frag.spawns = {
		"aster": Vector3(-3.5, 0.5, 11.5), "peris": Vector3(-2.0, 0.5, 12.4), "endo": Vector3(-5.0, 0.5, 12.4),
	}
	frag.shelters = [{"min": Vector2(-6.5, 10.4), "max": Vector2(-0.5, 13.4)}]
	frag.lights = [
		# the watchtower region: the cold institutional blue against the dark
		{"pos": Vector3(TOWER_X - 6.0, 16.0, 10.0), "color": Color(0.62, 0.74, 0.92), "energy": 3.6, "range": 34.0},
		{"pos": Vector3(TOWER_X + 6.0, 5.0, 8.0), "color": Color(0.45, 0.58, 0.80), "energy": 1.8, "range": 20.0},
		# the paranucleus region: the hazy gray/purple amyloid signature (GDD 4.5)
		{"pos": Vector3(PARA_X - 5.0, 15.0, 9.0), "color": Color(0.72, 0.64, 0.82), "energy": 3.4, "range": 36.0},
		{"pos": Vector3(PARA_X + 6.0, 6.0, -7.0), "color": Color(0.55, 0.46, 0.66), "energy": 2.0, "range": 24.0},
		# the core's own pink-red spill
		{"pos": Vector3(PARA_X, 8.4, 0.0), "color": Color(1.0, 0.45, 0.52), "energy": 1.6, "range": 10.0},
	]
	frag.labels = []
	frag.params = {"stamina_field_regen": true, "showcase_seed": _seed}
	frag.time_state = {"note_default": "The two boss mega-landmarks.", "routing_mode": "safe"}
	return frag
