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
			"reserve_margin": 0.25, "canopy_out": 0.0},
		"color": Color(0.24, 0.35, 0.32),   # dark desaturated verdigris (plate palette)
		"tile": "facility_metal",
		"lattice": "",
		"pipes": false,                     # no draped tangle on the plate — the flume, dome ribs and
	},                                      # ONE side pipe come from the survey (plumbing_details)
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
		"shape": SHAPE_COMPOSITE,           # SURVEY REBUILD 1.2: ONE lofted lathe from the
		"composite": "hypelines_mound",     # BuildingSurvey.HYPELINES ring table (skirt/drum/dome)
		"door_frame": "cyl",
		"door_radius": 1.53,                # the front lobe VALLEY the door cuts: 0.325H*(1-0.24)
		"radius": 2.5, "height": 6.2,       # silhouette crest at ground: 0.403H (foot 0.81H, plate)
		"flare": 1.0,
		# RECONCILED AT THE SURVEY: doors sized to the character inside the plate's parabolic
		# toll-gate arch (the arch idiom + toll board are survey detail passes); no canopy slab —
		# the arch is the entry architecture.
		"entrances": {"main_w": 0.9, "main_h": 1.5, "side_w": 0.8, "side_h": 1.4, "canopy_out": 0.0},
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
		"entrances": {"main_w": 1.1, "main_h": 1.32, "side_w": 0.9, "side_h": 1.25, "reserve_margin": 0.08},
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
		# RECONCILED AT THE SURVEY: the body wall ends at 0.53H = 2.44 m; the default 2.7 m portal rose
		# past it. Plate ratio (BUILDING_REVIEW ancourage #4): arch height 0.7x body height ~= 1.7 m.
		"entrances": {"main_w": 1.4, "main_h": 1.7, "side_w": 0.9, "side_h": 1.5},
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
		"shape": SHAPE_COMPOSITE,           # main block + collapsed side wing + cornice slab (REVIEW P1-P2)
		"composite": "zone3_split",
		# plan W x 0.9W (the plate ratio the mesh already built) — the spec used to say 4.0 deep while
		# the walls stood at 3.6, so the door frame floated 0.2 m off the wall. Surveyed coherent.
		"size": Vector3(4.0, 5.4, 3.6),
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
		"zone3_split":
			return _zone3_split_mesh(spec, reserved, recess)
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
	var cs: Dictionary = Survey.CLEANSTREETS
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
	var cs: Dictionary = Survey.CLEANSTREETS
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
	_emit_oriented_box_st(body, Vector3(-1.6, 0.15, mz), u_x, Vector3.UP, n_z, Vector3(0.85, 0.15, 0.6))
	_emit_oriented_box_st(body, Vector3(-1.6, float(mono["base_h"]) * 0.5 + 0.1, mz), u_x, Vector3.UP, n_z,
		Vector3(0.65, float(mono["base_h"]) * 0.5, 0.45))
	_emit_oriented_box_st(body, Vector3(-1.6, float(mono["base_h"]) + float(mono["h"]) * 0.5, mz),
		u_x, Vector3.UP, n_z, Vector3(float(mono["w"]) * 0.5, float(mono["h"]) * 0.5, 0.24))
	_emit_oriented_box_st(dark, Vector3(-1.6, float(mono["base_h"]) + float(mono["h"]) * 0.55, mz + 0.25),
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
	var hy: Dictionary = Survey.HYPELINES
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
