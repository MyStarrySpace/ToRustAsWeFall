"""
stylized-plant-builder helpers
================================

Reusable functions for building stylized low-poly potted plants in Blender.
Pair with SKILL.md — the footgun docs there are required reading.

Typical use:

    from helpers import (
        get_soil_top_z, get_pot_rim_metrics, fix_pot_materials,
        dump_and_verify_textures,  # call BEFORE final render — Footgun #14, #15
        poisson_disk_in_circle,
        make_vine_tube, sample_bezier, vine_clips_pot_wall,
        place_leaves_phyllotaxy, place_leaves_along_vine, scatter_flowers,
        make_heart_leaf_mesh, make_oval_leaf_mesh, make_leaf_pair_mesh,
        build_heart_leaf_pool,
        make_5petal_flower_mesh, make_bud_mesh,
    )

All functions are stateless wrt Blender selection state — they don't change
the active object, mode, or selection.
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix


# =============================================================================
# PERIS-SIM CANONICAL PALETTE — see Footgun #14
# =============================================================================
# Extracted from existing peris-sim/gltf-exports/*Tex.png. Use these in every
# new plant texture so the garden scene reads as a coherent set.

PERIS_SIM_PALETTE = {
    'VERY_DARK':   (0.02, 0.10, 0.04, 1.0),   # midrib / deep shadow
    'DARK':        (0.06, 0.20, 0.08, 1.0),   # leaf edge
    'MID_DARK':    (0.10, 0.32, 0.14, 1.0),   # body shadow
    'MID':         (0.20, 0.45, 0.18, 1.0),   # body
    'LIGHT':       (0.35, 0.60, 0.25, 1.0),   # highlight
    'VERY_LIGHT':  (0.55, 0.72, 0.35, 1.0),   # bright highlight
    'STEM_BROWN':  (0.55, 0.32, 0.20, 1.0),
    'CREAM':       (0.96, 0.94, 0.86, 1.0),   # flower / spathe white
    'YELLOW':      (0.96, 0.86, 0.45, 1.0),   # flower center
    'VARIEGATION': (0.78, 0.78, 0.30, 1.0),   # golden-pothos variegation
}


# =============================================================================
# POT / SOIL MEASUREMENT — see Footgun #1
# =============================================================================

def get_soil_top_z(soil_obj):
    """Return world-space Z of the topmost soil vertex.

    NEVER use soil.location.z — in these scenes, mesh verts are baked at world
    height while origin stays at (0,0,0).
    """
    return max((soil_obj.matrix_world @ v.co).z for v in soil_obj.data.vertices)


def get_pot_rim_metrics(pot_obj):
    """Return (rim_z, rim_inner_r, rim_outer_r) measured from mesh verts.

    rim_inner_r and rim_outer_r are the radii at the top of the pot (the
    inner cavity and outer wall). Returns conservative bounds.
    """
    verts = [(pot_obj.matrix_world @ v.co) for v in pot_obj.data.vertices]
    rim_z = max(v.z for v in verts)
    # Sample verts within 5cm of rim top
    top_band = [v for v in verts if v.z > rim_z - 0.05]
    rs = [(v.x**2 + v.y**2)**0.5 for v in top_band]
    return rim_z, min(rs), max(rs)


def dump_and_verify_textures(image_names, out_dir, min_leaf_res=64):
    """Save every named texture to disk and print resolution/orientation
    warnings. Required before final render — see Footgun #14, #15.

    For each image, this function:
      1. Saves to `{out_dir}/tex_audit_{name}.png` so you can OPEN and look at it.
      2. Warns if min(W,H) < min_leaf_res for any image with 'Leaf' in name.
      3. Prints aspect ratio so you can check it matches your UV layout
         (horizontal-leaf UVs need wide texture, vertical-leaf UVs need tall).

    You MUST visually open each saved tex_audit_*.png and confirm:
      - Resolution adequate for the rendered leaf's screen size
      - Drawn shape oriented to match the mesh UV layout (long axis aligned
        with whichever UV axis represents length in your mesh)
      - No empty alpha where you expect content
    """
    import os
    for name in image_names:
        img = bpy.data.images.get(name)
        if img is None:
            print(f"  MISSING: {name}")
            continue
        path = os.path.join(out_dir, f'tex_audit_{name}.png')
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        W, H = img.size
        aspect = W / H if H > 0 else 0
        orient = "wide" if aspect > 1.3 else "tall" if aspect < 0.77 else "square"
        warn = ""
        if 'Leaf' in name and min(W, H) < min_leaf_res:
            warn = f"  ⚠ LOW-RES (min < {min_leaf_res})"
        elif 'Leaf' not in name and min(W, H) < 12:
            warn = f"  ⚠ tiny (might be fine for noise/pattern)"
        print(f"  {name}: {W}×{H} [{orient}, aspect={aspect:.2f}] → {path}{warn}")


def fix_pot_materials(pot_obj, base_color=(0.92, 0.92, 0.90, 1.0),
                      roughness=0.4, sss_weight=0.15):
    """Normalize pot material to clean opaque white.

    Fixes Footgun #8: inherited HASHED-blend materials with low-alpha textures
    that render mostly transparent.

    NOTE: Plants no longer include saucers (removed 2026-06-05 — they weren't
    used in the game scene). If you ever pass a saucer object, just fix it
    separately with the same logic.
    """
    for obj in [pot_obj]:
        if obj is None: continue
        for mat in obj.data.materials:
            if mat is None: continue
            mat.blend_method = 'OPAQUE'
            if not mat.use_nodes:
                mat.use_nodes = True
            nt = mat.node_tree
            bsdf = next((n for n in nt.nodes if n.bl_idname == 'ShaderNodeBsdfPrincipled'), None)
            if bsdf is None:
                continue
            bsdf.inputs['Base Color'].default_value = base_color
            bsdf.inputs['Roughness'].default_value = roughness
            if 'Subsurface Weight' in bsdf.inputs:
                bsdf.inputs['Subsurface Weight'].default_value = sss_weight
                bsdf.inputs['Subsurface Radius'].default_value = (1.0, 0.6, 0.4)
                if 'Subsurface Scale' in bsdf.inputs:
                    bsdf.inputs['Subsurface Scale'].default_value = 0.06
            # Remove texture->BaseColor link (texture often broken)
            for link in list(nt.links):
                if link.to_node == bsdf and link.to_socket.name == 'Base Color':
                    if link.from_node.bl_idname == 'ShaderNodeTexImage':
                        nt.links.remove(link)


# =============================================================================
# ORIGIN SAMPLING — see Footgun #2
# =============================================================================

def poisson_disk_in_circle(n, radius_max, min_sep, max_tries=2000):
    """Sample n points in a 2D disk with at least min_sep separation.

    Distributes stem origins across the entire soil surface instead of
    clumping at the center. Without this, stems all converge in a tight
    bunch — Footgun #2.

    Use min_sep ≈ 2× stem radius_max for non-overlapping origins.
    """
    points = []
    tries = 0
    while len(points) < n and tries < max_tries:
        tries += 1
        # Uniform-in-disk: r = R·sqrt(u), not r = R·u
        r = math.sqrt(random.random()) * radius_max
        a = random.uniform(0, 2 * math.pi)
        p = (r * math.cos(a), r * math.sin(a))
        if all((p[0]-q[0])**2 + (p[1]-q[1])**2 >= min_sep**2 for q in points):
            points.append(p)
    return points


# =============================================================================
# BEZIER SAMPLING
# =============================================================================

def sample_bezier(P0, P1, P2, P3, n):
    """Sample cubic bezier at n+1 evenly-spaced t values.

    Returns list of (position, tangent_unit, t) tuples.

    NOTE: For cascading vines, prefer `sample_quad_bezier` — cubic curves
    have two middle control points which sag in between, producing the
    "droopy noodle" look. See Footgun #13.
    """
    out = []
    for i in range(n + 1):
        t = i / n
        p = ((1-t)**3 * P0
             + 3*(1-t)**2*t * P1
             + 3*(1-t)*t**2 * P2
             + t**3 * P3)
        tg = (3*(1-t)**2 * (P1 - P0)
              + 6*(1-t)*t * (P2 - P1)
              + 3*t**2 * (P3 - P2))
        if tg.length < 1e-5:
            tg = Vector((0, 0, 1))
        tg.normalize()
        out.append((p, tg, t))
    return out


def cascading_vine_control_points(P0, radial_unit, r0, soil_top_z, rim_z,
                                    rim_outer, floor_z, soil_r, length,
                                    jitter_scale=1.0):
    """Compute cubic-bezier control points for a vine on the smooth-cascade
    gradient. Use for ALL stems (center and edge) — the cubic shape degenerates
    naturally at low r_frac into an organic upward bend, and at high r_frac
    becomes the full cascade.

    See SKILL.md "Cascading-vine pattern" — uses smoothstep(r_frac) easing so
    there's no visible discontinuity between center and edge regimes
    (Footgun #36).

    P0 is the soil-level origin. radial_unit points from plant center toward
    P0 in the XY plane. r0 is distance from plant center.

    Returns (P1, P2, P3).
    """
    j = jitter_scale
    r_frac = min(1.0, r0 / soil_r)
    cascade = r_frac * r_frac * (3 - 2 * r_frac)  # smoothstep

    # Lateral bend direction: random for center (organic curl), outward for edge
    bend_random = random.uniform(0, 2 * math.pi)
    random_dir = Vector((math.cos(bend_random), math.sin(bend_random), 0))
    bend_unit = (random_dir * (1 - cascade) + radial_unit * cascade).normalized()

    # P1: rise control with lateral bend
    rise_z = soil_top_z + length * (0.30 + cascade * 0.20)
    P1 = Vector((P0.x + bend_unit.x * 0.20 * length,
                 P0.y + bend_unit.y * 0.20 * length,
                 rise_z))

    # P2: crest — interpolates from above-origin to far-outside-rim
    crest_r = (r0 + length * 0.20) * (1 - cascade) + (rim_outer + 0.30 + random.uniform(0.0, 0.15) * j) * cascade
    crest_z = (soil_top_z + length * 0.85) * (1 - cascade) + (rim_z + 0.05 + random.uniform(-0.05, 0.10) * j) * cascade
    P2 = Vector((bend_unit.x * crest_r + random.uniform(-0.03, 0.03) * j,
                 bend_unit.y * crest_r + random.uniform(-0.03, 0.03) * j,
                 crest_z))

    # P3: tip — interpolates from high tip to floor drape
    tip_r_center = r0 + length * 0.35
    tip_r_edge = max(rim_outer + 0.10, crest_r - 0.05)
    tip_r = tip_r_center * (1 - cascade) + tip_r_edge * cascade
    tip_z_center = soil_top_z + length * 1.0 + random.uniform(-0.10, 0.0) * j
    tip_z_edge = max(floor_z + 0.05,
                     rim_z - (rim_z - floor_z - 0.05) * cascade)
    cascade_sharp = cascade ** 1.2  # sharper transition to floor
    tip_z = tip_z_center * (1 - cascade_sharp) + tip_z_edge * cascade_sharp
    P3 = Vector((bend_unit.x * tip_r + random.uniform(-0.04, 0.04) * j,
                 bend_unit.y * tip_r + random.uniform(-0.04, 0.04) * j,
                 tip_z))
    return P1, P2, P3


def sample_quad_bezier(P0, P1, P2, n):
    """Sample quadratic bezier (3 control points) — use for STIFF cascading vines.

    The single middle control point P1 defines the arch apex; no mid-curve
    sag possible. Pothos/spider-plant/boston-fern all use quadratic for this
    reason (Footgun #13).

    Returns list of (position, tangent_unit, t) tuples.
    """
    out = []
    for i in range(n + 1):
        t = i / n
        p = (1-t)**2 * P0 + 2*(1-t)*t * P1 + t**2 * P2
        tg = 2*(1-t)*(P1-P0) + 2*t*(P2-P1)
        if tg.length < 1e-5:
            tg = Vector((0, 0, -1))
        tg.normalize()
        out.append((p, tg, t))
    return out


def make_vine_tube_quad(name, P0, P1, P2, segments=24, radius=0.030,
                         ring_verts=7, taper=0.35, mat=None,
                         link_collection=None):
    """Tube swept along QUADRATIC bezier (3 control points).

    Use for cascading vines (pothos, ivy). The quadratic arch is stiffer than
    cubic and doesn't sag in the middle. Default radius 0.030 (vs 0.012 for
    upright stems) — thin vines read as wet noodles even with right curve
    shape (Footgun #13b).
    """
    bm = bmesh.new()
    rings = []
    prev_side = None
    for i in range(segments + 1):
        t = i / segments
        p = (1-t)**2*P0 + 2*(1-t)*t*P1 + t**2*P2
        tg = 2*(1-t)*(P1-P0) + 2*t*(P2-P1)
        if tg.length < 1e-5:
            tg = Vector((0, 0, -1))
        tg.normalize()
        if prev_side is None:
            side = tg.cross(Vector((0, 0, 1)))
            if side.length < 1e-3:
                side = Vector((1, 0, 0))
            side.normalize()
        else:
            side = prev_side - tg * prev_side.dot(tg)
            if side.length < 1e-5:
                side = Vector((1, 0, 0))
            side.normalize()
        up = tg.cross(side).normalized()
        prev_side = side
        r = radius * (1.0 - taper * (i / segments))
        ring = []
        for j in range(ring_verts):
            a = j * 2 * math.pi / ring_verts
            offset = side * (r * math.cos(a)) + up * (r * math.sin(a))
            ring.append(bm.verts.new(p + offset))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for i in range(segments):
        r0, r1 = rings[i], rings[i+1]
        for j in range(ring_verts):
            jn = (j+1) % ring_verts
            bm.faces.new([r0[j], r0[jn], r1[jn], r1[j]])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    if mat:
        obj.data.materials.append(mat)
    coll = link_collection or bpy.context.scene.collection
    coll.objects.link(obj)
    return obj


# =============================================================================
# CLIP DETECTION — see Footgun #5
# =============================================================================

def vine_clips_pot_wall(samples, rim_z, rim_inner, rim_outer,
                         depth_threshold=0.10, band_buffer=0.04):
    """True if the vine geometry would clip through the visible pot wall.

    Only checks DEEP intrusions (z < rim_z - depth_threshold). Brief crossings
    right at the rim are natural top-emergence, not visible clipping.

    The pot is hollow; vines inside the cavity (r < rim_inner) at z < rim_z
    are HIDDEN by the pot interior — fine. Only the wall material band
    [rim_inner, rim_outer] at depth is forbidden.
    """
    for p, tg, t in samples:
        r = (p.x**2 + p.y**2)**0.5
        if (p.z < rim_z - depth_threshold
                and rim_inner - band_buffer < r < rim_outer + band_buffer):
            return True
    return False


# =============================================================================
# VINE TUBE BUILDER
# =============================================================================

def make_vine_tube(name, P0, P1, P2, P3, segments=24, radius=0.025,
                    ring_verts=7, taper=0.35, mat=None, link_collection=None):
    """Build a thin tapered cylinder swept along a cubic bezier.

    Uses parallel-transport frame: each ring's orientation derives from the
    previous ring's, projected onto the new tangent plane. This avoids the
    twisting artifacts that fresh tg×Z computation causes at every point.

    Returns the new Object.
    """
    bm = bmesh.new()
    rings = []
    prev_side = None
    for i in range(segments + 1):
        t = i / segments
        p = ((1-t)**3*P0 + 3*(1-t)**2*t*P1
             + 3*(1-t)*t**2*P2 + t**3*P3)
        tg = (3*(1-t)**2*(P1-P0) + 6*(1-t)*t*(P2-P1) + 3*t**2*(P3-P2))
        if tg.length < 1e-5:
            tg = Vector((0, 0, 1))
        tg.normalize()
        if prev_side is None:
            side = tg.cross(Vector((0, 0, 1)))
            if side.length < 1e-3:
                side = Vector((1, 0, 0))
            side.normalize()
        else:
            # Parallel transport
            side = prev_side - tg * prev_side.dot(tg)
            if side.length < 1e-5:
                side = Vector((1, 0, 0))
            side.normalize()
        up = tg.cross(side).normalized()
        prev_side = side
        r = radius * (1.0 - taper * (i / segments))
        ring = []
        for j in range(ring_verts):
            a = j * 2 * math.pi / ring_verts
            offset = side * (r * math.cos(a)) + up * (r * math.sin(a))
            ring.append(bm.verts.new(p + offset))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for i in range(segments):
        r0, r1 = rings[i], rings[i+1]
        for j in range(ring_verts):
            jn = (j+1) % ring_verts
            bm.faces.new([r0[j], r0[jn], r1[jn], r1[j]])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    if mat:
        obj.data.materials.append(mat)
    coll = link_collection or bpy.context.scene.collection
    coll.objects.link(obj)
    return obj


# =============================================================================
# LEAF MESHES
# =============================================================================

def make_heart_leaf_mesh(name, length=0.30, width=0.25, twist=0.0,
                          curl=0.012, leaf_mat=None):
    """Heart-shaped (cordate) leaf mesh, used for pothos and ivy.

    `twist`: pre-bake rotation around Y axis so left/right edges tilt up/down.
    Combine with a pool of variants (Footgun #3) for visual variety.
    """
    bm = bmesh.new()
    N = 24
    outline = []
    for i in range(N):
        t = (i / N) * 2 * math.pi
        hx = 16 * math.sin(t)**3
        hy = 13*math.cos(t) - 5*math.cos(2*t) - 2*math.cos(3*t) - math.cos(4*t)
        x = hx / 16 * width / 2
        y = -hy / 17 * length / 2
        # Pre-baked twist: z based on x position
        z = math.sin(twist) * x
        x = math.cos(twist) * x
        outline.append(Vector((x, y, z)))
    bm_verts = [bm.verts.new(v) for v in outline]
    center = bm.verts.new((0, 0, curl))
    bm.verts.ensure_lookup_table()
    for i in range(N):
        bm.faces.new([center, bm_verts[i], bm_verts[(i+1) % N]])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # UV map (planar from above)
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.new('UVMap')
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    xmin, xmax = min(xs), max(xs)
    ymin, ymax = min(ys), max(ys)
    for f in bm.faces:
        for l in f.loops:
            v = l.vert.co
            l[uv].uv = ((v.x-xmin)/(xmax-xmin), (v.y-ymin)/(ymax-ymin))
    bm.to_mesh(me)
    bm.free()
    if leaf_mat:
        me.materials.append(leaf_mat)
    return me


def make_leaf_pair_mesh(name, length=0.28, width=0.13, leaf_mat=None):
    """Paired oval leaves sharing center pivot at origin.

    Leaf 1 extends in +X direction (length wide), leaf 2 in -X. Pivot at
    (0,0,0) is the stem-attachment point. Used for opposite-decussate phyllotaxy
    (jasmine, mint, basil, etc.) — one mesh per node instead of two single-leaf
    objects.

    This pattern avoids Footgun #12 (off-center rotation pivot) entirely:
    rotating this mesh around its origin pivots both leaves around their shared
    base, exactly how a real leaf pair attaches.
    """
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    # Leaf 1 (+X side)
    v1_base_top = bm.verts.new((0, width*0.15, 0))
    v1_base_bot = bm.verts.new((0, -width*0.15, 0))
    v1_mid_top = bm.verts.new((length*0.5, width*0.5, 0.005))
    v1_mid_bot = bm.verts.new((length*0.5, -width*0.5, 0.005))
    v1_tip = bm.verts.new((length, 0, 0.0))
    bm.verts.ensure_lookup_table()
    f1a = bm.faces.new([v1_base_top, v1_mid_top, v1_mid_bot, v1_base_bot])
    f1b = bm.faces.new([v1_mid_top, v1_tip, v1_mid_bot])
    f1a.loops[0][uv].uv = (0, 0.6); f1a.loops[1][uv].uv = (0.5, 0.9)
    f1a.loops[2][uv].uv = (0.5, 0.1); f1a.loops[3][uv].uv = (0, 0.4)
    f1b.loops[0][uv].uv = (0.5, 0.9); f1b.loops[1][uv].uv = (1.0, 0.5); f1b.loops[2][uv].uv = (0.5, 0.1)
    # Leaf 2 (-X side, mirror)
    v2_base_top = bm.verts.new((0, width*0.15, 0))
    v2_base_bot = bm.verts.new((0, -width*0.15, 0))
    v2_mid_top = bm.verts.new((-length*0.5, width*0.5, 0.005))
    v2_mid_bot = bm.verts.new((-length*0.5, -width*0.5, 0.005))
    v2_tip = bm.verts.new((-length, 0, 0.0))
    bm.verts.ensure_lookup_table()
    f2a = bm.faces.new([v2_base_top, v2_base_bot, v2_mid_bot, v2_mid_top])
    f2b = bm.faces.new([v2_mid_top, v2_mid_bot, v2_tip])
    f2a.loops[0][uv].uv = (0, 0.6); f2a.loops[1][uv].uv = (0, 0.4)
    f2a.loops[2][uv].uv = (0.5, 0.1); f2a.loops[3][uv].uv = (0.5, 0.9)
    f2b.loops[0][uv].uv = (0.5, 0.9); f2b.loops[1][uv].uv = (0.5, 0.1); f2b.loops[2][uv].uv = (1.0, 0.5)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    if leaf_mat:
        me.materials.append(leaf_mat)
    return me


def make_oval_leaf_mesh(name, length=0.30, width=0.18, leaf_mat=None):
    """Oval pointed leaf plane — for jasmine, basil, mint, peace lily, etc.

    Mesh = simple 4-vert quad. Pair with a leaf texture that's oval-shaped
    with alpha cutout. Place perpendicular to stem in opposite-decussate
    pairs.
    """
    bm = bmesh.new()
    v0 = bm.verts.new((-width/2, -length*0.3, 0))
    v1 = bm.verts.new(( width/2, -length*0.3, 0))
    v2 = bm.verts.new(( width/2,  length*0.7, 0))
    v3 = bm.verts.new((-width/2,  length*0.7, 0))
    bm.verts.ensure_lookup_table()
    f = bm.faces.new([v0, v1, v2, v3])
    uv = bm.loops.layers.uv.new('UVMap')
    f.loops[0][uv].uv = (0, 0)
    f.loops[1][uv].uv = (1, 0)
    f.loops[2][uv].uv = (1, 1)
    f.loops[3][uv].uv = (0, 1)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if leaf_mat:
        me.materials.append(leaf_mat)
    return me


def build_heart_leaf_pool(prefix='PothosLeafMesh',
                           sizes=(('S', 0.22, 0.18),
                                  ('M', 0.30, 0.25),
                                  ('L', 0.40, 0.32),
                                  ('XL', 0.48, 0.40)),
                           twists=(-0.4, -0.15, 0.0, 0.15, 0.4),
                           leaf_mat=None):
    """Build a mesh pool with multiple sizes × twists for visual variety.

    Returns dict mapping size label -> list of mesh datablocks (one per twist).
    See Footgun #3 — pool variety is required to break up uniform foliage.
    """
    pool = {}
    for size_label, L, W in sizes:
        pool[size_label] = []
        for ti, twist in enumerate(twists):
            name = f'{prefix}_{size_label}_t{ti}'
            me = make_heart_leaf_mesh(name, L, W, twist=twist, leaf_mat=leaf_mat)
            pool[size_label].append(me)
    return pool


# =============================================================================
# LEAF PLACEMENT — phyllotaxy
# =============================================================================

def place_leaves_phyllotaxy(samples, leaf_mesh_pool, name_prefix='Leaf',
                              nodes_per_stem=(6, 10),
                              t_range=(0.10, 0.95),
                              petiole=(0.012, 0.020),
                              leaf_offset=(0.045, 0.075),
                              droop_range=(0.20, 0.55),
                              size_weights=(3, 4, 2),
                              link_collection=None):
    """Place leaves in opposite-decussate phyllotaxy along a stem.

    At each node, two leaves are placed on opposite sides perpendicular to the
    stem. Successive node pairs rotate 90° around the stem axis (true
    decussate pattern, used by jasmine, mint, basil, lilac, etc.).

    leaf_mesh_pool: list of meshes [small, medium, large] (or pool dict —
    if dict, takes random from each tier's list per Footgun #3).
    """
    if isinstance(leaf_mesh_pool, dict):
        size_keys = ['S', 'M', 'L']  # assume this ordering
        is_pool_dict = True
    else:
        is_pool_dict = False

    coll = link_collection or bpy.context.scene.collection
    n_nodes = random.randint(*nodes_per_stem)
    t_min, t_max = t_range
    node_ts = [t_min + (i+0.5)/n_nodes * (t_max - t_min) for i in range(n_nodes)]
    phyllotaxy_base = random.uniform(0, math.pi)
    placed = []

    for ni, ti in enumerate(node_ts):
        sidx = min(int(ti * len(samples)), len(samples)-2)
        p, tg, _ = samples[sidx]

        # Build a basis perpendicular to the stem tangent
        if abs(tg.z) > 0.95:
            primary = Vector((1, 0, 0))
        else:
            primary = tg.cross(Vector((0, 0, 1)))
            if primary.length < 1e-3:
                primary = Vector((1, 0, 0))
            primary.normalize()
        secondary = tg.cross(primary).normalized()

        # 90° rotation between successive nodes
        phyllo_angle = phyllotaxy_base + ni * (math.pi / 2)
        leaf_axis = (primary * math.cos(phyllo_angle)
                     + secondary * math.sin(phyllo_angle)).normalized()

        for side in (1, -1):
            pet = random.uniform(*petiole)
            leaf_origin = p + leaf_axis * side * pet
            droop = random.uniform(*droop_range)
            leaf_out_dir = (leaf_axis * side * 0.85
                            + Vector((0, 0, -droop + random.uniform(-0.15, 0.20)))
                            ).normalized()
            leaf_loc = leaf_origin + leaf_out_dir * random.uniform(*leaf_offset)

            # Orient leaf with NORMAL biased upward (broadside catches camera)
            forward = leaf_out_dir.normalized()
            desired_normal = Vector((
                random.uniform(-0.4, 0.4),
                random.uniform(-0.4, 0.4),
                random.uniform(0.6, 1.0)
            )).normalized()
            normal = desired_normal - forward * forward.dot(desired_normal)
            if normal.length < 0.05:
                normal = forward.cross(Vector((1, 0, 0)))
                if normal.length < 0.05:
                    normal = forward.cross(Vector((0, 1, 0)))
            normal.normalize()
            right = normal.cross(forward).normalized()
            M = Matrix((
                (right.x, forward.x, normal.x, 0),
                (right.y, forward.y, normal.y, 0),
                (right.z, forward.z, normal.z, 0),
                (0, 0, 0, 1)
            ))

            if is_pool_dict:
                size_key = random.choices(size_keys, weights=size_weights[:len(size_keys)])[0]
                leaf_mesh = random.choice(leaf_mesh_pool[size_key])
            else:
                leaf_mesh = random.choices(leaf_mesh_pool, weights=size_weights)[0]
            obj = bpy.data.objects.new(f'{name_prefix}_{len(placed):04d}', leaf_mesh)
            obj.matrix_world = Matrix.Translation(leaf_loc) @ M
            s = random.uniform(0.85, 1.20)
            obj.scale = (s, s, s)
            coll.objects.link(obj)
            placed.append(obj)
    return placed


def place_leaves_along_vine(samples, leaf_mesh_pool, t_exit, name_prefix='Leaf',
                              n_leaves=(6, 8),
                              t_max=0.99,
                              petiole_range=(0.06, 0.13),
                              droop_range=(0.10, 0.85),
                              full_twist=True,
                              size_tier_func=None,
                              link_collection=None,
                              skip_if_inside_pot=None,
                              stratified=True,
                              bucket_margin=0.20):
    """Place leaves uniformly along a vine (used for pothos cascading style).

    Unlike place_leaves_phyllotaxy, this puts ONE leaf per t-position (not
    paired), with FULL rotation variety (twist around forward axis ∈ [0, 2π])
    so the leaf can face any direction. See Footgun #3.

    `stratified=True` (default): divide t-range into n_leaves buckets, one leaf
    per bucket with jitter — guarantees spacing AND count in one pass. Avoids
    Footgun #11 (random + rejection sampling collisions).

    skip_if_inside_pot: optional callable(loc) -> bool to filter placements
    that would land inside the pot bbox.
    """
    coll = link_collection or bpy.context.scene.collection
    n = random.randint(*n_leaves)
    t_min = max(t_exit + 0.05, 0.15)
    if stratified:
        bucket_width = (t_max - t_min) / n
        t_values = []
        for i in range(n):
            b0 = t_min + i * bucket_width
            b1 = t_min + (i + 1) * bucket_width
            margin = bucket_width * bucket_margin
            t_values.append(random.uniform(b0 + margin, b1 - margin))
    else:
        t_values = sorted([random.uniform(t_min, t_max) for _ in range(n)])
    placed = []

    for ti in t_values:
        sidx = min(int(ti * len(samples)), len(samples)-2)
        p, tg, _ = samples[sidx]

        # Random angle around stem
        side_rot = random.uniform(-1, 1)
        side_vec = tg.cross(Vector((0, 0, 1)))
        if side_vec.length < 1e-3:
            side_vec = Vector((1, 0, 0))
        side_vec.normalize()
        out_dir = Vector((p.x, p.y, 0))
        if out_dir.length < 0.01:
            out_dir = side_vec.copy()
        out_dir.normalize()
        attach_dir = (out_dir * math.cos(side_rot)
                      + side_vec * math.sin(side_rot)).normalized()

        droop = random.uniform(*droop_range)
        leaf_dir = (attach_dir
                    + Vector((0, 0, -droop))
                    + Vector((random.uniform(-0.15, 0.15),
                              random.uniform(-0.15, 0.15),
                              0))).normalized()

        petiole = random.uniform(*petiole_range)
        loc = p + leaf_dir * petiole + Vector((
            random.uniform(-0.02, 0.02),
            random.uniform(-0.02, 0.02),
            random.uniform(-0.02, 0.02)
        ))

        if skip_if_inside_pot and skip_if_inside_pot(loc):
            continue

        # Pick mesh
        if size_tier_func:
            mesh = size_tier_func(ti, leaf_mesh_pool)
        elif isinstance(leaf_mesh_pool, dict):
            mesh = random.choice(leaf_mesh_pool[random.choice(list(leaf_mesh_pool.keys()))])
        else:
            mesh = random.choice(leaf_mesh_pool)

        # ROTATION with full twist around forward — KEY for variety (Footgun #3)
        forward = leaf_dir.normalized()
        if full_twist:
            twist_angle = random.uniform(0, 2 * math.pi)
        else:
            twist_angle = 0.0
        if abs(forward.z) > 0.95:
            right_initial = Vector((1, 0, 0))
        else:
            right_initial = forward.cross(Vector((0, 0, 1)))
            right_initial.normalize()
        normal_initial = right_initial.cross(forward).normalized()
        cos_t = math.cos(twist_angle)
        sin_t = math.sin(twist_angle)
        right = right_initial * cos_t + normal_initial * sin_t
        normal = -right_initial * sin_t + normal_initial * cos_t

        obj = bpy.data.objects.new(f'{name_prefix}_{len(placed):04d}', mesh)
        M = Matrix((
            (right.x, forward.x, normal.x, 0),
            (right.y, forward.y, normal.y, 0),
            (right.z, forward.z, normal.z, 0),
            (0, 0, 0, 1)
        ))
        obj.matrix_world = Matrix.Translation(loc) @ M
        s = random.uniform(0.85, 1.30)
        obj.scale = (s, s, s)
        coll.objects.link(obj)
        placed.append(obj)
    return placed


# =============================================================================
# FLOWER + BUD MESHES
# =============================================================================

def make_5petal_flower_mesh(name='FlowerMesh', R_petal=0.07, petal_W=0.04,
                             center_R=0.015, center_Z=0.010,
                             petal_mat=None, center_mat=None):
    """5-petal star flower mesh with raised yellow center disc.

    Default size matches jasmine scale on 1m-plant scenes.
    Keep R_petal ≤ 40% of typical leaf length (Footgun #7).
    """
    bm = bmesh.new()
    center = bm.verts.new((0, 0, 0.005))
    N = 5
    rim_verts = []
    for i in range(N):
        a = i * 2*math.pi / N + math.pi/2
        tip = bm.verts.new((R_petal*math.cos(a), R_petal*math.sin(a), 0.0))
        a_l = a + math.pi / N
        a_r = a - math.pi / N
        base_l = bm.verts.new((petal_W*0.55*math.cos(a_l), petal_W*0.55*math.sin(a_l), 0.0))
        base_r = bm.verts.new((petal_W*0.55*math.cos(a_r), petal_W*0.55*math.sin(a_r), 0.0))
        rim_verts.append((tip, base_l, base_r))
    bm.verts.ensure_lookup_table()
    for i in range(N):
        tip, bl, br = rim_verts[i]
        bm.faces.new([center, br, tip])
        bm.faces.new([center, tip, bl])
    # Center disc raised slightly
    cd = []
    for i in range(6):
        a = i * 2*math.pi/6
        cd.append(bm.verts.new((center_R*math.cos(a), center_R*math.sin(a), center_Z)))
    ct = bm.verts.new((0, 0, center_Z + 0.005))
    bm.verts.ensure_lookup_table()
    for i in range(6):
        bm.faces.new([ct, cd[i], cd[(i+1)%6]])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if petal_mat:
        me.materials.append(petal_mat)
    if center_mat:
        me.materials.append(center_mat)
        nf = len(me.polygons)
        for i in range(nf - 6, nf):
            me.polygons[i].material_index = 1
    return me


def make_bud_mesh(name='BudMesh', R=0.010, H=0.025, mat=None):
    """Small teardrop/cone bud mesh (closed flower).

    Used to mix with open flowers so the plant reads as partly-in-bud,
    a more lifelike state (Footgun #6).
    """
    bm = bmesh.new()
    N = 5
    base = []
    for i in range(N):
        a = i * 2*math.pi/N
        base.append(bm.verts.new((R*math.cos(a), R*math.sin(a), 0)))
    tip = bm.verts.new((0, 0, H))
    bm.verts.ensure_lookup_table()
    for i in range(N):
        bm.faces.new([base[i], base[(i+1)%N], tip])
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if mat:
        me.materials.append(mat)
    return me


# =============================================================================
# FLOWER / BUD SCATTERING — see Footgun #6
# =============================================================================

def scatter_flowers(samples, flower_mesh, bud_mesh=None,
                     name_prefix='Flower', bud_prefix='Bud',
                     t_range=(0.45, 0.99),
                     n_flowers=(5, 9),
                     bud_chance_at_mid=0.20, bud_chance_at_tip=0.50,
                     link_collection=None):
    """Distribute flowers and buds along the upper portion of a stem.

    Spreads flowers throughout t_range (not just clustered at t=1.0) — see
    Footgun #6. Bud probability rises toward the tip.
    """
    coll = link_collection or bpy.context.scene.collection
    n = random.randint(*n_flowers)
    t_values = sorted([random.uniform(*t_range) for _ in range(n)])
    placed_f = []
    placed_b = []
    t_mid = (t_range[0] + t_range[1]) / 2
    t_span = t_range[1] - t_range[0]

    for ti in t_values:
        sidx = min(int(ti * len(samples)), len(samples)-2)
        p, tg, _ = samples[sidx]
        side = tg.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        offset = (side * random.uniform(-0.10, 0.10)
                  + Vector((random.uniform(-0.05, 0.05),
                            random.uniform(-0.05, 0.05),
                            random.uniform(0.01, 0.06))))
        loc = p + offset

        # Bud chance rises with t
        bud_chance = bud_chance_at_mid + (ti - t_mid)/t_span * (bud_chance_at_tip - bud_chance_at_mid)
        is_bud = bud_mesh is not None and random.random() < bud_chance

        if is_bud:
            obj = bpy.data.objects.new(f'{bud_prefix}_{len(placed_b):03d}', bud_mesh)
            obj.location = loc
            outward = Vector((p.x, p.y, 0))
            fn = ((outward.normalized()*0.2 + Vector((0, 0, 0.9))).normalized()
                  if outward.length > 0.01 else Vector((0, 0, 1)))
            _orient_axis_angle(obj, fn)
            s = random.uniform(0.7, 1.2)
            obj.scale = (s, s, s)
            coll.objects.link(obj)
            placed_b.append(obj)
        else:
            obj = bpy.data.objects.new(f'{name_prefix}_{len(placed_f):03d}', flower_mesh)
            obj.location = loc
            outward = Vector((p.x, p.y, 0))
            if outward.length < 0.01:
                outward = Vector((1, 0, 0))
            outward.normalize()
            fn = (outward * 0.4 + Vector((0, 0, 0.8))
                  + Vector((random.uniform(-0.3, 0.3),
                            random.uniform(-0.3, 0.3), 0))).normalized()
            _orient_axis_angle(obj, fn)
            s = random.uniform(0.85, 1.35)
            obj.scale = (s, s, s)
            coll.objects.link(obj)
            placed_f.append(obj)

    return placed_f, placed_b


def _orient_axis_angle(obj, target_normal):
    """Set object rotation so its +Z axis points along target_normal."""
    z = Vector((0, 0, 1))
    rot_axis = z.cross(target_normal)
    if rot_axis.length > 1e-4:
        ang = math.acos(max(-1, min(1, z.dot(target_normal))))
        rot_axis.normalize()
        obj.rotation_mode = 'AXIS_ANGLE'
        obj.rotation_axis_angle = (ang, *rot_axis)
