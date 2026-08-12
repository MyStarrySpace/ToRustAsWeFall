"""
Shared helpers for the stylized-plant skill.

Drop into a Blender script and import / paste these functions. Designed to be
called in this order:
    1. wipe_scene()
    2. setup_world(...)
    3. make_pixel_image(...) for each texture
    4. make_pixel_mat(...) for each material
    5. build_pot/soil/saucer/floor()
    6. plant-specific build (cards, petioles, etc.)
    7. setup_lights_and_camera()
    8. render_and_save()

Critical lessons baked in:
- Card vertex orders are CCW from +Z so face normals point up by default.
- After every face creation, force normal up with face.normal_flip() if .z < 0.
- UVs computed from world position (not loop index) so they survive flips.
- No twist around leaf_dir — variation comes from leaf_dir blending.
- Spread origins (r0 ≥ 0.12) for plants with multiple stalks emerging from soil.
- Petioles arch UP to a peak, then bezier descends — leaf droops outward.

References to specific .blend versions in outputs/ correspond to the SKILL.md table.
"""

import bpy, bmesh, math, random
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree


# =============================================================================
# Scene setup
# =============================================================================

def wipe_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                bpy.data.images, bpy.data.textures, bpy.data.lights, bpy.data.cameras):
        for it in list(blk):
            try: blk.remove(it)
            except: pass
    for c in list(bpy.data.collections):
        if c.name != 'Collection':
            try: bpy.data.collections.remove(c)
            except: pass


def setup_world(bg_color=(0.05, 0.06, 0.08, 1.0), strength=1.0):
    w = bpy.context.scene.world
    if w is None:
        w = bpy.data.worlds.new('World'); bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputWorld'); out.location=(300,0)
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Color'].default_value = bg_color
    bg.inputs['Strength'].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs[0])


# =============================================================================
# Pixel-art textures
# =============================================================================

def make_pixel_image(name, grid, alpha=True):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    h = len(grid); w = len(grid[0])
    img = bpy.data.images.new(name, w, h, alpha=alpha)
    pixels = []
    for y in range(h):
        row = grid[h-1-y]  # Blender stores rows bottom-to-top
        for px in row:
            pixels.extend(px)
    img.pixels = pixels
    img.pack()
    img.update()
    return img


def make_pixel_mat(name, image, transparent=False, sss_weight=0.18,
                   sss_radius=(0.45, 0.75, 0.25), sss_scale=0.08, roughness=0.85):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(900,0)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location=(600,0)
    bsdf.inputs['Roughness'].default_value = roughness
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = 0.20
    if sss_weight > 0 and 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = sss_weight
        bsdf.inputs['Subsurface Radius'].default_value = sss_radius
        if 'Subsurface Scale' in bsdf.inputs:
            bsdf.inputs['Subsurface Scale'].default_value = sss_scale
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.location=(0,0)
    tex.image = image
    tex.interpolation = 'Closest'
    tex.extension = 'CLIP' if transparent else 'REPEAT'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if transparent:
        nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m


# =============================================================================
# Bezier helpers - PREFER QUADRATIC for fronds; cubic only if you need an inflection
# =============================================================================

def quad_bezier(p0, p1, p2, t):
    return p0*(1-t)**2 + p1*2*(1-t)*t + p2*t*t


def build_curve(p0, p_mid, p_tip, samples=10):
    return [quad_bezier(p0, p_mid, p_tip, i/samples) for i in range(samples+1)]


def cubic_bezier(p0, p1, p2, p3, t):
    """Use only when you NEED an inflection (e.g. Pothos vine over a rim)."""
    u = 1 - t
    return p0*u**3 + p1*3*u**2*t + p2*3*u*t**2 + p3*t**3


def build_curve_cubic(p0, p1, p2, p3, samples=18):
    return [cubic_bezier(p0, p1, p2, p3, i/samples) for i in range(samples+1)]


# =============================================================================
# LEAF CARD — flat quad with alpha-cutout texture
# CRITICAL: vertex order CCW from +Z so default normal points up. Then explicit
# normal_flip safety check.
# =============================================================================

def make_leaf_card(name, base_pos, leaf_dir, mat_name,
                   length=0.95, width=0.42, twist=0.0):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    half_w = width * 0.5
    leaf_dir = leaf_dir.normalized()
    up = Vector((0,0,1))
    face_normal_target = (up - leaf_dir * up.dot(leaf_dir)).normalized()
    if face_normal_target.length < 0.5:
        face_normal_target = Vector((0, 1, 0))
    local_x = face_normal_target.cross(leaf_dir).normalized()
    if abs(twist) > 1e-4:
        q = Quaternion(leaf_dir, twist)
        local_x = q @ local_x

    bl = base_pos - local_x * half_w
    br = base_pos + local_x * half_w
    tl = base_pos - local_x * half_w + leaf_dir * length
    tr = base_pos + local_x * half_w + leaf_dir * length
    v_bl = bm.verts.new(bl); v_br = bm.verts.new(br)
    v_tr = bm.verts.new(tr); v_tl = bm.verts.new(tl)
    bm.verts.ensure_lookup_table()

    # CCW from +Z: bl -> tl -> tr -> br
    f = bm.faces.new([v_bl, v_tl, v_tr, v_br])
    bm.faces.ensure_lookup_table()
    if f.normal.z < 0:
        f.normal_flip()

    uv_layer = bm.loops.layers.uv.new('UVMap')
    for loop in f.loops:
        v = loop.vert.co
        rel = v - base_pos
        u = (rel.dot(local_x) / max(half_w*2, 1e-6)) + 0.5
        vv = rel.dot(leaf_dir) / max(length, 1e-6)
        loop[uv_layer].uv = (u, vv)

    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = False
    obj = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(obj)
    obj.data.materials.append(bpy.data.materials[mat_name])
    return obj


# =============================================================================
# CURVED CARD — bezier strip for fronds, vines, ribbon leaves
# =============================================================================

def horiz_perp(tan):
    horiz = Vector((tan.x, tan.y, 0))
    if horiz.length < 1e-3: return Vector((1, 0, 0))
    horiz.normalize()
    return Vector((-horiz.y, horiz.x, 0))


def build_curved_card(name, p0, p_mid, p_tip, mat_name,
                      samples=18, base_width=1.6, twist=0.0,
                      width_profile_fn=None, uv_inset=0.02,
                      width_axis='horiz_perp'):
    if width_profile_fn is None:
        width_profile_fn = lambda t, w: w * (0.08 + 0.92 * math.sin(t * math.pi))

    pts = build_curve(p0, p_mid, p_tip, samples=samples)
    seg_dirs = [(pts[i+1]-pts[i]).normalized() for i in range(len(pts)-1)]
    _wat = horiz_perp

    width_dir = _wat(seg_dirs[0])
    if abs(twist) > 1e-4:
        q = Quaternion(seg_dirs[0], twist)
        width_dir = q @ width_dir

    verts = []
    for idx, p in enumerate(pts):
        if idx == 0: tan = seg_dirs[0]
        elif idx == len(pts)-1: tan = seg_dirs[-1]
        else: tan = (seg_dirs[idx-1] + seg_dirs[idx]).normalized()
        new_w = width_dir - tan * width_dir.dot(tan)
        if new_w.length < 1e-4: new_w = _wat(tan)
        else: new_w.normalize()
        width_dir = new_w
        t = idx / (len(pts)-1)
        w = width_profile_fn(t, base_width)
        verts.append(tuple(p - width_dir * w * 0.5))
        verts.append(tuple(p + width_dir * w * 0.5))

    faces = [(2*idx, 2*(idx+1), 2*(idx+1)+1, 2*idx+1) for idx in range(len(pts)-1)]

    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    me.uv_layers.new(name='UVMap')
    uv = me.uv_layers.active
    u_lo = uv_inset; u_hi = 1.0 - uv_inset
    for face_idx, poly in enumerate(me.polygons):
        t0 = face_idx / (len(pts)-1)
        t1 = (face_idx + 1) / (len(pts)-1)
        loop_indices = list(poly.loop_indices)
        uv.data[loop_indices[0]].uv = (u_lo, t0)
        uv.data[loop_indices[1]].uv = (u_lo, t1)
        uv.data[loop_indices[2]].uv = (u_hi, t1)
        uv.data[loop_indices[3]].uv = (u_hi, t0)
    for p in me.polygons: p.use_smooth = False

    obj = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(obj)
    obj.data.materials.append(bpy.data.materials[mat_name])

    # Force every face's normal up if it's pointing down
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    flipped = False
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip(); flipped = True
    if flipped:
        bm.to_mesh(me); me.update()
    bm.free()

    return obj


# =============================================================================
# Procedural fern frond texture (v13 recipe)
# Image dims should match card aspect: 20x110 for 0.20x1.10 fronds.
# =============================================================================

def fern_frond_grid(W=20, H=110,
                    PINNA_SPACING=4, PINNA_HEIGHT=3, MAX_EXTENT=6,
                    rachis_color=(0.18, 0.32, 0.12, 1.0),
                    pinna_a=(0.32, 0.62, 0.22, 1.0),
                    pinna_b=(0.26, 0.50, 0.18, 1.0),
                    pinna_c=(0.40, 0.70, 0.28, 1.0),
                    transparent=(0, 0, 0, 0)):
    """
    Build a feathered frond pixel grid with discrete pinnae + transparent gaps.
    Tuning knobs:
      MAX_EXTENT — widest pinna half-width. 4=wispy, 6=balanced, 9+=palm-like
      PINNA_SPACING — rows between pinna pairs (≥3 to keep gaps visible)
      PINNA_HEIGHT — rows per pinna (lance taper)
    """
    cx = (W - 1) / 2.0
    g = [[transparent] * W for _ in range(H)]
    rcx = int(round(cx))
    for y in range(H):
        if 0 <= rcx < W:
            g[y][rcx] = rachis_color
    for k, py in enumerate(range(3, H - 4, PINNA_SPACING)):
        t = py / max(H - 1, 1)
        if t < 0.10:
            scale = 0.35 + (t / 0.10) * 0.25
        elif t < 0.55:
            scale = 0.60 + (t - 0.10) / 0.45 * 0.40
        else:
            scale = 1.00 - (t - 0.55) / 0.45 * 0.65
        extent = max(1, int(round(MAX_EXTENT * scale)))
        for side in (+1, -1):
            for ph in range(PINNA_HEIGHT):
                if ph == 0: width = extent
                elif ph == 1: width = max(1, extent - 1)
                else: width = max(1, extent - 2)
                yy = py + ph
                if not (0 <= yy < H): continue
                for d in range(1, width + 1):
                    xx = rcx + side * d
                    if not (0 <= xx < W): continue
                    phase = (k + d) % 3
                    if phase == 0: c = pinna_a
                    elif phase == 1: c = pinna_b
                    else: c = pinna_c
                    g[yy][xx] = c
    return g


# =============================================================================
# BVH collision
# =============================================================================

def world_bvh(obj):
    me = obj.data; M = obj.matrix_world
    verts = [M @ v.co for v in me.vertices]
    polys = [list(p.vertices) for p in me.polygons]
    return BVHTree.FromPolygons(verts, polys, all_triangles=False)


def overlaps_any(bvh, others):
    for ob in others:
        if bvh.overlap(ob): return True
    return False


# =============================================================================
# Stratified angular slots
# =============================================================================

def stratified_angles(N, jitter=0.10, offset=0.0):
    return [(i / N) * math.tau + offset + random.uniform(-jitter, jitter)
            for i in range(N)]


# =============================================================================
# Lights and camera
# =============================================================================

def add_area(name, loc, target, energy, size=2.0, color=(1,1,1)):
    bpy.ops.object.light_add(type='AREA', location=loc)
    o = bpy.context.object; o.name = name
    o.data.energy = energy; o.data.size = size; o.data.color = color
    direction = Vector(target) - Vector(loc)
    o.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    return o


def setup_three_point(target=(0,0,1.5), key=450, fill=110, rim=150):
    add_area('Key',  ( 3.5,-3.5, 4.0), target, key,  2.5, (1.00, 0.96, 0.92))
    add_area('Fill', (-3.0,-1.5, 3.0), target, fill, 3.0, (0.85, 0.92, 1.00))
    add_area('Rim',  (-1.0, 4.0, 3.0), target, rim,  1.5, (1.00, 0.95, 0.85))


def setup_camera(loc=(5.0, -5.0, 2.6), target=(0,0,1.5), lens=50):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object; cam.name = 'Camera'; cam.data.lens = lens
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    bpy.context.scene.camera = cam
    return cam


def setup_render(samples=256, w=1280, h=1280):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.image_settings.file_format = 'PNG'
    sc.frame_set(1)
