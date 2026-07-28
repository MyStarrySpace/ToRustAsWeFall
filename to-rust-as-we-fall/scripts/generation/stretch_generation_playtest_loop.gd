class_name StretchGenerationPlaytestLoop
extends RefCounted

const RuntimeRegistryScript := preload("res://scripts/generation/generated_node_runtime_registry.gd")

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const GameSettingsScript := preload("res://scripts/system/settings.gd")
const GENERATED_STRETCH_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const ANIMATION_CONTRACT_ID := "playthrough_animation_v1"
const DEFAULT_CAPTURE_STEP := 0.25
const GENERATED_INPUT_COMMAND_PREFIX := "qa_generated_node_command/"
const WORLD_INPUT_COMMAND_PREFIX := "qa_world_interaction/"
const PHYSICAL_INTERACTION_TIMEOUT := 24.0
const MAX_PLAYTEST_ADVANCE_SECONDS := 120.0
const PARTY_IDS := ["aster", "peris", "endo"]
const PARTY_OFFSETS := {
	"aster": Vector3(0.0, 0.0, 0.0),
	"peris": Vector3(-1.4, 0.0, 1.1),
	"endo": Vector3(-1.4, 0.0, -1.1),
}
const CHARACTER_SPEEDS := {
	"aster": 3.2,
	"peris": 3.0,
	"endo": 2.8,
}

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
	_exercise_abilities(result, preview_instance)

	if preview_instance.has_method("headless_call_chunk"):
		preview_instance.call("headless_call_chunk", "reset_preview_state", [])
	_validate_progression_gate(result, preview_instance, spec)
	if preview_instance.has_method("headless_advance"):
		_advance_preview_with_animation(result, preview_instance, 0.5, "preview_boot", "Playthrough settle", {
			"event_type": "playthrough_settle",
		})

	var golden_report := _play_golden_path(preview_instance, spec, result, options)
	result["playthroughs"]["golden_path"] = golden_report
	_merge_playthrough_events(result, golden_report)
	_record_check(result, "golden_path_moves_party", int(golden_report.get("movement_commands", 0)) > 0, "Golden path drives preview movement")
	_record_check(result, "golden_path_uses_routes", int(golden_report.get("route_choices", 0)) >= maxi(0, (golden_report.get("visited_nodes", []) as Array).size() - 1), "Golden path uses the route graph")
	_record_check(result, "golden_path_uses_multilevel_navigation", bool(golden_report.get("used_multi_y_path", false)), "Golden path movement uses multi-level navigation waypoints")
	_record_check(
		result,
		"golden_path_uses_ordinary_interactions",
		int(golden_report.get("physical_interactions", 0)) > 0,
		"Golden approval never entered the ordinary input interaction coordinator"
	)
	_record_check(
		result,
		"golden_path_physical_actions_complete",
		(golden_report.get("interaction_failures", []) as Array).is_empty()
			and (golden_report.get("solution_action_failures", []) as Array).is_empty(),
		"Golden approval encountered an unreachable, rejected, or incomplete physical action"
	)
	_record_check(result, "golden_path_reaches_shelter", bool(golden_report.get("shelter_rested", false)), "Golden path reaches and rests at the exit shelter")
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
	var risky_report := _play_risky_recovery(preview_instance, spec, result, options)
	result["playthroughs"]["risky_recovery"] = risky_report
	_merge_playthrough_events(result, risky_report)
	_record_check(result, "risky_recovery_playable", bool(risky_report.get("recovered", false)), "Risky route recovery remains playable")
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

	var shadow_report := _play_shadow_path(preview_instance, spec, result, options)
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


func _validate_progression_gate(result: Dictionary, preview_instance: Node, spec: Dictionary) -> void:
	var golden_path: Array = spec.get("headless", {}).get("golden_path", [])
	if golden_path.size() < 3 or not preview_instance.has_method("headless_call_chunk"):
		return
	var attempted: Dictionary = _approval_interact_generated_node(
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
	# A valid level has at least one playable floor. Verticality is now tier-gated (teaching/standard are FLAT),
	# so this no longer REQUIRES multiple elevations — the multi-floor feature is covered by --test-grid-levels and
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

func _exercise_abilities(result: Dictionary, preview_instance: Node) -> void:
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

func _play_golden_path(preview_instance: Node, spec: Dictionary, result := {}, options := {}) -> Dictionary:
	var report := {
		"path_id": "golden_path",
		"visited_nodes": [],
		"route_ids": [],
		"route_choices": 0,
		"movement_commands": 0,
		"max_path_points": 0,
		"used_multi_y_path": false,
		"route_gaps": [],
		"physical_interactions": 0,
		"interaction_failures": [],
		"solution_action_failures": [],
		"shelter_rested": false,
		"first_shelter_beat_fired": false,
		"events": [],
	}
	if not preview_instance.has_method("headless_call_chunk"):
		return report
	if bool(options.get("reset_before_play", true)):
		preview_instance.call("headless_call_chunk", "reset_preview_state", [])
	var start_state: Dictionary = preview_instance.call("headless_get_state")
	report["started_at"] = float(start_state.get("scheduler_tick", 0.0))
	_append_report_event(report, "golden_path", "path_started", "Golden path reset and started", {
		"path_id": "golden_path",
	})
	_record_animation_snapshot(result, preview_instance, "golden_path", "Golden path reset", {
		"event_type": "path_started",
		"path_id": "golden_path",
	})
	var path: Array = spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	var consumed_solution_actions := {}
	for i in range(path.size()):
		var node_id := str(path[i])
		var abort_after_node := false
		var action_report := _approval_apply_solution_actions_before_node(
			preview_instance,
			spec,
			node_id,
			consumed_solution_actions,
			result,
			"golden_path"
		)
		report["movement_commands"] = int(report.get("movement_commands", 0)) \
			+ int(action_report.get("movement_commands", 0))
		(report["solution_action_failures"] as Array).append_array(
			action_report.get("failures", [])
		)
		if bool(options.get("fail_fast", false)) \
				and not (action_report.get("failures", []) as Array).is_empty():
			report["abort_reason"] = "solution_action_failed:%s" % node_id
			break
		var running_for_move := _node_suggests_running(_find_node(spec, node_id))
		if i > 0:
			var from_id := str(path[i - 1])
			var route_id := _find_route_id(spec, from_id, node_id, ["safe", "shortcut"])
			if route_id == "":
				(report["route_gaps"] as Array).append("%s>%s" % [from_id, node_id])
			else:
				var route_def := _find_route(spec, route_id)
				running_for_move = running_for_move or _route_suggests_running(route_def)
				(report["route_ids"] as Array).append(route_id)
				report["route_choices"] = int(report.get("route_choices", 0)) + 1
				_append_report_event(report, "golden_path", "route_chosen", "Chose route %s" % route_id, {
					"route": route_def,
				})
				_record_animation_snapshot(result, preview_instance, "golden_path", "Chose route %s" % route_id, {
					"event_type": "route_chosen",
					"route_id": route_id,
					"route": route_def,
					"running": running_for_move,
				})
		var move_report := _move_party_to_node_report(preview_instance, spec, node_id, result, options, running_for_move, "golden_path")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(move_report.get("commands", 0))
		report["max_path_points"] = maxi(int(report.get("max_path_points", 0)), int(move_report.get("max_path_points", 0)))
		report["used_multi_y_path"] = bool(report.get("used_multi_y_path", false)) or bool(move_report.get("used_multi_y_path", false))
		_append_report_event(report, "golden_path", "party_moved", "Party moved to %s" % node_id, move_report)
		var current_node := _find_node(spec, node_id)
		var runtime_handler := RuntimeRegistryScript.handler_for_node(current_node, str(spec.get("id", "")))
		_capture_node_commit(result, preview_instance, current_node, "golden_path")
		var interaction_completed := runtime_handler == ""
		if runtime_handler != "":
			var interaction := _approval_interact_generated_node(
				preview_instance, spec, node_id, result, "golden_path"
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
				abort_after_node = bool(options.get("fail_fast", false))
		var node_payload := _node_event_payload(spec, node_id, preview_instance)
		var event_type := "layout_traversed"
		var event_label := "Traversed %s" % node_id
		if runtime_handler != "":
			event_type = "node_activated" \
				if interaction_completed else "node_interaction_failed"
			event_label = ("Activated %s" if interaction_completed \
				else "Failed to activate %s") % node_id
		_append_report_event(report, "golden_path", event_type, event_label, node_payload)
		_record_animation_snapshot(result, preview_instance, "golden_path", event_label, {
			"event_type": event_type,
			"node_id": node_id,
			"node": node_payload,
		})
		var resource_report := (
			_capture_resource_beat(result, preview_instance, spec, node_id)
			if interaction_completed else {}
		)
		if not resource_report.is_empty():
			var resource_event_type := "resource_handled"
			if bool(resource_report.get("retained_in_hand", false)):
				resource_event_type = "resource_secured"
			elif bool(resource_report.get("endocytosis_completed", false)):
				resource_event_type = "resource_endocytosed"
			_append_report_event(report, "golden_path", resource_event_type, "Resource handled at %s" % node_id, resource_report)
		(report["visited_nodes"] as Array).append(node_id)
		if abort_after_node:
			report["abort_reason"] = "node_interaction_failed:%s" % node_id
			break
	var state: Dictionary = preview_instance.call("headless_get_state")
	report["ended_at"] = float(state.get("scheduler_tick", 0.0))
	report["duration"] = maxf(0.0, float(report["ended_at"]) - float(report["started_at"]))
	var chunk: Dictionary = state.get("chunk", {})
	report["scarcity_drain_ticks"] = int(chunk.get("scarcity_drain_ticks", 0))
	report["scarcity_atp_drained"] = float(chunk.get("scarcity_atp_drained", 0.0))
	report["scarcity_drain_per_character"] = float(
		chunk.get("scarcity_drain_per_character", 0.0)
	)
	report["scarcity_atp_floor_per_character"] = float(
		chunk.get("scarcity_atp_floor_per_character", 0.0)
	)
	report["shelter_rested"] = bool(chunk.get("shelter_rested", false))
	report["first_shelter_beat_fired"] = bool(chunk.get("first_shelter_beat_fired", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["final_outcome"] = str(chunk.get("last_outcome", ""))
	report["character_stats"] = state.get("character_stats", {}).duplicate(true)
	report["shortcut_unlocked"] = bool(chunk.get("shortcut_unlocked", false))
	report["climbvine_states"] = chunk.get("climbvine_states", []).duplicate(true)
	report["route_risk_field"] = chunk.get("route_risk_field", {}).duplicate(true)
	report["solution_path"] = chunk.get("solution_path", [])
	report["resources_collected"] = int(chunk.get("generation", {}).get("resources_collected", 0))
	report["physical_food_spawned_count"] = int(
		chunk.get("physical_food_spawned_count", 0)
	)
	report["pressure_taken"] = float(chunk.get("pressure_taken", 0.0))
	report["produced_chain_states"] = chunk.get("produced_chain_states", {})
	report["delivered_resource_nodes"] = chunk.get("delivered_resource_nodes", [])
	if bool(report.get("shelter_rested", false)):
		_append_report_event(report, "golden_path", "shelter_rested", "Exit shelter reached and rested", {
			"route_phase": str(chunk.get("route_phase", "")),
			"last_outcome": str(chunk.get("last_outcome", "")),
			"first_shelter_beat_fired": bool(chunk.get("first_shelter_beat_fired", false)),
		})
		_record_animation_snapshot(result, preview_instance, "golden_path", "Golden path rested at shelter", {
			"event_type": "shelter_rested",
			"node_id": "exit_shelter",
		})
	return report

## The Aster+Peris shadow run over the same node spine. It walks the golden node
## order but with the shadow loadout active, so each puzzle node falls through to its
## shadow approach — a genuinely different, recorded solution path.
func _play_shadow_path(preview_instance: Node, spec: Dictionary, result := {}, options := {}) -> Dictionary:
	var report := {
		"path_id": "shadow_path",
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
		var action_report := _approval_apply_solution_actions_before_node(
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
		var move_report := _move_party_to_node_report(preview_instance, spec, node_id, result, options, running_for_move, "shadow_path")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(move_report.get("commands", 0))
		report["used_multi_y_path"] = bool(report.get("used_multi_y_path", false)) or bool(move_report.get("used_multi_y_path", false))
		var current_node := _find_node(spec, node_id)
		var runtime_handler := RuntimeRegistryScript.handler_for_node(current_node, str(spec.get("id", "")))
		_capture_node_commit(result, preview_instance, current_node, "shadow_path")
		var interaction_completed := runtime_handler == ""
		if runtime_handler != "":
			var interaction := _approval_interact_generated_node(
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

func _play_risky_recovery(preview_instance: Node, spec: Dictionary, result := {}, options := {}) -> Dictionary:
	var report := {
		"path_id": "risky_recovery",
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
		var fallback_report := _follow_golden_segment(
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
	var prefix_report := _follow_golden_segment(
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
	var risky_action_report := _approval_apply_solution_actions_before_node(
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
	var risky_move := _move_party_to_node_report(
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
		var risky_interaction := _approval_interact_generated_node(
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
		var recovery_move := _move_party_to_node_report(preview_instance, spec, recovery_id, result, options, false, "risky_recovery")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(recovery_move.get("commands", 0))
		_append_report_event(report, "risky_recovery", "party_moved", "Party moved to recovery node %s" % recovery_id, recovery_move)
		_capture_node_commit(result, preview_instance, _find_node(spec, recovery_id), "risky_recovery")
		var recovery_node := _find_node(spec, recovery_id)
		if RuntimeRegistryScript.handler_for_node(
			recovery_node, str(spec.get("id", ""))
		) != "":
			var recovery_interaction := _approval_interact_generated_node(
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
		var suffix_report := _follow_golden_segment(
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


## Approval path: resolve the live interaction target, put a real GameState body at its
## authored data-space approach, then enter through the same semantic input command used
## by deterministic player recordings. Completion comes only from the chunk's authoritative
## state. A full hand, blocked route, rejected actor, or missing target therefore remains a
## visible failed playthrough instead of being papered over by activate_generated_node().
func _approval_interact_generated_node(
	preview_instance: Node,
	spec: Dictionary,
	node_id: String,
	result := {},
	phase := "approval"
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
	var actor := _approval_actor_for_target(preview_instance, node, target, approach)
	report["actor"] = actor
	if actor == "":
		report["failure"] = "no_eligible_actor"
		return report
	var formation := _approval_move_party_to_interaction(
		preview_instance, approach, actor, result, phase, node_id
	)
	report["movement_commands"] = int(formation.get("commands", 0))
	report["reached"] = bool(formation.get("actor_reached", false))
	if not bool(report["reached"]):
		report["failure"] = "interaction_approach_unreachable"
		return report
	if preview_instance.has_method("headless_select_character"):
		preview_instance.call("headless_select_character", actor)
	_approval_send_input_action(
		preview_instance, GENERATED_INPUT_COMMAND_PREFIX + node_id
	)
	report["requested"] = true
	report["completed"] = _approval_wait_for_node_completion(
		preview_instance, node_id, result, phase
	)
	var final_state: Dictionary = preview_instance.call("headless_get_state")
	report["last_outcome"] = str(
		final_state.get("chunk", {}).get("last_outcome", "")
	)
	if not bool(report["completed"]):
		report["failure"] = "interaction_did_not_complete"
	return report


## Execute solution-owned world/branch actions as actual detours. The action identifies
## a target, but does not grant its result: a body still walks to the source, requests the
## live interaction, waits on the scheduler, and reads the resulting mechanism state.
func _approval_apply_solution_actions_before_node(
	preview_instance: Node,
	spec: Dictionary,
	node_id: String,
	consumed_action_keys: Dictionary,
	result := {},
	phase := "approval"
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
			var action_report := _approval_perform_solution_action(
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


func _approval_perform_solution_action(
	preview_instance: Node,
	spec: Dictionary,
	action: Dictionary,
	action_group: String,
	result := {},
	phase := "approval"
) -> Dictionary:
	var action_id := _approval_solution_action_target_id(action, action_group)
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
	var target_data := _approval_action_data_position(
		preview_instance, spec, action, target
	)
	if target_data == Vector3.INF:
		report["failure"] = "missing_action_position"
		return report
	var actor := _approval_actor_for_target(preview_instance, {}, target, target_data)
	report["actor"] = actor
	if actor == "":
		report["failure"] = "no_eligible_actor"
		return report
	var movement := _approval_move_actor(
		preview_instance, actor, target_data, result, phase, action_id
	)
	report["movement_commands"] = int(movement.get("commands", 0))
	report["reached"] = bool(movement.get("reached", false))
	if not bool(report["reached"]):
		report["failure"] = "action_source_unreachable"
		return report
	if preview_instance.has_method("headless_select_character"):
		preview_instance.call("headless_select_character", actor)
	_approval_send_input_action(
		preview_instance, WORLD_INPUT_COMMAND_PREFIX + action_id
	)
	report["requested"] = true
	report["completed"] = _approval_wait_for_solution_action(
		preview_instance, action, action_group, result, phase, action_id
	)
	if not bool(report["completed"]):
		report["failure"] = "action_did_not_reach_authoritative_state"
		var state: Dictionary = preview_instance.call("headless_get_state")
		report["last_outcome"] = str(
			state.get("chunk", {}).get("last_outcome", "")
		)
	return report


func _approval_solution_action_target_id(
	action: Dictionary, action_group: String
) -> String:
	if action_group == "branch":
		return str(action.get("id", ""))
	match str(action.get("action", "")):
		"open_sluice", "open_first_sluice":
			return "open_first_sluice"
		"release_bridge", "release_cistern_bridge":
			return "release_cistern_bridge"
		"divert", "divert_current":
			return "divert_current"
		"restore", "restore_main_current":
			return "restore_main_current"
		"catch", "catch_spillway":
			return "catch_spillway"
		"enter_shelter":
			return "enter_shelter"
	return str(action.get("target", ""))


func _approval_action_data_position(
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


func _approval_actor_for_target(
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


func _approval_move_party_to_interaction(
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
		var offset := _approval_formation_offset(char_id, actor)
		var move := _approval_move_actor(
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


func _approval_formation_offset(char_id: String, actor: String) -> Vector3:
	if char_id == actor:
		return Vector3.ZERO
	if char_id == "aster" and actor != "aster":
		return PARTY_OFFSETS.get(actor, Vector3(1.4, 0.0, 0.0)) as Vector3
	return PARTY_OFFSETS.get(char_id, Vector3(1.4, 0.0, 0.0)) as Vector3


func _approval_move_actor(
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
	report["reached"] = _approval_actor_reached(
		preview_instance, actor, target
	)
	return report


func _approval_actor_reached(
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


func _approval_send_input_action(
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


func _approval_wait_for_node_completion(
	preview_instance: Node,
	node_id: String,
	result: Dictionary,
	phase: String
) -> bool:
	var remaining := PHYSICAL_INTERACTION_TIMEOUT
	while remaining >= 0.0:
		if _approval_node_completed(preview_instance, node_id):
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
	return _approval_node_completed(preview_instance, node_id)


func _approval_node_completed(preview_instance: Node, node_id: String) -> bool:
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	if node_id == "exit_shelter":
		return bool(chunk.get("shelter_rested", false))
	return (chunk.get("generation", {}).get("completed_nodes", []) as Array).has(
		node_id
	)


func _approval_wait_for_solution_action(
	preview_instance: Node,
	action: Dictionary,
	action_group: String,
	result: Dictionary,
	phase: String,
	action_id: String
) -> bool:
	var remaining := PHYSICAL_INTERACTION_TIMEOUT
	while remaining >= 0.0:
		if _approval_solution_action_completed(
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
	return _approval_solution_action_completed(
		preview_instance, action, action_group
	)


func _approval_solution_action_completed(
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
		"open_sluice", "open_first_sluice":
			return bool(chunk.get("first_sluice_open", false))
		"release_bridge", "release_cistern_bridge":
			return bool(chunk.get("cistern_bridge_installed", false))
		"divert", "divert_current":
			return bool(chunk.get("borrowed_current_diverted", false))
		"restore", "restore_main_current":
			return bool(chunk.get("main_current_restored", false))
		"catch", "catch_spillway":
			return bool(chunk.get("hydraulic_spillway_food_collected", false))
		"enter_shelter":
			return bool(chunk.get("shelter_rested", false))
	return false


## Kept only for focused data-layer diagnostics. Approval paths above must never call
## this helper: it bypasses movement, interaction assignment, inventory, and risk contact.
func _diagnostic_direct_activate_generated_node(
	preview_instance: Node, node_id: String
) -> bool:
	return bool(preview_instance.call(
		"headless_call_chunk", "activate_generated_node", [node_id]
	))


func _follow_golden_segment(
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
		var action_report := _approval_apply_solution_actions_before_node(
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
		var move_report := _move_party_to_node_report(
			preview_instance, spec, node_id, result, options, running_for_move, phase
		)
		report["commands"] = int(report.get("commands", 0)) + int(move_report.get("commands", 0))
		var current_node := _find_node(spec, node_id)
		_capture_node_commit(result, preview_instance, current_node, phase)
		if RuntimeRegistryScript.handler_for_node(current_node, str(spec.get("id", ""))) != "":
			var interaction := _approval_interact_generated_node(
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

func _move_party_to_node(preview_instance: Node, spec: Dictionary, node_id: String) -> int:
	return int(_move_party_to_node_report(preview_instance, spec, node_id).get("commands", 0))

func _move_party_to_node_report(preview_instance: Node, spec: Dictionary, node_id: String, result := {}, options := {}, running := false, phase := "movement") -> Dictionary:
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
	if commands > 0:
		_record_animation_snapshot(result, preview_instance, phase, "Arrived at %s" % node_id, {
			"event_type": "party_arrived",
			"node_id": node_id,
			"target": report["target"],
			"running": running,
		})
	return report

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
