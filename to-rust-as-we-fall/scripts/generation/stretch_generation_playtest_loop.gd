class_name StretchGenerationPlaytestLoop
extends RefCounted

const RuntimeRegistryScript := preload("res://scripts/generation/generated_node_runtime_registry.gd")
const AgentPlayerInputDriverScript := preload("res://tools/agent_player_input_driver.gd")
const PlayerObservationControllerScript := preload(
	"res://scripts/testing/player_observation_controller.gd"
)
const PersonaDecisionTraceScript := preload(
	"res://scripts/testing/persona_decision_trace.gd"
)

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const GameSettingsScript := preload("res://scripts/system/settings.gd")
const GENERATED_STRETCH_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const ANIMATION_CONTRACT_ID := "playthrough_animation_v1"
const DEFAULT_CAPTURE_STEP := 0.25
const DIAGNOSTIC_GENERATED_INPUT_COMMAND_PREFIX := "qa_generated_node_command/"
const DIAGNOSTIC_WORLD_INPUT_COMMAND_PREFIX := "qa_world_interaction/"
const PHYSICAL_INTERACTION_TIMEOUT := 24.0
const MAX_PLAYTEST_ADVANCE_SECONDS := 120.0
const PLAYER_DISCOVERY_MAX_DECISIONS := 24
const PLAYER_DISCOVERY_NEAR_INTERACTION_PX := 168.0
const PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES := 8
const PLAYER_DISCOVERY_OBSERVATION_SCHEMA := "player_observation_v1"
const GENERATED_STRATEGY_TRACE_SCHEMA := "generated_strategy_decision_trace_v1"
const PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX := 16.0
const PLAYER_DISCOVERY_MAX_VISIBLE_RETRIES := 4
const PLAYER_DISCOVERY_MAX_HOVER_REBIND_CHURN := 3
const PLAYER_DISCOVERY_MOTION_STABLE_SAMPLES := 7
const PLAYER_DISCOVERY_MIN_SETTLE_SECONDS := 1.0
const PLAYER_DISCOVERY_PATH_BASE_SECONDS := 60.0
const PLAYER_DISCOVERY_PATH_SECONDS_PER_NODE := 15.0
const PLAYER_DISCOVERY_PATH_MIN_SECONDS := 120.0
const PLAYER_DISCOVERY_PATH_MAX_SECONDS := 240.0
const PLAYER_DISCOVERY_GLOBAL_GRACE_SECONDS := 30.0
const PLAYER_DISCOVERY_HEARTBEAT_SECONDS := 5.0
const PLAYER_DISCOVERY_VISIBLE_PROGRESS_TIMEOUT_SECONDS := 4.0
const PLAYER_DISCOVERY_RALLY_START_TIMEOUT_SECONDS := 3.0
const PLAYER_DISCOVERY_RALLY_INCOMPLETE_STABLE_SECONDS := 1.5
const PARTY_IDS := ["aster", "peris", "endo"]
const PARTY_OFFSETS := {
	"aster": Vector3(0.0, 0.0, 0.0),
	"peris": Vector3(-1.4, 0.0, 1.1),
	"endo": Vector3(-1.4, 0.0, -1.1),
}
# Walk speeds read the cast registry, so the playtest loop times routes with the same
# speeds every real run uses.
static var CHARACTER_SPEEDS: Dictionary = StretchCapabilities.attribute_table(PARTY_IDS, "move_speed")

func generate_and_playtest(settings: Dictionary, tree: SceneTree, options := {}) -> Dictionary:
	var result := _base_result()
	var spec := StretchGeneratorScript.generate(settings)
	result["spec"] = spec.duplicate(true)
	result["spec_id"] = str(spec.get("id", ""))
	_record_check(result, "generator_success", bool(spec.get("success", false)), "Generator returned a playable spec")
	if not bool(spec.get("success", false)):
		result["success"] = false
		result["ok"] = false
		return result
	var playtest_result: Dictionary = await playtest_spec(spec, tree, options)
	playtest_result["spec"] = spec.duplicate(true)
	_record_check(playtest_result, "generator_success", true, "Generator returned a playable spec")
	return playtest_result

func playtest_spec(spec: Dictionary, tree: SceneTree, options := {}) -> Dictionary:
	var result := _base_result()
	result["spec_id"] = str(spec.get("id", ""))
	result["world_slot"] = spec.get("world_slot", {}).duplicate(true)
	result["composition"] = spec.get("composition", {}).duplicate(true)
	result["preview_scene"] = GENERATED_STRETCH_PREVIEW_SCENE_PATH
	result["spec"] = spec.duplicate(true)
	if bool(options.get("capture_animation", false)):
		result["animation"] = _base_animation_report(spec, options)
	_append_event(result, "generation", "spec_ready", "Generated stretch spec is ready", {
		"spec_id": str(spec.get("id", "")),
		"title": str(spec.get("title", "")),
		"seed": int(spec.get("source", {}).get("seed", 0)),
		"complexity_tier": str(spec.get("source", {}).get("complexity_tier", "")),
		"node_count": (spec.get("nodes", []) as Array).size(),
		"route_count": (spec.get("routes", []) as Array).size(),
		"world_slot": spec.get("world_slot", {}).duplicate(true),
		"composition": spec.get("composition", {}).duplicate(true),
	})

	var preview_scene: PackedScene = load(GENERATED_STRETCH_PREVIEW_SCENE_PATH)
	_record_check(result, "preview_scene_loads", preview_scene != null, "Generated preview scene loads")
	if preview_scene == null:
		return _finish_result(result)

	var preview_instance: Node = preview_scene.instantiate()
	_record_check(result, "preview_scene_instantiates", preview_instance != null, "Generated preview scene instantiates")
	if preview_instance == null:
		return _finish_result(result)

	preview_instance.set("preview_menu", false)  # drive the chunk directly, not the picker
	preview_instance.set("preview_chunk", "generated_stretch")
	preview_instance.set("scene_title_override", str(spec.get("title", "Generated Stretch")))
	# Generated-content approval uses Scarcity as its default stress-test projection.
	# A focused test may still request another economy explicitly, but an omitted
	# configuration must never inherit a local/persisted mode or silently choose an
	# easier control. In all cases this is applied after generation to the same spec.
	var preview_config: Dictionary = (
		GameSettingsScript.GAME_MODE_CHUNK_CONFIGS[GameSettingsScript.GAME_MODE_SCARCITY] as Dictionary
	).duplicate(true)
	var requested_preview_config: Variant = options.get("preview_config", {})
	if requested_preview_config is Dictionary and not (requested_preview_config as Dictionary).is_empty():
		preview_config = (requested_preview_config as Dictionary).duplicate(true)
	result["play_config"] = preview_config.duplicate(true)
	preview_config["spec"] = spec
	preview_instance.set("preview_chunk_config", preview_config)
	tree.root.add_child(preview_instance)
	for _i in range(int(options.get("settle_frames", 4))):
		await tree.process_frame

	_record_check(result, "preview_headless_state", preview_instance.has_method("headless_get_state"), "Preview exposes headless state")
	if not preview_instance.has_method("headless_get_state"):
		await _dispose_preview(preview_instance, tree)
		return _finish_result(result)

	var initial_state: Dictionary = preview_instance.call("headless_get_state")
	result["initial_state"] = _summarize_preview_state(initial_state)
	_validate_preview_boot(result, initial_state)
	_validate_random_walk_variety(result, spec)
	if preview_config.has("food_test"):
		_record_check(
			result,
			"preview_uses_requested_food_mode",
			str(initial_state.get("chunk", {}).get("food_test", "")) == str(preview_config.get("food_test", "")),
			"Generated preview did not apply the requested food-test mode"
		)
	if preview_config.has("game_mode"):
		_record_check(
			result,
			"preview_uses_requested_game_mode",
			str(initial_state.get("chunk", {}).get("game_mode", "")) == str(preview_config.get("game_mode", "")),
			"Generated preview did not apply the requested game-mode label"
		)
	_record_animation_snapshot(result, preview_instance, "preview_boot", "Preview ready", {
		"event_type": "preview_ready",
	})
	_diagnostic_exercise_abilities(result, preview_instance)

	# Diagnostic/setup quarantine: ability routing above is not player evidence,
	# and this reset occurs before the progression diagnostic and measured input
	# baseline. No receipt or movement sample survives it.
	_diagnostic_reset_preview_state(preview_instance)
	_diagnostic_validate_progression_gate(result, preview_instance, spec)
	if preview_instance.has_method("headless_advance"):
		_advance_preview_with_animation(result, preview_instance, 0.5, "preview_boot", "Playthrough settle", {
			"event_type": "playthrough_settle",
		})
	_begin_player_animation_evidence_baseline(result)
	var player_evidence_options: Dictionary = options.duplicate(true)
	var generated_node_count := (spec.get("nodes", []) as Array).size()
	var default_path_budget := clampf(
		PLAYER_DISCOVERY_PATH_BASE_SECONDS
			+ PLAYER_DISCOVERY_PATH_SECONDS_PER_NODE * generated_node_count,
		PLAYER_DISCOVERY_PATH_MIN_SECONDS,
		PLAYER_DISCOVERY_PATH_MAX_SECONDS
	)
	var requested_path_budget := float(player_evidence_options.get(
		"player_discovery_path_wall_seconds", default_path_budget))
	var path_budget := clampf(
		requested_path_budget, 1.0, PLAYER_DISCOVERY_PATH_MAX_SECONDS)
	var default_global_budget := path_budget * 3.0 \
		+ PLAYER_DISCOVERY_GLOBAL_GRACE_SECONDS
	var requested_global_budget := float(player_evidence_options.get(
		"player_discovery_global_wall_seconds", default_global_budget))
	var global_budget := clampf(
		requested_global_budget, 1.0,
		PLAYER_DISCOVERY_PATH_MAX_SECONDS * 3.0 \
			+ PLAYER_DISCOVERY_GLOBAL_GRACE_SECONDS)
	var global_started_usec := Time.get_ticks_usec() # @artifact_metadata_only
	player_evidence_options["player_discovery_path_wall_seconds"] = path_budget
	player_evidence_options["player_discovery_global_wall_seconds"] = global_budget
	player_evidence_options["player_discovery_global_started_usec"] = \
		global_started_usec
	player_evidence_options["player_discovery_global_deadline_usec"] = \
		global_started_usec + int(global_budget * 1000000.0)
	player_evidence_options["player_discovery_max_decisions"] = mini(
		PLAYER_DISCOVERY_MAX_DECISIONS,
		maxi(1, int(player_evidence_options.get(
			"player_discovery_max_decisions", PLAYER_DISCOVERY_MAX_DECISIONS)))
	)

	var golden_report: Dictionary = await _play_golden_path(
		preview_instance, spec, result, player_evidence_options
	)
	var golden_policy_evidence := _validate_player_surface_policy_evidence(
		golden_report)
	golden_report.merge(golden_policy_evidence, true)
	var policy_evidence_valid := bool(golden_policy_evidence.get("valid", false))
	result["playthroughs"]["golden_path"] = golden_report
	_merge_playthrough_events(result, golden_report)
	_record_check(
		result,
		"golden_path_moves_party",
		int(golden_report.get("movement_commands", 0)) > 0,
		"Visible discovery issues party travel through shipped input"
	)
	_record_check(
		result,
		"golden_path_uses_routes",
		int(golden_report.get("rally_gestures", 0)) > 0
			and (golden_report.get("atomic_rally_failures", []) as Array).is_empty()
			and int(golden_report.get("movement_commands", 0))
				== int(golden_report.get("route_choices", 0)),
		"Every whole-party travel intent is one held-RMB Rally with one rally_members receipt"
	)
	_record_check(
		result,
		"golden_path_decisions_are_player_observable",
		str(golden_report.get("decision_source", "")) in [
			"live_player_observable_surface", "none_headless"
		]
			and not bool(golden_report.get("solver_trace_used_for_actions", true))
			and (policy_evidence_valid or DisplayServer.get_name() == "headless"),
		"Generated solver/golden-path data must not drive playthrough decisions"
	)
	var golden_path_declares_multiple_levels := \
		_golden_path_declares_multiple_navigation_levels(spec)
	var golden_path_uses_multiple_levels := bool(
		golden_report.get("used_multi_y_path", false)
	)
	_record_check(
		result,
		"golden_path_navigation_matches_declared_levels",
		golden_path_uses_multiple_levels == golden_path_declares_multiple_levels,
		(
			"Golden path movement does not match its declared graph levels "
			+ "(declares_multiple=%s, observed_multiple=%s)"
			% [
				str(golden_path_declares_multiple_levels),
				str(golden_path_uses_multiple_levels),
			]
		)
	)
	_record_check(
		result,
		"golden_path_uses_ordinary_interactions",
		int(golden_report.get("physical_interactions", 0)) > 0,
		"Visible discovery never entered the ordinary input interaction coordinator"
	)
	_record_check(
		result,
		"golden_path_physical_actions_complete",
		(golden_report.get("interaction_failures", []) as Array).is_empty()
			and (golden_report.get("solution_action_failures", []) as Array).is_empty(),
		"Visible discovery encountered a silent or incomplete physical action"
	)
	_record_check(result, "golden_path_reaches_shelter", bool(golden_report.get("shelter_rested", false)), "Visible player-surface discovery reaches and rests at the exit shelter")
	if str(spec.get("composition", {}).get("mode", "")) == "chain_nested_poc":
		var expected_chain_outputs := 0
		var expected_carries := 0
		var golden_node_ids: Array = spec.get("headless", {}).get("golden_path", [])
		for node_v in spec.get("nodes", []):
			var node := node_v as Dictionary
			var node_id := str(node.get("id", ""))
			if not golden_node_ids.has(node_id):
				continue
			var handler_id := RuntimeRegistryScript.declared_handler(node)
			if str(node.get("runtime_chain_output_ref", "")) != "":
				expected_chain_outputs += 1
			if handler_id == RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
				expected_carries += 1
		_record_check(result, "chain_outputs_materialize", (golden_report.get("produced_chain_states", {}) as Dictionary).size() == expected_chain_outputs,
			"Golden path did not materialize every runtime-supported typed chain output")
		_record_check(result, "carry_payloads_delivered", (golden_report.get("delivered_resource_nodes", []) as Array).size() == expected_carries,
			"A physical carried payload did not reach shelter delivery state")
	var risky_report: Dictionary = await _play_risky_recovery(
		preview_instance, spec, result, player_evidence_options
	)
	result["playthroughs"]["risky_recovery"] = risky_report
	_merge_playthrough_events(result, risky_report)
	_record_check(result, "risky_recovery_playable", bool(risky_report.get("recovered", false)), "Risky route recovery remains playable")
	var diagnostic_risky_route_exists := not _find_first_route(spec, ["risky"]).is_empty()
	if str(risky_report.get("evidence_kind", "")) \
			== "visible_player_surface_discovery":
		_record_check(
			result,
			"risky_route_affordance_visible",
			not diagnostic_risky_route_exists
				or bool(risky_report.get("risk_surface_attempted", false)),
			"A generated risky route exists structurally but exposes no readable player-facing risk cue"
		)
	_record_check(
		result,
		"risky_recovery_physical_actions_complete",
		(risky_report.get("interaction_failures", []) as Array).is_empty()
			and (risky_report.get("solution_action_failures", []) as Array).is_empty(),
		"Risky approval encountered an unreachable, rejected, or incomplete physical action"
	)
	if bool(risky_report.get("has_risky_route", false)):
		_record_check(result, "risky_recovery_applies_pressure", float(risky_report.get("damage", 0.0)) > 0.0, "Risky recovery applies pressure before rest")
		var risky_reward: Dictionary = risky_report.get("reward", {})
		_record_check(
			result,
			"risky_route_grants_physical_reward",
			str(risky_reward.get("item_type", "")) == "lysate"
				and bool(risky_reward.get("spawned", false))
				and bool(risky_reward.get("picked_up", false))
				and (
					bool(risky_reward.get("retained_in_hand", false))
					or bool(risky_reward.get("endocytosis_completed", false))
				),
			"Risky optional route did not yield its advertised physical lysate"
		)
		if str(spec.get("composition", {}).get("mode", "")) == "chain_nested_poc":
			_record_check(result, "risky_route_grants_durable_food", str(risky_reward.get("item_type", "")) == "lysate" and bool(risky_reward.get("retained_in_hand", false)),
				"Risky route pressure did not grant a durable carried food reward")

	var shadow_report: Dictionary = await _play_shadow_path(
		preview_instance, spec, result, player_evidence_options
	)
	result["playthroughs"]["shadow_path"] = shadow_report
	_merge_playthrough_events(result, shadow_report)
	var choice_node_count := int(spec.get("headless", {}).get("solution_summary", {}).get("choice_node_count", 0))
	if choice_node_count > 0:
		_record_check(result, "shadow_path_completes", bool(shadow_report.get("shelter_rested", false)), "Aster+Peris shadow path reaches and rests at the exit shelter")
		_record_check(
			result,
			"shadow_path_physical_actions_complete",
			(shadow_report.get("interaction_failures", []) as Array).is_empty()
				and (shadow_report.get("solution_action_failures", []) as Array).is_empty(),
			"Shadow approval encountered an unreachable, rejected, or incomplete physical action"
		)
		_record_check(result, "shadow_path_no_specialist", bool(shadow_report.get("uses_only_pair", false)), "Shadow path never relies on a specialist approach")
		_record_check(result, "shadow_path_distinct", _solution_paths_differ(golden_report.get("solution_path", []), shadow_report.get("solution_path", [])), "Shadow path solves at least one node a different way than the golden path")
		_record_check(result, "shadow_party_visibly_excludes_endo", shadow_report.get("active_party", []) == ["aster", "peris"],
			"Shadow replay did not expose Aster+Peris as its active roster")

	var final_state: Dictionary = preview_instance.call("headless_get_state")
	result["final_state"] = _summarize_preview_state(final_state)
	_record_animation_snapshot(result, preview_instance, "final", "Final preview state", {
		"event_type": "final_state",
	})
	_finish_animation_report(result)
	await _dispose_preview(preview_instance, tree)
	return _finish_result(result)


## Pre-evidence mechanism diagnostic. Any resulting mutation is discarded by
## reset before the player-input evidence baseline.
func _diagnostic_validate_progression_gate(result: Dictionary, preview_instance: Node, spec: Dictionary) -> void:
	var golden_path: Array = spec.get("headless", {}).get("golden_path", [])
	if golden_path.size() < 3 or not preview_instance.has_method("headless_call_chunk"):
		return
	var attempted: Dictionary = _diagnostic_interact_generated_node(
		preview_instance, spec, "exit_shelter", result, "progression_gate"
	)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	_record_check(
		result,
		"out_of_order_exit_blocked",
		not bool(attempted.get("completed", false))
			and not bool(chunk.get("shelter_rested", false)),
		"The exit shelter cannot complete before the causal node chain"
	)
	preview_instance.call("headless_call_chunk", "reset_preview_state", [])


func _diagnostic_reset_preview_state(preview_instance: Node) -> void:
	if preview_instance.has_method("headless_call_chunk"):
		preview_instance.call("headless_call_chunk", "reset_preview_state", [])


func _begin_player_animation_evidence_baseline(result: Dictionary) -> void:
	result["pre_evidence_events"] = (
		result.get("events", []) as Array
	).duplicate(true)
	result["player_evidence_event_start_index"] = (
		result.get("events", []) as Array
	).size()
	result["player_evidence_events"] = []
	if not result.has("animation"):
		return
	var animation: Dictionary = result.get("animation", {})
	animation["diagnostic_snapshots"] = (
		animation.get("snapshots", []) as Array
	).duplicate(true)
	animation["snapshots"] = []
	animation["snapshot_count"] = 0
	animation["evidence_baseline"] = "after_fixture_and_diagnostics"
	result["animation"] = animation


func _validate_random_walk_variety(result: Dictionary, spec: Dictionary) -> void:
	var composition: Dictionary = spec.get("composition", {})
	if not bool(composition.get("uses_random_walk", false)):
		return
	var ids: Array[String] = []
	for raw_node in spec.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if str(node.get("role", "")) in ["boundary", "shelter_arrival"] or bool(node.get("optional", false)):
			continue
		ids.append(str(node.get("archetype_id", "")))
	if ids.size() < 3:
		return
	var walk_settings: Dictionary = composition.get("random_walk", {}).get("settings", {})
	if walk_settings.is_empty():
		walk_settings = spec.get("settings", {}).get("composition", {}).get("random_walk", {})
	var max_consecutive := maxi(1, int(walk_settings.get("max_consecutive_archetype", 2)))
	var max_share := clampf(float(walk_settings.get("max_archetype_share", 0.5)), 0.25, 1.0)
	var longest_run := 0
	var current_run := 0
	var previous := ""
	var counts := {}
	for archetype_id in ids:
		current_run = current_run + 1 if archetype_id == previous else 1
		previous = archetype_id
		longest_run = maxi(longest_run, current_run)
		counts[archetype_id] = int(counts.get(archetype_id, 0)) + 1
	var largest_count := 0
	for count in counts.values():
		largest_count = maxi(largest_count, int(count))
	_record_check(
		result,
		"random_walk_consecutive_variety",
		longest_run <= max_consecutive,
		"Random walk repeats one archetype for too many consecutive critical beats"
	)
	_record_check(
		result,
		"random_walk_share_variety",
		largest_count <= int(ceil(float(ids.size()) * max_share)),
		"Random walk lets one archetype dominate the critical route"
	)


## Graph floors and render height are deliberately separate. A standard generated
## stretch owns one flat DATA level even when its coord_map bends that level into a
## descending helix; demanding multiple logical Y values there rewards coordinate-
## frame leakage. Conversely, a hard/setpiece golden path that names more than one
## authored elevation must actually traverse typed connector edges between them.
func _golden_path_declares_multiple_navigation_levels(spec: Dictionary) -> bool:
	var levels := {}
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	for node_id_v in path:
		var node := _find_node(spec, str(node_id_v))
		if node.is_empty():
			continue
		levels[int(node.get("elevation_index", 0))] = true
	return levels.size() > 1

func _base_result() -> Dictionary:
	return {
		"contract_id": "stretch_generation_playtest_loop_v1",
		"success": true,
		"ok": true,
		"spec_id": "",
		"preview_scene": "",
		"checks": {},
		"errors": [],
		"warnings": [],
		"playthroughs": {},
		"events": [],
		"event_count": 0,
	}

func _finish_result(result: Dictionary) -> Dictionary:
	var errors: Array = result.get("errors", [])
	result["success"] = errors.is_empty()
	result["ok"] = errors.is_empty()
	result["event_count"] = (result.get("events", []) as Array).size()
	result["player_evidence_event_count"] = (
		result.get("player_evidence_events", []) as Array
	).size()
	return result

## Two recorded solution paths differ when any shared node was cleared with a
## different approach — the proof that the run took a genuinely different route.
func _solution_paths_differ(path_a: Array, path_b: Array) -> bool:
	var by_node := {}
	for entry in path_a:
		if entry is Dictionary:
			by_node[str((entry as Dictionary).get("node", ""))] = str((entry as Dictionary).get("approach_id", ""))
	for entry in path_b:
		if not (entry is Dictionary):
			continue
		var node_id := str((entry as Dictionary).get("node", ""))
		if by_node.has(node_id) and by_node[node_id] != str((entry as Dictionary).get("approach_id", "")):
			return true
	return false

func _record_check(result: Dictionary, check_id: String, passed: bool, failure_message: String) -> void:
	var checks: Dictionary = result.get("checks", {})
	checks[check_id] = passed
	result["checks"] = checks
	if not passed:
		var errors: Array = result.get("errors", [])
		errors.append(failure_message)
		result["errors"] = errors

func _record_warning(result: Dictionary, message: String) -> void:
	var warnings: Array = result.get("warnings", [])
	warnings.append(message)
	result["warnings"] = warnings

func _append_event(result: Dictionary, phase: String, event_type: String, label: String, data := {}) -> void:
	var events: Array = result.get("events", [])
	events.append({
		"index": events.size() + 1,
		"phase": phase,
		"type": event_type,
		"label": label,
		"data": data.duplicate(true) if data is Dictionary else {},
	})
	result["events"] = events
	result["event_count"] = events.size()

func _append_report_event(report: Dictionary, phase: String, event_type: String, label: String, data := {}) -> void:
	var events: Array = report.get("events", [])
	events.append({
		"phase": phase,
		"type": event_type,
		"label": label,
		"data": data.duplicate(true) if data is Dictionary else {},
	})
	report["events"] = events

func _merge_playthrough_events(result: Dictionary, report: Dictionary) -> void:
	for event in report.get("events", []):
		if not (event is Dictionary):
			continue
		var event_dict := event as Dictionary
		var player_events: Array = result.get("player_evidence_events", [])
		player_events.append(event_dict.duplicate(true))
		result["player_evidence_events"] = player_events
		_append_event(
			result,
			str(event_dict.get("phase", "")),
			str(event_dict.get("type", "")),
			str(event_dict.get("label", "")),
			event_dict.get("data", {})
		)

func _validate_preview_boot(result: Dictionary, state: Dictionary) -> void:
	_record_check(result, "preview_chunk_is_generated", str(state.get("preview_chunk", "")) == "generated_stretch", "Preview is running the generated stretch chunk")
	_record_check(result, "preview_party_preset_full", str(state.get("preview_party_preset", "")) == "full_party_full_health", "Preview uses full-party/full-health preset")
	var ui: Dictionary = state.get("ui", {})
	_record_check(result, "shared_preview_gui", str(ui.get("contract_id", "")) == "fragment_preview_shared_gui_v1" and bool(ui.get("shared_hud", false)), "Preview uses the shared fragment GUI and HUD")
	_record_check(result, "canonical_controls_visible", str(ui.get("controls", "")).contains("party abilities"), "Preview exposes the remappable party-ability controls")
	var world_slot: Dictionary = state.get("world_slot", {})
	_record_check(result, "world_slot_exposed", str(world_slot.get("slot_id", "")) != "", "Preview exposes world-slot metadata")
	_record_check(result, "full_party_full_stats", _party_is_full(state), "Aster, Peris, and Endo start at max HP/stamina/ATP")
	var chunk: Dictionary = state.get("chunk", {})
	var graybox: Dictionary = chunk.get("graybox", {})
	var navigation: Dictionary = state.get("navigation", {})
	_record_check(result, "preview_graybox_spatial_contract", str(graybox.get("contract_id", "")) == "generated_stretch_graybox_v1", "Generated preview exposes the spatial graybox contract")
	_record_check(result, "preview_navigation_grid_contract", str(navigation.get("contract_id", "")) == "unified_grid_v1", "Generated preview installs the unified multi-level grid")
	_record_check(result, "preview_graybox_click_targets", bool(graybox.get("supports_click_to_move", false)) and int(graybox.get("outline_target_count", 0)) > 0, "Generated preview exposes click-to-move outline targets")
	_record_check(result, "preview_graybox_content_placed", int(graybox.get("content_placement_count", 0)) > 0 and int(graybox.get("instanced_content_marker_count", 0)) > 0, "Generated preview instances flora/enemy/structure placements")
	# A valid level has at least one playable floor. Verticality is tier-gated (teaching/standard are FLAT),
	# so multiple elevations are not required here — the multi-floor feature is covered by --test-grid-levels and
	# the hard/setpiece playthroughs. When a level IS multi-level, its floors must still be consistent (>= 1).
	_record_check(result, "preview_graybox_elevations", int(graybox.get("elevation_count", 0)) >= 1, "Generated preview exposes at least one playable floor")
	_append_event(result, "preview_boot", "preview_ready", "Preview booted with full party and shared HUD", {
		"preview_chunk": str(state.get("preview_chunk", "")),
		"preview_party_preset": str(state.get("preview_party_preset", "")),
		"world_slot": world_slot.duplicate(true),
		"active_character": str(state.get("active_character", "")),
		"controls": str(ui.get("controls", "")),
		"party_full_stats": _party_is_full(state),
		"graybox": graybox.duplicate(true),
		"navigation": navigation.duplicate(true),
	})
	_append_event(result, "preview_boot", "graybox_ready", "Generated graybox surfaces, elevations, and content placements are instanced", {
		"contract_id": str(graybox.get("contract_id", "")),
		"node_surfaces": int(graybox.get("node_surface_count", 0)),
		"route_surfaces": int(graybox.get("route_surface_count", 0)),
		"content_placements": int(graybox.get("content_placement_count", 0)),
		"outline_targets": int(graybox.get("outline_target_count", 0)),
		"elevation_count": int(graybox.get("elevation_count", 0)),
		"navigation_walkable_cells": int(navigation.get("walkable_cell_count", 0)),
		"navigation_links": int(navigation.get("link_count", 0)),
	})

func _party_is_full(state: Dictionary) -> bool:
	var stats: Dictionary = state.get("character_stats", {})
	for char_id in PARTY_IDS:
		var char_stats: Dictionary = stats.get(char_id, {})
		if absf(float(char_stats.get("hp", -999.0)) - 100.0) > 0.01:
			return false
		if absf(float(char_stats.get("sta", -999.0)) - 100.0) > 0.01:
			return false
		if absf(float(char_stats.get("atp", -999.0)) - float(GameState.ATP_MAX_PIPS)) > 0.01:
			return false
	return true

## Pre-evidence semantic ability-routing diagnostic. This is not a persona
## action or playthrough receipt and its state is reset before measured play.
func _diagnostic_exercise_abilities(result: Dictionary, preview_instance: Node) -> void:
	if (
		not preview_instance.has_method("headless_select_character")
		or not preview_instance.has_method("headless_get_party_ability_routes")
		or not preview_instance.has_method("headless_activate_ability_action")
	):
		_record_check(result, "main_abilities_callable", false, "Preview exposes the canonical targeted-ability action contract")
		return
	var ability_specs := [
		{"char_id": "aster", "ability_id": "emp"},
		{"char_id": "peris", "ability_id": "wrap"},
	]
	var ability_routes: Dictionary = preview_instance.call("headless_get_party_ability_routes")
	var all_abilities_ok := true
	var ability_report := {}
	for spec in ability_specs:
		var char_id := str(spec.get("char_id", ""))
		var ability_id := str(spec.get("ability_id", ""))
		var route: Dictionary = ability_routes.get(ability_id, {})
		var input_action := str(route.get("input_action", ""))
		preview_instance.call("headless_select_character", char_id)
		var before: Dictionary = preview_instance.call("headless_get_state")
		var before_stats: Dictionary = before.get("character_stats", {}).get(char_id, {})
		var before_stamina := float(before_stats.get("sta", -1.0))
		var activated := input_action != "" and bool(preview_instance.call("headless_activate_ability_action", input_action))
		var after: Dictionary = preview_instance.call("headless_get_state")
		var after_stats: Dictionary = after.get("character_stats", {}).get(char_id, {})
		var ability_state: Dictionary = after.get("abilities", {}).get(ability_id, {})
		var spent_stamina := float(after_stats.get("sta", before_stamina)) < before_stamina
		var state_changed := str(ability_state.get("state", "ready")) != "ready"
		var ok := (
			activated
			and spent_stamina
			and state_changed
			and int(route.get("party_slot", -1)) >= 0
			and int(route.get("ability_slot", -1)) >= 0
			and str(ability_state.get("input_action", "")) == input_action
		)
		all_abilities_ok = all_abilities_ok and ok
		ability_report[ability_id] = {
			"activated": activated,
			"spent_stamina": spent_stamina,
			"state": str(ability_state.get("state", "")),
			"keybind": str(ability_state.get("keybind", "")),
			"input_action": input_action,
			"party_slot": int(route.get("party_slot", -1)),
			"ability_slot": int(route.get("ability_slot", -1)),
		}
		_append_event(result, "preview_boot", "ability_activated", "%s used %s" % [char_id.capitalize(), ability_id], {
			"character": char_id,
			"ability_id": ability_id,
			"keybind": str(ability_state.get("keybind", "")),
			"input_action": input_action,
			"activated": activated,
			"spent_stamina": spent_stamina,
			"before_stamina": before_stamina,
			"after_stamina": float(after_stats.get("sta", before_stamina)),
			"state": str(ability_state.get("state", "")),
		})
		_record_animation_snapshot(result, preview_instance, "preview_boot", "%s activated %s" % [char_id.capitalize(), ability_id], {
			"event_type": "ability_activated",
			"character": char_id,
			"ability_id": ability_id,
			"keybind": str(ability_state.get("keybind", "")),
			"input_action": input_action,
			"activated": activated,
			"spent_stamina": spent_stamina,
		})
	result["ability_report"] = ability_report
	_record_check(result, "main_abilities_exercised", all_abilities_ok, "Canonical EMP and Wrap route to their owners and spend stamina")

## Compatibility entry point. "golden_path" is the stable report key, not the
## decision source: the measured run discovers live, visible interaction
## surfaces and never reads the emitted solver trace to choose an action.
func _play_golden_path(
	preview_instance: Node, _spec: Dictionary, result := {}, options := {}
) -> Dictionary:
	return await _play_visible_surface_path(
		preview_instance,
		result,
		options,
		"golden_path",
		"first_read",
		""
	)


## Shared executor for generated-stretch player evidence. The policy sees only
## live on-screen interaction surfaces and player-facing feedback. Solver node
## IDs, routes, solution actions, and golden/shadow traces never select an
## action here. Every party travel intent is exactly one held-RMB Rally through
## AgentPlayerInputDriver; interactions are ordinary right-clicks.
func _play_visible_surface_path(
	preview_instance: Node,
	result: Dictionary,
	options: Dictionary,
	path_id: String,
	policy: String,
	fixture_loadout: String
) -> Dictionary:
	var report := _base_player_surface_report(path_id, policy)
	if preview_instance == null or not is_instance_valid(preview_instance):
		report["abort_reason"] = "missing_preview"
		return report
	if not preview_instance.has_method("headless_get_state"):
		report["abort_reason"] = "missing_read_only_state"
		return report
	if DisplayServer.get_name() == "headless":
		# Raw pointer routing and the held-RMB threshold are not present on the
		# headless display server. Treating a direct callback or semantic QA action
		# as equivalent here is the exact false-positive this boundary forbids.
		report["evidence_kind"] = "player_input_not_collected"
		report["decision_source"] = "none_headless"
		report["evidence_status"] = "requires_windowed_or_web_input_surface"
		report["abort_reason"] = "headless_has_no_shipped_pointer_surface"
		report["render_evidence_scope"] = "none"
		report["approval_eligible"] = false
		report["persona_decision_feed_eligible"] = false
		report["fixture_quarantine"] = {
			"classification": "not_run",
			"counts_toward_playthrough": false,
		}
		return report

	# Reset/roster construction is fixture-only. It happens before the input
	# driver is cleared and before timestamps, receipts, or movement evidence are
	# sampled, so no setup mutation can satisfy the measured run.
	report["fixture_quarantine"] = _fixture_prepare_player_evidence(
		preview_instance, options, fixture_loadout
	)
	# Interactive previews only attach an EventLog while the optional playthrough
	# recorder is active.  The Windowed test lane runs that recorder in OFF mode,
	# so without fixture instrumentation the real SelectionController can accept a
	# Rally (and show RALLY QUEUED) while the input driver has no production log in
	# which to verify its single atomic command.  Attach the empty observer before
	# the evidence baseline; this records commands but neither chooses nor applies
	# an action.
	var game_state = preview_instance.get("_game_state")
	var event_log_attached := false
	if game_state != null and game_state.event_log == null:
		game_state.event_log = EventLog.new()
		event_log_attached = true
	(report["fixture_quarantine"] as Dictionary)["event_log_instrumentation"] = {
		"attached": event_log_attached,
		"available": game_state != null and game_state.event_log != null,
		"counts_toward_playthrough": false,
	}
	var driver: Node = _player_input_driver(preview_instance)
	if driver == null:
		report["abort_reason"] = "missing_player_input_driver"
		return report
	var observer: Node = _player_observation_controller(preview_instance)
	if observer == null:
		report["abort_reason"] = "missing_player_observation_controller"
		return report
	driver.call("clear_receipts")
	await preview_instance.get_tree().process_frame

	var start_state: Dictionary = preview_instance.call("headless_get_state")
	report["started_at"] = float(start_state.get("scheduler_tick", 0.0))
	report["evidence_baseline"] = {
		"scheduler_tick": report["started_at"],
		"receipt_count": 0,
		"event_count": game_state.event_log.size()
			if game_state != null and game_state.event_log != null else 0,
		"movement_commands": 0,
		"physical_interactions": 0,
	}
	# This nonce is artifact provenance only. It is captured after every fixture
	# reset/instrumentation step and before the first player observation or shipped
	# input, then copied unchanged into the diagnostic run header and each decision.
	var baseline_nonce := Time.get_ticks_usec() # @artifact_metadata_only
	report["evidence_baseline_id"] = "%s:%s:%d" % [
		str(result.get("spec_id", "generated_stretch")), path_id, baseline_nonce,
	]
	_append_report_event(
		report,
		path_id,
		"player_discovery_started",
		"Visible player-surface discovery started",
		{
			"decision_source": "live_player_observable_surface",
			"policy": policy,
			"solver_trace_used_for_actions": false,
		}
	)
	_record_animation_snapshot(
		result,
		preview_instance,
		path_id,
		"Player-input evidence baseline",
		{
			"event_type": "player_discovery_started",
			"policy": policy,
			"solver_trace_used_for_actions": false,
		}
	)

	var discovery: Dictionary = await _drive_visible_player_discovery(
		preview_instance,
		driver,
		observer,
		result,
		options,
		path_id,
		policy,
		str(report["evidence_baseline_id"])
	)
	report.merge(discovery, true)
	var final_state: Dictionary = preview_instance.call("headless_get_state")
	_populate_player_surface_outcome(report, final_state)
	var policy_validation := _validate_player_surface_policy_evidence(report)
	report.merge(policy_validation, true)
	var observation_decision_links_valid := bool(
		policy_validation.get("observation_decision_links_valid", false))
	var validated_observation_decision_count := int(
		policy_validation.get("validated_observation_decision_count", 0))
	var visible_movement_receipts_valid := bool(
		policy_validation.get("visible_movement_receipts_valid", false))
	report["observation_decision_links_valid"] = observation_decision_links_valid
	report["validated_observation_decision_count"] = \
		validated_observation_decision_count
	report["visible_movement_receipts_valid"] = visible_movement_receipts_valid
	report["ended_at"] = float(final_state.get("scheduler_tick", 0.0))
	report["duration"] = maxf(
		0.0, float(report["ended_at"]) - float(report["started_at"])
	)
	report["action_receipts"] = driver.call("receipts")
	report["render_evidence_scope"] = (
		"semantic_input_only_headless"
		if DisplayServer.get_name() == "headless"
		else "native_framebuffer_and_input"
	)
	var visible_evidence_complete := (
		bool(report.get("visible_outcome_reached", false))
		and bool(report.get("decision_trace_complete", false))
		and observation_decision_links_valid
		and validated_observation_decision_count \
			== int(report.get("decision_count", -1))
		and visible_movement_receipts_valid
		and (report.get("atomic_rally_failures", []) as Array).is_empty()
		and (report.get("interaction_failures", []) as Array).is_empty()
	)
	report["visible_policy_evidence_complete"] = visible_evidence_complete
	report["approval_eligible"] = (
		DisplayServer.get_name() != "headless"
		and visible_evidence_complete
		# Private end state is only a cross-check that the rendered success cue was
		# truthful; it can never substitute for the visible policy evidence above.
		and bool(report.get("shelter_rested", false))
	)
	# first_read/risk_seeking are unnamed generated strategies. Their diagnostic
	# chain is intentionally quarantined until an explicit named-persona enrollment
	# run reproduces it through the canonical PersonaDecisionTrace writer.
	report["persona_decision_feed_eligible"] = false
	report["persona_tree_ineligible_reason"] = "unnamed_strategy_not_persona"
	report["evidence_status"] = (
		"player_input_complete_diagnostic_strategy"
		if visible_evidence_complete and bool(report.get("shelter_rested", false))
		else "player_input_incomplete"
	)
	if visible_evidence_complete and bool(report.get("shelter_rested", false)):
		_append_report_event(
			report,
			path_id,
			"shelter_rested",
			"Visible discovery reached and rested at the exit shelter",
			{"last_outcome": report.get("final_outcome", "")}
		)
		_record_animation_snapshot(
			result,
			preview_instance,
			path_id,
			"Visible discovery rested at shelter",
			{"event_type": "shelter_rested"}
		)
	return report


func _base_player_surface_report(path_id: String, policy: String) -> Dictionary:
	return {
		"path_id": path_id,
		"evidence_kind": "visible_player_surface_discovery",
		"decision_source": "live_player_observable_surface",
		"decision_policy": policy,
		"solver_trace_used_for_actions": false,
		"visited_nodes": [],
		"visible_decisions": [],
		"presentation_only_decisions": [],
		"decision_trace_schema": GENERATED_STRATEGY_TRACE_SCHEMA,
		"decision_trace_records": [],
		"decision_trace_baseline_id": "",
		"persona_tree_ineligible_reason": "unnamed_strategy_not_persona",
		"watchdog_contract": {},
		"watchdog_heartbeats": [],
		"watchdog_failures": [],
		"watchdog_input_release": {},
		"decision_trace_chain_tail": "",
		"decision_trace_failures": [],
		"decision_trace_complete": false,
		"route_ids": [],
		"route_choices": 0,
		"movement_commands": 0,
		"rally_gestures": 0,
		"atomic_rally_failures": [],
		"party_binding_preconditions": [],
		"party_binding_failures": [],
		"initial_party_binding_precondition": {},
		"max_path_points": 0,
		"used_multi_y_path": false,
		"route_gaps": [],
		"physical_interactions": 0,
		"refused_actions": [],
		"interaction_failures": [],
		"solution_action_failures": [],
		"shelter_rested": false,
		"first_shelter_beat_fired": false,
		"risk_surface_attempted": false,
		"events": [],
	}


func _fixture_prepare_player_evidence(
	preview_instance: Node, options: Dictionary, loadout: String
) -> Dictionary:
	var report := {
		"classification": "fixture_only_before_evidence_baseline",
		"reset_requested": bool(options.get("reset_before_play", true)),
		"reset_applied": false,
		"loadout_requested": loadout,
		"loadout_applied": false,
		"counts_toward_playthrough": false,
	}
	if not preview_instance.has_method("headless_call_chunk"):
		return report
	if bool(report["reset_requested"]):
		preview_instance.call("headless_call_chunk", "reset_preview_state", [])
		report["reset_applied"] = true
	if loadout != "":
		preview_instance.call("headless_call_chunk", "set_active_loadout", [loadout])
		report["loadout_applied"] = true
	return report


func _player_input_driver(preview_instance: Node) -> Node:
	var existing := preview_instance.get_node_or_null("AgentPlayerInputDriver")
	if existing != null:
		existing.call("setup", preview_instance)
		return existing
	var driver: Node = AgentPlayerInputDriverScript.new()
	driver.name = "AgentPlayerInputDriver"
	preview_instance.add_child(driver)
	driver.call("setup", preview_instance)
	return driver


func _player_observation_controller(preview_instance: Node) -> Node:
	var existing := preview_instance.get_node_or_null("PlayerObservationController")
	if existing != null:
		existing.call("setup", preview_instance)
		return existing
	var observer: Node = PlayerObservationControllerScript.new()
	observer.name = "PlayerObservationController"
	preview_instance.add_child(observer)
	observer.call("setup", preview_instance)
	return observer


func _new_player_discovery_watchdog(
		options: Dictionary, path_id: String
	) -> Dictionary:
	var started_usec := Time.get_ticks_usec() # @artifact_metadata_only
	var path_budget := clampf(float(options.get(
		"player_discovery_path_wall_seconds",
		PLAYER_DISCOVERY_PATH_MAX_SECONDS)), 1.0,
		PLAYER_DISCOVERY_PATH_MAX_SECONDS)
	var global_deadline_usec := int(options.get(
		"player_discovery_global_deadline_usec", 0))
	var visible_progress_timeout := clampf(float(options.get(
		"player_discovery_visible_progress_seconds",
		PLAYER_DISCOVERY_VISIBLE_PROGRESS_TIMEOUT_SECONDS)), 0.1, 30.0)
	var rally_start_timeout := clampf(float(options.get(
		"player_discovery_rally_start_seconds",
		PLAYER_DISCOVERY_RALLY_START_TIMEOUT_SECONDS)), 0.1, 30.0)
	var rally_incomplete_stable_timeout := clampf(float(options.get(
		"player_discovery_rally_incomplete_stable_seconds",
		PLAYER_DISCOVERY_RALLY_INCOMPLETE_STABLE_SECONDS)), 0.1, 30.0)
	return {
		"path_id": path_id,
		"started_usec": started_usec,
		"path_deadline_usec": started_usec + int(path_budget * 1000000.0),
		"global_started_usec": int(options.get(
			"player_discovery_global_started_usec", started_usec)),
		"global_deadline_usec": global_deadline_usec,
		"path_wall_seconds": path_budget,
		"global_wall_seconds": float(options.get(
			"player_discovery_global_wall_seconds", 0.0)),
		"visible_progress_timeout_seconds": visible_progress_timeout,
		"rally_start_timeout_seconds": rally_start_timeout,
		"rally_incomplete_stable_timeout_seconds": \
			rally_incomplete_stable_timeout,
		"last_visible_progress_usec": started_usec,
		"last_visible_progress_kind": "awaiting_initial_player_observation",
		"progress_event_count": 0,
		"next_heartbeat_usec": started_usec,
		"heartbeat_count": 0,
		"pending_abort_reason": "",
		"aborted": false,
		"observation_scan_usec": 0,
	}


## PlayerObservationController.snapshot() is a synchronous framebuffer/physics
## scan. While it runs, the SceneTree cannot advance a movement frame, so that
## CPU/render cost is not player wait time and cannot consume a gameplay-stall
## budget. The tracked launcher still owns the hard child-process timeout.
func _player_observation_snapshot(
		observer: Node, watchdog: Dictionary = {}
	) -> Variant:
	if observer == null or not observer.has_method("snapshot"):
		return null
	var scan_started_usec := Time.get_ticks_usec() # @artifact_metadata_only
	var observation_v: Variant = observer.call("snapshot")
	var scan_usec := maxi(0, Time.get_ticks_usec() - scan_started_usec) # @artifact_metadata_only
	if not watchdog.is_empty() and scan_usec > 0:
		_credit_player_observation_scan_time(watchdog, scan_usec)
	return observation_v


func _credit_player_observation_scan_time(
		watchdog: Dictionary, scan_usec: int
	) -> void:
	if watchdog.is_empty() or scan_usec <= 0:
		return
	watchdog["observation_scan_usec"] = int(watchdog.get(
		"observation_scan_usec", 0)) + scan_usec
	# Preserve the configured thresholds while moving their absolute clock edges
	# past time during which no production frame could possibly run.
	var path_deadline := int(watchdog.get("path_deadline_usec", 0))
	if path_deadline > 0:
		watchdog["path_deadline_usec"] = path_deadline + scan_usec
	# global_deadline_usec deliberately remains raw wall time: it is the
	# independent hard outer cap if observation itself becomes pathologically slow.
	if watchdog.has("last_visible_progress_usec"):
		watchdog["last_visible_progress_usec"] = int(watchdog.get(
			"last_visible_progress_usec", 0)) + scan_usec


static func _rally_incomplete_progress_stalled(
		active_elapsed: float,
		last_progress_elapsed: float,
		timeout_seconds: float
	) -> bool:
	return timeout_seconds > 0.0 \
		and active_elapsed - last_progress_elapsed >= timeout_seconds


func _player_discovery_watchdog_report(watchdog: Dictionary) -> Dictionary:
	var now_usec := Time.get_ticks_usec() # @artifact_metadata_only
	var path_deadline_usec := int(watchdog.get("path_deadline_usec", now_usec))
	var global_deadline_usec := int(watchdog.get("global_deadline_usec", 0))
	var observation_scan_usec := int(watchdog.get("observation_scan_usec", 0))
	return {
		"contract": "visible_player_ci_watchdog_v1",
		"clock_basis": "active_path_and_progress;hard_global_wall",
		"path_id": str(watchdog.get("path_id", "")),
		"path_wall_seconds": float(watchdog.get("path_wall_seconds", 0.0)),
		"global_wall_seconds": float(watchdog.get("global_wall_seconds", 0.0)),
		"visible_progress_timeout_seconds": float(watchdog.get(
			"visible_progress_timeout_seconds", 0.0)),
		"rally_start_timeout_seconds": float(watchdog.get(
			"rally_start_timeout_seconds", 0.0)),
		"rally_incomplete_stable_timeout_seconds": float(watchdog.get(
			"rally_incomplete_stable_timeout_seconds", 0.0)),
		"elapsed_seconds": maxf(0.0, float(
			now_usec - int(watchdog.get("started_usec", now_usec))) / 1000000.0),
		"active_wait_seconds": maxf(0.0, float(
			now_usec - int(watchdog.get("started_usec", now_usec))
			- observation_scan_usec) / 1000000.0),
		"observation_scan_seconds": float(observation_scan_usec) / 1000000.0,
		"path_remaining_seconds": maxf(
			0.0, float(path_deadline_usec - now_usec) / 1000000.0),
		"global_remaining_seconds": (
			maxf(0.0, float(global_deadline_usec - now_usec) / 1000000.0)
			if global_deadline_usec > 0 else -1.0
		),
		"last_visible_progress_kind": str(watchdog.get(
			"last_visible_progress_kind", "")),
		"seconds_since_visible_progress": maxf(0.0, float(
			now_usec - int(watchdog.get(
				"last_visible_progress_usec", now_usec))) / 1000000.0),
		"progress_event_count": int(watchdog.get("progress_event_count", 0)),
		"heartbeat_count": int(watchdog.get("heartbeat_count", 0)),
		"pending_abort_reason": str(watchdog.get("pending_abort_reason", "")),
		"aborted": bool(watchdog.get("aborted", false)),
	}


func _player_discovery_watchdog_abort_reason(watchdog: Dictionary) -> String:
	var pending := str(watchdog.get("pending_abort_reason", ""))
	if pending != "":
		return pending
	var now_usec := Time.get_ticks_usec() # @artifact_metadata_only
	var global_deadline_usec := int(watchdog.get("global_deadline_usec", 0))
	if global_deadline_usec > 0 and now_usec >= global_deadline_usec:
		return "global_player_discovery_wall_deadline"
	if now_usec >= int(watchdog.get("path_deadline_usec", now_usec + 1)):
		return "path_player_discovery_wall_deadline"
	var visible_progress_timeout_usec := int(float(watchdog.get(
		"visible_progress_timeout_seconds",
		PLAYER_DISCOVERY_VISIBLE_PROGRESS_TIMEOUT_SECONDS)) * 1000000.0)
	if visible_progress_timeout_usec > 0 and now_usec - int(watchdog.get(
			"last_visible_progress_usec", now_usec)) >= visible_progress_timeout_usec:
		return "player_visible_causal_progress_stalled"
	return ""


func _set_player_discovery_watchdog_pending(
		watchdog: Dictionary, reason: String
	) -> void:
	if reason != "" and str(watchdog.get("pending_abort_reason", "")) == "":
		watchdog["pending_abort_reason"] = reason


func _note_player_discovery_visible_progress(
		watchdog: Dictionary, progress_kind: String
	) -> void:
	var now_usec := Time.get_ticks_usec() # @artifact_metadata_only
	watchdog["last_visible_progress_usec"] = now_usec
	watchdog["last_visible_progress_kind"] = progress_kind
	watchdog["progress_event_count"] = int(watchdog.get(
		"progress_event_count", 0)) + 1


func _consider_player_discovery_observation_progress(
		watchdog: Dictionary,
		before: Dictionary,
		after: Dictionary,
		progress_kind: String
	) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	if not PersonaDecisionTraceScript.validate_player_observation(
			before).is_empty() or not PersonaDecisionTraceScript.validate_player_observation(
			after).is_empty():
		return false
	if _player_observation_action_progress_signature(before) \
			== _player_observation_action_progress_signature(after):
		return false
	_note_player_discovery_visible_progress(watchdog, progress_kind)
	return true


func _emit_player_discovery_heartbeat(
		report: Dictionary,
		watchdog: Dictionary,
		decision_count: int,
		stage: String
	) -> void:
	var now_usec := Time.get_ticks_usec() # @artifact_metadata_only
	var forced := stage in ["initial_observation", "choose_action", "watchdog_abort"]
	if not forced and now_usec < int(watchdog.get("next_heartbeat_usec", 0)):
		return
	watchdog["next_heartbeat_usec"] = now_usec + int(
		PLAYER_DISCOVERY_HEARTBEAT_SECONDS * 1000000.0)
	watchdog["heartbeat_count"] = int(watchdog.get("heartbeat_count", 0)) + 1
	var heartbeat := {
		"path_id": str(watchdog.get("path_id", "")),
		"decision_count": decision_count,
		"stage": stage,
		"elapsed_seconds": snappedf(maxf(0.0, float(
			now_usec - int(watchdog.get("started_usec", now_usec))) / 1000000.0),
			0.001),
		"seconds_since_visible_progress": snappedf(maxf(0.0, float(
			now_usec - int(watchdog.get(
				"last_visible_progress_usec", now_usec))) / 1000000.0), 0.001),
		"last_visible_progress_kind": str(watchdog.get(
			"last_visible_progress_kind", "")),
	}
	(report["watchdog_heartbeats"] as Array).append(heartbeat)
	print("[PLAYER_E2E_HEARTBEAT] %s" % JSON.stringify(heartbeat))


func _abort_player_discovery_for_watchdog(
		driver: Node,
		report: Dictionary,
		watchdog: Dictionary,
		reason: String
	) -> void:
	if bool(watchdog.get("aborted", false)):
		return
	watchdog["aborted"] = true
	watchdog["pending_abort_reason"] = reason
	var failure := {
		"failure": "player_discovery_watchdog_abort",
		"reason": reason,
		"player_observable_evidence_preserved": true,
	}
	(report["watchdog_failures"] as Array).append(failure.duplicate(true))
	(report["interaction_failures"] as Array).append(failure.duplicate(true))
	report["abort_reason"] = reason
	var release_receipt := {
		"kind": "watchdog_input_release",
		"reason": reason,
		"all_inputs_released": false,
	}
	if driver != null and driver.has_method("release_all_held_input"):
		var release_v: Variant = await driver.call(
			"release_all_held_input", reason)
		if release_v is Dictionary:
			release_receipt = (release_v as Dictionary).duplicate(true)
	report["watchdog_input_release"] = release_receipt
	_emit_player_discovery_heartbeat(
		report, watchdog, int(report.get("decision_count", 0)), "watchdog_abort")
	report["watchdog_contract"] = _player_discovery_watchdog_report(watchdog)
	print("[PLAYER_E2E_WATCHDOG_ABORT] %s" % JSON.stringify({
		"path_id": str(watchdog.get("path_id", "")),
		"reason": reason,
		"input_release": release_receipt,
	}))


## Fail-closed presence precondition for generated player-surface decisions.
## Every visible HUD portrait needs either one exact, unique, visible world-body
## binding OR the case-exact HIDDEN word that the HUD actually rendered. COVERED
## is informative but does not excuse a missing body. Concealed portraits stay
## selectable and may participate in one held-RMB Rally; they never receive a
## fabricated body token. This consumes no scene nodes, transforms, authored
## IDs, GameState values, or solver data.
func _player_observation_exact_party_presence_bindings(
		observation: Dictionary
	) -> Dictionary:
	var issues: Array[String] = []
	if str(observation.get("schema", "")) != PLAYER_DISCOVERY_OBSERVATION_SCHEMA:
		issues.append("wrong_observation_schema")
	if str(observation.get("source", "")) != "player_observable":
		issues.append("wrong_observation_source")
	for issue_v in PersonaDecisionTraceScript.validate_player_observation(
		observation):
		var issue := "observation_invalid:%s" % str(issue_v)
		if not issues.has(issue):
			issues.append(issue)

	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		issues.append("missing_observation_state")
		return {
			"valid": false,
			"capture_serial": int(observation.get("capture_serial", 0)),
			"portrait_tokens": [],
			"actual_visible_body_tokens": [],
			"body_tokens": [], # compatibility alias: actual visible bodies only
			"concealed_portrait_tokens": [],
			"covered_portrait_tokens": [],
			"bindings": {},
			"presence_modes": {},
			"issues": issues,
		}
	var state := state_v as Dictionary
	var hud_v: Variant = state.get("hud", {})
	var portrait_tokens: Array[String] = []
	var portrait_token_set := {}
	var portrait_labels := {}
	var portrait_statuses := {}
	var concealed_portrait_tokens: Array[String] = []
	var covered_portrait_tokens: Array[String] = []
	if hud_v is Dictionary:
		for portrait_v in (hud_v as Dictionary).get("portraits", []):
			if not (portrait_v is Dictionary) \
					or not bool((portrait_v as Dictionary).get("visible", false)):
				continue
			var portrait_token := str(
				(portrait_v as Dictionary).get("token", ""))
			if portrait_token == "":
				issues.append("visible_portrait_missing_token")
				continue
			if portrait_token_set.has(portrait_token):
				issues.append("duplicate_visible_portrait_token:%s" % portrait_token)
				continue
			portrait_token_set[portrait_token] = true
			portrait_labels[portrait_token] = str(
				(portrait_v as Dictionary).get("label", "")).strip_edges()
			var statuses_v: Variant = (portrait_v as Dictionary).get(
				"statuses", [])
			var statuses: Array[String] = []
			if not (statuses_v is Array):
				issues.append(
					"visible_portrait_statuses_not_array:%s" % portrait_token)
			else:
				for status_v in statuses_v as Array:
					if not (status_v is String):
						issues.append(
							"visible_portrait_status_not_string:%s" % portrait_token)
						continue
					var status := str(status_v)
					if status == "":
						issues.append(
							"visible_portrait_status_empty:%s" % portrait_token)
					elif status != status.strip_edges():
						issues.append(
							"visible_portrait_status_not_exact:%s" % portrait_token)
					elif statuses.has(status):
						issues.append(
							"visible_portrait_status_duplicate:%s:%s" % [
								portrait_token, status])
					else:
						statuses.append(status)
				var sorted_statuses := statuses.duplicate()
				sorted_statuses.sort()
				if statuses != sorted_statuses:
					issues.append(
						"visible_portrait_statuses_unsorted:%s" % portrait_token)
			portrait_statuses[portrait_token] = statuses
			if statuses.has("HIDDEN"):
				concealed_portrait_tokens.append(portrait_token)
			if statuses.has("COVERED"):
				covered_portrait_tokens.append(portrait_token)
			if statuses.has("HIDDEN") and statuses.has("COVERED"):
				issues.append(
					"visible_portrait_conflicting_presence_statuses:%s" \
					% portrait_token)
			portrait_tokens.append(portrait_token)
	else:
		issues.append("missing_observation_hud")
	portrait_tokens.sort()
	concealed_portrait_tokens.sort()
	covered_portrait_tokens.sort()
	if portrait_tokens.is_empty():
		issues.append("no_visible_hud_portraits")

	var bindings := {}
	var body_tokens: Array[String] = []
	var body_token_set := {}
	var body_screens := {}
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "party_body" \
				or not bool(cue.get("visible", false)):
			continue
		var binding := str(cue.get("binding", ""))
		var body_token := str(cue.get("source_token", ""))
		if binding == "":
			issues.append("visible_party_body_missing_binding")
		if body_token == "":
			issues.append("visible_party_body_missing_token")
		if binding != "" and not portrait_token_set.has(binding):
			issues.append("visible_party_body_unmatched_binding:%s" % binding)
		if binding != "" and bindings.has(binding):
			issues.append("duplicate_visible_party_body_binding:%s" % binding)
		elif binding != "" and body_token != "":
			bindings[binding] = body_token
		if body_token != "":
			if body_token_set.has(body_token):
				issues.append("duplicate_visible_party_body_token:%s" % body_token)
			else:
				body_token_set[body_token] = true
				body_tokens.append(body_token)
		var screen_v: Variant = cue.get("screen", [])
		if not (screen_v is Array) or (screen_v as Array).size() != 2:
			issues.append("visible_party_body_missing_screen:%s" % body_token)
		else:
			var point := Vector2(
				float((screen_v as Array)[0]), float((screen_v as Array)[1]))
			if not point.is_finite():
				issues.append("visible_party_body_nonfinite_screen:%s" % body_token)
			elif body_token != "":
				body_screens[body_token] = [point.x, point.y]
	body_tokens.sort()
	var presence_modes := {}
	for portrait_token in portrait_tokens:
		if bindings.has(portrait_token):
			if concealed_portrait_tokens.has(portrait_token):
				issues.append(
					"visible_portrait_hidden_with_visible_body:%s" \
					% portrait_token)
			presence_modes[portrait_token] = {
				"mode": "visible_body",
				"body_token": str(bindings.get(portrait_token, "")),
			}
		elif concealed_portrait_tokens.has(portrait_token):
			presence_modes[portrait_token] = {
				"mode": "rendered_hidden",
				"status": "HIDDEN",
			}
		else:
			issues.append("visible_portrait_missing_party_body:%s" % portrait_token)
	# Uniqueness and cardinality are about real body tokens only. A rendered
	# HIDDEN portrait is a distinct presence mode, never a synthetic body.
	if bindings.size() != body_tokens.size():
		issues.append("visible_party_body_token_count_mismatch")
	if presence_modes.size() != portrait_tokens.size():
		issues.append("visible_portrait_presence_count_mismatch")
	issues.sort()
	return {
		"valid": issues.is_empty(),
		"capture_serial": int(observation.get("capture_serial", 0)),
		"portrait_tokens": portrait_tokens,
		"portrait_labels": portrait_labels,
		"portrait_statuses": portrait_statuses,
		"concealed_portrait_tokens": concealed_portrait_tokens,
		"covered_portrait_tokens": covered_portrait_tokens,
		"actual_visible_body_tokens": body_tokens,
		"body_tokens": body_tokens,
		"body_screens": body_screens,
		"bindings": bindings,
		"presence_modes": presence_modes,
		"issues": issues,
	}


func _player_discovery_world_input_count(driver: Node) -> int:
	if driver == null or not driver.has_method("receipts"):
		return 0
	var count := 0
	for receipt_v in driver.call("receipts"):
		if not (receipt_v is Dictionary):
			continue
		if str((receipt_v as Dictionary).get("kind", "")) in [
			"move", "rally", "interact", "set_party_running",
			"use_item", "drop_item", "transfer_item", "retrieve_item",
		]:
			count += 1
	return count


## Raw receipt identities are validation-only. They explain which ordinary
## player action preceded a failed body binding without becoming policy input.
func _player_discovery_world_action_history(driver: Node) -> Array:
	var history: Array = []
	if driver == null or not driver.has_method("receipts"):
		return history
	for receipt_v in driver.call("receipts"):
		if not (receipt_v is Dictionary):
			continue
		var receipt := receipt_v as Dictionary
		var kind := str(receipt.get("kind", ""))
		if kind not in [
			"move", "rally", "interact", "set_party_running",
			"use_item", "drop_item", "transfer_item", "retrieve_item",
		]:
			continue
		history.append({
			"id": int(receipt.get("id", 0)),
			"kind": kind,
			"accepted": bool(receipt.get("accepted", false)),
			"target_token": str(receipt.get("target_token", "")),
			"character_id": str(receipt.get("character_id", "")),
			"atomic_group": bool(receipt.get("atomic_group", false)),
			"production_event_count": int(receipt.get(
				"production_event_count", 0)),
			"reason": str(receipt.get("reason", "")),
		})
	return history


func _player_observation_validation_party_probe(observer: Node) -> Dictionary:
	if observer == null or not observer.has_method(
			"validation_party_body_probe"):
		return {}
	var probe_v: Variant = observer.call("validation_party_body_probe")
	return (probe_v as Dictionary).duplicate(true) \
		if probe_v is Dictionary else {}


func _player_discovery_binding_gate_record(gate: Dictionary) -> Dictionary:
	var record := gate.duplicate(true)
	record.erase("observation")
	# These carry raw subject IDs, transforms, camera state, node paths, and
	# receipt history solely for failed-gate diagnosis. Never serialize them into
	# decision records or the policy-facing precondition report.
	record.erase("validation_party_body_probes")
	record.erase("validation_world_action_history")
	var public_steps: Array = []
	for step_v in record.get("recovery_steps", []):
		if not (step_v is Dictionary):
			continue
		var step := step_v as Dictionary
		var before_v: Variant = step.get("before", {})
		var after_v: Variant = step.get("after", {})
		public_steps.append({
			"recovery_index": int(step.get("recovery_index", -1)),
			"receipt": (step.get("receipt", {}) as Dictionary).duplicate(true),
			"before_capture_serial": int((before_v as Dictionary).get(
				"capture_serial", 0)) if before_v is Dictionary else 0,
			"after_capture_serial": int((after_v as Dictionary).get(
				"capture_serial", 0)) if after_v is Dictionary else 0,
			"before_observation_hash": PersonaDecisionTraceScript.canonical_hash(
				before_v as Dictionary) if before_v is Dictionary else "",
			"after_observation_hash": PersonaDecisionTraceScript.canonical_hash(
				after_v as Dictionary) if after_v is Dictionary else "",
		})
	record["recovery_steps"] = public_steps
	return record


## Camera recovery is itself restricted to shipped presentation controls:
## Home, wheel zoom, held Q/E yaw, and WASD pan. The helper verifies that those
## attempts did not add a gameplay-command receipt.
func _require_player_observation_party_bindings(
		driver: Node,
		observer: Node,
		starting_observation: Dictionary,
		context: String,
		max_recoveries: int,
		watchdog: Dictionary = {}
	) -> Dictionary:
	var current := starting_observation
	var checks: Array = []
	var recovery_receipts: Array = []
	var recovery_steps: Array = []
	var validation_party_body_probes: Array = [
		_player_observation_validation_party_probe(observer),
	]
	var validation_world_action_history := \
		_player_discovery_world_action_history(driver)
	var world_input_count_before := _player_discovery_world_input_count(driver)
	var recovery_limit := clampi(
		max_recoveries, 0, PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES)
	var binding := _player_observation_exact_party_presence_bindings(current)
	checks.append(binding.duplicate(true))
	for recovery_index in range(recovery_limit):
		if bool(binding.get("valid", false)):
			break
		var before_recovery := current.duplicate(true)
		var receipt_v: Variant = await _drive_observed_camera_recovery(
			driver, recovery_index)
		var receipt := receipt_v as Dictionary \
			if receipt_v is Dictionary else {}
		recovery_receipts.append(receipt.duplicate(true))
		var observation_v: Variant = _player_observation_snapshot(
			observer, watchdog)
		current = observation_v as Dictionary \
			if observation_v is Dictionary else {}
		validation_party_body_probes.append(
			_player_observation_validation_party_probe(observer))
		recovery_steps.append({
			"recovery_index": recovery_index,
			"receipt": receipt.duplicate(true),
			"before": before_recovery,
			"after": current.duplicate(true),
		})
		binding = _player_observation_exact_party_presence_bindings(current)
		checks.append(binding.duplicate(true))

	var presentation_receipts_only := true
	for receipt_v in recovery_receipts:
		if not (receipt_v is Dictionary):
			presentation_receipts_only = false
			continue
		var receipt := receipt_v as Dictionary
		var kind := str(receipt.get("kind", ""))
		var keycode := int(receipt.get("keycode", 0))
		presentation_receipts_only = presentation_receipts_only \
			and bool(receipt.get("accepted", false)) \
			and bool(receipt.get("player_reproducible", false)) \
			and bool(receipt.get("input_issued", false)) \
			and (kind in ["recenter", "zoom_out", "rotate_camera"] \
				or (kind == "key" and keycode in [KEY_W, KEY_A, KEY_S, KEY_D]))
	var world_input_count_after := _player_discovery_world_input_count(driver)
	var no_world_input_during_recovery := \
		world_input_count_after == world_input_count_before
	var exact_presence_bindings := bool(binding.get("valid", false))
	var valid := exact_presence_bindings and presentation_receipts_only \
		and no_world_input_during_recovery
	var failure_reason := ""
	if not exact_presence_bindings:
		failure_reason = "missing_exact_party_presence_bindings_before_world_input"
	elif not presentation_receipts_only:
		failure_reason = "party_binding_recovery_used_nonpresentation_input"
	elif not no_world_input_during_recovery:
		failure_reason = "world_input_issued_during_party_binding_recovery"
	return {
		"contract": "generated_party_presence_binding_precondition_v2",
		"context": context,
		"valid": valid,
		"recovered": valid and not recovery_receipts.is_empty(),
		"failure_reason": failure_reason,
		"binding": binding.duplicate(true),
		"checks": checks,
		"recovery_receipts": recovery_receipts,
		"recovery_steps": recovery_steps,
		"recovery_count": recovery_receipts.size(),
		"recovery_limit": recovery_limit,
		"presentation_receipts_only": presentation_receipts_only,
		"world_input_count_before": world_input_count_before,
		"world_input_count_after": world_input_count_after,
		"no_world_input_during_recovery": no_world_input_during_recovery,
		"zero_world_inputs_at_gate": world_input_count_after == 0,
		"validation_party_body_probes": validation_party_body_probes,
		"validation_world_action_history": validation_world_action_history,
		"observation": current,
	}


func _record_player_binding_failure(
		report: Dictionary, gate: Dictionary
	) -> void:
	# Validation-only summary of what each human camera gesture actually exposed.
	# Persona policy never receives this: it is retained solely so a failed
	# Windowed gate identifies the useful angle/body binding instead of reporting
	# only the final exhausted view.
	var recovery_binding_diagnostics: Array = []
	var checks := gate.get("checks", []) as Array
	var receipts := gate.get("recovery_receipts", []) as Array
	for check_index in range(checks.size()):
		var check_v: Variant = checks[check_index]
		if not (check_v is Dictionary):
			continue
		var check := check_v as Dictionary
		var diagnostic := {
			"check_index": check_index,
			"valid": bool(check.get("valid", false)),
			"body_screens": (check.get("body_screens", {}) as Dictionary).duplicate(true),
			"issues": (check.get("issues", []) as Array).duplicate(true),
		}
		if check_index > 0 and check_index - 1 < receipts.size() \
				and receipts[check_index - 1] is Dictionary:
			var receipt := receipts[check_index - 1] as Dictionary
			diagnostic["gesture"] = {
				"kind": str(receipt.get("kind", "")),
				"direction": str(receipt.get("direction", "")),
				"keycode": int(receipt.get("keycode", 0)),
				"hold_seconds": float(receipt.get("hold_seconds", 0.0)),
			}
		recovery_binding_diagnostics.append(diagnostic)
	var failure := {
		"failure": str(gate.get(
			"failure_reason",
			"missing_exact_party_presence_bindings_before_world_input")),
		"context": str(gate.get("context", "")),
		"binding": (gate.get("binding", {}) as Dictionary).duplicate(true),
		"recovery_count": int(gate.get("recovery_count", 0)),
		"recovery_limit": int(gate.get("recovery_limit", 0)),
		"presentation_receipts_only": bool(gate.get(
			"presentation_receipts_only", false)),
		"world_input_count_before": int(gate.get("world_input_count_before", 0)),
		"world_input_count_after": int(gate.get("world_input_count_after", 0)),
		"no_world_input_during_recovery": bool(gate.get(
			"no_world_input_during_recovery", false)),
		"zero_world_inputs_at_gate": bool(gate.get(
			"zero_world_inputs_at_gate", false)),
		"recovery_binding_diagnostics": recovery_binding_diagnostics,
		"validation_party_body_probes": (
			gate.get("validation_party_body_probes", []) as Array).duplicate(true),
		"validation_world_action_history": (
			gate.get("validation_world_action_history", []) as Array).duplicate(true),
	}
	(report["party_binding_failures"] as Array).append(failure.duplicate(true))
	(report["interaction_failures"] as Array).append(failure.duplicate(true))
	report["abort_reason"] = str(failure["failure"])


func _record_player_binding_recovery_decisions(
		report: Dictionary, gate: Dictionary
	) -> int:
	var recorded := 0
	for step_v in gate.get("recovery_steps", []):
		if not (step_v is Dictionary):
			continue
		var step := step_v as Dictionary
		var before_v: Variant = step.get("before", {})
		var after_v: Variant = step.get("after", {})
		var receipt_v: Variant = step.get("receipt", {})
		if not (before_v is Dictionary) or not (after_v is Dictionary) \
				or not (receipt_v is Dictionary):
			continue
		var receipt := receipt_v as Dictionary
		var kind := str(receipt.get("kind", "camera_recovery"))
		var semantic_verb := _generated_camera_recovery_verb(receipt)
		var target_token := "camera_pan" if kind == "key" \
			else ("camera_zoom_out" if kind == "zoom_out" \
			else ("camera_rotate" if kind == "rotate_camera" else "camera_center"))
		_append_visible_decision_record(
			report,
			before_v as Dictionary,
			"A visible portrait has neither its exact visible body nor a rendered HIDDEN cue, so recover framing with a shipped presentation control before choosing any gameplay action.",
			["require_exact_party_presence_bindings", "camera_recovery_only"],
			{
				"verb": semantic_verb,
				"kind": kind,
				"target_token": target_token,
				"recovery_index": int(step.get("recovery_index", -1)),
			},
			receipt,
			after_v as Dictionary,
			false,
			[]
		)
		recorded += 1
	return recorded


func _drive_visible_player_discovery(
	preview_instance: Node,
	driver: Node,
	observer: Node,
	result: Dictionary,
	options: Dictionary,
	phase: String,
	policy: String,
	evidence_baseline_id: String
) -> Dictionary:
	var report := {
		"path_id": phase,
		"observation_schema": PLAYER_DISCOVERY_OBSERVATION_SCHEMA,
		"observation_source": "player_observable",
		"observation_samples": [],
		"visited_nodes": [],
		"visible_decisions": [],
		"presentation_only_decisions": [],
		"decision_trace_schema": GENERATED_STRATEGY_TRACE_SCHEMA,
		"decision_trace_records": [],
		"decision_trace_baseline_id": "",
		"persona_tree_ineligible_reason": "unnamed_strategy_not_persona",
		"watchdog_contract": {},
		"watchdog_heartbeats": [],
		"watchdog_failures": [],
		"watchdog_input_release": {},
		"decision_trace_chain_tail": "",
		"decision_trace_failures": [],
		"decision_trace_complete": false,
		"route_choices": 0,
		"movement_commands": 0,
		"rally_gestures": 0,
		"atomic_rally_failures": [],
		"party_binding_preconditions": [],
		"party_binding_failures": [],
		"initial_party_binding_precondition": {},
		"max_path_points": 0,
		"used_multi_y_path": false,
		"physical_interactions": 0,
		"refused_actions": [],
		"interaction_failures": [],
		"solution_action_failures": [],
		"risk_surface_attempted": false,
	}
	var attempted_epoch := {}
	var approached_epoch := {}
	var approach_ground_by_surface := {}
	var completed_tokens := {}
	var completed_semantics := {}
	var retryable_tokens := {}
	var attempt_counts := {}
	var stalled_ground := {}
	var ground_projection_signature := ""
	var hover_rebind_churn := 0
	var epoch := 0
	var decisions := 0
	var visible_outcome_reached := false
	var camera_recoveries := 0
	var watchdog := _new_player_discovery_watchdog(options, phase)
	report["watchdog_contract"] = _player_discovery_watchdog_report(watchdog)
	var decision_limit := maxi(
		1, int(options.get("player_discovery_max_decisions", PLAYER_DISCOVERY_MAX_DECISIONS))
	)
	var party_binding_recovery_limit := clampi(int(options.get(
		"player_discovery_party_binding_recoveries",
		PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES)),
		0, PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES)
	_initialize_generated_strategy_trace(
		report, result, phase, policy, evidence_baseline_id)
	_emit_player_discovery_heartbeat(report, watchdog, decisions, "initial_observation")
	# No shipped action may precede the observation that explains it. This first
	# snapshot is also the exact basis recorded for any visible RUN decision.
	var initial_observation_v: Variant = _player_observation_snapshot(
		observer, watchdog)
	if not (initial_observation_v is Dictionary):
		(report["interaction_failures"] as Array).append({
			"failure": "missing_initial_player_observation",
		})
		report["policy_iteration_count"] = decisions
		report["decision_count"] = (report["visible_decisions"] as Array).size()
		report["visible_outcome_reached"] = false
		_finish_generated_strategy_trace(report, false)
		return report
	var initial_observation := initial_observation_v as Dictionary
	var initial_observation_issues: Array[String] = \
		PersonaDecisionTraceScript.validate_player_observation(initial_observation)
	if not initial_observation_issues.is_empty():
		(report["interaction_failures"] as Array).append({
			"failure": "invalid_initial_player_observation_boundary",
			"issues": initial_observation_issues.duplicate(),
		})
		report["policy_iteration_count"] = decisions
		report["decision_count"] = (report["visible_decisions"] as Array).size()
		report["visible_outcome_reached"] = false
		_finish_generated_strategy_trace(report, false)
		return report
	var initial_binding_gate := await _require_player_observation_party_bindings(
		driver,
		observer,
		initial_observation,
		"initial_before_world_input",
		party_binding_recovery_limit,
		watchdog
	)
	var initial_binding_record := _player_discovery_binding_gate_record(
		initial_binding_gate)
	report["initial_party_binding_precondition"] = \
		initial_binding_record.duplicate(true)
	(report["party_binding_preconditions"] as Array).append(
		initial_binding_record.duplicate(true))
	decisions += _record_player_binding_recovery_decisions(
		report, initial_binding_gate)
	if not bool(initial_binding_gate.get("valid", false)):
		_record_player_binding_failure(report, initial_binding_gate)
		report["policy_iteration_count"] = decisions
		report["decision_count"] = (report["visible_decisions"] as Array).size()
		report["visible_outcome_reached"] = false
		_finish_generated_strategy_trace(report, false)
		return report
	var bound_initial_observation_v: Variant = initial_binding_gate.get(
		"observation", {})
	if not (bound_initial_observation_v is Dictionary):
		_record_player_binding_failure(report, {
			"failure_reason": "missing_exact_party_presence_bindings_before_world_input",
			"context": "initial_before_world_input",
			"binding": {},
			"recovery_count": int(initial_binding_gate.get("recovery_count", 0)),
			"recovery_limit": party_binding_recovery_limit,
			"presentation_receipts_only": bool(initial_binding_gate.get(
				"presentation_receipts_only", false)),
			"world_input_count_before": int(initial_binding_gate.get(
				"world_input_count_before", 0)),
			"world_input_count_after": int(initial_binding_gate.get(
				"world_input_count_after", 0)),
			"no_world_input_during_recovery": bool(initial_binding_gate.get(
				"no_world_input_during_recovery", false)),
			"zero_world_inputs_at_gate": bool(initial_binding_gate.get(
				"zero_world_inputs_at_gate", false)),
		})
		report["policy_iteration_count"] = decisions
		report["decision_count"] = (report["visible_decisions"] as Array).size()
		report["visible_outcome_reached"] = false
		_finish_generated_strategy_trace(report, false)
		return report
	initial_observation = bound_initial_observation_v as Dictionary
	ground_projection_signature = _player_observation_projection_signature(
		initial_observation)
	(report["observation_samples"] as Array).append(
		_player_observation_digest(initial_observation)
	)
	# Long generated routes are execution once their visible destination has been
	# chosen. A person can use the shipped RUN control to avoid spending the
	# evidence window repeating that solved traversal, so both discovery
	# strategies do the same through ordinary party selection + R input. Keep the
	# decision gated by the HUD label: an unavailable or unpresented control is not
	# valid player evidence.
	if _player_discovery_should_enable_visible_run(policy, initial_observation):
		var run_receipt_v: Variant = await driver.call("set_party_running", true)
		var run_receipt := (
			run_receipt_v as Dictionary if run_receipt_v is Dictionary else {}
		)
		var run_after_v: Variant = _player_observation_snapshot(
			observer, watchdog)
		var run_after := run_after_v as Dictionary \
			if run_after_v is Dictionary else {}
		if run_after.is_empty():
			(report["interaction_failures"] as Array).append({
				"failure": "missing_post_run_player_observation",
			})
		if bool(run_receipt.get("input_issued", false)):
			_consider_player_discovery_observation_progress(
				watchdog, initial_observation, run_after,
				"run_mode_visible_change")
			var run_rationale := (
				"Scarcity pressure favors the visible RUN mode before route discovery."
				if policy == "risk_seeking"
				else "The visible RUN mode reduces repetitive traversal while preserving the same route decision."
			)
			var run_decision_nodes := (
				["risk_seeking", "enable_run_from_visible_hud"]
				if policy == "risk_seeking"
				else ["first_read", "reduce_repetitive_execution_with_visible_run"]
			)
			_append_visible_decision_record(
				report,
				initial_observation,
				run_rationale,
				run_decision_nodes,
				{
					"verb": "toggle_run",
					"kind": "set_party_running",
					"desired": true,
				},
				run_receipt,
				run_after,
				false,
				_player_party_ids_from_observation(initial_observation)
			)
			decisions += 1
	while decisions < decision_limit and not visible_outcome_reached:
		report["policy_iteration_count"] = decisions
		_emit_player_discovery_heartbeat(report, watchdog, decisions, "choose_action")
		var watchdog_abort_reason := _player_discovery_watchdog_abort_reason(
			watchdog)
		if watchdog_abort_reason != "":
			await _abort_player_discovery_for_watchdog(
				driver, report, watchdog, watchdog_abort_reason)
			break
		var observation_v: Variant = _player_observation_snapshot(
			observer, watchdog)
		if not (observation_v is Dictionary):
			(report["interaction_failures"] as Array).append({
				"failure": "missing_player_observation",
			})
			break
		var observation := observation_v as Dictionary
		if _player_observation_reads_as_success(observation):
			visible_outcome_reached = true
			break
		var observation_issues: Array[String] = \
			PersonaDecisionTraceScript.validate_player_observation(observation)
		if not observation_issues.is_empty():
			(report["interaction_failures"] as Array).append({
				"failure": "invalid_player_observation_boundary",
				"schema": str(observation.get("schema", "")),
				"source": str(observation.get("source", "")),
				"issues": observation_issues.duplicate(),
			})
			break
		var iteration_binding_gate := await _require_player_observation_party_bindings(
			driver,
			observer,
			observation,
			"decision_%d_before_world_input" % decisions,
			party_binding_recovery_limit,
			watchdog
		)
		var iteration_binding_record := _player_discovery_binding_gate_record(
			iteration_binding_gate)
		(report["party_binding_preconditions"] as Array).append(
			iteration_binding_record.duplicate(true))
		decisions += _record_player_binding_recovery_decisions(
			report, iteration_binding_gate)
		if not bool(iteration_binding_gate.get("valid", false)):
			_record_player_binding_failure(report, iteration_binding_gate)
			break
		if decisions >= decision_limit:
			break
		var bound_observation_v: Variant = iteration_binding_gate.get(
			"observation", {})
		if not (bound_observation_v is Dictionary):
			_record_player_binding_failure(report, {
				"failure_reason": "missing_exact_party_presence_bindings_before_world_input",
				"context": "decision_%d_before_world_input" % decisions,
				"binding": {},
				"recovery_count": int(iteration_binding_gate.get(
					"recovery_count", 0)),
				"recovery_limit": party_binding_recovery_limit,
				"presentation_receipts_only": bool(iteration_binding_gate.get(
					"presentation_receipts_only", false)),
				"world_input_count_before": int(iteration_binding_gate.get(
					"world_input_count_before", 0)),
				"world_input_count_after": int(iteration_binding_gate.get(
					"world_input_count_after", 0)),
				"no_world_input_during_recovery": bool(iteration_binding_gate.get(
					"no_world_input_during_recovery", false)),
				"zero_world_inputs_at_gate": bool(iteration_binding_gate.get(
					"zero_world_inputs_at_gate", false)),
			})
			break
		observation = bound_observation_v as Dictionary
		var current_projection_signature := \
			_player_observation_projection_signature(observation)
		if ground_projection_signature != "" \
				and current_projection_signature != ground_projection_signature:
			# Ground tokens name fixed screen bins, not durable world locations. Any
			# publicly visible projection change invalidates only screen-bin memory;
			# stable interaction presenter tokens and solved semantics remain valid.
			stalled_ground.clear()
			approach_ground_by_surface.clear()
		ground_projection_signature = current_projection_signature
		(report["observation_samples"] as Array).append(
			_player_observation_digest(observation)
		)
		if _player_observation_reads_as_success(observation):
			visible_outcome_reached = true
			break

		var surface := _choose_observed_interaction(
			observation,
			policy,
			attempted_epoch,
			completed_tokens,
			completed_semantics,
			retryable_tokens,
			attempt_counts,
			epoch
		)
		if surface.is_empty():
			var frontier := _choose_observed_frontier_ground(
				observation, stalled_ground, decisions
			)
			if not frontier.is_empty():
				decisions += 1
				var frontier_result := await _drive_observed_rally(
					preview_instance,
					driver,
					observer,
					observation,
					frontier,
					report,
					result,
					phase,
					"visible route frontier",
					watchdog
				)
				var frontier_key := str(frontier.get("token", ""))
				if bool(frontier_result.get("hover_rebind_failed", false)):
					hover_rebind_churn += 1
					stalled_ground.clear()
					if hover_rebind_churn >= \
							PLAYER_DISCOVERY_MAX_HOVER_REBIND_CHURN:
						_set_player_discovery_watchdog_pending(
							watchdog, "rally_hover_rebind_churn_limit")
				elif bool(frontier_result.get("accepted", false)) \
						and int(frontier_result.get("sample_count", 0)) > 0:
					hover_rebind_churn = 0
					stalled_ground.clear()
					camera_recoveries = 0
				else:
					hover_rebind_churn = 0
					stalled_ground[frontier_key] = true
				continue
			if camera_recoveries >= PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES:
				break
			decisions += 1
			var camera_receipt := await _drive_observed_camera_recovery(
				driver, camera_recoveries
			)
			var camera_after_v: Variant = _player_observation_snapshot(
				observer, watchdog)
			var camera_after := camera_after_v as Dictionary \
				if camera_after_v is Dictionary else {}
			if camera_after.is_empty():
				(report["interaction_failures"] as Array).append({
					"failure": "missing_post_camera_player_observation",
				})
			if bool(camera_receipt.get("accepted", false)):
				_consider_player_discovery_observation_progress(
					watchdog, observation, camera_after,
					"camera_control_visible_change")
			_append_visible_decision_record(
				report,
				observation,
				"No safe visible target remains, so reframe using a shipped camera control.",
				["visible_frontier_exhausted", "camera_recovery"],
				{
					"verb": _generated_camera_recovery_verb(camera_receipt),
					"kind": str(camera_receipt.get("kind", "camera_recovery")),
				},
				camera_receipt,
				camera_after,
				false,
				[]
			)
			# A shipped camera action starts a new public projection. Screen-bin
			# ground memory cannot cross it, even if the first post-key frame has not
			# yet exposed the full easing motion.
			stalled_ground.clear()
			approach_ground_by_surface.clear()
			ground_projection_signature = \
				_player_observation_projection_signature(camera_after)
			hover_rebind_churn = 0
			camera_recoveries += 1
			continue

		var surface_token := str(surface.get("token", ""))
		var visible_label := str(surface.get("verb", "INTERACT"))
		var follows_visible_resolve_cue := bool(surface.get(
			"resolves_visible_cue", false))
		var visible_copy := (
			visible_label + " " + str(surface.get("consequence", ""))
		).to_lower()
		if _player_visible_risk_score(visible_copy) > 0:
			report["risk_surface_attempted"] = true
		if int(approached_epoch.get(surface_token, -1)) != epoch:
			var approach := _choose_observed_ground_near_interaction(
				observation,
				surface,
				int(attempt_counts.get(surface_token, 0)),
				stalled_ground
			)
			if approach.is_empty():
				# A visible interaction is not permission to click it from arbitrary
				# range. Reframe through the same shipped camera controls a human uses
				# and re-observe until a playable floor approach exists.
				if camera_recoveries >= PLAYER_DISCOVERY_MAX_CAMERA_RECOVERIES:
					(report["interaction_failures"] as Array).append({
						"failure": "no_visible_unstalled_interaction_approach",
						"target_token": surface_token,
						"surface": visible_label,
					})
					break
				decisions += 1
				var camera_receipt := await _drive_observed_camera_recovery(
					driver, camera_recoveries
				)
				var camera_after_v: Variant = _player_observation_snapshot(
					observer, watchdog)
				var camera_after := camera_after_v as Dictionary \
					if camera_after_v is Dictionary else {}
				if camera_after.is_empty():
					(report["interaction_failures"] as Array).append({
						"failure": "missing_post_approach_camera_observation",
						"target_token": surface_token,
					})
				if bool(camera_receipt.get("accepted", false)):
					_consider_player_discovery_observation_progress(
						watchdog, observation, camera_after,
						"interaction_approach_camera_visible_change")
				_append_visible_decision_record(
					report,
					observation,
					"The visible interaction has no safe unstalled floor approach, so reframe before acting.",
					["visible_interaction", "approach_unavailable", "camera_recovery"],
					{
						"verb": _generated_camera_recovery_verb(camera_receipt),
						"kind": str(camera_receipt.get("kind", "camera_recovery")),
					},
					camera_receipt,
					camera_after,
					false,
					[]
				)
				stalled_ground.clear()
				approach_ground_by_surface.clear()
				ground_projection_signature = \
					_player_observation_projection_signature(camera_after)
				hover_rebind_churn = 0
				camera_recoveries += 1
				continue

			decisions += 1
			var approach_result := await _drive_observed_rally(
				preview_instance,
				driver,
				observer,
				observation,
				approach,
				report,
				result,
				phase,
				visible_label,
				watchdog
			)
			var approach_token := str(approach.get("token", ""))
			if bool(approach_result.get("hover_rebind_failed", false)):
				hover_rebind_churn += 1
				stalled_ground.clear()
				approach_ground_by_surface.erase(surface_token)
				if hover_rebind_churn >= \
						PLAYER_DISCOVERY_MAX_HOVER_REBIND_CHURN:
					_set_player_discovery_watchdog_pending(
						watchdog, "rally_hover_rebind_churn_limit")
			elif bool(approach_result.get("accepted", false)) \
					and bool(approach_result.get(
						"visible_motion_verified", false)) \
					and int(approach_result.get("sample_count", 0)) > 0:
				hover_rebind_churn = 0
				# Approach memory commits only after the exact visible Rally lineage
				# reaches ARRIVAL and every intended body/transform has settled.
				approached_epoch[surface_token] = epoch
				approach_ground_by_surface[surface_token] = approach_token
				stalled_ground.clear()
				camera_recoveries = 0
			elif approach_token != "":
				hover_rebind_churn = 0
				stalled_ground[approach_token] = true
				approached_epoch.erase(surface_token)
				approach_ground_by_surface.erase(surface_token)
			continue

		decisions += 1
		var semantic_key := _player_observation_surface_semantic_key(surface)
		var requires_party_selection := _player_surface_requires_party_selection(
			visible_copy
		)
		var before_visible_signature := _player_observation_visible_signature(
			observation
		)
		var point := _player_observation_screen_point(surface)
		var interaction_attempts: Array = []
		var interaction_accepted := false
		var after_observation := observation
		var visible_revalidation_failure := false
		var reobserve_before_world_input := false
		var world_interaction_attempt_committed := false
		if requires_party_selection:
			var party_selection_before := observation
			var party_selection_v: Variant = await driver.call("select_party")
			var party_selection := (
				party_selection_v as Dictionary
				if party_selection_v is Dictionary
				else {}
			)
			var party_selected_observation_v: Variant = _player_observation_snapshot(
				observer, watchdog)
			var party_selected_observation := party_selected_observation_v as Dictionary \
				if party_selected_observation_v is Dictionary else {}
			if party_selected_observation.is_empty():
				(report["interaction_failures"] as Array).append({
					"failure": "missing_post_party_selection_observation",
				})
			if bool(party_selection.get("input_issued", false)):
				_consider_player_discovery_observation_progress(
					watchdog, party_selection_before,
					party_selected_observation,
					"party_selection_visible_change")
				_append_visible_decision_record(
					report,
					party_selection_before,
					"The visible interaction announces a whole-party requirement.",
					["visible_party_requirement", "select_all_portraits"],
					{
						"verb": "select_party",
						"kind": "select_party_for_interaction",
						"surface": visible_label,
					},
					party_selection,
					party_selected_observation,
					false,
					_player_party_ids_from_observation(party_selection_before)
				)
			if not bool(party_selection.get("accepted", false)):
				(interaction_attempts as Array).append(
					party_selection.duplicate(true)
				)
			else:
				observation = party_selected_observation
				after_observation = observation
				var selected_surface := _observed_affordance_by_token(
					observation, surface_token
				)
				if selected_surface.is_empty() or not _player_observation_safe_action_point(
					observation,
					_player_observation_screen_point(selected_surface)
				):
					visible_revalidation_failure = true
					reobserve_before_world_input = true
					(interaction_attempts as Array).append({
						"kind": "visible_target_revalidation",
						"accepted": false,
						"reason": "The selected visible target moved out of the safe action area.",
						"player_observable_feedback": true,
					})
				else:
					surface = selected_surface
					point = _player_observation_screen_point(surface)
					before_visible_signature = \
						_player_observation_visible_signature(observation)

		for actor in _observed_interaction_actor_order(
			visible_label, str(surface.get("consequence", "")),
			_player_party_ids_from_observation(observation)
		):
			if _player_discovery_watchdog_abort_reason(watchdog) != "" \
					or visible_revalidation_failure \
					or (requires_party_selection and interaction_attempts.size() > 0):
				break
			if not requires_party_selection:
				var actor_selection_before := observation
				var actor_selection_v: Variant = await driver.call(
					"select_single", actor
				)
				var actor_selection := (
					actor_selection_v as Dictionary
					if actor_selection_v is Dictionary
					else {}
				)
				var actor_selected_observation_v: Variant = \
					_player_observation_snapshot(observer, watchdog)
				var actor_selected_observation := actor_selected_observation_v as Dictionary \
					if actor_selected_observation_v is Dictionary else {}
				if actor_selected_observation.is_empty():
					(report["interaction_failures"] as Array).append({
						"failure": "missing_post_single_selection_observation",
						"member": actor,
					})
				if bool(actor_selection.get("input_issued", false)):
					_consider_player_discovery_observation_progress(
						watchdog, actor_selection_before,
						actor_selected_observation,
						"portrait_selection_visible_change")
					_append_visible_decision_record(
						report,
						actor_selection_before,
						"Try the visible interaction with the next plausible portrait.",
						["visible_interaction", "portrait_actor_order"],
						{
							"verb": "select_single",
							"kind": "select_character_for_interaction",
							"surface": visible_label,
							"portrait_label": str(actor).capitalize(),
						},
						actor_selection,
						actor_selected_observation,
						false,
						[actor]
					)
				observation = actor_selected_observation
				after_observation = observation
				if not bool(actor_selection.get("accepted", false)):
					(interaction_attempts as Array).append(
						actor_selection.duplicate(true)
					)
					continue
			var stable_target := await _await_observed_affordance_action_stability(
				observer, surface_token, observation, watchdog)
			if not stable_target.is_empty():
				observation = stable_target.get("observation", {}) as Dictionary
				after_observation = observation
			var refreshed_before_click := (
				stable_target.get("affordance", {}) as Dictionary
				if not stable_target.is_empty() else {}
			)
			if refreshed_before_click.is_empty() or not \
					_player_observation_safe_action_point(
						observation,
						_player_observation_screen_point(refreshed_before_click)
					):
				visible_revalidation_failure = true
				reobserve_before_world_input = true
				(interaction_attempts as Array).append({
					"kind": "visible_target_revalidation",
					"accepted": false,
					"reason": "The selected visible target moved out of the safe action area.",
					"player_observable_feedback": true,
				})
				break
			var hover_rebind := await _hover_and_rebind_observed_affordance(
				driver,
				observer,
				observation,
				refreshed_before_click,
				watchdog
			)
			if not bool(hover_rebind.get("valid", false)):
				visible_revalidation_failure = true
				reobserve_before_world_input = true
				after_observation = hover_rebind.get(
					"observation", observation) as Dictionary
				var hover_failure_receipt := hover_rebind.get(
					"hover_receipt", {}) as Dictionary
				hover_failure_receipt["hover_rebind_reason"] = str(
					hover_rebind.get("reason", "visible_target_rebind_failed"))
				hover_failure_receipt["hover_rebind_diagnostic"] = (
					hover_rebind.get("rebind_diagnostic", {}) as Dictionary
				).duplicate(true)
				hover_failure_receipt["hover_rebind_frame_path"] = str(
					hover_rebind.get("rebind_frame_path", ""))
				(interaction_attempts as Array).append(
					hover_failure_receipt.duplicate(true))
				var hover_failure_ordered := _record_observed_hover_rebind_failure(
					report,
					observation,
					after_observation,
					hover_failure_receipt,
					refreshed_before_click,
					"interact",
					visible_label,
					str(hover_rebind.get("reason", "visible_target_rebind_failed"))
				)
				if not hover_failure_ordered:
					_set_player_discovery_watchdog_pending(
						watchdog, "hover_input_could_not_be_ordered")
				else:
					hover_rebind_churn += 1
				if hover_rebind_churn >= \
						PLAYER_DISCOVERY_MAX_HOVER_REBIND_CHURN:
					_set_player_discovery_watchdog_pending(
						watchdog, "interaction_hover_rebind_churn_limit")
				break
			observation = hover_rebind.get("observation", {}) as Dictionary
			after_observation = observation
			surface = hover_rebind.get("affordance", {}) as Dictionary
			point = hover_rebind.get("point", Vector2.INF)
			var hover_receipt := hover_rebind.get(
				"hover_receipt", {}) as Dictionary
			before_visible_signature = _player_observation_visible_signature(
				observation
			)
			var before_target_result := _player_observation_target_result(
				observation, surface_token
			)
			var before_target_serial := int(
				before_target_result.get("presentation_serial", 0)
			)
			var interaction_receipt_v: Variant = await driver.call(
				"interact_selected_screen_from_rendered_hover",
				actor,
				point,
				surface_token
			)
			var interaction_receipt := (
				interaction_receipt_v as Dictionary
				if interaction_receipt_v is Dictionary
				else {}
			)
			if bool(interaction_receipt.get("input_issued", false)) \
					and not world_interaction_attempt_committed:
				# Selection and hover are separate presentation inputs. Commit semantic
				# attempt memory only once the ordinary RMB world edge was actually
				# delivered; stale-hover replans must not consume the durable aff_* intent.
				attempted_epoch[surface_token] = epoch
				attempt_counts[surface_token] = int(
					attempt_counts.get(surface_token, 0)) + 1
				world_interaction_attempt_committed = true
				hover_rebind_churn = 0
			interaction_receipt["pointer_hover_receipt"] = \
				hover_receipt.duplicate(true)
			interaction_receipt["pointer_hover_rebound"] = true
			interaction_receipt["rendered_hover_rebind_capture_serial"] = int(
				observation.get("capture_serial", 0))
			interaction_receipt["rendered_hover_decision_capture_serial"] = int(
				hover_rebind.get("decision_capture_serial", 0))
			interaction_receipt["target_token"] = surface_token
			interaction_receipt["target_screen"] = [point.x, point.y]
			interaction_receipt = _merge_generated_auxiliary_input_receipts(
				interaction_receipt)
			# Capture the first freshly rendered state before any settle wait. A short
			# exact-target pulse may otherwise begin and expire between samples.
			var immediate_observation_v: Variant = _player_observation_snapshot(
				observer, watchdog)
			var immediate_observation := immediate_observation_v as Dictionary \
				if immediate_observation_v is Dictionary else {}
			if immediate_observation.is_empty():
				(report["interaction_failures"] as Array).append({
					"failure": "missing_immediate_post_interaction_observation",
					"target_token": surface_token,
				})
			elif PersonaDecisionTraceScript.validate_player_observation(
					immediate_observation).is_empty():
				_consider_player_discovery_observation_progress(
					watchdog, observation, immediate_observation,
					"interaction_immediate_visible_change")
			# Clicking near an edge leaves the real pointer in the shipped edge-pan
			# band. Park it with an ordinary MouseMotion while the routed interaction
			# completes so the exact target/result is not silently panned away.
			if bool(interaction_receipt.get("input_issued", false)) \
					and driver.has_method("park_pointer"):
				var park_receipt_v: Variant = await driver.call("park_pointer")
				var park_receipt := park_receipt_v as Dictionary \
					if park_receipt_v is Dictionary else {}
				interaction_receipt["pointer_park_receipt"] = \
					park_receipt.duplicate(true)
				interaction_receipt["pointer_parked_after_click"] = bool(
					park_receipt.get("accepted", false)) \
					and bool(park_receipt.get("input_issued", false))
				interaction_receipt = _merge_generated_auxiliary_input_receipts(
					interaction_receipt)
			report["physical_interactions"] = int(
				report["physical_interactions"]
			) + 1
			var observed_feedback := await _wait_for_observed_interaction_feedback(
				preview_instance,
				observer,
				observation,
				result,
				phase,
				visible_label,
				surface_token,
				before_target_serial,
				report,
				watchdog,
				immediate_observation
			)
			var feedback_observation_v: Variant = (
				observed_feedback as Dictionary).get("observation", null)
			if feedback_observation_v is Dictionary:
				after_observation = feedback_observation_v as Dictionary
			else:
				after_observation = {}
				(report["interaction_failures"] as Array).append({
					"failure": "missing_post_interaction_observation",
					"target_token": surface_token,
				})
			var target_result: Dictionary = (observed_feedback as Dictionary).get(
				"target_result", {}
			)
			var interaction_observation_samples: Array = (
				(observed_feedback as Dictionary).get(
					"observation_samples", []) as Array
			).duplicate(true)
			var visible_feedback := _player_observation_feedback_text(
				after_observation
			)
			var visible_change := _player_observation_visible_signature(
				after_observation
			) != before_visible_signature
			var target_success := _target_result_is_new_visible_success(
				target_result, surface_token, before_target_serial)
			if driver.has_method("finalize_interaction_receipt"):
				interaction_receipt = driver.call(
					"finalize_interaction_receipt",
					interaction_receipt,
					target_result,
					visible_feedback if not target_success else "",
					surface_token,
					before_target_serial
				)
			var accepted_after_feedback := bool(
				interaction_receipt.get("accepted", false)) and target_success
			interaction_receipt["visible_feedback_after_settle"] = visible_feedback
			interaction_receipt["target_token"] = surface_token
			interaction_receipt["target_screen"] = [point.x, point.y]
			(interaction_attempts as Array).append(
				interaction_receipt.duplicate(true)
			)
			var interaction_policy_nodes := [
				"visible_interaction",
				"target_revalidated",
				"await_exact_result_pulse",
			]
			if follows_visible_resolve_cue:
				interaction_policy_nodes.append("follow_visible_resolve_first_cue")
			_append_visible_decision_record(
				report,
				observation,
				"Activate the exact visible target after revalidating its current pointer pixel.",
				interaction_policy_nodes,
				{
					"verb": "interact",
					"kind": "interact",
					"target_token": surface_token,
					"screen": surface.get("screen", []).duplicate(),
					"surface": visible_label,
					"visible_change": visible_change,
				},
				interaction_receipt,
				after_observation,
				true,
				[actor],
				interaction_observation_samples
			)
			if _player_discovery_watchdog_abort_reason(watchdog) != "":
				break
			if accepted_after_feedback:
				interaction_accepted = true
				break
			# A visible refusal may identify a different required character. Re-read
			# the same still-visible affordance before the next portrait tries it.
			var refreshed := _observed_affordance_by_token(
				after_observation, surface_token
			)
			if refreshed.is_empty():
				break
			surface = refreshed
			point = _player_observation_screen_point(surface)

		if reobserve_before_world_input and not world_interaction_attempt_committed:
			# A person who sees the target move or disappear before the click simply
			# looks again. No world refusal occurred, so do not fabricate one or retire
			# the stable interaction-presenter intent.
			continue

		var after_visible_signature := _player_observation_visible_signature(
			after_observation
		)
		var visible_change := after_visible_signature != before_visible_signature
		if interaction_accepted:
			completed_tokens[surface_token] = true
			approach_ground_by_surface.erase(surface_token)
			if semantic_key != "":
				completed_semantics[semantic_key] = true
			retryable_tokens.erase(surface_token)
			if _player_observation_reads_as_success(after_observation):
				visible_outcome_reached = true
			(report["visited_nodes"] as Array).append(visible_label)
			_append_report_event(
				report,
				phase,
				"node_activated",
				"Interacted with visible %s through shipped input" % visible_label,
				{
					"target_token": surface_token,
					"surface": visible_label,
					"visible_change": visible_change,
				}
			)
			if visible_change:
				epoch += 1
		else:
			var refusal_visible := visible_revalidation_failure
			var refusal_feedback := _player_observation_feedback_text(
				after_observation
			)
			for attempt_v in interaction_attempts:
				if not (attempt_v is Dictionary):
					continue
				var attempt := attempt_v as Dictionary
				refusal_visible = refusal_visible \
					or bool(attempt.get("player_observable_feedback", false)) \
					or _feedback_reads_as_refusal(str(attempt.get(
						"visible_feedback_after_settle", ""
					)))
			var can_reapproach := visible_revalidation_failure \
				or _feedback_requests_visible_reapproach(refusal_feedback)
			if can_reapproach and int(attempt_counts.get(
					surface_token, 0
				)) < PLAYER_DISCOVERY_MAX_VISIBLE_RETRIES:
				retryable_tokens[surface_token] = true
				var failed_approach_token := str(
					approach_ground_by_surface.get(surface_token, ""))
				if failed_approach_token != "":
					stalled_ground[failed_approach_token] = true
				approach_ground_by_surface.erase(surface_token)
				approached_epoch.erase(surface_token)
			else:
				retryable_tokens.erase(surface_token)
			var refusal_report := {
				"target_token": surface_token,
				"surface": visible_label,
				"failure": "player_facing_interaction_refused",
				"attempts": interaction_attempts,
				"player_observable_feedback": refusal_visible,
			}
			if refusal_visible:
				(report["refused_actions"] as Array).append(refusal_report)
			else:
				(refusal_report as Dictionary)["failure"] = "silent_interaction_refusal"
				(report["interaction_failures"] as Array).append(refusal_report)

	if not visible_outcome_reached and decisions >= decision_limit \
			and _player_discovery_watchdog_abort_reason(watchdog) == "":
		_set_player_discovery_watchdog_pending(
			watchdog, "player_discovery_decision_limit")
	var final_watchdog_abort_reason := _player_discovery_watchdog_abort_reason(
		watchdog)
	if final_watchdog_abort_reason != "" and not bool(watchdog.get(
			"aborted", false)):
		await _abort_player_discovery_for_watchdog(
			driver, report, watchdog, final_watchdog_abort_reason)
	report["policy_iteration_count"] = decisions
	report["decision_count"] = (report["visible_decisions"] as Array).size()
	report["visible_outcome_reached"] = visible_outcome_reached
	report["discovery_exhausted"] = decisions >= decision_limit \
		and not visible_outcome_reached
	report["watchdog_contract"] = _player_discovery_watchdog_report(watchdog)
	_finish_generated_strategy_trace(report, visible_outcome_reached)
	return report


## Generated first-read/risk-seeking policies are diagnostic strategies, not
## named personas. They still receive a complete provenance header and a
## hash-covered run/decision/summary chain so a future enrollment step can
## inspect or replay them without letting them silently enter the persona tree.
func _initialize_generated_strategy_trace(
		report: Dictionary,
		result: Dictionary,
		phase: String,
		policy: String,
		evidence_baseline_id: String
	) -> void:
	var spec_v: Variant = result.get("spec", {})
	var spec := spec_v as Dictionary if spec_v is Dictionary else {}
	var spec_id := str(result.get("spec_id", spec.get("id", "generated_stretch")))
	var seed := int((spec.get("source", {}) as Dictionary).get("seed", 0))
	var invocation_nonce := Time.get_ticks_usec() # @artifact_metadata_only
	var provenance_root := "%s:%s:%s:%d" % [
		spec_id, phase, policy, invocation_nonce,
	]
	var run_id := "%s:run" % provenance_root
	var trace_id := "%s:trace" % provenance_root
	var invocation_id := "%s:invocation" % provenance_root
	var run := {
		"run_id": run_id,
		"trace_id": trace_id,
		"invocation_id": invocation_id,
		"strategy_id": policy,
		"persona_id": "",
		"persona_enrollment": "not_enrolled",
		"fragment_id": spec_id,
		"generated_spec_id": spec_id,
		"seed": seed,
		"content_fingerprint": PersonaDecisionTraceScript.canonical_hash(spec),
		"execution_platform": "web" if OS.has_feature("web") else "native",
		"authored_state": "authored_spawn",
		"evidence_baseline_id": evidence_baseline_id,
	}
	report["decision_trace_expected_content_fingerprint"] = str(
		run["content_fingerprint"])
	report["decision_trace_baseline_id"] = evidence_baseline_id
	report["decision_trace_run"] = run.duplicate(true)
	report["decision_trace_records"] = []
	report["decision_trace_chain_tail"] = ""
	_append_generated_strategy_trace_record(report, {
		"schema": GENERATED_STRATEGY_TRACE_SCHEMA,
		"record_type": PersonaDecisionTraceScript.RUN_RECORD,
		"classification": "diagnostic_strategy_not_persona",
		"run": run,
	})


func _finish_generated_strategy_trace(
		report: Dictionary, visible_outcome_reached: bool
	) -> void:
	var decision_records := report.get("visible_decisions", []) as Array
	var completion_reasons: Array[String] = []
	var watchdog_abort_reasons: Array[String] = []
	for watchdog_failure_v in report.get("watchdog_failures", []):
		if not (watchdog_failure_v is Dictionary):
			continue
		var watchdog_reason := str(
			(watchdog_failure_v as Dictionary).get("reason", ""))
		if watchdog_reason != "" and not watchdog_abort_reasons.has(
				watchdog_reason):
			watchdog_abort_reasons.append(watchdog_reason)
	watchdog_abort_reasons.sort()
	if not visible_outcome_reached:
		completion_reasons.append("visible_goal_not_reached")
	if decision_records.is_empty():
		completion_reasons.append("no_player_decisions_recorded")
	if not (report.get("decision_trace_failures", []) as Array).is_empty():
		completion_reasons.append("decision_evidence_invalid")
	if not (report.get("interaction_failures", []) as Array).is_empty():
		completion_reasons.append("interaction_evidence_incomplete")
	if not (report.get("atomic_rally_failures", []) as Array).is_empty():
		completion_reasons.append("rally_evidence_incomplete")
	if not watchdog_abort_reasons.is_empty():
		completion_reasons.append("ci_watchdog_abort")
	if not _generated_rally_records_have_complete_motion(report, false):
		completion_reasons.append("all_member_motion_evidence_incomplete")
	completion_reasons.sort()
	var trace_complete := completion_reasons.is_empty()
	var summary := {
		"schema": GENERATED_STRATEGY_TRACE_SCHEMA,
		"record_type": PersonaDecisionTraceScript.SUMMARY_RECORD,
		"classification": "diagnostic_strategy_not_persona",
		"run": (report.get("decision_trace_run", {}) as Dictionary).duplicate(true),
		"decision_count": decision_records.size(),
		"summary": {
			"trace_complete": trace_complete,
			"visible_outcome_reached": visible_outcome_reached,
			"completion_reasons": completion_reasons,
			"watchdog_abort_reasons": watchdog_abort_reasons,
			"eligible_for_learning": false,
			"persona_tree_ineligible_reason": "unnamed_strategy_not_persona",
		},
	}
	_append_generated_strategy_trace_record(report, summary)
	report["decision_trace_complete"] = trace_complete


func _append_generated_strategy_trace_record(
		report: Dictionary, unhashed_record: Dictionary
	) -> Dictionary:
	var record := PersonaDecisionTraceScript.json_safe(unhashed_record) as Dictionary
	record["previous_hash"] = str(report.get("decision_trace_chain_tail", ""))
	var hash_payload := record.duplicate(true)
	hash_payload.erase("record_hash")
	record["record_hash"] = PersonaDecisionTraceScript.canonical_hash(hash_payload)
	report["decision_trace_chain_tail"] = str(record["record_hash"])
	var trace_records := report.get("decision_trace_records", []) as Array
	trace_records.append(record)
	report["decision_trace_records"] = trace_records
	return record


func _validate_player_surface_policy_evidence(report: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var records := report.get("decision_trace_records", []) as Array
	var visible_decisions := report.get("visible_decisions", []) as Array
	var expected_previous := ""
	var expected_decision_index := 0
	var validated_observation_decision_count := 0
	var saw_run := false
	var saw_summary := false
	var run_identity: Dictionary = {}
	var summary_trace_complete := false
	var receipt_ids := {}
	var prior_trace_decisions: Array[Dictionary] = []
	for record_v in records:
		if not (record_v is Dictionary):
			failures.append("trace_record_not_object")
			continue
		var record := record_v as Dictionary
		if str(record.get("schema", "")) != GENERATED_STRATEGY_TRACE_SCHEMA:
			failures.append("trace_record_wrong_schema")
		if str(record.get("previous_hash", "")) != expected_previous:
			failures.append("trace_previous_hash_mismatch")
		var claimed_hash := str(record.get("record_hash", ""))
		var hash_payload := record.duplicate(true)
		hash_payload.erase("record_hash")
		if claimed_hash == "" or claimed_hash != \
				PersonaDecisionTraceScript.canonical_hash(hash_payload):
			failures.append("trace_record_hash_mismatch")
		expected_previous = claimed_hash
		match str(record.get("record_type", "")):
			PersonaDecisionTraceScript.RUN_RECORD:
				if saw_run or expected_decision_index > 0 or saw_summary:
					failures.append("misplaced_run_header")
				saw_run = true
				var run_v: Variant = record.get("run", {})
				if run_v is Dictionary:
					run_identity = (run_v as Dictionary).duplicate(true)
					var run_id := str(run_identity.get("run_id", ""))
					var trace_id := str(run_identity.get("trace_id", ""))
					var invocation_id := str(run_identity.get("invocation_id", ""))
					if run_id == "" or trace_id == "" or invocation_id == "" \
							or run_id == trace_id or run_id == invocation_id \
							or trace_id == invocation_id \
							or str(run_identity.get("content_fingerprint", "")) == "" \
							or str(run_identity.get("content_fingerprint", "")) != str(
								report.get(
									"decision_trace_expected_content_fingerprint", "")) \
							or str(run_identity.get("execution_platform", "")) \
								not in ["native", "web"] \
							or str(run_identity.get("evidence_baseline_id", "")) != str(
								report.get("decision_trace_baseline_id", "")) \
							or str(run_identity.get("persona_id", "")) != "" \
							or str(run_identity.get("persona_enrollment", "")) \
								!= "not_enrolled":
						failures.append("run_header_provenance_invalid")
				else:
					failures.append("run_header_missing_identity")
			PersonaDecisionTraceScript.DECISION_RECORD:
				if not saw_run or saw_summary:
					failures.append("decision_outside_run")
				if int(record.get("decision_index", -1)) != expected_decision_index:
					failures.append("decision_index_mismatch")
				var visible_record_matches := expected_decision_index \
					< visible_decisions.size() \
					and PersonaDecisionTraceScript.canonical_json(record) == \
						PersonaDecisionTraceScript.canonical_json(
							visible_decisions[expected_decision_index])
				if not visible_record_matches:
					failures.append("visible_decision_hash_record_mismatch:%d" \
						% expected_decision_index)
				if PersonaDecisionTraceScript.canonical_json(
						record.get("run", {})) != \
						PersonaDecisionTraceScript.canonical_json(run_identity):
					failures.append("decision_run_identity_mismatch")
				var observation_before_v: Variant = record.get(
					"observation_before", null)
				var observation_after_v: Variant = record.get(
					"observation_after", null)
				var observation_samples_v: Variant = record.get(
					"observation_samples", null)
				var outcome_v: Variant = record.get("outcome", {})
				var no_legacy_alias := not record.has("observation") \
					and (not (outcome_v is Dictionary) \
						or not (outcome_v as Dictionary).has("observation"))
				var observation_sequence_valid := \
					observation_before_v is Dictionary \
					and observation_after_v is Dictionary \
					and observation_samples_v is Array
				if observation_sequence_valid:
					observation_sequence_valid = \
						PersonaDecisionTraceScript.validate_player_observation(
							observation_before_v as Dictionary).is_empty() \
						and PersonaDecisionTraceScript.validate_player_observation(
							observation_after_v as Dictionary).is_empty() \
						and PersonaDecisionTraceScript.canonical_equal(
							observation_samples_v,
							PersonaDecisionTraceScript.deduplicate_observations(
								observation_samples_v as Array))
					if observation_sequence_valid:
						for sample_v in observation_samples_v as Array:
							if not (sample_v is Dictionary) \
									or not PersonaDecisionTraceScript.validate_player_observation(
										sample_v as Dictionary).is_empty():
								observation_sequence_valid = false
								break
				var structural_issues := \
					PersonaDecisionTraceScript.validate_decision_record(record)
				structural_issues.append_array(
					_generated_decision_progression_reasons(
						prior_trace_decisions, record))
				structural_issues.sort()
				var structural_v3_valid := structural_issues.is_empty() \
					and no_legacy_alias
				if not structural_v3_valid:
					failures.append("decision_v3_structure_invalid:%d:%s" % [
						expected_decision_index, str(structural_issues)])
				var context_v: Variant = record.get("evidence_context", {})
				var baseline_valid := context_v is Dictionary \
					and str((context_v as Dictionary).get(
						"evidence_baseline_id", "")) == str(
							report.get("decision_trace_baseline_id", "")) \
					and str(report.get("decision_trace_baseline_id", "")) != ""
				var receipt_links_valid := _generated_decision_receipt_links_valid(
					record, observation_before_v as Dictionary \
						if observation_before_v is Dictionary else {}, receipt_ids)
				if not receipt_links_valid:
					failures.append("decision_receipt_link_invalid:%d" \
						% expected_decision_index)
				var evidence_v: Variant = record.get("evidence", {})
				var recomputed := PersonaDecisionTraceScript.classify_evidence(record)
				var recomputed_reasons: Array = recomputed.get(
					"rejection_reasons", []).duplicate()
				if not recomputed_reasons.has("unnamed_strategy_not_persona"):
					recomputed_reasons.append("unnamed_strategy_not_persona")
				recomputed_reasons.sort()
				var quarantine_valid := evidence_v is Dictionary \
					and bool(recomputed.get("player_reproducible", false)) \
					and bool((evidence_v as Dictionary).get(
						"player_reproducible", false)) \
					and not bool((evidence_v as Dictionary).get(
						"eligible_for_learning", true)) \
					and PersonaDecisionTraceScript.canonical_json(
						(evidence_v as Dictionary).get("rejection_reasons", [])) == \
						PersonaDecisionTraceScript.canonical_json(recomputed_reasons)
				if observation_sequence_valid and structural_v3_valid \
						and baseline_valid and quarantine_valid \
						and visible_record_matches and receipt_links_valid:
					validated_observation_decision_count += 1
				else:
					failures.append("observation_decision_link_invalid:%d" \
						% expected_decision_index)
				# Retain the serialized predecessor even when this record is invalid.
				# Otherwise one corrupt decision could erase the ledger boundary that
				# the following generated decision must prove.
				prior_trace_decisions.append(record)
				expected_decision_index += 1
			PersonaDecisionTraceScript.SUMMARY_RECORD:
				if not saw_run or saw_summary:
					failures.append("misplaced_trace_summary")
				saw_summary = true
				if int(record.get("decision_count", -1)) != expected_decision_index:
					failures.append("summary_decision_count_mismatch")
				if PersonaDecisionTraceScript.canonical_json(
						record.get("run", {})) != \
						PersonaDecisionTraceScript.canonical_json(run_identity):
					failures.append("summary_run_identity_mismatch")
				var summary_v: Variant = record.get("summary", {})
				if summary_v is Dictionary:
					summary_trace_complete = bool((summary_v as Dictionary).get(
						"trace_complete", false))
					if bool((summary_v as Dictionary).get(
							"eligible_for_learning", true)) \
							or str((summary_v as Dictionary).get(
								"persona_tree_ineligible_reason", "")) \
								!= "unnamed_strategy_not_persona" \
							or bool((summary_v as Dictionary).get(
								"visible_outcome_reached", false)) != bool(
									report.get("visible_outcome_reached", false)):
						failures.append("summary_quarantine_or_outcome_invalid")
				else:
					failures.append("summary_payload_missing")
			_:
				failures.append("unknown_trace_record_type")
	if not saw_run:
		failures.append("run_header_missing")
	if not saw_summary:
		failures.append("trace_summary_missing")
	if expected_previous != str(report.get("decision_trace_chain_tail", "")):
		failures.append("trace_chain_tail_mismatch")
	if expected_decision_index != visible_decisions.size() \
			or expected_decision_index != int(report.get("decision_count", -1)):
		failures.append("report_decision_count_mismatch")
	if not summary_trace_complete:
		failures.append("summary_trace_incomplete")
	failures.sort()
	var observation_decision_links_valid := failures.is_empty() \
		and validated_observation_decision_count == expected_decision_index \
		and expected_decision_index > 0
	var visible_movement_receipts_valid := \
		_generated_rally_records_have_complete_motion(report)
	return {
		"valid": observation_decision_links_valid \
			and visible_movement_receipts_valid,
		"observation_decision_links_valid": observation_decision_links_valid,
		"validated_observation_decision_count": \
			validated_observation_decision_count,
		"visible_movement_receipts_valid": visible_movement_receipts_valid,
		"policy_evidence_failures": failures,
	}


func _generated_decision_progression_reasons(
		previous_decisions: Array, current_record: Dictionary
	) -> Array[String]:
	# Generated traces use the exact writer/reader ledger contract. Keeping this
	# narrow seam testable prevents the report verifier from regressing to isolated
	# per-record validation, which cannot see gaps between human actions.
	return PersonaDecisionTraceScript.decision_progression_reasons(
		previous_decisions, current_record)


func _generated_decision_receipt_links_valid(
		record: Dictionary,
		observation: Dictionary,
		receipt_ids: Dictionary
	) -> bool:
	var decision_v: Variant = record.get("decision", {})
	var input_v: Variant = record.get("input_receipt", {})
	var receipt_v: Variant = record.get("receipt", {})
	var outcome_v: Variant = record.get("outcome", {})
	if not (decision_v is Dictionary) or not (input_v is Dictionary) \
			or not (receipt_v is Dictionary) or not (outcome_v is Dictionary):
		return false
	var decision := decision_v as Dictionary
	var input_receipt := input_v as Dictionary
	var receipt := receipt_v as Dictionary
	var outcome := outcome_v as Dictionary
	var samples_v: Variant = record.get("observation_samples", [])
	var after_v: Variant = record.get("observation_after", {})
	if not (samples_v is Array) or not (after_v is Dictionary):
		return false
	var relifted := _generated_trace_bound_input_receipt(
		receipt, decision, observation, samples_v as Array, after_v as Dictionary)
	if PersonaDecisionTraceScript.canonical_json(input_receipt) != \
			PersonaDecisionTraceScript.canonical_json(relifted):
		return false
	var receipt_id := str(input_receipt.get("receipt_id", ""))
	if receipt_id == "" or receipt_ids.has(receipt_id):
		return false
	receipt_ids[receipt_id] = true
	var verb := str(decision.get("verb", ""))
	var accepted := bool(receipt.get("accepted", false))
	if verb == "" or str(input_receipt.get("verb", "")) != verb \
			or not _generated_driver_receipt_supports_semantic_verb(receipt, verb) \
			or str(input_receipt.get("status", "")) != (
				"accepted" if accepted else "refused") \
			or bool(outcome.get("accepted", not accepted)) != accepted \
			or str(outcome.get("status", "")) != (
				"accepted" if accepted else "refused"):
		return false
	var target_v: Variant = decision.get("target", {})
	if not (target_v is Dictionary):
		return false
	var target_token := str((target_v as Dictionary).get("token", ""))
	if target_token != str(record.get("target_token", "")):
		return false
	if receipt.has("target_token") \
			and str(receipt.get("target_token", "")) != target_token:
		return false
	if record.get("screen", null) is Array and receipt.get(
			"target_screen", null) is Array \
			and PersonaDecisionTraceScript.canonical_json(record.get("screen", [])) \
				!= PersonaDecisionTraceScript.canonical_json(
					receipt.get("target_screen", [])):
		return false
	if verb in ["camera_pan", "camera_recenter", "camera_rotate", "camera_zoom",
			"select_party", "select_single", "toggle_run"] \
			and not bool(receipt.get("input_issued", false)):
		return false
	if verb == "interact":
		if not _generated_interaction_pointer_park_valid(
				receipt, observation):
			return false
		var target_result_v: Variant = receipt.get(
			"target_result_attestation", {})
		if not (target_result_v is Dictionary):
			return false
		var target_result := target_result_v as Dictionary
		var baseline := _player_observation_target_result(
			observation, target_token)
		if target_token == "" \
				or str(target_result.get("source_token", "")) != target_token \
				or not bool(target_result.get("visible", false)) \
				or int(target_result.get("presentation_serial", 0)) \
					<= int(baseline.get("presentation_serial", 0)) \
				or str(target_result.get("result", "")) != (
					"success" if accepted else "rejected") \
				or PersonaDecisionTraceScript.canonical_json(
					outcome.get("interaction_result", {})) != \
					PersonaDecisionTraceScript.canonical_json(target_result):
			return false
	if verb == "rally":
		if not _generated_rally_pointer_park_valid(receipt, observation):
			return false
		var intended := receipt.get("intended_members", []) as Array
		if not bool(decision.get("group_verb", false)) \
				or not _same_string_members(
					intended, decision.get("intended_subjects", []) as Array) \
				or int(receipt.get("rally_event_count", -1)) != (
					1 if accepted else 0) \
				or int(input_receipt.get("production_event_count", -1)) != (
					1 if accepted else 0):
			return false
		var member_results_v: Variant = receipt.get("member_results", {})
		if intended.is_empty() or not (member_results_v is Dictionary) \
				or (member_results_v as Dictionary).size() != intended.size():
			return false
		for member_v in intended:
			if str((member_results_v as Dictionary).get(str(member_v), "")) != (
					"accepted" if accepted else "refused"):
				return false
		var movement_result_v: Variant = receipt.get(
			"movement_result_attestation", {})
		if not (movement_result_v is Dictionary):
			return false
		var movement_result := movement_result_v as Dictionary
		var expected_portrait_tokens := \
			_player_observation_portrait_tokens_for_members(
				observation, intended)
		var expected_phases := ["accepted", "progress", "arrival"] \
			if accepted else ["refused"]
		if movement_result.is_empty() \
				or not bool(movement_result.get("visible", false)) \
				or bool(movement_result.get("accepted", not accepted)) != accepted \
				or str(movement_result.get("target_token", "")) != target_token \
				or int(movement_result.get("presentation_serial", 0)) \
					<= _highest_visible_movement_result_serial(observation) \
				or not _same_string_members(
					movement_result.get("subjects", []) as Array,
					expected_portrait_tokens) \
				or not PersonaDecisionTraceScript.canonical_equal(
					movement_result.get("phases", []), expected_phases) \
				or str(movement_result.get("phase", "")) != (
					"arrival" if accepted else "refused") \
				or not (outcome.get("movement_result", null) is Dictionary):
			return false
		var derived_movement := outcome.get("movement_result", {}) as Dictionary
		for linked_key in ["target_token", "subjects", "presentation_serial",
				"phases", "phase", "accepted", "reason", "visible"]:
			if not PersonaDecisionTraceScript.canonical_equal(
					derived_movement.get(linked_key), movement_result.get(linked_key)):
				return false
		if not accepted and str(movement_result.get(
				"reason", "")).strip_edges() == "":
			return false
		if accepted:
			var motion_v: Variant = receipt.get("visible_motion_evidence", {})
			if not (motion_v is Dictionary):
				return false
			var motion := motion_v as Dictionary
			if not bool(motion.get("visible", false)) \
					or not _same_string_members(
						motion.get("intended_members", []) as Array, intended) \
					or not PersonaDecisionTraceScript.canonical_equal(
						motion.get("member_destinations", {}),
						receipt.get("member_destinations", {})) \
					or not PersonaDecisionTraceScript.canonical_equal(
						motion.get("movement_result", {}), movement_result) \
					or not _generated_accepted_rally_motion_evidence_valid(
						motion,
						intended,
						observation,
						samples_v as Array,
						after_v as Dictionary):
				return false
		else:
			var refusal_motion_v: Variant = receipt.get(
				"visible_motion_evidence", {})
			if not (refusal_motion_v is Dictionary) \
					or not PersonaDecisionTraceScript.canonical_equal(
						(refusal_motion_v as Dictionary).get(
							"movement_result", {}), movement_result) \
					or not _generated_refused_rally_motion_evidence_valid(
						refusal_motion_v as Dictionary,
						intended,
						observation,
						samples_v as Array,
						after_v as Dictionary):
				return false
	return true


func _generated_driver_receipt_supports_semantic_verb(
		receipt: Dictionary, semantic_verb: String
	) -> bool:
	var kind := str(receipt.get("kind", ""))
	match semantic_verb:
		"hover":
			return kind == "hover_pointer"
		"camera_pan":
			return kind == "key" and int(receipt.get("keycode", 0)) \
				in [KEY_W, KEY_A, KEY_S, KEY_D]
		"camera_recenter":
			return kind == "recenter"
		"camera_rotate":
			return kind == "rotate_camera" \
				and int(receipt.get("keycode", 0)) in [KEY_Q, KEY_E]
		"camera_zoom":
			return kind == "zoom_out"
		"toggle_run":
			return kind == "set_party_running"
	return kind == semantic_verb


func _same_string_members(left: Array, right: Array) -> bool:
	var left_strings: Array[String] = []
	var right_strings: Array[String] = []
	for value_v in left:
		left_strings.append(str(value_v))
	for value_v in right:
		right_strings.append(str(value_v))
	left_strings.sort()
	right_strings.sort()
	return left_strings == right_strings


## Validates the human-observable presence provenance carried by Rally motion
## evidence. Body tokens are always real party_body tokens. A member without an
## initial body is allowed only when its portrait rendered exact HIDDEN; a later
## token for that member must first appear in a captured party_body cue.
func _generated_rally_motion_presence_evidence_valid(
		motion: Dictionary,
		intended_members: Array,
		observation_before: Dictionary,
		observation_samples: Array,
		observation_after: Dictionary,
		allow_later_body_tokens: bool
	) -> bool:
	var member_tokens_v: Variant = motion.get("member_body_tokens", {})
	var concealed_v: Variant = motion.get("concealed_members", {})
	var concealed_tokens_v: Variant = motion.get(
		"concealed_portrait_tokens", [])
	if not (member_tokens_v is Dictionary) \
			or not (concealed_v is Dictionary) \
			or not (concealed_tokens_v is Array):
		return false
	var member_tokens := member_tokens_v as Dictionary
	var concealed := concealed_v as Dictionary
	var expected_concealed := _player_observation_concealed_members(
		observation_before, intended_members)
	if PersonaDecisionTraceScript.canonical_json(concealed) != \
			PersonaDecisionTraceScript.canonical_json(expected_concealed):
		return false
	var expected_concealed_tokens: Array[String] = []
	for token_v in expected_concealed.values():
		expected_concealed_tokens.append(str(token_v))
	expected_concealed_tokens.sort()
	var presented_concealed_tokens: Array[String] = []
	for token_v in concealed_tokens_v as Array:
		if not (token_v is String):
			return false
		presented_concealed_tokens.append(str(token_v))
	if presented_concealed_tokens != expected_concealed_tokens:
		return false
	var intended_set := {}
	for member_v in intended_members:
		var member := str(member_v)
		if member == "" or intended_set.has(member):
			return false
		intended_set[member] = true
	var initial_member_tokens := _player_observation_body_tokens_for_members(
		observation_before, intended_members)
	var unique_body_tokens := {}
	for member_v in member_tokens.keys():
		var member := str(member_v)
		var body_token := str(member_tokens.get(member_v, ""))
		if not intended_set.has(member) or body_token == "" \
				or unique_body_tokens.has(body_token):
			return false
		unique_body_tokens[body_token] = true
		if initial_member_tokens.has(member):
			if str(initial_member_tokens.get(member, "")) != body_token:
				return false
			continue
		if not allow_later_body_tokens or not expected_concealed.has(member):
			return false
		var later_visible := false
		for sample_v in observation_samples:
			if sample_v is Dictionary and \
					_player_observation_member_body_token_visible(
						sample_v as Dictionary, member, body_token):
				later_visible = true
				break
		if not later_visible:
			later_visible = _player_observation_member_body_token_visible(
				observation_after, member, body_token)
		if not later_visible:
			return false
	for member_v in initial_member_tokens.keys():
		var member := str(member_v)
		if str(member_tokens.get(member, "")) != str(
				initial_member_tokens.get(member_v, "")):
			return false
	for member_v in intended_members:
		var member := str(member_v)
		if not member_tokens.has(member) and not expected_concealed.has(member):
			return false
	var continuity_observations := observation_samples.duplicate()
	continuity_observations.append(observation_after)
	for member_v in expected_concealed.keys():
		var member := str(member_v)
		var portrait_token := str(expected_concealed.get(member_v, ""))
		var later_body_token := str(member_tokens.get(member, "")) \
			if not initial_member_tokens.has(member) else ""
		var body_seen := false
		for observation_v in continuity_observations:
			if not (observation_v is Dictionary):
				return false
			var current_observation := observation_v as Dictionary
			if later_body_token != "" and \
					_player_observation_member_body_token_visible(
						current_observation, member, later_body_token):
				body_seen = true
			if not body_seen and not \
					_player_observation_portrait_has_exact_hidden_presence(
						current_observation, portrait_token):
				return false
	return true


func _generated_accepted_rally_motion_evidence_valid(
		motion: Dictionary,
		intended_members: Array,
		observation_before: Dictionary,
		observation_samples: Array,
		observation_after: Dictionary
	) -> bool:
	if intended_members.is_empty() \
			or not _generated_rally_motion_presence_evidence_valid(
				motion,
				intended_members,
				observation_before,
				observation_samples,
				observation_after,
				true) \
			or not _same_string_members(
				motion.get("presented_movement_members", []) as Array,
				intended_members) \
			or not _generated_transform_samples_valid(
				motion.get("transform_samples", {}) as Dictionary,
				intended_members,
				motion.get("stationary_arrival_members", []) as Array):
		return false
	var member_tokens := motion.get("member_body_tokens", {}) as Dictionary
	var concealed := motion.get("concealed_members", {}) as Dictionary
	var moved := motion.get("moved_members", []) as Array
	var concealed_progress := motion.get(
		"concealed_progress_members", []) as Array
	var stationary_arrivals := motion.get(
		"stationary_arrival_members", []) as Array
	var presented := motion.get("presented_movement_members", []) as Array
	var movement_result_v: Variant = motion.get("movement_result", {})
	if not (movement_result_v is Dictionary):
		return false
	var movement_result := movement_result_v as Dictionary
	if not bool(movement_result.get("visible", false)) \
			or not bool(movement_result.get("accepted", false)) \
			or not (movement_result.get("phases", []) as Array).has("progress"):
		return false
	var visible_subjects := movement_result.get("subjects", []) as Array
	var expected_portrait_subjects := \
		_player_observation_portrait_tokens_for_members(
			observation_before, intended_members)
	if not _same_string_members(visible_subjects, expected_portrait_subjects):
		return false
	var expected_body_subjects: Array[String] = []
	var moved_set := {}
	for member_v in moved:
		var member := str(member_v)
		if moved_set.has(member) or not member_tokens.has(member):
			return false
		moved_set[member] = true
		expected_body_subjects.append(str(member_tokens.get(member, "")))
	expected_body_subjects.sort()
	if not _same_string_members(
			motion.get("subjects", []) as Array, expected_body_subjects):
		return false
	var concealed_progress_set := {}
	for member_v in concealed_progress:
		var member := str(member_v)
		var portrait_token := str(concealed.get(member, ""))
		if concealed_progress_set.has(member) or portrait_token == "" \
				or not visible_subjects.has(portrait_token):
			return false
		concealed_progress_set[member] = true
	var stationary_set := {}
	for member_v in stationary_arrivals:
		var member := str(member_v)
		if stationary_set.has(member) or moved_set.has(member) \
				or not _generated_stationary_rally_endpoint_valid(
					member,
					motion.get("transform_samples", {}) as Dictionary,
					motion.get("member_destinations", {}) as Dictionary):
			return false
		stationary_set[member] = true
	for member_v in concealed.keys():
		if not concealed_progress_set.has(str(member_v)):
			return false
	for member_v in presented:
		var member := str(member_v)
		if not moved_set.has(member) and not concealed_progress_set.has(member) \
				and not stationary_set.has(member):
			return false
	return true


func _generated_rally_records_have_complete_motion(
		report: Dictionary, require_accepted_rally := true
	) -> bool:
	var saw_rally := false
	var saw_accepted_rally := false
	for record_v in report.get("visible_decisions", []):
		if not (record_v is Dictionary):
			continue
		var record := record_v as Dictionary
		var decision_v: Variant = record.get("decision", {})
		if not (decision_v is Dictionary) \
				or str((decision_v as Dictionary).get("verb", "")) != "rally":
			continue
		saw_rally = true
		var receipt_v: Variant = record.get("receipt", {})
		if not (receipt_v is Dictionary):
			return false
		var receipt := receipt_v as Dictionary
		var observation_v: Variant = record.get("observation_before", {})
		if not (observation_v is Dictionary) \
				or not _generated_rally_pointer_park_valid(
				receipt, observation_v as Dictionary):
			return false
		var motion_v: Variant = receipt.get("visible_motion_evidence", {})
		if not (motion_v is Dictionary):
			return false
		var motion := motion_v as Dictionary
		var intended := receipt.get("intended_members", []) as Array
		var movement_result_v: Variant = receipt.get(
			"movement_result_attestation", {})
		if not (movement_result_v is Dictionary) \
				or (movement_result_v as Dictionary).is_empty():
			return false
		var movement_result := movement_result_v as Dictionary
		var record_samples_v: Variant = record.get("observation_samples", [])
		var record_after_v: Variant = record.get("observation_after", {})
		if not (record_samples_v is Array) or not (record_after_v is Dictionary):
			return false
		if bool(receipt.get("accepted", false)):
			saw_accepted_rally = true
			if not bool(movement_result.get("accepted", false)) \
					or str(movement_result.get("phase", "")) != "arrival" \
					or not PersonaDecisionTraceScript.canonical_equal(
						movement_result.get("phases", []),
						["accepted", "progress", "arrival"]) \
					or not bool(motion.get("visible", false)) \
					or not PersonaDecisionTraceScript.canonical_equal(
						motion.get("movement_result", {}), movement_result) \
					or intended.is_empty() \
					or not _generated_accepted_rally_motion_evidence_valid(
						motion,
						intended,
						observation_v as Dictionary,
						record_samples_v as Array,
						record_after_v as Dictionary):
				return false
		else:
			# A single visible whole-command refusal is still honest player evidence:
			# no production event and every intended member refused atomically. Only an
			# accepted Rally claims movement and therefore needs transform receipts.
			var member_results_v: Variant = receipt.get("member_results", {})
			if intended.is_empty() or not bool(receipt.get("atomic_group", false)) \
					or int(receipt.get("rally_event_count", -1)) != 0 \
					or not (member_results_v is Dictionary) \
					or (member_results_v as Dictionary).size() != intended.size() \
					or bool(movement_result.get("accepted", true)) \
					or str(movement_result.get("phase", "")) != "refused" \
					or not PersonaDecisionTraceScript.canonical_equal(
						movement_result.get("phases", []), ["refused"]) \
					or str(movement_result.get("reason", "")).strip_edges() == "" \
					or not PersonaDecisionTraceScript.canonical_equal(
						motion.get("movement_result", {}), movement_result) \
					or not _generated_refused_rally_motion_evidence_valid(
						motion,
						intended,
						observation_v as Dictionary,
						record_samples_v as Array,
						record_after_v as Dictionary):
				return false
			for member_v in intended:
				if str((member_results_v as Dictionary).get(
						str(member_v), "")) != "refused":
					return false
	return saw_rally and (saw_accepted_rally or not require_accepted_rally)


func _generated_rally_pointer_park_valid(
		receipt: Dictionary, observation_before: Dictionary
	) -> bool:
	return _generated_pointer_park_valid(
		receipt, observation_before, "pointer_parked_after_gesture")


func _generated_interaction_pointer_park_valid(
		receipt: Dictionary, observation_before: Dictionary
	) -> bool:
	return _generated_pointer_park_valid(
		receipt, observation_before, "pointer_parked_after_click")


func _generated_pointer_park_valid(
		receipt: Dictionary,
		observation_before: Dictionary,
		parked_flag: String
	) -> bool:
	if not _generated_pointer_hover_rebind_valid(
			receipt, observation_before):
		return false
	var park_v: Variant = receipt.get("pointer_park_receipt", {})
	if parked_flag == "" or not (park_v is Dictionary) \
			or not bool(receipt.get(parked_flag, false)):
		return false
	var park := park_v as Dictionary
	var state := observation_before.get("state", {}) as Dictionary
	var viewport := state.get("viewport", {}) as Dictionary
	var origin := viewport.get("origin", []) as Array
	var size := viewport.get("size", []) as Array
	var target_screen := receipt.get("target_screen", []) as Array
	var from_screen := park.get("from_screen", []) as Array
	var to_screen := park.get("to_screen", []) as Array
	if str(park.get("kind", "")) != "park_pointer" \
			or not bool(park.get("accepted", false)) \
			or not bool(park.get("input_issued", false)) \
			or not bool(park.get("player_reproducible", false)) \
			or origin.size() < 2 or size.size() < 2 \
			or target_screen.size() < 2 or from_screen.size() < 2 \
			or to_screen.size() < 2:
		return false
	var expected_center := Vector2(
		float(origin[0]) + float(size[0]) * 0.5,
		float(origin[1]) + float(size[1]) * 0.5)
	var target_point := Vector2(float(target_screen[0]), float(target_screen[1]))
	var from_point := Vector2(float(from_screen[0]), float(from_screen[1]))
	var parked_point := Vector2(float(to_screen[0]), float(to_screen[1]))
	var merged_events := receipt.get("input_events", []) as Array
	var park_events := park.get("input_events", []) as Array
	if park_events.size() != 1 or not (park_events[0] is Dictionary) \
			or merged_events.is_empty():
		return false
	var park_event := park_events[0] as Dictionary
	var event_position := park_event.get("position", []) as Array
	if event_position.size() < 2:
		return false
	var event_point := Vector2(
		float(event_position[0]), float(event_position[1]))
	var receipt_before := int(receipt.get("input_sequence_before", -1))
	var receipt_after := int(receipt.get("input_sequence_after", -1))
	var park_before := int(park.get("input_sequence_before", -1))
	var park_after := int(park.get("input_sequence_after", -1))
	if receipt_before < 0 or receipt_after <= receipt_before \
			or int(receipt.get("input_event_count", -1)) != merged_events.size() \
			or receipt_after - receipt_before != merged_events.size() \
			or park_before != receipt_after - 1 or park_after != receipt_after \
			or park_after != park_before + 1 \
			or int(park.get("input_event_count", -1)) != 1:
		return false
	for event_index in range(merged_events.size()):
		var merged_event_v: Variant = merged_events[event_index]
		if not (merged_event_v is Dictionary) or int(
				(merged_event_v as Dictionary).get("sequence", -1)) \
				!= receipt_before + event_index + 1:
			return false
	return target_point.is_equal_approx(from_point) \
		and parked_point.is_equal_approx(expected_center) \
		and event_point.is_equal_approx(parked_point) \
		and str(park_event.get("kind", "")) == "pointer_move" \
		and bool(park_event.get("issued", false)) \
		and int(park_event.get("button_mask", -1)) == 0 \
		and int(park_event.get("sequence", -1)) == park_after \
		and PersonaDecisionTraceScript.canonical_equal(
			merged_events[-1], park_event)


func _generated_pointer_hover_rebind_valid(
		receipt: Dictionary, observation_before: Dictionary
	) -> bool:
	var hover_v: Variant = receipt.get("pointer_hover_receipt", {})
	if not (hover_v is Dictionary) \
			or not bool(receipt.get("pointer_hover_rebound", false)):
		return false
	var hover := hover_v as Dictionary
	var target_token := str(receipt.get("target_token", ""))
	var target_screen := receipt.get("target_screen", []) as Array
	var hover_screen_v: Variant = hover.get("screen_point", null)
	var hover_screen: Array = []
	if hover_screen_v is Vector2:
		hover_screen = [
			(hover_screen_v as Vector2).x,
			(hover_screen_v as Vector2).y,
		]
	elif hover_screen_v is Array:
		hover_screen = (hover_screen_v as Array).duplicate()
	var hover_events := hover.get("input_events", []) as Array \
		if hover.get("input_events", null) is Array else []
	var merged_events := receipt.get("input_events", []) as Array \
		if receipt.get("input_events", null) is Array else []
	if target_token == "" or str(hover.get("kind", "")) != "hover_pointer" \
			or str(hover.get("target_token", "")) != target_token \
			or not bool(hover.get("accepted", false)) \
			or not bool(hover.get("input_issued", false)) \
			or not bool(hover.get("player_reproducible", false)) \
			or not bool(hover.get("rendered_hover_waited", false)) \
			or target_screen.size() != 2 or hover_screen.size() != 2 \
			or hover_events.size() != 1 or merged_events.size() < 3 \
			or not (hover_events[0] is Dictionary):
		return false
	var hover_event := hover_events[0] as Dictionary
	var event_position := hover_event.get("position", []) as Array
	if event_position.size() != 2 \
			or str(hover_event.get("kind", "")) != "pointer_move" \
			or not bool(hover_event.get("issued", false)) \
			or int(hover_event.get("button_mask", -1)) != 0:
		return false
	var target_point := Vector2(
		float(target_screen[0]), float(target_screen[1]))
	var described_hover_point := Vector2(
		float(hover_screen[0]), float(hover_screen[1]))
	var actual_hover_point := Vector2(
		float(event_position[0]), float(event_position[1]))
	var merged_before := int(receipt.get("input_sequence_before", -1))
	var hover_before := int(hover.get("input_sequence_before", -1))
	var hover_after := int(hover.get("input_sequence_after", -1))
	var world_before := int(receipt.get("world_input_sequence_before", -1))
	var world_after := int(receipt.get("world_input_sequence_after", -1))
	if merged_before < 0 or hover_before != merged_before \
			or hover_after != hover_before + 1 \
			or world_before != hover_after or world_after <= world_before \
			or int(hover_event.get("sequence", -1)) != hover_after \
			or not PersonaDecisionTraceScript.canonical_equal(
				merged_events[0], hover_event):
		return false
	var world_down_v: Variant = merged_events[1]
	if not (world_down_v is Dictionary):
		return false
	var world_down := world_down_v as Dictionary
	var down_position := world_down.get("position", []) as Array
	return int(receipt.get("rendered_hover_rebind_capture_serial", 0)) \
			== int(observation_before.get("capture_serial", -1)) \
		and int(receipt.get("rendered_hover_decision_capture_serial", 0)) \
			< int(receipt.get("rendered_hover_rebind_capture_serial", 0)) \
		and target_point.is_equal_approx(described_hover_point) \
		and target_point.is_equal_approx(actual_hover_point) \
		and str(world_down.get("kind", "")) == "pointer_button" \
		and int(world_down.get("button", 0)) == MOUSE_BUTTON_RIGHT \
		and bool(world_down.get("pressed", false)) \
		and int(world_down.get("sequence", -1)) == world_before + 1 \
		and down_position.size() == 2 \
		and Vector2(
			float(down_position[0]), float(down_position[1])
		).is_equal_approx(actual_hover_point)


func _append_visible_decision_record(
		report: Dictionary,
		observation_before: Dictionary,
		rationale_text: String,
		policy_nodes: Array,
		action: Dictionary,
		driver_receipt: Dictionary,
		observation_after: Dictionary,
		world_change: bool,
		intended_subjects: Array,
		observation_samples: Array = []
	) -> void:
	var records := report.get("visible_decisions", []) as Array
	var decision_index := records.size()
	var before_safe := PersonaDecisionTraceScript.json_safe(
		observation_before) as Dictionary
	var after_safe := PersonaDecisionTraceScript.json_safe(
		observation_after) as Dictionary
	var raw_samples_safe := PersonaDecisionTraceScript.json_safe(
		observation_samples) as Array
	var samples_safe := PersonaDecisionTraceScript.deduplicate_observations(
		raw_samples_safe)
	var verb := str(action.get("verb", "")).strip_edges().to_lower()
	if verb == "":
		verb = str(action.get("kind", "")).strip_edges().to_lower()
	if verb == "":
		verb = str(driver_receipt.get("kind", "")).strip_edges().to_lower()
	var target_token := str(action.get("target_token", ""))
	var group_verb := verb == "rally" or bool(action.get("group_verb", false))
	var subjects: Array = intended_subjects.duplicate()
	if group_verb and driver_receipt.get("intended_members", null) is Array:
		subjects = driver_receipt.get("intended_members", []).duplicate()
	var accepted := bool(driver_receipt.get("accepted", false))
	var trace_decision := {
		"verb": verb,
		"world_change": world_change,
		"group_verb": group_verb,
		"intended_subjects": subjects,
		"target": {
			"kind": "visible_surface" if target_token != "" else "visible_control",
			"token": target_token,
		},
	}
	var lifted_receipt := _generated_trace_bound_input_receipt(
		driver_receipt, trace_decision, before_safe, samples_safe, after_safe)
	var derived := PersonaDecisionTraceScript.derive_feedback_outcome(
		before_safe, after_safe, samples_safe, trace_decision, lifted_receipt)
	var feedback := (derived.get("feedback", {}) as Dictionary).duplicate(true)
	var outcome_record := (derived.get("outcome", {}) as Dictionary).duplicate(true)
	var record: Dictionary = action.duplicate(true)
	record.merge({
		"schema": GENERATED_STRATEGY_TRACE_SCHEMA,
		"record_type": PersonaDecisionTraceScript.DECISION_RECORD,
		"classification": "diagnostic_strategy_not_persona",
		"run": (report.get("decision_trace_run", {}) as Dictionary).duplicate(true),
		"decision_index": decision_index,
		"decision_source": PLAYER_DISCOVERY_OBSERVATION_SCHEMA,
		"observation_before": before_safe,
		"observation_after": after_safe,
		"observation_samples": samples_safe,
		"rationale": {
			"text": rationale_text,
			"policy_nodes": policy_nodes.duplicate(true),
		},
		"decision": trace_decision,
		"input_receipt": lifted_receipt,
		"receipt": driver_receipt.duplicate(true),
		"feedback": feedback,
		"outcome": outcome_record,
		"evidence_context": {
			"authored_state": true,
			"fixture_quarantine": false,
			"evidence_baseline_id": str(
				report.get("decision_trace_baseline_id", "")),
		},
	}, true)
	var raw_classification := PersonaDecisionTraceScript.classify_evidence(record)
	var raw_rejection_reasons: Array = raw_classification.get(
		"rejection_reasons", []).duplicate()
	if verb in ["select_party", "select_single"] and accepted \
			and (feedback.get("cues", []) as Array).is_empty():
		raw_rejection_reasons.append("selection_change_not_visibly_presented")
	raw_rejection_reasons.sort()
	var raw_player_reproducible := bool(raw_classification.get(
		"player_reproducible", false))
	if raw_rejection_reasons.has("selection_change_not_visibly_presented"):
		raw_player_reproducible = false
	var rejection_reasons: Array = raw_rejection_reasons.duplicate()
	if not rejection_reasons.has("unnamed_strategy_not_persona"):
		rejection_reasons.append("unnamed_strategy_not_persona")
	rejection_reasons.sort()
	record["evidence"] = {
		"player_reproducible": raw_player_reproducible,
		"eligible_for_learning": false,
		"rejection_reasons": rejection_reasons,
	}
	var structural_issues: Array[String] = \
		PersonaDecisionTraceScript.validate_decision_record(record)
	if not structural_issues.is_empty():
		(report["decision_trace_failures"] as Array).append({
			"decision_index": decision_index,
			"failure": "invalid_decision_record",
			"issues": structural_issues.duplicate(),
		})
	if not raw_player_reproducible:
		(report["decision_trace_failures"] as Array).append({
			"decision_index": decision_index,
			"failure": "non_reproducible_decision_evidence",
			"issues": raw_rejection_reasons,
		})
	var written := _append_generated_strategy_trace_record(report, record)
	records.append(written)
	report["visible_decisions"] = records


func _generated_trace_bound_input_receipt(
		driver_receipt: Dictionary,
		decision: Dictionary,
		observation_before: Dictionary,
		observation_samples: Array,
		observation_after: Dictionary
	) -> Dictionary:
	var lifted := PersonaDecisionTraceScript.shipped_input_receipt(
		driver_receipt, "keyboard_pointer")
	lifted["verb"] = str(decision.get("verb", ""))
	lifted["observation_before_capture_serial"] = int(
		observation_before.get("capture_serial", 0))
	var first_post_capture_serial := int(observation_after.get(
		"capture_serial", 0))
	if not observation_samples.is_empty() and observation_samples[0] is Dictionary:
		first_post_capture_serial = int((observation_samples[0] as Dictionary).get(
			"capture_serial", 0))
	lifted["first_post_input_capture_serial"] = first_post_capture_serial
	var target_v: Variant = decision.get("target", {})
	lifted["input_target_token"] = str((target_v as Dictionary).get(
		"token", "")) if target_v is Dictionary else ""
	return PersonaDecisionTraceScript.json_safe(lifted) as Dictionary


func _merge_generated_auxiliary_input_receipts(receipt: Dictionary) -> Dictionary:
	var merged := receipt.duplicate(true)
	if not merged.has("world_input_sequence_before"):
		merged["world_input_sequence_before"] = int(
			merged.get("input_sequence_before", -1))
		merged["world_input_sequence_after"] = int(
			merged.get("input_sequence_after", -1))
	for auxiliary_key in ["pointer_hover_receipt", "pointer_park_receipt"]:
		var auxiliary_value: Variant = merged.get(auxiliary_key, null)
		if not (auxiliary_value is Dictionary):
			continue
		var auxiliary := auxiliary_value as Dictionary
		if not bool(auxiliary.get("input_issued", false)):
			continue
		var merged_before := int(merged.get("input_sequence_before", -1))
		var merged_after := int(merged.get("input_sequence_after", -1))
		var auxiliary_before := int(auxiliary.get("input_sequence_before", -2))
		var auxiliary_after := int(auxiliary.get("input_sequence_after", -2))
		var is_prefix: bool = auxiliary_key == "pointer_hover_receipt" \
			and auxiliary_after == merged_before
		var is_suffix: bool = auxiliary_key == "pointer_park_receipt" \
			and auxiliary_before == merged_after
		if merged_before < 0 or merged_after < 0 \
				or (not is_prefix and not is_suffix):
			# Do not conceal an input gap. The decision validator must see and reject
			# any discontinuity rather than treating unrecorded input as part of the
			# hover -> world action -> pointer park gesture ledger.
			continue
		var merged_events: Array = merged.get("input_events", []).duplicate(true) \
			if merged.get("input_events", null) is Array else []
		if auxiliary.get("input_events", null) is Array:
			if is_prefix:
				var prefixed_events: Array = auxiliary.get(
					"input_events", []).duplicate(true)
				prefixed_events.append_array(merged_events)
				merged_events = prefixed_events
			else:
				merged_events.append_array(auxiliary.get("input_events", []))
		merged["input_events"] = merged_events
		merged["input_event_count"] = merged_events.size()
		if is_prefix:
			merged["input_sequence_before"] = int(auxiliary.get(
				"input_sequence_before", merged_before))
		else:
			merged["input_sequence_after"] = auxiliary_after
		merged["input_issued"] = not merged_events.is_empty()
	return merged


func _decision_trace_feedback(
		before: Dictionary,
		after: Dictionary,
		driver_receipt: Dictionary
	) -> Dictionary:
	var cues: Array = []
	var kind := str(driver_receipt.get("kind", ""))
	if kind == "interact":
		var target_v: Variant = driver_receipt.get("target_result_attestation", null)
		if target_v is Dictionary and bool((target_v as Dictionary).get(
				"visible", false)):
			cues.append({
				"kind": "interaction_result",
				"source_token": str((target_v as Dictionary).get("source_token", "")),
				"presentation_serial": int((target_v as Dictionary).get(
					"presentation_serial", 0)),
				"result": str((target_v as Dictionary).get("result", "")),
				"visible": true,
			})
	elif kind == "rally":
		var movement_result_v: Variant = driver_receipt.get(
			"movement_result_attestation", null)
		if movement_result_v is Dictionary \
				and bool((movement_result_v as Dictionary).get("visible", false)):
			cues.append({
				"kind": "movement_result",
				"target_token": str((movement_result_v as Dictionary).get(
					"target_token", "")),
				"subjects": (movement_result_v as Dictionary).get(
					"subjects", []).duplicate(),
				"phase": str((movement_result_v as Dictionary).get("phase", "")),
				"accepted": bool((movement_result_v as Dictionary).get(
					"accepted", false)),
				"reason": str((movement_result_v as Dictionary).get("reason", "")),
				"presentation_serial": int((movement_result_v as Dictionary).get(
					"presentation_serial", 0)),
				"visible": true,
			})
		var motion_v: Variant = driver_receipt.get("visible_motion_evidence", null)
		if motion_v is Dictionary and bool((motion_v as Dictionary).get(
				"visible", false)):
			cues.append({
				"kind": "movement",
				"subjects": (motion_v as Dictionary).get(
					"subjects", []).duplicate(),
				"visible": true,
			})
	elif kind == "set_party_running":
		var before_hud := (before.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary
		var after_hud := (after.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary
		var before_label := str(before_hud.get("run_label", ""))
		var after_label := str(after_hud.get("run_label", ""))
		if after_label != "" and after_label != before_label:
			cues.append({
				"kind": "hud",
				"text": after_label,
				"visible": true,
			})
	elif kind in ["select_party", "select_single"]:
		var before_selected := _player_observation_selected_portraits(before)
		var after_selected := _player_observation_selected_portraits(after)
		var intended: Array = []
		if kind == "select_single":
			intended = [str(driver_receipt.get("character_id", ""))]
		else:
			intended = driver_receipt.get("expected", []).duplicate()
		var exact_visible_selection := after_selected.size() == intended.size()
		var subjects: Array[String] = []
		for member_v in intended:
			var member := str(member_v)
			exact_visible_selection = exact_visible_selection \
				and after_selected.has(member)
			if after_selected.has(member):
				subjects.append(str(after_selected[member]))
		var visible_delta_or_noop := PersonaDecisionTraceScript.canonical_json(
			before_selected) != PersonaDecisionTraceScript.canonical_json(
				after_selected) or bool(driver_receipt.get("already_selected", false)) \
				or (kind == "select_single" and exact_visible_selection)
		if exact_visible_selection and visible_delta_or_noop:
			cues.append({
				"kind": "hud",
				"text": "VISIBLE PORTRAIT SELECTION",
				"subjects": subjects,
				"visible": true,
			})
	return {"player_observable": not cues.is_empty(), "cues": cues}


func _player_observation_selected_portraits(
		observation: Dictionary
	) -> Dictionary:
	var selected := {}
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return selected
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return selected
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("selected", false)):
			continue
		var member := str(portrait.get("label", "")).strip_edges().to_lower()
		var token := str(portrait.get("token", ""))
		if member != "" and token != "":
			selected[member] = token
	return selected


## One semantic whole-party travel boundary for the generated player. The
## caller has already delivered and rebound the ordinary hover; this helper
## issues exactly the driver's single held-RMB Rally commit and nothing else.
func _rally_whole_party(
		driver: Node, point: Vector2, target_token: String
	) -> Dictionary:
	var receipt_v: Variant = await driver.call(
		"rally_screen_from_rendered_hover", point, target_token)
	return receipt_v as Dictionary if receipt_v is Dictionary else {}


func _drive_observed_rally(
	preview_instance: Node,
	driver: Node,
	observer: Node,
	decision_observation: Dictionary,
	ground: Dictionary,
	report: Dictionary,
	result: Dictionary,
	phase: String,
	label: String,
	watchdog: Dictionary
) -> Dictionary:
	var target_token := str(ground.get("token", ""))
	var stable_target := await _await_observed_affordance_action_stability(
		observer, target_token, decision_observation, watchdog)
	if stable_target.is_empty():
		# Waiting/re-observing is not a world command. If the chosen public target
		# disappears or the rendered projection never settles, do not hover or click
		# its stale pixel; return to the policy loop for a fresh human-visible choice.
		return {
			"accepted": false,
			"verified_atomic": false,
			"visible_motion_verified": false,
			"whole_refusal": false,
			"hover_rebind_failed": false,
			"reobserve_required": true,
			"movement_result": {},
			"sample_count": 0,
			"watchdog_abort_reason": "",
			"receipt": {},
		}
	decision_observation = stable_target.get(
		"observation", decision_observation) as Dictionary
	ground = stable_target.get("affordance", ground) as Dictionary
	var hover_rebind := await _hover_and_rebind_observed_affordance(
		driver,
		observer,
		decision_observation,
		ground,
		watchdog
	)
	if not bool(hover_rebind.get("valid", false)):
		var hover_after := hover_rebind.get(
			"observation", decision_observation) as Dictionary
		var hover_failure_receipt := hover_rebind.get(
			"hover_receipt", {}) as Dictionary
		hover_failure_receipt["hover_rebind_reason"] = str(
			hover_rebind.get("reason", "visible_target_rebind_failed"))
		hover_failure_receipt["hover_rebind_diagnostic"] = (
			hover_rebind.get("rebind_diagnostic", {}) as Dictionary
		).duplicate(true)
		hover_failure_receipt["hover_rebind_frame_path"] = str(
			hover_rebind.get("rebind_frame_path", ""))
		var hover_failure_ordered := _record_observed_hover_rebind_failure(
			report,
			decision_observation,
			hover_after,
			hover_failure_receipt,
			ground,
			"rally",
			label,
			str(hover_rebind.get("reason", "visible_target_rebind_failed"))
		)
		(report["refused_actions"] as Array).append({
			"surface": label,
			"failure": "visible_target_hover_rebind_failed",
			"receipt": hover_failure_receipt.duplicate(true),
			"player_observable_feedback": true,
			"world_input_issued": false,
		})
		if not hover_failure_ordered:
			_set_player_discovery_watchdog_pending(
				watchdog, "hover_input_could_not_be_ordered")
		return {
			"accepted": false,
			"verified_atomic": false,
			"visible_motion_verified": false,
			"whole_refusal": false,
			"hover_rebind_failed": true,
			"movement_result": {},
			"sample_count": 0,
			"watchdog_abort_reason": (
				"" if hover_failure_ordered else "hover_input_could_not_be_ordered"),
			"receipt": hover_failure_receipt,
		}
	decision_observation = hover_rebind.get("observation", {}) as Dictionary
	ground = hover_rebind.get("affordance", {}) as Dictionary
	var point: Vector2 = hover_rebind.get("point", Vector2.INF)
	var hover_receipt := hover_rebind.get("hover_receipt", {}) as Dictionary
	var baseline_movement_serial := _highest_visible_movement_result_serial(
		decision_observation
	)
	# Validation-only full-XYZ baseline. Capture every intended presenter before
	# the held gesture, even while stationary: a very short route can finish during
	# the driver's release frames, and sampling only `is_moving()` afterward would
	# erase both endpoints. This data never enters target choice or policy.
	var intended_members_before_input := _player_party_ids_from_observation(
		decision_observation)
	var pre_park_transform_samples := \
		_new_generated_in_flight_transform_samples(intended_members_before_input)
	_sample_generated_in_flight_transforms(
		preview_instance,
		intended_members_before_input,
		pre_park_transform_samples,
		true)
	if driver == null or not driver.has_method(
			"rally_screen_from_rendered_hover"):
		_set_player_discovery_watchdog_pending(
			watchdog, "whole_party_rally_driver_unavailable")
		return {
			"accepted": false,
			"verified_atomic": false,
			"visible_motion_verified": false,
			"whole_refusal": false,
			"hover_rebind_failed": false,
			"movement_result": {},
			"sample_count": 0,
			"watchdog_abort_reason": "whole_party_rally_driver_unavailable",
			"receipt": {},
		}
	var rally_receipt := await _rally_whole_party(
		driver, point, target_token)
	rally_receipt["pointer_hover_receipt"] = hover_receipt.duplicate(true)
	rally_receipt["pointer_hover_rebound"] = true
	rally_receipt["rendered_hover_rebind_capture_serial"] = int(
		decision_observation.get("capture_serial", 0))
	rally_receipt["rendered_hover_decision_capture_serial"] = int(
		hover_rebind.get("decision_capture_serial", 0))
	rally_receipt["target_token"] = target_token
	rally_receipt["target_screen"] = [point.x, point.y]
	rally_receipt["movement_result_baseline_serial"] = \
		baseline_movement_serial
	rally_receipt = _merge_generated_auxiliary_input_receipts(rally_receipt)
	report["rally_gestures"] = int(report["rally_gestures"]) + 1
	var rally_events := int(rally_receipt.get("rally_event_count", 0))
	var accepted_atomic := (
		bool(rally_receipt.get("accepted", false))
		and bool(rally_receipt.get("atomic_group", false))
		and rally_events == 1
	)
	# Capture the first presented state immediately after release. Movement-result
	# ACCEPTED is intentionally short and must not be reconstructed from EventLog
	# or from the hold indicator that disappeared at release.
	var immediate_observation_v: Variant = _player_observation_snapshot(
		observer, watchdog)
	var immediate_observation := immediate_observation_v as Dictionary \
		if immediate_observation_v is Dictionary else {}
	# Always capture the post-release endpoint before pointer parking as well. If
	# the route already completed, the forced stationary endpoint still proves its
	# displacement from the pre-gesture baseline.
	_sample_generated_in_flight_transforms(
		preview_instance,
		rally_receipt.get("intended_members", []) as Array,
		pre_park_transform_samples,
		true)
	# Preserve the first rendered result at the clicked pixel before moving the
	# pointer. Then make the same harmless MouseMotion a person makes after a held
	# click so an edge target cannot keep panning the camera during evidence settle.
	# Merge that auxiliary packet into the originating receipt: leaving it between
	# decisions would create an unaccounted input-sequence gap in the trace ledger.
	if bool(rally_receipt.get("input_issued", false)) \
			and driver.has_method("park_pointer"):
		var park_receipt_v: Variant = await driver.call("park_pointer")
		var park_receipt := park_receipt_v as Dictionary \
			if park_receipt_v is Dictionary else {}
		rally_receipt["pointer_park_receipt"] = park_receipt.duplicate(true)
		rally_receipt["pointer_parked_after_gesture"] = bool(
			park_receipt.get("accepted", false)) \
			and bool(park_receipt.get("input_issued", false))
		rally_receipt = _merge_generated_auxiliary_input_receipts(rally_receipt)
	var settle := {
		"sample_count": 0,
		"used_multi_y_path": false,
		"settled": false,
		"visible_motion_verified": false,
		"moved_subjects": [],
		"moved_members": [],
		"presented_movement_members": [],
		"concealed_progress_members": [],
		"stationary_arrival_members": [],
		"member_body_tokens": {},
		"concealed_members": {},
		"concealed_portrait_tokens": [],
		"transform_samples": {},
		"movement_result_attestation": {},
		"observation_samples": [],
		"observation": decision_observation,
		"refusal_terminal_capture_fresh": false,
	}
	# A person's pacing is governed by the exact public movement-result lineage
	# and ensuing on-screen bodies, not EventLog. Authority remains a verifier of
	# atomicity only; it never decides when this input-driven player acts next.
	if bool(rally_receipt.get("input_issued", false)):
		settle = await _wait_for_player_rally_settle(
			preview_instance,
			observer,
			result,
			phase,
			label,
			decision_observation,
			rally_receipt.get("intended_members", []).duplicate(),
			report,
			watchdog,
			target_token,
			baseline_movement_serial,
			immediate_observation,
			pre_park_transform_samples,
			rally_receipt.get("member_destinations", {}) as Dictionary
		)
	var provisional_movement_result := settle.get(
		"movement_result_attestation", {}) as Dictionary
	if not bool(provisional_movement_result.get("accepted", true)) \
			and str(provisional_movement_result.get("phase", "")) == "refused":
		# The exact short refusal remains the first post-input sample. Seal a second
		# observation after pointer parking as the chronological terminal capture;
		# even if the red cue expires, its lineage remains in the earlier sample.
		var refusal_terminal_v: Variant = _player_observation_snapshot(
			observer, watchdog)
		settle = _seal_refused_rally_terminal_capture(
			settle,
			refusal_terminal_v as Dictionary \
				if refusal_terminal_v is Dictionary else {})
	var movement_result: Dictionary = settle.get(
		"movement_result_attestation", {})
	rally_receipt["movement_result_attestation"] = \
		movement_result.duplicate(true)
	var visible_commit := bool(movement_result.get("accepted", false)) \
		and (movement_result.get("phases", []) as Array).has("accepted")
	var visible_whole_refusal := (
		bool(rally_receipt.get("atomic_group", false))
		and rally_events == 0
		and bool(settle.get("refusal_terminal_capture_fresh", false))
		and not bool(movement_result.get("accepted", true))
		and str(movement_result.get("phase", "")) == "refused"
	)
	var visible_motion_verified := bool(settle.get(
		"visible_motion_verified", false)) and bool(settle.get("settled", false))
	var accepted_visible := accepted_atomic and visible_commit and visible_motion_verified
	rally_receipt["visible_motion_evidence"] = {
		"kind": "movement",
		"intended_members": rally_receipt.get(
			"intended_members", []).duplicate(),
		"member_body_tokens": settle.get(
			"member_body_tokens", {}).duplicate(true),
		"concealed_members": settle.get(
			"concealed_members", {}).duplicate(true),
		"concealed_portrait_tokens": settle.get(
			"concealed_portrait_tokens", []).duplicate(),
		"moved_members": settle.get("moved_members", []).duplicate(),
		"presented_movement_members": settle.get(
			"presented_movement_members", []).duplicate(),
		"concealed_progress_members": settle.get(
			"concealed_progress_members", []).duplicate(),
		"stationary_arrival_members": settle.get(
			"stationary_arrival_members", []).duplicate(),
		"member_destinations": (rally_receipt.get(
			"member_destinations", {}) as Dictionary).duplicate(true),
		"subjects": settle.get("moved_subjects", []).duplicate(),
		"transform_samples": settle.get(
			"transform_samples", {}).duplicate(true),
		"movement_result": movement_result.duplicate(true),
		"visible": visible_motion_verified,
	}
	if accepted_visible:
		report["movement_commands"] = int(report["movement_commands"]) + 1
		report["route_choices"] = int(report["route_choices"]) + 1
		report["max_path_points"] = maxi(
			int(report["max_path_points"]), int(settle.get("sample_count", 0))
		)
		report["used_multi_y_path"] = (
			bool(report["used_multi_y_path"])
			or bool(settle.get("used_multi_y_path", false))
		)
		_append_report_event(
			report,
			phase,
			"route_chosen",
			"Rallied the visible party toward %s" % label,
			{
				"target_token": str(ground.get("token", "")),
				"screen": [point.x, point.y],
				"rally_event_count": rally_events,
				"movement_samples": int(settle.get("sample_count", 0)),
			}
		)
	elif visible_whole_refusal:
		(report["refused_actions"] as Array).append({
			"surface": label,
			"failure": "player_facing_rally_refused",
			"receipt": rally_receipt.duplicate(true),
			"player_observable_feedback": true,
		})
	else:
		(report["atomic_rally_failures"] as Array).append({
			"surface": label,
			"failure": (
				"missing_all_member_visible_motion"
				if accepted_atomic and visible_commit
				else "missing_exact_movement_result_lineage"
				if bool(rally_receipt.get("atomic_group", false))
				else "non_atomic_rally_receipt"
			),
			"receipt": rally_receipt.duplicate(true),
		})
	var rally_after_v: Variant = settle.get("observation", {})
	if not (rally_after_v is Dictionary) or (rally_after_v as Dictionary).is_empty():
		rally_after_v = _player_observation_snapshot(observer, watchdog)
	var rally_after := rally_after_v as Dictionary \
		if rally_after_v is Dictionary else {}
	_append_visible_decision_record(
		report,
		decision_observation,
		"Use one held-RMB Rally to move every visible party member toward the chosen floor pixel.",
		[
			"visible_ground_frontier",
			"atomic_whole_party_rally",
			"await_all_presented_movement_and_full_xyz",
		],
		{
			"verb": "rally",
			"kind": "rally" if accepted_visible else (
				"rally_refused" if visible_whole_refusal else "rally_unverified"),
			"target_token": target_token,
			"screen": [point.x, point.y],
			"surface": label,
			"hover_consequence": str(ground.get("consequence", "")),
		},
		rally_receipt,
		rally_after,
		true,
		rally_receipt.get("intended_members", []).duplicate(),
		settle.get("observation_samples", []).duplicate(true)
	)
	return {
		"accepted": accepted_visible,
		"verified_atomic": accepted_atomic,
		"visible_motion_verified": visible_motion_verified,
		"whole_refusal": visible_whole_refusal,
		"movement_result": movement_result.duplicate(true),
		"sample_count": int(settle.get("sample_count", 0)),
		"watchdog_abort_reason": str(settle.get(
			"watchdog_abort_reason", "")),
		"receipt": rally_receipt,
	}


func _choose_observed_interaction(
	observation: Dictionary,
	policy: String,
	attempted_epoch: Dictionary,
	completed_tokens: Dictionary,
	completed_semantics: Dictionary,
	retryable_tokens: Dictionary,
	attempt_counts: Dictionary,
	epoch: int
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var carrying_visible_resource := _player_observation_has_visible_carry(
		observation
	)
	# A prior refused click can expose a concrete, player-facing dependency such
	# as `RESOLVE FIRST // EXTEND`. Treat that visible instruction as stronger
	# evidence than the usual exit bias. This is the same correction a person
	# makes after reading the refusal; it does not inspect the generated graph or
	# private progression state.
	var requested_title := _player_observation_resolve_target_label(observation)
	for affordance in _player_observation_affordances(observation, "interact"):
		var token := str(affordance.get("token", ""))
		if token == "" or completed_tokens.has(token):
			continue
		var point := _player_observation_screen_point(affordance)
		if not _player_observation_safe_action_point(observation, point):
			continue
		var visible_copy := (
			str(affordance.get("verb", ""))
			+ " "
			+ str(affordance.get("consequence", ""))
		).to_lower()
		var score := -int(roundf(
			_player_observation_distance_to_party(observation, affordance)
		))
		var risk_score := _player_visible_risk_score(visible_copy)
		var is_resource := _copy_contains_any(
			visible_copy, ["lysate", "cache", "salvage", "take", "carry"]
		)
		var is_exit := _copy_contains_any(
			visible_copy, ["rest", "shelter", "exit", "arrival"]
		)
		var attempted_this_epoch := int(attempted_epoch.get(token, -1)) == epoch
		if attempted_this_epoch and not (
			is_exit
			and bool(retryable_tokens.get(token, false))
			and int(attempt_counts.get(token, 0)) \
				< PLAYER_DISCOVERY_MAX_VISIBLE_RETRIES
		):
			continue
		var semantic_key := _player_observation_surface_semantic_key(affordance)
		var resolves_visible_cue := requested_title != "" \
			and visible_copy.contains(requested_title.to_lower())
		if is_resource and (
			carrying_visible_resource or completed_semantics.has(semantic_key)
		):
			# The visible carried-item receipt is enough information for a human
			# player to stop vacuuming every optional cache and return to the causal
			# route. The memory is semantic so reframing the camera cannot make the
			# same already-solved TAKE decision look new.
			continue
		if policy == "risk_seeking":
			score += risk_score * 450
			score += 1200 if is_resource else 0
			score -= 900 if is_exit else 0
		else:
			score += risk_score * 80
			score += 420 if is_resource else 0
			# Trying the plainly marked exit is an informative human action. An early
			# attempt yields the shipped RESOLVE FIRST cue; suppressing it kept the
			# agent wandering arbitrary floor forever instead of learning the level's
			# visible dependency.
			score += 700 if is_exit else 0
			score += 160 if _copy_contains_any(
				visible_copy, ["plant", "flure", "operate", "open", "use"]
			) else 0
		if resolves_visible_cue:
			# This must outrank the deliberately informative +700 exit attempt,
			# otherwise the agent retries the locked shelter with each portrait
			# instead of following the correction it can plainly see.
			score += 4000
		score -= int(attempt_counts.get(token, 0)) * 120
		var scored := affordance.duplicate(true)
		scored["policy_score"] = score
		scored["resolves_visible_cue"] = resolves_visible_cue
		candidates.append(scored)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("policy_score", 0)) != int(b.get("policy_score", 0)):
			return int(a.get("policy_score", 0)) > int(b.get("policy_score", 0))
		return str(a.get("token", "")) < str(b.get("token", ""))
	)
	return candidates[0] if not candidates.is_empty() else {}


func _choose_observed_ground_near_interaction(
	observation: Dictionary,
	interaction: Dictionary,
	alternative_index := 0,
	stalled_ground := {}
) -> Dictionary:
	var target_point := _player_observation_screen_point(interaction)
	if not target_point.is_finite():
		return {}
	var candidates := _player_observation_affordances(observation, "move")
	var ranked: Array[Dictionary] = []
	for ground in candidates:
		var ground_token := str(ground.get("token", ""))
		if ground_token == "" or stalled_ground.has(ground_token) \
				or str(ground.get("consequence", "")).to_upper().contains(
					"NO ROUTE"):
			continue
		var point := _player_observation_screen_point(ground)
		if not _player_observation_safe_action_point(observation, point):
			continue
		var scored := ground.duplicate(true)
		scored["interaction_screen_distance"] = point.distance_to(target_point)
		ranked.append(scored)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
			float(a.get("interaction_screen_distance", INF)),
			float(b.get("interaction_screen_distance", INF))
		):
			return float(a.get("interaction_screen_distance", INF)) \
				< float(b.get("interaction_screen_distance", INF))
		return str(a.get("token", "")) < str(b.get("token", ""))
	)
	if ranked.is_empty():
		return {}
	# A visible location refusal means the first formation landed on the wrong side
	# of the trigger. Humans retry from another nearby floor patch; cycling the
	# ranked screen-space candidates reproduces that behavior without reading an
	# authored shelter center or navigation coordinate.
	return ranked[mini(maxi(0, alternative_index), ranked.size() - 1)]


func _choose_observed_frontier_ground(
	observation: Dictionary, stalled_ground: Dictionary, decision_index: int
) -> Dictionary:
	var grounds := _player_observation_affordances(observation, "move")
	var cue_target := _player_observation_resolve_target_screen(observation)
	var candidates: Array[Dictionary] = []
	for ground in grounds:
		var token := str(ground.get("token", ""))
		if token == "" or stalled_ground.has(token) \
				or str(ground.get("consequence", "")).to_upper().contains("NO ROUTE"):
			continue
		var scored := ground.duplicate(true)
		var point := _player_observation_screen_point(ground)
		if not _player_observation_safe_action_point(observation, point):
			continue
		var party_distance := _player_observation_distance_to_party(
			observation, ground
		)
		var score := party_distance
		if cue_target.is_finite():
			score = 2000.0 - point.distance_to(cue_target)
		# Deterministic tie-break rotation prevents a symmetric camera from always
		# selecting the same dead-end edge pixel.
		scored["frontier_score"] = score
		scored["tie_break"] = absi(hash("%s:%d" % [token, decision_index]))
		candidates.append(scored)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
			float(a.get("frontier_score", 0.0)),
			float(b.get("frontier_score", 0.0))
		):
			return float(a.get("frontier_score", 0.0)) \
				> float(b.get("frontier_score", 0.0))
		return int(a.get("tie_break", 0)) < int(b.get("tie_break", 0))
	)
	return candidates[0] if not candidates.is_empty() else {}


func _generated_camera_recovery_verb(receipt: Dictionary) -> String:
	match str(receipt.get("kind", "")):
		"recenter":
			return "camera_recenter"
		"zoom_out":
			return "camera_zoom"
		"rotate_camera":
			return "camera_rotate"
		"key":
			if int(receipt.get("keycode", 0)) in [KEY_W, KEY_A, KEY_S, KEY_D]:
				return "camera_pan"
	return ""


func _drive_observed_camera_recovery(driver: Node, recovery_index: int) -> Dictionary:
	match recovery_index:
		0:
			return await driver.call("recenter")
		1:
			return await driver.call("zoom_out", 4)
		2:
			# At 1.6 rad/s this is a human-scale quarter turn. The former
			# ~41-degree probe could leave a lateral Rally formation partially
			# hidden behind shelter dressing from both sampled sides.
			return await driver.call("rotate_camera", "left", 1.0)
		3:
			# Cross the starting yaw so the two attempts inspect both broadside
			# views with one continuous shipped gesture apiece.
			return await driver.call("rotate_camera", "right", 2.0)
		4:
			# Spiral side dressing can hide the whole party at both +/-90 degrees.
			# Continue the same ordinary right hold to inspect the opposite radial
			# face at 180 degrees before trying translational recovery.
			return await driver.call("rotate_camera", "right", 1.0)
		5:
			return await driver.call("recenter")
		6:
			return await driver.call("press_key", KEY_W, 6)
		_:
			return await driver.call("press_key", KEY_D, 6)


func _wait_for_observed_interaction_feedback(
	preview_instance: Node,
	observer: Node,
	before: Dictionary,
	result: Dictionary,
	phase: String,
	label: String,
	target_token: String,
	baseline_presentation_serial: int,
	discovery_report: Dictionary,
	watchdog: Dictionary,
	immediate_post_input_observation := {}
) -> Dictionary:
	var elapsed := 0.0
	var latest := before
	var last_valid_progress_observation := before
	var captured_observations: Array = []
	var immediate_pending := immediate_post_input_observation is Dictionary \
		and not (immediate_post_input_observation as Dictionary).is_empty()
	while elapsed < minf(PHYSICAL_INTERACTION_TIMEOUT, 12.0):
		var watchdog_abort_reason := _player_discovery_watchdog_abort_reason(
			watchdog)
		if watchdog_abort_reason != "":
			_set_player_discovery_watchdog_pending(
				watchdog, watchdog_abort_reason)
			return {
				"observation": latest,
				"observation_samples": _observations_before_terminal(
					captured_observations),
				"target_result": {},
				"watchdog_abort_reason": watchdog_abort_reason,
			}
		_emit_player_discovery_heartbeat(
			discovery_report, watchdog,
			int(discovery_report.get("policy_iteration_count", 0)),
			"interaction_wait")
		var step := 0.0
		var snapshot_v: Variant = null
		if immediate_pending:
			snapshot_v = immediate_post_input_observation
			immediate_pending = false
		else:
			step = 0.1
			await preview_instance.get_tree().create_timer(
				step, true, false, false
			).timeout
			snapshot_v = _player_observation_snapshot(observer, watchdog)
		if snapshot_v is Dictionary:
			var candidate := snapshot_v as Dictionary
			if PersonaDecisionTraceScript.validate_player_observation(
					candidate).is_empty():
				var latest_capture_serial := int(candidate.get("capture_serial", 0))
				var last_capture_serial := int(before.get("capture_serial", 0)) \
					if captured_observations.is_empty() else int(
						(captured_observations[-1] as Dictionary).get(
							"capture_serial", 0))
				if latest_capture_serial > last_capture_serial:
					captured_observations.append(candidate.duplicate(true))
					latest = candidate
				_consider_player_discovery_observation_progress(
					watchdog, last_valid_progress_observation, latest,
					"interaction_visible_change")
				last_valid_progress_observation = latest
		var target_result := _player_observation_target_result(
			latest, target_token
		)
		_record_animation_snapshot(
			result,
			preview_instance,
			phase,
			"Interacting with %s" % label,
			{
				"event_type": "player_interaction_in_flight",
				"surface": label,
				"observation_schema": PLAYER_DISCOVERY_OBSERVATION_SCHEMA,
			}
		)
		elapsed += step
		if int(target_result.get("presentation_serial", 0)) \
				> baseline_presentation_serial \
				and str(target_result.get("source_token", "")) == target_token \
				and bool(target_result.get("visible", false)) \
				and str(target_result.get("result", "")) in ["success", "rejected"]:
			_note_player_discovery_visible_progress(
				watchdog, "interaction_exact_target_result")
			return {
				"observation": latest,
				"observation_samples": _observations_before_terminal(
					captured_observations),
				"target_result": target_result.duplicate(true),
				"watchdog_abort_reason": "",
			}
	_set_player_discovery_watchdog_pending(
		watchdog, "interaction_exact_result_timeout")
	return {
		"observation": latest,
		"observation_samples": _observations_before_terminal(
			captured_observations),
		"target_result": {},
		"watchdog_abort_reason": "interaction_exact_result_timeout",
	}


func _observations_before_terminal(observations: Array) -> Array:
	var samples := observations.duplicate(true)
	if not samples.is_empty():
		samples.pop_back()
	return samples


func _player_observation_target_result(
		observation: Dictionary, target_token: String
	) -> Dictionary:
	if target_token == "":
		return {}
	var newest: Dictionary = {}
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return newest
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "interaction_result" \
				or str(cue.get("source_token", "")) != target_token \
				or not bool(cue.get("visible", false)) \
				or str(cue.get("result", "")) not in ["success", "rejected"]:
			continue
		if int(cue.get("presentation_serial", 0)) \
				> int(newest.get("presentation_serial", 0)):
			newest = cue.duplicate(true)
	return newest


func _target_result_is_new_visible_success(
		target_result: Dictionary,
		target_token: String,
		baseline_presentation_serial: int
	) -> bool:
	return target_token != "" \
		and str(target_result.get("source_token", "")) == target_token \
		and bool(target_result.get("visible", false)) \
		and str(target_result.get("result", "")) == "success" \
		and int(target_result.get("presentation_serial", 0)) \
			> baseline_presentation_serial


func _player_observation_affordances(
	observation: Dictionary, kind: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = observation.get("state", {})
	for record_v in state.get("affordances", []):
		if record_v is Dictionary \
				and str((record_v as Dictionary).get("kind", "")) == kind:
			result.append((record_v as Dictionary).duplicate(true))
	return result


func _observed_affordance_by_token(
	observation: Dictionary, token: String
) -> Dictionary:
	var state: Dictionary = observation.get("state", {})
	for record_v in state.get("affordances", []):
		if record_v is Dictionary \
				and str((record_v as Dictionary).get("token", "")) == token:
			return (record_v as Dictionary).duplicate(true)
	return {}


## Human-faithful pointer precommit. Move the app-local pointer first, wait for
## the rendered hover, then take a fresh public observation and require exactly
## one copy of the already-chosen opaque token at the actual MouseMotion pixel.
## This helper never sees a node, camera, collider, transform, or world position.
func _hover_and_rebind_observed_affordance(
		driver: Node,
		observer: Node,
		decision_observation: Dictionary,
		chosen_affordance: Dictionary,
		watchdog: Dictionary
	) -> Dictionary:
	var target_token := str(chosen_affordance.get("token", ""))
	var target_kind := str(chosen_affordance.get("kind", ""))
	var target_verb := str(chosen_affordance.get("verb", ""))
	var target_consequence := str(chosen_affordance.get("consequence", ""))
	var chosen_point := _player_observation_screen_point(chosen_affordance)
	var result := {
		"valid": false,
		"reason": "visible_target_rebind_failed",
		"decision_capture_serial": int(
			decision_observation.get("capture_serial", 0)),
		"observation": decision_observation.duplicate(true),
		"affordance": {},
		"point": Vector2.INF,
		"hover_receipt": {},
	}
	if driver == null or not driver.has_method("hover_screen"):
		result["reason"] = "rendered_hover_driver_unavailable"
		return result
	if target_token == "" or target_kind not in ["move", "interact"] \
			or not _player_observation_safe_action_point(
				decision_observation, chosen_point):
		result["reason"] = "chosen_visible_target_has_no_safe_hover_pixel"
		return result
	var hover_receipt_v: Variant = await driver.call(
		"hover_screen", chosen_point, target_token)
	var hover_receipt := hover_receipt_v as Dictionary \
		if hover_receipt_v is Dictionary else {}
	result["hover_receipt"] = hover_receipt.duplicate(true)
	if not bool(hover_receipt.get("accepted", false)) \
			or not bool(hover_receipt.get("input_issued", false)) \
			or not bool(hover_receipt.get("rendered_hover_waited", false)):
		result["reason"] = "rendered_hover_input_not_presented"
		return result
	var actual_point := _driver_hover_receipt_point(hover_receipt)
	result["point"] = actual_point
	if not actual_point.is_finite():
		result["reason"] = "rendered_hover_receipt_has_no_exact_pixel"
		return result
	# This is the only awaited observation between MouseMotion and the world
	# button edge. The caller synchronously dispatches its from-rendered-hover API
	# after this helper returns; no process/render frame is yielded in between.
	var rebound_observation_v: Variant = _player_observation_snapshot(
		observer, watchdog)
	if not (rebound_observation_v is Dictionary):
		result["reason"] = "missing_post_hover_player_observation"
		return result
	var rebound_observation := rebound_observation_v as Dictionary
	result["observation"] = rebound_observation.duplicate(true)
	result["rebind_diagnostic"] = _observed_affordance_rebind_diagnostic(
		rebound_observation, target_token, actual_point)
	var observation_issues: Array[String] = \
		PersonaDecisionTraceScript.validate_player_observation(
			rebound_observation)
	if not observation_issues.is_empty():
		result["reason"] = "invalid_post_hover_player_observation:%s" \
			% str(observation_issues)
		return result
	if int(rebound_observation.get("capture_serial", 0)) <= int(
			decision_observation.get("capture_serial", 0)):
		result["reason"] = "post_hover_observation_is_not_fresh"
		return result
	var rebound_affordance := _observed_exact_affordance_at_pointer(
		rebound_observation, target_token, target_kind,
		target_verb, target_consequence, actual_point)
	if rebound_affordance.is_empty():
		result["reason"] = "exact_visible_token_not_rebound_at_hover_pixel"
		result["rebind_frame_path"] = _capture_hover_rebind_frame(
			observer, target_token,
			int(rebound_observation.get("capture_serial", 0)))
		return result
	result["valid"] = true
	result["reason"] = ""
	result["affordance"] = rebound_affordance.duplicate(true)
	return result


func _observed_affordance_rebind_diagnostic(
		observation: Dictionary, target_token: String, actual_point: Vector2
	) -> Dictionary:
	# Failure receipts may preserve only public, policy-visible facts. Keeping the
	# exact token and exact-pointer matches makes a rejected hover reproducible
	# without exposing a collider, camera transform, or world coordinate.
	var token_matches: Array = []
	var pointer_matches: Array = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return {
			"capture_serial": int(observation.get("capture_serial", 0)),
			"target_token": target_token,
			"actual_pointer": [actual_point.x, actual_point.y],
			"token_matches": token_matches,
			"pointer_matches": pointer_matches,
		}
	for affordance_v in (state_v as Dictionary).get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		var screen_point := _player_observation_screen_point(affordance)
		var public_record := {
			"token": str(affordance.get("token", "")),
			"kind": str(affordance.get("kind", "")),
			"verb": str(affordance.get("verb", "")),
			"consequence": str(affordance.get("consequence", "")),
			"screen": affordance.get("screen", []).duplicate() \
				if affordance.get("screen", null) is Array else [],
		}
		if str(affordance.get("token", "")) == target_token:
			token_matches.append(public_record.duplicate(true))
		if screen_point.is_equal_approx(actual_point):
			pointer_matches.append(public_record.duplicate(true))
	return {
		"capture_serial": int(observation.get("capture_serial", 0)),
		"target_token": target_token,
		"actual_pointer": [actual_point.x, actual_point.y],
		"token_matches": token_matches,
		"pointer_matches": pointer_matches,
	}


func _capture_hover_rebind_frame(
		observer: Node, target_token: String, capture_serial: int
	) -> String:
	# A failed target rebind retains the same framebuffer a person was looking at.
	# It is diagnostic evidence only and never feeds target selection or authority.
	if observer == null:
		return ""
	var viewport := observer.get_viewport()
	if viewport == null or viewport.get_texture() == null:
		return ""
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return ""
	var safe_token := target_token.validate_filename()
	var user_path := "user://hover_rebind_%s_%d.png" % [
		safe_token, capture_serial]
	if image.save_png(user_path) != OK:
		return ""
	return ProjectSettings.globalize_path(user_path)


func _driver_hover_receipt_point(receipt: Dictionary) -> Vector2:
	var events_v: Variant = receipt.get("input_events", [])
	if not (events_v is Array) or (events_v as Array).size() != 1:
		return Vector2.INF
	var event_v: Variant = (events_v as Array)[0]
	if not (event_v is Dictionary):
		return Vector2.INF
	var event := event_v as Dictionary
	var position_v: Variant = event.get("position", [])
	if str(event.get("kind", "")) != "pointer_move" \
			or not bool(event.get("issued", false)) \
			or int(event.get("button_mask", -1)) != 0 \
			or not (position_v is Array) \
			or (position_v as Array).size() != 2:
		return Vector2.INF
	var point := Vector2(
		float((position_v as Array)[0]), float((position_v as Array)[1]))
	return point if point.is_finite() else Vector2.INF


func _observed_exact_affordance_at_pointer(
		observation: Dictionary,
		target_token: String,
		target_kind: String,
		target_verb: String,
		target_consequence: String,
		actual_point: Vector2
	) -> Dictionary:
	var matches: Array[Dictionary] = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return {}
	for affordance_v in (state_v as Dictionary).get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		if str(affordance.get("token", "")) == target_token \
				and str(affordance.get("kind", "")) == target_kind \
				and str(affordance.get("verb", "")) == target_verb \
				and str(affordance.get("consequence", "")) \
					== target_consequence:
			matches.append(affordance)
	if matches.size() != 1:
		return {}
	var match := matches[0]
	var rebound_point := _player_observation_screen_point(match)
	if not rebound_point.is_equal_approx(actual_point) \
			or not _player_observation_safe_action_point(
				observation, rebound_point):
		return {}
	return match.duplicate(true)


## A failed hover rebind is still an ordinary human input and therefore belongs
## in the same globally ordered trace as every subsequent decision. It remains
## presentation-only and permanently ineligible for gameplay learning; no RMB
## world edge follows the ambiguous/stale token.
func _record_observed_hover_rebind_failure(
		report: Dictionary,
		observation_before: Dictionary,
		observation_after: Dictionary,
		hover_receipt: Dictionary,
		chosen_affordance: Dictionary,
		intended_world_verb: String,
		label: String,
		reason: String
	) -> bool:
	var target_token := str(chosen_affordance.get("token", ""))
	var hover_events := hover_receipt.get("input_events", []) as Array \
		if hover_receipt.get("input_events", null) is Array else []
	var pointer_motion_only := hover_events.size() == 1 \
		and hover_events[0] is Dictionary \
		and str((hover_events[0] as Dictionary).get("kind", "")) \
			== "pointer_move"
	var before_capture_serial := int(observation_before.get("capture_serial", 0))
	var after_capture_serial := int(observation_after.get("capture_serial", 0))
	var ordered_input := bool(hover_receipt.get("player_reproducible", false)) \
		and bool(hover_receipt.get("input_issued", false)) \
		and pointer_motion_only \
		and after_capture_serial > before_capture_serial \
		and PersonaDecisionTraceScript.validate_player_observation(
			observation_after).is_empty()
	var ordered_decision_index := (report.get("visible_decisions", []) as Array).size()
	if ordered_input:
		_append_visible_decision_record(
			report,
			observation_before,
			"Aim the ordinary pointer at the chosen visible target, then stop and re-observe if the rendered target no longer matches.",
			[
				"visible_target_chosen",
				"rendered_hover",
				"rebind_refused_before_world_input",
			],
			{
				"verb": "hover",
				"kind": "hover_pointer",
				"target_token": target_token,
				"target_kind": str(chosen_affordance.get("kind", "")),
				"target_verb": str(chosen_affordance.get("verb", "")),
				"target_consequence": str(
					chosen_affordance.get("consequence", "")),
				"screen": chosen_affordance.get("screen", []).duplicate() \
					if chosen_affordance.get("screen", null) is Array else [],
				"intended_world_verb": intended_world_verb,
				"surface": label,
				"rebind_outcome": reason,
			},
			hover_receipt,
			observation_after,
			false,
			[]
		)
	var record := {
		"schema": "presentation_only_hover_decision_v1",
		"classification": "presentation_only_human_reproducible",
		"decision_index": (report.get(
			"presentation_only_decisions", []) as Array).size(),
		"ordered_decision_index": ordered_decision_index \
			if ordered_input else -1,
		"observation_before": PersonaDecisionTraceScript.json_safe(
			observation_before),
		"observation_after": PersonaDecisionTraceScript.json_safe(
			observation_after),
		"decision": {
			"verb": "hover",
			"intended_world_verb": intended_world_verb,
			"world_change": false,
			"target": {"kind": "visible_surface", "token": target_token},
			"surface": label,
		},
		"receipt": hover_receipt.duplicate(true),
		"outcome": {
			"status": "rebind_refused",
			"reason": reason,
			"world_input_issued": false,
			"presentation_input_issued": bool(
				hover_receipt.get("input_issued", false)),
		},
		"player_reproducible": bool(
			hover_receipt.get("player_reproducible", false)) \
			and bool(hover_receipt.get("input_issued", false)) \
			and pointer_motion_only,
		"eligible_for_learning": false,
	}
	var records := report.get("presentation_only_decisions", []) as Array
	records.append(PersonaDecisionTraceScript.json_safe(record))
	report["presentation_only_decisions"] = records
	return ordered_input


## Camera follow can still be easing after a routed Rally reaches its terminal
## movement receipt, especially on a warped spiral. Ground tokens name fixed
## screen bins, so their own pixels are tautologically stable while the world
## slides beneath them. Wait for the complete public projection (visible party
## bodies plus pointer affordances) to repeat across completed draws, while the
## chosen token retains its exact public action semantics. This never discovers a
## replacement target or reads a camera transform/private world coordinate.
func _await_observed_affordance_action_stability(
		observer: Node,
		target_token: String,
		initial_observation: Dictionary,
		watchdog: Dictionary = {},
		max_samples := 30,
		required_stable_samples := 3
	) -> Dictionary:
	if observer == null or target_token == "":
		return {}
	var current_observation := initial_observation
	var current_affordance := _observed_affordance_by_token(
		current_observation, target_token)
	if current_affordance.is_empty():
		return {}
	var expected_kind := str(current_affordance.get("kind", ""))
	var expected_verb := str(current_affordance.get("verb", ""))
	var expected_consequence := str(current_affordance.get("consequence", ""))
	var last_projection_signature := \
		_player_observation_projection_signature(current_observation)
	var last_capture_serial := int(current_observation.get("capture_serial", 0))
	var stable_samples := 0
	for _sample_index in range(maxi(1, max_samples)):
		var observation_tree := observer.get_tree()
		if observation_tree == null:
			return {}
		await observation_tree.create_timer(0.05, true, false, false).timeout
		await RenderingServer.frame_post_draw
		var next_observation_v: Variant = _player_observation_snapshot(
			observer, watchdog)
		if not (next_observation_v is Dictionary):
			stable_samples = 0
			continue
		var next_observation := next_observation_v as Dictionary
		if not PersonaDecisionTraceScript.validate_player_observation(
				next_observation).is_empty():
			stable_samples = 0
			continue
		var next_capture_serial := int(next_observation.get("capture_serial", 0))
		if next_capture_serial <= last_capture_serial:
			stable_samples = 0
			continue
		last_capture_serial = next_capture_serial
		var next_affordance := _observed_affordance_by_token(
			next_observation, target_token)
		if next_affordance.is_empty():
			return {}
		if str(next_affordance.get("kind", "")) != expected_kind \
				or str(next_affordance.get("verb", "")) != expected_verb \
				or str(next_affordance.get("consequence", "")) \
					!= expected_consequence:
			return {}
		var next_projection_signature := \
			_player_observation_projection_signature(next_observation)
		if next_projection_signature == "":
			# A visible accepted/progress movement cue or insufficient rendered
			# geometry means projection stability is not yet provable. Keep sampling
			# the same public target instead of falling through to its stale pixel.
			stable_samples = 0
		elif next_projection_signature == last_projection_signature:
			stable_samples += 1
		else:
			stable_samples = 1
		last_projection_signature = next_projection_signature
		current_observation = next_observation
		current_affordance = next_affordance
		if stable_samples >= maxi(3, required_stable_samples):
			return {
				"observation": current_observation.duplicate(true),
				"affordance": current_affordance.duplicate(true),
			}
	return {}


## Canonical, lossy screen-space signature used only to decide whether the same
## rendered view has stopped moving. Every retained field already crosses the
## player-observation boundary; transient HUD/cue timers are intentionally absent.
func _player_observation_projection_signature(observation: Dictionary) -> String:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return ""
	var state := state_v as Dictionary
	var records: Array = []
	var distinct_screens := {}
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var cue_kind := str(cue.get("kind", ""))
		if cue_kind == "movement_result" \
				and bool(cue.get("visible", false)) \
				and str(cue.get("phase", "")) in ["accepted", "progress"]:
			# Screen-relative body motion is not evidence that the camera settled
			# while a public movement acknowledgement says the party is still moving.
			return ""
		if cue_kind != "party_body" or not bool(cue.get("visible", false)):
			continue
		var body_screen: Array = cue.get("screen", []) \
			if cue.get("screen", null) is Array else []
		if body_screen.size() != 2:
			continue
		distinct_screens["%s:%s" % [str(body_screen[0]), str(body_screen[1])]] = true
		records.append({
			"class": "party_body",
			"token": str(cue.get("source_token", "")),
			"binding": str(cue.get("binding", "")),
			"screen": body_screen.duplicate(),
		})
	for affordance_v in state.get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		var kind := str(affordance.get("kind", ""))
		if kind != "interact":
			continue
		var interaction_screen: Array = affordance.get("screen", []) \
			if affordance.get("screen", null) is Array else []
		if interaction_screen.size() != 2:
			continue
		distinct_screens["%s:%s" % [
			str(interaction_screen[0]), str(interaction_screen[1])]] = true
		records.append({
			"class": "affordance",
			"token": str(affordance.get("token", "")),
			"screen": interaction_screen.duplicate(),
		})
	records.sort_custom(func(a: Variant, b: Variant) -> bool:
		return PersonaDecisionTraceScript.canonical_json(a) \
			< PersonaDecisionTraceScript.canonical_json(b))
	# A single pivot-centred presenter can remain fixed through yaw/zoom. Two
	# screen-distinct rendered anchors are the minimum public proof of projection
	# stability; fixed ground sampling bins never count as anchors.
	if records.size() < 2 or distinct_screens.size() < 2:
		return ""
	return PersonaDecisionTraceScript.canonical_json({
		"viewport": (state.get("viewport", {}) as Dictionary).duplicate(true),
		"records": records,
	})


func _player_observation_screen_point(record: Dictionary) -> Vector2:
	var screen: Array = record.get("screen", [])
	if screen.size() < 2:
		return Vector2.INF
	return Vector2(float(screen[0]), float(screen[1]))


func _player_observation_safe_action_point(
	observation: Dictionary, point: Vector2
) -> bool:
	# The camera's shipped edge-scroll owns every hard screen edge. Both a held
	# Rally and a short interaction must use the exact interior pixel verified by
	# the production pointer ray; otherwise selection/camera follow can move the
	# intended collider out from under a stale edge click.
	if not point.is_finite():
		return false
	var state: Dictionary = observation.get("state", {})
	var viewport: Dictionary = state.get("viewport", {})
	var origin_v: Array = viewport.get("origin", [0, 0])
	var size_v: Array = viewport.get("size", [0, 0])
	var origin := Vector2.ZERO
	var size := Vector2.ZERO
	if origin_v.size() >= 2:
		origin = Vector2(float(origin_v[0]), float(origin_v[1]))
	if size_v.size() >= 2:
		size = Vector2(float(size_v[0]), float(size_v[1]))
	if size.x <= 0.0 or size.y <= 0.0:
		return point.x >= PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX \
			and point.y >= PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX
	return point.x >= origin.x + PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX \
		and point.y >= origin.y + PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX \
		and point.x <= origin.x + size.x - PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX \
		and point.y <= origin.y + size.y - PLAYER_DISCOVERY_HOLD_EDGE_INSET_PX


func _player_observation_party_screens(observation: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var state: Dictionary = observation.get("state", {})
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary) \
				or str((cue_v as Dictionary).get("kind", "")) != "party_body":
			continue
		var point := _player_observation_screen_point(cue_v as Dictionary)
		if point.is_finite():
			points.append(point)
	return points


func _player_observation_distance_to_party(
	observation: Dictionary, record: Dictionary
) -> float:
	var point := _player_observation_screen_point(record)
	if not point.is_finite():
		return INF
	var best := INF
	for body_point in _player_observation_party_screens(observation):
		best = minf(best, point.distance_to(body_point))
	return best


func _player_observation_visible_signature(observation: Dictionary) -> String:
	var state: Dictionary = observation.get("state", {})
	var affordances: Array = []
	for record_v in state.get("affordances", []):
		if not (record_v is Dictionary):
			continue
		var record := record_v as Dictionary
		affordances.append({
			"token": str(record.get("token", "")),
			"kind": str(record.get("kind", "")),
			"verb": str(record.get("verb", "")),
			"consequence": str(record.get("consequence", "")),
		})
	var cues: Array = []
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary) \
				or str((cue_v as Dictionary).get("kind", "")) == "party_body":
			continue
		var cue := cue_v as Dictionary
		cues.append({
			"kind": str(cue.get("kind", "")),
			"text": str(cue.get("text", "")),
			"phase": str(cue.get("phase", "")),
			"destination": str(cue.get("destination", "")),
		})
	var hud: Dictionary = state.get("hud", {})
	var portraits: Array = []
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		portraits.append({
			"token": str(portrait.get("token", "")),
			"label": str(portrait.get("label", "")),
			"status": str(portrait.get("status", "")),
			"statuses": _player_observation_portrait_statuses(portrait),
			"hold": (portrait.get("hold", {}) as Dictionary).duplicate(true),
		})
	var hands: Array = hud.get("hands", []).duplicate()
	hands.sort()
	return JSON.stringify({
		"affordances": affordances,
		"cues": cues,
		"hud": {
			"portraits": portraits,
			"hands": hands,
			"run_label": str(hud.get("run_label", "")),
			"routing_label": str(hud.get("routing_label", "")),
		},
	})


## Rolling CI liveness is advanced only by presentation changes a person can
## actually see after shipped input. Deliberately omit scheduler/tick values,
## bars, viewport metadata, and ground-ray coordinates: those can churn without
## any new causal information. Party-body screen motion is retained because it
## is the literal visible evidence for travel.
func _player_observation_action_progress_signature(
		observation: Dictionary
	) -> String:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return ""
	var state := state_v as Dictionary
	var interaction_records: Array[String] = []
	for affordance_v in state.get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) != "interact":
			continue
		interaction_records.append(PersonaDecisionTraceScript.canonical_json({
			"token": str(affordance.get("token", "")),
			"kind": "interact",
			"verb": str(affordance.get("verb", "")),
			"consequence": str(affordance.get("consequence", "")),
		}))
	interaction_records.sort()
	var cue_records: Array[String] = []
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var cue_kind := str(cue.get("kind", ""))
		var cue_record := {
			"kind": cue_kind,
			"text": str(cue.get("text", "")),
			"state": str(cue.get("state", "")),
			"source_token": str(cue.get("source_token", "")),
			"binding": str(cue.get("binding", "")),
			"result": str(cue.get("result", "")),
			"presentation_serial": int(cue.get("presentation_serial", 0)),
			"visible": bool(cue.get("visible", false)),
		}
		if cue_kind == "party_body":
			var body_screen_v: Variant = cue.get("screen", [])
			cue_record["screen"] = (body_screen_v as Array).duplicate() \
				if body_screen_v is Array else []
		cue_records.append(PersonaDecisionTraceScript.canonical_json(cue_record))
	cue_records.sort()
	var hud_v: Variant = state.get("hud", {})
	var hud := hud_v as Dictionary if hud_v is Dictionary else {}
	var portrait_records: Array[String] = []
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		var hold_v: Variant = portrait.get("hold", {})
		portrait_records.append(PersonaDecisionTraceScript.canonical_json({
			"token": str(portrait.get("token", "")),
			"label": str(portrait.get("label", "")),
			"selected": bool(portrait.get("selected", false)),
			"status": str(portrait.get("status", "")),
			"statuses": _player_observation_portrait_statuses(portrait),
			"hold": (hold_v as Dictionary).duplicate(true) \
				if hold_v is Dictionary else {},
		}))
	portrait_records.sort()
	var hands: Array = hud.get("hands", []).duplicate()
	hands.sort()
	return PersonaDecisionTraceScript.canonical_json({
		"interaction_affordances": interaction_records,
		"cues": cue_records,
		"hud": {
			"portraits": portrait_records,
			"hands": hands,
			"run_label": str(hud.get("run_label", "")),
			"routing_label": str(hud.get("routing_label", "")),
			"message": str(hud.get("message", "")),
		},
	})


func _player_observation_portrait_statuses(portrait: Dictionary) -> Array[String]:
	var statuses: Array[String] = []
	var statuses_v: Variant = portrait.get("statuses", [])
	if not (statuses_v is Array):
		return statuses
	for status_v in statuses_v as Array:
		if not (status_v is String):
			continue
		var status := str(status_v)
		if status != "" and not statuses.has(status):
			statuses.append(status)
	statuses.sort()
	return statuses


func _player_observation_party_body_positions(observation: Dictionary) -> Dictionary:
	var state: Dictionary = observation.get("state", {})
	var positions := {}
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "party_body" \
				or not bool(cue.get("visible", false)):
			continue
		var token := str(cue.get("source_token", ""))
		var screen_v: Variant = cue.get("screen", [])
		if token != "" and screen_v is Array and (screen_v as Array).size() == 2:
			positions[token] = (screen_v as Array).duplicate()
	return positions


func _player_observation_party_body_signature(observation: Dictionary) -> String:
	return PersonaDecisionTraceScript.canonical_json(
		_player_observation_party_body_positions(observation))


func _player_observation_body_tokens_for_members(
		observation: Dictionary, intended_members: Array
	) -> Dictionary:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return {}
	var state := state_v as Dictionary
	var hud_v: Variant = state.get("hud", {})
	if not (hud_v is Dictionary):
		return {}
	var portrait_token_by_member := {}
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)):
			continue
		var member := str(portrait.get("label", "")).strip_edges() \
			.to_snake_case().to_lower()
		var portrait_token := str(portrait.get("token", ""))
		if member != "" and portrait_token != "":
			portrait_token_by_member[member] = portrait_token
	var body_token_by_binding := {}
	var duplicate_bindings := {}
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "party_body" \
				or not bool(cue.get("visible", false)):
			continue
		var binding := str(cue.get("binding", ""))
		var body_token := str(cue.get("source_token", ""))
		if binding == "" or body_token == "":
			continue
		if body_token_by_binding.has(binding):
			duplicate_bindings[binding] = true
		else:
			body_token_by_binding[binding] = body_token
	var result := {}
	for member_v in intended_members:
		var member := str(member_v).strip_edges().to_snake_case().to_lower()
		var portrait_token := str(portrait_token_by_member.get(member, ""))
		if portrait_token == "" or duplicate_bindings.has(portrait_token) \
				or not body_token_by_binding.has(portrait_token):
			continue
		result[member] = str(body_token_by_binding[portrait_token])
	return result


## Returns only exact, rendered HIDDEN portrait bindings. It deliberately does
## not infer concealment from a missing body, COVERED, camera framing, or any
## private character state.
func _player_observation_concealed_members(
		observation: Dictionary, intended_members: Array
	) -> Dictionary:
	var presence := _player_observation_exact_party_presence_bindings(observation)
	if not bool(presence.get("valid", false)):
		return {}
	var intended_set := {}
	for member_v in intended_members:
		var member := str(member_v).strip_edges().to_snake_case().to_lower()
		if member != "":
			intended_set[member] = true
	var labels_v: Variant = presence.get("portrait_labels", {})
	var modes_v: Variant = presence.get("presence_modes", {})
	if not (labels_v is Dictionary) or not (modes_v is Dictionary):
		return {}
	var labels := labels_v as Dictionary
	var modes := modes_v as Dictionary
	var result := {}
	var duplicate_members := {}
	for portrait_token_v in modes.keys():
		var portrait_token := str(portrait_token_v)
		var mode_v: Variant = modes.get(portrait_token_v, {})
		if not (mode_v is Dictionary) \
				or str((mode_v as Dictionary).get("mode", "")) != "rendered_hidden" \
				or str((mode_v as Dictionary).get("status", "")) != "HIDDEN":
			continue
		var member := str(labels.get(portrait_token_v, "")).strip_edges() \
			.to_snake_case().to_lower()
		if member == "" or not intended_set.has(member):
			continue
		if result.has(member):
			duplicate_members[member] = true
		else:
			result[member] = portrait_token
	for member_v in duplicate_members.keys():
		result.erase(member_v)
	return result


func _player_observation_member_body_token_visible(
		observation: Dictionary, member: String, body_token: String
	) -> bool:
	if member == "" or body_token == "":
		return false
	var bound := _player_observation_body_tokens_for_members(
		observation, [member])
	return str(bound.get(
		member.strip_edges().to_snake_case().to_lower(), "")) == body_token


func _player_observation_portrait_has_exact_hidden_presence(
		observation: Dictionary, portrait_token: String
	) -> bool:
	if portrait_token == "":
		return false
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return false
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return false
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if str(portrait.get("token", "")) != portrait_token \
				or not bool(portrait.get("visible", false)):
			continue
		var statuses_v: Variant = portrait.get("statuses", [])
		if not (statuses_v is Array):
			return false
		var statuses: Array[String] = []
		for status_v in statuses_v as Array:
			if not (status_v is String):
				return false
			var status := str(status_v)
			if status == "" or status != status.strip_edges() \
					or statuses.has(status):
				return false
			statuses.append(status)
		var sorted_statuses := statuses.duplicate()
		sorted_statuses.sort()
		return statuses == sorted_statuses and statuses.has("HIDDEN") \
			and not statuses.has("COVERED")
	return false


func _player_observation_portrait_tokens_for_members(
		observation: Dictionary, intended_members: Array
	) -> Array[String]:
	var result: Array[String] = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return result
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return result
	var token_by_member := {}
	var duplicate_members := {}
	var duplicate_tokens := {}
	var seen_tokens := {}
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)):
			continue
		var member := str(portrait.get("label", "")).strip_edges() \
			.to_snake_case().to_lower()
		var token := str(portrait.get("token", ""))
		if member == "" or token == "":
			continue
		if token_by_member.has(member):
			duplicate_members[member] = true
		else:
			token_by_member[member] = token
		if seen_tokens.has(token):
			duplicate_tokens[token] = true
		else:
			seen_tokens[token] = true
	for member_v in intended_members:
		var member := str(member_v).strip_edges().to_snake_case().to_lower()
		var token := str(token_by_member.get(member, ""))
		if token == "" or duplicate_members.has(member) \
				or duplicate_tokens.has(token):
			return []
		result.append(token)
	result.sort()
	return result


func _highest_visible_movement_result_serial(observation: Dictionary) -> int:
	var highest := 0
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return highest
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) == "movement_result" \
				and bool(cue.get("visible", false)):
			highest = maxi(highest, int(cue.get(
				"presentation_serial", 0)))
	return highest


func _player_observation_member_body_signature(
		observation: Dictionary, member_body_tokens: Dictionary
	) -> String:
	var all_positions := _player_observation_party_body_positions(observation)
	var exact_positions := {}
	for member_v in member_body_tokens.keys():
		var member := str(member_v)
		var body_token := str(member_body_tokens.get(member_v, ""))
		exact_positions[member] = all_positions.get(body_token, null)
	return PersonaDecisionTraceScript.canonical_json(exact_positions)


func _player_observation_feedback_text(observation: Dictionary) -> String:
	var texts: Array[String] = []
	var state: Dictionary = observation.get("state", {})
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) not in [
			"hud", "consequence", "instruction"
		]:
			continue
		var text := str(cue.get("text", "")).strip_edges()
		if text != "" and not texts.has(text):
			texts.append(text)
	return " | ".join(texts)


func _player_observation_surface_semantic_key(surface: Dictionary) -> String:
	var copy := (
		str(surface.get("verb", ""))
		+ " "
		+ str(surface.get("consequence", ""))
	).strip_edges().to_lower()
	if _copy_contains_any(copy, ["lysate", "cache", "salvage", "take", "carry"]):
		return "resource_claim"
	if _copy_contains_any(copy, ["rest", "shelter", "exit", "arrival"]):
		return "exit_shelter"
	return copy


func _player_observation_has_visible_carry(observation: Dictionary) -> bool:
	var state: Dictionary = observation.get("state", {})
	var hud: Dictionary = state.get("hud", {})
	if not (hud.get("hands", []) as Array).is_empty():
		return true
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var hold_v: Variant = (portrait_v as Dictionary).get("hold", {})
		if not (hold_v is Dictionary) or (hold_v as Dictionary).is_empty():
			continue
		var hold := hold_v as Dictionary
		if str(hold.get("kind", "")).to_lower() == "carried_item" \
				or str(hold.get("label", "")).strip_edges() != "":
			return true
	var visible_feedback := _player_observation_feedback_text(observation).to_lower()
	return _copy_contains_any(
		visible_feedback,
		["held by", "carrying", "hands full", "hand slots full"]
	)


func _player_surface_requires_party_selection(visible_copy: String) -> bool:
	return _copy_contains_any(
		visible_copy,
		["shelter", "rest", "party arrival", "gather party", "regroup"]
	)


func _player_observation_reads_as_success(observation: Dictionary) -> bool:
	return _copy_contains_any(
		_player_observation_feedback_text(observation).to_lower(),
		[
			"stretch complete",
			"shelter secured",
			"canonical shelter rest has started",
			"ready party reached shelter",
		]
	)


func _feedback_requests_visible_reapproach(feedback: String) -> bool:
	return _copy_contains_any(
		feedback.to_lower(),
		[
			"no reachable interaction point",
			"unreachable",
			"no route",
			"outside the authored exit shelter",
			"committed to another action",
			"previous change has not taken effect",
			"arrival is not complete",
		]
	)


func _player_observation_resolve_target_label(
	observation: Dictionary
) -> String:
	var state: Dictionary = observation.get("state", {})
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var text := str((cue_v as Dictionary).get("text", ""))
		var marker := text.to_upper().find("RESOLVE FIRST //")
		if marker >= 0:
			var label := text.substr(
				marker + len("RESOLVE FIRST //")
			).strip_edges()
			# The HUD composes the actionable instruction with contextual party
			# feedback (for example `EXTEND | Aster — ...`). Only the immediate
			# label names the next visible affordance. Preserve spaces inside a
			# multi-word title while stopping at presentation separators.
			var label_end := label.length()
			for separator in ["|", "\r", "\n"]:
				var separator_index := label.find(separator)
				if separator_index >= 0:
					label_end = mini(label_end, separator_index)
			return label.substr(0, label_end).strip_edges()
	return ""


func _player_observation_has_visible_run_control(
	observation: Dictionary
) -> bool:
	var state: Dictionary = observation.get("state", {})
	var hud: Dictionary = state.get("hud", {})
	return str(hud.get("run_label", "")).strip_edges().to_upper() in [
		"WALK", "RUN",
	]


func _player_discovery_should_enable_visible_run(
	policy: String,
	observation: Dictionary
) -> bool:
	return policy in ["first_read", "risk_seeking"] \
		and _player_observation_has_visible_run_control(observation)


func _player_observation_resolve_target_screen(
	observation: Dictionary
) -> Vector2:
	var state: Dictionary = observation.get("state", {})
	var requested_title := _player_observation_resolve_target_label(observation)
	if requested_title == "":
		return Vector2.INF
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "world_text" \
				or not str(cue.get("text", "")).to_upper().contains(
					requested_title.to_upper()
				):
			continue
		return _player_observation_screen_point(cue)
	return Vector2.INF


func _player_observation_digest(observation: Dictionary) -> Dictionary:
	var state: Dictionary = observation.get("state", {})
	var interactions: Array = []
	var move_count := 0
	for affordance_v in state.get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) == "move":
			move_count += 1
		elif str(affordance.get("kind", "")) == "interact":
			interactions.append({
				"token": str(affordance.get("token", "")),
				"verb": str(affordance.get("verb", "")),
				"consequence": str(affordance.get("consequence", "")),
				"screen": affordance.get("screen", []).duplicate(),
			})
	return {
		"schema": str(observation.get("schema", "")),
		"source": str(observation.get("source", "")),
		"interaction_affordances": interactions,
		"move_affordance_count": move_count,
	}


func _player_party_ids_from_observation(observation: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var state: Dictionary = observation.get("state", {})
	var hud: Dictionary = state.get("hud", {})
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		if not bool((portrait_v as Dictionary).get("visible", false)):
			continue
		var visible_name := str(
			(portrait_v as Dictionary).get("label", "")
		).strip_edges().to_lower()
		if PARTY_IDS.has(visible_name) and not result.has(visible_name):
			result.append(visible_name)
	return result


func _observed_interaction_actor_order(
	verb: String, consequence: String, party: Array[String]
) -> Array[String]:
	var visible_copy := (verb + " " + consequence).to_lower()
	var preferred := ["aster", "peris", "endo"]
	if _copy_contains_any(visible_copy, ["plant", "flora", "flure", "tend"]):
		preferred = ["peris", "aster", "endo"]
	var ordered: Array[String] = []
	for actor in preferred:
		if party.has(actor):
			ordered.append(actor)
	for actor in party:
		if not ordered.has(actor):
			ordered.append(actor)
	return ordered


func _copy_contains_any(copy: String, terms: Array) -> bool:
	for term_v in terms:
		if copy.contains(str(term_v)):
			return true
	return false


func _wait_for_player_rally_settle(
	preview_instance: Node,
	observer: Node,
	result: Dictionary,
	phase: String,
	label: String,
	initial_observation: Dictionary,
	intended_members: Array,
	discovery_report: Dictionary,
	watchdog: Dictionary,
	target_token: String,
	baseline_movement_serial: int,
	immediate_post_input_observation := {},
	pre_park_transform_samples := {},
	rally_member_destinations := {}
) -> Dictionary:
	var report := {
		"elapsed": 0.0,
		"sample_count": 0,
		"settled": false,
		"used_multi_y_path": false,
		"visible_motion_verified": false,
		"moved_subjects": [],
		"moved_members": [],
		"presented_movement_members": [],
		"concealed_progress_members": [],
		"stationary_arrival_members": [],
		"member_body_tokens": {},
		"concealed_members": {},
		"concealed_portrait_tokens": [],
		"transform_samples": {},
		"movement_result_attestation": {},
		"observation_samples": [],
		"watchdog_abort_reason": "",
		"observation": initial_observation,
		"refusal_terminal_capture_fresh": false,
	}
	var transform_samples := (pre_park_transform_samples as Dictionary).duplicate(
		true) if pre_park_transform_samples is Dictionary \
		and not (pre_park_transform_samples as Dictionary).is_empty() \
		else _new_generated_in_flight_transform_samples(intended_members)
	_sample_generated_in_flight_transforms(
		preview_instance, intended_members, transform_samples)
	var latest := initial_observation
	var initial_positions := _player_observation_party_body_positions(
		initial_observation)
	var member_body_tokens := _player_observation_body_tokens_for_members(
		initial_observation, intended_members)
	var concealed_members := _player_observation_concealed_members(
		initial_observation, intended_members)
	var concealed_portrait_tokens: Array[String] = []
	for portrait_token_v in concealed_members.values():
		concealed_portrait_tokens.append(str(portrait_token_v))
	concealed_portrait_tokens.sort()
	report["concealed_members"] = concealed_members.duplicate(true)
	report["concealed_portrait_tokens"] = concealed_portrait_tokens
	var expected_body_count := intended_members.size()
	var last_motion := _player_observation_member_body_signature(
		initial_observation, member_body_tokens)
	# Rally liveness is measured in production frame-wait time. A rendered
	# observation is synchronous and may take seconds to scan, but the SceneTree
	# advances by only `step` while that scan runs (often by zero frames).
	var last_visible_progress_elapsed := 0.0
	var rally_start_timeout := float(watchdog.get(
		"rally_start_timeout_seconds",
		PLAYER_DISCOVERY_RALLY_START_TIMEOUT_SECONDS))
	var incomplete_stable_timeout := float(watchdog.get(
		"rally_incomplete_stable_timeout_seconds",
		PLAYER_DISCOVERY_RALLY_INCOMPLETE_STABLE_SECONDS))
	var stable_samples := 0
	var moved_members := {}
	var concealed_progress_members := {}
	var stationary_arrival_members := {}
	var body_binding_conflict := false
	var captured_observations: Array = []
	var immediate_pending := immediate_post_input_observation is Dictionary \
		and not (immediate_post_input_observation as Dictionary).is_empty()
	var movement_result: Dictionary = {}
	var exact_phase_liveness := {}
	var exact_route_status_liveness := {}
	var expected_portrait_tokens := \
		_player_observation_portrait_tokens_for_members(
			initial_observation, intended_members)
	# An accepted production route begins at zero. Only a strictly larger value
	# from the exact visible movement-result cue can renew route liveness; no
	# GameState, transform, scheduler, or unrelated presentation churn is trusted.
	var last_visible_route_progress := 0.0
	while float(report["elapsed"]) < PHYSICAL_INTERACTION_TIMEOUT:
		# The immediate post-release capture already exists and costs no additional
		# wait. Consume it before honoring a wall-clock abort so an exact visible
		# refusal is not replaced with the pre-input capture at the deadline.
		if _rally_watchdog_may_preempt_next_capture(immediate_pending):
			var watchdog_abort_reason := _player_discovery_watchdog_abort_reason(
				watchdog)
			if watchdog_abort_reason != "":
				_set_player_discovery_watchdog_pending(
					watchdog, watchdog_abort_reason)
				report["watchdog_abort_reason"] = watchdog_abort_reason
				break
		_emit_player_discovery_heartbeat(
			discovery_report, watchdog,
			int(discovery_report.get("policy_iteration_count", 0)), "rally_wait")
		var step := 0.0
		var snapshot_v: Variant = null
		if immediate_pending:
			snapshot_v = immediate_post_input_observation
			immediate_pending = false
		else:
			step = 0.1
			# Measured Windowed evidence waits on the production frame clock. Calling
			# headless_advance here would mutate scheduler time in a way no player can.
			await preview_instance.get_tree().create_timer(
				step, true, false, false
			).timeout
			snapshot_v = _player_observation_snapshot(observer, watchdog)
		if snapshot_v is Dictionary:
			var candidate := snapshot_v as Dictionary
			if PersonaDecisionTraceScript.validate_player_observation(
					candidate).is_empty():
				var candidate_serial := int(candidate.get("capture_serial", 0))
				var previous_serial := int(initial_observation.get(
					"capture_serial", 0)) if captured_observations.is_empty() \
					else int((captured_observations[-1] as Dictionary).get(
						"capture_serial", 0))
				if candidate_serial > previous_serial:
					captured_observations.append(candidate.duplicate(true))
					latest = candidate
		var current_positions := _player_observation_party_body_positions(latest)
		var current_member_body_tokens := _player_observation_body_tokens_for_members(
			latest, intended_members)
		# A member that began with exact rendered HIDDEN may later enter the
		# framebuffer. Bind that body only when an ordinary observation contains a
		# real visible party_body cue; never manufacture a placeholder token.
		for member_v in intended_members:
			var member := str(member_v).strip_edges().to_snake_case().to_lower()
			if member_body_tokens.has(member):
				var prior_body_token := str(member_body_tokens.get(member, ""))
				var current_body_token := str(current_member_body_tokens.get(member, ""))
				if current_body_token != "" and current_body_token != prior_body_token:
					body_binding_conflict = true
				continue
			if not concealed_members.has(member):
				continue
			if not current_member_body_tokens.has(member):
				if not _player_observation_portrait_has_exact_hidden_presence(
						latest, str(concealed_members.get(member, ""))):
					body_binding_conflict = true
				continue
			var body_token := str(current_member_body_tokens.get(member, ""))
			if body_token == "" or member_body_tokens.values().has(body_token):
				body_binding_conflict = true
				continue
			member_body_tokens[member] = body_token
			if current_positions.has(body_token):
				initial_positions[body_token] = current_positions[body_token]
		for member_v in member_body_tokens.keys():
			var member := str(member_v)
			var body_token := str(member_body_tokens.get(member_v, ""))
			if initial_positions.has(body_token) \
					and current_positions.has(body_token) \
					and current_positions[body_token] != initial_positions[body_token]:
				moved_members[member] = true
		var motion := _player_observation_member_body_signature(
			latest, member_body_tokens)
		var body_motion_changed := false
		if motion == last_motion:
			stable_samples += 1
		else:
			stable_samples = 0
			last_motion = motion
			body_motion_changed = true
		_record_animation_snapshot(
			result,
			preview_instance,
			phase,
			"Rallying toward %s" % label,
			{
				"event_type": "player_rally_in_flight",
				"surface": label,
				"observation_schema": PLAYER_DISCOVERY_OBSERVATION_SCHEMA,
				"visible_motion_changed": moved_members.size() > 0,
				"visible_moved_body_count": moved_members.size(),
			}
		)
		report["elapsed"] = float(report["elapsed"]) + step
		report["sample_count"] = int(report["sample_count"]) + 1
		_sample_generated_in_flight_transforms(
			preview_instance, intended_members, transform_samples)
		movement_result = _derive_exact_observed_rally_lineage(
			initial_observation,
			latest,
			_observations_before_terminal(captured_observations),
			target_token,
			intended_members,
			baseline_movement_serial
		)
		if not movement_result.is_empty():
			var next_phase_liveness := \
				_exact_rally_phase_liveness_transition(
					exact_phase_liveness,
					movement_result,
					target_token,
					expected_portrait_tokens)
			exact_phase_liveness = next_phase_liveness
			var visible_route_progress := _exact_visible_rally_progress(
				latest,
				movement_result,
				target_token,
				expected_portrait_tokens)
			var route_progress_advanced := visible_route_progress \
				> last_visible_route_progress + 0.0001
			if route_progress_advanced:
				last_visible_route_progress = visible_route_progress
			var next_route_status_liveness := \
				_exact_rally_route_status_liveness_transition(
					exact_route_status_liveness,
					latest,
					movement_result,
					target_token,
					expected_portrait_tokens)
			exact_route_status_liveness = next_route_status_liveness
			var renewal_reasons := _exact_rally_liveness_renewal_reasons(
				body_motion_changed,
				next_phase_liveness,
				movement_result,
				target_token,
				expected_portrait_tokens,
				route_progress_advanced)
			if renewal_reasons.is_empty() \
					and bool(next_route_status_liveness.get("advanced", false)):
				var route_status_reason := str(next_route_status_liveness.get(
					"renewal_reason", ""))
				if route_status_reason != "":
					renewal_reasons.append(route_status_reason)
			for renewal_reason in renewal_reasons:
				last_visible_progress_elapsed = float(report["elapsed"])
				_note_player_discovery_visible_progress(
					watchdog, str(renewal_reason))
			if bool(movement_result.get("visible", false)) \
					and bool(movement_result.get("accepted", false)) \
					and (movement_result.get("phases", []) as Array).has("progress"):
				var visible_subjects := movement_result.get("subjects", []) as Array
				for member_v in concealed_members.keys():
					var member := str(member_v)
					if visible_subjects.has(str(concealed_members.get(member_v, ""))):
						concealed_progress_members[member] = true
			if str(movement_result.get("phase", "")) in [
				"refused", "interrupted"
			]:
				break
		var presented_movement_members := moved_members.duplicate(true)
		for member_v in concealed_progress_members.keys():
			presented_movement_members[str(member_v)] = true
		stationary_arrival_members = _stationary_rally_arrival_members(
			transform_samples,
			intended_members,
			rally_member_destinations as Dictionary,
			movement_result,
			expected_portrait_tokens)
		for member_v in stationary_arrival_members.keys():
			presented_movement_members[str(member_v)] = true
		var all_current_visible := true
		for member_v in member_body_tokens.keys():
			all_current_visible = all_current_visible and current_positions.has(
				str(member_body_tokens.get(member_v, "")))
		if not bool(report["settled"]) \
				and float(report["elapsed"]) >= PLAYER_DISCOVERY_MIN_SETTLE_SECONDS \
				and stable_samples >= PLAYER_DISCOVERY_MOTION_STABLE_SAMPLES \
				and expected_body_count > 0 \
				and all_current_visible \
				and presented_movement_members.size() == expected_body_count \
				and not body_binding_conflict:
			report["settled"] = true
		# A follow camera can keep changing body screen coordinates after authority
		# has stopped, hold them steady while world travel continues, or let bodies
		# leave the frame before the persistent HUD arrival cue appears. The exact
		# same-lineage arrival is definitive once each intended portrait has either
		# visible body motion or exact HIDDEN-bound progress. Full-XYZ
		# authority/presenter parity is still checked independently below.
		if not bool(report["settled"]) \
				and _exact_rally_arrival_has_complete_visible_motion_history(
					movement_result,
					target_token,
					expected_portrait_tokens,
					intended_members,
					member_body_tokens,
					concealed_members,
					presented_movement_members,
					baseline_movement_serial
				):
			report["settled"] = true
		if bool(report["settled"]) \
				and str(movement_result.get("phase", "")) == "arrival":
			break
		if presented_movement_members.is_empty() and float(report["elapsed"]) \
				>= rally_start_timeout:
			_set_player_discovery_watchdog_pending(
				watchdog, "rally_visible_motion_did_not_start")
			report["watchdog_abort_reason"] = \
				"rally_visible_motion_did_not_start"
			break
		if not presented_movement_members.is_empty() \
				and _rally_incomplete_progress_stalled(
					float(report["elapsed"]),
					last_visible_progress_elapsed,
					incomplete_stable_timeout):
			_set_player_discovery_watchdog_pending(
				watchdog, "rally_incomplete_visible_motion_stalled")
			report["watchdog_abort_reason"] = \
				"rally_incomplete_visible_motion_stalled"
			break
	if not (bool(report["settled"]) \
			and str(movement_result.get("phase", "")) == "arrival") \
			and str(movement_result.get("phase", "")) not in [
				"refused", "interrupted"
			] \
			and str(report["watchdog_abort_reason"]) == "" \
			and float(report["elapsed"]) >= PHYSICAL_INTERACTION_TIMEOUT:
		_set_player_discovery_watchdog_pending(
			watchdog, "rally_visible_result_timeout")
		report["watchdog_abort_reason"] = "rally_visible_result_timeout"
	report["observation"] = latest
	report["observation_samples"] = _observations_before_terminal(
		captured_observations)
	report["movement_result_attestation"] = movement_result.duplicate(true)
	# Close the validation interval after the terminal capture and pointer park.
	# Force stationary presenters into this endpoint so a refused gesture cannot
	# hide a direct mutation merely because no production route is active.
	_sample_generated_in_flight_transforms(
		preview_instance, intended_members, transform_samples, true)
	stationary_arrival_members = _stationary_rally_arrival_members(
		transform_samples,
		intended_members,
		rally_member_destinations as Dictionary,
		movement_result,
		expected_portrait_tokens)
	var transform_motion_verified := _generated_transform_samples_valid(
		transform_samples,
		intended_members,
		stationary_arrival_members.keys())
	report["transform_samples"] = transform_samples
	report["transform_motion_verified"] = transform_motion_verified
	moved_members = _causal_rally_moved_members(
		moved_members, movement_result, transform_samples)
	if not bool(movement_result.get("accepted", false)):
		concealed_progress_members.clear()
	var presented_movement_members := moved_members.duplicate(true)
	for member_v in concealed_progress_members.keys():
		presented_movement_members[str(member_v)] = true
	for member_v in stationary_arrival_members.keys():
		presented_movement_members[str(member_v)] = true
	report["visible_motion_verified"] = bool(report["settled"]) \
		and bool(movement_result.get("accepted", false)) \
		and str(movement_result.get("phase", "")) == "arrival" \
		and transform_motion_verified \
		and presented_movement_members.size() == expected_body_count \
		and expected_body_count > 0 \
		and not body_binding_conflict
	var moved_member_ids: Array[String] = []
	var moved_tokens: Array[String] = []
	for member_v in moved_members.keys():
		var member := str(member_v)
		moved_member_ids.append(member)
		moved_tokens.append(str(member_body_tokens.get(member, "")))
	moved_member_ids.sort()
	moved_tokens.sort()
	var presented_member_ids: Array[String] = []
	for member_v in presented_movement_members.keys():
		presented_member_ids.append(str(member_v))
	presented_member_ids.sort()
	var concealed_progress_ids: Array[String] = []
	for member_v in concealed_progress_members.keys():
		concealed_progress_ids.append(str(member_v))
	concealed_progress_ids.sort()
	report["member_body_tokens"] = member_body_tokens.duplicate(true)
	report["moved_members"] = moved_member_ids
	report["moved_subjects"] = moved_tokens
	report["presented_movement_members"] = presented_member_ids
	report["concealed_progress_members"] = concealed_progress_ids
	var stationary_arrival_ids: Array[String] = []
	for member_v in stationary_arrival_members.keys():
		stationary_arrival_ids.append(str(member_v))
	stationary_arrival_ids.sort()
	report["stationary_arrival_members"] = stationary_arrival_ids
	report["used_multi_y_path"] = _generated_transform_samples_use_multiple_y(
		transform_samples, intended_members)
	return report


func _rally_watchdog_may_preempt_next_capture(immediate_pending: bool) -> bool:
	# An already-rendered post-input capture is evidence, not additional work. It
	# must be sealed before a wall-clock abort can stop future sampling.
	return not immediate_pending


func _causal_rally_moved_members(
		observed_screen_motion: Dictionary,
		movement_result: Dictionary,
		transform_samples := {}
	) -> Dictionary:
	if not bool(movement_result.get("accepted", true)) \
			and str(movement_result.get("phase", "")) == "refused":
		# Body pixels can drift while a follow/recenter camera is still easing.
		# They are presentation-only and cannot be attributed to a command whose
		# exact public terminal says REFUSED. The caller separately requires zero
		# Rally production events before accepting this as a whole-party refusal.
		return {}
	var causal := {}
	for member_v in observed_screen_motion.keys():
		var member := str(member_v)
		var sample := (transform_samples as Dictionary).get(member, {}) as Dictionary
		if float(sample.get("logical_displacement", 0.0)) > 0.02 \
				and float(sample.get("render_displacement", 0.0)) > 0.02 \
				and float(sample.get("global_position_displacement", 0.0)) > 0.02 \
				and float(sample.get("global_transform_displacement", 0.0)) > 0.02:
			causal[member] = true
	return causal


func _seal_refused_rally_terminal_capture(
		settle: Dictionary, terminal_candidate: Dictionary
	) -> Dictionary:
	var sealed := settle.duplicate(true)
	sealed["refusal_terminal_capture_fresh"] = false
	var prior_v: Variant = sealed.get("observation", {})
	if not (prior_v is Dictionary) or terminal_candidate.is_empty() \
			or not PersonaDecisionTraceScript.validate_player_observation(
				terminal_candidate).is_empty():
		return sealed
	var prior := prior_v as Dictionary
	if int(terminal_candidate.get("capture_serial", 0)) \
			<= int(prior.get("capture_serial", 0)) \
			or float(terminal_candidate.get("tick", 0.0)) \
				< float(prior.get("tick", 0.0)):
		return sealed
	var samples: Array = sealed.get("observation_samples", []).duplicate(true) \
		if sealed.get("observation_samples", null) is Array else []
	samples.append(prior.duplicate(true))
	sealed["observation_samples"] = \
		PersonaDecisionTraceScript.deduplicate_observations(samples)
	sealed["observation"] = terminal_candidate.duplicate(true)
	sealed["refusal_terminal_capture_fresh"] = true
	return sealed


## Current body visibility is deliberately not an input. Actual bodies retain
## their first visible displacement; an initially HIDDEN portrait instead needs
## the same exact public Rally lineage to identify it through PROGRESS and
## ARRIVAL. Full-XYZ authority/presenter parity verifies physical travel for all
## intended members without leaking transforms into policy.
func _exact_rally_arrival_has_complete_visible_motion_history(
		movement_result: Dictionary,
		target_token: String,
		expected_portrait_tokens: Array,
		intended_members: Array,
		member_body_tokens: Dictionary,
		concealed_members: Dictionary,
		presented_movement_members: Dictionary,
		baseline_movement_serial: int
	) -> bool:
	if target_token == "" or intended_members.is_empty() \
			or expected_portrait_tokens.size() != intended_members.size() \
			or not _same_string_members(
				presented_movement_members.keys(), intended_members):
		return false
	var intended_set := {}
	for member_v in intended_members:
		intended_set[str(member_v)] = true
	var unique_body_tokens := {}
	for member_v in member_body_tokens.keys():
		var member := str(member_v)
		var body_token := str(member_body_tokens.get(member_v, ""))
		if not intended_set.has(member) or body_token == "" \
				or unique_body_tokens.has(body_token):
			return false
		unique_body_tokens[body_token] = true
	var unique_portrait_tokens := {}
	for member_v in concealed_members.keys():
		var member := str(member_v)
		var portrait_token := str(concealed_members.get(member_v, ""))
		if not intended_set.has(member) or portrait_token == "" \
				or unique_portrait_tokens.has(portrait_token):
			return false
		unique_portrait_tokens[portrait_token] = true
	for member_v in intended_members:
		var member := str(member_v)
		if not member_body_tokens.has(member) and not concealed_members.has(member):
			return false
	if not bool(movement_result.get("visible", false)) \
			or not bool(movement_result.get("accepted", false)) \
			or not bool(movement_result.get("subjects_consistent", false)) \
			or not bool(movement_result.get("accepted_consistent", false)) \
			or not bool(movement_result.get("target_consistent", false)) \
			or not bool(movement_result.get("phase_order_valid", false)) \
			or str(movement_result.get("phase", "")) != "arrival" \
			or str(movement_result.get("target_token", "")) != target_token \
			or str(movement_result.get("reason", "")).strip_edges() != "" \
			or int(movement_result.get("new_serial_count", 0)) != 1 \
			or int(movement_result.get("presentation_serial", 0)) \
				<= baseline_movement_serial \
			or not _same_string_members(
				movement_result.get("subjects", []) as Array,
				expected_portrait_tokens) \
			or not PersonaDecisionTraceScript.canonical_equal(
				movement_result.get("phases", []),
				["accepted", "progress", "arrival"]):
		return false
	var phase_serials := movement_result.get(
		"phase_capture_serials", {}) as Dictionary
	return int(phase_serials.get("accepted", 0)) \
		< int(phase_serials.get("progress", 0)) \
		and int(phase_serials.get("progress", 0)) \
			< int(phase_serials.get("arrival", 0))


func _derive_exact_observed_rally_lineage(
	before: Dictionary,
	after: Dictionary,
	observation_samples: Array,
	target_token: String,
	intended_members: Array,
	baseline_movement_serial: int
) -> Dictionary:
	if target_token == "" or after.is_empty() \
			or not _same_string_members(
				intended_members, _player_party_ids_from_observation(before)):
		return {}
	var expected_portrait_tokens := \
		_player_observation_portrait_tokens_for_members(before, intended_members)
	if expected_portrait_tokens.size() != intended_members.size():
		return {}
	var decision := {
		"verb": "rally",
		"target": {"kind": "visible_surface", "token": target_token},
		"intended_subjects": intended_members.duplicate(),
		"group_verb": true,
		"world_change": true,
	}
	var derived := PersonaDecisionTraceScript.derive_feedback_outcome(
		before, after, observation_samples, decision, {})
	var outcome_v: Variant = derived.get("outcome", {})
	if not (outcome_v is Dictionary):
		return {}
	var lineage_v: Variant = (outcome_v as Dictionary).get(
		"movement_result", {})
	if not (lineage_v is Dictionary) or (lineage_v as Dictionary).is_empty():
		return {}
	var lineage := (lineage_v as Dictionary).duplicate(true)
	if int(lineage.get("new_serial_count", 0)) != 1 \
			or int(lineage.get("presentation_serial", 0)) \
				<= baseline_movement_serial \
			or not bool(lineage.get("visible", false)) \
			or not bool(lineage.get("subjects_consistent", false)) \
			or not bool(lineage.get("accepted_consistent", false)) \
			or not bool(lineage.get("target_consistent", false)) \
			or not bool(lineage.get("phase_order_valid", false)) \
			or str(lineage.get("target_token", "")) != target_token \
			or not _same_string_members(
				lineage.get("subjects", []) as Array,
				expected_portrait_tokens):
		return {}
	var phases := lineage.get("phases", []) as Array
	var phase_serials := lineage.get("phase_capture_serials", {}) as Dictionary
	if bool(lineage.get("accepted", false)):
		var valid_prefix := PersonaDecisionTraceScript.canonical_equal(
			phases, ["accepted"]) \
			or PersonaDecisionTraceScript.canonical_equal(
				phases, ["accepted", "progress"]) \
			or PersonaDecisionTraceScript.canonical_equal(
				phases, ["accepted", "progress", "arrival"]) \
			or PersonaDecisionTraceScript.canonical_equal(
				phases, ["accepted", "progress", "interrupted"])
		if not valid_prefix:
			return {}
		if phases.has("progress") and not (
				int(phase_serials.get("accepted", 0)) \
				< int(phase_serials.get("progress", 0))):
			return {}
		var terminal_phase := ""
		if phases.has("arrival"):
			terminal_phase = "arrival"
		elif phases.has("interrupted"):
			terminal_phase = "interrupted"
		if terminal_phase != "" and not (
				int(phase_serials.get("progress", 0)) \
				< int(phase_serials.get(terminal_phase, 0))):
			return {}
		var reason := str(lineage.get("reason", "")).strip_edges()
		if (terminal_phase == "arrival" and reason != "") \
				or (terminal_phase == "interrupted" and reason == ""):
			return {}
		lineage["phase"] = terminal_phase \
			if terminal_phase != "" else str(phases[-1])
		return lineage
	if not PersonaDecisionTraceScript.canonical_equal(phases, ["refused"]) \
			or str(lineage.get("reason", "")).strip_edges() == "":
		return {}
	lineage["phase"] = "refused"
	return lineage


func _exact_rally_phase_liveness_transition(
	previous: Dictionary,
	lineage: Dictionary,
	target_token: String,
	expected_subject_tokens: Array
) -> Dictionary:
	var next := previous.duplicate(true)
	next["advanced"] = false
	if lineage.is_empty() or target_token == "" \
			or not bool(lineage.get("visible", false)) \
			or str(lineage.get("target_token", "")) != target_token \
			or not _same_string_members(
				lineage.get("subjects", []) as Array,
				expected_subject_tokens):
		return next
	var serial := int(lineage.get("presentation_serial", 0))
	var phase := str(lineage.get("phase", ""))
	if not bool(lineage.get("accepted", false)):
		# A refusal is a terminal, causal answer to one real human gesture. Count
		# the first exact serial once so the watchdog can try another visible
		# frontier; repeated captures of that same red cue must not buy more time.
		if serial <= 0 or phase != "refused" \
				or int(lineage.get("new_serial_count", 1)) != 1 \
				or not PersonaDecisionTraceScript.canonical_equal(
					lineage.get("phases", []), ["refused"]) \
				or str(lineage.get("reason", "")).strip_edges() == "":
			return next
		if int(next.get("presentation_serial", 0)) > 0:
			return next
		next["presentation_serial"] = serial
		next["target_token"] = target_token
		next["subjects"] = expected_subject_tokens.duplicate()
		next["phase_rank"] = 0
		next["phase"] = "refused"
		next["accepted"] = false
		next["advanced"] = true
		return next
	var phase_rank := int({
		"accepted": 0,
		"progress": 1,
		"arrival": 2,
		"interrupted": 2,
	}.get(phase, -1))
	var expected_phases: Array = {
		"accepted": ["accepted"],
		"progress": ["accepted", "progress"],
		"arrival": ["accepted", "progress", "arrival"],
		"interrupted": ["accepted", "progress", "interrupted"],
	}.get(phase, []) as Array
	if serial <= 0 or phase_rank < 0 or expected_phases.is_empty() \
			or not PersonaDecisionTraceScript.canonical_equal(
				lineage.get("phases", []), expected_phases):
		return next
	var tracked_serial := int(next.get("presentation_serial", 0))
	if tracked_serial <= 0:
		# `accepted` is the phase-zero baseline. If the first sampled exact
		# lineage already includes progress or a terminal, its complete prefix
		# proves that a monotonic phase advance occurred between captures.
		next["presentation_serial"] = serial
		next["target_token"] = target_token
		next["subjects"] = expected_subject_tokens.duplicate()
		next["phase_rank"] = phase_rank
		next["phase"] = phase
		next["advanced"] = phase_rank > 0
		return next
	if serial != tracked_serial \
			or str(next.get("target_token", "")) != target_token \
			or not _same_string_members(
				next.get("subjects", []) as Array,
				expected_subject_tokens):
		return next
	var previous_rank := int(next.get("phase_rank", -1))
	if phase_rank <= previous_rank:
		return next
	# `_derive_exact_observed_rally_lineage` already proves every intermediate
	# phase capture and rejects skips/regressions. Renew only this exact lineage;
	# changing text, unrelated cues, or a different movement serial cannot help.
	next["phase_rank"] = phase_rank
	next["phase"] = phase
	next["advanced"] = true
	return next


func _exact_rally_liveness_renewal_reasons(
		body_motion_changed: bool,
		phase_liveness: Dictionary,
		lineage: Dictionary,
		target_token: String,
		expected_subject_tokens: Array,
		route_progress_advanced: bool
	) -> Array[String]:
	## At most one watchdog credit may be minted from a rendered capture. Raw body
	## drift is camera-relative and becomes causal only after the exact accepted
	## movement-result lineage binds it to this gesture. A first reasoned refusal
	## is itself one complete visible answer and takes precedence over drift.
	var reasons: Array[String] = []
	if lineage.is_empty() or target_token == "" \
			or not bool(lineage.get("visible", false)) \
			or str(lineage.get("target_token", "")) != target_token \
			or not _same_string_members(
				lineage.get("subjects", []) as Array,
				expected_subject_tokens):
		return reasons
	var phase := str(lineage.get("phase", ""))
	var accepted := bool(lineage.get("accepted", false))
	if bool(phase_liveness.get("advanced", false)):
		if not accepted:
			if phase == "refused" \
					and str(lineage.get("reason", "")).strip_edges() != "":
				reasons.append("rally_exact_phase_advance_refused")
			return reasons
		reasons.append("rally_exact_phase_advance_%s" % (
			phase if phase != "" else "presented"))
		return reasons
	if not accepted:
		return reasons
	if route_progress_advanced:
		reasons.append("rally_visible_route_progress")
	elif body_motion_changed:
		reasons.append("rally_bound_body_motion")
	return reasons


func _exact_rally_route_status_liveness_transition(
		previous: Dictionary,
		observation: Dictionary,
		lineage: Dictionary,
		target_token: String,
		expected_subject_tokens: Array
	) -> Dictionary:
	## Only the exact rendered movement cue for this accepted gesture can explain
	## stationary route work. A replan transition earns one credit. A cooperative
	## hold earns later credit only when its finite on-screen countdown decreases;
	## repeated/longer/foreign cues cannot keep the watchdog alive.
	var next := previous.duplicate(true)
	next["advanced"] = false
	next["renewal_reason"] = ""
	if observation.is_empty() or lineage.is_empty() \
			or not bool(lineage.get("visible", false)) \
			or not bool(lineage.get("accepted", false)) \
			or str(lineage.get("target_token", "")) != target_token \
			or not _same_string_members(
				lineage.get("subjects", []) as Array,
				expected_subject_tokens):
		return next
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return next
	var presentation_serial := int(lineage.get("presentation_serial", 0))
	var lineage_phase := str(lineage.get("phase", ""))
	var exact_cue: Dictionary = {}
	var exact_count := 0
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "movement_result" \
				or not bool(cue.get("visible", false)) \
				or not bool(cue.get("accepted", false)) \
				or int(cue.get("presentation_serial", 0)) \
					!= presentation_serial \
				or str(cue.get("target_token", "")) != target_token \
				or str(cue.get("phase", "")) != lineage_phase \
				or not _same_string_members(
					cue.get("subjects", []) as Array,
					expected_subject_tokens):
			continue
		exact_count += 1
		exact_cue = cue
	if exact_count != 1:
		return next
	var route_status := str(exact_cue.get("route_status", ""))
	var route_status_serial := int(exact_cue.get("route_status_serial", 0))
	var status_subjects := exact_cue.get(
		"route_status_subjects", []) as Array
	if route_status not in ["reforming_route", "cooperative_hold"] \
			or route_status_serial <= 0 or status_subjects.is_empty():
		return next
	for subject_v in status_subjects:
		if not expected_subject_tokens.has(str(subject_v)):
			return next
	var same_status_episode := int(next.get(
		"presentation_serial", 0)) == presentation_serial \
		and int(next.get("route_status_serial", 0)) == route_status_serial \
		and str(next.get("route_status", "")) == route_status \
		and _same_string_members(
			next.get("route_status_subjects", []) as Array,
			status_subjects)
	var remaining := maxf(0.0, float(exact_cue.get(
		"route_status_remaining_seconds", 0.0)))
	if not same_status_episode:
		next["presentation_serial"] = presentation_serial
		next["route_status_serial"] = route_status_serial
		next["route_status"] = route_status
		next["route_status_subjects"] = status_subjects.duplicate()
		next["remaining_seconds"] = remaining
		next["advanced"] = true
		next["renewal_reason"] = "rally_visible_route_reforming" \
			if route_status == "reforming_route" \
			else "rally_visible_cooperative_hold_started"
		return next
	if route_status != "cooperative_hold":
		return next
	var previous_remaining := float(next.get("remaining_seconds", remaining))
	if remaining < previous_remaining - 0.049:
		next["remaining_seconds"] = remaining
		next["advanced"] = true
		next["renewal_reason"] = "rally_visible_cooperative_hold_countdown"
	return next


func _exact_visible_rally_progress(
	observation: Dictionary,
	lineage: Dictionary,
	target_token: String,
	expected_subject_tokens: Array
) -> float:
	if observation.is_empty() or lineage.is_empty() \
			or not bool(lineage.get("visible", false)) \
			or not bool(lineage.get("accepted", false)) \
			or target_token == "" \
			or not _same_string_members(
				lineage.get("subjects", []) as Array,
				expected_subject_tokens):
		return -1.0
	var serial := int(lineage.get("presentation_serial", 0))
	var lineage_phase := str(lineage.get("phase", ""))
	var state_v: Variant = observation.get("state", {})
	if serial <= 0 or not (state_v is Dictionary):
		return -1.0
	var exact_progress := -1.0
	var exact_count := 0
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "movement_result" \
				or not bool(cue.get("visible", false)) \
				or int(cue.get("presentation_serial", 0)) != serial \
				or str(cue.get("target_token", "")) != target_token \
				or str(cue.get("phase", "")) != lineage_phase \
				or not bool(cue.get("accepted", false)) \
				or not _same_string_members(
					cue.get("subjects", []) as Array,
					expected_subject_tokens):
			continue
		var progress_v: Variant = cue.get("progress", null)
		if not (progress_v is int or progress_v is float):
			continue
		var progress := float(progress_v)
		if not is_finite(progress) or progress < 0.0 or progress > 1.0:
			continue
		exact_count += 1
		exact_progress = progress
	# Multiple cues claiming the same exact public lineage in one observation are
	# ambiguous player evidence, not permission to keep a watchdog alive.
	return exact_progress if exact_count == 1 else -1.0


func _new_generated_in_flight_transform_samples(character_ids: Array) -> Dictionary:
	var samples := {}
	for char_id_v in character_ids:
		samples[str(char_id_v)] = {
			"count": 0,
			"invalid": false,
			"first_logical": [],
			"last_logical": [],
			"first_render": [],
			"last_render": [],
			"first_global_position": [],
			"last_global_position": [],
			"first_global_transform_origin": [],
			"last_global_transform_origin": [],
			"logical_displacement": 0.0,
			"render_displacement": 0.0,
			"global_position_displacement": 0.0,
			"global_transform_displacement": 0.0,
			"render_y_min": INF,
			"render_y_max": -INF,
			"max_projection_error": 0.0,
			"max_global_position_error": 0.0,
			"max_global_transform_error": 0.0,
		}
	return samples


## Validation-only transform receipt. These authority values never enter the
## observation or policy; they prove after the shipped Rally that every intended
## presenter's live full-XYZ transform tracked its authoritative render position
## continuously while the movement was in flight.
func _sample_generated_in_flight_transforms(
		preview_instance: Node,
		character_ids: Array,
		samples: Dictionary,
		include_stationary := false
	) -> void:
	var game_state = preview_instance.get("_game_state")
	var presenters_v: Variant = preview_instance.get("_characters")
	if game_state == null or not (presenters_v is Dictionary):
		return
	var presenters := presenters_v as Dictionary
	for char_id_v in character_ids:
		var char_id := str(char_id_v)
		if not game_state.characters.has(char_id) \
				or (not include_stationary \
					and not game_state.is_moving(char_id) \
					and not game_state.is_external_traversal_active(char_id)):
			continue
		if not samples.has(char_id):
			samples[char_id] = _new_generated_in_flight_transform_samples(
				[char_id])[char_id]
		var entry := samples[char_id] as Dictionary
		var presenter_v: Variant = presenters.get(char_id)
		if not (presenter_v is Node3D) or not is_instance_valid(presenter_v):
			entry["invalid"] = true
			continue
		var presenter := presenter_v as Node3D
		var logical: Vector3 = game_state.get_position(char_id)
		var render: Vector3 = game_state.get_render_position(char_id)
		var projected_logical := logical
		var projection_error := logical.distance_to(render)
		if game_state.is_external_traversal_active(char_id):
			var traversal: Dictionary = game_state.get_external_traversal_state(char_id)
			var traversal_data: Vector3 = traversal.get("data_position", Vector3.INF)
			var traversal_render: Vector3 = traversal.get("render_position", Vector3.INF)
			projection_error = maxf(
				traversal_data.distance_to(logical),
				traversal_render.distance_to(render))
		elif game_state.coord_map != null and game_state.coord_map.has_method("to_world"):
			projected_logical = game_state.coord_map.to_world(logical)
			projection_error = projected_logical.distance_to(render)
		var position_error := presenter.global_position.distance_to(render)
		var transform_error := presenter.global_transform.origin.distance_to(render)
		var finite := logical.is_finite() and render.is_finite() \
			and projected_logical.is_finite() and presenter.global_position.is_finite() \
			and presenter.global_transform.origin.is_finite() \
			and is_finite(projection_error) and is_finite(position_error) \
			and is_finite(transform_error)
		entry["invalid"] = bool(entry.get("invalid", false)) or not finite
		if finite:
			entry["count"] = int(entry.get("count", 0)) + 1
			if (entry.get("first_logical", []) as Array).is_empty():
				entry["first_logical"] = _vector3_evidence(logical)
				entry["first_render"] = _vector3_evidence(render)
				entry["first_global_position"] = _vector3_evidence(
					presenter.global_position)
				entry["first_global_transform_origin"] = _vector3_evidence(
					presenter.global_transform.origin)
			entry["last_logical"] = _vector3_evidence(logical)
			entry["last_render"] = _vector3_evidence(render)
			entry["last_global_position"] = _vector3_evidence(
				presenter.global_position)
			entry["last_global_transform_origin"] = _vector3_evidence(
				presenter.global_transform.origin)
			entry["logical_displacement"] = _evidence_vector3(
				entry["first_logical"]).distance_to(logical)
			entry["render_displacement"] = _evidence_vector3(
				entry["first_render"]).distance_to(render)
			entry["global_position_displacement"] = _evidence_vector3(
				entry["first_global_position"]).distance_to(
					presenter.global_position)
			entry["global_transform_displacement"] = _evidence_vector3(
				entry["first_global_transform_origin"]).distance_to(
					presenter.global_transform.origin)
			entry["render_y_min"] = minf(
				float(entry.get("render_y_min", INF)), render.y)
			entry["render_y_max"] = maxf(
				float(entry.get("render_y_max", -INF)), render.y)
			entry["max_projection_error"] = maxf(
				float(entry.get("max_projection_error", 0.0)), projection_error)
			entry["max_global_position_error"] = maxf(
				float(entry.get("max_global_position_error", 0.0)), position_error)
			entry["max_global_transform_error"] = maxf(
				float(entry.get("max_global_transform_error", 0.0)), transform_error)


func _stationary_rally_arrival_members(
		samples: Dictionary,
		character_ids: Array,
		member_destinations: Dictionary,
		movement_result: Dictionary,
		expected_portrait_tokens: Array
	) -> Dictionary:
	var result := {}
	if character_ids.is_empty() \
			or not _same_string_members(
				member_destinations.keys(), character_ids) \
			or not bool(movement_result.get("visible", false)) \
			or not bool(movement_result.get("accepted", false)) \
			or not bool(movement_result.get("subjects_consistent", false)) \
			or not bool(movement_result.get("accepted_consistent", false)) \
			or not bool(movement_result.get("target_consistent", false)) \
			or not bool(movement_result.get("phase_order_valid", false)) \
			or str(movement_result.get("phase", "")) != "arrival" \
			or str(movement_result.get("target_token", "")) == "" \
			or str(movement_result.get("reason", "")).strip_edges() != "" \
			or int(movement_result.get("new_serial_count", 0)) != 1 \
			or int(movement_result.get("presentation_serial", 0)) <= 0 \
			or not PersonaDecisionTraceScript.canonical_equal(
				movement_result.get("phases", []),
				["accepted", "progress", "arrival"]) \
			or not _same_string_members(
				movement_result.get("subjects", []) as Array,
				expected_portrait_tokens):
		return result
	var phase_capture_serials := movement_result.get(
		"phase_capture_serials", {}) as Dictionary
	if int(phase_capture_serials.get("accepted", 0)) \
			>= int(phase_capture_serials.get("progress", 0)) \
			or int(phase_capture_serials.get("progress", 0)) \
				>= int(phase_capture_serials.get("arrival", 0)):
		return result
	for member_v in character_ids:
		var member := str(member_v)
		if _generated_stationary_rally_endpoint_valid(
				member, samples, member_destinations):
			result[member] = true
	return result


func _generated_stationary_rally_endpoint_valid(
		member: String,
		samples: Dictionary,
		member_destinations: Dictionary,
		destination_tolerance := 0.2,
		displacement_tolerance := 0.001
	) -> bool:
	var entry_v: Variant = samples.get(member, {})
	var destination_v: Variant = member_destinations.get(member, null)
	if not (entry_v is Dictionary) or not (destination_v is Array) \
			or (destination_v as Array).size() != 3:
		return false
	var entry := entry_v as Dictionary
	var first := _evidence_vector3(entry.get("first_logical", []))
	var last := _evidence_vector3(entry.get("last_logical", []))
	var destination := _evidence_vector3(destination_v)
	if int(entry.get("count", 0)) < 2 or bool(entry.get("invalid", true)) \
			or not first.is_finite() or not last.is_finite() \
			or not destination.is_finite() \
			or first.distance_to(destination) > destination_tolerance \
			or last.distance_to(destination) > destination_tolerance:
		return false
	for displacement_key in [
		"logical_displacement",
		"render_displacement",
		"global_position_displacement",
		"global_transform_displacement",
	]:
		var displacement := float(entry.get(displacement_key, INF))
		if not is_finite(displacement) or displacement > displacement_tolerance:
			return false
	return true


func _generated_transform_samples_valid(
		samples: Dictionary,
		character_ids: Array,
		stationary_members := [],
		tolerance := 0.08
	) -> bool:
	if character_ids.is_empty():
		return false
	var stationary_set := {}
	for member_v in stationary_members:
		stationary_set[str(member_v)] = true
	for char_id_v in character_ids:
		var char_id := str(char_id_v)
		var entry: Dictionary = samples.get(char_id, {})
		var stationary := stationary_set.has(char_id)
		if int(entry.get("count", 0)) <= 0 \
				or bool(entry.get("invalid", true)) \
				or (entry.get("first_logical", []) as Array).size() != 3 \
				or (entry.get("last_logical", []) as Array).size() != 3 \
				or (entry.get("first_render", []) as Array).size() != 3 \
				or (entry.get("last_render", []) as Array).size() != 3 \
				or float(entry.get("max_projection_error", INF)) > tolerance \
				or float(entry.get("max_global_position_error", INF)) > tolerance \
				or float(entry.get("max_global_transform_error", INF)) > tolerance:
			return false
		for displacement_key in [
			"logical_displacement",
			"render_displacement",
			"global_position_displacement",
			"global_transform_displacement",
		]:
			var displacement := float(entry.get(displacement_key, INF))
			if not is_finite(displacement) \
					or (stationary and displacement > 0.001) \
					or (not stationary and displacement <= 0.02):
				return false
	return true


func _generated_refused_rally_motion_evidence_valid(
		motion: Dictionary,
		character_ids: Array,
		observation_before: Dictionary,
		observation_samples: Array,
		observation_after: Dictionary
	) -> bool:
	return not bool(motion.get("visible", true)) \
		and _same_string_members(
			motion.get("intended_members", []) as Array, character_ids) \
		and (motion.get("moved_members", []) as Array).is_empty() \
		and (motion.get("presented_movement_members", []) as Array).is_empty() \
		and (motion.get("concealed_progress_members", []) as Array).is_empty() \
		and (motion.get("subjects", []) as Array).is_empty() \
		and _generated_rally_motion_presence_evidence_valid(
			motion,
			character_ids,
			observation_before,
			observation_samples,
			observation_after,
			false) \
		and _generated_refusal_transform_samples_unchanged(
			motion.get("transform_samples", {}) as Dictionary, character_ids)


func _generated_refusal_transform_samples_unchanged(
		samples: Dictionary,
		character_ids: Array,
		displacement_tolerance := 0.001,
		parity_tolerance := 0.08
	) -> bool:
	if character_ids.is_empty():
		return false
	for char_id_v in character_ids:
		var entry: Dictionary = samples.get(str(char_id_v), {})
		if int(entry.get("count", 0)) < 2 \
				or bool(entry.get("invalid", true)) \
				or (entry.get("first_logical", []) as Array).size() != 3 \
				or (entry.get("last_logical", []) as Array).size() != 3 \
				or (entry.get("first_render", []) as Array).size() != 3 \
				or (entry.get("last_render", []) as Array).size() != 3 \
				or (entry.get("first_global_position", []) as Array).size() != 3 \
				or (entry.get("last_global_position", []) as Array).size() != 3 \
				or (entry.get("first_global_transform_origin", []) as Array).size() != 3 \
				or (entry.get("last_global_transform_origin", []) as Array).size() != 3 \
				or float(entry.get("max_projection_error", INF)) > parity_tolerance \
				or float(entry.get("max_global_position_error", INF)) > parity_tolerance \
				or float(entry.get("max_global_transform_error", INF)) > parity_tolerance:
			return false
		# Endpoint vectors are the primary evidence. Recompute every displacement
		# instead of trusting a cached scalar that a stale or forged artifact could
		# leave at zero after mutating a terminal transform.
		for fields_v in [
			["first_logical", "last_logical", "logical_displacement"],
			["first_render", "last_render", "render_displacement"],
			[
				"first_global_position",
				"last_global_position",
				"global_position_displacement",
			],
			[
				"first_global_transform_origin",
				"last_global_transform_origin",
				"global_transform_displacement",
			],
		]:
			var fields := fields_v as Array
			var recomputed := _evidence_vector3(entry.get(
				str(fields[0]), [])).distance_to(_evidence_vector3(entry.get(
					str(fields[1]), [])))
			var stored := float(entry.get(str(fields[2]), INF))
			if not is_finite(recomputed) or not is_finite(stored) \
					or recomputed > displacement_tolerance \
					or stored > displacement_tolerance \
					or absf(stored - recomputed) > 0.000001:
				return false
	return true


func _vector3_evidence(value: Vector3) -> Array[float]:
	return [
		snappedf(value.x, 0.000001),
		snappedf(value.y, 0.000001),
		snappedf(value.z, 0.000001),
	]


func _evidence_vector3(value_v: Variant) -> Vector3:
	if not (value_v is Array) or (value_v as Array).size() != 3:
		return Vector3.INF
	var value := value_v as Array
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _generated_transform_samples_use_multiple_y(
		samples: Dictionary, character_ids: Array, tolerance := 0.02
	) -> bool:
	for char_id_v in character_ids:
		var entry: Dictionary = samples.get(str(char_id_v), {})
		var minimum := float(entry.get("render_y_min", INF))
		var maximum := float(entry.get("render_y_max", -INF))
		if is_finite(minimum) and is_finite(maximum) \
				and maximum - minimum > tolerance:
			return true
	return false


func _player_party_ids(preview_instance: Node) -> Array[String]:
	var party: Array[String] = []
	# The roster selected before the evidence baseline is the set a player sees
	# and can command in this run. Do not silently fall back to every registered
	# GameState character when a pair-only run is under test.
	var state: Dictionary = preview_instance.call("headless_get_state")
	for char_id_v in state.get("chunk", {}).get("active_party", []):
		party.append(str(char_id_v))
	if not party.is_empty():
		return party
	var hud_v: Variant = preview_instance.get("_hud")
	if hud_v != null and (hud_v as Object).has_method("get_portrait_ids"):
		for char_id_v in (hud_v as Object).call("get_portrait_ids"):
			party.append(str(char_id_v))
	if not party.is_empty():
		return party
	var gs_v: Variant = preview_instance.get("_game_state")
	if gs_v != null and (gs_v as Object).has_method("get_party"):
		for char_id_v in (gs_v as Object).call("get_party"):
			party.append(str(char_id_v))
	return party


func _player_visible_risk_score(visible_copy: String) -> int:
	var score := 0
	for term in ["risk", "exposed", "pressure", "danger", "damage", "shortcut", "cache", "lysate"]:
		if term in visible_copy:
			score += 1
	return score


func _feedback_reads_as_refusal(feedback: String) -> bool:
	var lowered := feedback.to_lower()
	for term in [
		"cannot", "can't", "blocked", "requires", "need ", "refused",
		"unreachable", "no reachable", "resolve first", "not ready", "not yet", "locked",
		"no route", "no free party", "not complete",
		"outside the authored exit shelter",
		"previous change has not taken effect", "route incomplete",
		"downstream break", "delivery blocked", "did not reach shelter",
		"committed to another action", "cannot pay", "restore the main current",
	]:
		if term in lowered:
			return true
	return false
func _populate_player_surface_outcome(
	report: Dictionary, state: Dictionary
) -> void:
	var chunk: Dictionary = state.get("chunk", {})
	report["shelter_rested"] = bool(chunk.get("shelter_rested", false))
	report["first_shelter_beat_fired"] = bool(
		chunk.get("first_shelter_beat_fired", false)
	)
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["final_outcome"] = str(chunk.get("last_outcome", ""))
	report["character_stats"] = state.get("character_stats", {}).duplicate(true)
	report["active_party"] = chunk.get("active_party", []).duplicate()
	report["blocked_nodes"] = chunk.get("blocked_nodes", []).duplicate()
	report["shortcut_unlocked"] = bool(chunk.get("shortcut_unlocked", false))
	report["climbvine_states"] = chunk.get("climbvine_states", []).duplicate(true)
	report["route_risk_field"] = chunk.get("route_risk_field", {}).duplicate(true)
	report["solution_path"] = chunk.get("solution_path", []).duplicate(true)
	report["solution_path_observation_only"] = true
	report["resources_collected"] = int(
		chunk.get("generation", {}).get("resources_collected", 0)
	)
	report["physical_food_spawned_count"] = int(
		chunk.get("physical_food_spawned_count", 0)
	)
	report["pressure_taken"] = float(chunk.get("pressure_taken", 0.0))
	report["risky_damage_total"] = float(chunk.get("risky_damage_total", 0.0))
	report["produced_chain_states"] = chunk.get(
		"produced_chain_states", {}
	).duplicate(true)
	report["delivered_resource_nodes"] = chunk.get(
		"delivered_resource_nodes", []
	).duplicate(true)
	report["scarcity_drain_ticks"] = int(chunk.get("scarcity_drain_ticks", 0))
	report["scarcity_atp_drained"] = float(chunk.get("scarcity_atp_drained", 0.0))
	report["scarcity_drain_per_character"] = float(
		chunk.get("scarcity_drain_per_character", 0.0)
	)
	report["scarcity_atp_floor_per_character"] = float(
		chunk.get("scarcity_atp_floor_per_character", 0.0)
	)


func _player_visible_reward_report(preview_instance: Node) -> Dictionary:
	var report := {
		"item_type": "",
		"spawned": false,
		"picked_up": false,
		"retained_in_hand": false,
		"endocytosis_completed": false,
	}
	if not preview_instance.has_method("headless_get_state"):
		return report
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	report["spawned"] = int(chunk.get("physical_food_spawned_count", 0)) > 0
	var inventory: Dictionary = state.get("inventory", {})
	for char_id in _player_party_ids(preview_instance):
		var character_inventory: Dictionary = inventory.get(char_id, {})
		for item_id_v in character_inventory.get("hands", []):
			var item_id := str(item_id_v)
			if item_id == "":
				continue
			var item: Dictionary = preview_instance.call("get_preview_item_state", item_id)
			if str(item.get("type", "")) != "lysate":
				continue
			report["item_type"] = "lysate"
			report["spawned"] = true
			report["picked_up"] = true
			report["retained_in_hand"] = true
			report["character"] = char_id
			report["item_id"] = item_id
			return report
	return report

## The Aster+Peris evidence run starts from a quarantined pair-roster fixture,
## then discovers and operates the same visible surfaces as a player.
## shadow approach — a genuinely different, recorded solution path.
func _play_shadow_path(
	preview_instance: Node, _spec: Dictionary, result := {}, options := {}
) -> Dictionary:
	var report: Dictionary = await _play_visible_surface_path(
		preview_instance,
		result,
		options,
		"shadow_path",
		"first_read",
		"shadow"
	)
	report["uses_only_pair"] = report.get("active_party", []) == ["aster", "peris"]
	return report


## Solver-driven replay retained only as a mechanism diagnostic. It cannot be
## reported as persona, approval, pacing, playability, or release evidence.
func _diagnostic_replay_shadow_solution(preview_instance: Node, spec: Dictionary, result := {}, options := {}) -> Dictionary:
	var report := {
		"path_id": "shadow_path",
		"evidence_kind": "solver_trace_mechanism_diagnostic",
		"decision_source": "emitted_shadow_solution",
		"approval_eligible": false,
		"counts_as_persona_play": false,
		"persona_decision_feed_eligible": false,
		"visited_nodes": [],
		"route_ids": [],
		"route_choices": 0,
		"movement_commands": 0,
		"max_path_points": 0,
		"used_multi_y_path": false,
		"physical_interactions": 0,
		"interaction_failures": [],
		"solution_action_failures": [],
		"shelter_rested": false,
		"uses_only_pair": true,
		"solution_path": [],
		"events": [],
	}
	if not preview_instance.has_method("headless_call_chunk"):
		return report
	preview_instance.call("headless_call_chunk", "reset_preview_state", [])
	preview_instance.call("headless_call_chunk", "set_active_loadout", ["shadow"])
	_append_report_event(report, "shadow_path", "path_started", "Shadow path (Aster+Peris) started", {"path_id": "shadow_path"})
	_record_animation_snapshot(result, preview_instance, "shadow_path", "Shadow path reset (Aster+Peris)", {
		"event_type": "path_started",
		"path_id": "shadow_path",
		"loadout": "shadow",
	})
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	var consumed_solution_actions := {}
	for i in range(path.size()):
		var node_id := str(path[i])
		var action_report := _diagnostic_apply_solution_actions_before_node(
			preview_instance,
			spec,
			node_id,
			consumed_solution_actions,
			result,
			"shadow_path"
		)
		report["movement_commands"] = int(report.get("movement_commands", 0)) \
			+ int(action_report.get("movement_commands", 0))
		(report["solution_action_failures"] as Array).append_array(
			action_report.get("failures", [])
		)
		var running_for_move := _node_suggests_running(_find_node(spec, node_id))
		if i > 0:
			var route_id := _find_route_id(spec, str(path[i - 1]), node_id, ["safe", "shortcut"])
			if route_id != "":
				var route_def := _find_route(spec, route_id)
				running_for_move = running_for_move or _route_suggests_running(route_def)
				(report["route_ids"] as Array).append(route_id)
				report["route_choices"] = int(report.get("route_choices", 0)) + 1
		var move_report := _diagnostic_move_party_to_node_report(preview_instance, spec, node_id, result, options, running_for_move, "shadow_path")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(move_report.get("commands", 0))
		report["used_multi_y_path"] = bool(report.get("used_multi_y_path", false)) or bool(move_report.get("used_multi_y_path", false))
		var current_node := _find_node(spec, node_id)
		var runtime_handler := RuntimeRegistryScript.handler_for_node(current_node, str(spec.get("id", "")))
		_capture_node_commit(result, preview_instance, current_node, "shadow_path")
		var interaction_completed := runtime_handler == ""
		if runtime_handler != "":
			var interaction := _diagnostic_interact_generated_node(
				preview_instance, spec, node_id, result, "shadow_path"
			)
			interaction_completed = bool(interaction.get("completed", false))
			report["movement_commands"] = int(report.get("movement_commands", 0)) \
				+ int(interaction.get("movement_commands", 0))
			if bool(interaction.get("requested", false)):
				report["physical_interactions"] = int(
					report.get("physical_interactions", 0)
				) + 1
			if not bool(interaction.get("completed", false)):
				(report["interaction_failures"] as Array).append(
					interaction.duplicate(true)
				)
		var node_payload := _node_event_payload(spec, node_id, preview_instance)
		var event_type := "layout_traversed"
		var event_label := "Traversed %s (shadow)" % node_id
		if runtime_handler != "":
			event_type = "node_activated" \
				if interaction_completed else "node_interaction_failed"
			event_label = ("Activated %s (shadow)" if interaction_completed \
				else "Failed to activate %s (shadow)") % node_id
		_append_report_event(report, "shadow_path", event_type, event_label, node_payload)
		_record_animation_snapshot(result, preview_instance, "shadow_path", event_label, {
			"event_type": event_type,
			"node_id": node_id,
			"node": node_payload,
			"loadout": "shadow",
		})
		if interaction_completed:
			_capture_resource_beat(
				result, preview_instance, spec, node_id, "shadow_path"
			)
		(report["visited_nodes"] as Array).append(node_id)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	report["shelter_rested"] = bool(chunk.get("shelter_rested", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["final_outcome"] = str(chunk.get("last_outcome", ""))
	report["blocked_nodes"] = chunk.get("blocked_nodes", [])
	report["active_party"] = chunk.get("active_party", [])
	report["produced_chain_states"] = chunk.get("produced_chain_states", {})
	report["delivered_resource_nodes"] = chunk.get("delivered_resource_nodes", [])
	var solution_path: Array = chunk.get("solution_path", [])
	report["solution_path"] = solution_path
	for entry in solution_path:
		if entry is Dictionary and str((entry as Dictionary).get("party", "")) == "specialist":
			report["uses_only_pair"] = false
	if bool(report.get("shelter_rested", false)):
		_record_animation_snapshot(result, preview_instance, "shadow_path", "Shadow path rested at shelter", {
			"event_type": "shelter_rested",
			"node_id": "exit_shelter",
			"loadout": "shadow",
		})
	return report

func _play_risky_recovery(
	preview_instance: Node, _spec: Dictionary, result := {}, options := {}
) -> Dictionary:
	var report: Dictionary = await _play_visible_surface_path(
		preview_instance,
		result,
		options,
		"risky_recovery",
		"risk_seeking",
		""
	)
	report["has_risky_route"] = bool(report.get("risk_surface_attempted", false))
	report["damage"] = float(report.get("risky_damage_total", 0.0))
	report["recovered"] = bool(report.get("shelter_rested", false))
	report["reward"] = _player_visible_reward_report(preview_instance)
	return report


## Solver-route replay retained only as a structural/mechanism diagnostic. It
## may use emitted route metadata, but it is never approval or persona evidence.
func _diagnostic_replay_risky_solution(preview_instance: Node, spec: Dictionary, result := {}, options := {}) -> Dictionary:
	var report := {
		"path_id": "risky_recovery",
		"evidence_kind": "solver_trace_mechanism_diagnostic",
		"decision_source": "emitted_risky_route",
		"approval_eligible": false,
		"counts_as_persona_play": false,
		"persona_decision_feed_eligible": false,
		"has_risky_route": false,
		"route_id": "",
		"movement_commands": 0,
		"physical_interactions": 0,
		"interaction_failures": [],
		"solution_action_failures": [],
		"damage": 0.0,
		"recovered": false,
		"events": [],
	}
	if not preview_instance.has_method("headless_call_chunk"):
		return report
	preview_instance.call("headless_call_chunk", "reset_preview_state", [])
	_record_animation_snapshot(result, preview_instance, "risky_recovery", "Risky recovery reset", {
		"event_type": "path_started",
		"path_id": "risky_recovery",
	})
	var consumed_solution_actions := {}
	var risky_route := _find_first_route(spec, ["risky"])
	if risky_route.is_empty():
		var fallback_path: Array = spec.get("headless", {}).get("golden_path", [])
		if fallback_path.is_empty():
			fallback_path = ["entry", "exit_shelter"]
		var fallback_report := _diagnostic_follow_solver_segment(
			preview_instance,
			spec,
			fallback_path,
			0,
			fallback_path.size() - 1,
			result,
			options,
			"risky_recovery",
			consumed_solution_actions
		)
		report["movement_commands"] = int(fallback_report.get("commands", 0))
		report["physical_interactions"] = int(
			fallback_report.get("physical_interactions", 0)
		)
		report["interaction_failures"] = fallback_report.get(
			"interaction_failures", []
		)
		report["solution_action_failures"] = fallback_report.get(
			"solution_action_failures", []
		)
		report["recovered"] = bool(
			preview_instance.call("headless_get_state")
				.get("chunk", {})
				.get("shelter_rested", false)
		)
		_append_report_event(report, "risky_recovery", "no_risky_route", "No risky route was available; fell back to golden path", {
			"recovered": bool(report.get("recovered", false)),
		})
		_record_animation_snapshot(result, preview_instance, "risky_recovery", "No risky route; fallback complete", {
			"event_type": "no_risky_route",
			"recovered": bool(report.get("recovered", false)),
		})
		return report
	report["has_risky_route"] = true
	report["route_id"] = str(risky_route.get("id", ""))
	var main_path: Array = spec.get("headless", {}).get("golden_path", [])
	if main_path.is_empty():
		main_path = ["entry", "exit_shelter"]
	var risky_source_id := str(risky_route.get("from", "entry"))
	var risky_source_index := main_path.find(risky_source_id)
	report["source_on_golden_path"] = risky_source_index >= 0
	_append_report_event(report, "risky_recovery", "path_started", "Risky recovery reset and started", {
		"path_id": "risky_recovery",
		"route": risky_route.duplicate(true),
	})
	# A risky-route scenario must obey the same prerequisites as a player. Walking the
	# golden prefix keeps this test valid when a risky branch begins late in a longer
	# generated stretch; directly teleporting to its source would only test a harness
	# loophole and now correctly conflicts with the runtime progression gate.
	if risky_source_index < 0:
		return report
	var prefix_report := _diagnostic_follow_solver_segment(
		preview_instance,
		spec,
		main_path,
		0,
		risky_source_index,
		result,
		options,
		"risky_recovery",
		consumed_solution_actions
	)
	report["movement_commands"] = int(prefix_report.get("commands", 0))
	report["physical_interactions"] = int(prefix_report.get("physical_interactions", 0))
	(report["interaction_failures"] as Array).append_array(
		prefix_report.get("interaction_failures", [])
	)
	(report["solution_action_failures"] as Array).append_array(
		prefix_report.get("solution_action_failures", [])
	)
	report["prefix_nodes"] = prefix_report.get("visited_nodes", [])
	_append_report_event(report, "risky_recovery", "prefix_completed", "Reached risky route start %s through its prerequisites" % risky_source_id, prefix_report)
	_record_animation_snapshot(result, preview_instance, "risky_recovery", "Activated risky route start", {
		"event_type": "node_activated",
		"node_id": risky_source_id,
	})
	var projected_damage := float(risky_route.get("damage", 0.0))
	if projected_damage <= 0.0:
		projected_damage = maxf(8.0, float(int(risky_route.get("cost", 1))) * 8.0)
	_append_report_event(report, "risky_recovery", "route_chosen", "Chose risky route %s" % str(risky_route.get("id", "")), {
		"route": risky_route.duplicate(true),
	})
	_record_animation_snapshot(result, preview_instance, "risky_recovery", "RISKY // projected -%s HP each" % projected_damage, {
		"event_type": "route_pressure_telegraph",
		"route_id": str(risky_route.get("id", "")),
		"route": risky_route.duplicate(true),
		"projected_damage": projected_damage,
		"running": true,
	})
	_advance_preview_with_animation(result, preview_instance, 1.2, "risky_recovery", "Reading the exposed route", {
		"event_type": "route_pressure_anticipation",
		"route_id": str(risky_route.get("id", "")),
		"projected_damage": projected_damage,
	})
	var risky_destination := str(risky_route.get("to", "exit_shelter"))
	var risky_action_report := _diagnostic_apply_solution_actions_before_node(
		preview_instance,
		spec,
		risky_destination,
		consumed_solution_actions,
		result,
		"risky_recovery"
	)
	report["movement_commands"] = int(report.get("movement_commands", 0)) \
		+ int(risky_action_report.get("movement_commands", 0))
	(report["solution_action_failures"] as Array).append_array(
		risky_action_report.get("failures", [])
	)
	if preview_instance.has_method("headless_set_routing_mode"):
		preview_instance.call("headless_set_routing_mode", "direct")
	var risky_move := _diagnostic_move_party_to_node_report(
		preview_instance,
		spec,
		risky_destination,
		result,
		options,
		true,
		"risky_recovery"
	)
	report["movement_commands"] = int(report.get("movement_commands", 0)) + int(risky_move.get("commands", 0))
	_append_report_event(report, "risky_recovery", "party_moved", "Party moved through risky route to %s" % str(risky_route.get("to", "exit_shelter")), risky_move)
	_record_animation_snapshot(result, preview_instance, "risky_recovery", "NEAR MISS // -%s HP each" % projected_damage, {
		"event_type": "route_pressure_impact",
		"route_id": str(risky_route.get("id", "")),
		"damage": projected_damage,
	})
	_advance_preview_with_animation(result, preview_instance, 0.75, "risky_recovery", "Pressure consequence", {
		"event_type": "route_pressure_recovery",
		"route_id": str(risky_route.get("id", "")),
		"damage": projected_damage,
	})
	_capture_node_commit(result, preview_instance, _find_node(spec, str(risky_route.get("to", "exit_shelter"))), "risky_recovery")
	var risky_node := _find_node(spec, risky_destination)
	var risky_runtime_handler := RuntimeRegistryScript.handler_for_node(
		risky_node, str(spec.get("id", ""))
	)
	var risky_interaction_completed := risky_runtime_handler == ""
	if risky_runtime_handler != "":
		var risky_interaction := _diagnostic_interact_generated_node(
			preview_instance, spec, risky_destination, result, "risky_recovery"
		)
		risky_interaction_completed = bool(
			risky_interaction.get("completed", false)
		)
		report["movement_commands"] = int(report.get("movement_commands", 0)) \
			+ int(risky_interaction.get("movement_commands", 0))
		if bool(risky_interaction.get("requested", false)):
			report["physical_interactions"] = int(
				report.get("physical_interactions", 0)
			) + 1
		if not bool(risky_interaction.get("completed", false)):
			(report["interaction_failures"] as Array).append(
				risky_interaction.duplicate(true)
			)
	var risky_event_type := "node_activated" \
		if risky_interaction_completed else "node_interaction_failed"
	var risky_event_label := ("Activated" if risky_interaction_completed \
		else "Failed to activate") + " risky route destination %s" % risky_destination
	_append_report_event(
		report,
		"risky_recovery",
		risky_event_type,
		risky_event_label,
		_node_event_payload(spec, risky_destination, preview_instance)
	)
	_record_animation_snapshot(result, preview_instance, "risky_recovery", risky_event_label, {
		"event_type": risky_event_type,
		"node_id": str(risky_route.get("to", "exit_shelter")),
	})
	var risky_resource := (
		_capture_resource_beat(
			result,
			preview_instance,
			spec,
			risky_destination,
			"risky_recovery"
		)
		if risky_interaction_completed else {}
	)
	if not risky_resource.is_empty():
		report["reward"] = risky_resource
	var recovery_id := str(risky_route.get("recovery", ""))
	if recovery_id != "":
		var recovery_move := _diagnostic_move_party_to_node_report(preview_instance, spec, recovery_id, result, options, false, "risky_recovery")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(recovery_move.get("commands", 0))
		_append_report_event(report, "risky_recovery", "party_moved", "Party moved to recovery node %s" % recovery_id, recovery_move)
		_capture_node_commit(result, preview_instance, _find_node(spec, recovery_id), "risky_recovery")
		var recovery_node := _find_node(spec, recovery_id)
		if RuntimeRegistryScript.handler_for_node(
			recovery_node, str(spec.get("id", ""))
		) != "":
			var recovery_interaction := _diagnostic_interact_generated_node(
				preview_instance, spec, recovery_id, result, "risky_recovery"
			)
			report["movement_commands"] = int(report.get("movement_commands", 0)) \
				+ int(recovery_interaction.get("movement_commands", 0))
			if bool(recovery_interaction.get("requested", false)):
				report["physical_interactions"] = int(
					report.get("physical_interactions", 0)
				) + 1
			if not bool(recovery_interaction.get("completed", false)):
				(report["interaction_failures"] as Array).append(
					recovery_interaction.duplicate(true)
				)
		_append_report_event(report, "risky_recovery", "node_activated", "Activated recovery node %s" % recovery_id, _node_event_payload(spec, recovery_id, preview_instance))
		_record_animation_snapshot(result, preview_instance, "risky_recovery", "Activated recovery node %s" % recovery_id, {
			"event_type": "node_activated",
			"node_id": recovery_id,
		})
	# Rejoin the authored main path at the furthest known destination and finish its
	# suffix normally. This makes the recovery test respect every downstream causal
	# prerequisite instead of teleporting from an early branch straight to shelter.
	var resume_index := risky_source_index
	var risky_destination_index := main_path.find(str(risky_route.get("to", "")))
	if risky_destination_index >= 0:
		resume_index = maxi(resume_index, risky_destination_index)
	var recovery_index := main_path.find(recovery_id)
	if recovery_index >= 0:
		resume_index = maxi(resume_index, recovery_index)
	if resume_index + 1 < main_path.size():
		var suffix_report := _diagnostic_follow_solver_segment(
			preview_instance,
			spec,
			main_path,
			resume_index + 1,
			main_path.size() - 1,
			result,
			options,
			"risky_recovery",
			consumed_solution_actions
		)
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(suffix_report.get("commands", 0))
		report["physical_interactions"] = int(report.get("physical_interactions", 0)) \
			+ int(suffix_report.get("physical_interactions", 0))
		(report["interaction_failures"] as Array).append_array(
			suffix_report.get("interaction_failures", [])
		)
		(report["solution_action_failures"] as Array).append_array(
			suffix_report.get("solution_action_failures", [])
		)
		report["suffix_nodes"] = suffix_report.get("visited_nodes", [])
		_append_report_event(report, "risky_recovery", "suffix_completed", "Rejoined and completed the main route", suffix_report)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	report["damage"] = float(chunk.get("risky_damage_total", 0.0))
	report["recovered"] = bool(chunk.get("shelter_rested", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["route_risk_field"] = chunk.get("route_risk_field", {}).duplicate(true)
	if bool(report.get("recovered", false)):
		_append_report_event(report, "risky_recovery", "shelter_rested", "Risky recovery reached and rested at shelter", {
			"damage": float(chunk.get("risky_damage_total", 0.0)),
			"route_phase": str(chunk.get("route_phase", "")),
			"last_outcome": str(chunk.get("last_outcome", "")),
		})
		_record_animation_snapshot(result, preview_instance, "risky_recovery", "Risky recovery rested", {
			"event_type": "shelter_rested",
			"damage": float(chunk.get("risky_damage_total", 0.0)),
		})
	return report


## Solver-trace mechanism diagnostic. This target-addressed path is deliberately
## quarantined from approval/persona evidence; it exists only to localize a
## generated mechanism failure after the real-input discovery run finds one.
func _diagnostic_interact_generated_node(
	preview_instance: Node,
	spec: Dictionary,
	node_id: String,
	result := {},
	phase := "diagnostic"
) -> Dictionary:
	var report := {
		"node_id": node_id,
		"actor": "",
		"target": "",
		"movement_commands": 0,
		"reached": false,
		"requested": false,
		"completed": false,
		"last_outcome": "",
	}
	if not preview_instance.has_method("headless_call_chunk"):
		report["failure"] = "missing_preview_chunk"
		return report
	var target_v: Variant = preview_instance.call(
		"headless_call_chunk", "get_node_or_null", ["GeneratedNode_%s" % node_id]
	)
	var target := target_v as Node3D if target_v is Node3D else null
	# get_node_or_null is a Node API rather than a chunk script method, so the generic
	# headless_call_chunk seam cannot dispatch it. Resolve against the live chunk only
	# after proving the named target exists; this remains read-only QA discovery.
	if target == null:
		var chunk_v: Variant = preview_instance.get("_active_chunk")
		if chunk_v is Node:
			target = (chunk_v as Node).get_node_or_null(
				"GeneratedNode_%s" % node_id
			) as Node3D
	if target == null or not target.has_signal("interaction_requested"):
		report["failure"] = "missing_interactable"
		return report
	report["target"] = str(target.name)
	var node := _find_node(spec, node_id)
	var approach := _node_approach_position(spec, node_id)
	var actor := _diagnostic_actor_for_target(preview_instance, node, target, approach)
	report["actor"] = actor
	if actor == "":
		report["failure"] = "no_eligible_actor"
		return report
	var formation := _diagnostic_move_party_to_interaction(
		preview_instance, approach, actor, result, phase, node_id
	)
	report["movement_commands"] = int(formation.get("commands", 0))
	report["reached"] = bool(formation.get("actor_reached", false))
	if not bool(report["reached"]):
		report["failure"] = "interaction_approach_unreachable"
		return report
	if preview_instance.has_method("headless_select_character"):
		preview_instance.call("headless_select_character", actor)
	_diagnostic_send_input_action(
		preview_instance, DIAGNOSTIC_GENERATED_INPUT_COMMAND_PREFIX + node_id
	)
	report["requested"] = true
	report["completed"] = _diagnostic_wait_for_node_completion(
		preview_instance, node_id, result, phase
	)
	var final_state: Dictionary = preview_instance.call("headless_get_state")
	report["last_outcome"] = str(
		final_state.get("chunk", {}).get("last_outcome", "")
	)
	if not bool(report["completed"]):
		report["failure"] = "interaction_did_not_complete"
	return report


## Diagnostic replay of solution-owned world/branch actions. Emitted action
## targets are forbidden inputs to persona or approval decision policies.
func _diagnostic_apply_solution_actions_before_node(
	preview_instance: Node,
	spec: Dictionary,
	node_id: String,
	consumed_action_keys: Dictionary,
	result := {},
	phase := "diagnostic"
) -> Dictionary:
	var report := {
		"attempted": 0,
		"completed": 0,
		"movement_commands": 0,
		"failures": [],
		"actions": [],
	}
	var solution: Dictionary = spec.get("headless", {}).get("solution", {})
	var groups := [
		{"namespace": "world", "actions": solution.get("world_actions", [])},
		{"namespace": "branch", "actions": solution.get("branch_actions", [])},
	]
	for group_v in groups:
		var group := group_v as Dictionary
		var action_group := str(group.get("namespace", "action"))
		var actions: Array = group.get("actions", [])
		for index in range(actions.size()):
			var key := "%s:%d" % [action_group, index]
			if consumed_action_keys.has(key):
				continue
			var action_v: Variant = actions[index]
			if not (action_v is Dictionary):
				continue
			var action := action_v as Dictionary
			var before_nodes: Array = action.get(
				"before_nodes", [str(action.get("before_node", ""))]
			)
			if not before_nodes.has(node_id):
				continue
			# One physical attempt is authoritative. Re-running the same action after a
			# rejection would turn a failed prediction into harness retry magic.
			consumed_action_keys[key] = true
			var action_report := _diagnostic_perform_solution_action(
				preview_instance, spec, action, action_group, result, phase
			)
			(report["actions"] as Array).append(action_report)
			report["attempted"] = int(report.get("attempted", 0)) + 1
			report["movement_commands"] = int(report.get("movement_commands", 0)) \
				+ int(action_report.get("movement_commands", 0))
			if bool(action_report.get("completed", false)):
				report["completed"] = int(report.get("completed", 0)) + 1
			else:
				(report["failures"] as Array).append(action_report.duplicate(true))
	return report


func _diagnostic_perform_solution_action(
	preview_instance: Node,
	spec: Dictionary,
	action: Dictionary,
	action_group: String,
	result := {},
	phase := "diagnostic"
) -> Dictionary:
	var action_id := _diagnostic_solution_action_target_id(action, action_group)
	var report := {
		"namespace": action_group,
		"action_id": action_id,
		"branch_id": str(action.get("branch_id", "")),
		"movement_commands": 0,
		"reached": false,
		"requested": false,
		"completed": false,
	}
	if action_id == "":
		report["failure"] = "missing_action_target"
		return report
	var target_v: Variant = preview_instance.call(
		"headless_call_chunk", "get_playthrough_interaction_target", [action_id]
	)
	var target := target_v as Node3D if target_v is Node3D else null
	if target == null or not target.has_signal("interaction_requested"):
		report["failure"] = "missing_action_interactable"
		return report
	var target_data := _diagnostic_action_data_position(
		preview_instance, spec, action, target
	)
	if target_data == Vector3.INF:
		report["failure"] = "missing_action_position"
		return report
	var actor := _diagnostic_actor_for_target(preview_instance, {}, target, target_data)
	report["actor"] = actor
	if actor == "":
		report["failure"] = "no_eligible_actor"
		return report
	var movement := _diagnostic_move_actor(
		preview_instance, actor, target_data, result, phase, action_id
	)
	report["movement_commands"] = int(movement.get("commands", 0))
	report["reached"] = bool(movement.get("reached", false))
	if not bool(report["reached"]):
		report["failure"] = "action_source_unreachable"
		return report
	if preview_instance.has_method("headless_select_character"):
		preview_instance.call("headless_select_character", actor)
	_diagnostic_send_input_action(
		preview_instance, DIAGNOSTIC_WORLD_INPUT_COMMAND_PREFIX + action_id
	)
	report["requested"] = true
	report["completed"] = _diagnostic_wait_for_solution_action(
		preview_instance, action, action_group, result, phase, action_id
	)
	if not bool(report["completed"]):
		report["failure"] = "action_did_not_reach_authoritative_state"
		var state: Dictionary = preview_instance.call("headless_get_state")
		report["last_outcome"] = str(
			state.get("chunk", {}).get("last_outcome", "")
		)
	return report


func _diagnostic_solution_action_target_id(
	action: Dictionary, action_group: String
) -> String:
	if action_group == "branch":
		return str(action.get("id", ""))
	match str(action.get("action", "")):
		"enter_shelter":
			return "enter_shelter"
	return str(action.get("target", ""))


func _diagnostic_action_data_position(
	preview_instance: Node,
	spec: Dictionary,
	action: Dictionary,
	target: Node3D
) -> Vector3:
	# The live registered source owns its exact data-space level. A flattened
	# serialized producer cell cannot reconstruct stacked-grid Y on its own.
	var gs_v: Variant = preview_instance.get("_game_state")
	var data_id := str(target.get("data_id")) if "data_id" in target else ""
	if gs_v != null and data_id != "" \
			and (gs_v as Object).has_method("has_interactable") \
			and bool((gs_v as Object).call("has_interactable", data_id)):
		var registered: Dictionary = (gs_v as Object).call(
			"get_interactable", data_id
		)
		var registered_position_v: Variant = registered.get(
			"position", Vector3.INF
		)
		if registered_position_v is Vector3 \
				and (registered_position_v as Vector3).is_finite():
			return registered_position_v as Vector3
	if target.has_meta("flat_authored_position"):
		var authored_v: Variant = target.get_meta("flat_authored_position")
		if authored_v is Vector3:
			return authored_v as Vector3
	var producer_cell_v: Variant = action.get("producer_cell", [])
	if producer_cell_v is Array and (producer_cell_v as Array).size() >= 2:
		return _navigation_cell_position(
			spec.get("navigation_grid", {}), producer_cell_v as Array
		)
	var world_target := target.global_position
	if target.has_method("get_interaction_target_position"):
		var resolved_v: Variant = target.call(
			"get_interaction_target_position", Vector3.ZERO, target.global_position
		)
		if resolved_v is Vector3:
			world_target = resolved_v as Vector3
	if gs_v != null and (gs_v as Object).get("coord_map") != null:
		return (gs_v as Object).get("coord_map").to_data(world_target)
	return world_target


func _navigation_cell_position(navigation: Dictionary, cell: Array) -> Vector3:
	if cell.size() < 2:
		return Vector3.INF
	var origin := _vec3(navigation.get("origin", []), Vector3.ZERO)
	var cell_size := float(navigation.get("cell_size", 1.0))
	return Vector3(
		origin.x + (float(cell[0]) + 0.5) * cell_size,
		origin.y,
		origin.z + (float(cell[1]) + 0.5) * cell_size
	)


func _diagnostic_actor_for_target(
	preview_instance: Node,
	node: Dictionary,
	target: Node,
	target_data: Vector3
) -> String:
	var state: Dictionary = preview_instance.call("headless_get_state")
	var active_party: Array = state.get("chunk", {}).get("active_party", PARTY_IDS)
	if active_party.is_empty():
		active_party = PARTY_IDS.duplicate()
	var required := ""
	if target != null and "required_character" in target:
		required = str(target.get("required_character"))
	if required == "" and target != null and target.has_method("get_interaction_delegate"):
		var delegate_v: Variant = target.call("get_interaction_delegate")
		if delegate_v != null and "required_character" in delegate_v:
			required = str((delegate_v as Object).get("required_character"))
	if required != "" and active_party.has(required):
		return required
	var gs_v: Variant = preview_instance.get("_game_state")
	var needs_free_hand := RuntimeRegistryScript.handler_for_node(
		node, ""
	) in [
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
	]
	if gs_v != null and (gs_v as Object).has_method("pick_interactor"):
		return str((gs_v as Object).call(
			"pick_interactor", "", target_data, active_party, needs_free_hand
		))
	return str(active_party[0]) if not active_party.is_empty() else ""


func _diagnostic_move_party_to_interaction(
	preview_instance: Node,
	target: Vector3,
	actor: String,
	result: Dictionary,
	phase: String,
	label: String
) -> Dictionary:
	var report := {"commands": 0, "actor_reached": false}
	var state: Dictionary = preview_instance.call("headless_get_state")
	var active_party: Array = state.get("chunk", {}).get("active_party", PARTY_IDS)
	if active_party.is_empty():
		active_party = PARTY_IDS.duplicate()
	var longest_duration := 0.0
	for char_id_v in active_party:
		var char_id := str(char_id_v)
		var offset := _diagnostic_formation_offset(char_id, actor)
		var move := _diagnostic_move_actor(
			preview_instance,
			char_id,
			target + offset,
			result,
			phase,
			"%s:%s" % [label, char_id],
			false
		)
		report["commands"] = int(report.get("commands", 0)) \
			+ int(move.get("commands", 0))
		longest_duration = maxf(
			longest_duration, float(move.get("duration", 0.0))
		)
		if char_id == actor:
			report["actor_reached"] = bool(move.get("reached", false))
	report["duration"] = longest_duration
	return report


func _diagnostic_formation_offset(char_id: String, actor: String) -> Vector3:
	if char_id == actor:
		return Vector3.ZERO
	if char_id == "aster" and actor != "aster":
		return PARTY_OFFSETS.get(actor, Vector3(1.4, 0.0, 0.0)) as Vector3
	return PARTY_OFFSETS.get(char_id, Vector3(1.4, 0.0, 0.0)) as Vector3


func _diagnostic_move_actor(
	preview_instance: Node,
	actor: String,
	target: Vector3,
	result: Dictionary,
	phase: String,
	label: String,
	capture := true
) -> Dictionary:
	var report := {
		"actor": actor,
		"target": _vec3_array(target),
		"commands": 0,
		"duration": 0.0,
		"reached": false,
	}
	if not preview_instance.has_method("headless_move_character") \
			or not preview_instance.has_method("headless_advance"):
		return report
	var commanded := bool(preview_instance.call(
		"headless_move_character", actor, target, false
	))
	if not commanded:
		return report
	report["commands"] = 1
	var movement_info: Dictionary = (
		preview_instance.call("headless_get_character_movement_info", actor)
		if preview_instance.has_method("headless_get_character_movement_info")
		else {}
	)
	var duration := float(movement_info.get("duration", 0.0)) + 0.2
	if is_nan(duration) or is_inf(duration) \
			or duration < 0.0 or duration > PHYSICAL_INTERACTION_TIMEOUT:
		report["duration_invalid"] = true
		return report
	duration = maxf(0.1, duration)
	report["duration"] = duration
	if capture:
		_advance_preview_with_animation(
			result, preview_instance, duration, phase, "Approaching %s" % label, {
				"event_type": "physical_interaction_approach",
				"actor": actor,
				"target": report["target"],
				"label": label,
			}
		)
	else:
		preview_instance.call("headless_advance", duration, 0.05)
	var remaining := maxf(0.0, PHYSICAL_INTERACTION_TIMEOUT - duration)
	while remaining > 0.0 and preview_instance.has_method(
		"headless_is_character_moving"
	) and bool(preview_instance.call("headless_is_character_moving", actor)):
		var step := minf(0.25, remaining)
		preview_instance.call("headless_advance", step, 0.05)
		remaining -= step
	report["reached"] = _diagnostic_actor_reached(
		preview_instance, actor, target
	)
	return report


func _diagnostic_actor_reached(
	preview_instance: Node, actor: String, target: Vector3
) -> bool:
	if preview_instance.has_method("headless_is_character_moving") \
			and bool(preview_instance.call("headless_is_character_moving", actor)):
		return false
	var state: Dictionary = preview_instance.call("headless_get_state")
	var actual := _vec3(
		state.get("characters", {}).get(actor, Vector3.INF), Vector3.INF
	)
	if actual == Vector3.INF:
		return false
	var gs_v: Variant = preview_instance.get("_game_state")
	if gs_v != null and (gs_v as Object).get("grid") != null:
		var grid_v: Variant = (gs_v as Object).get("grid")
		return grid_v.world_to_grid(actual) == grid_v.world_to_grid(target)
	return actual.distance_to(target) <= 0.35


func _diagnostic_send_input_action(
	preview_instance: Node, action_name: String
) -> void:
	var pressed := InputEventAction.new()
	pressed.action = StringName(action_name)
	pressed.pressed = true
	pressed.strength = 1.0
	# headless_advance advances the authoritative schedulers without pumping a
	# SceneTree render/input frame. Deliver the same InputEventAction to the
	# preview's normal _input entry point in that mode; windowed/recording runs
	# still travel through Input.parse_input_event and PlaythroughSession.
	if DisplayServer.get_name() == "headless" \
			and preview_instance.has_method("_input"):
		preview_instance.call("_input", pressed)
	else:
		Input.parse_input_event(pressed)
	var released := pressed.duplicate() as InputEventAction
	released.pressed = false
	released.strength = 0.0
	if DisplayServer.get_name() == "headless" \
			and preview_instance.has_method("_input"):
		preview_instance.call("_input", released)
	else:
		Input.parse_input_event(released)


func _diagnostic_wait_for_node_completion(
	preview_instance: Node,
	node_id: String,
	result: Dictionary,
	phase: String
) -> bool:
	var remaining := PHYSICAL_INTERACTION_TIMEOUT
	while remaining >= 0.0:
		if _diagnostic_node_completed(preview_instance, node_id):
			return true
		var step := minf(0.1, remaining)
		if step <= 0.0:
			break
		_advance_preview_with_animation(
			result, preview_instance, step, phase, "Interacting with %s" % node_id, {
				"event_type": "physical_interaction_wait",
				"node_id": node_id,
			}
		)
		remaining -= step
	return _diagnostic_node_completed(preview_instance, node_id)


func _diagnostic_node_completed(preview_instance: Node, node_id: String) -> bool:
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	if node_id == "exit_shelter":
		return bool(chunk.get("shelter_rested", false))
	return (chunk.get("generation", {}).get("completed_nodes", []) as Array).has(
		node_id
	)


func _diagnostic_wait_for_solution_action(
	preview_instance: Node,
	action: Dictionary,
	action_group: String,
	result: Dictionary,
	phase: String,
	action_id: String
) -> bool:
	var remaining := PHYSICAL_INTERACTION_TIMEOUT
	while remaining >= 0.0:
		if _diagnostic_solution_action_completed(
			preview_instance, action, action_group
		):
			return true
		var step := minf(0.1, remaining)
		if step <= 0.0:
			break
		_advance_preview_with_animation(
			result, preview_instance, step, phase, "Resolving %s" % action_id, {
				"event_type": "physical_world_action_wait",
				"action_id": action_id,
				"namespace": action_group,
			}
		)
		remaining -= step
	return _diagnostic_solution_action_completed(
		preview_instance, action, action_group
	)


func _diagnostic_solution_action_completed(
	preview_instance: Node, action: Dictionary, action_group: String
) -> bool:
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	if action_group == "branch":
		var branch_id := str(action.get(
			"branch_id", action.get("target", "")
		))
		var expected := str(action.get("expected_phase", "bridged"))
		for span_v in chunk.get("branch_span_states", []):
			if span_v is Dictionary \
					and str((span_v as Dictionary).get("branch_id", "")) == branch_id:
				return str((span_v as Dictionary).get("phase", "")) == expected
		return false
	match str(action.get("action", "")):
		"enter_shelter":
			return bool(chunk.get("shelter_rested", false))
	return false


## Kept only for focused data-layer diagnostics. Player-evidence paths must never call
## this helper: it bypasses movement, interaction assignment, inventory, and risk contact.
func _diagnostic_direct_activate_generated_node(
	preview_instance: Node, node_id: String
) -> bool:
	return bool(preview_instance.call(
		"headless_call_chunk", "activate_generated_node", [node_id]
	))


func _diagnostic_follow_solver_segment(
	preview_instance: Node,
	spec: Dictionary,
	path: Array,
	start_index: int,
	end_index: int,
	result := {},
	options := {},
	phase := "movement",
	consumed_solution_actions := {}
) -> Dictionary:
	var report := {
		"commands": 0,
		"visited_nodes": [],
		"route_ids": [],
		"physical_interactions": 0,
		"interaction_failures": [],
		"solution_action_failures": [],
	}
	if path.is_empty() or start_index > end_index:
		return report
	var first := maxi(0, start_index)
	var last := mini(end_index, path.size() - 1)
	for i in range(first, last + 1):
		var node_id := str(path[i])
		var action_report := _diagnostic_apply_solution_actions_before_node(
			preview_instance,
			spec,
			node_id,
			consumed_solution_actions,
			result,
			phase
		)
		report["commands"] = int(report.get("commands", 0)) \
			+ int(action_report.get("movement_commands", 0))
		(report["solution_action_failures"] as Array).append_array(
			action_report.get("failures", [])
		)
		var running_for_move := _node_suggests_running(_find_node(spec, node_id))
		if i > 0:
			var route_id := _find_route_id(spec, str(path[i - 1]), node_id, ["safe", "shortcut"])
			if route_id != "":
				var route_def := _find_route(spec, route_id)
				running_for_move = running_for_move or _route_suggests_running(route_def)
				(report["route_ids"] as Array).append(route_id)
		var move_report := _diagnostic_move_party_to_node_report(
			preview_instance, spec, node_id, result, options, running_for_move, phase
		)
		report["commands"] = int(report.get("commands", 0)) + int(move_report.get("commands", 0))
		var current_node := _find_node(spec, node_id)
		_capture_node_commit(result, preview_instance, current_node, phase)
		if RuntimeRegistryScript.handler_for_node(current_node, str(spec.get("id", ""))) != "":
			var interaction := _diagnostic_interact_generated_node(
				preview_instance, spec, node_id, result, phase
			)
			report["commands"] = int(report.get("commands", 0)) \
				+ int(interaction.get("movement_commands", 0))
			if bool(interaction.get("requested", false)):
				report["physical_interactions"] = int(
					report.get("physical_interactions", 0)
				) + 1
			if not bool(interaction.get("completed", false)):
				(report["interaction_failures"] as Array).append(
					interaction.duplicate(true)
				)
		(report["visited_nodes"] as Array).append(node_id)
	return report

func _diagnostic_move_party_to_node(preview_instance: Node, spec: Dictionary, node_id: String) -> int:
	return int(_diagnostic_move_party_to_node_report(preview_instance, spec, node_id).get("commands", 0))

func _diagnostic_move_party_to_node_report(preview_instance: Node, spec: Dictionary, node_id: String, result := {}, options := {}, running := false, phase := "movement") -> Dictionary:
	var report := {
		"node_id": node_id,
		"target": _vec3_array(_node_position(spec, node_id)),
		"commands": 0,
		"max_duration": 0.0,
		"characters": [],
		"running": running,
	}
	if not preview_instance.has_method("headless_move_character") or not preview_instance.has_method("headless_advance"):
		return report
	var target := _node_position(spec, node_id)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var current_positions: Dictionary = state.get("characters", {})
	var active_party: Array = state.get("chunk", {}).get("active_party", PARTY_IDS)
	if active_party.is_empty():
		active_party = PARTY_IDS.duplicate()
	var longest_duration := 0.0
	var commands := 0
	var max_path_points := 0
	var used_multi_y_path := false
	var invalid_movement_durations: Array[String] = []
	for char_id_v in active_party:
		var char_id := str(char_id_v)
		var target_pos := target + (PARTY_OFFSETS.get(char_id, Vector3.ZERO) as Vector3)
		var current_pos := _vec3(current_positions.get(char_id, target_pos), target_pos)
		var distance := current_pos.distance_to(target_pos)
		var commanded := bool(preview_instance.call("headless_move_character", char_id, target_pos, running))
		var movement_info: Dictionary = preview_instance.call("headless_get_character_movement_info", char_id) if preview_instance.has_method("headless_get_character_movement_info") else {}
		var movement_duration := 0.0
		if commanded:
			movement_duration = float(movement_info.get(
				"duration", distance / float(CHARACTER_SPEEDS.get(char_id, 3.0))
			)) + 0.15
			if is_nan(movement_duration) or is_inf(movement_duration) \
					or movement_duration < 0.0 \
					or movement_duration > MAX_PLAYTEST_ADVANCE_SECONDS:
				invalid_movement_durations.append(char_id)
				movement_duration = 0.0
			else:
				longest_duration = maxf(longest_duration, movement_duration)
		max_path_points = maxi(max_path_points, int(movement_info.get("path_count", 0)))
		used_multi_y_path = used_multi_y_path or _serialized_path_uses_multiple_y(movement_info.get("path", []))
		if commanded:
			commands += 1
		(report["characters"] as Array).append({
			"character": char_id,
			"from": _vec3_array(current_pos),
			"to": _vec3_array(target_pos),
			"distance": distance,
			"commanded": commanded,
			"running": bool(movement_info.get("running", running)),
			"locomotion": str(movement_info.get("locomotion", "run" if running else "walk")),
			"speed": float(movement_info.get("speed", CHARACTER_SPEEDS.get(char_id, 3.0))),
			"path_count": int(movement_info.get("path_count", 0)),
			"path": movement_info.get("path", []),
		})
	report["commands"] = commands
	report["max_duration"] = longest_duration
	report["max_path_points"] = max_path_points
	report["used_multi_y_path"] = used_multi_y_path
	report["invalid_movement_durations"] = invalid_movement_durations
	if commands > 0:
		_record_animation_snapshot(result, preview_instance, phase, "Move started to %s" % node_id, {
			"event_type": "party_move_started",
			"node_id": node_id,
			"target": report["target"],
			"running": running,
			"characters": report["characters"],
		})
	if longest_duration > 0.0:
		_advance_preview_with_animation(result, preview_instance, longest_duration, phase, "Moving to %s" % node_id, {
			"event_type": "party_moving",
			"node_id": node_id,
			"target": report["target"],
			"running": running,
		})
	# `headless_get_character_movement_info()` describes the currently active
	# planar leg. A typed multi-level command can hand that leg off to a ladder,
	# ramp, or later planar leg at its deadline, so advancing only the reported
	# duration leaves the party authoritatively in flight. The next physical
	# interaction would then be rejected by the ordinary move-command guard and
	# falsely look like disconnected generated topology. Drain the same live
	# GameState plans to completion; do not snap, teleport, or infer arrival from
	# the first segment's endpoint.
	var settle_duration := 0.0
	var settle_remaining := maxf(
		0.0, MAX_PLAYTEST_ADVANCE_SECONDS - longest_duration
	)
	var moving_characters := _diagnostic_moving_characters(
		preview_instance, active_party
	)
	while not moving_characters.is_empty() and settle_remaining > 0.0:
		var step := minf(0.25, settle_remaining)
		preview_instance.call("headless_advance", step, 0.05)
		settle_duration += step
		settle_remaining -= step
		moving_characters = _diagnostic_moving_characters(
			preview_instance, active_party
		)
	report["settle_duration"] = settle_duration
	report["total_advance_duration"] = longest_duration + settle_duration
	report["movement_completed"] = moving_characters.is_empty()
	report["still_moving_characters"] = moving_characters
	if commands > 0:
		_record_animation_snapshot(result, preview_instance, phase, "Arrived at %s" % node_id, {
			"event_type": "party_arrived",
			"node_id": node_id,
			"target": report["target"],
			"running": running,
			"movement_completed": moving_characters.is_empty(),
			"still_moving_characters": moving_characters,
		})
	return report


func _diagnostic_moving_characters(
	preview_instance: Node, active_party: Array
) -> Array[String]:
	var moving: Array[String] = []
	if not preview_instance.has_method("headless_is_character_moving"):
		return moving
	for char_id_v in active_party:
		var char_id := str(char_id_v)
		if bool(preview_instance.call("headless_is_character_moving", char_id)):
			moving.append(char_id)
	return moving

func _base_animation_report(spec: Dictionary, options: Dictionary) -> Dictionary:
	return {
		"contract_id": ANIMATION_CONTRACT_ID,
		"source_contract": "stretch_generation_playtest_loop_v1",
		"spec_id": str(spec.get("id", "")),
		"title": str(spec.get("title", "")),
		"preview_scene": GENERATED_STRETCH_PREVIEW_SCENE_PATH,
		"preview_party_preset": str(spec.get("world_slot", {}).get("preview_party_preset", "full_party_full_health")),
		"capture_step": maxf(0.05, float(options.get("capture_step", DEFAULT_CAPTURE_STEP))),
		"party": PARTY_IDS.duplicate(),
		"world_slot": _json_safe(spec.get("world_slot", {})),
		"layout": _build_animation_layout(spec),
		"snapshots": [],
		"events": [],
		"snapshot_count": 0,
		"event_count": 0,
		"duration": 0.0,
		"summary": {},
	}

func _build_animation_layout(spec: Dictionary) -> Dictionary:
	var nodes := []
	for raw_node in spec.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := (raw_node as Dictionary).duplicate(true)
		var node_id := str(node.get("id", ""))
		node["position"] = _vec3_array(_node_position(spec, node_id))
		var realized_placements := []
		if node.has("content_placements"):
			for placement_v in node.get("content_placements", []):
				if not (placement_v is Dictionary):
					continue
				var placement := placement_v as Dictionary
				if RuntimeRegistryScript.generated_content_is_realized(
					str(placement.get("category", "")),
					str(placement.get("id", placement.get("key", "")))
				):
					realized_placements.append(placement.duplicate(true))
		else:
			# True legacy layouts get only proven runtime content at the node origin;
			# HTML capture must never resurrect unbound nouns as diagram symbols.
			for category in ["flora", "enemies", "structures"]:
				for content_id_v in node.get(category, []):
					var content_id := str(content_id_v)
					if RuntimeRegistryScript.generated_content_is_realized(category, content_id):
						realized_placements.append({
							"id": content_id,
							"category": category,
							"position": node["position"],
							"size": [0.8, 0.8, 0.8],
						})
		node["content_placements"] = realized_placements
		nodes.append(node)
	var routes := []
	for raw_route in spec.get("routes", []):
		if raw_route is Dictionary:
			routes.append((raw_route as Dictionary).duplicate(true))
	return _json_safe({
		"contract_id": "playthrough_animation_layout_v1",
		"nodes": nodes,
		"routes": routes,
		"anchors": spec.get("anchors", {}).duplicate(true),
		"graybox": spec.get("graybox", {}).duplicate(true),
		"navigation": spec.get("navigation", {}).duplicate(true),
		"palette_usage": spec.get("palette_usage", {}).duplicate(true),
		"composition": spec.get("composition", {}).duplicate(true),
	})

func _capture_enabled(result: Dictionary) -> bool:
	var animation: Dictionary = result.get("animation", {})
	return str(animation.get("contract_id", "")) == ANIMATION_CONTRACT_ID

func _capture_step(result: Dictionary) -> float:
	var animation: Dictionary = result.get("animation", {})
	return maxf(0.05, float(animation.get("capture_step", DEFAULT_CAPTURE_STEP)))

func _advance_preview_with_animation(result: Dictionary, preview_instance: Node, duration: float, phase: String, label: String, data := {}) -> void:
	if not preview_instance.has_method("headless_advance") or duration <= 0.0 \
			or is_nan(duration) or is_inf(duration) \
			or duration > MAX_PLAYTEST_ADVANCE_SECONDS:
		return
	if not _capture_enabled(result):
		preview_instance.call("headless_advance", duration, 0.05)
		return
	var remaining := duration
	var elapsed := 0.0
	var step := _capture_step(result)
	while remaining > 0.0001:
		var dt := minf(step, remaining)
		preview_instance.call("headless_advance", dt, minf(dt, 0.05))
		elapsed += dt
		remaining -= dt
		var snapshot_data := data.duplicate(true) if data is Dictionary else {}
		snapshot_data["elapsed"] = elapsed
		snapshot_data["duration"] = duration
		_record_animation_snapshot(result, preview_instance, phase, label, snapshot_data)

func _record_animation_snapshot(result: Dictionary, preview_instance: Node, phase: String, label: String, data := {}) -> void:
	if not _capture_enabled(result) or not preview_instance.has_method("headless_get_state"):
		return
	var animation: Dictionary = result.get("animation", {})
	var snapshots: Array = animation.get("snapshots", [])
	var state: Dictionary = preview_instance.call("headless_get_state")
	var snapshot := {
		"index": snapshots.size() + 1,
		"time": float(state.get("scheduler_tick", 0.0)),
		"phase": phase,
		"label": label,
		"data": _json_safe(data),
		"active_character": str(state.get("active_character", "")),
		"selected_characters": _json_safe(state.get("selected_characters", [])),
		"run_active": bool(state.get("run_active", false)),
		"clock": _json_safe(state.get("clock", {})),
		"characters": _capture_animation_characters(preview_instance, state),
		"abilities": _json_safe(state.get("abilities", {})),
		"inventory": _capture_animation_inventory(state.get("inventory", {})),
		"chunk": _capture_animation_chunk(state.get("chunk", {})),
		"navigation": _json_safe(state.get("navigation", {})),
	}
	snapshots.append(snapshot)
	animation["snapshots"] = snapshots
	animation["snapshot_count"] = snapshots.size()
	result["animation"] = animation

func _capture_animation_characters(preview_instance: Node, state: Dictionary) -> Dictionary:
	var result := {}
	var positions: Dictionary = state.get("characters", {})
	var stats: Dictionary = state.get("character_stats", {})
	var inventory: Dictionary = state.get("inventory", {})
	var endocytosing: Dictionary = inventory.get("endocytosing", {})
	for char_id in PARTY_IDS:
		var movement_info: Dictionary = preview_instance.call("headless_get_character_movement_info", char_id) if preview_instance.has_method("headless_get_character_movement_info") else {"moving": false}
		var char_stats: Dictionary = stats.get(char_id, {})
		var char_inventory: Dictionary = inventory.get(char_id, {})
		var hand_slots: Array = char_inventory.get("hand_slots", [])
		var hand_labels := []
		for slot_v in hand_slots:
			var item_id := str(slot_v) if slot_v != null else ""
			if item_id == "":
				hand_labels.append("")
				continue
			var item: Dictionary = preview_instance.call("get_preview_item_state", item_id) if preview_instance.has_method("get_preview_item_state") else {}
			hand_labels.append(str(item.get("properties", {}).get("display_name", item.get("type", item_id))))
		var is_consuming := bool(endocytosing.get(char_id, false))
		var moving := bool(movement_info.get("moving", false))
		var running := bool(movement_info.get("running", false))
		var locomotion := "consume" if is_consuming else ("run" if moving and running else ("walk" if moving else "idle"))
		result[char_id] = {
			"position": _vec3_array(_vec3(positions.get(char_id, Vector3.ZERO), Vector3.ZERO)),
			"moving": moving,
			"running": running,
			"locomotion": locomotion,
			"speed": float(movement_info.get("speed", CHARACTER_SPEEDS.get(char_id, 3.0))),
			"movement": _json_safe(movement_info),
			"stats": _json_safe(char_stats),
			"status": str(char_stats.get("status", "")),
			"hands": _json_safe(char_inventory.get("hands", [])),
			"hand_slots": _json_safe(hand_slots),
			"hand_labels": _json_safe(hand_labels),
			"internal": _json_safe(char_inventory.get("internal", [])),
			"endocytosing": is_consuming,
		}
	return result

func _capture_animation_inventory(inventory: Variant) -> Dictionary:
	if not (inventory is Dictionary):
		return {}
	var source := inventory as Dictionary
	var result := {
		"collection": _json_safe(source.get("collection", [])),
		"endocytosing": _json_safe(source.get("endocytosing", {})),
	}
	for char_id in PARTY_IDS:
		result[char_id] = _json_safe(source.get(char_id, {}))
	return result

func _capture_animation_chunk(chunk: Variant) -> Dictionary:
	if not (chunk is Dictionary):
		return {}
	var source := chunk as Dictionary
	var generation: Dictionary = source.get("generation", {})
	return _json_safe({
		"contract_id": str(source.get("contract_id", "")),
		"spec_id": str(source.get("spec_id", "")),
		"route_choice": str(source.get("route_choice", "")),
		"route_phase": str(source.get("route_phase", "")),
		"shelter_reached": bool(source.get("shelter_reached", false)),
		"shelter_rested": bool(source.get("shelter_rested", false)),
		"shortcut_unlocked": bool(source.get("shortcut_unlocked", false)),
		"first_shelter_beat_fired": bool(source.get("first_shelter_beat_fired", false)),
		"last_outcome": str(source.get("last_outcome", "")),
		"risky_damage_total": float(source.get("risky_damage_total", 0.0)),
		"scarcity_clock_started": bool(source.get("scarcity_clock_started", false)),
		"scarcity_drain_armed": bool(source.get("scarcity_drain_armed", false)),
		"scarcity_drain_ticks": int(source.get("scarcity_drain_ticks", 0)),
		"scarcity_atp_drained": float(source.get("scarcity_atp_drained", 0.0)),
		"scarcity_hp_drained": float(source.get("scarcity_hp_drained", 0.0)),
		"scarcity_hp_absorbed": float(source.get("scarcity_hp_absorbed", 0.0)),
		"scarcity_zero_atp_hp_drain_per_character": float(
			source.get("scarcity_zero_atp_hp_drain_per_character", 0.0)
		),
		"resources_collected": int(generation.get("resources_collected", 0)),
		"active_loadout": str(source.get("active_loadout", generation.get("active_loadout", "spotlight"))),
		"active_party": source.get("active_party", generation.get("active_party", PARTY_IDS)),
		"completed_nodes": generation.get("completed_nodes", []),
		"activated_routes": generation.get("activated_routes", []),
		"produced_chain_states": source.get("produced_chain_states", generation.get("produced_chain_states", {})),
		"delivered_resource_nodes": source.get("delivered_resource_nodes", generation.get("delivered_resource_nodes", [])),
		"graybox": source.get("graybox", {}),
	})

func _finish_animation_report(result: Dictionary) -> void:
	if not _capture_enabled(result):
		return
	var animation: Dictionary = result.get("animation", {})
	var snapshots: Array = animation.get("snapshots", [])
	animation["events"] = _json_safe(result.get("events", []))
	animation["event_count"] = (result.get("events", []) as Array).size()
	animation["snapshot_count"] = snapshots.size()
	if snapshots.size() >= 2:
		var first_snapshot: Dictionary = snapshots[0]
		var last_snapshot: Dictionary = snapshots[snapshots.size() - 1]
		animation["duration"] = maxf(0.0, float(last_snapshot.get("time", 0.0)) - float(first_snapshot.get("time", 0.0)))
	animation["summary"] = _summarize_animation_snapshots(snapshots)
	result["animation"] = animation
	_record_check(result, "playthrough_animation_contract", str(animation.get("contract_id", "")) == ANIMATION_CONTRACT_ID, "Animation report uses the playthrough animation contract")
	_record_check(result, "playthrough_animation_snapshots", snapshots.size() >= 8, "Animation report records state snapshots")
	_record_check(result, "playthrough_animation_walk_state", bool(animation.get("summary", {}).get("has_walk_state", false)), "Animation report captures walk state")
	_record_check(result, "playthrough_animation_run_state", bool(animation.get("summary", {}).get("has_run_state", false)), "Animation report captures run state")
	_record_check(result, "playthrough_animation_inventory_state", bool(animation.get("summary", {}).get("has_hand_slots", false)), "Animation report captures hand-slot state")

func _summarize_animation_snapshots(snapshots: Array) -> Dictionary:
	var summary := {
		"has_walk_state": false,
		"has_run_state": false,
		"has_consume_state": false,
		"has_hand_slots": false,
		"has_held_item": false,
		"has_internal_item": false,
		"has_endocytosis": false,
		"has_multilevel_path": false,
	}
	for raw_snapshot in snapshots:
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot := raw_snapshot as Dictionary
		var characters: Dictionary = snapshot.get("characters", {})
		for char_id in characters.keys():
			var character: Dictionary = characters.get(char_id, {})
			var locomotion := str(character.get("locomotion", ""))
			summary["has_walk_state"] = bool(summary["has_walk_state"]) or locomotion == "walk"
			summary["has_run_state"] = bool(summary["has_run_state"]) or locomotion == "run"
			summary["has_consume_state"] = bool(summary["has_consume_state"]) or locomotion == "consume"
			summary["has_endocytosis"] = bool(summary["has_endocytosis"]) or bool(character.get("endocytosing", false))
			var hand_slots: Array = character.get("hand_slots", [])
			if hand_slots.size() > 0:
				summary["has_hand_slots"] = true
			for slot in hand_slots:
				if slot != null and str(slot) != "":
					summary["has_held_item"] = true
			var internal: Array = character.get("internal", [])
			if not internal.is_empty():
				summary["has_internal_item"] = true
			var movement: Dictionary = character.get("movement", {})
			summary["has_multilevel_path"] = bool(summary["has_multilevel_path"]) or _serialized_path_uses_multiple_y(movement.get("path", []))
	return summary


func _capture_node_commit(
	result: Dictionary,
	preview_instance: Node,
	node: Dictionary,
	phase: String
) -> void:
	if node.is_empty() or not preview_instance.has_method("headless_advance"):
		return
	if str(node.get("runtime_handler", "")) == "":
		return
	var node_id := str(node.get("id", ""))
	var role := str(node.get("role", ""))
	if node_id == "entry" or role == "boundary":
		return
	var action := str(node.get("action_verb", ""))
	if action == "":
		return
	var prediction := str(node.get("prediction_hint", node.get("systems_beat", {}).get("prediction", "")))
	_record_animation_snapshot(result, preview_instance, phase, "%s // predict the result" % action, {
		"event_type": "system_prediction",
		"node_id": node_id,
		"action_verb": action,
		"prediction": prediction,
	})
	_advance_preview_with_animation(result, preview_instance, 0.45, phase, "Reading the causal tell", {
		"event_type": "system_prediction_dwell",
		"node_id": node_id,
		"action_verb": action,
		"prediction": prediction,
	})
	var work_duration := 0.7
	if node_id == "exit_shelter" or role in ["shelter", "shelter_arrival"]:
		work_duration = 1.4
	elif bool(node.get("resource", false)) and str(node.get("survival_kind", "")) == "":
		work_duration = 1.8
	_advance_preview_with_animation(result, preview_instance, work_duration, phase, action, {
		"event_type": "system_intervention",
		"node_id": node_id,
		"action_verb": action,
	})

func _capture_resource_beat(result: Dictionary, preview_instance: Node, spec: Dictionary, node_id: String, phase := "golden_path") -> Dictionary:
	var node := _find_node(spec, node_id)
	if not bool(node.get("resource", false)):
		return {}
	var held_resource := _held_generated_resource(preview_instance, node_id)
	if not held_resource.is_empty():
		var holder := str(held_resource.get("character", ""))
		var held_item_id := str(held_resource.get("item_id", ""))
		_record_animation_snapshot(result, preview_instance, phase, "%s is visibly holding the resource" % holder.capitalize(), {
			"event_type": "resource_held",
			"node_id": node_id,
			"item_id": held_item_id,
			"character": holder,
			"action_verb": str(node.get("action_verb", "SECURE RESOURCE")),
		})
		_advance_preview_with_animation(result, preview_instance, 1.6, phase, "Carrier decision: hold, lock, or transfer", {
			"event_type": "resource_carrier_decision",
			"node_id": node_id,
			"item_id": held_item_id,
			"character": holder,
		})
		held_resource["retained_in_hand"] = true
		return held_resource
	var systems_verb := str(node.get("systems_beat", {}).get("verb", ""))
	if str(node.get("survival_kind", "")) != "forage" and systems_verb != "forage":
		return {}
	# QA observes the runtime transaction; it must never manufacture the reward it
	# is supposed to verify. A missing held lysate makes Scarcity approval fail and
	# points back to the node/runtime contract instead of masking the defect.
	var report := {
		"node_id": node_id,
		"character": "",
		"item_id": "",
		"item_type": "lysate",
		"spawned": false,
		"picked_up": false,
		"endocytosis_started": false,
		"endocytosis_completed": false,
		"missing_runtime_reward": true,
	}
	_record_check(
		result,
		"%s_physical_resource_%s" % [phase, node_id],
		false,
		"Forage node %s completed without producing a real carried lysate item" % node_id
	)
	_record_animation_snapshot(result, preview_instance, phase, "Missing physical reward at %s" % node_id, {
		"event_type": "resource_missing",
		"node_id": node_id,
		"item_type": "lysate",
	})
	return report


func _held_generated_resource(preview_instance: Node, node_id: String) -> Dictionary:
	if not preview_instance.has_method("headless_get_state") or not preview_instance.has_method("get_preview_item_state"):
		return {}
	var state: Dictionary = preview_instance.call("headless_get_state")
	var inventory: Dictionary = state.get("inventory", {})
	for char_id in PARTY_IDS:
		var char_inventory: Dictionary = inventory.get(char_id, {})
		for item_id_v in char_inventory.get("hands", []):
			var item_id := str(item_id_v)
			if item_id == "":
				continue
			var item: Dictionary = preview_instance.call("get_preview_item_state", item_id)
			var properties: Dictionary = item.get("properties", {})
			if str(properties.get("generated_node_id", "")) == node_id:
				return {
					"node_id": node_id,
					"character": char_id,
					"item_id": item_id,
					"item_type": str(item.get("type", "generated_tool")),
					"spawned": true,
					"picked_up": true,
					"endocytosis_started": false,
					"endocytosis_completed": false,
				}
	return {}

func _route_suggests_running(route: Dictionary) -> bool:
	var kind := _route_kind(route)
	return kind == "risky" or int(route.get("risk", 0)) > 1 or int(route.get("pressure", 0)) > 1

func _node_suggests_running(node: Dictionary) -> bool:
	var role := str(node.get("role", ""))
	return role in ["pressure", "route_pressure", "danger"] or int(node.get("pressure", 0)) > 1

func _json_safe(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Vector3:
		return _vec3_array(value)
	if value is Vector2:
		var vec2 := value as Vector2
		return [vec2.x, vec2.y]
	if value is Color:
		var color := value as Color
		return [color.r, color.g, color.b, color.a]
	if value is Dictionary:
		var result := {}
		var source := value as Dictionary
		for key in source.keys():
			result[str(key)] = _json_safe(source[key])
		return result
	if value is Array:
		var result := []
		for item in value as Array:
			result.append(_json_safe(item))
		return result
	if value is String or value is bool or value is int or value is float:
		return value
	return str(value)

func _node_event_payload(spec: Dictionary, node_id: String, preview_instance: Node) -> Dictionary:
	var node := _find_node(spec, node_id)
	var state: Dictionary = preview_instance.call("headless_get_state") if preview_instance.has_method("headless_get_state") else {}
	var chunk: Dictionary = state.get("chunk", {})
	return {
		"node_id": node_id,
		"title": str(node.get("title", node_id)),
		"role": str(node.get("role", "")),
		"position": _vec3_array(_node_position(spec, node_id)),
		"archetype_id": str(node.get("archetype_id", "")),
		"archetype_name": str(node.get("archetype_name", "")),
		"variant": str(node.get("variant", "")),
		"walk_element": str(node.get("walk_element", "")),
		"walk_ref": str(node.get("walk_ref", "")),
		"flora": node.get("flora", []).duplicate(true) if node.get("flora", []) is Array else [],
		"enemies": node.get("enemies", []).duplicate(true) if node.get("enemies", []) is Array else [],
		"structures": node.get("structures", []).duplicate(true) if node.get("structures", []) is Array else [],
		"resource": bool(node.get("resource", false)),
		"shortcut": bool(node.get("shortcut", false)),
		"pressure": int(node.get("pressure", 0)),
		"route_phase": str(chunk.get("route_phase", "")),
		"last_outcome": str(chunk.get("last_outcome", "")),
		"resources_collected": int(chunk.get("generation", {}).get("resources_collected", 0)),
		"shortcut_unlocked": bool(chunk.get("shortcut_unlocked", false)),
		"shelter_rested": bool(chunk.get("shelter_rested", false)),
	}

func _node_position(spec: Dictionary, node_id: String) -> Vector3:
	var anchors: Dictionary = spec.get("anchors", {})
	if anchors.has(node_id):
		return _vec3(anchors[node_id], Vector3.ZERO)
	for node in spec.get("nodes", []):
		if node is Dictionary and str((node as Dictionary).get("id", "")) == node_id:
			return _vec3((node as Dictionary).get("position", Vector3.ZERO), Vector3.ZERO)
	return Vector3.ZERO


func _node_approach_position(spec: Dictionary, node_id: String) -> Vector3:
	var node := _find_node(spec, node_id)
	return _vec3(
		node.get("approach_position", []), _node_position(spec, node_id)
	)


func _find_route_id(spec: Dictionary, from_id: String, to_id: String, allowed_kinds: Array) -> String:
	for route in spec.get("routes", []):
		if not (route is Dictionary):
			continue
		var route_def := route as Dictionary
		if str(route_def.get("from", "")) != from_id or str(route_def.get("to", "")) != to_id:
			continue
		var kind := _route_kind(route_def)
		if allowed_kinds.is_empty() or allowed_kinds.has(kind):
			return str(route_def.get("id", ""))
	return ""

func _find_first_route(spec: Dictionary, allowed_kinds: Array) -> Dictionary:
	for route in spec.get("routes", []):
		if route is Dictionary and allowed_kinds.has(_route_kind(route as Dictionary)):
			return (route as Dictionary).duplicate(true)
	return {}

func _find_route(spec: Dictionary, route_id: String) -> Dictionary:
	for route in spec.get("routes", []):
		if route is Dictionary and str((route as Dictionary).get("id", "")) == route_id:
			return (route as Dictionary).duplicate(true)
	return {}

func _find_node(spec: Dictionary, node_id: String) -> Dictionary:
	for node in spec.get("nodes", []):
		if node is Dictionary and str((node as Dictionary).get("id", "")) == node_id:
			return (node as Dictionary).duplicate(true)
	return {}

func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", ""))
	return kind if kind != "" else str(route.get("risk", "safe"))

func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]))
	return fallback

func _vec3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _serialized_path_uses_multiple_y(path: Variant) -> bool:
	if not (path is Array):
		return false
	var seen: Array[int] = []
	for raw_point in path:
		var point := _vec3(raw_point, Vector3.INF)
		if point == Vector3.INF:
			continue
		var level := int(roundf(point.y * 100.0))
		if not seen.has(level):
			seen.append(level)
	return seen.size() > 1

func _summarize_preview_state(state: Dictionary) -> Dictionary:
	var chunk: Dictionary = state.get("chunk", {}).duplicate(true)
	return {
		"preview_chunk": str(state.get("preview_chunk", "")),
		"preview_party_preset": str(state.get("preview_party_preset", "")),
		"world_slot": state.get("world_slot", {}).duplicate(true),
		"active_character": str(state.get("active_character", "")),
		"character_stats": state.get("character_stats", {}).duplicate(true),
		"abilities": state.get("abilities", {}).duplicate(true),
		"navigation": state.get("navigation", {}).duplicate(true),
		"chunk": chunk,
		"scarcity_experiment": {
			"enabled": str(chunk.get("food_test", "")) == "scarcity",
			"interval_seconds": float(chunk.get("scarcity_drain_interval", 0.0)),
			"drain_per_character": float(chunk.get("scarcity_drain_per_character", 0.0)),
			"floor_per_character": float(chunk.get("scarcity_atp_floor_per_character", 0.0)),
			"hp_drain_at_zero_per_character": float(
				chunk.get("scarcity_zero_atp_hp_drain_per_character", 0.0)
			),
			"started": bool(chunk.get("scarcity_clock_started", false)),
			"ticks": int(chunk.get("scarcity_drain_ticks", 0)),
			"atp_drained": float(chunk.get("scarcity_atp_drained", 0.0)),
			"hp_drained": float(chunk.get("scarcity_hp_drained", 0.0)),
			"hp_absorbed": float(chunk.get("scarcity_hp_absorbed", 0.0)),
		},
	}

func _dispose_preview(preview_instance: Node, tree: SceneTree) -> void:
	if preview_instance != null and is_instance_valid(preview_instance):
		preview_instance.queue_free()
		await tree.process_frame
