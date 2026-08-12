"""
Procedural animation helpers for Blender 5.x.

Pattern: pure-keyframe fall/move/scatter for pre-existing geometry,
no rigid-body sim, with the right gotchas handled.

Usage:
    from helpers import (
        prepare_for_animation,
        keyframe_fall,
        verify_animation_z,
        apply_clown_pass,
        restore_materials,
        label_projection_image,
    )

    objs = [o for o in bpy.data.objects if o.name.startswith('Walkway_')]
    prepare_for_animation(objs)        # origin_set on each + disable rb world
    for o in objs:
        keyframe_fall(o, rest_z=2.4, landed_z=0.06,
                      break_frame=30, fall_duration=30)
    verify_animation_z(objs, frames=[1, 30, 50, 65, 100, 150])
"""

import bpy
import mathutils
import math
import random
import colorsys
import json
import os


# -----------------------------------------------------------------------------
# Origin / mesh setup
# -----------------------------------------------------------------------------

def origin_to_geometry(obj):
    """Move obj's origin to its bbox center. Reliable per-object pattern."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')


def disable_rigid_body_world():
    """Free any baked rigid-body cache and disable the world. Prevents the
    documented bug where stale sim positions silently override fcurves."""
    scene = bpy.context.scene
    if scene.rigidbody_world is None:
        return
    try:
        bpy.ops.ptcache.free_bake_all()
    except Exception:
        pass
    scene.rigidbody_world.point_cache.frame_end = 1
    scene.rigidbody_world.enabled = False


def prepare_for_animation(objs):
    """Standard pre-animation cleanup:
    - clear any stale animation
    - origin_set so origin == mesh center (so location keyframes move the mesh)
    - disable rigid body world (avoid stale-cache footgun)
    """
    for o in objs:
        if o.animation_data:
            o.animation_data_clear()
    for o in objs:
        origin_to_geometry(o)
    disable_rigid_body_world()


# -----------------------------------------------------------------------------
# Bbox-center helpers (the right way to test "where is the mesh visually")
# -----------------------------------------------------------------------------

def bbox_center_z(obj):
    bb = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    zs = [v.z for v in bb]
    return (min(zs) + max(zs)) / 2.0


def bbox_world(obj):
    return [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]


def height(obj):
    bb_local = [mathutils.Vector(c) for c in obj.bound_box]
    return max(v.z for v in bb_local) - min(v.z for v in bb_local)


# -----------------------------------------------------------------------------
# fcurve walker — required because Blender 5.x layered-action API removed
# action.fcurves
# -----------------------------------------------------------------------------

def fcurves_of(obj):
    ad = obj.animation_data
    if not ad or not ad.action:
        return []
    fcs = []
    for layer in ad.action.layers:
        for strip in layer.strips:
            for slot in ad.action.slots:
                cb = strip.channelbag(slot)
                if cb is None:
                    continue
                fcs.extend(cb.fcurves)
    return fcs


def lock_curve_endpoints(obj):
    """For each fcurve: extrapolation=CONSTANT, kill modifiers, set per-key
    interpolation: CONSTANT before fall, BEZIER EASE_IN during fall, CONSTANT
    after. Assumes 3 keyframes per axis."""
    for fc in fcurves_of(obj):
        fc.extrapolation = 'CONSTANT'
        for m in list(fc.modifiers):
            fc.modifiers.remove(m)
        kps = sorted(fc.keyframe_points, key=lambda k: k.co.x)
        if len(kps) >= 1:
            kps[0].interpolation = 'CONSTANT'
        if len(kps) >= 2:
            kps[1].interpolation = 'BEZIER'
            kps[1].easing = 'EASE_IN'
        if len(kps) >= 3:
            kps[2].interpolation = 'CONSTANT'
        fc.update()


# -----------------------------------------------------------------------------
# The fall keyframe pattern
# -----------------------------------------------------------------------------

def keyframe_fall(obj, rest_z, landed_z,
                  break_frame=30, fall_duration=30,
                  drift_xy=0.0, tilt_deg=0.0,
                  rng=None):
    """3-keyframe fall: held at rest_z, then ease into landed_z.

    Assumes obj origin is at mesh center (call prepare_for_animation first).
    Optionally jitter the xy landing position and add a small tumble.
    """
    if obj.animation_data:
        obj.animation_data_clear()
    if rng is None:
        rng = random
    sx, sy = obj.location.x, obj.location.y
    sr = mathutils.Euler(obj.rotation_euler)

    end_f = break_frame + fall_duration
    dx = rng.uniform(-drift_xy, drift_xy) if drift_xy else 0.0
    dy = rng.uniform(-drift_xy, drift_xy) if drift_xy else 0.0
    tx = math.radians(rng.uniform(-tilt_deg, tilt_deg)) if tilt_deg else 0.0
    ty = math.radians(rng.uniform(-tilt_deg, tilt_deg)) if tilt_deg else 0.0

    # Frame 1: rest
    obj.location = mathutils.Vector((sx, sy, rest_z))
    obj.rotation_euler = sr
    obj.keyframe_insert('location', frame=1)
    obj.keyframe_insert('rotation_euler', frame=1)
    # Frame break_frame: still at rest (held flat by previous CONSTANT)
    obj.keyframe_insert('location', frame=break_frame)
    obj.keyframe_insert('rotation_euler', frame=break_frame)
    # Frame end_f: landed
    obj.location = mathutils.Vector((sx + dx, sy + dy, landed_z))
    obj.rotation_euler = mathutils.Euler((sr.x + tx, sr.y + ty, sr.z))
    obj.keyframe_insert('location', frame=end_f)
    obj.keyframe_insert('rotation_euler', frame=end_f)

    lock_curve_endpoints(obj)


# -----------------------------------------------------------------------------
# Verification — run BEFORE the 150-frame production render
# -----------------------------------------------------------------------------

def verify_animation_z(objs, frames, expect=None):
    """Sample mesh visible-Z at each frame. Print a report; return dict.

    expect is an optional dict {frame: (z_min_expected, z_max_expected)} —
    if any object falls outside the expected range, raises AssertionError.
    """
    scene = bpy.context.scene
    report = {}
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        rows = sorted([(round(bbox_center_z(o), 3), o.name) for o in objs])
        report[f] = {'highest': rows[-1], 'lowest': rows[0],
                     'top3': rows[-3:], 'bot3': rows[:3]}
        if expect and f in expect:
            zlo, zhi = expect[f]
            for z, n in rows:
                assert zlo - 0.05 <= z <= zhi + 0.05, \
                    f'frame {f}: {n} at z={z}, expected [{zlo}, {zhi}]'
    return report


# -----------------------------------------------------------------------------
# Clown pass — diagnostic when the render looks wrong
# -----------------------------------------------------------------------------

def apply_clown_pass(objs, save_to=None):
    """Assign each object a unique bright emission material in slot 0.

    Saves the original slot 0 material name per object to a json file at
    save_to (use this to restore_materials later). Returns dict
    {obj_name: (r, g, b)}.
    """
    saved = {}
    palette = {}
    for i, o in enumerate(objs):
        if not o.data or not hasattr(o.data, 'materials'):
            continue
        if len(o.data.materials) > 0 and o.data.materials[0]:
            saved[o.name] = o.data.materials[0].name
        else:
            saved[o.name] = None

        h = (i * 0.6180339887) % 1.0
        r, g, b = colorsys.hsv_to_rgb(h, 0.95, 1.0)
        palette[o.name] = [r, g, b]

        mat = bpy.data.materials.new(name=f'CLOWN_{o.name}')
        mat.use_nodes = True
        nt = mat.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Strength'].default_value = 5.0
        em.inputs['Color'].default_value = (r, g, b, 1.0)
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])

        if len(o.data.materials) == 0:
            o.data.materials.append(mat)
        else:
            o.data.materials[0] = mat

    if save_to:
        with open(save_to, 'w') as f:
            json.dump({'saved': saved, 'palette': palette}, f)
    return palette


def restore_materials(objs, save_path):
    """Reverse apply_clown_pass: restore slot 0 from save_path json,
    delete CLOWN_ materials."""
    with open(save_path) as f:
        data = json.load(f)
    saved = data['saved']
    for o in objs:
        orig = saved.get(o.name)
        if orig and orig in bpy.data.materials and len(o.data.materials) > 0:
            o.data.materials[0] = bpy.data.materials[orig]
    for m in list(bpy.data.materials):
        if m.name.startswith('CLOWN_'):
            bpy.data.materials.remove(m, do_unlink=True)


# -----------------------------------------------------------------------------
# Label projection — overlay object names on a rendered PNG
# -----------------------------------------------------------------------------

def project_objects_to_screen(objs, frame, res_x, res_y):
    """Return list of {'name', 'cx', 'cy', 'world_z', 'cam_dist',
    'on_screen'} for each object. Uses bbox CENTER, not matrix_world
    translation — origins for static scene objects are often (0,0,0)."""
    from bpy_extras.object_utils import world_to_camera_view
    scene = bpy.context.scene
    cam = scene.camera
    scene.frame_set(frame)
    bpy.context.view_layer.update()

    out = []
    for o in objs:
        if o.type != 'MESH':
            continue
        bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
        center = sum(bb, mathutils.Vector()) / 8.0
        cv = world_to_camera_view(scene, cam, center)
        if cv.z <= 0:
            continue
        px = cv.x * res_x
        py = (1.0 - cv.y) * res_y
        on_screen = (0 <= px <= res_x) and (0 <= py <= res_y)
        out.append({
            'name': o.name, 'cx': px, 'cy': py,
            'world_z': center.z, 'cam_dist': cv.z,
            'on_screen': on_screen,
        })
    return sorted(out, key=lambda p: p['cam_dist'])


def label_projection_image(rendered_png, projections, output_png,
                           highlight_names=None):
    """Overlay object names on rendered_png. Names in highlight_names are
    drawn in red; others in white. Skips overlapping labels."""
    from PIL import Image, ImageDraw, ImageFont
    img = Image.open(rendered_png).convert('RGB')
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(
            '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 11)
    except Exception:
        font = ImageFont.load_default()

    placed = []
    for p in projections:
        if not p.get('on_screen'):
            continue
        cx, cy = p['cx'], p['cy']
        if any(abs(cx - x) < 25 and abs(cy - y) < 14 for x, y in placed):
            continue
        placed.append((cx, cy))
        is_hl = highlight_names and p['name'] in highlight_names
        fill = (255, 80, 80) if is_hl else (220, 220, 220)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                draw.text((cx + dx, cy + dy), p['name'], font=font, fill=(0, 0, 0))
        draw.text((cx, cy), p['name'], font=font, fill=fill)

    img.save(output_png)


# -----------------------------------------------------------------------------
# Convenience: make a settle-on-floor animation for a list of objects
# -----------------------------------------------------------------------------

def collapse_to_floor(objs, *, floor_z=0.0, break_frame=30, jitter=3,
                     fall_duration=30, drift_xy=0.10, tilt_deg=18,
                     subgroups=None, seed=42):
    """High-level: drop a list of objects onto the floor.

    Each object's rest position = current bbox center.
    Each object's landed position = floor_z + height/2 (mesh sits flush).
    Optionally split objs into subgroups with different break_frames
    (e.g., bridge cells fall, then rails fall N frames later).

    subgroups: list of (predicate, break_offset, rail_jitter_extra) tuples.
        Default: single group, all break together at break_frame.
    """
    rng = random.Random(seed)
    prepare_for_animation(objs)

    if subgroups is None:
        subgroups = [(lambda o: True, 0, 0)]

    for o in objs:
        for predicate, break_offset, extra_jitter in subgroups:
            if predicate(o):
                bf = (break_frame + break_offset
                      + rng.randint(0, jitter + extra_jitter))
                break
        else:
            bf = break_frame + rng.randint(0, jitter)

        rest_z = bbox_center_z(o)  # current world position
        h = height(o)
        landed_z = floor_z + h / 2.0

        keyframe_fall(o, rest_z=rest_z, landed_z=landed_z,
                      break_frame=bf, fall_duration=fall_duration,
                      drift_xy=drift_xy, tilt_deg=tilt_deg, rng=rng)
