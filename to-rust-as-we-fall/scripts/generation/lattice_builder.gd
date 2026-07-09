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
	"cell_size": 1.25,     # target metres per cell; ~4x6 on the front face, matching the plate
	"frame_width": 0.20,   # cream strut thickness (the window inset from the cell edge)
	"frame_depth": 0.12,   # how far the frame top stands proud of the wall
	"back_bite": 0.03,     # how far the closed frame sinks INTO the wall (overlaps the box, no z-fight)
	"pane": 0.02,          # lit pane depth: recessed under the frame top, a hair proud of the wall behind
	"corner_round": 0.30,  # P (<=0.5): how much of the half-window is rounded — rounded RECTS, not circles
	"arc_seg": 3,          # segments per rounded corner (low-poly)
	"cell_aspect": 1.3,    # rows target taller cells (portrait windows) — height/width per cell
	"jitter": 0.12,        # per-cell hand-made irregularity: offset + scale the WINDOW within its cell
	"bevel": 0.05,         # frame moulding: the band crests this much above its rims (chamfered profile)
	"crown": true,         # emit a cornice + parapet + plinth silhouette
	"pane_color": Color(1.0, 0.72, 0.36),   # base window-light colour; per-pane brightness/tint varies off it
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
	for f in faces:
		cells += _honeyframe_face(f, p, frame_st, glass_st)
	# Closed corner posts down the four vertical box edges cover the miter seam where two faces' frames
	# meet at 90 degrees (otherwise a bare L-wedge runs the full height of every corner).
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var post := float(p["frame_width"]) * 0.75
	var half_y := size.y * 0.5
	for sx in [hx, -hx]:
		for sz in [hz, -hz]:
			_emit_box(frame_st, Vector3(sx, half_y, sz), Vector3(post, half_y, post))
	if bool(p.get("crown", true)):
		_emit_crown_and_base(frame_st, size)
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cells}

# A cornice + parapet-wall ring + a rooftop vent up top, and a stepped plinth at the base — the
# silhouette a bare box lacks. All closed boxes into the frame (cream) surface.
static func _emit_crown_and_base(st: SurfaceTool, size: Vector3) -> void:
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
	# stepped plinth at the base
	_emit_box(st, Vector3(0, 0.16, 0), Vector3(hx + 0.24, 0.16, hz + 0.24))
	_emit_box(st, Vector3(0, 0.40, 0), Vector3(hx + 0.11, 0.10, hz + 0.11))

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
	if str(spec.get("shape", "box")) == "cylinder":
		var r := float(spec.get("radius", 2.0))
		surfaces.append({"kind": "cyl", "r": r, "h": float(spec.get("height", 5.0)), "w": TAU * r})
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
		# A BUNDLE of parallel runs of mixed gauge track down together.
		var bundle := int(rng.call("randi_range", int(p["bundle_min"]), int(p["bundle_max"])))
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
		var a := uv.x / r
		var rr := r + dn
		return Vector3(rr * cos(a), float(surf["h"]) - uv.y, rr * sin(a))
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

const TRACERY_DEFAULTS := {
	"rows": 2,            # a couple of TALL openings stacked up the body height
	"frame_width": 0.26,  # rib thickness (wide ribs -> narrow lancet slots)
	"frame_depth": 0.12,  # rib top relief off the true-circle wall
	"back_bite": 0.07,    # how far the closed rib sinks INTO the drum (> the facet sagitta, so no float gap)
	"taper": 0.22,        # fraction of the slot height that tapers to the pointed tips (rest is parallel)
	"arc_seg": 14,        # points top->bottom along a slot side (smooth tall slot)
	"pane": 0.02,         # lit pane proud of the true-circle wall (recessed under the ribs)
	"bevel": 0.05,        # rib moulding: the band crests this much above its rims
	"col_pattern": [1.0, 0.5, 0.72, 0.5],   # relative lancet widths per bay (a big central lancet + flankers)
	"bays": 4,            # how many times the width pattern repeats around the drum
	"clerestory": true,   # a ring of small roundels above the main lancets
	"body_frac": 0.82,    # main lancets occupy this fraction of the height; the rest is the clerestory band
	"roundels": 16,       # roundel count in the clerestory ring
	"roundel_r": 0.32,    # roundel radius
	"pane_color": Color(1.0, 0.74, 0.42),   # base window-light colour; per-pane brightness/tint varies off it
}

## Build the tracery lattice for a drum of `radius`/`height`. Returns {frame, glass} ArrayMeshes.
static func tracery(radius: float, height: float, overrides: Dictionary = {}) -> Dictionary:
	var p := TRACERY_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var rows := int(p["rows"])
	var fw: float = p["frame_width"]
	var seg := int(p["arc_seg"])
	var taper: float = p["taper"]
	var top := float(p["frame_depth"])
	var back := -float(p["back_bite"])
	var bevel := float(p["bevel"])
	var pane := float(p["pane"])
	var base_pane: Color = p["pane_color"]
	var clerestory := bool(p["clerestory"])
	var body_h := height * float(p["body_frac"]) if clerestory else height
	var cell_h := body_h / float(rows)
	var win_hh := maxf(0.05, cell_h * 0.5 - fw)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	# Main lancets: per-column WIDTHS (a big central lancet + smaller flankers) walked by a running
	# angular cursor, the width pattern repeating `bays` times around the drum.
	var pattern: Array = p["col_pattern"]
	var bays := int(p["bays"])
	var total := 0.0
	for pw in pattern:
		total += float(pw)
	total *= float(bays)
	var circ := TAU * radius
	var cursor := 0.0
	for _bay in range(bays):
		for cw_rel in pattern:
			var seg_w := circ * (float(cw_rel) / total)
			var th := (cursor + seg_w * 0.5) / radius
			var win_hw := maxf(0.05, seg_w * 0.5 - fw)
			var inner := _lancet(win_hw, win_hh, seg, taper)
			var outer := _lancet(win_hw + fw, win_hh + fw, seg, taper)
			for j in range(rows):
				var yc := (float(j) + 0.5) * cell_h
				var key := cursor * 3.7 + float(j) * 57.3
				_emit_ring_cyl(th, yc, radius, outer, inner, top, back, bevel, frame_st)
				_emit_glass_cyl(th, yc, radius, inner, pane, _pane_color(base_pane, key), glass_st)
				cells += 1
			cursor += seg_w
	# Clerestory: a ring of small ROUNDELS above the main lancets (the crown band).
	if clerestory:
		var nr := int(p["roundels"])
		var rr := float(p["roundel_r"])
		var y_cl := body_h + (height - body_h) * 0.5
		var inner_c := _rounded_rect(rr, rr, rr, seg)
		var outer_c := _rounded_rect(rr + fw * 0.7, rr + fw * 0.7, rr + fw * 0.7, seg)
		for k in range(nr):
			var th := TAU * (float(k) + 0.5) / float(nr)
			var key := float(k) * 11.3 + 900.0
			_emit_ring_cyl(th, y_cl, radius, outer_c, inner_c, top, back, bevel, frame_st)
			_emit_glass_cyl(th, y_cl, radius, inner_c, pane, _pane_color(base_pane, key), glass_st)
			cells += 1
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cells}

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

const ENTRANCE_DEFAULTS := {
	"main_w": 1.6, "main_h": 2.7,
	"side_w": 1.1, "side_h": 2.1,
	"jamb": 0.20,        # frame post/lintel thickness
	"proud": 0.16,       # how far the frame stands off the wall
	"recess": 0.42,      # how deep the doorway pocket sinks in
	"canopy_out": 0.5,   # canopy overhang depth
	"side_at": 0.62,     # side-door lateral placement as a fraction of the half-width
}

## Build the entrances for a base shape. Returns {stone, dark, accent} ArrayMeshes + the sign anchor
## above the main door ("main_top" world pos, "main_n" outward normal).
static func entrances(spec: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var p := ENTRANCE_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent := SurfaceTool.new()
	accent.begin(Mesh.PRIMITIVE_TRIANGLES)
	var is_cyl := str(spec.get("shape", "box")) == "cylinder"
	var radius := float(spec.get("radius", 2.0))
	var size: Vector3 = spec.get("size", Vector3(4, 6, 4))
	var half_w := radius if is_cyl else size.x * 0.5
	var front := radius if is_cyl else size.z * 0.5
	var mf := _door_frame(is_cyl, radius, front, 0.0)
	_emit_door(stone, dark, dark, mf, float(p["main_w"]), float(p["main_h"]), p, false)
	var sf := _door_frame(is_cyl, radius, front, half_w * float(p["side_at"]))
	_emit_door(stone, dark, accent, sf, float(p["side_w"]), float(p["side_h"]), p, true)
	stone.generate_normals()
	dark.generate_normals()
	accent.generate_normals()
	return {
		"stone": stone.commit(), "dark": dark.commit(), "accent": accent.commit(),
		"main_top": (mf["anchor"] as Vector3) + (mf["v"] as Vector3) * (float(p["main_h"]) + 0.55) + (mf["n"] as Vector3) * 0.06,
		"main_n": mf["n"],
	}

# A right-handed local frame (u x v = n) anchored on the ground at the wall, facing +Z (the gallery
# front). `lateral` is an x-offset on a box face, or an arc-length offset around the drum.
static func _door_frame(is_cyl: bool, radius: float, front: float, lateral: float) -> Dictionary:
	var n: Vector3
	var anchor: Vector3
	if is_cyl:
		var th := PI * 0.5 + lateral / radius   # front (+Z) is theta = pi/2
		n = Vector3(cos(th), 0.0, sin(th))
		anchor = Vector3(radius * cos(th), 0.0, radius * sin(th))
	else:
		n = Vector3(0, 0, 1)
		anchor = Vector3(lateral, 0.0, front)
	var v := Vector3(0, 1, 0)
	var u := v.cross(n).normalized()   # u x v = n (right-handed, so the box winding faces outward)
	return {"anchor": anchor, "u": u, "v": v, "n": n}

static func _emit_door(stone: SurfaceTool, dark: SurfaceTool, acc: SurfaceTool, frame: Dictionary,
		dw: float, dh: float, p: Dictionary, enforcement: bool) -> void:
	var a: Vector3 = frame["anchor"]
	var u: Vector3 = frame["u"]
	var v: Vector3 = frame["v"]
	var n: Vector3 = frame["n"]
	var jamb: float = p["jamb"]
	var proud: float = p["proud"]
	var recess: float = p["recess"]
	var hw := dw * 0.5
	var jc := (dh + jamb) * 0.5
	# jambs + lintel (raised stone surround)
	_emit_oriented_box(stone, a + u * (hw + jamb * 0.5) + v * jc + n * (proud * 0.5), u, v, n, Vector3(jamb * 0.5, jc, proud * 0.5))
	_emit_oriented_box(stone, a - u * (hw + jamb * 0.5) + v * jc + n * (proud * 0.5), u, v, n, Vector3(jamb * 0.5, jc, proud * 0.5))
	_emit_oriented_box(stone, a + v * (dh + jamb * 0.5) + n * (proud * 0.5), u, v, n, Vector3(hw + jamb, jamb * 0.5, proud * 0.5))
	# recessed pocket (dark doorway interior)
	_emit_oriented_box(dark, a + v * (dh * 0.5) - n * (recess * 0.5), u, v, n, Vector3(hw, dh * 0.5, recess * 0.5))
	# two door leaves just inside the opening; enforcement leaves glow teal (accent)
	var leaf: SurfaceTool = acc if enforcement else dark
	for side in [-1.0, 1.0]:
		_emit_oriented_box(leaf, a + u * (side * hw * 0.5) + v * (dh * 0.5) - n * 0.05, u, v, n, Vector3(hw * 0.5 - 0.03, dh * 0.5 - 0.04, 0.03))
	# canopy overhang + two steps down to the ground
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
