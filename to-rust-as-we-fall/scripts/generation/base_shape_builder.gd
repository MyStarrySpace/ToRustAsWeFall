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
	"aghora_exchange", "aghora_stack", "locas_watchtower", "nutech_facility",
]

## Reference-derived proportions. Dimensions are metres; the base sits on y=0.
const SPECS := {
	"plumbing_power": {
		"title": "Plumbing Power Project",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.1: ONE lofted lathe from the
		"composite": "plumbing_lobed",      # BuildingSurvey.PLUMBING ring table (skirt/drum/dome/cupola)
		"door_frame": "cyl",
		"door_radius": 1.59,                # the front lobe VALLEY the door cuts: 0.355H*(1-0.20)
		"flare": 1.0,
		"radius": 2.39,                     # silhouette crest at ground: 0.355H*1.20 (footprint 0.85H)
		"height": 5.6,
		# Entry reconciled at the survey: the plate's hood scaled to the character door (0.9 x 1.5 m
		# inside the 1.4 m pitched hood); the plate shows NO side doors; the hood replaces the generic
		# canopy slab; the reserve margin is trimmed so the sign board clears the door band.
		"entrances": {"main_w": 0.9, "main_h": 1.5, "side_count_min": 0, "side_count_max": 0,
			"reserve_margin": 0.25, "canopy_out": 0.0, "main_surround": false},
		"color": Color(0.24, 0.35, 0.32),   # dark desaturated verdigris (plate palette)
		"tile": "facility_metal",
		"lattice": "",
		"pipes": false,                     # no draped tangle on the plate — the flume, dome ribs and
	},                                      # ONE side pipe come from the survey (plumbing_details)
	"honeycomb_cooperative": {
		"title": "Honeycomb Cooperative",
		"shape": SHAPE_BOX,                 # SURVEY REBUILD 1.9: the intact faces wear the sasb
		"size": Vector3(4.5, 10.0, 6.3),    # honeyframe; fixtures ride its REAL cell rects
		# the entry idiom (teal door + cyan transom + sconces + kiosk) owns the threshold; the
		# reserve margin stays slim so the clearance doesn't gut the storey-scale cell blobs
		"entrances": {"main_w": 1.6, "main_h": 2.7, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.2, "main_surround": false},
		"color": Color(0.48, 0.46, 0.38),   # cast-stone facade, darker (plate palette)
		"tile": "facility_metal",
		"lattice": "honeyframe",            # rounded-cell facade frame + lit panes
		"lattice_overrides": {"skip_faces": [Vector3(1, 0, 0)]},   # the TORN flank goes bare
		"pipes": true,                      # rust/conduit tangle down the flank
	},
	"beacon_hill": {
		"title": "Beacon Hill",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.6: the bell-jar as ONE loft from the
		"composite": "beacon_domed",        # BuildingSurvey.BEACON rings (flare/drum/shoulder/lantern)
		"door_frame": "cyl",
		"door_radius": 2.60,                # the wall's NARROWEST radius in the door band (the
											# bell-jar tapers: the portal recesses deep, plate-true)
		"radius": 2.77,                     # H:W 1.30 off the plate (was a too-slender 1.5)
		"height": 7.2,
		"tracery_height": 5.4,              # the REAR lancet tracery climbs the drum only
		"color": Color(0.20, 0.31, 0.28),   # dark verdigris tiled stone
		"tile": "facility_metal",
		"lattice": "tracery",               # restructured AROUND the five great-bay reservations:
		"bays": 12,                         # the lancet field only populates unreserved (rear) arcs
		# RECONCILED AT THE SURVEY: the portal + oval cartouche are the door's idiom
		# (beacon_details); the enforcement vestibule is the plate's second door (cyan accent).
		"entrances": {"main_w": 1.2, "main_h": 1.7, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "main_surround": false},
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
		# SURVEY REBUILD 1.10: the nested hex-arch portal owns the threshold (no generic stone);
		# reserve_margin 0.25 keeps the door region under the sign band at every roll
		"entrances": {"main_w": 1.5, "main_h": 2.2, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.25, "main_surround": false},
		"color": Color(0.31, 0.35, 0.37),   # dark steel-blue with rust + teal server glow
		"tile": "facility_metal",
		"lattice": "rackwork",              # extruded-face drawer strata + green LED matrices
	},
	"hypelines": {
		"title": "The Hypelines",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.2: ONE lofted lathe from the
		"composite": "hypelines_mound",     # BuildingSurvey.HYPELINES ring table (skirt/drum/dome)
		"door_frame": "cyl",
		"door_radius": 1.53,                # the front lobe VALLEY the door cuts: 0.325H*(1-0.24)
		"radius": 2.5, "height": 6.2,       # silhouette crest at ground: 0.403H (foot 0.81H, plate)
		"flare": 1.0,
		# RECONCILED AT THE SURVEY: doors sized to the character inside the plate's parabolic
		# toll-gate arch (the arch idiom + toll board are survey detail passes); no canopy slab —
		# the arch is the entry architecture.
		"entrances": {"main_w": 0.9, "main_h": 1.5, "side_w": 0.8, "side_h": 1.4, "canopy_out": 0.0,
			"main_surround": false},
		"color": Color(0.26, 0.33, 0.29),   # dark verdigris-rust
		"tile": "facility_metal",
		"lattice": "", "pipes": true,       # the drapes stand in for the plate's vein-tendril wrap
	},
	"greenfields": {
		"title": "Greenfields Collective",
		"shape": SHAPE_COMPOSITE,           # stacked-cushions: overhanging balcony slab rings (REVIEW P1)
		"composite": "greenfields_stack",
		"size": Vector3(5.2, 6.4, 5.0),
		# RECONCILED AT THE SURVEY: the first slab ring rides the 1.7 m ground-storey datum — the
		# default 2.7 m portal ran straight through it. Plate ratio (BUILDING_REVIEW greenfields #4):
		# arcade arch top ~80% of the 1.7 m ground storey ~= 1.35 m.
		"entrances": {"main_w": 1.1, "main_h": 1.32, "side_w": 0.9, "side_h": 1.25, "reserve_margin": 0.08,
			"main_surround": false, "canopy_out": 0.0},
		"color": Color(0.35, 0.45, 0.39),   # verdigris ashlar WALLS — the bone structure is the
		"tile": "facility_metal",           # balconies pass (greenfields_details), two-tone (plate)
		"lattice": "balconies",             # the wavy slab rings + rails + arcade + windows (survey)
	},
	"ancourage": {
		"title": "Ancourage",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.5: ONE continuous kiosk loft from the
		"composite": "ancourage_domes",     # BuildingSurvey.ANCOURAGE rings (body/brim/2-lobe dome)
		"door_frame": "cyl",
		"door_radius": 2.25,                # the round body wall the door cuts: 0.489H
		"radius": 2.60, "height": 4.6,      # silhouette max = the brim: 0.565H (wider than tall)
		# RECONCILED AT THE SURVEY: the entry is the plate's grand arch idiom (plank door under the
		# green cell-glass band, ancourage_details) — no generic surround, no side doors.
		"entrances": {"main_w": 1.0, "main_h": 1.5, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "main_surround": false},
		"color": Color(0.27, 0.36, 0.33),   # dark verdigris
		"tile": "facility_metal",
		"lattice": "", "pipes": true,       # the drapes stand in for the plate's drip veins
	},
	"bulwark_wharf": {
		"title": "Bulwark Wharf",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.7: gatehouse box + FOUR corner-tower
		"composite": "bulwark_towers",      # lofts from the BuildingSurvey.BULWARK table
		"size": Vector3(4.6, 5.2, 3.4),
		# RECONCILED AT THE SURVEY: reserve_margin 0.18 keeps the door region (y_top = h+jamb+margin)
		# under the sign band at EVERY height roll (sign y0 scales with H, the margin does not) and
		# its clearance width off the kiosk; the vault-door idiom owns its own threshold
		"entrances": {"main_w": 1.15, "main_h": 2.0, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.18, "main_surround": false},
		"color": Color(0.32, 0.36, 0.39),
		"tile": "facility_metal",
		"lattice": "",                      # the membrane is the FRAMED front panel + wings (details)
	},
	"cleanstreets": {
		"title": "The Cleanstreets Initiative",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.3: OPEN toll-canopy pavilion from the
		"composite": "canopy_piers",        # BuildingSurvey.CLEANSTREETS table (dais/piers/canopy)
		"size": Vector3(11.0, 6.0, 7.0),
		# RECONCILED AT THE SURVEY: the pavilion has NO front door — the main door IS the toll
		# portal on the +X flank (door_face 2) toward the front (door_lateral -2.2), where the
		# plate's road arrives; the queue lanes stay open; no canopy slab over the portal.
		"door_face": 2, "door_lateral": -2.2,
		"entrances": {"main_w": 0.9, "main_h": 2.0, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0},
		"color": Color(0.45, 0.47, 0.42),   # bone/tan mosaic base, verdigris panels ride the texture pass
		"tile": "facility_metal",
		"lattice": "",
	},
	"zone3": {
		"title": "Zone-3 Eroded Ruin",
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.8: split massing from the ZONE3 plan
		"composite": "zone3_split",         # datums (intact main + gutted wing + cornice slab)
		"size": Vector3(4.0, 5.4, 3.6),
		# RECONCILED AT THE SURVEY: reserve_margin 0.18 keeps the door region under the sign band;
		# the slat-roofed PORCH is the door idiom (no generic stone)
		"entrances": {"main_w": 1.0, "main_h": 1.9, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.18, "main_surround": false},
		"color": Color(0.28, 0.30, 0.28),
		"tile": "facility_metal",
		"lattice": "",
	},
	"aghora_exchange": {
		"title": "Aghora Exchange",
		"shape": SHAPE_COMPOSITE,           # the counterfeit agora's market hall (user plates,
		"composite": "aghora_domed",        # 2026-07-11): bazaar drum + tiered bell dome + the
		"door_frame": "cyl",                # the market arch cuts the DRUM wall, not a box face
		"height": 8.0,                      # great magenta neon ring — BuildingSurvey.AGHORA
		"radius": 2.88,                     # 0.360 * H (the foot flare)
		"door_radius": 2.72,                # 0.340 * H (the wall band the arch cuts)
		"bays": 12,
		"entrances": {"main_w": 1.6, "main_h": 2.2, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.25, "main_surround": false},
		"color": Color(0.26, 0.34, 0.32),   # dark verdigris; magenta neon + amber interiors ride details
		"tile": "facility_metal",
		"lattice": "",
		"pipes": true,                      # the plates crawl with conduit
	},
	"aghora_stack": {
		"title": "Aghora Bazaar Stack",
		"shape": SHAPE_BOX,                 # the canyon wall unit: stacked warm storefronts +
		"size": Vector3(5.0, 11.0, 4.2),    # awning rows + hanging neon banners (AGHORA_STACK)
		"entrances": {"main_w": 1.4, "main_h": 2.1, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.20, "main_surround": false},
		"color": Color(0.28, 0.35, 0.33),
		"tile": "facility_metal",
		"lattice": "",
		"pipes": true,
	},
	"nutech_facility": {
		"title": "NUTECH Facility",
		"shape": SHAPE_BOX,                 # the abandoned spray facility (GDD 11.2; paranucleus
		"size": Vector3(6.0, 7.2, 4.6),     # plate base cluster): a flat-roofed grey institutional
		# slab — storey window grids, the white roofline board, parapet + reservoir tanks + plant,
		# a loading dock flank. The Paranucleus grows over instances of THIS type.
		"entrances": {"main_w": 1.4, "main_h": 2.2, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.25, "main_surround": false},
		"color": Color(0.40, 0.41, 0.43),   # grey institutional concrete
		"tile": "facility_metal",
		"lattice": "",
		"pipes": false,
	},
	"locas_watchtower": {
		"title": "Loca's Watchtower",
		"shape": SHAPE_COMPOSITE,           # the Act 1 boss mega-landmark (GDD 11.1, boss plate
		"composite": "watchtower_tiers",    # 2026-07-11): three battered masonry tiers as ONE box
		"size": Vector3(6.4, 13.0, 6.4),    # loft over BuildingSurvey.LOCAS.tiers + the observation
		# cage at the crown holding Loca's bound chamber (fever-red core + containment tangles).
		# The mountain + switchback approach are fragment staging, not this spec.
		"entrances": {"main_w": 1.5, "main_h": 2.4, "side_count_min": 0, "side_count_max": 0,
			"canopy_out": 0.0, "reserve_margin": 0.20, "main_surround": false},
		"color": Color(0.33, 0.37, 0.43),   # cold institutional masonry (the cool-blue-lit plate)
		"tile": "facility_metal",
		"lattice": "",
		"pipes": false,                     # the crawl on this tower is the TANGLES (details), not pipes
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

## Resolve a building to its spec. The buildings are TYPES, not one-offs: seed 0 is the canonical
## plate specimen; any other seed rolls a plate-plausible VARIANT (BuildingSurvey.roll_vars — the
## roller re-reconciles dependent values, and the seed-sweep test proves every variant surveys
## clean). N in the showcase rerolls the whole row.
static func generate(kind: String, seed_value: int = 0) -> Dictionary:
	var key := kind if SPECS.has(kind) else str(BUILDINGS[0])
	var spec: Dictionary = (SPECS[key] as Dictionary).duplicate(true)
	spec["kind"] = key
	if seed_value != 0:
		var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
		var roll: Dictionary = Survey.roll_vars(key, seed_value)
		for k in (roll.get("spec", {}) as Dictionary).keys():
			spec[k] = (roll["spec"] as Dictionary)[k]
		var vars := {}
		for k2 in roll.keys():
			if k2 != "spec":
				vars[k2] = roll[k2]
		if not vars.is_empty():
			spec["vars"] = vars
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

## GAMEPLAY ANCHORS + MASSING PROFILE both live on the SURVEY now (BuildingSurvey, docs/
## SURVEY_REBUILD.md task 0): sockets are placed from the measured drawing (`BuildingSurvey.
## from_spec(spec).anchors()`), and attached parts (draped pipes, weak-point sockets, collars)
## consult the survey's silhouette profile (`radius_at`) so they touch the real surface — the
## mereotopology contract. The *_mesh builders below still carry their construction constants;
## each building's task-1 rebuild moves its meshing onto the survey.

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
		"aghora_domed":
			return _aghora_domed_mesh(spec, reserved, recess)
		"zone3_split":
			return _zone3_split_mesh(spec, reserved, recess)
		"watchtower_tiers":
			return _watchtower_mesh(spec, reserved, recess)
		_:
			return _box(spec.get("size", Vector3(4.0, 6.0, 4.0)))

# --- REVIEW-DRIVEN MASSING (docs/BUILDING_REVIEW.md priority-1 alterations) ------------------------

## Plumbing Power (SURVEY REBUILD 1.1): the melted-boiler massing as ONE LOFTED LATHE from the
## BuildingSurvey.PLUMBING ring table (fused root-lobes -> shoulder drum -> onion dome -> cupola).
## (The survey script is loaded at runtime — the survey reads BaseShapeBuilder's layout tables, so
## a parse-time class reference here would be a dependency cycle.)
static func _plumbing_lobed_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	return _survey_ring_loft(Survey.plumbing_rings(spec), reserved, recess, float(spec.get("height", 5.6)))

## Hypelines (SURVEY REBUILD 1.2): the pipeline-junction mound as the SAME survey ring loft — one
## continuous skirt/drum/dome profile from the BuildingSurvey.HYPELINES table. The arms, decks and
## fixtures are detail passes (hypelines_details) grown from the survey's arm table.
static func _hypelines_mound_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	return _survey_ring_loft(Survey.hypelines_rings(spec), reserved, recess, float(spec.get("height", 6.2)))

## THE SURVEY RING LOFT — one lofted lathe from a survey ring table (lobe-modulated radii), with the
## door cut into the wall (recessed pocket + jambs + lintel) and closed by ground + crown fans. No
## intersecting primitives: every vertex sits on the surveyed surface.
static func _survey_ring_loft(rings: Array, reserved: Array, recess: float, h: float) -> ArrayMesh:
	var door_theta := INF
	var door_half := 0.0
	var door_top := 0.0
	for reg in reserved:
		var rdd := reg as Dictionary
		if bool(rdd.get("cyl", false)):
			door_theta = float(rdd["theta"])
			door_half = float(rdd.get("open_half_arc", rdd.get("half_arc", 0.2)))
			door_top = float(rdd.get("open_y_top", rdd.get("y_top", 2.0)))
	# a ring inserted exactly at the lintel keeps every wall band on one side of the cut
	var rows: Array = rings.duplicate()
	if door_theta != INF:
		for i in range(rows.size() - 1):
			var ya := float((rows[i] as Dictionary)["y"])
			var yb := float((rows[i + 1] as Dictionary)["y"])
			if ya < door_top and door_top < yb:
				var t := (door_top - ya) / (yb - ya)
				var ra := rows[i] as Dictionary
				var rb := rows[i + 1] as Dictionary
				rows.insert(i + 1, {"y": door_top, "r": lerpf(float(ra["r"]), float(rb["r"]), t),
					"lobes": ra["lobes"], "amp": lerpf(float(ra["amp"]), float(rb["amp"]), t),
					"phase": ra["phase"]})
				break
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := CYL_SEGMENTS
	# the pocket back wall sits `recess` behind the ground ring's local wall at the door theta
	var r0d := rings[0] as Dictionary
	var wall0 := float(r0d["r"]) * (1.0 + float(r0d["amp"]) * cos(float(r0d["lobes"]) * ((door_theta if door_theta != INF else 0.0) + float(r0d["phase"]))))
	var back_r: float = maxf(0.35, wall0 - recess)
	for i in range(rows.size() - 1):
		var ra2 := rows[i] as Dictionary
		var rb2 := rows[i + 1] as Dictionary
		var band_mid := (float(ra2["y"]) + float(rb2["y"])) * 0.5
		var band_below := door_theta != INF and float(rb2["y"]) <= door_top + 0.001
		var prev_in := false
		if band_below:
			prev_in = _arc_dist(TAU * (float(seg) - 0.5) / float(seg), door_theta) < door_half
		for s in range(seg):
			var th0 := TAU * float(s) / float(seg)
			var th1 := TAU * float(s + 1) / float(seg)
			var thc := (th0 + th1) * 0.5
			var a0 := _lathe_pt(ra2, th0)
			var a1 := _lathe_pt(ra2, th1)
			var b0 := _lathe_pt(rb2, th0)
			var b1 := _lathe_pt(rb2, th1)
			var in_door := band_below and _arc_dist(thc, door_theta) < door_half
			var hint := Vector3(0, band_mid, 0)
			if not in_door:
				_quad_out(st, a0, a1, b1, b0, hint)
			else:
				# the recessed pocket column: back wall at a fixed radius behind the valley
				var pa0 := Vector3(cos(th0) * back_r, float(ra2["y"]), sin(th0) * back_r)
				var pa1 := Vector3(cos(th1) * back_r, float(ra2["y"]), sin(th1) * back_r)
				var pb0 := Vector3(cos(th0) * back_r, float(rb2["y"]), sin(th0) * back_r)
				var pb1 := Vector3(cos(th1) * back_r, float(rb2["y"]), sin(th1) * back_r)
				_quad_out(st, pa0, pa1, pb1, pb0, Vector3(0, band_mid, 0))
				# lintel underside where the pocket meets the wall band above
				if absf(float(rb2["y"]) - door_top) < 0.002:
					_quad_out(st, pb0, pb1, b1, b0, Vector3(0, door_top + h, 0))
			if band_below and in_door != prev_in:
				# a jamb wall at this column boundary, outer wall -> pocket back
				var jo := _lathe_pt(ra2, th0)
				var jt := _lathe_pt(rb2, th0)
				var ji := Vector3(cos(th0) * back_r, float(ra2["y"]), sin(th0) * back_r)
				var jti := Vector3(cos(th0) * back_r, float(rb2["y"]), sin(th0) * back_r)
				var eps := 0.09 if in_door else -0.09
				var jc := Vector3(cos(th0 - eps), 0.0, sin(th0 - eps)) * (back_r + h) + Vector3(0, band_mid, 0)
				_quad_out(st, ji, jo, jt, jti, jc)
			prev_in = in_door
	# crown fan (the cupola cap apex lands exactly at the spec height) + ground fan
	var top_ring := rows[rows.size() - 1] as Dictionary
	var apex := Vector3(0, h, 0)
	for s2 in range(seg):
		_tri_out(st, apex, _lathe_pt(top_ring, TAU * float(s2) / float(seg)),
			_lathe_pt(top_ring, TAU * float(s2 + 1) / float(seg)), Vector3(0, -h, 0))
	var base_ring := rows[0] as Dictionary
	for s3 in range(seg):
		_tri_out(st, Vector3.ZERO, _lathe_pt(base_ring, TAU * float(s3) / float(seg)),
			_lathe_pt(base_ring, TAU * float(s3 + 1) / float(seg)), Vector3(0, h * 2.0, 0))
	st.generate_normals()
	return st.commit()

# a point on a survey lathe ring (lobe-modulated radius) at absolute angle theta
static func _lathe_pt(ring: Dictionary, theta: float) -> Vector3:
	var r := float(ring["r"]) * (1.0 + float(ring["amp"]) * cos(float(ring["lobes"]) * (theta + float(ring["phase"]))))
	return Vector3(cos(theta) * r, float(ring["y"]), sin(theta) * r)

static func _arc_dist(a: float, b: float) -> float:
	return absf(fposmod(a - b + PI, TAU) - PI)

## Plumbing Power detail passes (SURVEY REBUILD 1.1), every part grown from the survey's frames:
## the descending flume (trough + mesh rails + the terminal-green WATER strip), six dome ribs, the
## handwheel cluster + pipe runs, capillary-slit panels, the sign board, the pitched entry hood,
## the green cascade, and the one vertical side pipe hanging from the flume's underside.
## Returns meshes grouped by material family:
##   body  — construction metal (the building tint)     rust — wheels / pipes / sign frame
##   dark  — slit panels, sign face, pool               glow — water / cascade / terminal screen
##   rails — the flume railing bands (alpha-scissor railing texture, UV-tiled)
## Plus "nameplate_pos": where the showcase's title label rides (ON the sign board).
static func plumbing_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var sv = Survey.from_spec(spec)
	var rings: Array = Survey.plumbing_rings(spec)
	var h := float(spec.get("height", 5.6))
	var body := _st()
	var rust := _st()
	var dark := _st()
	var glow := _st()
	var rails := _st()
	var flume: Dictionary = sv.flume_path()
	_plumbing_flume(body, rails, glow, flume)
	var frames: Dictionary = sv.plumbing_frames()
	for rib in (frames["ribs"] as Array):
		_plumbing_rib(body, rings, rib as Dictionary)
	_plumbing_wheels(rust, rings, frames["wheels"] as Array)
	for slit in (frames["slits"] as Array):
		_surface_panel(dark, slit as Dictionary)
	_plumbing_sign(rust, dark, frames["sign"] as Dictionary)
	_plumbing_hood(body, frames["hood"] as Dictionary)
	_plumbing_cascade(body, dark, glow, frames["cascade"] as Dictionary)
	_plumbing_side_pipe(rust, rings, frames["side_pipe"] as Dictionary, flume)
	# the terminal screen glowing in the doorway (the plate's key ground read) — PROUD of the
	# entrance door leaves (which sit at wall - recess*0.55), so the glow reads from outside
	var wall_r := float(spec.get("door_radius", 1.59))
	var scr_r := wall_r - 0.18
	_emit_oriented_box_st(glow, Vector3(0.0, 0.95, scr_r),
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0.26, 0.34, 0.015))
	var sign_fr := frames["sign"] as Dictionary
	var sn := Vector3(cos(float(sign_fr["theta"])), 0.0, sin(float(sign_fr["theta"])))
	var nameplate := sn * (float(sign_fr["r"]) + 0.30) + Vector3(0, (float(sign_fr["y0"]) + float(sign_fr["y1"])) * 0.5, 0)
	# every builder above emits raw vertices only (no append_from) — generate_normals is safe here
	for stool in [body, rust, dark, glow, rails]:
		(stool as SurfaceTool).generate_normals()
	return {"body": body.commit(), "rust": rust.commit(), "dark": dark.commit(),
		"glow": glow.commit(), "rails": rails.commit(), "nameplate_pos": nameplate, "height": h}

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# The flume: sweep the surveyed helix with a U trough section (outer/inner walls + floor + rim
# tops + underside), rail bands above both rims (UV-tiled for the railing texture), and the
# terminal-green water strip riding the channel floor. End caps close the two mouths.
static func _plumbing_flume(body: SurfaceTool, rails: SurfaceTool, glow: SurfaceTool, flume: Dictionary) -> void:
	var samples: Array = flume["samples"]
	var w: float = float(flume["trough_w"])
	var depth: float = float(flume["depth"])
	var rail_h: float = float(flume["rail_h"])
	var water_w: float = float(flume["water_w"])
	var wall := 0.045
	var under := 0.06
	var hw := w * 0.5
	# section strips as [inner radial offset, y offset] pairs (outer face wound outward)
	for i in range(samples.size() - 1):
		var s0 := samples[i] as Dictionary
		var s1 := samples[i + 1] as Dictionary
		var arc_len := absf(float(s1["theta"]) - float(s0["theta"])) * float(s0["r"])
		# strip emitter: two section points -> one quad between consecutive samples
		var strips := [
			[hw, -under, hw, depth, true],            # outer wall, outer face
			[hw - wall, depth, hw - wall, 0.0, false],  # outer wall, inner face (into the trough)
			[hw - wall, depth, hw, depth, true],      # outer rim top (up)
			[-(hw - wall), 0.0, hw - wall, 0.0, true],  # floor top (up)
			[-(hw - wall), 0.0, -(hw - wall), depth, true],   # inner wall, trough face
			[-hw, depth, -hw, -under, true],          # inner wall, back face (against the building)
			[-hw, depth, -(hw - wall), depth, true],  # inner rim top
			[-hw, -under, hw, -under, false],         # underside (faces down)
		]
		for strip in strips:
			var sp := strip as Array
			var p00 := _flume_pt(s0, float(sp[0]), float(sp[1]))
			var p01 := _flume_pt(s0, float(sp[2]), float(sp[3]))
			var p10 := _flume_pt(s1, float(sp[0]), float(sp[1]))
			var p11 := _flume_pt(s1, float(sp[2]), float(sp[3]))
			var mid := (p00 + p11) * 0.5
			var hint := Vector3(0, mid.y, 0) if bool(sp[4]) else mid + Vector3(0, 2.0, 0)
			_quad_out(body, p00, p01, p11, p10, hint)
		# rails: one two-sided textured band per rim (cull-disabled material, so single quads)
		for side in [-1.0, 1.0]:
			var ro := (hw - wall * 0.5) * float(side)
			var r00 := _flume_pt(s0, ro, depth)
			var r01 := _flume_pt(s0, ro, depth + rail_h)
			var r10 := _flume_pt(s1, ro, depth)
			var r11 := _flume_pt(s1, ro, depth + rail_h)
			var u0 := float(i) * arc_len / 0.42
			var u1 := float(i + 1) * arc_len / 0.42
			rails.set_uv(Vector2(u0, 1.0)); rails.add_vertex(r00)
			rails.set_uv(Vector2(u1, 1.0)); rails.add_vertex(r10)
			rails.set_uv(Vector2(u1, 0.0)); rails.add_vertex(r11)
			rails.set_uv(Vector2(u0, 1.0)); rails.add_vertex(r00)
			rails.set_uv(Vector2(u1, 0.0)); rails.add_vertex(r11)
			rails.set_uv(Vector2(u0, 0.0)); rails.add_vertex(r01)
		# the water strip, just above the floor
		var wq00 := _flume_pt(s0, -water_w * 0.5, 0.012)
		var wq01 := _flume_pt(s0, water_w * 0.5, 0.012)
		var wq10 := _flume_pt(s1, -water_w * 0.5, 0.012)
		var wq11 := _flume_pt(s1, water_w * 0.5, 0.012)
		_quad_out(glow, wq00, wq01, wq11, wq10, (wq00 + wq11) * 0.5 - Vector3(0, 1.0, 0))
	# end caps close the mouths
	for endi in [0, samples.size() - 1]:
		var se := samples[endi] as Dictionary
		var c0 := _flume_pt(se, -hw, -under)
		var c1 := _flume_pt(se, hw, -under)
		var c2 := _flume_pt(se, hw, depth)
		var c3 := _flume_pt(se, -hw, depth)
		var out_hint := (c0 + c2) * 0.5 + Vector3(0, 0.0, 0) + (Vector3(0, 1, 0).cross(Vector3(cos(float(se["theta"])), 0, sin(float(se["theta"]))))) * (2.0 if endi == 0 else -2.0)
		_quad_out(body, c0, c1, c2, c3, out_hint)

# a flume section point: radial offset `dr` (outward +) and vertical offset `dy` off the floor datum
static func _flume_pt(sample: Dictionary, dr: float, dy: float) -> Vector3:
	var th := float(sample["theta"])
	var r := float(sample["r"]) + dr
	return Vector3(cos(th) * r, float(sample["y"]) + dy, sin(th) * r)

# one dome rib: a tube hugging the surveyed dome surface from the cupola neck to the shoulder
static func _plumbing_rib(body: SurfaceTool, rings: Array, rib: Dictionary) -> void:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var th := float(rib["theta"])
	var rr := float(rib["r"])
	var pts: Array = []
	var steps := 7
	for i in range(steps + 1):
		var y := lerpf(float(rib["y0"]), float(rib["y1"]), float(i) / float(steps))
		var rad := float(Survey.lathe_local_r(rings, y, th)) + rr * 0.55
		pts.append(Vector3(cos(th) * rad, y, sin(th) * rad))
	_tube(body, pts, rr, 5)

# the rusted handwheel cluster: torus rim + 6 spokes + hub per wheel, vertical pipe runs linking
# the stacked pairs, and the freestanding stub wheel on its horizontal ground pipe
static func _plumbing_wheels(rust: SurfaceTool, rings: Array, wheels: Array) -> void:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var crest_pts := {}
	for wd_v in wheels:
		var wd := wd_v as Dictionary
		var th := float(wd["theta"])
		var dia := float(wd["dia"])
		var n := Vector3(cos(th), 0.0, sin(th))
		var stub := bool(wd.get("stub", false))
		var base_r := float(wd["r"])
		var center := n * (base_r + (0.55 if stub else dia * 0.18)) + Vector3(0, float(wd["y"]), 0)
		var basis := Basis(Quaternion(Vector3.UP, n))
		_emit_torus_st(rust, center, n, dia * 0.43, dia * 0.07, 14, 6)
		for k in range(6):
			var ang := TAU * float(k) / 6.0
			var spoke_dir := (basis * Vector3(cos(ang), 0.0, sin(ang))).normalized()
			_tube(rust, [center - spoke_dir * dia * 0.4, center + spoke_dir * dia * 0.4], dia * 0.045, 4)
		_tube(rust, [center - n * dia * 0.12, center + n * dia * 0.10], dia * 0.10, 6)
		if stub:
			# the ground pipe stub carrying the freestanding wheel back to the wall
			var wall_pt := n * (float(Survey.lathe_local_r(rings, float(wd["y"]), th)) - 0.05) + Vector3(0, float(wd["y"]), 0)
			_tube(rust, [wall_pt, center - n * dia * 0.12], 0.055, 5)
		else:
			var key := int(round(th * 100.0))
			if not crest_pts.has(key):
				crest_pts[key] = []
			(crest_pts[key] as Array).append({"y": float(wd["y"]), "th": th})
	# vertical pipe runs linking wheels stacked on the same lobe crest
	for key in crest_pts.keys():
		var stack := crest_pts[key] as Array
		if stack.size() < 2:
			continue
		var th2 := float((stack[0] as Dictionary)["th"])
		var n2 := Vector3(cos(th2), 0.0, sin(th2))
		var y_lo := INF
		var y_hi := -INF
		for e in stack:
			y_lo = minf(y_lo, float((e as Dictionary)["y"]))
			y_hi = maxf(y_hi, float((e as Dictionary)["y"]))
		var run_pts: Array = []
		for i in range(5):
			var y := lerpf(y_lo, y_hi, float(i) / 4.0)
			run_pts.append(n2 * (float(Survey.lathe_local_r(rings, y, th2)) + 0.05) + Vector3(0, y, 0))
		_tube(rust, run_pts, 0.045, 5)

# a capillary slit: a recessed-dark rounded-top panel riding the local surface
static func _surface_panel(dark: SurfaceTool, slit: Dictionary) -> void:
	var th := float(slit["theta"])
	var n := Vector3(cos(th), 0.0, sin(th))
	var u := Vector3(0, 1, 0).cross(n).normalized()
	var hw := float(slit["w"]) * 0.5
	var y0 := float(slit["y0"])
	var y1 := float(slit["y1"])
	var body_h := (y1 - y0) * 0.82   # the straight shaft; the top 18% rounds off
	var levels := [[0.0, 1.0], [body_h, 1.0], [body_h + (y1 - y0) * 0.12, 0.62], [y1 - y0, 0.22]]
	for i in range(levels.size() - 1):
		var l0 := levels[i] as Array
		var l1 := levels[i + 1] as Array
		var ya := y0 + float(l0[0])
		var yb := y0 + float(l1[0])
		var ra := lerpf(float(slit["r0"]), float(slit["r1"]), (ya - y0) / maxf(0.001, y1 - y0)) + 0.022
		var rb := lerpf(float(slit["r0"]), float(slit["r1"]), (yb - y0) / maxf(0.001, y1 - y0)) + 0.022
		var a0 := n * ra + u * (hw * float(l0[1])) + Vector3(0, ya, 0)
		var a1 := n * ra - u * (hw * float(l0[1])) + Vector3(0, ya, 0)
		var b0 := n * rb + u * (hw * float(l1[1])) + Vector3(0, yb, 0)
		var b1 := n * rb - u * (hw * float(l1[1])) + Vector3(0, yb, 0)
		_quad_out(dark, a0, a1, b1, b0, Vector3(0, (ya + yb) * 0.5, 0))

# the physical sign board: rusted raised frame + dark face (the showcase title label rides it)
static func _plumbing_sign(rust: SurfaceTool, dark: SurfaceTool, sign: Dictionary) -> void:
	var th := float(sign["theta"])
	var n := Vector3(cos(th), 0.0, sin(th))
	var u := Vector3(0, 1, 0).cross(n).normalized()
	var v := Vector3(0, 1, 0)
	var cy := (float(sign["y0"]) + float(sign["y1"])) * 0.5
	var hh := (float(sign["y1"]) - float(sign["y0"])) * 0.5
	var hw := float(sign["w"]) * 0.5
	var c := n * (float(sign["r"]) + 0.10) + Vector3(0, cy, 0)
	_emit_oriented_box_st(dark, c, u, v, n, Vector3(hw, hh, 0.035))
	for sx in [-1.0, 1.0]:
		_emit_oriented_box_st(rust, c + u * (hw * sx) + n * 0.01, u, v, n, Vector3(0.045, hh + 0.045, 0.045))
		_emit_oriented_box_st(rust, c + v * (hh * sx) + n * 0.01, u, v, n, Vector3(hw + 0.045, 0.045, 0.045))

# the pitched entry hood over the recessed doorway: the ridge runs along the wall, one tiled slope
# falls outward to the front eave, triangular cheeks close the sides, an underside faces the door
static func _plumbing_hood(body: SurfaceTool, hood: Dictionary) -> void:
	var th := float(hood["theta"])
	var n := Vector3(cos(th), 0.0, sin(th))
	var u := Vector3(0, 1, 0).cross(n).normalized()
	var anchor := n * float(hood["r"])
	var hw := float(hood["w"]) * 0.5
	var out := float(hood["out"])
	var ridge_l := anchor - u * hw * 0.85 + Vector3(0, float(hood["ridge"]), 0) + n * 0.06
	var ridge_r := anchor + u * hw * 0.85 + Vector3(0, float(hood["ridge"]), 0) + n * 0.06
	var eave_l := anchor - u * hw + Vector3(0, float(hood["eaves"]), 0) + n * out
	var eave_r := anchor + u * hw + Vector3(0, float(hood["eaves"]), 0) + n * out
	var wall_l := anchor - u * hw + Vector3(0, float(hood["eaves"]), 0) + n * 0.03
	var wall_r := anchor + u * hw + Vector3(0, float(hood["eaves"]), 0) + n * 0.03
	var inside := anchor - n * 1.5 + Vector3(0, float(hood["eaves"]) * 0.5, 0)
	_quad_out(body, ridge_l, ridge_r, eave_r, eave_l, inside)                      # the slope
	_quad_out(body, wall_l, wall_r, ridge_r, ridge_l, inside + n)                  # back upstand
	_quad_out(body, eave_l, eave_r, wall_r, wall_l, ridge_l + n * 2.0)             # underside
	_tri_out(body, eave_l, ridge_l, wall_l, inside + u * 2.0)                      # left cheek
	_tri_out(body, eave_r, ridge_r, wall_r, inside - u * 2.0)                      # right cheek
	# the hood IS the surround (main_surround=false): its own two shallow threshold steps
	_emit_oriented_box_st(body, anchor + Vector3(0, 0.065, 0) + n * 0.16, u, Vector3.UP, n,
		Vector3(hw * 0.62, 0.065, 0.16))
	_emit_oriented_box_st(body, anchor + Vector3(0, 0.028, 0) + n * 0.40, u, Vector3.UP, n,
		Vector3(hw * 0.74, 0.028, 0.15))

# the green cascade: an arched spout, the glowing fall + steps, and a dark pool at the apron
static func _plumbing_cascade(body: SurfaceTool, dark: SurfaceTool, glow: SurfaceTool, casc: Dictionary) -> void:
	var th := float(casc["theta"])
	var n := Vector3(cos(th), 0.0, sin(th))
	var u := Vector3(0, 1, 0).cross(n).normalized()
	var v := Vector3(0, 1, 0)
	var hw := float(casc["w"]) * 0.5
	var top := float(casc["y_top"])
	var wall := n * float(casc["r"])
	# arched spout against the wall; the glowing fall hangs CLEAR of it, spilling onto the steps
	_emit_oriented_box_st(body, wall + Vector3(0, top, 0) + n * 0.10, u, v, n, Vector3(hw * 0.55, top * 0.16, 0.12))
	var fall_top := wall + Vector3(0, top - 0.04, 0) + n * 0.26
	var fall_bot := wall + Vector3(0, 0.03, 0) + n * 0.46
	_quad_out(glow, fall_top - u * hw * 0.28, fall_top + u * hw * 0.28,
		fall_bot + u * hw * 0.34, fall_bot - u * hw * 0.34, wall - n * 2.0)
	_emit_oriented_box_st(body, wall + Vector3(0, 0.085, 0) + n * 0.56, u, v, n, Vector3(hw * 0.5, 0.085, 0.10))
	_emit_oriented_box_st(body, wall + Vector3(0, 0.04, 0) + n * 0.74, u, v, n, Vector3(hw * 0.62, 0.04, 0.09))
	_emit_oriented_box_st(dark, wall + Vector3(0, 0.012, 0) + n * 0.95, u, v, n, Vector3(hw * 0.8, 0.012, 0.20))

# the one vertical side pipe: hugs the surveyed wall from under the flume down to the ground,
# with a valve collar at the surveyed height
static func _plumbing_side_pipe(rust: SurfaceTool, rings: Array, pipe: Dictionary, flume: Dictionary) -> void:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var th := float(pipe["theta"])
	var pr := float(pipe["dia"]) * 0.5
	# the pipe drinks from the flume: its top meets the trough's underside at this theta
	var top_y := float(pipe["y_top"])
	var best := INF
	for s_v in (flume["samples"] as Array):
		var s := s_v as Dictionary
		var d := absf(fposmod(float(s["theta"]) - th + PI, TAU) - PI)
		if d < best:
			best = d
			top_y = float(s["y"]) - 0.10
	var pts: Array = []
	var steps := 8
	for i in range(steps + 1):
		var y := lerpf(top_y, 0.05, float(i) / float(steps))
		var rad := float(Survey.lathe_local_r(rings, y, th)) + pr + 0.02
		pts.append(Vector3(cos(th) * rad, y, sin(th) * rad))
	_tube(rust, pts, pr, 6)
	var vy := float(pipe["valve_y"])
	var vrad := float(Survey.lathe_local_r(rings, vy, th)) + pr + 0.02
	var vc := Vector3(cos(th) * vrad, vy, sin(th) * vrad)
	_emit_torus_st(rust, vc, Vector3.UP, pr * 1.35, pr * 0.35, 10, 5)

# A hand-emitted torus (raw vertices, so generate_normals stays safe alongside the other emitters —
# append_from would silently drop them). `axis` is the ring's normal.
static func _emit_torus_st(st: SurfaceTool, center: Vector3, axis: Vector3, r_major: float,
		r_minor: float, rings_n: int, segs: int) -> void:
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	for i in range(rings_n):
		var a0 := TAU * float(i) / float(rings_n)
		var a1 := TAU * float(i + 1) / float(rings_n)
		for k in range(segs):
			var b0 := TAU * float(k) / float(segs)
			var b1 := TAU * float(k + 1) / float(segs)
			var p00 := center + basis * _torus_pt(a0, b0, r_major, r_minor)
			var p01 := center + basis * _torus_pt(a0, b1, r_major, r_minor)
			var p10 := center + basis * _torus_pt(a1, b0, r_major, r_minor)
			var p11 := center + basis * _torus_pt(a1, b1, r_major, r_minor)
			var hub := center + basis * (Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)) * r_major)
			_quad_out(st, p00, p01, p11, p10, hub)

static func _torus_pt(a: float, b: float, r_major: float, r_minor: float) -> Vector3:
	var ring := Vector3(cos(a), 0.0, sin(a))
	return ring * (r_major + r_minor * cos(b)) + Vector3(0.0, r_minor * sin(b), 0.0)

## A tube swept along a polyline (closed with end fans) — the shared rib/pipe/spoke emitter.
static func _tube(st: SurfaceTool, pts: Array, radius: float, sides: int) -> void:
	if pts.size() < 2:
		return
	var rings_pts: Array = []
	for i in range(pts.size()):
		var p := pts[i] as Vector3
		var fwd: Vector3
		if i == 0:
			fwd = ((pts[1] as Vector3) - p).normalized()
		elif i == pts.size() - 1:
			fwd = (p - (pts[i - 1] as Vector3)).normalized()
		else:
			fwd = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.01:
			side = fwd.cross(Vector3.RIGHT)
		side = side.normalized()
		var up2 := side.cross(fwd).normalized()
		var ring: Array = []
		for k in range(sides):
			var ang := TAU * float(k) / float(sides)
			ring.append(p + (side * cos(ang) + up2 * sin(ang)) * radius)
		rings_pts.append(ring)
	for i in range(rings_pts.size() - 1):
		var ra := rings_pts[i] as Array
		var rb := rings_pts[i + 1] as Array
		var ca := pts[i] as Vector3
		for k in range(sides):
			var k2 := (k + 1) % sides
			_quad_out(st, ra[k] as Vector3, ra[k2] as Vector3, rb[k2] as Vector3, rb[k] as Vector3, ca)
	for endd in [[0, -1.0], [rings_pts.size() - 1, 1.0]]:
		var ei := int((endd as Array)[0])
		var ring_e := rings_pts[ei] as Array
		var ce := pts[ei] as Vector3
		var other := pts[1 if ei == 0 else ei - 1] as Vector3
		for k in range(sides):
			_tri_out(st, ce + (ce - other).normalized() * radius * 0.2, ring_e[k] as Vector3,
				ring_e[(k + 1) % sides] as Vector3, other)

## Cleanstreets (SURVEY REBUILD 1.3): the OPEN toll-canopy pavilion built from the survey — the
## stepped dais, six waisted mushroom-leg piers (each ONE small loft, foot -> waist -> flaring
## head), and the canopy as ONE perimeter sweep whose rim scallops and whose four corners sweep up
## into horns peaking exactly at the crown. Air between the legs; no walls.
static func _canopy_piers_mesh(spec: Dictionary) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var cs: Dictionary = Survey.table_for(spec, "cleanstreets")
	var size: Vector3 = spec.get("size", Vector3(11.0, 6.0, 7.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the dais + two front steps at the outer lane mouths
	var dais: Dictionary = cs["dais"]
	var dsz := dais["size"] as Vector3
	_emit_oriented_box_st(st, Vector3(0, dsz.y * 0.5, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK,
		dsz * 0.5)
	for sx in [-1.0, 1.0]:
		_emit_oriented_box_st(st, Vector3(float(sx) * 1.75, 0.175, dsz.z * 0.5 + 0.35),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(float(dais["step_w"]) * 0.5, 0.175, 0.35))
	# six waisted piers, each a tiny loft seated on the dais
	var piers: Dictionary = cs["piers"]
	var canopy: Dictionary = cs["canopy"]
	var leg_h := float(canopy["y0"]) - dsz.y
	for px in (piers["xs"] as Array):
		for pz in (piers["zs"] as Array):
			_pier_loft(st, Vector3(float(px), dsz.y, float(pz)), leg_h,
				float(piers["foot_r"]), float(piers["waist_r"]), float(piers["head_r"]),
				float(piers["waist_frac"]))
	# the canopy: one perimeter sweep — scalloped rim band + top/bottom caps, horns at the corners
	_canopy_sweep(st, Vector3(size.x * 0.5, 0, size.z * 0.5), float(canopy["y0"]), float(canopy["y1"]),
		float(canopy["scallop"]), float(canopy["horn_rise"]), float(canopy["horn_reach"]), size.y)
	st.generate_normals()
	return st.commit()

# a waisted mushroom leg: foot ring -> waist -> flaring head, the loft closed by the dais below and
# the canopy underside above
static func _pier_loft(st: SurfaceTool, base: Vector3, h: float, foot_r: float, waist_r: float,
		head_r: float, waist_frac: float) -> void:
	var levels := [[0.0, foot_r], [waist_frac * 0.55, lerpf(foot_r, waist_r, 0.75)],
		[waist_frac, waist_r], [0.78, lerpf(waist_r, head_r, 0.55)], [1.0, head_r]]
	var seg := 10
	for i in range(levels.size() - 1):
		var l0 := levels[i] as Array
		var l1 := levels[i + 1] as Array
		for s in range(seg):
			var a0 := TAU * float(s) / float(seg)
			var a1 := TAU * float(s + 1) / float(seg)
			var p00 := base + Vector3(cos(a0) * float(l0[1]), h * float(l0[0]), sin(a0) * float(l0[1]))
			var p01 := base + Vector3(cos(a1) * float(l0[1]), h * float(l0[0]), sin(a1) * float(l0[1]))
			var p10 := base + Vector3(cos(a0) * float(l1[1]), h * float(l1[0]), sin(a0) * float(l1[1]))
			var p11 := base + Vector3(cos(a1) * float(l1[1]), h * float(l1[0]), sin(a1) * float(l1[1]))
			_quad_out(st, p00, p01, p11, p10, base + Vector3(0, h * (float(l0[0]) + float(l1[0])) * 0.5, 0))

# the canopy slab as ONE perimeter sweep: rim samples run around the plan rectangle, scalloped in
# plan and lifted toward each corner into the horn (peaking exactly at `crown`); the rim band spans
# underside -> fascia top, closed by top and bottom fans from the slab centre.
static func _canopy_sweep(st: SurfaceTool, half: Vector3, y0: float, y1: float, scallop: float,
		horn_rise: float, horn_reach: float, crown: float) -> void:
	var per_edge := 12
	var pts_top: Array = []
	var pts_bot: Array = []
	var corners := [Vector2(half.x, half.z), Vector2(-half.x, half.z),
		Vector2(-half.x, -half.z), Vector2(half.x, -half.z)]
	for e in range(4):
		var a := corners[e] as Vector2
		var b := corners[(e + 1) % 4] as Vector2
		for s in range(per_edge):
			var t := float(s) / float(per_edge)
			var p := a.lerp(b, t)
			var out2 := (p / Vector2(half.x, half.z)).normalized()
			# plan scallop (two waves per edge) + the corner horn factor (quartic, tight to corners)
			var wave := sin(t * PI * 2.0) * scallop
			var cd := minf(t, 1.0 - t) * 2.0            # 0 at a corner, 1 mid-edge
			var horn := pow(1.0 - cd, 4.0)
			var pp := p + out2 * (wave + horn * horn_reach)
			var lift := horn * horn_rise
			# the horn peak lands exactly at the crown; elsewhere the fascia top stays at y1
			pts_bot.append(Vector3(pp.x, y0 + lift * 0.75, pp.y))
			pts_top.append(Vector3(pp.x, minf(y1 + lift, crown), pp.y))
	var n := pts_top.size()
	var mid := Vector3(0, (y0 + y1) * 0.5, 0)
	for i in range(n):
		var j := (i + 1) % n
		_quad_out(st, pts_bot[i] as Vector3, pts_bot[j] as Vector3, pts_top[j] as Vector3, pts_top[i] as Vector3, mid)
	var top_c := Vector3(0, y1, 0)
	var bot_c := Vector3(0, y0, 0)
	for i2 in range(n):
		var j2 := (i2 + 1) % n
		_tri_out(st, top_c, pts_top[i2] as Vector3, pts_top[j2] as Vector3, Vector3(0, y0 - 2.0, 0))
		_tri_out(st, bot_c, pts_bot[i2] as Vector3, pts_bot[j2] as Vector3, Vector3(0, y1 + 2.0, 0))

## Cleanstreets detail passes (SURVEY REBUILD 1.3), from the survey table: the S-topped queue
## divider fins with anti-loiter spikes, the placard set (fascia title board, fin/dais regulatory
## panels), the toll portal's header + kiosk (whose cyan '+' and screen are the building's ONLY
## cool emissives — the plate demands cyan here, as at beacon's enforcement door), the warm-gold
## vaulted underside (rib web + junction lights, the pavilion's main light), the honeycomb corner
## perforation clusters, and the freestanding monolith on the approach.
## Families: body (bone mosaic) / dark (verdigris panels) / warm (gold vault) / cyan (the kiosk).
static func cleanstreets_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var cs: Dictionary = Survey.table_for(spec, "cleanstreets")
	var size: Vector3 = spec.get("size", Vector3(11.0, 6.0, 7.0))
	var body := _st()
	var dark := _st()
	var warm := _st()
	var cyan := _st()
	var u_x := Vector3.RIGHT
	var n_z := Vector3.BACK
	# queue divider fins: profiled walls rising in an S toward the rear, spikes at the lane mouths
	var fins: Dictionary = cs["fins"]
	var dais: Dictionary = cs["dais"]
	var dsz := dais["size"] as Vector3
	var fz0 := float(fins["z0"])
	var fz1 := float(fins["z1"])
	var steps := 8
	for fx_v in (fins["xs"] as Array):
		var fx := float(fx_v)
		for i in range(steps):
			var t0 := float(i) / float(steps)
			var t1 := float(i + 1) / float(steps)
			var z0 := lerpf(fz1, fz0, t0)
			var z1 := lerpf(fz1, fz0, t1)
			var h0 := dsz.y + lerpf(float(fins["h_front"]), float(fins["h_rear"]), smoothstep(0.0, 1.0, t0))
			var h1 := dsz.y + lerpf(float(fins["h_front"]), float(fins["h_rear"]), smoothstep(0.0, 1.0, t1))
			var ht := float(fins["t"]) * 0.5
			var mid := Vector3(fx, (h0 + h1) * 0.5 * 0.5, (z0 + z1) * 0.5)
			for sside in [-1.0, 1.0]:
				_quad_out(body, Vector3(fx + ht * float(sside), dsz.y, z0), Vector3(fx + ht * float(sside), dsz.y, z1),
					Vector3(fx + ht * float(sside), h1, z1), Vector3(fx + ht * float(sside), h0, z0), Vector3(fx, mid.y, mid.z))
			_quad_out(body, Vector3(fx - ht, h0, z0), Vector3(fx + ht, h0, z0),
				Vector3(fx + ht, h1, z1), Vector3(fx - ht, h1, z1), Vector3(fx, dsz.y, (z0 + z1) * 0.5))
		# fin front end cap
		_quad_out(body, Vector3(fx - float(fins["t"]) * 0.5, dsz.y, fz1), Vector3(fx + float(fins["t"]) * 0.5, dsz.y, fz1),
			Vector3(fx + float(fins["t"]) * 0.5, dsz.y + float(fins["h_front"]), fz1),
			Vector3(fx - float(fins["t"]) * 0.5, dsz.y + float(fins["h_front"]), fz1), Vector3(fx, dsz.y + 0.5, fz1 - 2.0))
	# anti-loiter spikes along the dais front band, one row per lane
	var spikes: Dictionary = cs["spikes"]
	var fin_xs: Array = fins["xs"]
	for lane in range(fin_xs.size() + 1):
		var x_lo := -dsz.x * 0.5 + 0.6 if lane == 0 else float(fin_xs[lane - 1]) + 0.4
		var x_hi := dsz.x * 0.5 - 0.6 if lane == fin_xs.size() else float(fin_xs[lane]) - 0.4
		for k in range(int(spikes["count_per_lane"])):
			var sx2 := lerpf(x_lo, x_hi, (float(k) + 0.5) / float(spikes["count_per_lane"]))
			_spike(body, Vector3(sx2, dsz.y, float(spikes["z"])), float(spikes["r"]), float(spikes["h"]))
	# placards: fascia title board (front), fin panels, dais STAND BACK bands
	var sgn: Dictionary = cs["sign"]
	var sc := Vector3(0, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5, size.z * 0.5 + 0.30)
	_emit_oriented_box_st(dark, sc, u_x, Vector3.UP, n_z,
		Vector3(float(sgn["w"]) * 0.5, (float(sgn["y1"]) - float(sgn["y0"])) * 0.5, 0.04))
	for bx in [-1.0, 1.0]:
		_emit_oriented_box_st(body, sc + u_x * (float(sgn["w"]) * 0.5 * float(bx)) + n_z * 0.01,
			u_x, Vector3.UP, n_z, Vector3(0.06, (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 + 0.06, 0.06))
	for fpi in [1, 2]:
		var fpx := float(fin_xs[fpi])
		_emit_oriented_box_st(dark, Vector3(fpx, dsz.y + 1.05, 0.4), n_z, Vector3.UP, u_x,
			Vector3(0.30, 0.42, float(fins["t"]) * 0.5 + 0.02))
	_emit_oriented_box_st(dark, Vector3(-1.8, dsz.y - float(dais["band_h"]) * 0.5, dsz.z * 0.5 + 0.01),
		u_x, Vector3.UP, n_z, Vector3(1.6, float(dais["band_h"]) * 0.45, 0.02))
	_emit_oriented_box_st(dark, Vector3(2.6, dsz.y - float(dais["band_h"]) * 0.5, dsz.z * 0.5 + 0.01),
		u_x, Vector3.UP, n_z, Vector3(1.6, float(dais["band_h"]) * 0.45, 0.02))
	# the toll portal: header board over the surveyed door + the kiosk with its cyan cross/screen
	var toll: Dictionary = cs["toll"]
	var door_lat := float(spec.get("door_lateral", -2.2))
	var face_u := Vector3(0, 0, -1)   # the +X face's in-plane axis
	var anchor := Vector3(size.x * 0.5, 0, 0) + face_u * door_lat
	_emit_oriented_box_st(dark, anchor + Vector3(0.14, (float(toll["header_y0"]) + float(toll["header_y1"])) * 0.5, 0),
		face_u, Vector3.UP, Vector3.RIGHT,
		Vector3(float(toll["header_w"]) * 0.5, (float(toll["header_y1"]) - float(toll["header_y0"])) * 0.5, 0.04))
	var ksz := toll["kiosk"] as Vector3
	var kpos := anchor + face_u * 0.9 + Vector3(-0.4, 0, 0)
	_emit_oriented_box_st(dark, kpos + Vector3(0, ksz.y * 0.5, 0), face_u, Vector3.UP, Vector3.RIGHT, ksz * 0.5)
	var cface := kpos + Vector3(ksz.z * 0.5 + 0.015, 0, 0)
	var cr := float(toll["cross"]) * 0.5
	_emit_oriented_box_st(cyan, cface + Vector3(0, ksz.y * 0.72, 0), face_u, Vector3.UP, Vector3.RIGHT, Vector3(cr * 0.28, cr, 0.012))
	_emit_oriented_box_st(cyan, cface + Vector3(0, ksz.y * 0.72, 0), face_u, Vector3.UP, Vector3.RIGHT, Vector3(cr, cr * 0.28, 0.012))
	_emit_oriented_box_st(cyan, cface + Vector3(0, ksz.y * 0.42, 0), face_u, Vector3.UP, Vector3.RIGHT,
		Vector3(float(toll["screen"]) * 0.5, float(toll["screen"]) * 0.4, 0.012))
	# the warm-gold vaulted underside: a diamond rib web between the pier heads + junction lights
	var vault: Dictionary = cs["vault"]
	var piers: Dictionary = cs["piers"]
	var vy := float(vault["y"])
	var pxs: Array = piers["xs"]
	var pzs: Array = piers["zs"]
	for i3 in range(pxs.size()):
		_tube(body, [Vector3(float(pxs[i3]), vy, float(pzs[0])), Vector3(float(pxs[i3]), vy, float(pzs[1]))],
			float(vault["rib_r"]), 4)
		if i3 + 1 < pxs.size():
			for zi in range(2):
				_tube(body, [Vector3(float(pxs[i3]), vy, float(pzs[zi])), Vector3(float(pxs[i3 + 1]), vy, float(pzs[1 - zi]))],
					float(vault["rib_r"]), 4)
			var jx := (float(pxs[i3]) + float(pxs[i3 + 1])) * 0.5
			_emit_oriented_box_st(warm, Vector3(jx, vy - 0.05, 0), u_x, Vector3.UP, n_z,
				Vector3(float(vault["light_r"]), 0.05, float(vault["light_r"])))
	for px2 in pxs:
		for pz2 in pzs:
			_emit_oriented_box_st(warm, Vector3(float(px2) * 0.72, vy - 0.05, float(pz2) * 0.6),
				u_x, Vector3.UP, n_z, Vector3(float(vault["light_r"]), 0.05, float(vault["light_r"])))
	# honeycomb perforation clusters on the fascia corners (front + back faces)
	var perf: Dictionary = cs["perf"]
	for pside in [-1.0, 1.0]:
		for zside in [-1.0, 1.0]:
			for hidx in range(int(perf["holes"])):
				var hx2 := float(perf["x_center"]) * float(pside) + (BaseShapeBuilder._h01(float(hidx) * 7.3 + float(pside) * 3.0) - 0.5) * float(perf["half_w"]) * 1.7
				var hy2 := lerpf(float(perf["y0"]) + 0.15, float(perf["y1"]) - 0.15, BaseShapeBuilder._h01(float(hidx) * 13.7 + float(zside)))
				var hr := 0.07 + 0.09 * BaseShapeBuilder._h01(float(hidx) * 3.1 + float(pside))
				_emit_oriented_box_st(dark, Vector3(hx2, hy2, (size.z * 0.5 + 0.32) * float(zside)),
					u_x, Vector3.UP, n_z, Vector3(hr, hr, 0.02))
	# the freestanding monolith on the approach: stepped base + tombstone + teal face
	var mono: Dictionary = cs["monolith"]
	var mz := float(mono["z"])
	var mx := float(mono.get("x", -1.6))
	_emit_oriented_box_st(body, Vector3(mx, 0.15, mz), u_x, Vector3.UP, n_z, Vector3(0.85, 0.15, 0.6))
	_emit_oriented_box_st(body, Vector3(mx, float(mono["base_h"]) * 0.5 + 0.1, mz), u_x, Vector3.UP, n_z,
		Vector3(0.65, float(mono["base_h"]) * 0.5, 0.45))
	_emit_oriented_box_st(body, Vector3(mx, float(mono["base_h"]) + float(mono["h"]) * 0.5, mz),
		u_x, Vector3.UP, n_z, Vector3(float(mono["w"]) * 0.5, float(mono["h"]) * 0.5, 0.24))
	_emit_oriented_box_st(dark, Vector3(mx, float(mono["base_h"]) + float(mono["h"]) * 0.55, mz + 0.25),
		u_x, Vector3.UP, n_z, Vector3(float(mono["w"]) * 0.36, float(mono["h"]) * 0.36, 0.015))
	for stool in [body, dark, warm, cyan]:
		(stool as SurfaceTool).generate_normals()
	var nameplate := sc + n_z * 0.25
	return {"body": body.commit(), "dark": dark.commit(), "warm": warm.commit(),
		"cyan": cyan.commit(), "nameplate_pos": nameplate}

# a small anti-loiter spike: a four-sided pyramid on the dais surface
static func _spike(st: SurfaceTool, base: Vector3, r: float, h: float) -> void:
	var apex := base + Vector3(0, h, 0)
	var pts := [base + Vector3(r, 0, 0), base + Vector3(0, 0, r), base + Vector3(-r, 0, 0), base + Vector3(0, 0, -r)]
	for i in range(4):
		_tri_out(st, apex, pts[i] as Vector3, pts[(i + 1) % 4] as Vector3, base - Vector3(0, 1, 0))

## Ancourage (SURVEY REBUILD 1.5): the pumphouse kiosk as ONE continuous loft from the
## BuildingSurvey.ANCOURAGE ring table — round body, the fat rolled BRIM, and the 2-LOBE quilted
## dome cluster (per-ring lobe modulation; no intersecting spheres). Stacks, arch, roots and the
## rest are ancourage_details, grown from the same table.
static func _ancourage_domes_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	return _survey_ring_loft(Survey.ancourage_rings(spec), reserved, recess, float(spec.get("height", 4.6)))

## Ancourage detail passes: the stepped plinth, the grand arch idiom (tube arch + green cell-glass
## + mullions + the readout post — the door's declared ensemble), placards, two multi-foil roses,
## the louver, pores, engaged pipes with mini-wheels, the big valve wheel + rosette port, the two
## saddle stacks (the flare crowned by the plate's ONLY warm accent, the flame), piped saddle
## seams, and the signature ROOT-FAN of oily pipes spilling off the plinth.
## Families: body / bone (cream placard) / dark (boards, foils, roots) / glow (green) / warm / rust.
static func ancourage_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "ancourage")
	var rings: Array = Survey.ancourage_rings(spec)
	var h := float(spec.get("height", 4.6))
	var wall_r := float(spec.get("door_radius", 0.489 * h))
	var body := _st()
	var bone := _st()
	var dark := _st()
	var glow := _st()
	var warm := _st()
	var rust := _st()
	var n_f := Vector3(0, 0, 1)
	var u_f := Vector3(1, 0, 0)
	var kb := float(str(spec.get("kind", "ancourage")).hash() % 1000)
	# the stepped plinth ring, extending past the body
	var pl: Dictionary = tbl["plinth"]
	var body_r := 0.489 * h
	for stp in range(int(pl["steps"])):
		var inset := float(stp) * 0.22
		var sh := float(pl["h"]) / float(pl["steps"])
		_emit_torus_st(body, Vector3(0, float(pl["h"]) - sh * (float(stp) + 0.5), 0), Vector3.UP,
			body_r + float(pl["out"]) - inset, sh * 0.62, 20, 4)
	# the grand arch idiom: tube arch over the doorway; the glass band glows terminal green behind
	# mullion bars; the readout box rides a post left of the door
	var arch: Dictionary = tbl["arch"]
	var anchor := n_f * wall_r
	var arch_pts: Array = []
	for i in range(11):
		var t := float(i) / 10.0
		var uu := lerpf(-1.0, 1.0, t)
		arch_pts.append(anchor + u_f * (uu * float(arch["w"]) * 0.5)
			+ Vector3(0, maxf(0.06, float(arch["apex"]) * (1.0 - uu * uu)), 0) + n_f * 0.10)
	_tube(body, arch_pts, float(arch["r_tube"]), 6)
	var gy0 := float(arch["glass_y0"])
	var gy1 := float(arch["glass_y1"])
	_emit_oriented_box_st(glow, anchor + Vector3(0, (gy0 + gy1) * 0.5, 0) - n_f * 0.06,
		u_f, Vector3.UP, n_f, Vector3(float(arch["w"]) * 0.40, (gy1 - gy0) * 0.5, 0.03))
	for mb in range(int(arch["mullions"])):
		var mx := lerpf(-float(arch["w"]) * 0.34, float(arch["w"]) * 0.34, float(mb) / float(int(arch["mullions"]) - 1))
		_emit_oriented_box_st(dark, anchor + u_f * mx + Vector3(0, (gy0 + gy1) * 0.5, 0) - n_f * 0.02,
			u_f, Vector3.UP, n_f, Vector3(0.035, (gy1 - gy0) * 0.5 + 0.04, 0.035))
	var rd: Dictionary = tbl["readout"]
	var rpos := anchor + u_f * (-float(arch["w"]) * 0.5 - 0.30) + n_f * 0.28
	_emit_oriented_box_st(dark, rpos + Vector3(0, float(rd["h"]) * 0.45, 0), u_f, Vector3.UP, n_f,
		Vector3(0.05, float(rd["h"]) * 0.45, 0.05))
	_emit_oriented_box_st(glow, rpos + Vector3(0, float(rd["h"]) * 0.92, 0), u_f, Vector3.UP, n_f,
		Vector3(0.14, 0.12, 0.06))
	# placards: the cream Ancourage board on the brim front; the PPP board on the left face
	var sgn: Dictionary = tbl["sign"]
	var sy := (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h
	var sr := float(Survey.lathe_local_r(rings, sy, PI * 0.5))
	var sc := n_f * (sr + 0.06) + Vector3(0, sy, 0)
	_emit_oriented_box_st(bone, sc, u_f, Vector3.UP, n_f,
		Vector3(float(sgn["w"]) * 0.5, (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 * h, 0.035))
	var ppp: Dictionary = tbl["ppp"]
	var pth: float = PI * 0.5 + float(ppp["az"])
	var pn := Vector3(cos(pth), 0.0, sin(pth))
	var pu := Vector3(0, 1, 0).cross(pn).normalized()
	var pyc := (float(ppp["y0"]) + float(ppp["y1"])) * 0.5 * h
	_emit_oriented_box_st(dark, pn * (float(Survey.lathe_local_r(rings, pyc, pth)) + 0.04) + Vector3(0, pyc, 0),
		pu, Vector3.UP, pn, Vector3(float(ppp["w"]) * 0.5, (float(ppp["y1"]) - float(ppp["y0"])) * 0.5 * h, 0.025))
	# dome fixtures on the REAL lobed surface: multi-foil roses, the louver, round pores
	for ro_v in (tbl["roses"] as Array):
		var ro := ro_v as Array
		var rth: float = PI * 0.5 + float(ro[0])
		var rn := Vector3(cos(rth), 0.0, sin(rth))
		var ru := Vector3(0, 1, 0).cross(rn).normalized()
		var ryc := (float(ro[1]) + float(ro[2])) * 0.5 * h
		var rrad := float(ro[3]) * h * 0.5
		var rbase := rn * (float(Survey.lathe_local_r(rings, ryc, rth)) + 0.02) + Vector3(0, ryc, 0)
		_emit_oriented_box_st(dark, rbase, ru, Vector3.UP, rn, Vector3(rrad * 0.45, rrad * 0.45, 0.03))
		for fo in range(6):
			var fa := TAU * float(fo) / 6.0
			_emit_oriented_box_st(dark, rbase + (ru * cos(fa) + Vector3.UP * sin(fa)) * rrad * 0.78,
				ru, Vector3.UP, rn, Vector3(rrad * 0.3, rrad * 0.3, 0.025))
	var lou: Dictionary = tbl["louver"]
	if float(lou["w"]) > 0.01:
		var lth: float = PI * 0.5 + float(lou["az"])
		var ln := Vector3(cos(lth), 0.0, sin(lth))
		var lu := Vector3(0, 1, 0).cross(ln).normalized()
		var lyc := (float(lou["y0"]) + float(lou["y1"])) * 0.5 * h
		var lbase := ln * (float(Survey.lathe_local_r(rings, lyc, lth)) + 0.02) + Vector3(0, lyc, 0)
		_emit_oriented_box_st(dark, lbase, lu, Vector3.UP, ln,
			Vector3(float(lou["w"]) * h * 0.5, (float(lou["y1"]) - float(lou["y0"])) * 0.5 * h, 0.02))
		for sl in range(3):
			_emit_oriented_box_st(rust, lbase + Vector3(0, (float(sl) - 1.0) * (float(lou["y1"]) - float(lou["y0"])) * h * 0.26, 0) + ln * 0.025,
				lu, Vector3.UP, ln, Vector3(float(lou["w"]) * h * 0.44, 0.018, 0.012))
	for po_v in (tbl["pores"] as Array):
		var po := po_v as Array
		var poth: float = PI * 0.5 + float(po[0])
		var pon := Vector3(cos(poth), 0.0, sin(poth))
		var poyc := (float(po[1]) + float(po[2])) * 0.5 * h
		_emit_oriented_box_st(dark, pon * (float(Survey.lathe_local_r(rings, poyc, poth)) + 0.02) + Vector3(0, poyc, 0),
			Vector3(0, 1, 0).cross(pon).normalized(), Vector3.UP, pon,
			Vector3(float(po[3]) * h * 0.5, float(po[3]) * h * 0.5, 0.02))
	# engaged pipes hugging the wall (each with a mini wheel), the big valve wheel, the rosette
	var eng: Dictionary = tbl["engaged"]
	for az_v in (eng["azs"] as Array):
		var eth: float = PI * 0.5 + float(az_v)
		var en := Vector3(cos(eth), 0.0, sin(eth))
		var er := float(eng["r"]) * h
		var epts: Array = []
		for i4 in range(6):
			var ey := lerpf(0.05, 0.46 * h, float(i4) / 5.0)
			epts.append(en * (float(Survey.lathe_local_r(rings, ey, eth)) + er + 0.02) + Vector3(0, ey, 0))
		_tube(rust, epts, er, 5)
		var wy2 := float(eng["wheel_y"]) * h
		var wc2 := en * (float(Survey.lathe_local_r(rings, wy2, eth)) + er * 2.4) + Vector3(0, wy2, 0)
		_emit_torus_st(rust, wc2, en, er * 1.7, er * 0.32, 10, 5)
	var whl: Dictionary = tbl["wheel"]
	var wth: float = PI * 0.5 + float(whl["az"])
	var wn := Vector3(cos(wth), 0.0, sin(wth))
	var wyc := float(whl["y"]) * h
	var wdia := float(whl["dia"]) * h
	var wc := wn * (float(Survey.lathe_local_r(rings, wyc, wth)) + wdia * 0.18) + Vector3(0, wyc, 0)
	_emit_torus_st(rust, wc, wn, wdia * 0.43, wdia * 0.07, 14, 6)
	var wbasis := Basis(Quaternion(Vector3.UP, wn))
	for k in range(6):
		var ang := TAU * float(k) / 6.0
		var spoke := (wbasis * Vector3(cos(ang), 0.0, sin(ang))).normalized()
		_tube(rust, [wc - spoke * wdia * 0.4, wc + spoke * wdia * 0.4], wdia * 0.045, 4)
	var rst: Dictionary = tbl["rosette"]
	var rsth: float = PI * 0.5 + float(rst["az"])
	var rsn := Vector3(cos(rsth), 0.0, sin(rsth))
	var rsyc := float(rst["y"]) * h
	var rsc := rsn * (float(Survey.lathe_local_r(rings, rsyc, rsth)) + 0.04) + Vector3(0, rsyc, 0)
	_emit_torus_st(rust, rsc, rsn, float(rst["dia"]) * h * 0.42, float(rst["dia"]) * h * 0.09, 12, 5)
	# the saddle stacks: capped drum + the flare chimney crowned by the FLAME (the one warm accent)
	var stk: Dictionary = tbl["stacks"]
	var saddle_y := 0.955 * h
	_tube(body, [Vector3(float(stk["drum_x"]), saddle_y - 0.1, 0), Vector3(float(stk["drum_x"]), h + float(stk["drum_h"]), 0)],
		float(stk["drum_r"]), 8)
	_emit_torus_st(body, Vector3(float(stk["drum_x"]), h + float(stk["drum_h"]), 0), Vector3.UP,
		float(stk["drum_r"]) * 0.85, float(stk["drum_r"]) * 0.3, 12, 5)
	_tube(body, [Vector3(float(stk["flare_x"]), saddle_y - 0.1, 0), Vector3(float(stk["flare_x"]), h + float(stk["flare_h"]), 0)],
		float(stk["flare_r"]), 8)
	_emit_torus_st(body, Vector3(float(stk["flare_x"]), h + float(stk["flare_h"]), 0), Vector3.UP,
		float(stk["flare_r"]) * 1.15, float(stk["flare_r"]) * 0.22, 12, 5)
	_emit_oriented_box_st(warm, Vector3(float(stk["flare_x"]), h + float(stk["flare_h"]) + float(stk["flame_h"]) * 0.5, 0),
		u_f, Vector3.UP, n_f, Vector3(0.09, float(stk["flame_h"]) * 0.5, 0.09))
	# piped seam ridges along the saddle valley (the quilted-lobe read)
	for sm in range(int(tbl["seams"])):
		var szn := 1.0 if sm == 0 else -1.0
		var spts: Array = []
		for i5 in range(7):
			var sy2 := lerpf(0.62 * h, 0.995 * h, float(i5) / 6.0)
			var sth: float = PI * 0.5 * szn
			spts.append(Vector3(cos(sth), 0, sin(sth)) * (float(Survey.lathe_local_r(rings, sy2, sth)) + 0.035) + Vector3(0, sy2, 0))
		_tube(body, spts, 0.05, 4)
	# the ROOT-FAN: oily pipes pouring off the plinth, fanning outward across the ground
	var rts: Dictionary = tbl["roots"]
	for ri in range(int(rts["count"])):
		var frac := (float(ri) + 0.5) / float(rts["count"])
		var raz: float = PI * 0.5 + lerpf(-float(rts["spread"]), float(rts["spread"]), frac) + (_h01(kb + float(ri) * 7.7) - 0.5) * 0.18
		var rdir := Vector3(cos(raz), 0.0, sin(raz))
		var reach := float(rts["reach"]) * (0.65 + 0.45 * _h01(kb + float(ri) * 3.1))
		var p0 := rdir * (body_r + 0.15) + Vector3(0, float(pl["h"]) + 0.12, 0)
		var p1 := rdir * (body_r + float(pl["out"]) + 0.3) + Vector3(0, 0.16, 0)
		var p2 := rdir * (body_r + reach * 0.6) + Vector3(0, 0.09, 0) + rdir.cross(Vector3.UP) * ((_h01(kb + float(ri) * 11.3) - 0.5) * 0.7)
		var p3 := rdir * (body_r + reach) + Vector3(0, 0.05, 0)
		_tube(dark, [p0, p1, p2, p3], float(rts["r"]) * (0.75 + 0.5 * _h01(kb + float(ri) * 5.3)), 5)
	for stool in [body, bone, dark, glow, warm, rust]:
		(stool as SurfaceTool).generate_normals()
	return {"body": body.commit(), "bone": bone.commit(), "dark": dark.commit(),
		"glow": glow.commit(), "warm": warm.commit(), "rust": rust.commit(),
		"nameplate_pos": sc + n_f * 0.28}

## Beacon Hill (SURVEY REBUILD 1.6): the bell-jar urn as ONE loft from the BuildingSurvey.BEACON
## ring table — base flare, near-vertical drum, dome shoulder, the garden ledge, the lantern.
static func _beacon_domed_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	return _survey_ring_loft(Survey.beacon_rings(spec), reserved, recess, float(spec.get("height", 7.2)))

## Beacon Hill detail passes: the FIVE great arch bays (doubled bone rib outlines + the amber
## shelf-grid panes, storey-scaled INSIDE the bays only), dome ribs continuing from each bay head
## to the lantern, oval oculi, the portal's cartouche, the green status board, the enforcement
## vestibule (the plate's ONE cyan accent), warm sconces, the lantern clerestory and the planted
## roof-garden ring, and the corner planting beds.
## Families: bone / dark / amber (panes) / glow (green) / cyan / warm / leaf / rails.
## Aghora Exchange (user plates 2026-07-11): the bazaar drum + tiered bell dome as ONE loft from
## the BuildingSurvey.AGHORA ring table.
static func _aghora_domed_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	return _survey_ring_loft(Survey.aghora_rings(spec), reserved, recess, float(spec.get("height", 8.0)))

## Aghora Exchange detail passes, every part from the AGHORA survey frames: two ring bands of
## warm mullioned windows (split around the market arch), the arched gallery at the dome
## springing, ribbed dome + collar + spike finial, the great MAGENTA NEON RING (lotus + backing
## disc + brackets) standing proud of the dome face over the front roof TERRACE (rail + planters
## + awning + laundry line), flank banner plates, and the entry idiom (arch + canvas awning +
## hanging neon plate + steps).
static func aghora_exchange_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "aghora")
	var rings: Array = Survey.aghora_rings(spec)
	var h := float(spec.get("height", 8.0))
	var metal := _st()
	var dark := _st()
	var amber := _st()
	var neon := _st()
	var leaf := _st()
	var cloth := _st()
	var fr := PI * 0.5
	var kb := float(str(spec.get("kind", "aghora")).hash() % 1000)
	# window ring bands: mullioned amber panes riding the drum, split around the market arch
	var wb: Dictionary = tbl["windows"]
	var cols := int(wb["cols"])
	for band_v in (wb["bands"] as Array):
		var band := band_v as Array
		var by0 := float(band[0]) * h
		var by1 := float(band[1]) * h
		var byc := (by0 + by1) * 0.5
		for c in range(cols):
			var th := TAU * (float(c) + 0.5) / float(cols)
			var dth := absf(wrapf(th - fr, -PI, PI))
			if by0 < 2.8 and dth < 0.52:
				continue   # the market arch owns this arc
			var n := Vector3(cos(th), 0.0, sin(th))
			var u := Vector3(0, 1, 0).cross(n).normalized()
			var rad := float(Survey.lathe_local_r(rings, byc, th))
			var ww := rad * TAU / float(cols) * 0.30
			_emit_oriented_box_st(amber, n * (rad + 0.03) + Vector3(0, byc, 0), u, Vector3.UP, n,
				Vector3(ww, (by1 - by0) * 0.36, 0.02))
			_emit_oriented_box_st(metal, n * (rad + 0.045) + Vector3(0, byc, 0), u, Vector3.UP, n,
				Vector3(0.025, (by1 - by0) * 0.38, 0.015))
			_emit_oriented_box_st(metal, n * (rad + 0.045) + Vector3(0, byc, 0), u, Vector3.UP, n,
				Vector3(ww + 0.02, 0.025, 0.015))
			_emit_oriented_box_st(metal, n * (rad + 0.04) + Vector3(0, by0 - 0.04, 0), u, Vector3.UP, n,
				Vector3(ww + 0.06, 0.035, 0.05))
	# the gallery: open arches around the dome springing
	var ga: Dictionary = tbl["gallery"]
	var arches := int(ga["arches"])
	var gy0 := float(ga["y0"]) * h
	var gy1 := float(ga["y1"]) * h
	for a in range(arches):
		var ath := TAU * (float(a) + 0.5) / float(arches)
		var half_arc := TAU / float(arches) * 0.30
		var spring := gy1 - 0.35 * (gy1 - gy0)
		var pts: Array = []
		pts.append(_drum_pt(rings, ath - half_arc, gy0, 0.06))
		pts.append(_drum_pt(rings, ath - half_arc, spring, 0.06))
		for i in range(1, 6):
			var aa := PI - PI * float(i) / 6.0
			pts.append(_drum_pt(rings, ath + cos(aa) * half_arc, spring + sin(aa) * (gy1 - spring), 0.06))
		pts.append(_drum_pt(rings, ath + half_arc, spring, 0.06))
		pts.append(_drum_pt(rings, ath + half_arc, gy0, 0.06))
		_tube(metal, pts, 0.042, 5)
		var an := Vector3(cos(ath), 0.0, sin(ath))
		var au := Vector3(0, 1, 0).cross(an).normalized()
		var arad := float(Survey.lathe_local_r(rings, (gy0 + gy1) * 0.5, ath))
		_emit_oriented_box_st(dark, an * (arad + 0.01) + Vector3(0, (gy0 + gy1) * 0.5, 0),
			au, Vector3.UP, an, Vector3(half_arc * arad * 0.85, (gy1 - gy0) * 0.42, 0.012))
	# dome ribs + collar + spike finial + antenna
	var ribs := int(tbl["ribs"])
	for r_i in range(ribs):
		var rth := TAU * float(r_i) / float(ribs) + PI / float(ribs)
		var rpts: Array = []
		for kseg in range(7):
			var ry := lerpf(0.665 * h, 0.925 * h, float(kseg) / 6.0)
			rpts.append(_drum_pt(rings, rth, ry, 0.05))
		_tube(metal, rpts, 0.045, 5)
	_emit_torus_st(metal, Vector3(0, 0.900 * h, 0), Vector3.UP, 0.105 * h + 0.02, 0.035, 14, 5)
	_rings_loft(metal, Vector3(0, 0.930 * h, 0), 0.085 * h, [[0.0, 0.098 * h / (0.085 * h)],
		[0.55, 0.05 * h / (0.085 * h)], [1.0, 0.10]], 8)
	_tube(metal, [Vector3(0, 1.005 * h, 0), Vector3(0, 1.055 * h, 0)], 0.02, 4)
	_emit_oriented_box_st(neon, Vector3(0, 1.06 * h, 0), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(0.03, 0.03, 0.03))
	# THE GREAT NEON RING: outer + inner tori, five petal arcs, dark backing disc, dome brackets
	var nr: Dictionary = tbl["neon_ring"]
	var nrc_y := float(nr["y"]) * h
	var nr_r := float(nr["r"]) * h
	var dome_r := float(Survey.lathe_local_r(rings, nrc_y, fr))
	var nrc := Vector3(0, nrc_y, dome_r + float(nr["proud"]))
	var nrn := Vector3(0, 0, 1)
	_emit_torus_st(neon, nrc, nrn, nr_r, 0.055, 22, 6)
	_emit_torus_st(neon, nrc + nrn * -0.02, nrn, nr_r * 0.80, 0.028, 18, 5)
	var petals := int(nr["petals"])
	for pt_i in range(petals):
		var pa := PI * 0.5 + (float(pt_i) - float(petals - 1) * 0.5) * 0.52
		var tip := nrc + Vector3(cos(pa), sin(pa), 0) * nr_r * 0.62
		for side in [-1.0, 1.0]:
			var mid := nrc + Vector3(cos(pa + float(side) * 0.16), sin(pa + float(side) * 0.16), 0) * nr_r * 0.34
			_tube(neon, [nrc + Vector3(0, -nr_r * 0.05, 0.02), mid + Vector3(0, 0, 0.02), tip + Vector3(0, 0, 0.02)], 0.022, 4)
	var fan := 18
	for fi in range(fan):
		var a0 := TAU * float(fi) / float(fan)
		var a1 := TAU * float(fi + 1) / float(fan)
		dark.add_vertex(nrc + Vector3(0, 0, -0.05))
		dark.add_vertex(nrc + Vector3(cos(a1) * nr_r * 0.94, sin(a1) * nr_r * 0.94, -0.05))
		dark.add_vertex(nrc + Vector3(cos(a0) * nr_r * 0.94, sin(a0) * nr_r * 0.94, -0.05))
	for br in [-0.55, 0.55]:
		var hang := _drum_pt(rings, fr + float(br), nrc_y + nr_r * 0.35, 0.0)
		_tube(metal, [hang, nrc + Vector3(float(br) * nr_r * 0.7, nr_r * 0.25, -0.06)], 0.035, 4)
	# the front roof TERRACE: rail ring sector + planters + awning + laundry line
	var te: Dictionary = tbl["terrace"]
	var ty := float(te["y"]) * h
	var t_arc := float(te["half_arc"])
	var t_rad := float(Survey.lathe_local_r(rings, ty, fr)) + 0.12
	var rail_h := float(te["rail_h"])
	var rail_pts: Array = []
	for i2 in range(11):
		var rth2 := fr + lerpf(-t_arc, t_arc, float(i2) / 10.0)
		rail_pts.append(Vector3(cos(rth2) * t_rad, ty + rail_h, sin(rth2) * t_rad))
		if i2 % 2 == 0:
			_tube(metal, [Vector3(cos(rth2) * t_rad, ty, sin(rth2) * t_rad),
				Vector3(cos(rth2) * t_rad, ty + rail_h, sin(rth2) * t_rad)], 0.022, 4)
	_tube(metal, rail_pts, 0.028, 5)
	var planters := int(te["planters"])
	for pl_i in range(planters):
		var pth := fr + lerpf(-t_arc * 0.85, t_arc * 0.85, (float(pl_i) + 0.5) / float(planters))
		var pp := Vector3(cos(pth), 0, sin(pth)) * (t_rad - 0.35) + Vector3(0, ty, 0)
		_emit_oriented_box_st(dark, pp + Vector3(0, 0.14, 0), Vector3(1, 0, 0), Vector3.UP,
			Vector3(0, 0, 1), Vector3(0.16, 0.14, 0.16))
		_emit_oriented_box_st(leaf, pp + Vector3(0, 0.33, 0), Vector3(1, 0, 0), Vector3.UP,
			Vector3(0, 0, 1), Vector3(0.15, 0.07, 0.15))
	var aw_a := fr - t_arc * 0.55
	var awp0 := Vector3(cos(aw_a), 0, sin(aw_a)) * (t_rad - 0.15) + Vector3(0, ty, 0)
	var aw_u := Vector3(0, 1, 0).cross(Vector3(cos(aw_a), 0, sin(aw_a))).normalized()
	for pole in [-0.55, 0.55]:
		_tube(metal, [awp0 + aw_u * float(pole), awp0 + aw_u * float(pole) + Vector3(0, 0.9, 0)], 0.022, 4)
	_quad_out(cloth, awp0 + aw_u * -0.6 + Vector3(0, 0.9, 0), awp0 + aw_u * 0.6 + Vector3(0, 0.9, 0),
		awp0 + aw_u * 0.6 - Vector3(cos(aw_a), 0, sin(aw_a)) * 0.8 + Vector3(0, 1.12, 0),
		awp0 + aw_u * -0.6 - Vector3(cos(aw_a), 0, sin(aw_a)) * 0.8 + Vector3(0, 1.12, 0),
		awp0 + Vector3(0, -0.4, 0))
	var ln_a := fr + t_arc * 0.6
	var lp0 := Vector3(cos(ln_a), 0, sin(ln_a)) * (t_rad - 0.1) + Vector3(0, ty + rail_h + 0.35, 0)
	var lp1 := Vector3(0, 0.93 * h, 0)
	_tube(metal, [lp0, lp0.lerp(lp1, 0.5) + Vector3(0, -0.25, 0), lp1], 0.012, 3)
	for fl in range(4):
		var fp := lp0.lerp(lp1, 0.15 + 0.2 * float(fl)) + Vector3(0, -0.25 * sin(PI * (0.15 + 0.2 * float(fl))), 0)
		_emit_oriented_box_st(cloth, fp + Vector3(0, -0.12, 0), Vector3(1, 0, 0), Vector3.UP,
			Vector3(0, 0, 1), Vector3(0.09, 0.12, 0.01))
	# flank banner plates (magenta) on bracket tubes
	for b_v in (tbl["banners"] as Array):
		var b := b_v as Array
		var bth: float = fr + float(b[0])
		var b_y := float(b[1]) * h
		var bn := Vector3(cos(bth), 0.0, sin(bth))
		var bu := Vector3(0, 1, 0).cross(bn).normalized()
		var brad := float(Survey.lathe_local_r(rings, b_y, bth))
		_tube(metal, [bn * brad + Vector3(0, b_y + 0.05 * h, 0),
			bn * (brad + 0.35) + Vector3(0, b_y + 0.05 * h, 0)], 0.025, 4)
		_emit_oriented_box_st(neon, bn * (brad + 0.35) + Vector3(0, b_y, 0), bu, Vector3.UP, bn,
			Vector3(0.13, 0.05 * h, 0.02))
	# the entry idiom: doubled arch + canvas awning on poles + hanging neon plate + two steps
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.6))
	var door_h := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.2))
	var wall_r := float(spec.get("door_radius", 2.72))
	for off in [0.0, 0.10]:
		var aw2 := door_w * 0.5 + 0.16 - float(off)
		var spring2 := door_h - aw2 * 0.55
		var pts2: Array = []
		pts2.append(_drum_pt(rings, fr - aw2 / wall_r, 0.02, 0.07))
		pts2.append(_drum_pt(rings, fr - aw2 / wall_r, spring2, 0.07))
		for i3 in range(1, 6):
			var aa2 := PI - PI * float(i3) / 6.0
			pts2.append(_drum_pt(rings, fr + cos(aa2) * aw2 / wall_r, spring2 + sin(aa2) * (door_h + 0.14 - float(off) - spring2), 0.07))
		pts2.append(_drum_pt(rings, fr + aw2 / wall_r, spring2, 0.07))
		pts2.append(_drum_pt(rings, fr + aw2 / wall_r, 0.02, 0.07))
		_tube(metal, pts2, 0.055, 5)
	var en: Dictionary = tbl["entry"]
	var aw_out := float(en["awning_out"])
	var d_n := Vector3(cos(fr), 0.0, sin(fr))
	var d_u := Vector3(0, 1, 0).cross(d_n).normalized()
	var d_base := d_n * wall_r
	for pole2 in [-1.0, 1.0]:
		_tube(metal, [d_base + d_u * float(pole2) * (door_w * 0.5 + 0.25) + d_n * aw_out,
			d_base + d_u * float(pole2) * (door_w * 0.5 + 0.25) + d_n * aw_out + Vector3(0, door_h - 0.25, 0)], 0.028, 4)
	_quad_out(cloth, d_base + d_u * -(door_w * 0.5 + 0.35) + d_n * aw_out + Vector3(0, door_h - 0.25, 0),
		d_base + d_u * (door_w * 0.5 + 0.35) + d_n * aw_out + Vector3(0, door_h - 0.25, 0),
		d_base + d_u * (door_w * 0.5 + 0.35) + Vector3(0, door_h + 0.35, 0),
		d_base + d_u * -(door_w * 0.5 + 0.35) + Vector3(0, door_h + 0.35, 0),
		d_base + d_n * 0.5 + Vector3(0, door_h - 1.0, 0))
	_tube(metal, [d_base + d_u * (door_w * 0.5 + 0.55) + Vector3(0, door_h + 0.6, 0),
		d_base + d_u * (door_w * 0.5 + 0.55) + d_n * 0.4 + Vector3(0, door_h + 0.6, 0)], 0.02, 4)
	_emit_oriented_box_st(neon, d_base + d_u * (door_w * 0.5 + 0.55) + d_n * 0.4 + Vector3(0, door_h + 0.6 - float(en["sign_drop"]), 0),
		d_u, Vector3.UP, d_n, Vector3(0.10, 0.24, 0.02))
	_emit_oriented_box_st(dark, d_base + d_n * 0.3 + Vector3(0, 0.055, 0), d_u, Vector3.UP, d_n,
		Vector3(door_w * 0.5 + 0.4, 0.055, 0.35))
	_emit_oriented_box_st(dark, d_base + d_n * 0.15 + Vector3(0, 0.165, 0), d_u, Vector3.UP, d_n,
		Vector3(door_w * 0.5 + 0.25, 0.055, 0.2))
	for stool in [metal, dark, amber, neon, leaf, cloth]:
		(stool as SurfaceTool).generate_normals()
	return {"metal": metal.commit(), "dark": dark.commit(), "amber": amber.commit(),
		"neon": neon.commit(), "leaf": leaf.commit(), "cloth": cloth.commit(),
		"nameplate_pos": nrc + Vector3(0, nr_r + 0.4, 0.3)}

## Aghora Bazaar Stack detail passes, every part from the AGHORA_STACK survey frames: per-storey
## warm window banks (front + flanks, split around the storefront), awning rows at the storey
## tops, balcony rails with plants, hanging vertical neon banners + two horizontal sign boards in
## the storey gaps, the stair zigzag on the +X flank, roof tanks + laundry lines + a pole sign,
## and the storefront entry (awning + hanging plate).
static func aghora_stack_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "aghora_stack")
	var size: Vector3 = spec.get("size", Vector3(5.0, 11.0, 4.2))
	var h := size.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var metal := _st()
	var dark := _st()
	var amber := _st()
	var neon := _st()
	var leaf := _st()
	var cloth := _st()
	var kb := float(str(spec.get("kind", "aghora_stack")).hash() % 1000)
	var storeys := int(tbl["storeys"])
	var base := float(tbl["base"])
	var band := float(tbl["band"])
	var wcols: Dictionary = tbl["windows"]
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.4))
	for face_v in [[Vector3(0, 0, 1), hx, hz, int(wcols["front_cols"])],
			[Vector3(-1, 0, 0), hz, hx, int(wcols["side_cols"])],
			[Vector3(1, 0, 0), hz, hx, int(wcols["side_cols"])]]:
		var fa := face_v as Array
		var n: Vector3 = fa[0]
		var f_hw := float(fa[1])
		var f_d := float(fa[2])
		var cols := int(fa[3])
		var u := Vector3(0, 1, 0).cross(n).normalized()
		var stair_face: bool = n.x > 0.5 and int(tbl["stair_flank"]) == 1
		for k in range(storeys):
			var wy0 := (base + band * (float(k) + float(tbl["win_lo"]))) * h
			var wy1 := (base + band * (float(k) + float(tbl["win_hi"]))) * h
			var wyc := (wy0 + wy1) * 0.5
			for c in range(cols):
				var cx := lerpf(-f_hw + 0.5, f_hw - 0.5, (float(c) + 0.5) / float(cols))
				if k == 0 and n.z > 0.5 and absf(cx) < door_w * 0.5 + 0.45:
					continue   # the storefront owns the ground centre
				if stair_face and cx > f_hw - 1.4:
					continue   # the stair zigzag owns this strip
				var wc := n * (f_d + 0.03) + u * cx + Vector3(0, wyc, 0)
				var ww := (f_hw - 1.0) / float(cols) * 0.72
				_emit_oriented_box_st(amber, wc, u, Vector3.UP, n, Vector3(ww, (wy1 - wy0) * 0.42, 0.02))
				_emit_oriented_box_st(metal, wc + n * 0.015, u, Vector3.UP, n, Vector3(0.022, (wy1 - wy0) * 0.44, 0.014))
				_emit_oriented_box_st(metal, wc + n * 0.015, u, Vector3.UP, n, Vector3(ww + 0.02, 0.022, 0.014))
				_emit_oriented_box_st(metal, wc + Vector3(0, -(wy1 - wy0) * 0.46 - 0.03, 0) + n * 0.02,
					u, Vector3.UP, n, Vector3(ww + 0.05, 0.03, 0.05))
			# the awning row at this storey's top (skip the stair strip)
			var ay := (base + band * float(k + 1)) * h - 0.06
			var seg_w := (f_hw * 2.0 - 1.0) / 3.0
			for seg in range(3):
				if _h01(kb + float(k) * 7.7 + float(seg) * 3.1 + n.x * 40.0 + n.z * 80.0) < 0.30:
					continue   # a gap-toothed awning line (the plates' patchwork)
				var sc := -f_hw + 0.5 + seg_w * (float(seg) + 0.5)
				if stair_face and sc > f_hw - 1.6:
					continue
				var a_c := n * f_d + u * sc + Vector3(0, ay, 0)
				var slat_st := cloth if int(_h01(kb + float(seg) * 11.0 + float(k) * 5.0) * 2.0) == 0 else metal
				for sl in range(5):
					var t := (float(sl) + 0.5) / 5.0
					_emit_oriented_box_st(slat_st, a_c + n * (0.55 * t) + Vector3(0, -0.28 * t, 0),
						u, (Vector3.UP * 0.55 + n * 0.28).normalized(), (n * 0.55 - Vector3.UP * 0.28).normalized(),
						Vector3(seg_w * 0.5 - 0.06, 0.055, 0.012))
			# balcony rail + pots on ~60% of front storeys
			if n.z > 0.5 and k > 0 and _h01(kb + float(k) * 13.0) > 0.4:
				var b_y := (base + band * float(k)) * h + 0.02
				_tube(metal, [n * (f_d + 0.30) + u * (-f_hw + 0.6) + Vector3(0, b_y + 0.42, 0),
					n * (f_d + 0.30) + u * (f_hw - 0.6) + Vector3(0, b_y + 0.42, 0)], 0.022, 4)
				for up in range(5):
					var ux := lerpf(-f_hw + 0.6, f_hw - 0.6, float(up) / 4.0)
					_tube(metal, [n * (f_d + 0.30) + u * ux + Vector3(0, b_y, 0),
						n * (f_d + 0.30) + u * ux + Vector3(0, b_y + 0.42, 0)], 0.016, 4)
				for pot in range(2):
					var px := lerpf(-f_hw * 0.5, f_hw * 0.5, float(pot))
					_emit_oriented_box_st(dark, n * (f_d + 0.22) + u * px + Vector3(0, b_y + 0.10, 0),
						u, Vector3.UP, n, Vector3(0.12, 0.10, 0.12))
					_emit_oriented_box_st(leaf, n * (f_d + 0.22) + u * px + Vector3(0, b_y + 0.25, 0),
						u, Vector3.UP, n, Vector3(0.11, 0.06, 0.11))
	# hanging vertical neon banners + the two horizontal sign boards (front face)
	var fzn := Vector3(0, 0, 1)
	var fzu := Vector3(0, 1, 0).cross(fzn).normalized()
	for b_v in (tbl["banners"] as Array):
		var b := b_v as Array
		var bx := float(b[0]) * h
		var b_y2 := float(b[1]) * h
		var b_h := 0.05 * h
		_tube(metal, [fzn * hz + fzu * bx + Vector3(0, b_y2 + b_h + 0.15, 0),
			fzn * (hz + 0.30) + fzu * bx + Vector3(0, b_y2 + b_h + 0.15, 0)], 0.02, 4)
		_emit_oriented_box_st(neon, fzn * (hz + 0.30) + fzu * bx + Vector3(0, b_y2, 0),
			fzu, Vector3.UP, fzn, Vector3(0.032 * h, b_h, 0.02))
	for sg_v in (tbl["signs"] as Array):
		var sg := sg_v as Array
		var sy := (float(sg[0]) + float(sg[1])) * 0.5 * h
		var s_hh := (float(sg[1]) - float(sg[0])) * 0.5 * h
		_emit_oriented_box_st(dark, fzn * (hz + 0.06) + Vector3(0, sy, 0), fzu, Vector3.UP, fzn,
			Vector3(0.10 * h, s_hh, 0.025))
		_emit_oriented_box_st(neon, fzn * (hz + 0.09) + Vector3(0, sy, 0), fzu, Vector3.UP, fzn,
			Vector3(0.10 * h - 0.08, s_hh - 0.06, 0.012))
	# the stair zigzag on the +X flank: stringer + steps + landing + rail per storey
	if int(tbl["stair_flank"]) == 1:
		var sx := hx + 0.05
		for k2 in range(storeys - 1):
			var y_a := (base + band * float(k2)) * h + 0.05
			var y_b := (base + band * float(k2 + 1)) * h + 0.05
			var dirn := 1.0 if k2 % 2 == 0 else -1.0
			var z_a := dirn * (hz - 0.6)
			var z_b := -dirn * (hz - 0.6)
			_tube(metal, [Vector3(sx + 0.25, y_a, z_a), Vector3(sx + 0.25, y_b, z_b)], 0.035, 4)
			_tube(metal, [Vector3(sx + 0.55, y_a + 0.35, z_a), Vector3(sx + 0.55, y_b + 0.35, z_b)], 0.022, 4)
			for stp in range(6):
				var t2 := (float(stp) + 0.5) / 6.0
				_emit_oriented_box_st(dark, Vector3(sx + 0.30, lerpf(y_a, y_b, t2), lerpf(z_a, z_b, t2)),
					Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), Vector3(0.22, 0.025, 0.30))
			_emit_oriented_box_st(dark, Vector3(sx + 0.30, y_b, z_b - dirn * 0.3),
				Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), Vector3(0.30, 0.03, 0.45))
	# roof: tanks + laundry lines + one pole sign
	var tanks := int(tbl["roof_tanks"])
	for tk in range(tanks):
		var tx := lerpf(-hx * 0.5, hx * 0.5, (float(tk) + 0.5) / float(tanks))
		var tz := (0.3 if tk % 2 == 0 else -0.4) * hz
		_rings_loft(metal, Vector3(tx, h, tz), 0.9, [[0.0, 0.42], [0.1, 0.38], [0.85, 0.38], [1.0, 0.05]], 8)
	_tube(metal, [Vector3(-hx + 0.4, h + 0.8, hz - 0.3), Vector3(hx - 0.4, h + 0.55, -hz + 0.3)], 0.012, 3)
	for fl2 in range(5):
		var t3 := 0.12 + 0.18 * float(fl2)
		var fp2 := Vector3(-hx + 0.4, h + 0.8, hz - 0.3).lerp(Vector3(hx - 0.4, h + 0.55, -hz + 0.3), t3)
		_emit_oriented_box_st(cloth, fp2 + Vector3(0, -0.11, 0), Vector3(1, 0, 0), Vector3.UP,
			Vector3(0, 0, 1), Vector3(0.08, 0.11, 0.01))
	_tube(metal, [Vector3(hx - 0.5, h, -hz + 0.5), Vector3(hx - 0.5, h + 1.3, -hz + 0.5)], 0.025, 4)
	_emit_oriented_box_st(neon, Vector3(hx - 0.5, h + 1.05, -hz + 0.5), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(0.28, 0.20, 0.02))
	# the storefront entry: canvas awning on poles + a hanging neon plate
	var door_h3 := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.1))
	for pole3 in [-1.0, 1.0]:
		_tube(metal, [Vector3(float(pole3) * (door_w * 0.5 + 0.25), 0, hz + 0.75),
			Vector3(float(pole3) * (door_w * 0.5 + 0.25), door_h3 - 0.2, hz + 0.75)], 0.026, 4)
	_quad_out(cloth, Vector3(-(door_w * 0.5 + 0.35), door_h3 - 0.2, hz + 0.75),
		Vector3(door_w * 0.5 + 0.35, door_h3 - 0.2, hz + 0.75),
		Vector3(door_w * 0.5 + 0.35, door_h3 + 0.28, hz + 0.02),
		Vector3(-(door_w * 0.5 + 0.35), door_h3 + 0.28, hz + 0.02),
		Vector3(0, door_h3 - 1.2, hz + 0.4))
	_tube(metal, [Vector3(door_w * 0.5 + 0.5, door_h3 + 0.35, hz),
		Vector3(door_w * 0.5 + 0.5, door_h3 + 0.35, hz + 0.4)], 0.018, 4)
	_emit_oriented_box_st(neon, Vector3(door_w * 0.5 + 0.5, door_h3 + 0.05, hz + 0.4),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.09, 0.22, 0.018))
	for stool in [metal, dark, amber, neon, leaf, cloth]:
		(stool as SurfaceTool).generate_normals()
	return {"metal": metal.commit(), "dark": dark.commit(), "amber": amber.commit(),
		"neon": neon.commit(), "leaf": leaf.commit(), "cloth": cloth.commit(),
		"nameplate_pos": Vector3(0, h + 0.6, hz + 0.2)}

## Open-Files detail passes (SURVEY REBUILD 1.10) — the massing keeps the director's recursive
## awnings; this pass builds the GROUND IDIOM from the OPEN_FILES survey: the nested hex-arch
## portal (chamfered octagon loops stepping proud) pouring a cyan inner glow + the scan-beam fan
## and scan bar, the heraldic crest, the glowing green sign, flanking console pedestals, fin
## sconces and the apron bollards.
static func open_files_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "open_files")
	var size: Vector3 = spec.get("size", Vector3(5.6, 9.0, 5.6))
	var hz := size.z * 0.5
	var bone := _st()
	var dark := _st()
	var warm := _st()
	var glow := _st()
	var cyan := _st()
	var po: Dictionary = tbl["portal"]
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.5))
	var door_h := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.2))
	var frames := int(po["frames"])
	var f_step := float(po["frame_step"])
	# the nested chamfered-octagon portal frames, each loop stepping outward and prouder
	for f in range(frames):
		var hw := door_w * 0.5 + 0.15 + float(f) * f_step
		var top := door_h + 0.15 + float(f) * f_step
		var ch := float(po["chamfer"]) + 0.05 * float(f)
		var zf := hz + 0.05 + float(f) * 0.05
		_tube(bone, [Vector3(-hw, 0.02, zf), Vector3(-hw, top - ch, zf), Vector3(-hw + ch, top, zf),
			Vector3(hw - ch, top, zf), Vector3(hw, top - ch, zf), Vector3(hw, 0.02, zf)],
			0.062, 5)
	# the cyan light deep in the pocket + the scan bar + the threshold beam fan
	var recess := float(spec.get("door_recess", 0.5))
	_emit_oriented_box_st(cyan, Vector3(0, door_h * 0.52, hz - recess + 0.06),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(door_w * 0.5 - 0.06, door_h * 0.48, 0.02))
	var scan: Dictionary = tbl["scan"]
	_emit_oriented_box_st(cyan, Vector3(0, float(scan["bar_y"]), hz + 0.10),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(door_w * 0.5 + 0.25, 0.03, 0.03))
	var s_len := float(scan["len"])
	var w_end := tan(float(scan["half_ang"])) * s_len
	_quad_out(cyan, Vector3(-0.14, 0.02, hz + 0.12), Vector3(0.14, 0.02, hz + 0.12),
		Vector3(w_end, 0.02, hz + 0.12 + s_len), Vector3(-w_end, 0.02, hz + 0.12 + s_len),
		Vector3(0, -2.0, hz + 1.0))
	# the heraldic crest + the glowing sign (letters live on the glow plate at texture time)
	var cr: Dictionary = tbl["crest"]
	var cr_c := Vector3(0, (float(cr["y0"]) + float(cr["y1"])) * 0.5, hz + 0.06)
	var cr_hh := (float(cr["y1"]) - float(cr["y0"])) * 0.5
	_emit_oriented_box_st(bone, cr_c, Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(float(cr["w"]) * 0.5, cr_hh, 0.03))
	_emit_oriented_box_st(dark, cr_c + Vector3(0, 0, 0.045), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(float(cr["w"]) * 0.32, cr_hh * 0.62, 0.012))
	var sgn: Dictionary = tbl["sign"]
	var sg_c := Vector3(0, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5, hz + 0.07)
	var sg_hw := float(sgn["w"]) * 0.5
	var sg_hh := (float(sgn["y1"]) - float(sgn["y0"])) * 0.5
	_emit_oriented_box_st(dark, sg_c, Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sg_hw, sg_hh, 0.025))
	_emit_oriented_box_st(glow, sg_c + Vector3(0, 0, 0.035), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(sg_hw - 0.10, sg_hh - 0.10, 0.012))
	for bar in [[0.0, sg_hh, sg_hw + 0.05, 0.04], [0.0, -sg_hh, sg_hw + 0.05, 0.04],
			[-sg_hw, 0.0, 0.04, sg_hh + 0.05], [sg_hw, 0.0, 0.04, sg_hh + 0.05]]:
		var br := bar as Array
		_emit_oriented_box_st(bone, sg_c + Vector3(float(br[0]), float(br[1]), 0.02),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(float(br[2]), float(br[3]), 0.032))
	# console pedestals (green CRTs), fin sconces, apron bollards
	for cx_v in ((tbl["consoles"] as Dictionary)["xs"] as Array):
		var kx := float(cx_v)
		_emit_oriented_box_st(dark, Vector3(kx, 0.42, hz + 0.45),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.20, 0.42, 0.14))
		var kv := Vector3(0, 0.906, 0.423)
		var kn := Vector3(0, -0.423, 0.906)
		_emit_oriented_box_st(glow, Vector3(kx, 0.92, hz + 0.50) + kn * 0.02,
			Vector3(1, 0, 0), kv, kn, Vector3(0.13, 0.09, 0.01))
	var scn: Dictionary = tbl["sconces"]
	for sx_v in (scn["xs"] as Array):
		for sy_v in (scn["ys"] as Array):
			_emit_oriented_box_st(dark, Vector3(float(sx_v), float(sy_v), hz + 0.05),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.05, 0.11, 0.05))
			_emit_oriented_box_st(warm, Vector3(float(sx_v), float(sy_v) + 0.02, hz + 0.105),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.035, 0.07, 0.02))
	var bl: Dictionary = tbl["bollards"]
	var b_count := int(bl["count"])
	for b in range(b_count):
		var ba := lerpf(-1.05, 1.05, (float(b) + 0.5) / float(b_count))
		var bp := Vector3(sin(ba) * float(bl["radius"]), 0.0, hz + cos(ba) * float(bl["radius"]) * 0.55 + 0.6)
		_rings_loft(dark, bp, 0.55, [[0.0, 0.13], [0.12, 0.10], [1.0, 0.085]], 6)
		_emit_oriented_box_st(warm, bp + Vector3(0, 0.58, 0), Vector3(1, 0, 0), Vector3.UP,
			Vector3(0, 0, 1), Vector3(0.028, 0.028, 0.028))
	for stool in [bone, dark, warm, glow, cyan]:
		(stool as SurfaceTool).generate_normals()
	return {"bone": bone.commit(), "dark": dark.commit(), "warm": warm.commit(),
		"glow": glow.commit(), "cyan": cyan.commit(),
		"nameplate_pos": Vector3(0, float(sgn["y1"]) + 0.3, hz + 0.2)}

## Honeycomb detail passes (SURVEY REBUILD 1.9), every part from the HONEYCOMB survey + the
## engine's OWN cell grid (honeyframe_cell_rects): a vent louver + planter per facade cell, the
## hex-badge sign filling its storey-2 cell, the ring-balustrade parapet with red-tipped corner
## finials, the TORN +X flank (rust wash, the strut-chaos hole, catwalk rows with ember lights),
## and the entry idiom (cyan transom + warm sconces + CRT kiosk + planter boxes + steps).
static func honeycomb_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var Lat := load("res://scripts/generation/lattice_builder.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "honeycomb")
	var size: Vector3 = spec.get("size", Vector3(4.5, 10.0, 6.3))
	var h := size.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var bone := _st()
	var metal := _st()
	var dark := _st()
	var rust := _st()
	var leaf := _st()
	var warm := _st()
	var cyan := _st()
	var kb := float(str(spec.get("kind", "honeycomb")).hash() % 1000)
	# facade fixtures ride the engine's REAL cell rects (same axes/merge hashes as the frame)
	var ent: Dictionary = Lat.entrances(spec)
	var rects: Array = Lat.honeyframe_cell_rects(size, {"reserved": ent.get("reserved", []),
		"skip_faces": (spec.get("lattice_overrides", {}) as Dictionary).get("skip_faces", [])})
	var fx: Dictionary = tbl["fixtures"]
	var sc: Dictionary = tbl["sign_cell"]
	var sign_y := (float(sc["y0"]) + float(sc["y1"])) * 0.5 * h
	var sign_done := false
	for r_v in rects:
		var r := r_v as Dictionary
		var n: Vector3 = r["n"]
		var u: Vector3 = r["u"]
		var c: Vector3 = r["center"]
		var rw := float(r["w"])
		var rh := float(r["h"])
		if rw < 0.7 or rh < 0.7 or c.y > 0.95 * h:
			continue
		# the storey-2 centre cell on the front carries the hex-badge sign instead of fixtures
		if not sign_done and n.z > 0.5 and absf(c.x - float(sc["x"]) * h) < rw * 0.5 and absf(c.y - sign_y) < rh * 0.5:
			sign_done = true
			_emit_oriented_box_st(dark, c + n * 0.055, u, Vector3.UP, n,
				Vector3(rw * 0.34, rh * 0.30, 0.02))
			for hex_i in range(6):
				var a0 := TAU * float(hex_i) / 6.0 + PI / 6.0
				var a1 := TAU * float(hex_i + 1) / 6.0 + PI / 6.0
				var hc := c + Vector3(0, rh * 0.16, 0)
				_tube(bone, [hc + (u * cos(a0) + Vector3.UP * sin(a0)) * 0.14 + n * 0.09,
					hc + (u * cos(a1) + Vector3.UP * sin(a1)) * 0.14 + n * 0.09], 0.022, 4)
			continue
		if c.y < 1.2:
			continue   # ground cells belong to the entry idiom
		_emit_oriented_box_st(dark, c + u * (-rw * 0.26) + Vector3(0, rh * 0.20, 0) + n * 0.05,
			u, Vector3.UP, n, Vector3(float(fx["vent_w"]) * 0.5, float(fx["vent_h"]) * 0.5, 0.025))
		for sl in range(3):
			_emit_oriented_box_st(bone, c + u * (-rw * 0.26) + Vector3(0, rh * 0.20 - float(fx["vent_h"]) * 0.30 + float(sl) * float(fx["vent_h"]) * 0.30, 0) + n * 0.075,
				u, Vector3.UP, n, Vector3(float(fx["vent_w"]) * 0.46, 0.018, 0.012))
		_emit_oriented_box_st(bone, c + Vector3(0, -rh * 0.32, 0) + n * 0.075,
			u, Vector3.UP, n, Vector3(rw * 0.26, float(fx["planter_h"]) * 0.5, 0.075))
		_emit_oriented_box_st(leaf, c + Vector3(0, -rh * 0.32 + float(fx["planter_h"]) * 0.62, 0) + n * 0.075,
			u, Vector3.UP, n, Vector3(rw * 0.24, 0.035, 0.065))
	# the ring-balustrade parapet riding the crown (rail + baluster rings + red-tipped posts)
	var pp: Dictionary = tbl["parapet"]
	var py := h + 0.6
	var b_r := float(pp["baluster_r"])
	var spacing := float(pp["spacing"])
	var rim := [[Vector3(-hx - 0.09, 0, hz + 0.09), Vector3(hx + 0.09, 0, hz + 0.09)],
		[Vector3(hx + 0.09, 0, hz + 0.09), Vector3(hx + 0.09, 0, -hz - 0.09)],
		[Vector3(hx + 0.09, 0, -hz - 0.09), Vector3(-hx - 0.09, 0, -hz - 0.09)],
		[Vector3(-hx - 0.09, 0, -hz - 0.09), Vector3(-hx - 0.09, 0, hz + 0.09)]]
	for edge_v in rim:
		var e0: Vector3 = (edge_v as Array)[0]
		var e1: Vector3 = (edge_v as Array)[1]
		var e_dir := (e1 - e0).normalized()
		var e_len := (e1 - e0).length()
		var count := int(e_len / spacing)
		for bi in range(count):
			var bp := e0 + e_dir * ((float(bi) + 0.5) * e_len / float(count))
			_emit_torus_st(bone, Vector3(bp.x, py + b_r + 0.02, bp.z), e_dir.cross(Vector3.UP),
				b_r, 0.018, 8, 4)
		_tube(bone, [Vector3(e0.x, py + b_r * 2.0 + 0.05, e0.z), Vector3(e1.x, py + b_r * 2.0 + 0.05, e1.z)], 0.028, 5)
	for cxp in [-1.0, 1.0]:
		for czp in [-1.0, 1.0]:
			var post := Vector3(float(cxp) * (hx + 0.09), py, float(czp) * (hz + 0.09))
			_rings_loft(bone, post, float(pp["tip_h"]), [[0.0, float(pp["post_r"]) / float(pp["tip_h"])],
				[1.0, 0.35 * float(pp["post_r"]) / float(pp["tip_h"])]], 6)
			_emit_oriented_box_st(warm, post + Vector3(0, float(pp["tip_h"]) + 0.035, 0),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.032, 0.032, 0.032))
	# THE TORN FLANK (+X): rust wash, the strut-chaos hole, catwalk rows with ember lights
	var hole: Dictionary = tbl["hole"]
	var hzc := float(hole["z"]) * h
	var hhw := float(hole["half_w"]) * h
	var hy0 := float(hole["y0"]) * h
	var hy1 := float(hole["y1"]) * h
	_emit_oriented_box_st(dark, Vector3(hx + 0.02, (hy0 + hy1) * 0.5, hzc),
		Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0), Vector3(hhw, (hy1 - hy0) * 0.5, 0.02))
	var rim_pts: Array = []
	for ri in range(13):
		var ra := TAU * float(ri) / 12.0
		rim_pts.append(Vector3(hx + 0.06, (hy0 + hy1) * 0.5 + sin(ra) * (hy1 - hy0) * 0.5,
			hzc + cos(ra) * hhw * (1.0 + 0.08 * _h01(kb + float(ri) * 7.7))))
	_tube(rust, rim_pts, 0.05, 5)
	for st_i in range(int(hole["struts"])):
		var z_a := hzc + (_h01(kb + float(st_i) * 11.3) - 0.5) * hhw * 1.8
		var z_b := hzc + (_h01(kb + float(st_i) * 5.9 + 30.0) - 0.5) * hhw * 1.8
		var y_a := lerpf(hy0, hy1, _h01(kb + float(st_i) * 7.1 + 60.0))
		var y_b := lerpf(hy0, hy1, _h01(kb + float(st_i) * 3.7 + 90.0))
		var strut_st := rust if st_i % 3 != 0 else bone
		_tube(strut_st, [Vector3(hx - 0.12, y_a, z_a),
			Vector3(hx + 0.05 + 0.1 * _h01(kb + float(st_i) * 2.3), (y_a + y_b) * 0.5, (z_a + z_b) * 0.5),
			Vector3(hx - 0.12, y_b, z_b)], 0.042, 4)
	var cw: Dictionary = tbl["catwalks"]
	var cw_out := float(cw["out"]) * h
	for row_v in (cw["rows"] as Array):
		var ry := float(row_v) * h
		_emit_oriented_box_st(metal, Vector3(hx + cw_out * 0.5, ry, 0),
			Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), Vector3(hz - 0.15, 0.03, cw_out * 0.5))
		var rail_y := ry + float(cw["rail_h"]) * h
		_tube(metal, [Vector3(hx + cw_out - 0.04, rail_y, -hz + 0.15), Vector3(hx + cw_out - 0.04, rail_y, hz - 0.15)], 0.025, 4)
		for up_i in range(6):
			var uz := lerpf(-hz + 0.2, hz - 0.2, float(up_i) / 5.0)
			_tube(metal, [Vector3(hx + cw_out - 0.04, ry + 0.03, uz), Vector3(hx + cw_out - 0.04, rail_y, uz)], 0.018, 4)
		for br_i in range(int(cw["posts"])):
			var bz := lerpf(-hz + 0.3, hz - 0.3, (float(br_i) + 0.5) / float(int(cw["posts"])))
			_tube(metal, [Vector3(hx + cw_out - 0.06, ry - 0.03, bz), Vector3(hx + 0.02, ry - 0.5, bz)], 0.024, 4)
	for em in range(int(tbl["embers"])):
		var ey := lerpf(0.15 * h, 0.85 * h, _h01(kb + float(em) * 13.7 + 200.0))
		var ez := lerpf(-hz + 0.3, hz - 0.3, _h01(kb + float(em) * 7.9 + 240.0))
		_emit_oriented_box_st(warm, Vector3(hx + 0.10 + 0.25 * _h01(kb + float(em) * 3.1), ey, ez),
			Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), Vector3(0.028, 0.028, 0.028))
	var rst: Dictionary = tbl["rust"]
	for sk in range(int(rst["streaks"])):
		var sz2 := lerpf(-hz + 0.2, hz - 0.2, _h01(kb + float(sk) * 9.3))
		var s_top := h * (0.55 + 0.4 * _h01(kb + float(sk) * 5.1 + 20.0))
		var s_len := h * (0.15 + 0.30 * _h01(kb + float(sk) * 3.3 + 50.0))
		_emit_oriented_box_st(rust, Vector3(hx + 0.03, s_top - s_len * 0.5, sz2),
			Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), Vector3(0.05 + 0.05 * _h01(kb + float(sk) * 1.7), s_len * 0.5, 0.012))
	# the ENTRY idiom: cyan transom, warm sconces, the CRT kiosk, planter boxes and two steps
	var en: Dictionary = tbl["entry"]
	var door_w := float((spec.get("entrances", {}) as Dictionary).get("main_w", 1.6))
	var door_h := float((spec.get("entrances", {}) as Dictionary).get("main_h", 2.7))
	_emit_oriented_box_st(cyan, Vector3(0, door_h + 0.05 + float(en["transom_h"]) * 0.5, hz + 0.07),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(door_w * 0.5 + 0.12, float(en["transom_h"]) * 0.5, 0.03))
	for so in [1.0, -1.0]:
		var sx3 := float(so) * (door_w * 0.5 + float(en["sconce_off"]) - 0.6)
		_emit_oriented_box_st(dark, Vector3(sx3, float(en["sconce_y"]), hz + 0.06),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.05, 0.12, 0.05))
		_emit_oriented_box_st(warm, Vector3(sx3, float(en["sconce_y"]) + 0.02, hz + 0.115),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.035, 0.075, 0.02))
	var kx := float(en["kiosk_x"])
	_emit_oriented_box_st(dark, Vector3(kx, 0.42, hz + 0.50),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.17, 0.42, 0.13))
	var kv := Vector3(0, 0.906, 0.423)
	var kn := Vector3(0, -0.423, 0.906)
	_emit_oriented_box_st(cyan, Vector3(kx, 0.90, hz + 0.55) + kn * 0.02, Vector3(1, 0, 0), kv, kn,
		Vector3(0.11, 0.08, 0.01))
	for pxi in range(2):
		var plx := float((en["planters_x"] as Array)[pxi])
		_emit_oriented_box_st(bone, Vector3(plx, 0.22, hz + 0.45),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.24, 0.22, 0.20))
		_emit_oriented_box_st(leaf, Vector3(plx, 0.50, hz + 0.45),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.22, 0.07, 0.18))
	_emit_oriented_box_st(bone, Vector3(0, 0.07, hz + 0.42), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(door_w * 0.5 + 0.35, 0.07, 0.42))
	_emit_oriented_box_st(bone, Vector3(0, 0.20, hz + 0.22), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(door_w * 0.5 + 0.20, 0.06, 0.22))
	for stool in [bone, metal, dark, rust, leaf, warm, cyan]:
		(stool as SurfaceTool).generate_normals()
	return {"bone": bone.commit(), "metal": metal.commit(), "dark": dark.commit(),
		"rust": rust.commit(), "leaf": leaf.commit(), "warm": warm.commit(),
		"cyan": cyan.commit(),
		"nameplate_pos": Vector3(0, float(sc["y1"]) * h + 0.3, hz + 0.2)}

## Zone-3 detail passes (SURVEY REBUILD 1.8), every part from the ZONE3 survey frames: the
## slat-roofed PORCH row (posts + rafters + slat courses, wrapping the left flank), the boarded
## siding + barred shop window, the ALWAYS OPEN sign, the arched upper-window surrounds, the
## terminal cabinet (sole emissive), the cornice drip crust, and the rust TENDRILS — ground
## network, corner climbs, and the drip curtains falling through the torn wing's galleries.
static func zone3_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "zone3")
	var size: Vector3 = spec.get("size", Vector3(4.0, 5.4, 3.6))
	var h := size.y
	var hz := size.z * 0.5
	var wood := _st()
	var metal := _st()
	var dark := _st()
	var rust := _st()
	var glow := _st()
	var kb := float(str(spec.get("kind", "zone3")).hash() % 1000)
	var main_x0 := float(tbl["main_x0"]) * h
	var main_x1 := float(tbl["main_x1"]) * h
	var wing_x1 := float(tbl["wing_x1"]) * h
	var main_cx := (main_x0 + main_x1) * 0.5
	var main_hw := (main_x1 - main_x0) * 0.5
	# the PORCH row: tapered posts, sloped rafters, slat courses laid with gaps (front + left wrap)
	var po: Dictionary = tbl["porch"]
	var p_out := float(po["out"]) * h
	var y_wall := float(po["y_wall"]) * h
	var y_post := float(po["y_post"]) * h
	var bays := int(po["bays"])
	for b in range(bays + 1):
		var px := lerpf(main_x0 + 0.10, main_x1 - 0.10, float(b) / float(bays))
		_rings_loft(wood, Vector3(px, 0.0, hz + p_out - 0.08), y_post,
			[[0.0, 0.055 / y_post], [1.0, 0.038 / y_post]], 6)
	for b2 in range(bays):
		var xa := lerpf(main_x0 + 0.10, main_x1 - 0.10, float(b2) / float(bays))
		var xb := lerpf(main_x0 + 0.10, main_x1 - 0.10, float(b2 + 1) / float(bays))
		for rf in [xa + 0.06, (xa + xb) * 0.5, xb - 0.06]:
			_tube(wood, [Vector3(float(rf), y_wall, hz), Vector3(float(rf), y_post, hz + p_out)], 0.035, 4)
		var slats := int(po["slats"])
		for sl in range(slats):
			var t := (float(sl) + 0.5) / float(slats)
			var sy := lerpf(y_wall, y_post, t)
			var sz := lerpf(hz, hz + p_out, t)
			_emit_oriented_box_st(wood, Vector3((xa + xb) * 0.5, sy, sz),
				Vector3(1, 0, 0), Vector3(0, p_out, y_wall - y_post).normalized(), Vector3(0, y_post - y_wall, p_out).normalized().cross(Vector3(1, 0, 0)),
				Vector3((xb - xa) * 0.5 - 0.03, 0.055, 0.014))
	if bool(po.get("left_wrap", true)):
		var lz0 := -hz * 0.55
		var lz1 := hz * 0.55
		for pzv in [lz0, lz1]:
			_rings_loft(wood, Vector3(main_x0 - p_out + 0.08, 0.0, float(pzv)), y_post,
				[[0.0, 0.055 / y_post], [1.0, 0.038 / y_post]], 6)
		for rf2 in [lz0 + 0.06, (lz0 + lz1) * 0.5, lz1 - 0.06]:
			_tube(wood, [Vector3(main_x0, y_wall, float(rf2)), Vector3(main_x0 - p_out + 0.08, y_post, float(rf2))], 0.035, 4)
		var slats2 := int(po["slats"])
		for sl2 in range(slats2):
			var t2 := (float(sl2) + 0.5) / float(slats2)
			_emit_oriented_box_st(wood, Vector3(lerpf(main_x0, main_x0 - p_out + 0.08, t2), lerpf(y_wall, y_post, t2), (lz0 + lz1) * 0.5),
				Vector3(0, 0, 1), Vector3(-p_out, y_wall - y_post, 0).normalized(), Vector3(y_wall - y_post, p_out, 0).normalized(),
				Vector3((lz1 - lz0) * 0.5 - 0.03, 0.055, 0.014))
	# the boarded SIDING: horizontal courses split around the doorway
	var sd: Dictionary = tbl["siding"]
	var sd_y1 := float(sd["y1"]) * h
	var rows := int(sd["rows"])
	var door_hw := float(spec.get("entrances", {}).get("main_w", 1.0)) * 0.5 + 0.10
	for rw in range(rows):
		var by := (float(rw) + 0.5) / float(rows) * sd_y1
		var bh := sd_y1 / float(rows) * 0.42
		_emit_oriented_box_st(wood, Vector3((main_x0 - door_hw) * 0.5, by, hz + 0.03),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3((-door_hw - main_x0) * 0.5 - 0.02, bh, 0.014))
		if main_x1 - door_hw > 0.1:
			_emit_oriented_box_st(wood, Vector3((door_hw + main_x1) * 0.5, by, hz + 0.03),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3((main_x1 - door_hw) * 0.5 - 0.02, bh, 0.014))
	# the barred SHOP WINDOW: dark recess + bars
	var swn: Dictionary = tbl["shop_window"]
	var sw_c := Vector3(float(swn["x"]) * h, (float(swn["y0"]) + float(swn["y1"])) * 0.5 * h, hz)
	var sw_hw := float(swn["half_w"]) * h
	var sw_hh := (float(swn["y1"]) - float(swn["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, sw_c + Vector3(0, 0, 0.045), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sw_hw, sw_hh, 0.012))
	for bar in range(int(swn["bars"])):
		var bx := sw_c.x + lerpf(-sw_hw * 0.6, sw_hw * 0.6, float(bar) / float(int(swn["bars"]) - 1))
		_tube(metal, [Vector3(bx, sw_c.y - sw_hh, hz + 0.07), Vector3(bx, sw_c.y + sw_hh, hz + 0.07)], 0.022, 4)
	for hb in [-0.5, 0.5]:
		_tube(metal, [Vector3(sw_c.x - sw_hw, sw_c.y + float(hb) * sw_hh, hz + 0.07),
			Vector3(sw_c.x + sw_hw, sw_c.y + float(hb) * sw_hh, hz + 0.07)], 0.022, 4)
	_emit_oriented_box_st(wood, sw_c + Vector3(0, -sw_hh - 0.05, 0.07), Vector3(1, 0, 0), Vector3.UP,
		Vector3(0, 0, 1), Vector3(sw_hw + 0.08, 0.045, 0.06))
	# the ALWAYS OPEN sign: dark board + wood frame (letters are texture-time)
	var sgn: Dictionary = tbl["sign"]
	var sg_c := Vector3(float(sgn["x"]) * h, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h, hz + 0.06)
	var sg_hw := float(sgn["half_w"]) * h
	var sg_hh := (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, sg_c, Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sg_hw, sg_hh, 0.02))
	for fbar in [[0.0, sg_hh, sg_hw + 0.05, 0.045], [0.0, -sg_hh, sg_hw + 0.05, 0.045],
			[-sg_hw, 0.0, 0.045, sg_hh + 0.05], [sg_hw, 0.0, 0.045, sg_hh + 0.05]]:
		var fb := fbar as Array
		_emit_oriented_box_st(wood, sg_c + Vector3(float(fb[0]), float(fb[1]), 0.02),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(float(fb[2]), float(fb[3]), 0.03))
	# arched upper-window surrounds (front + left side): jambs + head arc + sill + dark glass
	for win_set in [[tbl["windows"], Vector3(0, 0, 1)], [tbl["side_windows"], Vector3(-1, 0, 0)]]:
		var wlist: Array = (win_set as Array)[0]
		var wn_v: Vector3 = (win_set as Array)[1]
		var wu := Vector3(0, 1, 0).cross(wn_v).normalized()
		var wall_d := hz if absf(wn_v.z) > 0.5 else size.x * 0.5
		for wn_r in wlist:
			var wn := wn_r as Array
			var wx := float(wn[0]) * h
			var whw := float(wn[1]) * h
			var wy0 := float(wn[2]) * h
			var wy1 := float(wn[3]) * h
			var spring := wy1 - whw
			var base_pt := wn_v * (wall_d + 0.05)
			var pts: Array = []
			pts.append(base_pt + wu * (wx - whw) + Vector3(0, wy0, 0))
			pts.append(base_pt + wu * (wx - whw) + Vector3(0, spring, 0))
			for ai in range(1, 6):
				var aa := PI - PI * float(ai) / 6.0
				pts.append(base_pt + wu * (wx + cos(aa) * whw) + Vector3(0, spring + sin(aa) * (wy1 - spring), 0))
			pts.append(base_pt + wu * (wx + whw) + Vector3(0, spring, 0))
			pts.append(base_pt + wu * (wx + whw) + Vector3(0, wy0, 0))
			_tube(metal, pts, 0.045, 5)
			_emit_oriented_box_st(dark, wn_v * (wall_d + 0.02) + wu * wx + Vector3(0, (wy0 + wy1) * 0.5, 0),
				wu, Vector3.UP, wn_v, Vector3(whw * 0.86, (wy1 - wy0) * 0.5 - 0.03, 0.012))
			_emit_oriented_box_st(wood, wn_v * (wall_d + 0.06) + wu * wx + Vector3(0, wy0 - 0.04, 0),
				wu, Vector3.UP, wn_v, Vector3(whw + 0.07, 0.04, 0.05))
	# the TERMINAL cabinet at the entry seam — the ruin's one glow
	var tm: Dictionary = tbl["terminal"]
	var tm_x := float(tm["x"]) * h
	var tm_h := float(tm["y1"]) * h
	_emit_oriented_box_st(dark, Vector3(tm_x, tm_h * 0.5, hz + 0.22),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.16, tm_h * 0.5, 0.13))
	_emit_oriented_box_st(glow, Vector3(tm_x, tm_h * 0.62, hz + 0.355),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.10, 0.085, 0.008))
	_emit_oriented_box_st(dark, Vector3(tm_x, tm_h * 0.38, hz + 0.37),
		Vector3(1, 0, 0), Vector3(0, 0.92, 0.39), Vector3(0, -0.39, 0.92), Vector3(0.11, 0.05, 0.015))
	# cornice DRIP crust + corner root CLIMBS + the wing-gallery drip curtains + ground tendrils
	var td: Dictionary = tbl["tendrils"]
	var cor_y := float(tbl["cornice_y"]) * h
	for d in range(int(td["drips"])):
		var dx := lerpf(main_x0 - 0.2, wing_x1 + 0.1, _h01(kb + float(d) * 7.7))
		var dl := 0.15 + 0.35 * _h01(kb + float(d) * 3.1 + 40.0)
		_tube(rust, [Vector3(dx, cor_y + 0.06, hz + float(tbl["cornice_over"]) * h * 0.6),
			Vector3(dx + (_h01(kb + float(d) * 5.9) - 0.5) * 0.12, cor_y - dl, hz + 0.10)], 0.038, 4)
	var climb_xs := [-0.345, 0.345, -0.30]
	for c in range(int(td["climbs"])):
		var cxf := float(climb_xs[c % 3])
		var on_front := c < 2
		var pts_c: Array = []
		for kseg in range(6):
			var t3 := float(kseg) / 5.0
			var wig := (_h01(kb + float(c) * 31.0 + float(kseg) * 9.3) - 0.5) * 0.22
			if on_front:
				pts_c.append(Vector3(cxf * h + wig, t3 * cor_y, hz + 0.05 + 0.04 * sin(t3 * PI)))
			else:
				pts_c.append(Vector3(main_x0 - 0.05 - 0.04 * sin(t3 * PI), t3 * cor_y, cxf * h + wig))
		_tube(rust, pts_c, 0.055 - 0.02 * 0.5, 5)
	var slabs: Array = tbl["slabs"]
	var wing_c := (main_x1 + wing_x1) * 0.5
	for si in range(slabs.size()):
		var sy := float(slabs[si]) * h
		var below := (float(slabs[si - 1]) * h + float(tbl["slab_t"]) * h) if si > 0 else 0.0
		for dc in range(3):
			var dcx := wing_c + lerpf(-0.5, 0.5, _h01(kb + float(si) * 17.0 + float(dc) * 5.3)) * (wing_x1 - main_x1 - 0.3)
			_tube(rust, [Vector3(dcx, sy - float(tbl["slab_t"]) * h * 0.5, hz - 0.15),
				Vector3(dcx + (_h01(kb + float(dc) * 11.1) - 0.5) * 0.1, below + 0.02, hz - 0.20)], 0.03, 4)
	for g in range(int(td["ground"])):
		var ga := TAU * (_h01(kb + float(g) * 13.7) - 0.5)
		var g_dir := Vector3(cos(ga), 0.0, sin(ga))
		var g0 := g_dir * (size.x * 0.42)
		var reach := float(td["reach"]) * h * (0.6 + 0.8 * _h01(kb + float(g) * 7.1 + 60.0))
		var pts_g: Array = []
		for kg in range(5):
			var tg := float(kg) / 4.0
			var side := g_dir.cross(Vector3.UP) * ((_h01(kb + float(g) * 23.0 + float(kg) * 3.7) - 0.5) * 0.8)
			pts_g.append(g0 + g_dir * (reach * tg) + side * tg + Vector3(0, 0.05 + 0.03 * sin(tg * PI), 0))
		_tube(rust, pts_g, 0.065 * (1.0 - 0.4 * _h01(kb + float(g) * 3.3)), 5)
	for stool in [wood, metal, dark, rust, glow]:
		(stool as SurfaceTool).generate_normals()
	return {"wood": wood.commit(), "metal": metal.commit(), "dark": dark.commit(),
		"rust": rust.commit(), "glow": glow.commit(),
		"nameplate_pos": sg_c + Vector3(0, sg_hh + 0.25, 0.15)}

## Bulwark detail passes (SURVEY REBUILD 1.7), every part from the BULWARK survey frames: the
## ogee-crested membrane FRAME + purple panel + voronoi web (restructured around the rose and
## pores), the ROSE APERTURE (ring + spokes + glass + clamp lugs), pore portholes, the rust weep,
## the sign board, the vault-door idiom (chamfer surround + wheel hub + steps), indicator lamp,
## pore-clamp readout + console kiosk (terminal green), tower collars/finials, and the barrier
## WINGS (sagging posts + membrane bays + webs) off both flanks.
static func bulwark_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "bulwark")
	var size: Vector3 = spec.get("size", Vector3(4.6, 5.2, 3.4))
	var h := size.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var metal := _st()
	var bone := _st()
	var dark := _st()
	var rust := _st()
	var membrane := _st()
	var glow := _st()
	var fr_t: Dictionary = tbl["frame"]
	var f_hw := float(fr_t["half_w"]) * h
	var f_y0 := float(fr_t["y0"]) * h
	var f_y1 := float(fr_t["y1"]) * h
	var f_apex := float(fr_t["apex"]) * h
	var rail_r := float(fr_t["rail_r"]) * h
	var zf := hz + 0.05
	# the sagging bottom rail (W dips at the quarter points), the jambs, the springing rail, and
	# the ogee crest rising to the apex — one frame family, all riding the front wall plane
	var bot_pts: Array = []
	for i in range(13):
		var t := float(i) / 12.0
		var dip := 0.027 * h * pow(absf(sin(TAU * t)), 0.8)
		bot_pts.append(Vector3(lerpf(-f_hw, f_hw, t), f_y0 - dip, zf))
	_tube(metal, bot_pts, rail_r, 6)
	_tube(metal, [Vector3(-f_hw, f_y1, zf), Vector3(f_hw, f_y1, zf)], rail_r, 6)
	for sx in [-1.0, 1.0]:
		_tube(metal, [Vector3(float(sx) * f_hw, f_y0 - 0.01, zf), Vector3(float(sx) * f_hw, f_y1, zf)], rail_r, 6)
		var ogee: Array = []
		for i2 in range(9):
			var t2 := float(i2) / 8.0
			ogee.append(Vector3(float(sx) * f_hw * (1.0 - t2), f_y1 + (f_apex - f_y1) * (0.5 - 0.5 * cos(PI * t2)), zf))
		_tube(metal, ogee, rail_r * 1.15, 6)
	if bool(fr_t.get("cupola", true)):
		_emit_oriented_box_st(metal, Vector3(0, f_apex + 0.028 * h, hz - 0.02),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.05 * h, 0.028 * h, 0.05 * h))
		_rings_loft(metal, Vector3(0, f_apex + 0.056 * h, hz - 0.02), 0.06 * h,
			[[0.0, 0.8], [1.0, 0.05]], 8)
	# the membrane PANEL: column strips from the sagging rail up to the frame band top, then the
	# crest gable filling the ogee — the purple skin the web rides on (front-facing)
	var cols := 12
	for c in range(cols):
		var t0 := float(c) / float(cols)
		var t1 := float(c + 1) / float(cols)
		var xa := lerpf(-f_hw, f_hw, t0)
		var xb := lerpf(-f_hw, f_hw, t1)
		var ya := f_y0 - 0.027 * h * pow(absf(sin(TAU * t0)), 0.8)
		var yb := f_y0 - 0.027 * h * pow(absf(sin(TAU * t1)), 0.8)
		_quad_out(membrane, Vector3(xa, ya, hz + 0.02), Vector3(xb, yb, hz + 0.02),
			Vector3(xb, f_y1, hz + 0.02), Vector3(xa, f_y1, hz + 0.02), Vector3(0, (f_y0 + f_y1) * 0.5, 0))
		var ga := f_y1 + (f_apex - f_y1) * (0.5 - 0.5 * cos(PI * (1.0 - absf(t0 * 2.0 - 1.0))))
		var gb := f_y1 + (f_apex - f_y1) * (0.5 - 0.5 * cos(PI * (1.0 - absf(t1 * 2.0 - 1.0))))
		_quad_out(membrane, Vector3(xa, f_y1, hz + 0.02), Vector3(xb, f_y1, hz + 0.02),
			Vector3(xb, gb, hz + 0.02), Vector3(xa, ga, hz + 0.02), Vector3(0, f_y1, 0))
	# the voronoi WEB on the panel, restructured around the rose + pores (the survey's keeps_clear
	# made the holes; here the web edges are actually dropped inside them)
	var Lat := load("res://scripts/generation/lattice_builder.gd") as GDScript
	var web_p := {"mirror": true, "seeds": 26, "focals": 2, "merge_start": 0.7,
		"merge_range": 2.4, "merge_max": 0.78, "sag": 0.14}
	var rose: Dictionary = tbl["rose"]
	var pores: Array = tbl["pores"]
	var holes: Array = [[float(rose["x"]) * h + f_hw, float(rose["y"]) * h - f_y0, float(rose["r"]) * h + 0.06]]
	for pr_v in pores:
		var pr := pr_v as Array
		holes.append([float(pr[0]) * h + f_hw, float(pr[1]) * h - f_y0, float(pr[2]) * h + 0.05])
	var raw_paths: Array = Lat._voronoi_web(f_hw * 2.0, f_y1 - f_y0, web_p, 37.0, Vector3(0, 0, 1), [])
	var web_paths: Array = []
	for path_v in raw_paths:
		var pv := path_v as PackedVector2Array
		var mid := (pv[0] + pv[pv.size() - 1]) * 0.5
		var inside := false
		for hole_v in holes:
			var hc := hole_v as Array
			if mid.distance_to(Vector2(float(hc[0]), float(hc[1]))) < float(hc[2]):
				inside = true
				break
		if not inside:
			web_paths.append(pv)
	var LG := load("res://scripts/generation/lattice_graph.gd") as GDScript
	var graph: Dictionary = LG.build(web_paths, 0.012)
	LG.mesh(bone, graph, LG.plane_surface(Vector3(-f_hw, f_y0, hz + 0.045), Vector3(1, 0, 0), Vector3(0, 1, 0)), 0.042, 5)
	# the ROSE APERTURE: outer ring + hub + radial spokes + purple glass + two clamp lugs
	var rc := Vector3(float(rose["x"]) * h, float(rose["y"]) * h, hz)
	var r_rose := float(rose["r"]) * h
	_emit_torus_st(metal, rc + Vector3(0, 0, 0.10), Vector3(0, 0, 1), r_rose, 0.055, 20, 6)
	_emit_torus_st(metal, rc + Vector3(0, 0, 0.09), Vector3(0, 0, 1), r_rose * 0.24, 0.04, 10, 5)
	var spokes := int(rose.get("spokes", 8))
	for sp in range(spokes):
		var a := TAU * float(sp) / float(spokes)
		_tube(metal, [rc + Vector3(cos(a) * r_rose * 0.24, sin(a) * r_rose * 0.24, 0.07),
			rc + Vector3(cos(a) * r_rose, sin(a) * r_rose, 0.07)], 0.028, 4)
	for lug in [0.0, PI]:
		_emit_oriented_box_st(metal, rc + Vector3(cos(lug) * (r_rose + 0.10), sin(lug) * (r_rose + 0.10), 0.09),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.09, 0.055, 0.035))
	var fan := 16
	for fi in range(fan):
		var a0 := TAU * float(fi) / float(fan)
		var a1 := TAU * float(fi + 1) / float(fan)
		membrane.add_vertex(rc + Vector3(0, 0, 0.03))
		membrane.add_vertex(rc + Vector3(cos(a1) * r_rose, sin(a1) * r_rose, 0.03))
		membrane.add_vertex(rc + Vector3(cos(a0) * r_rose, sin(a0) * r_rose, 0.03))
	# pore portholes (the flagged one is the four-lobed wheel)
	for pr_v2 in pores:
		var pr2 := pr_v2 as Array
		var pc := Vector3(float(pr2[0]) * h, float(pr2[1]) * h, hz)
		var r_p := float(pr2[2]) * h
		_emit_torus_st(metal, pc + Vector3(0, 0, 0.08), Vector3(0, 0, 1), r_p, 0.035, 12, 5)
		for fi2 in range(10):
			var b0 := TAU * float(fi2) / 10.0
			var b1 := TAU * float(fi2 + 1) / 10.0
			membrane.add_vertex(pc + Vector3(0, 0, 0.03))
			membrane.add_vertex(pc + Vector3(cos(b1) * r_p, sin(b1) * r_p, 0.03))
			membrane.add_vertex(pc + Vector3(cos(b0) * r_p, sin(b0) * r_p, 0.03))
		if pr2.size() > 3:
			for sp2 in range(4):
				var a2 := TAU * float(sp2) / 4.0 + PI * 0.25
				_tube(metal, [pc + Vector3(0, 0, 0.06), pc + Vector3(cos(a2) * r_p, sin(a2) * r_p, 0.06)], 0.024, 4)
	# the rust WEEP bleeding from the rose down over the sign band (three tapered streaks)
	var weep: Dictionary = tbl["weep"]
	var wx := float(weep["x"]) * h
	for streak in [[0.0, 0.085, 1.0], [-0.09, 0.036, 0.66], [0.07, 0.030, 0.78]]:
		var sk := streak as Array
		var s_top := float(weep["y1"]) * h
		var s_bot := lerpf(float(weep["y0"]) * h, s_top, 1.0 - float(sk[2]))
		_emit_oriented_box_st(rust, Vector3(wx + float(sk[0]), (s_top + s_bot) * 0.5, hz + 0.095),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
			Vector3(float(sk[1]), (s_top - s_bot) * 0.5, 0.012))
	# the SIGN board (letters are texture-time; the frame is riveted verdigris, green corner studs)
	var sgn: Dictionary = tbl["sign"]
	var sg_hw := float(sgn["half_w"]) * h
	var sg_y := (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h
	var sg_hh := (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, Vector3(0, sg_y, hz + 0.08), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sg_hw, sg_hh, 0.02))
	for bar in [[0.0, sg_hh, sg_hw + 0.05, 0.04], [0.0, -sg_hh, sg_hw + 0.05, 0.04],
			[-sg_hw, 0.0, 0.04, sg_hh + 0.05], [sg_hw, 0.0, 0.04, sg_hh + 0.05]]:
		var br := bar as Array
		_emit_oriented_box_st(metal, Vector3(float(br[0]), sg_y + float(br[1]), hz + 0.10),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(float(br[2]), float(br[3]), 0.035))
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			_emit_oriented_box_st(glow, Vector3(float(cx) * (sg_hw - 0.06), sg_y + float(cy) * (sg_hh - 0.06), hz + 0.115),
				Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.025, 0.025, 0.012))
	# the VAULT-DOOR idiom: doubled chamfered surround + wheel hub on the leaf + two steps
	var door_t: Dictionary = tbl["door"]
	var sw := float(door_t["surround_half_w"]) * h
	var s_top2 := float(door_t["surround_top"]) * h
	var ch := float(door_t["chamfer"]) * h
	for inset in [0.0, 0.12]:
		var swi := sw - float(inset)
		var t_i := s_top2 - float(inset)
		_tube(metal, [Vector3(-swi, 0.02, zf), Vector3(-swi, t_i - ch, zf), Vector3(-swi + ch, t_i, zf),
			Vector3(swi - ch, t_i, zf), Vector3(swi, t_i - ch, zf), Vector3(swi, 0.02, zf)], 0.065, 5)
	var recess := float(spec.get("door_recess", 0.5))
	var hub_c := Vector3(0, float(spec.get("entrances", {}).get("main_h", 2.0)) * 0.55, hz - recess + 0.07)
	var hub_r := float(door_t["hub_r"]) * h
	_emit_torus_st(metal, hub_c, Vector3(0, 0, 1), hub_r, 0.042, 14, 5)
	for sp3 in range(3):
		var a3 := TAU * float(sp3) / 3.0 + PI * 0.5
		_tube(metal, [hub_c + Vector3(0, 0, 0.02), hub_c + Vector3(cos(a3) * hub_r, sin(a3) * hub_r, 0.02)], 0.03, 4)
	_emit_oriented_box_st(metal, hub_c, Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.06, 0.06, 0.05))
	_emit_oriented_box_st(dark, Vector3(0, 0.055, hz + 0.42), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sw + 0.15, 0.055, 0.42))
	_emit_oriented_box_st(dark, Vector3(0, 0.165, hz + 0.24), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(sw + 0.02, 0.055, 0.24))
	# indicator lamp (left) + pore-clamp READOUT on the wall + the console KIOSK (right)
	var ind: Dictionary = tbl["indicator"]
	var ind_c := Vector3(float(ind["x"]) * h, (float(ind["y0"]) + float(ind["y1"])) * 0.5 * h, hz)
	var ind_hh := (float(ind["y1"]) - float(ind["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, ind_c + Vector3(0, 0, 0.05), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(float(ind["half_w"]) * h, ind_hh, 0.05))
	_emit_oriented_box_st(glow, ind_c + Vector3(0, 0, 0.105), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(float(ind["half_w"]) * h - 0.03, ind_hh - 0.03, 0.012))
	var rd: Dictionary = tbl["readout"]
	var rd_c := Vector3(float(rd["x"]) * h, (float(rd["y0"]) + float(rd["y1"])) * 0.5 * h, hz)
	var rd_hh := (float(rd["y1"]) - float(rd["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, rd_c + Vector3(0, 0, 0.04), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(float(rd["half_w"]) * h + 0.03, rd_hh + 0.03, 0.03))
	_emit_oriented_box_st(glow, rd_c + Vector3(0, 0, 0.075), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(float(rd["half_w"]) * h, rd_hh, 0.012))
	var ki: Dictionary = tbl["kiosk"]
	var ki_x := float(ki["x"]) * h
	_emit_oriented_box_st(dark, Vector3(ki_x, 0.36, hz + 0.55), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3(0.20, 0.36, 0.16))
	var desk_v := Vector3(0, 0.906, 0.423)
	var desk_n := Vector3(0, -0.423, 0.906)
	_emit_oriented_box_st(dark, Vector3(ki_x, 0.78, hz + 0.60), Vector3(1, 0, 0), desk_v, desk_n,
		Vector3(0.23, 0.17, 0.025))
	_emit_oriented_box_st(glow, Vector3(ki_x, 0.78, hz + 0.60) + desk_n * 0.032, Vector3(1, 0, 0), desk_v, desk_n,
		Vector3(0.15, 0.10, 0.008))
	# tower dressing: collar rings + finial spikes + the numbered placard on the front-right shaft
	var twr: Dictionary = tbl["tower"]
	var t_shaft := float(twr["r"]) * h
	for sx3 in [-1.0, 1.0]:
		for sz3 in [-1.0, 1.0]:
			var tc := Vector3(float(sx3) * hx, 0.0, float(sz3) * hz)
			for col_v in (twr["collars"] as Array):
				_emit_torus_st(metal, tc + Vector3(0, float(col_v) * h, 0), Vector3.UP,
					t_shaft + 0.015, 0.035, 14, 5)
			_rings_loft(metal, tc + Vector3(0, h, 0), 0.06 * h, [[0.0, 0.20], [1.0, 0.016]], 6)
	_emit_oriented_box_st(dark, Vector3(hx, 0.62 * h, hz + t_shaft + 0.02),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.10, 0.16, 0.015))
	# the BARRIER WINGS: sagging membrane bays on tapered posts off both flanks; each bay carries
	# its own small web; the top rail follows the sag; splay struts brace every post foot
	var wg: Dictionary = tbl["wing"]
	var bays := int(wg["bays"])
	var bay_len := float(wg["bay_len"]) * h
	var panel_h := float(wg["panel_h"]) * h
	var sag := float(wg["sag"])
	var wz := float(wg["lateral"]) * h
	var post_r := float(wg["post_r"]) * h
	var wing_p := {"mirror": false, "seeds": 10, "focals": 1, "merge_start": 0.6,
		"merge_range": 2.0, "merge_max": 0.7, "sag": 0.18}
	for sx4 in [-1.0, 1.0]:
		for b in range(bays):
			var x_a := float(sx4) * (hx + bay_len * float(b))
			var x_b := float(sx4) * (hx + bay_len * float(b + 1))
			var wcols := 6
			for c2 in range(wcols):
				var u0 := float(c2) / float(wcols)
				var u1 := float(c2 + 1) / float(wcols)
				var top_a := panel_h * (1.0 - sag * sin(PI * u0))
				var top_b := panel_h * (1.0 - sag * sin(PI * u1))
				# the two faces sit 12 mm apart — coplanar twins z-fight and the loser's culled
				# front faces read as a MISSING wing from one side
				var pa := Vector3(lerpf(x_a, x_b, u0), 0.05, wz + 0.012)
				var pb := Vector3(lerpf(x_a, x_b, u1), 0.05, wz + 0.012)
				_quad_out(membrane, pa, pb, Vector3(pb.x, top_b, wz + 0.012), Vector3(pa.x, top_a, wz + 0.012),
					Vector3(pa.x, panel_h * 0.5, wz - 2.0))
				var qa := Vector3(pa.x, 0.05, wz - 0.012)
				var qb := Vector3(pb.x, 0.05, wz - 0.012)
				_quad_out(membrane, qb, qa, Vector3(qa.x, top_a, wz - 0.012), Vector3(qb.x, top_b, wz - 0.012),
					Vector3(pa.x, panel_h * 0.5, wz + 2.0))
			var rail_pts: Array = []
			for i3 in range(7):
				var u2 := float(i3) / 6.0
				rail_pts.append(Vector3(lerpf(x_a, x_b, u2), panel_h * (1.0 - sag * sin(PI * u2)), wz))
			_tube(metal, rail_pts, 0.045, 5)
			var bay_paths: Array = Lat._voronoi_web(bay_len, panel_h * (1.0 - sag) - 0.1, wing_p,
				71.0 + float(b) * 13.0 + (0.0 if sx4 > 0.0 else 5.0), Vector3(0, 0, 1), [])
			var bay_graph: Dictionary = LG.build(bay_paths, 0.012)
			var w_origin := Vector3(minf(x_a, x_b), 0.05, wz + 0.03)
			LG.mesh(bone, bay_graph, LG.plane_surface(w_origin, Vector3(1, 0, 0), Vector3(0, 1, 0)), 0.032, 4)
			# the post at this bay's outer end (the last one is the tip mast)
			var pc2 := Vector3(x_b, 0.0, wz)
			var ph := panel_h + 0.4
			_rings_loft(metal, pc2, ph, [[0.0, 1.6 * post_r / ph], [0.05, post_r / ph],
				[1.0, 0.55 * post_r / ph]], 8)
			_rings_loft(metal, pc2 + Vector3(0, ph, 0), 0.22, [[0.0, 0.32], [0.5, 0.41], [1.0, 0.05]], 6)
			for strut_s in [-1.0, 1.0]:
				_tube(metal, [Vector3(x_b, 0.0, wz + float(strut_s) * 0.55),
					Vector3(x_b, panel_h * 0.32, wz)], 0.035, 4)
	for stool in [metal, bone, dark, rust, membrane, glow]:
		(stool as SurfaceTool).generate_normals()
	return {"metal": metal.commit(), "bone": bone.commit(), "dark": dark.commit(),
		"rust": rust.commit(), "membrane": membrane.commit(), "glow": glow.commit(),
		"nameplate_pos": Vector3(0, sg_y + sg_hh + 0.25, hz + 0.2)}

static func beacon_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "beacon")
	var rings: Array = Survey.beacon_rings(spec)
	var h := float(spec.get("height", 7.2))
	var bone := _st()
	var dark := _st()
	var amber := _st()
	var glow := _st()
	var cyan := _st()
	var warm := _st()
	var leaf := _st()
	var rails := _st()
	var fr := PI * 0.5
	var kb := float(str(spec.get("kind", "beacon_hill")).hash() % 1000)
	var half_arc := float(tbl["bay_half_arc"])
	var panes: Dictionary = tbl["panes"]
	var lantern_base := 0.905 * h
	for b_v in (tbl["bays"] as Array):
		var b := b_v as Array
		var bth: float = fr + float(b[0])
		var by0 := float(b[1]) * h
		var by1 := float(b[2]) * h
		var spring := by1 - (half_arc * float(Survey.lathe_local_r(rings, by1, bth)))
		# doubled rib outline: two concentric arch tubes riding the wall (jambs + semicircle head)
		for off_v in [0.0, 0.09]:
			var off := float(off_v)
			var pts: Array = []
			var arc_w := half_arc - off / maxf(0.5, float(Survey.lathe_local_r(rings, by0, bth)))
			pts.append(_drum_pt(rings, bth - arc_w, by0, 0.10))
			pts.append(_drum_pt(rings, bth - arc_w, spring, 0.10))
			for i in range(1, 8):
				var a := PI - PI * float(i) / 8.0
				var uu: float = cos(a) * arc_w
				var vy: float = spring + sin(a) * (by1 - spring - off)
				pts.append(_drum_pt(rings, bth + uu, vy, 0.10))
			pts.append(_drum_pt(rings, bth + arc_w, spring, 0.10))
			pts.append(_drum_pt(rings, bth + arc_w, by0, 0.10))
			_tube(bone, pts, float((tbl["ribs"] as Dictionary)["r"]), 5)
		# the amber shelf grid, storey-scaled rows inside the bay (columns across the arc)
		var cols := int(panes["cols"])
		var row_h := float(panes["row_h"])
		var rows := int((spring - by0) / row_h)
		for rw in range(rows):
			for cl in range(cols):
				var cth: float = bth + lerpf(-half_arc * 0.72, half_arc * 0.72, (float(cl) + 0.5) / float(cols))
				var cy := by0 + (float(rw) + 0.5) * row_h
				var pn := Vector3(cos(cth), 0.0, sin(cth))
				var pu := Vector3(0, 1, 0).cross(pn).normalized()
				var prad := float(Survey.lathe_local_r(rings, cy, cth)) + 0.03
				_emit_oriented_box_st(amber, pn * prad + Vector3(0, cy, 0), pu, Vector3.UP, pn,
					Vector3(half_arc * prad * 0.52 / float(cols), row_h * 0.40, 0.02))
		# the head fan: three short panes inside the arch
		for cl2 in range(3):
			var cth2: float = bth + lerpf(-half_arc * 0.45, half_arc * 0.45, (float(cl2) + 0.5) / 3.0)
			var cy2 := spring + (by1 - spring) * 0.35
			var pn2 := Vector3(cos(cth2), 0.0, sin(cth2))
			var prad2 := float(Survey.lathe_local_r(rings, cy2, cth2)) + 0.03
			_emit_oriented_box_st(amber, pn2 * prad2 + Vector3(0, cy2, 0),
				Vector3(0, 1, 0).cross(pn2).normalized(), Vector3.UP, pn2,
				Vector3(half_arc * prad2 * 0.24, (by1 - spring) * 0.24, 0.02))
		# the dome rib: continue from the bay head over the shoulder to the lantern base
		var rib_pts: Array = []
		for i2 in range(6):
			var ry := lerpf(by1 + 0.06, lantern_base, float(i2) / 5.0)
			rib_pts.append(_drum_pt(rings, bth, ry, 0.05))
		_tube(bone, rib_pts, float((tbl["ribs"] as Dictionary)["r"]), 5)
	# oval oculi between the arch heads
	for oc_v in (tbl["oculi"] as Array):
		var oc := oc_v as Array
		var oth: float = fr + float(oc[0])
		var oy := float(oc[1]) * h
		var on := Vector3(cos(oth), 0.0, sin(oth))
		_emit_torus_st(bone, on * (float(Survey.lathe_local_r(rings, oy, oth)) + 0.04) + Vector3(0, oy, 0),
			on, 0.16, 0.035, 10, 5)
	# the portal's oval cartouche (the door's idiom) — the showcase title label rides it
	var car: Dictionary = tbl["cartouche"]
	var cyc := (float(car["y0"]) + float(car["y1"])) * 0.5 * h
	var crad := float(Survey.lathe_local_r(rings, cyc, fr))
	var cno := Vector3(0, 0, 1)
	var chh := (float(car["y1"]) - float(car["y0"])) * 0.5 * h
	_emit_oriented_box_st(dark, cno * (crad + 0.06) + Vector3(0, cyc, 0), Vector3(1, 0, 0), Vector3.UP, cno,
		Vector3(float(car["w"]) * 0.5, chh, 0.025))
	for cbx in [-1.0, 1.0]:
		_emit_oriented_box_st(bone, cno * (crad + 0.07) + Vector3(float(cbx) * float(car["w"]) * 0.5, cyc, 0),
			Vector3(1, 0, 0), Vector3.UP, cno, Vector3(0.05, chh + 0.05, 0.05))
		_emit_oriented_box_st(bone, cno * (crad + 0.07) + Vector3(0, cyc + float(cbx) * chh, 0),
			Vector3(1, 0, 0), Vector3.UP, cno, Vector3(float(car["w"]) * 0.5 + 0.05, 0.05, 0.05))
	# warm sconces flanking the portal
	for sx in [-1.0, 1.0]:
		_emit_oriented_box_st(warm, cno * (crad + 0.10) + Vector3(float(sx) * 1.05, 0.115 * h, 0),
			Vector3(1, 0, 0), Vector3.UP, cno, Vector3(0.055, 0.10, 0.055))
	# the green status board on its post, left of the portal
	var st2: Dictionary = tbl["status"]
	var sth: float = fr + float(st2["az"])
	var sn := Vector3(cos(sth), 0.0, sin(sth))
	var su := Vector3(0, 1, 0).cross(sn).normalized()
	var syc := (float(st2["y0"]) + float(st2["y1"])) * 0.5 * h
	var srad := float(Survey.lathe_local_r(rings, syc, sth))
	_emit_oriented_box_st(glow, sn * (srad + 0.10) + Vector3(0, syc, 0), su, Vector3.UP, sn,
		Vector3(float(st2["w"]) * 0.5, (float(st2["y1"]) - float(st2["y0"])) * 0.5 * h, 0.03))
	_emit_oriented_box_st(bone, sn * (srad + 0.055) + Vector3(0, syc, 0), su, Vector3.UP, sn,
		Vector3(float(st2["w"]) * 0.5 + 0.05, (float(st2["y1"]) - float(st2["y0"])) * 0.5 * h + 0.05, 0.02))
	# the enforcement vestibule: arched bay, plaque, the CYAN chevron door, green keypads
	var ve: Dictionary = tbl["vestibule"]
	var vth: float = fr + float(ve["az"])
	var vn := Vector3(cos(vth), 0.0, sin(vth))
	var vu := Vector3(0, 1, 0).cross(vn).normalized()
	var vrad := float(Survey.lathe_local_r(rings, 1.0, vth))
	var vanchor := vn * vrad
	var vpts: Array = []
	for i3 in range(9):
		var t3 := float(i3) / 8.0
		var uu3 := lerpf(-1.0, 1.0, t3)
		vpts.append(vanchor + vu * (uu3 * float(ve["w"]) * 0.5)
			+ Vector3(0, maxf(0.05, float(ve["arch_apex"]) * (1.0 - uu3 * uu3)), 0) + vn * 0.08)
	_tube(bone, vpts, 0.055, 5)
	_emit_oriented_box_st(dark, vanchor + Vector3(0, float(ve["door_h"]) * 0.5, 0) + vn * 0.03,
		vu, Vector3.UP, vn, Vector3(float(ve["door_w"]) * 0.5, float(ve["door_h"]) * 0.5, 0.035))
	_emit_oriented_box_st(cyan, vanchor + Vector3(0, float(ve["door_h"]) * 0.52, 0) + vn * 0.075,
		vu, Vector3.UP, vn, Vector3(float(ve["door_w"]) * 0.30, 0.05, 0.012))
	for chs in [-1.0, 1.0]:
		var chp := vanchor + Vector3(0, float(ve["door_h"]) * 0.30, 0) + vn * 0.075 + vu * (float(chs) * float(ve["door_w"]) * 0.14)
		_emit_oriented_box_st(cyan, chp, (vu + Vector3(0, float(chs) * 0.9, 0)).normalized(), (Vector3.UP - vu * float(chs) * 0.9).normalized(), vn,
			Vector3(float(ve["door_w"]) * 0.24, 0.035, 0.012))
	_emit_oriented_box_st(dark, vanchor + Vector3(0, (float(ve["plaque_y0"]) + float(ve["plaque_y1"])) * 0.5, 0) + vn * 0.05,
		vu, Vector3.UP, vn, Vector3(float(ve["w"]) * 0.42, (float(ve["plaque_y1"]) - float(ve["plaque_y0"])) * 0.5, 0.02))
	for kp in range(3):
		_emit_oriented_box_st(glow, vanchor + vu * (float(ve["door_w"]) * 0.5 + 0.14) + Vector3(0, 0.9 + float(kp) * 0.16, 0) + vn * 0.05,
			vu, Vector3.UP, vn, Vector3(0.03, 0.03, 0.012))
	# the lantern: clerestory arch panes + the planted roof-garden ring on the 0.905H ledge
	var lan: Dictionary = tbl["lantern"]
	var lrad := float(Survey.lathe_local_r(rings, 0.94 * h, 0.0))
	for cl3 in range(int(lan["clerestory"])):
		var lth := TAU * (float(cl3) + 0.5) / float(lan["clerestory"])
		var lnv := Vector3(cos(lth), 0.0, sin(lth))
		_emit_oriented_box_st(amber, lnv * (lrad + 0.03) + Vector3(0, (float(lan["cy0"]) + float(lan["cy1"])) * 0.5 * h, 0),
			Vector3(0, 1, 0).cross(lnv).normalized(), Vector3.UP, lnv,
			Vector3(0.16, (float(lan["cy1"]) - float(lan["cy0"])) * 0.5 * h, 0.02))
	var ledge_r := float(Survey.lathe_local_r(rings, 0.906 * h, 0.0)) + 0.02
	var ring_pts := 20
	for rp in range(ring_pts):
		var a0 := TAU * float(rp) / float(ring_pts)
		var a1 := TAU * float(rp + 1) / float(ring_pts)
		_rail_strip(rails, Vector3(cos(a0) * ledge_r, lantern_base + 0.03, sin(a0) * ledge_r),
			Vector3(cos(a1) * ledge_r, lantern_base + 0.03, sin(a1) * ledge_r), float(lan["rail_h"]))
	for tf in range(int(lan["tufts"])):
		var ta := TAU * _h01(kb + float(tf) * 7.7)
		var ts := 0.09 + 0.09 * _h01(kb + float(tf) * 3.3)
		_emit_oriented_box_st(leaf, Vector3(cos(ta) * (ledge_r - 0.12), lantern_base + 0.06 + ts, sin(ta) * (ledge_r - 0.12)),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(ts, ts, ts))
	# planting beds at the front corners
	for bd_v in ((tbl["beds"] as Dictionary)["azs"] as Array):
		var bth2: float = fr + float(bd_v)
		var bn := Vector3(cos(bth2), 0.0, sin(bth2))
		var bu := Vector3(0, 1, 0).cross(bn).normalized()
		var brad := float(Survey.lathe_local_r(rings, 0.2, bth2))
		var bc := bn * (brad + 0.35)
		_emit_oriented_box_st(bone, bc + Vector3(0, 0.12, 0), bu, Vector3.UP, bn,
			Vector3(float((tbl["beds"] as Dictionary)["w"]) * 0.5, 0.12, 0.30))
		for tf2 in range(3):
			var toff := lerpf(-0.3, 0.3, float(tf2) / 2.0)
			var ts2 := 0.10 + 0.08 * _h01(kb + float(tf2) * 5.1 + float(bd_v))
			_emit_oriented_box_st(leaf, bc + bu * toff + Vector3(0, 0.24 + ts2, 0),
				Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(ts2, ts2, ts2))
	for stool in [bone, dark, amber, glow, cyan, warm, leaf, rails]:
		(stool as SurfaceTool).generate_normals()
	return {"bone": bone.commit(), "dark": dark.commit(), "amber": amber.commit(),
		"glow": glow.commit(), "cyan": cyan.commit(), "warm": warm.commit(),
		"leaf": leaf.commit(), "rails": rails.commit(),
		"nameplate_pos": cno * (crad + 0.30) + Vector3(0, cyc, 0)}

# a point riding the surveyed drum wall at (theta, y), standing `off` proud
static func _drum_pt(rings: Array, theta: float, y: float, off: float) -> Vector3:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var rad := float(Survey.lathe_local_r(rings, y, theta)) + off
	return Vector3(cos(theta) * rad, y, sin(theta) * rad)

## Hypelines detail passes (SURVEY REBUILD 1.2), every part grown from the survey's frames: the six
## pipe ARMS (the walkable LANE pair carries a flat deck at the level-1 datum with kerbs + railing
## bands; the pitched viaduct pairs carry thin catwalk strips), A-frame trestles, the signature
## valve wheel, the teal-backlit sign + IRON HEART ghost letters, the parabolic toll-gate arch with
## its board and the two warm lamps (the plate's only warm accents), the railed approach ramp,
## glowing membrane pores, the dome vent slit, and the antenna mast with its green lights.
## Material families: body / rust / dark / glow (terminal green) / warm (the two lamps) / rails.
static func hypelines_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var sv = Survey.from_spec(spec)
	var rings: Array = Survey.hypelines_rings(spec)
	var h := float(spec.get("height", 6.2))
	var hy: Dictionary = Survey.table_for(spec, "hypelines")
	var body := _st()
	var rust := _st()
	var dark := _st()
	var glow := _st()
	var warm := _st()
	var rails := _st()
	var deck: Dictionary = hy["deck"]
	for a in Survey.hypelines_arm_table(spec):
		_hypelines_arm(body, rails, a as Dictionary, deck)
	# the signature valve wheel, proud of the dome face
	var wh: Dictionary = hy["wheel"]
	var wth: float = PI * 0.5 + float(wh["az"])
	var wy := float(wh["y"]) * h
	var wdia := float(wh["dia"]) * h
	var wn := Vector3(cos(wth), 0.0, sin(wth))
	var wc := wn * (float(Survey.lathe_local_r(rings, wy, wth)) + wdia * 0.16) + Vector3(0, wy, 0)
	_emit_torus_st(rust, wc, wn, wdia * 0.43, wdia * 0.07, 14, 6)
	var wbasis := Basis(Quaternion(Vector3.UP, wn))
	for k in range(6):
		var ang := TAU * float(k) / 6.0
		var spoke := (wbasis * Vector3(cos(ang), 0.0, sin(ang))).normalized()
		_tube(rust, [wc - spoke * wdia * 0.4, wc + spoke * wdia * 0.4], wdia * 0.045, 4)
	_tube(rust, [wc - wn * wdia * 0.12, wc + wn * wdia * 0.10], wdia * 0.10, 6)
	# the sign stack: teal-backlit board + rusted frame, ghost letters, toll board in the arch
	var fr := PI * 0.5
	var n_f := Vector3(0, 0, 1)
	var u_f := Vector3(1, 0, 0)
	var sgn: Dictionary = hy["sign"]
	var sr := float(Survey.lathe_local_r(rings, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h, fr))
	var sc := n_f * (sr + 0.12) + Vector3(0, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h, 0)
	var shh := (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 * h
	_emit_oriented_box_st(glow, sc, u_f, Vector3.UP, n_f, Vector3(float(sgn["w"]) * 0.5, shh, 0.03))
	for sx in [-1.0, 1.0]:
		_emit_oriented_box_st(rust, sc + u_f * (float(sgn["w"]) * 0.5 * sx) + n_f * 0.01, u_f, Vector3.UP, n_f, Vector3(0.05, shh + 0.05, 0.05))
		_emit_oriented_box_st(rust, sc + Vector3(0, shh * sx, 0) + n_f * 0.01, u_f, Vector3.UP, n_f, Vector3(float(sgn["w"]) * 0.5 + 0.05, 0.05, 0.05))
	var gho: Dictionary = hy["ghost"]
	if float(gho["w"]) > 0.05:
		var gr := float(Survey.lathe_local_r(rings, (float(gho["y0"]) + float(gho["y1"])) * 0.5 * h, fr))
		_emit_oriented_box_st(dark, n_f * (gr + 0.03) + Vector3(0, (float(gho["y0"]) + float(gho["y1"])) * 0.5 * h, 0),
			u_f, Vector3.UP, n_f, Vector3(float(gho["w"]) * 0.5, (float(gho["y1"]) - float(gho["y0"])) * 0.5 * h, 0.015))
	var toll: Dictionary = hy["toll"]
	var wall_r := float(spec.get("door_radius", 1.53))
	_emit_oriented_box_st(glow, n_f * (wall_r + 0.10) + Vector3(0, (float(toll["y0"]) + float(toll["y1"])) * 0.5 * h, 0),
		u_f, Vector3.UP, n_f, Vector3(float(toll["w"]) * 0.5, (float(toll["y1"]) - float(toll["y0"])) * 0.5 * h, 0.025))
	# the lit terminal in the arch recess (proud of the door leaves so it reads from outside)
	_emit_oriented_box_st(glow, n_f * (wall_r - 0.18) + Vector3(0, 0.95, 0),
		u_f, Vector3.UP, n_f, Vector3(0.24, 0.32, 0.015))
	# the parabolic entry arch rim + the two warm lamps + the railed approach ramp
	var arch: Dictionary = hy["arch"]
	var arch_pts: Array = []
	for i in range(11):
		var t := float(i) / 10.0
		var uu := lerpf(-1.0, 1.0, t)
		arch_pts.append(n_f * (wall_r + 0.10) + u_f * (uu * float(arch["w"]) * 0.5)
			+ Vector3(0, maxf(0.05, float(arch["y_top"]) * h * (1.0 - uu * uu)), 0))
	_tube(body, arch_pts, float(arch["r_tube"]), 6)
	for lx in [-1.0, 1.0]:
		_emit_oriented_box_st(warm, n_f * (wall_r + 0.14) + u_f * (lx * (float(arch["w"]) * 0.5 + 0.10)) + Vector3(0, 1.35, 0),
			u_f, Vector3.UP, n_f, Vector3(0.06, 0.09, 0.06))
	var ramp: Dictionary = hy["ramp"]
	var rlen := float(ramp["len"])
	var rw := float(ramp["w"])
	_emit_oriented_box_st(body, n_f * (wall_r + rlen * 0.5) + Vector3(0, 0.045, 0), u_f, Vector3.UP, n_f,
		Vector3(rw * 0.5, 0.045, rlen * 0.5))
	for rx in [-1.0, 1.0]:
		_rail_strip(rails, n_f * (wall_r + 0.1) + u_f * (rx * rw * 0.5) + Vector3(0, 0.09, 0),
			n_f * (wall_r + rlen) + u_f * (rx * rw * 0.5) + Vector3(0, 0.09, 0), 0.30)
	# glowing membrane pores + the dark dome vent, riding the surveyed skin
	for p_v in (hy["pores"] as Array):
		var p := p_v as Array
		var pth: float = fr + float(p[0])
		_surface_panel(glow, {"theta": pth, "y0": float(p[1]) * h, "y1": float(p[2]) * h,
			"w": float(p[3]) * h, "r0": float(Survey.lathe_local_r(rings, float(p[1]) * h, pth)),
			"r1": float(Survey.lathe_local_r(rings, float(p[2]) * h, pth))})
	var vent: Dictionary = hy["vent"]
	var vth: float = fr + float(vent["az"])
	_surface_panel(dark, {"theta": vth, "y0": float(vent["y0"]) * h, "y1": float(vent["y1"]) * h,
		"w": float(vent["w"]) * h, "r0": float(Survey.lathe_local_r(rings, float(vent["y0"]) * h, vth)),
		"r1": float(Survey.lathe_local_r(rings, float(vent["y1"]) * h, vth))})
	# the antenna mast + its tiny green lights
	var mast: Dictionary = hy["mast"]
	_tube(body, [Vector3(0, 0.985 * h, 0), Vector3(0, float(mast["y_top"]) * h, 0)], float(mast["r"]) * h + 0.02, 5)
	for li in range(int(mast["lights"])):
		var ly := lerpf(1.0, float(mast["y_top"]) - 0.005, (float(li) + 0.6) / float(mast["lights"])) * h
		_emit_oriented_box_st(glow, Vector3(0.05, ly, 0), u_f, Vector3.UP, n_f, Vector3(0.03, 0.03, 0.03))
	for stool in [body, rust, dark, glow, warm, rails]:
		(stool as SurfaceTool).generate_normals()
	var nameplate := n_f * (sr + 0.42) + Vector3(0, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5 * h, 0)
	return {"body": body.commit(), "rust": rust.commit(), "dark": dark.commit(),
		"glow": glow.commit(), "warm": warm.commit(), "rails": rails.commit(),
		"nameplate_pos": nameplate, "height": h}

# One hypelines arm: the pipe tube with root + tip collars, its trestle, and the catwalk — the LANE
# pair gets the full deck at the level datum (kerbs + rail bands), viaducts a thin top strip.
static func _hypelines_arm(body: SurfaceTool, rails: SurfaceTool, ad: Dictionary, deck: Dictionary) -> void:
	var base := ad["base"] as Vector3
	var tip := ad["tip"] as Vector3
	var dirv := ad["dir"] as Vector3
	var pr := float(ad["pipe_r"])
	_tube(body, [base, tip], pr, 8)
	_emit_torus_st(body, base + dirv * 1.35, dirv, pr * 1.1, pr * 0.15, 10, 5)
	_emit_torus_st(body, tip - dirv * 0.18, dirv, pr * 1.05, pr * 0.13, 10, 5)
	var side := dirv.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	if bool(ad["lane"]):
		var a := ad["walk_base"] as Vector3
		var b := ad["walk_tip"] as Vector3
		var w := float(deck["deck_w"])
		var t := float(deck["deck_t"])
		var fwd := (b - a).normalized()
		var mid := (a + b) * 0.5
		var half_len := a.distance_to(b) * 0.5
		_emit_oriented_box_st(body, mid - Vector3(0, t * 0.5, 0), side, Vector3.UP, fwd,
			Vector3(w * 0.5, t * 0.5, half_len))
		for s in [-1.0, 1.0]:
			_emit_oriented_box_st(body, mid + side * (w * 0.5 * s) + Vector3(0, 0.035, 0), side, Vector3.UP, fwd,
				Vector3(0.045, 0.055, half_len))
			_rail_strip(rails, a + side * (w * 0.5 * s) + Vector3(0, 0.07, 0),
				b + side * (w * 0.5 * s) + Vector3(0, 0.07, 0), float(deck["rail_h"]))
	else:
		# the viaduct catwalk: a thin strip riding the pipe top with low rails
		var a2 := base + dirv * 1.3 + Vector3(0, pr + 0.03, 0)
		var b2 := tip - dirv * 0.1 + Vector3(0, pr + 0.03, 0)
		var fwd2 := (b2 - a2).normalized()
		_emit_oriented_box_st(body, (a2 + b2) * 0.5 - Vector3(0, 0.03, 0), side, Vector3.UP, fwd2,
			Vector3(0.20, 0.03, a2.distance_to(b2) * 0.5))
		for s2 in [-1.0, 1.0]:
			_rail_strip(rails, a2 + side * (0.20 * s2), b2 + side * (0.20 * s2), 0.22)
	# the openwork A-frame trestle at ~62% of the run (legs splay to feet, one horizontal tie)
	var tp := (base + dirv * (1.1 + float(ad["len"]) * 0.62))
	if tp.y > 1.2:
		for s3 in [-1.0, 1.0]:
			var foot: Vector3 = Vector3(tp.x, 0.0, tp.z) + side * (float(s3) * 0.95)
			_tube(body, [tp - Vector3(0, pr * 0.4, 0), foot], 0.10, 5)
		var tie_y := tp.y * 0.42
		var tie_off := 0.95 * (1.0 - tie_y / maxf(0.1, tp.y))
		_tube(body, [Vector3(tp.x, tie_y, tp.z) - side * tie_off,
			Vector3(tp.x, tie_y, tp.z) + side * tie_off], 0.06, 4)

# A UV-tiled railing band between two points (the alpha-scissor railing texture reads as balusters;
# the material is cull-disabled, so one quad serves both sides).
static func _rail_strip(rails: SurfaceTool, a: Vector3, b: Vector3, height: float) -> void:
	var u1 := a.distance_to(b) / 0.42
	rails.set_uv(Vector2(0.0, 1.0)); rails.add_vertex(a)
	rails.set_uv(Vector2(u1, 1.0)); rails.add_vertex(b)
	rails.set_uv(Vector2(u1, 0.0)); rails.add_vertex(b + Vector3(0, height, 0))
	rails.set_uv(Vector2(0.0, 1.0)); rails.add_vertex(a)
	rails.set_uv(Vector2(u1, 0.0)); rails.add_vertex(b + Vector3(0, height, 0))
	rails.set_uv(Vector2(0.0, 0.0)); rails.add_vertex(a + Vector3(0, height, 0))

## Greenfields (SURVEY REBUILD 1.4): the massing is the verdigris WALL box alone — the bone
## structure (wavy slab rings, railings, arcade, window niches, ribs, roof terrace) is the
## balconies pass, greenfields_details, so the plate's two-tone read is real, not one material.
static func _greenfields_stack_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	return _box_with_doors(spec.get("size", Vector3(5.2, 6.4, 5.0)), reserved, recess)

## The greenfields BALCONIES pass (the lattice the spec declared for months with no generator):
## every part rides the survey's storey datums — four wavy bone slab rings (ONE wave function:
## 4 crests per facade, crests on the bay centres), railings along every wavy rim, greenery tufts
## (densest at the corner), the ground arcade (bone arches + dark-green leaves + warm sconces),
## three floors of arched amber windows in bone niches, tendon ribs between bays, the roof terrace
## (shrubs + teal-cyan buds — the plate's accent light), and the sign board over the arcade.
## Families: bone / door (dark green) / amber (windows) / teal (roof buds) / leaf / warm / rails.
static func greenfields_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var g: Dictionary = Survey.table_for(spec, "greenfields")
	var size: Vector3 = spec.get("size", Vector3(5.2, 6.4, 5.0))
	var bone := _st()
	var door := _st()
	var amber := _st()
	var teal := _st()
	var leaf := _st()
	var warm := _st()
	var rails := _st()
	var ground := 1.7
	var floors := int(spec.get("storey_floors", 3))
	var storey := (size.y - ground) / float(floors)
	var slab: Dictionary = g["slab"]
	var kb := float(str(spec.get("kind", "greenfields")).hash() % 1000)
	for k in range(floors + 1):
		var y := minf(ground + storey * float(k), size.y - 0.09)
		var rim := _slab_sweep(bone, Vector3(size.x * 0.5, 0, size.z * 0.5), y,
			float(slab["t"]), float(slab["overhang"]), float(slab["wave"]), int(slab["crests"]))
		# railings along the wavy rim + greenery tufts (densest at the corner bays)
		for i in range(rim.size()):
			var a := rim[i] as Vector3
			var b := rim[(i + 1) % rim.size()] as Vector3
			_rail_strip(rails, Vector3(a.x, y + float(slab["t"]) * 0.5, a.z),
				Vector3(b.x, y + float(slab["t"]) * 0.5, b.z), float(g["rail_h"]))
			if _h01(kb + float(k) * 31.0 + float(i) * 7.7) > 0.62:
				var tuft := (a + b) * 0.5
				var ts := 0.10 + 0.10 * _h01(kb + float(i) * 3.3)
				_emit_oriented_box_st(leaf, Vector3(tuft.x, y + float(slab["t"]) * 0.5 + ts, tuft.z) - (Vector3(tuft.x, 0, tuft.z).normalized() * 0.18),
					Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(ts, ts, ts))
	# the ground ARCADE: bone arches, recessed dark-green leaves, warm sconces on the piers
	var arc: Dictionary = g["arcade"]
	for f in _wall_frames(size):
		var fd := f as Dictionary
		var n: Vector3 = fd["n"]
		var u: Vector3 = fd["u"]
		var hw := float(fd["w"]) * 0.5
		var bays := int(arc["bays"])
		for b2 in range(bays):
			var cx := lerpf(-hw + 0.75, hw - 0.75, float(b2) / float(bays - 1))
			var anchor := (fd["c"] as Vector3) + u * cx + n * 0.05
			_arch_frame(bone, anchor, u, n, float(arc["arch_w"]), float(arc["spring"]), float(arc["apex"]))
			_emit_oriented_box_st(door, anchor + Vector3(0, float(arc["spring"]) * 0.55, 0) - n * 0.02,
				u, Vector3.UP, n, Vector3(float(arc["arch_w"]) * 0.42, float(arc["spring"]) * 0.55, 0.04))
			if b2 < bays - 1:
				var px := lerpf(-hw + 0.75, hw - 0.75, (float(b2) + 0.5) / float(bays - 1))
				if absf(px) > 0.95:   # the centre pier slot holds the REAL door — no sconce in it
					_emit_oriented_box_st(warm, (fd["c"] as Vector3) + u * px + n * 0.10 + Vector3(0, float(arc["sconce_y"]), 0),
						u, Vector3.UP, n, Vector3(0.045, 0.10, 0.045))
		# the MAIN door (front face, centre slot) gets its own arch — the arcade IS its surround
		# (main_surround=false suppresses the generic stone that used to spear the bay arches)
		if (n as Vector3).dot(Vector3(0, 0, 1)) > 0.9:
			_arch_frame(bone, (fd["c"] as Vector3) + n * 0.05, u, n, 1.32, 0.95, 1.50)
	# three floors of arched amber windows in bone niches + tendon ribs between the bays
	var win: Dictionary = g["window"]
	var ribs: Dictionary = g["ribs"]
	for f2 in _wall_frames(size):
		var fd2 := f2 as Dictionary
		var n2: Vector3 = fd2["n"]
		var u2: Vector3 = fd2["u"]
		var hw2 := float(fd2["w"]) * 0.5
		for fl in range(floors):
			var base := ground + storey * float(fl)
			var wy0 := storey * float(win["band_y0"])
			var wy1 := storey * float(win["band_y1"])
			for b3 in range(int(win["per_face"])):
				var wx := lerpf(-hw2 + 0.75, hw2 - 0.75, float(b3) / float(int(win["per_face"]) - 1))
				var wc := (fd2["c"] as Vector3) + u2 * wx + Vector3(0, base + (wy0 + wy1) * 0.5, 0) + n2 * 0.03
				var whh := (wy1 - wy0) * 0.5
				_emit_oriented_box_st(bone, wc, u2, Vector3.UP, n2,
					Vector3(float(win["w"]) * 0.5 + float(win["frame"]), whh + float(win["frame"]), 0.05))
				_emit_oriented_box_st(amber, wc + n2 * 0.03, u2, Vector3.UP, n2,
					Vector3(float(win["w"]) * 0.5, whh, 0.03))
		for rb in range(int(win["per_face"]) - 1):
			var rx := lerpf(-hw2 + 0.75, hw2 - 0.75, (float(rb) + 0.5) / float(int(win["per_face"]) - 1))
			var rp0 := (fd2["c"] as Vector3) + u2 * rx + Vector3(0, ground + 0.1, 0) + n2 * 0.05
			_tube(bone, [rp0, rp0 + Vector3(0, size.y - ground - 0.3, 0)], float(ribs["r"]), 4)
	# the roof terrace: shrubs + the teal-cyan glowing buds (the plate's accent light)
	var roof: Dictionary = g["roof"]
	for sh in range(int(roof["shrubs"])):
		var sx3 := (_h01(kb + 50.0 + float(sh) * 7.1) - 0.5) * (size.x - 1.2)
		var sz3 := (_h01(kb + 60.0 + float(sh) * 11.3) - 0.5) * (size.z - 1.2)
		var shh2 := float(roof["shrub_h"]) * (0.55 + 0.45 * _h01(kb + float(sh) * 3.7)) * 0.5
		_emit_oriented_box_st(leaf, Vector3(sx3, size.y + shh2, sz3), Vector3.RIGHT, Vector3.UP, Vector3.BACK,
			Vector3(shh2 * 0.8, shh2, shh2 * 0.8))
	for bd in range(int(roof["buds"])):
		var bx3 := (_h01(kb + 80.0 + float(bd) * 9.7) - 0.5) * (size.x - 1.4)
		var bz3 := (_h01(kb + 90.0 + float(bd) * 5.3) - 0.5) * (size.z - 1.4)
		_emit_oriented_box_st(teal, Vector3(bx3, size.y + 0.45 + 0.5 * _h01(kb + float(bd) * 2.1), bz3),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.05, 0.05, 0.05))
	# the sign board riding the first slab band, front facade
	var sgn: Dictionary = g["sign"]
	var sc := Vector3(0, (float(sgn["y0"]) + float(sgn["y1"])) * 0.5, size.z * 0.5 + float(slab["overhang"]) + 0.05)
	_emit_oriented_box_st(door, sc, Vector3.RIGHT, Vector3.UP, Vector3.BACK,
		Vector3(float(sgn["w"]) * 0.5, (float(sgn["y1"]) - float(sgn["y0"])) * 0.5, 0.035))
	for bx4 in [-1.0, 1.0]:
		_emit_oriented_box_st(bone, sc + Vector3(float(sgn["w"]) * 0.5 * float(bx4), 0, 0.01),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.05, (float(sgn["y1"]) - float(sgn["y0"])) * 0.5 + 0.05, 0.05))
	for stool in [bone, door, amber, teal, leaf, warm, rails]:
		(stool as SurfaceTool).generate_normals()
	return {"bone": bone.commit(), "door": door.commit(), "amber": amber.commit(),
		"teal": teal.commit(), "leaf": leaf.commit(), "warm": warm.commit(), "rails": rails.commit(),
		"nameplate_pos": sc + Vector3(0, 0, 0.25)}

# the four vertical wall frames of a box (centre at ground level, in-plane u, outward n, width)
static func _wall_frames(size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	return [
		{"c": Vector3(0, 0, hz), "u": Vector3(1, 0, 0), "n": Vector3(0, 0, 1), "w": size.x},
		{"c": Vector3(0, 0, -hz), "u": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "w": size.x},
		{"c": Vector3(hx, 0, 0), "u": Vector3(0, 0, -1), "n": Vector3(1, 0, 0), "w": size.z},
		{"c": Vector3(-hx, 0, 0), "u": Vector3(0, 0, 1), "n": Vector3(-1, 0, 0), "w": size.z},
	]

# a bone arch: straight jambs + a semicircular head swept as one tube
static func _arch_frame(st: SurfaceTool, anchor: Vector3, u: Vector3, n: Vector3, w: float,
		spring: float, apex: float) -> void:
	var pts: Array = []
	pts.append(anchor - u * (w * 0.5))
	pts.append(anchor - u * (w * 0.5) + Vector3(0, spring, 0))
	var rise := apex - spring
	for i in range(1, 6):
		var a := PI - PI * float(i) / 6.0
		pts.append(anchor + u * (cos(a) * w * 0.5) + Vector3(0, spring + sin(a) * rise, 0))
	pts.append(anchor + u * (w * 0.5) + Vector3(0, spring, 0))
	pts.append(anchor + u * (w * 0.5))
	_tube(st, pts, 0.055, 4)

# one wavy slab ring: the box wears an overhanging band at `y_c` whose outer rim waves in plan
# (crests on the bay centres). Emits rim band + top/bottom annulus strips; returns the OUTER rim
# points at the slab's mid-height so railings and tufts can follow the same wave (one authority).
static func _slab_sweep(st: SurfaceTool, half: Vector3, y_c: float, t: float, overhang: float,
		wave: float, crests: int) -> Array:
	var per_edge := 10
	var outer: Array = []
	var inner: Array = []
	var corners := [Vector2(half.x, half.z), Vector2(-half.x, half.z),
		Vector2(-half.x, -half.z), Vector2(half.x, -half.z)]
	for e in range(4):
		var a := corners[e] as Vector2
		var b := corners[(e + 1) % 4] as Vector2
		for s in range(per_edge):
			var tt := float(s) / float(per_edge)
			var p := a.lerp(b, tt)
			var out2 := (p / Vector2(half.x, half.z)).normalized()
			var wv := absf(sin(tt * PI * float(crests))) * wave   # one crest per bay, corners quiet
			var pp := p + out2 * (overhang + wv)
			outer.append(Vector3(pp.x, y_c, pp.y))
			inner.append(Vector3(p.x * 0.985, y_c, p.y * 0.985))
	var n := outer.size()
	for i in range(n):
		var j := (i + 1) % n
		var o0 := outer[i] as Vector3
		var o1 := outer[j] as Vector3
		var i0 := inner[i] as Vector3
		var i1 := inner[j] as Vector3
		var up := Vector3(0, t * 0.5, 0)
		_quad_out(st, o0 - up, o1 - up, o1 + up, o0 + up, Vector3(0, y_c, 0))          # rim band
		_quad_out(st, i0 + up, i1 + up, o1 + up, o0 + up, Vector3(0, y_c - 3.0, 0))    # top
		_quad_out(st, i0 - up, i1 - up, o1 - up, o0 - up, Vector3(0, y_c + 3.0, 0))    # bottom
	return outer

## Bulwark Wharf (REVIEW P1): the gatehouse earns its two round corner towers — half-embedded at the
## front corners, rising past the roofline, domed caps + ring collars.
static func _bulwark_towers_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	# SURVEY REBUILD 1.7: the gatehouse box to the eave + FOUR corner towers GROWN from the box's
	# own corner construction points — each tower is ONE loft over BULWARK.tower.rings (splay foot /
	# banded shaft / turret bulge / cap cone), so a tower can never drift off its corner.
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "bulwark")
	var size: Vector3 = spec.get("size", Vector3(4.6, 5.2, 3.4))
	var h := size.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_box_with_doors(Vector3(size.x, h * 0.86, size.z), reserved, recess), 0, Transform3D.IDENTITY)
	# the towers loft in their OWN stool: generate_normals is only safe on raw emits, and st has
	# already appended the box (the generate-after-append trap drops appended surfaces)
	var tw := SurfaceTool.new()
	tw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = (tbl["tower"] as Dictionary)["rings"]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(float(sx) * size.x * 0.5, 0.0, float(sz) * size.z * 0.5)
			_rings_loft(tw, base, h, rings, 12)
	tw.generate_normals()
	st.append_from(tw.commit(), 0, Transform3D.IDENTITY)
	return st.commit()

# a lathe loft over survey rings [[y_frac, r_frac], ...] x height, seated at `base`, top capped
static func _rings_loft(st: SurfaceTool, base: Vector3, h: float, rings: Array, seg: int) -> void:
	for i in range(rings.size() - 1):
		var r0 := rings[i] as Array
		var r1 := rings[i + 1] as Array
		var y0 := float(r0[0]) * h
		var y1 := float(r1[0]) * h
		var ra := float(r0[1]) * h
		var rb := float(r1[1]) * h
		for k in range(seg):
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var p00 := base + Vector3(cos(a0) * ra, y0, sin(a0) * ra)
			var p01 := base + Vector3(cos(a1) * ra, y0, sin(a1) * ra)
			var p10 := base + Vector3(cos(a0) * rb, y1, sin(a0) * rb)
			var p11 := base + Vector3(cos(a1) * rb, y1, sin(a1) * rb)
			_quad_out(st, p00, p01, p11, p10, base + Vector3(0, (y0 + y1) * 0.5, 0))
	var top := rings[rings.size() - 1] as Array
	var ty := float(top[0]) * h
	var tr := float(top[1]) * h
	var apex := base + Vector3(0, ty, 0)
	for k2 in range(seg):
		var a0b := TAU * float(k2) / float(seg)
		var a1b := TAU * float(k2 + 1) / float(seg)
		st.add_vertex(apex)
		st.add_vertex(base + Vector3(cos(a1b) * tr, ty, sin(a1b) * tr))
		st.add_vertex(base + Vector3(cos(a0b) * tr, ty, sin(a0b) * tr))

## Zone-3 (SURVEY REBUILD 1.8): split massing from the ZONE3 plan datums — the intact MAIN block
## (its door cut in the sub-box frame, shifted back into place), the heavy cornice slab over the
## main block only, and the GUTTED wing: rear + outer walls, the torn floor slabs, a roof cap and
## the front corner post. The torn front stays OPEN — the cavity galleries are the plate's read.
static func _zone3_split_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "zone3")
	var size: Vector3 = spec.get("size", Vector3(4.0, 5.4, 3.6))
	var h := size.y
	var hz := size.z * 0.5
	var main_x0 := float(tbl["main_x0"]) * h
	var main_x1 := float(tbl["main_x1"]) * h
	var wing_x1 := float(tbl["wing_x1"]) * h
	var main_cx := (main_x0 + main_x1) * 0.5
	var cor_y := float(tbl["cornice_y"]) * h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the main block: door regions shift into the sub-box's local frame; the transform shifts back
	var local_reserved: Array = []
	for r_v in reserved:
		var r := (r_v as Dictionary).duplicate(true)
		if absf((r.get("n", Vector3.ZERO) as Vector3).z) > 0.5:
			r["x_center"] = float(r.get("x_center", 0.0)) - main_cx
		local_reserved.append(r)
	st.append_from(_box_with_doors(Vector3(main_x1 - main_x0, cor_y, size.z), local_reserved, recess),
		0, Transform3D(Basis(), Vector3(main_cx, 0.0, 0.0)))
	var raw := SurfaceTool.new()
	raw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_over := float(tbl["cornice_over"]) * h
	_emit_oriented_box_st(raw, Vector3(main_cx, (cor_y + h) * 0.5, 0.0),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1),
		Vector3((main_x1 - main_x0) * 0.5 + c_over, (h - cor_y) * 0.5, hz + c_over))
	# the gutted wing: rear wall, outer side wall, torn floor slabs, roof cap, front corner post
	var wall_t := 0.14
	var wcx := (main_x1 + wing_x1) * 0.5
	var wing_hw := (wing_x1 - main_x1) * 0.5
	_emit_oriented_box_st(raw, Vector3(wcx, cor_y * 0.5, -hz + wall_t * 0.5),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(wing_hw, cor_y * 0.5, wall_t * 0.5))
	_emit_oriented_box_st(raw, Vector3(wing_x1 - wall_t * 0.5, cor_y * 0.5, 0.0),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(wall_t * 0.5, cor_y * 0.5, hz))
	var slab_t := float(tbl["slab_t"]) * h
	for sy_v in (tbl["slabs"] as Array):
		_emit_oriented_box_st(raw, Vector3(wcx, float(sy_v) * h, 0.0),
			Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(wing_hw, slab_t * 0.5, hz - 0.02))
	_emit_oriented_box_st(raw, Vector3(wcx, cor_y - slab_t * 0.5, 0.0),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(wing_hw, slab_t * 0.5, hz))
	_emit_oriented_box_st(raw, Vector3(wing_x1 - 0.10, cor_y * 0.5, hz - 0.10),
		Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), Vector3(0.10, cor_y * 0.5, 0.10))
	raw.generate_normals()
	st.append_from(raw.commit(), 0, Transform3D.IDENTITY)
	return st.commit()

## Loca's Watchtower (the Act 1 boss landmark, GDD 11.1): the vertical plinth band takes the real
## door cut, then the three battered masonry tiers rise as ONE box loft over the LOCAS tier rows
## (double rows at a shared y = a setback ledge), capped by the cage floor. The observation CAGE's
## four corner posts are part of the massing (they carry the envelope to the crown); rails, bars,
## the core and the tangles are watchtower_details.
static func _watchtower_mesh(spec: Dictionary, reserved: Array, recess: float) -> ArrayMesh:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "locas")
	var size: Vector3 = spec.get("size", Vector3(6.4, 13.0, 6.4))
	var h := size.y
	var band := float(tbl["door_band"]) * h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_box_with_doors(Vector3(size.x, band, size.z), reserved, recess), 0, Transform3D.IDENTITY)
	# the tier loft + cage posts emit raw in their OWN stool (generate-after-append drops surfaces)
	var raw := SurfaceTool.new()
	raw.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_loft(raw, tbl["tiers"] as Array, h, size.x * 0.5, size.z * 0.5)
	var cage_f := float(((tbl["tiers"] as Array)[-1] as Array)[1])
	var post_r := float((tbl["cage"] as Dictionary)["post_r"]) * h
	var cage_y0 := float(((tbl["tiers"] as Array)[-1] as Array)[0]) * h
	var cage_y1 := float((tbl["cage"] as Dictionary)["y1"]) * h
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx := float(sx) * (size.x * 0.5 * cage_f - post_r)
			var cz := float(sz) * (size.z * 0.5 * cage_f - post_r)
			_emit_box_st(raw, Vector3(cx, (cage_y0 + cage_y1) * 0.5, cz),
				Vector3(post_r, (cage_y1 - cage_y0) * 0.5, post_r))
	raw.generate_normals()
	st.append_from(raw.commit(), 0, Transform3D.IDENTITY)
	return st.commit()

## A battered BOX loft over rows [[y_frac, half_frac], ...] x (h, hx, hz): walls between rows that
## span height, flat setback LEDGE rings between rows that share a y, a top cap on the last row.
static func _box_loft(st: SurfaceTool, rows: Array, h: float, hx: float, hz: float) -> void:
	for i in range(rows.size() - 1):
		var a := rows[i] as Array
		var b := rows[i + 1] as Array
		var y0 := float(a[0]) * h
		var y1 := float(b[0]) * h
		var fa := float(a[1])
		var fb := float(b[1])
		var c := Vector3(0, (y0 + y1) * 0.5, 0)
		if absf(y1 - y0) < 0.0001:
			# a setback ledge: an upward ring from the outer rect to the inner rect
			var oxl := hx * fa
			var ozl := hz * fa
			var ixl := hx * fb
			var izl := hz * fb
			var cl := Vector3(0, y0 - 1.0, 0)
			_quad_out(st, Vector3(-oxl, y0, ozl), Vector3(oxl, y0, ozl), Vector3(ixl, y0, izl), Vector3(-ixl, y0, izl), cl)
			_quad_out(st, Vector3(oxl, y0, -ozl), Vector3(-oxl, y0, -ozl), Vector3(-ixl, y0, -izl), Vector3(ixl, y0, -izl), cl)
			_quad_out(st, Vector3(oxl, y0, ozl), Vector3(oxl, y0, -ozl), Vector3(ixl, y0, -izl), Vector3(ixl, y0, izl), cl)
			_quad_out(st, Vector3(-oxl, y0, -ozl), Vector3(-oxl, y0, ozl), Vector3(-ixl, y0, izl), Vector3(-ixl, y0, -izl), cl)
			continue
		var x0 := hx * fa
		var z0 := hz * fa
		var x1 := hx * fb
		var z1 := hz * fb
		_quad_out(st, Vector3(-x0, y0, z0), Vector3(x0, y0, z0), Vector3(x1, y1, z1), Vector3(-x1, y1, z1), c)
		_quad_out(st, Vector3(x0, y0, -z0), Vector3(-x0, y0, -z0), Vector3(-x1, y1, -z1), Vector3(x1, y1, -z1), c)
		_quad_out(st, Vector3(x0, y0, z0), Vector3(x0, y0, -z0), Vector3(x1, y1, -z1), Vector3(x1, y1, z1), c)
		_quad_out(st, Vector3(-x0, y0, -z0), Vector3(-x0, y0, z0), Vector3(-x1, y1, z1), Vector3(-x1, y1, -z1), c)
	var top := rows[rows.size() - 1] as Array
	var ty := float(top[0]) * h
	var tf := float(top[1])
	var txc := hx * tf
	var tzc := hz * tf
	var ct := Vector3(0, ty - 1.0, 0)
	_quad_out(st, Vector3(-txc, ty, tzc), Vector3(txc, ty, tzc), Vector3(txc, ty, -tzc), Vector3(-txc, ty, -tzc), ct)

## The wall half-extent FRACTION at y_frac, read off the same tier rows the loft builds from (the
## vertical door band below the first row answers the full wall).
static func _locas_half_frac(rows: Array, y_frac: float) -> float:
	var first := rows[0] as Array
	if y_frac <= float(first[0]):
		return 1.0
	for i in range(rows.size() - 1):
		var a := rows[i] as Array
		var b := rows[i + 1] as Array
		var ya := float(a[0])
		var yb := float(b[0])
		if y_frac <= yb:
			if yb - ya < 0.0001:
				continue
			return lerpf(float(a[1]), float(b[1]), (y_frac - ya) / (yb - ya))
	return float((rows[rows.size() - 1] as Array)[1])

## Loca's Watchtower detail passes, every part from the LOCAS survey frames: the cool-blue window
## recess banks per tier, the tier-top edge light strips, the LOCA'S WATCHTOWER plaque, corner
## buttresses + tier-3 turrets, the observation cage's rails + bars, the beacon spires (cyan tips),
## the entry's heavy lintel + blue transom — and Loca's bound chamber: the fever-red CORE with the
## red-brown containment TANGLES spilling from the cage down the rear + flank walls.
## Families: stone / dark / blue (cool institutional light) / tips (beacon gems) / rust (tangles) /
## core (the red heart). Plus "nameplate_pos" (ON the plaque).
static func watchtower_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "locas")
	var size: Vector3 = spec.get("size", Vector3(6.4, 13.0, 6.4))
	var h := size.y
	var hx := size.x * 0.5
	var rows: Array = tbl["tiers"]
	var kb := float(str(spec.get("kind", "locas_watchtower")).hash() % 1000)
	var stone := _st()
	var dark := _st()
	var blue := _st()
	var tips := _st()
	var rust := _st()
	var core := _st()
	var faces := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	# --- window recess banks (dark frame + cool-blue pane, riding the battered wall) ---
	var ent: Dictionary = spec.get("entrances", {})
	var door_clear := float(ent.get("main_w", 1.5)) * 0.5 + 0.55
	var wb: Dictionary = tbl["windows"]
	var pq: Dictionary = tbl["plaque"]
	for bk in ["plinth", "t2", "t3"]:
		var bd := wb[bk] as Dictionary
		var by0 := float(bd["y0"]) * h
		var by1 := float(bd["y1"]) * h
		var bmid := (by0 + by1) * 0.5
		var cols := int(bd["cols"])
		var w_out := _locas_half_frac(rows, float(bd["y0"])) * hx
		var w_in := _locas_half_frac(rows, float(bd["y1"])) * hx
		var depth := (w_out - w_in) * 0.5 + 0.10
		var wall_mid := (w_out + w_in) * 0.5
		for f_v in faces:
			var n := f_v as Vector3
			var u := Vector3(1, 0, 0) if absf(n.z) > 0.5 else Vector3(0, 0, 1)
			if bk == "t3" and n.z > 0.5:
				continue   # the plaque owns the tier-3 front (declared at the survey)
			var face_half := wall_mid * 0.94
			var step := face_half * 1.6 / float(maxi(1, cols))
			var pane_w := step * 0.30
			for ci in range(cols):
				var xo := (float(ci) - float(cols - 1) * 0.5) * step
				if bk == "plinth" and n.z > 0.5 and absf(xo) < door_clear + pane_w:
					continue   # the entry keeps its clearance (reserved at the survey)
				var pc := u * xo + n * wall_mid + Vector3(0, bmid, 0)
				_emit_oriented_box_st(dark, pc + n * (depth * 0.5 - 0.02), u, Vector3.UP, n,
					Vector3(pane_w, (by1 - by0) * 0.5, depth * 0.5))
				_emit_oriented_box_st(blue, pc + n * (depth * 0.5 + 0.012), u, Vector3.UP, n,
					Vector3(pane_w * 0.68, (by1 - by0) * 0.36, depth * 0.5))
	# --- the plaque (dark board + stone frame; the showcase nameplate rides it) ---
	var pq_y := (float(pq["y0"]) + float(pq["y1"])) * 0.5 * h
	var pq_hh := (float(pq["y1"]) - float(pq["y0"])) * 0.5 * h
	var pq_hw := float(pq["half_w"]) * h
	var pq_wall := _locas_half_frac(rows, (float(pq["y0"]) + float(pq["y1"])) * 0.5) * hx
	var fzn := Vector3(0, 0, 1)
	var fxu := Vector3(1, 0, 0)
	_emit_oriented_box_st(dark, Vector3(0, pq_y, pq_wall + 0.10), fxu, Vector3.UP, fzn,
		Vector3(pq_hw, pq_hh, 0.05))
	for e_s in [[Vector3(0, pq_y + pq_hh, pq_wall + 0.13), Vector3(pq_hw + 0.08, 0.05, 0.05)],
			[Vector3(0, pq_y - pq_hh, pq_wall + 0.13), Vector3(pq_hw + 0.08, 0.05, 0.05)],
			[Vector3(-pq_hw, pq_y, pq_wall + 0.13), Vector3(0.05, pq_hh + 0.08, 0.05)],
			[Vector3(pq_hw, pq_y, pq_wall + 0.13), Vector3(0.05, pq_hh + 0.08, 0.05)]]:
		_emit_box_st(stone, (e_s as Array)[0] as Vector3, (e_s as Array)[1] as Vector3)
	# --- corner buttresses (tier 1) + tier-3 ledge turrets ---
	var bt: Dictionary = tbl["buttresses"]
	var bt_h := float(bt["half_w"]) * h + 0.10
	for c1 in range(4):
		var sx1 := 1.0 if c1 % 2 == 0 else -1.0
		var sz1 := 1.0 if c1 < 2 else -1.0
		_emit_box_st(stone, Vector3(sx1 * (hx - bt_h * 0.4), float(bt["y1"]) * h * 0.5, sz1 * (size.z * 0.5 - bt_h * 0.4)),
			Vector3(bt_h, float(bt["y1"]) * h * 0.5, bt_h))
	var tr: Dictionary = tbl["turrets"]
	if float(tr["r"]) > 0.0:
		var t_led := _ledge_pair_at(rows, 0.620)
		var t_c := (t_led.x + t_led.y) * 0.5 * hx
		var t_rows := [[0.0, float(tr["r"])], [0.018, float(tr["r"]) * 0.82],
			[float(tr["h"]) * 0.80, float(tr["r"]) * 0.90], [float(tr["h"]), 0.006]]
		for c2 in range(4):
			var sx2 := 1.0 if c2 % 2 == 0 else -1.0
			var sz2 := 1.0 if c2 < 2 else -1.0
			_rings_loft(stone, Vector3(sx2 * t_c, 0.620 * h, sz2 * t_c), h, t_rows, 10)
	# --- tier-top edge light strips (the plate's cool blue edge lighting) ---
	for st_y in (tbl["strips"] as Array):
		var sy := float(st_y) * h
		var rim := _locas_half_frac(rows, float(st_y) - 0.004) * hx
		for f_v2 in faces:
			var n2 := f_v2 as Vector3
			var u2 := Vector3(1, 0, 0) if absf(n2.z) > 0.5 else Vector3(0, 0, 1)
			_emit_oriented_box_st(blue, n2 * (rim - 0.02) + Vector3(0, sy + 0.03, 0), u2, Vector3.UP, n2,
				Vector3(rim * 0.98, 0.028, 0.045))
	# --- the observation cage: rails + bars (the posts are massing) ---
	var cg: Dictionary = tbl["cage"]
	var cage_hx := _locas_half_frac(rows, 0.99) * hx
	var post_r2 := float(cg["post_r"]) * h
	var rail_half := cage_hx - post_r2
	for ry in (cg["rail_ys"] as Array):
		var ryy := float(ry) * h
		for f_v3 in faces:
			var n3 := f_v3 as Vector3
			var u3 := Vector3(1, 0, 0) if absf(n3.z) > 0.5 else Vector3(0, 0, 1)
			_emit_oriented_box_st(dark, n3 * (cage_hx - post_r2) + Vector3(0, ryy, 0), u3, Vector3.UP, n3,
				Vector3(rail_half, 0.045, 0.045))
	var nbars := int(cg["bars"])
	var bar_y0 := 0.800 * h
	var bar_y1 := float((cg["rail_ys"] as Array)[-1]) * h
	for f_v4 in faces:
		var n4 := f_v4 as Vector3
		var u4 := Vector3(1, 0, 0) if absf(n4.z) > 0.5 else Vector3(0, 0, 1)
		for bi in range(nbars):
			var bo := (float(bi) - float(nbars - 1) * 0.5) / float(nbars) * rail_half * 1.7
			_emit_oriented_box_st(dark, u4 * bo + n4 * (cage_hx - post_r2) + Vector3(0, (bar_y0 + bar_y1) * 0.5, 0),
				u4, Vector3.UP, n4, Vector3(0.03, (bar_y1 - bar_y0) * 0.5, 0.03))
	# --- beacon spires on the cage posts (cyan tip gems) ---
	var sp: Dictionary = tbl["spires"]
	var mast_r := clampf(float(sp["r"]) * h, 0.028, 0.040)
	for c3 in range(4):
		var sx3 := 1.0 if c3 % 2 == 0 else -1.0
		var sz3 := 1.0 if c3 < 2 else -1.0
		var mp := Vector3(sx3 * (cage_hx - post_r2), 0.0, sz3 * (cage_hx - post_r2))
		_tube(dark, [mp + Vector3(0, 0.965 * h, 0), mp + Vector3(0, (1.0 + float(sp["mast_h"])) * h, 0)], mast_r, 6)
		var gem_c := mp + Vector3(0, (1.0 + float(sp["mast_h"])) * h + 0.10, 0)
		_emit_box_st(tips, gem_c, Vector3(0.09, 0.13, 0.09))
	# --- the entry: heavy lintel + jambs + the blue transom over the door ---
	var d_w := float(ent.get("main_w", 1.5)) * 0.5
	var d_h := float(ent.get("main_h", 2.4))
	var en: Dictionary = tbl["entry"]
	var hz0 := size.z * 0.5
	_emit_box_st(stone, Vector3(0, d_h + float(en["lintel_h"]) * 0.5 + 0.34, hz0 + 0.06),
		Vector3(d_w + 0.55, float(en["lintel_h"]) * 0.5, 0.14))
	for sx4 in [-1.0, 1.0]:
		_emit_box_st(stone, Vector3(float(sx4) * (d_w + 0.32), d_h * 0.5, hz0 + 0.05),
			Vector3(0.22, d_h * 0.5, 0.12))
	_emit_oriented_box_st(blue, Vector3(0, d_h + float(en["transom_h"]) * 0.5 + 0.05, hz0 + 0.02),
		fxu, Vector3.UP, fzn, Vector3(d_w * 0.82, float(en["transom_h"]) * 0.5, 0.05))
	# --- Loca's bound chamber: the fever-red core (a wobbled lathe mass) ---
	var co: Dictionary = tbl["core"]
	var co_y := float(co["y"]) * h
	var co_r := float(co["r"]) * h
	var co_rows: Array = []
	var n_co := 7
	for i_c in range(n_co + 1):
		var t_c2 := float(i_c) / float(n_co)
		var rr := sin(t_c2 * PI) * co_r * (1.0 + 0.18 * (_h01(kb + 31.0 + float(i_c) * 7.7) - 0.5))
		co_rows.append([(co_y - co_r + t_c2 * co_r * 2.0) / h, maxf(0.012, rr) / h])
	_rings_loft(core, Vector3.ZERO, h, co_rows, 10)
	# --- the containment tangles: strands from the core over the cage rim, down the walls ---
	var tg: Dictionary = tbl["tangles"]
	var strands := int(tg["strands"])
	# the falls favour the rear + flanks but one strand always takes the front-right corner — the
	# plate's tangles wrap the whole crown; the front face proper stays clear of the plaque + entry
	var strand_faces := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
	var strand_lats := [0.2, 0.72, -0.3, -0.55, -0.68]
	for s_i in range(strands):
		var sn := strand_faces[s_i % strand_faces.size()] as Vector3
		var su := Vector3(1, 0, 0) if absf(sn.z) > 0.5 else Vector3(0, 0, 1)
		var lat0: float = float(strand_lats[s_i % strand_lats.size()]) * cage_hx \
			+ (_h01(kb + 3.0 + float(s_i) * 13.7) - 0.5) * 0.3 * cage_hx
		var pts: Array = []
		pts.append(Vector3(0, co_y + co_r * 0.4, 0) + sn * co_r * 0.5)
		pts.append(sn * (cage_hx * 0.7) + su * lat0 * 0.4 + Vector3(0, 0.965 * h, 0))
		pts.append(sn * (cage_hx + 0.06) + su * lat0 + Vector3(0, float((cg["rail_ys"] as Array)[0]) * h, 0))
		var y_end := float(tg["y0"]) * h * (1.0 + 0.35 * _h01(kb + 71.0 + float(s_i) * 3.3))
		var n_pt := 7
		for p_i in range(1, n_pt + 1):
			var t_p := float(p_i) / float(n_pt)
			var yy := lerpf(0.800 * h, y_end, t_p)
			var wall := _locas_half_frac(rows, yy / h) * hx
			var wander := (_h01(kb + 17.0 + float(s_i) * 5.3 + float(p_i) * 3.1) - 0.5) * 0.16 * h
			pts.append(sn * (wall + 0.06) + su * (lat0 + wander) + Vector3(0, yy, 0))
		var s_r := (0.0075 + 0.0035 * _h01(kb + 41.0 + float(s_i) * 9.9)) * h
		_tube(rust, pts, s_r, 5)
		# a thinner companion strand shadowing the fall + a drip fork off its mid-wall run — the
		# bundled-cable read the plate has (never a single clean wire)
		var comp: Array = []
		for p_v in pts:
			comp.append((p_v as Vector3) + su * s_r * 2.4 + sn * s_r * 0.6)
		_tube(rust, comp, s_r * 0.55, 4)
		var fork_a := pts[4] as Vector3
		_tube(rust, [fork_a, fork_a + sn * 0.12 + su * 0.22 * h * (_h01(kb + 53.0 + float(s_i)) - 0.5)
			+ Vector3(0, -0.10 * h, 0)], s_r * 0.6, 4)
	# two wrap loops around the core (the containment read: wires encasing her)
	for w_i in range(2):
		var tilt := 0.5 + 0.7 * float(w_i)
		var loop_pts: Array = []
		for a_i in range(13):
			var aa := TAU * float(a_i) / 12.0
			var lp := Vector3(cos(aa) * co_r * 1.18, sin(aa) * sin(tilt) * co_r * 1.18, sin(aa) * cos(tilt) * co_r * 1.18)
			loop_pts.append(Vector3(0, co_y, 0) + lp)
		_tube(rust, loop_pts, 0.045, 5)
	for s_t in [stone, dark, blue, tips, rust, core]:
		(s_t as SurfaceTool).generate_normals()
	return {"stone": stone.commit(), "dark": dark.commit(), "blue": blue.commit(),
		"tips": tips.commit(), "rust": rust.commit(), "core": core.commit(),
		"nameplate_pos": Vector3(0, pq_y, pq_wall + 0.45)}

## NUTECH facility detail passes, every part from the NUTECH survey frames: the per-storey window
## grids (dark recesses, a hash-lit minority pale cool-white — never all lit, it's abandoned), the
## white NUTECH roofline board, the green status indicator, the entry's concrete surround + cool
## transom, the loading dock (platform + posts + steps + the roll-up panel), the parapet lip, and
## the roof gear — plant boxes, the spray RESERVOIR tanks, the antenna.
## Families: concrete / metal (tanks, posts) / dark / lit (pale windows) / white (the board) /
## green (indicator). Plus "nameplate_pos" (ON the board).
static func nutech_details(spec: Dictionary) -> Dictionary:
	var Survey := load("res://scripts/generation/building_survey.gd") as GDScript
	var tbl: Dictionary = Survey.table_for(spec, "nutech")
	var size: Vector3 = spec.get("size", Vector3(6.0, 7.2, 4.6))
	var h := size.y
	var kb := float(str(spec.get("kind", "nutech_facility")).hash() % 1000) \
		+ float(spec.get("height_total", h)) * 7.0
	var concrete := _st()
	var metal := _st()
	var dark := _st()
	var lit := _st()
	var white := _st()
	var green := _st()
	var storeys := int(tbl["storeys"])
	var nbase := float(tbl["base"])
	var band := float(tbl["band"])
	var wb: Dictionary = tbl["windows"]
	var lit_f := float(wb["lit"])
	var dk: Dictionary = tbl["dock"]
	var dock_n := Vector3(float(dk["side"]), 0, 0)
	var ent: Dictionary = spec.get("entrances", {})
	var door_clear := float(ent.get("main_w", 1.4)) * 0.5 + 0.55
	var faces := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	# --- the storey window grids ---
	for k in range(storeys):
		var by0 := (nbase + band * (float(k) + float(tbl["win_lo"]))) * h
		var by1 := (nbase + band * (float(k) + float(tbl["win_hi"]))) * h
		var bmid := (by0 + by1) * 0.5
		var bhh := (by1 - by0) * 0.5
		for f_v in faces:
			var n := f_v as Vector3
			var u := Vector3(1, 0, 0) if absf(n.z) > 0.5 else Vector3(0, 0, 1)
			var wall := (size.z * 0.5) if absf(n.z) > 0.5 else (size.x * 0.5)
			var face_half := ((size.x * 0.5) if absf(n.z) > 0.5 else (size.z * 0.5)) * 0.9
			var cols := int(wb["front_cols"]) if absf(n.z) > 0.5 else int(wb["side_cols"])
			var step := face_half * 1.7 / float(maxi(1, cols))
			var pane_w := step * 0.30
			for ci in range(cols):
				var xo := (float(ci) - float(cols - 1) * 0.5) * step
				if k == 0 and n.z > 0.5 and absf(xo) < maxf(door_clear, 0.24 * h) + pane_w:
					continue   # the entry + indicator keep their clearance (survey-declared)
				if k == 0 and n.dot(dock_n) > 0.5 and absf(xo) < float(dk["panel_half_w"]) * h + pane_w:
					continue   # the dock panel owns this stretch (survey-declared)
				var pc := u * xo + n * wall + Vector3(0, bmid, 0)
				_emit_oriented_box_st(dark, pc + n * 0.02, u, Vector3.UP, n,
					Vector3(pane_w, bhh, 0.05))
				if _h01(kb + float(k) * 31.0 + float(ci) * 7.3 + n.x * 3.0 + n.z * 11.0) < lit_f:
					_emit_oriented_box_st(lit, pc + n * 0.045, u, Vector3.UP, n,
						Vector3(pane_w * 0.72, bhh * 0.74, 0.035))
	# --- the white NUTECH board (roofline, front) ---
	var sg: Dictionary = tbl["sign"]
	var sg_y := (float(sg["y0"]) + float(sg["y1"])) * 0.5 * h
	var sg_hh := (float(sg["y1"]) - float(sg["y0"])) * 0.5 * h
	var sg_hw := float(sg["half_w"]) * h
	var fzn := Vector3(0, 0, 1)
	var fxu := Vector3(1, 0, 0)
	var hz0 := size.z * 0.5
	_emit_oriented_box_st(white, Vector3(0, sg_y, hz0 + 0.07), fxu, Vector3.UP, fzn,
		Vector3(sg_hw, sg_hh, 0.045))
	_emit_oriented_box_st(dark, Vector3(0, sg_y, hz0 + 0.05), fxu, Vector3.UP, fzn,
		Vector3(sg_hw + 0.06, sg_hh + 0.06, 0.02))
	# --- the green status indicator by the entry ---
	var ind: Dictionary = tbl["indicator"]
	_emit_oriented_box_st(green, Vector3(float(ind["x"]) * h,
		(float(ind["y0"]) + float(ind["y1"])) * 0.5 * h, hz0 + 0.04),
		fxu, Vector3.UP, fzn,
		Vector3(float(ind["half_w"]) * h, (float(ind["y1"]) - float(ind["y0"])) * 0.5 * h, 0.035))
	# --- the entry: concrete surround + cool transom ---
	var d_w := float(ent.get("main_w", 1.4)) * 0.5
	var d_h := float(ent.get("main_h", 2.2))
	var en: Dictionary = tbl["entry"]
	_emit_box_st(concrete, Vector3(0, d_h + float(en["lintel_h"]) * 0.5 + 0.02, hz0 + 0.05),
		Vector3(d_w + 0.42, float(en["lintel_h"]) * 0.5, 0.11))
	for sx in [-1.0, 1.0]:
		_emit_box_st(concrete, Vector3(float(sx) * (d_w + 0.24), d_h * 0.5, hz0 + 0.04),
			Vector3(0.16, d_h * 0.5, 0.10))
	_emit_oriented_box_st(lit, Vector3(0, d_h - float(en["transom_h"]) * 0.5 - 0.04, hz0 + 0.02),
		fxu, Vector3.UP, fzn, Vector3(d_w * 0.8, float(en["transom_h"]) * 0.5, 0.04))
	# --- the loading dock: platform + posts + steps + the roll-up panel ---
	var dhx := size.x * 0.5
	var d_out := float(dk["platform_out"]) * h
	var plat_h := float(dk["platform_h"]) * h
	var plat_c := dock_n * (dhx + d_out * 0.5)
	_emit_box_st(concrete, plat_c + Vector3(0, plat_h * 0.5, 0),
		Vector3(d_out * 0.5 + 0.05, plat_h * 0.5, size.z * 0.34))
	for pz in [-1.0, 1.0]:
		_emit_box_st(metal, dock_n * (dhx + d_out) + Vector3(0, plat_h + 0.35, float(pz) * size.z * 0.30),
			Vector3(0.05, 0.35, 0.05))
	_emit_box_st(concrete, plat_c + Vector3(0, plat_h * 0.25, size.z * 0.34 + 0.30),
		Vector3(d_out * 0.5, plat_h * 0.25, 0.30))
	_emit_oriented_box_st(dark, dock_n * (dhx + 0.03) + Vector3(0, (float(dk["panel_y0"]) + float(dk["panel_y1"])) * 0.5 * h, 0),
		Vector3(0, 0, 1), Vector3.UP, dock_n,
		Vector3(float(dk["panel_half_w"]) * h, (float(dk["panel_y1"]) - float(dk["panel_y0"])) * 0.5 * h, 0.04))
	# --- parapet lip + roof gear (plant, the reservoir tanks, the antenna) ---
	var pp: Dictionary = tbl["parapet"]
	var lip_y := (float(pp["y0"]) + 1.0) * 0.5 * h
	var lip_hh := (1.0 - float(pp["y0"])) * 0.5 * h
	for f_v2 in faces:
		var n2 := f_v2 as Vector3
		var u2 := Vector3(1, 0, 0) if absf(n2.z) > 0.5 else Vector3(0, 0, 1)
		var wall2 := (size.z * 0.5) if absf(n2.z) > 0.5 else (size.x * 0.5)
		var run2 := (size.x * 0.5) if absf(n2.z) > 0.5 else (size.z * 0.5)
		_emit_oriented_box_st(concrete, n2 * (wall2 + float(pp["lip"]) * 0.4) + Vector3(0, lip_y, 0),
			u2, Vector3.UP, n2, Vector3(run2 + float(pp["lip"]) * 0.4, lip_hh, float(pp["lip"]) * 0.5))
	var rf: Dictionary = tbl["roof"]
	for p_i in range(int(rf["plant"])):
		var px := (_h01(kb + 61.0 + float(p_i) * 9.1) - 0.5) * size.x * 0.55
		var pz2 := (_h01(kb + 67.0 + float(p_i) * 5.7) - 0.5) * size.z * 0.5
		var ph := 0.25 + 0.30 * _h01(kb + 71.0 + float(p_i) * 3.3)
		_emit_box_st(concrete, Vector3(px, h + ph * 0.5, pz2), Vector3(0.45, ph * 0.5, 0.38))
	var t_rows := [[0.0, float(rf["tank_r"])], [0.015, float(rf["tank_r"]) * 0.9],
		[float(rf["tank_h"]) * 0.85, float(rf["tank_r"]) * 0.95], [float(rf["tank_h"]), 0.01]]
	for t_i in range(int(rf["tanks"])):
		var tx := (float(t_i) - float(int(rf["tanks"]) - 1) * 0.5) * size.x * 0.30 - size.x * 0.12
		var tz := size.z * (0.16 if t_i % 2 == 0 else -0.16)
		_rings_loft(metal, Vector3(tx, h, tz), h, t_rows, 10)
		_tube(metal, [Vector3(tx, h + 0.10, tz), Vector3(tx, h + 0.10, tz) + Vector3(0.0, 0.0, -tz - size.z * 0.05)], 0.035, 5)
	if bool(rf["antenna"]):
		var ap := Vector3(size.x * 0.36, h, -size.z * 0.30)
		_tube(dark, [ap, ap + Vector3(0, 0.19 * h, 0)], 0.028, 5)
		_emit_box_st(green, ap + Vector3(0, 0.19 * h + 0.06, 0), Vector3(0.05, 0.06, 0.05))
	for s_t in [concrete, metal, dark, lit, white, green]:
		(s_t as SurfaceTool).generate_normals()
	return {"concrete": concrete.commit(), "metal": metal.commit(), "dark": dark.commit(),
		"lit": lit.commit(), "white": white.commit(), "green": green.commit(),
		"nameplate_pos": Vector3(0, sg_y, hz0 + 0.35)}

## The (outer, inner) half fractions of the setback ledge at y_frac (consecutive tier rows sharing y).
static func _ledge_pair_at(rows: Array, y_frac: float) -> Vector2:
	for i in range(rows.size() - 1):
		var a := rows[i] as Array
		var b := rows[i + 1] as Array
		if absf(float(a[0]) - y_frac) < 0.001 and absf(float(b[0]) - y_frac) < 0.001:
			return Vector2(float(a[1]), float(b[1]))
	return Vector2(1.0, 1.0)

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
