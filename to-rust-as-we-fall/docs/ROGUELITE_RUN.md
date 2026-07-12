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
- The finale site loads through the boss_showcase chunk with `{"finale": true}` — the prize
  interactable ("TAKE THE DOSE") reports `prize_retrieved` through preview state.
- The presenter (fragment_preview_sequence) polls: prize → `retrieve()` → the report card;
  wipe → the report card; shelter rest → the branch modal (unchanged). Permadeath wires
  `character_downed → mark_death` after every level load.
- Launch: the picker's "Roguelike Run (WFC stretches)" / `--preview=roguelike_wfc` (and the atom
  variant) — both now END.
- Guarded by `--test-roguelike-goal` (in `--test-all`): run shape, finale arrival, retrieval
  gating, permadeath ledger, wipe, the finale chunk's prize state, the presenter's finale arm.

## Next (the "more elements" track)

Grow the generator's vocabulary so runs vary in MECHANIC, not just layout — the reusable object
classes exist; they need loader object kinds + generator placement:

0. ~~decorative_flora + spike_strip~~ — DONE (2026-07-12): the ornamental invasives
   (docs/DECORATIVE_FLORA.md, loader kind `decorative_flora`, Peris HARVEST yellow reveal on Y,
   runback decor pass) and the anti-loiter studs (SET_PIECES 21, loader kind `spike_strip`,
   symmetric DoT). Demo: `--preview=hostile_streets`. Generator PLACEMENT (decor density knob +
   strips at chokepoints) still pending — joins the crawl_tunnel item below.
1. **crawl_tunnel** (CrawlTunnel exists) — squeeze shortcuts across node walls: the shadow-route
   element, depth-widening.
2. **Water basin valve + floats** (set-piece bay C logic) — extract from the showcase chunk into
   a reusable object, then generator-placed at channel nodes.
3. **Magnet hoist** (bay E) — same extraction path.
4. The register's build-next digest (ENVIRONMENT_ELEMENTS.md): flow-strip beat reader, Flure
   seep lures (objects exist), drawer-stairs v2, junction-box row, crossing-signal trio.
5. SET_PIECES proposals 8–20 as they're approved — the Aghora tolerance lanterns and sync floor
   are strong roguelite elements (decaying resources read beautifully under permadeath).
