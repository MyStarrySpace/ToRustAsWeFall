# Level Palettes — one palette per level, and assets USE it

Director-ratified 2026-07-25 ("define a consistent color palette for each level and use
it for assets"). The registry is DATA, shared by both sides of the pipeline:

- **`data/palettes/level_palettes.json`** — the single source of truth.
- **Godot**: `LevelPalette.color("channels", "water")` / `LevelPalette.global_color("portal_route")`
  (`scripts/system/level_palette.gd`). Missing level/role = loud error + magenta.
- **Blender builders**: `json.load` the same file (see `build_wash_dressing.py`'s
  `PAL`/`C()` helpers). A builder never hard-codes an rgb again.

## The law

1. **Every asset color traces to a palette row.** New level content starts by adding or
   reading its level's row — never by inventing a hex inline. Retuning a look = editing
   the JSON, and every consumer (chunk meshes, dressing pieces, paintlib parts, lights)
   follows on the next build.
2. **`_global` rows are invariants, never restyled per level**: terminal green `#5ce87f`
   (the ONLY standard emissive), the portal trio (purple transit / blue route / red
   locked — docs/PORTALS.md; NO gold portals), the Curecumin item gold (items, seals —
   never fixtures), warning amber.
3. **Per-character ownership tints stay in code** (the HUD contract), not in level rows.
4. **Generated content obeys the level palette too** — the branch/archetype set pieces
   draw from the hosting level's row (the archetype piece library bakes the channels
   row for v1; re-emit per district when their art passes land).
5. **Sub-palettes** (e.g. `channels.sections`) are part of the row: the nine section-gate
   hues are data here, mirrored nowhere else.
6. Rows marked `PROPOSED` are starter identities distilled from existing chunk looks
   (greenfields / stacks / aghora / endo_junction); the director refines them when
   that level's art pass lands — but new assets for those levels use the row as-is TODAY.
7. **The `species` row holds CANONICAL FLORA COLORS** (flora_taxonomy.md), district-
   independent: a species keeps its identity in every level (Hushbloom pale lavender
   `#d6cce6` — teal belongs to Seefern; healthy Scarpet greenish-brown `#6f6b4e` with
   rust scar patches; Mother-Flure root browns). Level rows restyle ARCHITECTURE,
   never species.

## Current rows

- **channels** — dark wet iron `#1a1c21` on `#101216`, rust `#42210f`, luminous water
  `#4cbff2` over `#0f2933`, teal flora `#33d9bf`, aged wood `#614526`, amber work-lamps
  `#b36610`; plus the nine `sections/*` gate hues; plus the organic-overgrowth and
  prop roles from the concept plates — `vein_bark`/`vein_ridge` (the vasculature),
  `biolume_blue`/`biolume_violet`/`biolume_stem` (the cluster glow), `lamp_red`
  (the red bar-lamp/dot-sign light), `pipe_joint` (ball-joint steel). The vein and
  biolume roles are shared by the texture generator (gen_vasculature.py), the piece
  library parts, and any runtime lights — one organism, one palette.
- **greenfields / stacks / aghora / endo_junction** — PROPOSED starters, see JSON.

## Species colours corrected from the concept cards (2026-07-27)

The species row is canon-derived, but where a written description and the director's
own card render disagreed, the CARD wins (it is the art of record):

- `climbvine_fiber` was a green; ENT-020 shows a **bone/beige** rope. Corrected, with
  `climbvine_node` darkened to match its grip-roots.
- `scarpet_green` (olive-brown) describes the *senescing* read; the tended card ENT-015
  is a vivid green mass shot with rust-orange. Added `scarpet_blade`,
  `scarpet_blade_deep` and `scarpet_senesce` for the tended blade mix — `scarpet_green`
  stays for the faded state.
- Added `seefern_vein_core`: ENT-014's veins read near-**white**, with the teal
  (`seefern_vein`) as their glow, not the core colour.
