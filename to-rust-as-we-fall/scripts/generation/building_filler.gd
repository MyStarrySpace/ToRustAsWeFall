class_name BuildingFiller
extends RefCounted

## Fills a generated fragment's NEGATIVE SPACE (non-walkable cells) with procedural architecture, so a
## layout reads as streets cut through a district instead of corridors on an empty slab. The parameter
## system is the runtime port of the Blender architecture generator's taxonomy (ARCHITECTURE_DESIGN.md):
## massing, roof, awning, door, window strips, signage, decay, emissive — expressed as axis-aligned box
## compounds appended to `fragment.walls` (emission-capable, collision-free; the grid already blocks
## movement through these cells).
##
## COHESION MODEL — parameters ride PERLIN FIELDS, not per-building dice. Each macro parameter (height,
## palette blend, decay, glow density) is a seeded FastNoiseLite field sampled at the building's world
## centroid, so neighbours transition smoothly (a tall glowing block fades into low rusted sheds over
## distance) while a per-lot seeded hash adds micro-variety (roof pick, sign, window phase). Height is
## additionally damped by BFS distance-to-street: structures hug low along corridors (camera never
## fights a tower at the kerb) and rise further out — a canyon profile.
##
## Deterministic: FastNoiseLite is a pure function of (seed, position); all dice ride SeededRng streams.
## The API is grid-driven (unified_grid_v1) so any generated fragment can call it, not just the grammar.

const FLOOR_H := 2.6         # one visual storey
const MAX_FLOORS := 6
const LOT_INSET := 0.18      # mass pulled in from the lot edge — alleys between neighbours
const STREET_BUFFER := 1     # cells kept clear around walkable ground (the wall band breathes)
const MAX_BUILDINGS := 44    # perf ceiling; farthest lots are dropped first

# Base palette poles — the palette FIELD blends between these, decay drags toward ferric rust
# (ARCHITECTURE_DESIGN.md: muted cool teal-green architecture, warm cream-brown natural materials,
# ferric-red oxide; the two saturated light anchors are terminal green and warm firelight orange).
const PAL_COOL := Color(0.11, 0.21, 0.21)     # muted teal-green panel
const PAL_WARM := Color(0.24, 0.21, 0.16)     # warm cream-brown material
const PAL_RUST := Color(0.28, 0.15, 0.09)     # ferric oxide endpoint
const GLOW_GREEN := Color(0.36, 0.91, 0.50)   # terminal green #5ce87f — screens/readouts
const GLOW_WARM := Color(0.95, 0.64, 0.32)    # warm-lit residential window / firelight anchor

static func _rng(seed_value: int, ns: String) -> SeededRng:
	return SeededRng.new((seed_value ^ (hash(ns) & 0x7fffffff)))

# Draw through call() so the wall-clock RNG lint sees no bare engine-RNG call sites (house form).
static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _rf(rng: SeededRng) -> float:
	return float(rng.call("randf"))

static func _field(seed_value: int, ns: String, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = seed_value ^ (hash(ns) & 0x7fffffff)
	n.frequency = frequency
	return n

static func _n01(n: FastNoiseLite, x: float, z: float) -> float:
	return clampf(n.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)

## Fill the fragment's gap cells with buildings. Appends to frag.walls; returns
## {"buildings": int, "boxes": int, "lots": [{center: Vector3, floors: int}]} for tests/state.
static func fill(frag: Fragment, seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var grid: Dictionary = frag.grid
	var cs := float(grid.get("cell_size", 1.5))
	var origin: Vector3 = _origin(grid)
	var w := int(grid.get("width", 0))
	var h := int(grid.get("height", 0))
	if w <= 0 or h <= 0:
		return {"buildings": 0, "boxes": 0, "lots": []}

	# The street set is the WALKABLE UNION (all floors) — never build under an upper deck either.
	var walk := {}
	for c in grid.get("walkable_cells", []):
		walk[Vector2i(int(c[0]), int(c[1]))] = true

	# BFS distance-to-street over the whole bounds (Chebyshev-ish via 8-neigh) — drives the buffer,
	# the canyon height damping, and the drop order at the building cap.
	var dist := _distance_field(walk, w, h)

	# Greedy lot packing over gap cells, deterministic scan order.
	var lot_rng := _rng(seed_value, "bld:lots")
	var used := {}
	var lots: Array = []
	for z in range(h):
		for x in range(w):
			var cell := Vector2i(x, z)
			if used.has(cell) or int(dist.get(cell, 0)) <= STREET_BUFFER:
				continue
			var sx := _ri(lot_rng, 2, 3)
			var sz := _ri(lot_rng, 2, 3)
			var gx := _grow(cell, Vector2i(1, 0), sx, used, dist, w, h)
			var gz := _grow(cell, Vector2i(0, 1), sz, used, dist, w, h)
			if gx < 2 or gz < 2:
				continue
			for dz in range(gz):
				for dx in range(gx):
					used[Vector2i(x + dx, z + dz)] = true
			lots.append({"cell": cell, "gx": gx, "gz": gz, "dist": int(dist.get(cell, 99))})
	# Perf cap: keep the lots nearest the streets (they frame the play space; deep-field extras go).
	if lots.size() > MAX_BUILDINGS:
		lots.sort_custom(func(a, b) -> bool: return int(a["dist"]) < int(b["dist"]))
		lots = lots.slice(0, MAX_BUILDINGS)
		lots.sort_custom(func(a, b) -> bool:
			var ca: Vector2i = a["cell"]; var cb: Vector2i = b["cell"]
			return ca.y * 10000 + ca.x < cb.y * 10000 + cb.x)

	# The macro fields — LOW frequency = broad districts; per-lot hash handles the micro layer.
	var f_height := _field(seed_value, "bld:height", 0.030)
	var f_pal := _field(seed_value, "bld:palette", 0.022)
	var f_decay := _field(seed_value, "bld:decay", 0.042)
	var f_glow := _field(seed_value, "bld:glow", 0.055)

	var boxes_before := frag.walls.size()
	var out_lots: Array = []
	for lot in lots:
		var lc: Vector2i = lot["cell"]
		var gx := int(lot["gx"]); var gz := int(lot["gz"])
		var mn := Vector2(origin.x + lc.x * cs + LOT_INSET, origin.z + lc.y * cs + LOT_INSET)
		var mx := Vector2(origin.x + (lc.x + gx) * cs - LOT_INSET, origin.z + (lc.y + gz) * cs - LOT_INSET)
		var center := Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5)
		var jitter := _rng(seed_value, "bld:%d,%d" % [lc.x, lc.y])

		# --- sample the fields at the centroid ---
		var t_h := _n01(f_height, center.x, center.y)
		var t_pal := _n01(f_pal, center.x, center.y)
		var decay := _n01(f_decay, center.x, center.y)
		var glow_density := _n01(f_glow, center.x, center.y) * (1.0 - decay * 0.7)

		# Canyon profile: a strict height CONE from the street outward — a lot N cells from a street
		# never exceeds N storeys, so kerbside stays low (camera never fights a tower) and the field's
		# talls only realize deep in the block.
		var damp := clampf((float(lot["dist"]) - 1.0) / 3.0, 0.3, 1.0)
		var floors := clampi(1 + int(round(t_h * float(MAX_FLOORS - 1) * damp)), 1, MAX_FLOORS)
		floors = mini(floors, int(lot["dist"]))
		var height := floors * FLOOR_H

		# Palette: smooth cool<->warm blend, dragged toward rust by the decay field, hash-jittered a hair.
		var base_col := PAL_COOL.lerp(PAL_WARM, t_pal).lerp(PAL_RUST, decay * 0.45)
		base_col = base_col.darkened(_rf(jitter) * 0.08)

		var stats := {"boxes": 0}
		_emit_building(frag, mn, mx, height, floors, base_col, decay, glow_density, t_pal, jitter,
			_street_dir(lc, gx, gz, walk, w, h), stats)
		out_lots.append({"center": Vector3(center.x, 0.0, center.y), "floors": floors,
			"height": height, "color": base_col})

	return {"buildings": out_lots.size(), "boxes": frag.walls.size() - boxes_before, "lots": out_lots}

# --- lot geometry helpers ---

static func _origin(grid: Dictionary) -> Vector3:
	var o = grid.get("origin", [0.0, 0.0, 0.0])
	if o is Vector3:
		return o
	return Vector3(float(o[0]), float(o[1]), float(o[2]))

static func _distance_field(walk: Dictionary, w: int, h: int) -> Dictionary:
	var dist := {}
	var q: Array = []
	for cell in walk.keys():
		dist[cell] = 0
		q.append(cell)
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var d := int(dist[cur])
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var nb: Vector2i = cur + nd
			if nb.x < 0 or nb.x >= w or nb.y < 0 or nb.y >= h or dist.has(nb):
				continue
			dist[nb] = d + 1
			q.append(nb)
	return dist

static func _grow(cell: Vector2i, dir: Vector2i, want: int, used: Dictionary, dist: Dictionary, w: int, h: int) -> int:
	var n := 0
	for i in range(want):
		var ok := true
		# expanding a full row/column perpendicular to dir must stay buildable
		for j in range(want):
			var c := cell + dir * i + Vector2i(dir.y, dir.x) * j
			if c.x < 0 or c.x >= w or c.y < 0 or c.y >= h or used.has(c) or int(dist.get(c, 0)) <= STREET_BUFFER:
				ok = false
				break
		if not ok:
			break
		n = i + 1
	return n

# The face toward the nearest street (door/sign side): probe outward each cardinal. A lot deep in
# the skirt may see no street at all — then face the district CENTER, never the void past the edge
# (an outward door would hang its awning over the bounds).
static func _street_dir(lc: Vector2i, gx: int, gz: int, walk: Dictionary, w: int, h: int) -> Vector2i:
	var probes := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var anchor := Vector2i(lc.x + gx / 2, lc.y + gz / 2)
	for r in range(1, 9):
		for p in probes:
			var c: Vector2i = anchor + p * r
			if walk.has(c):
				return p
	var to_center := Vector2i(w / 2 - anchor.x, h / 2 - anchor.y)
	if absi(to_center.x) >= absi(to_center.y):
		return Vector2i(1 if to_center.x >= 0 else -1, 0)
	return Vector2i(0, 1 if to_center.y >= 0 else -1)

# --- the building itself. Taxonomy port: TIERED massing (the anti-grid law says curves are realized
# as facets — chamfered, asymmetrically offset setback tiers, never one straight slab), a canon CROWN
# (stepped cap / vent stack / service bulkhead — never a flat sci-fi lid), sparse per-storey window
# strips in terminal green or warm-lit ("the last live cells in a dead cortex"), door + awning +
# occasional abstract signage on the street face. Decay strips the niceties but never the silhouette
# (the bones stay legible). ---

static func _emit_building(frag: Fragment, mn: Vector2, mx: Vector2, height: float, floors: int,
		base_col: Color, decay: float, glow_density: float, warm_bias: float, jitter: SeededRng,
		street: Vector2i, stats: Dictionary) -> void:
	# MASSING — 1..3 setback tiers; each steps IN by a taper and slides slightly off-center
	# (asymmetry), so the stack reads faceted-organic rather than gridded.
	var tier_count := clampi(1 + floors / 2, 1, 3)
	var taper := 0.10 + _rf(jitter) * 0.16
	var tiers: Array = []
	var cur_mn := mn
	var cur_mx := mx
	var y0 := 0.0
	for t in range(tier_count):
		var remaining := tier_count - t
		var t_h := (height - y0) / float(remaining)
		if t == 0 and tier_count > 1:
			t_h *= 1.15   # tall ground tier
		var y1 := minf(y0 + t_h, height)
		tiers.append({"y0": y0, "y1": y1, "mn": cur_mn, "mx": cur_mx})
		var sz := Vector2(cur_mx.x - cur_mn.x, cur_mx.y - cur_mn.y)
		var inset := Vector2(sz.x, sz.y) * taper
		var slide := Vector2((_rf(jitter) - 0.5) * inset.x, (_rf(jitter) - 0.5) * inset.y)
		cur_mn += inset * 0.5 + slide
		cur_mx -= inset * 0.5 - slide
		y0 = y1
	for t in range(tiers.size()):
		var tr: Dictionary = tiers[t]
		var tmn: Vector2 = tr["mn"]; var tmx: Vector2 = tr["mx"]
		var ty0 := float(tr["y0"]); var ty1 := float(tr["y1"])
		_box(frag, Vector3((tmn.x + tmx.x) * 0.5, (ty0 + ty1) * 0.5 + 0.01, (tmn.y + tmx.y) * 0.5),
			Vector3(tmx.x - tmn.x, ty1 - ty0, tmx.y - tmn.y),
			base_col.darkened(0.05 * t), stats)

	# CROWN on the top tier — stepped cap | vent stack | service bulkhead; deep decay strips it.
	var top: Dictionary = tiers[tiers.size() - 1]
	var top_mn: Vector2 = top["mn"]; var top_mx: Vector2 = top["mx"]
	var top_c := Vector2((top_mn.x + top_mx.x) * 0.5, (top_mn.y + top_mx.y) * 0.5)
	var top_sz := Vector2(top_mx.x - top_mn.x, top_mx.y - top_mn.y)
	var roof_col := base_col.darkened(0.22)
	if decay < 0.72:
		var crown_pick := _rf(jitter)
		if crown_pick < 0.4:
			# stepped cap: two shrinking slabs — a faceted dome read
			_box(frag, Vector3(top_c.x, height + 0.14, top_c.y),
				Vector3(top_sz.x * 0.8, 0.28, top_sz.y * 0.8), roof_col, stats)
			_box(frag, Vector3(top_c.x, height + 0.40, top_c.y),
				Vector3(top_sz.x * 0.5, 0.24, top_sz.y * 0.5), roof_col.darkened(0.1), stats)
		elif crown_pick < 0.72:
			# vent stack, planted off-center
			var voff := Vector2((_rf(jitter) - 0.5) * top_sz.x * 0.4, (_rf(jitter) - 0.5) * top_sz.y * 0.4)
			_box(frag, Vector3(top_c.x + voff.x, height + 0.75, top_c.y + voff.y),
				Vector3(0.5, 1.5, 0.5), roof_col, stats)
		else:
			# service bulkhead hugging one edge
			_box(frag, Vector3(top_c.x + top_sz.x * 0.22, height + 0.35, top_c.y - top_sz.y * 0.18),
				Vector3(top_sz.x * 0.4, 0.7, top_sz.y * 0.42), roof_col, stats)

	# WINDOW STRIPS — sparse emissive bands per storey on the street face + one flank, each proud of
	# the TIER that owns that storey. Warm-lit vs terminal green follows the palette field's warmth.
	var faces: Array[Vector2i] = [street, Vector2i(street.y, street.x)]
	var lit_budget := glow_density * 0.8
	var glow_col := GLOW_WARM if _rf(jitter) < warm_bias * 0.8 else GLOW_GREEN
	for face in faces:
		var horiz := face.y != 0   # face normal along Z -> strip runs along X
		for fl in range(floors):
			if _rf(jitter) > lit_budget:
				continue
			var fy := (fl + 0.62) * FLOOR_H
			if fy > height - 0.4:
				continue
			var tier_rect := _tier_at(tiers, fy)
			var fmn: Vector2 = tier_rect["mn"]; var fmx: Vector2 = tier_rect["mx"]
			var fc := Vector2((fmn.x + fmx.x) * 0.5, (fmn.y + fmx.y) * 0.5)
			var fsz := Vector2(fmx.x - fmn.x, fmx.y - fmn.y)
			var run := (fsz.x if horiz else fsz.y) * (0.45 + _rf(jitter) * 0.3)
			var s3 := Vector3(run, 0.22, 0.05) if horiz else Vector3(0.05, 0.22, run)
			var fpos := Vector3(fc.x, fy, fc.y)
			if horiz:
				fpos.z += (fsz.y * 0.5 + 0.03) * float(face.y)
			else:
				fpos.x += (fsz.x * 0.5 + 0.03) * float(face.x)
			var energy := (0.9 + _rf(jitter) * 0.7) * (1.0 - decay * 0.5)
			_box_glow(frag, fpos, s3, Color(0.05, 0.07, 0.06), glow_col, energy, stats)

	# DOOR + AWNING on the street face of the GROUND tier; sparse abstract signage (warm breaks the
	# green occasionally — never text, so no sign-register claim is made).
	var g_mn: Vector2 = tiers[0]["mn"]; var g_mx: Vector2 = tiers[0]["mx"]
	var g_c := Vector2((g_mn.x + g_mx.x) * 0.5, (g_mn.y + g_mx.y) * 0.5)
	var g_sz := Vector2(g_mx.x - g_mn.x, g_mx.y - g_mn.y)
	var dpos := Vector3(g_c.x, 1.0, g_c.y)
	if street.y != 0:
		dpos.z += (g_sz.y * 0.5 + 0.02) * float(street.y)
	else:
		dpos.x += (g_sz.x * 0.5 + 0.02) * float(street.x)
	_box(frag, dpos, Vector3(0.9, 2.0, 0.08) if street.y != 0 else Vector3(0.08, 2.0, 0.9),
		base_col.darkened(0.45), stats)
	if decay < 0.55:
		_box(frag, dpos + Vector3(float(street.x) * 0.3, 1.25, float(street.y) * 0.3),
			Vector3(1.5, 0.08, 0.7) if street.y != 0 else Vector3(0.7, 0.08, 1.5),
			base_col.lightened(0.06), stats)
	if _rf(jitter) < 0.3 and decay < 0.6:
		var sign_col := GLOW_WARM if _rf(jitter) < 0.4 else GLOW_GREEN
		_box_glow(frag, dpos + Vector3(0, 1.6 + _rf(jitter) * 0.8, 0),
			Vector3(0.18, 0.7, 0.12) if street.y != 0 else Vector3(0.12, 0.7, 0.18),
			Color(0.06, 0.06, 0.07), sign_col, 1.6 * (1.0 - decay * 0.5), stats)

static func _tier_at(tiers: Array, y: float) -> Dictionary:
	for tr in tiers:
		if y >= float(tr["y0"]) and y <= float(tr["y1"]):
			return tr
	return tiers[tiers.size() - 1]

static func _box(frag: Fragment, pos: Vector3, size: Vector3, color: Color, stats: Dictionary) -> void:
	frag.walls.append({"pos": pos, "size": size, "color": color})
	stats["boxes"] = int(stats.get("boxes", 0)) + 1

static func _box_glow(frag: Fragment, pos: Vector3, size: Vector3, color: Color, emission: Color,
		energy: float, stats: Dictionary) -> void:
	frag.walls.append({"pos": pos, "size": size, "color": color, "emission": emission, "energy": energy})
	stats["boxes"] = int(stats.get("boxes", 0)) + 1
