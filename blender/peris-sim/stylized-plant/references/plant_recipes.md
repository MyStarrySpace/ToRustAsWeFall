# Per-plant build recipes

Quick reference of the parameter sets that produced the latest accepted .blend per plant. All file paths are relative to this folder's parent (`peris-sim/`).

## Pilea peperomioides (`stylized_plant_pilea_v10_sss.blend`)
- **Pot**: stoneware urn `[(0.58,0),(0.78,0.18),(1.00,0.45),(1.18,0.78),(1.20,1.00),(1.16,1.22),(1.04,1.42),(0.98,1.55)]`
- **Leaf**: 3D mesh disc, peltate offset 0.32, dome center +0.04
- **Petioles**: bezier-bent cylinder, 8-vertex disc, taper to 0.55
- **Counts**: 6 inner-tall, 12 mid, 12 outer = 30 leaves
- **SSS**: weight 0.18, radius (0.45, 0.75, 0.25), scale 0.08
- **Texture**: 16×16 round leaf, dark mid-vein dot, light edge

## Calathea (`stylized_plant_calathea_v11.blend`)
- **Pot**: small concrete (tapered cylinder)
- **Leaf**: V-channel + length-arch (subdivide leaf into 4 quads, raise outer edges + bend midline)
- **Bump map**: image-derived bump strength 0.4 for herringbone vein detail
- **Counts**: 4 tall + 8 medium + 8 short = 20 leaves
- **Twist**: 0 (zero — V-shape gives all needed variety)
- **r0_range**: (0.10, 0.32) — origins spread across soil
- **Texture**: 14×34 lance with V-stripes from midrib

## Boston fern (`stylized_plant_boston_fern_v13.blend`)
- **Pot**: small terracotta `[(0.42,0),(0.50,0.06),(0.58,0.20),(0.62,0.40),(0.65,0.55),(0.66,0.70)]`
- **Frond**: curved card on **quadratic bezier** (NOT cubic — cubic causes twist)
- **Texture**: procedural via `fern_frond_grid(W=20, H=110, PINNA_SPACING=4, PINNA_HEIGHT=3, MAX_EXTENT=6)`
- **Card aspect**: 0.20 × 1.10 (width × length) — matches texture aspect
- **Counts**: 42 fronds across 3 tiers (upright / arching / drooping)
- **Width**: horizontal-perp (NOT view-perp); fronds drape vertically
- **Drape ranges**: out_r ∈ [0.55, 0.80] · L, tip_h ∈ [-1.2, -0.4], peak_z ∈ [0.65, 1.10]

## Jasmine (`stylized_plant_jasmine_v5.blend`, second iteration)
- **Pot**: scalloped white (unchanged from v4)
- **Branches**: bezier cards in 3 tiers — `upright` (6 spires of varied height to 1.6m), `arch` (16 mid-tier outward-curving), `droop` (only 4 SHORT drooping branches that just clear the rim, NOT long drape). 26 total.
  - Earlier v5 (8 long droopers reaching ground) read as "depressed/wilted" — keep droopers short
- **Width axis**: camera-perpendicular (`view_perp`) — width vector = `tg × view_dir`
- **Branch width**: 0.32-0.44, tapered to 70% at tip (less aggressive taper than first try)
- **Texture**: 64×96 RGBA — delicate ELONGATED leaflets (half_w=13, half_h=3) in opposite pairs along a thin stem with mid-vein shading and bright outer highlight. Critical: leaflets must read as fine + delicate, not chunky-square.
- **3D flowers**: `JasmineFlowerMesh_v3` (5-petal star, R_petal=0.16, wider petal base, yellow center disc Z=0.022). 3-5 per branch, ~100 total. Pure-white base color + 0.30 SSS for soft luminous bloom appearance.
- Important: do BOTH — more flowers AND bigger flowers AND brighter material. A handful of small flowers reads as "confetti", not blooms.

## Pothos (`stylized_plant_pothos_v6.blend`)
- **Pot**: tall white (same mesh as v5 — but PotMat must be `blend_method='OPAQUE'`; the v5 file had it stuck on HASHED with a 19%-alpha texture making the pot look black with stripes)
- **Pot wall profile**: outer radius 0.78 at rim, inner 0.66 at rim, narrows downward. The pot is hollow; vines may pass through the cavity (hidden by soil) but MUST NOT cross the wall band (0.66 < r < 0.78 below rim_z=1.55) or any part where leaves attached to the vine would protrude into the pot.
- **Vines**: thin tube meshes (cylinder swept along cubic bezier, parallel-transport frame to avoid twist)
  - Radius 0.022-0.032, 7 verts per ring, 24 segments, taper to 65% at tip
  - CRITICAL P1 placement: directly above P0 (same X,Y as origin) but at `z >= rim_z + 0.15`. This forces the curve to rise vertically out of the pot BEFORE going outward. Without this, the cubic interpolation cuts diagonally through the wall.
  - P2 must be at `r >= rim_outer + 0.15` and `z >= rim_z + 0.02` (well outside, above rim).
  - Two vine sub-tiers: 6 "crown" (P3 just over the rim, shallow droop) + 8 "drape" (P3 0.6-1.3m below rim for long cascade).
  - Always use rejection sampling: regenerate if the sampled curve has any point in `rim_inner-0.03 < r < rim_outer+0.03` at `z < rim_z+0.05`. With strict bounds this rejects ~95% of random tries — that's normal.
- **Leaves**: SEPARATE objects, each one a heart-shaped polygon mesh, not a painted strip
- **Leaf placement gate**: compute `t_exit` = first sample t where the vine is outside the pot (r > rim_outer+0.05 OR z > rim_z+0.02). Only place leaves at t > t_exit + 0.10. Also reject any leaf whose CENTER ends up inside the pot bbox after the petiole offset.
  - Heart outline = parametric `16sin³(t), 13cos(t) - 5cos(2t) - 2cos(3t) - cos(4t)` (24 verts), triangle-fanned to a slightly-raised center vert for subtle 3D curl
  - 4 size variants (S/M/L/XL: 0.22-0.48m length, 0.18-0.40m width)
  - 7-11 leaves per vine, biased denser at the drape (high t) using XL there
  - Each leaf oriented with tip along outward+downward direction, normal roughly +Z, with side-bias variety (-1..+1)
- **Leaf texture**: 32×32 procedural — DARK central vein, MID/LIGHT shading by distance from center, plus 8 random yellow variegation streaks (golden pothos look). MUST be `interpolation='Closest'` for crisp pixel style.
- **Materials**: `PothosStemMat` (desaturated brown-green) for vines; `PothosLeafMat` with leaf-texture + 0.12 SSS for leaves
- **Total**: 16 vines + ~140 leaves. Leaves clearly read as separate elements that "pop out" from the vines (vine radius ~0.025 vs leaf width ~0.18-0.40 → ~10× scale ratio)
- **Footgun**: in the v5 file, `soil.location.z` reads 0 but the soil MESH verts are at world z=1.49 (the origin is at world 0, geometry baked at rim height). Always read `max((soil.matrix_world @ v.co).z for v in soil.data.vertices)`, not `location.z + dimensions.z/2`.

## Haworthia (`stylized_plant_haworthia_v5.blend`)
- **Pot**: small terracotta (same profile as Boston fern)
- **Spike**: V-channel tapered card, tip-curl-up (last quad bent up)
- **Counts**: 50-60 spikes in 5 concentric rings, varying elevation
- **Twist**: 0
- **r0_range**: 5 rings from 0.04 to 0.34
- **Texture**: 12×40 dark green with light dots (variegation)

## Pothos v5 (DEPRECATED — see v6 above)
- v5 used a single curved card per vine with heart-leaves painted as a strip along V. Result read as a palm-tree head dropped into a pot — no visible separation between vines and leaves, leaves blurred together.

## Jade (`stylized_plant_jade_v3.blend`)
- **Pot**: wide stoneware
- **Trunk**: 3D bmesh main trunk + branches
- **Leaves**: small flat cards in canopy clusters at branch tips
- **Counts**: 200+ leaves across all clusters
- **Leaf direction**: spherical distribution around branch tip
- **Texture**: 8×10 small oval leaf

## Spider plant (`stylized_plant_spider_v3.blend`)
- **Pot**: round white
- **Leaf**: curved card on **quadratic bezier**
- **Counts**: 40-50 mixed upright / arching / drooping leaves
- **Texture**: 16×80 striped (white center, green edges)

## Peace lily (`stylized_plant_peace_lily_v6.blend`)
- **Pot**: tall dark gray
- **Leaf**: V-channel + length-arch (same as Calathea)
- **Counts**: 20-25 leaves in 3 tiers + 5 white spathes
- **Spathes**: same flat-card builder, larger SSS weight 0.30, near-uniform radius (0.85, 0.80, 0.65)
- **r0_range**: (0.10, 0.32)
- **Texture**: 16×40 dark green for leaves; pure white with subtle ridges for spathes

## 3x3 garden scene (`stylized_plant_garden_3x3_v13fern.blend`)
- All 9 plants linked via `bpy.data.libraries.load(blend_path, link=False)`
- 3×3 grid layout, 5.0 unit spacing
- Camera at (15, -18, 13), looking at (0, 0, 1)
- Dimmer 4-point lighting: Key=280, Fill=80, Rim=100, Top=90
- 1800×1200 render, Cycles 96 samples
