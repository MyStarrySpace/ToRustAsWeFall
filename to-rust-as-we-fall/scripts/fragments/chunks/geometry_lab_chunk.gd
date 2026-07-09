extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## GEOMETRY LAB — a workbench for MINIMAL geometry-construction algorithms, one at a time, with the
## construction's LABELED points shown so each step can be checked against the spec. Deterministic
## (nothing to reseed); parameters come from the preview config (e.g. the awning ANGLE).
##
## Algorithm 1 — AWNING / HOOD from a face rectangle:
##   1. A rectangular prism 3w x 3l x 4h, subdivided every 1 m.
##   2. On one face (the front, +Z) take a rectangle of points, all coplanar.
##   3. A = top-left, B = top-right; I = bottom-left, J = bottom-right.
##   4. C = the point below A, D = the point below B (one 1 m row down).
##   5. L_C, L_D = rays from C, D pointing AWAY from the building (+Z), at C/D's height.
##   6. L_A, L_B = rays from A, B at ANGLE (default 45 deg) below horizontal until they meet
##      L_C, L_D at E, F.
##   7. Faces ABFE (sloped roof) + AEC, BFD (gable sides).
##   8. Drop E, F straight down to the base -> G, H. Faces CEGI, DFHJ (side walls) + EFHG (front skirt).

const BOX := Vector3(3.0, 4.0, 3.0)    # algorithm 1 prism: w(x) x h(y) x l(z)
const BOX2 := Vector3(4.0, 6.0, 4.0)   # algorithm 2 (recursive) prism — larger, all sides
const STEP := 1.0
const RECURSE_DEPTH := 3               # algorithm 2: how many nested awning levels

var _turntable: Node3D
var _angle_deg := 45.0
var _algorithm := 1

func configure_chunk(config: Dictionary) -> void:
	if config.has("angle"):
		_angle_deg = float(config["angle"])
	if config.has("algorithm"):
		_algorithm = int(config["algorithm"])

func is_generation_preview() -> bool:
	return true

func get_scene_title() -> String:
	return "Geometry Lab — awning construction (algo %d)" % _algorithm

func _build_chunk() -> void:
	fragment = _lab_fragment()
	super._build_chunk()
	_turntable = Node3D.new()
	_turntable.name = "Construction"
	add_child(_turntable)
	if _algorithm == 2:
		# ALGORITHM 2: a larger prism; an awning on ALL FOUR sides, then recurse each side by drawing a
		# fresh awning off its EFHG skirt (out + down) -> a blocky, stepped, flared mass.
		_build_prism(_turntable, BOX2, false)
		_build_recursive(_turntable, BOX2)
	else:
		# ALGORITHM 1: one awning on the front face, with the labeled construction points.
		_build_prism(_turntable, BOX, true)
		_build_awning(_turntable)

func _process(delta: float) -> void:
	if is_instance_valid(_turntable):
		_turntable.rotate_y(delta * 0.2)

# --- Step 1-2: the subdivided prism + (optional) the 1 m grid on the working (+Z) face. ------------
func _build_prism(root: Node3D, size: Vector3, with_grid: bool) -> void:
	var box := MeshInstance3D.new()
	box.name = "Box"
	var bm := BoxMesh.new()
	bm.size = size
	box.mesh = bm
	box.position = Vector3(0, size.y * 0.5, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.60, 0.63, 0.68)
	bmat.roughness = 0.9
	box.material_override = bmat
	root.add_child(box)

	if not with_grid:
		return
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_LINES)
	var zf := size.z * 0.5 + 0.01
	var xl := -size.x * 0.5
	var xr := size.x * 0.5
	var x := xl
	while x <= xr + 0.001:
		gl.add_vertex(Vector3(x, 0.0, zf)); gl.add_vertex(Vector3(x, size.y, zf))
		x += STEP
	var y := 0.0
	while y <= size.y + 0.001:
		gl.add_vertex(Vector3(xl, y, zf)); gl.add_vertex(Vector3(xr, y, zf))
		y += STEP
	var glm := MeshInstance3D.new()
	glm.name = "FaceGrid"
	glm.mesh = gl.commit()
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.16, 0.18, 0.22)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glm.material_override = lmat
	root.add_child(glm)

# --- Steps 3-8: the awning construction, its faces, and the labeled points. ------------------------
func _build_awning(root: Node3D) -> void:
	var zf := BOX.z * 0.5                     # the front face plane
	var y_t := 3.0                            # top row of the selected rectangle (a grid line)
	var xl := -BOX.x * 0.5
	var xr := BOX.x * 0.5
	var theta := deg_to_rad(clampf(_angle_deg, 5.0, 85.0))
	var proj := STEP / tan(theta)             # how far E/F sit in front (drop STEP at ANGLE)

	var A := Vector3(xl, y_t, zf)
	var B := Vector3(xr, y_t, zf)
	var C := Vector3(xl, y_t - STEP, zf)      # below A
	var D := Vector3(xr, y_t - STEP, zf)      # below B
	var I := Vector3(xl, 0.0, zf)             # base-left
	var J := Vector3(xr, 0.0, zf)             # base-right
	var E := Vector3(xl, y_t - STEP, zf + proj)   # A-ray meets L_C
	var F := Vector3(xr, y_t - STEP, zf + proj)   # B-ray meets L_D
	var G := Vector3(xl, 0.0, zf + proj)          # E dropped to the base
	var H := Vector3(xr, 0.0, zf + proj)          # F dropped to the base

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, A, B, F, E)     # sloped roof
	_tri3(st, A, E, C)        # left gable
	_tri3(st, B, F, D)        # right gable
	_quad(st, C, E, G, I)     # left wall
	_quad(st, D, F, H, J)     # right wall
	_quad(st, E, F, H, G)     # front skirt
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Awning"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.44, 0.28)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # workbench: show both sides regardless of winding
	mi.material_override = mat
	root.add_child(mi)

	for pair in [["A", A], ["B", B], ["C", C], ["D", D], ["E", E], ["F", F], ["G", G], ["H", H], ["I", I], ["J", J]]:
		_add_point(root, str(pair[0]), pair[1] as Vector3)

# --- ALGORITHM 2: an awning on all four sides, each recursing off its EFHG skirt. -----------------
func _build_recursive(root: Node3D, size: Vector3) -> void:
	var proj := STEP / tan(deg_to_rad(clampf(_angle_deg, 5.0, 85.0)))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var yt := size.y
	# each side: [A (top-left), B (top-right), outward normal]
	var faces := [
		[Vector3(-hx, yt, hz), Vector3(hx, yt, hz), Vector3(0, 0, 1)],
		[Vector3(hx, yt, -hz), Vector3(-hx, yt, -hz), Vector3(0, 0, -1)],
		[Vector3(hx, yt, hz), Vector3(hx, yt, -hz), Vector3(1, 0, 0)],
		[Vector3(-hx, yt, -hz), Vector3(-hx, yt, hz), Vector3(-1, 0, 0)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		_awning_rec(st, f[0] as Vector3, f[1] as Vector3, f[2] as Vector3, proj, RECURSE_DEPTH)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "RecursiveAwnings"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.44, 0.28)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)

# One awning off a top edge A-B (outward normal n): roof ABFE, gables AEC/BFD, walls CEGI/DFHJ, and the
# skirt EFHG down to the base. Then recurse off the skirt's top edge E-F (stepping out + down).
func _awning_rec(st: SurfaceTool, a: Vector3, b: Vector3, n: Vector3, proj: float, depth: int) -> void:
	var c := a - Vector3(0.0, STEP, 0.0)
	var d := b - Vector3(0.0, STEP, 0.0)
	var i := Vector3(a.x, 0.0, a.z)
	var j := Vector3(b.x, 0.0, b.z)
	var e := c + n * proj
	var f := d + n * proj
	var g := Vector3(e.x, 0.0, e.z)
	var h := Vector3(f.x, 0.0, f.z)
	_quad(st, a, b, f, e)   # sloped roof
	_tri3(st, a, e, c)      # left gable
	_tri3(st, b, f, d)      # right gable
	_quad(st, c, e, g, i)   # left wall
	_quad(st, d, f, h, j)   # right wall
	_quad(st, e, f, h, g)   # front skirt
	if depth > 0 and (e.y - STEP) > 0.01:
		_awning_rec(st, e, f, n, proj, depth - 1)

func _add_point(root: Node3D, letter: String, pos: Vector3) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	s.mesh = sm
	s.position = pos
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.86, 0.2)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material_override = smat
	root.add_child(s)
	var lbl := Label3D.new()
	lbl.text = letter
	lbl.font_size = 48
	lbl.pixel_size = 0.006
	lbl.modulate = Color(1.0, 0.96, 0.55)
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos + Vector3(0.0, 0.2, 0.05)
	root.add_child(lbl)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

func _tri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

func _lab_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "geometry_lab_%d" % _algorithm
	frag.title = "Geometry Lab"
	frag.help = "Minimal geometry-construction algorithms with labeled points. Walk around the turntable."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster"])
	var cs := 1.5
	var w := 12
	var h := 12
	frag.floors = [{
		"pos": Vector3(0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.10, 0.11, 0.13), "tile": "deck_metal",
	}]
	var ox := -w * cs * 0.5
	var oz := -h * cs * 0.5
	var cells: Array = []
	for z in range(h):
		for x in range(w):
			cells.append([x, z])
	frag.grid = {
		"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [ox, 0.0, oz], "width": w, "height": h, "walkable_cells": cells,
	}
	frag.spawns = {"aster": Vector3(0.0, 0.5, 5.5)}
	frag.lights = [
		{"pos": Vector3(-3.0, 8.0, 6.0), "color": Color(0.9, 0.9, 0.95), "energy": 4.0, "range": 30.0},
		{"pos": Vector3(4.0, 4.0, 5.0), "color": Color(0.68, 0.72, 0.82), "energy": 2.4, "range": 20.0},
	]
	frag.params = {"stamina_field_regen": true}
	frag.time_state = {"note_default": "Geometry lab — awning construction.", "routing_mode": "safe"}
	return frag
