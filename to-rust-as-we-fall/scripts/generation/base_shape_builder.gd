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

## Ordered list the showcase walks. Add a building here as we bring each one in.
const BUILDINGS := ["plumbing_power", "honeycomb_cooperative"]

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
		"lattice": "tracery",               # pointed-arch window wall (NEXT — not built yet)
	},
	"honeycomb_cooperative": {
		"title": "Honeycomb Cooperative",
		"shape": SHAPE_BOX,
		# Tall apartment block; footprint a touch deeper than it is wide (~1.8x taller than wide).
		"size": Vector3(4.5, 8.0, 5.5),
		"color": Color(0.60, 0.58, 0.48),   # pale cast-stone facade
		"tile": "facility_metal",
		"lattice": "honeyframe",            # rounded-cell facade frame + lit panes
	},
}

const CYL_SEGMENTS := 12   # low-poly drum — clearly faceted, still reads round

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
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

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
