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
	resolved["progression_stage"] = _resolve_progression_stage(catalog, resolved)

	var palette_usage := _choose_palette_usage(catalog, resolved, budget, rng)
	var random_walk := _build_archetype_random_walk(catalog, resolved, budget, rng)
	var archetype_chain := _chain_from_random_walk(catalog, random_walk, rng) if _uses_archetype_random_walk(resolved) else _choose_archetype_chain(catalog, resolved, budget, rng)
	var nodes := _build_nodes(resolved, budget, palette_usage, archetype_chain, rng, random_walk)
	var routes := _build_routes(nodes, budget, rng)
	var graybox := _apply_graybox_layout(nodes, routes, catalog, resolved, budget)
	var navigation := _build_navigation_graph(nodes, routes, resolved, graybox)
	graybox["navigation_contract_id"] = str(navigation.get("contract_id", ""))
	graybox["navigation_node_count"] = int((navigation.get("nodes", []) as Array).size())
	graybox["navigation_edge_count"] = int((navigation.get("edges", []) as Array).size())
	var anchors := _build_anchors(nodes)
	var world_slot := _build_world_slot(resolved, anchors)
	var composition_summary := _build_composition_summary(resolved.get("composition", {}), archetype_chain, nodes, random_walk)
	var warnings := _collect_warnings(catalog, palette_usage)
	var solution := SolverScript.analyze(nodes, str(resolved.get("complexity_tier", "teaching")), int(resolved.get("progression_stage", 99)))

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
		},
		"settings": resolved,
		"budget": budget.duplicate(true),
		"world_slot": world_slot,
		"anchors": anchors,
		"graybox": graybox,
		"navigation": navigation,
		"nodes": nodes,
		"routes": routes,
		"archetype_chain": archetype_chain,
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
				"progression_stage": solution.get("progression_stage", int(resolved.get("progression_stage", 99))),
				"distinct_node_count": solution.get("distinct_node_count", 0),
				"distinct_nodes": solution.get("distinct_nodes", []),
				"multi_solution_required": solution.get("multi_solution_required", false),
				"multi_solution_ok": solution.get("multi_solution_ok", true),
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

	_validate_composition(catalog, resolved.get("composition", {}), limitations, resolved.get("budget", {}), errors)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"resolved_settings": resolved,
		"catalog": catalog,
	}

static func build_navigation_graph_from_spec(spec: Dictionary) -> Dictionary:
	var nodes: Array = spec.get("nodes", []).duplicate(true)
	var routes: Array = spec.get("routes", []).duplicate(true)
	var settings: Dictionary = spec.get("settings", {}).duplicate(true)
	if settings.is_empty():
		settings = {
			"id": str(spec.get("id", "generated_stretch")),
			"complexity_tier": str(spec.get("source", {}).get("complexity_tier", "generated")),
		}
	var graybox: Dictionary = spec.get("graybox", {}).duplicate(true)
	return _build_navigation_graph(nodes, routes, settings, graybox)

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
	var base_budget: Dictionary = (TIER_BUDGETS[tier] as Dictionary).duplicate(true)
	var override_budget: Dictionary = settings.get("budget", {})
	for key in override_budget.keys():
		base_budget[key] = _resolve_budget_value(override_budget[key], int(base_budget.get(key, 0)), rng)
	base_budget["node_count"] = maxi(4, int(base_budget.get("node_count", 6)))
	base_budget["branch_count"] = maxi(0, int(base_budget.get("branch_count", 0)))
	base_budget["archetype_depth"] = maxi(1, int(base_budget.get("archetype_depth", 1)))

	var resolved := settings.duplicate(true)
	resolved["id"] = _sanitize_id(str(resolved.get("id", "generated_stretch_%d" % seed)))
	resolved["title"] = str(resolved.get("title", "Generated Stretch"))
	resolved["seed"] = seed
	resolved["complexity_tier"] = tier
	resolved["budget"] = base_budget
	resolved["limitations"] = _normalize_limitations(settings.get("limitations", {}))
	resolved["composition"] = _normalize_composition(settings.get("composition", {}))
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
	return chain

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
		"stage": int(entry.get("stage", 1)),
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

static func _build_nodes(settings: Dictionary, budget: Dictionary, palette_usage: Dictionary, archetype_chain: Array, rng, random_walk: Dictionary = {}) -> Array:
	var node_count := int(budget.get("node_count", 6))
	var optional_count := int(budget.get("optional_node_count", 0))
	var resource_beats := int(budget.get("resource_beats", 1))
	var pressure_budget := int(budget.get("pressure_budget", 1))
	var composition: Dictionary = settings.get("composition", {})
	var walk_visits: Array = random_walk.get("visits", [])
	var roles := ["guidance", "route_pressure", "foraging", "danger", "shortcut", "mixed", "regroup", "setpiece"]
	var nodes := []
	for i in range(node_count):
		var role := "boundary" if i == 0 else ("shelter_arrival" if i == node_count - 1 else str(roles[(i - 1) % roles.size()]))
		var walk_entry := {}
		if i > 0 and i < node_count - 1 and not walk_visits.is_empty():
			walk_entry = (walk_visits[mini(i - 1, walk_visits.size() - 1)] as Dictionary).duplicate(true)
			role = str(walk_entry.get("node_role_hint", role))
		var optional := i > 0 and i < node_count - 1 and optional_count > 0 and (i % 3 == 0)
		if optional:
			optional_count -= 1
		var node_id := "entry" if i == 0 else ("exit_shelter" if i == node_count - 1 else "node_%02d" % i)
		var archetype: Dictionary = archetype_chain[(i - 1) % archetype_chain.size()] if i > 0 and i < node_count - 1 and not archetype_chain.is_empty() else {}
		var position := [float(i) * 12.0, 0.45, float(((i % 3) - 1) * 3)]
		if i == 0 and random_walk.has("entry_position"):
			position = random_walk.get("entry_position", position)
		elif i == node_count - 1 and random_walk.has("exit_position"):
			position = random_walk.get("exit_position", position)
		elif not walk_entry.is_empty() and walk_entry.has("position"):
			position = walk_entry.get("position", position)
		var flora := _slice_usage(palette_usage.get("flora", []), i, 1)
		var enemies := _slice_usage(palette_usage.get("enemies", []), i, 1) if pressure_budget > 0 and role in ["route_pressure", "danger", "mixed", "setpiece"] else []
		if not enemies.is_empty():
			pressure_budget -= 1
		var structures := _structures_for_role(role, palette_usage.get("structures", []), i)
		var is_resource := resource_beats > 0 and role in ["foraging", "regroup"]
		var archetype_id := str(archetype.get("id", "11" if role in ["boundary", "shelter_arrival"] else ""))
		var nested_archetypes := _nested_for_archetype(archetype_id, composition)
		var label := _label_for_node(role, i)
		if not walk_entry.is_empty():
			label = "A%s.%d %s" % [
				str(walk_entry.get("archetype_id", archetype_id)),
				int(walk_entry.get("step_index", 0)) + 1,
				str(walk_entry.get("element", "Element")).capitalize(),
			]
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
		}
		nodes.append(node)
		if resource_beats > 0 and role in ["foraging", "regroup"]:
			resource_beats -= 1
	return nodes

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

static func _build_navigation_graph(nodes: Array, routes: Array, settings: Dictionary, graybox: Dictionary) -> Dictionary:
	var nav_nodes := []
	var nav_edges := []
	var elevation_indices: Array[int] = []
	var floor_columns := {}
	for node in nodes:
		if not (node is Dictionary):
			continue
		var node_def := node as Dictionary
		var node_id := str(node_def.get("id", ""))
		if node_id == "":
			continue
		var position := _array_to_vec3(node_def.get("position", []), Vector3.ZERO)
		var elevation_index := int(node_def.get("elevation_index", 0))
		if not elevation_indices.has(elevation_index):
			elevation_indices.append(elevation_index)
		var footprint := _array_to_vec3(node_def.get("footprint", node_def.get("floor_size", [])), Vector3(4.0, 0.14, 4.0))
		nav_nodes.append({
			"id": node_id,
			"position": _vec3_to_array(position),
			"role": str(node_def.get("role", "")),
			"surface_id": "node:%s" % node_id,
			"surface_y": float(node_def.get("surface_y", position.y)),
			"elevation_index": elevation_index,
			"floor_size": _vec3_to_array(footprint),
			"radius": maxf(footprint.x, footprint.z) * 0.5,
			"supports_click_to_move": true,
			"content_count": (node_def.get("content_placements", []) as Array).size() if node_def.get("content_placements", []) is Array else 0,
		})
		var floor_key := _navigation_floor_key(position)
		if not floor_columns.has(floor_key):
			floor_columns[floor_key] = {
				"xz": [position.x, position.z],
				"floors": [],
			}
		(floor_columns[floor_key]["floors"] as Array).append({
			"node_id": node_id,
			"y": position.y,
			"elevation_index": elevation_index,
		})

	for route in routes:
		if not (route is Dictionary):
			continue
		var route_def := route as Dictionary
		var from_id := str(route_def.get("from", ""))
		var to_id := str(route_def.get("to", ""))
		var from_node := _find_node_in_list(nodes, from_id)
		var to_node := _find_node_in_list(nodes, to_id)
		if from_node.is_empty() or to_node.is_empty():
			continue
		var from_pos := _array_to_vec3(from_node.get("position", []), Vector3.ZERO)
		var to_pos := _array_to_vec3(to_node.get("position", []), Vector3.ZERO)
		var midpoint := _array_to_vec3(route_def.get("surface", {}).get("midpoint", []), (from_pos + to_pos) * 0.5)
		var waypoints := [from_pos, midpoint, to_pos]
		var kind := _route_kind(route_def)
		var height_delta := to_pos.y - from_pos.y
		var horizontal_length := maxf(0.001, Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z).length())
		var physical_cost := _path_distance_3d(waypoints)
		var risk_penalty := _navigation_risk_penalty(kind)
		nav_edges.append({
			"id": str(route_def.get("id", "%s_to_%s" % [from_id, to_id])),
			"from": from_id,
			"to": to_id,
			"route_id": str(route_def.get("id", "")),
			"kind": kind,
			"risk": str(route_def.get("risk", kind)),
			"recoverable": bool(route_def.get("recoverable", true)),
			"bidirectional": true,
			"width": float(route_def.get("width", route_def.get("surface", {}).get("width", 1.4))),
			"height_delta": height_delta,
			"slope_ratio": height_delta / horizontal_length,
			"traversal": "ramp" if absf(height_delta) > 0.05 else "walkway",
			"waypoints": _vec3_path_to_arrays(waypoints),
			"physical_cost": physical_cost,
			"risk_penalty": risk_penalty,
			"path_cost": physical_cost + risk_penalty,
		})

	var floor_column_list := []
	for key in floor_columns.keys():
		var column: Dictionary = floor_columns[key]
		var floors: Array = column.get("floors", [])
		floors.sort_custom(func(a, b): return float((a as Dictionary).get("y", 0.0)) < float((b as Dictionary).get("y", 0.0)))
		column["floors"] = floors
		floor_column_list.append(column)
	elevation_indices.sort()
	return {
		"contract_id": "multi_level_navigation_graph_v1",
		"space_id": str(settings.get("id", "generated_stretch")),
		"supports_multiple_elevations": bool(graybox.get("supports_multiple_elevations", elevation_indices.size() > 1)),
		"entry_node": "entry",
		"exit_node": "exit_shelter",
		"entry_anchor": "entry",
		"exit_anchor": "exit_shelter",
		"max_snap_distance": 9.0,
		"elevation_indices": elevation_indices,
		"nodes": nav_nodes,
		"edges": nav_edges,
		"floor_columns": floor_column_list,
		"route_modes": ["safe", "direct"],
		"golden_path_nodes": _golden_path(nodes),
		"source": {
			"generator": "archetype_based_stretch_v1",
			"spec_id": str(settings.get("id", "generated_stretch")),
			"complexity_tier": str(settings.get("complexity_tier", "generated")),
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

static func _collect_warnings(catalog, palette_usage: Dictionary) -> Array:
	var warnings := []
	for category in ["flora", "enemies", "structures"]:
		for key in palette_usage.get(category, []):
			if catalog.support_level(category, str(key)) != "implemented":
				warnings.append({
					"category": category,
					"id": key,
					"message": "%s is represented by a generated graybox placeholder." % key,
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
