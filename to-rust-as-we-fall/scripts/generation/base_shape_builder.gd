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
	"greenfields", "ancourage", "bulwark_wharf", "cleanstreets", "zone3",
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
		"lattice": "extruded_fins",         # server-rack channels = extrude the fin faces by a depth
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
}

const CYL_SEGMENTS := 24   # drum facets — smooth enough that a wrapped lattice sits flush, still low-poly

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
static func base_mesh(spec: Dictionary) -> ArrayMesh:
	match str(spec.get("shape", SHAPE_BOX)):
		SHAPE_CYLINDER:
			return _cylinder(float(spec.get("radius", 2.0)), float(spec.get("height", 5.0)))
		SHAPE_COMPOSITE:
			return _composite(spec)
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

## A small assembly of primitives baked into one ArrayMesh (base on y=0). Dispatched by "composite".
static func _composite(spec: Dictionary) -> ArrayMesh:
	match str(spec.get("composite", "")):
		"open_files_fins":
			return _open_files_mesh(spec.get("size", Vector3(5.6, 9.0, 5.6)))
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

## The Open Files massing: a radial ring of tall rectangular-prism FINS around a core, each fin capped
## by an equilateral triangular-prism GABLE, at STEPPED heights (the jagged server-rack crown). One fin
## reaches the full spec height so the AABB is exactly [0, size.y]. Deterministic (hash-stepped heights).
static func _open_files_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var ring := maxf(0.6, size.x * 0.5 - 0.9)   # fins sit inside the footprint
	var fin_w := 0.55                            # tangential half-width
	var fin_d := 0.45                            # radial half-depth
	var gable_h := fin_w * sqrt(3.0)             # equilateral triangle over the 2*fin_w base
	var top_fin := size.y - gable_h              # a fin whose gable apex touches size.y
	var core_h := size.y * 0.42
	_emit_box_st(st, Vector3(0, core_h * 0.5, 0), Vector3(ring * 0.8, core_h * 0.5, ring * 0.8))
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var dir := Vector3(cos(a), 0.0, sin(a))          # radial (fin depth + outward normal)
		var tang := Vector3(-sin(a), 0.0, cos(a))        # tangential (fin width)
		var frac := 0.55 + 0.45 * _h01(float(i) * 2.7)
		var h := top_fin if i == 0 else top_fin * frac
		var c := dir * ring
		_emit_oriented_box_st(st, Vector3(c.x, h * 0.5, c.z), tang, Vector3.UP, dir, Vector3(fin_w, h * 0.5, fin_d))
		_emit_gable_st(st, Vector3(c.x, h, c.z), tang, dir, fin_w, fin_d, gable_h)
	st.generate_normals()
	return st.commit()

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
