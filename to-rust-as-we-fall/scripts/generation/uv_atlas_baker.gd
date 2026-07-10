class_name UvAtlasBaker
extends RefCounted

## UV ATLAS BAKER — turns a generated (UV-less) ArrayMesh into a Blockbench-ready hand-painting kit:
## box-projected UV islands packed into one atlas, a template PNG painted with the base tint + a
## texel-visible panel grid, and PIXEL-ART EDGE WEAR laid down from the geometry itself (crease edges
## found by dihedral angle: convex creases get a dithered worn-bright line, concave ones grime).
## Export via export_obj() -> .obj + .mtl + .png that open directly in Blockbench for refinement.
##
## Deterministic throughout (hash dither, no RNG): the same mesh always bakes the same atlas, so a
## re-export never invalidates paint-over work done on an older template.

const PX_PER_M := 32          # the house pixel-art density (32 px/m tile atlas convention)
const PAD := 2                # texels of padding around every island
const MAX_ATLAS := 2048       # hard cap; beyond this the bake fails loudly rather than silently scale
const CREASE_DEG := 38.0      # dihedral angle above which an edge counts as a crease (gets wear)

## Bake `mesh` -> {"mesh": ArrayMesh (same tris, UVs added), "image": Image (the template),
## "islands": int, "creases": int}. `opts`: base_color, grime_color, wear_color, px_per_m.
static func bake(mesh: ArrayMesh, opts: Dictionary = {}) -> Dictionary:
	var ppm := int(opts.get("px_per_m", PX_PER_M))
	var base_color: Color = opts.get("base_color", Color(0.31, 0.35, 0.37))
	var grime: Color = opts.get("grime_color", Color(0.16, 0.17, 0.16))
	var wear: Color = opts.get("wear_color", Color(0.62, 0.66, 0.64))
	# --- gather every triangle from every surface into one soup ---
	var pos := PackedVector3Array()
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx_v == null or (idx_v as PackedInt32Array).is_empty():
			pos.append_array(verts)
		else:
			for i in (idx_v as PackedInt32Array):
				pos.append(verts[i])
	var tri_count := pos.size() / 3
	if tri_count == 0:
		return {}
	# --- per-triangle chart axis (dominant normal component -> one of 6 bins) ---
	var tri_axis := PackedInt32Array()
	var tri_normal: Array[Vector3] = []
	for t in range(tri_count):
		var n := (pos[t * 3 + 1] - pos[t * 3]).cross(pos[t * 3 + 2] - pos[t * 3])
		tri_normal.append(n.normalized() if n.length() > 1.0e-9 else Vector3.UP)
		tri_axis.append(_axis_bin(tri_normal[t]))
	# --- weld verts (quantized) for adjacency; edges shared by two tris ---
	var vid := {}
	var tri_vid := PackedInt32Array()
	for i2 in range(pos.size()):
		var key := Vector3i((pos[i2] * 512.0).round())
		if not vid.has(key):
			vid[key] = vid.size()
		tri_vid.append(int(vid[key]))
	var edge_tris := {}   # "a_b" (sorted vids) -> Array[tri]
	for t2 in range(tri_count):
		for e in range(3):
			var a := tri_vid[t2 * 3 + e]
			var b := tri_vid[t2 * 3 + (e + 1) % 3]
			var ek := "%d_%d" % [mini(a, b), maxi(a, b)]
			if not edge_tris.has(ek):
				edge_tris[ek] = []
			(edge_tris[ek] as Array).append(t2)
	# --- islands: connected components of same-bin adjacent triangles ---
	var island_of := PackedInt32Array()
	island_of.resize(tri_count)
	island_of.fill(-1)
	var islands: Array = []   # per island: {axis, tris: Array[int]}
	for t3 in range(tri_count):
		if island_of[t3] != -1:
			continue
		var stack: Array = [t3]
		var members: Array = []
		island_of[t3] = islands.size()
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			members.append(cur)
			for e2 in range(3):
				var a2 := tri_vid[cur * 3 + e2]
				var b2 := tri_vid[cur * 3 + (e2 + 1) % 3]
				var ek2 := "%d_%d" % [mini(a2, b2), maxi(a2, b2)]
				for other in (edge_tris[ek2] as Array):
					if island_of[int(other)] == -1 and tri_axis[int(other)] == tri_axis[t3]:
						island_of[int(other)] = islands.size()
						stack.append(int(other))
		islands.append({"axis": tri_axis[t3], "tris": members})
	# --- project each island to 2D texels, then shelf-pack ---
	for isl in islands:
		var id := isl as Dictionary
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for t4 in (id["tris"] as Array):
			for k in range(3):
				var p2 := _project(pos[int(t4) * 3 + k], int(id["axis"]))
				lo = lo.min(p2)
				hi = hi.max(p2)
		id["lo"] = lo
		id["w"] = maxi(1, int(ceilf((hi.x - lo.x) * float(ppm)))) + PAD * 2
		id["h"] = maxi(1, int(ceilf((hi.y - lo.y) * float(ppm)))) + PAD * 2
	var order := range(islands.size())
	order.sort_custom(func(x, y): return int((islands[x] as Dictionary)["h"]) > int((islands[y] as Dictionary)["h"]))
	var total_area := 0
	for isl2 in islands:
		total_area += int((isl2 as Dictionary)["w"]) * int((isl2 as Dictionary)["h"])
	var atlas_w := 64
	while atlas_w * atlas_w < total_area * 2 and atlas_w < MAX_ATLAS:
		atlas_w *= 2
	var shelf_x := 0
	var shelf_y := 0
	var shelf_h := 0
	for oi in order:
		var id2 := islands[oi] as Dictionary
		if shelf_x + int(id2["w"]) > atlas_w:
			shelf_y += shelf_h
			shelf_x = 0
			shelf_h = 0
		id2["ox"] = shelf_x + PAD
		id2["oy"] = shelf_y + PAD
		shelf_x += int(id2["w"])
		shelf_h = maxi(shelf_h, int(id2["h"]))
	var atlas_h := _next_pow2(shelf_y + shelf_h)
	if atlas_h > MAX_ATLAS:
		push_error("UvAtlasBaker: atlas %dx%d exceeds MAX_ATLAS — mesh too large for one sheet" % [atlas_w, atlas_h])
		return {}
	# --- write UVs (triangle soup out, one surface) ---
	var uvs := PackedVector2Array()
	uvs.resize(pos.size())
	var inv := Vector2(1.0 / float(atlas_w), 1.0 / float(atlas_h))
	for t5 in range(tri_count):
		var id3 := islands[island_of[t5]] as Dictionary
		for k2 in range(3):
			var p3 := _project(pos[t5 * 3 + k2], int(id3["axis"]))
			var texel := Vector2(float(int(id3["ox"])), float(int(id3["oy"]))) + (p3 - (id3["lo"] as Vector2)) * float(ppm)
			uvs[t5 * 3 + k2] = texel * inv
	# --- the template image: base fill + hash panel tint + island frames ---
	var img := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for isl3 in islands:
		var id4 := isl3 as Dictionary
		for py in range(int(id4["oy"]) - 1, int(id4["oy"]) + int(id4["h"]) - PAD * 2 + 1):
			for px in range(int(id4["ox"]) - 1, int(id4["ox"]) + int(id4["w"]) - PAD * 2 + 1):
				if px < 0 or py < 0 or px >= atlas_w or py >= atlas_h:
					continue
				var v := _h01(float(px / 8) * 13.1 + float(py / 8) * 7.7) * 0.08 - 0.04
				img.set_pixel(px, py, Color(base_color.r + v, base_color.g + v, base_color.b + v, 1.0))
	# --- pixel-art EDGE WEAR from geometry: crease edges rasterized into both adjacent islands ---
	var crease_count := 0
	var cos_thresh := cos(deg_to_rad(CREASE_DEG))
	for ek3 in edge_tris.keys():
		var tris: Array = edge_tris[ek3]
		if tris.size() != 2:
			continue
		var ta := int(tris[0])
		var tb := int(tris[1])
		if tri_normal[ta].dot(tri_normal[tb]) > cos_thresh:
			continue
		crease_count += 1
		# convex crease (faces bend AWAY) = worn bright edge; concave = grime shadow
		var ca := (pos[ta * 3] + pos[ta * 3 + 1] + pos[ta * 3 + 2]) / 3.0
		var cb := (pos[tb * 3] + pos[tb * 3 + 1] + pos[tb * 3 + 2]) / 3.0
		var convex := tri_normal[ta].dot(cb - ca) < 0.0
		var epts := _edge_points(ek3, tri_vid, pos, ta)
		for t6 in [ta, tb]:
			var id5 := islands[island_of[t6]] as Dictionary
			var a3 := _texel_of(epts[0], id5, ppm)
			var b3 := _texel_of(epts[1], id5, ppm)
			_wear_line(img, a3, b3, wear if convex else grime, convex)
	var out := ArrayMesh.new()
	var arrays2 := []
	arrays2.resize(Mesh.ARRAY_MAX)
	arrays2[Mesh.ARRAY_VERTEX] = pos
	arrays2[Mesh.ARRAY_TEX_UV] = uvs
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
	return {"mesh": out, "image": img, "islands": islands.size(), "creases": crease_count}

## Write the baked kit as <path_base>.obj/.mtl/.png — opens directly in Blockbench for paint-over.
static func export_obj(baked: Dictionary, path_base: String) -> bool:
	if baked.is_empty():
		return false
	var mesh := baked["mesh"] as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var png_name := path_base.get_file() + ".png"
	var mtl_name := path_base.get_file() + ".mtl"
	(baked["image"] as Image).save_png(path_base + ".png")
	var mtl := FileAccess.open(path_base + ".mtl", FileAccess.WRITE)
	if mtl == null:
		return false
	mtl.store_string("newmtl baked\nKd 1 1 1\nmap_Kd %s\n" % png_name)
	mtl.close()
	var f := FileAccess.open(path_base + ".obj", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("mtllib %s\nusemtl baked\n" % mtl_name)
	for p in pos:
		f.store_string("v %f %f %f\n" % [p.x, p.y, p.z])
	for uv in uvs:
		f.store_string("vt %f %f\n" % [uv.x, 1.0 - uv.y])
	for t in range(pos.size() / 3):
		var i := t * 3 + 1
		f.store_string("f %d/%d %d/%d %d/%d\n" % [i, i, i + 1, i + 1, i + 2, i + 2])
	f.close()
	return true

static func _axis_bin(n: Vector3) -> int:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if ay >= ax and ay >= az:
		return 2 if n.y >= 0.0 else 3
	if ax >= az:
		return 0 if n.x >= 0.0 else 1
	return 4 if n.z >= 0.0 else 5

# Project onto the chart plane with consistent handedness (no mirrored paint between +/- faces).
static func _project(p: Vector3, axis: int) -> Vector2:
	match axis:
		0: return Vector2(-p.z, -p.y)
		1: return Vector2(p.z, -p.y)
		2: return Vector2(p.x, p.z)
		3: return Vector2(p.x, -p.z)
		4: return Vector2(p.x, -p.y)
		_: return Vector2(-p.x, -p.y)

static func _texel_of(p: Vector3, island: Dictionary, ppm: int) -> Vector2i:
	var uv2 := _project(p, int(island["axis"]))
	var t := Vector2(float(int(island["ox"])), float(int(island["oy"]))) + (uv2 - (island["lo"] as Vector2)) * float(ppm)
	return Vector2i(t.round())

# One world-space edge (by welded ids) recovered from the owning triangle's corners.
static func _edge_points(ek: String, tri_vid: PackedInt32Array, pos: PackedVector3Array, tri: int) -> Array:
	var parts := ek.split("_")
	var a := int(parts[0])
	var b := int(parts[1])
	var pa := Vector3.ZERO
	var pb := Vector3.ZERO
	for k in range(3):
		if tri_vid[tri * 3 + k] == a:
			pa = pos[tri * 3 + k]
		if tri_vid[tri * 3 + k] == b:
			pb = pos[tri * 3 + k]
	return [pa, pb]

const _BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

# The pixel-art wear stroke: a Bresenham line of the wear tint; convex edges stipple a second,
# lighter pass one texel inward (the house Bayer dither) so the crease reads chipped, not inked.
static func _wear_line(img: Image, a: Vector2i, b: Vector2i, tint: Color, convex: bool) -> void:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	if steps == 0:
		return
	for s in range(steps + 1):
		var p := a + Vector2i((Vector2(d) * (float(s) / float(steps))).round())
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			continue
		if img.get_pixel(p.x, p.y).a < 0.5:
			continue   # outside every island (padding) — never paint the void
		img.set_pixel(p.x, p.y, tint)
		if convex and _BAYER4[(p.x % 4) + (p.y % 4) * 4] < 5:
			var q := p + (Vector2i(0, 1) if absi(d.x) >= absi(d.y) else Vector2i(1, 0))
			if q.x < img.get_width() and q.y < img.get_height() and img.get_pixel(q.x, q.y).a > 0.5:
				img.set_pixel(q.x, q.y, tint.lightened(0.18))

static func _next_pow2(v: int) -> int:
	var p := 64
	while p < v:
		p *= 2
	return p

static func _h01(nv: float) -> float:
	return fmod(absf(sin(nv * 127.13) * 43758.5453), 1.0)
