# Channels: Borrowed Current Systems Pass

This is the focused systems-thinking pass for the generated teaching stretch. It applies
[the systems-thinking puzzle standard](../../docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md) to the
existing First Sluice -> Cistern Bridge -> Borrowed Current sequence.

## Identity

- `fragment_id`: generated_teaching_channels_shelter_1_to_2
- `campaign_job`: teach -> combine -> transfer
- `kind`: hydraulic puzzle / traversal hybrid
- `party_spotlight`: Endo reads the infrastructure; the full party executes the route

## Systems-Thinking Contract

- `system_boundary_and_goal`: the finite hydraulic network from First Sluice to the shelter; get
  bridge cargo and one borrowed-current delivery through the system, then feed the exit
- `intended_player_model`: the network has one current; the diverter can feed the spillway or the
  shelter path, but not both at once
- `load_bearing_elements_and_links`: First Sluice -> cistern; Cistern Release -> bridge gap;
  Borrowed Current -> spillway catch; Borrowed Current -> shelter flow
- `stocks_inflows_and_outflows`: the cistern is the taught stock; visible water paths are the flows
- `feedback_loops`: none in this teaching pass; this establishes the finite-flow baseline that a
  later pressure or enemy loop can reuse
- `delays`: traversal carries the player from the diverter to the downstream catch before the
  delivery latches
- `nonlinear_thresholds`: the bridge gap changes from blocked to traversable when the bridge cargo
  is released
- `local_and_party_scales`: diverting locally enables the food catch but globally starves the
  shelter route
- `meaningful_leverage_point`: the Borrowed Current diverter changes network topology; it does not
  merely increase a number
- `likely_first_model`: the diverter permanently unlocks the food route without affecting the main
  route
- `likely_misconception`: after catching the spillway delivery, the player expects to continue
  forward instead of returning the finite current to the shelter
- `evidence_that_corrects_it`: the main tail drains as the violet spillway fills; both downstream
  causal links identify the gain and loss; the shelter beacon remains starved; after the catch the
  dry main route and diverter state communicate that flow must return
- `later_transfer_test`: catch and restore omit the persistent next-answer highlight; the player
  follows the visible current and changing relationships learned from the first two explicit beats
- `point_where_reasoning_is_solved`: the player catches the spillway delivery and correctly infers
  that the same current must be restored to feed the shelter
- `solved_state_execution_tail`: return to the diverter, restore the visible main current, and take
  the now-fed route to the shelter; tune this down if replay shows traversal without a new decision

## Guidance Progression

1. `first_sluice`: explicitly highlight the control, show its cistern consequence, and move the
   camera. This teaches the visual grammar.
2. `cistern_bridge`: explicitly highlight the release and show the bridge crossing the threshold.
3. `borrowed_current`: highlight the diverter once, but show both of its downstream relationships.
4. `food_spillway`: remove the persistent answer highlight. The violet flow, catch state, and
   diverter links carry the prediction.
5. `restore_current`: remove the persistent answer highlight. The starved shelter, dry main flow,
   and changed relationship labels should make returning to the diverter understandable.
6. `exit_ready`: highlight the shelter to end navigation cleanly after the reasoning is complete.

## Acceptance Checks

- Relationship labels change truthfully when flow changes branch.
- Diversion visibly fills the spillway and drains the competing main tail.
- Both diverter consequences flash when the current changes branch.
- The catch and restore phases have no persistent `hydraulic_next_step` answer highlight.
- Hydraulic control hover prompts resolve the live `command` binding before naming the action, so
  input uncertainty is not mistaken for a systems-thinking failure.
- Wrong-order feedback points to the missing relationship without completing the step.
- Replay distinguishes model revision from movement or click failure.
