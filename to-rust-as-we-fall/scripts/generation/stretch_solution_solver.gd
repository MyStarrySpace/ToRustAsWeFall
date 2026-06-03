class_name StretchSolutionSolver
extends RefCounted

## Proves a generated stretch is solvable more than one way — and always by the
## Aster+Peris pair. For each canonical loadout (spotlight full party / shadow pair)
## it walks the node spine and, per node, commits to the first APPROACH whose required
## capabilities the loadout can field (its own + any tool placed on the node). A node
## that presents a specialist/shadow split but offers the loadout no satisfiable
## approach is BLOCKED — so "solvable" is a real verdict, not a foregone conclusion.
##
## A stretch is multi-solution when the spotlight and shadow loadouts both reach the
## exit AND diverge on at least one puzzle node (they take different approaches). The
## shadow loadout failing anywhere is a "shadow_broken" warning: the design law is that
## the minimum pair can finish every puzzle.

const CapabilitiesScript := preload("res://scripts/generation/stretch_capabilities.gd")

const REQUIRED_TIERS := ["hard", "setpiece"]

const RISK_WEIGHTS := {"safe": 0, "direct": 1, "risky": 2}


static func analyze_spec(spec: Dictionary) -> Dictionary:
	var nodes: Array = spec.get("nodes", [])
	var tier := str(spec.get("source", {}).get("complexity_tier", spec.get("settings", {}).get("complexity_tier", "teaching")))
	return analyze(nodes, tier)


static func analyze(nodes: Array, tier := "teaching") -> Dictionary:
	var choice_nodes: Array[String] = []
	for node in nodes:
		if node is Dictionary and _presents_choice(node as Dictionary):
			choice_nodes.append(str((node as Dictionary).get("id", "")))

	var solution_paths := []
	for loadout in CapabilitiesScript.loadouts():
		solution_paths.append(_solve_loadout(nodes, loadout))

	var spotlight := _path_for(solution_paths, "spotlight")
	var shadow := _path_for(solution_paths, "shadow")
	var solvable_count := 0
	for path in solution_paths:
		if bool(path.get("solvable", false)):
			solvable_count += 1

	var distinct_nodes: Array[String] = []
	if bool(spotlight.get("solvable", false)) and bool(shadow.get("solvable", false)):
		var shadow_by_node := _approach_by_node(shadow)
		for entry in spotlight.get("approach_per_node", []):
			var node_id := str(entry.get("node", ""))
			if not choice_nodes.has(node_id):
				continue
			if str(entry.get("approach_id", "")) != str(shadow_by_node.get(node_id, {}).get("approach_id", "")):
				distinct_nodes.append(node_id)

	var multi_solution := not distinct_nodes.is_empty()
	var shadow_solvable := bool(shadow.get("solvable", false))
	var required := tier in REQUIRED_TIERS and not choice_nodes.is_empty()

	var warnings := []
	if not shadow_solvable and not (shadow.get("blocked_nodes", []) as Array).is_empty():
		warnings.append({
			"severity": "error",
			"code": "shadow_broken",
			"message": "Aster+Peris cannot solve %s — every puzzle must be solvable by the minimum pair." % str(shadow.get("blocked_nodes", [])),
		})
	if required and not multi_solution:
		warnings.append({
			"severity": "error",
			"code": "multi_solution_missing",
			"message": "Tier '%s' requires at least two distinct solution paths but only one was found." % tier,
		})
	elif not choice_nodes.is_empty() and not multi_solution:
		warnings.append({
			"severity": "warning",
			"code": "single_solution",
			"message": "Puzzle nodes are present but the spotlight and shadow loadouts solve them the same way.",
		})

	return {
		"contract_id": "stretch_solution_analysis_v1",
		"tier": tier,
		"choice_nodes": choice_nodes,
		"choice_node_count": choice_nodes.size(),
		"solution_paths": solution_paths,
		"solvable_loadout_count": solvable_count,
		"shadow_solvable": shadow_solvable,
		"multi_solution": multi_solution,
		"distinct_nodes": distinct_nodes,
		"distinct_node_count": distinct_nodes.size(),
		"multi_solution_required": required,
		"multi_solution_ok": (not required) or multi_solution,
		"warnings": warnings,
	}


## Resolve one loadout against the node spine — the per-node approach commitments
## that make up a single playable solution path.
static func _solve_loadout(nodes: Array, loadout: Dictionary) -> Dictionary:
	var base_caps: Dictionary = loadout.get("base_capabilities", {})
	var approach_per_node := []
	var blocked: Array[String] = []
	var solvable := true
	var total_risk := 0
	for node in nodes:
		if not (node is Dictionary):
			continue
		var node_dict := node as Dictionary
		var node_id := str(node_dict.get("id", ""))
		var approaches: Array = node_dict.get("approaches", [])
		if approaches.is_empty():
			# A plain traversal beat (entry / shelter / unscripted node) — always passable.
			approach_per_node.append({
				"node": node_id,
				"role": str(node_dict.get("role", "")),
				"approach_id": "traverse",
				"kind": "traverse",
				"party": "any",
				"requires": [],
				"risk": "safe",
				"blocked": false,
			})
			continue
		var available := base_caps.duplicate()
		for tag in CapabilitiesScript.node_content_capabilities(node_dict).keys():
			available[tag] = true
		var chosen := {}
		for approach in approaches:
			if not (approach is Dictionary):
				continue
			if CapabilitiesScript.requirements_met((approach as Dictionary).get("requires", []), available):
				chosen = approach as Dictionary
				break
		if chosen.is_empty():
			blocked.append(node_id)
			solvable = false
			approach_per_node.append({
				"node": node_id,
				"role": str(node_dict.get("role", "")),
				"approach_id": "",
				"kind": "blocked",
				"party": "",
				"requires": [],
				"risk": "blocked",
				"blocked": true,
			})
			continue
		var risk := str(chosen.get("risk", "safe"))
		total_risk += int(RISK_WEIGHTS.get(risk, 1))
		approach_per_node.append({
			"node": node_id,
			"role": str(node_dict.get("role", "")),
			"approach_id": str(chosen.get("id", "")),
			"label": str(chosen.get("label", "")),
			"kind": str(chosen.get("kind", "")),
			"party": str(chosen.get("party", "any")),
			"requires": (chosen.get("requires", []) as Array).duplicate(),
			"uses": (chosen.get("uses", []) as Array).duplicate(),
			"risk": risk,
			"taught_by": str(chosen.get("taught_by", "")),
			"blocked": false,
		})
	return {
		"loadout": str(loadout.get("id", "")),
		"label": str(loadout.get("label", "")),
		"party": (loadout.get("party", []) as Array).duplicate(),
		"solvable": solvable,
		"blocked_nodes": blocked,
		"approach_per_node": approach_per_node,
		"total_risk": total_risk,
	}


## A node presents a genuine choice when it offers both a specialist primary approach
## and an Aster+Peris shadow approach — the two ways a thinking player can take it.
static func _presents_choice(node: Dictionary) -> bool:
	var has_specialist := false
	var has_shadow := false
	for approach in node.get("approaches", []):
		if not (approach is Dictionary):
			continue
		match str((approach as Dictionary).get("party", "")):
			"specialist":
				has_specialist = true
			"aster_peris":
				has_shadow = true
	return has_specialist and has_shadow


static func _path_for(solution_paths: Array, loadout_id: String) -> Dictionary:
	for path in solution_paths:
		if path is Dictionary and str((path as Dictionary).get("loadout", "")) == loadout_id:
			return path
	return {}


static func _approach_by_node(path: Dictionary) -> Dictionary:
	var by_node := {}
	for entry in path.get("approach_per_node", []):
		if entry is Dictionary:
			by_node[str((entry as Dictionary).get("node", ""))] = entry
	return by_node
