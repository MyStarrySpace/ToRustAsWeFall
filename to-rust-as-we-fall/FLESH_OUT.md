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
- [ ] `ui-dataview-sweep` **READY** — Audit the remaining transparent gameplay overlays (queued-glow particles
  on `OutlineSurfaceTarget`, selection markers, the hover-grid) and give any that should read in data-view the
  same `render_priority` treatment. **Done-when:** each audited element either has render_priority > 126 or a
  documented reason it shouldn't; a guard test covers the ones fixed.
- [ ] `splash-droplets-round` **READY** — The pipe-splash texture's droplet specks render cross/plus-shaped at
  64px (1–3px discs + nearest filter). Make them read as round droplets (filled discs with a soft edge, or
  upscale the texture). **Done-when:** `--test-channels-splash-capture` PNG shows round droplets (capture +
  look); `--test-channels-pipe-splash` stays green.

### P1 — test coverage (every chunk earns a guard)
- [ ] `cov-playthrough-audit` **READY** — For each chunk in `scripts/fragments/chunks/` that has NO data-layer
  playthrough/beatability test, add one (`--test-<chunk>-playthrough`, the wash-relay pattern: drive the chunk
  to `complete` via the data layer, prove it's beatable). Do ONE chunk per pass; add a new `READY` line per
  remaining chunk as you go. **Done-when:** the new `--test-<chunk>-playthrough` reaches `complete` in `--test-all`.
- [ ] `cov-flat-collision-probe` **READY** — Generalize `--test-channels-probe-coverage` (walkable cell ⇒ deck
  collision under it) to the FLAT (non-warped) chunks, so "walkable == clickable" is guarded everywhere, not just
  the helix. **Done-when:** a probe asserts 0 walkable-but-uncollided cells on at least the flat chunks with a grid.

### P2 — channels enrichment
- [ ] `splash-per-outlet` **READY** — Sections with MULTIPLE visible outlets in the GLB (e.g. the jet section's
  jets) currently get one centre splash. Place a splash per real outlet derived from the section dressing /
  GLB outlet nodes. **Done-when:** the jet section shows ≥2 splashes at its outlets (capture + look) and the
  splash test still passes. *(If outlet positions aren't derivable from data/the model, retag NEEDS-HUMAN.)*

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
