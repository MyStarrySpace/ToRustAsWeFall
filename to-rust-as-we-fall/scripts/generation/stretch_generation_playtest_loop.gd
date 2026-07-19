class_name StretchGenerationPlaytestLoop
extends RefCounted

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const GENERATED_STRETCH_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const ANIMATION_CONTRACT_ID := "playthrough_animation_v1"
const DEFAULT_CAPTURE_STEP := 0.25
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
	var preview_config := {}
	var requested_preview_config: Variant = options.get("preview_config", {})
	if requested_preview_config is Dictionary:
		preview_config = (requested_preview_config as Dictionary).duplicate(true)
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
	_record_check(result, "golden_path_reaches_shelter", bool(golden_report.get("shelter_rested", false)), "Golden path reaches and rests at the exit shelter")
	if str(spec.get("composition", {}).get("mode", "")) == "chain_nested_poc":
		var expected_chain_outputs := 0
		var expected_nested_hosts := 0
		var expected_carries := 0
		for node_v in spec.get("nodes", []):
			var node := node_v as Dictionary
			if str(node.get("chain_output_ref", "")) != "":
				expected_chain_outputs += 1
			if not (node.get("nested_archetypes", []) as Array).is_empty():
				expected_nested_hosts += 1
			if bool(node.get("carry_payload", false)):
				expected_carries += 1
		_record_check(result, "chain_outputs_materialize", (golden_report.get("produced_chain_states", {}) as Dictionary).size() == expected_chain_outputs,
			"Golden path did not materialize every typed chain output")
		_record_check(result, "nested_support_changes_state", (golden_report.get("prepared_nested_nodes", {}) as Dictionary).size() == expected_nested_hosts,
			"Nested support remained metadata instead of a prepared runtime state")
		_record_check(result, "carry_payloads_delivered", (golden_report.get("delivered_resource_nodes", []) as Array).size() == expected_carries,
			"A physical carried payload did not reach shelter delivery state")
	if (
		str(preview_config.get("food_test", "")) == "scarcity"
		and str(spec.get("source", {}).get("complexity_tier", "teaching")) != "teaching"
	):
		var food_settings: Dictionary = preview_config.get("food_test_settings", {})
		var drain_interval := float(food_settings.get("drain_interval_seconds", 60.0))
		_record_check(
			result,
			"scarcity_cycle_relevant_on_golden_path",
			(
				float(golden_report.get("duration", 0.0)) >= drain_interval
				and int(golden_report.get("scarcity_drain_ticks", 0)) >= 1
			),
			"Standard-or-later scarcity run reaches shelter before one drain cycle can affect the route"
		)

	var risky_report := _play_risky_recovery(preview_instance, spec, result, options)
	result["playthroughs"]["risky_recovery"] = risky_report
	_merge_playthrough_events(result, risky_report)
	_record_check(result, "risky_recovery_playable", bool(risky_report.get("recovered", false)), "Risky route recovery remains playable")
	if bool(risky_report.get("has_risky_route", false)):
		_record_check(result, "risky_recovery_applies_pressure", float(risky_report.get("damage", 0.0)) > 0.0, "Risky recovery applies pressure before rest")
		if str(spec.get("composition", {}).get("mode", "")) == "chain_nested_poc":
			var risk_reward: Dictionary = risky_report.get("reward", {})
			_record_check(result, "risky_route_grants_durable_food", str(risk_reward.get("item_type", "")) == "lysate" and bool(risk_reward.get("retained_in_hand", false)),
				"Risky route pressure did not grant a durable carried food reward")

	var shadow_report := _play_shadow_path(preview_instance, spec, result, options)
	result["playthroughs"]["shadow_path"] = shadow_report
	_merge_playthrough_events(result, shadow_report)
	var choice_node_count := int(spec.get("headless", {}).get("solution_summary", {}).get("choice_node_count", 0))
	if choice_node_count > 0:
		_record_check(result, "shadow_path_completes", bool(shadow_report.get("shelter_rested", false)), "Aster+Peris shadow path reaches and rests at the exit shelter")
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
	var attempted := bool(
		preview_instance.call("headless_call_chunk", "activate_generated_node", ["exit_shelter"])
	)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	_record_check(
		result,
		"out_of_order_exit_blocked",
		not attempted and not bool(chunk.get("shelter_rested", false)),
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
		_record_check(result, "main_abilities_callable", false, "Preview exposes the 6x2 party-ability action contract")
		return
	var ability_specs := [
		{"char_id": "aster", "ability_id": "aster_focus"},
		{"char_id": "peris", "ability_id": "peris_tune"},
		{"char_id": "endo", "ability_id": "endo_patch"},
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
		var before_atp := float(before_stats.get("atp", -1.0))
		var activated := input_action != "" and bool(preview_instance.call("headless_activate_ability_action", input_action))
		var after: Dictionary = preview_instance.call("headless_get_state")
		var after_stats: Dictionary = after.get("character_stats", {}).get(char_id, {})
		var ability_state: Dictionary = after.get("abilities", {}).get(ability_id, {})
		var spent_atp := float(after_stats.get("atp", before_atp)) < before_atp
		var state_changed := str(ability_state.get("state", "ready")) != "ready"
		var ok := (
			activated
			and spent_atp
			and state_changed
			and int(route.get("party_slot", -1)) >= 0
			and int(route.get("ability_slot", -1)) >= 0
			and str(ability_state.get("input_action", "")) == input_action
		)
		all_abilities_ok = all_abilities_ok and ok
		ability_report[ability_id] = {
			"activated": activated,
			"spent_atp": spent_atp,
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
			"spent_atp": spent_atp,
			"before_atp": before_atp,
			"after_atp": float(after_stats.get("atp", before_atp)),
			"state": str(ability_state.get("state", "")),
		})
		_record_animation_snapshot(result, preview_instance, "preview_boot", "%s activated %s" % [char_id.capitalize(), ability_id], {
			"event_type": "ability_activated",
			"character": char_id,
			"ability_id": ability_id,
			"keybind": str(ability_state.get("keybind", "")),
			"input_action": input_action,
			"activated": activated,
			"spent_atp": spent_atp,
		})
	result["ability_report"] = ability_report
	_record_check(result, "main_abilities_exercised", all_abilities_ok, "Direct 6x2 party-ability actions route to their owners and spend ATP")

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
		"shelter_rested": false,
		"first_shelter_beat_fired": false,
		"events": [],
	}
	if not preview_instance.has_method("headless_call_chunk"):
		return report
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
	for i in range(path.size()):
		var node_id := str(path[i])
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
				preview_instance.call("headless_call_chunk", "choose_generated_route", [route_id, false])
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
		_capture_node_commit(result, preview_instance, _find_node(spec, node_id), "golden_path")
		_activate_node_with_nested_capture(result, preview_instance, node_id, "golden_path")
		var node_payload := _node_event_payload(spec, node_id, preview_instance)
		_append_report_event(report, "golden_path", "node_activated", "Activated %s" % node_id, node_payload)
		_record_animation_snapshot(result, preview_instance, "golden_path", "Activated %s" % node_id, {
			"event_type": "node_activated",
			"node_id": node_id,
			"node": node_payload,
		})
		var resource_report := _capture_resource_beat(result, preview_instance, spec, node_id)
		if not resource_report.is_empty():
			var resource_event_type := "resource_handled"
			if bool(resource_report.get("retained_in_hand", false)):
				resource_event_type = "resource_secured"
			elif bool(resource_report.get("endocytosis_completed", false)):
				resource_event_type = "resource_endocytosed"
			_append_report_event(report, "golden_path", resource_event_type, "Resource handled at %s" % node_id, resource_report)
		(report["visited_nodes"] as Array).append(node_id)
	var state: Dictionary = preview_instance.call("headless_get_state")
	report["ended_at"] = float(state.get("scheduler_tick", 0.0))
	report["duration"] = maxf(0.0, float(report["ended_at"]) - float(report["started_at"]))
	var chunk: Dictionary = state.get("chunk", {})
	report["scarcity_drain_ticks"] = int(chunk.get("scarcity_drain_ticks", 0))
	report["scarcity_atp_drained"] = float(chunk.get("scarcity_atp_drained", 0.0))
	report["shelter_rested"] = bool(chunk.get("shelter_rested", false))
	report["first_shelter_beat_fired"] = bool(chunk.get("first_shelter_beat_fired", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["final_outcome"] = str(chunk.get("last_outcome", ""))
	report["solution_path"] = chunk.get("solution_path", [])
	report["resources_collected"] = int(chunk.get("generation", {}).get("resources_collected", 0))
	report["produced_chain_states"] = chunk.get("produced_chain_states", {})
	report["prepared_nested_nodes"] = chunk.get("prepared_nested_nodes", {})
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
	for i in range(path.size()):
		var node_id := str(path[i])
		var running_for_move := _node_suggests_running(_find_node(spec, node_id))
		if i > 0:
			var route_id := _find_route_id(spec, str(path[i - 1]), node_id, ["safe", "shortcut"])
			if route_id != "":
				var route_def := _find_route(spec, route_id)
				running_for_move = running_for_move or _route_suggests_running(route_def)
				(report["route_ids"] as Array).append(route_id)
				report["route_choices"] = int(report.get("route_choices", 0)) + 1
				preview_instance.call("headless_call_chunk", "choose_generated_route", [route_id, false])
		var move_report := _move_party_to_node_report(preview_instance, spec, node_id, result, options, running_for_move, "shadow_path")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(move_report.get("commands", 0))
		report["used_multi_y_path"] = bool(report.get("used_multi_y_path", false)) or bool(move_report.get("used_multi_y_path", false))
		_capture_node_commit(result, preview_instance, _find_node(spec, node_id), "shadow_path")
		_activate_node_with_nested_capture(result, preview_instance, node_id, "shadow_path")
		var node_payload := _node_event_payload(spec, node_id, preview_instance)
		_append_report_event(report, "shadow_path", "node_activated", "Activated %s (shadow)" % node_id, node_payload)
		_record_animation_snapshot(result, preview_instance, "shadow_path", "Shadow solved %s" % node_id, {
			"event_type": "node_activated",
			"node_id": node_id,
			"node": node_payload,
			"loadout": "shadow",
		})
		_capture_resource_beat(result, preview_instance, spec, node_id, "shadow_path")
		(report["visited_nodes"] as Array).append(node_id)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	report["shelter_rested"] = bool(chunk.get("shelter_rested", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
	report["final_outcome"] = str(chunk.get("last_outcome", ""))
	report["blocked_nodes"] = chunk.get("blocked_nodes", [])
	report["active_party"] = chunk.get("active_party", [])
	report["produced_chain_states"] = chunk.get("produced_chain_states", {})
	report["prepared_nested_nodes"] = chunk.get("prepared_nested_nodes", {})
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
	var risky_route := _find_first_route(spec, ["risky"])
	if risky_route.is_empty():
		report["recovered"] = bool(preview_instance.call("headless_call_chunk", "run_generated_golden_path", []))
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
		preview_instance, spec, main_path, 0, risky_source_index, result, options, "risky_recovery"
	)
	report["movement_commands"] = int(prefix_report.get("commands", 0))
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
	var risky_move := _move_party_to_node_report(preview_instance, spec, str(risky_route.get("to", "exit_shelter")), result, options, true, "risky_recovery")
	report["movement_commands"] = int(report.get("movement_commands", 0)) + int(risky_move.get("commands", 0))
	_append_report_event(report, "risky_recovery", "party_moved", "Party moved through risky route to %s" % str(risky_route.get("to", "exit_shelter")), risky_move)
	preview_instance.call("headless_call_chunk", "choose_generated_route", [str(risky_route.get("id", "")), false])
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
	var risky_destination := str(risky_route.get("to", "exit_shelter"))
	_activate_node_with_nested_capture(result, preview_instance, risky_destination, "risky_recovery")
	_append_report_event(report, "risky_recovery", "node_activated", "Activated risky route destination %s" % str(risky_route.get("to", "exit_shelter")), _node_event_payload(spec, str(risky_route.get("to", "exit_shelter")), preview_instance))
	_record_animation_snapshot(result, preview_instance, "risky_recovery", "Activated risky destination", {
		"event_type": "node_activated",
		"node_id": str(risky_route.get("to", "exit_shelter")),
	})
	var risky_resource := _capture_resource_beat(result, preview_instance, spec, risky_destination, "risky_recovery")
	if not risky_resource.is_empty():
		report["reward"] = risky_resource
	var recovery_id := str(risky_route.get("recovery", ""))
	if recovery_id != "":
		var recovery_move := _move_party_to_node_report(preview_instance, spec, recovery_id, result, options, false, "risky_recovery")
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(recovery_move.get("commands", 0))
		_append_report_event(report, "risky_recovery", "party_moved", "Party moved to recovery node %s" % recovery_id, recovery_move)
		_capture_node_commit(result, preview_instance, _find_node(spec, recovery_id), "risky_recovery")
		_activate_node_with_nested_capture(result, preview_instance, recovery_id, "risky_recovery")
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
			"risky_recovery"
		)
		report["movement_commands"] = int(report.get("movement_commands", 0)) + int(suffix_report.get("commands", 0))
		report["suffix_nodes"] = suffix_report.get("visited_nodes", [])
		_append_report_event(report, "risky_recovery", "suffix_completed", "Rejoined and completed the main route", suffix_report)
	var state: Dictionary = preview_instance.call("headless_get_state")
	var chunk: Dictionary = state.get("chunk", {})
	report["damage"] = float(chunk.get("risky_damage_total", 0.0))
	report["recovered"] = bool(chunk.get("shelter_rested", false))
	report["final_phase"] = str(chunk.get("route_phase", ""))
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


func _activate_node_with_nested_capture(result: Dictionary, preview_instance: Node, node_id: String, phase: String) -> bool:
	var activated := bool(preview_instance.call("headless_call_chunk", "activate_generated_node", [node_id]))
	var state: Dictionary = preview_instance.call("headless_get_state") if preview_instance.has_method("headless_get_state") else {}
	var outcome := str(state.get("chunk", {}).get("last_outcome", ""))
	if not activated and outcome == "nested_prepared:%s" % node_id:
		var prepared_nodes: Dictionary = state.get("chunk", {}).get("prepared_nested_nodes", {})
		var prepared_state := str((prepared_nodes.get(node_id, {}) as Dictionary).get("prepared_state", "nested_dependency_ready"))
		_record_animation_snapshot(result, preview_instance, phase, "Nested support prepared at %s" % node_id, {
			"event_type": "nested_support_prepared",
			"node_id": node_id,
			"prepared_state": prepared_state,
		})
		_advance_preview_with_animation(result, preview_instance, 1.0, phase, "Reading the supported carry", {
			"event_type": "nested_support_read",
			"node_id": node_id,
		})
		activated = bool(preview_instance.call("headless_call_chunk", "activate_generated_node", [node_id]))
	return activated


func _follow_golden_segment(
	preview_instance: Node,
	spec: Dictionary,
	path: Array,
	start_index: int,
	end_index: int,
	result := {},
	options := {},
	phase := "movement"
) -> Dictionary:
	var report := {"commands": 0, "visited_nodes": [], "route_ids": []}
	if path.is_empty() or start_index > end_index:
		return report
	var first := maxi(0, start_index)
	var last := mini(end_index, path.size() - 1)
	for i in range(first, last + 1):
		var node_id := str(path[i])
		var running_for_move := _node_suggests_running(_find_node(spec, node_id))
		if i > 0:
			var route_id := _find_route_id(spec, str(path[i - 1]), node_id, ["safe", "shortcut"])
			if route_id != "":
				var route_def := _find_route(spec, route_id)
				running_for_move = running_for_move or _route_suggests_running(route_def)
				preview_instance.call("headless_call_chunk", "choose_generated_route", [route_id, false])
				(report["route_ids"] as Array).append(route_id)
		var move_report := _move_party_to_node_report(
			preview_instance, spec, node_id, result, options, running_for_move, phase
		)
		report["commands"] = int(report.get("commands", 0)) + int(move_report.get("commands", 0))
		_capture_node_commit(result, preview_instance, _find_node(spec, node_id), phase)
		_activate_node_with_nested_capture(result, preview_instance, node_id, phase)
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
	for char_id_v in active_party:
		var char_id := str(char_id_v)
		var target_pos := target + (PARTY_OFFSETS.get(char_id, Vector3.ZERO) as Vector3)
		var current_pos := _vec3(current_positions.get(char_id, target_pos), target_pos)
		var distance := current_pos.distance_to(target_pos)
		var commanded := bool(preview_instance.call("headless_move_character", char_id, target_pos, running))
		var movement_info: Dictionary = preview_instance.call("headless_get_character_movement_info", char_id) if preview_instance.has_method("headless_get_character_movement_info") else {}
		var movement_duration := float(movement_info.get("duration", distance / float(CHARACTER_SPEEDS.get(char_id, 3.0)))) + 0.15
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
	if not preview_instance.has_method("headless_advance") or duration <= 0.0:
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
		"resources_collected": int(generation.get("resources_collected", 0)),
		"active_loadout": str(source.get("active_loadout", generation.get("active_loadout", "spotlight"))),
		"active_party": source.get("active_party", generation.get("active_party", PARTY_IDS)),
		"completed_nodes": generation.get("completed_nodes", []),
		"activated_routes": generation.get("activated_routes", []),
		"produced_chain_states": source.get("produced_chain_states", generation.get("produced_chain_states", {})),
		"prepared_nested_nodes": source.get("prepared_nested_nodes", generation.get("prepared_nested_nodes", {})),
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
	var node_id := str(node.get("id", ""))
	var role := str(node.get("role", ""))
	if node_id == "entry" or role == "boundary":
		return
	var action := str(node.get("action_verb", "INTERVENE"))
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
	if not preview_instance.has_method("spawn_preview_item") or not preview_instance.has_method("pick_up_preview_item"):
		return {}
	var state: Dictionary = preview_instance.call("headless_get_state") if preview_instance.has_method("headless_get_state") else {}
	var endo_pos := _vec3(state.get("characters", {}).get("endo", _node_position(spec, node_id)), _node_position(spec, node_id))
	if preview_instance.has_method("headless_select_character"):
		preview_instance.call("headless_select_character", "endo")
	var item_id := str(preview_instance.call("spawn_preview_item", "lysate", endo_pos, {
		"display_name": "Foraged Lysate",
		"endocytosis_duration": 0.8,
		"atp_restore": 1.0,
	}))
	var report := {
		"node_id": node_id,
		"character": "endo",
		"item_id": item_id,
		"item_type": "lysate",
		"spawned": item_id != "",
		"picked_up": false,
		"endocytosis_started": false,
		"endocytosis_completed": false,
	}
	_record_animation_snapshot(result, preview_instance, phase, "Resource spawned at %s" % node_id, {
		"event_type": "resource_spawned",
		"node_id": node_id,
		"item_id": item_id,
		"item_type": "lysate",
	})
	if item_id == "":
		return report
	var picked := bool(preview_instance.call("pick_up_preview_item", "endo", item_id))
	report["picked_up"] = picked
	_record_animation_snapshot(result, preview_instance, phase, "Endo picked up %s" % item_id, {
		"event_type": "resource_picked_up",
		"node_id": node_id,
		"item_id": item_id,
		"picked_up": picked,
	})
	if not picked or not preview_instance.has_method("endocytose_preview_item"):
		return report
	var started := bool(preview_instance.call("endocytose_preview_item", "endo", item_id))
	report["endocytosis_started"] = started
	_record_animation_snapshot(result, preview_instance, phase, "Endo started endocytosis", {
		"event_type": "endocytosis_started",
		"node_id": node_id,
		"item_id": item_id,
		"started": started,
	})
	if started:
		_advance_preview_with_animation(result, preview_instance, 0.95, phase, "Endocytosis effect", {
			"event_type": "endocytosis_effect",
			"node_id": node_id,
			"item_id": item_id,
			"character": "endo",
		})
		var after: Dictionary = preview_instance.call("headless_get_state") if preview_instance.has_method("headless_get_state") else {}
		report["endocytosis_completed"] = not bool(after.get("inventory", {}).get("endocytosing", {}).get("endo", false))
		_record_animation_snapshot(result, preview_instance, phase, "Endocytosis completed", {
			"event_type": "endocytosis_completed",
			"node_id": node_id,
			"item_id": item_id,
			"completed": bool(report.get("endocytosis_completed", false)),
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
	return {
		"preview_chunk": str(state.get("preview_chunk", "")),
		"preview_party_preset": str(state.get("preview_party_preset", "")),
		"world_slot": state.get("world_slot", {}).duplicate(true),
		"active_character": str(state.get("active_character", "")),
		"character_stats": state.get("character_stats", {}).duplicate(true),
		"abilities": state.get("abilities", {}).duplicate(true),
		"navigation": state.get("navigation", {}).duplicate(true),
		"chunk": state.get("chunk", {}).duplicate(true),
	}

func _dispose_preview(preview_instance: Node, tree: SceneTree) -> void:
	if preview_instance != null and is_instance_valid(preview_instance):
		preview_instance.queue_free()
		await tree.process_frame
