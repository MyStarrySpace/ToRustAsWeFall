# Concept-Art Prompts — the reference-first asset pipeline

Every model in the game gets built FROM a reference image, never from imagination
(the prop-first ruling: primitives assembled without a reference read as sloppy,
especially organics). This directory holds the image-generation prompts that
produce those references, split by category so no single file grows unbounded:

- [flora.md](flora.md) — the tendable species. Mostly POINTERS: canonical prompts
  already live in `reference-docs/flora_image_prompts.md`, and generated cards +
  card models already exist (`blender/previews/ENT-0xx_*.png`,
  `blender/alien_entities_v1/v2.blend`). Only the species without cards get new
  prompts here.
- [fauna.md](fauna.md) — the thirteen canonical threats (`reference-docs/
  fauna_roster.md`). Seeded with the Plumbing Power Project's guards first.
- [plumbing_power_project.md](plumbing_power_project.md) — the district props for
  the wash relay / channels stretch (canonical district name: the Plumbing Power
  Project, GDD 4.4). One prompt per asset-sheet piece.
- [structures.md](structures.md) — the district-agnostic generation-vocabulary
  bodies (`data/generation/content_palette.json` structures). Rendered in the
  channels palette for now; other districts re-emit with their palette rows.

## Workflow

1. Copy a prompt into the image generator. Every prompt is SELF-CONTAINED — the
   style preamble is baked into each one.
2. Save the generated art under `reference-images/concept/<category>/<id>.png`
   (gitignored, like all reference imagery — note Grep/Glob skip it; use ls).
3. Build or rework the Blender piece against the image (crop-vs-prop comparison
   is the acceptance test), through `blender/archetypes/build_archetype_pieces.py`.
4. The piece lands on the labeled asset sheet (`archetype_pieces.blend` /
   `C:\tmp\archetype_asset_sheet.png`) for director approval before placement.

## Shared style core

Every prompt embeds this voice (adapted from the canonical flora prompt file):

> Voxel and low-poly base geometry with painterly atmospheric textures applied
> over it. Hand-painted brush detail visible on every surface. Diorama-on-dark
> composition: single subject centered, isolated against a near-black void,
> three-quarter hero view. Game-asset concept sheet framing.

Category files extend it with their palette (the Plumbing Power Project adds the
wet iron + cyan/red/purple accent language). Laws that bind every prompt:

- **Canon first** — names, roles, and morphology come from the taxonomies/GDD;
  a prompt never invents a species, mechanic, or landmark.
- **Wordless text** — signage is abstract dot-matrix glyph patterns, NEVER
  legible letters (wayfinding is light and color).
- **Portal law** — portals glow RED / PURPLE / BLUE only; dormant portals are
  dark. Gold belongs to the Curecumin item alone.
- **Palette authority** — colors named in prompts correspond to roles in
  `data/palettes/level_palettes.json`; the built piece must route through them.
