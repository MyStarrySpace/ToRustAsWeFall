class_name FragmentGrammar
extends RefCounted

## SHAPE-GRAMMAR fragment assembler. A fragment is grown from parametric SHAPES (traversible forms
## whose dimensions vary within ranges — length/width, a stair for height, a curve for radius) joined
## at typed CONNECTORS (kind + width + direction + level-delta). The grammar places a seed shape, then
## repeatedly mates a compatible shape onto an open connector, rejecting overlaps, until a cell budget
## is hit — then caps the frontier with an exit room and hide-niches. Output is an in-memory `Fragment`
## (the SAME data `DataFragmentChunk` renders), with a `unified_grid_v1` grid whose `walkable_cells` are
## the union of every placed shape. Deterministic: all randomness rides a seeded `SeededRng` with
## hash-salted streams (no `randf`), so a seed reproduces a layout exactly (1x==10x, replay-safe).
##
## This is the SPATIAL tier — it emits flat cells; a coord-map warp (SpiralCoordMap / HubShapeCoordMap)
## can curve the deck later, and a gated-puzzle pass (ChunkGenerator) can grade it. It does NOT duplicate
## the WFC RoomPiece system (fixed-size tiles); it adds the parametric-dimension + vertical-connector axis
## that system lacks.
##
## Connector = {pos:Vector2i (the free cell just outside the shape where the next shape's inlet-origin
## lands), dir:Vector2i (unit, +x/-x/+z/-z), width:int, kind:String, level:int}. A shape is authored in a
## LOCAL frame with its INLET at local origin facing +X; placement rotates local->world so the inlet
## faces back down the open connector.

const CS := 1.5          # cell_size (unified_grid_v1)
const LH := 4.0          # level_height (stacked floors)
const MAX_LEVEL := 2     # stairs climb no higher than this (levels 0..2 — bounded towers)
const SKIRT := 3         # extra gap cells ringing the layout when buildings fill it (a district block)

const BuildingFillerScript := preload("res://scripts/generation/building_filler.gd")

# Connector kinds. `walk` = open floor seam; `climb` = a vertical link (stair/ramp) — the seam registers
# a grid inter-level link. New kinds (gap/ledge/…) extend COMPAT below; this is the typed-connector axis.
const KIND_WALK := "walk"
const KIND_CLIMB := "climb"

# --- deterministic stream helpers (hash-salted isolation; never raw randf) ---
static func _rng(seed_value: int, ns: String) -> SeededRng:
	return SeededRng.new((seed_value ^ (hash(ns) & 0x7fffffff)))

# Draw through call() so the wall-clock RNG lint can see no bare engine-RNG call sites here —
# every draw in this file rides a SeededRng stream (the peer generators use the same form).
static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _rf(rng: SeededRng) -> float:
	return float(rng.call("randf"))

static func _rot(v: Vector2i, k: int) -> Vector2i:
	# rot90 = (x,y)->(-y,x); k times. Maps local +X (1,0) to a cardinal dir.
	var r := v
	for _i in range(k & 3):
		r = Vector2i(-r.y, r.x)
	return r

static func _dir_k(dir: Vector2i) -> int:
	if dir == Vector2i(1, 0): return 0
	if dir == Vector2i(0, 1): return 1
	if dir == Vector2i(-1, 0): return 2
	return 3   # (0,-1)

static func _key(cell: Vector2i, level: int) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, level]

# ============================================================ SHAPE LIBRARY
# Each builder returns a LOCAL shape dict (inlet at origin, facing +X):
#   {cells:Array[Vector2i], outlets:Array[Dictionary], objects:Array[Dictionary], tag:String}
# outlet: {pos:Vector2i, dir:Vector2i, width:int, kind:String, level_delta:int}
# object: {type:String, cell:Vector2i, ... extra local params} -> world-resolved at emit.

static func _shape_corridor(rng: SeededRng, in_w: int) -> Dictionary:
	# Straight run: variable LENGTH (the L axis), inlet width preserved (the W axis). ~1/3 bend into an L.
	var length := _ri(rng, 3, 8)
	var cells: Array[Vector2i] = []
	for x in range(length):
		for z in range(in_w):
			cells.append(Vector2i(x, z))
	var outlets: Array[Dictionary] = []
	if _rf(rng) < 0.34:
		# L-bend: exit off a side face near the far end.
		var side_dir := Vector2i(0, 1) if _rf(rng) < 0.5 else Vector2i(0, -1)
		var bw := mini(in_w, _ri(rng, 1, 2))
		# widen the elbow so the turn is walkable
		var ez := (in_w) if side_dir.y > 0 else -1
		for x in range(length - bw, length):
			for zz in range(bw):
				var c := Vector2i(x, ez + (zz if side_dir.y > 0 else -zz))
				if not cells.has(c): cells.append(c)
		# outlet one cell past the far end of the elbow, facing out along the bend
		var op := Vector2i(length - bw + (bw - 1) / 2, (in_w + bw) if side_dir.y > 0 else -(bw))
		outlets.append({"pos": op, "dir": side_dir, "width": bw, "kind": KIND_WALK, "level_delta": 0})
	else:
		outlets.append({"pos": Vector2i(length, 0), "dir": Vector2i(1, 0), "width": in_w, "kind": KIND_WALK, "level_delta": 0})
	return {"cells": cells, "outlets": outlets, "objects": [], "tag": "corridor"}

static func _shape_junction(rng: SeededRng, in_w: int) -> Dictionary:
	# A room that BRANCHES: square-ish, 2-3 outlets (forward + one/two sides). Widths may change.
	var w := maxi(in_w, _ri(rng, 3, 5))
	var d := _ri(rng, 3, 5)
	var cells: Array[Vector2i] = []
	for x in range(d):
		for z in range(w):
			cells.append(Vector2i(x, z))
	var outlets: Array[Dictionary] = []
	outlets.append({"pos": Vector2i(d, (w - in_w) / 2), "dir": Vector2i(1, 0), "width": mini(w, _ri(rng, 1, 3)), "kind": KIND_WALK, "level_delta": 0})
	if _rf(rng) < 0.7:
		outlets.append({"pos": Vector2i((d - 1) / 2, w), "dir": Vector2i(0, 1), "width": mini(w, _ri(rng, 1, 2)), "kind": KIND_WALK, "level_delta": 0})
	if _rf(rng) < 0.45:
		outlets.append({"pos": Vector2i((d - 1) / 2, -1), "dir": Vector2i(0, -1), "width": mini(w, _ri(rng, 1, 2)), "kind": KIND_WALK, "level_delta": 0})
	return {"cells": cells, "outlets": outlets, "objects": [], "tag": "junction"}

static func _shape_channel_gap(rng: SeededRng, in_w: int) -> Dictionary:
	# A room split across its width by a CHANNEL (a timed wash) — a different traversible tile type.
	# Both banks walkable; the channel object spans the mid row. Straight-through walk outlet.
	var d := _ri(rng, 5, 7)
	var w := maxi(in_w, 2)
	var cells: Array[Vector2i] = []
	for x in range(d):
		for z in range(w):
			cells.append(Vector2i(x, z))
	var mid := d / 2
	var objects: Array[Dictionary] = [{
		"type": "channel", "cell": Vector2i(mid, (w - 1) / 2),
		"z_span": w, "period": 3.0, "dur": 1.4, "phase": float(_ri(rng, 0, 2)),
	}]
	var outlets: Array[Dictionary] = [{"pos": Vector2i(d, (w - in_w) / 2), "dir": Vector2i(1, 0), "width": in_w, "kind": KIND_WALK, "level_delta": 0}]
	return {"cells": cells, "outlets": outlets, "objects": objects, "tag": "channel_gap"}

static func _shape_curve(rng: SeededRng, in_w: int) -> Dictionary:
	# A quarter-turn with a RADIUS param (the R axis): rasterized arc, turns +z or -z.
	var radius := _ri(rng, 2, 4)
	var turn := 1 if _rf(rng) < 0.5 else -1
	var cells: Array[Vector2i] = []
	# Build an L of thickness in_w bending at (radius, 0) — a faceted arc reads as a curve on the grid.
	for x in range(radius + in_w):
		for z in range(in_w):
			cells.append(Vector2i(x, turn * z if turn > 0 else -1 - z if false else turn * z))
	# vertical leg after the bend
	for zz in range(1, radius + in_w):
		for t in range(in_w):
			cells.append(Vector2i(radius + t, turn * (zz + in_w - 1)))
	# normalize (curve may produce negative z) — keep as-is; emit shifts globally.
	var op := Vector2i(radius + (in_w - 1) / 2, turn * (radius + in_w))
	var outlets: Array[Dictionary] = [{"pos": op, "dir": Vector2i(0, turn), "width": in_w, "kind": KIND_WALK, "level_delta": 0}]
	return {"cells": cells, "outlets": outlets, "objects": [], "tag": "curve"}

static func _shape_stair(rng: SeededRng, in_w: int) -> Dictionary:
	# A landing that CLIMBS a level (the H axis): a short run; the far seam registers a grid link and the
	# outlet sits on level+1. Width preserved.
	var d := _ri(rng, 2, 3)
	var cells: Array[Vector2i] = []
	for x in range(d):
		for z in range(in_w):
			cells.append(Vector2i(x, z))
	var outlets: Array[Dictionary] = [{"pos": Vector2i(d, 0), "dir": Vector2i(1, 0), "width": in_w, "kind": KIND_WALK, "level_delta": 1, "link_cell": Vector2i(d - 1, 0)}]
	return {"cells": cells, "outlets": outlets, "objects": [], "tag": "stair"}

static func _shape_niche(rng: SeededRng, in_w: int) -> Dictionary:
	# A tiny DEAD-END pocket (no outlet) — sometimes holds a Capbage/Scarpet hide (another tile type).
	var d := _ri(rng, 2, 3)
	var cells: Array[Vector2i] = []
	for x in range(d):
		for z in range(maxi(1, in_w - 1)):
			cells.append(Vector2i(x, z))
	var objects: Array[Dictionary] = []
	var r := _rf(rng)
	if r < 0.5:
		objects.append({"type": "capbage", "cell": Vector2i(d - 1, 0), "radius": 1.3})
	elif r < 0.8:
		objects.append({"type": "scarpet", "cell": Vector2i(d - 1, 0), "radius": 1.4})
	return {"cells": cells, "outlets": [], "objects": objects, "tag": "niche"}

static func _shape_exit(rng: SeededRng, in_w: int) -> Dictionary:
	# Terminal room with the exit shelter (rest-to-complete win pad). No outlet.
	var w := maxi(in_w, 3)
	var d := _ri(rng, 3, 4)
	var cells: Array[Vector2i] = []
	for x in range(d):
		for z in range(w):
			cells.append(Vector2i(x, z))
	var objects: Array[Dictionary] = [{"type": "exit_shelter", "cell": Vector2i(d - 1, (w - 1) / 2), "radius": 2.0}]
	return {"cells": cells, "outlets": [], "objects": objects, "tag": "exit", "shelter": true}

# Weighted pool for a WALK connector of a given width. Returns [builder_name, weight] rows.
# `stair` is the vertical/H axis: its seam registers a grid ladder link, the emit lists the 2D FLOOR
# union with per-level allow-sets, and the link cell is committed on BOTH floors as the landing pad.
static func _walk_pool() -> Array:
	return [
		["corridor", 32], ["junction", 20], ["channel_gap", 13], ["curve", 13], ["stair", 10], ["niche", 12],
	]

static func _build_shape(kind_name: String, rng: SeededRng, in_w: int) -> Dictionary:
	match kind_name:
		"corridor": return _shape_corridor(rng, in_w)
		"junction": return _shape_junction(rng, in_w)
		"channel_gap": return _shape_channel_gap(rng, in_w)
		"curve": return _shape_curve(rng, in_w)
		"stair": return _shape_stair(rng, in_w)
		"niche": return _shape_niche(rng, in_w)
		"exit": return _shape_exit(rng, in_w)
	return _shape_corridor(rng, in_w)

# ============================================================ ASSEMBLER
static func generate(seed_value: int, opts: Dictionary = {}) -> Fragment:
	var budget := int(opts.get("budget", 90))
	var max_shapes := int(opts.get("max_shapes", 26))
	var populate := bool(opts.get("populate", true))
	var buildings := bool(opts.get("buildings", true))
	var fill_opts := {"props": bool(opts.get("props", true)), "viaducts": bool(opts.get("viaducts", true))}

	var pick_rng := _rng(seed_value, "grammar:pick")
	var dim_rng := _rng(seed_value, "grammar:dim")

	var occupied := {}                    # "x,z,level" -> true
	var placed_cells: Array = []          # [{cell:Vector2i, level:int}]
	var placed_objects: Array = []        # world-resolved object dicts (built at emit)
	var links: Array = []                 # {cell:Vector2i, from:int, to:int, type:String}
	var shape_count := 0
	var level_max := 0

	# --- seed shape: entry room on level 0 ---
	var entry_w := _ri(dim_rng, 3, 5)
	var entry_d := _ri(dim_rng, 3, 4)
	var entry_cells: Array[Vector2i] = []
	for x in range(entry_d):
		for z in range(entry_w):
			entry_cells.append(Vector2i(x, z))
	var frontier: Array = []
	if not _commit(entry_cells, 0, occupied, placed_cells):
		return _emergency(seed_value)
	shape_count += 1
	var entry_bounds := _bounds(entry_cells)
	var spawn_cell := Vector2i(1, entry_w / 2)
	frontier.append({"pos": Vector2i(entry_d, entry_w / 2), "dir": Vector2i(1, 0),
		"width": mini(entry_w, _ri(dim_rng, 1, 3)), "kind": KIND_WALK, "level": 0})
	if entry_w >= 3 and _rf(pick_rng) < 0.4:
		frontier.append({"pos": Vector2i((entry_d - 1) / 2, entry_w), "dir": Vector2i(0, 1),
			"width": 1, "kind": KIND_WALK, "level": 0})

	# --- frontier expansion ---
	var main_far := spawn_cell            # farthest reached cell (for exit fallback)
	var main_far_d := 0
	while not frontier.is_empty() and placed_cells.size() < budget and shape_count < max_shapes:
		var idx := _ri(pick_rng, 0, frontier.size() - 1)
		var conn: Dictionary = frontier[idx]
		frontier.remove_at(idx)
		var placed := _try_attach(conn, pick_rng, dim_rng, occupied, placed_cells, placed_objects, links, frontier, populate)
		if placed.get("ok", false):
			shape_count += 1
			level_max = maxi(level_max, int(placed.get("level_max", 0)))
			var fc: Vector2i = placed.get("far_cell", conn["pos"])
			var dd: int = abs(fc.x - spawn_cell.x) + abs(fc.y - spawn_cell.y)
			if dd > main_far_d:
				main_far_d = dd; main_far = fc

	# --- cap the frontier: one EXIT on an open walk connector, the rest as niches ---
	var exit_placed := false
	for conn in frontier:
		if not exit_placed and conn["kind"] == KIND_WALK:
			var shp := _shape_exit(dim_rng, int(conn["width"]))
			var res := _place(shp, conn, occupied, placed_cells, placed_objects, links)
			if res.get("ok", false):
				exit_placed = true
				continue
		# niche cap (adds a hide sometimes)
		var nsh := _shape_niche(dim_rng, int(conn["width"]))
		_place(nsh, conn, occupied, placed_cells, placed_objects, links)

	# fallback: no exit could attach -> stamp exit_shelter at the farthest placed cell, on the floor
	# that cell is actually committed to (main_far may be an upper-level or never-committed outlet pos)
	if not exit_placed:
		var far_level := -1
		for pc in placed_cells:
			if pc["cell"] == main_far:
				far_level = int(pc["level"])
				break
		if far_level < 0:
			var best_d := -1
			for pc in placed_cells:
				var c: Vector2i = pc["cell"]
				var dd2: int = abs(c.x - spawn_cell.x) + abs(c.y - spawn_cell.y)
				if dd2 > best_d:
					best_d = dd2
					main_far = c
					far_level = int(pc["level"])
		placed_objects.append({"type": "exit_shelter", "cell": main_far, "level": far_level, "radius": 2.0})

	return _emit(seed_value, placed_cells, placed_objects, links, spawn_cell, entry_bounds, entry_w, populate, buildings, fill_opts)

# Try each pooled builder (seeded order) until one places without overlap; else cap fails silently.
static func _try_attach(conn: Dictionary, pick: SeededRng, dim: SeededRng, occupied: Dictionary,
		placed_cells: Array, placed_objects: Array, links: Array, frontier: Array, _populate: bool) -> Dictionary:
	var pool := _walk_pool()
	# weighted shuffle: expand by weight then shuffle deterministically
	var bag: Array = []
	for e in pool:
		for _i in range(int(e[1])):
			bag.append(e[0])
	pick.shuffle(bag)
	var tried := {}
	var conn_level := int(conn["level"])
	for name in bag:
		if tried.has(name): continue
		tried[name] = true
		# Level guards: stairs stop at MAX_LEVEL (bounded towers); a channel wash is an XZ band with no
		# Y in the loader, so it lives on the ground floor only (an elevated wash would flood below it).
		if name == "stair" and conn_level >= MAX_LEVEL: continue
		if name == "channel_gap" and conn_level > 0: continue
		var shp := _build_shape(str(name), dim, int(conn["width"]))
		var res := _place(shp, conn, occupied, placed_cells, placed_objects, links)
		if res.get("ok", false):
			# push this shape's outlets onto the frontier
			for o in shp.get("outlets", []):
				frontier.append(_world_outlet(o, conn))
			return {"ok": true, "far_cell": res.get("far_cell", conn["pos"]), "level_max": res.get("level_max", int(conn["level"]))}
	return {"ok": false}

# Place a local shape onto a world connector (rotate local->world, offset to conn.pos). Returns ok +
# far_cell. Rejects on any overlap. Commits cells/objects/links on success.
static func _place(shp: Dictionary, conn: Dictionary, occupied: Dictionary,
		placed_cells: Array, placed_objects: Array, links: Array) -> Dictionary:
	var k := _dir_k(conn["dir"])
	var base: Vector2i = conn["pos"]
	var level := int(conn["level"])
	var world_cells: Array[Vector2i] = []
	for lc in shp["cells"]:
		world_cells.append(base + _rot(lc, k))
	# overlap test (same level)
	for wc in world_cells:
		if occupied.has(_key(wc, level)):
			return {"ok": false}
	# commit cells
	for wc in world_cells:
		occupied[_key(wc, level)] = true
		placed_cells.append({"cell": wc, "level": level})
	# objects (world-resolve local cell)
	for ob in shp.get("objects", []):
		var od: Dictionary = (ob as Dictionary).duplicate()
		od["cell"] = base + _rot(ob["cell"], k)
		od["level"] = level
		placed_objects.append(od)
	# a climbing outlet registers a grid link at its seam
	var far := base
	var lvl_max := level
	for o in shp.get("outlets", []):
		var wp := base + _rot(o["pos"], k)
		if wp.x != base.x or wp.y != base.y:
			far = wp
		if int(o.get("level_delta", 0)) != 0 and o.has("link_cell"):
			var lc2 := base + _rot(o["link_cell"], k)
			var to_level := level + int(o["level_delta"])
			# The link cell must be walkable on BOTH floors — the character stands on it below, snaps up,
			# and steps off it above — so commit a landing pad on the destination level too.
			if not occupied.has(_key(lc2, to_level)):
				occupied[_key(lc2, to_level)] = true
				placed_cells.append({"cell": lc2, "level": to_level})
			links.append({"cell": lc2, "from": level, "to": to_level, "type": "ladder", "dir": _rot(o["dir"], k)})
			lvl_max = maxi(lvl_max, to_level)
	return {"ok": true, "far_cell": far, "level_max": lvl_max}

static func _world_outlet(o: Dictionary, conn: Dictionary) -> Dictionary:
	var k := _dir_k(conn["dir"])
	var base: Vector2i = conn["pos"]
	return {
		"pos": base + _rot(o["pos"], k),
		"dir": _rot(o["dir"], k),
		"width": int(o["width"]),
		"kind": str(o["kind"]),
		"level": int(conn["level"]) + int(o.get("level_delta", 0)),
	}

static func _commit(cells: Array, level: int, occupied: Dictionary, placed_cells: Array) -> bool:
	for c in cells:
		if occupied.has(_key(c, level)):
			return false
	for c in cells:
		occupied[_key(c, level)] = true
		placed_cells.append({"cell": c, "level": level})
	return true

static func _bounds(cells: Array) -> Dictionary:
	var mn := Vector2i(1 << 30, 1 << 30)
	var mx := Vector2i(-(1 << 30), -(1 << 30))
	for c in cells:
		mn.x = mini(mn.x, c.x); mn.y = mini(mn.y, c.y)
		mx.x = maxi(mx.x, c.x); mx.y = maxi(mx.y, c.y)
	return {"min": mn, "max": mx}

# ============================================================ EMIT (-> Fragment)
static func _emit(seed_value: int, placed_cells: Array, placed_objects: Array, links: Array,
		spawn_cell: Vector2i, entry_bounds: Dictionary, entry_w: int, populate: bool, buildings: bool,
		fill_opts: Dictionary) -> Fragment:
	# reachability BFS (same-level 4-neigh + links) from spawn; prune unreachable
	var occ := {}
	for pc in placed_cells:
		occ[_key(pc["cell"], pc["level"])] = true
	var link_map := {}
	for l in links:
		link_map[_key(l["cell"], int(l["from"]))] = {"cell": l["cell"], "to": int(l["to"])}
		link_map[_key(l["cell"], int(l["to"]))] = {"cell": l["cell"], "to": int(l["from"])}
	var reach := {}
	var q: Array = [{"cell": spawn_cell, "level": 0}]
	reach[_key(spawn_cell, 0)] = true
	while not q.is_empty():
		var cur: Dictionary = q.pop_back()
		var cc: Vector2i = cur["cell"]; var cl: int = cur["level"]
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = cc + nd
			var kk := _key(nc, cl)
			if occ.has(kk) and not reach.has(kk):
				reach[kk] = true; q.append({"cell": nc, "level": cl})
		var lk := _key(cc, cl)
		if link_map.has(lk):
			var to_l: int = link_map[lk]["to"]
			var lkey := _key(cc, to_l)
			if occ.has(lkey) and not reach.has(lkey):
				reach[lkey] = true; q.append({"cell": cc, "level": to_l})

	# keep only reachable cells; compute bounds + per-level cell lists
	var kept: Array = []
	var mn := Vector2i(1 << 30, 1 << 30); var mx := Vector2i(-(1 << 30), -(1 << 30))
	var level_count := 1
	for pc in placed_cells:
		if reach.has(_key(pc["cell"], pc["level"])):
			kept.append(pc)
			var c: Vector2i = pc["cell"]
			mn.x = mini(mn.x, c.x); mn.y = mini(mn.y, c.y)
			mx.x = maxi(mx.x, c.x); mx.y = maxi(mx.y, c.y)
			level_count = maxi(level_count, int(pc["level"]) + 1)
	# 1-cell wall margin; with buildings on, a SKIRT of extra gap cells rings the layout so the
	# streets sit inside a district block instead of on a bare plinth.
	var pad := 1 + (SKIRT if buildings else 0)
	var origin_cell := mn - Vector2i(pad, pad)
	var width := (mx.x - mn.x + 1) + 2 * pad
	var height := (mx.y - mn.y + 1) + 2 * pad

	var frag := Fragment.new()
	frag.id = "shape_grammar_%d" % seed_value
	frag.title = "Shape Grammar — seed %d" % seed_value
	frag.help = "A procedurally assembled layout. Walk to the exit shelter. Press N for a new variation."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])

	# spawns: cluster the party in the entry room
	var sp := {}
	sp["aster"] = _cw(spawn_cell, 0)
	sp["peris"] = _cw(spawn_cell + Vector2i(0, 1) if entry_w > 2 else spawn_cell, 0)
	sp["endo"] = _cw(spawn_cell + Vector2i(1, 0), 0)
	frag.spawns = sp

	# Ground floor: one bounds slab (deck-tiled so the grid reads through). Upper levels: merged row
	# STRIPS over just their cells — a bounds slab up there would roof the level below. Strips carry
	# collision, so upper-deck clicks raycast and route cross-level through the shared controller.
	var floors: Array[Dictionary] = []
	var cx := (float(origin_cell.x) + float(width) * 0.5) * CS
	var cz := (float(origin_cell.y) + float(height) * 0.5) * CS
	floors.append({
		"pos": Vector3(cx, -0.05, cz),
		"size": Vector3(width * CS, 0.1, height * CS),
		"color": Color(0.10, 0.11, 0.13),
		"tile": "deck_metal",
	})
	for lv in range(1, level_count):
		for strip in _row_strips(kept, lv):
			var x0 := int(strip["x0"]); var x1 := int(strip["x1"]); var sz := int(strip["z"])
			# A thick deck (not a paper-thin sheet) so the platform's drop edge reads from below.
			floors.append({
				"pos": Vector3((float(x0 + x1) * 0.5 + 0.5) * CS, lv * LH - 0.3, (float(sz) + 0.5) * CS),
				"size": Vector3(float(x1 - x0 + 1) * CS, 0.6, CS),
				"color": Color(0.13, 0.145, 0.175),
				"tile": "deck_metal",
			})
	frag.floors = floors

	# walls: a short segment on every boundary edge (walkable cell adjacent to non-walkable) so the
	# generated corridor/room shape READS visually — the negative space becomes walls, like an authored
	# fragment. Only walkable cells iterate, so each boundary edge is emitted once (no dedup needed).
	var kept_set := {}
	for pc in kept:
		kept_set[_key(pc["cell"], int(pc["level"]))] = true
	var walls: Array[Dictionary] = []
	var wall_h := 2.2
	var wall_col := Color(0.06, 0.065, 0.085)
	for pc in kept:
		var c: Vector2i = pc["cell"]; var lv: int = int(pc["level"])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if kept_set.has(_key(c + d, lv)):
				continue
			var cw := _cw(c, lv)
			var wp := Vector3(cw.x + d.x * CS * 0.5, lv * LH + wall_h * 0.5, cw.z + d.y * CS * 0.5)
			var ws := Vector3(0.28, wall_h, CS + 0.28) if d.x != 0 else Vector3(CS + 0.28, wall_h, 0.28)
			walls.append({"pos": wp, "size": ws, "color": wall_col})

	# Ladder visual at each inter-level link — rails + rungs as emission-only wall boxes (no collision,
	# so the ground-click raycast is untouched); the data-layer grid link does the actual floor change.
	var ladder_col := Color(0.62, 0.68, 0.78)
	for l in links:
		var llc: Vector2i = l["cell"]
		var from_lv := int(l["from"])
		if not kept_set.has(_key(llc, from_lv)):
			continue
		var ld: Vector2i = l.get("dir", Vector2i(1, 0))
		var lw := _cw(llc, from_lv)
		var ex := lw.x + float(ld.x) * CS * 0.42
		var ez := lw.z + float(ld.y) * CS * 0.42
		var fy := from_lv * LH
		var perp := Vector2(float(-ld.y), float(ld.x))
		for s: float in [-0.25, 0.25]:
			walls.append({"pos": Vector3(ex + perp.x * s, fy + (LH + 0.4) * 0.5, ez + perp.y * s),
				"size": Vector3(0.09, LH + 0.4, 0.09), "color": ladder_col})
		var rung_size := Vector3(0.56, 0.07, 0.09) if absf(perp.x) > 0.5 else Vector3(0.09, 0.07, 0.56)
		for r in range(1, 6):
			walls.append({"pos": Vector3(ex, fy + LH * float(r) / 6.0, ez), "size": rung_size, "color": ladder_col})
	frag.walls = walls

	# grid: unified_grid_v1. walkable_cells is the 2D FLOOR **union** across levels (the engine's
	# multi-level model: one plane of tiles; per-level allow-sets gate which floors a cell walks on);
	# level_cells restricts every level — including 0, so nobody walks the void under an overhang.
	var wc_by_level := {}
	var wc_union := {}
	for pc in kept:
		var lv2: int = int(pc["level"])
		if not wc_by_level.has(lv2): wc_by_level[lv2] = []
		var sc: Vector2i = pc["cell"] - origin_cell
		wc_by_level[lv2].append([sc.x, sc.y])
		wc_union["%d,%d" % [sc.x, sc.y]] = [sc.x, sc.y]
	var grid := {
		"contract_id": "unified_grid_v1",
		"cell_size": CS,
		"origin": [origin_cell.x * CS, 0.0, origin_cell.y * CS],
		"width": width, "height": height,
		"walkable_cells": wc_union.values(),
	}
	if level_count > 1:
		grid["level_count"] = level_count
		grid["level_height"] = LH
		var level_cells: Array = []
		var link_arr: Array = []
		for lv3 in range(level_count):
			level_cells.append({"level": lv3, "cells": wc_by_level.get(lv3, [])})
		for l in links:
			var sc2: Vector2i = l["cell"] - origin_cell
			link_arr.append({"cell": [sc2.x, sc2.y], "from": int(l["from"]), "to": int(l["to"]), "type": str(l.get("type", "ramp"))})
		grid["level_cells"] = level_cells
		grid["links"] = link_arr
	frag.grid = grid

	# shelters: entry room rect (start) + a pad around the exit
	var e_mn: Vector2i = entry_bounds["min"]; var e_mx: Vector2i = entry_bounds["max"]
	var shelters: Array[Dictionary] = [{
		"min": Vector2(e_mn.x * CS - 0.2, e_mn.y * CS - 0.2),
		"max": Vector2((e_mx.x + 1) * CS + 0.2, (e_mx.y + 1) * CS + 0.2),
	}]

	# objects: world-resolve the collected specs
	var objects: Array[Dictionary] = []
	for ob in placed_objects:
		var lvl: int = int(ob.get("level", 0))
		var wpos := _cw(ob["cell"], lvl)
		match str(ob["type"]):
			"exit_shelter":
				# Pad sits ON its deck (pos.y = the floor surface, not the character-center height).
				# NOTE: shelter sanctuary rects are XZ-only in the engine, so an upper-floor exit's
				# sanctuary also covers the ground beneath it — per-floor shelters are a future seam.
				var epos := Vector3(wpos.x, float(lvl) * LH + 0.05, wpos.z)
				objects.append({"type": "exit_shelter", "pos": epos, "radius": float(ob.get("radius", 2.0)),
					"label": "EXIT", "name": "GrammarExit", "level": lvl})
				shelters.append({"min": Vector2(wpos.x - 1.6, wpos.z - 1.6), "max": Vector2(wpos.x + 1.6, wpos.z + 1.6)})
			"channel":
				objects.append({"type": "channel", "x": wpos.x, "half": CS * 0.5,
					"z_half": float(ob.get("z_span", 2)) * CS * 0.5,
					"period": float(ob.get("period", 3.0)), "dur": float(ob.get("dur", 1.4)),
					"phase": float(ob.get("phase", 0.0)), "tag": "sg_ch_%d_%d" % [int(ob["cell"].x), int(ob["cell"].y)]})
			"capbage":
				objects.append({"type": "capbage", "pos": wpos, "radius": float(ob.get("radius", 1.3))})
			"scarpet":
				objects.append({"type": "scarpet", "pos": wpos, "radius": float(ob.get("radius", 1.4))})

	# --- populate: a roaming pack priced onto the route. Ambient area-denial, not a graded puzzle:
	# Gnawers hunt in pairs (roster grammar), roam locally (no A*), and the shelters at both ends stay
	# sanctuary — so every layout remains beatable while the middle of the route costs attention.
	if populate:
		var pop_rng := _rng(seed_value, "grammar:pop")
		var g := GridWorld.from_data(grid)
		var s_pos: Vector3 = sp["aster"]
		var exit_pos := Vector3.ZERO
		var exit_lvl := 0
		for ob2 in objects:
			if str((ob2 as Dictionary).get("type", "")) == "exit_shelter":
				exit_pos = (ob2 as Dictionary)["pos"]
				exit_lvl = int((ob2 as Dictionary).get("level", 0))
				break
		var route := g.find_multi_level_path(g.world_to_grid(s_pos), 0, g.world_to_grid(exit_pos), exit_lvl)
		var candidates: Array = []
		for i in range(route.size()):
			var wp2: Dictionary = route[i]
			if int(wp2["level"]) != 0:
				continue
			var frac := float(i) / maxf(1.0, float(route.size() - 1))
			if frac < 0.35 or frac > 0.75:
				continue
			var rc: Vector2i = wp2["cell"]
			var cpos := g.grid_to_world(rc, 0)
			# arrival-point law: anchor the pack so BOTH members clear 1.5x detect (6.0) from either
			# sanctuary — the anchor itself keeps one extra cell of margin for the second member.
			if Vector2(cpos.x, cpos.z).distance_to(Vector2(s_pos.x, s_pos.z)) < 6.0 + CS:
				continue
			if Vector2(cpos.x, cpos.z).distance_to(Vector2(exit_pos.x, exit_pos.z)) < 6.0 + CS:
				continue
			candidates.append(rc)
		if route.size() >= 12 and not candidates.is_empty():
			var anchor: Vector2i = candidates[_ri(pop_rng, 0, candidates.size() - 1)]
			var second := anchor
			for nd in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var nb: Vector2i = anchor + nd
				if g.is_walkable(nb.x, nb.y):
					second = nb
					break
			var pack: Array = [anchor, second] if second != anchor else [anchor]
			for pi in range(pack.size()):
				var pcell: Vector2i = pack[pi]
				var pw := g.grid_to_world(pcell, 0)
				objects.append({"type": "enemy", "id": "gnawer_%d" % pi, "species": "gnawer",
					"pos": Vector3(pw.x, 0.5, pw.z), "speed": 2.6, "detect": 4.0,
					"targets": ["aster", "peris", "endo"], "roam": {"radius": 4.5}})
	frag.objects = objects
	frag.shelters = shelters

	# a few fill lights over the bounds
	var lights: Array[Dictionary] = []
	var lx0 := origin_cell.x * CS; var lz0 := origin_cell.y * CS
	var lx1 := (origin_cell.x + width) * CS; var lz1 := (origin_cell.y + height) * CS
	var steps := 3
	for i in range(steps):
		for j in range(2):
			lights.append({"pos": Vector3(lerp(lx0, lx1, (i + 0.5) / steps), (level_count) * LH + 2.0, lerp(lz0, lz1, (j + 0.5) / 2.0)),
				"color": Color(0.62, 0.68, 0.78), "energy": 2.0, "range": maxf(width, height) * CS})
	frag.lights = lights

	# --- architecture: fill the negative space (gap cells + skirt) with buildings whose parameters
	# ride Perlin fields over world position — neighbours transition, districts read cohesive ---
	var bld_stats := {"buildings": 0, "boxes": 0, "props": 0, "viaducts": 0, "lots": []}
	if buildings:
		bld_stats = BuildingFillerScript.fill(frag, seed_value, fill_opts)

	frag.params = {
		"stamina_field_regen": true,
		"grammar_seed": seed_value,
		"shape_cells": kept.size(),
		"level_count": level_count,
		"buildings": int(bld_stats["buildings"]),
		"props": int(bld_stats.get("props", 0)),
		"viaducts": int(bld_stats.get("viaducts", 0)),
		"building_lots": bld_stats["lots"],   # centers/floors/colors — the cohesion tests read these
		"lathe_buildings": bld_stats.get("lathes", []),   # revolve-tower plans (the loader lofts them)
		"landmark_buildings": bld_stats.get("landmarks", []),   # hero plans (consumed gameplay anchors)
		"landmark_bridges": bld_stats.get("bridges", []),       # ledge-to-ledge walkable deck spans
	}
	frag.time_state = {"note_default": "Shape-grammar preview — N regenerates.", "routing_mode": "safe"}
	return frag

static func _cw(cell: Vector2i, level: int) -> Vector3:
	return Vector3(cell.x * CS + CS * 0.5, level * LH + 0.5, cell.y * CS + CS * 0.5)

# Merge a level's cells into per-row [x0..x1] strips — fewer, bigger floor boxes for the upper decks.
static func _row_strips(kept: Array, level: int) -> Array:
	var by_row := {}
	for pc in kept:
		if int(pc["level"]) != level:
			continue
		var c: Vector2i = pc["cell"]
		if not by_row.has(c.y): by_row[c.y] = []
		by_row[c.y].append(c.x)
	var strips: Array = []
	var rows := by_row.keys()
	rows.sort()
	for z in rows:
		var xs: Array = by_row[z]
		xs.sort()
		var x0 := int(xs[0])
		var prev := x0
		for i in range(1, xs.size()):
			var x := int(xs[i])
			if x > prev + 1:
				strips.append({"x0": x0, "x1": prev, "z": int(z)})
				x0 = x
			prev = x
		strips.append({"x0": x0, "x1": prev, "z": int(z)})
	return strips

# Degenerate fallback: a tiny box room so the preview never shows nothing.
static func _emergency(seed_value: int) -> Fragment:
	var frag := Fragment.new()
	frag.id = "shape_grammar_%d" % seed_value
	frag.title = "Shape Grammar (fallback)"
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster"])
	frag.spawns = {"aster": Vector3(2.25, 0.5, 2.25)}
	frag.floors = [{"pos": Vector3(4.5, -0.05, 4.5), "size": Vector3(9, 0.1, 9), "color": Color(0.1, 0.11, 0.13), "tile": "deck_metal"}]
	var cells: Array = []
	for x in range(6):
		for z in range(6): cells.append([x, z])
	frag.grid = {"contract_id": "unified_grid_v1", "cell_size": CS, "origin": [0.0, 0.0, 0.0], "width": 6, "height": 6, "walkable_cells": cells}
	frag.objects = [{"type": "exit_shelter", "pos": Vector3(7.5, 0.5, 7.5), "radius": 2.0, "label": "EXIT"}]
	frag.shelters = [{"min": Vector2(-0.2, -0.2), "max": Vector2(3.2, 3.2)}, {"min": Vector2(6.0, 6.0), "max": Vector2(9.2, 9.2)}]
	return frag
