class_name CreatureGrammar
extends RefCounted

## BODY GRAMMAR for procedural creatures. A creature is grown as a graph of PARTS — spine chains,
## radial palps, limb pairs, lumps, sensors — each part sampling its dimensions from ranges (the
## same philosophy as the level FragmentGrammar) and emitting SDF PRIMITIVES with per-joint blend
## radii. `SdfMesher` then smooth-min blends the primitives into one organic mesh: fat k at torso
## joints melts masses together, small k at spikes and conoids keeps them sharp.
##
## ARCHETYPES ARE CANON-GROUNDED (reference-docs/fauna_roster.md — consulted, not invented):
##   sapscrap  — three-palp C3-symmetric scrap-sized body; ONE palp tip glows (the clamp tell).
##   hidra     — segmented HELIX ("iron-cage propeller"); rests coiled, the last segments UNSPOOL
##               into the strike pose.
##   meeb      — amoeboid mass of soft lumps + pseudopods; FOOD-CUPS glow across the surface.
##   toxo      — crescent body tapering to an apical CONOID spike (the invasion complex).
##   gnawer    — canon gives only BITE + heme-red pigment; the low quadruped silhouette here is a
##               PROPOSAL for the director (pack pursuit implies a runner's body), colours canonical.
##
## Deterministic: every draw rides SeededRng streams (house call() form — the wall-clock RNG lint
## sees no bare engine call sites). Same seed + archetype = the same creature, byte for byte.

const ARCHETYPES := ["sapscrap", "hidra", "meeb", "toxo", "gnawer"]

const GLOW_GREEN := Color(0.36, 0.91, 0.50)
const GLOW_AMBER := Color(0.95, 0.64, 0.28)
const EYE_RED := Color(0.95, 0.25, 0.18)

static func _rng(seed_value: int, ns: String) -> SeededRng:
	return SeededRng.new((seed_value ^ (hash(ns) & 0x7fffffff)))

static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _rf(rng: SeededRng) -> float:
	return float(rng.call("randf"))

static func _rr(rng: SeededRng, lo: float, hi: float) -> float:
	return lo + _rf(rng) * (hi - lo)

## Generate one creature. Returns:
## {"prims": Array (SdfMesher primitives), "glows": [{pos, r, color, energy}],
##  "name": String, "color": Color, "archetype": String}
static func generate(seed_value: int, archetype: String = "") -> Dictionary:
	var kind := archetype
	if kind == "" or not ARCHETYPES.has(kind):
		kind = ARCHETYPES[_ri(_rng(seed_value, "crt:pick"), 0, ARCHETYPES.size() - 1)]
	var rng := _rng(seed_value, "crt:%s" % kind)
	var out: Dictionary
	match kind:
		"sapscrap": out = _sapscrap(rng)
		"hidra": out = _hidra(rng)
		"meeb": out = _meeb(rng)
		"toxo": out = _toxo(rng)
		_: out = _gnawer(rng)
	out["archetype"] = kind
	_drop_to_ground(out)
	return out

# --- primitive constructors ---

static func _cap(prims: Array, a: Vector3, b: Vector3, r1: float, r2: float, k: float) -> void:
	prims.append({"type": "capsule", "a": a, "b": b, "r1": r1, "r2": r2, "k": k})

static func _ell(prims: Array, c: Vector3, r: Vector3, k: float) -> void:
	prims.append({"type": "ellipsoid", "c": c, "r": r, "k": k})

static func _sph(prims: Array, c: Vector3, r: float, k: float) -> void:
	prims.append({"type": "sphere", "c": c, "r1": r, "k": k})

## Mirror every primitive appended after `from_idx` across the X=0 plane (bilateral parts).
static func _mirror_x(prims: Array, from_idx: int) -> void:
	for i in range(from_idx, prims.size()):
		var pr: Dictionary = (prims[i] as Dictionary).duplicate()
		if pr.has("a"):
			var a: Vector3 = pr["a"]; var b: Vector3 = pr["b"]
			pr["a"] = Vector3(-a.x, a.y, a.z)
			pr["b"] = Vector3(-b.x, b.y, b.z)
		if pr.has("c"):
			var c: Vector3 = pr["c"]
			pr["c"] = Vector3(-c.x, c.y, c.z)
		prims.append(pr)

# --- archetype builders ---

## Sapscrap: small central body, three palps at ~120° (C3 symmetry with jitter), one palp lifted
## with a glowing tip — the canon clamp tell.
static func _sapscrap(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var core_r := _rr(rng, 0.14, 0.2)
	var core := Vector3(0, core_r + 0.12, 0)
	_sph(prims, core, core_r, 0.06)
	_ell(prims, core + Vector3(0, core_r * 0.5, 0), Vector3(core_r * 0.7, core_r * 0.45, core_r * 0.7), 0.06)
	var tell_palp := _ri(rng, 0, 2)
	for i in range(3):
		var ang := TAU * float(i) / 3.0 + _rr(rng, -0.25, 0.25)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var lift := 0.34 if i == tell_palp else _rr(rng, -0.08, 0.05)
		var reach := _rr(rng, 0.34, 0.48)
		var elbow := core + dir * reach * 0.55 + Vector3(0, lift * 0.6, 0)
		var tip := core + dir * reach + Vector3(0, lift - 0.1, 0)
		var r0 := core_r * 0.42
		_cap(prims, core + dir * core_r * 0.5, elbow, r0, r0 * 0.75, 0.045)
		_cap(prims, elbow, tip, r0 * 0.75, r0 * 0.4, 0.04)
		# clamp jaws: two short prongs past the tip
		var side := dir.cross(Vector3.UP).normalized() * r0 * 0.5
		_cap(prims, tip, tip + dir * 0.08 + side, r0 * 0.35, r0 * 0.12, 0.025)
		_cap(prims, tip, tip + dir * 0.08 - side, r0 * 0.35, r0 * 0.12, 0.025)
		if i == tell_palp:
			glows.append({"pos": tip + dir * 0.05, "r": 0.045, "color": GLOW_AMBER, "energy": 1.5})
	return {"prims": prims, "glows": glows, "name": "Sapscrap",
		"color": Color(0.46, 0.41, 0.33).darkened(_rf(rng) * 0.08)}

## Hidra: a helical segment tube (iron-cage propeller) — coiled at rest, with the head end
## unspooling outward into the strike pose. Two small red sensor glows at the head.
static func _hidra(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var segs := _ri(rng, 9, 13)
	var helix_r := _rr(rng, 0.24, 0.36)
	var pitch := _rr(rng, 0.11, 0.16)
	var body_r := _rr(rng, 0.09, 0.13)
	var unspool := _ri(rng, 2, 4)
	var pts: Array = []
	var prev := Vector3.ZERO
	for i in range(segs + 1):
		var t := float(i)
		var p: Vector3
		if i <= segs - unspool:
			var ang := t * 1.05
			p = Vector3(cos(ang) * helix_r, 0.16 + t * pitch, sin(ang) * helix_r)
		else:
			# the unspooled head segments straighten out and rear up
			var straight := t - float(segs - unspool)
			p = prev + Vector3(0.16, 0.10 + straight * 0.03, 0.12).normalized() * (pitch + helix_r * 0.5)
		pts.append(p)
		prev = p
	for i in range(pts.size() - 1):
		var tt := float(i) / float(pts.size() - 1)
		var r := lerpf(body_r * 0.55, body_r, sin(tt * PI) * 0.6 + 0.4)
		_cap(prims, pts[i], pts[i + 1], r, r * 0.95, 0.085)
	# head wedge on the unspooled end
	var head: Vector3 = pts[pts.size() - 1]
	var neck: Vector3 = pts[pts.size() - 2]
	var fwd: Vector3 = (head - neck).normalized()
	_ell(prims, head + fwd * 0.08, Vector3(body_r * 1.4, body_r * 1.05, body_r * 1.15), 0.06)
	var side2 := fwd.cross(Vector3.UP).normalized()
	for s: float in [-1.0, 1.0]:
		glows.append({"pos": head + fwd * 0.16 + side2 * body_r * 0.55 * s + Vector3(0, body_r * 0.3, 0),
			"r": 0.03, "color": EYE_RED, "energy": 1.6})
	return {"prims": prims, "glows": glows, "name": "Hidra",
		"color": Color(0.30, 0.29, 0.32).darkened(_rf(rng) * 0.06)}

## Meeb: amoeboid — a handful of soft-blended lumps oozing into pseudopods, food-cups glowing
## across the surface (the suction tell).
static func _meeb(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var lumps := _ri(rng, 3, 5)
	var centers: Array = []
	for i in range(lumps):
		var c := Vector3(_rr(rng, -0.28, 0.28), _rr(rng, 0.18, 0.34), _rr(rng, -0.24, 0.24))
		var r := Vector3(_rr(rng, 0.22, 0.4), _rr(rng, 0.16, 0.26), _rr(rng, 0.22, 0.36))
		_ell(prims, c, r, 0.18)
		centers.append({"c": c, "r": r})
	var pods := _ri(rng, 2, 4)
	for i in range(pods):
		var ang := TAU * float(i) / float(pods) + _rr(rng, -0.5, 0.5)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var src: Dictionary = centers[_ri(rng, 0, centers.size() - 1)]
		var start: Vector3 = src["c"] + dir * (src["r"] as Vector3).x * 0.6
		var tip := start + dir * _rr(rng, 0.25, 0.45) + Vector3(0, -float(start.y) * 0.7, 0)
		_cap(prims, start, tip, _rr(rng, 0.1, 0.16), _rr(rng, 0.05, 0.09), 0.15)
	var cups := _ri(rng, 3, 6)
	for i in range(cups):
		var src2: Dictionary = centers[_ri(rng, 0, centers.size() - 1)]
		var n := Vector3(_rr(rng, -1, 1), _rr(rng, 0.1, 1), _rr(rng, -1, 1)).normalized()
		var sr: Vector3 = src2["r"]
		var pos: Vector3 = src2["c"] + Vector3(n.x * sr.x, n.y * sr.y, n.z * sr.z) * 0.92
		glows.append({"pos": pos, "r": _rr(rng, 0.03, 0.05), "color": GLOW_AMBER, "energy": 1.1})
	return {"prims": prims, "glows": glows, "name": "Meeb",
		"color": Color(0.55, 0.52, 0.43).darkened(_rf(rng) * 0.1)}

## Toxo: crescent body — an arc of tapering segments — ending in the sharp apical conoid.
static func _toxo(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var segs := _ri(rng, 4, 6)
	var arc := _rr(rng, 1.4, 2.0)
	var rad := _rr(rng, 0.34, 0.5)
	var thick := _rr(rng, 0.11, 0.15)
	var pts: Array = []
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var ang := -arc * 0.5 + arc * t
		pts.append(Vector3(sin(ang) * rad, thick + 0.05 + cos(ang) * rad * 0.35, 0))
	for i in range(segs):
		var t2 := float(i) / float(segs)
		_cap(prims, pts[i], pts[i + 1], lerpf(thick, thick * 0.45, t2), lerpf(thick, thick * 0.45, t2 + 1.0 / segs), 0.07)
	# apical conoid: a sharp spike extending the thin end
	var tipd: Vector3 = (pts[segs] - pts[segs - 1]).normalized()
	var conoid_tip: Vector3 = pts[segs] + tipd * _rr(rng, 0.14, 0.2)
	_cap(prims, pts[segs], conoid_tip, thick * 0.4, 0.012, 0.02)
	glows.append({"pos": conoid_tip, "r": 0.022, "color": Color(0.8, 0.85, 0.7), "energy": 0.9})
	return {"prims": prims, "glows": glows, "name": "Toxo",
		"color": Color(0.52, 0.47, 0.37).darkened(_rf(rng) * 0.1)}

## Gnawer (PROPOSED silhouette — canon states only bite + heme-red pigment + pack pursuit):
## a low-slung quadruped runner: tapered torso, blunt head with an offset under-jaw, four
## mirrored two-segment legs, short tail. Heme-red, paired red eye glows.
static func _gnawer(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var body_h := _rr(rng, 0.34, 0.46)
	var body_len := _rr(rng, 0.55, 0.8)
	var chest_r := _rr(rng, 0.17, 0.23)
	# torso: chest + belly + hip, melted together
	_ell(prims, Vector3(0, body_h, body_len * 0.28), Vector3(chest_r, chest_r * 0.92, body_len * 0.34), 0.1)
	_ell(prims, Vector3(0, body_h * 0.94, -body_len * 0.1), Vector3(chest_r * 0.88, chest_r * 0.8, body_len * 0.3), 0.1)
	_ell(prims, Vector3(0, body_h * 0.96, -body_len * 0.42), Vector3(chest_r * 0.7, chest_r * 0.68, body_len * 0.2), 0.09)
	# head + snout + under-jaw (the bite)
	var head_c := Vector3(0, body_h * 1.06, body_len * 0.62)
	_ell(prims, head_c, Vector3(chest_r * 0.62, chest_r * 0.58, chest_r * 0.72), 0.07)
	var snout_tip := head_c + Vector3(0, -0.04, chest_r * 1.05)
	_cap(prims, head_c + Vector3(0, -0.02, chest_r * 0.3), snout_tip, chest_r * 0.4, chest_r * 0.22, 0.05)
	_cap(prims, head_c + Vector3(0, -chest_r * 0.42, chest_r * 0.2),
		snout_tip + Vector3(0, -chest_r * 0.34, 0.02), chest_r * 0.26, chest_r * 0.12, 0.03)
	# tail
	var hip := Vector3(0, body_h * 0.98, -body_len * 0.5)
	var tail_mid := hip + Vector3(0, _rr(rng, 0.0, 0.1), -_rr(rng, 0.18, 0.26))
	_cap(prims, hip, tail_mid, chest_r * 0.4, chest_r * 0.22, 0.06)
	_cap(prims, tail_mid, tail_mid + Vector3(0, -0.02, -_rr(rng, 0.14, 0.22)), chest_r * 0.22, chest_r * 0.08, 0.04)
	# legs (one side, mirrored): front + rear pairs, two segments each
	var mirror_from := prims.size()
	var leg_r := chest_r * 0.3
	var stance := _rr(rng, 0.05, 0.12)
	for zoff: float in [body_len * 0.3, -body_len * 0.36]:
		var hip_p := Vector3(chest_r * 0.72, body_h * 0.9, zoff)
		var knee := hip_p + Vector3(stance, -body_h * 0.45, _rr(rng, -0.06, 0.02))
		var foot := Vector3(knee.x + stance * 0.4, 0.05, knee.z + _rr(rng, -0.03, 0.05))
		_cap(prims, hip_p, knee, leg_r, leg_r * 0.7, 0.06)
		_cap(prims, knee, foot, leg_r * 0.7, leg_r * 0.5, 0.04)
	_mirror_x(prims, mirror_from)
	for s: float in [-1.0, 1.0]:
		glows.append({"pos": head_c + Vector3(chest_r * 0.34 * s, chest_r * 0.22, chest_r * 0.5),
			"r": 0.028, "color": EYE_RED, "energy": 1.7})
	return {"prims": prims, "glows": glows, "name": "Gnawer (proposed)",
		"color": Color(0.48, 0.19, 0.15).darkened(_rf(rng) * 0.08)}

# --- shared post-pass: rest the body on the ground plane ---

static func _drop_to_ground(out: Dictionary) -> void:
	var min_y := 1.0e9
	for pr in out["prims"]:
		var pd := pr as Dictionary
		match str(pd.get("type", "")):
			"capsule":
				min_y = minf(min_y, minf((pd["a"] as Vector3).y, (pd["b"] as Vector3).y)
					- maxf(float(pd.get("r1", 0.1)), float(pd.get("r2", 0.1))))
			"ellipsoid":
				min_y = minf(min_y, (pd["c"] as Vector3).y - (pd["r"] as Vector3).y)
			_:
				min_y = minf(min_y, (pd["c"] as Vector3).y - float(pd.get("r1", 0.1)))
	var dy := 0.02 - min_y
	for pr in out["prims"]:
		var pd := pr as Dictionary
		if pd.has("a"):
			pd["a"] = (pd["a"] as Vector3) + Vector3(0, dy, 0)
			pd["b"] = (pd["b"] as Vector3) + Vector3(0, dy, 0)
		if pd.has("c"):
			pd["c"] = (pd["c"] as Vector3) + Vector3(0, dy, 0)
	for g in out["glows"]:
		(g as Dictionary)["pos"] = ((g as Dictionary)["pos"] as Vector3) + Vector3(0, dy, 0)
