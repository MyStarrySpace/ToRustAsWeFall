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
