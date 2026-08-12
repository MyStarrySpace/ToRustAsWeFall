---
name: sobel-stylized
description: Apply cel-shaded / pixel-art post-processing to Blender scenes — Sobel-edge inking from depth+normal passes, optionally angle-colored edges, plus directional face shading and a UV-checker diagnostic pass. Use when the user wants stylized rendering with crisp inked outlines on top of low-poly geometry.
---

# Sobel-Stylized Rendering Skill

A reusable post-processing pipeline that turns plain Cycles renders into cel-shaded / inked illustration looks. Built and refined while iterating on the elevator and chair scenes (the disco→clean→inked progression).

The technique is **post-processing only** — your materials, geometry, and lighting stay simple. The "lines" come from the Compositor reading the depth/normal buffers, NOT from textures or geometry.

Read `helpers.py` for the actual code.

## What this skill produces

- **Inked silhouettes**: dark lines at every geometric edge (object boundaries, face folds)
- **Directional face shading**: top-facing surfaces lighter, bottom-facing darker — adds depth without explicit lighting setup
- **Angle-colored edges** (optional): edge color shifts with the underlying surface direction for a luminous, hand-drawn feel
- **UV checkerboard diagnostic** (optional): swap all materials for a colored checker to debug UV mapping

Combined effect reads like Stardew Valley / Eastward / Sea of Stars — chunky stylized geometry with crisp lines.

## When to use

- The user asks for "cel-shaded", "inked", "pixel-art-look", "Stardew-like", "comic-book look"
- Geometry has clear silhouettes worth outlining (low-poly stylized models)
- You've already built the scene normally and just want to "stylize" it without re-modeling
- Solid-color materials are preferred over textured surfaces (lines compensate for the lack of texture detail)

## How the Sobel-edge pass works

The Compositor reads two render passes and applies edge detection to each:

1. **Position pass** (`use_pass_position = True`): world coords per pixel. Sobel of position → strong response wherever two adjacent pixels are on different surfaces. Captures **silhouettes** — outline of the chair against the background, outline of one cushion against another.
2. **Normal pass** (`use_pass_normal = True`): world-space normals per pixel. Sobel of normals → strong response where face normals change direction. Captures **face folds** — the seam between two faces of a cube even though they're on the same object.

Each Sobel result is converted to grayscale, then thresholded with a tight ColorRamp to get a binary mask. The two masks are combined with `Math.MAXIMUM` (so either edge type triggers a line). The combined mask drives a final Mix node that blends the rendered image with a black (or colored) line.

## Compositor graph

```
RenderLayers ──┬── Position ── Filter[Sobel] ── RGBToBW ── ColorRamp[threshold] ──┐
               │                                                                  │
               ├── Normal   ── Filter[Sobel] ── RGBToBW ── ColorRamp[threshold] ──┤
               │                                                                  │
               │                                          Math[MAXIMUM] ──────────┤── mask ──┐
               │                                                                             │
               └── Image ─────────────────────────────────────────────────────── Mix[MIX] ──── Output
                                                                                  ↑           ↑
                                                                            line color    final
```

Critical Blender 5.x notes:
- Use `scene.compositing_node_group`, not `scene.node_tree` (renamed)
- Composite output is `NodeGroupOutput` with an `Image` socket on the group's interface, not `CompositorNodeComposite`
- Use `ShaderNodeMath`, `ShaderNodeMixRGB`, `ShaderNodeValToRGB` (compositor uses shader-node prefixed types now)
- Filter node's type is now an input socket: `filter_node.inputs['Type'].default_value = 'Sobel'` (capital S)

## Tuning the lines

Three knobs control how the lines appear:

| Knob | Effect |
|---|---|
| `position_th` ColorRamp range | Tighter (e.g. `0.05..0.06`) = more silhouette outlines; wider (`0.05..0.20`) = only strongest silhouettes |
| `normal_th` ColorRamp range | Tighter = more face-fold lines (every cuboid edge); wider = only sharp creases |
| `mask_mul` factor | 1.0 = solid black; 0.5 = ghosted half-strength; <0.3 = barely there |

Start with `position 0.05..0.10`, `normal 0.10..0.20`, `mask 1.0`.

## Angle-colored edges

Instead of pure black lines, drive the line color from the surface normal. Top-facing surfaces produce **lighter** edge color; downward-facing surfaces produce **darker** color. The visual effect is "rim-lit" lines that pulse with surface orientation.

Wiring (replaces the constant RGB line color):

```
RenderLayers.Normal ── SeparateXYZ ── Z ── MapRange[-1,1 → 0,1] ── ColorRamp ── line color
```

The ColorRamp is where you choose the palette: position 0.0 = darkest (downward edges), 1.0 = lightest (upward edges). Add intermediate stops for richer gradient.

For the teal palette this came out to:
- 0.0: `(0.02, 0.04, 0.04)` near-black
- 0.4: `(0.06, 0.18, 0.16)` dark teal
- 0.7: `(0.22, 0.45, 0.40)` mid-teal
- 1.0: `(0.55, 0.85, 0.75)` light mint

## Directional face shading

Even with solid-color materials, you can get directional depth by multiplying the base color by a factor derived from the face normal's Z component. Top-facing faces brighten, bottom-facing darken.

Material insert (between Image Texture and Principled BSDF Base Color):

```
Geometry::Normal ── SeparateXYZ ── Z ── MapRange[-1,1 → dark_factor, light_factor] ──┐
                                                                                    ──── CombineColor ── Mix[MULTIPLY] ── BSDF.Base Color
ImageTexture.Color ─────────────────────────────────────────────────────────────────────────────────────┘
```

Recommended: `dark_factor = 0.55`, `light_factor = 1.20`. So top of cushion = 1.20× base, bottom = 0.55× base. Subtle but adds a lot of read.

Skip this on emission materials (glow accents shouldn't be darkened by direction).

## UV checkerboard diagnostic

A common 3D workflow trick: temporarily replace all materials with a checker pattern to see how UVs map. Stretched UVs show the checker squashed; misaligned UVs show abrupt seams.

The helper builds two-level Checker Textures (coarse red/blue + fine black/white) multiplied together, scaled by the object's UVs. Useful for diagnosing mapping issues before committing to a final atlas.

To use: `apply_uv_checker_to_scene()` — saves the original materials, applies the checker mat to all mesh objects. Render, inspect, then call `restore_materials()` to revert.

## Combining all three

The chair's final look uses:
1. Atlas-based solid color materials with directional face shading
2. Compositor Sobel edges with angle-driven color
3. Standard Cycles render

The result is an illustration-style image where:
- Each chair part has its own clear silhouette (Sobel)
- Surfaces show gradient from top to bottom (directional shading)
- Edges have a subtle color shift based on direction (angle-colored Sobel)

No texture painting required.

## Baking lines into textures (alternative to compositor)

The compositor approach above runs every frame. To get permanent edges baked into the UVs (for export, faster rendering, animation stability), use the bake pipeline instead.

**Why bake**: Sobel reads screen-space depth/normal — fine for stills, but lines re-compute per frame, the resolution depends on render size, and they flicker on sub-pixel camera motion. Baked edges are part of the texture, render the same from every angle, and export with the model.

### Two bake approaches

**A. Mesh-edge rasterization (recommended — gives crisp lines)**

Skip Cycles bake entirely. Walk every mesh edge in Python, decide if it's "sharp" (boundary edge OR angle between adjacent face normals > 20°), find its UV positions in each adjacent face, and rasterize a Bresenham line in the texture at those UV coords.

```python
bake_edges_via_rasterization(chair_parts, image_size=256,
                              sharp_angle_deg=20, line_thickness=1)
```

This produces a true wireframe of the geometric edges in UV space. Crisp 1-pixel lines exactly on every cube edge / cushion seam / silhouette boundary. No falloff, no AO blur.

**B. Pointiness bake via Cycles** (gives soft AO-like result)

Use a Pointiness shader → ColorRamp → Emission → bake EMIT. Older alternative — produces softer, more AO-like result. Useful if you want a smooth darkening near edges rather than crisp lines.

### Texture resolution & filtering

The bake target image's resolution drives the pixel-art chunkiness in the final render.

- `image_size=64` — chunky, visibly pixelated edges. Matches Blockbench / voxel-art aesthetic.
- `image_size=128` — moderate. Edges still readable as discrete pixels at typical render distances.
- `image_size=256` — crisp 1-pixel lines that look smooth at typical render distances. Use for non-pixelart looks.
- `image_size=512+` — overkill for this aesthetic. Lines become AA-ish blurs.

**Always set the edge texture node to `interpolation='Closest'`** (not Linear). Without this, Blender bilinearly samples the texture and the chunky pixels become smeared. Closest gives the "no anti-aliasing" pixel-art look where each texel renders as a sharp square.

If the bake size is small (≤64) and `line_thickness=1`, lines may break up at oblique angles. Bump to `line_thickness=2` for guaranteed continuity at low res.

### Recipe (rasterization, recommended):

1. **Smart UV unwrap each object** — every part needs unique non-overlapping UVs. `bpy.ops.uv.smart_project(island_margin=0.04, angle_limit=66.0)` per object works well. Each part gets its own [0,1] UV space.

2. **Create a target image per object** (or one shared atlas with all UVs packed). 256×256 per part is fine for 3D-to-2D projected outlines.

3. **Build a "bake material"** with:
   - `Geometry::Pointiness` → output goes to a `ColorRamp` (white below threshold, black above). Wider threshold range = more edges captured. `0.40 → 1.0 white`, `0.55 → 0.0 black` gives strong outlines.
   - `Emission` shader fed the ColorRamp output
   - An `Image Texture` node containing the bake target image, **selected and active** (Cycles requires this — `for n in nodes: n.select = False; tex.select = True; tree.nodes.active = tex`)

4. **Bake** with `bpy.ops.object.bake(type='EMIT')`. Settings: `cycles.bake_type = 'EMIT'`, `render.bake.use_clear = True`, `render.bake.margin = 4` to bleed pixels past UV edges (avoids seams).

5. **Use the baked image** in the final material as a multiply over base color:
   - `RGB(base_color) → Mix[MULTIPLY] → BSDF.Base Color`
   - `ImageTexture(baked_edges) → Mix[MULTIPLY].input2`
   - White edges = base color, black edges = darkened (the inked outline)

6. (Optional) chain in `add_directional_shading()` after the multiply for full stylization without needing the compositor.

The bake captures Pointiness, which is the closest equivalent to depth-Sobel applied per-vertex. It picks up real geometric edges (cube corners, cushion-segment seams) and ignores flat surfaces. The result is similar to what the compositor draws but lives permanently in the texture.

**Trade-off vs compositor**: Bake doesn't have a "magnitude × direction" component, so all lines come out the same color. To get angle-colored edges with bake, either store the normal Z in a separate channel of the bake (e.g., RGB → R=edge_mask, G=normal_z, B=unused) and recombine in the shader, or do two bakes.

## What this skill does NOT cover

- **Sub-pixel-accurate lines**: Compositor Sobel resolution = render resolution. Render at 2× and downsample for cleaner lines.
- **Animation**: compositor lines flicker at sub-pixel motion. Use the bake pipeline above for stable animated outlines, or add Freestyle.
- **One-pass bake into shared atlas**: the helpers bake to per-object images. Packing all UVs into one shared atlas image is doable but requires UV island packing and per-object UV scaling — not yet automated.

## Reference implementations

- `helpers.py` — `setup_sobel_compositor(scene)`, `add_directional_shading(material)`, `apply_uv_checker_to_scene()`
- `aster-sim/futuristic_floating_chair_v12_angle_lines.png` — the chair render with all three techniques combined
- `elevator/scifi_elevator_v5_sobel.png` — the same setup applied to the cyberpunk elevator scene
