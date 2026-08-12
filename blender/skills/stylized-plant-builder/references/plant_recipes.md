# Per-plant build recipes

Quick reference of parameter sets that produced each accepted .blend.
Paths are relative to the `peris-sim/` folder.

**Use with the `stylized-plant-builder` skill** — see `../SKILL.md` for the
build procedure and footgun list. This file is just the per-plant parameter
table; the lessons live in SKILL.md.

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

## Jasmine v14 (`stylized_plant_jasmine_v14.blend` — CURRENT)
- Same as v13 + **bezier P1 placed LOW** so the curve begins at the BASE of the stem, not the tip.
  - For heroes: `P1 = P0 + (0,0,L*0.15) + tilt_dir * tilt_amount * L * 0.25` — at 15% height already pulled into the bend direction
  - P2: `P0 + (0,0,L*0.50) + tilt_dir * tilt_amount * L * 0.75` — at 50% height, deep into the bend
- Hero tilt bumped further: `tilt_amount ∈ [0.35, 0.60]` (was 0.25-0.50)
- Hero stem trace shows continuous outward curve from t=0 to t=1: e.g. (-0.07, 0.0, 1.06) → (-0.64, 0.38, 2.50) for a 1.67m hero
- Footgun #20: P1-at-15%-height ensures the curve isn't ramrod-straight in the visible portion

## Jasmine v13 (DEPRECATED — see v14)
- Same as v12 PLUS:
  - **Hero stems bend significantly more**: `tilt_amount ∈ [0.25, 0.50]` (was 0.05-0.15), `lateral_angle ∈ [-π/2, π/2]` (was ±π/4). Bezier P2 placement biased much further along the bend direction.
  - **Density-proportional leaf nodes**: `n_nodes = max(3, min(12, int(L / 0.13)))` — guarantees ~1 node per 13cm regardless of stem length. Previously fixed-range nodes per stem made tall heroes look sparse.
  - 134 paired-leaf objects = 268 individual leaves total

## Jasmine v12 (DEPRECATED — see v13)
- Same structure as v11 (paired-leaf mesh + tilted stems + low-res palette)
- **Flower clusters now offset from stems** to prevent piercing (Footgun #16)
  - `t_cluster ∈ [0.88, 0.99]` (at tip, not midstem)
  - Pick single `cluster_dir` perpendicular to stem tangent + slight upward bias
  - Offset cluster center by ≥ 0.08m along cluster_dir
  - Individual flowers scatter only in the perpendicular plane (not back toward stem)
  - Per-flower distance check: skip if (loc - stem_point).length < 0.056
- 103 flowers + 79 buds in distinct clusters

## Jasmine v11 (DEPRECATED — see v12)

## Jasmine v9-v10 (DEPRECATED — see v11)
- **Pot**: scalloped white (unchanged)
- **Architecture**: thin stem tubes + PAIRED-LEAF meshes (single mesh with two leaves on ±X of central pivot) + 3D flower clusters
- **Stems**: DELIBERATE 3-tier spec (NOT Poisson — too uniform):
  - 2 heroes at r0 ∈ [0.05, 0.15], L ∈ [1.50, 1.85]
  - 7 medium at r0 ∈ [0.18, 0.40] with RANDOM thetas (not evenly distributed), L ∈ [0.95, 1.40]
  - 12 short outer at r0 ∈ [0.30, 0.55] random thetas, L ∈ [0.45, 0.80]
  - Tip-Z ratio 1.84x — proper variety, no spike
- **Stems TILT outward** by `tilt_amount * L`: hero ∈ [0.05, 0.15], medium ∈ [0.10, 0.30], short ∈ [0.20, 0.50]. Plus lateral rotation `±π/4` so they don't all lean same direction. Bezier control points biased to give organic curve, not pole.
- **Leaves**: PAIRED-LEAF mesh `JasLeafPair_S/M/L` — single mesh contains two leaves at (±length, 0, 0) sharing a center pivot at origin. Place ONE pair object per node, rotate so X-axis aligns with leaf_axis. Pivot is the attachment point → no off-center rotation artifacts (Footgun #12).
- **Flowers**: 1-3 clusters per stem at t ∈ [0.70, 0.98], each cluster has 2-7 flowers + 2-4 buds packed in 0.06m radius
- **Counts**: 21 stems, 113 paired-leaf objects (226 individual leaves), ~89 flowers, ~66 buds

## Jasmine v7-v8 (DEPRECATED)
- **Pot**: scalloped white (unchanged from v4)
- **Architecture**: separate thin stem tubes + individual oval leaf planes + 3D flowers/buds (NOT combined branch-cards). See SKILL.md Footgun #9.
- **Origins**: Poisson-disk sampled across soil_r=0.55, min_sep=0.13 → ~24 origins spread across the full soil surface. Tier by radius (Footgun #2):
  - `r0 < 0.18`: 'upright', L=0.95-1.40
  - `r0 < 0.36`: 'arch', L=0.75-1.15
  - else: 'short_arch', L=0.55-0.85 (do NOT make these reach the ground — Footgun #4)
- **Stems**: cylinder sweep along bezier, radius 0.010-0.014, 6 verts/ring, 22 segments
- **Leaves**: oval planes (JasLeafMesh_S/M/L_v3 at length 0.25/0.34/0.44), opposite-decussate phyllotaxy (90° rotation between successive nodes), 5-9 nodes per stem, normal biased upward + random tilt (Footgun #3)
- **Flowers**: JasmineFlowerMesh_v4 (R_petal=0.07 — small, 30-40% of leaf length per Footgun #7), distributed t in [0.45, 0.99] (NOT clustered at tips — Footgun #6)
- **Buds**: JasmineBudMesh_v2 (R=0.010, H=0.025), bud_chance rises with t (0.20 to 0.35)
- **Counts**: 24 stems, ~334 leaves, ~109 flowers, ~53 buds

## Jasmine v5 (DEPRECATED — see v7)
- **Pot**: scalloped white (unchanged from v4)
- **Branches**: bezier cards in 3 tiers — `upright` (6 spires of varied height to 1.6m), `arch` (16 mid-tier outward-curving), `droop` (only 4 SHORT drooping branches that just clear the rim, NOT long drape). 26 total.
  - Earlier v5 (8 long droopers reaching ground) read as "depressed/wilted" — keep droopers short
- **Width axis**: camera-perpendicular (`view_perp`) — width vector = `tg × view_dir`
- **Branch width**: 0.32-0.44, tapered to 70% at tip (less aggressive taper than first try)
- **Texture**: 64×96 RGBA — delicate ELONGATED leaflets (half_w=13, half_h=3) in opposite pairs along a thin stem with mid-vein shading and bright outer highlight. Critical: leaflets must read as fine + delicate, not chunky-square.
- **3D flowers**: `JasmineFlowerMesh_v3` (5-petal star, R_petal=0.16, wider petal base, yellow center disc Z=0.022). 3-5 per branch, ~100 total. Pure-white base color + 0.30 SSS for soft luminous bloom appearance.
- Important: do BOTH — more flowers AND bigger flowers AND brighter material. A handful of small flowers reads as "confetti", not blooms.

## Pothos v27 (`stylized_plant_pothos_v27.blend` — CURRENT)
**Single cubic bezier for ALL stems** with smooth `cascade = smoothstep(r_frac)`
interpolation of all 4 control points (Footgun #36 — no quad/cubic split).
- Length 1.0 + r_frac^1.3 * 1.5 (was 0.65 + ... — center stems now LONGER and more curved)
- P1 lateral bend: `bend_unit * 0.20 * L` where bend_unit lerps from random
  (center, organic curl) to outward (edge, cascade direction)
- P2 crest: `crest_r` lerps from `r0+L*0.20` (center) to `rim_outer+0.30` (edge)
- P3 tip: tip_r and tip_z both lerp; tip_z uses `cascade^1.2` for sharper
  floor approach at the outermost
- 35 vines, 181 leaves
- Texture un-rotated back to original orientation

## Pothos v26 (DEPRECATED — used hybrid quad/cubic with discontinuity at r_frac=0.50)
v25 + leaf density tuned down + texture rotated 180°.
- Leaf density `int(L / 0.32)` (was 0.22 — too dense)
- 144 leaves (was 217)
- PothosLeafTex rotated 180° — better orientation for default leaf placement

## Pothos v25 (`stylized_plant_pothos_v25.blend` — superseded by v26)
Cubic-bezier cascade (no sim) — fixes the v24 disaster where tip-pin sim
cut chains diagonally through the pot wall (Footgun #35).
- r_frac < 0.50: quadratic bezier (same as v24)
- r_frac >= 0.50: **CUBIC bezier with 4 control points**:
  - P0 = soil
  - P1 = directly above P0 at `z = rim_z + 0.20` (forces RISE)
  - P2 = `(rim_outer + 0.30) * radial_unit` at `z = rim_z + 0.05` (forces CREST FAR OUTSIDE wall)
  - P3 = drape tip just outside rim (`r = rim_outer + 0.10`, z = floor for outermost)
- Critical: P2.r must be `rim_outer + 0.30` minimum. With only +0.10 the
  descent from P2 to P3 still passes through the wall band.
- Same proportions as v24 (Footgun #33 measurements)
- 35 vines, 4 still clip "deeply" (z<rim_z-0.15 in wall band) — acceptable
- 217 leaves, ~1 per 22cm of chain length

## Pothos v24 (DEPRECATED — tip-pin sim cut chains through pot wall)
Hybrid: parametric for inner/mid (no sim), two-pin chain sim for outer cascade.
Built using measured proportions from Bloomscape silver-satin + golden pothos refs.

**Measured proportions (Footgun #33)**:
- Stem L ranges 0.5-2.0 × pot_dia: inner 0.5×, outer 1.5-2.0×
- Crown above rim: ~ pot_dia tall
- Drape below rim: ~1.5-2.0 × pot_dia
- Leaf width: ~0.4 × pot_dia (LARGE — 1/3 pot)
- Stem thickness: ~0.005-0.01 × pot_dia (very thin)
- Leaf density: ~1 per 0.2 × pot_dia of chain

**Two regimes by r_frac**:
- r_frac < 0.55: parametric quadratic bezier, no sim (mostly upright crown)
  - L = 0.65 + r_frac^1.5 * 1.85 (smooth gradient)
  - tip_z = soil + L * (0.95 - r_frac * 0.20) — mostly stays up
- r_frac >= 0.55: chain sim with TWO PINS (Footgun #34)
  - tip pinned at `(rim_outer + 0.05, drape_z)` — JUST outside rim, not far out
  - drape_z drops smoothly from rim_z (at r_frac=0.55) to floor (at r_frac=1.0)
  - chain L > straight base-to-tip distance × 1.3 → has slack to curve
  - apex pre-pose at rim_z + 0.20, midway radially
  - bend_iters: 5-8 (high stiffness, prevents collapse)
- 35 stems via Poisson disk (r_max=0.32, min_sep=0.06)
- 284 leaves, density ~1 per 22cm of chain length
- Quad bezier or sim-driven chain, parallel-transport tube sweep

## Pothos v23 (DEPRECATED — see v24)
**Smooth continuous gradient by radius** instead of discrete tiers (Footgun #31).
Tried Verlet sim (v21) — physically correct but produced "wilted" look (Footgun #32).
- 40 stems via Poisson disk in r=0.32 with min_sep=0.055, using power-1.5
  radius distribution (slight center bias)
- All parameters interpolate CONTINUOUSLY with `r_frac = r0/SOIL_R`:
  - L = 0.75 + r_frac * 0.55 + noise (shorter inner, longer outer)
  - apex_z = soil + L * (0.90 - r_frac * 0.25)
  - apex_r = r0 + L * (0.05 + r_frac * 0.25)
  - tip_z = soil + L * (0.95 - r_frac * 0.40) [never below rim — Footgun #32]
  - tip_r = r0 + L * (0.15 + r_frac * 0.45)
  - stem_radius = 0.025 - r_frac * 0.008
- Quadratic bezier, pot-wall rejection sampling (push apex further out if clipping)
- For outer half (r_frac > 0.6): apex_r and tip_r clamped to rim_outer + 0.10 so vines clear the pot
- 156 leaves: 3-5 per vine, stratified t in [0.35, 0.99], random forward+normal+360° twist per leaf

## Pothos v21-v22 (DEPRECATED — see v23). v21 used Verlet sim with discrete tiers (looked dead); v22 had too aggressive outer arch making it all cascade.
Actual physics sim via Python Verlet chain solver (Footgun #30).
- **Tried Blender soft body first; failed** — even with goal_spring=0.97 and
  goal_friction=25, the entire vine fell ~1.4m. The goal pin silently doesn't
  hold. Switched to in-Python Verlet sim.
- **Three tiers with different sim strategies**:
  - upright (40%): NO sim, just straight up with slight outward bias (L=0.45-0.90)
  - arch (30%): single-pin sim with pre-posed quadratic bezier initial chain (L=0.90-1.50)
  - drooper (30%): TWO-PIN sim — base + rim_pin around 30-40% along chain. Rim pin position = (rim_outer + 0.02) * radial_unit at z = rim_z + 0.05. Without rim pin, droopers fall straight down INTO the pot cavity (gravity has no horizontal component for a chain with single pin) (L=1.40-2.20)
- Chain sim: Verlet integration (dt=0.05, 180-220 iters), distance constraints (5 relax passes per step), bend constraint (1-3 applications based on tier stiffness), floor+wall collision per step.
- After sim, build tube mesh from settled chain positions via parallel-transport sweep.
- 40 vines, ~61 leaves (1 per tip + 1-2 mid-vine for longer chains)

## Pothos v20 (DEPRECATED — see v21)
4-tier parametric "gravity-pose" with collision-checked rejection sampling
(Footgun #28, #29). Long droopers actually reach the saucer level.
- 45 origins, Poisson radius 0.30, min_sep 0.055
- **4 petiole tiers** with weights 35/30/20/15:
  - `upright`: L=0.50-1.10, tip z = soil_top + L*[0.85, 1.0]
  - `arch`: L=0.80-1.40, tip z = soil_top + L*[0.20, 0.55]
  - `drooper`: L=1.20-1.80, tip z = rim_z - [0.30, 0.90]
  - `long_drooper`: L=1.80-2.40, tip z = saucer_z + [0.05, 0.40] (cascades to table)
- **Rejection sampling per stem** (up to 10 tries) checks BOTH `curve_clips_pot`
  AND `curve_below_floor`. Falls back to safe short stem if no valid config.
- Per-leaf random forward + normal + 360° twist around forward axis (Footgun #25)
- Leaf forward Z bias by petiole type: droopers' leaves face DOWN, uprights face up/out
- 45 leaves total, size pool varies by tier

## Pothos v19 (DEPRECATED — see v20)
Per-petiole architecture (still — like v18) PLUS wildness from real-ref study:
- **45 origins** in tighter `radius_max=0.30, min_sep=0.055` (was 32 in 0.40)
  — denser crown like real young pothos (Footgun #27)
- **3 petiole tiers** — Footgun #26:
  - 55% standard (L=0.70-1.40, pitch 0.30-0.85)
  - 30% droopers (L=0.50-1.00, pitch -0.40 to 0.10 — tip goes DOWN)
  - 15% young (L=0.25-0.55, pitch 0.50-0.95 — short close-to-soil)
- **Per-leaf random normal** (Footgun #25) — NOT a deterministic formula:
  - `nx = radial_xy.x * uniform(-0.3, 0.7) + uniform(-0.4, 0.4)` etc
- **Leaf forward direction** also per-leaf, with z-bias by tier (drooper leaves point DOWN)
- Variable leaf sizes per tier: standard gets random subset of [M,L,XL], droopers
  get [M,L,XL], young get [S,M,M]
- Scale 0.90-1.50 (was 1.25-1.65) — wider range gives leaf-size variety like reference

## Pothos v18 (DEPRECATED — see v19)
Restructured to match the young/compact pothos reference: **one big leaf per
short bent petiole, not multi-leaf stems**. This matches pilea/jade
architecture but with heart leaves at the tips.
- 32 petioles, each is a quadratic-bezier-bent tube ending in a single leaf
- Petiole length 0.90-1.60m (must be tall enough that leaves clear the pot —
  Footgun #22)
- Petiole pitch ∈ [0.40, 0.80]: 0=horizontal outward, 1=straight up. Lower
  pitch values fan leaves to the SIDES rather than all going up
- Tip outward extension: `radial_xy * L * (1 - pitch) * 1.5` — significant
  lateral spread
- P1 (mid control): `P0 + (0,0,L*0.5) + radial_xy * L * 0.15` (low so curve
  starts at base — Footgun #20)
- **Leaf orientation critical** (Footgun #23): the leaf NORMAL must face
  OUTWARD+UPWARD so broadside is visible to camera, not aligned with the
  petiole tangent. `desired_normal = (radial_xy * 0.5 + (0, 0, 0.8)).normalized()`,
  then project perpendicular to leaf_forward.
- Leaf forward (tip direction): outward + downward droop
- Sizes XL emphasis especially for longer petioles. Scale 1.25-1.65 (big mature)

## Pothos v15-v17 (DEPRECATED — see v18)
- Same as v14 PLUS scale-up:
  - **Stems 0.80-1.60m** (was 0.50-1.00m — v14 read as "baby plant")
  - **20 stems** (was 16), Poisson disk min_sep 0.16 (was 0.18)
  - **Density-proportional leaves**: `n_leaves = max(4, min(10, int(L / 0.18)))` — taller stems get more leaves spread along the full length
  - **Thicker stems** 0.032-0.048 (was 0.030-0.045)
  - 126 leaves total

## Pothos v14 (DEPRECATED — see v15)
- **Poisson-disk origin distribution** (16 origins in radius 0.50, min_sep 0.18) instead of even-theta. Even angular spacing made a "doughnut" with a visible split front-and-back (Footgun #21).
- **Random per-stem tilt direction**: each stem picks `tilt_angle = random.uniform(0, 2π)` — NOT radially outward. This kills the central gap.
- **Thicker stems**: radius 0.030-0.045 (was 0.020-0.028 — read as noodles, Footgun #13b confirmed for upright structure too)
- **Bigger leaf emphasis**: size_pool weighted toward L/XL especially in upper third
- **Longer petioles**: 0.08-0.18 (was 0.06-0.13) so leaves project further from stem
- 5-8 leaves per stem (was 3-6), 16 stems = ~103 leaves
- No supplementary cascade tier (v13's 5 cascade vines removed — too distracting from the upright character)

## Pothos v13 (DEPRECATED — see v14)
- **UPRIGHT structure** mirroring peace_lily_final (Footgun #17): 14 upright stems rising from soil with leaves arching outward + only 5 supplementary cascading vines (NOT the cascade-dominant v12 which read as "too droopy")
- Quadratic bezier for all vines (still — Footgun #13)
- Upright stems: P0 at soil, P1 = P0 + (0,0,L*0.6) + outward·arch·L*0.4, P2 = P0 + (0,0,L) + outward·tip_outward. L ∈ [0.40, 0.85].
- Cascade stems: apex at rim_outer+0.20-0.35, rim_z+0.30-0.50; tip drops 0.30-0.70
- Upright leaves can angle UPWARD (droop ∈ [-0.3, 0.4]), not just down
- Leaf-pool same as v12 (4 sizes × 5 twists, 14×14 PERIS_SIM_PALETTE texture)
- ~89 leaves total

## Pothos v12 (DEPRECATED — see v13)
- **QUADRATIC bezier** vines (3 control points) instead of cubic — was Footgun #13's source ("droopy", "no stiffness"). Quadratic gives a single parabolic arch with no mid-sag.
  - P0 = soil origin
  - P1 = APEX of arch (the only control point), at `r = rim_outer + [0.20, 0.40]`, `z = rim_z + [0.30, 0.55]` — must be HIGH AND FAR OUT
  - P2 = drape tip, drop varies by tier (short: 0.20-0.50, medium: 0.50-0.85, long: 0.85-1.20)
- **Thicker vine radius 0.028-0.040** (was 0.022-0.030 in v11 — too thin, read as wet noodle)
- Stratified-bucket leaf placement, 6-9 leaves per vine, full twist rotation
- 14×14 heart leaf texture using `PERIS_SIM_PALETTE`
- 14 vines

## Pothos v9-v11 (DEPRECATED — see v12)

## Pothos v9-v10 (DEPRECATED — see v11)
- **Pot**: tall white (PotMat must be `blend_method='OPAQUE'`)
- **Architecture**: STIFF arching vines with horizontal shoulder before drape
- **Critical bezier structure for vine stiffness** (Footgun #13):
  - P0 = soil origin
  - P1 = directly above P0 at z = rim_z + [0.20, 0.40] (vertical lift out of soil)
  - **P2 = SHOULDER**: at radius `rim_outer + [0.20, 0.45]` (horizontal extension), z = rim_z + [0.05, 0.20] (at/above rim). This is what gives the vine visible stiffness — the curve extends OUT horizontally before dropping.
  - **P3 = TIP**: radius can be slightly inside OR outside shoulder (no inward curl), z drops by varied amount based on drape kind:
    - 'short' (drop 0.30-0.60): tips just over the rim
    - 'medium' (drop 0.60-1.00): mid-cascade
    - 'long' (drop 1.00-1.40, weighted 3x more common): full cascade
  - 14 vines total spread evenly around (theta = even spacing + small jitter)
- **Leaves**: 20-variant mesh pool (4 sizes × 5 twist angles), stratified t-bucket sampling: 6-9 leaves per vine, bucket margin 20% to guarantee visible spacing between leaves
- **Counts**: 14 stiff vines, ~107 leaves

## Pothos v7-v8 (DEPRECATED)
- **Pot**: tall white, MUST set PotMat/SaucerMat to `blend_method='OPAQUE'` (Footgun #8 — inherited HASHED-blend bug)
- **Architecture**: vine tubes + individual heart leaf objects from a variety pool. See Footgun #9.
- **Vines**: 3 short "crown" (P3 just over rim) + 10 long "drape" (P3 at z=0.15-0.85, reaching toward saucer)
  - Tube radius 0.020-0.032, 7 verts/ring, 24 segments, taper 0.35
  - Bezier shape critical: P1 directly above (or slightly outward from) P0 at z ≥ rim_z + 0.20, P2 at r ≥ rim_outer + 0.20 at z ≥ rim_z + 0.05
  - Use `vine_clips_pot_wall(samples, ..., depth_threshold=0.10)` for rejection sampling (Footgun #5 — relaxed check allows natural rim emergence)
- **Leaf pool**: 4 sizes (S/M/L/XL) × 5 twist variants (-0.4, -0.15, 0, 0.15, 0.4) = 20 mesh variants. The twist is BAKED INTO THE MESH so even leaves with identical placement rotation look different (Footgun #3, item 1).
- **Leaf placement**: `place_leaves_along_vine()` — uniform along vine post-exit, NO phyllotaxy (pothos has alternate, single-leaf nodes). With FULL `random.uniform(0, 2π)` twist around the forward axis (Footgun #3, item 2). Side rotation `random.uniform(-1, 1)` so leaves can face stem-left/right not just outward (Footgun #3, item 3). Droop range 0.05-0.95.
- **Counts**: 13 vines, ~141 leaves, no flowers (pothos rarely blooms indoors)

## Pothos v5-v6 (DEPRECATED — see v7)
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
