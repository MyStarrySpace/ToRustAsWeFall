---
name: pixel-atlas-texturing
description: Turn a low-poly model (or an assembled room) into a HAND-PAINTABLE low-res pixel-art atlas and wire it into the Godot game. Use when the user wants UVs for hand-painting, an OBJ export for texturing, a single packed atlas, or to assemble a room from mixed sources (gltf imports + Crocotile rooms + new Blender pieces). The companion to the `low-poly` skill (which BUILDS models); this one TEXTURES + ASSEMBLES + ships them. Detail and shading are PAINTED, never modeled.
---

# Pixel-Atlas Texturing & Room Assembly

The texturing + shipping half of the To Rust low-poly pipeline. The `low-poly` skill builds chunky
faceted geometry; this skill takes that geometry (or a room assembled from mixed sources), gives it a
single **hand-paintable low-res pixel-art atlas**, verifies the UVs, and ships it to the Godot game.

Read `helpers.py` for the actual code. It runs inside Blender over the Lab MCP socket (below).

## The one principle that governs everything

**Geometry = simple flat forms + silhouette. Detail + shading = painted into a low-res pixel texture.**

Do NOT model bolts, rivets, panel seams, floor grates, louvers, vents, baseboards, wood grain, or
ambient occlusion. Those are *painted*. The reference is the artist's own work — look at
`to-rust-as-we-fall/resources/models/aster-sim/aster-sim-room-hi-res_1.png`,
`desk_texture_desk.png`, `office-chair_1.png`: flat geometry, every screw/seam/gradient hand-painted.

When you catch yourself adding a Geometry-Nodes bolt grid or a modeled grate — stop. That becomes a
flat plane the artist paints. (This skill exists because the elevator got over-modeled with 3016 faces
of GN bolts/ribs/grate/louver that all had to be stripped back to a 174-face flat shell.)

## ⚠️ Draw complex shapes COMPLETELY — never randomly cut off

A recurring failure: a complex/curved shape (a round portal or mirror, a curved sofa back, a torus,
a lathe) comes out **partially built** — a ring missing segments, an uncapped cylinder, a torus that
doesn't close, faces silently deleted by a destructive op. This MUST NOT ship. Guardrails:

1. **Close the loop.** A ring/torus/lathe must connect its last segment back to its first
   (`(i+1) % SIDES`, not `i+1` which leaves a gap). Cap the ends of any tube/cylinder.
2. **Build full circles for round things** — a portal/mirror is a full closed annulus or disc, not an
   arc. Use enough segments to read as round at game distance (12–24), all the way around.
3. **Count faces before/after every destructive op** (bmesh delete, boolean, decimate, dissolve,
   `strip_faces_by_uv_x`). If the delta isn't what you intended, you cut off too much — STOP and
   inspect. (The strip op once deleted the *entire* mesh because object-mode `poly.select` didn't carry
   into edit-mode delete — that's exactly this failure. Use bmesh, verify the count.)
4. **Render from ≥2 angles and orbit the shape** before exporting. A single hero angle hides a missing
   back. Eyeball that nothing is clipped, open, or half-there.
5. **Never gate completeness on a field/normal filter.** Godot/Blender GN `EMISSION_SHAPE_DIRECTED_POINTS`
   and normal-filtered scatter sample position/normal at independent offsets (engine bug #83811) and
   drop geometry unpredictably. Build explicit geometry instead of filtering it into existence.
6. **No accidental clipping at export.** Check camera near/far and that the whole asset is inside the
   view; check the UV layout — every island fully inside 0–1, none clipped at the border.

## Driving Blender — the Lab MCP socket

Blender (open, with the official **Blender Lab MCP** add-on server running on `localhost:9876`) speaks a
null-byte-delimited JSON protocol: send `{"type":"execute","code":<py>,"strict_json":false}\0`, get back
`{"status":"ok","result":...}\0`. Two ways in:

- `run_blender_python` MCP tool (the `blender-mcp-bridge.py` stdio bridge), OR
- pipe bpy into `c:/tmp/blsend.py` from Bash: `python /c/tmp/blsend.py <<'PY' … PY`.

Assign your return data to a dict named `result`. Operators that touch UVs/meshes need a VIEW_3D
context — always wrap them in `op()` from `helpers.py` (see the gotcha below).

## Pipeline A — texture a single asset (e.g. the elevator car)

1. **Simplify.** Strip any over-modeled detail to flat surfaces (`strip_faces_by_uv_x` if it was
   collapsed to the metal swatch, else delete the detail meshes). Verify the face-count drop is sane.
2. **Realize** any Geometry-Nodes / modifiers (`realize`) — you can't bake stable UVs onto procedural
   geometry.
3. **Unwrap into ONE atlas** (`atlas_unwrap`): flat paintable surfaces → clean unique islands packed
   into the left ~82%; repetitive metal hardware (if any geometry survives) → one shared swatch in the
   reserved right strip (its geometry gives the shape; the swatch only colors it).
4. **Join** to one mesh (`join_all`) — fine for a static prop; keep separate only if Godot references
   child node names.
5. **Verify density** (`uv_checker_setup` + render): uniform squares = good; stretched rectangles = bad.
   This is the "make the textures match the UVs" step — don't skip it.
6. **Export** (`export_obj_glb` + `export_template`): OBJ+MTL and the UV-layout PNG to the gitignored
   `blender/` source dir (the artist paints over the template), GLB to
   `to-rust-as-we-fall/resources/models/<asset>/` (committed runtime, same UVs).
7. **Re-import + test** in Godot (`--import`, then the asset's scene-load/feature test), commit the GLB.
8. **Hand-paint** — the artist paints `<asset>_albedo.png` over the template (+ an `_emissive` sidecar
   for glow). Then wire it (Pipeline C).

## Pipeline B — assemble a room from mixed sources (Peris's sim)

**PLACE the new geometry with the spatial grammar, not raw coordinates** (`blender/spatial_grammar.py`,
documented in the `low-poly` skill): floors via `slab`, walls via `wall`, openings via `recess` (no
gaps), furniture via `on` (on the floor — can't float), wall decor via `on_wall` (attached — can't float
over nothing), then `validate()` for floaters/over-nothing before rendering. Hand-written coordinates are
exactly what produces gaps-in-walls / floating-decor / props-over-a-hole; relations make placement
correct by construction.

The room is built from THREE kinds of pieces; keep them in one `.blend`, all sharing the pixel grid:

- **Imported gltf props** (the plants — `import_scene.gltf`). They arrive textured; leave their UVs/mats
  alone, just place them. Do NOT re-unwrap them into the room atlas.
- **A Crocotile room** (walls/floor + the two sofas) — import it, keep its existing textures, treat it as
  the shell you build around.
- **New Blender geometry** you add — the architecture, furniture, and the **portal** (the round thing —
  a full closed annulus/disc; consider futuristic accents: a thin glowing inner ring, a beveled frame,
  floating shards — all SIMPLE forms, glow via emission, detail painted). These new pieces get the
  hand-painted atlas treatment (Pipeline A steps 2–6) on their OWN atlas; imported pieces keep theirs.

Match the reference (cozy isometric: bamboo/wood furniture, terracotta pots, hanging + standing plants,
a round wood-framed mirror, a wall art panel, a bookshelf with knick-knacks, a kiosk terminal, a low
sofa with pillows, a rug). Build only the silhouette; paint the grain/cushion-shading/book-spines.

Then ship the room to Godot via **`RoomModelBinder`** (see the project's `room_model_binder` memory and
`scripts/game/world/room_model_binder.gd`): one descriptor (root name, floor surface Y, grid origin,
occupants, gltf path, wired emissive materials) + `validate()`. Run
`tools/gltf_wire_material_sidecars.py` after EVERY re-export (the DCC tools drop emissive wiring).

## Pipeline C — wire a painted texture into Godot

- Albedo + `_emissive` (+ optional `_normals`) PNG sidecars next to the gltf, wired by
  `tools/gltf_wire_material_sidecars.py`. Emissive mask is a color-keyed subset of the albedo (the
  glowing texels), emitting the terminal green `#5ce87f` for screens/indicators.
- **Pixel-art import**: NEAREST filtering, NO mipmap blur — otherwise the pixels smear and the look dies.
- A modeled scene root must be IDENTITY (an editor-drag tilt makes the data layer "float"); set the
  floor surface height with the binder's one knob.

## Texture resolution — keep it LOW (this is pixel art)

The project pixel grid is **16 px / world unit** (1/16 unit). Size the atlas to that density:

    atlas_px ≈ sqrt(total_surface_area_in_sq_units) * 16 / sqrt(packing_efficiency≈0.6)

- Elevator interior (~160 sq units) → **256**.
- A whole busy room (the aster office) → **512**.
- A single prop (chair, terminal, pot) → **64–128**.

Round to a power of two. When in doubt, go smaller — the style is low-res. Author the texture at the
surface's aspect ratio so it isn't stretched.

## Tile-atlas variant — 32 px/m hand-repaintable tiles with VARIATIONS (the project's house style)

The project's established texture technique (not the unique-island atlas above — this is the TILING one):
- **Pixel density = 32 px / meter.** A 1 m tile is a 32×32 px square. (This is the project's denser
  tiling-art density; the older one-atlas-per-room work used ~16 px/unit.)
- **One ATLAS SHEET of tiles**: rows = materials (rock, sand, metal, grate, rust, biolum, deck, panel…),
  COLUMNS = variations of that material as ADJACENT tiles on the sheet. Geometry SAMPLES a tile and the
  tile REPEATS across the surface; picking a different adjacent column per face/region gives handmade
  variety without seams reading as a grid.
- **Why**: each tile is a tiny pixel-art square → trivial to repaint, and the variations keep large
  surfaces from looking flat/stamped. Looks hand-made.
- **Generate a starting point procedurally** (see `blender/textures/` + the `gen_tiles.py` recipe):
  per material a LIMITED palette (3–5 shades) + a STRUCTURED painter (rock = speckle + cracks +
  highlights; metal = panel seam + rivets; grate = crosshatch bars; rust = corrosion blotches; biolum =
  glow clusters; deck = diamond-plate; sand = speckle + ripples), with a deterministic per-(material,
  variation) seed. Avoid pure noise — deliberate features read as pixel art. The user repaints from there.
- **Apply (tiling)**: one material per tile, Image Texture set `interpolation = 'Closest'` +
  `extension = 'REPEAT'`, and cube-project the surface UVs at **TILE = 1.0 m** (UV = world position in
  meters) so one 32-px tile lands per meter. (`extract tile -> own image -> REPEAT` is simplest;
  REPEAT-ing a sub-rect of the full atlas needs a fract-within-tile shader, so crop tiles out instead.)
- Atlas + tiles live in `blender/textures/` (source). When a model ships, bake/wire the chosen tiles as
  its texture (Closest filter, no mipmap) per the sidecar pipeline.

## Gotchas (all hit in practice)

- **Operator context.** `smart_project` / `pack_islands` / `export_layout` / `join` / `mode_set` fail
  with "context is incorrect" from a socket. Wrap in `op()` (VIEW_3D `temp_override`). `smart_project`'s
  poll also fails on a **0-face** mesh — if it errors, check you didn't just delete everything.
- **Object-mode `poly.select` does NOT reliably carry into edit-mode `mesh.delete`** — it can wipe the
  whole mesh. Delete faces with **bmesh** in object mode (`strip_faces_by_uv_x`), and verify the count.
- **Realize before UV.** UVs baked onto live GN geometry are unstable; `realize()` first.
- **Blender Z-up → Godot Y-up:** `export_yup=True` (gltf) / `up_axis='Y', forward_axis='NEGATIVE_Z'`
  (obj). `export_apply=True` realizes modifiers on export.
- **Don't overwrite the editable `.blend`** with a destructive (joined/realized) state until the exports
  are confirmed — save the joined/stripped master separately or commit the GLB first so git has a copy.
- **Source vs runtime split:** `.blend`, `.obj`, `.mtl`, UV templates, source art live in the gitignored
  `blender/` dir. Only the game-ready GLB + sidecars go under `to-rust-as-we-fall/resources/` (committed).
- **Never TILE a SWATCH atlas — keep its UVs in [0,1].** A *swatch* atlas (solid colour rectangles on a
  TRANSPARENT background, e.g. Crocotile `peris-sim_7`/`_16`) is for flat low-poly colouring: each piece
  samples ONE swatch, UVs inside [0,1]. Do NOT give it tiling/cube-project UVs — out-of-range UVs wrap
  (REPEAT) and sample the transparent BACKGROUND between swatches, and since these materials are OPAQUE
  (alpha ignored) that background's RGB (usually 0,0,0) renders as a **black checker**. This bit hard: a
  furniture-tiling pass put the Peris rug at UV u[-5.3..10] → the whole room floor read as a black/cream
  checker that looked exactly like a broken floor *texture* (it wasn't — the floor was solid; the flat
  Rug on top was bleeding the void). Only TILE a fully-OPAQUE seamless texture (the 32 px/m tile sheets
  above); SAMPLE a swatch atlas. A `Image.detect_alpha() != ALPHA_NONE` texture with any UV outside [0,1]
  is the red flag — `--test-peris-furniture-uvs` guards exactly this.

## What this skill does NOT cover

- Building the geometry from scratch / Blockbench style → `low-poly` skill.
- Plants → `stylized-plant-builder` skill (and Peris's plants are already gltf — just import them).
- The Godot scene logic (sequence, grid, interactables) → the project's scene-architecture rules.
