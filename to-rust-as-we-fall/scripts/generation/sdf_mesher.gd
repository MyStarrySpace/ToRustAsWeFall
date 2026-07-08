class_name SdfMesher
extends RefCounted

## Meshes a list of SDF primitives into an ArrayMesh. The creature pipeline's second half: a body
## grammar emits primitives (capsules with per-end radii, ellipsoids, spheres), each carrying a
## smooth-min blend radius `k`; this SPLATS them into a scalar field and polygonises it.
##
## Built for GDScript speed and robustness:
## - SPLATTING, not per-voxel scans: each primitive only evaluates inside its own influence box
##   (AABB + blend margin), smooth-min'd into the field in a fixed order — total work is the sum of
##   primitive box volumes, not grid x primitives. Deterministic (no threads, fixed order).
## - MARCHING TETRAHEDRA, not marching cubes: each surface cell splits into 6 tets sharing the main
##   diagonal, and every tet case (1 or 2 triangles) is derived in code from its sign mask — there is
##   no 256-entry literal table to mistype. Triangle winding is settled per-triangle against the
##   field gradient, which kills the whole class of orientation-case bugs.
## - Normals are the field gradient (central differences, trilinearly sampled) — smooth organic
##   shading straight from the SDF, no face averaging.
##
## prim: {"type": "capsule"|"ellipsoid"|"sphere",
##        capsule:  "a": Vector3, "b": Vector3, "r1": float, "r2": float   (tapered)
##        ellipsoid:"c": Vector3, "r": Vector3
##        sphere:   "c": Vector3, "r1": float
##        all:      "k": float  (smooth-min blend radius into the accumulated field)}

const FAR := 1.0e9

## Polygonise. cell = voxel size in metres (0.07-0.09 for the preview, coarser for tests).
## Returns {"mesh": ArrayMesh, "verts": int, "tris": int, "aabb": AABB} — null mesh if empty.
static func build(prims: Array, cell: float, color: Color = Color(0.5, 0.45, 0.4)) -> Dictionary:
	if prims.is_empty():
		return {"mesh": null, "verts": 0, "tris": 0, "aabb": AABB()}
	# --- bounds: union of primitive boxes + blend margin, snapped to the lattice ---
	var mn := Vector3(FAR, FAR, FAR)
	var mx := -mn
	for pr in prims:
		var pb := _prim_aabb(pr)
		mn = mn.min(pb.position)
		mx = mx.max(pb.position + pb.size)
	mn -= Vector3.ONE * cell * 2.0
	mx += Vector3.ONE * cell * 2.0
	var nx := int(ceil((mx.x - mn.x) / cell)) + 1
	var ny := int(ceil((mx.y - mn.y) / cell)) + 1
	var nz := int(ceil((mx.z - mn.z) / cell)) + 1
	var field := PackedFloat32Array()
	field.resize(nx * ny * nz)
	field.fill(FAR)

	# --- splat each primitive over its influence box only ---
	for pr in prims:
		var pd := pr as Dictionary
		var k := maxf(0.001, float(pd.get("k", 0.1)))
		var pb := _prim_aabb(pd)
		var x0 := maxi(0, int((pb.position.x - mn.x) / cell))
		var y0 := maxi(0, int((pb.position.y - mn.y) / cell))
		var z0 := maxi(0, int((pb.position.z - mn.z) / cell))
		var x1 := mini(nx - 1, int(ceil((pb.position.x + pb.size.x - mn.x) / cell)))
		var y1 := mini(ny - 1, int(ceil((pb.position.y + pb.size.y - mn.y) / cell)))
		var z1 := mini(nz - 1, int(ceil((pb.position.z + pb.size.z - mn.z) / cell)))
		for zi in range(z0, z1 + 1):
			for yi in range(y0, y1 + 1):
				var row := (zi * ny + yi) * nx
				var py := mn.y + yi * cell
				var pz := mn.z + zi * cell
				for xi in range(x0, x1 + 1):
					var d := _prim_dist(pd, Vector3(mn.x + xi * cell, py, pz))
					var idx := row + xi
					var old := field[idx]
					# polynomial smooth min (k-blend); far values pass through as plain min
					var h := clampf(0.5 + 0.5 * (old - d) / k, 0.0, 1.0)
					field[idx] = lerpf(old, d, h) - k * h * (1.0 - h)

	# --- marching tetrahedra over sign-mixed cells ---
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var vert_ids := {}
	# The KUHN triangulation: 6 tets sharing the cube's MAIN diagonal 0-7, one per axis-order
	# permutation (0 -> first axis -> first|second -> 7). This exactly tiles the cube — any other
	# "looks plausible" tet list overlaps/misses volume and doubles the isosurface into z-fighting
	# sheets (30-45% non-manifold edges; the manifold test guards this). Corner bits: x=1, y=2, z=4.
	var tets := [[0, 1, 3, 7], [0, 1, 5, 7], [0, 2, 3, 7], [0, 2, 6, 7], [0, 4, 5, 7], [0, 4, 6, 7]]
	var corner_off := [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
	]
	var cv := PackedFloat32Array()
	cv.resize(8)
	for zi in range(nz - 1):
		for yi in range(ny - 1):
			for xi in range(nx - 1):
				var neg := 0
				var pos := 0
				for ci in range(8):
					var o: Vector3i = corner_off[ci]
					var v := field[((zi + o.z) * ny + (yi + o.y)) * nx + xi + o.x]
					cv[ci] = v
					if v < 0.0: neg += 1
					else: pos += 1
				if neg == 0 or pos == 0:
					continue
				var base := Vector3(mn.x + xi * cell, mn.y + yi * cell, mn.z + zi * cell)
				for tet in tets:
					_emit_tet(tet, cv, corner_off, base, cell, verts, indices, vert_ids,
						field, mn, cell, nx, ny, nz)

	if indices.is_empty():
		return {"mesh": null, "verts": 0, "tris": 0, "aabb": AABB()}

	# --- normals from the field gradient at each vertex ---
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(verts.size()):
		normals[i] = _gradient(field, verts[i], mn, cell, nx, ny, nz)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.surface_set_material(0, mat)
	var out_aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		out_aabb = out_aabb.expand(v)
	return {"mesh": mesh, "verts": verts.size(), "tris": indices.size() / 3, "aabb": out_aabb}

# One tetrahedron: find the sign-crossing edges (3 -> one triangle, 4 -> two), interpolate the
# surface points, and wind each triangle against the local field gradient.
static func _emit_tet(tet: Array, cv: PackedFloat32Array, corner_off: Array, base: Vector3,
		cell: float, verts: PackedVector3Array, indices: PackedInt32Array, vert_ids: Dictionary,
		field: PackedFloat32Array, mn: Vector3, cell2: float, nx: int, ny: int, nz: int) -> void:
	var inside: Array = []
	var outside: Array = []
	for ci in tet:
		if cv[ci] < 0.0:
			inside.append(ci)
		else:
			outside.append(ci)
	if inside.is_empty() or outside.is_empty():
		return
	var pts: Array = []
	if inside.size() == 1 or inside.size() == 3:
		var lone: int = inside[0] if inside.size() == 1 else outside[0]
		var others: Array = outside if inside.size() == 1 else inside
		for oc in others:
			pts.append(_edge_point(lone, oc, cv, corner_off, base, cell))
		_push_tri(pts[0], pts[1], pts[2], verts, indices, vert_ids, field, mn, cell2, nx, ny, nz)
	else:
		# 2-2 split: quad ordered a0b0, a0b1, a1b1, a1b0 walks the ring
		var a0: int = inside[0]; var a1: int = inside[1]
		var b0: int = outside[0]; var b1: int = outside[1]
		var q0 := _edge_point(a0, b0, cv, corner_off, base, cell)
		var q1 := _edge_point(a0, b1, cv, corner_off, base, cell)
		var q2 := _edge_point(a1, b1, cv, corner_off, base, cell)
		var q3 := _edge_point(a1, b0, cv, corner_off, base, cell)
		_push_tri(q0, q1, q2, verts, indices, vert_ids, field, mn, cell2, nx, ny, nz)
		_push_tri(q0, q2, q3, verts, indices, vert_ids, field, mn, cell2, nx, ny, nz)

static func _edge_point(ca: int, cb: int, cv: PackedFloat32Array, corner_off: Array,
		base: Vector3, cell: float) -> Vector3:
	var va := cv[ca]
	var vb := cv[cb]
	# t clamped AWAY from the corners: a point landing exactly on a lattice corner welds across
	# every tet sharing it, dropping degenerate triangles and pin-holing the surface.
	var t := clampf(va / (va - vb), 0.02, 0.98) if absf(va - vb) > 1.0e-9 else 0.5
	var pa := base + Vector3(corner_off[ca]) * cell
	var pb := base + Vector3(corner_off[cb]) * cell
	return pa.lerp(pb, t)

static func _push_tri(p0: Vector3, p1: Vector3, p2: Vector3, verts: PackedVector3Array,
		indices: PackedInt32Array, vert_ids: Dictionary, field: PackedFloat32Array,
		mn: Vector3, cell: float, nx: int, ny: int, nz: int) -> void:
	var e1 := p1 - p0
	var e2 := p2 - p0
	var n := e1.cross(e2)
	if n.length_squared() < 1.0e-12:
		return
	# outward = toward positive field
	var g := _gradient(field, (p0 + p1 + p2) / 3.0, mn, cell, nx, ny, nz)
	var flip := n.dot(g) < 0.0
	var i0 := _vid(p0, verts, vert_ids)
	var i1 := _vid(p1, verts, vert_ids)
	var i2 := _vid(p2, verts, vert_ids)
	if i0 == i1 or i1 == i2 or i0 == i2:
		return
	if flip:
		indices.append(i0); indices.append(i2); indices.append(i1)
	else:
		indices.append(i0); indices.append(i1); indices.append(i2)

static func _vid(p: Vector3, verts: PackedVector3Array, vert_ids: Dictionary) -> int:
	var key := "%d,%d,%d" % [int(round(p.x * 5000.0)), int(round(p.y * 5000.0)), int(round(p.z * 5000.0))]
	if vert_ids.has(key):
		return vert_ids[key]
	var id := verts.size()
	verts.append(p)
	vert_ids[key] = id
	return id

static func _gradient(field: PackedFloat32Array, p: Vector3, mn: Vector3, cell: float,
		nx: int, ny: int, nz: int) -> Vector3:
	var e := cell * 0.6
	var g := Vector3(
		_sample(field, p + Vector3(e, 0, 0), mn, cell, nx, ny, nz) - _sample(field, p - Vector3(e, 0, 0), mn, cell, nx, ny, nz),
		_sample(field, p + Vector3(0, e, 0), mn, cell, nx, ny, nz) - _sample(field, p - Vector3(0, e, 0), mn, cell, nx, ny, nz),
		_sample(field, p + Vector3(0, 0, e), mn, cell, nx, ny, nz) - _sample(field, p - Vector3(0, 0, e), mn, cell, nx, ny, nz))
	return g.normalized() if g.length_squared() > 1.0e-12 else Vector3.UP

static func _sample(field: PackedFloat32Array, p: Vector3, mn: Vector3, cell: float,
		nx: int, ny: int, nz: int) -> float:
	var fx := clampf((p.x - mn.x) / cell, 0.0, float(nx - 1) - 0.001)
	var fy := clampf((p.y - mn.y) / cell, 0.0, float(ny - 1) - 0.001)
	var fz := clampf((p.z - mn.z) / cell, 0.0, float(nz - 1) - 0.001)
	var xi := int(fx); var yi := int(fy); var zi := int(fz)
	var tx := fx - xi; var ty := fy - yi; var tz := fz - zi
	var c000 := field[(zi * ny + yi) * nx + xi]
	var c100 := field[(zi * ny + yi) * nx + xi + 1]
	var c010 := field[(zi * ny + yi + 1) * nx + xi]
	var c110 := field[(zi * ny + yi + 1) * nx + xi + 1]
	var c001 := field[((zi + 1) * ny + yi) * nx + xi]
	var c101 := field[((zi + 1) * ny + yi) * nx + xi + 1]
	var c011 := field[((zi + 1) * ny + yi + 1) * nx + xi]
	var c111 := field[((zi + 1) * ny + yi + 1) * nx + xi + 1]
	return lerpf(lerpf(lerpf(c000, c100, tx), lerpf(c010, c110, tx), ty),
		lerpf(lerpf(c001, c101, tx), lerpf(c011, c111, tx), ty), tz)

# --- primitive distances + influence boxes ---

static func _prim_dist(pr: Dictionary, p: Vector3) -> float:
	match str(pr.get("type", "sphere")):
		"capsule":
			var a: Vector3 = pr["a"]
			var b: Vector3 = pr["b"]
			var r1 := float(pr.get("r1", 0.1))
			var r2 := float(pr.get("r2", r1))
			var ab := b - a
			var denom := ab.length_squared()
			var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0) if denom > 1.0e-9 else 0.0
			return (p - (a + ab * t)).length() - lerpf(r1, r2, t)
		"ellipsoid":
			var c: Vector3 = pr["c"]
			var r: Vector3 = pr["r"]
			var q := p - c
			var k0 := Vector3(q.x / r.x, q.y / r.y, q.z / r.z).length()
			var k1 := Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).length()
			return k0 * (k0 - 1.0) / maxf(k1, 1.0e-6)
		_:
			return (p - (pr["c"] as Vector3)).length() - float(pr.get("r1", 0.1))

static func _prim_aabb(pr: Dictionary) -> AABB:
	var margin := maxf(0.001, float(pr.get("k", 0.1))) * 1.6
	match str(pr.get("type", "sphere")):
		"capsule":
			var a: Vector3 = pr["a"]
			var b: Vector3 = pr["b"]
			var r := maxf(float(pr.get("r1", 0.1)), float(pr.get("r2", 0.1))) + margin
			var lo := a.min(b) - Vector3.ONE * r
			return AABB(lo, a.max(b) + Vector3.ONE * r - lo)
		"ellipsoid":
			var c: Vector3 = pr["c"]
			var r2: Vector3 = (pr["r"] as Vector3) + Vector3.ONE * margin
			return AABB(c - r2, r2 * 2.0)
		_:
			var c3: Vector3 = pr["c"]
			var r3 := float(pr.get("r1", 0.1)) + margin
			return AABB(c3 - Vector3.ONE * r3, Vector3.ONE * r3 * 2.0)
