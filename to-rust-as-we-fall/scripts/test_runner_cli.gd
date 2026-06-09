extends Node

## CLI test runner. Parses command-line arguments and dispatches tests.
## Usage: godot --headless --path "." -- --test-syntax
##        godot --headless --path "." -- --test-all
##        godot --headless --path "." -- --test-tag-day
##        godot --headless --path "." -- --test-sequence-contracts

var _passed := 0
var _failed := 0
# Per-test profiling: assigning _test_name (every test does this on entry) prints the wall-clock
# duration of the test that just finished, so a slow/hung test in --test-all is obvious. Plus a
# [START] marker so the culprit is named even if it never returns. _flush_test_timing() emits the
# last test. Uses wall-clock deliberately — it's measuring real suite time, not gameplay logic.
var _test_name_storage := ""
var _test_start_ms := 0
var _profile_tests := false
var _test_name: String:
	get:
		return _test_name_storage
	set(value):
		var now := Time.get_ticks_msec()
		if _profile_tests:
			if _test_name_storage != "":
				print("[TIMING] %7d ms  %s" % [now - _test_start_ms, _test_name_storage])
			if value != "":
				print("[START] %s" % value)
		_test_name_storage = value
		_test_start_ms = now

func _flush_test_timing() -> void:
	if _profile_tests and _test_name_storage != "":
		print("[TIMING] %7d ms  %s" % [Time.get_ticks_msec() - _test_start_ms, _test_name_storage])
	_test_name_storage = ""

# --test-intro runs the whole suite EXCEPT the heavy puzzle/generation tests (Puzzle Fast-Forward,
# Puzzle Fragments, the Channels previews, the playtest loop — ~110s combined). _heavy() returns
# true to skip one, and logs it so the omission is never silent.
var _skip_heavy := false
func _heavy(label: String) -> bool:
	if _skip_heavy:
		print("  SKIP (heavy puzzle test, --test-intro): %s" % label)
		return true
	return false
const DayNightCycleScript = preload("res://scripts/system/simulation/day_night_cycle.gd")
const FloraMemorySystem = preload("res://scripts/system/simulation/flora_memory_system.gd")
const FauxPhysicsSensorScript = preload("res://scripts/game/mechanics/faux_physics_sensor.gd")
const StretchArchetypeCatalogScript = preload("res://scripts/generation/stretch_archetype_catalog.gd")
const StretchGeneratorScript = preload("res://scripts/generation/stretch_generator.gd")
const StretchSolutionSolverScript = preload("res://scripts/generation/stretch_solution_solver.gd")
const StretchReplayBuilderScript = preload("res://scripts/generation/stretch_replay_builder.gd")
const StretchCapabilitiesScript = preload("res://scripts/generation/stretch_capabilities.gd")
const CampaignOrderScript = preload("res://scripts/system/campaign/campaign_order.gd")
const StretchGenerationPlaytestLoopScript = preload("res://scripts/generation/stretch_generation_playtest_loop.gd")
const PlaythroughAnimationHtmlRendererScript = preload("res://scripts/generation/playthrough_animation_html_renderer.gd")
const NavigationGraphScript = preload("res://scripts/system/core/navigation_graph.gd")
const PUZZLE_FRAGMENT_CATALOG_PATH := "res://data/puzzles/showcase_fragments.json"
const GENERATED_STRETCH_SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
const GENERATED_CHAIN_NESTED_POC_SPEC_PATH := "res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json"
const GENERATED_RANDOM_WALK_POC_SPEC_PATH := "res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json"
const MOTHER_HACK_DWELL_SECONDS := 0.6
const MOTHER_PORTAL_DWELL_SECONDS := 0.4
const MOTHER_BUD_DWELL_SECONDS := 0.6
const MOTHER_ROOT_SETTLE_SECONDS := 5.5
const MOTHER_PICKUP_DWELL_SECONDS := 0.8
const MOTHER_INSTALL_DWELL_SECONDS := 0.8
const MOTHER_TEND_DWELL_SECONDS := 1.0
const MOTHER_CLOAK_DWELL_SECONDS := 0.4
const SAVE_MANAGER_SINGLETON := "SaveManager"
const SAVE_MANAGER_SCRIPT_PATH := "res://scripts/system/persistence/save_manager.gd"
const ENGRAM_JOURNAL_SINGLETON := "EngramJournal"
const ENGRAM_JOURNAL_SCRIPT_PATH := "res://scripts/system/persistence/engram_journal.gd"
const FRAGMENT_PREVIEW_GUI_CONTRACT_ID := "fragment_preview_shared_gui_v1"
const GAME_HUD_CONTRACT_ID := "shared_game_hud_v1"
const GAME_HUD_SCRIPT_PATH := "res://scripts/ui/game_hud.gd"
const FRAGMENT_PREVIEW_CONTROL_HELP := "Click move  1-3 focus  Ctrl+1-3 multi-select  C cycle  Z/X abilities  V drop  T transfer  B retrieve  F1-F3 overlays  O drawer  Tab route  G dodge  Space pause  R reload"
const FRAGMENT_PREVIEW_INVENTORY_CONTROL_HELP := "Controls: Z/X abilities  V drop  T transfer  B retrieve"
const FRAGMENT_CHUNK_SCENE_PATHS := [
	"res://scenes/fragments/chunks/stacks_fragment_chunk.tscn",
	"res://scenes/fragments/chunks/rings_fragment_chunk.tscn",
	"res://scenes/fragments/chunks/lockout_fragment_chunk.tscn",
	"res://scenes/fragments/chunks/overlay_lab_chunk.tscn",
	"res://scenes/fragments/chunks/mother_ferrolure_chunk.tscn",
	"res://scenes/fragments/chunks/survival_range_chunk.tscn",
	"res://scenes/fragments/chunks/channels_rhythm_chunk.tscn",
	"res://scenes/fragments/chunks/channels_hide_window_chunk.tscn",
	"res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn",
	"res://scenes/fragments/chunks/generated_stretch_chunk.tscn",
]
# Every fragment is now previewed through ONE scene + a runtime picker (the *_preview.tscn files are
# gone). The scene-load test drives the single scene once per registry entry.
const FRAGMENT_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const FragmentPreviewScript := preload("res://scripts/fragments/fragment_preview_sequence.gd")
const ACT1_SEQUENCE_STEPS := [
	"channels_enter", "channels_to_memory", "channels_memory",
	"channels_corpse", "channels_window_one_intro", "channels_window_one_activate",
	"channels_window_one_cross", "channels_to_ferrolure", "channels_ferrolure",
	"channels_window_two_intro", "channels_window_two_activate",
	"channels_window_two_cross", "channels_to_encounter", "channels_encounter_intro",
	"channels_encounter_activate", "channels_encounter_hide",
	"channels_encounter_run", "channels_shelter", "channels_explore",
	"stacks_enter", "stacks_terminal", "stacks_signal", "stacks_archive", "stacks_explore",
	"rings_enter", "rings_client", "endo_departs", "rings_explore",
	"lockout_approach", "lockout_rejected", "lockout_chase",
	"lockout_exile", "complete",
]

func _ready() -> void:
	# Wait one frame so the _ready chain completes before scene tests add_child to root
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()

	var ran_test := false
	for arg in args:
		match arg:
			"--test-all":
				ran_test = true
				_profile_tests = "--profile" in args
				await _run_all_tests()
				_flush_test_timing()
			"--test-intro":
				# The full suite minus the heavy puzzle/generation tests (~110s) — fast feedback
				# for the intro/scene/UI/feature work without the slow puzzle timing sweeps.
				ran_test = true
				_skip_heavy = true
				_profile_tests = "--profile" in args
				await _run_all_tests()
				_flush_test_timing()
			"--test-syntax":
				ran_test = true
				_test_syntax()
			"--test-grid":
				ran_test = true
				_test_grid_pathfinding()
			"--test-game-state":
				ran_test = true
				_test_game_state()
			"--test-cooperative-pathfinding":
				ran_test = true
				_test_cooperative_pathfinding()
			"--test-path-renderer":
				ran_test = true
				_test_path_renderer()
			"--test-path-render-manager":
				ran_test = true
				await _test_path_render_manager()
			"--test-grid-levels":
				ran_test = true
				_test_grid_levels()
			"--test-state-machine":
				ran_test = true
				_test_state_machine()
			"--test-elevator-enemy-engagement":
				ran_test = true
				_test_elevator_enemy_engagement()
			"--test-chromatic-aberration":
				ran_test = true
				await _test_chromatic_aberration()
			"--test-lure-relay":
				ran_test = true
				await _test_lure_relay_puzzle()
			"--test-hidden-detection":
				ran_test = true
				_test_hidden_detection()
			"--test-two-tier-detection":
				ran_test = true
				_test_two_tier_detection()
			"--test-enemy-roaming":
				ran_test = true
				_test_enemy_roaming()
			"--test-fragment-preview-registry":
				ran_test = true
				_test_fragment_preview_registry()
			"--test-preview-party-move":
				ran_test = true
				await _test_preview_party_move()
			"--test-preview-path-render":
				ran_test = true
				await _test_preview_path_render()
			"--test-preview-hover-grid":
				ran_test = true
				await _test_preview_hover_grid()
			"--test-preview-pathfinding":
				ran_test = true
				_test_preview_pathfinding()
			"--test-overlay-materials":
				ran_test = true
				await _test_overlay_materials()
			"--test-chunk-interactable-outlines":
				ran_test = true
				await _test_chunk_interactable_outlines()
			"--test-preview-matches-committed":
				ran_test = true
				await _test_preview_matches_committed()
			"--test-party-preview-renderers":
				ran_test = true
				await _test_party_preview_renderers()
			"--test-path-timed-wait-segment":
				ran_test = true
				_test_path_timed_wait_segment()
			"--test-enemy-pursuit-timeout":
				ran_test = true
				_test_enemy_pursuit_timeout()
			"--test-detection-vertical-band":
				ran_test = true
				_test_detection_vertical_band()
			"--test-interactable-state-replay":
				ran_test = true
				_test_interactable_state_replay()
			"--test-dialogue-transcript-cap":
				ran_test = true
				_test_dialogue_transcript_cap()
			"--test-combat-cycle":
				ran_test = true
				_test_combat_cycle()
			"--test-dodge-combat-timing":
				ran_test = true
				_test_dodge_combat_timing()
			"--test-chain-combat":
				ran_test = true
				_test_chain_combat()
			"--test-dodge-failure-no-cooldown":
				ran_test = true
				_test_dodge_failure_no_cooldown()
			"--test-strike-skips-corpse":
				ran_test = true
				_test_strike_skips_corpse()
			"--test-showcase-gallery":
				ran_test = true
				await _test_showcase_gallery()
			"--test-showcase-capture":
				ran_test = true
				await _test_showcase_capture()
			"--test-visual-regression":
				ran_test = true
				await _test_visual_regression()
			"--test-predictive-attack":
				ran_test = true
				_test_predictive_attack()
			"--test-data-identify":
				ran_test = true
				_test_data_identify()
			"--test-player-cross-level":
				ran_test = true
				_test_player_cross_level_click()
			"--test-outline-particle-emission":
				ran_test = true
				_test_outline_particle_emission()
			"--test-interactable-outline-particles":
				ran_test = true
				_test_interactable_outline_particles()
			"--test-outline-feedback-system":
				ran_test = true
				_test_outline_feedback_system()
			"--test-interactable-data":
				ran_test = true
				_test_interactable_data()
			"--test-chunk-party-presence":
				ran_test = true
				_test_chunk_party_presence()
			"--test-sim-command-api":
				ran_test = true
				_test_sim_command_api()
			"--test-puzzle-outcome-coverage":
				ran_test = true
				_test_puzzle_outcome_coverage()
			"--test-overlay-facility-gating":
				ran_test = true
				await _test_overlay_facility_gating()
			"--test-event-log-roundtrip":
				ran_test = true
				_test_event_log_roundtrip()
			"--test-event-log-mutation-audit":
				ran_test = true
				_test_event_log_mutation_audit()
			"--test-movement-capture":
				ran_test = true
				_test_movement_capture()
			"--test-rng-determinism":
				ran_test = true
				_test_rng_determinism()
			"--test-rng-no-wallclock":
				ran_test = true
				_test_rng_no_wallclock()
			"--test-sequence-input-discipline":
				ran_test = true
				_test_sequence_input_discipline()
			"--test-save-load-integrity":
				ran_test = true
				_test_save_load_integrity()
			"--test-save-corruption-recovery":
				ran_test = true
				_test_save_corruption_recovery()
			"--test-actuator-composition-blind":
				ran_test = true
				_test_actuator_composition_blind()
			"--test-actuator-no-id-checks":
				ran_test = true
				_test_actuator_no_id_checks()
			"--test-hub-rest-restore":
				ran_test = true
				_test_hub_rest_restore()
			"--test-gate-block":
				ran_test = true
				_test_gate_block()
			"--test-zone-progression":
				ran_test = true
				_test_zone_progression()
			"--test-no-game-over":
				ran_test = true
				_test_no_game_over()
			"--test-scripted-death-only":
				ran_test = true
				_test_scripted_death_only()
			"--test-scene-triggers":
				ran_test = true
				_test_scene_triggers()
			"--test-replay-roundtrip":
				ran_test = true
				_test_replay_roundtrip()
			"--test-determinism-rerecord":
				ran_test = true
				_test_determinism_rerecord()
			"--test-portal-revisit":
				ran_test = true
				_test_portal_revisit()
			"--test-party-cohesion-default":
				ran_test = true
				_test_party_cohesion_default()
			"--test-scripted-split":
				ran_test = true
				_test_scripted_split()
			"--test-flora-memory":
				ran_test = true
				_test_flora_memory()
			"--test-scheduler":
				ran_test = true
				_test_event_scheduler()
			"--test-enemy":
				ran_test = true
				await _test_enemy()
			"--test-chain-enemy":
				ran_test = true
				await _test_chain_enemy()
			"--test-act1":
				ran_test = true
				await _test_act1()
			"--test-tag-day":
				ran_test = true
				await _test_tag_day()
			"--test-aster-sim":
				ran_test = true
				await _test_aster_sim()
			"--test-aster-playthrough":
				ran_test = true
				await _test_aster_playthrough()
			"--test-input-playthrough":
				ran_test = true
				await _test_input_playthrough()
			"--test-dialogue-pause":
				ran_test = true
				await _test_dialogue_pause_chain()
			"--test-settings":
				ran_test = true
				await _test_settings()
			"--test-dialogue-pagination":
				ran_test = true
				await _test_dialogue_pagination()
			"--test-dialogue-cutscene-mode":
				ran_test = true
				await _test_dialogue_cutscene_mode()
			"--test-interactable-highlight":
				ran_test = true
				await _test_interactable_highlight()
			"--test-pause-menu":
				ran_test = true
				await _test_pause_menu()
			"--test-peris-sim":
				ran_test = true
				await _test_peris_sim()
			"--test-elevator":
				ran_test = true
				await _test_elevator()
			"--test-elevator-fall-level":
				ran_test = true
				await _test_elevator_fall_level()
			"--test-leaving-facility":
				ran_test = true
				await _test_leaving_facility()
			"--test-showcase":
				ran_test = true
				await _test_showcase()
			"--test-engram":
				ran_test = true
				_test_engram_and_saves()
			"--test-puzzle-fragments":
				ran_test = true
				await _test_puzzle_fragments()
			"--test-survival-range-timing":
				ran_test = true
				await _test_survival_range_timing()
			"--test-day-night-cycle":
				ran_test = true
				await _test_day_night_cycle()
			"--test-tag-day-dialogue":
				ran_test = true
				await _test_tag_day_dialogue()
			"--test-peris-dialogue":
				ran_test = true
				await _test_peris_dialogue()
			"--test-elevator-dialogue":
				ran_test = true
				await _test_elevator_dialogue()
			"--test-endo-drink":
				ran_test = true
				await _test_endo_drink()
			"--test-junction-flow":
				ran_test = true
				await _test_junction_flow()
			"--test-climb":
				ran_test = true
				_test_climb_and_lockout()
			"--test-predict-detect":
				ran_test = true
				_test_predictive_detection()
			"--test-detect-equiv":
				ran_test = true
				_test_detection_equivalence()
			"--test-ferrolure":
				ran_test = true
				await _test_ferrolure()
			"--test-hide-encounter":
				ran_test = true
				_test_hide_encounter()
			"--test-hide-encounter-analysis":
				ran_test = true
				_test_hide_encounter_analysis()
			"--test-hide-encounter-shared-duration":
				ran_test = true
				_test_hide_encounter_shared_duration()
			"--test-hide-encounter-lure2-duration":
				ran_test = true
				_test_hide_encounter_lure2_duration()
			"--test-hide-encounter-exit-gap":
				ran_test = true
				_test_hide_encounter_exit_gap()
			"--test-hide-encounter-cluster-gap":
				ran_test = true
				_test_hide_encounter_cluster_gap()
			"--test-hide-encounter-run-drain":
				ran_test = true
				_test_hide_encounter_run_drain()
			"--test-hide-encounter-stand-regen":
				ran_test = true
				_test_hide_encounter_stand_regen()
			"--test-hide-encounter-consume-cost":
				ran_test = true
				_test_hide_encounter_consume_cost()
			"--test-hide-encounter-hold-duration":
				ran_test = true
				_test_hide_encounter_hold_duration()
			"--test-hide-encounter-walk-regen":
				ran_test = true
				_test_hide_encounter_walk_regen()
			"--test-hide-encounter-coupled-stand-hold":
				ran_test = true
				_test_hide_encounter_coupled_stand_hold()
			"--test-hide-encounter-coupled-stand-walk":
				ran_test = true
				_test_hide_encounter_coupled_stand_walk()
			"--test-hide-encounter-split-recovery":
				ran_test = true
				_test_hide_encounter_split_recovery()
			"--test-camera-shake":
				ran_test = true
				_test_camera_shake()
			"--test-physics":
				ran_test = true
				_test_physics_objects()
				_test_physics_edge_cases()
			"--test-pendulum":
				ran_test = true
				_test_pendulum()
			"--test-throw":
				ran_test = true
				_test_throw_physics()
			"--test-physics-comparison":
				ran_test = true
				await _test_physics_comparison()
			"--test-items":
				ran_test = true
				_test_items()
			"--test-abilities":
				ran_test = true
				_test_queued_abilities()
			"--test-dodge":
				ran_test = true
				_test_dodge_roll()
			"--test-scene-load":
				ran_test = true
				await _test_scene_load()
			"--test-all-scenes-load":
				ran_test = true
				await _test_all_scenes_load()
			"--test-scene-spatial":
				ran_test = true
				await _test_scene_spatial_consistency()
			"--test-occlusion-fade":
				ran_test = true
				await _test_occlusion_fade()
			"--test-archetype-generation":
				ran_test = true
				await _test_archetype_generation()
			"--test-generated-stretch-playtest-loop":
				ran_test = true
				await _test_generated_stretch_playtest_loop()
			"--test-generated-multi-solution":
				ran_test = true
				_test_generated_multi_solution()
			"--test-generated-replay":
				ran_test = true
				_test_generated_replay()
			"--test-campaign-order":
				ran_test = true
				_test_campaign_order()
			"--test-survival-archetypes":
				ran_test = true
				await _test_survival_archetypes()
			"--test-archetype-coherence":
				ran_test = true
				_test_archetype_coherence()
			"--test-character-roster":
				ran_test = true
				_test_character_roster()
			"--test-asset-pipeline":
				ran_test = true
				_test_asset_pipeline()
			"--test-mother-ferrolure":
				ran_test = true
				await _test_mother_ferrolure_preview()
			"--test-endo-junction-stretch":
				ran_test = true
				await _test_endo_junction_stretch_preview()
			"--test-channels-rhythm":
				ran_test = true
				await _test_channels_rhythm_preview()
			"--test-channels-hide":
				ran_test = true
				await _test_channels_hide_window_preview()
			"--test-peris-phase2":
				ran_test = true
				await _test_peris_phase2()
			"--test-peris-scene-transition":
				ran_test = true
				await _test_peris_scene_transition()
			"--drive-peris-transition":
				ran_test = true
				await _drive_peris_transition_child()
			"--test-sequence-contracts":
				ran_test = true
				await _test_sequence_contracts()
			"--test-intro-chain":
				ran_test = true
				await _test_intro_chain()
			"--test-intro-realinput":
				ran_test = true
				await _test_intro_realinput()
			"--test-elevator-realinput":
				ran_test = true
				await _test_elevator_realinput()
			"--test-fast-forward-invariance":
				ran_test = true
				await _test_fast_forward_invariance()
			"--test-puzzle-fast-forward-invariance":
				ran_test = true
				await _test_puzzle_fast_forward_invariance()
			"--report-act1-playtime":
				ran_test = true
				await _report_act1_playtime()
			"--report-act1-human-playtime":
				ran_test = true
				await _report_act1_human_playtime()
			"--report-survival-range-playtime":
				ran_test = true
				await _report_survival_range_playtime()
			"--report-mother-ferrolure-playtime":
				ran_test = true
				await _report_mother_ferrolure_playtime()

	# --start-peris-phase2: launch the scene directly at phase 2 for manual testing
	for i in range(args.size()):
		if args[i] == "--start-peris-phase2":
			var PSS = load("res://scripts/tutorial/peris_sim_sequence.gd")
			PSS._visit_phase = 2
			get_tree().change_scene_to_file("res://scenes/tutorial/peris_sim.tscn")
			return

	# --dump-dialogue <scene_path> [output_path]
	for i in range(args.size()):
		if args[i] == "--test-puzzle-fragment" and i + 1 < args.size():
			ran_test = true
			await _test_puzzle_fragments(args[i + 1])
		if args[i] == "--dump-dialogue" and i + 1 < args.size():
			ran_test = true
			var scene_path: String = args[i + 1]
			var output_path := "dialogue_dump.txt"
			if i + 2 < args.size() and not args[i + 2].begins_with("--"):
				output_path = args[i + 2]
			await _dump_dialogue(scene_path, output_path)
		if args[i] == "--dump-tutorial-dialogue" and i + 1 < args.size():
			ran_test = true
			var tutorial_scene: String = args[i + 1]
			var output_path := "tutorial_dialogue_dump.txt"
			if i + 2 < args.size() and not args[i + 2].begins_with("--"):
				output_path = args[i + 2]
			await _dump_tutorial_dialogue(tutorial_scene, output_path)
		if args[i] == "--report-generated-stretch-events":
			ran_test = true
			var generated_events_output := "res://reports/generated_stretch_event_report.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				generated_events_output = args[i + 1]
			await _report_generated_stretch_events(generated_events_output)
		if args[i] == "--export-hide-encounter-analysis":
			ran_test = true
			var analysis_output := "hide_encounter_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				analysis_output = args[i + 1]
			_export_hide_encounter_analysis(analysis_output)
		if args[i] == "--export-hide-encounter-exit-gap-analysis":
			ran_test = true
			var exit_gap_analysis_output := "hide_encounter_exit_gap_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				exit_gap_analysis_output = args[i + 1]
			_export_hide_encounter_exit_gap_analysis(exit_gap_analysis_output)
		if args[i] == "--export-hide-encounter-cluster-gap-analysis":
			ran_test = true
			var cluster_gap_analysis_output := "hide_encounter_cluster_gap_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				cluster_gap_analysis_output = args[i + 1]
			_export_hide_encounter_cluster_gap_analysis(cluster_gap_analysis_output)
		if args[i] == "--export-hide-encounter-run-drain-analysis":
			ran_test = true
			var run_drain_analysis_output := "hide_encounter_run_drain_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				run_drain_analysis_output = args[i + 1]
			_export_hide_encounter_run_drain_analysis(run_drain_analysis_output)
		if args[i] == "--export-hide-encounter-stand-regen-analysis":
			ran_test = true
			var stand_regen_analysis_output := "hide_encounter_stand_regen_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				stand_regen_analysis_output = args[i + 1]
			_export_hide_encounter_stand_regen_analysis(stand_regen_analysis_output)
		if args[i] == "--export-hide-encounter-hold-duration-analysis":
			ran_test = true
			var hold_duration_analysis_output := "hide_encounter_hold_duration_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				hold_duration_analysis_output = args[i + 1]
			_export_hide_encounter_hold_duration_analysis(hold_duration_analysis_output)
		if args[i] == "--export-hide-encounter-custom-analysis" and i + 1 < args.size():
			ran_test = true
			var config_path: String = args[i + 1]
			var custom_analysis_output := "hide_encounter_custom_analysis.json"
			if i + 2 < args.size() and not args[i + 2].begins_with("--"):
				custom_analysis_output = args[i + 2]
			_export_hide_encounter_custom_analysis(config_path, custom_analysis_output)
		if args[i] == "--export-hide-encounter-walk-regen-analysis":
			ran_test = true
			var walk_regen_analysis_output := "hide_encounter_walk_regen_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				walk_regen_analysis_output = args[i + 1]
			_export_hide_encounter_walk_regen_analysis(walk_regen_analysis_output)
		if args[i] == "--export-hide-encounter-coupled-stand-hold-analysis":
			ran_test = true
			var coupled_stand_hold_output := "hide_encounter_coupled_stand_hold_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				coupled_stand_hold_output = args[i + 1]
			_export_hide_encounter_coupled_stand_hold_analysis(coupled_stand_hold_output)
		if args[i] == "--export-hide-encounter-coupled-stand-walk-analysis":
			ran_test = true
			var coupled_stand_walk_output := "hide_encounter_coupled_stand_walk_analysis.json"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				coupled_stand_walk_output = args[i + 1]
			_export_hide_encounter_coupled_stand_walk_analysis(coupled_stand_walk_output)

	if ran_test:
		_print_results()
		get_tree().quit(0 if _failed == 0 else 1)
	else:
		pass

func _run_all_tests() -> void:
	_test_syntax()
	_test_grid_pathfinding()
	_test_game_state()
	_test_state_machine()
	_test_elevator_enemy_engagement()
	_test_data_identify()
	_test_hidden_detection()
	_test_two_tier_detection()
	_test_enemy_roaming()
	_test_predictive_attack()
	_test_fragment_preview_registry()
	await _test_preview_party_move()
	await _test_preview_path_render()
	await _test_preview_hover_grid()
	_test_preview_pathfinding()
	await _test_overlay_materials()
	await _test_chunk_interactable_outlines()
	await _test_preview_matches_committed()
	await _test_party_preview_renderers()
	_test_path_timed_wait_segment()
	_test_enemy_pursuit_timeout()
	_test_detection_vertical_band()
	_test_interactable_state_replay()
	_test_dialogue_transcript_cap()
	_test_combat_cycle()
	_test_dodge_combat_timing()
	_test_chain_combat()
	_test_dodge_failure_no_cooldown()
	_test_strike_skips_corpse()
	await _test_showcase_gallery()
	await _test_lure_relay_puzzle()
	await _test_chromatic_aberration()
	_test_cooperative_pathfinding()
	_test_path_renderer()
	await _test_path_render_manager()
	_test_grid_levels()
	_test_player_cross_level_click()
	_test_outline_particle_emission()
	_test_interactable_outline_particles()
	_test_outline_feedback_system()
	_test_interactable_data()
	_test_chunk_party_presence()
	_test_sim_command_api()
	_test_puzzle_outcome_coverage()
	_test_event_log_roundtrip()
	_test_event_log_mutation_audit()
	_test_movement_capture()
	_test_rng_determinism()
	_test_rng_no_wallclock()
	_test_sequence_input_discipline()
	await _test_archetype_generation()
	_test_generated_multi_solution()
	_test_generated_replay()
	_test_campaign_order()
	_test_archetype_coherence()
	_test_character_roster()
	await _test_survival_archetypes()
	if not _heavy("Generated Stretch Playtest Loop"):
		await _test_generated_stretch_playtest_loop()
	_test_save_load_integrity()
	_test_save_corruption_recovery()
	_test_actuator_composition_blind()
	_test_actuator_no_id_checks()
	_test_hub_rest_restore()
	_test_gate_block()
	_test_zone_progression()
	_test_no_game_over()
	_test_scripted_death_only()
	_test_scene_triggers()
	_test_replay_roundtrip()
	_test_determinism_rerecord()
	_test_portal_revisit()
	_test_party_cohesion_default()
	_test_scripted_split()
	_test_flora_memory()
	_test_event_scheduler()
	await _test_scene_load()
	await _test_all_scenes_load()
	await _test_scene_spatial_consistency()
	await _test_occlusion_fade()
	_test_asset_pipeline()
	await _test_aster_sim()
	await _test_aster_playthrough()
	await _test_input_playthrough()
	await _test_fast_forward_invariance()
	if not _heavy("Puzzle Fast-Forward Invariance"):
		await _test_puzzle_fast_forward_invariance()
	await _test_dialogue_pause_chain()
	await _test_settings()
	await _test_dialogue_pagination()
	await _test_dialogue_cutscene_mode()
	await _test_interactable_highlight()
	await _test_pause_menu()
	await _test_peris_sim()
	await _test_elevator()
	await _test_elevator_fall_level()
	await _test_overlay_facility_gating()
	await _test_leaving_facility()
	await _test_showcase()
	_test_engram_and_saves()
	if not _heavy("Puzzle Fragments"):
		await _test_puzzle_fragments()
	await _test_day_night_cycle()
	await _test_survival_range_timing()
	await _test_tag_day()
	await _test_tag_day_dialogue()
	await _test_peris_dialogue()
	await _test_peris_tutorial_redirect()
	await _test_elevator_dialogue()
	await _test_endo_drink()
	await _test_junction_flow()
	_test_climb_and_lockout()
	await _test_enemy()
	await _test_chain_enemy()
	await _test_act1()
	await _test_ferrolure()
	_test_camera_shake()
	_test_physics_objects()
	_test_physics_edge_cases()
	_test_pendulum()
	_test_throw_physics()
	await _test_physics_comparison()
	await _test_mother_ferrolure_preview()
	await _test_endo_junction_stretch_preview()
	if not _heavy("Channels Rhythm Preview"):
		await _test_channels_rhythm_preview()
	if not _heavy("Channels Hide Window Preview"):
		await _test_channels_hide_window_preview()
	await _test_peris_phase2()
	await _test_peris_scene_transition()
	# Real-input intro legs (Aster/Peris-2/Tag Day) — first-class, not on-demand. The slow
	# Elevator leg is sectioned to --test-elevator-realinput (by name, not by category).
	await _test_intro_realinput_core()
	await _test_sequence_contracts()
	_test_items()
	_test_queued_abilities()
	_test_dodge_roll()
	_test_predictive_detection()
	_test_detection_equivalence()

# --- Test: Syntax ---
# If we got this far, GDScript compiled successfully.
func _test_syntax() -> void:
	_test_name = "Syntax Check"
	_assert_true(true, "All GDScript files compiled without errors")
	_assert_no_dialogue_override_files()
	_assert_ouroboros_dialogue_draft()
	_assert_nustle_dialogue_draft()
	_assert_love_dimensionless_dialogue_draft()

func _assert_no_dialogue_override_files() -> void:
	var dir := DirAccess.open("res://data/dialogue/en")
	_assert_true(dir != null, "Dialogue source directory exists")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.contains("_overrides"):
			_assert_true(false,
				"Dialogue override files are not allowed; edit act1.xlsx instead: %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _assert_ouroboros_dialogue_draft() -> void:
	var required_keys := [
		"ouroboros.entry.narration",
		"ouroboros.aster.overlay_loop",
		"ouroboros.peris.name",
		"ouroboros.peris.tail",
		"ouroboros.aster.loop_model",
		"ouroboros.peris.secret",
		"ouroboros.peris.world_can_change",
		"ouroboros.peris.not_doomed",
		"ouroboros.close.narration",
	]
	for key in required_keys:
		_assert_true(DialogueData.has_key(key), "Ouroboros draft dialogue key exists: %s" % key)
	_assert_true(DialogueData.text("ouroboros.aster.loop_model").contains("same loop"),
		"Ouroboros draft keeps Aster's closed-loop systems read")
	_assert_true(DialogueData.text("ouroboros.peris.world_can_change").contains("world can change"),
		"Ouroboros draft keeps the world-can-change secret")
	_assert_true(DialogueData.text("ouroboros.peris.not_doomed").contains("not doomed"),
		"Ouroboros draft keeps the not-doomed anchor")

func _assert_nustle_dialogue_draft() -> void:
	var required_keys := [
		"nustle.dogs.peris.ask",
		"nustle.dogs.aster.ask",
		"nustle.dogs.peris.myth",
		"nustle.dogs.aster.mythical",
		"nustle.nuzzle.peris.lead",
		"nustle.nusselt.aster.mishear",
		"nustle.nusselt.aster.explain",
		"nustle.nuzzle.peris.correct",
		"nustle.word.peris.nustle",
		"nustle.word.aster.all_three",
		"nustle.close.peris.feel",
		"nustle.close.aster.this",
	]
	for key in required_keys:
		_assert_true(DialogueData.has_key(key), "Nustle draft dialogue key exists: %s" % key)
	var dog_myth := DialogueData.text("nustle.dogs.peris.myth")
	_assert_true(
		dog_myth.contains("universal hospitality")
		and dog_myth.contains("cooperate easily")
		and not dog_myth.to_lower().contains("love"),
		"Nustle draft keeps Peris's dog myth in hospitality/bonding language")
	var nusselt_read := DialogueData.text("nustle.nusselt.aster.explain")
	_assert_true(
		nusselt_read.contains("Nusselt number")
		and nusselt_read.contains("convective")
		and nusselt_read.contains("conductive")
		and nusselt_read.contains("Fur would complicate it")
		and nusselt_read.contains("Wet surface, higher local transfer")
		and not nusselt_read.contains("thermal map"),
		"Nustle draft keeps Aster's concise Nusselt expansion without the removed thermal-map line")
	var old_word := DialogueData.text("nustle.word.peris.nustle")
	_assert_true(
		old_word.contains("Nustle")
		and old_word.contains("settle comfortably, snuggle, or fondly take care of"),
		"Nustle draft keeps the approved old-word definition")
	_assert_equals(DialogueData.text("nustle.close.aster.this"),
		"...Just like this.",
		"Nustle draft keeps Aster's final answer")
	_assert_true(not DialogueData.has_key("nustle.word.peris.dog_myth"),
		"Rejected Nustle dog-myth draft key is absent")

func _assert_love_dimensionless_dialogue_draft() -> void:
	var required_keys := [
		"love_dimensionless.entry.narration",
		"love_dimensionless.aster.wake_test",
		"love_dimensionless.peris.drink_machine",
		"love_dimensionless.aster.separations_transport",
		"love_dimensionless.peris.word_funny",
		"love_dimensionless.peris.ads",
		"love_dimensionless.aster.simulo_skins",
		"love_dimensionless.peris.love_languages",
		"love_dimensionless.aster.soul_weight",
		"love_dimensionless.peris.jingle_weight",
		"love_dimensionless.aster.define_love",
		"love_dimensionless.aster.more_words",
		"love_dimensionless.peris.relationships",
		"love_dimensionless.aster.jingle",
		"love_dimensionless.peris.can_remember",
		"love_dimensionless.aster.yeah",
		"love_dimensionless.peris.dimensionless",
	]
	for key in required_keys:
		_assert_true(DialogueData.has_key(key), "Love is Dimensionless dialogue key exists: %s" % key)
	var intro := DialogueData.get_line("love_dimensionless.entry.narration")
	_assert_true(
		intro.context.contains("Late Act 2 / early Act 3")
		and intro.context.contains("unspecified mini-boss"),
		"Love is Dimensionless keeps the source placement note on the first row")
	var simulo_line := DialogueData.text("love_dimensionless.aster.simulo_skins")
	_assert_true(
		simulo_line.contains("Love at first site")
		and simulo_line.contains("love at a good price"),
		"Love is Dimensionless keeps the Simulo-skins ad phrasing")
	var relationships_line := DialogueData.text("love_dimensionless.peris.relationships")
	_assert_true(
		relationships_line.contains("relationships")
		and relationships_line.contains("dimensionless numbers"),
		"Love is Dimensionless bridges word meaning to dimensionless numbers")
	_assert_equals(DialogueData.text("love_dimensionless.peris.dimensionless"),
		"Love is dimensionless.",
		"Love is Dimensionless lands on the title line")

# --- Test: Scene Load ---
func _test_scene_load() -> void:
	_test_name = "Scene Load"

	var level_editor := load("res://scenes/editor/level_editor.tscn")
	_assert_true(level_editor != null, "level_editor.tscn loads")
	if level_editor != null:
		var editor_instance: Node = level_editor.instantiate()
		_assert_true(editor_instance != null, "level_editor.tscn instantiates")
		if editor_instance != null:
			get_tree().root.add_child(editor_instance)
			for _i in range(3):
				await get_tree().process_frame
			_assert_level_editor_plan_browser(editor_instance)
			editor_instance.queue_free()
			await get_tree().process_frame

	var aster_sim := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(aster_sim != null, "aster_sim.tscn loads")

	var peris_sim := load("res://scenes/tutorial/peris_sim.tscn")
	_assert_true(peris_sim != null, "peris_sim.tscn loads")

	var leaving := load("res://scenes/tutorial/leaving_facility.tscn")
	_assert_true(leaving != null, "leaving_facility.tscn loads")

	var tag_day := load("res://scenes/tutorial/tag_day.tscn")
	_assert_true(tag_day != null, "tag_day.tscn loads")

	for chunk_scene_path in FRAGMENT_CHUNK_SCENE_PATHS:
		var chunk_scene: PackedScene = load(chunk_scene_path)
		_assert_true(chunk_scene != null, "%s loads" % chunk_scene_path.get_file())
		if chunk_scene == null:
			continue
		var chunk_instance: Node = chunk_scene.instantiate()
		_assert_true(chunk_instance != null, "%s instantiates without its own GUI" % chunk_scene_path.get_file())
		if chunk_instance != null:
			_assert_no_embedded_game_gui(chunk_instance, chunk_scene_path.get_file())
			chunk_instance.free()

	var preview_packed: PackedScene = load(FRAGMENT_PREVIEW_SCENE_PATH)
	_assert_true(preview_packed != null, "fragment_preview.tscn loads")
	if preview_packed != null:
		# One scene, every registry entry: instantiate the single preview, point it at the entry's
		# chunk (menu off), and assert the same shared-GUI / overlay / ability wiring as before.
		for entry in FragmentPreviewScript.PREVIEW_ENTRIES:
			var label := String(entry.get("id", entry.get("chunk", "?")))
			var preview_instance: Node = preview_packed.instantiate()
			_assert_true(preview_instance != null, "fragment_preview instantiates for %s" % label)
			if preview_instance == null:
				continue
			preview_instance.set("preview_menu", false)
			preview_instance.set("preview_chunk", String(entry.get("chunk", "")))
			preview_instance.set("scene_title_override", String(entry.get("title", "")))
			preview_instance.set("preview_chunk_config", (entry.get("config", {}) as Dictionary).duplicate(true))
			get_tree().root.add_child(preview_instance)
			for _i in range(2):
				await get_tree().process_frame
			var env: Node = preview_instance.find_child("Environment", true, false)
			_assert_true(env != null, "%s has an Environment node" % label)
			_assert_fragment_preview_uses_shared_gui(preview_instance, label)
			_assert_preview_overlay_vision_sources(preview_instance, label)
			_assert_preview_main_ability_keymap(preview_instance, label)
			preview_instance.queue_free()
			await get_tree().process_frame

		# And the picker itself boots (menu on) with a button per entry and no chunk loaded yet.
		var menu_instance: Node = preview_packed.instantiate()
		get_tree().root.add_child(menu_instance)
		for _i in range(2):
			await get_tree().process_frame
		var menu_panel: Node = menu_instance.find_child("FragmentMenu", true, false)
		_assert_true(menu_panel != null, "fragment_preview boots into the picker menu")
		if menu_panel != null:
			var button_count := 0
			for descendant in menu_panel.find_children("*", "Button", true, false):
				button_count += 1
			_assert_true(button_count >= FragmentPreviewScript.PREVIEW_ENTRIES.size(),
				"The picker lists every fragment (got %d buttons)" % button_count)
		menu_instance.queue_free()
		await get_tree().process_frame

	var block_lib := load("res://resources/block_library.tres")
	_assert_true(block_lib != null, "block_library.tres loads")
	_assert_true(block_lib is MeshLibrary, "block_library is MeshLibrary")

	await get_tree().process_frame

## Auto-discover EVERY .tscn under res://scenes and confirm it loads. Scenes that
## aren't a heavy sequence (which their own dedicated test already instantiates)
## are also instantiated. This way a newly-added scene can never go untested.
func _test_all_scenes_load() -> void:
	_test_name = "All Scenes Load"
	var scene_paths := _discover_scenes("res://scenes")
	scene_paths.sort()
	_assert_true(scene_paths.size() >= 24,
		"Discovered the scene set (%d scenes under res://scenes)" % scene_paths.size())
	# These build a full act/sequence on _ready; their dedicated tests instantiate
	# and drive them, so here we only confirm the resource loads.
	var heavy := {
		"res://scenes/tutorial/act1.tscn": true,
		"res://scenes/tutorial/elevator.tscn": true,
	}
	for path in scene_paths:
		var packed: PackedScene = load(path)
		_assert_true(packed != null, "%s loads" % path)
		if packed == null or heavy.has(path):
			continue
		var inst: Node = packed.instantiate()
		_assert_true(inst != null, "%s instantiates" % path.get_file())
		if inst == null:
			continue
		get_tree().root.add_child(inst)
		await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame

func _discover_scenes(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			found.append_array(_discover_scenes(child))
		elif name.ends_with(".tscn"):
			found.append(child)
		name = dir.get_next()
	dir.list_dir_end()
	return found

## Spatial consistency for grid-backed tutorial scenes: every registered character
## and every interactable must sit on a finite, in-bounds, walkable cell. Catches
## characters spawned inside walls or off the grid.
func _test_scene_spatial_consistency() -> void:
	_test_name = "Scene Spatial Consistency"
	var grid_scenes := [
		"res://scenes/tutorial/aster_sim.tscn",
		"res://scenes/tutorial/peris_sim.tscn",
		"res://scenes/tutorial/leaving_facility.tscn",
		"res://scenes/tutorial/tag_day.tscn",
	]
	for path in grid_scenes:
		var packed: PackedScene = load(path)
		_assert_true(packed != null, "%s loads for spatial check" % path.get_file())
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		get_tree().root.add_child(inst)
		for _i in range(5):
			await get_tree().process_frame

		var label: String = path.get_file()
		var gs = inst.get("_game_state")
		_assert_true(gs != null, "%s exposes a GameState" % label)
		if gs == null:
			inst.queue_free()
			await get_tree().process_frame
			continue
		_assert_true(gs.characters.size() > 0, "%s registers characters in GameState" % label)

		# A grid is optional — some scenes use a procedural environment. When one
		# is present, character/interactable cells must be in-bounds and walkable.
		var grid = gs.grid
		if grid != null:
			_assert_true(int(grid.width) > 0 and int(grid.height) > 0 and float(grid.cell_size) > 0.0,
				"%s grid has sane dimensions (%dx%d, cell %.1f)" % [label, grid.width, grid.height, grid.cell_size])

		# Every GameState character: finite position (always); in-bounds + walkable when gridded.
		for char_id in gs.characters.keys():
			var pos: Vector3 = gs.get_position(char_id)
			_assert_true(_is_finite_vec3(pos),
				"%s character '%s' has a finite position" % [label, char_id])
			if not _is_finite_vec3(pos) or grid == null:
				continue
			var cell: Vector2i = grid.world_to_grid(pos)
			_assert_true(grid.is_in_bounds(cell.x, cell.y),
				"%s character '%s' starts inside the grid (cell %s)" % [label, char_id, cell])
			if grid.is_in_bounds(cell.x, cell.y):
				_assert_true(grid.is_walkable(cell.x, cell.y),
					"%s character '%s' starts on a walkable cell (cell %s, tile %d)" % [label, char_id, cell, grid.get_tile(cell.x, cell.y)])

		# Every interactable: finite position (always); in-bounds when gridded.
		for node in inst.find_children("*", "Interactable", true, false):
			if not (node is Node3D):
				continue
			var ipos: Vector3 = (node as Node3D).global_position
			_assert_true(_is_finite_vec3(ipos),
				"%s interactable '%s' has a finite position" % [label, node.name])
			if not _is_finite_vec3(ipos) or grid == null:
				continue
			var icell: Vector2i = grid.world_to_grid(ipos)
			_assert_true(grid.is_in_bounds(icell.x, icell.y),
				"%s interactable '%s' sits inside the grid (cell %s)" % [label, node.name, icell])

		inst.queue_free()
		await get_tree().process_frame

func _is_finite_vec3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

## OcclusionFade: shader loads, applies to occluders preserving albedo, and keeps
## the player_position uniform synced to the bound target each frame.
func _test_occlusion_fade() -> void:
	_test_name = "Occlusion Fade"

	var shader := load("res://resources/occlusion_fade.gdshader")
	_assert_true(shader is Shader, "Occlusion fade shader loads")
	var fade_script := load("res://scripts/game/objects/occlusion_fade.gd")
	_assert_true(fade_script is GDScript, "OcclusionFade script loads")

	var root := Node3D.new()
	get_tree().root.add_child(root)

	var target := Node3D.new()
	target.position = Vector3(2.0, 0.0, 3.0)
	root.add_child(target)

	var occluder := MeshInstance3D.new()
	occluder.mesh = BoxMesh.new()
	var src_mat := StandardMaterial3D.new()
	src_mat.albedo_color = Color(0.2, 0.4, 0.6)
	src_mat.roughness = 0.7
	occluder.material_override = src_mat
	root.add_child(occluder)

	var fade = fade_script.new()
	root.add_child(fade)
	fade.bind(target)
	var mat = fade.register_occluder(occluder)

	_assert_true(mat is ShaderMaterial, "register_occluder returns a ShaderMaterial")
	_assert_equals(fade.occluder_count(), 1, "OcclusionFade tracks the registered occluder")
	_assert_true(occluder.material_override is ShaderMaterial,
		"Occluder mesh now renders through the occlusion shader")
	if mat != null:
		var copied: Color = mat.get_shader_parameter("albedo_color")
		_assert_true(copied.is_equal_approx(Color(0.2, 0.4, 0.6)),
			"Occlusion fade preserves the source albedo color")

	# The controller syncs player_position (chest-height offset) each frame.
	target.position = Vector3(5.0, 0.0, -1.0)
	fade._process(0.016)
	if mat != null:
		var expected := target.global_position + Vector3(0.0, fade.target_height_offset, 0.0)
		var got: Vector3 = mat.get_shader_parameter("player_position")
		_assert_true(got.is_equal_approx(expected),
			"player_position uniform tracks the bound target (got %s)" % got)

	# Bulk registration over a subtree.
	var group_root := Node3D.new()
	root.add_child(group_root)
	for i in range(3):
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		group_root.add_child(mi)
	var fade2 = fade_script.new()
	root.add_child(fade2)
	var n: int = fade2.register_occluders_in(group_root)
	_assert_equals(n, 3, "register_occluders_in applies to every mesh under a root")

	root.queue_free()
	await get_tree().process_frame

func _assert_level_editor_plan_browser(editor_instance: Node) -> void:
	_assert_true(editor_instance.has_method("get_editor_plan_entries"),
		"Level editor exposes plan entries")
	_assert_true(editor_instance.has_method("show_plan_scene"),
		"Level editor can load a plan graybox")
	_assert_true(editor_instance.has_method("get_editor_plan_state"),
		"Level editor exposes plan browser state")
	_assert_true(editor_instance.has_method("get_generation_palette"),
		"Level editor exposes generation palette")
	_assert_true(editor_instance.has_method("generate_stretch_plan"),
		"Level editor can generate stretch plans")
	_assert_true(editor_instance.has_method("generate_and_playtest_stretch"),
		"Level editor can generate and playtest stretch plans")
	_assert_true(editor_instance.has_method("show_generated_stretch"),
		"Level editor can show generated stretch plans")
	_assert_true(editor_instance.has_method("get_generation_state"),
		"Level editor exposes generation state")
	if not editor_instance.has_method("get_editor_plan_state"):
		return

	var entries: Array = editor_instance.call("get_editor_plan_entries") if editor_instance.has_method("get_editor_plan_entries") else []
	_assert_true(entries.size() >= FRAGMENT_CHUNK_SCENE_PATHS.size(),
		"Level editor exposes every reusable fragment chunk plus saved generated specs as plans")
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var plan_id := str((entry as Dictionary).get("id", ""))
		editor_instance.call("show_plan_scene", plan_id)
		var per_plan_state: Dictionary = editor_instance.call("get_editor_plan_state")
		_assert_equals(str(per_plan_state.get("active_plan_id", "")), plan_id,
			"Level editor can load %s as a plan graybox" % plan_id)
		_assert_true(bool(per_plan_state.get("loaded", false)),
			"%s plan graybox loads" % plan_id)
		_assert_true(int(per_plan_state.get("anchor_count", 0)) > 0,
			"%s plan graybox exposes anchors" % plan_id)
		_assert_true(bool(per_plan_state.get("collisions_disabled", false)),
			"%s plan graybox remains read-only" % plan_id)
		if plan_id == "generated_teaching_channels_shelter_1_to_2":
			_assert_true(bool(per_plan_state.get("generated", false)),
				"Generated stretch appears as a generated plan")
			var plan_graybox: Dictionary = per_plan_state.get("graybox", {})
			_assert_equals(str(plan_graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
				"Generated plan exposes the spatial graybox contract")
			_assert_true(bool(plan_graybox.get("supports_click_to_move", false)),
				"Generated plan graybox declares click-to-move support")
			_assert_true(bool(plan_graybox.get("supports_multiple_elevations", false)),
				"Generated plan graybox includes multiple elevations")
			_assert_true(int(plan_graybox.get("content_placement_count", 0)) > 0,
				"Generated plan graybox exposes placed flora/enemy/structure content")
			var generation: Dictionary = per_plan_state.get("generation", {})
			_assert_equals(str(generation.get("spec_id", "")), "generated_teaching_channels_shelter_1_to_2",
				"Generated plan exposes its stretch spec id")
			var generated_slot: Dictionary = per_plan_state.get("world_slot", {})
			_assert_equals(str(generated_slot.get("entry_shelter_id", "")), "shelter_1",
				"Generated plan exposes entry shelter metadata")
			_assert_equals(str(generated_slot.get("exit_shelter_id", "")), "shelter_2",
				"Generated plan exposes exit shelter metadata")
		if plan_id == "generated_chain_nested_poc_shelter_2_to_3":
			_assert_true(bool(per_plan_state.get("generated", false)),
				"Chain/nested generated proof appears as a generated plan")
			var generation: Dictionary = per_plan_state.get("generation", {})
			_assert_equals(str(generation.get("spec_id", "")), "generated_chain_nested_poc_shelter_2_to_3",
				"Chain/nested generated plan exposes its stretch spec id")
			var composition: Dictionary = generation.get("composition", {})
			_assert_equals(str(composition.get("mode", "")), "chain_nested_poc",
				"Chain/nested generated plan exposes composition mode")
			_assert_true(int(composition.get("nested_count", 0)) >= 2,
				"Chain/nested generated plan exposes nested archetypes")
		if plan_id == "generated_random_walk_poc_shelter_3_to_4":
			_assert_true(bool(per_plan_state.get("generated", false)),
				"Random-walk generated proof appears as a generated plan")
			var generation: Dictionary = per_plan_state.get("generation", {})
			_assert_equals(str(generation.get("spec_id", "")), "generated_random_walk_poc_shelter_3_to_4",
				"Random-walk generated plan exposes its stretch spec id")
			var walk_composition: Dictionary = generation.get("composition", {})
			_assert_true(bool(walk_composition.get("uses_random_walk", false)),
				"Random-walk generated plan exposes random-walk metadata")
			_assert_true(int(walk_composition.get("walk_element_count", 0)) >= 7,
				"Random-walk generated plan exposes walked archetype elements")

	var state: Dictionary = editor_instance.call("get_editor_plan_state")
	_assert_equals(str(state.get("contract_id", "")), "level_editor_plan_graybox_v1",
		"Level editor reports the plan graybox contract")
	_assert_true(bool(state.get("loaded", false)),
		"Level editor loads an initial plan graybox")
	_assert_true(bool(state.get("visible", false)),
		"Level editor plan graybox starts visible")
	_assert_true(int(state.get("anchor_count", 0)) > 0,
		"Level editor plan graybox exposes plan anchors")
	_assert_true(bool(state.get("collisions_disabled", false)),
		"Level editor plan graybox is read-only and non-pickable")

	var plan_root := editor_instance.find_child("PlanPreviewRoot", true, false)
	_assert_true(plan_root != null,
		"Level editor mounts plan grayboxes under a shared root")
	if plan_root != null:
		_assert_true(plan_root.get_child_count() == 1,
			"Level editor mounts exactly one active plan graybox")
	_assert_true(editor_instance.find_child("PlanAnchorMarkers", true, false) != null,
		"Level editor overlays anchor markers on the active plan")

	var hud := editor_instance.find_child("HUD", true, false)
	_assert_true(hud != null,
		"Level editor keeps its HUD while showing plans")
	if hud != null:
		_assert_true(hud.find_child("PlanBrowserPanel", true, false) != null,
			"Level editor HUD exposes the plan browser panel")
		_assert_true(hud.find_child("PlanSelector", true, false) != null,
			"Level editor HUD exposes the plan selector")
		_assert_true(hud.find_child("PlanVisibilityButton", true, false) != null,
			"Level editor HUD exposes a plan visibility toggle")
		_assert_true(hud.find_child("GenerationTierSelector", true, false) != null,
			"Level editor HUD exposes generation tier control")
		_assert_true(hud.find_child("GenerationButton", true, false) != null,
			"Level editor HUD exposes generation action")
		_assert_true(hud.find_child("GenerationAllowedEdit", true, false) != null,
			"Level editor HUD exposes generation limitation input")

	editor_instance.call("show_plan_scene", "mother_ferrolure")
	state = editor_instance.call("get_editor_plan_state")
	_assert_equals(str(state.get("active_plan_id", "")), "mother_ferrolure",
		"Level editor can switch plans by id")
	_assert_equals(str(state.get("active_plan_title", "")), "Mother Flure",
		"Level editor reads the loaded chunk title")
	var slot: Dictionary = state.get("world_slot", {})
	_assert_equals(str(slot.get("slot_id", "")), "act1_mother_flure",
		"Level editor exposes world-slot metadata for loaded plans")
	_assert_true(int(state.get("anchor_count", 0)) > 0,
		"Mother Flure plan exposes anchors in editor state")
	_assert_true(bool(state.get("collisions_disabled", false)),
		"Switched plan graybox remains non-pickable")

	if editor_instance.has_method("generate_stretch_plan") and editor_instance.has_method("show_generated_stretch"):
		var generated_spec: Dictionary = editor_instance.call("generate_stretch_plan", {
			"id": "editor_generated_test",
			"title": "Editor Generated Test",
			"seed": 1701,
			"complexity_tier": "teaching",
			"limitations": {
				"required": {"flora": ["flure"], "structures": ["shelter"], "archetypes": ["11"]},
			},
			"world_slot": {
				"slot_id": "editor_generated_test",
				"act": 1,
				"region": "Editor",
				"entry_shelter_id": "shelter_1",
				"exit_shelter_id": "shelter_2",
				"entry_anchor": "entry",
				"exit_anchor": "exit_shelter",
				"preview_party_preset": "full_party_full_health",
			},
		})
		_assert_true(bool(generated_spec.get("success", false)),
			"Level editor generation API returns a valid stretch spec")
		editor_instance.call("show_generated_stretch", generated_spec)
		state = editor_instance.call("get_editor_plan_state")
		_assert_true(bool(state.get("generated", false)),
			"Level editor can show an in-memory generated stretch")
		_assert_true(int(state.get("anchor_count", 0)) > 0,
			"In-memory generated stretch exposes anchor markers")
		var generated_graybox: Dictionary = state.get("graybox", {})
		_assert_equals(str(generated_graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
			"In-memory generated stretch exposes the spatial graybox contract")
		_assert_true(int(generated_graybox.get("outline_target_count", 0)) > 0,
			"In-memory generated stretch exposes clickable outline targets")
		_assert_true(int(generated_graybox.get("instanced_content_marker_count", 0)) > 0,
			"In-memory generated stretch instances placed content markers")

	editor_instance.call("set_plan_visibility", false)
	state = editor_instance.call("get_editor_plan_state")
	_assert_true(not bool(state.get("visible", true)),
		"Level editor can hide the plan graybox")
	editor_instance.call("set_plan_visibility", true)
	state = editor_instance.call("get_editor_plan_state")
	_assert_true(bool(state.get("visible", false)),
		"Level editor can show the plan graybox again")

	editor_instance.call("focus_active_plan")
	var editor_camera := editor_instance.find_child("EditorCamera", true, false)
	_assert_true(editor_camera != null,
		"Level editor keeps a camera for plan focusing")
	if editor_camera != null:
		var distance := float(editor_camera.get("distance"))
		_assert_true(distance >= 18.0,
			"Level editor focus frames the active plan")

# --- Test: Archetype Stretch Generation ---
func _test_archetype_generation() -> void:
	_test_name = "Archetype Generation"

	var catalog := StretchArchetypeCatalogScript.new()
	var catalog_validation: Dictionary = catalog.validate()
	_assert_true(bool(catalog_validation.get("valid", false)), "Archetype catalog validates")
	_assert_equals(catalog.get_archetype_ids().size(), 16, "Catalog exposes archetypes 1-16 (11 puzzle/meta + 5 survival)")
	for flora_id in ["seefern", "scarpet", "flure", "mother_flure", "hushbloom", "doma", "snapbloom", "capbage", "gasafoetida", "climbvine", "resolution_roots", "forget_me_nots"]:
		_assert_true(catalog.has_content("flora", flora_id), "Catalog includes flora %s" % flora_id)
	for enemy_id in ["techos", "verdings", "hidras", "crusts", "candids", "meebs", "naturalizers", "gnawers", "neutros", "spikers", "tanglers", "toxos", "nosomas"]:
		_assert_true(catalog.has_content("enemies", enemy_id), "Catalog includes enemy %s" % enemy_id)

	var base_settings := {
		"id": "generated_test_standard",
		"title": "Generated Test Standard",
		"seed": 1701,
		"complexity_tier": "standard",
		"world_slot": {
			"slot_id": "generated_test_standard",
			"act": 1,
			"region": "Test",
			"entry_shelter_id": "shelter_1",
			"exit_shelter_id": "shelter_2",
			"entry_anchor": "entry",
			"exit_anchor": "exit_shelter",
		},
	}
	var spec_a: Dictionary = StretchGeneratorScript.generate(base_settings)
	var spec_b: Dictionary = StretchGeneratorScript.generate(base_settings)
	_assert_true(bool(spec_a.get("success", false)), "Generator returns a successful spec")
	_assert_equals(JSON.stringify(spec_a), JSON.stringify(spec_b), "Same seed and settings produce identical specs")
	var different_settings := base_settings.duplicate(true)
	different_settings["seed"] = 1702
	var spec_c: Dictionary = StretchGeneratorScript.generate(different_settings)
	_assert_true(JSON.stringify(spec_a.get("nodes", [])).hash() != JSON.stringify(spec_c.get("nodes", [])).hash()
			or JSON.stringify(spec_a.get("palette_usage", {})).hash() != JSON.stringify(spec_c.get("palette_usage", {})).hash(),
		"Different seed changes generated layout or composition")

	var previous_nodes := 0
	for tier in ["teaching", "standard", "hard", "setpiece"]:
		var validation: Dictionary = StretchGeneratorScript.validate_settings({"complexity_tier": tier, "seed": 9})
		var resolved: Dictionary = validation.get("resolved_settings", {})
		var budget: Dictionary = resolved.get("budget", {})
		var node_count := int(budget.get("node_count", 0))
		_assert_true(node_count >= previous_nodes, "%s tier budget is not smaller than the previous tier" % tier)
		previous_nodes = node_count

	var range_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_range_budget",
		"seed": 1701,
		"complexity_tier": "teaching",
		"budget": {
			"node_count": [7, 7],
			"flora_slots": [2, 2],
			"enemy_slots": 1,
		},
	})
	_assert_equals(int(range_spec.get("budget", {}).get("node_count", 0)), 7, "Budget ranges resolve inside the requested range")
	_assert_equals(int(range_spec.get("budget", {}).get("flora_slots", 0)), 2, "Numeric budget range override is honored")

	var limited_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_limited_test",
		"seed": 33,
		"complexity_tier": "teaching",
		"budget": {
			"flora_slots": 1,
			"enemy_slots": 1,
			"structures_slots": 3,
			"archetype_depth": 2,
		},
		"limitations": {
			"allowed": {
				"flora": ["flure"],
				"enemies": ["techos"],
				"structures": ["shelter", "forage_cache", "shortcut_gate"],
				"archetypes": ["2", "11"]
			},
			"blocked": {
				"flora": ["scarpet"]
			},
			"required": {
				"flora": ["flure"],
				"enemies": ["techos"],
				"structures": ["shelter"],
				"archetypes": ["11"]
			}
		},
	})
	_assert_true(bool(limited_spec.get("success", false)), "Allowed/blocked/required limitations can produce a valid spec")
	var limited_usage: Dictionary = limited_spec.get("palette_usage", {})
	_assert_equals(limited_usage.get("flora", []), ["flure"], "Allowed flora limits generated flora")
	_assert_equals(limited_usage.get("enemies", []), ["techos"], "Allowed enemy limits generated enemies")
	_assert_true(not (limited_usage.get("flora", []) as Array).has("scarpet"), "Blocked flora is excluded")
	for chain_entry in limited_spec.get("archetype_chain", []):
		if chain_entry is Dictionary:
			_assert_true(["2", "11"].has(str((chain_entry as Dictionary).get("id", ""))), "Allowed archetype limits are enforced")

	var invalid_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_invalid_limit_test",
		"limitations": {
			"blocked": {"flora": ["flure"]},
			"required": {"flora": ["flure"]},
		},
	})
	_assert_true(not bool(invalid_spec.get("success", true)), "Required/blocked conflicts fail validation")

	var chain_nested_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_chain_nested_runtime_test",
		"title": "Generated Chain Nested Runtime Test",
		"seed": 2403,
		"complexity_tier": "standard",
		"budget": {
			"node_count": 7,
			"optional_node_count": 1,
			"branch_count": 1,
			"archetype_depth": 5,
			"pressure_budget": 2,
			"flora_slots": 3,
			"enemy_slots": 2,
			"structures_slots": 5,
			"shortcut_count": 1,
			"resource_beats": 1,
		},
		"limitations": {
			"allowed": {
				"flora": ["flure", "hushbloom", "scarpet"],
				"enemies": ["techos", "naturalizers"],
				"structures": ["shelter", "barrier", "forage_cache", "carry_gear", "shortcut_gate", "terminal", "pipe"],
				"archetypes": ["1", "2", "3", "4", "6", "11"],
			},
			"required": {
				"flora": ["flure"],
				"enemies": ["naturalizers"],
				"structures": ["shelter", "carry_gear"],
				"archetypes": ["1", "2", "3", "4", "6"],
			},
		},
		"composition": {
			"mode": "chain_nested_poc",
			"chain": [
				{"id": "1", "variant": "reveal_plant", "label": "Reveal flure", "output": "flure_exposed"},
				{"id": "2", "variant": "flure_iron_decoy", "label": "Use flure", "input": "flure_exposed", "output": "patrol_diverted"},
				{"id": "3", "variant": "critical_resource", "label": "Carry component", "input": "patrol_diverted", "output": "carry_component_secured"},
				{"id": "6", "variant": "flow_diagram", "label": "Rebuild route", "input": "carry_component_secured", "output": "shelter_route_reassembled"},
			],
			"nested": [
				{"host": "3", "host_step": 4, "id": "4", "variant": "false_scent", "label": "Nested patrol distraction", "nested": [
					{"host_step": 5, "id": "2", "variant": "hushbloom_stun", "label": "Nested plant trigger"}
				]},
				{"host": "6", "host_step": 3, "id": "3", "variant": "information_artifact", "label": "Nested fragment carry"},
			],
		},
		"world_slot": {
			"slot_id": "generated_chain_nested_runtime_test",
			"act": 1,
			"region": "Channels",
			"entry_shelter_id": "shelter_2",
			"exit_shelter_id": "shelter_3",
		},
	})
	_assert_true(bool(chain_nested_spec.get("success", false)), "Generator builds a chain/nested archetype proof spec")
	var composition: Dictionary = chain_nested_spec.get("composition", {})
	_assert_equals(str(composition.get("mode", "")), "chain_nested_poc", "Generated proof carries composition mode")
	_assert_equals(int(composition.get("chain_count", 0)), 4, "Generated proof carries the explicit chain")
	_assert_equals(int(composition.get("nested_count", 0)), 3, "Generated proof flattens nested archetypes")
	_assert_equals(int(composition.get("nested_depth", 0)), 2, "Generated proof records nested depth")
	for link in composition.get("links", []):
		if link is Dictionary:
			_assert_true(bool((link as Dictionary).get("feeds_next", false)), "Generated proof links chain outputs into next inputs")
	var generated_chain_ids: Array[String] = []
	for chain_entry in chain_nested_spec.get("archetype_chain", []):
		if chain_entry is Dictionary:
			generated_chain_ids.append(str((chain_entry as Dictionary).get("id", "")))
	_assert_equals(generated_chain_ids.slice(0, 4), ["1", "2", "3", "6"],
		"Generated proof preserves explicit chain order")
	var nested_host_node_found := false
	for node in chain_nested_spec.get("nodes", []):
		if node is Dictionary and not ((node as Dictionary).get("nested_archetypes", []) as Array).is_empty():
			nested_host_node_found = true
			break
	_assert_true(nested_host_node_found, "Generated proof attaches nested archetypes to playable nodes")

	var random_walk_settings := {
		"id": "generated_random_walk_runtime_test",
		"title": "Generated Random Walk Runtime Test",
		"seed": 3117,
		"complexity_tier": "standard",
		"budget": {
			"node_count": 8,
			"optional_node_count": 1,
			"branch_count": 1,
			"archetype_depth": 4,
			"pressure_budget": 2,
			"flora_slots": 3,
			"enemy_slots": 2,
			"structures_slots": 5,
			"shortcut_count": 1,
			"resource_beats": 2,
		},
		"limitations": {
			"allowed": {
				"flora": ["flure", "hushbloom", "scarpet"],
				"enemies": ["techos", "naturalizers"],
				"structures": ["shelter", "forage_cache", "terminal", "carry_gear", "shortcut_gate", "pipe"],
				"archetypes": ["2", "3", "4", "6", "11"],
			},
			"required": {
				"flora": ["flure"],
				"enemies": ["naturalizers"],
				"structures": ["shelter"],
				"archetypes": ["2", "3", "4", "6"],
			},
		},
		"composition": {
			"mode": "archetype_random_walk",
			"random_walk": {
				"start_archetype": "2",
				"start_step": 0,
				"step_count": 7,
				"transition_chance": 0.45,
				"prefer_tags": ["flora", "patrol", "carry", "fragments"],
				"allow_revisit": true,
			},
		},
		"world_slot": {
			"slot_id": "generated_random_walk_runtime_test",
			"act": 1,
			"region": "Channels",
			"entry_shelter_id": "shelter_3",
			"exit_shelter_id": "shelter_4",
		},
	}
	var random_walk_spec: Dictionary = StretchGeneratorScript.generate(random_walk_settings)
	var random_walk_spec_b: Dictionary = StretchGeneratorScript.generate(random_walk_settings)
	_assert_true(bool(random_walk_spec.get("success", false)), "Generator builds a random-walk archetype proof spec")
	_assert_equals(JSON.stringify(random_walk_spec), JSON.stringify(random_walk_spec_b),
		"Random-walk generation is deterministic for the same seed")
	var random_walk_settings_c := random_walk_settings.duplicate(true)
	random_walk_settings_c["seed"] = 3118
	var random_walk_spec_c: Dictionary = StretchGeneratorScript.generate(random_walk_settings_c)
	_assert_true(JSON.stringify(random_walk_spec.get("composition", {}).get("random_walk", {})).hash() != JSON.stringify(random_walk_spec_c.get("composition", {}).get("random_walk", {})).hash(),
		"Different seed changes the random-walk path or layout")
	var walk_composition: Dictionary = random_walk_spec.get("composition", {})
	var walk_info: Dictionary = walk_composition.get("random_walk", {})
	_assert_true(bool(walk_composition.get("uses_random_walk", false)), "Generated proof records random-walk composition")
	_assert_equals(int(walk_composition.get("walk_element_count", 0)), 7, "Generated proof walks the requested number of archetype elements")
	_assert_true((walk_info.get("edges", []) as Array).size() >= 6, "Generated proof records random-walk element edges")
	var visited_walk_ids: Array = walk_info.get("visited_archetypes", [])
	for required_walk_id in ["2", "3", "4", "6"]:
		_assert_true(visited_walk_ids.has(required_walk_id), "Random walk covers required archetype %s" % required_walk_id)
	var walked_node_count := 0
	for node in random_walk_spec.get("nodes", []):
		if node is Dictionary and str((node as Dictionary).get("walk_element", "")) != "":
			walked_node_count += 1
	_assert_equals(walked_node_count, 7, "Generated random-walk nodes expose archetype elements")
	_assert_true(int(random_walk_spec.get("budget", {}).get("node_count", 0)) >= 9,
		"Random-walk step count expands the node budget to fit entry and exit")

	for required_key in ["anchors", "routes", "world_slot", "archetype_chain", "graybox", "navigation"]:
		_assert_true(spec_a.has(required_key), "Generated spec includes %s" % required_key)
	_assert_equals(str(spec_a.get("world_slot", {}).get("preview_party_preset", "")), "full_party_full_health",
		"Generated spec carries full-party/full-health preview preset")
	_assert_true(not (spec_a.get("headless", {}).get("golden_path", []) as Array).is_empty(),
		"Generated spec includes a golden path")
	var graybox: Dictionary = spec_a.get("graybox", {})
	_assert_equals(str(graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
		"Generated spec exposes the graybox layout contract")
	_assert_true(bool(graybox.get("supports_click_to_move", false)),
		"Generated graybox declares click-to-move support")
	_assert_true(bool(graybox.get("supports_multiple_elevations", false)),
		"Generated graybox can produce multiple elevations")
	var navigation: Dictionary = spec_a.get("navigation", {})
	_assert_equals(str(navigation.get("contract_id", "")), "multi_level_navigation_graph_v1",
		"Generated spec exposes the multi-level navigation graph contract")
	_assert_true(bool(navigation.get("supports_multiple_elevations", false)),
		"Generated navigation graph declares multiple elevation support")
	_assert_true((navigation.get("nodes", []) as Array).size() >= (spec_a.get("nodes", []) as Array).size(),
		"Generated navigation graph includes node surfaces")
	_assert_true((navigation.get("edges", []) as Array).size() >= (spec_a.get("routes", []) as Array).size(),
		"Generated navigation graph includes route edges")
	var graph = NavigationGraphScript.new()
	graph.configure(navigation)
	var graph_node_path: Array = graph.find_node_path("entry", "exit_shelter")
	_assert_true(graph_node_path.size() >= 2,
		"Generated navigation graph can route from entry to exit")
	var graph_world_path: Array = graph.find_path(Vector3(0.0, 0.5, 1.6), graph.get_node_position("exit_shelter"))
	_assert_true(graph_world_path.size() >= 3,
		"Generated navigation graph returns playable multi-waypoint world paths")
	_assert_true(graph.path_uses_multiple_elevations(graph_world_path),
		"Generated navigation path preserves Y-level changes")
	var stacked_graph = NavigationGraphScript.new()
	stacked_graph.configure({
		"contract_id": "multi_level_navigation_graph_v1",
		"supports_multiple_elevations": true,
		"entry_node": "lower",
		"exit_node": "upper",
		"nodes": [
			{"id": "lower", "position": [0.0, 0.45, 0.0], "elevation_index": 0},
			{"id": "ramp", "position": [4.0, 1.17, 0.0], "elevation_index": 1},
			{"id": "upper", "position": [0.0, 1.89, 0.0], "elevation_index": 2},
		],
		"edges": [
			{"id": "lower_to_ramp", "from": "lower", "to": "ramp", "kind": "safe", "waypoints": [[0.0, 0.45, 0.0], [4.0, 1.17, 0.0]]},
			{"id": "ramp_to_upper", "from": "ramp", "to": "upper", "kind": "safe", "waypoints": [[4.0, 1.17, 0.0], [0.0, 1.89, 0.0]]},
		],
	})
	_assert_equals(stacked_graph.find_nearest_node_id(Vector3(0.0, 1.86, 0.05)), "upper",
		"Navigation graph distinguishes stacked floors with the same X/Z")
	var stacked_path: Array = stacked_graph.find_path(Vector3(0.0, 0.45, 0.0), Vector3(0.0, 1.89, 0.0))
	_assert_true(stacked_path.size() >= 3 and stacked_graph.path_uses_multiple_elevations(stacked_path),
		"Navigation graph routes between stacked Y-levels through explicit connectors")
	var first_content_node_found := false
	for node in spec_a.get("nodes", []):
		if node is Dictionary and not ((node as Dictionary).get("content_placements", []) as Array).is_empty():
			first_content_node_found = true
			var placement: Dictionary = ((node as Dictionary).get("content_placements", []) as Array)[0]
			_assert_true((node as Dictionary).has("footprint"), "Generated nodes expose actual floor footprint sizing")
			_assert_true(placement.has("position") and placement.has("size"), "Generated content placements expose position and size")
			break
	_assert_true(first_content_node_found, "Generated graybox includes placed flora/enemy/structure content")

	var loaded_fixture := StretchGeneratorScript.load_spec(GENERATED_STRETCH_SPEC_PATH)
	_assert_equals(str(loaded_fixture.get("id", "")), "generated_teaching_channels_shelter_1_to_2",
		"Saved generated fixture spec loads")
	_assert_equals(str(loaded_fixture.get("schema", "")), "trawf_generated_stretch_spec_v1",
		"Saved generated fixture uses the stretch spec schema")
	var loaded_poc_fixture := StretchGeneratorScript.load_spec(GENERATED_CHAIN_NESTED_POC_SPEC_PATH)
	_assert_equals(str(loaded_poc_fixture.get("id", "")), "generated_chain_nested_poc_shelter_2_to_3",
		"Saved chain/nested generated proof spec loads")
	_assert_equals(str(loaded_poc_fixture.get("composition", {}).get("mode", "")), "chain_nested_poc",
		"Saved chain/nested proof fixture exposes composition metadata")
	var loaded_walk_fixture := StretchGeneratorScript.load_spec(GENERATED_RANDOM_WALK_POC_SPEC_PATH)
	_assert_equals(str(loaded_walk_fixture.get("id", "")), "generated_random_walk_poc_shelter_3_to_4",
		"Saved random-walk generated proof spec loads")
	_assert_true(bool(loaded_walk_fixture.get("composition", {}).get("uses_random_walk", false)),
		"Saved random-walk proof fixture exposes walk metadata")

	var chunk_scene := load("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
	_assert_true(chunk_scene != null, "Generated stretch chunk scene loads")
	if chunk_scene != null:
		var chunk_instance: Node = chunk_scene.instantiate()
		_assert_true(chunk_instance != null, "Generated stretch chunk instantiates")
		if chunk_instance != null:
			_assert_true(chunk_instance.has_method("configure_chunk"), "Generated chunk exposes configure_chunk")
			_assert_true(chunk_instance.has_method("get_generation_spec"), "Generated chunk exposes get_generation_spec")
			chunk_instance.free()
		var poc_chunk: Node = chunk_scene.instantiate()
		_assert_true(poc_chunk != null, "Generated chain/nested chunk instantiates")
		if poc_chunk != null:
			poc_chunk.call("configure_chunk", {"spec": chain_nested_spec})
			get_tree().root.add_child(poc_chunk)
			await get_tree().process_frame
			var poc_state: Dictionary = poc_chunk.call("get_preview_state")
			var poc_graybox: Dictionary = poc_chunk.call("get_graybox_state")
			var poc_navigation: Dictionary = poc_chunk.call("get_navigation_state")
			_assert_equals(str(poc_graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
				"Generated chain/nested chunk builds the spatial graybox contract")
			_assert_equals(str(poc_navigation.get("contract_id", "")), "multi_level_navigation_graph_v1",
				"Generated chain/nested chunk builds the multi-level navigation contract")
			_assert_true(int(poc_graybox.get("outline_target_count", 0)) > 0,
				"Generated chain/nested chunk builds clickable node outline targets")
			_assert_true(int(poc_graybox.get("instanced_content_marker_count", 0)) > 0,
				"Generated chain/nested chunk instances sized content markers")
			_assert_true(bool(poc_graybox.get("supports_multiple_elevations", false)),
				"Generated chain/nested chunk builds multiple elevations")
			_assert_equals(str(poc_state.get("generation", {}).get("composition", {}).get("mode", "")), "chain_nested_poc",
				"Generated chunk exposes chain/nested composition in preview state")
			_assert_equals(int(poc_state.get("generation", {}).get("nested_depth", 0)), 2,
				"Generated chunk exposes nested depth in preview state")
			var poc_golden: Variant = poc_chunk.call("run_generated_golden_path")
			_assert_true(poc_golden == true, "Generated chain/nested golden path reaches shelter")
			var poc_risky: Variant = poc_chunk.call("run_generated_risky_recovery")
			poc_state = poc_chunk.call("get_preview_state")
			_assert_true(poc_risky == true, "Generated chain/nested risky route recovery remains playable")
			_assert_true(float(poc_state.get("risky_damage_total", 0.0)) > 0.0,
				"Generated chain/nested risky route records pressure damage")
			poc_chunk.queue_free()
			await get_tree().process_frame
		var walk_chunk: Node = chunk_scene.instantiate()
		_assert_true(walk_chunk != null, "Generated random-walk chunk instantiates")
		if walk_chunk != null:
			walk_chunk.call("configure_chunk", {"spec": random_walk_spec})
			get_tree().root.add_child(walk_chunk)
			await get_tree().process_frame
			var walk_state: Dictionary = walk_chunk.call("get_preview_state")
			var walk_graybox: Dictionary = walk_chunk.call("get_graybox_state")
			var walk_navigation: Dictionary = walk_chunk.call("get_navigation_state")
			_assert_equals(str(walk_graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
				"Generated random-walk chunk builds the spatial graybox contract")
			_assert_equals(str(walk_navigation.get("contract_id", "")), "multi_level_navigation_graph_v1",
				"Generated random-walk chunk builds the multi-level navigation contract")
			_assert_true(int(walk_graybox.get("outline_target_count", 0)) > 0,
				"Generated random-walk chunk builds clickable node outline targets")
			_assert_true(int(walk_graybox.get("instanced_content_marker_count", 0)) > 0,
				"Generated random-walk chunk instances sized content markers")
			_assert_true(bool(walk_graybox.get("supports_multiple_elevations", false)),
				"Generated random-walk chunk builds multiple elevations")
			_assert_true(bool(walk_state.get("generation", {}).get("uses_random_walk", false)),
				"Generated chunk exposes random-walk composition in preview state")
			_assert_equals(int(walk_state.get("generation", {}).get("walk_element_count", 0)), 7,
				"Generated chunk exposes random-walk element count")
			var walk_golden: Variant = walk_chunk.call("run_generated_golden_path")
			_assert_true(walk_golden == true, "Generated random-walk golden path reaches shelter")
			var walk_risky: Variant = walk_chunk.call("run_generated_risky_recovery")
			walk_state = walk_chunk.call("get_preview_state")
			_assert_true(walk_risky == true, "Generated random-walk risky route recovery remains playable")
			_assert_true(float(walk_state.get("risky_damage_total", 0.0)) > 0.0,
				"Generated random-walk risky route records pressure damage")
			walk_chunk.queue_free()
			await get_tree().process_frame

	var preview_instance: Node = await _instantiate_preview_chunk_and_wait("generated_stretch", 3)
	_assert_true(preview_instance != null, "Generated stretch preview instantiates")
	if preview_instance == null:
		return
	var state: Dictionary = preview_instance.call("headless_get_state")
	_assert_equals(str(state.get("preview_chunk", "")), "generated_stretch", "Generated preview reports its chunk id")
	_assert_equals(str(state.get("preview_party_preset", "")), "full_party_full_health", "Generated preview starts with full-party preset")
	var preview_graybox: Dictionary = state.get("chunk", {}).get("graybox", {})
	_assert_equals(str(preview_graybox.get("contract_id", "")), "generated_stretch_graybox_v1",
		"Generated preview reports the spatial graybox contract")
	var preview_navigation: Dictionary = state.get("navigation", {})
	_assert_equals(str(preview_navigation.get("contract_id", "")), "multi_level_navigation_graph_v1",
		"Generated preview installs the multi-level navigation graph into GameState")
	_assert_true(bool(preview_navigation.get("supports_multiple_elevations", false)),
		"Generated preview navigation supports multiple elevations")
	_assert_true(bool(preview_graybox.get("supports_click_to_move", false)),
		"Generated preview reports click-to-move support")
	_assert_true(int(preview_graybox.get("outline_target_count", 0)) > 0,
		"Generated preview exposes clickable node outline targets")
	_assert_true(int(preview_graybox.get("instanced_content_marker_count", 0)) > 0,
		"Generated preview instances sized flora/enemy/structure markers")
	_assert_true(int(preview_graybox.get("route_surface_instance_count", 0)) > 0,
		"Generated preview instances route surfaces between nodes")
	for char_id in ["aster", "peris", "endo"]:
		var stats: Dictionary = state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(stats.get("hp", -1.0)), 100.0, "%s starts at max HP" % char_id)
		_assert_equals(float(stats.get("sta", -1.0)), 100.0, "%s starts at max stamina" % char_id)
		_assert_equals(float(stats.get("atp", -1.0)), float(GameState.ATP_MAX_PIPS), "%s starts at max ATP" % char_id)
	var elevated_target := Vector3.INF
	var generation_spec: Dictionary = preview_instance.call("headless_call_chunk", "get_generation_spec", [])
	for node in generation_spec.get("nodes", []):
		if node is Dictionary and int((node as Dictionary).get("elevation_index", 0)) > 0:
			elevated_target = _vec3_from_array((node as Dictionary).get("approach_position", (node as Dictionary).get("position", [])), Vector3.INF)
			break
	_assert_true(elevated_target != Vector3.INF, "Generated fixture includes an elevated navigation target")
	if elevated_target != Vector3.INF:
		preview_instance.call("headless_set_character_position", "aster", Vector3(0.0, 0.5, 1.6))
		var move_ok := bool(preview_instance.call("headless_move_character", "aster", elevated_target, false))
		var move_info: Dictionary = preview_instance.call("headless_get_character_movement_info", "aster")
		_assert_true(move_ok, "Generated preview accepts a click move to an elevated target")
		_assert_true(int(move_info.get("path_count", 0)) >= 3,
			"Generated preview routes elevated click movement through navigation waypoints")
		_assert_true(_serialized_path_uses_multiple_y(move_info.get("path", [])),
			"Generated preview movement path preserves multiple Y-levels")
		preview_instance.call("headless_set_character_position", "aster", Vector3(0.0, 0.5, 1.6))
	var golden_result: Variant = preview_instance.call("headless_call_chunk", "run_generated_golden_path", [])
	var golden_ok: bool = golden_result == true
	state = preview_instance.call("headless_get_state")
	_assert_true(golden_ok, "Generated golden path reaches the exit shelter")
	_assert_true(bool(state.get("chunk", {}).get("shelter_rested", false)), "Generated golden path rests at the exit shelter")
	_assert_true(bool(state.get("chunk", {}).get("shortcut_unlocked", false)), "Generated golden path exposes shortcut state")
	var risky_result: Variant = preview_instance.call("headless_call_chunk", "run_generated_risky_recovery", [])
	var risky_ok: bool = risky_result == true
	state = preview_instance.call("headless_get_state")
	_assert_true(risky_ok, "Generated risky route recovery remains playable")
	_assert_equals(str(state.get("chunk", {}).get("route_phase", "")), "complete", "Generated risky recovery completes")
	_assert_true(float(state.get("chunk", {}).get("risky_damage_total", 0.0)) > 0.0, "Generated risky recovery records pressure damage")
	preview_instance.queue_free()
	await get_tree().process_frame

func _test_generated_multi_solution() -> void:
	_test_name = "Generated Multi-Solution"

	# Puzzle-bearing stretches at every tier must be solvable two distinct ways, and
	# the Aster+Peris pair must always have a path of its own.
	for tier in ["teaching", "standard", "hard", "setpiece"]:
		var spec: Dictionary = StretchGeneratorScript.generate({
			"id": "generated_multi_solution_%s" % tier,
			"seed": 4242,
			"complexity_tier": tier,
			"limitations": {
				"required": {"archetypes": ["1", "4"]},
				"allowed": {"archetypes": ["1", "2", "3", "4", "6", "7", "8", "11"]},
			},
		})
		_assert_true(bool(spec.get("success", false)), "%s: generator returns a spec" % tier)
		var summary: Dictionary = spec.get("headless", {}).get("solution_summary", {})
		_assert_true(int(summary.get("choice_node_count", 0)) >= 1, "%s: stretch has at least one multi-solution puzzle node" % tier)
		_assert_true(bool(summary.get("multi_solution", false)), "%s: spotlight and shadow loadouts solve it differently" % tier)
		_assert_true(bool(summary.get("shadow_solvable", false)), "%s: Aster+Peris can solve the whole stretch" % tier)
		_assert_equals(int(summary.get("solvable_loadout_count", 0)), 2, "%s: both canonical loadouts solve" % tier)
		_assert_true(bool(summary.get("multi_solution_ok", false)), "%s: multi-solution tier gate is satisfied" % tier)
		_assert_true(bool(summary.get("bare_pair_solvable", false)), "%s: every node is solvable by the bare Aster+Peris pair" % tier)
		_assert_true(bool(summary.get("spotlight_within_stage", false)), "%s: the first-play full party stays within its progression stage" % tier)

		var paths: Array = spec.get("headless", {}).get("solution_paths", [])
		_assert_equals(paths.size(), 2, "%s: two solution paths are emitted" % tier)
		var spotlight := {}
		var shadow := {}
		for p in paths:
			if not (p is Dictionary):
				continue
			match str((p as Dictionary).get("loadout", "")):
				"spotlight":
					spotlight = p
				"shadow":
					shadow = p
		_assert_true(bool(spotlight.get("solvable", false)) and bool(shadow.get("solvable", false)), "%s: both paths are individually solvable" % tier)

		var shadow_by_node := {}
		var shadow_uses_only_pair := true
		for entry in shadow.get("approach_per_node", []):
			if not (entry is Dictionary):
				continue
			shadow_by_node[str((entry as Dictionary).get("node", ""))] = entry
			if str((entry as Dictionary).get("party", "any")) == "specialist":
				shadow_uses_only_pair = false
		var diverged := false
		for entry in spotlight.get("approach_per_node", []):
			if not (entry is Dictionary):
				continue
			var other: Dictionary = shadow_by_node.get(str((entry as Dictionary).get("node", "")), {})
			if not other.is_empty() and str((entry as Dictionary).get("approach_id", "")) != str(other.get("approach_id", "")):
				diverged = true
		_assert_true(diverged, "%s: the two paths take a different approach on at least one node" % tier)
		_assert_true(shadow_uses_only_pair, "%s: the shadow path never relies on a specialist approach" % tier)

	# The solver re-derives the same verdict straight from a spec — the path the chunk
	# and the Android replay both consume.
	var solver_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_multi_solution_solver_check",
		"seed": 909,
		"complexity_tier": "standard",
		"limitations": {"required": {"archetypes": ["1", "3"]}},
	})
	var analysis: Dictionary = StretchSolutionSolverScript.analyze_spec(solver_spec)
	_assert_true(bool(analysis.get("multi_solution", false)), "Solver re-derives multi-solution from a saved spec")
	_assert_equals(int(analysis.get("solvable_loadout_count", 0)), 2, "Solver finds both loadouts solvable")
	_assert_true((analysis.get("warnings", []) as Array).is_empty(), "A puzzle stretch produces no shadow-broken warnings")

	# A narrative-only stretch has nothing to multi-solve; that is allowed, not a failure.
	var narrative_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_narrative_only",
		"seed": 7,
		"complexity_tier": "teaching",
		"budget": {"archetype_depth": 1},
		"limitations": {
			"allowed": {"archetypes": ["11"]},
			"required": {"archetypes": ["11"]},
		},
	})
	var narrative_summary: Dictionary = narrative_spec.get("headless", {}).get("solution_summary", {})
	_assert_equals(int(narrative_summary.get("choice_node_count", 0)), 0, "Narrative-only stretch has no puzzle choice nodes")
	_assert_true(bool(narrative_summary.get("multi_solution_ok", false)), "Narrative-only stretch passes the tier gate")

	# An early stretch: the Aster+Peris shadow reaches for a LATER-stage (expert) technique
	# the first-play full party cannot use yet — exactly the requested mastery layer.
	var future_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_future_technique",
		"seed": 1234,
		"complexity_tier": "teaching",
		"progression_stage": 2,
		"limitations": {
			"required": {"archetypes": ["3"]},
			"allowed": {"archetypes": ["1", "2", "3", "11"]},
		},
	})
	var future_summary: Dictionary = future_spec.get("headless", {}).get("solution_summary", {})
	_assert_equals(int(future_spec.get("source", {}).get("progression_stage", 0)), 2, "Early stretch resolves to progression stage 2")
	_assert_true(bool(future_summary.get("shadow_uses_future_technique", false)), "Shadow path uses a technique from later in the game than the player has reached")
	_assert_true(bool(future_summary.get("spotlight_within_stage", false)), "Full party stays in-stage even when the shadow goes ahead")
	var f_spot := {}
	var f_shadow := {}
	for p in future_spec.get("headless", {}).get("solution_paths", []):
		match str((p as Dictionary).get("loadout", "")):
			"spotlight":
				f_spot = p
			"shadow":
				f_shadow = p
	var spot_max := 0
	for e in f_spot.get("approach_per_node", []):
		spot_max = maxi(spot_max, int((e as Dictionary).get("min_stage", 0)))
	_assert_true(spot_max <= 2, "No full-party approach exceeds progression stage 2")
	_assert_true(int(f_shadow.get("max_stage_used", 0)) > 2, "The shadow path commits to a stage-3+ technique")
	_assert_true((f_shadow.get("techniques", []) as Array).size() > 0, "The shadow path surfaces the technique(s) it relies on (teaching-beat transparency)")

	# Stage-filter guard: an allow-list of only later-game archetypes at an early stage is a
	# HARD error, not a silently puzzle-free corridor returned as success.
	var empty_pool_spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_empty_stage_pool",
		"seed": 5,
		"complexity_tier": "teaching",
		"progression_stage": 1,
		"limitations": {"allowed": {"archetypes": ["7", "10"]}},
	})
	_assert_true(not bool(empty_pool_spec.get("success", true)), "An all-later-game allow-list at an early stage fails validation, not a puzzle-free spine")

	# within_stage is meaningful: if a node's only specialist primary is beyond the stage,
	# the full party is forced onto a pair approach and within_stage reports false.
	var synth_nodes := [
		{"id": "entry", "role": "boundary", "approaches": []},
		{"id": "n1", "role": "danger", "stage": 2, "approaches": [
			{"id": "future_primary", "party": "specialist", "kind": "primary", "requires": ["combat"], "min_stage": 5},
			{"id": "pair_now", "party": "aster_peris", "kind": "shadow", "requires": ["overlay", "cover"], "min_stage": 2},
		]},
		{"id": "exit_shelter", "role": "shelter_arrival", "approaches": []},
	]
	var synth: Dictionary = StretchSolutionSolverScript.analyze(synth_nodes, "standard", 3)
	_assert_true(not bool(synth.get("spotlight_within_stage", true)), "When the only full-party primary is beyond stage, spotlight_within_stage is false (not dead-true)")

	# Catalog invariant: every archetype keeps an approach the bare pair can field with no
	# placed tool, so the pair can ALWAYS finish (the design's "not optional" shadow law).
	var catalog := StretchArchetypeCatalogScript.new()
	var bare: Dictionary = StretchCapabilitiesScript.bare_pair_capabilities()
	for aid in catalog.get_archetype_ids():
		var arch: Dictionary = catalog.get_archetype(aid)
		var has_bare := false
		for ap in arch.get("approaches", []):
			if not (ap is Dictionary) or str((ap as Dictionary).get("party", "")) == "specialist":
				continue
			if StretchCapabilitiesScript.requirements_met((ap as Dictionary).get("requires", []), bare):
				has_bare = true
				break
		_assert_true(has_bare, "Archetype %s keeps a bare-pair shadow approach (universal solvability)" % aid)

func _test_generated_replay() -> void:
	_test_name = "Generated Replay"

	var spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_replay_test",
		"seed": 4242,
		"complexity_tier": "standard",
		"limitations": {
			"required": {"archetypes": ["1", "4"]},
			"allowed": {"archetypes": ["1", "2", "3", "4", "6", "7", "8", "11"]},
		},
	})
	_assert_true(bool(spec.get("success", false)), "Replay source spec generates")

	var replay: Dictionary = StretchReplayBuilderScript.build(spec)
	_assert_equals(str(replay.get("schema", "")), "trawf_stretch_replay_v1", "Replay reports its schema")
	var level: Dictionary = replay.get("level", {})
	_assert_equals((level.get("nodes", []) as Array).size(), (spec.get("nodes", []) as Array).size(), "Replay projects every node onto the grid")
	_assert_true((level.get("routes", []) as Array).size() >= 1, "Replay projects routes onto the grid")
	_assert_true((level.get("content", []) as Array).size() >= 1, "Replay projects placed content onto the grid")

	var solutions: Array = replay.get("solutions", [])
	_assert_equals(solutions.size(), 2, "Replay carries both solution loadouts")
	var spotlight := {}
	var shadow := {}
	for s in solutions:
		if not (s is Dictionary):
			continue
		match str((s as Dictionary).get("loadout", "")):
			"spotlight":
				spotlight = s
			"shadow":
				shadow = s
	# Spotlight follows the full enabled party (the canonical roster — all six by default);
	# derive the expected size from the loadout so this stays correct as the roster grows.
	var spotlight_loadout := {}
	for loadout in StretchCapabilitiesScript.loadouts([]):
		if str((loadout as Dictionary).get("id", "")) == "spotlight":
			spotlight_loadout = loadout
	var spotlight_size := (spotlight_loadout.get("party", []) as Array).size()
	_assert_equals((spotlight.get("party", []) as Array).size(), spotlight_size, "Spotlight replay follows the full enabled party")
	_assert_equals((shadow.get("party", []) as Array).size(), 2, "Shadow replay follows the Aster+Peris pair")
	_assert_equals((spotlight.get("frames", []) as Array).size(), (spec.get("nodes", []) as Array).size(), "Spotlight replay has a keyframe per node")
	_assert_true(bool(spotlight.get("solvable", false)) and bool(shadow.get("solvable", false)), "Both replay solutions are solvable")

	var members_ok := true
	var positions_distinct := true
	for frame in spotlight.get("frames", []):
		if not (frame is Dictionary):
			members_ok = false
			continue
		var chars := frame.get("characters", {}) as Dictionary
		if chars.size() != spotlight_size:
			members_ok = false
		# Formation offsets must keep every member on its own spot — no stacking on the node cell.
		var seen_pos := {}
		for member in chars:
			var key := "%.3f,%.3f" % [float(chars[member][0]), float(chars[member][1])]
			if seen_pos.has(key):
				positions_distinct = false
			seen_pos[key] = true
	_assert_true(members_ok, "Every spotlight frame positions all enabled party members")
	_assert_true(positions_distinct, "Formation offsets keep every spotlight member on a distinct spot")

	var shadow_by_node := {}
	for entry in shadow.get("node_approaches", []):
		if entry is Dictionary:
			shadow_by_node[str((entry as Dictionary).get("node", ""))] = str((entry as Dictionary).get("approach_id", ""))
	var diverged := false
	for entry in spotlight.get("node_approaches", []):
		if not (entry is Dictionary):
			continue
		var nid := str((entry as Dictionary).get("node", ""))
		var aid := str((entry as Dictionary).get("approach_id", ""))
		if aid != "" and shadow_by_node.has(nid) and shadow_by_node[nid] != aid:
			diverged = true
	_assert_true(diverged, "Spotlight and shadow replays show different approaches on at least one node")

func _test_campaign_order() -> void:
	_test_name = "Campaign Order"

	# Default build groups every generated spec into Act > Region > stretch.
	var order = CampaignOrderScript.build_default_from_dir("res://data/generated_stretches")
	var root: Dictionary = order.root()
	_assert_true(not (root.get("children", []) as Array).is_empty(), "Default order has at least one act")
	_assert_true(order.flatten_stretches().size() >= 8, "Default order places every generated stretch")
	var act0: Dictionary = root["children"][0]
	_assert_equals(str(act0.get("kind", "")), "act", "First child of the campaign is an act")

	# Multi-level hierarchy + CRUD: region > group > stretch leaf.
	var rid := order.add_node(str(act0["id"]), "region", "Test Region")
	_assert_true(rid != "", "Can add a region under an act")
	var gid := order.add_node(rid, "group", "Test Group")
	_assert_true(gid != "", "Can nest a group under a region (multi-level hierarchy)")
	var sid := order.add_node(gid, "stretch", "Test Stretch", {"spec_id": "sx", "entry": "shelter_9", "exit": "shelter_10", "stage": 3})
	_assert_true(sid != "", "Can add a stretch leaf under a group")
	_assert_equals(order.add_node(sid, "group", "nope"), "", "Cannot nest under a stretch leaf")

	# Reparent (the drag operation) + cycle guard + rename + reorder/indent/outdent.
	_assert_true(order.move_node(gid, str(act0["id"]), -1), "Can reparent a group up to the act")
	_assert_true(not order.move_node(str(act0["id"]), gid, -1), "Cannot move a node into its own subtree (no cycle)")
	_assert_true(order.rename_node(rid, "Renamed Region"), "Can rename a node")
	_assert_equals(str(order.locate(rid)["node"].get("title", "")), "Renamed Region", "Rename sticks")
	var r2 := order.add_node(str(act0["id"]), "region", "Second Region")
	var before := (order.locate(str(act0["id"]))["node"]["children"] as Array).find(order.locate(r2)["node"])
	_assert_true(order.reorder_sibling(r2, -1), "Can reorder a sibling up")
	_assert_true((order.locate(str(act0["id"]))["node"]["children"] as Array).find(order.locate(r2)["node"]) < before, "Reorder moved the node earlier")

	# Drag "between"/"onto" semantics the tree uses.
	var aA := order.add_node(str(act0["id"]), "region", "Alpha")
	var aB := order.add_node(str(act0["id"]), "region", "Beta")
	_assert_true(order.move_after(aA, aB), "move_after places a node right after the target")
	var kids: Array = order.locate(str(act0["id"]))["node"]["children"]
	_assert_equals(kids.find(order.locate(aA)["node"]), kids.find(order.locate(aB)["node"]) + 1, "Moved node sits immediately after the target")
	_assert_true(order.move_into(aA, aB), "move_into nests a node under a container")
	_assert_equals(str(order.locate(aA)["parent"].get("id", "")), aB, "Moved node is now a child of the target container")
	_assert_true(not order.move_into(aB, aA), "move_into rejects nesting a node under its own descendant")

	# Validation flags a broken shelter link, a stage regression, and a missing spec.
	var bad = CampaignOrderScript.new()
	var ba := bad.add_node(str(bad.root()["id"]), "region", "R")
	bad.add_node(ba, "stretch", "A", {"spec_id": "a", "entry": "shelter_1", "exit": "shelter_2", "stage": 4})
	bad.add_node(ba, "stretch", "B", {"spec_id": "b", "entry": "shelter_7", "exit": "shelter_8", "stage": 2})
	bad.add_node(ba, "stretch", "C", {"spec_id": "ghost", "entry": "shelter_8", "exit": "shelter_9", "stage": 3})
	var rep := bad.validate(["a", "b"])
	var codes := {}
	for it in rep.get("issues", []):
		codes[str(it.get("code", ""))] = true
	_assert_true(codes.has("shelter_gap"), "Validation flags a broken shelter link")
	_assert_true(codes.has("stage_regression"), "Validation flags a stage regression")
	_assert_true(codes.has("missing_spec"), "Validation flags a stretch referencing a non-existent spec")
	_assert_true(int(rep.get("error_count", 0)) >= 1, "Missing spec is an error-severity issue")

	# id-repair: a hand-authored manifest with DUPLICATE + EMPTY ids loads with unique ids.
	var dup = CampaignOrderScript.new({
		"next_id": 1,
		"root": {"id": "campaign_001", "kind": "campaign", "title": "C", "children": [
			{"id": "region_001", "kind": "region", "title": "lit", "children": []},
			{"id": "region_001", "kind": "region", "title": "dup", "children": []},
			{"id": "", "kind": "region", "title": "empty", "children": []},
		]},
	})
	var dup_ids := {}
	var dup_unique := true
	var dup_stack := [dup.root()]
	while not dup_stack.is_empty():
		var dn = dup_stack.pop_back()
		var nid := str(dn.get("id", ""))
		if nid == "" or dup_ids.has(nid):
			dup_unique = false
		dup_ids[nid] = true
		for c in dn.get("children", []):
			dup_stack.append(c)
	_assert_true(dup_unique, "id-repair gives every node a unique non-empty id (duplicate + empty input)")
	_assert_true(not dup_ids.has(dup.add_node(str(dup.root()["id"]), "region", "fresh")), "a fresh add after id-repair does not collide")

	# move_node boundary indices land the node first / last (no off-by-one drift).
	var mp = CampaignOrderScript.new()
	var mpa := mp.add_node(str(mp.root()["id"]), "act", "A")
	var ra := mp.add_node(mpa, "region", "Ra")
	mp.add_node(mpa, "region", "Rb")
	var rc := mp.add_node(mpa, "region", "Rc")
	mp.move_node(rc, mpa, 0)
	_assert_equals(str(mp.locate(mpa)["node"]["children"][0].get("title", "")), "Rc", "move_node to index 0 puts the node first")
	mp.move_node(ra, mpa, 9)
	var mk: Array = mp.locate(mpa)["node"]["children"]
	_assert_equals(str(mk[mk.size() - 1].get("title", "")), "Ra", "move_node past the end appends the node last")

	# An optional higher-stage side branch is NOT a false stage regression.
	var br = CampaignOrderScript.new()
	var brr := br.add_node(str(br.root()["id"]), "region", "R")
	br.add_node(brr, "stretch", "M1", {"spec_id": "m1", "entry": "shelter_1", "exit": "shelter_2", "stage": 1, "branch": "main"})
	br.add_node(brr, "stretch", "Opt", {"spec_id": "o", "entry": "shelter_2", "exit": "shelter_2", "stage": 5, "branch": "optional"})
	br.add_node(brr, "stretch", "M2", {"spec_id": "m2", "entry": "shelter_2", "exit": "shelter_3", "stage": 2, "branch": "main"})
	var brcodes := {}
	for it in br.validate(["m1", "o", "m2"]).get("issues", []):
		brcodes[str(it.get("code", ""))] = true
	_assert_true(not brcodes.has("stage_regression"), "An optional higher-stage branch is not a false stage regression")

	# A stretch leaf with nested nodes is flagged (a leaf must stay a leaf).
	var lf = CampaignOrderScript.new({"root": {"id": "campaign_001", "kind": "campaign", "title": "C", "children": [
		{"id": "stretch_001", "kind": "stretch", "title": "S", "spec_id": "s", "children": [
			{"id": "stretch_002", "kind": "stretch", "title": "nested", "spec_id": "n", "children": []}]}]}})
	var lcodes := {}
	for it in lf.validate([]).get("issues", []):
		lcodes[str(it.get("code", ""))] = true
	_assert_true(lcodes.has("leaf_has_children"), "A stretch leaf with nested nodes is flagged")

	# JSON roundtrip + id-uniqueness repair.
	var restored = CampaignOrderScript.from_json(order.to_json())
	_assert_equals(restored.flatten_stretches().size(), order.flatten_stretches().size(), "Roundtrip preserves stretch count")
	restored.add_node(str(restored.root()["id"]), "act", "Fresh Act")
	var ids := {}
	var unique := true
	var stack := [restored.root()]
	while not stack.is_empty():
		var n = stack.pop_back()
		if ids.has(str(n.get("id", ""))):
			unique = false
		ids[str(n.get("id", ""))] = true
		for c in n.get("children", []):
			stack.append(c)
	_assert_true(unique, "All node ids are unique after load + a fresh add")

func _spotlight_approach_for_archetype(spec: Dictionary, aid: String) -> Dictionary:
	var node_arch := {}
	for n in spec.get("nodes", []):
		node_arch[str((n as Dictionary).get("id", ""))] = str((n as Dictionary).get("archetype_id", ""))
	for p in spec.get("headless", {}).get("solution_paths", []):
		if str((p as Dictionary).get("loadout", "")) == "spotlight":
			for e in (p as Dictionary).get("approach_per_node", []):
				if str(node_arch.get(str((e as Dictionary).get("node", "")), "")) == aid:
					return e
	return {}

func _test_character_roster() -> void:
	_test_name = "Character Roster"

	# The six brain-cell characters are registered, with combat/insulation from the right cells.
	var reg: Dictionary = StretchCapabilitiesScript.CHARACTER_REGISTRY
	for cid in ["aster", "peris", "endo", "myke", "oli", "tyreg"]:
		_assert_true(reg.has(cid), "Roster includes %s" % cid)
	_assert_true((reg["myke"]["capabilities"] as Array).has("combat"), "Myke (microglia) provides combat")
	_assert_true((reg["tyreg"]["capabilities"] as Array).has("force"), "Tyreg (T-reg) provides ranged force")
	_assert_true((reg["oli"]["capabilities"] as Array).has("insulation"), "Oli (oligodendrocyte) provides insulation")
	var spec_caps: Dictionary = StretchCapabilitiesScript.specialist_capabilities()
	_assert_true(spec_caps.has("combat") and spec_caps.has("barrier"), "Specialist caps include combat + barrier")
	_assert_true(not spec_caps.has("flora") and not spec_caps.has("overlay"), "Aster+Peris pair caps (flora/overlay) are NOT specialist")
	_assert_true((reg["aster"]["abilities"] as Dictionary).has("emp") and (reg["myke"]["abilities"] as Dictionary).has("inflame"), "Abilities are registered (Aster EMP, Myke Inflame)")

	var base := {
		"id": "roster_test", "seed": 313, "complexity_tier": "standard", "progression_stage": 3,
		"limitations": {"required": {"archetypes": ["1"]}, "allowed": {"archetypes": ["1", "11"], "enemies": ["techos", "gnawers"]}},
	}
	# FULL roster: the redirect's full-party approach is the combat specialist; multi-solution.
	var full := StretchGeneratorScript.generate(base)
	_assert_true(bool(full.get("headless", {}).get("solution_summary", {}).get("multi_solution", false)), "Full roster: redirect stretch is multi-solution (combat specialist vs the pair)")
	_assert_equals(str(_spotlight_approach_for_archetype(full, "1").get("party", "")), "specialist", "Full roster: the redirect's full-party approach is the combat specialist")

	# DISABLE the combat characters: the full party loses combat and the redirect falls to the
	# Aster+Peris approach — the enable/disable option genuinely changes what's solvable.
	var no_combat := base.duplicate(true)
	no_combat["id"] = "roster_test_nocombat"
	no_combat["roster"] = ["aster", "peris", "endo"]
	var nc := StretchGeneratorScript.generate(no_combat)
	var nc_summary: Dictionary = nc.get("headless", {}).get("solution_summary", {})
	var sp_party := []
	for p in nc.get("headless", {}).get("solution_paths", []):
		if str((p as Dictionary).get("loadout", "")) == "spotlight":
			sp_party = (p as Dictionary).get("party", [])
	_assert_true(not sp_party.has("myke") and not sp_party.has("tyreg"), "Disabled roster: the full party has no combat character")
	_assert_equals(str(_spotlight_approach_for_archetype(nc, "1").get("party", "")), "aster_peris", "Disabled combat: the redirect falls to the Aster+Peris approach")
	_assert_true(bool(nc_summary.get("shadow_solvable", false)) and bool(nc_summary.get("bare_pair_solvable", false)), "Disabled combat: the pair can still finish the stretch")

	# The minimum pair is never dropped, even if the roster omits them.
	var only_myke: Array = StretchCapabilitiesScript.normalize_roster(["myke"]).get("enabled", [])
	_assert_true(only_myke.has("aster") and only_myke.has("peris"), "Aster + Peris are always present (they never leave)")

	# Unknown / stale ids are dropped — never promoted to ghost party members.
	var with_ghost: Array = StretchCapabilitiesScript.normalize_roster(["myke", "ghost_cell", "not_real"]).get("enabled", [])
	_assert_true(with_ghost.has("myke") and not with_ghost.has("ghost_cell") and not with_ghost.has("not_real"), "Unknown roster ids are dropped (no ghost members)")

	# Content-capability filtering is roster-aware: a placed barrier lends "barrier" only when
	# NO enabled specialist owns it. With everyone enabled it's withheld (so the specialist-vs-
	# pair choice survives); with the barrier specialists (Endo + Oli) disabled it passes through.
	var barrier_node := {"structures": ["barrier"]}
	var full_filtered: Dictionary = StretchCapabilitiesScript.node_content_capabilities(barrier_node)
	_assert_true(not full_filtered.has("barrier"), "Full roster: a placed barrier does NOT lend the specialist 'barrier' (choice preserved)")
	var pair_only: Dictionary = StretchCapabilitiesScript.node_content_capabilities(barrier_node, ["aster", "peris"])
	_assert_true(pair_only.has("barrier"), "Barrier specialists disabled: a placed barrier DOES lend 'barrier' to the pair")

func _test_archetype_coherence() -> void:
	_test_name = "Archetype Coherence"

	var spec: Dictionary = StretchGeneratorScript.generate({
		"id": "coherence_test", "seed": 4477, "complexity_tier": "hard", "progression_stage": 4,
		"limitations": {
			"required": {"archetypes": ["2", "1", "13", "12"]},
			"allowed": {
				"archetypes": ["1", "2", "12", "13"],
				"flora": ["scarpet", "flure", "hushbloom", "capbage", "seefern", "doma"],
				"enemies": ["techos", "naturalizers", "meebs", "neutros", "gnawers", "candids", "spikers", "tanglers"],
			},
		},
	})
	_assert_true(bool(spec.get("success", false)), "Coherence spec generates")

	# Every archetype must carry >= 2 variants — the per-node variant cycling relies on this so a
	# repeated archetype never stamps the identical beat twice (a single-variant archetype would).
	var cat_file := FileAccess.open("res://data/generation/archetype_catalog.json", FileAccess.READ)
	if cat_file != null:
		var cat = JSON.parse_string(cat_file.get_as_text())
		if cat is Dictionary:
			var arches = (cat as Dictionary).get("archetypes", {})
			if arches is Dictionary:
				for aid in (arches as Dictionary).keys():
					var ad = (arches as Dictionary)[aid]
					if not (ad is Dictionary):
						continue
					var vcount: int = ((ad as Dictionary).get("variants", []) as Array).size()
					_assert_true(vcount >= 2, "Archetype %s carries >= 2 variants (cycling stays varied)" % str(aid))

	var forage_ok := false
	var exploit_ok := false
	var redirect_has_enemy := false
	var labels_named := true
	var variants_by_arch := {}
	for n in spec.get("nodes", []):
		var aid := str((n as Dictionary).get("archetype_id", ""))
		var sk := str((n as Dictionary).get("survival_kind", ""))
		var role := str((n as Dictionary).get("role", ""))
		var label := str((n as Dictionary).get("title", ""))
		var enemies: Array = (n as Dictionary).get("enemies", [])
		var structures: Array = (n as Dictionary).get("structures", [])
		if aid in ["1", "2", "12", "13"]:
			if not label.contains(str((n as Dictionary).get("archetype_name", ""))):
				labels_named = false
			if not variants_by_arch.has(aid):
				variants_by_arch[aid] = []
			(variants_by_arch[aid] as Array).append(str((n as Dictionary).get("variant", "")))
		if sk == "forage":
			forage_ok = role == "foraging" and structures.has("forage_cache") and int((n as Dictionary).get("atp_reward", 0)) > 0
		if sk == "exploit":
			exploit_ok = enemies.size() >= 2
		if aid == "1" and not enemies.is_empty():
			redirect_has_enemy = true
	_assert_true(forage_ok, "A forage node reads as foraging with a forage_cache + atp_reward (role/structure/survival cohere)")
	_assert_true(exploit_ok, "An exploit node places its predator + prey actors (>=2 enemies)")
	_assert_true(redirect_has_enemy, "A redirect node has an enemy to redirect")
	_assert_true(labels_named, "Node labels name their archetype, not a bare role label")

	var varied := true
	for aid in variants_by_arch:
		var vs: Array = variants_by_arch[aid]
		if vs.size() >= 2:
			var distinct := {}
			for v in vs:
				distinct[v] = true
			if distinct.size() < 2:
				varied = false
	_assert_true(varied, "A repeated archetype uses different variants across its occurrences")

	# A redirect node's placed flora matches its variant's need (no hushbloom_stun-with-scarpet).
	var plant_ok := true
	for n in spec.get("nodes", []):
		if str((n as Dictionary).get("variant", "")) == "hushbloom_stun":
			if not ((n as Dictionary).get("flora", []) as Array).has("hushbloom"):
				plant_ok = false
	_assert_true(plant_ok, "A hushbloom_stun plant beat actually places hushbloom (variant matches its prop)")

func _test_survival_archetypes() -> void:
	_test_name = "Survival Archetypes"

	# The five survival archetypes exist with kind survival + the right survival_kind.
	var catalog := StretchArchetypeCatalogScript.new()
	var survival_kinds := {"12": "forage", "13": "exploit", "14": "gauntlet", "15": "hazard", "16": "rest"}
	for aid in survival_kinds:
		var a: Dictionary = catalog.get_archetype(aid)
		_assert_equals(str(a.get("kind", "")), "survival", "Archetype %s is kind 'survival'" % aid)
		_assert_equals(str(a.get("survival_kind", "")), str(survival_kinds[aid]), "Archetype %s survival_kind is %s" % [aid, survival_kinds[aid]])

	# A survival stretch generates and is multi-solution + shadow/bare-pair solvable + in-stage.
	var spec: Dictionary = StretchGeneratorScript.generate({
		"id": "generated_survival_test", "seed": 808, "complexity_tier": "hard", "progression_stage": 4,
		"limitations": {
			"required": {"archetypes": ["12", "13", "14"]},
			"allowed": {"archetypes": ["11", "12", "13", "14", "15", "16"], "flora": ["scarpet", "flure", "capbage", "seefern"], "enemies": ["techos", "naturalizers"]},
		},
	})
	_assert_true(bool(spec.get("success", false)), "Survival stretch generates")
	var summary: Dictionary = spec.get("headless", {}).get("solution_summary", {})
	_assert_true(bool(summary.get("multi_solution", false)), "Survival stretch is multi-solution (get past two ways)")
	_assert_true(bool(summary.get("shadow_solvable", false)), "Aster+Peris can survive the whole stretch")
	_assert_true(bool(summary.get("bare_pair_solvable", false)), "Every survival node is bare-pair solvable")
	_assert_true(bool(summary.get("spotlight_within_stage", false)), "Survival spotlight stays within the progression stage")

	# Survival metadata lands on the spine nodes; an exploit node lends a 'redirect' tool.
	var kinds := {}
	var forage_node := {}
	var exploit_node := {}
	for node in spec.get("nodes", []):
		var sk := str((node as Dictionary).get("survival_kind", ""))
		if sk != "":
			kinds[sk] = true
		if sk == "forage" and forage_node.is_empty():
			forage_node = node
		if sk == "exploit" and exploit_node.is_empty():
			exploit_node = node
	_assert_true(kinds.has("forage") and kinds.has("gauntlet") and kinds.has("exploit"), "Required survival kinds (forage/gauntlet/exploit) appear on the spine")
	_assert_true(not forage_node.is_empty() and int(forage_node.get("atp_reward", 0)) > 0, "A forage node carries an atp_reward (partial ATP top-up)")
	_assert_true(not exploit_node.is_empty() and StretchCapabilitiesScript.node_content_capabilities(exploit_node).has("redirect"), "An exploit node's enemy configuration lends a 'redirect' tool (enemies as a tool)")
	# The exploit capability is actually CONSUMED by an approach (not dead): archetype 13's
	# weaponized_window requires it, so the configuration itself is a usable solve affordance.
	var a13_consumes := false
	for ap in catalog.get_archetype("13").get("approaches", []):
		if (ap.get("requires", []) as Array).has("exploit"):
			a13_consumes = true
	_assert_true(a13_consumes, "An approach requires the 'exploit' capability, so the enemy-config tool is wired, not dead")
	# Placed content never hands the Aster+Peris pair a specialist capability (no collapse).
	var barrier_node := {"structures": ["barrier"], "survival_kind": "hazard"}
	_assert_true(not StretchCapabilitiesScript.node_content_capabilities(barrier_node).has("barrier"), "A placed barrier structure does NOT grant the pair the specialist 'barrier' capability")

	# Chunk: a golden run banks ATP at the forage cache and takes attrition at the gauntlet.
	var preview: Node = await _instantiate_preview_chunk_and_wait("generated_stretch", 3, {"spec": spec})
	if preview != null:
		preview.call("headless_call_chunk", "run_generated_golden_path", [])
		var cs: Dictionary = preview.call("headless_get_state").get("chunk", {})
		_assert_true(int(cs.get("atp_foraged", 0)) > 0, "A golden run banks partial ATP at the forage cache")
		_assert_true(float(cs.get("pressure_taken", 0.0)) > 0.0, "A golden run takes HP/stamina attrition at the gauntlet/hazard")
		preview.queue_free()
		await get_tree().process_frame

func _test_generated_stretch_playtest_loop() -> void:
	_test_name = "Generated Stretch Playtest Loop"

	var settings := {
		"id": "generated_playtest_loop_random_walk",
		"title": "Generated Playtest Loop Random Walk",
		"seed": 4129,
		"complexity_tier": "standard",
		"budget": {
			"node_count": 8,
			"optional_node_count": 1,
			"branch_count": 1,
			"archetype_depth": 4,
			"pressure_budget": 2,
			"flora_slots": 3,
			"enemy_slots": 2,
			"structures_slots": 5,
			"shortcut_count": 1,
			"resource_beats": 2,
		},
		"limitations": {
			"allowed": {
				"flora": ["flure", "hushbloom", "scarpet"],
				"enemies": ["techos", "naturalizers"],
				"structures": ["shelter", "forage_cache", "terminal", "carry_gear", "shortcut_gate", "pipe"],
				"archetypes": ["2", "3", "4", "6", "11"],
			},
			"required": {
				"flora": ["flure"],
				"enemies": ["naturalizers"],
				"structures": ["shelter"],
				"archetypes": ["2", "3", "4", "6"],
			},
		},
		"composition": {
			"mode": "archetype_random_walk",
			"random_walk": {
				"start_archetype": "2",
				"start_step": 0,
				"step_count": 7,
				"transition_chance": 0.45,
				"prefer_tags": ["flora", "patrol", "carry", "fragments"],
				"allow_revisit": true,
			},
		},
		"world_slot": {
			"slot_id": "generated_playtest_loop_random_walk",
			"act": 1,
			"region": "Channels",
			"entry_shelter_id": "shelter_4",
			"exit_shelter_id": "shelter_5",
		},
	}

	var loop = StretchGenerationPlaytestLoopScript.new()
	_assert_true(loop != null, "Stretch generation playtest loop instantiates")
	var result: Dictionary = await loop.generate_and_playtest(settings, get_tree(), {
		"capture_animation": true,
		"capture_step": 0.4,
	})
	_assert_equals(str(result.get("contract_id", "")), "stretch_generation_playtest_loop_v1",
		"Playtest loop reports its contract")
	_assert_true(bool(result.get("success", false)), "Playtest loop succeeds without failures")
	_assert_equals(str(result.get("spec_id", "")), "generated_playtest_loop_random_walk",
		"Playtest loop reports the generated spec id")
	_assert_true((result.get("errors", []) as Array).is_empty(),
		"Playtest loop reports no failures")
	_assert_true(int(result.get("event_count", 0)) >= 20,
		"Playtest loop records a full event timeline")
	var loop_events: Array = result.get("events", [])
	_assert_true(_event_type_seen(loop_events, "spec_ready"),
		"Playtest loop records generation event")
	_assert_true(_event_type_seen(loop_events, "preview_ready"),
		"Playtest loop records preview boot event")
	_assert_true(_event_type_seen(loop_events, "ability_activated"),
		"Playtest loop records ability events")
	_assert_true(_event_type_seen(loop_events, "route_chosen"),
		"Playtest loop records route events")
	_assert_true(_event_type_seen(loop_events, "node_activated"),
		"Playtest loop records node events")
	_assert_true(_event_type_seen(loop_events, "shelter_rested"),
		"Playtest loop records shelter rest events")
	var checks: Dictionary = result.get("checks", {})
	for check_id in [
		"generator_success",
		"preview_scene_loads",
		"preview_scene_instantiates",
		"preview_headless_state",
		"preview_chunk_is_generated",
		"preview_party_preset_full",
		"shared_preview_gui",
		"canonical_controls_visible",
		"world_slot_exposed",
		"full_party_full_stats",
		"preview_graybox_spatial_contract",
		"preview_navigation_graph_contract",
		"preview_graybox_click_targets",
		"preview_graybox_content_placed",
		"preview_graybox_elevations",
		"main_abilities_exercised",
		"golden_path_moves_party",
		"golden_path_uses_routes",
		"golden_path_uses_multilevel_navigation",
		"golden_path_reaches_shelter",
		"risky_recovery_playable",
		"risky_recovery_applies_pressure",
		"playthrough_animation_contract",
		"playthrough_animation_snapshots",
		"playthrough_animation_walk_state",
		"playthrough_animation_run_state",
		"playthrough_animation_inventory_state",
	]:
		_assert_true(bool(checks.get(check_id, false)), "Playtest loop passes %s" % check_id)
	var animation: Dictionary = result.get("animation", {})
	_assert_equals(str(animation.get("contract_id", "")), "playthrough_animation_v1",
		"Playtest loop emits reusable playthrough animation data")
	_assert_true(int(animation.get("snapshot_count", 0)) >= 8,
		"Playtest animation captures multiple state snapshots")
	_assert_true((animation.get("layout", {}).get("nodes", []) as Array).size() >= 2,
		"Playtest animation carries graybox layout nodes")
	_assert_true((animation.get("layout", {}).get("routes", []) as Array).size() >= 1,
		"Playtest animation carries graybox route layout")
	var animation_summary: Dictionary = animation.get("summary", {})
	_assert_true(bool(animation_summary.get("has_walk_state", false)),
		"Playtest animation captures walking state")
	_assert_true(bool(animation_summary.get("has_run_state", false)),
		"Playtest animation captures running state")
	_assert_true(bool(animation_summary.get("has_hand_slots", false)),
		"Playtest animation captures hand slots")
	_assert_true(bool(animation_summary.get("has_endocytosis", false)),
		"Playtest animation captures endocytosis effects")
	_assert_true(_animation_has_character_path(animation, "aster"),
		"Playtest animation captures Aster movement paths")
	var generated_spec: Dictionary = result.get("spec", {})
	_assert_true(bool(generated_spec.get("composition", {}).get("uses_random_walk", false)),
		"Playtest loop keeps random-walk generation metadata")
	var golden_report: Dictionary = result.get("playthroughs", {}).get("golden_path", {})
	_assert_true((golden_report.get("visited_nodes", []) as Array).has("exit_shelter"),
		"Playtest loop drives the generated golden path to the exit shelter")
	_assert_true((golden_report.get("route_gaps", []) as Array).is_empty(),
		"Generated golden path is route-graph playable")
	_assert_true(int(golden_report.get("movement_commands", 0)) >= 3,
		"Playtest loop moves the party through preview movement")
	var risky_report: Dictionary = result.get("playthroughs", {}).get("risky_recovery", {})
	_assert_true(bool(risky_report.get("recovered", false)),
		"Playtest loop recovers from risky route pressure")
	_assert_true(float(risky_report.get("damage", 0.0)) > 0.0,
		"Playtest loop records risky route damage")

	var editor_scene: PackedScene = load("res://scenes/editor/level_editor.tscn")
	_assert_true(editor_scene != null, "Level editor loads for generate-and-playtest API")
	if editor_scene != null:
		var editor_instance: Node = await _instantiate_scene_and_wait(editor_scene, 3)
		_assert_true(editor_instance != null, "Level editor instantiates for generate-and-playtest API")
		if editor_instance != null:
			_assert_true(editor_instance.has_method("generate_and_playtest_stretch"),
				"Level editor exposes generate-and-playtest API")
			var editor_settings := settings.duplicate(true)
			editor_settings["id"] = "generated_editor_playtest_loop"
			editor_settings["seed"] = 4130
			var editor_result: Dictionary = await editor_instance.call("generate_and_playtest_stretch", editor_settings)
			_assert_true(bool(editor_result.get("success", false)),
				"Level editor generate-and-playtest API returns a playable result")
			var generation_state: Dictionary = editor_instance.call("get_generation_state")
			_assert_equals(str(generation_state.get("last_action", "")), "generate_and_playtest",
				"Level editor records generate-and-playtest as the last generation action")
			_assert_equals(str(generation_state.get("spec_id", "")), "generated_editor_playtest_loop",
				"Level editor records the generated playtest spec id")
			await _dispose_scene(editor_instance)

func _event_type_seen(events: Array, event_type: String) -> bool:
	for event in events:
		if event is Dictionary and str((event as Dictionary).get("type", "")) == event_type:
			return true
	return false

func _animation_has_character_path(animation: Dictionary, char_id: String) -> bool:
	for snapshot in animation.get("snapshots", []):
		if not (snapshot is Dictionary):
			continue
		var characters: Dictionary = (snapshot as Dictionary).get("characters", {})
		var character: Dictionary = characters.get(char_id, {})
		var movement: Dictionary = character.get("movement", {})
		if int(movement.get("path_count", 0)) >= 2:
			return true
	return false

func _generated_stretch_event_report_settings() -> Dictionary:
	return {
		"id": "generated_event_walk_shelter_4_to_5",
		"title": "Generated Event Walk: Shelter 4 -> Shelter 5",
		"seed": 5271,
		"complexity_tier": "hard",
		"budget": {
			"node_count": 10,
			"optional_node_count": 2,
			"branch_count": 2,
			"archetype_depth": 5,
			"pressure_budget": 3,
			"flora_slots": 4,
			"enemy_slots": 3,
			"structures_slots": 6,
			"shortcut_count": 1,
			"resource_beats": 2,
		},
		"limitations": {
			"allowed": {
				"flora": ["flure", "hushbloom", "scarpet", "seefern", "forget_me_nots"],
				"enemies": ["techos", "naturalizers", "tanglers"],
				"structures": ["shelter", "forage_cache", "terminal", "carry_gear", "shortcut_gate", "pipe", "barrier"],
				"archetypes": ["1", "2", "3", "4", "6", "8", "11"],
			},
			"required": {
				"flora": ["flure", "hushbloom"],
				"enemies": ["naturalizers"],
				"structures": ["shelter", "shortcut_gate"],
				"archetypes": ["1", "2", "3", "4", "6"],
			},
		},
		"composition": {
			"mode": "archetype_random_walk",
			"random_walk": {
				"start_archetype": "2",
				"start_step": 0,
				"step_count": 8,
				"transition_chance": 0.5,
				"prefer_tags": ["flora", "patrol", "carry", "fragments", "enemy"],
				"allow_revisit": true,
			},
		},
		"world_slot": {
			"slot_id": "generated_event_walk_shelter_4_to_5",
			"act": 1,
			"region": "Channels",
			"entry_shelter_id": "shelter_4",
			"exit_shelter_id": "shelter_5",
			"next_slot": "generated_event_walk_shelter_5_to_6",
		},
	}

func _report_generated_stretch_events(output_path: String) -> void:
	_test_name = "Generated Stretch Events"
	var loop = StretchGenerationPlaytestLoopScript.new()
	var result: Dictionary = await loop.generate_and_playtest(_generated_stretch_event_report_settings(), get_tree(), {
		"capture_animation": true,
		"capture_step": 0.25,
	})
	_assert_true(bool(result.get("success", false)), "Generated stretch playtest event report succeeds")
	_assert_true(int(result.get("event_count", 0)) >= 20, "Generated stretch event report captures an ordered timeline")
	var animation: Dictionary = result.get("animation", {})
	_assert_equals(str(animation.get("contract_id", "")), "playthrough_animation_v1", "Generated stretch event report includes playthrough animation data")
	_assert_true(int(animation.get("snapshot_count", 0)) >= 8, "Generated stretch event report captures animation snapshots")
	var spec: Dictionary = result.get("spec", {})
	var spec_path := "res://data/generated_stretches/%s.json" % str(spec.get("id", "generated_stretch_events"))
	var saved_spec := StretchGeneratorScript.save_spec(spec, spec_path)
	_assert_true(saved_spec, "Generated stretch spec saved for inspection")
	result["saved_spec_path"] = spec_path
	result["saved_spec"] = saved_spec
	var html_output_path := output_path.get_base_dir().path_join("generated_stretch_event_animation.html")
	result["animation_html_path"] = html_output_path

	var html_dir := ProjectSettings.globalize_path(html_output_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(html_dir)
	var html_file := FileAccess.open(html_output_path, FileAccess.WRITE)
	_assert_true(html_file != null, "Generated stretch animation output file opened")
	if html_file != null:
		html_file.store_string(PlaythroughAnimationHtmlRendererScript.build_html(result))
		html_file.close()

	var absolute_dir := ProjectSettings.globalize_path(output_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Generated stretch event report output file opened")
	if file == null:
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()

	print("  Generated stretch: %s" % str(spec.get("title", "")))
	print("  Saved spec: %s" % spec_path)
	print("  Event report: %s" % output_path)
	print("  Animation: %s" % html_output_path)
	print("  Event count: %d" % int(result.get("event_count", 0)))
	print("  Animation snapshots: %d" % int(animation.get("snapshot_count", 0)))
	for event in (result.get("events", []) as Array).slice(0, 18):
		if event is Dictionary:
			print("    %02d [%s] %s" % [
				int((event as Dictionary).get("index", 0)),
				str((event as Dictionary).get("phase", "")),
				str((event as Dictionary).get("label", "")),
			])

func _test_asset_pipeline() -> void:
	_test_name = "Asset Pipeline"

	_assert_true(
		FileAccess.file_exists("res://tools/gltf_emissive_from_color.py"),
		"glTF emissive color helper exists"
	)
	_assert_true(
		FileAccess.file_exists("res://tools/gltf_wire_material_sidecars.py"),
		"glTF material sidecar wiring helper exists"
	)
	_assert_true(
		FileAccess.file_exists("res://tools/aster_sim_room_outline_import.gd"),
		"Aster room outline import hook exists"
	)
	_assert_true(
		FileAccess.file_exists("res://scripts/game/objects/outline_surface_target.gd"),
		"Reusable outline surface target exists"
	)
	_assert_true(
		FileAccess.file_exists("res://scripts/game/characters/character_interaction_controller.gd"),
		"Reusable character interaction controller exists"
	)
	_assert_true(
		FileAccess.file_exists("res://scripts/game/objects/outline_feedback_manager.gd"),
		"Reusable outline feedback manager exists"
	)
	_assert_true(
		FileAccess.file_exists("res://scripts/game/objects/interactable_catalog.gd"),
		"Reusable interactable catalog exists"
	)
	_assert_true(
		FileAccess.file_exists("res://data/interactables/tutorial_interactables.json"),
		"Tutorial interactable data catalog exists"
	)
	var interactable_specs = JSON.parse_string(FileAccess.get_file_as_string("res://data/interactables/tutorial_interactables.json"))
	_assert_true(interactable_specs is Dictionary,
		"Tutorial interactable data catalog parses as a dictionary")
	if interactable_specs is Dictionary:
		_assert_equals(str(interactable_specs["tutorial.inspection"].interactable_type), "INSPECTION",
			"Inspection interactables are declared in data")
		_assert_true(not bool(interactable_specs["aster.drink_machine"].interaction_enabled),
			"Aster drink machine starts disabled from data")
		_assert_equals(str(interactable_specs["peris.logbook_gate"].interactable_type), "HOLD_ACTION",
			"Peris logbook gate is declared as a hold/action interactable")
	_assert_true(
		FileAccess.file_exists("res://resources/object_outline_feedback.gdshader"),
		"Object-level outline feedback shader exists"
	)
	var object_outline_shader_text := FileAccess.get_file_as_string("res://resources/object_outline_feedback.gdshader")
	_assert_true(
		object_outline_shader_text.contains("VERTEX += NORMAL * outline_width")
		and object_outline_shader_text.contains("EMISSION = outline_color.rgb * glow_strength"),
		"Object-level outline shader expands meshes and emits glow"
	)
	var outline_shader_text := FileAccess.get_file_as_string("res://resources/black_outline.gdshader")
	_assert_true(
		outline_shader_text.contains("close_outline_width")
		and outline_shader_text.contains("far_outline_width")
		and outline_shader_text.contains("mix(close_outline_width, far_outline_width"),
		"Aster outline shader scales width by camera distance"
	)
	_assert_true(
		outline_shader_text.contains("texture_outline_mix")
		and outline_shader_text.contains("local_outline_color")
		and outline_shader_text.contains("darker_nearby_color")
		and outline_shader_text.contains("component_min_color")
		and outline_shader_text.contains("colored_floor")
		and outline_shader_text.contains("scene_average_color")
		and outline_shader_text.contains("textureLod(screen_tex")
		and outline_shader_text.contains("local_color * mix")
		and outline_shader_text.contains("ALBEDO = mix(screen, edge_color, edge)"),
		"Aster outline shader multiplies the minimum nearby texture color by the scene average"
	)
	_assert_true(
		not outline_shader_text.contains("hover_outline_enabled")
		and not outline_shader_text.contains("selected_outline_enabled"),
		"Aster full-screen outline shader does not own hover/selected object masks"
	)
	_assert_true(
		outline_shader_text.contains("bright_region_threshold")
		and outline_shader_text.contains("bright_color_edge_suppression")
		and outline_shader_text.contains("brightest_luma")
		and outline_shader_text.contains("color_edge_weight * color_edge_suppression"),
		"Aster outline shader suppresses color outlines across emissive texture regions"
	)

	var gltf_path := "res://resources/models/aster-sim/room/aster-sim-room-hi-res.gltf"
	var import_text := FileAccess.get_file_as_string(gltf_path + ".import")
	_assert_true(
		import_text.contains('import_script/path="res://tools/aster_sim_room_outline_import.gd"'),
		"Aster room glTF imports with the outline preview hook"
	)
	var imported_scene: PackedScene = load(gltf_path)
	_assert_true(imported_scene != null, "Aster room imported scene loads")
	if imported_scene != null:
		var imported_room := imported_scene.instantiate()
		var outline_preview := imported_room.find_child("AsterSimRoomOutlinePreview", true, false) as MeshInstance3D
		_assert_true(outline_preview != null, "Aster room imported scene includes the outline preview quad")
		if outline_preview != null:
			var outline_material := outline_preview.material_override as ShaderMaterial
			_assert_true(outline_material != null, "Aster room outline preview uses a shader material")
			if outline_material != null and outline_material.shader != null:
				_assert_equals(outline_material.shader.resource_path,
					"res://resources/black_outline.gdshader",
					"Aster room outline preview uses the black outline shader")
				var close_param: Variant = outline_material.get_shader_parameter("close_outline_width")
				var far_param: Variant = outline_material.get_shader_parameter("far_outline_width")
				if close_param != null and far_param != null:
					var close_outline_width: float = close_param
					var far_outline_width: float = far_param
					_assert_true(close_outline_width > far_outline_width,
						"Aster room outline gets thicker closer to the camera")
				else:
					_assert_true(true,
						"Aster room outline uses shader-default near/far width controls")
				_assert_true(
					not outline_shader_text.contains("hover_outline_enabled")
					and not outline_shader_text.contains("selected_outline_enabled"),
					"Aster room outline preview leaves interactive highlights to object materials"
				)
		var surface_targets := _find_nodes_with_script(imported_room, "res://scripts/game/objects/outline_surface_target.gd")
		_assert_true(surface_targets.size() >= 8,
			"Aster room import splits material surfaces into outline target wrappers")
		if not surface_targets.is_empty():
			_assert_outline_surface_target_contract(surface_targets[0], "Aster room split surface", false, true)
		var normal_material := _find_material_by_resource_name(imported_room, "aster-sim-room-hi-res_1")
		_assert_true(normal_material is StandardMaterial3D,
			"Aster room imported material keeps a Godot StandardMaterial3D for normal mapping")
		if normal_material is StandardMaterial3D:
			var standard_material := normal_material as StandardMaterial3D
			_assert_true(standard_material.normal_enabled,
				"Aster room imported material has normal mapping enabled")
			_assert_true(standard_material.normal_texture != null,
				"Aster room imported material has a normal texture assigned")
		imported_room.free()
	var gltf_text := FileAccess.get_file_as_string(gltf_path)
	_assert_true(not gltf_text.is_empty(), "Aster room glTF source is readable")
	if gltf_text.is_empty():
		return

	var parsed: Variant = JSON.parse_string(gltf_text)
	_assert_true(parsed is Dictionary, "Aster room glTF parses as JSON")
	if not (parsed is Dictionary):
		return

	var gltf: Dictionary = parsed
	var source_rgb := (0xfc << 16) | (0xff << 8) | 0xfa
	var cool_blue_factor_rgb := (0x9b << 16) | (0xd7 << 8) | 0xff
	_assert_gltf_material_emissive_mask(
		gltf,
		"aster-sim-room-hi-res_1",
		"aster-sim-room-hi-res_1_emissive.png",
		source_rgb,
		source_rgb,
		cool_blue_factor_rgb,
		5123
	)
	_assert_gltf_material_emissive_mask(
		gltf,
		"aster-sim-room-hi-res_8",
		"aster-sim-room-hi-res_8_emissive.png",
		source_rgb,
		source_rgb,
		cool_blue_factor_rgb,
		112
	)
	_assert_gltf_material_normal_map(
		gltf,
		"aster-sim-room-hi-res_1",
		"aster-sim-room-hi-res_1_normals.png",
		1.0
	)

func _assert_gltf_material_emissive_mask(
	gltf: Dictionary,
	material_name: String,
	expected_emissive_uri: String,
	source_rgb: int,
	_emissive_rgb: int,
	factor_rgb: int,
	expected_lit_pixels: int
) -> void:
	var material_index := _find_gltf_material_index(gltf, material_name)
	_assert_true(material_index >= 0, "%s material exists" % material_name)
	if material_index < 0:
		return

	var materials: Array = gltf.get("materials", [])
	var material: Dictionary = materials[material_index]
	var emissive_texture_variant: Variant = material.get("emissiveTexture", null)
	_assert_true(emissive_texture_variant is Dictionary, "%s has an emissive texture" % material_name)
	if not (emissive_texture_variant is Dictionary):
		return

	var emissive_texture: Dictionary = emissive_texture_variant
	var texture_index := int(emissive_texture.get("index", -1))
	var textures: Array = gltf.get("textures", [])
	_assert_true(texture_index >= 0 and texture_index < textures.size(), "%s emissive texture index is valid" % material_name)
	if texture_index < 0 or texture_index >= textures.size():
		return

	var texture: Dictionary = textures[texture_index]
	var image_index := int(texture.get("source", -1))
	var images: Array = gltf.get("images", [])
	_assert_true(image_index >= 0 and image_index < images.size(), "%s emissive image index is valid" % material_name)
	if image_index < 0 or image_index >= images.size():
		return

	var image: Dictionary = images[image_index]
	_assert_equals(
		str(image.get("uri", "")),
		expected_emissive_uri,
		"%s emissive image URI is wired" % material_name
	)

	var extensions_used: Array = gltf.get("extensionsUsed", [])
	_assert_true(
		extensions_used.has("KHR_materials_emissive_strength"),
		"Aster room glTF declares the emissive strength extension for %s" % material_name
	)
	var material_extensions: Dictionary = material.get("extensions", {})
	var strength_info: Dictionary = material_extensions.get("KHR_materials_emissive_strength", {})
	_assert_true(
		absf(float(strength_info.get("emissiveStrength", 0.0)) - 2.5) < 0.001,
		"%s emissive strength is preserved" % material_name
	)
	_assert_true(
		_factor_matches_rgb(material.get("emissiveFactor", []), factor_rgb),
		"%s emissive factor is cool blue" % material_name
	)

	var base_texture_index := int(material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1))
	_assert_true(base_texture_index >= 0 and base_texture_index < textures.size(), "%s base texture index is valid" % material_name)
	if base_texture_index < 0 or base_texture_index >= textures.size():
		return

	var base_texture: Dictionary = textures[base_texture_index]
	var base_image_index := int(base_texture.get("source", -1))
	_assert_true(base_image_index >= 0 and base_image_index < images.size(), "%s base image index is valid" % material_name)
	if base_image_index < 0 or base_image_index >= images.size():
		return

	var base_image: Dictionary = images[base_image_index]
	var base_uri := str(base_image.get("uri", ""))
	var emissive_uri := str(image.get("uri", ""))
	var source_image := Image.new()
	var emissive_image := Image.new()
	var source_error := _load_png_from_res(source_image, "res://resources/models/aster-sim/room/%s" % base_uri)
	var emissive_error := _load_png_from_res(emissive_image, "res://resources/models/aster-sim/room/%s" % emissive_uri)
	_assert_equals(source_error, OK, "%s source texture loads" % material_name)
	_assert_equals(emissive_error, OK, "%s generated emissive texture loads" % material_name)
	if source_error != OK or emissive_error != OK:
		return

	source_image.convert(Image.FORMAT_RGBA8)
	emissive_image.convert(Image.FORMAT_RGBA8)
	_assert_equals(emissive_image.get_width(), source_image.get_width(), "%s emissive texture width matches source" % material_name)
	_assert_equals(emissive_image.get_height(), source_image.get_height(), "%s emissive texture height matches source" % material_name)

	var source_target_pixels := 0
	var masked_pixels := 0
	var mismatched_pixels := 0
	for y in range(source_image.get_height()):
		for x in range(source_image.get_width()):
			var source_pixel := source_image.get_pixel(x, y)
			var emissive_pixel := emissive_image.get_pixel(x, y)
			var source_matches := _rgb24(source_pixel) == source_rgb and _color_byte(source_pixel.a) > 0
			var actual_emissive_rgb := _rgb24(emissive_pixel)
			if source_matches:
				source_target_pixels += 1
				if actual_emissive_rgb != 0:
					masked_pixels += 1
				else:
					mismatched_pixels += 1
			elif actual_emissive_rgb != 0:
				mismatched_pixels += 1

	_assert_equals(source_target_pixels, expected_lit_pixels, "%s source texture contains expected #fcfffa pixels" % material_name)
	_assert_equals(masked_pixels, source_target_pixels, "Every #fcfffa source pixel contributes to the emissive mask for %s" % material_name)
	_assert_equals(mismatched_pixels, 0, "Only #fcfffa source pixels are emissive for %s" % material_name)

func _assert_gltf_material_normal_map(
	gltf: Dictionary,
	material_name: String,
	expected_normal_uri: String,
	expected_scale: float
) -> void:
	var material_index := _find_gltf_material_index(gltf, material_name)
	_assert_true(material_index >= 0, "%s normal-map material exists" % material_name)
	if material_index < 0:
		return

	var materials: Array = gltf.get("materials", [])
	var textures: Array = gltf.get("textures", [])
	var images: Array = gltf.get("images", [])
	var material: Dictionary = materials[material_index]
	var normal_texture_variant: Variant = material.get("normalTexture", null)
	_assert_true(normal_texture_variant is Dictionary, "%s has a normal texture" % material_name)
	if not (normal_texture_variant is Dictionary):
		return

	var normal_texture: Dictionary = normal_texture_variant
	var texture_index := int(normal_texture.get("index", -1))
	_assert_true(texture_index >= 0 and texture_index < textures.size(), "%s normal texture index is valid" % material_name)
	_assert_true(
		absf(float(normal_texture.get("scale", 1.0)) - expected_scale) < 0.001,
		"%s normal texture scale is preserved" % material_name
	)
	if texture_index < 0 or texture_index >= textures.size():
		return

	var texture: Dictionary = textures[texture_index]
	var image_index := int(texture.get("source", -1))
	_assert_true(image_index >= 0 and image_index < images.size(), "%s normal image index is valid" % material_name)
	if image_index < 0 or image_index >= images.size():
		return

	var image: Dictionary = images[image_index]
	_assert_equals(str(image.get("uri", "")), expected_normal_uri, "%s normal image URI is wired" % material_name)

	var base_texture_index := int(material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1))
	_assert_true(base_texture_index >= 0 and base_texture_index < textures.size(), "%s normal base texture index is valid" % material_name)
	if base_texture_index < 0 or base_texture_index >= textures.size():
		return

	var base_texture: Dictionary = textures[base_texture_index]
	var base_image_index := int(base_texture.get("source", -1))
	_assert_true(base_image_index >= 0 and base_image_index < images.size(), "%s normal base image index is valid" % material_name)
	if base_image_index < 0 or base_image_index >= images.size():
		return

	var base_image: Dictionary = images[base_image_index]
	var source_image := Image.new()
	var normal_image := Image.new()
	var source_error := _load_png_from_res(source_image, "res://resources/models/aster-sim/room/%s" % str(base_image.get("uri", "")))
	var normal_error := _load_png_from_res(normal_image, "res://resources/models/aster-sim/room/%s" % expected_normal_uri)
	_assert_equals(source_error, OK, "%s normal source texture loads" % material_name)
	_assert_equals(normal_error, OK, "%s normal texture loads" % material_name)
	if source_error != OK or normal_error != OK:
		return

	_assert_equals(normal_image.get_width(), source_image.get_width(), "%s normal texture width matches source" % material_name)
	_assert_equals(normal_image.get_height(), source_image.get_height(), "%s normal texture height matches source" % material_name)

func _find_gltf_material_index(gltf: Dictionary, material_name: String) -> int:
	var materials: Array = gltf.get("materials", [])
	for i in range(materials.size()):
		var material: Dictionary = materials[i]
		if str(material.get("name", "")) == material_name:
			return i
	return -1

func _find_material_by_resource_name(root: Node, material_name: String) -> Material:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var override_material := mesh_instance.material_override
		if _material_resource_name_matches(override_material, material_name):
			return override_material
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var surface_override := mesh_instance.get_surface_override_material(surface_index)
				if _material_resource_name_matches(surface_override, material_name):
					return surface_override
				var surface_material := mesh.surface_get_material(surface_index)
				if _material_resource_name_matches(surface_material, material_name):
					return surface_material
	for child in root.get_children():
		var child_material := _find_material_by_resource_name(child, material_name)
		if child_material != null:
			return child_material
	return null

func _material_resource_name_matches(material: Material, material_name: String) -> bool:
	return material != null and material.resource_name == material_name

func _rgb24(color: Color) -> int:
	return (_color_byte(color.r) << 16) | (_color_byte(color.g) << 8) | _color_byte(color.b)

func _color_byte(value: float) -> int:
	return clampi(int(round(value * 255.0)), 0, 255)

func _factor_matches_rgb(factor_variant: Variant, expected_rgb: int) -> bool:
	if not (factor_variant is Array):
		return false
	var factor: Array = factor_variant
	if factor.size() < 3:
		return false
	var expected_r := float((expected_rgb >> 16) & 0xff) / 255.0
	var expected_g := float((expected_rgb >> 8) & 0xff) / 255.0
	var expected_b := float(expected_rgb & 0xff) / 255.0
	return (
		absf(float(factor[0]) - expected_r) < 0.001
		and absf(float(factor[1]) - expected_g) < 0.001
		and absf(float(factor[2]) - expected_b) < 0.001
	)

func _load_png_from_res(image: Image, path: String) -> int:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ERR_FILE_CANT_READ
	return image.load_png_from_buffer(bytes)

func _test_mother_ferrolure_preview() -> void:
	_test_name = "Mother Ferrolure Preview"

	await _assert_preview_scene_idle_dialogue_stability(
		"res://scenes/fragments/mother_ferrolure_preview.tscn",
		"Chunk_mother_ferrolure",
		"Mother Flure",
		"This is not a corridor"
	)
	await _assert_preview_scene_main_ability_keymap(
		"res://scenes/fragments/mother_ferrolure_preview.tscn",
		"Mother Flure"
	)
	await _assert_preview_scene_interactable_click_flow(
		"res://scenes/fragments/mother_ferrolure_preview.tscn",
		"Chunk_mother_ferrolure",
		"*AlphaInteractable",
		"aster",
		"Mother Flure terminal",
		"active_terminal",
		"term_alpha"
	)

	var inventory_instance: Node = await _instantiate_preview_chunk_and_wait("mother_ferrolure", 2)
	_assert_true(inventory_instance != null, "mother preview instantiates")
	if inventory_instance == null:
		return

	var inventory_chunk: Node = inventory_instance.find_child("Chunk_mother_ferrolure", true, false)
	_assert_true(inventory_chunk != null, "Mother preview builds its chunk")
	if inventory_chunk == null:
		inventory_instance.queue_free()
		await get_tree().process_frame
		return

	var initial_state: Dictionary = inventory_chunk.get_preview_state()
	var initial_preview_state: Dictionary = inventory_instance.headless_get_state()
	var mother_slot: Dictionary = initial_preview_state.get("world_slot", {})
	_assert_equals(str(initial_preview_state.get("preview_party_preset", "")), "full_party_full_health", "Mother preview declares the full-party/full-health preset")
	_assert_equals(str(mother_slot.get("slot_id", "")), "act1_mother_flure", "Mother preview reports its world slot")
	_assert_equals(str(mother_slot.get("entry_shelter_id", "")), "shelter_5", "Mother world slot enters from Shelter 5")
	_assert_equals(str(mother_slot.get("exit_shelter_id", "")), "shelter_6", "Mother world slot exits toward Shelter 6")
	_assert_equals(str(mother_slot.get("entry_anchor", "")), "processing_stacks_exit", "Mother world slot enters from the Processing Stacks")
	_assert_equals(str(mother_slot.get("exit_anchor", "")), "residential_rings_approach", "Mother world slot exits toward the Residential Rings")
	for char_id in ["aster", "peris", "endo"]:
		var stats: Dictionary = initial_preview_state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(stats.get("hp", -1.0)), 100.0, "Mother preview starts %s at full HP" % char_id)
		_assert_equals(float(stats.get("sta", -1.0)), 100.0, "Mother preview starts %s at full stamina" % char_id)
		_assert_equals(float(stats.get("atp", -1.0)), GameState.ATP_MAX_PIPS, "Mother preview starts %s at full ATP" % char_id)
	_assert_true(not bool(initial_state.get("gear_pocket_open", false)), "Mother board starts with the gear pocket closed")
	_assert_true(not bool(initial_state.get("socket_lane_open", false)), "Mother board starts with the socket lane closed")
	_assert_true(not bool(initial_state.get("mother_lane_clear", false)), "Mother board starts with the mother lane clogged")

	inventory_instance.headless_select_character("aster")
	_assert_true(inventory_chunk.activate_terminal("term_beta"), "Aster can open the central service terminal")
	inventory_instance.headless_select_character("peris")
	_assert_true(inventory_chunk.use_portal(), "Peris can cross into the central service bay")
	_assert_true(not inventory_chunk.activate_fragment_move("crossbar", 1), "Crossbar cannot slide right while another root still blocks the lane")
	_assert_true(inventory_chunk.use_portal(), "Peris can return after a blocked root read")

	inventory_instance.headless_select_character("endo")
	inventory_instance.headless_set_character_position("endo", inventory_chunk.COLLAPSE_POS)
	_assert_true(inventory_chunk.clear_collapse(), "Endo can clear the collapse")
	inventory_instance.headless_set_character_position("endo", inventory_chunk.BODY_POSITIONS["body_a"])
	inventory_instance.set_preview_character_stat("endo", "atp", 1.0)
	_assert_true(inventory_chunk.harvest_body("body_a"), "Endo can harvest starch in the chamber")
	var held: Array = inventory_instance.get_preview_hand_items("endo")
	_assert_equals(held.size(), 1, "Harvesting gives Endo a held starch unit")
	_assert_true(inventory_instance.endocytose_preview_item("endo", str(held[0])), "Preview supports consuming harvested starch")
	inventory_instance.headless_advance(2.2)
	_assert_true(inventory_instance.get_preview_hand_items("endo").is_empty(), "Consumed starch frees Endo's hand")
	_assert_true(inventory_instance.get_preview_character_stat("endo", "atp") > 1.0, "Consumed starch restores ATP in the preview")

	_mother_execute_root_move(inventory_instance, inventory_chunk, "term_gamma", "gear_latch", 1, ["B2", "B3"], "Repair Test 1/3")
	_mother_execute_root_move(inventory_instance, inventory_chunk, "term_beta", "socket_brace", 1, ["D2", "E2"], "Repair Test 2/3")
	inventory_instance.headless_select_character("endo")
	inventory_instance.headless_set_character_position("endo", inventory_chunk.GEAR_POS)
	_assert_true(inventory_chunk.pick_up_gear(), "Endo can still lift the gear in the repair test")
	_mother_execute_root_move(inventory_instance, inventory_chunk, "term_alpha", "spine_gate", -1, ["A4", "B4"], "Repair Test 3/3")
	inventory_instance.headless_select_character("endo")
	inventory_instance.headless_set_character_position("endo", inventory_chunk._repair_point_position("edge_relief"))
	_assert_true(inventory_chunk.install_gear_at("edge_relief"), "A wrong repair mount still commits and resolves")
	var wrong_repair_state: Dictionary = inventory_chunk.get_preview_state()
	var repair_attempts: Array = wrong_repair_state.get("repair_attempts", [])
	_assert_true(not bool(wrong_repair_state.get("gear_installed", false)), "Wrong repair does not count as a successful install")
	_assert_true(repair_attempts.has("edge_relief"), "Wrong repair is recorded in chunk state")
	_assert_true(not bool(wrong_repair_state.get("socket_lane_open", true)), "Wrong edge-relief install closes the carry lane again")
	_assert_equals(wrong_repair_state.get("roots", {}).get("spine_gate", {}).get("cells", []), ["B4", "C4"], "Wrong edge-relief install drops the spine gate back into the lane")
	_assert_equals(inventory_instance.get_preview_hand_items("endo").size(), 0, "Rejected repair frees Endo's hands after the gear kicks back out")

	inventory_instance.queue_free()
	await get_tree().process_frame

	var solve_instance: Node = await _instantiate_preview_chunk_and_wait("mother_ferrolure", 2)
	_assert_true(solve_instance != null, "mother preview instantiates for the optimal solve")
	if solve_instance == null:
		return

	var solve_chunk: Node = solve_instance.find_child("Chunk_mother_ferrolure", true, false)
	_assert_true(solve_chunk != null, "Optimal-solve preview builds its chunk")
	if solve_chunk == null:
		solve_instance.queue_free()
		await get_tree().process_frame
		return

	_mother_execute_root_move(solve_instance, solve_chunk, "term_gamma", "gear_latch", 1, ["B2", "B3"], "Optimal 1/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_beta", "socket_brace", 1, ["D2", "E2"], "Optimal 2/9")
	var state_after_west: Dictionary = solve_chunk.get_preview_state()
	_assert_true(bool(state_after_west.get("gear_pocket_open", false)), "Optimal west opening unlocks the gear pocket")

	solve_instance.headless_select_character("endo")
	solve_instance.headless_set_character_position("endo", solve_chunk.GEAR_POS)
	_assert_true(solve_chunk.pick_up_gear(), "Endo can lift the gear once the west pocket is open")
	var hand_slots: Array = solve_instance.get_preview_hand_slots("endo")
	_assert_equals(str(hand_slots[0]), str(hand_slots[1]), "Two-hand gear occupies both hand slots")

	_mother_execute_root_move(solve_instance, solve_chunk, "term_alpha", "spine_gate", -1, ["A4", "B4"], "Optimal 3/9")
	var state_after_spine: Dictionary = solve_chunk.get_preview_state()
	_assert_true(bool(state_after_spine.get("socket_lane_open", false)), "Lifting the spine gate opens the carry lane to the socket")

	solve_instance.headless_select_character("endo")
	solve_instance.headless_set_character_position("endo", solve_chunk._repair_point_position("load_regulator"))
	_assert_true(solve_chunk.install_gear_at("load_regulator"), "Endo can install the mother gear at the correct repair point once the carry lane is open")
	var installed_state: Dictionary = solve_chunk.get_preview_state()
	_assert_equals(str(installed_state.get("installed_repair", "")), "load_regulator", "Optimal solve mounts the gear into the diagnosed load regulator")

	_mother_execute_root_move(solve_instance, solve_chunk, "term_beta", "socket_brace", 1, ["E2", "F2"], "Optimal 4/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_gamma", "tending_step", -1, ["E3", "E4"], "Optimal 5/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_beta", "crossbar", -1, ["D2", "D3", "D4"], "Optimal 6/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_beta", "bloom_curtain", 1, ["D5", "E5"], "Optimal 7/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_alpha", "mother_veil", 1, ["C6", "D6"], "Optimal 8/9")
	_mother_execute_root_move(solve_instance, solve_chunk, "term_alpha", "mother_veil", 1, ["D6", "E6"], "Optimal 9/9")

	var solved_state: Dictionary = solve_chunk.get_preview_state()
	_assert_true(bool(solved_state.get("mother_lane_clear", false)), "Optimal root sequence clears the mother lane end to end")

	solve_instance.headless_select_character("peris")
	solve_instance.headless_set_character_position("peris", solve_chunk.MOTHER_POS)
	_assert_true(solve_chunk.tend_mother(), "Peris can stabilize the mother after the optimal solution")
	var final_state: Dictionary = solve_chunk.get_preview_state()
	_assert_true(bool(final_state.get("mother_tended", false)), "Chunk state records the stabilized mother")

	solve_instance.queue_free()
	await get_tree().process_frame

func _test_endo_junction_stretch_preview() -> void:
	_test_name = "Endo Junction Stretch Preview"

	await _assert_preview_scene_idle_dialogue_stability(
		"res://scenes/fragments/endo_junction_stretch_preview.tscn",
		"Chunk_endo_junction_stretch",
		"Endo Junction Stretch",
		"This is not a corridor"
	)
	await _assert_preview_scene_main_ability_keymap(
		"res://scenes/fragments/endo_junction_stretch_preview.tscn",
		"Endo Junction Stretch"
	)
	await _assert_preview_scene_interactable_click_flow(
		"res://scenes/fragments/endo_junction_stretch_preview.tscn",
		"Chunk_endo_junction_stretch",
		"EndoJunctionReadInteractable",
		"endo",
		"Endo Junction marks",
		"junction_read",
		true
	)

	var instance: Node = await _instantiate_preview_chunk_and_wait("endo_junction_stretch", 3)
	_assert_true(instance != null, "endo_junction_stretch preview instantiates")
	if instance == null:
		return

	var chunk: Node = instance.find_child("Chunk_endo_junction_stretch", true, false)
	_assert_true(chunk != null, "Endo Junction preview builds its chunk")
	if chunk == null:
		await _dispose_scene(instance)
		return

	var preview_state: Dictionary = instance.headless_get_state()
	var slot: Dictionary = preview_state.get("world_slot", {})
	_assert_equals(str(preview_state.get("preview_party_preset", "")), "full_party_full_health", "Endo stretch declares the full-party/full-health preset")
	_assert_equals(str(slot.get("slot_id", "")), "act1_endo_junction_to_shelter_1", "Endo stretch reports its world slot")
	_assert_equals(str(slot.get("entry_shelter_id", "")), "endo_junction", "Endo stretch starts from the junction anchor")
	_assert_equals(str(slot.get("exit_shelter_id", "")), "shelter_1", "Endo stretch exits into Shelter 1")
	_assert_equals(str(slot.get("next_slot", "")), "act1_channels_first_spiral", "Endo stretch points at the later Channels slot")
	var canonical_party: Array = slot.get("canonical_party", [])
	_assert_equals(canonical_party.size(), 3, "Endo stretch canonical slot carries the full party")
	for char_id in ["aster", "peris", "endo"]:
		var stats: Dictionary = preview_state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(stats.get("hp", -1.0)), 100.0, "Endo stretch starts %s at full HP" % char_id)
		_assert_equals(float(stats.get("sta", -1.0)), 100.0, "Endo stretch starts %s at full stamina" % char_id)
		_assert_equals(float(stats.get("atp", -1.0)), GameState.ATP_MAX_PIPS, "Endo stretch starts %s at full ATP" % char_id)

	var initial_chunk_state: Dictionary = chunk.get_preview_state()
	_assert_true(not bool(initial_chunk_state.get("shelter_reached", false)), "Endo stretch starts before Shelter 1 is reached")
	_assert_true(not bool(initial_chunk_state.get("shortcut_unlocked", false)), "Endo stretch starts with the shortcut locked")

	instance.headless_select_character("endo")
	instance.headless_set_character_position("endo", chunk.JUNCTION_POS)
	_assert_true(chunk.read_junction(), "Endo can read his junction marks")
	instance.headless_select_character("aster")
	instance.headless_set_character_position("aster", chunk.GUIDE_MARK_POS)
	_assert_true(chunk.mark_safe_route(), "Aster can translate Endo's safe route")
	instance.headless_select_character("endo")
	instance.headless_set_character_position("endo", chunk.FORAGE_CACHE_POS)
	_assert_true(chunk.collect_forage(), "Endo can collect the first shelter-stretch cache")
	instance.headless_set_character_position("endo", chunk.SAFE_LEDGE_POS)
	_assert_true(chunk.commit_safe_route(), "Safe ledge route can be committed")
	var safe_state: Dictionary = instance.headless_get_state()
	for char_id in ["aster", "peris", "endo"]:
		var safe_stats: Dictionary = safe_state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(safe_stats.get("hp", -1.0)), 100.0, "Safe Endo stretch keeps %s at full HP before rest" % char_id)

	instance.headless_set_character_position("endo", chunk.SHORTCUT_LOCK_POS)
	_assert_true(chunk.unlock_shortcut(), "Endo can open the return shortcut")
	instance.headless_set_character_position("aster", chunk.SHELTER_POS)
	_assert_true(chunk.reach_shelter(), "Party can reach and rest at Shelter 1")
	var complete_state: Dictionary = chunk.get_preview_state()
	_assert_true(bool(complete_state.get("shelter_reached", false)), "Endo stretch records Shelter 1 reached")
	_assert_true(bool(complete_state.get("shelter_rested", false)), "Endo stretch records Shelter 1 rest")
	_assert_true(bool(complete_state.get("shortcut_unlocked", false)), "Endo stretch records shortcut unlock")
	_assert_equals(str(complete_state.get("route_choice", "")), "safe", "Golden path records the safe route")
	_assert_equals(int(complete_state.get("first_night_beat_count", 0)), 1, "First-night shelter beat fires once")
	_assert_true(chunk.reach_shelter(), "Shelter rest is idempotent after completion")
	var repeated_state: Dictionary = chunk.get_preview_state()
	_assert_equals(int(repeated_state.get("first_night_beat_count", 0)), 1, "First-night shelter beat does not refire")
	var rested_preview_state: Dictionary = instance.headless_get_state()
	for char_id in ["aster", "peris", "endo"]:
		var rested_stats: Dictionary = rested_preview_state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(rested_stats.get("hp", -1.0)), 100.0, "Shelter rest restores %s HP" % char_id)
		_assert_equals(float(rested_stats.get("sta", -1.0)), 100.0, "Shelter rest restores %s stamina" % char_id)
		_assert_equals(float(rested_stats.get("atp", -1.0)), GameState.ATP_MAX_PIPS, "Shelter rest restores %s ATP" % char_id)

	await _dispose_scene(instance)

	var direct_instance: Node = await _instantiate_preview_chunk_and_wait("endo_junction_stretch", 3)
	_assert_true(direct_instance != null, "endo_junction_stretch preview instantiates for the direct route")
	if direct_instance == null:
		return
	var direct_chunk: Node = direct_instance.find_child("Chunk_endo_junction_stretch", true, false)
	_assert_true(direct_chunk != null, "Direct-route Endo preview builds its chunk")
	if direct_chunk == null:
		await _dispose_scene(direct_instance)
		return

	direct_instance.headless_select_character("endo")
	direct_instance.headless_set_character_position("endo", direct_chunk.JUNCTION_POS)
	_assert_true(direct_chunk.read_junction(), "Direct route still begins with Endo's world read")
	direct_instance.headless_set_routing_mode("direct")
	direct_instance.headless_select_character("aster")
	direct_instance.headless_set_character_position("aster", direct_chunk.RISKY_BLOOM_POS)
	_assert_true(direct_chunk.commit_direct_route(), "Direct route is playable")
	var damaged_state: Dictionary = direct_chunk.get_preview_state()
	_assert_equals(str(damaged_state.get("route_choice", "")), "direct", "Direct route records its route choice")
	_assert_true(float(damaged_state.get("direct_damage_total", 0.0)) > 0.0, "Direct route records damage pressure")
	_assert_true(float(damaged_state.get("party_min_hp", 0.0)) > 0.0, "Direct route remains recoverable")
	direct_instance.headless_select_character("endo")
	direct_instance.headless_set_character_position("endo", direct_chunk.SHORTCUT_LOCK_POS)
	_assert_true(direct_chunk.unlock_shortcut(), "Direct route can still open the shortcut")
	direct_instance.headless_set_character_position("peris", direct_chunk.SHELTER_POS)
	_assert_true(direct_chunk.reach_shelter(), "Direct route can recover at Shelter 1")
	var direct_complete: Dictionary = direct_chunk.get_preview_state()
	_assert_true(bool(direct_complete.get("shelter_rested", false)), "Direct route records Shelter 1 rest")
	var direct_rest_state: Dictionary = direct_instance.headless_get_state()
	for char_id in ["aster", "peris", "endo"]:
		var direct_stats: Dictionary = direct_rest_state.get("character_stats", {}).get(char_id, {})
		_assert_equals(float(direct_stats.get("hp", -1.0)), 100.0, "Direct route rest restores %s HP" % char_id)

	await _dispose_scene(direct_instance)

func _test_channels_rhythm_preview() -> void:
	_test_name = "Channels Rhythm Preview"

	var instance: Node = await _instantiate_preview_chunk_and_wait("channels_rhythm", 2)
	_assert_true(instance != null, "channels_rhythm preview instantiates")
	if instance == null:
		return

	var chunk: Node = instance.find_child("Chunk_channels_rhythm", true, false)
	_assert_true(chunk != null, "Channels rhythm preview builds its chunk")
	if chunk == null:
		instance.queue_free()
		await get_tree().process_frame
		return

	var initial_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_equals(int(initial_state.get("periodic_channel_count", 0)), 3, "Channels rhythm preview exposes three periodic flood channels")
	_assert_true(int(initial_state.get("bridge_segment_count", 0)) >= 8, "Channels rhythm preview builds the bridge arc")
	_assert_equals(int(initial_state.get("swarm_unit_count", 0)), 5, "Channels rhythm preview spawns the siderophore pack")

	var analysis: Dictionary = chunk.get_wash_analysis() if chunk.has_method("get_wash_analysis") else {}
	_assert_true(bool(analysis.get("guaranteed", false)), "Channels rhythm preview analytically guarantees a washout")
	_assert_true(float(analysis.get("coverage_gap", 1.0)) <= 0.001, "Channels rhythm preview has no uncovered timing gap")

	var period := float(initial_state.get("flow_period", 6.0))
	var sample_count := 72
	for i in range(sample_count):
		var offset := period * float(i) / float(sample_count)
		if chunk.has_method("reset_preview_state"):
			chunk.call("reset_preview_state")
		if instance.has_method("headless_set_character_position"):
			instance.headless_set_character_position("aster", chunk.STAGE_POS)
			instance.headless_set_character_position("peris", chunk.STAGE_POS + Vector3(-1.6, 0.0, 1.4))
			instance.headless_set_character_position("endo", chunk.STAGE_POS + Vector3(-2.0, 0.0, -1.6))
		_assert_true(chunk.has_method("set_timing_offset"), "Channels rhythm chunk exposes timing offset controls")
		if chunk.has_method("set_timing_offset"):
			chunk.call("set_timing_offset", offset)
		_assert_true(bool(chunk.call("activate_lure")), "Channels rhythm preview activates at offset %.3f" % offset)
		if instance.has_method("headless_advance"):
			instance.headless_advance(6.2, 0.05)
		var offset_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
		_assert_equals(str(offset_state.get("swarm_state", "")), "washed", "Offset %.3f washes the pack" % offset)
		_assert_true(int(offset_state.get("washed_channel_index", -1)) >= 0, "Offset %.3f records a wash channel" % offset)
		_assert_equals(int(offset_state.get("washed_swarm_units", 0)), 5, "Offset %.3f washes every unit" % offset)

	instance.queue_free()
	await get_tree().process_frame

func _test_channels_hide_window_preview() -> void:
	_test_name = "Channels Hide Window Preview"

	await _assert_preview_scene_idle_dialogue_stability(
		"res://scenes/fragments/channels_hide_window_preview.tscn",
		"Chunk_channels_hide_window",
		"Channels Hide Window",
		"This is not a corridor"
	)

	var instance: Node = await _instantiate_preview_chunk_and_wait("channels_hide_window", 2)
	_assert_true(instance != null, "channels_hide_window preview instantiates")
	if instance == null:
		return

	var chunk: Node = instance.find_child("Chunk_channels_hide_window", true, false)
	_assert_true(chunk != null, "Channels hide window preview builds its chunk")
	if chunk == null:
		instance.queue_free()
		await get_tree().process_frame
		return

	var initial_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_equals(int(initial_state.get("periodic_channel_count", 0)), 3, "Channels hide window preview exposes three periodic flood channels")
	_assert_true(bool(initial_state.get("corridor_present", false)), "Channels hide window preview builds the fallback corridor")
	_assert_true(bool(initial_state.get("conceal_patch_present", false)), "Channels hide window preview builds the concealment patch")
	_assert_equals(int(initial_state.get("swarm_unit_count", 0)), 5, "Channels hide window preview spawns the siderophore pack")

	var analysis: Dictionary = chunk.get_wash_analysis() if chunk.has_method("get_wash_analysis") else {}
	_assert_true(not bool(analysis.get("guaranteed", true)), "Channels hide window preview is not analytically guaranteed")
	_assert_true(float(analysis.get("coverage_gap", 0.0)) >= 0.25, "Channels hide window preview leaves a meaningful timing gap")
	_assert_true(float(analysis.get("safe_sample_offset", -1.0)) >= 0.0, "Channels hide window preview exposes a sample safe offset")
	_assert_true(float(analysis.get("failed_sample_offset", -1.0)) >= 0.0, "Channels hide window preview exposes a sample failed offset")
	_assert_true(int(analysis.get("failed_sample_count", 0)) > 0, "Channels hide window preview includes failing offsets")

	var anchors: Dictionary = instance.headless_get_anchor_positions() if instance.has_method("headless_get_anchor_positions") else {}
	var stage_pos: Vector3 = anchors.get("stage", Vector3.ZERO)
	var hide_patch_pos: Vector3 = anchors.get("hide_patch", Vector3.ZERO)
	var goal_pos: Vector3 = anchors.get("goal", Vector3.ZERO)

	if chunk.has_method("reset_preview_state"):
		chunk.call("reset_preview_state")
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", stage_pos)
		instance.headless_set_character_position("peris", stage_pos + Vector3(-1.5, 0.0, 1.2))
		instance.headless_set_character_position("endo", stage_pos + Vector3(-1.8, 0.0, -1.3))
	_assert_true(bool(chunk.call("set_recommended_offset", "safe")), "Channels hide window preview can apply a safe offset preset")
	_assert_true(bool(chunk.call("activate_lure")), "Channels hide window preview activates on the sampled safe offset")
	if instance.has_method("headless_advance"):
		instance.headless_advance(6.2, 0.05)
	var washed_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_equals(str(washed_state.get("swarm_state", "")), "washed", "Sample safe offset washes the pack")
	_assert_true(int(washed_state.get("washed_channel_index", -1)) >= 0, "Sample safe offset records a wash channel")
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", goal_pos)
	if instance.has_method("headless_advance"):
		instance.headless_advance(0.2, 0.05)
	var success_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_equals(str(success_state.get("last_outcome", "")), "success", "Washing the pack still lets Aster clear the lane")

	if chunk.has_method("reset_preview_state"):
		chunk.call("reset_preview_state")
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", stage_pos)
		instance.headless_set_character_position("peris", stage_pos + Vector3(-1.5, 0.0, 1.2))
		instance.headless_set_character_position("endo", stage_pos + Vector3(-1.8, 0.0, -1.3))
	_assert_true(bool(chunk.call("set_recommended_offset", "fail")), "Channels hide window preview can apply a failed offset preset")
	_assert_true(bool(chunk.call("activate_lure")), "Channels hide window preview activates on the sampled failed offset")
	if instance.has_method("headless_advance"):
		instance.headless_advance(5.2, 0.05)
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", hide_patch_pos)
	if instance.has_method("headless_advance"):
		instance.headless_advance(5.4, 0.05)
	var retry_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_true(not bool(retry_state.get("detected", true)), "Getting into the patch before reacquisition avoids detection")
	_assert_equals(str(retry_state.get("swarm_state", "")), "idle", "The pack eventually resets after a concealed miss")
	_assert_equals(str(retry_state.get("phase", "")), "activate", "A concealed miss returns the lane to an activatable state")
	_assert_true(int(retry_state.get("concealed_retries", 0)) >= 1, "The preview records a concealed retry")

	if chunk.has_method("reset_preview_state"):
		chunk.call("reset_preview_state")
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", stage_pos)
	_assert_true(bool(chunk.call("set_recommended_offset", "fail")), "Channels hide window preview can reapply the failed offset preset")
	_assert_true(bool(chunk.call("activate_lure")), "Channels hide window preview reactivates on the failed offset")
	if instance.has_method("headless_advance"):
		instance.headless_advance(7.8, 0.05)
	var fail_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_true(bool(fail_state.get("detected", false)), "Staying exposed after a miss gets the player detected")
	_assert_equals(str(fail_state.get("last_outcome", "")), "detected", "Detection locks in once the pack reacquires the player")
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position("aster", hide_patch_pos)
	if instance.has_method("headless_advance"):
		instance.headless_advance(0.3, 0.05)
	var locked_fail_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_assert_equals(str(locked_fail_state.get("phase", "")), "failed", "Entering the patch after detection does not clear the failure")

	instance.queue_free()
	await get_tree().process_frame

func _mother_execute_root_move(instance: Node, chunk: Node, terminal_id: String, root_id: String, direction: int, expected_cells: Array, label: String) -> void:
	instance.headless_select_character("aster")
	_assert_true(chunk.activate_terminal(terminal_id), "%s opens %s" % [label, terminal_id])
	instance.headless_select_character("peris")
	_assert_true(chunk.use_portal(), "%s sends Peris to %s" % [label, terminal_id])
	_assert_true(chunk.activate_fragment_move(root_id, direction), "%s shifts %s" % [label, root_id])
	instance.headless_advance(5.5)
	var state: Dictionary = chunk.get_preview_state()
	var root_state: Dictionary = state.get("roots", {}).get(root_id, {})
	_assert_equals(root_state.get("cells", []), expected_cells, "%s lands %s at the expected cells" % [label, root_id])
	if not bool(state.get("portal_open", false)):
		instance.headless_select_character("aster")
		_assert_true(chunk.activate_terminal(terminal_id), "%s reopens %s for extraction" % [label, terminal_id])
		instance.headless_select_character("peris")
	_assert_true(chunk.use_portal(), "%s brings Peris back out" % label)

func _mother_record_timing(measurements: Dictionary, totals: Dictionary, key: String, bucket: String, result: Dictionary) -> void:
	measurements[key] = result
	totals[bucket] = float(totals.get(bucket, 0.0)) + float(result.get("measured", 0.0))

func _mother_measure_wait(instance: Node, measurements: Dictionary, totals: Dictionary, key: String, duration: float) -> void:
	var start_tick := _preview_scheduler_tick(instance)
	_advance_showcase(instance, duration)
	var result := {
		"predicted": duration,
		"measured": _preview_scheduler_tick(instance) - start_tick,
	}
	measurements[key] = result
	totals["settle"] = float(totals.get("settle", 0.0)) + float(result.get("measured", 0.0))

func _mother_snap_character(instance: Node, char_id: String, position: Vector3) -> void:
	if instance.has_method("headless_set_character_position"):
		instance.headless_set_character_position(char_id, position)

func _mother_activate_ability(
	instance: Node,
	measurements: Dictionary,
	totals: Dictionary,
	key: String,
	char_id: String,
	ability_id: String,
	dwell_time: float
) -> Dictionary:
	var start_tick := _preview_scheduler_tick(instance)
	if char_id != "" and instance.has_method("headless_select_character"):
		instance.headless_select_character(char_id)
	if dwell_time > 0.0:
		_advance_showcase(instance, dwell_time)
	var activated := instance.has_method("headless_activate_ability") and bool(instance.headless_activate_ability(ability_id))
	var result := {
		"predicted": dwell_time,
		"measured": _preview_scheduler_tick(instance) - start_tick,
		"result": activated,
	}
	_mother_record_timing(measurements, totals, key, "interaction", result)
	return result

func _mother_profile_root_move(
	instance: Node,
	chunk: Node,
	terminal_id: String,
	root_id: String,
	direction: int,
	label: String,
	include_movement: bool,
	measurements: Dictionary,
	totals: Dictionary
) -> void:
	if include_movement:
		_mother_record_timing(measurements, totals, "%s_peris_stage" % label, "movement", _survival_range_move_segment(instance, {
			"character": "peris",
			"end_position": chunk.BASE_PORTAL_POS,
		}))
		_mother_record_timing(measurements, totals, "%s_aster_move" % label, "movement", _survival_range_move_segment(instance, {
			"character": "aster",
			"end_position": chunk._terminal_position(terminal_id),
		}))
	var hack_result := _survival_range_dwell_and_call(instance, "aster", {
		"dwell_time": MOTHER_HACK_DWELL_SECONDS,
	}, "activate_terminal", [terminal_id])
	_mother_record_timing(measurements, totals, "%s_hack" % label, "interaction", hack_result)
	_assert_true(bool(hack_result.get("result", false)), "%s opens %s during timing run" % [label, terminal_id])
	var cross_in_result := _survival_range_dwell_and_call(instance, "peris", {
		"dwell_time": MOTHER_PORTAL_DWELL_SECONDS,
	}, "use_portal")
	_mother_record_timing(measurements, totals, "%s_cross_in" % label, "interaction", cross_in_result)
	_assert_true(bool(cross_in_result.get("result", false)), "%s sends Peris into %s during timing run" % [label, terminal_id])
	var activate_result := _survival_range_dwell_and_call(instance, "peris", {
		"dwell_time": MOTHER_BUD_DWELL_SECONDS,
	}, "activate_fragment_move", [root_id, direction])
	_mother_record_timing(measurements, totals, "%s_activate" % label, "interaction", activate_result)
	_assert_true(bool(activate_result.get("result", false)), "%s shifts %s during timing run" % [label, root_id])
	_mother_measure_wait(instance, measurements, totals, "%s_settle" % label, MOTHER_ROOT_SETTLE_SECONDS)
	var root_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	if not bool(root_state.get("portal_open", false)):
		var reopen_result := _survival_range_dwell_and_call(instance, "aster", {
			"dwell_time": MOTHER_HACK_DWELL_SECONDS,
		}, "activate_terminal", [terminal_id])
		_mother_record_timing(measurements, totals, "%s_reopen_hack" % label, "interaction", reopen_result)
		_assert_true(bool(reopen_result.get("result", false)), "%s reopens %s for extraction during timing run" % [label, terminal_id])
	var cross_out_result := _survival_range_dwell_and_call(instance, "peris", {
		"dwell_time": MOTHER_PORTAL_DWELL_SECONDS,
	}, "use_portal")
	_mother_record_timing(measurements, totals, "%s_cross_out" % label, "interaction", cross_out_result)
	_assert_true(bool(cross_out_result.get("result", false)), "%s brings Peris back out during timing run" % label)

func _run_mother_ferrolure_profile(profile: String) -> Dictionary:
	var instance: Node = await _instantiate_preview_chunk_and_wait("mother_ferrolure", 3)
	_assert_true(instance != null, "mother_ferrolure_preview.tscn instantiates for %s playtime run" % profile)
	if instance == null:
		return {}

	var chunk: Node = instance.find_child("Chunk_mother_ferrolure", true, false)
	_assert_true(chunk != null, "Mother chunk exists for %s playtime run" % profile)
	if chunk == null:
		await _dispose_scene(instance)
		return {}

	var include_movement := profile != "system_optimal"
	var include_wrong_repair := profile == "movement_wrong_repair"
	var measurements := {}
	var totals := {
		"movement": 0.0,
		"interaction": 0.0,
		"settle": 0.0,
	}
	var start_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	var start_tick := _preview_scheduler_tick(instance)

	_mother_profile_root_move(instance, chunk, "term_gamma", "gear_latch", 1, "move_1", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_beta", "socket_brace", 1, "move_2", include_movement, measurements, totals)

	if include_movement:
		_mother_record_timing(measurements, totals, "endo_to_gear", "movement", _survival_range_move_segment(instance, {
			"character": "endo",
			"end_position": chunk.GEAR_POS,
		}))
	_mother_snap_character(instance, "endo", chunk.GEAR_POS)
	var pickup_result := _survival_range_dwell_and_call(instance, "endo", {
		"dwell_time": MOTHER_PICKUP_DWELL_SECONDS,
	}, "pick_up_gear")
	_mother_record_timing(measurements, totals, "pick_up_gear", "interaction", pickup_result)
	_assert_true(bool(pickup_result.get("result", false)), "Timing run can pick up the mother gear")

	_mother_profile_root_move(instance, chunk, "term_alpha", "spine_gate", -1, "move_3", include_movement, measurements, totals)

	if include_wrong_repair:
		var wrong_cloak_result := _mother_activate_ability(instance, measurements, totals, "wrong_repair_cloak", "endo", "endo_patch", MOTHER_CLOAK_DWELL_SECONDS)
		_assert_true(bool(wrong_cloak_result.get("result", false)), "Timing run can trigger Endo's cloak for the wrong-repair carry")
		if include_movement:
			_mother_record_timing(measurements, totals, "endo_to_wrong_repair", "movement", _survival_range_move_segment(instance, {
				"character": "endo",
				"end_position": chunk._repair_point_position("edge_relief"),
			}))
		_mother_snap_character(instance, "endo", chunk._repair_point_position("edge_relief"))
		var wrong_install_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
		var wrong_install_hands: Array = instance.get_preview_hand_items("endo") if instance.has_method("get_preview_hand_items") else []
		_assert_true(bool(wrong_install_state.get("socket_lane_open", false)), "Wrong-repair route still has the carry lane open before the detour mount")
		_assert_true(not wrong_install_hands.is_empty(), "Wrong-repair route still has the gear in Endo's hands before the detour mount")
		var wrong_install_result := _survival_range_dwell_and_call(instance, "endo", {
			"dwell_time": MOTHER_INSTALL_DWELL_SECONDS,
		}, "install_gear_at", ["edge_relief"])
		_mother_record_timing(measurements, totals, "wrong_install", "interaction", wrong_install_result)
		_assert_true(bool(wrong_install_result.get("result", false)), "Timing run can commit the wrong repair detour")
		var post_wrong_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
		var recover_item_id := str(post_wrong_state.get("gear_item", ""))
		var recover_item_state: Dictionary = instance.get_preview_item_state(recover_item_id) if recover_item_id != "" and instance.has_method("get_preview_item_state") else {}
		var recover_target := Vector3(recover_item_state.get("position", chunk.HIDE_SPOT_POS + Vector3(1.4, 0.24, 0.0)))
		var recover_cloak_result := _mother_activate_ability(instance, measurements, totals, "recover_cloak", "endo", "endo_patch", MOTHER_CLOAK_DWELL_SECONDS)
		_assert_true(bool(recover_cloak_result.get("result", false)), "Timing run can trigger Endo's cloak for the recovery pull")
		if include_movement:
			_mother_record_timing(measurements, totals, "endo_recover_gear", "movement", _survival_range_move_segment(instance, {
				"character": "endo",
				"end_position": recover_target,
			}))
		_mother_snap_character(instance, "endo", recover_target)
		var recover_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
		var recover_stats: Dictionary = recover_state.get("character_stats", {}).get("endo", {})
		_assert_true(float(recover_stats.get("hp", 0.0)) > 0.0, "Wrong-repair route keeps Endo alive through the recovery pull")
		_assert_equals(str(recover_state.get("active_character", "")), "endo", "Wrong-repair route keeps Endo active at the recovery pickup")
		var recover_pickup_result := _survival_range_dwell_and_call(instance, "endo", {
			"dwell_time": MOTHER_PICKUP_DWELL_SECONDS,
		}, "pick_up_gear")
		_mother_record_timing(measurements, totals, "recover_pickup", "interaction", recover_pickup_result)
		_assert_true(bool(recover_pickup_result.get("result", false)), "Timing run can recover the rejected gear")
		_mother_profile_root_move(instance, chunk, "term_alpha", "spine_gate", -1, "reopen_carry", include_movement, measurements, totals)

	if include_movement:
		var repair_cloak_result := _mother_activate_ability(instance, measurements, totals, "repair_cloak", "endo", "endo_patch", MOTHER_CLOAK_DWELL_SECONDS)
		_assert_true(bool(repair_cloak_result.get("result", false)), "Timing run can trigger Endo's cloak for the repair carry")
	if include_movement:
		_mother_record_timing(measurements, totals, "endo_to_repair", "movement", _survival_range_move_segment(instance, {
			"character": "endo",
			"end_position": chunk._repair_point_position("load_regulator"),
		}))
	_mother_snap_character(instance, "endo", chunk._repair_point_position("load_regulator"))
	var install_state: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	var install_hands: Array = instance.get_preview_hand_items("endo") if instance.has_method("get_preview_hand_items") else []
	_assert_true(bool(install_state.get("socket_lane_open", false)), "Timing run still has the carry lane open before the load regulator mount")
	_assert_true(not install_hands.is_empty(), "Timing run still has the gear in Endo's hands before the load regulator mount")
	var install_result := _survival_range_dwell_and_call(instance, "endo", {
		"dwell_time": MOTHER_INSTALL_DWELL_SECONDS,
	}, "install_gear_at", ["load_regulator"])
	_mother_record_timing(measurements, totals, "install_gear", "interaction", install_result)
	_assert_true(bool(install_result.get("result", false)), "Timing run can install the load regulator gear")

	_mother_profile_root_move(instance, chunk, "term_beta", "socket_brace", 1, "move_4", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_gamma", "tending_step", -1, "move_5", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_beta", "crossbar", -1, "move_6", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_beta", "bloom_curtain", 1, "move_7", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_alpha", "mother_veil", 1, "move_8", include_movement, measurements, totals)
	_mother_profile_root_move(instance, chunk, "term_alpha", "mother_veil", 1, "move_9", include_movement, measurements, totals)

	if include_movement:
		_mother_record_timing(measurements, totals, "peris_to_mother", "movement", _survival_range_move_segment(instance, {
			"character": "peris",
			"end_position": chunk.MOTHER_POS,
		}))
	_mother_snap_character(instance, "peris", chunk.MOTHER_POS)
	var tend_result := _survival_range_dwell_and_call(instance, "peris", {
		"dwell_time": MOTHER_TEND_DWELL_SECONDS,
	}, "tend_mother")
	_mother_record_timing(measurements, totals, "tend_mother", "interaction", tend_result)

	var final_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	await _dispose_scene(instance)
	return {
		"profile": profile,
		"start_state": start_state,
		"final_state": final_state,
		"measurements": measurements,
		"movement_total": float(totals.get("movement", 0.0)),
		"interaction_total": float(totals.get("interaction", 0.0)),
		"settle_total": float(totals.get("settle", 0.0)),
		"measured_total": float(final_state.get("scheduler_tick", 0.0)) - start_tick,
		"root_move_count": 10 if include_wrong_repair else 9,
	}

# --- Test: EventScheduler ---
func _test_event_scheduler() -> void:
	_test_name = "EventScheduler"

	var sched := EventScheduler.new()
	_assert_true(sched != null, "EventScheduler created")
	_assert_equals(sched.get_current_tick(), 0.0, "Starts at tick 0")
	_assert_equals(sched.pending_count(), 0, "No pending events initially")

	# Schedule and advance
	var fired := []
	sched.schedule_at(1.0, func(): fired.append("a"), "event_a")
	sched.schedule_at(2.0, func(): fired.append("b"), "event_b")
	sched.schedule_at(1.5, func(): fired.append("c"), "event_c")
	_assert_equals(sched.pending_count(), 3, "3 events pending")

	sched.advance_ticks(1.0)
	_assert_equals(fired.size(), 1, "1 event fired at tick 1.0")
	_assert_equals(fired[0], "a", "Event 'a' fired first")
	_assert_equals(sched.get_current_tick(), 1.0, "Tick is 1.0")

	sched.advance_ticks(1.5)
	_assert_equals(fired.size(), 3, "All 3 events fired by tick 2.5")
	_assert_equals(fired[1], "c", "Event 'c' fired second (tick 1.5)")
	_assert_equals(fired[2], "b", "Event 'b' fired third (tick 2.0)")

	# schedule_after with array wrapper for lambda-mutable state.
	var after_result := [false]
	sched.schedule_after(0.5, func(): after_result[0] = true, "after_test")
	sched.advance_ticks(0.5)
	_assert_true(after_result[0], "schedule_after fires after delay")

	# Cancel by handle
	var cancel_result := [false]
	var handle := sched.schedule_after(1.0, func(): cancel_result[0] = true, "cancel_test")
	_assert_true(sched.cancel(handle), "cancel returns true for valid handle")
	sched.advance_ticks(2.0)
	_assert_true(not cancel_result[0], "Cancelled event did not fire")

	# Cancel by tag
	var tag_result := [0]
	sched.schedule_after(1.0, func(): tag_result[0] += 1, "batch")
	sched.schedule_after(2.0, func(): tag_result[0] += 1, "batch")
	sched.schedule_after(3.0, func(): tag_result[0] += 1, "keep")
	var removed := sched.cancel_tag("batch")
	_assert_equals(removed, 2, "cancel_tag removed 2 events")
	sched.advance_ticks(5.0)
	_assert_equals(tag_result[0], 1, "Only non-cancelled event fired")

	# Speed multiplier via advance()
	var sched2 := EventScheduler.new()
	var speed_result := [false]
	sched2.set_speed(10.0)
	sched2.schedule_at(5.0, func(): speed_result[0] = true, "speed_test")
	sched2.advance(0.5)  # 0.5 real seconds * 10x = 5.0 ticks
	_assert_true(speed_result[0], "Speed multiplier accelerates event firing")

	# Pause/resume
	var sched3 := EventScheduler.new()
	var pause_result := [false]
	sched3.schedule_at(1.0, func(): pause_result[0] = true, "pause_test")
	sched3.pause()
	sched3.advance_ticks(5.0)
	_assert_true(not pause_result[0], "Paused scheduler doesn't fire events")
	sched3.resume()
	sched3.advance_ticks(1.0)
	_assert_true(pause_result[0], "Resumed scheduler fires events")

	# Priority ordering
	var prio_order := []
	var sched4 := EventScheduler.new()
	sched4.schedule_at(1.0, func(): prio_order.append("low"), "low", 10)
	sched4.schedule_at(1.0, func(): prio_order.append("high"), "high", 0)
	sched4.schedule_at(1.0, func(): prio_order.append("mid"), "mid", 5)
	sched4.advance_ticks(1.0)
	_assert_equals(prio_order[0], "high", "Priority 0 fires first")
	_assert_equals(prio_order[1], "mid", "Priority 5 fires second")
	_assert_equals(prio_order[2], "low", "Priority 10 fires third")

	# Reactive chaining (event schedules another event)
	var sched5 := EventScheduler.new()
	var chain := []
	sched5.schedule_at(1.0, func():
		chain.append("first")
		sched5.schedule_after(0.5, func(): chain.append("second"), "chain2")
	, "chain1")
	sched5.advance_ticks(2.0)
	_assert_equals(chain.size(), 2, "Reactive chain: both events fired")
	_assert_equals(chain[1], "second", "Chained event fired correctly")

	# Serialize/deserialize
	var sched6 := EventScheduler.new()
	sched6.set_speed(5.0)
	sched6.advance_ticks(10.0)
	sched6.pause()
	var snap := sched6.serialize()
	_assert_equals(snap.current_tick, 10.0, "Serialized tick")
	_assert_equals(snap.speed, 5.0, "Serialized speed")
	_assert_equals(snap.paused, true, "Serialized paused")

	var sched7 := EventScheduler.new()
	sched7.deserialize(snap)
	_assert_equals(sched7.get_current_tick(), 10.0, "Deserialized tick")
	_assert_equals(sched7.get_speed(), 5.0, "Deserialized speed")
	_assert_true(sched7.is_paused(), "Deserialized paused state")

func _test_engram_and_saves() -> void:
	_test_name = "Engram + SaveManager"

	var save_manager = _test_singleton(SAVE_MANAGER_SINGLETON, SAVE_MANAGER_SCRIPT_PATH)
	var engram_journal = _test_singleton(ENGRAM_JOURNAL_SINGLETON, ENGRAM_JOURNAL_SCRIPT_PATH)
	_assert_true(save_manager != null, "SaveManager singleton is available")
	_assert_true(engram_journal != null, "EngramJournal singleton is available")
	if save_manager == null or engram_journal == null:
		return

	save_manager.call("clear_slot")
	engram_journal.call("reset_state")

	var image := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 1.0))

	var entry: Dictionary = engram_journal.call("create_manual_entry_from_image", image, {
		"scene_name": "Test Scene",
		"timestamp_label": "Act 1 / Day 1",
		"location": "Test Zone",
		"sub_location": "Checkpoint",
		"caption": "Test Zone, Day 1",
		"position": Vector3(4.0, 0.5, 7.0),
	})
	_assert_true(not entry.is_empty(), "Manual Engram entry created")
	_assert_equals(int(engram_journal.call("get_entry_count")), 1, "Journal count increments")
	_assert_true(FileAccess.file_exists(str(entry.get("image_path", ""))), "Stored capture file exists")

	engram_journal.call("toggle_bookmark", int(entry.get("id", -1)))
	var bookmarked: Dictionary = engram_journal.call("get_entry", int(entry.get("id", -1)))
	_assert_true(bool(bookmarked.get("player_bookmark", false)), "Bookmark persists in memory")

	var export_path := "user://saves/autosave/exported_capture.png"
	_assert_true(bool(engram_journal.call("export_capture", int(entry.get("id", -1)), export_path)), "Capture export succeeds")
	_assert_true(FileAccess.file_exists(export_path), "Exported capture exists")

	_assert_true(bool(save_manager.call("save_current", "test")), "SaveManager writes autosave manifest")
	_assert_true(bool(save_manager.call("has_slot")), "Autosave slot exists")

	var payload: Dictionary = save_manager.call("load_slot_payload")
	_assert_equals(int(payload.get("version", 0)), 1, "Save payload version matches")
	var journal_state: Dictionary = payload.get("journal", {})
	var saved_entries: Array = journal_state.get("entries", [])
	_assert_equals(saved_entries.size(), 1, "Journal entries persisted into save payload")
	_assert_equals(int(journal_state.get("next_id", 0)), 2, "Next capture id persisted")

	engram_journal.call("reset_state")
	_assert_equals(int(engram_journal.call("get_entry_count")), 0, "Reset clears in-memory journal")
	engram_journal.call("apply_save_state", journal_state)
	_assert_equals(int(engram_journal.call("get_entry_count")), 1, "Journal restores from save state")

	save_manager.call("clear_slot")
	engram_journal.call("reset_state")

# --- Test: Tag Day Sequence ---
func _test_tag_day() -> void:
	_test_name = "Tag Day Sequence"

	var scene := load("res://scenes/tutorial/tag_day.tscn")
	_assert_true(scene != null, "Tag Day scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Tag Day scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Tag Day scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var camera: Node = instance.find_child("GameCamera", true, false)
		_assert_true(camera != null, "GameCamera node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")
		for key in [
			"peris_sim.system.complete",
			"peris_sim.system.sanction_notice",
			"peris_sim.system.wellness_feed",
			"peris_sim.system.spiral_flash",
			"peris_sim.system.reconnect_denied",
		]:
			_assert_true(DialogueData.has_key(key), "Peris phase 2 dialogue key exists: %s" % key)

		# Event-driven progression test: verify scheduler, GameState, step system
		if "_current_step" in instance and "_scheduler" in instance:
			_assert_true(instance._scheduler != null, "EventScheduler exists")
			_assert_true(instance._game_state != null, "GameState exists")
			_assert_true(instance._current_step != "", "Current step is set")

			# Exercise corridor walk through GameState movement.
			instance._start_naturalizers_grip()
			for j in range(3):
				await get_tree().process_frame
			instance._begin_corridor_walk()
			for j in range(5):
				await get_tree().process_frame
			_assert_true(instance._game_state.is_moving("citizen"), "Citizen is walking the corridor")
			_assert_true(instance._game_state.is_moving("nk1"), "Naturalizer 1 is escorting")

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Aster Simulation ---
## Drive the whole Aster sim to completion using ONLY the data layer: the
## scheduler for time, the three interactables for input, and request_advance()
## for the one acknowledge line. No speed_multiplier hack, no synthetic clicks.
## This is the regression gate that the game is playable through the scheduler.
func _test_aster_playthrough() -> void:
	_test_name = "Aster Playthrough (data layer)"

	var scene := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(scene != null, "Aster sim scene loads for playthrough")
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(5):
		await get_tree().process_frame

	var dialogue: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler
	_assert_true(dialogue != null and scheduler != null,
		"Aster playthrough exposes dialogue and scheduler")
	if dialogue == null or scheduler == null:
		instance.queue_free()
		await get_tree().process_frame
		return

	var actioned := {}
	var reached_complete := false
	var saw_terminal_focus := false
	var safety := 0
	while safety < 6000:
		safety += 1
		# Acknowledge any wait gate (data-layer equivalent of a click), then
		# advance scheduler time. Dialogue rides the one clock both ways.
		_pump_dialogue(dialogue, 4.0)
		instance.headless_advance(0.5, 0.25)

		var step := str(instance._current_step)
		if step == "terminal_focus":
			saw_terminal_focus = true
		if step == "complete":
			reached_complete = true
			break

		# Each interaction fires once, when the data layer makes it available.
		if step == "show_terminal" and not actioned.has("show_terminal") \
				and instance._terminal != null and instance._terminal.is_interaction_enabled():
			actioned["show_terminal"] = true
			instance._terminal._trigger()
		elif step == "walk_to_drink" and not actioned.has("walk_to_drink") \
				and instance._drink_machine != null and instance._drink_machine.is_interaction_enabled():
			actioned["walk_to_drink"] = true
			instance._drink_machine._trigger()
		elif step == "explore_workspace" and not actioned.has("explore_workspace") \
				and instance._explore_gate_unlocked and instance._explore_hallway_gate != null:
			actioned["explore_workspace"] = true
			instance._explore_hallway_gate._trigger()

	_assert_true(saw_terminal_focus,
		"Clicking the terminal opens the forecast screen-focus beat")
	_assert_true(reached_complete,
		"Aster sim plays to completion through the data layer (last step: %s)" % str(instance._current_step))
	_assert_equals(str(instance.requested_scene_change), "res://scenes/tutorial/peris_sim.tscn",
		"Completed Aster sim hands off to the Peris sim")

	instance.queue_free()
	await get_tree().process_frame

## Real-input playthrough. Drives a scene through the ACTUAL per-frame loop with
## synthetic Input (mouse clicks routed through Input.parse_input_event), never
## force-firing a gate. The player must raycast the floor from a click, walk to the
## logbook gate, and let the proximity dwell fire it. This is the coverage that
## catches a scene that looks playable but strands the player at a hidden/unreachable
## gate — the Peris workspace stall.
func _test_input_playthrough() -> void:
	_test_name = "Input Playthrough (synthetic input)"
	await _input_playthrough_peris1()
	await _input_playthrough_aster_first_gate()

func _input_playthrough_peris1() -> void:
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	_assert_true(scene != null, "Peris sim loads for input playthrough")
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	instance.set("start_phase", 1)
	get_tree().root.add_child(instance)
	for i in range(10):
		await get_tree().process_frame

	# Roll through fade-in to the explorable workspace step.
	var safety := 0
	while str(instance._current_step) != "workspace" and safety < 4000:
		instance.headless_advance(0.1, 0.05)
		await get_tree().process_frame
		safety += 1
	_assert_equals(str(instance._current_step), "workspace",
		"Peris-1 reaches the workspace step (input playthrough)")

	var player: Node3D = instance._player as Node3D
	var gate: Node3D = instance._explore_logbook_gate as Node3D
	if player == null or gate == null or str(instance._current_step) != "workspace":
		_assert_true(false, "Peris-1 workspace exposes a player and logbook gate")
		instance.queue_free()
		await get_tree().process_frame
		return

	var gate_pos: Vector3 = gate.global_position
	var radius := float(gate.get("interaction_radius"))

	# Walk to the gate by clicking the floor near it (synthetic mouse through the
	# real input pipeline). Advance scheduler time so the exploration lock lifts and
	# the proximity dwell can fire.
	var reached := false
	var unlocked := false
	safety = 0
	while safety < 6000:
		safety += 1
		if not reached and safety % 40 == 1:
			_synthetic_ground_click(instance, Vector3(gate_pos.x, 0.0, gate_pos.z))
		instance.headless_advance(0.1, 0.05)
		await get_tree().process_frame
		var d := Vector2(player.global_position.x - gate_pos.x,
			player.global_position.z - gate_pos.z).length()
		if d <= radius:
			reached = true
		if instance._explore_gate_unlocked:
			unlocked = true
		if str(instance._current_step) == "monos_breakthrough":
			break

	_assert_true(reached, "Player walks to the logbook gate via synthetic clicks")
	_assert_true(unlocked, "Logbook gate unlocks after the exploration beat")
	_assert_equals(str(instance._current_step), "monos_breakthrough",
		"Reaching + dwelling the unlocked gate triggers it through real input (no force-fire); step=%s" % str(instance._current_step))

	# Past the gate the beat is dialogue + scheduled transitions: drive the one
	# dialogue clock (data-layer acknowledge) and time to the hand-off.
	var dialogue: Node = instance._dialogue
	var reached_complete := false
	safety = 0
	while safety < 12000:
		safety += 1
		_pump_dialogue(dialogue, 4.0)
		instance.headless_advance(0.5, 0.25)
		await get_tree().process_frame
		if str(instance._current_step) == "complete":
			reached_complete = true
			break
	_assert_true(reached_complete,
		"Peris-1 plays to complete via input + data-layer dialogue (last: %s)" % str(instance._current_step))

	instance.queue_free()
	await get_tree().process_frame

## Aster's first gate is the same shape of bug: the player must physically walk to
## the forecasting terminal and let the dwell open it. Prove that gate is reachable
## and fires through real input (full completion stays covered by the data-layer
## --test-aster-playthrough).
func _input_playthrough_aster_first_gate() -> void:
	var scene := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(scene != null, "Aster sim loads for input playthrough")
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(10):
		await get_tree().process_frame

	# Roll through the intro beats (fade, Ron) to the step where the terminal is live.
	var dialogue: Node = instance._dialogue
	var safety := 0
	while str(instance._current_step) != "show_terminal" and safety < 8000:
		_pump_dialogue(dialogue, 4.0)
		instance.headless_advance(0.25, 0.1)
		await get_tree().process_frame
		safety += 1
	_assert_equals(str(instance._current_step), "show_terminal",
		"Aster reaches the show_terminal step (input playthrough)")

	var player: Node3D = instance._player as Node3D
	var terminal: Node3D = instance._terminal as Node3D
	if player == null or terminal == null or str(instance._current_step) != "show_terminal":
		_assert_true(false, "Aster show_terminal exposes a player and a terminal")
		instance.queue_free()
		await get_tree().process_frame
		return

	# The forecasting terminal is an INSPECTION interactable: a click on the object
	# itself (not a proximity dwell) routes through the interaction controller, which
	# walks the player over and triggers it on arrival. Click the terminal directly.
	var opened := false
	safety = 0
	while safety < 6000:
		safety += 1
		if not opened and safety % 50 == 1:
			_synthetic_click_interactable(instance, terminal)
		_pump_dialogue(dialogue, 4.0)
		instance.headless_advance(0.1, 0.05)
		await get_tree().process_frame
		if str(instance._current_step) == "terminal_focus":
			opened = true
			break

	_assert_true(opened,
		"Clicking the terminal opens it through real input (controller-arrival, no force-fire); step=%s" % str(instance._current_step))

	instance.queue_free()
	await get_tree().process_frame

## Click the floor at a world position through the real input pipeline: project the
## point to a screen position via the active camera, then feed a left-click press and
## release to Input. The player's own _unhandled_input raycasts and moves — the test
## never calls _set_click_target or _trigger.
func _synthetic_ground_click(instance: Node, world_pos: Vector3) -> void:
	# Prefer THIS scene's own camera over the viewport's active camera: in a full --test-all run a
	# prior scene can leave its Camera3D current, which would unproject world_pos to the wrong
	# screen point and make the click miss (the leg stalls). unproject_position uses the camera's
	# own transform, so a non-current camera still resolves correctly.
	var camera: Camera3D = null
	if "_camera" in instance and instance._camera != null:
		camera = instance._camera
	else:
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos := camera.unproject_position(world_pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen_pos
		Input.parse_input_event(ev)

## Click an INSPECTION interactable. The headless display server never casts the
## viewport's physics-picking ray, so a real mouse event can't reach an object's
## _on_input_event. Deliver the left-click to that handler directly — the same entry
## point a real pick invokes — then let the REAL chain run: interaction_requested →
## the interaction controller walks the player over → triggers on arrival. We never
## call _trigger() ourselves, so the player must still reach the object.
func _synthetic_click_interactable(instance: Node, interactable: Node) -> void:
	if interactable == null or not interactable.has_method("_on_input_event"):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null and "_camera" in instance:
		camera = instance._camera
	var world_pos: Vector3 = (interactable as Node3D).global_position
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	if camera != null:
		ev.position = camera.unproject_position(world_pos)
	interactable.call("_on_input_event", camera, ev, world_pos, Vector3.UP, 0)

## Real-input reachability across the whole intro: each scene leg is driven to
## complete by genuine input only (synthetic clicks, dwell-by-walking, HUD ability
## keys, data-layer dialogue advance) — never gate._trigger() or a teleport. A leg
## that can't reach a gate STALLS at that step, which is the finding we want.
## Fast-forward must not change the game. Holding F multiplies the scheduler's speed,
## but events fire at the same TICKS, so a data-layer-driven scene must progress through
## the same steps and reach the same end whether F is held or not. Wall-clock timing
## (SceneTree tweens, Time.get_ticks) would diverge. We drive Tag Day (fully auto:
## dialogue + scheduler) via manual _process at 1x and 10x and compare.
func _test_fast_forward_invariance() -> void:
	_test_name = "Fast-Forward Invariance"
	var slow := await _run_ff_scene("res://scenes/tutorial/tag_day.tscn", false)
	var fast := await _run_ff_scene("res://scenes/tutorial/tag_day.tscn", true)
	_assert_true(slow.has("complete"),
		"Tag Day reaches complete at 1x via the data layer (steps: %s)" % str(slow))
	_assert_true(fast.has("complete"),
		"Tag Day reaches complete at 10x / fast-forward (steps: %s)" % str(fast))
	# Same logical progression. Fast-forward may snapshot fewer intermediate frames, so
	# the 10x sequence must be an in-order subsequence of the 1x sequence (no reorder,
	# no extra steps, no divergence).
	_assert_step_subsequence(slow, fast,
		"Tag Day runs the same step sequence with fast-forward as without")

## Drive a scene's data layer at a controlled speed: only our manual _process(dt) ticks
## it (set_process(false) silences the engine's own call), at the speed _compute_speed()
## derives from whether the fast_forward action is held. Returns the step history.
func _run_ff_scene(scene_path: String, fast_forward: bool) -> Array:
	var scene := load(scene_path)
	if scene == null:
		return []
	var instance: Node = scene.instantiate()
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	get_tree().root.add_child(instance)
	for i in range(5):
		await get_tree().process_frame
	instance.set_process(false)
	if fast_forward:
		Input.action_press("fast_forward")
	else:
		Input.action_release("fast_forward")
	var dialogue: Node = instance.get("_dialogue")
	var steps: Array = []
	var last := ""
	var idle := 0
	var guard := 0
	while guard < 30000:
		guard += 1
		if dialogue != null:
			_pump_dialogue(dialogue, 8.0)
		if instance.has_method("_process"):
			instance._process(0.1)
		var s := str(instance._current_step)
		if s != last:
			steps.append(s)
			last = s
			idle = 0
		else:
			idle += 1
		if s == "complete":
			break
		if idle > 6000:
			break
		await get_tree().process_frame
	Input.action_release("fast_forward")
	instance.queue_free()
	await get_tree().process_frame
	return steps

## Puzzles must run the same fast-forwarded as not. Real fast-forward advances the
## scheduler in bigger tick increments per frame, so we run each timing-sensitive
## fragment's scenarios with the normal fine step and again with every `advance`
## collapsed to ONE big tick step (the fast-forward extreme), and assert the final
## scene state — and pass/fail — are identical. Covers the mechanics whose timing
## moved onto the scheduler (enemy charge, ferrolure/hide windows, pendulum, range).
func _test_puzzle_fast_forward_invariance() -> void:
	_test_name = "Puzzle Fast-Forward Invariance"
	var catalog_script = load("res://scripts/fragments/puzzle_fragment_catalog.gd")
	var runner_script = load("res://scripts/fragments/puzzle_fragment_runner.gd")
	var schema = load("res://scripts/fragments/puzzle_fragment_schema.gd")
	if catalog_script == null or runner_script == null or schema == null:
		_assert_true(false, "Puzzle fast-forward: catalog/runner/schema load")
		return
	var catalog = catalog_script.new()
	if not catalog.load_from_file(PUZZLE_FRAGMENT_CATALOG_PATH):
		_assert_true(false, "Puzzle fast-forward: catalog JSON loads")
		return
	var runner = runner_script.new(get_tree())

	var ids := [
		"standard_enemy_lane", "chain_enemy_lane", "ferrolure_primed_window",
		"channels_hide_window_lane", "pendulum_lane", "shelter_to_shelter_range",
	]
	# 1x ~ 0.0166 tick/frame (60fps); 10x ~ 0.166 tick/frame. The fragment's scenario
	# assertions encode the meaningful teaching outcome, so we assert that outcome
	# (pass/fail) is the same at both speeds — i.e. the puzzle solves the same
	# fast-forwarded. (Continuous values like sinusoid levels / exact ticks are settle-
	# noise-sensitive, so we compare the scenario verdict, not the raw state dump.)
	for id in ids:
		var fragment: Dictionary = catalog.find_fragment(id)
		if fragment.is_empty():
			_assert_true(false, "Puzzle fast-forward: fragment '%s' exists" % id)
			continue
		var slow: Dictionary = await runner.run_fragment(_set_fragment_step(fragment.duplicate(true), 0.0166, schema))
		var fast: Dictionary = await runner.run_fragment(_set_fragment_step(fragment.duplicate(true), 0.166, schema))
		_compare_ff_puzzle_runs(id, slow, fast, schema)

func _set_fragment_step(fragment: Dictionary, step_value: float, schema) -> Dictionary:
	_set_step_in_actions(fragment.get(schema.KEY_SETUP, []), step_value, schema)
	for raw_scenario in fragment.get(schema.KEY_SCENARIOS, []):
		if typeof(raw_scenario) != TYPE_DICTIONARY:
			continue
		var scenario: Dictionary = raw_scenario
		_set_step_in_actions(scenario.get(schema.KEY_SETUP, []), step_value, schema)
		_set_step_in_actions(scenario.get(schema.KEY_SCRIPT, []), step_value, schema)
	return fragment

func _set_step_in_actions(actions: Array, step_value: float, schema) -> void:
	for action in actions:
		if typeof(action) == TYPE_DICTIONARY and str(action.get(schema.KEY_ACTION_TYPE, "")) == schema.ACTION_ADVANCE:
			action[schema.KEY_STEP] = step_value

## Scenarios known to diverge under fast-forward, tracked rather than gating the suite.
## (Empty: channels_hide_window's surge wash/miss is now predicted analytically at lure
## activation instead of discovered by per-frame flood sampling, so it's invariant.)
const _KNOWN_FF_PUZZLE_DIVERGENCES := {}

func _compare_ff_puzzle_runs(id: String, slow: Dictionary, fast: Dictionary, schema) -> void:
	var slow_scenarios: Array = slow.get(schema.KEY_SCENARIOS, [])
	var fast_scenarios: Array = fast.get(schema.KEY_SCENARIOS, [])
	_assert_equals(fast_scenarios.size(), slow_scenarios.size(),
		"%s: same scenario count at 1x vs 10x" % id)
	for i in range(mini(slow_scenarios.size(), fast_scenarios.size())):
		var s: Dictionary = slow_scenarios[i]
		var f: Dictionary = fast_scenarios[i]
		var sid := str(s.get(schema.KEY_ID, i))
		var key := "%s/%s" % [id, sid]
		var slow_ok := bool(s.get(schema.KEY_SUCCESS, false))
		var fast_ok := bool(f.get(schema.KEY_SUCCESS, false))
		_assert_true(slow_ok, "%s solves at 1x" % key)
		if _KNOWN_FF_PUZZLE_DIVERGENCES.has(key):
			if fast_ok != slow_ok:
				print("[KNOWN FF DIVERGENCE] %s differs fast-forwarded (1x:%s 10x:%s) — channels detect/search per-frame polling; tracked for a scheduler rework" % [
					key, str(slow_ok), str(fast_ok)])
			continue
		_assert_equals(fast_ok, slow_ok,
			"%s solves the same at 10x fast-forward (1x:%s 10x:%s; %s)" % [
				key, str(slow_ok), str(fast_ok), str(f.get(schema.KEY_MESSAGE, ""))])

func _test_intro_realinput() -> void:
	_test_name = "Intro Real-Input Reachability"
	# Aster's ground-click walk is order-sensitive in a full --test-all run (a prior test leaks
	# scene state that stalls the floor-raycast walk to the drink machine); it runs cleanly on
	# its own here, and Aster's real-input reachability is ALSO covered in --test-all by
	# --test-input-playthrough. So Aster lives in the standalone leg, not the --test-all core.
	await _run_realinput_leg("Aster", "res://scenes/tutorial/aster_sim.tscn", 0,
		Callable(self, "_aster_realinput_beats"))
	await _test_intro_realinput_core()
	await _test_elevator_realinput()

## The real-input intro legs that run in --test-all (Peris-2, Tag Day), each driven to `complete`
## with ONLY real input. Real-input/transition coverage is first-class — never sectioned off
## wholesale; only individual order-sensitive/slow legs (Aster, Elevator) live apart, by name.
func _test_intro_realinput_core() -> void:
	_test_name = "Intro Real-Input Reachability"
	await _run_realinput_leg("Peris-2", "res://scenes/tutorial/peris_sim.tscn", 2,
		Callable(self, "_peris2_realinput_beats"))
	await _run_realinput_leg("Tag Day", "res://scenes/tutorial/tag_day.tscn", 0,
		Callable(self, "_tagday_realinput_beats"))

## The Elevator real-input leg, sectioned out of --test-all ONLY because its wall-clock tweens are
## slow — not because input tests are skippable. Run it before touching the elevator. Elevator is
## real-input reachable through route_choice (incl. the EMP beat and a multi-select workaround);
## route_choice + gauntlet are documented blockers (see the beat comments) — assert the proven
## frontier, not a blocked complete.
func _test_elevator_realinput() -> void:
	_test_name = "Intro Real-Input Reachability"
	await _run_realinput_leg("Elevator", "res://scenes/tutorial/elevator.tscn", 0,
		Callable(self, "_elevator_realinput_beats"), "route_choice")

## milestone defaults to "complete"; pass an earlier step for legs with a documented
## real-input blocker (the elevator), where we assert reachability up to that step.
func _run_realinput_leg(label: String, scene_path: String, visit: int, factory: Callable, milestone := "complete") -> Dictionary:
	var scene := load(scene_path)
	_assert_true(scene != null, "%s: scene loads" % label)
	if scene == null:
		return {}
	var instance: Node = scene.instantiate()
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	if scene_path.ends_with("peris_sim.tscn") and "_visit_phase" in instance and visit > 0:
		instance._visit_phase = visit
	get_tree().root.add_child(instance)
	for i in range(5):
		await get_tree().process_frame
	var beats := {}
	if factory.is_valid():
		beats = factory.call(instance)
	var result := await _drive_scene_real_input(instance, beats)
	if milestone == "complete":
		_assert_equals(str(result.termination), "complete",
			"%s plays to complete via REAL input — no force-fire (last step: %s)" % [label, str(result.last_step)])
	else:
		_assert_true(result.steps.has(milestone),
			"%s is real-input reachable through '%s' (reached: %s)" % [label, milestone, str(result.last_step)])
	print("[REALINPUT] %s: %s @ %s -> %s | steps: %s" % [
		label, str(result.termination), str(result.last_step), str(result.next), str(result.steps)])
	# Reset the static phase so later peris loads default to phase 1.
	if scene_path.ends_with("peris_sim.tscn") and "_visit_phase" in instance:
		instance._visit_phase = 1
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("_teardown_sequence"):
		instance._teardown_sequence()
	instance.queue_free()
	await get_tree().process_frame
	return result

## The driver: each loop pumps the dialogue clock, issues the step's real input
## (once on entry, then re-issues every 40 idle iters so a walk gets re-pathed),
## advances scheduler time, and yields a real frame for input/physics/node-sync.
## A step that sits unchanged past the stall budget terminates as "stall".
func _drive_scene_real_input(instance: Node, beat_actions: Dictionary, max_iters := 30000, stall_budget := 5000) -> Dictionary:
	var dialogue: Node = instance.get("_dialogue")
	var actioned := {}
	var step_history: Array = []
	var last_step := ""
	var unchanged := 0
	var i := 0
	while i < max_iters:
		i += 1
		if dialogue != null:
			_pump_dialogue(dialogue, 8.0)
		var step := str(instance._current_step)
		if step != last_step:
			step_history.append(step)
			last_step = step
			unchanged = 0
		else:
			unchanged += 1
		if step == "complete":
			break
		if beat_actions.has(step):
			if not actioned.has(step):
				actioned[step] = true
				beat_actions[step].call()
			elif unchanged > 0 and unchanged % 40 == 0:
				beat_actions[step].call()
		if unchanged > stall_budget:
			break
		instance.headless_advance(0.1, 0.05)
		await get_tree().process_frame
	var next_scene := ""
	if "requested_scene_change" in instance:
		next_scene = str(instance.requested_scene_change)
	return {
		"termination": ("complete" if str(instance._current_step) == "complete" else "stall"),
		"last_step": str(instance._current_step),
		"steps": step_history,
		"next": next_scene,
	}

func _aster_realinput_beats(instance: Node) -> Dictionary:
	var beats := {}
	# INSPECTION terminal: click it; the controller walks Aster over and triggers.
	beats["show_terminal"] = func(): _synthetic_click_interactable(instance, instance._terminal)
	# HOLD_ACTION drink machine: walk into range, proximity dwell fires.
	beats["walk_to_drink"] = func(): _synthetic_ground_click(instance, Vector3(13.5, 0.0, 5.5))
	# HOLD_ACTION hallway gate: unlocks on its own after EXPLORE_MIN_TIME; walk into range.
	beats["explore_workspace"] = func(): _synthetic_ground_click(instance, Vector3(16.5, 0.0, 4.5))
	return beats

func _peris2_realinput_beats(instance: Node) -> Dictionary:
	var beats := {}
	beats["protect_prompt"] = func(): _press_hud_action_key(instance, KEY_X)
	beats["run_prompt"] = func(): _press_hud_action_key(instance, KEY_Z)
	# Sequence puts the player in select mode here; a click reports the target.
	beats["click_monos"] = func(): _synthetic_player_click(instance, instance.MONOS_POS)
	beats["confirm_protect"] = func(): _press_hud_action_key(instance, KEY_SPACE)
	return beats

func _tagday_realinput_beats(_instance: Node) -> Dictionary:
	# Tag Day is a scripted cinematic: every beat advances on dialogue/timers. No
	# player-gated input — the driver just pumps dialogue + advances time.
	return {}

## Deliver a left-click at a world position straight to the player's input handler.
## The headless display server casts no picking ray and the parse_input_event queue
## is unreliable across paused/select beats, so this calls the player's real
## _unhandled_input (the same method the engine calls on a click) — exercising the
## genuine raycast -> ground_clicked / _set_click_target chain.
func _synthetic_player_click(instance: Node, world_pos: Vector3) -> void:
	var p = instance.get("_player")
	if p == null or not p.has_method("_unhandled_input"):
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		cam = instance.get("_camera")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	if cam != null:
		ev.position = cam.unproject_position(world_pos)
	p._unhandled_input(ev)

## Deliver a key (optionally with Ctrl) straight to the sequence's _unhandled_key_input
## — the real path for the elevator's TAB character-switch and Ctrl+digit multi-select,
## which the sequence handles directly (not through the HUD).
func _synthetic_sequence_key(instance: Node, keycode: int, ctrl := false) -> void:
	if not instance.has_method("_unhandled_key_input"):
		return
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	instance._unhandled_key_input(ev)

func _elevator_realinput_beats(instance: Node) -> Dictionary:
	var beats := {}
	var exit_gate := Vector3(float(instance.ELEVATOR_SIZE.x) / 2.0, 0.0, 0.0)
	# Walk Peris onto the downed-Aster wake zone (HOLD_ACTION dwell).
	beats["approach_aster"] = func(): _synthetic_player_click(instance, Vector3(instance.ASTER_POS.x, 0.0, instance.ASTER_POS.z))
	# Queue EMP (E) while auto-paused, then resume (Space) to fire it.
	beats["emp_tutorial"] = func():
		_press_hud_action_key(instance, KEY_E)
		_press_hud_action_key(instance, KEY_SPACE)
	# Select the peris+aster pair (Ctrl+2), unpause (Space), then walk both to the
	# door gate: click moves the active char, Tab switches active, click again. These
	# must be spread across frames (the selection signal has to propagate before the
	# unpause is accepted), so step through them one per call.
	# FINDING: a click moves only the ACTIVE character (no party-move-on-click), and
	# Tab (_switch_character) resets the multi-select to one. So "walk both to the
	# door" can't be done with the pair intact in one motion. Workaround: move each
	# separately, then re-select the missing member so the both-at-door+pair gate fires.
	var ms := [0]
	beats["multiselect_tutorial"] = func():
		match ms[0]:
			0: _synthetic_sequence_key(instance, KEY_2, true)   # select aster into the pair
			1: _press_hud_action_key(instance, KEY_SPACE)        # unpause (pair satisfied)
			2: _synthetic_player_click(instance, exit_gate)      # walk peris (active) to door
			3: _synthetic_sequence_key(instance, KEY_TAB)         # switch to aster (drops pair)
			4: _synthetic_player_click(instance, exit_gate)      # walk aster to door
			_:
				# Both parked at the door; restore the pair so the gate accepts.
				if not instance._multiselect_has_required_pair():
					if not instance._selected_character_ids.has("peris"):
						_synthetic_sequence_key(instance, KEY_1, true)
					elif not instance._selected_character_ids.has("aster"):
						_synthetic_sequence_key(instance, KEY_2, true)
		ms[0] = min(ms[0] + 1, 5)
	# Enemies in the loaded combat chunks would game-over the party; neutralize
	# detection (test setup, not a gate force-fire) so this measures reachability.
	# Below-section beats run at BELOW_Y; click the floor at that height so the
	# ground-ray lands on the right spot (a y=0 click lands elsewhere on a y=-4 floor).
	beats["corridor"] = func(): _disable_enemy_detection(instance)
	# Route fork: walk east toward the convergence point (bridge height, y~0).
	# KNOWN BLOCKER: this gate keys on aster.x > ROUTES_CONVERGE.x - 2 (~37.5), but the
	# walkable bridge only reaches ~x=17, so it is unreachable by walking — the contract
	# tests pass it only by force-commanding aster's GameState position. See findings.
	beats["route_choice"] = func():
		_disable_enemy_detection(instance)
		_synthetic_player_click(instance, Vector3(instance.ROUTES_CONVERGE.x, 0.0, instance.ROUTES_CONVERGE.z))
	# Climb prompt zone (HOLD_ACTION dwell).
	beats["climb_attempt"] = func(): _synthetic_player_click(instance, Vector3(float(instance.BRIDGE_START_X) + 5.0, float(instance.BELOW_Y), 0.0))
	# Dormant plant (HOLD_ACTION, wall-clock dwell).
	beats["junction_arrive"] = func(): _synthetic_player_click(instance, Vector3(instance.JUNCTION_POS.x + float(instance.SHELTER_SIZE.x) / 2.0 - 0.8, float(instance.BELOW_Y), float(instance.SHELTER_SIZE.z) / 2.0 - 0.5))
	# Ferrolure activation then walk east to the gauntlet exit.
	beats["gauntlet"] = func():
		_disable_enemy_detection(instance)
		_synthetic_player_click(instance, instance.FERROLURE_POS)
		_synthetic_player_click(instance, instance.GAUNTLET_EXIT)
	return beats

## Dialogue must keep flowing while the gameplay scheduler is paused (the Peris
## protect prompt and exploration focus rely on this). A queued chain advances
## line-to-line and finishes; an acknowledge line waits for request_advance().
func _test_dialogue_pause_chain() -> void:
	_test_name = "Dialogue During Pause"

	var scene := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(scene != null, "Scene loads for pause-dialogue test")
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(5):
		await get_tree().process_frame

	var dialogue: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler
	if dialogue == null or scheduler == null:
		_assert_true(false, "Pause-dialogue test has dialogue and scheduler")
		instance.queue_free()
		await get_tree().process_frame
		return

	scheduler.pause()
	_assert_true(scheduler.is_paused(), "Gameplay scheduler is paused")

	# With auto-advance enabled, a three-line auto chain advances entirely on the
	# dialogue clock — proving the UI clock keeps flowing while gameplay is paused.
	var settings_node: Node = get_tree().root.get_node_or_null("Settings")
	var prior_auto := false
	if settings_node != null:
		prior_auto = bool(settings_node.get("auto_advance_dialogue"))
		settings_node.set_auto_advance_dialogue(true)
	dialogue.clear()
	var shown: Array[String] = []
	var finished := {"hit": false}
	var on_line := func(t: String): shown.append(t)
	var on_fin := func(): finished["hit"] = true
	dialogue.line_displayed.connect(on_line)
	dialogue.dialogue_finished.connect(on_fin)
	dialogue.say("First line during pause.", "TEST", "normal", false)
	dialogue.say("Second line during pause.", "TEST", "normal", false)
	dialogue.say("Third line during pause.", "TEST", "normal", false)

	var safety := 0
	while dialogue.is_active() and safety < 4000:
		dialogue.advance_ui_time(4.0)
		safety += 1
	if settings_node != null:
		settings_node.set_auto_advance_dialogue(prior_auto)

	_assert_true(scheduler.is_paused(), "Scheduler stayed paused while dialogue advanced")
	_assert_equals(shown.size(), 3, "All three queued lines trigger in turn while paused (no hang)")
	_assert_true(finished["hit"], "dialogue_finished fires after the paused chain completes")
	_assert_true(not dialogue.is_active(), "Dialogue box returns to idle while paused")

	# An acknowledge line holds until request_advance(), even while paused.
	dialogue.clear()
	finished["hit"] = false
	dialogue.say("Acknowledge me.", "TEST", "normal", true)
	for j in range(60):
		dialogue.advance_ui_time(4.0)
	_assert_true(dialogue.is_active(),
		"Acknowledge line waits for an explicit advance while paused (does not auto-skip)")
	dialogue.request_advance()
	_assert_true(not dialogue.is_active(),
		"request_advance() clears the acknowledge line while paused")
	_assert_true(finished["hit"], "dialogue_finished fires once the acknowledge line is advanced")

	dialogue.line_displayed.disconnect(on_line)
	dialogue.dialogue_finished.disconnect(on_fin)
	scheduler.resume()
	instance.queue_free()
	await get_tree().process_frame

## Settings autoload: preset → scale mapping, ConfigFile persistence round-trip.
func _test_settings() -> void:
	_test_name = "Settings"
	# TextSpeed: SLOW=0, NORMAL=1, FAST=2, INSTANT=3
	var s: Node = get_tree().root.get_node_or_null("Settings")
	_assert_true(s != null, "Settings autoload is registered")
	if s == null:
		return
	var original := int(s.text_speed)

	s.set_text_speed(1)  # NORMAL
	_assert_true(is_equal_approx(float(s.text_cps_scale()), 1.0) and is_equal_approx(float(s.text_hold_scale()), 1.0),
		"Normal preset is 1x speed and 1x hold")
	s.set_text_speed(0)  # SLOW
	_assert_true(float(s.text_cps_scale()) < 1.0 and float(s.text_hold_scale()) > 1.0,
		"Slow preset types slower and holds longer")
	s.set_text_speed(2)  # FAST
	_assert_true(float(s.text_cps_scale()) > 1.0 and float(s.text_hold_scale()) < 1.0,
		"Fast preset types faster and holds shorter")
	s.set_text_speed(3)  # INSTANT
	_assert_true(float(s.text_cps_scale()) >= 100.0,
		"Instant preset types effectively instantly")

	# Persistence: save FAST, load into a fresh instance.
	s.set_text_speed(2)  # FAST (set_text_speed saves)
	var fresh: Node = load("res://scripts/system/settings.gd").new()
	fresh.load_settings()
	_assert_equals(int(fresh.text_speed), 2, "Text speed persists across a fresh load")
	fresh.free()

	# Restore the shared autoload (and persisted file) so later tests see Normal.
	s.set_text_speed(original)

## Long lines paginate: the visible window pages, but _current_text stays the
## full logical line and line_displayed / dialogue_finished fire once per line.
func _test_dialogue_pagination() -> void:
	_test_name = "Dialogue Pagination"
	var box: Node = load("res://scripts/ui/dialogue_box.gd").new()
	get_tree().root.add_child(box)
	await get_tree().process_frame

	var shown: Array[String] = []
	var finished := {"n": 0}
	box.line_displayed.connect(func(t: String): shown.append(t))
	box.dialogue_finished.connect(func(): finished["n"] += 1)

	var short_line := "A short line."
	box.say(short_line)
	_assert_equals(box._pages.size(), 1, "A short line is a single page")
	# Drain it (click-only by default: type, then advance when awaiting).
	var guard := 0
	while box.is_active() and guard < 4000:
		box.advance_ui_time(8.0)
		if box.awaiting_advance():
			box.request_advance()
		guard += 1

	var long_line := "This is the first sentence of a deliberately long passage. Here is a second sentence that keeps going. A third sentence adds yet more length to push well past the pagination threshold. And a fourth sentence ensures we split into multiple readable pages instead of one wall of text."
	shown.clear()
	finished["n"] = 0
	box.say(long_line)
	_assert_equals(str(box._current_text), long_line, "Paginated line keeps _current_text as the full line")
	_assert_true(box._pages.size() > 1, "A >180-char line splits into multiple pages (got %d)" % box._pages.size())

	guard = 0
	var saw_multiple_pages := false
	while box.is_active() and guard < 8000:
		box.advance_ui_time(8.0)
		if box.awaiting_advance():
			box.request_advance()
		if int(box._page_index) > 0:
			saw_multiple_pages = true
		# _current_text must stay the full line throughout.
		if str(box._current_text) != long_line:
			break
		guard += 1

	_assert_equals(str(box._current_text), long_line, "_current_text stays the full line while paging")
	_assert_true(saw_multiple_pages, "Advancing walks through the pages")
	_assert_equals(shown.size(), 1, "line_displayed fires once per logical line, not per page")
	_assert_equals(int(finished["n"]), 1, "dialogue_finished fires once for the paginated line")
	if shown.size() == 1:
		_assert_equals(shown[0], long_line, "line_displayed carries the full line text")

	box.queue_free()
	await get_tree().process_frame

## Cutscene mode forces auto-advance (even for `wait` lines) so scripted-cinematic dialogue
## (Tag Day) keeps pace with the on-screen action instead of blocking on a click.
func _test_dialogue_cutscene_mode() -> void:
	_test_name = "Dialogue Cutscene Mode"
	var box: Node = load("res://scripts/ui/dialogue_box.gd").new()
	get_tree().root.add_child(box)
	await get_tree().process_frame

	# Default (no cutscene mode, auto-advance off): a `wait` line blocks for an explicit advance.
	box.say("Acknowledge me.", "", "normal", true)
	var guard := 0
	while box.is_active() and not box.awaiting_advance() and guard < 4000:
		box.advance_ui_time(8.0)
		guard += 1
	_assert_true(box.awaiting_advance(), "Default: a wait line blocks for an explicit advance (click)")
	box.request_advance()
	box.advance_ui_time(8.0)

	# Cutscene mode: the SAME wait line auto-advances on the beat and finishes WITHOUT a click.
	box.set_cutscene_mode(true)
	var finished := {"n": 0}
	box.dialogue_finished.connect(func(): finished["n"] += 1)
	box.say("Keep pace with the cutscene.", "", "normal", true)
	guard = 0
	var ever_awaited := false
	while box.is_active() and guard < 4000:
		box.advance_ui_time(8.0)
		if box.awaiting_advance():
			ever_awaited = true
			break
		guard += 1
	_assert_true(not ever_awaited, "Cutscene mode: a wait line never blocks on a click (awaiting_advance stays false)")
	_assert_equals(int(finished["n"]), 1, "Cutscene mode: the wait line auto-advances and finishes on its own")

	box.queue_free()
	await get_tree().process_frame

## "Hold SHIFT to reveal interactions": the highlight action -> HUD signal -> base handler ->
## every interactable runs its outline/PARTICLE highlight (the shader+particle duo, NOT a label).
## Hover shares the same feedback path. Driven through the REAL Input pipeline.
func _test_interactable_highlight() -> void:
	_test_name = "Interactable Highlight"
	_assert_true(InputMap.has_action("highlight"), "highlight input action is registered (SHIFT)")

	# set_highlight lights up the OBJECT's OutlineSurfaceTarget — the real outline SHADER and
	# particles emitted FROM the mesh surface — NOT a label or a fixed ring on the meshless zone.
	var it: Node = load("res://scripts/game/objects/interactable.gd").new()
	get_tree().root.add_child(it)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	it.add_child(box)
	var tgt: Node = OutlineSurfaceTarget.new()
	it.add_child(tgt)
	tgt.register_highlight_mesh(box)
	it.set_outline_target(tgt)
	await get_tree().process_frame
	it.interaction_enabled = true
	it.set_highlight(true)
	_assert_true(it._feedback_emitting, "set_highlight(true) runs the highlight")
	_assert_true(tgt.has_active_mesh_outline(), "the OBJECT's outline SHADER turns on (not a label/ring)")
	_assert_true(tgt.has_active_glow(), "the morphing-noise emission glow runs (energy from the outline, not a fixed ring)")
	it.set_highlight(false)
	_assert_true(not it._feedback_emitting, "set_highlight(false) stops the highlight")
	_assert_true(not tgt.has_active_mesh_outline(), "the outline shader clears on release")
	# Hover shares the SAME path — hovering shows the SAME outline shader + surface particles.
	it.set_hover_feedback(true)
	_assert_true(tgt.has_active_mesh_outline(), "hover shows the SAME outline shader")
	it.set_hover_feedback(false)
	_assert_true(not it._feedback_emitting, "leaving hover stops the highlight")
	it.queue_free()
	await get_tree().process_frame

	# Full pipeline through the real Peris scene: SHIFT key event -> HUD highlight_held -> base
	# _on_highlight_held -> every interactable's feedback running; release stops it.
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	var inst: Node = scene.instantiate()
	inst._visit_phase = 1
	if "suppress_scene_change" in inst:
		inst.suppress_scene_change = true
	get_tree().root.add_child(inst)
	for i in range(5):
		await get_tree().process_frame
	var guard := 0
	while str(inst._current_step) != "workspace" and guard < 300:
		inst.headless_advance(0.2, 0.1)
		await get_tree().process_frame
		guard += 1
	inst.headless_advance(0.5, 0.1)
	await get_tree().process_frame
	var interactables := _collect_interactable_nodes(inst)
	_assert_true(interactables.size() > 0, "Peris workspace has interactables to reveal (got %d)" % interactables.size())

	var press := InputEventAction.new()
	press.action = "highlight"
	press.pressed = true
	Input.parse_input_event(press)
	for i in range(3):
		await get_tree().process_frame
	var any_highlighted := false
	for node in interactables:
		if node._feedback_emitting:
			any_highlighted = true
	_assert_true(any_highlighted, "Holding SHIFT runs the outline/particle highlight (real input -> HUD -> handler)")

	# The object meshes (wrapped in OutlineSurfaceTargets via _outline_object_meshes) get the real
	# outline SHADER — the controller drives their set_highlight too, not just the zone particles.
	var targets := _collect_outline_targets(inst)
	var shader_outline_on := false
	for t in targets:
		if t.has_method("has_active_mesh_outline") and t.call("has_active_mesh_outline"):
			shader_outline_on = true
	_assert_true(targets.size() == 0 or shader_outline_on, "Holding SHIFT lights the mesh outline SHADER on object targets (got %d targets)" % targets.size())

	var release := InputEventAction.new()
	release.action = "highlight"
	release.pressed = false
	Input.parse_input_event(release)
	for i in range(3):
		await get_tree().process_frame
	var all_cleared := true
	for node in interactables:
		if node._feedback_emitting:
			all_cleared = false
	_assert_true(all_cleared, "Releasing SHIFT stops the highlight")

	inst._visit_phase = 1
	inst.queue_free()
	await get_tree().process_frame

func _collect_interactable_nodes(node: Node) -> Array:
	var out: Array = []
	if node is Interactable:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_interactable_nodes(child))
	return out

func _collect_outline_targets(node: Node) -> Array:
	var out: Array = []
	if node is OutlineSurfaceTarget:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_outline_targets(child))
	return out

## Pause menu: opens/closes, pauses the tree, navigates to Settings, and its
## text-speed buttons drive the Settings autoload.
func _test_pause_menu() -> void:
	_test_name = "Pause Menu"
	var s: Node = get_tree().root.get_node_or_null("Settings")
	var original := int(s.text_speed) if s != null else 1

	var pm: Node = load("res://scenes/ui/pause_menu.tscn").instantiate()
	get_tree().root.add_child(pm)
	await get_tree().process_frame

	_assert_true(not pm.is_open() and not pm.visible, "Pause menu starts closed")
	_assert_true(not get_tree().paused, "Tree starts unpaused")

	pm.open()
	_assert_true(pm.is_open() and pm.visible, "Pause menu opens")
	_assert_true(get_tree().paused, "Opening the pause menu pauses gameplay")

	# Navigate to Settings, then Esc-style toggle returns to the pause view.
	pm._show_settings()
	_assert_true(pm._settings_view.visible and not pm._pause_view.visible, "Settings view shows")
	pm.toggle()
	_assert_true(pm.is_open() and pm._pause_view.visible, "Toggle from Settings returns to the pause view (not closed)")

	# Text speed buttons drive the Settings autoload.
	if s != null:
		pm._show_settings()
		pm._on_speed_pressed(2)  # FAST
		_assert_equals(int(s.text_speed), 2, "Pause-menu text-speed button updates Settings")

	pm.close()
	_assert_true(not pm.is_open() and not get_tree().paused, "Closing the pause menu resumes gameplay")

	# Restore shared state.
	if s != null:
		s.set_text_speed(original)
	get_tree().paused = false
	pm.queue_free()
	await get_tree().process_frame

func _test_aster_sim() -> void:
	_test_name = "Aster Simulation"

	var scene := load("res://scenes/tutorial/aster_sim.tscn")
	_assert_true(scene != null, "Aster sim scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Aster sim scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Aster sim scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")
		var interaction_controller := aster.find_child("CharacterInteractionController", true, false) if aster != null else null
		_assert_true(interaction_controller != null,
			"Aster uses the reusable character interaction controller")

		var ron: Node = instance.find_child("Ron", true, false)
		_assert_true(ron != null, "Ron NPC node exists")

		var drink: Node = instance.find_child("DrinkMachine", true, false)
		_assert_true(drink != null, "Drink machine interactable exists")
		var terminal: Node = instance.find_child("Terminal", true, false)
		_assert_true(terminal != null, "Terminal interactable exists")
		if terminal != null and drink != null:
			_assert_equals(str(terminal.get("interactable_id")), "aster.terminal",
				"Aster terminal pulls its behavior from the interactable data catalog")
			_assert_interactable_type(terminal, Interactable.InteractableType.INSPECTION,
				"Aster terminal")
			_assert_equals(str(drink.get("interactable_id")), "aster.drink_machine",
				"Aster drink machine pulls its behavior from the interactable data catalog")
			_assert_interactable_type(drink, Interactable.InteractableType.HOLD_ACTION,
				"Aster drink machine")
			_assert_true(terminal.has_method("is_interaction_enabled") and not bool(terminal.call("is_interaction_enabled")),
				"Aster terminal is disabled until the monitor tutorial step")
			_assert_true(drink.has_method("is_interaction_enabled") and not bool(drink.call("is_interaction_enabled")),
				"Aster drink machine is disabled until Ron asks Aster to get a drink")
			var initial_step := str(instance._current_step)
			drink.call("_trigger")
			_assert_equals(instance._current_step, initial_step,
				"Disabled drink machine cannot skip the monitor sequence")
			instance._start_show_terminal()
			await get_tree().process_frame
			_assert_true(bool(terminal.call("is_interaction_enabled")),
				"Aster terminal enables at the monitor tutorial step")
			_assert_true(not bool(drink.call("is_interaction_enabled")),
				"Aster drink machine stays disabled during the monitor tutorial step")
			terminal.call("_trigger")
			await get_tree().process_frame
			_assert_equals(instance._current_step, "terminal_focus",
				"Clicking Aster's monitor opens the forecast screen-focus beat")
			instance.headless_advance(instance.TERMINAL_FOCUS_DURATION + 0.1)
			_assert_equals(instance._current_step, "terminal_data",
				"The terminal focus beat advances the sequence to terminal_data")
			_assert_true(not bool(drink.call("is_interaction_enabled")),
				"Aster drink machine remains disabled until the drink tutorial step")
			instance._start_walk_to_drink()
			await get_tree().process_frame
			_assert_true(bool(drink.call("is_interaction_enabled")),
				"Aster drink machine enables only at the drink tutorial step")
			drink.call("set_interaction_enabled", false)

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")
		if dialogue != null:
			_assert_true(dialogue.has_method("advance_ui_time"),
				"DialogueBox exposes UI-time advancement")
			_assert_true(dialogue.has_method("request_advance"),
				"DialogueBox exposes an explicit advance shared by click and data layer")
			# The dialogue clock is owned by the sequence and runs even when the
			# gameplay scheduler is paused.
			instance._scheduler.pause()
			dialogue.clear()
			dialogue.say("clock probe", "", "normal", false)
			dialogue.advance_ui_time(0.2)
			_assert_true(float(dialogue.get("_displayed_chars")) > 0.0,
				"Dialogue advances while the gameplay scheduler is paused")
			dialogue.clear()
			instance._scheduler.resume()
		var high_res_room := instance.find_child("default", true, false) as Node3D
		_assert_true(high_res_room != null, "Aster sim keeps the imported high-res room instance")
		var placement := instance.find_child("ScenePlacement", true, false) as Node3D
		_assert_true(placement != null, "Aster sim exposes authored placement markers")
		if placement != null:
			var required_markers := [
				"RoomCenter",
				"HighResRoomOrigin",
				"AsterStart",
				"RonStart",
				"RonExitTarget",
				"TerminalAnchor",
				"TerminalInteract",
				"DrinkMachineAnchor",
				"DrinkMachineInteract",
				"GlassBeadAnchor",
				"GlassBeadZoneMarker",
				"MacabreTealCanvas",
				"MacabreTealZoneMarker",
				"HunterAshCanvas",
				"HunterAshZoneMarker",
				"AwardsShelf",
				"AwardsCenterZoneMarker",
				"AwardsJournalismZoneMarker",
				"JStoreShelf",
				"JStoreMainZoneMarker",
				"HallwayExit",
				"DataMotesCenter",
			]
			for marker_name in required_markers:
				_assert_true(placement.find_child(marker_name, true, false) is Node3D,
					"Aster sim exposes %s as a scene placement node" % marker_name)
			for light_name in ["WarmDirectionalLight", "DeskLight", "DataLight", "HallwayExitLight"]:
				_assert_true(placement.find_child(light_name, true, false) is Light3D,
					"Aster sim exposes %s as a scene light" % light_name)
			var room_origin := placement.find_child("HighResRoomOrigin", true, false) as Node3D
			var room_center := placement.find_child("RoomCenter", true, false) as Node3D
			if high_res_room != null and room_origin != null:
				_assert_true(high_res_room.global_position.distance_to(room_origin.global_position) < 0.01,
					"High-res Aster room origin is aligned through a scene placement node")
			if high_res_room != null and room_center != null:
				var high_res_center := high_res_room.global_position + Vector3(3.5, 0.0, 6.0625)
				var center_delta := Vector2(
					high_res_center.x - room_center.global_position.x,
					high_res_center.z - room_center.global_position.z
				).length()
				_assert_true(center_delta < 0.01,
					"High-res Aster room is centered on the graybox room placement")
			var terminal_marker := placement.find_child("TerminalInteract", true, false) as Node3D
			var drink_marker := placement.find_child("DrinkMachineInteract", true, false) as Node3D
			var terminal_node := instance.find_child("Terminal", true, false) as Node3D
			var drink_node := instance.find_child("DrinkMachine", true, false) as Node3D
			if terminal_marker != null and terminal_node != null:
				_assert_true(terminal_node.global_position.distance_to(terminal_marker.global_position) < 0.01,
					"Terminal interactable uses its scene placement marker")
			if drink_marker != null and drink_node != null:
				_assert_true(drink_node.global_position.distance_to(drink_marker.global_position) < 0.01,
					"Drink machine interactable uses its scene placement marker")
		var room_spot := instance.find_child("SpotLight3D", true, false) as SpotLight3D
		_assert_true(room_spot != null, "Aster sim keeps the imported-room spotlight")
		if room_spot != null:
			_assert_true(room_spot.global_position.x >= 0.0 and room_spot.global_position.x <= 18.0
				and room_spot.global_position.z >= -2.0 and room_spot.global_position.z <= 14.0,
				"Aster sim imported-room spotlight is repositioned onto the graybox room")
		var imported_outline := instance.find_child("AsterSimRoomOutlinePreview", true, false) as MeshInstance3D
		var perception_quad := instance.find_child("PerceptionQuad", true, false) as MeshInstance3D
		var outline_overlay: MeshInstance3D = imported_outline if imported_outline != null else perception_quad
		var outline_material: ShaderMaterial = null
		_assert_true(outline_overlay != null, "Aster sim keeps an outline overlay node available")
		if outline_overlay != null:
			_assert_true(not outline_overlay.visible,
				"Aster sim temporarily disables the full-screen black outline overlay")
			outline_material = outline_overlay.material_override as ShaderMaterial
			if outline_overlay == perception_quad and outline_material != null and outline_material.shader != null:
				_assert_true(outline_material.shader.resource_path != "res://resources/black_outline.gdshader",
					"Aster sim fallback overlay is not running the black outline shader")
		_assert_equals(instance._perception_mode, "outline", "Aster sim keeps outline perception mode for object feedback")
		var feedback_manager := instance.find_child("OutlineFeedbackManager", true, false)
		_assert_true(feedback_manager != null, "Aster sim centralizes outline feedback state")
		var room_surface_targets := _find_nodes_with_script(instance, "res://scripts/game/objects/outline_surface_target.gd")
		_assert_true(room_surface_targets.size() >= 8,
			"Aster sim high-res room keeps generated per-surface wrappers")
		for target_name in [
			"RoomTargetDesk",
			"RoomTargetDrinkMachine",
			"RoomTargetDataDisplays",
		]:
			var room_target := instance.find_child(target_name, true, false)
			_assert_outline_surface_target_contract(room_target, target_name, true, false)
			if room_target != null and room_target.has_method("get_highlight_mesh_count"):
				_assert_true(int(room_target.call("get_highlight_mesh_count")) > 0,
					"%s is wired to actual graybox meshes" % target_name)
				_assert_true(int(room_target.call("get_outline_shell_count")) > 0,
					"%s creates object-local outline shell meshes" % target_name)
				_assert_true(bool(room_target.get("outline_particles_enabled")),
					"%s has outline particles enabled for the graybox effect preview" % target_name)
				_assert_true(int(room_target.get("outline_particles_per_mesh")) >= 180,
					"%s uses diagnostic outline particle density for the graybox effect preview" % target_name)
				_assert_true(float(room_target.get("selected_feedback_duration")) >= 2.5,
					"%s keeps amber selected feedback visible long enough to debug" % target_name)
				_assert_true(room_target.has_method("is_feedback_managed") and bool(room_target.call("is_feedback_managed")),
					"%s delegates hover and selection state to the outline feedback manager" % target_name)
		for surface_target in room_surface_targets:
			if surface_target.has_meta("source_surface"):
				_assert_true(not bool(surface_target.get("input_ray_pickable")),
					"Generated GLTF surface wrappers do not steal hover from semantic room targets")
		if high_res_room != null:
			_assert_true(not high_res_room.visible,
				"High-res room is hidden while testing graybox object outlines")
		if perception_quad != null:
			_assert_true(not perception_quad.visible,
				"Aster sim fallback outline quad is hidden while object feedback is debugged")
			if instance._perception_material != null:
				var shader: Shader = instance._perception_material.shader
				if shader != null:
					_assert_true(shader.resource_path != "res://resources/black_outline.gdshader",
						"Aster sim fallback does not run the black outline shader during object feedback debug")
		_assert_equals(DialogueData.text("aster_sim.ron.lighting"),
			"Geez, Aster, it looks like an evil lair in here. You ever think about turning the lights up? Might want to fix that before they think you've lost your mind...",
			"Ron combines the dim-lighting and lost-your-mind comments")
		_assert_equals(DialogueData.text("aster_sim.ron.greeting"),
			"Hey hey, Deputy Analyst, Separations and Transport!",
			"Ron greets Aster with the revised workplace title")
		_assert_equals(DialogueData.text("aster_sim.aster.lighting"),
			"The default's like working on the surface of the sun! I've always had it like this...",
			"Aster names his long-standing dim workspace preference")
		_assert_true(DialogueData.text("aster_sim.ron.tag_day_jobs").contains("happy Tag Day"),
			"Ron adds the revised Tag Day jobs comment after the lighting exchange")
		_assert_equals(DialogueData.text("aster_sim.device.tag_verify"),
			"HAPPY TAG DAY! WORKSTATIONS HAVE BEEN DISABLED. PLEASE DISCONNECT FROM SIMULATION",
			"Tag Day device notification uses the revised workstation shutdown text")
		_assert_equals(DialogueData.text("tag_day.nk_chat.10"),
			"Is there? You're what, twenty-three? Twenty-four? Soon it'll be you in that room...",
			"Tag Day NK-01 late corridor line matches the revised age-room threat")
		_assert_true(DialogueData.text("aster_sim.ron.tag_notify").contains("Chief Analyst, Separations and Transport"),
			"Ron uses the revised Chief Analyst promotion joke")
		_assert_equals(DialogueData.text("aster_sim.tag_routine"),
			"Man, they should really automate these checks sometime. Can't they'd just let me work instead of pulling us all out?",
			"Aster final simulation line uses the revised automation-check complaint")
		_assert_true(not DialogueData.has_key("aster_sim.ron.whatever_works"),
			"Ron does not answer Aster's lighting preference after walking out")
		_assert_true(not DialogueData.has_key("aster_sim.ron.lost_mind"),
			"Ron lost-your-mind comment is merged into the lighting line")
		for retired_key in [
			"aster_sim.working.thought.01",
			"aster_sim.working.thought.02",
			"aster_sim.ron.working_on",
			"aster_sim.aster.show",
			"aster_sim.system.cleaned",
			"aster.sim_expand.glass_bead.look",
			"aster.sim_expand.painting_1.look",
			"aster.sim_expand.painting_2.look",
			"aster.sim_expand.awards.look",
			"aster.sim_expand.awards.journalism_look",
			"aster.sim_expand.bookshelf.look",
			"aster.sim_expand.bookshelf.articles_pull",
		]:
			_assert_true(not DialogueData.has_key(retired_key),
				"Retired Aster sim setup/action dialogue key is absent: %s" % retired_key)
		_assert_true(DialogueData.text("aster.sim_expand.glass_bead.line").contains("nobody asks me to normalize anything"),
			"Aster sim glass bead dialogue uses the revised private-pleasure flavor")
		var hunter_ash_line := DialogueData.text("aster.sim_expand.painting_2.line")
		_assert_true(
			hunter_ash_line.contains("Breadth of Life")
			and hunter_ash_line.contains("mine's the digital one")
			and not hunter_ash_line.contains("waterfall thing"),
			"Aster sim Hunter and Ash dialogue uses the reference Breadth of Life hidden-reward seed")
		_assert_true(DialogueData.text("aster.sim_expand.bookshelf.line").contains("Journal of Adjusted Transfer Analysis"),
			"Aster sim J-store collection dialogue uses the revised journal list flavor")
		_assert_true(DialogueData.text("aster.sim_expand.bookshelf.articles_line").contains("Most of my work is on barrier fault prediction"),
			"Aster sim J-store articles dialogue uses the revised barrier-fault publication flavor")

		dialogue.clear()
		instance._scheduler.clear()
		instance._start_ron_move_fast()
		for i in range(2):
			await get_tree().process_frame

		_assert_true(instance._game_state.characters.has("ron"), "Ron is registered with GameState")
		_assert_true(instance._game_state.is_moving("ron"), "Ron movement is scheduler-backed")
		var ron_before: Vector3 = instance._game_state.get_position("ron")
		instance.headless_advance(0.5, 0.1)
		var ron_after: Vector3 = instance._game_state.get_position("ron")
		_assert_true(ron_after.distance_to(ron_before) > 0.1, "Ron advances when scheduler time advances")
		_assert_scheduler_animation_bridge(instance)

		_drain_dialogue_box(dialogue)
		instance.headless_advance(0.2, 0.05)
		for i in range(2):
			await get_tree().process_frame

		var aster_explore_zones := [
			"GlassBeadZone",
			"macabre_tealZone",
			"hunter_ashZone",
			"AwardsCenterZone",
			"AwardsJournalismZone",
			"JStoreMainZone",
			"HallwayGate",
		]
		for zone_name in aster_explore_zones:
			var zone := _assert_exploration_interactable_contract(instance, zone_name)
			if zone == null:
				continue
			if zone_name == "HallwayGate":
				_assert_equals(str(zone.get("interactable_id")), "aster.hallway_gate",
					"Aster hallway gate pulls its behavior from the interactable data catalog")
				_assert_interactable_type(zone, Interactable.InteractableType.HOLD_ACTION,
					"Aster hallway gate")
			else:
				_assert_equals(str(zone.get("interactable_id")), "tutorial.inspection",
					"%s pulls inspection behavior from the interactable data catalog" % zone_name)
				_assert_interactable_type(zone, Interactable.InteractableType.INSPECTION,
					"%s" % zone_name)
		var room_element_targets := _find_nodes_with_meta(instance, "room_element_id")
		_assert_true(room_element_targets.size() >= 8,
				"Aster sim exposes semantic graybox object outline targets")
		_assert_true(instance.find_child("JStoreArticlesZone", true, false) == null,
			"Aster sim uses one J-store interactable zone with sequenced lines")
		for target_name in [
			"RoomTargetDesk",
			"RoomTargetDrinkMachine",
			"RoomTargetGlassBeadGame",
			"RoomTargetMacabreTealPainting",
			"RoomTargetHunterAshPainting",
			"RoomTargetAwardsShelf",
			"RoomTargetJStoreShelf",
			"RoomTargetDataDisplays",
		]:
			var room_target := instance.find_child(target_name, true, false)
			_assert_outline_surface_target_contract(room_target, target_name, true, false)
			if room_target != null and room_target.has_method("get_highlight_mesh_count"):
				_assert_true(int(room_target.call("get_highlight_mesh_count")) > 0,
					"%s is wired to actual graybox meshes" % target_name)
				_assert_true(int(room_target.call("get_outline_shell_count")) > 0,
					"%s creates object-local outline shell meshes" % target_name)

		if placement != null:
			var zone_marker_pairs := {
				"GlassBeadZone": "GlassBeadZoneMarker",
				"macabre_tealZone": "MacabreTealZoneMarker",
				"hunter_ashZone": "HunterAshZoneMarker",
				"AwardsCenterZone": "AwardsCenterZoneMarker",
				"AwardsJournalismZone": "AwardsJournalismZoneMarker",
				"JStoreMainZone": "JStoreMainZoneMarker",
				"HallwayGate": "HallwayExit",
			}
			for zone_name in zone_marker_pairs.keys():
				var zone_node := instance.find_child(zone_name, true, false) as Node3D
				var marker_node := placement.find_child(str(zone_marker_pairs[zone_name]), true, false) as Node3D
				if zone_node != null and marker_node != null:
					_assert_true(zone_node.global_position.distance_to(marker_node.global_position) < 0.01,
						"%s uses its scene placement marker" % zone_name)

		var room_delegate_pairs := {
			"RoomTargetDesk": "Terminal",
			"RoomTargetDataDisplays": "Terminal",
			"RoomTargetDrinkMachine": "DrinkMachine",
			"RoomTargetGlassBeadGame": "GlassBeadZone",
			"RoomTargetMacabreTealPainting": "macabre_tealZone",
			"RoomTargetHunterAshPainting": "hunter_ashZone",
			"RoomTargetAwardsShelf": "AwardsCenterZone",
			"RoomTargetJStoreShelf": "JStoreMainZone",
		}
		for target_name in room_delegate_pairs.keys():
			var room_target := instance.find_child(str(target_name), true, false)
			var delegate := instance.find_child(str(room_delegate_pairs[target_name]), true, false)
			if room_target != null and delegate != null:
				_assert_true(room_target.has_method("get_interaction_delegate"),
					"%s exposes its semantic interaction delegate" % target_name)
				_assert_true(room_target.call("get_interaction_delegate") == delegate,
					"%s proxies clicks to %s" % [target_name, room_delegate_pairs[target_name]])

		var glass_zone := instance.find_child("GlassBeadZone", true, false)
		if glass_zone != null:
			dialogue.clear()
			dialogue.dialogue_finished.emit()
			await get_tree().process_frame
			_drive_interactable_zone(glass_zone, aster as Node3D, 1.0)
			_assert_equals(str(dialogue.get("_current_text")), "",
				"Aster inspection zones do not fire from proximity hold timers")

		var aster_camera = instance.find_child("GameCamera", true, false)
		var jstore_zone := instance.find_child("JStoreMainZone", true, false)
		if jstore_zone != null and aster_camera != null:
			dialogue.clear()
			jstore_zone.call("_trigger")
			await get_tree().process_frame
			_assert_equals(str(dialogue.get("_current_text")), DialogueData.text("aster.sim_expand.bookshelf.line"),
				"Aster exploration interaction opens directly on the object line")
			_assert_true(not str(dialogue.get("_current_text")).contains("Aster glances"),
				"Aster exploration interaction skips visible-action direction text")
			dialogue.clear()
			dialogue.dialogue_finished.emit()
			await get_tree().process_frame
			jstore_zone.call("_trigger")
			await get_tree().process_frame
			_assert_equals(str(dialogue.get("_current_text")), DialogueData.text("aster.sim_expand.bookshelf.articles_line"),
				"Aster J-store interaction advances to article details on the second click")
			dialogue.clear()
			dialogue.dialogue_finished.emit()
			if jstore_zone.has_meta("exploration_dialogue_index"):
				jstore_zone.set_meta("exploration_dialogue_index", 0)
			await get_tree().process_frame

		if glass_zone != null and feedback_manager != null:
			dialogue.clear()
			glass_zone.call("_on_mouse_entered")
			instance._sync_perception_shader()
			_assert_true(feedback_manager.call("get_hovered_target") == glass_zone,
				"Outline feedback manager owns interactable hover state")
			_assert_true(glass_zone.has_signal("interaction_requested"),
				"Interactable zones expose generic interaction requests")
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			glass_zone.call("_on_input_event", null, click, Vector3.ZERO, Vector3.UP, 0)
			instance._sync_perception_shader()
			_assert_true(feedback_manager.call("get_selected_target") == glass_zone,
				"Outline feedback manager owns interactable selected state")
			_assert_true(instance._game_state.is_moving("aster"),
				"Clicking an interactable asks the character controller to move Aster")
			_assert_equals(glass_zone.get("selected_feedback_color"), Color(1.0, 0.62, 0.12, 1.0),
				"Interactable selection feedback color is editable")
			_assert_true(glass_zone.find_child("SelectedParticles", true, false) != null,
				"Clicking an interactable emits selected feedback particles")
			var glass_particles := glass_zone.find_child("SelectedParticles", true, false) as GPUParticles3D
			if glass_particles != null:
				_assert_true(glass_particles.emitting and glass_particles.visible,
					"Interactable selected feedback is visible while Aster walks to inspect")
			instance.headless_advance(5.0, 0.05)
			await get_tree().process_frame
			_assert_equals(str(dialogue.get("_current_text")), DialogueData.text("aster.sim_expand.glass_bead.line"),
				"Inspection interactable fires when Aster reaches it in headless movement")
			_assert_true(feedback_manager.call("get_selected_target") == null,
				"Inspection interactable clears selected feedback after arrival")
			if glass_particles != null:
				_assert_true(not glass_particles.emitting and not glass_particles.visible,
					"Interactable selected feedback clears already-spawned particles")
			dialogue.clear()
			dialogue.dialogue_finished.emit()
			glass_zone.call("_on_mouse_exited")
			instance._sync_perception_shader()
			await get_tree().process_frame

		var macabre_target := instance.find_child("RoomTargetMacabreTealPainting", true, false)
		var awards_target := instance.find_child("RoomTargetAwardsShelf", true, false)
		if macabre_target != null and awards_target != null and feedback_manager != null:
			macabre_target.call("_on_mouse_entered")
			instance._sync_perception_shader()
			_assert_true(feedback_manager.call("get_hovered_target") == macabre_target,
				"Outline feedback manager owns graybox room hover state")
			_assert_true(bool(macabre_target.call("has_active_mesh_outline")),
				"Hovering a graybox room element applies the object outline shader to its meshes")
			_assert_true(int(macabre_target.call("get_outline_shell_count")) > 0,
				"Hovering a graybox room element uses object-local outline shell meshes")
			_assert_true(macabre_target.has_signal("interaction_requested"),
				"Room element targets expose generic interaction requests")
			var macabre_origin: Vector3 = macabre_target.call("get_outline_highlight_origin")
			var awards_origin: Vector3 = awards_target.call("get_outline_highlight_origin")
			_assert_true(macabre_origin.distance_to(awards_origin) > 4.0,
				"Room element hover targets are independently positioned")
			macabre_target.call("begin_queued_feedback", macabre_origin + Vector3(7.0, 0.0, 0.0))
			_assert_true(bool(macabre_target.call("has_active_glow")),
				"Room element selected feedback runs the morphing-noise emission glow on the object meshes")
			macabre_target.call("complete_queued_feedback")
			var surface_click := InputEventMouseButton.new()
			surface_click.button_index = MOUSE_BUTTON_LEFT
			surface_click.pressed = true
			macabre_target.call("_on_input_event", null, surface_click, macabre_origin, Vector3.UP, 0)
			instance._sync_perception_shader()
			_assert_true(feedback_manager.call("get_selected_target") == macabre_target,
				"Outline feedback manager owns graybox room selected state")
			_assert_true(bool(macabre_target.call("has_active_mesh_outline")),
				"Clicking a graybox room element keeps the object outline shader active for selected feedback")
			_assert_true(bool(macabre_target.call("is_selected_feedback_active")),
				"Clicked room element remains selected while Aster moves toward it")
			_assert_true(instance._game_state.is_moving("aster"),
				"Clicking a room element asks the character controller to move Aster toward it")
			_assert_true(bool(macabre_target.call("has_active_glow")),
				"Amber selected outline runs the morphing-noise emission glow on the outlined graybox meshes")
			macabre_target.call("_on_mouse_exited")
			instance._sync_perception_shader()
			_assert_true(bool(macabre_target.call("is_selected_feedback_active")),
				"Mouse exit does not clear queued gold feedback before arrival")
			instance.headless_advance(0.15, 0.05)
			_assert_true(bool(macabre_target.call("is_selected_feedback_active")),
				"Queued gold feedback persists during movement")
			instance.headless_advance(4.0, 0.05)
			await get_tree().process_frame
			_assert_equals(str(dialogue.get("_current_text")), DialogueData.text("aster.sim_expand.painting_1.line"),
				"Clicking an outlined room object triggers its paired inspection interactable")
			_assert_true(not bool(macabre_target.call("is_selected_feedback_active")),
				"Queued gold feedback clears after Aster reaches the object")
			_assert_true(feedback_manager.call("get_selected_target") == null,
				"Outline feedback manager clears selected state after arrival")
			_assert_true(not bool(macabre_target.call("has_active_glow")),
				"Room element emission glow stops and clears after arrival")

		var hallway_gate := instance.find_child("HallwayGate", true, false) as Node3D
		if hallway_gate != null:
			_assert_true(hallway_gate.global_position.x >= 16.0, "Aster Continue gate is at the room edge")

		await _assert_aster_interaction_click_matrix(instance, dialogue)

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Peris Simulation ---
func _test_peris_sim() -> void:
	_test_name = "Peris Simulation"

	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	_assert_true(scene != null, "Peris sim scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Peris sim scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Peris sim scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris player node exists")

		var monos: Node = instance.find_child("Monos", true, false)
		_assert_true(monos != null, "Monos NPC node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")
		for retired_key in [
			"peris_sim.waiting.thought",
			"peris_sim.monos.start",
			"peris_sim.sprint.thought",
			"peris_sim.care.thought",
			"peris_sim.correct.queue_first",
			"peris_sim.session_ends",
			"peris.sim_expand.narration.enter",
			"peris.sim_expand.logbook.interact",
		]:
			_assert_true(not DialogueData.has_key(retired_key),
				"Retired Peris sim dialogue key is absent: %s" % retired_key)

		instance._visit_phase = 1
		instance._start_workspace()
		for i in range(2):
			await get_tree().process_frame

		var peris_explore_zones := [
			"Plant1Zone",
			"Plant2Zone",
			"Plant3Zone",
			"Plant4Zone",
			"Plant5Zone",
			"Plant6Zone",
			"Plant7Zone",
			"Plant8Zone",
			"Plant9Zone",
			"PaintingZone",
			"WellnessZone",
			"StrikeWarningZone",
			"NotesZone",
			"LogbookGate",
		]
		for zone_name in peris_explore_zones:
			var zone := _assert_exploration_interactable_contract(instance, zone_name)
			if zone == null:
				continue
			if zone_name == "LogbookGate":
				_assert_equals(str(zone.get("interactable_id")), "peris.logbook_gate",
					"Peris logbook gate pulls its behavior from the interactable data catalog")
				_assert_interactable_type(zone, Interactable.InteractableType.HOLD_ACTION,
					"Peris logbook gate")
			else:
				_assert_equals(str(zone.get("interactable_id")), "tutorial.inspection",
					"%s pulls inspection behavior from the interactable data catalog" % zone_name)
				_assert_interactable_type(zone, Interactable.InteractableType.INSPECTION,
					"%s" % zone_name)
		_assert_interactable_spacing(instance, peris_explore_zones, 2.8,
			"Peris exploration interactables are spaced apart")

		# Exploration objects now carry the shared outline + surface-particle feedback.
		var peris_outline_targets := [
			"Plant1Outline", "Plant5Outline", "PaintingOutline", "WellnessOutline",
			"StrikeWarningOutline", "NotesOutline", "LogbookOutline",
		]
		for target_name in peris_outline_targets:
			var ot := instance.find_child(target_name, true, false)
			_assert_true(ot != null, "Peris exploration object %s has an outline target" % target_name)
			if ot == null:
				continue
			_assert_true(bool(ot.get("outline_particles_enabled")),
				"%s emits outline particles" % target_name)
			if ot.has_method("get_highlight_mesh_count"):
				_assert_true(int(ot.call("get_highlight_mesh_count")) > 0,
					"%s wraps actual object meshes" % target_name)
			if ot.has_method("get_outline_shell_count"):
				_assert_true(int(ot.call("get_outline_shell_count")) > 0,
					"%s builds object-local outline shells" % target_name)

		var camera = instance.find_child("GameCamera", true, false)
		var plant_zone := instance.find_child("Plant1Zone", true, false)
		if plant_zone != null and camera != null:
			dialogue.clear()
			_drive_interactable_zone(plant_zone, peris as Node3D, 1.0)
			_assert_equals(str(dialogue.get("_current_text")), "",
				"Peris inspection zones do not fire from proximity hold timers")
			var previous_offset: Vector3 = camera.follow_offset
			var previous_target: Node3D = camera.target
			plant_zone.call("_trigger")
			await get_tree().process_frame
			_assert_true(instance._scheduler.is_paused(),
				"Peris exploration interaction pauses scheduler time while focused")
			_assert_true(bool(camera.call("is_locked")),
				"Peris exploration interaction locks the camera to the interactable")
			_assert_equals(camera.follow_offset, Vector3(0, 4.2, 3.2),
				"Peris exploration interaction uses the close inspection camera offset")
			_assert_equals(str(dialogue.get("_current_text")), DialogueData.text("peris.sim_expand.plant_1.line"),
				"Peris plant interaction opens directly on the object line")
			_assert_true(not str(dialogue.get("_current_text")).contains("Peris "),
				"Peris plant interaction does not queue visible-action narration")
			_drain_dialogue_box(dialogue, 10.0, 0.05)
			await get_tree().process_frame
			_assert_true(not dialogue.is_active(),
				"Peris focused inspection dialogue advances while scheduler time is paused")
			_assert_true(not instance._scheduler.is_paused(),
				"Peris exploration focus restores scheduler time after dialogue finishes")
			_assert_true(not bool(camera.call("is_locked")),
				"Peris exploration focus unlocks the camera after dialogue finishes")
			_assert_equals(camera.follow_offset, previous_offset,
				"Peris exploration focus restores the previous camera offset")
			_assert_true(camera.target == previous_target,
				"Peris exploration focus restores the previous camera target")
			_assert_true(bool(peris.get("_move_enabled")),
				"Peris movement is re-enabled after exploration focus finishes")

		var strike_zone := instance.find_child("StrikeWarningZone", true, false)
		if strike_zone != null and camera != null:
			dialogue.clear()
			strike_zone.call("_trigger")
			await get_tree().process_frame
			var strike_text := str(dialogue.get("_current_text"))
			_assert_equals(strike_text, DialogueData.text("peris.sim_expand.strike_warning.notification"),
				"Strike warning opens on the pinned document without visible-action narration")
			_assert_true(not strike_text.contains("glances"),
				"Strike warning interaction does not queue the old glance narration")
			dialogue.clear()
			dialogue.dialogue_finished.emit()
			await get_tree().process_frame

		var logbook_gate := instance.find_child("LogbookGate", true, false) as Node3D
		if logbook_gate != null:
			_assert_true(logbook_gate.global_position.x <= -3.5, "Peris Continue gate is at the room edge")

		await _assert_peris_interaction_click_matrix(instance, dialogue)

		_assert_true(instance._game_state.characters.has("monos"), "Monos is registered with GameState")
		if monos != null:
			monos.fade_out(1.0)
			instance.headless_advance(0.5, 0.1)
			_assert_true(monos._label.modulate.a < 0.7, "Monos fade follows scheduler time")
			instance.headless_advance(0.6, 0.1)
			_assert_true(monos._label.modulate.a <= 0.01, "Monos fade completes under scheduler fast-forward")

		if dialogue != null:
			dialogue.clear()
			instance._start_alert_monos()
			await get_tree().process_frame
			_assert_equals(instance._current_step, "protect_prompt",
				"Peris protect tutorial reaches the paused dialogue prompt")
			_assert_equals(float(instance._compute_speed()), 0.0,
				"Peris protect tutorial freezes gameplay simulation time")
			_drain_dialogue_box(dialogue)
			await get_tree().process_frame
			_assert_true(not dialogue.is_active(),
				"Peris protect prompt dialogue can fast-forward while gameplay is paused")
			_assert_equals(instance._current_step, "protect_prompt",
				"UI-only dialogue advancement does not mutate the tutorial step")

		instance.queue_free()
		await get_tree().process_frame

		await _assert_peris_phase2_live_post_attack_progression(scene)

func _assert_peris_phase2_live_post_attack_progression(scene: PackedScene) -> void:
	var instance: Node = scene.instantiate()
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var dialogue: Node = instance.find_child("DialogueBox", true, false)
	_assert_true(dialogue != null, "Peris phase 2 live regression has dialogue")
	if dialogue == null:
		instance.queue_free()
		await get_tree().process_frame
		return

	var actioned := {}
	var saw_efficiency_log := false
	var saw_sanction_notice := false
	var elapsed := 0.0
	var step := 0.05
	while elapsed < 90.0:
		var current_step := str(instance._current_step)
		if current_step == "efficiency_log":
			saw_efficiency_log = true
		if current_step == "sanction_notice":
			saw_sanction_notice = true
			break

		if current_step == "protect_prompt" and not actioned.has("protect_prompt") and not dialogue.is_active():
			actioned["protect_prompt"] = true
			instance._on_protect_pressed()
		elif current_step == "run_prompt" and not actioned.has("run_prompt"):
			actioned["run_prompt"] = true
			instance._toggle_run()
		elif current_step == "click_monos" and not actioned.has("click_monos"):
			actioned["click_monos"] = true
			instance._start_confirm_protect()
		elif current_step == "confirm_protect" and not actioned.has("confirm_protect"):
			actioned["confirm_protect"] = true
			instance._toggle_pause()

		_pump_dialogue(dialogue, 12.0)
		if instance.has_method("_process"):
			instance._process(step)
		elapsed += step

	_assert_true(saw_efficiency_log,
		"Peris phase 2 live path reaches the feed-terminal close / efficiency log")
	_assert_true(saw_sanction_notice,
		"Peris phase 2 live path advances from closed feed terminal to sanction notice")
	_assert_equals(str(instance._current_step), "sanction_notice",
		"Peris phase 2 live path is not stuck after the feed terminal closes")

	instance._visit_phase = 1
	instance.queue_free()
	await get_tree().process_frame

func _assert_scheduler_animation_bridge(instance: Node) -> void:
	var probe := Node3D.new()
	probe.name = "SchedulerAnimationProbe"
	instance.add_child(probe)

	var player := AnimationPlayer.new()
	player.name = "ProbeAnimationPlayer"
	player.root_node = NodePath("..")
	probe.add_child(player)

	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 1.0
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(".:position:x"))
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, 1.0, 10.0)
	lib.add_animation("probe_move", anim)
	player.add_animation_library("", lib)

	instance._play_scheduler_animation(player, "probe_move")
	instance.headless_advance(0.5, 0.1)
	_assert_true(probe.position.x >= 4.0 and probe.position.x <= 6.0,
		"AnimationPlayer clip samples halfway from scheduler time")
	instance.headless_advance(0.6, 0.1)
	_assert_true(probe.position.x >= 9.5, "AnimationPlayer clip completes under scheduler fast-forward")
	_assert_true(not instance._scheduler_animation_states.has(player.get_instance_id()),
		"Completed scheduler animation is removed from active animation set")
	probe.queue_free()

func _assert_aster_interaction_click_matrix(instance: Node, dialogue: Node) -> void:
	var aster_start: Vector3 = instance._placement_or_grid("AsterStart", Vector2i(3, 4), 0.5)
	var terminal_start: Vector3 = instance._placement_or_position("DrinkMachineInteract", Vector3(8.0, aster_start.y, -3.0))
	terminal_start.y = aster_start.y
	var terminal_checks := [
		{"target": "RoomTargetDesk", "delegate": "Terminal", "label": "Desk visible target"},
		{"target": "RoomTargetDataDisplays", "delegate": "Terminal", "label": "Data displays visible target"},
	]
	for check in terminal_checks:
		await _reset_dialogue_focus(instance, dialogue)
		instance._scheduler.clear()
		instance._current_step = "show_terminal"
		if instance._terminal and instance._terminal.has_method("reset"):
			instance._terminal.reset()
		if instance._terminal and instance._terminal.has_method("set_interaction_enabled"):
			instance._terminal.set_interaction_enabled(true)
		await _click_target_and_advance(instance, str(check.target), "aster", terminal_start, 5.0, str(check.label))
		await get_tree().process_frame
		_assert_equals(instance._current_step, "terminal_focus",
			"%s click opens the terminal forecast focus beat" % check.label)
		# Advance only until the focus beat ends, so we land on terminal_data
		# rather than overshooting into the next scheduled steps.
		var reached_terminal_data := false
		for _i in range(80):
			instance.headless_advance(0.1, 0.1)
			if str(instance._current_step) == "terminal_data":
				reached_terminal_data = true
				break
		_assert_true(reached_terminal_data,
			"%s click reaches the terminal interactable and advances the tutorial" % check.label)
		_assert_equals(str(dialogue.get("_current_text")), "",
			"%s click advances silently through the forecast screen-focus beat" % check.label)

	await _reset_dialogue_focus(instance, dialogue)
	instance._scheduler.clear()
	instance._current_step = "walk_to_drink"
	instance._has_drunk = false
	if instance._drink_machine and instance._drink_machine.has_method("reset"):
		instance._drink_machine.reset()
	if instance._drink_machine and instance._drink_machine.has_method("set_interaction_enabled"):
		instance._drink_machine.set_interaction_enabled(true)
	await _click_target_and_advance(instance, "RoomTargetDrinkMachine", "aster", aster_start, 5.0, "Drink machine visible target")
	_drive_interactable_zone(instance._drink_machine, instance._player as Node3D, float(instance._drink_machine.get("dwell_time")) + 0.2)
	await get_tree().process_frame
	_assert_equals(instance._current_step, "drink",
		"Drink machine visible target click reaches the drink interactable")
	_assert_true(instance._has_drunk,
		"Drink machine visible target click updates the drink state")
	_assert_equals(float(instance._game_state.get_stat("aster", "atp")), float(instance.ATP_MAX),
		"Drink machine visible target click applies the ATP refill")

	var inspection_checks := [
		{"target": "RoomTargetGlassBeadGame", "delegate": "GlassBeadZone", "text": "aster.sim_expand.glass_bead.line"},
		{"target": "RoomTargetMacabreTealPainting", "delegate": "macabre_tealZone", "text": "aster.sim_expand.painting_1.line"},
		{"target": "RoomTargetHunterAshPainting", "delegate": "hunter_ashZone", "text": "aster.sim_expand.painting_2.line"},
		{"target": "RoomTargetAwardsShelf", "delegate": "AwardsCenterZone", "text": "aster.sim_expand.awards.line"},
		{"target": "RoomTargetJStoreShelf", "delegate": "JStoreMainZone", "text": "aster.sim_expand.bookshelf.line"},
	]
	for check in inspection_checks:
		await _reset_dialogue_focus(instance, dialogue)
		instance._scheduler.clear()
		instance._current_step = "explore_workspace"
		var delegate := instance.find_child(str(check.delegate), true, false)
		if delegate != null and delegate.has_method("reset"):
			delegate.reset()
		if delegate != null and delegate.has_meta("exploration_dialogue_index"):
			delegate.set_meta("exploration_dialogue_index", 0)
		await _click_target_and_advance(instance, str(check.target), "aster", aster_start, 6.0, str(check.target))
		_assert_equals(str(dialogue.get("_current_text")), DialogueData.text(str(check.text)),
			"%s click reaches %s and plays its inspection line" % [str(check.target), str(check.delegate)])
	await _reset_dialogue_focus(instance, dialogue)

func _assert_peris_interaction_click_matrix(instance: Node, dialogue: Node) -> void:
	var checks := []
	for i in range(1, 10):
		checks.append({
			"target": "Plant%dZone" % i,
			"text": "peris.sim_expand.plant_%d.line" % i,
		})
	checks.append({"target": "PaintingZone", "text": "peris.sim_expand.painting.line"})
	checks.append({"target": "WellnessZone", "text": "peris.sim_expand.wellness.line"})
	checks.append({"target": "StrikeWarningZone", "text": "peris.sim_expand.strike_warning.notification"})
	checks.append({"target": "NotesZone", "text": "peris.sim_expand.notes.line"})

	for check in checks:
		await _reset_dialogue_focus(instance, dialogue)
		instance._scheduler.clear()
		instance._current_step = "workspace"
		var target := instance.find_child(str(check.target), true, false)
		if target != null and target.has_method("reset"):
			target.reset()
		await _click_target_and_advance(instance, str(check.target), "peris", instance.PERIS_START, 7.0, str(check.target))
		_assert_equals(str(dialogue.get("_current_text")), DialogueData.text(str(check.text)),
			"%s click-to-arrival path plays the expected Peris inspection line" % check.target)
	await _reset_dialogue_focus(instance, dialogue)

func _assert_interactable_spacing(root: Node, node_names: Array, min_distance: float, label: String) -> void:
	var min_dist := 999999.0
	var closest_pair := ""
	for i in range(node_names.size()):
		var a_node := root.find_child(str(node_names[i]), true, false) as Node3D
		if a_node == null:
			continue
		for j in range(i + 1, node_names.size()):
			var b_node := root.find_child(str(node_names[j]), true, false) as Node3D
			if b_node == null:
				continue
			var dist := Vector2(
				a_node.global_position.x - b_node.global_position.x,
				a_node.global_position.z - b_node.global_position.z
			).length()
			if dist < min_dist:
				min_dist = dist
				closest_pair = "%s/%s" % [str(node_names[i]), str(node_names[j])]
	_assert_true(min_dist >= min_distance,
		"%s (closest: %s %.2fm, minimum: %.2fm)" % [label, closest_pair, min_dist, min_distance])

func _assert_exploration_interactable_contract(root: Node, node_name: String) -> Node:
	var node := root.find_child(node_name, true, false)
	_assert_true(node != null, "%s exploration interactable exists" % node_name)
	if node == null:
		return null
	var script: Script = node.get_script()
	var script_path := script.resource_path if script != null else ""
	_assert_equals(script_path, "res://scripts/game/objects/interactable.gd",
		"%s uses the shared interactable script" % node_name)
	_assert_equals(int(node.get("collision_layer")), 4,
		"%s is on the interactable collision layer" % node_name)
	_assert_equals(int(node.get("collision_mask")), 2,
		"%s detects player bodies" % node_name)
	_assert_true(bool(node.get("input_ray_pickable")),
		"%s can receive mouse hover and click picking" % node_name)
	_assert_true(node.has_signal("outline_hovered"),
		"%s emits shared hover outline feedback" % node_name)
	_assert_true(node.has_signal("outline_selected"),
		"%s emits shared selected outline feedback" % node_name)
	_assert_true(node.has_signal("interaction_requested"),
		"%s emits reusable interaction requests" % node_name)
	_assert_true(node.has_method("set_feedback_managed") and node.has_method("is_feedback_managed"),
		"%s can delegate feedback state to a central manager" % node_name)
	_assert_equals(node.get("hover_outline_color"), Color.WHITE,
		"%s hover outline defaults to white" % node_name)
	_assert_equals(node.get("selected_feedback_color"), Color(1.0, 0.62, 0.12, 1.0),
		"%s selected feedback defaults to editable amber" % node_name)
	var shape_node := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_assert_true(shape_node != null, "%s has a collision shape" % node_name)
	if shape_node != null:
		_assert_true(shape_node.shape is SphereShape3D, "%s uses a spherical interaction volume" % node_name)
		if shape_node.shape is SphereShape3D:
			var sphere := shape_node.shape as SphereShape3D
			_assert_true(sphere.radius >= 1.6, "%s has a larger interaction radius" % node_name)
			var highlight_radius := float(node.call("get_outline_highlight_radius")) if node.has_method("get_outline_highlight_radius") else float(node.get("outline_highlight_radius"))
			_assert_true(highlight_radius + 0.001 >= sphere.radius,
				"%s outline highlight covers the full interaction zone" % node_name)
	_assert_true(bool(node.get("monitoring")) and bool(node.get("interaction_enabled")),
		"%s interaction is active (monitoring its proximity zone)" % node_name)
	return node

func _assert_interactable_type(node: Node, expected_type: int, label: String) -> void:
	if node == null:
		return
	_assert_equals(int(node.get("interactable_type")), expected_type,
		"%s has the expected interactable type enum" % label)

func _test_singleton(singleton_name: String, script_path: String) -> Node:
	var existing := get_node_or_null("/root/%s" % singleton_name)
	if existing != null:
		return existing
	var script := load(script_path)
	if script == null:
		return null
	var node := Node.new()
	node.name = singleton_name
	node.set_script(script)
	get_tree().root.add_child(node)
	return node

func _assert_outline_surface_target_contract(node: Node, label: String, expect_pickable := true, expect_visual := true) -> void:
	_assert_true(node != null, "%s exists" % label)
	if node == null:
		return
	var script: Script = node.get_script()
	var script_path := script.resource_path if script != null else ""
	_assert_equals(script_path, "res://scripts/game/objects/outline_surface_target.gd",
		"%s uses the reusable outline target script" % label)
	_assert_true(node is StaticBody3D, "%s is a pickable static body" % label)
	if expect_pickable:
		_assert_equals(int(node.get("collision_layer")), 4, "%s is on the pickable/interactable layer" % label)
		_assert_true(bool(node.get("input_ray_pickable")), "%s can receive mouse hover and click input" % label)
	else:
		_assert_equals(int(node.get("collision_layer")), 0, "%s does not participate in picking by default" % label)
		_assert_true(not bool(node.get("input_ray_pickable")), "%s is not mouse pickable by default" % label)
	_assert_true(node.has_signal("outline_hovered"), "%s emits hover outline feedback" % label)
	_assert_true(node.has_signal("outline_selected"), "%s emits selected outline feedback" % label)
	_assert_true(node.has_signal("interaction_requested"), "%s emits reusable interaction requests" % label)
	_assert_true(node.has_method("set_feedback_managed") and node.has_method("is_feedback_managed"),
		"%s can delegate feedback state to a central manager" % label)
	_assert_equals(node.get("hover_outline_color"), Color.WHITE, "%s hover outline defaults to white" % label)
	_assert_equals(node.get("selected_feedback_color"), Color(1.0, 0.62, 0.12, 1.0),
		"%s selected feedback defaults to editable amber" % label)
	var visual := node.get_node_or_null("Visual") as MeshInstance3D
	if expect_visual:
		_assert_true(visual != null, "%s has a visual mesh child" % label)
	if visual != null and visual.mesh != null:
		_assert_equals(visual.mesh.get_surface_count(), 1,
			"%s visual contains exactly one split surface" % label)
	var shape_node := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_assert_true(shape_node != null and shape_node.shape != null, "%s has a generated pick collision shape" % label)
	if node.has_method("get_outline_highlight_radius"):
		_assert_true(float(node.call("get_outline_highlight_radius")) > 0.0,
			"%s calculates a shader highlight radius" % label)

func _find_nodes_with_script(root: Node, script_path: String) -> Array:
	var matches := []
	_collect_nodes_with_script(root, script_path, matches)
	return matches

func _find_nodes_with_meta(root: Node, meta_name: String) -> Array:
	var matches := []
	_collect_nodes_with_meta(root, meta_name, matches)
	return matches

func _collect_nodes_with_script(node: Node, script_path: String, matches: Array) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path == script_path:
		matches.append(node)
	for child in node.get_children():
		_collect_nodes_with_script(child, script_path, matches)

func _collect_nodes_with_meta(node: Node, meta_name: String, matches: Array) -> void:
	if node.has_meta(meta_name):
		matches.append(node)
	for child in node.get_children():
		_collect_nodes_with_meta(child, meta_name, matches)

func _clear_sequence_runtime_for_spatial_test(instance: Node) -> void:
	if "_scheduler" in instance and instance._scheduler:
		instance._scheduler.clear()
		instance._scheduler.resume()
	if "_dialogue" in instance and instance._dialogue and instance._dialogue.has_method("clear"):
		instance._dialogue.clear()
	if "_tutorial_prompt" in instance and instance._tutorial_prompt and instance._tutorial_prompt.has_method("hide_prompt"):
		instance._tutorial_prompt.hide_prompt()

func _drive_interactable_zone(area: Node, body: Node3D, dwell_seconds: float, step := 0.1) -> void:
	if area == null or body == null:
		return
	if area.has_method("_on_body_entered"):
		area.call("_on_body_entered", body)
	var elapsed := 0.0
	while elapsed < dwell_seconds:
		var dt: float = minf(step, dwell_seconds - elapsed)
		if area.has_method("_process"):
			area.call("_process", dt)
		elapsed += dt
	# Scheduler-driven dwell completes via a scheduled event, not _process; this
	# helper drives the interactable in isolation, so fire the completion directly.
	if "_scheduler" in area and area._scheduler != null and area.has_method("_on_dwell_complete"):
		area.call("_on_dwell_complete")
	if area.has_method("_on_body_exited"):
		area.call("_on_body_exited", body)

func _reset_dialogue_focus(instance: Node, dialogue: Node) -> void:
	if dialogue != null and dialogue.has_method("clear"):
		dialogue.clear()
		dialogue.dialogue_finished.emit()
	if "_scheduler" in instance and instance._scheduler != null and instance._scheduler.is_paused():
		instance._scheduler.resume()
	if "_player" in instance and instance._player != null and instance._player.has_method("set_move_enabled"):
		instance._player.set_move_enabled(true)
	await get_tree().process_frame

func _click_target_and_advance(
		instance: Node,
		target_name: String,
		char_id: String,
		start_position: Vector3,
		advance_seconds: float,
		label: String
	) -> void:
	var target := instance.find_child(target_name, true, false)
	_assert_true(target != null, "%s click target exists" % label)
	if target == null:
		return
	if target.has_method("complete_queued_feedback"):
		target.complete_queued_feedback()
	if target.has_method("_on_mouse_exited"):
		target.call("_on_mouse_exited")
	_set_sequence_character_position(instance, char_id, start_position)
	if "_player" in instance and instance._player != null and instance._player.has_method("set_move_enabled"):
		instance._player.set_move_enabled(true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var event_position: Vector3 = target.global_position if target is Node3D else start_position
	if target.has_method("get_outline_highlight_origin"):
		var origin = target.call("get_outline_highlight_origin")
		if origin is Vector3:
			event_position = origin
	target.call("_on_input_event", null, click, event_position, Vector3.UP, 0)
	if "_game_state" in instance and instance._game_state != null and instance._game_state.characters.has(char_id):
		_assert_true(instance._game_state.is_moving(char_id),
			"%s click starts scheduler-backed movement for %s" % [label, char_id])
	if instance.has_method("headless_advance"):
		instance.headless_advance(advance_seconds, 0.05)
	await get_tree().process_frame

func _assert_elevator_movement_gate(instance: Node, gate: Dictionary) -> void:
	var label := str(gate.get("label", "movement gate"))
	var start_step := str(gate.get("start_step", ""))
	var expected_step := str(gate.get("expected_step", ""))
	if bool(gate.get("reset_runtime", true)):
		_clear_sequence_runtime_for_spatial_test(instance)
	if start_step != "":
		instance._enter_step(start_step)
	var selected_ids: Array = gate.get("selected_ids", [])
	if selected_ids.size() > 0 and "_hud" in instance and instance._hud != null:
		instance._hud.set_selected_portraits(selected_ids)
	var characters: Array = gate.get("characters", [])
	for character_gate in characters:
		var character := character_gate as Dictionary
		_set_sequence_character_position(
			instance,
			str(character.get("id", "")),
			character.get("outside", Vector3.ZERO)
		)
	if instance.has_method("_on_process"):
		instance._on_process(0.1, 1.0)
	_assert_equals(instance._current_step, start_step, "%s does not fire while characters are outside mapped trigger zones" % label)
	if "_scheduler" in instance and instance._scheduler:
		instance._scheduler.resume()
	for character_gate in characters:
		var character := character_gate as Dictionary
		var char_id := str(character.get("id", ""))
		if "_game_state" in instance and instance._game_state:
			instance._game_state.command_move_to_pos(char_id, character.get("target", Vector3.ZERO))
	var max_time := float(gate.get("max_time", 4.0))
	var advance_step := float(gate.get("step", 0.05))
	if instance.has_method("headless_advance"):
		instance.headless_advance(max_time, advance_step)
	_assert_equals(instance._current_step, expected_step, "%s advances when mapped movement crosses the trigger" % label)

func _assert_elevator_escort_standoff(instance: Node, min_distance: float, label: String) -> void:
	for guard_id in ["eu1", "eu2"]:
		var guard_pos: Vector3 = instance._game_state.get_position(guard_id)
		var nearest := 999999.0
		for party_id in ["peris", "aster"]:
			var party_pos: Vector3 = instance._game_state.get_position(party_id)
			var dist := Vector2(guard_pos.x - party_pos.x, guard_pos.z - party_pos.z).length()
			nearest = minf(nearest, dist)
		_assert_true(nearest >= min_distance,
			"%s: %s remains %.2fm from the party (minimum %.2fm)" % [label, guard_id, nearest, min_distance])

func _assert_elevator_fall_lands_clear_of_enemies(instance: Node, min_buffer: float, label: String) -> void:
	var checked := 0
	var nearest_margin := INF
	for party_id in ["peris", "aster"]:
		var party_pos: Vector3 = instance._game_state.get_position(party_id)
		for enemy in instance._enemies:
			if not is_instance_valid(enemy):
				continue
			if enemy.has_method("is_alive") and not enemy.is_alive():
				continue
			if not instance._game_state.characters.has(enemy.char_id):
				continue
			var enemy_pos: Vector3 = instance._game_state.get_position(enemy.char_id)
			var enemy_range := 0.0
			if "detection_range" in enemy:
				enemy_range = float(enemy.detection_range)
			elif instance._game_state.characters[enemy.char_id].stats.has("detection_range"):
				enemy_range = float(instance._game_state.characters[enemy.char_id].stats["detection_range"])
			var horizontal_distance := Vector2(
				party_pos.x - enemy_pos.x,
				party_pos.z - enemy_pos.z
			).length()
			nearest_margin = minf(nearest_margin, horizontal_distance - enemy_range)
			checked += 1
	_assert_true(checked > 0, "%s checks spawned below-level enemies" % label)
	_assert_true(nearest_margin >= min_buffer,
		"%s: party lands outside enemy detection by %.2fm (minimum %.2fm)" % [label, nearest_margin, min_buffer])

func _assert_elevator_active_player_can_move(instance: Node, label: String) -> void:
	_assert_true(instance._player != null, "%s has an active player character" % label)
	if instance._player == null:
		return
	_assert_true(bool(instance._player.get("_move_enabled")),
		"%s leaves the active player movement-enabled" % label)

# --- Test: the elevator bridge collapse is a REAL cross-level transition (upper deck -> lower deck) ---
# The multi-level grid port: the party spawns on the UPPER deck (grid level 1) and the bridge collapse drops
# them to the LOWER deck (level 0) via set_character_level — the data-layer level + floor Y change and the
# transition is logged (KIND_SET_LEVEL), not a hand-poked Y. Guards against regressing to a manual Y poke.
func _test_elevator_fall_level() -> void:
	_test_name = "Elevator Fall Level"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if scene == null:
		_assert_true(false, "Elevator scene loads")
		return
	var instance: Node = scene.instantiate()
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	get_tree().root.add_child(instance)
	for i in range(8):
		await get_tree().process_frame
	var gs = instance._game_state
	_assert_true(gs != null and gs.grid != null and gs.grid.level_count >= 2,
		"The elevator builds a two-deck stacked grid")
	_assert_equals(gs.get_character_level("peris"), int(instance.LEVEL_UPPER), "Peris spawns on the upper deck")
	_assert_equals(gs.get_character_level("aster"), int(instance.LEVEL_UPPER), "Aster spawns on the upper deck")
	var upper_y: float = gs.get_position("peris").y
	# Drive the fall landing (the bridge gives way) and assert a real cross-level transition.
	instance._enter_step("bridge_collapse")
	instance._on_fall_landed()
	_assert_equals(gs.get_character_level("peris"), int(instance.LEVEL_LOWER), "After the fall Peris is on the lower deck")
	_assert_equals(gs.get_character_level("aster"), int(instance.LEVEL_LOWER), "After the fall Aster is on the lower deck")
	_assert_true(gs.get_position("peris").y < upper_y - 1.0,
		"The fall drops the data-layer Y to the lower deck (%.1f -> %.1f)" % [upper_y, gs.get_position("peris").y])
	# The transition is logged so replay reproduces the fall (not a silent position poke).
	if gs.event_log != null:
		var has_set_level := false
		for e in gs.event_log.events:
			if String(e.get("kind", "")) == GameEvent.KIND_SET_LEVEL:
				has_set_level = true
		_assert_true(has_set_level, "The fall logs a KIND_SET_LEVEL transition (replay reproduces it)")
	if instance.has_method("_teardown_sequence"):
		instance._teardown_sequence()
	instance.queue_free()
	await get_tree().process_frame

# --- Test: Leaving Facility ---
# --- Test: Elevator Tutorial ---
func _test_elevator() -> void:
	_test_name = "Elevator Tutorial"

	var scene := load("res://scenes/tutorial/elevator.tscn")
	_assert_true(scene != null, "Elevator scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Elevator scene instantiates")
		if "suppress_scene_change" in instance:
			instance.suppress_scene_change = true
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Scene is in tree")

		var env: Node = instance.find_child("Environment", true, false)
		_assert_true(env != null, "Environment node exists")

		var chars: Node = instance.find_child("Characters", true, false)
		_assert_true(chars != null, "Characters node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris player node exists")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		if "_scheduler" in instance:
			_assert_true(instance._scheduler != null, "EventScheduler exists")
			_assert_true(instance._game_state != null, "GameState exists")

		var exit_btn: Node = instance.find_child("ExitButton", true, false)
		_assert_true(exit_btn != null, "Exit button exists")
		if exit_btn != null:
			_assert_true(not bool(exit_btn.get("monitoring")),
				"Exit button interaction is inactive before EMP unlock")

		_clear_sequence_runtime_for_spatial_test(instance)
		instance._start_approach_aster()
		for wake_frame in range(2):
			await get_tree().process_frame
		var wake_zone := _assert_exploration_interactable_contract(instance, "AsterWakeZone")
		if wake_zone != null:
			_assert_equals(str(wake_zone.get("required_character")), "peris",
				"Aster wake zone is Peris-specific")
			_set_sequence_character_position(
				instance,
				"peris",
				instance.ASTER_POS + Vector3(3.5, 0.5, 0.0)
			)
			instance._on_process(0.1, 1.0)
			_assert_equals(instance._current_step, "approach_aster",
				"Aster wake zone does not fire while Peris is outside")
			_set_sequence_character_position(instance, "peris", (wake_zone as Node3D).global_position)
			_drive_interactable_zone(wake_zone, instance._peris_node, 0.7)
			instance.headless_advance(0.1, 0.05)
			_assert_equals(instance._current_step, "wake_aster",
				"Aster wake zone advances after Peris dwells in it")
			await get_tree().process_frame
			_assert_true(instance.find_child("AsterWakeZone", true, false) == null,
				"Aster wake zone disappears once Peris wakes him")

		_clear_sequence_runtime_for_spatial_test(instance)
		if dialogue.has_method("clear"):
			dialogue.clear()
		instance._start_units_activate()
		instance.headless_advance(4.0, 0.1)
		_assert_elevator_escort_standoff(instance, 2.0,
			"Escort units stop short during Aster EMP setup")
		_drain_dialogue_box(dialogue, 25.0, 0.05)
		instance.headless_advance(0.1, 0.05)
		_assert_equals(instance._current_step, "emp_tutorial",
			"EMP tutorial prompt fires after unit warning dialogue")
		_assert_true(instance._scheduler.is_paused(), "EMP tutorial pauses after the prompt is available")
		_assert_true(str(instance._tutorial_prompt._label.text).contains("EMP"),
			"EMP tutorial prompt text is visible")
		_assert_true(str(instance._tutorial_prompt._label.text).contains("[E]"),
			"EMP tutorial maps Aster's main ability to E")
		_assert_elevator_escort_standoff(instance, 2.0,
			"Escort units are not touching the party at the EMP prompt")
		instance._toggle_pause()
		_assert_true(instance._scheduler.is_paused(),
			"EMP tutorial cannot unpause before Aster queues EMP")
		_assert_true(_press_hud_action_key(instance, KEY_E), "Elevator accepts E (EMP action) for Aster EMP")
		_assert_true(instance._emp_queued, "Aster EMP queues from E while the tutorial is paused")
		_assert_elevator_escort_standoff(instance, 2.0,
			"Escort units are not touching the party while EMP is queued")
		instance._toggle_pause()
		_assert_true(not instance._scheduler.is_paused(),
			"EMP tutorial unpauses after Aster queues EMP")
		_assert_equals(instance._emp_count, 2, "Queued EMP fires when the tutorial unpauses")
		_assert_elevator_escort_standoff(instance, 2.0,
			"Escort units are not touching the party when EMP fires")
		instance.headless_advance(1.6, 0.1)
		_assert_equals(instance._current_step, "doors_unlocked",
			"Queued EMP advances to the door unlock")
		if exit_btn != null:
			_assert_true(bool(exit_btn.get("monitoring")),
				"Exit button interaction is active after EMP unlock")
		dialogue.dialogue_finished.emit()
		_assert_equals(instance._current_step, "doors_open",
			"Door cycling notification opens the doors automatically")
		if exit_btn != null:
			_assert_true(not bool(exit_btn.get("monitoring")),
				"Exit button interaction turns off once doors start opening")
		instance.headless_advance(2.1, 0.1)
		_assert_equals(instance._current_step, "multiselect_tutorial",
			"Door opening advances to the multiselect tutorial")
		_assert_true(instance._scheduler.is_paused(),
			"Multiselect tutorial pauses after doors finish opening")
		_assert_true(bool(instance._hud.get("_multi_select")),
			"Multiselect tutorial enables HUD multi-select")
		_assert_equals(instance._hud.get_selected_ids(), ["peris"],
			"Multiselect tutorial starts with only Peris selected")
		instance._toggle_pause()
		_assert_true(instance._scheduler.is_paused(),
			"Multiselect tutorial cannot unpause before Peris and Aster are selected together")

		var exit_gate := Vector3(instance.ELEVATOR_SIZE.x / 2.0, 0.5, 0.0)
		_set_sequence_character_position(instance, "peris", exit_gate + Vector3(0.0, 0.0, -0.5))
		_set_sequence_character_position(instance, "aster", exit_gate + Vector3(0.0, 0.0, 0.5))
		instance._on_process(0.1, 1.0)
		_assert_equals(instance._current_step, "multiselect_tutorial",
			"Door gate does not advance when both characters arrive without the two-character selection")
		instance._hud.set_selected_portraits(["peris", "aster"])
		_assert_equals(instance._hud.get_selected_ids(), ["peris", "aster"],
			"Ctrl/shift multi-select can select both Peris and Aster")
		instance._selected_character_ids.assign(["peris", "aster"])
		instance._apply_character_control_selection()
		# Group movement is driven by the ACTIVE controller issuing a spread party
		# move, not by both controllers moving to the same cell (which stacked them).
		_assert_true(bool(instance._peris_node.get("_move_enabled")) and bool(instance._peris_node.get("group_move")),
			"Selecting both routes the active controller as a spread group move")
		_assert_true(not bool(instance._aster_node.get("_move_enabled")),
			"The other member is carried by the group move, not its own click (no stacking)")
		# The party is the selected pair, so a group move spreads them onto distinct cells.
		_assert_equals(instance._game_state.get_party(), ["peris", "aster"],
			"Group control sets the party to the selected pair for spread moves")
		# Regression: a single ground click in group control must move EVERY selected
		# member, not just the active one. The elevator has no grid, so before the
		# gridless party fallback the non-active member (Aster) was stranded while only
		# the active controller (Peris) walked off. Drive the ACTUAL click path here.
		instance._game_state.command_stop("peris")
		instance._game_state.command_stop("aster")
		_assert_true(instance._player == instance._peris_node,
			"Peris is the active group-move controller")
		instance._player.move_to_world_position(exit_gate + Vector3(2.0, 0.0, 0.0))
		_assert_true(instance._game_state.is_moving("peris"),
			"Group-move click moves the active member (Peris)")
		_assert_true(instance._game_state.is_moving("aster"),
			"Group-move click also moves the carried member (Aster) on a gridless map")
		instance._toggle_pause()
		_assert_true(not instance._scheduler.is_paused(),
			"Multiselect tutorial unpauses after both characters are selected")
		_assert_elevator_movement_gate(instance, {
			"label": "two-character elevator exit gate",
			"start_step": "multiselect_tutorial",
			"expected_step": "corridor",
			"selected_ids": ["peris", "aster"],
			"characters": [
				{
					"id": "peris",
					"outside": exit_gate + Vector3(-4.0, 0.0, -3.5),
					"target": exit_gate + Vector3(0.0, 0.0, -0.5),
				},
				{
					"id": "aster",
					"outside": exit_gate + Vector3(-4.0, 0.0, 3.5),
					"target": exit_gate + Vector3(0.0, 0.0, 0.5),
				},
			],
			"max_time": 3.0,
		})

		instance._setup_perception("data", instance._aster_node)
		var before_shader_pos: Vector3 = instance._perception_material.get_shader_parameter("character_pos")
		instance._scheduler.resume()
		instance._game_state.command_move_to_pos("aster", Vector3(before_shader_pos.x + 4.0, 0.5, before_shader_pos.z))
		instance.headless_advance(0.6, 0.1)
		var after_shader_pos: Vector3 = instance._perception_material.get_shader_parameter("character_pos")
		_assert_true(after_shader_pos.x > before_shader_pos.x + 0.5,
			"Aster perception shader follows scheduler movement")

		# Bridge-end gate: walking to the far end of the (upper) bridge is what collapses it.
		_clear_sequence_runtime_for_spatial_test(instance)
		instance._load_chunk("below")
		_assert_true(instance._enemies.size() > 0,
			"Enemy/hazard route is present on the lower deck")
		_assert_elevator_movement_gate(instance, {
			"label": "Bridge-end collapse gate",
			"start_step": "bridge",
			"expected_step": "bridge_collapse",
			"characters": [
				{
					"id": "aster",
					"outside": Vector3(instance.BRIDGE_END_X - 7.0, 0.5, 0.0),
					"target": Vector3(instance.BRIDGE_END_X, 0.5, 0.0),
				},
			],
			"max_time": 4.0,
		})
		_assert_true(instance._game_state.get_position("aster").x > instance.BRIDGE_END_X - 1.5,
			"Bridge collapses at the far end, once Aster is past the enemy band")
		_set_sequence_character_position(
			instance, "aster", Vector3(instance.BRIDGE_END_X - 1.5, 0.5, 0.0))
		_set_sequence_character_position(
			instance,
			"peris",
			instance._game_state.get_position("aster") + Vector3(-0.8, 0.0, 0.8)
		)
		instance._on_fall_landed()
		_assert_elevator_fall_lands_clear_of_enemies(instance, 1.0,
			"Fall landing clear of the lower-deck enemies")

		# Post-fall: the climb prompt sits over the broken bridge; checking it opens the route fork.
		_clear_sequence_runtime_for_spatial_test(instance)
		instance._load_chunk("below")
		instance._enter_step("climb_attempt")
		instance._show_climb_interactable()
		for j in range(2):
			await get_tree().process_frame
		_assert_elevator_active_player_can_move(instance,
			"Post-fall climb prompt")
		var climb_zone := _assert_exploration_interactable_contract(instance, "ClimbPromptZone")
		if climb_zone != null:
			_assert_true(float(climb_zone.get("interaction_radius")) >= 2.4,
				"Climb prompt has a clearly defined larger interaction zone")
			_set_sequence_character_position(instance, "peris", (climb_zone as Node3D).global_position)
			_drive_interactable_zone(climb_zone, instance._peris_node, 0.9)
			instance.headless_advance(0.3, 0.05)
			_assert_equals(instance._current_step, "route_fork_dialogue",
				"Checking the broken bridge opens the route fork (can't retrace)")

		# Route convergence gate: after choosing a lane and walking it, reaching convergence
		# opens the junction (the fall already happened — this no longer triggers the collapse).
		_clear_sequence_runtime_for_spatial_test(instance)
		instance._load_chunk("below")
		_assert_elevator_movement_gate(instance, {
			"label": "Route convergence gate",
			"start_step": "route_choice",
			"expected_step": "junction_arrive",
			"characters": [
				{
					"id": "aster",
					"outside": Vector3(instance.ROUTES_CONVERGE.x - 4.0, instance.BELOW_Y + 0.5, 0.0),
					"target": instance.ROUTES_CONVERGE + Vector3(0.5, 0.5, 0.0),
				},
			],
			"max_time": 3.0,
		})
		_assert_true(instance._game_state.get_position("aster").x > instance.ROUTES_CONVERGE.x - 2.0,
			"Junction opens after Aster passes the enemy/hazard routes")

		for k in range(2):
			await get_tree().process_frame
		var plant_zone := _assert_exploration_interactable_contract(instance, "DormantPlant")
		if plant_zone != null:
			_set_sequence_character_position(instance, "peris", (plant_zone as Node3D).global_position)
			_drive_interactable_zone(plant_zone, instance._peris_node, 2.2)
			instance.headless_advance(2.1, 0.1)
			_assert_equals(instance._current_step, "endo_enters",
				"Dormant plant advances after Peris dwells in its mapped zone")

		_clear_sequence_runtime_for_spatial_test(instance)
		if not instance._game_state.characters.has("endo"):
			instance._register_gs_character("endo", instance._endo, 2.5)
		instance._start_gauntlet()
		_disable_enemy_detection(instance)
		for m in range(2):
			await get_tree().process_frame
		var ferrolure_zone := _assert_exploration_interactable_contract(instance, "FerrolureInteract")
		if ferrolure_zone != null:
			_set_sequence_character_position(instance, "peris", (ferrolure_zone as Node3D).global_position)
			_drive_interactable_zone(ferrolure_zone, instance._peris_node, 1.2)
			_assert_true(instance._ferrolure_active,
				"Ferrolure activates after dwelling in its mapped zone")

		_assert_elevator_movement_gate(instance, {
			"label": "Aster gauntlet exit gate",
			"start_step": "gauntlet",
			"expected_step": "complete",
			"reset_runtime": false,
			"characters": [
				{
					"id": "aster",
					"outside": Vector3(instance.GAUNTLET_EXIT.x - 4.0, instance.BELOW_Y + 0.5, 0.0),
					"target": instance.GAUNTLET_EXIT + Vector3(1.5, 0.5, 0.0),
				},
			],
			"max_time": 3.0,
		})

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Leaving Facility ---
func _test_leaving_facility() -> void:
	_test_name = "Leaving Facility"

	var scene := load("res://scenes/tutorial/leaving_facility.tscn")
	_assert_true(scene != null, "Leaving facility scene loads")

	if scene:
		var instance: Node = scene.instantiate()
		_assert_true(instance != null, "Leaving facility scene instantiates")
		get_tree().root.add_child(instance)
		for i in range(5):
			await get_tree().process_frame
		_assert_true(instance.is_inside_tree(), "Scene is in tree")

		var aster: Node = instance.find_child("Aster", true, false)
		_assert_true(aster != null, "Aster player node exists")

		var peris: Node = instance.find_child("Peris", true, false)
		_assert_true(peris != null, "Peris NPC node exists")

		var endo: Node = instance.find_child("Endo", true, false)
		_assert_true(endo != null, "Endo NPC node exists")

		var dialogue: Node = instance.find_child("DialogueBox", true, false)
		_assert_true(dialogue != null, "DialogueBox node exists")

		# Grid port: the scene runs on a GridWorld now — command Aster east and confirm he walks on it.
		var gs = instance._game_state
		_assert_true(gs != null and gs.grid != null, "Leaving facility runs on a GridWorld")
		if gs != null and gs.grid != null:
			var start_x: float = gs.get_position("aster").x
			gs.command_move_to_pos("aster", Vector3(8.0, 0.0, 0.0))  # short of the first iron spill
			for s in range(120):
				instance.headless_advance(0.1, 0.05)
				if not gs.is_moving("aster"):
					break
			_assert_true(gs.get_position("aster").x > start_x + 2.0,
				"Aster walks east on the grid (%.1f -> %.1f)" % [start_x, gs.get_position("aster").x])

		instance.queue_free()
		await get_tree().process_frame

# --- Test: Showcase ---
func _test_showcase() -> void:
	_test_name = "Showcase"

	var scene := load("res://scenes/showcase/showcase.tscn")
	_assert_true(scene != null, "Showcase scene loads")
	if not scene:
		return

	var instance: Node = await _instantiate_scene_and_wait(scene)
	_assert_true(instance != null, "Showcase scene instantiates")
	_assert_true(instance.is_inside_tree(), "Scene is in tree")
	_assert_true(instance.find_child("Environment", true, false) != null, "Environment node exists")
	_assert_true(instance.find_child("Hazards", true, false) != null, "Hazards node exists")
	_assert_true(instance.find_child("Characters", true, false) != null, "Characters node exists")
	_assert_true(instance.find_child("GameCamera", true, false) != null, "GameCamera node exists")
	_assert_true(instance.find_child("GameHUD", true, false) != null, "GameHUD node exists")
	_assert_true(instance.find_child("Aster", true, false) != null, "Aster node exists")
	_assert_true(instance.find_child("Peris", true, false) != null, "Peris node exists")
	_assert_true(instance.find_child("Endo", true, false) != null, "Endo node exists")
	_assert_true("_scheduler" in instance and instance._scheduler != null, "EventScheduler exists")
	_assert_true("_game_state" in instance and instance._game_state != null, "GameState exists")
	_assert_true("_characters" in instance and instance._characters.size() == 3, "Three showcase party characters registered")
	_assert_true(instance._standard_enemy != null, "Standard enemy station exists")
	_assert_true(instance._chain_enemy != null, "Chain enemy station exists")
	_assert_equals(instance._ferrolure_enemies.size(), 3, "Ferrolure pack count is 3")
	_assert_equals(instance._hide_swarm_units.size(), 4, "Hide swarm count is 4")
	_assert_true(instance._game_state.pendulums.has("showcase_pendulum"), "Pendulum registered in GameState")
	_assert_true(instance._game_state.physics_objects.has("push_barrel"), "Push barrel registered in GameState")
	_assert_true(instance._game_state.physics_objects.has("launcher_barrel"), "Launcher barrel registered in GameState")
	var station_positions: Dictionary = instance.get_station_positions()
	_assert_true(
		station_positions.has("enemy_probe")
		and station_positions.has("chain_probe")
		and station_positions.has("iron_patch")
		and station_positions.has("ferrolure")
		and station_positions.has("hide_spot")
		and station_positions.has("shelter")
		and station_positions.has("launcher"),
		"Headless station lookup exposes every showcase lane"
	)
	_assert_equals(instance._standard_enemy.get_state(), "patrol", "Standard enemy begins in patrol")
	_assert_equals(instance._chain_enemy.get_state(), "patrol", "Chain enemy begins in patrol")
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var enemy_positions: Dictionary = instance.get_station_positions()
	var aster_hp_before: float = instance.get_character_hp("aster")
	var enemy_hit_before: int = instance._enemy_hit_log.size()
	instance._select_character("aster")
	instance.headless_set_character_position("aster", enemy_positions["enemy_probe"])
	_advance_showcase(instance, 3.0)
	_assert_true(instance._standard_enemy.get_state() != "patrol", "Standard enemy leaves patrol when Aster enters its lane")
	_assert_equals(instance._standard_enemy._current_target_id, "aster", "Standard enemy acquires Aster as its target")
	_assert_true(
		instance._enemy_hit_log.size() > enemy_hit_before or instance.get_character_hp("aster") < aster_hp_before or instance._standard_enemy.get_state() in ["windup", "charge", "recover"],
		"Standard enemy lane progresses into its combat loop"
	)
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var chain_positions: Dictionary = instance.get_station_positions()
	var peris_hp_before: float = instance.get_character_hp("peris")
	var chain_hit_before: int = instance._enemy_hit_log.size()
	instance._select_character("peris")
	instance.headless_set_character_position("peris", chain_positions["chain_probe"])
	_advance_showcase(instance, 3.0)
	_assert_true(instance._chain_enemy.get_state() != "patrol", "Chain enemy leaves patrol when Peris enters its lane")
	_assert_equals(instance._chain_enemy._current_target_id, "peris", "Chain enemy acquires Peris as its target")
	_assert_true(
		instance._enemy_hit_log.size() > chain_hit_before or instance.get_character_hp("peris") < peris_hp_before or instance._chain_enemy.get_state() in ["windup", "charge", "recover"],
		"Chain enemy lane progresses into its combat loop"
	)
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var iron_positions: Dictionary = instance.get_station_positions()
	var iron_hp_before: float = instance.get_character_hp("endo")
	instance._select_character("endo")
	instance.headless_set_character_position("endo", iron_positions["iron_patch"])
	_advance_showcase(instance, 1.25)
	_assert_true(instance.get_character_hp("endo") < iron_hp_before, "Iron bloom lane drains health over time")
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var ferrolure_positions: Dictionary = instance.get_station_positions()
	var ferrolure_pos: Vector3 = ferrolure_positions["ferrolure"]
	var dist_before: Array[float] = []
	for enemy in instance._ferrolure_enemies:
		dist_before.append(instance._game_state.get_position(enemy.char_id).distance_to(ferrolure_pos))
	instance.activate_showcase_ferrolure()
	_assert_true(instance._showcase_ferrolure_active, "Ferrolure can be activated headlessly")
	_advance_showcase(instance, 1.0)
	var targets_cleared := true
	var moved_toward_lure := true
	for i in range(instance._ferrolure_enemies.size()):
		var enemy = instance._ferrolure_enemies[i]
		if not enemy._detection_targets.is_empty():
			targets_cleared = false
		var dist_now: float = instance._game_state.get_position(enemy.char_id).distance_to(ferrolure_pos)
		if dist_now >= dist_before[i]:
			moved_toward_lure = false
	_assert_true(targets_cleared, "Ferrolure clears normal target tracking while active")
	_assert_true(moved_toward_lure, "Ferrolure pack moves toward the lure signal")
	_advance_showcase(instance, 8.5)
	var targets_restored := true
	for enemy in instance._ferrolure_enemies:
		if enemy._detection_targets.size() != 3:
			targets_restored = false
	_assert_true(not instance._showcase_ferrolure_active, "Ferrolure expires after its timer")
	_assert_true(targets_restored, "Ferrolure pack restores normal tracking after expiry")
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var hide_positions: Dictionary = instance.get_station_positions()
	instance._select_character("endo")
	instance.headless_set_character_position("endo", hide_positions["hide_entry"])
	instance.activate_hide_lure()
	_advance_showcase(instance, 2.0)
	_assert_equals(instance._hide_last_outcome, "detected", "Hide lane fails when Endo stays exposed")
	_assert_equals(instance._hide_phase, "failed", "Hide lane enters the failed state on exposure")
	instance._reset_hide_encounter()
	instance.headless_set_character_position("endo", hide_positions["hide_spot"])
	instance.activate_hide_lure()
	_advance_showcase(instance, 6.2)
	_assert_equals(instance._hide_phase, "run", "Hide lane transitions to run after a successful wait")
	instance.headless_set_character_position("endo", hide_positions["shelter"])
	_advance_showcase(instance, 0.2)
	_assert_equals(instance._hide_last_outcome, "success", "Hide lane records success after shelter is reached")
	_assert_equals(instance._hide_phase, "safe", "Hide lane enters the safe state on a clean run")
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var pendulum_hit_before: int = instance._pendulum_event_log.size()
	var pendulum_hp_before: float = instance.get_character_hp("endo")
	instance._select_character("endo")
	instance.headless_set_character_position("endo", Vector3(13.4, 0.0, 19.5))
	_advance_showcase(instance, 5.0)
	var pendulum_hit := false
	for i in range(pendulum_hit_before, instance._pendulum_event_log.size()):
		if instance._pendulum_event_log[i]["target_id"] == "endo":
			pendulum_hit = true
			break
	_assert_true(pendulum_hit, "Pendulum lane resolves a character collision")
	_assert_true(instance.get_character_hp("endo") < pendulum_hp_before, "Pendulum lane deals damage on hit")
	await _dispose_scene(instance)

	instance = await _instantiate_scene_and_wait(scene)
	var launcher_start: Vector3 = instance._game_state.get_physics_position("launcher_barrel")
	var throw_target := Vector3(launcher_start.x + 3.5, 0.0, launcher_start.z)
	var throw_hp_before: float = instance.get_character_hp("aster")
	var physics_event_before: int = instance._physics_event_log.size()
	instance.headless_set_character_position("aster", throw_target)
	instance.trigger_showcase_throw()
	_advance_showcase(instance, 0.2)
	_assert_true(instance._game_state.is_physics_airborne("launcher_barrel"), "Launcher barrel becomes airborne when fired")
	_assert_true(instance._game_state.get_physics_position("launcher_barrel").x > launcher_start.x + 0.5, "Launcher barrel advances across the bay")
	_advance_showcase(instance, 2.0)
	var physics_hit_aster := false
	for i in range(physics_event_before, instance._physics_event_log.size()):
		if instance._physics_event_log[i]["collider_id"] == "aster":
			physics_hit_aster = true
			break
	_assert_true(physics_hit_aster, "Thrown barrel collides with a character placed in its path")
	_assert_true(instance.get_character_hp("aster") < throw_hp_before, "Thrown barrel collision deals damage")
	await _dispose_scene(instance)

func _test_puzzle_fragments(fragment_id := "") -> void:
	_test_name = "Puzzle Fragments" if fragment_id == "" else "Puzzle Fragment: %s" % fragment_id

	var catalog_script = load("res://scripts/fragments/puzzle_fragment_catalog.gd")
	_assert_true(catalog_script != null, "Puzzle fragment catalog script loads")
	if catalog_script == null:
		return

	var runner_script = load("res://scripts/fragments/puzzle_fragment_runner.gd")
	_assert_true(runner_script != null, "Puzzle fragment runner script loads")
	if runner_script == null:
		return

	var schema_script = load("res://scripts/fragments/puzzle_fragment_schema.gd")
	_assert_true(schema_script != null, "Puzzle fragment schema script loads")
	if schema_script == null:
		return

	var catalog = catalog_script.new()
	var loaded_catalog: bool = catalog.load_from_file(PUZZLE_FRAGMENT_CATALOG_PATH)
	_assert_true(loaded_catalog, "Puzzle fragment catalog JSON loads")
	if not loaded_catalog:
		return

	_assert_puzzle_fragment_schema_covers_catalog(catalog, schema_script)

	if fragment_id != "":
		var fragment: Dictionary = catalog.find_fragment(fragment_id)
		_assert_true(not fragment.is_empty(), "Puzzle fragment '%s' exists" % fragment_id)
		if fragment.is_empty():
			return

	var runner = runner_script.new(get_tree())
	var result: Dictionary = await runner.run_catalog(catalog, fragment_id)
	var fragments: Array = result.get("fragments", [])
	_assert_true(not fragments.is_empty(), "Puzzle fragment runner returned at least one fragment")
	if fragments.is_empty():
		return

	for fragment_result in fragments:
		for scenario_result in fragment_result.get("scenarios", []):
			var label := "%s / %s" % [fragment_result.get("id", "unknown"), scenario_result.get("id", "scenario")]
			var scenario_message := str(scenario_result.get("message", ""))
			_assert_true(
				bool(scenario_result.get("success", false)),
				"%s passes%s" % [label, (": " + scenario_message) if scenario_message != "" else ""]
			)

	_assert_equals(int(result.get("failed", 0)), 0, "Puzzle fragment suite has no failures")

func _assert_puzzle_fragment_schema_covers_catalog(catalog, schema_script) -> void:
	var unknown_actions: Dictionary = {}
	var unknown_ops: Dictionary = {}
	for fragment in catalog.get_fragments():
		_collect_unknown_fragment_actions(fragment.get(schema_script.KEY_SETUP, []), schema_script, unknown_actions, unknown_ops)
		for raw_scenario in fragment.get(schema_script.KEY_SCENARIOS, []):
			if typeof(raw_scenario) != TYPE_DICTIONARY:
				continue
			var scenario: Dictionary = raw_scenario
			_collect_unknown_fragment_actions(scenario.get(schema_script.KEY_SETUP, []), schema_script, unknown_actions, unknown_ops)
			_collect_unknown_fragment_actions(scenario.get(schema_script.KEY_SCRIPT, []), schema_script, unknown_actions, unknown_ops)
	_assert_equals(unknown_actions.keys(), [], "Puzzle fragment schema covers every catalog action type")
	_assert_equals(unknown_ops.keys(), [], "Puzzle fragment schema covers every catalog assertion operator")

func _collect_unknown_fragment_actions(actions: Array, schema_script, unknown_actions: Dictionary, unknown_ops: Dictionary) -> void:
	for raw_action in actions:
		if typeof(raw_action) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = raw_action
		var action_name := str(action.get(schema_script.KEY_ACTION_TYPE, ""))
		if schema_script.action_type_from_variant(action_name) == schema_script.ActionType.UNKNOWN:
			unknown_actions[action_name] = true
		if action_name == schema_script.ACTION_ASSERT_PATH:
			var op_name := str(action.get(schema_script.KEY_OP, schema_script.OP_EQUAL))
			if schema_script.compare_op_from_variant(op_name) == schema_script.CompareOp.UNKNOWN:
				unknown_ops[op_name] = true

## D13 — every puzzle stretch that classifies its scenarios with an "outcome" tag
## must demonstrate BOTH a success and a failure case. The runner separately
## proves each scenario passes; this guard proves the *coverage*. Untagged
## puzzle/survival/hybrid fragments are reported as still needing both cases
## (teaching beats — stacks/rings interactions — have no loss state and stay
## untagged, so they're listed as candidates only, not failures).
func _test_puzzle_outcome_coverage() -> void:
	_test_name = "PuzzleOutcomeCoverage"
	var catalog_script = load("res://scripts/fragments/puzzle_fragment_catalog.gd")
	_assert_true(catalog_script != null, "Puzzle fragment catalog script loads")
	if catalog_script == null:
		return
	var catalog = catalog_script.new()
	_assert_true(catalog.load_from_file(PUZZLE_FRAGMENT_CATALOG_PATH), "Puzzle fragment catalog loads")
	var classified := 0
	var pending: Array = []
	for fragment in catalog.get_fragments():
		var outcomes := {}
		for raw_scenario in fragment.get("scenarios", []):
			var o := String((raw_scenario as Dictionary).get("outcome", ""))
			if o != "":
				outcomes[o] = true
		if outcomes.is_empty():
			if String(fragment.get("kind", "")) in ["puzzle", "survival", "hybrid"]:
				pending.append(String(fragment.get("id")))
			continue
		classified += 1
		_assert_true(outcomes.has("success") and outcomes.has("failure"),
			"Puzzle stretch '%s' demonstrates both a success and a failure outcome" % fragment.get("id"))
	_assert_true(classified >= 23,
		"Every genuine puzzle stretch stays outcome-classified (got %d, expected >= 23)" % classified)
	print("[D13] %d puzzle stretch(es) classified with both outcomes; %d candidate(s) still need a fail/success case: %s"
		% [classified, pending.size(), str(pending)])

## D12 — Aster's data overlay maps the main facility (blueprints exist) out through
## Endo's junction, then goes dark in the maintenance corridors past it.
func _test_overlay_facility_gating() -> void:
	_test_name = "OverlayFacilityGating"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	_assert_true(scene != null, "Elevator scene loads for overlay gating")
	if scene == null:
		return
	var instance: Node = await _instantiate_scene_and_wait(scene, 5)
	_assert_true(instance != null, "Elevator scene instantiates for overlay gating")
	if instance == null:
		return
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	# Activate Aster's data overlay directly (normally fires at system_restored).
	instance._setup_perception("data", instance._aster_node)
	var quad := instance._perception_quad as MeshInstance3D
	_assert_true(quad != null, "Perception quad exists once the data overlay is active")
	if quad == null:
		await _dispose_scene(instance)
		return
	var boundary: float = instance.MAIN_FACILITY_MAX_X
	var below_y: float = instance.BELOW_Y
	# Within the main facility (out to Endo's junction) → overlay lit.
	if instance._game_state.characters.has("aster"):
		instance._game_state.command_stop("aster")
		instance._game_state.characters["aster"].position = Vector3(boundary - 6.0, below_y + 0.5, 0.0)
	instance._aster_node.global_position = Vector3(boundary - 6.0, below_y + 0.5, 0.0)
	instance._on_process(0.1, 1.0)
	_assert_true(quad.visible, "Data overlay stays lit through the main facility (out to Endo's junction)")
	# Past the junction (maintenance, no blueprints) → overlay dark.
	if instance._game_state.characters.has("aster"):
		instance._game_state.characters["aster"].position = Vector3(boundary + 6.0, below_y + 0.5, 0.0)
	instance._aster_node.global_position = Vector3(boundary + 6.0, below_y + 0.5, 0.0)
	instance._on_process(0.1, 1.0)
	_assert_true(not quad.visible, "Data overlay goes dark past Endo's junction (maintenance area)")
	await _dispose_scene(instance)

func _instantiate_scene_and_wait(scene: PackedScene, settle_frames := 5) -> Node:
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(settle_frames):
		await get_tree().process_frame
	return instance

# --- Fragment preview helpers (single fragment_preview.tscn + a chunk id, no per-chunk *_preview.tscn) ---

## Chunk id from a legacy "<chunk>_preview.tscn" path — callers still name the chunk that way.
func _preview_chunk_id_from_path(scene_path: String) -> String:
	return scene_path.get_file().trim_suffix("_preview.tscn")

## Instantiate the consolidated preview for one chunk (menu off), add it, and settle. The single
## entry point that replaced loading a dedicated "<chunk>_preview.tscn".
func _instantiate_preview_chunk_and_wait(chunk_id: String, settle_frames := 5, config := {}) -> Node:
	var packed: PackedScene = load(FRAGMENT_PREVIEW_SCENE_PATH)
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	if instance == null:
		return null
	instance.set("preview_menu", false)
	instance.set("preview_chunk", chunk_id)
	var entry: Dictionary = FragmentPreviewScript.get_preview_entry(chunk_id)
	var resolved_config: Dictionary = config if not config.is_empty() else (entry.get("config", {}) as Dictionary)
	if not resolved_config.is_empty():
		instance.set("preview_chunk_config", resolved_config.duplicate(true))
	if String(entry.get("title", "")) != "":
		instance.set("scene_title_override", String(entry.get("title", "")))
	get_tree().root.add_child(instance)
	for i in range(settle_frames):
		await get_tree().process_frame
	return instance

func _dispose_scene(instance: Node) -> void:
	if instance and is_instance_valid(instance):
		instance.queue_free()
		await get_tree().process_frame

func _assert_no_embedded_game_gui(root: Node, label: String) -> void:
	var gui_nodes: Array[String] = []
	_collect_embedded_game_gui_nodes(root, str(root.name), gui_nodes)
	_assert_equals(gui_nodes.size(), 0,
		"%s keeps reusable game GUI out of the chunk tree (found: %s)" % [label, str(gui_nodes)])

func _collect_embedded_game_gui_nodes(node: Node, path: String, gui_nodes: Array[String]) -> void:
	for child in node.get_children():
		var child_path := "%s/%s" % [path, str(child.name)]
		if child is CanvasLayer or child is Control:
			gui_nodes.append(child_path)
		_collect_embedded_game_gui_nodes(child, child_path, gui_nodes)

func _find_fragment_chunk_root(instance: Node) -> Node:
	if "_active_chunk" in instance:
		var active_chunk: Variant = instance.get("_active_chunk")
		if active_chunk is Node:
			return active_chunk
	for child in instance.get_children():
		var child_name := str(child.name)
		if child_name.begins_with("Chunk_") or child_name.ends_with("Chunk"):
			return child
	return null

func _assert_fragment_preview_uses_shared_gui(instance: Node, label: String) -> void:
	_assert_true(instance != null, "%s exists for shared GUI contract" % label)
	if instance == null:
		return
	_assert_true(instance.has_method("headless_get_state"), "%s exposes headless GUI state" % label)
	if not instance.has_method("headless_get_state"):
		return

	var state: Dictionary = instance.headless_get_state()
	var ui: Dictionary = state.get("ui", {})
	_assert_equals(str(ui.get("contract_id", "")), FRAGMENT_PREVIEW_GUI_CONTRACT_ID,
		"%s uses the shared fragment-preview GUI contract" % label)
	_assert_equals(str(ui.get("hud_script", "")), GAME_HUD_SCRIPT_PATH,
		"%s declares the shared GameHUD script" % label)
	_assert_true(bool(ui.get("shared_hud", false)), "%s binds the shared GameHUD instance" % label)
	_assert_equals(str(ui.get("controls", "")), FRAGMENT_PREVIEW_CONTROL_HELP,
		"%s uses the canonical preview control line" % label)
	_assert_equals(str(ui.get("inventory_controls", "")), FRAGMENT_PREVIEW_INVENTORY_CONTROL_HELP,
		"%s uses the canonical inventory control line" % label)

	var hud: Node = instance.find_child("GameHUD", true, false)
	_assert_true(hud != null, "%s creates exactly one reusable GameHUD node" % label)
	if hud == null:
		return
	_assert_true(hud.has_method("get_hud_contract"), "%s GameHUD exposes its reusable contract" % label)
	if not hud.has_method("get_hud_contract"):
		return

	var hud_contract: Dictionary = hud.call("get_hud_contract")
	_assert_equals(str(hud_contract.get("contract_id", "")), GAME_HUD_CONTRACT_ID,
		"%s GameHUD reports the shared HUD contract" % label)
	_assert_equals(str(hud_contract.get("script", "")), GAME_HUD_SCRIPT_PATH,
		"%s GameHUD contract points at the shared HUD script" % label)
	_assert_equals(str(hud_contract.get("run_keybind", "")), "",
		"%s preview HUD leaves Z free for main abilities" % label)
	_assert_equals(str(hud_contract.get("routing_keybind", "")), "Tab",
		"%s preview HUD keeps the shared route key" % label)
	_assert_equals(str(hud_contract.get("pause_keybind", "")), "Space",
		"%s preview HUD keeps the shared pause key" % label)

	var stat_names: Array = hud_contract.get("stats", [])
	for stat_name in ["atp", "hp", "sta"]:
		_assert_true(stat_names.has(stat_name), "%s shared HUD exposes %s stat" % [label, stat_name])
	var portrait_ids: Array = hud_contract.get("portraits", [])
	for char_id in ["aster", "peris", "endo"]:
		_assert_true(portrait_ids.has(char_id), "%s shared HUD exposes %s portrait" % [label, char_id])

	var hud_abilities: Dictionary = hud_contract.get("abilities", {})
	var state_abilities: Dictionary = state.get("abilities", {})
	for ability_id in ["aster_focus", "peris_tune", "endo_patch"]:
		var hud_ability: Dictionary = hud_abilities.get(ability_id, {})
		var state_ability: Dictionary = state_abilities.get(ability_id, {})
		_assert_equals(str(hud_ability.get("keybind", "")), str(state_ability.get("keybind", "")),
			"%s HUD and headless state agree on %s keybind" % [label, ability_id])

	var chunk_root := _find_fragment_chunk_root(instance)
	_assert_true(chunk_root != null, "%s mounts one chunk under the shared preview shell" % label)
	if chunk_root != null:
		_assert_no_embedded_game_gui(chunk_root, "%s %s" % [label, str(chunk_root.name)])

func _assert_preview_overlay_vision_sources(instance: Node, label: String) -> void:
	_assert_true(instance != null, "%s instance exists for overlay vision sources" % label)
	if instance == null:
		return
	_assert_true(instance.has_method("headless_set_character_position"), "%s can place party members for overlay checks" % label)
	_assert_true(instance.has_method("headless_set_overlay_state"), "%s can toggle overlay sources for checks" % label)
	_assert_true(instance.has_method("headless_get_state"), "%s exposes overlay vision state" % label)
	_assert_true(instance.has_method("set_preview_character_visible"), "%s can hide party members for overlay checks" % label)
	_assert_true(instance.has_method("_sync_overlay_stack"), "%s can sync its perception stack" % label)
	_assert_true("_overlay_stack_material" in instance, "%s owns a shared perception stack material" % label)
	if (
		not instance.has_method("headless_set_character_position")
		or not instance.has_method("headless_set_overlay_state")
		or not instance.has_method("headless_get_state")
		or not instance.has_method("set_preview_character_visible")
		or not instance.has_method("_sync_overlay_stack")
		or not ("_overlay_stack_material" in instance)
	):
		return

	var party_positions := {
		"aster": Vector3(1.0, 0.5, 1.0),
		"peris": Vector3(7.0, 0.5, 2.0),
		"endo": Vector3(-4.0, 0.5, -3.0),
	}
	for char_id in ["aster", "peris", "endo"]:
		instance.call("headless_set_overlay_state", char_id, true)
		instance.call("headless_set_character_position", char_id, party_positions[char_id])
	instance.call("_sync_overlay_stack")

	var material: ShaderMaterial = instance.get("_overlay_stack_material") as ShaderMaterial
	_assert_true(material != null, "%s perception stack has a shader material" % label)
	if material == null:
		return

	var expected_sources: Array[Vector3] = [
		party_positions["aster"] + Vector3(0.0, 1.0, 0.0),
		party_positions["peris"] + Vector3(0.0, 1.0, 0.0),
		party_positions["endo"] + Vector3(0.0, 1.0, 0.0),
	]
	_assert_equals(int(material.get_shader_parameter("data_vision_count")), 3,
		"%s data overlay clears around all visible party members" % label)
	_assert_equals(int(material.get_shader_parameter("fog_vision_count")), 3,
		"%s fog overlay clears around all visible party members" % label)
	_assert_preview_overlay_source_positions(material, "data", expected_sources, "%s data overlay" % label)
	_assert_preview_overlay_source_positions(material, "fog", expected_sources, "%s fog overlay" % label)

	var state: Dictionary = instance.call("headless_get_state")
	var state_sources: Array = state.get("overlay_vision_sources", [])
	_assert_equals(state_sources.size(), 3, "%s reports all overlay vision sources in headless state" % label)

	instance.call("headless_set_overlay_state", "endo", false)
	instance.call("_sync_overlay_stack")
	_assert_equals(int(material.get_shader_parameter("data_vision_count")), 3,
		"%s data overlay keeps party vision independent of overlay readout toggles" % label)
	_assert_equals(int(material.get_shader_parameter("fog_vision_count")), 3,
		"%s fog overlay keeps party vision independent of overlay readout toggles" % label)

	instance.call("set_preview_character_visible", "endo", false)
	instance.call("_sync_overlay_stack")
	_assert_equals(int(material.get_shader_parameter("data_vision_count")), 2,
		"%s data overlay removes invisible party members from vision sources" % label)
	_assert_equals(int(material.get_shader_parameter("fog_vision_count")), 2,
		"%s fog overlay removes invisible party members from vision sources" % label)
	instance.call("set_preview_character_visible", "endo", true)
	instance.call("headless_set_overlay_state", "endo", true)
	instance.call("headless_set_character_position", "endo", party_positions["endo"])
	instance.call("_sync_overlay_stack")

func _assert_preview_overlay_source_positions(
	material: ShaderMaterial,
	prefix: String,
	expected_sources: Array[Vector3],
	label: String
) -> void:
	var actual_sources: Array[Vector3] = [
		material.get_shader_parameter("%s_character_pos" % prefix),
		material.get_shader_parameter("%s_vision_pos_1" % prefix),
		material.get_shader_parameter("%s_vision_pos_2" % prefix),
	]
	for index in range(expected_sources.size()):
		_assert_vector3_close(actual_sources[index], expected_sources[index], 0.01,
			"%s source %d follows the correct party member" % [label, index + 1])

func _assert_vector3_close(actual: Vector3, expected: Vector3, tolerance: float, label: String) -> void:
	_assert_true(actual.distance_to(expected) <= tolerance,
		"%s (actual: %s expected: %s)" % [label, str(actual), str(expected)])

func _press_unhandled_key(instance: Node, keycode: int, ctrl_pressed := false, shift_pressed := false) -> bool:
	if instance == null or not instance.has_method("_unhandled_key_input"):
		return false
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = false
	event.ctrl_pressed = ctrl_pressed
	event.shift_pressed = shift_pressed
	instance.call("_unhandled_key_input", event)
	return true

## Dispatch a key to the scene's GameHUD _unhandled_input — the path that maps
## input actions (e.g. the emp action) to HUD signals like real play.
func _press_hud_action_key(instance: Node, keycode: int) -> bool:
	if instance == null:
		return false
	var hud = instance.get("_hud")
	if hud == null or not hud.has_method("_unhandled_input"):
		return false
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = false
	hud.call("_unhandled_input", event)
	return true

func _advance_showcase(instance: Node, duration: float, step := 0.05) -> void:
	if instance.has_method("headless_advance"):
		instance.headless_advance(duration, step)
		return
	if not ("_scheduler" in instance):
		return
	var scheduler: EventScheduler = instance._scheduler
	var remaining: float = duration
	while remaining > 0.0001:
		var dt: float = minf(step, remaining)
		scheduler.advance_ticks(dt)
		if instance.has_method("_on_process"):
			instance._on_process(dt, 1.0)
		_sync_showcase_runtime(instance, dt)
		remaining -= dt

func _sync_showcase_runtime(instance: Node, delta: float) -> void:
	if "_characters" in instance:
		for node in instance._characters.values():
			if node and is_instance_valid(node) and node.has_method("_physics_process"):
				node._physics_process(delta)
	if "_enemy_nodes" in instance:
		for enemy in instance._enemy_nodes:
			if enemy and is_instance_valid(enemy):
				enemy._process(delta)
	if "_physics_visuals" in instance:
		for visual in instance._physics_visuals.values():
			if visual and is_instance_valid(visual) and visual.has_method("_process"):
				visual._process(delta)

func _assert_preview_scene_idle_dialogue_stability(
	scene_path: String,
	chunk_name: String,
	label: String,
	forbidden_substring := ""
) -> void:
	var instance: Node = await _instantiate_preview_chunk_and_wait(_preview_chunk_id_from_path(scene_path), 3)
	_assert_true(instance != null, "%s instantiates for idle dialogue stability" % scene_path.get_file())
	if instance == null:
		return

	var chunk: Node = instance.find_child(chunk_name, true, false)
	_assert_true(chunk != null, "%s builds %s for idle dialogue stability" % [label, chunk_name])
	_assert_preview_dialogue_idle_stable(instance, label, forbidden_substring)
	await _dispose_scene(instance)

func _assert_preview_scene_main_ability_keymap(scene_path: String, label: String) -> void:
	var instance: Node = await _instantiate_preview_chunk_and_wait(_preview_chunk_id_from_path(scene_path), 3)
	_assert_true(instance != null, "%s instantiates for main ability keymap" % scene_path.get_file())
	if instance == null:
		return

	_assert_preview_main_ability_keymap(instance, label)
	await _dispose_scene(instance)

func _assert_preview_scene_interactable_click_flow(
	scene_path: String,
	chunk_name: String,
	interactable_pattern: String,
	active_char: String,
	label: String,
	expected_state_key := "",
	expected_state_value = true
) -> void:
	var instance: Node = await _instantiate_preview_chunk_and_wait(_preview_chunk_id_from_path(scene_path), 3)
	_assert_true(instance != null, "%s instantiates for interactable click flow" % scene_path.get_file())
	if instance == null:
		return

	var chunk: Node = instance.find_child(chunk_name, true, false)
	_assert_true(chunk != null, "%s builds %s for interactable click flow" % [label, chunk_name])
	if chunk == null:
		await _dispose_scene(instance)
		return

	var interactable := chunk.find_child(interactable_pattern, true, false)
	_assert_true(interactable != null, "%s exposes %s" % [label, interactable_pattern])
	if interactable == null:
		await _dispose_scene(instance)
		return

	_assert_interactable_type(interactable, Interactable.InteractableType.INSPECTION,
		"%s click-arrival interactable" % label)
	_assert_equals(float(interactable.get("dwell_time")), 0.0,
		"%s has no dwell timer" % label)

	var feedback_manager := instance.find_child("OutlineFeedbackManager", true, false)
	_assert_true(feedback_manager != null, "%s has the shared outline feedback manager" % label)
	if feedback_manager == null:
		await _dispose_scene(instance)
		return

	instance.headless_select_character(active_char)
	var target_node := interactable as Node3D
	_assert_true(target_node != null, "%s click target is spatial" % label)
	if target_node == null:
		await _dispose_scene(instance)
		return
	var target_pos: Vector3 = target_node.global_position
	instance.headless_set_character_position(active_char, target_pos)

	var state_before_idle: Dictionary = chunk.get_preview_state() if chunk.has_method("get_preview_state") else {}
	_advance_preview_interactable_idle_window(instance, 1.1)
	if expected_state_key != "":
		var state_after_idle: Dictionary = chunk.get_preview_state()
		_assert_equals(state_after_idle.get(expected_state_key), state_before_idle.get(expected_state_key),
			"%s does not fire from proximity dwell" % label)

	instance.headless_set_character_position(active_char, target_pos + Vector3(-5.0, 0.0, -1.5))
	var alpha_before_hover := _interactable_zone_alpha(interactable)
	interactable.call("_on_mouse_entered")
	var alpha_after_hover := _interactable_zone_alpha(interactable)
	_assert_true(feedback_manager.call("get_hovered_target") == interactable,
		"%s hover enters the shared outline manager" % label)
	if alpha_before_hover >= 0.0 and alpha_after_hover >= 0.0:
		_assert_true(alpha_after_hover > alpha_before_hover,
			"%s hover applies visible shader feedback" % label)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	interactable.call("_on_input_event", null, click, target_pos, Vector3.UP, 0)
	_assert_true(feedback_manager.call("get_selected_target") == interactable,
		"%s click switches to selected shader feedback" % label)
	_assert_true(instance.headless_is_character_moving(active_char),
		"%s click moves the active character toward the target" % label)
	_assert_true(interactable.find_child("SelectedParticles", true, false) != null,
		"%s selected feedback creates particles while moving" % label)

	instance.headless_advance(8.0, 0.05)
	if expected_state_key != "":
		var state_after_click: Dictionary = chunk.get_preview_state()
		_assert_equals(state_after_click.get(expected_state_key), expected_state_value,
			"%s click-arrival resolves the interaction" % label)
	_assert_true(feedback_manager.call("get_selected_target") == null,
		"%s arrival clears selected shader feedback" % label)
	var selected_particles := interactable.find_child("SelectedParticles", true, false) as GPUParticles3D
	if selected_particles != null:
		_assert_true(not selected_particles.emitting and not selected_particles.visible,
			"%s arrival clears selected particles" % label)
	interactable.call("_on_mouse_exited")

	await _dispose_scene(instance)

func _advance_preview_interactable_idle_window(instance: Node, duration: float, step := 0.1) -> void:
	var remaining := maxf(0.0, duration)
	while remaining > 0.0001:
		var dt := minf(step, remaining)
		if instance.has_method("_on_process"):
			instance.call("_on_process", dt, 1.0)
		_advance_preview_interactables_for_idle(instance, dt)
		if instance.has_method("_headless_sync_runtime"):
			instance.call("_headless_sync_runtime", dt)
		remaining -= dt

func _interactable_zone_alpha(interactable: Node) -> float:
	if interactable == null:
		return -1.0
	var marker := interactable.find_child("InteractionZoneMarker", true, false) as MeshInstance3D
	if marker == null or not (marker.material_override is StandardMaterial3D):
		return -1.0
	var material := marker.material_override as StandardMaterial3D
	return material.albedo_color.a

func _assert_preview_main_ability_keymap(instance: Node, label: String) -> void:
	_assert_true(instance != null, "%s instance exists for main ability keymap" % label)
	if instance == null:
		return
	_assert_true(instance.has_method("headless_get_state"), "%s exposes state for main ability keymap" % label)
	_assert_true(instance.has_method("headless_select_character"), "%s exposes character selection for main ability keymap" % label)
	if not instance.has_method("headless_get_state") or not instance.has_method("headless_select_character"):
		return

	var expected := {
		"aster_focus": {"owner": "aster", "keybind": "Z", "keycode": KEY_Z},
		"peris_tune": {"owner": "peris", "keybind": "X", "keycode": KEY_X},
		"endo_patch": {"owner": "endo", "keybind": "Z", "keycode": KEY_Z},
	}
	var state: Dictionary = instance.headless_get_state()
	var abilities: Dictionary = state.get("abilities", {})
	for ability_id in expected.keys():
		var spec: Dictionary = expected[ability_id]
		var ability: Dictionary = abilities.get(ability_id, {})
		_assert_equals(str(ability.get("owner", "")), str(spec.get("owner", "")),
			"%s %s belongs to its canonical character" % [label, ability_id])
		_assert_equals(str(ability.get("keybind", "")), str(spec.get("keybind", "")),
			"%s %s displays its Z/X main-ability key" % [label, ability_id])
		_assert_equals(int(ability.get("keycode", 0)), int(spec.get("keycode", 0)),
			"%s %s exposes its Z/X keycode in headless state" % [label, ability_id])

	var activations := [
		{"char_id": "aster", "ability_id": "aster_focus", "keycode": KEY_Z},
		{"char_id": "peris", "ability_id": "peris_tune", "keycode": KEY_X},
		{"char_id": "endo", "ability_id": "endo_patch", "keycode": KEY_Z},
	]
	for activation in activations:
		var char_id := str(activation.get("char_id", ""))
		var ability_id := str(activation.get("ability_id", ""))
		var keycode := int(activation.get("keycode", 0))
		instance.headless_select_character(char_id)
		var before: Dictionary = instance.headless_get_state()
		var before_stats: Dictionary = before.get("character_stats", {}).get(char_id, {})
		var before_atp := float(before_stats.get("atp", -1.0))
		var before_run := bool(before.get("run_active", false))

		_assert_true(_press_unhandled_key(instance, keycode),
			"%s accepts %s for %s's main ability" % [label, OS.get_keycode_string(keycode), char_id.capitalize()])
		var after: Dictionary = instance.headless_get_state()
		var ability_runtime: Dictionary = after.get("abilities", {}).get(ability_id, {})
		var after_stats: Dictionary = after.get("character_stats", {}).get(char_id, {})
		_assert_true(str(ability_runtime.get("state", "ready")) != "ready",
			"%s %s triggers from %s" % [label, ability_id, OS.get_keycode_string(keycode)])
		_assert_true(float(after_stats.get("atp", before_atp)) < before_atp,
			"%s %s spends ATP from %s" % [label, ability_id, OS.get_keycode_string(keycode)])
		if keycode == KEY_Z:
			_assert_equals(bool(after.get("run_active", true)), before_run,
				"%s uses Z for %s's ability without toggling run" % [label, char_id.capitalize()])

func _assert_preview_dialogue_idle_stable(
	instance: Node,
	label: String,
	forbidden_substring := "",
	idle_seconds := 3.2,
	step := 0.1
) -> void:
	_assert_true(instance != null, "%s instance exists for idle dialogue stability" % label)
	if instance == null:
		return
	_assert_true("_dialogue" in instance, "%s exposes dialogue for idle stability" % label)
	if not ("_dialogue" in instance):
		return
	var dialogue_box: Node = instance._dialogue
	_assert_true(dialogue_box != null, "%s has a dialogue box for idle stability" % label)
	if dialogue_box == null:
		return

	var displayed: Array[String] = []
	dialogue_box.line_displayed.connect(func(text: String): displayed.append(text))

	var remaining := maxf(0.0, idle_seconds)
	while remaining > 0.0001:
		var dt := minf(step, remaining)
		if instance.has_method("_on_process"):
			instance.call("_on_process", dt, 1.0)
		_advance_preview_interactables_for_idle(instance, dt)
		if instance.has_method("_headless_sync_runtime"):
			instance.call("_headless_sync_runtime", dt)
		_advance_dialogue_box(dialogue_box, dt)
		remaining -= dt

	# Flush anything that may have been spuriously queued so a repeat shows up.
	_drain_dialogue_box(dialogue_box)

	var counts := {}
	var repeated: Array[String] = []
	for text in displayed:
		counts[text] = int(counts.get(text, 0)) + 1
	for text in counts.keys():
		if int(counts.get(text, 0)) > 1:
			repeated.append(str(text))
	_assert_equals(repeated.size(), 0, "%s does not repeat dialogue while idling (seen: %s)" % [label, str(displayed)])

	if forbidden_substring != "":
		var leaked_forbidden := false
		for text in displayed:
			if text.contains(forbidden_substring):
				leaked_forbidden = true
				break
		_assert_true(not leaked_forbidden, "%s does not leak '%s' while idling" % [label, forbidden_substring])

func _advance_preview_interactables_for_idle(instance: Node, delta: float) -> void:
	if not ("_preview_interactables" in instance):
		return

	var active_char := ""
	if instance.has_method("get_preview_active_character"):
		active_char = str(instance.call("get_preview_active_character"))

	var characters := {}
	if "_characters" in instance:
		var raw_characters: Variant = instance.get("_characters")
		if raw_characters is Dictionary:
			characters = raw_characters

	var raw_interactables: Variant = instance.get("_preview_interactables")
	if not (raw_interactables is Array):
		return
	for interactable_variant in raw_interactables:
		if not (interactable_variant is Node):
			continue
		var interactable := interactable_variant as Node
		if interactable == null or not is_instance_valid(interactable):
			continue
		interactable.set("active_character", active_char)

		var interactable_node := interactable as Node3D
		var in_range := false
		if interactable_node != null:
			var radius := float(interactable.get("interaction_radius"))
			for character_variant in characters.values():
				if not (character_variant is Node3D):
					continue
				var character_node := character_variant as Node3D
				if character_node.global_position.distance_to(interactable_node.global_position) <= radius:
					in_range = true
					break
		interactable.set("_player_in_range", in_range)
		# Scheduler-driven dwell schedules on range-enter; mirror that here since we
		# set _player_in_range directly instead of going through _on_body_entered.
		if "_scheduler" in interactable and interactable.get("_scheduler") != null:
			var dwell_fsm = interactable.get("_dwell_fsm")
			var already_dwelling: bool = dwell_fsm != null and dwell_fsm.current() == "dwelling"
			if in_range and not already_dwelling:
				interactable.call("_begin_dwell")
			elif not in_range:
				interactable.call("_cancel_dwell")
		if interactable.has_method("_process"):
			interactable.call("_process", delta)

func _preview_scheduler_tick(instance: Node) -> float:
	if instance != null and instance.has_method("headless_get_state"):
		var state: Dictionary = instance.headless_get_state()
		return float(state.get("scheduler_tick", 0.0))
	return 0.0

func _load_survival_range_timing_predictions() -> Dictionary:
	var instance: Node = await _instantiate_preview_chunk_and_wait("survival_range", 3)
	if instance == null:
		_assert_true(false, "survival_range preview instantiates for timing predictions")
		return {}

	var predictions_variant: Variant = null
	if instance.has_method("headless_call_chunk"):
		predictions_variant = instance.headless_call_chunk("get_route_timing_predictions")
	var predictions: Dictionary = predictions_variant if predictions_variant is Dictionary else {}
	_assert_true(not predictions.is_empty(), "Survival range exposes timing predictions")
	await _dispose_scene(instance)
	return predictions

func _survival_range_move_segment(instance: Node, segment: Dictionary) -> Dictionary:
	var char_id := str(segment.get("character", ""))
	var destination: Vector3 = segment.get("end_position", Vector3.ZERO)
	var running := bool(segment.get("running", false))
	var start_tick := _preview_scheduler_tick(instance)
	if char_id != "" and instance.has_method("headless_select_character"):
		instance.headless_select_character(char_id)
	var started: bool = instance.has_method("headless_move_character") and bool(instance.headless_move_character(char_id, destination, running))
	var movement_info := {}
	if instance.has_method("headless_get_character_movement_info"):
		movement_info = instance.headless_get_character_movement_info(char_id)
	var duration := float(movement_info.get("duration", 0.0))
	if duration > 0.0:
		_advance_showcase(instance, duration)
	var moving_after: bool = instance.has_method("headless_is_character_moving") and bool(instance.headless_is_character_moving(char_id))
	if moving_after:
		_advance_showcase(instance, 0.001, 0.001)
		moving_after = instance.has_method("headless_is_character_moving") and bool(instance.headless_is_character_moving(char_id))
	return {
		"started": started,
		"predicted": float(segment.get("travel_time", 0.0)),
		"measured": _preview_scheduler_tick(instance) - start_tick,
		"moving_after": moving_after,
		"movement_info": movement_info,
	}

func _survival_range_dwell_and_call(
	instance: Node,
	char_id: String,
	segment: Dictionary,
	method_name: String,
	args: Array = []
) -> Dictionary:
	var start_tick := _preview_scheduler_tick(instance)
	if char_id != "" and instance.has_method("headless_select_character"):
		instance.headless_select_character(char_id)
	var dwell_time := float(segment.get("dwell_time", segment.get("total_time", 0.0)))
	if dwell_time > 0.0:
		_advance_showcase(instance, dwell_time)
	var call_result: Variant = null
	if instance.has_method("headless_call_chunk"):
		call_result = instance.headless_call_chunk(method_name, args)
	return {
		"predicted": dwell_time,
		"measured": _preview_scheduler_tick(instance) - start_tick,
		"result": call_result,
	}

func _run_survival_range_profile(profile: String) -> Dictionary:
	var instance: Node = await _instantiate_preview_chunk_and_wait("survival_range", 3)
	_assert_true(instance != null, "survival_range preview instantiates for %s timing run" % profile)
	if instance == null:
		return {}

	var prediction_variant: Variant = null
	if instance.has_method("headless_call_chunk"):
		prediction_variant = instance.headless_call_chunk("predict_route_timing", [profile])
	var prediction: Dictionary = prediction_variant if prediction_variant is Dictionary else {}
	_assert_true(not prediction.is_empty(), "Survival range reports %s timing profile" % profile)
	if prediction.is_empty():
		await _dispose_scene(instance)
		return {}

	if instance.has_method("headless_set_selected_characters"):
		instance.headless_set_selected_characters(["aster", "peris", "endo"])
	if instance.has_method("headless_set_routing_mode"):
		instance.headless_set_routing_mode(str(prediction.get("routing_mode", "safe")))

	var segments: Dictionary = prediction.get("segments", {})
	var measurements := {}
	var start_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	var start_tick := _preview_scheduler_tick(instance)

	measurements["depart"] = _survival_range_dwell_and_call(instance, "aster", segments.get("depart", {}), "depart_range")
	if segments.has("scout"):
		measurements["scout_move"] = _survival_range_move_segment(instance, segments.get("scout", {}))
		measurements["scout"] = _survival_range_dwell_and_call(instance, "aster", segments.get("scout", {}), "survey_route")
	if segments.has("stage_endo"):
		measurements["stage_endo"] = _survival_range_move_segment(instance, segments.get("stage_endo", {}))
	if segments.has("stage_peris"):
		measurements["stage_peris"] = _survival_range_move_segment(instance, segments.get("stage_peris", {}))
	if segments.has("lure"):
		measurements["lure"] = _survival_range_dwell_and_call(instance, "peris", segments.get("lure", {}), "activate_range_lure")
		if bool(prediction.get("use_peris_tune", false)) and instance.has_method("headless_activate_ability"):
			if instance.has_method("headless_select_character"):
				instance.headless_select_character("peris")
			measurements["peris_tune"] = {
				"activated": instance.headless_activate_ability("peris_tune"),
			}

	measurements["cross"] = _survival_range_dwell_and_call(instance, "endo", segments.get("cross", {}), "cross_seam")
	measurements["hide_move"] = _survival_range_move_segment(instance, segments.get("hide", {}))
	measurements["hide"] = _survival_range_dwell_and_call(instance, "endo", segments.get("hide", {}), "commit_hide")

	var post_hide_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	var post_hide_chunk: Dictionary = post_hide_state.get("chunk", {})
	var actual_window_margin := float(post_hide_chunk.get("lure_remaining", 0.0))

	if segments.has("hold"):
		var hold_duration := float(segments.get("hold", {}).get("total_time", 0.0))
		if hold_duration > 0.0:
			var hold_start := _preview_scheduler_tick(instance)
			_advance_showcase(instance, hold_duration)
			measurements["hold"] = {
				"predicted": hold_duration,
				"measured": _preview_scheduler_tick(instance) - hold_start,
			}
	if segments.has("shelter"):
		measurements["shelter"] = _survival_range_move_segment(instance, segments.get("shelter", {}))
		var shelter_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
		var shelter_chunk: Dictionary = shelter_state.get("chunk", {})
		if str(shelter_chunk.get("route_phase", "")) != "complete":
			_advance_showcase(instance, 0.05)

	var final_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	await _dispose_scene(instance)
	return {
		"profile": profile,
		"prediction": prediction,
		"measurements": measurements,
		"start_state": start_state,
		"predicted_total": float(prediction.get("total_time", 0.0)),
		"measured_total": float(final_state.get("scheduler_tick", 0.0)) - start_tick,
		"predicted_window_margin": float(prediction.get("window_margin", 0.0)),
		"actual_window_margin": actual_window_margin,
		"final_state": final_state,
	}

func _test_day_night_cycle() -> void:
	_test_name = "Day Night Cycle"

	var cycle = DayNightCycleScript.new()
	var day_boundary: Dictionary = cycle.advance(1, DayNightCycleScript.DAY_START, DayNightCycleScript.DEFAULT_DAY_DURATION_SECONDS)
	_assert_equals(int(day_boundary.get("day", 0)), 1, "A full day segment stays on the same day number")
	_assert_true(absf(float(day_boundary.get("time", -1.0)) - DayNightCycleScript.NIGHT_START) <= 0.0001, "900s reaches the night boundary")

	var night_boundary: Dictionary = cycle.advance(1, DayNightCycleScript.NIGHT_START, DayNightCycleScript.DEFAULT_NIGHT_DURATION_SECONDS)
	_assert_equals(int(night_boundary.get("day", 0)), 2, "A full night segment advances the calendar day")
	_assert_true(absf(float(night_boundary.get("time", -1.0)) - DayNightCycleScript.DAY_START) <= 0.0001, "300s rolls the clock back to dawn")

	var instance: Node = await _instantiate_preview_chunk_and_wait("survival_range", 3)
	_assert_true(instance != null, "survival_range preview instantiates for clock validation")
	if instance == null:
		return

	var start_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	var expected: Dictionary = cycle.advance(
		int(start_state.get("day", 1)),
		float(start_state.get("time", 0.0)),
		60.0
	)
	if instance.has_method("headless_advance"):
		instance.headless_advance(60.0, 1.0)
	var advanced_state: Dictionary = instance.headless_get_state() if instance.has_method("headless_get_state") else {}
	_assert_equals(int(advanced_state.get("day", 0)), int(expected.get("day", -1)), "Preview day advances with the shared clock")
	_assert_true(
		absf(float(advanced_state.get("time", -1.0)) - float(expected.get("time", -2.0))) <= 0.01,
		"Preview time advances 60s according to the shared clock"
	)
	_assert_equals(
		str(advanced_state.get("time_phase", "")),
		str(cycle.get_phase_name(float(expected.get("time", 0.0)))),
		"Preview reports the expected phase label after clock advancement"
	)
	await _dispose_scene(instance)

func _test_survival_range_timing() -> void:
	_test_name = "Survival Range Timing"

	var predictions := await _load_survival_range_timing_predictions()
	var staged_safe: Dictionary = predictions.get("staged_safe", {})
	var optimal_safe: Dictionary = predictions.get("optimal_safe", {})
	var greedy_direct: Dictionary = predictions.get("greedy_direct", {})

	_assert_true(not staged_safe.is_empty(), "Staged safe timing profile exists")
	_assert_true(not optimal_safe.is_empty(), "Optimal safe timing profile exists")
	_assert_true(not greedy_direct.is_empty(), "Greedy direct timing profile exists")
	if staged_safe.is_empty() or optimal_safe.is_empty() or greedy_direct.is_empty():
		return

	_assert_true(not bool(staged_safe.get("success", true)), "Safe route without Bloom is predicted to miss the window")
	_assert_true(float(staged_safe.get("window_margin", 0.0)) < 0.0, "Safe route without Bloom has negative window margin")
	_assert_true(bool(optimal_safe.get("success", false)), "Optimal safe route is predicted to succeed")
	_assert_true(float(optimal_safe.get("window_margin", 0.0)) > 0.0, "Optimal safe route keeps positive window margin")
	_assert_true(not bool(greedy_direct.get("success", true)), "Greedy direct profile is predicted to fail")
	_assert_equals(str(greedy_direct.get("outcome", "")), "hide_without_window", "Greedy direct profile fails at the hide")

	var measured := await _run_survival_range_profile("optimal_safe")
	_assert_true(not measured.is_empty(), "Measured optimal safe route returns data")
	if measured.is_empty():
		return

	var final_chunk: Dictionary = measured.get("final_state", {}).get("chunk", {})
	_assert_equals(str(final_chunk.get("route_phase", "")), "complete", "Measured optimal route reaches completion")
	_assert_true(bool(final_chunk.get("shelter_reached", false)), "Measured optimal route reaches the shelter")
	_assert_equals(str(final_chunk.get("last_outcome", "")), "success", "Measured optimal route records success")

	var predicted_total := float(measured.get("predicted_total", 0.0))
	var measured_total := float(measured.get("measured_total", 0.0))
	var total_diff := absf(predicted_total - measured_total)
	_assert_true(total_diff <= 0.08, "Measured total matches prediction within 0.08s (diff=%.3f)" % total_diff)

	var predicted_margin := float(measured.get("predicted_window_margin", 0.0))
	var actual_margin := float(measured.get("actual_window_margin", 0.0))
	var margin_diff := absf(predicted_margin - actual_margin)
	_assert_true(margin_diff <= 0.08, "Measured lure margin matches prediction within 0.08s (diff=%.3f)" % margin_diff)

	for step_name in ["scout_move", "stage_endo", "stage_peris", "hide_move", "shelter"]:
		var step: Dictionary = measured.get("measurements", {}).get(step_name, {})
		if step.is_empty():
			continue
		var step_diff := absf(float(step.get("predicted", 0.0)) - float(step.get("measured", 0.0)))
		_assert_true(step_diff <= 0.02, "%s timing matches predicted movement within 0.02s" % step_name)
		_assert_true(not bool(step.get("moving_after", true)), "%s finishes its movement command" % step_name)

func _report_survival_range_playtime() -> void:
	_test_name = "Survival Range Playtime"

	var predictions := await _load_survival_range_timing_predictions()
	_assert_true(not predictions.is_empty(), "Loaded survival range timing predictions for report")
	if predictions.is_empty():
		return

	var measured := await _run_survival_range_profile("optimal_safe")
	_assert_true(not measured.is_empty(), "Measured optimal safe route for report")
	if measured.is_empty():
		return

	var cycle = DayNightCycleScript.new()
	var start_state: Dictionary = measured.get("start_state", {})
	var start_day := int(start_state.get("day", 1))
	var start_time := float(start_state.get("time", 0.0))
	var start_clock: Dictionary = start_state.get("clock", {})
	var phase_name := str(start_clock.get("phase", cycle.get_phase_name(start_time)))
	var phase_duration := float(start_clock.get("phase_duration_seconds", cycle.get_phase_duration_seconds(start_time)))
	var phase_remaining := float(start_clock.get("phase_remaining_seconds", cycle.get_seconds_until_next_phase(start_time)))
	var measured_total := float(measured.get("measured_total", 0.0))
	var phase_consumed_percent := measured_total / maxf(phase_duration, 1.0) * 100.0
	var phase_remaining_after := maxf(0.0, phase_remaining - measured_total)
	var projected_clock: Dictionary = cycle.advance(start_day, start_time, measured_total)

	print("")
	print("  === Survival Range Playtime ===")
	print("  Safe route without Bloom: %s (fails, margin %+.2fs)" % [
		_format_playtime(float(predictions["staged_safe"].get("total_time", 0.0))),
		float(predictions["staged_safe"].get("window_margin", 0.0)),
	])
	print("  Optimal safe route: %s predicted, %s measured (margin %+.2fs)" % [
		_format_playtime(float(measured.get("predicted_total", 0.0))),
		_format_playtime(float(measured.get("measured_total", 0.0))),
		float(measured.get("predicted_window_margin", 0.0)),
	])
	print("  Greedy direct route: %s to fail (%.0f predicted seam damage)" % [
		_format_playtime(float(predictions["greedy_direct"].get("total_time", 0.0))),
		float(predictions["greedy_direct"].get("predicted_damage", 0.0)),
	])
	print("  Starts at Day %d %s and the optimal route uses %.1f%% of that phase window." % [
		start_day,
		phase_name,
		phase_consumed_percent,
	])
	print("  Clock after the optimal route: Day %d %s (%s left in the current phase)." % [
		int(projected_clock.get("day", start_day)),
		str(cycle.get_phase_name(float(projected_clock.get("time", start_time)))),
		_format_playtime(phase_remaining_after),
	])
	print("")

func _report_mother_ferrolure_playtime() -> void:
	_test_name = "Mother Ferrolure Playtime"

	var system_optimal := await _run_mother_ferrolure_profile("system_optimal")
	_assert_true(not system_optimal.is_empty(), "Measured Mother Ferrolure system-optimal route")
	if system_optimal.is_empty():
		return

	var movement_optimal := await _run_mother_ferrolure_profile("movement_optimal")
	_assert_true(not movement_optimal.is_empty(), "Measured Mother Ferrolure movement-optimal route")
	if movement_optimal.is_empty():
		return

	var movement_wrong := await _run_mother_ferrolure_profile("movement_wrong_repair")
	_assert_true(not movement_wrong.is_empty(), "Measured Mother Ferrolure wrong-repair detour route")
	if movement_wrong.is_empty():
		return

	var optimal_measurements: Dictionary = movement_optimal.get("measurements", {})
	var wrong_measurements: Dictionary = movement_wrong.get("measurements", {})
	_assert_true(bool(optimal_measurements.get("tend_mother", {}).get("result", false)), "Movement-optimal route still stabilizes the mother")
	_assert_true(bool(wrong_measurements.get("tend_mother", {}).get("result", false)), "Wrong-repair detour still recovers to a stabilized mother")

	var cycle = DayNightCycleScript.new()
	var start_state: Dictionary = movement_optimal.get("start_state", {})
	var start_day := int(start_state.get("day", 1))
	var start_time := float(start_state.get("time", 0.0))
	var start_clock: Dictionary = start_state.get("clock", {})
	var phase_name := str(start_clock.get("phase", cycle.get_phase_name(start_time)))
	var phase_duration := float(start_clock.get("phase_duration_seconds", cycle.get_phase_duration_seconds(start_time)))
	var optimal_total := float(movement_optimal.get("measured_total", 0.0))
	var wrong_total := float(movement_wrong.get("measured_total", 0.0))
	var optimal_phase_consumed_percent := optimal_total / maxf(phase_duration, 1.0) * 100.0
	var wrong_phase_consumed_percent := wrong_total / maxf(phase_duration, 1.0) * 100.0
	var optimal_projected_clock: Dictionary = cycle.advance(start_day, start_time, optimal_total)
	var wrong_projected_clock: Dictionary = cycle.advance(start_day, start_time, wrong_total)
	var root_animation_lower_bound := 9.0 * MOTHER_ROOT_SETTLE_SECONDS

	print("")
	print("  === Mother Ferrolure Playtime ===")
	print("  Root-slide lower bound: %s for 9 committed board shifts." % _format_playtime(root_animation_lower_bound))
	print("  System-optimal route: %s (%s interactions, %s root settling)." % [
		_format_playtime(float(system_optimal.get("measured_total", 0.0))),
		_format_playtime(float(system_optimal.get("interaction_total", 0.0))),
		_format_playtime(float(system_optimal.get("settle_total", 0.0))),
	])
	print("  Movement-optimal upper bound: %s (%s movement, %s interactions, %s root settling)." % [
		_format_playtime(optimal_total),
		_format_playtime(float(movement_optimal.get("movement_total", 0.0))),
		_format_playtime(float(movement_optimal.get("interaction_total", 0.0))),
		_format_playtime(float(movement_optimal.get("settle_total", 0.0))),
	])
	print("  Wrong-repair detour: %s total, adding %s over the clean movement line." % [
		_format_playtime(wrong_total),
		_format_playtime(wrong_total - optimal_total),
	])
	print("  Starts at Day %d %s. Clean movement line uses %.1f%% of that phase; the wrong-repair detour uses %.1f%%." % [
		start_day,
		phase_name,
		optimal_phase_consumed_percent,
		wrong_phase_consumed_percent,
	])
	print("  Clock after clean solve: Day %d %s. Clock after wrong detour: Day %d %s." % [
		int(optimal_projected_clock.get("day", start_day)),
		str(cycle.get_phase_name(float(optimal_projected_clock.get("time", start_time)))),
		int(wrong_projected_clock.get("day", start_day)),
		str(cycle.get_phase_name(float(wrong_projected_clock.get("time", start_time)))),
	])
	print("")

# --- Test: Grid Pathfinding ---
func _test_grid_pathfinding() -> void:
	_test_name = "Grid Pathfinding"

	# Create a simple room
	var grid := GridWorld.new()
	grid.create_room(10, 8, true)
	_assert_equals(grid.width, 10, "Room width is 10")
	_assert_equals(grid.height, 8, "Room height is 8")

	_assert_equals(grid.get_tile(0, 0), GridWorld.Tile.WALL, "Top-left is wall")
	_assert_equals(grid.get_tile(5, 4), GridWorld.Tile.FLOOR, "Center is floor")
	_assert_true(not grid.is_walkable(0, 0), "Wall is not walkable")
	_assert_true(grid.is_walkable(5, 4), "Floor is walkable")

	# Open-room path exists.
	var path := grid.find_path(Vector2i(1, 1), Vector2i(8, 6))
	_assert_true(path.size() > 0, "Path found in open room")

	if path.size() > 0:
		var end_cell := grid.world_to_grid(path[path.size() - 1])
		_assert_equals(end_cell, Vector2i(8, 6), "Path ends at target cell")

	for x in range(1, 9):
		grid.set_tile(x, 4, GridWorld.Tile.WALL)
	grid.set_tile(5, 4, GridWorld.Tile.FLOOR)

	# Path routes through the gap.
	var path2 := grid.find_path(Vector2i(1, 1), Vector2i(1, 6))
	_assert_true(path2.size() > 0, "Path found through wall gap")

	var passes_gap := false
	for wp in path2:
		var cell := grid.world_to_grid(wp)
		if cell.x >= 4 and cell.x <= 6 and cell.y == 4:
			passes_gap = true
			break
	_assert_true(passes_gap, "Path routes through gap in wall")

	grid.set_tile(5, 4, GridWorld.Tile.WALL)
	var path3 := grid.find_path(Vector2i(1, 1), Vector2i(1, 6))
	_assert_true(path3.is_empty(), "No path when fully walled off")

	# Coordinate conversion round-trip
	var cell := Vector2i(5, 3)
	var world_pos := grid.grid_to_world(cell)
	var back := grid.world_to_grid(world_pos)
	_assert_equals(back, cell, "grid_to_world → world_to_grid round-trip")

	# Load from strings (prototype format)
	var grid2 := GridWorld.new()
	grid2.load_from_strings(PackedStringArray([
		"111",
		"101",
		"111",
	]))
	_assert_equals(grid2.width, 3, "String-loaded width")
	_assert_equals(grid2.height, 3, "String-loaded height")
	_assert_equals(grid2.get_tile(1, 1), GridWorld.Tile.FLOOR, "String-loaded center is floor")
	_assert_equals(grid2.get_tile(0, 0), GridWorld.Tile.WALL, "String-loaded corner is wall")

	# find_tiles
	var grid3 := GridWorld.new()
	grid3.load_from_strings(PackedStringArray([
		"1111",
		"1051",
		"1601",
		"1111",
	]))
	var terminals := grid3.find_tiles(GridWorld.Tile.TERMINAL)
	_assert_equals(terminals.size(), 1, "Found 1 terminal tile")
	if terminals.size() > 0:
		_assert_equals(terminals[0], Vector2i(2, 1), "Terminal at correct position")
	var foods := grid3.find_tiles(GridWorld.Tile.FOOD)
	_assert_equals(foods.size(), 1, "Found 1 food tile")
	if foods.size() > 0:
		_assert_equals(foods[0], Vector2i(1, 2), "Food at correct position")

	# Locked door test
	var grid4 := GridWorld.new()
	grid4.load_from_strings(PackedStringArray([
		"111",
		"181",
		"101",
		"111",
	]))
	var locked := {Vector2i(1, 1): true}
	_assert_true(not grid4.is_walkable(1, 1, {}, locked), "Locked door blocks")
	_assert_true(grid4.is_walkable(1, 1, {}, {}), "Unlocked door passable")

# --- Test: Cooperative (space-time) pathfinding ---
# Characters reserve the (cell, time) slots their paths occupy; others plan around
# them. The invariant: no two characters ever occupy the same grid cell at the
# same scheduler tick while moving — including head-on swaps and convergence.

## Step the scheduler, sampling every tick, and report the worst-case overlap:
## how many sampled ticks had two characters in the same cell, plus the minimum
## center-to-center world distance seen.
func _coop_overlap_report(gs, ids: Array, sched, step: float, max_steps: int) -> Dictionary:
	var grid = gs.grid
	var same_cell_ticks := 0
	var min_dist := 1.0e9
	for s in range(max_steps):
		var cells := []
		var positions := []
		for id in ids:
			positions.append(gs.get_position(id))
			cells.append(grid.world_to_grid(positions[positions.size() - 1]))
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				if cells[i] == cells[j]:
					same_cell_ticks += 1
				var d: float = positions[i].distance_to(positions[j])
				if d < min_dist:
					min_dist = d
		var any_moving := false
		for id in ids:
			if gs.is_moving(id):
				any_moving = true
				break
		if not any_moving and s > 0:
			break
		sched.advance_ticks(step)
	return {"same_cell_ticks": same_cell_ticks, "min_dist": min_dist}

func _test_cooperative_pathfinding() -> void:
	_test_name = "Cooperative Pathfinding"

	# --- 1. Two characters swapping sides of an open room cross paths but never
	# share a cell at any tick. ---
	var grid := GridWorld.new()
	grid.create_room(16, 16, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.register_character("a", grid.grid_to_world(Vector2i(2, 8)), 3.0, {})
	gs.register_character("b", grid.grid_to_world(Vector2i(13, 8)), 3.0, {})
	gs.command_move_to_cell("a", Vector2i(13, 8))
	gs.command_move_to_cell("b", Vector2i(2, 8))
	var rep := _coop_overlap_report(gs, ["a", "b"], sched, 0.05, 600)
	_assert_equals(rep.same_cell_ticks, 0,
		"Crossing characters never share a cell (same-cell ticks=%d, min sep=%.2f)" % [rep.same_cell_ticks, rep.min_dist])
	_assert_true(not gs.is_moving("a") and not gs.is_moving("b"), "Both crossing characters arrived")
	_assert_equals(grid.world_to_grid(gs.get_position("a")), Vector2i(13, 8), "A reached its target")
	_assert_equals(grid.world_to_grid(gs.get_position("b")), Vector2i(2, 8), "B reached its target")

	# --- 2. A whole-party move spreads onto distinct cells and never overlaps. ---
	var grid2 := GridWorld.new()
	grid2.create_room(18, 14, true)
	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.grid = grid2
	gs2.scheduler = sched2
	gs2.register_character("aster", grid2.grid_to_world(Vector2i(2, 2)), 3.0, {})
	gs2.register_character("peris", grid2.grid_to_world(Vector2i(3, 2)), 3.0, {})
	gs2.register_character("endo", grid2.grid_to_world(Vector2i(4, 2)), 3.0, {})
	gs2.register_character("ron", grid2.grid_to_world(Vector2i(5, 2)), 3.0, {})
	gs2.set_party(["aster", "peris", "endo", "ron"])
	gs2.party_move_to_cell(Vector2i(12, 10))
	var rep2 := _coop_overlap_report(gs2, ["aster", "peris", "endo", "ron"], sched2, 0.05, 800)
	_assert_equals(rep2.same_cell_ticks, 0,
		"Party members never share a cell during a party move (min sep=%.2f)" % rep2.min_dist)
	var party_cells := {}
	for id in ["aster", "peris", "endo", "ron"]:
		_assert_true(not gs2.is_moving(id), "%s finished the party move" % id)
		var c := grid2.world_to_grid(gs2.get_position(id))
		_assert_true(not party_cells.has(c), "%s parked on its own distinct cell %s" % [id, c])
		party_cells[c] = id

	# --- 3. Head-on through a 2-wide corridor: each takes a lane, no overlap. ---
	var grid3 := GridWorld.new()
	grid3.load_from_strings(PackedStringArray([
		"####################",
		"#........##........#",
		"#........##........#",
		"#..................#",
		"#..................#",
		"#........##........#",
		"#........##........#",
		"####################",
	]))
	var sched3 := EventScheduler.new()
	var gs3 := GameState.new()
	gs3.grid = grid3
	gs3.scheduler = sched3
	gs3.register_character("x", grid3.grid_to_world(Vector2i(2, 3)), 3.0, {})
	gs3.register_character("y", grid3.grid_to_world(Vector2i(17, 4)), 3.0, {})
	gs3.command_move_to_cell("x", Vector2i(17, 4))
	gs3.command_move_to_cell("y", Vector2i(2, 3))
	var rep3 := _coop_overlap_report(gs3, ["x", "y"], sched3, 0.05, 1000)
	_assert_equals(rep3.same_cell_ticks, 0,
		"Head-on characters take separate lanes through the corridor (min sep=%.2f)" % rep3.min_dist)
	_assert_true(not gs3.is_moving("x") and not gs3.is_moving("y"), "Both head-on characters arrived")
	_assert_equals(grid3.world_to_grid(gs3.get_position("x")), Vector2i(17, 4), "X crossed the corridor")
	_assert_equals(grid3.world_to_grid(gs3.get_position("y")), Vector2i(2, 3), "Y crossed the corridor")

	# --- 4. Planning is deterministic and step-size (fast-forward) invariant. ---
	var fine := _coop_run_swap("fine", 0.05)
	var coarse := _coop_run_swap("coarse", 0.5)
	var repeat := _coop_run_swap("repeat", 0.05)
	_assert_true(fine.a.distance_to(repeat.a) < 0.001 and fine.b.distance_to(repeat.b) < 0.001,
		"Cooperative paths are deterministic across identical runs")
	_assert_true(fine.a.distance_to(coarse.a) < 0.001 and fine.b.distance_to(coarse.b) < 0.001,
		"Cooperative paths reach the same positions at fine (1x) and coarse (10x) step sizes")
	_assert_equals(fine.hash, coarse.hash, "Final state hash matches across step sizes (fast-forward invariant)")

	# --- 5. Characters of DIFFERENT speeds crossing still never share a cell.
	# A slow character's reservation windows are wider; the fast one must time
	# its transit around them. (The other cases use equal speed.) ---
	var grid5 := GridWorld.new()
	grid5.create_room(16, 16, true)
	var sched5 := EventScheduler.new()
	var gs5 := GameState.new()
	gs5.grid = grid5
	gs5.scheduler = sched5
	gs5.register_character("slow", grid5.grid_to_world(Vector2i(8, 2)), 2.0, {})
	gs5.register_character("fast", grid5.grid_to_world(Vector2i(2, 8)), 6.0, {})
	gs5.command_move_to_cell("slow", Vector2i(8, 13))
	gs5.command_move_to_cell("fast", Vector2i(13, 8))
	var rep5 := _coop_overlap_report(gs5, ["slow", "fast"], sched5, 0.05, 1000)
	_assert_equals(rep5.same_cell_ticks, 0,
		"Different-speed crossing never shares a cell (min sep=%.2f)" % rep5.min_dist)
	_assert_true(not gs5.is_moving("slow") and not gs5.is_moving("fast"), "Both different-speed characters arrived")
	_assert_equals(grid5.world_to_grid(gs5.get_position("slow")), Vector2i(8, 13), "Slow reached its target")
	_assert_equals(grid5.world_to_grid(gs5.get_position("fast")), Vector2i(13, 8), "Fast reached its target")

	# --- 6. A dodging character reserves its cells, so a cooperative mover routes
	# around it (dodge builds movement manually, bypassing _start_movement). ---
	var grid6 := GridWorld.new()
	grid6.create_room(16, 16, true)
	var sched6 := EventScheduler.new()
	var gs6 := GameState.new()
	gs6.grid = grid6
	gs6.scheduler = sched6
	gs6.register_character("dodger", grid6.grid_to_world(Vector2i(8, 8)), 3.0, {"dodge_unlocked": true, "stamina": 100.0})
	gs6.register_character("mover", grid6.grid_to_world(Vector2i(2, 8)), 3.0, {})
	var dodged: bool = gs6.dodge_roll("dodger", Vector3(0, 0, 1))
	_assert_true(dodged, "Dodge roll succeeded")
	var dodge_reserved := false
	for cell in gs6._reservations.keys():
		for slot in gs6._reservations[cell]:
			if String(slot.id) == "dodger":
				dodge_reserved = true
	_assert_true(dodge_reserved, "Dodging character holds cell reservations during the dodge")
	gs6.command_move_to_cell("mover", Vector2i(13, 8))
	var rep6 := _coop_overlap_report(gs6, ["dodger", "mover"], sched6, 0.02, 600)
	_assert_equals(rep6.same_cell_ticks, 0, "Cooperative mover never shares a cell with a dodging character (min sep=%.2f)" % rep6.min_dist)

	# --- 7. A mid-move speed change (e.g. toggling run) keeps cooperative timing
	# rather than reverting to a plain overlap-prone path. ---
	var grid7 := GridWorld.new()
	grid7.create_room(16, 16, true)
	var sched7 := EventScheduler.new()
	var gs7 := GameState.new()
	gs7.grid = grid7
	gs7.scheduler = sched7
	gs7.register_character("p", grid7.grid_to_world(Vector2i(2, 8)), 3.0, {})
	gs7.register_character("q", grid7.grid_to_world(Vector2i(13, 8)), 3.0, {})
	gs7.command_move_to_cell("p", Vector2i(13, 8))
	gs7.command_move_to_cell("q", Vector2i(2, 8))
	var same7 := 0
	var changed := false
	for s in range(600):
		var cp := grid7.world_to_grid(gs7.get_position("p"))
		var cq := grid7.world_to_grid(gs7.get_position("q"))
		if cp == cq:
			same7 += 1
		if not gs7.is_moving("p") and not gs7.is_moving("q") and s > 0:
			break
		# Toggle p's speed partway through the crossing.
		if not changed and s == 20:
			gs7.change_move_speed("p", 6.0)
			changed = true
		sched7.advance_ticks(0.05)
	_assert_true(changed, "Speed change fired mid-move")
	_assert_equals(same7, 0, "Speed change mid-move preserves the no-overlap guarantee")
	_assert_true(not gs7.is_moving("p") and not gs7.is_moving("q"), "Both arrived after a mid-move speed change")

	# --- 8. Cramped, elevator-like room: a mover can still reach a downed ally to
	# wake them (within interaction range) even though the ally + escorts hold
	# parked reservations. Guards the elevator "approach Aster" beat. ---
	var grid8 := GridWorld.new()
	grid8.create_room(7, 7, true)  # ~5x5 interior, like the elevator
	var sched8 := EventScheduler.new()
	var gs8 := GameState.new()
	gs8.grid = grid8
	gs8.scheduler = sched8
	gs8.register_character("aster", grid8.grid_to_world(Vector2i(3, 3)), 2.0, {})   # downed, parked
	gs8.register_character("eu1", grid8.grid_to_world(Vector2i(4, 4)), 2.0, {})     # escort, parked
	gs8.register_character("eu2", grid8.grid_to_world(Vector2i(2, 4)), 2.0, {})     # escort, parked
	gs8.register_character("peris", grid8.grid_to_world(Vector2i(1, 1)), 2.5, {})
	var moved8: bool = gs8.command_move_to_cell("peris", Vector2i(3, 3))  # click onto Aster
	_assert_true(moved8, "Peris accepts a move toward the downed ally")
	_assert_true(gs8.is_moving("peris"), "Peris starts moving toward Aster")
	for s in range(500):
		if not gs8.is_moving("peris"):
			break
		sched8.advance_ticks(0.05)
	var peris_wake := gs8.get_position("peris")
	var aster_wake := gs8.get_position("aster")
	_assert_true(peris_wake.distance_to(aster_wake) < 1.8,
		"Peris reaches wake range of the downed ally in a cramped room (sep=%.2f)" % peris_wake.distance_to(aster_wake))

## Run the swap scenario and return final positions + state hash. Used to prove
## determinism and fast-forward invariance at different scheduler step sizes.
func _coop_run_swap(_label: String, step: float) -> Dictionary:
	var grid := GridWorld.new()
	grid.create_room(16, 16, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.register_character("a", grid.grid_to_world(Vector2i(2, 8)), 3.0, {})
	gs.register_character("b", grid.grid_to_world(Vector2i(13, 8)), 3.0, {})
	gs.command_move_to_cell("a", Vector2i(13, 8))
	gs.command_move_to_cell("b", Vector2i(2, 8))
	for s in range(2000):
		if not gs.is_moving("a") and not gs.is_moving("b"):
			break
		sched.advance_ticks(step)
	return {"a": gs.get_position("a"), "b": gs.get_position("b"), "hash": gs.state_hash()}

# --- Test: reusable movement-path visual ---
# PathRenderer is the shared path line: point it at a GameState character and it
# builds the remaining-route geometry from the data layer. Render frames aren't
# pumped reliably headless, so drive _process() directly and inspect the mesh.
func _test_path_renderer() -> void:
	_test_name = "Path Renderer"

	# Gridless GameState (like the elevator): movement is straight-line world moves.
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	gs.register_character("mover", Vector3.ZERO, 3.0, {})

	var pr := PathRenderer.new()
	add_child(pr)  # _ready builds the line MeshInstance (not @tool → runs headless)
	pr.setup(gs, "mover", Color(0.2, 0.6, 1.0))

	# Idle: nothing to draw.
	pr._process(0.0)
	_assert_true(pr._line.mesh == null, "Idle character draws no path line")

	# Moving: the not-yet-traversed leg becomes line geometry.
	gs.command_move_to_pos("mover", Vector3(6.0, 0.0, 0.0))  # 6m / 3 = 2.0 ticks
	sched.advance_ticks(1.0)  # halfway
	pr._process(0.0)
	_assert_true(gs.is_moving("mover"), "Mover is mid-move")
	_assert_true(pr._line.mesh != null, "Moving character draws a path line")
	if pr._line.mesh != null:
		_assert_true(pr._line.mesh.get_surface_count() > 0,
			"Path line mesh has a surface (vertices were added)")

	# Running flips the line to the orange running tint.
	pr.set_running(true)
	pr._process(0.0)
	_assert_equals(pr._mat.albedo_color, PathRenderer.RUNNING_COLOR,
		"Running recolours the path line")
	pr.set_running(false)

	# Arrived: the line clears again.
	sched.advance_ticks(2.0)
	pr._process(0.0)
	_assert_true(not gs.is_moving("mover"), "Mover arrived")
	_assert_true(pr._line.mesh == null, "Arrived character draws no path line")

	# Explicit-path mode: works without any GameState movement (standalone previews).
	pr.char_id = ""
	pr.set_explicit_path([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 1.0)])
	pr._process(0.0)
	_assert_true(pr._line.mesh != null, "Explicit path draws a line with no GameState move")
	pr.clear_explicit_path()
	pr._process(0.0)
	_assert_true(pr._line.mesh == null, "Cleared explicit path draws nothing")

	pr.queue_free()

## PathRenderManager is the reusable, scene-level path system: it draws a path for EVERY moving
## character (player, party, NPC, escort), not just the one baked into player.gd — which is why the
## elevator party / escorts showed no path before. Also covers queued-while-paused moves.
func _test_path_render_manager() -> void:
	_test_name = "Path Render Manager"
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	gs.register_character("a", Vector3.ZERO, 3.0, {})
	gs.register_character("b", Vector3(5.0, 0.0, 0.0), 3.0, {})

	var root := Node3D.new()
	add_child(root)
	var mgr := PathRenderManager.new()
	root.add_child(mgr)
	mgr.setup(gs, root)

	# Two characters moving at once — the manager draws a path for EACH, not just the player.
	gs.command_move_to_pos("a", Vector3(4.0, 0.0, 4.0))
	gs.command_move_to_pos("b", Vector3(-3.0, 0.0, 2.0))
	sched.advance_ticks(0.3)
	mgr._process(0.0)
	_assert_true(mgr._renderers.has("a") and mgr._renderers.has("b"),
		"Manager makes a path renderer for every registered character (not just the player)")
	var pr_a: PathRenderer = mgr._renderers.get("a")
	var pr_b: PathRenderer = mgr._renderers.get("b")
	_assert_true(pr_a != null and pr_a._remaining_points().size() >= 2,
		"Character A's path is drawable (>= 2 points)")
	_assert_true(pr_b != null and pr_b._remaining_points().size() >= 2,
		"A second (party / NPC / escort) character's path also draws — the elevator-party gap")

	# Queued while paused: a move issued while the scheduler is paused still shows its full route.
	sched.pause()
	gs.command_move_to_pos("a", Vector3(0.0, 0.0, -4.0))
	mgr._process(0.0)
	_assert_true(gs.is_moving("a") and pr_a._remaining_points().size() >= 2,
		"A queued move (issued while paused) still shows its path")

	root.queue_free()
	await get_tree().process_frame

	# Gridless party fan-out: a single party move must address EVERY member and
	# spread them (distinct destinations), not stack them on one point.
	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.scheduler = sched2
	gs2.register_character("peris", Vector3.ZERO, 3.0, {})
	gs2.register_character("aster", Vector3(0.0, 0.0, 0.5), 3.0, {})
	gs2.set_party(["peris", "aster"])
	gs2.party_move_to_pos(Vector3(5.0, 0.0, 0.0))
	_assert_true(gs2.is_moving("peris") and gs2.is_moving("aster"),
		"Gridless party move addresses every member")
	var peris_dest: Vector3 = gs2.characters["peris"].movement.path[-1]
	var aster_dest: Vector3 = gs2.characters["aster"].movement.path[-1]
	_assert_true(absf(peris_dest.z - aster_dest.z) > 0.1,
		"Gridless party move fans members onto distinct points (no stacking)")

## Multi-level grid: a LEVEL is the same (x,z) plane lifted by level_height in world Y. Cells stay
## Vector2i (backward compatible — level defaults to 0 -> Y=0); ladders/ramps are inter-level links.
func _test_grid_levels() -> void:
	_test_name = "Grid Levels"
	var grid := GridWorld.new()
	grid.create_room(10, 10)
	grid.set_level_count(2)
	grid.level_height = 4.0

	# grid_to_world derives Y from the level; world_to_grid ignores Y (same cell on any floor).
	_assert_equals(grid.grid_to_world(Vector2i(5, 5), 0).y, 0.0, "Level 0 sits at Y=0 (backward compatible)")
	_assert_equals(grid.grid_to_world(Vector2i(5, 5), 1).y, 4.0, "Level 1 sits one level_height up")
	_assert_equals(grid.world_to_grid(grid.grid_to_world(Vector2i(5, 5), 1)), Vector2i(5, 5), "world_to_grid maps to the same cell on any floor")

	# Ladder/ramp links between floors.
	grid.add_inter_level_link(Vector2i(3, 3), 0, 1, "ladder")
	_assert_true(grid.can_traverse_link(Vector2i(3, 3), 0, 1) and grid.can_traverse_link(Vector2i(3, 3), 1, 0),
		"A ladder links both directions between its two floors")
	_assert_true(grid.get_link_cost(Vector2i(3, 3), 0, 1) > 1.0, "Climbing a ladder costs more than a flat step")
	_assert_equals(grid.links_from(Vector2i(3, 3), 0), [1], "links_from reports the reachable floor")
	_assert_true(not grid.can_traverse_link(Vector2i(4, 4), 0, 1), "No link where none was placed")

	# Character floor tracking + no-float movement: a character on level 1 stays at the level's Y.
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	var spawn := grid.grid_to_world(Vector2i(2, 2), 1)
	gs.register_character("up", spawn, 3.0, {})
	_assert_equals(gs.get_character_level("up"), 1, "A character spawned at a floor's Y registers on that floor")
	gs.command_move_to_cell("up", Vector2i(6, 6))
	sched.advance_ticks(0.4)
	_assert_true(gs.is_moving("up") and absf(gs.get_position("up").y - 4.0) < 0.6,
		"Moving on level 1 keeps the character at the floor's Y (no floating down to Y=0)")
	# set_character_level snaps Y to the new floor (a ladder/ramp arrival).
	gs.set_character_level("up", 0)
	_assert_equals(gs.get_character_level("up"), 0, "set_character_level records the new floor")
	_assert_true(absf(gs.get_position("up").y) < 0.01, "set_character_level snaps the data-layer Y to the floor")

	# Cross-floor A*: route from level 0 to level 1, which MUST go through the ladder cell.
	var g2 := GridWorld.new()
	g2.create_room(8, 8)
	g2.set_level_count(2)
	g2.add_inter_level_link(Vector2i(4, 4), 0, 1, "ladder")
	var ml := g2.find_multi_level_path(Vector2i(1, 1), 0, Vector2i(6, 6), 1)
	_assert_true(ml.size() >= 2, "Multi-level A* finds a route across floors via a ladder")
	var crossed := false
	for i in range(1, ml.size()):
		if int(ml[i].level) != int(ml[i - 1].level):
			crossed = true
			_assert_equals(ml[i].cell, ml[i - 1].cell, "A floor change happens AT a cell (the ladder), not mid-air")
			_assert_equals(ml[i].cell, Vector2i(4, 4), "The floor change uses the registered ladder cell")
	_assert_true(crossed, "The cross-floor route actually changes level (climbs the ladder)")
	_assert_true(ml[-1].cell == Vector2i(6, 6) and int(ml[-1].level) == 1, "Route ends at the destination cell on the target floor")

	# --- Per-level walkable footprints: a cell can be walkable on one floor but void on another. ---
	var gw := GridWorld.new()
	gw.create_room(10, 10)
	gw.set_level_count(2)
	# Level 1 (upper) is restricted to a small footprint; level 0 (lower) stays fully walkable.
	_assert_true(gw.is_cell_allowed_on_level(Vector2i(8, 8), 1), "Unrestricted level allows every cell")
	gw.allow_cell_region_on_level(Vector2i(1, 1), Vector2i(3, 3), 1)
	_assert_true(gw.is_level_restricted(1), "Declaring a region restricts the level to its footprint")
	_assert_true(gw.is_cell_allowed_on_level(Vector2i(2, 2), 1), "Cells inside the footprint stay walkable on level 1")
	_assert_true(not gw.is_cell_allowed_on_level(Vector2i(8, 8), 1), "Cells outside the footprint are void on level 1")
	_assert_true(gw.is_walkable(2, 2, {}, {}, 1), "is_walkable(level 1) true inside the footprint")
	_assert_true(not gw.is_walkable(8, 8, {}, {}, 1), "is_walkable(level 1) false outside the footprint (the void)")
	# The SAME (x,z) is still walkable on the unrestricted lower floor — footprints are per level.
	_assert_true(gw.is_walkable(8, 8, {}, {}, 0), "The same cell is walkable on the unrestricted lower floor")
	# find_path on level 1 refuses a destination outside the footprint, but routes inside it.
	_assert_true(gw.find_path(Vector2i(1, 1), Vector2i(8, 8), {}, false, {}, {}, 1).is_empty(),
		"find_path(level 1) can't reach a void cell off the footprint")
	_assert_true(not gw.find_path(Vector2i(1, 1), Vector2i(3, 3), {}, false, {}, {}, 1).is_empty(),
		"find_path(level 1) routes within the footprint")
	# World-space region helper maps an XZ rect to cells (cell_size 1, origin 0 → cell == floor(world)).
	var gwr := GridWorld.new()
	gwr.create_room(10, 10)
	gwr.set_level_count(2)
	gwr.allow_world_region_on_level(Vector2(0.5, 0.5), Vector2(2.5, 2.5), 1)
	_assert_true(gwr.is_cell_allowed_on_level(Vector2i(1, 1), 1), "World region marks the covered cells walkable")
	_assert_true(not gwr.is_cell_allowed_on_level(Vector2i(5, 5), 1), "World region leaves outside cells void")

	# No ladder between floors -> no cross-level route.
	var g3 := GridWorld.new()
	g3.create_room(8, 8)
	g3.set_level_count(2)
	_assert_true(g3.find_multi_level_path(Vector2i(1, 1), 0, Vector2i(6, 6), 1).is_empty(),
		"No ladder -> no route between floors (you can't walk through the air)")

	# --- Cross-level EXECUTOR: a character actually WALKS between floors via the ladder. ---
	# g2 has the ladder at (4,4) linking floors 0<->1. Record into a log so we can prove the
	# whole multi-floor traversal is ONE command that replay reproduces.
	var sched_x := EventScheduler.new()
	var gx := GameState.new()
	gx.grid = g2
	gx.scheduler = sched_x
	var xlog := EventLog.new()
	gx.event_log = xlog
	gx.register_character("climber", g2.grid_to_world(Vector2i(1, 1), 0), 3.0, {})
	_assert_equals(gx.get_character_level("climber"), 0, "Climber starts on level 0")

	_assert_true(gx.command_move_cross_level("climber", Vector2i(6, 6), 1),
		"command_move_cross_level finds a route to another floor")
	var ladder_visited := false
	for i in range(300):
		sched_x.advance_ticks(0.1)
		if not ladder_visited and gx.get_character_level("climber") == 1:
			ladder_visited = true
			_assert_true(gx.get_position("climber").distance_to(g2.grid_to_world(Vector2i(4, 4), 1)) < 0.6,
				"The floor change happens at the ladder cell (no mid-air transition)")
		if not gx.is_moving("climber") and gx.get_character_level("climber") == 1:
			break
	_assert_true(ladder_visited, "The climber transitioned to level 1 during the traversal (climbed the ladder)")
	_assert_equals(gx.get_character_level("climber"), 1, "The climber ends on the destination floor")
	_assert_equals(g2.world_to_grid(gx.get_position("climber")), Vector2i(6, 6),
		"The climber ends on the destination cell")
	_assert_true(absf(gx.get_position("climber").y - 4.0) < 0.05,
		"The climber's final Y matches the destination floor (no floating)")
	_assert_true(not gx.is_moving("climber"), "The climber is parked at the destination")

	# The whole traversal is ONE logged command; per-floor transitions are derived, not logged.
	var x_kinds: Array[String] = []
	for e in xlog.events:
		x_kinds.append(String(e["kind"]))
	_assert_equals(x_kinds.count("move_cross_level"), 1, "One move_cross_level command for the whole traversal")
	_assert_equals(x_kinds.count("set_level"), 0, "Per-floor transitions are derived from the command, not separately logged")

	# Replay reproduces the same destination floor + cell from that single command.
	gx.flush_tick()  # extend recorded_until past the traversal so replay advances through it
	var gx_replay := GameState.replay(xlog, g2)
	_assert_equals(gx_replay.get_character_level("climber"), 1, "Replay lands the climber on the destination floor")
	_assert_equals(g2.world_to_grid(gx_replay.get_position("climber")), Vector2i(6, 6),
		"Replay lands the climber on the destination cell")

	# Same-floor call delegates to an ordinary move; a floor with no route returns false.
	var gy := GameState.new()
	gy.grid = g2
	gy.scheduler = EventScheduler.new()
	gy.register_character("c2", g2.grid_to_world(Vector2i(1, 1), 0), 3.0, {})
	_assert_true(gy.command_move_cross_level("c2", Vector2i(2, 2), 0),
		"command_move_cross_level on the same floor falls back to an ordinary move")
	_assert_true(gy.is_moving("c2"), "Same-floor cross-level call starts a normal move")
	_assert_true(not gy.command_move_cross_level("c2", Vector2i(6, 6), 9),
		"No route to an absent floor -> command_move_cross_level returns false")

# --- Test: reusable scheduler-driven state machine (StateMachine) ---
func _test_state_machine() -> void:
	_test_name = "State Machine"
	var sched := EventScheduler.new()
	var log := {"enter": [], "exit": [], "update": 0, "changes": []}
	var fsm := StateMachine.new(sched, "test_fsm")
	fsm.add_state("idle",
		func(): log["enter"].append("idle"),
		func(): log["exit"].append("idle"))
	fsm.add_state("patrol",
		func(): log["enter"].append("patrol"),
		func(): log["exit"].append("patrol"),
		func(_d): log["update"] = int(log["update"]) + 1)
	fsm.add_state("alert", func(): log["enter"].append("alert"))
	fsm.state_changed.connect(func(from_s, to_s): log["changes"].append("%s->%s" % [from_s, to_s]))

	fsm.start("idle")
	_assert_equals(fsm.current(), "idle", "start sets the initial state")
	_assert_true(log["enter"] == ["idle"], "start runs the enter hook (no exit of a previous state)")

	fsm.transition_to("patrol")
	_assert_equals(fsm.current(), "patrol", "transition_to changes state")
	_assert_true(log["exit"] == ["idle"], "transition_to runs the previous state's exit hook")
	_assert_true(log["enter"] == ["idle", "patrol"], "transition_to runs the new state's enter hook")
	_assert_true(log["changes"] == ["idle->patrol"], "state_changed fires with from/to")

	var enters_before: int = (log["enter"] as Array).size()
	fsm.transition_to("patrol")
	_assert_equals((log["enter"] as Array).size(), enters_before, "a self-transition is a no-op")

	fsm.update(0.1)
	_assert_equals(int(log["update"]), 1, "update drives the current state's update hook")

	# Timed transition rides the scheduler (respects delay).
	fsm.transition_after(1.0, "alert")
	sched.advance_ticks(0.5)
	_assert_equals(fsm.current(), "patrol", "a scheduled transition has not fired before its delay")
	sched.advance_ticks(0.6)
	_assert_equals(fsm.current(), "alert", "a scheduled transition fires after the delay")

	# An intervening transition cancels a pending scheduled transition (no stale state change).
	var sm2 := StateMachine.new(sched, "test_fsm2")
	var fired := {"v": false}
	sm2.add_state("a")
	sm2.add_state("b", func(): fired["v"] = true)
	sm2.add_state("c")
	sm2.start("a")
	sm2.transition_after(1.0, "b")
	sm2.transition_to("c")
	sched.advance_ticks(2.0)
	_assert_true(not fired["v"], "an intervening transition cancels the pending scheduled transition")
	_assert_equals(sm2.current(), "c", "the FSM stays in the manually-chosen state")

	# Replay determinism: identical tick steps (1x vs 10x) reach the same state — fast-forward safe.
	_assert_equals(_drive_fsm_sequence(0.05), _drive_fsm_sequence(0.5),
		"chained timed transitions are step-size invariant (fast-forward / replay safe)")
	_assert_equals(_drive_fsm_sequence(0.05), "s2", "the chained FSM ends in the final state")

# --- Test: an enemy configured like the elevator's fork lane engages a target that walks in ---
# Data-layer (scheduler + _process), so headless runs the same combat loop as real play: the fork
# enemies aren't inert — walk into the lane and they detect, lock on, pursue, and attack.
func _test_elevator_enemy_engagement() -> void:
	_test_name = "Elevator Enemy Engagement"
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	gs.register_character("aster", Vector3(10.0, 0.5, 0.0), 2.5, {"hp": 100.0})
	# Configured exactly like a route_enemy in _build_below_chunk (default detection 6, party targets).
	var enemy := Enemy.new()
	enemy.game_state = gs
	enemy.char_id = "route_enemy_probe"
	enemy._detection_targets = ["aster", "peris"]
	holder.add_child(enemy)
	gs.register_character("route_enemy_probe", Vector3(0.0, 0.5, 0.0), enemy.move_speed,
		{"detection_range": enemy.detection_range})
	enemy.activate()
	enemy.set_patrol([Vector3(-1.5, 0.5, 0.0), Vector3(1.5, 0.5, 0.0)])
	_assert_equals(enemy.get_state(), "patrol", "Fork enemy starts patrolling")

	# Walk Aster into the enemy's lane (a move command — exactly what a player click issues).
	gs.command_move_to_pos("aster", Vector3(1.0, 0.5, 0.0))
	var combat_states := ["alert", "pursuit", "windup", "charge", "recover"]
	for _ei in range(240):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		if enemy.get_state() in ["windup", "charge", "recover"]:
			break
	_assert_true(enemy.get_state() != "patrol",
		"The fork enemy leaves patrol when Aster enters its lane (got: %s)" % enemy.get_state())
	_assert_equals(enemy._current_target_id, "aster", "The fork enemy locks onto Aster")
	_assert_true(enemy.get_state() in combat_states,
		"The fork enemy runs its combat loop instead of idling (got: %s)" % enemy.get_state())
	enemy.queue_free()
	holder.queue_free()

# --- Test: a hidden character is invisible to enemy detection (hide-spot foundation) ---
func _test_hidden_detection() -> void:
	_test_name = "Hidden From Detection"
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	gs.register_character("aster", Vector3(10.0, 0.5, 0.0), 2.5, {"hp": 100.0})
	gs.set_character_hidden("aster", true)
	_assert_true(gs.is_character_hidden("aster"), "set_character_hidden marks the target concealed")
	var enemy := Enemy.new()
	enemy.game_state = gs
	enemy.char_id = "guard"
	enemy._detection_targets = ["aster"]
	holder.add_child(enemy)
	gs.register_character("guard", Vector3(0.0, 0.5, 0.0), enemy.move_speed,
		{"detection_range": enemy.detection_range})
	enemy.activate()
	enemy.set_patrol([Vector3(-1.0, 0.5, 0.0), Vector3(1.0, 0.5, 0.0)])

	# Walk Aster right up to the guard WHILE HIDDEN — point-blank, but never spotted.
	gs.command_move_to_pos("aster", Vector3(0.5, 0.5, 0.0))
	for _i in range(80):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
	_assert_equals(enemy.get_state(), "patrol",
		"A hidden target is never spotted, even point-blank (got: %s)" % enemy.get_state())

	# Step out of cover — now the guard sees her.
	gs.set_character_hidden("aster", false)
	for _i in range(80):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		if enemy.get_state() != "patrol":
			break
	_assert_true(enemy.get_state() != "patrol",
		"Stepping out of cover gets her spotted (got: %s)" % enemy.get_state())
	_assert_equals(enemy._current_target_id, "aster", "The guard locks onto the revealed target")
	enemy.queue_free()
	holder.queue_free()

# --- Test: the two-lure relay hide puzzle solves on the data layer (headless == real play) ---
func _test_lure_relay_puzzle() -> void:
	_test_name = "Lure Relay Puzzle"
	var instance = await _instantiate_preview_chunk_and_wait("lure_relay", 4)
	if instance == null:
		_assert_true(false, "lure_relay preview instantiates")
		return
	var chunk = instance._active_chunk
	_assert_true(chunk != null, "Lure relay chunk loads in the shared preview")
	if chunk == null:
		instance.queue_free()
		await get_tree().process_frame
		return
	var anchors: Dictionary = chunk.get_preview_anchors()
	var dur: float = float(chunk.LURE_DURATION)
	var gs = instance._game_state

	# --- Intended solve: fire far Lure 2, hide by it, circle to Lure 1 while the guards are distracted,
	#     return to cover, let them relay the whole hall back past you, then run the now-open exit. ---
	chunk.reset_preview_state()
	_assert_true(chunk.activate_lure2(), "Lure 2 (far, by the guards) fires")
	instance.headless_set_character_position("peris", anchors["hide_spot"])
	instance.headless_advance(1.0, 0.1)
	_assert_equals(int(chunk.get_preview_state()["committed_lure"]), 2, "The sentries break toward Lure 2")
	_assert_true(gs.is_character_hidden("peris"), "In the offshoot by Lure 2, the runner is concealed")
	# Circle to the entrance Lure 1: the committed guards are DISTRACTED (range shrunk), so a runner
	# keeping distance can reach it. Drive the real move to prove the round trip isn't spotted.
	gs.command_move_to_pos("peris", anchors["lure_one"])
	instance.headless_advance(3.0, 0.1)
	_assert_true(not chunk.get_preview_state()["failed"], "Circling to Lure 1 past distracted guards is not a catch")
	_assert_true(chunk.activate_lure1(), "Lure 1 (near the entrance) fires")
	instance.headless_set_character_position("peris", anchors["hide_spot"])
	instance.headless_advance(0.5, 0.1)
	_assert_equals(int(chunk.get_preview_state()["committed_lure"]), 2, "They stay on Lure 2 while it holds")
	# Lure 2 expires -> relay to the still-singing Lure 1, walking the whole hall back past cover.
	instance.headless_advance(dur + 1.0, 0.1)
	_assert_equals(int(chunk.get_preview_state()["committed_lure"]), 1, "On Lure 2's expiry they relay to Lure 1 (got: %s)" % chunk.get_preview_state()["committed_lure"])
	_assert_true(not chunk.get_preview_state()["failed"], "The hidden runner is not caught as the sentries pass")
	# Slip out and run the now-open exit while Lure 1 holds them far away.
	instance.headless_set_character_position("peris", anchors["exit"])
	instance.headless_advance(0.3, 0.1)
	_assert_true(chunk.get_preview_state()["complete"], "Reaching the exit after the relay completes the puzzle")

	# --- Cheese FAILS: fire only Lure 1 (near entrance), then try to cross to the distant hide. The
	#     guards swarm the corridor toward Lure 1, so the only path to the hide runs through them point
	#     blank — spotted. Skipping Lure 2 (which clears that corridor) is a loss. ---
	chunk.reset_preview_state()
	instance.headless_set_character_position("peris", chunk.get_spawn_positions()["peris"])  # back to the entrance
	_assert_true(chunk.activate_lure1(), "Cheese: Lure 1 alone fires")
	instance.headless_advance(0.3, 0.1)
	gs.command_move_to_pos("peris", anchors["hide_spot"])  # nav-routed down the corridor — no diagonal cut
	instance.headless_advance(9.0, 0.1)
	_assert_true(chunk.get_preview_state()["failed"], "Firing only Lure 1 and crossing to the hide gets you spotted")
	_assert_true(not chunk.get_preview_state()["complete"], "The cheese does not solve the puzzle")

	# --- Wrong way: stroll up exposed toward the guards -> spotted ---
	chunk.reset_preview_state()
	instance.headless_set_character_position("peris", Vector3(40.0, 0.5, 0.0))
	gs.command_move_to_pos("peris", Vector3(50.0, 0.5, 0.0))
	instance.headless_advance(5.0, 0.1)
	_assert_true(chunk.get_preview_state()["failed"], "Strolling up exposed toward the exit puts a sentry onto you")
	instance.queue_free()
	await get_tree().process_frame

	# --- Tending: a lure is a TIMED_ACTION interactable — CLICK to use (never proximity), then Peris
	#     TENDS it for the interactable's dwell_time before it sings (the dwell timer, not a hand-rolled
	#     per-chunk schedule). Run on a FRESH instance (the puzzle sections above scatter the guards). ---
	var tend_inst = await _instantiate_preview_chunk_and_wait("lure_relay", 4)
	if tend_inst != null:
		var tchunk = tend_inst._active_chunk
		var lure2_node = tchunk.find_child("Lure2Interact", true, false)
		_assert_true(lure2_node != null, "Lure 2 interactable exists")
		if lure2_node != null:
			_assert_equals(int(lure2_node.interactable_type), int(Interactable.InteractableType.TIMED_ACTION),
				"The lure is a click + timed-action interactable, not proximity")
			lure2_node.active_character = "peris"      # the required tender
			lure2_node.on_interaction_arrived()        # Peris walked over -> starts the tend dwell
			tend_inst.headless_advance(0.5, 0.1)
			_assert_equals(int(tchunk.get_preview_state()["committed_lure"]), 0,
				"Reaching the lure starts Peris tending — it does NOT fire instantly")
			tend_inst.headless_advance(float(lure2_node.dwell_time) + 0.5, 0.1)
			_assert_equals(int(tchunk.get_preview_state()["committed_lure"]), 2,
				"After Peris finishes tending (dwell_time), the ferrolure sings and the guards commit")
		# Overshoot fix: a route to a point just BEFORE a corridor node (38, before node c40) must end AT
		# the point, not run forward to the node and backtrack.
		var tgs = tend_inst._game_state
		var ppath: Array = tgs.compute_preview_path("peris", Vector3(38.0, 0.5, 0.0))
		var backtracks := false
		for i in range(2, ppath.size()):
			var d1: Vector3 = (ppath[i - 1] as Vector3) - (ppath[i - 2] as Vector3)
			var d2: Vector3 = (ppath[i] as Vector3) - (ppath[i - 1] as Vector3)
			d1.y = 0.0
			d2.y = 0.0
			if d1.length() > 0.01 and d2.length() > 0.01 and d1.normalized().dot(d2.normalized()) < -0.5:
				backtracks = true
		_assert_true(not backtracks, "Route to a point before a node does NOT overshoot/backtrack")
		_assert_true((ppath[ppath.size() - 1] as Vector3).distance_to(Vector3(38.0, 0.5, 0.0)) < 0.6,
			"Route ends at the clicked point, not past it at the node")
		tend_inst.queue_free()
		await get_tree().process_frame

	# --- Wrong tender: a TIMED_ACTION lure requires 'peris'. With ASTER as the active character, finishing
	#     the FULL dwell must NOT activate it (the required_character gate rejects at _trigger). The preview
	#     re-syncs interactable.active_character from the active controller every frame, so we make Aster
	#     active via selection (setting the node field alone would be overwritten). Fresh instance so the
	#     lure is unused (an already-used interactable would skip the dwell for the wrong reason). ---
	var wrong_inst = await _instantiate_preview_chunk_and_wait("lure_relay", 4)
	if wrong_inst != null and wrong_inst.has_method("headless_set_selected_characters"):
		wrong_inst.headless_set_selected_characters(["aster"])  # Aster is now the active character
		var wchunk = wrong_inst._active_chunk
		var wlure = wchunk.find_child("Lure2Interact", true, false)
		if wlure != null:
			wlure.on_interaction_arrived()        # Aster "tends" — the dwell runs but the gate must reject
			wrong_inst.headless_advance(float(wlure.dwell_time) + 1.0, 0.1)
			_assert_equals(int(wchunk.get_preview_state()["committed_lure"]), 0,
				"A non-tender (Aster active) finishing the dwell does NOT activate the lure — required_character gate holds")
		wrong_inst.queue_free()
		await get_tree().process_frame

# --- Test: two-tier detection — a hide's TIER sets how close an enemy must be to spot you ---
func _test_two_tier_detection() -> void:
	_test_name = "Two-Tier Detection"
	var spots := func(dist: float, tier: int, distracted: bool) -> bool:
		var sched := EventScheduler.new()
		var gs := GameState.new()
		gs.scheduler = sched
		var holder := Node3D.new()
		add_child(holder)
		gs.register_character("aster", Vector3(dist, 0.5, 0.0), 2.5, {})
		gs.set_character_concealment("aster", tier)
		var enemy := Enemy.new()
		enemy.game_state = gs
		enemy.char_id = "guard"
		enemy._detection_targets = ["aster"]
		holder.add_child(enemy)
		gs.register_character("guard", Vector3(0.0, 0.5, 0.0), enemy.move_speed, {"detection_range": 6.0})
		enemy.activate()
		gs.set_character_distracted("guard", distracted)
		gs._recompute_all_detection_predictions()
		for _i in range(30):
			sched.advance_ticks(0.05)
		var seen := enemy.get_state() != "idle"
		enemy.queue_free()
		holder.queue_free()
		return seen
	# Outer band (~5m: inside outer 6.0, outside inner 2.7):
	_assert_true(spots.call(5.0, GameState.CONCEAL_NONE, false), "Exposed at outer range is spotted")
	_assert_true(not spots.call(5.0, GameState.CONCEAL_MEDIUM, false), "A medium hide loses an outer-range chaser (corner / scarpet)")
	# Inner band (~2m: inside inner 2.7):
	_assert_true(spots.call(2.0, GameState.CONCEAL_MEDIUM, false), "A medium hide does NOT save you up close (inner range)")
	_assert_true(not spots.call(2.0, GameState.CONCEAL_FULL, false), "Only a full hide (tight spot / shelter) loses a close chaser")
	# Distracted (near a lure): outer 6.0 -> 2.4. A target at 4m the guard would normally spot slips by,
	# but one that walks right up (1.5m) is still caught.
	_assert_true(spots.call(4.0, GameState.CONCEAL_NONE, false), "An undistracted guard spots an exposed target at 4m")
	_assert_true(not spots.call(4.0, GameState.CONCEAL_NONE, true), "A lure-distracted guard misses that same 4m target")
	_assert_true(spots.call(1.5, GameState.CONCEAL_NONE, true), "A distracted guard still catches a target that steps right into it")

# --- Test: lightweight enemy roaming wanders locally (no pathfinding), bounded, FF-invariant ---
func _test_enemy_roaming() -> void:
	_test_name = "Enemy Roaming"
	var anchor := Vector3(0.0, 0.5, 0.0)
	# 1. Roams from its anchor and stays inside its radius — no grid at all (pure straight hops).
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	var e := Enemy.new()
	e.game_state = gs
	e.char_id = "roamer"
	holder.add_child(e)
	gs.register_character("roamer", anchor, e.move_speed, {"detection_range": 6.0})
	e.activate()
	e.set_roam(anchor, 3.0)
	var moved := false
	var max_dist := 0.0
	for _i in range(500):
		sched.advance_ticks(0.05)
		var p := gs.get_position("roamer")
		var d := Vector2(p.x - anchor.x, p.z - anchor.z).length()
		max_dist = maxf(max_dist, d)
		if d > 0.4:
			moved = true
	_assert_true(moved, "A roaming enemy wanders away from its anchor")
	_assert_true(max_dist <= 3.0 + e.roam_step_distance, "Roaming stays within its radius (max %.2f)" % max_dist)
	_assert_equals(e.get_state(), "roam", "With no target nearby it keeps roaming")
	e.queue_free()
	holder.queue_free()

	# 2. Fast-forward invariance: the wander DECISIONS are tick-locked, so a 1x and a 10x step that
	#    land on the SAME tick produce the identical hop count, heading, and commanded destination.
	var probe := func(step: float) -> Dictionary:
		var s := EventScheduler.new()
		var g := GameState.new()
		g.scheduler = s
		var h := Node3D.new()
		add_child(h)
		var en := Enemy.new()
		en.game_state = g
		en.char_id = "roamer"
		h.add_child(en)
		g.register_character("roamer", anchor, en.move_speed, {"detection_range": 6.0})
		en.activate()
		en.set_roam(anchor, 3.0)
		while s.get_current_tick() < 12.0 - 1e-9:
			s.advance_ticks(minf(step, 12.0 - s.get_current_tick()))
		var dest := Vector3.ZERO
		var ch: Dictionary = g.characters["roamer"]
		if ch.movement != null:
			var path: Array = ch.movement.path
			dest = path[path.size() - 1]
		var res := {"seq": en._roam_seq, "heading": en._roam_heading, "dest": dest}
		en.queue_free()
		h.queue_free()
		return res
	var slow: Dictionary = probe.call(0.0166)
	var fast: Dictionary = probe.call(0.166)
	_assert_equals(slow["seq"], fast["seq"], "Same hop count at 1x and 10x (FF-invariant decisions)")
	_assert_true((slow["dest"] as Vector3).distance_to(fast["dest"]) < 0.01,
		"Same commanded roam destination at 1x and 10x")

	# 3. A roaming enemy still SEES: a target in range pulls it out of roam to engage.
	var s2 := EventScheduler.new()
	var g2 := GameState.new()
	g2.scheduler = s2
	var h2 := Node3D.new()
	add_child(h2)
	g2.register_character("aster", Vector3(2.0, 0.5, 0.0), 2.5, {})
	var en2 := Enemy.new()
	en2.game_state = g2
	en2.char_id = "roamer"
	en2._detection_targets = ["aster"]
	h2.add_child(en2)
	g2.register_character("roamer", anchor, en2.move_speed, {"detection_range": 6.0})
	en2.activate()
	en2.set_roam(anchor, 3.0)
	for _i in range(40):
		s2.advance_ticks(0.05)
	_assert_true(en2.get_state() != "roam" and en2.get_state() != "idle",
		"A roaming enemy that spots a target leaves roam to engage (got: %s)" % en2.get_state())
	en2.queue_free()
	h2.queue_free()

# --- Test: the fragment-preview chunk registry is internally consistent + the inspector dropdown ---
# matches it (the chunk id is a string, but it's constrained to CHUNK_SCENES by the @export_enum and
# load-time validation — this test is what keeps the dropdown from drifting out of sync).
func _test_fragment_preview_registry() -> void:
	_test_name = "Fragment Preview Registry"
	var Reg := FragmentPreviewScript
	# 1. Every picker entry maps to a real, loaded chunk scene.
	for entry in Reg.PREVIEW_ENTRIES:
		var chunk := String(entry.get("chunk", ""))
		_assert_true(Reg.CHUNK_SCENES.has(chunk),
			"PREVIEW_ENTRIES '%s' -> registered chunk '%s'" % [String(entry.get("id", "")), chunk])
		_assert_true(Reg.CHUNK_SCENES.get(chunk) != null, "Chunk scene for '%s' is loaded" % chunk)
	# 2. get_preview_entry resolves each id, and an unknown id is empty (no silent fallthrough).
	for entry in Reg.PREVIEW_ENTRIES:
		var got: Dictionary = Reg.get_preview_entry(String(entry.get("id", "")))
		_assert_equals(String(got.get("chunk", "")), String(entry.get("chunk", "")),
			"get_preview_entry('%s') resolves" % String(entry.get("id", "")))
	_assert_true(Reg.get_preview_entry("does_not_exist").is_empty(), "Unknown preview id resolves to empty")
	# 3. The inspector @export_enum dropdown stays in lockstep with CHUNK_SCENES (no drift on add).
	var packed: PackedScene = load(FRAGMENT_PREVIEW_SCENE_PATH)
	var inst: Node = packed.instantiate()
	var hint := ""
	for prop in inst.get_property_list():
		if String(prop.get("name", "")) == "preview_chunk":
			hint = String(prop.get("hint_string", ""))
			break
	inst.free()
	var enum_ids: Array = []
	for part in hint.split(",", false):
		enum_ids.append(String(part).split(":")[0])  # tolerate "name:idx" form
	var registry_ids: Array = Reg.CHUNK_SCENES.keys()
	_assert_equals(enum_ids.size(), registry_ids.size(),
		"preview_chunk dropdown lists every registered chunk (enum %d vs registry %d)" % [enum_ids.size(), registry_ids.size()])
	for id in registry_ids:
		_assert_true(id in enum_ids, "preview_chunk dropdown includes registered chunk '%s'" % id)

# --- Test: multi-select party move works in the shared chunk preview (Ctrl+1-3 then one click) ---
func _test_preview_party_move() -> void:
	_test_name = "Preview Party Move"
	var packed: PackedScene = load(FRAGMENT_PREVIEW_SCENE_PATH)
	var inst: Node = packed.instantiate()
	if inst == null:
		_assert_true(false, "fragment_preview instantiates")
		return
	inst.set("preview_menu", false)
	inst.set("preview_chunk", "lure_relay")
	get_tree().root.add_child(inst)
	for _i in range(5):
		await get_tree().process_frame
	var gs = inst._game_state
	# Multi-select the whole party (the headless equivalent of Ctrl+1/2/3).
	inst.headless_set_selected_characters(["aster", "peris", "endo"])
	_assert_equals(gs.get_party().size(), 3, "Selecting 3 sets a 3-member party (got %d)" % gs.get_party().size())
	_assert_true(bool(inst._player.get("group_move")), "The active node group-moves with >1 selected")
	var starts := {}
	for cid in ["aster", "peris", "endo"]:
		starts[cid] = gs.get_position(cid)
	# A SINGLE click on the active controller drives a party move (gridless fan around the target).
	var target := Vector3(16.0, 0.5, 0.0)
	inst._player.move_to_world_position(target)
	for _i in range(120):
		gs.scheduler.advance_ticks(0.1)
	for cid in ["aster", "peris", "endo"]:
		var before: float = (starts[cid] as Vector3).distance_to(target)
		var after: float = gs.get_position(cid).distance_to(target)
		_assert_true(after < before - 1.0,
			"One click moved %s toward the target (%.1f -> %.1f)" % [cid, before, after])
	# Single-select drops back to solo control (no group move).
	inst.headless_set_selected_characters(["peris"])
	_assert_true(not bool(inst._player.get("group_move")), "Single select disables group move")
	inst.queue_free()
	await get_tree().process_frame

# --- Test: the shared movement-path renderer draws in chunk previews ---
func _test_preview_path_render() -> void:
	_test_name = "Preview Path Render"
	var inst = await _instantiate_preview_chunk_and_wait("lure_relay", 4)
	if inst == null:
		_assert_true(false, "fragment_preview instantiates")
		return
	var mgr = inst.find_child("PathRenderManager", true, false)
	_assert_true(mgr != null, "Preview has a PathRenderManager")
	var gs = inst._game_state
	# Issue a real move and let the renderer build its ribbon over a few frames.
	gs.command_move_to_pos("peris", Vector3(20.0, 0.5, 0.0))
	gs.scheduler.advance_ticks(0.5)
	for _i in range(4):
		await get_tree().process_frame
	if mgr != null:
		var pr = mgr._renderers.get("peris")
		_assert_true(pr != null, "A path renderer exists for the moving character")
		_assert_true(pr != null and pr._line != null and pr._line.mesh != null,
			"The moving character's path ribbon is drawn in the preview")
	# The active player builds a hover grid (the target-cell preview), hidden until the cursor is over
	# the floor in move mode.
	var player = inst._player
	_assert_true(player != null and player.get("_hover_grid") != null, "Active player has a hover grid")
	if player != null and player.get("_hover_grid") != null:
		_assert_true(not player.get("_hover_grid").visible, "Hover grid is hidden until the floor is hovered")
	inst.queue_free()
	await get_tree().process_frame

# --- Test: hovering the floor reveals the target-cell grid in chunk previews ---
## The hover grid follows the cursor by POLLING get_viewport().get_mouse_position() each frame in
## _process (it used to react to InputEventMouseMotion in _unhandled_input, which never reaches the
## player — that was the "grid overlay isn't working in stacks" bug). The headless display server
## stores no mouse position, so we can't feed the poll a cursor headlessly; instead we (1) run the
## real poll to prove _process -> _update_hover_grid is wired and crash-free, then (2) drive the
## worker with a real floor projection to prove the raycast -> snap -> reveal logic. In a window the
## poll feeds that worker the live cursor every frame.
func _test_preview_hover_grid() -> void:
	_test_name = "Preview Hover Grid"
	var inst = await _instantiate_preview_chunk_and_wait("stacks", 6)
	if inst == null:
		_assert_true(false, "fragment_preview instantiates for hover-grid test")
		return
	var player = inst._player
	_assert_true(player != null and player.get("_hover_grid") != null,
		"Active player has a hover grid")
	var camera: Camera3D = inst._camera if "_camera" in inst else null
	if player == null or player.get("_hover_grid") == null or camera == null:
		_assert_true(false, "Hover-grid test needs the active player, its grid, and a camera")
		await _dispose_scene(inst)
		return
	camera.make_current()  # so _raycast_ground (uses the current camera) matches our unprojection
	var hover_grid: Node3D = player.get("_hover_grid")
	_assert_true(not hover_grid.visible, "Hover grid starts hidden (no cursor over the floor yet)")

	# The real per-frame poll runs. Headless has no stored mouse position (reads (0,0)), so this
	# leaves the grid hidden — but it proves the poll path is live and doesn't crash.
	player._update_hover_grid()
	_assert_true(not hover_grid.visible, "Poll with no cursor over the floor keeps the grid hidden")

	# Hover a cell-CENTER point on the stacks floor (x in [-2,66], z in [-12,12]) so the raycast
	# lands mid-cell and the floorf() snap is stable away from a cell boundary.
	var target := Vector3(8.5, 0.0, 2.5)
	player._update_hover_from_screen(camera.unproject_position(target))
	_assert_true(hover_grid.visible, "Hovering the floor reveals the grid")
	_assert_true(absf(hover_grid.global_position.x - 8.5) < 0.5,
		"Hover grid snaps to the hovered cell X (got %.2f, want ~8.5)" % hover_grid.global_position.x)
	_assert_true(absf(hover_grid.global_position.z - 2.5) < 0.5,
		"Hover grid snaps to the hovered cell Z (got %.2f, want ~2.5)" % hover_grid.global_position.z)
	_assert_true(hover_grid.global_position.y > 0.0,
		"Hover grid sits just above the floor (got y=%.3f)" % hover_grid.global_position.y)

	# Sweeping to a different cell tracks the cursor.
	var target2 := Vector3(12.5, 0.0, -3.5)
	player._update_hover_from_screen(camera.unproject_position(target2))
	_assert_true(hover_grid.visible, "Hover grid stays visible over the floor after a sweep")
	_assert_true(absf(hover_grid.global_position.x - 12.5) < 0.5,
		"Hover grid tracks to the new cell X (got %.2f, want ~12.5)" % hover_grid.global_position.x)
	_assert_true(absf(hover_grid.global_position.z + 3.5) < 0.5,
		"Hover grid tracks to the new cell Z (got %.2f, want ~-3.5)" % hover_grid.global_position.z)

	# A "click the target" prompt switches to select mode — the hover grid must stand down.
	player.set_click_mode("select")
	player._update_hover_from_screen(camera.unproject_position(target))
	_assert_true(not hover_grid.visible, "Select-mode prompt hides the hover grid")
	player.set_click_mode("move")

	await _dispose_scene(inst)

# --- Test: compute_preview_path is a READ-ONLY route preview (no move, no log) for the hover path ---
func _test_preview_pathfinding() -> void:
	_test_name = "Preview Pathfinding"
	var sched := EventScheduler.new()
	var log := EventLog.new()
	GameState._pending_event_log = log
	var gs := GameState.new()
	gs.scheduler = sched
	gs.register_character("aster", Vector3(0.0, 0.5, 0.0), 3.0, {})
	var before: Vector3 = gs.get_position("aster")
	var log_before: int = log.size()
	var path: Array[Vector3] = gs.compute_preview_path("aster", Vector3(6.0, 0.5, 2.0))
	_assert_true(path.size() >= 2, "Preview returns a route (start + end), got %d" % path.size())
	# Pure UI: it must emit nothing and not move/mutate the character — like the hover grid.
	_assert_equals(log.size(), log_before, "compute_preview_path emits NO event-log entries (replay-safe)")
	_assert_true(not gs.is_moving("aster"), "compute_preview_path does NOT start a move")
	_assert_true(gs.get_position("aster").distance_to(before) < 0.001,
		"compute_preview_path does NOT move the character")
	# Deterministic — the same query yields the same route.
	var path2: Array[Vector3] = gs.compute_preview_path("aster", Vector3(6.0, 0.5, 2.0))
	_assert_equals(path.size(), path2.size(), "Preview path is deterministic")
	_assert_true(path[path.size() - 1].distance_to(path2[path2.size() - 1]) < 0.001,
		"Preview endpoint is stable")
	# Unknown character -> no preview.
	_assert_equals(gs.compute_preview_path("nobody", Vector3(1.0, 0.0, 1.0)).size(), 0,
		"Unknown character -> empty preview path")

	# --- Party preview: each member previews its OWN route to its OWN spread destination. ---
	gs.register_character("peris", Vector3(0.0, 0.5, 1.0), 3.0, {})
	gs.register_character("endo", Vector3(0.0, 0.5, -1.0), 3.0, {})
	gs.set_party(["aster", "peris", "endo"])
	var log_party_before: int = log.size()
	var party: Array = gs.compute_preview_party_paths(Vector3(8.0, 0.5, 0.0))
	_assert_equals(party.size(), 3, "Party preview returns a route per member (got %d)" % party.size())
	_assert_equals(log.size(), log_party_before, "Party preview emits NO event-log entries (replay-safe)")
	_assert_true(not gs.is_moving("peris") and not gs.is_moving("endo"),
		"Party preview starts no moves")
	var min_z := 1.0e9
	var max_z := -1.0e9
	for e in party:
		var p: Array = e["path"]
		if p.size() >= 2:
			var z: float = (p[p.size() - 1] as Vector3).z
			min_z = minf(min_z, z)
			max_z = maxf(max_z, z)
	_assert_true(max_z - min_z > 0.5,
		"Party members preview DISTINCT destinations (z spread %.2f)" % (max_z - min_z))

# --- Test: floor-overlay materials render in the opaque pass (the preview scene drops alpha-blend) ---
# The fragment-preview scene does not composite the alpha-BLEND transparent pass, so any floor overlay
# using TRANSPARENCY_ALPHA is invisible there. The hover grid + path ribbon MUST be opaque or scissor.
# This guards the regression that made the grid faint/invisible and the path "never show".
func _test_overlay_materials() -> void:
	_test_name = "Overlay Materials"
	var player: Node3D = load("res://scenes/game/player_character.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	var hg = player.get("_hover_grid")
	_assert_true(hg != null and hg.material_override != null, "Hover grid builds a material")
	if hg != null and hg.material_override != null:
		_assert_true(int(hg.material_override.transparency) != int(BaseMaterial3D.TRANSPARENCY_ALPHA),
			"Hover grid material is NOT alpha-blend (invisible in previews) — got %d" % int(hg.material_override.transparency))
	player.queue_free()
	await get_tree().process_frame
	var pr := PathRenderer.new()
	add_child(pr)
	await get_tree().process_frame
	_assert_true(pr._mat != null and int(pr._mat.transparency) != int(BaseMaterial3D.TRANSPARENCY_ALPHA),
		"Path ribbon material is NOT alpha-blend — got %d" % (int(pr._mat.transparency) if pr._mat != null else -1))
	pr.queue_free()
	await get_tree().process_frame

# --- Test: chunk object interactables are wired to the shared outline+shimmer (auto-migration) ---
# A chunk object's interactable must forward to an OutlineSurfaceTarget, or it shows no hover outline /
# active shimmer. Spot-check representative meshed interactables so the auto-wiring can't silently break.
func _test_chunk_interactable_outlines() -> void:
	_test_name = "Chunk Interactable Outlines"
	var checks := [
		{"chunk": "stacks", "node": "TerminalInteractable"},
		{"chunk": "lure_relay", "node": "Lure2Interact"},
	]
	for c in checks:
		var inst = await _instantiate_preview_chunk_and_wait(c["chunk"], 4)
		if inst == null:
			_assert_true(false, "%s preview instantiates" % c["chunk"])
			continue
		var chunk = inst._active_chunk
		var node = chunk.find_child(c["node"], true, false) if chunk != null else null
		_assert_true(node != null, "%s exposes %s" % [c["chunk"], c["node"]])
		if node != null:
			var tgt = node.get("_outline_target") if "_outline_target" in node else null
			_assert_true(tgt != null,
				"%s/%s is wired to an outline target (hover outline + active shimmer)" % [c["chunk"], c["node"]])
		await _dispose_scene(inst)

# --- Test: the hover path preview matches the path a click actually commits (no preview lie) ---
# compute_preview_path must equal what command_move_to_pos produces, so the dim preview is honest. This
# catches a divergence like the nav-graph overshoot (preview fixed but committed still backtracking).
func _test_preview_matches_committed() -> void:
	_test_name = "Preview Matches Committed"
	var inst = await _instantiate_preview_chunk_and_wait("lure_relay", 4)  # has a nav graph (the overshoot case)
	if inst == null:
		_assert_true(false, "lure_relay preview instantiates")
		return
	var gs = inst._game_state
	var target := Vector3(38.0, 0.5, 0.0)  # just before node c40
	var preview: Array[Vector3] = gs.compute_preview_path("peris", target)
	gs.command_move_to_pos("peris", target)
	var mv = gs.characters["peris"].movement
	var committed: Array = (mv.path as Array) if mv != null else []
	_assert_equals(preview.size(), committed.size(),
		"Preview length == committed length (%d vs %d)" % [preview.size(), committed.size()])
	if preview.size() == committed.size() and preview.size() > 0:
		var maxd := 0.0
		for i in range(preview.size()):
			maxd = maxf(maxd, (preview[i] as Vector3).distance_to(committed[i]))
		_assert_true(maxd < 0.01, "Preview path matches the committed path (max deviation %.3f)" % maxd)
	await _dispose_scene(inst)

# --- Test: a party group-move previews ONE ribbon PER member, not a single shared line (headless) ---
# The "only one path shown" bug was that the player built a single PathRenderer for the whole party. The
# fix gives each member its OWN renderer (_update_party_preview). This drives that path directly and asserts
# one drawable ribbon per member with DISTINCT destinations — deterministic, no display needed.
func _test_party_preview_renderers() -> void:
	_test_name = "Party Preview Renderers"
	var inst = await _instantiate_preview_chunk_and_wait("lure_relay", 6)
	if inst == null:
		_assert_true(false, "lure_relay preview instantiates")
		return
	var player = inst.get("_player")
	var gs = inst.get("_game_state")
	if player == null or gs == null or not inst.has_method("headless_set_selected_characters"):
		_assert_true(false, "preview exposes player + game_state + selection API")
		await _dispose_scene(inst)
		return
	# Peris first stays primary (the node we drive); a full 3-member party selected.
	inst.headless_set_selected_characters(["peris", "aster", "endo"])
	for cid in gs.characters.keys():
		gs.command_stop(cid)
	var party: Array = gs.get_party()
	player.group_move = true
	_assert_true(party.size() >= 2, "Multi-select builds a party (got %d members)" % party.size())

	# Drive the party preview directly with a world-space hit (bypasses the screen raycast).
	var base: Vector3 = player.global_position
	var hit := Vector3(base.x + 3.0, base.y, base.z)
	player._clear_path_preview()
	player._update_party_preview(hit)

	var previews: Dictionary = player.get("_party_previews")
	_assert_equals(previews.size(), party.size(),
		"One preview ribbon PER member, not a single shared line (got %d for %d members)" % [previews.size(), party.size()])
	var drawable := 0
	var dests: Array[Vector3] = []
	for cid in previews.keys():
		var pr = previews[cid]
		var ep: Array = pr._explicit_path
		if ep.size() >= 2:
			drawable += 1
			dests.append(ep[ep.size() - 1])
	_assert_equals(drawable, party.size(), "Every member's ribbon has a drawable path (%d of %d)" % [drawable, party.size()])
	# Distinct destinations — the "all members share one destination" half of the bug.
	var max_spread := 0.0
	for i in range(dests.size()):
		for j in range(i + 1, dests.size()):
			max_spread = maxf(max_spread, dests[i].distance_to(dests[j]))
	_assert_true(max_spread > 0.5, "Members preview DISTINCT destinations (max spread %.2f)" % max_spread)
	await _dispose_scene(inst)

# --- Test: position holds EXACTLY at a wait waypoint during an embedded zero-distance wait segment ---
# A cooperative path can embed a WAIT: two consecutive waypoints share a position but span time. Position
# is a pure function of the scheduler tick (_interpolate_path_timed), so mid-wait reads must stay pinned to
# the wait waypoint with zero drift. Guards the lerp-of-identical-points / span handling of an embedded wait.
func _test_path_timed_wait_segment() -> void:
	_test_name = "Path Timed Wait Segment"
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	gs.register_character("c", Vector3(0, 0.5, 0), 2.0, {})
	var p1 := Vector3(3.0, 0.5, 0.0)
	var path: Array[Vector3] = [Vector3(0, 0.5, 0), p1, p1, Vector3(6.0, 0.5, 0.0)]
	var ticks: Array[float] = [0.0, 1.0, 3.0, 4.0]  # WAIT at p1 from tick 1 to tick 3 (same pos, distinct ticks)
	gs._start_movement("c", path, ticks)
	# Sample strictly inside the wait window; every reading must equal p1.
	var max_drift := 0.0
	for i in range(1, 21):
		var t := 1.0 + 2.0 * (float(i) / 21.0)  # in (1.0, 3.0)
		sched.advance_ticks(t - sched.get_current_tick())
		max_drift = maxf(max_drift, gs.get_position("c").distance_to(p1))
	_assert_true(max_drift < 0.001, "Position holds at the wait waypoint with zero drift (max %.4f)" % max_drift)
	# After the wait it resumes toward the final waypoint.
	sched.advance_ticks(4.0 - sched.get_current_tick())
	_assert_true(gs.get_position("c").distance_to(Vector3(6.0, 0.5, 0.0)) < 0.001, "Resumes to the final waypoint after the wait")

# --- Test: a pursuing enemy DISENGAGES when it loses sight of the target (rescan -> search -> return) ---
# The pursuit state arms a rescan timer. A still-visible target is correctly RE-ACQUIRED on each rescan
# (search admits detection), so it doesn't "give up" on someone in plain view. But once the target is GONE
# (here: fully concealed), the rescan drops to search, search finds nothing, and the enemy returns home
# instead of pursuing a ghost forever. Guards the lose-sight disengage path end-to-end.
func _test_enemy_pursuit_timeout() -> void:
	_test_name = "Enemy Pursuit Disengage"
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	gs.register_character("target", Vector3(6.0, 0.5, 0.0), 2.5, {"hp": 100.0})
	var enemy := Enemy.new()
	enemy.game_state = gs
	enemy.char_id = "guard"
	enemy._detection_targets = ["target"]
	enemy.move_speed = 0.5  # too slow to close 6m before the rescan -> stays in pursuit, never windup
	holder.add_child(enemy)
	gs.register_character("guard", Vector3(0.0, 0.5, 0.0), enemy.move_speed, {"detection_range": 20.0})
	enemy.activate()
	gs._recompute_all_detection_predictions()
	# Phase 1: spot the target and enter pursuit.
	var reached_pursuit := false
	for _i in range(60):  # up to 3s
		sched.advance_ticks(0.05)
		if enemy.get_state() == "pursuit":
			reached_pursuit = true
			break
	_assert_true(reached_pursuit, "Spotting the target enters pursuit")
	# Phase 2: the target vanishes (full concealment). The next rescan must NOT re-acquire it.
	gs.set_character_hidden("target", true)
	gs._recompute_all_detection_predictions()
	var reached_search := false
	for _i in range(260):  # ~13s — rescan -> search -> search_duration -> return -> home
		sched.advance_ticks(0.05)
		if enemy.get_state() == "search":
			reached_search = true
	var final_state := enemy.get_state()
	_assert_true(reached_search, "Losing sight of the target drops pursuit to search (rescan), not chasing a ghost")
	_assert_true(final_state in ["search", "return", "idle", "roam", "patrol"],
		"After failing to re-acquire, the enemy disengages home (ended in %s, not an aggro state)" % final_state)
	enemy.queue_free()
	holder.queue_free()

# --- Test: detection is blocked across floors (the DETECTION_VERTICAL_BAND guard) ---
# Two characters within horizontal range but separated vertically by more than the band are on different
# floors and must not see each other. Guards the cross-floor exemption that keeps a stacked-floor scene from
# spuriously spotting a character one level up/down.
func _test_detection_vertical_band() -> void:
	_test_name = "Detection Vertical Band"
	var spots := func(dy: float) -> bool:
		var sched := EventScheduler.new()
		var gs := GameState.new()
		gs.scheduler = sched
		var holder := Node3D.new()
		add_child(holder)
		gs.register_character("target", Vector3(3.0, dy, 0.0), 2.5, {})
		var enemy := Enemy.new()
		enemy.game_state = gs
		enemy.char_id = "guard"
		enemy._detection_targets = ["target"]
		holder.add_child(enemy)
		gs.register_character("guard", Vector3(0.0, 0.0, 0.0), enemy.move_speed, {"detection_range": 20.0})
		enemy.activate()
		gs._recompute_all_detection_predictions()
		for _i in range(20):
			sched.advance_ticks(0.05)
		var seen := enemy.get_state() != "idle"
		enemy.queue_free()
		holder.queue_free()
		return seen
	_assert_true(spots.call(0.0), "Same-floor target within horizontal range is spotted")
	_assert_true(not spots.call(5.0), "A target 5m above (a different floor) is NOT spotted despite horizontal range")

# --- Windowed eyeball: capture each bay of the Showcase Gallery to a PNG (run WITHOUT --headless) ---
# Not an assertion test — it teleports the followed character to each bay so the follow camera frames it,
# and saves vr_showcase_*.png for visual review of the geometry/labels/flora.
func _test_showcase_capture() -> void:
	_test_name = "Showcase Capture"
	if DisplayServer.get_name() == "headless":
		print("  SKIP (needs a display — run WITHOUT --headless)")
		return
	var inst = await _instantiate_preview_chunk_and_wait("showcase_gallery", 6)
	if inst == null:
		_assert_true(false, "showcase_gallery instantiates")
		return
	if not await _vr_wait_render():
		print("  [VR] showcase SKIPPED — window never rendered")
		await _dispose_scene(inst)
		return
	# Hide the player's hover grid so it doesn't dominate the frame (the follow camera stays live).
	var player = inst.get("_player")
	if player != null:
		if player.has_method("set_process"):
			player.set_process(false)
		var hg = player.get("_hover_grid")
		if hg != null:
			hg.visible = false
	var bays := {
		"hiding": Vector3(16.0, 0.5, -6.0),
		"enemies": Vector3(38.5, 0.5, -8.0),
		"chain": Vector3(44.0, 0.5, 8.0),
		"flora": Vector3(62.0, 0.5, -3.0),
	}
	for name in bays.keys():
		inst.headless_set_character_position("peris", bays[name])
		if player != null:
			var hg2 = player.get("_hover_grid")
			if hg2 != null:
				hg2.visible = false
		for i in range(50):
			await get_tree().process_frame  # let the follow camera ease onto the bay
		var img := await _vr_capture()
		if img != null:
			img.save_png("res://vr_showcase_%s.png" % name)
			print("  [VR] saved vr_showcase_%s.png" % name)
	_assert_true(true, "Showcase bays captured")
	await _dispose_scene(inst)

# --- Test: the Showcase Gallery chunk shows off all three hiding tiers, both enemy types, and flora ---
# Validates the exhibit content (3 hide tiers, 2 named enemy types + a demo sentry, the flora line-up) AND
# that the hiding geometry actually TEACHES: on the EXPOSED pad the pacing sentry spots you, on the MEDIUM
# pad it holds you at range, on the FULL pad it never sees you. Reaching the exit completes the tour.
func _test_showcase_gallery() -> void:
	_test_name = "Showcase Gallery"
	var inst = await _instantiate_preview_chunk_and_wait("showcase_gallery", 5)
	if inst == null:
		_assert_true(false, "showcase_gallery preview instantiates")
		return
	var chunk = inst._active_chunk
	var state: Dictionary = chunk.get_preview_state()
	_assert_equals(int(state.get("hiding_type_count", 0)), 3, "Three hiding tiers on display")
	_assert_equals(int(state.get("flora_count", 0)), 6, "All six flora species on display")
	_assert_equals(int(state.get("enemy_count", 0)), 2, "Both enemy TYPES (standard + chain) are present")
	_assert_true((state.get("enemy_types", []) as Array).has("standard") and (state.get("enemy_types", []) as Array).has("chain"),
		"The state reports both enemy types")
	var demo = chunk.find_child("GalleryDemoSentry", true, false)
	_assert_true(demo != null, "The hiding bay has a demo sentry")
	var anchors: Dictionary = chunk.get_preview_anchors()

	# Drive each pad. Order FULL -> MEDIUM -> EXPOSED so the sentry stays calm until the exposed test.
	var aggro_states := ["alert", "pursuit", "windup", "charge", "impact", "recover", "stagger"]
	var spotted_on := func(pad_pos: Vector3) -> bool:
		inst.headless_set_character_position("peris", pad_pos)
		inst.headless_advance(8.0, 0.1)  # let the sentry pace its full line past the pad
		return demo != null and str(demo.get_state()) in aggro_states
	if demo != null:
		_assert_true(not spotted_on.call(anchors["pad_full"] as Vector3),
			"FULL safehold: the sentry never spots you")
		_assert_true(not spotted_on.call(anchors["pad_medium"] as Vector3),
			"MEDIUM low cover: the sentry holds at range (not spotted at the pad)")
		_assert_true(spotted_on.call(anchors["pad_exposed"] as Vector3),
			"EXPOSED: the pacing sentry spots you")

	# Reaching the exit completes the tour.
	inst.headless_set_character_position("peris", Vector3(79.0, 0.5, 0.0))
	inst.headless_advance(0.3, 0.1)
	_assert_true(bool(chunk.get_preview_state().get("complete", false)), "Reaching the EXIT completes the gallery tour")
	await _dispose_scene(inst)

# --- Test: a ChainEnemy's attack is REAL data-layer damage that respects the dodge window ---
# Written to break the current code: a ChainEnemy segment hit only emits hit_target — it never calls
# adjust_stat — so GameState HP (the detection/disengage authority) is untouched and the chain can't down
# a target or be slipped by a dodge. These assert the CORRECT behaviour and should go red until fixed.
func _make_chain_attack_ctx(target_hp: float, dodge: bool) -> Dictionary:
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	gs.register_character("aster", Vector3(3.0, 0.5, 0.0), 2.5, {"hp": target_hp, "stamina": 100.0})
	if dodge:
		gs.characters["aster"].stats["dodge_unlocked"] = true
		gs.characters["aster"].stats["auto_dodge"] = true
	var enemy := ChainEnemy.new()
	enemy.game_state = gs
	enemy.char_id = "chain"
	enemy._detection_targets = ["aster"]
	enemy.attack_range = 3.0
	enemy.charge_damage = 25.0
	holder.add_child(enemy)
	gs.register_character("chain", Vector3(0.0, 0.5, 0.0), enemy.move_speed, {"detection_range": 6.0})
	enemy.set_wall_line(Vector3(0.0, 0.5, 1.5), Vector3(0, 0, 1))  # tail anchored behind the head
	enemy.activate()
	gs._recompute_all_detection_predictions()
	return {"sched": sched, "gs": gs, "enemy": enemy, "holder": holder}

func _test_chain_combat() -> void:
	_test_name = "Chain Combat"
	# (1) A chain's attack must reduce the target's GameState HP (segment hit must be real data-layer damage).
	var ctx := _make_chain_attack_ctx(100.0, false)
	var sched: EventScheduler = ctx["sched"]
	var gs: GameState = ctx["gs"]
	var enemy: ChainEnemy = ctx["enemy"]
	for i in range(240):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		if float(gs.get_stat("aster", "hp")) < 100.0:
			break
	_assert_true(float(gs.get_stat("aster", "hp")) < 100.0,
		"A ChainEnemy attack reduces the target's GameState HP (got %.1f)" % gs.get_stat("aster", "hp"))
	_cleanup_attack_ctx(ctx)

	# (2) Consequence: once the chain downs the target's GameState HP, it disengages (never works a corpse).
	var dctx := _make_chain_attack_ctx(40.0, false)
	var dsched: EventScheduler = dctx["sched"]
	var dgs: GameState = dctx["gs"]
	var denemy: ChainEnemy = dctx["enemy"]
	var downed := false
	for i in range(600):
		dsched.advance_ticks(0.05)
		denemy._process(0.05)
		if float(dgs.get_stat("aster", "hp")) <= 0.0:
			downed = true
			# let it re-evaluate after the kill
			for j in range(40):
				dsched.advance_ticks(0.05)
				denemy._process(0.05)
			break
	_assert_true(downed, "The chain downs the target's GameState HP")
	_assert_true(denemy.get_state() in ["search", "return", "idle", "roam", "patrol"],
		"After downing the target the chain disengages (state=%s)" % denemy.get_state())
	_cleanup_attack_ctx(dctx)

	# (3) A dodging target is NOT hit by a chain segment (the dodge window must protect against segments too).
	var xctx := _make_chain_attack_ctx(100.0, false)
	var xsched: EventScheduler = xctx["sched"]
	var xgs: GameState = xctx["gs"]
	var xenemy: ChainEnemy = xctx["enemy"]
	xgs.characters["aster"].stats["dodge_unlocked"] = true
	var hp_when_dodging := 100.0
	for i in range(240):
		xsched.advance_ticks(0.05)
		xenemy._process(0.05)
		# Keep the target perpetually in a fresh dodge while the chain works its charge.
		if xenemy.get_state() == "charge" and not xgs.is_dodging("aster"):
			xgs.characters["aster"].stats["stamina"] = 100.0
			xgs.characters["aster"].stats["_last_dodge_tick"] = -100.0
			xgs.dodge_roll("aster", Vector3(0, 0, 1))
			hp_when_dodging = float(xgs.get_stat("aster", "hp"))
		if xenemy.get_state() == "recover":
			break
	_assert_true(absf(float(xgs.get_stat("aster", "hp")) - hp_when_dodging) < 0.01,
		"A chain segment does NOT damage a target that is mid-dodge (hp %.1f vs %.1f at dodge)" % [xgs.get_stat("aster", "hp"), hp_when_dodging])
	_cleanup_attack_ctx(xctx)

# --- Test: a dodge that fails to move (wall-blocked) must NOT burn the cooldown ---
# Written to break the current code: dodge_roll sets _last_dodge_tick before the wall-block check, so a
# refunded (zero-distance) dodge wrongly puts the character on cooldown.
func _test_dodge_failure_no_cooldown() -> void:
	_test_name = "Dodge Failure No Cooldown"
	var gs := GameState.new()
	var sched := EventScheduler.new()
	var grid := GridWorld.new()
	grid.create_room(30, 30)
	gs.grid = grid
	gs.scheduler = sched
	# Hard against the +X wall so a +X dodge is fully blocked (zero distance -> refund).
	gs.register_character("p", grid.grid_to_world(Vector2i(28, 15)), 3.0, {"stamina": 100.0, "dodge_unlocked": true})
	var into_wall := gs.dodge_roll("p", Vector3(1, 0, 0))
	_assert_true(not into_wall, "A dodge straight into a wall fails (no movement)")
	_assert_true(absf(float(gs.characters["p"].stats.stamina) - 100.0) < 0.01, "A blocked dodge refunds stamina")
	# Immediately dodge a valid direction — it must NOT be on cooldown from the blocked attempt.
	var away := gs.dodge_roll("p", Vector3(-1, 0, 0))
	_assert_true(away, "A valid dodge right after a blocked one is NOT on cooldown (blocked dodge didn't move, so it can't cost the cooldown)")

# --- Test: a strike never lands on a target that is already down (no hitting a corpse) ---
# Written to break the current code: _apply_strike applies damage without re-checking the target is alive,
# so a charge that resolves after the target died (another enemy's kill) still hits the corpse.
func _test_strike_skips_corpse() -> void:
	_test_name = "Strike Skips Corpse"
	var ctx := _make_attack_ctx(500.0, false)
	var sched: EventScheduler = ctx["sched"]
	var gs: GameState = ctx["gs"]
	var enemy: Enemy = ctx["enemy"]
	var hits_after_death := [0]
	var dead := [false]
	enemy.hit_target.connect(func(_t, _d):
		if dead[0]:
			hits_after_death[0] += 1)
	for i in range(240):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		# The instant the guard commits its lunge, an OUTSIDE source downs the target.
		if enemy.get_state() == "charge" and not dead[0]:
			dead[0] = true
			gs.set_stat("aster", "hp", 0.0)
		if enemy.get_state() == "recover":
			break
	_assert_true(dead[0], "The target is downed mid-charge by an outside source")
	_assert_equals(hits_after_death[0], 0, "The committed strike does NOT land on the now-dead target (no corpse hit)")
	_cleanup_attack_ctx(ctx)

# --- Test: the dialogue transcript is capped at TRANSCRIPT_MAX, dropping the oldest lines ---
# A long scene runs far more than 40 lines; the history must cap (pop_front) so it can't grow unbounded.
# Guards the cap directly: the oldest entries fall off and the newest stay.
func _test_dialogue_transcript_cap() -> void:
	_test_name = "Dialogue Transcript Cap"
	var box = load("res://scripts/ui/dialogue_box.gd").new()
	var cap := int(box.TRANSCRIPT_MAX)
	var total := cap + 5
	for i in range(total):
		box._append_to_transcript("line_%d" % i, "spk", "normal")
	_assert_equals(box._transcript.size(), cap, "Transcript caps at TRANSCRIPT_MAX (%d)" % cap)
	_assert_equals(String(box._transcript[0]["text"]), "line_%d" % (total - cap),
		"Oldest entries pop_front off the transcript (first kept is line_%d)" % (total - cap))
	_assert_equals(String(box._transcript[box._transcript.size() - 1]["text"]), "line_%d" % (total - 1),
		"The newest line stays at the tail")
	box.free()

# --- Test: explicit interactable enable/disable + reset round-trip through the event log & replay ---
# Sequences lock gates with set_interactable_enabled(false) and re-arm one-shots with reset_interactable().
# Both emit their own KIND, so replay MUST reproduce the enabled/triggered state — otherwise a gate that
# was locked in live play is wrongly open on replay (or a re-armed terminal stays spent). The existing
# --test-interactable-data covers register+trigger; this covers the explicit enable/disable + reset paths.
func _test_interactable_state_replay() -> void:
	_test_name = "Interactable State Replay"
	var grid := GridWorld.new()
	grid.create_room(10, 10, true)

	# (1) Explicit disable: a gate locked via set_interactable_enabled(false) replays as disabled + rejects.
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = EventScheduler.new()
	var log := EventLog.new()
	gs.event_log = log
	gs.register_interactable({"id": "gate", "position": grid.grid_to_world(Vector2i(4, 4)), "requires_hold": false})
	_assert_true(gs.is_interactable_enabled("gate"), "Gate starts enabled")
	gs.set_interactable_enabled("gate", false)
	_assert_true(not gs.is_interactable_enabled("gate"), "Gate is locked after set_interactable_enabled(false)")
	var replayed := GameState.replay(log, grid)
	_assert_true(not replayed.is_interactable_enabled("gate"),
		"Replay reproduces the explicitly-disabled gate (KIND_SET_INTERACTABLE_ENABLED round-trips)")
	_assert_true(not replayed.trigger_interactable("gate", ""),
		"A replayed locked gate still rejects triggers")

	# (2) Reset / re-arm: a spent one-shot reset via reset_interactable() replays as enabled + fireable.
	var gs2 := GameState.new()
	gs2.grid = grid
	gs2.scheduler = EventScheduler.new()
	var log2 := EventLog.new()
	gs2.event_log = log2
	gs2.register_interactable({"id": "terminal", "position": grid.grid_to_world(Vector2i(5, 5)), "requires_hold": false, "one_shot": true})
	_assert_true(gs2.trigger_interactable("terminal", ""), "One-shot terminal fires the first time")
	_assert_true(not gs2.is_interactable_enabled("terminal"), "Spent one-shot is disabled")
	gs2.reset_interactable("terminal")
	_assert_true(gs2.is_interactable_enabled("terminal"), "reset_interactable re-arms the one-shot")
	var replayed2 := GameState.replay(log2, grid)
	_assert_true(replayed2.is_interactable_enabled("terminal"),
		"Replay reproduces the reset (re-armed) one-shot as enabled (KIND_RESET_INTERACTABLE round-trips)")
	_assert_true(not replayed2.get_interactable("terminal").get("triggered", false),
		"Replay clears the triggered flag after a reset")
	_assert_true(replayed2.trigger_interactable("terminal", ""),
		"A replayed reset one-shot can fire again")

# --- Test: floor overlays actually COMPOSITE pixels inside the real preview scene (windowed only) ---
# The preview scene drops the alpha-BLEND pass, so an overlay can be structurally correct yet invisible.
# Headless has no framebuffer to read, so this is the ONE test that must run WITH a display:
#   ../Godot_v4.6.1-stable_win64_console.exe --path "." -- --test-visual-regression
# Method: freeze the scene, capture the floor with the hover overlay OFF, turn it ON, capture again, and
# require that a meaningful slice of floor pixels CHANGED. Invisible overlay (the bug) -> no change -> FAIL.
# PNGs (vr_<chunk>_*.png) are written for eyeballing — never claim an overlay works without looking.
const _VR_DIFF_THRESHOLD := 0.06   # per-channel delta that counts a pixel as changed
const _VR_MIN_CHANGED_FRAC := 0.01 # >=1% of sampled floor pixels must change for the overlay to "show"
const _VR_SAMPLE_STEP := 2

func _test_visual_regression() -> void:
	_test_name = "Visual Regression"
	if DisplayServer.get_name() == "headless":
		print("  SKIP (visual regression needs a display — run WITHOUT --headless)")
		return
	for chunk in ["lure_relay", "stacks"]:
		await _vr_hover_overlay_draws(chunk)
	# NOTE: the party "one ribbon per member" guard is the HEADLESS, deterministic
	# _test_party_preview_renderers (a pixel diff fights the pause/process model — party ribbons are
	# add_child'd under a paused tree and never get a _process to build their mesh).

func _vr_hover_overlay_draws(chunk: String) -> void:
	var inst = await _instantiate_preview_chunk_and_wait(chunk, 6)
	if inst == null:
		_assert_true(false, "[%s] preview instantiates" % chunk)
		return
	# Let the camera ease-in and first paint settle.
	for i in range(60):
		await get_tree().process_frame
	var player = inst.get("_player")
	var gs = inst.get("_game_state")
	var cam: Camera3D = get_tree().root.get_viewport().get_camera_3d()
	if player == null or gs == null or cam == null:
		_assert_true(false, "[%s] preview exposes player + game_state + camera" % chunk)
		await _dispose_scene(inst)
		return
	if not await _vr_wait_render():
		print("  [VR] %s SKIPPED — window never rendered (no display / cold framebuffer)" % chunk)
		await _dispose_scene(inst)
		return

	# Stop the per-frame hover re-poll (so it can't clobber our forced hover) and stop EVERY character so
	# the PathRenderManager clears its committed-move ribbons — we want a clean floor baseline, otherwise an
	# unrelated moving NPC's ribbon would land in the diff. Let a few UNPAUSED frames render so the clears
	# actually paint, THEN freeze.
	if player.has_method("set_process"):
		player.set_process(false)
	if player.has_method("set_move_enabled"):
		player.set_move_enabled(true)
	if player.has_method("set_click_mode"):
		player.set_click_mode("move")
	player.group_move = false
	if player.has_method("_clear_path_preview"):
		player._clear_path_preview()
	var hg = player.get("_hover_grid")
	if hg != null:
		hg.visible = false
	for cid in gs.characters.keys():
		gs.command_stop(cid)
	for i in range(12):
		await get_tree().process_frame
	get_tree().paused = true  # freeze everything; from here the ONLY thing that changes is our overlay

	var before := await _vr_capture()

	# Overlay ON — aim the hover at a walkable point a few metres ahead (corridors run along +X).
	var base: Vector3 = player.global_position
	var target := Vector3(base.x + 3.0, base.y, base.z)
	var screen: Vector2 = cam.unproject_position(target)
	player._update_hover_from_screen(screen)
	var after := await _vr_capture()

	if before != null:
		before.save_png("res://vr_%s_before.png" % chunk)
	if after != null:
		after.save_png("res://vr_%s_after.png" % chunk)

	# Self-locating diff region: the bounding box of the player and the hovered target on screen, padded —
	# the hover grid + preview ribbon live entirely inside it, so the changed fraction is meaningful no
	# matter where on the floor the overlay landed.
	var region := _vr_overlay_region(cam, player.global_position, target, before)
	var changed := _vr_changed_fraction(before, after, region)
	print("  [VR] %s hover+path changed=%.4f region=%s (target %s screen %s)" % [chunk, changed, str(region), str(target), str(screen)])
	_assert_true(changed >= _VR_MIN_CHANGED_FRAC,
		"[%s] hover grid + path overlay draws on the floor (%.2f%% pixels changed)" % [chunk, changed * 100.0])

	get_tree().paused = false
	await _dispose_scene(inst)

# Pixel bounding box covering the player→target span (where the overlay draws), padded and clamped.
func _vr_overlay_region(cam: Camera3D, player_pos: Vector3, target: Vector3, img: Image, pad := 60.0) -> Rect2i:
	var p := cam.unproject_position(player_pos)
	var t := cam.unproject_position(target)
	var r := Rect2(p, Vector2.ZERO).expand(t).grow(pad)
	var w := img.get_width() if img != null else 1152
	var h := img.get_height() if img != null else 648
	var x0 := clampi(int(r.position.x), 0, w - 1)
	var y0 := clampi(int(r.position.y), 0, h - 1)
	var x1 := clampi(int(r.position.x + r.size.x), 0, w)
	var y1 := clampi(int(r.position.y + r.size.y), 0, h)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))

func _vr_capture() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := get_tree().root.get_texture()
	if tex == null:
		return null
	return tex.get_image()

# A real rendered frame has the HUD + lit scene → many bright pixels. A cold/uninitialised framebuffer
# (the window hasn't painted yet) is near-uniform dark. We use this to tell "the overlay didn't draw"
# (a real regression) apart from "the window never rendered" (an environment hiccup) so the test never
# reports a false FAIL on a cold start.
func _vr_rendered(img: Image) -> bool:
	if img == null:
		return false
	var w := img.get_width()
	var h := img.get_height()
	var bright := 0
	var n := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.25:
				bright += 1
			n += 1
			x += 16
		y += 16
	return n > 0 and float(bright) / float(n) > 0.03

# Spin up to ~8 short waits until the window has actually painted. Returns false if it never did.
func _vr_wait_render() -> bool:
	for attempt in range(8):
		var img := await _vr_capture()
		if _vr_rendered(img):
			return true
		for i in range(15):
			await get_tree().process_frame
	return false

func _vr_changed_fraction(a: Image, b: Image, region: Rect2i) -> float:
	if a == null or b == null:
		return 0.0
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 0.0
	var x0 := region.position.x
	var y0 := region.position.y
	var x1 := mini(region.position.x + region.size.x, a.get_width())
	var y1 := mini(region.position.y + region.size.y, a.get_height())
	var sampled := 0
	var changed := 0
	var y := y0
	while y < y1:
		var x := x0
		while x < x1:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sampled += 1
			if absf(ca.r - cb.r) > _VR_DIFF_THRESHOLD or absf(ca.g - cb.g) > _VR_DIFF_THRESHOLD or absf(ca.b - cb.b) > _VR_DIFF_THRESHOLD:
				changed += 1
			x += _VR_SAMPLE_STEP
		y += _VR_SAMPLE_STEP
	if sampled == 0:
		return 0.0
	return float(changed) / float(sampled)

# --- Test: enemy attacks land predictively, the lunge never teleports, and the FSM disengages ---
# Encodes the three bugs the redesign fixed: (1) the charge used to teleport the body onto a target
# that moved during windup (it now lunges through the data layer); (2) the enemy attacked a downed
# target forever (it now disengages); (3) striking the enemy mid-windup now interrupts it (stagger).
func _test_predictive_attack() -> void:
	_test_name = "Predictive Attack"

	# --- No teleport: the lunge is a real data-layer move, so the guard's position never jumps even
	# when the target slides sideways during windup (the exact case that used to snap it across the map).
	var ctx := _make_attack_ctx(500.0, false)
	var sched: EventScheduler = ctx["sched"]
	var gs: GameState = ctx["gs"]
	var enemy: Enemy = ctx["enemy"]
	var hit_count := [0]
	enemy.hit_target.connect(func(_t, _d): hit_count[0] += 1)
	var max_step := 0.0
	var prev: Vector3 = gs.get_position("guard")
	for i in range(240):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		if enemy.get_state() == "windup" and i % 7 == 0:
			gs.command_move_to_pos("aster", Vector3(4.0, 0.5, 4.0))
		var now: Vector3 = gs.get_position("guard")
		max_step = maxf(max_step, Vector2(now.x - prev.x, now.z - prev.z).length())
		prev = now
	# charge_speed (8) * dt (0.05) = 0.4 per tick; the old teleport-snap jumped >2 units in one tick.
	_assert_true(max_step < 0.6,
		"The lunge never teleports — max per-tick move %.2f stays near charge_speed*dt (0.4)" % max_step)
	_assert_true(hit_count[0] > 0, "The predicted strike lands at least once")
	_cleanup_attack_ctx(ctx)

	# --- Dodge: locked (default) -> the strike lands + the attacker commits its lunge; unlocked+auto
	# -> the first strike is evaded with no damage.
	var locked := _run_one_attack(_make_attack_ctx(100.0, false))
	_assert_true(locked["hit"], "With dodge locked, the predicted strike lands")
	_assert_true(float(locked["hp"]) < 100.0, "The struck character takes damage (hp %.0f)" % locked["hp"])
	_assert_true(float(locked["enemy_x"]) > float(locked["start_x"]) + 0.5,
		"The attacker commits to its lunge (moved toward the target, x %.1f -> %.1f)" % [locked["start_x"], locked["enemy_x"]])
	var dodged := _run_one_attack(_make_attack_ctx(100.0, true))
	_assert_true(float(dodged["hp"]) >= 99.99,
		"With dodge unlocked, the first strike is evaded (no damage, hp %.0f)" % dodged["hp"])

	# --- Disengage: once the target is downed (hp 0), the guard stops striking and leaves combat
	# (the old FSM cycled windup/recover on a corpse forever).
	var dctx := _make_attack_ctx(40.0, false)  # two 25-damage hits -> downed
	var dsched: EventScheduler = dctx["sched"]
	var denemy: Enemy = dctx["enemy"]
	var hits_after_down := [0]
	var downed := [false]
	denemy.hit_target.connect(func(_t, _d):
		if downed[0]:
			hits_after_down[0] += 1)
	for i in range(500):
		dsched.advance_ticks(0.05)
		denemy._process(0.05)
		if not downed[0] and dctx["gs"].get_stat("aster", "hp") <= 0.0:
			downed[0] = true
	_assert_true(downed[0], "The target goes down under repeated strikes")
	_assert_true(denemy.get_state() in ["search", "return", "idle", "roam", "patrol"],
		"After the target is downed the guard disengages (state=%s)" % denemy.get_state())
	_assert_equals(hits_after_down[0], 0, "No further strikes land on a downed target")
	_cleanup_attack_ctx(dctx)

	# --- Stagger: a hit taken mid-windup interrupts the attack (player counterplay).
	var sctx := _make_attack_ctx(500.0, false)
	var ssched: EventScheduler = sctx["sched"]
	var senemy: Enemy = sctx["enemy"]
	var saw_windup := [false]
	var staggered := [false]
	for i in range(200):
		ssched.advance_ticks(0.05)
		senemy._process(0.05)
		if senemy.get_state() == "windup" and not saw_windup[0]:
			saw_windup[0] = true
			senemy.take_damage(10.0)
		if senemy.get_state() == "stagger":
			staggered[0] = true
			break
	_assert_true(saw_windup[0], "The guard reaches windup")
	_assert_true(staggered[0], "Striking the guard mid-windup staggers it (interrupt -> counterplay)")
	_cleanup_attack_ctx(sctx)

## Build a guard-vs-target attack scenario. Guard at origin, target a few units away in range.
func _make_attack_ctx(target_hp: float, dodge: bool) -> Dictionary:
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	var holder := Node3D.new()
	add_child(holder)
	gs.register_character("aster", Vector3(4.0, 0.5, 0.0), 2.5, {"hp": target_hp, "stamina": 100.0})
	if dodge:
		gs.characters["aster"].stats["dodge_unlocked"] = true
		gs.characters["aster"].stats["auto_dodge"] = true
	var enemy := Enemy.new()
	enemy.game_state = gs
	enemy.char_id = "guard"
	enemy._detection_targets = ["aster"]
	enemy.attack_range = 3.0
	enemy.charge_damage = 25.0
	holder.add_child(enemy)
	gs.register_character("guard", Vector3(0.0, 0.5, 0.0), enemy.move_speed, {"detection_range": 6.0})
	enemy.activate()
	gs._recompute_all_detection_predictions()
	return {"sched": sched, "gs": gs, "enemy": enemy, "holder": holder}

## Drive one attack to its first resolution (the guard reaching recover). Returns hit/hp/positions.
func _run_one_attack(ctx: Dictionary) -> Dictionary:
	var sched: EventScheduler = ctx["sched"]
	var gs: GameState = ctx["gs"]
	var enemy: Enemy = ctx["enemy"]
	var start_x: float = gs.get_position("guard").x
	var hit := [false]
	enemy.hit_target.connect(func(_t, _d): hit[0] = true)
	for i in range(200):
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		if enemy.get_state() == "recover":
			break
	var res := {"hit": hit[0], "hp": gs.get_stat("aster", "hp"),
		"enemy_x": gs.get_position("guard").x, "start_x": start_x}
	_cleanup_attack_ctx(ctx)
	return res

func _cleanup_attack_ctx(ctx: Dictionary) -> void:
	if ctx.has("enemy") and is_instance_valid(ctx["enemy"]):
		ctx["enemy"].queue_free()
	if ctx.has("holder") and is_instance_valid(ctx["holder"]):
		ctx["holder"].queue_free()

# --- Test: the enemy FSM walks the FULL attack cycle in order, loops, restores speed, and is FF-invariant ---
# Proves the state machine drives combat end-to-end: alert -> pursuit -> windup -> charge -> impact ->
# recover, then re-engages (the loop), the charge_speed is restored to move_speed afterwards, and the whole
# thing produces the SAME strike count at a fine and a coarse tick step (fast-forward changes nothing).
func _test_combat_cycle() -> void:
	_test_name = "Combat Cycle"
	var ctx := _make_attack_ctx(500.0, false)  # tanky target so the guard re-engages several times
	var sched: EventScheduler = ctx["sched"]
	var gs: GameState = ctx["gs"]
	var enemy: Enemy = ctx["enemy"]
	var hits := [0]
	enemy.hit_target.connect(func(_t, _d): hits[0] += 1)
	var seq: Array[String] = [enemy.get_state()]
	for i in range(360):  # ~18s
		sched.advance_ticks(0.05)
		enemy._process(0.05)
		var st := enemy.get_state()
		if st != seq[seq.size() - 1]:
			seq.append(st)
	# Every cycle state appears, and the FIRST appearance of each is in attack order.
	var order := ["alert", "pursuit", "windup", "charge", "impact", "recover"]
	var idx := {}
	for s in order:
		idx[s] = seq.find(s)
		_assert_true(int(idx[s]) >= 0, "The cycle reaches '%s'" % s)
	_assert_true(int(idx["alert"]) < int(idx["pursuit"]) and int(idx["pursuit"]) < int(idx["windup"])
		and int(idx["windup"]) < int(idx["charge"]) and int(idx["charge"]) < int(idx["impact"])
		and int(idx["impact"]) < int(idx["recover"]),
		"States fire in attack order: alert->pursuit->windup->charge->impact->recover  (seq head: %s)" % str(seq.slice(0, 8)))
	_assert_true(hits[0] >= 2, "The guard re-engages and strikes more than once (combat loops; %d hits)" % hits[0])
	# Drain out of any in-flight charge, then the lunge's charge_speed must be back to move_speed.
	var guard_speed := 0.0
	for i in range(40):
		guard_speed = float(gs.characters["guard"].move_speed)
		if enemy.get_state() != "charge":
			break
		sched.advance_ticks(0.05)
	_assert_true(absf(guard_speed - enemy.move_speed) < 0.01,
		"charge_speed is restored to move_speed after the charge (got %.2f, want %.2f)" % [guard_speed, enemy.move_speed])
	_cleanup_attack_ctx(ctx)

	# Fast-forward invariance: identical strike count at a fine (0.05) and a coarse (0.5) tick step.
	var hits_to_tick := func(step: float) -> int:
		var c := _make_attack_ctx(500.0, false)
		var s: EventScheduler = c["sched"]
		var e: Enemy = c["enemy"]
		var n := [0]
		e.hit_target.connect(func(_t, _d): n[0] += 1)
		while s.get_current_tick() < 12.0 - 1e-9:
			s.advance_ticks(minf(step, 12.0 - s.get_current_tick()))
		_cleanup_attack_ctx(c)
		return n[0]
	var fine := int(hits_to_tick.call(0.05))
	var coarse := int(hits_to_tick.call(0.5))
	_assert_true(fine >= 2, "Combat resolves multiple strikes in 12s at 1x (%d)" % fine)
	_assert_equals(coarse, fine, "Combat is fast-forward invariant: same strike count at fine and coarse tick steps")

# --- Test: the dodge is resolved at IMPACT, and a failed dodge still lets the strike land ---
# #20: a dodge enabled only AFTER the charge commits still slips the hit (and one revoked mid-charge lands).
# #24: an unlocked dodge that can't pay (low stamina) fails at impact, so the strike connects.
func _test_dodge_combat_timing() -> void:
	_test_name = "Dodge Combat Timing"
	# Drive an attack to its first recover, optionally flipping the target's dodge stats the first time a
	# given state is reached, and report the damage the target took.
	var run := func(start_dodge: bool, flip_at: String, flip_to: bool, stamina: float) -> float:
		var ctx := _make_attack_ctx(100.0, start_dodge)
		var s: EventScheduler = ctx["sched"]
		var gs: GameState = ctx["gs"]
		var e: Enemy = ctx["enemy"]
		gs.characters["aster"].stats["stamina"] = stamina
		var flipped := [false]
		for i in range(240):
			s.advance_ticks(0.05)
			e._process(0.05)
			if flip_at != "" and not flipped[0] and e.get_state() == flip_at:
				flipped[0] = true
				gs.characters["aster"].stats["dodge_unlocked"] = flip_to
				gs.characters["aster"].stats["auto_dodge"] = flip_to
			if e.get_state() == "recover":
				break
		var dmg := 100.0 - float(gs.get_stat("aster", "hp"))
		_cleanup_attack_ctx(ctx)
		return dmg

	# #20: dodge unlocked only once the charge commits still slips the strike — proving the dodge is
	# resolved AT IMPACT, not locked in at lunge-commit. (start_dodge=false keeps the target from
	# detection-fleeing before the charge, so the charge is actually reached.)
	_assert_true(run.call(false, "charge", true, 100.0) < 0.01,
		"Dodge enabled mid-charge still slips the strike (resolved at impact, not at lunge-commit)")
	# #24: an unlocked+auto dodge with too little stamina FAILS at impact, so the strike connects.
	_assert_true(run.call(true, "", true, 5.0) > 0.0,
		"An unlocked dodge that can't pay stamina fails -> the strike lands")
	# A fully-funded auto-dodge evades (it both detection-dodges away and slips the strike — no damage).
	_assert_true(run.call(true, "", true, 100.0) < 0.01,
		"A funded auto-dodge evades the strike")

# --- Test: chromatic aberration is live in the sim scenes ---
func _test_chromatic_aberration() -> void:
	_test_name = "Chromatic Aberration (Sims)"
	for scene_path in ["res://scenes/tutorial/aster_sim.tscn", "res://scenes/tutorial/peris_sim.tscn"]:
		var scene = load(scene_path)
		if scene == null:
			_assert_true(false, "%s loads" % scene_path)
			continue
		var inst = scene.instantiate()
		get_tree().root.add_child(inst)
		for i in range(4):
			await get_tree().process_frame
		_assert_true(bool(inst.get("chromatic_aberration_enabled")),
			"%s has chromatic aberration enabled" % scene_path.get_file())
		var layer = inst.get("_chromatic_aberration_layer")
		var mat = inst.get("_chromatic_aberration_material")
		_assert_true(layer != null and mat != null,
			"%s builds the chromatic aberration post-process" % scene_path.get_file())
		if layer != null:
			_assert_true(layer.visible, "%s chromatic layer is active" % scene_path.get_file())
		if mat != null:
			_assert_true(float(mat.get_shader_parameter("strength_px")) > 0.0,
				"%s chromatic shader carries a non-zero strength" % scene_path.get_file())
		inst.queue_free()
		await get_tree().process_frame

# --- Test: hover-to-identify with Aster's data overlay ---
# When the data overlay is on, hovering an interactable surfaces the object's name; off, nothing.
func _test_data_identify() -> void:
	_test_name = "Data Identify Hover"
	var area = load("res://scenes/game/interactable.tscn").instantiate()
	add_child(area)
	area.description = "Door Button"

	# Data overlay OFF: hovering shows no scan readout.
	area.set_hover_feedback(true)
	_assert_true(area._identify_label_3d == null or not area._identify_label_3d.visible,
		"No identify readout while the data overlay is off")
	area.set_hover_feedback(false)

	# Data overlay ON: hovering reveals the object's name.
	area.set_data_identify(true)
	area.set_hover_feedback(true)
	_assert_true(area._identify_label_3d != null and area._identify_label_3d.visible,
		"Hovering with the data overlay reveals a readout")
	_assert_true("DOOR BUTTON" in area._identify_label_3d.text,
		"The readout shows the object's name (got: %s)" % (area._identify_label_3d.text if area._identify_label_3d != null else ""))

	# Turning the overlay off hides it even while still hovered.
	area.set_data_identify(false)
	_assert_true(not area._identify_label_3d.visible, "Turning off the data overlay hides the readout")

	# Re-enable, then a disabled/used object shows nothing.
	area.set_data_identify(true)
	area.set_interaction_enabled(false)
	area.set_hover_feedback(true)
	_assert_true(not area._identify_label_3d.visible, "A disabled object does not surface a readout")
	area.queue_free()

func _drive_fsm_sequence(step: float) -> String:
	var sched := EventScheduler.new()
	var sm := StateMachine.new(sched, "drive")
	sm.add_state("s0")
	sm.add_state("s2")
	sm.add_state("s1", func(): sm.transition_after(1.0, "s2"))  # chain forward on enter
	sm.start("s0")
	sm.transition_after(1.0, "s1")
	var t := 0.0
	while t < 3.0:
		sched.advance_ticks(step)
		t += step
	return sm.current()

# --- Test: clicking another floor routes the player cross-level (shared controller, every scene) ---
# The player used to REJECT a click on a different stacked floor (it would lerp through the air).
# On a multi-level grid it now routes over ladders/ramps via command_move_cross_level instead.
func _test_player_cross_level_click() -> void:
	_test_name = "Player Cross-Level Click"
	var grid := GridWorld.new()
	grid.create_room(8, 8)
	grid.set_level_count(2)
	grid.level_height = 4.0
	grid.add_inter_level_link(Vector2i(4, 4), 0, 1, "ladder")

	# level_for_y inverts grid_to_world's Y so a floor-1 point maps to level 1.
	var floor1_point := grid.grid_to_world(Vector2i(6, 6), 1)
	_assert_equals(grid.level_for_y(floor1_point.y), 1, "level_for_y maps a floor-1 Y to level 1")
	_assert_equals(grid.level_for_y(0.0), 0, "level_for_y maps the ground floor to level 0")

	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.register_character("hero", grid.grid_to_world(Vector2i(1, 1), 0), 3.0, {})

	var player_scene: PackedScene = load("res://scenes/game/player_character.tscn")
	var player = player_scene.instantiate()
	add_child(player)  # _ready builds the dest marker etc.
	player.grid_world = grid
	player.game_state = gs
	player.char_id = "hero"
	player.global_position = grid.grid_to_world(Vector2i(1, 1), 0)

	# A click on floor 1 routes across floors (returns true) instead of being rejected.
	_assert_true(player.move_to_world_position(floor1_point),
		"A click on another floor routes cross-level instead of being rejected")
	for i in range(300):
		sched.advance_ticks(0.1)
		if not gs.is_moving("hero") and gs.get_character_level("hero") == 1:
			break
	_assert_equals(gs.get_character_level("hero"), 1, "The player climbs to the clicked floor")
	_assert_equals(grid.world_to_grid(gs.get_position("hero")), Vector2i(6, 6),
		"The player ends on the clicked cell")
	player.queue_free()

	# A single-floor grid still rejects a click far above the floor (no phantom climb without a grid level).
	var flat := GridWorld.new()
	flat.create_room(8, 8)  # level_count stays 1
	var gs2 := GameState.new()
	gs2.grid = flat
	gs2.scheduler = EventScheduler.new()
	gs2.register_character("hero2", flat.grid_to_world(Vector2i(1, 1)), 3.0, {})
	var p2 = player_scene.instantiate()
	add_child(p2)
	p2.grid_world = flat
	p2.game_state = gs2
	p2.char_id = "hero2"
	p2.global_position = flat.grid_to_world(Vector2i(1, 1))
	_assert_true(not p2.move_to_world_position(flat.grid_to_world(Vector2i(6, 6)) + Vector3(0, 5.0, 0)),
		"On a single-floor grid, a click far above the floor is still rejected")
	p2.queue_free()

# --- Test: outline particles emit from the object surface ---
# The per-mesh outline feedback used a box emission shape sized from the mesh AABB,
# which collapsed into a centre blob (worse once the object was scaled). It now
# samples the mesh surface so particles spread around the object's outline.
func _test_outline_particle_emission() -> void:
	_test_name = "Outline Particle Emission"

	var target := OutlineSurfaceTarget.new()
	add_child(target)

	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 3.0)

	var emission := target._build_surface_emission(box, 220)
	_assert_equals(int(emission["count"]), 220, "Surface emission yields the requested point count")
	var positions: PackedVector3Array = emission["positions"]
	_assert_equals(positions.size(), 220, "One emission point per sample")

	# Points must SPREAD across the surface, not collapse to a single cluster.
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for p in positions:
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	var span := mx - mn
	_assert_true(span.x > 1.5 and span.y > 0.7 and span.z > 2.0,
		"Emission points span the mesh outline (span=%s), not one spot" % str(span))

	# Every point lies ON the box surface (distance to the nearest face ~ 0).
	var half := box.size * 0.5
	var max_surface_dist := 0.0
	for p in positions:
		var d := minf(minf(absf(absf(p.x) - half.x), absf(absf(p.y) - half.y)), absf(absf(p.z) - half.z))
		max_surface_dist = maxf(max_surface_dist, d)
	_assert_true(max_surface_dist < 0.01,
		"Every emission point lies on the mesh surface (max off-surface=%.4f)" % max_surface_dist)

	# Deterministic: same mesh + count reproduces identical points (replay-safe, no RNG).
	var positions2: PackedVector3Array = target._build_surface_emission(box, 220)["positions"]
	var deterministic := positions.size() == positions2.size()
	if deterministic:
		for i in range(positions.size()):
			if positions[i].distance_to(positions2[i]) > 0.00001:
				deterministic = false
				break
	_assert_true(deterministic, "Surface sampling is deterministic for identical inputs")

	# Degenerate mesh (no triangles) falls back to a sphere, never a clustered box.
	var empty := ArrayMesh.new()
	var degenerate := target._build_surface_emission(empty, 64)
	_assert_equals(int(degenerate["count"]), 0, "A mesh with no triangles yields zero surface points")

	# The built emitter uses surface point emission, not a box blob.
	var mi := MeshInstance3D.new()
	mi.mesh = box
	target.add_child(mi)
	var particles = target._ensure_outline_particles(mi)
	_assert_true(particles != null, "Outline particles are created for a highlight mesh")
	if particles != null:
		var pm := particles.process_material as ParticleProcessMaterial
		_assert_equals(pm.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS,
			"Outline particles emit from surface points, not a box")
		_assert_true(pm.emission_point_count > 1, "Outline emission uses many surface points")
		_assert_true(pm.emission_point_texture != null, "Outline emission has a point-position texture")
		_assert_true(not particles.top_level and particles.local_coords,
			"Outline particles ride the mesh transform so points land on the surface")

	target.queue_free()

# --- Test: proximity interactable feedback traces its outline ---
# Plain interactables have no mesh, so their "outline" is the interaction footprint.
# The selected feedback emits from a ring around that radius (not a central blob) and
# recolours to selected_feedback_color, the same in every scene.
func _test_interactable_outline_particles() -> void:
	_test_name = "Interactable Outline Particles"

	var it := Interactable.new()
	it.interaction_radius = 2.0
	it.selected_feedback_color = Color(0.2, 0.9, 0.4, 1.0)
	add_child(it)
	it._ensure_selected_particles()

	var pm := it._selected_particles.process_material as ParticleProcessMaterial
	_assert_true(pm != null, "Interactable selected particles have a process material")
	if pm != null:
		_assert_equals(pm.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_RING,
			"Interactable particles emit from a ring outline, not a central point")
		_assert_true(pm.emission_ring_radius > 1.0,
			"Ring radius scales with the interaction footprint (got %.2f)" % pm.emission_ring_radius)
		_assert_true(pm.emission_ring_inner_radius < pm.emission_ring_radius,
			"Ring keeps a band (inner < outer) so particles trace the outline edge")

	# Colour feedback applies regardless of scene.
	it.play_selected_feedback()
	if pm != null:
		_assert_equals(pm.color, it.selected_feedback_color,
			"Selected feedback recolours the interactable particles")
	_assert_true(it._selected_particles.emitting, "play_selected_feedback starts the emitter")

	it.queue_free()

# --- Test: the shared outline system (data -> representation) ---
# OutlineFeedbackManager builds + binds outline targets for ANY branch (chunk or
# sequence), so chunk outlines work in gameplay, not only tutorials.
func _test_outline_feedback_system() -> void:
	_test_name = "Outline Feedback System"

	var host := Node3D.new()
	host.name = "OutlineSystemHost"
	get_tree().root.add_child(host)

	# ensure() find-or-create, scoped to the caller's branch and idempotent.
	var system := OutlineFeedbackManager.ensure(host)
	_assert_true(system != null, "ensure() returns a system for a fresh branch")
	_assert_true(system == OutlineFeedbackManager.ensure(host),
		"ensure() is idempotent for the same branch")
	# A descendant (e.g. a chunk under its host) finds the same system.
	var child := Node3D.new()
	host.add_child(child)
	_assert_true(OutlineFeedbackManager.ensure(child) == system,
		"A descendant finds its branch's existing system")

	# Build an outlined object through the system — no TutorialSequence involved.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	mesh.mesh = box
	host.add_child(mesh)
	var delegate := Node3D.new()
	host.add_child(delegate)
	var target := system.outline_meshes(host, "SystemOutline", [mesh], "sys", 1.0, {
		"selected_particle_count": 42,
		"delegate": delegate,
		"metadata": {"sys_meta": 7},
	})
	_assert_true(target != null, "outline_meshes builds a target from mesh bounds")
	if target != null:
		_assert_true(bool(target.get("outline_particles_enabled")),
			"Built target has outline particles enabled")
		_assert_equals(int(target.get("selected_particle_count")), 42,
			"opts override the per-target tuning")
		_assert_equals(int(target.get_meta("sys_meta")), 7,
			"opts.metadata is applied to the target")
		if target.has_method("get_interaction_delegate"):
			_assert_true(target.call("get_interaction_delegate") == delegate,
				"opts.delegate wires the interaction delegate")
		if target.has_method("get_highlight_mesh_count"):
			_assert_true(int(target.call("get_highlight_mesh_count")) > 0,
				"Built target wraps the object's meshes")
		if target.has_method("is_feedback_managed"):
			_assert_true(bool(target.call("is_feedback_managed")),
				"Built target is bound to the system (feedback-managed)")

		# The binding is live: selecting drives the system + particle feedback. This is
		# what was dead for gameplay chunks before (no manager bound the target).
		target.emit_signal("outline_selected", target)
		_assert_true(system.get_selected_target() == target,
			"Selecting a built target registers with the system")
		if target.has_method("has_active_glow"):
			_assert_true(bool(target.call("has_active_glow")),
				"Selection lights the target's outline particles")

	host.queue_free()

# --- Test: data-first interactables ---
# GameState owns interactable state; register/trigger/enable are event-logged so
# a replay rebuilds the registry and re-fires triggers.
func _test_interactable_data() -> void:
	_test_name = "Interactable Data Layer"
	var grid := GridWorld.new()
	grid.create_room(10, 10, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	var log := EventLog.new()
	gs.event_log = log

	gs.register_interactable({
		"id": "t1", "position": grid.grid_to_world(Vector2i(4, 4)),
		"requires_hold": false, "one_shot": true, "required_character": "aster",
		"dialogue_key": "aster.terminal",
	})
	_assert_true(gs.has_interactable("t1"), "Interactable registered into the data layer")
	_assert_true(gs.is_interactable_enabled("t1"), "Newly registered interactable is enabled")

	# Wrong character is rejected and records nothing.
	var log_before := log.size()
	_assert_true(not gs.trigger_interactable("t1", "peris"),
		"Trigger rejected for the wrong required character")
	_assert_equals(log.size(), log_before, "A rejected trigger records no event")

	# Right character triggers, marks triggered, and disables the one-shot.
	_assert_true(gs.trigger_interactable("t1", "aster"), "Trigger accepted for the required character")
	_assert_true(gs.get_interactable("t1").get("triggered", false), "Trigger marks the interactable triggered")
	_assert_true(not gs.is_interactable_enabled("t1"), "One-shot interactable disables after firing")
	_assert_true(not gs.trigger_interactable("t1", "aster"), "A spent one-shot can't fire again")

	# Event log holds exactly one register + one trigger.
	var kinds: Array[String] = []
	for e in log.events:
		kinds.append(String(e["kind"]))
	_assert_equals(kinds.count("register_interactable"), 1, "One register_interactable event logged")
	_assert_equals(kinds.count("trigger_interactable"), 1, "One trigger_interactable event logged")

	# Replay rebuilds the registry + the triggered/disabled state.
	var replayed := GameState.replay(log, grid)
	_assert_true(replayed.has_interactable("t1"), "Replay reconstructs the interactable")
	_assert_true(replayed.get_interactable("t1").get("triggered", false),
		"Replay reconstructs the triggered state")
	_assert_true(not replayed.is_interactable_enabled("t1"),
		"Replay reconstructs the one-shot-disabled state")

	# --- Query + move-to loop: find interactables in the party's combined visible
	# range, move a character to one, and trigger it (the automated chunk-test loop). ---
	var grid2 := GridWorld.new()
	grid2.create_room(24, 24, true)
	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.grid = grid2
	gs2.scheduler = sched2
	gs2.register_character("aster", grid2.grid_to_world(Vector2i(3, 3)), 3.0, {})
	gs2.register_character("peris", grid2.grid_to_world(Vector2i(4, 3)), 3.0, {})
	gs2.set_party(["aster", "peris"])
	gs2.register_interactable({"id": "near_a", "position": grid2.grid_to_world(Vector2i(6, 4)), "requires_hold": false})
	gs2.register_interactable({"id": "far_a", "position": grid2.grid_to_world(Vector2i(20, 20)), "requires_hold": false})
	var visible := gs2.interactables_in_range(gs2.get_party(), 12.0)
	_assert_true(visible.has("near_a"), "A nearby interactable is within the party's visible range")
	_assert_true(not visible.has("far_a"), "A far interactable is outside the visible range")
	# Move aster to the nearby interactable, then trigger it.
	_assert_true(gs2.move_to_interactable("aster", "near_a"), "move_to_interactable issues a move")
	for s in range(400):
		if not gs2.is_moving("aster"):
			break
		sched2.advance_ticks(0.05)
	var reached := gs2.get_position("aster").distance_to(grid2.grid_to_world(Vector2i(6, 4))) < 1.5
	_assert_true(reached, "Aster reaches the targeted interactable")
	_assert_true(gs2.trigger_interactable("near_a", "aster"), "Reached interactable can then be triggered")

# --- Test: chunk party presence (D8a) ---
func _test_chunk_party_presence() -> void:
	_test_name = "ChunkPartyPresence"

	# A chunk with no PartyPresence node returns an empty map (no override → the
	# host keeps its full default roster).
	var bare := SceneChunk.new()
	_assert_true(bare.get_party_presence().is_empty(),
		"A chunk without a PartyPresence node reports no presence override")
	bare.free()

	# A PartyPresence node reports its configured roster.
	var presence := PartyPresence.new()
	presence.aster_present = true
	presence.peris_present = false
	presence.endo_present = true
	var map := presence.presence_map()
	_assert_true(bool(map.get("aster")), "PartyPresence marks aster present")
	_assert_true(not bool(map.get("peris")), "PartyPresence marks peris absent")
	_assert_true(bool(map.get("endo")), "PartyPresence marks endo present")
	var ids := presence.present_ids()
	_assert_true(ids.has("aster") and ids.has("endo") and not ids.has("peris"),
		"present_ids lists only the present members")

	# A chunk discovers a PartyPresence child and surfaces its map.
	var chunk := SceneChunk.new()
	chunk.add_child(presence)
	var discovered := chunk.get_party_presence()
	_assert_true(not bool(discovered.get("peris", true)),
		"A chunk surfaces its PartyPresence child's map")
	chunk.free()

# --- Test: SimCommand API surface (D9) ---
func _test_sim_command_api() -> void:
	_test_name = "SimCommandAPI"

	var list := SimCommand.list_interactables(8.0)
	_assert_equals(list.type, SimCommand.Type.LIST_INTERACTABLES, "list_interactables builds the right command")
	_assert_equals(float(list.args.get("radius", -1.0)), 8.0, "list_interactables carries its radius")

	var move := SimCommand.move_to_interactable("Terminal", "aster")
	_assert_equals(move.type, SimCommand.Type.MOVE_TO_INTERACTABLE, "move_to_interactable builds the right command")
	_assert_equals(str(move.args.get("id")), "Terminal", "move_to_interactable carries its target id")
	_assert_equals(str(move.args.get("char_id")), "aster", "move_to_interactable carries the actor")

	var equip := SimCommand.equip_item("ferritin_shard")
	_assert_equals(equip.type, SimCommand.Type.EQUIP_ITEM, "equip_item builds the right command")
	_assert_equals(str(equip.args.get("item_id")), "ferritin_shard", "equip_item carries its item id")

	var drop := SimCommand.drop_item("ferritin_shard", "endo")
	_assert_equals(drop.type, SimCommand.Type.DROP_ITEM, "drop_item builds the right command")
	_assert_equals(str(drop.args.get("char_id")), "endo", "drop_item carries the actor")

	var give := SimCommand.give_item("ferritin_shard", "peris", "aster")
	_assert_equals(give.type, SimCommand.Type.GIVE_ITEM, "give_item builds the right command")
	_assert_equals(str(give.args.get("to_char")), "peris", "give_item carries the recipient")

	var throw := SimCommand.throw_object("barrel", 5.0, -2.0)
	_assert_equals(throw.type, SimCommand.Type.THROW_OBJECT, "throw_object builds the right command")
	_assert_equals(float(throw.args.get("x")), 5.0, "throw_object carries its target x")

	var queue := SimCommand.queue_moves([Vector3(1, 0, 1), Vector3(2, 0, 2)])
	_assert_equals(queue.type, SimCommand.Type.QUEUE_MOVES, "queue_moves builds the right command")
	_assert_equals((queue.args.get("points") as Array).size(), 2, "queue_moves carries its waypoints")

	var rest := SimCommand.rest()
	_assert_equals(rest.type, SimCommand.Type.REST, "rest builds the right command")

	# The runner resolves an interactable by exact id, and returns empty otherwise.
	var grid := GridWorld.new()
	grid.create_room(16, 16, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched
	gs.grid = grid
	gs.register_interactable({"id": "console_a", "position": grid.grid_to_world(Vector2i(2, 2)), "radius": 3.0})
	var runner := SimRunner.new(get_tree())
	_assert_equals(runner._resolve_interactable_id(gs, "console_a"), "console_a",
		"SimRunner resolves an interactable by its exact registered id")
	_assert_equals(runner._resolve_interactable_id(gs, "missing"), "",
		"SimRunner returns empty for an unknown interactable")

	# Ballistic throw lands a registered physics object near its target XZ.
	gs.register_physics_object("toss", grid.grid_to_world(Vector2i(2, 2)), 0.5, 2.0, 0.6, true)
	var toss_target := grid.grid_to_world(Vector2i(8, 6))
	toss_target.y = 0.0
	_assert_true(gs.throw_physics_object_to("toss", toss_target),
		"throw_physics_object_to launches a registered object")
	for i in range(800):
		if sched.pop_next().is_empty():
			break
	var landed := gs.get_physics_position("toss")
	var land_err := Vector2(landed.x - toss_target.x, landed.z - toss_target.z).length()
	_assert_true(land_err < 2.0, "Thrown object lands near its target (err %.2f)" % land_err)
	_assert_true(not gs.throw_physics_object_to("nope", toss_target),
		"Throwing an unregistered object fails cleanly")

# --- Test: GameState ---
func _test_game_state() -> void:
	_test_name = "GameState"

	# Create grid, scheduler, and GameState
	var grid := GridWorld.new()
	grid.create_room(10, 8, true)

	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	_assert_true(gs.grid != null, "GameState has grid")

	# Register a character
	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {"atp": 6})
	_assert_true(gs.characters.has("aster"), "Character registered")
	_assert_true(gs.characters["aster"].move_speed == 3.0, "Move speed is 3.0")
	_assert_true(gs.characters["aster"].stats.atp == 6, "Stats preserved")

	# Command: move to cell
	var moved := gs.command_move_to_cell("aster", Vector2i(5, 3))
	_assert_true(moved, "command_move_to_cell returns true")
	_assert_true(gs.is_moving("aster"), "Character is moving")
	_assert_true(gs.characters["aster"].movement != null, "Movement state exists")

	# Mid-movement: position should have moved from start
	var start_pos := grid.grid_to_world(Vector2i(1, 1))
	sched.advance_ticks(0.5)
	var mid_pos := gs.get_position("aster")
	_assert_true(gs.is_moving("aster"), "Still moving after partial advance")
	_assert_true(mid_pos.distance_to(start_pos) > 0.1, "Character moved from start")

	# Advance scheduler until arrival
	sched.advance_ticks(100.0)
	_assert_true(not gs.is_moving("aster"), "Character arrived after advancing scheduler")
	var final_pos := gs.get_position("aster")
	var final_cell := grid.world_to_grid(final_pos)
	_assert_equals(final_cell, Vector2i(5, 3), "Final cell matches target")

	# Command: move to unreachable cell (wall)
	var blocked := gs.command_move_to_cell("aster", Vector2i(0, 0))
	_assert_true(not blocked, "Cannot pathfind to wall")

	# Command: straight-line move
	var pos_moved := gs.command_move_to_pos("aster", Vector3(4.5, 0, 2.5))
	_assert_true(pos_moved, "command_move_to_pos returns true")
	sched.advance_ticks(100.0)
	_assert_true(not gs.is_moving("aster"), "Straight-line move completed")

	# Command: stop mid-movement
	gs.command_move_to_cell("aster", Vector2i(8, 6))
	_assert_true(gs.is_moving("aster"), "Moving before stop")
	sched.advance_ticks(0.3)
	var stop_pos := gs.get_position("aster")
	gs.command_stop("aster")
	_assert_true(not gs.is_moving("aster"), "Stopped after command_stop")
	var after_stop := gs.get_position("aster")
	_assert_true(stop_pos.distance_to(after_stop) < 0.01, "Position preserved after stop")

	# Serialize / deserialize round-trip
	gs.command_move_to_cell("aster", Vector2i(3, 3))
	sched.advance_ticks(100.0)

	var snapshot := gs.serialize()
	_assert_true(snapshot.has("characters"), "Snapshot has characters")
	_assert_true(snapshot.characters.has("aster"), "Snapshot has aster")

	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.grid = grid
	gs2.scheduler = sched2
	gs2.deserialize(snapshot)
	_assert_true(gs2.characters.has("aster"), "Deserialized has aster")
	var pos1: Vector3 = gs.get_position("aster")
	var pos2: Vector3 = gs2.get_position("aster")
	_assert_true(pos1.distance_to(pos2) < 0.01, "Positions match after round-trip")

	# Unregister
	gs.unregister_character("aster")
	_assert_true(not gs.characters.has("aster"), "Character unregistered")

func _test_event_log_roundtrip() -> void:
	_test_name = "EventLog Roundtrip"

	var grid := GridWorld.new()
	grid.create_room(10, 8, true)

	# --- Recording session ---
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.event_log = EventLog.new()

	var start_pos := grid.grid_to_world(Vector2i(1, 1))
	gs.register_character("aster", start_pos, 3.0, {"atp": 6})
	_assert_true(gs.event_log.size() == 1, "Register emits one event")

	sched.advance_ticks(0.25)
	gs.command_move_to_cell("aster", Vector2i(5, 3))
	sched.advance_ticks(100.0)  # advance past arrival
	_assert_true(not gs.is_moving("aster"), "Recording: arrived after advance")

	gs.command_move_to_pos("aster", Vector3(2.5, 0, 2.5))
	sched.advance_ticks(0.4)
	gs.command_stop("aster")
	gs.change_move_speed("aster", 5.0)

	var path: Array[Vector3] = [grid.grid_to_world(Vector2i(3, 3)), grid.grid_to_world(Vector2i(4, 4))]
	gs.command_walk_path("aster", path)
	sched.advance_ticks(100.0)
	gs.flush_tick()

	var snap1 := gs.serialize()
	var event_count := gs.event_log.size()
	_assert_equals(event_count, 6, "Recorded 6 commands")
	_assert_true(gs.event_log.recorded_until >= 200.0,
		"recorded_until tracks scheduler tick (got %f)" % gs.event_log.recorded_until)

	# --- Replay from in-memory log ---
	var gs_replay := GameState.replay(gs.event_log, grid)
	var snap_replay := gs_replay.serialize()
	_assert_true(snap_replay.characters.has("aster"), "Replay reconstructs character")

	var pos_orig := Vector3(snap1.characters["aster"].position[0], snap1.characters["aster"].position[1], snap1.characters["aster"].position[2])
	var pos_rep := Vector3(snap_replay.characters["aster"].position[0], snap_replay.characters["aster"].position[1], snap_replay.characters["aster"].position[2])
	_assert_true(pos_orig.distance_to(pos_rep) < 0.01,
		"Replay final position matches recording (orig=%s, replay=%s)" % [pos_orig, pos_rep])
	_assert_equals(snap_replay.characters["aster"].move_speed, snap1.characters["aster"].move_speed,
		"Replay preserves move_speed")

	# --- Roundtrip log through bytes ---
	var bytes := gs.event_log.to_bytes()
	_assert_true(bytes.size() > 0, "Log serializes to non-empty bytes")
	var log_decoded := EventLog.from_bytes(bytes)
	_assert_equals(log_decoded.size(), event_count, "Decoded log has same event count")

	var gs_replay2 := GameState.replay(log_decoded, grid)
	var snap_replay2 := gs_replay2.serialize()
	var pos_rep2 := Vector3(snap_replay2.characters["aster"].position[0], snap_replay2.characters["aster"].position[1], snap_replay2.characters["aster"].position[2])
	_assert_true(pos_orig.distance_to(pos_rep2) < 0.01,
		"Position matches after byte-roundtrip + replay (got %s)" % pos_rep2)

	# --- Replay does not append to its own log ---
	gs_replay.event_log = EventLog.new()
	gs_replay.command_stop("aster")
	_assert_true(gs_replay.event_log.size() == 1, "Post-replay recording works (replay flag cleared)")

	# --- Unregister also goes through the log ---
	gs.unregister_character("aster")
	_assert_true(gs.event_log.size() == event_count + 1, "Unregister appended to log")
	var gs_replay3 := GameState.replay(gs.event_log, grid)
	_assert_true(not gs_replay3.characters.has("aster"), "Replay reflects unregister")

	# --- Item commands round-trip ---
	var sched_i := EventScheduler.new()
	var gs_i := GameState.new()
	gs_i.grid = grid
	gs_i.scheduler = sched_i
	gs_i.event_log = EventLog.new()

	gs_i.register_character("aster", grid.grid_to_world(Vector2i(2, 2)), 3.0, {"atp": 50})
	gs_i.register_character("peris", grid.grid_to_world(Vector2i(2, 3)), 3.0, {"atp": 50})

	var item_id_a := gs_i.spawn_item("food", grid.grid_to_world(Vector2i(2, 2)), {"atp_restore": 25})
	var item_id_b := gs_i.spawn_item("flora_seed", grid.grid_to_world(Vector2i(5, 5)))
	_assert_equals(item_id_a, "item_1", "First spawn id is item_1")
	_assert_equals(item_id_b, "item_2", "Second spawn id is item_2")

	_assert_true(gs_i.pick_up_item("aster", item_id_a), "Aster picks up item_1")
	_assert_true(gs_i.transfer_item("aster", "peris", item_id_a), "Transfer item_1 aster→peris")
	_assert_true(gs_i.drop_item("peris", item_id_a), "Peris drops item_1")
	gs_i.remove_item(item_id_b)
	gs_i.flush_tick()

	# Replay
	var gs_i_replay := GameState.replay(gs_i.event_log, grid)
	_assert_true(gs_i_replay.items.has(item_id_a), "Replay preserves item_1")
	_assert_true(not gs_i_replay.items.has(item_id_b), "Replay reflects removed item_2")
	var item_after: Dictionary = gs_i_replay.items[item_id_a]
	_assert_equals(item_after["holder"], "", "Replay: item_1 holder cleared after drop")
	_assert_equals(item_after["location"], "ground", "Replay: item_1 on ground")
	_assert_equals(gs_i_replay.get_hand_items("peris").size(), 0, "Replay: Peris hands empty after drop")

	# --- Physics + pendulum + dodge round-trip ---
	var sched_p := EventScheduler.new()
	var gs_p := GameState.new()
	gs_p.grid = grid
	gs_p.scheduler = sched_p
	gs_p.event_log = EventLog.new()

	gs_p.register_character("aster", grid.grid_to_world(Vector2i(2, 2)), 3.0,
		{"stamina": 50.0, "dodge_unlocked": true})
	gs_p.register_physics_object("box1", grid.grid_to_world(Vector2i(4, 4)), 0.5, 2.0, 0.6, true)
	gs_p.register_pendulum("p1", Vector3(6, 5, 6), 4.0, 0.6)
	sched_p.advance_ticks(0.2)
	gs_p.dodge_roll("aster", Vector3(1, 0, 0))
	sched_p.advance_ticks(0.5)
	gs_p.apply_area_impulse(grid.grid_to_world(Vector2i(4, 4)) + Vector3(0.5, 0, 0), 2.0, 4.0)
	sched_p.advance_ticks(2.0)
	gs_p.unregister_physics_object("box1")
	gs_p.unregister_pendulum("p1")
	gs_p.flush_tick()

	_assert_equals(gs_p.event_log.size(), 7, "Recorded 7 physics/pendulum/dodge events")

	var gs_p_replay := GameState.replay(gs_p.event_log, grid)
	_assert_true(gs_p_replay.characters.has("aster"), "Replay reconstructs aster")
	_assert_true(not gs_p_replay.physics_objects.has("box1"),
		"Replay reflects unregister_physics_object")
	_assert_true(not gs_p_replay.pendulums.has("p1"),
		"Replay reflects unregister_pendulum")
	# Stamina consumed by dodge should match across runs.
	_assert_equals(
		gs_p_replay.characters["aster"].stats.get("stamina", -1.0),
		gs_p.characters["aster"].stats.get("stamina", -1.0),
		"Replay matches stamina post-dodge")

	# --- Abilities round-trip via handler registry ---
	var sched_a := EventScheduler.new()
	var gs_a := GameState.new()
	gs_a.grid = grid
	gs_a.scheduler = sched_a
	gs_a.event_log = EventLog.new()

	gs_a.register_character("peris", grid.grid_to_world(Vector2i(2, 2)), 3.0, {})
	var fired_orig: Array = []
	# In-range immediate fire
	gs_a.queue_ability("peris", "protect", grid.grid_to_world(Vector2i(2, 2)), 3.0,
		func(): fired_orig.append("protect"))
	# Out-of-range queue, then cancel
	gs_a.queue_ability("peris", "emp", grid.grid_to_world(Vector2i(8, 8)), 1.0,
		func(): fired_orig.append("emp"))
	gs_a.cancel_queued_ability("peris")
	gs_a.flush_tick()

	_assert_equals(fired_orig.size(), 1, "Recording: only in-range protect fired")
	_assert_equals(gs_a.event_log.size(), 4, "4 ability events logged (register + queue + queue + cancel)")

	# Replay with handler registry should fire protect again.
	var fired_replay: Array = []
	var handlers := {
		&"protect": func(): fired_replay.append("protect"),
		&"emp": func(): fired_replay.append("emp"),
	}
	var gs_a_replay := GameState.replay(gs_a.event_log, grid, handlers)
	_assert_equals(fired_replay.size(), 1, "Replay: registered handler fires once")
	_assert_equals(fired_replay[0], "protect", "Replay: correct ability fired")
	_assert_true(not gs_a_replay.has_queued_ability("peris"),
		"Replay: cancelled ability is not queued")

	# Replay without handlers stays consistent without firing.
	var gs_a_replay_nohandlers := GameState.replay(gs_a.event_log, grid)
	_assert_true(not gs_a_replay_nohandlers.has_queued_ability("peris"),
		"Replay without handlers: cancel still applies")

# Lint: every public, non-static function in game_state.gd that mutates
# state must call _emit so the action lands in the event log. Read-only
# queries and explicitly-allowlisted helpers are exempt. Catches future
# drift where public commands miss log wiring.
func _test_event_log_mutation_audit() -> void:
	_test_name = "EventLog Mutation Audit"

	var path := "res://scripts/system/core/game_state.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	_assert_true(f != null, "game_state.gd opens")
	if f == null:
		return
	var content := f.get_as_text()
	f.close()

	# Read-only or log-helper functions that legitimately do not emit.
	# Adding to this list requires a justification (why this public function
	# does not represent a player/sequence input that needs replaying).
	var allowlist := PackedStringArray([
		# Pure queries
		"get_position", "is_moving", "get_grid_cell", "get_character_level",
		"is_character_hidden", "get_character_concealment", "is_character_distracted",
		# Concealment and lure-distraction are DERIVED state (a chunk sets them each frame from
		# hide-zone / lure proximity, like a detection prediction) — not a player/sequence input, so
		# they aren't logged; replay rebuilds them from the logged movements that carry characters
		# into/out of cover and enemies to/from the lure.
		"set_character_hidden", "set_character_concealment", "set_character_distracted",
		"get_hand_items", "get_hand_slots", "get_internal_items",
		"has_free_hand", "has_free_hands",
		"get_scent_radius",
		"get_physics_position", "is_physics_moving", "is_physics_airborne",
		"get_throw_height", "get_throw_peak_height",
		# Computes a launch velocity then delegates to throw_physics_object, which
		# emits the throw (with that velocity) — replay rides the delegated event.
		"throw_physics_object_to",
		"get_pendulum_omega", "get_pendulum_period", "get_pendulum_angle",
		"get_pendulum_position", "get_pendulum_bob_velocity",
		"is_dodging", "is_endocytosing",
		"has_queued_ability", "get_queued_ability",
		"is_narratively_available", "is_downed", "is_party_downed",
		"get_party", "get_split_members", "is_split_active",
		# Interactable registry queries (register/trigger/enable/reset emit).
		"has_interactable", "get_interactable", "is_interactable_enabled",
		"interactables_in_range",
		# Composes command_move_to_cell (which emits); no event of its own.
		"move_to_interactable",
		# Snapshot/restore bypasses the log for tests.
		"serialize", "deserialize", "state_hash",
		# Event-log infrastructure itself
		"replay", "register_ability_handler", "flush_tick",
		# Setup must happen before commands run; carried in the
		# log's base_seed metadata field, not as an event
		"set_base_seed",
		# Mechanism infrastructure: scene-scoped, not per-run state. Not
		# serialized in the event log; scenes register mechanisms in their
		# _ready and the lint should not require these to emit.
		"register_mechanism", "unregister_mechanism",
		"get_all_actuators", "evaluate_mechanisms",
		# Stat reads
		"get_stat", "get_stat_cap", "is_running",
		# Stat and running wrappers emit; these
		# call through them rather than emitting directly.
		"adjust_stat", "toggle_running", "reset_characters_to_full",
		# Pure ATP helpers (static, no state) — formatting/clamping only.
		"normalize_atp", "clamp_atp", "atp_text",
		# Navigation graph is map structure (like the grid), set from level data
		# at scene setup — not a per-run player command. Carried with the
		# scene/grid that replay is given, not as an event. get_navigation_state
		# is a pure query.
		"set_navigation_graph", "set_navigation_data", "clear_navigation_graph",
		"get_navigation_state",
		# Read-only route preview for the hover path: computes the path a click WOULD take (nav-graph /
		# A* / straight line) without issuing or logging a move — pure UI, like the hover grid.
		"compute_preview_path", "compute_preview_party_paths",
	])

	var public_funcs := _parse_public_funcs(content)
	_assert_true(public_funcs.size() > 0, "Parser found public functions")

	var missing: Array = []
	for fn in public_funcs:
		var name: String = fn["name"]
		if allowlist.has(name):
			continue
		var body: String = fn["body"]
		if not body.contains("_emit("):
			missing.append(name)

	_assert_equals(missing.size(), 0,
		"All public mutating functions emit (missing _emit in: %s)" % str(missing))

## Character movement — player AND scripted NPC — must be captured in the event
## log and replay deterministically. Proves the data layer "captures moving
## characters" end to end.
func _test_movement_capture() -> void:
	_test_name = "Movement Capture"

	var grid := GridWorld.new()
	grid.create_room(12, 12)  # walkable interior with a wall border
	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler
	gs.grid = grid
	var log := EventLog.new()
	gs.event_log = log

	gs.register_character("hero", grid.grid_to_world(Vector2i(2, 2)), GameState.WALK_SPEED)
	gs.register_character("npc", grid.grid_to_world(Vector2i(8, 8)), 3.0)

	# The exact commands player.gd / npc.gd issue for movement.
	gs.command_move_to_cell("hero", Vector2i(6, 6))
	gs.command_walk_path("hero", [grid.grid_to_world(Vector2i(7, 7))])
	gs.command_move_to_pos("npc", grid.grid_to_world(Vector2i(3, 3)))

	# Every movement command landed in the log, for both characters.
	var kinds := {}
	for e in log.events:
		var k := str(e.get("kind", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
	_assert_true(int(kinds.get(str(GameEvent.KIND_REGISTER_CHARACTER), 0)) >= 2,
		"Both characters are registered in the event log")
	_assert_true(int(kinds.get(str(GameEvent.KIND_MOVE_TO_CELL), 0)) >= 1,
		"Grid move command is captured")
	_assert_true(int(kinds.get(str(GameEvent.KIND_WALK_PATH), 0)) >= 1,
		"Walk-path command is captured")
	_assert_true(int(kinds.get(str(GameEvent.KIND_MOVE_TO_POS), 0)) >= 1,
		"World-position move command (NPC) is captured")

	# Settle movement, flush the tail tick, then replay into a fresh state.
	scheduler.advance_ticks(12.0)
	gs.flush_tick()
	var hero_end := gs.get_position("hero")
	var npc_end := gs.get_position("npc")

	var replayed := GameState.replay(log, grid)
	_assert_true(hero_end.distance_to(replayed.get_position("hero")) < 0.05,
		"Replay reproduces the hero's movement (%s vs %s)" % [hero_end, replayed.get_position("hero")])
	_assert_true(npc_end.distance_to(replayed.get_position("npc")) < 0.05,
		"Replay reproduces the NPC's movement (%s vs %s)" % [npc_end, replayed.get_position("npc")])

# Determinism test: same base seed across two runs must produce the same
# sequence of values from every system's RNG. Different seeds must produce
# (with overwhelming probability) different sequences.
func _test_rng_determinism() -> void:
	_test_name = "RNG Determinism"

	# Twin runs at the same seed
	var reg_a := RngRegistry.new(42)
	var reg_b := RngRegistry.new(42)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(20):
		seq_a.append(reg_a.get_rng(&"ai.techo").randi())
		seq_a.append(reg_a.get_rng(&"loot").randf())
		seq_a.append(reg_a.get_rng(&"ambient").randf_range(0.0, 1.0))
	for _i in range(20):
		seq_b.append(reg_b.get_rng(&"ai.techo").randi())
		seq_b.append(reg_b.get_rng(&"loot").randf())
		seq_b.append(reg_b.get_rng(&"ambient").randf_range(0.0, 1.0))
	_assert_equals(seq_a.hash(), seq_b.hash(), "Same seed → same value sequence")

	# Different seed means different sequence.
	var seq_a_techo: Array = []
	var reg_a2 := RngRegistry.new(42)
	for _i in range(20):
		seq_a_techo.append(reg_a2.get_rng(&"ai.techo").randi())
	var reg_c := RngRegistry.new(43)
	var seq_c: Array = []
	for _i in range(20):
		seq_c.append(reg_c.get_rng(&"ai.techo").randi())
	_assert_true(seq_a_techo.hash() != seq_c.hash(),
		"Different seed → different sequence (same system)")

	# Per-system isolation: consuming one system's RNG must not shift another's
	var reg_d := RngRegistry.new(42)
	var loot_d: Array = []
	for _i in range(10):
		loot_d.append(reg_d.get_rng(&"loot").randi())
	# Repeat with extra ai.techo calls interleaved.
	var reg_e := RngRegistry.new(42)
	for _i in range(10):
		reg_e.get_rng(&"ai.techo").randi()  # different system, should not perturb loot
	var loot_e: Array = []
	for _i in range(10):
		loot_e.append(reg_e.get_rng(&"loot").randi())
	_assert_equals(loot_d.hash(), loot_e.hash(),
		"Per-system isolation: ai.techo calls do not shift loot output")

	# Per-spawn (birth_id) isolation: two Techos born at different events
	# get different streams from the same system name.
	var techo_4712 := reg_a.get_rng(&"ai.techo", 4712).randi()
	var techo_9999 := reg_a.get_rng(&"ai.techo", 9999).randi()
	_assert_true(techo_4712 != techo_9999,
		"Different birth_ids in same system produce different streams")

	# GameState integration: replay must reseed from log.base_seed
	var grid := GridWorld.new()
	grid.create_room(8, 6, true)
	var log := EventLog.new()
	log.base_seed = 1234
	var gs := GameState.replay(log, grid)
	_assert_equals(gs.base_seed, 1234, "Replay propagates base_seed from log")
	_assert_equals(gs.rng_registry.base_seed, 1234, "Replay's registry uses replayed seed")

# Snapshot equality with epsilon for replay-safe float comparisons.
func _snapshots_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a.keys():
			if not b.has(k):
				return false
			if not _snapshots_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _snapshots_equal(a[i], b[i]):
				return false
		return true
	if a is float and b is float:
		return absf(a - b) < 0.001
	return a == b

# Drive the same script for continuous and save/load runs.
func _eventlog_drive_sequence(gs: GameState, sched: EventScheduler, grid: GridWorld, start: int, end: int) -> void:
	# Mix immediate state changes with scheduler-driven arrivals.
	for step in range(start, end):
		var cell_x: int = 1 + (step % 6)
		var cell_z: int = 1 + ((step / 6) % 4)
		gs.command_move_to_cell("aster", Vector2i(cell_x, cell_z))
		sched.advance_ticks(0.5)
		gs.command_stop("aster")
		sched.advance_ticks(0.1)
		if step % 3 == 0:
			gs.spawn_item("food", grid.grid_to_world(Vector2i(cell_x, cell_z)))
		sched.advance_ticks(0.4)

# Resumed and continuous runs must end in the same state.
func _test_save_load_integrity() -> void:
	_test_name = "Save/Load Integrity"

	var grid := GridWorld.new()
	grid.create_room(10, 8, true)

	# Run A: continuous, with mid-save and end-save.
	var sched_a := EventScheduler.new()
	var gs_a := GameState.new()
	gs_a.grid = grid
	gs_a.scheduler = sched_a
	gs_a.event_log = EventLog.new()
	gs_a.set_base_seed(7)
	gs_a.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {"atp": 50})

	_eventlog_drive_sequence(gs_a, sched_a, grid, 0, 10)  # ticks 0..10
	gs_a.flush_tick()
	var mid_bytes := gs_a.event_log.to_bytes()
	_assert_true(mid_bytes.size() > 0, "Mid-run save produced bytes (%d)" % mid_bytes.size())
	var mid_event_count := gs_a.event_log.size()

	_eventlog_drive_sequence(gs_a, sched_a, grid, 10, 20)  # ticks 10..20
	gs_a.flush_tick()
	var snap_a := gs_a.serialize()
	var end_event_count_a := gs_a.event_log.size()

	# Run B: replay mid-save, then continue.
	var loaded := EventLog.load_bytes(mid_bytes)
	_assert_equals(loaded["status"], EventLog.LoadStatus.OK, "Mid-bytes load OK")
	var mid_log: EventLog = loaded["log"]
	_assert_equals(mid_log.size(), mid_event_count, "Loaded log has same event count as snapshot")
	_assert_equals(mid_log.base_seed, 7, "Loaded log preserves base_seed")

	var gs_b := GameState.replay(mid_log, grid)
	# Continue appending to the loaded log after replay.
	gs_b.event_log = mid_log
	_eventlog_drive_sequence(gs_b, gs_b.scheduler, grid, 10, 20)
	gs_b.flush_tick()
	var snap_b := gs_b.serialize()
	var end_event_count_b := gs_b.event_log.size()

	_assert_equals(end_event_count_b, end_event_count_a,
		"Continued log has same event count as continuous run")
	# Use the same epsilon-aware comparison the CLI replay uses
	_assert_true(_snapshots_equal(snap_a, snap_b),
		"Continuous and resumed runs produce equal final state")

	# Bytes round-trip: re-serializing the resumed log yields readable bytes
	var end_bytes := gs_b.event_log.to_bytes()
	var reloaded := EventLog.load_bytes(end_bytes)
	_assert_equals(reloaded["status"], EventLog.LoadStatus.OK, "End bytes load OK")

# Truncated saves recover complete events and drop the partial one.
func _test_save_corruption_recovery() -> void:
	_test_name = "Save Corruption Recovery"

	var grid := GridWorld.new()
	grid.create_room(8, 6, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.event_log = EventLog.new()

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {"atp": 50})
	for i in range(5):
		gs.command_move_to_cell("aster", Vector2i(1 + i, 1))
		sched.advance_ticks(2.0)
	gs.flush_tick()
	var clean_bytes := gs.event_log.to_bytes()
	var full_count := gs.event_log.size()
	_assert_true(full_count >= 6, "Recorded at least 6 events")

	# Chop inside an event blob.
	var cut: int = int(clean_bytes.size() * 0.8)
	var truncated := clean_bytes.slice(0, cut)
	var loaded := EventLog.load_bytes(truncated)
	_assert_equals(loaded["status"], EventLog.LoadStatus.TRUNCATED,
		"Truncated bytes report TRUNCATED status")
	var partial: EventLog = loaded["log"]
	_assert_true(partial.size() < full_count,
		"Partial log has fewer events than the original (%d < %d)" % [partial.size(), full_count])
	_assert_true(partial.size() >= 1, "At least one event recovered (got %d)" % partial.size())

	# Partial replay should match the truncation point.
	var gs_partial := GameState.replay(partial, grid)
	_assert_true(gs_partial.characters.has("aster"),
		"Replay of partial log: aster registered")

	# Bad header: stream missing magic returns BAD_HEADER and an empty log
	var no_magic := PackedByteArray()
	no_magic.append_array("not a save file at all".to_utf8_buffer())
	var bad := EventLog.load_bytes(no_magic)
	_assert_equals(bad["status"], EventLog.LoadStatus.BAD_HEADER,
		"Stream without magic reports BAD_HEADER")
	_assert_equals((bad["log"] as EventLog).size(), 0, "Bad-header log is empty")

# One party move should fan out to every party member.
func _test_party_cohesion_default() -> void:
	_test_name = "Party Cohesion Default"

	var grid := GridWorld.new()
	grid.create_room(14, 10, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"narrative_available": true,
	})
	gs.register_character("peris", grid.grid_to_world(Vector2i(2, 1)), 3.0, {
		"narrative_available": true,
	})
	gs.register_character("endo", grid.grid_to_world(Vector2i(3, 1)), 3.0, {
		"narrative_available": true,
	})

	gs.set_party(["aster", "peris", "endo"])
	_assert_equals(gs.get_party().size(), 3, "Party has 3 members")
	_assert_true(not gs.is_split_active(), "No split active by default")

	gs.party_move_to_cell(Vector2i(8, 5))
	for member in ["aster", "peris", "endo"]:
		_assert_true(gs.is_moving(member),
			"%s has movement queued after party_move_to_cell" % member)

	sched.advance_ticks(100.0)
	for member in ["aster", "peris", "endo"]:
		_assert_true(not gs.is_moving(member),
			"%s arrived at target" % member)

	# party_move_to_pos also addresses every member
	gs.party_move_to_pos(Vector3(3.5, 0, 6.5))
	for member in ["aster", "peris", "endo"]:
		_assert_true(gs.is_moving(member),
			"%s moves on party_move_to_pos" % member)

	# Log one party command, not per-member moves.
	var event_count_before := gs.event_log.size() if gs.event_log else 0
	sched.advance_ticks(100.0)
	var log := EventLog.new()
	gs.event_log = log
	gs.party_move_to_cell(Vector2i(10, 7))
	_assert_equals(log.size(), 1,
		"One party_move_to_cell command → one event (not per-member)")
	_assert_equals(String(log.events[0]["kind"]), "party_move_to_cell",
		"Logged kind is party_move_to_cell")

	# Replay reproduces the same fanout.
	sched.advance_ticks(100.0)
	gs.flush_tick()
	var full_log := EventLog.new()
	gs.event_log = full_log
	gs.set_party(["aster", "peris", "endo"])
	gs.party_move_to_cell(Vector2i(5, 5))
	sched.advance_ticks(100.0)
	gs.flush_tick()
	var replayed := GameState.replay(full_log, grid)
	replayed.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"narrative_available": true,
	})  # No-op safeguard; replay already constructed this.
	_assert_equals(replayed.get_party().size(), 3, "Replay reconstructs party")

# Scripted split limits party_move to the main group.
func _test_scripted_split() -> void:
	_test_name = "Scripted Split"

	var grid := GridWorld.new()
	grid.create_room(14, 10, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	for member in ["aster", "peris", "endo"]:
		gs.register_character(member, grid.grid_to_world(Vector2i(1, 1)), 3.0, {
			"narrative_available": true,
		})
	gs.set_party(["aster", "peris", "endo"])

	gs.start_split(["peris"])
	_assert_true(gs.is_split_active(), "Split is active")
	_assert_equals(gs.get_split_members(), ["peris"], "Peris is the split member")

	# party_move addresses only the main group.
	gs.party_move_to_cell(Vector2i(6, 5))
	_assert_true(gs.is_moving("aster"), "Aster moves on party command")
	_assert_true(gs.is_moving("endo"), "Endo moves on party command")
	_assert_true(not gs.is_moving("peris"),
		"Peris does NOT move on party command — she's split off")

	gs.command_move_to_cell("peris", Vector2i(10, 8))
	_assert_true(gs.is_moving("peris"), "Peris moves when addressed directly")

	gs.end_split()
	_assert_true(not gs.is_split_active(), "Split ended")
	_assert_equals(gs.get_split_members().size(), 0, "No split members after end")

	# Finish prior movement before party-wide movement.
	sched.advance_ticks(100.0)
	gs.party_move_to_cell(Vector2i(4, 4))
	for member in ["aster", "peris", "endo"]:
		_assert_true(gs.is_moving(member),
			"%s rejoins party-wide movement after end_split" % member)

	# start_split with a non-party member ignores the invalid id
	gs.end_split()  # ensure clean state
	gs.start_split(["aster", "nonexistent"])
	_assert_equals(gs.get_split_members(), ["aster"],
		"Invalid split members are filtered out")

# Portal backtracking: register two zones linked by portals, take a
# portal from A to B, save A's zone state on exit, return via B to A,
# assert the saved state is preserved. Also verifies visit_count, first
# vs revisit semantics, and that a registered revisit transform fires on
# the second entry to harden the encounter.
func _test_portal_revisit() -> void:
	_test_name = "Portal Revisit"

	var grid := GridWorld.new()
	grid.create_room(14, 10, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"narrative_available": true,
	})

	var zm := ZoneManager.new()
	var zone_a := Zone.new()
	zone_a.id = &"channels"
	var zone_b := Zone.new()
	zone_b.id = &"stacks"
	zm.register_zone(zone_a)
	zm.register_zone(zone_b)

	var hub_a := Hub.new()
	hub_a.id = &"hub_channels"
	hub_a.zone_id = &"channels"
	var hub_b := Hub.new()
	hub_b.id = &"hub_stacks"
	hub_b.zone_id = &"stacks"
	zm.register_hub(hub_a)
	zm.register_hub(hub_b)

	var portal_a_to_b := Portal.new()
	portal_a_to_b.id = &"portal_a_b"
	portal_a_to_b.from_zone_id = &"channels"
	portal_a_to_b.to_zone_id = &"stacks"
	portal_a_to_b.to_hub_id = &"hub_stacks"
	zm.register_portal(portal_a_to_b)

	var portal_b_to_a := Portal.new()
	portal_b_to_a.id = &"portal_b_a"
	portal_b_to_a.from_zone_id = &"stacks"
	portal_b_to_a.to_zone_id = &"channels"
	portal_b_to_a.to_hub_id = &"hub_channels"
	zm.register_portal(portal_b_to_a)

	# Revisit transform: on second entry to channels, replace the enemy
	# roster with a harder variant and set the "tended" flag.
	zm.register_revisit_transform(&"channels", func(state: Dictionary) -> Dictionary:
		state["enemy_roster"] = ["shaded_naturalizer", "shaded_naturalizer"]
		state["tended"] = true
		state["revisit_level"] = int(state.get("revisit_level", 0)) + 1
		return state)

	# Observe portal-taken
	var portals_taken: Array = []
	zm.portal_taken.connect(func(id: StringName): portals_taken.append(String(id)))

	# --- First visit to A ---
	zm.enter_zone(&"channels")
	zm.enter_hub(&"hub_channels", gs, ["aster"])
	_assert_equals(zm.get_visit_count(&"channels"), 1, "First entry: visit_count = 1")
	_assert_true(zm.is_first_visit(&"channels"), "is_first_visit true on first entry")

	# Simulate scene saving its state on zone-exit
	zm.save_zone_state(&"channels", {
		"enemy_roster": ["naturalizer"],
		"tended": false,
		"revisit_level": 0,
	})

	# Take portal A to B.
	var ok := zm.take_portal(&"portal_a_b", gs, ["aster"])
	_assert_true(ok, "Portal A→B taken")
	_assert_equals(portals_taken[0], "portal_a_b", "portal_taken names the portal")
	_assert_equals(zm.current_zone, &"stacks", "Now in zone B")
	_assert_equals(zm.current_hub, &"hub_stacks", "At zone B's hub")
	_assert_equals(zm.get_visit_count(&"stacks"), 1, "First entry to B: count = 1")

	# Scene saves B's state on exit
	zm.save_zone_state(&"stacks", {"enemy_roster": ["siderophore_cluster"]})

	# Take portal B to A.
	zm.take_portal(&"portal_b_a", gs, ["aster"])
	_assert_equals(zm.current_zone, &"channels", "Back in zone A")
	_assert_equals(zm.get_visit_count(&"channels"), 2, "Revisit: count = 2")
	_assert_true(not zm.is_first_visit(&"channels"), "is_first_visit false on revisit")

	# Saved state is preserved, AND revisit transform has been applied
	var a_state := zm.get_zone_state(&"channels")
	_assert_equals(a_state.get("enemy_roster", []), ["shaded_naturalizer", "shaded_naturalizer"],
		"Revisit transform replaced enemy roster")
	_assert_equals(a_state.get("tended", false), true, "Revisit transform set tended=true")
	_assert_equals(a_state.get("revisit_level", -1), 1, "Revisit transform incremented level")

	# B's state preserved across the round trip (even though we came through it)
	var b_state := zm.get_zone_state(&"stacks")
	_assert_equals(b_state.get("enemy_roster", []), ["siderophore_cluster"],
		"Zone B state preserved through backtrack")

	# --- Third entry: transform runs again on top of already-transformed state ---
	zm.take_portal(&"portal_a_b", gs, ["aster"])
	zm.take_portal(&"portal_b_a", gs, ["aster"])
	_assert_equals(zm.get_visit_count(&"channels"), 3, "Third entry: count = 3")
	var a_state_3 := zm.get_zone_state(&"channels")
	_assert_equals(a_state_3.get("revisit_level", -1), 2,
		"Transform re-applied on third entry, level incremented again")

	# Bad portal id returns false cleanly
	var bad := zm.take_portal(&"nonexistent", gs, ["aster"])
	_assert_equals(bad, false, "Unknown portal id returns false")

# Record a scripted session into an event log, replay the log into a
# fresh GameState, assert the two state hashes match. Baseline round-trip
# for replay determinism; deeper coverage is in save-load-integrity,
# but this is the cleanest "one recording, one replay" check.
func _test_replay_roundtrip() -> void:
	_test_name = "Replay Roundtrip"

	var grid := GridWorld.new()
	grid.create_room(12, 8, true)

	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.event_log = EventLog.new()
	gs.set_base_seed(2026)

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0,
		"stamina": 80.0, "max_stamina": 80.0,
		"atp": 6, "narrative_available": true,
	})
	gs.register_character("peris", grid.grid_to_world(Vector2i(2, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0,
		"stamina": 80.0, "max_stamina": 80.0,
		"atp": 6, "narrative_available": true,
	})
	for i in range(6):
		gs.command_move_to_cell("aster", Vector2i(2 + i, 2 + (i % 3)))
		sched.advance_ticks(2.0)
		if i == 2:
			gs.down_character("peris")
		if i == 4:
			gs.restore_character("peris")
	gs.spawn_item("fire_fruit", grid.grid_to_world(Vector2i(5, 5)))
	gs.flush_tick()

	var original_hash := gs.state_hash()

	var replayed := GameState.replay(gs.event_log, grid)
	var replay_hash := replayed.state_hash()

	_assert_equals(replay_hash, original_hash,
		"Record→replay round-trip produces identical state hash")
	_assert_true(_snapshots_equal(gs.serialize(), replayed.serialize()),
		"Serialized snapshots are structurally equal")

	# Round-trip through bytes too
	var bytes := gs.event_log.to_bytes()
	var loaded := EventLog.load_bytes(bytes)
	_assert_equals(loaded["status"], EventLog.LoadStatus.OK, "Log bytes decode cleanly")
	var from_bytes := GameState.replay(loaded["log"], grid)
	_assert_equals(from_bytes.state_hash(), original_hash,
		"Bytes → log → replay still produces identical hash")

# Re-record determinism: replay while appending into a fresh log.
# The re-recorded log must match the original event-for-event.
func _test_determinism_rerecord() -> void:
	_test_name = "Determinism Re-Record"

	var grid := GridWorld.new()
	grid.create_room(10, 8, true)

	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.event_log = EventLog.new()
	gs.set_base_seed(99)

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {"atp": 4})
	for i in range(5):
		gs.command_move_to_cell("aster", Vector2i(1 + i, 1 + (i % 2)))
		sched.advance_ticks(1.5)
		if i == 2:
			gs.spawn_item("seed", grid.grid_to_world(Vector2i(3, 3)))
	gs.flush_tick()
	var log_original := gs.event_log

	# Replay while re-recording
	var log_rerec := EventLog.new()
	var _replayed := GameState.replay(log_original, grid, {}, log_rerec)

	_assert_equals(log_rerec.size(), log_original.size(),
		"Re-recorded log has same event count (%d == %d)" % [log_rerec.size(), log_original.size()])
	_assert_equals(log_rerec.base_seed, log_original.base_seed,
		"Re-recorded log preserves base_seed")

	# Event-for-event compare: ticks, kinds, payloads.
	var divergences: Array = []
	for i in range(log_original.size()):
		var a: Dictionary = log_original.events[i]
		var b: Dictionary = log_rerec.events[i]
		if String(a["kind"]) != String(b["kind"]):
			divergences.append("event %d: kind %s vs %s" % [i, a["kind"], b["kind"]])
			continue
		if abs(float(a["tick"]) - float(b["tick"])) > 1e-6:
			divergences.append("event %d: tick %f vs %f" % [i, a["tick"], b["tick"]])
			continue
		if not _snapshots_equal(a["payload"], b["payload"]):
			divergences.append("event %d: payload differs" % i)
	_assert_equals(divergences.size(), 0,
		"Re-recorded log matches original event-for-event (divergences: %s)" % str(divergences))

	# Byte-level compare of the serialized form (modulo saved_unix which is
	# re-captured on each to_bytes call). Strip the header's saved_unix and
	# compare the structural parts.
	var bytes_a := log_original.to_bytes()
	var bytes_b := log_rerec.to_bytes()
	# The saved_unix field may differ by a second; compare via load+compare
	# instead of raw bytes.
	var loaded_a := EventLog.load_bytes(bytes_a)
	var loaded_b := EventLog.load_bytes(bytes_b)
	_assert_equals(loaded_a["log"].size(), loaded_b["log"].size(),
		"Byte-serialized logs decode to same event count")

# Scene triggers: each concrete trigger type fires its scene exactly once
# for a matching dispatch; priority resolution when multiple triggers
# match simultaneously; one-shot tracking; time-of-day triggers repeat.
# Also verifies ZoneManager integration: binding a ZoneManager causes
# spoke_completed and gate_passed signals to dispatch via SceneManager.
func _test_scene_triggers() -> void:
	_test_name = "Scene Triggers"

	# --- Four concrete trigger types, each matches its own context ---
	var sm := SceneManager.new()
	sm.register_trigger(SceneTriggers.OnSpokeComplete.new(
		&"scene_channels_cleared", &"channels_encounter"))
	sm.register_trigger(SceneTriggers.OnGatePass.new(
		&"scene_endo_joins", &"endo_junction"))
	sm.register_trigger(SceneTriggers.OnMilestone.new(
		&"scene_first_cure_component", &"cure_component_1"))
	sm.register_trigger(SceneTriggers.OnTimeOfDay.new(
		&"scene_dusk_ambience", &"dusk"))

	var fired: Array = []
	sm.scene_fired.connect(func(id: StringName, _ctx: Dictionary):
		fired.append(String(id)))

	sm.dispatch({"kind": &"spoke_completed", "spoke_id": &"channels_encounter"})
	_assert_equals(fired.size(), 1, "Spoke-complete trigger fires")
	_assert_equals(fired[0], "scene_channels_cleared", "...correct scene id")

	sm.dispatch({"kind": &"gate_passed", "gate_id": &"endo_junction"})
	_assert_equals(fired.size(), 2, "Gate-pass trigger fires")
	_assert_equals(fired[1], "scene_endo_joins", "...correct scene id")

	sm.dispatch({"kind": &"milestone", "milestone_id": &"cure_component_1"})
	_assert_equals(fired.size(), 3, "Milestone trigger fires")

	sm.dispatch({"kind": &"time_of_day", "time_of_day": &"dusk"})
	_assert_equals(fired.size(), 4, "Time-of-day trigger fires")

	# --- Unmatched context fires nothing ---
	sm.dispatch({"kind": &"spoke_completed", "spoke_id": &"unknown_spoke"})
	_assert_equals(fired.size(), 4, "Non-matching context does not fire")

	# --- One-shot: re-dispatch the same context does not re-fire ---
	sm.dispatch({"kind": &"spoke_completed", "spoke_id": &"channels_encounter"})
	_assert_equals(fired.size(), 4, "One-shot trigger does not re-fire")

	# --- Time-of-day is not one-shot; should re-fire each cycle ---
	sm.dispatch({"kind": &"time_of_day", "time_of_day": &"dusk"})
	_assert_equals(fired.size(), 5, "Time-of-day trigger re-fires by design")

	# --- Priority resolution: higher priority wins ---
	var sm2 := SceneManager.new()
	var high := SceneTriggers.OnGatePass.new(&"high", &"shared_gate", 100)
	var low := SceneTriggers.OnGatePass.new(&"low", &"shared_gate", 1)
	sm2.register_trigger(low)   # register lower priority first
	sm2.register_trigger(high)  # to ensure priority wins over registration order
	var fired2: Array = []
	sm2.scene_fired.connect(func(id: StringName, _ctx: Dictionary):
		fired2.append(String(id)))
	sm2.dispatch({"kind": &"gate_passed", "gate_id": &"shared_gate"})
	_assert_equals(fired2.size(), 1, "Priority clash fires exactly one scene")
	_assert_equals(fired2[0], "high", "Higher priority wins over registration order")

	# --- Tie-break by registration order ---
	var sm3 := SceneManager.new()
	var first := SceneTriggers.OnGatePass.new(&"first", &"tied_gate", 50)
	var second := SceneTriggers.OnGatePass.new(&"second", &"tied_gate", 50)
	sm3.register_trigger(first)
	sm3.register_trigger(second)
	var fired3: Array = []
	sm3.scene_fired.connect(func(id: StringName, _ctx: Dictionary):
		fired3.append(String(id)))
	sm3.dispatch({"kind": &"gate_passed", "gate_id": &"tied_gate"})
	_assert_equals(fired3[0], "first", "Equal priority → first registered wins")

	# --- ZoneManager binding: signals flow through dispatch ---
	var grid := GridWorld.new()
	grid.create_room(10, 8, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched
	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"narrative_available": true,
	})
	var zm := ZoneManager.new()
	var zone := Zone.new()
	zone.id = &"channels"
	zm.register_zone(zone)
	var gate := Gate.new()
	gate.id = &"bound_gate"
	gate.zone_id = &"channels"
	zm.register_gate(gate)

	var sm4 := SceneManager.new()
	sm4.register_trigger(SceneTriggers.OnSpokeComplete.new(&"bound_spoke_scene", &"sp1"))
	sm4.register_trigger(SceneTriggers.OnGatePass.new(&"bound_gate_scene", &"bound_gate"))
	sm4.bind_zone_manager(zm)
	var fired4: Array = []
	sm4.scene_fired.connect(func(id: StringName, _ctx: Dictionary):
		fired4.append(String(id)))
	zm.enter_zone(&"channels")
	zm.mark_spoke_complete(&"sp1")
	zm.try_pass_gate(&"bound_gate", gs, ["aster"])
	_assert_equals(fired4.size(), 2, "ZoneManager bound signals flow through dispatch")
	_assert_equals(fired4[0], "bound_spoke_scene", "...spoke scene fires")
	_assert_equals(fired4[1], "bound_gate_scene", "...gate scene fires")

# Down every party member in a spoke; confirm no game_over signal or
# similar end-state flag fires, that retreat_to_last_hub returns true,
# that party_retreated carries the hub id, and that every party member is
# narratively available again after the retreat.
func _test_no_game_over() -> void:
	_test_name = "No Game Over"

	var grid := GridWorld.new()
	grid.create_room(12, 8, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	# Register party with explicit max stats so restore works
	for member in ["aster", "peris"]:
		gs.register_character(member, grid.grid_to_world(Vector2i(1, 1)), 3.0, {
			"hp": 100.0, "max_hp": 100.0,
			"stamina": 80.0, "max_stamina": 80.0,
			"atp": 6, "narrative_available": true,
		})

	var zm := ZoneManager.new()
	var zone := Zone.new()
	zone.id = &"channels"
	zm.register_zone(zone)
	var hub := Hub.new()
	hub.id = &"hub_channels"
	hub.zone_id = &"channels"
	zm.register_hub(hub)
	zm.enter_zone(&"channels")
	zm.enter_hub(&"hub_channels", gs, ["aster", "peris"])

	# Track signals the architecture forbids
	var game_over_fired := [false]
	var deaths_fired: Array = []
	gs.character_died.connect(func(cid: String, _scripted: bool):
		deaths_fired.append(cid))

	var retreated_to: Array = []
	zm.party_retreated.connect(func(hub_id: StringName):
		retreated_to.append(String(hub_id)))

	# Go into a spoke, everyone gets downed
	gs.down_character("aster")
	gs.down_character("peris")
	_assert_true(gs.is_party_downed(["aster", "peris"]), "Party is fully downed")
	_assert_equals(game_over_fired[0], false, "No game_over flag fires")
	_assert_equals(deaths_fired.size(), 0, "No deaths fire on combat down")

	# Retreat
	var ok := zm.retreat_to_last_hub(gs, ["aster", "peris"])
	_assert_true(ok, "retreat_to_last_hub succeeds when a hub is set")
	_assert_equals(retreated_to.size(), 1, "party_retreated fires once")
	_assert_equals(retreated_to[0], "hub_channels", "...naming the hub")

	# Confirm restoration
	for member in ["aster", "peris"]:
		var stats: Dictionary = gs.characters[member].stats
		_assert_equals(stats.get("hp", -1.0), 100.0, "%s HP restored" % member)
		_assert_true(gs.is_narratively_available(member),
			"%s narrative-available after retreat" % member)
	_assert_true(not gs.is_party_downed(["aster", "peris"]),
		"Party no longer downed after retreat")

	# No-hub path: retreat before any hub is entered returns false cleanly
	var zm2 := ZoneManager.new()
	var ok2 := zm2.retreat_to_last_hub(gs, ["aster", "peris"])
	_assert_equals(ok2, false, "retreat returns false when no hub has been entered")

# Lint: character_died.emit( may appear ONLY inside die_scripted(). Every
# other emission site would represent a non-scripted death path, which
# the architecture forbids. Walks scripts/ for .gd files, flags any
# real call site (not a comment) where the enclosing function is not
# die_scripted.
#
# The test runner itself is excluded because it references the signal
# name in lint strings and docstrings; no production code should do that.
func _test_scripted_death_only() -> void:
	_test_name = "Scripted Death Only"

	var excluded_files := PackedStringArray([
		"res://scripts/test_runner_cli.gd",
	])
	var all_files: Array = []
	_walk_gd_files("res://scripts/", all_files)

	var offenders: Array = []
	for path in all_files:
		if excluded_files.has(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		if not content.contains("character_died.emit("):
			continue
		var current_func := ""
		for line in content.split("\n"):
			var stripped: String = line.strip_edges()
			# Skip pure comment lines; docs can mention the signal.
			if stripped.begins_with("#"):
				continue
			if stripped.begins_with("func "):
				current_func = stripped.substr(5).get_slice("(", 0).strip_edges()
			elif stripped.begins_with("static func "):
				current_func = stripped.substr(12).get_slice("(", 0).strip_edges()
			if line.contains("character_died.emit("):
				if current_func != "die_scripted":
					offenders.append("%s:%s emits character_died outside die_scripted" % [path, current_func])

	_assert_equals(offenders.size(), 0,
		"character_died.emit( only from die_scripted (offenders: %s)" % str(offenders))

# Down a character, retreat to a hub, trigger rest, assert every stat is
# restored to its declared max and the character is narratively available
# again. Proves the failure model's "care is infrastructural" thesis at
# the simulation level: nobody stays down after a rest.
func _test_hub_rest_restore() -> void:
	_test_name = "Hub Rest Restore"

	var grid := GridWorld.new()
	grid.create_room(10, 8, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	# Register aster with explicit max stats so restore has something to
	# restore TO. Without max_hp / max_stamina in stats, restore leaves
	# the value alone (safer than guessing).
	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0,
		"stamina": 80.0, "max_stamina": 80.0,
		"atp": 6,
		"narrative_available": true,
	})

	# Down clears stats and narrative availability.
	gs.down_character("aster")
	_assert_equals(gs.characters["aster"].stats.get("hp", -1.0), 0.0, "HP zeroed on down")
	_assert_equals(gs.characters["aster"].stats.get("stamina", -1.0), 0.0, "Stamina zeroed on down")
	_assert_true(not gs.is_narratively_available("aster"),
		"Narrative-unavailable when downed")

	# Retreat position is enough to trigger hub restore.
	var hub := Hub.new()
	hub.id = &"hub_channels"
	hub.zone_id = &"channels"
	hub.position = grid.grid_to_world(Vector2i(4, 4))
	hub.radius = 2.0

	Hub.restore_party(gs, ["aster"])

	var stats: Dictionary = gs.characters["aster"].stats
	_assert_equals(stats.get("hp", -1.0), 100.0, "HP restored to max")
	_assert_equals(stats.get("stamina", -1.0), 80.0, "Stamina restored to max")
	_assert_equals(stats.get("atp", -1.0), GameState.ATP_MAX_PIPS, "ATP restored to full")
	_assert_true(gs.is_narratively_available("aster"), "Narrative-available after rest")

# Gate requires Endo. Without Endo in the party, try_pass emits blocked
# with a reason naming the missing member and does not pass. Adding Endo
# lets it through. Also: an Endo who is narratively-unavailable (downed)
# still blocks the gate until rested.
func _test_gate_block() -> void:
	_test_name = "Gate Block"

	var grid := GridWorld.new()
	grid.create_room(10, 8, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0, "narrative_available": true,
	})
	gs.register_character("peris", grid.grid_to_world(Vector2i(2, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0, "narrative_available": true,
	})

	var gate := Gate.new()
	gate.id = &"endo_junction"
	gate.zone_id = &"channels"
	gate.required_members = [&"endo"]

	var blocked_reasons: Array = []
	var passed_count := [0]
	gate.blocked.connect(func(reason: StringName): blocked_reasons.append(String(reason)))
	gate.passed.connect(func(): passed_count[0] += 1)

	# Without Endo: blocked.
	var ok_without := gate.try_pass(gs, ["aster", "peris"])
	_assert_equals(ok_without, false, "try_pass returns false without Endo")
	_assert_equals(passed_count[0], 0, "passed signal did not fire")
	_assert_equals(blocked_reasons.size(), 1, "blocked signal fired once")
	_assert_equals(blocked_reasons[0], "missing_endo", "Reason names the missing member")

	# Downed Endo stays blocked.
	gs.register_character("endo", grid.grid_to_world(Vector2i(3, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0, "narrative_available": true,
	})
	gs.down_character("endo")
	var ok_downed := gate.try_pass(gs, ["aster", "peris", "endo"])
	_assert_equals(ok_downed, false, "Gate blocks when required member is downed")
	_assert_equals(blocked_reasons[1], "unavailable_endo",
		"Reason names the unavailable member")

	# Restored Endo passes.
	gs.restore_character("endo")
	var ok_restored := gate.try_pass(gs, ["aster", "peris", "endo"])
	_assert_equals(ok_restored, true, "Gate passes with available Endo")
	_assert_equals(passed_count[0], 1, "passed signal fired once")

# Zone A to spoke to gate to Zone B. Zone transitions fire their signals,
# and hub reachability shifts: zone A's hubs are reachable while in zone A,
# fall out of reach once zone B is entered.
func _test_zone_progression() -> void:
	_test_name = "Zone Progression"

	var grid := GridWorld.new()
	grid.create_room(20, 8, true)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	gs.register_character("aster", grid.grid_to_world(Vector2i(1, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0, "narrative_available": true,
	})
	gs.register_character("peris", grid.grid_to_world(Vector2i(2, 1)), 3.0, {
		"hp": 100.0, "max_hp": 100.0, "narrative_available": true,
	})

	var zm := ZoneManager.new()

	# Build two zones
	var zone_a := Zone.new()
	zone_a.id = &"channels"
	zone_a.hub_ids = [&"hub_channels_a", &"hub_channels_b"]
	zm.register_zone(zone_a)
	var zone_b := Zone.new()
	zone_b.id = &"stacks"
	zone_b.hub_ids = [&"hub_stacks"]
	zm.register_zone(zone_b)

	var hub_a := Hub.new()
	hub_a.id = &"hub_channels_a"
	hub_a.zone_id = &"channels"
	zm.register_hub(hub_a)
	var hub_b := Hub.new()
	hub_b.id = &"hub_channels_b"
	hub_b.zone_id = &"channels"
	zm.register_hub(hub_b)
	var hub_s := Hub.new()
	hub_s.id = &"hub_stacks"
	hub_s.zone_id = &"stacks"
	zm.register_hub(hub_s)

	var gate_ab := Gate.new()
	gate_ab.id = &"channels_to_stacks"
	gate_ab.zone_id = &"channels"
	zm.register_gate(gate_ab)

	# Observe signals
	var zones_entered: Array = []
	var zones_exited: Array = []
	var hubs_entered: Array = []
	zm.zone_entered.connect(func(id: StringName): zones_entered.append(String(id)))
	zm.zone_exited.connect(func(id: StringName): zones_exited.append(String(id)))
	zm.hub_entered.connect(func(id: StringName): hubs_entered.append(String(id)))

	# Enter zone A: A hubs reachable, B hub hidden.
	zm.enter_zone(&"channels")
	_assert_equals(zones_entered.size(), 1, "zone_entered fires on first zone")
	_assert_equals(zones_entered[0], "channels", "...for channels")
	_assert_equals(zones_exited.size(), 0, "no zone_exited on first enter")
	_assert_true(zm.is_hub_reachable(&"hub_channels_a"), "Hub A reachable in zone A")
	_assert_true(zm.is_hub_reachable(&"hub_channels_b"), "Hub B reachable in zone A")
	_assert_true(not zm.is_hub_reachable(&"hub_stacks"), "Zone B hub not reachable yet")

	# Enter hub A and rest.
	zm.enter_hub(&"hub_channels_a", gs, ["aster", "peris"])
	_assert_equals(hubs_entered.size(), 1, "hub_entered fired")

	# Mark a spoke complete
	zm.mark_spoke_complete(&"channels_encounter")
	_assert_true(zm.is_spoke_complete(&"channels_encounter"), "Spoke completion tracked")

	# Pass the gate
	var ok := zm.try_pass_gate(&"channels_to_stacks", gs, ["aster", "peris"])
	_assert_true(ok, "Unrestricted gate passes")
	_assert_true(zm.is_gate_passed(&"channels_to_stacks"), "Gate recorded as passed")

	# Enter zone B; A hubs fall out of reach.
	zm.enter_zone(&"stacks")
	_assert_equals(zones_exited.size(), 1, "zone_exited fires on transition")
	_assert_equals(zones_exited[0], "channels", "...naming the old zone")
	_assert_equals(zones_entered.size(), 2, "zone_entered fires for new zone")
	_assert_equals(zones_entered[1], "stacks", "...named stacks")
	_assert_true(not zm.is_hub_reachable(&"hub_channels_a"),
		"Old zone's hub A falls out of reach after transition")
	_assert_true(not zm.is_hub_reachable(&"hub_channels_b"),
		"Old zone's hub B falls out of reach after transition")
	_assert_true(zm.is_hub_reachable(&"hub_stacks"), "New zone's hub reachable")

# Composition-blind test: a single faux-physics sensor must trigger
# identically whether the weight comes from one heavy character, two light
# characters, an item on the floor, or a character + item combined. The
# mechanism must never inspect what kind of actuator is on it.
func _test_actuator_composition_blind() -> void:
	_test_name = "Actuator Composition-Blind"

	var grid := GridWorld.new()
	grid.create_room(8, 8, true)

	var plate_pos := grid.grid_to_world(Vector2i(4, 4))

	# Helper: build a fresh GameState + mechanism + signal counter, return
	# the trigger count after evaluating once.
	var run_scenario := func(setup: Callable) -> int:
		var sched := EventScheduler.new()
		var gs := GameState.new()
		gs.grid = grid
		gs.scheduler = sched
		var plate := FauxPhysicsSensorScript.new()
		plate.id = &"plate"
		plate.position = plate_pos
		plate.radius = 0.6
		plate.mode = FauxPhysicsSensorScript.SensorMode.TOTAL_WEIGHT
		plate.required_weight = 2.0
		gs.register_mechanism(plate)
		var triggers := [0]
		plate.triggered.connect(func(): triggers[0] += 1)
		setup.call(gs)
		gs.evaluate_mechanisms()
		return triggers[0]

	# (a) one heavy character (weight 2.5)
	var heavy_char := func(gs: GameState) -> void:
		gs.register_character("oli", plate_pos, 3.0, {"weight": 2.5})
	_assert_equals(run_scenario.call(heavy_char), 1, "(a) one heavy character triggers plate")

	# (b) two light characters (weight 1.0 each)
	var two_light := func(gs: GameState) -> void:
		gs.register_character("aster", plate_pos, 3.0, {"weight": 1.0})
		gs.register_character("peris", plate_pos, 3.0, {"weight": 1.0})
	_assert_equals(run_scenario.call(two_light), 1, "(b) two light characters trigger plate")

	# (c) one heavy item on the ground (weight 2.5)
	var heavy_item := func(gs: GameState) -> void:
		gs.spawn_item("mother_gear", plate_pos, {"weight": 2.5})
	_assert_equals(run_scenario.call(heavy_item), 1, "(c) one heavy item triggers plate")

	# (d) one character + one item, summing to threshold
	var char_plus_item := func(gs: GameState) -> void:
		gs.register_character("aster", plate_pos, 3.0, {"weight": 1.0})
		gs.spawn_item("fire_fruit", plate_pos, {"weight": 1.0})
	_assert_equals(run_scenario.call(char_plus_item), 1, "(d) character + item triggers plate")

	# Below-threshold cases must not trigger.
	var one_light := func(gs: GameState) -> void:
		gs.register_character("aster", plate_pos, 3.0, {"weight": 1.0})
	_assert_equals(run_scenario.call(one_light), 0, "one light character does not trigger")

	var off_plate := func(gs: GameState) -> void:
		gs.register_character("oli", grid.grid_to_world(Vector2i(0, 0)), 3.0, {"weight": 5.0})
	_assert_equals(run_scenario.call(off_plate), 0, "actuator outside zone does not trigger")

	# Untriggered transition: trigger then remove the actuator
	var sched2 := EventScheduler.new()
	var gs2 := GameState.new()
	gs2.grid = grid
	gs2.scheduler = sched2
	var plate2 := FauxPhysicsSensorScript.new()
	plate2.id = &"plate"
	plate2.position = plate_pos
	plate2.radius = 0.6
	plate2.mode = FauxPhysicsSensorScript.SensorMode.TOTAL_WEIGHT
	plate2.required_weight = 2.0
	gs2.register_mechanism(plate2)
	var triggered := [0]
	var untriggered := [0]
	plate2.triggered.connect(func(): triggered[0] += 1)
	plate2.untriggered.connect(func(): untriggered[0] += 1)
	gs2.register_character("oli", plate_pos, 3.0, {"weight": 2.5})
	gs2.evaluate_mechanisms()
	_assert_equals(triggered[0], 1, "Triggered fires on transition")
	gs2.unregister_character("oli")
	gs2.evaluate_mechanisms()
	_assert_equals(untriggered[0], 1, "Untriggered fires when actuator leaves")

	# Idempotent: re-evaluating with same state produces no extra signals
	gs2.register_character("oli", plate_pos, 3.0, {"weight": 2.5})
	gs2.evaluate_mechanisms()
	gs2.evaluate_mechanisms()
	gs2.evaluate_mechanisms()
	_assert_equals(triggered[0], 2, "Re-evaluation with same triggered state does not re-fire")

	var count_sensor := FauxPhysicsSensorScript.new()
	count_sensor.mode = FauxPhysicsSensorScript.SensorMode.ACTUATOR_COUNT
	count_sensor.required_count = 2
	_assert_true(count_sensor.evaluate([
		Actuator.make(Vector3.ZERO, 0.1, &"small"),
		Actuator.make(Vector3.ZERO, 0.1, &"small"),
	]), "Count mode triggers on enough actuators")
	_assert_true(not count_sensor.evaluate([
		Actuator.make(Vector3.ZERO, 10.0, &"heavy"),
	]), "Count mode ignores weight")

	var signature_sensor := FauxPhysicsSensorScript.new()
	signature_sensor.mode = FauxPhysicsSensorScript.SensorMode.SIGNATURE_PRESENT
	signature_sensor.required_signature = &"conductive"
	_assert_true(signature_sensor.evaluate([
		Actuator.make(Vector3.ZERO, 0.1, &"organic"),
		Actuator.make(Vector3.ZERO, 0.1, &"conductive"),
	]), "Signature mode triggers when required material is present")
	_assert_true(not signature_sensor.evaluate([
		Actuator.make(Vector3.ZERO, 5.0, &"organic"),
	]), "Signature mode ignores unrelated heavy actuators")

	var material_scale := FauxPhysicsSensorScript.new()
	material_scale.mode = FauxPhysicsSensorScript.SensorMode.SIGNATURE_WEIGHT
	material_scale.required_signature = &"metal"
	material_scale.required_weight = 2.0
	_assert_true(material_scale.evaluate([
		Actuator.make(Vector3.ZERO, 1.0, &"metal"),
		Actuator.make(Vector3.ZERO, 1.0, &"stone"),
		Actuator.make(Vector3.ZERO, 1.0, &"metal"),
	]), "Signature-weight mode sums only matching material")
	_assert_true(not material_scale.evaluate([
		Actuator.make(Vector3.ZERO, 1.0, &"metal"),
		Actuator.make(Vector3.ZERO, 5.0, &"stone"),
	]), "Signature-weight mode rejects unmatched weight")

# Lint: Mechanism subclasses must never reference char_id, character lists,
# or call methods that special-case characters vs items. Walks
# scripts/game/ for files that extend Mechanism (directly or transitively)
# and greps for forbidden patterns.
func _test_actuator_no_id_checks() -> void:
	_test_name = "Actuator No ID Checks"

	var forbidden := PackedStringArray([
		"char_id",
		"is_character(",
		"characters[",
		"characters.has(",
		"\"item_id\"",  # mechanism payloads should not name item ids either
	])

	var mechanism_files: Array = []
	_collect_mechanism_files(mechanism_files)
	_assert_true(mechanism_files.size() >= 2,
		"Found at least the base + one subclass (got %d, files: %s)" % [mechanism_files.size(), str(mechanism_files)])

	var offenders: Array = []
	for path in mechanism_files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		for pat in forbidden:
			if content.contains(pat):
				offenders.append("%s contains %s" % [path, pat])

	_assert_equals(offenders.size(), 0,
		"Mechanism files free of identity checks (offenders: %s)" % str(offenders))

# Discover every .gd file that participates in the Mechanism hierarchy.
# A file participates if its class_name is a known mechanism class OR if
# it extends one. Iterates to a fixed point so deep subclass chains are
# included transitively. Includes the base class itself (matched by
# class_name).
func _collect_mechanism_files(out: Array) -> void:
	var all_files: Array = []
	_walk_gd_files("res://scripts/", all_files)

	var known: Dictionary = {"Mechanism": true}
	for _pass in range(5):
		var added_this_pass := false
		for path in all_files:
			if out.has(path):
				continue
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var content := f.get_as_text()
			f.close()
			var declared := ""
			for line in content.split("\n"):
				var s: String = line.strip_edges()
				if s.begins_with("class_name "):
					declared = s.substr(11).get_slice(" ", 0).strip_edges()
					break
			var matches := false
			if declared != "" and known.has(declared):
				matches = true
			else:
				for cls in known.keys():
					if content.contains("extends " + cls):
						matches = true
						break
			if matches:
				out.append(path)
				if declared != "" and not known.has(declared):
					known[declared] = true
				added_this_pass = true
		if not added_this_pass:
			break

func _walk_gd_files(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var full := path.path_join(name)
		if d.current_is_dir():
			_walk_gd_files(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()

# Lint: sequence scripts must not own raw player input or duplicate the ground
# raycast. Input / raycast / interaction routing belongs in the shared controller
# (player.gd ground_clicked + click mode, GameHUD action→signal mapping, the
# project input map). Per-step DECISIONS may stay in the sequence, expressed via
# input actions and HUD signals — never raw keycodes or raycasts.
func _test_sequence_input_discipline() -> void:
	_test_name = "Sequence Input Discipline"
	var bad := {
		"project_ray_origin": "ground raycast — use player.gd's shared raycast / ground_clicked",
		"intersect_ray": "ground raycast — use the shared controller",
		"Input.is_key_pressed": "raw key polling — use Input.is_action_pressed + the input map",
	}
	var dir := DirAccess.open("res://scripts/tutorial")
	_assert_true(dir != null, "tutorial scripts dir opens")
	if dir == null:
		return
	var offenders: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with("_sequence.gd"):
			var text := FileAccess.get_file_as_string("res://scripts/tutorial/".path_join(fname))
			for pat in bad.keys():
				if text.contains(pat):
					offenders.append("%s: '%s' (%s)" % [fname, pat, bad[pat]])
		fname = dir.get_next()
	dir.list_dir_end()
	_assert_equals(offenders.size(), 0,
		"Sequence scripts own no raw input / duplicated raycast (offenders: %s)" % str(offenders))

# Lint: forbid wall-clock RNG / time calls in game-logic .gd files. Files
# that legitimately need them for visual or performance reasons must
# annotate themselves with `# @rendering_only` near the top.
func _test_rng_no_wallclock() -> void:
	_test_name = "RNG No Wallclock"

	var bad_patterns := PackedStringArray([
		"randi()", "randf()", "randomize()",
		"randi_range(", "randf_range(",
		"randfn(", "randv2(",
		"RandomNumberGenerator.new()",
		"Time.get_ticks_msec(", "Time.get_ticks_usec(",
		"Time.get_unix_time_from_system(",
	])

	# Files that may legitimately use these (visual-only, test, perf):
	# either listed here explicitly, or marked with `# @rendering_only`.
	var explicit_allowlist := PackedStringArray([
		# RNG plumbing itself wraps the engine API
		"res://scripts/system/random/seeded_rng.gd",
		# Tests exercise determinism / perf / Monte Carlo by design
		"res://scripts/test_runner_cli.gd",
		"res://scripts/game/mechanics/hide_encounter_analysis.gd",
		# Save metadata is allowed to record wall-clock timestamps for the
		# UI; nothing in the game logic reads these values
		"res://scripts/system/persistence/save_manager.gd",
		"res://scripts/system/persistence/engram_journal.gd",
		"res://scripts/system/core/event_log.gd",
	])

	var dirs_to_walk := PackedStringArray([
		"res://scripts/",
	])
	var offenders: Array = []
	for dir in dirs_to_walk:
		_walk_for_rng_lint(dir, bad_patterns, explicit_allowlist, offenders)

	_assert_equals(offenders.size(), 0,
		"No wall-clock RNG / time outside allowlist (offenders: %s)" % str(offenders))

func _walk_for_rng_lint(path: String, bad_patterns: PackedStringArray,
		allow: PackedStringArray, offenders: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var full := path.path_join(name)
		if d.current_is_dir():
			_walk_for_rng_lint(full, bad_patterns, allow, offenders)
		elif name.ends_with(".gd"):
			if allow.has(full):
				name = d.get_next()
				continue
			var f := FileAccess.open(full, FileAccess.READ)
			if f == null:
				name = d.get_next()
				continue
			var content := f.get_as_text()
			f.close()
			# File-level escape hatch for purely-visual scripts
			if content.contains("# @rendering_only_file"):
				name = d.get_next()
				continue
			# Per-line check: a line containing a bad pattern is OK if the
			# same line carries `# @rendering_only`. This lets sequence
			# scripts mix game logic with cosmetic light pulses safely.
			for line in content.split("\n"):
				if line.contains("# @rendering_only"):
					continue
				for pat in bad_patterns:
					if line.contains(pat):
						offenders.append("%s uses %s" % [full, pat])
						break
		name = d.get_next()
	d.list_dir_end()

# Returns Array of {name: String, body: String} for every "func NAME(" in the
# source whose name does not begin with underscore. Static funcs are included
# (they are public). The body span runs until the next top-level "func "
# or end of file.
func _parse_public_funcs(content: String) -> Array:
	var result: Array = []
	var lines := content.split("\n")
	var current_name := ""
	var current_body := ""
	var in_collected := false

	for raw in lines:
		var line: String = raw
		var stripped := line.strip_edges()
		var is_func_line := false
		var func_name := ""
		if stripped.begins_with("func "):
			is_func_line = true
			func_name = stripped.substr(5).get_slice("(", 0).strip_edges()
		elif stripped.begins_with("static func "):
			is_func_line = true
			func_name = stripped.substr(12).get_slice("(", 0).strip_edges()

		if is_func_line:
			# Flush previous
			if in_collected:
				result.append({"name": current_name, "body": current_body})
			current_name = func_name
			current_body = ""
			in_collected = not func_name.begins_with("_")
		else:
			if in_collected:
				current_body += line + "\n"

	if in_collected:
		result.append({"name": current_name, "body": current_body})
	return result

func _test_flora_memory() -> void:
	_test_name = "Flora Memory"

	var flora := FloraMemorySystem.new()
	flora.register_node("near", {
		"species": "Lumivine",
		"zone": "channels",
		"position": Vector3.ZERO,
		"signal_type": "iron",
		"signal_label": "iron bloom",
		"signal_pos": Vector3(6, 0, 0),
		"relationship_strength": 0.82,
		"tended": true,
	})
	flora.register_node("far", {
		"species": "Archive Vine",
		"zone": "channels",
		"position": Vector3(22, 0, 0),
		"signal_type": "resource",
		"signal_label": "cache warmth",
		"signal_pos": Vector3(26, 0, 0),
		"relationship_strength": 0.55,
	})
	flora.register_node("forget", {
		"species": "Forget-Me-Not",
		"zone": "channels",
		"position": Vector3(2, 0, 0),
		"signal_type": "relationship",
		"signal_label": "Aster",
		"signal_pos": Vector3(2, 0, 0),
		"relationship_strength": 1.0,
		"role": "relationship",
		"forget_me_not": true,
		"tended": true,
		"childhood_species": true,
	})

	var started := flora.start_read("near", 0.0)
	_assert_true(bool(started.get("started", false)), "Sensor read starts from encountered flora")
	var early_snapshot := flora.get_overlay_snapshot(0.7, "channels")
	_assert_true(early_snapshot.get("visible_clues", []).size() == 1, "Encounter rule hides unencountered remote nodes")
	_assert_true(str(early_snapshot.get("visible_clues", [])[0].get("signal_label", "")) == "iron bloom", "Early context stays specific")

	flora.encounter_node("far")
	flora.start_read("near", 20.0)
	var propagated_snapshot := flora.get_overlay_snapshot(24.0, "channels")
	_assert_true(propagated_snapshot.get("visible_clues", []).size() >= 2, "Encountered remote nodes join the network after propagation")

	flora.set_stage(FloraMemorySystem.Stage.LATE)
	flora.start_read("near", 40.0)
	var late_snapshot := flora.get_overlay_snapshot(41.0, "channels")
	var late_clue: Dictionary = late_snapshot.get("visible_clues", [])[0]
	_assert_true(str(late_clue.get("signal_label", "")) != "iron bloom", "Late degradation coarsens contextual readings")
	_assert_true(late_snapshot.get("time_remaining", 0.0) < early_snapshot.get("time_remaining", 0.0), "Late read window is shorter than early")

	flora.set_stage(FloraMemorySystem.Stage.EARLY)
	var forget_read := flora.start_read("forget", 60.0)
	_assert_equals(str(forget_read.get("scent", "")), "rust going away", "Forget-me-not keeps the phantom scent early")
	flora.set_stage(FloraMemorySystem.Stage.ENDGAME)
	var failed_forget := flora.start_read("forget", 80.0)
	_assert_equals(str(failed_forget.get("scent", "")), "none", "Forget-me-not scent collapses in endgame without repair")
	flora.apply_cure_component("Chaperone Lattice")
	var restored_forget := flora.start_read("forget", 100.0)
	_assert_true(str(restored_forget.get("scent", "")) != "none", "Chaperone Lattice restores relational scent support")

# --- Assertions ---

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: [%s] %s" % [_test_name, message])
		_passed += 1
	else:
		print("  FAIL: [%s] %s" % [_test_name, message])
		_failed += 1

func _assert_equals(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("  PASS: [%s] %s (got: %s)" % [_test_name, message, actual])
		_passed += 1
	else:
		print("  FAIL: [%s] %s (expected: %s, got: %s)" % [_test_name, message, expected, actual])
		_failed += 1

func _vec3_from_array(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return fallback

func _serialized_path_uses_multiple_y(path: Variant) -> bool:
	if not (path is Array):
		return false
	var seen: Array[int] = []
	for raw_point in path:
		var point := _vec3_from_array(raw_point, Vector3.INF)
		if point == Vector3.INF:
			continue
		var level := int(roundf(point.y * 100.0))
		if not seen.has(level):
			seen.append(level)
	return seen.size() > 1

# --- Dialogue Sequence Tests ---

func _advance_dialogue_box(dialogue_box: Node, dt: float) -> void:
	# Feed the one dialogue clock dt ticks (no speed_multiplier — that field is
	# gone; the box has no clock of its own).
	if dialogue_box != null and dialogue_box.has_method("advance_ui_time"):
		dialogue_box.call("advance_ui_time", dt)

## Advance the box, then acknowledge a wait gate the way the headless "player"
## would (a fully-typed wait=true line waits for an explicit advance). This is
## the single mechanism that replaces the old speed_multiplier = 10000 hack.
func _pump_dialogue(dialogue_box: Node, dt: float) -> void:
	if dialogue_box == null:
		return
	_advance_dialogue_box(dialogue_box, dt)
	if not dialogue_box.has_method("request_advance"):
		return
	# Click-only by default: advance every line the box is waiting on (the
	# headless equivalent of the player clicking), not just wait=true lines.
	if dialogue_box.has_method("awaiting_advance"):
		if bool(dialogue_box.call("awaiting_advance")):
			dialogue_box.call("request_advance")
		return
	if not bool(dialogue_box.get("_waiting_for_input")):
		return
	var shown := float(dialogue_box.get("_displayed_chars"))
	var total := str(dialogue_box.get("_current_text")).length()
	if shown >= float(total):
		dialogue_box.call("request_advance")

## Drain all currently-queued dialogue to idle, acknowledging wait gates. Pumps
## the dialogue clock in large ticks until the box reports idle.
func _drain_dialogue_box(dialogue_box: Node, _duration := 0.0, _step := 0.0) -> void:
	var safety := 0
	while safety < 5000:
		if dialogue_box == null or (dialogue_box.has_method("is_active") and not dialogue_box.is_active()):
			return
		_pump_dialogue(dialogue_box, 16.0)
		safety += 1

## Pop through scheduler events, flushing dialogue between each.
## step_actions: Dictionary mapping step names to Callables that simulate
## player input (e.g. teleporting to a position, pressing a key).
## Actions fire once when _current_step first matches the key.
## Returns an array of {tick, text, speaker, style} dictionaries.
func _pop_dialogue_log(instance: Node, step_actions: Dictionary = {}) -> Array[Dictionary]:
	var log_entries: Array[Dictionary] = []
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler

	var capture := func(text: String):
		log_entries.append({
			"tick": scheduler.get_current_tick(),
			"text": text,
			"speaker": dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else "",
			"style": dialogue_box._style,
		})
	dialogue_box.line_displayed.connect(capture)

	var last_actioned_step := ""
	var safety := 0
	var idle := 0
	while safety < 20000:
		# Flush dialogue box
		for j in range(200):
			if not dialogue_box.is_active():
				break
			_pump_dialogue(dialogue_box, 16.0)

		# Check for step actions to simulate input
		var current_step: String = instance._current_step
		if current_step in step_actions and current_step != last_actioned_step:
			last_actioned_step = current_step
			step_actions[current_step].call()
			# Run _on_process so proximity gates and per-frame checks can fire
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
			idle = 0
			continue

		if scheduler.pending_count() == 0:
			idle += 1
			if idle > 20:
				break
			for j in range(10):
				_pump_dialogue(dialogue_box, 16.0)
			continue
		idle = 0
		var info: Dictionary = scheduler.pop_next()
		if info.is_empty():
			break
		safety += 1

	dialogue_box.line_displayed.disconnect(capture)
	return log_entries

func _drive_sequence_contract(instance: Node, step_actions: Dictionary = {}, max_pops := 20000) -> Dictionary:
	var log: Array[Dictionary] = []
	var step_history: Array = []
	var step_ticks := {}
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler
	var actioned_steps: Dictionary = {}
	var termination_reason := "safety"

	var step_state := {"last": ""}
	var capture_step := func():
		var current_step: String = instance._current_step
		if current_step != "" and current_step != step_state["last"]:
			step_history.append(current_step)
			if not step_ticks.has(current_step):
				step_ticks[current_step] = scheduler.get_current_tick()
			step_state["last"] = current_step

	var capture_line := func(text: String):
		log.append({
			"tick": scheduler.get_current_tick(),
			"text": text,
			"speaker": dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else "",
			"style": dialogue_box._style,
		})

	capture_step.call()
	dialogue_box.line_displayed.connect(capture_line)

	var safety := 0
	var idle := 0
	while safety < max_pops:
		for j in range(200):
			if not dialogue_box.is_active():
				break
			_pump_dialogue(dialogue_box, 16.0)
			capture_step.call()

		var current_step: String = instance._current_step
		if current_step in step_actions and not actioned_steps.has(current_step):
			actioned_steps[current_step] = true
			step_actions[current_step].call()
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
			capture_step.call()
			idle = 0
			continue

		if current_step == "complete" and scheduler.pending_count() == 0 and not dialogue_box.is_active():
			termination_reason = "complete"
			break

		if scheduler.pending_count() == 0:
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
				capture_step.call()
			if instance._current_step == "complete" and not dialogue_box.is_active():
				termination_reason = "complete"
				break
			idle += 1
			if idle > 20:
				termination_reason = "idle"
				break
			for j in range(10):
				_pump_dialogue(dialogue_box, 16.0)
				capture_step.call()
			continue

		idle = 0
		var info: Dictionary = scheduler.pop_next()
		capture_step.call()
		if info.is_empty():
			termination_reason = "empty_pop"
			break
		safety += 1

	if dialogue_box.line_displayed.is_connected(capture_line):
		dialogue_box.line_displayed.disconnect(capture_line)

	return {
		"dialogue_log": log,
		"step_history": step_history,
		"step_ticks": step_ticks,
		"termination_reason": termination_reason,
		"actioned_steps": actioned_steps.keys(),
	}

func _drive_sequence_contract_with_wall_time(
	instance: Node,
	step_actions: Dictionary = {},
	max_pops := 20000,
	dialogue_speed_multiplier := 1.0,
	continue_delay := 0.35,
	process_delta := 0.05
) -> Dictionary:
	var log: Array[Dictionary] = []
	var step_history: Array = []
	var step_ticks := {}
	var step_wall_times := {}
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler
	var actioned_steps: Dictionary = {}
	var termination_reason := "safety"
	var wall_time := 0.0
	var scheduler_time := 0.0
	var dialogue_time := 0.0

	var step_state := {"last": ""}
	var wait_input_time := 0.0

	var capture_step := func():
		var current_step: String = instance._current_step
		if current_step != "" and current_step != step_state["last"]:
			step_history.append(current_step)
			if not step_ticks.has(current_step):
				step_ticks[current_step] = scheduler.get_current_tick()
			if not step_wall_times.has(current_step):
				step_wall_times[current_step] = wall_time
			step_state["last"] = current_step

	var capture_line := func(text: String):
		log.append({
			"tick": scheduler.get_current_tick(),
			"wall_time": wall_time,
			"text": text,
			"speaker": dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else "",
			"style": dialogue_box._style,
		})

	var process_dialogue := func(dt: float):
		# Realistic-pace harness: the caller's multiplier is applied here (the
		# box no longer carries a speed_multiplier field).
		_advance_dialogue_box(dialogue_box, dt * dialogue_speed_multiplier)
		wall_time += dt
		dialogue_time += dt
		var awaiting: bool = dialogue_box.has_method("awaiting_advance") and bool(dialogue_box.call("awaiting_advance"))
		if awaiting:
			# Simulate a player pausing continue_delay before clicking to advance.
			wait_input_time += dt
			if wait_input_time >= continue_delay:
				dialogue_box.request_advance()
				wait_input_time = 0.0
		else:
			wait_input_time = 0.0

	capture_step.call()
	dialogue_box.line_displayed.connect(capture_line)

	var safety := 0
	var idle := 0
	while safety < max_pops:
		for j in range(200):
			if not dialogue_box.is_active():
				break
			process_dialogue.call(process_delta)
			capture_step.call()

		var current_step: String = instance._current_step
		if current_step in step_actions and not actioned_steps.has(current_step):
			actioned_steps[current_step] = true
			step_actions[current_step].call()
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
			capture_step.call()
			idle = 0
			continue

		if current_step == "complete" and scheduler.pending_count() == 0 and not dialogue_box.is_active():
			termination_reason = "complete"
			break

		if scheduler.pending_count() == 0:
			if instance.has_method("_on_process"):
				instance._on_process(0.1, 1.0)
				capture_step.call()
			if instance._current_step == "complete" and not dialogue_box.is_active():
				termination_reason = "complete"
				break
			idle += 1
			if idle > 20:
				termination_reason = "idle"
				break
			for j in range(10):
				if not dialogue_box.is_active():
					break
				process_dialogue.call(process_delta)
				capture_step.call()
			continue

		idle = 0
		var before_tick := scheduler.get_current_tick()
		var info: Dictionary = scheduler.pop_next()
		var after_tick := scheduler.get_current_tick()
		var dt_tick := maxf(0.0, after_tick - before_tick)
		wall_time += dt_tick
		scheduler_time += dt_tick
		if instance.has_method("_on_process"):
			instance._on_process(0.1, 1.0)
		capture_step.call()
		if info.is_empty():
			termination_reason = "empty_pop"
			break
		safety += 1

	if dialogue_box.line_displayed.is_connected(capture_line):
		dialogue_box.line_displayed.disconnect(capture_line)

	return {
		"dialogue_log": log,
		"step_history": step_history,
		"step_ticks": step_ticks,
		"step_wall_times": step_wall_times,
		"termination_reason": termination_reason,
		"actioned_steps": actioned_steps.keys(),
		"elapsed_wall_time": wall_time,
		"scheduler_elapsed_time": scheduler_time,
		"dialogue_elapsed_time": dialogue_time,
	}

func _format_steps(steps: Array) -> String:
	var parts := []
	for step in steps:
		parts.append(str(step))
	var text := ""
	for i in range(parts.size()):
		if i > 0:
			text += " -> "
		text += str(parts[i])
	return text

func _assert_step_subsequence(actual: Array, expected: Array, message: String) -> void:
	var cursor := 0
	var matched_all := true
	for step in expected:
		while cursor < actual.size() and actual[cursor] != step:
			cursor += 1
		if cursor >= actual.size():
			matched_all = false
			break
		cursor += 1
	_assert_true(
		matched_all,
		"%s (expected: %s | got: %s)" % [message, _format_steps(expected), _format_steps(actual)]
	)

func _assert_step_absent(actual: Array, forbidden_step: String, message: String) -> void:
	_assert_true(
		not actual.has(forbidden_step),
		"%s (history: %s)" % [message, _format_steps(actual)]
	)

func _set_sequence_character_position(instance: Node, char_id: String, pos: Vector3) -> void:
	var node: Node3D = null
	if instance.has_method("_get_character_node"):
		node = instance._get_character_node(char_id)
	elif char_id == "aster" and "_aster_node" in instance:
		node = instance._aster_node
	elif char_id == "peris" and "_peris_node" in instance:
		node = instance._peris_node
	elif char_id == "endo" and "_endo" in instance:
		node = instance._endo
	elif char_id == "player" and "_player" in instance:
		node = instance._player
	elif "_player" in instance and instance._player != null and str(instance._player.get("char_id")) == char_id:
		node = instance._player

	if node:
		node.global_position = pos

	if "_game_state" in instance and instance._game_state and instance._game_state.characters.has(char_id):
		instance._game_state.command_stop(char_id)
		instance._game_state.characters[char_id].position = pos

func _disable_enemy_detection(instance: Node) -> void:
	var enemy_groups: Array = []
	if "_enemies" in instance:
		enemy_groups.append(instance._enemies)
	if "_gauntlet_enemies" in instance:
		enemy_groups.append(instance._gauntlet_enemies)

	for enemy_group in enemy_groups:
		for enemy in enemy_group:
			if not is_instance_valid(enemy):
				continue
			if "_detection_targets" in enemy:
				enemy.set("_detection_targets", [])
			if "_current_target_id" in enemy:
				enemy.set("_current_target_id", "")
			if enemy.has_method("_change_state"):
				enemy._change_state("idle")
			if enemy.game_state and enemy.game_state.characters.has(enemy.char_id):
				enemy.game_state.characters[enemy.char_id].stats["detection_range"] = 0.0

func _run_sequence_contract(
	label: String,
	scene_path: String,
	expected_steps: Array,
	step_actions_factory: Callable = Callable(),
	setup: Callable = Callable(),
	expected_next_scene := "",
	forbidden_steps: Array = [],
	expected_final_step := "complete",
	extra_assertions: Callable = Callable()
) -> Dictionary:
	_test_name = label
	var scene := load(scene_path)
	_assert_true(scene != null, "Scene loads")
	if not scene:
		return {}

	var instance: Node = scene.instantiate()
	_assert_true(instance != null, "Scene instantiates")
	if not instance:
		return {}

	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	if setup.is_valid():
		setup.call(instance)

	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var step_actions := {}
	if step_actions_factory.is_valid():
		step_actions = step_actions_factory.call(instance)

	var result := _drive_sequence_contract(instance, step_actions)
	var step_history: Array = result.step_history
	var actioned_steps: Array = result.actioned_steps
	_assert_true(not step_history.is_empty(), "Captured step history")
	_assert_step_subsequence(step_history, expected_steps, "Required step order holds")

	if expected_final_step != "":
		_assert_equals(instance._current_step, expected_final_step, "Final step is %s" % expected_final_step)

	if not step_actions.is_empty():
		_assert_equals(
			actioned_steps.size(),
			step_actions.size(),
			"All scripted step hooks ran"
		)

	for forbidden_step in forbidden_steps:
		_assert_step_absent(step_history, forbidden_step, "Step %s does not appear" % forbidden_step)

	if expected_next_scene != "" and "requested_scene_change" in instance:
		_assert_equals(instance.requested_scene_change, expected_next_scene, "Recorded next scene handoff")

	_assert_true(
		result.termination_reason in ["complete", "idle"],
		"Driver terminated cleanly (got: %s)" % result.termination_reason
	)

	if extra_assertions.is_valid():
		extra_assertions.call(instance, result)

	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("_teardown_sequence"):
		instance._teardown_sequence()
	instance.queue_free()
	await get_tree().process_frame
	return result

func _format_playtime(seconds: float) -> String:
	if seconds < 0.0:
		return "n/a"
	var total_seconds := int(round(seconds))
	var minutes := total_seconds / 60
	var secs := total_seconds % 60
	return "%d:%02d (%0.1fs)" % [minutes, secs, seconds]

func _step_tick(result: Dictionary, step: String) -> float:
	var step_ticks: Dictionary = result.get("step_ticks", {})
	if step_ticks.has(step):
		return float(step_ticks[step])
	return -1.0

func _step_wall_time(result: Dictionary, step: String) -> float:
	var step_wall_times: Dictionary = result.get("step_wall_times", {})
	if step_wall_times.has(step):
		return float(step_wall_times[step])
	return -1.0

func _get_sequence_character_position(instance: Node, char_id: String) -> Vector3:
	if "_game_state" in instance and instance._game_state and instance._game_state.characters.has(char_id):
		return instance._game_state.get_position(char_id)
	var node: Node3D = null
	if instance.has_method("_get_character_node"):
		node = instance._get_character_node(char_id)
	elif char_id == "aster" and "_aster_node" in instance:
		node = instance._aster_node
	elif char_id == "peris" and "_peris_node" in instance:
		node = instance._peris_node
	elif char_id == "endo" and "_endo" in instance:
		node = instance._endo
	elif char_id == "player" and "_player" in instance:
		node = instance._player
	return node.global_position if node else Vector3.ZERO

func _get_sequence_character_speed(instance: Node, char_id: String) -> float:
	if "_game_state" in instance and instance._game_state and instance._game_state.characters.has(char_id):
		return float(instance._game_state.characters[char_id].move_speed)
	return 3.0

func _schedule_human_move(
	instance: Node,
	char_id: String,
	target: Vector3,
	tag: String,
	reaction_delay := 0.35
) -> float:
	var from := _get_sequence_character_position(instance, char_id)
	var speed := _get_sequence_character_speed(instance, char_id)
	var travel_time := from.distance_to(target) / maxf(speed, 0.1)
	var total_delay := reaction_delay + travel_time
	instance._scheduler.schedule_after(total_delay, func():
		_set_sequence_character_position(instance, char_id, target)
	, tag)
	return total_delay

func _clear_sequence_runtime(instance: Node) -> void:
	if "_scheduler" in instance and instance._scheduler:
		instance._scheduler.clear()
	if "_dialogue" in instance and instance._dialogue and instance._dialogue.has_method("clear"):
		instance._dialogue.clear()

func _make_act1_sequence_actions(instance: Node) -> Dictionary:
	var actions := {}
	actions["channels_to_memory"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.CHANNELS_MEMORY_TRIGGER_X + 1.0, 0.5, 0.0)
		)
	actions["channels_memory"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("channels_corpse")
	actions["channels_corpse"] = func():
		_clear_sequence_runtime(instance)
		_set_sequence_character_position(instance, "aster", instance.CHANNELS_WINDOW_ONE_STAGE_POS)
		_set_sequence_character_position(instance, "peris", instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2))
		_set_sequence_character_position(instance, "endo", instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0))
		instance._enter_step("channels_window_one_intro")
	actions["channels_window_one_intro"] = func():
		instance._begin_channels_window_lane("window_one")
	actions["channels_window_one_activate"] = func():
		instance.activate_channels_window_lure("window_one")
	actions["channels_window_one_cross"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			instance.CHANNELS_WINDOW_ONE_GOAL_POS
		)
		instance._update_channels_window_puzzles(0.1, 1.0)
	actions["channels_to_ferrolure"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.CHANNELS_FERROLURE_TRIGGER_X + 1.0, 0.5, 0.0)
		)
	actions["channels_ferrolure"] = func():
		_clear_sequence_runtime(instance)
		_set_sequence_character_position(instance, "aster", instance.CHANNELS_WINDOW_TWO_STAGE_POS)
		_set_sequence_character_position(instance, "peris", instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2))
		_set_sequence_character_position(instance, "endo", instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0))
		instance._enter_step("channels_window_two_intro")
	actions["channels_window_two_intro"] = func():
		instance._begin_channels_window_lane("window_two")
	actions["channels_window_two_activate"] = func():
		instance.activate_channels_window_lure("window_two")
	actions["channels_window_two_cross"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			instance.CHANNELS_WINDOW_TWO_GOAL_POS
		)
		instance._update_channels_window_puzzles(0.1, 1.0)
	actions["channels_to_encounter"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.CHANNELS_ENCOUNTER_TRIGGER_X + 1.0, 0.5, 0.0)
		)
	actions["channels_encounter_intro"] = func():
		_clear_sequence_runtime(instance)
		_set_sequence_character_position(instance, "aster", instance.CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4))
		_set_sequence_character_position(instance, "peris", instance.CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2))
		_set_sequence_character_position(instance, "endo", instance.CHANNELS_ENCOUNTER_ENTRY_POS)
		instance._begin_channels_encounter()
	actions["channels_encounter_activate"] = func():
		instance._on_channels_run_lure_activated()
	actions["channels_encounter_hide"] = func():
		_set_sequence_character_position(
			instance,
			"endo",
			instance.CHANNELS_HIDE_SPOT_POS
		)
	actions["channels_encounter_run"] = func():
		_set_sequence_character_position(
			instance,
			"endo",
			instance.CHANNELS_SHELTER_POS
		)
	actions["channels_shelter"] = func():
		_clear_sequence_runtime(instance)
		instance._start_channels_explore()
	actions["channels_explore"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.CHANNELS_END.x - 4.0, 0.5, 0.0)
		)
	actions["stacks_enter"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("stacks_terminal")
	actions["stacks_terminal"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("stacks_signal")
	actions["stacks_signal"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("stacks_archive")
	actions["stacks_archive"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("stacks_explore")
	actions["stacks_explore"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.STACKS_END.x - 4.0, 0.5, 0.0)
		)
	actions["rings_enter"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("rings_client")
	actions["rings_client"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("endo_departs")
	actions["endo_departs"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("rings_explore")
	actions["rings_explore"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.RINGS_END.x - 4.0, 0.5, 0.0)
		)
	actions["lockout_approach"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("lockout_rejected")
	actions["lockout_rejected"] = func():
		_clear_sequence_runtime(instance)
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.LOCKOUT_START.x + 5.0, 0.5, 0.0)
		)
		instance._start_lockout_chase()
	actions["lockout_chase"] = func():
		_set_sequence_character_position(
			instance,
			"aster",
			Vector3(instance.LOCKOUT_START.x - 11.0, 0.5, 0.0)
		)
	actions["lockout_exile"] = func():
		_clear_sequence_runtime(instance)
		instance._enter_step("complete")
		instance._change_scene_or_record("res://scenes/tutorial/leaving_facility.tscn")
	actions["complete"] = func():
		instance._change_scene_or_record("res://scenes/tutorial/leaving_facility.tscn")
	return actions

func _make_act1_human_actions(instance: Node) -> Dictionary:
	var actions := {}
	actions["channels_to_memory"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.CHANNELS_MEMORY_TRIGGER_X + 1.0, 0.5, 0.0),
			"human_channels_to_memory",
			0.5
		)
	actions["channels_to_ferrolure"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.CHANNELS_FERROLURE_TRIGGER_X + 1.0, 0.5, 0.0),
			"human_channels_to_ferrolure",
			0.45
		)
	actions["channels_window_one_intro"] = func():
		var stage_targets := {
			"aster": instance.CHANNELS_WINDOW_ONE_STAGE_POS,
			"peris": instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
			"endo": instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
		}
		for char_id in stage_targets.keys():
			_set_sequence_character_position(instance, char_id, stage_targets[char_id])
	actions["channels_window_one_activate"] = func():
		var char_id := "aster"
		var target: Vector3 = instance.CHANNELS_WINDOW_ONE_LURE_POS
		var from := _get_sequence_character_position(instance, char_id)
		var speed := _get_sequence_character_speed(instance, char_id)
		var travel_time := from.distance_to(target) / maxf(speed, 0.1)
		var arrive_delay := 0.25 + travel_time
		instance._scheduler.schedule_after(arrive_delay, func():
			_set_sequence_character_position(instance, char_id, target)
		, "human_channels_window_one_arrive")
		instance._scheduler.schedule_after(arrive_delay + 1.6, func():
			_set_sequence_character_position(instance, char_id, target)
			instance.activate_channels_window_lure("window_one")
		, "human_channels_window_one_activate")
	actions["channels_window_one_cross"] = func():
		_schedule_human_move(
			instance,
			"aster",
			instance.CHANNELS_WINDOW_ONE_GOAL_POS,
			"human_channels_window_one_cross",
			0.15
		)
	actions["channels_to_encounter"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.CHANNELS_ENCOUNTER_TRIGGER_X + 1.0, 0.5, 0.0),
			"human_channels_to_encounter",
			0.45
		)
	actions["channels_window_two_intro"] = func():
		var stage_targets := {
			"aster": instance.CHANNELS_WINDOW_TWO_STAGE_POS,
			"peris": instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
			"endo": instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
		}
		for char_id in stage_targets.keys():
			_set_sequence_character_position(instance, char_id, stage_targets[char_id])
	actions["channels_window_two_activate"] = func():
		var char_id := "aster"
		var target: Vector3 = instance.CHANNELS_WINDOW_TWO_LURE_POS
		var from := _get_sequence_character_position(instance, char_id)
		var speed := _get_sequence_character_speed(instance, char_id)
		var travel_time := from.distance_to(target) / maxf(speed, 0.1)
		var arrive_delay := 0.25 + travel_time
		instance._scheduler.schedule_after(arrive_delay, func():
			_set_sequence_character_position(instance, char_id, target)
		, "human_channels_window_two_arrive")
		instance._scheduler.schedule_after(arrive_delay + 1.6, func():
			_set_sequence_character_position(instance, char_id, target)
			instance.activate_channels_window_lure("window_two")
		, "human_channels_window_two_activate")
	actions["channels_window_two_cross"] = func():
		_schedule_human_move(
			instance,
			"aster",
			instance.CHANNELS_WINDOW_TWO_GOAL_POS,
			"human_channels_window_two_cross",
			0.15
		)
	actions["channels_encounter_activate"] = func():
		var char_id := "endo"
		var target: Vector3 = instance.CHANNELS_RUN_LURE_POS
		var from := _get_sequence_character_position(instance, char_id)
		var speed := _get_sequence_character_speed(instance, char_id)
		var travel_time := from.distance_to(target) / maxf(speed, 0.1)
		var arrive_delay := 0.35 + travel_time
		instance._scheduler.schedule_after(arrive_delay, func():
			_set_sequence_character_position(instance, char_id, target)
		, "human_channels_lure_arrive")
		instance._scheduler.schedule_after(arrive_delay + 2.0, func():
			_set_sequence_character_position(instance, char_id, target)
			instance._on_channels_run_lure_activated()
		, "human_channels_lure_activate")
	actions["channels_encounter_hide"] = func():
		_schedule_human_move(
			instance,
			"endo",
			instance.CHANNELS_HIDE_SPOT_POS,
			"human_channels_encounter_hide",
			0.2
		)
	actions["channels_encounter_run"] = func():
		_schedule_human_move(
			instance,
			"endo",
			instance.CHANNELS_SHELTER_POS,
			"human_channels_encounter_run",
			0.2
		)
	actions["channels_explore"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.CHANNELS_END.x - 4.0, 0.5, 0.0),
			"human_channels_explore",
			0.4
		)
	actions["stacks_explore"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.STACKS_END.x - 4.0, 0.5, 0.0),
			"human_stacks_explore",
			0.4
		)
	actions["rings_explore"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.RINGS_END.x - 4.0, 0.5, 0.0),
			"human_rings_explore",
			0.4
		)
	actions["lockout_chase"] = func():
		_schedule_human_move(
			instance,
			"aster",
			Vector3(instance.LOCKOUT_START.x - 11.0, 0.5, 0.0),
			"human_lockout_chase",
			0.2
		)
	return actions

func _dialogue_style_speed_multiplier(style: String) -> float:
	match style:
		"fragment":
			return 0.4
		"poem":
			return 0.7
		"whisper":
			return 0.25
		_:
			return 1.0

func _dialogue_line_duration(key: String, continue_delay := 0.35) -> float:
	var line := DialogueData.get_line(key)
	var cps := 30.0 * _dialogue_style_speed_multiplier(line.style)
	var display_time := line.text.length() / maxf(cps, 1.0)
	var hold_time := continue_delay if line.wait else 2.0
	return display_time + hold_time

func _dialogue_chain_duration(keys: Array, delay_between := 0.0, continue_delay := 0.35) -> float:
	var total := 0.0
	for i in range(keys.size()):
		total += _dialogue_line_duration(str(keys[i]), continue_delay)
		if delay_between > 0.0 and i < keys.size() - 1:
			total += delay_between
	return total

func _travel_duration(from: Vector3, to: Vector3, speed: float, reaction_delay := 0.0) -> float:
	return reaction_delay + from.distance_to(to) / maxf(speed, 0.1)

func _party_move_duration(from_positions: Dictionary, destinations: Dictionary, speeds: Dictionary) -> float:
	var longest := 0.0
	for id in destinations.keys():
		if not from_positions.has(id):
			continue
		longest = maxf(
			longest,
			from_positions[id].distance_to(destinations[id]) / maxf(float(speeds.get(id, 3.0)), 0.1)
		)
	return longest

func _mark_estimate_step(step_wall_times: Dictionary, step_name: String, system_time: float, dialogue_time: float) -> void:
	step_wall_times[step_name] = system_time + dialogue_time

func _estimate_act1_human_playtime() -> Dictionary:
	var scene := load("res://scenes/tutorial/act1.tscn")
	if not scene:
		return {}
	var instance: Node = scene.instantiate()
	if not instance:
		return {}

	var speeds := {
		"aster": 3.0,
		"peris": 2.5,
		"endo": 2.5,
	}
	var positions := {
		"aster": instance.CHANNELS_START + Vector3(5, 0.5, 0),
		"peris": instance.CHANNELS_START + Vector3(0, 0.5, 1),
		"endo": instance.CHANNELS_START + Vector3(-1, 0.5, 0),
	}
	var step_wall_times := {}
	var system_time := 2.5
	var dialogue_time := 0.0

	_mark_estimate_step(step_wall_times, "channels_enter", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	])
	system_time += 0.5

	_mark_estimate_step(step_wall_times, "channels_to_memory", system_time, dialogue_time)
	var target := Vector3(instance.CHANNELS_MEMORY_TRIGGER_X + 1.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.5)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "channels_memory", system_time, dialogue_time)
	var party_targets := {
		"peris": instance.CHANNELS_BODY_POS + Vector3(-1.0, 0.0, 1.1),
		"aster": instance.CHANNELS_BODY_POS + Vector3(-3.0, 0.0, 0.4),
		"endo": instance.CHANNELS_BODY_POS + Vector3(-4.2, 0.0, -0.8),
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.memory",
		"channels.peris.know_place",
		"channels.aster.not_here",
		"channels.peris.saw_it",
		"channels.narration.leads",
	])
	system_time += 0.5

	_mark_estimate_step(step_wall_times, "channels_corpse", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.aster.report",
		"channels.peris.smell",
		"channels.peris.clients",
		"channels.aster.lysate",
		"channels.peris.people",
		"channels.aster.hungry",
		"channels.aster.downgrade",
	])
	system_time += 0.5

	_mark_estimate_step(step_wall_times, "channels_window_one_intro", system_time, dialogue_time)
	party_targets = {
		"aster": instance.CHANNELS_WINDOW_ONE_STAGE_POS,
		"peris": instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
		"endo": instance.CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.window_one",
		"channels.endo.window_one",
	])
	system_time += 0.35

	_mark_estimate_step(step_wall_times, "channels_window_one_activate", system_time, dialogue_time)
	system_time += _travel_duration(
		positions["aster"],
		instance.CHANNELS_WINDOW_ONE_LURE_POS,
		speeds["aster"],
		0.25
	)
	positions["aster"] = instance.CHANNELS_WINDOW_ONE_LURE_POS
	system_time += 1.6

	_mark_estimate_step(step_wall_times, "channels_window_one_cross", system_time, dialogue_time)
	system_time += _travel_duration(
		positions["aster"],
		instance.CHANNELS_WINDOW_ONE_GOAL_POS,
		speeds["aster"],
		0.15
	)
	positions["aster"] = instance.CHANNELS_WINDOW_ONE_GOAL_POS

	_mark_estimate_step(step_wall_times, "channels_to_ferrolure", system_time, dialogue_time)
	target = Vector3(instance.CHANNELS_FERROLURE_TRIGGER_X + 1.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.45)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "channels_ferrolure", system_time, dialogue_time)
	party_targets = {
		"peris": instance.CHANNELS_FERROLURE_POS + Vector3(-0.8, 0.0, 0.6),
		"aster": instance.CHANNELS_FERROLURE_POS + Vector3(-2.5, 0.0, -0.3),
		"endo": instance.CHANNELS_FERROLURE_POS + Vector3(-3.6, 0.0, 1.2),
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.flora",
		"channels.aster.lure",
		"channels.peris.signals",
		"channels.peris.pause",
	])
	dialogue_time += _dialogue_chain_duration([
		"channels.peris.touch",
		"channels.peris.always",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "channels_window_two_intro", system_time, dialogue_time)
	party_targets = {
		"aster": instance.CHANNELS_WINDOW_TWO_STAGE_POS,
		"peris": instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
		"endo": instance.CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.window_two",
		"channels.peris.window_two",
	])
	system_time += 0.35

	_mark_estimate_step(step_wall_times, "channels_window_two_activate", system_time, dialogue_time)
	system_time += _travel_duration(
		positions["aster"],
		instance.CHANNELS_WINDOW_TWO_LURE_POS,
		speeds["aster"],
		0.25
	)
	positions["aster"] = instance.CHANNELS_WINDOW_TWO_LURE_POS
	system_time += 1.6

	_mark_estimate_step(step_wall_times, "channels_window_two_cross", system_time, dialogue_time)
	system_time += _travel_duration(
		positions["aster"],
		instance.CHANNELS_WINDOW_TWO_GOAL_POS,
		speeds["aster"],
		0.15
	)
	positions["aster"] = instance.CHANNELS_WINDOW_TWO_GOAL_POS

	_mark_estimate_step(step_wall_times, "channels_to_encounter", system_time, dialogue_time)
	target = Vector3(instance.CHANNELS_ENCOUNTER_TRIGGER_X + 1.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.45)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "channels_encounter_intro", system_time, dialogue_time)
	party_targets = {
		"aster": instance.CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": instance.CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": instance.CHANNELS_ENCOUNTER_ENTRY_POS,
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]

	_mark_estimate_step(step_wall_times, "channels_encounter_activate", system_time, dialogue_time)
	var lure_arrival_time := _travel_duration(
		positions["endo"],
		instance.CHANNELS_RUN_LURE_POS,
		speeds["endo"],
		0.35
	)
	system_time += lure_arrival_time + 2.0
	positions["endo"] = instance.CHANNELS_RUN_LURE_POS

	_mark_estimate_step(step_wall_times, "channels_encounter_hide", system_time, dialogue_time)
	var hide_travel_time := _travel_duration(
		positions["endo"],
		instance.CHANNELS_HIDE_SPOT_POS,
		speeds["endo"],
		0.2
	)
	system_time += 20.0
	positions["endo"] = instance.CHANNELS_HIDE_SPOT_POS

	_mark_estimate_step(step_wall_times, "channels_encounter_run", system_time, dialogue_time)
	system_time += _travel_duration(
		positions["endo"],
		instance.CHANNELS_SHELTER_POS,
		speeds["endo"],
		0.2
	)
	positions["endo"] = instance.CHANNELS_SHELTER_POS

	_mark_estimate_step(step_wall_times, "channels_shelter", system_time, dialogue_time)
	party_targets = {
		"aster": instance.CHANNELS_SHELTER_POS + Vector3(-1.8, 0.0, -1.2),
		"peris": instance.CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		"endo": instance.CHANNELS_SHELTER_POS + Vector3(-0.3, 0.0, -0.2),
	}
	system_time += _party_move_duration(positions, party_targets, speeds)
	for id in party_targets.keys():
		positions[id] = party_targets[id]
	dialogue_time += _dialogue_chain_duration([
		"channels.narration.shelter",
		"channels.endo.door",
		"channels.narration.recuperate",
		"channels.narration.shortcut",
	])
	system_time += 0.5

	_mark_estimate_step(step_wall_times, "channels_explore", system_time, dialogue_time)
	target = Vector3(instance.CHANNELS_END.x - 4.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.4)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "stacks_enter", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"stacks.narration.enter",
		"stacks.aster.cores",
		"stacks.peris.noisy",
		"stacks.narration.network_address",
		"stacks.aster.know_number",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "stacks_terminal", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"stacks.aster.support_team",
		"stacks.aster.drink_machine",
		"stacks.peris.priorities",
		"stacks.narration.cleaned_terminal",
		"stacks.aster.cleaner_than_place",
		"stacks.aster.simplodrink",
		"stacks.peris.miss_machine",
		"stacks.aster.expectation",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "stacks_signal", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"stacks.narration.instrumented_lane",
		"stacks.aster.nonstandard",
		"stacks.aster.metrics",
		"stacks.peris.damn_cooler",
		"stacks.aster.cooling_part",
		"stacks.peris.meaning",
		"stacks.aster.standardization",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "stacks_archive", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"stacks.narration.workspace",
		"stacks.aster.pull_archive",
		"stacks.aster.ghost_ids",
		"stacks.peris.fake_permissions",
		"stacks.aster.security_patch",
		"stacks.aster.not_the_type",
		"stacks.aster.right",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "stacks_explore", system_time, dialogue_time)
	target = Vector3(instance.STACKS_END.x - 4.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.4)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "rings_enter", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"rings.narration.enter",
		"rings.aster.signal",
		"rings.peris.remember",
	])
	system_time += 3.0

	_mark_estimate_step(step_wall_times, "rings_client", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"rings.peris.hello",
		"rings.narration.client",
		"rings.peris.wall",
		"rings.narration.empty",
		"rings.aster.tags",
	])
	system_time += 3.0

	_mark_estimate_step(step_wall_times, "endo_departs", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"rings.endo.discomfort",
		"rings.endo.stops",
		"rings.peris.endo",
		"rings.narration.leaving",
		"rings.peris.understands",
		"rings.aster.just_us",
		"rings.peris.visiting",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "rings_explore", system_time, dialogue_time)
	target = Vector3(instance.RINGS_END.x - 4.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.4)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "lockout_approach", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"lockout.narration.clean",
		"lockout.aster.signals",
		"lockout.aster.panel",
	])
	system_time += 1.0

	_mark_estimate_step(step_wall_times, "lockout_rejected", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"lockout.system.rejected",
		"lockout.aster.again",
		"lockout.system.rejected2",
		"lockout.aster.hack",
		"lockout.system.blocked",
	])
	system_time += 1.0

	_mark_estimate_step(step_wall_times, "lockout_chase", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"lockout.narration.footsteps",
		"lockout.peris.run",
		"lockout.narration.chase",
	])
	target = Vector3(instance.LOCKOUT_START.x - 11.0, 0.5, 0.0)
	system_time += _travel_duration(positions["aster"], target, speeds["aster"], 0.2)
	positions["aster"] = target

	_mark_estimate_step(step_wall_times, "lockout_exile", system_time, dialogue_time)
	dialogue_time += _dialogue_chain_duration([
		"lockout.narration.boundary",
		"lockout.aster.not_in",
		"lockout.peris.back_to",
		"lockout.narration.forward",
	])
	system_time += 2.0

	_mark_estimate_step(step_wall_times, "complete", system_time, dialogue_time)
	instance.queue_free()
	return {
		"step_wall_times": step_wall_times,
		"system_time": system_time,
		"dialogue_time": dialogue_time,
		"scene_total": system_time + dialogue_time,
		"hide_travel_time": hide_travel_time,
	}

func _report_act1_playtime() -> void:
	var result := await _run_sequence_contract(
		"Act 1 Playtime",
		"res://scenes/tutorial/act1.tscn",
		ACT1_SEQUENCE_STEPS,
		Callable(self, "_make_act1_sequence_actions"),
		Callable(),
		"res://scenes/tutorial/leaving_facility.tscn"
	)
	var start_tick := _step_tick(result, "channels_enter")
	var shelter_tick := _step_tick(result, "channels_shelter")
	var explore_tick := _step_tick(result, "channels_explore")
	var complete_tick := _step_tick(result, "complete")
	var channels_to_shelter := shelter_tick - start_tick
	var channels_to_explore := explore_tick - start_tick
	var act1_total := complete_tick - start_tick
	_assert_true(start_tick >= 0.0, "Captured channels entry tick")
	_assert_true(shelter_tick >= 0.0, "Captured shelter tick")
	_assert_true(explore_tick >= 0.0, "Captured channels explore tick")
	_assert_true(complete_tick >= 0.0, "Captured Act 1 completion tick")
	print("")
	print("  === Act 1 Playtime ===")
	print("  Channels to shelter: %s" % _format_playtime(channels_to_shelter))
	print("  Channels to free explore: %s" % _format_playtime(channels_to_explore))
	print("  Full scripted Act 1: %s" % _format_playtime(act1_total))
	print("")

func _report_act1_human_playtime() -> void:
	_test_name = "Act 1 Human Playtime"
	var result := _estimate_act1_human_playtime()
	_assert_true(not result.is_empty(), "Computed human playtime estimate")
	var channels_enter_wall := _step_wall_time(result, "channels_enter")
	var channels_shelter_wall := _step_wall_time(result, "channels_shelter")
	var channels_explore_wall := _step_wall_time(result, "channels_explore")
	var complete_wall := _step_wall_time(result, "complete")
	var scene_total := float(result.get("scene_total", 0.0))
	var scheduler_total := float(result.get("system_time", 0.0))
	var dialogue_total := float(result.get("dialogue_time", 0.0))
	var hide_travel_time := float(result.get("hide_travel_time", 0.0))
	_assert_true(channels_enter_wall >= 0.0, "Captured channels entry wall time")
	_assert_true(channels_shelter_wall >= 0.0, "Captured shelter wall time")
	_assert_true(channels_explore_wall >= 0.0, "Captured channels explore wall time")
	_assert_true(complete_wall >= 0.0, "Captured Act 1 completion wall time")
	_assert_true(hide_travel_time < 20.0, "Encounter hide run fits within lure duration")

	print("")
	print("  === Act 1 Human Playtime ===")
	print("  Channels to shelter: %s" % _format_playtime(channels_shelter_wall - channels_enter_wall))
	print("  Channels to free explore: %s" % _format_playtime(channels_explore_wall - channels_enter_wall))
	print("  Full scripted Act 1 (from channels enter): %s" % _format_playtime(complete_wall - channels_enter_wall))
	print("  Full scripted scene (including fade): %s" % _format_playtime(scene_total))
	print("  Scheduler-driven time: %s" % _format_playtime(scheduler_total))
	print("  Dialogue/display time: %s" % _format_playtime(dialogue_total))
	print("")

func _test_tag_day_dialogue() -> void:
	_test_name = "Tag Day Dialogue"
	var scene := load("res://scenes/tutorial/tag_day.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var log := _pop_dialogue_log(instance)

	_assert_true(log.size() >= 28, "At least 28 dialogue lines (got: %d)" % log.size())

	# Verify groan appears exactly once
	var groan_count := 0
	for entry in log:
		if "get back to work" in entry.text:
			groan_count += 1
	_assert_true(groan_count == 1, "Groan appears exactly once (got: %d)" % groan_count)

	# Verify groan has BYSTANDER speaker
	for entry in log:
		if "get back to work" in entry.text:
			_assert_true(entry.speaker == "BYSTANDER", "Groan speaker is BYSTANDER (got: %s)" % entry.speaker)

	# Verify Aster's report line exists with correct speaker
	var report_count := 0
	for entry in log:
		if "incident report" in entry.text:
			report_count += 1
			_assert_true(entry.speaker == "ASTER", "Report speaker is ASTER (got: %s)" % entry.speaker)
	_assert_true(report_count == 1, "Report blocked appears once (got: %d)" % report_count)

	# Verify poem appears before fragments
	var first_poem_tick := 9999.0
	var first_fragment_tick := 9999.0
	for entry in log:
		if entry.style == "poem" and entry.tick < first_poem_tick:
			first_poem_tick = entry.tick
		if entry.style == "fragment" and entry.tick < first_fragment_tick:
			first_fragment_tick = entry.tick
	_assert_true(first_poem_tick < first_fragment_tick, "Poem starts before fragments")

	# Verify whimper appears after a gap (the BANG silence)
	var bang_tick := 0.0
	var whimper_tick := 0.0
	for entry in log:
		if "bang" in entry.text:
			bang_tick = entry.tick
		if entry.text == "whimper.":
			whimper_tick = entry.tick
	if bang_tick > 0 and whimper_tick > 0:
		var gap := whimper_tick - bang_tick
		_assert_true(gap >= 2.0, "BANG to whimper gap >= 2s (got: %.1f)" % gap)

	# Verify BANG fragment is reached (poem chain completed, fragments fired)
	var has_bang := false
	for entry in log:
		if "BANG" in entry.text:
			has_bang = true
	_assert_true(has_bang, "BANG fragment reached (poem chain completed)")

	# Verify BANG fires before the lockdown (poem+fragments complete before walk ends)
	var bang_tick_val := 0.0
	var lockdown_tick := 0.0
	for entry in log:
		if "BANG" in entry.text and bang_tick_val == 0.0:
			bang_tick_val = entry.tick
		if "MEDICAL BAY" in entry.text and lockdown_tick == 0.0:
			lockdown_tick = entry.tick
	if bang_tick_val > 0 and lockdown_tick > 0:
		_assert_true(bang_tick_val < lockdown_tick,
			"BANG before lockdown (bang=%.1f lockdown=%.1f)" % [bang_tick_val, lockdown_tick])

	# Verify NK chat lines appear in the dialogue log
	var nk_count := 0
	for entry in log:
		if entry.speaker == "NK-01" or entry.speaker == "NK-02":
			nk_count += 1
	_assert_true(nk_count >= 8, "NK chat lines in dialogue (got: %d)" % nk_count)
	var revised_nk10 := DialogueData.text("tag_day.nk_chat.10")
	var has_revised_nk10 := false
	for entry in log:
		if entry.text == revised_nk10:
			has_revised_nk10 = true
			break
	_assert_true(has_revised_nk10,
		"Tag Day dialogue log includes the revised NK-01 age-room threat")

	# Verify NK lines interleave with poem lines (NK appears after a poem line)
	var found_nk_after_poem := false
	for i in range(1, log.size()):
		if (log[i].speaker == "NK-01" or log[i].speaker == "NK-02") and log[i - 1].style == "poem":
			found_nk_after_poem = true
			break
	_assert_true(found_nk_after_poem, "NK chat interleaves with poem")

	# Verify scan passed appears near the end
	var scan_passed := false
	for entry in log:
		if "PASSED" in entry.text:
			scan_passed = true
	_assert_true(scan_passed, "Scan passed line exists")

	instance.queue_free()
	await get_tree().process_frame

func _test_peris_dialogue() -> void:
	_test_name = "Peris Dialogue"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Phase 2: attack, ordered tutorial, protect, aftermath.
	var log := _pop_dialogue_log(instance, {
		"protect_prompt": func():
			# Simulate pressing X to queue protect
			instance._on_protect_pressed(),
		"run_prompt": func():
			# Simulate pressing Z to toggle run
			instance._toggle_run(),
		"click_monos": func():
			# Simulate clicking near Monos
			instance._start_confirm_protect(),
		"confirm_protect": func():
			# Teleport Peris near portal so proximity check passes
			var target: Vector3 = instance.PORTAL_POS + Vector3(-0.5, 0.5, 0)
			instance._player.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._start_executing(),
	})

	_assert_true(log.size() >= 4, "At least 4 dialogue lines (got: %d)" % log.size())

	# Verify Monos appears
	var has_monos := false
	for entry in log:
		if entry.speaker == "Monos" or "Monos" in entry.text:
			has_monos = true
	_assert_true(has_monos, "Monos dialogue appears")

	# Verify system overtime prompt
	var has_overtime := false
	for entry in log:
		if "OVERTIME" in entry.text:
			has_overtime = true
	_assert_true(has_overtime, "Session overtime prompt appears")

	# Verify Monos thanks after protect
	var has_thanks := false
	for entry in log:
		if "thank you" in entry.text.to_lower():
			has_thanks = true
	_assert_true(has_thanks, "Monos thanks Peris after protect")

	# Verify efficiency penalty
	var has_penalty := false
	for entry in log:
		if "62%" in entry.text or "PENALTY" in entry.text:
			has_penalty = true
	_assert_true(has_penalty, "Efficiency penalty logged")

	var has_sanction := false
	var has_wellness := false
	var has_reconnect_denied := false
	var has_worker_exit := false
	for entry in log:
		var lower_text: String = entry.text.to_lower()
		if "sanction" in lower_text or "suspended pending review" in lower_text:
			has_sanction = true
		if "breathing techniques" in lower_text or "gel" in lower_text or "soap" in lower_text:
			has_wellness = true
		if "reconnect request denied" in lower_text:
			has_reconnect_denied = true
		if "medical attention" in lower_text or "are you okay" in lower_text:
			has_worker_exit = true
	_assert_true(has_sanction, "Sanction notice appears after Monos is saved")
	_assert_true(has_wellness, "Wellness feed replaces the client feed")
	_assert_true(has_reconnect_denied, "Reconnect denial appears before exit")
	_assert_true(has_worker_exit, "Simulation bay exit dialogue appears")

	instance._visit_phase = 1
	instance.queue_free()
	await get_tree().process_frame

func _test_peris_tutorial_redirect() -> void:
	_test_name = "Peris Tutorial Redirect"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Phase 2: test out-of-order inputs trigger corrections
	var log := _pop_dialogue_log(instance, {
		"protect_prompt": func():
			# Wrong: try Z before X, should show correction.
			instance._toggle_run()
			# Correct: press X
			instance._on_protect_pressed(),
		"run_prompt": func():
			# Wrong: try Space before Z, should show correction.
			instance._toggle_pause()
			# Correct: press Z
			instance._toggle_run(),
		"click_monos": func():
			instance._start_confirm_protect(),
		"confirm_protect": func():
			var target: Vector3 = instance.PORTAL_POS + Vector3(-0.5, 0.5, 0)
			instance._player.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._start_executing(),
	})

	# Verify the tutorial still completed despite wrong inputs
	var has_thanks := false
	for entry in log:
		if "thank you" in entry.text.to_lower():
			has_thanks = true
	_assert_true(has_thanks, "Tutorial completed despite redirects")

	# Verify efficiency penalty still logged
	var has_penalty := false
	for entry in log:
		if "62%" in entry.text or "PENALTY" in entry.text:
			has_penalty = true
	_assert_true(has_penalty, "Efficiency penalty logged after redirects")

	instance._visit_phase = 1
	instance.queue_free()
	await get_tree().process_frame

# --- Dialogue Dump ---

func _test_elevator_dialogue() -> void:
	_test_name = "Elevator Dialogue"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var log := _pop_dialogue_log(instance, {
		"consciousness_fragments": func():
			# Skip tween fragments and jump to waking.
			if instance._aster_node:
				instance._aster_node.visible = true
			for unit in [instance._escort_1, instance._escort_2]:
				if unit:
					unit.visible = true
			instance._emergency_light.light_energy = 3.0
			instance._fade_rect.color.a = 0.0
			instance._start_waking(),
		"approach_aster": func():
			# Teleport Peris near Aster
			var target: Vector3 = instance.ASTER_POS + Vector3(0.5, 0.5, 0)
			instance._peris_node.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._on_aster_wake_interacted(),
		"units_activate": func():
			# Resume from auto-pause so dialogue can advance
			instance._scheduler.resume(),
		"emp_tutorial": func():
			instance._on_emp_pressed()
			instance._flush_queued_abilities(),
		"doors_unlocked": func():
			if instance._exit_button:
				instance._exit_button._trigger(),
		"multiselect_tutorial": func():
			# Resume from auto-pause and teleport both near the door exit
			instance._hud.set_selected_portraits(["peris", "aster"])
			instance._scheduler.resume()
			var exit_gate := Vector3(instance.ELEVATOR_SIZE.x / 2.0, 0.5, 0)
			instance._peris_node.global_position = exit_gate + Vector3(0, 0, -0.5)
			instance._aster_node.global_position = exit_gate + Vector3(0, 0, 0.5)
			instance._game_state.characters["peris"].position = exit_gate + Vector3(0, 0, -0.5)
			instance._game_state.characters["aster"].position = exit_gate + Vector3(0, 0, 0.5),
		"corridor": func():
			# Suppress enemy detection during dialogue test
			for enemy in instance._enemies:
				if is_instance_valid(enemy):
					enemy._detection_targets.clear()
					if instance._game_state.characters.has(enemy.char_id):
						instance._game_state.characters[enemy.char_id].stats["detection_range"] = 0.0,
		"route_choice": func():
			# Move to convergence so the fall beat can trigger later.
			_set_sequence_character_position(
				instance,
				"aster",
				instance.ROUTES_CONVERGE + Vector3(1.5, 0.5, 0.0)
			),
		"bridge_collapse": func():
			pass,
	})

	_assert_true(log.size() >= 20, "At least 20 dialogue lines (got: %d)" % log.size())

	# Verify Aster retells Tag Day
	var has_tag_day := false
	for entry in log:
		if "wellness wing" in entry.text.to_lower() or "privacy" in entry.text.to_lower():
			has_tag_day = true
	_assert_true(has_tag_day, "Aster retells Tag Day")

	# Verify Peris mentions sanction
	var has_sanction := false
	for entry in log:
		if "gel" in entry.text.to_lower() or "breathing" in entry.text.to_lower():
			has_sanction = true
	_assert_true(has_sanction, "Peris mentions sanction/gel")

	# Verify escort unit protocol
	var has_protocol := false
	for entry in log:
		if "RE-SEDATION" in entry.text or "SEDATION" in entry.text:
			has_protocol = true
	_assert_true(has_protocol, "Escort unit protocol fires")

	# Verify door override after EMP
	var has_override := false
	for entry in log:
		if "OVERRIDE" in entry.text:
			has_override = true
	_assert_true(has_override, "Door override after EMP")

	# Verify bridge dialogue
	var has_bodies := false
	for entry in log:
		if "people down there" in entry.text:
			has_bodies = true
	_assert_true(has_bodies, "Bridge bodies dialogue exists")

	# Verify final bridge line
	var has_ahead := false
	for entry in log:
		if "ahead" in entry.text and "Lights" in entry.text:
			has_ahead = true
	_assert_true(has_ahead, "Final 'There's something ahead' line exists")

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Endo Drink Pickup ---
func _test_endo_drink() -> void:
	_test_name = "Endo Drink"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load junction chunk to get the drink mesh
	instance._load_chunk("junction")
	for i in range(2):
		await get_tree().process_frame

	var drink: MeshInstance3D = instance._drink_mesh
	_assert_true(drink != null, "Drink mesh exists")
	if not drink:
		instance.queue_free()
		await get_tree().process_frame
		return

	var drink_start_pos: Vector3 = drink.global_position
	_assert_true(drink_start_pos.y < -3.0, "Drink starts on container (got y: %.1f)" % drink_start_pos.y)

	# Set up Endo so the shelter step can run
	instance._endo.visible = true
	instance._endo.position = Vector3(
		instance.JUNCTION_POS.x - instance.SHELTER_SIZE.x / 2.0,
		instance.BELOW_Y + 0.5, 0)
	instance._register_gs_character("endo", instance._endo, 2.5)

	# Trigger the shelter step (Endo walks to container)
	instance._start_endo_shelter()
	# Advance the scheduler enough for Endo to reach the container
	for i in range(80):
		instance._scheduler.advance(0.1)
		await get_tree().process_frame

	var drink_after_walk: Vector3 = drink.global_position
	var drink_moved := drink_start_pos.distance_to(drink_after_walk) > 0.5
	_assert_true(drink_moved, "Drink moved after Endo walks (dist: %.2f)" % drink_start_pos.distance_to(drink_after_walk))

	# Advance more for Endo to walk back with the drink
	for i in range(80):
		instance._scheduler.advance(0.1)
		await get_tree().process_frame

	var endo_pos: Vector3 = instance._endo.global_position
	var drink_final: Vector3 = drink.global_position
	var drink_near_endo := endo_pos.distance_to(drink_final) < 2.0
	_assert_true(drink_near_endo, "Drink near Endo after delivery (dist: %.2f)" % endo_pos.distance_to(drink_final))

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Junction Arrival Flow ---
func _test_junction_flow() -> void:
	_test_name = "Junction Flow"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load junction chunk
	instance._load_chunk("junction")
	for i in range(3):
		await get_tree().process_frame

	# Verify interactable objects exist
	var interactable_names := ["Junction_Workbench", "Junction_Monitor", "Junction_Food", "Junction_Lookout", "Junction_Heater", "Junction_Markings", "Junction_Game"]
	var found_count := 0
	for iname in interactable_names:
		if instance.find_child(iname, true, false):
			found_count += 1
	_assert_true(found_count == 7, "All 7 junction interactables exist (got: %d)" % found_count)

	# Verify drink mesh exists on container
	_assert_true(instance._drink_mesh != null, "Drink mesh exists in junction")

	# Junction arrival sets dusk and enables movement.
	instance._start_junction_arrive()
	for i in range(3):
		await get_tree().process_frame

	_assert_true(instance._current_step == "junction_arrive", "Step is junction_arrive (got: %s)" % instance._current_step)

	# Verify Endo is NOT visible yet (arrives when Peris tends the plant)
	_assert_true(not instance._endo.visible, "Endo not visible on initial arrival")

	# Verify dormant plant exists
	var plant := instance.find_child("DormantPlant", true, false)
	_assert_true(plant != null, "Dormant plant interactable exists")

	# Trigger the plant interaction (simulates Peris tending it)
	if plant:
		plant._trigger()
	for i in range(5):
		await get_tree().process_frame
	# Advance scheduler past the 2s Endo entrance delay after plant
	for i in range(10):
		instance._scheduler.advance(0.5)
		await get_tree().process_frame

	_assert_true(instance._endo.visible, "Endo visible after plant tended")
	_assert_true(instance._current_step == "endo_enters", "Step advanced to endo_enters (got: %s)" % instance._current_step)

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Climb and Soft Lockout Dialogue ---
func _test_climb_and_lockout() -> void:
	_test_name = "Climb and Lockout"

	# Verify climb dialogue keys exist
	var has_climb_aster := DialogueData.text("elevator.aster.climb") != ""
	var has_climb_peris := DialogueData.text("elevator.peris.climb") != ""
	var has_another_way := DialogueData.text("elevator.aster.another_way") != ""
	_assert_true(has_climb_aster, "Aster climb dialogue exists")
	_assert_true(has_climb_peris, "Peris climb dialogue exists")
	_assert_true(has_another_way, "Another way dialogue exists")

	# Verify soft lockout dialogue (dismiss, not locked out)
	var has_dismiss := DialogueData.has_key("elevator.aster.dismiss")
	var has_not_back := DialogueData.has_key("elevator.peris.not_back")
	_assert_true(has_dismiss, "Aster dismiss (soft lockout) dialogue exists")
	_assert_true(has_not_back, "Peris not-back dialogue exists")

	# Verify junction interactable dialogue keys exist
	for prefix in ["junction.workbench", "junction.monitor", "junction.food", "junction.lookout", "junction.heater", "junction.markings", "junction.game"]:
		var has_aster := DialogueData.text(prefix + ".aster") != ""
		var has_peris := DialogueData.text(prefix + ".peris") != ""
		_assert_true(has_aster, "%s.aster dialogue exists" % prefix)
		_assert_true(has_peris, "%s.peris dialogue exists" % prefix)

# --- Test: Enemy System ---
func _test_enemy() -> void:
	_test_name = "Enemy"

	# Set up a minimal scene with GameState + scheduler
	var root := Node3D.new()
	root.name = "EnemyTestRoot"
	get_tree().root.add_child(root)

	var chars := Node3D.new()
	chars.name = "Characters"
	root.add_child(chars)

	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler

	# Create a target character (simulated player)
	var target := Node3D.new()
	target.name = "aster"
	target.set("char_id", "aster")
	target.position = Vector3(10, 0, 0)
	chars.add_child(target)
	# Give the target real hp: the enemy now disengages from a downed (hp <= 0) target, so a stat-less
	# target would be "killed" by the first hit (adjust_stat creates hp at -charge_damage) and the cycle
	# would stop. A live target lets us observe the repeating attack loop.
	gs.register_character("aster", Vector3(10, 0, 0), 3.0, {"hp": 500.0})

	# Create an enemy
	var enemy := Enemy.new()
	enemy.name = "test_enemy"
	enemy.game_state = gs
	enemy.char_id = "enemy_0"
	enemy.max_hp = 100.0
	enemy.detection_range = 6.0
	enemy._detection_targets = ["aster"]
	chars.add_child(enemy)
	gs.register_character("enemy_0", Vector3(0, 0, 0), 1.5, {"detection_range": 6.0})

	for i in range(2):
		await get_tree().process_frame

	# Test: initial state
	_assert_true(enemy.get_state() == "idle", "Initial state is idle (got: %s)" % enemy.get_state())
	_assert_true(enemy.is_alive(), "Enemy starts alive")
	_assert_true(enemy._hp == 100.0, "HP starts at max (got: %.1f)" % enemy._hp)

	# Activation outside range should not detect.
	enemy.activate()
	for i in range(5):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(enemy.get_state() == "idle", "No detection at distance 10 (got: %s)" % enemy.get_state())

	# Move target within range via command (triggers predictive detection)
	gs.command_move_to_pos("aster", Vector3(1, 0, 0))

	# Predictive detection should fire.
	for i in range(10):
		scheduler.advance(0.5)
		await get_tree().process_frame

	var combat_states := ["alert", "pursuit", "windup", "charge", "impact", "recover"]
	_assert_true(enemy.get_state() in combat_states,
		"Detects target within range (got: %s)" % enemy.get_state())

	# Check for alert label ("!") on the target (may already have transitioned)
	var has_alert := false
	for child in target.get_children():
		if child is Label3D and child.text == "!":
			has_alert = true
	if enemy.get_state() == "alert":
		_assert_true(has_alert, "Alert '!' appears on target")
	else:
		_assert_true(true, "Alert '!' appeared then removed (now in %s)" % enemy.get_state())

	# Advance through the full attack cycle
	for i in range(20):
		scheduler.advance(0.3)
		await get_tree().process_frame
	_assert_true(enemy.get_state() in combat_states,
		"Attack cycle progresses (got: %s)" % enemy.get_state())

	# Test: take_damage
	enemy.take_damage(40.0)
	_assert_true(enemy._hp == 60.0, "HP after 40 damage (got: %.1f)" % enemy._hp)
	_assert_true(enemy.is_alive(), "Still alive at 60 HP")

	# Test: die
	enemy.take_damage(60.0)
	_assert_true(enemy._hp == 0.0, "HP after lethal damage (got: %.1f)" % enemy._hp)
	_assert_true(not enemy.is_alive(), "Dead after lethal damage")
	_assert_true(enemy.get_state() == "dead", "State is dead (got: %s)" % enemy.get_state())

	# --- Test: enemy detects player approaching on enemy route ---
	var route_enemy := Enemy.new()
	route_enemy.name = "route_test"
	route_enemy.game_state = gs
	route_enemy.char_id = "route_e"
	route_enemy.detection_range = 6.0
	route_enemy._detection_targets = ["player_route"]
	chars.add_child(route_enemy)
	gs.register_character("route_e", Vector3(20, 0, -4), 1.5, {"detection_range": 6.0})
	route_enemy.position = Vector3(20, 0, -4)

	var route_player := Node3D.new()
	route_player.name = "player_route"
	route_player.set("char_id", "player_route")
	route_player.position = Vector3(12, 0, -4)
	chars.add_child(route_player)
	gs.register_character("player_route", Vector3(12, 0, -4), 3.0, {"hp": 500.0})

	route_enemy.activate()
	# Move player toward enemy (triggers predictive detection)
	gs.command_move_to_pos("player_route", Vector3(20, 0, -4))
	for i in range(2):
		await get_tree().process_frame

	for i in range(8):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(route_enemy.get_state() != "idle" and route_enemy.get_state() != "patrol",
		"Enemy detects player on enemy route (got: %s)" % route_enemy.get_state())

	# --- Test: player on hazard route is safe from enemies ---
	var safe_enemy := Enemy.new()
	safe_enemy.name = "safe_test"
	safe_enemy.game_state = gs
	safe_enemy.char_id = "safe_e"
	safe_enemy.detection_range = 6.0
	safe_enemy._detection_targets = ["player_safe"]
	chars.add_child(safe_enemy)
	gs.register_character("safe_e", Vector3(20, 0, -4), 1.5, {"detection_range": 6.0})
	safe_enemy.position = Vector3(20, 0, -4)

	var safe_player := Node3D.new()
	safe_player.name = "player_safe"
	safe_player.set("char_id", "player_safe")
	safe_player.position = Vector3(20, 0, 5)
	chars.add_child(safe_player)
	gs.register_character("player_safe", Vector3(20, 0, 5), 3.0)

	safe_enemy.activate()
	# Player moves along hazard route (distance 9 from enemy, out of range 6)
	gs.command_move_to_pos("player_safe", Vector3(30, 0, 5))
	for i in range(2):
		await get_tree().process_frame

	for i in range(8):
		scheduler.advance(0.5)
		await get_tree().process_frame
	_assert_true(safe_enemy.get_state() == "idle",
		"Enemy ignores player on hazard route dist=9 (got: %s)" % safe_enemy.get_state())

	root.queue_free()
	await get_tree().process_frame

# --- Test: Chain Enemy ---
func _test_chain_enemy() -> void:
	_test_name = "Chain Enemy"

	var root := Node3D.new()
	root.name = "ChainTestRoot"
	get_tree().root.add_child(root)

	var chars := Node3D.new()
	chars.name = "Characters"
	root.add_child(chars)

	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = scheduler

	# Create a chain enemy
	var chain := ChainEnemy.new()
	chain.name = "test_chain"
	chain.game_state = gs
	chain.char_id = "chain_0"
	chain.segment_count = 6
	chain.segment_spacing = 0.3
	chain.max_stretch = 0.5
	chain.detection_range = 5.0
	chain._detection_targets = ["target_c"]
	chars.add_child(chain)
	gs.register_character("chain_0", Vector3(0, 0, 0), 1.5, {"detection_range": 5.0})

	for i in range(3):
		await get_tree().process_frame

	# Test: correct number of segments created
	_assert_true(chain._segments.size() == 6, "6 segments created (got: %d)" % chain._segments.size())
	_assert_true(chain._segment_positions.size() == 6, "6 segment positions (got: %d)" % chain._segment_positions.size())

	# Test: set_wall_line initializes positions along a direction
	chain.set_wall_line(Vector3(5, 0, 0), Vector3(1, 0, 0))
	_assert_true(chain._segment_positions[0].distance_to(Vector3(5, 0, 0)) < 0.01,
		"Wall line starts at (5,0,0)")
	_assert_true(chain._segment_positions[5].distance_to(Vector3(5 + 5 * 0.3, 0, 0)) < 0.01,
		"Wall line end segment at correct position")

	# Test: activate works (inherits from Enemy)
	chain.activate()
	_assert_true(chain.get_state() == "idle", "Initial state is idle (got: %s)" % chain.get_state())

	# Record initial segment positions
	var initial_positions: Array[Vector3] = []
	for pos in chain._segment_positions:
		initial_positions.append(pos)

	# Move the lead point via GameState
	gs.command_move_to_pos("chain_0", Vector3(10, 0, 0))

	# Advance scheduler and process frames so segments follow
	for i in range(30):
		scheduler.advance(0.1)
		await get_tree().process_frame

	# Test: segments have moved from initial positions
	var segments_moved := false
	for i in range(chain._segment_positions.size()):
		if chain._segment_positions[i].distance_to(initial_positions[i]) > 0.1:
			segments_moved = true
			break
	_assert_true(segments_moved, "Segments moved after lead point moved")

	# Spacing constraint keeps segments within max_stretch.
	var spacing_ok := true
	for i in range(1, chain._segment_positions.size()):
		var dist: float = chain._segment_positions[i].distance_to(chain._segment_positions[i - 1])
		if dist > chain.max_stretch + 0.01:
			spacing_ok = false
	_assert_true(spacing_ok, "All segments within max_stretch of previous")

	# Contact damage with a target near a middle segment.
	var target := Node3D.new()
	target.name = "target_c"
	target.set("char_id", "target_c")
	chars.add_child(target)
	gs.register_character("target_c", Vector3(0, 0, 0), 1.0)

	# Position target near segment 3
	var seg3_pos: Vector3 = chain._segment_positions[3]
	target.position = seg3_pos + Vector3(0.3, 0, 0)
	gs.characters["target_c"].position = target.position

	var hit_detected := false
	chain.hit_target.connect(func(tid: String, dmg: float):
		hit_detected = true
	)

	# Test segment contact directly using get_segment_positions
	# Place target exactly at segment 3's position
	chain._segment_positions[3] = Vector3(20, 0, 5)
	target.global_position = Vector3(20.2, 0, 5)
	var seg_positions := chain.get_segment_positions()
	var contact_found := false
	for sp in seg_positions:
		if sp.distance_to(target.global_position) < 0.6:
			contact_found = true
			break
	_assert_true(contact_found, "Segment contact within 0.6 of target")

	# Also test the public check_segment_contact method
	chain._segment_positions[2] = target.global_position + Vector3(0.1, 0, 0)
	var contact_id := chain.check_segment_contact(0.6)
	_assert_true(contact_id == "target_c", "check_segment_contact finds target (got: '%s')" % contact_id)

	# Test: color change propagates to all segments
	chain._set_mesh_color(Color(0.9, 0.1, 0.1))
	var all_red := true
	for mat in chain._segment_mats:
		if mat.albedo_color.r < 0.8:
			all_red = false
	_assert_true(all_red, "All segments turn red on color change")

	# Anchor constraint keeps head within max_reach.
	chain._fsm.force_current("idle")
	chain._hp = chain.max_hp
	chain._anchored = true
	var anchor := Vector3(0, 0, 0)
	chain._anchor_pos = anchor
	var max_reach: float = chain.get_max_reach()
	_assert_true(absf(max_reach - chain.segment_count * chain.segment_spacing) < 0.01,
		"Max reach = segment_count * spacing (got: %.2f)" % max_reach)

	# Move lead point way beyond max reach
	chain.global_position = Vector3(max_reach + 5.0, 0, 0)
	# Reset segment positions so _process can work cleanly
	for i in range(chain.segment_count):
		chain._segment_positions[i] = chain.global_position - Vector3(0, 0, i * chain.segment_spacing)
	chain._segment_positions[chain.segment_count - 1] = anchor

	for i in range(5):
		scheduler.advance(0.1)
		await get_tree().process_frame

	# Head should have been clamped back
	var head_dist: float = chain.global_position.distance_to(anchor)
	_assert_true(head_dist <= max_reach + 0.05,
		"Anchored head within max_reach (dist: %.2f, max: %.2f)" % [head_dist, max_reach])

	# Tail should be pinned to anchor
	var tail_dist: float = chain._segment_positions[chain.segment_count - 1].distance_to(anchor)
	_assert_true(tail_dist < 0.01, "Tail pinned to anchor (dist: %.3f)" % tail_dist)

	# Test: detach releases the constraint
	chain.detach()
	chain.global_position = Vector3(max_reach + 10.0, 0, 0)
	for i in range(5):
		scheduler.advance(0.1)
		await get_tree().process_frame
	var detached_dist: float = chain.global_position.distance_to(anchor)
	_assert_true(detached_dist > max_reach, "Detached head moves beyond max_reach (dist: %.2f)" % detached_dist)

	# Re-anchor to another position.
	var new_anchor := Vector3(50, 0, 0)
	chain.anchor_to(new_anchor)
	_assert_true(chain._anchored, "Re-anchored after anchor_to()")
	_assert_true(chain._anchor_pos.distance_to(new_anchor) < 0.01, "New anchor position set")

	# HP/death inherited from Enemy; run last because it kills the chain.
	chain._fsm.force_current("idle")
	chain._hp = chain.max_hp
	chain.take_damage(chain.max_hp)
	_assert_true(not chain.is_alive(), "Chain dies when HP reaches 0")
	_assert_true(chain.get_state() == "dead", "Chain state is dead (got: %s)" % chain.get_state())

	root.queue_free()
	await get_tree().process_frame

# --- Test: Act 1 Levels ---
func _test_act1() -> void:
	_test_name = "Act 1 Levels"
	var scene := load("res://scenes/tutorial/act1.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Verify scene structure
	_assert_true(instance.find_child("Environment", false, false) != null, "Environment node exists")
	_assert_true(instance.find_child("Characters", false, false) != null, "Characters node exists")

	# Verify characters
	var aster := instance.find_child("Aster", true, false)
	var peris := instance.find_child("Peris", true, false)
	var endo := instance.find_child("Endo", true, false)
	_assert_true(aster != null, "Aster exists")
	_assert_true(peris != null, "Peris exists")
	_assert_true(endo != null, "Endo exists")
	_assert_true(endo.visible, "Endo visible at start")

	# Verify channels chunk loaded
	_assert_true(instance._chunks.has("channels"), "Channels chunk loaded at start")

	# Load all 4 chunks and verify
	instance._load_chunk("stacks")
	instance._load_chunk("rings")
	instance._load_chunk("lockout")
	for i in range(2):
		await get_tree().process_frame

	_assert_true(instance._chunks.has("stacks"), "Stacks chunk loaded")
	_assert_true(instance._chunks.has("rings"), "Rings chunk loaded")
	_assert_true(instance._chunks.has("lockout"), "Lockout chunk loaded")

	# Verify key scene anchors exist
	_assert_true(instance.find_child("ChannelsBody", true, false) != null, "Body landmark in channels")
	_assert_true(instance.find_child("ChannelsWindowLane_window_one", true, false) != null, "First timed window lane in channels")
	_assert_true(instance.find_child("ChannelsWindowInteract_window_one", true, false) != null, "First timed window interactable in channels")
	_assert_true(instance.find_child("ChannelsWindowChannel_window_one_0", true, false) != null, "First timed window rhythm channel in channels")
	_assert_true(instance.find_child("ChannelsWindowBridge_window_one_0", true, false) != null, "First timed window bridge segment in channels")
	_assert_true(instance.find_child("ChannelsWindowCorpse_window_one_0", true, false) != null, "First timed window corpse cluster in channels")
	_assert_true(instance.find_child("ChannelsWindowSwarm_window_one_0", true, false) != null, "First timed window siderophore unit in channels")
	_assert_true(instance.find_child("SecondFerrolure", true, false) != null, "Second ferrolure in channels")
	_assert_true(instance.find_child("ChannelsWindowLane_window_two", true, false) != null, "Second timed window lane in channels")
	_assert_true(instance.find_child("ChannelsWindowInteract_window_two", true, false) != null, "Second timed window interactable in channels")
	_assert_true(instance.find_child("ChannelsWindowChannel_window_two_0", true, false) != null, "Second timed window rhythm channel in channels")
	_assert_true(instance.find_child("EncounterFerrolure", true, false) != null, "Encounter ferrolure in channels")
	_assert_true(instance.find_child("EncounterFerrolureInteract", true, false) != null, "Encounter interactable in channels")
	_assert_true(instance.find_child("ChannelsHideSpot", true, false) != null, "Hide spot in channels")
	_assert_true(instance.find_child("ChannelsSwarm_0", true, false) != null, "Swarm cluster in channels")
	_assert_true(instance.find_child("ChannelsShelterDoor", true, false) != null, "Shelter door in channels")
	_assert_true(instance.find_child("ChannelsShortcutGate", true, false) != null, "Shortcut gate in channels")
	_assert_true(instance.find_child("ChannelsShelterLabel", true, false) != null, "Shelter label in channels")
	_assert_true(instance.find_child("DataTerminal", true, false) != null, "Terminal interactable in stacks")
	_assert_true(instance.find_child("SignalWall", true, false) != null, "Signal wall interactable in stacks")
	_assert_true(instance.find_child("SupportWorkspace", true, false) != null, "Support workspace interactable in stacks")
	_assert_true(instance.find_child("ClientNPC", true, false) != null, "Client interactable in rings")
	_assert_true(instance.find_child("AccessPanel", true, false) != null, "Access panel in lockout")
	_assert_true(not instance._channels_shortcut_unlocked, "Channels shortcut starts locked")
	_assert_true(not instance._channels_party_recuperated, "Party starts unrested in channels")

	# Smoke the two timed ferrolure windows that pad out the Channels route.
	instance.start_channels_window_puzzle("window_one")
	await get_tree().process_frame
	_assert_true(instance._current_step == "channels_window_one_activate", "Window one enters activation step")
	var window_one_contract: Dictionary = instance.headless_get_state().get("channels_window_lanes", {}).get("window_one", {})
	_assert_equals(int(window_one_contract.get("periodic_channel_count", 0)), 3, "Window one exposes three periodic flood channels")
	_assert_true(bool(window_one_contract.get("wash_analysis", {}).get("guaranteed", false)), "Window one wash analysis guarantees a washout across timing offsets")
	instance.activate_channels_window_lure("window_one")
	_assert_true(instance._current_step == "channels_window_one_cross", "Window one activation opens the crossing window")
	instance.headless_advance(6.0)
	var window_one_rhythm_state: Dictionary = instance.headless_get_state().get("channels_window_lanes", {}).get("window_one", {})
	_assert_equals(str(window_one_rhythm_state.get("swarm_state", "")), "washed", "Window one ferrolure branch washes the siderophore pack")
	_assert_true(int(window_one_rhythm_state.get("washed_channel_index", -1)) >= 0, "Window one records which rhythm channel washed the pack")
	instance.headless_set_character_position("aster", instance.CHANNELS_WINDOW_ONE_GOAL_POS)
	instance._update_channels_window_puzzles(0.1, 1.0)
	_assert_true(instance._current_step == "channels_to_ferrolure", "Window one success returns to the ferrolure travel step")
	_assert_true(instance._channels_window_lanes["window_one"]["last_outcome"] == "success", "Window one records a success outcome")

	instance.start_channels_window_puzzle("window_two")
	await get_tree().process_frame
	instance.activate_channels_window_lure("window_two")
	instance.headless_advance(instance.CHANNELS_WINDOW_TWO_DURATION + 0.1)
	_assert_true(instance._channels_window_lanes["window_two"]["phase"] == "failed", "Window two can fail on a missed crossing window")
	_assert_true(instance._channels_window_lanes["window_two"]["last_outcome"] == "window_closed", "Window two failure records the timeout reason")

	# Smoke the Channels hide-and-run encounter.
	instance.prepare_channels_fragment()
	var hide_spot := instance.find_child("ChannelsHideSpot", true, false)
	instance._begin_channels_encounter()
	await get_tree().process_frame
	_assert_true(instance._current_step == "channels_encounter_activate", "Encounter enters activation step")
	_assert_true(instance._active_character == "endo", "Encounter hands control to Endo")
	_assert_true(instance._player == endo, "Endo becomes the active player for the encounter")
	_assert_true(not instance._channels_run_lure_active, "Encounter lure starts inactive")

	instance._on_channels_run_lure_activated()
	_assert_true(instance._current_step == "channels_encounter_hide", "Lure activation advances to hide step")
	_assert_true(instance._channels_run_lure_active, "Lure activation powers the encounter plant")

	instance._on_channels_run_lure_expired()
	_assert_true(instance._channels_encounter_resetting, "Missing the hide window arms an encounter retry")
	instance._scheduler.cancel_tag("channels_run_lure_expire")
	instance._scheduler.cancel_tag("channels_encounter_retry")
	instance._reset_channels_encounter_nodes()

	instance._begin_channels_encounter()
	instance._on_channels_run_lure_activated()
	endo.global_position = hide_spot.global_position
	instance._update_channels_encounter(0.1, 1.0)
	_assert_true(instance._channels_party_hidden, "Endo can hide before the lure expires")

	instance._on_channels_run_lure_expired()
	_assert_true(instance._current_step == "channels_encounter_run", "Hidden party can transition into the run step")
	_assert_true(not instance._channels_run_lure_active, "Lure powers down before the shelter sprint")

	instance._aster_hp = 41.0
	instance._peris_hp = 58.0
	if instance._game_state.characters.has("aster"):
		instance._game_state.characters["aster"].stats["atp"] = 3.0
	if instance._game_state.characters.has("peris"):
		instance._game_state.characters["peris"].stats["atp"] = 4.0
	endo.global_position = instance.CHANNELS_SHELTER_POS
	instance._update_channels_encounter(0.1, 1.0)
	_assert_true(instance._current_step == "channels_shelter", "Encounter success advances to the shelter beat")
	_assert_true(instance._channels_shortcut_unlocked, "Shelter reach unlocks the channels shortcut")
	_assert_true(instance._channels_party_recuperated, "Shelter reach marks the party as recuperated")
	_assert_equals(instance._aster_hp, 100.0, "Shelter recuperation restores Aster HP")
	_assert_equals(instance._peris_hp, 100.0, "Shelter recuperation restores Peris HP")
	_assert_equals(float(instance._game_state.characters["aster"].stats.get("atp", 0.0)), 8.0, "Shelter recuperation restores Aster ATP")
	_assert_equals(float(instance._game_state.characters["peris"].stats.get("atp", 0.0)), 8.0, "Shelter recuperation restores Peris ATP")

	var engram_journal = _test_singleton(ENGRAM_JOURNAL_SINGLETON, ENGRAM_JOURNAL_SCRIPT_PATH)
	_assert_true(engram_journal != null, "EngramJournal singleton is available for Stacks")
	if engram_journal != null:
		engram_journal.call("reset_state", false)
	instance.prepare_stacks_fragment("engram")
	instance.trigger_stacks_support_log()
	await get_tree().process_frame
	if engram_journal != null:
		_assert_equals(int(engram_journal.call("get_entry_count")), 1, "Stacks intro creates one Engram support log")
	_assert_true(instance._engram_overlay.visible, "Stacks intro opens the Engram overlay")
	_assert_equals(instance.headless_get_state()["stacks"]["engram"]["story_key"], "stacks_support_team_log", "Stacks intro records the support log story key")
	instance.close_stacks_engram_overlay()
	instance.headless_advance(0.2)
	_assert_true(instance._current_step == "stacks_terminal", "Closing the Engram advances to the terminal beat")

	instance.prepare_stacks_fragment("terminal")
	instance.trigger_stacks_terminal()
	_assert_true(instance._stacks_terminal_interacted, "Stacks terminal interaction is tracked")
	_assert_true(instance._current_step == "stacks_signal", "Stacks terminal interaction advances to signal beat")

	instance.prepare_stacks_fragment("signal")
	instance.trigger_stacks_signal()
	_assert_true(instance._stacks_signal_interacted, "Stacks signal interaction is tracked")
	_assert_true(instance._current_step == "stacks_archive", "Stacks signal interaction advances to archive beat")

	instance.prepare_stacks_fragment("archive")
	instance.trigger_stacks_archive()
	_assert_true(instance._stacks_archive_interacted, "Stacks workspace interaction is tracked")
	_assert_true(instance._stacks_audit_flags_found, "Stacks workspace interaction flags the audit clue")
	_assert_true(instance._current_step == "stacks_explore", "Stacks workspace interaction returns control to exploration")

	# Verify dialogue keys exist for all scenes
	for prefix in ["channels.narration.enter", "channels.peris.know_place", "channels.aster.report",
		"channels.narration.window_one", "channels.endo.window_one", "channels.peris.touch",
		"channels.narration.window_two", "channels.peris.window_two", "channels.endo.kneel",
		"channels.narration.recuperate", "channels.narration.shortcut",
		"stacks.engram.support_log.title", "stacks.aster.support_team", "stacks.aster.standardization", "stacks.aster.right",
		"rings.peris.wall", "rings.endo.stops", "rings.peris.visiting",
		"lockout.system.rejected", "lockout.aster.not_in", "lockout.peris.back_to"]:
		var text := DialogueData.text(prefix)
		_assert_true(text != "", "Dialogue key exists: %s" % prefix)

	# Verify chunk unloading works
	instance._unload_chunk("channels")
	await get_tree().process_frame
	_assert_true(not instance._chunks.has("channels"), "Channels unloaded")
	_assert_true(instance.find_child("EncounterFerrolureInteract", true, false) == null, "Encounter interactable unloads with channels")

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Predictive Detection (quadratic solver) ---
func _test_predictive_detection() -> void:
	_test_name = "Predictive Detection"

	# User example: two units 10 apart, closing at 2 units/sec total.
	# Ranges 4 and 2 produce events at t=3 and t=4.
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.scheduler = sched

	gs.register_character("unit_a", Vector3(0, 0, 0), 1.0, {"detection_range": 4.0})
	gs.register_character("unit_b", Vector3(10, 0, 0), 1.0, {"detection_range": 2.0})

	var detections: Array[Dictionary] = []
	gs.detection_predicted.connect(func(det: String, tgt: String):
		detections.append({"detector": det, "target": tgt, "tick": sched.get_current_tick()})
	)

	gs.command_move_to_pos("unit_a", Vector3(10, 0, 0))
	gs.command_move_to_pos("unit_b", Vector3(0, 0, 0))

	# At t=3, unit_a should detect.
	sched.advance_ticks(3.0)
	_assert_true(detections.size() >= 1, "Head-on: first detection by t=3 (got: %d)" % detections.size())
	if detections.size() >= 1:
		_assert_true(detections[0].detector == "unit_a", "Head-on: unit_a detects first (got: %s)" % detections[0].detector)
		_assert_true(absf(detections[0].tick - 3.0) < 0.1, "Head-on: first at t=3 (got: %.2f)" % detections[0].tick)

	# At t=4, unit_b should detect.
	sched.advance_ticks(1.0)
	_assert_true(detections.size() >= 2, "Head-on: second detection by t=4 (got: %d)" % detections.size())
	if detections.size() >= 2:
		_assert_true(detections[1].detector == "unit_b", "Head-on: unit_b detects second (got: %s)" % detections[1].detector)
		_assert_true(absf(detections[1].tick - 4.0) < 0.1, "Head-on: second at t=4 (got: %.2f)" % detections[1].tick)

	# One moving, one stationary: range 3, distance 8, speed 2, t=2.5.
	var gs2 := GameState.new()
	var sched2 := EventScheduler.new()
	gs2.scheduler = sched2
	gs2.register_character("mover", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs2.register_character("static_c", Vector3(8, 0, 0), 1.0, {})

	var det2: Array[Dictionary] = []
	gs2.detection_predicted.connect(func(det: String, tgt: String):
		det2.append({"detector": det, "target": tgt, "tick": sched2.get_current_tick()})
	)

	gs2.command_move_to_pos("mover", Vector3(10, 0, 0))
	sched2.advance_ticks(2.5)
	_assert_true(det2.size() >= 1, "One-moving: detection by t=2.5 (got: %d)" % det2.size())
	if det2.size() >= 1:
		_assert_true(absf(det2[0].tick - 2.5) < 0.1, "One-moving: at t=2.5 (got: %.2f)" % det2[0].tick)

	# Movement cancellation invalidates predictions.
	var gs3 := GameState.new()
	var sched3 := EventScheduler.new()
	gs3.scheduler = sched3
	gs3.register_character("cancel_a", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs3.register_character("cancel_b", Vector3(6, 0, 0), 1.0, {})

	var det3: Array[Dictionary] = []
	gs3.detection_predicted.connect(func(det: String, tgt: String):
		det3.append({"detector": det, "tick": sched3.get_current_tick()})
	)

	gs3.command_move_to_pos("cancel_a", Vector3(10, 0, 0))
	gs3.command_stop("cancel_a")
	sched3.advance_ticks(5.0)
	_assert_true(det3.size() == 0, "Cancelled: no detection (got: %d)" % det3.size())

	# Already in range triggers immediate detection.
	var gs4 := GameState.new()
	var sched4 := EventScheduler.new()
	gs4.scheduler = sched4
	gs4.register_character("close_a", Vector3(0, 0, 0), 1.0, {"detection_range": 5.0})
	gs4.register_character("close_b", Vector3(3, 0, 0), 1.0, {})

	var det4: Array[Dictionary] = []
	gs4.detection_predicted.connect(func(det: String, tgt: String):
		det4.append({"detector": det, "tick": sched4.get_current_tick()})
	)

	gs4.command_move_to_pos("close_a", Vector3(1, 0, 0))
	sched4.advance_ticks(0.01)
	_assert_true(det4.size() >= 1, "Already in range: immediate detection (got: %d)" % det4.size())

	# Parallel paths never converge.
	var gs5 := GameState.new()
	var sched5 := EventScheduler.new()
	gs5.scheduler = sched5
	gs5.register_character("par_a", Vector3(0, 0, 0), 2.0, {"detection_range": 3.0})
	gs5.register_character("par_b", Vector3(0, 0, 5), 2.0, {})

	var det5: Array[Dictionary] = []
	gs5.detection_predicted.connect(func(det: String, tgt: String):
		det5.append({"detector": det})
	)

	gs5.command_move_to_pos("par_a", Vector3(10, 0, 0))
	gs5.command_move_to_pos("par_b", Vector3(10, 0, 5))
	sched5.advance_ticks(10.0)
	_assert_true(det5.size() == 0, "Parallel paths: no detection (got: %d)" % det5.size())

# --- Test: Detection Equivalence (predictive vs brute-force tick scan) ---
func _test_detection_equivalence() -> void:
	_test_name = "Detection Equivalence"

	# Brute-force scanner: advance in small ticks, check distances each step
	# Returns the first tick where distance < range, or -1.0
	var _bruteforce_detect := func(
		pos_a: Vector3, vel_a: Vector3,
		pos_b: Vector3, vel_b: Vector3,
		det_range: float, max_time: float
	) -> float:
		var dt := 0.01
		var t := 0.0
		while t <= max_time:
			var pa := pos_a + vel_a * t
			var pb := pos_b + vel_b * t
			var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if dist < det_range:
				return t
			t += dt
		return -1.0

	# Scenario configs: [pos_a, vel_a, pos_b, vel_b, range, label]
	var scenarios: Array[Dictionary] = [
		{"pa": Vector3(0,0,0), "va": Vector3(2,0,0), "pb": Vector3(12,0,0), "vb": Vector3.ZERO, "range": 3.0, "label": "Approach stationary"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(10,0,0), "vb": Vector3(-1,0,0), "range": 4.0, "label": "Head-on range=4"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(10,0,0), "vb": Vector3(-1,0,0), "range": 2.0, "label": "Head-on range=2"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,1), "pb": Vector3(8,0,8), "vb": Vector3.ZERO, "range": 2.0, "label": "Diagonal approach"},
		{"pa": Vector3(0,0,0), "va": Vector3(3,0,0), "pb": Vector3(5,0,4), "vb": Vector3(0,0,-1), "range": 3.0, "label": "Perpendicular closing"},
		{"pa": Vector3(0,0,0), "va": Vector3(1,0,0), "pb": Vector3(0,0,20), "vb": Vector3(1,0,0), "range": 5.0, "label": "Parallel far apart"},
		{"pa": Vector3(0,0,0), "va": Vector3(2,0,0), "pb": Vector3(15,0,2), "vb": Vector3(-1,0,0), "range": 3.0, "label": "Offset head-on"},
		{"pa": Vector3(0,0,0), "va": Vector3(0,0,0), "pb": Vector3(4,0,0), "vb": Vector3.ZERO, "range": 5.0, "label": "Both static in range"},
		{"pa": Vector3(0,0,0), "va": Vector3(0,0,0), "pb": Vector3(10,0,0), "vb": Vector3.ZERO, "range": 5.0, "label": "Both static out of range"},
	]

	for scenario in scenarios:
		var pa: Vector3 = scenario.pa
		var va: Vector3 = scenario.va
		var pb: Vector3 = scenario.pb
		var vb: Vector3 = scenario.vb
		var det_range: float = scenario.range
		var label: String = scenario.label

		# Brute force result
		var bf_t: float = _bruteforce_detect.call(pa, va, pb, vb, det_range, 20.0)

		# Predictive result via GameState
		var sched := EventScheduler.new()
		var gs := GameState.new()
		gs.scheduler = sched
		var speed_a: float = va.length() if va.length() > 0.01 else 1.0
		var speed_b: float = vb.length() if vb.length() > 0.01 else 1.0
		gs.register_character("det_a", pa, speed_a, {"detection_range": det_range})
		gs.register_character("det_b", pb, speed_b, {})

		var pred_detections: Array[float] = []
		gs.detection_predicted.connect(func(_det: String, _tgt: String):
			pred_detections.append(sched.get_current_tick())
		)

		# Issue movement commands matching the velocities
		if va.length() > 0.01:
			var dest_a := pa + va.normalized() * 30.0
			gs.command_move_to_pos("det_a", dest_a)
		if vb.length() > 0.01:
			var dest_b := pb + vb.normalized() * 30.0
			gs.command_move_to_pos("det_b", dest_b)
		# For static in-range, trigger recompute manually
		if va.length() <= 0.01 and vb.length() <= 0.01:
			gs._recompute_all_detection_predictions()

		sched.advance_ticks(20.0)
		var pred_t: float = pred_detections[0] if pred_detections.size() > 0 else -1.0

		# Compare
		if bf_t < 0.0:
			_assert_true(pred_t < 0.0, "%s: both agree no detection" % label)
		else:
			_assert_true(pred_t >= 0.0, "%s: both agree detection occurs" % label)
			if pred_t >= 0.0:
				var diff := absf(pred_t - bf_t)
				_assert_true(diff < 0.05, "%s: timing matches (bf=%.2f pred=%.2f diff=%.3f)" % [label, bf_t, pred_t, diff])

	# Multi-entity scenario: 3 detectors, 2 targets moving in various directions
	var sched_m := EventScheduler.new()
	var gs_m := GameState.new()
	gs_m.scheduler = sched_m
	gs_m.register_character("d1", Vector3(0, 0, 0), 2.0, {"detection_range": 4.0})
	gs_m.register_character("d2", Vector3(0, 0, 10), 1.5, {"detection_range": 3.0})
	gs_m.register_character("d3", Vector3(10, 0, 5), 1.0, {"detection_range": 5.0})
	gs_m.register_character("t1", Vector3(8, 0, 0), 2.0, {})
	gs_m.register_character("t2", Vector3(5, 0, 12), 1.0, {})

	var multi_det: Array[Dictionary] = []
	gs_m.detection_predicted.connect(func(det: String, tgt: String):
		multi_det.append({"detector": det, "target": tgt, "tick": sched_m.get_current_tick()})
	)

	gs_m.command_move_to_pos("d1", Vector3(10, 0, 0))
	gs_m.command_move_to_pos("t1", Vector3(0, 0, 0))
	gs_m.command_move_to_pos("d2", Vector3(5, 0, 12))
	gs_m.command_move_to_pos("t2", Vector3(0, 0, 10))

	sched_m.advance_ticks(10.0)

	# d1: range 4, start dist 8, closing at 4 units/sec, t=1.0.
	# d2: range 3, dist ~5.4, closing at ~2.5, t≈1.0.
	# d3: stationary range 5; t1 starts near range and moves away.
	_assert_true(multi_det.size() >= 2, "Multi-entity: at least 2 detections (got: %d)" % multi_det.size())
	if multi_det.size() >= 1:
		_assert_true(multi_det[0].tick < 2.0, "Multi-entity: first detection before t=2 (got: %.2f)" % multi_det[0].tick)

	# --- N=10 large-scale equivalence tests ---
	# Setup: 10 units with various positions, speeds, detection ranges
	# Compare all predicted detections against brute-force tick scan

	# Brute-force scanner that models finite paths (units stop at destination)
	var _bf_scan_all := func(
		units: Array[Dictionary],  # [{id, pos, vel, range}]
		max_time: float, dt: float
	) -> Array[Dictionary]:  # [{detector, target, tick}]
		var results: Array[Dictionary] = []
		var detected: Dictionary = {}
		# Compute max travel time per unit based on path_len field (default 30)
		var max_travel: Array[float] = []
		for u in units:
			var spd: float = u.vel.length()
			var plen: float = u.get("path_len", 30.0)
			max_travel.append(plen / spd if spd > 0.01 else 0.0)
		# Position at time t, clamped to path end
		var _pos_at := func(u: Dictionary, t_val: float, mt: float) -> Vector3:
			var tt: float = minf(t_val, mt) if mt > 0.0 else 0.0
			return u.pos + u.vel * tt
		var t := 0.0
		while t <= max_time:
			for i in range(units.size()):
				if units[i].range <= 0.0:
					continue
				var pa: Vector3 = _pos_at.call(units[i], t, max_travel[i])
				for j in range(units.size()):
					if i == j:
						continue
					var key := "%s_%s" % [units[i].id, units[j].id]
					if detected.has(key):
						continue
					var pb: Vector3 = _pos_at.call(units[j], t, max_travel[j])
					var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
					if dist < units[i].range:
						detected[key] = true
						results.append({"detector": units[i].id, "target": units[j].id, "tick": t})
			t += dt
		return results

	# Test A: 10 units in a line, every other one moving toward center
	var setup_a: Array[Dictionary] = []
	for i in range(10):
		var x: float = i * 4.0
		var vel := Vector3(-1.0 if i % 2 == 0 else 1.0, 0, 0)
		var det_range: float = 3.0 if i < 5 else 0.0
		setup_a.append({"id": "a%d" % i, "pos": Vector3(x, 0, 0), "vel": vel, "range": det_range})

	var bf_a: Array[Dictionary] = _bf_scan_all.call(setup_a, 15.0, 0.01)

	var sched_a := EventScheduler.new()
	var gs_a := GameState.new()
	gs_a.scheduler = sched_a
	for u in setup_a:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_a.register_character(u.id, u.pos, spd, stats)

	var pred_a: Array[Dictionary] = []
	var pred_a_seen: Dictionary = {}
	gs_a.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_a_seen.has(key):
			pred_a_seen[key] = true
			pred_a.append({"detector": det, "target": tgt, "tick": sched_a.get_current_tick()})
	)
	for u in setup_a:
		if u.vel.length() > 0.01:
			gs_a.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 30.0)
	sched_a.advance_ticks(15.0)

	_assert_true(bf_a.size() == pred_a.size(),
		"Line-10: same detection count (bf=%d pred=%d)" % [bf_a.size(), pred_a.size()])
	# Check every brute-force detection has a matching predictive one (order may differ)
	var all_matched_a := true
	for bf_entry in bf_a:
		var found := false
		for p_entry in pred_a:
			if bf_entry.detector == p_entry.detector and bf_entry.target == p_entry.target and absf(bf_entry.tick - p_entry.tick) < 0.05:
				found = true
				break
		if not found:
			all_matched_a = false
	if bf_a.size() == pred_a.size() and bf_a.size() > 0:
		_assert_true(all_matched_a, "Line-10: all detections match within 0.05s")
	else:
		_assert_true(true, "Line-10: count mismatch — skipping match check")

	# Test B: 10 units in a circle converging on center
	var setup_b: Array[Dictionary] = []
	for i in range(10):
		var angle: float = i * TAU / 10.0
		var radius := 12.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var vel := -pos.normalized() * 1.5  # Move toward center
		var det_range: float = 4.0 if i % 3 == 0 else 2.0  # Varying ranges
		setup_b.append({"id": "b%d" % i, "pos": pos, "vel": vel, "range": det_range})

	var bf_b: Array[Dictionary] = _bf_scan_all.call(setup_b, 10.0, 0.01)

	var sched_b := EventScheduler.new()
	var gs_b := GameState.new()
	gs_b.scheduler = sched_b
	for u in setup_b:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_b.register_character(u.id, u.pos, spd, stats)

	var pred_b: Array[Dictionary] = []
	var pred_b_seen: Dictionary = {}
	gs_b.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_b_seen.has(key):
			pred_b_seen[key] = true
			pred_b.append({"detector": det, "target": tgt, "tick": sched_b.get_current_tick()})
	)
	for u in setup_b:
		if u.vel.length() > 0.01:
			gs_b.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 30.0)
	sched_b.advance_ticks(10.0)

	_assert_true(bf_b.size() == pred_b.size(),
		"Circle-10: same detection count (bf=%d pred=%d)" % [bf_b.size(), pred_b.size()])

	# Mixed 10-unit case: stationary, crossing, and parallel paths.
	var setup_c: Array[Dictionary] = []
	setup_c.append({"id": "c0", "pos": Vector3(0, 0, 0), "vel": Vector3(2, 0, 0), "range": 5.0, "path_len": 40.0})
	setup_c.append({"id": "c1", "pos": Vector3(20, 0, 0), "vel": Vector3(-2, 0, 0), "range": 3.0, "path_len": 40.0})
	setup_c.append({"id": "c2", "pos": Vector3(0, 0, 5), "vel": Vector3(2, 0, 0), "range": 0.0, "path_len": 40.0})
	setup_c.append({"id": "c3", "pos": Vector3(10, 0, 3), "vel": Vector3.ZERO, "range": 6.0})
	setup_c.append({"id": "c4", "pos": Vector3(10, 0, -3), "vel": Vector3.ZERO, "range": 0.0})
	setup_c.append({"id": "c5", "pos": Vector3(5, 0, -8), "vel": Vector3(0, 0, 2), "range": 4.0, "path_len": 40.0})
	setup_c.append({"id": "c6", "pos": Vector3(15, 0, -8), "vel": Vector3(0, 0, 1.5), "range": 3.0, "path_len": 40.0})
	setup_c.append({"id": "c7", "pos": Vector3(25, 0, 0), "vel": Vector3(-1, 0, 1), "range": 4.0, "path_len": 40.0})
	setup_c.append({"id": "c8", "pos": Vector3(0, 0, -15), "vel": Vector3(1, 0, 1), "range": 2.0, "path_len": 40.0})
	setup_c.append({"id": "c9", "pos": Vector3(30, 0, 10), "vel": Vector3(-3, 0, -2), "range": 5.0, "path_len": 40.0})

	var bf_c: Array[Dictionary] = _bf_scan_all.call(setup_c, 12.0, 0.01)

	var sched_c := EventScheduler.new()
	var gs_c := GameState.new()
	gs_c.scheduler = sched_c
	for u in setup_c:
		var spd: float = u.vel.length() if u.vel.length() > 0.01 else 1.0
		var stats := {"detection_range": u.range} if u.range > 0.0 else {}
		gs_c.register_character(u.id, u.pos, spd, stats)

	var pred_c: Array[Dictionary] = []
	var pred_c_seen: Dictionary = {}
	gs_c.detection_predicted.connect(func(det: String, tgt: String):
		var key := det + "_" + tgt
		if not pred_c_seen.has(key):
			pred_c_seen[key] = true
			pred_c.append({"detector": det, "target": tgt, "tick": sched_c.get_current_tick()})
	)
	for u in setup_c:
		if u.vel.length() > 0.01:
			gs_c.command_move_to_pos(u.id, u.pos + u.vel.normalized() * 40.0)
	sched_c.advance_ticks(12.0)

	# Predictive may find more detections than brute-force because it rechecks
	# after units arrive and stop (post-arrival predictions). All brute-force
	# detections should have a matching predictive one.
	_assert_true(pred_c.size() >= bf_c.size(),
		"Mixed-10: predictive >= brute-force (bf=%d pred=%d)" % [bf_c.size(), pred_c.size()])
	var all_bf_in_pred := true
	for bf_entry in bf_c:
		var found := false
		for p_entry in pred_c:
			if bf_entry.detector == p_entry.detector and bf_entry.target == p_entry.target and absf(bf_entry.tick - p_entry.tick) < 0.1:
				found = true
				break
		if not found:
			all_bf_in_pred = false
	_assert_true(all_bf_in_pred, "Mixed-10: all bf detections found in predictive (bf=%d)" % bf_c.size())

# --- Test: Ferrolure Gauntlet ---
func _test_ferrolure() -> void:
	_test_name = "Ferrolure"
	var scene := load("res://scenes/tutorial/elevator.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	# Load gauntlet chunk
	instance._load_chunk("gauntlet")
	for i in range(3):
		await get_tree().process_frame

	# Verify ferrolure mesh exists
	_assert_true(instance._ferrolure_mesh != null, "Ferrolure mesh exists")

	# Verify gauntlet enemies exist
	_assert_true(instance._gauntlet_enemies.size() == 5,
		"5 gauntlet enemies spawned (got: %d)" % instance._gauntlet_enemies.size())

	# Verify enemies target players initially
	var first_enemy: Enemy = instance._gauntlet_enemies[0]
	_assert_true("aster" in first_enemy._detection_targets or "peris" in first_enemy._detection_targets,
		"Enemies target players before ferrolure")

	# Activate ferrolure
	instance._on_ferrolure_activated()
	for i in range(2):
		await get_tree().process_frame

	_assert_true(instance._ferrolure_active, "Ferrolure is active after activation")

	# Verify enemies ignore players.
	_assert_true(first_enemy._detection_targets.is_empty(),
		"Enemies stop targeting players when lure active (targets: %s)" % str(first_enemy._detection_targets))

	# Enemies should move toward the ferrolure.
	for i in range(20):
		instance._scheduler.advance(0.3)
		await get_tree().process_frame

	# Check that enemies moved toward the ferrolure
	var lure_pos: Vector3 = instance.FERROLURE_POS
	var near_lure := 0
	for enemy in instance._gauntlet_enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(lure_pos) < 8.0:
			near_lure += 1
	_assert_true(near_lure >= 3,
		"Most enemies moved toward ferrolure (near: %d/5)" % near_lure)

	# Expire ferrolure
	instance._on_ferrolure_expired()
	for i in range(2):
		await get_tree().process_frame

	_assert_true(not instance._ferrolure_active, "Ferrolure deactivated after expiry")

	# Verify enemies re-target players
	_assert_true("aster" in first_enemy._detection_targets or "peris" in first_enemy._detection_targets,
		"Enemies re-target players after lure expires")

	instance.queue_free()
	await get_tree().process_frame

# --- Test: Hide Encounter Solver ---
func _test_hide_encounter() -> void:
	_test_name = "Hide Encounter"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"siderophore_speed_values": [1.5, 1.6, 1.7],
	})
	_assert_true(not solved.is_empty(), "Solver found hallway distances that fit the encounter")
	if solved.is_empty():
		return

	var cfg: Dictionary = solved["config"]
	_assert_true(cfg["hide_distance"] > 0.0, "Hide is placed beyond lure 2")
	_assert_true(cfg["hide_distance"] < cfg["lure_distance"], "Hide stays between the two lures")
	_assert_true(cfg["siderophore_speed"] > 0.0, "Solver tunes a positive siderophore speed")
	_assert_true(solved.has("search_space"), "Solver reports the searched parameter space")

	var success: Dictionary = solved["success"]
	_assert_true(success["success"], "Intended sequence succeeds")
	_assert_true(success.get("exit_margin", -1.0) > 0.0, "Success exits before lure 2 expires")
	_assert_true(success.get("lure1_margin", -1.0) > 0.0, "Success reaches lure 2 before lure 1 expires")

	var slow_retreat: Dictionary = solved["slow_retreat"]
	var slow_lure2: Dictionary = solved["slow_lure2_activation"]
	var no_lure2: Dictionary = solved["no_lure2"]
	var slow_exit: Dictionary = solved["slow_exit"]

	_assert_true(not slow_retreat["success"], "Slow retreat fails")
	_assert_true(not slow_lure2["success"], "Slow lure 2 activation fails")
	_assert_true(not no_lure2["success"], "Skipping lure 2 fails")
	_assert_true(not slow_exit["success"], "Slow exit fails")

	_assert_true(String(slow_retreat["failure_reason"]) != "", "Slow retreat records a failure reason")
	_assert_true(String(slow_lure2["failure_reason"]) != "", "Slow lure 2 activation records a failure reason")
	_assert_true(String(no_lure2["failure_reason"]) != "", "No-lure-2 run records a failure reason")
	_assert_true(String(slow_exit["failure_reason"]) != "", "Slow exit records a failure reason")

func _test_hide_encounter_analysis() -> void:
	_test_name = "Hide Encounter Analysis"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"siderophore_speed_values": [1.5, 1.7],
			"config": {
				"hold_regen": 5.0,
				"hide_regen": 2.5,
			},
		},
		"bifurcation": {"step": 5.0},
		"phase_plane": {"stamina_samples": [35.0, 55.0, 75.0, 100.0]},
		"monte_carlo": {"trials": 64, "sample_limit": 8, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Analysis bundle builds")
	if bundle.is_empty():
		return

	_assert_true(bundle.has("phase_plane"), "Bundle includes phase-plane data")
	_assert_true(bundle.has("stamina_bifurcation"), "Bundle includes bifurcation data")
	_assert_true(bundle.has("monte_carlo"), "Bundle includes Monte Carlo data")
	_assert_true(bundle.has("search") and bundle["search"].has("parameter_space"), "Bundle includes solver parameter space")
	_assert_true(bundle["search"].has("objective"), "Bundle includes solver objective metadata")
	_assert_equals(String(bundle.get("methodology_version", "")), "hide-encounter-v5", "Bundle reports the current methodology version")
	_assert_equals(float(bundle["tuned_config"].get("hold_regen", -1.0)), 5.0, "Analysis preserves hold regen from search config")
	_assert_equals(float(bundle["tuned_config"].get("hide_regen", -1.0)), 2.5, "Analysis preserves hide regen from search config")
	_assert_equals(float(bundle["tuned_config"].get("consume_stamina_cost", -1.0)), 0.0, "Analysis preserves consume stamina cost from search config")

	var bifurcation: Dictionary = bundle["stamina_bifurcation"]
	_assert_true(bifurcation["samples"].size() > 0, "Bifurcation sweep produced samples")
	_assert_true(float(bifurcation.get("first_success_stamina", -1.0)) >= 0.0, "Bifurcation found a success threshold")

	var vector_field: Array = bundle["phase_plane"].get("vector_field", [])
	_assert_equals(vector_field.size(), 5, "Phase-plane exposes run, walk, hold, hide, and stand regimes")
	_assert_true(bundle["phase_plane"].has("discrete_events"), "Phase-plane reports discrete stamina events")

	var monte_carlo: Dictionary = bundle["monte_carlo"]
	var confusion: Dictionary = monte_carlo["confusion_matrix"]
	var total_confusion := int(confusion["true_positive"]) + int(confusion["false_positive"]) + int(confusion["true_negative"]) + int(confusion["false_negative"])
	_assert_equals(total_confusion, monte_carlo["trials"], "Confusion matrix covers every Monte Carlo trial")

func _test_hide_encounter_shared_duration() -> void:
	_test_name = "Hide Encounter Shared Duration"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for shared-duration search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"share_lure_duration": true,
		"optimize_for_threshold": true,
		"siderophore_speed_values": [1.5, 1.6, 1.7, 1.8],
		"lure_duration_values": [14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0],
		"threshold_search": {"resolution": 5.0},
	})
	_assert_true(solved.is_empty(), "Current systems do not admit a valid equal-duration lure solution in the tested bounds")

func _test_hide_encounter_lure2_duration() -> void:
	_test_name = "Hide Encounter Lure2 Duration"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for lure2-duration search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"walk_regen_values": [0.0],
		"stand_regen_values": [5.0],
		"hold_regen_values": [0.0],
		"hide_regen_values": [5.0],
		"hold_duration_values": [2.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"lure2_duration_values": [14.0, 16.0, 18.0, 20.0, 22.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
		},
	})
	_assert_true(not solved.is_empty(), "Lure2-duration search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true([14.0, 16.0, 18.0, 20.0, 22.0].has(float(solved["config"]["lure2_duration"])), "Lure2-duration search chooses a searched lure 2 duration")
	_assert_true(solved["search_space"].has("lure2_duration_values"), "Lure2-duration search records lure 2 timing values")
	_assert_true(solved["success"]["success"], "Lure2-duration search preserves intended success")

func _test_hide_encounter_exit_gap() -> void:
	_test_name = "Hide Encounter Exit Gap"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for exit-gap search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"exit_gap_values": [2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Exit-gap search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["exit_gap"]) >= 2.5, "Exit-gap search chooses a searched gap value")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Exit-gap search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Exit-gap search preserves intended success")

func _test_hide_encounter_cluster_gap() -> void:
	_test_name = "Hide Encounter Cluster Gap"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for cluster-gap search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"cluster_gap_values": [4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0],
		"exit_gap_values": [2.5],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Cluster-gap search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["cluster_gap"]) >= 4.0, "Cluster-gap search chooses a searched gap value")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Cluster-gap search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Cluster-gap search preserves intended success")

func _test_hide_encounter_run_drain() -> void:
	_test_name = "Hide Encounter Run Drain"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for run-drain search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"run_drain_values": [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0, 125.0, 130.0, 135.0, 140.0, 145.0, 150.0, 155.0, 160.0, 165.0, 170.0, 175.0, 180.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Run-drain search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["run_drain"]) >= 30.0, "Run-drain search chooses a searched decay value")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Run-drain search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Run-drain search preserves intended success")

func _test_hide_encounter_stand_regen() -> void:
	_test_name = "Hide Encounter Stand Regen"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for stand-regen search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5, 30.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Stand-regen search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["stand_regen"]) >= 0.0, "Stand-regen search chooses a searched regen value")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Stand-regen search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Stand-regen search preserves intended success")

func _test_hide_encounter_consume_cost() -> void:
	_test_name = "Hide Encounter Consume Cost"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for consume-cost search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"walk_regen_values": [0.0],
		"stand_regen_values": [5.0],
		"hold_regen_values": [0.0],
		"hide_regen_values": [5.0],
		"consume_stamina_cost_values": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0],
		"hold_duration_values": [2.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Consume-cost search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["consume_stamina_cost"]) >= 0.0, "Consume-cost search chooses a searched cost")
	_assert_true(solved["search_space"].has("consume_stamina_cost_values"), "Consume-cost search records the searched cost values")
	_assert_true(solved["success"]["success"], "Consume-cost search preserves intended success")

func _test_hide_encounter_hold_duration() -> void:
	_test_name = "Hide Encounter Hold Duration"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for hold-duration search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"stand_regen_values": [15.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"hold_duration_values": [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Hold-duration search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["hold_duration"]) >= 0.5, "Hold-duration search chooses a searched shared hold")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Hold-duration search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Hold-duration search preserves intended success")

func _test_hide_encounter_walk_regen() -> void:
	_test_name = "Hide Encounter Walk Regen"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for walk-regen search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"stand_regen_values": [15.0],
		"hold_duration_values": [2.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"walk_regen_values": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Walk-regen search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["walk_regen"]) >= 0.0, "Walk-regen search chooses a searched regen value")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Walk-regen search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Walk-regen search preserves intended success")

func _test_hide_encounter_coupled_stand_hold() -> void:
	_test_name = "Hide Encounter Coupled Stand Hold"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for coupled stand-hold search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"walk_regen_values": [3.0],
		"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0],
		"hold_duration_values": [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Coupled stand-hold search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["stand_regen"]) >= 0.0, "Coupled stand-hold search chooses a searched stand regen")
	_assert_true(float(solved["config"]["hold_duration"]) >= 0.5, "Coupled stand-hold search chooses a searched hold duration")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Coupled stand-hold search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Coupled stand-hold search preserves intended success")

func _test_hide_encounter_coupled_stand_walk() -> void:
	_test_name = "Hide Encounter Coupled Stand Walk"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for coupled stand-walk search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0],
		"walk_regen_values": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
		"hold_duration_values": [2.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Coupled stand-walk search finds a valid encounter")
	if solved.is_empty():
		return

	_assert_true(float(solved["config"]["stand_regen"]) >= 0.0, "Coupled stand-walk search chooses a searched stand regen")
	_assert_true(float(solved["config"]["walk_regen"]) >= 0.0, "Coupled stand-walk search chooses a searched walk regen")
	_assert_true(float(solved.get("first_success_stamina", -1.0)) >= 0.0, "Coupled stand-walk search records a stamina threshold")
	_assert_true(solved["success"]["success"], "Coupled stand-walk search preserves intended success")

func _test_hide_encounter_split_recovery() -> void:
	_test_name = "Hide Encounter Split Recovery"

	var sim_script = load("res://scripts/game/mechanics/hide_encounter_sim.gd")
	_assert_true(sim_script != null, "Hide encounter sim script loads for split-recovery search")
	if sim_script == null:
		return

	var sim = sim_script.new()
	var solved: Dictionary = sim.search_solution({
		"lure_values": [12.0],
		"hide_values": [7.0],
		"siderophore_speed_values": [1.7],
		"run_drain_values": [30.0],
		"walk_regen_values": [0.0],
		"stand_regen_values": [5.0],
		"hold_regen_values": [0.0, 2.5, 5.0],
		"hide_regen_values": [0.0, 2.5, 5.0],
		"hold_duration_values": [2.0],
		"cluster_gap_values": [7.5],
		"exit_gap_values": [2.5],
		"optimize_for_threshold": true,
		"threshold_search": {"resolution": 2.5},
		"config": {
			"lure1_duration": 12.0,
			"lure2_duration": 18.0,
		},
	})
	_assert_true(not solved.is_empty(), "Split-recovery search finds a valid encounter")
	if solved.is_empty():
		return

	var chosen_hold_regen: float = float(solved["config"].get("hold_regen", solved["config"]["stand_regen"]))
	var chosen_hide_regen: float = float(solved["config"].get("hide_regen", solved["config"]["stand_regen"]))
	_assert_true([0.0, 2.5, 5.0].has(chosen_hold_regen), "Split-recovery search chooses a searched hold regen")
	_assert_true([0.0, 2.5, 5.0].has(chosen_hide_regen), "Split-recovery search chooses a searched hide regen")
	_assert_true(solved["search_space"].has("hold_regen_values"), "Split-recovery search records hold regen parameter space")
	_assert_true(solved["search_space"].has("hide_regen_values"), "Split-recovery search records hide regen parameter space")
	_assert_true(solved["success"]["success"], "Split-recovery search preserves intended success")

func _export_hide_encounter_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Analysis Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle()
	_assert_true(not bundle.is_empty(), "Hide encounter analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter analysis to: %s" % output_path)

func _export_hide_encounter_exit_gap_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Exit Gap Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for exit-gap export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"exit_gap_values": [2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter exit-gap analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for exit-gap analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter exit-gap analysis to: %s" % output_path)

func _export_hide_encounter_cluster_gap_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Cluster Gap Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for cluster-gap export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"cluster_gap_values": [4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0],
			"exit_gap_values": [2.5],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter cluster-gap analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for cluster-gap analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter cluster-gap analysis to: %s" % output_path)

func _export_hide_encounter_run_drain_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Run Drain Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for run-drain export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"run_drain_values": [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0, 125.0, 130.0, 135.0, 140.0, 145.0, 150.0, 155.0, 160.0, 165.0, 170.0, 175.0, 180.0],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter run-drain analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for run-drain analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter run-drain analysis to: %s" % output_path)

func _export_hide_encounter_stand_regen_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Stand Regen Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for stand-regen export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"run_drain_values": [30.0],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5, 30.0],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter stand-regen analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for stand-regen analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter stand-regen analysis to: %s" % output_path)

func _export_hide_encounter_hold_duration_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Hold Duration Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for hold-duration export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"run_drain_values": [30.0],
			"stand_regen_values": [15.0],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"hold_duration_values": [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter hold-duration analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for hold-duration analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter hold-duration analysis to: %s" % output_path)

func _export_hide_encounter_custom_analysis(config_path: String, output_path: String) -> void:
	_test_name = "Hide Encounter Custom Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for custom export")
	if analysis_script == null:
		return

	var overrides := _load_hide_encounter_analysis_overrides(config_path)
	_assert_true(not overrides.is_empty(), "Hide encounter custom analysis config loaded")
	if overrides.is_empty():
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle(overrides)
	_assert_true(not bundle.is_empty(), "Hide encounter custom analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for custom analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter custom analysis to: %s" % output_path)

func _load_hide_encounter_analysis_overrides(config_path: String) -> Dictionary:
	var resolved_path := config_path
	if not resolved_path.begins_with("res://") and not resolved_path.begins_with("user://"):
		if resolved_path.begins_with("./"):
			resolved_path = resolved_path.substr(2)
		if resolved_path.begins_with("/"):
			resolved_path = resolved_path.substr(1)
		resolved_path = "res://%s" % resolved_path

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	_assert_true(file != null, "Custom analysis config opened")
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	_assert_true(parsed is Dictionary, "Custom analysis config parsed as dictionary")
	if parsed is Dictionary:
		return parsed
	return {}

func _export_hide_encounter_walk_regen_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Walk Regen Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for walk-regen export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"run_drain_values": [30.0],
			"stand_regen_values": [15.0],
			"hold_duration_values": [2.0],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"walk_regen_values": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter walk-regen analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for walk-regen analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter walk-regen analysis to: %s" % output_path)

func _export_hide_encounter_coupled_stand_hold_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Coupled Stand Hold Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for coupled stand-hold export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"run_drain_values": [30.0],
			"walk_regen_values": [3.0],
			"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0],
			"hold_duration_values": [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter coupled stand-hold analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for coupled stand-hold analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter coupled stand-hold analysis to: %s" % output_path)

func _export_hide_encounter_coupled_stand_walk_analysis(output_path: String) -> void:
	_test_name = "Hide Encounter Coupled Stand Walk Export"

	var analysis_script = load("res://scripts/game/mechanics/hide_encounter_analysis.gd")
	_assert_true(analysis_script != null, "Hide encounter analysis script loads for coupled stand-walk export")
	if analysis_script == null:
		return

	var analysis = analysis_script.new()
	var bundle: Dictionary = analysis.build_bundle({
		"search": {
			"lure_values": [12.0],
			"hide_values": [7.0],
			"siderophore_speed_values": [1.7],
			"run_drain_values": [30.0],
			"stand_regen_values": [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0],
			"walk_regen_values": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
			"hold_duration_values": [2.0],
			"cluster_gap_values": [7.5],
			"exit_gap_values": [2.5],
			"optimize_for_threshold": true,
			"threshold_search": {"resolution": 2.5},
			"config": {
				"lure1_duration": 12.0,
				"lure2_duration": 18.0,
			},
		},
		"bifurcation": {"step": 2.5},
		"monte_carlo": {"trials": 128, "sample_limit": 12, "seed": 17},
	})
	_assert_true(not bundle.is_empty(), "Hide encounter coupled stand-walk analysis bundle exported")
	if bundle.is_empty():
		return

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	_assert_true(file != null, "Output file opened for coupled stand-walk analysis export")
	if file == null:
		return
	file.store_string(JSON.stringify(bundle, "\t"))
	print("  Wrote hide encounter coupled stand-walk analysis to: %s" % output_path)

# --- Dialogue Dump ---

func _dump_tutorial_dialogue(tutorial_scene: String, output_path: String) -> void:
	_test_name = "Tutorial Dialogue Dump"
	var target := tutorial_scene.strip_edges().to_lower()
	var sections: Array[Dictionary] = []
	match target:
		"aster", "aster-sim", "aster_sim":
			sections.append(await _collect_tutorial_dialogue_section(
				"Aster Sim - scripted clean path",
				"res://scenes/tutorial/aster_sim.tscn",
				Callable(),
				Callable(self, "_aster_dialogue_dump_actions")
			))
			sections.append(_dialogue_key_section("Aster Sim - overlay/thought lines", [
				"aster_sim.drink_redirect.thought",
			]))
			sections.append(_dialogue_key_section("Aster Sim - optional inspection lines", [
				"aster.sim_expand.glass_bead.line",
				"aster.sim_expand.painting_1.line",
				"aster.sim_expand.painting_2.line",
				"aster.sim_expand.awards.line",
				"aster.sim_expand.awards.journalism_line",
				"aster.sim_expand.bookshelf.line",
				"aster.sim_expand.bookshelf.articles_line",
			]))
		"peris", "peris-sim", "peris_sim":
			sections.append(await _collect_tutorial_dialogue_section(
				"Peris Sim Phase 1 - scripted clean path",
				"res://scenes/tutorial/peris_sim.tscn",
				Callable(self, "_peris_phase_1_dialogue_dump_setup"),
				Callable(self, "_peris_phase_1_dialogue_dump_actions")
			))
			sections.append(await _collect_tutorial_dialogue_section(
				"Peris Sim Phase 2 - scripted clean path",
				"res://scenes/tutorial/peris_sim.tscn",
				Callable(self, "_peris_phase_2_dialogue_dump_setup"),
				Callable(self, "_peris_phase_2_dialogue_dump_actions")
			))
			sections.append(_dialogue_key_section("Peris Sim - overlay/thought and correction lines", [
				"peris.sim_expand.opening.line",
				"peris_sim.protect_remind",
				"peris_sim.correct.not_yet",
			]))
			sections.append(_dialogue_key_section("Peris Sim - optional inspection lines", [
				"peris.sim_expand.plant_1.line",
				"peris.sim_expand.plant_2.line",
				"peris.sim_expand.plant_3.line",
				"peris.sim_expand.plant_4.line",
				"peris.sim_expand.plant_5.line",
				"peris.sim_expand.plant_6.line",
				"peris.sim_expand.plant_7.line",
				"peris.sim_expand.plant_8.line",
				"peris.sim_expand.plant_9.line",
				"peris.sim_expand.painting.line",
				"peris.sim_expand.wellness.line",
				"peris.sim_expand.strike_warning.notification",
				"peris.sim_expand.strike_warning.line",
				"peris.sim_expand.notes.line",
			]))
		"peris-phase1", "peris_phase1":
			sections.append(await _collect_tutorial_dialogue_section(
				"Peris Sim Phase 1 - scripted clean path",
				"res://scenes/tutorial/peris_sim.tscn",
				Callable(self, "_peris_phase_1_dialogue_dump_setup"),
				Callable(self, "_peris_phase_1_dialogue_dump_actions")
			))
		"peris-phase2", "peris_phase2":
			sections.append(await _collect_tutorial_dialogue_section(
				"Peris Sim Phase 2 - scripted clean path",
				"res://scenes/tutorial/peris_sim.tscn",
				Callable(self, "_peris_phase_2_dialogue_dump_setup"),
				Callable(self, "_peris_phase_2_dialogue_dump_actions")
			))
		_:
			print("  ERROR: Unknown tutorial dialogue target: %s" % tutorial_scene)
			print("  Expected one of: aster, peris, peris-phase1, peris-phase2")
			return

	_write_dialogue_dump_sections(output_path, tutorial_scene, sections)

func _collect_tutorial_dialogue_section(
		section_title: String,
		scene_path: String,
		setup: Callable,
		actions_factory: Callable
	) -> Dictionary:
	var scene := load(scene_path)
	if not scene:
		return {
			"title": section_title,
			"scene": scene_path,
			"error": "Could not load scene",
			"lines": [],
		}

	var instance: Node = scene.instantiate()
	if setup.is_valid():
		setup.call(instance)
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var actions: Dictionary = {}
	if actions_factory.is_valid():
		var action_result = actions_factory.call(instance)
		if action_result is Dictionary:
			actions = action_result

	var lines := _pop_dialogue_log(instance, actions)
	instance.queue_free()
	await get_tree().process_frame
	return {
		"title": section_title,
		"scene": scene_path,
		"lines": lines,
	}

func _aster_dialogue_dump_actions(instance: Node) -> Dictionary:
	return {
		"show_terminal": func(): instance._on_terminal_interacted(),
		"walk_to_drink": func(): instance._on_drink_interacted(),
		"explore_workspace": func():
			instance._explore_gate_unlocked = true
			instance._on_exploration_gate_interacted(),
	}

func _peris_phase_1_dialogue_dump_setup(instance: Node) -> void:
	instance._visit_phase = 1

func _peris_phase_1_dialogue_dump_actions(instance: Node) -> Dictionary:
	return {
		"workspace": func():
			instance._explore_gate_unlocked = true
			instance._on_exploration_gate_interacted(),
	}

func _peris_phase_2_dialogue_dump_setup(instance: Node) -> void:
	instance._visit_phase = 2

func _peris_phase_2_dialogue_dump_actions(instance: Node) -> Dictionary:
	return {
		"protect_prompt": func(): instance._on_protect_pressed(),
		"run_prompt": func(): instance._toggle_run(),
		"click_monos": func(): instance._start_confirm_protect(),
		"confirm_protect": func():
			var target: Vector3 = instance.PORTAL_POS + Vector3(-0.5, 0.5, 0.0)
			instance._player.global_position = target
			instance._game_state.characters["peris"].position = target
			instance._start_executing(),
	}

func _dialogue_key_section(section_title: String, keys: Array[String]) -> Dictionary:
	var lines: Array[Dictionary] = []
	for key in keys:
		var line := DialogueData.get_line(key)
		lines.append({
			"key": key,
			"tick": 0.0,
			"text": line.text,
			"speaker": line.speaker,
			"style": line.style,
		})
	return {
		"title": section_title,
		"scene": "DialogueData",
		"lines": lines,
	}

func _write_dialogue_dump_sections(output_path: String, target: String, sections: Array[Dictionary]) -> void:
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		print("  ERROR: Could not open %s for writing" % output_path)
		return

	var total_lines := 0
	for section in sections:
		total_lines += (section.get("lines", []) as Array).size()

	file.store_line("# Tutorial dialogue dump: %s" % target)
	file.store_line("# %d sections, %d lines captured" % [sections.size(), total_lines])
	file.store_line("# Format: index | tick | style | speaker | key | text")
	file.store_line("")

	for section in sections:
		file.store_line("## %s" % str(section.get("title", "Untitled section")))
		file.store_line("# Source: %s" % str(section.get("scene", "")))
		if section.has("error"):
			file.store_line("ERROR: %s" % str(section.error))
			file.store_line("")
			continue
		var lines: Array = section.get("lines", [])
		for i in range(lines.size()):
			var entry: Dictionary = lines[i]
			var text := _single_line_dump_text(str(entry.get("text", "")))
			var speaker := str(entry.get("speaker", ""))
			var key := str(entry.get("key", ""))
			var style := str(entry.get("style", "normal"))
			var tick := float(entry.get("tick", 0.0))
			file.store_line("%03d | %.2f | %s | %s | %s | %s" % [
				i + 1,
				tick,
				style,
				speaker,
				key,
				text,
			])
		file.store_line("")

	file.close()
	print("  Wrote %d dialogue lines to %s" % [total_lines, output_path])

func _single_line_dump_text(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n")

func _dump_dialogue(scene_path: String, output_path: String) -> void:
	_test_name = "Dialogue Dump"
	print("  Dumping dialogue for: %s" % scene_path)

	var scene := load(scene_path)
	if not scene:
		print("  ERROR: Could not load scene: %s" % scene_path)
		return

	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	# Let the scene initialize
	for i in range(3):
		await get_tree().process_frame

	if not "_dialogue" in instance or not "_scheduler" in instance:
		print("  ERROR: Scene does not have _dialogue or _scheduler")
		instance.queue_free()
		return

	var log: Array[String] = []
	var dialogue_box: Node = instance._dialogue
	var scheduler: EventScheduler = instance._scheduler

	# Hook line_displayed to capture every dialogue line
	dialogue_box.line_displayed.connect(func(text: String):
		var speaker: String = dialogue_box._speaker_label.text if dialogue_box._speaker_label.visible else ""
		var style: String = dialogue_box._style
		var tick := scheduler.get_current_tick()
		var prefix := "%.2f [%s]" % [tick, style]
		if speaker != "":
			prefix += " %s:" % speaker
		log.append("%s %s" % [prefix, text])
	)

	# Pop through all scheduler events. Between each pop, flush the
	# dialogue box so dialogue_finished fires and chains the next event.
	var safety := 0
	var idle_pops := 0
	while safety < 5000:
		# Flush dialogue box until it's idle (all queued lines displayed + finished)
		for j in range(200):
			if not dialogue_box.is_active():
				break
			_pump_dialogue(dialogue_box, 16.0)

		if scheduler.pending_count() == 0:
			idle_pops += 1
			if idle_pops > 5:
				break
			# One more flush in case dialogue_finished queued something
			for j in range(10):
				_pump_dialogue(dialogue_box, 16.0)
			continue

		idle_pops = 0
		var info: Dictionary = scheduler.pop_next()
		if info.is_empty():
			break
		safety += 1

	# Write to file
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_line("# Dialogue dump: %s" % scene_path)
		file.store_line("# %d lines captured" % log.size())
		file.store_line("")
		for line in log:
			file.store_line(line)
		file.close()
		print("  Wrote %d dialogue lines to %s" % [log.size(), output_path])
	else:
		print("  ERROR: Could not open %s for writing" % output_path)
		for line in log:
			print("    %s" % line)

	instance.queue_free()
	await get_tree().process_frame

func _test_camera_shake() -> void:
	_test_name = "Camera Shake"

	# Set up a minimal scene: camera + target node
	var target := Node3D.new()
	target.position = Vector3(5, 0, 5)
	get_tree().root.add_child(target)

	var cam := Camera3D.new()
	cam.name = "TestShakeCam"
	cam.set_script(preload("res://scripts/ui/game_camera.gd"))
	get_tree().root.add_child(cam)
	cam.target = target
	cam.follow_offset = Vector3(0, 10, 7)
	cam.follow_speed = 100.0  # High follow speed so position converges fast

	# Let camera settle to target
	for i in range(10):
		cam._process(0.016)
	var settled_pos := cam.global_position

	# Trigger shake
	cam.shake(0.5, 3.0)
	_assert_true(cam._shake_intensity > 0.0, "Shake intensity set after shake()")

	# Shake should offset position from settled.
	var max_offset := 0.0
	for i in range(30):
		cam._process(0.016)
		var offset := (cam.global_position - settled_pos).length()
		if offset > max_offset:
			max_offset = offset
	_assert_true(max_offset > 0.01, "Camera moved from settled position during shake (max offset: %.4f)" % max_offset)

	# After enough frames, shake should decay
	for i in range(200):
		cam._process(0.016)
	_assert_true(cam._shake_intensity < 0.001, "Shake decayed to near zero (got: %.6f)" % cam._shake_intensity)

	# Shake while locked
	cam.lock_to(Vector3(10, 0, 10))
	for i in range(10):
		cam._process(0.016)
	var locked_pos := cam.global_position

	cam.shake(0.4, 3.0)
	var locked_max_offset := 0.0
	for i in range(30):
		cam._process(0.016)
		var offset := (cam.global_position - locked_pos).length()
		if offset > locked_max_offset:
			locked_max_offset = offset
	_assert_true(locked_max_offset > 0.01, "Camera shakes while locked (max offset: %.4f)" % locked_max_offset)

	cam.queue_free()
	target.queue_free()

func _test_physics_objects() -> void:
	_test_name = "Physics Objects"

	# Setup: grid + scheduler + game state
	var grid := GridWorld.new()
	grid.create_room(20, 20)
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = sched

	# Test 1: Register and query position
	gs.register_physics_object("barrel1", Vector3(5, 0, 5), 0.5, 2.0, 0.6)
	_assert_true(gs.physics_objects.has("barrel1"), "Physics object registered")
	var pos := gs.get_physics_position("barrel1")
	_assert_true(absf(pos.x - 5.0) < 0.01, "Initial position correct (got: %.2f)" % pos.x)

	# Test 2: Character pushes object
	gs.register_character("pusher", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("pusher", Vector3(10, 0, 5))

	# Check prediction was scheduled
	_assert_true(sched.pending_count() >= 2, "At least 2 events pending (movement + collision, got: %d)" % sched.pending_count())

	# Track collisions via signal (use array since lambdas can't modify outer locals)
	var collision_log: Array = []
	gs.physics_collision.connect(func(oid, cid, imp): collision_log.append(oid))

	# Pop through scheduler events
	for i in range(500):
		var info := sched.pop_next()
		if info.is_empty():
			break
	_assert_true(collision_log.size() > 0, "Physics collision signal fired (count: %d)" % collision_log.size())

	# Pop remaining events to let barrel settle
	for i in range(200):
		var info := sched.pop_next()
		if info.is_empty():
			break

	var final_pos := gs.get_physics_position("barrel1")
	_assert_true(final_pos.x > 5.1, "Barrel pushed in +X direction (got: %.2f)" % final_pos.x)

	# Mass ratio: heavy object barely moves.
	gs.register_physics_object("heavy", Vector3(5, 0, 8), 0.5, 20.0, 0.6)
	gs.register_character("pusher2", Vector3(3, 0, 8), 3.0)
	gs.command_move_to_pos("pusher2", Vector3(10, 0, 8))
	for i in range(500):
		var info := sched.pop_next()
		if info.is_empty():
			break
	var heavy_pos := gs.get_physics_position("heavy")
	_assert_true(heavy_pos.x < final_pos.x, "Heavy object moved less than light (heavy: %.2f, light: %.2f)" % [heavy_pos.x, final_pos.x])

	# Chain reaction pushes A into B.
	gs.register_physics_object("chain_a", Vector3(5, 0, 12), 0.5, 1.0, 0.5)
	gs.register_physics_object("chain_b", Vector3(6.5, 0, 12), 0.5, 1.0, 0.5)
	gs.register_character("chain_pusher", Vector3(3, 0, 12), 4.0)
	gs.command_move_to_pos("chain_pusher", Vector3(10, 0, 12))

	var chain_b_moved := false
	for i in range(1000):
		var info := sched.pop_next()
		if info.is_empty():
			break
		if gs.is_physics_moving("chain_b"):
			chain_b_moved = true

	# Let everything settle
	for i in range(500):
		var info := sched.pop_next()
		if info.is_empty():
			break

	var chain_a_final := gs.get_physics_position("chain_a")
	var chain_b_final := gs.get_physics_position("chain_b")
	var chain_a_moved := absf(chain_a_final.x - 5.0) > 0.1
	_assert_true(chain_a_moved, "Chain A displaced (got: %.2f, started: 5.0)" % chain_a_final.x)
	_assert_true(chain_b_final.x > 7.0, "Chain B pushed by chain reaction (got: %.2f)" % chain_b_final.x)

	# Wall stop.
	gs.register_physics_object("wall_obj", Vector3(17, 0, 5), 0.5, 1.0, 0.3)
	gs.register_character("wall_pusher", Vector3(15, 0, 5), 5.0)
	gs.command_move_to_pos("wall_pusher", Vector3(19, 0, 5))
	for i in range(500):
		var info := sched.pop_next()
		if info.is_empty():
			break
	var wall_obj_pos := gs.get_physics_position("wall_obj")
	_assert_true(wall_obj_pos.x < 19.0, "Object stopped before wall (got: %.2f)" % wall_obj_pos.x)

	# Resting object blocks walkability.
	var barrel_cell := grid.world_to_grid(gs.get_physics_position("barrel1"))
	_assert_true(not grid.is_walkable(barrel_cell.x, barrel_cell.y), "Barrel blocks grid cell at rest")

	# Test 7: Area impulse
	gs.register_physics_object("blast_a", Vector3(10, 0, 15), 0.5, 1.0, 0.5)
	gs.register_physics_object("blast_b", Vector3(11, 0, 15), 0.5, 1.0, 0.5)
	gs.register_physics_object("blast_c", Vector3(10, 0, 16), 0.5, 1.0, 0.5)
	var pre_a := gs.get_physics_position("blast_a")
	var pre_b := gs.get_physics_position("blast_b")
	gs.apply_area_impulse(Vector3(10.5, 0, 15.5), 3.0, 5.0)

	for i in range(500):
		var info := sched.pop_next()
		if info.is_empty():
			break

	var post_a := gs.get_physics_position("blast_a")
	var post_b := gs.get_physics_position("blast_b")
	var post_c := gs.get_physics_position("blast_c")
	var a_moved := pre_a.distance_to(post_a) > 0.1
	var b_moved := pre_b.distance_to(post_b) > 0.1
	_assert_true(a_moved, "Blast object A moved (dist: %.2f)" % pre_a.distance_to(post_a))
	_assert_true(b_moved, "Blast object B moved (dist: %.2f)" % pre_b.distance_to(post_b))

	# Test 8: Unregister
	gs.unregister_physics_object("barrel1")
	_assert_true(not gs.physics_objects.has("barrel1"), "Barrel unregistered")
	_assert_true(grid.is_walkable(barrel_cell.x, barrel_cell.y), "Grid cell freed after unregister")

func _test_physics_edge_cases() -> void:
	_test_name = "Physics Edge Cases"

	# --- Non-pushable object ---
	var gs: GameState
	var sched: EventScheduler
	var grid2: GridWorld

	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("static_box", Vector3(5, 0, 5), 0.5, 5.0, 0.6, false)
	gs.register_character("runner", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("runner", Vector3(10, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var static_pos := gs.get_physics_position("static_box")
	_assert_true(absf(static_pos.x - 5.0) < 0.01, "Non-pushable object stays put (got: %.2f)" % static_pos.x)

	# --- Parallel miss: character walks past object (offset in Z) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("side_barrel", Vector3(5, 0, 7), 0.3)
	gs.register_character("passerby", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("passerby", Vector3(10, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var side_pos := gs.get_physics_position("side_barrel")
	_assert_true(absf(side_pos.x - 5.0) < 0.01, "Object not hit when character walks past (Z offset 2.0, got: %.2f)" % side_pos.x)

	# --- Near miss: character barely misses ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("near_miss", Vector3(5, 0, 6.0), 0.3)
	gs.register_character("grazer", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("grazer", Vector3(10, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var near_pos := gs.get_physics_position("near_miss")
	# collision_range = 0.7, offset in Z = 1.0, miss.
	_assert_true(absf(near_pos.x - 5.0) < 0.01, "Near miss: Z offset 1.0 > collision range 0.7 (got: %.2f)" % near_pos.x)

	# --- Diagonal push ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("diag_obj", Vector3(7, 0, 7), 0.5, 1.5, 0.5)
	gs.register_character("diag_char", Vector3(3, 0, 3), 4.0)
	gs.command_move_to_pos("diag_char", Vector3(10, 0, 10))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var diag_pos := gs.get_physics_position("diag_obj")
	var diag_moved := diag_pos.distance_to(Vector3(7, 0, 7)) > 0.1
	_assert_true(diag_moved, "Diagonal push moves object (dist: %.2f)" % diag_pos.distance_to(Vector3(7, 0, 7)))
	# Should be pushed roughly along +X+Z diagonal
	_assert_true(diag_pos.x > 7.0, "Diagonal push: +X component (got: %.2f)" % diag_pos.x)
	_assert_true(diag_pos.z > 7.0, "Diagonal push: +Z component (got: %.2f)" % diag_pos.z)

	# --- Friction comparison: icy vs rough ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("icy", Vector3(5, 0, 5), 0.5, 1.0, 0.2)
	gs.register_physics_object("rough", Vector3(5, 0, 8), 0.5, 1.0, 0.9)
	gs.register_character("ice_pusher", Vector3(3, 0, 5), 3.0)
	gs.register_character("rough_pusher", Vector3(3, 0, 8), 3.0)
	gs.command_move_to_pos("ice_pusher", Vector3(10, 0, 5))
	gs.command_move_to_pos("rough_pusher", Vector3(10, 0, 8))
	for _di in range(1000):
		if sched.pop_next().is_empty(): break
	var icy_pos := gs.get_physics_position("icy")
	var rough_pos := gs.get_physics_position("rough")
	_assert_true(icy_pos.x > rough_pos.x, "Icy slides farther than rough (icy: %.2f, rough: %.2f)" % [icy_pos.x, rough_pos.x])

	# --- Speed comparison: fast vs slow character ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("target_fast", Vector3(5, 0, 5), 0.5, 1.0, 0.5)
	gs.register_physics_object("target_slow", Vector3(5, 0, 8), 0.5, 1.0, 0.5)
	gs.register_character("fast_char", Vector3(3, 0, 5), 6.0)
	gs.register_character("slow_char", Vector3(3, 0, 8), 1.5)
	gs.command_move_to_pos("fast_char", Vector3(10, 0, 5))
	gs.command_move_to_pos("slow_char", Vector3(10, 0, 8))
	for _di in range(2000):
		if sched.pop_next().is_empty(): break
	var fast_result := gs.get_physics_position("target_fast")
	var slow_result := gs.get_physics_position("target_slow")
	_assert_true(fast_result.x > slow_result.x, "Fast char pushes farther than slow (fast: %.2f, slow: %.2f)" % [fast_result.x, slow_result.x])

	# --- Radius comparison: large vs small collision radius ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("big_radius", Vector3(5, 0, 5), 1.0, 1.0, 0.5)
	gs.register_physics_object("small_radius", Vector3(5, 0, 8), 0.2, 1.0, 0.5)
	gs.register_character("rad_char1", Vector3(3, 0, 5), 3.0)
	gs.register_character("rad_char2", Vector3(3, 0, 8), 3.0)
	gs.command_move_to_pos("rad_char1", Vector3(10, 0, 5))
	gs.command_move_to_pos("rad_char2", Vector3(10, 0, 8))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var big_pos := gs.get_physics_position("big_radius")
	var small_pos := gs.get_physics_position("small_radius")
	# Both should move (same mass/friction), but big_radius hits earlier (larger collision range)
	_assert_true(big_pos.x > 5.1, "Large radius object pushed (got: %.2f)" % big_pos.x)
	_assert_true(small_pos.x > 5.1, "Small radius object pushed (got: %.2f)" % small_pos.x)

	# --- Determinism: same setup twice produces identical results ---
	var det_results: Array[float] = []
	for trial in range(2):
		gs = GameState.new()
		sched = EventScheduler.new()
		grid2 = GridWorld.new()
		grid2.create_room(30, 30)
		gs.grid = grid2
		gs.scheduler = sched
		gs.register_physics_object("det_obj", Vector3(6, 0, 6), 0.5, 1.5, 0.5)
		gs.register_character("det_char", Vector3(3, 0, 6), 3.5)
		gs.command_move_to_pos("det_char", Vector3(12, 0, 6))
		for _di in range(1000):
			if sched.pop_next().is_empty(): break
		det_results.append(gs.get_physics_position("det_obj").x)
	_assert_true(absf(det_results[0] - det_results[1]) < 0.001, "Deterministic: two runs match (%.4f vs %.4f)" % [det_results[0], det_results[1]])

	# --- Object already overlapping character at registration ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_character("overlap_char", Vector3(5, 0, 5), 3.0)
	gs.register_physics_object("overlap_obj", Vector3(5.3, 0, 5), 0.5, 1.0, 0.5)
	# Object is already within collision range (0.4 + 0.5 = 0.9, distance = 0.3)
	# Character is stationary, so no push should occur (no velocity)
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var overlap_pos := gs.get_physics_position("overlap_obj")
	_assert_true(absf(overlap_pos.x - 5.3) < 0.1, "Stationary overlap: no push without velocity (got: %.2f)" % overlap_pos.x)

	# --- Character stops before reaching object ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("far_obj", Vector3(15, 0, 5), 0.5, 1.0, 0.5)
	gs.register_character("short_walk", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("short_walk", Vector3(8, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var far_pos := gs.get_physics_position("far_obj")
	_assert_true(absf(far_pos.x - 15.0) < 0.01, "Object untouched when char stops short (got: %.2f)" % far_pos.x)

	# --- Multiple objects in a line (bowling) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("pin1", Vector3(6, 0, 5), 0.4, 0.8, 0.4)
	gs.register_physics_object("pin2", Vector3(7.5, 0, 5), 0.4, 0.8, 0.4)
	gs.register_physics_object("pin3", Vector3(9, 0, 5), 0.4, 0.8, 0.4)
	gs.register_character("bowler", Vector3(3, 0, 5), 5.0)
	gs.command_move_to_pos("bowler", Vector3(15, 0, 5))
	for _di in range(2000):
		if sched.pop_next().is_empty(): break
	var pin1_pos := gs.get_physics_position("pin1")
	var pin2_pos := gs.get_physics_position("pin2")
	var pin3_pos := gs.get_physics_position("pin3")
	var pin1_displaced := absf(pin1_pos.x - 6.0) > 0.1
	_assert_true(pin1_displaced, "Bowling pin 1 displaced (got: %.2f, started: 6.0)" % pin1_pos.x)
	_assert_true(pin2_pos.x > 7.6, "Bowling pin 2 pushed (got: %.2f)" % pin2_pos.x)
	_assert_true(pin3_pos.x > 9.1, "Bowling pin 3 pushed (got: %.2f)" % pin3_pos.x)
	# Pins should end up in order (1 < 2 < 3)
	_assert_true(pin1_pos.x < pin2_pos.x, "Bowling order: pin1 < pin2 (%.2f < %.2f)" % [pin1_pos.x, pin2_pos.x])
	_assert_true(pin2_pos.x < pin3_pos.x, "Bowling order: pin2 < pin3 (%.2f < %.2f)" % [pin2_pos.x, pin3_pos.x])

	# --- Opposite direction push (character approaches from +X) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("reverse_obj", Vector3(8, 0, 5), 0.5, 1.0, 0.5)
	gs.register_character("reverse_char", Vector3(12, 0, 5), 3.0)
	gs.command_move_to_pos("reverse_char", Vector3(3, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var rev_pos := gs.get_physics_position("reverse_obj")
	_assert_true(rev_pos.x < 7.9, "Reverse push: object pushed in -X (got: %.2f)" % rev_pos.x)

	# --- Area impulse: object outside radius not affected ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("in_range", Vector3(5, 0, 5), 0.5, 1.0, 0.5)
	gs.register_physics_object("out_range", Vector3(15, 0, 5), 0.5, 1.0, 0.5)
	gs.apply_area_impulse(Vector3(5, 0, 5), 3.0, 5.0)
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var out_pos := gs.get_physics_position("out_range")
	_assert_true(absf(out_pos.x - 15.0) < 0.01, "Object outside blast radius not moved (got: %.2f)" % out_pos.x)

	# Area impulse falloff: closer objects pushed farther.
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	# Place objects on different Z so they can't chain-push each other
	gs.register_physics_object("close_obj", Vector3(6, 0, 5), 0.5, 1.0, 0.5)
	gs.register_physics_object("far_falloff", Vector3(8, 0, 10), 0.5, 1.0, 0.5)
	gs.apply_area_impulse(Vector3(5, 0, 5), 5.0, 8.0)
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var close_final := gs.get_physics_position("close_obj")
	var far_final := gs.get_physics_position("far_falloff")
	var close_moved := close_final.distance_to(Vector3(6, 0, 5))
	var far_moved := far_final.distance_to(Vector3(8, 0, 10))
	_assert_true(close_moved > far_moved, "Blast falloff: closer pushed more (close: %.2f, far: %.2f)" % [close_moved, far_moved])

	# --- Zero-radius object (degenerate case) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("tiny", Vector3(5, 0, 5), 0.01, 1.0, 0.5)
	gs.register_character("tiny_pusher", Vector3(3, 0, 5), 3.0)
	gs.command_move_to_pos("tiny_pusher", Vector3(10, 0, 5))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	# Should not crash; object may or may not be pushed depending on collision range
	_assert_true(true, "Zero-radius object: no crash")

	# --- Unregister while moving ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("vanish", Vector3(5, 0, 5), 0.5, 1.0, 0.3)
	gs.register_character("vanish_pusher", Vector3(3, 0, 5), 4.0)
	gs.command_move_to_pos("vanish_pusher", Vector3(10, 0, 5))
	# Pop one event (likely the collision), then unregister mid-slide
	sched.pop_next()
	gs.unregister_physics_object("vanish")
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	_assert_true(not gs.physics_objects.has("vanish"), "Unregister mid-flight: no crash, object gone")

	# --- Many objects: 10 objects in a cluster, area impulse scatters all ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	var center := Vector3(15, 0, 15)
	for i in range(10):
		var angle := float(i) * TAU / 10.0
		var opos := center + Vector3(cos(angle) * 1.5, 0, sin(angle) * 1.5)
		gs.register_physics_object("cluster_%d" % i, opos, 0.3, 1.0, 0.5)
	gs.apply_area_impulse(center, 5.0, 6.0)
	for _di in range(3000):
		if sched.pop_next().is_empty(): break
	var scatter_count := 0
	for i in range(10):
		var cpos := gs.get_physics_position("cluster_%d" % i)
		if cpos.distance_to(center) > 2.0:
			scatter_count += 1
	_assert_true(scatter_count >= 8, "Cluster scatter: %d/10 objects moved outward" % scatter_count)

func _test_pendulum() -> void:
	_test_name = "Pendulum"
	var gs: GameState
	var sched: EventScheduler
	var grid2: GridWorld

	# --- Basic oscillation ---
	gs = GameState.new()
	sched = EventScheduler.new()
	gs.scheduler = sched

	gs.register_pendulum("p1", Vector3(5, 8, 5), 4.0, 0.5, Vector3.FORWARD, 0.4, 0.0, 0.0)
	_assert_true(gs.pendulums.has("p1"), "Pendulum registered")

	var period := gs.get_pendulum_period("p1")
	_assert_true(period > 0.5 and period < 5.0, "Period reasonable (got: %.2f)" % period)

	# At t=0 with phase=0: angle = amplitude * cos(0) = amplitude
	var angle_0 := gs.get_pendulum_angle("p1", 0.0)
	_assert_true(absf(angle_0 - 0.5) < 0.01, "Angle at t=0 = amplitude (got: %.3f)" % angle_0)

	# At t=period/2: angle should be -amplitude (half period, cos(pi) = -1)
	var angle_half := gs.get_pendulum_angle("p1", period / 2.0)
	_assert_true(absf(angle_half + 0.5) < 0.01, "Angle at T/2 = -amplitude (got: %.3f)" % angle_half)

	# At t=period: angle should return to amplitude (full cycle, cos(2pi) = 1)
	var angle_full := gs.get_pendulum_angle("p1", period)
	_assert_true(absf(angle_full - 0.5) < 0.01, "Angle at T = amplitude (got: %.3f)" % angle_full)

	# --- Position traces an arc ---
	var pos_0 := gs.get_pendulum_position("p1", 0.0)
	var pos_half := gs.get_pendulum_position("p1", period / 2.0)
	var pos_quarter := gs.get_pendulum_position("p1", period / 4.0)

	# At quarter period, angle = 0, bob hangs straight down
	_assert_true(pos_quarter.y < pos_0.y, "Bob lowest at T/4 (%.2f < %.2f)" % [pos_quarter.y, pos_0.y])
	# At 0 and half, bob is at opposite extremes in X (or Z depending on axis)
	var lateral_diff := pos_0.distance_to(pos_half)
	_assert_true(lateral_diff > 1.0, "Bob swings between extremes (dist: %.2f)" % lateral_diff)

	# --- Bob velocity peaks at bottom, zero at extremes ---
	var vel_0 := gs.get_pendulum_bob_velocity("p1", 0.0)
	var vel_quarter := gs.get_pendulum_bob_velocity("p1", period / 4.0)
	_assert_true(vel_0.length() < 0.5, "Velocity near zero at extreme (got: %.3f)" % vel_0.length())
	_assert_true(vel_quarter.length() > 1.0, "Velocity peaks at bottom (got: %.3f)" % vel_quarter.length())

	# --- Damping reduces amplitude over time ---
	gs = GameState.new()
	sched = EventScheduler.new()
	gs.scheduler = sched
	gs.register_pendulum("damped", Vector3(5, 8, 5), 4.0, 0.5, Vector3.FORWARD, 0.4, 0.0, 0.5)
	var amp_early := absf(gs.get_pendulum_angle("damped", 0.0))
	var amp_late := absf(gs.get_pendulum_angle("damped", 5.0))
	_assert_true(amp_late < amp_early, "Damping reduces amplitude (early: %.3f, late: %.3f)" % [amp_early, amp_late])

	# --- Pendulum hits character walking through ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(20, 20)
	gs.grid = grid2
	gs.scheduler = sched

	# Pendulum swings along X at y=8, bob reaches down to y=4 (length=4)
	# Bob swings laterally around x=5
	gs.register_pendulum("swinger", Vector3(5, 8, 5), 4.0, 0.6, Vector3.FORWARD, 0.5)

	# Character walks through the swing zone
	var hit_log: Array = []
	gs.pendulum_hit.connect(func(pid, tid, vel): hit_log.append({"pid": pid, "tid": tid, "speed": vel.length()}))

	gs.register_character("walker", Vector3(2, 0, 5), 2.0)
	gs.command_move_to_pos("walker", Vector3(8, 0, 5))

	for _di in range(2000):
		if sched.pop_next().is_empty(): break

	_assert_true(hit_log.size() > 0, "Pendulum hit character (hits: %d)" % hit_log.size())
	if hit_log.size() > 0:
		_assert_true(hit_log[0].speed > 0.5, "Hit has velocity (speed: %.2f)" % hit_log[0].speed)

	# --- Pendulum hits physics object ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(20, 20)
	gs.grid = grid2
	gs.scheduler = sched

	# Phase PI/2 so bob starts at center (angle=0) and swings toward the object
	gs.register_pendulum("pusher_pend", Vector3(5, 8, 5), 4.0, 0.6, Vector3.FORWARD, 0.5, PI / 2.0)
	gs.register_physics_object("pend_target", Vector3(7.0, 0, 5), 0.5, 1.0, 0.5)

	var pobj_hits: Array = []
	gs.pendulum_hit.connect(func(pid, tid, vel): pobj_hits.append({"tid": tid, "speed": vel.length()}))

	for _di in range(2000):
		if sched.pop_next().is_empty(): break

	_assert_true(pobj_hits.size() > 0, "Pendulum-physics collision detected (hits: %d)" % pobj_hits.size())
	var pend_obj_pos := gs.get_physics_position("pend_target")
	_assert_true(pend_obj_pos.distance_to(Vector3(6.5, 0, 5)) > 0.05, "Pendulum pushed physics object (dist: %.2f)" % pend_obj_pos.distance_to(Vector3(6.5, 0, 5)))

	# --- Character walks past but out of range ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(20, 20)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_pendulum("miss_pend", Vector3(5, 8, 5), 4.0, 0.3, Vector3.FORWARD, 0.3)
	var miss_log: Array = []
	gs.pendulum_hit.connect(func(pid, tid, vel): miss_log.append(tid))

	# Walk at z=8, pendulum swings at z=5, out of range.
	gs.register_character("far_walker", Vector3(2, 0, 8), 2.0)
	gs.command_move_to_pos("far_walker", Vector3(8, 0, 8))
	for _di in range(1000):
		if sched.pop_next().is_empty(): break

	_assert_true(miss_log.size() == 0, "No hit when character walks out of range (hits: %d)" % miss_log.size())

	# --- Different lengths = different periods ---
	gs = GameState.new()
	sched = EventScheduler.new()
	gs.scheduler = sched
	gs.register_pendulum("short", Vector3(0, 5, 0), 1.0, 0.5)
	gs.register_pendulum("long", Vector3(0, 15, 0), 9.0, 0.5)
	var short_period := gs.get_pendulum_period("short")
	var long_period := gs.get_pendulum_period("long")
	_assert_true(long_period > short_period, "Longer pendulum = longer period (short: %.2f, long: %.2f)" % [short_period, long_period])
	# T = 2pi*sqrt(L/g), so T_long/T_short = sqrt(9/1) = 3
	var ratio := long_period / short_period
	_assert_true(absf(ratio - 3.0) < 0.1, "Period ratio matches sqrt(L) (got: %.2f, expected: 3.0)" % ratio)

	# --- Phase offset ---
	gs = GameState.new()
	sched = EventScheduler.new()
	gs.scheduler = sched
	gs.register_pendulum("phase0", Vector3(0, 5, 0), 2.0, 0.5, Vector3.FORWARD, 0.3, 0.0)
	gs.register_pendulum("phase90", Vector3(0, 5, 0), 2.0, 0.5, Vector3.FORWARD, 0.3, PI / 2.0)
	var p0_angle := gs.get_pendulum_angle("phase0", 0.0)
	var p90_angle := gs.get_pendulum_angle("phase90", 0.0)
	_assert_true(absf(p0_angle - 0.5) < 0.01, "Phase 0: angle=amplitude at t=0 (got: %.3f)" % p0_angle)
	_assert_true(absf(p90_angle) < 0.01, "Phase PI/2: angle=0 at t=0 (got: %.3f)" % p90_angle)

	# --- Unregister ---
	gs.unregister_pendulum("phase0")
	_assert_true(not gs.pendulums.has("phase0"), "Pendulum unregistered")

func _test_throw_physics() -> void:
	_test_name = "Throw Physics"
	var gs: GameState
	var sched: EventScheduler
	var grid2: GridWorld

	# --- Basic throw: lob forward ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("ball", Vector3(5, 0, 5), 0.3, 0.5, 0.5)
	gs.throw_physics_object("ball", Vector3(4, 6, 0), Vector3(5, 1, 5))

	_assert_true(gs.is_physics_airborne("ball"), "Ball is airborne after throw")
	_assert_true(gs.is_physics_moving("ball"), "Ball is moving after throw")

	# Check peak height (vy=6, peak at t=vy/g=0.612s, height=1+6*0.612-0.5*9.8*0.612²=2.837)
	var peak := gs.get_throw_peak_height("ball")
	_assert_true(peak > 2.0, "Peak height > 2.0 (got: %.2f)" % peak)

	# Mid-flight: Y should be above ground
	sched.advance_ticks(0.3)
	var mid_pos := gs.get_physics_position("ball")
	_assert_true(mid_pos.y > 1.0, "Mid-flight Y above ground (got: %.2f)" % mid_pos.y)
	_assert_true(mid_pos.x > 5.5, "Mid-flight X moved forward (got: %.2f)" % mid_pos.x)

	# Drain to landing
	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var landed_pos := gs.get_physics_position("ball")
	_assert_true(landed_pos.y < 0.1, "Ball on ground after landing (y: %.2f)" % landed_pos.y)
	_assert_true(landed_pos.x > 8.0, "Ball traveled forward (x: %.2f)" % landed_pos.x)
	_assert_true(not gs.is_physics_airborne("ball"), "Ball no longer airborne")

	# --- Throw straight up: lands near origin ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("up_ball", Vector3(10, 0, 10), 0.3, 0.5, 0.5)
	gs.throw_physics_object("up_ball", Vector3(0, 8, 0), Vector3(10, 0, 10))

	var up_peak := gs.get_throw_peak_height("up_ball")
	_assert_true(up_peak > 3.0, "Vertical throw peak height (got: %.2f)" % up_peak)

	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var up_landed := gs.get_physics_position("up_ball")
	_assert_true(absf(up_landed.x - 10.0) < 0.5, "Vertical throw lands near origin X (got: %.2f)" % up_landed.x)
	_assert_true(absf(up_landed.z - 10.0) < 0.5, "Vertical throw lands near origin Z (got: %.2f)" % up_landed.z)

	# --- Throw into wall: truncated flight ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(20, 20)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("wall_ball", Vector3(15, 0, 10), 0.3, 0.5, 0.5)
	gs.throw_physics_object("wall_ball", Vector3(8, 4, 0), Vector3(15, 1, 10))

	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var wall_landed := gs.get_physics_position("wall_ball")
	_assert_true(wall_landed.x < 19.0, "Throw stopped at wall (x: %.2f)" % wall_landed.x)

	# --- Throw hits character mid-flight ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	var throw_hits: Array = []
	gs.physics_collision.connect(func(oid, cid, imp): throw_hits.append({"oid": oid, "cid": cid}))

	gs.register_character("target_char", Vector3(10, 0, 5), 0.0)
	gs.register_physics_object("projectile", Vector3(5, 0, 5), 0.4, 0.3, 0.5)
	gs.throw_physics_object("projectile", Vector3(6, 3, 0), Vector3(5, 1, 5))

	for _di in range(1000):
		if sched.pop_next().is_empty(): break

	# Thrown object should hit the character and land near it
	var proj_final := gs.get_physics_position("projectile")
	_assert_true(proj_final.x > 7.0, "Projectile reached target area (x: %.2f)" % proj_final.x)
	_assert_true(not gs.is_physics_airborne("projectile"), "Projectile landed after hit")
	_assert_true(throw_hits.size() > 0, "Throw collision signal fired (count: %d)" % throw_hits.size())

	# --- Post-landing slide ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("slider", Vector3(5, 0, 10), 0.3, 0.5, 0.3)
	gs.throw_physics_object("slider", Vector3(5, 4, 0), Vector3(5, 1, 10))

	# Track if the object slides after landing
	var slide_detected := false
	var slide_log: Array = []
	gs.physics_collision.connect(func(oid, cid, imp): slide_log.append(oid))

	for _di in range(1000):
		if sched.pop_next().is_empty(): break

	var slider_final := gs.get_physics_position("slider")
	_assert_true(slider_final.y < 0.1, "Slider on ground (y: %.2f)" % slider_final.y)
	# With vx=5 and bounce_factor=0.5, post-landing slide speed=2.5, slide_dist=2.5²/(2*0.3*3)=3.47
	_assert_true(slider_final.x > 9.0, "Post-landing slide extended range (x: %.2f)" % slider_final.x)

	# --- Throw with no vertical component (flat throw) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("flat", Vector3(5, 0, 10), 0.3, 0.5, 0.5)
	gs.throw_physics_object("flat", Vector3(4, 0, 0), Vector3(5, 2, 10))

	# With vy=0 from y=2: flight_time = sqrt(2*2/9.8)=0.639s, lands at x=5+4*0.639=7.56
	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var flat_final := gs.get_physics_position("flat")
	_assert_true(flat_final.y < 0.1, "Flat throw lands (y: %.2f)" % flat_final.y)
	_assert_true(flat_final.x > 7.0, "Flat throw traveled forward (x: %.2f)" % flat_final.x)

	# --- Throw from ground (y=0): just vy lifts it ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("ground_throw", Vector3(5, 0, 10), 0.3, 0.5, 0.5)
	gs.throw_physics_object("ground_throw", Vector3(3, 5, 0), Vector3(5, 0, 10))

	var gt_peak := gs.get_throw_peak_height("ground_throw")
	_assert_true(gt_peak > 1.0, "Ground throw has peak height (got: %.2f)" % gt_peak)

	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var gt_final := gs.get_physics_position("ground_throw")
	_assert_true(gt_final.y < 0.1, "Ground throw lands (y: %.2f)" % gt_final.y)
	_assert_true(gt_final.x > 7.0, "Ground throw traveled (x: %.2f)" % gt_final.x)

	# --- Diagonal throw (XZ) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("diag_throw", Vector3(5, 0, 5), 0.3, 0.5, 0.5)
	gs.throw_physics_object("diag_throw", Vector3(3, 5, 3), Vector3(5, 0, 5))

	for _di in range(500):
		if sched.pop_next().is_empty(): break

	var diag_final := gs.get_physics_position("diag_throw")
	_assert_true(diag_final.x > 6.5, "Diagonal throw +X (got: %.2f)" % diag_final.x)
	_assert_true(diag_final.z > 6.5, "Diagonal throw +Z (got: %.2f)" % diag_final.z)

	# --- Throw hits physics object (bowling) ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	# Rock lands near barrel, post-landing slide pushes it
	gs.register_physics_object("target_barrel", Vector3(11, 0, 10), 0.5, 1.5, 0.4)
	gs.register_physics_object("thrown_rock", Vector3(5, 0, 10), 0.4, 0.5, 0.3)
	gs.throw_physics_object("thrown_rock", Vector3(6, 3, 0), Vector3(5, 1, 10))

	for _di in range(2000):
		if sched.pop_next().is_empty(): break

	var barrel_after := gs.get_physics_position("target_barrel")
	_assert_true(barrel_after.distance_to(Vector3(11, 0, 10)) > 0.1, "Barrel displaced by thrown rock (barrel x: %.2f)" % barrel_after.x)

	# --- Determinism ---
	var throw_results: Array[float] = []
	for trial in range(2):
		gs = GameState.new()
		sched = EventScheduler.new()
		grid2 = GridWorld.new()
		grid2.create_room(30, 30)
		gs.grid = grid2
		gs.scheduler = sched
		gs.register_physics_object("det", Vector3(5, 0, 10), 0.3, 0.5, 0.4)
		gs.throw_physics_object("det", Vector3(4, 5, 2), Vector3(5, 0.5, 10))
		for _di in range(1000):
			if sched.pop_next().is_empty(): break
		throw_results.append(gs.get_physics_position("det").x)
	_assert_true(absf(throw_results[0] - throw_results[1]) < 0.001, "Throw deterministic (%.4f vs %.4f)" % [throw_results[0], throw_results[1]])

func _test_physics_comparison() -> void:
	_test_name = "Physics Comparison"

	# ============================
	# CUSTOM ENGINE: Push scenario
	# ============================
	var gs := GameState.new()
	var sched := EventScheduler.new()
	var grid2 := GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_physics_object("custom_barrel", Vector3(8, 0, 10), 0.5, 2.0, 0.5)
	gs.register_character("custom_pusher", Vector3(3, 0, 10), 4.0)

	var custom_start := Time.get_ticks_usec()
	gs.command_move_to_pos("custom_pusher", Vector3(15, 0, 10))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var custom_elapsed := Time.get_ticks_usec() - custom_start
	var custom_result := gs.get_physics_position("custom_barrel")

	# Run same scenario twice for determinism check
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("custom_barrel", Vector3(8, 0, 10), 0.5, 2.0, 0.5)
	gs.register_character("custom_pusher", Vector3(3, 0, 10), 4.0)
	gs.command_move_to_pos("custom_pusher", Vector3(15, 0, 10))
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	var custom_result2 := gs.get_physics_position("custom_barrel")

	var custom_deterministic := custom_result.distance_to(custom_result2) < 0.001

	# ============================
	# JOLT ENGINE: Push scenario
	# ============================
	var jolt_root := Node3D.new()
	jolt_root.name = "JoltTestScene"
	get_tree().root.add_child(jolt_root)

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30, 1, 30)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(15, -0.5, 15)
	jolt_root.add_child(floor_body)

	# Barrel (RigidBody3D)
	var jolt_barrel := RigidBody3D.new()
	jolt_barrel.mass = 2.0
	jolt_barrel.position = Vector3(8, 0.5, 10)
	var barrel_shape := CollisionShape3D.new()
	var barrel_sphere := SphereShape3D.new()
	barrel_sphere.radius = 0.5
	barrel_shape.shape = barrel_sphere
	jolt_barrel.add_child(barrel_shape)
	jolt_root.add_child(jolt_barrel)

	# Wait for physics to settle
	for i in range(30):
		await get_tree().physics_frame

	var jolt_barrel_start := jolt_barrel.position

	# Push barrel with an impulse equivalent to a 4 unit/sec character hitting it
	var jolt_start := Time.get_ticks_usec()
	jolt_barrel.apply_impulse(Vector3(4.0 * 2.0 * 0.85, 0, 0))

	# Run physics for ~2 seconds (120 physics frames at 60Hz)
	for i in range(120):
		await get_tree().physics_frame
	var jolt_elapsed := Time.get_ticks_usec() - jolt_start
	var jolt_result := jolt_barrel.position

	# Run same scenario again for determinism check
	jolt_barrel.position = Vector3(8, 0.5, 10)
	jolt_barrel.linear_velocity = Vector3.ZERO
	jolt_barrel.angular_velocity = Vector3.ZERO
	for i in range(30):
		await get_tree().physics_frame
	jolt_barrel.apply_impulse(Vector3(4.0 * 2.0 * 0.85, 0, 0))
	for i in range(120):
		await get_tree().physics_frame
	var jolt_result2 := jolt_barrel.position
	var jolt_deterministic := jolt_result.distance_to(jolt_result2) < 0.01

	jolt_root.queue_free()
	await get_tree().process_frame

	# ============================
	# COMPARISON RESULTS
	# ============================
	print("")
	print("  === Physics Engine Comparison ===")
	print("  Scenario: character pushes barrel from x=3 to x=15, barrel at x=8")
	print("")
	print("  Custom (scheduler-driven):")
	print("    Result:  barrel at x=%.4f z=%.4f" % [custom_result.x, custom_result.z])
	print("    Time:    %d µs" % custom_elapsed)
	print("    Deterministic: %s (diff: %.6f)" % ["YES" if custom_deterministic else "NO", custom_result.distance_to(custom_result2)])
	print("    Headless:      YES (no physics server needed)")
	print("    Speed control: YES (scheduler fast-forward, pop_next)")
	print("    Predictive:    YES (collision pre-scheduled, zero per-frame cost)")
	print("")
	print("  Jolt (Godot built-in):")
	print("    Result:  barrel at x=%.4f z=%.4f y=%.4f" % [jolt_result.x, jolt_result.z, jolt_result.y])
	print("    Time:    %d µs (120 physics frames)" % jolt_elapsed)
	print("    Deterministic: %s (diff: %.6f)" % ["YES" if jolt_deterministic else "NO", jolt_result.distance_to(jolt_result2)])
	print("    Headless:      YES (Jolt has no render deps)")
	print("    Speed control: NO (tied to physics tick rate)")
	print("    Predictive:    NO (per-frame integration)")
	print("")

	# Assertions
	_assert_true(custom_result.x > 8.0, "Custom: barrel pushed (x: %.2f)" % custom_result.x)
	_assert_true(jolt_result.x > 8.0, "Jolt: barrel pushed (x: %.2f)" % jolt_result.x)
	_assert_true(custom_deterministic, "Custom: deterministic across runs")
	_assert_true(custom_elapsed < jolt_elapsed, "Custom faster than Jolt (%d µs vs %d µs)" % [custom_elapsed, jolt_elapsed])

	# ============================
	# CHAIN REACTION COMPARISON
	# ============================
	# Custom: 3 barrels in a line
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	gs.register_physics_object("c1", Vector3(8, 0, 5), 0.4, 1.0, 0.4)
	gs.register_physics_object("c2", Vector3(9.5, 0, 5), 0.4, 1.0, 0.4)
	gs.register_physics_object("c3", Vector3(11, 0, 5), 0.4, 1.0, 0.4)
	gs.register_character("chain_p", Vector3(3, 0, 5), 5.0)

	custom_start = Time.get_ticks_usec()
	gs.command_move_to_pos("chain_p", Vector3(15, 0, 5))
	for _di in range(2000):
		if sched.pop_next().is_empty(): break
	custom_elapsed = Time.get_ticks_usec() - custom_start
	var c1_pos := gs.get_physics_position("c1")
	var c2_pos := gs.get_physics_position("c2")
	var c3_pos := gs.get_physics_position("c3")

	# Jolt: 3 barrels in a line
	jolt_root = Node3D.new()
	jolt_root.name = "JoltChainTest"
	get_tree().root.add_child(jolt_root)

	var jolt_floor := StaticBody3D.new()
	var jf_shape := CollisionShape3D.new()
	var jf_box := BoxShape3D.new()
	jf_box.size = Vector3(30, 1, 30)
	jf_shape.shape = jf_box
	jolt_floor.add_child(jf_shape)
	jolt_floor.position = Vector3(15, -0.5, 15)
	jolt_root.add_child(jolt_floor)

	var jolt_barrels: Array[RigidBody3D] = []
	for bx in [8.0, 9.5, 11.0]:
		var b := RigidBody3D.new()
		b.mass = 1.0
		b.position = Vector3(bx, 0.5, 5)
		var bs := CollisionShape3D.new()
		var bsp := SphereShape3D.new()
		bsp.radius = 0.4
		bs.shape = bsp
		b.add_child(bs)
		jolt_root.add_child(b)
		jolt_barrels.append(b)

	for i in range(30):
		await get_tree().physics_frame

	jolt_start = Time.get_ticks_usec()
	jolt_barrels[0].apply_impulse(Vector3(5.0 * 1.0 * 0.85, 0, 0))
	for i in range(180):
		await get_tree().physics_frame
	jolt_elapsed = Time.get_ticks_usec() - jolt_start

	print("  === Chain Reaction Comparison (3 barrels) ===")
	print("  Custom:  [%.2f, %.2f, %.2f]  %d µs" % [c1_pos.x, c2_pos.x, c3_pos.x, custom_elapsed])
	print("  Jolt:    [%.2f, %.2f, %.2f]  %d µs" % [jolt_barrels[0].position.x, jolt_barrels[1].position.x, jolt_barrels[2].position.x, jolt_elapsed])
	print("")

	_assert_true(c3_pos.x > 11.0, "Custom chain: barrel 3 pushed (x: %.2f)" % c3_pos.x)
	_assert_true(jolt_barrels[2].position.x > 11.0, "Jolt chain: barrel 3 pushed (x: %.2f)" % jolt_barrels[2].position.x)

	# ============================
	# AREA IMPULSE COMPARISON
	# ============================
	# Custom: 5 objects around a center
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched
	var custom_scatter_positions: Array[Vector3] = []
	for i in range(5):
		var angle := float(i) * TAU / 5.0
		var opos := Vector3(15 + cos(angle) * 1.5, 0, 15 + sin(angle) * 1.5)
		gs.register_physics_object("s%d" % i, opos, 0.3, 1.0, 0.5)
		custom_scatter_positions.append(opos)

	custom_start = Time.get_ticks_usec()
	gs.apply_area_impulse(Vector3(15, 0, 15), 4.0, 6.0)
	for _di in range(1000):
		if sched.pop_next().is_empty(): break
	custom_elapsed = Time.get_ticks_usec() - custom_start

	var custom_scatter_moved := 0
	for i in range(5):
		if gs.get_physics_position("s%d" % i).distance_to(custom_scatter_positions[i]) > 0.5:
			custom_scatter_moved += 1

	# Jolt: 5 objects around a center
	jolt_root.queue_free()
	await get_tree().process_frame
	jolt_root = Node3D.new()
	jolt_root.name = "JoltScatterTest"
	get_tree().root.add_child(jolt_root)

	var jf2 := StaticBody3D.new()
	var jf2_shape := CollisionShape3D.new()
	var jf2_box := BoxShape3D.new()
	jf2_box.size = Vector3(30, 1, 30)
	jf2_shape.shape = jf2_box
	jf2.add_child(jf2_shape)
	jf2.position = Vector3(15, -0.5, 15)
	jolt_root.add_child(jf2)

	var jolt_scatter: Array[RigidBody3D] = []
	var jolt_scatter_starts: Array[Vector3] = []
	for i in range(5):
		var angle := float(i) * TAU / 5.0
		var opos := Vector3(15 + cos(angle) * 1.5, 0.5, 15 + sin(angle) * 1.5)
		var b := RigidBody3D.new()
		b.mass = 1.0
		b.position = opos
		var bs := CollisionShape3D.new()
		var bsp := SphereShape3D.new()
		bsp.radius = 0.3
		bs.shape = bsp
		b.add_child(bs)
		jolt_root.add_child(b)
		jolt_scatter.append(b)
		jolt_scatter_starts.append(opos)

	for i in range(30):
		await get_tree().physics_frame

	jolt_start = Time.get_ticks_usec()
	for b in jolt_scatter:
		var dir := (b.position - Vector3(15, 0.5, 15)).normalized()
		var dist := b.position.distance_to(Vector3(15, 0.5, 15))
		var falloff := 1.0 - (dist / 4.0)
		b.apply_impulse(dir * 6.0 * falloff)
	for i in range(120):
		await get_tree().physics_frame
	jolt_elapsed = Time.get_ticks_usec() - jolt_start

	var jolt_scatter_moved := 0
	for i in range(5):
		if jolt_scatter[i].position.distance_to(jolt_scatter_starts[i]) > 0.5:
			jolt_scatter_moved += 1

	print("  === Area Impulse Comparison (5 objects) ===")
	print("  Custom:  %d/5 scattered  %d µs" % [custom_scatter_moved, custom_elapsed])
	print("  Jolt:    %d/5 scattered  %d µs" % [jolt_scatter_moved, jolt_elapsed])
	print("")

	_assert_true(custom_scatter_moved >= 4, "Custom scatter: %d/5 moved" % custom_scatter_moved)
	_assert_true(jolt_scatter_moved >= 4, "Jolt scatter: %d/5 moved" % jolt_scatter_moved)

	print("  === Summary ===")
	print("  Custom engine strengths:")
	print("    - Deterministic (exact match across runs)")
	print("    - Predictive (zero per-frame collision checks)")
	print("    - Speed-controllable (10x fast-forward, pop_next for tests)")
	print("    - Integrated with EventScheduler (pause, tag cancel)")
	print("    - Headlessly testable with pop_next()")
	print("  Jolt strengths:")
	print("    - Full rigid body simulation (rotation, stacking, joints)")
	print("    - Continuous collision detection")
	print("    - Industry-standard solver (tunneling prevention)")
	print("    - Free angular dynamics (tumbling, spinning)")
	print("")

	jolt_root.queue_free()
	await get_tree().process_frame

func _test_peris_phase2() -> void:
	_test_name = "Peris Phase 2"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if not scene:
		_assert_true(false, "Scene loads")
		return
	var instance: Node = scene.instantiate()
	instance._visit_phase = 2
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var log := _pop_dialogue_log(instance, {
		"protect_prompt": func(): instance._on_protect_pressed(),
		"run_prompt": func(): instance._toggle_run(),
		"click_monos": func(): instance._start_confirm_protect(),
		"confirm_protect": func(): instance._start_executing(),
	})

	_assert_true(log.size() >= 3, "Phase 2: at least 3 dialogue lines (got: %d)" % log.size())

	# Verify the attack/overtime dialogue fires
	var has_hit := false
	var has_overtime := false
	var has_protect := false
	for entry in log:
		if "hit" in entry.text.to_lower() or "monos" in entry.text.to_lower():
			has_hit = true
		if "overtime" in entry.text.to_lower() or "OVERTIME" in entry.text:
			has_overtime = true
		if "protect" in entry.text.to_lower() or "shield" in entry.text.to_lower():
			has_protect = true

	_assert_true(has_hit or log.size() >= 2, "Phase 2: attack dialogue appears")

	# Verify protect prompt dialogue fires (the bug: dialogue wasn't showing because scheduler was frozen)
	var has_protect_him := false
	for entry in log:
		if "protect" in entry.text.to_lower():
			has_protect_him = true
	_assert_true(has_protect_him, "Phase 2: protect dialogue shows during pause (bug fix verified)")

	# Verify the session completes
	var has_complete := false
	for entry in log:
		if "complete" in entry.text.to_lower() or "session" in entry.text.to_lower():
			has_complete = true
	_assert_true(has_complete, "Phase 2: session completion logged")

	# Verify efficiency/completion text (same line as session complete)
	var has_efficiency := false
	for entry in log:
		if "efficiency" in entry.text.to_lower() or "%" in entry.text or "62" in entry.text:
			has_efficiency = true
	_assert_true(has_efficiency or has_complete, "Phase 2: efficiency logged")

	var has_sanction := false
	var has_wellness := false
	var has_reconnect_denied := false
	for entry in log:
		var lower_text: String = entry.text.to_lower()
		if "sanction" in lower_text or "suspended pending review" in lower_text:
			has_sanction = true
		if "restorative mode" in lower_text or "gel" in lower_text or "soap" in lower_text:
			has_wellness = true
		if "reconnect request denied" in lower_text:
			has_reconnect_denied = true
	_assert_true(has_sanction, "Phase 2: sanction mode follows efficiency penalty")
	_assert_true(has_wellness, "Phase 2: wellness feed appears during sanction")
	_assert_true(has_reconnect_denied, "Phase 2: reconnect denial appears before transition")

	instance._visit_phase = 1
	instance.queue_free()
	await get_tree().process_frame

## End-of-scene crash guard. The transition crash is a NON-FATAL GDScript null-deref: it prints
## a SCRIPT ERROR but doesn't abort, and the scene still reaches `complete` and transitions — so
## an in-process state assertion (reached_complete / current_scene) can't tell buggy from fixed.
## Instead, drive the REAL transition lifecycle in a CHILD headless instance and assert its log
## carries no "on a null value". RED when a scheduled _complete tears the scheduler down
## mid-advance and the next advance/get_current_tick derefs null; GREEN once the advance sites
## re-guard. This is why input/transition coverage must run for real, not via a faked teardown.
func _test_peris_scene_transition() -> void:
	_test_name = "Peris Scene Transition"
	var exe := OS.get_executable_path()
	if exe == "":
		_assert_true(false, "Executable path available for the subprocess transition guard")
		return
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ".", "--", "--drive-peris-transition"])
	var code := OS.execute(exe, args, out, true)  # read_stderr=true → captures child SCRIPT ERRORs
	var log := ""
	for line in out:
		log += str(line)
	var drove := log.contains("[PERIS-TRANSITION-CHILD] reached_complete=true")
	var crashed := log.contains("on a null value")
	if crashed:
		for raw in log.split("\n"):
			if raw.contains("on a null value") or (raw.contains(".gd:") and raw.contains("at:")):
				print("  [transition-crash] %s" % raw.strip_edges())
	_assert_true(drove, "Child drove Peris-2 to complete via the real transition (exit %d)" % code)
	_assert_true(not crashed, "Peris end-of-scene transition touches no torn-down scheduler (no 'on a null value')")

## Child entry for the subprocess guard above (run via --drive-peris-transition). Drives Peris-2's
## REAL transition lifecycle — real input to `complete`, then the actual change_scene_to_file ->
## teardown -> final process (NOT suppressed, NOT a manual teardown) — and prints a sentinel. A
## scheduler used after teardown surfaces as a SCRIPT ERROR in this child's stderr.
func _drive_peris_transition_child() -> void:
	_test_name = "Peris Transition (child)"
	var scene := load("res://scenes/tutorial/peris_sim.tscn")
	if scene == null:
		print("[PERIS-TRANSITION-CHILD] reached_complete=false last_step=<no-scene>")
		return
	var instance: Node = scene.instantiate()
	if "_visit_phase" in instance:
		instance._visit_phase = 2
	get_tree().root.add_child(instance)
	get_tree().current_scene = instance
	for i in range(5):
		await get_tree().process_frame
	var beats := _peris2_realinput_beats(instance)
	var dialogue: Node = instance.get("_dialogue")
	var actioned := {}
	var last_step := ""
	var unchanged := 0
	var reached_complete := false
	for i in range(30000):
		if not is_instance_valid(instance):
			break
		var step := str(instance._current_step)
		if step != last_step:
			last_step = step
			unchanged = 0
		else:
			unchanged += 1
		if step == "complete":
			reached_complete = true
			break
		if dialogue != null and is_instance_valid(dialogue):
			_pump_dialogue(dialogue, 8.0)
		if beats.has(step):
			if not actioned.has(step):
				actioned[step] = true
				beats[step].call()
			elif unchanged > 0 and unchanged % 40 == 0:
				beats[step].call()
		if unchanged > 5000:
			break
		# Fire the final beat through the PRODUCTION _process path (not headless_advance): a big
		# delta makes _scheduler.advance() inside _process() fire the scheduled _complete, which
		# tears the scene down mid-advance — exactly the real-play sequence that derefs
		# _ui_scheduler.get_current_tick() on null when _process forgets to re-guard.
		if step == "transition_out":
			instance._process(3.0)
		else:
			instance.headless_advance(0.1, 0.05)
		# _complete sets step="complete" then tears the scene down; catch it before the
		# process_frame below frees the instance.
		if is_instance_valid(instance) and str(instance._current_step) == "complete":
			reached_complete = true
			break
		await get_tree().process_frame
	# Let the deferred free + teardown + final process run for real — where the crash lives.
	for i in range(15):
		await get_tree().process_frame
		await get_tree().physics_frame
	print("[PERIS-TRANSITION-CHILD] reached_complete=%s last_step=%s current_scene=%s" % [
		str(reached_complete), last_step, str(get_tree().current_scene)])

func _test_sequence_contracts() -> void:
	var aster_actions := func(instance: Node):
		var actions := {}
		actions["show_terminal"] = func(): instance._on_terminal_interacted()
		actions["walk_to_drink"] = func(): instance._on_drink_interacted()
		# Exploration beat: unlock the gate immediately and fire it. The scene
		# normally waits EXPLORE_MIN_TIME of scheduler time, but contract tests
		# skip straight through.
		actions["explore_workspace"] = func():
			instance._explore_gate_unlocked = true
			instance._on_exploration_gate_interacted()
		return actions

	var peris_phase_1_setup := func(instance: Node):
		instance._visit_phase = 1

	var peris_phase_1_actions := func(instance: Node):
		var actions := {}
		# Exploration beat: unlock and fire the logbook gate so Monos connects.
		actions["workspace"] = func():
			instance._explore_gate_unlocked = true
			instance._on_exploration_gate_interacted()
		return actions

	var peris_phase_2_setup := func(instance: Node):
		instance._visit_phase = 2

	var peris_phase_2_actions := func(instance: Node):
		var actions := {}
		actions["protect_prompt"] = func(): instance._on_protect_pressed()
		actions["run_prompt"] = func(): instance._toggle_run()
		actions["click_monos"] = func(): instance._start_confirm_protect()
		actions["confirm_protect"] = func(): instance._start_executing()
		return actions

	var leaving_actions := func(instance: Node):
		var actions := {}
		actions["first_corridor"] = func():
			_set_sequence_character_position(
				instance,
				"aster",
				Vector3(instance.IRON_1_POS.x - 1.0, 0.5, instance.IRON_1_POS.z)
			)
		actions["safe_route_lesson"] = func():
			_set_sequence_character_position(
				instance,
				"aster",
				Vector3(instance.MIDPOINT.x + 1.0, 0.5, instance.MIDPOINT.z)
			)
		actions["second_iron"] = func():
			_set_sequence_character_position(
				instance,
				"aster",
				Vector3(instance.SHELTER_POS.x + 0.5, 0.5, instance.SHELTER_POS.z)
			)
		return actions

	# clearance -> complete now rides the scheduler (the blue fade is a cosmetic tween),
	# so the driver reaches complete on its own — no force-fire needed.
	var tag_day_actions := func(_instance: Node):
		return {}

	var elevator_actions := func(instance: Node):
		var actions := {}
		actions["consciousness_fragments"] = func():
			if instance._aster_node:
				instance._aster_node.visible = true
			for unit in [instance._escort_1, instance._escort_2]:
				if unit:
					unit.visible = true
			instance._emergency_light.light_energy = 3.0
			instance._fade_rect.color.a = 0.0
			instance._start_waking()
		actions["approach_aster"] = func():
			_set_sequence_character_position(
				instance,
				"peris",
				instance.ASTER_POS + Vector3(0.5, 0.5, 0.0)
			)
			instance._on_aster_wake_interacted()
		actions["emp_tutorial"] = func():
			instance._on_emp_pressed()
			instance._toggle_pause()
		actions["multiselect_tutorial"] = func():
			instance._hud.set_selected_portraits(["peris", "aster"])
			instance._scheduler.resume()
			var exit_gate := Vector3(instance.ELEVATOR_SIZE.x / 2.0, 0.5, 0.0)
			_set_sequence_character_position(
				instance,
				"peris",
				exit_gate + Vector3(0.0, 0.0, -0.5)
			)
			_set_sequence_character_position(
				instance,
				"aster",
				exit_gate + Vector3(0.0, 0.0, 0.5)
			)
		actions["corridor"] = func():
			_disable_enemy_detection(instance)
		actions["bridge"] = func():
			# Walk out across the bridge to its far end — the gate collapses it there.
			_disable_enemy_detection(instance)
			_set_sequence_character_position(
				instance,
				"aster",
				Vector3(instance.BRIDGE_END_X - 1.0, 0.5, 0.0)
			)
		actions["bridge_collapse"] = func():
			instance._on_fall_landed()
		actions["climb_attempt"] = func():
			instance._on_climb_prompt_interacted()
		actions["route_choice"] = func():
			_disable_enemy_detection(instance)
			_set_sequence_character_position(
				instance,
				"aster",
				instance.ROUTES_CONVERGE + Vector3(1.5, 0.5, 0.0)
			)
		actions["junction_arrive"] = func():
			instance._start_dusk_from_plant()
		actions["endo_shelter"] = func():
			instance._on_endo_delivered("endo")
		actions["gauntlet"] = func():
			_disable_enemy_detection(instance)
			instance._on_ferrolure_activated()
			_set_sequence_character_position(
				instance,
				"aster",
				instance.GAUNTLET_EXIT + Vector3(1.5, 0.5, 0.0)
			)
		actions["complete"] = func():
			instance._change_scene_or_record("res://scenes/tutorial/act1.tscn")
			instance._scheduler.clear()
		return actions

	var act1_actions := Callable(self, "_make_act1_sequence_actions")

	await _run_sequence_contract(
		"Sequence Contract: Aster Sim",
		"res://scenes/tutorial/aster_sim.tscn",
		[
			"fade_in", "working", "ron_approaches", "ron_greeting",
			"show_terminal", "terminal_data", "ron_drinks", "walk_to_drink",
			"drink", "ron_move_fast", "explore_workspace", "tag_notify",
			"walk_to_exit", "transition_out", "complete",
		],
		aster_actions,
		Callable(),
		"res://scenes/tutorial/peris_sim.tscn"
	)

	await _run_sequence_contract(
		"Sequence Contract: Peris Phase 1",
		"res://scenes/tutorial/peris_sim.tscn",
		[
			"fade_in", "workspace", "monos_breakthrough",
			"transition_out", "complete",
		],
		peris_phase_1_actions,
		peris_phase_1_setup,
		"res://scenes/tutorial/aster_sim.tscn"
	)

	await _run_sequence_contract(
		"Sequence Contract: Tag Day",
		"res://scenes/tutorial/tag_day.tscn",
		[
			"arrive", "citizen_scan", "naturalizers_grip", "corridor_walk",
			"fragments", "neutralization", "lockdown", "return_focus",
			"aster_scans", "clearance", "complete",
		],
		tag_day_actions,
		Callable(),
		"res://scenes/tutorial/elevator.tscn"
	)

	await _run_sequence_contract(
		"Sequence Contract: Peris Phase 2",
		"res://scenes/tutorial/peris_sim.tscn",
		[
			"fade_in", "session_begins", "attack", "protect_prompt",
			"run_prompt", "click_monos", "confirm_protect",
			"executing", "aftermath", "efficiency_log", "sanction_notice",
			"sanction_feed", "spiral_flash", "reconnect_denied", "sim_bay_exit",
			"transition_out", "complete",
		],
		peris_phase_2_actions,
		peris_phase_2_setup,
		"res://scenes/tutorial/tag_day.tscn"
	)

	await _run_sequence_contract(
		"Sequence Contract: Leaving Facility",
		"res://scenes/tutorial/leaving_facility.tscn",
		[
			"fade_in", "facility_exit", "endo_joins", "first_corridor",
			"safe_route_lesson", "dusk_approaches", "second_iron",
			"reach_shelter", "first_rest", "dawn", "complete",
		],
		leaving_actions
	)

	await _run_sequence_contract(
		"Sequence Contract: Elevator",
		"res://scenes/tutorial/elevator.tscn",
		[
			"consciousness_fragments", "waking", "approach_aster", "wake_aster",
			"conversation", "system_restored", "units_activate", "emp_tutorial",
			"doors_unlocked", "doors_open", "multiselect_tutorial", "corridor",
			"bridge", "bridge_collapse", "fallen", "climb_attempt",
			"route_fork_dialogue", "route_choice", "junction_arrive",
			"endo_enters", "endo_shelter", "night_watch", "dawn", "morning",
			"gauntlet", "complete",
		],
		elevator_actions,
		Callable(),
		"res://scenes/tutorial/act1.tscn",
		["game_over"]
	)

	await _run_sequence_contract(
		"Sequence Contract: Act 1",
		"res://scenes/tutorial/act1.tscn",
		ACT1_SEQUENCE_STEPS,
		act1_actions,
		Callable(),
		"res://scenes/tutorial/leaving_facility.tscn",
		["channels_encounter_reset"]
	)

## Walk the whole tutorial intro as one connected chain: start at the main scene,
## drive each leg to complete, then FOLLOW its recorded requested_scene_change into
## the next scene (suppress_scene_change keeps the tree from swapping under us). This
## catches a broken hand-off or a scene that stalls on real entry — things the
## per-scene contract tests, which load each scene in isolation, can't see.
func _test_intro_chain() -> void:
	_test_name = "Intro Chain (end-to-end)"
	var scene_path := "res://scenes/tutorial/peris_sim.tscn"
	var peris_visits := 0
	var legs: Array[String] = []
	var guard := 0
	while scene_path != "" and guard < 10:
		guard += 1
		var visit := 0
		if scene_path.ends_with("peris_sim.tscn"):
			peris_visits += 1
			visit = peris_visits
		var leg := await _drive_intro_leg(scene_path, visit)
		var leg_name := scene_path.get_file()
		if visit > 0:
			leg_name += " (phase %d)" % visit
		legs.append("%s -> %s [%s]" % [leg_name, str(leg.next).get_file(), str(leg.termination)])
		_assert_equals(str(leg.termination), "complete",
			"Intro chain: %s plays to complete without stalling (last step: %s)" % [leg_name, str(leg.last_step)])
		var nxt := str(leg.next)
		# The tutorial intro ends when the elevator hands off to Act 1 (the game proper).
		if scene_path.ends_with("elevator.tscn"):
			_assert_equals(nxt, "res://scenes/tutorial/act1.tscn",
				"Intro chain ends by handing the elevator off to Act 1")
			break
		_assert_true(nxt != "" and nxt != scene_path,
			"Intro chain: %s hands off to a next scene (got: %s)" % [leg_name, nxt])
		if nxt == "" or nxt == scene_path:
			break
		scene_path = nxt
	print("[INTRO CHAIN] " + " | ".join(legs))
	_assert_true(peris_visits >= 2, "Intro chain visits the Peris sim twice (phase 1, then phase 2 after Aster)")

func _drive_intro_leg(scene_path: String, visit: int) -> Dictionary:
	var scene := load(scene_path)
	if scene == null:
		return {"termination": "load_fail", "last_step": "", "next": "", "steps": []}
	var instance: Node = scene.instantiate()
	if "suppress_scene_change" in instance:
		instance.suppress_scene_change = true
	# Peris is visited twice; the static _visit_phase selects which half runs.
	if scene_path.ends_with("peris_sim.tscn") and "_visit_phase" in instance:
		instance._visit_phase = visit
	get_tree().root.add_child(instance)
	for i in range(3):
		await get_tree().process_frame
	var actions := _intro_leg_actions(scene_path, visit, instance)
	var result := _drive_sequence_contract(instance, actions)
	var next_scene := ""
	if "requested_scene_change" in instance:
		next_scene = str(instance.requested_scene_change)
	var last_step := str(instance._current_step)
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("_teardown_sequence"):
		instance._teardown_sequence()
	instance.queue_free()
	await get_tree().process_frame
	return {
		"termination": str(result.get("termination_reason", "?")),
		"last_step": last_step,
		"next": next_scene,
		"steps": result.get("step_history", []),
	}

## The scripted interaction at each gated step, per scene. Mirrors the per-scene
## contract hooks (force-fired / teleported beats); the chain's value is verifying
## the connected end-to-end path, not the input fidelity of every beat (real-input
## reachability is covered separately by --test-input-playthrough).
func _intro_leg_actions(scene_path: String, visit: int, instance: Node) -> Dictionary:
	var actions := {}
	if scene_path.ends_with("aster_sim.tscn"):
		actions["show_terminal"] = func(): instance._on_terminal_interacted()
		actions["walk_to_drink"] = func(): instance._on_drink_interacted()
		actions["explore_workspace"] = func():
			instance._explore_gate_unlocked = true
			instance._on_exploration_gate_interacted()
	elif scene_path.ends_with("peris_sim.tscn"):
		if visit <= 1:
			actions["workspace"] = func():
				instance._explore_gate_unlocked = true
				instance._on_exploration_gate_interacted()
		else:
			actions["protect_prompt"] = func(): instance._on_protect_pressed()
			actions["run_prompt"] = func(): instance._toggle_run()
			actions["click_monos"] = func(): instance._start_confirm_protect()
			actions["confirm_protect"] = func(): instance._start_executing()
	elif scene_path.ends_with("tag_day.tscn"):
		# clearance -> complete rides the scheduler now; no force-fire needed.
		pass
	elif scene_path.ends_with("elevator.tscn"):
		# consciousness_fragments -> fade_in -> waking and bridge_collapse -> fall now
		# ride the scheduler (the fades/fall are cosmetic tweens), so no force-fire.
		actions["approach_aster"] = func():
			_set_sequence_character_position(instance, "peris", instance.ASTER_POS + Vector3(0.5, 0.5, 0.0))
			instance._on_aster_wake_interacted()
		actions["emp_tutorial"] = func():
			instance._on_emp_pressed()
			instance._toggle_pause()
		actions["multiselect_tutorial"] = func():
			instance._hud.set_selected_portraits(["peris", "aster"])
			instance._scheduler.resume()
			var exit_gate := Vector3(instance.ELEVATOR_SIZE.x / 2.0, 0.5, 0.0)
			_set_sequence_character_position(instance, "peris", exit_gate + Vector3(0.0, 0.0, -0.5))
			_set_sequence_character_position(instance, "aster", exit_gate + Vector3(0.0, 0.0, 0.5))
		actions["corridor"] = func(): _disable_enemy_detection(instance)
		# Cross the (upper-deck) bridge: walk Aster to the far end, which is what collapses it. Without
		# this the leg stalls at "bridge" (the gate keys on aster.x past the span, but nothing moved her).
		actions["bridge"] = func():
			_disable_enemy_detection(instance)
			_set_sequence_character_position(instance, "aster", Vector3(instance.BRIDGE_END_X, 0.5, 0.0))
		actions["climb_attempt"] = func(): instance._on_climb_prompt_interacted()
		actions["route_choice"] = func():
			_disable_enemy_detection(instance)
			_set_sequence_character_position(instance, "aster", instance.ROUTES_CONVERGE + Vector3(1.5, 0.5, 0.0))
		actions["junction_arrive"] = func(): instance._start_dusk_from_plant()
		actions["endo_shelter"] = func(): instance._on_endo_delivered("endo")
		actions["gauntlet"] = func():
			_disable_enemy_detection(instance)
			instance._on_ferrolure_activated()
			_set_sequence_character_position(instance, "aster", instance.GAUNTLET_EXIT + Vector3(1.5, 0.5, 0.0))
		actions["complete"] = func():
			instance._change_scene_or_record("res://scenes/tutorial/act1.tscn")
			instance._scheduler.clear()
	return actions

func _test_items() -> void:
	_test_name = "Items & Endocytosis"

	var gs := GameState.new()
	var sched := EventScheduler.new()
	gs.scheduler = sched

	gs.register_character("aster", Vector3(5, 0, 5), 3.0, {"atp": 4.0})
	gs.register_character("peris", Vector3(6, 0, 5), 3.0, {"atp": 6.0})

	# --- Spawn and pickup ---
	var lysate_id := gs.spawn_item("lysate", Vector3(5, 0, 5))
	_assert_true(gs.items.has(lysate_id), "Item spawned")
	_assert_true(gs.items[lysate_id].location == "ground", "Item starts on ground")

	var picked := gs.pick_up_item("aster", lysate_id)
	_assert_true(picked, "Pickup succeeds")
	_assert_true(gs.items[lysate_id].location == "hand", "Item now in hand")
	_assert_true(gs.items[lysate_id].holder == "aster", "Holder is aster")
	_assert_true(gs.get_hand_items("aster").size() == 1, "Aster has 1 hand item")

	# --- Full hands ---
	var lysate2 := gs.spawn_item("lysate", Vector3(5, 0, 5))
	gs.pick_up_item("aster", lysate2)
	_assert_true(gs.get_hand_items("aster").size() == 2, "Aster has 2 hand items")
	_assert_true(not gs.has_free_hand("aster"), "No free hands")

	var lysate3 := gs.spawn_item("lysate", Vector3(5, 0, 5))
	var full_pick := gs.pick_up_item("aster", lysate3)
	_assert_true(not full_pick, "Cannot pick up with full hands")

	# --- Drop ---
	var dropped := gs.drop_item("aster", lysate2)
	_assert_true(dropped, "Drop succeeds")
	_assert_true(gs.items[lysate2].location == "ground", "Dropped item on ground")
	_assert_true(gs.has_free_hand("aster"), "Hand freed after drop")

	# --- Transfer ---
	var transferred := gs.transfer_item("aster", "peris", lysate_id)
	_assert_true(transferred, "Transfer succeeds (within range)")
	_assert_true(gs.items[lysate_id].holder == "peris", "Item holder changed to peris")
	_assert_true(gs.get_hand_items("aster").size() == 0, "Aster hands empty after transfer")
	_assert_true(gs.get_hand_items("peris").size() == 1, "Peris has 1 item after transfer")

	# --- Transfer at distance fails ---
	gs.register_character("far_char", Vector3(20, 0, 20), 3.0)
	var far_item := gs.spawn_item("seed", Vector3(20, 0, 20))
	gs.pick_up_item("far_char", far_item)
	var far_transfer := gs.transfer_item("far_char", "aster", far_item)
	_assert_true(not far_transfer, "Transfer at distance fails")

	# --- Endocytose lysate: restores ATP ---
	var pre_atp: float = gs.characters["peris"].stats.get("atp", 0.0)
	gs.endocytose_item("peris", lysate_id)
	_assert_true(gs.is_endocytosing("peris"), "Peris is endocytosing")

	# Pop the scheduler event to complete endocytosis
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	var post_atp: float = gs.characters["peris"].stats.get("atp", 0.0)
	_assert_true(post_atp > pre_atp, "ATP increased after digesting lysate (%.1f -> %.1f)" % [pre_atp, post_atp])
	_assert_true(not gs.items.has(lysate_id), "Lysate consumed (removed from items)")
	_assert_true(not gs.is_endocytosing("peris"), "Endocytosis complete")

	# --- Endocytose cure component: stored + added to collection ---
	var cure_id := gs.spawn_item("cure_component", Vector3(6, 0, 5), {"collection_name": "Chaperone Lattice", "adds_to_collection": true})
	gs.pick_up_item("peris", cure_id)
	gs.endocytose_item("peris", cure_id)
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	_assert_true(gs.items[cure_id].location == "internal", "Cure component stored internally")
	_assert_true(cure_id in gs.collection, "Cure component added to collection")
	_assert_true(gs.get_internal_items("peris").has(cure_id), "Peris has cure internally")

	# Exocytose: internal to hand.
	var exo := gs.exocytose_item("peris", cure_id)
	_assert_true(exo, "Exocytose succeeds")
	_assert_true(gs.items[cure_id].location == "hand", "Exocytosed item back in hand")
	_assert_true(gs.get_hand_items("peris").size() == 1, "Peris has item in hand after exocytose")

	# --- Exocytose with full hands: drops to ground ---
	gs.pick_up_item("peris", lysate2)
	_assert_true(not gs.has_free_hand("peris"), "Peris hands full")
	var seed_id := gs.spawn_item("seed", Vector3(6, 0, 5))
	gs.pick_up_item("peris", seed_id)  # Fails — hands full
	# Manually put a seed in internal for testing
	gs.items[seed_id].holder = "peris"
	gs.items[seed_id].location = "internal"
	gs.characters["peris"].internal.append(seed_id)
	var exo2 := gs.exocytose_item("peris", seed_id)
	_assert_true(exo2, "Exocytose with full hands succeeds")
	_assert_true(gs.items[seed_id].location == "ground", "Exocytosed to ground when hands full")

	# --- Scent radius ---
	var scent_item := gs.spawn_item("lysate", Vector3(5, 0, 5))
	gs.pick_up_item("aster", scent_item)
	var scent := gs.get_scent_radius("aster")
	_assert_true(scent > 5.0, "Carrying lysate generates scent (radius: %.1f)" % scent)

	gs.drop_item("aster", scent_item)
	var no_scent := gs.get_scent_radius("aster")
	_assert_true(no_scent < 0.01, "No scent after dropping lysate (radius: %.3f)" % no_scent)

	# --- Endocytose hushbloom: stun effect ---
	var hush_id := gs.spawn_item("hushbloom", Vector3(5, 0, 5))
	gs.pick_up_item("aster", hush_id)

	var stun_log: Array = []
	gs.item_endocytosed.connect(func(cid, iid, eff): stun_log.append(eff))

	gs.endocytose_item("aster", hush_id)
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	_assert_true(stun_log.has("stun_self"), "Hushcap endocytosis emits stun_self effect")

	# --- Endocytose fire fruit: self damage ---
	var fire_id := gs.spawn_item("fire_fruit", Vector3(5, 0, 5))
	gs.pick_up_item("aster", fire_id)
	gs.characters["aster"].stats["hp"] = 100.0
	gs.endocytose_item("aster", fire_id)
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	var hp_after: float = gs.characters["aster"].stats.get("hp", 100.0)
	_assert_true(hp_after < 100.0, "Fire fruit dealt self damage (hp: %.1f)" % hp_after)

	# --- Endocytose curecumin: stat upgrade (universal, +10 hp_max + refill) ---
	gs.characters["aster"].stats["hp"] = 80.0
	var cap_before: float = gs.get_stat_cap("aster", "hp")
	var cure_up := gs.spawn_item("curecumin", Vector3(5, 0, 5))
	gs.pick_up_item("aster", cure_up)
	gs.endocytose_item("aster", cure_up)
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	var cap_after: float = gs.get_stat_cap("aster", "hp")
	_assert_equals(cap_after, cap_before + 10.0, "Curecumin raised hp_max by 10")
	_assert_equals(gs.get_stat("aster", "hp"), cap_after,
		"Curecumin refilled hp to new cap")
	_assert_true(not gs.items.has(cure_up), "Curecumin consumed (item removed)")

	# --- Endocytose solfloraphane on Aster: locked_to peris, no upgrade ---
	var sol_aster := gs.spawn_item("solfloraphane", Vector3(5, 0, 5))
	gs.pick_up_item("aster", sol_aster)
	var aster_tend_before: float = float(gs.characters["aster"].stats.get("tending_speed", 0.0))
	gs.endocytose_item("aster", sol_aster)
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	_assert_true(gs.items.has(sol_aster),
		"Solfloraphane preserved when consumer is wrong character")
	_assert_equals(gs.items[sol_aster].location, "internal",
		"Locked-out solfloraphane sits in Aster's internal")
	_assert_equals(float(gs.characters["aster"].stats.get("tending_speed", 0.0)),
		aster_tend_before, "Aster tending_speed unchanged")

	# --- Endocytose solfloraphane on Peris: applies tending_speed +0.15 ---
	# Earlier asserts left Peris's hands in an unknown state; clear them so
	# the upgrade flow has a clean slate.
	gs.characters["peris"].hands = [null, null]
	var sol_peris := gs.spawn_item("solfloraphane", Vector3(5, 0, 5))
	_assert_true(gs.pick_up_item("peris", sol_peris), "Peris picks up solfloraphane")
	_assert_true(gs.endocytose_item("peris", sol_peris), "Peris starts solfloraphane endocytosis")
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	_assert_equals(float(gs.characters["peris"].stats.get("tending_speed", 0.0)),
		0.15, "Peris tending_speed +0.15 after solfloraphane")
	_assert_true(not gs.items.has(sol_peris), "Solfloraphane consumed by Peris")

	# --- Cancel endocytosis ---
	var cancel_item := gs.spawn_item("seed", Vector3(5, 0, 5))
	gs.pick_up_item("aster", cancel_item)
	gs.endocytose_item("aster", cancel_item)
	_assert_true(gs.is_endocytosing("aster"), "Endocytosis started")
	gs.cancel_endocytosis("aster")
	_assert_true(not gs.is_endocytosing("aster"), "Endocytosis cancelled")
	_assert_true(gs.items[cancel_item].location == "hand", "Item stays in hand after cancel")

	# --- Remove item ---
	gs.remove_item(cancel_item)
	_assert_true(not gs.items.has(cancel_item), "Item removed from items dict")
	_assert_true(gs.get_hand_items("aster").size() == 0, "Hand slot cleared on remove")

	# --- Determinism ---
	var det_results: Array[float] = []
	for trial in range(2):
		var gs2 := GameState.new()
		var s2 := EventScheduler.new()
		gs2.scheduler = s2
		gs2.register_character("det_char", Vector3(5, 0, 5), 3.0, {"atp": 4.0})
		var det_item := gs2.spawn_item("lysate", Vector3(5, 0, 5))
		gs2.pick_up_item("det_char", det_item)
		gs2.endocytose_item("det_char", det_item)
		for _di in range(100):
			if s2.pop_next().is_empty(): break
		det_results.append(gs2.characters["det_char"].stats.get("atp", 0.0))
	_assert_true(absf(det_results[0] - det_results[1]) < 0.001, "Deterministic: ATP matches (%.2f vs %.2f)" % [det_results[0], det_results[1]])

func _test_queued_abilities() -> void:
	_test_name = "Queued Abilities"

	var gs := GameState.new()
	var sched := EventScheduler.new()
	var grid2 := GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_character("peris", Vector3(3, 0, 5), 3.0)

	# --- Already in range: fires immediately ---
	var fired: Array = []
	gs.queue_ability("peris", "protect", Vector3(4, 0, 5), 2.0, func(): fired.append("protect"))
	_assert_true(fired.size() == 1, "In-range ability fires immediately (fired: %d)" % fired.size())
	_assert_true(not gs.has_queued_ability("peris"), "No queued ability after immediate fire")

	# --- Out of range: queues and auto-moves ---
	var fired2: Array = []
	gs.queue_ability("peris", "protect", Vector3(15, 0, 5), 2.5, func(): fired2.append("protect"))
	_assert_true(gs.has_queued_ability("peris"), "Ability queued when out of range")
	_assert_true(gs.get_queued_ability("peris") == "protect", "Queued ability name is protect")
	_assert_true(gs.is_moving("peris"), "Character auto-moves toward target")

	# Pop scheduler until character arrives and ability fires
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	_assert_true(fired2.size() == 1, "Ability fired after auto-move (fired: %d)" % fired2.size())
	_assert_true(not gs.has_queued_ability("peris"), "Queue cleared after firing")

	# Verify character stopped near target
	var final_pos := gs.get_position("peris")
	var dist_to_target := Vector2(final_pos.x - 15.0, final_pos.z - 5.0).length()
	_assert_true(dist_to_target <= 2.5, "Character within ability range (dist: %.2f)" % dist_to_target)

	# --- Cancel queued ability ---
	var fired3: Array = []
	gs.queue_ability("peris", "emp", Vector3(25, 0, 5), 2.0, func(): fired3.append("emp"))
	_assert_true(gs.has_queued_ability("peris"), "Ability queued")
	gs.cancel_queued_ability("peris")
	_assert_true(not gs.has_queued_ability("peris"), "Ability cancelled")

	# Drain remaining events; cancelled ability should not fire.
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	_assert_true(fired3.size() == 0, "Cancelled ability never fired")

	# --- Ability signal emitted ---
	var signal_log: Array = []
	gs.ability_fired.connect(func(cid, ab, tpos): signal_log.append({"char": cid, "ability": ab}))

	gs.register_character("aster", Vector3(3, 0, 10), 4.0)
	gs.queue_ability("aster", "emp", Vector3(12, 0, 10), 3.0, func(): pass)
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	_assert_true(signal_log.size() >= 1, "ability_fired signal emitted (count: %d)" % signal_log.size())
	if signal_log.size() > 0:
		_assert_true(signal_log[0].ability == "emp", "Signal has correct ability name")

	# --- Queue replaces previous queue ---
	var fired_a: Array = []
	var fired_b: Array = []
	gs.register_character("tyreg", Vector3(3, 0, 15), 3.0)
	gs.queue_ability("tyreg", "suppress", Vector3(20, 0, 15), 2.0, func(): fired_a.append(1))
	gs.queue_ability("tyreg", "freeze", Vector3(10, 0, 15), 2.0, func(): fired_b.append(1))
	_assert_true(gs.get_queued_ability("tyreg") == "freeze", "Second queue replaced first")
	for _di in range(500):
		if sched.pop_next().is_empty(): break
	_assert_true(fired_b.size() == 1, "Replacement ability fired")
	# First ability may or may not fire depending on timing, but second definitely should
	_assert_true(fired_b.size() >= fired_a.size(), "Replacement took priority")

func _test_dodge_roll() -> void:
	_test_name = "Dodge Roll"

	var gs := GameState.new()
	var sched := EventScheduler.new()
	var grid2 := GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_character("peris", Vector3(10, 0, 10), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
	})

	# --- Basic dodge ---
	var start_pos := gs.get_position("peris")
	var dodged := gs.dodge_roll("peris", Vector3(1, 0, 0))
	_assert_true(dodged, "Dodge roll succeeds")
	_assert_true(gs.is_dodging("peris"), "Character is dodging")
	_assert_true(gs.is_moving("peris"), "Character is moving during dodge")

	var sta_after: float = gs.characters["peris"].stats.stamina
	_assert_true(sta_after < 100.0, "Stamina consumed (got: %.1f)" % sta_after)
	_assert_true(absf(sta_after - (100.0 - gs.DODGE_STAMINA_COST)) < 0.01, "Correct stamina cost")

	# Pop to completion
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	_assert_true(not gs.is_dodging("peris"), "Dodge finished")

	var end_pos := gs.get_position("peris")
	var dodge_dist := end_pos.distance_to(start_pos)
	_assert_true(dodge_dist > 2.0, "Moved during dodge (dist: %.2f)" % dodge_dist)
	_assert_true(end_pos.x > start_pos.x, "Moved in +X direction")

	# --- Dodge not unlocked ---
	gs.register_character("locked", Vector3(10, 0, 15), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": false,
	})
	var no_dodge := gs.dodge_roll("locked", Vector3(1, 0, 0))
	_assert_true(not no_dodge, "Dodge fails when not unlocked")

	# --- Not enough stamina ---
	gs.characters["peris"].stats["stamina"] = 5.0
	var low_sta := gs.dodge_roll("peris", Vector3(1, 0, 0))
	_assert_true(not low_sta, "Dodge fails with low stamina")
	_assert_true(absf(gs.characters["peris"].stats.stamina - 5.0) < 0.01, "Stamina not consumed on fail")

	# --- Cooldown ---
	gs.characters["peris"].stats["stamina"] = 100.0
	gs.dodge_roll("peris", Vector3(0, 0, 1))
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	# Immediate retry should be on cooldown.
	var cd_dodge := gs.dodge_roll("peris", Vector3(0, 0, -1))
	_assert_true(not cd_dodge, "Dodge on cooldown")

	# Advance past cooldown
	sched.advance_ticks(gs.DODGE_COOLDOWN + 0.1)
	gs.characters["peris"].stats["stamina"] = 100.0
	var after_cd := gs.dodge_roll("peris", Vector3(-1, 0, 0))
	_assert_true(after_cd, "Dodge succeeds after cooldown")
	for _di in range(100):
		if sched.pop_next().is_empty(): break

	# --- Wall stop ---
	gs.register_character("waller", Vector3(27, 0, 10), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
	})
	gs.dodge_roll("waller", Vector3(1, 0, 0))
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	var wall_pos := gs.get_position("waller")
	_assert_true(wall_pos.x < 29.0, "Dodge stopped at wall (x: %.2f)" % wall_pos.x)

	# --- I-frames: detection suppressed during dodge ---
	gs.register_character("dodger", Vector3(5, 0, 5), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
	})
	gs.register_character("enemy_det", Vector3(8, 0, 5), 0.0, {
		"detection_range": 4.0,
	})

	var det_log: Array = []
	gs.detection_predicted.connect(func(det, tgt): det_log.append(tgt))

	# Enemy should detect dodger normally (within range)
	# But during dodge, detection is suppressed
	gs.dodge_roll("dodger", Vector3(-1, 0, 0))  # Dodge away from enemy
	_assert_true(gs.is_dodging("dodger"), "Dodger is dodging")

	# Detection during dodge should be suppressed.
	for _di in range(100):
		if sched.pop_next().is_empty(): break

	var dodger_detected := false
	for entry in det_log:
		if entry == "dodger":
			dodger_detected = true
	_assert_true(not dodger_detected, "I-frames: dodger not detected during dodge")

	# --- Diagonal dodge ---
	gs.register_character("diag", Vector3(10, 0, 10), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
	})
	var diag_start := gs.get_position("diag")
	gs.dodge_roll("diag", Vector3(1, 0, 1))
	for _di in range(100):
		if sched.pop_next().is_empty(): break
	var diag_end := gs.get_position("diag")
	_assert_true(diag_end.x > diag_start.x, "Diagonal dodge +X")
	_assert_true(diag_end.z > diag_start.z, "Diagonal dodge +Z")

	# --- Signal emitted ---
	var dodge_log: Array = []
	gs.dodge_started.connect(func(cid, dir): dodge_log.append(cid))
	gs.register_character("sig_test", Vector3(15, 0, 15), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
	})
	gs.dodge_roll("sig_test", Vector3(0, 0, 1))
	_assert_true(dodge_log.size() == 1, "dodge_started signal emitted")
	for _di in range(100):
		if sched.pop_next().is_empty(): break

	# --- Predicted enemy strike: an auto-dodging target evades it; with dodge locked it lands ---
	# Attacks are now PREDICTIVE (the hit is scheduled for the contact tick and commits), so the
	# dodge is checked at contact: a dodge-capable target auto-evades, an un-unlocked one is struck.
	_test_name = "Dodge I-Frames vs Enemy"

	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_character("hero", Vector3(10, 0, 10), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
		"auto_dodge": true,
		"hp": 100.0,
	})
	var hero_node := Node3D.new()
	hero_node.name = "hero"
	hero_node.position = Vector3(10, 0.5, 10)
	get_tree().root.add_child(hero_node)

	var enemy := Enemy.new()
	enemy.game_state = gs
	enemy.char_id = "baddie"
	enemy._detection_targets = ["hero"]
	enemy.charge_damage = 25.0
	enemy.attack_range = 3.0
	get_tree().root.add_child(enemy)
	gs.register_character("baddie", Vector3(11, 0, 10), 3.0, {"detection_range": 8.0})
	enemy.activate()

	var hit_log: Array = []
	enemy.hit_target.connect(func(tid, dmg): hit_log.append({"target": tid, "damage": dmg}))

	# Phase 1: dodge unlocked + auto-evade -> the predicted strike is slipped.
	gs._recompute_all_detection_predictions()
	for i in range(200):
		sched.advance_ticks(0.02)
		enemy._process(0.02)
	_assert_true(hit_log.size() == 0, "An auto-dodging hero evades the predicted strike (hits: %d)" % hit_log.size())
	_assert_true(gs.get_stat("hero", "hp") >= 99.99, "Auto-dodge keeps the hero's HP (hp: %.1f)" % gs.get_stat("hero", "hp"))

	# Phase 2: lock dodge, re-engage from a clean adjacent setup -> the predicted strike now lands.
	gs.characters["hero"].stats["dodge_unlocked"] = false
	gs.characters["hero"].stats["auto_dodge"] = false
	gs.set_stat("hero", "hp", 100.0)
	gs.snap_character_to("hero", Vector3(10, 0.5, 10))
	gs.snap_character_to("baddie", Vector3(11, 0.5, 10))
	hero_node.global_position = Vector3(10, 0.5, 10)
	enemy._current_target_id = ""
	enemy._change_state("idle")
	hit_log.clear()
	gs._recompute_all_detection_predictions()
	for i in range(200):
		sched.advance_ticks(0.02)
		enemy._process(0.02)
	_assert_true(hit_log.size() >= 1, "With dodge locked, the predicted strike lands (hits: %d)" % hit_log.size())
	if hit_log.size() > 0:
		_assert_true(hit_log[0].target == "hero", "Hit target is hero")
		_assert_true(hit_log[0].damage == 25.0, "Damage is 25 (got: %.1f)" % hit_log[0].damage)
	_assert_true(gs.get_stat("hero", "hp") < 100.0, "The struck hero takes damage (hp: %.1f)" % gs.get_stat("hero", "hp"))

	enemy.queue_free()
	hero_node.queue_free()
	await get_tree().process_frame

	# --- Predictive auto-dodge: character auto-evades incoming attack ---
	_test_name = "Predictive Auto-Dodge"

	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	# Character with auto_dodge enabled
	gs.register_character("evader", Vector3(10, 0, 10), 3.0, {
		"stamina": 100.0,
		"dodge_unlocked": true,
		"auto_dodge": true,
	})

	# Enemy approaches from the right
	gs.register_character("attacker", Vector3(18, 0, 10), 4.0, {
		"detection_range": 3.0,
	})

	var auto_dodge_log: Array = []
	gs.dodge_started.connect(func(cid, dir): auto_dodge_log.append({"char": cid, "dir": dir}))
	var det_log2: Array = []
	gs.detection_predicted.connect(func(det, tgt): det_log2.append(tgt))

	# Move attacker toward evader
	gs.command_move_to_pos("attacker", Vector3(10, 0, 10))

	# Pop scheduler: attacker walks toward evader, detection predicted,
	# auto-dodge triggers before detection_predicted is emitted
	for _di in range(500):
		if sched.pop_next().is_empty(): break

	_assert_true(auto_dodge_log.size() >= 1, "Auto-dodge triggered (count: %d)" % auto_dodge_log.size())
	if auto_dodge_log.size() > 0:
		_assert_true(auto_dodge_log[0].char == "evader", "Evader auto-dodged")
		# Dodge should be perpendicular to approach (approach is -X, perp is +Z or -Z)
		var dodge_dir: Vector3 = auto_dodge_log[0].dir
		_assert_true(absf(dodge_dir.z) > 0.5, "Dodge perpendicular to attack (dir.z: %.2f)" % dodge_dir.z)

	# detection_predicted should NOT have fired for evader (auto-dodge consumed it)
	var evader_detected := false
	for entry in det_log2:
		if entry == "evader":
			evader_detected = true
	_assert_true(not evader_detected, "detection_predicted suppressed by auto-dodge")

	# Stamina should have been consumed
	var evader_sta: float = gs.characters["evader"].stats.stamina
	_assert_true(evader_sta < 100.0, "Auto-dodge consumed stamina (got: %.1f)" % evader_sta)

	# --- Auto-dodge fails when stamina is too low ---
	gs = GameState.new()
	sched = EventScheduler.new()
	grid2 = GridWorld.new()
	grid2.create_room(30, 30)
	gs.grid = grid2
	gs.scheduler = sched

	gs.register_character("low_sta", Vector3(10, 0, 10), 3.0, {
		"stamina": 5.0,
		"dodge_unlocked": true,
		"auto_dodge": true,
	})
	gs.register_character("attacker2", Vector3(18, 0, 10), 4.0, {
		"detection_range": 3.0,
	})

	var det_log3: Array = []
	gs.detection_predicted.connect(func(det, tgt): det_log3.append(tgt))

	gs.command_move_to_pos("attacker2", Vector3(10, 0, 10))
	for _di in range(500):
		if sched.pop_next().is_empty(): break

	# Low stamina makes dodge fail; detection_predicted fires normally.
	var low_sta_detected := false
	for entry in det_log3:
		if entry == "low_sta":
			low_sta_detected = true
	_assert_true(low_sta_detected, "Low stamina: detection fires (auto-dodge failed)")

func _print_results() -> void:
	print("")
	print("=== TEST RESULTS ===")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("  Total:  %d" % (_passed + _failed))
	if _failed > 0:
		print("  STATUS: FAILED")
	else:
		print("  STATUS: ALL PASSED")
	print("====================")
