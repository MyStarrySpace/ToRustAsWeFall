---
name: procedural-animation
description: Author keyframed procedural animations for Blender scenes — bridge collapses, falling debris, structural failure, scattered objects coming to rest. Use when the user wants pre-existing geometry to move/fall/break apart on a timeline without setting up a physics simulation. Covers the gotchas around object origin vs mesh data, fcurve extrapolation, layered-action API in Blender 5.x, and the diagnostic workflow for catching problems BEFORE re-rendering 150 frames.
---

# Procedural Animation Skill

A reusable playbook for keyframed multi-object animations in Blender 5.x via Python — falling debris, structural collapses, scattered settling, etc.

Read `helpers.py` for the actual reusable code. This file is the design playbook: the bugs I hit, why they happened, the verification workflow that would have caught them at the start.

## When to use this over rigid-body physics

**Use keyframes when:**
- The motion is predictable / deterministic (fall straight down, slide, swing)
- You need every piece to land in a specific final state
- The number of pieces is < ~100 (43 worked great; 1000 needs sim)
- You'd otherwise have to bake a sim and the result keeps not matching what you want

**Use physics when:**
- Pieces should bounce off each other or off the floor
- The chaos *is* the point (explosion, structural shear with cascading collapse)
- You'd accept "approximately correct" and let the solver pick poses

The bridge collapse in this repo went through 3 failed physics attempts (cells exploding outward from phantom self-overlap forces, kinematic keyframes not respecting CONSTANT interp, stale rigid-body cache silently overriding fcurves) before switching to pure keyframes succeeded. **For deterministic falls, keyframes are dramatically more reliable.**

## ⚠️ The single biggest footgun: object origin ≠ mesh center

**Symptom:** You keyframe `obj.location.z` from rest height to floor. The visual mesh doesn't move. `obj.matrix_world.translation.z` reads correctly (it changed). But the mesh sits stubbornly at its original height, looking like a ghost.

**Cause:** The object's origin is at one place (e.g., world z=0 from the original modeling step), but the mesh data extends from z=2.4 to z=2.9 in object-local coordinates. When you keyframe `location`, you're keyframing the origin. The mesh, which is drawn at `origin + local_vertex_pos`, slides along with the origin — but if you started with a non-zero local offset and your "fall" only moves the origin from z=0 to z=0.05, the mesh barely moves: it goes from z=2.4-2.9 → z=2.45-2.95.

**Fix:** Before keyframing, run `bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')` on every object you plan to animate. This moves the origin to the bbox center and shifts mesh data so locally everything is centered around 0. Now keyframing `location` actually moves what's on screen.

```python
# CRITICAL — must deselect everything first, then select only the target
for o in falling_objs:
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
```

Doing this in batch with `bpy.context.temp_override(...)` was unreliable in my testing — it silently no-ops on most objects with "Set Origin not supported for Light object(s)" warnings even when no lights are involved. The deselect-then-select pattern works on every object.

**Verify** by checking that mesh local extent is centered on 0:
```python
lb = [mathutils.Vector(c) for c in o.bound_box]
local_z = (max(v.z for v in lb) + min(v.z for v in lb)) / 2
assert abs(local_z) < 0.05, f'{o.name} mesh still offset from origin'
```

## ⚠️ Always test with bbox center, never with origin

`obj.matrix_world.translation` returns the origin position. If origin and mesh center don't agree (see above), this lies. **Always verify visible position via the world bbox center:**

```python
def visible_z(o):
    bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    return (min(v.z for v in bb) + max(v.z for v in bb)) / 2
```

I declared "everything is on the floor at frame 100" three separate times based on `o.location.z == 0.08`, while the user kept showing me screenshots of railings still at bridge height. The lesson: never trust origin coordinates as a proxy for visual position.

## Three-keyframe fall pattern

For each object, exactly three keyframes:

| Frame | Position | Interpolation |
|---|---|---|
| 1 | rest | `CONSTANT` |
| break_frame | rest (held) | `BEZIER` `EASE_IN` |
| land_frame | landed | `CONSTANT` |

Plus on every fcurve: `extrapolation = 'CONSTANT'` and remove any `CYCLES` modifier.

```python
def fall(o, rest_z, landed_z, break_frame=30, fall_duration=30):
    if o.animation_data:
        o.animation_data_clear()
    sx, sy = o.location.x, o.location.y
    sr = mathutils.Euler(o.rotation_euler)
    end_f = break_frame + fall_duration

    # frame 1: rest
    o.location = mathutils.Vector((sx, sy, rest_z))
    o.rotation_euler = sr
    o.keyframe_insert('location', frame=1)
    o.keyframe_insert('rotation_euler', frame=1)
    # frame break_frame: still at rest (held by CONSTANT before)
    o.keyframe_insert('location', frame=break_frame)
    o.keyframe_insert('rotation_euler', frame=break_frame)
    # frame end_f: landed
    o.location = mathutils.Vector((sx, sy, landed_z))
    o.keyframe_insert('location', frame=end_f)
    o.keyframe_insert('rotation_euler', frame=end_f)
    # set per-keyframe interpolation + extrapolation
    _lock_curves(o, break_frame, end_f)
```

See `helpers.py` for `_lock_curves` (handles the layered-action API in Blender 5.x).

## ⚠️ Blender 5.x layered actions break every fcurves walker you find online

Pre-5.x: `obj.animation_data.action.fcurves` returned a flat list. **Removed in 5.x.** Now actions have layers → strips → channelbags-per-slot → fcurves.

```python
def fcurves_of(obj):
    ad = obj.animation_data
    if not ad or not ad.action:
        return []
    fcs = []
    for layer in ad.action.layers:
        for strip in layer.strips:
            for slot in ad.action.slots:
                cb = strip.channelbag(slot)
                if cb is None: continue
                fcs.extend(cb.fcurves)
    return fcs
```

Use this in any 5.x code that needs to walk fcurves. Old StackOverflow snippets that do `action.fcurves` will silently break.

## ⚠️ fcurve.extrapolation defaults to LINEAR — set it to CONSTANT

After your last keyframe, Blender extrapolates by default with the slope between the last two keyframes. For a fall that ends at z=0.05 with previous keyframe at z=2.4, that slope continues — your "landed" objects keep accelerating downward past frame 60 into the floor.

```python
fc.extrapolation = 'CONSTANT'  # hold last keyframe value indefinitely
```

Same applies for the start: extrapolation before the first keyframe also runs the slope backward. CONSTANT clamps both ends.

## ⚠️ Disable the rigid body world entirely if you're not using it

Blender bug T67059: stale rigid body cache positions silently override fcurves. If you've ever had rigid bodies in this scene, even after removing them, the cache can still play. Belt-and-braces:

```python
if scene.rigidbody_world:
    bpy.ops.ptcache.free_bake_all()
    scene.rigidbody_world.point_cache.frame_end = 1
    scene.rigidbody_world.enabled = False
```

## Diagnostic workflow — clown pass + labels

When the animation looks wrong and you can't tell which objects are misbehaving, **don't tweak parameters and re-render.** Generate a diagnostic image:

1. **Clown pass.** Replace material slot 0 of every animated object with a unique emission color. Golden-angle hue spacing works well:
   ```python
   for i, o in enumerate(animated_objs):
       h = (i * 0.6180339887) % 1.0
       r, g, b = colorsys.hsv_to_rgb(h, 0.95, 1.0)
       # build emission material with this color, assign to slot 0
   ```
   Save the original material per object first so you can restore.

2. **Label projection.** Project every visible object's bbox center to screen space, draw the name with PIL. Use bbox CENTER, not `matrix_world.translation` — the latter is the origin, which for static corridor objects is often (0,0,0) and projects to one point.
   ```python
   from bpy_extras.object_utils import world_to_camera_view
   bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
   center_world = sum(bb, Vector()) / 8
   cv = world_to_camera_view(scene, scene.camera, center_world)
   if cv.z > 0:
       px, py = cv.x * res_x, (1 - cv.y) * res_y
   ```

3. **Render with the clown materials, overlay labels with PIL.** Now you can see exactly which colored shape corresponds to which object name.

This single diagnostic image identified the rail-origin bug after 4 days of misdiagnosis. **Reach for this earlier than you think you should.**

## Verification before kicking off a 150-frame render

Before `bpy.ops.render.render(animation=True)`, run a programmatic check at sample frames {1, break_frame, mid-fall, land_frame, scene.frame_end}:

```python
def visible_z(o):
    bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    return (min(v.z for v in bb) + max(v.z for v in bb)) / 2

for f in [1, 30, 50, 65, 100, 150]:
    scene.frame_set(f)
    bpy.context.view_layer.update()
    zs = sorted([(visible_z(o), o.name) for o in animated_objs])
    print(f'frame {f}: highest={zs[-1]}, lowest={zs[0]}')
```

Expected for a fall:
- frame 1, break_frame: highest ≈ rest height (e.g., 2.92), lowest ≈ rest_min
- mid-fall: spread across, descending
- land_frame and after: highest ≤ FLOOR + max_height/2 (e.g., 0.28 for posts)

If any frame disagrees with this, fix it before rendering. **150 frames at Cycles 32 samples ≈ 20 minutes wall time. Five sample-frame renders at 16 samples ≈ 90 seconds.** The math is in your favor.

## Padding for GIF loop boundaries

GIFs auto-loop. If your animation is "intact bridge → collapse → settled debris", the loop boundary is settled→intact, which reads as "bridge floats back up". Pad the end:

```bash
ffmpeg -i collapse.mp4 \
  -vf "tpad=stop_mode=clone:stop_duration=2" \
  -c:v libx264 -pix_fmt yuv420p collapse_padded.mp4
```

Two seconds of held-still aftermath makes the loop boundary obvious as "settled state, then restart".

## Reference

- `helpers.py` — `keyframe_fall()`, `bbox_center_z()`, `apply_clown_pass()`, `restore_materials()`, `verify_animation_z()`, `lock_extrapolation()`, fcurve walker for 5.x layered actions
- `references/bridge_collapse.md` — the full bridge-collapse script as built in `elevator/destructible_hallway.blend`

## What this skill does NOT cover

- **Bouncing physics** — for that, set up rigid bodies properly with `collision_shape='CONVEX_HULL'`, `collision_margin=0.0`, and `margin=0.001` on cell fracture. See `physics_collapse.md` (not yet written).
- **Cloth / soft body** — different domain entirely.
- **Motion capture import** — out of scope.
- **Cell fracture itself** — for breaking solid objects into shards, see the original Blender Cell Fracture addon docs. Note: not bundled in 5.x by default; use a manual grid-fracture (4×3×1 cells from a single bounding box) as a workaround.
