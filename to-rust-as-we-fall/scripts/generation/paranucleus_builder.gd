extends RefCounted
class_name ParanucleusBuilder

## THE PARANUCLEUS — the Act 2 boss mega-landmark (GDD 11.2 + 4.5; boss plate reference-images/
## bosses/paranucleus.png, decomposed 2026-07-11): a monumental amyloid aggregate grown around the
## abandoned NUTECH spray facility. Visual register: OPHANIM — wheels within wheels. Bone-white and
## pale-lavender stacked RINGS standing vertically, all sharing ONE center; raised TOOTH patterns
## along the inner edge of every ring (the plaque's protein-subunit register made architectural);
## porous gaps bridged by thin strands; a faint PINK-RED CORE at the deepest center (the map's only
## pink-red saturation); grey NUTECH industrial fragments at the base, partly ENGULFED by the growth.
##
## This is NOT a district building — it has no wall plan, so it does not ride BuildingSurvey.
## It keeps the survey DISCIPLINE instead: the ring table below is the measured drawing (radii
## reconciled so every nested pair clears its neighbour, teeth included), and validate() turns
## every silent failure into a loud string — an undeclared ring-through-facility contact, a ring
## piercing the ground, a broken nesting chain. The seed sweep test proves every variant validates.
##
## build() emits each ring in its OWN LOCAL FRAME (the circle in local XY, axis = local Z) and
## returns its basis + shared origin, so a scene can spin each wheel in its own plane — the rings
## are wheels; the geometry produces paths that exist at certain alignments and not others.

const CANON_R0 := 7.6          # the outermost ring's major radius (m) at the canonical scale
const CANON_CENTER_Y := 8.4    # the shared wheel center — ring 0's bottom arc dips through the
							   # facility platform + the swallowed block (declared engulfment),
							   # its tube clearing the ground by ~0.15 m

## The measured ring table: [major_r, tube_r, teeth_len, axis_azimuth, axis_pitch] — ALL lengths as
## fractions of r0, angles in radians. RECONCILED HERE: every nested pair holds
## (R_k - tube_k - teeth_k*1.15) - (R_k+1 + tube_k+1) >= 0.015 (the 1.15 = the roller's longest
## tooth roll), and the bound is EXACT, not conservative: two circles sharing a center always come
## within R_a - R_b of each other (their planes meet in a line through the center, and both circles
## cross it), so the chain clearing means the wheels can turn to ANY alignment without touching —
## the ophanim's freedom is a survey guarantee.
const RINGS := [
	[1.000, 0.060, 0.040, 0.00, 0.06],
	[0.810, 0.052, 0.036, 0.55, -0.10],
	[0.640, 0.047, 0.033, 1.10, 0.12],
	[0.485, 0.042, 0.030, 1.65, -0.08],
	[0.345, 0.037, 0.027, 2.20, 0.10],
	[0.220, 0.032, 0.024, 2.80, -0.12],
]
const CORE := {"r": 0.100, "wobble": 0.16}

## The NUTECH facility fragments (fractions of r0; h = full height, boxes seat on the ground).
## `engulfed` declares the boxes the ring bottoms legitimately pass through — the growth swallowed
## them (GDD: "partly engulfed by the amyloid growth, partly still legible as a working facility").
## `sign` marks the boxes that carry a NUTECH board on their +Z face.
const BASE := {
	"boxes": [
		{"x": 0.00, "z": 0.02, "hx": 0.88, "h": 0.055, "hz": 0.64},                      # the apron platform
		{"x": -0.50, "z": 0.30, "hx": 0.24, "h": 0.260, "hz": 0.18, "sign": true},
		{"x": 0.44, "z": 0.32, "hx": 0.20, "h": 0.220, "hz": 0.16, "sign": true},
		{"x": 0.06, "z": -0.10, "hx": 0.16, "h": 0.400, "hz": 0.14, "engulfed": true},   # swallowed block
		{"x": -0.16, "z": -0.44, "hx": 0.22, "h": 0.180, "hz": 0.16, "engulfed": true},
		{"x": 0.74, "z": -0.06, "hx": 0.13, "h": 0.130, "hz": 0.11},
	],
	"engulf_platform": true,   # the apron slab sits under the wheel — the bottom arcs cross it
}

## Resolve the Paranucleus to a spec. Seed 0 = the canonical plate specimen; other seeds roll a
## plate-plausible variant (axis fan re-jittered, teeth density, porosity) whose numbers still
## validate — the sweep test proves it.
static func generate(seed_value: int = 0) -> Dictionary:
	var spec := {
		"kind": "paranucleus",
		"r0": CANON_R0,
		"center_y": CANON_CENTER_Y,
		"rings": _dup_rings(),
		"core": CORE.duplicate(true),
		"base": BASE.duplicate(true),
		"teeth_every": 0.13,     # radians between teeth along a ring
		"gap_count": 3,          # porous gaps per ring (bridged by strands)
		"seed": seed_value,
	}
	if seed_value == 0:
		return spec
	var rng := SeededRng.new((seed_value * 2654435761) ^ 0x5aa5)
	var s := lerpf(0.94, 1.08, float(rng.call("randf")))
	spec["r0"] = CANON_R0 * s
	spec["center_y"] = CANON_CENTER_Y * s
	var rows: Array = spec["rings"]
	for k in range(rows.size()):
		var row := rows[k] as Array
		row[3] = float(row[3]) + lerpf(-0.15, 0.15, float(rng.call("randf")))
		row[4] = float(row[4]) + lerpf(-0.06, 0.06, float(rng.call("randf")))
		row[2] = float(row[2]) * lerpf(0.85, 1.15, float(rng.call("randf")))
	spec["teeth_every"] = lerpf(0.10, 0.16, float(rng.call("randf")))
	spec["gap_count"] = int(rng.call("randi_range", 2, 4))
	return spec

static func _dup_rings() -> Array:
	var out: Array = []
	for row in RINGS:
		out.append((row as Array).duplicate())
	return out

## The loud-string reconcile pass. Empty = the drawing is buildable.
static func validate(spec: Dictionary) -> Array:
	var problems: Array = []
	var r0 := float(spec.get("r0", CANON_R0))
	var cy := float(spec.get("center_y", CANON_CENTER_Y))
	var rows: Array = spec.get("rings", RINGS)
	# nesting chain: every nested pair must clear its neighbour at EVERY alignment
	for k in range(rows.size() - 1):
		var a := rows[k] as Array
		var b := rows[k + 1] as Array
		var inner_a := (float(a[0]) - float(a[1]) - float(a[2])) * r0
		var outer_b := (float(b[0]) + float(b[1])) * r0
		if outer_b > inner_a - 0.015 * r0:
			problems.append("paranucleus: ring %d (outer %.2f) does not clear ring %d's toothed bore (%.2f) — re-reconcile the ring table" % [k + 1, outer_b, k, inner_a])
	# the core must sit clear of the innermost wheel
	var last := rows[rows.size() - 1] as Array
	var core_r := float((spec.get("core", CORE) as Dictionary).get("r", 0.1)) * r0 * 1.2
	if core_r > (float(last[0]) - float(last[1]) - float(last[2])) * r0 - 0.01 * r0:
		problems.append("paranucleus: the core (%.2f) crowds the innermost ring's bore" % core_r)
	# rings must not pierce the ground; contacts with the facility must be DECLARED engulfment
	var base: Dictionary = spec.get("base", BASE)
	var boxes: Array = base.get("boxes", [])
	for k2 in range(rows.size()):
		var row := rows[k2] as Array
		var bs := _ring_basis(row)
		var rr := float(row[0]) * r0
		var tube := float(row[1]) * r0
		for i in range(48):
			var th := TAU * float(i) / 48.0
			var p := bs * Vector3(cos(th) * rr, sin(th) * rr, 0.0) + Vector3(0, cy, 0)
			if p.y - tube < -0.05:
				problems.append("paranucleus: ring %d pierces the ground (arc bottom y=%.2f, tube %.2f)" % [k2, p.y, tube])
				break
			for bi in range(boxes.size()):
				var bx := boxes[bi] as Dictionary
				if bool(bx.get("engulfed", false)):
					continue
				if bi == 0 and bool(base.get("engulf_platform", false)):
					continue
				var half := Vector3(float(bx["hx"]), float(bx["h"]) * 0.5, float(bx["hz"])) * r0
				var cbox := Vector3(float(bx["x"]) * r0, float(bx["h"]) * 0.5 * r0, float(bx["z"]) * r0)
				var d := (p - cbox).abs() - half
				var dist := Vector3(maxf(d.x, 0), maxf(d.y, 0), maxf(d.z, 0)).length()
				if dist < tube + 0.05:
					problems.append("paranucleus: ring %d passes through facility box %d without a declared engulfment — declare it or move the box" % [k2, bi])
	return problems

static func _ring_basis(row: Array) -> Basis:
	# the wheel's plane: circle in local XY; axis = local Z, laid horizontal at the azimuth fan
	# angle, then pitched slightly — every wheel shares the center, none shares a plane
	return Basis(Vector3.UP, float(row[3])) * Basis(Vector3.RIGHT, float(row[4]))

## Build the whole aggregate. Returns:
##   rings          [{bone, lav, basis, spin}] — per-wheel meshes in LOCAL frame (spin = rad/s sign)
##   origin         the shared wheel center (world)
##   core           the pink-red heart (world frame, at origin)
##   nutech / dark / signs   the facility fragments (world frame, seated on y=0)
##   sign_positions [{pos, n}] — where the scene parks its NUTECH lettering
static func build(spec: Dictionary) -> Dictionary:
	var r0 := float(spec.get("r0", CANON_R0))
	var cy := float(spec.get("center_y", CANON_CENTER_Y))
	var kb := float(int(spec.get("seed", 0)) * 137 % 1000)
	var rows: Array = spec.get("rings", RINGS)
	var rings_out: Array = []
	for k in range(rows.size()):
		var row := rows[k] as Array
		rings_out.append(_build_ring(row, k, r0, kb, spec))
	# the core: a wobbled lathe mass (never a clean sphere — it's an aggregate, not a machine)
	var core_st := _st()
	var co: Dictionary = spec.get("core", CORE)
	var co_r := float(co["r"]) * r0
	var wob := float(co.get("wobble", 0.16))
	var co_rows: Array = []
	var n_co := 8
	for i_c in range(n_co + 1):
		var t_c := float(i_c) / float(n_co)
		var rr := sin(t_c * PI) * co_r * (1.0 + wob * (BaseShapeBuilder._h01(kb + 91.0 + float(i_c) * 6.1) - 0.5))
		co_rows.append([(-co_r + t_c * co_r * 2.0) / r0, maxf(0.02, rr) / r0])
	BaseShapeBuilder._rings_loft(core_st, Vector3.ZERO, r0, co_rows, 12)
	core_st.generate_normals()
	# the NUTECH facility fragments
	var nutech := _st()
	var dark := _st()
	var signs := _st()
	var sign_positions: Array = []
	var base: Dictionary = spec.get("base", BASE)
	for bx_v in (base.get("boxes", []) as Array):
		var bx := bx_v as Dictionary
		var half := Vector3(float(bx["hx"]), float(bx["h"]) * 0.5, float(bx["hz"])) * r0
		var cbox := Vector3(float(bx["x"]) * r0, float(bx["h"]) * 0.5 * r0, float(bx["z"]) * r0)
		BaseShapeBuilder._emit_box_st(nutech, cbox, half)
		# institutional window strips on the taller blocks
		if float(bx["h"]) > 0.15:
			for si in range(2):
				var sy := cbox.y + half.y * (0.15 + 0.45 * float(si))
				BaseShapeBuilder._emit_oriented_box_st(dark,
					Vector3(cbox.x, sy, cbox.z + half.z + 0.015),
					Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
					Vector3(half.x * 0.78, 0.09, 0.03))
		if bool(bx.get("sign", false)):
			var sp := Vector3(cbox.x, cbox.y + half.y * 0.62, cbox.z + half.z + 0.06)
			BaseShapeBuilder._emit_oriented_box_st(signs, sp, Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
				Vector3(half.x * 0.66, half.y * 0.22, 0.045))
			sign_positions.append({"pos": sp + Vector3(0, 0, 0.08), "n": Vector3(0, 0, 1)})
	for s_t in [nutech, dark, signs]:
		(s_t as SurfaceTool).generate_normals()
	return {"rings": rings_out, "origin": Vector3(0, cy, 0), "core": core_st.commit(),
		"nutech": nutech.commit(), "dark": dark.commit(), "signs": signs.commit(),
		"sign_positions": sign_positions}

## One wheel, in its LOCAL frame: the lumpy main tube in arc chunks (porous gaps between them),
## thin lavender strands bridging every gap + the pale inner ribbon, the inward tooth row, and
## chunky nodules straddling the tube.
static func _build_ring(row: Array, k: int, r0: float, kb: float, spec: Dictionary) -> Dictionary:
	var rr := float(row[0]) * r0
	var tube := float(row[1]) * r0
	var teeth := float(row[2]) * r0
	var bone := _st()
	var lav := _st()
	var rk := kb + float(k) * 61.7
	# gap spans (porosity): hash-placed, never overlapping (spaced around the fan)
	var n_gap := int(spec.get("gap_count", 3))
	var gaps: Array = []
	for g in range(n_gap):
		var g0 := TAU * (float(g) + 0.15 + 0.55 * BaseShapeBuilder._h01(rk + 7.0 + float(g) * 3.3)) / float(n_gap)
		gaps.append([g0, g0 + 0.07 + 0.11 * BaseShapeBuilder._h01(rk + 13.0 + float(g) * 5.1)])
	# the main tube: arc chunks between gaps, each sub-split with its own lumpy radius
	var seg := 56
	var arc_pts: Array = []
	for i in range(seg + 1):
		var th := TAU * float(i) / float(seg)
		if _in_gap(th, gaps):
			if arc_pts.size() >= 2:
				_emit_lumpy_arc(bone, arc_pts, tube, rk)
			arc_pts = []
			continue
		var bulge := 1.0 + 0.10 * (BaseShapeBuilder._h01(rk + 23.0 + float(i) * 2.7) - 0.5)
		var zoff := tube * 0.5 * (BaseShapeBuilder._h01(rk + 29.0 + float(i) * 4.1) - 0.5)
		arc_pts.append(Vector3(cos(th) * rr * bulge, sin(th) * rr * bulge, zoff))
	if arc_pts.size() >= 2:
		_emit_lumpy_arc(bone, arc_pts, tube, rk)
	# strands bridging each gap (the growth never fully lets go) + the pale inner ribbon
	for g_v in gaps:
		var ga := float((g_v as Array)[0]) - 0.04
		var gb := float((g_v as Array)[1]) + 0.04
		for s_i in range(2):
			var pts: Array = []
			var bow := (0.88 + 0.10 * float(s_i)) + 0.06 * BaseShapeBuilder._h01(rk + 37.0 + float(s_i))
			for i2 in range(7):
				var t2 := float(i2) / 6.0
				var th2 := lerpf(ga, gb, t2)
				var rr2 := rr * lerpf(1.0, bow, sin(t2 * PI))
				pts.append(Vector3(cos(th2) * rr2, sin(th2) * rr2, tube * (0.4 - 0.8 * float(s_i))))
			BaseShapeBuilder._tube(lav, pts, tube * 0.22, 5)
	var ribbon: Array = []
	for i3 in range(seg + 1):
		var th3 := TAU * float(i3) / float(seg)
		ribbon.append(Vector3(cos(th3) * (rr - tube * 0.55), sin(th3) * (rr - tube * 0.55), -tube * 0.35))
	BaseShapeBuilder._tube(lav, ribbon, tube * 0.16, 4)
	# the tooth row: inward spikes along the bore (skipped across gaps)
	var t_every := float(spec.get("teeth_every", 0.13))
	var n_teeth := int(TAU / t_every)
	for ti in range(n_teeth):
		var tha := TAU * float(ti) / float(n_teeth)
		if _in_gap(tha, gaps):
			continue
		var dir_in := -Vector3(cos(tha), sin(tha), 0)
		var base_p := Vector3(cos(tha) * (rr - tube * 0.7), sin(tha) * (rr - tube * 0.7), 0)
		var t_len := teeth * (0.8 + 0.4 * BaseShapeBuilder._h01(rk + 43.0 + float(ti) * 1.7))
		_emit_spike(bone, base_p, dir_in, tube * 0.30, t_len)
	# nodules straddling the tube
	var n_nod := 8 + int(BaseShapeBuilder._h01(rk + 53.0) * 6.9)
	for ni in range(n_nod):
		var thn := TAU * BaseShapeBuilder._h01(rk + 59.0 + float(ni) * 8.3)
		if _in_gap(thn, gaps):
			continue
		var np := Vector3(cos(thn) * rr, sin(thn) * rr, 0)
		var ns := tube * (0.55 + 0.5 * BaseShapeBuilder._h01(rk + 67.0 + float(ni) * 3.9))
		BaseShapeBuilder._emit_box_st(bone, np + Vector3(0, 0, tube * 0.4 * (BaseShapeBuilder._h01(rk + 71.0 + float(ni)) - 0.5)),
			Vector3(ns, ns * 0.8, ns * 0.9))
	bone.generate_normals()
	lav.generate_normals()
	# alternate spin directions, slower toward the core — wheels within wheels, out of phase
	var spin := (0.05 + 0.02 * float(k % 3)) * (1.0 if k % 2 == 0 else -1.0)
	return {"bone": bone.commit(), "lav": lav.commit(), "basis": _ring_basis(row), "spin": spin}

static func _in_gap(th: float, gaps: Array) -> bool:
	var t := fposmod(th, TAU)
	for g_v in gaps:
		if t >= float((g_v as Array)[0]) and t <= float((g_v as Array)[1]):
			return true
	return false

## An arc polyline as 2-3 tube chunks with individually lumped radii (organic, never machined).
static func _emit_lumpy_arc(st: SurfaceTool, pts: Array, tube: float, rk: float) -> void:
	var n := pts.size()
	var chunks := maxi(1, n / 9)
	var per := int(ceil(float(n) / float(chunks)))
	var i := 0
	var ci := 0
	while i < n - 1:
		var sub := pts.slice(i, mini(n, i + per + 1))
		var t_r := tube * (0.82 + 0.4 * BaseShapeBuilder._h01(rk + 83.0 + float(ci) * 5.7))
		BaseShapeBuilder._tube(st, sub, t_r, 7)
		i += per
		ci += 1

## A four-sided spike from base ring to tip, pointing along `dir` (the protein tooth).
static func _emit_spike(st: SurfaceTool, base_p: Vector3, dir: Vector3, w: float, l: float) -> void:
	var d := dir.normalized()
	var u := d.cross(Vector3(0, 0, 1))
	if u.length() < 0.1:
		u = d.cross(Vector3(0, 1, 0))
	u = u.normalized()
	var v := d.cross(u).normalized()
	var tip := base_p + d * l
	var c0 := base_p + u * w
	var c1 := base_p + v * w
	var c2 := base_p - u * w
	var c3 := base_p - v * w
	for tri in [[c0, c1, tip], [c1, c2, tip], [c2, c3, tip], [c3, c0, tip], [c1, c0, c2], [c3, c2, c0]]:
		var t := tri as Array
		st.add_vertex(t[0] as Vector3)
		st.add_vertex(t[1] as Vector3)
		st.add_vertex(t[2] as Vector3)

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st
