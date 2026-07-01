class_name StretchBranchWeaver
extends RefCounted

## Turns a bare linear stretch grid into a SPINE-WITH-BRANCHES (hub-and-spoke) shape: it attaches varied lateral
## ROOMS — spokes — off the spine's OUTWARD rim at spread-out points along the level. On the flat data grid these
## are extra walkable rooms hanging off one side of the corridor; once the chunk warps the grid onto its descending
## helix, "outward" (away from the path centreline) is RADIALLY OUTWARD, so each spoke juts away from the spiral at
## its own angle — the whole thing reads as a star/hub around the spiral instead of a bare curl. Branches are
## OPTIONAL explorable space (dead-end rooms + short loops): they never touch the entry->exit spine, so
## solvability/curriculum (which run on the pre-weave grid) are unaffected — this only ADDS reachable floor + a
## place to scatter reward content, which is what makes a run long enough to matter against the day/night clock.
##
## Deterministic: seeded purely from the level (same grid+seed -> same branches every build), so it's replay-safe
## and the chunk reproduces it identically. Operates on the unified_grid_v1 contract and re-emits the SAME keys,
## with world positions of every existing cell preserved (bounds grow + re-index in lockstep with the origin).

# How many spoke rooms to hang off the spine, by difficulty tier — more (and, below, bigger) for harder stretches
# so exploring them fills more of the day/night budget.
const TIER_BRANCH_COUNT := {"teaching": 2, "standard": 4, "hard": 6, "setpiece": 8}
const _MAX_BRANCHES := 12

## Weave branches into `grid_data`. opts: {seed:int, tier:String, stage:int, count:int(optional override)}.
## Returns a NEW grid_data (the input is not mutated) with the extra walkable cells + a "branches" metadata array
## ([{neck:[x,z], cells:[[x,z],...], shape:String}]). A grid with no walkable cells, or count<=0, is returned as-is.
static func weave(grid_data: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = grid_data.duplicate(true)
	var base_cells: Array = grid_data.get("walkable_cells", [])
	if base_cells.is_empty():
		return out
	var tier := str(opts.get("tier", "standard"))
	var stage := int(opts.get("stage", 1))
	var count := int(opts.get("count", TIER_BRANCH_COUNT.get(tier, 3)))
	count = mini(_MAX_BRANCHES, count + int(stage / 3))   # a little denser deep in a run
	if count <= 0:
		return out
	var seed := int(opts.get("seed", 0)) ^ 0x5b0c_a9e1
	var rng := SeededRng.new(seed)

	# Occupied cells (0-based grid indices). Branches read the spine's OUTWARD (+z) rim per column from this set.
	var cells := {}
	for c in base_cells:
		cells[Vector2i(int(c[0]), int(c[1]))] = true
	var width := int(grid_data.get("width", 1))
	var height := int(grid_data.get("height", 1))

	# Per-column outward rim: the max z of any walkable cell in that column (the spine's outer edge to hang off).
	var rim := {}
	for v in cells.keys():
		if not rim.has(v.x) or v.y > rim[v.x]:
			rim[v.x] = v.y

	# Attach columns spread across the mid 80% of the level so spokes land at varied helix angles (a star, not a
	# comb bunched at one end). Deterministic spacing; jittered a little per branch.
	var branches: Array = []
	var lo := maxi(1, int(width * 0.10))
	var hi := maxi(lo + 1, int(width * 0.90))
	var placed := 0
	for i in range(count):
		var frac := (float(i) + 0.5) / float(count)
		var nx := clampi(lo + int(frac * float(hi - lo)) + rng.randi_range(-1, 1), 1, width - 2)
		if not rim.has(nx):
			nx = _nearest_rim_column(rim, nx, width)
			if nx < 0:
				continue
		var rim_z: int = int(rim[nx])
		var shape := _pick_shape(rng, tier)
		var local: Array = _shape_offsets(shape, rng, tier)
		var branch_cells: Array = []
		var neck := Vector2i(nx, rim_z + 1)
		for off in local:
			var abs_cell := Vector2i(nx + int(off.x), rim_z + 1 + int(off.y))   # +z = outward from the spine
			if cells.has(abs_cell):
				continue
			cells[abs_cell] = true
			branch_cells.append(abs_cell)
		if branch_cells.is_empty():
			continue
		branches.append({"neck": [neck.x, neck.y], "shape": shape, "cells": branch_cells})
		placed += 1

	if placed == 0:
		return out
	return _reemit(out, cells, branches)

# --- shapes ---------------------------------------------------------------------------------------------------

static func _pick_shape(rng: SeededRng, tier: String) -> String:
	var pool := ["chamber", "hall", "pocket", "web"]
	if tier == "teaching":
		pool = ["pocket", "chamber"]
	return str(rng.pick(pool))

## Local cell offsets for a shape, in (dv = lateral spread across the spine, du = depth outward). Always includes
## (0,0) — the neck touching the spine — so the room is path-connected. du grows AWAY from the spine (+z).
static func _shape_offsets(shape: String, rng: SeededRng, tier: String) -> Array:
	var big := 1 if tier == "hard" or tier == "setpiece" else 0
	match shape:
		"pocket":
			return _rect(rng.randi_range(2, 3), rng.randi_range(2, 3))
		"chamber":
			return _rect(rng.randi_range(3, 4 + big), rng.randi_range(4, 5 + big))
		"hall":
			# a long narrow spoke opening into a room at its far end
			var stem: Array = _rect(2, rng.randi_range(3, 4))
			var room: Array = _rect_at(rng.randi_range(4, 5 + big), rng.randi_range(2, 3 + big), 0, len_of(stem))
			return stem + room
		"web":
			# a small hub with thin arms — the "web-like" variant
			var out: Array = _rect(2, 2)
			out.append_array(_rect_at(1, rng.randi_range(2, 3), -2, 1))   # left arm
			out.append_array(_rect_at(1, rng.randi_range(2, 3), 2, 1))    # right arm
			out.append_array(_rect_at(2, rng.randi_range(2, 3), 0, 2))    # far arm
			return out
	return _rect(2, 2)

## A width×depth rectangle of local offsets centred laterally on the neck, growing outward from depth 0.
static func _rect(w: int, d: int) -> Array:
	return _rect_at(w, d, 0, 0)

## width×depth rectangle centred at lateral `cv` and starting at depth `d0`.
static func _rect_at(w: int, d: int, cv: int, d0: int) -> Array:
	var out: Array = []
	var half := int(w / 2)
	for dv in range(-half, w - half):
		for du in range(d):
			out.append(Vector2i(cv + dv, d0 + du))
	return out

## Max depth reached by a set of offsets (so a hall's room can start past its stem).
static func len_of(offsets: Array) -> int:
	var m := 0
	for o in offsets:
		m = maxi(m, int(o.y) + 1)
	return m

static func _nearest_rim_column(rim: Dictionary, nx: int, width: int) -> int:
	for step in range(1, width):
		if rim.has(nx + step):
			return nx + step
		if rim.has(nx - step):
			return nx - step
	return -1

# --- re-emit the unified_grid_v1 with the branch cells added, world positions preserved ------------------------

static func _reemit(out: Dictionary, cells: Dictionary, branches: Array) -> Dictionary:
	# Renormalise so every cell index is >= 0 again; shift the origin in lockstep so no existing cell's WORLD
	# position moves (origin + cell stays constant), and the coord_map (built from the pre-weave spine) still aligns.
	var min_x := 0x7fffffff
	var min_z := 0x7fffffff
	var max_x := -0x7fffffff
	var max_z := -0x7fffffff
	for v in cells.keys():
		min_x = mini(min_x, v.x); min_z = mini(min_z, v.y)
		max_x = maxi(max_x, v.x); max_z = maxi(max_z, v.y)
	var shift := Vector2i(min_x, min_z)
	var cell_size := float(out.get("cell_size", 1.0))
	var origin: Array = out.get("origin", [0.0, 0.45, 0.0])
	out["origin"] = [float(origin[0]) + float(shift.x) * cell_size, float(origin[1]), float(origin[2]) + float(shift.y) * cell_size]
	out["width"] = (max_x - min_x) + 1
	out["height"] = (max_z - min_z) + 1

	out["walkable_cells"] = _sorted_shift(cells.keys(), shift)

	# Branches sit on level 0. If the grid is multi-level, extend level 0's cell list; re-shift the rest.
	var level_cells: Array = out.get("level_cells", [])
	if not level_cells.is_empty():
		out["level_cells"] = _reemit_levels(level_cells, cells, branches, shift)

	# Re-index (shift) the derived cell lists that reference grid cells. Branch cells add none of these.
	out["risk_cell_list"] = _shift_risk(out.get("risk_cell_list", []), shift)
	out["route_cells"] = _shift_routes(out.get("route_cells", {}), shift)
	out["links"] = _shift_links(out.get("links", []), shift)

	# Branch metadata (shifted to the new 0-based frame) for content scatter + tests.
	var brs: Array = []
	for b in branches:
		var nc: Array = b["neck"]
		brs.append({
			"neck": [int(nc[0]) - shift.x, int(nc[1]) - shift.y],
			"shape": str(b["shape"]),
			"cells": _sorted_shift(b["cells"], shift),
		})
	out["branches"] = brs
	return out

static func _reemit_levels(level_cells: Array, all_cells: Dictionary, branches: Array, shift: Vector2i) -> Array:
	# Branch cells all belong to level 0; other levels keep their original cells (re-shifted). Rebuild level 0 as
	# (its original cells + every branch cell), so the union matches walkable_cells.
	var branch_set := {}
	for b in branches:
		for c in b["cells"]:
			branch_set[c] = true
	var out: Array = []
	for entry in level_cells:
		var lvl := int(entry.get("level", 0))
		var lset := {}
		for c in entry.get("cells", []):
			lset[Vector2i(int(c[0]), int(c[1]))] = true
		if lvl == 0:
			for c in branch_set.keys():
				lset[c] = true
		out.append({"level": lvl, "cells": _sorted_shift(lset.keys(), shift)})
	return out

static func _shift_risk(risk_list: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for r in risk_list:
		var c: Array = r.get("cell", [0, 0])
		out.append({"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
			"penalty": float(r.get("penalty", 0.0)), "recoverable": bool(r.get("recoverable", true))})
	return out

static func _shift_routes(route_cells: Dictionary, shift: Vector2i) -> Dictionary:
	var out := {}
	for rid in route_cells.keys():
		var src: Dictionary = route_cells[rid]
		var cells_out: Array = []
		for c in src.get("cells", []):
			cells_out.append([int(c[0]) - shift.x, int(c[1]) - shift.y])
		out[rid] = {"cells": cells_out, "kind": str(src.get("kind", ""))}
	return out

static func _shift_links(links: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for lk in links:
		var c: Array = lk.get("cell", [0, 0])
		out.append({"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
			"from": int(lk.get("from", 0)), "to": int(lk.get("to", 0)), "type": str(lk.get("type", "ramp"))})
	return out

static func _sorted_shift(keys, shift: Vector2i) -> Array:
	var arr: Array = []
	for v in keys:
		arr.append(v)
	arr.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var out: Array = []
	for v in arr:
		out.append([v.x - shift.x, v.y - shift.y])
	return out
