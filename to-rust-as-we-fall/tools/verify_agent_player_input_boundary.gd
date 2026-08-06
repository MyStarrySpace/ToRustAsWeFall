extends SceneTree

## Static approval-evidence boundary for autonomous player harnesses. Direct commands are legal in
## fixture-only mechanism tests, but never when reachable from the evidence roots below.
## Run: Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_agent_player_input_boundary.gd
## Bounded watchdog fixture: append `-- --verify-player-discovery-watchdog-contract`.

const MATERIAL_SCAN_PREVIEW_SCENE := preload(
	"res://scenes/fragments/fragment_preview.tscn")
const MATERIAL_SCAN_PREVIEW_SCRIPT := preload(
	"res://scripts/fragments/fragment_preview_sequence.gd")
const WATCHDOG_LOOP_SCRIPT := preload(
	"res://scripts/generation/stretch_generation_playtest_loop.gd")
const WATCHDOG_INPUT_DRIVER_SCRIPT := preload(
	"res://tools/agent_player_input_driver.gd")
const GENERATED_INTERACTION_TRUTH_SCRIPT := preload(
	"res://tools/verify_generated_interaction_truth.gd")
const WATCHDOG_TRACE_SCRIPT := preload(
	"res://scripts/testing/persona_decision_trace.gd")
const MOVEMENT_CONTINUITY_TRACKER_SCRIPT := preload(
	"res://scripts/testing/movement_continuity_tracker.gd")

const AUDITS := [
	{
		"path": "res://scripts/test_runner_cli.gd",
		"label": "Windowed persona evidence wiring",
		"roots": [
			"_test_persona_probe",
			"_persona_windowed_basin_run",
			"_test_basin_player_journey",
		],
		"input_required": [
			"_test_persona_probe",
			"_persona_windowed_basin_run",
			"_test_basin_player_journey",
		],
		"rally_required": ["_test_basin_player_journey"],
		"fixture_only": ["_instantiate_preview_chunk_and_wait"],
		"baseline_token": "controller.setup(",
		"diagnostic_only": [
			"_run_legacy_ai_playthrough_diagnostic",
			"_run_legacy_persona_seed_diagnostic",
			"_run_legacy_persona_fragment_diagnostic",
			"_legacy_persona_diagnostic_run",
		],
		"required_by_function": {
			"_test_basin_player_journey": {
				"reachable": false,
				"token_groups": [
					["PlayerObservationControllerScript.new("],
					["_basin_journey_capture_observation("],
					["_basin_journey_choose_ladder_affordance("],
					["rally_screen("],
					["_basin_journey_choose_interaction_affordance("],
					["interact_selected_screen("],
					["BASIN RISING"],
					["get_tree().create_timer("],
				],
			},
			"_assert_persona_four_portrait_rally_fixture": {
				"reachable": false,
				"token_groups": [
					["aster", "peris", "endo", "marco"],
					["_presented_party_ids"],
					["select_party("],
					["unbound_members"],
					["_annotate_group_rally_effect"],
					["atomic_group"],
					["intended_members"],
					["member_results"],
				],
			},
			"_test_interactable_highlight": {
				"reachable": false,
				"token_groups": [
					["ShaderMaterial.new("],
					["ALPHA = 0.0"],
					["get_player_observation_render_nodes"],
					["is_empty("],
					["ImageTexture.create_from_image("],
					["TRANSPARENCY_ALPHA"],
					["albedo_texture"],
				],
			},
			"_test_player_observation_visibility": {
				"reachable": false,
				"token_groups": [
					["ShaderMaterial.new("],
					["ALPHA = 0.0"],
					["get_player_observation_screen_candidates"],
					["snapshot(", "call(\"snapshot\"", "call('snapshot'"],
					["transparent_shader_candidate_pixels"],
					["ImageTexture.create_from_image("],
					["TRANSPARENCY_ALPHA"],
					["albedo_texture"],
					["play_expiring_rejection(0.42"],
					["next_scan_delay_msec = 550"],
					["an expired result is not re-attested"],
					["an off-screen source cannot self-attest"],
					["a hidden source mesh cannot self-attest"],
				],
			},
		},
		"forbidden_by_function": {
			"_test_basin_player_journey": {
				"headless_advance": "the required Windowed journey advances a hidden scheduler instead of waiting for rendered frames",
				"_contract_click_world(": "the required Windowed journey projects a private world target instead of clicking an observed affordance",
				".rally(": "the required Windowed journey supplies a world-addressed Rally target instead of an observed screen point",
				"call(\"rally\"": "the required Windowed journey dynamically dispatches world-addressed Rally",
				"callv(\"rally\"": "the required Windowed journey dynamically dispatches world-addressed Rally",
				"\"headless_advance\"": "the required Windowed journey aliases hidden scheduler advancement",
				"\"rally\"": "the required Windowed journey aliases world-addressed Rally",
				"console.global_position": "the console action is addressed from a private world transform",
				"shelter.global_position": "the shelter action is addressed from a private world transform",
			},
		},
		"forbidden_constructed_by_function": {
			"_test_basin_player_journey": {
				"headlessadvance": "the required Windowed journey constructs a hidden scheduler-advance method name",
				"rally": "the required Windowed journey constructs a world-addressed Rally method name",
			},
		},
	},
	{
		"path": "res://scripts/test_runner_cli.gd",
		"label": "Basin journey observation-only choice policy",
		"roots": [
			"_basin_journey_choose_ladder_affordance",
			"_basin_journey_choose_interaction_affordance",
			"_basin_journey_observation_has_text",
		],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"presentation_only": true,
	},
	{
		"path": "res://scripts/testing/persona_player_controller.gd",
		"label": "presentation-only persona decision executor",
		"roots": ["play", "_on_validation_external_traversal_started"],
		"input_required": ["play", "_execute_choice"],
		"rally_required": ["play", "_execute_choice"],
		"fixture_only": [],
		"presentation_only": true,
		"receipt_only": [
			"_validation_set_navigation_edge_receipt_connection",
			"_on_validation_external_traversal_started",
		],
	},
	{
		"path": "res://scripts/testing/player_observation_controller.gd",
		"label": "player-observation screen boundary",
		"roots": ["snapshot"],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"presentation_only": true,
		# Policy-visible interaction targets may be verified by the production
		# pointer seam, but they must first come from rendered screen evidence or
		# an actually delivered hover. Enumerating hidden collision nodes and then
		# projecting their authored transforms lets an invisible collider become a
		# solve oracle while still looking like a screen token downstream.
		"forbidden_by_function": {
			"_affordance_snapshot": {
				"_scene_nodes(": "interaction discovery enumerates hidden scene nodes",
				"get_player_observation_render_nodes": "the observer pulls render nodes and projects private transforms instead of consuming the production presenter's screen API",
				"_presentation_surface_screen_points(": "the observer projects presenter transforms instead of consuming production-owned screen candidates",
			},
			"_ground_sample_points": {
				"_scene_nodes(": "ground discovery is biased by hidden scene-node enumeration",
				"global_position": "ground probes are biased by authored world transforms",
			},
			"_presented_text_cues": {
				"_scene_nodes(": "policy text cues enumerate scene nodes instead of rendered text evidence",
				"global_position": "policy text cues trust an authored transform without framebuffer visibility",
			},
			"_party_body_cues": {
				"_host.get(\"_characters\"": "party-body presentation enumerates the private authoritative roster",
				"global_position": "party-body pixels are projected from private live transforms instead of a rendered presenter",
			},
			"_hud_snapshot": {
				"_portrait_label(": "the observer reopens the HUD's private portrait-node registry instead of consuming its public rendered label",
			},
		},
		# The observer may consume opaque screen points from an explicitly registered
		# production presenter, but it must still prove that the point resolves to the
		# same source through the shipped pointer ray. A transient result additionally
		# needs the exact result-pulse screen surface; rediscovering only the base object
		# is not evidence that the green/red pulse itself was presented.
		"required_by_function": {
			"_affordance_snapshot": {
				"reachable": true,
				"token_groups": [
					["get_nodes_in_group("],
					["player_observation_presenters", "PLAYER_OBSERVATION_PRESENTER_GROUP"],
					["get_player_observation_screen_candidates"],
					["_command_collider_at("],
					["_presentation_owner_matches_hit("],
					["_render_surface_point_visible(", "_presentation_point_visible(", "_render_point_visible("],
					["get_player_pointer_affordance"],
				],
			},
			"_interaction_presentation_snapshot": {
				"reachable": true,
				"token_groups": [
					["WeakRef"],
					["get_player_interaction_presentation"],
					["_interaction_result_screen("],
				],
			},
			"_interaction_result_cues": {
				"reachable": true,
				"token_groups": [
					["source_token"],
					["presentation_serial"],
					["screen_v"],
					["visible"],
				],
			},
			"_interaction_result_screen": {
				"reachable": true,
				"token_groups": [
					["get_player_interaction_presentation_screen_candidates"],
					["_affordance_tokens.get("],
					["_affordance_presentation_sources.get("],
					["WeakRef"],
					["_framebuffer_result_tint_candidate("],
					["_ui_blocks_point("],
				],
			},
			"_framebuffer_result_tint_candidate": {
				"reachable": true,
				"token_groups": [
					["viewport.get_texture("],
					["get_image("],
					["get_pixel", "get_pixelv"],
					["success"],
					["rejected"],
				],
			},
			"_party_body_cues": {
				"reachable": true,
				"token_groups": [
					["get_nodes_in_group("],
					["player_observation_party_presenters", "PLAYER_BODY_PRESENTER_GROUP"],
					["get_player_observation_screen_candidates"],
					["_body_point_visible("],
				],
			},
			"_hud_snapshot": {
				"reachable": false,
				"token_groups": [
					["shown.get(\"label\"", "shown.get('label'"],
				],
			},
		},
		"guards_before_emit": [
			{
				"function": "_affordance_snapshot",
				"emit_tokens": ["\"kind\": \"interact\""],
				"guard_token_groups": [
					["get_player_observation_screen_candidates"],
					["_command_collider_at("],
					["_presentation_owner_matches_hit("],
					["_render_surface_point_visible(", "_presentation_point_visible(", "_render_point_visible("],
					["get_player_pointer_affordance"],
				],
			},
			{
				"function": "_interaction_presentation_snapshot",
				"emit_tokens": ["presentations.append({"],
				"guard_token_groups": [
					["get_player_interaction_presentation"],
					["presentation.get(\"visible\""],
					["_interaction_result_screen("],
				],
			},
			{
				"function": "_interaction_result_cues",
				"emit_tokens": ["\"kind\": \"interaction_result\""],
				"guard_token_groups": [
					["source_token == \"\""],
					["presentation.get(\"visible\""],
					["screen_v is Array"],
				],
			},
		],
		"ordered_after_anchor": [
			{
				"function": "snapshot",
				"anchor_tokens": ["_capture_serial += 1"],
				"ordered_token_groups": [
					["_movement_presentation_snapshot("],
					["_interaction_presentation_snapshot("],
					["_ground_snapshot("],
					["_affordance_snapshot("],
					["_cue_snapshot("],
				],
			},
		],
	},
	{
		"path": "res://scripts/game/objects/outline_surface_target.gd",
		"label": "production player-observation presenter",
		"roots": [
			"get_player_observation_screen_candidates",
			"get_player_interaction_presentation_screen_candidates",
		],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"required_by_function": {
			"get_player_observation_screen_candidates": {
				"reachable": true,
				"token_groups": [
					["get_player_observation_render_nodes"],
					["_screen_candidates_for_render_nodes("],
				],
			},
			"get_player_interaction_presentation_screen_candidates": {
				"reachable": true,
				"token_groups": [
					["get_player_interaction_presentation_render_nodes"],
					["_screen_candidates_for_render_nodes("],
				],
			},
			"_refresh_player_observation_presenter_registration": {
				"reachable": true,
				"token_groups": [
					["PLAYER_OBSERVATION_PRESENTER_GROUP", "player_observation_presenters"],
					["add_to_group("],
					["remove_from_group("],
					["interaction_requested"],
				],
			},
			"_material_has_visible_surface": {
				"reachable": false,
				"token_groups": [
					["BaseMaterial3D.TRANSPARENCY_DISABLED"],
					["BaseMaterial3D.DISTANCE_FADE_DISABLED"],
					["proximity_fade_enabled"],
				],
			},
		},
		# Base affordance discovery has no target-specific framebuffer ID. Until it
		# does, a ShaderMaterial cannot safely attest that its mesh emitted any
		# visible pixel: a fully transparent shader-backed pickable collider would
		# otherwise become a policy target through physics alone.
		"conservative_shader_material_rejection": [
			"_material_has_visible_surface",
		],
	},
	{
		"path": "res://scripts/game/characters/player.gd",
		"label": "production party-body observation presenter",
		"roots": ["get_player_observation_screen_candidates"],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"required_by_function": {
			"_ready": {
				"reachable": false,
				"token_groups": [
					["add_to_group("],
					["PLAYER_BODY_PRESENTER_GROUP", "player_observation_party_presenters"],
				],
			},
			"get_player_observation_screen_candidates": {
				"reachable": true,
				"token_groups": [
					["get_player_observation_render_nodes"],
					["camera.unproject_position("],
					["viewport.get_visible_rect("],
				],
			},
		},
	},
	{
		"path": "res://scripts/fragments/chunks/generated_stretch_chunk.gd",
		"label": "generated hydraulic shelter presentation",
		"roots": [],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"required_by_function": {
			"_build_hydraulic_puzzle": {
				"reachable": false,
				"token_groups": [
					["_hydraulic_exit_beacon"],
					["camera_occlusion_exempt"],
					["HydraulicExitBeaconTarget"],
				],
			},
		},
		"guards_before_emit": [
			{
				"function": "_build_hydraulic_puzzle",
				"emit_tokens": ["HydraulicExitBeaconTarget"],
				"guard_token_groups": [
					["_hydraulic_exit_beacon.set_meta("],
					["camera_occlusion_exempt"],
				],
			},
		],
	},
	{
		"path": "res://scripts/generation/stretch_generation_playtest_loop.gd",
		"label": "generated-stretch approval playthroughs",
		"roots": ["_play_golden_path", "_play_shadow_path", "_play_risky_recovery", "_play_visible_surface_path"],
		"input_required": ["_play_golden_path", "_play_shadow_path", "_play_risky_recovery", "_play_visible_surface_path", "_approval_interact_generated_node", "_approval_apply_solution_actions_before_node", "_approval_perform_solution_action", "_approval_move_party_to_interaction", "_approval_move_actor", "_approval_send_input_action", "_follow_golden_segment", "_move_party_to_node", "_move_party_to_node_report"],
		"rally_required": ["_play_visible_surface_path", "_approval_move_party_to_interaction", "_move_party_to_node", "_move_party_to_node_report"],
		"fixture_only": ["_diagnostic_direct_activate_generated_node"],
		"watchdog_contract": true,
		# A persona style may be supplied independently, but no shipped action may
		# be issued until the first strict player_observation_v1 has been sampled
		# and validated. This catches pre-observation RUN/Rally convenience actions.
		"observation_before_input": [
			{
				"function": "_drive_visible_player_discovery",
				# Discovery deliberately samples through the accounting wrapper: the
				# wrapper performs the real player-observation scan and credits only
				# its synchronous scan cost back to the active-path watchdog.
				"observation_tokens": ["_player_observation_snapshot("],
				"input_tokens": ["driver.call("],
				"validation_token_groups": [
					["_strict_player_observation", "observation.get(\"schema\"", "validate_player_observation("],
					["_strict_player_observation", "observation.get(\"source\"", "validate_player_observation("],
				],
			},
		],
		# These are deliberately concrete evidence values, not provenance strings.
		# Runtime tests still own semantic correctness; this static tripwire prevents
		# eligibility from regressing to decision_source/solver_trace self-attestation.
		"evidence_contracts": [
			{
				"function": "_play_visible_surface_path",
				"anchor_tokens": [
					"report[\"approval_eligible\"]",
					"report[\"persona_decision_feed_eligible\"]",
					"report[\"evidence_status\"]",
				],
				"required_token_groups": [
					["visible_outcome_reached"],
					["observation_decision_links_valid", "validated_observation_decision_count"],
					["visible_movement_receipts_valid", "visible_movement_complete", "all_visible_rallies_presented"],
				],
			},
			{
				"function": "playtest_spec",
				"anchor_tokens": ["golden_path_decisions_are_player_observable"],
				"required_token_groups": [
					["policy_evidence_valid", "_validate_player_surface_policy_evidence"],
				],
			},
		],
		"ordered_after_anchor": [
			{
				"function": "_drive_visible_player_discovery",
				"anchor_tokens": ["while decisions < decision_limit"],
				"ordered_token_groups": [
					["_emit_player_discovery_heartbeat("],
					["_player_discovery_watchdog_abort_reason("],
					["_player_observation_snapshot("],
					["_choose_observed_interaction("],
				],
			},
			{
				"function": "_drive_visible_player_discovery",
				"anchor_tokens": ["var final_watchdog_abort_reason"],
				"ordered_token_groups": [
					["_abort_player_discovery_for_watchdog("],
					["_finish_generated_strategy_trace("],
				],
			},
			{
				"function": "_player_observation_snapshot",
				"anchor_tokens": ["var observation_v: Variant = observer.call(\"snapshot\")"],
				"ordered_token_groups": [
					["var scan_usec :="],
					["_credit_player_observation_scan_time("],
					["return observation_v"],
				],
			},
			{
				"function": "_wait_for_observed_interaction_feedback",
				"anchor_tokens": ["while elapsed <"],
				"ordered_token_groups": [
					["_player_discovery_watchdog_abort_reason("],
					["_emit_player_discovery_heartbeat("],
					["create_timer("],
				],
			},
			{
				"function": "_wait_for_player_rally_settle",
				"anchor_tokens": ["while float(report[\"elapsed\"])"],
				"ordered_token_groups": [
					["_player_discovery_watchdog_abort_reason("],
					["_emit_player_discovery_heartbeat("],
					["create_timer("],
				],
			},
			{
				"function": "_finish_generated_strategy_trace",
				"anchor_tokens": ["for watchdog_failure_v"],
				"ordered_token_groups": [
					["ci_watchdog_abort"],
					["watchdog_abort_reasons"],
					["_append_generated_strategy_trace_record("],
				],
			},
		],
		"required_by_function": {
			"playtest_spec": {
				"reachable": false,
				"token_groups": [
					["mini(\n\t\tPLAYER_DISCOVERY_MAX_DECISIONS", "mini(PLAYER_DISCOVERY_MAX_DECISIONS"],
					["player_discovery_global_started_usec"],
					["player_discovery_global_deadline_usec"],
					["Time.get_ticks_usec("],
				],
			},
			"_drive_visible_player_discovery": {
				"reachable": true,
				"token_groups": [
					["set_party_running"],
					["select_single"],
					["select_party"],
					["input_issued"],
					["_append_visible_decision_record("],
				],
			},
			"_player_observation_snapshot": {
				"reachable": false,
				"token_groups": [
					["observer.call(\"snapshot\")"],
					["scan_started_usec"],
					["scan_usec"],
					["_credit_player_observation_scan_time("],
				],
			},
			"_new_player_discovery_watchdog": {
				"reachable": false,
				"token_groups": [
					["Time.get_ticks_usec("],
					["path_deadline_usec"],
					["global_deadline_usec"],
					["last_visible_progress_usec"],
					["next_heartbeat_usec"],
				],
			},
			"_player_discovery_watchdog_abort_reason": {
				"reachable": false,
				"token_groups": [
					["Time.get_ticks_usec("],
					["global_deadline_usec"],
					["path_deadline_usec"],
					["last_visible_progress_usec"],
					["player_visible_causal_progress_stalled"],
				],
			},
			"_note_player_discovery_visible_progress": {
				"reachable": false,
				"token_groups": [
					["last_visible_progress_usec"],
					["last_visible_progress_kind"],
					["progress_event_count"],
				],
			},
			"_consider_player_discovery_observation_progress": {
				"reachable": false,
				"token_groups": [
					["validate_player_observation("],
					["_player_observation_action_progress_signature("],
					["_note_player_discovery_visible_progress("],
				],
			},
			"_emit_player_discovery_heartbeat": {
				"reachable": false,
				"token_groups": [
					["next_heartbeat_usec"],
					["heartbeat_count"],
					["watchdog_heartbeats"],
					["seconds_since_visible_progress"],
					["[PLAYER_E2E_HEARTBEAT]"],
				],
			},
			"_abort_player_discovery_for_watchdog": {
				"reachable": false,
				"token_groups": [
					["watchdog_failures"],
					["interaction_failures"],
					["release_all_held_input"],
					["watchdog_input_release"],
					["[PLAYER_E2E_WATCHDOG_ABORT]"],
				],
			},
			"_wait_for_observed_interaction_feedback": {
				"reachable": false,
				"token_groups": [
					["_player_discovery_watchdog_abort_reason("],
					["_emit_player_discovery_heartbeat("],
					["create_timer("],
					["interaction_exact_result_timeout"],
				],
			},
			"_finish_generated_strategy_trace": {
				"reachable": false,
				"token_groups": [
					["watchdog_failures"],
					["ci_watchdog_abort"],
					["watchdog_abort_reasons"],
					["_append_generated_strategy_trace_record("],
				],
			},
			"_validate_player_surface_policy_evidence": {
				"reachable": true,
				"token_groups": [
					["validate_player_observation("],
					["_generated_decision_receipt_links_valid("],
					["classify_evidence("],
				],
			},
			"_generated_decision_receipt_links_valid": {
				"reachable": true,
				"token_groups": [
					["shipped_input_receipt("],
					["receipt_id"],
					["input_issued"],
					["target_result_attestation"],
					["_generated_transform_samples_valid("],
					["member_body_tokens"],
				],
			},
			"_wait_for_player_rally_settle": {
				"reachable": true,
				"token_groups": [
					["_player_discovery_watchdog_abort_reason("],
					["_emit_player_discovery_heartbeat("],
					["create_timer("],
					["rally_visible_motion_did_not_start"],
					["rally_incomplete_visible_motion_stalled"],
					["rally_visible_result_timeout"],
					["_derive_exact_observed_rally_lineage("],
					["_exact_rally_arrival_has_complete_visible_motion_history("],
					["movement_result_attestation"],
					["baseline_movement_serial"],
					["intended_members"],
					["global_position"],
					["global_transform.origin"],
					["get_position"],
					["get_render_position"],
					["max_projection_error"],
					["max_global_position_error"],
					["max_global_transform_error"],
					["first_global_position", "initial_global_position", "start_global_position"],
					["last_global_position", "latest_global_position", "end_global_position"],
					["displacement", "distance_travelled", "motion_distance"],
					["moved_subjects"],
					["visible_motion_verified"],
				],
			},
			"_drive_observed_rally": {
				"reachable": false,
				"token_groups": [
					["_hover_and_rebind_observed_affordance("],
					["_record_observed_hover_rebind_failure("],
					["rally_screen_from_rendered_hover"],
					["pointer_hover_receipt"],
					["rendered_hover_rebind_capture_serial"],
					["visible_motion_evidence"],
					["movement_result_attestation"],
					["movement_result_baseline_serial"],
					["transform_samples"],
					["moved_subjects"],
					["visible_motion_verified"],
				],
			},
			"_hover_and_rebind_observed_affordance": {
				"reachable": false,
				"token_groups": [
					["target_verb := str(chosen_affordance.get(\"verb\""],
					["target_consequence := str(chosen_affordance.get(\"consequence\""],
					["hover_screen"],
					["_driver_hover_receipt_point("],
					["_player_observation_snapshot("],
					["validate_player_observation("],
					["_observed_exact_affordance_at_pointer("],
					["target_verb, target_consequence, actual_point"],
				],
			},
			"_await_observed_affordance_action_stability": {
				"reachable": false,
				"token_groups": [
					["required_stable_samples := 3"],
					["_player_observation_projection_signature("],
					["RenderingServer.frame_post_draw"],
					[
						"var current_capture_serial := int(",
						"var last_capture_serial := int(",
					],
					["var next_capture_serial := int("],
					[
						"next_capture_serial <= current_capture_serial",
						"next_capture_serial <= last_capture_serial",
					],
					[
						"current_capture_serial = next_capture_serial",
						"last_capture_serial = next_capture_serial",
					],
					["maxi(3, required_stable_samples)"],
				],
			},
			"_player_observation_projection_signature": {
				"reachable": false,
				"token_groups": [
					["cue_kind != \"party_body\"", "cue_kind == \"party_body\""],
					["body_screen"],
					["kind != \"interact\"", "kind == \"interact\""],
					["interaction_screen"],
					["distinct_screens"],
					["state.get(\"viewport\""],
				],
			},
			"_observed_exact_affordance_at_pointer": {
				"reachable": false,
				"token_groups": [
					["target_token"],
					["target_kind"],
					["target_verb"],
					["target_consequence"],
					["affordance.get(\"verb\""],
					["affordance.get(\"consequence\""],
					["== target_verb"],
					["== target_consequence"],
					["matches.size() != 1"],
					["is_equal_approx(actual_point)"],
					["_player_observation_safe_action_point("],
				],
			},
			"_record_observed_hover_rebind_failure": {
				"reachable": false,
				"token_groups": [
					["_append_visible_decision_record("],
					["\"verb\": \"hover\""],
					["\"kind\": \"hover_pointer\""],
					[
						"observation_after,\n\t\t\tfalse,\n\t\t\t[]",
						"observation_after, false, []",
					],
					["presentation_only_human_reproducible"],
					["\"world_change\": false"],
					["\"world_input_issued\": false"],
					["player_reproducible"],
					["\"eligible_for_learning\": false"],
				],
			},
			"_generated_driver_receipt_supports_semantic_verb": {
				"reachable": false,
				"token_groups": [
					["\"hover\""],
					["kind == \"hover_pointer\""],
				],
			},
			"_generated_pointer_hover_rebind_valid": {
				"reachable": false,
				"token_groups": [
					["pointer_hover_receipt"],
					["rendered_hover_waited"],
					["world_input_sequence_before"],
					["rendered_hover_rebind_capture_serial"],
					["MOUSE_BUTTON_RIGHT"],
				],
			},
			"_decision_trace_feedback": {
				"reachable": false,
				"token_groups": [
					["select_single"],
					["select_party"],
					["portraits"],
					["selected"],
				],
			},
		},
		"forbidden_by_function": {
			"_drive_visible_player_discovery": {
				"accepted_after_feedback,": "a caller-computed boolean is passed into receipt finalization instead of the exact target presentation record",
				"_note_player_discovery_visible_progress(": "the outer policy resets liveness from a baseline/decision loop instead of a validated visible causal delta",
				"\"interaction_target_hover_rebind_failed\"": "an ordinary failed rendered hover immediately aborts interaction discovery instead of recording the pointer input and replanning from a fresh public observation",
			},
			"_drive_observed_rally": {
				"\"rally_target_hover_rebind_failed\"": "an ordinary failed rendered hover immediately aborts Rally discovery instead of recording the pointer input and replanning from a fresh public observation",
			},
			"_record_observed_hover_rebind_failure": {
				"_set_player_discovery_watchdog_pending(": "the hover evidence recorder owns trace ordering only; bounded replan policy must decide separately whether churn warrants an abort",
			},
			"_player_observation_projection_signature": {
				"viewport_bins": "fixed ground/move bins cannot prove that the rendered world projection has settled",
				"_ground": "ground probes or ground-token memory cannot prove projection stability",
				"ground_records": "ground/move samples are fixed screen bins and cannot anchor projection stability",
				"kind == \"move\"": "move affordances are fixed screen bins and cannot anchor projection stability",
				"kind != \"move\"": "projection stability must positively retain interaction presenters rather than deriving an anchor set from move bins",
				"camera.": "projection stability may use only public rendered observations, not a private camera object",
				"camera.get": "projection stability may use only public rendered observations, not private camera state",
				"get_camera": "projection stability may not discover or read a private camera",
				"get_world_3d": "projection stability may not read private world or physics state",
				"global_position": "projection stability may not read a private world position",
				"global_transform": "projection stability may not read a private presenter transform",
				"world_position": "projection stability may not read a private world position",
				"unproject_position": "projection stability may not project private world coordinates",
				"project_ray": "projection stability may not use a private camera/world ray",
			},
			"_emit_player_discovery_heartbeat": {
				"_note_player_discovery_visible_progress(": "a heartbeat is liveness metadata and must never manufacture visible causal progress",
			},
			"_wait_for_player_rally_settle": {
				"or float(report[\"elapsed\"]) >= 2.5": "a Rally is declared visually settled without any rendered party motion",
				"_sample_player_party_y(": "Rally evidence samples only authoritative Y instead of continuous full-XYZ live presenter transforms",
				"_sampled_multiple_y(": "Rally evidence reduces a full-transform path to a Y-only endpoint set",
			},
		},
	},
	{
		"path": "res://scripts/generation/stretch_generation_playtest_loop.gd",
		"label": "generated-stretch policy selection",
		"roots": [
			"_choose_observed_interaction",
			"_choose_observed_ground_near_interaction",
			"_choose_observed_frontier_ground",
			"_player_observation_resolve_target_screen",
			"_observed_interaction_actor_order",
		],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"presentation_only": true,
		"forbidden_presentation_code_tokens": {
			"validation_party_body_probe": "raw presenter transforms and ray blockers are validation-only and must not enter generated policy selection",
			"watchdog": "CI watchdog state must not enter target or action selection",
			"Time.get_ticks": "wall-clock time must not enter target or action selection",
			"deadline_usec": "deadline metadata must not enter target or action selection",
			"wall_seconds": "wall-clock budgets must not enter target or action selection",
			"heartbeat": "heartbeat metadata must not enter target or action selection",
			"last_visible_progress": "watchdog progress metadata must not enter target or action selection",
		},
	},
	{
		"path": "res://tools/generated_input_playthrough_driver.gd",
		"label": "generated input pilot",
		"roots": ["_run"],
		"input_required": ["_run", "_play_world_step", "_play_solution_actions_before_node", "_play_branch_solution_action", "_play_world_solution_action", "_play_node", "_ensure_full_party", "_send_generated_command", "_send_world_interaction", "_send_action", "_send_key", "_send_key_event"],
		"rally_required": ["_play_node", "_ensure_full_party"],
		"fixture_only": [],
	},
	{
		"path": "res://tools/agent_player_input_driver.gd",
		"label": "central shipped-input executor",
		"roots": ["select_single", "select_party", "move", "move_screen", "rally", "rally_screen", "hover_screen", "rally_screen_from_rendered_hover", "interact", "interact_screen", "interact_selected_screen_from_rendered_hover", "push", "set_party_running", "set_running", "stop", "click_screen", "drag_screen", "cancel_rally", "press_key", "park_pointer", "rotate_camera", "release_all_held_input"],
		"input_required": ["select_single", "select_party", "move", "move_screen", "rally", "rally_screen", "hover_screen", "rally_screen_from_rendered_hover", "interact", "interact_screen", "interact_selected_screen_from_rendered_hover", "push", "set_party_running", "set_running", "stop", "click_screen", "drag_screen", "cancel_rally", "press_key", "park_pointer", "rotate_camera", "release_all_held_input"],
		"rally_required": ["rally", "rally_screen", "rally_screen_from_rendered_hover"],
		"fixture_only": [],
		"required_by_function": {
			"_mouse_click": {
				"reachable": false,
				"token_groups": [
					["await _mouse_move(point)"],
					["_dispatch_mouse_button(point, button, true"],
					["_dispatch_mouse_button(point, button, false"],
					["await _wait_frames(1)"],
				],
			},
			"_dispatch_mouse_button": {
				"reachable": false,
				"token_groups": [
					["InputEventMouseButton.new()"],
					["event.position = point"],
					["\"position\": [point.x, point.y]"],
					["Input.parse_input_event(event)"],
					["_record_input_event(\"pointer_button\""],
				],
			},
			"_mouse_button": {
				"reachable": false,
				"token_groups": [
					["_dispatch_mouse_button(point, button, pressed"],
					["await _wait_frames(1)"],
				],
			},
			"_release_rally": {
				"reachable": false,
				"token_groups": [
					["event.position = point"],
					["\"position\": [point.x, point.y]"],
				],
			},
			"release_all_held_input": {
				"reachable": false,
				"token_groups": [
					["_held_keys.keys()"],
					["_held_mouse_buttons.keys()"],
					["event.pressed = false"],
					["Input.parse_input_event("],
					["_held_keys.clear()"],
					["_held_mouse_buttons.clear()"],
					["all_inputs_released"],
				],
			},
			"park_pointer": {
				"reachable": true,
				"token_groups": [
					["_viewport_rect().get_center()", "viewport_rect.get_center()"],
					["_begin_receipt(\"park_pointer\""],
					["input_issued"],
					["_mouse_move("],
					["_finish_receipt("],
				],
			},
			"rotate_camera": {
				"reachable": true,
				"token_groups": [
					["_begin_receipt(\"rotate_camera\""],
					["KEY_Q", "KEY_E"],
					["_send_key_state(keycode, true)"],
					["create_timer("],
					["_send_key_state(keycode, false)"],
					["_finish_receipt("],
				],
			},
			"select_single": {
				"reachable": true,
				"token_groups": [
					["input_issued"],
					["already_selected"],
					["_send_key("],
				],
			},
			"select_party": {
				"reachable": true,
				"token_groups": [
					["input_issued"],
					["already_selected"],
					["_presented_party_ids("],
					["unbound_members"],
					["CHARACTER_KEYS.has("],
					["_send_key("],
				],
			},
			"hold_rally": {
				"reachable": true,
				"token_groups": [
					["_presented_party_ids("],
					["intended_members"],
					["member_results"],
					["atomic_group"],
					["rally_event_count"],
				],
			},
			"hover_screen": {
				"reachable": true,
				"token_groups": [
					["_begin_receipt(\"hover_pointer\""],
					["target_token"],
					["_mouse_move(point)"],
					["RenderingServer.frame_post_draw"],
					["rendered_hover_waited"],
					["_rendered_hover_sequence"],
				],
			},
			"rally_screen_from_rendered_hover": {
				"reachable": true,
				"token_groups": [
					["rendered_hover_required"],
					["hold_rally(receipt, point, target_token)"],
				],
			},
			"interact_selected_screen_from_rendered_hover": {
				"reachable": true,
				"token_groups": [
					["preserve_group_selection"],
					["_dispatch_quick_right_click_from_rendered_hover("],
					["_interaction_command_seen_since("],
				],
			},
			"_dispatch_rally_down_from_rendered_hover": {
				"reachable": false,
				"token_groups": [
					["_rendered_hover_matches("],
					["_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, true)"],
				],
			},
			"_dispatch_quick_right_click_from_rendered_hover": {
				"reachable": false,
				"token_groups": [
					["_rendered_hover_matches("],
					["_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, true)"],
					["_dispatch_mouse_button(point, MOUSE_BUTTON_RIGHT, false)"],
				],
			},
			"set_party_running": {
				"reachable": true,
				"token_groups": [
					["input_issued"],
					["_visible_run_label("],
					["_send_key("],
				],
			},
		},
		"forbidden_by_function": {
			"_mouse_click": {
				"await _mouse_button(": "a quick click yields a slow rendered frame between button edges and can be reclassified as a held Rally",
			},
			"_presented_party_ids": {
				"CHARACTER_KEYS.has(": "Rally intent filters a HUD-presented member because its portrait binding is unfamiliar",
			},
			"_visible_refusal_text": {
				"_hud_message": "the input receipt reopens a private HUD label instead of leaving feedback derivation to player observations",
			},
			"_release_rally": {
				"_selection_controller": "the input receipt reopens the private selection controller",
				"_rally_indicator": "the input receipt reads private Rally presentation state",
			},
			"_dispatch_rally_down_from_rendered_hover": {
				"await ": "RMB-down may not yield after the fresh exact-token hover rebind",
				"_mouse_move(": "the atomic Rally commit may not move away from the revalidated hover pixel",
			},
			"_dispatch_quick_right_click_from_rendered_hover": {
				"await ": "RMB-down may not yield after the fresh exact-token hover rebind",
				"_mouse_move(": "the atomic interaction commit may not move away from the revalidated hover pixel",
			},
		},
	},
	{
		"path": "res://tools/agent_player_input_driver.gd",
		"label": "screen-input target derivation",
		"roots": [
			"select_single", "select_party", "move_screen", "rally_screen",
			"hover_screen", "rally_screen_from_rendered_hover",
			"interact_screen", "interact_selected_screen",
			"interact_selected_screen_from_rendered_hover", "set_party_running",
		],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"presentation_only": true,
		# These helpers read authority only after an input edge to construct a
		# receipt. They may not choose a target or decide whether to issue input.
		# Call sites remain in policy scope, so an action helper that calls
		# _game_state() for targeting (for example an "empty" world click) still fails.
		"receipt_only": [
			"_game_state", "_event_count", "_new_event_kinds",
			"_interaction_command_seen_since", "_rally_event_members",
			"_rally_event_member_destinations",
			"_annotate_group_rally_effect", "_finish_from_live_command",
			"_begin_receipt", "_finish_receipt", "_replace_receipt_snapshot",
			"finalize_group_rally_receipt", "finalize_interaction_receipt",
		],
		"forbidden_by_function": {
			"finalize_interaction_receipt": {
				"accepted_from_visible_result": "receipt acceptance trusts a caller boolean instead of a causally matched production interaction",
			},
		},
		"required_by_function": {
			"finalize_interaction_receipt": {
				"reachable": false,
				"token_groups": [
					["target_presentation: Dictionary"],
					["bool(receipt.get(\"accepted\"", "bool(receipt.get('accepted'"],
					["source_token"],
					["presentation_serial"],
					["result"],
					["visible"],
					["accepted_from_target_result"],
				],
			},
		},
	},
	{
		"path": "res://tools/verify_generated_interaction_truth.gd",
		"label": "generated exact pointer receipt verifier",
		"roots": [],
		"input_required": [],
		"rally_required": [],
		"fixture_only": [],
		"required_by_function": {
			"_exact_pointer_receipt_matches": {
				"reachable": false,
				"token_groups": [
					["viewport_rect.has_point(expected_point)"],
					["input_sequence_before"],
					["input_sequence_after"],
					["input_event_count"],
					["events_v as Array).size() != 3"],
					["before + index + 1"],
					["_receipt_position_matches("],
					["_exact_pointer_button_event("],
				],
			},
		},
	},
]

const DIRECT_STATE := {
	"command_move_to_pos": "direct singleton GameState movement",
	"command_move_to_grid": "direct singleton GameState movement",
	"command_move_cross_level": "direct cross-level GameState movement",
	"command_walk_path": "direct GameState path command",
	"command_stop": "direct GameState stop command",
	"set_running": "direct GameState locomotion mutation",
	"command_start_drag": "direct GameState drag command",
	"command_stop_drag": "direct GameState drag command",
	"command_push": "direct GameState push command",
	"command_rest": "direct GameState rest command",
	"command_rally_members": "direct Rally authority call instead of the held gesture",
	"snap_character_to": "character teleport/snap",
	"set_character_level": "direct character-level mutation",
	"headless_move_character": "headless movement shortcut",
	"headless_set_character_position": "headless teleport shortcut",
	"headless_commit_rally": "headless Rally shortcut instead of the held gesture",
	"headless_select_character": "headless selection shortcut",
	"headless_advance": "direct scheduler advancement instead of the production frame clock",
	"set_preview_character_stat": "direct preview-stat mutation",
	"adjust_preview_character_stat": "direct preview-stat mutation",
	".set_stat(": "direct GameState stat mutation",
	".adjust_stat(": "direct GameState stat mutation",
	".set_world_state(": "direct authoritative world-state mutation",
	"get_tree().paused =": "direct pause-state repair inside measured evidence",
	".set_paused(": "direct pause-presenter repair inside measured evidence",
	".resume()": "direct scheduler repair inside measured evidence",
}
const DYNAMIC_DIRECT_STATE_METHODS := {
	"command_move_to_pos": "dynamic singleton GameState movement",
	"command_move_to_grid": "dynamic singleton GameState movement",
	"command_move_cross_level": "dynamic cross-level GameState movement",
	"command_walk_path": "dynamic GameState path command",
	"command_stop": "dynamic GameState stop command",
	"command_start_drag": "dynamic GameState drag command",
	"command_stop_drag": "dynamic GameState drag command",
	"command_push": "dynamic GameState push command",
	"command_rest": "dynamic GameState rest command",
	"command_rally_members": "dynamic Rally authority call instead of the held gesture",
	"snap_character_to": "dynamic character teleport/snap",
	"set_character_level": "dynamic character-level mutation",
	"headless_move_character": "dynamic headless movement shortcut",
	"headless_set_character_position": "dynamic headless teleport shortcut",
	"headless_commit_rally": "dynamic headless Rally shortcut instead of the held gesture",
	"headless_select_character": "dynamic headless selection shortcut",
	"headless_advance": "dynamic scheduler advancement instead of the production frame clock",
	"set_preview_character_stat": "dynamic preview-stat mutation",
	"adjust_preview_character_stat": "dynamic preview-stat mutation",
	"set_stat": "dynamic GameState stat mutation",
	"adjust_stat": "dynamic GameState stat mutation",
	"set_world_state": "dynamic authoritative world-state mutation",
}
const HIDDEN_POLICY_OBSERVATION := {
	"_game_state": "private GameState access",
	"_active_chunk": "private active-chunk access",
	"get_preview_state": "private preview/FSM state",
	"get_preview_anchors": "authored solve-anchor access",
	"get_preview_registry": "private target registry access",
	"_interactables": "private interactable registry access",
	"get_character_level": "exact authoritative level access",
	"get_render_position": "exact authoritative character-position access",
	"get_position(": "exact authoritative world-position access",
	"grid_to_world": "exact grid/world transform access",
	"world_to_grid": "exact world/grid transform access",
	"Vector3(": "hard-coded world-space target access",
}
const DIRECT_CONSEQUENCE := {
	".on_interaction_arrived(": "direct interaction-arrival callback",
	"call(\"on_interaction_arrived\"": "direct interaction-arrival callback",
	"._trigger(": "direct interactable trigger",
	"call(\"_trigger\"": "direct interactable trigger",
	"trigger_interactable(": "direct interactable trigger",
	"activate_generated_node": "direct generated-mechanism activation",
	"interaction_requested.emit": "direct interaction signal emission",
	"emit_signal(\"interaction_requested\"": "direct interaction signal emission",
	".set(\"active_character\"": "direct interaction actor mutation",
	"call(\"_input\"": "direct _input callback instead of SceneTree input delivery",
	"_on_interaction_requested(": "direct interaction request callback",
	"_commit_rally(": "direct Rally consequence commit",
	"_commit_pick(": "direct pick consequence commit",
}
const SINGLETON_MOVES := ["command_move_to_pos", "command_move_to_grid", "command_move_cross_level", "command_walk_path", "headless_move_character", "headless_set_character_position", "snap_character_to"]
const INPUT_BOUNDARIES := ["Input.parse_input_event(", "Input.action_press(", "Input.action_release(", "push_input(", "AgentPlayerInputDriver", "PersonaPlayerController", "PlayerGestureDriver", "PlayerInputDriver", "HumanParityInputDriver", "player_input_driver", "agent_input_driver", "gesture_driver", "call(\"move_screen\"", "call(\"rally_screen\"", "call(\"interact_screen\""]
const RALLY_BOUNDARIES := [".rally(", ".rally_screen(", "driver.call(\"rally\",", "call(\"rally_screen\"", "rally_party(", "rally_all(", "perform_rally(", "hold_rally(", "rally_whole_party("]

var _checks := 0
var _failures := 0
var _seen := {}
var _calls := RegEx.new()
var _called_cache := {}

func _init() -> void:
	_calls.compile("(^|[^A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	call_deferred("_run")

func _run() -> void:
	if "--scan-outline-observation-materials" in OS.get_cmdline_user_args():
		await _scan_outline_observation_materials()
		quit(0)
		return
	if "--verify-player-discovery-watchdog-contract" in OS.get_cmdline_user_args():
		await _test_player_discovery_watchdog_contract()
		print("PLAYER DISCOVERY WATCHDOG CONTRACT: %d checks, %d failures" % [
			_checks, _failures])
		quit(0 if _failures == 0 else 1)
		return
	_verify_cursor_and_window_isolation("res://")
	_verify_cursor_policy_mutation_fixtures()
	_verify_constructed_evidence_method_mutation_fixtures()
	_verify_exact_pointer_receipt_fixtures()
	_verify_rally_arrival_visibility_fixtures()
	_verify_movement_continuity_fixtures()
	for audit_v in AUDITS:
		_audit(audit_v as Dictionary)
	print("AGENT PLAYER INPUT BOUNDARY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_movement_continuity_fixtures() -> void:
	var continuous = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var continuous_plan := _continuity_ordinary_authority([
		Vector3.ZERO,
		Vector3(2.0, 0.5, 0.0),
		Vector3(4.0, 1.0, 0.0),
		Vector3(6.0, 1.5, 0.0),
	], [0.0, 0.25, 0.50, 0.75], "continuous")
	_continuity_sample(continuous, 0, 0.0, false, Vector3.ZERO)
	_continuity_sample(continuous, 1, 0.25, true, Vector3(2.0, 0.5, 0.0), {
		"category": "navigation", "kind": "continuous_route", "type": "walk",
	}, 9.0, continuous_plan)
	_continuity_sample(continuous, 2, 0.50, true, Vector3(4.0, 1.0, 0.0), {
		"category": "navigation_edge", "kind": "cross_level", "type": "ladder",
	}, 9.0, continuous_plan)
	_continuity_sample(continuous, 3, 0.75, false, Vector3(6.0, 1.5, 0.0))
	var continuous_receipt := continuous.receipt("aster") as Dictionary
	var continuous_episode := continuous_receipt.get(
		"last_completed_episode", {}) as Dictionary
	_continuity_runtime_assert(
		bool(continuous_receipt.get("valid", false))
		and int(continuous_receipt.get("completed_continuous_episode_count", 0)) == 1
		and int(continuous_episode.get(
			"strict_interior_presented_frame_count", 0)) == 2
		and int(continuous_episode.get(
			"strict_interior_scheduler_tick_count", 0)) == 2
		and float(continuous_episode.get("max_step_fraction", 1.0)) < 0.5
		and ((continuous_episode.get("movement_provenance", []) as Array).any(
			func(value: Variant) -> bool:
				return value is Dictionary \
					and str((value as Dictionary).get("type", "")) == "ladder")),
		"movement-continuity-accepts-bounded-full-xyz-route",
		"origin, two strict interior frames/ticks, endpoint, and typed ladder phase pass")

	var late_attachment = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var late_plan := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0,
	], [0.7, 0.8, 0.9], "late")
	_continuity_sample(late_attachment, 7, 0.7, true,
		Vector3.ZERO, {}, 12.0, late_plan)
	_continuity_sample(late_attachment, 8, 0.8, true,
		Vector3.RIGHT, {}, 12.0, late_plan)
	_continuity_sample(late_attachment, 9, 0.9, false, Vector3.RIGHT * 2.0)
	var late_attachment_receipt := late_attachment.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(late_attachment_receipt.get("valid", true))
		and int(late_attachment_receipt.get(
			"completed_continuous_episode_count", 0)) == 0
		and (late_attachment_receipt.get("violations", []) as Array).has(
			"movement_started_before_observed_origin"),
		"movement-continuity-rejects-late-attached-origin",
		"an in-flight suffix and settled endpoint cannot fabricate a settled origin")

	var synchronized_snap = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	_continuity_sample(synchronized_snap, 10, 1.0, false, Vector3.ZERO)
	_continuity_sample(synchronized_snap, 11, 1.1, false, Vector3(8.0, 2.0, -3.0))
	var synchronized_receipt := synchronized_snap.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(synchronized_receipt.get("valid", true))
		and int(synchronized_receipt.get("settled_jump_violation_count", 0)) == 1
		and (synchronized_receipt.get("violations", []) as Array).has(
			"settled_endpoint_jump_without_continuous_episode"),
		"movement-continuity-rejects-synchronized-endpoint-snap",
		"logical, render, global_position, and transform agreeing at a jumped endpoint still fails")

	var settled_drift = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	_continuity_sample(settled_drift, 12, 1.2, false, Vector3.ZERO)
	_continuity_sample(settled_drift, 13, 1.3, false, Vector3(0.05, 0.0, 0.0))
	_continuity_sample(settled_drift, 14, 1.4, false, Vector3(0.10, 0.0, 0.0))
	_continuity_sample(settled_drift, 15, 1.5, false, Vector3(0.15, 0.0, 0.0))
	var settled_drift_receipt := settled_drift.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(settled_drift_receipt.get("valid", true))
		and int(settled_drift_receipt.get(
			"settled_jump_violation_count", 0)) == 1,
		"movement-continuity-rejects-accumulated-settled-drift",
		"sub-threshold direct mutations cannot move the legal settled anchor")

	var endpoint_correction = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var endpoint_plan := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0, Vector3.RIGHT * 3.0,
	], [1.6, 1.7, 1.8, 1.9], "endpoint")
	_continuity_sample(endpoint_correction, 16, 1.6, false, Vector3.ZERO)
	_continuity_sample(endpoint_correction, 17, 1.7, true,
		Vector3.RIGHT, {}, 12.0, endpoint_plan)
	_continuity_sample(endpoint_correction, 18, 1.8, true,
		Vector3.RIGHT * 2.0, {}, 12.0, endpoint_plan)
	_continuity_sample(endpoint_correction, 19, 1.9, false, Vector3.RIGHT * 8.0)
	var endpoint_correction_receipt := endpoint_correction.receipt(
		"aster") as Dictionary
	var endpoint_correction_episode := endpoint_correction_receipt.get(
		"last_completed_episode", {}) as Dictionary
	_continuity_runtime_assert(
		not bool(endpoint_correction_receipt.get("valid", true))
		and int(endpoint_correction_receipt.get("invalid_episode_count", 0)) == 1
		and float(endpoint_correction_episode.get(
			"max_step_fraction", 0.0)) >= 0.5,
		"movement-continuity-rejects-large-endpoint-correction",
		"two real interior samples cannot launder a dominant final-position snap")

	var subhalf_local_jump = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var subhalf_plan := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0,
		Vector3.RIGHT * 3.0, Vector3.RIGHT * 4.0, Vector3.RIGHT * 5.0,
	], [2.0, 3.0, 4.0, 5.0, 6.0, 7.0], "subhalf")
	_continuity_sample(subhalf_local_jump, 20, 2.0, false, Vector3.ZERO)
	_continuity_sample(subhalf_local_jump, 21, 3.0, true,
		Vector3.RIGHT, {}, 1.1, subhalf_plan)
	_continuity_sample(subhalf_local_jump, 22, 4.0, true,
		Vector3.RIGHT * 2.0, {}, 1.1, subhalf_plan)
	_continuity_sample(subhalf_local_jump, 23, 5.0, true,
		Vector3.RIGHT * 3.0, {}, 1.1, subhalf_plan)
	_continuity_sample(subhalf_local_jump, 24, 6.0, true,
		Vector3.RIGHT * 5.0, {}, 1.1, subhalf_plan)
	_continuity_sample(subhalf_local_jump, 25, 7.0, false,
		Vector3.RIGHT * 5.0)
	var subhalf_jump_receipt := subhalf_local_jump.receipt("aster") as Dictionary
	var subhalf_jump_episode := subhalf_jump_receipt.get(
		"last_completed_episode", {}) as Dictionary
	_continuity_runtime_assert(
		not bool(subhalf_jump_receipt.get("valid", true))
		and float(subhalf_jump_episode.get("max_step_fraction", 1.0)) < 0.5
		and (subhalf_jump_episode.get("violations", []) as Array).has(
			"logical_position_local_speed_bound_exceeded"),
		"movement-continuity-rejects-subhalf-local-jump",
		"0->1->2->3->5 fails its declared local speed even though no step dominates half the path")

	var wrong_path = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var l_shaped_plan := _continuity_ordinary_authority([
		Vector3.ZERO,
		Vector3(0.0, 0.0, 5.0),
		Vector3(0.0, 0.0, 10.0),
		Vector3(5.0, 0.0, 10.0),
		Vector3(10.0, 0.0, 10.0),
	], [8.0, 9.0, 10.0, 11.0, 12.0], "wrong-path")
	_continuity_sample(wrong_path, 80, 8.0, false, Vector3.ZERO)
	_continuity_sample(wrong_path, 81, 9.0, true,
		Vector3(5.0, 0.0, 0.0), {}, 5.1, l_shaped_plan)
	_continuity_sample(wrong_path, 82, 10.0, true,
		Vector3(10.0, 0.0, 0.0), {}, 5.1, l_shaped_plan)
	_continuity_sample(wrong_path, 83, 11.0, true,
		Vector3(10.0, 0.0, 5.0), {}, 5.1, l_shaped_plan)
	_continuity_sample(wrong_path, 84, 12.0, false,
		Vector3(10.0, 0.0, 10.0))
	var wrong_path_receipt := wrong_path.receipt("aster") as Dictionary
	var wrong_path_episode := wrong_path_receipt.get(
		"last_completed_episode", {}) as Dictionary
	_continuity_runtime_assert(
		not bool(wrong_path_receipt.get("valid", true))
		and float(wrong_path_receipt.get("max_logical_speed_excess", INF)) <= 0.01
		and float(wrong_path_episode.get("max_step_fraction", 1.0)) < 0.5
		and (wrong_path_episode.get("violations", []) as Array).has(
			"logical_position_not_on_committed_motion_plan"),
		"movement-continuity-rejects-same-speed-wrong-path",
		("equal-length steps and matching endpoints cannot cut across space outside " \
		+ "the exact committed path"))

	var repaired_endpoint = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var repaired_plan := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0, Vector3.RIGHT * 3.0,
	], [13.0, 14.0, 15.0, 16.0], "repaired-endpoint")
	_continuity_sample(repaired_endpoint, 90, 13.0, false, Vector3.ZERO)
	_continuity_sample(repaired_endpoint, 91, 14.0, true,
		Vector3.RIGHT, {}, 1.1, repaired_plan)
	_continuity_sample(repaired_endpoint, 92, 15.0, true,
		Vector3.RIGHT * 2.0, {}, 1.1, repaired_plan)
	_continuity_sample(repaired_endpoint, 93, 16.0, false,
		Vector3(NAN, 0.0, 0.0))
	_continuity_sample(repaired_endpoint, 94, 16.0, false,
		Vector3.RIGHT * 3.0)
	var repaired_endpoint_receipt := repaired_endpoint.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(repaired_endpoint_receipt.get("valid", true))
		and (repaired_endpoint_receipt.get("violations", []) as Array).has(
			"malformed_or_non_finite_sample"),
		"movement-continuity-retains-malformed-endpoint-frame",
		"a repaired endpoint cannot erase an earlier non-finite presented endpoint frame")

	var valid_handoff = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var handoff_walk := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0,
	], [5.0, 5.5, 6.0], "handoff-walk")
	var handoff_external := _continuity_external_authority([
		Vector3.RIGHT * 1.5,
		Vector3.RIGHT * 2.5,
		Vector3.RIGHT * 3.5,
	], [0.0, 1.0, 2.0], 5.75, 6.75, "handoff-external")
	_continuity_sample(valid_handoff, 60, 5.0, false, Vector3.ZERO)
	_continuity_sample(valid_handoff, 61, 5.25, true,
		Vector3.RIGHT * 0.5, {}, 2.1, handoff_walk)
	_continuity_sample(valid_handoff, 62, 5.5, true,
		Vector3.RIGHT, {}, 2.1, handoff_walk)
	_continuity_sample(valid_handoff, 63, 6.0, true,
		Vector3.RIGHT * 2.0, {}, 2.1, handoff_external)
	_continuity_sample(valid_handoff, 64, 6.25, true,
		Vector3.RIGHT * 2.5, {}, 2.1, handoff_external)
	_continuity_sample(valid_handoff, 65, 6.75, false,
		Vector3.RIGHT * 3.5)
	var valid_handoff_receipt := valid_handoff.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		bool(valid_handoff_receipt.get("valid", false))
		and int(valid_handoff_receipt.get("bounded_step_count", 0)) >= 5
		and int(valid_handoff_receipt.get(
			"invalid_motion_authority_count", -1)) == 0
		and float(valid_handoff_receipt.get(
			"max_logical_speed_excess", INF)) <= 0.01
		and float(valid_handoff_receipt.get(
			"max_render_speed_excess", INF)) <= 0.01,
		"movement-continuity-accepts-exact-plan-handoff",
		"one ordinary-to-external seam contributes the exact tail plus head arc budget")

	var bad_handoff = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	var bad_walk := _continuity_ordinary_authority([
		Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0,
	], [7.0, 7.5, 8.0], "bad-handoff-walk")
	var bad_external := _continuity_external_authority([
		Vector3.RIGHT * 1.75,
		Vector3.RIGHT * 2.75,
		Vector3.RIGHT * 3.75,
	], [0.0, 1.0, 2.0], 7.75, 8.75, "bad-handoff-external")
	_continuity_sample(bad_handoff, 70, 7.0, false, Vector3.ZERO)
	_continuity_sample(bad_handoff, 71, 7.25, true,
		Vector3.RIGHT * 0.5, {}, 2.1, bad_walk)
	_continuity_sample(bad_handoff, 72, 7.5, true,
		Vector3.RIGHT, {}, 2.1, bad_walk)
	_continuity_sample(bad_handoff, 73, 8.0, true,
		Vector3.RIGHT * 2.25, {}, 2.1, bad_external)
	_continuity_sample(bad_handoff, 74, 8.25, true,
		Vector3.RIGHT * 2.75, {}, 2.1, bad_external)
	_continuity_sample(bad_handoff, 75, 8.75, false,
		Vector3.RIGHT * 3.75)
	var bad_handoff_receipt := bad_handoff.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(bad_handoff_receipt.get("valid", true))
		and int(bad_handoff_receipt.get(
			"invalid_motion_authority_count", 0)) >= 1
		and (bad_handoff_receipt.get("violations", []) as Array).has(
			"invalid_motion_authority_interval"),
		"movement-continuity-rejects-spatially-disconnected-handoff",
		"a new plan cannot claim an interval unless its start is the old plan's exact seam")

	var portal_source := Vector3(1.0, 0.0, 2.0)
	var portal_destination := Vector3(31.0, 4.0, -9.0)
	var unissued_portal = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	_continuity_sample(unissued_portal, 30, 3.0, false, portal_source)
	var fully_shaped_but_unissued_portal := {
		"contract_id": "typed_portal_discontinuity/v1",
		"category": "topology_transition",
		"kind": "portal_hop",
		"type": "portal",
		"character_id": "aster",
		"authority_key": "gameplay:portal_pad:west_to_east",
		"transition_serial": 4,
		"source": {"x": portal_source.x, "y": portal_source.y, "z": portal_source.z},
		"destination": {
			"x": portal_destination.x,
			"y": portal_destination.y,
			"z": portal_destination.z,
		},
	}
	unissued_portal.sample({
		"character_id": "aster",
		"scheduler_tick": 3.1,
		"presented_frame": 31,
		"in_flight": false,
		"logical_position": portal_destination,
		"render_position": portal_destination,
		"presented_position": portal_destination,
		"presented_transform_origin": portal_destination,
		"logical_to_render_projection_valid": true,
		"logical_to_render_projection_error": 0.0,
		"declared_local_speed_bound": 0.0,
		"motion_authority": _continuity_hold_authority(portal_destination, 3.1),
		"portal_discontinuity": fully_shaped_but_unissued_portal,
	})
	var unissued_portal_result := unissued_portal.receipt("aster") as Dictionary
	_continuity_runtime_assert(
		not bool(unissued_portal_result.get("valid", true))
		and int(unissued_portal_result.get("typed_portal_exception_count", 0)) == 0
		and int(unissued_portal_result.get("settled_jump_violation_count", 0)) == 1
		and (unissued_portal_result.get("violations", []) as Array).has(
			"unissued_portal_discontinuity_not_authorized"),
		"movement-continuity-rejects-shaped-but-unissued-portal",
		("shape is not authority; a future exception requires a production " \
		+ "portal issuer and causal lineage"))

	var settled_split_authority = MOVEMENT_CONTINUITY_TRACKER_SCRIPT.new()
	settled_split_authority.sample({
		"character_id": "aster",
		"scheduler_tick": 4.2,
		"presented_frame": 42,
		"in_flight": false,
		"logical_position": Vector3.ZERO,
		"render_position": Vector3.ZERO,
		"presented_position": Vector3(0.10, 0.0, 0.0),
		"presented_transform_origin": Vector3(0.10, 0.0, 0.0),
		"logical_to_render_projection_valid": false,
		"logical_to_render_projection_error": 0.20,
		"declared_local_speed_bound": 0.0,
		"motion_authority": _continuity_hold_authority(Vector3.ZERO, 4.2),
	})
	var settled_split_result := settled_split_authority.receipt(
		"aster") as Dictionary
	_continuity_runtime_assert(
		not bool(settled_split_result.get("valid", true))
		and (settled_split_result.get("violations", []) as Array).has(
			"logical_render_projection_diverged")
		and (settled_split_result.get("violations", []) as Array).has(
			"global_position_diverged_from_render")
		and (settled_split_result.get("violations", []) as Array).has(
			"global_transform_origin_diverged_from_render"),
		"movement-continuity-rejects-settled-split-authority",
		("settled projection/presentation cannot drift outside parity tolerance " \
		+ "below the movement threshold"))


func _continuity_sample(
		tracker,
		presented_frame: int,
		scheduler_tick: float,
		in_flight: bool,
		position: Vector3,
		movement_provenance: Dictionary = {},
		declared_local_speed_bound := 0.0,
		motion_authority: Dictionary = {},
		projection_valid := true,
		projection_error := 0.0
	) -> void:
	var resolved_motion_authority := motion_authority.duplicate(true) \
		if not motion_authority.is_empty() \
		else _continuity_hold_authority(position, scheduler_tick)
	resolved_motion_authority["sample_tick"] = scheduler_tick
	if str(resolved_motion_authority.get("phase", "")) in ["settled", "route_hold"]:
		resolved_motion_authority["start_tick"] = scheduler_tick
		resolved_motion_authority["end_tick"] = scheduler_tick
	tracker.sample({
		"character_id": "aster",
		"scheduler_tick": scheduler_tick,
		"presented_frame": presented_frame,
		"in_flight": in_flight,
		"logical_position": position,
		"render_position": position,
		"presented_position": position,
		"presented_transform_origin": position,
		"logical_to_render_projection_valid": projection_valid,
		"logical_to_render_projection_error": projection_error,
		"declared_local_speed_bound": declared_local_speed_bound,
		"motion_authority": resolved_motion_authority,
		"movement_provenance": movement_provenance,
		"portal_discontinuity": {},
	})


func _continuity_hold_authority(position: Vector3, sample_tick := 0.0) -> Dictionary:
	return {
		"contract_id": "movement_authority/v1",
		"valid": position.is_finite(),
		"phase": "settled",
		"plan_key": "",
		"sample_tick": sample_tick,
		"start_tick": sample_tick,
		"end_tick": sample_tick,
		"data_anchor": position,
		"render_anchor": position,
		"data_path": [],
		"render_path": [],
		"break_ticks": [],
		"path_cumulative": [],
		"progress_start": 0.0,
		"coord_map_id": 0,
	}


func _continuity_ordinary_authority(
		path: Array, break_ticks: Array, plan_key: String) -> Dictionary:
	return {
		"contract_id": "movement_authority/v1",
		"valid": true,
		"phase": "ordinary",
		"plan_key": plan_key,
		"sample_tick": float(break_ticks[0]),
		"start_tick": float(break_ticks[0]),
		"end_tick": float(break_ticks.back()),
		"data_anchor": path[0],
		"render_anchor": path[0],
		"data_path": path.duplicate(),
		"render_path": path.duplicate(),
		"break_ticks": break_ticks.duplicate(),
		"path_cumulative": [],
		"progress_start": 0.0,
		"coord_map_id": 0,
	}


func _continuity_external_authority(
		path: Array, cumulative: Array, start_tick: float,
		end_tick: float, plan_key: String, progress_start := 0.0) -> Dictionary:
	return {
		"contract_id": "movement_authority/v1",
		"valid": true,
		"phase": "external",
		"plan_key": plan_key,
		"sample_tick": start_tick,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"data_anchor": path[0],
		"render_anchor": path[0],
		"data_path": path.duplicate(),
		"render_path": path.duplicate(),
		"break_ticks": [],
		"path_cumulative": cumulative.duplicate(),
		"progress_start": progress_start,
		"coord_map_id": 0,
	}


func _continuity_runtime_assert(
		condition: bool, rule: String, detail: String) -> void:
	_checks += 1
	if not condition:
		_fail("res://tools/verify_agent_player_input_boundary.gd",
			"<movement-continuity-runtime>", 0, rule, detail, "")


func _verify_exact_pointer_receipt_fixtures() -> void:
	var point := Vector2(321.25, 123.75)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	var receipt := {
		"kind": "interact",
		"screen_point": point,
		"input_issued": true,
		"input_sequence_before": 0,
		"input_sequence_after": 3,
		"input_event_count": 3,
		"input_events": [
			{
				"sequence": 1,
				"kind": "pointer_move",
				"issued": true,
				"button_mask": 0,
				"position": [point.x, point.y],
			},
			{
				"sequence": 2,
				"kind": "pointer_button",
				"issued": true,
				"button": MOUSE_BUTTON_RIGHT,
				"pressed": true,
				"shift": false,
				"double_click": false,
				"button_mask": MOUSE_BUTTON_MASK_RIGHT,
				"position": [point.x, point.y],
			},
			{
				"sequence": 3,
				"kind": "pointer_button",
				"issued": true,
				"button": MOUSE_BUTTON_RIGHT,
				"pressed": false,
				"shift": false,
				"double_click": false,
				"button_mask": 0,
				"position": [point.x, point.y],
			},
		],
	}
	var canonical_pointer_receipt := bool(
		GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			receipt, point, viewport_rect, true))
	_pointer_receipt_assert(
		canonical_pointer_receipt,
		"exact-pointer-ledger-accepts-canonical",
		"one fresh move/down/up ledger at the observed viewport point must pass"
	)

	var reordered := receipt.duplicate(true)
	var reordered_events := reordered.get("input_events", []) as Array
	var reordered_down: Variant = reordered_events[1]
	reordered_events[1] = reordered_events[2]
	reordered_events[2] = reordered_down
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			reordered, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-order",
		"an RMB release-before-press forgery must fail"
	)

	var extra_event := receipt.duplicate(true)
	var extra_events := extra_event.get("input_events", []) as Array
	var forged_extra := (extra_events[0] as Dictionary).duplicate(true)
	forged_extra["sequence"] = 4
	extra_events.append(forged_extra)
	extra_event["input_event_count"] = 4
	extra_event["input_sequence_after"] = 4
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			extra_event, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-extra-event",
		"a second pointer move cannot be hidden in an otherwise coherent ledger"
	)

	var false_count := receipt.duplicate(true)
	false_count["input_event_count"] = 2
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			false_count, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-count",
		"the declared input count must equal the exact three-event ledger"
	)

	var sequence_gap := receipt.duplicate(true)
	(sequence_gap.get("input_events", []) as Array)[1]["sequence"] = 3
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			sequence_gap, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-sequence-gap",
		"move, down, and up must occupy contiguous sequence bounds"
	)

	var wrong_position := receipt.duplicate(true)
	(wrong_position.get("input_events", []) as Array)[2]["position"] = [
		point.x + 1.0, point.y,
	]
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			wrong_position, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-position",
		"every mechanical edge must carry the exact revalidated viewport point"
	)

	var wrong_screen_description := receipt.duplicate(true)
	wrong_screen_description["screen_point"] = point + Vector2(0.0, 1.0)
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			wrong_screen_description, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-screen-description",
		"the receipt target description must match the revalidated observed point"
	)

	var unissued_event := receipt.duplicate(true)
	(unissued_event.get("input_events", []) as Array)[1]["issued"] = false
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			unissued_event, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-unissued-edge",
		"every recorded mechanical edge must carry a strict issued flag"
	)

	var unissued_receipt := receipt.duplicate(true)
	unissued_receipt["input_issued"] = false
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			unissued_receipt, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-unissued-receipt",
		"the command-level issued flag cannot be forged false"
	)

	var stale_ledger := receipt.duplicate(true)
	stale_ledger["input_sequence_before"] = 9
	stale_ledger["input_sequence_after"] = 12
	for index in range(3):
		(stale_ledger.get("input_events", []) as Array)[index]["sequence"] = 10 + index
	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			stale_ledger, point, viewport_rect, true),
		"exact-pointer-ledger-rejects-stale-prefix",
		"the measured generated click requires the freshly cleared input ledger"
	)

	_pointer_receipt_assert(
		not GENERATED_INTERACTION_TRUTH_SCRIPT._exact_pointer_receipt_matches(
			receipt, point, Rect2(Vector2.ZERO, Vector2(100.0, 100.0)), true),
		"exact-pointer-ledger-rejects-out-of-bounds",
		"an otherwise matching click outside the shipped viewport must fail"
	)


func _pointer_receipt_assert(condition: bool, rule: String, detail: String) -> void:
	_checks += 1
	if not condition:
		_fail("res://tools/verify_agent_player_input_boundary.gd",
			"<pointer-receipt-runtime>", 0, rule, detail, "")


func _verify_rally_arrival_visibility_fixtures() -> void:
	var loop = WATCHDOG_LOOP_SCRIPT.new()
	var target_token := "ground_arrival_fixture"
	var intended_members := ["aster", "endo", "peris"]
	var portrait_tokens := [
		"portrait_0001", "portrait_0002", "portrait_0003",
	]
	var member_body_tokens := {
		"aster": "body_0001",
		"endo": "body_0003",
		"peris": "body_0002",
	}
	var exact_arrival := {
		"visible": true,
		"accepted": true,
		"subjects_consistent": true,
		"accepted_consistent": true,
		"target_consistent": true,
		"phase_order_valid": true,
		"phase": "arrival",
		"phases": ["accepted", "progress", "arrival"],
		"phase_capture_serials": {
			"accepted": 71,
			"progress": 74,
			"arrival": 83,
		},
		"new_serial_count": 1,
		"presentation_serial": 6,
		"target_token": target_token,
		"subjects": portrait_tokens.duplicate(),
		"reason": "",
	}
	var all_visibly_moved := {
		"aster": true,
		"endo": true,
		"peris": true,
	}
	var no_concealed_members := {}
	# No body remains in the terminal frame. Earlier bound-body displacement and
	# the exact persistent ARRIVAL cue are the human-visible completion evidence.
	var terminal_visible_body_positions := {}
	var offscreen_arrival_settles := bool(loop.call(
		"_exact_rally_arrival_has_complete_visible_motion_history",
		exact_arrival,
		target_token,
		portrait_tokens,
		intended_members,
		member_body_tokens,
		no_concealed_members,
		all_visibly_moved,
		5
	))
	_watchdog_runtime_assert(
		terminal_visible_body_positions.is_empty() and offscreen_arrival_settles,
		"rally-arrival-after-bodies-leave-frame-settles",
		"all intended bodies moved visibly before an exact same-lineage ARRIVAL"
	)

	var one_member_never_seen_move := all_visibly_moved.duplicate()
	one_member_never_seen_move.erase("peris")
	_watchdog_runtime_assert(
		not bool(loop.call(
			"_exact_rally_arrival_has_complete_visible_motion_history",
			exact_arrival,
			target_token,
			portrait_tokens,
			intended_members,
			member_body_tokens,
			no_concealed_members,
			one_member_never_seen_move,
			5
		)),
		"rally-arrival-never-seen-member-fails",
		"an ARRIVAL cue cannot replace missing visible motion for one intended body"
	)

	# Peris begins with an exact rendered HIDDEN portrait rather than a body cue.
	# Same-lineage PROGRESS presents Peris' movement while the other two members
	# retain their visible body-motion histories.
	var visible_member_body_tokens := member_body_tokens.duplicate(true)
	visible_member_body_tokens.erase("peris")
	var concealed_peris := {
		"peris": "portrait_0003",
	}
	_watchdog_runtime_assert(
		bool(loop.call(
			"_exact_rally_arrival_has_complete_visible_motion_history",
			exact_arrival,
			target_token,
			portrait_tokens,
			intended_members,
			visible_member_body_tokens,
			concealed_peris,
			all_visibly_moved,
			5
		)),
		"rally-arrival-exact-hidden-lineage-settles",
		"an exact initial HIDDEN portrait may carry same-lineage Rally progress"
	)
	_watchdog_runtime_assert(
		not bool(loop.call(
			"_exact_rally_arrival_has_complete_visible_motion_history",
			exact_arrival,
			target_token,
			portrait_tokens,
			intended_members,
			visible_member_body_tokens,
			no_concealed_members,
			all_visibly_moved,
			5
		)),
		"rally-arrival-missing-hidden-binding-fails",
		"a member without a body cue needs its exact initial HIDDEN portrait binding"
	)

	var stationary_sample := {
		"endo": {
			"count": 2,
			"invalid": false,
			"first_logical": [13.5, 0.45, 3.5],
			"last_logical": [13.5, 0.45, 3.5],
			"logical_displacement": 0.0,
			"render_displacement": 0.0,
			"global_position_displacement": 0.0,
			"global_transform_displacement": 0.0,
		},
	}
	var exact_stationary_destination := {
		"aster": [12.5, 0.45, 2.5],
		"endo": [13.5, 0.45, 3.5],
		"peris": [14.5, 0.45, 3.5],
	}
	_watchdog_runtime_assert(
		bool(loop.call(
			"_generated_stationary_rally_endpoint_valid",
			"endo", stationary_sample, exact_stationary_destination)),
		"rally-stationary-member-exact-endpoint-valid",
		"a member already on its immutable formation endpoint participates without fake travel"
	)
	var exact_stationary_members := loop.call(
		"_stationary_rally_arrival_members",
		stationary_sample,
		intended_members,
		exact_stationary_destination,
		exact_arrival,
		portrait_tokens
	) as Dictionary
	_watchdog_runtime_assert(
		exact_stationary_members.keys() == ["endo"],
		"rally-stationary-member-same-lineage-classified",
		"the exact whole-party ACCEPTED/PROGRESS/ARRIVAL lineage classifies only Endo at its assigned formation vertex"
	)
	var moved_plus_stationary := {
		"aster": true,
		"peris": true,
	}
	for member_v in exact_stationary_members.keys():
		moved_plus_stationary[str(member_v)] = true
	_watchdog_runtime_assert(
		bool(loop.call(
			"_exact_rally_arrival_has_complete_visible_motion_history",
			exact_arrival,
			target_token,
			portrait_tokens,
			intended_members,
			member_body_tokens,
			no_concealed_members,
			moved_plus_stationary,
			5
		)),
		"rally-arrival-stationary-member-participates",
		"an already-arrived member counts only after the exact same-lineage whole-party arrival names it"
	)
	_watchdog_runtime_assert(
		not bool(loop.call(
			"_exact_rally_arrival_has_complete_visible_motion_history",
			exact_arrival,
			target_token,
			portrait_tokens,
			intended_members,
			member_body_tokens,
			no_concealed_members,
			{"aster": true, "peris": true},
			5
		)),
		"rally-arrival-stationary-member-omission-fails",
		"the group receipt cannot use stationary participation to excuse an omitted intended member"
	)
	var wrong_stationary_destination := {
		"aster": [12.5, 0.45, 2.5],
		"endo": [17.5, 0.45, 3.5],
		"peris": [14.5, 0.45, 3.5],
	}
	_watchdog_runtime_assert(
		not bool(loop.call(
			"_generated_stationary_rally_endpoint_valid",
			"endo", stationary_sample, wrong_stationary_destination)),
		"rally-stationary-member-wrong-endpoint-fails",
		"zero displacement is never accepted without the exact production destination"
	)
	_watchdog_runtime_assert(
		(loop.call(
			"_stationary_rally_arrival_members",
			stationary_sample,
			intended_members,
			wrong_stationary_destination,
			exact_arrival,
			portrait_tokens
		) as Dictionary).is_empty(),
		"rally-stationary-member-wrong-destination-not-classified",
		"a zero-displacement member at any other point is not presented participation"
	)
	var omitted_destination := exact_stationary_destination.duplicate(true)
	omitted_destination.erase("peris")
	omitted_destination["outsider"] = [14.5, 0.45, 3.5]
	_watchdog_runtime_assert(
		(loop.call(
			"_stationary_rally_arrival_members",
			stationary_sample,
			intended_members,
			omitted_destination,
			exact_arrival,
			portrait_tokens
		) as Dictionary).is_empty(),
		"rally-stationary-member-destination-roster-exact",
		"an equal-sized destination map cannot replace an intended member with an outsider"
	)
	var incomplete_stationary_lineage := exact_arrival.duplicate(true)
	incomplete_stationary_lineage["phases"] = ["accepted", "arrival"]
	incomplete_stationary_lineage["phase_capture_serials"] = {
		"accepted": 71,
		"arrival": 83,
	}
	_watchdog_runtime_assert(
		(loop.call(
			"_stationary_rally_arrival_members",
			stationary_sample,
			intended_members,
			exact_stationary_destination,
			incomplete_stationary_lineage,
			portrait_tokens
		) as Dictionary).is_empty(),
		"rally-stationary-member-needs-progress-lineage",
		"an endpoint plus ARRIVAL cannot replace the exact whole-party PROGRESS cue"
	)
	var omitted_stationary_subject := exact_arrival.duplicate(true)
	var incomplete_subjects := portrait_tokens.duplicate()
	incomplete_subjects.remove_at(1)
	omitted_stationary_subject["subjects"] = incomplete_subjects
	_watchdog_runtime_assert(
		(loop.call(
			"_stationary_rally_arrival_members",
			stationary_sample,
			intended_members,
			exact_stationary_destination,
			omitted_stationary_subject,
			portrait_tokens
		) as Dictionary).is_empty(),
		"rally-stationary-member-needs-subject-lineage",
		"the same-lineage arrival must visibly name every intended portrait, including the stationary member"
	)


## App-local InputEvents are the only legal automated pointer seam. Scan every
## executable/test source file, including diagnostics and capture tools, so a
## dynamic call or alternate receiver cannot quietly reclaim the workstation
## pointer. Window relocation/mode authority has exactly one allowlisted owner.
func _verify_cursor_and_window_isolation(root_path: String) -> void:
	var source_paths: Array[String] = []
	_collect_executable_test_source_paths(root_path, source_paths)
	_checks += 1
	for source_path in source_paths:
		var source := FileAccess.get_file_as_string(source_path)
		for violation_v in _cursor_policy_violations(source, source_path):
			var violation := violation_v as Dictionary
			var token := str(violation.get("token", ""))
			var offset := source.to_lower().find(token.to_lower())
			var line_number := source.substr(0, maxi(0, offset)).count("\n") + 1
			_fail(source_path, "<file>", line_number,
				str(violation.get("category", "cursor-isolation")),
				str(violation.get("message", "source violates cursor/window isolation")),
				token)


func _verify_cursor_policy_mutation_fixtures() -> void:
	var pointer_warp_symbol := "".join(["warp", "_", "mouse"])
	var pointer_warp_csharp := "".join(["Warp", "Mouse"])
	var pointer_warp_prefix := "".join(["war", "p"])
	var pointer_warp_suffix := "".join(["_", "mouse"])
	var pointer_warp_fragment_a := "".join(["w", "ar"])
	var pointer_warp_fragment_b := "".join(["p", "_"])
	var pointer_warp_fragment_c := "".join(["mou", "se"])
	var capture_symbol := "".join(["set", "_", "mouse", "_", "mode"])
	var captured_mode := "".join(["MOUSE", "_", "MODE", "_", "CAPTURED"])
	var window_position_symbol := "".join(["window", "_", "set", "_", "position"])
	var window_mode_symbol := "".join(["window", "_", "set", "_", "mode"])
	var window_prefix := "".join(["win", "dow", "_"])
	var setter_prefix := "".join(["s", "et", "_"])
	var window_type_receiver := "".join(["Win", "dow"])
	var window_alias_receiver := "".join(["sur", "face"])
	var window_getter := "".join(["get", "_", "window"])
	var csharp_window_getter := "".join(["Get", "Window"])
	var window_foreground_symbol := "".join(["move", "_", "to", "_", "foreground"])
	var mutations := [
		{
			"name": "direct_input_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "Input.%s(Vector2.ZERO)" % pointer_warp_symbol,
			"category": "os-cursor-warp",
		},
		{
			"name": "spaced_input_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "Input . %s (Vector2.ZERO)" % pointer_warp_symbol,
			"category": "os-cursor-warp",
		},
		{
			"name": "dynamic_input_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "Input.call(\"%s\", Vector2.ZERO)" % pointer_warp_symbol,
			"category": "os-cursor-warp",
		},
		{
			"name": "constructed_dynamic_input_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "Input.call(\"%s\" + \"%s\", Vector2.ZERO)" % [
				pointer_warp_prefix, pointer_warp_suffix],
			"category": "os-cursor-warp",
		},
		{
			"name": "multi_fragment_dynamic_input_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "Input.call(\"%s\" + \"%s\" + \"%s\", Vector2.ZERO)" % [
				pointer_warp_fragment_a,
				pointer_warp_fragment_b,
				pointer_warp_fragment_c,
			],
			"category": "os-cursor-warp",
		},
		{
			"name": "csharp_input_warp",
			"path": "res://tests/mutation.cs",
			"source": "Input.%s(Vector2.Zero);" % pointer_warp_csharp,
			"category": "os-cursor-warp",
		},
		{
			"name": "display_server_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "DisplayServer.%s(Vector2.ZERO)" % pointer_warp_symbol,
			"category": "os-cursor-warp",
		},
		{
			"name": "viewport_warp",
			"path": "res://scripts/testing/mutation.gd",
			"source": "get_viewport().%s(Vector2.ZERO)" % pointer_warp_symbol,
			"category": "os-cursor-warp",
		},
		{
			"name": "dynamic_cursor_capture",
			"path": "res://tools/mutation.gd",
			"source": "Input.call(\"%s\", Input.%s)" % [capture_symbol, captured_mode],
			"category": "automated-os-pointer",
		},
		{
			"name": "window_reposition",
			"path": "res://scripts/testing/mutation.gd",
			"source": "DisplayServer.%s(Vector2i.ZERO)" % window_position_symbol,
			"category": "window-lifetime",
		},
		{
			"name": "dynamic_window_mode",
			"path": "res://scripts/testing/mutation.gd",
			"source": "DisplayServer.call(\"%s\", 0)" % window_mode_symbol,
			"category": "window-lifetime",
		},
		{
			"name": "constructed_window_position",
			"path": "res://scripts/testing/mutation.gd",
			"source": "DisplayServer.call(\"%s\" + \"%s\" + \"position\", Vector2i.ZERO)" % [
				window_prefix, setter_prefix],
			"category": "window-lifetime",
		},
		{
			"name": "constructed_window_mode",
			"path": "res://scripts/testing/mutation.gd",
			"source": "DisplayServer.call(\"%s\" + \"%s\" + \"mode\", 0)" % [
				window_prefix, setter_prefix],
			"category": "window-lifetime",
		},
		{
			"name": "window_position_property",
			"path": "res://tools/mutation.gd",
			"source": "%s.position = Vector2i.ZERO" % window_type_receiver,
			"category": "window-lifetime",
		},
		{
			"name": "window_position_setter",
			"path": "res://tools/mutation.gd",
			"source": "get_window().set_%s(Vector2i.ZERO)" % "".join(["pos", "ition"]),
			"category": "window-lifetime",
		},
		{
			"name": "window_position_dynamic",
			"path": "res://tools/mutation.gd",
			"source": "get_window().call(\"set_%s\", Vector2i.ZERO)" % "".join(["pos", "ition"]),
			"category": "window-lifetime",
		},
		{
			"name": "typed_window_position",
			"path": "res://tools/mutation.gd",
			"source": "var surface: %s = get_window()\nsurface.position = Vector2i.ZERO" % window_type_receiver,
			"category": "window-lifetime",
		},
		{
			"name": "inferred_window_position",
			"path": "res://tools/mutation.gd",
			"source": "var %s := %s()\n%s.position = Vector2i.ZERO" % [
				window_alias_receiver, window_getter, window_alias_receiver],
			"category": "window-lifetime",
		},
		{
			"name": "csharp_inferred_window_position",
			"path": "res://tests/mutation.cs",
			"source": "var %s = %s();\n%s.SetPosition(Vector2I.Zero);" % [
				window_alias_receiver, csharp_window_getter, window_alias_receiver],
			"category": "window-lifetime",
		},
		{
			"name": "window_mode_property",
			"path": "res://tools/mutation.gd",
			"source": "%s.mode = Window.MODE_WINDOWED" % window_type_receiver,
			"category": "window-lifetime",
		},
		{
			"name": "window_mode_setter",
			"path": "res://tools/mutation.gd",
			"source": "_root_window.set_%s(Window.MODE_FULLSCREEN)" % "".join(["mo", "de"]),
			"category": "window-lifetime",
		},
		{
			"name": "window_mode_dynamic",
			"path": "res://tools/mutation.gd",
			"source": "get_tree().root.set(\"%s\", Window.MODE_FULLSCREEN)" % "".join(["mo", "de"]),
			"category": "window-lifetime",
		},
		{
			"name": "window_foreground_method",
			"path": "res://tools/mutation.gd",
			"source": "_root_window.%s()" % window_foreground_symbol,
			"category": "window-lifetime",
		},
		{
			"name": "window_foreground_dynamic",
			"path": "res://tools/mutation.gd",
			"source": "get_window().call(\"%s\")" % window_foreground_symbol,
			"category": "window-lifetime",
		},
	]
	for mutation_v in mutations:
		var mutation := mutation_v as Dictionary
		var violations := _cursor_policy_violations(
			str(mutation.get("source", "")), str(mutation.get("path", "")))
		var categories: Array[String] = []
		for violation_v in violations:
			categories.append(str((violation_v as Dictionary).get("category", "")))
		_checks += 1
		if not categories.has(str(mutation.get("category", ""))):
			_fail(str(mutation.get("path", "")), "<mutation>", 1,
				"cursor-policy-mutation-escaped",
				"cursor/window isolation must reject every direct, spaced, dynamic, and alternate-receiver mutation",
				str(mutation.get("name", "")))

	var safe_source := "".join([
		"var motion := InputEventMouseMotion.new()", "\n",
		"Input.parse_input_event(motion)",
	])
	_checks += 1
	if not _cursor_policy_violations(
			safe_source, "res://tools/app_local_fixture.gd").is_empty():
		_fail("res://tools/app_local_fixture.gd", "<mutation>", 1,
			"cursor-policy-safe-fixture-rejected",
			"app-local Godot pointer injection must remain allowed", "")

	var allowed_park := "DisplayServer.%s(Vector2i(20000, 20000))" \
		% window_position_symbol
	_checks += 1
	if not _cursor_policy_violations(
			allowed_park, "res://tools/offscreen_window.gd").is_empty():
		_fail("res://tools/offscreen_window.gd", "<mutation>", 1,
			"offscreen-window-allowlist-rejected",
			"the single tracked offscreen park helper must retain window-position authority", "")

	var ordinary_character_position := "character.position = Vector3.ZERO"
	_checks += 1
	if not _cursor_policy_violations(
			ordinary_character_position, "res://scripts/testing/safe_character.gd").is_empty():
		_fail("res://scripts/testing/safe_character.gd", "<mutation>", 1,
			"window-policy-safe-fixture-rejected",
			"ordinary character transforms must not be confused with Window.position", "")

	var ordinary_character_setter := "character.set_position(Vector3.ZERO)"
	_checks += 1
	if not _cursor_policy_violations(
			ordinary_character_setter, "res://scripts/testing/safe_character.gd").is_empty():
		_fail("res://scripts/testing/safe_character.gd", "<mutation>", 1,
			"window-policy-safe-fixture-rejected",
			"ordinary character position setters must not be confused with Window.set_position", "")


## Mutation vectors for the two release-critical Basin loopholes. Splitting a forbidden method
## across string literals must not evade the curated root contract, while the approved screen-space
## method must not be confused with its world-addressed sibling.
func _verify_constructed_evidence_method_mutation_fixtures() -> void:
	var constructed_advance := \
		"var method = \"headless_\" + \"advance\"\nhost.call(method, 0.1)"
	var constructed_world_rally := \
		"var method = \"ral\" + \"ly\"\nCallable(driver, method).call(target)"
	var constructed_screen_rally := \
		"var method = \"rally_\" + \"screen\"\ndriver.call(method, point)"
	for fixture_v in [
		{
			"name": "constructed-headless-advance",
			"source": constructed_advance,
			"compact": "headlessadvance",
			"expected": true,
		},
		{
			"name": "constructed-world-rally",
			"source": constructed_world_rally,
			"compact": "rally",
			"expected": true,
		},
		{
			"name": "constructed-screen-rally-safe",
			"source": constructed_screen_rally,
			"compact": "rally",
			"expected": false,
		},
	]:
		var fixture := fixture_v as Dictionary
		_checks += 1
		var detected := _contains_constructed_identifier_exact(
			str(fixture.get("source", "")), str(fixture.get("compact", "")))
		if detected != bool(fixture.get("expected", false)):
			_fail("res://tools/verify_agent_player_input_boundary.gd", "<mutation>", 1,
				"constructed-evidence-method-mutation-mismatch",
				"constructed forbidden methods must fail without rejecting rally_screen",
				str(fixture.get("name", "")))


func _cursor_policy_violations(source: String, source_path: String) -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	var source_lower := source.to_lower()
	var identifier_compact_source := source_lower.replace("_", "")
	var pointer_warp_symbol := "".join(["warp", "_", "mouse"])
	if identifier_compact_source.contains(pointer_warp_symbol.replace("_", "")) \
			or _contains_constructed_cursor_warp(source):
		violations.append({
			"category": "os-cursor-warp",
			"token": pointer_warp_symbol,
			"message": "source may not name or dynamically dispatch a workstation cursor-warp API",
		})

	if _is_automated_input_source(source_path):
		for token in _automated_os_pointer_symbols():
			if source_lower.contains(token.to_lower()):
				violations.append({
					"category": "automated-os-pointer",
					"token": token,
					"message": "automated input must inject app-local events and may not capture, confine, or drive the OS pointer",
				})

	if _normalized_source_path(source_path) != "res://tools/offscreen_window.gd":
		for token in _window_lifetime_symbols():
			var compact_token := token.to_lower().replace("_", "")
			if identifier_compact_source.contains(compact_token) \
					or _contains_constructed_identifier(source, compact_token):
				violations.append({
					"category": "window-lifetime",
					"token": token,
					"message": "only the tracked offscreen helper may reposition, foreground, or change native window mode",
				})
		for alternative in _window_member_alternative_violations(source):
			violations.append(alternative)
	return violations


func _contains_constructed_cursor_warp(source: String) -> bool:
	return _contains_constructed_identifier(
		source, "".join(["warp", "mouse"]))


func _contains_constructed_identifier(source: String, forbidden_compact: String) -> bool:
	var matcher := RegEx.new()
	var pattern := "(?is)(?:&?[\"'][A-Za-z0-9_]+[\"']\\s*\\+\\s*)+&?[\"'][A-Za-z0-9_]+[\"']"
	if matcher.compile(pattern) != OK:
		return false
	for match_result in matcher.search_all(source):
		var compact := ""
		var value := match_result.get_string().to_lower()
		for index in range(value.length()):
			var codepoint := value.unicode_at(index)
			if (codepoint >= 48 and codepoint <= 57) \
					or (codepoint >= 97 and codepoint <= 122):
				compact += String.chr(codepoint)
		if compact.contains(forbidden_compact.to_lower()):
			return true
	return false


func _contains_constructed_identifier_exact(
		source: String, forbidden_compact: String
	) -> bool:
	var matcher := RegEx.new()
	var pattern := "(?is)(?:&?[\"'][A-Za-z0-9_]+[\"']\\s*\\+\\s*)+&?[\"'][A-Za-z0-9_]+[\"']"
	if matcher.compile(pattern) != OK:
		return false
	for match_result in matcher.search_all(source):
		var compact := ""
		var value := match_result.get_string().to_lower()
		for index in range(value.length()):
			var codepoint := value.unicode_at(index)
			if (codepoint >= 48 and codepoint <= 57) \
					or (codepoint >= 97 and codepoint <= 122):
				compact += String.chr(codepoint)
		if compact == forbidden_compact.to_lower():
			return true
	return false


func _window_member_alternative_violations(source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var typed_identifiers: Array[String] = []
	var typed_matcher := RegEx.new()
	var typed_pattern := "(?im)(?:\\bvar\\s+)?(?<gd>[A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*Window\\b|\\bWindow\\s+(?<cs>[A-Za-z_][A-Za-z0-9_]*)\\b"
	if typed_matcher.compile(typed_pattern) == OK:
		for match_result in typed_matcher.search_all(source):
			var identifier := match_result.get_string("gd")
			if identifier == "":
				identifier = match_result.get_string("cs")
			if identifier != "" and not typed_identifiers.has(identifier):
				typed_identifiers.append(identifier)
	var alias_matcher := RegEx.new()
	var alias_pattern := "(?im)^[ \\t]*(?:@onready[ \\t]+)?(?:var[ \\t]+)?(?<alias>[A-Za-z_][A-Za-z0-9_]*)[ \\t]*(?::=|=)[ \\t]*(?:(?:get_?window|window)[ \\t]*\\([ \\t]*\\)|get_viewport[ \\t]*\\([ \\t]*\\)[ \\t]*\\.[ \\t]*get_?window[ \\t]*\\([ \\t]*\\)|get_tree[ \\t]*\\([ \\t]*\\)[ \\t]*\\.[ \\t]*root)[ \\t]*;?[ \\t]*(?:(?:#|//).*)?$"
	if alias_matcher.compile(alias_pattern) == OK:
		for match_result in alias_matcher.search_all(source):
			var identifier := match_result.get_string("alias")
			if identifier != "" and not typed_identifiers.has(identifier):
				typed_identifiers.append(identifier)
	var typed_receiver_suffix := ""
	if not typed_identifiers.is_empty():
		typed_receiver_suffix = "|\\b(?:%s)\\b" % "|".join(typed_identifiers)
	var receiver := "(?:\\bWindow\\b|\\b(?:get_?window|window)\\s*\\(\\s*\\)|\\bget_viewport\\s*\\(\\s*\\)\\s*\\.\\s*get_?window\\s*\\(\\s*\\)|\\bget_tree\\s*\\(\\s*\\)\\s*\\.\\s*root|\\b[A-Za-z_][A-Za-z0-9_]*window[A-Za-z0-9_]*%s)" % typed_receiver_suffix
	for alternative in [
		{"token": "Window.position", "suffix": "position\\s*="},
		{"token": "Window.position", "suffix": "set_?position\\s*\\("},
		{"token": "Window.position", "suffix": "(?:set|set_deferred|call)\\s*\\(\\s*(?:StringName\\s*\\(\\s*)?&?[\"'](?:set_?)?position[\"']"},
		{"token": "Window.mode", "suffix": "mode\\s*="},
		{"token": "Window.mode", "suffix": "set_?mode\\s*\\("},
		{"token": "Window.mode", "suffix": "(?:set|set_deferred|call)\\s*\\(\\s*(?:StringName\\s*\\(\\s*)?&?[\"'](?:set_?)?mode[\"']"},
		{"token": "Window.move_to_foreground", "suffix": "move_?to_?foreground\\s*\\("},
		{"token": "Window.move_to_foreground", "suffix": "call\\s*\\(\\s*(?:StringName\\s*\\(\\s*)?&?[\"']move_?to_?foreground[\"']"},
	]:
		var matcher := RegEx.new()
		if matcher.compile("(?im)" + receiver + "\\s*\\.\\s*" + str(alternative.suffix)) != OK \
				or matcher.search(source) == null:
			continue
		result.append({
			"category": "window-lifetime",
			"token": str(alternative.token),
			"message": "only the tracked offscreen helper may reposition, foreground, or change native window mode",
		})
	return result


func _automated_os_pointer_symbols() -> Array[String]:
	return [
		"".join(["set", "_", "mouse", "_", "mode"]),
		"".join(["mouse", "_", "set", "_", "mode"]),
		"".join(["MOUSE", "_", "MODE", "_", "CAPTURED"]),
		"".join(["MOUSE", "_", "MODE", "_", "CONFINED"]),
		"".join(["MOUSE", "_", "MODE", "_", "CONFINED", "_", "HIDDEN"]),
		"".join(["Mouse", "Mode", "Enum", ".", "Captured"]),
		"".join(["Mouse", "Mode", "Enum", ".", "Confined"]),
		"".join(["Mouse", "Mode", "Enum", ".", "Confined", "Hidden"]),
		"".join(["Set", "Cursor", "Pos"]),
		"".join(["Set", "Physical", "Cursor", "Pos"]),
		"".join(["Clip", "Cursor"]),
		"".join(["Set", "Capture"]),
		"".join(["Release", "Capture"]),
		"".join(["Send", "Input"]),
		"".join(["mouse", "_", "event"]),
		"".join(["CG", "Warp", "Mouse", "Cursor", "Position"]),
		"".join(["CG", "Associate", "Mouse", "And", "Mouse", "Cursor", "Position"]),
		"".join(["X", "Warp", "Pointer"]),
		"".join(["X", "Grab", "Pointer"]),
		"".join(["SDL", "_", "Warp", "Mouse"]),
		"".join(["SDL", "_", "Set", "Relative", "Mouse", "Mode"]),
		"".join(["SDL", "_", "Capture", "Mouse"]),
		"".join(["glfw", "Set", "Cursor", "Pos"]),
		"".join(["GLFW", "_", "CURSOR", "_", "DISABLED"]),
		"".join(["GLFW", "_", "CURSOR", "_", "CAPTURED"]),
		"".join(["Cursor", ".", "Position"]),
		"".join(["Cursor", "]::", "Position"]),
		"".join(["pya", "utogui"]),
		"".join(["Auto", "It"]),
		"".join(["pyn", "put"]),
		"".join(["robot", "js"]),
	]


func _window_lifetime_symbols() -> Array[String]:
	return [
		"".join(["window", "_", "set", "_", "position"]),
		"".join(["window", "_", "move", "_", "to", "_", "foreground"]),
		"".join(["window", "_", "set", "_", "mode"]),
	]


func _is_automated_input_source(source_path: String) -> bool:
	var normalized := _normalized_source_path(source_path)
	if normalized.begins_with("res://tools/") \
			or normalized.begins_with("res://tests/") \
			or normalized.begins_with("res://scripts/testing/"):
		return true
	return normalized in [
		"res://scripts/test_runner_cli.gd",
		"res://scripts/test_bootstrap.gd",
		"res://scripts/generation/stretch_generation_playtest_loop.gd",
		"res://scripts/fragments/preview_web_e2e_controller.gd",
		"res://scripts/system/playthrough_session.gd",
	]


func _normalized_source_path(source_path: String) -> String:
	return source_path.replace("\\", "/").to_lower()


func _collect_executable_test_source_paths(
		directory_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_fail(directory_path, "<directory>", 0, "cursor-warp-scan-unavailable",
			"could not enumerate executable/test sources for cursor/window isolation", "")
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if directory.current_is_dir():
			if entry not in [".", "..", ".godot", "Godot", "node_modules", "build"]:
				_collect_executable_test_source_paths(
					directory_path.path_join(entry), result)
		elif _is_executable_test_source(entry):
			result.append(directory_path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()


func _is_executable_test_source(file_name: String) -> bool:
	var extension := file_name.get_extension().to_lower()
	return extension in [
		"gd", "cs", "c", "cc", "cpp", "h", "hh", "hpp", "py",
		"ps1", "bat", "cmd", "sh", "js", "mjs", "ts",
	]


func _test_player_discovery_watchdog_contract() -> void:
	var loop = WATCHDOG_LOOP_SCRIPT.new()
	var started_usec := Time.get_ticks_usec()
	var watchdog_v: Variant = loop.call("_new_player_discovery_watchdog", {
		"player_discovery_path_wall_seconds": 1.0,
		"player_discovery_global_started_usec": started_usec,
		"player_discovery_global_deadline_usec": started_usec + 5000000,
		"player_discovery_global_wall_seconds": 5.0,
		"player_discovery_visible_progress_seconds": 0.12,
		"player_discovery_rally_start_seconds": 0.12,
		"player_discovery_rally_incomplete_stable_seconds": 0.12,
	}, "bounded_watchdog_fixture")
	_watchdog_runtime_assert(watchdog_v is Dictionary,
		"watchdog-constructs", "watchdog helper returns a dictionary")
	if not (watchdog_v is Dictionary):
		return
	var watchdog := watchdog_v as Dictionary
	var report := {
		"path_id": "bounded_watchdog_fixture",
		"visible_decisions": [],
		"decision_trace_records": [],
		"decision_trace_failures": [],
		"decision_trace_chain_tail": "",
		"decision_trace_complete": false,
		"watchdog_contract": {},
		"watchdog_heartbeats": [],
		"watchdog_failures": [],
		"watchdog_input_release": {},
		"interaction_failures": [],
		"atomic_rally_failures": [],
		"decision_count": 0,
	}
	loop.call("_initialize_generated_strategy_trace", report, {
		"spec_id": "bounded_watchdog_fixture",
		"spec": {
			"id": "bounded_watchdog_fixture",
			"source": {"seed": 17},
		},
	}, "bounded_watchdog_fixture", "bounded_fixture", "watchdog_baseline")
	loop.call("_emit_player_discovery_heartbeat",
		report, watchdog, 0, "initial_observation")
	var initial_contract_v: Variant = loop.call(
		"_player_discovery_watchdog_report", watchdog)
	var initial_contract := initial_contract_v as Dictionary \
		if initial_contract_v is Dictionary else {}
	_watchdog_runtime_assert(int(initial_contract.get(
		"progress_event_count", -1)) == 0,
		"baseline-is-not-progress",
		"initial observation/liveness metadata does not manufacture causal progress")
	var initial_heartbeats := report.get("watchdog_heartbeats", []) as Array
	var first_heartbeat := initial_heartbeats[0] as Dictionary \
		if not initial_heartbeats.is_empty() \
			and initial_heartbeats[0] is Dictionary else {}
	_watchdog_runtime_assert(not first_heartbeat.is_empty()
		and first_heartbeat.has("seconds_since_visible_progress")
		and first_heartbeat.has("last_visible_progress_kind"),
		"heartbeat-exposes-progress-age",
		"heartbeat artifact carries progress age and kind without advancing it")

	var wait_started_usec := Time.get_ticks_usec()
	# The watchdog is intentionally wall-clock based. A SceneTreeTimer follows
	# engine/game time and can run faster than wall time in a headless verifier.
	OS.delay_msec(160)
	var abort_reason := str(loop.call(
		"_player_discovery_watchdog_abort_reason", watchdog))
	var detection_elapsed := float(
		Time.get_ticks_usec() - wait_started_usec) / 1000000.0
	_watchdog_runtime_assert(
		abort_reason == "player_visible_causal_progress_stalled",
		"visible-progress-stall-aborts",
		"low-bound watchdog aborts when no validated rendered delta occurs")
	_watchdog_runtime_assert(detection_elapsed >= 0.12 and detection_elapsed < 0.75,
		"visible-progress-stall-is-bounded",
		"low-bound stall is detected within a deterministic sub-second bound")

	var global_watchdog_v: Variant = loop.call(
		"_new_player_discovery_watchdog", {
			"player_discovery_path_wall_seconds": 1.0,
			"player_discovery_global_deadline_usec": Time.get_ticks_usec() - 1,
			"player_discovery_visible_progress_seconds": 30.0,
		}, "expired_global_fixture")
	var global_watchdog := global_watchdog_v as Dictionary \
		if global_watchdog_v is Dictionary else {}
	_watchdog_runtime_assert(str(loop.call(
		"_player_discovery_watchdog_abort_reason", global_watchdog)) \
			== "global_player_discovery_wall_deadline",
		"global-deadline-aborts",
		"one monotonic global deadline bounds the multi-path run")
	var path_watchdog_v: Variant = loop.call(
		"_new_player_discovery_watchdog", {
			"player_discovery_path_wall_seconds": 1.0,
			"player_discovery_global_deadline_usec": Time.get_ticks_usec() + 5000000,
			"player_discovery_visible_progress_seconds": 30.0,
		}, "expired_path_fixture")
	var path_watchdog := path_watchdog_v as Dictionary \
		if path_watchdog_v is Dictionary else {}
	path_watchdog["path_deadline_usec"] = Time.get_ticks_usec() - 1
	_watchdog_runtime_assert(str(loop.call(
		"_player_discovery_watchdog_abort_reason", path_watchdog)) \
			== "path_player_discovery_wall_deadline",
		"path-deadline-aborts",
		"each visible player path retains its own monotonic deadline")

	var driver: Node = WATCHDOG_INPUT_DRIVER_SCRIPT.new()
	root.add_child(driver)
	driver.set("_held_keys", {
		KEY_W: {"ctrl": false, "shift": false},
	})
	driver.set("_held_mouse_buttons", {MOUSE_BUTTON_RIGHT: true})
	driver.set("_last_pointer", Vector2(4.0, 4.0))
	var abort_started_usec := Time.get_ticks_usec()
	await loop.call("_abort_player_discovery_for_watchdog",
		driver, report, watchdog, abort_reason)
	var abort_elapsed := float(
		Time.get_ticks_usec() - abort_started_usec) / 1000000.0
	var release := report.get("watchdog_input_release", {}) as Dictionary
	_watchdog_runtime_assert(bool(release.get("all_inputs_released", false))
		and (release.get("released_keys", []) as Array).has(KEY_W)
		and (release.get("released_mouse_buttons", []) as Array).has(
			MOUSE_BUTTON_RIGHT)
		and (driver.get("_held_keys") as Dictionary).is_empty()
		and (driver.get("_held_mouse_buttons") as Dictionary).is_empty(),
		"watchdog-releases-held-input",
		"abort emits real release edges and clears tracked held input")
	_watchdog_runtime_assert(abort_elapsed < 0.75,
		"watchdog-cleanup-is-bounded",
		"input cleanup and failed-report sealing complete within a sub-second bound")
	_watchdog_runtime_assert(
		(report.get("watchdog_failures", []) as Array).size() == 1
		and (report.get("interaction_failures", []) as Array).size() == 1
		and bool((report.get("watchdog_contract", {}) as Dictionary).get(
			"aborted", false)),
		"watchdog-failure-precedes-summary",
		"abort failure is present in report evidence before trace finalization")

	loop.call("_finish_generated_strategy_trace", report, false)
	var records := report.get("decision_trace_records", []) as Array
	var expected_previous := ""
	var hash_chain_valid := records.size() >= 2
	for record_v in records:
		if not (record_v is Dictionary):
			hash_chain_valid = false
			continue
		var record := record_v as Dictionary
		var payload := record.duplicate(true)
		var actual_hash := str(payload.get("record_hash", ""))
		payload.erase("record_hash")
		hash_chain_valid = hash_chain_valid \
			and str(record.get("previous_hash", "")) == expected_previous \
			and actual_hash == WATCHDOG_TRACE_SCRIPT.canonical_hash(payload)
		expected_previous = actual_hash
	var summary_record := records.back() as Dictionary \
		if not records.is_empty() and records.back() is Dictionary else {}
	var summary := summary_record.get("summary", {}) as Dictionary
	_watchdog_runtime_assert(hash_chain_valid,
		"watchdog-summary-hash-chain",
		"run and failed summary retain a valid previous_hash/record_hash chain")
	_watchdog_runtime_assert(
		str(summary_record.get("record_type", "")) \
			== str(WATCHDOG_TRACE_SCRIPT.SUMMARY_RECORD)
		and not bool(summary.get("trace_complete", true))
		and (summary.get("completion_reasons", []) as Array).has(
			"ci_watchdog_abort")
		and (summary.get("watchdog_abort_reasons", []) as Array).has(
			abort_reason)
		and not bool(report.get("decision_trace_complete", true)),
		"watchdog-summary-is-hash-covered-failure",
		"timeout reason is inside the hash-covered incomplete summary")
	driver.queue_free()
	await process_frame


func _watchdog_runtime_assert(
		condition: bool, rule: String, detail: String) -> void:
	_checks += 1
	if not condition:
		_fail("res://tools/verify_agent_player_input_boundary.gd",
			"<watchdog-runtime>", 0, rule, detail, "")


## Optional diagnostic for reviewing the conservative presentation predicate
## across every configured preview. It is intentionally not part of the fast
## static gate; run it explicitly after tightening material visibility rules.
func _scan_outline_observation_materials() -> void:
	var findings: Array[Dictionary] = []
	var preview_count := 0
	for entry_v in MATERIAL_SCAN_PREVIEW_SCRIPT.PREVIEW_ENTRIES:
		if not (entry_v is Dictionary):
			continue
		var entry := entry_v as Dictionary
		var entry_id := str(entry.get("id", ""))
		var chunk_id := str(entry.get("chunk", entry_id))
		if entry_id == "" or chunk_id == "":
			continue
		var preview := MATERIAL_SCAN_PREVIEW_SCENE.instantiate()
		if preview == null:
			print("[OUTLINE_MATERIAL_SCAN/BOOT_FAIL] %s" % entry_id)
			continue
		preview.set("preview_menu", false)
		preview.set("preview_chunk", chunk_id)
		var config_v: Variant = entry.get("config", {})
		if config_v is Dictionary and not (config_v as Dictionary).is_empty():
			preview.set("preview_chunk_config", (config_v as Dictionary).duplicate(true))
		root.add_child(preview)
		for _settle in range(8):
			await process_frame
		preview_count += 1
		for target_v in get_nodes_in_group(&"player_observation_presenters"):
			if not (target_v is Node) or not preview.is_ancestor_of(target_v as Node) \
					or not (target_v as Node).has_method("get_highlight_meshes"):
				continue
			var target := target_v as Node
			var meshes_v: Variant = target.call("get_highlight_meshes")
			if not (meshes_v is Array) or (meshes_v as Array).is_empty():
				continue
			var rejected_base: Array[Dictionary] = []
			var has_conservative_surface := false
			for mesh_v in meshes_v as Array:
				if not (mesh_v is MeshInstance3D) or not is_instance_valid(mesh_v):
					continue
				var mesh := mesh_v as MeshInstance3D
				var materials: Array[Material] = []
				if mesh.material_override != null:
					materials.append(mesh.material_override)
				elif mesh.mesh != null:
					for surface_index in range(mesh.mesh.get_surface_count()):
						var material := mesh.get_active_material(surface_index)
						if material != null:
							materials.append(material)
				if materials.is_empty():
					has_conservative_surface = true
					continue
				for material in materials:
					if material is BaseMaterial3D:
						var base := material as BaseMaterial3D
						var reasons: Array[String] = []
						if base.albedo_color.a <= 0.01:
							reasons.append("zero_albedo_alpha")
						if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
							reasons.append("transparency_enabled")
						if base.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
							reasons.append("distance_fade_enabled")
						if base.proximity_fade_enabled:
							reasons.append("proximity_fade_enabled")
						if reasons.is_empty():
							has_conservative_surface = true
						else:
							rejected_base.append({
								"mesh": str(mesh.get_path()),
								"reasons": reasons,
							})
			if not rejected_base.is_empty() and not has_conservative_surface:
				findings.append({
					"preview": entry_id,
					"target": str(target.get_path()),
					"rejected_base_materials": rejected_base,
				})
		preview.queue_free()
		await process_frame
	print("OUTLINE OBSERVATION MATERIAL SCAN: %d previews, %d findings" % [
		preview_count, findings.size()])
	for finding in findings:
		print("[OUTLINE_MATERIAL_SCAN/FINDING] %s" % JSON.stringify(finding))

func _audit(audit: Dictionary) -> void:
	_called_cache.clear()
	var path := str(audit.get("path", ""))
	if not FileAccess.file_exists(path):
		_fail(path, "<file>", 0, "missing-audit-target", "required evidence source does not exist", "")
		return
	var source := FileAccess.get_file_as_string(path)
	if source == "":
		_fail(path, "<file>", 0, "unreadable-audit-target", "required evidence source is empty or unreadable", "")
		return
	var parsed := _parse_functions(source)
	var functions: Dictionary = parsed.get("functions", {})
	var owners: Dictionary = parsed.get("owners", {})
	var evidence := {}
	for root_v in audit.get("roots", []):
		var root_name := str(root_v)
		_checks += 1
		if not functions.has(root_name):
			_fail(path, root_name, 0, "missing-evidence-root", "curated entry point is missing; update this verifier with its replacement", "")
			continue
		for reachable in _reachable(root_name, functions):
			evidence[reachable] = true
	var fixtures := {}
	for fixture_v in audit.get("fixture_only", []):
		var fixture_name := str(fixture_v)
		fixtures[fixture_name] = true
		_checks += 1
		if not functions.has(fixture_name):
			_fail(path, fixture_name, 0, "missing-fixture-quarantine", "declared fixture-only helper is missing", "")
	var diagnostics := {}
	for diagnostic_v in audit.get("diagnostic_only", []):
		var diagnostic_name := str(diagnostic_v)
		diagnostics[diagnostic_name] = true
		_checks += 1
		if not functions.has(diagnostic_name):
			_fail(path, diagnostic_name, 0, "missing-diagnostic-quarantine",
				"declared diagnostic-only entry point is missing", "")
		elif evidence.has(diagnostic_name):
			var diagnostic_function: Dictionary = functions[diagnostic_name]
			_fail(path, diagnostic_name, int(diagnostic_function.get("line", 0)),
				"diagnostic-reachable-from-evidence",
				"legacy hidden/headless diagnostic is reachable from an approval-evidence root",
				str(diagnostic_function.get("signature", "")))
	var receipt_only := {}
	for receipt_v in audit.get("receipt_only", []):
		var receipt_name := str(receipt_v)
		receipt_only[receipt_name] = true
		_checks += 1
		if not functions.has(receipt_name):
			_fail(path, receipt_name, 0, "missing-receipt-quarantine",
				"declared receipt-only helper is missing", "")
	var baseline_token := str(audit.get("baseline_token", ""))
	if baseline_token != "":
		_verify_fixture_baseline(path, audit, functions, fixtures, baseline_token)

	var input_backed := _capability(functions, false)
	var rally_backed := _capability(functions, true)
	for required_v in audit.get("input_required", []):
		var required := str(required_v)
		if not functions.has(required) or not evidence.has(required):
			continue # Deleting an obsolete helper is a valid repair.
		_checks += 1
		if not bool(input_backed.get(required, false)):
			var function: Dictionary = functions[required]
			_fail(path, required, int(function.get("line", 0)), "no-player-input-boundary", "action reaches neither a central player-input driver nor raw shipped Input events", str(function.get("signature", "")))

	var must_rally := {}
	for required_v in audit.get("rally_required", []):
		var required := str(required_v)
		if functions.has(required) and evidence.has(required):
			must_rally[required] = true
	for name_v in evidence.keys():
		var name := str(name_v)
		if fixtures.has(name) or diagnostics.has(name):
			continue
		var function: Dictionary = functions.get(name, {})
		_scan_function(path, name, function, audit, receipt_only.has(name))
		var group_line := _group_decomposition_line(name, function)
		if group_line > 0:
			must_rally[name] = true
			var record := _line_record(function, group_line)
			_fail(path, name, group_line, "group-move-decomposition", "one whole-party decision is decomposed into singleton moves; issue exactly one Rally gesture", str(record.get("raw", "")).strip_edges())
	for name_v in must_rally.keys():
		var name := str(name_v)
		_checks += 1
		if not bool(rally_backed.get(name, false)):
			var function: Dictionary = functions.get(name, {})
			_fail(path, name, int(function.get("line", 0)), "missing-atomic-rally", "group intent must use one real held-RMB Rally; Ctrl/portrait multi-select and singleton move bursts do not count", str(function.get("signature", "")))
	_verify_forbidden_function_tokens(path, audit, functions)
	_verify_forbidden_constructed_function_identifiers(path, audit, functions)
	_verify_required_function_tokens(path, audit, functions)
	_verify_guards_before_emit(path, audit, functions)
	_verify_observation_before_input(path, audit, functions)
	_verify_evidence_contracts(path, audit, functions)
	_verify_conservative_shader_material_rejection(path, audit, functions)
	_verify_ordered_after_anchor(path, audit, functions)
	_verify_forbidden_presentation_code_tokens(path, audit, functions, evidence)
	if bool(audit.get("watchdog_contract", false)):
		_verify_player_discovery_watchdog_static_contract(
			path, functions, parsed)

	# Prefix constants live outside functions, but taint the dedicated approval/pilot files.
	if path.ends_with("stretch_generation_playtest_loop.gd") or path.ends_with("generated_input_playthrough_driver.gd"):
		for line_v in parsed.get("lines", []):
			var line: Dictionary = line_v
			var number := int(line.get("line", 0))
			var search := str(line.get("search", ""))
			var stripped := search.strip_edges()
			var quarantined_diagnostic := path.ends_with("stretch_generation_playtest_loop.gd") \
				and stripped.begins_with("const DIAGNOSTIC_")
			if search.contains("qa_") and str(owners.get(number, "")) == "" \
					and not quarantined_diagnostic:
				_fail(path, "<global>", number, "hidden-semantic-input", "qa_* target-addressed actions bypass visible picking and are not player evidence", str(line.get("raw", "")).strip_edges())
	print("[AGENT_INPUT_BOUNDARY] audited %s: %d reachable functions" % [str(audit.get("label", path)), evidence.size()])

func _verify_fixture_baseline(path: String, audit: Dictionary, functions: Dictionary,
		fixtures: Dictionary, baseline_token: String) -> void:
	for root_v in audit.get("roots", []):
		var root_name := str(root_v)
		if not functions.has(root_name):
			continue
		var root: Dictionary = functions[root_name]
		var baseline_line := 0
		var fixture_calls := {}
		for fixture_name_v in fixtures.keys():
			fixture_calls[str(fixture_name_v)] = 0
		for line_v in root.get("lines", []):
			var line: Dictionary = line_v
			var search := str(line.get("search", ""))
			var number := int(line.get("line", 0))
			if baseline_line == 0 and search.contains(baseline_token):
				baseline_line = number
			for fixture_name_v in fixtures.keys():
				var fixture_name := str(fixture_name_v)
				if int(fixture_calls[fixture_name]) == 0 and search.contains(fixture_name + "("):
					fixture_calls[fixture_name] = number
		for fixture_name_v in fixture_calls.keys():
			var fixture_name := str(fixture_name_v)
			var call_line := int(fixture_calls[fixture_name])
			if call_line == 0:
				continue
			_checks += 1
			if baseline_line == 0 or baseline_line <= call_line:
				_fail(path, root_name, call_line, "fixture-baseline-missing",
					"fixture setup must be followed by a fresh evidence baseline before player actions",
					str((functions[root_name] as Dictionary).get("signature", "")))

func _verify_forbidden_function_tokens(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	var contracts_v: Variant = audit.get("forbidden_by_function", {})
	if not (contracts_v is Dictionary):
		return
	for function_name_v in (contracts_v as Dictionary).keys():
		var function_name := str(function_name_v)
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-observation-contract-function",
				"observation candidate helper is missing; update the verifier for its replacement", "")
			continue
		var forbidden_v: Variant = (contracts_v as Dictionary).get(function_name, {})
		if not (forbidden_v is Dictionary):
			continue
		var function: Dictionary = functions[function_name]
		for line_v in function.get("lines", []):
			var line := line_v as Dictionary
			var search := str(line.get("search", ""))
			for token_v in (forbidden_v as Dictionary).keys():
				var token := str(token_v)
				if not search.contains(token):
					continue
				_fail(path, function_name, int(line.get("line", 0)),
					"hidden-observation-seed", str((forbidden_v as Dictionary)[token]),
					str(line.get("raw", "")).strip_edges())


func _verify_forbidden_constructed_function_identifiers(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	var contracts_v: Variant = audit.get(
		"forbidden_constructed_by_function", {})
	if not (contracts_v is Dictionary):
		return
	for function_name_v in (contracts_v as Dictionary).keys():
		var function_name := str(function_name_v)
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-constructed-method-contract-function",
				"constructed-method guard names a missing evidence function", "")
			continue
		var forbidden_v: Variant = (contracts_v as Dictionary).get(
			function_name, {})
		if not (forbidden_v is Dictionary):
			continue
		var function: Dictionary = functions[function_name]
		var raw_lines: Array[String] = [str(function.get("signature", ""))]
		for line_v in function.get("lines", []):
			raw_lines.append(str((line_v as Dictionary).get("raw", "")))
		var raw_source := "\n".join(raw_lines)
		for compact_v in (forbidden_v as Dictionary).keys():
			var compact := str(compact_v)
			_checks += 1
			if not _contains_constructed_identifier_exact(raw_source, compact):
				continue
			_fail(path, function_name, int(function.get("line", 0)),
				"constructed-direct-state-action",
				str((forbidden_v as Dictionary)[compact]),
				str(function.get("signature", "")))


func _verify_required_function_tokens(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	var contracts_v: Variant = audit.get("required_by_function", {})
	if not (contracts_v is Dictionary):
		return
	for function_name_v in (contracts_v as Dictionary).keys():
		var function_name := str(function_name_v)
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-presentation-contract-function",
				"required presentation-boundary helper is missing; update the verifier only if its replacement preserves the same dataflow", "")
			continue
		var contract_v: Variant = (contracts_v as Dictionary).get(function_name, {})
		if not (contract_v is Dictionary):
			continue
		var contract := contract_v as Dictionary
		var search := ""
		if bool(contract.get("reachable", false)):
			var reachable_search: Array[String] = []
			for reachable_name in _reachable(function_name, functions):
				reachable_search.append(_function_search(functions.get(reachable_name, {})))
			search = "\n".join(reachable_search)
		else:
			search = _function_search(functions[function_name])
		for group_v in contract.get("token_groups", []):
			if not (group_v is Array):
				continue
			var found := false
			for token_v in group_v as Array:
				if search.contains(str(token_v)):
					found = true
					break
			_checks += 1
			if not found:
				var function: Dictionary = functions[function_name]
				_fail(path, function_name, int(function.get("line", 0)),
					"missing-presentation-dataflow",
					"policy-visible data must remain on the registered presenter, screen-candidate, exact-pointer, and exact-source path",
					"missing one of %s" % str(group_v))


func _verify_guards_before_emit(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	for contract_v in audit.get("guards_before_emit", []):
		if not (contract_v is Dictionary):
			continue
		var contract := contract_v as Dictionary
		var function_name := str(contract.get("function", ""))
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-guarded-emission-function",
				"curated policy-visible emission function is missing; update the verifier for its replacement", "")
			continue
		var function: Dictionary = functions[function_name]
		var emit_line := _first_matching_line(function, contract.get("emit_tokens", []))
		_checks += 1
		if emit_line <= 0:
			_fail(path, function_name, int(function.get("line", 0)),
				"missing-policy-visible-emission",
				"curated affordance/cue emission disappeared; update the verifier for its replacement",
				str(function.get("signature", "")))
			continue
		for group_v in contract.get("guard_token_groups", []):
			if not (group_v is Array):
				continue
			var guard_line := _first_matching_line(function, group_v as Array)
			_checks += 1
			if guard_line <= 0 or guard_line >= emit_line:
				_fail(path, function_name, emit_line,
					"unguarded-policy-visible-emission",
					"screen candidates, exact pointer/source matching, and rendered-result validation must dominate the policy-visible emission",
					"guard %s; emit %s" % [str(group_v), _raw_line(function, emit_line)])


func _verify_observation_before_input(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	for contract_v in audit.get("observation_before_input", []):
		if not (contract_v is Dictionary):
			continue
		var contract := contract_v as Dictionary
		var function_name := str(contract.get("function", ""))
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-observation-order-function",
				"observation-before-input function is missing; update the verifier for its replacement", "")
			continue
		var function: Dictionary = functions[function_name]
		var observation_line := _first_matching_line(
			function, contract.get("observation_tokens", []))
		var input_line := _first_matching_line(function, contract.get("input_tokens", []))
		if observation_line <= 0:
			_fail(path, function_name, int(function.get("line", 0)),
				"missing-player-observation", "policy issues input without sampling player_observation_v1", str(function.get("signature", "")))
			continue
		if input_line <= 0:
			_fail(path, function_name, int(function.get("line", 0)),
				"missing-player-input", "curated policy function no longer exposes its shipped-input edge; update the verifier for a delegated replacement", str(function.get("signature", "")))
			continue
		if observation_line >= input_line:
			_fail(path, function_name, input_line, "input-before-observation",
				"the first shipped action occurs before the first player_observation_v1 sample", _raw_line(function, input_line))
		for group_v in contract.get("validation_token_groups", []):
			if not (group_v is Array):
				continue
			var validation_line := _first_matching_line(function, group_v as Array)
			_checks += 1
			if validation_line <= 0 or validation_line >= input_line:
				_fail(path, function_name, input_line, "input-before-observation-validation",
					"the first shipped action occurs before the observation schema/source is validated", _raw_line(function, input_line))


func _verify_evidence_contracts(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	for contract_v in audit.get("evidence_contracts", []):
		if not (contract_v is Dictionary):
			continue
		var contract := contract_v as Dictionary
		var function_name := str(contract.get("function", ""))
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-evidence-contract-function",
				"eligibility function is missing; update the verifier for its replacement", "")
			continue
		var function: Dictionary = functions[function_name]
		var search := _function_search(function)
		for anchor_v in contract.get("anchor_tokens", []):
			var anchor := str(anchor_v)
			_checks += 1
			if not search.contains(anchor):
				_fail(path, function_name, int(function.get("line", 0)),
					"missing-evidence-eligibility-anchor", "curated eligibility/status assignment disappeared; update the verifier for its replacement", str(function.get("signature", "")))
		for group_v in contract.get("required_token_groups", []):
			if not (group_v is Array):
				continue
			var found := false
			for token_v in group_v as Array:
				if search.contains(str(token_v)):
					found = true
					break
			_checks += 1
			if not found:
				_fail(path, function_name, int(function.get("line", 0)),
					"self-attested-evidence-eligibility",
					"eligibility must consume concrete observation/decision, visible movement, and visible outcome proof rather than provenance strings",
					"missing one of %s" % str(group_v))


func _verify_conservative_shader_material_rejection(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	for function_name_v in audit.get(
			"conservative_shader_material_rejection", []):
		var function_name := str(function_name_v)
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-shader-visibility-contract",
				"the conservative ShaderMaterial visibility boundary is missing", "")
			continue
		var function: Dictionary = functions[function_name]
		var shader_branch_line := 0
		var shader_branch_indent := -1
		var shader_rejected := false
		var body_indent := 1 << 20
		var body_fallback := ""
		for line_v in function.get("lines", []):
			var line := line_v as Dictionary
			var compact := str(line.get("code", "")).replace(" ", "").replace("\t", "")
			if compact != "":
				body_indent = mini(body_indent, int(line.get("indent", body_indent)))
		for line_v in function.get("lines", []):
			var line := line_v as Dictionary
			var compact := str(line.get("code", "")).replace(" ", "").replace("\t", "")
			if int(line.get("indent", -1)) == body_indent \
					and compact.begins_with("return"):
				body_fallback = compact
			if shader_branch_line == 0:
				if compact.contains("ifmaterialisShaderMaterial"):
					shader_branch_line = int(line.get("line", 0))
					shader_branch_indent = int(line.get("indent", -1))
					shader_rejected = compact.contains("returnfalse")
				continue
			if compact == "":
				continue
			var indent := int(line.get("indent", -1))
			if indent <= shader_branch_indent:
				break
			if compact.contains("returntrue"):
				shader_rejected = false
				break
			if compact.contains("returnfalse"):
				shader_rejected = true
		var fail_closed_fallback := body_fallback == "returnfalse"
		if not fail_closed_fallback \
				and (shader_branch_line == 0 or not shader_rejected):
			_fail(path, function_name, int(function.get("line", 0)),
				"unproven-shader-surface",
				("base policy affordances have no target-specific framebuffer proof; "
				+ "explicitly reject ShaderMaterial surfaces until such proof exists"),
				str(function.get("signature", "")))


func _verify_ordered_after_anchor(
		path: String, audit: Dictionary, functions: Dictionary) -> void:
	for contract_v in audit.get("ordered_after_anchor", []):
		if not (contract_v is Dictionary):
			continue
		var contract := contract_v as Dictionary
		var function_name := str(contract.get("function", ""))
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-ordered-contract-function",
				"ordered watchdog contract function is missing", "")
			continue
		var function := functions[function_name] as Dictionary
		var cursor := _first_matching_line(
			function, contract.get("anchor_tokens", []))
		_checks += 1
		if cursor <= 0:
			_fail(path, function_name, int(function.get("line", 0)),
				"missing-watchdog-order-anchor",
				"watchdog ordering anchor disappeared", str(contract.get(
					"anchor_tokens", [])))
			continue
		for group_v in contract.get("ordered_token_groups", []):
			if not (group_v is Array):
				continue
			var ordered_line := _first_matching_line_after(
				function, group_v as Array, cursor)
			_checks += 1
			if ordered_line <= 0:
				_fail(path, function_name, cursor,
					"watchdog-ordering-regression",
					"required watchdog step is missing or occurs before its predecessor",
					"after line %d require %s" % [cursor, str(group_v)])
				break
			cursor = ordered_line


func _verify_forbidden_presentation_code_tokens(
		path: String,
		audit: Dictionary,
		functions: Dictionary,
		evidence: Dictionary
	) -> void:
	var forbidden_v: Variant = audit.get("forbidden_presentation_code_tokens", {})
	if not (forbidden_v is Dictionary):
		return
	var forbidden := forbidden_v as Dictionary
	for name_v in evidence.keys():
		var function_name := str(name_v)
		var function_v: Variant = functions.get(function_name, {})
		if not (function_v is Dictionary):
			continue
		for line_v in (function_v as Dictionary).get("lines", []):
			var line := line_v as Dictionary
			var code := str(line.get("code", ""))
			for token_v in forbidden.keys():
				var token := str(token_v)
				_checks += 1
				if code.contains(token):
					_fail(path, function_name, int(line.get("line", 0)),
						"wall-clock-policy-leak", str(forbidden[token]),
						str(line.get("raw", "")).strip_edges())


func _verify_player_discovery_watchdog_static_contract(
		path: String, functions: Dictionary, parsed: Dictionary) -> void:
	var exact_decision_cap := false
	for line_v in parsed.get("lines", []):
		var raw := str((line_v as Dictionary).get("raw", "")).strip_edges()
		if raw == "const PLAYER_DISCOVERY_MAX_DECISIONS := 24":
			exact_decision_cap = true
			break
	_checks += 1
	if not exact_decision_cap:
		_fail(path, "<global>", 0, "unbounded-player-decision-count",
			"generated player discovery must retain the hard <=24 decision cap", "")

	# Only helpers that prove a rendered delta/result may advance causal progress.
	# In particular, the outer policy loop and heartbeat emitter may not reset the
	# timer merely because another iteration or baseline snapshot occurred.
	var allowed_progress_callers := {
		"_consider_player_discovery_observation_progress": true,
		"_drive_observed_rally": true,
		"_wait_for_observed_interaction_feedback": true,
		"_wait_for_player_rally_settle": true,
	}
	for function_name_v in functions.keys():
		var function_name := str(function_name_v)
		var function := functions[function_name] as Dictionary
		for line_v in function.get("lines", []):
			var line := line_v as Dictionary
			if not str(line.get("code", "")).contains(
					"_note_player_discovery_visible_progress("):
				continue
			_checks += 1
			if not allowed_progress_callers.has(function_name):
				_fail(path, function_name, int(line.get("line", 0)),
					"noncausal-watchdog-progress",
					"only validated rendered deltas/results may reset causal progress",
					str(line.get("raw", "")).strip_edges())

	var progress_guards := [
		{
			"function": "_consider_player_discovery_observation_progress",
			"guards": [
				["validate_player_observation("],
				["_player_observation_action_progress_signature("],
			],
		},
		{
			"function": "_wait_for_observed_interaction_feedback",
			"guards": [
				["baseline_presentation_serial"],
				["source_token"],
				["bool(target_result.get(\"visible\""],
			],
		},
		{
			"function": "_wait_for_player_rally_settle",
			"guards": [["if motion == last_motion"], ["else:"]],
		},
	]
	for guard_contract_v in progress_guards:
		var guard_contract := guard_contract_v as Dictionary
		var function_name := str(guard_contract.get("function", ""))
		_checks += 1
		if not functions.has(function_name):
			_fail(path, function_name, 0, "missing-progress-proof-function",
				"curated visible-progress proof helper is missing", "")
			continue
		var function := functions[function_name] as Dictionary
		var note_line := _first_matching_line(
			function, ["_note_player_discovery_visible_progress("])
		_checks += 1
		if note_line <= 0:
			_fail(path, function_name, int(function.get("line", 0)),
				"missing-visible-progress-edge",
				"curated rendered evidence no longer advances watchdog progress", "")
			continue
		for guard_group_v in guard_contract.get("guards", []):
			var guard_group := guard_group_v as Array
			var guard_line := _first_matching_line(function, guard_group)
			_checks += 1
			if guard_line <= 0 or guard_line >= note_line:
				_fail(path, function_name, note_line,
					"unguarded-visible-progress-edge",
					"a validated rendered change/result must dominate progress reset",
					"guard %s; note %s" % [
						str(guard_group), _raw_line(function, note_line)])


func _first_matching_line_after(
		function: Dictionary, tokens: Array, after_line: int) -> int:
	for line_v in function.get("lines", []):
		var line := line_v as Dictionary
		if int(line.get("line", 0)) <= after_line:
			continue
		var search := str(line.get("search", ""))
		for token_v in tokens:
			if search.contains(str(token_v)):
				return int(line.get("line", 0))
	return 0


func _first_matching_line(function: Dictionary, tokens: Array) -> int:
	var first := 0
	for line_v in function.get("lines", []):
		var line := line_v as Dictionary
		var search := str(line.get("search", ""))
		for token_v in tokens:
			if search.contains(str(token_v)):
				var number := int(line.get("line", 0))
				if first == 0 or number < first:
					first = number
	return first


func _raw_line(function: Dictionary, line_number: int) -> String:
	for line_v in function.get("lines", []):
		var line := line_v as Dictionary
		if int(line.get("line", 0)) == line_number:
			return str(line.get("raw", "")).strip_edges()
	return str(function.get("signature", ""))


func _function_search(function: Dictionary) -> String:
	var lines: Array[String] = [str(function.get("signature", ""))]
	for line_v in function.get("lines", []):
		lines.append(str((line_v as Dictionary).get("search", "")))
	return "\n".join(lines)


func _scan_function(path: String, name: String, function: Dictionary,
		audit: Dictionary, receipt_only := false) -> void:
	for line_v in function.get("lines", []):
		var line: Dictionary = line_v
		var search := str(line.get("search", ""))
		var code := str(line.get("code", ""))
		var number := int(line.get("line", 0))
		var snippet := str(line.get("raw", "")).strip_edges()
		for token_v in DIRECT_STATE.keys():
			var token := str(token_v)
			var searchable := search if token.contains("\"") or token.contains("'") else code
			if searchable.contains(token):
				if token == "set_running" and code.contains("driver.set_running"):
					continue
				_fail(path, name, number, "direct-state-action", str(DIRECT_STATE[token]), snippet)
		for method_v in DYNAMIC_DIRECT_STATE_METHODS.keys():
			var method := str(method_v)
			if search.contains("call(\"%s\"" % method) \
					or search.contains("call('%s'" % method) \
					or search.contains("callv(\"%s\"" % method) \
					or search.contains("callv('%s'" % method):
				_fail(path, name, number, "direct-state-action",
					str(DYNAMIC_DIRECT_STATE_METHODS[method]), snippet)
		for token_v in DIRECT_CONSEQUENCE.keys():
			var token := str(token_v)
			var searchable := search if token.contains("\"") or token.contains("'") else code
			if searchable.contains(token):
				_fail(path, name, number, "direct-consequence", str(DIRECT_CONSEQUENCE[token]), snippet)
		if bool(audit.get("presentation_only", false)) and not receipt_only:
			for token_v in HIDDEN_POLICY_OBSERVATION.keys():
				var token := str(token_v)
				if search.contains(token):
					_fail(path, name, number, "hidden-policy-observation",
						str(HIDDEN_POLICY_OBSERVATION[token]), snippet)
		if search.contains("qa_"):
			_fail(path, name, number, "hidden-semantic-input", "qa_* target-addressed actions bypass visible picking and are not player evidence", snippet)
		if (path.ends_with("stretch_generation_playtest_loop.gd") or path.ends_with("generated_input_playthrough_driver.gd")) and (search.contains("spec.get(\"headless\"") or search.contains("spec.get('headless'")):
			_fail(path, name, number, "solver-oracle-action-policy", "agent action policy reads solver-only spec.headless golden-path/solution data", snippet)

func _capability(functions: Dictionary, rally: bool) -> Dictionary:
	var capable := {}
	for name_v in functions.keys():
		var name := str(name_v)
		var function: Dictionary = functions[name]
		if (rally and _has_rally(function)) or (not rally and _has_input(function)):
			capable[name] = true
	var changed := true
	while changed:
		changed = false
		for name_v in functions.keys():
			var name := str(name_v)
			if capable.has(name):
				continue
			for called in _called(functions[name], functions):
				if capable.has(called):
					capable[name] = true
					changed = true
					break
	return capable

func _has_input(function: Dictionary) -> bool:
	for line_v in function.get("lines", []):
		var search := str((line_v as Dictionary).get("search", ""))
		for token_v in INPUT_BOUNDARIES:
			if search.contains(str(token_v)):
				return true
	return false

func _has_rally(function: Dictionary) -> bool:
	var right_button := false
	var hold_timing := false
	var press_edge := false
	var release_edge := false
	for line_v in function.get("lines", []):
		var search := str((line_v as Dictionary).get("search", ""))
		for token_v in RALLY_BOUNDARIES:
			if search.contains(str(token_v)):
				return true
		right_button = right_button or search.contains("MOUSE_BUTTON_RIGHT")
		hold_timing = hold_timing or search.contains("RALLY_HOLD") or search.contains("rally_hold") or search.contains("wait")
		press_edge = press_edge or search.contains("MOUSE_BUTTON_RIGHT, true")
		release_edge = release_edge or search.contains("MOUSE_BUTTON_RIGHT, false")
	# Input capability is checked independently. Allow a Rally root to deliver its two
	# edges through a shared raw-input helper instead of forcing parse_input_event here.
	return right_button and hold_timing and press_edge and release_edge

func _group_decomposition_line(name: String, function: Dictionary) -> int:
	var first_move := 0
	var move_lines := 0
	var party_loop := false
	var move_all := false
	for line_v in function.get("lines", []):
		var line: Dictionary = line_v
		var search := str(line.get("search", ""))
		move_all = move_all or search.contains("move_all")
		var compact := search.replace(" ", "").replace("\t", "")
		if compact.begins_with("for") and (compact.contains("inparty") or compact.contains("inactive_party") or compact.contains("inPARTY_IDS") or compact.contains("inPARTY_KEYS") or compact.contains("[\"aster\",\"peris\",\"endo\"]")):
			party_loop = true
		for token_v in SINGLETON_MOVES:
			if search.contains(str(token_v)):
				move_lines += 1
				if first_move == 0:
					first_move = int(line.get("line", 0))
				break
	if first_move == 0:
		return 0
	return first_move if name.contains("party") or name.contains("move_all") or party_loop or move_all or move_lines >= 2 else 0

func _parse_functions(source: String) -> Dictionary:
	var functions := {}
	var owners := {}
	var lines: Array = []
	var current := ""
	var signature_depth := 0
	var number := 0
	for raw_v in source.split("\n"):
		number += 1
		var raw := str(raw_v).trim_suffix("\r")
		var code := _strip_strings_and_comment(raw)
		var search := _strip_comment(raw)
		var record := {"line": number, "raw": raw, "code": code, "search": search, "indent": _indent(raw)}
		lines.append(record)
		var name := _function_name(code)
		if name != "":
			current = name
			signature_depth = code.count("(") - code.count(")")
			functions[current] = {"line": number, "signature": raw.strip_edges(), "lines": []}
			owners[number] = current
			continue
		if current != "" and signature_depth > 0:
			owners[number] = current
			functions[current]["signature"] = "%s\n%s" % [
				str((functions[current] as Dictionary).get("signature", "")),
				raw.strip_edges(),
			]
			signature_depth += code.count("(") - code.count(")")
			continue
		if current != "" and code.strip_edges() != "" and _indent(raw) == 0:
			current = ""
		if current != "":
			owners[number] = current
			if code.strip_edges() != "" or search.strip_edges() != "":
				(functions[current].get("lines", []) as Array).append(record)
	return {"functions": functions, "owners": owners, "lines": lines}

func _reachable(root_name: String, functions: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var stack: Array[String] = [root_name]
	while not stack.is_empty():
		var name: String = stack.pop_back()
		if seen.has(name):
			continue
		seen[name] = true
		out.append(name)
		for called in _called(functions.get(name, {}), functions):
			if not seen.has(called):
				stack.append(called)
	return out

func _called(function: Dictionary, functions: Dictionary) -> Array[String]:
	var cache_key := int(function.get("line", -1))
	if _called_cache.has(cache_key):
		return (_called_cache[cache_key] as Array).duplicate()
	var out: Array[String] = []
	var seen := {}
	for line_v in function.get("lines", []):
		for match_v in _calls.search_all(str((line_v as Dictionary).get("code", ""))):
			var called := str((match_v as RegExMatch).get_string(2))
			if functions.has(called) and not seen.has(called):
				seen[called] = true
				out.append(called)
	_called_cache[cache_key] = out.duplicate()
	return out

func _line_record(function: Dictionary, number: int) -> Dictionary:
	for line_v in function.get("lines", []):
		var line: Dictionary = line_v
		if int(line.get("line", 0)) == number:
			return line
	return {}

func _function_name(code: String) -> String:
	var prefix := ""
	if code.begins_with("func "):
		prefix = "func "
	elif code.begins_with("static func "):
		prefix = "static func "
	else:
		return ""
	var open_paren := code.find("(", prefix.length())
	return "" if open_paren < prefix.length() + 1 else code.substr(prefix.length(), open_paren - prefix.length()).strip_edges()

func _indent(line: String) -> int:
	var width := 0
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if character == "\t":
			width += 4
		elif character == " ":
			width += 1
		else:
			break
	return width

func _strip_strings_and_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if quote != "":
			out += " "
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
			out += " "
		elif character == "#":
			break
		else:
			out += character
	return out

func _strip_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if quote != "":
			out += character
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
			out += character
		elif character == "#":
			break
		else:
			out += character
	return out

func _fail(path: String, function_name: String, number: int, rule: String, detail: String, snippet: String) -> void:
	var key := "%s|%s|%d|%s" % [path, function_name, number, rule]
	if _seen.has(key):
		return
	_seen[key] = true
	_failures += 1
	var location := "%s::%s:%d" % [path.trim_prefix("res://"), function_name, number]
	var suffix := "" if snippet == "" else "\n    %s" % snippet
	printerr("[AGENT_INPUT_BOUNDARY/FAIL] %s [%s] %s%s" % [location, rule, detail, suffix])
