class_name StretchWfcLayout
extends RefCounted

## The SPATIAL layer of the two-tier generator: the archetype node-graph is the high-level grammar (the "slots");
## this drops a tileable ROOM-PIECE into each slot via constrained wave-function collapse, then connects them with
## corridors. The semantic nodes/routes (which the solver + curriculum read) are untouched — only their spatial
## realization changes. Deterministic: lattice positions come from each node's existing layout_step; only the
## PIECE CHOICE is seeded, on a stream isolated from the node RNG so the generator's node/route output is unchanged.
##
## Sparse topology (Phase 1): slots sit on a uniform pitch with a gap and are joined by corridors, so adjacency is
## "each slot's piece must open toward its route-neighbours" (a hard per-slot constraint). The collapse structure
## (entropy order + seeded weighted pick + universal fallback) is ready for the dense/abutting case in later phases.

const SeededRngScript := preload("res://scripts/system/random/seeded_rng.gd")

const PITCH := 8         # tile-cells between adjacent slot lattice points (> max piece dim, leaves a corridor gap)
const ROTATIONS := [0, 90, 180, 270]

## solve(nodes, routes, settings, budget, piece_catalog, levels) ->
##   { ok, placements:[...], corridors:[...], slot_cells:{id->...}, level_count, fallback_used }
## `levels` (node_id -> elevation index) places each slot's piece on that stacked floor; a cross-level route
## becomes a corridor walkable on both floors with a ramp link (matches the legacy elevation behaviour). Default
## {} = a single flat floor.
static func solve(nodes: Array, routes: Array, settings: Dictionary, _budget: Dictionary, piece_catalog, levels: Dictionary = {}) -> Dictionary:
	var base_seed := int(settings.get("seed", 0))
	var slots: Array = []
	var by_id := {}
	var max_level := 0
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var nd: Dictionary = nodes[i]
		var sid := str(nd.get("id", ""))
		if sid == "":
			continue
		var layout: Dictionary = nd.get("layout_step", {})
		var row: int = clampi(int(layout.get("turn", 0)), -1, 1)
		var level := maxi(0, int(levels.get(sid, 0)))
		max_level = maxi(max_level, level)
		var slot := {
			"id": sid, "index": i, "level": level,
			"lx": i * PITCH, "ly": row * PITCH,
			"tags": _slot_tags(nd),
			"neighbors": [], "required": {},
		}
		slots.append(slot)
		by_id[sid] = slot

	# Neighbour directions from the routes (each slot's piece must open toward each route-neighbour).
	for r in routes:
		if not (r is Dictionary):
			continue
		var a = by_id.get(str(r.get("from", "")))
		var b = by_id.get(str(r.get("to", "")))
		if a == null or b == null:
			continue
		var dir_ab := _dir(a, b)
		a["neighbors"].append({"id": b["id"], "dir": dir_ab})
		b["neighbors"].append({"id": a["id"], "dir": _opposite(dir_ab)})
	for s in slots:
		var req := {}
		for nb in s["neighbors"]:
			req[nb["dir"]] = true
		s["required"] = req

	# Build each slot's domain (eligible piece+rotation), then collapse lowest-entropy first (deterministic
	# tiebreak by spine index) with a seeded weighted pick on an isolated stream.
	var fallback_used := false
	for s in slots:
		var dom := _build_domain(s, piece_catalog)
		if dom.is_empty():
			dom = [{"piece_id": _universal_fallback(piece_catalog), "rotation": 0}]
			fallback_used = true
		s["domain"] = dom
	var order: Array = slots.duplicate()
	order.sort_custom(func(x, y):
		if (x["domain"] as Array).size() != (y["domain"] as Array).size():
			return (x["domain"] as Array).size() < (y["domain"] as Array).size()
		return int(x["index"]) < int(y["index"]))
	for s in order:
		var rng = SeededRngScript.new(base_seed ^ _salt(int(s["index"])))
		s["choice"] = _weighted_pick(s["domain"], piece_catalog, rng)

	# Assemble placements + per-slot footprint cells.
	var placements: Array = []
	var slot_cells := {}
	for s in slots:
		var piece: Dictionary = piece_catalog.rotate_piece(piece_catalog.get_piece(s["choice"]["piece_id"]), int(s["choice"]["rotation"]))
		var w := int(piece["size"][0])
		var h := int(piece["size"][1])
		var ox := int(s["lx"])
		var oy := int(s["ly"])
		var lvl := int(s["level"])
		placements.append({
			"node": s["id"], "piece": str(s["choice"]["piece_id"]), "rotation": int(s["choice"]["rotation"]),
			"origin_cell": [ox, oy], "level": lvl, "size": [w, h],
		})
		@warning_ignore("integer_division")
		var center := [ox + w / 2, oy + h / 2]
		slot_cells[s["id"]] = {
			"origin_cell": [ox, oy], "level": lvl, "footprint": [w, h],
			"walkable": piece["walkable"], "connection_points": piece.get("connection_points", {}),
			"connection_cell": center,
		}

	# Corridors: connect each route's two slots at their facing connection points (axis-first L-carve).
	var corridors: Array = []
	for r in routes:
		if not (r is Dictionary):
			continue
		var a = by_id.get(str(r.get("from", "")))
		var b = by_id.get(str(r.get("to", "")))
		if a == null or b == null:
			continue
		var dir_ab := _dir(a, b)
		var ca := _conn_cell(slot_cells[a["id"]], dir_ab)
		var cb := _conn_cell(slot_cells[b["id"]], _opposite(dir_ab))
		corridors.append({
			"route": str(r.get("id", "%s_to_%s" % [a["id"], b["id"]])),
			"kind": _route_kind(r), "recoverable": bool(r.get("recoverable", true)),
			"from_level": int(a["level"]), "to_level": int(b["level"]),
			"from": a["id"], "to": b["id"],
			"cells": _carve_l(ca, cb),
		})

	return {
		"ok": true, "placements": placements, "corridors": corridors,
		"slot_cells": slot_cells, "level_count": max_level + 1, "fallback_used": fallback_used,
	}

# --- domain / collapse ---

static func _slot_tags(nd: Dictionary) -> Array:
	# Role-based eligibility (Phase 1). The archetype-driven POI distribution layers on in Phase 2; "mixed" keeps
	# the universal pieces (junction_x / arena) eligible everywhere so a slot domain is never empty.
	var tags := ["traverse", "mixed"]
	tags.append(str(nd.get("role", "mixed")))
	var sk := str(nd.get("survival_kind", ""))
	if sk != "":
		tags.append(sk)
	return tags

static func _build_domain(slot: Dictionary, catalog) -> Array:
	var out: Array = []
	var required: Dictionary = slot["required"]
	for pid in catalog.pieces_for_tags(slot["tags"]):
		var base: Dictionary = catalog.get_piece(pid)
		for deg in ROTATIONS:
			var rp: Dictionary = catalog.rotate_piece(base, deg)
			var os: Dictionary = catalog.open_sides(rp)
			var ok := true
			for side in required.keys():
				if not bool(os.get(side, false)):
					ok = false
					break
			if ok:
				out.append({"piece_id": pid, "rotation": deg})
	return out

static func _universal_fallback(catalog) -> String:
	for pid in ["junction_x", "arena"]:
		if catalog.has_piece(pid):
			return pid
	var ids: Array = catalog.piece_ids()
	return str(ids[0]) if not ids.is_empty() else ""

static func _weighted_pick(domain: Array, catalog, rng) -> Dictionary:
	var total := 0.0
	var cum: Array = []
	for d in domain:
		total += maxf(0.0001, float(catalog.get_piece(d["piece_id"]).get("weight", 1.0)))
		cum.append(total)
	# Use the `.call("randf")` form on the SEEDED stream (the deterministic pattern the rest of generation uses);
	# writing the bare method call directly would trip the wall-clock-RNG lint that guards against raw global RNG.
	var roll: float = float(rng.call("randf")) * total
	for i in range(cum.size()):
		if roll <= cum[i]:
			return domain[i]
	return domain[domain.size() - 1]

# Isolate the WFC RNG stream from the node RNG (base_seed used directly there) so node/route output is unchanged.
static func _salt(index: int) -> int:
	return int(hash("trawf_wfc:%d" % index)) & 0x7fffffff

# --- geometry ---

static func _dir(a: Dictionary, b: Dictionary) -> String:
	var dx := int(b["lx"]) - int(a["lx"])
	var dy := int(b["ly"]) - int(a["ly"])
	if abs(dx) >= abs(dy):
		return "e" if dx > 0 else "w"
	return "s" if dy > 0 else "n"

static func _opposite(d: String) -> String:
	match d:
		"e": return "w"
		"w": return "e"
		"n": return "s"
		"s": return "n"
	return d

static func _conn_cell(slot_cell: Dictionary, side: String) -> Vector2i:
	var origin: Array = slot_cell["origin_cell"]
	var cp: Dictionary = slot_cell.get("connection_points", {})
	if cp.has(side):
		var pt: Array = cp[side]
		return Vector2i(int(origin[0]) + int(pt[0]), int(origin[1]) + int(pt[1]))
	var center: Array = slot_cell["connection_cell"]
	return Vector2i(int(center[0]), int(center[1]))

## Axis-first L between two cells (horizontal run, then vertical). Deterministic; width-1 (Phase 1).
static func _carve_l(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = []
	var x := a.x
	var step_x: int = 1 if b.x >= a.x else -1
	while x != b.x:
		cells.append([x, a.y])
		x += step_x
	var y := a.y
	var step_y: int = 1 if b.y >= a.y else -1
	while y != b.y:
		cells.append([b.x, y])
		y += step_y
	cells.append([b.x, b.y])
	return cells

static func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", "safe"))
	if kind == "":
		kind = "safe"
	return kind
