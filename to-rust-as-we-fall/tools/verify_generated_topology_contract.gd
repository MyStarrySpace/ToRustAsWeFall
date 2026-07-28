extends SceneTree

const Weaver := preload("res://scripts/generation/stretch_branch_weaver.gd")
const Generator := preload("res://scripts/generation/stretch_generator.gd")
const Solver := preload("res://scripts/generation/stretch_solution_solver.gd")
const SpiralTemplate := preload("res://scripts/generation/spiral_meta_template.gd")
const GridWorldScript := preload("res://scripts/game/world/grid_world.gd")

const HYDRAULIC_SPEC_PATH := \
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	verify_branch_roles()
	verify_generator_branch_solution_projection()
	verify_saved_hydraulic_topology_projection()
	verify_gated_spiral_returns()
	verify_semantic_topology_guard()
	if _failures == 0:
		print("Generated topology contract: %d checks passed." % _checks)
		quit(0)
	else:
		push_error("Generated topology contract: %d/%d checks failed." % [_failures, _checks])
		quit(1)


func verify_branch_roles() -> void:
	var spine := _line_grid(96)
	var woven: Dictionary = Weaver.weave(
		spine, {"seed": 9127, "tier": "teaching", "stage": 1, "count": 3}
	)
	var branches: Array = woven.get("branches", [])
	check(branches.size() == 3, "an explicit three-spoke weave emits three purposeful branches")
	var roles := []
	for branch_v in branches:
		var branch := branch_v as Dictionary
		roles.append(str(branch.get("role", "")))
		var contract: Dictionary = branch.get("causal_contract", {})
		check(
			str(contract.get("contract_id", "")) == "generated_branch_role_v1"
			and bool(contract.get("cannot_bypass_unresolved", false)),
			"%s carries the unresolved-blocker contract" % str(branch.get("id", "branch"))
		)
	check(
		roles == ["mandatory_producer", "optional_risk_reward", "mandatory_producer"],
		"woven rooms alternate required production and priced optional bets"
	)
	check(
		bool(Weaver.validate_branch_contracts(branches, woven).get("valid", false)),
		"woven branches pass the shared semantic-role guard"
	)
	var producer: Dictionary = branches[0]
	var reward: Dictionary = branches[1]
	var producer_contract: Dictionary = producer.get("causal_contract", {})
	var producer_cell = producer_contract.get("producer_cell", null)
	var consumer_cell = producer_contract.get("consumer_cell", null)
	var consumer_cells: Array = producer_contract.get("consumer_cells", [])
	check(
		bool(producer.get("required_for_progress", false))
		and str(producer_contract.get("consumer_policy", ""))
		== "next_unresolved_spine_blocker",
		"mandatory branch output is consumed by the next spine blocker"
	)
	check(
		producer_cell is Array
		and (producer_cell as Array).size() >= 2
		and (producer.get("cells", []) as Array).has(producer_cell)
		and not consumer_cells.is_empty()
		and consumer_cell is Array
		and (consumer_cell as Array).size() >= 2
		and consumer_cells.has(consumer_cell)
		and (woven.get("walkable_cells", []) as Array).has(consumer_cell)
		and not (producer.get("cells", []) as Array).has(consumer_cell)
		and int((consumer_cell as Array)[0])
			> _max_cell_x(producer.get("cells", [])),
		"mandatory branch names an exact later-spine cut plus its visual midpoint"
	)
	check_cut_disconnect_and_restore(woven, consumer_cells, "branch_00 consumer cut")
	check(
		str(reward.get("causal_contract", {}).get("content_policy", ""))
		== "risk_scaled_physical_reward"
		and str(reward.get("causal_contract", {}).get("topology_effect", "")) == "none",
		"optional branch buys a physical reward without changing progression topology"
	)
	check(
		not roles.has("recovery_return"),
		"woven rooms do not claim the meta-template's separate recovery mechanic"
	)

	var deep_woven: Dictionary = Weaver.weave(
		spine, {"seed": 9127, "tier": "teaching", "stage": 9, "count": 3}
	)
	check(
		JSON.stringify(woven.get("walkable_cells", []))
		== JSON.stringify(deep_woven.get("walkable_cells", [])),
		"campaign stage does not add empty walking-distance branches"
	)
	check(
		JSON.stringify((woven.get("branches", []) as Array)[0].get("causal_contract", {}))
		== JSON.stringify((deep_woven.get("branches", []) as Array)[0].get("causal_contract", {})),
		"exact branch producer and consumer addresses are stage-independent"
	)
	var setpiece_woven: Dictionary = Weaver.weave(
		spine, {"seed": 9127, "tier": "setpiece", "stage": 9}
	)
	check(
		(setpiece_woven.get("branches", []) as Array).size() == 2,
		"the default weave stays at one producer plus one priced detour at every pressure tier"
	)


func verify_generator_branch_solution_projection() -> void:
	var generated := Generator.generate({
		"id": "topology_projection_9127",
		"seed": 9127,
		"complexity_tier": "standard",
		"budget": {"node_count": 7},
		"spatial_profile": {"branch_room_count": 3},
	})
	check(
		bool(generated.get("success", false)),
		"generator emits its fixed branch topology before solver analysis: %s"
				% str(generated.get("validation", generated.get("error", "")))
	)
	if not bool(generated.get("success", false)):
		return
	var spine: Dictionary = generated.get("spine_navigation_grid", {})
	var navigation: Dictionary = generated.get("navigation_grid", {})
	var branches: Array = navigation.get("branches", [])
	check(
		str(navigation.get("branch_weave_contract_id", ""))
		== Weaver.BRANCH_WEAVE_CONTRACT_ID
		and branches.size() == 3
		and (spine.get("branches", []) as Array).is_empty(),
		"spec separates the bare macro-shape spine from three authoritative woven branches"
	)
	var semantic_return_routes := []
	for route_v in generated.get("routes", []):
		if route_v is Dictionary and (
			str((route_v as Dictionary).get("kind", "")) == "shortcut"
			or str((route_v as Dictionary).get("topology_role", "")) == "recovery_return"
		):
			semantic_return_routes.append(route_v)
	var return_policy: Dictionary = generated.get("topology_contract", {}).get(
		"return_policy", {}
	)
	check(
		semantic_return_routes.is_empty()
		and str(return_policy.get("authority", ""))
			== "runtime_meta_template_climbvine_state"
		and not bool(return_policy.get("semantic_route_may_unlock", true)),
		"generator leaves recovery to the real ClimbvineReturn instead of emitting a metadata shortcut"
	)
	check(
		not (generated.get("settings", {}).get("budget", {}) as Dictionary).has(
			"shortcut_count"
		),
		"generation no longer budgets an abstract shortcut independently of the meta-template"
	)
	var twice := Weaver.weave(navigation, {
		"seed": 42, "tier": "setpiece", "count": 6,
	})
	check(
		JSON.stringify(twice) == JSON.stringify(navigation),
		"an emitted branch weave is idempotent even when a later caller supplies different options"
	)
	var expected_actions: Array = Solver.mandatory_branch_actions(
		branches, generated.get("nodes", []), navigation
	)
	var headless_actions: Array = generated.get("headless", {}).get(
		"solution", {}
	).get("branch_actions", [])
	check(
		expected_actions.size() == 2
		and _serialized_variants_equal(headless_actions, expected_actions),
		"headless solution emits one exact interaction for each mandatory "
		+ "producer and none for the reward branch"
	)
	for action_v in headless_actions:
		var action := action_v as Dictionary
		var matching_branch := _branch_by_id(branches, str(action.get("branch_id", "")))
		var contract: Dictionary = matching_branch.get("causal_contract", {})
		check(
			str(action.get("runtime_handler", "")) == "branch_span_producer"
			and str(action.get("activation_policy", "")) == "interact_at_producer"
			and (action.get("producer_cell", []) as Array).size() == 2
			and (action.get("consumer_cell", []) as Array).size() == 2
			and not (action.get("consumer_cells", []) as Array).is_empty()
			and JSON.stringify(action.get("consumer_cells", []))
			== JSON.stringify(contract.get("consumer_cells", []))
			and str(action.get("before_node", "")) != ""
			and str(action.get("expected_phase", "")) == "bridged"
			and bool(action.get("wait_for_completion", false))
			and bool(action.get("cannot_bypass_unresolved", false)),
			"%s names its physical producer, blocked span, and bridged completion"
					% str(action.get("id", "branch action"))
		)
		check_cut_disconnect_and_restore(
			navigation,
			action.get("consumer_cells", []),
			"%s emitted cut" % str(action.get("id", "branch action"))
		)
	var solved_again := Solver.analyze_spec(generated)
	check(
		JSON.stringify(solved_again.get("branch_actions", []))
		== JSON.stringify(expected_actions)
		and int(solved_again.get("mandatory_branch_action_count", 0)) == 2,
		"standalone solver analysis consumes persisted navigation branches"
	)
	var invalid_cut_spec := generated.duplicate(true)
	var invalid_navigation: Dictionary = invalid_cut_spec.get("navigation_grid", {})
	var invalid_branches: Array = invalid_navigation.get("branches", [])
	var first_mandatory := _first_mandatory_branch_index(invalid_branches)
	if first_mandatory >= 0:
		var invalid_branch: Dictionary = invalid_branches[first_mandatory]
		var invalid_contract: Dictionary = invalid_branch.get("causal_contract", {})
		var old_midpoint: Array = invalid_contract.get("consumer_cell", [0, 0])
		var fake_midpoint := [int(old_midpoint[0]), int(old_midpoint[1]) + 100]
		invalid_contract["consumer_cell"] = fake_midpoint
		invalid_contract["consumer_cells"] = [fake_midpoint]
		invalid_branch["causal_contract"] = invalid_contract
		invalid_branches[first_mandatory] = invalid_branch
		invalid_navigation["branches"] = invalid_branches
		invalid_cut_spec["navigation_grid"] = invalid_navigation
		var invalid_solution := Solver.analyze_spec(invalid_cut_spec)
		check(
			not bool(invalid_solution.get("branch_contract_valid", true))
			and not bool(invalid_solution.get("shadow_solvable", true)),
			"solver solvability fails when a plural consumer set no longer cuts entry from exit"
		)
	var damaged := generated.duplicate(true)
	(damaged["headless"]["solution"] as Dictionary)["branch_actions"] = []
	check(
		not bool(Generator.validate_topology_contract(damaged).get("valid", true)),
		"topology validation rejects a solution that drops mandatory branch work"
	)


func verify_saved_hydraulic_topology_projection() -> void:
	var fixture := Generator.load_spec(HYDRAULIC_SPEC_PATH)
	check(not fixture.is_empty(), "saved Channels fixture loads for topology verification")
	if fixture.is_empty():
		return
	var spine: Dictionary = fixture.get("spine_navigation_grid", {})
	var navigation: Dictionary = fixture.get("navigation_grid", {})
	var branches: Array = navigation.get("branches", [])
	check(
		str(spine.get("contract_id", "")) == "unified_grid_v1"
		and (spine.get("branches", []) as Array).is_empty()
		and str(navigation.get("branch_weave_contract_id", ""))
			== Weaver.BRANCH_WEAVE_CONTRACT_ID
		and branches.size() == 3
		and (navigation.get("walkable_cells", []) as Array).size()
			> (spine.get("walkable_cells", []) as Array).size(),
		"saved Channels fixture separates its bare spine from the authoritative woven grid"
	)
	var saved_fake_returns := []
	for route_v in fixture.get("routes", []):
		if route_v is Dictionary and (
			str((route_v as Dictionary).get("kind", "")) == "shortcut"
			or str((route_v as Dictionary).get("topology_role", "")) == "recovery_return"
		):
			saved_fake_returns.append(route_v)
	check(
		saved_fake_returns.is_empty(),
		"saved Channels topology contains no prose-only return shortcut beside the real climbvine"
	)
	check(
		not (fixture.get("settings", {}).get("budget", {}) as Dictionary).has(
			"shortcut_count"
		),
		"saved Channels settings contain no obsolete semantic-shortcut budget"
	)
	var branch_validation := Weaver.validate_branch_contracts(branches, navigation)
	check(
		bool(branch_validation.get("valid", false))
		and int(branch_validation.get("proven_cut_count", 0)) == 2,
		"saved Channels mandatory branches carry two grid-proven consumer cut sets"
	)
	var topology_validation := Generator.validate_topology_contract(fixture)
	check(
		bool(topology_validation.get("valid", false)),
		"saved Channels fixture passes the complete topology contract: %s"
				% str(topology_validation.get("errors", []))
	)
	var expected_actions := Solver.mandatory_branch_actions(
		branches, fixture.get("nodes", []), navigation
	)
	var headless_actions: Array = fixture.get("headless", {}).get(
		"solution", {}
	).get("branch_actions", [])
	var action_projection_valid := expected_actions.size() == 2 \
		and _serialized_variants_equal(headless_actions, expected_actions)
	for action_v in headless_actions:
		if not (action_v is Dictionary):
			action_projection_valid = false
			continue
		var action := action_v as Dictionary
		action_projection_valid = (
			action_projection_valid
			and not (action.get("consumer_cells", []) as Array).is_empty()
			and (action.get("consumer_cell", []) as Array).size() == 2
			and str(action.get("before_node", "")) != ""
		)
		check_cut_disconnect_and_restore(
			navigation,
			action.get("consumer_cells", []),
			"saved %s cut" % str(action.get("id", "branch action"))
		)
	check(
		action_projection_valid,
		"saved Channels headless solution serializes exact cut sets and traversal anchors"
	)
	var mandatory_hydraulic_actions := []
	for action_v in fixture.get("headless", {}).get("solution", {}).get("world_actions", []):
		if action_v is Dictionary:
			mandatory_hydraulic_actions.append(str((action_v as Dictionary).get("action", "")))
	var optional_hydraulic_actions := []
	for action_v in fixture.get("systems_contract", {}).get("optional_world_actions", []):
		if action_v is Dictionary:
			optional_hydraulic_actions.append(str((action_v as Dictionary).get("action", "")))
	check(
		mandatory_hydraulic_actions == ["open_sluice", "release_bridge"]
		and optional_hydraulic_actions == ["divert", "restore", "catch"],
		"saved Channels migration preserves mandatory hydraulic progress and optional spillway play"
	)


func verify_gated_spiral_returns() -> void:
	var spine := _line_grid(96)
	var template = SpiralTemplate.new()
	var coord_map = template.build_coord_map(spine)
	var specs: Array = template.return_point_specs(spine, coord_map)
	check(not specs.is_empty(), "the long spiral exposes at least one stacked recovery anchor")
	for spec_v in specs:
		var spec := spec_v as Dictionary
		check(
			str(spec.get("kind", "")) == "climb"
			and str(spec.get("role", "")) == "recovery_return"
			and not bool(spec.get("starts_active", true)),
			"spiral emits one dormant climbvine, not a paired drop/stair"
		)
		check(
			int(spec.get("lower_spine_order", -1)) > int(spec.get("upper_spine_order", -1))
			and str(spec.get("traversal_direction", "")) == "lower_to_upper",
			"climbvine traversal moves from later/lower progress back to earlier/upper progress"
		)
	check(
		bool(template.validate_return_point_specs(specs).get("valid", false)),
		"spiral return specs pass the shared topology guard"
	)
	var scaled_spine := _line_grid(48)
	scaled_spine["cell_size"] = 2.0
	var scaled_coord_map = template.build_coord_map(scaled_spine)
	var scaled_specs: Array = template.return_point_specs(
		scaled_spine, scaled_coord_map
	)
	check(
		not scaled_specs.is_empty(),
		"spiral converts its world-space loop period into navigation cells"
	)
	if not scaled_specs.is_empty():
		var scaled_spec := scaled_specs[0] as Dictionary
		var scaled_upper: Vector3 = scaled_spec.get(
			"upper", Vector3.ZERO
		)
		var scaled_lower: Vector3 = scaled_spec.get(
			"lower", Vector3.ZERO
		)
		check(
			absf(
				(scaled_lower.x - scaled_upper.x)
					- scaled_coord_map.period_s()
			) <= float(scaled_spine.get("cell_size", 1.0)),
			"scaled-grid climbvine endpoints remain one physical loop apart"
		)
	var illegal := specs.duplicate(true)
	var forward_drop: Dictionary = illegal[0]
	forward_drop["kind"] = "drop"
	forward_drop["starts_active"] = true
	forward_drop["forward_traversal"] = true
	illegal[0] = forward_drop
	check(
		not bool(template.validate_return_point_specs(illegal).get("valid", true)),
		"shared guard rejects the old always-on forward drop partner"
	)

	# Setpiece spines distribute their authored footprint across navigation
	# levels. Level zero deliberately ends before one full spiral period here:
	# a level-zero-only probe would claim there is no recovery point even though
	# level one contains two real stacked cells.
	var layered := _line_grid(96)
	layered["level_count"] = 2
	layered["level_height"] = 0.72
	var level_zero_cells := []
	for x in range(20):
		level_zero_cells.append([x, 1])
	var level_one_cells := []
	for x in range(10, 96):
		level_one_cells.append([x, 1])
	layered["level_cells"] = [
		{"level": 0, "cells": level_zero_cells},
		{"level": 1, "cells": level_one_cells},
	]
	var layered_coord_map = template.build_coord_map(layered)
	var layered_specs: Array = template.return_point_specs(
		layered, layered_coord_map
	)
	check(
		not layered_specs.is_empty(),
		"multi-level spiral derives recovery from real nonzero-level spine cells"
	)
	if not layered_specs.is_empty():
		var layered_spec := layered_specs[0] as Dictionary
		var upper: Vector3 = layered_spec.get("upper", Vector3.ZERO)
		var lower: Vector3 = layered_spec.get("lower", Vector3.ZERO)
		var upper_level := int(
			layered_spec.get("upper_navigation_level", -1)
		)
		var lower_level := int(
			layered_spec.get("lower_navigation_level", -1)
		)
		var layered_grid = GridWorldScript.from_data(layered)
		var upper_cell := layered_grid.world_to_grid(upper)
		var lower_cell := layered_grid.world_to_grid(lower)
		check(
			upper_level == 1
			and lower_level == 1
			and layered_grid.is_walkable(
				upper_cell.x, upper_cell.y, {}, {}, upper_level
			)
			and layered_grid.is_walkable(
				lower_cell.x, lower_cell.y, {}, {}, lower_level
			),
			"multi-level climbvine anchors name actual authoritative cells and levels"
		)
		check(
			layered_coord_map.to_world(lower).y
				< layered_coord_map.to_world(upper).y,
			"multi-level climbvine later endpoint is physically below its upper anchor"
		)


func verify_semantic_topology_guard() -> void:
	var nodes := [
		{"id": "entry", "optional": false},
		{"id": "producer", "optional": false},
		{"id": "reward", "optional": true, "branch_role": "optional_risk_reward"},
		{"id": "gate", "optional": false},
		{"id": "exit_shelter", "optional": false},
	]
	var routes := [
		{"id": "main_0", "from": "entry", "to": "producer", "kind": "safe"},
		{"id": "main_1", "from": "producer", "to": "reward", "kind": "safe"},
		{"id": "main_2", "from": "reward", "to": "gate", "kind": "safe"},
		{"id": "main_3", "from": "gate", "to": "exit_shelter", "kind": "safe"},
		{
			"id": "optional_bypass",
			"from": "producer",
			"to": "gate",
			"kind": "safe",
			"topology_role": "optional_branch_bypass",
			"bypasses_optional": "reward",
			"cannot_bypass_unresolved": true,
		},
		{
			"id": "bound_climbvine_return",
			"from": "gate",
			"to": "entry",
			"kind": "shortcut",
			"topology_role": "recovery_return",
			"topology_effect": "backtrack_only",
			"starts_active": false,
			"unlock_requires_node": "gate",
			"cannot_bypass_unresolved": true,
			"runtime_handler": "climbvine_return_v1",
			"runtime_mechanism_id": "test_climbvine_00",
			"runtime_source_endpoint": "test_climbvine_00:lower",
			"runtime_target_endpoint": "test_climbvine_00:upper",
			"unlocks_shortcut": false,
		},
	]
	var valid_spec := {"nodes": nodes, "routes": routes}
	check(
		bool(Generator.validate_topology_contract(valid_spec).get("valid", false)),
		"optional reward bypass plus an exact climbvine-bound recovery validates"
	)
	var metadata_only := valid_spec.duplicate(true)
	var metadata_routes: Array = metadata_only.get("routes", [])
	var metadata_return: Dictionary = (metadata_routes.back() as Dictionary).duplicate(true)
	metadata_return.erase("runtime_mechanism_id")
	metadata_routes[metadata_routes.size() - 1] = metadata_return
	metadata_only["routes"] = metadata_routes
	check(
		not bool(Generator.validate_topology_contract(metadata_only).get("valid", true)),
		"topology validation rejects a prose-only recovery edge with no exact mechanism identity"
	)

	var illegal_spec := valid_spec.duplicate(true)
	(illegal_spec["routes"] as Array).append({
		"id": "forward_drop",
		"from": "entry",
		"to": "exit_shelter",
		"kind": "drop",
		"topology_role": "recovery_return",
		"topology_effect": "forward",
		"starts_active": true,
		"cannot_bypass_unresolved": false,
	})
	var illegal_validation := Generator.validate_topology_contract(illegal_spec)
	check(
		not bool(illegal_validation.get("valid", true))
		and _errors_contain(illegal_validation.get("errors", []), "producer")
		and _errors_contain(illegal_validation.get("errors", []), "forward drop"),
		"topology validation rejects a forward drop that skips an unresolved producer"
	)


func _line_grid(width: int) -> Dictionary:
	var cells := []
	for x in range(width):
		cells.append([x, 1])
	return {
		"contract_id": "unified_grid_v1",
		"space_id": "topology_test",
		"origin": [0.0, 0.45, 0.0],
		"cell_size": 1.0,
		"width": width,
		"height": 3,
		"walkable_cells": cells,
		"level_cells": [],
		"risk_cell_list": [],
		"route_cells": {},
		"links": [],
	}


func _errors_contain(errors: Array, needle: String) -> bool:
	for error_v in errors:
		if str(error_v).to_lower().contains(needle.to_lower()):
			return true
	return false


func _serialized_variants_equal(left: Variant, right: Variant) -> bool:
	return (
		JSON.parse_string(JSON.stringify(left))
		== JSON.parse_string(JSON.stringify(right))
	)


func check_cut_disconnect_and_restore(
		grid_data: Dictionary, cut_cells: Array, label: String
) -> void:
	var grid = GridWorldScript.from_data(grid_data)
	var endpoints := _progress_endpoints(grid_data.get("walkable_cells", []))
	if endpoints.size() < 2:
		check(false, "%s has progress endpoints" % label)
		return
	var start := endpoints[0] as Vector2i
	var finish := endpoints[1] as Vector2i
	var initially_connected := not grid.find_path(start, finish).is_empty()
	for cell_v in cut_cells:
		var cell := _to_cell(cell_v)
		grid.add_dynamic_blocker(cell, "topology_cut_test")
	var disconnected := grid.find_path(start, finish).is_empty()
	check(
		initially_connected and disconnected,
		"%s disconnects entry-side travel from exit-side travel" % label
	)
	for cell_v in cut_cells:
		grid.remove_dynamic_blocker(_to_cell(cell_v))
	check(
		not grid.find_path(start, finish).is_empty(),
		"%s restoration reconnects the same route" % label
	)


func _progress_endpoints(cells: Array) -> Array:
	var start := Vector2i(2147483647, 0)
	var finish := Vector2i(-2147483647, 0)
	for cell_v in cells:
		var cell := _to_cell(cell_v)
		if cell.x < start.x or (cell.x == start.x and cell.y < start.y):
			start = cell
		if cell.x > finish.x or (cell.x == finish.x and cell.y < finish.y):
			finish = cell
	return [start, finish] if start.x <= finish.x else []


func _to_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(2147483647, 0)


func _max_cell_x(cells: Array) -> int:
	var result := -2147483647
	for cell_v in cells:
		result = maxi(result, _to_cell(cell_v).x)
	return result


func _branch_by_id(branches: Array, branch_id: String) -> Dictionary:
	for branch_v in branches:
		if branch_v is Dictionary and str((branch_v as Dictionary).get("id", "")) == branch_id:
			return branch_v as Dictionary
	return {}


func _first_mandatory_branch_index(branches: Array) -> int:
	for index in range(branches.size()):
		if branches[index] is Dictionary \
				and str((branches[index] as Dictionary).get("role", "")) \
				== "mandatory_producer":
			return index
	return -1


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		push_error("  FAIL: %s" % label)
