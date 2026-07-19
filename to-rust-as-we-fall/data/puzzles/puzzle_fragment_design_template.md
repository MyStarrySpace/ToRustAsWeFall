# Puzzle Fragment Design Template

Copy this file when drafting a new fragment. Keep it short enough that the fragment still feels atomic.

## Identity

- `fragment_id`:
- `display_name`:
- `scene`:
- `campaign_job`: teach / reinforce / combine / gate / shortcut / mastery
- `kind`: puzzle / survival / hybrid
- `quest_hook`:
- `party_spotlight`:

## Intent

- `primary_insight`:
- `secondary_texture`:
- `durable_outcome`:
- `why_this_exists_in_the_level`:
- `what_makes_this_feel_like_an_encounter`:

## Systems-Thinking Contract

Use [the systems-thinking puzzle standard](../../docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md).
Write `none` when a field genuinely does not apply.

- `system_boundary_and_goal`:
- `intended_player_model`:
- `load_bearing_elements_and_links`:
- `stocks_inflows_and_outflows`:
- `feedback_loops`:
- `delays`:
- `nonlinear_thresholds`:
- `local_and_party_scales`:
- `meaningful_leverage_point`:
- `likely_first_model`:
- `likely_misconception`:
- `evidence_that_corrects_it`:
- `later_transfer_test`:
- `point_where_reasoning_is_solved`:
- `solved_state_execution_tail`:

## Cognitive Targets

- `main_target`: recognition / recall / timing / prospective_memory / route_planning / map_layer_arbitration / pressure_management
- `working_memory_budget`:
- `attention_switch`:
- `ambiguity_source`:
- `what_should_be_externalized`:

## World Systems And Verbs

- `systems`:
- `player_verbs`:
- `party_layers_in_play`:
- `resources_in_play`:
- `pressure_sources`:

## State Model

- `states`:
- `critical_transitions`:
- `irreversible_commits`:
- `recovery_paths`:
- `failure_states`:

## Difficulty Budget

- `info_load`:
- `time_pressure`:
- `execution_precision`:
- `ambiguity`:
- `reset_cost`:
- `durability`:

## Failure Pedagogy

- `naive_failure`:
- `greedy_failure`:
- `trust_failure`:
- `recovery_failure`:
- `what_the_player_should_learn_from_each`:

## Layout Notes

- `required_landmarks`:
- `safe_space`:
- `hazard_space`:
- `commit_point`:
- `reward_or_release_point`:
- `optional_side_risk`:
- `regroup_beat`:

## Headless Instrumentation

- `anchors_to_expose`:
- `state_paths_to_expose`:
- `helper_methods_to_expose`:
- `event_counters_to_track`:

## Deterministic Scenario Plan

- `golden_path`:
- `representative_failure`:
- `recovery_case`:
- `sequence_guard`:

## Solver And Tuning Knobs

- `structural_parameters`:
- `behavioral_parameters`:
- `information_parameters`:
- `success_metrics`:
- `first_threshold_variable`:

## Analysis Plan

- `closed_form_possible`: yes / no
- `phase_plane_axes`:
- `bifurcation_variable`:
- `monte_carlo_perturbations`:
- `integration_checks`:

## Sequence Fit

- `what_it_assumes_the_player_already_knows`:
- `what_future_fragment_reuses_this`:
- `what_persistent_change_carries_forward`:
- `how_this_supports_the_level_promise`:
- `campaign_memory`: what the player should remember this room as

## Catalog Notes

Optional metadata we may eventually store alongside fragment entries:

```json
{
  "design": {
    "campaign_job": "teach",
    "primary_insight": "Use the lure to create a later movement window.",
    "cognitive_targets": ["prospective_memory", "timing"],
    "pressure_sources": ["enemy_pursuit", "resource_drain"],
    "durable_outcome": "safe passage to shelter",
    "knobs": ["lure_duration", "hallway_distance", "enemy_speed"]
  }
}
```

That metadata is optional for now. The important part is that every fragment has a written brief before it gets tuned.
