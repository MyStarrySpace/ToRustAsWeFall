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

const BOX := Vector3(3.0, 4.0, 3.0)   # w(x) x h(y) x l(z)
const STEP := 1.0

var _turntable: Node3D
var _angle_deg := 45.0

func configure_chunk(config: Dictionary) -> void:
	if config.has("angle"):
		_angle_deg = float(config["angle"])

func is_generation_preview() -> bool:
	return true

func get_scene_title() -> String:
	return "Geometry Lab — awning construction"

func _build_chunk() -> void:
	fragment = _lab_fragment()
	super._build_chunk()
	_turntable = Node3D.new()
	_turntable.name = "Construction"
	add_child(_turntable)
	_build_subdivided_box(_turntable)
	_build_awning(_turntable)

func _process(delta: float) -> void:
	if is_instance_valid(_turntable):
		_turntable.rotate_y(delta * 0.2)

# --- Step 1-2: the subdivided prism + the 1 m grid on the working (+Z) face. -----------------------
func _build_subdivided_box(root: Node3D) -> void:
	var box := MeshInstance3D.new()
	box.name = "Box"
	var bm := BoxMesh.new()
	bm.size = BOX
	box.mesh = bm
	box.position = Vector3(0, BOX.y * 0.5, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.60, 0.63, 0.68)
	bmat.roughness = 0.9
	box.material_override = bmat
	root.add_child(box)

	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_LINES)
	var zf := BOX.z * 0.5 + 0.01
	var xl := -BOX.x * 0.5
	var xr := BOX.x * 0.5
	var x := xl
	while x <= xr + 0.001:
		gl.add_vertex(Vector3(x, 0.0, zf)); gl.add_vertex(Vector3(x, BOX.y, zf))
		x += STEP
	var y := 0.0
	while y <= BOX.y + 0.001:
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
	frag.id = "geometry_lab"
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
