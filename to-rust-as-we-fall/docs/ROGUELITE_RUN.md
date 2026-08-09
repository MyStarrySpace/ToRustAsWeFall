# The Roguelite Run — the Retrieval Descent (decided 2026-07-12)

The mode's design authority is `reference-docs/dlc_roguelike_mode.md` (permadeath, procedural
arrangement, no narrative scaffolding, the tag-swap framing, the DLC roster). The run-shape
economics are `reference-docs/run_meta_decisions.md` (risk/reward branches). This doc records the
GOAL those left open, and the build state. The generation is the driver: every level is produced
by the procedural pipeline (WFC stretches / atom chains) and varies per seed.

## The goal

**A run is a finite, seeded DESCENT to a boss-site retrieval.**

- `RunSession.target_depth` rolls 5–7 per run seed. Each shelter offers the ratified risk/reward
  branch; the last shelter's branch announces the site (`finale_next`).
- The bottom level is a FINALE SITE hosting a mega-landmark retrieval. v1: **the Paranucleus** —
  hold the front vantage, park the wheel, wait the window, thread the alignment crossing, and
  TAKE THE DOSE (the reservoir cache beyond the far mouth). Retrieval completes the run.
  (The Watchtower approach and the Aghora gate are the planned alternate finale sites — the
  boss pieces are the roguelite's finales.)
- **Permadeath** (the DLC doc's law): a fallen character leaves the run permanently; every deeper
  level regenerates FOR the smaller roster (the solver guarantee holds for the current party);
  an empty roster is a wipe and the run is over.
- The **summary** is the score surface: depth vs target, retrieval, survivors, the permadeath
  ledger, branches chosen. One button starts a fresh run on the next seed.
- The fiction is the tag-swap reading made mechanical: system-invisible scavengers making supply
  dives into the collapsing deep.

## Where it lives

- `RunSession` (scripts/generation/run_session.gd) — the headless run authority owns the whole
  goal: `target_depth`, `at_finale()`, `_generate_finale()`, `retrieve()`, `mark_death()`,
  `run_over`, `summary()`. Deterministic per seed; drivable end-to-end in a test.
- The finale site loads through the boss_showcase chunk with `{"finale": true}`. The cache owns
  one source-tagged GameState vial; "TAKE THE DOSE" completes only after that exact vial reaches
  the interacting character's hand. `prize_retrieved` remains a compatibility preview derived
  from the saved item transaction, not an independent reward boolean.
- The presenter (fragment_preview_sequence) polls: prize → `retrieve()` → the report card;
  wipe → the report card; shelter rest → the branch modal (unchanged). Permadeath wires
  `character_downed → mark_death` after every level load.
- Launch: the picker's "Roguelike Run (WFC stretches)" / `--preview=roguelike_wfc` (and the atom
  variant) — both now END.
- Guarded by `--test-roguelike-goal` (in `--test-all`): run shape, finale arrival, retrieval
  gating, permadeath ledger, wipe, the finale chunk's prize state, the presenter's finale arm.

## District theming — DONE (2026-07-19)

Procedural depths now rotate through five mechanically grounded districts inspired by the main
game: Channels, Open Files / Stacks, Greenfields Collective, the Cleanstreets Initiative, and the
Deadzone. A seeded run visits all five before repeating one, and adjacent depths never reuse a
district.

Each district contract controls its content pools, floor and hazard surfaces, lighting, landmark
anchor requirements, causal read, and feedback role. The dominant landmark is an authored scene
cluster rather than runtime-built decorative geometry: a Channels pump house, Stacks archive
spire, Greenfields root pavilion, Cleanstreets toll-canopy pavilion, or Deadzone chembrane ruin.
The generator places that cluster beside a compatible systemic node so the building vocabulary
reinforces what the stretch asks the player to notice and manipulate.

Cleanstreets also owns generated route set-pieces rather than only a skyline skin. Its pale,
sweeping arterial uses authored slanted no-rest furniture and anti-loiter stud scenes. The active
stud scenes are seated directly on navigation risk cells: SAFE preview can bend around them when
an alternate lane exists, while DIRECT crosses them and pays continuous, locally messaged health
damage. That makes the hostile architecture a legible route trade rather than unexplained attrition.

## Next (the "more elements" track)

Grow the generator's vocabulary so runs vary in MECHANIC, not just layout — the reusable object
classes exist; they need loader object kinds + generator placement:

0. ~~decorative_flora + spike_strip~~ — DONE (2026-07-12): the ornamental invasives
   (docs/DECORATIVE_FLORA.md, loader kind `decorative_flora`, scenery-only runback decor pass)
   and the anti-loiter
   studs (SET_PIECES 21, loader kind `spike_strip`,
   symmetric DoT). Demo: `--preview=hostile_streets`. Cleanstreets generator placement is now
   DONE: authored stud-lane scenes occupy route-risk cells. The general decor density pass remains.
1. **crawl_tunnel** (CrawlTunnel exists) — squeeze shortcuts across node walls: the shadow-route
   element, depth-widening.
2. **Water basin valve + floats** (set-piece bay C logic) — extract from the showcase chunk into
   a reusable object, then generator-placed at channel nodes.
3. **Magnet hoist** (bay E) — same extraction path.
4. The register's build-next digest (ENVIRONMENT_ELEMENTS.md): flow-strip beat reader, Flure
   seep lures (objects exist), drawer-stairs v2, junction-box row, crossing-signal trio.
5. SET_PIECES proposals 8–20 as they're approved — the Aghora tolerance lanterns and sync floor
   are strong roguelite elements (decaying resources read beautifully under permadeath).

## The open-world structure (director, 2026-08-14) — SUPERSEDES the binary shelter fork

The run is **not** a linear descent through single levels. It is a **procedurally generated open
world** the player moves through along **multiple paths**, carrying:

- **Multiple routes to resources**, not one fork with two doors. A destination is reachable more than
  one way, and the ways differ in what they cost and what they pay.
- **Hidden power-ups** — found by exploring, not offered at a menu.
- **Other characters waiting along the way** — a companion is DISCOVERED in the world, at a place,
  not granted as the reward of a chosen branch.

### The economic spine: every path is priced, and the currency is HP

The player chooses tradeoffs by choosing routes. The profiles the director named:

| Route profile | Difficulty | Outcome |
| --- | --- | --- |
| Hard route | high | the richer payout |
| Moderate route | medium | less |
| **Trivial route** | very low | **a guaranteed small LOSS** |

**Routes are denominated in HP** (director, 2026-08-14). Under permadeath HP is the run's real
currency: it does not refill on a timer, restoring it costs an ATP-priced shelter rest, and spending
it to zero ends a character permanently. ATP remains the food/rest economy; it is not the unit a
route trade is quoted in.

The third profile is the one the current model cannot express, and it is the interesting one: a
**certain, priced skip**. Today `run_branch_decisions.gd` only authors "a costly path that grants a
unique reward vs a safe path without it" — safety is free, it merely forgoes. A guaranteed HP loss
makes the cautious line *cost something*, so caution is a real decision rather than a default, and a
struggling run gets a legible pressure valve: you can always afford to skip, and you feel the fee.

### Worked example — the long hall (director's own, 2026-08-14)

A corridor with no cover until the far end, tuned so the sprint does not quite reach it:

1. Running the hall consumes the **full stamina bar**.
2. Stamina empties, so the party **drops to walk speed** short of the hide.
3. The pursuit **closes the gap** the party can no longer hold.
4. The party **takes damage** — roughly **20–30 HP**, more on harder difficulty.

**The price is arithmetic, not luck.** The hall's length is set slightly beyond full-stamina sprint
range, so the shortfall — distance remaining after exhaustion, divided by the closing rate, times the
strike rate — IS the fee. That makes the trivial route's cost authorable and tunable rather than a
dice roll, which is what lets it be advertised to the player as a known price.

**Stamina is the MECHANISM; HP is the PRICE.** Stamina is what converts a routing choice into a
damage bill; HP is the only currency permadeath actually counts. The coupling is already shipped and
taught elsewhere — the showcase gallery's lesson is exactly this in miniature (spend stamina on the
approach and the retreat happens at walking pace under a charge) — so the route economy composes an
existing relationship rather than inventing one.

### What this changes, honestly

- **The branch layer is superseded, not extended.** `run_branch_decisions.decide()` returns exactly
  two options at a shelter (`options[0]` costly, `options[1]` safe). An open world needs a **route
  graph with N priced edges**, evaluated by where the player IS rather than at an authored fork.
- **Recruit stops being a reward.** `next_recruit(roster)` currently hands a companion to whoever
  picks the risky branch. Under the ruling, a companion is a WORLD PLACEMENT the player can find,
  miss, or reach by several routes. (The register-on-presence roster pattern already supports a
  character existing only where a chunk asks for them.)
- **Permadeath and the finale are unchanged.** A finite seeded world with a boss-site retrieval is
  compatible with an open topology; "descent" becomes a direction of travel, not a stack of levels.
- **Solvability generalizes for free.** The greedy flood-open validator (proofs §7.2b) already runs
  on a flattened `(cell, level)` graph and proves completeness for ANY opening order — it never
  depended on a linear spine. An open world is exactly the shape it was written for. What it does
  NOT cover is the economic layer: reachability says nothing about affordability.
- **The resource layer becomes load-bearing.** With priced routes, the assessment's §7.4 finding
  stops being a corner case: the exit is already ATP-gated in every mode, and nothing at generation
  compares a route's cost against the budget a player can actually hold. **G3 (the risk-lane budget
  guard) is now a prerequisite, not a nice-to-have.**

### Open questions (for the director, not to be guessed at)

1. **Is the world one connected map, or regions joined by gates?** Both satisfy "multiple paths"; they
   differ completely in generation and in what a run's shape feels like.
2. **Do routes reprice as the run proceeds** (a taken route exhausted, a skipped one souring), or is
   the price fixed at generation?
3. **Is a missed companion missed for the run, or re-findable?** Permadeath argues for the former;
   an open world with backtracking argues the latter.
4. ~~What is the guaranteed loss denominated in?~~ **ANSWERED (director, 2026-08-14): HP**, via
   stamina exhaustion (see the long hall). Open sub-questions: is the loss dealt to one member, split
   across the party, or the player's choice of who eats it? And does the generator TUNE hall length
   from a target HP cost, or author length and report the resulting cost?
