class_name StretchGenerator
extends RefCounted

const CatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")
const SeededRngScript := preload("res://scripts/system/random/seeded_rng.gd")
const SolverScript := preload("res://scripts/generation/stretch_solution_solver.gd")

const SPEC_SCHEMA := "trawf_generated_stretch_spec_v1"
const DEFAULT_SPEC_DIR := "res://data/generated_stretches"

const TIER_BUDGETS := {
	"teaching": {
		"node_count": 6,
		"optional_node_count": 0,
		"branch_count": 1,
		"archetype_depth": 2,
		"pressure_budget": 1,
		"flora_slots": 2,
		"enemy_slots": 1,
		"structures_slots": 3,
		"shortcut_count": 1,
		"resource_beats": 1,
	},
	"standard": {
		"node_count": 8,
		"optional_node_count": 1,
		"branch_count": 1,
		"archetype_depth": 3,
		"pressure_budget": 2,
		"flora_slots": 3,
		"enemy_slots": 2,
		"structures_slots": 4,
		"shortcut_count": 1,
		"resource_beats": 1,
	},
	"hard": {
		"node_count": 10,
		"optional_node_count": 2,
		"branch_count": 2,
		"archetype_depth": 4,
		"pressure_budget": 3,
		"flora_slots": 4,
		"enemy_slots": 3,
		"structures_slots": 5,
		"shortcut_count": 2,
		"resource_beats": 2,
	},
	"setpiece": {
		"node_count": 12,
		"optional_node_count": 3,
		"branch_count": 3,
		"archetype_depth": 5,
		"pressure_budget": 4,
		"flora_slots": 5,
		"enemy_slots": 4,
		"structures_slots": 6,
		"shortcut_count": 2,
		"resource_beats": 2,
	},
}

const CATEGORY_ALIASES := {
	"flora": "flora",
	"enemy": "enemies",
	"enemies": "enemies",
	"structure": "structures",
	"structures": "structures",
	"archetype": "archetypes",
	"archetypes": "archetypes",
}

## Default campaign position per tier — how far the player is assumed to have progressed.
## The first-play full party may only use techniques taught up to this stage; the
## Aster+Peris shadow (a mastery run) may reach later. Overridable via settings.progression_stage.
const TIER_PROGRESSION_STAGE := {
	"teaching": 2,
	"standard": 3,
	"hard": 4,
	"setpiece": 5,
}

static func generate(settings: Dictionary) -> Dictionary:
	var validation := validate_settings(settings)
	if not bool(validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "validation_failed",
			"validation": validation,
		}

	var catalog = validation.get("catalog")
	var resolved: Dictionary = validation.get("resolved_settings", {})
	var budget: Dictionary = resolved.get("budget", {})
	var rng = SeededRngScript.new(int(resolved.get("seed", 0)))
	# progression_stage is resolved in validate_settings (so it can hard-error an
	# empty stage pool); resolved already carries it.

	var palette_usage := _choose_palette_usage(catalog, resolved, budget, rng)
	var random_walk := _build_archetype_random_walk(catalog, resolved, budget, rng)
	var archetype_chain := _chain_from_random_walk(catalog, random_walk, rng) if _uses_archetype_random_walk(resolved) else _choose_archetype_chain(catalog, resolved, budget, rng)
	var limitations: Dictionary = resolved.get("limitations", {})
	var available_flora := _available_values(catalog, "flora", _category_limitations(limitations, "allowed", "flora"), _category_limitations(limitations, "blocked", "flora"))
	var available_enemies := _available_values(catalog, "enemies", _category_limitations(limitations, "allowed", "enemies"), _category_limitations(limitations, "blocked", "enemies"))
	var available_structures := _available_values(catalog, "structures", _category_limitations(limitations, "allowed", "structures"), _category_limitations(limitations, "blocked", "structures"))
	var nodes := _build_nodes(catalog, resolved, budget, palette_usage, archetype_chain, rng, random_walk, available_flora, available_enemies, available_structures)
	var routes := _build_routes(nodes, budget, rng)
	var graybox := _apply_graybox_layout(nodes, routes, catalog, resolved, budget)
	var navigation_grid := _build_navigation_grid(nodes, routes, resolved, graybox)
	graybox["navigation_contract_id"] = str(navigation_grid.get("contract_id", ""))
	graybox["navigation_node_count"] = nodes.size()
	graybox["navigation_edge_count"] = routes.size()
	var anchors := _build_anchors(nodes)
	var world_slot := _build_world_slot(resolved, anchors)
	var teaching_chain := _teaching_chain_edges(catalog, archetype_chain)
	var composition_summary := _build_composition_summary(resolved.get("composition", {}), archetype_chain, nodes, random_walk)
	composition_summary["teaching_chain"] = teaching_chain
	var warnings := _collect_warnings(catalog, nodes)
	var solution := SolverScript.analyze(nodes, str(resolved.get("complexity_tier", "teaching")), int(resolved.get("progression_stage", 99)), resolved.get("roster", []))

	return {
		"success": true,
		"ok": true,
		"schema": SPEC_SCHEMA,
		"id": str(resolved.get("id", "generated_stretch")),
		"title": str(resolved.get("title", "Generated Stretch")),
		"source": {
			"generator": "archetype_based_stretch_v1",
			"seed": int(resolved.get("seed", 0)),
			"complexity_tier": str(resolved.get("complexity_tier", "teaching")),
			"progression_stage": int(resolved.get("progression_stage", 99)),
			"roster": resolved.get("roster", []),
		},
		"settings": resolved,
		"budget": budget.duplicate(true),
		"world_slot": world_slot,
		"anchors": anchors,
		"graybox": graybox,
		"navigation_grid": navigation_grid,
		"nodes": nodes,
		"routes": routes,
		"archetype_chain": archetype_chain,
		"teaching_chain": teaching_chain,
		"composition": composition_summary,
		"palette_usage": palette_usage,
		"headless": {
			"golden_path": _golden_path(nodes),
			"risky_recovery": _risky_recovery(routes, nodes),
			"solution_paths": solution.get("solution_paths", []),
			"solution_summary": {
				"multi_solution": solution.get("multi_solution", false),
				"choice_node_count": solution.get("choice_node_count", 0),
				"choice_nodes": solution.get("choice_nodes", []),
				"solvable_loadout_count": solution.get("solvable_loadout_count", 0),
				"shadow_solvable": solution.get("shadow_solvable", false),
				"bare_pair_solvable": solution.get("bare_pair_solvable", false),
				"spotlight_within_stage": solution.get("spotlight_within_stage", true),
				"shadow_uses_future_technique": solution.get("shadow_uses_future_technique", false),
				"shadow_techniques": solution.get("shadow_techniques", []),
				"progression_stage": solution.get("progression_stage", int(resolved.get("progression_stage", 99))),
				"distinct_node_count": solution.get("distinct_node_count", 0),
				"distinct_nodes": solution.get("distinct_nodes", []),
				"multi_solution_required": solution.get("multi_solution_required", false),
				"multi_solution_ok": solution.get("multi_solution_ok", true),
				"spotlight_pressure": solution.get("spotlight_pressure", 0.0),
				"shadow_pressure": solution.get("shadow_pressure", 0.0),
				"shadow_combination_premium": solution.get("shadow_combination_premium", 0.0),
				"combination_pressure_gap": solution.get("combination_pressure_gap", 0.0),
				"diagnosis_node_count": solution.get("diagnosis_node_count", 0),
				"diagnosis_nodes": solution.get("diagnosis_nodes", []),
				"diagnosis_penalty": solution.get("diagnosis_penalty", 0.0),
			},
			"state_paths": [
				"chunk.generation.spec_id",
				"chunk.generation.route_choice",
				"chunk.generation.shelter_rested",
				"chunk.generation.shortcut_unlocked",
				"chunk.generation.composition",
				"chunk.generation.composition.random_walk",
				"chunk.generation.unsupported_placeholder_count",
				"chunk.generation.navigation",
				"chunk.generation.active_loadout",
				"chunk.generation.solution_path",
				"chunk.generation.blocked_nodes"
			],
		},
		"validation": {
			"warnings": warnings,
			"solution_warnings": solution.get("warnings", []),
			"multi_solution": solution.get("multi_solution", false),
			"multi_solution_ok": solution.get("multi_solution_ok", true),
			"multi_solution_required": solution.get("multi_solution_required", false),
			"shadow_solvable": solution.get("shadow_solvable", false),
			"bare_pair_solvable": solution.get("bare_pair_solvable", false),
			"spotlight_within_stage": solution.get("spotlight_within_stage", true),
		},
	}

static func validate_settings(settings: Dictionary) -> Dictionary:
	var catalog := CatalogScript.new()
	var catalog_validation: Dictionary = catalog.validate()
	var errors: Array[String] = []
	if not bool(catalog_validation.get("valid", false)):
		errors.append_array(catalog_validation.get("errors", []))

	var resolved := _resolve_settings(settings)
	resolved["progression_stage"] = _resolve_progression_stage(catalog, resolved)
	_apply_stage_depth_scaling(resolved)
	var limitations: Dictionary = resolved.get("limitations", {})
	for mode in ["allowed", "blocked", "required"]:
		var group: Dictionary = limitations.get(mode, {})
		for raw_category in group.keys():
			var category := _canonical_category(str(raw_category))
			if category == "":
				errors.append("Unknown limitation category: %s" % str(raw_category))
				continue
			var values := _string_array(group.get(raw_category, []))
			for value in values:
				if category == "archetypes":
					if not catalog.has_archetype(value):
						errors.append("Unknown archetype in %s: %s" % [mode, value])
				elif not catalog.has_content(category, value):
					errors.append("Unknown %s in %s: %s" % [category, mode, value])

	for category in ["flora", "enemies", "structures", "archetypes"]:
		var allowed := _category_limitations(limitations, "allowed", category)
		var blocked := _category_limitations(limitations, "blocked", category)
		var required := _category_limitations(limitations, "required", category)
		for value in required:
			if blocked.has(value):
				errors.append("%s is both required and blocked in %s" % [value, category])
			if not allowed.is_empty() and not allowed.has(value):
				errors.append("%s is required but not allowed in %s" % [value, category])
		var available := _available_values(catalog, category, allowed, blocked)
		if available.is_empty() and _category_slot_budget(category, resolved.get("budget", {})) > 0:
			errors.append("No available values for %s after limitations" % category)
		if category == "archetypes" and not available.is_empty():
			var prog := int(resolved.get("progression_stage", 99))
			var composition: Dictionary = resolved.get("composition", {})
			var has_seed := not required.is_empty() \
				or not (composition.get("chain", []) as Array).is_empty() \
				or str(composition.get("random_walk", {}).get("start_archetype", "")) != ""
			if not has_seed and int(resolved.get("budget", {}).get("archetype_depth", 0)) > 0 \
					and _filter_archetypes_by_stage(catalog, available, prog).is_empty():
				errors.append("No archetypes available at progression stage %d after the stage filter; raise progression_stage or allow earlier-stage archetypes." % prog)

	_validate_composition(catalog, resolved.get("composition", {}), limitations, resolved.get("budget", {}), errors)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"resolved_settings": resolved,
		"catalog": catalog,
	}


static func build_navigation_grid_from_spec(spec: Dictionary) -> Dictionary:
	var settings: Dictionary = spec.get("settings", {}).duplicate(true)
	if settings.is_empty():
		settings = {"id": str(spec.get("id", "generated_stretch"))}
	return _build_navigation_grid(
		spec.get("nodes", []), spec.get("routes", []), settings, spec.get("graybox", {}))

## The unified-grid traversal layer for a generated stretch — the GridWorld.from_data contract built
## from the SAME semantic nodes/routes the solver reads (the solver and replay artifact never touch
## this). Node footprints + rasterized route corridors become walkable cells; a risky/shortcut route
## lays per-cell risk along its corridor (cautious routing detours, non-recoverable refuses); the
## uniform elevation tiers (surface y = 0.45 + 0.72*index) become stacked grid levels with a "ramp"
## link at each cross-elevation route's midpoint. route_cells (by route_id) gives the runtime chunk
## the cells to lock/unlock as the route-choice state changes. Deterministic: array order + sorted
## cell exports, no RNG.
static func _build_navigation_grid(nodes: Array, routes: Array, settings: Dictionary, graybox: Dictionary) -> Dictionary:
	var cell := 1.0
	var margin := 3.0
	var node_lookup := {}
	var elevation_indices: Array[int] = []
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for node in nodes:
		if not (node is Dictionary):
			continue
		var nd := node as Dictionary
		var nid := str(nd.get("id", ""))
		if nid == "":
			continue
		var pos := _array_to_vec3(nd.get("position", []), Vector3.ZERO)
		var foot := _array_to_vec3(nd.get("footprint", nd.get("floor_size", [])), Vector3(4.0, 0.14, 4.0))
		var elev := maxi(0, int(nd.get("elevation_index", 0)))
		if not elevation_indices.has(elev):
			elevation_indices.append(elev)
		node_lookup[nid] = {"pos": pos, "foot": foot, "elev": elev}
		min_x = minf(min_x, pos.x - foot.x * 0.5)
		max_x = maxf(max_x, pos.x + foot.x * 0.5)
		min_z = minf(min_z, pos.z - foot.z * 0.5)
		max_z = maxf(max_z, pos.z + foot.z * 0.5)
	if node_lookup.is_empty():
		return {}
	for route in routes:
		if not (route is Dictionary):
			continue
		var rd := route as Dictionary
		var mid_v: Variant = rd.get("surface", {}).get("midpoint", [])
		if mid_v is Array and (mid_v as Array).size() >= 3:
			var mid := _array_to_vec3(mid_v, Vector3.ZERO)
			min_x = minf(min_x, mid.x)
			max_x = maxf(max_x, mid.x)
			min_z = minf(min_z, mid.z)
			max_z = maxf(max_z, mid.z)
	min_x -= margin
	min_z -= margin
	max_x += margin
	max_z += margin
	var grid_w := int(ceil((max_x - min_x) / cell)) + 1
	var grid_h := int(ceil((max_z - min_z) / cell)) + 1
	var origin := Vector3(min_x, 0.45, min_z)  # y of elevation tier 0 (the graybox surface)
	elevation_indices.sort()
	var multi: bool = elevation_indices.size() > 1
	var level_count: int = (int(elevation_indices[elevation_indices.size() - 1]) + 1) if multi else 1

	var walk := {}          # Vector2i -> true
	var levels := {}        # level(int) -> {Vector2i: true}
	var risk := {}          # Vector2i -> {penalty, recoverable}  (max penalty wins on overlap)
	var links := []         # [{cell, from, to, type}]
	var route_cells := {}   # route_id -> {cells: [...], kind: String}

	for nid in node_lookup.keys():
		var info: Dictionary = node_lookup[nid]
		var pos: Vector3 = info.pos
		var foot: Vector3 = info.foot
		var a := _ng_cell(origin, cell, pos.x - foot.x * 0.5, pos.z - foot.z * 0.5)
		var b := _ng_cell(origin, cell, pos.x + foot.x * 0.5, pos.z + foot.z * 0.5)
		for cz in range(a.y, b.y + 1):
			for cx in range(a.x, b.x + 1):
				_ng_mark(walk, levels, multi, int(info.elev), Vector2i(cx, cz))

	for route in routes:
		if not (route is Dictionary):
			continue
		var rd := route as Dictionary
		var from_info: Dictionary = node_lookup.get(str(rd.get("from", "")), {})
		var to_info: Dictionary = node_lookup.get(str(rd.get("to", "")), {})
		if from_info.is_empty() or to_info.is_empty():
			continue
		var from_pos: Vector3 = from_info.pos
		var to_pos: Vector3 = to_info.pos
		var midpoint := _array_to_vec3(rd.get("surface", {}).get("midpoint", []), (from_pos + to_pos) * 0.5)
		var half_width: float = maxf(0.7, float(rd.get("width", rd.get("surface", {}).get("width", 1.4))) * 0.5)
		var kind := _route_kind(rd)
		var corridor := {}
		for seg in [[from_pos, midpoint], [midpoint, to_pos]]:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			var seg_len: float = maxf(0.001, Vector2(p1.x - p0.x, p1.z - p0.z).length())
			var steps := int(ceil(seg_len / (cell * 0.35)))
			for s in range(steps + 1):
				var t := float(s) / float(steps)
				var px: float = lerpf(p0.x, p1.x, t)
				var pz: float = lerpf(p0.z, p1.z, t)
				var reach := int(ceil((half_width + cell * 0.45) / cell))
				var center := _ng_cell(origin, cell, px, pz)
				for dz in range(-reach, reach + 1):
					for dx in range(-reach, reach + 1):
						var cc := Vector2i(center.x + dx, center.y + dz)
						var cw_x: float = origin.x + (float(cc.x) + 0.5) * cell
						var cw_z: float = origin.z + (float(cc.y) + 0.5) * cell
						if Vector2(cw_x - px, cw_z - pz).length() <= half_width + cell * 0.45:
							corridor[cc] = true
		var corridor_cells: Array = corridor.keys()
		corridor_cells.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
		var exported: Array = []
		for cc in corridor_cells:
			_ng_mark(walk, levels, multi, int(from_info.elev), cc)
			if int(to_info.elev) != int(from_info.elev):
				_ng_mark(walk, levels, multi, int(to_info.elev), cc)
			exported.append([cc.x, cc.y])
			var pen := _navigation_risk_penalty(kind)
			if pen > 0.0:
				var existing: Dictionary = risk.get(cc, {})
				if existing.is_empty() or float(existing.get("penalty", 0.0)) < pen:
					risk[cc] = {"penalty": pen, "recoverable": bool(rd.get("recoverable", true))}
		var rid := str(rd.get("id", "%s_to_%s" % [str(rd.get("from", "")), str(rd.get("to", ""))]))
		route_cells[rid] = {"cells": exported, "kind": kind}
		if int(to_info.elev) != int(from_info.elev):
			links.append({
				"cell": [_ng_cell(origin, cell, midpoint.x, midpoint.z).x, _ng_cell(origin, cell, midpoint.x, midpoint.z).y],
				"from": int(from_info.elev), "to": int(to_info.elev), "type": "ramp",
			})

	var walk_export: Array = walk.keys()
	walk_export.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var walk_cells: Array = []
	for c in walk_export:
		walk_cells.append([c.x, c.y])
	var level_cells: Array = []
	if multi:
		for lv in range(level_count):
			if not levels.has(lv):
				continue
			var lv_sorted: Array = (levels[lv] as Dictionary).keys()
			lv_sorted.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
			var lv_cells: Array = []
			for c in lv_sorted:
				lv_cells.append([c.x, c.y])
			level_cells.append({"level": lv, "cells": lv_cells})
	var risk_export: Array = risk.keys()
	risk_export.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var risk_list: Array = []
	for c in risk_export:
		risk_list.append({"cell": [c.x, c.y],
			"penalty": float(risk[c].penalty), "recoverable": bool(risk[c].recoverable)})

	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"space_id": str(settings.get("id", "generated_stretch")),
		"supports_multiple_elevations": multi,
		"elevation_indices": elevation_indices,
		"origin": [origin.x, origin.y, origin.z],
		"cell_size": cell,
		"width": grid_w,
		"height": grid_h,
		"walkable_cells": walk_cells,
		"level_cells": level_cells,
		"risk_cell_list": risk_list,
		"links": links,
		"level_count": level_count,
		"level_height": 0.72,
		"route_cells": route_cells,
		"entry_anchor": "entry",
		"exit_anchor": "exit_shelter",
	}

static func _ng_cell(origin: Vector3, cell: float, x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - origin.x) / cell)), int(floor((z - origin.z) / cell)))

static func _ng_mark(walk: Dictionary, levels: Dictionary, multi: bool, elev: int, c: Vector2i) -> void:
	walk[c] = true
	if multi:
		if not levels.has(elev):
			levels[elev] = {}
		levels[elev][c] = true

static func load_spec(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func save_spec(spec: Dictionary, path: String) -> bool:
	if path == "":
		path = "%s/%s.json" % [DEFAULT_SPEC_DIR, _sanitize_id(str(spec.get("id", "generated_stretch")))]
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(spec, "\t"))
	return true

static func _resolve_settings(settings: Dictionary) -> Dictionary:
	var seed := int(settings.get("seed", 1701))
	var tier := str(settings.get("complexity_tier", "teaching")).to_lower()
	if not TIER_BUDGETS.has(tier):
		tier = "teaching"
	var rng = SeededRngScript.new(seed ^ 911)
	var tier_floor: Dictionary = (TIER_BUDGETS[tier] as Dictionary).duplicate(true)
	var base_budget: Dictionary = tier_floor.duplicate(true)
	var override_budget: Dictionary = settings.get("budget", {})
	var overridden_keys := []
	for key in override_budget.keys():
		base_budget[key] = _resolve_budget_value(override_budget[key], int(base_budget.get(key, 0)), rng)
		overridden_keys.append(str(key))
	base_budget["node_count"] = maxi(4, int(base_budget.get("node_count", 6)))
	base_budget["branch_count"] = maxi(0, int(base_budget.get("branch_count", 0)))
	base_budget["archetype_depth"] = maxi(1, int(base_budget.get("archetype_depth", 1)))

	var resolved := settings.duplicate(true)
	resolved["id"] = _sanitize_id(str(resolved.get("id", "generated_stretch_%d" % seed)))
	resolved["title"] = str(resolved.get("title", "Generated Stretch"))
	resolved["seed"] = seed
	resolved["complexity_tier"] = tier
	resolved["budget"] = base_budget
	# Stash the tier floor + which budget keys the caller pinned, so the stage-driven depth
	# scaling (applied once the progression stage is known) can grow the auto keys above the
	# floor while leaving an explicit override exactly as authored.
	resolved["budget_tier_floor"] = tier_floor
	resolved["budget_overridden_keys"] = overridden_keys
	resolved["limitations"] = _normalize_limitations(settings.get("limitations", {}))
	resolved["composition"] = _normalize_composition(settings.get("composition", {}))
	resolved["roster"] = settings.get("roster", [])
	var resolved_composition: Dictionary = resolved.get("composition", {})
	if _composition_mode_uses_random_walk(str(resolved_composition.get("mode", ""))):
		var walk_settings: Dictionary = resolved_composition.get("random_walk", {})
		var walk_steps := int(walk_settings.get("step_count", 0))
		if walk_steps > 0:
			base_budget["node_count"] = maxi(int(base_budget.get("node_count", 6)), walk_steps + 2)
			resolved["budget"] = base_budget
	if not resolved.has("world_slot") or not (resolved.get("world_slot") is Dictionary):
		resolved["world_slot"] = {}
	return resolved

static func _resolve_budget_value(value: Variant, fallback: int, rng) -> int:
	if value is Array and (value as Array).size() >= 2:
		var a := int((value as Array)[0])
		var b := int((value as Array)[1])
		return int(rng.call("randi_range", mini(a, b), maxi(a, b)))
	if value is float or value is int:
		return int(value)
	return fallback

static func _normalize_limitations(raw: Variant) -> Dictionary:
	var result := {
		"allowed": {"flora": [], "enemies": [], "structures": [], "archetypes": []},
		"blocked": {"flora": [], "enemies": [], "structures": [], "archetypes": []},
		"required": {"flora": [], "enemies": [], "structures": [], "archetypes": []},
	}
	if not (raw is Dictionary):
		return result
	for mode in ["allowed", "blocked", "required"]:
		var group: Dictionary = (raw as Dictionary).get(mode, {})
		if not (group is Dictionary):
			continue
		for raw_category in group.keys():
			var category := _canonical_category(str(raw_category))
			if category == "":
				continue
			result[mode][category] = _string_array(group.get(raw_category, []))
	return result

static func _normalize_composition(raw: Variant) -> Dictionary:
	var result := {
		"mode": "",
		"chain": [],
		"nested": [],
		"random_walk": {},
		"shadow_solution": {},
	}
	if not (raw is Dictionary):
		return result

	var raw_dict := raw as Dictionary
	result["mode"] = str(raw_dict.get("mode", "")).strip_edges().to_lower()
	if raw_dict.get("shadow_solution", {}) is Dictionary:
		result["shadow_solution"] = (raw_dict.get("shadow_solution", {}) as Dictionary).duplicate(true)

	var chain := []
	var raw_chain: Variant = raw_dict.get("chain", [])
	if raw_chain is Array:
		var chain_index := 0
		for raw_link in raw_chain:
			var link := _normalize_composition_link(raw_link, "chain_%02d" % chain_index, "chain")
			if not link.is_empty():
				link["chain_index"] = chain_index
				chain.append(link)
				chain_index += 1
	result["chain"] = chain

	var nested := []
	_append_nested_composition_entries(nested, raw_dict.get("nested", []), "", "", 1)
	result["nested"] = nested
	result["random_walk"] = _normalize_random_walk(raw_dict.get("random_walk", raw_dict.get("walk", {})))
	return result

static func _normalize_random_walk(raw: Variant) -> Dictionary:
	var result := {
		"start_archetype": "",
		"start_step": 0,
		"step_count": 0,
		"transition_chance": 0.35,
		"prefer_tags": [],
		"allow_revisit": true,
	}
	if not (raw is Dictionary):
		return result
	var raw_dict := raw as Dictionary
	result["start_archetype"] = str(raw_dict.get("start_archetype", raw_dict.get("start", ""))).strip_edges()
	result["start_step"] = maxi(0, int(raw_dict.get("start_step", 0)))
	result["step_count"] = maxi(0, int(raw_dict.get("step_count", raw_dict.get("steps", 0))))
	result["transition_chance"] = clampf(float(raw_dict.get("transition_chance", 0.35)), 0.0, 1.0)
	result["prefer_tags"] = _string_array(raw_dict.get("prefer_tags", []))
	result["allow_revisit"] = bool(raw_dict.get("allow_revisit", true))
	return result

static func _normalize_composition_link(raw: Variant, fallback_ref: String, role: String) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var entry := raw as Dictionary
	var id := str(entry.get("id", "")).strip_edges()
	if id == "":
		return {}
	var normalized := {
		"ref": str(entry.get("ref", fallback_ref)),
		"id": id,
		"variant": str(entry.get("variant", "")).strip_edges(),
		"label": str(entry.get("label", "")).strip_edges(),
		"input": str(entry.get("input", "")).strip_edges(),
		"output": str(entry.get("output", "")).strip_edges(),
		"role": role,
	}
	if entry.has("host") or entry.has("host_id"):
		normalized["host_id"] = str(entry.get("host_id", entry.get("host", ""))).strip_edges()
	if entry.has("host_step"):
		normalized["host_step"] = int(entry.get("host_step", 0))
	return normalized

static func _append_nested_composition_entries(result: Array, raw_entries: Variant, default_host: String, parent_ref: String, depth: int) -> void:
	if not (raw_entries is Array):
		return
	var local_index := 0
	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			continue
		var entry_dict := raw_entry as Dictionary
		var fallback_ref := "nested_%02d" % result.size() if parent_ref == "" else "%s_%02d" % [parent_ref, local_index]
		var nested := _normalize_composition_link(raw_entry, fallback_ref, "nested")
		if nested.is_empty():
			continue
		var host_id := str(entry_dict.get("host_id", entry_dict.get("host", default_host))).strip_edges()
		nested["host_id"] = host_id
		nested["parent_ref"] = parent_ref
		nested["depth"] = depth
		result.append(nested)
		_append_nested_composition_entries(result, entry_dict.get("nested", []), str(nested.get("id", "")), str(nested.get("ref", "")), depth + 1)
		local_index += 1

static func _validate_composition(catalog, composition: Dictionary, limitations: Dictionary, budget: Dictionary, errors: Array[String]) -> void:
	var allowed := _category_limitations(limitations, "allowed", "archetypes")
	var blocked := _category_limitations(limitations, "blocked", "archetypes")
	for entry in composition.get("chain", []):
		_validate_composition_entry(catalog, entry, allowed, blocked, "composition chain", errors)
	for entry in composition.get("nested", []):
		_validate_composition_entry(catalog, entry, allowed, blocked, "nested composition", errors)
		if entry is Dictionary:
			var host_id := str((entry as Dictionary).get("host_id", "")).strip_edges()
			if host_id != "" and not catalog.has_archetype(host_id):
				errors.append("Unknown nested host archetype: %s" % host_id)
	if _composition_mode_uses_random_walk(str(composition.get("mode", ""))):
		var walk: Dictionary = composition.get("random_walk", {})
		var start_id := str(walk.get("start_archetype", ""))
		if start_id != "" and not catalog.has_archetype(start_id):
			errors.append("Unknown random-walk start archetype: %s" % start_id)
		if start_id != "" and blocked.has(start_id):
			errors.append("Random-walk start archetype %s is blocked" % start_id)
		if start_id != "" and not allowed.is_empty() and not allowed.has(start_id):
			errors.append("Random-walk start archetype %s is outside allowed set" % start_id)
		var required := _category_limitations(limitations, "required", "archetypes")
		var walk_steps := int(walk.get("step_count", 0))
		if walk_steps <= 0:
			walk_steps = maxi(1, int(budget.get("node_count", 6)) - 2)
		if required.size() > walk_steps:
			errors.append("Random-walk step count %d cannot cover %d required archetypes" % [walk_steps, required.size()])

static func _validate_composition_entry(catalog, entry: Variant, allowed: Array, blocked: Array, context: String, errors: Array[String]) -> void:
	if not (entry is Dictionary):
		return
	var entry_dict := entry as Dictionary
	var id := str(entry_dict.get("id", "")).strip_edges()
	if id == "":
		return
	if not catalog.has_archetype(id):
		errors.append("Unknown archetype in %s: %s" % [context, id])
		return
	if blocked.has(id):
		errors.append("%s uses blocked archetype %s" % [context, id])
	if not allowed.is_empty() and not allowed.has(id):
		errors.append("%s uses archetype %s outside allowed set" % [context, id])
	var variant := str(entry_dict.get("variant", "")).strip_edges()
	if variant == "":
		return
	var archetype: Dictionary = catalog.get_archetype(id)
	var variants: Array = archetype.get("variants", [])
	if not variants.has(variant):
		errors.append("Unknown variant %s for archetype %s in %s" % [variant, id, context])

static func _uses_archetype_random_walk(settings: Dictionary) -> bool:
	return _composition_mode_uses_random_walk(str(settings.get("composition", {}).get("mode", "")))

static func _composition_mode_uses_random_walk(mode: String) -> bool:
	return mode in ["archetype_random_walk", "random_walk", "element_random_walk"]

static func _choose_palette_usage(catalog, settings: Dictionary, budget: Dictionary, rng) -> Dictionary:
	var limitations: Dictionary = settings.get("limitations", {})
	return {
		"flora": _choose_values(catalog, "flora", _category_slot_budget("flora", budget), limitations, rng),
		"enemies": _choose_values(catalog, "enemies", _category_slot_budget("enemies", budget), limitations, rng),
		"structures": _choose_values(catalog, "structures", _category_slot_budget("structures", budget), limitations, rng),
	}

## A stretch sits at least as late as the latest archetype it is forced to contain, so
## the first-play full party always has an in-stage primary approach for every spine node.
static func _resolve_progression_stage(catalog, resolved: Dictionary) -> int:
	var tier := str(resolved.get("complexity_tier", "teaching"))
	var stage := int(resolved.get("progression_stage", int(TIER_PROGRESSION_STAGE.get(tier, 2))))
	var limitations: Dictionary = resolved.get("limitations", {})
	for id in _category_limitations(limitations, "required", "archetypes"):
		stage = maxi(stage, _archetype_stage(catalog, str(id)))
	var composition: Dictionary = resolved.get("composition", {})
	for link in composition.get("chain", []):
		if link is Dictionary:
			stage = maxi(stage, _archetype_stage(catalog, str((link as Dictionary).get("id", ""))))
	for entry in composition.get("nested", []):
		if entry is Dictionary:
			stage = maxi(stage, _archetype_stage(catalog, str((entry as Dictionary).get("id", ""))))
	stage = maxi(stage, _archetype_stage(catalog, str(composition.get("random_walk", {}).get("start_archetype", ""))))
	return stage

static func _archetype_stage(catalog, id: String) -> int:
	if id == "" or not catalog.has_archetype(id):
		return 0
	return int(catalog.get_archetype(id).get("stage", 1))

## Per-stage growth ABOVE the tier each scalable budget key gains for every progression
## stage past the tier's natural stage, and the bound it may not exceed. The tier stays the
## base/floor; a late-stage stretch is genuinely bigger and deeper (more nodes, a longer
## archetype chain, an extra branch), not just a wider archetype pool.
const STAGE_DEPTH_SCALING := {
	"node_count": {"per_stage": 1.0, "max": 16},
	"archetype_depth": {"per_stage": 0.6, "max": 7},
	"branch_count": {"per_stage": 0.34, "max": 4},
}

## Grow the auto (non-overridden) scalable budget keys with the resolved progression stage,
## measured from the tier's natural stage so the tier remains the floor and an explicitly
## pinned key is never touched. Runs once after the stage is resolved; deterministic.
static func _apply_stage_depth_scaling(resolved: Dictionary) -> void:
	var budget: Dictionary = resolved.get("budget", {})
	var floor_budget: Dictionary = resolved.get("budget_tier_floor", budget)
	var overridden := _string_array(resolved.get("budget_overridden_keys", []))
	var tier := str(resolved.get("complexity_tier", "teaching"))
	var natural_stage := int(TIER_PROGRESSION_STAGE.get(tier, 2))
	var stage := int(resolved.get("progression_stage", natural_stage))
	var steps := maxi(0, stage - natural_stage)
	resolved["stage_depth_steps"] = steps
	if steps <= 0:
		return
	for key in STAGE_DEPTH_SCALING.keys():
		if overridden.has(str(key)):
			continue
		var spec: Dictionary = STAGE_DEPTH_SCALING[key]
		var floor_value := int(floor_budget.get(key, budget.get(key, 0)))
		var grown := floor_value + int(floor(float(steps) * float(spec.get("per_stage", 0.0))))
		grown = mini(grown, int(spec.get("max", grown)))
		budget[key] = maxi(int(budget.get(key, floor_value)), grown)
	# Keep the random-walk floor the composition expects (node_count >= step_count + 2).
	var composition: Dictionary = resolved.get("composition", {})
	if _composition_mode_uses_random_walk(str(composition.get("mode", ""))):
		var walk_steps := int(composition.get("random_walk", {}).get("step_count", 0))
		if walk_steps > 0:
			budget["node_count"] = maxi(int(budget.get("node_count", 6)), walk_steps + 2)
	resolved["budget"] = budget

static func _filter_archetypes_by_stage(catalog, ids: Array, max_stage: int) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		if _archetype_stage(catalog, str(id)) <= max_stage:
			result.append(str(id))
	return result

static func _choose_archetype_chain(catalog, settings: Dictionary, budget: Dictionary, rng) -> Array:
	var limitations: Dictionary = settings.get("limitations", {})
	var required := _category_limitations(limitations, "required", "archetypes")
	var allowed := _category_limitations(limitations, "allowed", "archetypes")
	var blocked := _category_limitations(limitations, "blocked", "archetypes")
	var available := _filter_archetypes_by_stage(catalog, _available_values(catalog, "archetypes", allowed, blocked), int(settings.get("progression_stage", 99)))
	var composition: Dictionary = settings.get("composition", {})
	var composition_chain: Array = composition.get("chain", [])
	var target_count := maxi(required.size(), maxi(composition_chain.size(), int(budget.get("archetype_depth", 2))))
	var ids: Array[String] = []

	var chain := []
	for raw_link in composition_chain:
		if not (raw_link is Dictionary):
			continue
		var link := raw_link as Dictionary
		var id := str(link.get("id", ""))
		if id == "" or blocked.has(id) or (not allowed.is_empty() and not allowed.has(id)):
			continue
		chain.append(_archetype_chain_entry(catalog, id, rng, str(link.get("variant", "")), {
			"composition_role": "chain_link",
			"composition_mode": str(composition.get("mode", "")),
			"chain_index": int(link.get("chain_index", chain.size())),
			"chain_input": str(link.get("input", "")),
			"chain_output": str(link.get("output", "")),
			"chain_label": str(link.get("label", "")),
			"link_ref": str(link.get("ref", "")),
		}))
		if not ids.has(id):
			ids.append(id)

	for value in required:
		if not ids.has(value):
			ids.append(value)
	while ids.size() < target_count and not available.is_empty():
		var picked := str(rng.pick(available))
		available.erase(picked)
		if not ids.has(picked):
			ids.append(picked)

	for i in range(ids.size()):
		var id := ids[i]
		var already_added := false
		for existing in chain:
			if existing is Dictionary and str((existing as Dictionary).get("id", "")) == id:
				already_added = true
				break
		if already_added:
			continue
		chain.append(_archetype_chain_entry(catalog, id, rng, "", {
			"composition_role": "required_append" if required.has(id) else "generated_fill",
			"chain_index": chain.size(),
		}))
	return _order_chain_by_teaching(catalog, chain)

## Reorder a chain so an archetype that TEACHES a technique sits before an archetype whose
## expert approach USES it (its `borrows_from`), so the stretch introduces a technique before
## it is leaned on. Cycle-tolerant: a Kahn pass with a deterministic tie-break (original
## order), falling back to original order when a borrow cycle leaves nothing unblocked, so it
## never drops or duplicates a node. chain_index is renumbered to the new play order.
static func _order_chain_by_teaching(catalog, chain: Array) -> Array:
	if chain.size() < 2:
		return chain
	var present := {}
	for i in range(chain.size()):
		if chain[i] is Dictionary:
			present[str((chain[i] as Dictionary).get("id", ""))] = i
	# prereqs[id] = the archetypes (present in this chain) this id borrows a technique from.
	var prereqs := {}
	for i in range(chain.size()):
		if not (chain[i] is Dictionary):
			continue
		var id := str((chain[i] as Dictionary).get("id", ""))
		var needs := {}
		for src in _archetype_borrows_from(catalog, id):
			if present.has(src) and src != id:
				needs[src] = true
		prereqs[id] = needs
	var ordered := []
	var placed := {}
	while ordered.size() < chain.size():
		var picked_index := -1
		for i in range(chain.size()):
			if not (chain[i] is Dictionary) or placed.has(i):
				continue
			var id := str((chain[i] as Dictionary).get("id", ""))
			var ready := true
			for src in (prereqs.get(id, {}) as Dictionary).keys():
				var src_index := int(present.get(src, -1))
				if src_index >= 0 and not placed.has(src_index):
					ready = false
					break
			if ready:
				picked_index = i
				break
		if picked_index < 0:
			# A borrow cycle blocks every remaining node — break it by original order.
			for i in range(chain.size()):
				if chain[i] is Dictionary and not placed.has(i):
					picked_index = i
					break
		if picked_index < 0:
			break
		placed[picked_index] = true
		ordered.append(chain[picked_index])
	for i in range(ordered.size()):
		if ordered[i] is Dictionary:
			(ordered[i] as Dictionary)["chain_index"] = i
	return ordered

## The archetype ids whose techniques an archetype's approaches borrow (the `borrows_from`
## links) — the teaching prerequisites of that archetype.
static func _archetype_borrows_from(catalog, id: String) -> Array:
	var result := []
	if id == "" or not catalog.has_archetype(id):
		return result
	for approach in catalog.get_archetype(id).get("approaches", []):
		if not (approach is Dictionary):
			continue
		var src := str((approach as Dictionary).get("borrows_from", "")).strip_edges()
		if src != "" and not result.has(src):
			result.append(src)
	return result

## The teaching-dependency edges present in a built chain: each {from, to, technique} says
## the `from` archetype teaches a technique the `to` archetype's expert approach uses, and
## (after _order_chain_by_teaching) `from` precedes `to` whenever the order is acyclic. Emitted
## on the spec so the chunk/UI can show the prerequisite before the payoff.
static func _teaching_chain_edges(catalog, chain: Array) -> Array:
	var index_of := {}
	for i in range(chain.size()):
		if chain[i] is Dictionary:
			index_of[str((chain[i] as Dictionary).get("id", ""))] = i
	var edges := []
	for i in range(chain.size()):
		if not (chain[i] is Dictionary):
			continue
		var id := str((chain[i] as Dictionary).get("id", ""))
		for approach in catalog.get_archetype(id).get("approaches", []):
			if not (approach is Dictionary):
				continue
			var src := str((approach as Dictionary).get("borrows_from", "")).strip_edges()
			if src == "" or not index_of.has(src) or src == id:
				continue
			edges.append({
				"from": src,
				"to": id,
				"technique": str((approach as Dictionary).get("taught_by", "")),
				"approach": str((approach as Dictionary).get("id", "")),
				"from_index": int(index_of.get(src, -1)),
				"to_index": int(index_of.get(id, -1)),
				"ordered": int(index_of.get(src, -1)) < int(index_of.get(id, -1)),
			})
	return edges

static func _archetype_chain_entry(catalog, id: String, rng, variant_override := "", extras := {}) -> Dictionary:
	var entry: Dictionary = catalog.get_archetype(id)
	var variants: Array = entry.get("variants", [])
	var variant := variant_override
	if variant == "" and not variants.is_empty():
		variant = str(rng.pick(variants))
	var result := {
		"id": id,
		"name": str(entry.get("name", "Archetype %s" % id)),
		"kind": str(entry.get("kind", "")),
		"variant": variant,
		"tags": entry.get("tags", []),
		"step_count": (entry.get("steps", []) as Array).size() if entry.get("steps", []) is Array else 0,
		"shadow_solution": entry.get("shadow_solution", {}),
		"approaches": entry.get("approaches", []),
		"compatible_node_roles": entry.get("compatible_node_roles", []),
		"all_variants": entry.get("variants", []),
		"stage": int(entry.get("stage", 1)),
		"survival_kind": str(entry.get("survival_kind", "")),
		"atp_reward": int(entry.get("atp_reward", 0)),
		"pressure_cost": int(entry.get("pressure_cost", 0)),
		"exploit_target": str(entry.get("exploit_target", "")),
		"solve": str(entry.get("solve", "")),
		"reads": entry.get("reads", []),
		"correct_read": str(entry.get("correct_read", "")),
	}
	if extras is Dictionary:
		for key in (extras as Dictionary).keys():
			result[key] = (extras as Dictionary)[key]
	return result

static func _build_archetype_random_walk(catalog, settings: Dictionary, budget: Dictionary, rng) -> Dictionary:
	var composition: Dictionary = settings.get("composition", {})
	if not _composition_mode_uses_random_walk(str(composition.get("mode", ""))):
		return {}
	var walk_settings: Dictionary = composition.get("random_walk", {})
	var limitations: Dictionary = settings.get("limitations", {})
	var allowed := _category_limitations(limitations, "allowed", "archetypes")
	var blocked := _category_limitations(limitations, "blocked", "archetypes")
	var required := _category_limitations(limitations, "required", "archetypes")
	var available := _filter_archetypes_by_stage(catalog, _available_values(catalog, "archetypes", allowed, blocked), int(settings.get("progression_stage", 99)))
	if available.is_empty():
		return {}
	var target_steps := int(walk_settings.get("step_count", 0))
	if target_steps <= 0:
		target_steps = maxi(1, int(budget.get("node_count", 6)) - 2)
	target_steps = maxi(1, target_steps)

	var current_id := str(walk_settings.get("start_archetype", ""))
	if current_id == "" or not available.has(current_id):
		current_id = str(required[0]) if not required.is_empty() and available.has(str(required[0])) else str(rng.pick(available))
	var current_step := maxi(0, int(walk_settings.get("start_step", 0)))
	var transition_chance := float(walk_settings.get("transition_chance", 0.35))
	var prefer_tags := _string_array(walk_settings.get("prefer_tags", []))
	var allow_revisit := bool(walk_settings.get("allow_revisit", true))
	var missing_required: Array[String] = []
	for id in required:
		if not missing_required.has(id):
			missing_required.append(id)

	var visits := []
	var edges := []
	var layout := []
	var lane := 0
	for walk_index in range(target_steps):
		var entry: Dictionary = catalog.get_archetype(current_id)
		var steps: Array = entry.get("steps", [])
		var step_count := maxi(1, steps.size())
		current_step = clampi(current_step, 0, step_count - 1)
		var step_label := str(steps[current_step]) if current_step < steps.size() else "resolve element"
		var variant := _variant_for_archetype(entry, rng)
		var turn := int(rng.call("randi_range", -1, 1))
		lane = clampi(lane + turn, -2, 2)
		var position := [float(walk_index + 1) * 12.0, 0.45, float(lane) * 3.2]
		var tags := _string_array(entry.get("tags", []))
		var compatible_roles: Array = entry.get("compatible_node_roles", [])
		var role_hint := _role_hint_for_walk_step(step_label, compatible_roles, walk_index)
		var visit := {
			"ref": "walk_%02d" % walk_index,
			"walk_index": walk_index,
			"id": current_id,
			"archetype_id": current_id,
			"archetype_name": str(entry.get("name", "Archetype %s" % current_id)),
			"kind": str(entry.get("kind", "")),
			"variant": variant,
			"tags": tags,
			"step_index": current_step,
			"step_count": step_count,
			"element": step_label,
			"element_label": step_label,
			"node_role_hint": role_hint,
			"position": position,
			"layout_step": {
				"x": walk_index + 1,
				"lane": lane,
				"turn": turn,
			},
		}
		visits.append(visit)
		layout.append(visit["layout_step"])
		missing_required.erase(current_id)

		var next_id := current_id
		var next_step := current_step + 1
		var reason := "next_step"
		var should_transition := next_step >= step_count
		var remaining_slots := target_steps - walk_index - 1
		if remaining_slots > 0 and missing_required.size() >= remaining_slots:
			should_transition = true
			reason = "required_cover"
		if not should_transition and float(rng.call("randf")) < transition_chance:
			should_transition = true
			reason = "tag_jump"
		if should_transition:
			next_id = _choose_next_walk_archetype(catalog, available, current_id, tags, prefer_tags, missing_required, allow_revisit, rng)
			next_step = 0
			if next_id == current_id:
				reason = "restart"
			elif reason != "tag_jump":
				reason = "step_terminal"
		if walk_index < target_steps - 1:
			edges.append({
				"from": "walk_%02d" % walk_index,
				"to": "walk_%02d" % (walk_index + 1),
				"from_archetype": current_id,
				"to_archetype": next_id,
				"from_step": current_step,
				"to_step": next_step,
				"reason": reason,
			})
			visit["next_archetype_id"] = next_id
			visit["next_step_index"] = next_step
			visit["transition_reason"] = reason
		current_id = next_id
		current_step = next_step

	var exit_lane := lane + int(rng.call("randi_range", -1, 1))
	exit_lane = clampi(exit_lane, -2, 2)
	return {
		"enabled": true,
		"mode": str(composition.get("mode", "")),
		"seed": int(settings.get("seed", 0)),
		"settings": walk_settings.duplicate(true),
		"visits": visits,
		"edges": edges,
		"layout": layout,
		"entry_position": [0.0, 0.45, 0.0],
		"exit_position": [float(target_steps + 1) * 12.0, 0.45, float(exit_lane) * 3.2],
		"element_count": visits.size(),
		"visited_archetypes": _visited_archetypes(visits),
	}

static func _chain_from_random_walk(catalog, random_walk: Dictionary, rng) -> Array:
	var chain := []
	for visit in random_walk.get("visits", []):
		if not (visit is Dictionary):
			continue
		var walk_entry := visit as Dictionary
		var id := str(walk_entry.get("archetype_id", walk_entry.get("id", "")))
		chain.append(_archetype_chain_entry(catalog, id, rng, str(walk_entry.get("variant", "")), {
			"composition_role": "random_walk_element",
			"composition_mode": str(random_walk.get("mode", "archetype_random_walk")),
			"chain_index": int(walk_entry.get("walk_index", chain.size())),
			"chain_label": str(walk_entry.get("element", "")),
			"link_ref": str(walk_entry.get("ref", "")),
			"walk_ref": str(walk_entry.get("ref", "")),
			"walk_index": int(walk_entry.get("walk_index", chain.size())),
			"walk_step_index": int(walk_entry.get("step_index", 0)),
			"walk_element": str(walk_entry.get("element", "")),
		}))
	return chain

static func _variant_for_archetype(entry: Dictionary, rng) -> String:
	var variants: Array = entry.get("variants", [])
	return str(rng.pick(variants)) if not variants.is_empty() else ""

static func _choose_next_walk_archetype(
	catalog,
	available: Array,
	current_id: String,
	current_tags: Array,
	prefer_tags: Array,
	missing_required: Array,
	allow_revisit: bool,
	rng
) -> String:
	for id in missing_required:
		if available.has(id):
			return str(id)
	var weighted := []
	for raw_id in available:
		var id := str(raw_id)
		if not allow_revisit and id == current_id and available.size() > 1:
			continue
		var entry: Dictionary = catalog.get_archetype(id)
		var tags := _string_array(entry.get("tags", []))
		var score := 1 + _tag_overlap(tags, current_tags) + _tag_overlap(tags, prefer_tags)
		for _i in range(score):
			weighted.append(id)
	if weighted.is_empty():
		return current_id
	return str(rng.pick(weighted))

static func _tag_overlap(a: Array, b: Array) -> int:
	var count := 0
	for value in a:
		if b.has(str(value)):
			count += 1
	return count

static func _role_hint_for_walk_step(step_label: String, compatible_roles: Array, walk_index: int) -> String:
	var text := step_label.to_lower()
	if text.contains("patrol") or text.contains("hazard") or text.contains("enemy") or text.contains("dodge"):
		return "danger" if compatible_roles.has("danger") else "route_pressure"
	if text.contains("acquire") or text.contains("retrieve") or text.contains("pick up") or text.contains("resource"):
		return "foraging"
	if text.contains("position") or text.contains("identify") or text.contains("read"):
		return "guidance"
	if text.contains("regroup") or text.contains("deliver"):
		return "regroup"
	if text.contains("use") or text.contains("resolve") or text.contains("assemble"):
		return "mixed"
	if not compatible_roles.is_empty():
		return str(compatible_roles[walk_index % compatible_roles.size()])
	return "mixed"

static func _visited_archetypes(visits: Array) -> Array[String]:
	var ids: Array[String] = []
	for visit in visits:
		if not (visit is Dictionary):
			continue
		var id := str((visit as Dictionary).get("archetype_id", ""))
		if id != "" and not ids.has(id):
			ids.append(id)
	return ids

static func _build_nodes(catalog, settings: Dictionary, budget: Dictionary, palette_usage: Dictionary, archetype_chain: Array, rng, random_walk: Dictionary, available_flora: Array, available_enemies: Array, available_structures: Array) -> Array:
	var node_count := int(budget.get("node_count", 6))
	var optional_count := int(budget.get("optional_node_count", 0))
	var resource_beats := int(budget.get("resource_beats", 1))
	var pressure_budget := int(budget.get("pressure_budget", 1))
	var composition: Dictionary = settings.get("composition", {})
	var walk_visits: Array = random_walk.get("visits", [])
	var occurrences := {}
	var nodes := []
	for i in range(node_count):
		var is_interior := i > 0 and i < node_count - 1
		var walk_entry := {}
		if is_interior and not walk_visits.is_empty():
			walk_entry = (walk_visits[mini(i - 1, walk_visits.size() - 1)] as Dictionary).duplicate(true)
		var node_id := "entry" if i == 0 else ("exit_shelter" if i == node_count - 1 else "node_%02d" % i)
		var archetype: Dictionary = archetype_chain[(i - 1) % archetype_chain.size()] if is_interior and not archetype_chain.is_empty() else {}
		var archetype_id := str(archetype.get("id", "11" if i == 0 or i == node_count - 1 else ""))
		# Vary the variant across repeated occurrences of the same archetype so a cycled
		# chain doesn't read as the same beat twice — flora, actors and label follow it.
		if is_interior and not archetype.is_empty():
			var all_variants: Array = archetype.get("all_variants", archetype.get("variants", []))
			if not all_variants.is_empty():
				var occ := int(occurrences.get(archetype_id, 0))
				occurrences[archetype_id] = occ + 1
				archetype = archetype.duplicate(true)
				archetype["variant"] = str(all_variants[occ % all_variants.size()])
		# Role is the archetype's identity, not a blind cycle — so a forage beat reads as
		# foraging, a redirect as danger, never "Guidance Beat" stamped on a plant puzzle.
		var role := "boundary" if i == 0 else ("shelter_arrival" if i == node_count - 1 else "")
		if role == "":
			role = str(walk_entry.get("node_role_hint", "")) if not walk_entry.is_empty() else ""
			if role == "":
				role = _role_for_archetype(archetype, i - 1)
		var optional := is_interior and optional_count > 0 and (i % 3 == 0)
		if optional:
			optional_count -= 1
		var position := [float(i) * 12.0, 0.45, float(((i % 3) - 1) * 3)]
		if i == 0 and random_walk.has("entry_position"):
			position = random_walk.get("entry_position", position)
		elif i == node_count - 1 and random_walk.has("exit_position"):
			position = random_walk.get("exit_position", position)
		elif not walk_entry.is_empty() and walk_entry.has("position"):
			position = walk_entry.get("position", position)
		# Content + structure are the archetype's required props and ACTORS (a redirect gets a
		# charger, an exploit gets prey + a predator, a forage gets food), not a generic slice.
		var flora := _flora_for_node(catalog, archetype, available_flora, rng) if is_interior else _slice_usage(available_flora, i, 1)
		# The archetype's REQUIRED actors are part of its fiction (a redirect needs a charger,
		# an exploit needs prey + a predator). The tier's pressure_budget caps how dense a
		# SCALABLE threat (a gauntlet's enforcement line) may get, so lighter tiers stay sparser
		# — with a floor of 2 that keeps every node's structurally-required pair intact.
		var enemy_cap := clampi(pressure_budget, 2, 3)
		var enemies := _enemies_for_node(catalog, archetype, available_enemies, enemy_cap, rng) if is_interior else []
		var structures := _structure_for_node(archetype, role, available_structures)
		var is_resource := resource_beats > 0 and role in ["foraging", "regroup"]
		var nested_archetypes := _nested_for_archetype(archetype_id, composition)
		var label := _node_label(archetype, role, i)
		var node := {
			"id": node_id,
			"role": role,
			"label": label,
			"title": label,
			"position": position,
			"optional": optional,
			"archetype_id": archetype_id,
			"archetype_name": str(archetype.get("name", "Narrative beat" if role in ["boundary", "shelter_arrival"] else "")),
			"variant": str(archetype.get("variant", "")),
			"composition_role": str(archetype.get("composition_role", "")),
			"chain_index": int(archetype.get("chain_index", -1)),
			"chain_input": str(archetype.get("chain_input", "")),
			"chain_output": str(archetype.get("chain_output", "")),
			"chain_label": str(archetype.get("chain_label", "")),
			"link_ref": str(archetype.get("link_ref", "")),
			"walk_ref": str(archetype.get("walk_ref", walk_entry.get("ref", ""))),
			"walk_index": int(archetype.get("walk_index", walk_entry.get("walk_index", -1))),
			"walk_step_index": int(archetype.get("walk_step_index", walk_entry.get("step_index", -1))),
			"walk_element": str(archetype.get("walk_element", walk_entry.get("element", ""))),
			"walk_transition": str(walk_entry.get("transition_reason", "")),
			"layout_step": walk_entry.get("layout_step", {}),
			"nested_archetypes": nested_archetypes,
			"nested_depth": _max_nested_depth(nested_archetypes),
			"flora": flora,
			"enemies": enemies,
			"structures": structures,
			"resource_beat": is_resource,
			"resource": is_resource,
			"shortcut": role == "shortcut" or structures.has("shortcut_gate"),
			"pressure": 1 if not enemies.is_empty() else 0,
			"shadow_solution": archetype.get("shadow_solution", composition.get("shadow_solution", {})),
			"approaches": archetype.get("approaches", []),
			"stage": int(archetype.get("stage", 1)),
			"survival_kind": str(archetype.get("survival_kind", "")),
			"atp_reward": int(archetype.get("atp_reward", 0)),
			"pressure_cost": int(archetype.get("pressure_cost", 0)),
			"exploit_target": str(archetype.get("exploit_target", "")),
			"solve": str(archetype.get("solve", "")),
			"reads": (archetype.get("reads", []) as Array).duplicate(true),
			"correct_read": str(archetype.get("correct_read", "")),
		}
		nodes.append(node)
		if resource_beats > 0 and role in ["foraging", "regroup"]:
			resource_beats -= 1
	# Archetype-driven roles no longer force a 'shortcut' node, so guarantee the return
	# ratchet the budget asks for lands on a non-optional beat — the golden run still
	# exposes shortcut state, and the return_shortcut route has a node to anchor to.
	if int(budget.get("shortcut_count", 0)) > 0 and not _any_shortcut(nodes):
		var pick := _designate_shortcut_node(nodes)
		if pick >= 0:
			(nodes[pick] as Dictionary)["shortcut"] = true
			if available_structures.has("shortcut_gate") and not (nodes[pick]["structures"] as Array).has("shortcut_gate"):
				nodes[pick]["structures"] = ["shortcut_gate"]
	return nodes

## A shortcut on an OPTIONAL beat never gets walked by the golden path, so only a
## non-optional shortcut counts as "the run exposes shortcut state".
static func _any_shortcut(nodes: Array) -> bool:
	for n in nodes:
		if n is Dictionary and bool((n as Dictionary).get("shortcut", false)) and not bool((n as Dictionary).get("optional", false)):
			return true
	return false

## The last non-optional interior beat — a sensible place for a return-to-safety ratchet.
static func _designate_shortcut_node(nodes: Array) -> int:
	for i in range(nodes.size() - 2, 0, -1):
		var n: Dictionary = nodes[i]
		if not bool(n.get("optional", false)) and str(n.get("role", "")) not in ["boundary", "shelter_arrival"]:
			return i
	return -1

static func _nested_for_archetype(archetype_id: String, composition: Dictionary) -> Array:
	var nested := []
	if archetype_id == "":
		return nested
	for entry in composition.get("nested", []):
		if not (entry is Dictionary):
			continue
		var nested_entry := entry as Dictionary
		if str(nested_entry.get("host_id", "")) != archetype_id:
			continue
		nested.append(nested_entry.duplicate(true))
	return nested

static func _max_nested_depth(nested_archetypes: Array) -> int:
	var result := 0
	for entry in nested_archetypes:
		if entry is Dictionary:
			result = maxi(result, int((entry as Dictionary).get("depth", 1)))
	return result

static func _build_routes(nodes: Array, budget: Dictionary, rng) -> Array:
	var routes := []
	for i in range(nodes.size() - 1):
		routes.append({
			"id": "main_%02d_%02d" % [i, i + 1],
			"from": (nodes[i] as Dictionary).get("id", ""),
			"to": (nodes[i + 1] as Dictionary).get("id", ""),
			"kind": "safe",
			"risk": "safe",
			"cost": 1,
			"recoverable": true,
		})
	for i in range(1, nodes.size() - 1):
		if not (nodes[i] is Dictionary) or not bool((nodes[i] as Dictionary).get("optional", false)):
			continue
		var previous_index := i - 1
		while previous_index > 0 and nodes[previous_index] is Dictionary and bool((nodes[previous_index] as Dictionary).get("optional", false)):
			previous_index -= 1
		var next_index := i + 1
		while next_index < nodes.size() - 1 and nodes[next_index] is Dictionary and bool((nodes[next_index] as Dictionary).get("optional", false)):
			next_index += 1
		if previous_index >= 0 and next_index < nodes.size():
			routes.append({
				"id": "optional_bypass_%02d_%02d" % [previous_index, next_index],
				"from": (nodes[previous_index] as Dictionary).get("id", ""),
				"to": (nodes[next_index] as Dictionary).get("id", ""),
				"kind": "safe",
				"risk": "safe",
				"cost": 1,
				"recoverable": true,
				"bypasses_optional": str((nodes[i] as Dictionary).get("id", "")),
			})
	if int(budget.get("branch_count", 0)) > 0 and nodes.size() >= 4:
		routes.append({
			"id": "risky_direct",
			"from": "entry",
			"to": "exit_shelter",
			"kind": "risky",
			"risk": "risky",
			"cost": 0,
			"recoverable": true,
			"damage": 18.0 + float(rng.call("randi_range", 0, 8)),
		})
	if int(budget.get("shortcut_count", 0)) > 0 and nodes.size() >= 5:
		routes.append({
			"id": "return_shortcut",
			"from": (nodes[nodes.size() - 2] as Dictionary).get("id", ""),
			"to": "entry",
			"kind": "shortcut",
			"risk": "shortcut",
			"cost": 0,
			"recoverable": true,
			"unlocks_shortcut": true,
		})
	return routes

static func _apply_graybox_layout(nodes: Array, routes: Array, catalog, settings: Dictionary, budget: Dictionary) -> Dictionary:
	var min_point := Vector3(1.0e20, 1.0e20, 1.0e20)
	var max_point := Vector3(-1.0e20, -1.0e20, -1.0e20)
	var has_bounds := false
	var content_placement_count := 0
	var elevation_indices: Array[int] = []
	var route_surface_count := 0

	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var node: Dictionary = nodes[i]
		var role := str(node.get("role", "mixed"))
		var elevation_index := _graybox_elevation_index(node, i, nodes.size())
		if not elevation_indices.has(elevation_index):
			elevation_indices.append(elevation_index)
		var surface_y := _graybox_surface_y(elevation_index)
		var position := _array_to_vec3(node.get("position", [float(i) * 12.0, 0.45, 0.0]), Vector3(float(i) * 12.0, 0.45, 0.0))
		position.y = surface_y
		var footprint := _graybox_node_footprint(role, node)
		var approach := position + _graybox_approach_offset(role, footprint)
		var placements := _build_graybox_content_placements(node, position, footprint, catalog)
		content_placement_count += placements.size()

		node["position"] = _vec3_to_array(position)
		node["elevation_index"] = elevation_index
		node["surface_y"] = surface_y
		node["elevation_meters"] = surface_y - 0.45
		node["footprint"] = _vec3_to_array(footprint)
		node["floor_size"] = _vec3_to_array(footprint)
		node["approach_position"] = _vec3_to_array(approach)
		node["content_placements"] = placements
		nodes[i] = node

		var half := footprint * 0.5 + Vector3(1.0, 0.0, 1.0)
		var node_min := position - half
		var node_max := position + half + Vector3(0.0, 3.2, 0.0)
		min_point = node_min if not has_bounds else min_point.min(node_min)
		max_point = node_max if not has_bounds else max_point.max(node_max)
		has_bounds = true

	for i in range(routes.size()):
		if not (routes[i] is Dictionary):
			continue
		var route: Dictionary = routes[i]
		var from_node := _find_node_in_list(nodes, str(route.get("from", "")))
		var to_node := _find_node_in_list(nodes, str(route.get("to", "")))
		if from_node.is_empty() or to_node.is_empty():
			continue
		var from_pos := _array_to_vec3(from_node.get("position", []), Vector3.ZERO)
		var to_pos := _array_to_vec3(to_node.get("position", []), Vector3.ZERO)
		var width := _graybox_route_width(route)
		route["width"] = width
		route["height_delta"] = to_pos.y - from_pos.y
		route["surface"] = {
			"from": _vec3_to_array(from_pos),
			"to": _vec3_to_array(to_pos),
			"midpoint": _vec3_to_array((from_pos + to_pos) * 0.5),
			"width": width,
			"supports_click_to_move": true,
			"slope": to_pos.y - from_pos.y,
		}
		routes[i] = route
		route_surface_count += 1

	elevation_indices.sort()
	if not has_bounds:
		min_point = Vector3.ZERO
		max_point = Vector3(20.0, 3.0, 12.0)

	return {
		"contract_id": "generated_stretch_graybox_v1",
		"unit_scale": 1.0,
		"surface_y_base": 0.45,
		"elevation_step": 0.72,
		"elevation_indices": elevation_indices,
		"elevation_count": elevation_indices.size(),
		"supports_click_to_move": true,
		"supports_outline_targets": true,
		"supports_multiple_elevations": elevation_indices.size() > 1,
		"node_surface_count": nodes.size(),
		"route_surface_count": route_surface_count,
		"content_placement_count": content_placement_count,
		"bounds": {
			"min": _vec3_to_array(min_point),
			"max": _vec3_to_array(max_point),
			"center": _vec3_to_array((min_point + max_point) * 0.5),
			"size": _vec3_to_array(max_point - min_point),
		},
		"source": {
			"spec_id": str(settings.get("id", "generated_stretch")),
			"complexity_tier": str(settings.get("complexity_tier", "teaching")),
			"node_budget": int(budget.get("node_count", nodes.size())),
		},
	}


static func _graybox_elevation_index(node: Dictionary, index: int, node_count: int) -> int:
	var role := str(node.get("role", "mixed"))
	if index == 0 or index == node_count - 1 or role in ["boundary", "shelter", "shelter_arrival"]:
		return 0
	var layout: Dictionary = node.get("layout_step", {})
	var turn := int(layout.get("turn", (index % 3) - 1))
	var lane := int(layout.get("lane", 0))
	var elevation_index := clampi(1 + turn, 0, 3)
	if role == "setpiece":
		elevation_index += 1
	elif role == "danger" and lane < 0:
		elevation_index -= 1
	elif role == "foraging" and lane == 0:
		elevation_index += 1
	return clampi(elevation_index, 0, 3)

static func _graybox_surface_y(elevation_index: int) -> float:
	return 0.45 + float(maxi(0, elevation_index)) * 0.72

static func _graybox_node_footprint(role: String, node: Dictionary) -> Vector3:
	var optional_padding := 0.4 if bool(node.get("optional", false)) else 0.0
	match role:
		"boundary":
			return Vector3(6.0, 0.16, 4.2)
		"shelter", "shelter_arrival":
			return Vector3(7.2, 0.18, 5.4)
		"foraging":
			return Vector3(5.8 + optional_padding, 0.14, 4.4 + optional_padding)
		"guidance":
			return Vector3(4.8 + optional_padding, 0.14, 4.0 + optional_padding)
		"route_pressure", "danger":
			return Vector3(5.4 + optional_padding, 0.14, 4.8 + optional_padding)
		"shortcut":
			return Vector3(4.8 + optional_padding, 0.14, 4.8 + optional_padding)
		"setpiece":
			return Vector3(6.6 + optional_padding, 0.16, 5.2 + optional_padding)
		_:
			return Vector3(5.2 + optional_padding, 0.14, 4.2 + optional_padding)

static func _graybox_approach_offset(role: String, footprint: Vector3) -> Vector3:
	var z_offset := footprint.z * 0.34
	if role in ["danger", "route_pressure"]:
		return Vector3(-footprint.x * 0.22, 0.0, z_offset)
	if role in ["shelter", "shelter_arrival"]:
		return Vector3(-footprint.x * 0.18, 0.0, z_offset)
	return Vector3(0.0, 0.0, z_offset)

static func _build_graybox_content_placements(node: Dictionary, node_position: Vector3, footprint: Vector3, catalog) -> Array:
	var placements := []
	var slot_index := 0
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var content_id := str(value)
			var size := _graybox_content_size(category, content_id)
			var offset := _graybox_content_offset(category, slot_index, footprint)
			offset.y = size.y * 0.5
			var position := node_position + offset
			var support: String = catalog.support_level(category, content_id) if catalog != null and catalog.has_method("support_level") else "placeholder"
			placements.append({
				"id": content_id,
				"category": category,
				"support": support,
				"shape": _graybox_content_shape(category, content_id),
				"role": _graybox_content_role(category, content_id),
				"size": _vec3_to_array(size),
				"local_offset": _vec3_to_array(offset),
				"position": _vec3_to_array(position),
				"rotation_y_degrees": float((slot_index * 37 + int(node.get("chain_index", 0)) * 11) % 180),
				"label": content_id,
			})
			slot_index += 1
	return placements

static func _graybox_content_offset(category: String, slot_index: int, footprint: Vector3) -> Vector3:
	var stagger := float(slot_index % 3) - 1.0
	match category:
		"flora":
			return Vector3(-footprint.x * 0.28 + stagger * 0.45, 0.0, -footprint.z * 0.22)
		"enemies":
			return Vector3(footprint.x * 0.24, 0.0, -footprint.z * 0.05 + stagger * 0.55)
		"structures":
			return Vector3(stagger * 0.55, 0.0, footprint.z * 0.18)
		_:
			return Vector3.ZERO

static func _graybox_content_shape(category: String, content_id: String) -> String:
	if category == "flora":
		match content_id:
			"scarpet", "resolution_roots", "forget_me_nots":
				return "mat"
			"climbvine":
				return "vine_column"
			"mother_flure":
				return "canopy"
			_:
				return "plant_cluster"
	if category == "enemies":
		return "enemy_volume"
	match content_id:
		"pipe":
			return "pipe"
		"terminal":
			return "console"
		"shelter":
			return "shelter_shell"
		"shortcut_gate":
			return "gate"
		"root_slide":
			return "slide"
		_:
			return "structure_box"

static func _graybox_content_role(category: String, content_id: String) -> String:
	if category == "enemies":
		return "pressure"
	if category == "flora":
		match content_id:
			"scarpet":
				return "cover"
			"seefern":
				return "readable_screen"
			"climbvine", "resolution_roots":
				return "traversal"
			"flure", "mother_flure":
				return "puzzle_flora"
			_:
				return "resource"
	match content_id:
		"terminal":
			return "guidance"
		"forage_cache":
			return "resource"
		"shortcut_gate":
			return "shortcut"
		"shelter":
			return "rest"
		_:
			return "structure"

static func _graybox_content_size(category: String, content_id: String) -> Vector3:
	if category == "flora":
		match content_id:
			"seefern":
				return Vector3(0.9, 1.8, 0.7)
			"scarpet":
				return Vector3(2.2, 0.16, 1.7)
			"flure":
				return Vector3(1.8, 1.45, 1.8)
			"mother_flure":
				return Vector3(5.2, 3.2, 5.2)
			"hushbloom":
				return Vector3(1.0, 1.1, 1.0)
			"doma":
				return Vector3(1.2, 1.4, 1.2)
			"snapbloom":
				return Vector3(1.1, 1.2, 1.1)
			"capbage":
				return Vector3(1.35, 0.9, 1.35)
			"gasafoetida":
				return Vector3(1.0, 1.35, 1.0)
			"climbvine":
				return Vector3(0.8, 2.7, 0.8)
			"resolution_roots":
				return Vector3(2.8, 0.22, 2.1)
			"forget_me_nots":
				return Vector3(1.4, 0.7, 1.4)
			_:
				return Vector3(1.1, 1.0, 1.1)
	if category == "enemies":
		match content_id:
			"hidras", "nosomas":
				return Vector3(1.8, 1.5, 1.8)
			"tanglers":
				return Vector3(1.9, 1.0, 1.9)
			"crusts", "naturalizers":
				return Vector3(1.5, 1.1, 1.5)
			"spikers", "toxos":
				return Vector3(1.25, 1.35, 1.25)
			"gnawers", "meebs":
				return Vector3(1.0, 0.8, 1.0)
			_:
				return Vector3(1.2, 1.1, 1.2)
	match content_id:
		"shelter":
			return Vector3(4.8, 2.4, 3.4)
		"terminal":
			return Vector3(1.2, 1.65, 0.75)
		"forage_cache":
			return Vector3(1.7, 0.75, 1.0)
		"shortcut_gate":
			return Vector3(2.4, 2.2, 0.38)
		"pipe":
			return Vector3(3.3, 0.55, 0.55)
		"barrier":
			return Vector3(2.6, 1.25, 0.5)
		"membrane":
			return Vector3(2.4, 1.6, 0.25)
		"root_slide":
			return Vector3(3.8, 0.45, 1.15)
		"carry_gear":
			return Vector3(1.1, 0.8, 1.1)
		"hide_slot":
			return Vector3(1.6, 1.4, 1.0)
		"junction":
			return Vector3(3.0, 1.2, 2.0)
		_:
			return Vector3(1.4, 1.0, 1.0)

static func _graybox_route_width(route: Dictionary) -> float:
	var kind := _route_kind(route)
	if kind == "risky":
		return 1.15
	if kind == "shortcut":
		return 1.25
	if route.has("bypasses_optional"):
		return 1.35
	return 1.85

static func _find_node_in_list(nodes: Array, node_id: String) -> Dictionary:
	for node in nodes:
		if node is Dictionary and str((node as Dictionary).get("id", "")) == node_id:
			return node as Dictionary
	return {}

static func _array_to_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return fallback

static func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _vec3_path_to_arrays(path: Array) -> Array:
	var result := []
	for value in path:
		if value is Vector3:
			result.append(_vec3_to_array(value))
	return result

static func _path_distance_3d(path: Array) -> float:
	var distance := 0.0
	for i in range(1, path.size()):
		if path[i - 1] is Vector3 and path[i] is Vector3:
			distance += (path[i - 1] as Vector3).distance_to(path[i] as Vector3)
	return distance

static func _navigation_risk_penalty(kind: String) -> float:
	match kind:
		"risky":
			return 28.0
		"shortcut":
			return 4.0
		_:
			return 0.0

static func _navigation_floor_key(position: Vector3) -> String:
	return "%d:%d" % [int(roundf(position.x * 10.0)), int(roundf(position.z * 10.0))]

static func _build_anchors(nodes: Array) -> Dictionary:
	var anchors := {
		"aster": [0.0, 0.5, 1.6],
		"peris": [-1.6, 0.5, 0.0],
		"endo": [-1.2, 0.5, -1.8],
	}
	for node in nodes:
		if node is Dictionary:
			anchors[str((node as Dictionary).get("id", ""))] = (node as Dictionary).get("position", [0.0, 0.45, 0.0])
	return anchors

static func _build_world_slot(settings: Dictionary, anchors: Dictionary) -> Dictionary:
	var slot: Dictionary = settings.get("world_slot", {}).duplicate(true)
	var spec_id := str(settings.get("id", "generated_stretch"))
	if not slot.has("slot_id"):
		slot["slot_id"] = spec_id
	if not slot.has("act"):
		slot["act"] = 1
	if not slot.has("region"):
		slot["region"] = "Generated Stretch"
	if not slot.has("entry_shelter_id"):
		slot["entry_shelter_id"] = "generated_entry"
	if not slot.has("exit_shelter_id"):
		slot["exit_shelter_id"] = "generated_exit"
	slot["entry_anchor"] = str(slot.get("entry_anchor", "entry"))
	slot["exit_anchor"] = str(slot.get("exit_anchor", "exit_shelter"))
	slot["canonical_party"] = slot.get("canonical_party", ["aster", "peris", "endo"])
	slot["preview_party_preset"] = str(slot.get("preview_party_preset", "full_party_full_health"))
	slot["next_slot"] = str(slot.get("next_slot", ""))
	return slot

static func _build_composition_summary(composition: Dictionary, archetype_chain: Array, nodes: Array, random_walk: Dictionary = {}) -> Dictionary:
	var chain: Array = composition.get("chain", []).duplicate(true)
	var nested: Array = composition.get("nested", []).duplicate(true)
	var max_depth := 0
	for entry in nested:
		if entry is Dictionary:
			max_depth = maxi(max_depth, int((entry as Dictionary).get("depth", 1)))
	var links := []
	for i in range(chain.size() - 1):
		var current: Dictionary = chain[i]
		var next: Dictionary = chain[i + 1]
		links.append({
			"from_chain_index": i,
			"to_chain_index": i + 1,
			"from_archetype": str(current.get("id", "")),
			"to_archetype": str(next.get("id", "")),
			"output": str(current.get("output", "")),
			"input": str(next.get("input", "")),
			"feeds_next": str(current.get("output", "")) != "" and str(current.get("output", "")) == str(next.get("input", "")),
		})
	var host_nodes := []
	for node in nodes:
		if node is Dictionary and not (node as Dictionary).get("nested_archetypes", []).is_empty():
			host_nodes.append(str((node as Dictionary).get("id", "")))
	return {
		"mode": str(composition.get("mode", "")),
		"chain": chain,
		"nested": nested,
		"links": links,
		"chain_count": chain.size() if not chain.is_empty() else archetype_chain.size(),
		"nested_count": nested.size(),
		"nested_depth": max_depth,
		"has_nested": not nested.is_empty(),
		"host_nodes": host_nodes,
		"uses_random_walk": not random_walk.is_empty(),
		"random_walk": random_walk.duplicate(true),
		"walk_element_count": int(random_walk.get("element_count", 0)),
		"walk_archetype_count": (random_walk.get("visited_archetypes", []) as Array).size() if random_walk.get("visited_archetypes", []) is Array else 0,
	}

## Flag content the generator actually PLACED (not just the featured palette) that is a
## graybox placeholder, so the warnings match what a player would see on the spine.
static func _collect_warnings(catalog, nodes: Array) -> Array:
	var warnings := []
	var seen := {}
	for node in nodes:
		if not (node is Dictionary):
			continue
		for category in ["flora", "enemies", "structures"]:
			for key in (node as Dictionary).get(category, []):
				var dedupe := "%s:%s" % [category, str(key)]
				if seen.has(dedupe):
					continue
				seen[dedupe] = true
				if catalog.support_level(category, str(key)) != "implemented":
					warnings.append({
						"category": category,
						"id": str(key),
						"message": "%s is represented by a generated graybox placeholder." % str(key),
					})
	return warnings

static func _golden_path(nodes: Array) -> Array:
	var path := []
	for node in nodes:
		if node is Dictionary and not bool((node as Dictionary).get("optional", false)):
			path.append(str((node as Dictionary).get("id", "")))
	return path

static func _risky_recovery(routes: Array, nodes: Array) -> Array:
	for route in routes:
		if route is Dictionary and _route_kind(route as Dictionary) == "risky":
			return [str((route as Dictionary).get("id", "")), "exit_shelter"]
	return _golden_path(nodes)

static func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", ""))
	if kind != "":
		return kind
	return str(route.get("risk", "safe"))

static func _choose_values(catalog, category: String, count: int, limitations: Dictionary, rng) -> Array:
	var required := _category_limitations(limitations, "required", category)
	var allowed := _category_limitations(limitations, "allowed", category)
	var blocked := _category_limitations(limitations, "blocked", category)
	var available := _available_values(catalog, category, allowed, blocked)
	var target_count := maxi(required.size(), count)
	var values: Array[String] = []
	for value in required:
		if not values.has(value):
			values.append(value)
	while values.size() < target_count and not available.is_empty():
		var picked := str(rng.pick(available))
		available.erase(picked)
		if not values.has(picked):
			values.append(picked)
	return values

static func _available_values(catalog, category: String, allowed: Array, blocked: Array) -> Array[String]:
	var values: Array[String] = []
	var source: Array[String] = catalog.get_archetype_ids() if category == "archetypes" else catalog.get_content_keys(category)
	for value in source:
		var key := str(value)
		if not allowed.is_empty() and not allowed.has(key):
			continue
		if blocked.has(key):
			continue
		values.append(key)
	return values

static func _category_limitations(limitations: Dictionary, mode: String, category: String) -> Array[String]:
	var group: Dictionary = limitations.get(mode, {})
	if not (group is Dictionary):
		return []
	return _string_array(group.get(category, []))

static func _category_slot_budget(category: String, budget: Dictionary) -> int:
	match category:
		"flora":
			return int(budget.get("flora_slots", 0))
		"enemies":
			return int(budget.get("enemy_slots", 0))
		"structures":
			return int(budget.get("structures_slots", budget.get("structure_slots", 0)))
		"archetypes":
			return int(budget.get("archetype_depth", 0))
		_:
			return 0

static func _slice_usage(values: Array, index: int, count: int) -> Array:
	var result := []
	if values.is_empty() or count <= 0:
		return result
	for i in range(count):
		result.append(values[(index + i) % values.size()])
	return result

## --- Archetype coherence: a node's role, structure, actors and label all derive from
## its archetype, so a forage beat reads as foraging (not "Danger Beat"), a redirect gets
## an actual charger to redirect, and an exploit gets the predator+prey it needs. ---

## The role a node wears, driven by its archetype (survival kind first, else a compatible
## role) rather than a blind cycle — so role never contradicts what the node is.
static func _role_for_archetype(archetype: Dictionary, index: int) -> String:
	# A diagnosis node is a read-and-deduce beat — it wears the guidance role so it reads as
	# a station the party studies, never a danger pad.
	if str(archetype.get("kind", "")) == "diagnosis" or str(archetype.get("solve", "")) == "deduce":
		return "guidance"
	match str(archetype.get("survival_kind", "")):
		"forage":
			return "foraging"
		"rest":
			return "regroup"
		"gauntlet", "exploit":
			return "danger"
		"hazard":
			return "route_pressure"
	var roles: Array = archetype.get("compatible_node_roles", [])
	if roles.is_empty():
		return "mixed"
	return str(roles[index % roles.size()])

## Enemy "slots" an archetype needs, each a set of acceptable content-palette tags. A
## redirect needs a charger; an exploit needs prey + a predator; a gauntlet needs lanes.
static func _enemy_needs(archetype: Dictionary) -> Array:
	var variant := str(archetype.get("variant", ""))
	match str(archetype.get("survival_kind", "")):
		"exploit":
			match variant:
				"siderophore_into_meeb":
					return [["siderophore", "swarm"], ["engulfer", "predator", "siderophore_counter"]]
				"trigger_neutro_burst":
					return [["burst", "aoe", "neutral_until_triggered"], ["siderophore"]]
				"gnawer_onto_loud_signal":
					return [["siderophore", "swarm"], ["hunter", "metabolic"]]
				"candid_zone_route":
					return [["biofilm", "environment"], ["patrol", "stealth"]]
				_:
					return [["siderophore"], ["engulfer", "predator"]]
		"gauntlet":
			return [["patrol", "enforcement"], ["sniper", "line_of_sight"], ["stealth", "grapple"]]
		"hazard":
			return [["siderophore", "biofilm"]]
		"forage":
			return [["swarm", "siderophore"]]
		"rest":
			return []
	match str(archetype.get("id", "")):
		"1":
			return [["hunter", "swarm", "siderophore", "metabolic"]]
		"4":
			return [["patrol", "enforcement"]]
		"7":
			return [["patrol", "enforcement", "sniper", "line_of_sight"]]
		"10":
			return [["patrol"], ["siderophore"]]
	return []

## Flora an archetype wants — the variant usually names it (hushbloom_stun -> hushbloom),
## plus survival/cover needs — so the placed plant matches the approach that references it.
static func _flora_needs(archetype: Dictionary) -> Array:
	var variant := str(archetype.get("variant", ""))
	var sk := str(archetype.get("survival_kind", ""))
	var needs := []
	var variant_flora := {
		"hushbloom_stun": "hushbloom", "flure_iron_decoy": "flure", "climbvine_traversal": "climbvine",
		"resolution_roots_stabilize": "resolution_roots", "resolution_roots_break": "resolution_roots",
	}
	if variant_flora.has(variant):
		needs.append({"id": str(variant_flora[variant])})
	match sk:
		"forage", "rest":
			needs.append({"id": "capbage"})
			needs.append({"tag": "cover"})
		"exploit":
			needs.append({"id": "flure"})
		"hazard":
			needs.append({"id": "resolution_roots"})
	match str(archetype.get("id", "")):
		"1", "3", "7":
			needs.append({"tag": "cover"})
		"4":
			needs.append({"id": "flure"})
		"6":
			needs.append({"tag": "reveal"})
	if needs.is_empty():
		needs.append({"tag": "cover"})
	return needs

## Resolve one content need (a specific id, or any of some tags) against the available pool,
## avoiding what's already placed. Falls back from an unavailable exact id to its tags.
static func _content_for_need(catalog, category: String, available: Array, need: Dictionary, exclude: Array, rng) -> String:
	if need.has("id"):
		var id := str(need["id"])
		if available.has(id) and not exclude.has(id):
			return id
	var want_tags: Array = []
	if need.has("tags"):
		want_tags = need["tags"]
	elif need.has("tag"):
		want_tags = [str(need["tag"])]
	elif need.has("id"):
		want_tags = catalog.get_content(category, str(need["id"])).get("tags", [])
	var candidates := []
	for c in available:
		if exclude.has(str(c)):
			continue
		var tags: Array = catalog.get_content(category, str(c)).get("tags", [])
		for t in want_tags:
			if tags.has(str(t)):
				candidates.append(str(c))
				break
	return str(rng.pick(candidates)) if not candidates.is_empty() else ""

static func _enemies_for_node(catalog, archetype: Dictionary, available: Array, max_count: int, rng) -> Array:
	var placed := []
	for tag_options in _enemy_needs(archetype):
		if placed.size() >= max_count:
			break
		var pick := _content_for_need(catalog, "enemies", available, {"tags": tag_options}, placed, rng)
		if pick != "":
			placed.append(pick)
	return placed

static func _flora_for_node(catalog, archetype: Dictionary, available: Array, rng) -> Array:
	var placed := []
	for need in _flora_needs(archetype):
		if placed.size() >= 2:
			break
		var pick := _content_for_need(catalog, "flora", available, need, placed, rng)
		if pick != "":
			placed.append(pick)
	return placed

const ARCHETYPE_STRUCTURE := {"1": "barrier", "2": "root_slide", "3": "carry_gear", "4": "pipe", "5": "membrane", "6": "terminal", "7": "hide_slot", "8": "class_gate", "11": "junction"}
const SURVIVAL_STRUCTURE := {"forage": "forage_cache", "rest": "hide_slot", "gauntlet": "barrier", "hazard": "water_control", "exploit": "pipe"}
const ROLE_STRUCTURE := {"boundary": "junction", "shelter_arrival": "shelter", "foraging": "forage_cache", "route_pressure": "pipe", "guidance": "terminal", "danger": "barrier", "shortcut": "shortcut_gate", "mixed": "membrane", "regroup": "hide_slot", "setpiece": "root_slide"}

## The structure on a node, preferred by survival kind / archetype, then role — never a
## stray shelter on an interior node (which used to undercut the find-shelter tension).
static func _structure_for_node(archetype: Dictionary, role: String, available: Array) -> Array:
	var pref := str(SURVIVAL_STRUCTURE.get(str(archetype.get("survival_kind", "")), ""))
	if pref == "":
		pref = str(ARCHETYPE_STRUCTURE.get(str(archetype.get("id", "")), ""))
	if pref != "" and available.has(pref):
		return [pref]
	var role_pref := str(ROLE_STRUCTURE.get(role, "pipe"))
	if available.has(role_pref) and (role_pref != "shelter" or role == "shelter_arrival"):
		return [role_pref]
	for s in available:
		if str(s) != "shelter" or role == "shelter_arrival":
			return [str(s)]
	# Only "shelter" is available and this isn't the arrival beat: place no structure rather
	# than a stray interior shelter or a "pipe" the palette may not even allow.
	return []

## A node label that reads as the archetype + its variant, not the bare role name.
static func _node_label(archetype: Dictionary, role: String, index: int) -> String:
	if role == "boundary":
		return "Entry Boundary"
	if role == "shelter_arrival":
		return "Shelter Arrival"
	var name := str(archetype.get("name", ""))
	if name == "":
		return _label_for_node(role, index)
	var variant := str(archetype.get("variant", ""))
	if variant != "":
		return "%s · %s" % [name, variant.capitalize().replace("_", " ")]
	return name

static func _structures_for_role(role: String, structures: Array, index: int) -> Array:
	var preferred := {
		"boundary": "junction",
		"foraging": "forage_cache",
		"route_pressure": "pipe",
		"guidance": "terminal",
		"danger": "barrier",
		"shortcut": "shortcut_gate",
		"mixed": "membrane",
		"regroup": "hide_slot",
		"setpiece": "root_slide",
		"shelter_arrival": "shelter",
	}
	var result := []
	var pick := str(preferred.get(role, "pipe"))
	if structures.has(pick):
		result.append(pick)
	elif not structures.is_empty():
		result.append(structures[index % structures.size()])
	return result

static func _label_for_node(role: String, index: int) -> String:
	match role:
		"boundary":
			return "Entry Boundary"
		"route_pressure":
			return "Route Pressure"
		"foraging":
			return "Foraging Beat"
		"guidance":
			return "Guidance Beat"
		"danger":
			return "Danger Beat"
		"shortcut":
			return "Shortcut Lock"
		"mixed":
			return "Mixed Node"
		"regroup":
			return "Regroup Pocket"
		"setpiece":
			return "Set Piece"
		"shelter_arrival":
			return "Shelter Arrival"
		_:
			return "Node %d" % index

static func _canonical_category(category: String) -> String:
	return str(CATEGORY_ALIASES.get(category.strip_edges().to_lower(), ""))

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := str(entry).strip_edges().to_lower()
			if text != "" and not result.has(text):
				result.append(text)
	elif value is String:
		for part in str(value).split(",", false):
			var text := part.strip_edges().to_lower()
			if text != "" and not result.has(text):
				result.append(text)
	return result

static func _sanitize_id(value: String) -> String:
	var result := value.strip_edges().to_lower()
	result = result.replace(" ", "_")
	result = result.replace("-", "_")
	result = result.replace("'", "")
	result = result.replace("\"", "")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	return result
