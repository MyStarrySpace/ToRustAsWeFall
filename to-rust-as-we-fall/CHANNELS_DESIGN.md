# The Channels — Design (Sector 12, the flooded drainage)

The authoritative design intent for the channels stretch. Written down so it stops getting
re-explained. The current `wash_relay_chunk.gd` is ONE chunk of this larger structure; treat
this doc as the target the chunk should grow toward.

## Spatial structure (nested)

- **Stretch** — the whole channels level, bookended by **two shelters**: the **START shelter at
  the BOTTOM of the spiral**, and the **END shelter at the TOP** (just below the bridge you enter
  from). You **ASCEND** the spiral, climbing against the downward flow — a wash carries you back
  DOWN to the bottom start shelter.
- **Entry** — you arrive on a **bridge atop the spiral**, where you can see the WHOLE stretch
  laid out below at a glance: every plant, every terminal, the whole climb. Then you drop in and
  the climb begins from the bottom. That overlook is the in-fiction reason **Peris knows the
  plants' positions later** — she read them from the bridge, so they stay marked in her flora
  overlay even where the party can't currently see them (see "Perception in the channels").
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

## Section-design principles

Grounded in the GDD: *asymmetric perception IS the gameplay* (§1, §2.2); *difficulty rises
because the characters degrade, not because the levels get harder* (§1, §2.3); *every puzzle has
a Presented solve (the hook member) and an Aster+Peris Shadow solve* (§2.6, anti-principles §2.6.6);
*the geometry and the binding icon teach — never explanatory text* (§2.8). A section that violates
these isn't "polish-later," it's unfinished.

1. **Two solves, one geometry (build the Shadow, don't bolt it on).** Author each section as ONE
   space with a Presented solve (the hook member — usually **Endo**, who reads this drainage as
   home) AND a designed **Aster+Peris Shadow** through the *same* hazard. Fill both columns of the
   spec or the section is unfinished. The Shadow is harder by setup/resource (TRACE the real beat +
   BLOOM a substitute lane), never a relabel of the same button, never prompted or labeled.
2. **Demand two registers, not one button.** A section is legitimate only if clearing it genuinely
   needs two perception registers composed — one answers WHERE (Peris BLOOM lights the dark lane),
   the other WHEN (Aster TRACE names the surge window). Each ability is a **state the solve reads**
   (a bloomed cell is the only walkable read of a dark section; the TRACE window is the only safe
   cross), not a flavor toast. Test: if reverting an ability doesn't make the section unsolvable or
   strictly harder, it isn't load-bearing — fix it.
3. **The geometry teaches on first approach, never gated behind failure.** The mechanic is legible
   from the layout + binding icon on first sight; any line lands *as* the player attempts it (the
   first held-override visibly calms the basin and re-surges the instant it's vacated — hold=calm,
   release=surge, no text). The bridge overlook pre-teaches the whole stretch. Move the surge
   preview to the FIRST encounter of each section *type*; the wash-counter line is character color
   ("we run these"), never the rule.
4. **Escalate by degradation and new pressure, never by shrinking the window.** A later section is
   harder because a register decayed (Peris's flora read flickers/mis-marks; a bloom germinates
   slower or fails) or a NEW pressure stacks (a guard laid over a timing surge → solve WHEN-to-cross
   and WHERE-to-hide at once) — reuse the SAME geometry with a degradation param. Never shorten the
   period or add spouts; tighter timing is level-difficulty, the thing the pitch rejects.
5. **The advance-helper is a HELD commitment with an inheritable role — never a one-shot latch.**
   A held console (stand on it → flow holds; vacate → flow resumes) keeps the holder committed and
   exposed; co-locate a guard that threatens the *holder* so losing them forces a re-plan and any
   non-washed member inherits the station. Forbid permanent `_override_locked` latches.
6. **A wash costs by depth and recovers diegetically — beatable, never soft-lock.** Sweep the
   member to the start shelter and STRAND them; recovery is a chosen time investment via the chunk's
   connect-back (Terminal = fast call, Sloperope = slow free climb), scaling with how deep they
   fell. The held-role section is the natural place to wait for a downed member; all-three-washed =
   redo the chunk, so reuniting before pushing is the smart play; BRACE refunds the re-cross.
7. **Three voices in three registers; the wash is iron, not water.** Cut the `//` readouts to true
   machine confirmations; the rest are character lines in-register — Aster the data read ("Clearance
   holds four seconds"), Peris the relational/flora read ("It pulls down — wait for it to breathe
   out"), **Endo never speaks** (UI marker / gesture / pre-scouted path). Theme every hazard as the
   body's waste-clearance failing (rust-red iron backwash + particulate, named pathology).

## Section spec template (fill this per section)

- **ID / TYPE** — name + the ONE verb (override / read-the-beat / hold-plate / hide / lure).
- **HAZARD + TELL** — what washes you + the pause-readable diegetic telegraph. Anything that can
  wash you MUST telegraph first — no coin-flips.
- **CADENCE** — scheduler periods/phases/durs (a list; single-period is the degenerate case).
  Analytic next-onset only, never per-frame coincidence. Fast-forward + replay invariant.
- **PERCEPTION_LOCK** — what is HIDDEN from each single register, revealed only by composing two
  (one WHERE, one WHEN). Name the overlays that must be on to read it.
- **PRESENTED SOLVE** — the hook member's path (Endo reads home, crosses first, holds the helper).
- **SHADOW SOLVE (Aster+Peris)** — the harder same-hazard route (Aster TRACE times it + Peris BLOOM
  lights/causeways the lane, no Endo). Beatable, harder by setup, NEVER prompted or labeled.
- **ADVANCE_HELPER** — {held-override / held-plate / double-plate / timed-window}; HELD, never a
  latch. Where it sits, what it relieves while held.
- **ROLE_INHERITANCE** — who takes the held station on a wash + what re-planning the loss forces.
- **FAIL / RECOVER** — what a wash does here (swept, stranded, dropped) + the depth-scaled cost;
  which connect-back rejoins at THIS chunk + BRACE refund. Never a soft-lock.
- **TEACH_BEAT** — the diegetic first-encounter tell (staging + binding icon + one in-register line
  played ONCE on entry, not after N failures).
- **ESCALATION_HOOK** — from the degradation/pressure menu (flora-sensor decay / overlay loss / a
  new stacked pressure), NOT "lower the period." Same geometry, a degradation param.
- **DIALOGUE** — in-register lines (Aster data / Peris relational / Endo silent UI); `//` = machine.

## Worked example — THE HOLDFAST CROSSING

A guarded basin you ASCEND whose flow-override must be HELD, not latched.

- **Presented:** a wide lowered basin floods on TWO interleaved beats (e.g. 4.0s + 6.5s) so the safe
  gap grows/shrinks on a long cycle — a live read, not a memorized beat. Each spout's strip
  brightens before its own onset. A far-ledge **flow-override console**: stand on it → both spouts
  hold open; vacate → flooding resumes. The wash is iron backwash (rust + particulate upstream).
- **Perception (three truths about one basin):** Aster overlay = the cadence/timers + the override
  as a hackable hold; Peris overlay = the fertile lip cells (for a flora causeway) + the plant pins
  she read from the bridge, still marked in the dark; Endo overlay = the safe-tile diagonal (cells
  dry longest) + the deep hide nook. All on = fully legible; Aster+Peris only = cadence + flora but
  NOT the handed safe-tiles, so the pair must DERIVE the path. Each highlight renders only under its
  owner's toggle.
- **Presented solve (Endo hook):** Endo's survival overlay paints the safe diagonal (home); he
  crosses first and HOLDS the override; Aster & Peris walk the calmed basin. A roaming guard
  threatens the HOLDER — knock Endo off and the two on the floor are exposed; whoever isn't
  mid-cross inherits the hold.
- **Shadow solve (Aster+Peris, harder, unadvertised):** no Endo = no safe-tile overlay AND no spare
  body to hold while two cross. Aster TRACE solves the next window where BOTH spouts are dark (a real
  min-gap over the two cadences) for an UNHELD timed crossing; Peris BLOOM plants anchor-flora on a
  fertile lip → after a germination wait it raises a **causeway** that locally breaks the current
  (causeway cells excluded from the wash), so they cross in two timed dashes. Harder: a correct
  double-beat read + a germination wait under threat; the causeway covers only ONE lane.
- **Teach (no text):** the first step onto the override visibly calms the basin and dims both strips;
  step OFF and they re-brighten and a harmless spout surges where you stood. Player SEES hold=calm,
  release=surge. The bridge overlook already showed the basin + Peris named its plants.
- **Fail/recover:** a washed member is swept to the start shelter, stranded; recover via Terminal
  (fast, costly) or Sloperope (slow, free), cost by depth; BRACE refunds the re-cross; all three
  down = redo the chunk.
- **Escalation (same geometry, later):** ramp through Peris's degradation — her lip markers + bridge
  pins go fuzzy/drop and a causeway germinates slower or fails. The Shadow gets harder exactly where
  it leans on her; the Endo Presented path is unchanged. NO new spouts, NO shorter period.

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
