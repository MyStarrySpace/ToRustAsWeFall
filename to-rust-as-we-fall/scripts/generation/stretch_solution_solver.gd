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
	var prog := int(spec.get("source", {}).get("progression_stage", spec.get("settings", {}).get("progression_stage", 99)))
	var roster = spec.get("source", {}).get("roster", spec.get("settings", {}).get("roster", []))
	return analyze(nodes, tier, prog, roster)


## `roster` is the set of ENABLED characters (the enable/disable options). The spotlight
## loadout is built from it, so disabling the combat character makes a combat-only node fall
## to the pair's approach; the shadow (Aster+Peris) path is unaffected and always solves.
static func analyze(nodes: Array, tier := "teaching", progression_stage := 99, roster = []) -> Dictionary:
	# Only non-optional nodes count toward the multi-solution guarantee: the chunk's golden
	# path (and the playtest) walk the non-optional spine, so an optional detour carrying a
	# choice must not be what proves the stretch is solvable two ways.
	var choice_nodes: Array[String] = []
	for node in nodes:
		if node is Dictionary and not bool((node as Dictionary).get("optional", false)) and _presents_choice(node as Dictionary):
			choice_nodes.append(str((node as Dictionary).get("id", "")))

	var solution_paths := []
	for loadout in CapabilitiesScript.loadouts(roster):
		solution_paths.append(_solve_loadout(nodes, loadout, progression_stage, roster))

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
	var bare_pair_solvable := _bare_pair_solvable(nodes)
	var shadow_uses_future := bool(shadow.get("uses_future_technique", false))
	var spotlight_within_stage := bool(spotlight.get("within_stage", true))

	var warnings := []
	if not bare_pair_solvable:
		warnings.append({
			"severity": "error",
			"code": "bare_pair_unsolvable",
			"message": "A node has no shadow approach the bare Aster+Peris pair can field without a placed tool — the pair must be able to finish unconditionally.",
		})
	if not shadow_solvable and not (shadow.get("blocked_nodes", []) as Array).is_empty():
		warnings.append({
			"severity": "error",
			"code": "shadow_broken",
			"message": "Aster+Peris cannot solve %s — every puzzle must be solvable by the minimum pair." % str(shadow.get("blocked_nodes", [])),
		})
	if not spotlight_within_stage:
		warnings.append({
			"severity": "error",
			"code": "spotlight_out_of_stage",
			"message": "The full-party path relies on a technique from beyond the stretch's progression stage — first-play solutions must stay in-stage.",
		})
	if tier in REQUIRED_TIERS and choice_nodes.is_empty():
		warnings.append({
			"severity": "error",
			"code": "no_puzzle_nodes",
			"message": "Tier '%s' must contain at least one multi-solution puzzle node, but the spine has none (an empty/degenerate archetype pool)." % tier,
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
		"progression_stage": progression_stage,
		"roster": (CapabilitiesScript.normalize_roster(roster).get("enabled", []) as Array),
		"spotlight_party": (spotlight.get("party", []) as Array),
		"choice_nodes": choice_nodes,
		"choice_node_count": choice_nodes.size(),
		"solution_paths": solution_paths,
		"solvable_loadout_count": solvable_count,
		"shadow_solvable": shadow_solvable,
		"bare_pair_solvable": bare_pair_solvable,
		"spotlight_within_stage": spotlight_within_stage,
		"shadow_uses_future_technique": shadow_uses_future,
		"shadow_techniques": shadow.get("techniques", []),
		"multi_solution": multi_solution,
		"distinct_nodes": distinct_nodes,
		"distinct_node_count": distinct_nodes.size(),
		"multi_solution_required": required,
		"multi_solution_ok": (not required) or multi_solution,
		"warnings": warnings,
	}


## Every node must keep at least one approach the bare Aster+Peris pair can field with NO
## placed tool — a CAPABILITY guarantee that the pair can always finish (the design law).
## The qualifying approach may be a harder, later-stage expert technique; the pair being
## able to do it at all is what matters here, not that it is stage-appropriate.
static func _bare_pair_solvable(nodes: Array) -> bool:
	var bare: Dictionary = CapabilitiesScript.bare_pair_capabilities()
	for node in nodes:
		if not (node is Dictionary):
			continue
		var approaches: Array = (node as Dictionary).get("approaches", [])
		if approaches.is_empty():
			continue
		var ok := false
		for approach in approaches:
			if not (approach is Dictionary):
				continue
			if str((approach as Dictionary).get("party", "")) == "specialist":
				continue
			if CapabilitiesScript.requirements_met((approach as Dictionary).get("requires", []), bare):
				ok = true
				break
		if not ok:
			return false
	return true


## Resolve one loadout against the node spine — the per-node approach commitments
## that make up a single playable solution path.
static func _solve_loadout(nodes: Array, loadout: Dictionary, progression_stage := 99, roster = []) -> Dictionary:
	var base_caps: Dictionary = loadout.get("base_capabilities", {})
	var enforce_stage := bool(loadout.get("enforce_stage", false))
	var approach_per_node := []
	var blocked: Array[String] = []
	var solvable := true
	var total_risk := 0
	var max_stage_used := 0
	var uses_future := false
	var within_stage := true
	var techniques: Array[String] = []
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
		var node_stage := int(node_dict.get("stage", 1))
		var available := base_caps.duplicate()
		for tag in CapabilitiesScript.node_content_capabilities(node_dict, roster).keys():
			available[tag] = true
		var chosen := {}
		var first_capable := {}  # first approach the party could field IGNORING the stage gate
		for approach in approaches:
			if not (approach is Dictionary):
				continue
			var ap := approach as Dictionary
			if not CapabilitiesScript.requirements_met(ap.get("requires", []), available):
				continue
			if first_capable.is_empty():
				first_capable = ap
			if enforce_stage and int(ap.get("min_stage", node_stage)) > progression_stage:
				continue  # capable, but this technique is not taught yet at this stage
			chosen = ap
			break
		# If the stage gate pushed the loadout off the approach it would naturally take, the
		# first-play party could not solve this node on its own stage-appropriate line.
		if enforce_stage and not chosen.is_empty() and not first_capable.is_empty() \
				and str(chosen.get("id", "")) != str(first_capable.get("id", "")):
			within_stage = false
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
		var chosen_min_stage := int(chosen.get("min_stage", node_stage))
		var stage_ahead := chosen_min_stage > progression_stage
		max_stage_used = maxi(max_stage_used, chosen_min_stage)
		if stage_ahead:
			uses_future = true
		var taught := str(chosen.get("taught_by", ""))
		if taught != "" and not techniques.has(taught):
			techniques.append(taught)
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
			"min_stage": chosen_min_stage,
			"expert": bool(chosen.get("expert", false)),
			"stage_ahead": stage_ahead,
			"borrows_from": str(chosen.get("borrows_from", "")),
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
		"max_stage_used": max_stage_used,
		"uses_future_technique": uses_future,
		"within_stage": within_stage,
		"techniques": techniques,
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
