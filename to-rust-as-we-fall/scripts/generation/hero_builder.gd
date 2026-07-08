class_name HeroBuilder
extends RefCounted

## Named HERO buildings — each district's landmark, decomposed from its reference image
## (reference-images/architecture/) into its actual BASE SHAPES rather than a box. The organic,
## melted, revolve-and-bulge silhouettes are SDF metaball compositions (SdfMesher does the blend),
## plus emissive DETAIL layers (window grids, a helical ramp, a portal) merged into one glowing mesh.
##
## RECIPES (what I actually see in each plate):
##   plumbing   — a gothic CLUSTER COLUMN: ~7 fat vertical lobes flaring into feet with pointed-arch
##                gaps between, a barrel drum, a squashed DOME, a small CUPOLA + finial, and a green
##                HELICAL RAMP screwing around the shaft. Tall slit windows in the recesses.
##   open_files — a BUNDLE of tall tapered FINS of varying height splaying from buttress feet, deep
##                channels between them packed with server-rack WINDOW GRIDS, a pointed crown.
##   hypelines  — a vertical STACK of 3 bulbous spheres (vesicle cluster) with fat TUBES radiating
##                out on branching web legs, pore-windows over the bulbs, an arched toll portal.
##   greenfields— stacked SCALLOPED balcony bands (oblate ellipsoids bulging over each storey),
##                warm arched windows, rooftop greenery. Cream + flora-teal.
##
## Pure data: generate() returns SDF prims + detail specs; body_mesh()/detail_mesh() polygonise them
## (returning Resources, node-free, testable). Deterministic — every draw rides a SeededRng stream.

const ARCHETYPES := ["plumbing", "open_files", "hypelines", "greenfields"]

const GLOW_GREEN := Color(0.36, 0.91, 0.50)
const GLOW_WARM := Color(0.97, 0.66, 0.34)

static func _rng(seed_value: int, ns: String) -> SeededRng:
	return SeededRng.new((seed_value ^ (hash(ns) & 0x7fffffff)))

static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _rf(rng: SeededRng) -> float:
	return float(rng.call("randf"))

static func _rr(rng: SeededRng, lo: float, hi: float) -> float:
	return lo + _rf(rng) * (hi - lo)

## spec: {prims, cell, panels, helices, arches, glows, accent, accent_energy, name, color, tile, height}
static func generate(archetype: String, seed_value: int) -> Dictionary:
	var kind := archetype if ARCHETYPES.has(archetype) else "plumbing"
	var rng := _rng(seed_value, "hero:%s" % kind)
	var spec: Dictionary
	match kind:
		"plumbing": spec = _plumbing(rng)
		"open_files": spec = _open_files(rng)
		"hypelines": spec = _hypelines(rng)
		_: spec = _greenfields(rng)
	spec["name"] = kind
	# defaults so a recipe can omit a layer
	for key in ["panels", "helices", "arches", "glows"]:
		if not spec.has(key):
			spec[key] = []
	if not spec.has("cell"):
		spec["cell"] = 0.16
	# Seat the body on the ground: the fat smooth-min blend pushes the isosurface below the lowest
	# prim centre, so shift everything up until the naive prim minimum clears y=0 with a margin for
	# the blend dip. Keeps the meshed base at/above the plinth (matches the creature ground-drop).
	_ground_hero(spec, 0.5)
	return spec

static func _ground_hero(spec: Dictionary, target: float) -> void:
	var min_y := 1.0e9
	for pr in spec["prims"]:
		var pd := pr as Dictionary
		match str(pd.get("type", "")):
			"capsule":
				min_y = minf(min_y, minf((pd["a"] as Vector3).y, (pd["b"] as Vector3).y)
					- maxf(float(pd.get("r1", 0.1)), float(pd.get("r2", 0.1))))
			"ellipsoid":
				min_y = minf(min_y, (pd["c"] as Vector3).y - (pd["r"] as Vector3).y)
			"box":
				min_y = minf(min_y, (pd["c"] as Vector3).y - (pd["b"] as Vector3).y)
			_:
				min_y = minf(min_y, (pd["c"] as Vector3).y - float(pd.get("r1", 0.1)))
	var dy := target - min_y
	if absf(dy) < 0.001:
		return
	var up := Vector3(0, dy, 0)
	for pr in spec["prims"]:
		var pd := pr as Dictionary
		if pd.has("a"): pd["a"] = (pd["a"] as Vector3) + up
		if pd.has("b") and pd.has("a"): pd["b"] = (pd["b"] as Vector3) + up
		if pd.has("c"): pd["c"] = (pd["c"] as Vector3) + up
	for pn in spec["panels"]: (pn as Dictionary)["c"] = ((pn as Dictionary)["c"] as Vector3) + up
	for hx in spec["helices"]:
		(hx as Dictionary)["y0"] = float((hx as Dictionary)["y0"]) + dy
		(hx as Dictionary)["y1"] = float((hx as Dictionary)["y1"]) + dy
	for ar in spec["arches"]: (ar as Dictionary)["c"] = ((ar as Dictionary)["c"] as Vector3) + up
	for g in spec["glows"]: (g as Dictionary)["pos"] = ((g as Dictionary)["pos"] as Vector3) + up

# ============================================================ RECIPES

static func _plumbing(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var panels: Array = []
	var lobes := _ri(rng, 6, 8)
	var R := _rr(rng, 1.5, 1.8)          # lobe ring radius
	var H := _rr(rng, 7.0, 8.5)
	var phase := _rf(rng) * TAU
	# --- cluster column: each lobe a vertical stack of spheres, fat+splayed at the foot,
	# thinning and drawing inward toward the shoulder. Fat k melts them; the gaps read as ogives.
	for i in range(lobes):
		var ang := phase + TAU * float(i) / float(lobes)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var stack := 5
		for s in range(stack):
			var t := float(s) / float(stack - 1)
			var y := lerpf(0.3, H * 0.6, t)
			var rad := lerpf(R * 1.18, R * 0.5, t)       # splayed foot -> tucked shoulder
			var rr := lerpf(0.62, 0.32, t)
			prims.append({"type": "sphere", "c": dir * rad + Vector3(0, y, 0), "r1": rr, "k": 0.6})
	# central core so the lobes read as attached to a shaft
	prims.append({"type": "capsule", "a": Vector3(0, 0.4, 0), "b": Vector3(0, H * 0.62, 0),
		"r1": R * 0.85, "r2": R * 0.6, "k": 0.6})
	# barrel drum
	prims.append({"type": "ellipsoid", "c": Vector3(0, H * 0.68, 0),
		"r": Vector3(R * 0.95, H * 0.16, R * 0.95), "k": 0.5})
	# squashed dome
	prims.append({"type": "ellipsoid", "c": Vector3(0, H * 0.82, 0),
		"r": Vector3(R * 0.82, H * 0.14, R * 0.82), "k": 0.4})
	# neck + cupola + finial
	prims.append({"type": "capsule", "a": Vector3(0, H * 0.9, 0), "b": Vector3(0, H * 0.97, 0),
		"r1": R * 0.28, "r2": R * 0.26, "k": 0.2})
	prims.append({"type": "ellipsoid", "c": Vector3(0, H * 1.0, 0),
		"r": Vector3(R * 0.34, R * 0.22, R * 0.34), "k": 0.2})
	prims.append({"type": "capsule", "a": Vector3(0, H * 1.02, 0), "b": Vector3(0, H * 1.12, 0),
		"r1": 0.06, "r2": 0.03, "k": 0.05})
	# a couple of side pipes (thin capsules riding the shaft)
	for p in range(2):
		var pa := phase + TAU * (0.2 + 0.55 * float(p))
		var pd := Vector3(cos(pa), 0, sin(pa)) * (R * 1.05)
		prims.append({"type": "capsule", "a": pd + Vector3(0, 0.2, 0), "b": pd + Vector3(0, H * 0.66, 0),
			"r1": 0.14, "r2": 0.12, "k": 0.08})
	# tall slit windows in the recesses between lobes, at two heights
	for i in range(lobes):
		var ang2 := phase + TAU * (float(i) + 0.5) / float(lobes)
		var dir2 := Vector3(cos(ang2), 0, sin(ang2))
		for hh: float in [H * 0.22, H * 0.46]:
			panels.append({"c": dir2 * (R * 1.02) + Vector3(0, hh, 0), "n": dir2,
				"w": 0.28, "h": 1.4, "cols": 1, "rows": 1})
	# green outflow glow at the base
	glows.append({"pos": Vector3(cos(phase) * R * 0.9, 0.5, sin(phase) * R * 0.9), "r": 0.18,
		"color": GLOW_GREEN, "energy": 1.6})
	var helices := [{"center": Vector3.ZERO, "r": R * 1.12, "y0": H * 0.26, "y1": H * 0.72,
		"turns": 1.35, "width": 0.34, "color": GLOW_GREEN, "energy": 1.4}]
	return {"prims": prims, "cell": 0.15, "panels": panels, "helices": helices, "glows": glows,
		"accent": GLOW_GREEN, "accent_energy": 1.3, "height": H,
		"color": Color(0.34, 0.46, 0.47), "tile": "rust_iron"}

static func _open_files(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var panels: Array = []
	var fins := _ri(rng, 9, 12)
	var R := _rr(rng, 1.5, 1.9)
	var H := _rr(rng, 8.0, 10.0)
	var phase := _rf(rng) * TAU
	# central tapered core (the fins cluster around it; channels between fins reach down to it)
	prims.append({"type": "capsule", "a": Vector3(0, 0.4, 0), "b": Vector3(0, H * 0.9, 0),
		"r1": R * 0.72, "r2": R * 0.44, "k": 0.5})
	# fins: tall capsules, splayed at the foot, drawn in and taller toward the centre-front, pointed top
	for i in range(fins):
		var ang := phase + TAU * float(i) / float(fins)
		var dir := Vector3(cos(ang), 0, sin(ang))
		# a triangular height envelope — tallest cluster on one side (the reference's ragged crown)
		var centre_bias := 0.5 + 0.5 * cos(ang - phase)
		var fh := H * lerpf(0.62, 1.0, centre_bias * centre_bias) * _rr(rng, 0.94, 1.06)
		var foot := dir * (R * 1.12) + Vector3(0, 0.2, 0)
		var top := dir * (R * 0.66) + Vector3(0, fh, 0)
		prims.append({"type": "capsule", "a": foot, "b": top, "r1": 0.36, "r2": 0.12, "k": 0.28})
	# server-rack window grids in the channels between fins, up the core, many rows
	for i in range(fins):
		var ang2 := phase + TAU * (float(i) + 0.5) / float(fins)
		var dir2 := Vector3(cos(ang2), 0, sin(ang2))
		panels.append({"c": dir2 * (R * 0.7) + Vector3(0, H * 0.45, 0), "n": dir2,
			"w": 0.5, "h": H * 0.72, "cols": 2, "rows": int(H * 2.2)})
	var arches := [{"c": Vector3(cos(phase), 0, sin(phase)) * (R * 0.95) + Vector3(0, 1.3, 0),
		"n": Vector3(cos(phase), 0, sin(phase)), "w": 1.3, "h": 2.4}]
	return {"prims": prims, "cell": 0.15, "panels": panels, "arches": arches,
		"accent": GLOW_GREEN, "accent_energy": 1.15, "height": H,
		"color": Color(0.37, 0.42, 0.45), "tile": "wall_panel"}

static func _hypelines(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var R := _rr(rng, 1.8, 2.2)
	var stacks := 3
	var ys: Array = []
	var y := R * 0.95
	for s in range(stacks):
		var rr := R * lerpf(1.0, 0.5, float(s) / float(stacks - 1))
		prims.append({"type": "sphere", "c": Vector3(0, y, 0), "r1": rr, "k": 0.7})
		ys.append({"y": y, "r": rr})
		y += rr * 1.35
	var H: float = float((ys[stacks - 1] as Dictionary)["y"]) + R * 0.5
	# radiating tubes from the middle sphere, out + slightly up, on branching web legs
	var tubes := _ri(rng, 4, 6)
	var mid: Dictionary = ys[1]
	var phase := _rf(rng) * TAU
	for i in range(tubes):
		var ang := phase + TAU * float(i) / float(tubes)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var root := dir * float(mid["r"]) * 0.7 + Vector3(0, float(mid["y"]), 0)
		var far := dir * (R * 3.2) + Vector3(0, float(mid["y"]) + R * 0.6, 0)
		prims.append({"type": "capsule", "a": root, "b": far, "r1": 0.4, "r2": 0.34, "k": 0.3})
		# a web leg dropping from the tube to the ground (support)
		var mid_pt := root.lerp(far, 0.62)
		prims.append({"type": "capsule", "a": Vector3(mid_pt.x, 0.2, mid_pt.z), "b": mid_pt,
			"r1": 0.22, "r2": 0.16, "k": 0.2})
		# pore windows on the bulbs along this bearing
		for sd in ys:
			var sph := sd as Dictionary
			glows.append({"pos": dir * float(sph["r"]) * 0.96 + Vector3(0, float(sph["y"]), 0),
				"r": 0.13, "color": GLOW_GREEN, "energy": 1.2})
	var arches := [{"c": Vector3(cos(phase), 0, sin(phase)) * (R * 0.92) + Vector3(0, 1.4, 0),
		"n": Vector3(cos(phase), 0, sin(phase)), "w": 1.5, "h": 2.6}]
	return {"prims": prims, "cell": 0.17, "glows": glows, "arches": arches,
		"accent": GLOW_GREEN, "accent_energy": 1.2, "height": H,
		"color": Color(0.33, 0.43, 0.42), "tile": "rust_iron"}

static func _greenfields(rng: SeededRng) -> Dictionary:
	var prims: Array = []
	var glows: Array = []
	var panels: Array = []
	var bands := _ri(rng, 4, 5)
	var R := _rr(rng, 1.7, 2.0)
	var band_h := _rr(rng, 1.5, 1.8)
	var phase := _rf(rng) * TAU
	var H := 0.0
	for b in range(bands):
		var y := 0.4 + band_h * (float(b) + 0.5)
		var grow := R * (1.0 + 0.04 * float(b))          # each band billows slightly over the last
		# oblate storey band (the scalloped balcony overhang)
		prims.append({"type": "ellipsoid", "c": Vector3(0, y, 0),
			"r": Vector3(grow, band_h * 0.62, grow), "k": 0.45})
		H = y + band_h * 0.6
		# warm arched windows around the band
		var wins := 6
		for wcol in range(wins):
			var wa := phase + TAU * float(wcol) / float(wins)
			var wd := Vector3(cos(wa), 0, sin(wa))
			panels.append({"c": wd * (grow * 1.0) + Vector3(0, y, 0), "n": wd,
				"w": 0.4, "h": 1.0, "cols": 1, "rows": 1})
	# rooftop greenery — small teal plant blobs
	for g in range(7):
		var ga := phase + TAU * float(g) / 7.0
		glows.append({"pos": Vector3(cos(ga), 0, sin(ga)) * R * 0.85 + Vector3(0, H + 0.15, 0),
			"r": 0.16, "color": Color(0.32, 0.78, 0.55), "energy": 0.9})
	return {"prims": prims, "cell": 0.16, "panels": panels, "glows": glows,
		"accent": GLOW_WARM, "accent_energy": 1.0, "height": H,
		"color": Color(0.62, 0.60, 0.5), "tile": "wall_panel"}

# ============================================================ MESHING (node-free; returns Resources)

const MesherRef := preload("res://scripts/generation/sdf_mesher.gd")

## The SDF body. Caller assigns the tinted atlas material to surface 0.
static func body_mesh(spec: Dictionary) -> ArrayMesh:
	var built: Dictionary = MesherRef.build(spec["prims"], float(spec.get("cell", 0.16)), spec.get("color", Color(0.4, 0.4, 0.4)))
	return built["mesh"]

## All emissive detail (window grids + helical ramps + portal arches) merged into ONE mesh, so the
## chunk gives it a single emissive material tinted `accent`. Null if the building has no detail.
static func detail_mesh(spec: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for pn in spec.get("panels", []):
		any = _grid_panel(st, pn as Dictionary) or any
	for hx in spec.get("helices", []):
		any = _helix_ribbon(st, hx as Dictionary) or any
	for ar in spec.get("arches", []):
		any = _arch(st, ar as Dictionary) or any
	if not any:
		return null
	st.generate_normals()
	return st.commit()

# A grid of small inset quads on a plane (window rack). c=center, n=outward normal.
static func _grid_panel(st: SurfaceTool, p: Dictionary) -> bool:
	var c: Vector3 = p["c"]
	var n: Vector3 = (p["n"] as Vector3).normalized()
	var up := Vector3.UP
	var right := n.cross(up).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var cols := maxi(1, int(p.get("cols", 1)))
	var rows := maxi(1, int(p.get("rows", 1)))
	var w := float(p["w"])
	var h := float(p["h"])
	var cw := w / float(cols)
	var ch := h / float(rows)
	var cell_w := cw * 0.7
	var cell_h := ch * 0.62
	for cx in range(cols):
		for cy in range(rows):
			var ox := (float(cx) - float(cols - 1) * 0.5) * cw
			var oy := (float(cy) - float(rows - 1) * 0.5) * ch
			var cc := c + right * ox + up * oy + n * 0.04
			_quad(st, cc, right * cell_w * 0.5, up * cell_h * 0.5)
	return true

# A banked ribbon swept along a helix (the Plumbing ramp).
static func _helix_ribbon(st: SurfaceTool, hx: Dictionary) -> bool:
	var center: Vector3 = hx["center"]
	var r := float(hx["r"])
	var y0 := float(hx["y0"])
	var y1 := float(hx["y1"])
	var turns := float(hx["turns"])
	var width := float(hx["width"])
	var steps := int(turns * 24.0) + 2
	var prev_out := Vector3.ZERO
	var prev_in := Vector3.ZERO
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var ang := t * turns * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var y := lerpf(y0, y1, t)
		var out_pt := center + dir * (r + width * 0.5) + Vector3(0, y, 0)
		var in_pt := center + dir * (r - width * 0.5) + Vector3(0, y + 0.04, 0)
		if i > 0:
			st.add_vertex(prev_in); st.add_vertex(prev_out); st.add_vertex(out_pt)
			st.add_vertex(prev_in); st.add_vertex(out_pt); st.add_vertex(in_pt)
		prev_out = out_pt
		prev_in = in_pt
	return true

# A filled arched portal quad (rectangle + half-disc top) on a face.
static func _arch(st: SurfaceTool, a: Dictionary) -> bool:
	var c: Vector3 = a["c"]
	var n: Vector3 = (a["n"] as Vector3).normalized()
	var up := Vector3.UP
	var right := n.cross(up).normalized()
	var w := float(a["w"]) * 0.5
	var h := float(a["h"]) * 0.5
	var base := c + n * 0.05 - up * h * 0.4
	_quad(st, base, right * w, up * h * 0.6)
	# half-disc crown
	var crown := base + up * h * 0.6
	var segs := 8
	for s in range(segs):
		var a0 := PI * float(s) / float(segs)
		var a1 := PI * float(s + 1) / float(segs)
		var p0 := crown + right * cos(a0) * w + up * sin(a0) * w
		var p1 := crown + right * cos(a1) * w + up * sin(a1) * w
		st.add_vertex(crown); st.add_vertex(p0); st.add_vertex(p1)
	return true

static func _quad(st: SurfaceTool, c: Vector3, ex: Vector3, ey: Vector3) -> void:
	var p0 := c - ex - ey
	var p1 := c + ex - ey
	var p2 := c + ex + ey
	var p3 := c - ex + ey
	st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
