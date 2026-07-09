class_name BaseShapeBuilder
extends RefCounted

## BASE SHAPE BUILDER — the ground floor of the district architecture, built bottom-up.
##
## Each district building starts as ONE low-poly base primitive that matches the reference plate's
## overall MASSING — nothing more. Detail (lobes, drums, domes, honeycomb facades, signage) is
## layered on in later steps; this tool only draws the silhouette-honest base solid so we can see the
## proportions land before committing to detail.
##
##   Plumbing Power Project  ->  a squat CYLINDER  (the bulbous verdigris drum tower)
##   Honeycomb Cooperative   ->  a tall BOX         (the apartment block / rectangular prism)
##
## Keep it low-poly and honest to the reference proportions. Grow it one primitive at a time.

const SHAPE_CYLINDER := "cylinder"
const SHAPE_BOX := "box"
const SHAPE_COMPOSITE := "composite"   # a small assembly of primitives (e.g. the Open Files fin cluster)

## Ordered list the showcase walks. Add a building here as we bring each one in.
const BUILDINGS := [
	"plumbing_power", "honeycomb_cooperative", "beacon_hill", "open_files", "hypelines",
	"greenfields", "ancourage", "bulwark_wharf", "cleanstreets", "zone3", "tiered_hall", "tiered_terrace",
]

## Reference-derived proportions. Dimensions are metres; the base sits on y=0.
const SPECS := {
	"plumbing_power": {
		"title": "Plumbing Power Project",
		"shape": SHAPE_CYLINDER,
		# Squat drum — the reference tower is roughly 1.3x as tall as its base is wide (H ~= 2.5 * r).
		"radius": 2.2,
		"height": 5.6,
		"color": Color(0.33, 0.43, 0.43),   # weathered verdigris copper
		"tile": "facility_metal",
		"lattice": "",                      # facade (wheels/slits/dome) is later; draped pipes for now
		"pipes": true,                      # the plate's draped conduit runs
	},
	"honeycomb_cooperative": {
		"entrances": {"reserve_margin": 0.2},   # storey-scale blobs: a fat clearance would gut the facade
		"title": "Honeycomb Cooperative",
		"shape": SHAPE_BOX,
		# Tall apartment block; footprint a touch deeper than it is wide (~1.8x taller than wide).
		"size": Vector3(4.5, 8.0, 5.5),
		"color": Color(0.60, 0.58, 0.48),   # pale cast-stone facade
		"tile": "facility_metal",
		"lattice": "honeyframe",            # rounded-cell facade frame + lit panes
		"pipes": true,                      # rust/conduit tangle down the flank
	},
	"beacon_hill": {
		"title": "Beacon Hill",
		"shape": SHAPE_CYLINDER,
		# Tall verdigris bell-tower (the Reading Room); a cylinder base, the bell taper is a later pass.
		"radius": 2.4,
		"height": 7.2,
		"color": Color(0.32, 0.42, 0.40),   # verdigris tiled stone
		"tile": "facility_metal",
		"lattice": "tracery",               # pointed-arch (lancet) window wall + lit glass behind
		"bays": 7,                          # bay width 2.15 — the door assembly (~2.0) fits inside a bay
		"entrances": {"side_count_min": 1, "side_count_max": 1},   # plate: main door + ONE enforcement door
	},
	# --- The remaining districts: existence + a base primitive established so Fable only owns the
	# --- lattices/complex massing. Simple massing here; the notes flag what is Fable's.
	"open_files": {
		"title": "The Open Files Initiative",
		"shape": SHAPE_COMPOSITE,           # radial cluster of tall rect-prism FINS, each gabled
		"composite": "open_files_fins",
		"size": Vector3(5.6, 9.0, 5.6),
		"color": Color(0.31, 0.35, 0.37),   # dark steel-blue with rust + teal server glow
		"tile": "facility_metal",
		"lattice": "",                      # lattice deferred — see FABLE_TASKLIST (extruded-face channels)
	},
	"hypelines": {
		"title": "The Hypelines",
		"shape": SHAPE_CYLINDER,            # PLACEHOLDER drum; real = stacked-bulb blob + SPLIT base (Fable)
		"radius": 2.6, "height": 6.2,
		"color": Color(0.32, 0.38, 0.34),   # verdigris-rust
		"tile": "facility_metal",
		"lattice": "", "pipes": true,       # the radiating viaducts read as heavy pipes
	},
	"greenfields": {
		"title": "Greenfields Collective",
		"shape": SHAPE_BOX,                 # rounded barrel corners are a Fable detail
		"size": Vector3(5.2, 6.4, 5.0),
		"color": Color(0.60, 0.64, 0.56),   # pale cast-stone / teal
		"tile": "facility_metal",
		"lattice": "balconies",             # wrapping per-floor balconies (Fable — beam+curve spec)
	},
	"ancourage": {
		"title": "Ancourage",
		"shape": SHAPE_CYLINDER,            # squat drum; the DOME cap + pipe drainage are Fable
		"radius": 2.7, "height": 3.0,
		"color": Color(0.34, 0.40, 0.38),
		"tile": "facility_metal",
		"lattice": "", "pipes": true,
	},
	"bulwark_wharf": {
		"title": "Bulwark Wharf",
		"shape": SHAPE_BOX,                 # gatehouse; corner turrets + rose windows + barrier wall = Fable
		"size": Vector3(4.2, 5.2, 3.6),
		"color": Color(0.40, 0.44, 0.48),
		"tile": "facility_metal",
		"lattice": "",
	},
	"cleanstreets": {
		"title": "The Cleanstreets Initiative",
		"shape": SHAPE_BOX,                 # wide low CANOPY massing; splayed tree-columns = Fable
		"size": Vector3(7.0, 2.8, 4.2),
		"color": Color(0.52, 0.56, 0.54),
		"tile": "facility_metal",
		"lattice": "",
	},
	"zone3": {
		"title": "Zone-3 Eroded Ruin",
		"shape": SHAPE_BOX,                 # faceted block; the amyloid-drip decay is Fable
		"size": Vector3(4.0, 5.4, 4.0),
		"color": Color(0.34, 0.36, 0.34),
		"tile": "facility_metal",
		"lattice": "",
	},
	"tiered_hall": {
		"title": "Tiered Hall",
		"shape": SHAPE_CYLINDER,            # a "cake" that shrinks upward (tiers) -> exposed ledges
		"radius": 2.6, "height": 9.0,
		"tiers": 3, "tier_inset": 0.16,
		"color": Color(0.56, 0.51, 0.43),
		"tile": "facility_metal",
		"lattice": "tracery",               # runs PER vertical drum band
		"ledge_treatments": ["railings", "planters"],   # flat rings get an edge rail + planter boxes
	},
	"tiered_terrace": {
		"title": "Tiered Terrace",
		"shape": SHAPE_BOX,                 # the BOX "cake": honeyframe per tier, crown only on the roof
		"size": Vector3(4.2, 8.4, 4.2),
		"tiers": 3, "tier_inset": 0.16,
		"color": Color(0.60, 0.55, 0.46),
		"tile": "facility_metal",
		"lattice": "honeyframe",
		"ledge_treatments": ["railings", "greenery"],   # edge rail + a low greenery hedge
	},
}

const CYL_SEGMENTS := 24   # drum facets — smooth enough that a wrapped lattice sits flush, still low-poly
const LEDGE_MIN_WIDTH := 0.12   # a tier ledge narrower than this (from clamped tiers) is not treatable

## Resolve a building to its spec, plus convenience fields for placement/labelling. The seed argument
## is accepted for parity with the other generation previews; base shapes are deterministic (nothing
## to reroll yet), so it is ignored until we add varied detail.
static func generate(kind: String, _seed_value: int = 0) -> Dictionary:
	var key := kind if SPECS.has(kind) else str(BUILDINGS[0])
	var spec: Dictionary = (SPECS[key] as Dictionary).duplicate(true)
	spec["kind"] = key
	match str(spec["shape"]):
		SHAPE_CYLINDER:
			spec["height_total"] = float(spec["height"])
			spec["footprint"] = float(spec["radius"]) * 2.0
		_:
			var s: Vector3 = spec["size"]
			spec["height_total"] = s.y
			spec["footprint"] = maxf(s.x, s.z)
	return spec

## The base solid, an ArrayMesh whose base rests on y=0 so it seats on a plinth/ground.
## `reserved` = the door regions (from LatticeBuilder.entrances) — real OPENINGS are cut into the wall
## and framed by a recessed pocket, so the door parts don't z-fight a solid wall.
static func base_mesh(spec: Dictionary, reserved: Array = []) -> ArrayMesh:
	var recess := float(spec.get("door_recess", 0.5))
	var tiers := maxi(1, int(spec.get("tiers", 1)))          # >1 = a stacked "cake" that shrinks upward
	var inset := float(spec.get("tier_inset", 0.16))         # each tier's footprint fraction lost per level
	match str(spec.get("shape", SHAPE_BOX)):
		SHAPE_CYLINDER:
			var r := float(spec.get("radius", 2.0))
			var h := float(spec.get("height", 5.0))
			if tiers > 1:
				return _tiered_cylinder(r, h, tiers, inset, reserved, recess)
			return _cylinder_with_doors(r, h, reserved, recess) if not reserved.is_empty() else _cylinder(r, h)
		SHAPE_COMPOSITE:
			return _composite(spec)
		_:
			var s: Vector3 = spec.get("size", Vector3(4.0, 6.0, 4.0))
			if tiers > 1:
				return _tiered_box(s, tiers, inset, reserved, recess)
			return _box_with_doors(s, reserved, recess) if not reserved.is_empty() else _box(s)

# A TIERED base ("cake"): stack `tiers` solid drums, each `inset` smaller than the one below, so each
# lower tier's exposed top-cap ring reads as a ledge. Doors only on the bottom tier. One merged mesh.
static func _tiered_cylinder(radius: float, height: float, tiers: int, inset: float, reserved: Array, recess: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band := height / float(tiers)
	for k in range(tiers):
		var rk := maxf(0.4, radius * (1.0 - inset * float(k)))
		var doors: Array = reserved if k == 0 else []
		st.append_from(_cylinder_with_doors(rk, band, doors, recess), 0, Transform3D(Basis(), Vector3(0.0, float(k) * band, 0.0)))
	return st.commit()

static func _tiered_box(size: Vector3, tiers: int, inset: float, reserved: Array, recess: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band := size.y / float(tiers)
	for k in range(tiers):
		var f := maxf(0.25, 1.0 - inset * float(k))
		var doors: Array = reserved if k == 0 else []
		st.append_from(_box_with_doors(Vector3(size.x * f, band, size.z * f), doors, recess), 0, Transform3D(Basis(), Vector3(0.0, float(k) * band, 0.0)))
	return st.commit()

## The exposed ledge rings of a tiered base: [{y, r_inner, r_outer}] per drum tier (cylinder) — where
## a lattice/treatment sits on the flat tops. Empty for a flat (single-tier) base.
static func tier_ledges(spec: Dictionary) -> Array:
	var tiers := maxi(1, int(spec.get("tiers", 1)))
	if tiers <= 1:
		return []
	var out: Array = []
	if str(spec.get("shape", SHAPE_BOX)) == SHAPE_CYLINDER:
		var radius := float(spec.get("radius", 2.0))
		var band := float(spec.get("height", 5.0)) / float(tiers)
		var inset := float(spec.get("tier_inset", 0.16))
		for k in range(tiers - 1):
			var r_out := maxf(0.4, radius * (1.0 - inset * float(k)))
			var r_in := maxf(0.4, radius * (1.0 - inset * float(k + 1)))
			if r_out - r_in < LEDGE_MIN_WIDTH:
				continue   # both tiers hit the radius clamp -> a zero-width ring, nothing to stand on
			out.append({"cyl": true, "y": float(k + 1) * band, "r_outer": r_out, "r_inner": r_in})
	else:
		var s: Vector3 = spec.get("size", Vector3(4, 6, 4))
		var band := s.y / float(tiers)
		var inset := float(spec.get("tier_inset", 0.16))
		for k in range(tiers - 1):
			var fo := maxf(0.25, 1.0 - inset * float(k))
			var fi := maxf(0.25, 1.0 - inset * float(k + 1))
			if (fo - fi) * minf(s.x, s.z) * 0.5 < LEDGE_MIN_WIDTH:
				continue   # footprint stopped shrinking (clamp) -> collapsed ledge
			out.append({"cyl": false, "y": float(k + 1) * band,
				"outer": Vector2(s.x, s.z) * fo, "inner": Vector2(s.x, s.z) * fi})
	return out

## A small assembly of primitives baked into one ArrayMesh (base on y=0). Dispatched by "composite".
static func _composite(spec: Dictionary) -> ArrayMesh:
	match str(spec.get("composite", "")):
		"open_files_fins":
			return _open_files_mesh(spec.get("size", Vector3(5.6, 9.0, 5.6)))
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

## The Open Files massing: a SOLID faceted tower (an n-gon core prism) skinned with tall buttress FINS
## on every facet, each fin capped by an equilateral triangular-prism GABLE, at STEPPED heights — the
## jagged server-rack crown. The fins pack the perimeter so it reads as one solid tower (small channels
## between them are the future rack lattice). One fin reaches the full spec height so the AABB is
## exactly [0, size.y]. Deterministic (hash-stepped heights); all faces wound OUTWARD (no culling holes).
static func _open_files_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 9
	var core_r := size.x * 0.5 * 0.66            # solid faceted core radius (to a facet mid)
	var core_top := size.y * 0.46                # the core is solid up to here; fins rise past it
	var fin_w := 0.46                            # tangential half-width (fins nearly touch -> solid read)
	var fin_d := 0.42                            # radial half-depth (how far the fin stands proud)
	var gable_h := fin_w * sqrt(3.0)             # equilateral triangle over the 2*fin_w base
	var top_fin := size.y - gable_h              # the tall fin whose gable apex touches size.y
	_emit_ngon_prism(st, n, core_r, core_top)
	for i in range(n):
		var a := TAU * (float(i) + 0.5) / float(n)
		var dir := Vector3(cos(a), 0.0, sin(a))          # radial (fin depth + outward)
		var tang := Vector3(-sin(a), 0.0, cos(a))        # tangential (fin width)
		var frac := 0.5 + 0.5 * _h01(float(i) * 2.7)
		var h := top_fin if i == 0 else lerpf(core_top + 0.5, top_fin, frac)
		var c := dir * (core_r * 0.98)                   # fin base hugs the core, standing proud
		_emit_oriented_box_st(st, Vector3(c.x, h * 0.5, c.z), tang, Vector3.UP, dir, Vector3(fin_w, h * 0.5, fin_d))
		_emit_gable_st(st, Vector3(c.x, h, c.z), tang, dir, fin_w, fin_d, gable_h)
	st.generate_normals()
	return st.commit()

# A solid convex n-gon prism (base on y=0, top at `h`), every face wound OUTWARD via _tri_out.
static func _emit_ngon_prism(st: SurfaceTool, n: int, r: float, h: float) -> void:
	var mid := Vector3(0, h * 0.5, 0)
	var ct := Vector3(0, h, 0)
	var cb := Vector3.ZERO
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var t0 := Vector3(r * cos(a0), h, r * sin(a0))
		var t1 := Vector3(r * cos(a1), h, r * sin(a1))
		var b0 := Vector3(r * cos(a0), 0.0, r * sin(a0))
		var b1 := Vector3(r * cos(a1), 0.0, r * sin(a1))
		_tri_out(st, ct, t0, t1, mid)              # top fan
		_tri_out(st, cb, b0, b1, mid)              # bottom fan
		_tri_out(st, b0, b1, t1, mid)              # side quad
		_tri_out(st, b0, t1, t0, mid)

# An equilateral triangular prism (gable) sitting at `base_center`: base 2*fin_w along `tang`, apex
# `gable_h` up, extruded ±fin_d along `radial`. Closed (two end triangles + two slopes + base).
static func _emit_gable_st(st: SurfaceTool, base_center: Vector3, tang: Vector3, radial: Vector3, fin_w: float, fin_d: float, gable_h: float) -> void:
	var bl_f := base_center - tang * fin_w + radial * fin_d
	var br_f := base_center + tang * fin_w + radial * fin_d
	var bl_b := base_center - tang * fin_w - radial * fin_d
	var br_b := base_center + tang * fin_w - radial * fin_d
	var ap_f := base_center + Vector3.UP * gable_h + radial * fin_d
	var ap_b := base_center + Vector3.UP * gable_h - radial * fin_d
	_tri_st(st, bl_f, br_f, ap_f)                 # front triangle
	_tri_st(st, br_b, bl_b, ap_b)                 # back triangle
	_tri_st(st, bl_f, ap_f, ap_b); _tri_st(st, bl_f, ap_b, bl_b)   # left slope
	_tri_st(st, br_f, br_b, ap_b); _tri_st(st, br_f, ap_b, ap_f)   # right slope
	_tri_st(st, bl_f, bl_b, br_b); _tri_st(st, bl_f, br_b, br_f)   # base underside

static func _emit_box_st(st: SurfaceTool, center: Vector3, half: Vector3) -> void:
	_emit_oriented_box_st(st, center, Vector3.RIGHT, Vector3.UP, Vector3.BACK, half)

static func _emit_oriented_box_st(st: SurfaceTool, center: Vector3, u: Vector3, v: Vector3, n: Vector3, half: Vector3) -> void:
	var vtx := [
		center - u * half.x - v * half.y - n * half.z, center + u * half.x - v * half.y - n * half.z,
		center + u * half.x - v * half.y + n * half.z, center - u * half.x - v * half.y + n * half.z,
		center - u * half.x + v * half.y - n * half.z, center + u * half.x + v * half.y - n * half.z,
		center + u * half.x + v * half.y + n * half.z, center - u * half.x + v * half.y + n * half.z,
	]
	var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	for fq in faces:
		_tri_st(st, vtx[fq[0]], vtx[fq[2]], vtx[fq[1]])
		_tri_st(st, vtx[fq[0]], vtx[fq[3]], vtx[fq[2]])

static func _tri_st(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

# Emit a triangle wound so it is FRONT-FACING (visible) from outside a convex solid — no matter what
# order the caller passed the corners. Matches the proven `_emit_box` convention: Godot's visible outer
# face has (b-a)x(c-a) pointing TOWARD the centre, so we keep the order when the cross product points
# inward and flip it otherwise. (generate_normals still derives the correct outward normal for lighting.)
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - center) <= 0.0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)

static func _h01(nv: float) -> float:
	return fmod(absf(sin(nv * 127.13) * 43758.5453), 1.0)

static func _cylinder(radius: float, height: float) -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = CYL_SEGMENTS
	cm.rings = 1
	return _seated(cm, height * 0.5)

static func _box(size: Vector3) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return _seated(bm, size.y * 0.5)

# A cylinder with real door OPENINGS cut into the base wall + a recessed pocket per door (back wall +
# jambs + lintel + threshold). `doors` = drum reserved regions {theta, half_arc, y_top}. Faces OUTWARD.
static func _cylinder_with_doors(radius: float, height: float, doors: Array, recess: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := CYL_SEGMENTS
	var rin := maxf(0.3, radius - recess)
	var axis_hi := Vector3(0.0, height * 2.0, 0.0)
	var yts: Array = []
	for i in range(seg):
		yts.append(_cyl_door_yt(TAU * (float(i) + 0.5) / float(seg), doors))
	for i in range(seg):
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var yt: float = yts[i]
		var wo0 := Vector3(radius * cos(a0), 0.0, radius * sin(a0))
		var wo1 := Vector3(radius * cos(a1), 0.0, radius * sin(a1))
		if yt <= 0.0:
			_quad_out(st, wo0, wo1, wo1 + Vector3(0, height, 0), wo0 + Vector3(0, height, 0), Vector3(0, height * 0.5, 0))
		else:
			_quad_out(st, wo0 + Vector3(0, yt, 0), wo1 + Vector3(0, yt, 0), wo1 + Vector3(0, height, 0), wo0 + Vector3(0, height, 0), Vector3(0, (yt + height) * 0.5, 0))
			var bi0 := Vector3(rin * cos(a0), 0.0, rin * sin(a0))
			var bi1 := Vector3(rin * cos(a1), 0.0, rin * sin(a1))
			_quad_out(st, bi0, bi1, bi1 + Vector3(0, yt, 0), bi0 + Vector3(0, yt, 0), Vector3(0, yt * 0.5, 0))   # pocket back
			_quad_out(st, bi0 + Vector3(0, yt, 0), bi1 + Vector3(0, yt, 0), wo1 + Vector3(0, yt, 0), wo0 + Vector3(0, yt, 0), axis_hi)   # lintel (down)
			_quad_out(st, bi0, bi1, wo1, wo0, Vector3(0, -height, 0))   # threshold (up)
		var prev_door: bool = float(yts[(i - 1 + seg) % seg]) > 0.0
		if (yt > 0.0) != prev_door:
			var jyt := maxf(yt, float(yts[(i - 1 + seg) % seg]))
			var jo := Vector3(radius * cos(a0), 0.0, radius * sin(a0))
			var ji := Vector3(rin * cos(a0), 0.0, rin * sin(a0))
			var eps := 0.09 if yt > 0.0 else -0.09   # jamb faces INTO the door; centre on the anti-door side
			var jc := Vector3(cos(a0 - eps), 0.0, sin(a0 - eps)) * radius * 2.0 + Vector3(0, jyt * 0.5, 0)
			_quad_out(st, ji, jo, jo + Vector3(0, jyt, 0), ji + Vector3(0, jyt, 0), jc)
	var ct := Vector3(0, height, 0)
	for i in range(seg):
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		_tri_out(st, ct, Vector3(radius * cos(a0), height, radius * sin(a0)), Vector3(radius * cos(a1), height, radius * sin(a1)), Vector3(0, -height, 0))
		_tri_out(st, Vector3.ZERO, Vector3(radius * cos(a0), 0.0, radius * sin(a0)), Vector3(radius * cos(a1), 0.0, radius * sin(a1)), axis_hi)
	st.generate_normals()
	return st.commit()

static func _cyl_door_yt(theta: float, doors: Array) -> float:
	var yt := 0.0
	for reg in doors:
		var rd := reg as Dictionary
		if not bool(rd.get("cyl", false)):
			continue
		var dth := theta - float(rd["theta"])
		while dth > PI:
			dth -= TAU
		while dth < -PI:
			dth += TAU
		if absf(dth) < float(rd.get("open_half_arc", rd.get("half_arc", 0.0))):
			yt = maxf(yt, float(rd.get("open_y_top", rd.get("y_top", 0.0))))
	return yt

# A box with real door OPENINGS on the vertical faces + a recessed pocket per door. `doors` = box
# reserved regions {n, x_center, half_w, y_top}.
static func _box_with_doors(size: Vector3, doors: Array, recess: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var hy := size.y * 0.5
	var cen := Vector3(0, hy, 0)
	var up := Vector3(0, 1, 0)
	var faces := [
		[Vector3(0, hy, hz), Vector3(1, 0, 0), Vector3(0, 0, 1), size.x],
		[Vector3(0, hy, -hz), Vector3(-1, 0, 0), Vector3(0, 0, -1), size.x],
		[Vector3(hx, hy, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), size.z],
		[Vector3(-hx, hy, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), size.z],
	]
	for f in faces:
		var fc: Vector3 = f[0]
		var u: Vector3 = f[1]
		var n: Vector3 = f[2]
		var fw: float = f[3]
		var bl := Vector3(fc.x, 0.0, fc.z) - u * (fw * 0.5)   # face base-left (on the ground)
		var door = _box_door_on(n, doors)
		if door == null:
			_quad_out(st, bl, bl + u * fw, bl + u * fw + up * size.y, bl + up * size.y, cen)
		else:
			var hw: float = float(door.get("open_half_w", door.get("half_w", 0.5)))
			var yt: float = float(door.get("open_y_top", door.get("y_top", 2.0)))
			var lx := fw * 0.5 + float(door["x_center"]) - hw   # opening left, right along u from bl
			var rx := fw * 0.5 + float(door["x_center"]) + hw
			_quad_out(st, bl, bl + u * lx, bl + u * lx + up * size.y, bl + up * size.y, cen)                          # left of hole
			_quad_out(st, bl + u * rx, bl + u * fw, bl + u * fw + up * size.y, bl + u * rx + up * size.y, cen)        # right of hole
			_quad_out(st, bl + u * lx + up * yt, bl + u * rx + up * yt, bl + u * rx + up * size.y, bl + u * lx + up * size.y, cen)  # above hole
			var pl := bl + u * lx
			var pr := bl + u * rx
			var back := -n * recess
			_quad_out(st, pl + back, pr + back, pr + back + up * yt, pl + back + up * yt, cen + back * 2.0)   # pocket back (faces +n)
			_quad_out(st, pl, pl + back, pl + back + up * yt, pl + up * yt, pl - u + back * 0.5)              # left jamb
			_quad_out(st, pr + back, pr, pr + up * yt, pr + back + up * yt, pr + u + back * 0.5)              # right jamb
			_quad_out(st, pl + up * yt, pl + back + up * yt, pr + back + up * yt, pr + up * yt, Vector3(0, size.y * 2, 0))   # lintel (down)
	_quad_out(st, Vector3(-hx, size.y, -hz), Vector3(hx, size.y, -hz), Vector3(hx, size.y, hz), Vector3(-hx, size.y, hz), Vector3(0, -1, 0))
	_quad_out(st, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(0, size.y + 1, 0))
	st.generate_normals()
	return st.commit()

static func _box_door_on(face_n: Vector3, doors: Array):
	for reg in doors:
		var rd := reg as Dictionary
		if bool(rd.get("cyl", true)):
			continue
		if (rd["n"] as Vector3).dot(face_n) > 0.9:
			return rd
	return null

static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
	_tri_out(st, a, b, c, center)
	_tri_out(st, a, c, d, center)

## Bake a centred primitive into an ArrayMesh lifted so its BASE sits on y=0.
static func _seated(prim: PrimitiveMesh, lift: float) -> ArrayMesh:
	var arrays: Array = prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		verts[i].y += lift
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
