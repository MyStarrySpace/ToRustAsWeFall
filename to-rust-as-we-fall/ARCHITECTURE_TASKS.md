# Architecture Implementation Tasks

Derived from `game_architecture.md`. Tasks are ordered by dependency — later tasks assume earlier foundations. Success conditions are written to be automatable via the headless test runner (`--test-*` flags in `scripts/test_runner_cli.gd`) or the CLI playthrough harness (`--cli`) wherever possible.

Distinct from `TASKS.md`, which tracks prototype-port feature work. Where overlap exists, the relevant prototype-port phase is noted.

---

## 1. Event-sourced state foundation

Everything else in the doc ("recording and playback come for free", save integrity, determinism testing, Psy-Knapse mechanic) sits on this. Extends the existing `EventScheduler` into an authoritative, replayable *event log*.

**Architectural decision (locked in by 1.1–1.5):** the log records *external commands* (player/sequence/AI inputs), not internal state mutations. The deterministic scheduler reproduces all internal mutations (movement arrivals, dodge ends, collision fires, etc.) when the same commands are replayed against an identical starting state. This avoids logging every interpolated tick and keeps the log compact, but it makes the scheduler's determinism load-bearing — every divergence between record and replay is a scheduler-determinism bug.

**Tick-drain decision:** the log carries `recorded_until: float` alongside the event array. Replay drains pending scheduler events up to this tick at the end of replay so movements still in flight at save time complete identically. Callers that advance the scheduler without issuing commands (e.g. waiting for a character to arrive) must call `GameState.flush_tick()` before serializing.

- [x] **1.1** Define `GameEvent` schema: `{tick: float, kind: StringName, payload: Dictionary}`. Plain-data payloads only. — [scripts/game/game_event.gd](scripts/game/game_event.gd)
- [x] **1.2** Audit all state mutations in `game_state.gd`. All public commands route through `_emit`. Lint `--test-event-log-mutation-audit` enforces the invariant by parsing every public function and failing if it mutates without emitting (queries/snapshot helpers are allowlisted with justification).
- [x] **1.3** Add `EventLog` class (append-only, in-memory) with `recorded_until` tracking. — [scripts/game/event_log.gd](scripts/game/event_log.gd)
- [x] **1.4** Add `GameState.replay(log, grid, ability_handlers)` that constructs fresh state by replaying events. Full dispatch table for movement, items, physics, pendulums, dodge, abilities. Drains pending scheduler events up to `log.recorded_until` so movements in flight at save time arrive identically.
- [x] **1.5** Add event-log serializer (`to_bytes` / `from_bytes` via `var_to_bytes`). Versioned header (`FORMAT_VERSION = 1`).

**Resolved — Callable payloads:** `queue_ability` keeps its `Callable` parameter for game-code ergonomics, but the log records only the ability *id* (a `String`). At replay time, `GameState.replay(log, grid, ability_handlers)` consults an `ability_id → Callable` dict to fire the right behavior. Abilities without a registered handler dispatch as no-ops — the queue + range-arrival still happen, just no behavior. Game code that wants replay-safe abilities registers handlers at startup via `GameState.register_ability_handler`.

**Resolved — internal command calls polluting the log:** when one public command (e.g. `queue_ability`) internally called another (e.g. `command_move_to_pos`), the inner call also emitted, producing redundant events on replay. Fixed by extracting `_do_move_to_pos` and `_do_stop` private helpers that mutate state without emitting. Public commands now follow the pattern `_emit(...); _do_*(...)`. Internal callers use the `_do_*` variants.

**Success conditions**
- [x] `--test-event-log-roundtrip`: 34/34 assertions passing across movement, items, physics, pendulums, dodge, and abilities. Final positions and stats match within FP epsilon. Replay does not re-append to its own log. Unregister round-trips. Ability handler registry verified.
- [x] `--test-event-log-mutation-audit`: parses every public function in `game_state.gd` and fails if it mutates state without `_emit`. Allowlist documents the exceptions (queries, snapshot/restore helpers, log infrastructure). Negative-test verified by adding a sentinel function and confirming the lint catches it.
- [x] CLI: `--cli --record out.log` writes the log + a state snapshot. `--cli --replay out.log` replays against the scene's grid and asserts the replayed final state matches the snapshot, exiting 0/1. Round-trip verified end-to-end. Recording uses `GameState._pending_event_log` so the log captures the session from the scene's first `register_character` onward.

---

## 2. Seeded deterministic RNG

Pairs with #1. Without this, replays diverge and everything downstream (#3, #11, #13) breaks.

**Survey finding (locked in by 2.1):** no game-logic system currently uses randomness. All existing `randf` / `randi` / `Time.get_ticks_msec` calls are visual (light pulses, camera shake, debris scatter) or test/analysis code. The lint catches future drift; existing visual code is annotated rather than rewritten.

**Annotation convention:**
- Per-line: `# @rendering_only` at the end of a line allows that single line to use Godot's globals.
- File-level: `# @rendering_only_file` near the top exempts the whole file. Use only for files that are 100% visual (camera, fragment chunks, decoration-heavy sequence scripts).

- [x] **2.1** Lint-gated check on `randi()`, `randf()`, `randomize()`, `RandomNumberGenerator.new()`, `Time.get_ticks_*`, `Time.get_unix_time_from_system()`. Existing visual usages annotated with `@rendering_only` or `@rendering_only_file`. Save-metadata files (`save_manager.gd`, `engram_journal.gd`) and analysis harnesses (`hide_encounter_analysis.gd`) are explicitly allowlisted.
- [x] **2.2** `SeededRng` wraps `RandomNumberGenerator`; constructor requires an explicit seed. — [scripts/game/seeded_rng.gd](scripts/game/seeded_rng.gd)
- [x] **2.3** `RngRegistry` keyed by `(system_name, birth_id)`. Seeds derive from `base_seed * 1000003 ^ hash(system_name) * 1000003 ^ birth_id` — XOR alone collapses too many keys, so we mix with a large odd prime first. — [scripts/game/rng_registry.gd](scripts/game/rng_registry.gd)
- [~] **2.4** `GameState.base_seed` exists with `set_base_seed(value)` setter that re-seeds the registry. `EventLog.base_seed` carries it through save/replay; `GameState.replay` re-seeds from the log. **Pending:** title-screen + pause-menu UI for player-visible seed entry (UI work, not engine work).
- [~] **2.5** RNG consumption events. The schema and registry support per-spawn `birth_id` derivation, so a Techo born at event N gets a deterministic seed without explicit logging. **No RNG-consumption events emitted yet** because no game system uses RNG; will be added per-system as systems land.

**Open issue — SeededRng.set_state pitfall:** the initial implementation set `_rng.state = 0` after `_rng.seed = seed_value`, which discarded the seed's effect (every instance produced identical output). Fixed by removing the state reset; the seed setter on `RandomNumberGenerator` derives the initial state. Documented in code so it doesn't regress.

**Success conditions**
- [x] `--test-rng-determinism`: 6/6. Same seed → same value sequence (across multiple systems). Different seed → different sequence (same system). Per-system isolation: extra `ai.techo` calls do not perturb `loot` output. Per-spawn isolation: same system with different `birth_id`s produces independent streams. `GameState.replay` propagates the log's `base_seed` and re-seeds the registry.
- [x] `--test-rng-no-wallclock`: walks `scripts/`, fails if any `.gd` line uses a wall-clock pattern (`randi`, `randf`, `randomize`, `RandomNumberGenerator.new`, `Time.get_ticks_*`, `Time.get_unix_time_from_system`) outside the allowlist or without `@rendering_only` / `@rendering_only_file`. Currently passing on a clean tree.
- [ ] Two replays of the same event stream produce identical logs when re-recorded — covered indirectly by the determinism test today; will get an explicit `--test-rng-rerecord-stable` test alongside the first game system that uses RNG.

---

## 3. Save / load as event log

Falls out of #1 and #2. Not a separate subsystem — it's the log plus a base seed.

**Format decision (locked in by 3.1):** v1 was a single `var_to_bytes` blob (atomic, no partial recovery). v2 is length-prefixed: `[8-byte magic][u32 header_len][header dict][per event: u32 ev_len + event dict]`. A truncated stream stops cleanly at the last fully-written event; a corrupted event blob terminates loading at that point. Everything before the failure is returned as a partial log. The cost is a few extra bytes per event for length prefixes; the benefit is that crash-truncated saves (mid-write) load as far as they can.

- [x] **3.1** Save format v2: header (`{version, base_seed, recorded_until, saved_unix}`) + length-prefixed events. `EventLog.to_bytes()` writes the whole stream; `EventLog.load_bytes()` returns `{log, status, recovered}`. Header lacks `build_hash` because there's no build pipeline yet — added when one exists.
- [x] **3.2** Load = `GameState.replay(log, grid, ability_handlers)`. Replay re-seeds from `log.base_seed` and drains pending scheduler events to `log.recorded_until` so movements in flight at save time arrive identically.
- [x] **3.3** Corrupt-save handling: `EventLog.load_bytes` returns one of `LoadStatus.{OK, TRUNCATED, CORRUPTED, BAD_HEADER}`. The returned log always contains every event that decoded cleanly before the failure point. UI signal not yet wired — the status is the API; an autoload or game-level handler can emit a user-visible signal when it gets a non-OK status.
- [ ] **3.4** Quick-save / quick-load hotkeys. **Deferred** until there's a game-level input controller to host them. The save/load API exists (`EventLog.to_bytes` / `load_bytes`); SaveManager needs a `save_event_log(slot)` / `load_event_log(slot)` wrapper, and the input map needs `quick_save` / `quick_load` actions wired to a global handler.

**Success conditions**
- [x] `--test-save-load-integrity`: 7/7. Drive a 20-step scripted sequence; snapshot bytes mid-run, continue to end, snapshot again. Then load mid-bytes into a fresh GameState via replay, continue with the same second-half commands, snapshot end. Continuous and resumed runs produce equal final state. `base_seed` and event count round-trip cleanly through bytes.
- [x] `--test-save-corruption-recovery`: 7/7. Truncate a clean log to 80% of its bytes; `load_bytes` returns `TRUNCATED` status with the events that fit fully recovered. Replay of the partial log yields a valid mid-state. `BAD_HEADER` returned for streams missing the magic, with an empty log.

**Supersedes** prototype-port Phase 19 (Save/Load). Phase 19 can be deleted once 3.4 lands and SaveManager wraps the event-log API.

**Open issue — `set_base_seed` propagation:** Initially the base seed lived only on `GameState`, so save files written by a recording session lost the seed (the EventLog had its own default-zero `base_seed`). Fixed: `GameState.set_base_seed` now propagates to `event_log.base_seed` if a log is attached. Tests caught this immediately.

---

## 4. Actuator abstraction

World-as-physical-system. Pressure plates, triggers, and mechanisms respond to physical conditions, not to character identity.

**Design decision (locked in by 4.1–4.2):** `Actuator` is plain data (`position`, `weight`, `signature`), not a base class anything inherits. `GameState.get_all_actuators()` builds the list on demand from characters/items/physics_objects. Mechanisms see the list filtered to their zone and evaluate a pure condition. This makes the contract impossible to misuse: a Mechanism that wants more than the three Actuator fields would have to query GameState directly, which the lint catches.

- [x] **4.1** `Actuator` data class with `position`, `weight`, `signature`. — [scripts/game/actuator.gd](scripts/game/actuator.gd). `GameState.get_all_actuators()` reads characters' `stats.weight` (default 1.0), items' `properties.weight` (default 0.0), and physics objects' `mass`.
- [x] **4.2** `Mechanism` base class with `id`, `position`, `radius`, `update(actuators)`. Emits `triggered` / `untriggered` on transitions; idempotent. `WeightMechanism` subclass triggers when summed weight in zone ≥ threshold. — [scripts/game/mechanism.gd](scripts/game/mechanism.gd), [scripts/game/weight_mechanism.gd](scripts/game/weight_mechanism.gd)
- [ ] **4.3** Migrate existing pressure-sensitive interactables. **N/A:** `interactable.gd` is proximity-based, not weight-based — no pressure-sensitive interactables exist yet to migrate. The `WeightMechanism` is in place for the first scene that needs one.
- [~] **4.4** Heavy-item → weight mapping in `item_data.gd`. **Pending:** the schema supports `weight` as a per-type property, but the existing item types (`mother_gear`, `fragment`, `fire_fruit`, etc.) don't yet declare weights. Tests pass weights via `properties` overrides. Will land alongside the first scene that uses pressure plates.

**Open issue — `evaluate_mechanisms()` is on-demand only:** runtime scenes need to call `evaluate_mechanisms()` after any change that may have shifted actuator positions. Not auto-fired from movement / drop / pickup yet because there are no live mechanisms in the running game. When the first scene wires a pressure plate, hook it into the scheduler-driven movement-arrival path the way detection prediction works today.

**Success conditions**
- [x] `--test-actuator-composition-blind`: 9/9. A weight-2.0 plate triggers identically when activated by (a) one heavy character (weight 2.5), (b) two light characters (1.0 each), (c) one heavy item, (d) one character + one item summing to threshold. Single light character does not trigger; actuator outside the zone does not trigger; transitions fire once on enter/leave; re-evaluation is idempotent.
- [x] `--test-actuator-no-id-checks`: 2/2. Walks `scripts/` for files in the Mechanism class hierarchy (auto-discovered to fixed point), greps for forbidden patterns (`char_id`, `is_character(`, `characters[`, `characters.has(`, `"item_id"`). False-positive doc-comment match caught by reading the lint output and rewording the docstring.

---

## 5. Composition-independent puzzle harness

Every cure puzzle must be solvable by Aster + Peris alone. This task builds the harness that enforces that invariant.

- [ ] **5.1** Define `PuzzleScenario`: puzzle-id, min-composition (always Aster + Peris), items-on-hand, environmental state.
- [ ] **5.2** For each authored puzzle (start with Inflammashunt), write a CLI script that solves it with the min composition.
- [ ] **5.3** Add CI job that runs all min-composition scripts. A puzzle without a passing min-composition script is a build failure.
- [ ] **5.4** Add optional "extended-composition" scripts that document the more graceful solution path when recruits are present.

**Success conditions**
- Every puzzle in `data/puzzles/` has a corresponding `tests/puzzles/<id>_min.cli` script that completes with exit 0 using only Aster + Peris.
- `--test-all-puzzles-min-comp` runs the whole suite and fails if any puzzle lacks a min-composition solution.

---

## 6. Hub / spoke / gate scaffolding

Game-shape primitives. Zones are data; hubs and gates are nodes with explicit roles.

**Design decision (locked in by 6.1–6.4):** Zone is a plain `Resource` with exported fields so scenes can declare zones in `.tres` files. Hub and Gate are `RefCounted` data classes, not `Node3D` — they're referenced by scene-level nodes via id. `ZoneManager` is `RefCounted` (not an autoload) so tests can construct one per scenario. This decouples the model from the scene tree; when we later need a scene-tree integration, a Node wrapper can hold a ZoneManager reference.

**Design decision (locked in by 6.5):** narrative-availability is a per-character bool stored in `stats["narrative_available"]`. `down_character` / `restore_character` are logged commands (emit through `_emit`). They're issued by combat code (on HP → 0) and by hubs (on rest). Both are replay-safe because they go through the event log.

- [x] **6.1** `Zone` resource with `id`, `display_name`, `hub_ids`, `spoke_ids`, `gate_ids`. — [scripts/game/zone.gd](scripts/game/zone.gd). (The `essential_third` field was removed when #8 was dropped.)
- [x] **6.2** `Hub` class with `id`, `zone_id`, `position`, `radius`, and a `restore_party(gs, party)` static helper. Entering a hub triggers `restore_character` for every party member — each restore goes through the log. — [scripts/game/hub.gd](scripts/game/hub.gd)
- [x] **6.3** `Gate` class with `required_members` and `try_pass(gs, party) -> bool`. Emits either `passed` or `blocked(reason: StringName)` exactly once per call. Reasons are `missing_<id>` (not in party) or `unavailable_<id>` (downed / narratively unavailable). — [scripts/game/gate.gd](scripts/game/gate.gd)
- [x] **6.4** `ZoneManager` with registries for zones/hubs/gates and signals `zone_entered`, `zone_exited`, `hub_entered`, `gate_passed`, `gate_blocked`, `spoke_completed`. Tracks current zone, hub, completed spokes, and passed gates. `is_hub_reachable(hub_id)` returns true only for hubs in the currently-active zone — implements the "old hubs fall out of practical reach" semantics. **Not an autoload** — instantiated per scene. — [scripts/game/zone_manager.gd](scripts/game/zone_manager.gd)
- [x] **6.5** Hub-rest flow: `down_character` and `restore_character` commands on GameState, both logged. Rest sets HP/stamina to declared max values (from `stats.max_hp` / `stats.max_stamina`) and ATP to `SurvivalStats.ATP_MAX_PIPS`, and flips `narrative_available` to true.

**Open issue — evaluate_mechanisms / enter_hub auto-trigger:** scenes today must call `zm.enter_hub(...)` manually when the party reaches the hub's radius. Automating this via movement-arrival signals is straightforward (detection prediction pattern) but deferred until the first scene wires a live hub.

**Open issue — party membership is test-side:** ZoneManager's methods take an explicit `party: Array` parameter rather than querying a canonical source. With #8 dropped, the canonical party model is just "who's currently recruited" — arrives alongside #9 (cohesion) and recruitment flow.

**Success conditions**
- [x] `--test-hub-rest-restore`: 7/7. Down a character; HP/stamina zero; narrative-available flips false. Rest at hub; HP/stamina restored to declared max, ATP to full, narrative-available true.
- [x] `--test-gate-block`: 8/8. Gate requiring Endo blocks without Endo (reason `missing_endo`). Adding a downed Endo still blocks (reason `unavailable_endo`). Restoring Endo and retrying → passes once.
- [x] `--test-zone-progression`: 17/17. Two-zone scripted run: enter zone A, both A hubs reachable, zone B's not. Enter hub, mark spoke complete, pass gate. Enter zone B → `zone_exited(channels)` fires, zone A hubs fall out of reach, zone B hub becomes reachable.

---

## 7. Failure / recovery model

No game-over. Downed ≠ dead. Retreat to hub = full recovery.

**API shape (locked in by 7.1–7.4):**
- `down_character` / `restore_character`: combat and rest, fully recoverable, logged commands (added in #6).
- `die_scripted(char_id)`: the ONLY path to permanent death. Sets `stats.dead = true`, emits `character_died(char_id, true)`. The `scripted` flag on the signal is always true because `die_scripted` is the sole emission site; the parameter is there to document intent and to make the lint explicit.
- `is_downed(char_id)` / `is_party_downed(party)`: queries.
- `ZoneManager.retreat_to_last_hub(gs, party) -> bool`: restores every party member and fires `party_retreated(hub_id)`. Returns false if no hub has been entered yet (the party has nowhere to retreat TO — scenes should prevent this by ensuring a hub is entered before spokes begin).

- [x] **7.1** `downed` state as `stats.narrative_available == false` (set by `down_character`). Not a separate state-machine node — the existing stat dict carries the flag, which is reachable via `is_downed(char_id)`.
- [~] **7.2** "Remove any remaining game over code paths". **Machinery in place:** `retreat_to_last_hub` + `party_retreated` signal give scenes the replacement. **Existing content not migrated:** `tutorial/elevator_sequence.gd` has a "We Fell" game-over path at `_start_game_over()` (iron spill failure). Migration is content work — when the elevator scene is rewritten, swap the fade-and-end for `zm.retreat_to_last_hub` + a specific retreat point. Flagged here; not changed in this slice.
- [x] **7.3** Permadeath via scripted events only. `character_died.emit(` appears in exactly one place (`die_scripted`). The `--test-scripted-death-only` lint enforces this by scanning all production `.gd` files and rejecting emissions in any other function.
- [x] **7.4** Downed-party-recovery primitive. Game code can check `gs.is_party_downed(party)` in its spoke loop and call `zm.retreat_to_last_hub(gs, party)` when it returns true. Auto-trigger on every `character_downed` signal is a straightforward extension; left to scene code because the "spoke loop" is scene-specific.

**Success conditions**
- [x] `--test-no-game-over`: 12/12. Down all party members in a spoke → no `game_over`-style signal, no `character_died`, `is_party_downed` is true. `retreat_to_last_hub` returns true, emits `party_retreated(hub_channels)`, every member's HP/stamina restored to max, narrative-available true. Retreat without a prior hub returns false cleanly.
- [x] `--test-scripted-death-only`: 1/1. Walks `scripts/` (excluding the test runner itself, which references the signal name in lint strings and docstrings). Flags any `character_died.emit(` call outside `die_scripted`. Negative-test verified with a sentinel function.

---

## 8. ~~Load-bearing spine + rotating essential third~~ — REMOVED

**Design change (2026-04-18):** dropped the "rotating essential third" model. The game is beatable with Aster and Peris alone; every ally can be refused. This is a stronger form of the architecture doc's original thesis ("every puzzle must be solvable by Aster and Peris alone") — we are committing to A+P sufficiency even for zone-specific gates, not just for puzzles.

**Consequences for other tasks:**
- Gates keep their per-gate `required_members` list (#6). Games with Aster+Peris-only runs simply declare gates with empty `required_members` (any-party) or `[aster, peris]` (which is always satisfied by the spine).
- No `zone_third` concept in ZoneManager. A canonical party source still needs to land (currently ZoneManager takes `party: Array` explicitly) but the party model is just "who's currently recruited" — no essential-member distinction.
- Zone resource's `essential_third` field removed (dead code).
- `--test-spine-sufficiency` is now trivially satisfied by construction and doesn't need to exist as a runtime test; content review will enforce it during level design.

---

## 9. Party cohesion default

Party moves as a unit. Splits are scripted.

- [ ] **9.1** Movement command defaults: clicking a destination moves whole party (formation + follow).
- [ ] **9.2** `PartySplit(members: Array, duration_or_event: Variant)` — scripted-only API; not exposed to player input.
- [ ] **9.3** Out-of-split movement commands always target whole party.

**Success conditions**
- `--test-party-cohesion-default`: issue move command, assert all party members have movement events queued to formation slots.
- `--test-scripted-split`: start a scripted split, assert only split members move independently; end split, assert reunification.

---

## 10. Portal / backtracking

Designed-affordance backtracking. Zones change on revisit.

- [ ] **10.1** `Portal` node: data-driven destination zone-id + re-entry hub-id.
- [ ] **10.2** `ZoneState` snapshots: on zone-exit, persist zone's stateful entities (enemy populations, NPC states, environmental flags); on re-entry, apply zone's revisit-state transforms (new enemies, shifted NPC states).
- [ ] **10.3** Author the Inflammashunt revisit state as first example.

**Success conditions**
- `--test-portal-revisit`: complete a zone, take portal to a different zone, return via portal, assert enemy roster / NPC states / environmental flags differ from first visit per revisit-state spec.

---

## 11. Scene triggering

Ordered trigger priorities: spoke-completion, gate-pass, milestone, time-of-day.

**Design decisions (locked in by 11.1–11.3):**
- Context is a plain `Dictionary` with a `kind: StringName` field and kind-specific payload (e.g. `spoke_id`, `gate_id`). Keeps the surface duck-typed and open to new trigger types without modifying the base class.
- Default priorities encode the narrative hierarchy: gate-pass (30) > milestone (20) > spoke-complete (10) > time-of-day (0). Ties break by registration order so scene authors can control resolution by ordering their `register_trigger` calls.
- Time-of-day triggers default to `one_shot = false` because they're ambient flavor that repeats each cycle; every other type defaults one-shot.

- [x] **11.1** `SceneTrigger` base class with `scene_id`, `priority`, `one_shot`, `evaluate(context) -> bool`. — [scripts/game/scene_trigger.gd](scripts/game/scene_trigger.gd)
- [x] **11.2** Concrete triggers `OnSpokeComplete`, `OnGatePass`, `OnMilestone`, `OnTimeOfDay` bundled in one file as the naming conveys ("these are the four"). — [scripts/game/scene_triggers.gd](scripts/game/scene_triggers.gd)
- [x] **11.3** `SceneManager` (RefCounted, not autoload) with `register_trigger`, `dispatch(context)`, `scene_fired(scene_id, context)` signal, and `bind_zone_manager(zm)` convenience that wires `spoke_completed` and `gate_passed` through. — [scripts/game/scene_manager.gd](scripts/game/scene_manager.gd)

**Open item — milestone / time-of-day wiring:** `bind_zone_manager` covers spoke + gate events. Milestone and time-of-day need source signals too (milestone signals from GameState? from a separate MilestoneTracker? time-of-day from DayNightCycle). When those sources land, extend `SceneManager.bind_*` helpers.

**Success conditions**
- [x] `--test-scene-triggers`: 15/15. Each of four trigger types fires its scene for the matching dispatch. Non-matching contexts fire nothing. One-shot triggers don't re-fire; time-of-day re-fires by design. Priority resolution: higher priority wins over registration order. Equal priority: earliest registration wins. ZoneManager-bound signals flow through to dispatch.

---

## 12. Replay / debug tooling

Falls out of #1. Not new functionality — new surfaces on existing functionality.

- [ ] **12.1** `--cli --record <path>` writes the event log to disk as the CLI session runs.
- [ ] **12.2** `--cli --replay <path>` replays a log and exits with final-state hash.
- [ ] **12.3** In-editor debug overlay: scrub the event log forward/backward, render state at any tick.
- [ ] **12.4** Bug report export: `--export-bug-log` dumps current event log + build hash + base seed in a single file.

**Success conditions**
- `--test-replay-roundtrip`: record a CLI session, replay it, final state hashes match.
- `--test-bug-log-self-contained`: exported bug log, replayed on a clean checkout at the matching build hash, reconstructs the reported state.

---

## 13. Context-sensitive consume / deploy input

Architectural decision from the doc's "Same-button consume-and-deploy" note: use aim-resolved context, not a shared binding.

- [ ] **13.1** Single "use" input. Target resolver: hovered mechanism → deploy; hovered empty floor tile → deploy; self/no-target → consume.
- [ ] **13.2** Visual affordance: held-item icon + aim reticle previews which action will fire.
- [ ] **13.3** Confirm-on-deploy for irrecoverable items (optional, playtest-driven).

**Success conditions**
- `--test-consume-deploy-context`: CLI scripted scenarios — (a) aim at mechanism + use → deploy event; (b) aim at self + use → consume event; (c) aim at empty floor + use → deploy-to-floor event. No scenario produces the wrong action.
- Manual playtest: accidental fat-finger rate < 1 error per 10 min of play (informal metric; log errors to telemetry).

---

## Dependency graph

```
#1 event log ──┬─→ #3 save/load
               ├─→ #12 replay tooling
               └─→ #11 scene triggering
#2 seeded RNG ─→ (requires #1 for RNG-spawn events)
#4 actuators ──→ #5 puzzle harness
#6 hub/spoke ──┬─→ #7 failure model
               ├─→ #10 portals
               └─→ #11 scene triggers
#8 REMOVED — game is A+P-sufficient by design
#9 cohesion  ──→ (independent)
#13 input    ──→ (independent, but needs #4 for deploy targets)
```

Recommended start: **#1 → #2 → #3** as one engine-foundations sprint. Then **#4 → #5** as a world-model sprint. Then **#6 → #7** as a game-shape sprint. #9, #10, #11, #12, #13 can slot in as needed.
