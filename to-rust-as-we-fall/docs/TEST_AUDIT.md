# Test Suite Audit — 2026-07-20

All 337 `_test_*` functions in `scripts/test_runner_cli.gd` (~40k lines, 5,329 assertions)
classified against one question: **does this test catch a bug a player would hit, or does it
constrain authoring choices?** Classification was done by four independent read-passes with a
shared rubric, plus a timing profile (`--test-all --profile`) and a map of the seeded/replay
infrastructure.

## Verdict summary

| Verdict | Count (approx) | Meaning |
| --- | --- | --- |
| KEEP | ~240 | Catches real bugs; encodes a documented lesson; determinism/replay/input/lifecycle |
| RESHAPE | ~40 | Sound core buried under authored-choice assertions — strip to the invariant |
| FOLD | ~15 | Coverage subsumable by a seeded playthrough of the same content |
| RETIRE | ~35 | Provides ~no protection (tautologies, tuning mirrors, diagnostics-as-tests, prose pins) |

The fear is **partially** confirmed: the suite's core is strong (determinism, replay,
real-input, reproduce-first bug guards — none of which constrain content), but ~90 tests are
constraint or dead weight, concentrated in a few families.

## 1. RETIRE — no protection, pure churn (propose deleting)

**Tautology "capture tests" (11)** — their only assertion is `_assert_true(true)`; they are
eyeball tools mislabeled as tests. Keep them as dev capture *tools*, drop them from the test
registry: `showcase_capture`, `terminal_focus_capture`, `channels_splash_capture`,
`dest_ghost_capture`, `channels_water_crop`, `channels_occlusion_live`,
`occlusion_shader_capture`, `peris_room_capture`, `wash_relay_water_capture`,
`wash_drain_loop_capture`, plus the diagnostic `channels_wash_intro_hover`.

**The `hide_encounter_*` parameter-sweep family (13 of 14)** — twelve one-axis sweeps of the
same solver, each asserting only "the search tool found a solution and picked a value from the
array it was handed", plus `_analysis` pinning `methodology_version == "hide-encounter-v5"`.
Tuning research, not tests. Keep ONE solvability check (`_test_hide_encounter`, reshaped); the
live encounter is already exercised in `_test_act1`.

**Diagnostics that cannot go red**: `chase_probe`, `chase_perf` (assert only "probe ran";
already excluded from `--test-all`). Reclassify as tools.

**Prose/content pins**: `climb_and_lockout` (dialogue-key existence, drives nothing),
`peris_phase2` (strict subset of `peris_dialogue`), the ~50 verbatim DialogueData string
asserts inside `_test_aster_sim`, the exact draft-string asserts inside `_test_syntax`.
These break on every copy edit and catch nothing.

**Aesthetic presence checks**: `chromatic_aberration` (a cosmetic post-process is enabled),
`channels_splash_droplets` (droplet sprite is a disc not a plus), `peris_sim`'s decor roster
(couch visible, bear visible, armchair hidden — amended three times in one working session
without ever representing a bug), `ascii_height_layers` (duplicates descent coverage while
asserting debug-ASCII text), `physics_comparison` ("custom engine faster than Jolt").

## 2. RESHAPE — keep the invariant, strip the authored-choice shell

- **Generation aesthetics**: `asset_pipeline` (exact shader-source substrings, exact emissive
  pixel counts), `building_filler_programs` (green/cyan/warm glow-count "signatures"),
  `building_filler` / `architecture_showcase` / `building_survey` / `biomes` (massing,
  proportions, palette steps, per-family "builds the X pass"). Keep: determinism, watertight
  `boundary_edge_count==0`, validate()-goes-RED, connectivity, street clearance.
- **Channels/wash-relay exact counts**: `wash_relay_transit_breaks` (9 silhouettes / 4
  portals / "18s" vent), `channels_scene` (silhouettes==9), `wash_relay` mega-test's
  per-section-index asserts. These pin authored level geometry.
- **Scene-layout contracts**: `aster_sim`'s 23-marker roster + <0.01 coordinate equalities +
  particle-count tuning; `peris_sim`'s plant-on-table ±1.5 cm, 0.5 m grid snapping, 1.2 m zone
  spacing (all three fought legitimate re-decoration this week); `junction_flow` anchor
  spacing; elevator light-energy thresholds and 12-mesh iron footprint counts; `settings`
  verbatim keycap labels. Keep: reachability, walkability, binder validation, progression.
- **Dialogue-driver mirrors**: `tag_day_dialogue` / `elevator_dialogue` / `peris_dialogue`
  assert speaker labels, line counts, and text substrings. Keep only the load-bearing ordering
  invariants (poem-before-fragments; BANG-before-lockdown; EMP-as-world-animation).

## 3. FOLD — subsumable by seeded playthroughs

Scene-structure smoke legs (`find_child != null` walls) and force-fired click matrices in
`aster_sim` / `peris_sim` / `elevator` / `act1` / `sequence_contracts` / `lockout_chase`;
the wash-relay siblings `checkpoint`, `strand_recover`, `held_override`, `telegraph_visible`,
`flood_visual`, `flush_hint`; per-chunk outline-grammar copies (`channels_wash_intro_grammar`,
`pump_hall_grammar` — the unit lesson lives in `outline_feedback_system` and the systemic
`chunk_interactable_outlines`); `endo_drink`, `leaving_facility`, `roguelike_run`.

**Why fold rather than keep:** these advance by `_trigger()`/`snap_character_to`/`_start_*` —
force-fire — so by construction they cannot catch the one bug class that matters most here:
an unreachable gate / stall. The suite's own best tests prove the alternative works.

## 4. The protected core — do NOT touch

- **Determinism/replay/fast-forward**: `rng_determinism`, `rng_no_wallclock`,
  `replay_roundtrip`, `determinism_rerecord`, `event_log_*`, `cooperative_pathfinding`,
  `state_machine`, `grid_levels`, `day_night`, `detection_equivalence` (predictive vs
  brute-force), `save_load_integrity`. These *enable* the seeded direction.
- **Real-input/lifecycle** (first-class per CLAUDE.md): `input_playthrough`,
  `intro_realinput(_core)`, `elevator_realinput`, `peris_scene_transition`,
  `elevator_teardown_clean`, `right_click_move`, `touch_modes`, `player_contract`.
- **Reproduce-first bug guards** (each cites its bug): `airborne_strike_survives_recompute`,
  `preview_parked_bail`, `left_click_no_interact`, `drink_partial_dwell`,
  `lure_not_path_waypoint`, `shelter_sanctuary`, `strike_skips_corpse`,
  `dodge_failure_no_cooldown`, `sight_mask_bake`, `hover_grid_alignment`, and kin.
- **Architecture lints**: `sequence_input_discipline`, `chunk_mutation_discipline`,
  `actuator_no_id_checks`, `scripted_death_only`, `event_log_mutation_audit`,
  `project_hygiene`.
- **Render laws** (structural, not aesthetic): `overlay_materials`, `camera_occlusion`,
  `peris_furniture_uvs`, `lattice_holes`, `visual_regression`, `uv_atlas_baker`.

## 5. The seeded-playthrough harness (the replacement)

Eleven tests already have the target shape — fixed seed, drive the level, assert outcomes:
`run_session_e2e`, `roguelike_goal`, `generated_stretch_playtest_loop`, `puzzle_fragments`,
`pump_hall`, `channels_wash_intro`, `blind_floor`, `capbage_retrieve`, `sprint_gap`,
`wash_relay_playthrough`, `generated_solution_realinput`. What's missing is ONE entry point.

All the rails exist (`SeededRng`/`RngRegistry` per-system streams; `EventLog` v2 +
`GameState.replay`; SimCommand/SimRunner; `headless_advance`; `_drive_scene_real_input`;
`.trwfplay` input tapes) but the three driver styles are incompatible and SimRunner attaches
no EventLog and emits no milestone stream.

**Proposal — `PlaythroughHarness.run(spec) -> report`:**

```gdscript
# spec: { scene: "res://..." OR chunk: "wash_relay" OR stretch: {seed, stage, ...},
#         base_seed: int, drive: "commands"|"beats"|"solution",
#         script: Array[SimCommand] | {step: Callable} | null,
#         max_ticks: float }
# report: { milestones: Array,        # normalized: tutorial steps / chunk node completions
#           event_log: EventLog,      # always attached, always replayable
#           final_snapshot: Dictionary, state_hash: int,
#           termination: "complete"|"stall"|"timeout", stalled_at: String }
```

Every harness run gets three standard assertion packs for free:
1. **Completes** — real/commanded input only; a stall names the gate (`stalled_at`).
2. **Deterministic** — same seed + script twice → identical `state_hash`; replaying the
   captured EventLog reproduces it (rides `GameState.replay`).
3. **Fast-forward invariant** — coarse vs fine tick steps → same milestone subsequence.

Build cost is glue, not new systems: attach an EventLog in SimRunner, extend it to
`headless_advance` generated chunks, and normalize `_current_step` (tutorials) vs
`_completed_nodes` (chunks) into one milestone stream. On failure, the harness dumps the
EventLog as a replay artifact for the `.trwfplay`-style debugger.

## 6. Cost notes (from `--test-all --profile`, 201 tests timed before cutoff)

Slowest: Scene Load 142.7s, Lockout Chase 33.3s, Playtest Loop 31.9s, Chunk Interactable
Outlines 28.9s, Inflammashunt 27.8s, Run Economy 23.4s. Retiring the tautology captures and
the hide_encounter sweeps saves little wall-clock (they're cheap) — the win is **churn**, not
seconds. The reshape of `wash_relay_transit_breaks` (4.3s) and the fold of wash siblings
saves ~30s and, more importantly, stops pinning level geometry.

## 7. Suggested execution order

1. Retire the tautology captures + diagnostics (move to `tools/`, keep them runnable).
2. Retire the hide_encounter sweeps (keep one solvability check + the exporter as a tool).
3. Reshape the dialogue mirrors and the layout contracts (strip to ordering/reachability).
4. Build `PlaythroughHarness` + convert ONE scene (Peris-1: already has beats + seeds) as the
   exemplar; then fold the wash-relay siblings and the force-fired scene matrices one family
   at a time, each with a red/green check that the folded coverage still catches its bug.
5. Only then touch the generation-aesthetics reshapes (they're cheap to keep meanwhile).

Rule for every retirement: if the test's comment cites a reproduced bug, the lesson moves
into the harness assertion or the test stays. Nothing is silently weakened.
