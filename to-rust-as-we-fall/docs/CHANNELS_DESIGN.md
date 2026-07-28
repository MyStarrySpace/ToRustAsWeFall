# The Channels — Design (Sector 12, the flooded drainage)

> **Canon correction (2026-07-21):** the uppercase `TRACE`, `BLOOM`, and `BRACE`
> vocabulary retained in older proposals below is design shorthand, not a cast-ability kit.
> Implement it through target-owned SCAN/HACK, READ/TEND, and place-specific survival
> interactions/overlays. Do not surface those terms as ability buttons. The committed cast
> roster is Aster's **EMP** and Peris's **Wrap** only.

The authoritative design intent for the channels stretch. Written down so it stops getting
re-explained. The current `wash_relay_chunk.gd` is ONE chunk of this larger structure; treat
this doc as the target the chunk should grow toward.

## Spatial structure (nested)

- **Stretch** — the whole channels level, bookended by **two shelters**: the **START shelter at
  the BOTTOM of the spiral**, and the **END shelter at the TOP** (just below the bridge you enter
  from). You **ASCEND** the spiral, climbing against the downward flow — a wash carries you back
  DOWN to the bottom start shelter.
- **Entry** — you arrive on a **bridge atop the spiral**, where you can see the WHOLE stretch
  laid out below at a glance: every plant, every flow control, the whole climb. Then you drop in and
  the climb begins from the bottom. That overlook is the in-fiction reason **Peris knows the
  plants' positions later** — she read them from the bridge, so they stay marked in her flora
  overlay even where the party can't currently see them (see "Perception in the channels").
- **Chunk** — the stretch is divided into chunks. A chunk is the span from the previous chunk
  down to **the sloperope that connects it back to the stretch start**. That physical line is the
  chunk's "checkpoint": a washed member uses it to
  rejoin at THIS chunk instead of redoing the whole stretch. It restores no stats; HP/stamina
  recovery and revival belong to a full shelter rest.
- **Section** — each chunk is divided into sections. A section is a challenge (or series of
  challenges) that ends in **something that helps the other members advance** — e.g. an
  **override button that stops the channel flow for that section** so the rest of the party can
  cross.

## Entry teaching — the wash-tutorial threshold (Endo's Junction → the spiral)

Before the fall to the spiral, at **Endo's Junction** (his home turf — the channels are Endo's
territory), a self-contained room TEACHES the wash mechanic diegetically (GDD §2.8, tutorial-as-
scene) so the player meets the spiral already understanding it. Layout (from the design sketch),
three bands:

- **Top shelf:** the tools laid out — **Capbage ×3** (TIGHT-tier hide flora; GDD §7.9 — a
  self-sealing leaf head a character steps into and is *fully undetectable* inside, one per
  Capbage), the **flure** (the lure flower), and a **portal**.
- **Middle:** **three channels (washes) side by side**, phased so **at least one is always
  flooding** (Channel 1 flooded, Channels 2–3 alternating) — you **cannot walk straight across**.
- **Bottom:** a **portal** (left), **enemies** (they patrol/guard the crossing), and the exit
  **→ TO SPIRAL** (right).

**The teaching solve:** **hide in a Capbage** to slip the patrolling enemy (tight-hide,
undetectable), **activate the flure** to **lure that enemy into the alternating channels**; it's
**washed (drowned)** crossing them; then **take the portal across** to the spiral.

**What it teaches, before any of it can kill the player, all in one room — the channels' whole
stealth+wash vocabulary:**
1. **Hiding** — the Capbage tight-hide (the hide verb, on Peris's flora; ties to the spiral's hide
   alcoves later).
2. **The flure** — lure an enemy where you want it.
3. **The wash** — timed water, alternating, lethal (you learn it by watching the enemy die in it,
   not by dying yourself).
4. **Wash kills enemies** — the drain-loop drown, planted here first as the lesson.
5. **Portal traversal** — cross a wash barrier you cannot walk.

**Reuses / new:** the Capbage is a flora `CONCEAL_FULL` tight hide (reuses the existing
concealment system + the spiral's hide-alcove model); the flure reuses `lure_relay`'s lure; the
lure-into-wash drown reuses the drain-loop's `_drown`/`take_damage` path; it sits in the existing
**Endo's Junction** region (`endo_junction_stretch`, `next_slot: act1_channels_first_spiral`). NEW:
the "three adjacent channels, ≥1 always on" tutorial layout; a **portal traversal** mechanic
(step in → cross; today only the warp-in VFX exists, not a player teleport); and a Capbage as a
placeable/standing tight-hide prop here.

**Capbage group-interaction (general Capbage behavior, taught here with the 3-pack):** with
multiple members selected, clicking a *group* of Capbages **assigns one member per Capbage** (a
one-to-one hide). If there are MORE selected members than Capbages, the **closest** members get
the hides and the rest don't fit (one character per Capbage; rare larger specimens fit two — GDD
§7.9). This rides the existing party-assignment machinery (the `_assign_party_cells` distinct-cell
outward-ring spread used for party moves), just targeting Capbage slots instead of free cells.

**Open questions for this room:** (a) is the portal a free teleport, or does clearing the enemy
power/unlock it? (b) does this live as the final beat of the existing junction chunk, or its own
small `channels_wash_intro` chunk between the junction and the spiral?

## Failure, reunion, and shelter recovery (the core loop)

- A character who is **washed out** (mistimed cross, guard hit) is swept down to the **start of
  the stretch** (the start shelter). They are **stranded** there until reunited with the party.
- **Reunion** = they must **climb the deployed sloperope** back up to the proper chunk. The
  physical connect-back at a chunk's end lets a stranded member rejoin there;
  it never heals, restores stamina, revives, or clears deprivation.
- **Recovery** = a **full rest at a shelter**. This is where HP/stamina recovery and revival live,
  and where the party spends ATP to afford the night.
- **The decision:** when a member goes down, the party chooses to either
  (a) **invest the time to send them back up** now, or
  (b) **leave them waiting** while the others finish the section, then drop the sloperope at the
      chunk end so they can climb.
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
   spec or the section is unfinished. The Shadow is harder by setup/resource (read the real beat at
   its gauge + tend or place an already-authored flora tool), never a relabel of the same button,
   never prompted or labeled.
2. **Demand two registers, not one button.** A section is legitimate only if clearing it genuinely
   needs two perception registers composed — one answers WHERE (Peris reads or tends the lane),
   the other WHEN (Aster reads the surge at a gauge or through his overlay). Each contextual action
   produces a **world state the solve reads** (a tended cell marks walkable ground; a scanned gauge
   exposes the safe crossing window), not a flavor toast. Test: if reverting that world state doesn't make the section unsolvable or
   strictly harder, it isn't load-bearing — fix it.
3. **The geometry teaches on first approach; explicit hand-holding is earned, not default.** The
   *implicit* tell is always present from first sight — the flow-strip telegraph brightens before
   every surge (now visible on the real GLB scene), the binding icon, the layout, the bridge
   overlook pre-reading the whole stretch, and the first held-override visibly calming-then-
   resurging (hold=calm, release=surge, no text). That implicit layer is the primary teacher and
   is NEVER gated behind failure. The *explicit* spelled-out aid (the ghost flush-preview + Aster's
   "time it here" line) is deliberately **earned** — it appears only after the party is washed
   ~3× in the SAME section (a struggling-player escalation), so the tutorial isn't spammed up
   front. Keep the explicit hint gated; never gate the implicit tell. (The wash-counter "we run
   these" line is character color, not a rule.)
4. **Escalate by degradation and new pressure, never by shrinking the window.** A later section is
   harder because a register decayed (Peris's flora read flickers/mis-marks; a bloom germinates
   slower or fails) or a NEW pressure stacks (a guard laid over a timing surge → solve WHEN-to-cross
   and WHERE-to-hide at once) — reuse the SAME geometry with a degradation param. Never shorten the
   period or add spouts; tighter timing is level-difficulty, the thing the pitch rejects.
5. **The advance-helper is a HELD commitment with an inheritable role — never a one-shot latch.**
   A held console (stand on it → flow holds; vacate → flow resumes) keeps the holder committed and
   exposed; co-locate a guard that threatens the *holder* so losing them forces a re-plan and any
   non-washed member inherits the station. Forbid permanent `_override_locked` latches.
6. **A wash costs by depth and reunites diegetically — beatable, never soft-lock.** Sweep the
   member to the start shelter and STRAND them; reunion is a chosen time investment through the
   physical sloperope, scaling with how deep they fell. The held-role section is the natural place
   to wait for a washed member; all-three-washed = redo the chunk, so reuniting before pushing is
   the smart play. Recovery waits for the next full shelter rest.
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
- **SHADOW SOLVE (Aster+Peris)** — the harder same-hazard route (Aster reads WHEN through his overlay
  or a target-owned gauge; Peris reads/tends WHERE through her flora register, no Endo). Beatable,
  harder by setup, NEVER prompted or labeled.
- **ADVANCE_HELPER** — {held-override / held-plate / double-plate / timed-window}; HELD, never a
  latch. Where it sits, what it relieves while held.
- **ROLE_INHERITANCE** — who takes the held station on a wash + what re-planning the loss forces.
- **FAIL / REJOIN** — what a wash does here (swept, stranded, dropped), the physical runback/climb
  cost, and which connect-back reunites the party at THIS chunk. It changes no stats. Never a soft-lock.
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
  body to hold while two cross. Aster scans the basin's real gauge to find the next window where BOTH
  spouts are dark (a real min-gap over the two cadences) for an UNHELD timed crossing; Peris tends or
  places an authored traversal-flora cutting on a valid fertile lip → after its visible growth wait
  it raises a **causeway** that locally breaks the current
  (causeway cells excluded from the wash), so they cross in two timed dashes. Harder: a correct
  double-beat read + a germination wait under threat; the causeway covers only ONE lane.
- **Teach (no text):** the first step onto the override visibly calms the basin and dims both strips;
  step OFF and they re-brighten and a harmless spout surges where you stood. Player SEES hold=calm,
  release=surge. The bridge overlook already showed the basin + Peris named its plants.
- **Fail/rejoin:** a washed member is swept to the start shelter, stranded but mobile; they run the
  route again or climb the deployed Sloperope, with travel time priced by depth. Rejoining never
  restores stats; a full shelter rest owns recovery. All three washed = redo the chunk.
- **Escalation (same geometry, later):** ramp through Peris's degradation — her lip markers + bridge
  pins go fuzzy/drop and a causeway germinates slower or fails. The Shadow gets harder exactly where
  it leans on her; the Endo Presented path is unchanged. NO new spouts, NO shorter period.

## How the current chunk maps to this (and what's still TODO)

The shipped `wash_relay_chunk.gd` is effectively **one chunk** of the stretch:
- ✅ Sections with challenges ending in an advance-helper (override / plate / sluice).
- ✅ A wash sweeps the member to the start (`START_POS`).
- ✅ A physical sloperope connect-back exists at the chunk end.
- ✅ Surge telegraph now survives the real GLB scene (warped under `_strip_root`).
- ✅ **Strand-and-rejoin is real** — a wash STRANDS the member at the start; the deployed sloperope
  reconnects them without changing HP, stamina, ATP, downed state, or deprivation. Full shelter
  rest remains the only recovery sink.
- 🔜 **Multi-chunk stretch** — split the stretch into several chunks, each with its own
  connect-back device, bookended by two shelters, entered from the spiral-top bridge. Reunion
  happens at the chunk; recovery happens at shelter. (Larger restructure; future.)
- 🔜 **Per-section activator co-op** — guarantee each chunk has a hold/activate section where one
  member enables the others and the role can be inherited on a wash.
- 🔜 **Bridge entry vantage** — the opening over-look that justifies Peris's plant knowledge.

## Invariants to preserve

- Everything timing-related rides the gameplay scheduler (replay / fast-forward safe).
- Visual-only effects are `@rendering_only`; warped set-pieces live under their own `Node3D`
  root so they survive `hide_flat_graybox` when `channels.glb` loads.
