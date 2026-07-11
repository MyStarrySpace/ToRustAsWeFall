extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## THE AGHORA — a bazaar CANYON vignette (GDD's counterfeit agora; plates reference-images/
## architecture/aghora/): two rows of seed-varied bazaar STACKS flanking a market lane, the
## EXCHANGE dome at its head, banner lines strung across the canyon, canvas market stalls and warm
## lantern light below, the magenta neon marking the district. Walk the lane; N reseeds the stacks.

const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")

const LANE_HEAD_Z := -13.0
const ROW_X := 6.4

var _seed := 0

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])

func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "The Aghora — bazaar canyon"

func _build_chunk() -> void:
	fragment = _bazaar_fragment()
	super._build_chunk()
	# the Exchange holds the lane's head; the stacks wall the canyon, every one a seeded variant
	_spawn_landmark_building({"kind": "aghora_exchange", "pos": Vector3(0, 0, LANE_HEAD_Z),
		"yaw": 0.0, "spec_seed": _seed})
	var slots := [
		{"x": -ROW_X, "z": -5.5, "yaw": PI * 0.5}, {"x": -ROW_X, "z": 0.5, "yaw": PI * 0.5},
		{"x": -ROW_X, "z": 6.5, "yaw": PI * 0.5},
		{"x": ROW_X, "z": -2.5, "yaw": -PI * 0.5}, {"x": ROW_X, "z": 3.5, "yaw": -PI * 0.5},
	]
	for i in range(slots.size()):
		var s := slots[i] as Dictionary
		_spawn_landmark_building({"kind": "aghora_stack",
			"pos": Vector3(float(s["x"]), 0, float(s["z"])),
			"yaw": float(s["yaw"]), "spec_seed": _seed * 7 + i + 1})
	_build_banner_lines()
	_build_stalls()

## Banner lines sagging across the canyon between the opposing rows, hung with market flags.
func _build_banner_lines() -> void:
	var kb := float(_seed * 53 % 1000)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flags := SurfaceTool.new()
	flags.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flag_cols := [Color(0.62, 0.20, 0.55), Color(0.24, 0.44, 0.42), Color(0.52, 0.30, 0.20),
		Color(0.66, 0.56, 0.30)]
	for li in range(3):
		var lz := -6.0 + 5.4 * float(li)
		var lh := 6.4 + 1.3 * BaseShape._h01(kb + 5.0 + float(li) * 7.7)
		var a := Vector3(-ROW_X + 2.2, lh, lz)
		var b := Vector3(ROW_X - 2.2, lh + 0.4 * (BaseShape._h01(kb + 11.0 + float(li)) - 0.5), lz)
		var pts: Array = []
		for t in range(9):
			var tt := float(t) / 8.0
			var sag := sin(tt * PI) * 0.85
			pts.append(a.lerp(b, tt) + Vector3(0, -sag, 0))
		BaseShape._tube(lines, pts, 0.022, 4)
		for f in range(6):
			var ft := (float(f) + 0.75) / 7.0
			var fp := a.lerp(b, ft) + Vector3(0, -sin(ft * PI) * 0.85, 0)
			var col := flag_cols[(li + f) % flag_cols.size()] as Color
			flags.set_color(col)
			BaseShape._emit_oriented_box_st(flags, fp + Vector3(0, -0.30, 0),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.24, 0.28, 0.012))
	lines.generate_normals()
	flags.generate_normals()
	var linem := StandardMaterial3D.new()
	linem.albedo_color = Color(0.10, 0.10, 0.11)
	_add_lattice_mesh(self, "BannerLines", lines.commit(), linem)
	var flagm := StandardMaterial3D.new()
	flagm.vertex_color_use_as_albedo = true
	flagm.roughness = 1.0
	flagm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_lattice_mesh(self, "BannerFlags", flags.commit(), flagm)

## Canvas market stalls hugging the lane edges: posts, a tilted canvas roof, a counter.
func _build_stalls() -> void:
	var kb := float(_seed * 29 % 1000)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canvas := SurfaceTool.new()
	canvas.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canvas_cols := [Color(0.55, 0.34, 0.30), Color(0.34, 0.44, 0.40), Color(0.58, 0.48, 0.30)]
	var stalls := [
		{"x": -2.9, "z": -7.5, "f": 1.0}, {"x": 2.9, "z": -4.0, "f": -1.0},
		{"x": -2.9, "z": 1.0, "f": 1.0}, {"x": 2.9, "z": 5.5, "f": -1.0},
	]
	for si in range(stalls.size()):
		var s := stalls[si] as Dictionary
		var base := Vector3(float(s["x"]), 0, float(s["z"]))
		var fdir := float(s["f"])   # which way the stall opens (toward the lane)
		for px in [-1.0, 1.0]:
			for pz in [-1.0, 1.0]:
				var ph := 1.9 if pz > 0 else 1.6
				BaseShape._emit_box_st(wood, base + Vector3(px * 1.0 * fdir, ph * 0.5, pz * 0.8),
					Vector3(0.05, ph * 0.5, 0.05))
		BaseShape._emit_box_st(wood, base + Vector3(0, 0.55, -0.35 * fdir), Vector3(0.95, 0.06, 0.42))
		BaseShape._emit_box_st(wood, base + Vector3(0, 0.245, -0.35 * fdir), Vector3(0.80, 0.245, 0.34))
		# the tilted canvas sheet, pitched down toward the lane
		var roof_c := base + Vector3(0, 1.78, 0)
		var v := Vector3(0, 1, 0.34 * fdir).normalized()
		var n := Vector3(0, 0.34, -1.0 * fdir).normalized()
		canvas.set_color(canvas_cols[si % canvas_cols.size()] as Color)
		BaseShape._emit_oriented_box_st(canvas, roof_c, Vector3(1, 0, 0), v, n, Vector3(1.18, 0.014, 1.0))
		# a little clutter on the counter
		for c in range(3):
			var cx := (BaseShape._h01(kb + float(si) * 17.0 + float(c) * 3.3) - 0.5) * 1.3
			var chh := 0.10 + 0.14 * BaseShape._h01(kb + float(si) * 23.0 + float(c) * 5.1)
			BaseShape._emit_box_st(wood, base + Vector3(cx, 0.55 + chh, -0.35 * fdir),
				Vector3(0.09, chh, 0.09))
	wood.generate_normals()
	canvas.generate_normals()
	var woodm := StandardMaterial3D.new()
	woodm.albedo_color = Color(0.26, 0.19, 0.14)
	woodm.roughness = 0.95
	_add_lattice_mesh(self, "StallWood", wood.commit(), woodm)
	var canvasm := StandardMaterial3D.new()
	canvasm.vertex_color_use_as_albedo = true
	canvasm.roughness = 1.0
	canvasm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_lattice_mesh(self, "StallCanvas", canvas.commit(), canvasm)

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["seed"] = _seed
	return st

func _bazaar_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "aghora_bazaar_%d" % _seed
	frag.title = "The Aghora — bazaar canyon"
	frag.help = "The counterfeit agora's market canyon: stacks, stalls, banner lines, the Exchange at the head."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var w := 16
	var h := 20
	frag.floors = [{
		"pos": Vector3(0, -0.05, -1.0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.12, 0.10, 0.11), "tile": "deck_metal",
	}]
	var origin_x := -w * cs * 0.5
	var origin_z := -1.0 - h * cs * 0.5
	var blocked := {}
	for z in range(h):
		for x in range(w):
			var wx := origin_x + (float(x) + 0.5) * cs
			var wz := origin_z + (float(z) + 0.5) * cs
			# the exchange drum + the stack rows wall the canyon; stalls hug the lane edges
			if Vector2(wx, wz - LANE_HEAD_Z).length() < 3.6:
				blocked[Vector2i(x, z)] = true
			if absf(wx) > 3.9:
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
		"aster": Vector3(0.0, 0.5, 7.0), "peris": Vector3(-1.5, 0.5, 7.8), "endo": Vector3(1.5, 0.5, 7.8),
	}
	frag.shelters = [{"min": Vector2(-3.2, 5.6), "max": Vector2(3.2, 8.6)}]
	# night-market light: warm lanterns down the lane, the district's magenta at the head
	var lights: Array[Dictionary] = [
		{"pos": Vector3(0, 7.0, LANE_HEAD_Z + 4.5), "color": Color(0.92, 0.38, 0.80), "energy": 2.6, "range": 16.0},
		{"pos": Vector3(0, 12.0, 2.0), "color": Color(0.66, 0.58, 0.66), "energy": 2.2, "range": 30.0},
	]
	for li in range(4):
		lights.append({"pos": Vector3(-2.2 + 4.4 * float(li % 2), 2.6, -8.0 + 4.6 * float(li)),
			"color": Color(0.98, 0.72, 0.36), "energy": 1.7, "range": 8.0})
	frag.lights = lights
	frag.labels = []
	frag.params = {"stamina_field_regen": true, "showcase_seed": _seed}
	frag.time_state = {"note_default": "The Aghora's night market.", "routing_mode": "safe"}
	return frag
