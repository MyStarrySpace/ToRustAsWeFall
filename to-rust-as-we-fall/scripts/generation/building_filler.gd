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
const GLOW_CYAN := Color(0.42, 0.72, 0.95)   # cold office / scanner light (the second saturated anchor)

# PROGRAM ARCHETYPES — the connective economy that fills BETWEEN the district hero cores
# (ARCHITECTURE_DESIGN.md §4.18-4.24). A low street-hugging box lot is assigned a program, which
# drives its facade/crown/entry SIGNATURE so the fill reads as commerce / manufacturing / supply
# chain / offices instead of anonymous boxes. Taller deep-block lots stay hero-silhouette lathe
# towers (untouched). Programs are chosen from the same seeded fields + per-lot hash, so the mix is
# deterministic and transitions smoothly like every other filler parameter.
const PROGRAMS := ["retail", "office", "warehouse", "fabrication", "crossdock", "mixed", "generic"]

# District-IDIOM weighting (opts.idiom): the built environment's class register (GDD §4.11).
# capitalist = The Hypelines / The Cleanstreets (always-open commerce, logistics); institutional =
# the central-facility clerical core; industrial = the supply-chain belt; socialist = the collectives
# (NO always-open retail — their idiom has none); mixed = the default even spread.
const IDIOM_WEIGHTS := {
	"mixed":         {"retail": 3, "office": 3, "warehouse": 2, "fabrication": 2, "crossdock": 1, "mixed": 3, "generic": 4},
	"capitalist":    {"retail": 6, "office": 2, "warehouse": 3, "fabrication": 1, "crossdock": 3, "mixed": 3, "generic": 2},
	"institutional": {"retail": 1, "office": 7, "warehouse": 2, "fabrication": 1, "crossdock": 1, "mixed": 2, "generic": 3},
	"industrial":    {"retail": 1, "office": 1, "warehouse": 5, "fabrication": 5, "crossdock": 4, "mixed": 1, "generic": 2},
	"socialist":     {"retail": 0, "office": 2, "warehouse": 1, "fabrication": 3, "crossdock": 1, "mixed": 4, "generic": 6},
}

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
	# THE 3D RESERVATION GRID (district_volume.gd): laid out FIRST, before any packing or meshing —
	# streets claim their head-room columns, viaduct corridors claim their deck bands, landmarks and
	# fabric lots claim their build volumes. Roads-through-buildings become a recorded conflict at
	# reservation time instead of geometry, and the audit re-checks the emitted boxes.
	var vol := DistrictVolume.over_grid(grid)
	vol.claim_streets(walk)
	var viaducts_on := bool(opts.get("viaducts", true))
	var via_plans: Array = []
	var corridors: Array = []
	var used := {}
	if viaducts_on:
		via_plans = _plan_viaducts(seed_value, walk, upper, dist, w, h)
		for vi in range(via_plans.size()):
			var pl: Dictionary = via_plans[vi]
			var deck_y := DECK_TOP + 0.9 * float(vi)
			var band := {"axis": int(pl["axis"]), "lane": int(pl["lane"]),
				"y0": deck_y - 0.65, "y1": deck_y + 2.0}
			corridors.append(band)
			var run := w if int(pl["axis"]) == 0 else h
			for i in range(run):
				var lane_cell := Vector2i(i, int(pl["lane"])) if int(pl["axis"]) == 0 else Vector2i(int(pl["lane"]), i)
				vol.claim_cell(lane_cell, float(band["y0"]), float(band["y1"]), "viaduct")
			for pc in pl["piers"]:
				used[pc] = true
				vol.claim_cell(pc as Vector2i, 0.0, deck_y, "viaduct")

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
	var service_links: Array = []
	if bool(opts.get("landmarks", true)):
		var lm := _plan_landmarks(seed_value, lots, walk, origin, cs, w, h, frag, grid, vol,
			str(opts.get("idiom", "mixed")))
		landmarks = lm["landmarks"]
		bridge_plans = lm["bridges"]
		service_links = lm["service_links"]
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
	var idiom := str(opts.get("idiom", "mixed"))
	var decay_bias := clampf(float(opts.get("decay_add", 0.0)), 0.0, 0.9)
	if not IDIOM_WEIGHTS.has(idiom):
		idiom = "mixed"
	var program_tally := {}
	var dock_plans: Array = []
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
		var decay := clampf(_n01(f_decay, center.x, center.y) + decay_bias, 0.0, 1.0)
		var glow_density := _n01(f_glow, center.x, center.y) * (1.0 - decay * 0.7)

		# Canyon profile: a strict height CONE from the street outward — a lot N cells from a street
		# never exceeds N storeys, so kerbside stays low (camera never fights a tower) and the field's
		# talls only realize deep in the block.
		var damp := clampf((float(lot["dist"]) - 1.0) / 3.0, 0.3, 1.0)
		var floors := clampi(1 + int(round(t_h * float(MAX_FLOORS - 1) * damp)), 1, MAX_FLOORS)
		floors = mini(floors, int(lot["dist"]))
		# The rail corridor: a lane CROSSING the lot can PLUG THROUGH it (the road threads a framed
		# aperture — the reservation grid makes that a legitimate shared claim); a lane merely
		# adjacent keeps the under-deck cap and may earn a roof DOCK instead.
		var cross_band := {}
		var cross_count := 0
		var adjacent_plan := {}
		for pvi in range(via_plans.size()):
			var pl: Dictionary = via_plans[pvi]
			var lane := int(pl["lane"])
			var lo := lc.y if int(pl["axis"]) == 0 else lc.x
			var hi := lo + (gz if int(pl["axis"]) == 0 else gx) - 1
			if lane >= lo and lane <= hi:
				cross_count += 1
				if cross_band.is_empty():
					cross_band = {"plan": pl, "band": corridors[pvi], "vi": pvi}
			elif lane == lo - 1 or lane == hi + 1:
				if adjacent_plan.is_empty():
					adjacent_plan = {"plan": pl, "vi": pvi, "side": -1 if lane == lo - 1 else 1}
		var through := false
		if not cross_band.is_empty():
			# tall enough to bridge the corridor, moderate decay, seeded taste — and exactly ONE
			# crossing lane (a second corridor would slice the upper mass; it stays capped instead)
			through = cross_count == 1 and decay < 0.62 and mini(gx, gz) >= 2 and _rf(jitter) < 0.55
			if through:
				floors = 5 + (1 if _rf(jitter) < 0.4 else 0)
			else:
				floors = mini(floors, 2)
		elif not adjacent_plan.is_empty():
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
		var lot_rect_hi := Vector2i(lc.x + gx - 1, lc.y + gz - 1)
		var lot_owner := "lot:%d,%d" % [lc.x, lc.y]
		if through:
			# THE THROUGH-PORTAL BLOCK: the viaduct keeps its band; the building claims BELOW and
			# ABOVE it and walls the band off everywhere except the lane slot — a framed tunnel.
			var band: Dictionary = cross_band["band"]
			vol.claim_rect(lc, lot_rect_hi, 0.0, float(band["y0"]) - 0.15, lot_owner)
			vol.claim_rect(lc, lot_rect_hi, float(band["y1"]) + 0.15, height + 1.2, lot_owner)
			_emit_through_building(frag, mn, mx, height, base_col, decay, glow_density, t_pal,
				jitter, origin, cs, cross_band["plan"], band, facade_tile, stats)
			program_tally["through"] = int(program_tally.get("through", 0)) + 1
			out_lots.append({"center": Vector3(center.x, 0.0, center.y), "floors": floors,
				"height": height, "color": base_col, "through": true})
			continue
		# the lot's CEILING from the reservation grid: the lowest overhead corridor above it (the
		# per-lane proximity heuristic stays as a soft cap; the volume is the hard authority)
		var ceiling := vol.free_top(lc, lot_rect_hi, 0.0, lot_owner)
		if ceiling < height + 0.2:
			floors = maxi(1, mini(floors, int((ceiling - 0.6) / FLOOR_H)))
			height = floors * FLOOR_H
		if not adjacent_plan.is_empty() and floors == 2 and decay < 0.7 and _rf(jitter) < 0.5:
			# ROOF DOCK: this building plugs into the side rail — a stepped gangway drops from the
			# deck to its roof (planned here, emitted with the viaduct so the boxes are road-owned)
			dock_plans.append({"plan": adjacent_plan["plan"], "vi": int(adjacent_plan["vi"]),
				"side": int(adjacent_plan["side"]), "mn": mn, "mx": mx, "roof": height,
				"cell": lc, "gx": gx, "gz": gz, "street": street})
		if floors >= 3:
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
			# (3+ storeys only: the connective FABRIC — retail/shed/office/warehouse/dock — is the
			#  low street-hugger and takes the program box path below; drums rise deep in the block)
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
			vol.claim_rect(lc, lot_rect_hi, 0.0, height + 2.4, lot_owner)
			# the street-face entry kit still anchors the base (the reference towers keep a kiosk)
			_emit_entry(frag, mn, mx, base_col, decay, t_pal, jitter, street, props_on, stats)
		else:
			var program := _pick_program(idiom, decay, t_pal, glow_density, floors, jitter)
			program_tally[program] = int(program_tally.get(program, 0)) + 1
			vol.claim_rect(lc, lot_rect_hi, 0.0, minf(height + 2.4, ceiling), lot_owner)
			_emit_building(frag, mn, mx, height, floors, base_col, decay, glow_density, t_pal, jitter,
				street, props_on, facade_tile, program, minf(ceiling - 0.25, 1.0e9), stats)
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
	var via_boxes_start := frag.walls.size()
	var walk_decks := 0
	var deck_links := 0
	var deck_routes: Array = []
	var dock_gangs: Array = []
	var walkable_vis := {}
	if viaducts_on:
		var stats_v := {"boxes": 0}
		var lh := float(grid.get("level_height", 4.0))
		for vi2 in range(via_plans.size()):
			var pl2: Dictionary = via_plans[vi2]
			var deck_y := DECK_TOP + 0.9 * float(vi2)
			var lvl := int(round(deck_y / lh))
			var walkable_line: bool = lvl >= 1 and absf(deck_y - float(lvl) * lh) < 0.05
			if walkable_line:
				# a WALKABLE line parks no tram across its deck (a stalled car would split the walk)
				pl2["tram"] = -1
			_emit_viaduct(frag, pl2, origin, cs, w, h, deck_y, stats_v)
			if walkable_line:
				# THE DECK IS A GRID FLOOR: register every lane cell at its level, and drop ladder
				# links at street crossings so the line is climbable from the ground it spans.
				var axis2 := int(pl2["axis"])
				var lane2 := int(pl2["lane"])
				var run2 := w if axis2 == 0 else h
				var deck_cells: Array = []
				var crossing_cells: Array = []
				for i2 in range(run2):
					var dc := Vector2i(i2, lane2) if axis2 == 0 else Vector2i(lane2, i2)
					deck_cells.append([dc.x, dc.y])
					if walk.has(dc):
						crossing_cells.append(dc)
				var link_cells: Array = []
				if crossing_cells.size() >= 1:
					link_cells.append(crossing_cells[0])
				if crossing_cells.size() >= 3:
					link_cells.append(crossing_cells[crossing_cells.size() - 1])
				var link_arr: Array = []
				for lcv in link_cells:
					link_arr.append([(lcv as Vector2i).x, (lcv as Vector2i).y])
				_apply_bridge_to_grid(grid, {"level": lvl, "cells": deck_cells, "links": link_arr})
				walk_decks += 1
				deck_links += link_arr.size()
				walkable_vis[vi2] = true
				deck_routes.append({"level": lvl, "cells": deck_cells, "links": link_arr,
					"axis": axis2, "lane": lane2, "deck_y": deck_y})
				for lcv2 in link_cells:
					var link_c: Vector2i = lcv2
					var stand := Vector2i(-1, -1)
					for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var cand: Vector2i = link_c + nb
						if not walk.has(cand) and cand.x >= 0 and cand.y >= 0 and cand.x < w and cand.y < h:
							stand = cand
							break
					if stand.x >= 0:
						_emit_deck_ladder(frag, stand, link_c, origin, cs, deck_y, stats_v)
		for dp in dock_plans:
			var dpd := dp as Dictionary
			var dock_deck_y := DECK_TOP + 0.9 * float(dpd["vi"])
			_emit_rail_dock(frag, dpd, origin, cs, dock_deck_y, stats_v)
			# a dock on a WALKABLE line becomes a GANGWAY crawl: deck -> roof hatch -> down
			# through the building -> out its street door (one way; the grammar emits the object)
			if walkable_vis.has(int(dpd["vi"])):
				dock_gangs.append(_dock_gang_spec(dpd, origin, cs, dock_deck_y))

	# THE GEOMETRY AUDIT: every non-viaduct box the filler emitted, checked against the walkable
	# street columns and the viaduct corridor bands. Green = the reservation grid held.
	var violations: Array = vol.audit_boxes(frag.walls, boxes_before, via_boxes_start, walk, corridors)

	return {"buildings": out_lots.size(), "boxes": frag.walls.size() - boxes_before,
		"props": prop_count, "viaducts": via_plans.size(), "lathes": lathes, "lots": out_lots,
		"landmarks": landmarks, "bridges": bridge_plans, "programs": program_tally,
		"service_links": service_links,
		"through_blocks": int(program_tally.get("through", 0)), "rail_docks": dock_plans.size(),
		"walk_decks": walk_decks, "deck_links": deck_links,
		"deck_routes": deck_routes, "dock_gangs": dock_gangs,
		"volume_conflicts": vol.conflicts, "volume_violations": violations}

# --- LANDMARKS: BaseShapeBuilder heroes whose gameplay anchors the level consumes ------------------

## The landmark pool: each kind declares the LOT SIDE it needs (cells at cs=1.5). The rebuilt
## districts joined the pool — survey-built, parametric, with playable anchors (crumble traps,
## balcony flora, walkable lane docks). Cleanstreets' 11 m pavilion needs bespoke lots (later).
## Elevated overhangs (hypelines arm decks at the 4.0 m level plane) are street-legal; ground
## overhang stays within ~0.15 m of the lot rim by these sizings.
const LANDMARK_KINDS := {
	"bulwark_wharf": 3, "tiered_terrace": 3, "plumbing_power": 3,
	# hypelines' ground lobes poke ~0.25 m past a 3-cell lot rim and its arm decks fly at the
	# legal 4.0 m plane; ancourage's overhang is the ELEVATED brim (its roots are ground clutter
	# by design). greenfields has solid street-level walls, so it genuinely needs a 4-cell lot.
	"ancourage": 3, "greenfields": 4, "hypelines": 3,
	"fabrication_hall": 3, "bonded_warehouse": 3, "reclamation_works": 3,
	"distribution_substation": 3,
}
const INFRASTRUCTURE_KINDS := ["fabrication_hall", "bonded_warehouse", "reclamation_works",
	"distribution_substation"]
const BRIDGE_MIN_SPAN := 3.0
const BRIDGE_MAX_SPAN := 16.0
const BRIDGE_LEVEL_TOL := 1.4    # a socket may sit this far off a level plane and still snap to it

# Pick up to two big street-adjacent lots, orient each landmark's MAIN door to its street (the road
# connector), carve the approach, and bridge the pair's facing ledge sockets when the lane is clear.
static func _plan_landmarks(seed_value: int, lots: Array, walk: Dictionary, origin: Vector3, cs: float,
		w: int, h: int, frag: Fragment, grid: Dictionary, vol: DistrictVolume = null,
		idiom: String = "mixed") -> Dictionary:
	var out := {"landmarks": [], "bridges": [], "service_links": [], "consumed": {}}
	var cands: Array = []
	for li in range(lots.size()):
		var lot := lots[li] as Dictionary
		if int(lot["gx"]) >= 3 and int(lot["gz"]) >= 3 and int(lot["dist"]) <= 3:
			# a hero rises ~26 m — its whole column must be free of overhead corridors BEFORE it is
			# picked (the reservation grid is the authority; an unchecked pick lets a viaduct slice a dome)
			if vol != null:
				var lc_c: Vector2i = lot["cell"]
				var rect_hi := Vector2i(lc_c.x + int(lot["gx"]) - 1, lc_c.y + int(lot["gz"]) - 1)
				if vol.rect_blocked(lc_c, rect_hi, 0.0, 26.0, "street") != "":
					continue
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
	var prev_kind := ""
	for pi in range(picks.size()):
		var li2 := int(picks[pi])
		out["consumed"][li2] = true
		var lot2 := lots[li2] as Dictionary
		var lc: Vector2i = lot2["cell"]
		var gx := int(lot2["gx"])
		var gz := int(lot2["gz"])
		if vol != null:
			vol.claim_rect(lc, Vector2i(lc.x + gx - 1, lc.y + gz - 1), 0.0, 26.0,
				"landmark:%d" % li2)
		# kinds that FIT this lot (and differ from the pair's first pick, for variety)
		var fits: Array = []
		for kk in LANDMARK_KINDS.keys():
			if int(LANDMARK_KINDS[kk]) <= mini(gx, gz) and str(kk) != prev_kind:
				fits.append(kk)
		if fits.is_empty():
			fits = ["bulwark_wharf"]
		var choice_pool := fits
		var infra_fits: Array = []
		for fit_v in fits:
			if INFRASTRUCTURE_KINDS.has(str(fit_v)):
				infra_fits.append(fit_v)
		if pi == 0 and not infra_fits.is_empty() and (idiom == "industrial" or _rf(rng) < 0.55):
			choice_pool = infra_fits
		elif pi > 0 and INFRASTRUCTURE_KINDS.has(prev_kind):
			var compatible := _compatible_service_kinds(prev_kind, fits)
			if not compatible.is_empty():
				choice_pool = compatible
		var kind := str(choice_pool[_ri(rng, 0, choice_pool.size() - 1)])
		prev_kind = kind
		var spec_seed := _ri(rng, 1, 999983)
		var spec: Dictionary = BaseShapeBuilder.generate(kind, spec_seed)
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
		var service_ports: Array = []
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
		for service_v in (anchors.get("service_ports", []) as Array):
			var service := service_v as Dictionary
			var sp := pos + basis * (service["pos"] as Vector3)
			var sd := basis * (service["dir"] as Vector3)
			service_ports.append({"id": service["id"], "commodity": service["commodity"],
				"flow": service["flow"], "width": float(service["width"]),
				"pos": [sp.x, sp.y, sp.z], "dir": [sd.x, sd.y, sd.z]})
		(out["landmarks"] as Array).append({"kind": kind, "pos": [pos.x, pos.y, pos.z], "yaw": yaw,
			"spec_seed": spec_seed,
			"street": [sdir.x, sdir.y], "door_cell": [door_cell.x, door_cell.y],
			"door_pos": [door_w.x, door_w.y, door_w.z], "approach": approach,
			"sockets": socks, "lanes": lanes, "service_ports": service_ports,
			"system_role": str(spec.get("system_role", "")),
			"supply_chain_stage": str(spec.get("supply_chain_stage", ""))})
		# BALCONY slots grow flora: seeded glowing plants on the tier ledges — the building is
		# level dressing and a light source, not scenery (the plants ride the survey's sockets)
		for a4 in (anchors.get("balcony_slots", []) as Array):
			var bd := a4 as Dictionary
			if _rf(rng) > 0.6:
				continue
			var fw := pos + basis * (bd["pos"] as Vector3)
			frag.objects.append({"type": "flora_light", "pos": fw,
				"opts": {"radius": 2.6, "energy": 1.1}})
		# EVERY landmark spends one structural WEAK POINT as a playable crumble trap: the pry
		# point at the wall foot, the kill zone on the ground in front of the face
		if not (anchors.get("weak_points", []) as Array).is_empty():
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
		var service_plan := plan_service_link((out["landmarks"] as Array)[0] as Dictionary,
			(out["landmarks"] as Array)[1] as Dictionary)
		if not service_plan.is_empty():
			(out["service_links"] as Array).append(service_plan)
			# A typed exchange is also a playable two-stage operation. The loader turns this plain data
			# into shared Interactables + causal links + one marked environmental field; no generated
			# building script gets its own bespoke click behavior.
			frag.objects.append(service_operation_from_link(service_plan))
		var plan := plan_bridge((out["landmarks"] as Array)[0] as Dictionary,
			(out["landmarks"] as Array)[1] as Dictionary, walk, origin, cs,
			float(grid.get("level_height", 4.0)))
		if not plan.is_empty():
			(out["bridges"] as Array).append(plan)
			_apply_bridge_to_grid(grid, plan)
			_emit_bridge(frag, plan, origin, cs)
	return out

## Pick kinds that can exchange at least one exact commodity. This is the causal grammar: the first
## structure constrains the second by its declared ports instead of only by silhouette variety.
static func _compatible_service_kinds(first_kind: String, fits: Array) -> Array:
	var first: Dictionary = BaseShapeBuilder.SPECS.get(first_kind, {})
	var out: Array = []
	for fit_v in fits:
		var candidate: Dictionary = BaseShapeBuilder.SPECS.get(str(fit_v), {})
		if _service_specs_compatible(first, candidate):
			out.append(fit_v)
	return out

static func _service_specs_compatible(a: Dictionary, b: Dictionary) -> bool:
	for pa_v in (a.get("service_ports", []) as Array):
		var pa := pa_v as Dictionary
		for pb_v in (b.get("service_ports", []) as Array):
			var pb := pb_v as Dictionary
			if str(pa.get("commodity", "")) == str(pb.get("commodity", "")) \
					and str(pa.get("flow", "")) != str(pb.get("flow", "")):
				return true
	return false

## Resolve one directed link between two already world-transformed landmark plans. The link is data,
## not a collision-bearing pipe across the street; theme/encounter layers may render it overhead,
## underground, or as a causal overlay without changing the construction contract.
static func plan_service_link(lm_a: Dictionary, lm_b: Dictionary) -> Dictionary:
	for pair_v in [[lm_a, lm_b], [lm_b, lm_a]]:
		var pair := pair_v as Array
		var source := pair[0] as Dictionary
		var sink := pair[1] as Dictionary
		for out_v in (source.get("service_ports", []) as Array):
			var output := out_v as Dictionary
			if str(output.get("flow", "")) != "out":
				continue
			for in_v in (sink.get("service_ports", []) as Array):
				var input := in_v as Dictionary
				if str(input.get("flow", "")) != "in" \
						or str(input.get("commodity", "")) != str(output.get("commodity", "")):
					continue
				var source_control := _landmark_control_position(source)
				var receiver_control := _landmark_control_position(sink)
				var street := _landmark_street_vector(sink)
				var effect_pos := receiver_control + street * 1.55
				return {"commodity": output["commodity"],
					"from_kind": str(source.get("kind", "")), "from_port": output["id"],
					"from_pos": output["pos"], "to_kind": str(sink.get("kind", "")),
					"to_port": input["id"], "to_pos": input["pos"],
					"source_control_pos": source_control,
					"receiver_control_pos": receiver_control,
					"effect_pos": effect_pos,
					"effect_half": Vector2(0.72, 1.18) if absf(street.x) > 0.5 else Vector2(1.18, 0.72)}
	return {}


## Convert a typed architectural exchange into the loader's reusable playable contract. Copy names the
## exact verb and consequence before commitment; the environmental field is deliberately local, visible,
## and optional, so failure tests a prediction instead of invalidating an otherwise solved stretch.
static func service_operation_from_link(link: Dictionary) -> Dictionary:
	var commodity := str(link.get("commodity", "service"))
	var language := _service_language(commodity)
	var from_kind := str(link.get("from_kind", "source"))
	var to_kind := str(link.get("to_kind", "receiver"))
	return {
		"type": "infrastructure_operation",
		"operation_id": "%s_%s_%s" % [commodity, from_kind, to_kind],
		"commodity": commodity,
		"source_kind": from_kind,
		"receiver_kind": to_kind,
		"source_name": _building_title(from_kind),
		"receiver_name": _building_title(to_kind),
		"source_control_pos": link.get("source_control_pos", Vector3.ZERO),
		"receiver_control_pos": link.get("receiver_control_pos", Vector3.ZERO),
		"effect_pos": link.get("effect_pos", Vector3.ZERO),
		"effect_half": link.get("effect_half", Vector2(1.18, 0.72)),
		"source_action": language["source_action"],
		"source_preview": language["source_preview"],
		"receiver_action": language["receiver_action"],
		"receiver_preview": language["receiver_preview"],
		"service_relationship": language["service_relationship"],
		"effect_relationship": language["effect_relationship"],
		"hazard_label": language["hazard_label"],
		"safe_label": language["safe_label"],
		"damage_per_second": language["damage_per_second"],
		"safe_concealment": language["safe_concealment"],
	}


static func _landmark_control_position(landmark: Dictionary) -> Vector3:
	var door := _arr3(landmark, "door_pos")
	if door == Vector3.ZERO:
		door = _arr3(landmark, "pos")
	return Vector3(door.x, 0.12, door.z) + _landmark_street_vector(landmark) * 0.42


static func _landmark_street_vector(landmark: Dictionary) -> Vector3:
	var raw: Variant = landmark.get("street", [0, 1])
	if raw is Array and (raw as Array).size() >= 2:
		var direction := Vector3(float(raw[0]), 0.0, float(raw[1]))
		return direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD
	return Vector3.FORWARD


static func _building_title(kind: String) -> String:
	return str((BaseShapeBuilder.SPECS.get(kind, {}) as Dictionary).get("title", kind.replace("_", " ").capitalize()))


static func _service_language(commodity: String) -> Dictionary:
	match commodity:
		"electricity":
			return {
				"source_action": "ROUTE POWER", "receiver_action": "GROUND AND START",
				"source_preview": "Energizes the receiving control and makes GROUND AND START available.",
				"receiver_preview": "Grounds the marked arc fault; the service approach stops draining health.",
				"service_relationship": "POWER FEEDS", "effect_relationship": "GROUNDS ARC FAULT",
				"hazard_label": "ARC FAULT", "safe_label": "GROUNDED SERVICE BAY",
				"damage_per_second": 2.0, "safe_concealment": false,
			}
		"fabricated_goods":
			return {
				"source_action": "DISPATCH PARTS", "receiver_action": "CLEAR RECEIVING",
				"source_preview": "Moves the parts order to receiving and makes CLEAR RECEIVING available.",
				"receiver_preview": "Moves the marked cargo spill off the service approach.",
				"service_relationship": "PARTS FEED", "effect_relationship": "CLEARS CARGO SPILL",
				"hazard_label": "UNSECURED CARGO", "safe_label": "RECEIVING LANE CLEAR",
				"damage_per_second": 1.5, "safe_concealment": false,
			}
		"wastewater":
			return {
				"source_action": "OPEN EFFLUENT LINE", "receiver_action": "RUN RECLAMATION",
				"source_preview": "Routes the effluent to reclamation and makes RUN RECLAMATION available.",
				"receiver_preview": "Filters the marked acid spill; the service approach stops draining health.",
				"service_relationship": "EFFLUENT FEEDS", "effect_relationship": "FILTERS ACID SPILL",
				"hazard_label": "ACID EFFLUENT", "safe_label": "FILTERED SERVICE BAY",
				"damage_per_second": 2.0, "safe_concealment": false,
			}
		"process_water":
			return {
				"source_action": "PUMP RECLAIMED WATER", "receiver_action": "FLUSH FABRICATION LINE",
				"source_preview": "Pressurizes the fabrication intake and makes FLUSH FABRICATION LINE available.",
				"receiver_preview": "Flushes the marked steam leak; the service approach stops draining health.",
				"service_relationship": "WATER FEEDS", "effect_relationship": "CLEARS STEAM LEAK",
				"hazard_label": "STEAM LEAK", "safe_label": "COOLED SERVICE BAY",
				"damage_per_second": 2.0, "safe_concealment": false,
			}
		"data":
			return {
				"source_action": "SEND MANIFEST", "receiver_action": "ACCEPT MANIFEST",
				"source_preview": "Sends the inventory manifest and makes ACCEPT MANIFEST available.",
				"receiver_preview": "Suppresses the marked enforcement scanner; its service bay becomes full cover.",
				"service_relationship": "MANIFEST FEEDS", "effect_relationship": "SUPPRESSES SCANNER",
				"hazard_label": "ENFORCEMENT SCANNER", "safe_label": "SCAN-BLIND SERVICE BAY",
				"damage_per_second": 0.0, "safe_concealment": true,
			}
		_:
			return {
				"source_action": "ROUTE SERVICE", "receiver_action": "COMMISSION RECEIVER",
				"source_preview": "Routes the typed service and makes COMMISSION RECEIVER available.",
				"receiver_preview": "Resolves the marked service fault on the approach.",
				"service_relationship": "SERVICE FEEDS", "effect_relationship": "RESOLVES FAULT",
				"hazard_label": "SERVICE FAULT", "safe_label": "SERVICE BAY SAFE",
				"damage_per_second": 1.5, "safe_concealment": false,
			}

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
	# THE UNION CONTRACT (unified_grid_v1): a cell is traversable at a level only if it is BOTH a
	# FLOOR tile (walkable_cells union) and in that level's allow-set. Upper cells must therefore
	# join the union — and the moment the union grows past the ground footprint, level 0 needs its
	# OWN explicit allow-set or the new cells would leak into ground walkability.
	var lvl0: Dictionary = {}
	for lce in level_cells:
		if int((lce as Dictionary).get("level", -1)) == 0:
			lvl0 = lce as Dictionary
	if lvl0.is_empty():
		lvl0 = {"level": 0, "cells": (grid.get("walkable_cells", []) as Array).duplicate()}
		level_cells.append(lvl0)
	var entry: Dictionary = {}
	for lce2 in level_cells:
		if int((lce2 as Dictionary).get("level", -1)) == lvl:
			entry = lce2 as Dictionary
	if entry.is_empty():
		entry = {"level": lvl, "cells": []}
		level_cells.append(entry)
	var union := grid.get("walkable_cells", []) as Array
	var seen := {}
	for uc in union:
		seen[Vector2i(int(uc[0]), int(uc[1]))] = true
	for c in (plan["cells"] as Array):
		(entry["cells"] as Array).append(c)
		var cv := Vector2i(int(c[0]), int(c[1]))
		if not seen.has(cv):
			seen[cv] = true
			union.append(c)
	grid["walkable_cells"] = union
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

## The connective-fabric dispatcher (ARCHITECTURE_DESIGN.md §4.18-4.24): a low box lot renders as
## its assigned PROGRAM — retail arcade / clerical office / bonded warehouse / fabrication shed /
## cross-dock yard / mixed-use infill — each a distinct facade+crown+entry signature layered over a
## shared slab massing. `generic` is the bare slab box with no program layered on. Every part
## is an axis-aligned box through _box/_boxt/_box_glow, so it stays collision-free, atlas-textured on
## legal tiles, emissive-pure, and seed-deterministic like the rest of the filler.
static func _emit_building(frag: Fragment, mn: Vector2, mx: Vector2, height: float, floors: int,
		base_col: Color, decay: float, glow_density: float, warm_bias: float, jitter: SeededRng,
		street: Vector2i, props_on: bool, facade_tile: String, program: String, max_top: float,
		stats: Dictionary) -> void:
	if program == "generic":
		_emit_generic_building(frag, mn, mx, height, floors, base_col, decay, glow_density, warm_bias,
			jitter, street, props_on, facade_tile, max_top, stats)
		return
	var c := Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5)
	var sz := Vector2(mx.x - mn.x, mx.y - mn.y)
	var horiz := street.y != 0   # street-face normal along Z -> the face runs along X

	# per-program palette + tile: industrial programs rust, offices pull toward clean teal panel
	var col := base_col
	var tile := facade_tile
	if program == "warehouse" or program == "fabrication":
		col = base_col.lerp(PAL_RUST, 0.28 + decay * 0.22)
		tile = "rust_iron" if decay > 0.4 else "facility_metal"
	elif program == "office":
		col = PAL_COOL.lerp(base_col, 0.5)
		tile = "wall_panel"

	# BASE MASS — even slab tiers (no organic slide; the fabric reads rectilinear against the drums).
	# crossdock is an open covered yard: only a low base plinth, then a canopy on posts.
	var base_h := height if program != "crossdock" else 0.7
	_boxt(frag, Vector3(c.x, base_h * 0.5 + 0.01, c.y), Vector3(sz.x, base_h, sz.y), col, tile, stats)
	if program != "crossdock":
		_facet_steps(frag, c, sz, base_h, col, tile, floors, stats)
	if program in ["warehouse", "office", "mixed"] and floors >= 2:
		# a subtle upper set-back so the slab isn't a pure prism
		var up_h := 0.14
		_boxt(frag, Vector3(c.x, height + up_h * 0.5, c.y), Vector3(sz.x * 0.94, up_h, sz.y * 0.94),
			col.darkened(0.1), tile, stats)

	var crown_room: float = max_top - height   # what the program may raise above its roofline
	match program:
		"retail":
			_sig_retail(frag, c, sz, height, street, horiz, col, decay, jitter, stats)
		"office":
			_sig_office(frag, c, sz, height, floors, street, horiz, col, glow_density, stats)
		"warehouse":
			_sig_warehouse(frag, c, sz, height, street, horiz, col, decay, jitter, stats)
		"fabrication":
			_sig_fabrication(frag, c, sz, height, street, horiz, col, decay, jitter, crown_room, stats)
		"crossdock":
			_sig_crossdock(frag, c, sz, base_h, street, horiz, col, stats)
		"mixed":
			_sig_mixed(frag, c, sz, height, floors, street, horiz, col, warm_bias, jitter, stats)

	# props: industrial/retail keep the street kit; offices stay tended (no pipe-root decay props)
	if program != "office":
		_emit_entry(frag, mn, mx, col, decay if program != "retail" else minf(decay, 0.4),
			warm_bias, jitter, street, props_on, stats)

## PLINTH + EAVE steps: two stepped facets that break the pure-prism read (the shape language's
## curve law realized as offsets — a skirt slab at the ground, an inset reveal band under the top).
static func _facet_steps(frag: Fragment, c: Vector2, sz: Vector2, height: float, col: Color,
		tile: String, floors: int, stats: Dictionary) -> void:
	_boxt(frag, Vector3(c.x, 0.14, c.y), Vector3(sz.x + 0.3, 0.28, sz.y + 0.3),
		col.darkened(0.16), tile, stats)
	if floors >= 2:
		_box(frag, Vector3(c.x, height - 0.42, c.y), Vector3(sz.x + 0.08, 0.14, sz.y + 0.08),
			col.darkened(0.22), stats)

## A faceted ARCH over an opening: two stepped lintel courses narrowing upward — the generator's
## curve idiom at door scale. Grate tile on the spandrel gives the lattice read.
static func _facet_arch(frag: Fragment, base: Vector3, horiz: bool, w0: float, col: Color,
		stats: Dictionary) -> void:
	_box(frag, base, Vector3(w0, 0.14, 0.08) if horiz else Vector3(0.08, 0.14, w0),
		col.darkened(0.28), stats)
	_box(frag, base + Vector3(0, 0.14, 0), Vector3(w0 * 0.62, 0.14, 0.08) if horiz
		else Vector3(0.08, 0.14, w0 * 0.62), col.darkened(0.34), stats)

## A grate-tile LATTICE band on the street face (mesh_lattice vocabulary: the grate tile reads as
## latticework at pixel-art scale).
static func _lattice_band(frag: Fragment, c: Vector2, sz: Vector2, street: Vector2i, horiz: bool,
		y: float, band_h: float, run_frac: float, col: Color, stats: Dictionary) -> void:
	var lp := _face_pt(c, sz, street, 0.045, y)
	_boxt(frag, lp, _face_sz(sz, horiz, run_frac, band_h, 0.07), col.lightened(0.2), "grate", stats)

## A point on the street face, pushed `out` beyond the wall, at height y.
static func _face_pt(c: Vector2, sz: Vector2, street: Vector2i, out: float, y: float) -> Vector3:
	return Vector3(c.x + float(street.x) * (sz.x * 0.5 + out), y, c.y + float(street.y) * (sz.y * 0.5 + out))

## A face-parallel box size: a run along the face (fraction of width) x height x thickness.
static func _face_sz(sz: Vector2, horiz: bool, run_frac: float, h: float, thick: float) -> Vector3:
	return Vector3(sz.x * run_frac, h, thick) if horiz else Vector3(thick, h, sz.y * run_frac)

## RETAIL ARCADE (§4.18): a row of shuttered bays under a continuous sagging slat-canopy, a hoarding
## band clad over the upper storey, an ALWAYS OPEN sign that always burns green (retail's signature).
static func _sig_retail(frag: Fragment, c: Vector2, sz: Vector2, height: float, street: Vector2i,
		horiz: bool, col: Color, decay: float, jitter: SeededRng, stats: Dictionary) -> void:
	var face_len := sz.x if horiz else sz.y
	# shutter bay row at the ground
	var bays := clampi(int(face_len / 1.4), 2, 4)
	for i in range(bays):
		var f := (float(i) + 0.5) / float(bays) - 0.5
		var along := Vector2(float(absi(street.y)), float(absi(street.x))) * (f * face_len)
		var bp := _face_pt(c, sz, street, 0.03, 1.0) + Vector3(along.x, 0.0, along.y)
		_box(frag, bp, _face_sz(sz, horiz, 0.7 / float(bays), 1.7, 0.06), col.darkened(0.5), stats)
	# continuous slat-canopy in three segments, the centre segment dipped (a sag)
	for seg in range(3):
		var f2 := (float(seg) - 1.0) * (face_len / 3.0)
		var along2 := Vector2(float(absi(street.y)), float(absi(street.x))) * f2
		var sag := 0.12 if seg == 1 else 0.0
		var cp := _face_pt(c, sz, street, 0.4, 2.0 - sag) + Vector3(along2.x, 0.0, along2.y)
		var csz := Vector3(sz.x / 3.0 + 0.1, 0.08, 0.9) if horiz else Vector3(0.9, 0.08, sz.y / 3.0 + 0.1)
		_box(frag, cp, csz, col.darkened(0.25), stats)
	# faceted arches over each bay + the lattice spandrel band above them (the arcade read)
	for i2 in range(bays):
		var fa := (float(i2) + 0.5) / float(bays) - 0.5
		var along_a := Vector2(float(absi(street.y)), float(absi(street.x))) * (fa * face_len)
		_facet_arch(frag, _face_pt(c, sz, street, 0.05, 1.95) + Vector3(along_a.x, 0.0, along_a.y),
			horiz, face_len * 0.62 / float(bays), col, stats)
	_lattice_band(frag, c, sz, street, horiz, 2.35, 0.34, 0.8, col, stats)
	# hoarding band clad over the upper storey (aspirational ad panel)
	var hb := _face_pt(c, sz, street, 0.05, height - 0.55)
	_boxt(frag, hb, _face_sz(sz, horiz, 0.86, 0.7, 0.08), col.lightened(0.16), "wall_panel", stats)
	# ALWAYS OPEN — always burns (the one building whose lights never go out)
	var sp := _face_pt(c, sz, street, 0.18, height - 0.55)
	_box_glow(frag, sp, _face_sz(sz, horiz, 0.5, 0.34, 0.06), Color(0.05, 0.08, 0.06), GLOW_GREEN,
		1.5, stats)

## CLERICAL OFFICE (§4.23): continuous cold-cyan ribbon glazing every floor on the street face and
## one flank, a service bulkhead cap — tended, no rust. Reads as a bank of screens.
static func _sig_office(frag: Fragment, c: Vector2, sz: Vector2, height: float, floors: int,
		street: Vector2i, horiz: bool, col: Color, glow_density: float, stats: Dictionary) -> void:
	var faces: Array[Vector2i] = [street, Vector2i(street.y, street.x)]
	for face in faces:
		var fh := face.y != 0
		var fl_count := maxi(floors, 1)
		for fl in range(fl_count):
			var fy := (float(fl) + 0.55) * FLOOR_H
			if fy > height - 0.35:
				continue
			var rp := _face_pt(c, sz, face, 0.04, fy)
			_box_glow(frag, rp, _face_sz(sz, fh, 0.82, 0.34, 0.05), Color(0.05, 0.06, 0.08),
				GLOW_CYAN, 0.9 + glow_density * 0.4, stats)
	# lattice reveal band under the crown (trabecular read), then the service bulkhead
	_lattice_band(frag, c, sz, street, horiz, height - 0.85, 0.3, 0.72, col, stats)
	_boxt(frag, Vector3(c.x + sz.x * 0.18, height + 0.32, c.y - sz.y * 0.14),
		Vector3(sz.x * 0.44, 0.64, sz.y * 0.44), col.darkened(0.18), "facility_metal", stats)

## BONDED WAREHOUSE (§4.21): windowless banded racking, pore vents, a parapet, and a bonded
## scan-cage entry (cyan) with a green inventory readout. Rust bleeds down the seams.
static func _sig_warehouse(frag: Fragment, c: Vector2, sz: Vector2, height: float, street: Vector2i,
		horiz: bool, col: Color, decay: float, jitter: SeededRng, stats: Dictionary) -> void:
	# horizontal racking bands across the street face (no windows)
	var bands := clampi(int(height / 1.3), 2, 5)
	for b in range(1, bands):
		var by := height * float(b) / float(bands)
		_box(frag, _face_pt(c, sz, street, 0.02, by), _face_sz(sz, horiz, 0.9, 0.1, 0.05),
			col.darkened(0.32), stats)
	# a couple of pore vents high up
	for v in range(2):
		var f := (float(v) - 0.5) * (sz.x if horiz else sz.y) * 0.5
		var along := Vector2(float(absi(street.y)), float(absi(street.x))) * f
		_box(frag, _face_pt(c, sz, street, 0.03, height - 0.6) + Vector3(along.x, 0.0, along.y),
			Vector3(0.4, 0.4, 0.06) if horiz else Vector3(0.06, 0.4, 0.4), col.darkened(0.4), stats)
	# ferric bleed streaks down the seams
	for st in range(2):
		var fs := (float(st) - 0.5) * (sz.x if horiz else sz.y) * 0.6
		var alongs := Vector2(float(absi(street.y)), float(absi(street.x))) * fs
		_box(frag, _face_pt(c, sz, street, 0.02, height * 0.5) + Vector3(alongs.x, 0.0, alongs.y),
			Vector3(0.12, height * 0.8, 0.04) if horiz else Vector3(0.04, height * 0.8, 0.12),
			PAL_RUST.darkened(0.1), stats)
	# parapet band around the top edge
	_box(frag, Vector3(c.x, height + 0.12, c.y), Vector3(sz.x + 0.1, 0.22, sz.y + 0.1),
		col.darkened(0.24), stats)
	# bonded scan-cage entry: a recessed dark door in a cyan frame + a green inventory readout aside
	var dp := _face_pt(c, sz, street, 0.03, 1.1)
	_box(frag, dp, _face_sz(sz, horiz, 0.28, 2.1, 0.06), col.darkened(0.55), stats)
	_box_glow(frag, dp + Vector3(0, 0.05, 0), _face_sz(sz, horiz, 0.34, 2.3, 0.04),
		Color(0.05, 0.06, 0.08), GLOW_CYAN, 1.1, stats)
	_facet_arch(frag, _face_pt(c, sz, street, 0.06, 2.35), horiz, 1.7, col, stats)
	var side := Vector2(float(absi(street.y)), float(absi(street.x))) * ((sz.x if horiz else sz.y) * 0.3)
	_box_glow(frag, _face_pt(c, sz, street, 0.05, 1.5) + Vector3(side.x, 0.0, side.y),
		Vector3(0.3, 0.3, 0.05) if horiz else Vector3(0.05, 0.3, 0.3), Color(0.05, 0.08, 0.06),
		GLOW_GREEN, 1.2, stats)

## FABRICATION SHED (§4.20): a long low hall with a sawtooth monitor-roof, ONE line still running
## (a single green strip through the clerestory + one on the wall), a wide roll-up door, vent stacks.
static func _sig_fabrication(frag: Fragment, c: Vector2, sz: Vector2, height: float, street: Vector2i,
		horiz: bool, col: Color, decay: float, jitter: SeededRng, crown_room: float, stats: Dictionary) -> void:
	# sawtooth monitor-roof: a row of short raised ridges along the long axis
	var ridges := clampi(int((sz.x if horiz else sz.y) / 1.6), 2, 5)
	for r in range(ridges):
		var f := (float(r) + 0.5) / float(ridges) - 0.5
		var along := Vector2(float(absi(street.y)), float(absi(street.x)))
		# ridge runs ACROSS the long axis (perpendicular to the face run)
		var rp := Vector3(c.x, height + 0.22, c.y) + Vector3(along.x * f * sz.x, 0.0, along.y * f * sz.y)
		_boxt(frag, rp, Vector3(sz.x / float(ridges) * 0.7, 0.44, sz.y * 0.9) if horiz
			else Vector3(sz.x * 0.9, 0.44, sz.y / float(ridges) * 0.7), col.darkened(0.2), "facility_metal", stats)
	# the ONE live line — a green clerestory strip on the roof ridge and one low on the wall
	_box_glow(frag, Vector3(c.x, height + 0.36, c.y), Vector3(sz.x * 0.7, 0.1, 0.06) if horiz
		else Vector3(0.06, 0.1, sz.y * 0.7), Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.3, stats)
	_box_glow(frag, _face_pt(c, sz, street, 0.03, 0.9), _face_sz(sz, horiz, 0.55, 0.16, 0.05),
		Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.0, stats)
	_lattice_band(frag, c, sz, street, horiz, height - 0.5, 0.36, 0.85, col, stats)
	# wide roll-up loading door under its faceted arch
	_box(frag, _face_pt(c, sz, street, 0.02, 1.1), _face_sz(sz, horiz, 0.5, 2.2, 0.06),
		col.darkened(0.5), stats)
	_facet_arch(frag, _face_pt(c, sz, street, 0.05, 2.3), horiz, (sz.x if horiz else sz.y) * 0.55,
		col, stats)
	# vent stacks on the roof (skipped when an overhead corridor leaves no room)
	if crown_room > 1.8:
		for vs in range(2):
			var voff := Vector2((float(vs) - 0.5) * sz.x * 0.4, (float(vs) - 0.5) * sz.y * 0.3)
			_boxt(frag, Vector3(c.x + voff.x, height + 0.9, c.y + voff.y), Vector3(0.4, 1.3, 0.4),
				col.darkened(0.3), "facility_metal", stats)

## CROSS-DOCK YARD (§4.22): an open covered apron — a canopy on corner posts over a low plinth —
## with a conveyor descent stub and a green diverter meter. Everything in transit, nothing enclosed.
static func _sig_crossdock(frag: Fragment, c: Vector2, sz: Vector2, base_h: float, street: Vector2i,
		horiz: bool, col: Color, stats: Dictionary) -> void:
	var cy := 2.4
	# four corner posts
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_box(frag, Vector3(c.x + dx * sz.x * 0.42, cy * 0.5, c.y + dz * sz.y * 0.42),
				Vector3(0.2, cy, 0.2), col.darkened(0.3), stats)
	# the canopy slab
	_boxt(frag, Vector3(c.x, cy + 0.08, c.y), Vector3(sz.x + 0.2, 0.16, sz.y + 0.2),
		col.darkened(0.18), "deck_metal", stats)
	# a conveyor descent stub coming down to the deck from the canopy edge (a stepped incline)
	for step in range(3):
		var t := float(step) / 3.0
		_box(frag, _face_pt(c, sz, street, 0.15, cy - 0.2 - t * 1.4),
			_face_sz(sz, horiz, 0.3, 0.14, 0.5), col.darkened(0.28), stats)
	# the lattice gantry arch across the yard mouth (grate infill over stepped courses)
	_facet_arch(frag, _face_pt(c, sz, street, 0.2, cy - 0.35), horiz, (sz.x if horiz else sz.y) * 0.8,
		col, stats)
	_lattice_band(frag, c, sz, street, horiz, cy - 0.62, 0.24, 0.75, col, stats)
	# green diverter meter at the deck
	_box_glow(frag, _face_pt(c, sz, street, 0.1, 1.0), Vector3(0.3, 0.5, 0.05) if horiz
		else Vector3(0.05, 0.5, 0.3), Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.3, stats)

## MIXED-USE INFILL (§4.24): the literal in-between block — shuttered retail below, cyan office
## ribbon in the middle, pore windows and one warm residential window at the crammed top; two signage
## registers overlapping (green + warm), the two neighbouring districts bleeding together.
static func _sig_mixed(frag: Fragment, c: Vector2, sz: Vector2, height: float, floors: int,
		street: Vector2i, horiz: bool, col: Color, warm_bias: float, jitter: SeededRng, stats: Dictionary) -> void:
	# ground: shutter bays
	var bays := clampi(int((sz.x if horiz else sz.y) / 1.4), 2, 3)
	for i in range(bays):
		var f := (float(i) + 0.5) / float(bays) - 0.5
		var along := Vector2(float(absi(street.y)), float(absi(street.x))) * (f * (sz.x if horiz else sz.y))
		_box(frag, _face_pt(c, sz, street, 0.03, 1.0) + Vector3(along.x, 0.0, along.y),
			_face_sz(sz, horiz, 0.7 / float(bays), 1.6, 0.06), col.darkened(0.5), stats)
	# mid: office ribbon (cyan)
	if height > FLOOR_H + 0.5:
		_box_glow(frag, _face_pt(c, sz, street, 0.04, FLOOR_H + 0.55), _face_sz(sz, horiz, 0.8, 0.3, 0.05),
			Color(0.05, 0.06, 0.08), GLOW_CYAN, 0.95, stats)
	# top: pore windows + ONE warm residential window
	var top_y := height - 0.55
	for v in range(2):
		var f2 := (float(v) - 0.5) * (sz.x if horiz else sz.y) * 0.45
		var along2 := Vector2(float(absi(street.y)), float(absi(street.x))) * f2
		_box_glow(frag, _face_pt(c, sz, street, 0.03, top_y) + Vector3(along2.x, 0.0, along2.y),
			Vector3(0.32, 0.34, 0.05) if horiz else Vector3(0.05, 0.34, 0.32), Color(0.06, 0.06, 0.05),
			GLOW_WARM if v == 0 else GLOW_GREEN, 1.1, stats)
	# stepped cornice (two shrinking bands — the faceted-curve read) + a grate balcony rail
	_box(frag, Vector3(c.x, height + 0.1, c.y), Vector3(sz.x * 0.98, 0.16, sz.y * 0.98),
		col.darkened(0.2), stats)
	_box(frag, Vector3(c.x, height + 0.24, c.y), Vector3(sz.x * 0.88, 0.12, sz.y * 0.88),
		col.darkened(0.26), stats)
	_lattice_band(frag, c, sz, street, horiz, top_y - 0.6, 0.4, 0.68, col, stats)
	# two signage registers overlapping near the door
	var dp := _face_pt(c, sz, street, 0.16, height * 0.5)
	_box_glow(frag, dp, Vector3(0.14, 0.5, 0.05) if horiz else Vector3(0.05, 0.5, 0.14),
		Color(0.06, 0.06, 0.07), GLOW_GREEN, 1.2, stats)
	_box_glow(frag, dp + Vector3(0.0, 0.7, 0.0), Vector3(0.12, 0.4, 0.05) if horiz else Vector3(0.05, 0.4, 0.12),
		Color(0.07, 0.06, 0.05), GLOW_WARM, 1.1, stats)

static func _emit_generic_building(frag: Fragment, mn: Vector2, mx: Vector2, height: float, floors: int,
		base_col: Color, decay: float, glow_density: float, warm_bias: float, jitter: SeededRng,
		street: Vector2i, props_on: bool, facade_tile: String, max_top: float, stats: Dictionary) -> void:
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
	if decay < 0.72 and height + 1.7 < max_top:
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

## THE THROUGH-PORTAL BLOCK: a tall slab the viaduct passes THROUGH. Lower mass to just under the
## corridor band, upper mass from just above it, SIDE masses walling the band off on every strip of
## the lot except the lane slot — so the road threads a real framed tunnel, not a gap between two
## buildings. Jamb columns, a lintel plate and a terminal-green edge strip frame the mouth. All
## boxes stay outside the corridor band on the lane cells by construction (the audit re-checks).
static func _emit_through_building(frag: Fragment, mn: Vector2, mx: Vector2, height: float,
		base_col: Color, decay: float, glow_density: float, warm_bias: float, jitter: SeededRng,
		origin: Vector3, cs: float, plan: Dictionary, band: Dictionary, facade_tile: String,
		stats: Dictionary) -> void:
	var c := Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5)
	var sz := Vector2(mx.x - mn.x, mx.y - mn.y)
	var axis := int(plan["axis"])
	var lane := int(plan["lane"])
	var y_lo := float(band["y0"]) - 0.15   # lower mass top
	var y_hi := float(band["y1"]) + 0.15   # upper mass bottom
	var col := base_col.darkened(0.04)
	# lower + upper masses
	_boxt(frag, Vector3(c.x, y_lo * 0.5, c.y), Vector3(sz.x, y_lo, sz.y), col, facade_tile, stats)
	_boxt(frag, Vector3(c.x, (y_hi + height) * 0.5, c.y), Vector3(sz.x, height - y_hi, sz.y),
		col.darkened(0.06), facade_tile, stats)
	# side masses: wall the band off outside the lane slot. The lane slot spans the lane cell
	# plus a margin; the side masses stop clear of it (and so clear of the corridor band cells).
	var slot_c := (origin.z if axis == 0 else origin.x) + (float(lane) + 0.5) * cs
	var slot_half := cs * 0.5 + 0.35
	var band_h := y_hi - y_lo
	if axis == 0:
		var s0 := slot_c - slot_half   # lot strip below the slot: [mn.y .. s0]
		if s0 - mn.y > 0.3:
			_boxt(frag, Vector3(c.x, y_lo + band_h * 0.5, (mn.y + s0) * 0.5),
				Vector3(sz.x, band_h, s0 - mn.y), col.darkened(0.03), facade_tile, stats)
		var s1 := slot_c + slot_half
		if mx.y - s1 > 0.3:
			_boxt(frag, Vector3(c.x, y_lo + band_h * 0.5, (s1 + mx.y) * 0.5),
				Vector3(sz.x, band_h, mx.y - s1), col.darkened(0.03), facade_tile, stats)
		# portal frame on both mouths: jambs + lintel + the green edge strip
		for mx_s: float in [mn.x, mx.x]:
			for jz: float in [slot_c - slot_half + 0.12, slot_c + slot_half - 0.12]:
				_box(frag, Vector3(mx_s, y_lo + band_h * 0.5, jz), Vector3(0.24, band_h, 0.24),
					col.darkened(0.3), stats)
			_box(frag, Vector3(mx_s, y_hi + 0.14, slot_c), Vector3(0.28, 0.28, slot_half * 2.0),
				col.darkened(0.3), stats)
			_box_glow(frag, Vector3(mx_s, y_hi + 0.03, slot_c), Vector3(0.1, 0.05, slot_half * 1.6),
				Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.2, stats)
	else:
		var t0 := slot_c - slot_half
		if t0 - mn.x > 0.3:
			_boxt(frag, Vector3((mn.x + t0) * 0.5, y_lo + band_h * 0.5, c.y),
				Vector3(t0 - mn.x, band_h, sz.y), col.darkened(0.03), facade_tile, stats)
		var t1 := slot_c + slot_half
		if mx.x - t1 > 0.3:
			_boxt(frag, Vector3((t1 + mx.x) * 0.5, y_lo + band_h * 0.5, c.y),
				Vector3(mx.x - t1, band_h, sz.y), col.darkened(0.03), facade_tile, stats)
		for mz_s: float in [mn.y, mx.y]:
			for jx: float in [slot_c - slot_half + 0.12, slot_c + slot_half - 0.12]:
				_box(frag, Vector3(jx, y_lo + band_h * 0.5, mz_s), Vector3(0.24, band_h, 0.24),
					col.darkened(0.3), stats)
			_box(frag, Vector3(slot_c, y_hi + 0.14, mz_s), Vector3(slot_half * 2.0, 0.28, 0.28),
				col.darkened(0.3), stats)
			_box_glow(frag, Vector3(slot_c, y_hi + 0.03, mz_s), Vector3(slot_half * 1.6, 0.05, 0.1),
				Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.2, stats)
	# upper-mass window band (the building lives above the road)
	var wsz := Vector3(sz.x * 0.7, 0.28, 0.05) if axis == 1 else Vector3(0.05, 0.28, sz.y * 0.7)
	var wpos := Vector3(c.x, y_hi + 1.3, mn.y - 0.03) if axis == 1 else Vector3(mn.x - 0.03, y_hi + 1.3, c.y)
	_box_glow(frag, wpos, wsz, Color(0.05, 0.06, 0.08),
		GLOW_WARM if _rf(jitter) < warm_bias else GLOW_GREEN, 0.9, stats)

## The gangway-crawl DATA for one roof dock: mouth on the deck beside the gangway, then the
## authored path — roof landing, inside the building, out the street door at ground level.
static func _dock_gang_spec(dp: Dictionary, origin: Vector3, cs: float, deck_y: float) -> Dictionary:
	var plan: Dictionary = dp["plan"]
	var axis := int(plan["axis"])
	var lane := int(plan["lane"])
	var side := int(dp["side"])
	var mn: Vector2 = dp["mn"]
	var mx: Vector2 = dp["mx"]
	var roof := float(dp["roof"])
	var street: Vector2i = dp.get("street", Vector2i(0, 1))
	var lane_c := (origin.z if axis == 0 else origin.x) + (float(lane) + 0.5) * cs
	var along_c := (mn.x + mx.x) * 0.5 if axis == 0 else (mn.y + mx.y) * 0.5
	var lot_edge := (mn.y if side < 0 else mx.y) if axis == 0 else (mn.x if side < 0 else mx.x)
	var mouth := Vector3(along_c, deck_y, lane_c) if axis == 0 else Vector3(lane_c, deck_y, along_c)
	var pad_c := lot_edge - float(side) * 0.8
	var pad := Vector3(along_c, roof + 0.25, pad_c) if axis == 0 else Vector3(pad_c, roof + 0.25, along_c)
	var g_c := Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5)
	var inside := Vector3(g_c.x, 1.0, g_c.y)
	var g_sz := Vector2(mx.x - mn.x, mx.y - mn.y)
	var door := Vector3(g_c.x + float(street.x) * (g_sz.x * 0.5 + 0.6), 0.25,
		g_c.y + float(street.y) * (g_sz.y * 0.5 + 0.6))
	return {"name": "DockGangway_%d_%d" % [dp["cell"].x, dp["cell"].y], "mouth": mouth,
		"waypoints": [pad, inside, door]}

## The climbable LADDER at a deck link cell: twin rails + rungs up the deck edge, a green marker
## at the top. Road furniture (emitted in the viaduct phase); the grid link at this cell is the
## real traversal — this is its visual promise.
static func _emit_deck_ladder(frag: Fragment, stand: Vector2i, link_c: Vector2i, origin: Vector3,
		cs: float, deck_y: float, stats: Dictionary) -> void:
	# the ladder stands on the kerb cell, leaning toward the link cell's deck edge — the street
	# column itself stays clear (the grid link at the crossing is the real transition)
	var sc := Vector3(origin.x + (float(stand.x) + 0.5) * cs, 0.0, origin.z + (float(stand.y) + 0.5) * cs)
	var lc3 := Vector3(origin.x + (float(link_c.x) + 0.5) * cs, 0.0, origin.z + (float(link_c.y) + 0.5) * cs)
	var toward := (lc3 - sc).normalized()
	var base := sc + toward * 0.1
	var across := Vector3(-toward.z, 0.0, toward.x)
	var lad_h := deck_y + 0.65
	var rail_col := Color(0.12, 0.14, 0.16)
	for s_off: float in [-0.2, 0.2]:
		var rp := base + across * s_off
		_box(frag, Vector3(rp.x, lad_h * 0.5, rp.z), Vector3(0.06, lad_h, 0.06), rail_col, stats)
	var rungs := int(deck_y / 0.75)
	for r in range(1, rungs + 1):
		_box(frag, Vector3(base.x, float(r) * 0.75, base.z),
			Vector3(absf(across.x) * 0.42 + 0.05, 0.06, absf(across.z) * 0.42 + 0.05),
			rail_col.lightened(0.1), stats)
	_box_glow(frag, Vector3(base.x, deck_y + 0.9, base.z), Vector3(0.12, 0.2, 0.12),
		Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.2, stats)

## THE ROOF DOCK: a stepped gangway (the faceted-curve idiom) dropping from the viaduct deck to an
## adjacent building's roof — the building plugs into the side rail. Emitted with the viaduct so
## its boxes are road-owned; the landing pad and hatch glow sit on the roof it serves.
static func _emit_rail_dock(frag: Fragment, dp: Dictionary, origin: Vector3, cs: float,
		deck_top: float, stats: Dictionary) -> void:
	var plan: Dictionary = dp["plan"]
	var axis := int(plan["axis"])
	var lane := int(plan["lane"])
	var side := int(dp["side"])    # which side of the lot the lane runs on
	var mn: Vector2 = dp["mn"]
	var mx: Vector2 = dp["mx"]
	var roof := float(dp["roof"])
	var lane_c := (origin.z if axis == 0 else origin.x) + (float(lane) + 0.5) * cs
	var deck_edge := lane_c - float(side) * DECK_W * 0.5
	var along_c := (mn.x + mx.x) * 0.5 if axis == 0 else (mn.y + mx.y) * 0.5
	var lot_edge := (mn.y if side < 0 else mx.y) if axis == 0 else (mn.x if side < 0 else mx.x)
	# three stepped treads from deck height down to the roof, spanning deck edge -> lot edge
	var gap := absf(lot_edge - deck_edge)
	var step_len := maxf(gap / 3.0, 0.4)
	for st in range(3):
		var t := (float(st) + 0.5) / 3.0
		var sy := lerpf(deck_top + 0.02, roof + 0.12, t)
		var s_c := lerpf(deck_edge, lot_edge, t) + float(side) * 0.0
		var tread_pos := Vector3(along_c, sy, s_c) if axis == 0 else Vector3(s_c, sy, along_c)
		var tread_sz := Vector3(1.0, 0.1, step_len + 0.15) if axis == 0 else Vector3(step_len + 0.15, 0.1, 1.0)
		_boxt(frag, tread_pos, tread_sz, Color(0.13, 0.15, 0.17), "grate", stats)
	# roof landing pad + the hatch marker
	var pad_c := lot_edge - float(side) * 0.8
	var pad_pos := Vector3(along_c, roof + 0.07, pad_c) if axis == 0 else Vector3(pad_c, roof + 0.07, along_c)
	_boxt(frag, pad_pos, Vector3(1.3, 0.12, 1.3), Color(0.12, 0.14, 0.16), "grate", stats)
	_box_glow(frag, pad_pos + Vector3(0, 0.1, 0), Vector3(0.5, 0.06, 0.5),
		Color(0.05, 0.08, 0.06), GLOW_GREEN, 1.1, stats)

## Weighted program draw for one box lot. Idiom sets the base weights; the fields nudge them
## (decay -> industrial programs, cool/tended palette -> office, glow -> retail), and a one-storey
## lot cannot be a stacked mixed block. Rides the lot's own `jitter` stream -> deterministic.
static func _pick_program(idiom: String, decay: float, warm_bias: float, glow_density: float,
		floors: int, jitter: SeededRng) -> String:
	var base: Dictionary = IDIOM_WEIGHTS.get(idiom, IDIOM_WEIGHTS["mixed"])
	var w := {}
	for prog in PROGRAMS:
		w[prog] = float(base.get(prog, 0))
	# field nudges (multiplicative, gentle — the idiom still dominates)
	w["warehouse"] *= 1.0 + decay * 1.2
	w["fabrication"] *= 1.0 + decay * 0.8
	w["office"] *= 1.0 + (1.0 - decay) * (1.0 - warm_bias) * 1.3
	w["retail"] *= 1.0 + glow_density * 1.0
	w["crossdock"] *= 1.0 + decay * 0.4
	if floors < 2:
		w["mixed"] = 0.0        # a stacked retail/office/residential block needs the height
		w["office"] *= 0.5
	var total := 0.0
	for prog in PROGRAMS:
		total += float(w[prog])
	if total <= 0.0:
		return "generic"
	var r := _rf(jitter) * total
	for prog in PROGRAMS:
		r -= float(w[prog])
		if r <= 0.0:
			return prog
	return "generic"

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

const DECK_TOP := 8.0        # deck surface = grid LEVEL 2 (level_height 4.0) so the line is WALKABLE;
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
