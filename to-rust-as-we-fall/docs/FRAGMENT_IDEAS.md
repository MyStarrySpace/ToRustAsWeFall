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
- **HOOK:** An **Ferrule** camps a 2-cell breach and strikes whoever *lingers* in it (its exact roster
  verb). A channel beat crosses the breach — so you must enter aligned with the dry window and never
  stop, or the linger-strike lands during your forced wait.
- **VERB:** time-the-window.
- **ELEMENTS:** Ferrule (linger-striker), one `channel`, shelters both sides.
- **PAIR:** Aster TRACE reads the beat, Peris crosses on it. Couple or deterministically offset the
  Ferrule cadence and the channel cadence so it stays **one** WHEN verb (two independent clocks would
  drift it into a two-clock puzzle).
- **FAIL:** priced sweep to the previous gap; free-flush only if this is a first-exposure teacher.
- **BUILD:** one new class (Ferrule FSM: camp-a-cell + linger-timer strike). Channel is COMPOSABLE-NOW.
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
- **BUILD:** one new class (Spiker: rooted, visibly connects to a moving target in-arc, then damages only after an uninterrupted LOS delay). Its counter is the verbatim
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

- **ATTEMPTED 2026-08-08, PARKED — read this before retrying.** Two of the three roster lines verify
  immediately: `move_speed 1.35` ("creeps in") and `windup_duration 1.55` (the uncoil, "a clear
  step-away window" — deliberately the inverse of the Naturalizer's short 0.35 contact tell).
  "Prefers hyperexcitable neurons" maps cleanly onto shipped run state via `GameState.is_running()`,
  and the re-lock poll belongs on the scheduler under its own tag (copy `naturalizer.gd`'s
  `_hesitation_poll` idiom), never per frame.
  **RESOLVED 2026-08-08 and SHIPPED (partial).** The cause was the detection SUBSCRIPTION: the base
  drops it outside `DETECTION_SCANNING_STATES`, so a committed enemy stops scanning and every body --
  including its own target -- reads invisible. `Tangler` overrides `_sync_detection_subscription` to
  keep scanning through `alert` and `pursuit` (it is still creeping) and drop it for the snap itself.
  With that, the lock correctly takes the RUNNING body and correctly does NOT release when that body
  goes quiet. `--test-tangler` guards creep speed, the long uncoil, and both halves of that rule.
  **The HAND-OFF works too, and the thing that hid it was the test, not the class.** A Tangler stops
  scanning once it is in contact (windup/charge/impact/recover, by design), and a decoy parked at
  `attack_range` drops it straight into that cycle forever -- so no hand-off can ever fire and the
  lock looks stuck. A decoy ORBITS: hold the bodies inside the 5.0 scan but outside the 2.2 attack
  range and the Tangler stays in PURSUIT, which is the state the lock rule is defined for. The lock
  then moves to the new runner within one poll (~0.5s). Asserted in `--test-tangler`.
  **Superseded note, kept for the ruled-out list:** gating re-lock candidacy on
  `is_detection_pair_currently_visible(detector, other)`. It reads true before acquisition and false
  for every body from the first tick AFTER the enemy acquires — including the acquired target itself —
  so the lock freezes on whoever was seen first and never jumps to the runner, which is the whole
  decoy play. Measured, and NOT explained by the detector's `detection_targets` (still lists both),
  target concealment (0), shelter, or dodge. Next attempt: stop using that predicate for re-targeting;
  do the enemy's own range + concealment check, or find what the base uses to hold a target through
  `pursuit`.
  **Harness traps that cost four runs:** `set_running` silently refuses without `stamina` in the
  registered stats; in a `SceneTree` script `_ready` does not fire until the tree processes, so
  `await process_frame` before `activate()`; `_has_detection_los` needs `gs.grid`, so a gridless probe
  reports nothing visible while prediction-based acquisition still fires; `create_room` borders are
  walls, so place bodies in the interior.

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
| **1 — one new class each** | #1 Ferrule, #2 Spiker, #3 Tangler | one enemy FSM per chunk; all counters already ship |
| **2 — one class + a system** | #12 Harvest (cache-carry state), #10 Census Night (Hushbloom), #4 Windup Window (Flare, party-facing only) | a small state or object on top of one class |
| **3 — the reveal system** | #7 Cable Run, #16 The Wall That Walks | CloakedEnemy + reveal-consumption (build once, use twice) |
| **4 — the enemy-on-enemy edge** | #8 self-solving gate, #9 flare ignition (pack variant), #14 ascent | the shared "large" unlock; opens a tier of combo cards |
| **stretch (compose tier 1–4)** | #13 Heist, #14 Ascent, #15 Curfew | chain the above with typed handshakes + connect-backs |

**Do NOT** resolve the 6 OPEN matrix cells (Climbvine×Hidras, Climbvine×Redactors,
Forget-me-nots×{Sapscraps, Ferrules, Hidras, Crusts}) — director-only. #14 (Climbvine ascent) and #16
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

---

## Port-model fragments (composition-first — ports, gaps, configurations)

Drafted 2026-08-06 across four lenses (gravity / ecology / supply / watchers) against
`FRAGMENT_COMPOSITION_MODEL.md`, then put through the same two-auditor adversarial pass this document
uses — an **ecology-canon** checker and a **design-law + port-coherence** checker, twice over. Every
correction both checkers raised is folded in below; nothing here still carries a flagged canon error.
Read these as *port declarations first, set pieces second* — an entry earns its number by what its
ports let it plug into.

**Ranking criterion (why they are in this order, and it is not "which is the nicest level"):**
1. **Admissible-set fanout** — how many *unrelated* suppliers or consumers its ports type-check
   against without either side knowing what the other is.
2. **Scarcity of the port class it trades in** — absorbers, directed vertical supply, and checkable
   broadcast *bands* are the classes the economy layer is starved of; another gating latch is not.
3. **Structural demand** — how much shape its inputs force onto the composition (two arrivals at two
   heights, a shared lift budget) rather than just consuming what happens to be nearby.
4. **Countability** — whether its quantities are things the aggregate check can actually sum, or prose.

**SINKS, called out up front, because the model is short of them:** **#20 Wallow Sump** (bodies,
throughput bounded by a digestion duty cycle) and **#21 Scanned Plaza** (one enforcement body,
permanently) are the only true body-absorbers here. **#28** is a sink for a *timed consumable*, not
for bodies. **#24 Cache Row is explicitly NOT a sink** — it takes a pursuit in and hands a dispersed
body back out, net zero, and is labelled a BANK for exactly that reason.

---

### 17. Cover Slots on a Watched Crossing
- **HOOK:** A rooted **Spiker** holds a visible connection and damages only if that connection
  survives its full delay — so the crossing is a *supply* problem, not an evasion one. You need bodies
  standing on the line, spaced so no exposed gap between consecutive shadows outlasts the delay at
  walking speed. The fragment is indifferent to *which* bodies.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | `occluding_mass` (height ≥ h_i at slot i) | IN | 2 (rung-dependent) | gating | exclusive | lateral (pushed) or from above (`gravity`, one-way) |
  | `pedestal_lift` | IN | 1 | gating | exclusive | from below |
  | `concealment(medium)` — Scarpet bed | IN | 1 | gating | broadcast | lateral |
  | `tight_hide` — Capbage, level state | IN | 1 | gating | exclusive | lateral |
  | crossing open while the spacing contract holds | OUT | 1 | gating | broadcast | lateral / upward, two-way |
  | discharge cadence (`info`) | OUT | 1 | gating | broadcast | ambient, radial from the plinth |
  | drawn **Tangler** (feed-the-line only) + a `lure` leaking channel | OUT | 1 | pressure | exclusive | lateral out, `ground_fauna` |
  | released occluders, re-deliverable | OUT | 2 | gating | exclusive | lateral onward — **horizontal config only** |

  The geometry lives on the **slot**, not on the body: each slot i publishes a precomputed
  (required height h_i, guaranteed shadow L_i) from the authored plinth height and span, so the port
  demands only "a body of height ≥ h_i at slot i" and `max exposed gap < delay × walk speed` is a
  per-rung assert the local proof re-runs. **Scarpet is not an occluder** — it is CONCEAL_MEDIUM
  iron-dead masking that breaks the *lock* at outer range only (roster L31), and may never fill a
  spacing slot. Capbage keeps its own verb: tight hide and recovery anchor, count 1.
- **GAPS:** slot run (crossing axis, {1,2,4} slots); plinth (levels {0,1,2} — raising it raises h and
  switches the lift input on); crossing span ({2,5,8} cells) — may be an authored body **or** a gap
  another fragment fills.
- **CONFIGS:** ground plinth (h=1, lift count 0, span 8, one occluder — the teaching config) ·
  two slots raised (default) · long run (span 22, three occluders, or two plus one eaten discharge) ·
  shortened fuse (delay 1.6 s — same bodies no longer suffice; a pure ramp knob) · two roots (crossed
  segments, shadows stop coinciding) · feed the line (let a connection mature to *export* a Tangler) ·
  vertical dropped occlusion.
- **ORIENTATION:** Horizontal it is a *lender* of mass (occluders push onward afterwards). Vertical the
  turret roots below and watches an ascent, delivery is one-way, the released-occluders output
  disappears and the mass is **consumed** — and the drop must be actuated by an autonomous supplier
  (a basin release, a timed dropper) or a one-way link the party already earned, never by a member
  standing above the ascent that is itself the gate.
- **PAIR:** Aster reads the connection delay and the post-discharge recovery gap — the arithmetic that
  turns span × walk speed into a required count and spacing. Peris reads which slot cells hold what:
  Capbage slots are **level state** (tended across shelter cycles, or bloomed at a Client-Bed Tending
  Station where the species is bed-determined and read, never chosen) — a seed costs multiple in-game
  days, so nothing here is manufactured in-run. Nobody holds a station; the occluders are placed.
- **FAIL:** Eating a full discharge is the cheap solve at a worse price — damage, then the Spiker's
  recovery gap leaves the crossing briefly free. Every slot already filled stays filled.
- **BUILD:** Push system ships (crate-vs-crate planning, ghost, supersede), inter-level links ship. **The
  Spiker is unbuilt** — this fragment *is* the register's own "Spiker + movable cover" first slice.
  New: an **occlusion query** (does a body of height h at cell C break the plinth→target segment)
  resolved against dynamic bodies on the **scheduler tick**, never per frame. Canon note for the
  feed-the-line config: a Tangler grapples the Spiker and propagates tau, and a tau-seeded Spiker
  *eventually collapses* (GDD §7.9) — a slow ecological outcome, not a crossing-scale clear, so even
  with the inter-enemy matrix built the turret is not removed within a run; many Tanglers die crossing
  an exposed Spiker corridor (§7.8), and a regularly-firing Spiker's corridor is canonically quiet of
  other enemies, which caps what ambient pressure the long-run configs may assume. Reserve "unravel"
  for a Candid zone acting on a Tangler.
- **WHY IT COMPOSES:** the universal *consumer* for every "delivers a body or a surface" output in the
  catalog — type-agnostic about the supplier, ruthlessly specific about the geometry — and it shares
  the `pedestal_lift` port with the director's seed fragment, so the two create a **countable
  scarcity** rather than a thematic rhyme.

### 18. The Drop Gallery
- **HOOK:** A gallery runs above a floor too far below to climb back to. Everything the floor crossing
  needs goes through a mouth in the gallery floor before anyone descends, aimed at a cell and released
  on a tick chosen by someone standing where the danger is not. The party splits along a one-way edge,
  and the only help that crosses it falls.
- **PORTS:** the fragment's real demand is a **boundary signature, not a port pair** — rim openness at
  **two levels** (`{level: upper, faces:[lateral, above]}` and `{level: lower, faces:[lateral]}`), plus
  a one-way `gravity`-directed vertical rim with no return face, so the directed reachability query
  sees the valve.

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | carried consumables (armed pod, vine, Flure stock, iron mass) | IN | 2 (0 under TOOLS GROWN HERE) | gating | exclusive | lateral, at the gallery level |
  | delivered `surface`/anchor (a vine anchor set at the lower level) | OUT | 1 | gating | exclusive | from above, one-way — the **timeless** export |
  | relocated resident (`fauna_body`) | OUT | 1 | pressure | exclusive | lateral, lower level, `ground_fauna` |

  The **pod delivery is an internal affordance, not a cross-composition supply** — the aura is centred
  on the *carrier*, the 30–45 s clock starts when a warm hand closes on it (so the drop eats the
  window), and the floor member must pick it up and carry it. A pod emitting where it lies is
  **DERIVED** from the Capbage cache line ("the pod emerges still emitting and the gas releases into
  the corridor") and is a named build item, not base canon.
- **GAPS:** lower room floor ({4,9,14} cells, hazard ceiling: max enemies, max conceal tier, max water
  level) · gallery run ({3,6,10} cells — pressure here must be an *upper*-level hazard: a Crust band, a
  rotted catwalk, a Spiker with line of sight along the gallery) · vertical separation ({1,2,3} levels).
  **The separation rung does not change blindness** — one default level is 4.0 world Y against a 2.0
  detection band, so the two floors are mutually blind at every rung and the fragment gets that premise
  from the engine for free. The rung buys **descent cost** (the chute's traversal duration) and
  **nested content** in the shaft.
- **CONFIGS:** tools carried in (the port is live — a real consumer in the resource economy) · tools
  grown here (Peris tends a Gasafoetida cluster on the damp corner; the site binds to `body`, count 0) ·
  solid gallery floor / gallery floor is a gap · **Candid lane** (then **no Capbage anywhere in the
  room** — colonies smother them and deny the substrate; the break is the chute or a Scarpet mat at
  CONCEAL_MEDIUM) · **Capbage recovery** (wild: 2–3 s seal, may open early; or tended across cycles:
  1–2 s, reads the environment reliably — pick one and pay for it) · enemy as output (relocated) ·
  enemy as input (a Flure parks it under the gallery — **CANON against Sapscraps only**; DERIVED
  against Ferrules and Hidras, whose roster counters are cross-on-the-beat / break-the-sightline /
  douse, or a *carried* Gasafoetida pod, which is the CANON Ferrule tool).
- **ORIENTATION:** Vertical-primary and it should stay that way. The horizontal sibling (a grated slot
  in a sealed wall) has to *author* both the mutual blindness and the one-wayness as rules, which is
  exactly the invented-mechanism trap; reach for it only where a level has no vertical separation to
  spend.
- **PAIR:** Either member takes the gallery, and the choice is the plan. Peris above: she charges the
  pod and harvests the vine, and sites where a dropped tool covers the lane — but Aster crosses without
  her flora read. Aster above: he calls the tick from overwatch (a Naturalizer's route period, a
  Ferrule's linger interval, the pod's burn-down) but the floor member has no tending register. The
  aura renders as a **visible gas volume in the world**, legible to anyone — no coverage readout on
  Peris's overlay.
- **FAIL:** A mis-aimed drop is simply spent. The floor member breaks to cover (Capbage or Scarpet per
  the config) while the gallery member repositions to the second mouth. With both tools gone the party
  regroups below and crosses slowly with the resident live — one section of the day clock, mobile
  throughout, no stat change. Pairing rule: with a **Naturalizer** resident, a Candid mat is the SOLVE
  lane (scan-blind, priced in floor DoT), never added pressure — and no delivered pod repels an
  immobile colony, which cannot flee.
- **BUILD:** Cheapest of the vertical set. Ships: multi-level grid + links, the detection vertical band,
  **CrawlTunnel** (authored path through grid-forbidden geometry, concealed, slowed, one-at-a-time
  queueing — the chute with no new class), concealment tiers, Flure, outline/click grammar,
  PathRenderManager. New: **DropMouth** (a released item that commits its landing cell and tick
  *analytically* at release); the **Gasafoetida pod class** (unbuilt in every form); one lower-floor
  resident (Naturalizer patrol is real today; a Ferrule FSM is shared with #27). Do not extend
  `ClimbvineReturn` downward — its lack of an upper→lower verb is a deliberate decision.
- **WHY IT COMPOSES:** it demands **two arrivals at two different heights**, which is the single most
  productive constraint in this set — it forces a composition to reach one region twice at two levels,
  which is what turns a stack of rooms into real vertical topology. And it is a pure valve: everything
  past it is downstream in the strong sense, so the difficulty bound can total unabsorbed pressure over
  a region the party can never re-enter.

### 19. Slope Nursery
- **HOOK:** Climbvine grows only on inclines, and this canted terrace is the only slope on the leg.
  Each tended plant ripens one vine per day rollover and a body carries two, so the drop off the lip is
  not gated by skill — it is gated by how many days you spent planting before you arrived.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | a **day rollover** source reachable upstream | IN | — (predicate) | gating | broadcast | ambient / temporal, priced against the day clock |
  | one contiguous inclined face ≥ N cells | IN | — (predicate) | gating | broadcast | lateral or from below |
  | iron decoy or Scarpet paving on the tending apron | IN | 1 | pressure (`surplus_ok`) | broadcast | lateral |
  | harvested Climbvine vine (hand-slot item) | OUT | **per rung**: 1/2/3/4 plants → 1/2/3/4 per ripening | gating | exclusive | lateral, `carried` |
  | one-way descent, terrace lip → floor below | OUT | 1 | gating | broadcast | from above, one-way |
  | naturally-grown Climbvine connect-back | OUT | 1 | gating | broadcast | from below, upward — the P11 floor |

  **Ripening rides the day rollover, not a rest.** `_advance_flora_day` advances every tended growth on
  *any* rollover — the running clock's and the night skip's — so the currency is a day waited, priced
  by P16, and a rest-gated variant is a **build**, not a description. The rest cycle itself is a shared
  depletable budget and is therefore not a port. A spent vine is a **persistent but revertible** link
  (player-planted Climbvine reverts on a Peris-death runeback); only the naturally-grown specimen is
  world geometry, so no composition may make a spent vine its sole guarantee of reachability. Vine
  spend carries a precondition: the anchor pair must be `carried`-reachable **without traversing the
  link the vine repairs**.
- **GAPS:** landing floor under the drop ({1,2,3} levels — depth prices both the commitment and the
  climb-back) · the slope face ({3,6,9} cells → the plant count, hence the yield) · the tending apron
  (1–3 cells offset, bounded by tending reach; hazard ceiling set so the pair can hold it).
- **CONFIGS:** solvent (3 plants, shelter near, decoy sited — the canonical Climbvine first appearance
  in the **Plumbing Power Project**, shelters 2–3, where the *natural* specimen is the return and a
  *planted* vine is the stock; naturals can never be harvested) · one-face (1 plant, 1 vine — the
  composition must choose which downstream demand gets it) · mixed row (naturals hang beside tended:
  weathered/dark-rootlet vs fresh/pale-rootlet is a **public** read, so the lesson is *which of your own
  plants is stressed and will pay nothing today*) · camped lip (a **Ferrule** on the drop mouth — a real
  chokepoint every body crosses, its roster niche — with the apron inside its flare arc, so the
  voluntary hold is deliberate lingering in a breach it owns) · coupling site (the vine is spent as a
  coupling instead of a ratline — feeds #25) · cellar (inverted; only legal if the descent is free and
  fall-safe and the natural connect-back is restated in the inverted frame — it is the P11 output and
  may never vanish with a config).
- **ORIENTATION:** Vertical by default; the coupling-site config is the horizontal realization and the
  economy is byte-identical (one vine per ripening, two hand slots, finite slope).
- **PAIR:** Peris is `FLORA_TENDER` in code — only her hands plant, tend and harvest, and her exclusive
  *read* is plant **state** (healthy / dormant / stressed / dying, by colour, scent, touch), i.e. which
  plant will actually pay today. Aster times the loiter drift between holds and does the dusk
  arithmetic. **Named counter-cheese:** Scarpet paving the apron makes idle/foraging Sapscraps route
  around it (CANON) — that is the legitimate *slow* solve, priced against the day clock, versus the
  fast Flure solve.
- **FAIL:** A broken hold drops the plant to stressed — it pays nothing this cycle and recovers by the
  next. A fall lands the member on the floor below, mobile, no stat change; the natural vine is the
  climb back and its duration scales with depth.
- **BUILD:** **Ships, and the ledger was overstated elsewhere:** `command_tend_flora` /
  `_advance_flora_day` / `command_harvest_flora` are the whole tend→ripen→harvest loop, Peris-gated,
  replay-safe and night-skip aware; plus the item runtime with a 2-slot hand cap, `flure.gd`,
  `scarpet.gd`, `add/remove_inter_level_link`, shelter rest. **New:** the Climbvine seed's
  `harvest_item_type` authoring; the slope-cell planting predicate; the **spend transaction**
  (vine → `add_inter_level_link` at an authored anchor pair, with save/replay state); the
  tended-vs-natural refuse-harvest flag.
- **WHY IT COMPOSES:** its output is not a solution, it is **currency with a direction** — the general
  repair for directed reachability, countable as `days × plants ≥ two-way links demanded`, with the
  reachability precondition above keeping the check honest.

### 20. Wallow Sump — **SINK**
- **HOOK:** A narrow ledge crosses a decommissioned extraction bore, and something slow lives in the
  water at the bottom. Everything sent over the lip is gone for good, and a **Ferrule** camped on the
  lip makes hovering there to decide the most expensive thing you can do.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | `water_level` (band `[drained..flooded]`) | IN | — (band) | gating | broadcast | ambient, from a parent basin/valve |
  | delivered body (`fauna_body`) | IN | rate-bounded | pressure | exclusive | **delivery** `gravity` from above; **absorption** matched only by a same-level `ground_fauna` claim at the landing |
  | one walkable span to the far lip | IN | 1 | gating | exclusive | lateral, or from above (then one-way) |
  | standing siderophore draw (a tended Flure field) | IN | 1 | pressure | broadcast | lateral |
  | digestion freeze window (`clock_phase`) | OUT | — (band) | gating | broadcast | in-plane, read by anything on the bore floor |
  | leak — a float-borne resident on your floor | OUT | 1 | pressure | exclusive | lateral, `ground_fauna` |

  **Absorption is unbounded in count but SERIALIZED in time** — a Meeb has no stomach, it has a duty
  cycle: each engulf locks it in place for the digestion span, then it drifts on (GDD §7.4). The sink's
  throughput bound is that freeze cycle, which is a far better thing for a downstream fragment to
  negotiate against than a capacity number. The pump's three-state cycle (**DRAINED → MID → FLOODED,
  wrapping**) is the shipped control; MID seals the pit and drops the ledge link, so it delivers
  neither the under-route nor the lift — that dead beat is what the Ferrule's linger-strike prices.
  Because level is one broadcast band, a composition that nests an under-route child *and* a
  float-lift child under one pump fails `[economy/broadcast-band-empty]` instead of silently
  double-counting.
- **GAPS:** the bore floor / under-route (3–9 cells of passage, playable with the resident as ambient
  pressure and the water level as an externally-owned clock) · the delivery shaft ({1,2,3} levels — the
  socket a gravity source drops into) · the lip shelf (a draw or bait pocket; a **wild Capbage** here is
  the tight-tier break for a party stranded with a live body on the wrong side) · the inclined bore wall
  (a naturally-growing Sloperope return — the only surface Climbvine grows on).
- **CONFIGS:** grated lip (selective sink; the party stands safe on the grate) · open mouth (symmetric
  hazard, higher throughput) · **pen-and-flood** (the resident is the sump's own penned roamer and
  removal is by flooding — placeable today, no quiet-interval output) · Meeb resident (the engulf-freeze
  window; needs the inter-enemy matrix) · float armed / absent · polarity flipped (the penned body walks
  out **through the DRAINED under-route**, whose cells are unblocked — never up the service housing,
  which is a 0.6 m evidence box) · lip camped / clear.
- **ORIENTATION:** Vertical natively — the one-wayness *is* gravity, which is what makes it an honest
  terminal sink. The horizontal variant (a flooded side-bay off a corridor, lip as curb) is a **leaky**
  sink: bodies wander back over the curb, absorption becomes probabilistic, and the float rises to a
  step rather than a floor.
- **PAIR:** Aster reads the pump's schedule and the digestion span, so the party knows whether the
  under-route crossing fits inside one freeze; he also calls the Ferrule's linger beat. Peris tends the
  **standing** Flure field on the lip shelf so the draw crosses the mouth rather than the ledge (a
  Flure is a persistent broadcast decoy, with a decaying tail even after the plant dies — CANON against
  **Sapscraps**; DERIVED against Ferrules and Hidras, and `flure.gd` has no species allowlist, so
  eligibility is scenario policy) and sites the Scarpet siding so idle and foraging siderophores route
  **around** it, steering the approach lane over the mouth. Scarpet only degrades an *active* pursuit's
  signal over time — a committed chaser still has to be walked to the lip; the instant contact break is
  the Capbage.
- **FAIL:** DRAINED, the character lands on the bore floor and pays the climb — one pump cycle of day
  clock, sharing the floor with a slow resident whose counter is to sidestep its line. FLOODED, the fall
  is a Channel-grammar sweep to the bore rim landing, set down **mobile, with no stat change**.
- **BUILD:** Ships: the extraction-bore sump object (`_spawn_sump`) with its reversible pump, float→ledge
  inter-level link, service housing and its own penned enemy that drowns at FLOOD; `remove_inter_level_link`;
  Flure, Sapscrap, Scarpet, Capbage, `climbvine_return.gd`, the Channel sweep, search-to-last-known.
  **New, first-class, even for pen-and-flood:** occupancy-based drowning — the shipped commit damages
  only the sump's *own* pen, so until every character on `pit_cells` is resolved the sump is a
  self-contained set piece with no input port. Also: a **`gravity` mobility predicate for `fauna_body`**
  plus **enemy one-way descent across a link** (`enemy.gd` never calls `command_move_cross_level`) —
  without both, a body matched into the shaft balances arithmetically and deadlocks in play. The lift
  link is two-way today; declaring it one-way needs a directional link kind. Only the Meeb configuration
  touches the inter-enemy matrix.
- **WHY IT COMPOSES:** it is the port-complement of the director's seed fragment — that fragment outputs
  one enemy and inputs a pedestal lift; this one absorbs bodies from above and delivers a lift from
  below — so the two clip together with nothing left over. Sinks are the scarce kind; this is the floor
  of a stack, the place a composition's accumulated surplus terminates.

### 21. The Scanned Plaza That Keeps Its Patrol — **SINK (capacity 1)**
- **HOOK:** A fixed enforcement route never leaves its jurisdiction, so this plaza permanently absorbs
  one **Naturalizer**. **Crusts** have taken the walls, so the wall-hugging instinct is gone, and the
  only unscannable ground is a **Candid** mat that charges you health by the tick.
- **STAGING CORRECTION (load-bearing):** Naturalizer patrols *skip* colonized corridors, because their
  equipment stops working there (GDD §7.3). So the route walks **clean ground** — an elevated stack-top
  or a clean perimeter lane — and **scans across and down into** the colonized aisle, exactly as
  ECOLOGY_COMBOS Card 2 stages it. Placement invariant: **no mat cell may lie on the patrol's walked
  route.** The concealed lane is the roster's own bypass ("route through Candid air where its scan
  fails"), not a lane inside the patrol's footprint.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | enforcement body on a fixed route | IN | 1 | pressure | exclusive | lateral, **one-way in — absorbed for the run** |
  | scan-blind floor colony spanning the narrowest scanned width | IN | — (extent rung) | gating | broadcast | lateral spread |
  | `fauna_body(tangler)`, arriving **in pursuit of a party member** | IN | ≤1, unravel-lane config only | pressure | exclusive | lateral, `ground_fauna` |
  | concealed lane priced in hp/tick | OUT | 1 | gating | broadcast | lateral, two-way |
  | fauna-exclusion over the mat footprint | OUT | 1 | pressure | broadcast | ambient, radial |
  | the absorbed patrol's cadence, republished (`clock_phase`, with a **period band**) | OUT | 1 | **gating** | broadcast | ambient, to every fragment with sight of the floor |
  | released patrol (uncapped-advance config only) | OUT | 1 | pressure | exclusive | lateral out |

  **Honest capacity is 1.** Everything other than a led-in Tangler is *repelled to the plaza edge* —
  returned to the composition, not absorbed. Fauna exclusion is CANON (§7.3: Candid conditions are
  hostile to almost every other enemy type; Tangler-free per §7.9; siderophores read the corridor
  iron-dead); only the specific "re-anchors to the *edge*" claim stays DERIVED.
- **GAPS:** the mat ({2,5,10} cells, resizable on both axes — but **capped so the front can never reach
  the authored route**) · the open lane (the mat's complement, 1–5 cells; a timing fragment can give it
  a second clock) · the perimeter Crust band (4–16 cells).
- **CONFIGS:** one route, wide mat (teaching) · two routes (capacity 2; the republished output then
  carries **two periods**, so the band-intersection check can catch two consumers needing incompatible
  periods) · retreating mat / advancing mat (per **shelter cycle**, not run-time — the Scarpet-vs-Candid
  contest resolves over multiple in-game days, so a run inherits a rung and the run-time variable is
  only *which* rung) · **uncapped advance** (declared **capacity-destroying**: at full advance the
  patrol abandons the plaza and the released body becomes a declared output, never a silent leak) ·
  **unravel lane** (its own configuration, because leading a pursuer onto the mat is a *second* verb —
  redirect-aggression — and P8 is one verb per section) · perimeter route (needs a named igniter:
  Myke's Inflame, lit infrastructure such as the Ancourage fused-heat flare lane, or a flaming
  projectile; the bare pair cannot cast fire) · cloaked kin (a **Redactor** posted; the fragment becomes
  reveal-gated and inherits #23's cost).
- **ORIENTATION:** Horizontal primarily. Vertical is a scanned stairwell whose mat climbs the treads
  from a flooded sump below — extent measured in colonized landings, and the concealed lane becomes
  one-way down, so committing to it is committing to the descent.
- **PAIR:** Aster reads the patrol period and names how much open lane fits inside one sweep-away
  window — a fixed route is a deterministic beat, which is what lets a bare pair get a WHEN read with no
  specialist. Peris reads the front (bleached Candid flooring against tended Scarpet is world-visible,
  not overlay data) and her tending moves it between cycles. The crossover is measured: health on the
  mat versus daylight on the timed lane, both legible before committing.
- **FAIL:** Caught on the open lane, the canonical recovery is break to cover — and here cover **is** the
  mat, so failure routes you onto the expensive lane, costing health rather than the run. Low on health
  while on the mat, step off into the Scarpet margin (medium concealment, no DoT) and wait out a period.
  Adjacency of lane→mat→margin is a placement invariant.
- **BUILD:** Cheapest of the whole set. Ships: the Naturalizer subclass (fixed patrol, strike, hesitation
  zones, save authority), `candid_zone.gd` (DoT + CONCEAL_FULL scan-blindness), `scarpet.gd`, the
  concealment tick pattern that already runs in both `_process` and `headless_process`. New and small:
  the mat as a **resizable region with a per-cycle rung**, and exposing the patrol's cadence as a
  neighbour-readable port. New and genuinely unbuilt: terrain damage applied to **enemy** bodies for the
  unravel lane — counted against the same **P13 inter-enemy matrix** build, with its own FF-invariance
  test. Crusts are a placeholder: the base config greyboxes the perimeter as a closed wall-adjacent
  strip needing no Crust behaviour.
- **PRIOR ART:** this formalizes ECOLOGY_COMBOS Card 2 and #11's Candid shadow lane into ports; the
  new material is the **sink framing** and the republished-cadence output, not the HP-timer emergence.

### 22. Candid Mat Aperture
- **HOOK:** A Candid colony has taken the floor of a service corridor. Every body that wants through is
  squeezed into the one clean lane the colony has not claimed, and that lane narrows on the colony's own
  advance beat while the only thing that widens it is Peris out-competing the mat with Scarpet. You are
  setting, in real time, how wide a hole to leave in a wall that only you can walk through.
- **REFUSAL IS GRADED, NOT ABSOLUTE** — declare it per class: **HARD** (Tanglers route around; Naturalizer
  patrols skip colonized corridors), **SOFT** (siderophores have trouble navigating iron-dead gradients —
  density drops, it does not go to zero), **UNSTATED, needs a ruling** (Gnawers, Meebs). A boundary that
  hard-refuses two classes and merely thins three is a *better* composition operator than a wall.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | mobile enemy population at the mat's edge | IN | 3 (0 under CLOSED / MAT-AS-PEN) | pressure | exclusive (hard classes) / probabilistic (soft) | lateral |
  | tended flora inside the spread radius — **consumed permanently** | IN | 1 | pressure | exclusive | lateral, one-way |
  | metered enemy stream out of the lane's far mouth | OUT | 3 | pressure | exclusive | lateral, directed one-way |
  | enemy holding pool (CLOSED / MAT-AS-PEN only) | OUT | 3 | pressure | exclusive | stays here |
  | **scan-blind air** (Naturalizer scans fail) | OUT | 1 | gating | broadcast | ambient over the mat extent |
  | patrol-route truncation — **OPEN, director ruling required** | OUT | 1 | gating | broadcast | ambient over the **explicit cell set** of the truncated segment |

  Aperture start width is a **configuration axis (1–4 cells)**, not a port — a "banked from a previous
  shelter cycle" supply has no supplier inside the composition and could never be discharged. The
  party-facing damage floor is a **hazard ceiling** on the site (`dot_per_sec`), not an output; nobody
  declares an input for being hurt. The mat's flora consumption is declared as
  `consumes_flora_within: <radius>` so a critic can flag any *gating* flora supplier whose footprint
  intersects it; until that critic exists, restrict the flora-neighbour config to pressure-class
  suppliers.
- **GAPS:** the clean lane itself (cross-axis 1–4, run {4,8,12}) — the model's size-negotiation case at
  its purest, because the extent is a **live** variable a child negotiates against · the mat-interior
  island ({2,3,5} square; enemy-proof by construction, ringed by DoT) · the upstream mouth apron (the
  supplier site) · the ignition seat (outside the mat, so reaching it means leaving the scan-blind air).
  **Both interior sites are FLORA-EXCLUDED:** no Capbage, Hushbloom or Seefern child furniture — Candid
  zones deny the substrate and smother what is already there, and a colony kills Seefern outright.
  Scarpet is the one flora permitted, because contesting the colony is its canonical role.
- **CONFIGS:** aperture wide / single-file / closed · advance beat on (the fragment is a clock the level
  can price against) or off · **canopy present** (three strata — hyphal canopy, pseudohyphal chains,
  yeast carpet; fire burns the canopy down **a layer** per application) vs **carpet-only** (one stratum,
  one burn); regrowth is DERIVED from "a spreading colony", not quoted · fire-seated (a **named**
  directed flame: a lit vent or a held interlock) · **serotinous seat** (an ignited Gasafoetida cluster
  — an *uncontrolled* widen: 3–5 flaming pods on bouncing arcs that burn any tended flora in radius; a
  better fragment, because the widen becomes risky rather than free) · flora neighbour present/absent ·
  refusal polarity: mat-as-wall (default) or mat-as-pen.
- **ORIENTATION:** Horizontal natively — it is a floor colony, and the wall-hazard niche belongs to
  Crusts. Vertical is the mat on a stair landing so the aperture is a single tread and the DoT becomes
  **unavoidable** (no sidestep on a tread). Do **not** claim "pursuers won't follow you to height" as
  the payoff — enemies are strictly single-floor movers today, so that is the engine's shipped
  limitation, not this fragment's output.
- **PAIR:** Aster reads the advance beat — a cadence, his register — and names the last tick the lane is
  passable un-taxed. Peris is the **widen lever**: sustained Scarpet tending out-competes and retreats
  the colony, and `scarpet.gd` ships, so the throttle verb is exercisable with no fire system at all.
  She also knows which of her own tended flora the spread will take.
- **FAIL:** Stepping onto the mat is a damage tick, not a death — the failure mode is the fragment's own
  mechanic. If the aperture closes mid-lane you finish the crossing on the mat and arrive damaged and
  mobile. **Recovery anchor:** the mat's own scan-blind interior — a party that fails the crossing
  stands in it, unreadable, paying health per second but safe from enforcement, and re-approaches.
- **BUILD:** `candid_zone.gd` ships (pale mat, CONCEAL_FULL scan-blindness, health drain, loader
  concealment pass); Naturalizer with its scheduler-polled registered-zone system ships; `scarpet.gd`
  ships. **New, and it *is* the fragment: enemy region refusal** — a per-enemy forbidden-cell mask
  consulted by the mover and by roam's wall-bounce (enemies have roam radius, patrol routes and pursuit,
  but no "will not enter these cells"). Also: the advance beat as colony cells claimed on a scheduler
  cadence with the aperture re-walked on the grid (a composition of the shipped water-level re-walk).
  **Ship on scan-blind alone**; hold the route-truncation output until the director rules. Nothing here
  kills anything, so the inter-enemy matrix is not required.
- **WHY IT COMPOSES:** it transforms the **shape** of enemy flow rather than its quantity, and shape is
  what makes a small sink sufficient — a capacity-1 absorber fails against a mob and succeeds against a
  single-file queue. It has **zero gating inputs**, so it can be dropped into an over-supplied
  composition without creating new demand; its only cost is what its spread eats.

### 23. The Light You Grow on Cleared Ground — reveal SOURCE
- **HOOK:** Everything worth seeing in this bay is invisible, and the only thing that can see it is a
  plant grown standing still, in the open, on a schedule somebody else's patrol sets. The glow radius is
  the puzzle's size dial, and every band is another held beat with a body pinned at a known cell.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | growth substrate — a **non-colonized** strip ≥ 3 contiguous cells | IN | 1 | gating | exclusive | lateral |
  | `recovery_anchor` (Scarpet bed) | IN | 1 | gating | broadcast | lateral, adjacent |
  | `tight_hide` (Capbage — **one character per head**) | IN | = members exposed at the station | gating | **exclusive** | lateral, adjacent |
  | scan/patrol cadence (`clock_phase`) | IN | — (band) | gating | broadcast | ambient |
  | transiting enforcement body | IN | 0–1 | pressure | exclusive | lateral, `ground_fauna` |
  | rooted **Spiker** sightline crossing the station | IN | 0–1 | pressure | broadcast | ambient, **immobile — never transits** |
  | **reveal volume** (light-scatter / material mismatch: Hidras, early-stage Crusts, Redactors, a creeping Tangler — one director-ruled mechanism) | OUT | 1 | gating | broadcast | radial in-plane; **downward and one-way** in the lantern-well config |

  Exposure is **not a port** — it is a declared *leaking channel* (a detection fan of radius r at the
  station cell), checked by the global safe-passage flood; a broadcast pressure port would contribute
  nothing to the difficulty bound. Sterility is **not** a bar on Seefern: the Dead-Zone cultivar
  establishes, runs hot, glows cold blue-white, smells acrid, dies within about a day, and reveals at a
  **smaller radius**. The real substrate constraint is Candid colonization, which **smothers and kills**
  Seefern over days.
- **BANDS, anchored on the canon state ladder:** band 3 = healthy (steady teal-green — canonically the
  widest activated zone of any flora), band 2 = partially tended, band 1 = **stressed**, whose canon tell
  is *patchy uneven dimming with unlit stems*. So an interrupted hold does not shrink the disc — it
  makes the volume **ragged and hole-punched**, and a child's "covers my footprint" check fails on the
  holes. That is a better failure than a clean radius step.
- **GAPS:** the lit interior (radius/shaft-depth rungs 3/5/8 across bands — the child declares only "I
  require reveal covering my footprint", so a Redactor posting, a Hidra cabling run, an early Crust band
  or a creeping Tangler drop into the identical socket) · the tender's standing ground (1–3 cells offset)
  · the substrate strip ({3,6,9} cells).
- **CONFIGS:** planted bay (default) · found lamp (a natural specimen at band 2 — no substrate input, no
  hold, radius **fixed** at 5) · dead-zone burn (capped at band 1, cold blue-white, acrid, dead within a
  day, seed consumed — so every reveal-gated child inherits a deadline it did not author) · contested
  substrate (the Scarpet-vs-Candid contest is a **between-run** parameter fixing the strip at entry; the
  only in-run decay is the plant's own stress band) · lantern well · **reveal port flipped to INPUT**
  (no substrate; the bay hosts a reveal-gated child and becomes a pure consumer — the seed fragment's
  polarity flip realized in the perception economy).
- **ORIENTATION:** Horizontal, the tender inside the volume they are growing. Vertical is the lantern
  well — light falls down a shaft, so the person paying the exposure is never the person using the
  light. **Requirement, not flavour:** the well must carry a two-way link traversable inside one growth
  beat (or the carry-to-cover recovery is unreachable), and the cadence source must sit on the
  **tender's** floor — cross-floor detection is dead beyond the vertical band, so Aster cannot read a
  patrol he cannot see. Only the light falls; never the read, never the rescue.
- **PAIR (and P12):** Peris **sites and seeds** the plant — a one-shot only she can do (`FLORA_TENDER` is
  code-gated) — but each growth **beat is a generic held station any surviving member can take**, on the
  wash-relay `ADVANCE_HELPER` / role-inheritance pattern. Without that split a downed Peris strands the
  bare pair on a fragment they cannot finish. Aster is the clock: a fixed route is a deterministic beat
  he names, and in the Spiker variant he reads the connection delay that bounds how long anyone can
  stand there. Peris's overlay surfaces **story only** here — the node joining her care network, with
  its dialogue trigger; the solvable information is the plant's visible growth band and the patrol's
  visible route.
- **FAIL:** Break a hold and the plant drops to stressed: the volume goes ragged, the child is no longer
  covered, and you re-tend a band — one growth cycle and a walk. A member the patrol commits to is driven
  off and downed, not erased; the party carries them into the adjacent hide and resumes at the lower band.
- **BUILD:** Ships: concealment tiers, `scarpet.gd`, `candid_zone.gd`, the Naturalizer, click-gated
  tending, the held-station pattern. **Not built, and it is the whole cost: the reveal system** —
  CloakedEnemy hidden-from-player state + a reveal **volume** + reveal consumption (the flora side is
  taxonomy data in `flora_species.gd`, with no enemy-side cloak state). Shared with the register's #7
  Cable Run and #16 The Wall That Walks — **build once, reused three times**. Specific to this fragment:
  the volume must be a **scheduler-derived banded radius**, not a per-frame light query; and level
  awareness for the lantern well. It does **not** rely on the inter-enemy edge; the canonical payoff
  where a revealed Redactor is engaged by the corridor's own fauna does, and is deliberately excluded —
  this fragment's output stops at visibility.
- **WHY IT COMPOSES:** it makes REVEAL a first-class broadcast supply with a **resizable extent**, so the
  parent never has to know what it is revealing, and it turns two existing consumer ideas in this
  register from set pieces into composable children.

### 24. Cache Row — a **BANK**, explicitly **not** a sink
- **HOOK:** A run of **Capbages** is both the only supply cache and the only tight hide on this leg, and
  a sealed head holds either your goods or a body, never both. Diving into a stocked head under pursuit
  throws whatever will not fit in your hands out onto the substrate, where it keeps behaving like itself.
- **NOT A SINK — say it in the ledger.** One pursuit in, one dispersed body out: it absorbs a *chase*
  and converts it into ambient roam that somebody downstream inherits. Net `fauna_body` is **zero**. A
  composition that books it as an absorber runs hotter than its check says. The one configuration that
  is a real absorber is **drown mouth**, where the row's approach ends in a shipped basin pen that
  drowns a penned enemy at HIGH.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | hand-carried consumables from upstream | IN | 4 | pressure | exclusive | lateral, **one-way in time** |
  | a pursuit that cannot be outrun on this geometry (**Gnawer pack, Meeb, Tangler** — *not* a Naturalizer, which walks a fixed route and lands a lethal strike) | IN | 1 | pressure (`surplus_ok`) | exclusive | lateral, `ground_fauna` |
  | banked supply, withdrawable on a later pass (1/WILD head, 2/TENDED) | OUT | 4 | gating | exclusive | lateral, deferred — **requires return-reachability from each consumer** |
  | ejected items on the substrate | OUT | 2 | pressure | exclusive | lateral (horizontal) / falls one-way (shaft) |
  | released, de-aggroed body | OUT | 1 | pressure | exclusive | lateral, `ground_fauna` |

  Hand-slot occupancy is a shared depletable budget → it lives in the configuration's **cost record**
  (3 of 4 occupied at the mouth), never in the port row.
- **GAPS:** interval between heads ({2,4,8} cells, 2–5 heads — interval length is what makes re-banking
  expensive) · the approach lane (how many seconds you have to pick a head) · the substrate apron in
  front of one nominated head (a Candid mat → retrieval costs HP; a Channel → the next beat carries them
  off; a spike strip).
- **CONFIGS:** **architectural row** (Act 1 / Zone 2 early — maintenance closets, alcoves, sealed doors
  as the tight tier, with **one** rare wild Capbage carrying the collision; a dense *row* of Capbages is
  Zone 2 **mid** at the earliest) · wild row (1 item, 2–3 s seal, may open early) · tended row (2 items,
  1–2 s, reads the environment accurately; set by how many shelter cycles Peris spent) · single head
  (**illegal with a pursuit present — require ≥2 heads whenever the pursuit port is live**) · found stock
  (a sealed head with a name label holds a body; without one it holds items) · beacon head (a germinated
  Flure inside — the head that should be safest is broadcasting iron) · **smothered row** (a *live*
  Candid colony still breaks the pursuit at an HP price, so it kills the **bank**, not the sink; a
  genuine pass-through needs the heads dead by heavy siderophore traffic degradation or by fire — Myke,
  not the bare pair) · shaft (heads staggered up levels — **needs a declared connect-back**, or the
  ejection is simply LOST, not "a descent you earn back") · drown mouth.
- **ORIENTATION:** Horizontal by default; the shaft config lifts the identical row onto stacked levels
  and only the *direction a mistake travels* changes — the cleanest demonstration that orientation is a
  configuration axis rather than a different fragment.
- **PAIR:** The public tells are public: head size and leaf-layer count, open-vs-sealed silhouette, seam
  luminescence, leaf colour for health, a white fungal mat for smothered, a name label for occupied.
  Peris's edge is **history and scent** — she knows which heads are tended because she tended them
  (code-gated), and she reads the germinated-Flure beacon by its metallic wet-iron scent. Aster reads
  how long the seal must hold before the pack's rescan times out and it disperses.
- **FAIL:** A panic dive into a stocked head ejects the overflow and seals you anyway — the hide *works*,
  the pursuit still breaks, you walk the next leg poor. Recovery is priced: wait out the disperse and
  pick the items back up, or spend the pod now emitting on the apron to walk back into its own cloud. A
  downed member is carried back to the previous interval (**body carry ships**).
- **BUILD:** Ships: `capbage.gd` (CONCEAL_FULL positional hide), the item runtime and 2-slot hands,
  `hushbloom.gd` v2, `flure.gd` + the flure-seed item type, `scarpet.gd`, `candid_zone.gd`,
  `spike_strip.gd`, Channel, and the pursuit-timeout→search→return disengage that already makes "seal and
  they disperse" real. **New:** the **cache on Capbage** (a 1-or-2 slot cavity with deposit/withdraw and
  the cache-vs-character collision — `capbage.gd` has no cache state at all); the tended/wild axis as
  real state; the per-item ejection behaviours (a pod keeps emitting, a Hushbloom fires on the jostle, a
  cached Flure seed germinates); and the Gasafoetida pod item, inherited from #28. Not required: the
  inter-enemy edge — the break is target-side concealment and the disperse is the shipped disengage.
- **WHY IT COMPOSES:** it separates supply from demand **in time**, so a source three fragments upstream
  can feed a sink two fragments downstream without the two ever touching — provided the withdrawal
  precondition holds.

### 25. The Counterweight Drum
- **HOOK:** A drum at the head of a well turns only while something is falling. Peris grows the vine that
  ties the drum to whatever else in the level turns, so a descent spends itself rotating that thing
  instead of just sinking. What goes down buys what goes up: the paired side rises exactly as far as the
  loaded side sinks.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | ballast — **configuration-selected, one mobility each** | IN | 1 | gating | exclusive | CARGO: `surface`/`carried`; SWARM: see below |
  | harvested Climbvine in a hand slot (1, or 2 under DOUBLE TIE) | IN | 1–2 | gating | exclusive | `carried`, lateral |
  | a tick-pure **phase provider** within tie span | IN | 1 | gating | broadcast | **ambient** — consumer inside provider's region |
  | one level of lift, delivered upward per descent | OUT | 1 | gating | exclusive | from below, one-way per charge |
  | parked/committed alignment (`clock_phase`, declared as a **band**; CUT collapses the band to a point) | OUT | 1 | gating | broadcast | ambient |
  | spent mass — **split by config**: `surface` (cargo, gating) *or* `fauna_body` (swarm, pressure) | OUT | 1 | see left | exclusive | cargo: `carried`; swarm: lateral at the **lower** level, `ground_fauna` |

  The effector is an **ambient** demand, not a socket: any provider exposing a tick-pure phase within tie
  span qualifies — the rotating pipe hub, a cell-shutter crank column, an ophanim ring rim, a coupled
  valve pair — so fanout is ≥4 and the economy layer resolves it by scope containment rather than
  adjacency. **SET_PIECES canon, corrected:** iron chunks are the **ballast**; a Flure-lured Sapscrap
  swarm is the **hoisted removal** (no kill), not the motor.
- **GAPS:** the drop well ({1,2,3,4} levels — descent duration *is* the difficulty dial, since it sets how
  much rotation one charge buys) · the tie run ({2,5,10} cells, hazard ceiling declared) · the ballast
  yard ({3,6,12} cells).
- **CONFIGS:** cargo as ballast (the natural neighbour of a gravity source) · **swarm as payload** (a
  Flure in the lowered cage draws the cluster in; iron on the paired side hoists them out of play —
  legal only against siderophores) · **cut to park** — and the park is **releasable**, following the
  built NUTECH ring brake (a second use releases, phase continuous), so no cut can brick a distant
  consumer · hold the coupling (reusable, but the tie is exposed: the canon anti-cheese is a
  Flure-herded siderophore swarm **bunching beside a planted Flare**, which trips it — Flares are inert
  until set off) · single tie / **double tie** (two effectors at a declared ratio, with the admissible
  set given as (alignment_A, alignment_B) **pairs** so the intersection check has something to intersect).
  *Party-as-ballast is cut* — it is the only configuration that pays in bodies, and it created a reunion
  obligation no port carried.
- **ORIENTATION:** Vertical is the scarce, compositional realization — gravity is the motor and the lift
  output is a genuine level gain, which is exactly the pedestal raise the seed fragment demands.
  Horizontal (a paddle in a Channel run, driven by a scheduled flood) recharges for free every flood
  period, so the ordering pressure evaporates and the "lift" degrades to a lateral haul that satisfies
  no pedestal input. Horizontal teaches; vertical composes.
- **PAIR:** Peris is the only one who can **tend and harvest** a Climbvine, so the coupling costs *her* a
  tend-and-harvest cycle; any carrier can then spend, tie or cut it at the drum. Aster names the tick at
  which a cut parks the effector on the alignment the party wants, and how much rotation this well's
  depth actually buys — every rotating effector in canon has a phase that is a pure function of the
  scheduler tick. A strained tie **visibly frays and creaks** — a diegetic public tell (P18), not an
  overlay readout.
- **FAIL:** Cutting on the wrong tick parks a useless alignment and spends the vine. Recovery: re-supply
  mass (a runback to the ballast yard, or another spilled load from upstream) and a second vine — one
  section of day clock plus one vine, no stat change. Soft-lock floors: the ballast yard always holds one
  more descent than the minimum solve, and **a battered inclined pitch on the well wall carries a
  naturally-growing, non-harvestable Sloperope** — Climbvine grows only on inclines, so nothing "hangs"
  in a vertical well; a vine spanning open space is a pre-**spent** ratline between two anchor bosses,
  not a specimen.
- **BUILD:** Ships: the rotating pipe hub and push wheel; ring phase as a pure function of the tick, the
  NUTECH brake detent, and analytically-predicted queued launch (guarded by `--test-projection-alignment`
  — the honesty standard a coupled phase must meet); Flure with its ecology law; the basin/sump
  committed-state pattern; multi-level links. **New:** **ClimbvineTie** — the canonical
  tie-between-rotating-surfaces verb, which must bind two phase sources at an authored ratio as a **pure
  function of the tick**, never an integrated per-frame rotation, or fast-forward invariance breaks;
  **CounterweightDrum** (paired rise/sink, scheduler-committed like BasinWater — the counterweight
  basket is a proposed, never-built set piece); and the plantable/harvestable Climbvine, shared with #19.
  Optional: the Flare FSM, only for the hold-the-coupling anti-cheese. No inter-enemy edge.
- **WHY IT COMPOSES:** it is the only piece in the vocabulary that converts a **descent into an ascent**,
  and it makes the vine supply a first-class currency — because it *consumes* Climbvine, a harvest
  fragment anywhere in the level becomes a countable source.

### 26. Toxo Bed in a Failed-Immunity Pocket
- **HOOK:** In a pocket the enforcement apparatus stopped visiting, a bed of **Toxos** is thriving:
  feeble, and hunted by everything healthy. A Flure moves iron-seekers directly and nothing else; a Toxo
  placed at a cell you choose moves the classes no Flure reaches directly.
- **TRANSPORT IS THE SHIPPED CARRY, NOT PURSUIT.** `downed_body_manager.gd` already implements
  Carry / Set down with a both-hands-free gate and an interaction zone that rides the body; retargeting
  it to a live fauna body is the build. The canon staging is **place/drop the Toxo as bait**, or **lead
  your own pursuer into the pocket** so the healthy-hunt takes it. Toxos do not follow you.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | enforcement-free interval over the **bed** | IN | 1 | **gating in the Naturalizer-facing config only; pressure otherwise** | broadcast | ambient, satisfiable **non-locally** |
  | a hunter within draw range | IN | 1 | pressure | **exclusive** | lateral, `ground_fauna` |
  | Toxo bait tokens, carried out (hands occupied) | OUT | 3 (scales with bed area) | pressure | exclusive | lateral, `carried` |
  | hunt-draw beacon at a chosen cell (declared as a **band**, radius/strength — no count) | OUT | — | pressure | broadcast | ambient |
  | patrol deviation window — **OPEN, director ruling required** | OUT | 1 | gating | exclusive | lateral, one-way in time |
  | leak — unbaited Toxos drifting out | OUT | 1 | pressure | exclusive | lateral, two-way |

  **Narrowed claim:** a Flure draws siderophores **directly**; the canon Meeb and Gnawer pulls exist only
  as *mediated second-order chains* through a Flure-concentrated siderophore cluster, which requires a
  siderophore population you may not have and lands the draw where the cluster forms rather than where
  you chose. This fragment's novelty is a **placeable direct pull**, and the Naturalizer — the one hunter
  no Flure chain reaches at all.
- **GAPS:** the bed floor (population scales with area — a low-stakes teaching site sitting inside a
  high-value economic node) · the draw run ({6,12,20} cells — a **carry** run, hands full, and the length
  is the difficulty knob) · the drop cell pocket · the deviation corridor (a gap that exists only for the
  window's duration — the temporal analogue of an extent).
- **CONFIGS:** bed sealed (deterministic supply, no leak) / bed open · **Naturalizer-facing** — the
  **drop cell** sits inside one authored patrol's detection while the **bed sits outside every live
  route**, because Toxos in Naturalizer territory lose fast · Gnawer-facing · Meeb-facing (the feed line
  into #20) · polarity flipped (the pocket as **sink**: lead a pursuer here to be taken by what answers
  the resident draw) · dressing: Candid-lit (the interval comes from an upstream mat) or Dead Zone.
- **ORIENTATION:** Horizontal. **The vertical realization is BLOCKED**, and honestly: hunters cannot
  descend inter-level links and a Toxo cannot be walked up one (`enemy.gd` has no cross-level movement),
  so "same ports, inverted economics" would certify a hole nothing can enter or leave. Either add enemy
  link traversal as a named build and mark the config blocked on it, or make the vertical a **party-side
  one-way drop** — the party commits, the fauna economy stays on one floor.
- **PAIR:** Aster reads the authored route and its return tick, so he can say how long a deviation window
  really lasts and whether the carry run is affordable. Peris reads **where the bed is** — the extent of
  the pocket where nothing grows, the silence of flora being louder than any readout — and tends the
  Capbage at the drop cell. **Flora sites must lie outside the failed-immunity extent**; in the Dead-Zone
  dressing the only flora she can field inside is cultivated Seefern at about a day's life, which is a
  nice priced read rather than a contradiction. Break-contact, where the config needs one, is **Capbage
  only** — Scarpet masks iron and metabolic signatures, and a Toxo is tracked by neither.
- **FAIL:** The bait is feeble, so the ordinary worst case is chip damage and a walk back for another
  body. The instructive failure: a hunter answers **early**, mid-carry, and the party is between a
  predator and its meal — set the bait down and step behind the Capbage, and the hunter takes the Toxo.
  The bed regrows in a pocket nothing hunts, so supply is renewable at the price of day clock.
- **BUILD:** Ships: the whole **Flure lure transaction** (activation nonce, lured state, settle/park,
  resolver, its own state authority) — the Toxo bed is *the same mechanism with a different eligible-class
  list*, which is the honest framing; the Naturalizer with its scheduler-polled zone system (the
  deviation extends exactly that machinery, as an inserted waypoint plus a scheduled return tick);
  search-to-last-known; Capbage; `candid_zone.gd`; the carry. **New:** a Toxos class (the cheapest fauna
  on the roster); the deviate-and-return behaviour, declared as a countable output; the eligible-class
  extension with the ecology law kept explicit; Gnawer and Meeb classes for the respective facings.
  **The split to be honest about:** the draw and the deviation work **without** the inter-enemy matrix —
  the hunter comes to the cell and mills there, which is most of the compositional value and is playable
  now — but the actual **consumption** of the token is enemy-on-enemy and does not exist, so without it
  the draw never decays and the token count never depletes.

### 27. The Hopper Stair
- **HOOK:** A gantry of loaded hoppers hangs over a floor the party cannot walk. Pulling a latch spills
  its stock into the void, and where it lands it becomes surface. The second latch sits on a stub the
  gantry does not reach — you get there only by descending, crossing the first spill, and climbing that
  spill's own scree ramp. The order of spilling *is* the crossing.
- **GEOMETRY, PINNED:** there is **no catwalk between the two latches** (a walkable run between them
  would delete the ordering constraint entirely, which is the whole fragment). The **Ferrule camps the
  descent mouth** it now guards.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | arrival at the gantry level | IN | — | boundary signature (rim openness at the upper level) | — | from below or lateral, top only |
  | hopper stock | IN | **0 — authored body** | — | — | — |
  | restock (belt line, magnet hoist) | IN | 1 | pressure, `surplus_ok` | exclusive | lateral — absence downgrades the fragment from re-entrant to one-shot, it does not error |
  | spilled load pad — walkable cells at the landing | OUT | 2 | gating | exclusive | from above, one-way — **internal affordance** (see below) |
  | scree cone: an inclined surface **plus a runtime inter-level link** | OUT | 1 | gating | **exclusive**, availability `after_own_gates` | below, one-way |
  | "a spill has fired here" (`info`) | OUT | 1 | gating | broadcast | ambient |

  **The upward-return input is deleted:** the built silo already registers its scree cone as a runtime
  climbable ramp (`ramp_cell` / `ramp_to_level`), so the return is internal, needs no vine, no hand slot
  and no ripening — which also removes this fragment's Climbvine dependency entirely. **The scree is
  exclusive, not broadcast** — a cone is terrain another fragment consumes, not a state predicate.
  **One clock only:** the Ferrule's linger interval; the Sapscrap pad-strip commit fires at a fixed
  integer multiple of it, so Aster's single read names both. The Crust wall band is cut.
  **The enemy-output port is deleted** and canon kept: the shipped silo **buries** whatever stands in the
  spill zone. That also removes the gravity-vs-`ground_fauna` deadlock the shed body would have created.
- **GAPS:** the drop shaft ({1,2,3} levels, hazard ceiling declared) · the landing floor ({4,9,16} cells)
  — solid (spills are shortcuts, wrong order costs time only: the teaching form) or a gap another
  fragment fills (spills are the only footing: the exam form).
- **CONFIGS:** solid landing / void landing · single hopper (the atom: a pure downward source, one gating
  output) / twin hopper (ordering exists — the authored default) · **decaying pads** (Sapscraps strip an
  unattended pad on the derived commit; the pad is then an *internal* affordance and may not be exported
  — the economy layer has no time axis and cannot see a supply expire) vs **stable pads** (no decay; the
  pads become a genuine export that can discharge another fragment's `occluding_mass` or platform input)
  · enemy as input (an upstream fragment delivers a Sapscrap cluster to the gantry, drawn to stocked
  iron; spilling becomes a race) · sweep variant (a declared **kit change**: `ShedLoad` re-points the
  Channel's RESERVED→CARRYING→IMPACT sweep downward so a body is relocated instead of buried — with its
  own test, and never assumed silently).
- **ORIENTATION:** Vertical-primary; gravity is the mechanism. The **raked** sibling turns the hoppers
  into side-tipping chutes along a long incline and the loads slide: the resizable axis flips from rise
  to run, one-wayness survives, the scree arrives as a shallow fan (a longer planting if anyone wants
  one), and a swept body travels further but slower, so a downstream absorber gets warning it never gets
  vertically.
- **PAIR:** Aster names the Ferrule's linger beat at the descent mouth — so the latch is crossed and
  pulled without standing still — and, from the same clock, the deadline by which the second spill must
  be walked. Peris reads which face of the cone is inclined enough to take a planting and tends it if the
  composition wants a second route; the landing floor also carries a **wild Capbage** as the tight-tier
  break for a party caught below on the wrong beat.
- **FAIL:** Spilling in the wrong order strands the party at the wrong height with a spent hopper behind
  them. Two priced recoveries, and they are **different transactions**: (a) spend a harvested vine
  already in hand — the link exists immediately, cost is one hand slot; (b) with no vine in hand, Peris
  plants on the cone and the climb exists only after one ripening. Floor: the hoppers always carry one
  more load than the minimum solve, and the silo's own scree ramp is always a climb.
- **BUILD:** Ships: the multi-level grid with add/remove link, cross-level pathing; **the silo drop chute
  object** (hatch lever, avalanche, climbable ramp registered as a runtime link, bury zone); the belt
  line and magnet hoist with the canon rule that Sapscraps strip an unattended iron plate on a scheduled
  commit; dynamic blockers and walkability toggling. **New:** a **ShedLoad** pad that registers its cells
  and link at the commit tick **analytically** (never per frame) and carries the strip timer; and a
  **Ferrule FSM** (camp-a-cell + linger-timer strike), shared with #18. No inter-enemy edge — the only
  enemy removal is the environment burying it.

### 28. Two Hands, One Pod — the escorted carry
- **HOOK:** The thing you came for needs both of somebody's hands and turns them slow, and the only way
  past the pack's hunting ground is a **Gasafoetida** pod that starts burning its 30–45 seconds the
  moment a warm hand closes on it. The repellent is a bubble around the carrier, not a corridor you
  clear.
- **PORTS:**

  | Port | Dir | Count | Class | Mult | Channel |
  |---|---|---|---|---|---|
  | one **charged, unspent** Gasafoetida pod | IN | 1 (2 under the two-trip and two-cloud configs) | **gating** | exclusive | lateral; or vertical/`gravity` in the drop config |
  | the payload — a two-hand object | IN | 1 | gating | exclusive | lateral, one-way in intent (it must come out, so the leg is a round trip on one clock) |
  | payload delivered past the hunting ground | OUT | 1 | gating | exclusive | lateral |
  | spent pod — inert husk still occupying a slot | OUT | 1 | pressure | exclusive | lateral |
  | displaced pack that **returns** | OUT | 1 | pressure | broadcast | lateral, delayed |

  **The pod is genuinely gating, and the fail-forward now matches:** a slow two-hand carrier takes pack
  bites (each landing inside its enzyme cloud — the enzyme rides the bite, there is no ambient DoT band)
  and goes down before the far mouth, so the payload cannot be delivered without a pod. The recovery is
  *drop the payload, leave the slow state, retreat on stamina, return with the next pod* — not "cross
  bloody". Hand slots (3 of 4 at the mouth) live in the **cost record**, not the port row. **Supply rate
  is the shipped rule: one pod per cluster per day rollover** at harvest stage — that is what makes the
  gating input real.
- **GAPS:** the crossing floor ({8,16,30} cells — run length **is** difficulty, because the pod clock is
  fixed by canon and the carry is slow) · the pod's damp corner at the mouth (fill it locally and the
  gating input is satisfied internally; leave it and a deficit is a genuine hard error) · one cell inside
  the run workable only while the bubble covers it — the model's nesting rule stated in **supply** rather
  than geometry.
- **CONFIGS:** one pod, one trip (the teacher) · one pod, two trips (**count 2**) · **two clouds**
  (**its own declared `teaches`**: routing between static safe points, not escorting — a different verb
  on the same body, so it is declared, not smuggled; the pod arrives `vertical`/`gravity`, one-way, and
  since a pod burns from pickup and only a sealed Capbage cavity holds one unspent, a member must already
  be above, which restaffs the pair) · split hands · **sealed reserve** (a Capbage at the mouth holds a
  banked pod unspent — the only way to bring a second in, and the direct chain onto #24) · cluster in the
  lane (**named** environmental igniter: the Ancourage fused-heat flare lane's own lit infrastructure —
  never "any fire in the composition", since the pair cannot make fire) · camped mouth (a **Ferrule**
  holds the mouth and flares at whoever lingers — the pod solves exactly the lingering problem it
  punishes, so the first seconds buy the entrance rather than the run) · ramp.
- **ORIENTATION:** Horizontal by default; the ramp config makes the escort vertical — same clock, same
  two speeds, but a fumbled payload rolls back down, converting the failure from "the clock ran out" to
  "the distance got longer".
- **PAIR:** At shelter 10 the guaranteed pair is **Aster + Peris** (Endo departs 6–7); **Myke is present
  as the info-anchor whose road knowledge reveals the DZ junction but is not required labour**, and Oli
  has not joined — so the fragment must be solvable with the pair doing all the work. Peris tends the
  cluster, charges the pod, and **is** the bubble, because she is the one with a free hand; Aster takes
  the payload into the slow carry and reads how long the pack's re-approach takes, hence whether the
  return leg fits. The forced staffing is the lesson. The Inflammashunt is a cure-component zone, so the
  **day clock is exempt** — the pressure is the pod clock and hand slots.
- **NAMED COUNTER-CHEESE:** Gnawers hunt by metabolic signature and Scarpet suppresses it, so a pre-laid
  Scarpet causeway is the canon signal-safe lane. Because the day clock cannot price it here, the base
  config declares the floor as **fused, dry Ancourage substrate that will not take Scarpet**; the
  alternate **paved lane** config lets the floor take it and prices the solve in Peris's tending cycles
  *between* visits. Pick one per placement and say which. A Scarpet mat at the mouth is the
  CONCEAL_MEDIUM staging tile where the carrier sets the payload down between legs.
- **FAIL:** Gas running out mid-run is not a reset. The pack re-approaches on a readable convergence, and
  the carrier drops the payload to leave the slow state and get clear on stamina; the payload lies where
  you left it and you come back with the next pod. Priced recoveries: a Hushbloom planted at the mouth
  breaks a rush for its stun window (recharge **30–60 s**, per the committed ruling that supersedes the
  mirror), and an ignited cluster regrows its pods over several minutes, so a burnt supply is a wait.
  A downed Gnawer's corpse stays briefly caustic, which taxes retrieving a payload beside one.
- **BUILD:** The most expensive of the set. Ships: the item runtime and hand slots, the 2-slot drag that
  already models a two-handed carry, `hushbloom.gd`, `capbage.gd`, `scarpet.gd`, and pursuit/disengage/roam
  so a displaced pack genuinely returns. **A Gasafoetida object does not exist in any form.** Needed:
  a tended cluster charging one pod per day rollover; a pod whose emit clock **starts on pickup**, timed
  off the gameplay scheduler tick (never wall clock), leaving an inert slot-occupying husk; the repel
  aura as a **moving detector-side derived state** — generalize the shipped `set_character_distracted`
  pattern to a radius around a carrier, recomputed on the detection-prediction path, never polled per
  frame; the seal-contains-the-gas rule; the serotinous ignition only if the lane config is used; and
  **object carry as distinct from body carry** (a retarget, not a new system). A pod emitting where it
  *lies* is **DERIVED** from the Capbage cache line and is a build item, not base canon. No inter-enemy
  edge — nothing here kills anything.

---

## What was dropped, and why

**Nothing was rejected outright** — all twelve drafts came back *fixable*, and every correction is folded
in above. What was **deleted** rather than corrected: the Drop Gallery's HOT GALLERY config and both
"arrival" ports (enemies cannot traverse links; arrivals are a boundary signature, not a supply); the
Counterweight Drum's PARTY-AS-BALLAST (it paid in bodies and created a reunion obligation no port
carried); the Hopper Stair's inter-latch catwalk, its upward-return input and its enemy-output port (the
catwalk deleted the fragment's own ordering, the silo's scree ramp already *is* the return, and canon
buries what stands in a spill); the Candid Aperture's "aperture seed" port (a time channel with no
supplier inside the composition); the Slope Nursery's rest-cycle port (a shared depletable budget, and
the code ripens on any day rollover); Cache Row's claim to be a sink (net zero on bodies); and the Toxo
Bed's vertical configuration, which is **blocked** until enemy cross-level traversal ships.

---

## What composes with what

**A worked chain that balances — #19 → #18 → #17 → #20, over two levels.**

1. **#19 Slope Nursery** sits on L2. Inputs: a day-rollover source (the run's shelter chain), one
   2-plant slope rung, a Scarpet apron. Outputs: **2 vines** (exclusive, carried), a one-way descent
   L2→L1, and a natural Sloperope climb L1→L2 — the P11 floor and the only reason the next fragment's
   demand is satisfiable at all.
2. **#18 Drop Gallery** shares the L2 terrace as its gallery and the L1 room as its lower floor. Its
   two-level **boundary signature** is discharged by the Nursery's descent plus the natural climb —
   nothing else in the catalog delivers both heights. It exports its one *timeless* output: a vine
   anchor spent at L1 (**vine budget 2 → 1**), giving a second two-way L1↔L2 link at the far end so the
   party need not walk back to the natural. Its pod delivery stays internal — the aura rides the carrier,
   so it cannot be exported anyway. Because the room will host a Capbage (below), the lower-floor gap may
   **not** be filled with a Candid mat; the flora-exclusion rule catches that at assembly.
3. **#17 Cover Slots** fills the gallery's lower-room gap at the 9-cell rung, with a raised plinth. Its
   `occluding_mass` ×2 is discharged by the gallery's two drop mouths — `gravity`, one-way, so the
   **vertical** config applies and the released-occluders output does not exist: the mass is consumed,
   not lent. `tight_hide` ×1 is the room's pre-existing tended Capbage. `pedestal_lift` ×1 is discharged
   by #20's float.
4. **#20 Wallow Sump** sits at the room's far lip and takes `water_level` as a broadcast band from an
   authored valve upstream. #17's lift consumer requires `[flooded, flooded]`; nothing else in this
   composition requires `[drained, drained]` at the same time, so the band intersection is non-empty and
   the check passes. Nest a child in the sump's under-route as well and it goes empty —
   `[economy/broadcast-band-empty]` — which is the point of declaring level as one band instead of two
   outputs.

**The ledgers.** *Vines:* produced 2, spent 1, one in hand leaving the region; both anchors are
`carried`-reachable without traversing the link the vine repairs. *Bodies:* the Spiker is **rooted**, so
it can never be a source — its only pressure exports are a sightline (a leaking channel bounded by the
site's hazard ceiling) and, in the feed-the-line config, one drawn Tangler. With that config **off**, the
sump's absorbable-body port goes unclaimed → `[economy/unused-sink]`, a warning, not an error. With it
**on**, the Tangler arrives laterally at the sump's lip on the landing level and the sump's
`ground_fauna` port claims it: net exclusive `fauna_body` = **0**, peak concurrent unabsorbed = **1**
(the body in transit), comfortably inside a mid-stage bound.

**Other clean joins.**
- **#27 → #17** in the **stable-pad** config: spilled pads are `occluding_mass` delivered from above and
  consumed. Never join them in the decaying-pad config — the check has no time axis and cannot see an
  occluder expire.
- **#22 between any hot source and a small sink:** the aperture is the piece that converts a mob into a
  single-file queue, which is what makes a capacity-1 absorber like **#21** sufficient at all.
- **#19 → #25:** the Nursery makes vines countable and the Drum is the only fragment that consumes them
  as a *coupling* rather than a link, so a level with both has a real vine market rather than a prop.
- **#23 → #7 / #16** (existing register entries): build the reveal system once and it serves the
  producer plus two consumers already drafted.
- **#24 next to any lure or repel source:** the bank is where a pod or vine goes to wait for the leg that
  needs it — but always check return-reachability, because a bank behind a one-way drop is write-only.
- **#26 needs an enforcement-free interval**, which #22 could supply — except that output is flagged
  OPEN pending a director ruling, so until it lands, take the interval from a Dead-Zone dressing and ship
  the bed's Gnawer- and Meeb-facing configurations.
