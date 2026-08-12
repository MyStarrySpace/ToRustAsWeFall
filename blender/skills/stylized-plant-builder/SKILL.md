---
name: stylized-plant-builder
description: Build stylized low-poly potted plants in Blender from a pot + soil mesh. Generates structural stems/vines as tube-swept beziers, attaches individual leaf planes or heart cards in opposite-pair phyllotaxy, scatters 3D flowers/buds. Use when creating a new potted plant (jasmine, pothos, jade, fern, calathea, peace lily, etc.) or improving an existing one that looks "depressed", clumped, uniform, or palm-tree-like.
---

# Stylized plant builder

This skill captures everything I've learned across 6+ plant builds in the
`peris-sim/` folder (jasmine, pothos, calathea, boston fern, pilea, haworthia,
jade, spider plant, peace lily). The recurring failures and their fixes are
documented here so future builds don't relearn the same lessons.

## The core architecture

A potted plant in this codebase = **pot + soil (given)** + 3 generated
layers:

> **Saucers removed (2026-06-05).** Older .blend files include a `Saucer`
> object, but the final game scene doesn't use them. New plants should NOT
> include a saucer object — it adds geometry/material/texture for no visual
> benefit. If you open an old .blend with a Saucer, delete it before exporting
> (also delete `SaucerMat` and `SaucerTex`).

1. **Structural skeleton** — `Branch_NNN` or `Vine_NNN` tube meshes swept along
   cubic beziers. Carry the leaves; they're the visible "stem" structure.
2. **Foliage** — individual leaf planes/cards/hearts as separate objects
   (instances of a small mesh pool), attached at intervals along the skeleton.
3. **Reproductive bits** — flowers and buds as separate 3D meshes scattered
   along the upper portions of stems.

**Never paint leaves onto a single branch card.** That was the v1-v5 mistake
for both jasmine and pothos. It reads flat, prevents per-leaf variation, and
fails on close inspection. Always build leaves as separate objects.

## Standard build procedure

```python
from helpers import (
    poisson_disk_in_circle, make_vine_tube, sample_bezier,
    place_leaves_phyllotaxy, scatter_flowers,
    vine_clips_pot_wall, get_soil_top_z, get_pot_rim_metrics,
)

# 1. Measure the existing pot
soil_top_z = get_soil_top_z(bpy.data.objects['Soil'])
rim_z, rim_inner, rim_outer = get_pot_rim_metrics(bpy.data.objects['Pot'])

# 2. Generate stem origins spread across the soil (NOT all in one spot)
origins_2d = poisson_disk_in_circle(
    n=24, radius_max=0.55, min_sep=0.13
)
origins_2d.sort(key=lambda p: p[0]**2 + p[1]**2)  # center-out tiering

# 3. Build each stem with bezier shape appropriate to tier
for ox, oy in origins_2d:
    r0 = (ox**2 + oy**2)**0.5
    if r0 < 0.18:
        kind = 'upright'  # tall, vertical
    elif r0 < 0.36:
        kind = 'arch'     # mid-height, arching out
    else:
        kind = 'short_arch'  # short outer ring

    P0, P1, P2, P3 = stem_bezier_for_tier(kind, ox, oy, soil_top_z)
    if vine_clips_pot_wall(P0,P1,P2,P3, rim_z, rim_inner, rim_outer):
        continue  # rejection sample, regenerate
    make_vine_tube('Branch_NNN', P0,P1,P2,P3, radius=0.012, mat=stem_mat)

# 4. Place leaves along each stem with opposite-decussate phyllotaxy
for stem_samples in all_stems:
    place_leaves_phyllotaxy(
        stem_samples, leaf_mesh_pool,
        nodes_per_stem=(6, 10),
        phyllotaxy='opposite-decussate',  # 90° rotation between pairs
        leaf_normal_bias='up-and-toward-camera',
        twist_variety=True,  # CRITICAL — see footgun #3
    )

# 5. Scatter flowers and buds along upper half
for stem_samples in all_stems:
    scatter_flowers(
        stem_samples, flower_mesh, bud_mesh,
        t_range=(0.45, 0.99),
        flowers_per_stem=(5, 9),
        bud_chance_at_tip=0.35,
    )
```

## Footguns (read these before every build)

### Footgun #1 — "soil.location.z" is a LIE in these scenes

In every `peris-sim/stylized_plant_*.blend` so far, `bpy.data.objects['Soil']`
has `location = (0, 0, 0)` but its mesh vertices are baked at world Z = rim
height (~1.49 for pothos pot, ~1.06 for jasmine pot). The geometry sits at
world height; the origin doesn't reflect it.

**Never** use `soil.location.z` or `soil.location.z + soil.dimensions.z/2`.
**Always** measure from mesh verts:

```python
soil_top_z = max((soil.matrix_world @ v.co).z for v in soil.data.vertices)
```

Same applies to pot rim — measure from mesh verts, not `pot.location.z`.
`get_soil_top_z()` and `get_pot_rim_metrics()` in helpers.py do this correctly.

### Footgun #2 — All stems converging at the center (clumped origins)

If you use `r0 = random.uniform(0, R)` with N stems, you get a tight bunch in
the middle because (a) uniform-in-r oversamples the center, and (b) without
inter-stem spacing you get overlapping origins. The plant looks like it's
"tied" in the pot.

**Fix**: Use Poisson-disk sampling (`poisson_disk_in_circle`) with
`min_sep ≈ 2 × stem_radius_max` (typically 0.13 for soil_r ≈ 0.55). This
guarantees stems spread across the entire soil surface. Then tier them by
distance from center: inner stems upright, outer stems short and arching.

### Footgun #3 — Uniform leaves (all the same orientation, same shape)

If every leaf uses the same mesh and the same rotation logic, the plant looks
like a fake mass-produced plastic plant — even if every leaf is in a different
position. This was the v6 pothos problem: 141 leaves all in identical
heart-shape orientation, hanging straight down.

**Fix — three sources of variety, all needed**:

  1. **Mesh pool** with multiple bake-in twist variants per size. E.g. 4
     sizes × 5 twist angles = 20 mesh variants. The twist tilts the leaf's
     left/right edges along Z so even leaves rotated to the same orientation
     in space have different physical shapes.
  2. **Random rotation around the leaf's forward (petiole) axis**, full
     `[0, 2π]`. This is the single biggest fix — it makes leaves face
     sideways, upside-down, edge-on, etc.
  3. **Variety in the leaf's `forward` direction** itself: blend outward and
     stem-side directions with `cos/sin(side_rot)`, and vary the droop from
     0.05 to 0.95 (not a narrow band).

```python
# Random twist around forward axis — THIS is the key
twist_angle = random.uniform(0, 2*math.pi)
right = right_initial * cos(twist_angle) + normal_initial * sin(twist_angle)
normal = -right_initial * sin(twist_angle) + normal_initial * cos(twist_angle)
```

### Footgun #4 — Long droopers reaching the ground = "depressed/wilted"

Jasmine v5 had 8 long drooping branches reaching the floor. User said it
"looks depressed". Pilea, jade, etc., all had this in v1-v3.

**Fix**: For plants that should look perky (jasmine, jade, calathea, peace
lily, pilea), the droopiest tier should NOT reach the ground. Keep `droop` tips
at `z ≥ soil_top_z - 0.20`. Reserve long drape (down to `z = 0.15-0.85`) for
genuinely cascading plants — pothos, spider plant, boston fern, and only with
3-12 vines that are clearly distinct cascades.

### Footgun #5 — Bezier vines passing through the pot wall

The cubic bezier mathematically passes through the wall band briefly as it
exits a deep pot — averaging weights pulls the mid-curve inside the pot's
radial extent even when P1 is high above. With strict wall-band rejection
(`r in [rim_inner, rim_outer] at z < rim_z`), 100% of long drape attempts get
rejected.

**Fix**: Only reject when the wall-band intrusion is DEEP below the rim
(`z < rim_z - 0.10`). Brief intrusion right at the rim is natural-looking
emergence, not visible clipping. Inside the cavity (`r < rim_inner`,
`z < rim_z`) is also fine — the vine is hidden by the pot interior.

The `vine_clips_pot_wall()` helper in helpers.py uses this relaxed check.

### Footgun #6 — Flowers clustered ONLY at tips = "stick with pompom"

Putting all flowers in a tight cluster at each stem tip gives the plant a
"flowery lollipop" look — flowers above, bare stems below. This is what real
jasmine doesn't look like.

**Fix**: Distribute flowers along the upper half of each stem (`t in [0.45,
0.99]`), not just at `t = 1.0`. Mix in buds (smaller teardrop meshes) with
probability rising toward the tip. The interleaving of leaves + flowers +
buds throughout the upper plant is what reads as "lively flowering jasmine"
vs "decorated stick".

For jasmine specifically: real jasmine has flowers in TIGHT CLUSTERS along
the stem, not individual scattered blooms. Build 1-3 cluster points per stem
(at t ∈ [0.65, 0.98]) and within each cluster pack 3-6 flowers + 2-4 buds in
a 0.06-0.10m radius. The result reads as a flowering plant rather than a
plant with scattered confetti.

### Footgun #7 — Flowers oversized relative to leaves

Real jasmine flowers (~2 cm) are SMALLER than the leaves (~5 cm). If you make
flowers `R_petal = 0.16` and leaves `length = 0.18`, the flowers visually
dominate and the plant reads as 'flower-arrangement' not 'plant'.

**Fix**: Keep flowers smaller than leaves. For the 1m-scale plants in this
codebase: `R_petal ≈ 0.06-0.08`, leaves length `0.20-0.45`. Roughly
flowers = 30-40% of leaf length.

### Footgun #8 — Material `blend_method='HASHED'` on a mostly-opaque texture

The pothos v5 file had `PotMat` stuck on `HASHED` blend with a 19%-opaque
texture — the pot rendered ~80% transparent (showed black/dark beige stripes
where alpha was low). Inherited bug from an earlier session.

**Fix**: Always set pot materials to `blend_method='OPAQUE'`. Only use
`HASHED`/`CLIP`/`BLEND` for actual cutout textures (leaves, flowers). The
`fix_pot_materials()` helper in helpers.py normalizes this.

### Footgun #10 — Dominant central spike (one stem much taller than the rest)

When upright stems get `L = random.uniform(L_min, L_max)` with `L_max / L_min
> 1.3`, one stem inevitably hits near `L_max` and visually dominates as a
"Christmas tree spire" sticking out of the bush. This was jasmine v7's
Branch_000 at 1.10m next to ~0.50m siblings.

**Fix**: Within any tier, keep `L_max / L_min ≤ 1.25`. For jasmine v8 I used
`(0.85, 1.05)` which gives 1.24x max ratio — still varied enough to look
natural, never produces a spike. If you want one tall hero stem, place it
deliberately (not by random sampling).

### Footgun #33 — Real-plant measurements you should know before building

I kept making proportional mistakes (leaves too small, stems too short)
because I was eyeballing rather than measuring real refs. Here are the
proportions I measured from Bloomscape silver-satin and golden-pothos
product photos:

For pothos (`pot_dia` = diameter of pot):
- **Stem length range**: 0.5 to 2.0 × pot_dia. Inner crown stems are short
  (0.5×), outer cascading vines are long (1.5-2.0×).
- **Crown height above rim**: ~ 1.0 × pot_dia (dense leaf ball ~ pot-width tall)
- **Longest drape below rim**: ~ 1.5-2.0 × pot_dia (vines hang ~1.5x pot
  height below the rim)
- **Leaf width**: ~ 0.35-0.45 × pot_dia (leaves are LARGE — about a third
  of pot diameter)
- **Stem thickness**: ~ 0.005-0.01 × pot_dia (very thin — leaves dwarf stems
  by ~5-10×)
- **Leaf density on cascading vines**: ~ 1 leaf per 0.2 × pot_dia of vine
  length

For the peris-sim pot (pot_dia=1.56, pot_height=1.55):
- Stem L = 0.6-2.5m smooth gradient by origin radius
- Crown above rim: ~1.5m tall
- Longest drape: ~2.0m (tip near floor)
- Leaf width: ~0.55-0.70m (XL size with scale 1.4×)
- Stem radius: 0.010-0.022m
- Leaf density: ~1 per 22cm of chain

Always measure refs in pot_dia units. Plant proportions are scale-invariant
within a species.

### Footgun #36 — Hybrid "quad for inner, cubic for outer" creates a visible discontinuity at the boundary

v26 used `if r_frac < 0.50: quad_bezier else: cubic_bezier`. The two regimes
have different shapes (quad just arches, cubic does up-over-down), so the
plant silhouette had a visible "snap" between regimes — mid stems behaved
qualitatively differently from one to the next at r_frac ≈ 0.50.

**Fix**: use a SINGLE cubic bezier for all stems, with control points
interpolated by `cascade = smoothstep(r_frac)`. The cubic shape at
`cascade=0` degenerates into a simple upward bend (because P1 and P2 are
both near "above origin" with similar XY, only z differs), and at
`cascade=1` it becomes the full cascade shape. Smooth all the way through.

See the "Cascading-vine pattern" recipe above for the exact formulas.

### Footgun #35 — Tip-pin chain sim cuts diagonally through pot wall

Two-pin chain sim (base at soil, tip outside pot at floor) wants the
SHORTEST chain shape between pins. With high bend stiffness and a curved
initial pose, the sim refines the initial pose toward the shortest path,
which goes DIAGONALLY through the pot wall. Result: vines appear as little
sticks poking through the pot at various heights. v24 disaster — exactly
this failure mode.

**Fix — use a CUBIC bezier (4 control points) for cascading vines, no sim**:
The four control points geometrically constrain the curve to "rise, cross
the rim, descend" without any simulation:
- P0 = soil origin
- P1 = directly above P0 at z = rim_z + 0.20 (forces RISE)
- P2 = WELL outside rim at z = rim_z + 0.05 (forces CREST outside the wall)
  - Critical: P2.r must be `rim_outer + 0.30` minimum. With only `+0.10`,
    the descent from P2 to P3 still crosses through the wall band.
- P3 = drape tip at desired floor level, just outside rim

Cubic bezier with this control-point layout naturally stays "up, over,
down" because P1's high z keeps the curve up early, P2's far-out r keeps
the descent outside the wall, P3 ends at floor.

Pothos v25 uses this approach and only 4 of 35 vines clip even shallowly.

### Footgun #34 — Two-pin chain (base + tip on floor) gives natural cascade

For long cascading vines, simulating ONLY with base pin produces "chain
hangs straight down inside pot" (Footgun #30). The fix from v21 was a rim
pin, but the cleaner fix is a **tip pin at the desired endpoint**:

```python
# Drooper vine: pin base AT soil, pin tip JUST OUTSIDE the rim, AT floor level
tip_r = rim_outer + 0.05            # just outside pot wall
tip_z = floor_z + 0.05               # at floor (or higher if chain too short)
tip_pin = Vector((radial_unit.x * tip_r, radial_unit.y * tip_r, tip_z))

# Initial pose: bezier from base → apex above rim → tip pin
# This shape is what the sim refines into natural drape
apex = midpoint with apex_r ~ between rim and tip_r, apex_z ~ rim_z + 0.20

# Sim with high bend stiffness — chain has shape (rises over rim, then drapes down)
chain = simulate_chain_with_tip_pin(P0, initial, n_segs, tip_pin, bend_iters=4-8)
```

The key constraint: chain length L must significantly exceed straight-line
distance from base to tip pin, so the chain has slack to curve naturally.
If L ≈ straight distance, the chain settles as a straight line. For pothos
v24: ensure `L > base_to_tip_distance * 1.3` for visible drape.

Also critical: tip_r should be just barely outside the rim, NOT far out.
Real pothos drape STRAIGHT DOWN once they clear the rim — they don't extend
radially outward at the floor. Far-out tips create a starburst pattern.

### Footgun #31 — Discrete tiers (upright/arch/drooper) make harsh visual splits; use smooth gradient by radius instead

Pothos v21 used 3 discrete tiers with different bend stiffness/length/sim
strategies. Inner stems were rigid-straight, outer stems were limp-collapsed
— the visual contrast was jarring ("dead/droopy"). Real plants don't have
discrete stiffness tiers; they have a smooth gradient.

**Fix**: interpolate ALL stem parameters continuously by origin radius. For
pothos v23:
```python
r_frac = r0 / SOIL_R  # 0 at center, 1 at edge, smooth in between
L = 0.75 + r_frac * 0.55 + noise         # shorter inner, longer outer
apex_z = soil + L * (0.90 - r_frac*0.25)  # apex slightly lower at edge
apex_r = r0 + L * (0.05 + r_frac*0.25)    # apex extends further at edge
tip_z = soil + L * (0.95 - r_frac*0.40)   # tip drops more at edge — but NOT to zero
tip_r = r0 + L * (0.15 + r_frac*0.45)     # tip extends further at edge
stem_radius = 0.025 - r_frac * 0.008      # thinner stems at edge
```

The KEY insight: every parameter that varies should vary CONTINUOUSLY with
r_frac, not via if/elif on tier label. Even leaf size/count can interpolate
this way (although discrete leaf meshes constrain the size step).

### Footgun #32 — "Stiffer everywhere" fixes both extremes

When inner stems look "too stiff" AND outer stems look "too floppy" simultaneously,
both readings come from the SAME problem: the floppy ones look limp/dead so
by contrast the stiff ones look rigid/dead. Bumping the overall stiffness
makes the entire plant look ALIVE.

Practical numbers (post-debug): for the peris-sim pot scale:
- tip_z multiplier range: 0.55 to 0.95 (was 0.0 to 0.95 — too floppy at edge)
- apex_z multiplier range: 0.65 to 0.90 (no drooper-class going down to rim_z)
- No long_droopers reaching the floor unless explicitly desired for character

The natural plant look is "alive with subtle arches", not "physically settled
under gravity". The physics-correct droop reads as wilted.

### Footgun #30 — Blender soft body goal won't pin if your settings are wrong, AND chains hang straight down without a "rim pin"

Two lessons from actually trying physics for pothos vines:

**(a) Blender's soft body goal silently fails to pin** even with goal_spring
near max. Tried 0.97 with mass=0.35 and goal_friction=25 — entire vine still
fell ~1.4m. Reasons aren't fully clear but the behavior is well-documented as
finicky. The straightforward fix is to use a Python chain simulator
(Verlet + distance constraints + bend stiffness) instead.

**(b) A free-hanging chain pinned only at the base hangs STRAIGHT DOWN** —
gravity has no horizontal component, so the chain settles vertically below
the pin. For a pot scenario this means the chain disappears INTO the pot
cavity, not over the rim.

Real plants don't behave this way because the stem GREW over the rim — the
rim is now a physical contact point the stem rests on. Simulate this with a
**rim pin**: pick a chain segment ~30-40% along its length, pin its XY
position at `(rim_outer + small_buffer) * radial_unit` and z=rim_z+small.
The base pin holds the root, the rim pin holds the "rest point", and
everything past the rim pin drapes freely outside the pot.

Verlet chain code skeleton (in helpers.py as `simulate_chain_with_rim_pin`):
```python
positions[0] = P0_base  # always pinned
positions[rim_pin_idx] = rim_pin_pos  # always pinned
# All other verts: Verlet step under gravity, then distance + bend relax,
# then floor + pot-wall collision constraints
```

For non-drooper tiers (upright, arch), single-pin sim works fine because
the chains are short enough that "straight down from base" doesn't reach
problematic territory.

### Footgun #28 — "Gravity-pose" via parametric tiers gets you 90% of physics sim

For drooping branches/vines, the temptation is to set up Blender soft-body
sim, bake at frame 60, etc. That works but is fiddly and slow. For stylized
plants, a 4-tier parametric pose with explicit drooper z-targets achieves
the same visual result in a single pass:

  - `upright`: short, tip stays near top of stem (z = soil_top + L * [0.85, 1.0])
  - `arch`: medium, tip arcs out and slightly down (z = soil_top + L * [0.20, 0.55])
  - `drooper`: tip drops well below rim (z = rim_z - [0.30, 0.90])
  - `long_drooper`: tip ON the floor (z = floor_z + [0.05, 0.40])

Mix weights e.g. 35/30/20/15 for upright/arch/drooper/long_drooper.

If the parametric look isn't enough — e.g. user wants natural mid-curve
sag from gravity — fall back to soft body with hooks at bezier control
points, or simulate the chain dynamics in Python and bake the resulting
shape into the bezier.

### Footgun #29 — Need to check collision against pot AND floor for drooping curves

Long-drooper curves can clip through:
1. The pot wall (Footgun #5/#13) — covered
2. The FLOOR/SAUCER if tip z drops below `floor_z + small_margin`

Add an explicit floor check:
```python
def curve_below_floor(samples, floor_z):
    return any(p.z < floor_z + 0.02 for p, _, _ in samples)
```

Use rejection sampling: try up to 10 random configurations per stem until
one passes BOTH `curve_clips_pot()` and `curve_below_floor()`. Fall back
to a safe-default short stem if no valid drooper config found.

### Footgun #25 — Uniform leaf-orientation formula = stiff radial fan; need per-leaf randomness

If `desired_normal = radial_xy * 0.5 + (0,0,0.8)` is applied to EVERY leaf,
they all face outward-and-up identically — produces an unnaturally orderly
radial fan. Real plants are messy: each leaf rotated its own way as it grew
toward whatever light it happened to find.

**Fix**: per-leaf RANDOM orientation, not a deterministic formula:
```python
nx = radial_xy.x * uniform(-0.3, 0.7) + uniform(-0.4, 0.4)
ny = radial_xy.y * uniform(-0.3, 0.7) + uniform(-0.4, 0.4)
nz = uniform(-0.2, 1.0)  # mostly up but can be down
desired_normal = Vector((nx, ny, nz)).normalized()
```

Each leaf gets its own independent random normal with general up-bias but
substantial sideways and even slight-down components.

### Footgun #26 — Need a "drooper tier" for wildness — not every petiole goes UP

Real pothos has some petioles that emerged outward, then gravity pulled them
DOWN — so the petiole ends with negative pitch and the leaf hangs. Without
any drooping petioles, the plant reads as stiff/manicured.

**Fix**: mix petiole types with explicit tiers. For pothos v19:
- 55% standard (upright/outward, pitch 0.30-0.85)
- **30% drooper** (pitch -0.40 to 0.10 — tip BELOW or barely above origin)
- 15% young (short, close to soil)

Droopers need:
- Their bezier P1 placed laterally (`P0 + (0,0,L*0.35) + radial_xy * L * 0.35`) so the curve starts outward then drops
- Their leaf forward direction biased DOWN (`leaf_forward.z ∈ [-1.0, -0.2]`)

### Footgun #27 — Density too low + origins too spread = sparse twiggy plant

Pothos v18 had 28-32 origins in a 0.40 radius — too sparse for the leaves to
form a coherent mass. v19 uses 45 origins in a 0.30 radius (min_sep 0.055)
— tighter, denser cluster of petioles, leaves overlap chaotically like the
real reference.

Real pothos crown emerges from a small root mass; petioles are crowded at
the base and only spread at the tips.

### Footgun #23 — Leaf normal aligned with petiole = edge-on from camera

If you orient a leaf with `leaf_forward = petiole_direction` and compute the
normal as a perpendicular to that forward, leaves on a near-vertical petiole
end up with their NORMAL nearly horizontal — meaning the leaf face points
sideways. From a camera looking down/across, the leaf shows edge-on as a
thin sliver. The plant reads as twiggy/sparse even with many leaves.

**Fix — orient leaf normal toward where it would naturally face**:
```python
# Leaf forward (tip direction) — outward and slightly down
leaf_forward = (radial_xy + Vector((0, 0, -droop))).normalized()
# Leaf normal — OUTWARD + MOSTLY UP, NOT perpendicular to forward
desired_normal = (radial_xy * 0.5 + Vector((0, 0, 0.8))).normalized()
# Now project desired_normal so it's perpendicular to leaf_forward (required
# for an orthonormal basis), but starting from this desired direction:
normal = desired_normal - leaf_forward * leaf_forward.dot(desired_normal)
normal.normalize()
right = normal.cross(leaf_forward)
```

This makes the leaf BROADSIDE visible to anyone outside the plant looking at
it — exactly what real leaves do (chase sunlight = present broadside up).
Petiole direction only determines tip-direction, not face direction.

### Footgun #24 — One-leaf-per-stem vs multi-leaf-per-stem is a fundamental architectural choice

The two pothos architectures I built:
1. **Multi-leaf chains** (v9-v15): tall vine tubes with several leaves placed
   at intervals along each. Suits MATURE cascading or trailing plants.
2. **One-leaf-per-petiole** (v18+): each leaf has its own short bent petiole
   emerging from the soil crown. Suits YOUNG/COMPACT plants like
   pilea peperomioides, jade, or young pothos in a small pot.

The user's reference photo determines which. Compact bushy reference = #2.
Long trailing reference = #1.

Don't try to derive this from the species name — pothos in particular ranges
from compact-young-on-table to massive-trailing-from-bookshelf, and the same
species deserves a different architecture each way.

### Footgun #22 — Stems too short relative to pot size = "baby plant"

A 1m pot with stems capped at 1.0m makes the foliage occupy only the top
1/3 of the frame — the plant reads as a small juvenile in a big pot. The
pot dominates the composition.

**Fix**: stem max length should reach AT LEAST the same height as the pot
above the soil top. For the peris-sim pot (rim_z=1.55, soil_top_z=1.49), a
1.55m pot wants stems 0.80-1.60m so the plant column equals or exceeds the
pot column.

Also check leaf distribution: if leaves all cluster at the tip of each stem,
even tall stems read as bare-pole-with-tuft. Use density-proportional
node count (`n_leaves = max(4, min(10, int(L / 0.18)))` for pothos-style)
so leaves spread along the full stem length.

### Footgun #20 — Bezier P1 placed too high makes "ramrod-straight" stems

Even with strong tilt amount and lateral angle on a cubic bezier, if P1 is
at `P0 + (0,0,L*0.30)`, then the lowest 30% of the stem is locked to nearly
vertical because P1 is directly above the origin. The result reads as a
straight pole with only a tip-flick. The user called this out specifically
("stems just stick up ram-rod straight").

**Fix**: P1 must be LOW (15-20% of L) AND already significantly displaced
in the tilt direction so the curve starts bending from the base:
```python
# Hero stem with significant base-up bend
P1 = P0 + Vector((0, 0, L*0.15)) + tilt_dir * tilt_amount * L * 0.25
P2 = P0 + Vector((0, 0, L*0.50)) + tilt_dir * tilt_amount * L * 0.75
```

Visual check: sample 5 points along the curve and print their x/y/z. The
lateral displacement should grow smoothly from t=0 (small) to t=1 (full
displacement), with the middle sample at roughly half the lateral travel.
If the first 30% is laterally stationary, P1 is too high.

### Footgun #21 — Evenly-spaced theta origins create a "doughnut" gap

Pothos v13 used `theta = vi * 2π / N_UPRIGHT + small_jitter` for 14 stems
spread around the center. From most camera angles this produces a visible
SPLIT or GAP in the foliage — leaves cluster left and right of camera with
emptiness front and back, like a doughnut viewed edge-on.

**Fix**: use Poisson-disk distribution `poisson_disk_in_circle(n, radius,
min_sep)` instead. Origins fall in genuinely-random positions that don't
align into a circle. Combined with per-stem random tilt direction (each stem
picks `tilt_angle = random.uniform(0, 2π)` rather than tilting radially
outward), the silhouette becomes a coherent ball with no visible split.

Also: if your stems all lean radially outward FROM the center, even with
random origins you'll get a doughnut — the leaning direction reinforces the
gap. Each stem should lean in its OWN random direction.

### Footgun #18 — Fixed-range node counts produce sparse leaves on tall stems

If `n_nodes = random.randint(4, 6)` is constant across all stems, a 1.6m
hero stem ends up with 4-6 nodes (one every 25-40cm — looks sparse and
twiggy), while a 0.5m short stem has the same 4-6 (one every 8-12cm — looks
dense). The visual density per unit-length is wildly inconsistent.

**Fix**: scale node count to stem length with a target spacing:
```python
target_spacing = 0.13  # ~13cm between nodes
n_nodes = max(3, min(12, int(L / target_spacing)))
```

This is the same idea as adaptive subdivision — give each stem the right
number of features for its physical size.

### Footgun #19 — Tall stems left straight read as poles, not branches

The original v9-v12 jasmine had heroes with `tilt_amount ∈ [0.05, 0.15]` —
1.5m stems with only 7-22cm of lateral displacement. Read as vertical poles
shooting out of the bush. Real flowering stems on tall plants curve as they
grow under their own weight (gravitropism) — they should bend by 20-50% of
their length.

**Fix for tall stems**: bump `tilt_amount` to `[0.25, 0.50]` and
`lateral_angle` to full `[-π/2, π/2]` (heroes can lean in any direction).
Also bias the bezier P2 control point further along the bend direction
(`tilt_dir * tilt_amount * L * 0.80` instead of `0.55`) so the curve isn't
mostly vertical with just a tip-flick.

For pothos/cascading vines: this footgun doesn't apply — those use
quadratic bezier with apex-far-out which gives them their bend naturally.

### Footgun #16 — Decorations placed by random offset around the stem center pierce through the stem

I placed jasmine flower clusters by sampling a point along the stem then
applying a random offset `Vector((u(-1,1), u(-1,1), u(-1,1))) * 0.06`. With
stem tube radius ~0.012 and flower body radius ~0.07, this often gave
flower-center positions where the flower's GEOMETRY OVERLAPS the stem tube
— visible as stems piercing through flower petals.

**Fix — three rules**:
  1. **Prefer placing at the TIP (t ≈ 0.99)**: stems have no geometry past
     their end, so flowers placed beyond the tip can't intersect the stem.
  2. **Project the cluster ONE DIRECTION away from the stem axis**, not in
     a sphere around it. Pick a single `cluster_dir` perpendicular to the
     stem tangent, offset the cluster center by `MIN_OFFSET = max(stem_r +
     flower_r, 0.08)`, then scatter individual flowers within a cone aligned
     to that direction.
  3. **Verify distance**: for each placed flower, compute `(loc -
     stem_sample_point).length` and skip if < `MIN_OFFSET * 0.7`.

The cluster-projection pattern also looks MORE NATURAL than spherical
scatter — real flower clusters bunch on one side of the stem (where the
inflorescence emerged), not in a halo around the stem.

### Footgun #17 — Don't replicate "cascading" pattern when a more upright relative looks better

I built pothos as a deep cascading plant (heavy drape, vines reaching low)
because pothos CAN look like that in the wild. But for the user's scene the
peace lily v6 reference (which is also in this codebase) is what they wanted
to match — upright stems, leaves arching from a central crown, only a few
vines softly draping. Pothos is plastic enough in the wild to go either way.

**Lesson**: when there's a successful sibling plant in the codebase
(`peace_lily_final.blend`, `pilea_v10_sss.blend`, etc.) that has a similar
silhouette to what the user wants, MIRROR that plant's tier structure
instead of starting from scratch. Even within "cascading-capable" species,
the upright form is often more visually appealing and matches a domestic
houseplant context.

For pothos v13, the spec is now: 14 upright stems (peace-lily-style) + only
5 cascading vines, not 14 long drape + 4 short crown like v12 had.

### Footgun #14 — Texture resolution must MATCH the codebase's existing style, not what looks "good in isolation"

The `peris-sim/` codebase uses a deliberate Minecraft-style very-low-res palette
— leaves are 12-20 pixels per side, with stark color steps and chunky edges.
Reference set: `peris-sim/gltf-exports/` LeafTex (12×14), CalLeafTex (20×36),
VineTex (14×64), JasmineBranchTex (20×40), FrondCardTex (20×110).

If you redraw a leaf texture at "good" resolution (96×96+ with smooth veins),
the new plant will visually CLASH with every other plant in the garden scene.
This is what happened when I bumped jasmine to 128×64 and pothos to 96×96 —
they looked nice alone but stuck out as the "smooth ones" in a scene of pixelated
ones.

**Fix — match the existing palette and resolution band**:
  - Always inspect `peris-sim/gltf-exports/*Tex.png` BEFORE drawing new textures.
  - Leaf textures: 12-20 pixels on the long dimension.
  - Use the EXACT palette colors from the existing textures. Extract with:
    ```python
    from PIL import Image; import numpy as np; from collections import Counter
    arr = np.array(Image.open(path))
    mask = arr[..., 3] > 100
    Counter(map(tuple, arr[mask][:, :3])).most_common(10)
    ```

**peris-sim canonical palette** (rgb 0-1):
```
P_VERY_DARK   = (0.02, 0.10, 0.04)   # midrib / deep shadow
P_DARK        = (0.06, 0.20, 0.08)   # leaf edge
P_MID_DARK    = (0.10, 0.32, 0.14)   # body
P_MID         = (0.20, 0.45, 0.18)   # body lighter
P_LIGHT       = (0.35, 0.60, 0.25)   # highlight
P_VERY_LIGHT  = (0.55, 0.72, 0.35)   # bright highlight
P_STEM_BROWN  = (0.55, 0.32, 0.20)
P_CREAM       = (0.96, 0.94, 0.86)   # flower / spathe white
P_YELLOW      = (0.96, 0.86, 0.45)   # flower center / variegation
P_VARIEGATION = (0.78, 0.78, 0.30)   # golden pothos variegation
```

Use these constants verbatim in any new plant texture. Defined in
`helpers.py` as `PERIS_SIM_PALETTE`.

If the user explicitly asks for higher-res textures, ignore this footgun.
Otherwise default to matching existing.

Specific texture sizes I've validated for matching style:
  - Jasmine oval leaf (horizontal): 20×10
  - Pothos heart leaf: 14×14
  - Calathea lance leaf: 20×36 (matches existing CalLeafTex)
  - Vine card with painted leaves: 14×64 (matches existing VineTex)

### Footgun #15 — UV orientation mismatch between mesh and texture

The single largest "looks weird" issue I hit. A paired-leaf MESH with the
leaf extending in +X (UV u-axis = length), midrib at v=0.5 — but the
TEXTURE was drawn as a vertical leaf (long dimension along its own height).
Result: the texture is read SIDEWAYS, stretched across the leaf's short
dimension. The leaf rendered as "thin dashes" instead of broad oval shapes.

**Fix — write a UV-to-texture consistency check before drawing the texture**:

  1. Inspect the mesh UVs and identify which UV axis = leaf length, which =
     leaf width, where the midrib is in UV space.
  2. Draw the texture WITH THE LEAF ORIENTED MATCHING THE UV LAYOUT.
     - If U=length, draw a HORIZONTAL leaf (long dimension in texture-X).
     - If V=length, draw a VERTICAL leaf (long dimension in texture-Y).
  3. Save the texture to disk and OPEN IT alongside a UV-overlay screenshot
     of the mesh. They should be obviously oriented the same way.

The paired-leaf mesh in `make_leaf_pair_mesh()` uses U=length, V=width,
V=0.5=midrib. So jasmine leaf texture is drawn at 128×64 with leaf
horizontal: base at left (U=0), tip at right (U=1), midrib horizontal
through the middle (V=0.5).

### Mandatory texture-dump-and-verify step

Add this between "build textures" and "render final":

```python
def dump_and_verify_textures(image_names, out_dir):
    """Save every texture to disk so you can SEE them.
    Then OPEN each one and verify:
      1. Resolution is high enough (≥ 64×64 for leaves)
      2. The drawn shape matches what the mesh UVs expect
      3. No empty alpha regions where you expect content
    """
    import bpy, os
    for name in image_names:
        img = bpy.data.images.get(name)
        if img is None:
            print(f"  MISSING: {name}")
            continue
        path = os.path.join(out_dir, f'tex_audit_{name}.png')
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        # Sanity-check resolution
        if min(img.size) < 64 and 'Leaf' in name:
            print(f"  WARN low-res: {name} = {img.size[0]}×{img.size[1]}")
        else:
            print(f"  OK: {name} = {img.size[0]}×{img.size[1]} → {path}")
```

This is NON-NEGOTIABLE before declaring done. The user explicitly called out
"the mesh doesn't always correspond with the drawn textures" — exactly
because I had skipped this step.

### Footgun #12 — Leaf rotation pivot at center, not base = wonky angles

If your leaf mesh has its origin/pivot at the geometric center (or at the leaf
TIP), then rotating it to attach to a stem makes the leaf "stick out" from
the rotation center — which is in the MIDDLE of the leaf, not where it
attaches to the stem. The visible attachment point ends up halfway down the
leaf, which looks broken.

**Fix**: design leaf meshes with the attachment vertex at LOCAL ORIGIN
(0,0,0). Either single leaves with base-at-origin, or — better for paired
plants like jasmine — a paired-leaf mesh with TWO leaves extending in ±X
from origin, sharing a center pivot. One mesh = one node's leaf pair, rotated
once. See `make_leaf_pair_mesh` example in jasmine v9.

This also dramatically reduces the object count (one paired-mesh per node
instead of two single-leaf objects), and the leaves are guaranteed to be in
the same plane (which is how real opposite-decussate phyllotaxy actually
looks).

### Footgun #13 — Cubic bezier is too floppy for cascading vines; use quadratic

I tried cubic bezier (4 control points: P0, P1, P2, P3) for pothos vines
through v11 and the result was always droopy. Even with P1 forced high above
the rim and P2 forced far out, the cubic curve has TWO middle control points
which can pull the mid-section into sag. The user kept saying "looks droopy",
"no stiffness", "wet noodles".

Boston fern and spider plant in this codebase use QUADRATIC bezier (3 control
points: P0, P1, P2) and don't have this problem. The recipe file explicitly
warns: "quadratic bezier (NOT cubic — cubic causes twist)". Quadratic gives
a single clean parabolic arch from origin to tip with P1 as the apex.

**Fix — use quadratic bezier for any cascading structural element**:

```python
def sample_quad_bezier(P0, P1, P2, n):
    out = []
    for i in range(n+1):
        t = i / n
        p = (1-t)**2 * P0 + 2*(1-t)*t * P1 + t**2 * P2
        tg = 2*(1-t)*(P1-P0) + 2*t*(P2-P1)
        if tg.length < 1e-5: tg = Vector((0,0,-1))
        tg.normalize()
        out.append((p, tg, t))
    return out
```

For pothos v12 vines:
  - P0 = soil origin
  - P1 = APEX of arch: `r = rim_outer + [0.20, 0.40]`, `z = rim_z + [0.30, 0.55]`
    (high AND far out — defines the entire shoulder)
  - P2 = drape tip: `r ≈ apex_r + jitter`, `z = apex_z - [0.20, 1.20]` by tier

Quadratic also has the side benefit of guaranteeing the curve is contained
in the triangle P0-P1-P2 (a property called the convex hull), so it can't
sneak through the pot wall the way cubic curves sometimes do.

### Footgun #13b — Thin tubes read as flimsy even with the right curve

Even with a stiff quadratic arch, vines at radius 0.022-0.030 still read as
"thin wires" rather than woody stems. The visual stiffness comes from the
combination of curve shape AND tube thickness.

**Fix**: pothos vines need radius `[0.028, 0.040]` — almost double the leaf
attachment point thickness, so the vine reads as a substantial stem.

### Footgun #11 — Stratified leaf placement vs. random + rejection

Using `random.uniform(t_min, t_max)` + reject-if-too-close-to-existing is
wasteful when you have small available range and tight spacing constraints —
many candidates collide. Pothos v8 first attempt produced 2.6 leaves/vine
where 6-8 was target.

**Fix**: Use STRATIFIED sampling. Divide the available t-range into
`n_leaves` equal buckets, place one leaf per bucket with jitter `(bucket *
0.20)` margin from bucket edges. This guarantees both count and spacing in
one pass. See `place_leaves_along_vine` in helpers.py — accepts `stratified=True`.

### Footgun #9 — Leaves baked as "branch card" instead of separate planes

This was the structural mistake of v1-v5. A curved card with leaves PAINTED on
the texture reads as flat green stripes, no matter how good the texture is.
Each leaf must be a separate object with its own orientation. See Footgun #3
for why variety matters.

For perpendicular-to-stem leaf attachment (opposite-decussate phyllotaxy),
use `place_leaves_phyllotaxy()`. It rotates 90° between successive node
pairs, which is what jasmine, mint, basil, and most opposite-leaved plants do.

## Decision tree: which plant style?

```
Is the plant supposed to cascade visibly?
├── Yes (pothos, spider plant, ivy, string-of-pearls)
│   └── 10-14 vines on QUADRATIC bezier (Footgun #13 — cubic = droopy)
│       P1 = APEX (high+far: r ≥ rim_outer + 0.20, z ≥ rim_z + 0.30)
│       P2 = tip drop to z ∈ [0.15, 1.40] by tier
│       Tube radius 0.028-0.040 (Footgun #13b — thin = flimsy)
│       Leaves as separate objects with stratified t-bucket placement
│       Use rotation variety (twist around forward axis) — Footgun #3
│
├── Sort-of (boston fern, calathea — arching fronds)
│   └── Many (20-50) curved CARDS on quadratic bezier (NOT tube + leaves)
│       Width axis = horizontal-perp (drape vertically)
│       Each card is one rigid mesh — inherent stiffness
│
└── No (jasmine, jade, pilea, peace lily, haworthia — upright)
    └── Poisson-disk origins spread across soil
        Tier by radius: upright center, arching mid, short outer
        Leaves as separate planes perpendicular to stem
        Flowers distributed along upper half if flowering
        DO NOT make tier-3 reach the ground — Footgun #4
```

## Named patterns

### Cascading-vine pattern (use for pothos, ivy, philodendron, string-of-pearls)

The validated approach for drooping vines that emerge from a pot interior,
arc over the rim, and drape down outside without clipping the pot.

**Use a SINGLE cubic bezier for ALL stems** (inner and outer), with control-
point parameters smoothly interpolated by a `cascade` factor derived from
origin radius. Don't have separate "inner=quad, outer=cubic" code paths
— that produces a visible discontinuity in the plant silhouette where the
two regimes meet (Footgun #36).

```python
def smoothstep(t):  # easing for parameter interpolation
    return t * t * (3 - 2 * t)

# For each origin (ox, oy):
r_frac = min(1.0, (ox**2 + oy**2)**0.5 / SOIL_R)
cascade = smoothstep(r_frac)  # 0 at center, 1 at edge, smoothly

# Length: longer at edge, but center should also be substantial+bendy
L = 1.0 + (r_frac ** 1.3) * 1.5 + random.uniform(-0.15, 0.25)

# === Cubic bezier control points (all interpolated by cascade) ===

# P1 = rise control, with lateral bend for naturalism
rise_z = soil_top_z + L * (0.30 + cascade * 0.20)
# Bend direction: random angle for center (organic curl), outward for edge
bend_random = random.uniform(0, 2*math.pi)
bend_unit = lerp_unit(
    random_dir=(cos(bend_random), sin(bend_random), 0),
    outward_dir=radial_unit,
    t=cascade,
)
P1 = P0 + bend_unit * 0.20 * L + Vector((0, 0, rise_z - P0.z))

# P2 = "crest" — smoothly transitions from "above origin" to "far outside rim"
crest_r = lerp(r0 + L*0.20,            rim_outer + 0.30, cascade)
crest_z = lerp(soil_top_z + L*0.85,    rim_z + 0.05,     cascade)
P2 = Vector((bend_unit.x * crest_r, bend_unit.y * crest_r, crest_z))
# Note: bend_unit ≈ random at center, ≈ radial_unit at edge — same smooth lerp

# P3 = tip — smoothly transitions from "high tip" to "floor drape"
tip_r = lerp(r0 + L*0.35, max(rim_outer + 0.10, crest_r - 0.05), cascade)
tip_z = lerp(soil_top_z + L * 1.0,
             max(floor_z + 0.05, rim_z - (rim_z - floor_z - 0.05) * cascade),
             cascade ** 1.2)  # sharper transition to floor for outermost
P3 = Vector((tip_dir.x * tip_r, tip_dir.y * tip_r, tip_z))

chain = sample_cubic_bezier(P0, P1, P2, P3, n_segments)
```

**Why this works**:
- A SINGLE bezier function for all r_frac means no visible discontinuity
- `cascade = smoothstep(r_frac)` gives smooth easing — center vines are
  upright-with-bend, edges are full cascade, intermediate is intermediate
- At center (`cascade ≈ 0`): P1/P2/P3 form an upward-bending curve in a
  random horizontal direction (organic, not rigid)
- At edge (`cascade ≈ 1`): P1 high, P2 far out, P3 at floor — the standard
  cascade shape
- The convex-hull property of cubic bezier still applies: if all 4 control
  points are outside the wall band at the edge configuration, the curve is
  too

**Don't simulate this**: chain physics (Verlet or soft body) WANTS the
shortest path between pinned endpoints. Even with high bend stiffness, the
chain settles toward a straight line from base to tip — which cuts through
the pot wall (Footgun #35). The cubic bezier with 4 control points already
gives the desired shape; sim just degrades it.

```python
# For each origin (ox, oy) with r_frac >= 0.50 (outer ring):
P0 = Vector((ox, oy, soil_top_z + 0.01))
radial_unit = Vector((ox, oy, 0)).normalized()

# Length: smooth gradient by radius, with cascade up to ~2x pot_height
L = 0.65 + (r_frac ** 1.4) * 1.65 + random.uniform(-0.10, 0.25)

# CUBIC bezier with carefully placed control points:
# P1 = directly above P0, near rim height — forces "rise"
rise_z = rim_z + 0.20 + random.uniform(0.0, 0.15)
P1 = Vector((P0.x, P0.y, rise_z))

# P2 = FAR outside rim (NOT just outside — critical!), at rim height
# Why far out: cubic interpolation needs P2 well past rim_outer so the
# descent from P2 to P3 doesn't pass through the wall band
crest_r = rim_outer + 0.30 + random.uniform(0.0, 0.15)  # +0.30 minimum
crest_z = rim_z + 0.05 + random.uniform(-0.05, 0.10)
P2 = Vector((radial_unit.x * crest_r, radial_unit.y * crest_r, crest_z))

# P3 = drape tip, stays at crest radius (don't push tip back inward)
tip_r = max(rim_outer + 0.10, crest_r - 0.05 + random.uniform(-0.05, 0.05))
drop_factor = (r_frac - 0.50) / 0.50  # 0 at r_frac=0.50, 1 at r_frac=1.0
tip_z = max(floor_z + 0.05,
            rim_z - (rim_z - floor_z - 0.05) * drop_factor + random.uniform(-0.05, 0.05))
P3 = Vector((radial_unit.x * tip_r + jitter,
             radial_unit.y * tip_r + jitter,
             tip_z))

# Sample bezier directly — NO simulation needed
chain = sample_cubic_bezier(P0, P1, P2, P3, n_segments)
```

**Why this works**:
- P1's high z forces the start of the curve to rise vertically out of the soil
- P2's FAR-OUT radius forces the curve apex to clear the wall by a wide margin
- P3 just outside the rim keeps tips draping straight down, not radiating outward
- The cubic bezier's convex-hull property guarantees the curve stays within
  the convex polygon P0-P1-P2-P3, so if those four corners are all OUTSIDE
  the wall band, the whole curve is too

**Don't simulate this**: chain physics (Verlet or soft body) WANTS the
shortest path between pinned endpoints. Even with high bend stiffness, the
chain settles toward a straight line from base to tip — which cuts through
the pot wall (Footgun #35). The cubic bezier with 4 control points already
gives the desired shape; sim just degrades it.

For inner/mid vines (r_frac < 0.50): use simpler quadratic bezier with
apex partway up + slight outward. They don't need cubic since they stay
above the rim.

## Per-plant recipes

See `references/plant_recipes.md` for the exact parameters that produced each
accepted .blend.

## Mandatory verification step (DO THIS BEFORE DECLARING DONE)

Every plant build must end with a side-by-side comparison against a reference
image of the real plant. This is **non-negotiable** — every issue the user
called out in this codebase ("looks like a palm tree", "looks depressed", "too
uniform", "central spike", "leaves clumping", "wrong proportions") was visible
in a 5-second comparison but invisible from the rendered image alone.

### Verification procedure

```python
# 1. DUMP EVERY TEXTURE TO DISK AND OPEN EACH ONE (Footgun #14, #15).
#    Verify resolution ≥ 64×64 for leaves and that the drawn shape's
#    orientation matches the mesh's UV layout.
dump_and_verify_textures([
    'JasmineLeafTex', 'PothosLeafTex', 'JasmineBranchTex',  # leaf/foliage
    # flowers usually have no texture — skip
], out_dir='peris-sim/')
# READ each saved tex_audit_*.png — don't just trust the resolution warning.

# 2. Render at the resolution the user will VIEW it (1080×1080 minimum).
#    Small preview renders hide every issue worth catching.
scene.render.resolution_x = 1080
scene.render.resolution_y = 1080
scene.cycles.samples = 64
bpy.ops.render.render(write_still=True)

# 3. Open both the render AND the reference. If you don't have a reference,
#    web-search one BEFORE rendering. "real [plant name] in white pot"
#    typically gets a clean reference.

# 4. Score against the comparison checklist below. If ANY of these scores
#    differ meaningfully between render and reference, fix and re-render.
```

### Comparison checklist (score each render vs reference)

| Dimension              | What to check                                                    |
|------------------------|------------------------------------------------------------------|
| Overall silhouette     | Bushy ball vs tall spire vs cascading curtain vs upright stalks  |
| Stem height variance   | Are all stems similar height? Is one dominant (= spike)?         |
| Leaf/stem visual ratio | Can you see stem BETWEEN leaves, or are leaves a solid mass?     |
| Leaf orientation       | Are leaves randomly oriented, or all the same way (uniform)?     |
| Leaf size relative to flower | Are flowers smaller than leaves (normal) or larger (Footgun #7)? |
| Flower distribution    | Clustered at tips (lollipop, bad) vs distributed (good)?         |
| Plant fills pot        | Does foliage emerge from across the soil or one central tuft?    |
| Cascade behavior       | If cascading: airy drape with visible vine, or thick sausage?    |
| Color saturation       | Leaves vibrant green or pale/yellow (= sick-looking)?            |
| **Texture sharpness**  | **Are leaf edges crisp or pixelated/blurry? (Footgun #14)**      |
| **Texture orientation**| **Does the texture appear stretched/rotated wrong? (Footgun #15)**|

### "Looks-fine" anti-patterns I keep hitting

When you've just rendered and it looks reasonable in isolation, check
specifically for these — they're easy to miss without comparison:

  * **The central spike**: one Poisson-disk-inner stem with max `L` becomes a
    dominant Christmas tree spire above the bush. Cap `L` range so max/min ≤
    1.25x within a tier. Branch_000 in jasmine v7 was 1.10m vs 0.49m sibling
    = 2.2x = spike. (Footgun #4 extension.)
  * **The leaf sausage**: long drape vine with 10+ XL leaves packed close
    together looks like a thick rope, not vine-with-leaves. Use STRATIFIED
    t-bucket sampling (not random with rejection) and cap leaves per vine at
    6-8. Pothos v7 had 10.8 leaves/vine avg with random sampling → tight
    clusters; v8 uses stratified buckets with bucket_width margin = 20%.
  * **Lollipop tip clusters**: flowers all packed at t=1.0 of each stem gives
    "decorated stick" look. Use `t_range=(0.45, 0.99)` or `(0.65, 0.98)` with
    multiple sub-clusters per stem if you want clusters.
  * **Flat ground-touching droopers**: tier-3 stems reaching the floor →
    user reads as "wilted/depressed". Keep tier-3 tips at `z ≥ soil_top_z -
    0.20` unless plant is explicitly a cascading species.

### When working from a user-supplied reference

The user often posts photos of the real plant alongside the render. Don't
just acknowledge — actually compare:

  1. Describe the reference: silhouette, density, leaf type, leaf:flower
     ratio, leaf orientation, color, what's in/out of pot.
  2. Describe the render against the same dimensions.
  3. List the deltas explicitly. ("Reference has leaves throughout, mine has
     leaves only on bottom half" — that's actionable.)
  4. Fix the deltas, not the easiest thing to fix.

Do NOT skip step 3 — that's where most of these footguns live. The user
called me out in the v7 round for not having done this; they were right.
