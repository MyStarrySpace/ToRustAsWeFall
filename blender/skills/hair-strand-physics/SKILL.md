---
name: hair-strand-physics
description: Generate low-poly hair (or any tendril/spine/quill/feather/cloak-fringe) strands from a base mesh and rig them with cloth simulation so they hang and sway naturally. Each face of the base mesh becomes one strand via per-face inset → extrude-N-times → power-curve bending weight assignment → cloth + self-collision. Use when the user wants soft dynamic hair, dreadlocks, frill, kelp, hanging chains, or any other strand-array effect on a character/object.
---

# Hair-Strand Physics Skill

A reusable Python pipeline for turning a base mesh (e.g., a scalp cap, a kelp anchor, a peacock body) into an array of low-poly cloth-simulated strands. The result is rigid roots, gracefully bending bodies, and dangling tips that respect collision with the underlying body and each other.

Read `helpers.py` for the actual reusable code.

## Visual signature

- **Rigid roots, floppy tips.** Per-vertex bending stiffness ramps from 1.0 at the base to ~0.02 at the strand tip via a power curve. Strands don't buckle at the scalp; they curl gracefully along their length.
- **Alternating hinge/segment topology.** Each strand has SHORT extrusion segments (act as bend hinges) alternating with LONG segments (act as rigid body sections). Bending concentrates at the hinges; the long segments stay straight.
- **Density gradient.** Long segments ramp from shorter near base to longer near tip — gives more articulation closer to the head where it's needed, then sweeps out to longer end pieces.
- **Length variation by base position.** Strands attached near the top of the head are long; strands near the face/ears are short. Driven by face Z position with a 0.45–1.0 length factor.
- **Asymmetric curl via per-extrude bias.** A small constant vector (e.g., +X) added to every extruded vert accumulates over N steps to produce side-swept hair.

## When to use

- **Character hair** — dreadlocks, dreads, long ponytails, afros, plumage, peacock tail.
- **Cloak fringe** — tassels hanging off a robe edge, the bottom edge of a kilt.
- **Soft tentacles** — kelp, anemone fronds, jellyfish trails.
- **Spine arrays** — hedgehog spines, porcupine quills (use stiffer cloth settings, almost no bending).
- **Frill / wing edge** — bird wing feathers attached to a wing armature.

When to NOT use:
- Single hero strand that needs precise art control → keyframe it instead.
- Long flowing hair where you want polished sweep curves → use Blender's particle hair or the new Hair Curves system.
- Strands that need physically simulated wind interaction in-game → cloth is fine for cutscene/cinematic; for realtime, bake to vertex animation.

## High-level pipeline

1. **Inputs:** a base mesh (the "scalp"), parented to whatever skeleton/armature you want.
2. **For each face of the base mesh:**
   - Inset the face by `INSET_THICKNESS` (absolute, e.g., 0.01) — creates a smaller inner rectangle surrounded by 4 strip faces. The strip is the strand "root collar"; the inner rectangle is the strand cross-section.
   - Cache the face's normal direction BEFORE extruding (so all extrudes go consistently along that direction; tiny float drift in the per-extrude face normal causes strands to curl unpredictably otherwise).
   - Extrude the inset face `N_EXTRUDES` times (typically 8–12). After each extrude, translate the new verts by `step_vector + bias_vector`. Step alternates between SHORT (hinge, e.g., 0.012) and LONG (segment, e.g., 0.06–0.12 scaled by length_factor and ramped along the strand). Bias is a constant nudge in some direction (e.g., (+X, 0, 0) for rightward sweep, (0, 0, -0.005) for natural droop).
3. **Vertex groups:**
   - `HairBase` — every vert on the inset strip faces + the original face verts. These get pinned in cloth (pin stiffness 100, vertex_group_mass).
   - `HairBend` — BFS distance from every vert to the nearest base vert (in edges). Weight = `(1 - d/max_d)^2.5`. Base = 1.0, tip ≈ 0.02. Assign to cloth's `vertex_group_bending`.
4. **Cloth modifier** on the strand mesh:
   - `mass = 0.5`, `tension/compression = 3`, `shear = 1`, `bending_stiffness = 1.5`, `bending_stiffness_max = 0.05`.
   - `pin_stiffness = 100`, `air_damping = 0.5`, `tension_damping = 1`, `bending_damping = 0.3`.
   - Self-collision ON with `self_distance_min = 0.010`, `self_friction = 5`.
   - External collision: `distance_min = 0.015`, `collision_quality = 10`.
   - Cloth `quality = 15` (more sim substeps for clean collision).
5. **Collision modifiers** on every nearby mesh (body, clothes, hat, ground): `thickness_outer = 0.02`, `thickness_inner = 0.005`, `damping = 0.5`.
6. **Bake** the point cache via `bpy.ops.ptcache.bake_all(bake=True)` with proper window override.

## ⚠️ The single biggest footgun: face normal drift across extrudes

When you do `extrude_face_region` N times in a row, each new top face has a freshly computed normal. After 8–12 extrudes, floating-point error in the normal direction accumulates and the strand visibly curls or twists even though you never asked it to. The fix is one line: **cache the original face's normal vector before the first extrude and use that cached direction for every extrude step.**

```python
for orig_face in original_faces:
    n = orig_face.normal.normalized().copy()  # ← cache it
    current_top = orig_face
    for i in range(N_EXTRUDES):
        ext = bmesh.ops.extrude_face_region(bm, geom=[current_top])
        new_verts = [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]
        new_faces = [g for g in ext['geom'] if isinstance(g, bmesh.types.BMFace)]
        for v in new_verts:
            v.co += n * step  # ← cached n, not current_top.normal
        current_top = new_faces[0]
```

If you use `current_top.normal` instead, the strands will look correct in the first 3–4 extrudes and then start drifting sideways. Caught me out for an hour.

## ⚠️ Bending weight: linear ramp looks wrong; use a power curve

A linear ramp `weight = 1 - d/max_d` makes the midpoint of the strand half-stiff. The strand still buckles near the base because the inner edges support all the weight above them, and "half stiff" isn't stiff enough to resist the leverage. The strand ends up twisted/chaotic near the scalp and rigid at the tips — the opposite of what you want.

**Use a power curve `(1 - d/max_d)^2.5`** to keep the base nearly full-stiffness for the first half of the strand, then drop off rapidly toward the tip. The strands bend along their length rather than folding at the root.

| distance | linear | power 2.5 |
|---|---|---|
| 0 (base) | 1.00 | **1.00** |
| 1 | 0.88 | 0.72 |
| 4 | 0.50 | 0.18 |
| 6 | 0.25 | 0.031 |
| 8 (tip) | 0.00 | 0.02 |

## ⚠️ Cloth needs `vertex_group_bending` AND a `bending_stiffness_max` to use the gradient

It's not enough to assign the bending vertex group. Cloth interpolates the per-vertex bending stiffness from `bending_stiffness * weight` down to `bending_stiffness_max`. If `bending_stiffness_max` is missing or equal to `bending_stiffness`, the gradient has no effect. Set them as a range — e.g., 1.5 base, 0.05 minimum.

Some Blender 5.x builds report `bending_stiffness_max` as a single-set-but-internally-mirrored value; if you check immediately after assignment you may see both fields read the same. Set, save the .blend, and re-bake; the gradient is in effect even if the inspect API is confusing.

## ⚠️ Pin-group identification — use bmesh tags, not Z coordinates

Naive "pin everything with z < 1.1" works only for strands extruded straight up. If your strands extrude along face normals (which is what looks natural), strands pointing sideways have their entire bodies at low Z, and your filter pins the whole strand.

**Use `v.tag = True/False` during the bmesh extrude loop** to mark base-vs-extruded verts. Set tag True on all verts before starting (including inset-created verts), then set tag False on each extrude's new verts. After bm.to_mesh, read the tags off and build the vertex group from those.

```python
for v in bm.verts: v.tag = True
# ...
for v in inset_result['faces'][i].verts: v.tag = True  # strip face verts stay base
for v in orig_face.verts: v.tag = True                 # inset face = prism bottom = base
# ...
for v in ext_verts: v.tag = False                       # extruded verts are floppy
# ...
base_indices = [v.index for v in bm.verts if v.tag]
```

## ⚠️ Cloth must be FIRST in the modifier stack on a Mirror/Subsurf/Solidify object

If the base mesh uses Mirror + Subdivision + Solidify (common for character clothing), put the Cloth modifier at the TOP of the stack. Cloth simulates the source half-mesh; Mirror duplicates the simulated result; Subsurf smooths; Solidify thickens. The other order (Mirror → Cloth) means cloth tries to simulate a non-manifold doubled mesh and behaves unpredictably.

## ⚠️ Collision modifier vs Cloth modifier

A given object can be ONE of:
- A cloth body (has Cloth modifier) — simulates softly, collides with other objects.
- A passive collider (has Collision modifier) — static, pushes cloths away.

Not both. If you give Coat a Cloth modifier, remove its Collision modifier; the Hair will still collide with the Coat because cloths automatically interact with each other via self-collision when overlapping.

## Asymmetric curl via per-extrude bias

To make strands lean to one side (Aster's swept-back dreadlock look):

```python
RIGHT_BIAS = 0.012  # per-extrude rightward offset in local units
bias = Vector((RIGHT_BIAS, 0, 0))
for i in range(N_EXTRUDES):
    # ... extrude ...
    for v in new_verts:
        v.co += n * step + bias  # ← bias accumulates over N extrudes
```

Total bias at the tip = `RIGHT_BIAS * N_EXTRUDES`. For N=12 and bias=0.012 → 0.144 local units rightward = visible side sweep.

You can also use a constant downward bias to give strands a natural pre-gravity droop, which the cloth sim then refines.

## Wavy and curly variants

The same pipeline produces wavy or curly hair by adding a periodic per-extrude offset perpendicular to the strand normal. The pipeline already caches the strand normal `n` (see the face-normal-drift warning); for wavy/curly we additionally build two basis vectors `u`, `v` perpendicular to `n`:

```python
world_z = Vector((0, 0, 1))
ref = Vector((1, 0, 0)) if abs(n.dot(world_z)) > 0.95 else world_z
u = n.cross(ref).normalized()
v = n.cross(u).normalized()
```

**Wavy** — sinusoidal back-and-forth in the `u` direction:

```python
t = (i + 1) / N_EXTRUDES        # 0 < t <= 1 along the strand
offset = sin(2*pi * frequency * t + phase) * amplitude
wave_bias = u * offset
v_world.co += n * step + constant_bias + wave_bias
```

- `amplitude` 0.02–0.04 in local units
- `frequency` 1.5–2.5 cycles per strand
- `phase` randomized per strand (e.g., per-face hash) so neighboring strands aren't synchronized

The strand snakes left/right as it extrudes outward, ending at the tip. Looks like loose textured hair, soft beach waves, or kelp blades.

**Curly** — corkscrew spiral around the strand axis using both `u` and `v`:

```python
t = (i + 1) / N_EXTRUDES
angle = 2*pi * frequency * t + phase
wave_bias = (u * cos(angle) + v * sin(angle)) * amplitude
```

- `amplitude` 0.02–0.035 in local units (corkscrew radius)
- `frequency` 2–4 turns per strand for tight curls; 0.5–1 turn for ringlets
- `phase` randomized per strand

The strand corkscrews outward, each segment offset slightly around the central axis. Looks like coily/curly hair, telephone cords, fiddlehead ferns.

**Combining with `right_bias`** is fine — the curl/wave is added on top of the constant bias, so you can have wavy hair that ALSO leans to one side. They live in different directions (`u`-perpendicular vs `+X` world) so they don't fight.

**Pick wave frequency and N_EXTRUDES together.** Each wave needs enough segments to resolve. With 12 extrudes and frequency 2.0, you get 6 segments per cycle, which is the minimum for a recognizable sine. Bump `N_EXTRUDES` to 14–16 if waves look polygonal/zigzaggy, especially for curly mode where every quarter-turn needs at least one segment.

**Bake time** — wavy/curly geometry has more bending energy stored at rest, so cloth simulation takes more substeps to settle without exploding. Increase `cloth.settings.quality` to 20+ for curly hair. If strands "jitter" during the first frames of bake, drop `mass` slightly (0.3–0.4 instead of 0.5).

## Density gradient (more segments near base)

Bending concentrates at the SHORT (hinge) segments. To get more bending control near the scalp:

- Increase total `N_EXTRUDES` (12 instead of 8).
- Ramp the LONG segment length OUTWARD: shorter near base, longer near tip.

```python
RAMP_START = 0.55   # near base, LONG = LONG_BASE * 0.55
RAMP_END = 1.20     # near tip, LONG = LONG_BASE * 1.20

for i in range(N_EXTRUDES):
    if i % 2 == 0:
        step = SHORT_LEN
    else:
        t = i / (N_EXTRUDES - 1)
        long_factor = RAMP_START + (RAMP_END - RAMP_START) * t
        step = LONG_BASE * length_factor * long_factor
```

Combined with the bending power-curve, this gives fine bending articulation at the base where the user reads expression, and longer rigid tip segments that drape gracefully.

## Length variation by face Z position

For a hair cap on top of a head, strands near the top should be long (covering the skull and falling); strands near the temples/forehead should be short (don't extend past the face). Map face center Z to a length factor:

```python
z_norm = (face_center.z - Z_MIN) / (Z_MAX - Z_MIN)  # 0..1 over the scalp's z range
length_factor = 0.45 + 0.55 * z_norm   # 0.45 at face level, 1.0 at crown
```

Strands at Z_MAX (crown) are 1.0× full length; strands at Z_MIN (temples) are 0.45×. Multiplied through the LONG segment ramp to scale every long segment in that strand.

## Reference

- `helpers.py` — `extrude_strand_array()`, `compute_bending_weights()`, `setup_cloth_and_collision()`, `bake_and_render_preview()`.
- The Aster character build in this repo (`characters/aster.blend`) is the canonical reference. Hair object is "Hair", base mesh is the original 32-face cap with Mirror modifier.

## Variations that work the same way

- **Cloak fringe.** Use a strip of faces along the bottom edge of a cloak. Pin top of strip, extrude tassels downward, longer LONG segments since gravity does the work, less bending stiffness gradient needed.
- **Soft horns/antlers/spines.** Use much stiffer cloth (bending_stiffness 15, mass 0.05) so they barely bend. Skip the bias and the length-by-Z variation; let them point along their face normals as rigid spikes that respond slightly to motion.
- **Bird tail / peacock plumage.** Use longer LONG segments (0.2+), single-sided cloth (one row of strands along the tail base), no self-collision needed (strands are far apart), strong RIGHT_BIAS or similar to fan them outward.

## What this skill does NOT cover

- **Polished hairstyles** — for art-directed flowing locks use Blender Hair Curves (particle hair).
- **Wet-hair or stranding clumps** — would need vertex paint guides and per-strand mass adjustments not implemented here.
- **In-engine real-time hair** — bake the cloth animation to vertex animation textures and play back in the engine; cloth modifier won't run at runtime.
- **Per-strand color/material variation** — the strand mesh is one mesh with one material. To color tip-vs-base differently, use the same BFS-distance vertex group to drive a shader gradient.
