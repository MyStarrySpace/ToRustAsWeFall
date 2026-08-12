"""
Sobel-stylized rendering helpers.

Three independent techniques you can mix and match:
  1. setup_sobel_compositor(scene, ...) — adds the Compositor graph that draws
     dark lines wherever the geometry has an edge (silhouette OR face fold).
  2. add_directional_shading(material) — modifies a material so its base color
     is multiplied by a top-bottom gradient. Top-facing brighter, downward darker.
  3. apply_uv_checker_to_scene(scene) / restore_materials(...) — temporarily
     swaps all materials for a checker pattern to debug UVs.

All Blender 5.x compatible. Notable API changes from 4.x:
  - scene.compositing_node_group instead of scene.node_tree
  - NodeGroupOutput with Image socket instead of CompositorNodeComposite
  - ShaderNode-prefixed math/mix/colorramp nodes work in compositor
  - Filter node's type is on an input socket (capital "Sobel")
"""

import bpy


# =============================================================================
# 1) Sobel compositor setup
# =============================================================================

def setup_sobel_compositor(scene,
                           position_th=(0.05, 0.10),
                           normal_th=(0.10, 0.20),
                           line_strength=1.0,
                           line_color=(0.0, 0.0, 0.0, 1.0),
                           use_angle_color=False,
                           angle_color_stops=None):
    """
    Build a compositor graph that draws inked outlines on the rendered image.

    position_th: (low, high) ColorRamp range applied to the Position-Sobel mask.
                 Tighter range = more outlines.
    normal_th:   (low, high) for the Normal-Sobel mask. Catches face folds.
    line_strength: 0..1 multiplier — 1.0 = solid lines, 0.5 = ghosted.
    line_color:  RGBA color used for the inked lines (when use_angle_color=False).
    use_angle_color: if True, lines are colored by the surface normal direction
                     instead of being pure `line_color`.
    angle_color_stops: list of (position, RGBA) stops for the angle ColorRamp.
                       Default goes from near-black (down) to mint (up).
    """
    vl = scene.view_layers[0]
    vl.use_pass_z = True
    vl.use_pass_normal = True
    vl.use_pass_position = True

    scene.use_nodes = True
    if scene.compositing_node_group is None:
        ng = bpy.data.node_groups.new('Compositor', 'CompositorNodeTree')
        scene.compositing_node_group = ng
    ng = scene.compositing_node_group

    # Wipe nodes & interface
    for n in list(ng.nodes):
        ng.nodes.remove(n)
    while ng.interface.items_tree:
        ng.interface.remove(ng.interface.items_tree[0])
    ng.interface.new_socket(name='Image', in_out='OUTPUT', socket_type='NodeSocketColor')

    rl = ng.nodes.new('CompositorNodeRLayers');  rl.location = (-1200, 0)
    out_n = ng.nodes.new('NodeGroupOutput');     out_n.location = (1500, 0)

    # ---- Position-Sobel chain (silhouettes) ----
    pos_filter = ng.nodes.new('CompositorNodeFilter')
    pos_filter.location = (-700, 250)
    pos_filter.inputs['Type'].default_value = 'Sobel'
    pos_filter.inputs['Factor'].default_value = 1.0
    ng.links.new(rl.outputs['Position'], pos_filter.inputs['Image'])

    pos_bw = ng.nodes.new('CompositorNodeRGBToBW')
    pos_bw.location = (-450, 250)
    ng.links.new(pos_filter.outputs[0], pos_bw.inputs[0])

    pos_th = ng.nodes.new('ShaderNodeValToRGB')
    pos_th.location = (-200, 250)
    pos_th.color_ramp.elements[0].position = position_th[0]
    pos_th.color_ramp.elements[0].color = (0, 0, 0, 1)
    pos_th.color_ramp.elements[1].position = position_th[1]
    pos_th.color_ramp.elements[1].color = (1, 1, 1, 1)
    ng.links.new(pos_bw.outputs[0], pos_th.inputs[0])

    # ---- Normal-Sobel chain (face folds) ----
    nrm_filter = ng.nodes.new('CompositorNodeFilter')
    nrm_filter.location = (-700, -100)
    nrm_filter.inputs['Type'].default_value = 'Sobel'
    nrm_filter.inputs['Factor'].default_value = 1.0
    ng.links.new(rl.outputs['Normal'], nrm_filter.inputs['Image'])

    nrm_bw = ng.nodes.new('CompositorNodeRGBToBW')
    nrm_bw.location = (-450, -100)
    ng.links.new(nrm_filter.outputs[0], nrm_bw.inputs[0])

    nrm_th = ng.nodes.new('ShaderNodeValToRGB')
    nrm_th.location = (-200, -100)
    nrm_th.color_ramp.elements[0].position = normal_th[0]
    nrm_th.color_ramp.elements[0].color = (0, 0, 0, 1)
    nrm_th.color_ramp.elements[1].position = normal_th[1]
    nrm_th.color_ramp.elements[1].color = (1, 1, 1, 1)
    ng.links.new(nrm_filter.outputs[0], nrm_bw.inputs[0])
    ng.links.new(nrm_bw.outputs[0], nrm_th.inputs[0])

    # ---- Combine masks (max — either trigger draws line) ----
    combine = ng.nodes.new('ShaderNodeMath')
    combine.operation = 'MAXIMUM'
    combine.location = (50, 100)
    ng.links.new(pos_th.outputs[0], combine.inputs[0])
    ng.links.new(nrm_th.outputs[0], combine.inputs[1])

    # ---- Mask multiplier ----
    mask_mul = ng.nodes.new('ShaderNodeMath')
    mask_mul.operation = 'MULTIPLY'
    mask_mul.location = (300, 100)
    mask_mul.inputs[1].default_value = line_strength
    ng.links.new(combine.outputs[0], mask_mul.inputs[0])

    # ---- Line color: constant or angle-driven ----
    if use_angle_color:
        sep = ng.nodes.new('ShaderNodeSeparateXYZ')
        sep.location = (300, -350)
        ng.links.new(rl.outputs['Normal'], sep.inputs[0])

        mr = ng.nodes.new('ShaderNodeMapRange')
        mr.location = (450, -350)
        mr.inputs['From Min'].default_value = -1.0
        mr.inputs['From Max'].default_value = 1.0
        mr.inputs['To Min'].default_value = 0.0
        mr.inputs['To Max'].default_value = 1.0
        ng.links.new(sep.outputs['Z'], mr.inputs['Value'])

        cr = ng.nodes.new('ShaderNodeValToRGB')
        cr.location = (650, -350)
        # Default angle gradient (override via angle_color_stops)
        if angle_color_stops is None:
            angle_color_stops = [
                (0.0, (0.02, 0.04, 0.04, 1.0)),
                (0.4, (0.06, 0.18, 0.16, 1.0)),
                (0.7, (0.22, 0.45, 0.40, 1.0)),
                (1.0, (0.55, 0.85, 0.75, 1.0)),
            ]
        # Configure the ColorRamp
        cr.color_ramp.elements[0].position = angle_color_stops[0][0]
        cr.color_ramp.elements[0].color = angle_color_stops[0][1]
        cr.color_ramp.elements[1].position = angle_color_stops[-1][0]
        cr.color_ramp.elements[1].color = angle_color_stops[-1][1]
        for pos, col in angle_color_stops[1:-1]:
            new_e = cr.color_ramp.elements.new(pos)
            new_e.color = col
        ng.links.new(mr.outputs['Result'], cr.inputs[0])
        line_color_socket = cr.outputs['Color']
    else:
        line_node = ng.nodes.new('CompositorNodeRGB')
        line_node.location = (300, -300)
        line_node.outputs['Color'].default_value = line_color
        line_color_socket = line_node.outputs['Color']

    # ---- Final mix: image → line color via mask ----
    final = ng.nodes.new('ShaderNodeMixRGB')
    final.blend_type = 'MIX'
    final.location = (800, 0)
    ng.links.new(mask_mul.outputs[0], final.inputs['Fac'])
    ng.links.new(rl.outputs['Image'], final.inputs[1])
    ng.links.new(line_color_socket, final.inputs[2])

    ng.links.new(final.outputs[0], out_n.inputs[0])
    return ng


# =============================================================================
# 2) Directional face shading shader insert
# =============================================================================

def add_directional_shading(mat, light_factor=1.20, dark_factor=0.55):
    """
    Modify a material's color path so the Base Color is multiplied by a factor
    that depends on the surface normal's Z component.

      face normal Z = +1 (up)    → multiplied by light_factor
      face normal Z =  0 (side)  → multiplied by mid factor
      face normal Z = -1 (down)  → multiplied by dark_factor

    The image-texture color stays the source of truth; this just shades it.
    Skips emission materials (no point darkening glow). Returns False if the
    material doesn't have the expected texture→BSDF chain.
    """
    if not mat.use_nodes:
        return False
    nt = mat.node_tree
    img_tex = next((n for n in nt.nodes if n.type == 'TEX_IMAGE'), None)
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    em = next((n for n in nt.nodes if n.type == 'EMISSION'), None)
    if img_tex is None:
        return False
    target = bsdf if bsdf else em
    if target is None:
        return False
    target_color = 'Base Color' if bsdf else 'Color'

    # Skip if already added (look for our marker — Geometry node)
    if any(n.type == 'NEW_GEOMETRY' for n in nt.nodes):
        return False

    # Disconnect existing color link to BSDF
    for link in list(nt.links):
        if link.from_node == img_tex and link.to_socket == target.inputs[target_color]:
            nt.links.remove(link); break

    geo = nt.nodes.new('ShaderNodeNewGeometry')
    geo.location = (img_tex.location.x - 100, img_tex.location.y - 350)

    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    sep.location = (geo.location.x + 200, geo.location.y)
    nt.links.new(geo.outputs['Normal'], sep.inputs[0])

    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.location = (sep.location.x + 200, sep.location.y)
    mr.inputs['From Min'].default_value = -1.0
    mr.inputs['From Max'].default_value = 1.0
    mr.inputs['To Min'].default_value = dark_factor
    mr.inputs['To Max'].default_value = light_factor
    nt.links.new(sep.outputs['Z'], mr.inputs['Value'])

    comb = nt.nodes.new('ShaderNodeCombineColor')
    comb.location = (mr.location.x + 200, mr.location.y)
    if hasattr(comb, 'mode'):
        comb.mode = 'RGB'
    nt.links.new(mr.outputs['Result'], comb.inputs[0])
    nt.links.new(mr.outputs['Result'], comb.inputs[1])
    nt.links.new(mr.outputs['Result'], comb.inputs[2])

    mul = nt.nodes.new('ShaderNodeMix')
    mul.data_type = 'RGBA'
    mul.blend_type = 'MULTIPLY'
    mul.clamp_factor = True
    mul.location = (comb.location.x + 200, img_tex.location.y)
    mul.inputs['Factor'].default_value = 1.0
    nt.links.new(img_tex.outputs['Color'], mul.inputs[6])
    nt.links.new(comb.outputs[0], mul.inputs[7])
    nt.links.new(mul.outputs[2], target.inputs[target_color])

    return True


# =============================================================================
# 3) UV checkerboard diagnostic
# =============================================================================

def make_uv_check_material(name='Mat_UVCheck'):
    """Procedural checker material for UV diagnostic. Two-level pattern:
    coarse red/blue squares + finer black/white squares, multiplied."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (600, 0)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location = (300, 0)
    bsdf.inputs['Roughness'].default_value = 0.85

    tc = nt.nodes.new('ShaderNodeTexCoord'); tc.location = (-600, 0)

    mp = nt.nodes.new('ShaderNodeMapping'); mp.location = (-400, 0)
    mp.inputs['Scale'].default_value = (8, 8, 1)
    nt.links.new(tc.outputs['UV'], mp.inputs['Vector'])

    chk = nt.nodes.new('ShaderNodeTexChecker'); chk.location = (-100, 0)
    chk.inputs['Color1'].default_value = (1.0, 0.2, 0.2, 1)
    chk.inputs['Color2'].default_value = (0.2, 0.6, 1.0, 1)
    chk.inputs['Scale'].default_value = 1.0
    nt.links.new(mp.outputs[0], chk.inputs['Vector'])

    chk2 = nt.nodes.new('ShaderNodeTexChecker'); chk2.location = (-100, -200)
    chk2.inputs['Color1'].default_value = (0.05, 0.05, 0.05, 1)
    chk2.inputs['Color2'].default_value = (0.95, 0.95, 0.95, 1)
    chk2.inputs['Scale'].default_value = 4.0
    mp2 = nt.nodes.new('ShaderNodeMapping'); mp2.location = (-400, -200)
    mp2.inputs['Scale'].default_value = (32, 32, 1)
    nt.links.new(tc.outputs['UV'], mp2.inputs['Vector'])
    nt.links.new(mp2.outputs[0], chk2.inputs['Vector'])

    mix = nt.nodes.new('ShaderNodeMixRGB'); mix.blend_type = 'MULTIPLY'
    mix.location = (200, 0)
    mix.inputs['Fac'].default_value = 0.3
    nt.links.new(chk.outputs['Color'], mix.inputs[1])
    nt.links.new(chk2.outputs['Color'], mix.inputs[2])
    nt.links.new(mix.outputs[0], bsdf.inputs['Base Color'])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m


def apply_uv_checker_to_scene(scene):
    """Replace all mesh objects' materials with the UV checker. Returns a
    dict of (object_name → original_materials_list) so you can restore."""
    uv_check = make_uv_check_material()
    saved = {}
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue
        saved[obj.name] = list(obj.data.materials)
        obj.data.materials.clear()
        obj.data.materials.append(uv_check)
    return saved


def restore_materials(saved):
    """Restore materials previously saved by apply_uv_checker_to_scene()."""
    for name, mats in saved.items():
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue
        obj.data.materials.clear()
        for m in mats:
            obj.data.materials.append(m)


# =============================================================================
# 4) Convenience: the full stylized pipeline
# =============================================================================

def apply_full_stylized_pipeline(scene, materials=None,
                                  position_th=(0.05, 0.10),
                                  normal_th=(0.10, 0.20),
                                  line_strength=1.0,
                                  use_angle_color=True,
                                  light_factor=1.20,
                                  dark_factor=0.55):
    """One-call setup: directional shading on each non-emission material,
    plus the angle-colored Sobel compositor."""
    if materials is None:
        materials = [m for m in bpy.data.materials
                     if m.use_nodes and not _is_emission_only(m)]

    for mat in materials:
        add_directional_shading(mat, light_factor=light_factor, dark_factor=dark_factor)

    setup_sobel_compositor(scene,
                            position_th=position_th,
                            normal_th=normal_th,
                            line_strength=line_strength,
                            use_angle_color=use_angle_color)


def _is_emission_only(mat):
    """True if material's only shader is an Emission (no Principled BSDF)."""
    if not mat.use_nodes:
        return False
    has_em = any(n.type == 'EMISSION' for n in mat.node_tree.nodes)
    has_bsdf = any(n.type == 'BSDF_PRINCIPLED' for n in mat.node_tree.nodes)
    return has_em and not has_bsdf


# =============================================================================
# 5) Bake edges into per-object texture (alternative to compositor)
# =============================================================================

def smart_unwrap(obj, island_margin=0.04, angle_limit=66.0):
    """Smart UV unwrap a single object. Note: smart_project rotates islands
    for tight packing — the pixel grid won't be axis-aligned with the surface.
    For pixel-art that aligns to world XYZ, use cube_unwrap_axis_aligned() instead."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name='UVMap')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=island_margin, angle_limit=angle_limit)
    bpy.ops.object.mode_set(mode='OBJECT')


def cube_unwrap_axis_aligned(obj):
    """Cube-project the object's UVs (each face's UVs aligned with world XYZ),
    then renormalize so the resulting UVs fill [0,1] with aspect preserved.

    Use this for pixel-art baking — the UV grid stays axis-aligned with the
    object's surfaces (horizontal world edges → horizontal pixel rows etc.)
    instead of being rotated for packing efficiency.
    """
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name='UVMap')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Renormalize UVs to fill [0,1] with aspect preserved (uniform scale)
    me = obj.data
    uv = me.uv_layers.active
    if uv:
        u_lo = min(uv.data[li].uv[0] for poly in me.polygons for li in poly.loop_indices)
        u_hi = max(uv.data[li].uv[0] for poly in me.polygons for li in poly.loop_indices)
        v_lo = min(uv.data[li].uv[1] for poly in me.polygons for li in poly.loop_indices)
        v_hi = max(uv.data[li].uv[1] for poly in me.polygons for li in poly.loop_indices)
        max_span = max((u_hi - u_lo) or 1.0, (v_hi - v_lo) or 1.0)
        for poly in me.polygons:
            for li in poly.loop_indices:
                u, v = uv.data[li].uv
                uv.data[li].uv = ((u - u_lo) / max_span, (v - v_lo) / max_span)


def texture_size_for_world_extent(obj, texels_per_unit=24,
                                    min_size=32, max_size=256, snap=8):
    """Compute an appropriate bake-image resolution for an object based on its
    world-space size, so all parts have a consistent texels-per-world-unit.

    A 1m chair part at texels_per_unit=24 → ~24px texture; a 4m wall → ~96px.
    Snapping to a multiple of `snap` keeps sizes tidy.

    Returns the integer image size (width = height).
    """
    from mathutils import Vector
    M = obj.matrix_world
    bbox_world = [M @ Vector(c) for c in obj.bound_box]
    xs = [v.x for v in bbox_world]
    ys = [v.y for v in bbox_world]
    zs = [v.z for v in bbox_world]
    dims = sorted([max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs)], reverse=True)
    surface_extent = dims[0] + dims[1]   # rough sum of two main axes
    target_size = int(round(surface_extent * texels_per_unit))
    target_size = max(min_size, min(max_size, target_size))
    target_size = ((target_size + snap - 1) // snap) * snap
    return target_size


def rasterize_edges_to_image(obj, image, sharp_angle_deg=20.0, line_thickness=1,
                              color_mode='black', invert_for_multiply=False):
    """Draw crisp lines on `image` along every "sharp" mesh edge of `obj`.

    For each mesh edge:
      - If it's a boundary (only 1 adjacent face) → always draw (silhouette).
      - Else if angle between adjacent face normals > sharp_angle_deg → draw.
    The edge's UV coordinates in each adjacent face are turned into image
    pixel positions via Bresenham's line algorithm. Image is initialized to
    white; lines are drawn in the chosen color.

    Use *after* smart_unwrap() so each face has its own UV island.

    line_thickness: 1 = pixel-thin, 2 = 3×3 stamp, 3 = 5×5 stamp.

    color_mode:
      'black'     — all lines pure black. Multiply with base color in shader
                    gives a clean inked outline.
      'direction' — RGB color = abs(world-space edge direction). X-aligned
                    edges read red, Y green, Z blue, diagonals mix. Used in
                    shader with MULTIPLY for tinted darkening, or MIX to
                    overwrite base with hue.
      'normal'    — RGB color = average adjacent face normal mapped from
                    [-1,1] to [0,1]. Highlights face-direction at the edge.

    invert_for_multiply:
      If True, write (1-R, 1-G, 1-B) to the line pixels. With shader
      MULTIPLY, this *tints* the base color toward the edge direction
      instead of darkening into black-ish on multiply. Try if the colored
      lines look too dark after multiplying.
    """
    import bmesh
    import math
    from mathutils import Vector
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.active
    if uv_layer is None:
        bm.free()
        return 0
    W, H = image.size
    pixels = [1.0] * (W * H * 4)
    sharp_threshold = math.radians(sharp_angle_deg)
    world_matrix = obj.matrix_world.to_3x3()

    segments = []
    for edge in bm.edges:
        if len(edge.link_faces) == 0:
            continue
        if len(edge.link_faces) == 1:
            sharp = True   # silhouette boundary
        else:
            try:
                angle = edge.link_faces[0].normal.angle(edge.link_faces[1].normal)
            except ValueError:
                angle = 0
            sharp = angle > sharp_threshold
        if not sharp:
            continue

        v1, v2 = edge.verts
        # Compute per-edge color
        if color_mode == 'black':
            color = (0.0, 0.0, 0.0)
        elif color_mode == 'direction':
            local_dir = (v2.co - v1.co).normalized()
            world_dir = (world_matrix @ local_dir).normalized()
            color = (abs(world_dir.x), abs(world_dir.y), abs(world_dir.z))
        elif color_mode == 'normal':
            n = Vector((0, 0, 0))
            for f in edge.link_faces: n += f.normal
            n = (world_matrix @ n).normalized() if n.length > 0 else Vector((0, 0, 1))
            color = ((n.x + 1) / 2, (n.y + 1) / 2, (n.z + 1) / 2)
        else:
            color = (0.0, 0.0, 0.0)

        if invert_for_multiply:
            color = (1.0 - color[0], 1.0 - color[1], 1.0 - color[2])

        for face in edge.link_faces:
            uv1 = uv2 = None
            for loop in face.loops:
                if loop.vert == v1:   uv1 = loop[uv_layer].uv.copy()
                elif loop.vert == v2: uv2 = loop[uv_layer].uv.copy()
            if uv1 is not None and uv2 is not None:
                segments.append((uv1, uv2, color))
    bm.free()

    def set_pixel(x, y, color):
        if 0 <= x < W and 0 <= y < H:
            idx = (y * W + x) * 4
            pixels[idx]   = color[0]
            pixels[idx+1] = color[1]
            pixels[idx+2] = color[2]

    def draw_line(uv_a, uv_b, color):
        x0 = int(round(uv_a.x * (W - 1)))
        y0 = int(round(uv_a.y * (H - 1)))
        x1 = int(round(uv_b.x * (W - 1)))
        y1 = int(round(uv_b.y * (H - 1)))
        dx = abs(x1 - x0); dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            for ox in range(-(line_thickness // 2), line_thickness // 2 + 1):
                for oy in range(-(line_thickness // 2), line_thickness // 2 + 1):
                    set_pixel(x0 + ox, y0 + oy, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy: err -= dy; x0 += sx
            if e2 < dx:  err += dx; y0 += sy

    for uv1, uv2, color in segments:
        draw_line(uv1, uv2, color)
    image.pixels = pixels
    image.update()
    return len(segments)


def bake_edges_via_rasterization(objects, image_size=None,
                                  image_name_prefix='BakedEdges_',
                                  sharp_angle_deg=20.0,
                                  line_thickness=1,
                                  color_mode='direction',
                                  axis_aligned=True,
                                  texels_per_unit=24,
                                  save_dir=None):
    """For each object, unwrap and rasterize sharp edges directly into a
    texture. Faster and crisper than Pointiness baking — no Cycles bake step
    needed. Returns dict {obj_name: image}.

    image_size: if None (default), each object gets a per-object size computed
                from its world bounding box * texels_per_unit. This keeps the
                texel density CONSISTENT across all parts (small parts get
                small textures, big parts get big ones). Pass an int to force
                a single uniform size.

    axis_aligned: if True (default), uses cube_unwrap_axis_aligned() so the
                  UV grid lines up with world XYZ — pixel rows are horizontal
                  on horizontal surfaces. If False, uses smart_project (which
                  rotates islands for packing).

    texels_per_unit: target texel density (pixels per 1 unit world space).
                     Only used when image_size=None. Higher = more detail.
    """
    baked = {}
    for obj in objects:
        if obj.type != 'MESH':
            continue
        if axis_aligned:
            cube_unwrap_axis_aligned(obj)
        else:
            smart_unwrap(obj)

        # Per-object size
        size = (image_size if image_size is not None
                else texture_size_for_world_extent(obj, texels_per_unit=texels_per_unit))

        img_name = f'{image_name_prefix}{obj.name}'
        if img_name in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[img_name])
        img = bpy.data.images.new(img_name, size, size, alpha=False)
        img.generated_color = (1, 1, 1, 1)
        baked[obj.name] = img
        n = rasterize_edges_to_image(obj, img,
                                       sharp_angle_deg=sharp_angle_deg,
                                       line_thickness=line_thickness,
                                       color_mode=color_mode)
        if save_dir is not None:
            import os
            os.makedirs(save_dir, exist_ok=True)
            img.filepath_raw = os.path.join(save_dir, img_name + '.png')
            img.file_format = 'PNG'
            img.save()
    return baked


def make_pointiness_bake_material(name, target_image,
                                    threshold_low=0.40, threshold_high=0.55):
    """Material that outputs a Pointiness-based edge mask via Emission, with
    the target image set as the active texture node (required for baking).

    threshold_low/high: ColorRamp positions. Wider range (e.g. 0.40, 0.55)
    catches more edges; narrower (0.50, 0.65) only the sharpest convex corners.
    """
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name])
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (700, 0)
    geo = nt.nodes.new('ShaderNodeNewGeometry'); geo.location = (-700, 0)
    cr = nt.nodes.new('ShaderNodeValToRGB'); cr.location = (-450, 0)
    cr.color_ramp.elements[0].position = threshold_low
    cr.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
    cr.color_ramp.elements[1].position = threshold_high
    cr.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
    nt.links.new(geo.outputs['Pointiness'], cr.inputs['Fac'])
    em = nt.nodes.new('ShaderNodeEmission'); em.location = (-100, 0)
    em.inputs['Strength'].default_value = 1.0
    nt.links.new(cr.outputs['Color'], em.inputs['Color'])
    nt.links.new(em.outputs[0], out.inputs[0])
    # Image texture node — must be active and selected for Cycles to bake to it
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.location = (-100, -300)
    tex.image = target_image
    for n in nt.nodes: n.select = False
    tex.select = True
    nt.nodes.active = tex
    return m, tex


def bake_edges_per_object(objects, image_size=256,
                           image_name_prefix='BakedEdges_',
                           threshold_low=0.40, threshold_high=0.55,
                           save_dir=None):
    """For each object, smart-unwrap, create a target image, bake pointiness
    edges into it. Returns a dict {obj_name: image} of bake results.

    save_dir: if set, saves each baked PNG to this directory.
    """
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.bake_type = 'EMIT'
    bpy.context.scene.cycles.samples = 16
    bpy.context.scene.render.bake.use_clear = True
    bpy.context.scene.render.bake.margin = 4

    saved_materials = {}
    baked = {}

    for obj in objects:
        if obj.type != 'MESH':
            continue

        # 1. Save originals, smart unwrap
        saved_materials[obj.name] = list(obj.data.materials)
        smart_unwrap(obj)

        # 2. Create bake target
        img_name = f'{image_name_prefix}{obj.name}'
        if img_name in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[img_name])
        img = bpy.data.images.new(img_name, image_size, image_size, alpha=False)
        img.generated_color = (1, 1, 1, 1)
        baked[obj.name] = img

        # 3. Apply bake material
        bake_mat, tex_node = make_pointiness_bake_material(
            f'BakeMat_{obj.name}', img,
            threshold_low=threshold_low, threshold_high=threshold_high)
        obj.data.materials.clear()
        obj.data.materials.append(bake_mat)

        # 4. Bake
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for n in bake_mat.node_tree.nodes: n.select = False
        tex_node.select = True
        bake_mat.node_tree.nodes.active = tex_node
        try:
            bpy.ops.object.bake(type='EMIT')
        except Exception as e:
            print(f"Bake failed for {obj.name}: {e}")

        # 5. Save image
        if save_dir is not None:
            import os
            os.makedirs(save_dir, exist_ok=True)
            img.filepath_raw = os.path.join(save_dir, img_name + '.png')
            img.file_format = 'PNG'
            img.save()

    # 6. Restore original materials (caller can rebuild materials using
    #    the baked images however they want)
    for obj in objects:
        if obj.name in saved_materials:
            obj.data.materials.clear()
            for m in saved_materials[obj.name]:
                obj.data.materials.append(m)

    return baked


def make_baked_edge_material(name, base_color, edge_image,
                              roughness=0.85, metallic=0.25,
                              with_directional=True,
                              light_factor=1.40, dark_factor=0.55):
    """Build a final material that combines:
      - solid base_color (RGB tuple)
      - baked edge_image (multiplied — black where edges)
      - directional shading (top-facing brighter, optional)

    Use after bake_edges_per_object() with the returned image dict.
    """
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name])
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)

    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (1000, 0)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location = (700, 0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic

    base_node = nt.nodes.new('ShaderNodeRGB'); base_node.location = (-400, 200)
    base_node.outputs['Color'].default_value = base_color

    edge_tex = nt.nodes.new('ShaderNodeTexImage'); edge_tex.location = (-400, -100)
    edge_tex.image = edge_image
    edge_tex.interpolation = 'Linear'
    edge_tex.extension = 'CLIP'

    # Multiply base * edge_mask
    mul1 = nt.nodes.new('ShaderNodeMix'); mul1.data_type = 'RGBA'
    mul1.blend_type = 'MULTIPLY'; mul1.clamp_factor = True
    mul1.location = (0, 0)
    mul1.inputs['Factor'].default_value = 1.0
    nt.links.new(base_node.outputs['Color'], mul1.inputs[6])
    nt.links.new(edge_tex.outputs['Color'], mul1.inputs[7])

    final_color = mul1.outputs[2]

    if with_directional:
        # Directional factor
        geo = nt.nodes.new('ShaderNodeNewGeometry'); geo.location = (0, -400)
        sep = nt.nodes.new('ShaderNodeSeparateXYZ'); sep.location = (200, -400)
        nt.links.new(geo.outputs['Normal'], sep.inputs[0])
        mr = nt.nodes.new('ShaderNodeMapRange'); mr.location = (350, -400)
        mr.inputs['From Min'].default_value = -1.0
        mr.inputs['From Max'].default_value = 1.0
        mr.inputs['To Min'].default_value = dark_factor
        mr.inputs['To Max'].default_value = light_factor
        nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
        comb = nt.nodes.new('ShaderNodeCombineColor'); comb.location = (500, -400)
        if hasattr(comb, 'mode'): comb.mode = 'RGB'
        nt.links.new(mr.outputs['Result'], comb.inputs[0])
        nt.links.new(mr.outputs['Result'], comb.inputs[1])
        nt.links.new(mr.outputs['Result'], comb.inputs[2])
        # Multiply (base*edge) * directional
        mul2 = nt.nodes.new('ShaderNodeMix'); mul2.data_type = 'RGBA'
        mul2.blend_type = 'MULTIPLY'; mul2.clamp_factor = True
        mul2.location = (400, 0)
        mul2.inputs['Factor'].default_value = 1.0
        nt.links.new(mul1.outputs[2], mul2.inputs[6])
        nt.links.new(comb.outputs[0], mul2.inputs[7])
        final_color = mul2.outputs[2]

    nt.links.new(final_color, bsdf.inputs['Base Color'])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m
