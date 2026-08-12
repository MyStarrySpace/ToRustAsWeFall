# Bridge collapse reference

The destructible_hallway.blend in this repo is the canonical reference build.
This file documents the exact procedure that finally worked, after 3 failed
physics attempts and 5 keyframe iterations.

## Scene structure

Inside `elevator/destructible_hallway.blend`:

- **Static corridor (does NOT fall)**:
  - `Floor`, `Ceiling`, `Wall_Back`, `Wall_L_*`, `Wall_R_*`
  - `Pillar_L_*`, `Pillar_R_*` — corridor support pillars (do not confuse
    with railing posts)
  - `Pipe_*` — ceiling pipes
  - `Light_L_*_box`, `Light_L_*_glow` — wall-mounted lights
  - `Elev_*` — elevator at the back
- **Bridge (DOES fall)**:
  - `Walkway_Seg0` — walkway base slab
  - `Walkway_Seg1_p_i_j_k`, `Walkway_Seg2_p_i_j_k` — fractured cells (4×3
    grid per segment)
  - `Railing_F_*`, `Railing_B_*` — front and back railings (3 horizontal
    bars + 6 posts each side, 18 total)

## The procedure

```python
import bpy, mathutils, random
from helpers import (collapse_to_floor, verify_animation_z,
                    apply_clown_pass, restore_materials)

falling = [o for o in bpy.data.objects
           if o.name.startswith('Walkway_Seg1_p_')
           or o.name.startswith('Walkway_Seg2_p_')
           or o.name == 'Walkway_Seg0'
           or o.name.startswith('Railing_')]

# Cells fall at frame 30, rails at frame 38 (8 frames later)
is_rail = lambda o: o.name.startswith('Railing_')
subgroups = [
    (is_rail, 8, 4),                  # rails: break_frame+8, +random[0..4]
    (lambda o: True, 0, 3),           # everything else: break_frame, +[0..3]
]

collapse_to_floor(
    falling,
    floor_z=0.0,
    break_frame=30,
    jitter=3,
    fall_duration=30,
    drift_xy=0.10,
    tilt_deg=18,
    subgroups=subgroups,
    seed=42,
)

# Verify before rendering
report = verify_animation_z(falling, frames=[1, 30, 50, 65, 100, 150])
for f, info in report.items():
    print(f, info['highest'], info['lowest'])

# Expected at frame 100+: highest object's bbox center near floor + post_height/2
```

## What I had to do that's NOT in helpers.py

The current bridge had **degraded mesh data** from earlier failed attempts
(rails with origins at floor but mesh extending 2.4 units up). After
`origin_set` repaired the origins, several rails ended up at world Z = 5-6
(above the ceiling) because their visible mesh had been at z=2.5-3 with origin
at z=3+. To get them back to a sensible bridge height I had to explicitly
override the rest position:

```python
# Apply AFTER prepare_for_animation, BEFORE collapse_to_floor or keyframe_fall
RAIL_BAR_Z = 2.92
RAIL_POST_Z = 2.70
BRIDGE_TOP = 2.45

for o in falling:
    h = height(o)
    if o.name.startswith('Walkway_'):
        o.location.z = BRIDGE_TOP - h / 2.0
    elif 'post' in o.name:
        o.location.z = RAIL_POST_Z
    else:  # rail bar
        o.location.z = RAIL_BAR_Z
```

This was a one-time recovery for this file. For a fresh scene, the rest
positions captured by `collapse_to_floor` (= current `bbox_center_z`) should
be correct.

## Render pipeline

```python
scene = bpy.context.scene
scene.render.resolution_x = 1280
scene.render.resolution_y = 960
scene.cycles.samples = 32
scene.render.filepath = '/path/to/frames/frame_'
scene.render.image_settings.file_format = 'PNG'
bpy.ops.render.render(animation=True)
```

Encode + pad the loop boundary:

```bash
ffmpeg -y -framerate 30 -i frames/frame_%04d.png \
  -vf "tpad=stop_mode=clone:stop_duration=2" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 collapse.mp4
ffmpeg -y -i collapse.mp4 \
  -vf "fps=20,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  collapse.gif
```

The `tpad` 2-second pad makes the GIF loop boundary "settled debris → restart"
instead of "settled debris → intact bridge", which reads as floating up.

## Iteration log (so future me doesn't repeat these)

1. **v1-v5: Cell fracture + rigid body sim.** Cells exploded outward from
   phantom self-overlap forces. Tried various `collision_margin`,
   `collision_shape='CONVEX_HULL'`, manual cell separation. None reliable.
   Lesson: rigid body for 25 already-touching shards is fragile.

2. **v6-v8: Keyframed kinematic toggle.** Set `rigid_body.kinematic` keyframes
   so cells held still then released. The boolean keyframes interpolated as
   BEZIER (default) and refused to flip. Switched to CONSTANT — worked, but
   stale ptcache silently overrode the result.

3. **v9: Pure keyframes, no physics.** Worked for cells (origin = mesh
   center), failed for rails (origin offset). User saw "floating ghost
   bridge" of railings staying at bridge height while cells fell.

4. **v10-v12: More keyframe tweaking.** Did not address the origin offset.
   Same bug, three more times. Each time I "verified" by checking
   `o.location.z` which lied.

5. **v13: Locked extrapolation, padded loop.** Bandaid. Real bug still there.

6. **v14: Origin_set + bbox-center verify.** This is what works. Extracted
   into helpers.py.
