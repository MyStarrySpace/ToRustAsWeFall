class_name StretchGenerator
extends RefCounted

const CatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")
const SeededRngScript := preload("res://scripts/system/random/seeded_rng.gd")
const GenerationProbeScript := preload("res://scripts/generation/generation_probe.gd")
const SolverScript := preload("res://scripts/generation/stretch_solution_solver.gd")
const RoomPieceCatalogScript := preload("res://scripts/generation/roompiece_catalog.gd")
const WfcLayoutScript := preload("res://scripts/generation/stretch_wfc_layout.gd")
const GridStitcherScript := preload("res://scripts/generation/stretch_grid_stitcher.gd")
const BiomesScript := preload("res://scripts/generation/biomes.gd")
const PoiDistributionScript := preload("res://scripts/generation/stretch_poi_distribution.gd")
const SystemsCurriculumScript := preload("res://scripts/generation/stretch_systems_curriculum.gd")
const BaseShapeScript := preload("res://scripts/generation/base_shape_builder.gd")
const BuildingFillerScript := preload("res://scripts/generation/building_filler.gd")
const FloraSpeciesScript := preload("res://scripts/game/objects/flora_species.gd")
const BranchWeaverScript := preload("res://scripts/generation/stretch_branch_weaver.gd")
const RuntimeRegistryScript := preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)

# The generated entry is a deployment surface, not a content socket. Party
# presenters have a 0.25 m body radius; the extra margin keeps real generated
# flora (including its outline/pointer collider) out of both the initial body
# volume and the immediately readable formation around it.
const PARTY_SPAWN_IDS: Array[String] = ["aster", "peris", "endo"]
const PARTY_SPAWN_BODY_RADIUS := 0.25
const PARTY_SPAWN_CONTENT_MARGIN := 0.30

# Generated actions are not points floating over approximate floor geometry.
# Their approach is a persisted typed graph vertex plus the nearby vertices from
# which the shipped interactable will actually accept the action.  The extra
# 0.15 m mirrors generated_stretch_chunk's physical arrival tolerance.
const INTERACTION_APPROACH_CONTRACT_ID := "generated_interaction_approach_v1"
const GENERATED_INTERACTION_RADIUS := 1.8
const GENERATED_INTERACTION_ACCEPTANCE_RADIUS := (
	GENERATED_INTERACTION_RADIUS + 0.15
)
const CONTENT_NAVIGATION_CONTRACT_ID := "generated_content_navigation_v1"
const SPEC_INTEGRITY_CONTRACT_ID := "generated_spec_integrity_v1"
const SPATIAL_SOCKET_CONTRACT_ID := "generated_spatial_feature_sockets_v1"
const PARTY_SPAWN_CLEARANCE_CONTRACT_ID := "generated_party_spawn_clearance_v1"

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

## Complexity tier owns traversal scale. Standard and later stretches need enough
## physical decision space for their route, exposure, and resource decisions to interact;
## teaching stays compact, and an explicit spatial_profile always wins.
const TIER_SLOT_PITCH := {
	"teaching": 8,
	"standard": 13,
	"hard": 15,
	"setpiece": 16,
}
const RUNTIME_ONLY_PLAY_CONFIG_KEYS := [
	"game_mode",
	"play_config",
	"preview_config",
	"food_test",
	"food_test_settings",
	"drain_interval_seconds",
	"drain_atp",
	"zero_atp_hp_drain",
	"scarcity",
	"difficulty",
	"difficulty_mode",
	"pressure_profile",
]

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
	# Reserve a later beat for the same causal model. This only grows a stretch when
	# its selected CONTENT would otherwise be introduced once and never tested; it
	# does not scale geometry merely because the campaign stage is higher.
	SystemsCurriculumScript.ensure_reasoning_budget(resolved, budget, archetype_chain)
	_ensure_complete_chain_budget(resolved, budget, archetype_chain)
	resolved["budget"] = budget
	var limitations: Dictionary = resolved.get("limitations", {})
	var available_flora := _available_values(catalog, "flora", _category_limitations(limitations, "allowed", "flora"), _category_limitations(limitations, "blocked", "flora"))
	var available_enemies := _available_values(catalog, "enemies", _category_limitations(limitations, "allowed", "enemies"), _category_limitations(limitations, "blocked", "enemies"))
	var available_structures := _available_values(catalog, "structures", _category_limitations(limitations, "allowed", "structures"), _category_limitations(limitations, "blocked", "structures"))
	var nodes := _build_nodes(catalog, resolved, budget, palette_usage, archetype_chain, rng, random_walk, available_flora, available_enemies, available_structures)
	# POI distribution (Layer A): guarantee every archetype's CRUCIAL ELEMENT is realized as content (a shared
	# element is placed once and covers all archetypes needing it — dedup at the element level), then scatter
	# progression-scaled AMBIENT POIs (denser/more varied at higher stages = mastery, solver-neutral). The guarantee
	# runs BEFORE the solver so any injected content is part of the analysis; ambient POIs live on a separate list
	# the solver ignores. On the default palette the per-node needs already cover everything, so injection is a
	# safety net (it only fires when a restricted/biome palette would otherwise strand a crucial element).
	var poi_distribution = PoiDistributionScript.new()
	var progression_stage := int(resolved.get("progression_stage", 2))
	_guarantee_element_coverage(nodes, poi_distribution, available_flora, available_structures)
	var poi_density := _apply_poi_density(nodes, poi_distribution, progression_stage, rng)
	var element_coverage := _compute_element_coverage(nodes, poi_distribution)
	var routes := _build_routes(nodes, budget, rng)
	var systems_contract: Dictionary = SystemsCurriculumScript.build_contract(catalog, nodes, routes, resolved)
	for node_index in range(nodes.size()):
		if not (nodes[node_index] is Dictionary):
			continue
		var presentation_node := nodes[node_index] as Dictionary
		if str(presentation_node.get("action_verb", "")) == "":
			presentation_node["action_verb"] = SystemsCurriculumScript.action_verb_for_node(presentation_node)
		nodes[node_index] = presentation_node
	# SPATIAL layer: WFC drops a room-piece into each archetype-node slot, stitched into one unified grid (the
	# node-graph semantics above are untouched — WFC runs on an isolated RNG stream). Falls back to the proven
	# legacy rasterizer if WFC ever yields nothing usable, so the generator never returns an unplayable grid.
	var piece_catalog = RoomPieceCatalogScript.new()
	# Elevation per node from the existing role/layout logic, so WFC stacks the pieces across floors (and lays a
	# ramp link on cross-floor routes) exactly where the legacy grid did — keeps the multi-elevation invariant.
	var max_levels := int(TIER_MAX_LEVELS.get(str(resolved.get("complexity_tier", "teaching")), 1))
	var levels := {}
	for li in range(nodes.size()):
		if nodes[li] is Dictionary:
			levels[str((nodes[li] as Dictionary).get("id", ""))] = _graybox_elevation_index(nodes[li], li, nodes.size(), max_levels)
	var layout: Dictionary = WfcLayoutScript.solve(nodes, routes, resolved, budget, piece_catalog, levels)
	var navigation_grid: Dictionary = GridStitcherScript.build(
		layout.get("placements", []), layout.get("corridors", []), layout.get("slot_cells", {}), resolved)
	var graybox: Dictionary
	var spatial_features: Array = []
	if navigation_grid.is_empty():
		layout = {}   # signal legacy in the roompieces block
		graybox = _apply_graybox_layout(nodes, routes, catalog, resolved, budget)
		navigation_grid = _build_navigation_grid_legacy(nodes, routes, resolved, graybox)
	else:
		_assign_spatial_features(nodes, layout, piece_catalog)
		graybox = _apply_wfc_graybox(nodes, routes, layout, catalog, resolved, budget)
		spatial_features = _collect_spatial_features(nodes, navigation_grid)
	# Persist the exact branch geometry before solving. The bare spine remains a
	# separate input for macro-shape coordinate maps; navigation_grid is the fixed,
	# authoritative playable topology used by the solver and deterministic replay.
	var spine_navigation_grid := navigation_grid.duplicate(true)
	navigation_grid = _weave_navigation_grid(spine_navigation_grid, resolved)
	var navigation_branches: Array = navigation_grid.get("branches", [])
	var approach_projection := _project_actionable_interaction_approaches(
		nodes,
		routes,
		navigation_grid,
		str(resolved.get("id", "generated_stretch"))
	)
	if not bool(approach_projection.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "actionable_interaction_approach_projection_failed",
			"validation": {"actionable_interaction_approaches": approach_projection},
			"draft_nodes": nodes,
			"draft_navigation_grid": navigation_grid,
		}
	graybox["navigation_contract_id"] = str(navigation_grid.get("contract_id", ""))
	graybox["navigation_node_count"] = nodes.size()
	graybox["navigation_edge_count"] = routes.size()
	graybox["actionable_interaction_approach_count"] = int(
		approach_projection.get("actionable_node_count", 0)
	)
	graybox["spatial_feature_count"] = spatial_features.size()
	var themed_landmarks := _build_themed_landmarks(nodes, navigation_grid, resolved)
	var infrastructure := _build_infrastructure_composition(nodes, navigation_grid, resolved, themed_landmarks)
	themed_landmarks.append_array(infrastructure.get("landmarks", []) as Array)
	graybox["themed_landmark_count"] = themed_landmarks.size()
	graybox["infrastructure_operation_count"] = (infrastructure.get("operations", []) as Array).size()
	var themed_setpieces := _build_themed_route_setpieces(navigation_grid, resolved)
	graybox["themed_setpiece_count"] = themed_setpieces.size()
	var anchors := _build_anchors(nodes)
	# WFC footprints can be as small as 3x2. The legacy boundary-flora socket
	# shared the open approach face with the three spawn anchors, which could put
	# a Capbage's real 1.4 m outline collider directly over Endo. Exclude only
	# content that actually overlaps a party spawn; all other generated content
	# remains unchanged, and the validator below fails closed on any overlap that
	# appears outside the entry boundary.
	var spawn_excluded_content_count := _exclude_entry_spawn_overlaps(nodes, anchors)
	if spawn_excluded_content_count > 0:
		# Spawn clearance may remove the one noun that supplied a stretch-wide
		# crucial element. Relocate that clue onto a non-entry node after the
		# exclusion; re-injecting it at the boundary would recreate the collision
		# this pass just removed.
		var relocated_content_node_indices: Array[int] = _guarantee_element_coverage(
			nodes,
			poi_distribution,
			available_flora,
			available_structures,
			true)
		# Rebuild only nodes that received a relocated noun. Rebuilding the entry
		# would compact its placement indices and could move a previously safe
		# retained noun back into the party's spawn footprint.
		_rebuild_declared_content_placements(
			nodes, catalog, relocated_content_node_indices)
		# `_collect_spatial_features` returns detached dictionaries. Refresh the
		# emitted top-level runtime contract after socket reassignment so it cannot
		# retain an excluded entry socket or omit the relocated visible clue.
		spatial_features = _collect_spatial_features(nodes, navigation_grid)
		graybox["spatial_feature_count"] = spatial_features.size()
		graybox["content_placement_count"] = _content_placement_count(nodes)
		graybox["spawn_excluded_content_count"] = spawn_excluded_content_count
		element_coverage = _compute_element_coverage(nodes, poi_distribution)
		systems_contract = SystemsCurriculumScript.build_contract(
			catalog, nodes, routes, resolved)
	else:
		graybox["spawn_excluded_content_count"] = 0
	# Content placement is part of the navigation graph, not decorative metadata
	# projected onto it after the fact. Reconcile every realized noun to a
	# reachable vertex inside its owning room before emitting its receipt. The
	# visible position, local offset, and any authored feature socket all move
	# together, so presentation and click movement consume the same truth.
	var content_navigation_placement := _place_realized_content_on_navigation(
		nodes,
		navigation_grid,
		layout.get("slot_cells", {}) as Dictionary,
		anchors
	)
	if not bool(content_navigation_placement.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "realized_content_navigation_projection_failed",
			"validation": {
				"realized_content_navigation": content_navigation_placement,
			},
			"draft_nodes": nodes,
			"draft_navigation_grid": navigation_grid,
			"draft_settings": resolved,
		}
	if int(content_navigation_placement.get("moved_placement_count", 0)) > 0:
		# `_collect_spatial_features` returns detached dictionaries. Refresh it
		# after graph-first socket placement so the top-level runtime contract
		# cannot retain the pre-navigation assignment positions.
		spatial_features = _collect_spatial_features(nodes, navigation_grid)
		graybox["spatial_feature_count"] = spatial_features.size()
	var content_navigation_projection := _project_realized_content_navigation(
		nodes, navigation_grid)
	if not bool(content_navigation_projection.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "realized_content_navigation_projection_failed",
			"validation": {
				"realized_content_navigation": content_navigation_projection,
			},
			"draft_nodes": nodes,
			"draft_navigation_grid": navigation_grid,
			"draft_settings": resolved,
		}
	graybox["realized_content_navigation_count"] = int(
		content_navigation_projection.get("realized_content_placement_count", 0))
	var world_slot := _build_world_slot(resolved, anchors)
	var teaching_chain := _teaching_chain_edges(catalog, archetype_chain)
	var composition_summary := _build_composition_summary(resolved.get("composition", {}), archetype_chain, nodes, random_walk)
	composition_summary["teaching_chain"] = teaching_chain
	composition_summary["element_coverage"] = element_coverage
	composition_summary["poi_density"] = poi_density
	var warnings := _collect_warnings(catalog, nodes, resolved.get("composition", {}))
	var solution := SolverScript.analyze(
		nodes,
		str(resolved.get("complexity_tier", "teaching")),
		int(resolved.get("progression_stage", 99)),
		resolved.get("roster", []),
		navigation_branches,
		navigation_grid
	)
	var headless_solution := _solution_script(solution, _golden_path(nodes))
	var authored_world_actions := SystemsCurriculumScript.world_actions_for_spec(
		str(resolved.get("id", ""))
	)
	if not authored_world_actions.is_empty():
		headless_solution["world_actions"] = authored_world_actions
	var topology_contract := _build_topology_contract(
		nodes, routes, navigation_branches, navigation_grid
	)

	var spec := {
		"success": true,
		"ok": true,
		"schema": SPEC_SCHEMA,
		"id": str(resolved.get("id", "generated_stretch")),
		"title": str(resolved.get("title", "Generated Stretch")),
		"biome": str(resolved.get("biome", "")),
		"area_theme": (resolved.get("area_theme", {}) as Dictionary).duplicate(true),
		"zone_transition": (resolved.get("zone_transition", {}) as Dictionary).duplicate(true),
		"source": {
			"generator": "archetype_based_stretch_v2_systems",
			"seed": int(resolved.get("seed", 0)),
			"complexity_tier": str(resolved.get("complexity_tier", "teaching")),
			"progression_stage": int(resolved.get("progression_stage", 99)),
			"roster": resolved.get("roster", []),
		},
		"spec_integrity": {
			"contract_id": SPEC_INTEGRITY_CONTRACT_ID,
			"party_spawn_clearance_contract_id": PARTY_SPAWN_CLEARANCE_CONTRACT_ID,
			"spatial_socket_contract_id": SPATIAL_SOCKET_CONTRACT_ID,
			"content_navigation_contract_id": CONTENT_NAVIGATION_CONTRACT_ID,
		},
		"settings": resolved,
		"budget": budget.duplicate(true),
		"world_slot": world_slot,
		"anchors": anchors,
		"graybox": graybox,
		"spine_navigation_grid": spine_navigation_grid,
		"navigation_grid": navigation_grid,
		"roompieces": _roompieces_block(layout),
		"spatial_features": spatial_features,
		"themed_landmarks": themed_landmarks,
		"themed_setpieces": themed_setpieces,
		"infrastructure_operations": infrastructure.get("operations", []),
		"nodes": nodes,
		"routes": routes,
		"archetype_chain": archetype_chain,
		"teaching_chain": teaching_chain,
		"composition": composition_summary,
		"systems_contract": systems_contract,
		"topology_contract": topology_contract,
		"palette_usage": palette_usage,
		"headless": {
			"golden_path": _golden_path(nodes),
			"risky_recovery": _risky_recovery(routes, nodes),
			"solution": headless_solution,
			"solution_paths": solution.get("solution_paths", []),
			"solution_summary": {
				"multi_solution": solution.get("multi_solution", false),
				"choice_node_count": solution.get("choice_node_count", 0),
				"choice_nodes": solution.get("choice_nodes", []),
				"branch_contract_valid": solution.get("branch_contract_valid", false),
				"mandatory_branch_action_count": solution.get("mandatory_branch_action_count", 0),
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
			},
			"state_paths": [
				"chunk.generation.spec_id",
				"chunk.generation.route_choice",
				"chunk.generation.shelter_rested",
				"chunk.generation.composition",
				"chunk.generation.composition.random_walk",
				"chunk.generation.unsupported_placeholder_count",
				"chunk.generation.omitted_content_count",
				"chunk.generation.navigation",
				"chunk.generation.spatial_features",
				"chunk.generation.area_theme",
				"chunk.generation.themed_landmarks",
				"chunk.generation.themed_setpieces",
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
	var mode_validation := validate_mode_independent_spec(spec)
	(spec["validation"] as Dictionary)["mode_independence"] = mode_validation
	if not bool(mode_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "mode_independence_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var topology_validation := validate_topology_contract(spec)
	(spec["validation"] as Dictionary)["topology"] = topology_validation
	if not bool(topology_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "topology_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var systems_validation: Dictionary = SystemsCurriculumScript.validate_contract(spec)
	(spec["validation"] as Dictionary)["systems"] = systems_validation
	if not bool(systems_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "systems_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var spatial_validation := validate_spatial_features(spec)
	(spec["validation"] as Dictionary)["spatial_features"] = spatial_validation
	if not bool(spatial_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "spatial_feature_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var integrity_validation := validate_spec_integrity_contract(spec)
	(spec["validation"] as Dictionary)["integrity"] = integrity_validation
	if not bool(integrity_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "spec_integrity_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var content_navigation_validation := validate_realized_content_navigation(spec)
	(spec["validation"] as Dictionary)["realized_content_navigation"] = (
		content_navigation_validation)
	if not bool(content_navigation_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "realized_content_navigation_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var approach_validation := validate_actionable_interaction_approaches(spec)
	(spec["validation"] as Dictionary)["actionable_interaction_approaches"] = (
		approach_validation
	)
	if not bool(approach_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "actionable_interaction_approach_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var spawn_clearance_validation := validate_party_spawn_clearance(spec)
	(spec["validation"] as Dictionary)["party_spawn_clearance"] = (
		spawn_clearance_validation
	)
	if not bool(spawn_clearance_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "party_spawn_clearance_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	var theme_validation := validate_area_theme(spec)
	(spec["validation"] as Dictionary)["area_theme"] = theme_validation
	if not bool(theme_validation.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "area_theme_contract_failed",
			"validation": spec["validation"],
			"draft_spec": spec,
		}
	# The level and the verdict on whether anyone can play it are emitted together. A stretch that
	# cannot be finished, or that can only be finished by bleeding, is answerable HERE rather than
	# after a player has walked into it.
	spec["probe"] = GenerationProbeScript.probe(spec, {"analysis": solution})
	return spec


## Seal a deliberately authored fixed spatial spec through the same current
## acceptance boundary as procedural output.  This is an explicit authoring
## operation, not a persisted-spec repair path: callers supply the authoritative
## grid/nodes, and a disconnected action or stale runtime projection fails rather
## than regenerating or replacing that authored geometry.
static func finalize_authored_fixed_spec(draft: Dictionary) -> Dictionary:
	var spec := draft.duplicate(true)
	var nodes_v: Variant = spec.get("nodes", null)
	var routes_v: Variant = spec.get("routes", null)
	var navigation_v: Variant = spec.get("navigation_grid", null)
	if not (nodes_v is Array) or not (routes_v is Array) \
			or not (navigation_v is Dictionary):
		return {
			"success": false,
			"ok": false,
			"error": "authored_fixed_spec_shape_failed",
			"validation": {
				"valid": false,
				"errors": [
					"Authored fixed specs require nodes, routes, and a navigation grid."
				],
			},
			"draft_spec": spec,
		}

	var nodes := nodes_v as Array
	var routes := routes_v as Array
	var navigation_grid := navigation_v as Dictionary
	var spec_id := str(spec.get("id", "authored_fixed_spec"))
	var settings_v: Variant = spec.get("settings", {})
	var settings := (
		(settings_v as Dictionary).duplicate(true)
		if settings_v is Dictionary else {}
	)
	settings["id"] = spec_id
	settings["title"] = str(spec.get("title", "Authored Fixed Spec"))
	settings["progression_stage"] = maxi(
		1, int(settings.get("progression_stage", 1)))
	spec["settings"] = settings
	spec["schema"] = SPEC_SCHEMA
	spec["biome"] = str(spec.get("biome", ""))
	for empty_array_field in [
		"spatial_features",
		"themed_landmarks",
		"themed_setpieces",
		"infrastructure_operations",
	]:
		if not (spec.get(empty_array_field, null) is Array):
			spec[empty_array_field] = []
	if not (spec.get("area_theme", null) is Dictionary):
		spec["area_theme"] = {}
	if not (spec.get("zone_transition", null) is Dictionary):
		spec["zone_transition"] = {}

	# Systems projection is allowed to remove invented actions from layout-only
	# nodes and to attach only handlers that the production registry implements.
	var catalog := CatalogScript.new()
	spec["systems_contract"] = SystemsCurriculumScript.build_contract(
		catalog, nodes, routes, settings)
	spec["nodes"] = nodes

	var approach_projection := _project_actionable_interaction_approaches(
		nodes, routes, navigation_grid, spec_id)
	if not bool(approach_projection.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "authored_actionable_interaction_approach_failed",
			"validation": {
				"valid": false,
				"errors": approach_projection.get("errors", []),
				"actionable_interaction_approaches": approach_projection,
			},
			"draft_spec": spec,
		}
	spec["nodes"] = nodes

	var content_navigation_projection := _project_realized_content_navigation(
		nodes, navigation_grid)
	if not bool(content_navigation_projection.get("valid", false)):
		return {
			"success": false,
			"ok": false,
			"error": "authored_content_navigation_failed",
			"validation": {
				"valid": false,
				"errors": content_navigation_projection.get("errors", []),
				"realized_content_navigation": content_navigation_projection,
			},
			"draft_spec": spec,
		}
	spec["nodes"] = nodes

	var navigation_branches: Array = navigation_grid.get("branches", [])
	spec["topology_contract"] = _build_topology_contract(
		nodes, routes, navigation_branches, navigation_grid)
	spec["spec_integrity"] = {
		"contract_id": SPEC_INTEGRITY_CONTRACT_ID,
		"party_spawn_clearance_contract_id": PARTY_SPAWN_CLEARANCE_CONTRACT_ID,
		"spatial_socket_contract_id": SPATIAL_SOCKET_CONTRACT_ID,
		"content_navigation_contract_id": CONTENT_NAVIGATION_CONTRACT_ID,
	}
	var graybox_v: Variant = spec.get("graybox", {})
	if graybox_v is Dictionary:
		var graybox := graybox_v as Dictionary
		graybox["navigation_contract_id"] = str(
			navigation_grid.get("contract_id", ""))
		graybox["navigation_node_count"] = nodes.size()
		graybox["navigation_edge_count"] = routes.size()
		graybox["actionable_interaction_approach_count"] = int(
			approach_projection.get("actionable_node_count", 0))
		graybox["realized_content_navigation_count"] = int(
			content_navigation_projection.get(
				"realized_content_placement_count", 0))
		spec["graybox"] = graybox

	var acceptance := validate_spec_acceptance(spec)
	spec["success"] = bool(acceptance.get("valid", false))
	spec["ok"] = bool(acceptance.get("valid", false))
	spec["validation"] = acceptance
	if not bool(acceptance.get("valid", false)):
		spec["error"] = "authored_fixed_spec_acceptance_failed"
	else:
		spec.erase("error")
	return spec


static func _ensure_complete_chain_budget(settings: Dictionary, budget: Dictionary, archetype_chain: Array) -> void:
	if str(settings.get("composition", {}).get("mode", "")) != "chain_nested_poc" or archetype_chain.is_empty():
		return
	var chain_size := 0
	for entry_v in archetype_chain:
		if entry_v is Dictionary and str((entry_v as Dictionary).get("composition_role", "")) == "chain_link":
			chain_size += 1
	if chain_size <= 0:
		chain_size = archetype_chain.size()
	var original_count := int(budget.get("node_count", 6))
	var candidate_count := original_count
	var optional_budget := int(budget.get("optional_node_count", 0))
	while candidate_count < original_count + chain_size + optional_budget + 2:
		var optional_remaining := optional_budget
		var critical_count := 0
		for node_index in range(1, candidate_count - 1):
			var optional := optional_remaining > 0 and node_index % 3 == 0
			if optional:
				optional_remaining -= 1
			else:
				critical_count += 1
		if critical_count >= chain_size and critical_count % chain_size == 0:
			break
		candidate_count += 1
	if candidate_count > original_count:
		budget["node_count"] = candidate_count
		settings["reasoning_budget_added_nodes"] = int(settings.get("reasoning_budget_added_nodes", 0)) + candidate_count - original_count

static func validate_settings(settings: Dictionary) -> Dictionary:
	var catalog := CatalogScript.new()
	var catalog_validation: Dictionary = catalog.validate()
	var errors: Array[String] = []
	if not bool(catalog_validation.get("valid", false)):
		errors.append_array(catalog_validation.get("errors", []))
	# Generation owns fixed content. Economy presets are runtime pressure projections
	# over that content and must be supplied to the preview/playtest host only after
	# a spec has been generated. Rejecting these keys prevents a caller from quietly
	# making a different map, reward set, or solution for Scarcity.
	for runtime_path in _runtime_play_config_paths(settings):
		errors.append(
			"Runtime play configuration '%s' is not a generator setting; apply it to one fixed spec after generation."
			% runtime_path
		)

	var resolved := _resolve_settings(settings)
	resolved["progression_stage"] = _resolve_progression_stage(catalog, resolved)
	_apply_systems_progression_profile(resolved)
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
					elif mode == "required" and not SystemsCurriculumScript.is_procedurally_eligible(value):
						errors.append("Archetype %s is not eligible for procedural generation: %s" % [value, SystemsCurriculumScript.blocked_reason(value)])
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


static func _runtime_play_config_paths(value: Variant, path := "settings") -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key_v in (value as Dictionary).keys():
			var key := str(key_v)
			var child_path := "%s.%s" % [path, key]
			if RUNTIME_ONLY_PLAY_CONFIG_KEYS.has(key):
				result.append(child_path)
			result.append_array(_runtime_play_config_paths((value as Dictionary)[key_v], child_path))
	elif value is Array:
		for index in range((value as Array).size()):
			result.append_array(_runtime_play_config_paths(
				(value as Array)[index], "%s[%d]" % [path, index]
			))
	return result


## A generated spec is fixed content, whether it was produced in memory, supplied
## by a caller, or read back from disk. Keep the same mode-blind rule at all three
## boundaries so serialization cannot become an escape hatch around validate_settings().
static func validate_mode_independent_spec(spec: Dictionary) -> Dictionary:
	var runtime_paths := _runtime_play_config_paths(spec, "spec")
	var errors: Array[String] = []
	for runtime_path in runtime_paths:
		errors.append(
			"Generated content contains runtime play configuration '%s'."
			% runtime_path
		)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"runtime_paths": runtime_paths,
	}


static func _weave_navigation_grid(spine_navigation_grid: Dictionary, settings: Dictionary) -> Dictionary:
	if spine_navigation_grid.is_empty():
		return {}
	var options := {
		"seed": int(settings.get("seed", 0)),
		"tier": str(settings.get("complexity_tier", "standard")),
		"stage": int(settings.get("progression_stage", 99)),
	}
	var spatial_profile: Dictionary = settings.get("spatial_profile", {})
	if spatial_profile.has("branch_room_count"):
		options["count"] = maxi(0, int(spatial_profile.get("branch_room_count", 0)))
	return BranchWeaverScript.weave(spine_navigation_grid, options)


static func _navigation_branch_contracts(branches: Array) -> Array:
	var result: Array = []
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		var branch := branch_v as Dictionary
		result.append({
			"id": str(branch.get("id", "")),
			"role": str(branch.get("role", "")),
			"required_for_progress": bool(branch.get("required_for_progress", false)),
			"neck": (branch.get("neck", []) as Array).duplicate(),
			"cells": (branch.get("cells", []) as Array).duplicate(true),
			"causal_contract": (branch.get("causal_contract", {}) as Dictionary).duplicate(true),
		})
	return result


static func _build_topology_contract(
		nodes: Array,
		routes: Array,
		navigation_branches: Array,
		navigation_grid: Dictionary
) -> Dictionary:
	var semantic_branches := []
	for node_v in nodes:
		if not (node_v is Dictionary) or not bool((node_v as Dictionary).get("optional", false)):
			continue
		semantic_branches.append({
			"node": str((node_v as Dictionary).get("id", "")),
			"role": str((node_v as Dictionary).get("branch_role", "")),
			"required_for_progress": false,
		})
	var topology_routes := []
	for route_v in routes:
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		if str(route.get("topology_role", "")) == "" and str(route.get("kind", "")) != "shortcut":
			continue
		topology_routes.append({
			"route": str(route.get("id", "")),
			"role": str(route.get("topology_role", "")),
			"effect": str(route.get("topology_effect", "")),
			"starts_active": bool(route.get("starts_active", true)),
			"unlock_requires_node": str(route.get("unlock_requires_node", "")),
		})
	return {
		"contract_id": "generated_topology_contract_v1",
		"navigation_grid_field": "navigation_grid",
		"spine_navigation_grid_field": "spine_navigation_grid",
		"branch_weave_contract_id": BranchWeaverScript.BRANCH_WEAVE_CONTRACT_ID,
		"branch_roles": ["mandatory_producer", "optional_risk_reward"],
		"semantic_branches": semantic_branches,
		"navigation_branches": _navigation_branch_contracts(navigation_branches),
		"mandatory_branch_action_count": SolverScript.mandatory_branch_actions(
			navigation_branches, nodes, navigation_grid
		).size(),
		"topology_routes": topology_routes,
		"return_policy": {
			"authority": "runtime_meta_template_climbvine_state",
			"semantic_route_may_unlock": false,
			"kind": "gated_climbvine",
			"role": "recovery_return",
			"starts_active": false,
			"activation_policy": "tend_upper_anchor",
			"activation_character": "peris",
			"traversal_direction": "lower_to_upper",
			"topology_effect": "backtrack_only",
			"allow_forward_drop": false,
		},
		"invariants": {
			"branches_have_semantic_roles": true,
			"forward_routes_cannot_skip_unresolved_nodes": true,
			"recovery_returns_unlock_from_their_later_endpoint": true,
			"always_on_forward_drops_forbidden": true,
		},
	}


## Validate semantic graph shortcuts independently from the spatial template. A forward edge may skip optional
## reward nodes, but it may not jump a required causal beat unless every skipped beat is an explicit prerequisite
## of that edge. Generated recovery routes are later -> earlier, dormant, and unlock only at their later endpoint.
static func validate_topology_contract(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var nodes: Array = spec.get("nodes", [])
	var routes: Array = spec.get("routes", [])
	var node_index := {}
	var optional_by_id := {}
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			continue
		var node := nodes[index] as Dictionary
		var node_id := str(node.get("id", ""))
		if node_id == "":
			continue
		node_index[node_id] = index
		optional_by_id[node_id] = bool(node.get("optional", false))
		if bool(node.get("optional", false)) \
				and str(node.get("branch_role", "")) != "optional_risk_reward":
			errors.append("Optional node '%s' lacks the optional_risk_reward branch role." % node_id)

	var topology_route_count := 0
	for route_v in routes:
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		var route_id := str(route.get("id", "unnamed_route"))
		var from_id := str(route.get("from", ""))
		var to_id := str(route.get("to", ""))
		if not node_index.has(from_id) or not node_index.has(to_id):
			errors.append("Route '%s' references an unknown endpoint." % route_id)
			continue
		var from_index := int(node_index[from_id])
		var to_index := int(node_index[to_id])
		var kind := str(route.get("kind", "safe"))
		var topology_role := str(route.get("topology_role", ""))
		var changes_topology := kind in ["shortcut", "drop"] or topology_role != "" \
				or str(route.get("topology_effect", "")) != ""
		if changes_topology:
			topology_route_count += 1
			if not bool(route.get("cannot_bypass_unresolved", false)):
				errors.append("Topology route '%s' omits the unresolved-blocker invariant." % route_id)
		if kind == "drop":
			errors.append("Route '%s' is a forward drop; generated returns must be gated climbs." % route_id)

		if to_index > from_index + 1:
			var declared_prerequisites := _string_array(route.get("unlock_requires_resolved", []))
			for skipped_index in range(from_index + 1, to_index):
				var skipped := nodes[skipped_index] as Dictionary
				var skipped_id := str(skipped.get("id", ""))
				if not bool(skipped.get("optional", false)) and not declared_prerequisites.has(skipped_id):
					errors.append(
					"Forward route '%s' bypasses unresolved mandatory node '%s'."
					% [route_id, skipped_id]
				)

		if topology_role == "optional_branch_bypass":
			var bypassed_id := str(route.get("bypasses_optional", ""))
			if bypassed_id == "" or not bool(optional_by_id.get(bypassed_id, false)):
				errors.append("Optional bypass '%s' does not bypass an optional node." % route_id)

		if kind == "shortcut" or topology_role == "recovery_return":
			if to_index >= from_index:
				errors.append("Recovery route '%s' is not later-to-earlier backtracking." % route_id)
			if topology_role != "recovery_return" \
					or str(route.get("topology_effect", "")) != "backtrack_only":
				errors.append("Recovery route '%s' lacks a backtrack-only recovery role." % route_id)
			if bool(route.get("starts_active", true)):
				errors.append("Recovery route '%s' starts active." % route_id)
			if str(route.get("unlock_requires_node", "")) != from_id:
				errors.append("Recovery route '%s' does not unlock at its later endpoint." % route_id)
			# A semantic edge is not a mechanism. If a future generated topology really
			# needs to serialize one, it must bind to the exact ClimbvineReturn instance
			# and its physical endpoints; selecting the route itself may never unlock it.
			if str(route.get("runtime_handler", "")) != "climbvine_return_v1" \
					or str(route.get("runtime_mechanism_id", "")) == "" \
					or str(route.get("runtime_source_endpoint", "")) == "" \
					or str(route.get("runtime_target_endpoint", "")) == "" \
					or bool(route.get("unlocks_shortcut", false)):
				errors.append(
					"Recovery route '%s' is prose/metadata rather than an exact climbvine binding."
					% route_id
				)

	var contract: Dictionary = spec.get("topology_contract", {})
	var return_policy: Dictionary = contract.get("return_policy", {})
	if not contract.is_empty():
		if bool(return_policy.get("allow_forward_drop", true)) \
				or bool(return_policy.get("starts_active", true)) \
				or str(return_policy.get("activation_policy", "")) != "tend_upper_anchor" \
				or str(return_policy.get("topology_effect", "")) != "backtrack_only" \
				or str(return_policy.get("authority", "")) \
					!= "runtime_meta_template_climbvine_state" \
				or bool(return_policy.get("semantic_route_may_unlock", true)):
			errors.append("The generated return policy permits an ungated or forward traversal.")

	# Generated navigation is solved as emitted. The runtime may render or warp the
	# grid, but it may not add mandatory rooms after this validation boundary.
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	var has_emitted_weave := (
		str(navigation_grid.get("branch_weave_contract_id", ""))
		== BranchWeaverScript.BRANCH_WEAVE_CONTRACT_ID
		or spec.has("spine_navigation_grid")
	)
	var navigation_branches: Array = navigation_grid.get("branches", [])
	if has_emitted_weave:
		if str(navigation_grid.get("branch_weave_contract_id", "")) \
				!= BranchWeaverScript.BRANCH_WEAVE_CONTRACT_ID:
			errors.append("The authoritative navigation grid lacks the fixed branch-weave contract id.")
		var branch_validation := BranchWeaverScript.validate_branch_contracts(
			navigation_branches, navigation_grid
		)
		for branch_error_v in branch_validation.get("errors", []):
			errors.append("Navigation branch: %s" % str(branch_error_v))

		var spine_navigation_grid: Dictionary = spec.get("spine_navigation_grid", {})
		if not spine_navigation_grid.is_empty() \
				and not (spine_navigation_grid.get("branches", []) as Array).is_empty():
			errors.append("spine_navigation_grid contains woven branches instead of the bare macro-shape spine.")

		var expected_navigation_contracts := _navigation_branch_contracts(
			navigation_branches
		)
		if JSON.stringify(contract.get("navigation_branches", [])) \
				!= JSON.stringify(expected_navigation_contracts):
			errors.append("topology_contract navigation branches differ from the authoritative navigation grid.")

		var expected_branch_actions := SolverScript.mandatory_branch_actions(
			navigation_branches, nodes, navigation_grid
		)
		for branch_action_v in expected_branch_actions:
			var branch_action := branch_action_v as Dictionary
			if str(branch_action.get("before_node", "")) == "":
				errors.append("A mandatory branch action lacks an executable before_node interleave anchor.")
			var affected_node_ids: Array = branch_action.get(
				"affected_node_ids", [])
			var sorted_affected_node_ids := affected_node_ids.duplicate()
			sorted_affected_node_ids.sort()
			if affected_node_ids.is_empty():
				errors.append(
					"A mandatory branch action disconnects no typed interaction destination.")
			elif affected_node_ids != sorted_affected_node_ids:
				errors.append(
					"A mandatory branch action has non-canonical affected_node_ids ordering.")
		var emitted_branch_actions: Array = spec.get("headless", {}).get(
			"solution", {}
		).get("branch_actions", [])
		# Persisted JSON promotes integral numbers to floats (for example, solution_order
		# 0 becomes 0.0). Compare their JSON-normalized Variant trees so serialization-only
		# numeric representation cannot invalidate an otherwise exact action projection.
		if not _serialized_variants_equal(emitted_branch_actions, expected_branch_actions):
			errors.append("The headless solution omits or changes a mandatory navigation-branch action.")
		if int(contract.get("mandatory_branch_action_count", -1)) \
				!= expected_branch_actions.size():
			errors.append("topology_contract reports the wrong mandatory branch-action count.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"topology_route_count": topology_route_count,
		"navigation_branch_count": navigation_branches.size(),
		"mandatory_branch_action_count": SolverScript.mandatory_branch_actions(
			navigation_branches, nodes, navigation_grid
		).size(),
	}


static func _serialized_variants_equal(left: Variant, right: Variant) -> bool:
	return (
		JSON.parse_string(JSON.stringify(left))
		== JSON.parse_string(JSON.stringify(right))
	)


## Public verifier used by batch tools and QA without duplicating the contract law.
static func validate_systems_contract(spec: Dictionary) -> Dictionary:
	return SystemsCurriculumScript.validate_contract(spec)


static func validate_spec_integrity_contract(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var integrity_v: Variant = spec.get("spec_integrity", null)
	if not (integrity_v is Dictionary):
		return {
			"valid": false,
			"errors": ["Generated stretch has no spec-integrity contract."],
		}
	var integrity := integrity_v as Dictionary
	var required := {
		"contract_id": SPEC_INTEGRITY_CONTRACT_ID,
		"party_spawn_clearance_contract_id": PARTY_SPAWN_CLEARANCE_CONTRACT_ID,
		"spatial_socket_contract_id": SPATIAL_SOCKET_CONTRACT_ID,
		"content_navigation_contract_id": CONTENT_NAVIGATION_CONTRACT_ID,
	}
	for key_v in required.keys():
		var key := str(key_v)
		if str(integrity.get(key, "")) != str(required[key_v]):
			errors.append(
				"Spec-integrity contract uses the wrong %s." % key)
	return {"valid": errors.is_empty(), "errors": errors}


## One acceptance boundary for generated results, persisted JSON, editor saves,
## and inline configured specs. Keeping the sections visible lets callers report
## the exact rejected contract without choosing a weaker subset of validators.
static func validate_spec_acceptance(spec: Dictionary) -> Dictionary:
	var sections := {
		"integrity": validate_spec_integrity_contract(spec),
		"mode_independence": validate_mode_independent_spec(spec),
		"topology": validate_topology_contract(spec),
		"systems": validate_systems_contract(spec),
		"spatial_features": validate_spatial_features(spec),
		"actionable_interaction_approaches": (
			validate_actionable_interaction_approaches(spec)),
		"party_spawn_clearance": validate_party_spawn_clearance(spec),
		"realized_content_navigation": validate_realized_content_navigation(spec),
		"area_theme": validate_area_theme(spec),
	}
	var errors: Array[String] = []
	for section_name_v in sections.keys():
		var section_name := str(section_name_v)
		var section := sections[section_name_v] as Dictionary
		if bool(section.get("valid", false)):
			continue
		var section_errors_v: Variant = section.get("errors", [])
		if not (section_errors_v is Array) or (section_errors_v as Array).is_empty():
			errors.append("%s contract failed." % section_name)
			continue
		for error_v in section_errors_v as Array:
			errors.append("%s: %s" % [section_name, str(error_v)])
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"sections": sections,
	}


## Public verifier for generated feature prefabs. A platform is only valid when it replaces real walkable cells,
## assigns its archetype content to explicit sockets, and names the causal relationship it is meant to expose.
static func validate_spatial_features(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var features: Array = spec.get("spatial_features", [])
	var nodes_by_id := {}
	for node_v in spec.get("nodes", []):
		if node_v is Dictionary:
			nodes_by_id[str((node_v as Dictionary).get("id", ""))] = node_v
	var grid = GridWorld.from_data(spec.get("navigation_grid", {}))
	var seen_nodes := {}
	for raw_feature in features:
		if not (raw_feature is Dictionary):
			errors.append("Spatial feature is not a dictionary")
			continue
		var feature := raw_feature as Dictionary
		var feature_id := str(feature.get("id", "spatial_feature"))
		var node_id := str(feature.get("node_id", ""))
		if not nodes_by_id.has(node_id):
			errors.append("%s references unknown node %s" % [feature_id, node_id])
			continue
		if seen_nodes.has(node_id):
			errors.append("Node %s owns more than one primary spatial feature" % node_id)
		seen_nodes[node_id] = true
		var node := nodes_by_id[node_id] as Dictionary
		var node_feature_v: Variant = node.get("spatial_feature", null)
		if not (node_feature_v is Dictionary) \
				or not _serialized_variants_equal(node_feature_v, feature):
			errors.append(
				"%s diverges from its node-owned spatial feature receipt" % feature_id)
		if str(node.get("role", "")) in ["boundary", "shelter", "shelter_arrival"]:
			errors.append("%s occupies a boundary/shelter node" % feature_id)
		var scene_path := str(feature.get("scene", ""))
		# Exported resources live inside the PCK and are not ordinary filesystem files.
		# ResourceLoader is the authoritative existence check for authored scenes in both
		# editor/headless runs and Web exports.
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			errors.append("%s has no authored scene" % feature_id)
		var floor_cells: Array = feature.get("floor_cells", [])
		if floor_cells.size() < 9:
			errors.append("%s replaces fewer than nine standing cells" % feature_id)
		var level := int(feature.get("elevation_index", 0))
		for cell_v in floor_cells:
			if not (cell_v is Array) or (cell_v as Array).size() < 2:
				errors.append("%s has a malformed floor cell" % feature_id)
				continue
			var cell := Vector2i(int(cell_v[0]), int(cell_v[1]))
			if not grid.is_walkable(cell.x, cell.y, {}, {}, level):
				errors.append("%s replaces non-walkable cell %s" % [feature_id, str(cell)])
		var assignments: Array = feature.get("socket_assignments", [])
		if assignments.size() < 2:
			errors.append("%s does not spatially separate at least two system elements" % feature_id)
		_validate_spatial_feature_socket_assignments(
			feature, node, feature_id, errors)
		var assignment_ids := []
		for assignment_v in assignments:
			if assignment_v is Dictionary:
				assignment_ids.append(str((assignment_v as Dictionary).get("socket", "")))
		var runtime_binding: Dictionary = feature.get("runtime_binding", {})
		for key in [
			"binding_id",
			"runtime_handler",
			"mechanism_id",
			"source_socket_id",
			"effect_socket_id",
			"completion_predicate",
		]:
			if str(runtime_binding.get(key, "")).strip_edges() == "":
				errors.append("%s runtime binding is missing %s" % [feature_id, key])
		if str(runtime_binding.get("runtime_handler", "")) \
				!= str(node.get("runtime_handler", "")):
			errors.append("%s runtime binding is not owned by its node handler" % feature_id)
		for socket_key in ["source_socket_id", "effect_socket_id"]:
			var socket_id := str(runtime_binding.get(socket_key, ""))
			if socket_id != "" and not assignment_ids.has(socket_id):
				errors.append("%s binds missing socket %s" % [feature_id, socket_id])
		var causal_model: Dictionary = feature.get("causal_model", {})
		for key in ["primary_insight", "leverage", "failure_prediction"]:
			if str(causal_model.get(key, "")).strip_edges() == "":
				errors.append("%s causal model is missing %s" % [feature_id, key])
		if (causal_model.get("emergent_inputs", []) as Array).size() < 3:
			errors.append("%s does not name enough interacting systems for emergence" % feature_id)
	return {"valid": errors.is_empty(), "errors": errors, "feature_count": features.size()}


static func _validate_spatial_feature_socket_assignments(
		feature: Dictionary,
		node: Dictionary,
		feature_id: String,
		errors: Array[String]
	) -> void:
	var content_sockets_v: Variant = feature.get("content_sockets", null)
	if not (content_sockets_v is Dictionary):
		errors.append("%s has no typed content-socket catalog" % feature_id)
		return
	var content_sockets := content_sockets_v as Dictionary
	var assignments_v: Variant = feature.get("socket_assignments", null)
	if not (assignments_v is Array):
		errors.append("%s has no socket-assignment array" % feature_id)
		return
	var assignments_by_socket := {}
	for assignment_v in assignments_v as Array:
		if not (assignment_v is Dictionary):
			errors.append("%s has a malformed socket assignment" % feature_id)
			continue
		var assignment := assignment_v as Dictionary
		var socket_id := str(assignment.get("socket", ""))
		if socket_id == "":
			errors.append("%s has an unnamed socket assignment" % feature_id)
			continue
		if assignments_by_socket.has(socket_id):
			errors.append("%s assigns socket %s more than once" % [feature_id, socket_id])
			continue
		assignments_by_socket[socket_id] = assignment

	var realized_socket_ids := {}
	var realized_count := 0
	var node_position := _array_to_vec3(node.get("position", []), Vector3.INF)
	for placement_v in node.get("content_placements", []):
		if not (placement_v is Dictionary):
			errors.append("%s owns a malformed content placement" % feature_id)
			continue
		var placement := placement_v as Dictionary
		var category := str(placement.get("category", ""))
		var content_id := str(placement.get("id", ""))
		if not RuntimeRegistryScript.generated_content_is_realized(category, content_id):
			continue
		realized_count += 1
		var socket_id := str(placement.get("socket_id", ""))
		if socket_id == "":
			errors.append(
				"%s leaves realized %s/%s without an authored socket"
				% [feature_id, category, content_id])
			continue
		if realized_socket_ids.has(socket_id):
			errors.append("%s seats more than one placement on %s" % [feature_id, socket_id])
			continue
		realized_socket_ids[socket_id] = true
		var socket_index := _spatial_socket_index(socket_id, category)
		var category_sockets_v: Variant = content_sockets.get(category, null)
		if socket_index < 0 or not (category_sockets_v is Array) \
				or socket_index >= (category_sockets_v as Array).size():
			errors.append(
				"%s seats %s/%s on incompatible socket %s"
				% [feature_id, category, content_id, socket_id])
			continue
		var assignment_v: Variant = assignments_by_socket.get(socket_id, null)
		if not (assignment_v is Dictionary):
			errors.append(
				"%s has no assignment receipt for realized %s/%s on %s"
				% [feature_id, category, content_id, socket_id])
			continue
		var assignment := assignment_v as Dictionary
		if str(assignment.get("category", "")) != category \
				or str(assignment.get("content_id", "")) != content_id \
				or not _serialized_variants_equal(
					assignment.get("position", null), placement.get("position", null)):
			errors.append(
				"%s assignment %s does not exactly describe its realized placement"
				% [feature_id, socket_id])
		if node_position.is_finite():
			var socket_offset := _array_to_vec3(
				(category_sockets_v as Array)[socket_index], Vector3.INF)
			var size := _array_to_vec3(placement.get("size", []), Vector3.INF)
			var placed_position := _array_to_vec3(
				placement.get("position", []), Vector3.INF)
			if socket_offset.is_finite() and size.is_finite():
				socket_offset.y = size.y * 0.5
				var expected_position := node_position + socket_offset
				if not placed_position.is_finite() \
						or not placed_position.is_equal_approx(expected_position):
					errors.append(
						"%s placement on %s has drifted from its authored socket"
						% [feature_id, socket_id])
	for socket_id_v in assignments_by_socket.keys():
		if not realized_socket_ids.has(str(socket_id_v)):
			errors.append(
				"%s retains stale assignment %s with no realized placement"
				% [feature_id, str(socket_id_v)])
	if assignments_by_socket.size() != realized_count:
		errors.append(
			"%s has %d assignments for %d realized placements"
			% [feature_id, assignments_by_socket.size(), realized_count])


static func _spatial_socket_index(socket_id: String, category: String) -> int:
	var prefix := str({
		"flora": "flora", "enemies": "enemy", "structures": "structure",
	}.get(category, ""))
	if prefix == "" or not socket_id.begins_with("%s_" % prefix):
		return -1
	var index_text := socket_id.trim_prefix("%s_" % prefix)
	if not index_text.is_valid_int():
		return -1
	var index := int(index_text)
	return index if socket_id == "%s_%d" % [prefix, index] else -1


## Public validation boundary for generated action navigation.  A semantic node
## is executable only when its visible source is projected onto a walkable
## `(cell, level)` and every accepted arrival vertex is connected to the prior
## required action (or the entry for the first action).  Requiring an alternate
## vertex is what keeps a normal full-party Rally from turning the source into a
## permanently occupied singleton destination.
static func validate_actionable_interaction_approaches(
	spec: Dictionary
	) -> Dictionary:
	var errors: Array[String] = []
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	if str(navigation_grid.get("contract_id", "")) \
			!= GridWorld.GRID_DATA_CONTRACT_ID:
		return {
			"valid": false,
			"errors": ["Generated stretch has no unified navigation grid."],
			"actionable_node_count": 0,
		}
	var grid := GridWorld.from_data(navigation_grid)
	var nodes: Array = spec.get("nodes", [])
	var spec_id := str(spec.get("id", ""))
	var entry_node := _find_node_in_list(nodes, "entry")
	var entry_vertex := _project_reference_vertex(grid, entry_node)
	if entry_vertex.is_empty():
		errors.append("Generated entry has no walkable graph vertex on its declared level.")
	var required_from_vertex := entry_vertex
	var required_from_node_id := "entry"
	var expected_component_id := _interaction_component_id(entry_vertex)
	var actionable_count := 0
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var handler_id := RuntimeRegistryScript.handler_for_node(node, spec_id)
		if handler_id == "":
			continue
		actionable_count += 1
		var node_id := str(node.get("id", "node"))
		var contract_v: Variant = node.get("interaction_approach", {})
		if not (contract_v is Dictionary):
			errors.append("%s has no interaction approach dictionary." % node_id)
			continue
		var contract := contract_v as Dictionary
		if str(contract.get("contract_id", "")) \
				!= INTERACTION_APPROACH_CONTRACT_ID:
			errors.append("%s uses an unknown interaction approach contract." % node_id)
		if str(contract.get("handler_id", "")) != handler_id:
			errors.append("%s interaction approach names the wrong runtime handler." % node_id)
		if str(contract.get("required_from_node_id", "")) != required_from_node_id:
			errors.append(
				"%s interaction approach is not anchored to required predecessor %s."
				% [node_id, required_from_node_id]
			)
		if str(contract.get("component_id", "")) != expected_component_id:
			errors.append("%s interaction approach names the wrong graph component." % node_id)
		var interaction_radius_v: Variant = contract.get("interaction_radius", null)
		var interaction_radius := (
			float(interaction_radius_v)
			if _interaction_finite_number(interaction_radius_v) else NAN
		)
		if not contract.has("interaction_radius") \
				or not _interaction_finite_number(interaction_radius_v) \
				or not is_equal_approx(
					interaction_radius, GENERATED_INTERACTION_RADIUS):
			errors.append(
				"%s interaction approach does not persist the shipped interaction radius."
				% node_id
			)
		var acceptance_radius_v: Variant = contract.get("acceptance_radius", null)
		var acceptance_radius := (
			float(acceptance_radius_v)
			if _interaction_finite_number(acceptance_radius_v) else NAN
		)
		if not contract.has("acceptance_radius") \
				or not _interaction_finite_number(acceptance_radius_v) \
				or not is_equal_approx(
					acceptance_radius, GENERATED_INTERACTION_ACCEPTANCE_RADIUS):
			errors.append(
				"%s interaction approach does not persist the shipped acceptance radius."
				% node_id
			)
		var declared_from := _interaction_vertex_from_data(
			contract.get("required_from_vertex", {})
		)
		if not _interaction_vertices_equal(declared_from, required_from_vertex):
			errors.append(
				"%s interaction approach does not retain its predecessor graph vertex."
				% node_id
			)
		var component_anchor := _interaction_vertex_from_data(
			contract.get("component_anchor", {})
		)
		if not _interaction_vertices_equal(component_anchor, entry_vertex):
			errors.append(
				"%s interaction approach does not retain the entry component anchor."
				% node_id
			)
		var primary := _interaction_vertex_from_data(
			contract.get("approach_vertex", {})
		)
		if primary.is_empty() or not _interaction_vertex_walkable(grid, primary):
			errors.append("%s primary interaction approach is not walkable." % node_id)
			continue
		var primary_cell: Vector2i = primary.get("cell", Vector2i.ZERO)
		var primary_level := int(primary.get("level", -1))
		var source_position := _array_to_vec3(
			node.get("approach_position", []), Vector3.INF
		)
		if not source_position.is_finite() \
				or grid.world_to_grid(source_position) != primary_cell \
				or grid.level_for_y(source_position.y) != primary_level \
				or not source_position.is_equal_approx(
					grid.grid_to_world(primary_cell, primary_level)):
			errors.append(
				"%s visible interaction source is not built from its primary graph vertex."
				% node_id
			)
		var region_v: Variant = contract.get("region_vertices", [])
		if not (region_v is Array):
			errors.append("%s interaction region is not an array." % node_id)
			continue
		var region := region_v as Array
		if region.size() < 2:
			errors.append(
				"%s interaction region has no alternate arrival when Rally occupies its primary."
				% node_id
			)
		var primary_count := 0
		var seen_vertices := {}
		for region_index in range(region.size()):
			var vertex_v: Variant = region[region_index]
			var vertex := _interaction_vertex_from_data(vertex_v)
			if vertex.is_empty():
				errors.append("%s interaction region contains malformed graph data." % node_id)
				continue
			if _interaction_vertices_equal(vertex, primary):
				primary_count += 1
				if region_index != 0:
					errors.append(
					"%s interaction region does not place its primary vertex first."
					% node_id
				)
			var vertex_key := _interaction_vertex_key(vertex)
			if seen_vertices.has(vertex_key):
				errors.append("%s interaction region repeats vertex %s." % [node_id, vertex_key])
				continue
			seen_vertices[vertex_key] = true
			if not _interaction_vertex_walkable(grid, vertex):
				errors.append("%s interaction region contains non-walkable %s." % [node_id, vertex_key])
				continue
			var region_cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
			var region_level := int(vertex.get("level", -1))
			if region_level != primary_level:
				errors.append("%s interaction region crosses an unannotated floor." % node_id)
				continue
			var region_world := grid.grid_to_world(region_cell, region_level)
			if Vector2(region_world.x - source_position.x,
					region_world.z - source_position.z).length() \
					> GENERATED_INTERACTION_ACCEPTANCE_RADIUS + 0.001:
				errors.append("%s interaction region exceeds the source's physical reach." % node_id)
			if required_from_vertex.is_empty() \
					or not _interaction_vertices_connected(
						grid, required_from_vertex, vertex):
				errors.append(
					"%s interaction region vertex %s is unreachable from %s."
					% [node_id, vertex_key, required_from_node_id]
				)
		if primary_count == 0:
			errors.append("%s interaction region omits its primary vertex." % node_id)
		elif primary_count > 1:
			errors.append("%s interaction region repeats its primary vertex." % node_id)
		if _node_updates_required_interaction_predecessor(node):
			required_from_vertex = primary
			required_from_node_id = node_id
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"actionable_node_count": actionable_count,
		"component_id": expected_component_id,
	}


## Project every actionable node into the final authoritative navigation graph.
## This runs after branch weaving, so the contract cannot accidentally describe
## the pre-weave spine while gameplay routes on a different graph.
static func _project_actionable_interaction_approaches(
	nodes: Array,
	_routes: Array,
	navigation_grid: Dictionary,
	spec_id: String,
	only_missing := false
	) -> Dictionary:
	var errors: Array[String] = []
	if str(navigation_grid.get("contract_id", "")) \
			!= GridWorld.GRID_DATA_CONTRACT_ID:
		return {
			"valid": false,
			"errors": ["Cannot project actions without a unified navigation grid."],
			"actionable_node_count": 0,
		}
	var grid := GridWorld.from_data(navigation_grid)
	var entry_node := _find_node_in_list(nodes, "entry")
	var entry_vertex := _project_reference_vertex(grid, entry_node)
	if entry_vertex.is_empty():
		return {
			"valid": false,
			"errors": ["Generated entry cannot be projected onto its declared navigation level."],
			"actionable_node_count": 0,
		}
	var required_from_vertex := entry_vertex
	var required_from_node_id := "entry"
	var component_id := _interaction_component_id(entry_vertex)
	var actionable_count := 0
	for node_index in range(nodes.size()):
		if not (nodes[node_index] is Dictionary):
			continue
		var node := nodes[node_index] as Dictionary
		var handler_id := RuntimeRegistryScript.handler_for_node(node, spec_id)
		if handler_id == "":
			continue
		actionable_count += 1
		var node_id := str(node.get("id", "node"))
		var existing_v: Variant = node.get("interaction_approach", null)
		if only_missing and node.has("interaction_approach"):
			# Presence is an explicit authored claim even when its value is {}, null,
			# an array, or a string. Preserve it for fail-closed validation; legacy
			# migration is allowed only when the key itself is absent.
			if existing_v is Dictionary:
				var existing_primary := _interaction_vertex_from_data(
					(existing_v as Dictionary).get("approach_vertex", {})
				)
				if _node_updates_required_interaction_predecessor(node) \
						and not existing_primary.is_empty():
					required_from_vertex = existing_primary
					required_from_node_id = node_id
			continue
		var declared_level := int(node.get("elevation_index", 0))
		var authored_position := _array_to_vec3(
			node.get("approach_position", node.get("position", [])), Vector3.INF
		)
		if not authored_position.is_finite():
			errors.append("%s has no finite authored interaction approach." % node_id)
			continue
		var nearby := _walkable_interaction_vertices(
			grid,
			authored_position,
			declared_level,
			GENERATED_INTERACTION_ACCEPTANCE_RADIUS
		)
		var reachable: Array[Dictionary] = []
		for vertex_v in nearby:
			var vertex := vertex_v as Dictionary
			if _interaction_vertices_connected(grid, required_from_vertex, vertex):
				reachable.append(vertex)
		if reachable.is_empty():
			errors.append(
				"%s has no walkable interaction approach reachable from %s."
				% [node_id, required_from_node_id]
			)
			continue
		var primary := reachable[0]
		var primary_cell: Vector2i = primary.get("cell", Vector2i.ZERO)
		var primary_world := grid.grid_to_world(primary_cell, declared_level)
		var region_candidates := _walkable_interaction_vertices(
			grid,
			primary_world,
			declared_level,
			GENERATED_INTERACTION_ACCEPTANCE_RADIUS
		)
		var region: Array[Dictionary] = []
		for vertex_v in region_candidates:
			var vertex := vertex_v as Dictionary
			if _interaction_vertices_connected(grid, required_from_vertex, vertex):
				region.append(vertex)
		if region.size() < 2:
			errors.append(
				"%s has no alternate reachable interaction arrival for a rallied party."
				% node_id
			)
			continue
		# The primary is the first item because the region sorter measures from its
		# exact cell centre. Persist arrays, not Vector2i, so JSON replay is stable.
		var exported_region: Array = []
		for vertex_v in region:
			exported_region.append(_interaction_vertex_to_data(vertex_v))
		node["approach_position"] = _vec3_to_array(primary_world)
		node["interaction_approach"] = {
			"contract_id": INTERACTION_APPROACH_CONTRACT_ID,
			"handler_id": handler_id,
			"required_from_node_id": required_from_node_id,
			"required_from_vertex": _interaction_vertex_to_data(required_from_vertex),
			"component_id": component_id,
			"component_anchor": _interaction_vertex_to_data(entry_vertex),
			"approach_vertex": _interaction_vertex_to_data(primary),
			"region_vertices": exported_region,
			"interaction_radius": GENERATED_INTERACTION_RADIUS,
			"acceptance_radius": GENERATED_INTERACTION_ACCEPTANCE_RADIUS,
		}
		nodes[node_index] = node
		if _node_updates_required_interaction_predecessor(node):
			required_from_vertex = primary
			required_from_node_id = node_id
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"actionable_node_count": actionable_count,
		"component_id": component_id,
	}


static func _node_updates_required_interaction_predecessor(node: Dictionary) -> bool:
	return not bool(node.get("optional", false)) \
		and bool(node.get("runtime_progression_required", true))


static func _project_reference_vertex(grid: GridWorld, node: Dictionary) -> Dictionary:
	if node.is_empty():
		return {}
	var position := _array_to_vec3(
		node.get("approach_position", node.get("position", [])), Vector3.INF
	)
	var level := int(node.get("elevation_index", 0))
	if not position.is_finite() or level < 0 or level >= grid.level_count:
		return {}
	var requested := grid.world_to_grid(position)
	var cell := grid.nearest_walkable_cell(
		requested, level, maxi(grid.width, grid.height)
	)
	if not grid.is_walkable(cell.x, cell.y, {}, {}, level):
		return {}
	return {"cell": cell, "level": level}


static func _walkable_interaction_vertices(
	grid: GridWorld,
	center: Vector3,
	level: int,
	radius: float
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not center.is_finite() or level < 0 or level >= grid.level_count:
		return result
	var center_cell := grid.world_to_grid(center)
	var search_radius := int(ceil(radius / maxf(grid.cell_size, 0.001))) + 1
	for dz in range(-search_radius, search_radius + 1):
		for dx in range(-search_radius, search_radius + 1):
			var cell := center_cell + Vector2i(dx, dz)
			if not grid.is_walkable(cell.x, cell.y, {}, {}, level):
				continue
			var world := grid.grid_to_world(cell, level)
			var distance := Vector2(
				world.x - center.x, world.z - center.z
			).length()
			if distance > radius + 0.001:
				continue
			result.append({
				"cell": cell,
				"level": level,
				"distance": distance,
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := float(a.get("distance", INF))
		var b_distance := float(b.get("distance", INF))
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		var a_cell: Vector2i = a.get("cell", Vector2i.ZERO)
		var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
	)
	for vertex in result:
		vertex.erase("distance")
	return result


static func _interaction_vertex_from_data(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var raw := value as Dictionary
	var cell_v: Variant = raw.get("cell", null)
	var cell: Vector2i
	if cell_v is Vector2i:
		cell = cell_v as Vector2i
	elif cell_v is Array and (cell_v as Array).size() == 2 \
			and _interaction_integral_component((cell_v as Array)[0]) \
			and _interaction_integral_component((cell_v as Array)[1]):
		cell = Vector2i(
			int((cell_v as Array)[0]), int((cell_v as Array)[1])
		)
	else:
		return {}
	if not raw.has("level") \
			or not _interaction_integral_component(raw.get("level", null)):
		return {}
	return {"cell": cell, "level": int(raw.get("level", -1))}


static func _interaction_integral_component(value: Variant) -> bool:
	if not _interaction_finite_number(value):
		return false
	var number := float(value)
	return number >= -2147483648.0 \
		and number <= 2147483647.0 \
		and number == floorf(number)


static func _interaction_finite_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return (value_type == TYPE_INT or value_type == TYPE_FLOAT) \
		and is_finite(float(value))


static func _interaction_vertex_to_data(vertex: Dictionary) -> Dictionary:
	var normalized := _interaction_vertex_from_data(vertex)
	if normalized.is_empty():
		return {}
	var cell: Vector2i = normalized.get("cell", Vector2i.ZERO)
	return {"cell": [cell.x, cell.y], "level": int(normalized.get("level", 0))}


static func _interaction_vertex_key(vertex: Dictionary) -> String:
	var normalized := _interaction_vertex_from_data(vertex)
	if normalized.is_empty():
		return "invalid"
	var cell: Vector2i = normalized.get("cell", Vector2i.ZERO)
	return "%d:%d:%d" % [int(normalized.get("level", -1)), cell.x, cell.y]


static func _interaction_component_id(entry_vertex: Dictionary) -> String:
	return "entry_component:%s" % _interaction_vertex_key(entry_vertex)


static func _interaction_vertices_equal(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() \
		and int(a.get("level", -1)) == int(b.get("level", -1)) \
		and a.get("cell", Vector2i(-1, -1)) == b.get("cell", Vector2i(-2, -2))


static func _interaction_vertex_walkable(
	grid: GridWorld, vertex: Dictionary
	) -> bool:
	var normalized := _interaction_vertex_from_data(vertex)
	if normalized.is_empty():
		return false
	var cell: Vector2i = normalized.get("cell", Vector2i.ZERO)
	var level := int(normalized.get("level", -1))
	return level >= 0 and level < grid.level_count \
		and grid.is_walkable(cell.x, cell.y, {}, {}, level)


static func _interaction_vertices_connected(
	grid: GridWorld, from_vertex: Dictionary, to_vertex: Dictionary
	) -> bool:
	var from_normalized := _interaction_vertex_from_data(from_vertex)
	var to_normalized := _interaction_vertex_from_data(to_vertex)
	if not _interaction_vertex_walkable(grid, from_normalized) \
			or not _interaction_vertex_walkable(grid, to_normalized):
		return false
	var from_cell: Vector2i = from_normalized.get("cell", Vector2i.ZERO)
	var to_cell: Vector2i = to_normalized.get("cell", Vector2i.ZERO)
	return not grid.find_multi_level_plan(
		from_cell,
		int(from_normalized.get("level", 0)),
		to_cell,
		int(to_normalized.get("level", 0))
	).is_empty()


## Seat each runtime-bound content object on a real vertex in its owning room
## before a receipt is projected. Generated visuals and navigation therefore
## share one authored position; there is no runtime-only nearest-cell snap.
static func _place_realized_content_on_navigation(
		nodes: Array,
		navigation_grid: Dictionary,
		slot_cells: Dictionary,
		anchors: Dictionary
	) -> Dictionary:
	var errors: Array[String] = []
	if str(navigation_grid.get("contract_id", "")) \
			!= GridWorld.GRID_DATA_CONTRACT_ID:
		return {
			"valid": false,
			"errors": [
				"Cannot place realized content without a unified navigation grid."
			],
			"realized_content_placement_count": 0,
			"moved_placement_count": 0,
		}
	var grid := GridWorld.from_data(navigation_grid)
	var entry_vertex := _project_reference_vertex(
		grid, _find_node_in_list(nodes, "entry"))
	if entry_vertex.is_empty():
		return {
			"valid": false,
			"errors": [
				"Cannot place realized content without a walkable entry vertex."
			],
			"realized_content_placement_count": 0,
			"moved_placement_count": 0,
		}
	var used_vertices := {}
	var spawn_positions := _party_spawn_positions(anchors)
	var realized_count := 0
	var moved_count := 0
	for node_index in range(nodes.size()):
		if not (nodes[node_index] is Dictionary):
			continue
		var node := nodes[node_index] as Dictionary
		var node_id := str(node.get("id", "node"))
		var candidates := _realized_content_room_vertices(
			node,
			slot_cells.get(node_id, {}) as Dictionary,
			grid,
			entry_vertex
		)
		var placements: Array = node.get("content_placements", [])
		for placement_index in range(placements.size()):
			if not (placements[placement_index] is Dictionary):
				continue
			var placement := placements[placement_index] as Dictionary
			var category := str(placement.get("category", ""))
			var content_id := str(placement.get("id", ""))
			if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id):
				continue
			realized_count += 1
			var authored_position := _placement_world_position(placement, node)
			if not authored_position.is_finite():
				errors.append(
					"%s/%s: Placement has no finite authored position."
					% [node_id, content_id])
				continue
			var ordered_candidates: Array = candidates.duplicate(true)
			for candidate_v in ordered_candidates:
				if not (candidate_v is Dictionary):
					continue
				var candidate := candidate_v as Dictionary
				var candidate_world: Vector3 = candidate.get(
					"world", Vector3.INF) as Vector3
				candidate["distance"] = Vector2(
					candidate_world.x - authored_position.x,
					candidate_world.z - authored_position.z
				).length()
			ordered_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_distance := float(a.get("distance", INF))
				var b_distance := float(b.get("distance", INF))
				if not is_equal_approx(a_distance, b_distance):
					return a_distance < b_distance
				var a_cell: Vector2i = a.get("cell", Vector2i.ZERO)
				var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
				return a_cell.y < b_cell.y \
					or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
			)
			var chosen := {}
			for candidate_v in ordered_candidates:
				if not (candidate_v is Dictionary):
					continue
				var candidate := candidate_v as Dictionary
				var vertex := {
					"cell": candidate.get("cell", Vector2i.ZERO),
					"level": int(candidate.get("level", -1)),
				}
				var vertex_key := _interaction_vertex_key(vertex)
				if used_vertices.has(vertex_key):
					continue
				var vertex_world: Vector3 = candidate.get(
					"world", Vector3.INF) as Vector3
				if not vertex_world.is_finite():
					continue
				var placed_position := Vector3(
					vertex_world.x, authored_position.y, vertex_world.z)
				var candidate_placement := placement.duplicate(true)
				candidate_placement["position"] = _vec3_to_array(placed_position)
				if not spawn_positions.is_empty() \
						and _placement_overlaps_party_spawn(
							candidate_placement, node, spawn_positions):
					continue
				var expected := _expected_realized_content_navigation(
					candidate_placement, node, grid, entry_vertex)
				if not bool(expected.get("valid", false)):
					continue
				chosen = {
					"position": placed_position,
					"vertex_key": vertex_key,
				}
				break
			if chosen.is_empty():
				errors.append(
					"%s/%s: No distinct reachable walkable vertex in the owning room can seat the visible content."
					% [node_id, content_id])
				continue
			var placed_position: Vector3 = chosen.get(
				"position", authored_position) as Vector3
			var node_position := _array_to_vec3(
				node.get("position", []), Vector3.INF)
			placement["position"] = _vec3_to_array(placed_position)
			if node_position.is_finite():
				placement["local_offset"] = _vec3_to_array(
					placed_position - node_position)
			placement.erase("navigation")
			used_vertices[str(chosen.get("vertex_key", ""))] = true
			if Vector2(
				placed_position.x - authored_position.x,
				placed_position.z - authored_position.z
			).length() > 0.001:
				moved_count += 1
			placements[placement_index] = placement
			node = _move_realized_content_socket_with_placement(node, placement)
		node["content_placements"] = placements
		nodes[node_index] = node
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"realized_content_placement_count": realized_count,
		"moved_placement_count": moved_count,
	}


## Candidate vertices are restricted to the room-piece mask when WFC data is
## available. The legacy rasterizer has no mask receipt, so its node footprint is
## the equivalent owning-room boundary.
static func _realized_content_room_vertices(
		node: Dictionary,
		slot_cell: Dictionary,
		grid: GridWorld,
		entry_vertex: Dictionary
	) -> Array:
	var result: Array = []
	var level_v: Variant = node.get("elevation_index", null)
	if not _interaction_integral_component(level_v):
		return result
	var level := int(level_v)
	if level < 0 or level >= grid.level_count:
		return result
	if not slot_cell.is_empty():
		var origin_v: Variant = slot_cell.get("origin_cell", null)
		var rows_v: Variant = slot_cell.get("walkable", null)
		if origin_v is Array and (origin_v as Array).size() >= 2 \
				and rows_v is Array:
			var origin_cell := Vector2i(
				int((origin_v as Array)[0]), int((origin_v as Array)[1]))
			var graph_origin_cell := Vector2i(
				roundi(grid.origin.x / maxf(grid.cell_size, 0.001)),
				roundi(grid.origin.z / maxf(grid.cell_size, 0.001)))
			var rows := rows_v as Array
			for row_index in range(rows.size()):
				var row := str(rows[row_index])
				for column_index in range(row.length()):
					if row[column_index] != ".":
						continue
					var cell := Vector2i(
						origin_cell.x + column_index - graph_origin_cell.x,
						origin_cell.y + row_index - graph_origin_cell.y)
					var world := grid.grid_to_world(cell, level)
					_append_realized_content_vertex(
						result, world, level, grid, entry_vertex)
			return result
	var node_position := _array_to_vec3(
		node.get("position", []), Vector3.INF)
	var footprint := _array_to_vec3(
		node.get("footprint", []), Vector3.INF)
	if not node_position.is_finite() or not footprint.is_finite():
		return result
	for z in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, z)
			var world := grid.grid_to_world(cell, level)
			if absf(world.x - node_position.x) > footprint.x * 0.5 + 0.001 \
					or absf(world.z - node_position.z) > footprint.z * 0.5 + 0.001:
				continue
			_append_realized_content_vertex(
				result, world, level, grid, entry_vertex)
	return result


static func _append_realized_content_vertex(
		result: Array,
		world: Vector3,
		level: int,
		grid: GridWorld,
		entry_vertex: Dictionary
	) -> void:
	var cell := grid.world_to_grid(world)
	var vertex := {"cell": cell, "level": level}
	if not _interaction_vertex_walkable(grid, vertex) \
			or not _interaction_vertices_connected(grid, entry_vertex, vertex):
		return
	for existing_v in result:
		if existing_v is Dictionary \
				and (existing_v as Dictionary).get("cell", Vector2i(-1, -1)) == cell \
				and int((existing_v as Dictionary).get("level", -1)) == level:
			return
	result.append({"cell": cell, "level": level, "world": world})


## A feature socket is authored data too. Moving only the content placement would
## make the visible object disagree with both its feature assignment and the
## integrity validator, so all three representations are updated atomically.
static func _move_realized_content_socket_with_placement(
		node: Dictionary, placement: Dictionary
	) -> Dictionary:
	var socket_id := str(placement.get("socket_id", ""))
	if socket_id == "":
		return node
	var category := str(placement.get("category", ""))
	var feature_v: Variant = node.get("spatial_feature", null)
	if not (feature_v is Dictionary):
		return node
	var feature := feature_v as Dictionary
	if feature.is_empty():
		return node
	var socket_index := _spatial_socket_index(socket_id, category)
	var sockets_v: Variant = feature.get("content_sockets", null)
	if socket_index >= 0 and sockets_v is Dictionary:
		var sockets := sockets_v as Dictionary
		var category_sockets_v: Variant = sockets.get(category, null)
		if category_sockets_v is Array \
				and socket_index < (category_sockets_v as Array).size():
			var category_sockets := category_sockets_v as Array
			category_sockets[socket_index] = (
				placement.get("local_offset", []) as Array).duplicate()
			sockets[category] = category_sockets
			feature["content_sockets"] = sockets
	var assignments: Array = feature.get("socket_assignments", [])
	for assignment_index in range(assignments.size()):
		if not (assignments[assignment_index] is Dictionary):
			continue
		var assignment := assignments[assignment_index] as Dictionary
		if str(assignment.get("socket", "")) != socket_id:
			continue
		assignment["position"] = (
			placement.get("position", []) as Array).duplicate()
		assignments[assignment_index] = assignment
	feature["socket_assignments"] = assignments
	node["spatial_feature"] = feature
	return node


## Project every runtime-bound content object onto the same typed graph used by
## click movement. The object cell identifies where the visible mechanism lives;
## the reachable region identifies where a body can actually produce its verb.
## This runs only during fresh generation. Persisted explicit receipts are never
## rewritten by canonicalization.
static func _project_realized_content_navigation(
		nodes: Array, navigation_grid: Dictionary
	) -> Dictionary:
	var errors: Array[String] = []
	if str(navigation_grid.get("contract_id", "")) \
			!= GridWorld.GRID_DATA_CONTRACT_ID:
		return {
			"valid": false,
			"errors": ["Cannot project realized content without a unified navigation grid."],
			"realized_content_placement_count": 0,
		}
	var grid := GridWorld.from_data(navigation_grid)
	var entry_vertex := _project_reference_vertex(
		grid, _find_node_in_list(nodes, "entry"))
	if entry_vertex.is_empty():
		return {
			"valid": false,
			"errors": ["Cannot project realized content without a walkable entry vertex."],
			"realized_content_placement_count": 0,
		}
	var realized_count := 0
	for node_index in range(nodes.size()):
		if not (nodes[node_index] is Dictionary):
			continue
		var node := nodes[node_index] as Dictionary
		var placements: Array = node.get("content_placements", [])
		for placement_index in range(placements.size()):
			if not (placements[placement_index] is Dictionary):
				continue
			var placement := placements[placement_index] as Dictionary
			var category := str(placement.get("category", ""))
			var content_id := str(placement.get("id", ""))
			if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id):
				continue
			realized_count += 1
			var expected := _expected_realized_content_navigation(
				placement, node, grid, entry_vertex)
			if not bool(expected.get("valid", false)):
				for error_v in expected.get("errors", []):
					errors.append(
						"%s/%s: %s" % [
							str(node.get("id", "node")), content_id, str(error_v)])
				continue
			placement["navigation"] = expected.get("receipt", {})
			placements[placement_index] = placement
		node["content_placements"] = placements
		nodes[node_index] = node
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"realized_content_placement_count": realized_count,
	}


## Fail-closed public verifier. A saved or inline spec must carry the exact graph
## receipt emitted from its visible position and runtime binding; a stale cell,
## level, radius, kind, or disconnected region is rejected rather than repaired.
static func validate_realized_content_navigation(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	if str(navigation_grid.get("contract_id", "")) \
			!= GridWorld.GRID_DATA_CONTRACT_ID:
		return {
			"valid": false,
			"errors": ["Generated stretch has no unified navigation grid."],
			"realized_content_placement_count": 0,
		}
	var grid := GridWorld.from_data(navigation_grid)
	var nodes: Array = spec.get("nodes", [])
	var entry_vertex := _project_reference_vertex(
		grid, _find_node_in_list(nodes, "entry"))
	if entry_vertex.is_empty():
		errors.append("Generated entry has no walkable content-navigation anchor.")
	var realized_count := 0
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var placements_v: Variant = node.get("content_placements", null)
		if not (placements_v is Array):
			errors.append(
				"%s has no content-placement array." % str(node.get("id", "node")))
			continue
		for placement_v in placements_v as Array:
			if not (placement_v is Dictionary):
				errors.append(
					"%s has a malformed content placement."
					% str(node.get("id", "node")))
				continue
			var placement := placement_v as Dictionary
			var category := str(placement.get("category", ""))
			var content_id := str(placement.get("id", ""))
			if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id):
				continue
			realized_count += 1
			var label := "%s/%s" % [str(node.get("id", "node")), content_id]
			var expected := _expected_realized_content_navigation(
				placement, node, grid, entry_vertex)
			if not bool(expected.get("valid", false)):
				for error_v in expected.get("errors", []):
					errors.append("%s: %s" % [label, str(error_v)])
				continue
			var receipt_v: Variant = placement.get("navigation", null)
			if not (receipt_v is Dictionary):
				errors.append("%s has no typed content-navigation receipt." % label)
				continue
			if not _serialized_variants_equal(
					receipt_v, expected.get("receipt", {})):
				errors.append(
					"%s content-navigation receipt differs from its reachable graph region."
					% label)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"realized_content_placement_count": realized_count,
	}


static func _expected_realized_content_navigation(
		placement: Dictionary,
		node: Dictionary,
		grid: GridWorld,
		entry_vertex: Dictionary
	) -> Dictionary:
	var errors: Array[String] = []
	var category := str(placement.get("category", ""))
	var content_id := str(placement.get("id", ""))
	var binding_id := RuntimeRegistryScript.generated_content_binding(
		category, content_id)
	var runtime_navigation := RuntimeRegistryScript.generated_content_navigation(
		category, content_id)
	if binding_id == "" or runtime_navigation.is_empty():
		errors.append("Runtime binding has no content-navigation semantics.")
		return {"valid": false, "errors": errors}
	var level_v: Variant = node.get("elevation_index", null)
	if not _interaction_integral_component(level_v):
		errors.append("Owning node has no integral navigation level.")
		return {"valid": false, "errors": errors}
	var level := int(level_v)
	if level < 0 or level >= grid.level_count:
		errors.append("Owning node level is outside the unified graph.")
		return {"valid": false, "errors": errors}
	var position := _array_to_vec3(placement.get("position", []), Vector3.INF)
	if not position.is_finite():
		errors.append("Placement has no finite world position.")
		return {"valid": false, "errors": errors}
	var content_cell := grid.world_to_grid(position)
	if content_cell.x < 0 or content_cell.y < 0 \
			or content_cell.x >= grid.width or content_cell.y >= grid.height:
		errors.append("Placement cell is outside the unified graph bounds.")
		return {"valid": false, "errors": errors}
	var content_vertex := {"cell": content_cell, "level": level}
	var radius_v: Variant = runtime_navigation.get("radius", null)
	if not _interaction_finite_number(radius_v) or float(radius_v) <= 0.0:
		errors.append("Runtime binding has no finite standing-region radius.")
		return {"valid": false, "errors": errors}
	var radius := float(radius_v)
	var reachable_region: Array = []
	for candidate_v in _walkable_interaction_vertices(
			grid, position, level, radius):
		var candidate := candidate_v as Dictionary
		if _interaction_vertices_connected(grid, entry_vertex, candidate):
			reachable_region.append(_interaction_vertex_to_data(candidate))
	if reachable_region.is_empty():
		errors.append("Placement has no reachable adjacent standing region.")
		return {"valid": false, "errors": errors}
	var navigation_kind := str(runtime_navigation.get("kind", ""))
	var requires_content_vertex := (
		navigation_kind == RuntimeRegistryScript.CONTENT_NAVIGATION_OCCUPIABLE
		or bool(runtime_navigation.get("requires_content_vertex", false))
	)
	if requires_content_vertex:
		if not _interaction_vertex_walkable(grid, content_vertex) \
				or not _interaction_vertices_connected(
					grid, entry_vertex, content_vertex):
			errors.append("Content does not occupy a reachable walkable cell.")
			return {"valid": false, "errors": errors}
		var content_vertex_data := _interaction_vertex_to_data(content_vertex)
		var region_contains_content := false
		for region_vertex_v in reachable_region:
			if _serialized_variants_equal(region_vertex_v, content_vertex_data):
				region_contains_content = true
				break
		if not region_contains_content:
			errors.append("Content standing region omits its required content cell.")
			return {"valid": false, "errors": errors}
	if navigation_kind not in [
		RuntimeRegistryScript.CONTENT_NAVIGATION_OCCUPIABLE,
		RuntimeRegistryScript.CONTENT_NAVIGATION_INTERACTABLE,
	]:
		errors.append("Runtime binding uses an unknown content-navigation kind.")
		return {"valid": false, "errors": errors}
	var receipt := {
		"contract_id": CONTENT_NAVIGATION_CONTRACT_ID,
		"binding_id": binding_id,
		"kind": navigation_kind,
		"component_id": _interaction_component_id(entry_vertex),
		"content_vertex": _interaction_vertex_to_data(content_vertex),
		"reachable_region": reachable_region,
		"radius": radius,
	}
	var arrival_policy := str(runtime_navigation.get("arrival_policy", ""))
	if arrival_policy != "":
		receipt["arrival_policy"] = arrival_policy
	return {
		"valid": true,
		"errors": [],
		"receipt": receipt,
	}


## Public generated-spawn invariant. Only content with a shipped generated
## runtime binding participates: prose-only palette nouns create no collider and
## therefore cannot invalidate the physical deployment surface. The clearance
## radius includes the real presenter's interaction/outline footprint, the
## player capsule, and a small readable-formation margin.
static func validate_party_spawn_clearance(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var anchors: Dictionary = spec.get("anchors", {})
	var spawn_positions := _party_spawn_positions(anchors)
	for char_id in PARTY_SPAWN_IDS:
		if not anchors.has(char_id):
			errors.append("Missing generated party spawn anchor '%s'." % char_id)
	var checked_placements := 0
	for node_v in spec.get("nodes", []):
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		for placement_v in node.get("content_placements", []):
			if not (placement_v is Dictionary):
				continue
			var placement := placement_v as Dictionary
			if not RuntimeRegistryScript.generated_content_is_realized(
					str(placement.get("category", "")),
					str(placement.get("id", ""))):
				continue
			checked_placements += 1
			var position := _placement_world_position(placement, node)
			if not position.is_finite():
				errors.append(
					"%s/%s has no finite generated content position."
					% [str(node.get("id", "node")), str(placement.get("id", "content"))]
				)
				continue
			var clearance := _placement_spawn_clearance_radius(placement)
			for spawn_v in spawn_positions:
				var spawn := spawn_v as Dictionary
				var spawn_position := spawn.get("position", Vector3.INF) as Vector3
				var horizontal_distance := Vector2(
					position.x - spawn_position.x,
					position.z - spawn_position.z
				).length()
				if horizontal_distance + 0.001 >= clearance:
					continue
				errors.append(
					"%s/%s is %.3f m from %s spawn; %.3f m is required."
					% [
						str(node.get("id", "node")),
						str(placement.get("id", "content")),
						horizontal_distance,
						str(spawn.get("character_id", "party")),
						clearance,
					]
				)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"party_anchor_count": spawn_positions.size(),
		"realized_content_placement_count": checked_placements,
	}


## Public verifier for roguelite district identity. A biome is not a color name: it must carry an authored
## building/feature cluster, a distinct surface language, and a placement beside a compatible systemic node.
static func validate_area_theme(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var biome := str(spec.get("biome", ""))
	var theme: Dictionary = spec.get("area_theme", {})
	var landmarks: Array = spec.get("themed_landmarks", [])
	var setpieces: Array = spec.get("themed_setpieces", [])
	var infrastructure_operations: Array = spec.get("infrastructure_operations", [])
	if biome == "":
		return {"valid": theme.is_empty() and landmarks.is_empty(), "errors": errors, "landmark_count": 0}
	if theme.is_empty():
		errors.append("Biome '%s' has no rendered area theme" % biome)
		return {"valid": false, "errors": errors, "landmark_count": landmarks.size()}
	if str(theme.get("contract_id", "")) != "main_game_area_theme_v1":
		errors.append("Biome '%s' uses an unknown area-theme contract" % biome)
	if str(theme.get("id", "")) != biome:
		errors.append("Area theme id does not match biome '%s'" % biome)
	if (theme.get("building_vocabulary", []) as Array).is_empty() \
			or (theme.get("feature_vocabulary", []) as Array).is_empty():
		errors.append("Biome '%s' does not expose both buildings and features" % biome)
	if landmarks.is_empty():
		errors.append("Biome '%s' emitted no authored landmark" % biome)
	var nodes_by_id := {}
	for node_v in spec.get("nodes", []):
		if node_v is Dictionary:
			nodes_by_id[str((node_v as Dictionary).get("id", ""))] = node_v
	var grid = GridWorld.from_data(spec.get("navigation_grid", {}))
	for landmark_v in landmarks:
		if not (landmark_v is Dictionary):
			errors.append("Biome '%s' emitted a malformed landmark" % biome)
			continue
		var landmark := landmark_v as Dictionary
		var scene_path := str(landmark.get("scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			errors.append("Theme landmark has no authored scene: %s" % scene_path)
		var node_id := str(landmark.get("anchor_node_id", ""))
		if not nodes_by_id.has(node_id):
			errors.append("Theme landmark references unknown node %s" % node_id)
			continue
		var anchor_node := nodes_by_id[node_id] as Dictionary
		if str(anchor_node.get("role", "")) in ["entry", "boundary", "shelter", "shelter_arrival"]:
			errors.append("Theme landmark anchors to a boundary/shelter node")
		var anchor_structures: Array = landmark.get("anchor_structures", [])
		var matched := false
		for structure_v in anchor_node.get("structures", []):
			if anchor_structures.has(str(structure_v)):
				matched = true
				break
		if not matched:
			errors.append("Theme landmark %s is not beside a compatible systemic structure" % str(landmark.get("id", "")))
		var position := _array_to_vec3(landmark.get("position", []), Vector3.INF)
		if position == Vector3.INF:
			errors.append("Theme landmark %s has no position" % str(landmark.get("id", "")))
		else:
			var center_cell := grid.world_to_grid(position)
			var level := int(landmark.get("elevation_index", 0))
			if grid.is_walkable(center_cell.x, center_cell.y, {}, {}, level):
				errors.append("Theme landmark %s overlaps the walkable route" % str(landmark.get("id", "")))
		for field in ["primary_read", "feedback_role"]:
			if str(landmark.get(field, "")).strip_edges() == "":
				errors.append("Theme landmark %s is missing %s" % [str(landmark.get("id", "")), field])
	var setpiece_defs: Array = theme.get("route_setpieces", [])
	var authored_risk_cells: Array = (
		spec.get("navigation_grid", {}) as Dictionary
	).get("risk_cell_list", [])
	# Route-setpiece definitions are vocabulary, not permission to invent a
	# hazard. An all-safe generated graph must emit neither false-positive risk
	# cells nor scenery that claims a risky lane exists.
	if not setpiece_defs.is_empty() and not authored_risk_cells.is_empty() \
			and setpieces.is_empty():
		errors.append("Biome '%s' emitted no interactive route setpieces" % biome)
	var risk_cells := {}
	for risk_v in spec.get("navigation_grid", {}).get("risk_cell_list", []):
		if risk_v is Dictionary and (risk_v as Dictionary).get("cell", []) is Array:
			var risk_cell: Array = (risk_v as Dictionary).get("cell", [])
			if risk_cell.size() >= 2:
				risk_cells["%d:%d" % [int(risk_cell[0]), int(risk_cell[1])]] = true
	for setpiece_v in setpieces:
		if not (setpiece_v is Dictionary):
			errors.append("Biome '%s' emitted a malformed route setpiece" % biome)
			continue
		var setpiece := setpiece_v as Dictionary
		var scene_path := str(setpiece.get("scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			errors.append("Theme route setpiece has no authored scene: %s" % scene_path)
		var source_cell: Array = setpiece.get("risk_cell", [])
		if source_cell.size() < 2 or not risk_cells.has("%d:%d" % [int(source_cell[0]), int(source_cell[1])]):
			errors.append("Theme route setpiece %s is not seated on a risky route cell" % str(setpiece.get("id", "")))
		for field in ["primary_read", "leverage", "failure_prediction"]:
			if str(setpiece.get(field, "")).strip_edges() == "":
				errors.append("Theme route setpiece %s is missing %s" % [str(setpiece.get("id", "")), field])
	if not (theme.get("infrastructure_pair", {}) as Dictionary).is_empty() and infrastructure_operations.is_empty():
		errors.append("Biome '%s' emitted no typed infrastructure operation" % biome)
	for operation_v in infrastructure_operations:
		if not (operation_v is Dictionary):
			errors.append("Biome '%s' emitted a malformed infrastructure operation" % biome)
			continue
		var operation := operation_v as Dictionary
		if str(operation.get("contract_id", "")) != "generated_infrastructure_operation_v1":
			errors.append("Infrastructure operation uses an unknown contract")
		for action_field in ["source_action", "source_preview", "receiver_action", "receiver_preview",
				"service_relationship", "effect_relationship"]:
			if str(operation.get(action_field, "")).strip_edges() == "":
				errors.append("Infrastructure operation lacks %s" % action_field)
		for node_field in ["source_node_id", "receiver_node_id"]:
			if not nodes_by_id.has(str(operation.get(node_field, ""))):
				errors.append("Infrastructure operation references unknown %s" % node_field)
	var transition: Dictionary = spec.get("zone_transition", {})
	var previous_biome := str((spec.get("settings", {}) as Dictionary).get("previous_biome", ""))
	if previous_biome != "" and previous_biome != biome:
		if transition.is_empty():
			errors.append("Biome '%s' has no entry transition from '%s'" % [biome, previous_biome])
		else:
			if str(transition.get("contract_id", "")) != "generated_zone_transition_v1":
				errors.append("Zone transition uses an unknown contract")
			if str(transition.get("from_id", "")) != previous_biome \
					or str(transition.get("to_id", "")) != biome:
				errors.append("Zone transition does not match %s -> %s" % [previous_biome, biome])
			if str(transition.get("from_floor_tile", "")) == "" \
					or str(transition.get("to_floor_tile", "")) == "" \
					or int(transition.get("length_cells", 0)) < 3:
				errors.append("Zone transition lacks enough surface blend data")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"landmark_count": landmarks.size(),
		"setpiece_count": setpieces.size(),
		"infrastructure_operation_count": infrastructure_operations.size(),
		"transition_count": 0 if transition.is_empty() else 1,
	}


static func build_navigation_grid_from_spec(spec: Dictionary) -> Dictionary:
	var settings: Dictionary = spec.get("settings", {}).duplicate(true)
	if settings.is_empty():
		settings = {"id": str(spec.get("id", "generated_stretch"))}
	# WFC specs carry a roompieces block → rebuild the grid deterministically from the placements/corridors.
	# Older (legacy-rasterized) specs lack it → the legacy node-footprint rasterizer rebuilds them as before.
	var rp: Dictionary = spec.get("roompieces", {})
	if rp is Dictionary and not (rp.get("placements", []) as Array).is_empty():
		return GridStitcherScript.build(
			rp.get("placements", []), rp.get("corridors", []), rp.get("slot_cells", {}), settings)
	return _build_navigation_grid_legacy(
		spec.get("nodes", []), spec.get("routes", []), settings, spec.get("graybox", {}))

## A room-pieces block for the spec — the deterministic rebuild input for build_navigation_grid_from_spec. An
## empty layout (legacy fallback) yields no placements, so the rebuild routes through the legacy rasterizer.
static func _roompieces_block(layout: Dictionary) -> Dictionary:
	return {
		"contract_id": "trawf_roompieces_v1",
		"tile_size": 1,
		"layout_engine": "wfc_v1" if not (layout.get("placements", []) as Array).is_empty() else "legacy",
		"fallback_used": bool(layout.get("fallback_used", false)),
		"placements": layout.get("placements", []),
		"corridors": layout.get("corridors", []),
		"slot_cells": layout.get("slot_cells", {}),
	}

## The unified-grid traversal layer for a generated stretch — the GridWorld.from_data contract built
## from the SAME semantic nodes/routes the solver reads (the solver and replay artifact never touch
## this). Node footprints + rasterized route corridors become walkable cells; a risky/shortcut route
## lays per-cell risk along its corridor (cautious routing detours, non-recoverable refuses); the
## uniform elevation tiers (surface y = 0.45 + 0.72*index) become stacked grid levels with a "ramp"
## link at each cross-elevation route's midpoint. route_cells (by route_id) gives the runtime chunk
## the cells to lock/unlock as the route-choice state changes. Deterministic: array order + sorted
## cell exports, no RNG.
static func _build_navigation_grid_legacy(nodes: Array, routes: Array, settings: Dictionary, graybox: Dictionary) -> Dictionary:
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

static func load_spec(
		path: String, regenerate_stale_from_settings := false
	) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var canonical := canonicalize_spec(parsed as Dictionary)
	var acceptance := validate_spec_acceptance(canonical)
	if not bool(acceptance.get("valid", false)):
		if regenerate_stale_from_settings \
				and _legacy_snapshot_requires_full_regeneration(
					canonical, acceptance):
			var regenerated := generate(
				(canonical.get("settings", {}) as Dictionary).duplicate(true))
			if bool(regenerated.get("success", false)):
				push_warning(
					"Rejected stale generated snapshot '%s' and regenerated its complete spatial/solver snapshot from settings."
					% path)
				return regenerated
		push_error(
			"Refusing stale or malformed generated stretch spec '%s'; regenerate the complete snapshot from its settings: %s"
			% [path, "; ".join(acceptance.get("errors", []))]
		)
		return {}
	return canonical


static func _legacy_snapshot_requires_full_regeneration(
		spec: Dictionary, acceptance: Dictionary
	) -> bool:
	# Absence identifies the pre-integrity schema. Presence is an explicit claim,
	# even when null/empty/malformed, and may never enter the regeneration path.
	if spec.has("spec_integrity"):
		return false
	var settings_v: Variant = spec.get("settings", null)
	if not (settings_v is Dictionary) or (settings_v as Dictionary).is_empty():
		return false
	# Likewise, an explicit per-placement receipt is never overwritten. Legacy
	# snapshots have none of these keys; a partially authored migration must fail.
	for node_v in spec.get("nodes", []):
		if not (node_v is Dictionary):
			continue
		for placement_v in (node_v as Dictionary).get("content_placements", []):
			if placement_v is Dictionary \
					and (placement_v as Dictionary).has("navigation"):
				return false
	var sections: Dictionary = acceptance.get("sections", {})
	# Only contracts introduced or made stricter by this integrity revision may be
	# stale. Existing authored semantics must already validate before settings are
	# allowed to reproduce the whole deterministic snapshot.
	for required_section in [
		"mode_independence",
		"topology",
		"systems",
		"actionable_interaction_approaches",
		"area_theme",
	]:
		var section_v: Variant = sections.get(required_section, null)
		if not (section_v is Dictionary) \
				or not bool((section_v as Dictionary).get("valid", false)):
			return false
	return true

static func save_spec(spec: Dictionary, path: String) -> bool:
	var canonical := canonicalize_spec(spec)
	var acceptance := validate_spec_acceptance(canonical)
	if not bool(acceptance.get("valid", false)):
		push_error(
			"Refusing to save a stale or malformed generated stretch: %s"
			% "; ".join(acceptance.get("errors", []))
		)
		return false
	if path == "":
		path = "%s/%s.json" % [DEFAULT_SPEC_DIR, _sanitize_id(str(spec.get("id", "generated_stretch")))]
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(canonical, "\t"))
	return true

## Persisted specs may carry retired flora names. Those are accepted at this
## serialization boundary, but every returned/written runtime spec uses the
## canonical key. This intentionally does not add aliases to the live palette.
static func canonicalize_spec(spec: Dictionary) -> Dictionary:
	var normalized := _canonicalize_persisted_flora(spec) as Dictionary
	normalized = _canonicalize_persisted_branch_action_triggers(normalized) as Dictionary
	normalized = _canonicalize_persisted_interaction_approaches(normalized)
	return _canonicalize_persisted_branch_action_coverage(normalized)


## Legacy fixtures predate typed action approaches.  Migrate only an absent
## contract; an explicitly present malformed/unreachable contract must survive
## to the fail-closed validator rather than being silently repaired.
static func _canonicalize_persisted_interaction_approaches(
	spec: Dictionary
	) -> Dictionary:
	var nodes: Array = spec.get("nodes", [])
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	if nodes.is_empty() or navigation_grid.is_empty():
		return spec
	var projection := _project_actionable_interaction_approaches(
		nodes,
		spec.get("routes", []),
		navigation_grid,
		str(spec.get("id", "")),
		true
	)
	if bool(projection.get("valid", false)):
		spec["nodes"] = nodes
	return spec


## Typed interaction regions were added before exact per-cut destination coverage.
## Migrate only an absent `affected_node_ids` field by recomputing it from the
## persisted woven graph and typed approaches. An explicitly present malformed or
## stale claim remains untouched so acceptance validation fails closed.
static func _canonicalize_persisted_branch_action_coverage(
		spec: Dictionary
	) -> Dictionary:
	var navigation_grid: Dictionary = spec.get("navigation_grid", {})
	var nodes: Array = spec.get("nodes", [])
	var branches: Array = navigation_grid.get("branches", [])
	if navigation_grid.is_empty() or nodes.is_empty() or branches.is_empty():
		return spec
	var expected_by_branch := {}
	for action_v in SolverScript.mandatory_branch_actions(
			branches, nodes, navigation_grid):
		if not (action_v is Dictionary):
			continue
		var action := action_v as Dictionary
		var branch_id := str(action.get("branch_id", action.get("target", "")))
		if branch_id != "":
			expected_by_branch[branch_id] = (
				action.get("affected_node_ids", []) as Array).duplicate()
	if expected_by_branch.is_empty():
		return spec
	return _canonicalize_persisted_branch_action_coverage_value(
		spec, expected_by_branch) as Dictionary


static func _canonicalize_persisted_branch_action_coverage_value(
		value: Variant, expected_by_branch: Dictionary
	) -> Variant:
	if value is Dictionary:
		var normalized := {}
		for raw_key in (value as Dictionary).keys():
			normalized[raw_key] = \
				_canonicalize_persisted_branch_action_coverage_value(
					(value as Dictionary)[raw_key], expected_by_branch)
		if str(normalized.get("kind", "")) == "mandatory_branch_interaction" \
				and not normalized.has("affected_node_ids"):
			var branch_id := str(normalized.get(
				"branch_id", normalized.get("target", "")))
			if expected_by_branch.has(branch_id):
				normalized["affected_node_ids"] = (
					expected_by_branch[branch_id] as Array).duplicate()
		return normalized
	if value is Array:
		var normalized := []
		for item in value as Array:
			normalized.append(
				_canonicalize_persisted_branch_action_coverage_value(
					item, expected_by_branch))
		return normalized
	return value


## `before_nodes` extends the original singular interleave anchor so an optional
## route that encounters the same physical cut can trigger the producer before
## crossing. Older fixtures remain valid: their canonical golden anchor is the
## only known trigger, and freshly generated specs carry the complete spatial set.
static func _canonicalize_persisted_branch_action_triggers(
	value: Variant
) -> Variant:
	if value is Dictionary:
		var normalized := {}
		for raw_key in (value as Dictionary).keys():
			normalized[raw_key] = _canonicalize_persisted_branch_action_triggers(
				(value as Dictionary)[raw_key]
			)
		if (
			str(normalized.get("kind", "")) == "mandatory_branch_interaction"
			and not normalized.has("before_nodes")
			and str(normalized.get("before_node", "")) != ""
		):
			normalized["before_nodes"] = [
				str(normalized.get("before_node", ""))
			]
		return normalized
	if value is Array:
		var normalized := []
		for item in value as Array:
			normalized.append(
				_canonicalize_persisted_branch_action_triggers(item)
			)
		return normalized
	return value

static func _canonicalize_persisted_flora(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized := {}
		for raw_key in (value as Dictionary).keys():
			var next_key: Variant = raw_key
			if raw_key is String and FloraSpeciesScript.is_legacy_key(str(raw_key)):
				var mapped_key := FloraSpeciesScript.canonical_key(str(raw_key))
				if mapped_key != "":
					next_key = mapped_key
			normalized[next_key] = _canonicalize_persisted_flora((value as Dictionary)[raw_key])
		return normalized
	if value is Array:
		var normalized := []
		for item in value as Array:
			normalized.append(_canonicalize_persisted_flora(item))
		return normalized
	if value is String and FloraSpeciesScript.is_legacy_key(str(value)):
		var mapped_value := FloraSpeciesScript.canonical_key(str(value))
		return mapped_value if mapped_value != "" else value
	return value

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
		# Legacy specs budget a prose-only `return_shortcut` in the semantic
		# graph. Recovery is owned exclusively by the meta-template's real,
		# saved ClimbvineReturn mechanism, so this obsolete knob cannot affect content.
		if str(key) == "shortcut_count":
			continue
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
	# Preserve the tier floor + caller pins as audit data. Campaign stage never
	# mutates these spatial budgets; the systems profile carries progression.
	resolved["budget_tier_floor"] = tier_floor
	resolved["budget_overridden_keys"] = overridden_keys
	# A BIOME is a named content preset: if the caller named one (and didn't pin explicit
	# limitations), restrict generation to that biome's slice of the palette via the existing
	# limitations.allowed machinery. The biome id is preserved on the spec for downstream display.
	var biome := str(settings.get("biome", ""))
	var previous_biome := str(settings.get("previous_biome", ""))
	var raw_limitations: Variant = settings.get("limitations", {})
	if biome != "" and BiomesScript.has_biome(biome) and (not (raw_limitations is Dictionary) or (raw_limitations as Dictionary).is_empty()):
		raw_limitations = BiomesScript.limitations_for(biome)
	resolved["biome"] = biome
	resolved["previous_biome"] = previous_biome
	resolved["area_theme"] = BiomesScript.theme_contract_for(biome, seed) if biome != "" else {}
	resolved["zone_transition"] = BiomesScript.transition_contract_for(previous_biome, biome)
	resolved["limitations"] = _normalize_limitations(raw_limitations)
	resolved["composition"] = _normalize_composition(settings.get("composition", {}))
	resolved["roster"] = settings.get("roster", [])
	var spatial_profile: Dictionary = {}
	if settings.get("spatial_profile", {}) is Dictionary:
		spatial_profile = (settings.get("spatial_profile", {}) as Dictionary).duplicate(true)
	if not spatial_profile.has("slot_pitch"):
		spatial_profile["slot_pitch"] = int(TIER_SLOT_PITCH.get(tier, 8))
	resolved["spatial_profile"] = spatial_profile
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
			var values := _string_array(group.get(raw_category, []))
			if category == "flora":
				var canonical_values: Array[String] = []
				for raw_value in values:
					var canonical_value := FloraSpeciesScript.canonical_key(str(raw_value))
					if canonical_value != "" and not canonical_values.has(canonical_value):
						canonical_values.append(canonical_value)
				values = canonical_values
			result[mode][category] = values
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
		"max_consecutive_archetype": 2,
		"max_archetype_share": 0.5,
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
	result["max_consecutive_archetype"] = maxi(1, int(raw_dict.get("max_consecutive_archetype", 2)))
	result["max_archetype_share"] = clampf(float(raw_dict.get("max_archetype_share", 0.5)), 0.25, 1.0)
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
	var chain: Array = composition.get("chain", [])
	for entry in chain:
		_validate_composition_entry(catalog, entry, allowed, blocked, "composition chain", errors)
	# A composed chain is a causal pipeline, not adjacency flavor. Every upstream
	# output must be named, every downstream input must consume it, and the types
	# must match exactly. The first input and final output remain open boundaries.
	for i in range(chain.size() - 1):
		if not (chain[i] is Dictionary) or not (chain[i + 1] is Dictionary):
			continue
		var current := chain[i] as Dictionary
		var next := chain[i + 1] as Dictionary
		var output := str(current.get("output", "")).strip_edges()
		var input := str(next.get("input", "")).strip_edges()
		if output == "":
			errors.append("Composition chain link %d (%s) must declare an output consumed by the next link." % [i, str(current.get("id", ""))])
		elif input == "":
			errors.append("Composition chain link %d (%s) must declare an input produced by the previous link." % [i + 1, str(next.get("id", ""))])
		elif output != input:
			errors.append("Composition chain handshake mismatch at %d->%d: output '%s' does not feed input '%s'." % [i, i + 1, output, input])
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
	if not SystemsCurriculumScript.is_procedurally_eligible(id):
		errors.append("%s uses procedurally blocked archetype %s: %s" % [context, id, SystemsCurriculumScript.blocked_reason(id)])
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

## Campaign stage now increases the MODEL the player must reason about, not the
## amount of geometry they must service. Complexity tier still owns spatial size,
## branches, pressure, and presentation budget. The compatibility field remains so
## old consumers do not mistake this for an unprocessed setting.
static func _apply_systems_progression_profile(resolved: Dictionary) -> void:
	var tier := str(resolved.get("complexity_tier", "teaching"))
	var natural_stage := int(TIER_PROGRESSION_STAGE.get(tier, 2))
	var stage := int(resolved.get("progression_stage", natural_stage))
	resolved["stage_depth_steps"] = 0
	resolved["systems_profile"] = SystemsCurriculumScript.profile_for_stage(stage)

static func _filter_archetypes_by_stage(catalog, ids: Array, max_stage: int) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		if SystemsCurriculumScript.is_procedurally_eligible(str(id)) and _archetype_stage(catalog, str(id)) <= max_stage:
			result.append(str(id))
	return result

## An archetype is a BREATHER when every approach it offers requires nothing — it poses no question,
## it connects. Derived from the catalog rather than an id list so a new archetype is classified by
## what it actually demands, not by anyone remembering to add it here.
static func _archetype_poses_no_demand(catalog, id: String) -> bool:
	var entry: Dictionary = catalog.get_archetype(id)
	var approaches: Array = entry.get("approaches", [])
	if approaches.is_empty():
		return true
	for approach_v in approaches:
		if approach_v is Dictionary \
				and not ((approach_v as Dictionary).get("requires", []) as Array).is_empty():
			return false
	return true


static func _choose_archetype_chain(catalog, settings: Dictionary, budget: Dictionary, rng) -> Array:
	var limitations: Dictionary = settings.get("limitations", {})
	var required := _category_limitations(limitations, "required", "archetypes")
	var allowed := _category_limitations(limitations, "allowed", "archetypes")
	var blocked := _category_limitations(limitations, "blocked", "archetypes")
	var available := _filter_archetypes_by_stage(catalog, _available_values(catalog, "archetypes", allowed, blocked), int(settings.get("progression_stage", 99)))
	# Procedural eligibility was only ever consulted while building `preferred`, and the fill loop
	# falls back to `available` whenever that runs dry — so a story-mode archetype could still be
	# generated through the back door. Filter the pool itself: blocked must mean unreachable by any
	# path, not merely unpreferred.
	var procedural: Array[String] = []
	for candidate_v in available:
		if SystemsCurriculumScript.is_procedurally_eligible(str(candidate_v)):
			procedural.append(str(candidate_v))
	if not procedural.is_empty():
		available = procedural
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
	var preferred := SystemsCurriculumScript.preferred_archetype_ids(
		catalog, available, int(settings.get("progression_stage", 1)))
	# CONNECTIVE TISSUE IS BUDGETED, NOT POOLED. Three archetypes declare only approaches that
	# require nothing — Narrative beat, Shelter-rest management, Expectation subversion. They are
	# legitimate BREATHERS, not puzzles, but drawing them from the same pool as demanding archetypes
	# let the fill loop stack them: they took 21% of every node generated, and one stretch came out
	# entirely breather and posed no question anywhere in it. Cap their share so a stretch always
	# spends most of its nodes on something that asks the player for something.
	var breather_cap := maxi(1, int(floor(float(target_count) / 3.0)))
	var breathers := 0
	for existing_id in ids:
		if _archetype_poses_no_demand(catalog, existing_id):
			breathers += 1
	var guard := 0
	while ids.size() < target_count and not available.is_empty() and guard < 256:
		guard += 1
		var source: Array = preferred if not preferred.is_empty() else available
		var picked := str(rng.pick(source))
		var is_breather := _archetype_poses_no_demand(catalog, picked)
		if is_breather and breathers >= breather_cap:
			# Skip it for now, but only while a demanding alternative still exists — a stretch that
			# genuinely has nothing else available must still be fillable.
			var has_alternative := false
			for candidate in available:
				if not _archetype_poses_no_demand(catalog, str(candidate)):
					has_alternative = true
					break
			if has_alternative:
				preferred.erase(picked)
				if preferred.is_empty():
					available.erase(picked)
				continue
		available.erase(picked)
		preferred.erase(picked)
		if not ids.has(picked):
			ids.append(picked)
			if is_breather:
				breathers += 1

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
	# An authored causal chain's order is semantic: output N is the declared input
	# of N+1. Never topologically reshuffle it after validating that handshake.
	if not composition_chain.is_empty():
		return chain
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
	var systems_model: Dictionary = SystemsCurriculumScript.model_for_archetype(entry, id)
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
		"spatial_affordances": (entry.get("spatial_affordances", []) as Array).duplicate(true),
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
		"systems_dimensions": (systems_model.get("dimensions", []) as Array).duplicate(),
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
		var preferred := SystemsCurriculumScript.preferred_archetype_ids(
			catalog, available, int(settings.get("progression_stage", 1)))
		var start_pool: Array = preferred if not preferred.is_empty() else available
		current_id = str(required[0]) if not required.is_empty() and available.has(str(required[0])) else str(rng.pick(start_pool))
	var current_step := maxi(0, int(walk_settings.get("start_step", 0)))
	var transition_chance := float(walk_settings.get("transition_chance", 0.35))
	var prefer_tags := _string_array(walk_settings.get("prefer_tags", []))
	var allow_revisit := bool(walk_settings.get("allow_revisit", true))
	var max_consecutive := clampi(int(walk_settings.get("max_consecutive_archetype", 2)), 1, target_steps)
	var max_occurrences := maxi(
		1,
		int(ceil(float(target_steps) * float(walk_settings.get("max_archetype_share", 0.5))))
	)
	var missing_required: Array[String] = []
	for id in required:
		if not missing_required.has(id):
			missing_required.append(id)

	var visits := []
	var edges := []
	var layout := []
	var lane := 0
	var last_id := ""
	var consecutive := 0
	var visit_counts := {}
	var resume_steps := {}
	for walk_index in range(target_steps):
		consecutive = consecutive + 1 if current_id == last_id else 1
		last_id = current_id
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
		visit_counts[current_id] = int(visit_counts.get(current_id, 0)) + 1

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
		var diversity_break := (
			remaining_slots > 0
			and available.size() > 1
			and (
				consecutive >= max_consecutive
				or int(visit_counts.get(current_id, 0)) >= max_occurrences
			)
		)
		if diversity_break:
			should_transition = true
			reason = "diversity_break"
		if should_transition:
			if next_step < step_count:
				resume_steps[current_id] = next_step
			else:
				resume_steps.erase(current_id)
			next_id = _choose_next_walk_archetype(
				catalog, available, current_id, tags, prefer_tags, missing_required,
				allow_revisit, visit_counts, max_occurrences, diversity_break, rng
			)
			next_step = int(resume_steps.get(next_id, 0)) if next_id != current_id else next_step
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
	visit_counts: Dictionary,
	max_occurrences: int,
	force_different: bool,
	rng
) -> String:
	for id in missing_required:
		if available.has(id) and (not force_different or str(id) != current_id):
			return str(id)
	var weighted := []
	for raw_id in available:
		var id := str(raw_id)
		# The random-walk chain builder is the OTHER path into a stretch, and it never consulted
		# procedural eligibility — so a story-mode archetype kept arriving here even after being
		# blocked in the pooled builder. Blocked has to mean unreachable on every path.
		if not SystemsCurriculumScript.is_procedurally_eligible(id):
			continue
		if (force_different or not allow_revisit) and id == current_id and available.size() > 1:
			continue
		if int(visit_counts.get(id, 0)) >= max_occurrences and available.size() > 1:
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
	var chain_mode := str(composition.get("mode", "")) == "chain_nested_poc"
	var playable_chain: Array = archetype_chain.duplicate(true)
	if chain_mode:
		playable_chain.clear()
		for entry_v in archetype_chain:
			if entry_v is Dictionary and str((entry_v as Dictionary).get("composition_role", "")) == "chain_link":
				playable_chain.append((entry_v as Dictionary).duplicate(true))
		if playable_chain.is_empty():
			playable_chain = archetype_chain.duplicate(true)
	var chain_cursor := 0
	var walk_visits: Array = random_walk.get("visits", [])
	var occurrences := {}
	var nodes := []
	for i in range(node_count):
		var is_interior := i > 0 and i < node_count - 1
		var optional := is_interior and optional_count > 0 and (i % 3 == 0)
		if optional:
			optional_count -= 1
		var walk_entry := {}
		if is_interior and i - 1 < walk_visits.size() and walk_visits[i - 1] is Dictionary:
			walk_entry = (walk_visits[i - 1] as Dictionary).duplicate(true)
		var node_id := "entry" if i == 0 else ("exit_shelter" if i == node_count - 1 else "node_%02d" % i)
		# Optional slots are reward detours, not missing links in the mandatory causal
		# chain. Only critical interior nodes advance the chain cursor.
		var chain_position := chain_cursor
		var archetype: Dictionary = playable_chain[chain_position % playable_chain.size()] if is_interior and not optional and not playable_chain.is_empty() else {}
		if is_interior and not optional and not playable_chain.is_empty():
			chain_cursor += 1
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
		var role := "boundary" if i == 0 else ("shelter_arrival" if i == node_count - 1 else ("foraging" if optional else ""))
		if role == "":
			role = str(walk_entry.get("node_role_hint", "")) if not walk_entry.is_empty() else ""
			if role == "":
				role = _role_for_archetype(archetype, i - 1)
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
		if optional and available_structures.has("forage_cache") and not structures.has("forage_cache"):
			structures.append("forage_cache")
		var is_chain_carry := chain_mode and archetype_id == "3" and not optional
		var survival_kind := str(archetype.get("survival_kind", ""))
		var is_resource := (
			optional
			or is_chain_carry
			or survival_kind == "forage"
			or (resource_beats > 0 and role in ["foraging", "regroup"])
		)
		# Every ATP-bearing generated resource is an authored lysate pickup. The carry
		# chain's tool payload remains distinct, but there is no abstract food beat that
		# can credit the party without occupying a hand and being endocytosed.
		var is_food_resource := is_resource and not is_chain_carry
		var authored_atp_reward := int(archetype.get("atp_reward", 0))
		var food_reward_atp := authored_atp_reward if authored_atp_reward > 0 else 2
		var nested_archetypes := _nested_for_archetype(archetype_id, composition) if not optional else []
		var label := "Lysate reserve" if optional else _node_label(archetype, role, i)
		var chain_cycle := int(chain_position / maxi(1, playable_chain.size())) if is_interior and not optional and not playable_chain.is_empty() else -1
		var raw_chain_input := str(archetype.get("chain_input", ""))
		var raw_chain_output := str(archetype.get("chain_output", ""))
		var chain_input_ref := "chain_%02d:%s" % [chain_cycle, raw_chain_input] if raw_chain_input != "" else ""
		var chain_output_ref := "chain_%02d:%s" % [chain_cycle, raw_chain_output] if raw_chain_output != "" else ""
		if chain_mode and chain_cycle > 0 and chain_position % playable_chain.size() == 0 and raw_chain_input == "":
			raw_chain_input = str((playable_chain[playable_chain.size() - 1] as Dictionary).get("chain_output", ""))
			if raw_chain_input != "":
				chain_input_ref = "chain_%02d:%s" % [chain_cycle - 1, raw_chain_input]
		var node := {
			"id": node_id,
			"role": role,
			"label": label,
			"title": label,
			"position": position,
			"optional": optional,
			"branch_role": "optional_risk_reward" if optional else "",
			"archetype_id": archetype_id,
			"archetype_name": str(archetype.get("name", "Narrative beat" if role in ["boundary", "shelter_arrival"] else "")),
			"variant": str(archetype.get("variant", "")),
			"composition_role": str(archetype.get("composition_role", "")),
			"chain_index": int(archetype.get("chain_index", -1)),
			"chain_cycle": chain_cycle,
			"chain_input": raw_chain_input,
			"chain_output": raw_chain_output,
			"chain_input_ref": chain_input_ref,
			"chain_output_ref": chain_output_ref,
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
			"spatial_affordances": (archetype.get("spatial_affordances", []) as Array).duplicate(true),
			"flora": flora,
			"enemies": enemies,
			"structures": structures,
			"resource_beat": is_resource,
			"resource": is_resource,
			"resource_kind": "food" if is_food_resource else ("carry" if is_chain_carry else ""),
			"resource_item_type": "lysate" if is_food_resource else "generated_tool",
			"reward_kind": "food" if is_food_resource else "",
			"reward_atp": food_reward_atp if is_food_resource else 0,
			"carry_payload": is_chain_carry,
			"pressure": 1 if not enemies.is_empty() else 0,
			"shadow_solution": archetype.get("shadow_solution", composition.get("shadow_solution", {})),
			"approaches": archetype.get("approaches", []),
			"stage": int(archetype.get("stage", 1)),
			"survival_kind": survival_kind,
			"atp_reward": food_reward_atp if is_food_resource else 0,
			"pressure_cost": int(archetype.get("pressure_cost", 0)),
			"exploit_target": str(archetype.get("exploit_target", "")),
		}
		nodes.append(node)
		if resource_beats > 0 and role in ["foraging", "regroup"] and not optional:
			resource_beats -= 1
	if chain_mode and not nodes.is_empty():
		var final_output_ref := ""
		var final_output := ""
		for node_index in range(nodes.size() - 2, 0, -1):
			if not (nodes[node_index] is Dictionary):
				continue
			final_output_ref = str((nodes[node_index] as Dictionary).get("chain_output_ref", ""))
			final_output = str((nodes[node_index] as Dictionary).get("chain_output", ""))
			if final_output_ref != "":
				break
		if final_output_ref != "" and nodes[nodes.size() - 1] is Dictionary:
			var exit_node: Dictionary = nodes[nodes.size() - 1]
			exit_node["chain_input"] = final_output
			exit_node["chain_input_ref"] = final_output_ref
			nodes[nodes.size() - 1] = exit_node
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
		# Nested composition is playable only when the child owns a typed mechanism,
		# an exact stable instance, and the physical output source that it unlocks.
		# Older composition metadata had none of those and produced a purple box plus
		# a two-click flag. Keep that prose out of the runtime until a real kit binds it.
		if not _nested_entry_has_runtime_binding(nested_entry):
			continue
		nested.append(nested_entry.duplicate(true))
	return nested


static func _nested_entry_has_runtime_binding(entry: Dictionary) -> bool:
	return (
		str(entry.get("runtime_handler", "")).strip_edges() != ""
		and str(entry.get("mechanism_id", "")).strip_edges() != ""
		and str(entry.get("output_source_id", "")).strip_edges() != ""
		and str(entry.get("completion_predicate", "")).strip_edges() != ""
	)

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
					"topology_role": "optional_branch_bypass",
					"cannot_bypass_unresolved": true,
				})
	if int(budget.get("branch_count", 0)) > 0 and nodes.size() >= 4:
		# Risk buys access to an optional detour; it never skips mandatory causal
		# beats. The safe bypass stays on the golden spine, so pressure and reward
		# describe one truthful topology instead of a solver-breaking shortcut.
		var risky_optional_index := -1
		for i in range(1, nodes.size() - 1):
			if nodes[i] is Dictionary and bool((nodes[i] as Dictionary).get("optional", false)):
				risky_optional_index = i
				break
		if risky_optional_index >= 1:
			var risky_from := str((nodes[risky_optional_index - 1] as Dictionary).get("id", ""))
			var risky_to := str((nodes[risky_optional_index] as Dictionary).get("id", ""))
			for route_index in range(routes.size()):
				var candidate := routes[route_index] as Dictionary
				if str(candidate.get("from", "")) != risky_from or str(candidate.get("to", "")) != risky_to:
					continue
				candidate["id"] = "risky_optional_%02d_%02d" % [risky_optional_index - 1, risky_optional_index]
				candidate["kind"] = "risky"
				candidate["risk"] = "risky"
				candidate["cost"] = 0
				candidate["damage"] = 18.0 + float(rng.call("randi_range", 0, 8))
				candidate["optional_reward_node"] = risky_to
				candidate["branch_role"] = "optional_risk_reward"
				candidate["cannot_bypass_unresolved"] = true
				var reward_atp := clampi(int(ceil(float(candidate["damage"]) / 10.0)), 2, 4)
				var reward_node: Dictionary = nodes[risky_optional_index]
				reward_node["reward_kind"] = "food"
				reward_node["reward_atp"] = reward_atp
				reward_node["atp_reward"] = reward_atp
				reward_node["resource"] = true
				reward_node["resource_beat"] = true
				reward_node["resource_kind"] = "food"
				reward_node["resource_item_type"] = "lysate"
				reward_node["label"] = "Risk cache · %d ATP lysate" % reward_atp
				reward_node["title"] = str(reward_node["label"])
				nodes[risky_optional_index] = reward_node
				routes[route_index] = candidate
				break
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
		var elevation_index := _graybox_elevation_index(node, i, nodes.size(), int(TIER_MAX_LEVELS.get(str(settings.get("complexity_tier", "teaching")), 1)))
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


## Bind WFC's selected feature room-pieces back to their semantic archetype nodes. Geometry owns the prefab and
## socket positions; the archetype affinity owns why those sockets matter. Keeping both halves in the emitted
## contract lets presentation change without losing the intended causal model.
static func _assign_spatial_features(nodes: Array, layout: Dictionary, piece_catalog) -> void:
	var node_indices := {}
	for i in range(nodes.size()):
		if nodes[i] is Dictionary:
			node_indices[str((nodes[i] as Dictionary).get("id", ""))] = i
	for placement_v in layout.get("placements", []):
		if not (placement_v is Dictionary):
			continue
		var placement := placement_v as Dictionary
		var node_id := str(placement.get("node", ""))
		if not node_indices.has(node_id):
			continue
		var piece: Dictionary = piece_catalog.rotate_piece(
			piece_catalog.get_piece(str(placement.get("piece", ""))),
			int(placement.get("rotation", 0))
		)
		var feature_def: Dictionary = piece.get("spatial_feature", {})
		var affordance: Dictionary = placement.get("spatial_affordance", {})
		if feature_def.is_empty() or affordance.is_empty():
			continue
		var node_index := int(node_indices[node_id])
		var node := nodes[node_index] as Dictionary
		# Layout-only archetypes cannot advertise a systemic platform. Likewise, two
		# palette nouns do not become a relationship unless both have generated
		# runtime bindings. Preserve the WFC footprint, but omit the causal prefab.
		if str(node.get("runtime_handler", "")) == "":
			continue
		var realized_socket_count := 0
		for category in ["flora", "enemies", "structures"]:
			for content_id_v in node.get(category, []):
				if RuntimeRegistryScript.generated_content_is_realized(
					category, str(content_id_v)
				):
					realized_socket_count += 1
		if realized_socket_count < 2 \
				or not _spatial_feature_can_socket_all_realized_content(
					node, feature_def):
			continue
		var runtime_binding: Dictionary = affordance.get(
			"runtime_binding", feature_def.get("runtime_binding", {})
		)
		if not _spatial_feature_runtime_binding_is_exact(
			runtime_binding, str(node.get("runtime_handler", ""))
		):
			continue
		var feature := feature_def.duplicate(true)
		feature.merge({
			"contract_id": "generated_spatial_feature_v1",
			"id": "feature_%s" % node_id,
			"node_id": node_id,
			"roompiece": str(placement.get("piece", "")),
			"rotation": int(placement.get("rotation", 0)),
			"affordance_id": str(affordance.get("id", "")),
			"feature_variant": str(affordance.get("feature_variant", "systems_deck")),
			"archetype_id": str(node.get("archetype_id", "")),
			"archetype_name": str(node.get("archetype_name", "")),
			"archetype_variant": str(node.get("variant", "")),
			"runtime_binding": runtime_binding.duplicate(true),
			"causal_model": {
				"system_boundary": "the grated platform, its system sockets, and connected route mouths",
				"primary_insight": str(affordance.get("primary_insight", "")),
				"leverage": str(affordance.get("leverage", "")),
				"failure_prediction": str(affordance.get("failure_prediction", "")),
				"feedback": (affordance.get("feedback", []) as Array).duplicate(true),
				"emergent_inputs": (affordance.get("emergent_inputs", []) as Array).duplicate(true),
				"reasoning_ends": "when the player can predict the response before committing across the deck",
			},
		}, true)
		node["spatial_feature"] = feature
		nodes[node_index] = node


static func _spatial_feature_can_socket_all_realized_content(
		node: Dictionary, feature: Dictionary
	) -> bool:
	var sockets_v: Variant = feature.get("content_sockets", null)
	if not (sockets_v is Dictionary):
		return false
	var sockets := sockets_v as Dictionary
	for category in ["flora", "enemies", "structures"]:
		var realized_count := 0
		for content_id_v in node.get(category, []):
			if RuntimeRegistryScript.generated_content_is_realized(
					category, str(content_id_v)):
				realized_count += 1
		var category_sockets_v: Variant = sockets.get(category, null)
		if realized_count > 0 and not (category_sockets_v is Array):
			return false
		if category_sockets_v is Array \
				and realized_count > (category_sockets_v as Array).size():
			return false
	return true


static func _spatial_feature_runtime_binding_is_exact(
		binding: Dictionary, owner_handler: String
) -> bool:
	if owner_handler == "" \
			or str(binding.get("runtime_handler", "")) != owner_handler:
		return false
	for key in [
		"binding_id",
		"mechanism_id",
		"source_socket_id",
		"effect_socket_id",
		"completion_predicate",
	]:
		if str(binding.get(key, "")).strip_edges() == "":
			return false
	return true


static func _collect_spatial_features(nodes: Array, navigation_grid: Dictionary) -> Array:
	var result: Array = []
	var grid = GridWorld.from_data(navigation_grid)
	var cells_by_level := {}
	var level_cells: Array = navigation_grid.get("level_cells", [])
	if level_cells.is_empty():
		cells_by_level[0] = navigation_grid.get("walkable_cells", [])
	else:
		for entry_v in level_cells:
			if entry_v is Dictionary:
				cells_by_level[int((entry_v as Dictionary).get("level", 0))] = (entry_v as Dictionary).get("cells", [])
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var feature: Dictionary = node.get("spatial_feature", {})
		if feature.is_empty():
			continue
		var center := _array_to_vec3(feature.get("position", node.get("position", [])), Vector3.ZERO)
		var footprint := _array_to_vec3(feature.get("footprint", node.get("footprint", [])), Vector3(5.0, 0.14, 5.0))
		var half := Vector2(footprint.x, footprint.z) * 0.5
		var level := int(feature.get("elevation_index", node.get("elevation_index", 0)))
		var floor_cells: Array = []
		for cell_v in cells_by_level.get(level, []):
			if not (cell_v is Array) or (cell_v as Array).size() < 2:
				continue
			var cell := Vector2i(int(cell_v[0]), int(cell_v[1]))
			var world: Vector3 = grid.grid_to_world(cell, level)
			if absf(world.x - center.x) <= half.x - 0.01 \
					and absf(world.z - center.z) <= half.y - 0.01:
				floor_cells.append([cell.x, cell.y])
		feature["floor_cells"] = floor_cells
		result.append(feature.duplicate(true))
	return result


## Place a district landmark OUTSIDE the authoritative walkable footprint, beside a node whose real structure
## matches the landmark's vocabulary. It frames an existing causal beat without introducing a decorative fake
## interaction or obstructing movement. The prefab owns all geometry; generation emits only placement data.
static func _build_themed_landmarks(nodes: Array, navigation_grid: Dictionary, settings: Dictionary) -> Array:
	var theme: Dictionary = settings.get("area_theme", {})
	if theme.is_empty() or navigation_grid.is_empty():
		return []
	var grid = GridWorld.from_data(navigation_grid)
	var seed := int(settings.get("seed", 0))
	var result: Array = []
	var occupied: Array[Vector3] = []
	for landmark_v in theme.get("landmarks", []):
		if not (landmark_v is Dictionary):
			continue
		var landmark_def := landmark_v as Dictionary
		var anchor_structures: Array = landmark_def.get("anchor_structures", [])
		var candidates: Array = []
		for node_v in nodes:
			if not (node_v is Dictionary):
				continue
			var node := node_v as Dictionary
			if str(node.get("role", "")) in ["entry", "boundary", "shelter", "shelter_arrival"]:
				continue
			var matches := 0
			for structure_v in node.get("structures", []):
				if anchor_structures.has(str(structure_v)):
					matches += 1
			if matches <= 0:
				continue
			var node_id := str(node.get("id", ""))
			candidates.append({
				"node": node,
				"score": matches * 1000 + posmod(int(hash(
					"theme-anchor:%d:%s:%s" % [seed, str(landmark_def.get("id", "")), node_id]
				)), 1000),
			})
		candidates.sort_custom(func(a, b):
			if int(a.get("score", 0)) != int(b.get("score", 0)):
				return int(a.get("score", 0)) > int(b.get("score", 0))
			return str((a.get("node", {}) as Dictionary).get("id", "")) \
				< str((b.get("node", {}) as Dictionary).get("id", ""))
		)
		var clearance := float(landmark_def.get("clearance", 3.5))
		for candidate_v in candidates:
			var anchor_node := (candidate_v as Dictionary).get("node", {}) as Dictionary
			var anchor_position := _array_to_vec3(anchor_node.get("position", []), Vector3.ZERO)
			var level := int(anchor_node.get("elevation_index", 0))
			var landmark_position := _themed_landmark_position(
				grid, anchor_position, level, clearance, seed, str(landmark_def.get("id", "")), occupied
			)
			if landmark_position == Vector3.INF:
				continue
			var toward_anchor := anchor_position - landmark_position
			var placed := landmark_def.duplicate(true)
			placed.merge({
				"contract_id": "generated_theme_landmark_v1",
				"theme_id": str(theme.get("id", "")),
				"source_area": str(theme.get("source_area", "")),
				"anchor_node_id": str(anchor_node.get("id", "")),
				"position": _vec3_to_array(landmark_position),
				"elevation_index": level,
				"rotation_y": atan2(toward_anchor.x, toward_anchor.z),
			}, true)
			result.append(placed)
			occupied.append(landmark_position)
			break
	return result


## Compose one directed supply/utility exchange into the roguelite stretch. Both buildings remain portable
## authored assets outside navigation; their controls occupy distinct reachable cells, and the receiver's
## consequence occupies a marked local risk cell. The pair is skipped unless its BaseShape ports prove the
## declared commodity really can flow source -> receiver.
static func _build_infrastructure_composition(
		nodes: Array,
		navigation_grid: Dictionary,
		settings: Dictionary,
		existing_landmarks: Array
	) -> Dictionary:
	var empty := {"landmarks": [], "operations": []}
	var theme: Dictionary = settings.get("area_theme", {})
	var pair: Dictionary = theme.get("infrastructure_pair", {})
	var catalog: Dictionary = theme.get("infrastructure_catalog", {})
	if pair.is_empty() or catalog.is_empty() or navigation_grid.is_empty():
		return empty
	var source_kind := str(pair.get("source", ""))
	var receiver_kind := str(pair.get("receiver", ""))
	var commodity := str(pair.get("commodity", ""))
	if not catalog.has(source_kind) or not catalog.has(receiver_kind) \
			or not _infrastructure_pair_matches(source_kind, receiver_kind, commodity):
		return empty
	var seed := int(settings.get("seed", 0))
	var grid = GridWorld.from_data(navigation_grid)
	var occupied: Array[Vector3] = []
	for existing_v in existing_landmarks:
		if existing_v is Dictionary:
			var existing_position := _array_to_vec3((existing_v as Dictionary).get("position", []), Vector3.INF)
			if existing_position != Vector3.INF:
				occupied.append(existing_position)
	# Anchor choice and physical seating are one placement problem. Selecting one
	# high-scoring node for each endpoint before checking the authored building
	# footprints made a valid compact/branched graph fail whenever that single
	# pair happened to have no two clear off-route sites. Search the same ranked,
	# deterministic candidates and backtrack both node and site choices. Nothing
	# is squeezed onto the route: every candidate still passes the existing
	# authored-clearance test, and the endpoints must use distinct nodes/sites.
	var placement_plan := _select_infrastructure_placement(
		grid,
		nodes,
		catalog[source_kind] as Dictionary,
		catalog[receiver_kind] as Dictionary,
		seed,
		source_kind,
		receiver_kind,
		occupied
	)
	if placement_plan.is_empty():
		return empty
	var source_node := placement_plan.get("source_node", {}) as Dictionary
	var receiver_node := placement_plan.get("receiver_node", {}) as Dictionary
	var landmarks: Array = []
	var placements := [
		{
			"kind": source_kind,
			"node": source_node,
			"definition": catalog[source_kind],
			"position": placement_plan.get("source_position", Vector3.INF),
		},
		{
			"kind": receiver_kind,
			"node": receiver_node,
			"definition": catalog[receiver_kind],
			"position": placement_plan.get("receiver_position", Vector3.INF),
		},
	]
	for placement_v in placements:
		var placement := placement_v as Dictionary
		var node := placement["node"] as Dictionary
		var definition := placement["definition"] as Dictionary
		var anchor_position := _array_to_vec3(node.get("position", []), Vector3.ZERO)
		var level := int(node.get("elevation_index", 0))
		var kind := str(placement.get("kind", "infrastructure"))
		var building_position := placement.get("position", Vector3.INF) as Vector3
		if building_position == Vector3.INF:
			return empty
		var toward_anchor := anchor_position - building_position
		var actual_structures: Array = node.get("structures", [])
		var landmark := definition.duplicate(true)
		landmark.merge({
			"id": "infrastructure_%s" % kind,
			"kind": kind,
			"contract_id": "generated_infrastructure_landmark_v1",
			"theme_id": str(theme.get("id", "")),
			"source_area": str(theme.get("source_area", "")),
			"anchor_node_id": str(node.get("id", "")),
			"anchor_structures": actual_structures.duplicate(),
			"position": _vec3_to_array(building_position),
			"elevation_index": level,
			"rotation_y": atan2(toward_anchor.x, toward_anchor.z),
			"primary_read": "%s supplies %s to %s." % [
				kind.replace("_", " ").capitalize(), commodity.replace("_", " "),
				receiver_kind.replace("_", " ").capitalize()],
			"feedback_role": "Its service control draws a visible typed edge to the receiving plant and then to the affected route field.",
		}, true)
		landmarks.append(landmark)
		occupied.append(building_position)

	var source_control := _infrastructure_control_position(grid, source_node, seed, "source")
	var receiver_control := _infrastructure_control_position(grid, receiver_node, seed, "receiver")
	var effect_pos := _infrastructure_effect_position(grid, navigation_grid, receiver_node,
		receiver_control, seed)
	var raw_operation := BuildingFillerScript.service_operation_from_link({
		"commodity": commodity, "from_kind": source_kind, "to_kind": receiver_kind,
		"source_control_pos": source_control, "receiver_control_pos": receiver_control,
		"effect_pos": effect_pos, "effect_half": Vector2(0.66, 0.66),
	})
	raw_operation["contract_id"] = "generated_infrastructure_operation_v1"
	raw_operation["source_node_id"] = str(source_node.get("id", ""))
	raw_operation["receiver_node_id"] = str(receiver_node.get("id", ""))
	raw_operation["source_landmark_id"] = "infrastructure_%s" % source_kind
	raw_operation["receiver_landmark_id"] = "infrastructure_%s" % receiver_kind
	# Generated specs serialize to JSON, so keep vectors in the same numeric-array form as nodes/routes.
	raw_operation["source_control_pos"] = _vec3_to_array(source_control)
	raw_operation["receiver_control_pos"] = _vec3_to_array(receiver_control)
	raw_operation["effect_pos"] = _vec3_to_array(effect_pos)
	raw_operation["effect_half"] = [0.66, 0.66]
	return {"landmarks": landmarks, "operations": [raw_operation]}


static func _infrastructure_pair_matches(source_kind: String, receiver_kind: String, commodity: String) -> bool:
	var source: Dictionary = BaseShapeScript.SPECS.get(source_kind, {})
	var receiver: Dictionary = BaseShapeScript.SPECS.get(receiver_kind, {})
	for source_port_v in source.get("service_ports", []):
		var source_port := source_port_v as Dictionary
		if str(source_port.get("flow", "")) != "out" \
				or str(source_port.get("commodity", "")) != commodity:
			continue
		for receiver_port_v in receiver.get("service_ports", []):
			var receiver_port := receiver_port_v as Dictionary
			if str(receiver_port.get("flow", "")) == "in" \
					and str(receiver_port.get("commodity", "")) == commodity:
				return true
	return false


static func _select_infrastructure_placement(
		grid,
		nodes: Array,
		source_definition: Dictionary,
		receiver_definition: Dictionary,
		seed: int,
		source_kind: String,
		receiver_kind: String,
		occupied: Array[Vector3]
	) -> Dictionary:
	var source_candidates := _infrastructure_anchor_candidates(
		nodes, source_definition, seed, "source")
	var receiver_candidates := _infrastructure_anchor_candidates(
		nodes, receiver_definition, seed, "receiver")
	var source_clearance := float(source_definition.get("clearance", 3.5))
	var receiver_clearance := float(receiver_definition.get("clearance", 3.5))
	for source_node_v in source_candidates:
		var source_node := source_node_v as Dictionary
		var source_node_id := str(source_node.get("id", ""))
		var source_anchor := _array_to_vec3(
			source_node.get("position", []), Vector3.ZERO)
		var source_level := int(source_node.get("elevation_index", 0))
		var source_sites := _themed_landmark_positions(
			grid,
			source_anchor,
			source_level,
			source_clearance,
			seed,
			"infra_%s" % source_kind,
			occupied
		)
		for source_position in source_sites:
			var occupied_after_source: Array[Vector3] = occupied.duplicate()
			occupied_after_source.append(source_position)
			for receiver_node_v in receiver_candidates:
				var receiver_node := receiver_node_v as Dictionary
				if str(receiver_node.get("id", "")) == source_node_id:
					continue
				var receiver_anchor := _array_to_vec3(
					receiver_node.get("position", []), Vector3.ZERO)
				var receiver_level := int(receiver_node.get("elevation_index", 0))
				var receiver_position := _themed_landmark_position(
					grid,
					receiver_anchor,
					receiver_level,
					receiver_clearance,
					seed,
					"infra_%s" % receiver_kind,
					occupied_after_source
				)
				if receiver_position == Vector3.INF:
					continue
				return {
					"source_node": source_node,
					"source_position": source_position,
					"receiver_node": receiver_node,
					"receiver_position": receiver_position,
				}
	return {}


static func _infrastructure_anchor_candidates(
		nodes: Array, definition: Dictionary, seed: int, endpoint: String
	) -> Array:
	var wanted: Array = definition.get("anchor_structures", [])
	var candidates: Array = []
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var node_id := str(node.get("id", ""))
		if str(node.get("role", "")) in ["entry", "boundary", "shelter", "shelter_arrival"]:
			continue
		var matches := 0
		for structure_v in node.get("structures", []):
			if wanted.has(str(structure_v)):
				matches += 1
		candidates.append({
			"node": node,
			"node_id": node_id,
			"score": matches * 1000 + posmod(int(hash(
				"infra-anchor:%d:%s:%s" % [seed, endpoint, node_id])), 1000),
		})
	# Hash collisions must not let implementation-specific sort behavior choose a
	# different authored layout on replay. Node id is the total-order tiebreaker.
	candidates.sort_custom(func(a, b):
		var score_a := int(a.get("score", 0))
		var score_b := int(b.get("score", 0))
		if score_a != score_b:
			return score_a > score_b
		return str(a.get("node_id", "")) < str(b.get("node_id", ""))
	)
	var result: Array = []
	for candidate_v in candidates:
		result.append((candidate_v as Dictionary).get("node", {}) as Dictionary)
	return result


static func _infrastructure_control_position(
		grid, node: Dictionary, seed: int, endpoint: String
	) -> Vector3:
	var center := _array_to_vec3(node.get("position", []), Vector3.ZERO)
	var center_cell: Vector2i = grid.world_to_grid(center)
	var level := int(node.get("elevation_index", 0))
	var offsets: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]
	var start := posmod(int(hash("infra-control:%d:%s:%s" % [seed, endpoint, str(node.get("id", ""))])), offsets.size())
	for i in range(offsets.size()):
		var cell: Vector2i = center_cell + offsets[(start + i) % offsets.size()]
		if grid.is_walkable(cell.x, cell.y, {}, {}, level):
			return grid.grid_to_world(cell, level) + Vector3(0.0, 0.12, 0.0)
	return center + Vector3(0.0, 0.12, 0.0)


static func _infrastructure_effect_position(
		grid, navigation_grid: Dictionary, receiver_node: Dictionary, receiver_control: Vector3, seed: int
	) -> Vector3:
	var level := int(receiver_node.get("elevation_index", 0))
	var receiver_center := _array_to_vec3(receiver_node.get("position", []), receiver_control)
	var best := Vector3.INF
	var best_distance: float = INF
	var levels := _navigation_level_by_cell(navigation_grid)
	for risk_v in navigation_grid.get("risk_cell_list", []):
		if not (risk_v is Dictionary):
			continue
		var raw: Array = (risk_v as Dictionary).get("cell", [])
		if raw.size() < 2:
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var risk_level := int(levels.get("%d:%d" % [cell.x, cell.y], level))
		var world: Vector3 = grid.grid_to_world(cell, risk_level) + Vector3(0.0, 0.05, 0.0)
		var distance: float = world.distance_squared_to(receiver_center)
		if distance < best_distance:
			best_distance = distance
			best = world
	if best != Vector3.INF:
		return best
	# No authored risk cell: choose another reachable neighbour so the receiver and its consequence
	# remain separate visible objects instead of one ambiguous click target.
	var fallback_node := receiver_node.duplicate(true)
	fallback_node["position"] = _vec3_to_array(receiver_control)
	return _infrastructure_control_position(grid, fallback_node, seed + 17, "effect")


## Seat authored district hazards on the SAME risk cells the navigation layer exposes to route preview.
## This keeps the causal model honest: SAFE can price/avoid the deterrent lane before the click, while DIRECT
## visibly crosses it and pays continuous damage. The scene owns the fixture geometry; generation only chooses
## deterministic cells and emits the flat-space coverage contract consumed by the runtime presenter.
static func _build_themed_route_setpieces(navigation_grid: Dictionary, settings: Dictionary) -> Array:
	var theme: Dictionary = settings.get("area_theme", {})
	var definitions: Array = theme.get("route_setpieces", [])
	var risk_entries: Array = navigation_grid.get("risk_cell_list", [])
	if definitions.is_empty() or risk_entries.is_empty() or navigation_grid.is_empty():
		return []
	var grid = GridWorld.from_data(navigation_grid)
	var risk_cells: Array[Vector2i] = []
	for risk_v in risk_entries:
		if not (risk_v is Dictionary):
			continue
		var raw_cell: Array = (risk_v as Dictionary).get("cell", [])
		if raw_cell.size() < 2:
			continue
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if not risk_cells.has(cell):
			risk_cells.append(cell)
	if risk_cells.is_empty():
		return []
	risk_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var level_by_cell := _navigation_level_by_cell(navigation_grid)
	var result: Array = []
	var seed := int(settings.get("seed", 0))
	for definition_v in definitions:
		if not (definition_v is Dictionary):
			continue
		var definition := definition_v as Dictionary
		var wanted := clampi(int(definition.get("count", 3)), 1, 8)
		var count := mini(wanted, risk_cells.size())
		var start := posmod(int(hash("theme-setpiece:%d:%s" % [seed, str(definition.get("id", ""))])), risk_cells.size())
		for i in range(count):
			# Even sampling makes a repeated fixture read as a road system instead of one noisy pile.
			var sample_index := posmod(start + int(floor(float(i) * float(risk_cells.size()) / float(count))), risk_cells.size())
			var cell := risk_cells[sample_index]
			var level := int(level_by_cell.get("%d:%d" % [cell.x, cell.y], 0))
			var position: Vector3 = grid.grid_to_world(cell, level)
			var tangent := _risk_cell_tangent(cell, risk_cells)
			var placed := definition.duplicate(true)
			placed.merge({
				"contract_id": "generated_theme_route_setpiece_v1",
				"theme_id": str(theme.get("id", "")),
				"source_area": str(theme.get("source_area", "")),
				"instance_index": i,
				"id": "%s_%02d" % [str(definition.get("id", "route_setpiece")), i + 1],
				"position": _vec3_to_array(position),
				"rotation_y": -atan2(tangent.y, tangent.x),
				"elevation_index": level,
				"risk_cell": [cell.x, cell.y],
				"half_size": [0.46, 0.46],
				"show_label": i == 0,
			}, true)
			result.append(placed)
	return result


static func _navigation_level_by_cell(navigation_grid: Dictionary) -> Dictionary:
	var result := {}
	for level_v in navigation_grid.get("level_cells", []):
		if not (level_v is Dictionary):
			continue
		var level := int((level_v as Dictionary).get("level", 0))
		for cell_v in (level_v as Dictionary).get("cells", []):
			if cell_v is Array and (cell_v as Array).size() >= 2:
				result["%d:%d" % [int(cell_v[0]), int(cell_v[1])]] = level
	return result


static func _risk_cell_tangent(cell: Vector2i, risk_cells: Array[Vector2i]) -> Vector2:
	var nearest := Vector2i(cell.x + 1, cell.y)
	var nearest_distance := INF
	for other in risk_cells:
		if other == cell:
			continue
		var distance := Vector2(other.x - cell.x, other.y - cell.y).length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
	var tangent := Vector2(nearest.x - cell.x, nearest.y - cell.y)
	return tangent.normalized() if tangent.length_squared() > 0.0 else Vector2.RIGHT


static func _themed_landmark_position(
	grid,
	anchor: Vector3,
	level: int,
	clearance: float,
	seed: int,
	landmark_id: String,
	occupied: Array[Vector3]
) -> Vector3:
	var positions := _themed_landmark_positions(
		grid, anchor, level, clearance, seed, landmark_id, occupied, 1)
	return positions[0] as Vector3 if not positions.is_empty() else Vector3.INF


static func _themed_landmark_positions(
	grid,
	anchor: Vector3,
	level: int,
	clearance: float,
	seed: int,
	landmark_id: String,
	occupied: Array[Vector3],
	max_results: int = 0
) -> Array[Vector3]:
	var directions := [
		Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0),
		Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, -1).normalized(), Vector3(-1, 0, 1).normalized(),
	]
	var positions: Array[Vector3] = []
	var start := posmod(int(hash("theme-site:%d:%s" % [seed, landmark_id])), directions.size())
	# Preserve the original three rings byte-for-byte for every placement that
	# already succeeded. A finite woven graph can extend beyond that legacy local
	# window, though, so continue in the same 2 m cadence to a cap derived from
	# the actual grid and occupied sites rather than silently dropping the theme.
	var radii: Array[float] = [
		clearance + 4.0,
		clearance + 6.0,
		clearance + 8.0,
	]
	var extended_radius := clearance + 10.0
	var radius_cap := _themed_landmark_search_radius_cap(
		grid, anchor, clearance, occupied)
	while extended_radius <= radius_cap + 0.001:
		radii.append(extended_radius)
		extended_radius += 2.0
	for radius in radii:
		for i in range(directions.size()):
			var direction := directions[(start + i) % directions.size()] as Vector3
			var candidate := anchor + direction * float(radius)
			candidate.y = anchor.y
			if _themed_landmark_site_is_clear(grid, candidate, level, clearance, occupied):
				positions.append(candidate)
				if max_results > 0 and positions.size() >= max_results:
					return positions
	return positions


## Finite sufficiency bound for the radial site search. Once a candidate radius
## exceeds the farthest grid corner plus the exact cell-ring margin used by the
## clearance predicate, every direction lies beyond every possible walkable
## cell. Once it also exceeds every occupied site's anchor distance plus the
## unchanged separation threshold, every direction clears existing landmarks.
## Aligning that bound upward to the existing 2 m cadence guarantees the search
## terminates with at least one valid ring without introducing a magic radius.
static func _themed_landmark_search_radius_cap(
	grid,
	anchor: Vector3,
	clearance: float,
	occupied: Array[Vector3]
) -> float:
	var cell_size := maxf(0.01, float(grid.cell_size))
	var anchor_flat := Vector2(anchor.x, anchor.z)
	var grid_origin: Vector3 = grid.origin
	var grid_min := Vector2(grid_origin.x, grid_origin.z)
	var grid_max := grid_min + Vector2(
		maxi(0, int(grid.width)) * cell_size,
		maxi(0, int(grid.height)) * cell_size
	)
	var farthest_grid_corner := 0.0
	for corner in [
		grid_min,
		Vector2(grid_max.x, grid_min.y),
		grid_max,
		Vector2(grid_min.x, grid_max.y),
	]:
		farthest_grid_corner = maxf(
			farthest_grid_corner, anchor_flat.distance_to(corner as Vector2))
	var clearance_cell_radius := int(ceil(
		(clearance + 0.75) / cell_size))
	# The predicate scans a square of cells. This diagonal bound includes the
	# candidate cell itself plus one full cell for floor/world quantization.
	var grid_cell_margin := sqrt(2.0) \
		* float(clearance_cell_radius + 1) * cell_size
	var required_radius := farthest_grid_corner + grid_cell_margin
	var separation_threshold := clearance * 2.0 + 2.0
	for used in occupied:
		if not used.is_finite():
			continue
		required_radius = maxf(
			required_radius,
			anchor_flat.distance_to(Vector2(used.x, used.z))
				+ separation_threshold
		)
	var extended_start := clearance + 10.0
	var additional_steps := maxi(0, int(ceil(
		(required_radius + 0.001 - extended_start) / 2.0)))
	return extended_start + float(additional_steps) * 2.0


static func _themed_landmark_site_is_clear(
	grid, position: Vector3, level: int, clearance: float, occupied: Array[Vector3]
) -> bool:
	for used in occupied:
		if Vector2(used.x - position.x, used.z - position.z).length() < clearance * 2.0 + 2.0:
			return false
	var center: Vector2i = grid.world_to_grid(position)
	var cell_radius := int(ceil((clearance + 0.75) / maxf(0.01, float(grid.cell_size))))
	for dz in range(-cell_radius, cell_radius + 1):
		for dx in range(-cell_radius, cell_radius + 1):
			if grid.is_walkable(center.x + dx, center.y + dz, {}, {}, level):
				return false
	return true


## The WFC analogue of _apply_graybox_layout: node spatial fields come from the room-piece each slot collapsed
## to (position = piece centre, footprint = piece size), not the role-based footprint. Content placements + route
## surfaces + the graybox contract block are otherwise identical, so the chunk + the grid test consume it unchanged.
static func _apply_wfc_graybox(nodes: Array, routes: Array, layout: Dictionary, catalog, settings: Dictionary, budget: Dictionary) -> Dictionary:
	var slot_cells: Dictionary = layout.get("slot_cells", {})
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
		var nid := str(node.get("id", ""))
		var role := str(node.get("role", "mixed"))
		var sc: Dictionary = slot_cells.get(nid, {})
		var level := maxi(0, int(sc.get("level", 0)))
		if not elevation_indices.has(level):
			elevation_indices.append(level)
		var position: Vector3
		var footprint: Vector3
		if sc.is_empty():
			position = _array_to_vec3(node.get("position", [float(i) * 8.0, 0.45, 0.0]), Vector3(float(i) * 8.0, 0.45, 0.0))
			footprint = _graybox_node_footprint(role, node)
		else:
			position = GridStitcherScript.node_world(slot_cells, nid)
			var fc: Array = sc.get("footprint", [4, 4])
			footprint = Vector3(float(fc[0]), 0.14, float(fc[1]))
		var surface_y := position.y
		var feature: Dictionary = node.get("spatial_feature", {})
		var interaction_offset := _array_to_vec3(
			feature.get("interaction_socket", []), Vector3.INF
		) if not feature.is_empty() else Vector3.INF
		var approach := (
			position + interaction_offset
			if interaction_offset != Vector3.INF
			else position + _graybox_approach_offset(role, footprint)
		)
		var placements := _build_graybox_content_placements(node, position, footprint, catalog)
		content_placement_count += placements.size()
		if not feature.is_empty():
			feature["position"] = _vec3_to_array(position)
			feature["footprint"] = _vec3_to_array(footprint)
			feature["elevation_index"] = level
			feature["socket_assignments"] = _spatial_feature_socket_assignments(placements)
			node["spatial_feature"] = feature

		node["position"] = _vec3_to_array(position)
		node["elevation_index"] = level
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
		"layout_engine": "wfc_v1",
		"roompiece_catalog": "trawf_roompiece_catalog_v1",
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

# How many stacked DATA floors a tier may use. Verticality is EARNED, not the default: teaching/standard levels
# are FLAT (1 floor) — unconditional per-node-index elevation would give every level 3 floors, which reads as
# confusing stacked ribbons. (Note: the RENDER can still spiral a flat level into a climbing helix via the
# coord_map — that's a separate warp, not data floors.)
const TIER_MAX_LEVELS := {"teaching": 1, "standard": 1, "hard": 2, "setpiece": 3}

static func _graybox_elevation_index(node: Dictionary, index: int, node_count: int, max_levels: int = 3) -> int:
	if max_levels <= 1:
		return 0
	var role := str(node.get("role", "mixed"))
	if index == 0 or index == node_count - 1 or role in ["boundary", "shelter", "shelter_arrival"]:
		return 0
	var layout: Dictionary = node.get("layout_step", {})
	var turn := int(layout.get("turn", (index % 3) - 1))
	var lane := int(layout.get("lane", 0))
	var top := max_levels - 1
	var elevation_index := clampi(1 + turn, 0, top)
	if role == "setpiece":
		elevation_index += 1
	elif role == "danger" and lane < 0:
		elevation_index -= 1
	elif role == "foraging" and lane == 0:
		elevation_index += 1
	return clampi(elevation_index, 0, top)

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
	# Shelter dressing occupies the positive-Z half of its pad. Approach from the
	# open face so the camera can see the party and Home never recenters on a shell.
	if role in ["boundary", "shelter", "shelter_arrival"]:
		return Vector3(-footprint.x * 0.12, 0.0, -footprint.z * 0.38)
	if role in ["danger", "route_pressure"]:
		return Vector3(-footprint.x * 0.22, 0.0, z_offset)
	return Vector3(0.0, 0.0, z_offset)

static func _build_graybox_content_placements(node: Dictionary, node_position: Vector3, footprint: Vector3, catalog) -> Array:
	var placements := []
	var slot_index := 0
	var category_indices := {}
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var content_id := str(value)
			# Never turn a design noun into a box, cylinder, or billboard. A generated
			# placement exists only when this presenter can instantiate the noun's real
			# gameplay contract; the warning report records everything omitted.
			if not RuntimeRegistryScript.generated_content_is_realized(category, content_id):
				continue
			var size := _graybox_content_size(category, content_id)
			var category_index := int(category_indices.get(category, 0))
			var socket := _spatial_feature_content_socket(node, category, category_index)
			var offset := (
				_array_to_vec3(socket.get("offset", []), Vector3.ZERO)
				if not socket.is_empty()
				else _graybox_content_offset(category, slot_index, footprint)
			)
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
				"socket_id": str(socket.get("id", "")),
			})
			slot_index += 1
			category_indices[category] = category_index + 1
	return placements


static func _spatial_feature_content_socket(
		node: Dictionary, category: String, category_index: int) -> Dictionary:
	var feature: Dictionary = node.get("spatial_feature", {})
	var sockets: Dictionary = feature.get("content_sockets", {})
	var category_sockets: Array = sockets.get(category, [])
	if category_index < 0 or category_index >= category_sockets.size():
		return {}
	var socket_prefix := str({
		"flora": "flora", "enemies": "enemy", "structures": "structure",
	}.get(category, category))
	return {
		"id": "%s_%d" % [socket_prefix, category_index],
		"offset": category_sockets[category_index],
	}


static func _spatial_feature_socket_assignments(placements: Array) -> Array:
	var assignments: Array = []
	for placement_v in placements:
		if not (placement_v is Dictionary):
			continue
		var placement := placement_v as Dictionary
		var socket_id := str(placement.get("socket_id", ""))
		if socket_id == "":
			continue
		assignments.append({
			"socket": socket_id,
			"category": str(placement.get("category", "")),
			"content_id": str(placement.get("id", "")),
			"position": (placement.get("position", []) as Array).duplicate(),
		})
	return assignments

static func _graybox_content_offset(category: String, slot_index: int, footprint: Vector3) -> Vector3:
	var stagger := float(slot_index % 3) - 1.0
	match category:
		"flora":
			return Vector3(-footprint.x * 0.32 + stagger * 0.28, 0.0, -footprint.z * 0.28)
		"enemies":
			return Vector3(footprint.x * 0.30, 0.0, footprint.z * 0.24 + stagger * 0.3)
		"structures":
			return Vector3(footprint.x * 0.26 + stagger * 0.28, 0.0, footprint.z * 0.28)
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
			"scarpet", "capbage":
				return "cover"
			"seefern":
				return "readable_screen"
			"climbvine", "resolution_roots":
				return "traversal"
			"flure", "mother_flure":
				return "puzzle_flora"
			"gasafoetida":
				return "design_placeholder"
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
			"capbage":
				return Vector3(1.2, 1.4, 1.2)
			"gasafoetida":
				return Vector3(1.1, 1.2, 1.1)
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
			"hidras", "redactors":
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


static func _party_spawn_positions(anchors: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for char_id in PARTY_SPAWN_IDS:
		if not anchors.has(char_id):
			continue
		var position := _array_to_vec3(anchors.get(char_id, []), Vector3.INF)
		if not position.is_finite():
			continue
		result.append({"character_id": char_id, "position": position})
	return result


static func _placement_world_position(
	placement: Dictionary, node: Dictionary
	) -> Vector3:
	var direct := _array_to_vec3(placement.get("position", []), Vector3.INF)
	if direct.is_finite():
		return direct
	var node_position := _array_to_vec3(node.get("position", []), Vector3.INF)
	var local_offset := _array_to_vec3(
		placement.get("local_offset", []), Vector3.INF)
	if node_position.is_finite() and local_offset.is_finite():
		return node_position + local_offset
	return Vector3.INF


static func _placement_spawn_clearance_radius(placement: Dictionary) -> float:
	var size := _array_to_vec3(
		placement.get("size", []), Vector3(1.0, 1.0, 1.0))
	var presenter_radius := Vector2(size.x, size.z).length() * 0.5
	match str(placement.get("id", "")):
		"capbage":
			presenter_radius = maxf(
				presenter_radius,
				maxf(1.4, float(placement.get("conceal_radius", 1.4)))
			)
		"scarpet":
			presenter_radius = maxf(
				presenter_radius,
				maxf(1.65, float(placement.get("conceal_radius", 1.65)))
			)
		"hushbloom":
			presenter_radius = maxf(presenter_radius, 1.1)
	return presenter_radius + PARTY_SPAWN_BODY_RADIUS \
		+ PARTY_SPAWN_CONTENT_MARGIN


static func _placement_overlaps_party_spawn(
	placement: Dictionary,
	node: Dictionary,
	spawn_positions: Array[Dictionary]
	) -> bool:
	if not RuntimeRegistryScript.generated_content_is_realized(
			str(placement.get("category", "")),
			str(placement.get("id", ""))):
		return false
	var position := _placement_world_position(placement, node)
	if not position.is_finite():
		return true
	var clearance := _placement_spawn_clearance_radius(placement)
	for spawn_v in spawn_positions:
		var spawn_position := (spawn_v as Dictionary).get(
			"position", Vector3.INF) as Vector3
		if not spawn_position.is_finite():
			continue
		if Vector2(position.x - spawn_position.x,
				position.z - spawn_position.z).length() + 0.001 < clearance:
			return true
	return false


## Generated content is allowed to be near the entry, but never inside the
## three-character deployment formation. Removing the placement and its semantic
## noun together is intentional: a missing real mechanism is honest; retaining a
## hidden noun or collision-only proxy is not. Non-entry overlaps are left for
## `validate_party_spawn_clearance` to reject, since silently deleting a causal
## interior mechanism could change the solution.
static func _exclude_entry_spawn_overlaps(
	nodes: Array, anchors: Dictionary
	) -> int:
	var spawn_positions := _party_spawn_positions(anchors)
	if spawn_positions.size() != PARTY_SPAWN_IDS.size():
		return 0
	var excluded_count := 0
	for node_index in range(nodes.size()):
		if not (nodes[node_index] is Dictionary):
			continue
		var node := nodes[node_index] as Dictionary
		if str(node.get("id", "")) != "entry" \
				and str(node.get("role", "")) != "boundary":
			continue
		var retained: Array = []
		var excluded_keys := {}
		var excluded_socket_ids := {}
		for placement_v in node.get("content_placements", []):
			if not (placement_v is Dictionary):
				retained.append(placement_v)
				continue
			var placement := placement_v as Dictionary
			if not _placement_overlaps_party_spawn(
					placement, node, spawn_positions):
				retained.append(placement)
				continue
			excluded_count += 1
			excluded_keys[
				"%s:%s" % [str(placement.get("category", "")),
				str(placement.get("id", ""))]
			] = true
			var socket_id := str(placement.get("socket_id", ""))
			if socket_id != "":
				excluded_socket_ids[socket_id] = true
		node["content_placements"] = retained
		for key_v in excluded_keys.keys():
			var parts := str(key_v).split(":", false, 1)
			if parts.size() != 2:
				continue
			var category := str(parts[0])
			var content_id := str(parts[1])
			var still_placed := false
			for placement_v in retained:
				if placement_v is Dictionary \
						and str((placement_v as Dictionary).get(
							"category", "")) == category \
						and str((placement_v as Dictionary).get(
							"id", "")) == content_id:
					still_placed = true
					break
			if not still_placed:
				var declared: Array = node.get(category, [])
				declared.erase(content_id)
				node[category] = declared
		if not excluded_socket_ids.is_empty():
			var feature: Dictionary = node.get("spatial_feature", {})
			if not feature.is_empty():
				var assignments: Array = []
				for assignment_v in feature.get("socket_assignments", []):
					if assignment_v is Dictionary and excluded_socket_ids.has(
							str((assignment_v as Dictionary).get("socket", ""))):
						continue
					assignments.append(assignment_v)
				feature["socket_assignments"] = assignments
				node["spatial_feature"] = feature
		nodes[node_index] = node
	return excluded_count


static func _content_placement_count(nodes: Array) -> int:
	var count := 0
	for node_v in nodes:
		if node_v is Dictionary:
			count += ((node_v as Dictionary).get(
				"content_placements", []) as Array).size()
	return count


## Re-project semantic nouns after a spawn-colliding crucial clue is relocated.
## Coverage is not real unless the fallback noun gets the same portable content
## placement and spatial-socket receipt that the runtime presenter consumes.
static func _rebuild_declared_content_placements(
		nodes: Array, catalog, node_indices: Array[int]
	) -> void:
	for node_index in node_indices:
		if node_index < 0 or node_index >= nodes.size() \
				or not (nodes[node_index] is Dictionary):
			continue
		var node := nodes[node_index] as Dictionary
		var position := _array_to_vec3(node.get("position", []), Vector3.INF)
		var footprint := _array_to_vec3(node.get("footprint", []), Vector3.INF)
		if not position.is_finite() or not footprint.is_finite():
			continue
		var placements := _build_graybox_content_placements(
			node, position, footprint, catalog)
		node["content_placements"] = placements
		var feature_v: Variant = node.get("spatial_feature", {})
		if feature_v is Dictionary and not (feature_v as Dictionary).is_empty():
			var feature := feature_v as Dictionary
			feature["socket_assignments"] = _spatial_feature_socket_assignments(
				placements)
			node["spatial_feature"] = feature
		nodes[node_index] = node


static func _build_anchors(nodes: Array) -> Dictionary:
	var anchors := {}
	var entry_pos: Array = [0.0, 0.45, 0.0]
	var entry_approach: Array = []
	for node in nodes:
		if node is Dictionary:
			var id := str((node as Dictionary).get("id", ""))
			var pos: Array = (node as Dictionary).get("position", [0.0, 0.45, 0.0])
			anchors[id] = pos
			if id == "entry":
				entry_pos = pos
				entry_approach = (node as Dictionary).get("approach_position", [])
	# Spawn on the entry's open approach face, not at the structural anchor under
	# the shelter shell. The fan is wide enough to keep all characters readable.
	var spawn := entry_approach if entry_approach.size() >= 3 else entry_pos
	var ex := float(spawn[0])
	var ey := float(spawn[1]) + 0.05
	var ez := float(spawn[2])
	anchors["aster"] = [ex, ey, ez]
	anchors["peris"] = [ex + 0.9, ey, ez + 0.28]
	anchors["endo"] = [ex - 0.9, ey, ez + 0.28]
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
	# Report only child mechanisms that survived the runtime-binding boundary. The
	# composition planner may propose nested prose, but it is not playable content
	# until a node carries the exact typed child binding.
	var nested: Array = []
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		for nested_v in (node_v as Dictionary).get("nested_archetypes", []):
			if nested_v is Dictionary:
				nested.append((nested_v as Dictionary).duplicate(true))
	var max_depth := 0
	for entry in nested:
		if entry is Dictionary:
			max_depth = maxi(max_depth, int((entry as Dictionary).get("depth", 1)))
	var runtime_input_refs := {}
	var runtime_output_refs := {}
	for node_v in nodes:
		if not (node_v is Dictionary):
			continue
		var runtime_input := str((node_v as Dictionary).get("runtime_chain_input_ref", ""))
		var runtime_output := str((node_v as Dictionary).get("runtime_chain_output_ref", ""))
		if runtime_input != "":
			runtime_input_refs[runtime_input] = true
		if runtime_output != "":
			runtime_output_refs[runtime_output] = true
	var links := []
	var runtime_bound_link_count := 0
	for i in range(chain.size() - 1):
		var current: Dictionary = chain[i]
		var next: Dictionary = chain[i + 1]
		var output_ref := str(current.get("output", ""))
		var input_ref := str(next.get("input", ""))
		var runtime_bound := (
			output_ref != ""
			and output_ref == input_ref
			and runtime_output_refs.has(output_ref)
			and runtime_input_refs.has(input_ref)
		)
		if runtime_bound:
			runtime_bound_link_count += 1
		links.append({
			"from_chain_index": i,
			"to_chain_index": i + 1,
			"from_archetype": str(current.get("id", "")),
			"to_archetype": str(next.get("id", "")),
			"output": output_ref,
			"input": input_ref,
			"feeds_next": output_ref != "" and output_ref == input_ref,
			"runtime_bound": runtime_bound,
			"authority": "exact_mechanism_predicate" if runtime_bound else "layout_concept_only",
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
		"runtime_bound_link_count": runtime_bound_link_count,
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

## Report requested palette nouns that cannot enter the playable runtime. They are
## deliberately omitted rather than rendered as suggestive graybox stand-ins.
static func _collect_warnings(catalog, nodes: Array, composition := {}) -> Array:
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
				if not RuntimeRegistryScript.generated_content_is_realized(category, str(key)):
					var omitted := RuntimeRegistryScript.generated_content_omission(
						category, str(key)
					)
					omitted["palette_support"] = catalog.support_level(category, str(key))
					warnings.append(omitted)
	if composition is Dictionary:
		for nested_v in (composition as Dictionary).get("nested", []):
			if not (nested_v is Dictionary) \
					or _nested_entry_has_runtime_binding(nested_v as Dictionary):
				continue
			warnings.append({
				"kind": "omitted_generated_mechanic",
				"reason": "missing_nested_runtime_binding",
				"host_archetype": str((nested_v as Dictionary).get("host_id", "")),
				"nested_archetype": str((nested_v as Dictionary).get("nested_id", "")),
				"required_fields": [
					"runtime_handler",
					"mechanism_id",
					"output_source_id",
					"completion_predicate",
				],
			})
	return warnings

static func _golden_path(nodes: Array) -> Array:
	var path := []
	for node in nodes:
		if node is Dictionary and not bool((node as Dictionary).get("optional", false)):
			path.append(str((node as Dictionary).get("id", "")))
	return path

## The generated puzzle's SOLUTION as replayable DATA: the golden (full-party) path as an ordered list of the
## exact action to take at each node — which APPROACH clears it, its kind/risk, and any ability the approach needs.
## Emitted into the spec so a test can, from the same seed, regenerate the identical puzzle AND drive this solution
## end-to-end (walk to each node, interact, cast the ability) as if a real player were playing it. Deterministic:
## the solver is a pure function of the (deterministic) spec, so the same seed yields the same solution.
static func _solution_script(solution: Dictionary, golden_path: Array) -> Dictionary:
	var paths: Array = solution.get("solution_paths", [])
	var chosen := {}
	for p in paths:
		if p is Dictionary and str((p as Dictionary).get("loadout", "")) == "spotlight":
			chosen = p
			break
	if chosen.is_empty() and not paths.is_empty() and paths[0] is Dictionary:
		chosen = paths[0]
	var per_node := {}
	for ap in chosen.get("approach_per_node", []):
		if ap is Dictionary:
			per_node[str((ap as Dictionary).get("node", ""))] = ap
	var actions: Array = []
	for node_id in golden_path:
		var ap: Dictionary = per_node.get(str(node_id), {})
		var runtime_handler := str(ap.get("runtime_handler", ""))
		if runtime_handler == "":
			continue
		var requires: Array = ap.get("requires", [])
		actions.append({
			"node": str(node_id),
			"runtime_handler": runtime_handler,
			"approach_id": str(ap.get("approach_id", ap.get("id", "traverse"))),
			"kind": str(ap.get("kind", "traverse")),
			"risk": str(ap.get("risk", "safe")),
			"party": str(ap.get("party", "any")),
			"requires": requires.duplicate() if requires is Array else [],
		})
	return {
		"loadout": str(chosen.get("loadout", "spotlight")),
		"reaches": "exit_shelter",
		"solvable": bool(chosen.get("solvable", true)),
		"actions": actions,
		"branch_actions": (solution.get("branch_actions", []) as Array).duplicate(true),
	}

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
				"trigger_flare_burst":
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
		"2":
			# Plant-as-tool only needs fauna when the named plant verb acts on fauna. The old
			# catalog tagged this archetype enemy_routing but emitted an empty target set,
			# leaving Flure/Hushbloom beats as decorative plants beside an abstract button.
			if variant == "flure_iron_decoy":
				return [["siderophore", "iron", "patrol"]]
			if variant == "hushbloom_stun":
				return [["patrol", "enforcement", "hunter"]]
			return []
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
		"forage":
			# The lysate cache is the forage affordance; flora only provides nearby cover.
			needs.append({"tag": "cover"})
		"rest":
			# Capbage supports the authored field hide-rest (survival, never HP recovery).
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
## stray shelter on an interior node (a mid-stretch shelter undercuts the find-shelter tension).
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

# --- POI distribution (Layer A: crucial-element coverage + shared-element merge + progression density) ----------

## The element keys a node's PLAYABLE content currently supplies. Once layout
## has emitted `content_placements`, that list is authoritative: a semantic noun
## without a portable runtime binding must never make the coverage report green.
## Before layout, only runtime-bound declared nouns participate in the injection
## pass, so an unsupported palette entry cannot suppress a real fallback clue.
static func _node_supplied_elements(node: Dictionary, distribution) -> Array:
	var out := {}
	if node.has("content_placements"):
		for placement_v in node.get("content_placements", []):
			if not (placement_v is Dictionary):
				continue
			var placement := placement_v as Dictionary
			var category := str(placement.get("category", ""))
			var content_id := str(placement.get("id", ""))
			if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id):
				continue
			for key in distribution.satisfies(category, content_id):
				out[key] = true
		return out.keys()
	for category in ["flora", "structures"]:
		for content_id_v in node.get(category, []):
			var content_id := str(content_id_v)
			if not RuntimeRegistryScript.generated_content_is_realized(
					category, content_id):
				continue
			for key in distribution.satisfies(category, content_id):
				out[key] = true
	return out.keys()

## Guarantee every archetype's crucial element is realized as content SOMEWHERE in the stretch. Because coverage is
## keyed by ELEMENT (not by node), a shared element placed once already covers every archetype that needs it — the
## merge is structural. We only inject when an element is entirely absent AND the palette can supply it; otherwise
## the element is left unsatisfiable (the bare pair's base capabilities still guarantee solvability via the solver).
static func _guarantee_element_coverage(
		nodes: Array,
		distribution,
		available_flora: Array,
		available_structures: Array,
		avoid_entry_boundaries := false
	) -> Array[int]:
	var changed_node_indices: Array[int] = []
	var covered := {}
	for node in nodes:
		if node is Dictionary:
			for key in _node_supplied_elements(node, distribution):
				covered[key] = true
	for requesting_index in range(nodes.size()):
		var requesting_node_v: Variant = nodes[requesting_index]
		if not (requesting_node_v is Dictionary):
			continue
		var requesting_node := requesting_node_v as Dictionary
		for key in distribution.crucial_elements_for(requesting_node):
			if covered.has(key):
				continue
			var ec: Dictionary = distribution.element_content(str(key))
			if _coverage_injection_node_allowed(
					requesting_node, avoid_entry_boundaries) \
					and _inject_element_content(
					requesting_node, ec, available_flora, available_structures):
				covered[key] = true
				if not changed_node_indices.has(requesting_index):
					changed_node_indices.append(requesting_index)
				continue
			# Coverage is a stretch-level contract. A dense late-stage requesting node
			# may already be at its local flora/structure cap; in that case, place the
			# same authored clue on the first other node with room instead of silently
			# reporting an uncovered crucial element. Requesting-node preference keeps
			# the clue local whenever possible, while this deterministic fallback makes
			# the implementation match the documented "somewhere in the stretch" rule.
			for fallback_index in range(nodes.size()):
				var fallback_node_v: Variant = nodes[fallback_index]
				if fallback_index == requesting_index \
						or not (fallback_node_v is Dictionary) \
						or not _coverage_injection_node_allowed(
							fallback_node_v as Dictionary, avoid_entry_boundaries):
					continue
				if _inject_element_content(
						fallback_node_v as Dictionary,
						ec,
						available_flora,
						available_structures):
					covered[key] = true
					if not changed_node_indices.has(fallback_index):
						changed_node_indices.append(fallback_index)
					break
	return changed_node_indices


static func _inject_element_content(
		node: Dictionary,
		element_content: Dictionary,
		available_flora: Array,
		available_structures: Array
	) -> bool:
	# Prefer flora (cheap, no structure-placement rules), capped so a node never
	# floods with plants. The same caps governed the original local-only path.
	var flora_v: Variant = node.get("flora", [])
	if flora_v is Array and (flora_v as Array).size() < 3:
		for fid_v in element_content.get("flora", []):
			var fid := str(fid_v)
			if available_flora.has(fid) \
					and RuntimeRegistryScript.generated_content_is_realized(
						"flora", fid) \
					and not (flora_v as Array).has(fid):
				(flora_v as Array).append(fid)
				return true
	var structures_v: Variant = node.get("structures", [])
	if structures_v is Array and (structures_v as Array).size() < 2:
		for sid_v in element_content.get("structures", []):
			var sid := str(sid_v)
			if available_structures.has(sid) \
					and RuntimeRegistryScript.generated_content_is_realized(
						"structures", sid) \
					and not (structures_v as Array).has(sid):
				(structures_v as Array).append(sid)
				return true
	return false


static func _coverage_injection_node_allowed(
		node: Dictionary, avoid_entry_boundaries: bool
	) -> bool:
	if not avoid_entry_boundaries:
		return true
	return str(node.get("id", "")) != "entry" \
		and str(node.get("role", "")) not in [
			"boundary", "shelter", "shelter_arrival",
		]

## Compute the coverage report for the spec: which crucial elements each stretch requires, which are covered, and
## which are SHARED (required by more than one distinct archetype — placed once, used by all). Pure read, no mutation.
static func _compute_element_coverage(nodes: Array, distribution) -> Dictionary:
	var required_by := {}     # element key -> {archetype_id: true}
	var covered_by := {}      # element key -> [node ids that supply it]
	for node in nodes:
		if not (node is Dictionary):
			continue
		var arche := str(node.get("archetype_id", ""))
		for key in distribution.crucial_elements_for(node):
			if not required_by.has(key):
				required_by[key] = {}
			if arche != "":
				required_by[key][arche] = true
		for key in _node_supplied_elements(node, distribution):
			if not covered_by.has(key):
				covered_by[key] = []
			(covered_by[key] as Array).append(str(node.get("id", "")))
	var elements := {}
	var uncovered := []
	var shared := []
	for key in required_by.keys():
		var archs: Array = (required_by[key] as Dictionary).keys()
		var supply: Array = covered_by.get(key, [])
		var is_covered := not supply.is_empty()
		elements[key] = {"covered": is_covered, "supplied_by": supply, "required_by": archs}
		if not is_covered:
			uncovered.append(str(key))
		if archs.size() > 1:
			shared.append(str(key))
	uncovered.sort()
	shared.sort()
	return {
		"contract_id": "trawf_element_coverage_v2",
		"coverage_scope": "realized_runtime_content",
		"elements": elements,
		"required_count": required_by.size(),
		"covered_count": required_by.size() - uncovered.size(),
		"uncovered": uncovered,
		"complete": uncovered.is_empty(),
		"shared_elements": shared,
	}

## Scatter cosmetic AMBIENT POIs onto interior nodes. Later stages may use a richer
## palette, but these live on a separate list the solver and systems curriculum
## ignore; they are presentation, never the source of reasoning difficulty.
static func _apply_poi_density(nodes: Array, distribution, stage: int, rng) -> Dictionary:
	var count: int = distribution.ambient_count(stage)
	var variety: int = distribution.ambient_variety(stage)
	var pool: Array = distribution.ambient_flora()
	var total := 0
	var used := {}
	for node in nodes:
		if not (node is Dictionary):
			continue
		if str(node.get("role", "")) in ["boundary", "shelter_arrival"]:
			continue
		if pool.is_empty():
			continue
		var ambient := []
		var allowed_variety := mini(variety, pool.size())
		for k in range(count):
			# Round-robin through the first `allowed_variety` pool entries, jittered by the node + index so two
			# nodes don't read identically but the choice stays seed-deterministic (no wall-clock).
			var jitter := int(rng.call("randi_range", 0, maxi(0, allowed_variety - 1))) if allowed_variety > 0 else 0
			var pick := str(pool[(k + jitter) % allowed_variety]) if allowed_variety > 0 else ""
			if pick != "":
				ambient.append(pick)
				used[pick] = true
				total += 1
		node["ambient_flora"] = ambient
	return {
		"contract_id": "trawf_poi_density_v1",
		"stage": stage,
		"per_node_count": count,
		"per_node_variety": variety,
		"total_ambient": total,
		"distinct_ambient": used.keys().size(),
	}

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
