# Teaching Beats Catalogue

Meta-doc tracking the shadow-solution layer's teaching beats across the game's geography. The catalogue connects techniques to the places where players can learn them before they matter.

## Principle

Every shadow solution requires the player to know a technique. The technique is taught at one or more locations in the game's geography, never at the puzzle itself. Teaching beats are environmental, diegetic, distributed, and easy to miss.

They are not tutorials. They are not UI prompts. They are not adjacent hints. They are small moments where the world quietly demonstrates that a later expert solution is possible.

## How To Read Entries

Each entry lists:

- `technique`: the specific mechanic, capability, or inference pattern
- `teaching_beat`: where the player can learn it
- `applied_puzzles`: puzzles whose shadow solutions require it
- `status`: `taught`, `planned`, `undertaught`, or `gap`

A technique with no teaching beat is a design gap. A puzzle with an untaught required technique is shadow-broken until addressed.

## Catalogued Techniques

### Rapid Scarpet-Drag For Moving Heavy Objects

`status`: planned

Technique:

Scarpet flora can be planted rapidly when prepared with accelerator substrate. The resulting bed reduces friction enough for two characters to drag a heavy object without triggering siderophore detection. A single character cannot drag alone.

Teaching beat:

Marco's drag-demonstration scene after the Mother Flure chamber. Marco demonstrates rapid Scarpet on an unrelated heavy object, with Peris registering that she wants to learn it.

Applied puzzles:

- Mother Flure chamber return solve
- The Honeycomb Cooperative boulder puzzle

### Hushbloom-Stunned Offshoot Portal Escape

`status`: undertaught

Technique:

Hushbloom's stun release can disable portal tracking temporarily when applied to both sides of a portal threshold. The party can use the disabled portal as a hide route during chase sequences.

Current teaching:

The player learns Hushbloom stun in general flora contexts, but not the portal-tracking application.

Recommended teaching beat:

A Channels environmental detail or shelter conversation where Peris tends Hushbloom near a portal terminal and the tracking indicator visibly dims for a moment.

Applied puzzles:

- Lockout chase decline path

### Three-Route Information Cross-Reference

`status`: planned, concrete beat defined

Technique:

When a puzzle presents multiple information routes, the routes overlap. Two routes plus careful observation of the central space can reconstruct a third route's missing information.

Teaching beat:

#### Stacks Redundant Routing Cache

Placement:

- optional side room in the The Open Files Initiative, before Inflammashunt
- low danger, no survival clock pressure
- small tangible reward, such as restorative supplies, a worker note, or a minor Engram entry

Room premise:

A sealed worker cache sits behind three route labels:

- `Line A`: terminal registry path
- `Line B`: flora residue path
- `Line C`: collapsed crawl path

Line C is inaccessible. The player can still infer what happened there by combining Aster's and Peris's reads with the central room's physical evidence.

Aster read:

- terminal registry says Line C was "closed for dry-flow contamination"
- later entry says the cache was moved away from the wet return line
- a schematic shows Line A and Line C share a pressure return

Peris read:

- flora residue avoids one dry conduit and grows toward an old wet seam
- Peris can identify which line stayed biologically viable
- the living residue contradicts the terminal's stale closure label

Central observation:

- the collapsed Line C grate has fresh tool scratches facing outward
- the cache bracket beside Line C is empty
- residue tracks lead from Line C toward one of the two accessible latches

Correct inference:

Line C is not the cache location anymore. The worker moved the cache into the accessible latch that shares Line C's pressure return but is not on the wet seam.

Reward signal:

The player opens the inferred latch and gets a small cache. No prompt says "you reconstructed the third route." The physical reward confirms the technique.

Why this teaches the technique:

- one route is inaccessible
- two accessible reads are incomplete and slightly contradictory
- central-space observation resolves the contradiction
- a reward confirms that reconstructing a missing route is valid

Applied puzzles:

- Inflammashunt shadow solution
- future multi-route Act 2 and Act 3 shadow solutions

### Aster's Overlay Deep-Scan Mode

`status`: planned, no committed application

Technique:

Aster's overlay has a deprecated diagnostic mode that reads environmental signals from spaces he cannot physically enter. It requires standing at signal-leakage points, drains resources heavily, and produces lower-fidelity readings than direct access.

Teaching beat:

The Open Files Initiative terminal logs about construction-era signal leakage and diagnostic scans.

Applied puzzles:

- no committed puzzle yet

### Aster's Credential Emulation Hack

`status`: planned

Technique:

Aster can produce short-duration emulations of enforcement-class credentials under specific environmental conditions. The emulation is fragile and fails loudly if misused.

Teaching beat:

An earlier terminal hack where Aster emulates a credential as a curiosity or one-off environmental beat. The label "credential emulation" should be visible enough to remember.

Applied puzzles:

- Beacon Hill shadow solution

### Peris's Doma In Tight-Corridor Pursuit Breaks

`status`: planned

Technique:

Peris's Doma flora can provide hide-only pursuit-break cover in tight corridors, replacing Oli's barrier more slowly but functionally.

Teaching beat:

An Act 1 shelter conversation or low-pressure encounter where Peris uses Doma in a tight passage.

Applied puzzles:

- The Honeycomb Cooperative shadow solution

## Design Gaps

### High Priority

Hushbloom-portal-stun remains undertaught. The lockout chase is early enough that this needs a stronger Act 1 teaching beat.

### Medium Priority

Three-route cross-reference now has a concrete teaching beat, but the Stacks Redundant Routing Cache still needs an implementation-facing fragment spec and headless test.

### Low Priority

Deep-scan mode needs a committed application before it needs more teaching detail.

## Accumulation Across The Game

By the end of Act 1, the player should have had opportunities to learn:

- Scarpet-drag
- Hushbloom portal-stun
- three-route cross-reference

Act 2 and Act 3 shadow solutions can rely on these earlier teachings, but should add new beats for techniques introduced later.

## Anti-Principles

- Teaching beats are not tutorials.
- Teaching beats are not adjacent hints.
- Teaching beats are not guaranteed to be understood on first play.
- Teaching beats are not unlock flags.
- Teaching beats do not tell the player that a shadow solution exists.

## Open Questions

- Should shadow-solution completions be tracked internally for tuning?
- Should repeated use of a taught technique create subtle party recognition dialogue?
- How many Act 1 teaching beats can fit before the player feels overloaded?

## Related Docs

- [Inflammashunt Puzzle - Full Spec](./inflammashunt_puzzle.md)
- [Inflammashunt Puzzle - Shadow Solution](./inflammashunt_shadow_solution.md)
- `design_principles_shadow_solutions.md`
- `marco_drag_scene.md`
- `flora_taxonomy.md`
