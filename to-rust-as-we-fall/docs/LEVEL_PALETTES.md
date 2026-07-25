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
   must draw from the hosting level's row (open fix from the asset autopsy: today they
   ship magenta/purple confetti from nowhere).
5. **Sub-palettes** (e.g. `channels.sections`) are part of the row: the nine section-gate
   hues are data here, mirrored nowhere else.
6. Rows marked `PROPOSED` are starter identities distilled from existing chunk looks
   (greenfields / stacks / aghora / endo_junction); the director refines them when
   that level's art pass lands — but new assets for those levels use the row as-is TODAY.

## Current rows

- **channels** — dark wet iron `#1a1c21` on `#101216`, rust `#42210f`, luminous water
  `#4cbff2` over `#0f2933`, teal flora `#33d9bf`, aged wood `#614526`, amber work-lamps
  `#b36610`; plus the nine `sections/*` gate hues.
- **greenfields / stacks / aghora / endo_junction** — PROPOSED starters, see JSON.
