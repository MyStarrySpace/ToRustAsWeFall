extends SceneTree

const Generator := preload("res://scripts/generation/stretch_generator.gd")
const Solver := preload("res://scripts/generation/stretch_solution_solver.gd")
const Replay := preload("res://scripts/generation/stretch_replay_builder.gd")

var checks := 0
var failures := 0


func _init() -> void:
	var base := {
		"id": "systems_contract_standard",
		"seed": 7319,
		"complexity_tier": "standard",
		"progression_stage": 3,
		"limitations": {"allowed": {"archetypes": ["1", "2", "3", "4", "6", "11", "12"]}},
	}
	var a: Dictionary = Generator.generate(base)
	var b: Dictionary = Generator.generate(base)
	check(bool(a.get("success", false)), "standard systems stretch generates")
	check(JSON.stringify(a) == JSON.stringify(b), "systems contract is seed-deterministic")
	var validation: Dictionary = Generator.validate_systems_contract(a)
	check(bool(validation.get("valid", false)), "standard systems contract validates: %s" % str(validation.get("errors", [])))
	var contract: Dictionary = a.get("systems_contract", {})
	check(str(contract.get("focus_model_id", "")) != "", "contract names a focus causal model")
	check(not (contract.get("causal_links", []) as Array).is_empty(), "contract emits teach-to-test or typed state links")
	check(str(contract.get("reasoning_solved_at", "")) != "exit_shelter", "reasoning ends before shelter traversal")
	check(int(contract.get("solved_state_execution_tail_nodes", 99)) <= 1, "solved-state execution tail is bounded")
	check(str(contract.get("feedback_contract", {}).get("visibility_policy", "")) == "party_visibility_union", "causal links use party-wide visibility")
	var replay: Dictionary = Replay.build(a)
	check(str(replay.get("schema", "")) == "trawf_stretch_replay_v1", "systems stretch still emits deterministic replay data")
	check((replay.get("solutions", []) as Array).size() == 2, "replay keeps spotlight and shadow solutions")
	check(JSON.stringify(replay) == JSON.stringify(Replay.build(b)), "same systems seed emits the same replay")

	# Spatial composition is selected through the archetype's affordance contract. Plant-as-tool's
	# Flure variant must provide a response actor, separate it from the flora leverage socket, and
	# preserve those authored cells as ordinary walkable GridWorld truth.
	var platform_settings := {
		"id": "systems_grated_signal_roost",
		"seed": 4417,
		"complexity_tier": "standard",
		"progression_stage": 1,
		"limitations": {
			"allowed": {"archetypes": ["2", "11"]},
			"required": {"archetypes": ["2"]},
		},
		"composition": {"chain": [{"id": "2", "variant": "flure_iron_decoy"}]},
	}
	var platform_spec: Dictionary = Generator.generate(platform_settings)
	var platform_spec_again: Dictionary = Generator.generate(platform_settings)
	check(bool(platform_spec.get("success", false)), "eligible Plant-as-tool stretch generates")
	check(JSON.stringify(platform_spec) == JSON.stringify(platform_spec_again),
		"spatial feature selection and sockets are seed-deterministic")
	var platform_features: Array = platform_spec.get("spatial_features", [])
	check(platform_features.size() == 1, "standard tier emits one grated spatial composition")
	if not platform_features.is_empty():
		var platform := platform_features[0] as Dictionary
		check(str(platform.get("kind", "")) == "grated_platform",
			"archetype affordance selects the grated room-piece")
		check((platform.get("floor_cells", []) as Array).size() == 25,
			"the five-by-five grate replaces exactly 25 walkable cells")
		var categories := {}
		for assignment_v in platform.get("socket_assignments", []):
			if assignment_v is Dictionary:
				categories[str((assignment_v as Dictionary).get("category", ""))] = true
		check(categories.has("flora") and categories.has("enemies") and categories.has("structures"),
			"platform sockets separate leverage flora, response fauna, and puzzle structure")
		check((platform.get("causal_model", {}).get("emergent_inputs", []) as Array).size() >= 3,
			"platform contract names the interacting systems that can produce emergence")
	check(bool(Generator.validate_spatial_features(platform_spec).get("valid", false)),
		"platform feature contract validates against authoritative navigation")

	var tier_nodes := -1
	var tier_depth := -1
	var previous_rank := 0
	for stage in [1, 2, 3, 4, 5, 6]:
		var spec: Dictionary = Generator.generate({
			"id": "systems_stage_%d" % stage,
			"seed": 73,
			"complexity_tier": "teaching",
			"progression_stage": stage,
			"limitations": {"allowed": {"archetypes": ["2", "12", "16", "15", "11", "1", "3", "8", "4", "5", "6", "7", "14", "13", "10", "17"]}},
		})
		check(bool(spec.get("success", false)), "stage %d generates" % stage)
		if not bool(spec.get("success", false)):
			continue
		var budget: Dictionary = spec.get("budget", {})
		if tier_nodes < 0:
			tier_nodes = int(budget.get("node_count", -1))
			tier_depth = int(budget.get("archetype_depth", -1))
		check(int(budget.get("node_count", -2)) == tier_nodes, "stage %d does not inflate node count" % stage)
		check(int(budget.get("archetype_depth", -2)) == tier_depth, "stage %d does not inflate archetype depth" % stage)
		var profile: Dictionary = spec.get("systems_contract", {}).get("progression_profile", {})
		var rank := int(profile.get("complexity_rank", 0))
		check(rank > previous_rank, "stage %d increases reasoning rank" % stage)
		previous_rank = rank
		check(bool(Generator.validate_systems_contract(spec).get("valid", false)), "stage %d systems contract validates" % stage)

	var stage_six: Dictionary = Generator.generate({
		"id": "systems_stage_six",
		"seed": 17,
		"complexity_tier": "teaching",
		"progression_stage": 6,
		"limitations": {"required": {"archetypes": ["17"]}, "allowed": {"archetypes": ["11", "17"]}},
	})
	check(str(stage_six.get("systems_contract", {}).get("progression_profile", {}).get("perception_degradation", "")) == "one_source_hidden_from_each_character", "stage 6 uses composite partial reads")

	var chain: Dictionary = Generator.generate({
		"id": "systems_typed_chain",
		"seed": 31,
		"complexity_tier": "hard",
		"progression_stage": 4,
		"composition": {"mode": "chain_nested_poc", "chain": [
			{"id": "1", "output": "lane_open"},
			{"id": "3", "input": "lane_open", "output": "component_delivered"},
			{"id": "6", "input": "component_delivered", "output": "route_known"},
		], "nested": [{"id": "2", "host_id": "3", "host_step": 2}]},
	})
	check(bool(chain.get("success", false)), "matching typed causal chain generates")
	if bool(chain.get("success", false)):
		for link in chain.get("composition", {}).get("links", []):
			check(bool((link as Dictionary).get("feeds_next", false)), "every authored chain output feeds the next input")
		var produced_refs := {}
		var consumed_refs := {}
		var physical_nested_carry := false
		for node_v in chain.get("nodes", []):
			var node := node_v as Dictionary
			var input_ref := str(node.get("chain_input_ref", ""))
			var output_ref := str(node.get("chain_output_ref", ""))
			if bool(node.get("optional", false)):
				check(input_ref == "" and output_ref == "", "optional reward does not consume a mandatory chain link")
				check(str(node.get("reward_kind", "")) == "food" and int(node.get("reward_atp", 0)) > 0,
					"optional detour carries a durable food reward")
				continue
			if input_ref != "":
				check(produced_refs.has(input_ref), "typed input %s has an earlier producer" % input_ref)
				consumed_refs[input_ref] = true
			if output_ref != "":
				produced_refs[output_ref] = true
			if not (node.get("nested_archetypes", []) as Array).is_empty():
				physical_nested_carry = bool(node.get("resource", false)) and bool(node.get("carry_payload", false))
		check(physical_nested_carry, "nested plant preparation is hosted by a physical carried payload")
		for output_ref in produced_refs.keys():
			check(consumed_refs.has(output_ref), "typed output %s is consumed by a later node or shelter" % output_ref)
		for route_v in chain.get("routes", []):
			var route := route_v as Dictionary
			if str(route.get("kind", "")) != "risky":
				continue
			var reward_node := {}
			for node_v in chain.get("nodes", []):
				if str((node_v as Dictionary).get("id", "")) == str(route.get("to", "")):
					reward_node = node_v as Dictionary
					break
			check(int(reward_node.get("reward_atp", 0)) >= int(ceil(float(route.get("damage", 0.0)) / 10.0)),
				"risky detour reward scales with its HP exposure")

	var mismatch: Dictionary = Generator.generate({
		"id": "systems_bad_chain",
		"seed": 31,
		"complexity_tier": "standard",
		"composition": {"mode": "chain_nested_poc", "chain": [
			{"id": "1", "output": "lane_open"},
			{"id": "2", "input": "unrelated_state", "output": "plant_ready"},
		]},
	})
	check(not bool(mismatch.get("success", true)), "mismatched causal handshake is rejected")
	var blocked: Dictionary = Generator.generate({
		"id": "systems_blocked_subversion",
		"seed": 31,
		"complexity_tier": "setpiece",
		"progression_stage": 6,
		"limitations": {"required": {"archetypes": ["9"]}},
	})
	check(not bool(blocked.get("success", true)), "untyped expectation subversion is rejected")
	var underfit_profile: Dictionary = Generator.generate({
		"id": "systems_underfit_feedback_profile",
		"seed": 31,
		"complexity_tier": "hard",
		"progression_stage": 4,
		"limitations": {"required": {"archetypes": ["1"]}, "allowed": {"archetypes": ["1"]}},
	})
	check(not bool(underfit_profile.get("success", true)),
		"stage 4 rejects a focus mechanic with no feedback or party-scale model")

	var random_walk: Dictionary = Generator.generate({
		"id": "systems_random_walk",
		"seed": 5519,
		"complexity_tier": "standard",
		"progression_stage": 3,
		"limitations": {
			"allowed": {"archetypes": ["1", "2", "3", "4", "6", "11"]},
			"required": {"archetypes": ["1", "2", "4"]},
		},
		"composition": {"mode": "archetype_random_walk", "random_walk": {
			"start_archetype": "4", "step_count": 6, "transition_chance": 0.4,
			"prefer_tags": ["patrol", "flora", "timing"],
		}},
	})
	check(bool(random_walk.get("success", false)), "random-walk composition generates with a later focus test")
	if bool(random_walk.get("success", false)):
		check(int(random_walk.get("settings", {}).get("reasoning_budget_added_nodes", 0)) >= 1,
			"random walk reserves a reasoning node instead of ending after first exposure")
		check(bool(Generator.validate_systems_contract(random_walk).get("valid", false)),
			"random-walk systems contract validates")
		var focus_id := str(random_walk.get("systems_contract", {}).get("focus_model_id", ""))
		var focus_tests := 0
		for model in random_walk.get("systems_contract", {}).get("causal_models", []):
			if str((model as Dictionary).get("id", "")) == focus_id:
				focus_tests = ((model as Dictionary).get("test_nodes", []) as Array).size()
		check(focus_tests >= 1, "random-walk focus model returns under a changed condition")

	var curated := [
		{"id": "systems_curated_teaching", "seed": 2207, "complexity_tier": "teaching", "progression_stage": 2,
			"limitations": {"required": {"archetypes": ["2", "3"]}, "allowed": {"archetypes": ["1", "2", "3", "4", "5", "6", "7", "8", "10", "11"]}}},
		{"id": "systems_curated_survival", "seed": 6160, "complexity_tier": "hard", "progression_stage": 4,
			"limitations": {"required": {"archetypes": ["12", "13", "14", "15"]}, "allowed": {"archetypes": ["11", "12", "13", "14", "15", "16"]}}},
		{"id": "systems_curated_setpiece", "seed": 9043, "complexity_tier": "setpiece", "progression_stage": 5,
			"limitations": {"required": {"archetypes": ["10", "1", "3", "4", "6"]}, "allowed": {"archetypes": ["1", "2", "3", "4", "5", "6", "7", "8", "10", "11"]}},
			"composition": {"mode": "archetype_random_walk", "random_walk": {
				"start_archetype": "10", "step_count": 9, "transition_chance": 0.5,
				"prefer_tags": ["danger_zone", "carry", "patrol", "fragments"],
			}}},
	]
	for settings in curated:
		var spec: Dictionary = Generator.generate(settings)
		var label := str(settings.get("id", "curated"))
		check(bool(spec.get("success", false)), "%s generates" % label)
		if not bool(spec.get("success", false)):
			continue
		check(bool(Generator.validate_systems_contract(spec).get("valid", false)), "%s systems contract validates" % label)
		var analysis: Dictionary = Solver.analyze_spec(spec)
		check(bool(analysis.get("shadow_solvable", false)), "%s remains Aster+Peris solvable" % label)
		check(bool(analysis.get("bare_pair_solvable", false)), "%s remains bare-pair solvable" % label)

	var focus_summary := ""
	for model in contract.get("causal_models", []):
		if str((model as Dictionary).get("id", "")) == str(contract.get("focus_model_id", "")):
			focus_summary = str((model as Dictionary).get("relationship", ""))
			break
	var spine_summary := []
	for beat in contract.get("lesson_spine", []):
		spine_summary.append("%s:%s/%s" % [
			str((beat as Dictionary).get("node", "")),
			str((beat as Dictionary).get("beat", "")),
			str((beat as Dictionary).get("verb", "")),
		])
	print("SAMPLE SYSTEMS CONTRACT: profile=%s | focus=%s | spine=%s" % [
		str(contract.get("progression_profile", {}).get("name", "")),
		focus_summary,
		" -> ".join(spine_summary),
	])
	print("STRETCH SYSTEMS GENERATION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		failures += 1
		push_error("  FAIL  %s" % label)
