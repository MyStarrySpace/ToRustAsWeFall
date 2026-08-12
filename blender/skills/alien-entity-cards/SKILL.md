---
name: alien-entity-cards
description: Build alien flora/fauna entities for ToRustAsWeFall in Blender using pixel-art textured cards plus minimal 3D primitives. Use when creating or revising any ENT-### entity from the roster docs, especially plants with leaf/frond/flower silhouettes, glowing veins or markings, or state variants (wild/tended/spent etc.). Derived from stylized-plant-builder (Peris sim) — same card+texture pipeline, different palette and conventions.
---

# Alien entity card builder

Card+pixel-texture pipeline for the ENT-### roster, adapted from
`skills/stylized-plant-builder` (Peris sim plants). The plants skill's
footguns all still apply — read it first. This file adds the
roster-specific conventions and the deltas.

## Core architecture

An entity = **stage-grounding** + 2 generated layers:

1. **Structure** — minimal 3D primitives only where a card can't carry it:
   stalks/vines (cylinders or tube-swept beziers), translucent bodies,
   substrate slabs/tiles/walls. Keep these LOW-POLY and matte.
2. **Detail** — pixel-art textured quad cards for everything with a
   silhouette: leaves, fronds, flowers, buds, roots, wall faces, ground
   tufts. NEVER model serrated/lobed silhouettes in geometry — draw them
   into the texture's alpha (this was the ENT-014 v2 mistake: mesh fronds
   read as sticks and plates).

## Scene conventions (EntityRoster scene)

- One collection per entity/state: `ENT-014_tended`, `ENT-008_cloaked`...
  Object names prefixed `E014t_`. Rebuilds go through `ent_helpers.C(name)`
  which empties the collection (idempotent).
- Shared render rig in `RIG`: `RosterCam`, KeyL/FillL/RimL, `Stage` disc.
  `ent_helpers.frame(coll)` aims the camera at a collection's bbox;
  `render_coll(name, path, direction=...)` isolates + renders.
- Previews: 900×900 EEVEE to `previews/<COLL>.png`. Wall-mounted entities
  render from `(0.4,-1.8,0.55)`; mats from high `(0.8,-1.2,1.4)`.
- Default facing: cards face **−Y** (toward camera at default direction).
  Wall backdrops sit at +Y behind the entity.

## Palette (roster, NOT the peris-sim greens)

Restricted palette: muted teals/greens dominant, rust-red + warm cream
accents, near-black background. RGB 0-255 for textures:

```
TEAL_DEEP    = (10, 46, 42)     # frond/blade body
TEAL_EDGE    = (16, 70, 60)     # blade edge highlight
GLOW_CYAN    = (60, 240, 200)   # emissive veins/markings (ENT-014 family)
GLOW_DIM     = (30, 140, 120)   # vein falloff pixel
GREEN_MID    = (78, 116, 56)    # healthy foliage
GREEN_DARK   = (50, 82, 40)
GREEN_LIGHT  = (104, 142, 68)
RUST         = (150, 76, 34)    # converted/spent foliage
RUST_DARK    = (96, 44, 22)
RUST_DEEP    = (60, 30, 16)
FLOWER_RED   = (168, 64, 30)    # ENT-016 trumpet
FLOWER_RIB   = (118, 40, 22)
FLOWER_RIM   = (212, 122, 52)
AMBER_GLOW   = (235, 170, 70)   # throats, resin (emission map)
CREAM        = (210, 190, 150)
BARK         = (86, 58, 36)     # vines/stalks
BARK_DARK    = (52, 34, 22)
STONE        = (38, 40, 38)     # walls/masonry (±8 per-block jitter)
MORTAR       = (16, 18, 18)
SOIL         = (26, 19, 12)
```

Emission is a SEPARATE texture (glow pixels on transparent black), wired
to Emission Color with per-state strength — states share textures and
differ by `Emission Strength` (wild ≈ 2, tended ≈ 7, stressed ≈ 16) plus
count/scale changes. Don't redraw textures per state unless the colorway
itself changes (ENT-015's three colorways are redraws).

## Texture rules (inherits Footguns #14/#15 from plants skill)

- Pixel-art at native low res: 12–32 px short side, 24–72 px long side.
  No anti-aliasing, no gradients — stepped shades from the palette.
- Draw with base/attachment at **bottom-center** (vertical cards) or
  **left-center** (horizontal leaves). UV layout: quad corners
  (0,0)(1,0)(1,1)(0,1), V = up the card.
- In Blender: Image Texture node `interpolation='Closest'`,
  `tex.Color → Base Color`, `tex.Alpha → BSDF.Alpha`. Alpha via
  HASHED/DITHERED (try `blend_method='HASHED'`, fall back to
  `surface_render_method='DITHERED'` on Blender 5+). OPAQUE for
  everything without cutout.
- **Audit sheet is non-negotiable**: after drawing, compose all textures
  ×6 nearest-neighbor into `textures/entity/_audit.png` and LOOK at it
  before building. Verify silhouette, palette, base anchor position.

## Card rules

- 4-vert quad, origin at the BASE (attachment point), built from pydata
  with verts `(-w/2,0,0)(w/2,0,0)(w/2,0,h)(-w/2,0,h)` — placement is then
  `obj.location = attach_point`, rotation aims the card. (Plants skill
  Footgun #12.)
- Variety: per-card random yaw/tilt jitter and ±15% scale, always
  (Footgun #3). For carpets/clusters use crossed pairs (two quads at 90°).
- Fans (ENT-014): cards in a near-planar fan facing −Y, center card
  tallest, flanking pairs smaller with increasing yaw — matches the
  diorama-on-dark reads of the concept art.

## Blender-5 / EEVEE deltas learned this project

- `scn.render.engine = 'BLENDER_EEVEE'` (5.x merged Next); transparency
  needs `mt.surface_render_method = 'BLENDED'` (legacy `blend_method`
  may not exist — wrap both in try/except).
- Translucent body + internal glow (ENT-002/007/012): outer shell alpha
  0.3–0.45, emissive elements must sit OUTSIDE any opaque inner mesh —
  granules hidden inside a core sphere render invisible (ENT-007 v1 bug).
- Soft "haze/mist/dust": stacks of alpha 0.07–0.12 spheres still work
  fine and read painterly at preview distance — don't reach for volumes.
- Big batches of `bpy.ops` primitives (~400+) can exceed the MCP timeout
  but DO complete — verify with a collection-count query instead of
  re-running (re-running is safe anyway since `C()` empties collections).

## Entity-specific recipes (validated)

- **ENT-014**: glow-vein frond card (28×56) + emission map; 5–7 card fan;
  3D pebble mound + faint emissive ground disc. States = emission
  strength + frond count.
- **ENT-015**: square masonry planter (soil box + perimeter stone cubes,
  slight height jitter) + 5×6 grid of crossed cluster cards (22×22) with
  colorway weights — healthy ≈ 85/15 green/rust, partially ≈ 50/50,
  spent = all rust. Reference: three-tile progression sheet.
- **ENT-016**: flat roots card (44×44) on ground + radial rosette of
  lance leaf cards (36×12, droop 55–75°) + 3D stalk + top cards:
  bloom = 3 crossed trumpet cards w/ amber throat emission;
  wild = crossed bud cards, broad green rosette;
  spent = crossed wilt cards on bent stalk, dry leaves, rust dust specks.
- **ENT-020**: stone-wall card backdrop (52×72 texture) + 3D gnarled
  vine chain climbing in an S (main strand + thin spiral secondary,
  grip tufts into wall at nodes). Tended adds small green tuft cards at
  nodes. Harvested/deployed variants stay primitive-based.

## Verification (same as plants skill, roster flavor)

Render the state collection, open it NEXT TO the user's reference, and
walk the comparison checklist (silhouette / density / palette / glow
placement / state read). List deltas explicitly, fix deltas — not the
easiest thing. Re-render before declaring done.
