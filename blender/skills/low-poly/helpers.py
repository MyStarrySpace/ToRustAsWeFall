"""
Shared helpers for the low-poly Blockbench-style skill.

Use for any low-poly faceted asset — chairs, props, vehicles, buildings, weapons,
furniture. For plants specifically, use the stylized-plant skill which adds
leaf-card / bezier-frond builders on top of these primitives.

Critical lessons baked in:
- Every polygon has use_smooth = False after build (blocky facets, no smoothing).
- 8-sided cylinders by default (not 32). Octagonal lathe for cylindrical things.
- Pixel-art textures with Closest interpolation, packed into the .blend.
- Material count stays small — re-use across the scene.
"""

import bpy, bmesh, math
from mathutils import Vector


# =============================================================================
# Scene setup
# =============================================================================

def wipe_scene():
    """Remove all objects, meshes, materials, etc. for a clean rebuild."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                bpy.data.images, bpy.data.textures, bpy.data.lights,
                bpy.data.cameras, bpy.data.worlds):
        for it in list(blk):
            try: blk.remove(it)
            except: pass
    for c in list(bpy.data.collections):
        if c.name != 'Collection':
            try: bpy.data.collections.remove(c)
            except: pass


def setup_world(bg_color=(0.04, 0.05, 0.08, 1.0), strength=0.5):
    """Set the world background (default: dark moody)."""
    w = bpy.data.worlds.new('World')
    bpy.context.scene.world = w
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
    """Create a packed Blender image from a 2D list of (r,g,b,a) pixel tuples."""
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    h = len(grid); w = len(grid[0])
    img = bpy.data.images.new(name, w, h, alpha=alpha)
    pixels = []
    for y in range(h):
        for px in grid[h-1-y]:  # Blender stores rows bottom-to-top
            pixels.extend(px)
    img.pixels = pixels
    img.pack()
    img.update()
    return img


def make_pixel_mat(name, image=None, base_color=(0.5,0.5,0.5,1),
                   transparent=False, roughness=0.85, metallic=0.0,
                   sheen=0.0, sss_weight=0.0,
                   sss_radius=(0.45, 0.75, 0.25), sss_scale=0.08):
    """
    Build a Principled BSDF material.

    If `image` is None, uses a flat base_color. Otherwise uses an Image Texture
    node with Closest interpolation (for pixel-art crispness).
    """
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(900,0)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location=(600,0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = 0.5
    if sheen > 0 and 'Sheen Weight' in bsdf.inputs:
        bsdf.inputs['Sheen Weight'].default_value = sheen
    if sss_weight > 0 and 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = sss_weight
        bsdf.inputs['Subsurface Radius'].default_value = sss_radius
        if 'Subsurface Scale' in bsdf.inputs:
            bsdf.inputs['Subsurface Scale'].default_value = sss_scale

    if image is not None:
        tex = nt.nodes.new('ShaderNodeTexImage'); tex.location=(0,0)
        tex.image = image
        tex.interpolation = 'Closest'
        tex.extension = 'CLIP' if transparent else 'REPEAT'
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        if transparent:
            nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    else:
        bsdf.inputs['Base Color'].default_value = base_color

    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m


def make_emission_mat(name, color=(0.20, 0.55, 1.0, 1.0), strength=18.0):
    """Pure emission material for glow / screens / sci-fi accents."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(300,0)
    em = nt.nodes.new('ShaderNodeEmission'); em.location=(0,0)
    em.inputs['Color'].default_value = color
    em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


# =============================================================================
# Geometry building blocks
# =============================================================================

def add_obj(name, mesh, mat_name=None, faceted=True):
    """Wrap a mesh in an object, link to scene, apply material, enforce flat shading."""
    obj = bpy.data.objects.new(name, mesh); bpy.context.collection.objects.link(obj)
    if mat_name and mat_name in bpy.data.materials:
        obj.data.materials.append(bpy.data.materials[mat_name])
    if faceted:
        for p in mesh.polygons:
            p.use_smooth = False
    return obj


def make_box(name, center, size, mat_name=None):
    """Axis-aligned box. center=(x,y,z), size=(sx,sy,sz)."""
    cx, cy, cz = center
    sx, sy, sz = size
    bm = bmesh.new()
    pts = [
        (cx-sx/2, cy-sy/2, cz-sz/2), (cx+sx/2, cy-sy/2, cz-sz/2),
        (cx+sx/2, cy+sy/2, cz-sz/2), (cx-sx/2, cy+sy/2, cz-sz/2),
        (cx-sx/2, cy-sy/2, cz+sz/2), (cx+sx/2, cy-sy/2, cz+sz/2),
        (cx+sx/2, cy+sy/2, cz+sz/2), (cx-sx/2, cy+sy/2, cz+sz/2),
    ]
    verts = [bm.verts.new(p) for p in pts]
    bm.verts.ensure_lookup_table()
    faces = [
        (0,1,2,3), (7,6,5,4),  # bottom, top
        (0,4,5,1), (1,5,6,2), (2,6,7,3), (3,7,4,0),  # sides
    ]
    for fi in faces:
        bm.faces.new([verts[i] for i in fi])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return add_obj(name, me, mat_name)


def make_tapered_box(name, center, top_size, bot_size, height, mat_name=None):
    """A box where top and bottom have different sizes — for tapered shapes."""
    cx, cy, cz = center
    sx_t, sy_t = top_size
    sx_b, sy_b = bot_size
    bm = bmesh.new()
    pts = [
        (cx-sx_b/2, cy-sy_b/2, cz-height/2), (cx+sx_b/2, cy-sy_b/2, cz-height/2),
        (cx+sx_b/2, cy+sy_b/2, cz-height/2), (cx-sx_b/2, cy+sy_b/2, cz-height/2),
        (cx-sx_t/2, cy-sy_t/2, cz+height/2), (cx+sx_t/2, cy-sy_t/2, cz+height/2),
        (cx+sx_t/2, cy+sy_t/2, cz+height/2), (cx-sx_t/2, cy+sy_t/2, cz+height/2),
    ]
    verts = [bm.verts.new(p) for p in pts]
    bm.verts.ensure_lookup_table()
    for fi in [(0,1,2,3), (7,6,5,4), (0,4,5,1), (1,5,6,2), (2,6,7,3), (3,7,4,0)]:
        bm.faces.new([verts[i] for i in fi])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return add_obj(name, me, mat_name)


def lathe(name, profile, mat_name=None, sides=8):
    """
    Build an axially-symmetric mesh from a profile of (radius, z) tuples.
    The profile is the OUTER WALL only; uses sides verts per ring.

    For a hollow vessel (pot, bowl), pass an inner profile too via lathe_hollow.
    """
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(sides):
            a = i / sides * math.tau
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for j in range(len(rings) - 1):
        for i in range(sides):
            ni = (i + 1) % sides
            bm.faces.new([rings[j][i], rings[j][ni], rings[j+1][ni], rings[j+1][i]])
    # Caps (flip first one so it points down)
    bm.faces.new([rings[0][i] for i in range(sides)][::-1])
    bm.faces.new([rings[-1][i] for i in range(sides)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return add_obj(name, me, mat_name)


def lathe_loft(name, profile, mat_name=None, sides=8, x_scale=1.0, y_scale=1.0):
    """Like lathe but with non-uniform scaling (for elliptical pots/seats)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(sides):
            a = i / sides * math.tau
            ring.append(bm.verts.new((r * x_scale * math.cos(a),
                                      r * y_scale * math.sin(a), z)))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for j in range(len(rings) - 1):
        for i in range(sides):
            ni = (i + 1) % sides
            bm.faces.new([rings[j][i], rings[j][ni], rings[j+1][ni], rings[j+1][i]])
    bm.faces.new([rings[0][i] for i in range(sides)][::-1])
    bm.faces.new([rings[-1][i] for i in range(sides)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    return add_obj(name, me, mat_name)


def make_octagonal_cylinder(name, center, radius, height, mat_name=None, sides=8):
    """Quick capped cylinder via lathe."""
    cx, cy, cz = center
    profile = [(radius, cz - height/2), (radius, cz + height/2)]
    obj = lathe(name, profile, mat_name=mat_name, sides=sides)
    obj.location.x += cx
    obj.location.y += cy
    return obj


def make_floor(name, half_size=5.0, z=0.0, mat_name=None):
    """A flat square floor."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    for x, y in [(-half_size, -half_size), (half_size, -half_size),
                 (half_size, half_size), (-half_size, half_size)]:
        bm.verts.new((x, y, z))
    bm.verts.ensure_lookup_table()
    bm.faces.new(bm.verts)
    bm.to_mesh(me); bm.free()
    return add_obj(name, me, mat_name)


# =============================================================================
# Lights, camera, render
# =============================================================================

def add_area(name, loc, target, energy, size=2.5, color=(1,1,1)):
    bpy.ops.object.light_add(type='AREA', location=loc)
    o = bpy.context.object; o.name = name
    o.data.energy = energy; o.data.size = size; o.data.color = color
    direction = Vector(target) - Vector(loc)
    o.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    return o


def add_point(name, loc, energy, color=(1,1,1), soft=0.4):
    bpy.ops.object.light_add(type='POINT', location=loc)
    o = bpy.context.object; o.name = name
    o.data.energy = energy; o.data.color = color
    o.data.shadow_soft_size = soft
    return o


def setup_three_point(target=(0,0,1), key=350, fill=110, rim=140,
                      key_color=(1.00, 0.96, 0.92),
                      fill_color=(0.85, 0.92, 1.00),
                      rim_color=(1.00, 0.95, 0.85)):
    """Standard 3-point area lighting."""
    add_area('Key',  ( 3.0,-3.0, 4.0), target, key,  2.5, key_color)
    add_area('Fill', (-3.0,-1.5, 3.0), target, fill, 3.0, fill_color)
    add_area('Rim',  (-1.0, 3.0, 3.0), target, rim,  1.5, rim_color)


def setup_camera(loc=(3.0, -3.5, 1.7), target=(0,0,1.2), lens=50):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object; cam.name = 'Camera'; cam.data.lens = lens
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    bpy.context.scene.camera = cam
    return cam


def setup_render(samples=256, w=1600, h=1200, exposure=0.0,
                 view_transform='Filmic', look='Medium High Contrast'):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.image_settings.file_format = 'PNG'
    sc.view_settings.view_transform = view_transform
    sc.view_settings.look = look
    sc.view_settings.exposure = exposure
