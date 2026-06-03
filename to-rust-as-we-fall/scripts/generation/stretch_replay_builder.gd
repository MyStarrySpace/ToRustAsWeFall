class_name StretchReplayBuilder
extends RefCounted

## Turns a generated stretch spec into a self-contained, deterministic REPLAY: a flat
## top-down projection of the level plus, for each solution loadout (spotlight full
## party / Aster+Peris shadow), a keyframed path of the party executing that solution
## node by node. The replay is pure data (no scene, no RNG), so the same artifact drives
## an in-game replay viewer and the Android level-sketch app's playback — both just
## interpolate the keyframes and show the per-node approach caption.

const SCHEMA := "trawf_stretch_replay_v1"
const DEFAULT_CELL_WORLD_SIZE := 2.0
const NODE_BEAT := 1.0  # seconds of replay time spent crossing to / solving each node

## Formation offsets (in cells) so party members read as a small group, not one dot.
const FORMATION := {
	"aster": [0.0, -0.35],
	"peris": [-0.4, 0.3],
	"endo": [0.4, 0.3],
}


static func build(spec: Dictionary, options := {}) -> Dictionary:
	var nodes: Array = spec.get("nodes", [])
	var routes: Array = spec.get("routes", [])
	var cell_size := float(options.get("cell_world_size", DEFAULT_CELL_WORLD_SIZE))
	var origin := _compute_origin(nodes)
	var grid := {
		"cell_world_size": cell_size,
		"origin": origin,
	}
	var node_cells := {}
	for node in nodes:
		if node is Dictionary:
			node_cells[str((node as Dictionary).get("id", ""))] = _project((node as Dictionary).get("position", []), origin, cell_size)

	var level := {
		"nodes": _project_nodes(nodes, origin, cell_size),
		"routes": _project_routes(routes, node_cells),
		"content": _project_content(nodes, origin, cell_size),
		"bounds_cells": _bounds_cells(node_cells, origin, cell_size, nodes),
	}

	var solutions := []
	for path in spec.get("headless", {}).get("solution_paths", []):
		if path is Dictionary:
			solutions.append(_build_solution(path as Dictionary, node_cells))

	return {
		"schema": SCHEMA,
		"spec_id": str(spec.get("id", "generated_stretch")),
		"title": str(spec.get("title", "Generated Stretch")),
		"region": str(spec.get("world_slot", {}).get("region", "")),
		"complexity_tier": str(spec.get("source", {}).get("complexity_tier", "")),
		"progression_stage": int(spec.get("source", {}).get("progression_stage", 99)),
		"grid": grid,
		"level": level,
		"solutions": solutions,
		"multi_solution": bool(spec.get("headless", {}).get("solution_summary", {}).get("multi_solution", false)),
	}


static func _build_solution(path: Dictionary, node_cells: Dictionary) -> Dictionary:
	var party := _string_array(path.get("party", ["aster", "peris", "endo"]))
	var frames := []
	var node_approaches := []
	var t := 0.0
	for entry in path.get("approach_per_node", []):
		if not (entry is Dictionary):
			continue
		var node_id := str((entry as Dictionary).get("node", ""))
		var cell: Array = node_cells.get(node_id, [0.0, 0.0])
		var characters := {}
		for member in party:
			var offset: Array = FORMATION.get(member, [0.0, 0.0])
			characters[member] = [float(cell[0]) + float(offset[0]), float(cell[1]) + float(offset[1])]
		var label := str((entry as Dictionary).get("label", ""))
		var expert := bool((entry as Dictionary).get("expert", false)) or bool((entry as Dictionary).get("stage_ahead", false))
		var caption := node_id if label == "" else "%s — %s" % [node_id, label]
		if expert:
			caption += "  ⟐ expert: later-stage technique"
		frames.append({
			"t": t,
			"node": node_id,
			"role": str((entry as Dictionary).get("role", "")),
			"approach_id": str((entry as Dictionary).get("approach_id", "")),
			"kind": str((entry as Dictionary).get("kind", "")),
			"risk": str((entry as Dictionary).get("risk", "")),
			"min_stage": int((entry as Dictionary).get("min_stage", 0)),
			"expert": expert,
			"stage_ahead": bool((entry as Dictionary).get("stage_ahead", false)),
			"borrows_from": str((entry as Dictionary).get("borrows_from", "")),
			"caption": caption,
			"blocked": bool((entry as Dictionary).get("blocked", false)),
			"characters": characters,
		})
		node_approaches.append({
			"node": node_id,
			"approach_id": str((entry as Dictionary).get("approach_id", "")),
			"label": label,
			"kind": str((entry as Dictionary).get("kind", "")),
			"party": str((entry as Dictionary).get("party", "")),
			"risk": str((entry as Dictionary).get("risk", "")),
			"min_stage": int((entry as Dictionary).get("min_stage", 0)),
			"expert": expert,
			"stage_ahead": bool((entry as Dictionary).get("stage_ahead", false)),
			"borrows_from": str((entry as Dictionary).get("borrows_from", "")),
		})
		t += NODE_BEAT
	return {
		"loadout": str(path.get("loadout", "")),
		"label": str(path.get("label", "")),
		"party": party,
		"solvable": bool(path.get("solvable", false)),
		"uses_future_technique": bool(path.get("uses_future_technique", false)),
		"max_stage_used": int(path.get("max_stage_used", 0)),
		"blocked_nodes": path.get("blocked_nodes", []),
		"duration": maxf(0.0, t - NODE_BEAT),
		"frames": frames,
		"node_approaches": node_approaches,
	}


static func _project_nodes(nodes: Array, origin: Array, cell_size: float) -> Array:
	var result := []
	for node in nodes:
		if not (node is Dictionary):
			continue
		var n := node as Dictionary
		var cell := _project(n.get("position", []), origin, cell_size)
		result.append({
			"id": str(n.get("id", "")),
			"role": str(n.get("role", "")),
			"label": str(n.get("title", n.get("label", ""))),
			"archetype_id": str(n.get("archetype_id", "")),
			"cell": [roundi(float(cell[0])), roundi(float(cell[1]))],
			"level": int(n.get("elevation_index", 0)),
			"optional": bool(n.get("optional", false)),
		})
	return result


static func _project_routes(routes: Array, node_cells: Dictionary) -> Array:
	var result := []
	for route in routes:
		if not (route is Dictionary):
			continue
		var r := route as Dictionary
		var from_id := str(r.get("from", ""))
		var to_id := str(r.get("to", ""))
		if not node_cells.has(from_id) or not node_cells.has(to_id):
			continue
		var from_cell: Array = node_cells[from_id]
		var to_cell: Array = node_cells[to_id]
		result.append({
			"id": str(r.get("id", "")),
			"kind": _route_kind(r),
			"from": from_id,
			"to": to_id,
			"from_cell": [roundi(float(from_cell[0])), roundi(float(from_cell[1]))],
			"to_cell": [roundi(float(to_cell[0])), roundi(float(to_cell[1]))],
		})
	return result


static func _project_content(nodes: Array, origin: Array, cell_size: float) -> Array:
	var result := []
	for node in nodes:
		if not (node is Dictionary):
			continue
		var n := node as Dictionary
		var placements: Array = n.get("content_placements", [])
		if not placements.is_empty():
			for placement in placements:
				if not (placement is Dictionary):
					continue
				var p := placement as Dictionary
				var cell := _project(p.get("position", p.get("world_position", [])), origin, cell_size)
				result.append({
					"kind": str(p.get("key", p.get("id", ""))),
					"category": str(p.get("category", "")),
					"cell": [roundi(float(cell[0])), roundi(float(cell[1]))],
					"level": int(n.get("elevation_index", 0)),
					"support": str(p.get("support", "")),
				})
		else:
			# No detailed placements — fall back to the node's content lists at the node cell.
			var node_cell := _project(n.get("position", []), origin, cell_size)
			for category in ["flora", "enemies", "structures"]:
				for key in n.get(category, []):
					result.append({
						"kind": str(key),
						"category": category,
						"cell": [roundi(float(node_cell[0])), roundi(float(node_cell[1]))],
						"level": int(n.get("elevation_index", 0)),
						"support": "",
					})
	return result


static func _compute_origin(nodes: Array) -> Array:
	var min_x := 1.0e20
	var min_z := 1.0e20
	for node in nodes:
		if not (node is Dictionary):
			continue
		var pos: Array = (node as Dictionary).get("position", [])
		if pos.size() >= 3:
			min_x = minf(min_x, float(pos[0]))
			min_z = minf(min_z, float(pos[2]))
	if min_x > 1.0e19:
		min_x = 0.0
		min_z = 0.0
	return [min_x, min_z]


static func _bounds_cells(node_cells: Dictionary, origin: Array, cell_size: float, nodes: Array) -> Dictionary:
	var max_x := 0
	var max_y := 0
	var min_x := 0
	var min_y := 0
	var first := true
	for key in node_cells.keys():
		var cell: Array = node_cells[key]
		var cx := roundi(float(cell[0]))
		var cy := roundi(float(cell[1]))
		if first:
			min_x = cx; max_x = cx; min_y = cy; max_y = cy; first = false
		else:
			min_x = mini(min_x, cx); max_x = maxi(max_x, cx)
			min_y = mini(min_y, cy); max_y = maxi(max_y, cy)
	return {"min": [min_x, min_y], "max": [max_x, max_y], "width": max_x - min_x + 1, "height": max_y - min_y + 1}


static func _project(pos: Variant, origin: Array, cell_size: float) -> Array:
	if pos is Array and (pos as Array).size() >= 3 and cell_size > 0.0:
		var x := float((pos as Array)[0])
		var z := float((pos as Array)[2])
		return [(x - float(origin[0])) / cell_size, (z - float(origin[1])) / cell_size]
	return [0.0, 0.0]


static func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", ""))
	return kind if kind != "" else str(route.get("risk", "safe"))


static func _string_array(value: Variant) -> Array:
	var result := []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result
