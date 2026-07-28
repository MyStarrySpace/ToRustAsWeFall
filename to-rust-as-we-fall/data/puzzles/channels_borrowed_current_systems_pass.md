# Channels: Borrowed Current Systems Pass

This is the focused systems-thinking pass for the generated teaching stretch. It applies
[the systems-thinking puzzle standard](../../docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md) to the
existing First Sluice -> Cistern Bridge sequence and its optional Borrowed Current branch.

## Identity

- `fragment_id`: generated_teaching_channels_shelter_1_to_2
- `campaign_job`: teach -> test on the required route; optional transfer for a physical reward
- `kind`: hydraulic puzzle / traversal hybrid
- `party_spotlight`: Endo reads the infrastructure; the full party executes the route

## Systems-Thinking Contract

- `system_boundary_and_goal`: the finite hydraulic network from First Sluice to the shelter; carry
  the bridge cargo into the route gap and reach the shelter. The spillway lysate is not required.
- `intended_player_model`: water transports physical cargo. Once the bridge seats, the main route
  and exit are ready. A later optional diversion changes the route of newly launched flow, while a
  payload already in motion keeps the route it captured at launch.
- `load_bearing_elements_and_links`: First Sluice -> cistern; Cistern Release -> moving bridge
  cargo -> route gap and main feed; optional Borrowed Current -> moving lysate -> spillway catch.
- `stocks_inflows_and_outflows`: the cistern is the taught stock; visible water paths and moving
  cargo are flows; the bridge gap and spillway catch are distinct sinks.
- `feedback_loops`: the optional diverter temporarily starves the already-ready main route; restoring
  it closes that risk loop without cancelling or redirecting the payload already in flight.
- `delays`: both cargo movements are visible. Optional lysate travel lasts 2.6 seconds from launch
  to `spillway_delivery_available`, leaving a deliberate window in which to restore the main route.
- `nonlinear_thresholds`: the bridge gap changes from blocked to traversable only when the carried
  bridge seats; the optional lysate cannot be caught until its delayed arrival.
- `local_and_party_scales`: the local reward bet temporarily removes the party's shelter feed and
  may commit one carrier hand, but it is never part of the baseline route.
- `meaningful_leverage_point`: the Borrowed Current valve allocates future flow. It does not teleport
  cargo, duplicate current, or rewrite the route of an object already travelling.
- `likely_first_model`: opening the sluice simply activates a bridge switch, rather than physically
  carrying debris into the gap.
- `likely_misconception`: restoring the valve while the lysate is moving will redirect or delete the
  launched reward.
- `evidence_that_corrects_it`: bridge cargo visibly travels and seats before the route opens. On the
  optional branch, the moving lysate retains its violet spillway route while the main channel lights
  again; the route labels and both downstream links change with future flow, not the payload.
- `later_transfer_test`: after learning transport and delay from the bridge, the player may divert,
  restore during the 2.6-second travel window, and predict that the captured payload still arrives at
  the spillway.
- `point_where_reasoning_is_solved`: required reasoning is solved when the bridge cargo seats and the
  main route becomes `exit_ready`. Optional reasoning is solved when the player correctly predicts
  that an in-flight payload survives an early restore.
- `solved_state_execution_tail`: the baseline tail is only traversal to the shelter. Choosing the
  reward branch introduces one new timing/topology decision rather than mandatory backtracking.

## Optional Risk / Reward Contract

- `risk`: diverting temporarily dries the ready shelter route; reaching the catch costs time and the
  caught lysate occupies one free hand.
- `reward`: one physical lysate. Pickup changes ATP by 0; ATP value is realized only through the
  separate endocytosis mechanic.
- `preferred_transfer_order`: `divert -> restore while payload is in transit -> catch`.
- `also_valid`: `divert -> catch -> restore`. This is safer to understand but leaves the main route
  starved for longer.
- `route_capture_rule`: the route is captured at launch. Valve changes during travel affect only
  future flow and must not redirect the launched payload.

## Guidance Progression

1. `first_sluice`: explicitly highlight the control, show water travelling to the cistern, and move
   the camera. This teaches the visual grammar.
2. `cistern_bridge`: explicitly highlight the release and show cargo physically crossing and seating
   in the gap. Seating the bridge completes the required hydraulic chain and makes the exit ready.
3. `borrowed_current`: present the diverter as an optional risk/reward proposition, never as the next
   required step. Hover or pause may show both downstream relationships.
4. `food_spillway_launch`: show the launched lysate moving on the violet route and the main route
   drying. Do not replace that evidence with an answer arrow.
5. `restore_in_flight`: let the player restore immediately. Re-light the main route while the lysate
   visibly continues toward the spillway, falsifying the redirect misconception.
6. `food_spillway_catch`: make arrival and free-hand requirements legible. The portrait gains a held
   lysate, while ATP remains unchanged.
7. `exit_ready`: shelter guidance remains valid after bridge seating and after either optional order.

## Acceptance Checks

- A baseline replay reaches the shelter with only `open_sluice -> release_bridge`; it never diverts,
  catches, or restores the optional branch.
- Baseline `solution.actions` omit the spillway catch, and each loadout records `node_04` as
  `skip_optional_interaction` / `optional_layout_traversal` while retaining the opt-in handler.
- Bridge cargo visibly travels before seating, and seating makes the main route `exit_ready`.
- Mandatory `world_actions` contain only `open_sluice` and `release_bridge`.
- Optional `world_actions` explicitly encode `divert`, `restore`, and `catch` as noncritical
  `optional_risk_reward` actions.
- Diversion visibly launches the spillway payload and drains the competing main route.
- The payload reaches `spillway_delivery_available` 2.6 seconds after launch even when the valve is
  restored during travel.
- Both `divert -> restore -> catch` and `divert -> catch -> restore` preserve the same physical reward
  and finish with the main route ready.
- Catching requires a free hand and grants no ATP until endocytosis.
- Hydraulic control hover prompts resolve the live `command` binding before naming the action, so
  input uncertainty is not mistaken for a systems-thinking failure.
- Wrong-order feedback points to the missing relationship without completing the step.
- Replay distinguishes model revision from movement or click failure.
