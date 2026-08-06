class_name HubShapeCoordMap
extends RefCounted

## A coord_map that wraps a flat stretch grid around ANY closed SHAPE's perimeter, descending — the generalisation
## of SpiralCoordMap (which is the circle case). The shape is a PARAMETER: a circle, a rectangle, or an arbitrary
## polygon. The flat data grid stays flat (grid/movement/detection unchanged); only the world render + click inverse
## warp. The player walks a linear grid; the world wraps `turns` times around the chosen shape, dropping each loop,
## so it reads as a hub (the shape) with the stretch coiling around it. Every shape is treated as a POLYGON (a
## circle = a fine N-gon), so ONE code path handles all of them.
##
## Flat frame: p.x = progress along the level (s = p.x - s_offset), p.z = lateral (lane = p.z - lane_center),
## p.y = deck height (its offset above the base is preserved as a lift, so upper floors stack).

var center := Vector3.ZERO
var y0 := 0.45              # world height at s = 0 (top of the descent)
var kclimb := -0.15        # world height per unit s — NEGATIVE (descends), so a loop-ahead cell sits below
var s_offset := 0.0
var lane_center := 0.0
var perimeter := 1.0       # arc-length of one loop around the shape (in the same units as s / cells)
var shape_id := "circle"
# The BASE: a flat central floor (the shape as a floor) at y0 that the ENTRY shelter connects to. It occupies the
# flat cells BEFORE the perimeter start (s < 0), mapped to a flat rectangle at the hub centre — NOT warped, so the
# player rests + walks on it, then steps out onto the descending deck. base_span = 0 -> no base (plain hub/spiral).
var base_span := 0.0       # flat-s extent of the base region (cells before s=0)
var base_half_lane := 0.0  # lateral half-width of the base rectangle (world units, = deck half-width)
# Edges of the (centred) shape polygon in the XZ plane: each {a:Vector2, b:Vector2, len:float, cum:float,
# tan:Vector2 (unit a->b), nrm:Vector2 (unit outward)}.
var _edges: Array = []

const MIN_INRADIUS_PAD := 4.0   # keep the shape big enough that the inner deck stays well clear of the centre

## Build from a unified_grid_v1 grid + a shape descriptor:
##   {type:"circle"} | {type:"rect", aspect:float} | {type:"polygon", points:[[x,y],...] (centred, any scale)}
## `turns` ~ loops around the shape; `descent_per_turn` = world-units dropped per loop.
static func from_grid(grid_data: Dictionary, shape := {}, turns := 0.0, descent_per_turn := 6.0, base_y := 0.45, base_cells := 0) -> HubShapeCoordMap:
	var m := HubShapeCoordMap.new()
	var origin: Array = grid_data.get("origin", [0.0, 0.45, 0.0])
	var cs := float(grid_data.get("cell_size", 1.0))
	# Build from the SPINE grid: its width IS the perimeter length. The base is a SEPARATE flat region the chunk
	# prepends at world x < origin.x, so s = 0 (the entry / perimeter start) stays at the spine's origin.x and base
	# cells (world x < origin.x) map to s < 0. r0/height therefore size off the real spine, not base+branches.
	var w := float(int(grid_data.get("width", 1))) * cs
	var h := float(int(grid_data.get("height", 1))) * cs
	var t: float = turns if turns > 0.0 else clampf(w / 40.0, 1.0, 2.5)
	m.base_span = float(base_cells) * cs
	m.base_half_lane = h * 0.5
	m.s_offset = float(origin[0])
	m.lane_center = float(origin[2]) + h * 0.5
	m.y0 = base_y
	m.shape_id = str(shape.get("type", "circle"))

	# Target perimeter so s over [0, w] wraps ~t times; build the unit shape, scale it to that perimeter, then grow
	# it if its inradius is too small to hold the deck's lateral half-width (h/2) without crossing the centre.
	var target_perimeter := w / maxf(1.0, t)
	var pts := _unit_shape_points(shape)
	# Round sharp corners (Chaikin): a smooth perimeter has no sharp outward WEDGE between two edges, so every deck
	# point sits cleanly in one edge's slab and the click inverse is exact. A fine circle N-gon is already smooth.
	# Fewer sides = sharper corners = more rounding needed so a fixed-width deck wraps them without pinching inside.
	if pts.size() < 6:
		pts = _round_corners(pts, 4)
	elif pts.size() < 20:
		pts = _round_corners(pts, 3)
	var scaled := _scale_to_perimeter(pts, target_perimeter)
	var inradius := _inradius(scaled)
	var need := h * 0.5 + MIN_INRADIUS_PAD
	if inradius < need and inradius > 0.001:
		var k := need / inradius
		for i in range(scaled.size()):
			scaled[i] *= k
	m._build_edges(scaled)
	m.perimeter = m._total_perimeter()
	# Recompute the effective turn count from the final perimeter, so the descent-per-turn stays honest.
	var eff_turns := w / maxf(1.0, m.perimeter)
	m.kclimb = -(descent_per_turn * eff_turns / maxf(1.0, w))
	return m

# --- shape construction ---------------------------------------------------------------------------------------

static func _unit_shape_points(shape: Dictionary) -> Array:
	var type := str(shape.get("type", "circle"))
	match type:
		"rect":
			var aspect := maxf(0.2, float(shape.get("aspect", 1.6)))   # width:height
			var hx := aspect
			var hz := 1.0
			return [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
		"polygon":
			var out: Array = []
			for p in shape.get("points", []):
				out.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
			if out.size() >= 3:
				return _center_points(out)
			# fall through to circle if the polygon is degenerate
		"triangle":
			return _ngon(3)
		"pentagon":
			return _ngon(5)
		"hexagon":
			return _ngon(6)
	# circle: a fine N-gon reads as a smooth circle through the same polygon code path.
	return _ngon(int(shape.get("sides", 32)))

static func _ngon(n: int) -> Array:
	var sides := maxi(3, n)
	var out: Array = []
	for i in range(sides):
		var a := TAU * float(i) / float(sides) - PI * 0.5
		out.append(Vector2(cos(a), sin(a)))
	return out

static func _center_points(pts: Array) -> Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var out: Array = []
	for p in pts:
		out.append(p - c)
	return out

## Chaikin corner-cutting: replace each vertex with two points 1/4 and 3/4 along its edges, rounding sharp corners
## into short smooth runs. Keeps the overall shape (a rounded rectangle still reads as a rectangle) while removing
## the sharp wedges that make the perimeter inverse ambiguous.
static func _round_corners(pts: Array, iterations: int) -> Array:
	var cur: Array = pts
	for _it in range(iterations):
		var out: Array = []
		var n := cur.size()
		for i in range(n):
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[(i + 1) % n]
			out.append(a * 0.75 + b * 0.25)
			out.append(a * 0.25 + b * 0.75)
		cur = out
	return cur

static func _scale_to_perimeter(pts: Array, target: float) -> Array:
	var per := 0.0
	for i in range(pts.size()):
		per += (pts[(i + 1) % pts.size()] - pts[i]).length()
	if per < 0.0001:
		return pts
	var k := target / per
	var out: Array = []
	for p in pts:
		out.append(p * k)
	return out

static func _inradius(pts: Array) -> float:
	# Min distance from the centroid (origin, since centred) to any edge segment.
	var best := 1e20
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var ab := b - a
		var len_sq := ab.length_squared()
		var tproj := 0.0 if len_sq < 1e-9 else clampf((-a).dot(ab) / len_sq, 0.0, 1.0)
		var d := (a + ab * tproj).length()
		best = minf(best, d)
	return best

func _build_edges(pts: Array) -> void:
	_edges.clear()
	var cum := 0.0
	# Determine winding to get an OUTWARD normal (positive signed area = CCW).
	var area := 0.0
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var seg := b - a
		var l := seg.length()
		if l < 1e-6:
			continue
		var tan := seg / l
		# Outward normal: for CCW winding the outward normal is (tan.y, -tan.x); flip for CW.
		var nrm := Vector2(tan.y, -tan.x) if ccw else Vector2(-tan.y, tan.x)
		_edges.append({"a": a, "b": b, "len": l, "cum": cum, "tan": tan, "nrm": nrm})
		cum += l

func _total_perimeter() -> float:
	var p := 0.0
	for e in _edges:
		p += float(e["len"])
	return p

# --- perimeter sampling ---------------------------------------------------------------------------------------

## Sample the perimeter at arc-length t (wrapped into [0, perimeter)): returns {pt:Vector2, tan:Vector2, nrm:Vector2}.
func _sample(t: float) -> Dictionary:
	if _edges.is_empty():
		return {"pt": Vector2.ZERO, "tan": Vector2(1, 0), "nrm": Vector2(0, 1)}
	var tt := fmod(t, perimeter)
	if tt < 0.0:
		tt += perimeter
	for e in _edges:
		var start := float(e["cum"])
		var l := float(e["len"])
		if tt <= start + l or e == _edges[_edges.size() - 1]:
			var local := clampf(tt - start, 0.0, l)
			var a: Vector2 = e["a"]
			var tan: Vector2 = e["tan"]
			return {"pt": a + tan * local, "tan": tan, "nrm": e["nrm"]}
	var last: Dictionary = _edges[_edges.size() - 1]
	return {"pt": last["b"], "tan": last["tan"], "nrm": last["nrm"]}

func arc_pos(s: float, lane: float) -> Vector3:
	var samp := _sample(s)
	var pt: Vector2 = samp["pt"]
	var nrm: Vector2 = samp["nrm"]
	var planar := pt + nrm * lane
	return Vector3(center.x + planar.x, y0 + s * kclimb, center.z + planar.y)

func basis_at(s: float) -> Basis:
	var samp := _sample(s)
	var nrm: Vector2 = samp["nrm"]
	var tan: Vector2 = samp["tan"]
	return Basis(Vector3(nrm.x, 0.0, nrm.y), Vector3.UP, Vector3(tan.x, 0.0, tan.y))

## Warped world -> flat data. The correct edge is the one whose perpendicular SLAB contains the point (its
## projection falls WITHIN the segment, not past an endpoint) — nearest-by-distance alone mis-picks an adjacent
## edge when `lane` is larger than the edge is long. Among slab edges take the least perpendicular distance; only
## if the point sits in no slab (a sharp corner region) fall back to the nearest endpoint. Then pick the loop
## (turn) whose height matches world Y — the descent makes each loop a distinct height, so s is exact.
func world_to_arc(world: Vector3) -> Dictionary:
	var planar := Vector2(world.x - center.x, world.z - center.z)
	var best_dist := 1e20
	var best_arc := 0.0
	var best_lane := 0.0
	var have_slab := false
	var corner_dist := 1e20
	var corner_arc := 0.0
	var corner_lane := 0.0
	for e in _edges:
		var a: Vector2 = e["a"]
		var tan: Vector2 = e["tan"]
		var nrm: Vector2 = e["nrm"]
		var l := float(e["len"])
		var v := planar - a
		var along_raw := v.dot(tan)
		var along := clampf(along_raw, 0.0, l)
		var perp := planar - (a + tan * along)
		var dist := perp.length()
		var arc := float(e["cum"]) + along
		var lane := perp.dot(nrm)
		if along_raw >= -0.001 and along_raw <= l + 0.001:
			if dist < best_dist:
				best_dist = dist; best_arc = arc; best_lane = lane; have_slab = true
		elif dist < corner_dist:
			corner_dist = dist; corner_arc = arc; corner_lane = lane
	if not have_slab:
		best_arc = corner_arc
		best_lane = corner_lane
	# Refine: the edge estimate can be off by ~a corner region on sharp shapes. Slide the arc a little either way to
	# the perimeter point genuinely closest to the world point (the forward offsets purely along the normal, so the
	# closest perimeter point IS the true arc); read lane as the signed normal distance there. Makes it exact.
	var best_d := 1e20
	var refined := best_arc
	var refined_nrm := Vector2(0, 1)
	var refined_pt := Vector2.ZERO
	var step := 0.25
	var a0 := best_arc - 3.0
	var steps := int(6.0 / step) + 1
	for i in range(steps):
		var arc := a0 + float(i) * step
		var samp := _sample(arc)
		var spt: Vector2 = samp["pt"]
		var d: float = (planar - spt).length()
		if d < best_d:
			best_d = d
			refined = arc
			refined_nrm = samp["nrm"]
			refined_pt = samp["pt"]
	best_arc = refined
	best_lane = (planar - refined_pt).dot(refined_nrm)
	var s_h := (world.y - y0) / kclimb if absf(kclimb) > 1e-6 else best_arc
	var turn := roundf((s_h - best_arc) / maxf(0.001, perimeter))
	return {"s": best_arc + turn * perimeter, "lane": best_lane}

func period_s() -> float:
	return perimeter

# --- the base: a flat central floor before the perimeter (s < 0) ----------------------------------------------

## The base is a flat rectangle at the hub centre at y0. It joins the deck SEAMLESSLY at s = 0: the entry cross-
## section (radial, along the entry normal) is continued backward along the entry TANGENT, so a member walks off
## the base straight onto the deck. lane keeps the deck's radial meaning; s (negative) runs backward off the rim.
func _base_world(s: float, lane: float) -> Vector3:
	var e := _sample(0.0)
	var pt: Vector2 = e["pt"]
	var nrm: Vector2 = e["nrm"]
	var tan: Vector2 = e["tan"]
	var planar := pt + nrm * lane + tan * s   # s<0 -> backward along the entry tangent, flat
	return Vector3(center.x + planar.x, y0, center.z + planar.y)

func _base_data(world: Vector3) -> Dictionary:
	var e := _sample(0.0)
	var pt: Vector2 = e["pt"]
	var nrm: Vector2 = e["nrm"]
	var tan: Vector2 = e["tan"]
	var v := Vector2(world.x - center.x, world.z - center.z) - pt
	return {"s": v.dot(tan), "lane": v.dot(nrm)}

## Is this flat point (s already offset) in the base region?
func _is_base_s(s: float) -> bool:
	return base_span > 0.0 and s < 0.0

# --- coord_map interface --------------------------------------------------------------------------------------

func to_world(p: Vector3) -> Vector3:
	var s := p.x - s_offset
	if _is_base_s(s):
		return _base_world(s, p.z - lane_center) + Vector3.UP * (p.y - y0)
	return arc_pos(s, p.z - lane_center) + Vector3.UP * (p.y - y0)

func to_data(w: Vector3) -> Vector3:
	return to_data_on_surface(w, y0)


## Exact inverse for a point on a known data-space floor. Upper floors are a
## vertical lift of the base/perimeter mapping; remove that lift before either
## base detection or the height-selected perimeter inverse runs.
func to_data_on_surface(w: Vector3, data_y: float) -> Vector3:
	var base_world := w - Vector3.UP * (data_y - y0)
	# Base if the world point sits on the flat base rectangle (near y0, backward off the entry rim); else perimeter.
	if base_span > 0.0:
		var b := _base_data(base_world)
		if float(b["s"]) < 0.0 and float(b["s"]) > -base_span - 1.0 and absf(float(b["lane"])) < base_half_lane + 1.0 and absf(base_world.y - y0) < 1.5:
			return Vector3(float(b["s"]) + s_offset, data_y, float(b["lane"]) + lane_center)
	var r := world_to_arc(base_world)
	return Vector3(float(r["s"]) + s_offset, data_y, float(r["lane"]) + lane_center)

func to_basis(p: Vector3) -> Basis:
	var s := p.x - s_offset
	if _is_base_s(s):
		var e := _sample(0.0)
		var nrm: Vector2 = e["nrm"]
		var tan: Vector2 = e["tan"]
		return Basis(Vector3(nrm.x, 0.0, nrm.y), Vector3.UP, Vector3(tan.x, 0.0, tan.y))
	return basis_at(s)

func to_xform(p: Vector3) -> Transform3D:
	var s := p.x - s_offset
	if _is_base_s(s):
		return Transform3D(to_basis(p), _base_world(s, p.z - lane_center) + Vector3.UP * (p.y - y0))
	return Transform3D(basis_at(s), arc_pos(s, p.z - lane_center) + Vector3.UP * (p.y - y0))
