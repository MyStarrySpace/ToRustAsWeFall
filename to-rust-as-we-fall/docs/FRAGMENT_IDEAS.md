# Fragment & Level Ideas Register — buildable level content from the rosters

**Owner: the director** (edit freely — this document is yours). Drafted 2026-07-07 by composing the
canonical rosters (`reference-docs/fauna_roster.md`, `flora_taxonomy.md`) with the design registers
(`ENVIRONMENT_ELEMENTS.md`, `ECOLOGY_COMBOS.md`, `DESIGN_PRINCIPLES.md`) and put through a two-auditor
adversarial pass — an **ecology-canon** checker (roster/verb/ruling fidelity) and a **design-law +
buildability** checker (spine, P8/P10/P11/P12/P16/P17/P18, honest new-class count). Five drafts were
FLAGGED and corrected; every correction is folded into the entry and summarized in the appendix.

Companion registers: `ENVIRONMENT_ELEMENTS.md` (the atomic per-region elements these compose),
`ECOLOGY_COMBOS.md` (the flora×fauna combo cards), `LEVEL_DESIGN_RESEARCH.md`. Authoring discipline:
`.claude/skills/level-authoring/SKILL.md`.

**These are ABOVE the element/combo layer** — each idea is a *fragment* (one playable chunk) or a
*stretch* (a gated chain of chunks) that composes elements and combos. Working names are DESCRIPTIVE;
christening anything properly is the director's call.

**How to read an entry:** HOOK = the one core tension. VERB(S) = what each section teaches (one verb
per section, P8). ELEMENTS = the canonical fauna/flora/objects used (exact spellings). PAIR = the
guaranteed Aster+Peris solve (the P10 floor); SHADOW where the presented solve uses a specialist.
FAIL = the P11 recovery. BUILD = honest — COMPOSABLE-NOW vs the exact new classes needed, cross-checked
against **code**, not just the stale `[BUILD]` flags. AUDIT = what the adversarial pass corrected.

---

## Cross-cutting build reality (read before picking one)

Three findings from the audit gate which ideas are cheap:

1. **The enemy-on-enemy strike edge is the shared unlock.** `_resolve_strike` (`scripts/game/enemy.gd`)
   drives party-only `_detection_targets`, so *any* "the turret / the burst / the ecology kills another
   enemy" is **topology, not a mechanic** (P6) until that edge ships — scheduler-analytic, with its own
   FF-invariance test (Build-next #8, "large"). It gates the showy halves of **#4, #8, #9, #14**. Building
   it once opens a whole tier of the combo cards. Never count it as free.
2. **There is no player-attack verb, by design** (nothing in `player.gd` / `project.godot`; combat is
   "rarely the best move", P13). Every "fight/kill through" framing must become **endure telegraphed
   chip-damage** (enemy→party) or **route-around**. This is why #5 was rebuilt.
3. **Code beats the stale flags — in both directions.** `scarpet.gd` (`class_name Scarpet`) and
   `candid_zone.gd` (CONCEAL_FULL scan-blind + DoT) **already ship**, so ideas leaning on them (#2, #3,
   #8, #11, #12, #15) are cheaper than the registers imply. Conversely the **cloak/reveal system is only
   taxonomy DATA** (`flora_species.gd`) with no enemy-side cloak state — #7 and #16 must count the whole
   CloakedEnemy + reveal-consumption system (Ledger #7), not a `flora_light` tweak.

**Roster timeline (bit everyone):** Endo travels with the party only through **shelters ~6–7**, then
departs; Myke/Oli arrive shelters 11–12. So **Ancourage (shelter 10) fragments run on Aster+Peris only**
— no Endo BRACE (this broke draft #9). At **Open Files** the register's *presented* solver is Endo; the
Aster spoof is the *shadow* (this broke draft #11's framing).

---

## Micro tension chunks (one core tension, greybox-first)

### 1. Linger Tax
- **HOOK:** An **Aember** camps a 2-cell breach and strikes whoever *lingers* in it (its exact roster
  verb). A channel beat crosses the breach — so you must enter aligned with the dry window and never
  stop, or the linger-strike lands during your forced wait.
- **VERB:** time-the-window.
- **ELEMENTS:** Aember (linger-striker), one `channel`, shelters both sides.
- **PAIR:** Aster TRACE reads the beat, Peris crosses on it. Couple or deterministically offset the
  Aember cadence and the channel cadence so it stays **one** WHEN verb (two independent clocks would
  drift it into a two-clock puzzle).
- **FAIL:** priced sweep to the previous gap; free-flush only if this is a first-exposure teacher.
- **BUILD:** one new class (Aember FSM: camp-a-cell + linger-timer strike). Channel is COMPOSABLE-NOW.
  **Follow-up seed (separate chunk, per the emergence rule):** a **Hushbloom** as mistimed-hold
  insurance — canon, it interrupts any wind-up (ruling 7).
- **AUDIT:** OK both. Only gap: name the pair solve and couple the two cadences.

### 2. Wall-Hugger's Lament
- **HOOK:** Inverts the hug-the-wall instinct. **Crust** acid pores vent on a cadence along *both*
  walls; a **Spiker** turret watches the exposed center lane. Safe ground is the *moving intersection*
  of "wall not venting now" and "out of the turret arc."
- **VERB:** positioning under a moving safe-cell.
- **ELEMENTS:** Crust vents (greybox = `channel` objects reskinned as wall-adjacent strips — keep it a
  reskinned band, NOT full Crust AI), Spiker (rooted LOS turret), Capbage/Scarpet (both ship).
- **PAIR:** Aster TRACE = acid cadence (WHEN), Peris Scarpet/Capbage = LOS-break (WHERE). Reverting
  either register makes it unsolvable.
- **BUILD:** one new class (Spiker: rooted, fires at the player in-arc). Its counter is the verbatim
  roster line — "break LOS with Capbage or Scarpet." Keep Spiker enemy→party only here.
- **AUDIT:** OK both.

### 3. The Loudest One
- **HOOK:** A **Tangler** locks onto the *loudest neural-active mover* (its canonical attractor). One
  member runs a noisy decoy orbit; the quiet two thread the tau-thicket. Decoy stops → the lock jumps.
- **VERB:** distract (hold the lock).
- **ELEMENTS:** Tangler, tau-thicket geometry, shelters.
- **PAIR:** Aster is the loud decoy, Peris the quiet crosser. **Scarpet does NOT help the crossers here**
  — it masks iron/metabolic, not the neural channel the Tangler reads; "quiet" means *walking*, not
  masked. (This distinction is the whole point.)
- **BUILD:** one new class (Tangler chases-loudest, enemy→party). **Keep the lead-into-Candid converter
  OUT of the atom** — that "unravel the Tangler in a Candid zone" is an enemy-degradation edge, unbuilt.
- **AUDIT:** OK both.

### 4. Windup Window
- **HOOK:** A **Flare** cluster lane where *your own bunching* is the trigger (ruling 3: bunching is
  bunching, whoever crowds) — 2–3s wind-up, then a friend-and-foe burst. Single-file through the portal
  queue is safe but slow under **Gnawer**-pack pressure.
- **VERB:** cross single-file (spacing discipline).
- **ELEMENTS:** Flare cluster, `portal_pad` queue, Gnawer pack (the surviving pressure).
- **PAIR SHADOW:** the same portal-queue crossing done by **two** bodies — fewer members to keep
  unbunched, strictly harder (a real cost premium, not a cheaper trick).
- **BUILD:** Flare FSM (bunch-trigger + wind-up + burst) as a party-facing hazard is buildable. **The
  "lure a bunched Sapscrap group to bomb the pack" play is NOT this chunk** — it needs the enemy-on-enemy
  edge + Sapscraps + Gnawer classes; split it to its own offensive combo card.
- **AUDIT:** FLAGGED (law). Original conflated the offensive combo into the "shadow." Corrected: presented
  pressure IS the Gnawer pack (same geometry); shadow is the 2-body queue; offensive play moved out.

### 5. The Feeding Frenzy  *(was "Immunity Gap")*
- **HOOK:** **Toxos** are bait, not opponents (there is no player-attack verb). A dense Toxo pocket
  draws every healthy hunter into a feeding frenzy between you and a cache. Route *through the frenzy
  while the predators are occupied*, or *lead your own pursuer into the pocket* so the healthy-hunt takes it.
- **VERB:** time-the-frenzy / redirect-aggression (archetype 1).
- **ELEMENTS:** Toxos (bait/location-tell, roster verb), one co-located real predator (the HP source),
  cache, shelters.
- **PAIR:** measured P17 crossover — the through-the-frenzy window vs the slow detour under the day
  clock; prove the flip with a sweep, don't assert it. HP toll comes from the **real predator**, never
  from grinding feeble Toxos.
- **BUILD:** one new class (Toxos: weak, drawn-upon). The predator is whatever pack you place.
- **AUDIT:** FLAGGED (both). Original was a "fight through" gauntlet — no player-attack verb exists and
  it fought the routing-over-combat spine (P13). Rebuilt around the canonical bait/ignore role.

### 6. Two Hands on the Gate
- **HOOK:** Pure held-station co-op. Hold the metrics-gate console (Open Files #4) while the crosser
  clears a portal (Plumbing #4); the holder is exposed to a **Naturalizer**'s return leg. Then the
  crossed member holds the *far* console to ferry the holder back — inheritable roles (P12).
- **VERB:** hold.
- **ELEMENTS:** metrics-gate held override + `portal_pad` + Naturalizer patrol — **both elements
  COMPOSABLE-NOW**; a coded chunk on the `wash_relay` held-console pattern.
- **PAIR:** this IS the bare-pair story (two consoles, two crossings); name it as such.
- **BUILD:** no new class. One [BUILD] *composition*: the patrol's charge must target the holder's
  console tile (P12/CHANNELS #5) — unbuilt but small.
- **AUDIT:** OK both — model one-verb held composition. Only note: name the threat as a Naturalizer.

---

## Fragments (a composed chunk, gated)

### 7. Cable Run
- **HOOK:** **Hidras** disguised as cabling line a Hypelines conduit corridor (their canonical habitat);
  planted **Seefern** reveals the material-signature mismatch. Move past unscanned cabling and the
  ambush-cut lands. WHERE lock.
- **VERB:** reveal.
- **ELEMENTS:** Hidra, Seefern reveal.
- **PAIR SHADOW:** Aster's overlay reveal — make it *momentary/narrow* so it is harder than a persistent
  planted Seefern (else the shadow is easier — illegal).
- **BUILD:** the **whole cloak/reveal system** (Ledger #7): CloakedEnemy hidden-from-player state +
  reveal volume + consumption plumbing. NOT a `flora_light` extension. Teach the first Hidra safely so a
  cut is a *named mistake*, not a coin-flip (P6/P18).
- **AUDIT:** OK both — canon-clean; only the build cost was understated (now corrected).

### 8. The Gate That Solves Itself  *(combo card 4)*
- **HOOK:** A loud (running) member holds a **Tangler**'s neural lock and leads it across a **Spiker**'s
  firing arc; the turret kills the grappler; corpse-signs mark the cleared lane.
- **VERB:** redirect-aggression (the gate self-resolves).
- **ELEMENTS:** Tangler + Spiker (built by #3 and #2 first), Scarpet as the *quiet crossers'* cover +
  Spiker LOS-break.
- **BUILD:** gated on the **enemy-on-enemy strike edge** (Tangler-dies-to-Spiker-fire), FF-analytic —
  #2/#3 supply the two classes but *never* the self-solving duel. Without the edge, "the turret kills
  the grappler" is topology, not a mechanic.
- **AUDIT:** FLAGGED (both). Original inverted the bait — "Scarpet-quiet baits the Tangler" is backwards
  (a Tangler locks the *loudest*, and Scarpet doesn't touch the neural channel). Corrected: loud bait,
  Scarpet = quiet cover only. And the decisive build (the enemy→enemy edge) was omitted.

### 9. Flare Lane Ignition  *(combo cards 3 + 11, Ancourage #2 stage)*
- **HOOK:** The party can't cast fire, so the *environment* is the igniter. Aster reads the vent/flare
  cadence; Peris **tends a Gasafoetida cluster** at the damp band edge; the flare-lane's own lit
  infrastructure ignites the cluster on the beat, and the serotinous burst detonates the bunched
  **Flares**. Place, then leave the radius before the beat.
- **VERB:** vent-timing / plant-and-clear.
- **ELEMENTS:** Gasafoetida **cluster** (3–5 pods, the serotinous FIRE register — NOT a single carried
  pod, which is only REPEL), Flares, Ancourage fused-heat vent lane.
- **PAIR:** **Aster+Peris only** (Ancourage is shelter 10 — Endo is gone). Presented ≈ the pair solve
  here; a Myke-Inflame variant is the later specialist path.
- **BUILD:** large stack — Gasafoetida object + Flare FSM + **analytic ignition-propagation** (each with
  an FF test). **Scope the burst's target explicitly:** clearing a party-facing choke is buildable;
  bombing a Gnawer PACK needs the enemy→enemy edge.
- **AUDIT:** FLAGGED (both). Two errors: "Endo BRACE presented" is impossible at shelter 10; and the fire
  burst is a *grown/tended cluster*, not a placed pod. Both corrected.

### 10. Census Night  *(combo card 12 shape, Act 2 Cleanstreets, greybox-now path)*
- **HOOK:** Two civic gates on independent cadences; the agent that makes the phase-lock lethal is a
  **Naturalizer** patrol whose sweep reaches the "safe-pause" pad exactly when the gates lock. A
  **Hushbloom** stuns the Naturalizer (enforcement is stunnable, ruling 4) to buy pad-time — and its
  30–60s recharge is the genuine third clock.
- **VERB:** phase-lock reading + stun-to-buy-time.
- **ELEMENTS:** two civic cadence-gates (greybox = `channel`-gates), Naturalizer, Hushbloom.
- **PAIR:** both cadences must be Aster-TRACE-legible ahead of time so the pad-trap is a *readable
  mistake*, not a gotcha.
- **BUILD:** Hushbloom object + Naturalizer patrol; greybox path exists.
- **AUDIT:** FLAGGED (ecology). Original left the Hushbloom inert (a stun with no enemy to act on, and a
  phase-lock with no agent). Corrected: the Naturalizer is the killer AND the stun's target.

### 11. Spoofed Through  *(Open Files #1)*
- **HOOK:** A tag-reader scan-arch + a **Naturalizer** on a fixed route. The credential-spoof window is
  a HELD station (not a latch); hold it open while the others file through.
- **VERB:** spoof (held).
- **ELEMENTS:** scan-arch, Naturalizer, Candid film corridor (the shadow lane — `candid_zone` ships).
- **PRESENTED vs SHADOW:** the register's *presented* solve is **Endo's authorized-tag held override**;
  **Aster's transient spoof through the Candid scan-blind lane is the SHADOW** (HP-DoT priced, harder).
  Lead with the presented path, or justify Endo's absence.
- **BUILD:** held-override + Candid lane both composable now.
- **AUDIT:** FLAGGED (ecology framing). Original led with the shadow (Aster) as if it were the presented
  path. Corrected to the register's presented/shadow split.

### 12. Harvest Under Watch  *(Hypelines #5)*
- **HOOK:** **Sapscrap** strippers swarm a cache; a **Flure** pulls them off (their textbook roster
  interaction — only siderophores answer an iron decoy). The lure decays, and two slow carry trips
  (archetype 3) price so the **second trip needs a re-lure**. A roaming enemy survives as back-half
  pressure.
- **VERB:** lure → carry.
- **ELEMENTS:** Sapscraps, Flure, cache-carry, a **non-enforcement roaming** enemy (Naturalizers walk
  fixed routes — they don't roam; use a genuine roamer for the pressure).
- **PAIR SHADOW:** Aster times the decoy hold, Peris sites the Flure + a Scarpet siding — tighter window,
  no Endo.
- **BUILD:** confirm/add a cache-carry slow-walk state (body-carry exists today; retargeting to a cache
  is small).
- **AUDIT:** OK both — canonical Flure→carry chain. Only fix: "roaming patrol" → a real roamer, not a
  Naturalizer.

---

## Stretches (a gated chain of chunks)

### 13. The Open Files Heist
- **SHAPE:** start shelter → bridge overlook → **#11 spoof gate** → drawer-canyon ledger (Open Files #3)
  → metrics-gate sacrificial hold (Open Files #4) → exit shelter. Typed archetype-chain handshakes: the
  spoofed tag suppresses scan escalation; the canyon yields the records the hold spends.
- **BUILD/FAIL:** add a **start shelter + per-chunk connect-back** (only the exit was named). Bound the
  "marked → patrol reroute" escalation so it **decays after one section** — a persistent stretch-wide
  spiral would break the P10 bare-pair floor and P11's one-section cost. Bridge overlook is [BUILD]
  (stage-gated, P3); reroute uses NEEDS-BUILD Open Files #2.
- **AUDIT:** OK — canonical Act-1 Open Files composition. Corrections: bound the escalation, add
  start-shelter + connect-backs.

### 14. Ancourage Ascent
- **SHAPE:** vent-timing approach → **#9 flare-lane ignition** → post-burst debris field with circling
  **Gnawers** (card 3 canon: burst debris draws a converging pack), sprint gaps priced ~90% of the 40wu
  bar. Fail **sweeps DOWN the slope** to the previous gap with a **Sloperope (Climbvine)** connect-back —
  the exact canonical Climbvine use (grows only on inclines; an ascent is ideal). Best fail-forward of
  the set.
- **PAIR:** Aster+Peris (Ancourage is shelter 10). Inflammashunt is a DZ, so the **dusk clock is exempt**
  — stamina/positional pricing carries the tension, not P16.
- **BUILD:** large, far-horizon — inherits #9's stack + DebrisField + Gnawer convergence + Sloperope
  connect-back (Plumbing #3 NEEDS-BUILD). Gnawer-in-debris is enemy→party (fine); only a Flare-bombs-pack
  variant needs the enemy→enemy edge.
- **AUDIT:** OK — inherits #9's corrections (pair not Endo; grown cluster).

### 15. Greenfields Curfew
- **SHAPE:** tending-station holds (Greenfields #3) as **pacing troughs** — the only ground stamina
  regenerates — between Flure-lure run windows (Greenfields #2) under **Naturalizer** sweeps. The night
  clock (P16) is the level's boss (legal here — Greenfields is not a cure-component DZ). The Flure lures
  the loitering siderophores, NOT the enforcement (correct Greenfields #2 grammar).
- **VERB(S):** hold (trough) alternating with lure/time-the-window (spike).
- **BUILD:** honest greyboxes — card 7's tended-density-as-advance-notice as a fixed schedule (Build-next
  #1); cadence-doors as `channel`-gates; generic Naturalizer patrol. Scarpet already ships.
- **FAIL:** add per-chunk connect-backs (unspecified in the draft).
- **AUDIT:** OK — right district for card 7; night-clock-as-boss is legal.

### 16. The Wall That Walks  *(Act 2/3 seed)*
- **HOOK:** A **Redactor** posted as a slice of corridor wall. The gate is the **REVEAL, not a fight**
  (its canonical role); route around once seen.
- **VERB:** reveal.
- **ELEMENTS:** Redactor, Seefern (stable reveal volume), Gasafoetida (the shadow's cloud-distortion
  reveal — ruling 8's second sensory-mismatch channel).
- **PAIR SHADOW:** Gasafoetida-cloud distortion gives a *transient, local* flee-silhouette (the cloak
  isn't stripped) — strictly harder than Seefern's stable reveal, which is exactly right for a shadow.
- **BUILD:** the mandatory CloakedEnemy + Seefern-reveal system (the single biggest reveal-layer build;
  shared with #7) + the Gasafoetida object for the second channel. The heat-haze ripple must telegraph
  from first sight so a blind strike is a *named mistake* (P6/P18).
- **AUDIT:** OK — excellent spine fit, wisely scoped to reveal-and-route (avoids the enemy→enemy matrix a
  proxy-kill would need).

---

## Build ordering (cheapest playable first)

| Tier | Ideas | What it costs |
|---|---|---|
| **0 — no new fauna class** | #5 Feeding Frenzy, #6 Two Hands on the Gate | compose shipped systems (+ one held-station composition for #6) |
| **1 — one new class each** | #1 Aember, #2 Spiker, #3 Tangler | one enemy FSM per chunk; all counters already ship |
| **2 — one class + a system** | #12 Harvest (cache-carry state), #10 Census Night (Hushbloom), #4 Windup Window (Flare, party-facing only) | a small state or object on top of one class |
| **3 — the reveal system** | #7 Cable Run, #16 The Wall That Walks | CloakedEnemy + reveal-consumption (build once, use twice) |
| **4 — the enemy-on-enemy edge** | #8 self-solving gate, #9 flare ignition (pack variant), #14 ascent | the shared "large" unlock; opens a tier of combo cards |
| **stretch (compose tier 1–4)** | #13 Heist, #14 Ascent, #15 Curfew | chain the above with typed handshakes + connect-backs |

**Do NOT** resolve the 6 OPEN matrix cells (Climbvine×Hidras, Climbvine×Redactors,
Forget-me-nots×{Sapscraps, Aembers, Hidras, Crusts}) — director-only. #14 (Climbvine ascent) and #16
(Redactor) are the natural hosts if the director *wants* to pose the Climbvine×Redactor blind-ascent
question; as drafted they only reuse already-resolved interactions.

---

## Appendix — what the adversarial audit corrected

- **#4 Windup Window** — the offensive "bomb the pack" combo was masquerading as the P10 shadow (and
  needs the unbuilt enemy→enemy edge + two extra classes). Presented pressure is now the Gnawer pack on
  the same geometry; the shadow is the harder 2-body queue; the combo moved to its own card.
- **#5 Feeding Frenzy** (was Immunity Gap) — "fight through the Toxos" needed a player-attack verb the
  game deliberately lacks and fought P13. Rebuilt around the canonical Toxo bait/ignore role: the frenzy
  is the hazard, the HP toll comes from a real predator.
- **#8 Gate That Solves Itself** — bait was inverted (a Tangler locks the *loudest*, and Scarpet doesn't
  touch the neural channel). Fixed to loud-bait / Scarpet-quiet-cover; flagged the enemy→enemy edge as
  the decisive build.
- **#9 Flare Lane Ignition** — "Endo BRACE presented" is impossible at Ancourage (shelter 10; Endo
  departed ~6–7); and the fire burst is a *grown Gasafoetida cluster*, not a carried pod. Both corrected;
  pair set to Aster+Peris.
- **#10 Census Night** — the Hushbloom had no enemy to stun and the phase-lock had no agent. Added the
  Naturalizer as both the killer and the stun target, making the recharge a real third clock.
- **#11 Spoofed Through** — led with Aster (the shadow) as if it were the presented path; restored the
  register's Endo-presented / Aster-Candid-shadow split.
- **Continuity note applied throughout:** roster timeline (Endo through shelters ~6–7 only) and the
  code-verified availability of `scarpet.gd` / `candid_zone.gd` vs the un-built cloak/reveal system.
