"""
Hair-strand-physics helpers.

Per-face inset + N extrudes along cached face normal, with bending
weight gradient and cloth+self-collision setup. See SKILL.md for the
design playbook and the gotchas worth knowing.

Usage:
    from helpers import (
        generate_strands,
        compute_bending_weights,
        setup_cloth_and_collision,
        bake_strand_simulation,
    )

    obj = bpy.data.objects['Hair']  # mesh with N "scalp" faces, modifiers OK
    generate_strands(obj,
        n_extrudes=12,
        short_len=0.012,
        long_base=0.085,
        length_z_min=0.66, length_z_max=1.05,
        right_bias=0.012,
        ramp_start=0.55, ramp_end=1.20,
    )
    compute_bending_weights(obj, power=2.5)
    setup_cloth_and_collision(obj,
        collider_names=['Base', 'Coat', 'Shirt', 'Vest', 'Pants', 'Shoes'])
    bake_strand_simulation(obj, frame_end=120)
"""

import bpy
import bmesh
import math
import mathutils
from mathutils import Vector
from collections import deque


# -----------------------------------------------------------------------------
# Strand generation: per-face inset + N extrudes along cached normal
# -----------------------------------------------------------------------------

def generate_strands(
    obj,
    *,
    inset_thickness=0.01,
    n_extrudes=12,
    short_len=0.012,
    long_base=0.085,
    length_z_min=0.66,
    length_z_max=1.05,
    z_length_min_factor=0.45,
    z_length_max_factor=1.0,
    ramp_start=0.55,
    ramp_end=1.20,
    right_bias=0.0,
    droop_bias=0.0,
    wave_mode='straight',          # 'straight' | 'wavy' | 'curly'
    wave_amplitude=0.025,           # peak per-extrude offset in local units
    wave_frequency=1.8,             # full cycles (wavy) or turns (curly) per strand
    wave_phase_per_strand=True,     # randomize phase per strand for variation
    base_vgroup='HairBase',
):
    """Build strand geometry from the current faces of `obj`.

    Each face becomes one strand: inset → N alternating SHORT/LONG extrudes
    along the cached face normal, with optional cumulative bias per step
    for asymmetric curl.

    Parameters scaled so that values match Blender's edit-mode displayed
    units (local mesh units; multiply by object scale to get world).

    Args:
        inset_thickness: absolute inset around each face (creates strip ring).
        n_extrudes: total extrudes per strand. Pattern alternates SHORT, LONG.
        short_len: SHORT segment length (the hinges).
        long_base: base LONG segment length, scaled by length_factor and ramp.
        length_z_min, length_z_max: face-z range mapped to length_factor.
        z_length_min/max_factor: scale strands at the low/high end of z.
        ramp_start, ramp_end: LONG segment length ramps along strand from
            (start * long_base) near base to (end * long_base) near tip.
        right_bias: extra +X offset added every extrude step (cumulative).
        droop_bias: extra -Z offset added every extrude step (cumulative).
        base_vgroup: name of vertex group to create for pinned base verts.
    """
    if bpy.context.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()

    # Mark every existing vert as "base"; extruded verts will be unmarked
    for v in bm.verts:
        v.tag = True

    original_faces = list(bm.faces)
    constant_bias = Vector((right_bias, 0.0, droop_bias))

    # Stable per-strand phase offset (uses face index) — so each strand's
    # wave starts at a slightly different point and the hair looks varied.
    import random
    rng = random.Random(0xCAFEBABE)
    phase_by_face = {f.index: rng.uniform(0, 2 * math.pi) for f in original_faces}

    for orig_face in original_faces:
        # CRITICAL: cache the original normal before any extrudes (see SKILL.md)
        n = orig_face.normal.normalized().copy()
        fc = orig_face.calc_center_median()

        # Build two basis vectors u, v perpendicular to n for wavy/curly biases.
        # u is "horizontal-ish" (cross with world Z), v completes the basis.
        world_z = Vector((0, 0, 1))
        if abs(n.dot(world_z)) > 0.95:
            ref = Vector((1, 0, 0))   # fallback when n is near vertical
        else:
            ref = world_z
        u = n.cross(ref).normalized()
        v = n.cross(u).normalized()

        phase = phase_by_face[orig_face.index] if wave_phase_per_strand else 0.0

        # length factor from face Z position
        if length_z_max > length_z_min:
            z_norm = max(0.0, min(1.0,
                (fc.z - length_z_min) / (length_z_max - length_z_min)))
        else:
            z_norm = 1.0
        length_factor = (
            z_length_min_factor
            + (z_length_max_factor - z_length_min_factor) * z_norm
        )

        # Inset (creates strip faces around the smaller inner rectangle)
        inset_result = bmesh.ops.inset_individual(
            bm, faces=[orig_face],
            thickness=inset_thickness, depth=0.0,
            use_even_offset=True,
            use_relative_offset=False,
            use_interpolate=False,
        )
        # Strip-face verts and the (now smaller) original face verts are base
        for f in inset_result['faces']:
            for v in f.verts:
                v.tag = True
        for v in orig_face.verts:
            v.tag = True

        current_top = orig_face

        for i in range(n_extrudes):
            if i % 2 == 0:
                step = short_len
            else:
                t_seg = i / max(n_extrudes - 1, 1)
                long_factor = ramp_start + (ramp_end - ramp_start) * t_seg
                step = long_base * length_factor * long_factor

            # Compute the per-extrude bias offset (in addition to constant_bias)
            # so the strand has a built-in wavy or curly shape.
            t = (i + 1) / max(n_extrudes, 1)  # 0 < t <= 1 along strand
            if wave_mode == 'wavy':
                # Sinusoidal back-and-forth in the u direction (perpendicular to normal)
                offset = math.sin(2 * math.pi * wave_frequency * t + phase) * wave_amplitude
                wave_bias = u * offset
            elif wave_mode == 'curly':
                # Spiral around the strand axis (n direction)
                angle = 2 * math.pi * wave_frequency * t + phase
                wave_bias = (u * math.cos(angle) + v * math.sin(angle)) * wave_amplitude
            else:
                wave_bias = Vector((0, 0, 0))

            ext = bmesh.ops.extrude_face_region(bm, geom=[current_top])
            ext_verts = [g for g in ext['geom']
                         if isinstance(g, bmesh.types.BMVert)]
            ext_faces = [g for g in ext['geom']
                         if isinstance(g, bmesh.types.BMFace)]

            for v in ext_verts:
                v.co += n * step + constant_bias + wave_bias
                v.tag = False  # extruded verts are floppy

            current_top = ext_faces[0]

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Read tags off before bm.to_mesh invalidates the reference
    base_indices = [v.index for v in bm.verts if v.tag]
    bm.to_mesh(me)
    bm.free()
    me.update()

    # Replace base vertex group
    if base_vgroup in obj.vertex_groups:
        obj.vertex_groups.remove(obj.vertex_groups[base_vgroup])
    vg = obj.vertex_groups.new(name=base_vgroup)
    vg.add(base_indices, 1.0, 'REPLACE')

    return {
        'polys': len(me.polygons),
        'verts': len(me.vertices),
        'base_indices': base_indices,
    }


# -----------------------------------------------------------------------------
# Bending weight gradient via BFS distance from base
# -----------------------------------------------------------------------------

def compute_bending_weights(
    obj,
    *,
    base_vgroup='HairBase',
    bend_vgroup='HairBend',
    power=2.5,
    min_weight=0.02,
):
    """Build a vertex group with per-vert bending weights using a power-curve
    falloff from base (1.0) to tip (min_weight).

    weight[v] = max(min_weight, (1 - distance(v, base)/max_dist) ** power)

    Distance is graph distance in edges from the nearest base vert.
    """
    me = obj.data

    # Read base indices from existing vertex group
    base_vg = obj.vertex_groups.get(base_vgroup)
    if base_vg is None:
        raise ValueError(f"No vertex group named {base_vgroup}")
    base_set = set()
    for v in me.vertices:
        for g in v.groups:
            if g.group == base_vg.index and g.weight > 0.5:
                base_set.add(v.index)
                break

    # Build adjacency
    adj = {i: set() for i in range(len(me.vertices))}
    for e in me.edges:
        a, b = e.vertices
        adj[a].add(b)
        adj[b].add(a)

    # BFS from all base verts simultaneously
    dist = {i: -1 for i in range(len(me.vertices))}
    q = deque()
    for i in base_set:
        dist[i] = 0
        q.append(i)
    while q:
        cur = q.popleft()
        for nb in adj[cur]:
            if dist[nb] == -1:
                dist[nb] = dist[cur] + 1
                q.append(nb)

    max_dist = max((d for d in dist.values() if d >= 0), default=1)

    def weight_at(d):
        if d <= 0:
            return 1.0
        if d < 0:
            return 0.5  # disconnected — give it moderate weight
        t = d / max_dist
        return max(min_weight, (1.0 - t) ** power)

    # Replace bending vertex group
    if bend_vgroup in obj.vertex_groups:
        obj.vertex_groups.remove(obj.vertex_groups[bend_vgroup])
    bvg = obj.vertex_groups.new(name=bend_vgroup)
    for v in me.vertices:
        bvg.add([v.index], weight_at(dist[v.index]), 'REPLACE')

    return {
        'max_dist': max_dist,
        'curve': {d: round(weight_at(d), 3) for d in range(max_dist + 1)},
    }


# -----------------------------------------------------------------------------
# Cloth modifier + collision setup
# -----------------------------------------------------------------------------

def setup_cloth_and_collision(
    obj,
    *,
    base_vgroup='HairBase',
    bend_vgroup='HairBend',
    pin_stiffness=100.0,
    mass=0.5,
    tension_stiffness=3.0,
    compression_stiffness=3.0,
    shear_stiffness=1.0,
    bending_stiffness=1.5,
    bending_stiffness_min=0.05,
    tension_damping=1.0,
    bending_damping=0.3,
    air_damping=0.5,
    quality=15,
    self_collision=True,
    self_distance_min=0.010,
    external_distance_min=0.015,
    collision_quality=10,
    friction=5.0,
    collider_names=(),
    collider_thickness_outer=0.02,
    collider_thickness_inner=0.005,
    collider_damping=0.5,
):
    """Configure Cloth on obj + Collision modifiers on the named neighbors.

    `bend_vgroup` is assigned to vertex_group_bending so per-vert weights drive
    per-edge bending stiffness (interpolated from bending_stiffness down to
    bending_stiffness_min based on the group weight).
    """
    # Make sure cloth is first in stack
    cloth = next((m for m in obj.modifiers if m.type == 'CLOTH'), None)
    if cloth is None:
        cloth = obj.modifiers.new('Cloth', 'CLOTH')

    # Move cloth to top of stack (above any Mirror/Subsurf/Solidify)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    while obj.modifiers.find(cloth.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=cloth.name)

    cs = cloth.settings
    cs.vertex_group_mass = base_vgroup
    cs.vertex_group_bending = bend_vgroup
    cs.pin_stiffness = pin_stiffness
    cs.mass = mass
    cs.tension_stiffness = tension_stiffness
    cs.compression_stiffness = compression_stiffness
    cs.shear_stiffness = shear_stiffness
    cs.bending_stiffness = bending_stiffness
    try:
        cs.bending_stiffness_max = bending_stiffness_min
    except Exception:
        pass  # property may not exist in some Blender builds
    cs.tension_damping = tension_damping
    cs.bending_damping = bending_damping
    cs.air_damping = air_damping
    cs.quality = quality

    col = cloth.collision_settings
    col.use_collision = True
    col.collision_quality = collision_quality
    col.distance_min = external_distance_min
    col.use_self_collision = self_collision
    col.self_distance_min = self_distance_min
    col.self_friction = friction
    col.friction = friction
    col.damping = 0.3

    # Make sure obj is NOT itself a collider (cloth + collision conflict)
    for m in list(obj.modifiers):
        if m.type == 'COLLISION':
            obj.modifiers.remove(m)

    # Add Collision modifiers to neighbors
    added = []
    for name in collider_names:
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        # Skip if already cloth (can't be both)
        if any(m.type == 'CLOTH' for m in o.modifiers):
            continue
        if not any(m.type == 'COLLISION' for m in o.modifiers):
            o.modifiers.new('Collision', 'COLLISION')
            added.append(name)
        # Tune collision properties on the field-source (not the modifier)
        if o.collision:
            o.collision.thickness_outer = collider_thickness_outer
            o.collision.thickness_inner = collider_thickness_inner
            o.collision.damping = collider_damping

    return {'colliders_added': added}


# -----------------------------------------------------------------------------
# Bake
# -----------------------------------------------------------------------------

def bake_strand_simulation(obj, *, frame_start=1, frame_end=120):
    """Bake the cloth point cache for `obj`. Uses bake_all to capture any
    other cloths in the scene at the same time."""
    cloth = next((m for m in obj.modifiers if m.type == 'CLOTH'), None)
    if cloth is None:
        raise ValueError("No cloth modifier on object")

    try:
        bpy.ops.ptcache.free_bake_all()
    except Exception:
        pass

    cloth.point_cache.frame_start = frame_start
    cloth.point_cache.frame_end = frame_end

    scene = bpy.context.scene
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(scene=scene, window=window,
                                    screen=window.screen):
        bpy.ops.ptcache.bake_all(bake=True)

    return {
        'baked': cloth.point_cache.is_baked,
        'frame_start': frame_start,
        'frame_end': frame_end,
    }


# -----------------------------------------------------------------------------
# Convenience: full pipeline in one call
# -----------------------------------------------------------------------------

def build_hair(
    obj,
    *,
    n_extrudes=12,
    short_len=0.012,
    long_base=0.085,
    length_z_min=0.66,
    length_z_max=1.05,
    right_bias=0.012,
    wave_mode='straight',
    wave_amplitude=0.025,
    wave_frequency=1.8,
    collider_names=('Base', 'Coat', 'Shirt', 'Vest', 'Pants', 'Shoes'),
    frame_end=120,
):
    """Full pipeline: generate strands, compute bending weights, setup cloth
    and collision, bake. Returns a dict with summary stats.

    `wave_mode`:
        'straight' (default) — strands extrude in a straight line along normal.
        'wavy'   — sinusoidal sway perpendicular to the strand axis. Good
                   for textured / wavy hair. Try amplitude 0.02-0.04,
                   frequency 1.5-2.5 cycles per strand.
        'curly'  — corkscrew spiral around the strand axis. Good for
                   coily / curly hair. Try amplitude 0.02-0.035,
                   frequency 2.0-4.0 turns per strand.
    """
    gen = generate_strands(obj,
        n_extrudes=n_extrudes,
        short_len=short_len,
        long_base=long_base,
        length_z_min=length_z_min,
        length_z_max=length_z_max,
        right_bias=right_bias,
        wave_mode=wave_mode,
        wave_amplitude=wave_amplitude,
        wave_frequency=wave_frequency,
    )
    bend = compute_bending_weights(obj)
    setup_cloth_and_collision(obj, collider_names=collider_names)
    bake = bake_strand_simulation(obj, frame_end=frame_end)
    return {
        'polys': gen['polys'],
        'verts': gen['verts'],
        'base_pinned': len(gen['base_indices']),
        'max_distance': bend['max_dist'],
        'baked': bake['baked'],
    }
