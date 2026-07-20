# Test Audit — full per-test classification tables

Raw data behind TEST_AUDIT.md. Format: `name | line | what it checks | CLASS | VERDICT | seeded | note`.
Rubric and verdict definitions live in TEST_AUDIT.md. Indented `scene:` rows break the giant
scene tests into assertion groups with their own verdicts.

## Part A — lines 1584-9700 (generation, roguelike, intro playthroughs)

```
_test_syntax | 1584 | GDScript compiles; UI-scene lint; exact dialogue-draft strings | GUARD | RESHAPE | na | split out exact-string asserts = MIRROR churn; keep compile + UI lint
_test_scene_load | 1758 | scenes/chunks/previews load+instantiate, shared-GUI/overlay/ability wiring | GUARD | KEEP | na | lifecycle/load + "no embedded GUI" lint
_test_all_scenes_load | 1848 | auto-discover every .tscn loads+instantiates | GUARD | KEEP | na | a newly-added scene can never go untested
_test_scene_spatial_consistency | 1897 | chars/interactables on finite in-bounds walkable cells | GUARD | KEEP | na | catches spawn-inside-wall / off-grid
_test_occlusion_fade | 1966 | occlusion shader preserves albedo, syncs player uniform | GUARD | KEEP | na | render feature contract
_test_archetype_generation | 2216 | generator determinism, budgets, composition metadata, connectivity | GUARD | RESHAPE | y | keep determinism + entry-exit + golden playable; drop composition-metadata MIRROR
_test_generated_multi_solution | 2707 | puzzle stretches solvable two ways; bare-pair always solves | BEHAVIOR | KEEP | y | universal-solvability design law
_test_generated_replay | 2862 | replay projects nodes/routes/content; two loadouts | GUARD | KEEP | y | replay/determinism first-class
_test_campaign_order | 2940 | campaign-tree CRUD, cycle guard, validation, JSON roundtrip | GUARD | KEEP | na | real validation logic
_test_roompiece_catalog | 3070 | catalog validates; socket-compat truth table; rotation closure | GUARD | KEEP | na | rotation/socket math real
_test_biomes | 3125 | biome palette restriction, connectivity, solvable; landmark assets | GUARD | RESHAPE | y | keep palette-restrict + connects + solvable; asset-existence + tile-distinctness = LAYOUT
_test_poi_distribution | 3322 | element-content coverage, density scales w/ stage, solvable | GUARD | KEEP | y | coverage-honesty is the core; density overlaps curriculum-ramp
_test_poi_determinism | 3384 | element coverage + density reproducible from seed | GUARD | KEEP | y | determinism guard
_test_wfc_layout | 3401 | WFC placements per node, determinism, stitched grid connects | GUARD | KEEP | y | determinism + entry-exit
_test_shape_grammar | 3484 | fragment valid/determ/varies, connectivity every seed, weak-wall kill | GUARD | RESHAPE | y | determinism+connectivity KEEP; live legs are de-facto playthroughs
_test_district_volume | 3737 | volume-claim conflict/audit; live deck walk, sentry, silo | GUARD | RESHAPE | y | conflict-audit KEEP; live legs de-facto playthroughs
_test_building_filler_programs | 3959 | program mix+determinism; per-program glow-count signatures | LAYOUT | RESHAPE | y | glow-count signatures aesthetic; keep determinism/mix
_test_building_filler | 4046 | filler appends-only, determinism, placement law, cohesion | LAYOUT | RESHAPE | y | keep determinism + never-removes-walkable + street-clearance; aesthetics out
_test_sight_mask_bake | 4335 | sight mask bakes walls/floor; warped levels skip baked mask | GUARD | KEEP | y | documented spiral-vision bug
_test_project_hygiene | 4416 | root/data unpolluted | GUARD | KEEP | na | enforced lint per CLAUDE.md
_test_architecture_showcase | 4447 | base-shape massing/proportions; lattices watertight; boots | LAYOUT | RESHAPE | y | keep watertight boundary_edge_count==0; massing/proportion aesthetic
_test_building_survey | 4848 | buildings survey clean; RED collision cases; detail families | LAYOUT | RESHAPE | y | keep validate()-goes-RED; "builds the X pass" families are MIRROR
_test_center_camera | 5409 | recenter/lock-noop; center key routes to party centroid | BEHAVIOR | KEEP | na | real input path
_test_creature_grammar | 5478 | archetypes mesh grounded/finite; determinism; closed 2-manifold | GUARD | KEEP | y | manifold law documents bug class
_test_roguelike_run | 5627 | roguelike entry config; each descent generates connected level | GUARD | FOLD | y | subsumed by run_session_e2e + loader_descent
_test_run_branch_decisions | 5679 | branch = 2 risk-ranked options; recruit order; determinism | BEHAVIOR | KEEP | y | meta-choice structure
_test_run_economy | 5751 | fork: richer wins clean, leaner wins sloppy, crossover | BEHAVIOR | KEEP | y | neither-branch-dominates guarantee
_test_generated_traversible | 5836 | flood from entry: every walkable cell + node reachable | BEHAVIOR | KEEP | y | reachable==visible invariant
_test_generated_stretch_quality | 5910 | corridor widths vary, party spawns on stretch, floor collision | BEHAVIOR | KEEP | y | encodes user-flagged bugs
_test_generated_food_modes | 6114 | three modes on one level; pickup, scarcity, shelter restore | BEHAVIOR | KEEP | y | de-facto seeded playthrough
_test_generated_stretch_walk | 6414 | real ground click walks player across generated floor | BEHAVIOR | KEEP | y | catches can't-walk-on-floor
_test_grid_ascii | 6465 | render spec-ASCII; render-parse lossless roundtrip | GUARD | KEEP | y | interchange roundtrip
_test_main_menu | 6517 | menu loads, buttons target real scenes, boots into menu | GUARD | KEEP | na | entry-point wiring
_test_builder | 6574 | builder paints floor, ASCII roundtrips, level traversable | BEHAVIOR | KEEP | na | builder-to-playable pipeline
_test_builder_touch | 6610 | one-finger paint, two-finger pan/pinch via synthetic touch | GUARD | KEEP | na | real touch-input coverage
_test_ascii_to_playable | 6655 | authored ASCII boots; real click walks player | BEHAVIOR | KEEP | na | author-load-walk end-to-end
_test_run_session_e2e | 6746 | full run: generate/descend/recruit; boot+walk to exit | BEHAVIOR | KEEP | y | canonical seeded playthrough — the target model
_test_roguelike_loader_descent | 6830 | branch modal, recruit reload, depth advance, seam teardown | GUARD | KEEP | y | lifecycle: freed-node + coord_map seam bugs
_test_curriculum_ramp | 6949 | stage raises causal complexity not geometry; solvable every stage | BEHAVIOR | KEEP | y | curriculum directive
_test_character_roster | 7114 | six characters; disabling combat changes solvability | BEHAVIOR | KEEP | y | roster-aware solvability
_test_archetype_coherence | 7170 | archetypes >=2 variants; nodes cohere; repeats vary | BEHAVIOR | KEEP | y | generation coherence
_test_survival_archetypes | 7249 | 5 survival archetypes; solvable; golden run banks/attrites | BEHAVIOR | KEEP | y | partial playthrough
_test_generated_stretch_playtest_loop | 7311 | generate+playtest: event timeline, golden/risky | BEHAVIOR | KEEP | y | de-facto seeded playthrough
_test_asset_pipeline | 7606 | tool files exist; exact shader substrings; pixel counts | MIRROR | RESHAPE | na | keep file-exists + emissive-nonzero; shader-string/pixel-count churn
_test_mother_flure_preview | 8019 | drives Mother Flure puzzle to complete | BEHAVIOR | KEEP | na | full puzzle playthrough
_test_endo_junction_stretch_preview | 8225 | drives Endo stretch to complete, safe+direct | BEHAVIOR | KEEP | na | full playthrough both routes
_test_endo_junction_stretch_act1 | 8427 | same chunk runs inside act1 to complete | BEHAVIOR | KEEP | na | chunk-host lifecycle in real scene
_test_event_scheduler | 8817 | schedule/cancel/tag/speed/pause/priority/serialize | GUARD | KEEP | na | core scheduler + WASM null-trap discard
_test_engram_and_saves | 8950 | engram entry/bookmark/export; save/load roundtrip | GUARD | KEEP | na | persistence roundtrip
_test_tag_day | 9005 | Tag Day loads; nodes; dialogue keys; corridor walk | GUARD | RESHAPE | na | node/key asserts MIRROR; completion covered by ff-invariance + realinput-core
_test_aster_playthrough | 9106 | drives Aster sim to complete via data layer | BEHAVIOR | KEEP | na | canonical data-layer playthrough
_test_input_playthrough | 9246 | Peris-1 + Aster first gate via synthetic Input | BEHAVIOR | KEEP | na | first-class real-input; catches unreachable-gate stall
_test_fast_forward_invariance | 9482 | Tag Day 1x vs 10x same steps + completion | GUARD | KEEP | na | fast-forward invariance
_test_puzzle_fast_forward_invariance | 9548 | timing puzzles 1x vs 10x identical verdict | GUARD | KEEP | na | analytic-prediction lesson
_test_intro_realinput | 9622 | runs all real-input legs | BEHAVIOR | KEEP | na | orchestrator; Peris-1 leg duplicates input_playthrough
_test_intro_realinput_core | 9638 | Peris-2 + Tag Day real-input to complete | BEHAVIOR | KEEP | na | first-class real-input core
_test_elevator_realinput | 9653 | Elevator full descent real-input to complete | BEHAVIOR | KEEP | na | RIGHT-click command lesson
```

## Part B — lines 9700-19500 (dialogue, UI, scenes, preview/overlay)

```
_test_dialogue_pause_chain | 10320 | UI dialogue clock advances while gameplay paused | GUARD | KEEP | na | two-lane pause invariant
_test_settings | 10393 | preset mapping, ConfigFile+rebind persistence, keymap | GUARD | RESHAPE | na | InputMap snapshot/restore KEEP; verbatim keycap labels MIRROR
_test_dialogue_pagination | 10681 | long line paginates; signals fire once per logical line | GUARD | KEEP | na | once-per-line contract
_test_dialogue_cutscene_mode | 10737 | cutscene mode forces auto-advance on wait lines | GUARD | KEEP | na | cinematic never blocks
_test_interactable_highlight | 10933 | SHIFT outline; dwell ownership; late body-exit no-op | GUARD | KEEP | na | hard-won hover/dwell bugs
_test_preview_highlight_wired | 11185 | preview HUD wires hold-SHIFT reveal via base handler | GUARD | KEEP | na | copy-paste drift bug
_test_pause_menu | 11230 | opens/closes, pauses tree, drives Settings | GUARD | KEEP | na | real UI lifecycle
_test_aster_sim | 11276 | tutorial scene mega-test | mixed | RESHAPE | na | groups below
  aster_sim: node/controller/catalog existence (11288-11317) | MIRROR | FOLD | subsumed by any boot
  aster_sim: step gating, terminal re-read, drink wave-off (11318-11382) | BEHAVIOR | KEEP | real progression
  aster_sim: 23 markers + <0.01 alignment tolerances (11448-11543) | LAYOUT | RESHAPE | keep walkable/clearance only
  aster_sim: outline particle/duration tuning (11557-11731) | LAYOUT | RESHAPE | aesthetic constants
  aster_sim: exact DialogueData strings (11609-11662) | MIRROR | RETIRE | ~50 verbatim-line asserts
  aster_sim: exploration click matrix (11683-11898) | BEHAVIOR | FOLD | force-snapped; fold into playthrough
_test_peris_sim | 11904 | tutorial scene mega-test ~458 asserts | mixed | RESHAPE | na | groups below
  peris_sim: binder validate + occupancy + walkable (11921-11974) | GUARD | KEEP | silent bind failures loud
  peris_sim: plants rest-on-table y<=0.015, blocks cell (12000-12026) | LAYOUT | RESHAPE | keep only table-blocks-grid
  peris_sim: decor presence roster (12027-12036) | LAYOUT | RETIRE | aesthetic composition roster
  peris_sim: zone contract + 1.2m spacing (12045-12093) | LAYOUT | RESHAPE | spacing minimum is authored
  peris_sim: inspection focus lifecycle (12097-12149) | BEHAVIOR | KEEP | exact camera offset is MIRROR
  peris_sim: phase-2 live loop reaches sanction (12181-12235) | BEHAVIOR | KEEP | real _process loop catches stalls
  peris_sim: 12-zone click matrix (12342-12371) | BEHAVIOR | FOLD | force-triggered
_test_ability_data | 12644 | xlsx ability loader round-trips | MIRROR | RESHAPE | na | loader guard fine; exact values mirror sheet
_test_grid_port_robustness | 12690 | cross-deck click rejected; grid swap no strand | GUARD | KEEP | na | adversarial real path
_test_act1_chunk_grids | 12764 | each chunk swaps grid; player walks it | GUARD | KEEP | na | stale-grid strand guard
_test_act1_prepare_fragment_grids | 12814 | prepare_* entry sets up grid like enter fns | GUARD | RESHAPE | na | merge with act1_chunk_grids
_test_elevator_fall_level | 12863 | collapse is real cross-level, KIND_SET_LEVEL logged | GUARD | KEEP | na | replay reproduces
_test_elevator_bridge_collapse | 12906 | walk fires collapse; ecology below never pursues | GUARD | RESHAPE | na | keep trigger/no-pursuit/pause; piece counts LAYOUT
_test_elevator_camera_after_collapse | 13140 | collapse restores camera offset | GUARD | KEEP | na | camera-stuck-low bug
_test_chunk_streaming | 13202 | prewarm/incremental; dormant fauna until reveal | GUARD | KEEP | na | streaming lifecycle
_test_elevator_distracted_fauna | 13372 | distracted fauna ignores mid-range, chases close | BEHAVIOR | KEEP | na | real detection mechanic
_test_elevator_box_select_multiselect | 13461 | held-COMMAND rally; selection stays singleton | BEHAVIOR | KEEP | na | rally pill guard
_test_elevator_enemy_performance | 13543 | deterministic AI budgets; dormant=0; reveal<750ms | PERF | KEEP | na | wall-clock ceiling soft
_test_elevator_wreckage_gate | 13652 | two-person gate; solo fails+alerts; revalidates | BEHAVIOR | KEEP | na | reproduce-first
_test_elevator | 13805 | full tutorial mega-test | mixed | RESHAPE | na | groups below
  elevator: node existence + EMP visuals + faceplates (13820-13851) | MIRROR | FOLD | scene smoke
  elevator: wake zone dwell/teardown (13863-13886) | BEHAVIOR | KEEP | real dwell gate
  elevator: escort choreography + EMP standoff (13888-13936) | BEHAVIOR | KEEP | no-touch invariant
  elevator: EMP visuals + rally + stale reboot (13937-14025) | BEHAVIOR | RESHAPE | keep rally/reboot; light thresholds LAYOUT
  elevator: iron cadence + safe-route overlay (14078-14260) | BEHAVIOR | KEEP | one-bite-per-tick; footprint counts RESHAPE
  elevator: wreckage/junction/gauntlet gates (14262-14442) | BEHAVIOR | KEEP | real movement gates
_test_leaving_facility | 14484 | scene loads; Aster walks east | BEHAVIOR | FOLD | na | subsume in playthrough
_test_showcase | 14527 | station lanes drive mechanics | BEHAVIOR | KEEP | n | overlaps dedicated tests
_test_puzzle_fragments | 14693 | data catalog: every scenario passes; schema covers | BEHAVIOR | KEEP | na | THE seeded-scenario model
_test_puzzle_outcome_coverage | 14776 | outcome stretches show success+failure; floor 20 | GUARD | KEEP | na | floor number brittle
_test_overlay_facility_gating | 14811 | Aster overlay lit in facility, dark past junction | BEHAVIOR | KEEP | na | design D12
_test_day_night_cycle | 15848 | clock advance math, phase labels | GUARD | KEEP | na | deterministic clock
_test_survival_range_timing | 15886 | route timing predicted vs measured; refusals | BEHAVIOR | KEEP | na | seeded-style end-to-end
_test_grid_pathfinding | 16105 | room/walls/path/gaps/no-path/round-trip | GUARD | KEEP | na | foundational
_test_cooperative_pathfinding | 16229 | space-time reservations; determinism+FF-invariant | GUARD | KEEP | na | core invariant
_test_path_renderer | 16439 | route geometry + caching; running tint | GUARD | KEEP | na | per-frame re-warp perf bug
_test_path_render_manager | 16565 | path per moving char; ghost regressions | GUARD | KEEP | na | reproduce-first render bugs
_test_camera_occlusion | 16780 | global uniform registered; apply_to keeps albedo | GUARD | KEEP | na | render laws
_test_grid_levels | 16859 | multi-level ladders/cross-floor A*; replay | GUARD | KEEP | na | one logged command law
_test_state_machine | 17003 | FSM hooks, scheduler transitions, FF-invariant | GUARD | KEEP | na | determinism
_test_story_beats | 17061 | beat runner lifecycle; validation | GUARD | KEEP | na | authoring-error validation
_test_elevator_enemy_engagement | 17195 | fork-lane enemy detect/lock/pursue/attack | BEHAVIOR | KEEP | na | data-layer combat
_test_hidden_detection | 17232 | hidden invisible point-blank; revealed spotted | BEHAVIOR | KEEP | na | stealth foundation
_test_distract_gate | 17283 | LOS honesty, real gate, lure solve, expiry | BEHAVIOR | KEEP | na | full puzzle via real mechanics
_test_lure_relay_puzzle | 17430 | intended solve; cheese fails; overshoot fix | BEHAVIOR | KEEP | na | puzzle playthrough
_test_two_tier_detection | 17552 | hide tier sets spot distance | BEHAVIOR | KEEP | na | detection mechanic
_test_detection_los | 17591 | wall blocks the spot | BEHAVIOR | KEEP | na | no seeing through walls
_test_enemy_roaming | 17624 | roam bounded, FF-invariant, still sees targets | GUARD | KEEP | na | tick-locked wander
_test_fragment_preview_registry | 17712 | picker/CHUNK_SCENES lockstep; labs complete | GUARD | KEEP | na | anti-drift
_test_data_fragment_loader | 17783 | .tres composes real modular classes | BEHAVIOR | KEEP | na | loader drives real mechanics
_test_preview_party_move | 17831 | party move fans members; single-select solo | BEHAVIOR | KEEP | na | overlaps party_preview_renderers
_test_preview_path_render | 17870 | path renderer draws in preview | GUARD | RESHAPE | na | merge with siblings
_test_preview_hover_grid | 17906 | hover grid polls/snaps; Decal tight | GUARD | KEEP | na | stacks overlay bug
_test_hover_grid_alignment | 17998 | overlay snaps to data-grid cell center | GUARD | KEEP | na | half-cell out-of-phase bug
_test_characters_grounded | 18066 | characters stand on measured floor top | GUARD | KEEP | na | floating bug
_test_preview_ribbon_grounded | 18110 | ribbon above floor; inherits anchor level | GUARD | KEEP | na | under-floor bug
_test_hover_grid_edge_fade | 18156 | hover patch fades center-to-rim | LAYOUT | RESHAPE | na | aesthetic fade
_test_ron_warp_in | 18182 | Ron spawns via resolver, walkable, grounded | GUARD | KEEP | na | spawn resolver
_test_aster_hover_outline | 18220 | scene enables physics picking for hover | GUARD | KEEP | na | picking-off-by-default bug
_test_terminal_front_focus | 18249 | screen focus frames monitor front | GUARD | KEEP | na | wrong-axis framing bug
_test_terminal_queued_glow | 18303 | committing terminal lights queued glow | GUARD | KEEP | na | terminal-lacked-glow bug
_test_grid_nearest_walkable_world | 18347 | wall spot snaps walkable+grounded | GUARD | KEEP | na | no wall spawns
_test_preview_pathfinding | 18370 | preview path read-only, deterministic | GUARD | KEEP | na | replay-safe hover
_test_peris_furniture_uvs | 18427 | transparent-atlas UVs stay in [0,1] | GUARD | KEEP | na | black-checker void lint
_test_overlay_materials | 18462 | Decal/ribbon/ghost/composite render laws | GUARD | KEEP | na | multiple render lessons
_test_touch_modes | 18537 | CAMERA/SELECT/ACTION modes via real input | GUARD | KEEP | na | real input lifecycle
_test_ortho_orbit | 18764 | ortho orbit flip; zoom/snap/pan; restore | BEHAVIOR | KEEP | na | camera register
_test_projection_alignment | 18849 | ring phases pure-fn-of-tick; crossing gate | BEHAVIOR | KEEP | y | seed 0 determinism
_test_projection_alignment_safety | 18945 | never thread closed wheel; brake refuses | BEHAVIOR | KEEP | y | analytic safety law
_test_roguelike_goal | 19046 | seeded descent, retrieval, permadeath, chase | BEHAVIOR | KEEP | y | seeded-playthrough model
_test_dev_console | 19189 | console toggle; fog law; photo/events | GUARD | KEEP | na | fog decouple law
_test_chunk_interactable_outlines | 19266 | EVERY chunk click-gated + outline registered | GUARD | KEEP | na | systemic safeguard
_test_preview_matches_committed | 19351 | hover preview equals committed path | GUARD | KEEP | na | overshoot divergence
_test_party_preview_renderers | 19386 | one ribbon per member, distinct dests | GUARD | KEEP | na | only-one-path bug
_test_path_timed_wait_segment | 19436 | position pins at embedded wait waypoint | GUARD | KEEP | na | zero-drift edge
_test_enemy_pursuit_timeout | 19462 | pursuer disengages on lost sight | BEHAVIOR | KEEP | na | no ghost-chasing
_test_detection_vertical_band | 19506 | detection blocked across floors | BEHAVIOR | KEEP | na | cross-floor exemption
_test_lattice_holes | 19541 | red-shell hole/winding detector | VISUAL | KEEP | na | drum-handedness bug
_test_uv_atlas_baker | 19682 | islands/creases; deterministic re-bake | GUARD | KEEP | na | protects paint-over
```

## Part C — lines 19500-28500 (channels/wash, combat, replay, saves)

```
_test_player_contract | 19738 | per-fragment hover/click/key-once sweep | GUARD | KEEP | na | auto-gen real-input; windowed
_test_showcase_capture | 19968 | teleports to bays, saves PNGs | VISUAL | RETIRE | na | asserts only true
_test_terminal_focus_capture | 20013 | frames monitor, saves PNG | VISUAL | RETIRE | na | tautology
_test_channels_arc | 20080 | arc round-trip, monotonic climb, warp | GUARD | KEEP | na | click-lands invariant
_test_channels_scene | 20134 | glb loads, gameplay maps on model, 9 silhouettes | BEHAVIOR | RESHAPE | na | drop silhouette count
_test_interactable_warp | 20203 | warped scene moves proximity zones onto helix | GUARD | KEEP | na | dwell-never-arms lesson
_test_wash_relay_branches | 20233 | 5 branches, reachable, deterministic | BEHAVIOR | RESHAPE | y | keep reachability+determinism, drop count
_test_wash_relay_transit_breaks | 20317 | portal topology, valve 18s, counts | BEHAVIOR | RESHAPE | na | worst count offender
_test_wash_relay_abilities | 20421 | TRACE/BLOOM/BRACE fire, reset | BEHAVIOR | FOLD | na | subsumed by playthrough
_test_channels_splash_droplets | 20468 | droplets render round not plus | LAYOUT | RETIRE | na | aesthetic sprite detail
_test_channels_water_visible_range | 20519 | far water fades, near stays | VISUAL | KEEP | na | pixel-verifies overlay law
_test_channels_pipe_splash | 20572 | splash leads flood >=0.5s | BEHAVIOR | RESHAPE | na | fairness cue; internal arrays
_test_channels_splash_capture | 20608 | captures splash PNG | VISUAL | RETIRE | na | tautology
_test_channels_probe_coverage | 20654 | every walkable cell clickable | GUARD | KEEP | na | unreachable-by-click gaps
_test_generated_stretch_probe_coverage | 20738 | warped cells have collision | BEHAVIOR | RESHAPE | na | keep collision, drop span MIRROR
_test_spiral_drop_down | 20803 | drop-pads drop+turn, climbvines | BEHAVIOR | KEEP | y | shortcut mechanic
_test_stretch_branches | 20880 | weaver adds reachable floor, deterministic | GUARD | KEEP | y | drop contract-key list
_test_pump_hall | 20939 | full stealth playthrough | BEHAVIOR | KEEP | na | de-facto seeded playthrough
_test_roguelike_atom_run | 21072 | run scaling + played loop + set-pieces | BEHAVIOR | KEEP | y | de-facto seeded playthrough
_test_generated_atom_playable | 21352 | generated bridge played; variants | BEHAVIOR | RESHAPE | y | strip color/mode MIRROR
_test_chunk_batch | 21705 | 30-seed sweep: gated+lock-before-key | GUARD | KEEP | y | fairness across seeds
_test_chunk_atoms | 21762 | locked blocks, solved connects, determinism | GUARD | KEEP | y | puzzle invariant
_test_ascii_height_layers | 21789 | height-sliced ASCII layers | LAYOUT | RETIRE | y | duplicate descent coverage
_test_hub_base_playable | 21834 | base connected, real click walks | BEHAVIOR | KEEP | y | real-input walk
_test_warp_metric | 21914 | warp preserves ~1u spacing | GUARD | KEEP | na | KTHETA*R0 invariant
_test_hub_shapes | 21942 | per-shape round-trip inverse, curl | GUARD | KEEP | na | click-lands inverse
_test_generated_solution_replay | 22005 | seed identical solution, replay beats | GUARD | KEEP | y | determinism + validity
_test_generated_solution_realinput | 22034 | solution driven by real clicks | BEHAVIOR | KEEP | y | real-input playthrough
_test_channels_click_alignment | 22108 | cursor-deck round-trips <0.3 | GUARD | KEEP | na | warped click bug
_test_dest_ghost_capture | 22146 | captures ghost PNG | VISUAL | RETIRE | na | tautology
_test_channels_water_crop | 22194 | captures flood PNGs | VISUAL | RETIRE | na | tautology
_test_channels_occlusion_live | 22262 | prints occlusion numbers | VISUAL | RETIRE | na | diagnostic
_test_perception_los_capture | 22358 | LOS shadows pixel diff >0 | VISUAL | KEEP | na | real pixel assert
_test_occlusion_shader_capture | 22427 | synthetic occlusion PNG | VISUAL | RETIRE | na | tautology
_test_peris_room_capture | 22481 | captures peris room PNG | VISUAL | RETIRE | na | tautology
_test_wash_relay_water_capture | 22508 | captures flood PNG | VISUAL | RETIRE | na | tautology
_test_wash_relay_flood_visual | 22560 | flooding shows water, drains | BEHAVIOR | RESHAPE | na | visible-cause fairness
_test_wash_relay_checkpoint | 22599 | wash sweeps, Terminal recovers | BEHAVIOR | FOLD | na | dup of strand_recover
_test_wash_relay_trace_cadence | 22643 | TRACE names real beat | BEHAVIOR | RESHAPE | na | strip label MIRROR
_test_wash_relay_strand_recover | 22722 | stranded, BRACE refunds, rejoins | BEHAVIOR | FOLD | na | dup of checkpoint
_test_wash_relay_held_override | 22754 | override held not latched | BEHAVIOR | FOLD | na | dup of wash_relay leg
_test_channels_wash_intro | 22796 | full wash-intro playthrough | BEHAVIOR | KEEP | na | de-facto seeded playthrough
_test_channels_wash_intro_grammar | 22899 | hover hull / reveal / glow | GUARD | FOLD | na | dup of outline system tests
_test_channels_wash_intro_hover | 22938 | data-layer hover snaps | BEHAVIOR | FOLD | na | subsumed by live_input
_test_channels_wash_intro_live_input | 22985 | real cursor grid+ribbon+ghosts | GUARD | KEEP | na | prior tests bypassed live path
_test_channels_wash_intro_hover_capture | 23073 | hover pixel diff | VISUAL | RESHAPE | na | merge with visual_regression
_test_channels_slab_isolate | 23229 | isolate layers; ghost <2.5u | VISUAL | RESHAPE | na | keep ghost-width only
_test_aster_outline_render | 23307 | outline pixel diff + diagnosis | VISUAL | RESHAPE | na | heavy diagnostic
_test_channels_wash_intro_capture | 23466 | room lit not black | VISUAL | KEEP | na | black-room bug
_test_wash_relay_telegraph_visible | 23499 | telegraphs survive graybox | BEHAVIOR | FOLD | na | like flood_visual
_test_wash_relay_queued_glow | 23541 | servicer walks to FLAT cell on helix | GUARD | KEEP | na | flat-space API bug
_test_wash_relay_playthrough | 23594 | party crosses front-half gauntlet | BEHAVIOR | KEEP | na | proves beatable
_test_refuge_run_playthrough | 23650 | refuge run completes | BEHAVIOR | KEEP | na | beatability
_test_wash_relay_branch_puzzles | 23760 | caches locked till switch, decoy | BEHAVIOR | RESHAPE | na | fold into playthrough
_test_wash_relay_no_hang | 23876 | finite coords through warp | GUARD | KEEP | na | NaN crash-proofing
_test_wash_relay_menu_load | 23946 | picker load installs coord_map | GUARD | KEEP | na | --preview bypass path
_test_wash_relay_hover_sweep | 23984 | hover sweep finite, <120ms | GUARD | KEEP | na | overlap w/ no_hang
_test_wash_relay_helix_path_draws | 24070 | ribbon rides helix finite | GUARD | RESHAPE | na | overlaps ribbon_build
_test_wash_relay_ribbon_build | 24114 | ribbon finite, pathological capped | GUARD | KEEP | na | crash cap
_test_wash_relay_pathfind_perf | 24187 | hover+find_path <60ms | PERF | KEEP | na | real freeze budget
_test_nav_oracle | 24230 | navmesh bake determinism + admissibility | GUARD | KEEP | na | guided-A* oracle
_test_reachability_cull | 24290 | unreachable culled, reachable moves | GUARD | KEEP | na | reproduce-first
_test_chunk_robustness | 24414 | every chunk spawns/anchors walkable, reset | GUARD | KEEP | na | systemic net
_test_channels_robustness | 24434 | spiral grid/movement/win/FF-determinism | BEHAVIOR | RESHAPE | na | overlap w/ playthrough
_test_wash_relay | 24569 | exhaustive mega-test all mechanics | BEHAVIOR | RESHAPE | na | section-index MIRROR
_test_channels_textures | 24690 | glb albedo, occlusion wrap preserves | GUARD | KEEP | na | rendering guard
_test_wash_relay_flush_hint | 24734 | hint after 3 washes same section | BEHAVIOR | RESHAPE | na | tutorial-hint timing
_test_wash_drain_loop | 24776 | drain U-loop, guard drowns, FF-invariant | BEHAVIOR | RESHAPE | na | keep FF-invariance
_test_wash_drain_loop_capture | 24907 | captures PNG | VISUAL | RETIRE | na | tautology
_test_showcase_gallery | 25025 | tiers/flora/enemies, hiding teaches | BEHAVIOR | KEEP | na | drop inventory counts
_test_set_piece_showcase | 25067 | crawl/hub/water/slab driven end-to-end | BEHAVIOR | KEEP | na | portal rule
_test_chain_combat | 25256 | ChainEnemy real damage, disengage, dodge | GUARD | KEEP | na | reproduce-first
_test_dodge_failure_no_cooldown | 25318 | wall-dodge costs nothing | GUARD | KEEP | na | reproduce-first
_test_strike_skips_corpse | 25351 | charge doesn't hit dead target | GUARD | KEEP | na | reproduce-first
_test_dialogue_transcript_cap | 25378 | transcript caps, pop_front | GUARD | KEEP | na | unbounded-growth
_test_interactable_state_replay | 25397 | enable/disable/reset replay round-trip | GUARD | KEEP | na | replay determinism
_test_visual_regression | 25475 | hover overlay composites pixels | VISUAL | KEEP | na | alpha-blend preview law
_test_predictive_attack | 25639 | no-teleport lunge, dodge@impact | GUARD | KEEP | na | charge_speed*dt cap
_test_pump_hall_live | 25722 | real cursor flure outline, right-click carry | GUARD | KEEP | na | reported bug; windowed
_test_blind_floor | 25839 | full DoT-corridor playthrough | BEHAVIOR | KEEP | na | de-facto playthrough
_test_conceal_stops_strikes | 25963 | conceal mid-windup sheds attacker | GUARD | KEEP | na | reported bug
_test_capbage_retrieve | 26008 | full retrieve chunk playthrough | BEHAVIOR | KEEP | na | de-facto playthrough
_test_sprint_gap | 26153 | full sprint-gap playthrough + tuning | BEHAVIOR | KEEP | na | de-facto playthrough
_test_portal_group | 26234 | one-at-a-time crossing, ghosts, replay | BEHAVIOR | KEEP | na | portal rule + replay
_test_tension_sweep | 26322 | sprint/death-march sweep invariants | BEHAVIOR | KEEP | na | game-wide tuning harness
_test_run_stamina_budget | 26390 | drain re-arms after pause | GUARD | KEEP | na | free-sprint bug
_test_charge_whiff | 26435 | sprinter slips led charge | GUARD | KEEP | na | led-not-homing
_test_drag_retrieve | 26498 | drag mechanics + replay | BEHAVIOR | KEEP | na | mechanic + replay
_test_pump_hall_grammar | 26612 | hover hull+name, click glow | GUARD | FOLD | na | dup of outline system
_test_downed_carry | 26653 | downed body carry, revive | BEHAVIOR | KEEP | na | retrieve verb
_test_combat_downed | 26702 | combat hp0 canonical down | GUARD | KEEP | na | combat vs scripted down
_test_shelter_safety | 26745 | sheltered unspottable, step-out spotted | GUARD | KEEP | na | attacked-in-shelter bug
_test_combat_cycle | 26831 | FSM cycle order, loops, FF-invariant | GUARD | KEEP | na | documented flag
_test_dodge_combat_timing | 26887 | dodge@impact #20, no-stamina #24 | GUARD | KEEP | na | cites issues
_test_dialogue_hold_advance | 26927 | hold-click flows lines | BEHAVIOR | KEEP | na | real-input dialogue
_test_chromatic_aberration | 26972 | sims have CA layer enabled | LAYOUT | RETIRE | na | aesthetic post-process
_test_data_identify | 27000 | hover names object, overlay tints | BEHAVIOR | KEEP | na | hover naming
_test_player_cross_level_click | 27050 | click other floor routes cross-level | GUARD | KEEP | na | real-input cross-level
_test_player_overhead_height_gate | 27124 | overhead coil rejected zoomed-in | GUARD | KEEP | na | height gate on helix
_test_outline_particle_emission | 27159 | surface emission internals | MIRROR | RESHAPE | na | off-by-default particles
_test_interactable_outline_particles | 27228 | ring emission; burst no-op | MIRROR | RESHAPE | na | keep no-op-burst only
_test_outline_feedback_system | 27257 | canonical-hover no-op, idempotent | GUARD | KEEP | na | hover-churn lesson
_test_interactable_data | 27349 | register/trigger/enable logged, replay | GUARD | KEEP | na | replay determinism
_test_chunk_party_presence | 27422 | PartyPresence roster contract | BEHAVIOR | KEEP | na | low churn
_test_sim_command_api | 27454 | command builders carry args, throw lands | GUARD | RESHAPE | na | builder restatements MIRROR
_test_game_state | 27519 | register/move/serialize round-trip | GUARD | KEEP | na | foundational
_test_event_log_roundtrip | 27605 | record-replay-bytes round-trip | GUARD | KEEP | na | replay determinism
_test_event_log_mutation_audit | 27784 | lint: mutators emit | GUARD | KEEP | na | first-class lint
_test_movement_capture | 27902 | moves captured, replay reproduces | GUARD | KEEP | na | replay determinism
_test_rng_determinism | 27951 | seed same seq, stream isolation | GUARD | KEEP | y | core determinism
_test_save_load_integrity | 28052 | continuous vs resumed equal | GUARD | KEEP | y | save determinism
_test_save_corruption_recovery | 28105 | truncated recovers, bad header empty | GUARD | KEEP | na | corruption recovery
_test_party_cohesion_default | 28150 | party fans, one logged event, replay | GUARD | KEEP | na | movement + replay
_test_scripted_split | 28217 | split limits move to main group | BEHAVIOR | KEEP | na | split mechanic
_test_portal_revisit | 28269 | zone backtrack, revisit transform | GUARD | KEEP | na | zone persistence
_test_replay_roundtrip | 28383 | record-replay hash matches | GUARD | KEEP | y | replay baseline
_test_determinism_rerecord | 28436 | replay re-record event-for-event | GUARD | KEEP | y | determinism
```

## Part D — lines 28500-39792 (lints, flora, physics, act1, chases)

```
_test_scene_triggers | 28500 | trigger types fire-once, priority | GUARD | KEEP | na | dispatch invariant
_test_no_game_over | 28606 | party down fires no game_over | GUARD | KEEP | na | failure-model law
_test_scripted_death_only | 28680 | lint: death only in die_scripted | GUARD | KEEP | na | death-path lint
_test_hub_rest_restore | 28721 | hub rest restores downed | BEHAVIOR | KEEP | na | care thesis
_test_gate_block | 28767 | gate needs Endo; blocks w/ reason | BEHAVIOR | KEEP | na | party gating
_test_zone_progression | 28832 | zone-spoke-gate transitions | BEHAVIOR | KEEP | na | hub reach
_test_actuator_composition_blind | 28925 | plate triggers on weight only | GUARD | KEEP | na | actuator law
_test_actuator_no_id_checks | 29054 | lint: mechanisms reference no char_id | GUARD | KEEP | na | architecture lint
_test_canonical_location_names | 29153 | lint: retired district names absent | GUARD | RESHAPE | na | low-value but protects player text
_test_chunk_mutation_discipline | 29210 | lint: chunks compose kit only | GUARD | KEEP | na | director ratchet
_test_sequence_input_discipline | 29236 | lint: no raw input in sequences | GUARD | KEEP | na | input lint
_test_rng_no_wallclock | 29264 | lint: no wall-clock RNG in logic | GUARD | KEEP | na | determinism law
_test_flora_memory | 29380 | flora clue propagation, degradation | BEHAVIOR | RESHAPE | na | exact scent strings brittle
_test_tag_day_dialogue | 31116 | drives tag_day; line count/speakers/text | MIRROR | RESHAPE | na | keep poem<fragment ordering only
_test_peris_dialogue | 31225 | phase-2 text present | MIRROR | RESHAPE | na | overlaps peris_phase2
_test_peris_tutorial_redirect | 31309 | wrong-order inputs correct; completes | BEHAVIOR | KEEP | na | real-input lifecycle
_test_elevator_dialogue | 31362 | drives elevator; key-existence | MIRROR | RESHAPE | na | EMP-as-animation assert is behavior
_test_endo_drink | 31469 | Endo walks, drink delivered | BEHAVIOR | FOLD | na | subsumable set-piece
_test_junction_flow | 31527 | authored anchors, spacing, walkability | LAYOUT | RESHAPE | na | keep reachability + progression
_test_climb_and_lockout | 31681 | dialogue keys exist non-empty | MIRROR | RETIRE | na | drives nothing
_test_enemy | 31706 | enemy detect/alert/attack/death cycle | BEHAVIOR | KEEP | na | core lifecycle
_test_chain_enemy | 31863 | segments follow, contact, death | BEHAVIOR | KEEP | na | some exact positions
_test_act1 | 32036 | chunks, windows, encounter, shelter | BEHAVIOR | RESHAPE | na | force-fires beats; strip find_child noise
_test_predictive_detection | 32269 | detection solver timing 5 geometries | GUARD | KEEP | na | timing contract
_test_detection_equivalence | 32372 | predictive == brute-force N=10 | GUARD | KEEP | na | optimization vs truth
_test_flure | 32661 | lure gauntlet: window, footprint, flock | BEHAVIOR | KEEP | na | briefing-window lesson
_test_hide_encounter | 32785 | solver solves; 4 failure modes fail | MIRROR | FOLD | na | abstract sim; live in act1
_test_hide_encounter_analysis | 32827 | analysis bundle + version string | MIRROR | RETIRE | y | research internals
_test_hide_encounter_shared_duration | 32875 | no equal-duration solution exists | MIRROR | RETIRE | na | search tautology
_test_hide_encounter_lure2_duration | 32893 | sweep lure2; chosen in set | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_exit_gap | 32929 | sweep exit_gap; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_cluster_gap | 32958 | sweep cluster_gap; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_run_drain | 32988 | sweep run_drain 31 values | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_stand_regen | 33019 | sweep stand_regen; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_consume_cost | 33051 | sweep consume cost; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_hold_duration | 33088 | sweep hold_duration; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_walk_regen | 33121 | sweep walk_regen; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_coupled_stand_hold | 33155 | 2-axis sweep; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_coupled_stand_walk | 33190 | 2-axis sweep; chosen | MIRROR | RETIRE | na | tuning mirror
_test_hide_encounter_split_recovery | 33225 | 2-axis sweep; records space | MIRROR | RETIRE | na | tuning mirror
_test_camera_shake | 33940 | shake offsets then decays | BEHAVIOR | RESHAPE | na | weaken to perturb-decay
_test_camera_free_look | 33997 | free-look enable, middle-drag pans | BEHAVIOR | KEEP | na | camera input-mode routing
_test_left_click_no_interact | 34051 | LEFT never interacts; RIGHT does | GUARD | KEEP | na | click-hijack bug
_test_right_click_move | 34104 | RIGHT-click ground moves via real input | BEHAVIOR | KEEP | na | real synthetic-input path
_test_selection_controller | 34178 | pick, marquee, deselect, rally | BEHAVIOR | KEEP | na | core RTS controls
_test_pick_interactor | 34342 | interactor choice: required/nearest/downed | BEHAVIOR | KEEP | na | deterministic-for-replay
_test_interaction_delegates_to_capable | 34397 | routes walk to capable member | BEHAVIOR | KEEP | na | capable-character law
_test_lure_not_path_waypoint | 34447 | walk past lure adds no waypoint | GUARD | KEEP | na | ribbon-pivot bug
_test_grid_risk | 34472 | risk routing detours, refusals, replays | BEHAVIOR | KEEP | na | preview==commit + replay
_test_grid_from_data | 34536 | from_data carves footprint, risk, links | GUARD | KEEP | na | grid data contract
_test_generated_grid | 34576 | every spec connected, deterministic | BEHAVIOR | KEEP | na | reachability + determinism
_test_dodge_knockdown | 34652 | no-stamina dodge knocks down | BEHAVIOR | KEEP | na | dodge mechanics
_test_preview_parked_bail | 34695 | parked-cell preview instant, fallback | GUARD | KEEP | na | 2.2s hang bug
_test_drink_partial_dwell | 34719 | partial hold doesn't pour; full does | BEHAVIOR | KEEP | na | dwell-from-arrival bug
_test_push_lab | 34803 | Sokoban push directions/refusals | BEHAVIOR | KEEP | na | push mechanics
_test_rest_lab | 34889 | rest revives; full house skips night | BEHAVIOR | KEEP | na | rest loop
_test_modeled_room_binder | 34938 | binder rules, tilt/occupant validation | GUARD | KEEP | na | tilted-root bug
_test_flora_garden | 34999 | garden tend/flourish/harvest loop | BEHAVIOR | KEEP | na | fragment playthrough
_test_dusk_run | 35042 | cross+rest clears night; dawdle debuff | BEHAVIOR | KEEP | na | GDD 422 both endings
_test_flora_network | 35089 | plant/grow/yield/network + replay | BEHAVIOR | KEEP | na | replay leg
_test_day_night | 35172 | time pure tick fn; deprivation; replay | GUARD | KEEP | na | FF-invariant by construction
_test_shelter_rest | 35254 | rest gates/heal/revive/night-skip + replay | BEHAVIOR | KEEP | na | GDD 3.3
_test_wrong_character_feedback | 35449 | wrong char shows naming thought | BEHAVIOR | KEEP | na | silent-rejection bug
_test_physics_objects | 35594 | push, mass ratio, chain, area impulse | BEHAVIOR | KEEP | na | custom physics
_test_airborne_strike_survives_recompute | 35726 | airborne strike under recompute | GUARD | KEEP | na | red/green documented
_test_physics_edge_cases | 35760 | ~16 edge scenarios + determinism | BEHAVIOR | KEEP | na | includes determinism leg
_test_pendulum | 36068 | oscillation, damping, hits | BEHAVIOR | KEEP | na | hazard physics
_test_throw_physics | 36219 | lob/wall/hit/slide + determinism | BEHAVIOR | KEEP | na | throw physics
_test_physics_comparison | 36437 | custom vs Jolt benchmark | PERF | RETIRE | na | engine-choice benchmark; brittle
_test_peris_phase2 | 36736 | phase-2 text present | MIRROR | RETIRE | na | subset of peris_dialogue
_test_peris_scene_transition | 36819 | subprocess real transition stderr grep | GUARD | KEEP | na | philosophy-endorsed guard
_test_elevator_teardown_clean | 36855 | subprocess collapse+free stderr grep | GUARD | KEEP | na | timer-outlives-scene leak
_test_sequence_contracts | 36982 | 7 scenes reach complete via steps | GUARD | KEEP | na | force-fired; step-lists brittle
_test_intro_chain | 37249 | whole intro chains to Act 1 | GUARD | KEEP | na | catches broken handoffs
_test_items | 37378 | spawn/pickup/transfer/endocytose + determinism | BEHAVIOR | KEEP | na | item system
_test_queued_abilities | 37573 | ability queues, auto-moves, cancel | BEHAVIOR | KEEP | na | ability queueing
_test_dodge_roll | 37646 | dodge basic/locked/cooldown/wall | BEHAVIOR | KEEP | na | distinct from dodge_knockdown
_test_decorative_flora | 37933 | decoratives place/reveal/clear, drain | BEHAVIOR | KEEP | na | counts/tint are LAYOUT edges
_test_aghora_clearance | 38063 | banner/stack/window clearance across seeds | LAYOUT | KEEP | y | clipping correctness, not aesthetics
_test_boss_playable | 38133 | boss hazards damage, climb/survey/winch | BEHAVIOR | KEEP | na | showcase-is-encounter
_test_shelter_sanctuary | 38248 | no detect/strike inside shelter region | BEHAVIOR | KEEP | na | attacked-in-shelter bug
_test_naturalizer_hushbloom | 38302 | Naturalizer hesitates; Hushbloom freezes | BEHAVIOR | KEEP | na | chase levers
_test_inflammashunt | 38382 | 10 scenarios: wrong approaches stay solvable | BEHAVIOR | KEEP | na | recoverability law
_test_lockout_from_top_rally_reset | 38810 | reset cancels live rally, re-arms | GUARD | KEEP | na | Dean's find
_test_lockout_chase | 38868 | whole chase end-to-end | BEHAVIOR | KEEP | na | mostly force-fire; one normal-input leg
_test_chase_probe | 39241 | 7 naive strategies; prints traces | BEHAVIOR | RETIRE | na | asserts only "ran"
_test_chase_perf | 39464 | ms/step benchmarks | PERF | RETIRE | na | asserts only "ran"
```
