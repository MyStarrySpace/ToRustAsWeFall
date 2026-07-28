extends SceneTree

const Generator := preload("res://scripts/generation/stretch_generator.gd")
const Solver := preload("res://scripts/generation/stretch_solution_solver.gd")
const Replay := preload("res://scripts/generation/stretch_replay_builder.gd")
const RuntimeRegistry := preload("res://scripts/generation/generated_node_runtime_registry.gd")

const HYDRAULIC_SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
const FINITE_CURRENT_MODEL_ID := "finite_current_routing_v1"

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
	check(str(contract.get("reasoning_solved_at", "")) == "exit_shelter", "implemented shelter arrival remains the final runtime outcome")
	check(int(contract.get("solved_state_execution_tail_nodes", 99)) <= 1, "solved-state execution tail is bounded")
	check(str(contract.get("feedback_contract", {}).get("visibility_policy", "")) == "party_visibility_union", "causal links use party-wide visibility")
	var replay: Dictionary = Replay.build(a)
	check(str(replay.get("schema", "")) == "trawf_stretch_replay_v1", "systems stretch still emits deterministic replay data")
	check((replay.get("solutions", []) as Array).size() == 2, "replay keeps spotlight and shadow solutions")
	check(JSON.stringify(replay) == JSON.stringify(Replay.build(b)), "same systems seed emits the same replay")

	var hydraulic_fixture := Generator.load_spec(HYDRAULIC_SPEC_PATH)
	check(not hydraulic_fixture.is_empty(), "authored hydraulic teaching fixture loads")
	if not hydraulic_fixture.is_empty():
		var fixture_validation := Generator.validate_systems_contract(hydraulic_fixture)
		check(
			bool(fixture_validation.get("valid", false)),
			"saved hydraulic teaching fixture validates: %s" % str(fixture_validation.get("errors", []))
		)
		check_hydraulic_solution_projection(hydraulic_fixture, "saved hydraulic fixture")
		var hydraulic := Generator.generate(hydraulic_fixture.get("settings", {}))
		check(bool(hydraulic.get("success", false)), "authored hydraulic teaching stretch regenerates")
		if bool(hydraulic.get("success", false)):
			check_hydraulic_solution_projection(hydraulic, "regenerated hydraulic stretch")
			var hydraulic_contract: Dictionary = hydraulic.get("systems_contract", {})
			check(
				str(hydraulic_contract.get("focus_model_id", "")) == FINITE_CURRENT_MODEL_ID,
				"hydraulic chain is one finite-current focus model"
			)
			var focus_roles := []
			for raw_beat in hydraulic_contract.get("lesson_spine", []):
				if raw_beat is Dictionary \
						and str((raw_beat as Dictionary).get("model_id", "")) == FINITE_CURRENT_MODEL_ID:
					focus_roles.append(str((raw_beat as Dictionary).get("beat", "")))
			check(
				focus_roles == ["teach", "test"],
				"hydraulic main route ends after its explicit teach and bridge test"
			)
			check(
				str(hydraulic_contract.get("reasoning_solved_at", "")) == "hydraulic:cistern_bridge",
				"seating the carried bridge solves the mandatory hydraulic reasoning"
			)
			var optional_focus_roles := []
			var all_optional_beats_noncritical := true
			for raw_beat in hydraulic_contract.get("optional_lesson_spine", []):
				if raw_beat is Dictionary \
						and str((raw_beat as Dictionary).get("model_id", "")) == FINITE_CURRENT_MODEL_ID:
					optional_focus_roles.append(str((raw_beat as Dictionary).get("beat", "")))
					all_optional_beats_noncritical = (
						all_optional_beats_noncritical
						and not bool((raw_beat as Dictionary).get("critical", true))
					)
			check(
				optional_focus_roles == ["transfer", "application", "application"]
				and all_optional_beats_noncritical,
				"spillway routing is a noncritical transfer, restore-in-flight, and catch branch"
			)
			var hydraulic_validation := Generator.validate_systems_contract(hydraulic)
			check(
				bool(hydraulic_validation.get("focus_has_transfer", false))
				and bool(hydraulic_validation.get("focus_transfer_follows_test", false)),
				"hydraulic transfer is sequenced after its teach and test"
			)
			var action_ids := []
			var action_boundaries := []
			for raw_action in hydraulic.get("headless", {}).get("solution", {}).get("world_actions", []):
				if raw_action is Dictionary:
					action_ids.append(str((raw_action as Dictionary).get("action", "")))
					action_boundaries.append(str((raw_action as Dictionary).get("before_node", "")))
			check(
				action_ids == ["open_sluice", "release_bridge"],
				"headless solution contains only mandatory main-route hydraulic actions"
			)
			check(
				action_boundaries == ["node_02", "node_03"],
				"mandatory hydraulic actions declare their traversal interleave boundaries"
			)
			var optional_action_ids := []
			var optional_actions: Array = hydraulic_contract.get("optional_world_actions", [])
			for raw_action in optional_actions:
				if raw_action is Dictionary:
					optional_action_ids.append(str((raw_action as Dictionary).get("action", "")))
			check(
				optional_action_ids == ["divert", "restore", "catch"],
				"spillway actions are explicit but excluded from the mandatory solution"
			)
			var capture: Dictionary = (
				optional_actions[0].get("captured_route_timing", {})
				if not optional_actions.is_empty()
				else {}
			)
			check(
				str(capture.get("route_captured_at", "")) == "launch"
				and is_equal_approx(float(capture.get("travel_delay_seconds", 0.0)), 2.6)
				and bool(capture.get("valve_changes_after_launch_do_not_redirect", false)),
				"optional payload captures the spillway route for its 2.6-second travel"
			)
			check(
				hydraulic_contract.get("optional_world_action_policy", {}).get(
					"preferred_transfer_order", []
				) == ["divert", "restore", "catch"],
				"optional transfer asks the player to restore main flow while the payload is moving"
			)
			var missing_test := hydraulic.duplicate(true)
			var broken_spine: Array = missing_test.get("systems_contract", {}).get("lesson_spine", [])
			for beat_index in range(broken_spine.size()):
				if broken_spine[beat_index] is Dictionary \
						and str((broken_spine[beat_index] as Dictionary).get("model_id", "")) == FINITE_CURRENT_MODEL_ID \
						and str((broken_spine[beat_index] as Dictionary).get("beat", "")) == "test":
					broken_spine.remove_at(beat_index)
					break
			check(
				not bool(Generator.validate_systems_contract(missing_test).get("valid", true)),
				"validation rejects transfer when its preceding test is missing"
			)

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
	check(platform_features.is_empty(),
		"unbound Flure/fauna/structure nouns do not advertise systemic platform contracts")
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
			"limitations": {"allowed": {"archetypes": ["2", "12", "16", "15", "11", "1", "3", "8", "4", "5", "6", "7", "14", "13", "10"]}},
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
		"limitations": {"required": {"archetypes": ["6"]}, "allowed": {"archetypes": ["6", "11"]}},
	})
	check(str(stage_six.get("systems_contract", {}).get("progression_profile", {}).get("perception_degradation", "")) == "one_source_hidden_from_each_character", "stage 6 uses composite partial reads")
	var stage_six_summary: Dictionary = stage_six.get("headless", {}).get("solution_summary", {})
	check(not stage_six_summary.has("diagnosis_node_count")
		and not stage_six_summary.has("diagnosis_penalty"),
		"stage 6 does not invent a generic diagnosis minigame")

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
			check(
				bool((link as Dictionary).get("feeds_next", false)),
				"every authored layout-chain output feeds the next conceptual input"
			)
			check(
				not bool((link as Dictionary).get("runtime_bound", true))
				and str((link as Dictionary).get("authority", "")) == "layout_concept_only",
				"an unbound conceptual chain is explicitly distinguished from gameplay authority"
			)
		check(
			int(chain.get("composition", {}).get("runtime_bound_link_count", -1)) == 0,
			"composition summary reports zero playable chain links without exact mechanism predicates"
		)
		var produced_refs := {}
		var consumed_refs := {}
		var unsupported_nested_emitted := false
		var unsupported_runtime_chain_claimed := false
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
				unsupported_nested_emitted = true
			if str(node.get("runtime_chain_input_ref", "")) != "" \
					or str(node.get("runtime_chain_output_ref", "")) != "":
				unsupported_runtime_chain_claimed = true
		check(
			not unsupported_nested_emitted
			and not bool(chain.get("composition", {}).get("has_nested", true)),
			"nested prose without a typed mechanism and physical output source is omitted"
		)
		var warned_missing_nested_binding := false
		for warning_v in chain.get("validation", {}).get("warnings", []):
			if warning_v is Dictionary \
					and str((warning_v as Dictionary).get("reason", "")) \
					== "missing_nested_runtime_binding":
				warned_missing_nested_binding = true
		check(
			warned_missing_nested_binding,
			"omitted nested composition reports the exact missing runtime-binding reason"
		)
		check(
			not unsupported_runtime_chain_claimed,
			"a generic pickup does not claim that an unrelated semantic chain changed"
		)
		var exact_bound_payload := {
			"resource": true,
			"carry_payload": true,
			"chain_output_ref": "chain_00:payload_held",
			"runtime_chain_binding": {
				"mechanism_id": "payload_source_00",
				"physical_source_id": "node:payload_source_00",
				"output_ref": "chain_00:payload_held",
				"output_predicate": "exact_source_item_is_held",
			},
		}
		check(
			RuntimeRegistry.materializes_chain_output(
				RuntimeRegistry.HANDLER_PHYSICAL_PAYLOAD, exact_bound_payload
			),
			"an exact physical source and completion predicate may bind a future chain output"
		)
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
	check(bool(underfit_profile.get("success", false))
		and not bool(underfit_profile.get("systems_contract", {}).get("runtime_profile_coverage", true)),
		"stage 4 keeps unsupported archetypes spatial without claiming runtime profile coverage")

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
		check(int(random_walk.get("settings", {}).get("reasoning_budget_added_nodes", 0)) == 0,
			"layout-only random-walk archetypes do not inflate the runtime reasoning budget")
		check(bool(Generator.validate_systems_contract(random_walk).get("valid", false)),
			"random-walk systems contract validates")
		var focus_id := str(random_walk.get("systems_contract", {}).get("focus_model_id", ""))
		var focus_tests := 0
		for model in random_walk.get("systems_contract", {}).get("causal_models", []):
			if str((model as Dictionary).get("id", "")) == focus_id:
				focus_tests = ((model as Dictionary).get("test_nodes", []) as Array).size()
		check(focus_tests == 0, "random-walk layout prose does not manufacture a repeated runtime mechanic")

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


func check_hydraulic_solution_projection(spec: Dictionary, label: String) -> void:
	var mandatory_action_nodes := []
	for raw_action in spec.get("headless", {}).get("solution", {}).get("actions", []):
		if raw_action is Dictionary:
			mandatory_action_nodes.append(str((raw_action as Dictionary).get("node", "")))
	check(
		not mandatory_action_nodes.has("node_04"),
		"%s does not claim the skipped spillway catch as a mandatory action" % label
	)
	var optional_traversal_count := 0
	var optional_projection_valid := true
	for raw_path in spec.get("headless", {}).get("solution_paths", []):
		if not (raw_path is Dictionary):
			continue
		for raw_approach in (raw_path as Dictionary).get("approach_per_node", []):
			if not (raw_approach is Dictionary):
				continue
			var approach := raw_approach as Dictionary
			if str(approach.get("node", "")) != "node_04":
				continue
			optional_traversal_count += 1
			optional_projection_valid = (
				optional_projection_valid
				and str(approach.get("approach_id", "")) == "skip_optional_interaction"
				and str(approach.get("kind", "")) == "optional_layout_traversal"
				and str(approach.get("runtime_handler", "")) == ""
				and str(approach.get("optional_runtime_handler", ""))
					== "authored_hydraulic_spillway_food_v1"
				and bool(approach.get("optional_interaction", false))
			)
	check(
		optional_traversal_count == 2 and optional_projection_valid,
		"%s marks the catch as an optional pass-through for both loadouts" % label
	)


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		failures += 1
		push_error("  FAIL  %s" % label)
