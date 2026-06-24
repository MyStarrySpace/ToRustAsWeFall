# The Channels — Design (Sector 12, the flooded drainage)

The authoritative design intent for the channels stretch. Written down so it stops getting
re-explained. The current `wash_relay_chunk.gd` is ONE chunk of this larger structure; treat
this doc as the target the chunk should grow toward.

## Spatial structure (nested)

- **Stretch** — the whole channels level, bookended by **two shelters** (a start shelter and
  an end shelter). You descend the spiral from one to the other.
- **Entry** — you arrive on a **bridge atop the spiral**, where you can see the WHOLE stretch
  at a glance: every plant, every terminal, the layout of the descent. This vantage is the
  in-fiction reason **Peris knows the plants' positions later** (she read them from the bridge).
- **Chunk** — the stretch is divided into chunks. A chunk is the span from the previous chunk
  down to **the thing that connects it back to the stretch start** — a **sloperope** or a
  **terminal**. That connect-back device is the chunk's "checkpoint": a washed member uses it to
  rejoin at THIS chunk instead of redoing the whole stretch.
- **Section** — each chunk is divided into sections. A section is a challenge (or series of
  challenges) that ends in **something that helps the other members advance** — e.g. an
  **override button that stops the channel flow for that section** so the rest of the party can
  cross.

## Failure & recovery (the core loop)

- A character who is **washed out** (mistimed cross, guard hit) is swept down to the **start of
  the stretch** (the start shelter). They are **stranded** there until recovered.
- **Recovery** = they must **climb (sloperope) or telephone (terminal) back up** to the proper
  chunk. The connect-back device at a chunk's end is what lets a stranded member rejoin at that
  chunk. Recovery is a **time investment**, not instant — it's a decision, not a freebie.
- **The decision:** when a member goes down, the party chooses to either
  (a) **invest the time to send them back up** now, or
  (b) **leave them waiting** while the others finish the section, then bring them up at the
      chunk end (drop the sloperope / hit the terminal).
- **Consequence scales with depth:** the deeper into a chunk a member is downed, the more they
  (or the party) must re-cover to get them back to the front — so a late-chunk wash hurts more
  than an early one.
- **All three washed out → the chunk must be redone.** So the smart play is to get the downed
  member reunited with the party before pushing on.

## The three-character co-op (the intended play)

The section-end interactable (e.g. the flow override) is the fulcrum. Canonical solve:
1. **Send the puzzle-solver across first** — e.g. Endo solves the section to reach the override.
2. **They activate it for the others** — Endo presses the override; the flow stops; **Aster and
   Peris cross** safely.
3. **Role hand-off on failure** — if the activator (Endo) is washed out, **another member takes
   over the activator role** (whoever isn't mid-crossing).
4. The trio matters because the activator is exposed/committed while the others depend on them —
   losing the activator forces a re-plan, not just a retry.

This is the answer to "the trio never needs three minds": at least one section per chunk should
require **one member to hold/activate while the others advance**, with a real role to inherit
when someone goes down.

## How the current chunk maps to this (and what's still TODO)

The shipped `wash_relay_chunk.gd` is effectively **one chunk** of the stretch:
- ✅ Sections with challenges ending in an advance-helper (override / plate / sluice).
- ✅ A wash sweeps the member to the start (`START_POS`).
- ✅ Connect-back devices exist at the chunk end (Terminal = telephone up, Sloperope = climb).
- ✅ Surge telegraph now survives the real GLB scene (warped under `_strip_root`).
- ⏳ **Strand-and-rescue is being made real now** — a wash STRANDS the member (immobile at the
  start); the Terminal/sloperope actually recover stranded members; Endo's BRACE refunds a
  stranded member's stamina. (Was dead code — `_washed` was never populated.)
- 🔜 **Multi-chunk stretch** — split the stretch into several chunks, each with its own
  connect-back device, bookended by two shelters, entered from the spiral-top bridge. Recovery
  rejoins at the chunk, not the stretch start. (Larger restructure; future.)
- 🔜 **Per-section activator co-op** — guarantee each chunk has a hold/activate section where one
  member enables the others and the role can be inherited on a wash.
- 🔜 **Bridge entry vantage** — the opening over-look that justifies Peris's plant knowledge.

## Invariants to preserve

- Everything timing-related rides the gameplay scheduler (replay / fast-forward safe).
- Visual-only effects are `@rendering_only`; warped set-pieces live under their own `Node3D`
  root so they survive `hide_flat_graybox` when `channels.glb` loads.
