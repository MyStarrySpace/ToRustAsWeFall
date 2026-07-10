class_name LatticeBuilder
extends RefCounted

## LATTICE BUILDER — step 2 of the district architecture, layered on the base shapes (step 1).
## Takes a base solid and skins its faces with a "lattice" of surface detail. Elements:
##
##   honeyframe — the Honeycomb Cooperative facade. SUBDIVIDE each vertical face into an N×M grid
##                (per the user's spec), then turn every grid cell into a rounded-rect WINDOW inside a
##                raised cream FRAME strut lattice. Corners are ROUNDED (the "cut toward the vertex"
##                round) and the struts naturally thicken at the grid junctions — the honeycomb look.
##
## Pipes (edge-descent tubes) and tracery (the PPP's pointed-arch window wall) are the next elements.
## Everything here is deterministic (a regular grid — no RNG yet) and low-poly.

const HONEYFRAME_DEFAULTS := {
	"cell_size": 1.45,     # target metres per cell; ~3 blobs across the front face (plate scale)
	# (rows come from cell_size * cell_aspect — the plate face reads ~3 wide x ~6 high)
	"frame_width": 0.20,   # cream strut thickness (the window inset from the cell edge)
	"frame_depth": 0.12,   # how far the frame top stands proud of the wall
	"back_bite": 0.03,     # how far the closed frame sinks INTO the wall (overlaps the box, no z-fight)
	"pane": 0.02,          # lit pane depth: recessed under the frame top, a hair proud of the wall behind
	"corner_round": 0.30,  # P (<=0.5): how much of the half-window is rounded — rounded RECTS, not circles
	"arc_seg": 3,          # segments per rounded corner (low-poly)
	"cell_aspect": 0.95,   # near-round blob target (height/width per cell); variance + merges stretch them
	"jitter": 0.12,        # per-cell hand-made irregularity: offset + scale the WINDOW within its cell
	"bevel": 0.05,         # frame moulding: the band crests this much above its rims (chamfered profile)
	"crown": true,         # emit a cornice + parapet + plinth silhouette
	"pane_color": Color(1.0, 0.72, 0.36),   # base window-light colour; per-pane brightness/tint varies off it
	"rib_merge": "sasb",   # "sasb" (the director's S_A/S_B corner-cut network — THE honeyframe) or
	                       # "frame_ring" (the old moulded per-cell rings, kept for comparison)
	"cut": 0.30,           # S_A: corner-cut fraction along each edge away from the vertex (capped 0.5)
	"pinch": 0.72,         # S_A rounding pulled TOWARD the vertex (the organic pinched junction)
	"rib_radius": 0.10,    # S_A/S_B rib crest radius (the strut gauge)
	"rib_sides": 5,
	# IRREGULAR SUBDIVISION — the plate's cells are organic blobs of DIFFERING size/shape, not a grid.
	# The director's algorithm runs on "the subdivided mesh"; these make that mesh irregular:
	"size_variance": 0.45, # grid-line spacing spread (rows/columns of visibly different size)
	"merge_chance": 0.26,  # chance an interior cell wall dissolves -> two cells fuse into one big blob
	"cut_variance": 0.4,   # per-vertex spread of the S_A cut fraction (junction pinches vary)
}

## Build the honeyframe lattice for a box of `size` (base at y=0). Returns {frame, glass} ArrayMeshes:
## `frame` = the raised cream strut lattice, `glass` = the flush lit window panes.
static func honeyframe(size: Vector3, overrides: Dictionary = {}) -> Dictionary:
	var p := HONEYFRAME_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var faces := _box_vertical_faces(size)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	var mode := str(p.get("rib_merge", "sasb"))
	for f in faces:
		match mode:
			"frame_ring":
				cells += _honeyframe_face(f as Dictionary, p, frame_st, glass_st)
			"junction":
				cells += _honeyframe_face_junction(f as Dictionary, p, frame_st, glass_st)
			_:
				cells += _honeyframe_face_sasb(f as Dictionary, p, frame_st, glass_st)
	# Closed corner posts down the four vertical box edges cover the miter seam where two faces' frames
	# meet at 90 degrees (otherwise a bare L-wedge runs the full height of every corner).
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var post := float(p["frame_width"]) * 0.75
	var half_y := size.y * 0.5
	for sx in [hx, -hx]:
		for sz in [hz, -hz]:
			_emit_box(frame_st, Vector3(sx, half_y, sz), Vector3(post, half_y, post))
	# `crown` = the rooftop cornice/parapet/vent; `base` = the stepped ground plinth. Split flags (both
	# default true = a flat building) so a TIERED cake puts the crown only on the top drum and the plinth
	# only on the ground drum — not a rooftop vent baked into every inter-tier ledge.
	if bool(p.get("crown", true)):
		_emit_crown(frame_st, size)
	if bool(p.get("base", true)):
		_emit_base_plinth(frame_st, size)
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cells}

# A cornice + parapet-wall ring + a rooftop vent — the roof silhouette a bare box lacks. Closed boxes.
static func _emit_crown(st: SurfaceTool, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var oh := 0.18   # cornice overhang
	var ct := 0.26   # cornice thickness
	_emit_box(st, Vector3(0, size.y + ct * 0.5, 0), Vector3(hx + oh, ct * 0.5, hz + oh))   # cornice slab
	# parapet-wall ring around the roof edge
	var py := size.y + ct
	var ph := 0.34
	var pw := 0.09
	_emit_box(st, Vector3(0, py + ph * 0.5, hz + oh - pw), Vector3(hx + oh, ph * 0.5, pw))
	_emit_box(st, Vector3(0, py + ph * 0.5, -(hz + oh - pw)), Vector3(hx + oh, ph * 0.5, pw))
	_emit_box(st, Vector3(hx + oh - pw, py + ph * 0.5, 0), Vector3(pw, ph * 0.5, hz + oh))
	_emit_box(st, Vector3(-(hx + oh - pw), py + ph * 0.5, 0), Vector3(pw, ph * 0.5, hz + oh))
	# a small rooftop vent/housing
	_emit_box(st, Vector3(hx * 0.35, py + 0.28, -hz * 0.25), Vector3(hx * 0.28, 0.28, hz * 0.22))

# The stepped plinth at the base — the ground foot a bare box lacks.
static func _emit_base_plinth(st: SurfaceTool, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	_emit_box(st, Vector3(0, 0.16, 0), Vector3(hx + 0.24, 0.16, hz + 0.24))
	_emit_box(st, Vector3(0, 0.40, 0), Vector3(hx + 0.11, 0.10, hz + 0.11))

# ============================================================================================
# VORONOI MEMBRANE — the director's decoration function, implemented as designed: (1) VORONOI —
# scatter seeds over the face and take the cell web; (2) FOCAL POINTS — cells MERGE harder the
# further they sit from a focal point, so the web stays fine around the focals and opens into big
# blobs away from them; (3) MIRRORING — seeds/focals are generated on HALF the face and mirrored, so
# the decor reads as authored symmetry. The surviving web edges feed LatticeGraph -> one watertight
# fused rib membrane (Bulwark Wharf's plate wall). FAR LOD: the SAME 2D web bakes into a texture on
# a flat quad; GeometryInstance3D visibility ranges cross the two over — decoration becomes texture
# at distance, engine-native, no per-frame code.
# ============================================================================================

const VORONOI_DEFAULTS := {
	"seeds": 34,            # Voronoi sites per face (pre-mirror total; density of the web)
	"focals": 2,            # focal points per face (mirrored like the seeds)
	"merge_start": 0.7,     # distance from a focal where merging begins
	"merge_range": 2.4,     # distance over which the merge chance ramps to merge_max
	"merge_max": 0.78,      # cells this far from every focal usually fuse
	"sag": 0.14,            # catenary droop per metre of edge span (the plate's membrane hangs)
	"mirror": true,
	"rib_radius": 0.065,
	"rib_sides": 5,
	"rib_color": Color(0.72, 0.70, 0.66),
	"lod_switch": 30.0,     # metres: nearer = rib GEOMETRY, farther = the baked TEXTURE quad
	"tex_px": 256,          # far-LOD texture width (height follows the face aspect)
}

## Build the Voronoi membrane for a box of `size`. Returns {"frame": ArrayMesh (near LOD, all faces),
## "faces": [{tex, c, u, n, w, h}] (far-LOD bake per face), "lod_switch": float}.
static func voronoi(size: Vector3, overrides: Dictionary = {}) -> Dictionary:
	var p := VORONOI_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var reserved: Array = p.get("reserved", [])
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	frame_st.set_color(p["rib_color"])
	var faces_out: Array = []
	for f in _box_vertical_faces(size):
		var fd := f as Dictionary
		var w: float = fd["w"]
		var h: float = fd["h"]
		var n: Vector3 = (fd["n"] as Vector3).normalized()
		var u: Vector3 = (fd["u"] as Vector3).normalized()
		var c: Vector3 = fd["c"]
		var fkey := (n.x * 5.3 + n.z * 11.7) * 23.0
		var paths := _voronoi_web(w, h, p, fkey, n, reserved)
		var origin := c - u * (w * 0.5) + Vector3(0, -h * 0.5, 0)
		var graph: Dictionary = LatticeGraph.build(paths, 0.012)
		LatticeGraph.mesh(frame_st, graph, LatticeGraph.plane_surface(origin, u, Vector3(0, 1, 0)), float(p["rib_radius"]), int(p["rib_sides"]))
		faces_out.append({"tex": _bake_web_texture(paths, w, h, int(p["tex_px"]), float(p["rib_radius"]), p["rib_color"] as Color),
			"c": c, "u": u, "n": n, "w": w, "h": h})
	frame_st.generate_normals()
	return {"frame": frame_st.commit(), "faces": faces_out, "lod_switch": float(p["lod_switch"])}

# The 2D web for one face: jittered-grid seeds on the half-face, mirrored; Voronoi cells by
# half-plane clipping; interior edges dropped by the focal-falloff merge; door edges dropped.
static func _voronoi_web(w: float, h: float, p: Dictionary, fkey: float, face_n: Vector3, reserved: Array) -> Array:
	var mirror := bool(p["mirror"])
	var half_w := w * 0.5 if mirror else w
	var count := maxi(4, int(p["seeds"]) / (2 if mirror else 1))
	# jittered-grid seed placement over the (half-)face — even coverage, deterministic
	var seeds: Array = []
	var gcols := maxi(1, int(round(sqrt(float(count) * half_w / h))))
	var grows := maxi(1, int(ceil(float(count) / float(gcols))))
	var placed := 0
	for gj in range(grows):
		for gi in range(gcols):
			if placed >= count:
				break
			var sx := (float(gi) + 0.18 + 0.64 * _h01(fkey + float(placed) * 12.9)) * half_w / float(gcols)
			var sy := (float(gj) + 0.18 + 0.64 * _h01(fkey + float(placed) * 7.7 + 40.0)) * h / float(grows)
			if mirror:
				sx = minf(sx, half_w - 0.06)   # keep off the axis so the mirror twin never degenerates
			seeds.append(Vector2(sx, sy))
			placed += 1
	if mirror:
		var mirrored: Array = []
		for s in seeds:
			mirrored.append(Vector2(w - (s as Vector2).x, (s as Vector2).y))
		seeds.append_array(mirrored)
	# focal points (mirrored the same way): the web stays FINE around these, merges away from them
	var focals: Array = []
	for fi in range(maxi(1, int(p["focals"]))):
		var fx := half_w * (0.25 + 0.6 * _h01(fkey + float(fi) * 31.3 + 200.0))
		var fy := h * (0.2 + 0.6 * _h01(fkey + float(fi) * 17.9 + 300.0))
		focals.append(Vector2(fx, fy))
		if mirror:
			focals.append(Vector2(w - fx, fy))
	# Voronoi cells by half-plane clipping (bounded by the face rect)
	var edge_map: Dictionary = {}
	for i in range(seeds.size()):
		var poly := _voronoi_cell(seeds, i, w, h)
		for e in range(poly.size()):
			var a := poly[e] as Vector2
			var b := poly[(e + 1) % poly.size()] as Vector2
			if a.distance_to(b) < 0.05:
				continue
			var ka := "%d,%d" % [int(round(a.x * 500.0)), int(round(a.y * 500.0))]
			var kb := "%d,%d" % [int(round(b.x * 500.0)), int(round(b.y * 500.0))]
			var ek := ka + "|" + kb if ka < kb else kb + "|" + ka
			if not edge_map.has(ek):
				edge_map[ek] = {"a": a, "b": b, "n": 0}
			(edge_map[ek] as Dictionary)["n"] = int((edge_map[ek] as Dictionary)["n"]) + 1
	# the merge: interior edges (shared by two cells) dissolve with distance from the nearest focal
	var ms := float(p["merge_start"])
	var mr := maxf(0.1, float(p["merge_range"]))
	var mm := clampf(float(p["merge_max"]), 0.0, 1.0)
	var paths: Array = []
	for ek in edge_map.keys():
		var ed := edge_map[ek] as Dictionary
		var a2 := ed["a"] as Vector2
		var b2 := ed["b"] as Vector2
		if int(ed["n"]) >= 2:
			var mid := (a2 + b2) * 0.5
			var dmin := 1.0e9
			for fp in focals:
				dmin = minf(dmin, mid.distance_to(fp as Vector2))
			var chance := clampf((dmin - ms) / mr, 0.0, 1.0) * mm
			if _h01(fkey + mid.x * 43.7 + mid.y * 91.3) < chance:
				continue   # the two cells fuse — the web opens into a bigger blob here
		if _seg_reserved_face(a2, b2, w, face_n, reserved):
			continue   # never web across a doorway
		# CATENARY sag: interior, horizontal-ish strands hang under gravity (the membrane read).
		# Border strands and verticals stay straight; endpoints are untouched, so the weld is exact.
		var span := a2.distance_to(b2)
		var horiz := absf((b2 - a2).normalized().x) if span > 1.0e-6 else 0.0
		var on_border := _on_rect_border(a2, w, h) and _on_rect_border(b2, w, h)
		var sag := minf(0.26, span * float(p.get("sag", 0.0))) * horiz
		if sag > 0.03 and int(ed["n"]) >= 2 and not on_border:
			var mid2 := (a2 + b2) * 0.5
			paths.append(PackedVector2Array([
				a2,
				a2.lerp(b2, 0.28) + Vector2(0, -sag * 0.8),
				mid2 + Vector2(0, -sag),
				a2.lerp(b2, 0.72) + Vector2(0, -sag * 0.8),
				b2,
			]))
		else:
			paths.append(PackedVector2Array([a2, b2]))
	return paths

static func _on_rect_border(pt: Vector2, w: float, h: float) -> bool:
	return pt.x < 0.02 or pt.x > w - 0.02 or pt.y < 0.02 or pt.y > h - 0.02

# One seed's Voronoi cell: the face rect clipped by the bisector half-plane against every other seed.
static func _voronoi_cell(seeds: Array, i: int, w: float, h: float) -> Array:
	var poly: Array = [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
	var si := seeds[i] as Vector2
	for j in range(seeds.size()):
		if j == i:
			continue
		var sj := seeds[j] as Vector2
		var mid := (si + sj) * 0.5
		var dir := sj - si
		if dir.length_squared() < 1.0e-10:
			continue
		poly = _clip_halfplane(poly, mid, dir)
		if poly.size() < 3:
			return []
	return poly

# Sutherland-Hodgman clip: keep the side where (p - mid) . dir <= 0 (closer to seed i).
static func _clip_halfplane(poly: Array, mid: Vector2, dir: Vector2) -> Array:
	var out: Array = []
	var m := poly.size()
	for k in range(m):
		var a := poly[k] as Vector2
		var b := poly[(k + 1) % m] as Vector2
		var da := (a - mid).dot(dir)
		var db := (b - mid).dot(dir)
		if da <= 0.0:
			out.append(a)
			if db > 0.0:
				out.append(a.lerp(b, da / (da - db)))
		elif db <= 0.0:
			out.append(a.lerp(b, da / (da - db)))
	return out

# FAR LOD: rasterize the SAME web into an RGBA texture (alpha background) — at distance the
# decoration IS this texture on a flat quad. Same paths, same params -> the two LODs always agree.
static func _bake_web_texture(paths: Array, w: float, h: float, px_w: int, rib_r: float, col: Color) -> ImageTexture:
	var px_h := maxi(8, int(round(float(px_w) * h / maxf(w, 0.01))))
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var sx := float(px_w) / w
	var sy := float(px_h) / h
	var rad := maxi(1, int(round(rib_r * sx)))
	for pathv in paths:
		var pts := pathv as PackedVector2Array
		for s in range(pts.size() - 1):
			var a := pts[s]
			var b := pts[s + 1]
			var steps := maxi(2, int(a.distance_to(b) * sx))
			for t in range(steps + 1):
				var q := a.lerp(b, float(t) / float(steps))
				var cx := int(round(q.x * sx))
				var cy := px_h - 1 - int(round(q.y * sy))   # face y-up -> image y-down
				for oy in range(-rad, rad + 1):
					for ox in range(-rad, rad + 1):
						if ox * ox + oy * oy > rad * rad:
							continue
						var qx := cx + ox
						var qy := cy + oy
						if qx >= 0 and qx < px_w and qy >= 0 and qy < px_h:
							img.set_pixel(qx, qy, col)
	return ImageTexture.create_from_image(img)

# ============================================================================================
# S_A / S_B honeyframe — the director's corner-cut construction (the "Welcombe" setting), verbatim:
# subdivide the face into a grid; per grid VERTEX pick a point at `cut` (<=50%) along each outgoing
# edge; connect those points AROUND the vertex (S_A) and ROUND the S_A curves so they cut TOWARD the
# vertex (concave — the organic, load-bearing junction); the remaining straight runs BETWEEN adjacent
# cut points along the edges are S_B. Every grid cell becomes a rounded opening. The whole network is
# fused watertight by LatticeGraph (S_A+S_B endpoints weld into degree-3 dome hubs).
# ============================================================================================
static func _honeyframe_face_sasb(f: Dictionary, p: Dictionary, frame_st: SurfaceTool, glass_st: SurfaceTool) -> int:
	var w: float = f["w"]
	var h: float = f["h"]
	var cols := int(max(1, round(w / float(p["cell_size"]))))
	var rows := int(max(1, round(h / (float(p["cell_size"]) * float(p["cell_aspect"])))))
	var c: Vector3 = f["c"]
	var u: Vector3 = (f["u"] as Vector3).normalized()
	var n: Vector3 = (f["n"] as Vector3).normalized()
	var origin := c - u * (w * 0.5) + Vector3(0, -h * 0.5, 0)   # face bottom-left; lattice y = world up
	var jitter := float(p["jitter"])
	var cut := clampf(float(p["cut"]), 0.05, 0.5)
	var pinch := clampf(float(p["pinch"]), 0.0, 1.0)
	var reserved: Array = p.get("reserved", [])
	var base_pane: Color = p["pane_color"]
	var rib_r := float(p["rib_radius"])
	var size_var := clampf(float(p.get("size_variance", 0.0)), 0.0, 0.8)
	var merge_chance := clampf(float(p.get("merge_chance", 0.0)), 0.0, 0.45)
	var cut_var := clampf(float(p.get("cut_variance", 0.0)), 0.0, 0.9)
	var fkey := (n.x * 3.7 + n.z * 9.1) * 17.0
	# 1. the SUBDIVIDED mesh — IRREGULAR on purpose (the plate's cells differ in size and shape):
	# varied grid-line spacing + jittered interior vertices. Inset by one rib radius so border ribs
	# sit ON the face.
	var xs := _varied_axis(cols, rib_r, w - 2.0 * rib_r, fkey + 3.0, size_var)
	var ys := _varied_axis(rows, rib_r, h - 2.0 * rib_r, fkey + 7.0, size_var)
	var jbase := minf((w - 2.0 * rib_r) / float(cols), (h - 2.0 * rib_r) / float(rows))
	var vp: Array = []
	for i in range(cols + 1):
		var col_arr: Array = []
		for j in range(rows + 1):
			var pos := Vector2(float(xs[i]), float(ys[j]))
			if i > 0 and i < cols and j > 0 and j < rows:
				pos.x += (_h01(fkey + float(i) * 12.9 + float(j) * 7.3) - 0.5) * jitter * jbase
				pos.y += (_h01(fkey + float(i) * 5.1 + float(j) * 3.3 + 50.0) - 0.5) * jitter * jbase
			col_arr.append(pos)
		vp.append(col_arr)
	# 1b. CELL MERGING: an interior wall may dissolve, fusing its two cells into one bigger blob
	# (capped at PAIRS so no vertex loses more than two edges). `merged`: cell index -> partner.
	var merged: Dictionary = {}
	var dropped_h: Dictionary = {}   # "i:j" = horizontal edge (vp[i][j] -> vp[i+1][j]), j in 1..rows-1
	var dropped_v: Dictionary = {}   # "i:j" = vertical edge (vp[i][j] -> vp[i][j+1]), i in 1..cols-1
	for i in range(cols):
		for j in range(1, rows):
			var ca := i * rows + (j - 1)
			var cb := i * rows + j
			if not merged.has(ca) and not merged.has(cb) and _h01(fkey + float(i) * 17.3 + float(j) * 29.1 + 100.0) < merge_chance:
				merged[ca] = cb
				merged[cb] = ca
				dropped_h["%d:%d" % [i, j]] = true
	for i2 in range(1, cols):
		for j2 in range(rows):
			var ca2 := (i2 - 1) * rows + j2
			var cb2 := i2 * rows + j2
			if not merged.has(ca2) and not merged.has(cb2) and _h01(fkey + float(i2) * 23.9 + float(j2) * 11.3 + 300.0) < merge_chance:
				merged[ca2] = cb2
				merged[cb2] = ca2
				dropped_v["%d:%d" % [i2, j2]] = true
	# 2-3. cut points along each SURVIVING edge away from each vertex -> S_B spans between them,
	# and a per-vertex registry of its cut points (for the S_A ring). The cut fraction varies per
	# vertex, so junction pinches differ across the facade.
	var paths: Array = []
	var vpts: Dictionary = {}
	# An edge in a door clearance is dropped HERE, before emission — the vertex registry then only
	# ever sees surviving edges, so the S_A ring adapts and orphaned connector curls are impossible
	# (a post-filter on finished paths stranded S_A arcs whose S_B partner died).
	for j3 in range(rows + 1):
		for i3 in range(cols):
			if j3 > 0 and j3 < rows and dropped_h.has("%d:%d" % [i3, j3]):
				continue   # this wall dissolved — its two cells are one blob
			var a: Vector2 = (vp[i3] as Array)[j3]
			var b: Vector2 = (vp[i3 + 1] as Array)[j3]
			if _seg_reserved_face(a, b, w, n, reserved):
				continue
			var pa := a.lerp(b, _sasb_cut(cut, cut_var, fkey, i3, j3))
			var pb := a.lerp(b, 1.0 - _sasb_cut(cut, cut_var, fkey, i3 + 1, j3))
			paths.append(PackedVector2Array([pa, pb]))
			_sasb_reg(vpts, i3, j3, pa, a)
			_sasb_reg(vpts, i3 + 1, j3, pb, b)
	for i4 in range(cols + 1):
		for j4 in range(rows):
			if i4 > 0 and i4 < cols and dropped_v.has("%d:%d" % [i4, j4]):
				continue
			var a2: Vector2 = (vp[i4] as Array)[j4]
			var b2: Vector2 = (vp[i4] as Array)[j4 + 1]
			if _seg_reserved_face(a2, b2, w, n, reserved):
				continue
			var pa2 := a2.lerp(b2, _sasb_cut(cut, cut_var, fkey, i4, j4))
			var pb2 := a2.lerp(b2, 1.0 - _sasb_cut(cut, cut_var, fkey, i4, j4 + 1))
			paths.append(PackedVector2Array([pa2, pb2]))
			_sasb_reg(vpts, i4, j4, pa2, a2)
			_sasb_reg(vpts, i4, j4 + 1, pb2, b2)
	# 4+6. S_A connectors around each vertex, ROUNDED toward the vertex (concave corner cuts)
	for i3 in range(cols + 1):
		for j3 in range(rows + 1):
			var lst: Array = vpts.get("%d:%d" % [i3, j3], [])
			if lst.size() < 2:
				continue
			lst.sort_custom(func(x, y) -> bool: return float((x as Dictionary)["ang"]) < float((y as Dictionary)["ang"]))
			var vtx: Vector2 = (vp[i3] as Array)[j3]
			var m := lst.size()
			var conns := m if m > 2 else 1
			for k in range(conns):
				var pd_a := lst[k] as Dictionary
				var pd_b := lst[(k + 1) % m] as Dictionary
				var gap := float(pd_b["ang"]) - float(pd_a["ang"])
				if gap <= 0.0:
					gap += TAU
				var pa3 := pd_a["p"] as Vector2
				var pb3 := pd_b["p"] as Vector2
				if gap > 2.6:
					paths.append(PackedVector2Array([pa3, pb3]))   # wide gap (face border run): straight
				else:
					paths.append(_concave_arc(pa3, pb3, vtx, pinch, 5))
	var graph: Dictionary = LatticeGraph.build(paths, 0.01)
	frame_st.set_color(Color(0.9, 0.87, 0.78))
	LatticeGraph.mesh(frame_st, graph, LatticeGraph.plane_surface(origin, u, Vector3(0, 1, 0)), rib_r, int(p["rib_sides"]))
	# glass: one lit pane per REGION (a merged pair reads as one big blob opening)
	var pane := float(p["pane"])
	var cells := 0
	for i5 in range(cols):
		for j5 in range(rows):
			var cidx := i5 * rows + j5
			if merged.has(cidx) and int(merged[cidx]) < cidx:
				continue   # the region is emitted from its lower-index cell
			var region_cells: Array = [Vector2i(i5, j5)]
			if merged.has(cidx):
				var pidx := int(merged[cidx])
				region_cells.append(Vector2i(int(pidx / float(rows)), pidx % rows))
			var rmin := Vector2(1.0e9, 1.0e9)
			var rmax := Vector2(-1.0e9, -1.0e9)
			for rc in region_cells:
				var ci := (rc as Vector2i).x
				var cj := (rc as Vector2i).y
				for corner in [(vp[ci] as Array)[cj], (vp[ci + 1] as Array)[cj], (vp[ci] as Array)[cj + 1], (vp[ci + 1] as Array)[cj + 1]]:
					rmin = Vector2(minf(rmin.x, (corner as Vector2).x), minf(rmin.y, (corner as Vector2).y))
					rmax = Vector2(maxf(rmax.x, (corner as Vector2).x), maxf(rmax.y, (corner as Vector2).y))
			var cen := (rmin + rmax) * 0.5
			var hwp := maxf(0.06, (rmax.x - rmin.x) * 0.5 - rib_r * 0.9)
			var hhp := maxf(0.06, (rmax.y - rmin.y) * 0.5 - rib_r * 0.9)
			# a pane is dropped when the PANE ITSELF overlaps a door clearance (testing the full region
			# rect also killed the lit cells that merely FLANK the entrance — the plate keeps those)
			if _rect_reserved_face(cen - Vector2(hwp, hhp), cen + Vector2(hwp, hhp), w, n, reserved):
				continue
			var rr := minf(hwp, hhp) * 0.7
			var key := fkey + float(i5) * 31.7 + float(j5) * 13.9
			_glass_fan_plane(origin, u, Vector3(0, 1, 0), n, cen, _rounded_rect(hwp, hhp, rr, 3), pane, _pane_color(base_pane, key), glass_st)
			cells += 1
	return cells

# Grid-line boundaries with hash-varied spacing: n spans over [start, start+span], each a different
# width — the plate's rows/columns of visibly different size.
static func _varied_axis(n: int, start: float, span: float, key: float, variance: float) -> Array:
	var weights: Array = []
	var total := 0.0
	for i in range(n):
		var wgt := 1.0 + (_h01(key + float(i) * 13.7) - 0.5) * 2.0 * variance
		weights.append(wgt)
		total += wgt
	var out: Array = [start]
	var acc := start
	for i2 in range(n):
		acc += span * (float(weights[i2]) / total)
		out.append(acc)
	return out

# The S_A cut fraction at one vertex — varied per vertex so the junction pinches differ.
static func _sasb_cut(cut: float, cut_var: float, fkey: float, i: int, j: int) -> float:
	return clampf(cut * (1.0 + (_h01(fkey + float(i) * 31.1 + float(j) * 8.7 + 200.0) - 0.5) * cut_var), 0.08, 0.5)

static func _sasb_reg(vpts: Dictionary, i: int, j: int, pt: Vector2, vtx: Vector2) -> void:
	var key := "%d:%d" % [i, j]
	if not vpts.has(key):
		vpts[key] = []
	(vpts[key] as Array).append({"p": pt, "ang": atan2(pt.y - vtx.y, pt.x - vtx.x)})

# Quadratic bezier from `a` to `b` whose control point is pulled toward the vertex — the S_A rounding
# that "cuts toward the vertex" (concave, pinching in).
static func _concave_arc(a: Vector2, b: Vector2, vtx: Vector2, pinch: float, seg: int) -> PackedVector2Array:
	var ctrl := ((a + b) * 0.5).lerp(vtx, pinch)
	var out := PackedVector2Array()
	for s in range(seg + 1):
		var t := float(s) / float(seg)
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out

# Does a face-local RECT overlap a reserved door region on this face? (Same clearance the ribs use.)
static func _rect_reserved_face(rmin: Vector2, rmax: Vector2, w: float, face_n: Vector3, reserved: Array) -> bool:
	for reg in reserved:
		var rd := reg as Dictionary
		if bool(rd.get("cyl", true)):
			continue
		if (rd["n"] as Vector3).dot(face_n) < 0.9:
			continue
		var cx := w * 0.5 + float(rd["x_center"])
		var hw := float(rd["half_w"])
		if rmin.y < float(rd["y_top"]) and rmax.x > cx - hw and rmin.x < cx + hw:
			return true
	return false

# Does a face-local grid EDGE (sampled) cross a reserved door region on this face? Decided BEFORE
# emission so the S_A vertex registry only ever sees surviving edges.
static func _seg_reserved_face(a: Vector2, b: Vector2, w: float, face_n: Vector3, reserved: Array) -> bool:
	for reg in reserved:
		var rd := reg as Dictionary
		if bool(rd.get("cyl", true)):
			continue
		if (rd["n"] as Vector3).dot(face_n) < 0.9:
			continue
		var cx := w * 0.5 + float(rd["x_center"])
		var hw := float(rd["half_w"])
		var yt := float(rd["y_top"])
		for s in range(7):
			var pt := a.lerp(b, float(s) / 6.0)
			if pt.y < yt and absf(pt.x - cx) < hw:
				return true
	return false

# Glass fan on a box face with self-correcting winding (never faces into the wall regardless of the
# outline's authored orientation). `cen` + `outline` are face-local; colour = the pane's own light.
static func _glass_fan_plane(origin: Vector3, u: Vector3, v: Vector3, n: Vector3, cen: Vector2, outline: PackedVector2Array, dn: float, col: Color, st: SurfaceTool) -> void:
	st.set_color(col)
	var mid := origin + u * cen.x + v * cen.y + n * dn
	var count := outline.size()
	for i in range(count):
		var a2 := cen + outline[i]
		var b2 := cen + outline[(i + 1) % count]
		var a3 := origin + u * a2.x + v * a2.y + n * dn
		var b3 := origin + u * b2.x + v * b2.y + n * dn
		LatticeGraph._face(st, mid, a3, b3, n)

static func _honeyframe_face(f: Dictionary, p: Dictionary, frame_st: SurfaceTool, glass_st: SurfaceTool) -> int:
	var w: float = f["w"]
	var h: float = f["h"]
	var cols := int(max(1, round(w / float(p["cell_size"]))))
	var rows := int(max(1, round(h / (float(p["cell_size"]) * float(p["cell_aspect"])))))
	var cw := w / float(cols)
	var ch := h / float(rows)
	var c: Vector3 = f["c"]
	var u: Vector3 = (f["u"] as Vector3).normalized()
	var n: Vector3 = (f["n"] as Vector3).normalized()
	var v := n.cross(u).normalized()   # in-plane "up" (points +y for a vertical face)
	var fw: float = p["frame_width"]
	var fd: float = p["frame_depth"]
	var back: float = -float(p["back_bite"])
	var pane: float = p["pane"]
	var base_pane: Color = p["pane_color"]
	var seg: int = int(p["arc_seg"])
	var bevel: float = p["bevel"]
	var jitter: float = p["jitter"]
	# Window (inner) half-size = cell half-size minus the frame; the frame keeps a CONSTANT width by
	# offsetting the outer outline out by `fw`, so cell_half == window_half + fw.
	var win_hw := maxf(0.05, cw * 0.5 - fw)
	var win_hh := maxf(0.05, ch * 0.5 - fw)
	var r_in := minf(win_hw, win_hh) * clampf(float(p["corner_round"]) * 2.0, 0.0, 1.0)
	# The outer outline is the FULL cell rectangle (sharp corners), so the frame tiles the whole face
	# with no gaps and the strut fans from each sharp grid-vertex corner out to the rounded window arc
	# — that fan IS the "round toward the vertex" junction (concave window-arc sides, solid crossings).
	var outer := _rounded_rect(win_hw + fw, win_hh + fw, 0.0, seg)
	for row in range(rows):
		for col in range(cols):
			var cu := -w * 0.5 + (col + 0.5) * cw
			var cv := -h * 0.5 + (row + 0.5) * ch
			if _cell_reserved_box(cu, cv, n, h, p.get("reserved", [])):
				continue   # keep this cell clear for a door
			var center := c + u * cu + v * cv
			var key := absf(center.x) * 12.9 + absf(center.y) * 7.3 + absf(center.z) * 3.1
			# Per-cell irregularity: nudge + scale the WINDOW inside its cell (the frame band thickens
			# unevenly around it). The outer cell rect stays put, so the lattice still tiles seamlessly.
			var js := 1.0 + (_h01(key * 6.1) - 0.5) * jitter
			var jx := (_h01(key * 2.3) - 0.5) * jitter * cw
			var jy := (_h01(key * 4.7) - 0.5) * jitter * ch
			var inner := _rounded_rect(win_hw * js, win_hh * js, r_in * js, seg)
			var off := Vector2(jx, jy)
			var inner_j := PackedVector2Array()
			for pt in inner:
				inner_j.append(pt + off)
			_emit_frame_ring(center, u, v, n, outer, inner_j, fd, back, bevel, frame_st)
			_emit_glass(center, u, v, n, inner_j, pane, _pane_color(base_pane, key), glass_st)
	return rows * cols

# JUNCTION honeyframe for one face: a grid of half-round STRUTS (a line per column + per row) with a
# rib_junction hub at every grid crossing (the organic "melting junction"), and a lit rounded window in
# each cell. This is the algorithm-3 way — the struts fuse at crossings instead of a per-cell inset.
static func _honeyframe_face_junction(f: Dictionary, p: Dictionary, frame_st: SurfaceTool, glass_st: SurfaceTool) -> int:
	var w: float = f["w"]
	var h: float = f["h"]
	var cols := int(max(1, round(w / float(p["cell_size"]))))
	var rows := int(max(1, round(h / (float(p["cell_size"]) * float(p["cell_aspect"])))))
	var cw := w / float(cols)
	var ch := h / float(rows)
	var c: Vector3 = f["c"]
	var u: Vector3 = (f["u"] as Vector3).normalized()
	var n: Vector3 = (f["n"] as Vector3).normalized()
	var v := n.cross(u).normalized()
	var radius := float(p["frame_width"]) * 0.72   # thicker so the struts read solid, not wiry
	# strut centre-lines in face-centred (x,y), INSET by `radius` from the edges so the half-round width
	# stays on the face (nothing pokes past the wall / below the base). Vertical per column, horiz per row.
	var mx := w * 0.5 - radius
	var my := h * 0.5 - radius
	var paths: Array = []
	for col in range(cols + 1):
		var x := clampf(-w * 0.5 + col * cw, -mx, mx)
		paths.append(PackedVector2Array([Vector2(x, -my), Vector2(x, my)]))
	for row in range(rows + 1):
		var y := clampf(-h * 0.5 + row * ch, -my, my)
		paths.append(PackedVector2Array([Vector2(-mx, y), Vector2(mx, y)]))
	_build_ribs_junction_planar(frame_st, paths, c, u, v, radius, 5)
	# a lit rounded window inset into each cell (kept smaller than the cell so the struts dominate)
	var base_pane: Color = p["pane_color"]
	var win_hw := maxf(0.04, cw * 0.5 - radius * 1.85)
	var win_hh := maxf(0.04, ch * 0.5 - radius * 1.85)
	for row in range(rows):
		for col in range(cols):
			var cx := -w * 0.5 + (float(col) + 0.5) * cw
			var cy := -h * 0.5 + (float(row) + 0.5) * ch
			var key := absf(c.x + cx) * 12.9 + absf(c.y + cy) * 7.3 + absf(c.z) * 3.1
			var outline := _rounded_rect(win_hw, win_hh, minf(win_hw, win_hh) * 0.4, 3)
			var oj := PackedVector2Array()
			for pt in outline:
				oj.append(pt + Vector2(cx, cy))
			_emit_glass(c, u, v, n, oj, float(p["pane"]), _pane_color(base_pane, key), glass_st)
	return rows * cols

# A rounded rectangle outline in the (x,y) face plane, wound CCW. 4 quarter-arcs of radius r.
static func _rounded_rect(hw: float, hh: float, r: float, seg: int) -> PackedVector2Array:
	r = minf(r, minf(hw, hh))
	var pts := PackedVector2Array()
	var centers := [
		Vector2(hw - r, hh - r), Vector2(-(hw - r), hh - r),
		Vector2(-(hw - r), -(hh - r)), Vector2(hw - r, -(hh - r)),
	]
	var start := [0.0, PI * 0.5, PI, PI * 1.5]
	for corner in range(4):
		for s in range(seg + 1):
			var a: float = start[corner] + (PI * 0.5) * float(s) / float(seg)
			pts.append(centers[corner] + Vector2(cos(a), sin(a)) * r)
	return pts

static func _p3(center: Vector3, u: Vector3, v: Vector3, n: Vector3, pt: Vector2, dn: float) -> Vector3:
	return center + u * pt.x + v * pt.y + n * dn

# A CLOSED frame-border prism between the outer (cell) and inner (window) outlines. The top is a
# MOULDING: the rims sit at `top`, a mid crest rises `bevel` higher, so the cross-section reads
# outer(low) -> crest(high) -> inner(low). Walls drop to `back` (into the wall); the bottom annulus
# closes it. Inner wall is the window REVEAL. Watertight — no open underside.
static func _emit_frame_ring(center: Vector3, u: Vector3, v: Vector3, n: Vector3,
		outer: PackedVector2Array, inner: PackedVector2Array, top: float, back: float, bevel: float, st: SurfaceTool) -> void:
	var count := outer.size()
	for i in range(count):
		var j := (i + 1) % count
		var ot_i := _p3(center, u, v, n, outer[i], top)
		var ot_j := _p3(center, u, v, n, outer[j], top)
		var it_i := _p3(center, u, v, n, inner[i], top)
		var it_j := _p3(center, u, v, n, inner[j], top)
		var mt_i := _p3(center, u, v, n, outer[i].lerp(inner[i], 0.5), top + bevel)
		var mt_j := _p3(center, u, v, n, outer[j].lerp(inner[j], 0.5), top + bevel)
		var ob_i := _p3(center, u, v, n, outer[i], back)
		var ob_j := _p3(center, u, v, n, outer[j], back)
		var ib_i := _p3(center, u, v, n, inner[i], back)
		var ib_j := _p3(center, u, v, n, inner[j], back)
		# top moulding: outer rim -> mid crest -> inner rim (faces +n)
		_tri(st, ot_i, ot_j, mt_j)
		_tri(st, ot_i, mt_j, mt_i)
		_tri(st, mt_i, mt_j, it_j)
		_tri(st, mt_i, it_j, it_i)
		# bottom annulus (faces -n, against the wall)
		_tri(st, ob_i, ib_j, ob_j)
		_tri(st, ob_i, ib_i, ib_j)
		# outer wall (faces outward)
		_tri(st, ob_i, ot_i, ot_j)
		_tri(st, ob_i, ot_j, ob_j)
		# inner wall = the window reveal (faces inward, toward the window)
		_tri(st, it_i, it_j, ib_j)
		_tri(st, it_i, ib_j, ib_i)

# The lit window pane: a fan over the inner outline at `depth`, wound to face OUTWARD (+n) so it needs
# no double-siding. `col` is the pane's own light (per-pane) written as vertex COLOR for the window shader.
static func _emit_glass(center: Vector3, u: Vector3, v: Vector3, n: Vector3,
		inner: PackedVector2Array, depth: float, col: Color, st: SurfaceTool) -> void:
	st.set_color(col)
	var count := inner.size()
	var mid := _p3(center, u, v, n, Vector2.ZERO, depth)
	for i in range(count):
		var j := (i + 1) % count
		_tri(st, mid, _p3(center, u, v, n, inner[j], depth), _p3(center, u, v, n, inner[i], depth))

# Deterministic hash (Blender-parity) + per-pane window light: mostly lit at varied brightness, a few
# unlit (dark), an occasional cool or extra-warm window — so a facade reads as many individual lives.
static func _h01(nv: float) -> float:
	return fmod(absf(sin(nv * 127.13) * 43758.5453), 1.0)

static func _pane_color(base: Color, key: float) -> Color:
	if _h01(key * 1.7) < 0.16:
		return Color(0.03, 0.03, 0.035)   # an unlit window
	var bri := 0.5 + 0.5 * _h01(key * 3.3)
	var c := Color(base.r * bri, base.g * bri, base.b * bri)
	var t := _h01(key * 5.1)
	if t < 0.26:
		c = c.lerp(Color(0.55, 0.70, 1.0) * bri, 0.4)   # a cool-lit window
	elif t > 0.82:
		c = c.lerp(Color(1.0, 0.50, 0.20) * bri, 0.4)   # an extra-warm window
	return c

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

# A closed axis-aligned box (12 tris), used for corner posts.
static func _emit_box(st: SurfaceTool, center: Vector3, half: Vector3) -> void:
	var c := center
	var e := half
	var vtx := [
		c + Vector3(-e.x, -e.y, -e.z), c + Vector3(e.x, -e.y, -e.z),
		c + Vector3(e.x, -e.y, e.z), c + Vector3(-e.x, -e.y, e.z),
		c + Vector3(-e.x, e.y, -e.z), c + Vector3(e.x, e.y, -e.z),
		c + Vector3(e.x, e.y, e.z), c + Vector3(-e.x, e.y, e.z),
	]
	var faces := [
		[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1],
		[1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0],
	]
	for fq in faces:
		_tri(st, vtx[fq[0]], vtx[fq[2]], vtx[fq[1]])
		_tri(st, vtx[fq[0]], vtx[fq[3]], vtx[fq[2]])

# ============================================================================================
# PIPES — edge/face-descent tubes that drape down a building (works on box faces AND the cylinder).
# Per the spec: a density -> pipe count; each pipe walks DOWN from the top with curve-sampled steps
# and a probability of jogging diagonally to a side lane; occasionally a shorter follower runs
# alongside it. Deterministic (SeededRng), low-poly swept tubes.
# ============================================================================================

const PIPE_DEFAULTS := {
	"density": 0.22,        # pipe runs per metre of surface width -> target count
	"lane_w": 0.45,         # lateral lane spacing for a diagonal jog
	"step_min": 0.5,        # descent step per move (the CURVE_PARAMETER, sampled)
	"step_max": 1.4,
	"diag_prob": 0.35,      # chance a step jogs diagonally to a side lane rather than straight down
	"radius_min": 0.05,     # per-pipe gauge range (mixes fat risers + thin conduit)
	"radius_max": 0.11,
	"single_frac": 0.55,    # fraction of runs that are a SINGLE pipe (the rest bundle 2-3 together)
	"bundle_min": 1,        # how many pipes track together in a run
	"bundle_max": 3,
	"bundle_gap": 0.16,     # lateral spacing between bundled pipes
	"edge_bias": 0.5,       # chance a run hugs a vertical edge instead of a random face lane
	"sag": 0.22,            # catenary belly per unit of HORIZONTAL run (near-none on vertical runs)
	"sag_segs": 4,          # subdivisions per segment for the sag curve
	"coupling_every": 1.3,  # metres of run between banded couplings
	"coupling_scale": 1.5,  # coupling radius as a multiple of the pipe radius
	"coupling_len": 0.11,
	"bracket_every": 2.2,   # metres between wall standoff brackets
	"sides": 6,             # tube cross-section segments (low-poly)
	"standoff": 0.055,      # how far the pipe floats off the surface
	"base_color": Color(0.28, 0.31, 0.29),   # weathered metal
	"rust_color": Color(0.34, 0.17, 0.10),   # rust brown — pools low + bands along the run
}

## Build the pipe lattice for a base shape (`spec` carries shape/size or radius/height). One ArrayMesh.
static func pipes(spec: Dictionary, seed_value: int, overrides: Dictionary = {}) -> ArrayMesh:
	var p := PIPE_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var rng := SeededRng.new(seed_value)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surfaces: Array = []
	if str(spec.get("shape", "box")) == "cylinder" or (spec.has("radius") and not spec.has("size")):
		# drum-based massings (incl. composites); an r_at override (the massing profile) makes the
		# drapes follow the REAL silhouette so pipes touch lobes/tiers/domes instead of floating
		var r := float(spec.get("radius", 2.0))
		var surf := {"kind": "cyl", "r": r, "h": float(spec.get("height", 5.0)), "w": TAU * r}
		if overrides.has("r_at") and overrides["r_at"] is Callable:
			surf["r_at"] = overrides["r_at"]
		surfaces.append(surf)
	else:
		for f in _box_vertical_faces(spec.get("size", Vector3(4, 6, 4))):
			var fd := f as Dictionary
			fd["kind"] = "face"
			surfaces.append(fd)
	for surf in surfaces:
		_pipes_surface(surf, p, rng, st)
	st.generate_normals()
	return st.commit()

static func _pipes_surface(surf: Dictionary, p: Dictionary, rng: SeededRng, st: SurfaceTool) -> void:
	var w: float = surf["w"]
	var h: float = surf["h"]
	var num := int(max(1, round(float(p["density"]) * w)))
	var lane: float = p["lane_w"]
	for _i in range(num):
		# Edge-hugging: half the runs start near a vertical edge/recess (as in the plate) instead of
		# scattering across a flat face centre.
		var x0: float
		if float(rng.call("randf")) < float(p["edge_bias"]):
			var near_left := float(rng.call("randf")) < 0.5
			x0 = float(rng.call("randf_range", 0.08, lane)) if near_left else w - float(rng.call("randf_range", 0.08, lane))
		else:
			x0 = float(rng.call("randf_range", 0.0, w))
		var lead := _subdivide_sag(_walk_pipe(x0, w, h, p, rng), float(p["sag"]), int(p["sag_segs"]))
		# Most runs are a SINGLE pipe; the rest bundle 2-3 mixed-gauge runs together.
		var bundle := 1
		if float(rng.call("randf")) >= float(p["single_frac"]):
			bundle = int(rng.call("randi_range", maxi(2, int(p["bundle_min"])), int(p["bundle_max"])))
		for b in range(bundle):
			var pr := float(rng.call("randf_range", float(p["radius_min"]), float(p["radius_max"])))
			var off := 0.0 if b == 0 else float(ceili(b / 2.0)) * float(p["bundle_gap"]) * (1.0 if b % 2 == 1 else -1.0)
			var path := lead if is_zero_approx(off) else _offset_path(lead, off, w)
			_sweep_uv(path, surf, pr, int(p["sides"]), float(p["standoff"]), p, st)

# Insert a downward catenary belly into each segment. +v is down (see _surf_map), so the belly ADDS to
# v, scaled by the segment's HORIZONTAL run — vertical runs get ~no sag, sideways spans droop.
static func _subdivide_sag(path: PackedVector2Array, sag: float, segs: int) -> PackedVector2Array:
	if path.size() < 2 or segs < 1:
		return path
	var out := PackedVector2Array()
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var belly := sag * absf(b.x - a.x) * 4.0
		for s in range(segs):
			var t := float(s) / float(segs)
			var pt := a.lerp(b, t)
			pt.y += belly * t * (1.0 - t)
			out.append(pt)
	out.append(path[path.size() - 1])
	return out

static func _offset_path(path: PackedVector2Array, off: float, w: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pt in path:
		out.append(Vector2(clampf(pt.x + off, 0.0, w), pt.y))
	return out

static func _walk_pipe(x0: float, w: float, h: float, p: Dictionary, rng: SeededRng) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := clampf(x0, 0.0, w)
	var v := 0.0
	var last_jog := 0.0   # sign of the previous horizontal move; a straight step resets it to 0
	pts.append(Vector2(x, v))
	var guard := 0
	while v < h and guard < 240:
		guard += 1
		v = minf(h, v + float(rng.call("randf_range", float(p["step_min"]), float(p["step_max"]))))
		if float(rng.call("randf")) < float(p["diag_prob"]):
			# Keep drifting the SAME way on back-to-back diagonals (never reverse left<->right without a
			# straight step between); only a straight step frees the pipe to pick a fresh side.
			var s: float = last_jog if last_jog != 0.0 else (-1.0 if float(rng.call("randf")) < 0.5 else 1.0)
			var nx := clampf(x + s * float(p["lane_w"]), 0.0, w)
			if is_equal_approx(nx, x):   # blocked by the wall — reset so the next jog can go the other way
				last_jog = 0.0
			else:
				x = nx
				last_jog = s
		else:
			last_jog = 0.0
		pts.append(Vector2(x, v))
	return pts

static func _sweep_uv(path_uv: PackedVector2Array, surf: Dictionary, radius: float, sides: int, standoff: float, p: Dictionary, st: SurfaceTool) -> void:
	if path_uv.size() < 2:
		return
	var pts3: Array = []
	var cols: Array = []
	var base: Color = p["base_color"]
	var rust: Color = p["rust_color"]
	var h: float = surf["h"]
	for uv in path_uv:
		pts3.append(_surf_map(surf, uv, standoff + radius))
		# Rustier low on the run + a per-point band; the pipe carries its own patina as vertex colour.
		var t := clampf((uv.y / h) * 0.6 + _h01(uv.x * 3.1 + uv.y * 7.7) * 0.4, 0.0, 1.0)
		cols.append(base.lerp(rust, t))
	_sweep_tube(pts3, radius, sides, cols, st)
	_emit_pipe_hardware(path_uv, surf, radius, standoff, sides, p, st)

# Banded couplings at intervals + thin standoff brackets pinning the pipe to the wall — the hardware
# that makes a tube read as plumbing.
static func _emit_pipe_hardware(path_uv: PackedVector2Array, surf: Dictionary, radius: float, standoff: float, sides: int, p: Dictionary, st: SurfaceTool) -> void:
	var acc_c := 0.0
	var acc_b := 0.0
	var ce: float = p["coupling_every"]
	var be: float = p["bracket_every"]
	var cr := radius * float(p["coupling_scale"])
	var clen: float = p["coupling_len"]
	var dk := Color(0.16, 0.11, 0.08)
	for i in range(1, path_uv.size()):
		var a := path_uv[i - 1]
		var b := path_uv[i]
		var seg := a.distance_to(b)
		acc_c += seg
		acc_b += seg
		var mid := (a + b) * 0.5
		if acc_c >= ce:
			acc_c = 0.0
			var pa := _surf_map(surf, a, standoff + radius)
			var pb := _surf_map(surf, b, standoff + radius)
			var dir := (pb - pa)
			if dir.length() > 1e-5:
				dir = dir.normalized()
				var c3 := _surf_map(surf, mid, standoff + radius)
				_sweep_tube([c3 - dir * clen * 0.5, c3 + dir * clen * 0.5], cr, sides, [dk, dk], st)
		if acc_b >= be:
			acc_b = 0.0
			_sweep_tube([_surf_map(surf, mid, 0.0), _surf_map(surf, mid, standoff + radius)], radius * 0.34, 4, [dk, dk], st)

static func _surf_map(surf: Dictionary, uv: Vector2, dn: float) -> Vector3:
	if str(surf["kind"]) == "cyl":
		var r: float = surf["r"]
		var a := uv.x / r                      # arc-length param stays on the NOMINAL radius
		var wy := float(surf["h"]) - uv.y
		var rw := r
		if surf.has("r_at"):
			rw = float((surf["r_at"] as Callable).call(wy))   # the massing profile: hug the real wall
		return Vector3((rw + dn) * cos(a), wy, (rw + dn) * sin(a))
	var center: Vector3 = surf["c"]
	var u: Vector3 = surf["u"]
	var n: Vector3 = surf["n"]
	var vax := n.cross(u)
	var uloc := uv.x - float(surf["w"]) * 0.5
	return center + u * uloc + vax * (float(surf["h"]) * 0.5 - uv.y) + n * dn

static func _sweep_tube(pts: Array, radius: float, sides: int, colors: Array, st: SurfaceTool) -> void:
	if pts.size() < 2:
		return
	var have_cols := colors.size() == pts.size()
	var end_col: Color = colors[0] if colors.size() > 0 else Color.WHITE
	var rings: Array = []
	for i in range(pts.size()):
		var dir: Vector3
		if i == 0:
			dir = (pts[1] as Vector3) - (pts[0] as Vector3)
		elif i == pts.size() - 1:
			dir = (pts[i] as Vector3) - (pts[i - 1] as Vector3)
		else:
			dir = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
		if dir.length() < 1e-5:
			dir = Vector3.DOWN
		dir = dir.normalized()
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.9:
			up = Vector3.RIGHT
		var right := dir.cross(up).normalized()
		var fwd := right.cross(dir).normalized()
		var ring: Array = []
		for s in range(sides):
			var ang := TAU * float(s) / float(sides)
			ring.append((pts[i] as Vector3) + (right * cos(ang) + fwd * sin(ang)) * radius)
		rings.append(ring)
	for i in range(rings.size() - 1):
		if have_cols:
			st.set_color(colors[i])
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(sides):
			var s2 := (s + 1) % sides
			_tri(st, r0[s], r0[s2], r1[s2])
			_tri(st, r0[s], r1[s2], r1[s])
	# End caps so the tube is a closed solid (no open bore), wound opposite at the two ends.
	var first: Array = rings[0]
	var last: Array = rings[rings.size() - 1]
	var p0: Vector3 = pts[0]
	var pn: Vector3 = pts[pts.size() - 1]
	st.set_color(colors[colors.size() - 1] if have_cols else end_col)
	for s in range(sides):
		var s2 := (s + 1) % sides
		_tri(st, p0, first[s2], first[s])
		_tri(st, pn, last[s], last[s2])

# ============================================================================================
# TRACERY — pointed-arch (lancet) window wall wrapped on a CYLINDER (Beacon Hill). A raised stone RIB
# lattice in front, lit glass panes behind (the glass "curtain"). Same frame-ring idea as honeyframe,
# but the cell outline is a lancet and the whole thing maps onto the drum.
# ============================================================================================

## The Beacon Hill facade is not a tiled lancet grid — it is ONE continuous flowing rib NETWORK
## (Art-Nouveau tracery). Per bay, top -> bottom: a big ARCH springs over a large gridded window;
## OVAL "eyes" sit in the spandrels between adjacent arches; the arch springs draw DOWN into inverted
## TEARDROPS at the bay boundaries; each teardrop's point continues as a vertical LINE (mullion) to the
## base. Three window classes nest in the negative space: LARGE (gridded, under the arch), THIN (a slit
## inside each teardrop AND flanking the large window under the arch), SMALL (under the teardrop point).
## Ribs are half-round bone mouldings swept along the flowing paths (reusing the tube sweep); windows
## are lit glass fans just proud of the drum, behind the ribs (the "glass curtain + tracery" two-layer).
const TRACERY_DEFAULTS := {
	"bays": 8,                # large windows around the drum (each bay: one tall window + its arches)
	"rib_radius": 0.08,       # rib crest radius — the plate's mouldings are FAT, not hairlines
	"rib_sides": 5,
	"pane": 0.012,            # glass just proud of the drum, sitting BEHIND the ribs
	"y_root": 0.03,           # mullion feet (fraction of body height)
	"y_base": 0.16,           # sill / bottom of the large windows — above the plinth
	"y_spring": 0.60,         # top of the large windows / spring of the inner (window) arch
	"y_inner": 0.74,          # inner (window) pointed-arch apex
	"y_outer_spring": 0.56,   # OUTER arch spring height ON the mullion (the arch grows out of it)
	"y_outer": 0.86,          # outer arch apex — the second, larger arch nesting over the window arch
	"large_w_frac": 0.62,     # large-window width / bay width — the windows dominate the facade
	"grid_cols": 4,           # gridded large-window sub-panes (fills the bay with bright glass)
	"grid_rows": 15,          # tall stack of lit panes
	"comma_frac": 0.055,      # size of the two comma / mouchette drops in the tympanum (fraction of body H)
	"flank_hw_frac": 0.085,   # flanking vesica half-width / bay width
	"flank_hh_frac": 0.15,    # flanking vesica half-height / body height (a shorter pointed oval)
	"body_frac": 0.88,        # main tracery zone; the rest up top is the domed crown band
	"crown_windows": 26,      # small arched windows around the domed crown
	"pane_color": Color(1.0, 0.74, 0.42),   # base window-light colour; per-pane brightness/tint varies off it
	"rib_color": Color(0.82, 0.78, 0.64),   # bone-cream ribs
}

## Build the tracery lattice for a drum of `radius`/`height`. Returns {frame, glass, cells}.
##
## GROUND-ZERO REBUILD (Fable): the rib network is now a CONNECTED planar graph meshed watertight by
## LatticeGraph — one flowing Art-Nouveau surface, per the plate. Per bay the paths CONNECT by
## construction: the mullion runs root -> body course; the sill and both arches T into it; the window
## jambs T into the sill and CHAIN through the inner arch into one continuous window rib; the two
## mouchette drops and the flanking vesicas are closed loops kissing the arches; the crown arches
## spring off the body course. Doors: a `reserved` bay keeps its mullions but drops everything else
## (and the course seam hides inside it).
static func tracery(radius: float, height: float, overrides: Dictionary = {}) -> Dictionary:
	var p := TRACERY_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var r := radius
	var circ := TAU * r
	var bays := int(p["bays"])
	var bw := circ / float(bays)
	var body_h := height * float(p["body_frac"])   # the main tracery zone; crown band sits above it
	var y_root := float(p["y_root"]) * body_h
	var yb := float(p["y_base"]) * body_h
	var ys := float(p["y_spring"]) * body_h
	var y_inner := float(p["y_inner"]) * body_h
	var ys2 := float(p["y_outer_spring"]) * body_h
	var y_outer := float(p["y_outer"]) * body_h
	var pane := float(p["pane"])
	var base_pane: Color = p["pane_color"]
	var flank_hw := float(p["flank_hw_frac"]) * bw
	var flank_hh := float(p["flank_hh_frac"]) * body_h
	var comma_sz := float(p["comma_frac"]) * body_h
	var rib_r := float(p["rib_radius"])
	var reserved: Array = p.get("reserved", [])
	# Bay grid aligned so bay b's CENTRE sits at theta = PI/2 + b*dtheta — the same centres the doors
	# snap to. A reserved region names its bay ("bay" from entrances); fall back to nearest-centre.
	var x_base := r * (PI * 0.5 - 0.5 * (TAU / float(bays)))   # bay 0's left mullion (arc-length)
	var res_bays: Dictionary = {}
	var door_clear_y := 0.0   # the tallest door clearance — the upper network must stay ABOVE it
	for reg in reserved:
		var rd := reg as Dictionary
		if not bool(rd.get("cyl", false)):
			continue
		door_clear_y = maxf(door_clear_y, float(rd.get("y_top", 0.0)))
		if rd.has("bay"):
			res_bays[int(rd["bay"])] = true
		else:
			res_bays[wrapi(int(round((float(rd["theta"]) - PI * 0.5) / (TAU / float(bays)))), 0, bays)] = true
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths: Array = []
	var cells := 0
	var hlw := float(p["large_w_frac"]) * bw * 0.5
	for b in range(bays):
		var x0 := x_base + float(b) * bw   # left bay boundary (arc-length) — the mullion axis
		var x1 := x0 + bw
		var xc := x0 + bw * 0.5            # bay centre — the large window / door axis
		# the mullion ALWAYS stands (it frames a door bay too): root -> body course
		paths.append(_line2(Vector2(x0, y_root), Vector2(x0, body_h), 8))
		var is_door := res_bays.has(b)
		# the UPPER network runs over a door bay too — but ONLY the parts that clear the door opening
		# (on a short tiered band the whole bay is door height; without the gate the arch/course/drops
		# float across the cut hole):
		if not is_door or ys2 > door_clear_y:
			paths.append(_arch_pts(x0, x1, ys2, y_outer, 14))        # outer arch, springs off the mullions
		if not is_door or body_h > door_clear_y:
			paths.append(_line2(Vector2(x0, body_h), Vector2(x1, body_h), 6))   # body course (the dome ring)
		for sgn in [-1.0, 1.0]:
			# mouchette DROPS flank the inner apex in the OPEN tympanum, mirrored, leaning apart.
			# Sized/placed to stay CLEAR of both arches (an overlapping drop pokes through the outer
			# arch — the red-shell test catches the exposed interior).
			var dcx := xc + float(sgn) * hlw * 0.55
			var dcy := y_inner * 0.48 + y_outer * 0.52 - comma_sz * 0.15
			if is_door and dcy - comma_sz < door_clear_y:
				continue
			paths.append(_drop_loop(dcx, dcy, comma_sz * 0.85, float(sgn)))
			_glass_fan_cyl(dcx / r, dcy, r, _drop_loop(0.0, 0.0, comma_sz * 0.62, float(sgn)), pane, _pane_color(base_pane, dcx * 5.3 + 11.0), glass_st)
			cells += 1
		if is_door:
			continue   # this bay holds a door — no sill / window / vesicas at door height
		# sill across the bay — T's into both mullions
		paths.append(_line2(Vector2(x0, yb), Vector2(x1, yb), 6))
		# window frame: jambs T into the sill, then CHAIN through the inner arch (one flowing rib)
		paths.append(_line2(Vector2(xc - hlw, yb), Vector2(xc - hlw, ys), 4))
		paths.append(_line2(Vector2(xc + hlw, yb), Vector2(xc + hlw, ys), 4))
		paths.append(_arch_pts(xc - hlw, xc + hlw, ys, y_inner, 12))
		# flanking vesica loops, stepped DOWN and OUT (the plate's cascading almonds)
		var gap := bw * 0.5 - hlw
		for sgn in [-1.0, 1.0]:
			var vx := xc + float(sgn) * (hlw + gap * 0.5)
			var vcy := yb + (ys - yb) * 0.58
			paths.append(_closed(_vesica_pts(vx, vcy, flank_hw, flank_hh, 12)))
			_glass_fan_cyl(vx / r, vcy, r, _vesica_pts(0.0, 0.0, flank_hw * 0.55, flank_hh * 0.78, 10), pane, _pane_color(base_pane, vx * 3.1 + 7.0), glass_st)
			var vx2 := xc + float(sgn) * (hlw + gap * 0.78)
			var vcy2 := yb + (ys - yb) * 0.24
			paths.append(_closed(_vesica_pts(vx2, vcy2, flank_hw * 0.62, flank_hh * 0.62, 10)))
			_glass_fan_cyl(vx2 / r, vcy2, r, _vesica_pts(0.0, 0.0, flank_hw * 0.34, flank_hh * 0.47, 8), pane, _pane_color(base_pane, vx2 * 4.7 + 23.0), glass_st)
			cells += 2
		# the LARGE gridded window (glass curtain behind the ribs)
		cells += _grid_window(xc, (yb + ys) * 0.5, hlw, (ys - yb) * 0.5, int(p["grid_cols"]), int(p["grid_rows"]), r, p, glass_st)
	# --- CROWN BAND: small arches springing off the body course, lit lancets between ---
	var crown_y := body_h + (height - body_h) * 0.45
	var nrw := int(p["crown_windows"])
	var chw := (circ / float(nrw)) * 0.30
	var chh := (height - body_h) * 0.55
	for kk in range(nrw):
		var cx := x_base + (float(kk) + 0.5) / float(nrw) * circ
		var cb := wrapi(int(floor((cx - x_base) / bw)), 0, bays)
		if res_bays.has(cb) and body_h <= door_clear_y:
			continue   # short tier: the course is gated off this door bay — a crown arch would dangle
		paths.append(_arch_pts(cx - chw, cx + chw, body_h, body_h + chh, 6))
		_glass_fan_cyl(cx / r, crown_y, r, _lancet(chw * 0.7, chh * 0.55, 5, 0.25), pane, _pane_color(base_pane, cx * 7.7 + 50.0), glass_st)
		cells += 1
	# --- fuse the whole network watertight ---
	var graph: Dictionary = LatticeGraph.build(paths, 0.02)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	frame_st.set_color(p["rib_color"])
	LatticeGraph.mesh(frame_st, graph, LatticeGraph.drum_surface(r), rib_r, int(p["rib_sides"]))
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cells}

# Ensure an outline is exactly closed (first point repeated at the end) so the graph welds it into a
# loop instead of leaving two near-coincident capped ends.
static func _closed(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(outline)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) > 1.0e-6:
		out.append(out[0])
	return out

# A closed comma / mouchette DROP: a teardrop leaned sideways (`sgn` mirrors it) so the point aims
# along the arch it nests against. First == last -> the graph sweeps it as a loop.
static func _drop_loop(cx: float, cy: float, size: float, sgn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var seg := 16
	var tilt := float(sgn) * 0.55
	var ct := cos(tilt)
	var st_ := sin(tilt)
	for i in range(seg + 1):
		var a := TAU * float(i) / float(seg)
		var wf := maxf(sin(a * 0.5), 0.32)           # narrow at the tail but never a zero-width pinch
		var px := size * 0.85 * sin(a) * wf
		var py := size * 1.4 * (0.5 - 0.5 * cos(a)) - size * 0.7
		out.append(Vector2(cx + px * ct - py * st_, cy + px * st_ + py * ct))
	return out

# Glass fan with ORIENTATION-CORRECTED winding: the fan faces outward regardless of whether the
# outline was authored CW or CCW. (The old emitter assumed CW — CCW outlines like the grid-window
# rounded rects rendered facing INTO the drum, the "missing big windows" bug.)
static func _glass_fan_cyl(base_th: float, yc: float, r: float, outline: PackedVector2Array, pane: float, col: Color, st: SurfaceTool) -> void:
	var pts := outline
	if _signed_area(pts) > 0.0:
		pts = PackedVector2Array(outline)
		pts.reverse()
	_emit_glass_cyl(base_th, yc, r, pts, pane, col, st)

static func _signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		var q := pts[(i + 1) % pts.size()]
		a += pts[i].x * q.y - q.x * pts[i].y
	return a * 0.5

# TIERED tracery: a tiered ("cake") base has N vertical drum bands, each at its own shrinking radius.
# The lattice acts PER VERTICAL FACE — one full tracery band per tier at that tier's radius, stacked in
# Y — so a tier's ribs wrap its own drum (not the one below) and stop at the ledge. Doors (the reserved
# bays) live on the ground tier only. Flat ledge faces are handled by `ledge_treatment`, not here.
static func tracery_tiered(spec: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var tiers := maxi(1, int(spec.get("tiers", 1)))
	var radius := float(spec.get("radius", 2.4))
	var height := float(spec.get("height", 7.2))
	var inset := float(spec.get("tier_inset", 0.16))
	var band := height / float(tiers)
	var reserved: Array = overrides.get("reserved", [])
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	for k in range(tiers):
		var rk := maxf(0.4, radius * (1.0 - inset * float(k)))
		var ov := overrides.duplicate()
		ov["reserved"] = reserved if k == 0 else []          # doors only on the ground tier
		if spec.has("bays"):
			ov["bays"] = int(spec["bays"])
		var built: Dictionary = tracery(rk, band, ov)
		var xf := Transform3D(Basis(), Vector3(0.0, float(k) * band, 0.0))
		if built.get("frame") != null:
			fst.append_from(built["frame"] as ArrayMesh, 0, xf)
		if built.get("glass") != null:
			gst.append_from(built["glass"] as ArrayMesh, 0, xf)
		cells += int(built.get("cells", 0))
	return {"frame": fst.commit(), "glass": gst.commit(), "cells": cells}

# TIERED honeyframe: the box equivalent — one honeyframe band per tier at that tier's shrunk footprint.
static func honeyframe_tiered(spec: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var tiers := maxi(1, int(spec.get("tiers", 1)))
	var size: Vector3 = spec.get("size", Vector3(4.5, 8.0, 5.5))
	var inset := float(spec.get("tier_inset", 0.16))
	var band := size.y / float(tiers)
	var reserved: Array = overrides.get("reserved", [])
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(tiers):
		var f := maxf(0.25, 1.0 - inset * float(k))
		var ov := overrides.duplicate()
		ov["reserved"] = reserved if k == 0 else []
		ov["crown"] = (k == tiers - 1)   # rooftop cornice/parapet/vent only on the top drum
		ov["base"] = (k == 0)            # stepped plinth only on the ground drum
		var built: Dictionary = honeyframe(Vector3(size.x * f, band, size.z * f), ov)
		var xf := Transform3D(Basis(), Vector3(0.0, float(k) * band, 0.0))
		if built.get("frame") != null:
			fst.append_from(built["frame"] as ArrayMesh, 0, xf)
		if built.get("glass") != null:
			gst.append_from(built["glass"] as ArrayMesh, 0, xf)
	return {"frame": fst.commit(), "glass": gst.commit()}

# Convert a 2D (arc-length, height) rib path into SDF CAPSULE prims mapped onto the drum. Consecutive
# capsules share endpoints, and every rib's capsules union with a smooth-min `k`, so where ribs cross
# they FUSE into one organic surface (the metaball merge) instead of reading as overlapping sausages.
# The centreline sits `standoff` off the true-circle wall so half the capsule sinks into the drum.
static func _rib_caps(path2d: PackedVector2Array, radius: float, rib_r: float, k: float, standoff: float, out: Array) -> void:
	for i in range(path2d.size() - 1):
		var a := _cylp(0.0, 0.0, radius, path2d[i], standoff)
		var b := _cylp(0.0, 0.0, radius, path2d[i + 1], standoff)
		out.append({"type": "capsule", "a": a, "b": b, "r1": rib_r, "r2": rib_r, "k": k})

# Sweep a half-round bone rib along a 2D (arc-length, height) path mapped onto the drum. The centreline
# sits `standoff` off the true-circle wall so half the tube sinks into the drum -> a surface moulding.
static func _sweep_rib(path2d: PackedVector2Array, r: float, p: Dictionary, st: SurfaceTool) -> void:
	if path2d.size() < 2:
		return
	var pts3: Array = []
	var cols: Array = []
	var col: Color = p["rib_color"]
	var so := float(p["standoff"])
	for pt in path2d:
		pts3.append(_cylp(0.0, 0.0, r, pt, so))
		cols.append(col)
	_sweep_tube(pts3, float(p["rib_radius"]), int(p["rib_sides"]), cols, st)

# ============================================================================================
# RIB JUNCTION (algorithm 3) — the clean, no-sausage, no-SDF way to FUSE crossing ribs. Given a
# junction CENTRE, an in-plane frame (u,v) (n = u x v is the half-round bulge direction, e.g. the
# surface normal), and the arm DIRECTIONS meeting there, it: intersects the arm EDGES (centreline
# +/- radius) at the junction CORNERS, forms the merged footprint boundary, and lofts it to a
# half-round ridge -> one watertight hub. Route each detected rib-path crossing through this instead of
# overlapping two _sweep_tube()s (which sausage) or fielding an SDF (which is heavy). Appends to `st`.
# `arm_len` is how far the hub reaches before the straight rib takes over (sweep the rib up to here).
static func rib_junction(st: SurfaceTool, center: Vector3, u_in: Vector3, v_in: Vector3, arm_dirs: Array, radius: float, arm_len: float = 0.0) -> void:
	var u := u_in.normalized()
	var v := v_in.normalized()
	var nrm := u.cross(v).normalized()
	var reach := arm_len if arm_len > 0.0 else radius * 2.4
	var arms: Array = []
	for d3 in arm_dirs:
		var a2 := Vector2((d3 as Vector3).dot(u), (d3 as Vector3).dot(v))
		if a2.length() < 1.0e-6:
			continue
		a2 = a2.normalized()
		arms.append({"d": a2, "p": Vector2(-a2.y, a2.x), "ang": atan2(a2.y, a2.x)})
	arms.sort_custom(func(x, y): return float(x["ang"]) < float(y["ang"]))
	var n := arms.size()
	if n < 2:
		return
	# corner[i] = arm i's LEFT edge ∩ arm (i+1)'s RIGHT edge (in the (u,v) plane)
	var corner: Array = []
	for i in range(n):
		var ai: Dictionary = arms[i]
		var aj: Dictionary = arms[(i + 1) % n]
		corner.append(_isect2((ai["p"] as Vector2) * radius, ai["d"], (aj["p"] as Vector2) * -radius, aj["d"]))
	# merged footprint boundary loop (per arm: far-right, far-left, corner-to-next)
	var loop: Array = []
	for i in range(n):
		var ai: Dictionary = arms[i]
		var e := (ai["d"] as Vector2) * reach
		var pr := (ai["p"] as Vector2) * radius
		loop.append(e - pr)
		loop.append(e + pr)
		loop.append(corner[i] as Vector2)
	var m := loop.size()
	var cen := _centroid2(loop)
	# loft quarter-circle layers (inset + raise) -> half-round ridge; map (u,v)+n back to 3D
	var layers := 4
	var pts: Array = []
	var ys: Array = []
	for k in range(layers + 1):
		var a := (float(k) / float(layers)) * PI * 0.5
		pts.append(_inset2(loop, radius * (1.0 - cos(a)) * 0.94, cen))
		ys.append(radius * sin(a))
	for k in range(layers):
		var p0: Array = pts[k]
		var p1: Array = pts[k + 1]
		for i in range(m):
			var j := (i + 1) % m
			var a0 := _map2(center, u, v, nrm, p0[i], ys[k])
			var b0 := _map2(center, u, v, nrm, p0[j], ys[k])
			var a1 := _map2(center, u, v, nrm, p1[i], ys[k + 1])
			var b1 := _map2(center, u, v, nrm, p1[j], ys[k + 1])
			_tri(st, a0, b0, b1)
			_tri(st, a0, b1, a1)
	var top: Array = pts[layers]
	var tc := _map2(center, u, v, nrm, _centroid2(top), float(ys[layers]))
	var base: Array = pts[0]
	var bc := _map2(center, u, v, nrm, _centroid2(base), 0.0)
	for i in range(m):
		var j := (i + 1) % m
		_tri(st, tc, _map2(center, u, v, nrm, top[i], float(ys[layers])), _map2(center, u, v, nrm, top[j], float(ys[layers])))
		_tri(st, bc, _map2(center, u, v, nrm, base[j], 0.0), _map2(center, u, v, nrm, base[i], 0.0))

static func _map2(center: Vector3, u: Vector3, v: Vector3, nrm: Vector3, p: Vector2, y: float) -> Vector3:
	return center + u * p.x + v * p.y + nrm * y

static func _isect2(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2) -> Vector2:
	var den := d1.x * d2.y - d1.y * d2.x
	if absf(den) < 1.0e-6:
		return p1
	var t := ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den
	return p1 + d1 * t

static func _centroid2(pts: Array) -> Vector2:
	var s := Vector2.ZERO
	for pt in pts:
		s += pt as Vector2
	return s / float(maxi(1, pts.size()))

# Inset a CCW polygon inward by `delta` (each edge along its inward normal; new verts = adjacent
# inset-edge intersections). Inward chosen per edge toward the centroid.
static func _inset2(loop: Array, delta: float, centroid: Vector2) -> Array:
	var m := loop.size()
	var out: Array = []
	for i in range(m):
		var a: Vector2 = loop[(i - 1 + m) % m]
		var b: Vector2 = loop[i]
		var c: Vector2 = loop[(i + 1) % m]
		out.append(_isect2(a + _inward2(a, b, centroid) * delta, b - a, b + _inward2(b, c, centroid) * delta, c - b))
	return out

static func _inward2(a: Vector2, b: Vector2, centroid: Vector2) -> Vector2:
	var e := b - a
	var nrm := Vector2(-e.y, e.x).normalized()
	if nrm.dot(centroid - (a + b) * 0.5) < 0.0:
		nrm = -nrm
	return nrm

# ---- JUNCTION rib-merge for a whole rib network on the DRUM (the algorithm-3 alternative to the SDF).
# Sweeps each rib path as a half-round moulding on the drum, then drops a rib_junction hub at every
# detected path crossing so the crossings read fused (no sausage crease) — no voxel field.
static func _build_ribs_junction(st: SurfaceTool, paths: Array, r: float, rib_r: float, standoff: float, sides: int) -> void:
	for path in paths:
		_sweep_half_round_on_drum(st, path as PackedVector2Array, r, rib_r, standoff, sides)
	for cr in _find_crossings(paths):
		var rd := cr as Dictionary
		_add_drum_junction(st, rd["pos"], rd["da"], rd["db"], r, rib_r, standoff)

# The O(n^2) rib-crossing detection, ported to C++ (LatticeGeomNative) with a GDScript fallback (same
# _seg_x thresholds). Returns [{pos:Vector2, da:Vector2, db:Vector2}] — one per interior crossing.
static var _geom_checked := false
static var _geom: Object = null

static func _find_crossings(paths: Array) -> Array:
	if not _geom_checked or (_geom != null and not is_instance_valid(_geom)):
		_geom_checked = true
		_geom = ClassDB.instantiate("LatticeGeomNative") if ClassDB.class_exists("LatticeGeomNative") else null
	if _geom != null and is_instance_valid(_geom):
		return _geom.call("segment_crossings", paths)
	var out: Array = []
	for i in range(paths.size()):
		var pa: PackedVector2Array = paths[i]
		for j in range(i + 1, paths.size()):
			var pb: PackedVector2Array = paths[j]
			for si in range(pa.size() - 1):
				for sj in range(pb.size() - 1):
					var hit := _seg_x(pa[si], pa[si + 1], pb[sj], pb[sj + 1])
					if bool(hit.get("hit", false)):
						out.append({"pos": hit["pos"], "da": pa[si + 1] - pa[si], "db": pb[sj + 1] - pb[sj]})
	return out

# Sweep a HALF-ROUND moulding (flat bottom on the drum, arc bulging out) along a (arc-length, height)
# path mapped onto the drum. The flat chord sits on the opaque drum, so only the outer arc is emitted.
static func _sweep_half_round_on_drum(st: SurfaceTool, path2d: PackedVector2Array, r: float, rib_r: float, standoff: float, sides: int) -> void:
	var m := path2d.size()
	if m < 2:
		return
	var rings: Array = []
	for idx in range(m):
		var pt: Vector2 = path2d[idx]
		var a := pt.x / r
		var u_arc := Vector3(-sin(a), 0.0, cos(a))     # arc tangent
		var rad := Vector3(cos(a), 0.0, sin(a))        # radial outward (bulge)
		var center := _cylp(0.0, 0.0, r, pt, standoff)
		var t2: Vector2 = path2d[1] - path2d[0] if idx == 0 else (path2d[m - 1] - path2d[m - 2] if idx == m - 1 else path2d[idx + 1] - path2d[idx - 1])
		var t3 := u_arc * t2.x + Vector3(0.0, 1.0, 0.0) * t2.y
		t3 = u_arc if t3.length() < 1.0e-6 else t3.normalized()
		var perp := rad.cross(t3).normalized()         # in-surface perpendicular
		var ring: Array = []
		for s in range(sides + 1):
			var phi := PI * float(s) / float(sides)
			ring.append(center + perp * (rib_r * cos(phi)) + rad * (rib_r * sin(phi)))
		rings.append(ring)
	for i in range(m - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(sides):
			_tri(st, r0[s], r0[s + 1], r1[s + 1])
			_tri(st, r0[s], r1[s + 1], r1[s])

# A rib_junction hub at a crossing on the drum: frame v=arc-tangent, u=vertical (so n=uxv=radial out).
static func _add_drum_junction(st: SurfaceTool, pos2d: Vector2, dir_a: Vector2, dir_b: Vector2, r: float, rib_r: float, standoff: float) -> void:
	var a := pos2d.x / r
	var u_arc := Vector3(-sin(a), 0.0, cos(a))
	var center := _cylp(0.0, 0.0, r, pos2d, standoff)
	var ta := (u_arc * dir_a.x + Vector3(0.0, 1.0, 0.0) * dir_a.y).normalized()
	var tb := (u_arc * dir_b.x + Vector3(0.0, 1.0, 0.0) * dir_b.y).normalized()
	rib_junction(st, center, Vector3(0.0, 1.0, 0.0), u_arc, [ta, -ta, tb, -tb], rib_r, rib_r * 1.7)

# ---- The same JUNCTION rib-merge on a FLAT FACE (origin + in-face axes u,v; n = u x v = face out). ---
static func _build_ribs_junction_planar(st: SurfaceTool, paths: Array, origin: Vector3, u: Vector3, v: Vector3, radius: float, sides: int) -> void:
	for path in paths:
		_sweep_half_round_planar(st, path as PackedVector2Array, origin, u, v, radius, sides)
	for cr in _find_crossings(paths):
		var rd := cr as Dictionary
		var da: Vector2 = rd["da"]
		var db: Vector2 = rd["db"]
		var pos: Vector2 = rd["pos"]
		var ta := (u * da.x + v * da.y).normalized()
		var tb := (u * db.x + v * db.y).normalized()
		rib_junction(st, origin + u * pos.x + v * pos.y, u, v, [ta, -ta, tb, -tb], radius, radius * 1.7)

static func _sweep_half_round_planar(st: SurfaceTool, path2d: PackedVector2Array, origin: Vector3, u: Vector3, v: Vector3, radius: float, sides: int) -> void:
	var m := path2d.size()
	if m < 2:
		return
	var nrm := u.cross(v).normalized()   # face outward = bulge direction
	var rings: Array = []
	for idx in range(m):
		var pt: Vector2 = path2d[idx]
		var center := origin + u * pt.x + v * pt.y
		var t2: Vector2 = path2d[1] - path2d[0] if idx == 0 else (path2d[m - 1] - path2d[m - 2] if idx == m - 1 else path2d[idx + 1] - path2d[idx - 1])
		var t3 := u * t2.x + v * t2.y
		t3 = u if t3.length() < 1.0e-6 else t3.normalized()
		var perp := nrm.cross(t3).normalized()
		var ring: Array = []
		for s in range(sides + 1):
			var phi := PI * float(s) / float(sides)
			ring.append(center + perp * (radius * cos(phi)) + nrm * (radius * sin(phi)))
		rings.append(ring)
	for i in range(m - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(sides):
			_tri(st, r0[s], r0[s + 1], r1[s + 1])
			_tri(st, r0[s], r1[s + 1], r1[s])

# Segment-segment intersection in 2D (interiors only, away from endpoints). {hit:bool, pos:Vector2}.
static func _seg_x(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Dictionary:
	var da := a2 - a1
	var db := b2 - b1
	var den := da.x * db.y - da.y * db.x
	if absf(den) < 1.0e-9:
		return {"hit": false}
	var t := ((b1.x - a1.x) * db.y - (b1.y - a1.y) * db.x) / den
	var uu := ((b1.x - a1.x) * da.y - (b1.y - a1.y) * da.x) / den
	if t > 0.02 and t < 0.98 and uu > 0.02 and uu < 0.98:
		return {"hit": true, "pos": a1 + da * t}
	return {"hit": false}

# A subdivided straight segment (so a rib hugs the drum curvature instead of chording across facets).
static func _line2(a: Vector2, b: Vector2, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(seg + 1):
		out.append(a.lerp(b, float(i) / float(seg)))
	return out

# A pointed (cusped) arch polyline: spring (x0,y_spring) -> cusp apex (mid,apex) -> spring (x1,y_spring).
static func _arch_pts(x0: float, x1: float, y_spring: float, apex: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var xm := (x0 + x1) * 0.5
	var rise := apex - y_spring
	for i in range(seg + 1):        # left half rises to the apex
		var t := float(i) / float(seg)
		out.append(Vector2(lerpf(x0, xm, t), y_spring + rise * sin(t * PI * 0.5)))
	for i in range(1, seg + 1):     # right half falls back to the spring (cusp at the apex)
		var t := float(i) / float(seg)
		out.append(Vector2(lerpf(xm, x1, t), apex - rise * (1.0 - cos(t * PI * 0.5))))
	return out

# A closed ellipse outline (the oval "eye"), first point repeated so the swept rib closes.
static func _ellipse_pts(cx: float, cy: float, rx: float, ry: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(seg + 1):
		var a := TAU * float(i) / float(seg)
		out.append(Vector2(cx + rx * cos(a), cy + ry * sin(a)))
	return out

# A closed inverted-teardrop outline: a point at the bottom (cx, y_bot), rounded top near (cx, y_top),
# widest at mid. The width vanishes at the bottom (a=0) via the sin(a/2) pinch -> the pointed tip.
static func _teardrop_pts(cx: float, y_top: float, y_bot: float, hw: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var h := y_top - y_bot
	for i in range(seg + 1):
		var a := TAU * float(i) / float(seg)
		var wf := sin(a * 0.5)                    # 0 at the bottom point, 1 at the top
		out.append(Vector2(cx + hw * sin(a) * wf * 1.6, y_bot + h * (0.5 - 0.5 * cos(a))))
	return out

# A vesica / pointed oval: pointed at TOP and BOTTOM, widest at the middle (the flanking-lancet shape
# and the almond window inside it). Wound like _lancet so the glass fan faces outward.
static func _vesica_pts(cx: float, cy: float, hw: float, hh: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(seg + 1):            # right side, top point -> bottom point
		var t := float(i) / float(seg)
		var f := sin(t * PI)            # 0 at both tips, 1 at the middle
		out.append(Vector2(cx + hw * f, cy + hh - 2.0 * hh * t))
	for i in range(seg - 1, 0, -1):     # left side back up (skip shared tips)
		var t := float(i) / float(seg)
		var f := sin(t * PI)
		out.append(Vector2(cx - hw * f, cy + hh - 2.0 * hh * t))
	return out

# A comma / half-yin-yang (mouchette): a round bulb at the top tapering to a point that HOOKS to one
# side (`sgn`). Two mirrored commas face each other in the tympanum between the nested arches.
static func _comma_pts(cx: float, cy: float, size: float, sgn: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var h := size * 1.7
	for i in range(seg + 1):
		var a := TAU * float(i) / float(seg)
		var wf := sin(a * 0.5)                      # 0 at the bottom point, 1 at the top bulb
		var bx := size * sin(a) * wf * 1.25
		var by := h * (0.5 - 0.5 * cos(a))          # 0 at the point, h at the bulb top
		var hook := sgn * size * 0.9 * (1.0 - wf)   # curl the point sideways -> the comma tail
		out.append(Vector2(cx + bx + hook, cy - h * 0.4 + by))
	return out

# The large window as a fine grid of small lit panes (bare drum shows between them as the mullions).
static func _grid_window(xc: float, yc: float, hw: float, hh: float, cols: int, rows: int, r: float, p: Dictionary, st: SurfaceTool) -> int:
	var cw := (hw * 2.0) / float(cols)
	var ch := (hh * 2.0) / float(rows)
	var gap := minf(cw, ch) * 0.10
	var base_pane: Color = p["pane_color"]
	var pane := float(p["pane"])
	var n := 0
	for cxi in range(cols):
		for cyi in range(rows):
			var px := xc - hw + (float(cxi) + 0.5) * cw
			var py := yc - hh + (float(cyi) + 0.5) * ch
			_glass_fan_cyl(px / r, py, r, _rounded_rect(cw * 0.5 - gap, ch * 0.5 - gap, 0.01, 1), pane, _pane_color(base_pane, px * 3.1 + py * 7.7), st)
			n += 1
	return n

# A tall pointed-arch (lancet) outline: near-parallel sides at ±hw for most of the height, tapering to
# pointed tips at ±hh over the outer `taper` fraction. taper->0 is a rectangle; taper->0.5 is a vesica.
static func _lancet(hw: float, hh: float, seg: int, taper: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):        # right side, top tip -> bottom tip
		var t := float(i) / float(seg)
		var f := smoothstep(0.0, taper, minf(t, 1.0 - t))
		pts.append(Vector2(hw * f, hh - 2.0 * hh * t))
	for i in range(seg - 1, 0, -1): # left side, bottom -> top (skip the shared tips)
		var t := float(i) / float(seg)
		var f := smoothstep(0.0, taper, minf(t, 1.0 - t))
		pts.append(Vector2(-hw * f, hh - 2.0 * hh * t))
	return pts

static func _cylp(base_th: float, yc: float, r: float, pt: Vector2, dn: float) -> Vector3:
	var a := base_th + pt.x / r
	var rr := r + dn
	return Vector3(rr * cos(a), yc + pt.y, rr * sin(a))

# A CLOSED lancet rib on the drum: top annulus at r+`top`, walls dropping to r+`back` (inside the drum),
# and the bottom annulus that closes it. `back` is negative and deeper than the facet sagitta so the rib
# always bites into the faceted drum (no float gap at facet midpoints).
static func _emit_ring_cyl(base_th: float, yc: float, r: float,
		outer: PackedVector2Array, inner: PackedVector2Array, top: float, back: float, bevel: float, st: SurfaceTool) -> void:
	var count := outer.size()
	for i in range(count):
		var j := (i + 1) % count
		var ot_i := _cylp(base_th, yc, r, outer[i], top)
		var ot_j := _cylp(base_th, yc, r, outer[j], top)
		var it_i := _cylp(base_th, yc, r, inner[i], top)
		var it_j := _cylp(base_th, yc, r, inner[j], top)
		var mt_i := _cylp(base_th, yc, r, outer[i].lerp(inner[i], 0.5), top + bevel)
		var mt_j := _cylp(base_th, yc, r, outer[j].lerp(inner[j], 0.5), top + bevel)
		var ob_i := _cylp(base_th, yc, r, outer[i], back)
		var ob_j := _cylp(base_th, yc, r, outer[j], back)
		var ib_i := _cylp(base_th, yc, r, inner[i], back)
		var ib_j := _cylp(base_th, yc, r, inner[j], back)
		# top moulding: outer rim -> mid crest -> inner rim (faces outward)
		_tri(st, ot_i, ot_j, mt_j)
		_tri(st, ot_i, mt_j, mt_i)
		_tri(st, mt_i, mt_j, it_j)
		_tri(st, mt_i, it_j, it_i)
		# bottom annulus (faces inward, into the drum)
		_tri(st, ob_i, ib_j, ob_j)
		_tri(st, ob_i, ib_i, ib_j)
		# outer wall
		_tri(st, ob_i, ot_i, ot_j)
		_tri(st, ob_i, ot_j, ob_j)
		# inner wall = the window reveal
		_tri(st, it_i, it_j, ib_j)
		_tri(st, it_i, ib_j, ib_i)

# The lit lancet pane, wound to face OUTWARD (+radial) so it needs no double-siding. `col` is the
# per-pane window light written as vertex COLOR for the window shader.
static func _emit_glass_cyl(base_th: float, yc: float, r: float,
		inner: PackedVector2Array, pane: float, col: Color, st: SurfaceTool) -> void:
	st.set_color(col)
	var count := inner.size()
	var mid := _cylp(base_th, yc, r, Vector2.ZERO, pane)
	for i in range(count):
		var j := (i + 1) % count
		_tri(st, mid, _cylp(base_th, yc, r, inner[j], pane), _cylp(base_th, yc, r, inner[i], pane))

# The four vertical facade faces of a box (base at y=0): centre, in-plane U axis, outward normal, w, h.
static func _box_vertical_faces(size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var my := size.y * 0.5
	return [
		{"c": Vector3(0, my, hz), "u": Vector3(1, 0, 0), "n": Vector3(0, 0, 1), "w": size.x, "h": size.y},
		{"c": Vector3(0, my, -hz), "u": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "w": size.x, "h": size.y},
		{"c": Vector3(hx, my, 0), "u": Vector3(0, 0, -1), "n": Vector3(1, 0, 0), "w": size.z, "h": size.y},
		{"c": Vector3(-hx, my, 0), "u": Vector3(0, 0, 1), "n": Vector3(-1, 0, 0), "w": size.z, "h": size.y},
	]

# ============================================================================================
# ENTRANCES — a grand MAIN portal (jambs + lintel + recessed doors + canopy + steps) at the base
# centre-front, plus a smaller SIDE door (maintenance / enforcement) with a teal accent. Works on box
# faces AND the drum (placed in a right-handed local frame, so the boxes sit correctly on the curve).
# ============================================================================================

## Build the entrance MESHES for a base shape FROM THE SURVEY's door placements
## (BuildingSurvey.door_placements — the one placement authority; the parameter table lives there
## too as BuildingSurvey.ENTRANCE_DEFAULTS). Returns {stone, dark, accent} meshes, the main sign
## anchor, the full `anchors` list, `reserved` regions (the survey's opening reservations — passed
## to the base-mesh cutters and lattices), and the placed `side_count`.
static func entrances(spec: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var p: Dictionary = BuildingSurvey.ENTRANCE_DEFAULTS.duplicate()
	var spec_ov: Dictionary = spec.get("entrances", {})   # per-building entrance tuning lives on the spec
	for k in spec_ov.keys():
		p[k] = spec_ov[k]
	for k in overrides.keys():
		p[k] = overrides[k]
	var placements: Array = BuildingSurvey.door_placements(spec, p)
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent := SurfaceTool.new()
	accent.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anchors: Array = []
	var reserved: Array = []
	var main_n := Vector3(0, 0, 1)
	var main_top := Vector3(0, 3, 3)
	var side_count := 0
	for pl_v in placements:
		var pl := pl_v as Dictionary
		var fr := pl["frame"] as Dictionary
		var is_main := bool(pl["main"])
		var surround := not (is_main and not bool(p.get("main_surround", true)))
		_emit_door(stone, dark, dark if is_main else accent, fr, float(pl["w"]), float(pl["h"]), p, not is_main, surround)
		if is_main:
			main_n = fr["n"]
			main_top = (fr["anchor"] as Vector3) + Vector3(0, 1, 0) * (float(pl["h"]) + 0.55) + main_n * 0.06
			anchors.append({"main": true, "pos": fr["anchor"], "n": fr["n"], "top": main_top})
		else:
			side_count += 1
			anchors.append({"main": false, "pos": fr["anchor"], "n": fr["n"]})
		reserved.append(pl["region"])
	stone.generate_normals()
	dark.generate_normals()
	accent.generate_normals()
	return {
		"stone": stone.commit(), "dark": dark.commit(), "accent": accent.commit(),
		"main_top": main_top, "main_n": main_n,
		"anchors": anchors, "reserved": reserved, "side_count": side_count,
	}

# Is a box cell (face-local centred cu,cv; face height h; face normal) inside a reserved door region?
static func _cell_reserved_box(cu: float, cv: float, face_n: Vector3, h: float, reserved: Array) -> bool:
	for reg in reserved:
		var rd := reg as Dictionary
		if bool(rd.get("cyl", true)):
			continue
		if (rd["n"] as Vector3).dot(face_n) < 0.9:
			continue
		if (h * 0.5 + cv) < float(rd["y_top"]) and absf(cu - float(rd["x_center"])) < float(rd["half_w"]):
			return true
	return false

# Is a drum angle within a reserved door arc?
static func _arc_reserved(theta: float, reserved: Array) -> bool:
	for reg in reserved:
		var rd := reg as Dictionary
		if not bool(rd.get("cyl", false)):
			continue
		var dth := theta - float(rd["theta"])
		while dth > PI:
			dth -= TAU
		while dth < -PI:
			dth += TAU
		if absf(dth) < float(rd["half_arc"]):
			return true
	return false

static func _emit_door(stone: SurfaceTool, dark: SurfaceTool, acc: SurfaceTool, frame: Dictionary,
		dw: float, dh: float, p: Dictionary, enforcement: bool, surround: bool = true) -> void:
	var a: Vector3 = frame["anchor"]
	var u: Vector3 = frame["u"]
	var v: Vector3 = frame["v"]
	var n: Vector3 = frame["n"]
	var jamb: float = p["jamb"]
	var proud: float = p["proud"]
	var recess: float = p["recess"]
	var hw := dw * 0.5
	var jc := (dh + jamb) * 0.5
	# jambs + lintel (raised stone surround) — SKIPPED when the building's survey places its OWN
	# entry idiom (plumbing hood / hypelines arch / greenfields arcade): the idiom IS the surround,
	# and the generic stone used to interpenetrate it (the phone playtest's overlap report)
	if surround:
		_emit_oriented_box(stone, a + u * (hw + jamb * 0.5) + v * jc + n * (proud * 0.5), u, v, n, Vector3(jamb * 0.5, jc, proud * 0.5))
		_emit_oriented_box(stone, a - u * (hw + jamb * 0.5) + v * jc + n * (proud * 0.5), u, v, n, Vector3(jamb * 0.5, jc, proud * 0.5))
		_emit_oriented_box(stone, a + v * (dh + jamb * 0.5) + n * (proud * 0.5), u, v, n, Vector3(hw + jamb, jamb * 0.5, proud * 0.5))
	# The doorway INTERIOR is now a real pocket cut into the base mesh (no z-fighting dark box here).
	# Two door leaves set BACK inside that pocket; enforcement leaves glow teal (accent).
	var leaf: SurfaceTool = acc if enforcement else dark
	for side in [-1.0, 1.0]:
		_emit_oriented_box(leaf, a + u * (side * hw * 0.5) + v * (dh * 0.5) - n * (recess * 0.55), u, v, n, Vector3(hw * 0.5 - 0.03, dh * 0.5 - 0.04, 0.03))
	if not surround:
		return
	# canopy overhang + two steps down to the ground (a building whose survey places its OWN entry
	# idiom — the plumbing hood — zeroes canopy_out and no slab is emitted)
	if float(p["canopy_out"]) > 0.05:
		_emit_oriented_box(stone, a + v * (dh + jamb + 0.05) + n * (float(p["canopy_out"]) * 0.5), u, v, n, Vector3(hw + jamb + 0.12, 0.06, float(p["canopy_out"]) * 0.5))
	_emit_oriented_box(stone, a + v * 0.07 + n * 0.18, u, v, n, Vector3(hw + 0.12, 0.07, 0.18))
	_emit_oriented_box(stone, a + v * 0.03 + n * 0.42, u, v, n, Vector3(hw + 0.28, 0.03, 0.20))

# A closed box in an arbitrary right-handed (u,v,n) frame — the oriented cousin of _emit_box.
static func _emit_oriented_box(st: SurfaceTool, center: Vector3, u: Vector3, v: Vector3, n: Vector3, half: Vector3) -> void:
	var vtx := [
		center - u * half.x - v * half.y - n * half.z,
		center + u * half.x - v * half.y - n * half.z,
		center + u * half.x - v * half.y + n * half.z,
		center - u * half.x - v * half.y + n * half.z,
		center - u * half.x + v * half.y - n * half.z,
		center + u * half.x + v * half.y - n * half.z,
		center + u * half.x + v * half.y + n * half.z,
		center - u * half.x + v * half.y + n * half.z,
	]
	var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	for fq in faces:
		_tri(st, vtx[fq[0]], vtx[fq[2]], vtx[fq[1]])
		_tri(st, vtx[fq[0]], vtx[fq[3]], vtx[fq[2]])
