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
		"shape": SHAPE_COMPOSITE,           # melted-boiler massing (BUILDING_REVIEW P1-P2): lobed
		"composite": "plumbing_lobed",      # root-skirt + shoulder drum + onion dome + cupola
		"door_frame": "cyl",                # doors cut the DRUM wall (drum-frame reserved regions)
		"door_radius": 1.37,                # the shoulder drum the door actually cuts (radius*0.62)
		"flare": 0.95,                      # footprint = flare x massing diameter (lobes reach ~1.5x the drum)
		"radius": 2.2,                      # the flare reaches ~1.7x the drum radius at ground
		"height": 5.6,
		"color": Color(0.24, 0.35, 0.32),   # dark desaturated verdigris (plate palette)
		"tile": "facility_metal",
		"lattice": "",                      # spiral flume + slit windows are the next passes
		"pipes": true,                      # the plate's draped conduit runs
	},
	"honeycomb_cooperative": {
		"entrances": {"reserve_margin": 0.2},   # storey-scale blobs: a fat clearance would gut the facade
		"title": "Honeycomb Cooperative",
		"shape": SHAPE_BOX,
		# Tall slab: height 2.2x the front width, side face DEEPER than the front is wide (REVIEW P2).
		"size": Vector3(4.5, 10.0, 6.3),
		"color": Color(0.48, 0.46, 0.38),   # cast-stone facade, darker (plate palette)
		"tile": "facility_metal",
		"lattice": "honeyframe",            # rounded-cell facade frame + lit panes
		"pipes": true,                      # rust/conduit tangle down the flank
	},
	"beacon_hill": {
		"title": "Beacon Hill",
		"shape": SHAPE_COMPOSITE,           # drum -> elliptical dome shoulder -> rooftop lantern (REVIEW P1)
		"composite": "beacon_domed",
		"door_frame": "cyl",
		"radius": 2.4,
		"height": 7.2,
		"tracery_height": 5.4,              # the lattice climbs the DRUM only (0.75H), never the dome
		"color": Color(0.20, 0.31, 0.28),   # dark verdigris tiled stone (REVIEW P3)
		"tile": "facility_metal",
		"lattice": "tracery",               # pointed-arch (lancet) window wall + lit glass behind
		"bays": 7,                          # bay width 2.15 — the door assembly (~2.0) fits inside a bay
		"entrances": {"side_count_min": 1, "side_count_max": 1},   # plate: main door + ONE enforcement door
	},
	# --- The remaining districts: existence + a base primitive established so Fable only owns the
	# --- lattices/complex massing. Simple massing here; the notes flag what is Fable's.
	"open_files": {
		"title": "The Open Files Initiative",
		"shape": SHAPE_COMPOSITE,           # RECURSIVE CONNECTED AWNINGS mass (geometry-lab algo 2)
		"composite": "open_files_awnings",
		"size": Vector3(5.6, 9.0, 5.6),     # FULL ground footprint — the flare ends at these planes
		"awning_step": 1.0,                 # the construction grid STEP (A->C drop per level)
		"awning_angle": 58.0,               # awning slope (proj = step/tan) — the visible step flare
		"awning_shift": 2.0,                # max curve-driven extra DOWN shift per level (floored steps)
		"awning_depth": 3,                  # recursion depth (levels = depth+1, ground-clamped)
		"awning_merge": 0.55,               # adjacent-corner merge chance ceiling (rises with depth)
		"rack_depth": 0.2,                  # the faces-EXTRUDE parameter: drawer strata depth
		"color": Color(0.31, 0.35, 0.37),   # dark steel-blue with rust + teal server glow
		"tile": "facility_metal",
		"lattice": "rackwork",              # extruded-face drawer strata + green LED matrices
	},
	"hypelines": {
		"title": "The Hypelines",
		"shape": SHAPE_COMPOSITE,           # three-tier domed mound + radiating pipe ARMS (REVIEW P1-P2)
		"composite": "hypelines_mound",
		"door_frame": "cyl",
		"radius": 2.6, "height": 6.2,
		"flare": 1.0,
		"color": Color(0.26, 0.33, 0.29),   # dark verdigris-rust
		"tile": "facility_metal",
		"lattice": "", "pipes": true,       # the radiating viaducts read as heavy pipes
	},
	"greenfields": {
		"title": "Greenfields Collective",
		"shape": SHAPE_COMPOSITE,           # stacked-cushions: overhanging balcony slab rings (REVIEW P1)
		"composite": "greenfields_stack",
		"size": Vector3(5.2, 6.4, 5.0),
		"color": Color(0.52, 0.56, 0.47),   # cast-stone over teal
		"tile": "facility_metal",
		"lattice": "balconies",             # wrapping per-floor balconies (Fable — beam+curve spec)
	},
	"ancourage": {
		"title": "Ancourage",
		"shape": SHAPE_COMPOSITE,           # squat drum + eave ring + 2-lobe dome crown (REVIEW P1-P2)
		"composite": "ancourage_domes",
		"door_frame": "cyl",
		"radius": 2.7, "height": 4.6,       # the dome cluster restores the plate's missing top 40%
		"color": Color(0.27, 0.36, 0.33),   # dark verdigris
		"tile": "facility_metal",
		"lattice": "", "pipes": true,
	},
	"bulwark_wharf": {
		"title": "Bulwark Wharf",
		"shape": SHAPE_COMPOSITE,           # squat gatehouse + two domed corner towers (REVIEW P1-P2)
		"composite": "bulwark_towers",
		"size": Vector3(4.6, 5.2, 3.4),     # squatter than before (plate ~1:1.15 w:h with towers)
		"color": Color(0.32, 0.36, 0.39),
		"tile": "facility_metal",
		"lattice": "voronoi",               # the plate's catenary Voronoi MEMBRANE wall (mirrored, focal-merged)
	},
	"cleanstreets": {
		"title": "The Cleanstreets Initiative",
		"shape": SHAPE_COMPOSITE,           # OPEN canopy pavilion on waisted piers over a stepped
		"composite": "canopy_piers",        # dais — air between the legs, wider than tall (REVIEW P1)
		"size": Vector3(11.0, 6.0, 7.0),
		"color": Color(0.45, 0.47, 0.42),   # bone/tan mosaic base, verdigris panels ride the texture pass
		"tile": "facility_metal",
		"lattice": "",
	},
	"zone3": {
		"title": "Zone-3 Eroded Ruin",
		"shape": SHAPE_COMPOSITE,           # main block + collapsed side wing + cornice slab (REVIEW P1-P2)
		"composite": "zone3_split",
		"size": Vector3(4.0, 5.4, 4.0),
		"color": Color(0.28, 0.30, 0.28),
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
			# A composite may be drum-based (radius/height, no size) — the lobed/domed massings.
			if spec.has("size"):
				var s: Vector3 = spec["size"]
				spec["height_total"] = s.y
				spec["footprint"] = maxf(s.x, s.z)
			else:
				spec["height_total"] = float(spec.get("height", 6.0))
				spec["footprint"] = float(spec.get("radius", 2.5)) * 2.0 * float(spec.get("flare", 1.0))
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
			return _composite(spec, reserved, recess)
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

## GAMEPLAY ANCHORS — the architecture->puzzle contract (director, 2026-07-09). A generated building
## is not scenery: it exposes SOCKETS the level/puzzle layer consumes. Deterministic positions;
## SEMANTICS live in the consumer (a chunk decides what a weak point does when struck):
##   weak_points   [{pos, n, radius}]        structural weaknesses — may CRUMBLE when hit (a scheduled
##                                            collapse killing/blocking what's beneath, spawning rubble)
##   connectors    [{kind:"road"|"bridge", pos, dir, width, main?}]  where level roads/bridges attach —
##                                            roads at door thresholds, bridges at ledge rims/roof edges
##   balcony_slots [{pos, out, size}]         content points on tier ledges (flora, lures, rest spots,
##                                            set-piece controls — whatever the level assigns)
static func gameplay_anchors(spec: Dictionary, ent: Dictionary = {}) -> Dictionary:
	var weak: Array = []
	var conns: Array = []
	var balc: Array = []
	var kb := float(str(spec.get("kind", "bld")).hash() % 1000)
	# ROAD connectors: one per entrance threshold, facing out (the main door flagged for the level's spine)
	for a in (ent.get("anchors", []) as Array):
		var ad := a as Dictionary
		conns.append({"kind": "road", "pos": ad["pos"] as Vector3, "dir": ad["n"] as Vector3,
			"width": 1.2, "main": bool(ad.get("main", false))})
	if str(spec.get("composite", "")) == "open_files_awnings":
		# The awning stack: weak points on hash-picked skirt bands (the visible stepped facades);
		# bridge sockets at the flat core-roof edges. The sloped awning roofs hold no balcony slots.
		var lay := _awning_layout(spec)
		for k3 in range(2):
			var fi := int(_h01(kb + 3.0 + float(k3) * 13.7) * 3.99)
			var lv: Array = (lay["faces"] as Array)[fi]
			var li := int(_h01(kb + 8.0 + float(k3) * 5.1) * float(lv.size() - 1) * 0.99)
			var pts := lv[li] as Dictionary
			var mid: Vector3 = ((pts["E"] as Vector3) + (pts["F"] as Vector3)) * 0.5
			var wy := (mid.y + float(pts["bottom_y"])) * 0.5
			weak.append({"pos": Vector3(mid.x, wy, mid.z), "n": pts["n"] as Vector3, "radius": 0.7})
		var core: Vector2 = lay["core"]
		var hh: float = lay["h"]
		for fd0 in [[Vector3(0, hh, core.y), Vector3(0, 0, 1)], [Vector3(0, hh, -core.y), Vector3(0, 0, -1)],
				[Vector3(core.x, hh, 0), Vector3(1, 0, 0)], [Vector3(-core.x, hh, 0), Vector3(-1, 0, 0)]]:
			conns.append({"kind": "bridge", "pos": (fd0 as Array)[0] as Vector3, "dir": (fd0 as Array)[1] as Vector3, "width": 1.0})
		return {"weak_points": weak, "connectors": conns, "balcony_slots": balc}
	if str(spec.get("composite", "")) == "hypelines_mound":
		for a in hypelines_arms(spec):
			var ad := a as Dictionary
			conns.append({"kind": "bridge", "pos": ad["tip"] as Vector3,
				"dir": (ad["dir"] as Vector3).normalized(), "width": 1.1})
	if str(spec.get("shape", SHAPE_BOX)) == SHAPE_CYLINDER 			or (spec.has("radius") and not spec.has("size")):
		var hgt := float(spec.get("height", 5.0))
		var nw := 2 + int(_h01(kb + 1.0) * 1.9)
		for k in range(nw):
			var th := TAU * _h01(kb + 10.0 + float(k) * 7.7)
			var wy := hgt * (0.45 + 0.4 * _h01(kb + 20.0 + float(k) * 3.3))
			# the socket sits ON the real silhouette (massing profile), whatever the massing is
			var rk := massing_radius_at(spec, wy)
			var nrm := Vector3(cos(th), 0.0, sin(th))
			weak.append({"pos": nrm * rk + Vector3(0, wy, 0), "n": nrm, "radius": 0.7})
	else:
		var s: Vector3 = spec.get("size", Vector3(4, 6, 4))
		var hx := s.x * 0.5
		var hz := s.z * 0.5
		# cornice-corner weaknesses (two hash-picked corners) + one upper mid-face
		var c0 := int(_h01(kb + 2.0) * 3.99)
		for k2 in range(2):
			var corner := (c0 + k2 * 2) % 4
			var cx := hx if corner % 2 == 0 else -hx
			var cz := hz if corner < 2 else -hz
			weak.append({"pos": Vector3(cx, s.y * 0.85, cz), "n": Vector3(cx, 0, cz).normalized(), "radius": 0.7})
		weak.append({"pos": Vector3(0, s.y * 0.7, hz), "n": Vector3(0, 0, 1), "radius": 0.8})
		# roof-rim bridge connectors (flat boxes without tiers get their sockets at the parapet)
		if maxi(1, int(spec.get("tiers", 1))) <= 1:
			for fd in [[Vector3(0, s.y, hz), Vector3(0, 0, 1)], [Vector3(0, s.y, -hz), Vector3(0, 0, -1)],
					[Vector3(hx, s.y, 0), Vector3(1, 0, 0)], [Vector3(-hx, s.y, 0), Vector3(-1, 0, 0)]]:
				conns.append({"kind": "bridge", "pos": (fd as Array)[0] as Vector3, "dir": (fd as Array)[1] as Vector3, "width": 1.0})
	# tier ledges (cyl or box): BRIDGE sockets at the rim quarters, BALCONY slots around the ring
	for lg in tier_ledges(spec):
		var ld := lg as Dictionary
		var ly := float(ld["y"])
		for q in range(4):
			var smp := LedgeBuilder._ledge_center_sample(ld, (float(q) + 0.5) / 4.0)
			var opos := smp["pos"] as Vector3
			conns.append({"kind": "bridge", "pos": Vector3(opos.x, ly, opos.z) + (smp["outward"] as Vector3) * 0.3,
				"dir": smp["outward"] as Vector3, "width": 1.0})
		var ns := 3 + int(_h01(kb + 40.0) * 2.9)
		for sl in range(ns):
			var smp2 := LedgeBuilder._ledge_center_sample(ld, (float(sl) + 0.25) / float(ns))
			var bpos := smp2["pos"] as Vector3
			balc.append({"pos": Vector3(bpos.x, ly, bpos.z), "out": smp2["outward"] as Vector3, "size": 0.5})
	return {"weak_points": weak, "connectors": conns, "balcony_slots": balc}

## MASSING PROFILE — the outer silhouette radius at height y, for every drum-based shape and
## composite. This is the MEREOTOPOLOGY contract (director): attached parts (draped pipes, weak-point
## sockets, arms, collars) consult THIS so they touch the real surface — never the spec's nominal
## radius, which the lobed/tiered/domed massings no longer follow. Piecewise-linear approximations
## of each composite's construction; keep them in lockstep with the *_mesh builders.
static func massing_radius_at(spec: Dictionary, y: float) -> float:
	var r := float(spec.get("radius", 2.0))
	var h := float(spec.get("height", spec.get("height_total", 5.0)))
	match str(spec.get("composite", "")):
		"plumbing_lobed":
			var rd := float(spec.get("door_radius", r * 0.62))
			if y < h * 0.47:
				return lerpf(rd * 1.5, rd, clampf(y / (h * 0.47), 0.0, 1.0))
			if y < h * 0.74:
				return rd
			var dn := clampf((y - h * 0.74) / (rd * 0.75), 0.0, 1.0)
			return maxf(rd * 0.2, rd * 1.12 * sqrt(maxf(0.0, 1.0 - dn * dn)))
		"ancourage_domes":
			var bh := h * 0.53
			if y < bh:
				return r
			return maxf(0.3, lerpf(r * 0.95, r * 0.2, clampf((y - bh) / (h - bh), 0.0, 1.0)))
		"hypelines_mound":
			if y < h * 0.38:
				return r
			if y < h * 0.68:
				return lerpf(r * 0.78, r * 0.62, (y - h * 0.38) / (h * 0.30))
			if y < h * 0.9:
				return lerpf(r * 0.5, r * 0.38, (y - h * 0.68) / (h * 0.22))
			return maxf(0.2, lerpf(r * 0.4, r * 0.1, clampf((y - h * 0.9) / (h * 0.1), 0.0, 1.0)))
		"beacon_domed":
			if y < h * 0.75:
				return r
			return maxf(r * 0.4, lerpf(r, r * 0.45, clampf((y - h * 0.75) / (h * 0.25), 0.0, 1.0)))
	var tiers := maxi(1, int(spec.get("tiers", 1)))
	if str(spec.get("shape", "")) == SHAPE_CYLINDER and tiers > 1:
		var band := h / float(tiers)
		return maxf(0.4, r * (1.0 - float(spec.get("tier_inset", 0.16)) * float(mini(tiers - 1, int(y / band)))))
	return r

## A small assembly of primitives baked into one ArrayMesh (base on y=0). Dispatched by "composite".
static func _composite(spec: Dictionary, reserved: Array = [], recess: float = 0.5) -> ArrayMesh:
	match str(spec.get("composite", "")):
		"open_files_awnings":
			return _awning_stack_mesh(spec, reserved, recess)
		"open_files_fins":
			return _open_files_mesh(spec.get("size", Vector3(5.6, 9.0, 5.6)))
		"plumbing_lobed":
			return _plumbing_lobed_mesh(spec, reserved, recess)
		"canopy_piers":
			return _canopy_piers_mesh(spec)
		"ancourage_domes":
			return _ancourage_domes_mesh(spec, reserved, recess)
		"beacon_domed":
			return _beacon_domed_mesh(spec, reserved, recess)
		"hypelines_mound":
			return _hypelines_mound_mesh(spec, reserved, recess)
		"greenfields_stack":
			return _greenfields_stack_mesh(spec, reserved, recess)
		"bulwark_towers":
			return _bulwark_towers_mesh(spec, reserved, recess)
		"zone3_split":
			return _zone3_split_mesh(spec, reserved, recess)
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

# --- REVIEW-DRIVEN MASSING (docs/BUILDING_REVIEW.md priority-1 alterations) ------------------------

## Plumbing Power: the melted-boiler silhouette — a shoulder drum whose bottom 45% flares into fused
## root-lobes reaching ~1.7x the drum radius (the plate's dominant feature), crowned by an onion dome
## + cupola. The door keeps the drum's real wall cut; the lobe ring leaves a gap at the door theta so
## the entry stays reachable (the plate's shadowed ground archway).
static func _plumbing_lobed_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var h := float(spec.get("height", 5.6))
	var rd := float(spec.get("door_radius", float(spec.get("radius", 2.2)) * 0.62))   # the shoulder drum (plate: diameter ~0.5H)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the core drum carries the full height to the dome line + the real door cut
	st.append_from(_cylinder_with_doors(rd, h * 0.74, reserved, recess), 0, Transform3D.IDENTITY)
	# fused root-lobes: tapered cylinders leaning into the drum; skip the arc holding the door
	var door_theta := INF
	for reg in reserved:
		if bool((reg as Dictionary).get("cyl", false)):
			door_theta = float((reg as Dictionary)["theta"])
	var lobes := 7
	for i in range(lobes):
		var th := TAU * float(i) / float(lobes) + 0.31
		var dth := TAU
		if door_theta != INF:
			dth = absf(fposmod(th - door_theta + PI, TAU) - PI)
		if dth < 0.62:
			continue   # the ground archway: the door's approach stays clear of lobes
		var lb := CylinderMesh.new()
		lb.bottom_radius = rd * (0.52 + 0.1 * _h01(float(i) * 3.7))
		lb.top_radius = rd * 0.26
		lb.height = h * (0.42 + 0.06 * _h01(float(i) * 8.1))
		lb.radial_segments = 10
		var ring := rd * 0.92
		st.append_from(_seated(lb, lb.height * 0.5), 0,
			Transform3D(Basis(), Vector3(cos(th) * ring, 0.0, sin(th) * ring)))
	# onion dome (squashed sphere) + cupola finial
	var dome := SphereMesh.new()
	dome.radius = rd * 1.12
	dome.height = rd * 1.5
	dome.radial_segments = 16
	dome.rings = 8
	st.append_from(dome, 0, Transform3D(Basis(), Vector3(0.0, h * 0.74, 0.0)))
	var cup := CylinderMesh.new()
	cup.top_radius = rd * 0.14
	cup.bottom_radius = rd * 0.18
	cup.radial_segments = 10
	cup.height = h * 0.09
	st.append_from(cup, 0, Transform3D(Basis(), Vector3(0.0, h * 0.74 + rd * 0.72, 0.0)))
	var cap := SphereMesh.new()
	cap.radius = rd * 0.2
	cap.radial_segments = 10
	cap.rings = 5
	var cap_y := h - rd * 0.1   # finial apex lands exactly at the spec height
	cap.height = rd * 0.2
	st.append_from(cap, 0, Transform3D(Basis(), Vector3(0.0, cap_y, 0.0)))
	# NO generate_normals here: on mixed append_from sources it DROPS earlier surfaces
	# (probed live); every appended mesh already carries its normals.
	return st.commit()

## Cleanstreets: an OPEN canopy pavilion — a thick slab with swept-up corner horns riding mushroom
## piers over a stepped dais; air between the legs (no walls). Wider than tall, unlike every
## neighbour (the plate's defining read).
static func _canopy_piers_mesh(spec: Dictionary) -> ArrayMesh:
	var size: Vector3 = spec.get("size", Vector3(11.0, 6.0, 7.0))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var slab_y := size.y * 0.56
	var slab_t := size.y * 0.22
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# stepped dais
	var dais := BoxMesh.new()
	dais.size = Vector3(size.x, size.y * 0.075, size.z)
	st.append_from(_seated(dais, dais.size.y * 0.5), 0, Transform3D.IDENTITY)
	var step := BoxMesh.new()
	step.size = Vector3(size.x * 0.5, size.y * 0.04, size.z * 0.22)
	st.append_from(_seated(step, step.size.y * 0.5), 0, Transform3D(Basis(), Vector3(0.0, 0.0, hz + step.size.z * 0.4)))
	# 6 waisted piers (2 rows x 3), flaring toward the canopy head
	for ix in range(3):
		for iz in range(2):
			var pier := CylinderMesh.new()
			pier.bottom_radius = size.y * 0.115
			pier.top_radius = size.y * 0.16
			pier.height = slab_y - dais.size.y
			pier.radial_segments = 12
			st.append_from(_seated(pier, pier.height * 0.5 + dais.size.y), 0,
				Transform3D(Basis(), Vector3((float(ix) - 1.0) * hx * 0.68, 0.0, (float(iz) - 0.5) * hz * 1.05)))
	# the canopy slab + swept-up corner horns
	var slab := BoxMesh.new()
	slab.size = Vector3(size.x, slab_t, size.z)
	st.append_from(_seated(slab, slab_t * 0.5 + slab_y), 0, Transform3D.IDENTITY)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var horn := BoxMesh.new()
			horn.size = Vector3(size.x * 0.2, slab_t * 0.9, size.z * 0.2)
			var tilt := Basis(Vector3(0, 0, 1), cx * -0.32) * Basis(Vector3(1, 0, 0), cz * 0.32)
			# the swept-up horn tips DEFINE the massing's top (exact rotated-AABB half height)
			var horn_top := absf(tilt.x.y) * horn.size.x * 0.5 + absf(tilt.y.y) * horn.size.y * 0.5 				+ absf(tilt.z.y) * horn.size.z * 0.5
			st.append_from(horn, 0, Transform3D(tilt,
				Vector3(cx * (hx - horn.size.x * 0.42), size.y - horn_top, cz * (hz - horn.size.z * 0.42))))
	# NO generate_normals here: on mixed append_from sources it DROPS earlier surfaces
	# (probed live); every appended mesh already carries its normals.
	return st.commit()

## Ancourage: the squat drum earns its missing top 40% — a fat overhanging eave ring at the waist and
## a 2-lobe squashed dome cluster seated on the eave line (the plate's silhouette), door cut kept in
## the drum wall.
static func _ancourage_domes_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var r := float(spec.get("radius", 2.7))
	var h := float(spec.get("height", 4.6))
	var body_h := h * 0.53
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_cylinder_with_doors(r, body_h, reserved, recess), 0, Transform3D.IDENTITY)
	var eave := TorusMesh.new()
	eave.inner_radius = r * 0.86
	eave.outer_radius = r * 1.2
	eave.rings = 20
	eave.ring_segments = 8
	st.append_from(eave, 0, Transform3D(Basis(), Vector3(0.0, body_h, 0.0)))
	var main := SphereMesh.new()
	main.radius = r * 0.78
	main.height = (h - body_h) * 2.0
	main.radial_segments = 16
	main.rings = 8
	# placed by its TOP so the apex lands exactly at the spec height
	st.append_from(main, 0, Transform3D(Basis(), Vector3(-r * 0.25, h - main.height * 0.5, 0.0)))
	var side := SphereMesh.new()
	side.radius = r * 0.6
	side.height = r * 0.78
	side.radial_segments = 14
	side.rings = 7
	st.append_from(side, 0, Transform3D(Basis(), Vector3(r * 0.38, body_h, r * 0.12)))
	# NO generate_normals here: on mixed append_from sources it DROPS earlier surfaces
	# (probed live); every appended mesh already carries its normals.
	return st.commit()

## Beacon Hill (REVIEW P1): the drum ends at 0.75H, curves through an elliptical dome shoulder and
## closes with a rooftop lantern drum — the flat merlon top read as a water tank, not the Reading Room.
static func _beacon_domed_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var r := float(spec.get("radius", 2.4))
	var h := float(spec.get("height", 7.2))
	var drum_h := h * 0.75
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_cylinder_with_doors(r, drum_h, reserved, recess), 0, Transform3D.IDENTITY)
	var dome := SphereMesh.new()
	dome.radius = r * 1.0
	dome.height = h * 0.23 * 2.0
	dome.radial_segments = 16
	dome.rings = 8
	st.append_from(dome, 0, Transform3D(Basis(), Vector3(0.0, drum_h, 0.0)))
	var lantern := CylinderMesh.new()
	lantern.top_radius = r * 0.45
	lantern.bottom_radius = r * 0.45
	lantern.height = h * 0.085
	lantern.radial_segments = 12
	st.append_from(_seated(lantern, lantern.height * 0.5), 0, Transform3D(Basis(), Vector3(0.0, h - lantern.height - h * 0.02, 0.0)))
	var fin := SphereMesh.new()
	fin.radius = r * 0.16
	fin.height = h * 0.04
	fin.radial_segments = 10
	fin.rings = 5
	st.append_from(fin, 0, Transform3D(Basis(), Vector3(0.0, h - h * 0.02, 0.0)))
	# NO generate_normals (drops earlier append_from surfaces); sources carry their own.
	return st.commit()

## Hypelines (REVIEW P1-P2): a three-tier domed mound with radiating pipeline ARMS at the shoulder —
## the junction-hub read. Arms are part of the massing (the silhouette), not the draped-pipes pass.
static func _hypelines_mound_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var r := float(spec.get("radius", 2.6))
	var h := float(spec.get("height", 6.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# tier 1 skirt (doors) / tier 2 mid drum / tier 3 upper drum, strong shrink-up
	st.append_from(_cylinder_with_doors(r, h * 0.38, reserved, recess), 0, Transform3D.IDENTITY)
	var t2 := CylinderMesh.new()
	t2.top_radius = r * 0.62
	t2.bottom_radius = r * 0.78
	t2.height = h * 0.30
	t2.radial_segments = 18
	st.append_from(_seated(t2, t2.height * 0.5), 0, Transform3D(Basis(), Vector3(0.0, h * 0.38, 0.0)))
	var t3 := CylinderMesh.new()
	t3.top_radius = r * 0.38
	t3.bottom_radius = r * 0.5
	t3.height = h * 0.22
	t3.radial_segments = 14
	st.append_from(_seated(t3, t3.height * 0.5), 0, Transform3D(Basis(), Vector3(0.0, h * 0.68, 0.0)))
	var cap := SphereMesh.new()
	cap.radius = r * 0.4
	cap.height = (h - h * 0.9) * 2.0
	cap.radial_segments = 14
	cap.rings = 7
	st.append_from(cap, 0, Transform3D(Basis(), Vector3(0.0, h - cap.height * 0.5, 0.0)))
	# 6 radiating LANE arms leaving the shoulder — these are level infrastructure, not dressing:
	# each arm tip is exported as a BRIDGE connector socket (hypelines_arms), so the level layer can
	# dock walkable lanes onto them (the director's walkable-lanes directive).
	for a in hypelines_arms(spec):
		var ad := a as Dictionary
		var arm := CylinderMesh.new()
		arm.top_radius = h * 0.045
		arm.bottom_radius = h * 0.045
		arm.height = r * 2.3
		arm.radial_segments = 10
		var dirv := ad["dir"] as Vector3
		var basis := Basis(Quaternion(Vector3.UP, dirv.normalized()))
		st.append_from(arm, 0, Transform3D(basis, (ad["base"] as Vector3) + dirv * r * 0.55))
	return st.commit()

## The hypelines lane-arm table: {base, dir, tip} per arm — the ONE source both the massing mesh and
## the gameplay bridge sockets read, so a walkable lane docked at a socket always meets its arm.
static func hypelines_arms(spec: Dictionary) -> Array:
	var r := float(spec.get("radius", 2.6))
	var h := float(spec.get("height", 6.2))
	var out: Array = []
	for i in range(6):
		var side := 1.0 if i < 3 else -1.0
		var az := deg_to_rad(float([30.0, 60.0, 90.0][i % 3])) * side
		var pitch := float([0.06, 0.2, 0.12][i % 3])
		var dirv := Vector3(cos(az), 0.0, sin(az)).rotated(Vector3(sin(az), 0.0, -cos(az)).normalized(), pitch).normalized()
		var base := Vector3(0.0, h * (0.55 + 0.07 * float(i % 3)), 0.0)
		out.append({"base": base, "dir": dirv, "tip": base + dirv * (r * 0.55 + r * 1.15)})
	return out

## Greenfields (REVIEW P1): the stacked-cushions read — a box body wearing four overhanging
## bone-cream balcony slab rings, one above each storey.
static func _greenfields_stack_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var size: Vector3 = spec.get("size", Vector3(5.2, 6.4, 5.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_box_with_doors(size, reserved, recess), 0, Transform3D.IDENTITY)
	var ground := 1.7
	var storey := (size.y - ground) / 3.0
	for k in range(4):
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x + 0.7, 0.18, size.z + 0.7)
		var y := ground + storey * float(k)
		st.append_from(slab, 0, Transform3D(Basis(), Vector3(0.0, minf(y, size.y - 0.09), 0.0)))
	return st.commit()

## Bulwark Wharf (REVIEW P1): the gatehouse earns its two round corner towers — half-embedded at the
## front corners, rising past the roofline, domed caps + ring collars.
static func _bulwark_towers_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var size: Vector3 = spec.get("size", Vector3(4.2, 5.2, 3.6))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body_h := size.y * 0.86
	st.append_from(_box_with_doors(Vector3(size.x, body_h, size.z), reserved, recess), 0, Transform3D.IDENTITY)
	var tr := size.x * 0.14
	for sx in [-1.0, 1.0]:
		var cx := float(sx) * (size.x * 0.5)
		var cz := size.z * 0.5
		var tower := CylinderMesh.new()
		tower.top_radius = tr
		tower.bottom_radius = tr * 1.15
		tower.height = size.y * 0.94
		tower.radial_segments = 12
		st.append_from(_seated(tower, tower.height * 0.5), 0, Transform3D(Basis(), Vector3(cx, 0.0, cz)))
		var capd := SphereMesh.new()
		capd.radius = tr * 1.05
		capd.height = (size.y - size.y * 0.94) * 2.0 + tr * 0.8
		capd.radial_segments = 12
		capd.rings = 6
		st.append_from(capd, 0, Transform3D(Basis(), Vector3(cx, size.y - capd.height * 0.5, cz)))
		for fr in [0.25, 0.5, 0.75]:
			var collar := TorusMesh.new()
			collar.inner_radius = tr * 0.95
			collar.outer_radius = tr * 1.22
			collar.rings = 14
			collar.ring_segments = 6
			st.append_from(collar, 0, Transform3D(Basis(), Vector3(cx, size.y * 0.94 * fr, cz)))
	return st.commit()

## Zone-3 (REVIEW P1-P2): the eroded ruin is a TWO-part composite — main block + a collapsed
## side wing stepped back — crowned by a heavy projecting cornice slab on the main block only.
static func _zone3_split_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var size: Vector3 = spec.get("size", Vector3(4.0, 5.4, 4.0))
	var w := size.x
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a_h := size.y
	st.append_from(_box_with_doors(Vector3(w, a_h, w * 0.9), reserved, recess), 0, Transform3D.IDENTITY)
	var cornice := BoxMesh.new()
	cornice.size = Vector3(w + w * 0.18, a_h * 0.06, w * 0.9 + w * 0.18)
	st.append_from(cornice, 0, Transform3D(Basis(), Vector3(0.0, a_h - cornice.size.y * 0.5, 0.0)))
	var wing := BoxMesh.new()
	wing.size = Vector3(w * 0.6, a_h * 0.83, w * 0.7)
	st.append_from(_seated(wing, wing.size.y * 0.5), 0,
		Transform3D(Basis(), Vector3(w * 0.5 + wing.size.x * 0.45, 0.0, -w * 0.9 * 0.5 + wing.size.z * 0.5)))
	return st.commit()

# --- RECURSIVE CONNECTED AWNINGS (the Open Files massing — geometry-lab algorithm 2, ported) -------
#
# A core prism wears an awning on all four sides; each awning recurses off its skirt (out + down,
# with a floored curve-driven extra shift), and adjacent faces' awnings MERGE at shared corners on a
# deterministic per-level dice roll — the blocky, stepped, converging-butte mass. Building-grade
# changes from the lab workbench: consistent OUTWARD winding (the lab ran CULL_DISABLED), skirts end
# exactly on the next level's roof edge (a watertight seam instead of nested ground shells), the
# LAST level's skirt is the ground facade and takes the real door cut, and the recursion stops while
# that facade is still tall enough for a door.

## The shared layout both the base mesh and the rackwork read (they must never diverge).
## Returns {faces:[per-face Array of level dicts], levels_y, proj, step, core:Vector2(hx,hz), h}.
## A level dict = _awning_points + "bottom_y" (where its skirt hands over to the next roof; 0 = ground).
static func _awning_layout(spec: Dictionary) -> Dictionary:
	var size: Vector3 = spec.get("size", Vector3(5.6, 9.0, 5.6))
	var step := float(spec.get("awning_step", 1.0))
	var angle := deg_to_rad(clampf(float(spec.get("awning_angle", 68.0)), 5.0, 85.0))
	var max_shift := float(spec.get("awning_shift", 2.0))
	var depth := maxi(1, int(spec.get("awning_depth", 3)))
	var door_clear := float(spec.get("door_clear_y", 2.8))
	var proj := step / tan(angle)
	# Dry-run the level heights: y[d] is level d's A/B height. Stop while the ground facade (the last
	# skirt, from y_last - step down to 0) can still hold a door.
	var levels_y: Array = []
	var y := size.y
	var d := 0
	while d <= depth:
		levels_y.append(y)
		var t := clampf(float(d + 1) / float(depth), 0.0, 1.0)
		var shift := floorf(max_shift * t) * step
		var next_y := y - step - shift
		if next_y - step < door_clear + step * 0.4:
			break
		y = next_y
		d += 1
	var flare := proj * float(levels_y.size())
	var hx := maxf(0.8, size.x * 0.5 - flare)
	var hz := maxf(0.8, size.z * 0.5 - flare)
	# 4 top corners in rotational order (the lab's frame): face fi spans corner[fi]->corner[fi+1],
	# outward normal[fi]; B of face fi == A of face fi+1 (the shared merge corner).
	var corners := [Vector3(hx, size.y, hz), Vector3(-hx, size.y, hz), Vector3(-hx, size.y, -hz), Vector3(hx, size.y, -hz)]
	var normals := [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
	var faces: Array = []
	for fi in range(4):
		var a: Vector3 = corners[fi]
		var b: Vector3 = corners[(fi + 1) % 4]
		var n: Vector3 = normals[fi]
		var lv: Array = []
		for k in range(levels_y.size()):
			var pts := _awning_points_at(a, b, n, proj, step)
			pts["bottom_y"] = float(levels_y[k + 1]) if k + 1 < levels_y.size() else 0.0
			pts["n"] = n
			lv.append(pts)
			if k + 1 < levels_y.size():
				var drop: float = float(levels_y[k]) - float(levels_y[k + 1]) - step
				a = (pts["E"] as Vector3) - Vector3(0.0, drop, 0.0)
				b = (pts["F"] as Vector3) - Vector3(0.0, drop, 0.0)
		faces.append(lv)
	return {"faces": faces, "levels_y": levels_y, "proj": proj, "step": step,
		"core": Vector2(hx, hz), "h": size.y}

# The lab's 10-point awning construction off a top edge A-B (outward normal n): C/D one step below,
# E/F out by proj at C/D's height. G/H/I/J are derived by the emitters (bottom_y varies per level).
static func _awning_points_at(a: Vector3, b: Vector3, n: Vector3, proj: float, step: float) -> Dictionary:
	var c := a - Vector3(0.0, step, 0.0)
	var d := b - Vector3(0.0, step, 0.0)
	return {"A": a, "B": b, "C": c, "D": d, "E": c + n * proj, "F": d + n * proj}

## The full awning-stack solid. `reserved` box door regions cut a real opening + recessed pocket into
## the LAST level's skirt (the ground facade) of their face.
static func _awning_stack_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var lay := _awning_layout(spec)
	var faces: Array = lay["faces"]
	var core: Vector2 = lay["core"]
	var h: float = lay["h"]
	var kb := float(str(spec.get("kind", "open_files")).hash() % 1000)
	var merge_ceiling := clampf(float(spec.get("awning_merge", 0.55)), 0.0, 1.0)
	var n_levels: int = (faces[0] as Array).size()

	# Merge dice per shared corner per level (deterministic hash chain, rises with depth like the
	# lab's default merge curve). merged[fi][k] = face fi's RIGHT corner merges face fi+1's LEFT.
	var merged: Array = []
	for fi in range(4):
		var arr: Array = []
		for k in range(n_levels):
			var t := float(k) / float(maxi(1, n_levels - 1))
			arr.append(_h01(kb + 7.0 + float(fi) * 31.7 + float(k) * 11.3) < merge_ceiling * t)
		merged.append(arr)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Core top cap (the flat roof between the four level-0 roof edges).
	_quad_out(st, Vector3(-core.x, h, -core.y), Vector3(core.x, h, -core.y),
		Vector3(core.x, h, core.y), Vector3(-core.x, h, core.y), Vector3(0, h - 2.0, 0))
	for fi in range(4):
		var lv: Array = faces[fi]
		var right_merge: Array = merged[fi]
		var left_merge: Array = merged[(fi + 3) % 4]
		for k in range(lv.size()):
			var last := k == lv.size() - 1
			var door = _box_door_on((lv[k] as Dictionary)["n"] as Vector3, reserved) if last else null
			_emit_awning_level(st, lv[k] as Dictionary, bool(left_merge[k]), bool(right_merge[k]), door, recess)
	# EVERY corner gets the chamfer closure (top tri + diagonal fill): without it, the pie wedge
	# between two adjacent gables is OPEN from above — you look straight down between the end walls
	# into the notch shadow (the "holes" report). A merged corner additionally omitted its gables +
	# end walls above, so the closure reads as the awnings flowing around the corner; an unmerged
	# corner keeps its step and the closure reads as a chamfered cap.
	for fi in range(4):
		var la: Array = faces[fi]
		var lb: Array = faces[(fi + 1) % 4]
		for k in range(mini(la.size(), lb.size())):
			_emit_merge_bridge(st, la[k] as Dictionary, lb[k] as Dictionary)
	_emit_awning_ground(st, lay)
	st.generate_normals()
	return st.commit()

# One awning level: roof ABFE; end gable+wall per corner unless that corner merges; the skirt E..F
# down to bottom_y — with a real door opening + pocket when `door` is set (the ground facade).
static func _emit_awning_level(st: SurfaceTool, pts: Dictionary, skip_left: bool, skip_right: bool, door, recess: float) -> void:
	var a: Vector3 = pts["A"]
	var b: Vector3 = pts["B"]
	var c: Vector3 = pts["C"]
	var dd: Vector3 = pts["D"]
	var e: Vector3 = pts["E"]
	var f: Vector3 = pts["F"]
	var n: Vector3 = pts["n"]
	var by := float(pts["bottom_y"])
	var up := Vector3.UP
	var u := (b - a).normalized()
	var roof_hint := (a + b + e + f) * 0.25 - n * 0.6 - up * 0.9
	_quad_out(st, a, b, f, e, roof_hint)
	if not skip_left:
		_tri_out(st, a, e, c, (a + e + c) / 3.0 + u * 1.0)                 # left gable (faces -u)
		var cg := Vector3(c.x, by, c.z)
		var eg := Vector3(e.x, by, e.z)
		_quad_out(st, c, e, eg, cg, (c + e + eg + cg) * 0.25 + u * 1.0)    # left end wall
	if not skip_right:
		_tri_out(st, b, f, dd, (b + f + dd) / 3.0 - u * 1.0)               # right gable (faces +u)
		var dh := Vector3(dd.x, by, dd.z)
		var fh := Vector3(f.x, by, f.z)
		_quad_out(st, dd, f, fh, dh, (dd + f + fh + dh) * 0.25 - u * 1.0)  # right end wall
	# the skirt (with the door cut on the ground facade)
	var eb := Vector3(e.x, by, e.z)
	var fb := Vector3(f.x, by, f.z)
	var skirt_hint := (e + f + fb + eb) * 0.25 - n * 1.0
	if door == null:
		_quad_out(st, e, f, fb, eb, skirt_hint)
		return
	var fw := e.distance_to(f)
	var hw: float = float(door.get("open_half_w", door.get("half_w", 0.5)))
	var yt: float = float(door.get("open_y_top", door.get("y_top", 2.0)))
	yt = minf(yt, e.y - 0.15)
	var lx := fw * 0.5 + float(door["x_center"]) - hw
	var rx := fw * 0.5 + float(door["x_center"]) + hw
	var bl := eb   # skirt base-left; right along u (E->F matches the face's A->B direction)
	_quad_out(st, bl, bl + u * lx, bl + u * lx + up * (e.y - by), bl + up * (e.y - by), skirt_hint)   # left of hole
	_quad_out(st, bl + u * rx, fb, f, bl + u * rx + up * (e.y - by), skirt_hint)                       # right of hole
	_quad_out(st, bl + u * lx + up * yt, bl + u * rx + up * yt,
		bl + u * rx + up * (e.y - by), bl + u * lx + up * (e.y - by), skirt_hint)                      # above hole
	var pl := bl + u * lx
	var pr := bl + u * rx
	var back := -n * recess
	_quad_out(st, pl + back, pr + back, pr + back + up * yt, pl + back + up * yt, pl + back * 3.0)     # pocket back
	_quad_out(st, pl, pl + back, pl + back + up * yt, pl + up * yt, pl - u * 1.0)                      # left jamb
	_quad_out(st, pr + back, pr, pr + up * yt, pr + back + up * yt, pr + u * 1.0)                      # right jamb
	_quad_out(st, pl + up * yt, pl + back + up * yt, pr + back + up * yt, pr + up * yt, pl + up * (yt + 3.0))  # lintel (faces down)

# Bridge face fi's right corner to face fi+1's left at one level: the chamfer roof + the diagonal
# fill dropping to the notch ground. FOUR points, not three (director's report): only at level 0 do
# the two faces share one corner point — at every deeper level face i's B and face i+1's A are
# DIFFERENT points (each face's edge moved outward along its OWN normal), so a single-apex triangle
# left a wedge hole at every merged corner below the top. The quad degenerates to the level-0
# triangle by itself when B == A.
static func _emit_merge_bridge(st: SurfaceTool, pa: Dictionary, pb: Dictionary) -> void:
	var b1: Vector3 = pa["B"]     # face i's top corner point
	var a2: Vector3 = pb["A"]     # face i+1's top corner point (== b1 only at level 0)
	var f1: Vector3 = pa["F"]
	var e2: Vector3 = pb["E"]
	var out_dir := ((pa["n"] as Vector3) + (pb["n"] as Vector3)).normalized()
	var hint := (b1 + a2 + f1 + e2) * 0.25 - out_dir * 0.8 - Vector3.UP * 0.4
	_quad_out(st, b1, a2, e2, f1, hint)
	var g2 := Vector3(e2.x, 0.0, e2.z)
	var h1 := Vector3(f1.x, 0.0, f1.z)
	var wall_hint := (f1 + e2 + g2 + h1) * 0.25 - out_dir * 1.0
	_quad_out(st, f1, e2, g2, h1, wall_hint)

# --- RACKWORK: the faces-extrude lattice (director's spec) ----------------------------------------
# "Instead of pipes down the edges, take the FACES and EXTRUDE them out by a [PARAMETER] depth" —
# the recessed server-rack channels. Each exposed skirt band carries rows of closed DRAWER boxes
# standing `rack_depth` proud of the facade (a hash-chosen few pulled further out — the open-drawer
# read); the gaps between them are the recessed channels. Green LED matrices ride the drawer fronts
# as a SEPARATE emissive mesh (single-sided cards — kept out of the red-shell scan like the glass).
## Returns {"frame": ArrayMesh (closed drawer boxes), "leds": ArrayMesh (emissive matrix cards)}.
static func rack_mesh(spec: Dictionary, reserved: Array = []) -> Dictionary:
	var lay := _awning_layout(spec)
	var depth := float(spec.get("rack_depth", 0.14))
	var kb := float(str(spec.get("kind", "open_files")).hash() % 1000)
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leds := SurfaceTool.new()
	leds.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row_h := 0.30
	var gap := 0.05
	for fi in range(4):
		var lv: Array = (lay["faces"] as Array)[fi]
		for k in range(lv.size()):
			var pts := lv[k] as Dictionary
			var n: Vector3 = pts["n"]
			var e: Vector3 = pts["E"]
			var f: Vector3 = pts["F"]
			var by := float(pts["bottom_y"])
			var door = _box_door_on(n, reserved) if k == lv.size() - 1 else null
			var u := (f - e).normalized()
			var band_w := e.distance_to(f) - 0.5          # keep off the corner walls
			var band_top := e.y - 0.10
			var band_bot := by + 0.10
			if band_top - band_bot < row_h or band_w < 1.0:
				continue
			var rows := int((band_top - band_bot) / (row_h + gap))
			var cols := int(band_w / (0.72 + gap))
			var dw := (band_w - float(cols - 1) * gap) / float(cols)
			var origin := e + u * 0.25 + Vector3(0, -(e.y - band_top), 0)
			for r in range(rows):
				var ry := band_top - float(r) * (row_h + gap) - row_h * 0.5
				for cc in range(cols):
					var cx := (float(cc) + 0.5) * dw + float(cc) * gap
					var center := Vector3(origin.x, ry, origin.z) + u * cx
					# door clearance on the ground facade: skip drawers overlapping the doorway
					if door != null:
						var hw := float(door.get("half_w", 0.6)) + dw * 0.5
						var xc := e.distance_to(f) * 0.5 + float(door["x_center"])
						if absf((cx + 0.25) - xc) < hw and ry - row_h * 0.5 < float(door.get("y_top", 2.0)) + 0.1:
							continue
					var pull := depth * (1.55 if _h01(kb + float(fi) * 91.3 + float(k) * 17.1 + float(r) * 5.7 + float(cc) * 2.3) > 0.82 else 1.0)
					# bury the back face 5 cm INSIDE the skirt — an exactly-coplanar back z-fights
					# with the facade (the shimmer bands report)
					_emit_oriented_box_st(frame, center + n * ((pull - 0.05) * 0.5),
						u, Vector3.UP, n, Vector3(dw * 0.5, row_h * 0.5, (pull + 0.05) * 0.5))
					# the LED matrix: a hash-lit grid of small cards on the drawer front
					var front := center + n * (pull + 0.014)
					for my in range(2):
						for mx in range(4):
							if _h01(kb + float(fi) * 3.1 + float(k) * 7.7 + float(r) * 13.9 + float(cc) * 29.3 + float(my) * 4.9 + float(mx) * 1.7) > 0.72:
								continue
							var lc := front + u * ((float(mx) - 1.5) * dw * 0.18) + Vector3(0, (float(my) - 0.5) * row_h * 0.42, 0)
							var lu := u * 0.032
							var lup := Vector3(0, 0.032, 0)
							leds.add_vertex(lc - lu - lup); leds.add_vertex(lc + lu - lup); leds.add_vertex(lc + lu + lup)
							leds.add_vertex(lc - lu - lup); leds.add_vertex(lc + lu + lup); leds.add_vertex(lc - lu + lup)
	frame.generate_normals()
	leds.generate_normals()
	return {"frame": frame.commit(), "leds": leds.commit()}

# The ground underside: the core rectangle + one rectangle per face out to that face's final skirt.
# Corner notches stay open underneath (ground-contact, invisible from any exterior angle).
static func _emit_awning_ground(st: SurfaceTool, lay: Dictionary) -> void:
	var core: Vector2 = lay["core"]
	var above := Vector3(0, 2.0, 0)
	_quad_out(st, Vector3(-core.x, 0, -core.y), Vector3(core.x, 0, -core.y),
		Vector3(core.x, 0, core.y), Vector3(-core.x, 0, core.y), above)
	for fi in range(4):
		var lv: Array = (lay["faces"] as Array)[fi]
		var lastp := lv[lv.size() - 1] as Dictionary
		var n: Vector3 = lastp["n"]
		var e: Vector3 = lastp["E"]
		var f: Vector3 = lastp["F"]
		var out_e := Vector3(e.x, 0.0, e.z)
		var out_f := Vector3(f.x, 0.0, f.z)
		var in_e := out_e - n * ((out_e - Vector3(0, 0, 0)).dot(n) - (core.x if absf(n.x) > 0.5 else core.y))
		var in_f := out_f - n * ((out_f - Vector3(0, 0, 0)).dot(n) - (core.x if absf(n.x) > 0.5 else core.y))
		_quad_out(st, in_e, in_f, out_f, out_e, above)

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
