class_name BuildingSurvey
extends RefCounted

## THE MEASURED DRAWING of one district building, AS DATA — the single coordinate authority every
## construction pass reads (docs/SURVEY_REBUILD.md task 0; the director's measure-first method).
## A building is surveyed BEFORE it is meshed:
##   datums        named heights — plinth / storey tops / eave (top of the vertical wall band) / crown
##   plan          the axis-and-bay grid: drum (wall radius + bays) or box (half extents + wall faces)
##   profile       the silhouette r(y) (drum) or half-extents(y) (box) as ordered control points —
##                 this absorbs the old BaseShapeBuilder.massing_radius_at piecewise tables
##   reservations  a typed claim on wall space for EVERY planned part (openings, lattice fields,
##                 decorations, sockets) — two parts that want the same wall are reconciled HERE
##                 (restructure the field around the reservation, or fold the part into the base),
##                 so collisions are impossible by construction, never patched after meshing
##   sockets       the gameplay registry (doors, roads, bridges/lanes, weak points, balcony slots) —
##                 the architecture->puzzle contract, every socket ON a surveyed surface
##
## Consumers read the survey, not each other:
##   - door placement is door_placements() — LatticeBuilder.entrances emits meshes FROM it
##   - draped pipes follow radius_at() (the silhouette profile keeps parts on the real surface)
##   - gameplay anchors come from sockets (anchors() reshapes them for the existing consumers)
## The *_mesh builders in BaseShapeBuilder still carry their own construction constants; each
## building's task-1 rebuild (docs/SURVEY_REBUILD.md) moves its meshing onto the survey. Until then
## the profile tables here MIRROR those constants — keep them in lockstep, and validate() is the
## tripwire when they drift.

const EPS := 0.02                 # overlap / datum tolerance (m)
const DRUM_BAYS_FALLBACK := 8     # mirrors LatticeBuilder.TRACERY_DEFAULTS.bays (the drum plan grid)
const DEFAULT_STOREY := 2.7       # storey band height when a building has no authored storey plan

## Entrance parameters — placement half (main/side sizes, clearance) + mesh half (proud/recess/
## canopy). Placement is the survey's job; LatticeBuilder.entrances reads the same table for meshes.
const ENTRANCE_DEFAULTS := {
	"main_w": 1.6, "main_h": 2.7,
	"side_w": 1.1, "side_h": 2.1,
	"jamb": 0.20,        # frame post/lintel thickness
	"proud": 0.16,       # how far the frame stands off the wall
	"recess": 0.42,      # how deep the doorway pocket sinks in
	"canopy_out": 0.5,   # canopy overhang depth
	"side_count_min": 1, # range of SIDE entrances; the count is seeded per building
	"side_count_max": 3,
	"reserve_margin": 0.45,   # extra clearance (m) around a door the lattice must keep clear
}

## Eave datum (top of the vertical WALL band, where the crown/dome/roof takes over) as a fraction of
## total height, per composite. Each ratio traces to the massing constant that traces to the plate
## decomposition in docs/BUILDING_REVIEW.md.
const EAVE_RATIOS := {
	"plumbing_lobed": 0.74,    # dome springing (plate: dome crown 72-100% H)
	"ancourage_domes": 0.53,   # eave ring / dome cluster seat (plate: body ~45% H + eave band)
	"hypelines_mound": 0.38,   # tier-1 skirt top (plate: base skirt 35-40% H)
	"beacon_domed": 0.75,      # drum top / dome shoulder springing (plate: shoulder top ~75% H)
	"canopy_piers": 0.56,      # canopy slab underside (plate: open leg zone ~45% + dais)
	"bulwark_towers": 0.86,    # gatehouse body top (towers rise past it to the crown)
	"zone3_split": 0.94,       # cornice underside (plate: crown slab = top ~6% H)
}

## Authored storey plans (ground band + floor count between plinth and eave), per building kind.
## Numbers trace to the plate decompositions; buildings without an entry get equal DEFAULT_STOREY
## bands. greenfields' ground/storey split is ALSO the slab-ring datum table the massing builds on.
const STOREY_PLANS := {
	"honeycomb_cooperative": {"ground_factor": 1.2, "floors": 6},   # plate: tall ground + 6 floors
	"greenfields": {"ground": 1.7, "floors": 3},                    # plate: arcade + 3 floors
}

var kind := ""
var spec: Dictionary = {}
var datums: Dictionary = {"plinth": 0.0, "storeys": [], "eave": 0.0, "crown": 0.0}
var plan: Dictionary = {}
var profile: Array = []          # drum: [{y, r}] / box: [{y, hx, hz}] — ascending y, steps allowed
var reservations: Array = []     # typed wall claims (openings carry the legacy door-region keys)
var sockets: Array = []          # {kind: door|road|bridge|weak_point|balcony, pos, ...}


## Survey a building from its BaseShapeBuilder spec (generate() output; raw SPECS entries work too).
## `plate_ratios` lets a per-building rebuild override datum ratios measured off the plate.
static func from_spec(spec_in: Dictionary, plate_ratios: Dictionary = {}) -> BuildingSurvey:
	var sv := BuildingSurvey.new()
	sv.spec = spec_in.duplicate(true)
	sv.kind = str(spec_in.get("kind", ""))
	sv._survey_datums(plate_ratios)
	sv._survey_plan()
	sv._survey_profile()
	var placements := door_placements(sv.spec)
	sv._survey_reservations(placements)
	sv._survey_sockets(placements)
	return sv

func _height_total() -> float:
	if spec.has("height_total"):
		return float(spec["height_total"])
	if spec.has("size"):
		return (spec["size"] as Vector3).y
	return float(spec.get("height", 6.0))

func _footprint() -> float:
	if spec.has("footprint"):
		return float(spec["footprint"])
	if spec.has("size"):
		var s: Vector3 = spec["size"]
		return maxf(s.x, s.z)
	return float(spec.get("radius", 2.5)) * 2.0 * float(spec.get("flare", 1.0))

func _is_drum() -> bool:
	return str(spec.get("shape", "")) == "cylinder" or (spec.has("radius") and not spec.has("size"))


# ============================================================================================
# SURVEY PASSES — datums, plan, profile, reservations, sockets
# ============================================================================================

func _survey_datums(plate_ratios: Dictionary) -> void:
	var h := _height_total()
	var comp := str(spec.get("composite", ""))
	var eave_ratio := float(plate_ratios.get("eave", EAVE_RATIOS.get(comp, 1.0)))
	datums["plinth"] = 0.0
	datums["eave"] = h * eave_ratio
	datums["crown"] = h
	var eave := float(datums["eave"])
	var storeys: Array = []
	var sp: Dictionary = STOREY_PLANS.get(kind, {})
	if plate_ratios.has("storeys"):
		storeys = (plate_ratios["storeys"] as Array).duplicate()
	elif sp.has("ground"):
		var ground := float(sp["ground"])
		var floors := int(sp["floors"])
		var band := (eave - ground) / float(maxi(1, floors))
		storeys.append(ground)
		for k in range(1, floors + 1):
			storeys.append(ground + band * float(k))
	elif sp.has("ground_factor"):
		var gf := float(sp["ground_factor"])
		var floors := int(sp["floors"])
		var f := eave / (gf + float(floors))
		storeys.append(gf * f)
		for k in range(1, floors + 1):
			storeys.append(gf * f + f * float(k))
	else:
		var n := maxi(1, int(round(eave / DEFAULT_STOREY)))
		for k in range(1, n + 1):
			storeys.append(eave * float(k) / float(n))
	datums["storeys"] = storeys

func _survey_plan() -> void:
	if _is_drum():
		plan = {
			"kind": "drum",
			"radius": float(spec.get("radius", 2.0)),
			# the wall the doors actually cut (the plumbing drum sits inside its lobed skirt)
			"wall_radius": float(spec.get("door_radius", spec.get("radius", 2.0))),
			"bays": int(spec.get("bays", DRUM_BAYS_FALLBACK)),
			"front_theta": PI * 0.5,
		}
	else:
		var size: Vector3 = spec.get("size", Vector3(4, 6, 4))
		plan = {
			"kind": "box",
			"half_extents": Vector2(size.x * 0.5, size.z * 0.5),
			"faces": _wall_faces(size),
			"front_n": Vector3(0, 0, 1),
		}

## The silhouette profile control points. These tables mirror the *_mesh construction constants in
## BaseShapeBuilder (the old massing_radius_at breakpoints; curves sampled piecewise-linear) — the
## survey is the READ surface; per-building rebuilds re-derive both from the plate.
func _survey_profile() -> void:
	profile.clear()
	var h := _height_total()
	var crown := float(datums["crown"])
	var comp := str(spec.get("composite", ""))
	if _is_drum():
		var r := float(spec.get("radius", 2.0))
		match comp:
			"plumbing_lobed":
				var rd := float(spec.get("door_radius", r * 0.62))
				_pr(0.0, rd * 1.5)                       # root-lobe flare at ground
				_pr(h * 0.47, rd)                        # lobes fuse into the shoulder drum
				_pr(h * 0.74, rd)                        # drum top / dome springing
				for t in [0.0, 0.35, 0.6, 0.8, 0.92, 1.0]:
					var tf := float(t)
					var rr := maxf(rd * 0.2, rd * 1.12 * sqrt(maxf(0.0, 1.0 - tf * tf)))
					_pr(h * 0.74 + rd * 0.75 * tf, rr)   # onion dome, sampled
				_pr(crown, rd * 0.2)                     # cupola shaft to the finial
			"ancourage_domes":
				_pr(0.0, r)
				_pr(h * 0.53, r)                         # body top / eave ring
				_pr(h * 0.53, r * 0.95)                  # dome cluster seat
				_pr(crown, r * 0.2)
			"hypelines_mound":
				_pr(0.0, r)
				_pr(h * 0.38, r)                         # tier-1 skirt
				_pr(h * 0.38, r * 0.78)
				_pr(h * 0.68, r * 0.62)                  # tier-2 drum
				_pr(h * 0.68, r * 0.5)
				_pr(h * 0.9, r * 0.38)                   # tier-3 drum
				_pr(h * 0.9, r * 0.4)
				_pr(crown, r * 0.1)                      # dome cap
			"beacon_domed":
				_pr(0.0, r)
				_pr(h * 0.75, r)                         # drum
				_pr(crown, r * 0.45)                     # dome shoulder into the lantern
			_:
				var tiers := maxi(1, int(spec.get("tiers", 1)))
				if tiers > 1:
					var band := h / float(tiers)
					var inset := float(spec.get("tier_inset", 0.16))
					for k in range(tiers):
						var rk := maxf(0.4, r * (1.0 - inset * float(k)))
						_pr(band * float(k), rk)
						_pr(band * float(k + 1), rk)
				else:
					_pr(0.0, r)
					_pr(crown, r)
	else:
		var size: Vector3 = spec.get("size", Vector3(4, 6, 4))
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		match comp:
			"zone3_split":
				_pb(0.0, hx, hz)                          # main block plan W x 0.9W (plate ratio)
				_pb(h * 0.94, hx, hz)
				_pb(h * 0.94, hx + size.x * 0.09, hz + size.x * 0.09)   # cornice slab overhang (0.09W)
				_pb(crown, hx + size.x * 0.09, hz + size.x * 0.09)
			"open_files_awnings":
				# stepped awning flare approximated as a straight taper ground->core; the layout is
				# the construction authority (BaseShapeBuilder._awning_layout) — task-1 re-derives
				var core: Vector2 = BaseShapeBuilder._awning_layout(spec)["core"]
				_pb(0.0, hx, hz)
				_pb(crown, core.x, core.y)
			_:
				var tiers := maxi(1, int(spec.get("tiers", 1)))
				if tiers > 1:
					var band := h / float(tiers)
					var inset := float(spec.get("tier_inset", 0.16))
					for k in range(tiers):
						var f := maxf(0.25, 1.0 - inset * float(k))
						_pb(band * float(k), hx * f, hz * f)
						_pb(band * float(k + 1), hx * f, hz * f)
				else:
					_pb(0.0, hx, hz)
					_pb(crown, hx, hz)

func _pr(y: float, r: float) -> void:
	profile.append({"y": y, "r": r})

func _pb(y: float, hx: float, hz: float) -> void:
	profile.append({"y": y, "hx": hx, "hz": hz})

## RESERVATIONS: openings (the door placements), the declared lattice's field claim, and decoration
## bands the massing wears (greenfields' slab rings). A lattice field lists the openings it is
## restructured around in `keeps_clear`; anything else overlapping an opening is a validation error.
func _survey_reservations(placements: Array) -> void:
	reservations.clear()
	var opening_ids: Array = []
	for pl_v in placements:
		var region := ((pl_v as Dictionary)["region"] as Dictionary)
		reservations.append(region)
		opening_ids.append(str(region["id"]))
	var eave := float(datums["eave"])
	var crown := float(datums["crown"])
	match str(spec.get("lattice", "")):
		"tracery":
			reservations.append({
				"id": "field_tracery", "type": "lattice_field", "cyl": true,
				"theta": 0.0, "half_arc": PI,
				"y0": 0.0, "y1": float(spec.get("tracery_height", spec.get("height", crown))),
				"keeps_clear": opening_ids,
			})
		"honeyframe", "voronoi", "rackwork":
			for f_v in _wall_faces(spec.get("size", Vector3(4, 6, 4))):
				var f := f_v as Dictionary
				reservations.append({
					"id": "field_%s_%s" % [str(spec.get("lattice", "")), _n_name(f["n"] as Vector3)],
					"type": "lattice_field", "cyl": false, "n": f["n"],
					"x_center": 0.0, "half_w": float(f["w"]) * 0.5,
					"y0": 0.0, "y1": crown,
					"keeps_clear": opening_ids,
				})
		"balconies":
			# greenfields: the balcony lattice LIVES on the slab-ring datums — ring bands, not wall
			# fields. keeps_clear stays EMPTY: a ring crossing a doorway is a real collision (the
			# door heights were reconciled at the survey to fit under the first ring).
			var storeys: Array = datums["storeys"]
			for k in range(storeys.size()):
				var y := minf(float(storeys[k]), crown - 0.09)
				reservations.append({
					"id": "slab_ring_%d" % k, "type": "lattice_field", "ring": true,
					"y0": y - 0.09, "y1": y + 0.09, "keeps_clear": [],
				})
	if str(spec.get("composite", "")) == "canopy_piers":
		# the canopy slab band: nothing else may claim the air the slab occupies
		reservations.append({
			"id": "canopy_slab", "type": "decoration", "ring": true,
			"y0": eave, "y1": crown, "keeps_clear": [],
		})

## SOCKETS — the architecture->puzzle contract (director, 2026-07-09), now placed FROM the survey:
##   weak_point   structural weaknesses ON the silhouette profile — may crumble when hit
##   road         one per entrance threshold, facing out (main flagged for the level's spine)
##   bridge       where level bridges/walkable lanes dock (ledge rims, roof edges, hypelines arms)
##   balcony      content points on tier ledges (flora, lures, rest spots, set-piece controls)
##   door         the placed entrances themselves (the placement authority's record)
func _survey_sockets(placements: Array) -> void:
	sockets.clear()
	var comp := str(spec.get("composite", ""))
	var kb := float(str(kind).hash() % 1000)
	for pl_v in placements:
		var pl := pl_v as Dictionary
		var fr := pl["frame"] as Dictionary
		sockets.append({"kind": "door", "pos": fr["anchor"], "n": fr["n"], "main": bool(pl["main"])})
		sockets.append({"kind": "road", "pos": fr["anchor"], "dir": fr["n"], "width": 1.2, "main": bool(pl["main"])})
	if comp == "open_files_awnings":
		# weak points on hash-picked skirt bands (the visible stepped facades); bridge sockets at
		# the flat core-roof edges. The sloped awning roofs hold no balcony slots.
		var lay: Dictionary = BaseShapeBuilder._awning_layout(spec)
		for k3 in range(2):
			var fi := int(BaseShapeBuilder._h01(kb + 3.0 + float(k3) * 13.7) * 3.99)
			var lv: Array = (lay["faces"] as Array)[fi]
			var li := int(BaseShapeBuilder._h01(kb + 8.0 + float(k3) * 5.1) * float(lv.size() - 1) * 0.99)
			var pts := lv[li] as Dictionary
			var mid: Vector3 = ((pts["E"] as Vector3) + (pts["F"] as Vector3)) * 0.5
			var wy := (mid.y + float(pts["bottom_y"])) * 0.5
			sockets.append({"kind": "weak_point", "pos": Vector3(mid.x, wy, mid.z), "n": pts["n"], "radius": 0.7})
		var core: Vector2 = lay["core"]
		var hh: float = lay["h"]
		for fd0 in [[Vector3(0, hh, core.y), Vector3(0, 0, 1)], [Vector3(0, hh, -core.y), Vector3(0, 0, -1)],
				[Vector3(core.x, hh, 0), Vector3(1, 0, 0)], [Vector3(-core.x, hh, 0), Vector3(-1, 0, 0)]]:
			sockets.append({"kind": "bridge", "pos": (fd0 as Array)[0], "dir": (fd0 as Array)[1], "width": 1.0})
		return
	if comp == "hypelines_mound":
		# the lane-arm tips: walkable-lane dock sockets (the director's walkable-lanes directive)
		for a in BaseShapeBuilder.hypelines_arms(spec):
			var ad := a as Dictionary
			sockets.append({"kind": "bridge", "lane": true, "pos": ad["tip"],
				"dir": (ad["dir"] as Vector3).normalized(), "width": 1.1})
	if str(plan.get("kind", "")) == "drum":
		var hgt := float(spec.get("height", 5.0))
		var nw := 2 + int(BaseShapeBuilder._h01(kb + 1.0) * 1.9)
		for k in range(nw):
			var th := TAU * BaseShapeBuilder._h01(kb + 10.0 + float(k) * 7.7)
			var wy := hgt * (0.45 + 0.4 * BaseShapeBuilder._h01(kb + 20.0 + float(k) * 3.3))
			var nrm := Vector3(cos(th), 0.0, sin(th))
			sockets.append({"kind": "weak_point", "pos": nrm * radius_at(wy) + Vector3(0, wy, 0),
				"n": nrm, "radius": 0.7})
	else:
		var s: Vector3 = spec.get("size", Vector3(4, 6, 4))
		# cornice-corner weaknesses (two hash-picked corners) + one upper mid-face, ON the profile
		# extents at their height (a tiered box's upper corners sit on the shrunken tier)
		var c0 := int(BaseShapeBuilder._h01(kb + 2.0) * 3.99)
		for k2 in range(2):
			var corner := (c0 + k2 * 2) % 4
			var he := half_extents_at(s.y * 0.85)
			var cx := he.x if corner % 2 == 0 else -he.x
			var cz := he.y if corner < 2 else -he.y
			sockets.append({"kind": "weak_point", "pos": Vector3(cx, s.y * 0.85, cz),
				"n": Vector3(cx, 0, cz).normalized(), "radius": 0.7})
		sockets.append({"kind": "weak_point", "pos": Vector3(0, s.y * 0.7, half_extents_at(s.y * 0.7).y),
			"n": Vector3(0, 0, 1), "radius": 0.8})
		# roof-rim bridge connectors (flat boxes without tiers get their sockets at the parapet)
		if maxi(1, int(spec.get("tiers", 1))) <= 1:
			var hx := s.x * 0.5
			var hz := s.z * 0.5
			for fd in [[Vector3(0, s.y, hz), Vector3(0, 0, 1)], [Vector3(0, s.y, -hz), Vector3(0, 0, -1)],
					[Vector3(hx, s.y, 0), Vector3(1, 0, 0)], [Vector3(-hx, s.y, 0), Vector3(-1, 0, 0)]]:
				sockets.append({"kind": "bridge", "pos": (fd as Array)[0], "dir": (fd as Array)[1], "width": 1.0})
	# tier ledges (cyl or box): BRIDGE sockets at the rim quarters, BALCONY slots around the ring
	for lg in BaseShapeBuilder.tier_ledges(spec):
		var ld := lg as Dictionary
		var ly := float(ld["y"])
		for q in range(4):
			var smp: Dictionary = LedgeBuilder._ledge_center_sample(ld, (float(q) + 0.5) / 4.0)
			var opos := smp["pos"] as Vector3
			sockets.append({"kind": "bridge",
				"pos": Vector3(opos.x, ly, opos.z) + (smp["outward"] as Vector3) * 0.3,
				"dir": smp["outward"], "width": 1.0})
		var ns := 3 + int(BaseShapeBuilder._h01(kb + 40.0) * 2.9)
		for sl in range(ns):
			var smp2: Dictionary = LedgeBuilder._ledge_center_sample(ld, (float(sl) + 0.25) / float(ns))
			var bpos := smp2["pos"] as Vector3
			sockets.append({"kind": "balcony", "pos": Vector3(bpos.x, ly, bpos.z),
				"out": smp2["outward"], "size": 0.5})


# ============================================================================================
# READ SURFACE — what consumers query
# ============================================================================================

## Silhouette radius at height y (drums). Boxes answer their larger half extent so a radial consumer
## (pipe drapes) still gets a usable envelope.
func radius_at(y: float) -> float:
	if profile.is_empty():
		return float(spec.get("radius", 2.0))
	var first := profile[0] as Dictionary
	if y <= float(first["y"]):
		return _point_r(first)
	for i in range(profile.size() - 1):
		var b := profile[i + 1] as Dictionary
		if y <= float(b["y"]):
			var a := profile[i] as Dictionary
			var dy := float(b["y"]) - float(a["y"])
			if dy <= 0.0001:
				continue   # a step discontinuity: the segment above owns this y
			return lerpf(_point_r(a), _point_r(b), (y - float(a["y"])) / dy)
	return _point_r(profile[profile.size() - 1] as Dictionary)

## Half extents (hx, hz) at height y (boxes). Drums answer (r, r).
func half_extents_at(y: float) -> Vector2:
	if profile.is_empty():
		var r := float(spec.get("radius", 2.0))
		return Vector2(r, r)
	var first := profile[0] as Dictionary
	if y <= float(first["y"]):
		return _point_he(first)
	for i in range(profile.size() - 1):
		var b := profile[i + 1] as Dictionary
		if y <= float(b["y"]):
			var a := profile[i] as Dictionary
			var dy := float(b["y"]) - float(a["y"])
			if dy <= 0.0001:
				continue
			return _point_he(a).lerp(_point_he(b), (y - float(a["y"])) / dy)
	return _point_he(profile[profile.size() - 1] as Dictionary)

func _point_r(p: Dictionary) -> float:
	if p.has("r"):
		return float(p["r"])
	return maxf(float(p.get("hx", 2.0)), float(p.get("hz", 2.0)))

func _point_he(p: Dictionary) -> Vector2:
	if p.has("r"):
		return Vector2(float(p["r"]), float(p["r"]))
	return Vector2(float(p.get("hx", 2.0)), float(p.get("hz", 2.0)))

## The opening reservations (the door regions), in the legacy reserved-region shape the base mesh
## cutters and lattice builders consume.
func openings() -> Array:
	var out: Array = []
	for r_v in reservations:
		if str((r_v as Dictionary).get("type", "")) == "opening":
			out.append(r_v)
	return out

## The gameplay anchors in the legacy {weak_points, connectors, balcony_slots} shape
## (ex BaseShapeBuilder.gameplay_anchors — building_filler and the showcase read this).
func anchors() -> Dictionary:
	var weak: Array = []
	var conns: Array = []
	var balc: Array = []
	for s_v in sockets:
		var s := s_v as Dictionary
		match str(s["kind"]):
			"weak_point":
				weak.append({"pos": s["pos"], "n": s["n"], "radius": float(s["radius"])})
			"road":
				conns.append({"kind": "road", "pos": s["pos"], "dir": s["dir"],
					"width": float(s["width"]), "main": bool(s.get("main", false))})
			"bridge":
				conns.append({"kind": "bridge", "pos": s["pos"], "dir": s["dir"], "width": float(s["width"])})
			"balcony":
				balc.append({"pos": s["pos"], "out": s["out"], "size": float(s["size"])})
	return {"weak_points": weak, "connectors": conns, "balcony_slots": balc}

## The whole measured drawing as one dictionary (deterministic printing / comparison).
func summary() -> Dictionary:
	return {"kind": kind, "datums": datums, "plan": plan, "profile": profile,
		"reservations": reservations, "sockets": sockets}


# ============================================================================================
# DOOR PLACEMENT — the ONE authority (LatticeBuilder.entrances emits meshes from these)
# ============================================================================================

## Place the entrances for a base shape: the MAIN door at the front (+Z), plus a seeded number of
## SIDE doors distributed around the building (drum doors snap to tracery bays). Returns
## [{main, frame:{anchor,u,v,n}, w, h, region, bay}] — `region` is the reserved wall claim carrying
## BOTH extents (the opening the wall cuts, and the clearance the lattice keeps free).
static func door_placements(spec_in: Dictionary, params: Dictionary = {}) -> Array:
	var p := ENTRANCE_DEFAULTS.duplicate()
	var spec_ov: Dictionary = spec_in.get("entrances", {})
	for k in spec_ov.keys():
		p[k] = spec_ov[k]
	for k in params.keys():
		p[k] = params[k]
	var is_cyl := str(spec_in.get("shape", "box")) == "cylinder" or str(spec_in.get("door_frame", "")) == "cyl"
	# door_radius: the wall the door ACTUALLY cuts when it differs from the massing radius (the
	# plumbing drum sits inside its lobed skirt — the door lives on the drum, not the flare).
	var radius := float(spec_in.get("door_radius", spec_in.get("radius", 2.0)))
	var faces := _wall_faces(spec_in.get("size", Vector3(4, 6, 4)))
	var main_w := float(p["main_w"])
	var main_h := float(p["main_h"])
	var side_w := float(p["side_w"])
	var side_h := float(p["side_h"])
	var jamb := float(p["jamb"])
	var margin := float(p["reserve_margin"])
	var rng := SeededRng.new(int(str(spec_in.get("kind", "")).hash()) ^ 0x5177)
	var n_side := int(rng.call("randi_range", int(p["side_count_min"]), int(p["side_count_max"])))
	# On a TRACERY drum, doors live IN bays (the plate: each door framed by its bay's mullions) —
	# snap every door to a bay CENTRE and reserve exactly that bay.
	var snap_drum := is_cyl and str(spec_in.get("lattice", "")) == "tracery"
	var bays := int(spec_in.get("bays", DRUM_BAYS_FALLBACK))
	var dtheta := TAU / float(bays)
	var used_bays: Dictionary = {}
	var out: Array = []
	var mf := _door_frame_cyl(radius, PI * 0.5) if is_cyl else _door_frame_face(faces[0], 0.0)
	var mrr := _reserve_region(is_cyl, radius, mf, main_w, main_h, jamb, margin, "door_main")
	if snap_drum:
		mrr["bay"] = 0
		used_bays[0] = true
	out.append({"main": true, "frame": mf, "w": main_w, "h": main_h, "region": mrr})
	for k in range(n_side):
		var sfr: Dictionary
		var side_bay := -1
		if is_cyl:
			var theta := PI * 0.5 + TAU * float(k + 1) / float(n_side + 1)
			if snap_drum:
				side_bay = wrapi(int(round((theta - PI * 0.5) / dtheta)), 0, bays)
				if used_bays.has(side_bay):
					continue   # bay already holds a door — drop this side entrance
				used_bays[side_bay] = true
				theta = PI * 0.5 + float(side_bay) * dtheta
			sfr = _door_frame_cyl(radius, theta)
		else:
			sfr = _door_frame_face(faces[1 + (k % 3)], 0.0)
		var srr := _reserve_region(is_cyl, radius, sfr, side_w, side_h, jamb, margin, "door_side_%d" % k)
		if side_bay >= 0:
			srr["bay"] = side_bay
		out.append({"main": false, "frame": sfr, "w": side_w, "h": side_h, "region": srr})
	return out

# The four vertical wall faces of a box plan (base at y=0): centre, in-plane U, outward normal, w, h.
static func _wall_faces(size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var my := size.y * 0.5
	return [
		{"c": Vector3(0, my, hz), "u": Vector3(1, 0, 0), "n": Vector3(0, 0, 1), "w": size.x, "h": size.y},
		{"c": Vector3(0, my, -hz), "u": Vector3(-1, 0, 0), "n": Vector3(0, 0, -1), "w": size.x, "h": size.y},
		{"c": Vector3(hx, my, 0), "u": Vector3(0, 0, -1), "n": Vector3(1, 0, 0), "w": size.z, "h": size.y},
		{"c": Vector3(-hx, my, 0), "u": Vector3(0, 0, 1), "n": Vector3(-1, 0, 0), "w": size.z, "h": size.y},
	]

# A right-handed door frame (u x v = n) on the ground at the drum wall, at absolute angle `theta`.
static func _door_frame_cyl(radius: float, theta: float) -> Dictionary:
	var n := Vector3(cos(theta), 0.0, sin(theta))
	var v := Vector3(0, 1, 0)
	return {"anchor": n * radius, "u": v.cross(n).normalized(), "v": v, "n": n}

# A right-handed door frame on a box wall face (from _wall_faces) at lateral offset `lateral`.
static func _door_frame_face(face: Dictionary, lateral: float) -> Dictionary:
	var c: Vector3 = face["c"]
	var uf: Vector3 = face["u"]
	var n: Vector3 = face["n"]
	var v := Vector3(0, 1, 0)
	return {"anchor": Vector3(c.x, 0.0, c.z) + uf * lateral, "u": v.cross(n).normalized(), "v": v, "n": n}

# A door region carries TWO extents: the OPENING (open_*, = the actual door size — the base mesh cuts
# EXACTLY this so the frame sits on solid wall at the rim, not floating in an oversized hole) and the
# CLEARANCE (half_*/y_top, = door + frame + margin — what the lattice keeps clear).
static func _reserve_region(is_cyl: bool, radius: float, frame: Dictionary, door_w: float,
		door_h: float, jamb: float, margin: float, id: String) -> Dictionary:
	var n: Vector3 = frame["n"]
	var clear := door_w * 0.5 + jamb + margin
	var clear_y := door_h + jamb + margin
	if is_cyl:
		return {"id": id, "type": "opening", "cyl": true, "theta": atan2(n.z, n.x),
			"open_half_arc": (door_w * 0.5) / radius, "open_y_top": door_h,
			"half_arc": clear / radius, "y_top": clear_y, "y0": 0.0, "y1": clear_y}
	return {"id": id, "type": "opening", "cyl": false, "n": n, "x_center": 0.0,
		"open_half_w": door_w * 0.5, "open_y_top": door_h,
		"half_w": clear, "y_top": clear_y, "y0": 0.0, "y1": clear_y}

static func _n_name(n: Vector3) -> String:
	if absf(n.z) > 0.5:
		return "front" if n.z > 0.0 else "back"
	return "right" if n.x > 0.0 else "left"


# ============================================================================================
# VALIDATE — every silent failure mode becomes a loud string (empty result = a clean survey)
# ============================================================================================

func validate() -> Array[String]:
	var problems: Array[String] = []
	_validate_datums(problems)
	_validate_profile(problems)
	for r_v in reservations:
		_validate_reservation(r_v as Dictionary, problems)
	_validate_overlaps(problems)
	for s_v in sockets:
		_validate_socket(s_v as Dictionary, problems)
	return problems

func _validate_datums(problems: Array[String]) -> void:
	var plinth := float(datums["plinth"])
	var eave := float(datums["eave"])
	var crown := float(datums["crown"])
	if absf(crown - _height_total()) > 0.1:
		problems.append("%s: crown datum %.2f != massing height %.2f — the survey no longer traces the envelope" % [kind, crown, _height_total()])
	if plinth < -EPS or eave <= plinth or eave > crown + EPS:
		problems.append("%s: datum ladder broken (plinth %.2f <= eave %.2f <= crown %.2f must hold)" % [kind, plinth, eave, crown])
	var prev := plinth
	for s_v in (datums["storeys"] as Array):
		var s := float(s_v)
		if s <= prev + EPS:
			problems.append("%s: storey datum %.2f does not ascend past %.2f" % [kind, s, prev])
		if s > eave + 0.05:
			problems.append("%s: storey datum %.2f rises past the eave %.2f" % [kind, s, eave])
		prev = s

func _validate_profile(problems: Array[String]) -> void:
	var crown := float(datums["crown"])
	if profile.size() < 2:
		problems.append("%s: silhouette profile has %d control points — survey the silhouette before construction" % [kind, profile.size()])
		return
	var prev_y := -INF
	for p_v in profile:
		var p := p_v as Dictionary
		var y := float(p["y"])
		if y < prev_y - 0.0001:
			problems.append("%s: profile control point at y=%.2f breaks ascending order" % [kind, y])
		prev_y = y
		if _point_r(p) <= 0.0:
			problems.append("%s: profile radius/extent at y=%.2f is not positive" % [kind, y])
	if float((profile[0] as Dictionary)["y"]) > EPS:
		problems.append("%s: profile does not start at the ground (first y=%.2f)" % [kind, float((profile[0] as Dictionary)["y"])])
	if float((profile[profile.size() - 1] as Dictionary)["y"]) < crown - 0.05:
		problems.append("%s: profile stops at y=%.2f, below the crown %.2f" % [kind, float((profile[profile.size() - 1] as Dictionary)["y"]), crown])

func _validate_reservation(r: Dictionary, problems: Array[String]) -> void:
	var id := str(r.get("id", "?"))
	var crown := float(datums["crown"])
	var y0 := float(r.get("y0", 0.0))
	var y1 := float(r.get("y1", 0.0))
	if y1 <= y0:
		problems.append("%s: reservation '%s' has an empty height band (%.2f..%.2f)" % [kind, id, y0, y1])
	if y0 < -EPS or y1 > crown + 0.5:
		problems.append("%s: reservation '%s' leaves the building (band %.2f..%.2f, crown %.2f)" % [kind, id, y0, y1, crown])
	var on_drum := str(plan.get("kind", "")) == "drum"
	if bool(r.get("cyl", false)) and not on_drum:
		problems.append("%s: reservation '%s' is a drum arc on a box plan" % [kind, id])
	if not bool(r.get("cyl", false)) and r.has("n") and on_drum:
		problems.append("%s: reservation '%s' is a box face claim on a drum plan" % [kind, id])
	if str(r.get("type", "")) == "opening":
		var open_top := float(r.get("open_y_top", y1))
		# the wall the opening cuts must EXIST across the whole opening: the silhouette may not fall
		# inside the door plane below the lintel (the melted-tier door bug this check exists for)
		if on_drum:
			var wall_r := float(plan.get("wall_radius", plan.get("radius", 2.0)))
			for t in range(5):
				var yy := lerpf(y0, open_top, float(t) / 4.0)
				if radius_at(yy) < wall_r - 0.05:
					problems.append("%s: opening '%s' rises past its wall — silhouette %.2f falls inside the door plane %.2f at y=%.2f (fold the door into the wall band)" % [kind, id, radius_at(yy), wall_r, yy])
					break
		elif str(spec.get("composite", "")) != "open_files_awnings" and r.has("n"):
			# (the awning stack is exempt: its layout enforces door_clear_y on the ground facade,
			# and the survey's straight-taper profile under-reads the stepped skirts near ground)
			var nrm := r["n"] as Vector3
			var face_hw := _face_half_width(nrm)
			if face_hw <= 0.0:
				problems.append("%s: opening '%s' faces %s but no plan wall face does" % [kind, id, str(nrm)])
			elif absf(float(r.get("x_center", 0.0))) + float(r.get("open_half_w", 0.5)) > face_hw + EPS:
				problems.append("%s: opening '%s' runs off its wall face (|%.2f|+%.2f > %.2f)" % [kind, id, float(r.get("x_center", 0.0)), float(r.get("open_half_w", 0.5)), face_hw])
			else:
				var plane_d := _wall_plane_dist(nrm)
				for t in range(5):
					var yy2 := lerpf(y0, open_top, float(t) / 4.0)
					var he := half_extents_at(yy2)
					var ext := he.y if absf(nrm.z) > 0.5 else he.x
					if ext < plane_d - 0.05:
						problems.append("%s: opening '%s' rises past its wall — the silhouette falls inside the door plane at y=%.2f (fold the door into the wall band)" % [kind, id, yy2])
						break

# distance from the plan centre to the wall plane the reservation's normal points through
func _wall_plane_dist(n: Vector3) -> float:
	var he: Vector2 = plan.get("half_extents", Vector2(2, 2))
	return he.y if absf(n.z) > 0.5 else he.x

# the half-width of the plan wall face the normal points through (0 = no such face)
func _face_half_width(n: Vector3) -> float:
	for f_v in (plan.get("faces", []) as Array):
		if ((f_v as Dictionary)["n"] as Vector3).dot(n) > 0.9:
			return float((f_v as Dictionary)["w"]) * 0.5
	return 0.0

func _validate_overlaps(problems: Array[String]) -> void:
	for i in range(reservations.size()):
		for j in range(i + 1, reservations.size()):
			var a := reservations[i] as Dictionary
			var b := reservations[j] as Dictionary
			if not _res_overlap(a, b):
				continue
			var ta := str(a.get("type", ""))
			var tb := str(b.get("type", ""))
			var ida := str(a.get("id", "?"))
			var idb := str(b.get("id", "?"))
			if ta == "opening" and tb == "opening":
				problems.append("%s: openings '%s' and '%s' claim the same wall — reconcile the plan grid before meshing" % [kind, ida, idb])
			elif ta == "opening" or tb == "opening":
				var field := b if ta == "opening" else a
				var open_id := ida if ta == "opening" else idb
				if not (field.get("keeps_clear", []) as Array).has(open_id):
					problems.append("%s: '%s' overlaps opening '%s' without keeping it clear — restructure the field around the reservation or fold the part into the base" % [kind, str(field.get("id", "?")), open_id])
			else:
				problems.append("%s: '%s' and '%s' both claim the same wall band — reconcile at the survey" % [kind, ida, idb])

# Two reservations overlap when they share a wall AND their height bands AND lateral spans intersect.
func _res_overlap(a: Dictionary, b: Dictionary) -> bool:
	if float(a.get("y0", 0.0)) >= float(b.get("y1", 0.0)) - EPS \
			or float(b.get("y0", 0.0)) >= float(a.get("y1", 0.0)) - EPS:
		return false
	var a_ring := bool(a.get("ring", false))
	var b_ring := bool(b.get("ring", false))
	if a_ring or b_ring:
		return true   # a full-perimeter band shares every wall at its height
	var a_cyl := bool(a.get("cyl", false))
	var b_cyl := bool(b.get("cyl", false))
	if a_cyl != b_cyl:
		return false   # different wall languages = different walls
	if a_cyl:
		var dth := absf(fposmod(float(a["theta"]) - float(b["theta"]) + PI, TAU) - PI)
		return dth < float(a["half_arc"]) + float(b["half_arc"]) - EPS
	if not (a.has("n") and b.has("n")):
		return false
	if (a["n"] as Vector3).dot(b["n"] as Vector3) < 0.9:
		return false
	return absf(float(a.get("x_center", 0.0)) - float(b.get("x_center", 0.0))) \
		< float(a.get("half_w", 0.0)) + float(b.get("half_w", 0.0)) - EPS

func _validate_socket(s: Dictionary, problems: Array[String]) -> void:
	var skind := str(s.get("kind", "?"))
	var pos: Vector3 = s.get("pos", Vector3.ZERO)
	var crown := float(datums["crown"])
	if pos.y < -0.5 or pos.y > crown + 1.0:
		problems.append("%s: %s socket floats off the building (y=%.2f, crown %.2f)" % [kind, skind, pos.y, crown])
		return
	var horiz := Vector2(pos.x, pos.z)
	match skind:
		"weak_point":
			if str(spec.get("composite", "")) == "open_files_awnings":
				if horiz.length() > _footprint():
					problems.append("%s: weak point off the awning stack (%.2f out)" % [kind, horiz.length()])
			elif str(plan.get("kind", "")) == "drum":
				if absf(horiz.length() - radius_at(pos.y)) > 0.2:
					problems.append("%s: weak point floats off the silhouette (|xz|=%.2f, profile %.2f at y=%.2f)" % [kind, horiz.length(), radius_at(pos.y), pos.y])
			else:
				var he := half_extents_at(pos.y)
				var on_x := absf(absf(pos.x) - he.x) <= 0.25 and absf(pos.z) <= he.y + 0.25
				var on_z := absf(absf(pos.z) - he.y) <= 0.25 and absf(pos.x) <= he.x + 0.25
				if not (on_x or on_z):
					problems.append("%s: weak point floats off the wall planes (%.2f, %.2f vs %.2f x %.2f at y=%.2f)" % [kind, pos.x, pos.z, he.x, he.y, pos.y])
		"door", "road":
			if pos.y > 0.3:
				problems.append("%s: %s socket is not at the threshold (y=%.2f)" % [kind, skind, pos.y])
			if str(plan.get("kind", "")) == "drum":
				var wall_r := float(plan.get("wall_radius", plan.get("radius", 2.0)))
				if absf(horiz.length() - wall_r) > 0.3:
					problems.append("%s: %s socket off the door wall (|xz|=%.2f, wall %.2f)" % [kind, skind, horiz.length(), wall_r])
			else:
				var he2 := half_extents_at(0.5)
				var on_x2 := absf(absf(pos.x) - he2.x) <= 0.3 and absf(pos.z) <= he2.y + 0.3
				var on_z2 := absf(absf(pos.z) - he2.y) <= 0.3 and absf(pos.x) <= he2.x + 0.3
				if not (on_x2 or on_z2):
					problems.append("%s: %s socket floats off the wall planes" % [kind, skind])
		"bridge":
			if not bool(s.get("lane", false)) and horiz.length() > _footprint() + 1.0:
				problems.append("%s: bridge socket floats %.2f out from a %.2f footprint" % [kind, horiz.length(), _footprint()])
		"balcony":
			var ledges: Array = BaseShapeBuilder.tier_ledges(spec)
			var on_ledge := false
			for lg in ledges:
				if absf(float((lg as Dictionary)["y"]) - pos.y) <= 0.1:
					on_ledge = true
			if not on_ledge:
				problems.append("%s: balcony slot at y=%.2f sits on no tier-ledge datum" % [kind, pos.y])
