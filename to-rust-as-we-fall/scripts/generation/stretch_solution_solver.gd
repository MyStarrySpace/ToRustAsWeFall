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
const RuntimeRegistryScript := preload("res://scripts/generation/generated_node_runtime_registry.gd")
const BranchWeaverScript := preload("res://scripts/generation/stretch_branch_weaver.gd")

const REQUIRED_TIERS := ["hard", "setpiece"]

const RISK_WEIGHTS := {"safe": 0, "direct": 1, "risky": 2}

## Combination-pressure model. Every committed approach carries a base attrition cost (its
## risk plus the node's own survival pressure). On a choice node — one offering both the
## combined (specialist/multi-character) approach and the Aster+Peris pair approach — the
## combined line is the cleaner one, so the PAIR pays an extra premium that grows with the
## progression stage: the pair-solve stays valid everywhere, but becomes visibly costlier
## the later the stretch sits, which is how "combination becomes needed, not required" reads.
const PRESSURE_PER_RISK := 1.0
const PRESSURE_SURVIVAL := {"forage": 0.0, "rest": 0.0, "exploit": 1.0, "hazard": 2.0, "gauntlet": 2.0}
const COMBINATION_PREMIUM_BASE := 1.0
const COMBINATION_PREMIUM_PER_STAGE := 1.0
## The combined (specialist) line shaves a little off the base at a choice node — the clean
## solve — so even at stage 0 the two costs differ in the pair's disfavour.
const COMBINATION_SPOTLIGHT_RELIEF := 0.5


static func analyze_spec(spec: Dictionary) -> Dictionary:
	var nodes: Array = spec.get("nodes", [])
	var tier := str(spec.get("source", {}).get("complexity_tier", spec.get("settings", {}).get("complexity_tier", "teaching")))
	var prog := int(spec.get("source", {}).get("progression_stage", spec.get("settings", {}).get("progression_stage", 99)))
	var roster = spec.get("source", {}).get("roster", spec.get("settings", {}).get("roster", []))
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	var branches: Array = navigation_grid.get("branches", [])
	return analyze(nodes, tier, prog, roster, branches, navigation_grid)


## `roster` is the set of ENABLED characters (the enable/disable options). The spotlight
## loadout is built from it, so disabling the combat character makes a combat-only node fall
## to the pair's approach; the shadow (Aster+Peris) path is unaffected and always solves.
static func analyze(
		nodes: Array,
		tier := "teaching",
		progression_stage := 99,
		roster = [],
		branches: Array = [],
		navigation_grid: Dictionary = {}
) -> Dictionary:
	# Only non-optional nodes count toward the multi-solution guarantee: the chunk's golden
	# path (and the playtest) walk the non-optional spine, so an optional detour carrying a
	# choice must not be what proves the stretch is solvable two ways.
	var choice_nodes: Array[String] = []
	for node in nodes:
		if not (node is Dictionary) or bool((node as Dictionary).get("optional", false)):
			continue
		if _presents_choice(node as Dictionary):
			choice_nodes.append(str((node as Dictionary).get("id", "")))

	var branch_validation: Dictionary = BranchWeaverScript.validate_branch_contracts(
		branches, navigation_grid
	)
	var branch_actions := mandatory_branch_actions(branches, nodes, navigation_grid)
	var solution_paths := []
	for loadout in CapabilitiesScript.loadouts(roster):
		var path := _solve_loadout(nodes, loadout, progression_stage, roster)
		path["branch_actions"] = branch_actions.duplicate(true)
		path["branch_contract_valid"] = bool(branch_validation.get("valid", false))
		if not bool(branch_validation.get("valid", false)):
			path["solvable"] = false
			path["blocked_branches"] = _mandatory_branch_ids(branches)
		solution_paths.append(path)

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
	var bare_pair_solvable := _bare_pair_solvable(nodes) \
			and bool(branch_validation.get("valid", false))
	var shadow_uses_future := bool(shadow.get("uses_future_technique", false))
	var spotlight_within_stage := bool(spotlight.get("within_stage", true))

	var warnings := []
	if not bool(branch_validation.get("valid", false)):
		warnings.append({
			"severity": "error",
			"code": "invalid_branch_contract",
			"message": "Generated navigation branches are not a truthful solvable contract: %s"
					% str(branch_validation.get("errors", [])),
		})
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
		"branch_contract_valid": bool(branch_validation.get("valid", false)),
		"branch_contract_errors": branch_validation.get("errors", []),
		"branch_actions": branch_actions,
		"mandatory_branch_action_count": branch_actions.size(),
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
		"spotlight_pressure": float(spotlight.get("pressure", 0.0)),
		"shadow_pressure": float(shadow.get("pressure", 0.0)),
		"shadow_combination_premium": float(shadow.get("combination_premium", 0.0)),
		"combination_pressure_gap": float(shadow.get("pressure", 0.0)) - float(spotlight.get("pressure", 0.0)),
		"warnings": warnings,
	}


## Required branch work is part of the solution, not presentation layered on at
## runtime. Each action names the exact producer and downstream blocker cells in
## the persisted woven-grid frame so a replay can interact, wait, and only then
## cross the newly bridged span. Optional reward rooms deliberately emit no action.
static func mandatory_branch_actions(
		branches: Array, nodes: Array = [], navigation_grid: Dictionary = {}
) -> Array:
	var actions: Array = []
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		var branch := branch_v as Dictionary
		if str(branch.get("role", "")) != BranchWeaverScript.ROLE_MANDATORY_PRODUCER \
				or not bool(branch.get("required_for_progress", false)):
			continue
		var contract: Dictionary = branch.get("causal_contract", {})
		var branch_id := str(branch.get("id", contract.get("branch_id", "")))
		var producer_cell = contract.get("producer_cell", [])
		var consumer_cell = contract.get("consumer_cell", [])
		var consumer_cells: Array = contract.get("consumer_cells", [])
		# Compatibility for older persisted contracts. New generated specs always
		# carry the proven plural cut and generator validation rejects this fallback.
		if consumer_cells.is_empty() and consumer_cell is Array \
				and (consumer_cell as Array).size() >= 2:
			consumer_cells = [(consumer_cell as Array).duplicate()]
		if branch_id.is_empty() or not (producer_cell is Array) \
				or (producer_cell as Array).size() < 2 \
				or not (consumer_cell is Array) or (consumer_cell as Array).size() < 2 \
				or consumer_cells.is_empty():
			continue
		var before_node := _before_node_for_consumer(
			consumer_cell as Array, nodes, navigation_grid
		)
		var before_nodes := _before_nodes_for_consumer(
			consumer_cell as Array, nodes, navigation_grid
		)
		if before_node != "" and not before_nodes.has(before_node):
			before_nodes.append(before_node)
		var affected_node_ids := _affected_nodes_for_consumer_cut(
			consumer_cells, nodes, navigation_grid
		)
		actions.append({
			"id": "activate_%s_span" % branch_id,
			"action": "activate",
			"target": branch_id,
			"branch_id": branch_id,
			"role": BranchWeaverScript.ROLE_MANDATORY_PRODUCER,
			"kind": "mandatory_branch_interaction",
			"runtime_handler": str(contract.get("runtime_handler", "branch_span_producer")),
			"activation_policy": str(contract.get("activation_policy", "interact_at_producer")),
			"producer_cell": (producer_cell as Array).duplicate(),
			"consumer_cells": consumer_cells.duplicate(true),
			"consumer_cell": (consumer_cell as Array).duplicate(),
			# The canonical golden path skips optional reward nodes, while an opting-in
			# path must cross the same cut to reach them. Keep the legacy singular
			# trigger for golden replays and emit every earliest physical destination
			# that can encounter the cut so neither path arrives at a closed span.
			"before_node": before_node,
			"before_nodes": before_nodes,
			# `before_nodes` is the legacy replay interleave. Runtime actionability
			# consumes this exact graph-derived set instead: apply the emitted cut to
			# the final woven graph, then record every typed interaction region whose
			# own declared predecessor can no longer reach any accepted arrival.
			"affected_node_ids": affected_node_ids,
			"produces_state": str(contract.get("produces_state", "%s_resolved" % branch_id)),
			"expected_phase": str(contract.get("completion_phase", "bridged")),
			"wait_for_completion": bool(contract.get("wait_for_completion", true)),
			"required_for_progress": true,
			"cannot_bypass_unresolved": bool(contract.get("cannot_bypass_unresolved", false)),
		})
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell: Array = a.get("consumer_cell", [2147483647, 0])
		var b_cell: Array = b.get("consumer_cell", [2147483647, 0])
		var a_x := int(a_cell[0]) if not a_cell.is_empty() else 2147483647
		var b_x := int(b_cell[0]) if not b_cell.is_empty() else 2147483647
		if a_x != b_x:
			return a_x < b_x
		return str(a.get("branch_id", "")) < str(b.get("branch_id", ""))
	)
	for index in range(actions.size()):
		(actions[index] as Dictionary)["solution_order"] = index
	return actions


## Determine the semantic destinations physically severed by one mandatory
## consumer cut. This is deliberately evaluated on the final woven GridWorld,
## after actionable nodes have published their exact typed approach regions.
## A node can be optional, absent from the golden path, or spatially non-monotonic;
## none of those presentation facts changes whether its real arrival vertices are
## behind the cut.
static func _affected_nodes_for_consumer_cut(
		consumer_cells: Array, nodes: Array, navigation_grid: Dictionary
	) -> Array[String]:
	var affected: Array[String] = []
	if consumer_cells.is_empty() or navigation_grid.is_empty():
		return affected
	var grid := GridWorld.from_data(navigation_grid)
	if grid == null:
		return affected
	for cell_v in consumer_cells:
		var cell := _consumer_cell_from_data(cell_v)
		if cell == Vector2i(-2147483648, -2147483648):
			continue
		grid.add_dynamic_blocker(cell, "mandatory_branch_coverage")
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var node_id := str(node.get("id", ""))
		var approach_v: Variant = node.get("interaction_approach", null)
		if node_id == "" or not (approach_v is Dictionary):
			continue
		var approach := approach_v as Dictionary
		var required_from := _interaction_vertex_from_data(
			approach.get("required_from_vertex", null))
		var region_v: Variant = approach.get("region_vertices", null)
		if required_from.is_empty() or not (region_v is Array) \
				or (region_v as Array).is_empty():
			continue
		var any_reachable := false
		for vertex_v in region_v as Array:
			var vertex := _interaction_vertex_from_data(vertex_v)
			if not vertex.is_empty() \
					and _interaction_vertices_connected(
						grid, required_from, vertex):
				any_reachable = true
				break
		if not any_reachable:
			affected.append(node_id)
	affected.sort()
	return affected


static func _consumer_cell_from_data(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		var x_v: Variant = (value as Array)[0]
		var z_v: Variant = (value as Array)[1]
		if _integral_number(x_v) and _integral_number(z_v):
			return Vector2i(int(x_v), int(z_v))
	return Vector2i(-2147483648, -2147483648)


static func _interaction_vertex_from_data(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var raw := value as Dictionary
	var cell := _consumer_cell_from_data(raw.get("cell", null))
	if cell == Vector2i(-2147483648, -2147483648) \
			or not _integral_number(raw.get("level", null)):
		return {}
	return {"cell": cell, "level": int(raw.get("level", -1))}


static func _integral_number(value: Variant) -> bool:
	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= -2147483648.0 \
		and number <= 2147483647.0 and number == floorf(number)


static func _interaction_vertices_connected(
		grid: GridWorld, from_vertex: Dictionary, to_vertex: Dictionary
	) -> bool:
	if grid == null or from_vertex.is_empty() or to_vertex.is_empty():
		return false
	var from_cell: Vector2i = from_vertex.get("cell", Vector2i.ZERO)
	var from_level := int(from_vertex.get("level", -1))
	var to_cell: Vector2i = to_vertex.get("cell", Vector2i.ZERO)
	var to_level := int(to_vertex.get("level", -1))
	if from_level < 0 or from_level >= grid.level_count \
			or to_level < 0 or to_level >= grid.level_count \
			or not grid.is_walkable(
				from_cell.x, from_cell.y, {}, {}, from_level) \
			or not grid.is_walkable(to_cell.x, to_cell.y, {}, {}, to_level):
		return false
	return not grid.find_multi_level_plan(
		from_cell, from_level, to_cell, to_level).is_empty()


static func _before_node_for_consumer(
		consumer_cell: Array, nodes: Array, navigation_grid: Dictionary
) -> String:
	var fallback := ""
	var origin: Array = navigation_grid.get("origin", [0.0, 0.0, 0.0])
	var cell_size := float(navigation_grid.get("cell_size", 1.0))
	var consumer_world_x := (
		float(origin[0]) + (float(consumer_cell[0]) + 0.5) * cell_size
	) if consumer_cell.size() >= 2 else INF
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		if bool(node.get("optional", false)):
			continue
		var node_id := str(node.get("id", ""))
		if node_id == "exit_shelter":
			fallback = node_id
		var position: Array = node.get("position", [])
		if position.size() >= 3 and float(position[0]) + 0.001 >= consumer_world_x:
			return node_id
	return fallback


## A mandatory cut can sit immediately before an optional reward node. The
## golden path bypasses that node, so one singular `before_node` cannot schedule
## the producer for both routes. Emit the first spatial destination past the cut
## plus the first required destination; action consumers de-duplicate after the
## first successful trigger.
static func _before_nodes_for_consumer(
		consumer_cell: Array, nodes: Array, navigation_grid: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	var origin: Array = navigation_grid.get("origin", [0.0, 0.0, 0.0])
	var cell_size := float(navigation_grid.get("cell_size", 1.0))
	var consumer_world_x := (
		float(origin[0]) + (float(consumer_cell[0]) + 0.5) * cell_size
	) if consumer_cell.size() >= 2 else INF
	var first_destination := ""
	var first_required_destination := ""
	var fallback := ""
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var node_id := str(node.get("id", ""))
		if node_id == "exit_shelter":
			fallback = node_id
		var position: Array = node.get("position", [])
		if position.size() < 3 \
				or float(position[0]) + 0.001 < consumer_world_x:
			continue
		if first_destination == "":
			first_destination = node_id
		if not bool(node.get("optional", false)):
			first_required_destination = node_id
			break
	if first_destination != "":
		result.append(first_destination)
	if first_required_destination != "" \
			and not result.has(first_required_destination):
		result.append(first_required_destination)
	elif result.is_empty() and fallback != "":
		result.append(fallback)
	return result


static func _mandatory_branch_ids(branches: Array) -> Array[String]:
	var result: Array[String] = []
	for branch_v in branches:
		if branch_v is Dictionary \
				and str((branch_v as Dictionary).get("role", "")) \
				== BranchWeaverScript.ROLE_MANDATORY_PRODUCER:
			result.append(str((branch_v as Dictionary).get("id", "")))
	return result


## Every node must keep at least one approach the bare Aster+Peris pair can field with NO
## placed tool — a CAPABILITY guarantee that the pair can always finish (the design law).
## The qualifying approach may be a harder, later-stage expert technique; the pair being
## able to do it at all is what matters here, not that it is stage-appropriate.
static func _bare_pair_solvable(nodes: Array) -> bool:
	for node in nodes:
		if not (node is Dictionary):
			continue
		var node_dict := node as Dictionary
		var handler_id := RuntimeRegistryScript.declared_handler(node_dict)
		if handler_id == "":
			continue
		if not bool(node_dict.get(
			"runtime_progression_required", not bool(node_dict.get("optional", false))
		)):
			# Optional interactions may still demand a capability to claim their reward,
			# but declining one can never make the baseline party unsolvable.
			continue
		if (
			not RuntimeRegistryScript.is_implemented(handler_id)
			or RuntimeRegistryScript.handler_approach(handler_id).is_empty()
		):
			return false
	return true


## Resolve one loadout against the node spine — the per-node approach commitments
## that make up a single playable solution path.
static func _solve_loadout(nodes: Array, loadout: Dictionary, progression_stage := 99, roster = []) -> Dictionary:
	var base_caps: Dictionary = loadout.get("base_capabilities", {})
	var enforce_stage := bool(loadout.get("enforce_stage", false))
	var is_pair := str(loadout.get("id", "")) == "shadow"
	# The premium the pair pays at a choice node grows with the campaign stage (clamped so an
	# uncapped stage like 99 doesn't run away). Spotlight gets a small relief there instead.
	var premium_stage := mini(maxi(0, progression_stage), 8)
	var choice_premium := COMBINATION_PREMIUM_BASE + COMBINATION_PREMIUM_PER_STAGE * float(premium_stage)
	var approach_per_node := []
	var blocked: Array[String] = []
	var solvable := true
	var total_risk := 0
	var pressure := 0.0
	var combination_premium := 0.0
	var choice_nodes_taken := 0
	var max_stage_used := 0
	var uses_future := false
	var within_stage := true
	var techniques: Array[String] = []
	for node in nodes:
		if not (node is Dictionary):
			continue
		var node_dict := node as Dictionary
		var node_id := str(node_dict.get("id", ""))
		var handler_id := RuntimeRegistryScript.declared_handler(node_dict)
		var progression_required := bool(node_dict.get(
			"runtime_progression_required",
			handler_id != "" and not bool(node_dict.get("optional", false))
		))
		if handler_id != "" and not progression_required:
			# Keep the real handler on the node for an opting-in player, but serialize
			# the mandatory solution as a pass-through. This prevents deterministic
			# replay from claiming an optional reward interaction it never performed.
			approach_per_node.append({
				"node": node_id,
				"role": str(node_dict.get("role", "")),
				"approach_id": "skip_optional_interaction",
				"kind": "optional_layout_traversal",
				"label": "OPTIONAL %s" % RuntimeRegistryScript.initial_action_label(
					node_dict, handler_id
				),
				"party": "any",
				"requires": [],
				"uses": [],
				"risk": "safe",
				"runtime_handler": "",
				"optional_runtime_handler": handler_id,
				"optional_interaction": true,
				"runtime_progression_required": false,
				"blocked": false,
			})
			continue
		if handler_id == "":
			# Layout-only nodes remain on the traversal path but are not actions and
			# cannot block either loadout.
			approach_per_node.append({
				"node": node_id,
				"role": str(node_dict.get("role", "")),
				"approach_id": "traverse",
				"kind": "layout_traversal",
				"party": "any",
				"requires": [],
				"risk": "safe",
				"runtime_handler": "",
				"blocked": false,
			})
			continue
		var handler_approach := RuntimeRegistryScript.handler_approach(handler_id)
		if RuntimeRegistryScript.is_implemented(handler_id) and not handler_approach.is_empty():
			var handler_record := handler_approach.duplicate(true)
			handler_record["node"] = node_id
			handler_record["role"] = str(node_dict.get("role", ""))
			handler_record["runtime_handler"] = handler_id
			handler_record["requires"] = []
			handler_record["uses"] = []
			handler_record["label"] = RuntimeRegistryScript.initial_action_label(node_dict, handler_id)
			handler_record["min_stage"] = int(node_dict.get("stage", 1))
			handler_record["expert"] = false
			handler_record["stage_ahead"] = false
			handler_record["borrows_from"] = ""
			handler_record["node_pressure"] = 0.0
			handler_record["combination_premium"] = 0.0
			approach_per_node.append(handler_record)
			continue
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
			"runtime_handler": handler_id,
			"blocked": true,
		})
		continue
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
		# Base attrition for this node + the combination premium on a choice node. The pair
		# (shadow) takes the cleaner combined line's place with its own labour, so it pays the
		# stage-scaled premium; the spotlight gets the relief. A non-choice node costs the same
		# either way (no combination to forgo there).
		var node_pressure := PRESSURE_PER_RISK * float(RISK_WEIGHTS.get(risk, 1))
		node_pressure += float(PRESSURE_SURVIVAL.get(str(node_dict.get("survival_kind", "")), 0.0))
		node_pressure += float(int(node_dict.get("pressure_cost", 0)))
		var node_premium := 0.0
		if _presents_choice(node_dict):
			choice_nodes_taken += 1
			if is_pair:
				node_premium = choice_premium
			else:
				node_premium = -COMBINATION_SPOTLIGHT_RELIEF
		combination_premium += node_premium
		pressure += maxf(0.0, node_pressure + node_premium)
		var record := {
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
			"node_pressure": node_pressure,
			"combination_premium": node_premium,
			"blocked": false,
		}
		approach_per_node.append(record)
	return {
		"loadout": str(loadout.get("id", "")),
		"label": str(loadout.get("label", "")),
		"party": (loadout.get("party", []) as Array).duplicate(),
		"solvable": solvable,
		"blocked_nodes": blocked,
		"approach_per_node": approach_per_node,
		"total_risk": total_risk,
		"pressure": pressure,
		"combination_premium": combination_premium,
		"choice_nodes_taken": choice_nodes_taken,
		"max_stage_used": max_stage_used,
		"uses_future_technique": uses_future,
		"within_stage": within_stage,
		"techniques": techniques,
	}


## A node presents a genuine choice when it offers both a specialist primary approach
## and an Aster+Peris shadow approach — the two ways a thinking player can take it.
static func _presents_choice(node: Dictionary) -> bool:
	# None of the current generated-node handlers implements alternate approach
	# lifecycles. Archetype approach prose cannot manufacture a solver choice.
	return false


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
