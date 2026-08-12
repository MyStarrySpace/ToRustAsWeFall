"""
Shared helpers for the BUILDING-GENERATION skill.

Deterministic, faceted, LOD-aware primitives every generator in this skill can reuse.
Generators may stay self-contained OR import this (the channels pattern):
    import sys; sys.path.insert(0, r"...\\blender\\skills\\building-generation"); import helpers as H

Rules baked in:
- Determinism: use h01()/vary() (hashes of an index), never randf()/wall-clock -> replayable, seedable.
- Faceted low-poly: finish() sets use_smooth=False.
- LOD: every generator ships a NEAR (real mesh) and a FAR (flat plane + texture impostor).
- EEVEE-Next alpha: set flags via alpha_flags() (blend_method was removed in 4.2+; use surface_render_method).
"""
import bpy, bmesh, math
from mathutils import Vector
TAU = math.tau

# ---- deterministic randomness (index -> [0,1)); NEVER randf ----
def h01(n): return (math.sin(n * 127.13) * 43758.5453) % 1.0
def vary(i, salt=0.0): return h01(i * 12.9898 + salt * 78.233)
def smooth(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def lerp(a, b, t): return a + (b - a) * t

# ---- mesh finishing ----
def finish(bm, name, mat=None, faceted=True):
    me = bpy.data.meshes.new(name); bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    if faceted:
        for p in me.polygons: p.use_smooth = False
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    if mat: o.data.materials.append(mat)
    return o

def wipe():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras,
              bpy.data.worlds, bpy.data.metaballs, bpy.data.images, bpy.data.curves):
        for it in list(c):
            try: c.remove(it)
            except Exception: pass

# ---- materials ----
def matp(name, col, rough=0.78, metal=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    return m

def alpha_flags(m):
    """Make a material do alpha CLIP across Blender versions (blend_method removed in 4.2+ EEVEE-Next)."""
    for attr, val in (('blend_method', 'CLIP'), ('surface_render_method', 'DITHERED'), ('shadow_method', 'CLIP')):
        try: setattr(m, attr, val)
        except Exception: pass

# ---- demo scaffolding (world / light / camera / render) ----
def demo_env(bg=(0.05, 0.055, 0.07), strength=0.6):
    w = bpy.data.worlds.new("W"); bpy.context.scene.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (bg[0], bg[1], bg[2], 1.0)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = strength

def demo_sun(loc, tgt, energy):
    l = bpy.data.lights.new("S", 'SUN'); l.energy = energy
    o = bpy.data.objects.new("S", l); bpy.context.scene.collection.objects.link(o)
    o.location = loc; o.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o

def demo_cam(loc, tgt, lens=42):
    cam = bpy.data.cameras.new("C"); cam.lens = lens
    o = bpy.data.objects.new("C", cam); bpy.context.scene.collection.objects.link(o)
    o.location = loc; o.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = o; return o

def demo_render(path, w=1500, h=640):
    sc = bpy.context.scene
    try: sc.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError: sc.render.engine = 'CYCLES'
    sc.render.resolution_x = w; sc.render.resolution_y = h; sc.render.image_settings.file_format = 'PNG'
    try: sc.view_settings.view_transform = 'AgX'
    except Exception: pass
    sc.render.filepath = path; bpy.ops.render.render(write_still=True)
