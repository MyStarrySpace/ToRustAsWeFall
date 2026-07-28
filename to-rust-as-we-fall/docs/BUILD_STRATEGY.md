# TRAWF Build Strategy — Atomic Pieces First

The high-level approach for building level content strategically, so every build compounds. Companion to
`DESIGN_PRINCIPLES.md` (the constitution — spine test + P1-P18) and `LEVEL_DESIGN_RESEARCH.md` (elements
fished from comparable games). This doc is the *sequencing* layer: what to build, in what order, and why.

## The method: case law + statute law, built together

The Watched Gap taught the pattern — the *fragment* found three real engine bugs, and its adversarial review
hardened the *contract*. So we build two layers that force each other:

- **Case law (fragments):** each atom is a court case that exercises real mechanics and forces one new law
  into the verifier.
- **Statute law (the contract):** each verifier slot a fragment forces makes the next fragment cheaper and
  the generator more honest.

### Governing rules (distilled from this session's failures)

1. **One new thing per fragment.** Each atom adds at most one new mechanic / verb / contract-slot; everything
   else reuses tested pieces. (Kept the Watched Gap's three bug-hunts debuggable.)
2. **Red-first work orders.** Playtest scenarios are written *in the work order before implementation* — that
   IS the delegation contract for Opus: "make these go green without weakening them."
3. **Extract before compose.** If a mechanic lives inside a monolith (wash_relay owns washes + held consoles +
   sweep), extract it into a reusable object (like `Flure`/`Capbage`/`PortalPad`) before any atom composes it.
   Never copy puzzle logic.
4. **Presented + Shadow from birth**, enforced by the ability-ablation verifier, not by prose (P10).
5. **Topology gating != mechanically solvable.** Prove the solve with a real in-engine playtest, never a
   flood-fill alone. Keep the honesty ledger visible (`ChunkGenerator.mechanic()` stamps NOT-BUILDABLE).

## Director rulings (locked this session, 2026-07-01)

- **P11 wash target = the BOTTOM (start shelter).** The doc is canon; A2 fixes `wash_relay`'s previous-gap
  divergence to match. Reunion is a depth-scaled physical time cost (runback/sloperope); recovery remains shelter rest.
- **C1 (charge-structure impact) + C3 (systemic lure-stimulus channel): GREEN-LIT.** C3 scheduled right after
  A2, before a third fragment hand-puppets the enemy FSM.
- **Location renames applied** (GDD 4.4 canonical; see `reference-docs/act1_timeline.md` + memory
  `act1_location_names`). The Stacks = **The Open Files Initiative** (data-terminals district).
- **Greenfields Collective (Residential Rings) is a relational/memory zone, NOT populated-stealth** — Peris
  reads emotional residue in flora (client-bloom, propagation trace, forget-me-nots). Serves P2 (WHERE
  register) + P14 (flora) + the care/degradation theme, not a sneak-past-guards beat.

## Track A — the fragment library (sequenced by dependency)

Reshaped so the terminal object (Track D) is extracted first and every atom draws its mechanism from it.

| # | Atom | Composes (exists) | The ONE new thing | Forces into the contract |
|---|------|-------------------|-------------------|--------------------------|
| **D0** | **Extract `Terminal`** (Door + Recon subtypes) | Interactable, dynamic blockers, per-char overlay | the reusable typed object | `mechanism: {family, subtype}` slot |
| **A1** | **The Crossfire** — Watched Gap v2 w/ mutual overwatch (two sentries covering each other) + conceal pocket + patrol beat = built-in Shadow; a **Recon terminal** feeds the shadow's WHEN read | LOS, lures, conceal tiers, patrol | mutual-overwatch composition | VISIBILITY invariant (seen-cells) + PERCEPTION_LOCK |
| **A2** | **The Holdfast** — atomic wash crossing, **Flow terminal** held override, wash→bottom, role inheritance | washes, held consoles, sweep (post-extract) | the wash/console/sloperope extraction | FAIL/RECOVER slot + monotone-ascent |
| **A3** | **The Two-Hand Door** — simultaneity split; Shadow = timed-latch hack | held plates, dynamic blockers | simultaneity verb | completion-grammar slot |
| **A4** | **The Hide Chain** — stealth-and-time through loose→medium→tight hide tiers | conceal tiers, patrol, Capbage | tier-chain composition | TEACH_BEAT slot |
| **A5** | **The Three Doors** — N candidate objectives, one real; cheap-slow clue reads vs expensive-direct assault (Desperados III New Orleans) | interactables, party spread, Recon terminal | info-as-objective archetype | information-scarcity generator constraint |
| **A6** | **Lure Relay retrofit** — existing chunk brought under the atom contract + verifier | — | — | regression breadth |

## Track B — the contract, growing only when forced

Seen-cells VISIBILITY (A1) → ability-ablation / SHADOW slot (A1-A2, hooks the existing solver) →
TELL/FAIL/TEACH_BEAT schema slots (A2/A4) → lock-before-key ordering (cheap, any time) → then, once 3+ atoms
exist: the **assembly layer** — coupling edges, key provenance, monotone-ascent, connect-backs (Dormans).

## Track C — director-gated mechanic unlocks

- **C1 charge-structure impact** [GREEN] — unblocks the `redirect` archetype (currently stamped NOT-BUILDABLE).
- **C3 systemic lure-stimulus channel** [GREEN, after A2] — attraction as a GameState stimulus any enemy FSM
  answers, so fragments stop hand-puppeting the FSM (Watched Gap + lure_relay both do today).
- **C2 carry state** [deferred] — unblocks Carry-the-Heavy-Thing (the Flow Aligner canon).
- **C4 suspicion "?" grace tier** [deferred] — "?" before "!"; changes the catch grammar everywhere.

## Track D — section-typed environmental-object families

Each object is a reusable, verb-distinct interactable, keyed by biome/section — the concrete vocabulary of the
gate **mechanism** slot. Generalizes P14 (one load-bearing verb) to all interactive objects; satisfies P15
(canon-and-meaning) by construction because each district's canonical identity dictates its native family.

**District → native family (canonical names):**

| District | Native family | Serves |
|----------|---------------|--------|
| **Plumbing Power Project** (the Plumbing) | Flow terminals + flora + washes | gated ascent / A2 Holdfast |
| **The Open Files Initiative** (the Open Files) | Recon + Door terminals, Aster's hacking | P3 info-as-content — the district that *is* data terminals |
| **Greenfields Collective** (the Greenfields) | relational/memory flora (client-bloom, propagation, forget-me-nots) | P2 WHERE register + care theme (NOT stealth) |
| **The Hypelines** (the Lines) | resource caches, Credential terminals | Myke's join; checkpoint bypass |

**Terminal subtypes (canon-grounded, GDD §2.1.4/§10.2/§2.6):** Door (hack → open a dynamic-blocker gate),
Recon (hack → reveal layout/flora/patrol on the overlay — buy knowledge, P3), Credential (pacify/reroute a
checkpoint), Signal (fire a lure at range — the C3 channel), Flow (HELD → hold a wash while others cross).
Each = one verb, one effect; the subtype decides which register reads it best (P2).

## Milestone M1 — one real gated ascent of three atoms

A1 + A2 + A4 chained bottom-to-top with extracted connect-backs and the monotone-ascent verifier: the first
true channels-shaped stretch *built from atoms*. This is where the meta-generation conversation reopens with
real material instead of speculation.

## Open decisions (director)

1. **D0 subtype set** — Door + Recon (fold Flow into A2)? or extract Flow in D0 too?
2. **Other object families to reserve palette slots for now** — Credential (Hypelines/checkpoints), Power
   (Oli's register), section-native hazards (Stacks signal-leakage, Plumbing conduits)?
3. **`channels` biome display = "Plumbing Power Project"** (canonical) vs keep "the Channels" as the region
   concept surfaced to the player. (Only the display string changed; slug/concept stay "channels".)
4. **`garden` biome** — leave as a generic type, or map to a canonical district?
5. Carryover from the register: **`--test-curriculum-ramp` grows depth/size with stage** (P1 forbids that as
   the long-arc axis); and whether to promote any of the audit's **P19-P28** candidates into the register.
