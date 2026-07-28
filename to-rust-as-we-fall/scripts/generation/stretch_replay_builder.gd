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
const RuntimeRegistryScript := preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)

## Formation offsets (in cells) so party members read as a small group, not one dot.
## A six-slot wedge: Aster points, the support pair flanks, the rear rank trails — every
## canonical member gets a distinct slot so the full party never collapses onto one cell.
const FORMATION := {
	"aster": [0.0, -0.45],
	"peris": [-0.42, -0.12],
	"endo": [0.42, -0.12],
	"myke": [0.0, 0.22],
	"oli": [-0.42, 0.42],
	"tyreg": [0.42, 0.42],
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
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	for path in spec.get("headless", {}).get("solution_paths", []):
		if path is Dictionary:
			solutions.append(_build_solution(
				path as Dictionary, node_cells, navigation_grid, origin, cell_size
			))

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


static func _build_solution(
		path: Dictionary,
		node_cells: Dictionary,
		navigation_grid: Dictionary,
		replay_origin: Array,
		replay_cell_size: float
) -> Dictionary:
	var party := _string_array(path.get("party", ["aster", "peris", "endo"]))
	var frames := []
	var node_approaches := []
	var branch_actions: Array = path.get("branch_actions", [])
	var branch_actions_by_node := {}
	for action_v in branch_actions:
		if not (action_v is Dictionary):
			continue
		var before_node := str((action_v as Dictionary).get("before_node", ""))
		if not branch_actions_by_node.has(before_node):
			branch_actions_by_node[before_node] = []
		(branch_actions_by_node[before_node] as Array).append(action_v)
	var t := 0.0
	for entry in path.get("approach_per_node", []):
		if not (entry is Dictionary):
			continue
		var node_id := str((entry as Dictionary).get("node", ""))
		for action_v in branch_actions_by_node.get(node_id, []):
			var action := action_v as Dictionary
			var producer_cell := _branch_action_replay_cell(
				action, navigation_grid, replay_origin, replay_cell_size
			)
			frames.append({
				"t": t,
				"node": node_id,
				"role": str(action.get("role", "mandatory_producer")),
				"approach_id": str(action.get("id", "")),
				"kind": str(action.get("kind", "mandatory_branch_interaction")),
				"risk": "safe",
				"min_stage": 0,
				"expert": false,
				"stage_ahead": false,
				"borrows_from": "",
				"caption": "SIDE BRANCH — EXTEND DOWNSTREAM SPAN",
				"blocked": false,
				"branch_action": action.duplicate(true),
				"characters": _formation_at(producer_cell, party),
			})
			t += NODE_BEAT
		var cell: Array = node_cells.get(node_id, [0.0, 0.0])
		var characters := {}
		for member in party:
			if not FORMATION.has(member):
				# A roster member with no formation slot would stack on the node cell — warn so
				# FORMATION is kept in sync with the roster rather than silently colliding.
				push_warning("stretch_replay_builder: no FORMATION slot for '%s' — add one to avoid overlap" % member)
			var offset: Array = FORMATION.get(member, [0.0, 0.0])
			characters[member] = [float(cell[0]) + float(offset[0]), float(cell[1]) + float(offset[1])]
		var label := str((entry as Dictionary).get("label", ""))
		var expert := bool((entry as Dictionary).get("expert", false))
		var stage_ahead := bool((entry as Dictionary).get("stage_ahead", false))
		var caption := node_id if label == "" else "%s — %s" % [node_id, label]
		if stage_ahead:
			caption += "  ⟐ expert: later-stage technique"
		elif expert:
			caption += "  ⟐ expert technique"
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
		"branch_actions": branch_actions.duplicate(true),
		"branch_action_count": branch_actions.size(),
	}


static func _branch_action_replay_cell(
		action: Dictionary,
		navigation_grid: Dictionary,
		replay_origin: Array,
		replay_cell_size: float
) -> Array:
	var producer: Array = action.get("producer_cell", [])
	if producer.size() < 2:
		return [0.0, 0.0]
	var nav_origin: Array = navigation_grid.get("origin", [0.0, 0.0, 0.0])
	var nav_cell_size := float(navigation_grid.get("cell_size", 1.0))
	return _project([
		float(nav_origin[0]) + (float(producer[0]) + 0.5) * nav_cell_size,
		float(nav_origin[1]),
		float(nav_origin[2]) + (float(producer[1]) + 0.5) * nav_cell_size,
	], replay_origin, replay_cell_size)


static func _formation_at(cell: Array, party: Array) -> Dictionary:
	var characters := {}
	for member in party:
		if not FORMATION.has(member):
			push_warning(
				"stretch_replay_builder: no FORMATION slot for '%s' — add one to avoid overlap"
				% member
			)
		var offset: Array = FORMATION.get(member, [0.0, 0.0])
		characters[member] = [
			float(cell[0]) + float(offset[0]),
			float(cell[1]) + float(offset[1]),
		]
	return characters


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
		if n.has("content_placements"):
			for placement in placements:
				if not (placement is Dictionary):
					continue
				var p := placement as Dictionary
				var category := str(p.get("category", ""))
				var content_id := str(p.get("key", p.get("id", "")))
				if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id
				):
					continue
				var cell := _project(p.get("position", p.get("world_position", [])), origin, cell_size)
				result.append({
					"kind": content_id,
					"category": category,
					"cell": [roundi(float(cell[0])), roundi(float(cell[1]))],
					"level": int(n.get("elevation_index", 0)),
					"support": str(p.get("support", "")),
				})
		else:
			# No detailed placements — fall back to the node's content lists at the node cell.
			var node_cell := _project(n.get("position", []), origin, cell_size)
			for category in ["flora", "enemies", "structures"]:
				for key in n.get(category, []):
					if not RuntimeRegistryScript.generated_content_is_realized(
						category, str(key)
					):
						continue
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
