# Save-State And Replay Authority Standard

Status: canonical implementation standard for gameplay state, save/load, deterministic replay,
and fast-forward work.

Read this alongside the [Systems-Thinking Puzzle Design Standard](SYSTEMS_THINKING_PUZZLE_STANDARD.md),
[Design Principle Register](DESIGN_PRINCIPLES.md), and
[level-design review rubric](../data/puzzles/level_design_review_rubric.md).

## The Player-Facing Contract

A save is an observation of the one truthful simulation, not a checkpoint approximation. Loading
must restore the same causal state the player could inspect at that tick. It must not:

- finish an action for free;
- return an actor to the start while keeping a paid consequence;
- erase a committed delay, danger, carry, cooldown, or traversal;
- retain a character, wave, latch, or reward created after the save;
- replay an already-applied strike, payment, signal, or one-shot consequence;
- choose a new random result; or
- change an outcome because more or fewer render frames occurred.

These are systems-truth requirements. A reload exploit creates a second causal model: the visible
world says an action is in progress while the save says it has not happened yet. That makes player
prediction and deterministic replay untrustworthy.

## Three Different Things

Keep these concepts separate:

1. **Authoritative state** is portable data that answers what is true at the saved scheduler tick.
2. **Scheduled work** is a derived callback that advances authoritative state at an absolute tick.
3. **Presentation** is a view of authoritative state: animation, interpolation, particles, sound,
   labels, shaders, and camera emphasis.

`EventScheduler.serialize()` preserves clock, pause, and speed. It intentionally does not preserve
`Callable` objects. Scheduler determinism makes an uninterrupted run reproducible; it does not make
a scene-local phase saveable. `StateMachine` likewise owns callback lifecycle, not persistence.

## Required Authority At Commitment

The moment a gameplay action commits, write enough portable state to answer all of these:

- `identity`: which stable actor, object, interaction, or mechanism owns it;
- `phase`: what is happening now;
- `context`: origin, destination, target, route, payload, holder, group, or other causal inputs;
- `timing`: start tick and absolute next/completion deadline, when time matters;
- `progress_rule`: how state between the endpoints is calculated;
- `interruptions`: what cancels, redirects, pauses, or completes it;
- `spent_effects`: which costs and one-shot consequences have already happened; and
- `version`: the record contract version.

An endpoint-only commit is forbidden. A climber, carrier, attacker, flow payload, opening gate, or
character holding an interaction cannot remain logically at the origin until its animation ends.
Collision, targeting, saving, loading, and replay must all observe the active phase.

A typical world-state record is shaped like this:

```gdscript
{
    "version": 1,
    "phase": "opening",
    "actor_id": "aster",
    "target_id": "wreckage_gate",
    "origin": Vector3(...),
    "destination": Vector3(...),
    "started_at": 42.0,
    "deadline": 43.15,
    "cost_applied": true,
}
```

Use a stable key such as `runtime:<system>:<stable-id>`. Node instance IDs are not stable across a
fresh scene instance. If several entities share one record, their IDs and ordering must also be
stable and portable.

## Restore Algorithm

Production restoration follows this order:

1. Build required scene infrastructure and chunks without inventing run state.
2. Clear the old scheduler callback heap.
3. Restore the scheduler clock, pause state, and speed.
4. Replace authoritative GameState registries from the snapshot. Snapshot absence is authoritative:
   actors, waves, phases, and records created later must disappear.
5. Ask every presenter/owner to run `on_game_state_snapshot_restored()` or its documented portable
   restore method.
6. Each owner mirrors the saved phase without emitting gameplay signals or reapplying costs, then
   arms exactly one callback for each future absolute deadline.

If scene construction registers default characters or mechanisms, construct them before GameState
deserialization so the snapshot overwrites those defaults. Loading a chunk afterward may overwrite
the saved actor record with spawn defaults and is therefore unsafe unless attachment is explicitly
read-only.

Restore hooks must be idempotent. Calling one twice may cancel and re-arm its tag, but it must still
leave exactly one future transition and emit no synthetic `opened`, `arrived`, `hit`, `died`,
`interacted`, or reward signal.

When no authority record exists, restore the pre-commit baseline and retract local future state.
Do not publish the current scene-local phase into the freshly loaded GameState; that converts a
post-save future into history.

## Timing Rules

- Gameplay time comes from `EventScheduler`, never wall-clock time or render `delta`.
- Persist absolute deadlines in scheduler time. Remaining time is a derived readout.
- Loading after the deadline resolves the phase once according to its explicit overdue policy.
- Repeating work stores its next absolute tick, not merely its interval.
- Epoch-derived recurring callbacks must reconstruct a deadline strictly later than the current
  scheduler tick. Float-roundoff equality is a completed boundary, never a zero-delay rearm.
- Damage, detection, collision, flow arrivals, cooldowns, and hazard contacts must run on fixed or
  analytic scheduler events. `_process()` and `_physics_process()` may only project state.
- Positional gameplay predicates such as checkpoint crossings, formation arrival, concealment, and
  whole-party exits must commit from saved scheduler events or exact movement/occupancy receipts;
  neither a render frame nor a manually invoked headless presenter may make the predicate true.
- Presentation interpolation may use render `delta`, but it cannot decide whether an outcome occurs
  or how much authoritative damage/resource change occurs.

An input event may commit a command during a rendered frame; the command and its scheduler tick are
the authority. Polling a position or accumulating `delta` every frame to deal damage is not.

## Ownership Rules

- Prefer GameState for universal character, item, movement, physics, party, and economy state.
- A reusable world object may own a versioned GameState `world_state` record and rebuild itself from
  it through the standard restore hook.
- A portable `RefCounted` mechanism may expose explicit `serialize_state()` / `restore_state()` when
  its enclosing owner persists that record.
- Chunk scripts compose kit objects. They should not create a parallel consequence authority.
- Visual state is derived. Materials, shader fade, tween progress, mesh visibility, and camera pose
  are rebuilt from the authoritative phase unless a camera cutscene explicitly owns them.
- A genuinely presentation-only timer or non-persistent analysis harness must be named in the
  static guardrail allowlist with a narrow reason.

## Required Exploit Tests

Every new timed or multi-step gameplay state needs midpoint coverage for both presenter lifecycles:

1. Save before commitment, create a future phase, load, and prove the future is retracted.
2. Save in the middle, let the future complete, then load onto the same node.
3. Load the same midpoint into a freshly instanced presenter.
4. Prove phase, identity, context, already-paid costs, and spatial progress match the snapshot.
5. Advance to just before the saved deadline and prove it cannot finish early.
6. Cross the deadline and prove it completes exactly once.
7. Invoke the restore hook twice and prove only one callback/effect remains.
8. Prove restoration itself emits no gameplay signal and applies no damage/reward/cost.
9. Compare ordinary, paused, and fast-forward execution where the system has a cadence.

For roster or spawned-object systems, also save before a spawn, create it, load, and prove both the
presenter and authoritative registry entry disappear.

## Audited Authority Ledger

This ledger records the current authority boundary, not a promise that every narrative sequence is
finished. The focused verifier named in the last column is the evidence for the migrated scope.

| System | Portable authority | Restore seam / evidence |
| --- | --- | --- |
| GameState core | Character roster, movement/run/dodge/knockdown, abilities, rest/revive/field restore, endocytosis, drag/push, items, physics, pendulums, shields, external traversal, mechanisms, RNG | `verify_game_state_snapshot_authority.gd` |
| Enemy FSM | Stable character record with phase, target/context, HP, and absolute phase deadlines | `verify_enemy_save_authority.gd` |
| ChainEnemy | Enemy authority plus anchor and fixed analytic contact cadence | `verify_chain_enemy_save_authority.gd` |
| Naturalizer | Enemy authority plus grip-specific phase/context | `verify_naturalizer_save_authority.gd` |
| Interactable dwell / construction | Versioned world-state phase, actor, range state, and deadline. GameState registration events and snapshots preserve the complete HOLD / INSPECTION / TIMED_ACTION grammar (with deterministic migration from legacy `requires_hold` records), and bound presenters consume that grammar after `_ready`; a real timed source therefore cannot silently degrade into an instant inspection. | `verify_interactable_save_authority.gd` |
| PartyGate3D / PortalPad | Versioned mechanism/transit records and restore hooks; PortalPad accepts only the exact source pad and its nearby servicing body, reserves the complete solo/group cohort, actor, queue index, endpoints, arrival, and serial before each hop, then reconciles pre/post-snap signal saves without repeating or substituting a hop. Direct compatibility calls and remote selected actors are inert. | `verify_party_gate_authority.gd`, `verify_portal_pad_authority.gd` |
| CrawlTunnel / AlignmentCrossing | Group queue, slots, phase callbacks, and predicted launch deadlines | `verify_crawl_tunnel_save_authority.gd` |
| ClimbvineReturn | Exact upper/lower source receipts from nearby ready bodies, saved traversal state for the entire climb, and all-or-nothing gathered cohorts; direct `tend` / `start_climb` compatibility calls and remote selected members are inert | `verify_climbvine_return.gd` |
| HazardField / Channel | Fixed cadence, active phases, locked physical sweep carries, saved impact policy, and consequences committed only at arrival | `verify_hazard_channel_authority.gd` |
| GridRiskField | Authored-active marked-cell terrain, fixed cadence, saved roster/severity/contact history, and position-selective damage sampled only on scheduler ticks | `verify_generated_pressure_field_authority.gd` |
| Flure / Hushbloom | Versioned effect/window/poll records layered on interactable authority; picking converts the authored Hushbloom into one source-tagged canonical GameState item through a saved PICKING→PICKED transaction | `verify_flora_effect_authority.gd` |
| InfrastructureOperation | Exact source/body/proximity receipt, stable-ID saved commodity transit along a visible route, receiver enablement only on physical arrival, and an exact receiver receipt before field resolution; direct compatibility verbs are inert | `verify_infrastructure_operation_save_authority.gd`; `verify_infrastructure_catalog.gd` |
| BranchSpanProducer | The exact one-shot terminal receipt and its ready nearby body on the terminal's exact navigation floor begin one canonical GameState `extending` mechanism phase; the physical bridge, collision, and gap blocker all derive from that phase, while the actor-id compatibility helper is inert and an accepted-trigger/pre-owner restore rearms instead of bridging | `verify_branch_span_producer.gd`; `verify_generated_resource_exit_authority.gd` |
| DrawerStairProducer | Six repeatable category levers consume exact nearby source/body receipts. One shared versioned record preserves each index phase, analytic progress endpoints, absolute deadline, transition serial, and monotonic receipt provenance before visible movement; derived drawer collision, wrong-selection cover, and the sole viable deep-to-shallow non-rotten GridWorld link are rebuilt from that truth. Mid-motion reversal and accepted-before-owner restores cannot grant a drawer transition. | `verify_drawer_stair_producer.gd` |
| Flora Garden | Finite issued seed stock plus stable pad-to-growth/source-seed ownership; growth stage and tending remain canonical GameState flora truth. The crate, three planting pads, and three tend controls each consume only their exact one-shot source receipt from nearby, conscious, action-free Peris on the same navigation floor; v3 monotonic counts and saved seed/plant transactions retract accepted-before-owner seams without free seeds, growth, or daily care. | `verify_flora_garden_save_authority.gd`; CLI `--test-flora-garden` |
| Generated stretch runtime | Generated mechanism, cargo, flow, route, traversal, infrastructure-operation, theme-hazard records, and grid-risk composition with no route-choice party tax; finite node/cache/spillway resources use exact source receipts and one pre-existing GameState item identity through saved `AVAILABLE` → `CLAIMING` → `CLAIMED` phases, while EXIT atomically owns its exact roster, paid rest, and required payload delivery | `verify_generated_runtime_save_authority.gd`; `verify_generated_resource_exit_authority.gd`; `verify_generated_pressure_field_authority.gd`; `verify_infrastructure_operation_save_authority.gd` |
| Data Fragment | Chunk cadence and stable-ID infrastructure-operation state. Each weak-wall collapse consumes only its own one-shot receipt from an exact nearby, conscious, action-free party body on the same navigation floor; the saved monotonic count, absolute crumble deadline, moving external slabs, and rubble outcome reconcile accepted-trigger/pre-owner saves without granting or wedging a collapse. The exit likewise consumes its exact source receipt before a full-conscious-party, exact-footprint, atomic canonical GameState rest, with saved monotonic source count and same/fresh signal-seam recovery. | `verify_chunk_cadence_authority.gd`; `verify_infrastructure_operation_save_authority.gd`; `verify_data_fragment_shelter_authority.gd` |
| Wash Relay | v7 exact-source authority: every read, branch mechanism, override, survivor/cache/cell service, and exit consequence consumes only its own monotonic physical control receipt from the eligible nearby body; accepted-before-owner saves retract and explicitly rearm retryable sources without granting work. Fixed flood/spatial cadences, saved two-leg current carries whose shelter result commits only on impact, locked Sloperope climbs, source-tagged lysate claims, concealment, retry release, and exit truth remain derived from canonical body positions rather than render/headless frames. | `verify_wash_control_receipt_authority.gd`; `verify_wash_spatial_authority.gd`; `verify_wash_current_save_authority.gd`; `verify_channels_lifecycle.gd`; `verify_wash_branch_mechanism_authority.gd` |
| Lockout Chase | The boundary scanner and service-door control consume only their own one-shot receipt from a nearby, conscious, action-free party body; portal seals bind a specific physical seal source to a specific PortalPad and reserve that receipt, the exact held Hushbloom identity, and the absolute stun deadline before removal. Falling gantry topology, the multi-phase service door, enemy barricade/body-pile clambers, role-gated player climbs, and PortalPad-owned pursuer transit retain saved in-flight bodies. Tyreg is a stable physical GameState escort whose offer requires party/body/station/range/LOS truth and whose Suppress transaction consumes named rounds from her exact held magazine. | `verify_lockout_chase_save_authority.gd`; `verify_lockout_tyreg_authority.gd`; `verify_lockout_active_pacing.gd`; `verify_chunk_cadence_authority.gd` |
| Survival Range | Every consequence requires the exact physical one-shot control receipt from a nearby, conscious, action-free body; spatial rust-bloom cadence, information-only scouting, real Enemy lure endpoints, Capbage concealment, crossing/winch traversals, absolute lure deadline, and atomic party shelter rest remain saved authority. Direct public verbs are inert and repeatable mechanisms explicitly rearm after their causal reset. | `verify_survival_range_save_authority.gd` |
| Fragment Preview runtime | Analytic preview clock, fixed stamina cadence, absolute ability deadlines, replay-persisted autonomous camera policy, acting-character occlusion focus, and post-reset material rewrapping that preserves authored water/fog/effect shaders | `verify_fragment_preview_runtime_authority.gd`; `verify_replay_occlusion_lifecycle.gd` |
| Reusable SceneChunk shelters | Explicit authored shelter footprints and required-member lists; absence, incapacity, movement, or exact-footprint failure blocks before one canonical atomic GameState party-rest command | `verify_scene_chunk_party_rest_authority.gd` |
| Reusable SceneChunk mechanisms | v3 exact nearby source/body receipts and monotonic counts for sump, silo, and belt controls; sump rearms only after its physical level transition commits, while silo/belt remain owner-derived one-shots. Accepted-before-owner saves are consumed without granting water, avalanche, or power; v2 phases migrate with their original deadlines | `verify_scene_chunk_mechanism_save_authority.gd` |
| Leaving Facility | Endo's ABSENT/PENDING/JOINED record installs his body and party membership before JOINED is observable; three ordered PartyGate3D route records own absolute lift deadlines and versioned context; the fixed Shelter 1 footprint requires the complete conscious trio and commits one canonical atomic GameState party-rest transaction with a saved dawn deadline; causal narrative handoffs are named portable method/dialogue continuations | `verify_leaving_facility_endo_join_authority.gd`; `verify_leaving_facility_gate_save_authority.gd`; `verify_leaving_facility_shelter_authority.gd`; `verify_leaving_facility_continuation_authority.gd` |
| Puzzle Atom | v5 stage lures begin only from the exact two-second physical Flure/Peris source receipt; the real Enemy body owns reachable outbound settlement and return. Stage races, retry state, fixed-cadence full-conscious-party checkpoint receipts, canonical party shelter rest, completion, and saved spatial-poll deadline survive same/fresh restores; render/headless presenter calls cannot clear a gate | `verify_puzzle_atom_save_authority.gd` |
| Flure teaching atoms | Exact physical Flure source receipts drive saved lure/return windows; retired helper and forged-signal seams are inert. Fixed-cadence full-conscious-party exit checks reject selected-portrait or lone-runner completion | `verify_remaining_chunk_save_authority.gd`; CLI `--test-distract-gate`, `--test-lure-relay` |
| Set Piece / Boss showcases | Hub wheel, water valve, loose strut, hoist switch, and hoist lever consequences require their exact control receipt and nearby ready body. Boss survey, winch, and brake likewise consume only their own sources; saved monotonic counts, the complete winch sweep batch, and a reserved brake target transaction reconcile accepted-trigger seams. Basin, slab, analytic magnet lift/drop phases with grounded-station truth, trolley/hub transit, scree, and fixed Spiker cadence remain portable, while the exact source-tagged reservoir vial resolves one saved AVAILABLE→CLAIMING→CLAIMED canonical-item transaction. | `verify_set_piece_save_authority.gd`; `verify_boss_control_transactions.gd`; CLI projection-alignment and Boss playable checks |
| Refuge Run | A saved fixed spatial cadence commits route choice only from an exact conscious body crossing a painted lane and owns spatial bloom damage plus Scarpet/slit/spot concealment. The registered Flure, sweep pulse, and exit shelter require exact source/body/proximity/consumed-trigger receipts; direct compatibility verbs are inert. Refuge deadlines, real Enemy consequences, registered enclosures, and the exact-trio COMMITTING→RESTED transaction remain portable and reconcile signal-time save seams. | `verify_refuge_run_system_authority.gd` |
| Showcase Room | Canonical GameState HP, one saved fixed scheduler cadence for iron exposure, saved discrete-impact i-frame deadlines, and no duplicate host damage after Enemy has already committed its strike | `verify_showcase_room_save_authority.gd`; CLI `--test-showcase` |
| Showcase Gallery | Per-body concealment derived from physical Scarpet/Capbage occupancy; versioned, source-validated evidence for every shipped hiding/enemy/flora response; and one exact-trio regroup record whose saved positions all cross the exit threshold | `verify_showcase_gallery_spatial_concealment.gd`; CLI `--test-showcase-gallery` |
| Rings reassignment / departure | Marco's canonical one-shot accepts only Peris with conscious, available, action-free Peris and Endo physically gathered beside him; the v3 record preserves actor, commit tick, and both positions before beginning Endo's locked departure traversal, whose arrival owns roster, presence, selection, and visibility removal. Client Bloom, Propagation, and Forget-Me-Not each consume an independent exact one-shot Peris source/body receipt with saved monotonic counts and accepted-before-owner retraction; they remain order-free informational observations and never gate or complete the route. | `verify_rings_departure_save_authority.gd` |
| Mother Flure | Exact source/actor/proximity/consumed-trigger receipts for every terminal, portal, root bud, collapse, corpse, gear lift/mount, Mother tending, and exit; saved root/debris shifts, installed gear truth, membrane opening, endpoint-committed portal traversal, fixed root-hazard cadence, and finite source-tagged corpse items. Retired consequence verbs are inert and accepted-trigger save seams reconcile without granting or wedging work. | `verify_mother_flure_save_authority.gd`; `verify_mother_flure_body_source_authority.gd`; `verify_mother_flure_quality_extension.gd` |
| Inflammashunt | All nineteen authored actions consume only their exact one-shot source receipt from the required nearby, conscious, action-free body; monotonic saved receipt counts retract accepted-trigger/pre-callback saves while retired consequence helpers remain inert. Valve-water, root growth/recovery, buffer reform, and housing opening retain absolute deadlines and visible midpoints. The gas sac and catalyst use exact source-tagged GameState items with saved AVAILABLE/CLAIMING/CLAIMED-style transactions, holder/free-hand truth, duplicate suppression, and durable claimed tombstones; hand/drop/transfer ownership alone drives the repellent aura. | `verify_inflammashunt_process_authority.gd`; `verify_remaining_chunk_save_authority.gd`; CLI `--test-inflammashunt` |
| Endo Junction | Every read, route mark, cache, safe/direct crossing, shortcut, and shelter consequence consumes the exact world-interactable receipt from its nearby ready body; selected-portrait and direct compatibility calls are inert. Saved route commitments, spatial HazardField damage, external traversals, return-grate PartyGate topology, the exact wall-cache item transaction, and atomic party rest reconcile accepted-trigger and signal-time restores without replaying work. | `verify_endo_junction_save_authority.gd` |
| Channels Wash Intro | Saved cadence/polls plus party and hunter Channel carries; drown provenance commits only on arrival and is accepted at the exit only while every matching stable Enemy body is dead at its downstream endpoint | `verify_channels_wash_intro_authority.gd`; `verify_channels_lifecycle.gd` |
| Stacks | Canonical bank one-shots require physical Aster and an accepted source trigger receipt before recording evidence or a prediction; inert legacy helpers cannot advance them. The derived shelter one-shot requires its active party body plus the exact conscious trio in the authored region, then publishes COMMITTING→RESTED before one canonical atomic party rest; anxiety/completion follows only that physical paid outcome and reconciles same/fresh signal-time saves | `verify_stacks_fragment_save_authority.gd` |
| ATP scarcity clock | Portable snapshot published into GameState, including next absolute tick | `snapshot()` / `restore()` contract and scarcity regression suite |
| FlowRouterValve | Explicit portable route and in-flight flow records | `serialize_state()` / `restore_state()` contract |
| Tutorial base continuations | Versioned named-method records for fades and dialogue chains, absolute gameplay/UI clocks, and exact active dialogue page/typewriter state | `verify_tutorial_continuation_authority.gd`; unnamed callback fallbacks remain bounded below |
| Tag Day | Saved accepted movement receipts and physical formation endpoints; explicit whimper/lockdown/scan/clearance callback phases; opening checkpoint, conversation, scan, and failed-scan handoffs use named portable method/dialogue continuations with exact deadlines | `verify_tag_day_grip_authority.gd`; `verify_tag_day_escort_callback_authority.gd`; `verify_tutorial_continuation_authority.gd` |
| Aster Sim | The forecast terminal and drink machine each consume only their own monotonic one-shot receipt from nearby, conscious, action-free Aster. v2 terminal/drink records retract accepted-before-owner saves without granting or wedging the action; the drink then owns one canonical lysate/endocytosis transaction. Ron's accepted physical approach, terminal focus/settle phases, exact transition deadline with camera/input reconstruction, and named causal continuations remain portable. | `verify_aster_drink_authority.gd`; `verify_aster_sim_sequence_authority.gd`; `verify_aster_linear_continuations.gd` |
| Peris Sim | The watering-can pickup and fern service each consume only their exact one-shot source receipt from nearby, conscious, action-free Peris; v2 per-source counts, exact can/mechanism provenance, and owner-derived rearm retract accepted-before-owner saves without free inventory or watering. Versioned visit, exploration, Wrap, HUD, hint, dialogue, and transition phases remain reconstructible. | `verify_peris_watering_authority.gd`; `verify_peris_sim_sequence_authority.gd` |
| Elevator bridge, lower route, Endo handoff, Junction rest, hazards, wreckage, and gauntlet | Versioned sequence records cover Endo's physical entrance and canonical carried-water handoff; lower-route authority stores learned overlays, exact per-body crossing/source-window history, and cautious-grid knowledge while each real Flure remains the sole owner of its active phase and deadline; Junction night requires the exact conscious trio inside the authored shelter, consumes that water, commits one atomic party-rest batch, and reconstructs its absolute watch deadline; armed/falling/landed bridge collapse uses GameState external traversal; three-body gauntlet formation, real Enemy/Flure windows, midpoint arming, defeat/reset, and transition deadlines commit only after their physical endpoints | `verify_elevator_route_flure_authority.gd`; `verify_elevator_endo_handoff_authority.gd`; `verify_elevator_junction_rest_authority.gd`; `verify_elevator_runtime_save_authority.gd`; `verify_elevator_bridge_collapse_save_authority.gd`; `verify_elevator_gauntlet_intro_authority.gd`; `verify_elevator_gauntlet_runtime_authority.gd`; other narrative choreography remains bounded below |
| Act 1 campaign / Channels causal core | Stable-ID Enemy FSM bodies, reusable Flure effect windows, Channel-owned physical wash carries/impacts, swept provenance that remains gated by the corresponding dead Enemy bodies, mirrored GridWorld cover, and a source-bound one-shot Channels hearth whose exact gathered trio commits canonical party rest. Integrated Stacks banks/shelter and optional terminal/signal/archive observations likewise require their physical one-shot receipts; the support log can be viewed only after the terminal acquires it. Rings requires the exact Marco one-shot's gathered Peris/Endo receipt before Endo's locked departure, and optional residential knowledge comes only from its exact trace source. The v3 room record remains limited to roster/phase/result bookkeeping; active-chunk topology, campaign-host phases, and every linear handoff are portable. No proxy swarm, analytical wash, remote compatibility helper, render-owned consequence, or anonymous gameplay callback may advance the route. | `verify_act1_channels_runtime_save_authority.gd`; `verify_channels_longform_extension.gd`; `verify_stacks_rings_longform.gd`; `verify_act1_rings_departure_authority.gd`; `verify_act1_linear_continuations.gd` |
| Campaign iron (Act 1 / Leaving Facility) | Fixed scheduler cadence with versioned records, exact next ticks, and portable exposure evidence | `verify_campaign_iron_save_authority.gd` |
| Capture/modal pause | Save snapshots strip transient capture pause while preserving a genuine pre-existing player pause | `verify_capture_pause_save_authority.gd` |

The machine-readable companion is
`tools/verify_save_authority_guardrails.gd`. Adding a scheduler-owning gameplay file requires either
an audited authority entry or a narrowly documented debt/allowlist entry. New unclassified owners
fail the verifier.

## Bounded Debt

These scopes are intentionally visible debt, not implicit permission for similar code:

- `tutorial_sequence.gd` now reconstructs every named fade, named method delay, and named
  dialogue-chain continuation, including the exact dialogue page and inter-line delay. Its
  compatibility path for anonymous or foreign Callables remains scene-local debt until every
  external caller uses stable continuation IDs.
  Act 1 Channels' Enemy/Flure/Channel causal core and physical formation/endpoint gates are
  authoritative; every Act 1 linear story and campaign handoff now uses a stable named continuation.
  Peris Sim's visit handoff, exploration gate, Wrap transaction, post-Wrap sequence phases, and room
  presentation observers now use named endpoints and are covered by its focused authority verifier.
- Elevator's lower-route knowledge/crossings and source-owned Flure windows, Endo entrance/handoff,
  exact-trio Junction rest, hazards, wreckage, bridge collapse, and complete three-body gauntlet run
  are authoritative. Optional Junction observations and route-choice dialogue choreography still
  need per-phase midpoint coverage before the entire sequence can be called audited.
- Interactable's no-scheduler dwell fallback is restricted to standalone/non-persistent previews.
  Production-bound interactables must receive the scheduler and use their authoritative dwell
  record.

Debt is exact and ratcheted. When a case is migrated, remove its verifier entry and this note in the
same change. Do not broaden an exemption to make a new warning disappear.

## Review Checklist

Before approving a gameplay phase:

- Is there one stable source of truth at every intermediate tick?
- Does commitment immediately write phase, context, and already-paid effects?
- Does the record carry absolute deadlines and an interruption policy?
- Does snapshot absence retract post-save future state?
- Can same-node and fresh-node restore rebuild the phase without emitting effects?
- Are callbacks derived and idempotently re-armed after the scheduler heap is cleared?
- Can `_process`, camera state, shaders, animation, or frame rate change an outcome?
- Does the failure/reload behavior preserve the causal model the player was shown?
- Is there a midpoint exploit regression, not only an endpoint serialization test?
