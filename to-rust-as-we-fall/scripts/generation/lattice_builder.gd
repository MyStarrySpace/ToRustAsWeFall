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
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var mid_y := size.y * 0.5
	# The four vertical facade faces: centre, in-plane U axis, outward normal, width, height.
	var faces := [
		{"c": Vector3(0, mid_y, hz), "u": Vector3(1, 0, 0), "n": Vector3(0, 0, 1), "w": size.x, "h": size.y},
		{"c": Vector3(0, mid_y, -hz), "u": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "w": size.x, "h": size.y},
		{"c": Vector3(hx, mid_y, 0), "u": Vector3(0, 0, -1), "n": Vector3(1, 0, 0), "w": size.z, "h": size.y},
		{"c": Vector3(-hx, mid_y, 0), "u": Vector3(0, 0, 1), "n": Vector3(-1, 0, 0), "w": size.z, "h": size.y},
	]
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
	var outer := _rounded_rect(win_hw + fw, win_hh + fw, r_in + fw, seg)
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
