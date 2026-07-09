class_name LedgeBuilder
extends RefCounted

## LEDGE TREATMENTS for a tiered ("cake") base. The flat top ring of each lower tier is a LEDGE; the
## `ledge_treatments` spec param decorates them. It is an Array of modes applied to EVERY ledge:
##   "railings" — a ring of algorithm-4 cards (pixel-art railing texture, alpha-scissor) along the edge.
##   "planters" — spaced planter boxes around the ledge with a greenery clump on each.
##   "greenery" — a denser ring of greenery clumps (a low hedge), no box.
## An empty/absent list is a FLAT-LEDGED building (bare rings) — the default. `build()` returns geometry
## keyed by material role so the caller assigns the railing / stone / foliage materials:
##   {rails: ArrayMesh (UV'd for the railing texture), planters: ArrayMesh, greenery: ArrayMesh}
## Geometry only lives here; tier geometry comes from BaseShapeBuilder.tier_ledges(spec).

const RAIL_H := 0.5          # ledge railings are lower than a full balcony rail
const RAIL_SEGS := 24        # cards around a drum ledge (polygon approximation of the ring)
const RAIL_TILE := 0.4       # one railing tile per ~0.4 m of run
const PLANTER_W := 0.5
const PLANTER_H := 0.32
const PLANTER_D := 0.3
const BLOB_R := 0.26

static func build(spec: Dictionary, _overrides: Dictionary = {}) -> Dictionary:
	var modes: Array = spec.get("ledge_treatments", [])
	var ledges: Array = BaseShapeBuilder.tier_ledges(spec)
	if modes.is_empty() or ledges.is_empty():
		return {}
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planters := SurfaceTool.new()
	planters.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := SurfaceTool.new()
	green.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_rail := false
	var any_planter := false
	var any_green := false
	for ledge in ledges:
		if "railings" in modes:
			_railing(rails, ledge)
			any_rail = true
		if "planters" in modes:
			_clumps(planters, green, ledge, 8, true)
			any_planter = true
			any_green = true
		if "greenery" in modes:
			_clumps(planters, green, ledge, 16, false)
			any_green = true
	var out: Dictionary = {}
	if any_rail:
		rails.generate_normals()
		out["rails"] = rails.commit()
	if any_planter:
		planters.generate_normals()
		out["planters"] = planters.commit()
	if any_green:
		green.generate_normals()
		out["greenery"] = green.commit()
	return out

# --- railing ring / runs -------------------------------------------------------------------------

static func _railing(st: SurfaceTool, ledge: Dictionary) -> void:
	var y := float(ledge["y"])
	if bool(ledge.get("cyl", false)):
		var r := float(ledge["r_outer"]) - 0.06     # just inside the drum edge
		for i in range(RAIL_SEGS):
			var a0 := TAU * float(i) / float(RAIL_SEGS)
			var a1 := TAU * float(i + 1) / float(RAIL_SEGS)
			_card(st, Vector3(r * cos(a0), y, r * sin(a0)), Vector3(r * cos(a1), y, r * sin(a1)))
	else:
		var outer: Vector2 = ledge["outer"]
		var hx := outer.x * 0.5 - 0.06
		var hz := outer.y * 0.5 - 0.06
		# 4 straight runs along the rectangle perimeter
		_card_run(st, Vector3(-hx, y, hz), Vector3(hx, y, hz))
		_card_run(st, Vector3(hx, y, -hz), Vector3(-hx, y, -hz))
		_card_run(st, Vector3(-hx, y, -hz), Vector3(-hx, y, hz))
		_card_run(st, Vector3(hx, y, hz), Vector3(hx, y, -hz))

static func _card_run(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	# subdivide a straight run so a long edge tiles the railing texture evenly
	var segs := maxi(1, int(round(a.distance_to(b) / (RAIL_TILE * 4.0))))
	for i in range(segs):
		var p0 := a.lerp(b, float(i) / float(segs))
		var p1 := a.lerp(b, float(i + 1) / float(segs))
		_card(st, p0, p1)

# One vertical railing card from base p0->p1, up RAIL_H. UV v=0 top / v=1 base, u tiles across the run.
static func _card(st: SurfaceTool, p0: Vector3, p1: Vector3) -> void:
	var ur := maxf(1.0, p0.distance_to(p1) / RAIL_TILE)
	var t0 := p0 + Vector3(0.0, RAIL_H, 0.0)
	var t1 := p1 + Vector3(0.0, RAIL_H, 0.0)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
	st.set_uv(Vector2(ur, 1.0)); st.add_vertex(p1)
	st.set_uv(Vector2(ur, 0.0)); st.add_vertex(t1)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
	st.set_uv(Vector2(ur, 0.0)); st.add_vertex(t1)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(t0)

# --- planters + greenery -------------------------------------------------------------------------

static func _clumps(box_st: SurfaceTool, green_st: SurfaceTool, ledge: Dictionary, count: int, with_box: bool) -> void:
	var y := float(ledge["y"])
	for i in range(count):
		var frac := (float(i) + 0.5) / float(count)
		var sample := _ledge_center_sample(ledge, frac)
		var pos: Vector3 = sample["pos"]
		pos.y = y
		var outward: Vector3 = sample["outward"]
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		if with_box:
			_oriented_box(box_st, pos + Vector3(0.0, PLANTER_H * 0.5, 0.0), outward, tangent,
				PLANTER_W * 0.5, PLANTER_H * 0.5, PLANTER_D * 0.5)
			_blob(green_st, pos + Vector3(0.0, PLANTER_H + BLOB_R * 0.4, 0.0), BLOB_R)
		else:
			_blob(green_st, pos + Vector3(0.0, BLOB_R * 0.5, 0.0), BLOB_R * 1.1)

# A point on the CENTRE line of the ledge ring (between inner and outer edge), + its outward normal.
static func _ledge_center_sample(ledge: Dictionary, frac: float) -> Dictionary:
	if bool(ledge.get("cyl", false)):
		var rc := (float(ledge["r_outer"]) + float(ledge["r_inner"])) * 0.5
		var a := TAU * frac
		return {"pos": Vector3(rc * cos(a), 0.0, rc * sin(a)), "outward": Vector3(cos(a), 0.0, sin(a))}
	# box: march the rectangle perimeter at the ledge centre ring
	var outer: Vector2 = ledge["outer"]
	var inner: Vector2 = ledge["inner"]
	var hx := (outer.x + inner.x) * 0.25
	var hz := (outer.y + inner.y) * 0.25
	var t := frac * 4.0
	var side := int(floor(t)) % 4
	var f: float = t - floor(t)
	match side:
		0: return {"pos": Vector3(lerp(-hx, hx, f), 0.0, hz), "outward": Vector3(0, 0, 1)}
		1: return {"pos": Vector3(hx, 0.0, lerp(hz, -hz, f)), "outward": Vector3(1, 0, 0)}
		2: return {"pos": Vector3(lerp(hx, -hx, f), 0.0, -hz), "outward": Vector3(0, 0, -1)}
		_: return {"pos": Vector3(-hx, 0.0, lerp(-hz, hz, f)), "outward": Vector3(-1, 0, 0)}

# An oriented box (planter) — 8 corners from centre + half-extents along (tangent, up, outward).
static func _oriented_box(st: SurfaceTool, c: Vector3, o: Vector3, t: Vector3, hw: float, hh: float, hd: float) -> void:
	var tw := t * hw
	var uh := Vector3.UP * hh
	var od := o * hd
	var p000 := c - tw - uh - od
	var p100 := c + tw - uh - od
	var p110 := c + tw + uh - od
	var p010 := c - tw + uh - od
	var p001 := c - tw - uh + od
	var p101 := c + tw - uh + od
	var p111 := c + tw + uh + od
	var p011 := c - tw + uh + od
	_quad(st, p001, p101, p111, p011)   # outward (+o)
	_quad(st, p100, p000, p010, p110)   # inward (-o)
	_quad(st, p101, p100, p110, p111)   # +t
	_quad(st, p000, p001, p011, p010)   # -t
	_quad(st, p011, p111, p110, p010)   # top
	_quad(st, p000, p100, p101, p001)   # bottom

# A low-poly greenery clump: a squashed octahedron (6 verts / 8 faces), reads as a leafy mound.
static func _blob(st: SurfaceTool, c: Vector3, r: float) -> void:
	var rx := r
	var ry := r * 0.72
	var xp := c + Vector3(rx, 0, 0)
	var xn := c - Vector3(rx, 0, 0)
	var zp := c + Vector3(0, 0, rx)
	var zn := c - Vector3(0, 0, rx)
	var yp := c + Vector3(0, ry, 0)
	var yn := c - Vector3(0, ry * 0.5, 0)
	_tri(st, yp, xp, zp); _tri(st, yp, zp, xn); _tri(st, yp, xn, zn); _tri(st, yp, zn, xp)
	_tri(st, yn, zp, xp); _tri(st, yn, xn, zp); _tri(st, yn, zn, xn); _tri(st, yn, xp, zn)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
