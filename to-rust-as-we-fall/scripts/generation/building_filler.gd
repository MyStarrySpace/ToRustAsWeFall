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

	# Cells belonging to any UPPER floor (stacked decks) — viaduct lanes avoid these columns so the
	# guideway never threads a platform or a ladder.
	var upper := {}
	for lce in grid.get("level_cells", []):
		if int((lce as Dictionary).get("level", 0)) >= 1:
			for c in (lce as Dictionary).get("cells", []):
				upper[Vector2i(int(c[0]), int(c[1]))] = true

	# TRANSIT VIADUCTS (canon transit_viaduct): plan lanes BEFORE lot packing so piers claim their
	# ground and no building grows into a pier cell.
	var viaducts_on := bool(opts.get("viaducts", true))
	var via_plans: Array = []
	var used := {}
	if viaducts_on:
		via_plans = _plan_viaducts(seed_value, walk, upper, dist, w, h)
		for pl in via_plans:
			for pc in pl["piers"]:
				used[pc] = true

	# Greedy lot packing over gap cells, deterministic scan order.
	var lot_rng := _rng(seed_value, "bld:lots")
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

	# LANDMARK buildings (the architecture->puzzle hookup, docs/SET_PIECES.md): the two biggest
	# street-adjacent lots become BaseShapeBuilder heroes whose gameplay anchors the level CONSUMES —
	# the main-door ROAD connector snaps the building's facing to its street (an approach is carved if
	# needed), and facing BRIDGE connectors between the pair span a walkable deck (level cells + ladder
	# links appended to the grid — real traversal, not scenery).
	var landmarks: Array = []
	var bridge_plans: Array = []
	if bool(opts.get("landmarks", true)):
		var lm := _plan_landmarks(seed_value, lots, walk, origin, cs, w, h, frag, grid)
		landmarks = lm["landmarks"]
		bridge_plans = lm["bridges"]
		var consumed: Dictionary = lm["consumed"]
		if not consumed.is_empty():
			var kept_lots: Array = []
			for li in range(lots.size()):
				if not consumed.has(li):
					kept_lots.append(lots[li])
			lots = kept_lots
			# carved road approaches changed the street set — refresh the distance field, and DROP any
			# lot the new road now touches (it was packed against the old streets; building it would
			# violate the street buffer)
			dist = _distance_field(walk, w, h)
			var filtered: Array = []
			for lot_r in lots:
				var ld := lot_r as Dictionary
				var lc0: Vector2i = ld["cell"]
				var clear := true
				for dz in range(int(ld["gz"])):
					for dx in range(int(ld["gx"])):
						if int(dist.get(Vector2i(lc0.x + dx, lc0.y + dz), 99)) <= STREET_BUFFER:
							clear = false
				if clear:
					ld["dist"] = int(dist.get(lc0, 99))
					filtered.append(ld)
			lots = filtered

	# The macro fields — LOW frequency = broad districts; per-lot hash handles the micro layer.
	var f_height := _field(seed_value, "bld:height", 0.030)
	var f_pal := _field(seed_value, "bld:palette", 0.022)
	var f_decay := _field(seed_value, "bld:decay", 0.042)
	var f_glow := _field(seed_value, "bld:glow", 0.055)

	var boxes_before := frag.walls.size()
	var props_on := bool(opts.get("props", true))
	var prop_count := 0
	var lathes: Array = []
	var coil_count := 0
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
		# The rail corridor: anything within a cell of a viaduct lane stays under its deck.
		for pl in via_plans:
			var lane := int(pl["lane"])
			if int(pl["axis"]) == 0:
				if lane >= lc.y - 1 and lane <= lc.y + gz:
					floors = mini(floors, 2)
			elif lane >= lc.x - 1 and lane <= lc.x + gx:
				floors = mini(floors, 2)
		var height := floors * FLOOR_H

		# Palette: smooth cool<->warm blend, dragged toward rust by the decay field, hash-jittered a hair.
		var base_col := PAL_COOL.lerp(PAL_WARM, t_pal).lerp(PAL_RUST, decay * 0.45)
		base_col = base_col.darkened(_rf(jitter) * 0.08)
		# Facade material rides the same fields: rusted panels where decay bites, cool wall panelling
		# on the teal side of the palette, plain facility metal on the warm side.
		var facade_tile := "rust_iron" if decay > 0.58 else ("wall_panel" if t_pal < 0.45 else "facility_metal")

		var street := _street_dir(lc, gx, gz, walk, w, h)
		var stats := {"boxes": 0}
		if floors >= 2:
			# LATHE TOWER — the reference silhouettes (revolve-shaped, never boxes): drum with lobed
			# base + dome, scalloped band stack, or ribbed spire cluster, picked by the fields.
			# Planned as DATA; the fragment loader lofts the mesh (it owns scene nodes).
			var near_lane := false
			for pl in via_plans:
				var lane := int(pl["lane"])
				if int(pl["axis"]) == 0:
					near_lane = near_lane or (lane >= lc.y - 1 and lane <= lc.y + gz)
				else:
					near_lane = near_lane or (lane >= lc.x - 1 and lane <= lc.x + gx)
			var kind := "drum"
			if decay < 0.5 and t_pal < 0.38:
				kind = "ribbed"
			elif decay < 0.5 and t_pal > 0.6:
				kind = "banded"
			if near_lane:
				kind = "banded"   # flat top under the guideway — a dome would graze the deck
			var wants_coil: bool = kind == "drum" and int(lot["dist"]) >= 3 and coil_count < 2
			if wants_coil:
				coil_count += 1
			lathes.append({
				"center": Vector3(center.x, 0.0, center.y),
				"base_r": minf(mx.x - mn.x, mx.y - mn.y) * 0.5 - 0.1,
				"height": height,
				"archetype": kind,
				"seed": seed_value ^ (lc.x * 73856093) ^ (lc.y * 19349663),
				"warm_bias": t_pal, "glow_density": glow_density, "decay": decay,
				"tile": facade_tile, "color": base_col,
				"coil": wants_coil,
			})
			# the street-face entry kit still anchors the base (the reference towers keep a kiosk)
			_emit_entry(frag, mn, mx, base_col, decay, t_pal, jitter, street, props_on, stats)
		else:
			_emit_building(frag, mn, mx, height, floors, base_col, decay, glow_density, t_pal, jitter,
				street, props_on, facade_tile, stats)
		out_lots.append({"center": Vector3(center.x, 0.0, center.y), "floors": floors,
			"height": height, "color": base_col})

	# --- STREET FURNITURE over the buffer band (dist==1: the non-walkable kerb between street and
	# lots). Same field-driven cohesion: the decay field picks tended vs desiccated planters and
	# thins the lamps; the glow field decides which lamps are actually lit. A subset of lit lamps
	# carries a real OmniLight (capped) so the walk routes get pools of light. ---
	if props_on:
		var prop_rng := _rng(seed_value, "bld:props")
		var lamp_lights := 0
		var stats_p := {"boxes": 0}
		for z in range(h):
			for x in range(w):
				var cell := Vector2i(x, z)
				if int(dist.get(cell, 0)) != 1 or used.has(cell):
					continue
				if _rf(prop_rng) > 0.24:
					continue
				# face the adjacent street; sit pushed 0.2 toward the lot side of the kerb cell
				var facing := Vector2i.ZERO
				for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if walk.has(cell + nd):
						facing = nd
						break
				if facing == Vector2i.ZERO:
					continue
				var raw_c := Vector2(origin.x + (float(x) + 0.5) * cs, origin.z + (float(z) + 0.5) * cs)
				var cpos2 := raw_c - Vector2(float(facing.x), float(facing.y)) * 0.2
				var decay2 := _n01(f_decay, cpos2.x, cpos2.y)
				var lit := _rf(prop_rng) < _n01(f_glow, cpos2.x, cpos2.y) * (1.0 - decay2 * 0.6) + 0.15
				# long furniture (troughs, rails, pipes) runs ALONG the kerb — legal only when every
				# walkable 8-neighbour lies strictly on the FACING side (corner bulges and diagonal
				# street cells would otherwise catch a trough end). A DOUBLE kerb (streets on both
				# sides — a median strip) has no safe "away" side: only a centred bollard row fits it.
				var along_v := Vector2i(absi(facing.y), absi(facing.x))
				if walk.has(cell - facing):
					if not walk.has(cell + along_v) and not walk.has(cell - along_v):
						_prop_bollards(frag, raw_c, facing, stats_p)
						prop_count += 1
					continue
				var clear_flanks := true
				for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
						Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
					if walk.has(cell + n) and n.x * facing.x + n.y * facing.y <= 0:
						clear_flanks = false
						break
				var pick := _rf(prop_rng)
				if pick < 0.36 or not clear_flanks:
					var with_light := lit and lamp_lights < 8 and _rf(prop_rng) < 0.55
					_prop_street_lamp(frag, cpos2, facing, lit, with_light, stats_p)
					if with_light:
						lamp_lights += 1
				elif pick < 0.66:
					_prop_planter(frag, cpos2, facing, decay2, stats_p)
				elif pick < 0.88:
					_prop_bollards(frag, cpos2, facing, stats_p)
				else:
					_prop_pipe_stub(frag, cpos2, facing, stats_p)
				prop_count += 1
		# A rare MEMORIAL MONUMENT on an unbuilt gap cell near the district's heart.
		if _rf(prop_rng) < 0.35:
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			var mid := Vector2i(w / 2, h / 2)
			for z2 in range(h):
				for x2 in range(w):
					var c2 := Vector2i(x2, z2)
					var dd := int(dist.get(c2, 0))
					if used.has(c2) or dd < 2 or dd > 3:
						continue
					var md: int = absi(c2.x - mid.x) + absi(c2.y - mid.y)
					if md < best_d:
						best_d = md
						best = c2
			if best.x >= 0:
				_prop_monument(frag, Vector2(origin.x + (float(best.x) + 0.5) * cs,
					origin.z + (float(best.y) + 0.5) * cs), stats_p)
				prop_count += 1

	# Raise the planned viaducts last — deck, rails, guide strips, piers, gantries, a parked tram.
	# The second line rides 0.9 higher so crossing guideways read as an interchange, never coplanar.
	if viaducts_on:
		var stats_v := {"boxes": 0}
		for vi in range(via_plans.size()):
			_emit_viaduct(frag, via_plans[vi], origin, cs, w, h, DECK_TOP + 0.9 * float(vi), stats_v)

	return {"buildings": out_lots.size(), "boxes": frag.walls.size() - boxes_before,
		"props": prop_count, "viaducts": via_plans.size(), "lathes": lathes, "lots": out_lots,
		"landmarks": landmarks, "bridges": bridge_plans}

# --- LANDMARKS: BaseShapeBuilder heroes whose gameplay anchors the level consumes ------------------

const LANDMARK_KINDS := ["bulwark_wharf", "tiered_terrace"]   # box-based, both fit 3x3-cell lots
const BRIDGE_MIN_SPAN := 3.0
const BRIDGE_MAX_SPAN := 16.0
const BRIDGE_LEVEL_TOL := 1.4    # a socket may sit this far off a level plane and still snap to it

# Pick up to two big street-adjacent lots, orient each landmark's MAIN door to its street (the road
# connector), carve the approach, and bridge the pair's facing ledge sockets when the lane is clear.
static func _plan_landmarks(seed_value: int, lots: Array, walk: Dictionary, origin: Vector3, cs: float,
		w: int, h: int, frag: Fragment, grid: Dictionary) -> Dictionary:
	var out := {"landmarks": [], "bridges": [], "consumed": {}}
	var cands: Array = []
	for li in range(lots.size()):
		var lot := lots[li] as Dictionary
		if int(lot["gx"]) >= 3 and int(lot["gz"]) >= 3 and int(lot["dist"]) <= 3:
			cands.append(li)
	if cands.is_empty():
		return out
	var rng := _rng(seed_value, "bld:landmarks")
	var first := int(cands[0])
	var second := -1
	# prefer a second lot sharing a row/column band with the first (a bridge needs alignment) at a
	# bridgeable range; fall back to the nearest other candidate
	var fc: Vector2i = (lots[first] as Dictionary)["cell"]
	var best_score := 1.0e9
	for ci in cands:
		if int(ci) == first:
			continue
		var cc: Vector2i = (lots[int(ci)] as Dictionary)["cell"]
		var d := Vector2(fc.x - cc.x, fc.y - cc.y).length() * cs
		if d < BRIDGE_MIN_SPAN or d > BRIDGE_MAX_SPAN + 6.0:
			continue
		var aligned := mini(absi(cc.x - fc.x), absi(cc.y - fc.y))
		var score := float(aligned) * 100.0 + d
		if score < best_score:
			best_score = score
			second = int(ci)
	var picks: Array = [first] if second < 0 else [first, second]
	var kind0 := str(LANDMARK_KINDS[_ri(rng, 0, LANDMARK_KINDS.size() - 1)])
	for pi in range(picks.size()):
		var li2 := int(picks[pi])
		out["consumed"][li2] = true
		var lot2 := lots[li2] as Dictionary
		var lc: Vector2i = lot2["cell"]
		var gx := int(lot2["gx"])
		var gz := int(lot2["gz"])
		var kind := kind0 if pi == 0 else str(LANDMARK_KINDS[(LANDMARK_KINDS.find(kind0) + 1) % LANDMARK_KINDS.size()])
		var spec: Dictionary = BaseShapeBuilder.generate(kind)
		var anchors: Dictionary = BuildingSurvey.from_spec(spec).anchors()
		var sdir := _street_dir(lc, gx, gz, walk, w, h)
		var yaw := atan2(float(sdir.x), float(sdir.y))   # rotate the spec's +Z (main door) onto the street
		var pos := Vector3(origin.x + (float(lc.x) + float(gx) * 0.5) * cs, 0.0,
			origin.z + (float(lc.y) + float(gz) * 0.5) * cs)
		var basis := Basis(Vector3.UP, yaw)
		# the ROAD connector: the main door's threshold — carve the approach out to the street
		var door_w := pos
		for a in (anchors.get("connectors", []) as Array):
			var ad := a as Dictionary
			if str(ad["kind"]) == "road" and bool(ad.get("main", false)):
				door_w = pos + basis * (ad["pos"] as Vector3)
		var door_cell := Vector2i(int(floor((door_w.x - origin.x) / cs)), int(floor((door_w.z - origin.z) / cs)))
		var approach: Array = []
		var ac := door_cell
		for step in range(6):
			ac += sdir
			if ac.x < 0 or ac.x >= w or ac.y < 0 or ac.y >= h:
				break
			if walk.has(ac):
				break
			approach.append([ac.x, ac.y])
			walk[ac] = true
			_carve_walkable(grid, ac)
			# the road APRON is FLOOR, not architecture (the street-blockage invariant scans walls)
			frag.floors.append({"pos": Vector3(origin.x + (float(ac.x) + 0.5) * cs, -0.02, origin.z + (float(ac.y) + 0.5) * cs),
				"size": Vector3(cs, 0.06, cs), "color": Color(0.17, 0.18, 0.20), "tile": "deck_metal"})
		# world-space bridge sockets for the pairing pass; WALKABLE LANES (survey deck descriptors,
		# e.g. the hypelines arms) dock straight into the grid — level cells + a ladder link
		var socks: Array = []
		var lanes: Array = []
		for a2 in (anchors.get("connectors", []) as Array):
			var ad2 := a2 as Dictionary
			if str(ad2["kind"]) == "bridge":
				var wp := pos + basis * (ad2["pos"] as Vector3)
				var wd := basis * (ad2["dir"] as Vector3)
				socks.append({"pos": [wp.x, wp.y, wp.z], "dir": [wd.x, wd.y, wd.z]})
				if ad2.has("deck"):
					var dk := ad2["deck"] as Dictionary
					var ws := pos + basis * (dk["start"] as Vector3)
					var we := pos + basis * (dk["end"] as Vector3)
					lanes.append({"start": [ws.x, ws.y, ws.z], "end": [we.x, we.y, we.z],
						"width": float(dk["width"]), "walk_y": float(dk["walk_y"]) + pos.y})
		for lane in lanes:
			var lplan := apply_lane_to_grid(grid, lane as Dictionary, origin, cs)
			if not lplan.is_empty():
				_emit_lane_stub(frag, lplan)
		(out["landmarks"] as Array).append({"kind": kind, "pos": [pos.x, pos.y, pos.z], "yaw": yaw,
			"street": [sdir.x, sdir.y], "door_cell": [door_cell.x, door_cell.y], "approach": approach,
			"sockets": socks, "lanes": lanes})
		# the FIRST landmark also spends one structural WEAK POINT as a playable crumble trap: the
		# pry point at the wall foot, the kill zone on the ground in front of the face
		if pi == 0:
			var wps := anchors.get("weak_points", []) as Array
			if not wps.is_empty():
				var wp := wps[_ri(rng, 0, wps.size() - 1)] as Dictionary
				var wpos := pos + basis * (wp["pos"] as Vector3)
				var wn := (basis * (wp["n"] as Vector3)).normalized()
				var foot := Vector3(wpos.x, 0.0, wpos.z)
				var kc := foot + wn * 1.5
				frag.objects.append({"type": "weak_wall",
					"pos": foot, "n": wn,
					"kill_min": Vector3(kc.x - 1.4, 0.0, kc.z - 1.4),
					"kill_max": Vector3(kc.x + 1.4, 0.0, kc.z + 1.4)})
	# the BRIDGE: first facing, level-snappable, clear-laned socket pair between the two landmarks
	if (out["landmarks"] as Array).size() == 2:
		var plan := plan_bridge((out["landmarks"] as Array)[0] as Dictionary,
			(out["landmarks"] as Array)[1] as Dictionary, walk, origin, cs,
			float(grid.get("level_height", 4.0)))
		if not plan.is_empty():
			(out["bridges"] as Array).append(plan)
			_apply_bridge_to_grid(grid, plan)
			_emit_bridge(frag, plan, origin, cs)
	return out

## PURE bridge planner (unit-testable): the first pair of near-axis-aligned, mutually FACING bridge
## sockets that snaps to a level plane and whose lane crosses only STREET cells. Returns {} or
## {"a", "b", "level", "y", "cells", "links"}.
static func plan_bridge(lm_a: Dictionary, lm_b: Dictionary, walk: Dictionary, origin: Vector3,
		cs: float, lh: float) -> Dictionary:
	for sa in (lm_a.get("sockets", []) as Array):
		var pa := _arr3(sa as Dictionary, "pos")
		var da := _arr3(sa as Dictionary, "dir")
		for sb in (lm_b.get("sockets", []) as Array):
			var pb := _arr3(sb as Dictionary, "pos")
			var db := _arr3(sb as Dictionary, "dir")
			if da.dot(db) > -0.5:
				continue   # not facing each other
			var lvl := int(round(((pa.y + pb.y) * 0.5) / lh))
			if lvl < 1 or absf(pa.y - float(lvl) * lh) > BRIDGE_LEVEL_TOL or absf(pb.y - float(lvl) * lh) > BRIDGE_LEVEL_TOL:
				continue
			var axis_x := absf(pb.x - pa.x) >= absf(pb.z - pa.z)
			var lateral := absf(pb.z - pa.z) if axis_x else absf(pb.x - pa.x)
			var span := absf(pb.x - pa.x) if axis_x else absf(pb.z - pa.z)
			if lateral > cs * 0.75 or span < BRIDGE_MIN_SPAN or span > BRIDGE_MAX_SPAN:
				continue
			var ca := Vector2i(int(floor((pa.x - origin.x) / cs)), int(floor((pa.z - origin.z) / cs)))
			var cb := Vector2i(int(floor((pb.x - origin.x) / cs)), int(floor((pb.z - origin.z) / cs)))
			var step := Vector2i(signi(cb.x - ca.x), 0) if axis_x else Vector2i(0, signi(cb.y - ca.y))
			# lane cells strictly BETWEEN the feet, all street (the span flies over walkable ground)
			var cells: Array = []
			var cur := ca + step
			var ok := true
			while cur != cb:
				if not walk.has(cur):
					ok = false
					break
				cells.append([cur.x, cur.y])
				cur += step
			if not ok or cells.size() < 2:
				continue
			return {"a": [pa.x, pa.y, pa.z], "b": [pb.x, pb.y, pb.z], "level": lvl,
				"y": float(lvl) * lh, "cells": cells,
				"links": [cells[0], cells[cells.size() - 1]]}
	return {}

static func _arr3(d: Dictionary, key: String) -> Vector3:
	var a := d.get(key, [0, 0, 0]) as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# Carve one cell walkable at GROUND level: FLOOR tile + (on multi-level grids, whose level-0
# allow-set is enumerated explicitly) the level-0 allowance.
static func _carve_walkable(grid: Dictionary, cell: Vector2i) -> void:
	(grid.get("walkable_cells", []) as Array).append([cell.x, cell.y])
	if grid.has("level_cells"):
		for lce in (grid["level_cells"] as Array):
			if int((lce as Dictionary).get("level", -1)) == 0:
				((lce as Dictionary)["cells"] as Array).append([cell.x, cell.y])

## Dock a WALKABLE LANE (a survey deck descriptor: {start, end, width, walk_y} in world space) into
## the grid: the deck's cells get allowances at the level plane its walk surface snaps to, and the
## TIP gets a ladder link down to ground. Returns the applied plan ({} if the lane doesn't reach a
## level plane or spans under two cells). This is how a building's survey-carried lanes (the
## hypelines arms) become playable grid, reusing the bridge machinery.
static func apply_lane_to_grid(grid: Dictionary, lane: Dictionary, origin: Vector3, cs: float) -> Dictionary:
	var lh := float(grid.get("level_height", 4.0))
	var a := _arr3(lane, "start")
	var b := _arr3(lane, "end")
	var walk_y := float(lane.get("walk_y", (a.y + b.y) * 0.5))
	var lvl := int(round(walk_y / lh))
	if lvl < 1 or absf(walk_y - float(lvl) * lh) > BRIDGE_LEVEL_TOL:
		return {}
	var cells: Array = []
	var seen := {}
	var steps := maxi(1, int(ceil(a.distance_to(b) / (cs * 0.5))))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var c := Vector2i(int(floor((p.x - origin.x) / cs)), int(floor((p.z - origin.z) / cs)))
		if not seen.has(c):
			seen[c] = true
			cells.append([c.x, c.y])
	if cells.size() < 2:
		return {}
	var plan := {"a": [a.x, a.y, a.z], "b": [b.x, b.y, b.z], "level": lvl,
		"y": float(lvl) * lh, "cells": cells, "links": [cells[cells.size() - 1]]}
	_apply_bridge_to_grid(grid, plan)
	return plan

# The lane's ladder GRAB STUB at the tip (the deck itself is the building's own arm geometry).
static func _emit_lane_stub(frag: Fragment, plan: Dictionary) -> void:
	var tip := _arr3(plan, "b")
	var y := float(plan["y"])
	var stub_bot := maxf(3.05, y - 1.0)
	frag.walls.append({"pos": Vector3(tip.x, (stub_bot + y + 0.45) * 0.5, tip.z),
		"size": Vector3(0.16, (y + 0.45) - stub_bot, 0.16),
		"color": Color(0.55, 0.5, 0.4), "emission": Color(0.36, 0.91, 0.50), "emission_energy": 0.4})

# Append the bridge's DECK to the grid: level allowances for the deck cells + ladder links at both
# ends. Deck cells are street cells, so level 0 stays walkable UNDER the span.
static func _apply_bridge_to_grid(grid: Dictionary, plan: Dictionary) -> void:
	var lvl := int(plan["level"])
	grid["level_count"] = maxi(int(grid.get("level_count", 1)), lvl + 1)
	if not grid.has("level_height"):
		grid["level_height"] = 4.0
	var level_cells := grid.get("level_cells", []) as Array
	var entry: Dictionary = {}
	for lce in level_cells:
		if int((lce as Dictionary).get("level", -1)) == lvl:
			entry = lce as Dictionary
	if entry.is_empty():
		entry = {"level": lvl, "cells": []}
		level_cells.append(entry)
	for c in (plan["cells"] as Array):
		(entry["cells"] as Array).append(c)
	grid["level_cells"] = level_cells
	var links := grid.get("links", []) as Array
	for lc in (plan["links"] as Array):
		links.append({"cell": lc, "from": 0, "to": lvl, "type": "ladder"})
	grid["links"] = links

# The bridge's VISUAL: a deck slab with side rails and a ladder post at each end.
static func _emit_bridge(frag: Fragment, plan: Dictionary, origin: Vector3, cs: float) -> void:
	var pa := _arr3(plan, "a")
	var pb := _arr3(plan, "b")
	var y := float(plan["y"])
	var mid := (pa + pb) * 0.5
	var axis_x := absf(pb.x - pa.x) >= absf(pb.z - pa.z)
	var span := absf(pb.x - pa.x) if axis_x else absf(pb.z - pa.z)
	var deck_size := Vector3(span, 0.14, 1.15) if axis_x else Vector3(1.15, 0.14, span)
	frag.walls.append({"pos": Vector3(mid.x, y - 0.07, mid.z), "size": deck_size, "color": Color(0.32, 0.30, 0.27)})
	var rail_off := Vector3(0, 0, 0.62) if axis_x else Vector3(0.62, 0, 0)
	for s in [-1.0, 1.0]:
		var rs := Vector3(span, 0.42, 0.08) if axis_x else Vector3(0.08, 0.42, span)
		frag.walls.append({"pos": Vector3(mid.x, y + 0.21, mid.z) + rail_off * s, "size": rs,
			"color": Color(0.5, 0.46, 0.36)})
	# ladder markers are deck-end GRAB STUBS kept ABOVE the 3m street-clearance plane (a ground post
	# beside the lane violates the street invariants — the climb itself is the logical ladder link,
	# already in the grid).
	var stub_bot := maxf(3.05, y - 1.0)
	for foot in [pa, pb]:
		var f3 := foot as Vector3
		frag.walls.append({"pos": Vector3(f3.x, (stub_bot + y + 0.45) * 0.5, f3.z),
			"size": Vector3(0.16, (y + 0.45) - stub_bot, 0.16),
			"color": Color(0.55, 0.5, 0.4), "emission": Color(0.36, 0.91, 0.50), "emission_energy": 0.4})

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
		street: Vector2i, props_on: bool, facade_tile: String, stats: Dictionary) -> void:
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
		_boxt(frag, Vector3((tmn.x + tmx.x) * 0.5, (ty0 + ty1) * 0.5 + 0.01, (tmn.y + tmx.y) * 0.5),
			Vector3(tmx.x - tmn.x, ty1 - ty0, tmx.y - tmn.y),
			base_col.darkened(0.05 * t), facade_tile, stats)

	# BUTTRESS FINS pinning the ground tier's corners (canon structure vocabulary).
	if floors >= 4 and _rf(jitter) < 0.5:
		var f_mn: Vector2 = tiers[0]["mn"]; var f_mx: Vector2 = tiers[0]["mx"]
		var fin_h := (float(tiers[0]["y1"]) - float(tiers[0]["y0"])) * 0.85
		var fin_col := base_col.darkened(0.28)
		for cx: float in [f_mn.x, f_mx.x]:
			for cz: float in [f_mn.y, f_mx.y]:
				_box(frag, Vector3(cx, fin_h * 0.5, cz), Vector3(0.5, fin_h, 0.13), fin_col, stats)
				_box(frag, Vector3(cx, fin_h * 0.5, cz), Vector3(0.13, fin_h, 0.5), fin_col, stats)

	# LATTICE INFILL panel (mesh_lattice vocabulary) on the street face of the upper tier — the
	# grate tile reads as latticework at pixel-art scale. Healthy blocks only; decay strips it.
	if floors >= 3 and decay < 0.5 and _rf(jitter) < 0.42 and tiers.size() > 1:
		var lt: Dictionary = tiers[1]
		var l_mn: Vector2 = lt["mn"]; var l_mx: Vector2 = lt["mx"]
		var l_c := Vector2((l_mn.x + l_mx.x) * 0.5, (l_mn.y + l_mx.y) * 0.5)
		var l_sz := Vector2(l_mx.x - l_mn.x, l_mx.y - l_mn.y)
		var l_h := (float(lt["y1"]) - float(lt["y0"])) * 0.62
		var l_y := (float(lt["y0"]) + float(lt["y1"])) * 0.5
		var lp := Vector3(l_c.x, l_y, l_c.y)
		var lsz: Vector3
		if street.y != 0:
			lp.z += (l_sz.y * 0.5 + 0.04) * float(street.y)
			lsz = Vector3(l_sz.x * 0.72, l_h, 0.07)
		else:
			lp.x += (l_sz.x * 0.5 + 0.04) * float(street.x)
			lsz = Vector3(0.07, l_h, l_sz.y * 0.72)
		_boxt(frag, lp, lsz, base_col.lightened(0.22), "grate", stats)

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
			_boxt(frag, Vector3(top_c.x, height + 0.14, top_c.y),
				Vector3(top_sz.x * 0.8, 0.28, top_sz.y * 0.8), roof_col, facade_tile, stats)
			_boxt(frag, Vector3(top_c.x, height + 0.40, top_c.y),
				Vector3(top_sz.x * 0.5, 0.24, top_sz.y * 0.5), roof_col.darkened(0.1), facade_tile, stats)
		elif crown_pick < 0.72:
			# vent stack, planted off-center
			var voff := Vector2((_rf(jitter) - 0.5) * top_sz.x * 0.4, (_rf(jitter) - 0.5) * top_sz.y * 0.4)
			_boxt(frag, Vector3(top_c.x + voff.x, height + 0.75, top_c.y + voff.y),
				Vector3(0.5, 1.5, 0.5), roof_col, "facility_metal", stats)
		else:
			# service bulkhead hugging one edge
			_boxt(frag, Vector3(top_c.x + top_sz.x * 0.22, height + 0.35, top_c.y - top_sz.y * 0.18),
				Vector3(top_sz.x * 0.4, 0.7, top_sz.y * 0.42), roof_col, "facility_metal", stats)

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
			var energy := (0.75 + _rf(jitter) * 0.35) * (1.0 - decay * 0.5)
			_box_glow(frag, fpos, s3, Color(0.05, 0.07, 0.06), glow_col, energy, stats)

	_emit_entry(frag, tiers[0]["mn"], tiers[0]["mx"], base_col, decay, warm_bias, jitter, street,
		props_on, stats)

# DOOR + AWNING + signage + the building-attached props on the street face — shared by box sheds
# and lathe towers (the reference towers keep a ground kiosk against the curved shell).
static func _emit_entry(frag: Fragment, g_mn: Vector2, g_mx: Vector2, base_col: Color, decay: float,
		warm_bias: float, jitter: SeededRng, street: Vector2i, props_on: bool, stats: Dictionary) -> void:
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
			Color(0.06, 0.06, 0.07), sign_col, 1.25 * (1.0 - decay * 0.5), stats)

	# BUILDING-ATTACHED PROPS — a wall sconce beside the door (warm-lit follows the palette field),
	# a terminal kiosk at healthy blocks, pipe roots spreading along the base where decay has set in.
	if not props_on:
		return
	var along := Vector2(float(absi(street.y)), float(absi(street.x)))   # unit along the door face
	if _rf(jitter) < 0.75 - decay * 0.5:
		var sc_col := GLOW_WARM if _rf(jitter) < warm_bias else GLOW_GREEN
		var sc_pos := dpos + Vector3(along.x * 0.85, 1.3, along.y * 0.85)
		_box_glow(frag, sc_pos, Vector3(0.16, 0.22, 0.16), Color(0.07, 0.07, 0.08), sc_col,
			1.1 * (1.0 - decay * 0.4), stats)
	if _rf(jitter) < 0.18 and decay < 0.4:
		var kpos := dpos + Vector3(along.x * -1.3 + float(street.x) * 0.22, 0.0, along.y * -1.3 + float(street.y) * 0.22)
		_box(frag, Vector3(kpos.x, 0.75, kpos.z),
			Vector3(0.42, 1.5, 0.5) if street.y != 0 else Vector3(0.5, 1.5, 0.42), Color(0.12, 0.15, 0.15), stats)
		_box_glow(frag, Vector3(kpos.x + float(street.x) * 0.24, 1.05, kpos.z + float(street.y) * 0.24),
			Vector3(0.3, 0.38, 0.04) if street.y != 0 else Vector3(0.04, 0.38, 0.3),
			Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.4, stats)
	if decay > 0.55:
		var pipe_col := Color(0.21, 0.13, 0.09)
		for pr in range(2):
			var run := (g_sz.x if street.y != 0 else g_sz.y) * (0.5 + _rf(jitter) * 0.4)
			var slide := along * (_rf(jitter) - 0.5) * 0.8
			_box(frag, Vector3(dpos.x + float(street.x) * 0.12 + slide.x, 0.16 + float(pr) * 0.22,
				dpos.z + float(street.y) * 0.12 + slide.y),
				Vector3(run, 0.14, 0.14) if street.y != 0 else Vector3(0.14, 0.14, run), pipe_col, stats)
		_box(frag, dpos + Vector3(along.x * 0.5 + float(street.x) * 0.1, 0.9, along.y * 0.5 + float(street.y) * 0.1),
			Vector3(0.13, 1.8, 0.13), pipe_col.darkened(0.1), stats)

static func _tier_at(tiers: Array, y: float) -> Dictionary:
	for tr in tiers:
		if y >= float(tr["y0"]) and y <= float(tr["y1"]):
			return tr
	return tiers[tiers.size() - 1]

# --- transit viaduct (canon §3.7 transit_viaduct — the elevated rail of a post-solarpunk city) ---

const DECK_TOP := 7.0        # deck surface height; underside 6.5 clears characters (3.0 law),
                             # level-1 balustrades (6.2) and every street it bridges
const DECK_W := 1.9

## Choose 1-2 lanes across the district. A lane must cross streets (that's the point of a viaduct),
## avoid every upper-floor column (never thread a platform or ladder), keep spacing from its
## siblings, and find ground for at least two piers.
static func _plan_viaducts(seed_value: int, walk: Dictionary, upper: Dictionary, dist: Dictionary,
		w: int, h: int) -> Array:
	var rng := _rng(seed_value, "bld:viaduct")
	var want := 1 + (1 if _rf(rng) < 0.35 else 0)
	var plans: Array = []
	var taken := {}
	for _attempt in range(14):
		if plans.size() >= want:
			break
		var axis := 0 if _rf(rng) < 0.5 else 1     # 0: runs along X at row `lane`; 1: along Z at column
		var dim := h if axis == 0 else w
		var run := w if axis == 0 else h
		if dim < 8 or run < 8:
			continue
		var lane := _ri(rng, int(float(dim) * 0.25), int(float(dim) * 0.75))
		var spaced := true
		for tl in taken.get(axis, []):
			if absi(int(tl) - lane) < 4:
				spaced = false
		if not spaced:
			continue
		var crossings := 0
		var blocked := false
		for i in range(run):
			var c := Vector2i(i, lane) if axis == 0 else Vector2i(lane, i)
			if upper.has(c):
				blocked = true
				break
			if walk.has(c):
				crossings += 1
		if blocked or crossings < 2:
			continue
		var piers: Array = []
		for i in range(1, run - 1, 3):
			var c := Vector2i(i, lane) if axis == 0 else Vector2i(lane, i)
			# a pier is FAT (0.85 sq) — kerb cells (dist 1) put it inside the street's clearance,
			# so piers stand at dist >= 2 and the deck simply spans further over street + kerb.
			if walk.has(c) or int(dist.get(c, 0)) < 2:
				continue
			piers.append(c)
		if piers.size() < 2:
			continue
		var gantries: Array = []
		for i in range(3, run - 3, 7):
			if _window_clear(i, lane, axis, upper):
				gantries.append(i)
		var tram := -1
		var tri := _ri(rng, 2, run - 3)
		if _window_clear(tri, lane, axis, upper):
			tram = tri
		plans.append({"axis": axis, "lane": lane, "piers": piers, "gantries": gantries, "tram": tram})
		if not taken.has(axis):
			taken[axis] = []
		taken[axis].append(lane)
	return plans

static func _window_clear(i: int, lane: int, axis: int, upper: Dictionary) -> bool:
	for di in range(-1, 2):
		for dl in range(-1, 2):
			var c := Vector2i(i + di, lane + dl) if axis == 0 else Vector2i(lane + dl, i + di)
			if upper.has(c):
				return false
	return true

static func _emit_viaduct(frag: Fragment, plan: Dictionary, origin: Vector3, cs: float,
		w: int, h: int, deck_top: float, stats: Dictionary) -> void:
	var axis := int(plan["axis"])
	var lane := int(plan["lane"])
	var run := w if axis == 0 else h
	var lane_c := (origin.z if axis == 0 else origin.x) + (float(lane) + 0.5) * cs
	var run0 := (origin.x if axis == 0 else origin.z)
	var run_len := float(run) * cs
	var run_c := run0 + run_len * 0.5
	var underside := deck_top - 0.5
	var deck_col := Color(0.14, 0.16, 0.18)
	var rail_col := Color(0.10, 0.115, 0.135)
	var pier_col := Color(0.15, 0.16, 0.17)

	# axis 0 boxes span X and sit at Z=lane_c; axis 1 swaps. _vx handles the swap once.
	_boxt(frag, _vx(axis, run_c, deck_top - 0.25, lane_c), _vs(axis, run_len, 0.5, DECK_W), deck_col, "deck_metal", stats)
	for s: float in [-1.0, 1.0]:
		_box(frag, _vx(axis, run_c, deck_top + 0.35, lane_c + s * (DECK_W * 0.5 - 0.08)),
			_vs(axis, run_len, 0.7, 0.1), rail_col, stats)
		_box_glow(frag, _vx(axis, run_c, deck_top + 0.72, lane_c + s * (DECK_W * 0.5 - 0.16)),
			_vs(axis, run_len, 0.06, 0.05), Color(0.05, 0.08, 0.06), GLOW_GREEN, 0.7, stats)
	for pc in plan["piers"]:
		var pi := (pc as Vector2i).x if axis == 0 else (pc as Vector2i).y
		var px := run0 + (float(pi) + 0.5) * cs
		var col_h := underside - 0.3 - 4.2
		_boxt(frag, _vx(axis, px, 2.1, lane_c), _vs(axis, 0.85, 4.2, 0.85), pier_col, "facility_metal", stats)
		_boxt(frag, _vx(axis, px, 4.2 + col_h * 0.5, lane_c), _vs(axis, 0.55, col_h, 0.55),
			pier_col.darkened(0.06), "facility_metal", stats)
		_box(frag, _vx(axis, px, underside - 0.15, lane_c), _vs(axis, 0.5, 0.3, DECK_W + 0.2),
			pier_col.darkened(0.12), stats)
	var alt := true
	for gi in plan["gantries"]:
		var gx := run0 + (float(int(gi)) + 0.5) * cs
		for s: float in [-1.0, 1.0]:
			_box(frag, _vx(axis, gx, deck_top + 0.7, lane_c + s * (DECK_W * 0.5 + 0.14)),
				_vs(axis, 0.12, 1.4, 0.12), rail_col, stats)
		_box(frag, _vx(axis, gx, deck_top + 1.42, lane_c), _vs(axis, 0.12, 0.12, DECK_W + 0.5), rail_col, stats)
		_box_glow(frag, _vx(axis, gx, deck_top + 1.3, lane_c), _vs(axis, 0.1, 0.12, 0.1),
			Color(0.06, 0.06, 0.07), GLOW_GREEN if alt else GLOW_WARM, 1.0, stats)
		alt = not alt
	if int(plan["tram"]) >= 0:
		var tx := run0 + (float(int(plan["tram"])) + 0.5) * cs
		_box(frag, _vx(axis, tx, deck_top + 0.48, lane_c), _vs(axis, 2.7, 0.95, 1.24), Color(0.16, 0.20, 0.21), stats)
		_box_glow(frag, _vx(axis, tx, deck_top + 0.62, lane_c + DECK_W * 0.5 - 0.55),
			_vs(axis, 1.9, 0.14, 0.05), Color(0.06, 0.07, 0.07), GLOW_WARM, 0.55, stats)

static func _vx(axis: int, along: float, y: float, across: float) -> Vector3:
	return Vector3(along, y, across) if axis == 0 else Vector3(across, y, along)

static func _vs(axis: int, along: float, y: float, across: float) -> Vector3:
	return Vector3(along, y, across) if axis == 0 else Vector3(across, y, along)

# --- street furniture (canon §3.12 names; box-compound reads, no collision) ---

# street_lamp: post + short arm + head. A LIT head glows; with_light adds a real OmniLight pool.
static func _prop_street_lamp(frag: Fragment, p: Vector2, facing: Vector2i, lit: bool,
		with_light: bool, stats: Dictionary) -> void:
	var pole_col := Color(0.10, 0.11, 0.13)
	_box(frag, Vector3(p.x, 1.6, p.y), Vector3(0.1, 3.2, 0.1), pole_col, stats)
	var arm := Vector2(float(facing.x), float(facing.y)) * 0.25
	_box(frag, Vector3(p.x + arm.x * 0.5, 3.15, p.y + arm.y * 0.5),
		Vector3(absf(arm.x) + 0.08, 0.08, absf(arm.y) + 0.08), pole_col, stats)
	var head := Vector3(p.x + arm.x, 3.05, p.y + arm.y)
	if lit:
		_box_glow(frag, head, Vector3(0.26, 0.18, 0.26), Color(0.08, 0.09, 0.08), GLOW_GREEN, 1.5, stats)
		if with_light:
			frag.lights.append({"pos": head - Vector3(0, 0.3, 0), "color": Color(0.45, 0.85, 0.55),
				"energy": 1.1, "range": 4.5})
	else:
		_box(frag, head, Vector3(0.26, 0.18, 0.26), Color(0.08, 0.09, 0.08), stats)

# planter_trough: tended (green top) or desiccated (dun top) — the decay field decides.
static func _prop_planter(frag: Fragment, p: Vector2, facing: Vector2i, decay: float, stats: Dictionary) -> void:
	var along_x := facing.y != 0   # trough runs parallel to the street edge
	_box(frag, Vector3(p.x, 0.22, p.y),
		Vector3(1.3, 0.44, 0.5) if along_x else Vector3(0.5, 0.44, 1.3), Color(0.12, 0.12, 0.13), stats)
	var top_col := Color(0.15, 0.32, 0.19) if decay < 0.5 else Color(0.24, 0.19, 0.12)
	_box(frag, Vector3(p.x, 0.5, p.y),
		Vector3(1.15, 0.22, 0.38) if along_x else Vector3(0.38, 0.22, 1.15), top_col, stats)

# bollard_row: three posts guarding the kerb.
static func _prop_bollards(frag: Fragment, p: Vector2, facing: Vector2i, stats: Dictionary) -> void:
	var along := Vector2(float(absi(facing.y)), float(absi(facing.x)))
	for i in range(3):
		var off := along * (float(i) - 1.0) * 0.5
		_box(frag, Vector3(p.x + off.x, 0.35, p.y + off.y), Vector3(0.14, 0.7, 0.14),
			Color(0.14, 0.15, 0.17), stats)

# a stub of surfaced pipework breaking the kerb line (the pipe_root_spread's street-side cousin).
static func _prop_pipe_stub(frag: Fragment, p: Vector2, facing: Vector2i, stats: Dictionary) -> void:
	var along_x := facing.y != 0
	var pipe_col := Color(0.21, 0.13, 0.09)
	_box(frag, Vector3(p.x, 0.14, p.y),
		Vector3(1.1, 0.16, 0.16) if along_x else Vector3(0.16, 0.16, 1.1), pipe_col, stats)
	_box(frag, Vector3(p.x, 0.5, p.y), Vector3(0.15, 0.9, 0.15), pipe_col.darkened(0.1), stats)

# memorial_monument: plinth + shaft + a terminal-green plaque; one per district at most.
static func _prop_monument(frag: Fragment, p: Vector2, stats: Dictionary) -> void:
	_box(frag, Vector3(p.x, 0.25, p.y), Vector3(1.0, 0.5, 1.0), Color(0.17, 0.18, 0.20), stats)
	_box(frag, Vector3(p.x, 1.6, p.y), Vector3(0.46, 2.2, 0.46), Color(0.15, 0.16, 0.18), stats)
	_box_glow(frag, Vector3(p.x, 1.0, p.y + 0.27), Vector3(0.3, 0.34, 0.04),
		Color(0.06, 0.07, 0.06), GLOW_GREEN, 1.2, stats)

static func _box(frag: Fragment, pos: Vector3, size: Vector3, color: Color, stats: Dictionary) -> void:
	frag.walls.append({"pos": pos, "size": size, "color": color})
	stats["boxes"] = int(stats.get("boxes", 0)) + 1

# A box carrying a pixel-art atlas tile ("tile" key — the loader tints the world-triplanar
# 1-tile/m material with the box colour, so the palette fields survive texturing).
static func _boxt(frag: Fragment, pos: Vector3, size: Vector3, color: Color, tile: String, stats: Dictionary) -> void:
	frag.walls.append({"pos": pos, "size": size, "color": color, "tile": tile})
	stats["boxes"] = int(stats.get("boxes", 0)) + 1

static func _box_glow(frag: Fragment, pos: Vector3, size: Vector3, color: Color, emission: Color,
		energy: float, stats: Dictionary) -> void:
	frag.walls.append({"pos": pos, "size": size, "color": color, "emission": emission, "energy": energy})
	stats["boxes"] = int(stats.get("boxes", 0)) + 1
