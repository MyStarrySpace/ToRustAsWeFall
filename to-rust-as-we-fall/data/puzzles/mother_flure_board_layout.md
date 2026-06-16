# Mother Flure 6x6 Board Draft

This is the first-pass expansion plan for the Mother Flure chamber after the current 3-lane prototype. The goal is to turn the scene into a real Lot Clot payoff: a readable traffic-jam board at architectural scale, with enough density to feel like a puzzle board while still fitting the role-based Aster/Peris/Endo loop.

This draft is meant to be implementation-facing. It is concrete enough to wire into the chunk scene, but it is still a tuning document rather than a mathematically proven final card.

## Design Goals

- Keep the room footprint roughly where it is now and enlarge the effective puzzle board inside it.
- Make the chamber read as a scaled-up `Rush Hour`-style traffic jam rather than a corridor with three toggles.
- Preserve the story beats from the puzzle spec:
  - get Endo into the gear pocket
  - carry the two-hand gear to the socket
  - finally clear the mother approach
- Keep the first story solve moderate:
  - target first-clear time: `5-8 minutes`
  - target clean repeat time: `3-5 minutes`
- Let the board look denser than the required solution. A few roots should be visible decoys so the chamber feels like a full board, not a chain of obvious switches.

## World Mapping

- Core board size: `6 x 6`
- Cell size: `6.0 x 6.0` world units
- Suggested board center: `x = 60`, `z = 0`
- Resulting board footprint: about `36 x 36` world units
- Suggested board bounds:
  - west edge: `x = 42`
  - east edge: `x = 78`
  - north edge: `z = -18`
  - south edge: `z = 18`

This keeps the current left apron for portal terminals and the base portal, while leaving an east apron for the socket dais and the mother herself.

## Board Grammar

- The 6x6 grid is the logical puzzle board, not a literal tiled floor. In-world it should read as channels and root gutters.
- Cells should be wide enough for characters to visually commit to entering a lane.
- The board should include a few dead-end grooves and off-board fragment buds so it feels older and more biological than a clean toy board.
- The active walk goal is the center row, which becomes the carry/tending corridor once the blockers are displaced.

## Core Board

Columns run `1-6` west to east. Rows run `A-F` north to south.

```text
    1 2 3 4 5 6
A | A A A . C C
B | D D . B . E
C | . F . B G E
D | I F H H H .
E | I . . J J .
F | I . . . . .
```

Legend:

- `A` = North Rail
- `B` = Spine Gate
- `C` = Survey Rib
- `D` = Gear Latch
- `E` = Mother Veil
- `F` = Socket Brace
- `G` = Bloom Curtain
- `H` = Crossbar
- `I` = Carry Spur
- `J` = Tending Step

The critical mother corridor is row `C`. In the start state it is blocked by `F`, `B`, `G`, and `E`.

## Major Root Pieces

### `A` North Rail

- orientation: horizontal
- length: `3`
- start cells: `A1-A3`
- main job: reads as part of the old board frame; mostly a visible false affordance

### `B` Spine Gate

- orientation: vertical
- length: `2`
- start cells: `B4-C4`
- useful slide states:
  - `A4-B4`
  - `C4-D4`
  - `D4-E4`
- main job: central blocker in the mother corridor

### `C` Survey Rib

- orientation: horizontal
- length: `2`
- start cells: `A5-A6`
- main job: top-edge congestion and visual weight; optional move in first-pass solve

### `D` Gear Latch

- orientation: horizontal
- length: `2`
- start cells: `B1-B2`
- useful slide states:
  - `B2-B3`
  - `B3-B4`
- main job: west-side lock that keeps the gear bay from reading open too early

### `E` Mother Veil

- orientation: vertical
- length: `2`
- start cells: `B6-C6`
- useful slide states:
  - `C6-D6`
  - `D6-E6`
- main job: eastern blocker that keeps the final mother approach shut until late

### `F` Socket Brace

- orientation: vertical
- length: `2`
- start cells: `C2-D2`
- useful slide states:
  - `D2-E2`
  - `E2-F2`
- main job: west-center blocker; moving it opens the gear-side route and later helps the carry lane read correctly

### `G` Bloom Curtain

- orientation: vertical
- length: `2`
- start cells: `C5-D5`
- useful slide states:
  - `D5-E5`
  - `E5-F5`
- main job: middle-east blocker that visually reads like a thick siderophore mat around a live root

### `H` Crossbar

- orientation: horizontal
- length: `3`
- start cells: `D3-D5`
- useful slide states:
  - `D2-D4`
  - `D4-D6`
- main job: sells the board as a real traffic-jam field; mostly decoy pressure in the first solve

### `I` Carry Spur

- orientation: vertical
- length: `3`
- start cells: `D1-F1`
- main job: southwest mass that makes the gear pocket feel boxed in and heavy

### `J` Tending Step

- orientation: horizontal
- length: `2`
- start cells: `E4-E5`
- useful slide states:
  - `E3-E4`
  - `E5-E6`
- main job: small release piece that has to move before the east side can fully unwind

## Spatial Beats Around The Board

These sit outside the 6x6 core but should line up with it spatially.

- West apron:
  - portal bank cluster
  - terminal line
  - Aster standing space
- Southwest pocket:
  - Endo-only carry entry
  - two-hand mother gear
  - one hide slit or safe pocket nearby so Endo's overlay matters
- Mid-east apron:
  - socket dais
  - clear enough to stage a two-hand carry arrival
- Far east apron:
  - mother body
  - tending interaction point
  - strongest siderophore visual density before clear

## Terminal / Fragment Service Map

The old prototype uses one terminal per root lane. The enlarged board should instead give each terminal a cluster identity.

### `TERM-12A`

- serves north and east fragments
- associated roots:
  - `B` Spine Gate
  - `C` Survey Rib
  - `E` Mother Veil
- Aster overlay emphasis:
  - destination IDs
  - east-side logistics ghost
  - old construction routing

### `TERM-12B`

- serves the central board
- associated roots:
  - `F` Socket Brace
  - `G` Bloom Curtain
  - `H` Crossbar
- Aster overlay emphasis:
  - core board wiring
  - active corridor occupancy
  - route that currently leads to the socket

### `TERM-12C`

- serves west and south fragments
- associated roots:
  - `D` Gear Latch
  - `I` Carry Spur
  - `J` Tending Step
- Aster overlay emphasis:
  - maintenance reroute marks
  - collapse-adjacent service history
  - safest return portal windows

## Intended First-Pass Solve

This is the recommended story solve for the first implementation pass. It uses enough moves to feel like a board without making the first mandatory slow-puzzle too punishing.

### Phase 1: Open The Gear Pocket

1. Slide `D` Gear Latch east to `B2-B3`.
2. Slide `F` Socket Brace down to `D2-E2`.
3. Endo enters the southwest pocket and lifts the mother gear.

Why this phase works:

- The first move is west-side and easy to read.
- The second move makes the gear reveal feel earned rather than simply placed in the room.
- Endo's overlay can now clearly mark the carry route, hide slit, and food sources in the collapse wing.

### Phase 2: Open The Carry Lane To The Socket

4. Slide `B` Spine Gate up to `A4-B4`.
5. Carry the gear across the newly opened center corridor to the socket dais.
6. Install the gear.

Why this phase works:

- `B` is the first major central blocker, so moving it feels like the board has "started."
- The carry run gives the player a body-scale payoff between puzzle states.
- Installing the gear creates a mid-puzzle milestone before the final clear.

### Phase 3: Unwind The East Side

The implemented board currently needs two extra release moves to make the east side honest:

7. Slide `F` Socket Brace down again to `E2-F2`.
8. Slide `J` Tending Step left to `E3-E4`.
9. Slide `H` Crossbar left to `D2-D4`.
10. Slide `G` Bloom Curtain down to `D5-E5`.
11. Slide `E` Mother Veil down to `C6-D6`.
12. Slide `E` Mother Veil down again to `D6-E6`.

At this point row `C` is clear end-to-end:

```text
C | . . . . . .
```

13. Approach and tend the mother.

Why this phase works:

- The second `F` move and `H` reposition turn the east side into a real jam instead of a linear cleanup.
- `J` is still the small release move that makes the back half feel discovered instead of brute-forced.
- `G` and `E` read like the last two mats of siderophore pressure peeling back from the mother.
- The double move on `E` makes the final reveal feel larger than a single toggle.

## Optional Decoys

The first mandatory version should not require every visible root.

These pieces can be movable but optional in the first pass:

- `A` North Rail
- `C` Survey Rib
- `I` Carry Spur

That gives us a board that looks denser than its minimum solve while still letting the first implementation stay approachable.

## Failure / Recovery Shape

- Peris failures should be local and recoverable:
  - caught in a bad slide lane
  - returns late through a portal
  - eats damage from the following siderophore swarm
- Endo failures should be logistical:
  - carrying the two-hand gear through a lane that is not actually stable yet
  - overcommitting to the mother lane before the east blockers are fully down
- Aster failures should be informational:
  - opening the wrong service cluster
  - letting a useful portal expire while Peris is still remote

Because the scene is a slow-puzzle, none of these should reset the board.

## Overlay Hooks

### Aster

- Show all three terminal clusters and their served fragments at once.
- Highlight the current service destination when a terminal is active.
- Ghost the old Unit NV maintenance plan over the board, especially the east apron and the collapse service line.

### Peris

- Show dormant buds for the currently reachable fragments.
- Let the mother stress read soften as the east side opens.
- Show caretaker traces near the mother lane and one blur near the collapse wing.

### Endo

- Mark:
  - gear pocket
  - hide slit
  - food/corpse points in the collapse wing
  - carry-safe line once the center corridor opens

## Player-Facing Obscurity

- The live scene should not expose exact cell coordinates, blocker identities, or explicit compass-direction answers through overlays or failure text.
- Service buds can be readable as local alcove affordances, but they should feel like probing a biological board rather than pushing a UI arrow button.
- Peris's overlay should report stress, memory, and trace quality, not a literal move list.
- Aster's overlay can reveal cluster relationships and infrastructure context without enumerating the exact solve path.

## Recommended Implementation Order

1. Rebuild the chamber floor around a `6 x 6` logical board.
2. Replace the current 3 root lanes with the 9 named roots above.
3. Move the current gear, socket, and mother anchors onto the beat positions in this layout.
4. Keep the current inventory, consume, and portal systems; remap them onto the enlarged board.
5. Add a headless scenario for:
  - gear pocket open
  - gear installed
  - mother lane clear
  - representative bad-slide damage case

## Notes For Tuning

- If this still solves too quickly, the safest complexity increase is to make `H` Crossbar part of the required east-side unwind.
- If the first solve feels too dense, keep `A`, `C`, `H`, and `I` visible but non-interactive for the first content pass, then enable them later.
- If the chamber stops reading as "Lot Clot at scale," the problem is probably not piece count but lane framing. The board must be readable from the first camera angle.
