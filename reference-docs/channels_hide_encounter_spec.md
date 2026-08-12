# Channels: hide-and-run encounter spec

Consolidated spec for implementing the hide-and-run sequence in Godot. This is Beat 3.75 of the Channels scene, after the second ferrolure/flora coda, before Beat 4 (shelter). Control has returned from the cutscene and the player is now in Endo's POV.

## Corridor layout

Linear corridor running left (entry) to right (exit). Order of features along the path:

```
entry — lure 2 — [hide notch] — lure 1 — siderophore cluster (7) — exit
```

### Distances (from math solver)

- Lure 2 to lure 1 (retreat distance, the critical variable): **L = 550 px**
- Hide notch centered between lure 2 and lure 1 (approximately 275 px from each)
- Entry to lure 2: short positioning distance (100-150 px)
- Lure 1 to siderophore cluster: short, lure 1 is at the edge of the cluster's unaware detection radius
- Cluster to exit: short, the cluster starts blocking the path shortly before the exit
- Hide-to-exit distance (D_exit): approximately 275 px (half the corridor), within the stamina budget for a rested party

### Notch geometry

- Rectangular recess cut into the lower wall of the corridor
- Interior large enough for 3 characters to stand (about 50 × 55 units in prototype scale)
- Panel/barrier at the mouth of the notch partially occluding the opening. Party behind the panel is out of line of sight from anything walking in the main corridor
- Navigation: characters enter and exit the notch through a single waypoint above the panel at corridor level. No diagonal clipping through walls
- Line-of-sight rule: if a character is inside the notch AND behind the panel (below the panel's top edge), they are invisible to anything in the main corridor

## Entities

### Siderophores

- Count: 7 in a single cluster at the far end of the corridor
- Starting position: clustered in the corridor blocking the path to exit
- Spread: when fixated on a lure, they distribute in a ring around it (approximately 30 px radius). They don't stack on the lure's center point. The collective coverage of 7 siderophores at a lure is wider than the corridor, so a single lure cannot clear the path

### Detection radii (per siderophore)

- Unaware state: **32 px** (large, covers corridor width)
- Fixated state: **14 px** (smaller, but collective coverage at a lure still blocks)

### States

- `unaware`: default; drifts slowly in place; uses unaware radius
- `fixated`: one lure is active within its awareness; moves toward lure's swarm offset position; uses fixated radius
- Transitions:
  - `unaware` → `fixated`: any active lure triggers fixation (prefers lure 1 if both active)
  - `fixated` → `unaware`: current fixation target expires and no other lure is active
  - `fixated → fixated (new target)`: current target expires, another lure is active

### Movement speed

- Siderophore speed: **v_s = 80 px/s** (tunable)

## Lures (ferrolures 1 and 2)

### Activation

- Requires a character to stand on the interactable for the activation hold duration
- **Hold duration: 2.0 s**
- Only Peris can activate in this encounter (other characters can interact with lures elsewhere, but this encounter uses Peris specifically)
- Stamina does not drain during the hold (she's standing still and regenerates)

### Durations

- **Lure 1 duration: 10 s**
- **Lure 2 duration: 13 s**

### Effect on siderophores

- Active lure attracts siderophores in its awareness range, flipping them to `fixated` state with that lure as target
- Fixated siderophores migrate to their swarm-offset position around the lure
- When a lure expires, siderophores fixated on it re-evaluate: move to another active lure if one exists, else go unaware

## Party

### Members

- Peris (activator, runs the two-lure sequence)
- Aster (pre-hides at the notch)
- Endo (pre-hides at the notch; player has control of him for this encounter)

### Stamina (locked constants from prototype)

- Max: 100
- Run drain: 30/s
- Walk regen: 3/s
- Stand regen: 15/s
- When stamina hits 0, forced to walk. Cannot run again until stamina rises above threshold (currently any stamina > 0 re-enables run attempt, but sustained running requires ongoing budget)

### Movement speeds

- Run: 140 px/s
- Walk: 46 px/s (roughly 33% of run)

### Max continuous run distance from full stamina

- 3.33 s × 140 px/s = **467 px**

## Player plan (intended solution)

1. Player (controlling Endo) positions Aster and Endo in the hide notch via the corridor-level waypoint
2. Switch control to Peris. Walk (not run) to lure 1 to arrive with full stamina
3. Activate lure 1 (2s hold). Stamina regenerates to full during hold. Siderophores fixate on lure 1 and move to ring around it
4. Run back toward lure 2. Distance 550 px exceeds 467 px run budget, so Peris runs until stamina empties (~3.33s, 467 px), then walks the remaining 83 px (~1.80s). Total retreat time: ~5.1s
5. Activate lure 2 (2s hold). Stamina regenerates during hold. Lure 1 is still active (2.87s remaining). Siderophores stay fixated on lure 1; lure 2 is dormant-with-signal, no siderophores yet
6. Peris walks/runs into the hide notch via the waypoint and joins Aster and Endo
7. Wait in the hide (regenerating stamina) until lure 1 expires. Siderophores now re-fixate on lure 2 (the only active lure) and begin migrating left toward it
8. Siderophores walk past the hide notch. The panel occludes the party from line of sight. Detection does not trigger even though siderophores pass within their fixated radius of the notch position (occlusion overrides radius detection)
9. Once enough siderophores have crossed past the hide (threshold: 5 of 7 past the notch), the "exit window" opens. Path to exit is clear
10. Party runs right along the corridor past the empty lure 1 area, past the former cluster position, to the exit. D_exit ≈ 275 px, within run budget for rested party
11. Lure 2 expires after the run completes. Siderophores go unaware near lure 2, but the party is already at the exit

## Timing budget (solved from math)

Total encounter time: ~18-20s from lure 1 activation to arrival at exit.

| Phase | Time | Running stamina |
|-------|------|------|
| Walk to lure 1 | ~3s | regens during walk |
| Activate lure 1 (hold) | 2s | full |
| Retreat to lure 2 | ~5.1s | depletes 100 → 0 → walks |
| Activate lure 2 (hold) | 2s | regens 0 → 30 |
| Walk to hide | ~1s | regens |
| Wait for lure 1 to expire | ~2.9s | regens to full |
| Siderophores cross to lure 2 | 550/80 ≈ 6.9s | full |
| Run to exit | ~2s | uses budget |

## Environmental cues (three redundant channels for flow/siderophore awareness)

The player reads the encounter's state through:

- **Visual**: water level rises before flow surges; VFX pulse on lures when active; siderophore state color shifts (deeper coral when fixated); swarm coalescing at a lure; crossing migration visually legible
- **Audio**: water sounds louder during surges; lure activation has a tonal hum; siderophore proximity has audio falloff; footsteps of the swarm audible as they cross past the hide
- **Physical**: siderophores occupy corridor space visibly; cluster coverage makes "try to run through" obviously non-viable; panel occlusion in the hide is geometrically clear

## Failure modes (verified by math + simulation)

Each failure maps to a specific player mistake:

1. **Slow retreat**: player runs Peris past the point where she reaches lure 2 before lure 1 expires. Can happen if player doesn't manage stamina (burned some before encounter, can't sustain the retreat) or walks part unnecessarily. Siderophores go unaware while Peris is still in the corridor, detect her at full radius.

2. **Slow lure 2 activation**: rare but possible if the player gets interrupted mid-hold. Lure 1 expires, siderophores disperse, Peris is stationary at lure 2 and gets detected during her own activation.

3. **No lure 2 (early hide)**: player skips lure 2 and hides directly. Lure 1 expires with no second lure active. Siderophores drift unaware back toward cluster with full radii. May or may not detect the hidden party depending on their drift paths, but even if the hide holds, the exit path is still blocked.

4. **Slow exit run**: party runs with insufficient stamina (burned by pre-encounter running, or tried to run Peris to lure 1 instead of walking). Lure 2 expires mid-run, siderophores go unaware near lure 2, party gets caught mid-corridor.

## Design principles encoded in this puzzle

- **Care is infrastructural, not reactive**: pre-resting before the encounter determines success. Reacting in-the-moment does not.
- **The system is legible and the rhythms are learnable**: three redundant environmental cues for flow, clear siderophore states via color, predictable lure duration. No hidden randomness.
- **Indirect solutions over direct intervention**: you cannot fight the siderophores, only redirect them. The tools that work are patience, positioning, and timing.
- **Failure is recoverable in spirit even if not in-run**: the game reloads to before the encounter on party defeat; the lesson carries over. No permanent loss from this puzzle.

## Implementation notes for Godot

- Event scheduler should handle lure timers, siderophore state transitions, and detection checks as discrete events
- ODE solver for stamina dynamics during continuous motion (running/walking regen integrated over time)
- Pathfinding must respect notch geometry: entry/exit of hide requires the waypoint, no diagonal clipping
- Detection check occurs every frame but uses O(N_siderophores × N_party) loop (small constants, trivial cost)
- Occlusion check for hide: simple rectangle containment + panel line-of-sight test
- Swarm-offset positions per siderophore can be precomputed deterministically from an orbit seed, keeps behavior reproducible for automated testing
- UI during encounter: pause, character switch, walk/run toggle for each character, movement tap. Ability buttons hide during activation holds (cutscene-ish treatment)
- Automated test harness should verify: solution exists from any realistic player state; intended solution is completable; each failure mode triggers when expected; no soft-lock states exist

## What to build, in order

1. Corridor layout + notch geometry + waypoint navigation
2. Siderophore entity with two-radius detection, unaware/fixated states, swarm-offset behavior
3. Ferrolure entity with hold-to-activate, duration timer, fixation effect
4. Stamina system integration (already exists in prototype; verify constants match)
5. Scripted cluster placement (7 siderophores, ring around cluster center with orbit seeds)
6. Scripted first encounter: set lure 1 duration, lure 2 duration, corridor scale, siderophore speed
7. Panel occlusion logic
8. Exit window trigger (5 of 7 siderophores past the hide threshold)
9. Automated tests covering success + 4 failure modes
10. Audio and VFX layer
11. Diegetic planning visualization (Endo gesture → overlay shows the sequence — see Beat 3.75 design note)

## Variables summary

| Symbol | Meaning | Value | Notes |
|--------|---------|-------|-------|
| L | Retreat distance | 550 px | Primary tuning knob |
| D_exit | Hide to exit | ~275 px | Derived from corridor scale |
| v_s | Siderophore speed | 80 px/s | Secondary tuning knob |
| T_hold | Activation hold | 2.0 s | Prototype constant |
| T_L1 | Lure 1 duration | 10 s | Tunable |
| T_L2 | Lure 2 duration | 13 s | Must exceed L/v_s + crossing + exit run |
| R_unaware | Unaware radius | 32 px | |
| R_fixated | Fixated radius | 14 px | |
| v_run | Run speed | 140 px/s | Prototype constant |
| v_walk | Walk speed | 46 px/s | Prototype constant |
| S_max | Max stamina | 100 | Prototype constant |
| D_run | Run drain | 30/s | Prototype constant |
| R_stand | Stand regen | 15/s | Prototype constant |
| R_walk | Walk regen | 3/s | Prototype constant |
| d_run_max | Max run distance from full | 467 px | Derived: v_run × S_max / D_run |
