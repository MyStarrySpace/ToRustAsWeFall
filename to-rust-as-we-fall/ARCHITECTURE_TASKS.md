# Architecture Implementation Tasks

Derived from `game_architecture.md`. Tasks are ordered by dependency — later tasks assume earlier foundations. Success conditions are written to be automatable via the headless test runner (`--test-*` flags in `scripts/test_runner_cli.gd`) or the CLI playthrough harness (`--cli`) wherever possible.

Distinct from `TASKS.md`, which tracks prototype-port feature work. Where overlap exists, the relevant prototype-port phase is noted.

---

## 1. Event-sourced state foundation

Everything else in the doc ("recording and playback come for free", save integrity, determinism testing, Psy-Knapse mechanic) sits on this. Extends the existing `EventScheduler` into an authoritative, replayable *event log*.

**Architectural decision (locked in by 1.1–1.5):** the log records *external commands* (player/sequence/AI inputs), not internal state mutations. The deterministic scheduler reproduces all internal mutations (movement arrivals, dodge ends, collision fires, etc.) when the same commands are replayed against an identical starting state. This avoids logging every interpolated tick and keeps the log compact, but it makes the scheduler's determinism load-bearing — every divergence between record and replay is a scheduler-determinism bug.

**Tick-drain decision:** the log carries `recorded_until: float` alongside the event array. Replay drains pending scheduler events up to this tick at the end of replay so movements still in flight at save time complete identically. Callers that advance the scheduler without issuing commands (e.g. waiting for a character to arrive) must call `GameState.flush_tick()` before serializing.

- [x] **1.1** Define `GameEvent` schema: `{tick: float, kind: StringName, payload: Dictionary}`. Plain-data payloads only. — [scripts/game/game_event.gd](scripts/game/game_event.gd)
- [~] **1.2** Audit all state mutations in `game_state.gd`. **Done:** movement commands, item commands, physics commands (register/unregister/throw/apply_area_impulse), pendulum commands (register/unregister), dodge_roll. **Remaining:** abilities (queue_ability needs Callable→ability-id refactor first; cancel_queued_ability). Lint pass for the audit not yet built.
- [x] **1.3** Add `EventLog` class (append-only, in-memory) with `recorded_until` tracking. — [scripts/game/event_log.gd](scripts/game/event_log.gd)
- [~] **1.4** Add `GameState.replay(log, grid)` that constructs fresh state by replaying events. **Movement commands dispatched.** Items/physics/pendulums/abilities/dodge dispatch cases pending alongside 1.2.
- [x] **1.5** Add event-log serializer (`to_bytes` / `from_bytes` via `var_to_bytes`). Versioned header (`FORMAT_VERSION = 1`).

**Open issue — Callable payloads:** `queue_ability(char_id, ability, target_pos, range, callback)` takes a `Callable`. Callables aren't replay-safe. Resolution: replace the Callable with a `StringName` ability id, and have the system look up the handler at replay time from a registry. Tracked separately; will land alongside the abilities portion of 1.2.

**Success conditions**
- [x] `--test-event-log-roundtrip`: 13/13 assertions passing. Records a movement-only session (register, advance, move-to-cell, advance, move-to-pos, advance, stop, change-speed, walk-path, advance), serializes, decodes, replays — final positions match within 0.01 units. Replay does not re-append to its own log. Unregister round-trips.
- [ ] `--test-event-log-mutation-audit`: lint not yet built; scheduled alongside completion of 1.2.
- [ ] CLI: `--cli --record out.log` / `--cli --replay out.log --assert-final-state-matches` — surface not yet wired into `cli_game.gd`.

---

## 2. Seeded deterministic RNG

Pairs with #1. Without this, replays diverge and everything downstream (#3, #11, #13) breaks.

- [ ] **2.1** Remove all uses of `randi()`, `randf()`, `randomize()`, wall-clock seeds. Grep-gated CI check.
- [ ] **2.2** Add `SeededRng` (wraps Godot's `RandomNumberGenerator`); require explicit seed on construction.
- [ ] **2.3** Add `RngRegistry` keyed by system name (`"ai.techo"`, `"ai.cytokine"`, `"loot"`, `"ambient"`, ...). Each system fetches its own RNG via `RngRegistry.get("ai.techo", spawn_event_id)`. Seeds derive from `base_seed XOR hash(system_name) XOR spawn_event_id` — no wall-clock input.
- [ ] **2.4** Surface `GameState.base_seed` in the title screen + pause menu (read/write, like Minecraft seeds).
- [ ] **2.5** Log RNG consumption into the event stream when systems are born (so mid-run spawns don't drift between replays).

**Success conditions**
- `--test-rng-determinism`: seed a `GameState` with base_seed=42, run a fixed scripted sequence that exercises each registered system (AI, loot, ambient), hash the final state; repeat 3×; all hashes match.
- `--test-rng-no-wallclock`: grep-gated — fails build if any `.gd` calls `randi()`, `randf()`, `Time.get_*ticks*`, or `randomize()` (allowlist for visual-only code marked `@rendering_only`).
- Two replays of the same event stream produce identical logs when re-recorded.

---

## 3. Save / load as event log

Falls out of #1 and #2. Not a separate subsystem — it's the log plus a base seed.

- [ ] **3.1** Save = `{base_seed, events[]}` + small header (version, build hash, timestamp for UI only).
- [ ] **3.2** Load = `GameState.replay(events, base_seed)`.
- [ ] **3.3** Corrupt-save handling: replay stops at first malformed event, state freezes at last clean tick, UI offers "continue from clean point" or "abort".
- [ ] **3.4** Quick-save / quick-load hotkeys.

**Success conditions**
- `--test-save-load-integrity`: run fixed sequence for 1000 ticks, save mid-run at tick 500, continue to 1000, save final. Separately: save at 500, load from that save, continue to 1000, save. Both final saves must produce byte-identical states.
- `--test-save-corruption-recovery`: construct an event log, truncate last event in the middle, load → state matches truncate-point state, UI emits `save_corrupted` signal.

**Supersedes** prototype-port Phase 19 (Save/Load). Phase 19 can be deleted once this task completes.

---

## 4. Actuator abstraction

World-as-physical-system. Pressure plates, triggers, and mechanisms respond to physical conditions, not to character identity.

- [ ] **4.1** Define `Actuator` contract: any entity with `position: Vector3`, `weight: float`, `signature: StringName` (e.g. `"organic"`, `"metal"`, `"heavy_fruit"`). Characters, items, physics objects all implement this.
- [ ] **4.2** Define `Mechanism` contract: evaluates a condition over actuators in its zone (e.g. `sum(weight) >= threshold`, `count(signature == "organic") >= 1`). Mechanisms never inspect `char_id`.
- [ ] **4.3** Migrate existing pressure-sensitive interactables (`interactable.gd`) to the Mechanism contract.
- [ ] **4.4** Add heavy-item → weight mapping in `item_data.gd`.

**Success conditions**
- `--test-actuator-composition-blind`: set up a pressure plate requiring weight ≥ 2.0. Verify it triggers when (a) one heavy character stands on it, (b) two light characters stand on it, (c) one heavy fruit is placed on it, (d) one character + one item combine to reach threshold. All four cases must trigger identical downstream events.
- `--test-actuator-no-id-checks`: grep-gated — fails if any `Mechanism` subclass references `char_id`, `is_character()`, or checks a character list.

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

- [ ] **6.1** Define `Zone` resource (`.tres`): id, hub-ids[], spoke-ids[], gate-ids[], essential-third.
- [ ] **6.2** Define `Hub` node: rest-point that restores HP/ATP/stamina on enter, triggers processing scenes, persists until zone-exit.
- [ ] **6.3** Define `Gate` node: evaluates party-composition predicate before allowing passage. Predicate is environmental (e.g. "terminal only Aster can access"), not a popup.
- [ ] **6.4** `ZoneManager` autoload: tracks current zone, active hub, which spokes are complete, which gates are passed.
- [ ] **6.5** Hub-rest flow: restores HP/ATP/stamina; marks all downed characters as narratively available for scenes.

**Success conditions**
- `--test-hub-rest-restore`: down a character, retreat to hub, trigger rest, assert HP == maxHP, ATP == maxATP, stamina == maxStamina, narrative-available == true.
- `--test-gate-block`: approach a gate requiring Endo while Endo is not in party → gate emits `blocked(reason: "endo_required")`, does not advance. Add Endo → passes.
- `--test-zone-progression`: run a scripted sequence from zone A hub → spoke → gate → zone B hub. Assert zone transitions fire, old zone's hubs remain reachable within same zone, fall out of reach after next zone-exit.

---

## 7. Failure / recovery model

No game-over. Downed ≠ dead. Retreat to hub = full recovery.

- [ ] **7.1** Extend character state machine with `downed` state (already listed in `TASKS.md` 2.2 — verify it exists and behaves per architecture).
- [ ] **7.2** Remove any remaining "game over" code paths; replace with "retreat-to-last-hub" flow.
- [ ] **7.3** Ensure permadeath only occurs via scripted narrative events (flag on event payload).
- [ ] **7.4** Downed-party-recovery: if all characters downed in a spoke, auto-retreat to last hub with scripted fade, restore party.

**Success conditions**
- `--test-no-game-over`: CLI scenario — down all characters, assert no `game_over` signal ever fires; assert `party_retreated(hub_id)` fires; assert party state at hub is fully restored.
- `--test-scripted-death-only`: grep-gated — any `character_died` emission must have `payload.scripted == true`; otherwise test fails.

---

## 8. Load-bearing spine + rotating essential third

Aster + Peris always load-bearing. One rotating third per zone. Previous thirds remain as non-essential party members.

- [ ] **8.1** `Party` model: `essential = ["aster", "peris"]` (fixed) + `zone_third: StringName` (rotates) + `non_essential: Array[StringName]` (accumulates).
- [ ] **8.2** Gate predicates default to `{essential} ∪ {zone_third}`. Exceptional gates can override with explicit requirements.
- [ ] **8.3** Zone transition updates `zone_third` per the rotation table (Act 1 → Endo, Supply Lines → Myke, Maintenance Warrens → Oli, Archive Depths → Tyreg).
- [ ] **8.4** Scene-trigger system checks essential presence before firing zone-critical scenes.

**Success conditions**
- `--test-rotating-third`: scripted sequence advances through three zones, assert `zone_third` transitions match rotation table, assert non-essential list accumulates previous thirds.
- `--test-spine-sufficiency`: for each zone, verify all gates are passable with only `{aster, peris, zone_third}` — no gate silently requires any other character.

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

- [ ] **11.1** `SceneTrigger` base class with `evaluate(context) -> bool` + `priority: int`.
- [ ] **11.2** Concrete triggers: `OnSpokeComplete`, `OnGatePass`, `OnMilestone`, `OnTimeOfDay`.
- [ ] **11.3** `SceneManager` autoload: evaluates pending triggers on state changes, fires highest-priority scene that hasn't played.

**Success conditions**
- `--test-scene-triggers`: scripted scenario exercises all four trigger types in isolation; assert each fires its scene exactly once; assert priority resolution when multiple triggers match simultaneously.

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
               ├─→ #8 rotating third
               ├─→ #10 portals
               └─→ #11 scene triggers
#9 cohesion  ──→ (independent)
#13 input    ──→ (independent, but needs #4 for deploy targets)
```

Recommended start: **#1 → #2 → #3** as one engine-foundations sprint. Then **#4 → #5** as a world-model sprint. Then **#6 → #7 → #8** as a game-shape sprint. #9, #10, #11, #12, #13 can slot in as needed.
