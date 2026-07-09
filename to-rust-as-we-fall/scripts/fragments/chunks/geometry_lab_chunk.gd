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
var _max_down_shift := 2.0   # algo 2: max extra DOWNWARD shift (grid units) of a recursed awning's A/B
var _merge_seed := 1         # algo 2: seed for the adjacent-awning merge dice
var _junction_lines := 3     # algo 3: how many centrelines meet at the junction (any number)
var _junction_seed := 1      # algo 3: varies the line ANGLES (and arm lengths); N-key rerolls it
var _junction_profile := "round"   # algo 3: "flat" beam or "round" (half-round tube) cross-section

# algo 2 [PARAMETER_CURVE]s as real Godot Curve resources (editable in the inspector / assignable in the
# .tscn). Sampled over recursion-depth t in [0,1]. Null -> a true-linear default (see _linear_curve).
@export var shift_curve: Curve   # distributes the downward shift across recursion depth
@export var merge_curve: Curve   # likelihood of merging adjacent awnings vs recursion depth

func configure_chunk(config: Dictionary) -> void:
	if config.has("angle"):
		_angle_deg = float(config["angle"])
	if config.has("algorithm"):
		_algorithm = int(config["algorithm"])
	if config.has("max_down_shift"):
		_max_down_shift = float(config["max_down_shift"])
	if config.has("merge_seed"):
		_merge_seed = int(config["merge_seed"])
	if config.has("junction_lines"):
		_junction_lines = maxi(2, int(config["junction_lines"]))
	if config.has("junction_seed"):
		_junction_seed = int(config["junction_seed"])
	elif config.has("seed"):
		_junction_seed = int(config["seed"])
	if config.has("profile"):
		_junction_profile = str(config["profile"])

# N-key in the preview reseeds the generation -> reroll algorithm 3's line angles.
func get_generation_seed() -> int:
	return _junction_seed

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
	if _algorithm == 4:
		# ALGORITHM 4: railings — a balcony slab extrudes out; the railing is drawn as flat CARDS
		# (planes) pulled back from the edge, textured with a pixel-art railing (alpha transparency).
		_build_railings(_turntable)
	elif _algorithm == 3:
		# ALGORITHM 3: clean-merge two crossing EXTRUDED paths — intersect the centerlines, find the
		# corner points where the arm edges cross, fill the junction, seam back into the arms.
		_build_junction(_turntable)
	elif _algorithm == 2:
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
	glm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

# --- ALGORITHM 2: an awning on all four sides, each recursing off its EFHG skirt, with a floored
# --- curve-distributed DOWNWARD SHIFT per level and a curve-driven MERGE of adjacent-face awnings. ---
func _build_recursive(root: Node3D, size: Vector3) -> void:
	var proj := STEP / tan(deg_to_rad(clampf(_angle_deg, 5.0, 85.0)))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var yt := size.y
	# 4 top corners in rotational order; face fi spans corner[fi]->corner[fi+1], outward normal[fi].
	# So B of face fi == A of face fi+1 (they share the corner) — the merge seam.
	var corners := [Vector3(hx, yt, hz), Vector3(-hx, yt, hz), Vector3(-hx, yt, -hz), Vector3(hx, yt, -hz)]
	var normals := [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
	var sc: Curve = shift_curve if shift_curve != null else _linear_curve()
	var mc: Curve = merge_curve if merge_curve != null else _linear_curve()   # rises with depth by default

	# 1) precompute each face's awning levels, applying the floored downward shift to each next A/B.
	var per_face: Array = []
	for fi in range(4):
		var levels: Array = []
		var a: Vector3 = corners[fi]
		var b: Vector3 = corners[(fi + 1) % 4]
		var n: Vector3 = normals[fi]
		var d := 0
		while d <= RECURSE_DEPTH:
			var pts := _awning_points(a, b, n, proj)
			levels.append(pts)
			var t := float(d + 1) / float(RECURSE_DEPTH)
			var shift := floorf(_max_down_shift * sc.sample(clampf(t, 0.0, 1.0)))
			a = (pts["E"] as Vector3) - Vector3(0.0, shift, 0.0)
			b = (pts["F"] as Vector3) - Vector3(0.0, shift, 0.0)
			if a.y - STEP <= 0.01:
				break
			d += 1
		per_face.append(levels)

	# 2) roll the merge dice per adjacent corner per shared level (deterministic).
	var rng := SeededRng.new(_merge_seed)
	var merged: Array = []   # merged[fi][d] = face fi's RIGHT corner merges face fi+1's LEFT at level d
	for fi in range(4):
		var arr: Array = []
		var la: Array = per_face[fi]
		var lb: Array = per_face[(fi + 1) % 4]
		var shared := mini(la.size(), lb.size())
		for d in range((per_face[fi] as Array).size()):
			var do_merge := false
			if d < shared:
				var t := float(d) / float(RECURSE_DEPTH)
				do_merge = float(rng.call("randf")) < mc.sample(clampf(t, 0.0, 1.0))
			arr.append(do_merge)
		merged.append(arr)

	# 3) draw awnings (omitting a corner's gable+wall where it merges) + the merge bridges.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for fi in range(4):
		var levels: Array = per_face[fi]
		var right_merge: Array = merged[fi]              # this face's RIGHT corner
		var left_merge: Array = merged[(fi + 3) % 4]     # previous face's right == this face's LEFT
		for d in range(levels.size()):
			var skip_left := d < left_merge.size() and bool(left_merge[d])
			var skip_right := d < right_merge.size() and bool(right_merge[d])
			_draw_awning_faces(st, levels[d], skip_left, skip_right)
	for fi in range(4):
		var la: Array = per_face[fi]
		var lb: Array = per_face[(fi + 1) % 4]
		var rm: Array = merged[fi]
		for d in range(rm.size()):
			if bool(rm[d]) and d < la.size() and d < lb.size():
				_draw_merge_bridge(st, la[d], lb[d])
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

# The 10 awning points off a top edge A-B (outward normal n): C/D one step below, E/F out by proj at
# C/D's height, G/H those dropped to the base, I/J the base below A/B.
func _awning_points(a: Vector3, b: Vector3, n: Vector3, proj: float) -> Dictionary:
	var c := a - Vector3(0.0, STEP, 0.0)
	var d := b - Vector3(0.0, STEP, 0.0)
	var e := c + n * proj
	var f := d + n * proj
	return {
		"A": a, "B": b, "C": c, "D": d, "E": e, "F": f,
		"G": Vector3(e.x, 0.0, e.z), "H": Vector3(f.x, 0.0, f.z),
		"I": Vector3(a.x, 0.0, a.z), "J": Vector3(b.x, 0.0, b.z),
	}

# Roof ABFE + skirt EFHG always; the left gable/wall (AEC, CEGI) and right gable/wall (BFD, DFHJ) are
# omitted where that corner merges into a bridge.
func _draw_awning_faces(st: SurfaceTool, pts: Dictionary, skip_left: bool, skip_right: bool) -> void:
	_quad(st, pts["A"], pts["B"], pts["F"], pts["E"])
	if not skip_left:
		_tri3(st, pts["A"], pts["E"], pts["C"])
		_quad(st, pts["C"], pts["E"], pts["G"], pts["I"])
	if not skip_right:
		_tri3(st, pts["B"], pts["F"], pts["D"])
		_quad(st, pts["D"], pts["F"], pts["H"], pts["J"])
	_quad(st, pts["E"], pts["F"], pts["H"], pts["G"])

# Bridge the corner gap between face fi's right side (pa) and face fi+1's left side (pb): the top
# triangle B1-E2-F1 and the vertical fill F1-E2-G2-H1 (their gable/wall edges were removed above).
func _draw_merge_bridge(st: SurfaceTool, pa: Dictionary, pb: Dictionary) -> void:
	_tri3(st, pa["B"], pb["E"], pa["F"])
	_quad(st, pa["F"], pb["E"], pb["G"], pa["H"])

# A TRUE-linear Curve (y = t). NOTE: Curve.add_point() defaults to TANGENT_FREE, which cubic-interps to
# a SMOOTHSTEP, not a line — so the tangent mode must be TANGENT_LINEAR on both ends.
func _linear_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	c.add_point(Vector2(1.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c

# --- ALGORITHM 3: clean-merge crossing extruded paths (a beam profile: width 2*w, height h). --------
# Two crossing centerlines -> intersection P -> the arm EDGES (centreline +/- w) intersect at corner
# points around P -> fill the junction (central polygon + arm panels) + walls: one watertight surface.
func _build_junction(root: Node3D) -> void:
	var w := 0.42                       # ribbon half-width
	var h := 0.55                       # extrude height
	# ANY NUMBER of centrelines through the junction -> 2*N arm far-endpoints. Each line is a diameter
	# through the origin at an evenly-spread angle (a clean N-way star); P = their common intersection.
	var num := maxi(2, _junction_lines)
	var length := 3.0
	var rng := SeededRng.new(_junction_seed)
	var lines: Array = []
	for k in range(num):
		# even spread + a seeded jitter (< half the spacing, so lines stay distinct, angles VARIED),
		# and per-arm length variation. N-key rerolls the seed -> a fresh angle configuration.
		var ang := PI * (float(k) + (float(rng.call("randf")) - 0.5) * 0.8) / float(num)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var lp := length * (0.65 + 0.5 * float(rng.call("randf")))
		var ln := length * (0.65 + 0.5 * float(rng.call("randf")))
		lines.append([-dir * ln, dir * lp])
	var p := _line_intersect_xz(
		lines[0][0], (lines[0][1] as Vector3) - (lines[0][0] as Vector3),
		lines[1][0], (lines[1][1] as Vector3) - (lines[1][0] as Vector3))
	var ends: Array = []
	for ln in lines:
		ends.append(ln[1])
		ends.append(ln[0])

	# per-arm frame (dir + left perpendicular), sorted CCW by angle around P
	var arms: Array = []
	for e in ends:
		var d: Vector3 = ((e - p) * Vector3(1, 0, 1)).normalized()
		arms.append({"end": e, "dir": d, "perp": Vector3(-d.z, 0.0, d.x), "ang": atan2(d.z, d.x)})
	arms.sort_custom(func(x, y): return float(x["ang"]) < float(y["ang"]))
	var n := arms.size()

	# corner[i] = where arm i's LEFT edge meets arm (i+1)'s RIGHT edge (the outer junction corners)
	var corner: Array = []
	for i in range(n):
		var ai: Dictionary = arms[i]
		var aj: Dictionary = arms[(i + 1) % n]
		var pi: Vector3 = p + (ai["perp"] as Vector3) * w
		var pj: Vector3 = p - (aj["perp"] as Vector3) * w
		corner.append(_line_intersect_xz(pi, ai["dir"], pj, aj["dir"]))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the merged footprint as ONE CCW boundary loop: per arm [far-right, far-left, corner-to-next].
	var loop: Array = []
	for i in range(n):
		var ai: Dictionary = arms[i]
		var pr: Vector3 = ai["perp"]
		loop.append((ai["end"] as Vector3) - pr * w)   # far-right
		loop.append((ai["end"] as Vector3) + pr * w)   # far-left
		loop.append(corner[i] as Vector3)              # corner to the next arm
	if _junction_profile == "round":
		_loft_rounded(st, loop, w)   # HALF-ROUND tube: quarter-circle inset-and-raise to a ridge
	else:
		_loft_flat(st, loop, h)      # FLAT beam: bottom + top + vertical walls

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "MergedJunction"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.44, 0.28)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)

	# show the raw (non-extruded) centrelines + label P and the junction corners
	var yh := Vector3(0.0, h, 0.0)
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_LINES)
	for ln in lines:
		gl.add_vertex((ln[0] as Vector3) + yh)
		gl.add_vertex((ln[1] as Vector3) + yh)
	var glm := MeshInstance3D.new()
	glm.name = "Centrelines"
	glm.mesh = gl.commit()
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.3, 0.85, 1.0)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glm.material_override = lmat
	glm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # debug guides must not shadow the arms
	root.add_child(glm)
	_add_point(root, "P", p + yh)
	for i in range(n):
		_add_point(root, "C%d" % i, (corner[i] as Vector3) + yh)

# FLAT beam: the footprint boundary loop filled top + bottom (centroid fans) and walled up by h.
func _loft_flat(st: SurfaceTool, loop: Array, h: float) -> void:
	var yh := Vector3(0.0, h, 0.0)
	var cen := _centroid(loop)
	var m := loop.size()
	for i in range(m):
		var a: Vector3 = loop[i]
		var b: Vector3 = loop[(i + 1) % m]
		_tri3(st, cen + yh, a + yh, b + yh)   # top fan
		_tri3(st, cen, b, a)                  # bottom fan
		_wall(st, a, b, h)                    # vertical wall

# HALF-ROUND tube: loft the boundary loop through quarter-circle layers — each layer is the footprint
# INSET by radius*(1-cos a) and RAISED by radius*sin a, so the section rounds from the full width at
# the base to a thin ridge at the top (a half-round moulding over the merged footprint).
func _loft_rounded(st: SurfaceTool, loop: Array, radius: float) -> void:
	var m := loop.size()
	var cen := _centroid(loop)
	var layers := 5
	var rings: Array = []
	for k in range(layers + 1):
		var a := (float(k) / float(layers)) * PI * 0.5
		var delta := radius * (1.0 - cos(a)) * 0.94
		var y := radius * sin(a)
		var ring: Array = []
		for pt in _inset_polygon(loop, delta, cen):
			ring.append((pt as Vector3) + Vector3(0.0, y, 0.0))
		rings.append(ring)
	for k in range(layers):
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for i in range(m):
			var j := (i + 1) % m
			_quad(st, r0[i], r0[j], r1[j], r1[i])
	var top: Array = rings[layers]
	var tc := _centroid(top)
	var base: Array = rings[0]
	var bc := _centroid(base)
	for i in range(m):
		var j := (i + 1) % m
		_tri3(st, tc, top[i], top[j])       # top ridge cap
		_tri3(st, bc, base[j], base[i])     # base cap

# Inset a CCW polygon inward by `delta` (each edge shifted along its inward normal; new vertices are the
# intersections of adjacent inset edges). Inward is decided per edge toward the centroid.
func _inset_polygon(loop: Array, delta: float, centroid: Vector3) -> Array:
	var m := loop.size()
	var out: Array = []
	for i in range(m):
		var a: Vector3 = loop[(i - 1 + m) % m]
		var b: Vector3 = loop[i]
		var c: Vector3 = loop[(i + 1) % m]
		var nab := _inward_normal(a, b, centroid)
		var nbc := _inward_normal(b, c, centroid)
		out.append(_line_intersect_xz(a + nab * delta, b - a, b + nbc * delta, c - b))
	return out

func _inward_normal(a: Vector3, b: Vector3, centroid: Vector3) -> Vector3:
	var e := (b - a) * Vector3(1, 0, 1)
	var nrm := Vector3(-e.z, 0.0, e.x).normalized()
	if nrm.dot(centroid - (a + b) * 0.5) < 0.0:
		nrm = -nrm
	return nrm

# Intersection of two lines in the XZ plane (y ignored), each given point + direction. Parallel -> p1.
func _line_intersect_xz(p1: Vector3, d1: Vector3, p2: Vector3, d2: Vector3) -> Vector3:
	var denom := d1.x * d2.z - d1.z * d2.x
	if absf(denom) < 1.0e-6:
		return p1
	var t := ((p2.x - p1.x) * d2.z - (p2.z - p1.z) * d2.x) / denom
	return Vector3(p1.x + d1.x * t, 0.0, p1.z + d1.z * t)

func _centroid(pts: Array) -> Vector3:
	var s := Vector3.ZERO
	for pt in pts:
		s += pt as Vector3
	return s / float(maxi(1, pts.size()))

# A vertical wall quad from edge p0-p1 (at y=0) up to height h.
func _wall(st: SurfaceTool, p0: Vector3, p1: Vector3, h: float) -> void:
	var yh := Vector3(0.0, h, 0.0)
	_quad(st, p0, p1, p1 + yh, p0 + yh)

# --- ALGORITHM 4: railings via textured CARDS. -----------------------------------------------------
# A balcony slab extrudes out from a wall; the railing is drawn as flat quads ("cards") pulled back a
# little from the edge, textured with a pixel-art railing (posts + rails) using alpha transparency, so
# we get a detailed railing for ~6 verts + one texture instead of modelling every baluster.
func _build_railings(root: Node3D) -> void:
	var w := 3.2       # balcony width
	var d := 1.6       # how far the balcony extrudes out (+Z) from the wall
	var slab_t := 0.16 # balcony floor thickness
	var rail_h := 1.0  # railing height
	var pull := 0.16   # pull the railing cards back from the balcony edge
	var y0 := 1.9      # balcony floor height off the ground

	# reference wall the balcony hangs off (so the demo reads as a balcony on a building)
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var wm := BoxMesh.new()
	wm.size = Vector3(w + 1.4, 4.0, 0.3)
	wall.mesh = wm
	wall.position = Vector3(0.0, 2.0, -0.15)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.58, 0.61, 0.66)
	wmat.roughness = 0.9
	wall.material_override = wmat
	root.add_child(wall)

	# the balcony slab (opaque), extruding +Z
	var slab := MeshInstance3D.new()
	slab.name = "Balcony"
	var sm := BoxMesh.new()
	sm.size = Vector3(w, slab_t, d)
	slab.mesh = sm
	slab.position = Vector3(0.0, y0, d * 0.5)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.70, 0.68, 0.60)
	smat.roughness = 0.88
	slab.material_override = smat
	root.add_child(slab)

	# railing cards (pulled back from the edges), textured with the pixel-art railing + alpha
	var rmat := StandardMaterial3D.new()
	rmat.albedo_texture = _railing_texture()
	rmat.albedo_color = Color(0.88, 0.84, 0.72)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	rmat.alpha_scissor_threshold = 0.5
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED     # a card is one plane — show it from both sides
	rmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp pixel-art
	rmat.roughness = 0.85
	var yb := y0 + slab_t * 0.5   # railing base (top of the slab)
	var yt := yb + rail_h
	var zf := d - pull            # front edge, pulled back
	var xl := -w * 0.5 + pull
	var xr := w * 0.5 - pull
	var per := 0.4                # a railing tile every ~0.4 m
	_add_card(root, "RailFront", Vector3(xl, yb, zf), Vector3(xr, yb, zf), Vector3(xr, yt, zf), Vector3(xl, yt, zf), rmat, (xr - xl) / per)
	_add_card(root, "RailLeft", Vector3(xl, yb, 0.0), Vector3(xl, yb, zf), Vector3(xl, yt, zf), Vector3(xl, yt, 0.0), rmat, zf / per)
	_add_card(root, "RailRight", Vector3(xr, yb, zf), Vector3(xr, yb, 0.0), Vector3(xr, yt, 0.0), Vector3(xr, yt, zf), rmat, zf / per)

# One repeating railing tile as a small RGBA image: a post on the left + top & bottom rails, the rest
# transparent. Tiled across a card it reads as evenly-spaced balusters. FILTER_NEAREST keeps it crisp.
func _railing_texture() -> ImageTexture:
	var tw := 12
	var th := 24
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var bar := Color(0.90, 0.86, 0.72, 1.0)
	for x in range(tw):
		for y in range(0, 3):            # top rail
			img.set_pixel(x, y, bar)
		for y in range(th - 3, th):      # bottom rail
			img.set_pixel(x, y, bar)
	for x in range(1, 4):                # one post (left of the tile)
		for y in range(3, th - 3):
			img.set_pixel(x, y, bar)
	return ImageTexture.create_from_image(img)

func _add_card(root: Node3D, card_name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: Material, ur: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a=bottom-left b=bottom-right c=top-right d=top-left; v=0 at the top (rail), v=1 at the base
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(ur, 1.0)); st.add_vertex(b)
	st.set_uv(Vector2(ur, 0.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(ur, 0.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(d)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = card_name
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)

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
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
