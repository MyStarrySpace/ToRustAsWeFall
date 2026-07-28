# The Scavenger Cargo Beat — the complete formalized sequence

**Status: the behavioral chain is BUILT but lives only in uncommitted working-tree
changes** (generated_stretch_chunk.gd + the generation stack + its focused regression
`tools/verify_generated_scavenger_authority.gd`, 35 checks green). No commit has ever
preserved the full chain — commit `91f459c2` had only the press-control-bridge-appears
version. This document is the beat's canonical record so the design cannot drift or
vanish again; the implementation ledger at the bottom tracks what still must land.

## The beat, complete

The transcript-canonical sequence, including the setup the earlier specs omitted:

1. **The setup.** Loose CARGO (debris/crate) sits ELEVATED on a loading rack beside the
   crossing gap. A **Sapscrap** — not a generic scavenger — forages dormant nearby. A
   connected **lysate source** sits further along, richer than anything on the rack.
2. **The knock-down.** Opening the first sluice sends the Sapscrap toward the rack (the
   scent moves with the water). Its CONTACT with the rack knocks the cargo loose — the
   cargo FALLS to the dry basin floor below the crossing.
3. **The ride.** The Sapscrap RIDES the cargo down (decision settled below), steps off
   at the bottom unbothered, and paths away to the lysate source. The basin now holds
   the fallen cargo and no threat.
4. **The current.** A later control releases the current through the basin. The water
   that would sweep YOU carries the CARGO laterally downstream (same physics, one
   predicate) until it seats across the crossing gap.
5. **The crossing.** The seated cargo bridges the gap; the walk grid rewalks; the path
   opens. The player crossed because they read the whole causal chain — enemy, weight,
   water — not because a control conjured a bridge.

## Settled: the Sapscrap RIDES the cargo down

Not "jumps clear as it falls." Reasons, in order of force:

- **Canon locomotion** (fauna_image_prompts): Sapscraps *glide on stub-legs, smooth and
  low* — there is no jump in the body's movement vocabulary. A leap reads off-species.
- **The demonstration** (P18): the fall teaches *weight* — the same mass the current
  will later push. The scrap riding it down and stepping off unhurt ALSO teaches that
  enemies live inside the same physics you are about to exploit.
- **One authority**: the engine already carries bodies on locked external traversals
  (the Channel sweep). The fall is one short locked traversal carrying cargo AND
  scrap together — save/replay-safe by the same contract the 35-check regression
  already guards, not a second animation system.
- **Character**: a scavenger that placidly rides the wreck it caused is a better
  Sapscrap than one that flees its own accident.

## Identity requirement: it is a SAPSCRAP

The current implementation spawns a generic `EnemyScript` displayed as "Lysate
scavenger" (brown, detection 0). The canonical identity:

- Species/display: **Sapscrap** (roster canon); char id prefix `sapscrap_`.
- Body: wears `sapscrap_body` from the archetype library (base capsule + eye lights
  hidden — the wash_ascent `_spawn_fauna` pattern).
- The lysate departure is IN-SPECIES: siderophore foragers abandon a poor source for a
  richer one; no bespoke motivation needed.
- Flure compatibility follows free (siderophore class answers iron decoys): a placed
  Flure is a legal OPTIONAL lever to pull the scrap off the rack early — do not build
  around it, but never block it.

## Implementation ledger — what must still land, and where

| Item | Where | Owner state |
| --- | --- | --- |
| Commit the behavioral chain | generated_stretch_chunk.gd + generation stack + verify tool | UNCOMMITTED in the parallel session's worktree — commit it before anything else touches those files |
| Setup section (Sapscrap → fall → lysate departure) in the systems spec | docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md | spec currently documents only the water-transport half; file is in the same uncommitted flight |
| The full chain in the curriculum + generated JSON | stretch_systems_curriculum.gd, data/generated_stretches/*.json | same flight |
| Sapscrap identity swap | the `EnemyScript.new()` site (~line 5448) + body attach | small, after the commit lands |
| Ride-down (cargo + scrap on one locked traversal) | the contact→fall handler | replaces the current trigger-and-separate-retreat staging |
| Water-shader compile error (`fres` redefinition) | resources/channels_water.gdshader | **FIXED + committed** (this session) — the verify's 35 checks now run clean |

The wash_ascent slice also has a natural second placement (its broken pier at the rail
gap is a fallen platform beside a Channel current with Sapscraps and a Flure already
live) — compose it there only AFTER the generated-stretch original is committed and
identity-corrected, so there is one canonical implementation to inherit from.
