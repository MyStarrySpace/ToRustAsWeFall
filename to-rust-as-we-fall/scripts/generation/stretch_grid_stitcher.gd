class_name StretchGridStitcher
extends RefCounted

## Rasterizes the WFC layout (room-piece walkable masks + corridor cells) into ONE contiguous unified_grid_v1
## payload — the exact GridWorld.from_data contract the runtime chunk + preview already consume, so nothing
## downstream changes. Also guarantees entry->exit connectivity (force-carves a straight link if a layout ever
## leaves them in separate components). Pure + deterministic (sorted-cell exports, no RNG).

const CELL := 1.0
const MARGIN := 3
const ORIGIN_Y := 0.45
const LEVEL_HEIGHT := 0.72

## build(placements, corridors, slot_cells, settings) -> unified_grid_v1 Dictionary (empty if no cells).
static func build(placements: Array, corridors: Array, slot_cells: Dictionary, settings: Dictionary) -> Dictionary:
	var walk := {}          # level:int -> { Vector2i(abs): true }
	var risk := {}          # Vector2i(abs) -> {penalty, recoverable}
	var route_cells := {}   # route_id -> {cells:[abs], kind}

	# Room-piece floor cells.
	for p in placements:
		if not (p is Dictionary):
			continue
		var node := str(p["node"])
		var origin := Vector2i(int(p["origin_cell"][0]), int(p["origin_cell"][1]))
		var lvl := int(p["level"])
		var info: Dictionary = slot_cells.get(node, {})
		var wk: Array = info.get("walkable", [])
		for ny in range(wk.size()):
			var rowstr := str(wk[ny])
			for nx in range(rowstr.length()):
				if rowstr[nx] == ".":
					_mark(walk, lvl, Vector2i(origin.x + nx, origin.y + ny))

	# Corridor cells (+ risk on risky/shortcut routes).
	for c in corridors:
		if not (c is Dictionary):
			continue
		var lvl2 := int(c["level"])
		var kind := str(c.get("kind", "safe"))
		var pen := _risk_penalty(kind)
		var exported: Array = []
		for cellpt in c["cells"]:
			var v := Vector2i(int(cellpt[0]), int(cellpt[1]))
			_mark(walk, lvl2, v)
			exported.append(v)
			if pen > 0.0:
				var existing: Dictionary = risk.get(v, {})
				if existing.is_empty() or float(existing.get("penalty", 0.0)) < pen:
					risk[v] = {"penalty": pen, "recoverable": bool(c.get("recoverable", true))}
		route_cells[str(c["route"])] = {"cells": exported, "kind": kind}

	if walk.is_empty():
		return {}

	# Connectivity guard: flood from the entry; force-carve a straight link to any unreachable component the
	# exit lands in (belt-and-suspenders — the spine corridors already connect entry->exit by construction).
	_ensure_connected(walk, route_cells, slot_cells)

	# Global cell bounds over every level.
	var min_x := 0x7fffffff
	var min_z := 0x7fffffff
	var max_x := -0x7fffffff
	var max_z := -0x7fffffff
	for lvl in walk.keys():
		for v in (walk[lvl] as Dictionary).keys():
			min_x = mini(min_x, v.x)
			min_z = mini(min_z, v.y)
			max_x = maxi(max_x, v.x)
			max_z = maxi(max_z, v.y)
	var off := Vector2i(min_x - MARGIN, min_z - MARGIN)   # abs cell -> grid cell = abs - off
	var grid_w := (max_x - min_x) + 2 * MARGIN + 1
	var grid_h := (max_z - min_z) + 2 * MARGIN + 1
	var origin := Vector3(float(off.x) * CELL, ORIGIN_Y, float(off.y) * CELL)

	var elevation_indices: Array[int] = []
	for lvl in walk.keys():
		if not elevation_indices.has(int(lvl)):
			elevation_indices.append(int(lvl))
	elevation_indices.sort()
	var multi: bool = elevation_indices.size() > 1
	var level_count: int = (int(elevation_indices[elevation_indices.size() - 1]) + 1) if multi else 1

	# walkable_cells (offset to 0-based grid cells, canonical sorted order for determinism).
	var all_cells := {}
	for lvl in walk.keys():
		for v in (walk[lvl] as Dictionary).keys():
			all_cells[v] = true
	var walk_cells := _sorted_cell_list(all_cells.keys(), off)

	var level_cells: Array = []
	if multi:
		for lvl in range(level_count):
			if not walk.has(lvl):
				continue
			level_cells.append({"level": lvl, "cells": _sorted_cell_list((walk[lvl] as Dictionary).keys(), off)})

	var risk_list: Array = []
	for v in _sorted_keys(risk.keys()):
		risk_list.append({"cell": [v.x - off.x, v.y - off.y],
			"penalty": float(risk[v]["penalty"]), "recoverable": bool(risk[v]["recoverable"])})

	var route_cells_out := {}
	for rid in route_cells.keys():
		var src: Dictionary = route_cells[rid]
		var cells_out: Array = []
		for v in src["cells"]:
			cells_out.append([v.x - off.x, v.y - off.y])
		route_cells_out[rid] = {"cells": cells_out, "kind": str(src["kind"])}

	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"space_id": str(settings.get("id", "generated_stretch")),
		"supports_multiple_elevations": multi,
		"elevation_indices": elevation_indices,
		"origin": [origin.x, origin.y, origin.z],
		"cell_size": CELL,
		"width": grid_w,
		"height": grid_h,
		"walkable_cells": walk_cells,
		"level_cells": level_cells,
		"risk_cell_list": risk_list,
		"links": [],
		"level_count": level_count,
		"level_height": LEVEL_HEIGHT,
		"route_cells": route_cells_out,
		"entry_anchor": "entry",
		"exit_anchor": "exit_shelter",
	}

## World position (cell centre) of a node's connection cell — the generator reconciles node.position from this.
static func node_world(slot_cells: Dictionary, node_id: String) -> Vector3:
	var info: Dictionary = slot_cells.get(node_id, {})
	if info.is_empty():
		return Vector3(0, ORIGIN_Y, 0)
	var c: Array = info.get("connection_cell", [0, 0])
	var lvl := int(info.get("level", 0))
	return Vector3(float(c[0]) + 0.5, ORIGIN_Y + float(lvl) * LEVEL_HEIGHT, float(c[1]) + 0.5)

# --- helpers ---

static func _mark(walk: Dictionary, lvl: int, v: Vector2i) -> void:
	if not walk.has(lvl):
		walk[lvl] = {}
	walk[lvl][v] = true

static func _risk_penalty(kind: String) -> float:
	match kind:
		"risky": return 6.0
		"shortcut": return 3.0
	return 0.0

static func _sorted_cell_list(keys: Array, off: Vector2i) -> Array:
	var sorted := _sorted_keys(keys)
	var out: Array = []
	for v in sorted:
		out.append([v.x - off.x, v.y - off.y])
	return out

static func _sorted_keys(keys: Array) -> Array:
	var arr := keys.duplicate()
	arr.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	return arr

## BFS from the entry over the combined walkable set (per level). If exit_shelter's cell isn't reached, carve a
## straight axis-first corridor from the nearest reached cell to it on the exit's level.
static func _ensure_connected(walk: Dictionary, route_cells: Dictionary, slot_cells: Dictionary) -> void:
	var entry: Dictionary = slot_cells.get("entry", {})
	var exit: Dictionary = slot_cells.get("exit_shelter", {})
	if entry.is_empty() or exit.is_empty():
		return
	var start := Vector2i(int(entry["connection_cell"][0]), int(entry["connection_cell"][1]))
	var goal := Vector2i(int(exit["connection_cell"][0]), int(exit["connection_cell"][1]))
	var goal_lvl := int(exit.get("level", 0))
	# Flood on the goal's level only (Phase 1 is single-level; cross-level links come later).
	var cells: Dictionary = walk.get(goal_lvl, {})
	if cells.is_empty():
		return
	var seen := {}
	var queue: Array = [start]
	seen[start] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + d
			if cells.has(nx) and not seen.has(nx):
				seen[nx] = true
				queue.append(nx)
	if seen.has(goal):
		return
	# Force-carve a straight L from start to goal on the goal level.
	var carved: Array = []
	var x := start.x
	while x != goal.x:
		var v := Vector2i(x, start.y)
		_mark(walk, goal_lvl, v); carved.append(v)
		x += 1 if goal.x > start.x else -1
	var y := start.y
	while y != goal.y:
		var v2 := Vector2i(goal.x, y)
		_mark(walk, goal_lvl, v2); carved.append(v2)
		y += 1 if goal.y > start.y else -1
	_mark(walk, goal_lvl, goal)
	route_cells["__forced_connect"] = {"cells": carved, "kind": "safe"}
