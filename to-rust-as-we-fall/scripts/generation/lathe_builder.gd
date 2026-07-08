class_name LatheBuilder
extends RefCounted

## Faceted RING-LOFT tower meshes — the runtime answer to the architecture reference set, which is
## revolve-shaped, never rectangular (see reference-images/architecture/): the Plumbing drum's lobed
## flared base swelling into a domed cap, Greenfields' stacked scalloped bands, Open Files' deep
## vertical flutes converging into a spire crown. A tower is a stack of RINGS, each a lobed n-gon
## (radius modulated by cos(lobes*theta)), lofted into flat-shaded facets ("curves realized via
## facets" — the anti-grid law). Windows are a second EMISSIVE surface: arched slot quads sitting
## just proud of the shell, wrapped around the curve.
##
## Data-in, mesh-out: `make_profile(plan)` turns a filler PLAN (pure data, deterministic per seed)
## into rings + windows; `build(profile)` lofts the ArrayMesh. The fragment loader owns the nodes.

const FLOOR_H := 2.6

static func _rng(seed_value: int, ns: String) -> SeededRng:
	return SeededRng.new((seed_value ^ (hash(ns) & 0x7fffffff)))

static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _rf(rng: SeededRng) -> float:
	return float(rng.call("randf"))

static func _rr(rng: SeededRng, lo: float, hi: float) -> float:
	return lo + _rf(rng) * (hi - lo)

const GLOW_GREEN := Color(0.36, 0.91, 0.50)
const GLOW_WARM := Color(0.95, 0.64, 0.32)

## plan: {center: Vector3, base_r: float, height: float, archetype: "drum"|"banded"|"ribbed",
##        seed: int, warm_bias: float, glow_density: float, decay: float}
## -> profile {center, segments, rings: [{y, r, lobes, amp, phase, squash}], cap, cupola,
##             windows: [{y, h, step, color, energy}], max_r}
static func make_profile(plan: Dictionary) -> Dictionary:
	var rng := _rng(int(plan["seed"]), "lathe:%d,%d" % [int((plan["center"] as Vector3).x * 10.0),
		int((plan["center"] as Vector3).z * 10.0)])
	var kind := str(plan.get("archetype", "drum"))
	var base_r := float(plan["base_r"])
	var height := float(plan["height"])
	var decay := float(plan.get("decay", 0.3))
	var glow := float(plan.get("glow_density", 0.5))
	var warm := float(plan.get("warm_bias", 0.5))
	var rings: Array = []
	var windows: Array = []
	var cap := "flat"
	var cupola := false
	var phase := _rf(rng) * TAU
	var squash := _rr(rng, 0.82, 1.0)
	var max_r := 0.0
	match kind:
		"banded":
			# stacked scalloped storey bands, soft 4-lobed plan, slight overhang growth per band
			var bands := clampi(int(round(height / FLOOR_H)), 2, 5)
			var lobes := 4
			var amp := _rr(rng, 0.05, 0.10)
			for b in range(bands):
				var y0 := height * float(b) / float(bands)
				var y1 := height * float(b + 1) / float(bands)
				var grow := 1.0 + 0.05 * float(b)   # upper bands billow slightly OVER the lower
				rings.append({"y": y0 + 0.06, "r": base_r * 0.88 * grow, "lobes": lobes, "amp": amp, "phase": phase, "squash": squash})
				rings.append({"y": (y0 + y1) * 0.5, "r": base_r * grow, "lobes": lobes, "amp": amp, "phase": phase, "squash": squash})
				rings.append({"y": y1 - 0.04, "r": base_r * 0.9 * grow, "lobes": lobes, "amp": amp, "phase": phase, "squash": squash})
				windows.append({"y": (y0 + y1) * 0.5 - 0.55, "h": 1.1, "step": 2,
					"color": GLOW_WARM if _rf(rng) < 0.75 + warm * 0.25 else GLOW_GREEN,
					"energy": (0.85 + _rf(rng) * 0.3) * (1.0 - decay * 0.5)})
			max_r = base_r * (1.0 + 0.05 * float(bands - 1)) * (1.0 + 0.10)
		"ribbed":
			# deep constant flutes, gentle taper, ribs converging into a spire crown
			var lobes2 := _ri(rng, 9, 13)
			var amp2 := _rr(rng, 0.16, 0.24)
			var levels := 5
			for i in range(levels + 1):
				var t := float(i) / float(levels)
				rings.append({"y": height * t, "r": base_r * lerpf(1.0, 0.68, t * t),
					"lobes": lobes2, "amp": amp2, "phase": phase, "squash": squash})
			cap = "spires"
			var wn := clampi(int(round(height / FLOOR_H)) - 1, 1, 5)
			for w2 in range(wn):
				if _rf(rng) > glow + 0.25:
					continue
				windows.append({"y": height * (0.15 + 0.7 * float(w2) / float(maxi(1, wn))), "h": 0.8,
					"step": 3, "color": GLOW_GREEN, "energy": (0.8 + _rf(rng) * 0.4) * (1.0 - decay * 0.5)})
			max_r = base_r * (1.0 + amp2)
		_:
			# drum: lobed flared base (fused buttress roots) fading by mid-height, mid bulge,
			# tapering into a dome with a cupola
			var lobes3 := _ri(rng, 5, 7)
			var base_amp := _rr(rng, 0.16, 0.26)
			var bulge := _rr(rng, 1.04, 1.14)
			rings.append({"y": 0.0, "r": base_r, "lobes": lobes3, "amp": base_amp, "phase": phase, "squash": squash})
			rings.append({"y": height * 0.18, "r": base_r * 0.92, "lobes": lobes3, "amp": base_amp * 0.5, "phase": phase, "squash": squash})
			rings.append({"y": height * 0.45, "r": base_r * bulge * 0.9, "lobes": lobes3, "amp": 0.04, "phase": phase, "squash": squash})
			rings.append({"y": height * 0.7, "r": base_r * 0.86, "lobes": lobes3, "amp": 0.02, "phase": phase, "squash": squash})
			rings.append({"y": height * 0.88, "r": base_r * 0.7, "lobes": lobes3, "amp": 0.0, "phase": phase, "squash": squash})
			cap = "dome"
			cupola = _rf(rng) < 0.6 and decay < 0.6
			var wn2 := clampi(int(round(height / FLOOR_H)) - 1, 1, 4)
			for w3 in range(wn2):
				if _rf(rng) > glow + 0.35:
					continue
				windows.append({"y": height * (0.3 + 0.5 * float(w3) / float(maxi(1, wn2))), "h": 1.0,
					"step": 2, "color": GLOW_GREEN if _rf(rng) < 0.7 - warm * 0.3 else GLOW_WARM,
					"energy": (0.8 + _rf(rng) * 0.4) * (1.0 - decay * 0.5)})
			max_r = base_r * (1.0 + base_amp)
	return {"center": plan["center"], "segments": _ri(rng, 10, 13), "rings": rings, "cap": cap,
		"cupola": cupola, "windows": windows, "max_r": max_r, "height": height}

## SDF capsule-chain SPIRAL coiling around a drum (the Plumbing flume silhouette) — meshed by the
## loader with SdfMesher. World coordinates, deterministic.
static func coil_prims(plan: Dictionary) -> Array:
	var c: Vector3 = plan["center"]
	var rng := _rng(int(plan["seed"]), "lathe:coil")
	var base_r := float(plan["base_r"])
	var height := float(plan["height"])
	var coil_r := base_r * 0.95 + 0.4
	var turns := _rr(rng, 1.1, 1.6)
	var y0 := height * 0.22
	var y1 := height * 0.78
	var steps := 26
	var prims: Array = []
	var prev := Vector3.ZERO
	var a0 := _rf(rng) * TAU
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := a0 + t * turns * TAU
		var p := Vector3(c.x + cos(ang) * coil_r, lerpf(y0, y1, t), c.z + sin(ang) * coil_r)
		if i > 0:
			prims.append({"type": "capsule", "a": prev, "b": p, "r1": 0.3, "r2": 0.3, "k": 0.12})
		prev = p
	return prims

## Loft the profile into an ArrayMesh: surface 0 = the shell (caller assigns the atlas material),
## surface 1 = emissive window quads (material set here). Flat-shaded facets.
static func build(profile: Dictionary) -> Dictionary:
	var rings: Array = profile["rings"]
	if rings.size() < 2:
		return {"mesh": null}
	var center: Vector3 = profile["center"]
	var segments := int(profile["segments"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rings.size() - 1):
		_loft(st, center, rings[i], rings[i + 1], segments)
	var top: Dictionary = rings[rings.size() - 1]
	match str(profile.get("cap", "flat")):
		"dome":
			var dr := top.duplicate()
			var dome_h := float(top["r"]) * 0.75
			for d in range(3):
				var t := float(d + 1) / 3.0
				var nr := dr.duplicate()
				nr["y"] = float(top["y"]) + dome_h * sin(t * PI * 0.5)
				nr["r"] = float(top["r"]) * cos(t * PI * 0.42) + 0.03
				nr["amp"] = 0.0
				_loft(st, center, dr, nr, segments)
				dr = nr
			_fan(st, center, dr, segments)
			if bool(profile.get("cupola", false)):
				var c0 := {"y": float(dr["y"]) - 0.05, "r": 0.4, "lobes": 4, "amp": 0.0, "phase": 0.0, "squash": 1.0}
				var c1 := {"y": float(dr["y"]) + 0.7, "r": 0.32, "lobes": 4, "amp": 0.0, "phase": 0.0, "squash": 1.0}
				_loft(st, center, c0, c1, 6)
				_fan(st, center, c1, 6)
		"spires":
			# the flutes keep rising past the roofline and pinch inward — a crown of spikes
			var sp := top.duplicate()
			sp["y"] = float(top["y"]) + 1.6
			sp["r"] = float(top["r"]) * 0.5
			sp["amp"] = float(top.get("amp", 0.2)) * 2.2
			_loft(st, center, top, sp, segments)
			_fan(st, center, sp, segments)
		_:
			_fan(st, center, top, segments)
	st.generate_normals()
	var mesh := st.commit()

	# window quads — proud of the shell, wrapped segment-by-segment
	var windows: Array = profile.get("windows", [])
	if not windows.is_empty():
		var wt := SurfaceTool.new()
		wt.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		var wcol := Color(1, 1, 1)
		var wenergy := 1.0
		for wd in windows:
			var y_mid := float(wd["y"]) + float(wd["h"]) * 0.5
			var ring_lo: Dictionary = rings[0]
			var ring_hi: Dictionary = rings[rings.size() - 1]
			for i in range(rings.size() - 1):
				if float(rings[i]["y"]) <= y_mid and float(rings[i + 1]["y"]) >= y_mid:
					ring_lo = rings[i]
					ring_hi = rings[i + 1]
					break
			wcol = wd["color"]
			wenergy = float(wd["energy"])
			var step := maxi(1, int(wd["step"]))
			for s in range(0, segments, step):
				var th := (float(s) + 0.5) / float(segments) * TAU
				var rad := _radius_at(ring_lo, ring_hi, y_mid, th) + 0.06
				var half_arc := TAU / float(segments) * 0.28
				var p0 := _cyl(center, th - half_arc, rad, float(wd["y"]))
				var p1 := _cyl(center, th + half_arc, rad, float(wd["y"]))
				var p2 := _cyl(center, th + half_arc, rad, float(wd["y"]) + float(wd["h"]))
				var p3 := _cyl(center, th - half_arc, rad, float(wd["y"]) + float(wd["h"]))
				wt.add_vertex(p0); wt.add_vertex(p2); wt.add_vertex(p1)
				wt.add_vertex(p0); wt.add_vertex(p3); wt.add_vertex(p2)
				any = true
		if any:
			wt.generate_normals()
			var wmesh := wt.commit()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wmesh.surface_get_arrays(0))
			var wmat := StandardMaterial3D.new()
			wmat.albedo_color = Color(0.05, 0.06, 0.05)
			wmat.emission_enabled = true
			wmat.emission = wcol
			wmat.emission_energy_multiplier = wenergy
			mesh.surface_set_material(mesh.get_surface_count() - 1, wmat)
	return {"mesh": mesh}

static func _ring_point(center: Vector3, ring: Dictionary, s: int, segments: int) -> Vector3:
	var th := float(s) / float(segments) * TAU
	var rad := float(ring["r"]) * (1.0 + float(ring.get("amp", 0.0)) * cos(float(ring.get("lobes", 4)) * (th + float(ring.get("phase", 0.0)))))
	return Vector3(center.x + cos(th) * rad, float(ring["y"]), center.z + sin(th) * rad * float(ring.get("squash", 1.0)))

static func _loft(st: SurfaceTool, center: Vector3, ra: Dictionary, rb: Dictionary, segments: int) -> void:
	for s in range(segments):
		var a0 := _ring_point(center, ra, s, segments)
		var a1 := _ring_point(center, ra, s + 1, segments)
		var b0 := _ring_point(center, rb, s, segments)
		var b1 := _ring_point(center, rb, s + 1, segments)
		st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(b1)
		st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(a1)

static func _fan(st: SurfaceTool, center: Vector3, ring: Dictionary, segments: int) -> void:
	var apex := Vector3(center.x, float(ring["y"]) + 0.06, center.z)
	for s in range(segments):
		var p0 := _ring_point(center, ring, s, segments)
		var p1 := _ring_point(center, ring, s + 1, segments)
		st.add_vertex(p0); st.add_vertex(apex); st.add_vertex(p1)

static func _radius_at(ring_lo: Dictionary, ring_hi: Dictionary, y: float, th: float) -> float:
	var y0 := float(ring_lo["y"])
	var y1 := float(ring_hi["y"])
	var t := clampf((y - y0) / maxf(0.001, y1 - y0), 0.0, 1.0)
	var r0 := float(ring_lo["r"]) * (1.0 + float(ring_lo.get("amp", 0.0)) * cos(float(ring_lo.get("lobes", 4)) * (th + float(ring_lo.get("phase", 0.0)))))
	var r1 := float(ring_hi["r"]) * (1.0 + float(ring_hi.get("amp", 0.0)) * cos(float(ring_hi.get("lobes", 4)) * (th + float(ring_hi.get("phase", 0.0)))))
	return lerpf(r0, r1, t)

static func _cyl(center: Vector3, th: float, rad: float, y: float) -> Vector3:
	return Vector3(center.x + cos(th) * rad, y, center.z + sin(th) * rad)
