# Fleshing-Out Backlog — Channels & Fragments (autonomous `/loop`)

This is the worklist + protocol for an **unattended `/loop`** that fleshes out the level-content chunks
(the channels and the other fragments) — geometry, VFX, encounters, and the tests that guard them.

**To run it:** `/loop work the next READY item in to-rust-as-we-fall/FLESH_OUT.md following its protocol`.
Each loop pass does ONE item end-to-end, commits, marks it done here, and the loop schedules the next.

---

## Protocol — DO THIS EACH PASS

1. **Pick** the top item whose status is `READY` (highest priority first, top to bottom). 
2. If it's tagged `NEEDS-HUMAN`, do **NOT** attempt it — skip to the next `READY`. (These are design/content/tuning
   calls the loop must not guess.) If the only items left are `NEEDS-HUMAN` or `DONE` → **STOP** and report them.
3. **Execute it with the project discipline** (`.claude/CLAUDE.md` is the law):
   - **Reproduce-first**: write a FAILING test that encodes the desired behaviour (watch it go red).
   - **Build/flesh** it in the chunk (thin sequence scripts; all timing on the scheduler; cosmetics `@rendering_only`).
   - **Verify**: the new test goes green; run `--test-syntax`, the chunk's own `--test-*`, and any suite the change
     touches. **A VISUAL change REQUIRES a capture-and-look** — write/extend a windowed `--test-*-capture`, run it
     WITHOUT `--headless`, and read the PNG. (Tests passing is not enough — the session's hard lesson.)
   - **Never weaken a test to pass, never break a green test, never defer a bug.**
4. **Commit** one focused commit (no `.claude/`, no `Co-Authored-By`). Re-run the relevant suite to confirm green.
5. **Mark the item `DONE`** (edit this file, move it to the Done log with its commit hash). If the work surfaced
   follow-ups, add them as new `READY` or `NEEDS-HUMAN` items.
6. **Continue** the loop (the next pass picks the next item).

## Stop conditions (report, don't push through)
- No `READY` items remain (only `NEEDS-HUMAN`/`DONE`) → STOP, list what needs a human.
- A test you cannot make green after a genuine attempt → STOP, report the failure + output (don't weaken it).
- An item needs a **destructive or outward action** (delete a non-trivial file, push, anything external) → STOP, flag.
- You've done several passes and want a human checkpoint → fine to STOP and summarize.

## Guardrails
- ONE item per pass. Commit only when green. Keep the relevant suite green.
- Transparent overlays must survive the perception data-view (`render_priority` above the overlay quad's 126 —
  the water/ghost/splash precedent). 
- Fast-forward/replay safety: every logical transition rides the gameplay scheduler; per-frame motion is cosmetic.
- **Don't invent lore, dialogue, or new encounters** — those are `NEEDS-HUMAN`. The loop's job is completeness,
  polish, coverage, and well-specified mechanics, not creative authorship.

---

## Backlog

### P1 — overlay/visual completeness (concrete, verifiable)
- [x] `ui-dataview-dest-ring` **DONE** — dest ring now `render_priority = 127` so it survives the data-view;
  guarded in `--test-path-render-manager`. (See Done log.)
- [x] `ui-dataview-sweep` **DONE** — Audited every transparent gameplay overlay for data-view survival; the
  queued energy GLOW shell was the one offender (transparent at 118 → now 127), guarded. (See Done log.)
- [x] `splash-droplets-round` **DONE** — Droplet specks were 1px "discs" → a 5px plus/cross (diagonals excluded
  by `ox²+oy²<=1`) with hard alpha. Now min radius 2 + a soft radial falloff (solid core, soft 1px rim) so they
  read as round droplets. (See Done log.)

### P1 — test coverage (every chunk earns a guard)
- [~] `cov-playthrough-audit` **IN PROGRESS** — Beatability test per chunk that lacks one (wash-relay pattern:
  drive to `complete` via the data layer). ONE chunk per pass. Audit of the 15 chunks:
  - Covered: `wash_relay` (`--test-wash-relay-playthrough`), `lure_relay` (`--test-lure-relay` reaches `complete`),
    `showcase_gallery` (`--test-showcase-gallery` asserts the tour completes), `refuge_run`
    (`--test-refuge-run-playthrough`, **DONE** this pass — see Done log).
  - **READY** (have a `complete`/win concept, still need a playthrough): `endo_junction_stretch`,
    `generated_stretch`, `mother_flure`, `survival_range`. (Do one per pass.)
  - N/A — sandbox/showcase chunks with no beatable objective (a playthrough test doesn't apply; they have their
    own feature tests): `push_lab`, `rest_lab`, `flora_garden`, `dusk_run`, `rings_fragment`, `lockout_fragment`,
    `stacks_fragment`. (Revisit only if one gains a win/exit condition.)
  - **Done-when:** each READY chunk above has a `--test-<chunk>-playthrough` reaching `complete` in `--test-all`.
- [ ] `cov-flat-collision-probe` **READY** — Generalize `--test-channels-probe-coverage` (walkable cell ⇒ deck
  collision under it) to the FLAT (non-warped) chunks, so "walkable == clickable" is guarded everywhere, not just
  the helix. **Scoping (2026-06-23):** of the 15 chunks, only `generated_stretch` and `wash_relay` build their own
  grid; `wash_relay` is the warped one already probed, so the flat target is essentially `generated_stretch`
  (verify its floors are colliders, not mesh-only `_add_box`). The mesh-only chunks have no grid, so "walkable"
  isn't defined for them — N/A. **Done-when:** `--test-generated-stretch-probe-coverage` asserts 0
  walkable-but-uncollided cells (probe straight down on each `grid.grid_to_world(cell)`, no coord_map).

### P1 — visibility / line-of-sight wiring
- [ ] `los-wire-chunk-sight-blockers` **READY** — Enemy-detection LOS is live (`grid.has_line_of_sight` gates
  `_on_detection_event`), but it only bites where a scene marks walls as grid `WALL` tiles or registers
  `grid.add_sight_blocker(cell)`. Chunks that build walls as mesh-only `_add_box` get no enemy LOS yet. Wire
  sight-blockers from each gridded chunk's wall geometry (derive from the wall boxes at build, like occupancy —
  derived, never logged). Do ONE chunk per pass. **Done-when:** a `--test-<chunk>-detection-los` shows a guard
  failing to spot a target across one of that chunk's real walls (and spotting it in the open).

### P2 — channels enrichment
- [ ] `splash-per-outlet` **READY** — Sections with MULTIPLE visible outlets in the GLB (e.g. the jet section's
  jets) currently get one centre splash. Place a splash per real outlet derived from the section dressing /
  GLB outlet nodes. **Done-when:** the jet section shows ≥2 splashes at its outlets (capture + look) and the
  splash test still passes. *(If outlet positions aren't derivable from data/the model, retag NEEDS-HUMAN.)*

### Scenes
- [ ] `scene-tag-day-flesh` **NEEDS-HUMAN** — Flesh out the Tag Day checkpoint scene (`tag_day.tscn` /
  `tag_day_sequence.gd`). The scene already plays end-to-end (covered by `--test-tag-day` ×3 and reached in
  `--test-intro-realinput`), so the remaining work is **creative/content**: the checkpoint-queue staging, the
  naturalizer grip-and-walk choreography, the "Hollow Men" poem beats + timing, and any new dialogue — all of
  which are authorship the loop must not guess. **Loop-safe sub-tasks** (split these out as `READY` if/when the
  human specifies them): a `--test-tag-day-playthrough` data-layer beatability guard (wash-relay pattern), a
  flat-collision probe for its grid (see `cov-flat-collision-probe`), and data-view/render_priority audits of any
  overlays it adds. **Done-when:** the human defines the concrete beats; until then this stays NEEDS-HUMAN.

### NEEDS-HUMAN (loop must NOT attempt — flagged for review)
- [ ] `tune-water-alpha` **NEEDS-HUMAN** — final flood-water translucency (`water_alpha`, currently 0.88) and
  splash alpha/lead-in feel are aesthetic calls.
- [ ] `content-new-chunks` **NEEDS-HUMAN** — net-new fragment archetypes / encounters / lore are creative design.
- [ ] `drain-loop-feel` **NEEDS-HUMAN** — whether the drain guard should be lethal-kill vs knock-down, bait timing,
  etc. are gameplay-design calls (already chosen once; revisit only with direction).

---

## Done log
<!-- The loop appends finished items here with their commit hash. -->
- `ui-dataview-dest-ring` (2026-06-22) — destination ring draws over the perception overlay (render_priority
  127); red/green-verified in `--test-path-render-manager`. First validating pass of the framework.
- `occlusion/visibility overhaul` (2026-06-23, user request — several commits) — (1) camera-occlusion reveal
  larger (3.5→5.5) + zoom-out auto-off (the fade circle fades as the camera pulls back); (2) perception clear
  zone 8→14; (3) route ribbon + dest ghost/ring draw through faded/occluding geometry (no depth test); (4)
  move-raycast pierces overhead helix decks when zoomed in (`_hit_height_ok`, `--test-player-overhead-gate`);
  (5) perception LOS — the clear zone hugs walls via screen-space line of sight (`--test-perception-los-capture`,
  17.4% on/off diff verified); (6) enemy-detection LOS — grid `has_line_of_sight` gates the spot
  (`--test-detection-los`), replay-deterministic. Follow-up `los-wire-chunk-sight-blockers` queued above.
- `cov-playthrough-audit: refuge_run` (2026-06-23) — added `--test-refuge-run-playthrough` (in `--test-all`):
  drives the composite refuge stretch to `complete` via the chunk's own commands — safe north route, stage the
  slit + open the lure window (→ slit safe), gather the party on the shelter spot + ride the sweep (→ spot safe),
  gather at the exit + `reach_exit()` (→ route_phase `complete`). Proves the slit/spot/exit gates line up and the
  stretch is beatable. (cov-playthrough-audit remains IN PROGRESS — 4 chunks still queued.)
- `splash-droplets-round` (2026-06-23) — pipe-splash droplet specks now render as round soft discs (min radius 2
  + radial alpha falloff) instead of 1px plus/crosses. Guarded red/green in `--test-channels-splash-droplets`
  (re-derives the generator's droplet centres, asserts each flung droplet has a solid 3×3 core — impossible for a
  plus); eyeballed via `vr_splash_droplets.png` (dark-composited so the white-on-transparent splash is visible).
  `--test-channels-pipe-splash` stays green.
- `ui-dataview-sweep` (2026-06-22) — transparent-overlay data-view audit. Findings: selection = 2D marquee on a
  CanvasLayer (UI, survives inherently); crisp outline HULL = opaque (`unshaded, cull_front, depth_draw_always` →
  always in the screen texture); highlight PARTICLES = opaque `StandardMaterial3D` (default `TRANSPARENCY_DISABLED`
  → survives); dest ring + ghost = already 127. The ONE offender: the queued/selected ENERGY GLOW shell
  (`outline_emission_noise.gdshader`, `blend_add` = transparent) was `render_priority = 118` < the overlay quad's
  126, so it vanished in data-view. Fix: 118 → 127 in `outline_surface_target.gd::_ensure_glow_shell`; guarded
  red/green in `--test-outline-feedback-system` (builds a target, fires `begin_queued_feedback`, asserts the
  `OutlineEmissionShell` material `render_priority > 126`).
