---
name: stylized-plant
description: Build a stylized low-poly Blockbench-aesthetic potted plant in Blender via the Blender MCP. Use when the user asks for a 3D model of a houseplant, a fern, a succulent, etc. with a "low-poly", "Blockbench", "pixel-art texture" or similar look. The skill produces a `.blend` file and a Cycles render with consistent stylization across plants.
---

# Stylized Plant Skill

A reusable pipeline for building stylized low-poly Blockbench-style potted plants. Use this when the user asks for a 3D model of a houseplant in this aesthetic. The skill produces a `.blend` and a Cycles render.

Read `helpers.py` (in this folder) for the actual code. This file is the design playbook — what worked, what didn't, what to avoid.

**Before modeling**: gather references. See the "Reference gathering" section in the sibling `low-poly` skill — it applies here too. For plants specifically, search for "[plant name] real photo" AND "[plant name] illustration" AND "[plant name] low poly" so you get botanical accuracy + stylization cues.

## High-level pipeline

1. **Wipe the scene** — clear all `bpy.data.objects/meshes/materials/curves/images/textures/lights/cameras` and reset the World shader so the build is fully reproducible.
2. **Generate pixel-art textures** as `bpy.data.images` from a small grid of (r,g,b,a) tuples (typically 8-32 px per side). Pack into the .blend so the file is portable.
3. **Build the pot, soil, saucer, floor** as bmesh octagonal geometry with `use_smooth = False` (hard facets). Pot is lathed from a 2D `(r, z)` profile.
4. **Build the plant geometry** — depends on plant type (see "Leaf attachment patterns" below).
5. **Place leaves/stems with stratified angular slots** + BVH collision detection against the pot.
6. **Set up materials** with `Closest` interpolation (crucial for pixel art), alpha cutout for cards, optional subsurface scattering for that real-leaf glow.
7. **Lights and camera**: 3-point area lighting + camera framed for the silhouette.
8. **Render at Cycles 256 samples**, save `.blend` and `.png` to outputs.

## Leaf attachment patterns

Pick the right pattern based on the leaf shape complexity:

### Pattern A — 3D mesh disc (Pilea, Money plant, anything with a clearly 3D leaf)
Use when the leaf is small, round, has volume. Build an N-sided disc with thickness via bmesh, dome the center slightly, and use the closed-mesh's natural normal direction. `bmesh.ops.recalc_face_normals` works correctly here.

### Pattern B — Flat textured card (Calathea, Peace lily, Jade, Haworthia)
Use when the leaf has a strong 2D pattern that's easier to draw than to model (stripes, herringbone, variegation). The leaf is a single quad with an alpha-cutout pixel-art texture. **CRITICAL**: see "Face normal bug" below.

### Pattern C — Curved bezier strip (Boston fern, Pothos vine, Spider plant ribbon, Jasmine branch)
Use when the leaf/frond/vine is long and arcing. Subdivide a quadratic or cubic bezier into N segments, place a left/right vertex pair at each control point along the perpendicular width axis, and connect the pairs into a strip of quads.

## ⚠️ FACE NORMAL BUG

The biggest pitfall I hit. **Default vertex orders in flat card builders produce face normals pointing DOWN** (CW from +Z view = right-hand rule normal points -Z). Cycles renders alpha-cutout double-sided so the *texture* shows correctly, but lighting, shading, and SSS all hit the wrong side, and `bmesh.ops.recalc_face_normals()` doesn't reliably re-orient isolated planar quads — different leaves end up with normals flipped in different directions.

**Fix in two parts**:

1. **Vertex order**: For a flat quad with `bl, br, tr, tl` (bottom-left through top-left), use `[bl, tl, tr, br]`. For a bezier strip with `(left_i, right_i)` pairs, use `(left_i, left_{i+1}, right_{i+1}, right_i)`. Both are CCW from +Z.

2. **Force-up check**: After `bm.faces.new(...)`, call:
   ```python
   bm.faces.ensure_lookup_table()
   if face.normal.z < 0:
       face.normal_flip()
   ```

Always call this. It's a no-op when the order is already correct, and a save when it's not.

3. **UV from world position, not loop index**: After a possible flip, loop-index-based UVs go wrong. Compute UVs from the vertex position:
   ```python
   rel = vert.co - base_pos
   u = (rel.dot(local_x) / (width)) + 0.5
   v = rel.dot(leaf_dir) / length
   ```

## ⚠️ Twist around leaf axis — use sparingly

It's tempting to add `random.uniform(-π, π)` twist around `leaf_dir` for variety. **Don't.** A twist of ±π/2 makes the leaf face point sideways relative to up, producing edge-on "blowing in the wind" appearance.

Variety should come from **leaf direction variation**, not from twisting around it. Use `random.uniform(-0.15, 0.15)` max.

## ⚠️ Texture aspect ratio MUST match card aspect

A texture authored at 128×128 will appear visually "fat" when stretched onto a long, narrow card mesh. Image dimensions should approximate `(card_width / card_length) * texture_height`. For a fern frond at 0.20 × 1.10, a 20×110 image gives 1:1 pixel-to-card-aspect mapping.

## ⚠️ Frond textures need transparent gaps between pinnae

A continuous-fill stripe pattern reads as "wide solid leaf with grooves" — not as feathery fronds. Real ferns have *separate* pinnae attached to a central rachis with **gaps of empty air between them**. See `fern_frond_grid()` in helpers.py for the v13 recipe (PINNA_SPACING=4, PINNA_HEIGHT=3, MAX_EXTENT=6).

## ⚠️ Bezier choice for fronds: prefer quadratic over cubic

Cubic beziers introduce a subtle twist artifact when the strip-of-quads is built along the curve — leaves "spin to the side" instead of draping straight down. **Use quadratic** for fronds. Reserve cubic for cases where you need an inflection point (e.g. Pothos vine that goes up and over the rim).

## Subsurface scattering for leaves

```python
bsdf.inputs['Subsurface Weight'].default_value = 0.18-0.22       # leaves
bsdf.inputs['Subsurface Weight'].default_value = 0.30            # white flowers/spathes
bsdf.inputs['Subsurface Radius'].default_value = (0.45, 0.75, 0.25)  # green-biased
bsdf.inputs['Subsurface Scale'].default_value = 0.08-0.10
```

Green-biased radius (G > R > B) gives the warm green glow when light scatters through the leaf.

## Reference

See `helpers.py` for shared code (BVH, card builders, pixel-image helper, material setup, fern_frond_grid).
See `references/plant_recipes.md` for per-plant parameters.
See the `.blend` files in this folder for one full reference build per plant.
