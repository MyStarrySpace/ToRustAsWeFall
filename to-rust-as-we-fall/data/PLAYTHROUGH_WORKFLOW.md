# Optimal Playthrough Workflow

## Purpose

Simulate an optimal player run through each game section to measure pacing, APM feel, and difficulty. This is a design validation tool, not a functional test. The test suite verifies code correctness. The playthrough validates game feel.

## Playthrough evidence boundary (hard rules)

Strategy quality and control-surface fidelity are measured separately. The
strategy explains why an optimal player chooses an action; the executor must
still prove that action through a boundary the player can use. An optimal
decision performed by an internal state edit is not a playthrough. If a player
cannot perform the same action through the shipped controls from the same
authored state, it is not playthrough evidence.

- Every approval/playthrough action must use the shipped keyboard/pointer,
  controller, touch, or player-command boundary. Read-only `status` and
  assertions may observe results; they may not create them. Calling a hidden
  singleton movement helper, direct callback, or mechanism method is diagnostic
  setup, not play. For current promotable Native/Web persona evidence, active
  actions require a mechanically issued keyboard/pointer ledger from the
  shipped driver. `player_command` is limited to passive wait; controller and
  touch remain reserved/nonpromotable until their mechanical and presentation
  proof contracts exist.
- Preserve the public verb. A group Rally or other party action is issued once
  as one held group gesture over every portrait visible in the HUD roster,
  never hidden as selection churn plus one singleton move per member.
  `select_party` binds the same exact full visible roster. Record intended
  membership and each member's accepted/refused result. If any visible portrait
  lacks a shipped binding, fail the whole action closed before movement.
  Acceptance is homogeneous: all intended members are accepted by the one
  production event. If any member cannot participate, require one visible
  whole-command refusal with zero movement; never learn from a mixed result.
- Do not assign gameplay state or use snap/teleport placement to skip travel,
  hazards, interaction range, or timing. The sole teleport exception is an
  authored portal exercised through its production interaction and portal
  mechanic.
- Setup/reset placement belongs in a clearly labeled fixture quarantine before
  the measured run (or teardown after it). Reset timers, command counts,
  movement samples, and evidence baselines after staging. Fixture motion or
  proximity cannot satisfy any route, interaction, pacing, or completion claim.
- Every accepted or refused movement/state-change request needs
  player-observable feedback. Record the acceptance/progress/consequence cue or
  the refusal reason/cue. A return value, input receipt, event-log entry, or
  final position alone is insufficient. Move/Rally proof must bind the exact
  visible target and intended portrait tokens through a monotonic causal
  presentation lineage; camera drift or an unrelated generic cue is not proof.
  Acceptance describes the production command boundary and is immutable. If a
  later hazard, route cancellation, or other authored consequence stops an
  accepted move short, record the exact visible lineage
  `accepted -> progress -> interrupted`, with `accepted: true` and a non-empty
  player-facing stopped-short reason. `interrupted` is terminal for settling but
  is not arrival or a demonstrated success; it cannot advance a success policy
  or enter a decision tree as proof of the expected result.
- A no-input wait keeps `production_event_count` at zero, but a separate post-hoc
  validator audits authoritative events during the interval without exposing
  them to policy. Every background change needs a new rendered causal cue. A
  player-facing forced traversal must show active and arrival on the exact
  affected opaque portrait/body binding; another character's matching label is
  not evidence.
- Hiding optional briefing/help text must not hide gameplay feedback. A measured
  run may use the shipped `H` control to clear the briefing, but command
  receipts, acceptance/refusal, movement progress, and consequence cues must
  remain player-observable and recorded.

A legacy script that bypasses these rules may still be useful as a simulation
diagnostic, but it must be labeled diagnostic and cannot approve pacing,
playability, controls, or release readiness.

When a measured run feeds persona automation, policy input is exclusively the
full validated `player_observation_v1`. A `persona_decision_trace_v3` decision
stores the exact before observation, canonically de-duplicated multi-frame
samples in first-seen order during the action, and the exact after observation.
Before, samples, and after must remain chronological. The writer derives
visible feedback and outcome; an interaction requires a new presentation serial
bound to the opaque token of the exact pre-click target. It also derives the
persona goal from persisted visible evidence. Callers cannot author feedback,
outcome, or goal proof.

Those decisions are not promotable merely because a local trace and summary
look green. Native and Web independently require the fixed Basin cohort of
DeanTakahashi and EazySpeezy at repeat indexes 0 and 1. The final hash-chained
receipt must embed the complete platform-local cohort manifest, and the
distiller reconstructs that `persona_strict_invocation_manifest_v1` from all
four traces. One failed,
interrupted, filtered, duplicate, missing, or mixed-content member makes the
cohort unattested. Missing, failed, stale-contract, or revoked receipts remain
diagnostic evidence only.

Authored-content provenance uses a versioned fingerprint schema plus SHA-256
digest: portable resource bytes for authored fragments and a canonical semantic
spec for generated layouts. Fragment-scoped nodes may gain support from repeated
distinct full-goal runs on the same content; global nodes also require distinct
content identities. A separate gameplay-build identity records
`gameplay_build_fingerprint_schema` and `gameplay_build_fingerprint` (currently
`gameplay_build_resource_set_bytes_v1`) for the executable/export that supplied
mechanics; it does not count as content
diversity, and behaviorally different builds cannot pool evidence. V2 traces
and existing v2 library provenance remain diagnostic and non-executable until
fresh v3 cohorts are distilled. The current decision trees are partial, bespoke
policies. Bulk non-AI generated-level replay from observations is a future goal,
not a completed generalized player.

## What We Measure

| Metric | How | Target |
|--------|-----|--------|
| **Section time** | `status` at start/end of each section, delta the scheduler ticks | 3-5 min per shelter stretch at 1x speed |
| **APM** | Count commands per section, divide by section time | 10-20 actions/minute feels engaged without frantic |
| **Dead time** | Seconds where the player has nothing to do | < 5s continuous dead time |
| **Difficulty** | Does the optimal strategy require thinking, or is it autopilot? | Each section should have 1-2 decision points |
| **Dialogue density** | Lines per section | 4-8 lines per narrative beat; > 10 is monologue |

## How to Run

[Testing and release gate](../docs/TESTING.md) is authoritative for current
execution, prerequisites, tier contracts, and gate commands. Run its canonical
PowerShell commands from the repository root through the tracked
`scripts/test-gate.ps1` launcher; do not copy a workstation-specific Godot
executable or version into this workflow. This document governs playthrough
strategy, pacing measurement, and evidence interpretation, not test-runner
invocation.

Do not replace the canonical Headless tier with `--test-all`; its required
manifest also runs the standalone agent-input boundary and persona-decision
pipeline verifiers.

Persona release evidence requires both the Native Windowed cohort and the Web
Chromium cohort. Native runs receive a clean artifact-owned Godot `user://`;
Web uses a fresh export, browser context, and run-owned artifacts. Prior saves,
settings, traces, or browser storage cannot satisfy either gate. These are gate
requirements, not a statement that the latest full v3 cohorts have passed.

For a run that includes an optimal-playthrough trace, inspect each player-facing
command and the read-only `status` dumps at section boundaries under the
applicable tier's output described in `docs/TESTING.md`.

## Record Normal Play and Render It Without Planning Pauses

This is the player-facing workflow. It records ordinary keyboard, mouse, touch, and controller
input against gameplay scheduler ticks while embedding each scene's authoritative `EventLog`
and final `GameState` snapshot.

```powershell
# 1. Play normally. Closing the game seals the artifact. The Windows switch
# explicitly acknowledges that this attended human workflow opens the game.
.\tools\record_playthrough.ps1 `
  -Output .\playthroughs\channels.trwfplay `
  -AllowVisibleWindow

# 2. Replay at exact recorded simulation ticks and render a fixed-60-FPS movie.
# On Windows this legacy renderer has no hidden-owner host, so either run it on
# an isolated display machine or explicitly accept its visible window.
.\tools\render_playthrough.ps1 `
  -Recording .\playthroughs\channels.trwfplay `
  -Output .\playthroughs\channels.avi `
  -AllowVisibleWindow
```

`-AllowVisibleWindow` is an attended-workflow opt-in, not an offscreen flag.
Neither PowerShell helper is valid automated test, persona, or approval
evidence. Those runs must use the tracked `scripts/test-gate.ps1` boundary,
which creates and audits the Windows hidden owner before Godot starts.

Space-planning pauses collapse because no scheduler ticks elapsed between the inputs issued
while paused. Time spent thinking while the simulation was still running remains: enemies,
hunger, water, and movement experienced that time, so deleting it would change the run.

For a Web build, open the game with `?record_playthrough=channels.trwfplay`, play normally,
then press **F10** to seal and download the artifact. Render that downloaded file with the
same `render_playthrough.ps1` command. Browser-local replay can use
`?replay_playthrough=channels.trwfplay` while the artifact remains in that origin's `user://`
storage.

## How to Write a Playthrough Script

### File format
Plain text, one command per line. `#` comments describe strategy.

### Section structure
```
# === SECTION NAME ===
# Strategy: [what the optimal player does]
# Expected: [estimated time breakdown]
status                    # Checkpoint: record start state
[commands]                # The actual play
status                    # Checkpoint: record end state
```

### Commands available
- `move <x> <z>` — Issue the player-facing move command (waits for arrival; never places the body)
- `wait <seconds>` — Let ordinary presented gameplay frames elapse; never skip or directly advance scheduler time
- `advance` — Use the player-facing dialogue-advance action
- `run` — Toggle run/walk
- `dwell [secs]` — Wait for a production proximity interaction already reached through play
- `status` — Read and print a game-state snapshot; never mutates it
- `assert <stat> <op> <value>` — Read and verify a stat

Any additional command must declare the player-facing verb or input it maps to.
Commands such as `set_position`, `set_level`, `set_stat`, `complete`, `trigger`,
or `teleport` are fixture/diagnostic operations and are prohibited inside a
measured playthrough.

### Writing the optimal strategy

For each section, answer:
1. **What does the player know?** (first play vs. second play)
2. **What's the fastest path?** (skip optional content)
3. **What must the player do?** (required interactions, forced dialogue)
4. **What can go wrong?** (hazards, enemies, wrong turns)
5. **How does the player avoid what can go wrong?** (the optimal input sequence)

Write the commands that execute the optimal strategy. The `#` comments ARE the design documentation — they explain why each command is the right move.

## When to Run This

- **After adding a new section**: Write the playthrough commands for it, run, check pacing
- **After changing dialogue**: Re-run to verify section times haven't bloated
- **After changing movement speeds/distances**: Re-run to verify travel times
- **After changing enemy behavior**: Re-run to verify the optimal strategy still works
- **Before milestone**: Full playthrough to check the entire experience

## Interpreting Results

### Pacing reference: Subnautica day/night

The GDD targets ~15 min day, ~5 min night. A full day-night cycle is ~20 min.
Players should reach shelter in 3-5 min of game time per shelter stretch.
An Act 1 run (shelters 1-10) should take ~30-50 min of game time.

### Level sizing math

- Walk speed: 3.0 units/sec. Run: 6.0 units/sec.
- 3 min of walking = ~540 units of linear distance.
- But exploration is not linear: side branches, backtracking, dwelling at
  interactables, avoiding hazards. Effective exploration covers ~40% of
  distance walked. So a level with 200 units of main path + 100 units of
  side branches gives ~300 units to explore, which takes ~3-4 min at walk.
- Width should be 30-60 units to allow meaningful route choices.

### Good pacing
- Each shelter-to-shelter stretch is 3-5 min at 1x speed
- Dialogue and movement alternate (never > 45s of pure dialogue or pure walking)
- The player always knows what to do next (prompt, dialogue hint, or environmental cue)
- Transitions between sections feel like progression, not loading
- At least 2-3 side branches worth exploring per section
- At least 1 resource decision per section (food, flora, shelter timing)
- The day/night clock creates gentle urgency, not panic

### Bad signs
- Section < 2 min: hallway, not a level. Add branching, resources, exploration.
- Section > 7 min: too sprawling for one shelter stretch. Split or add a midpoint.
- > 10 consecutive `advance` commands: monologue. Break it up with movement or interaction.
- Dead time > 10s with nothing to do: player is lost. Add a landmark or prompt.
- 0 decision points in a section: autopilot. Add a route choice or hazard.
- Main path is a straight line with no width: player never has to look around.

## Updating the Playthrough

When you add or change a section:
1. Add the section to `test_optimal_playthrough.txt` with strategy comments
2. Run the playthrough
3. Record actual times in the comments (replace "Expected" with "Actual")
4. If pacing is off, adjust the section (dialogue count, walk distance, hold times)
5. Re-run until pacing feels right
6. Commit the updated playthrough script — it IS the pacing design document
