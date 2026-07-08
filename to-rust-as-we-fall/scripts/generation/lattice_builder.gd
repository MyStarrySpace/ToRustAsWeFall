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
	"frame_depth": 0.12,   # how far the frame stands proud of the face
	"corner_round": 0.30,  # P (<=0.5): how much of the half-window is rounded — rounded RECTS, not circles
	"arc_seg": 3,          # segments per rounded corner (low-poly)
	"glass_proud": 0.085,  # the lit pane sits just under the frame top (recessed, but not so deep the frame occludes it)
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
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cells}

static func _honeyframe_face(f: Dictionary, p: Dictionary, frame_st: SurfaceTool, glass_st: SurfaceTool) -> int:
	var w: float = f["w"]
	var h: float = f["h"]
	var cols := int(max(1, round(w / float(p["cell_size"]))))
	var rows := int(max(1, round(h / float(p["cell_size"]))))
	var cw := w / float(cols)
	var ch := h / float(rows)
	var c: Vector3 = f["c"]
	var u: Vector3 = (f["u"] as Vector3).normalized()
	var n: Vector3 = (f["n"] as Vector3).normalized()
	var v := n.cross(u).normalized()   # in-plane "up" (points +y for a vertical face)
	var fw: float = p["frame_width"]
	var fd: float = p["frame_depth"]
	var seg: int = int(p["arc_seg"])
	var proud: float = p["glass_proud"]
	# Window (inner) half-size = cell half-size minus the frame; the frame keeps a CONSTANT width by
	# offsetting the outer outline out by `fw`, so cell_half == window_half + fw.
	var win_hw := maxf(0.05, cw * 0.5 - fw)
	var win_hh := maxf(0.05, ch * 0.5 - fw)
	var r_in := minf(win_hw, win_hh) * clampf(float(p["corner_round"]) * 2.0, 0.0, 1.0)
	var inner := _rounded_rect(win_hw, win_hh, r_in, seg)
	# The outer outline is the FULL cell rectangle (sharp corners), so the frame tiles the whole face
	# with no gaps and the strut fans from each sharp grid-vertex corner out to the rounded window arc
	# — that fan IS the "round toward the vertex" junction (concave window-arc sides, solid crossings).
	var outer := _rounded_rect(win_hw + fw, win_hh + fw, 0.0, seg)
	for row in range(rows):
		for col in range(cols):
			var cu := -w * 0.5 + (col + 0.5) * cw
			var cv := -h * 0.5 + (row + 0.5) * ch
			var center := c + u * cu + v * cv
			_emit_frame_ring(center, u, v, n, outer, inner, fd, frame_st)
			_emit_glass(center, u, v, n, inner, proud, glass_st)
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

# The raised frame ring between the outer (cell) and inner (window) outlines: a top face at +depth
# plus the outer and inner walls dropping back to the face plane.
static func _emit_frame_ring(center: Vector3, u: Vector3, v: Vector3, n: Vector3,
		outer: PackedVector2Array, inner: PackedVector2Array, depth: float, st: SurfaceTool) -> void:
	var count := outer.size()
	for i in range(count):
		var j := (i + 1) % count
		var ot_i := _p3(center, u, v, n, outer[i], depth)
		var ot_j := _p3(center, u, v, n, outer[j], depth)
		var it_i := _p3(center, u, v, n, inner[i], depth)
		var it_j := _p3(center, u, v, n, inner[j], depth)
		var ob_i := _p3(center, u, v, n, outer[i], 0.0)
		var ob_j := _p3(center, u, v, n, outer[j], 0.0)
		var ib_i := _p3(center, u, v, n, inner[i], 0.0)
		var ib_j := _p3(center, u, v, n, inner[j], 0.0)
		# top face (faces +n)
		_tri(st, ot_i, ot_j, it_j)
		_tri(st, ot_i, it_j, it_i)
		# outer wall (faces outward)
		_tri(st, ob_i, ot_i, ot_j)
		_tri(st, ob_i, ot_j, ob_j)
		# inner wall (faces inward, toward the window)
		_tri(st, it_i, it_j, ib_j)
		_tri(st, it_i, ib_j, ib_i)

# The lit window pane: a fan over the inner outline, sitting flush (a hair proud) on the face.
static func _emit_glass(center: Vector3, u: Vector3, v: Vector3, n: Vector3,
		inner: PackedVector2Array, proud: float, st: SurfaceTool) -> void:
	var count := inner.size()
	var mid := _p3(center, u, v, n, Vector2.ZERO, proud)
	for i in range(count):
		var j := (i + 1) % count
		_tri(st, mid, _p3(center, u, v, n, inner[i], proud), _p3(center, u, v, n, inner[j], proud))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

# ============================================================================================
# PIPES — edge/face-descent tubes that drape down a building (works on box faces AND the cylinder).
# Per the spec: a density -> pipe count; each pipe walks DOWN from the top with curve-sampled steps
# and a probability of jogging diagonally to a side lane; occasionally a shorter follower runs
# alongside it. Deterministic (SeededRng), low-poly swept tubes.
# ============================================================================================

const PIPE_DEFAULTS := {
	"radius": 0.07,       # tube radius
	"density": 0.35,      # pipes per metre of surface width -> target count
	"lane_w": 0.45,       # lateral lane spacing for a diagonal jog
	"step_min": 0.5,      # descent step per move (the CURVE_PARAMETER, sampled)
	"step_max": 1.4,
	"diag_prob": 0.35,    # chance a step jogs diagonally to a side lane rather than straight down
	"second_prob": 0.4,   # chance a pipe spawns a parallel follower
	"second_gap": 0.15,   # lateral offset of the follower
	"second_len": 0.6,    # follower length as a fraction of the lead pipe (capped by the lead's end)
	"sides": 6,           # tube cross-section segments (low-poly)
	"standoff": 0.05,     # how far the pipe floats off the surface
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
	for _i in range(num):
		var lead := _walk_pipe(float(rng.call("randf_range", 0.0, w)), w, h, p, rng)
		_sweep_uv(lead, surf, float(p["radius"]), int(p["sides"]), float(p["standoff"]), st)
		if float(rng.call("randf")) < float(p["second_prob"]) and lead.size() >= 2:
			var frac := clampf(float(rng.call("randf_range", 0.3, float(p["second_len"]))), 0.2, 1.0)
			var glen := int(ceil(lead.size() * frac))
			var off := (-1.0 if float(rng.call("randf")) < 0.5 else 1.0) * float(p["second_gap"])
			var follow := PackedVector2Array()
			for k in range(mini(glen, lead.size())):
				follow.append(lead[k] + Vector2(off, 0.0))
			_sweep_uv(follow, surf, float(p["radius"]) * 0.85, int(p["sides"]), float(p["standoff"]), st)

static func _walk_pipe(x0: float, w: float, h: float, p: Dictionary, rng: SeededRng) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := clampf(x0, 0.0, w)
	var v := 0.0
	pts.append(Vector2(x, v))
	var guard := 0
	while v < h and guard < 240:
		guard += 1
		v = minf(h, v + float(rng.call("randf_range", float(p["step_min"]), float(p["step_max"]))))
		if float(rng.call("randf")) < float(p["diag_prob"]):
			x = clampf(x + (-1.0 if float(rng.call("randf")) < 0.5 else 1.0) * float(p["lane_w"]), 0.0, w)
		pts.append(Vector2(x, v))
	return pts

static func _sweep_uv(path_uv: PackedVector2Array, surf: Dictionary, radius: float, sides: int, standoff: float, st: SurfaceTool) -> void:
	if path_uv.size() < 2:
		return
	var pts3: Array = []
	for uv in path_uv:
		pts3.append(_surf_map(surf, uv, standoff + radius))
	_sweep_tube(pts3, radius, sides, st)

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

static func _sweep_tube(pts: Array, radius: float, sides: int, st: SurfaceTool) -> void:
	if pts.size() < 2:
		return
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
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(sides):
			var s2 := (s + 1) % sides
			_tri(st, r0[s], r0[s2], r1[s2])
			_tri(st, r0[s], r1[s2], r1[s])

# ============================================================================================
# TRACERY — pointed-arch (lancet) window wall wrapped on a CYLINDER (Beacon Hill). A raised stone RIB
# lattice in front, lit glass panes behind (the glass "curtain"). Same frame-ring idea as honeyframe,
# but the cell outline is a lancet and the whole thing maps onto the drum.
# ============================================================================================

const TRACERY_DEFAULTS := {
	"cols": 12,           # lancet columns around the drum
	"rows": 2,            # a couple of TALL openings stacked up the height
	"frame_width": 0.26,  # rib thickness (wide ribs -> narrow lancet slots)
	"frame_depth": 0.12,  # rib relief off the wall
	"taper": 0.22,        # fraction of the slot height that tapers to the pointed tips (rest is parallel)
	"arc_seg": 14,        # points top->bottom along a slot side (smooth tall slot)
	"standoff": 0.035,    # lit pane proud of the wall (recessed under the ribs)
}

## Build the tracery lattice for a drum of `radius`/`height`. Returns {frame, glass} ArrayMeshes.
static func tracery(radius: float, height: float, overrides: Dictionary = {}) -> Dictionary:
	var p := TRACERY_DEFAULTS.duplicate()
	for k in overrides.keys():
		p[k] = overrides[k]
	var cols := int(p["cols"])
	var rows := int(p["rows"])
	var cell_w := TAU * radius / float(cols)
	var cell_h := height / float(rows)
	var fw: float = p["frame_width"]
	var win_hw := maxf(0.05, cell_w * 0.5 - fw)
	var win_hh := maxf(0.05, cell_h * 0.5 - fw)
	var seg := int(p["arc_seg"])
	var taper: float = p["taper"]
	var inner := _lancet(win_hw, win_hh, seg, taper)
	var outer := _lancet(win_hw + fw, win_hh + fw, seg, taper)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(rows):
		for i in range(cols):
			var th := TAU * (float(i) + 0.5) / float(cols)
			var yc := (float(j) + 0.5) * cell_h
			_emit_ring_cyl(th, yc, radius, outer, inner, float(p["frame_depth"]), frame_st)
			_emit_glass_cyl(th, yc, radius, inner, float(p["standoff"]), glass_st)
	frame_st.generate_normals()
	glass_st.generate_normals()
	return {"frame": frame_st.commit(), "glass": glass_st.commit(), "cells": cols * rows}

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

static func _emit_ring_cyl(base_th: float, yc: float, r: float,
		outer: PackedVector2Array, inner: PackedVector2Array, depth: float, st: SurfaceTool) -> void:
	var count := outer.size()
	for i in range(count):
		var j := (i + 1) % count
		var ot_i := _cylp(base_th, yc, r, outer[i], depth)
		var ot_j := _cylp(base_th, yc, r, outer[j], depth)
		var it_i := _cylp(base_th, yc, r, inner[i], depth)
		var it_j := _cylp(base_th, yc, r, inner[j], depth)
		var ob_i := _cylp(base_th, yc, r, outer[i], 0.0)
		var ob_j := _cylp(base_th, yc, r, outer[j], 0.0)
		var ib_i := _cylp(base_th, yc, r, inner[i], 0.0)
		var ib_j := _cylp(base_th, yc, r, inner[j], 0.0)
		_tri(st, ot_i, ot_j, it_j)
		_tri(st, ot_i, it_j, it_i)
		_tri(st, ob_i, ot_i, ot_j)
		_tri(st, ob_i, ot_j, ob_j)
		_tri(st, it_i, it_j, ib_j)
		_tri(st, it_i, ib_j, ib_i)

static func _emit_glass_cyl(base_th: float, yc: float, r: float,
		inner: PackedVector2Array, standoff: float, st: SurfaceTool) -> void:
	var count := inner.size()
	var mid := _cylp(base_th, yc, r, Vector2.ZERO, standoff)
	for i in range(count):
		var j := (i + 1) % count
		_tri(st, mid, _cylp(base_th, yc, r, inner[i], standoff), _cylp(base_th, yc, r, inner[j], standoff))

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
