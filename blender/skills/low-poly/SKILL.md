---
name: low-poly
description: Build low-poly Blockbench-aesthetic 3D assets in Blender via the Blender MCP. Use when the user asks for a stylized low-poly model with pixel-art textures, hard facets, blocky geometry — chairs, props, vehicles, buildings, anything except plants (use stylized-plant for those). Produces `.blend` + Cycles render.
---

# Low-Poly Blockbench Skill

A reusable pipeline for building stylized low-poly Blockbench-style 3D assets. The visual signature: chunky faceted geometry, pixel-art textures with crisp `Closest` filtering, no smooth shading, simple silhouettes that read at a glance.

The plant-specific skill (`stylized-plant`) is built on this same foundation but adds leaf/stem-specific helpers. For a chair, computer, weapon, vehicle, etc., use this skill.

Read `helpers.py` for the actual code.

## Visual signature (the things that make it "Blockbench-y")

1. **Hard facets only** — `use_smooth = False` on every polygon. No subdivision surfaces. No smooth shading. Cuboids are visibly cuboid.
2. **Octagonal/hexagonal substitutes for circles** — never use a 32-sided cylinder when 6 or 8 sides will do. The reduced sidedness is what gives the chunky look.
3. **Pixel-art textures** — small grids (8-32 px per side typically), `tex.interpolation = 'Closest'`, packed into the .blend.
4. **Limited material count** — re-use the same 3-5 materials across the whole scene rather than authoring a new one per object.
5. **Visible silhouette over fine detail** — a viewer should recognize the object from 50% size in 1 second.

## High-level pipeline

0. **Gather references** — see the Reference Gathering section below. **Don't skip this.** Modeling without refs produces generic-looking blobs.
1. **Wipe scene** — clear all objects, meshes, materials, curves, images, textures, lights, cameras. Reset world.
2. **Plan the silhouette** — sketch (mentally) the object as a stack of primitives. A chair is: seat box + back box + arm rails + base. Don't model what you wouldn't draw.
3. **Build pixel-art textures** as `bpy.data.images` from RGBA grids. Pack into the .blend.
4. **Build geometry** as bmesh primitives — boxes, octagonal lathes, capped cylinders. `use_smooth = False` everywhere.
5. **Materials** with Principled BSDF + image texture + Closest filtering. Optional SSS for organic things.
6. **3-point area lighting** + camera framed for the silhouette.
7. **Render at Cycles 256 samples**, Filmic + Medium-High Contrast view transform.
8. **Save .blend + .png** to the project folder.

## Reference gathering — DO THIS BEFORE MODELING

**Always start by looking at real examples.** Modeling from imagination produces generic, dated-looking results. 5 minutes of reference research prevents an hour of "it doesn't look right" iteration.

### When to gather references

- New object type the skill hasn't built before (chair, vehicle, weapon, etc.)
- User asks for a specific style ("cyberpunk", "art-deco", "Studio Ghibli", "Blockbench")
- User says the previous attempt "looks dumb" or "doesn't feel right" — that's a sign the model lacks visual grounding
- Anytime the user gives a one-word style descriptor without further detail

### What to look for in references (the checklist)

For each reference image, note:

1. **Silhouette** — what's the overall shape from a flat side view? A chair: tall narrow back + wide low seat + projecting armrests.
2. **Proportions** — back-height vs seat-width vs armrest-projection ratios. Get these wrong and the object reads as off even if every detail is correct.
3. **Distinctive features** — what makes this style THIS style? Sci-fi chair: floating base, glowing accent, exposed mechanism. Cottagecore chair: wooden frame, floral cushion, curved back. The 1-2 most distinctive features must make it into the model.
4. **Color palette** — pull 3-5 colors. Note which is dominant, which is accent.
5. **Material breakdown** — soft vs hard, matte vs gloss, opaque vs glowing. Where do the materials transition?
6. **Repeating elements** — most objects have rhythmic detail (chair stitches, vehicle panel lines). Skipping these makes the model feel under-detailed.

### Tools — pick the right one

**`WebSearch`** — fast first pass. Use for keyword discovery and link gathering. Cheap, gets you 10 results in one call. The text summaries are okay but you don't actually SEE the images.

```
Examples:
WebSearch("low poly futuristic gaming chair reclined cushioned")
WebSearch("blockbench style sci-fi furniture references")
WebSearch("art deco chair silhouette black and white sketch")
```

**Claude in Chrome MCP** (`mcp__Claude_in_Chrome__*`) — use this when you need to actually SEE images. Open Google Images, Pinterest, ArtStation, or Sketchfab and look at the thumbnails directly. The browser tools can take screenshots and read the page DOM, so you can study a moodboard visually.

```
Workflow:
1. tabs_create_mcp → tabs_context_mcp to get a tab id
2. navigate("https://www.google.com/search?q=blockbench+chair&tbm=isch", tabId)
3. computer screenshot to view the results
4. Identify 3-5 promising thumbnails — describe what you see in your reasoning
5. Navigate to interesting individual results for closer study
```

**`WebFetch`** — fetch a specific page's text/HTML. Useful for reading a design article or model description, but it can't render images so it's a complement to WebSearch, not a replacement.

### The minimum viable reference pass

For ANY new low-poly asset:

1. Run 1-2 `WebSearch` queries with style + object type ("low poly futuristic chair", "blockbench voxel chair").
2. Open Google Images via Claude in Chrome and screenshot the top results — this is the cheapest way to get actual visual references.
3. In your reasoning, write a short "design notes" block citing what you observed:
   - "Most low-poly chairs use ~8-12 visible cuboids"
   - "Sci-fi chairs almost always have one bright accent color (cyan, orange, magenta) on a dark base"
   - "Reclined gaming chairs have visible head wings and a separate lumbar pad"
4. Save those notes alongside the .blend (in a comment or sibling .md) so future builds inherit the reasoning.

### Reference-driven iteration

When the user rejects a build ("looks dumb", "feels off"), don't just tweak — **go back to the references**. Compare the model side-by-side with the closest reference. The reason it "looks dumb" is almost always:

- Wrong proportions (head too small, base too wide)
- Missing the 1-2 distinctive style features
- Too much smooth shading / not faceted enough
- Generic materials with no color identity

Fix THOSE before fiddling with details.

## Pixel-art textures

Generate procedurally:

```python
def make_pixel_image(name, grid, alpha=True):
    h, w = len(grid), len(grid[0])
    img = bpy.data.images.new(name, w, h, alpha=alpha)
    pixels = []
    for y in range(h):
        for px in grid[h-1-y]:  # Blender stores rows bottom-to-top
            pixels.extend(px)
    img.pixels = pixels
    img.pack()
    return img
```

The grid is a list of lists of `(r, g, b, a)` floats in [0,1].

**On the material side, ALWAYS**:
- `tex.interpolation = 'Closest'` — without this, pixels blur and the look is ruined
- `tex.extension = 'CLIP'` for alpha cutouts so the transparent border doesn't tile
- Pack all images into the .blend so the file is portable

**Common texture sizes** (width × height):
- Small accent decal: 8×8
- Object-sized base color: 16×16 to 32×32
- Long thin elements (rails, fronds): match the aspect (e.g. 12×60 for a 0.20×1.00 plank)
- Floor/wall tile: 16×16 to 32×32, designed to tile
- A pure-color "patch" doesn't need a texture — just set Base Color directly

**⚠️ Texture aspect ratio MUST match the surface aspect** — a 128×128 texture stretched onto a long narrow card will look fat. Author the texture at the surface's aspect.

## Material conventions

Three baseline materials that cover most assets:

```python
# Matte plastic / painted surface
bsdf.inputs['Base Color'].default_value = (...)
bsdf.inputs['Roughness'].default_value = 0.85
bsdf.inputs['Metallic'].default_value = 0.0

# Brushed metal / chrome accent
bsdf.inputs['Roughness'].default_value = 0.25
bsdf.inputs['Metallic'].default_value = 1.0

# Soft cushion / cloth
bsdf.inputs['Roughness'].default_value = 0.90
bsdf.inputs['Sheen Weight'].default_value = 0.3   # adds the cloth glow
```

For glow / emission (sci-fi accents, screens, anti-grav fields):

```python
em = nt.nodes.new('ShaderNodeEmission')
em.inputs['Color'].default_value = (0.20, 0.55, 1.0, 1.0)
em.inputs['Strength'].default_value = 18.0   # 5-30 typical, higher = more bloom
```

Pair the emission with an actual point light at the same location so the surrounding scene picks up the glow color.

## Geometry building blocks

### Octagonal lathe (cylindrical objects: pots, pillars, pedestals, chair stems)

Profile is a list of `(radius, z)` tuples; each is a ring of `SIDES` vertices. Connect adjacent rings into quads, cap the top and bottom. **Use 8 sides** for the right blocky feel; 6 reads as more rustic, 12+ starts looking smooth.

```python
def lathe(name, profile, mat_name, sides=8):
    bm = bmesh.new()
    rings = [[bm.verts.new((r*cos(i/sides*tau), r*sin(i/sides*tau), z))
              for i in range(sides)] for r,z in profile]
    bm.verts.ensure_lookup_table()
    for j in range(len(rings)-1):
        for i in range(sides):
            ni = (i+1) % sides
            bm.faces.new([rings[j][i], rings[j][ni], rings[j+1][ni], rings[j+1][i]])
    bm.faces.new([rings[0][i] for i in range(sides)][::-1])
    bm.faces.new([rings[-1][i] for i in range(sides)])
    # Build, then disable smooth shading on every polygon
```

### Cuboid box (chairs, monitors, furniture)

`bpy.ops.mesh.primitive_cube_add(size=2)` then scale. Or a fully custom bmesh box with vertex positions matching the silhouette you want (good for things like a slightly tapered seat).

### Bevel by adding a vertex ring, NOT bevel modifier

For Blockbench style, never use Bevel modifier — it produces sub-pixel edges that defeat the look. Instead, manually add an extra vertex loop near the edge to imply a chamfer. Or just leave the edge sharp.

### Forget about subdivision modifiers

Same reason: they kill the faceted look. Build the topology you want directly.

### Spheres: start with a cube and subdivide, NOT a UV sphere

Default `bpy.ops.mesh.primitive_uv_sphere_add` produces 32+ smooth-feeling triangle fans at the poles. Bad for the blocky aesthetic AND the triangulated topology fights pixel-art texturing.

Better: start with a cube (`primitive_cube_add`), apply 1-2 levels of `subdivide`, then optionally normalize each vertex to unit length (`v.co.normalize() * radius`) to get a quad-only "spherified cube". This gives you:
- All quads (clean for UVs and edits)
- Visible facets at low subdivision levels (matches the Blockbench look)
- Predictable poles (8 corners, no pinching)

```python
bpy.ops.mesh.primitive_cube_add(size=2)
obj = bpy.context.object
bm = bmesh.new(); bm.from_mesh(obj.data)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
# Optional: spherify by normalizing each vert
for v in bm.verts:
    v.co = v.co.normalized() * 1.0
bm.to_mesh(obj.data); bm.free()
# Keep faceted shading (use_smooth = False on every poly)
```

Cuts=1 gives a chunky 6-side-each cube-sphere (24 quads). Cuts=2 gives a more spherical 96 quads. Cuts=3+ starts looking smooth — usually you want 1 or 2.

## Building scenes & environments — RELATIONAL placement, never raw coordinates

A single prop you can place by eye. A **scene** (a room, a level, an environment with dozens of
connected parts) you CANNOT — author it by writing out absolute coordinates and you WILL get walls
with gaps, decorations floating in space, props sitting over a hole/water, railings detached from the
deck. The failure is structural: raw coordinates carry no notion of **parthood, connection, or
support** (mereotopology), so nothing is forced to actually touch what it belongs to.

**Use the spatial grammar: `blender/spatial_grammar.py`.** You state RELATIONS, not numbers — every
element is placed *on* a surface, *attached to* a wall, *spanning between* anchors, or *recessed into*
a wall — and then a validator proves there are no floaters / over-nothing before you render.

```python
import sys, importlib; sys.path.insert(0, r"...\ToRustAsWeFall\blender")
import spatial_grammar; importlib.reload(spatial_grammar)
g = spatial_grammar.Grammar()
floor = g.slab_xz("Floor", -7,51, -17,3.2, top=0, thick=0.3, mat=M_DECK)  # fills a footprint
wall  = g.wall("Back", 'x', at=-4, lo=-7,hi=7.2, base=0, height=6, thick=0.4, mat=M_WALL, side=-1)
door  = g.recess(wall, 2.0,4.0, opening_h=2.6)        # SPLITS the wall into L/R/lintel — no gap, ever
g.on(   "Crate", floor, u=0.2,v=0.4, sx=1.3,sz=1.3, sy=1.3, mat=M_RUST)      # bottom flush -> can't float
g.on_wall("Pipe", wall, '+z', u=0.5,v=0.6, w=8,h=0.24, depth=0.24, mat=M_PIPE) # back flush -> can't float
g.row("Post", (5,0,3.1),(37,0,3.1), spacing=2.2, factory=...)               # repeat along a line
g.stairs("Steps", (0,3,0), (4,0,0), width=2.0, mat=M_MID)                   # solid stairs between platforms
g.stairs_arc("Spiral", (0,0), radius=11, a0=.., a1=.., width=2.5, y0=2, y1=5, mat=M_MID)  # curved/spiral stairs
for issue in g.validate(): print(issue)   # FLOATING / OVER-NOTHING — fix BEFORE rendering
g.emit(scene)                              # builds the Blender meshes (chunk frame -> Blender Z-up)
```

The grammar in practice:

1. **Floors as slabs filling footprints.** `slab_xz(x0,x1,z0,z1, top, thick)` fills a region; adjacent
   slabs that share an edge ABUT exactly → no seams, no gaps. Never place a floor by guessing a center.
2. **Walls stand on edge lines.** `wall(axis, at, lo,hi, base, height, thick, side)` — a wall is a thin
   box on a floor edge, never a free-floating slab.
3. **Openings via `recess()`, never by leaving a gap by hand.** It deletes the wall and re-adds L + R +
   lintel pieces whose union == the wall minus the opening. Gapless by construction. Returns the pieces
   (`door["L"]`, `["lintel"]`, `["opening"]`) so you can attach a frame/strips/sign to them.
4. **Props ON surfaces (`on`, `stack`).** Bottom is set flush to the surface top → a crate literally
   cannot float, and `validate()` flags it if its footprint runs off the floor edge (over water/a hole).
5. **Decorations ON walls (`on_wall`).** Pipes, vents, panels, signs, strips attach to a *specific wall
   box* at parametric (u along the run, v up the height), protruding `depth`. Because they're hosted by a
   real wall, they can't float in space or stretch across a doorway/branch opening (the #1 thing that
   went wrong with hand-coordinates). If a wall was split by `recess`, attach to the returned pieces.
6. **Spans & rows for repetition.** `span(p0,p1)` for a rail/pipe/beam between two anchors; `row(a,b,
   spacing, factory)` for posts/brackets/rungs/ladder — the factory returns `None` to skip a slot
   (e.g. a railing post over a channel gap).
7. **Stairs connect two platforms.** `stairs(name, p0, p1, width, mat, step_rise)` builds a SOLID
   stepped staircase between two 3D points (step count derives from the height difference; treads
   overlap so it reads solid, not floating slats). `stairs_arc(name, center, radius, a0, a1, width,
   y0, y1, mat)` is the curved variant — spiral descents/ascents, curved ramps. Use these instead of
   hand-stepping boxes; stairs are everywhere in this game (between landings, into water, up a spiral).
   Tag `structure` (an internal assembly). Build them in the travel direction you want (a spiral
   gauntlet climbs UP from a bottom start-shelter, so y0<y1).
8. **Grouping = hierarchy.** Build a sub-assembly (railing = posts + rails; ladder = rails + rungs;
   door = alcove + frame + strips) and reason about it as one part placed relative to a host. Tag the
   designed-internal members `"structure"` (skipped by the floater check) and the free members `"prop"`
   (checked), so the validator catches YOUR mistakes, not the assembly's intentional internal joints.

**Mereotopology / `validate()`** — the cheap insurance. Tags: `floor`/`structure`/`wall` (supports),
`prop` (must be supported or attached), `water`/`opening` (NOT a support → a prop over them is flagged).
- **FLOATING**: a prop AABB that is externally-connected to *nothing* (touches no other solid).
- **OVER-NOTHING**: a prop resting at a floor level whose footprint isn't fully over a floor (it's
  partly over water / a hole / past an edge) and isn't wall-backed.
Run it and fix every issue **before** you light/render — a clean validate is what stops the "decoration
over nothing / gap in the wall / floating object" class of bug at the source.

**Coordinate convention.** Author in the target's own frame (for a game chunk: `x` east, `y` UP, `z`
depth, matching the chunk's constants directly). `emit()` maps to Blender Z-up via the chunk convention
`Blender(x, -z, y)` so a `export_yup=True` glTF lands back in Godot coords with no re-aligning. (See
`blender/channels/build_channels.py` for a full environment authored entirely through the grammar:
catwalk, sunken water channel, surge slots, recessed door, attached pipes/vents/panels, railing, ladder,
crates — validate-clean, 0 floaters.)

## Hard-shading enforcement

After every mesh build, set `polygon.use_smooth = False`. Easy to forget. The skill's helper does it for you in the bmesh-to-mesh wrapper:

```python
def finalize_mesh(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
```

If you DO want one specific element smoothed (e.g. an emission sphere for a glow core), call `obj.select_set(True); bpy.ops.object.shade_smooth()` on just that object.

## Lighting

Standard 3-point area-light setup, energies in the 100-500 range, `size = 2-4` for soft area lights:

```python
# Key: front-side angled, slightly warm
add_area('Key', loc=( 3.0, -3.0, 4.0), target, energy=350, size=2.5, color=(1.00, 0.96, 0.92))
# Fill: opposite, cooler, ~25-35% of key
add_area('Fill', loc=(-3.0, -1.5, 3.0), target, energy=110, size=3.0, color=(0.85, 0.92, 1.00))
# Rim: back, ~30-40% of key, warm
add_area('Rim',  loc=(-1.0,  4.0, 3.0), target, energy=140, size=1.5, color=(1.00, 0.95, 0.85))
```

For dense / dark scenes, add a 4th top light. For "moody" sci-fi scenes, swap key/fill colors so cool dominates.

## Render settings

```python
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 256          # 96-128 for previews, 256 for final
sc.cycles.use_denoising = True
sc.render.resolution_x = 1600
sc.render.resolution_y = 1200
sc.view_settings.view_transform = 'Filmic'
sc.view_settings.look = 'Medium High Contrast'
sc.view_settings.exposure = 0.0  # boost to +0.5 if scene has emissions you want haloing
```

## Camera framing

For showcase renders, 3/4 view at slightly above eye-level reads best:

```python
cam.location = (cam_x, cam_y, target_z + 0.5)   # 0.5-1.0 units above target
cam.data.lens = 45-55                            # 50mm = standard portrait
direction = Vector(target) - cam.location
cam.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
```

Distance: roughly `2 * object_diagonal` for a comfortable framing with margin.

## Color palette guidance

Stick to a small palette per asset (4-7 colors). Use one dark, one mid, one light from each material's family. For a sci-fi chair this might be:
- Shell: near-black `(0.06, 0.07, 0.09)`
- Cushion: dark gray `(0.10, 0.11, 0.13)`
- Chrome accent: light gray `(0.85, 0.87, 0.90)`
- Glow: cyan-blue `(0.20, 0.55, 1.0)`

Avoid pure black `(0, 0, 0)` — even "black" surfaces in the real world have ~5% reflectance.

## What this skill DOESN'T cover

- Plants (use the `stylized-plant` skill — face-normal bug, leaf cards, bezier fronds)
- Characters / rigged figures (would need its own skill: armatures, weight painting)
- Photorealistic rendering (this skill is explicitly stylized)

## Reference implementations

- `helpers.py` in this folder — the shared building blocks
- `examples/` — small `.blend` files showing the patterns:
  - `chair_floating.blend` — futuristic floating office chair (the example that motivated this skill)
- `peris-sim/stylized-plant/` — the plant skill that grew out of this same foundation
