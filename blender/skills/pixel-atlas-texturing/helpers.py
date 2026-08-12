"""
helpers.py — reusable bpy snippets for the pixel-atlas-texturing skill.

These run INSIDE Blender (via the Blender Lab MCP socket — see SKILL.md). They are written to be
copy-pasted into a socket `execute` payload, not imported. Every function is pure-bpy and assumes a
live Blender session with the asset already built/imported.

The golden rule of this skill: GEOMETRY is simple flat forms; DETAIL + SHADING are painted into a
low-res pixel-art texture. So most of this file is about UVs, not modeling.
"""

import bpy, bmesh, mathutils


# ----------------------------------------------------------------------------------------------------
# Operator context — UV/mesh operators (smart_project, pack_islands, export_layout, join, mode_set)
# fail with "context is incorrect" when run from a socket/script context. They need a VIEW_3D area.
# Wrap EVERY such operator in op(); pure-data edits (bmesh, mesh.uv_layers) do NOT need it.
# ----------------------------------------------------------------------------------------------------
def view3d():
    for w in bpy.context.window_manager.windows:
        for a in w.screen.areas:
            if a.type == 'VIEW_3D':
                r = next((rr for rr in a.regions if rr.type == 'WINDOW'), None)
                return w, a, r
    return None, None, None

def op(fn, **kw):
    """Run a bpy.ops operator inside a VIEW_3D context override. Returns the operator result."""
    W, A, R = view3d()
    if A:
        with bpy.context.temp_override(window=W, area=A, region=R):
            return fn(**kw)
    return fn(**kw)


# ----------------------------------------------------------------------------------------------------
# Realize Geometry-Nodes / modifiers WITHOUT the modifier_apply operator (no context headaches).
# Needed before UV work, because you can't bake stable UVs onto procedural geometry that regenerates.
# ----------------------------------------------------------------------------------------------------
def realize(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    new_me = bpy.data.meshes.new_from_object(ev)   # GN/modifiers applied
    old = obj.data
    obj.data = new_me
    for md in list(obj.modifiers):
        obj.modifiers.remove(md)
    if old.users == 0:
        bpy.data.meshes.remove(old)


# ----------------------------------------------------------------------------------------------------
# Pure-data cube-projection UVs — uniform texel density, TILING (seamless across pieces in world space).
# Use this for the "tiling pixel texture" style (Crocotile/Blockbench). For a single HAND-PAINTED atlas
# use atlas_unwrap() below instead.
#   TILE = world units per texture tile. TILE = 1.0 -> one tile per unit (= 16 px/unit at a 16px tile).
# ----------------------------------------------------------------------------------------------------
def cube_uv(obj, tile=1.0, world=True):
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    mw = obj.matrix_world if world else mathutils.Matrix.Identity(4)
    nm = mw.to_3x3()
    for poly in me.polygons:
        n = nm @ poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 0:   u, v = co.y, co.z
            elif ax == 1: u, v = co.x, co.z
            else:         u, v = co.x, co.y
            uv[li].uv = (u / tile, v / tile)


# ----------------------------------------------------------------------------------------------------
# THE atlas unwrap. Flat paintable surfaces -> clean unique islands packed into the left ~S of UV space.
# Repetitive metal hardware (bolts/grate/louver/ribs/rails — if they survive as geometry) -> ONE shared
# swatch in the reserved right strip (overlap is fine: the geometry gives the shape, the swatch just
# colors it). Pass the two object lists (split by name/role). Run on SEPARATE objects, BEFORE join.
# ----------------------------------------------------------------------------------------------------
def atlas_unwrap(atlas_objs, metal_objs, S=0.82, box=(0.845, 0.04, 0.99, 0.96)):
    # 1) smart-project the paintable group together into a shared 0-1 layout
    bpy.ops.object.select_all(action='DESELECT')
    for o in atlas_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = atlas_objs[0]
    op(bpy.ops.object.mode_set, mode='EDIT')
    op(bpy.ops.mesh.select_all, action='SELECT')
    op(bpy.ops.uv.smart_project, island_margin=0.006, area_weight=1.0,
       correct_aspect=True, scale_to_bounds=False)
    op(bpy.ops.object.mode_set, mode='OBJECT')
    # 2) shrink that layout into the left/main S square, freeing the right strip
    for o in atlas_objs:
        for d in o.data.uv_layers.active.data:
            d.uv = (d.uv[0] * S, d.uv[1] * S)
    # 3) collapse the hardware onto the shared swatch (per-object normalized into the box; overlap OK)
    for o in metal_objs:
        me = o.data
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        uvl = me.uv_layers.active.data
        cos = [v.co for v in me.vertices]
        mn = mathutils.Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
        mx = mathutils.Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
        ext = [(mx[i] - mn[i]) or 1.0 for i in range(3)]
        for poly in me.polygons:
            n = poly.normal; ax = max(range(3), key=lambda i: abs(n[i]))
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                if ax == 0:   a, b = (co.y - mn.y) / ext[1], (co.z - mn.z) / ext[2]
                elif ax == 1: a, b = (co.x - mn.x) / ext[0], (co.z - mn.z) / ext[2]
                else:         a, b = (co.x - mn.x) / ext[0], (co.y - mn.y) / ext[1]
                uvl[li].uv = (box[0] + (box[2] - box[0]) * a, box[1] + (box[3] - box[1]) * b)


def join_all(meshes, name="Asset"):
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    op(bpy.ops.object.join)
    car = bpy.context.view_layer.objects.active
    car.name = name; car.data.name = name
    return car


# ----------------------------------------------------------------------------------------------------
# Strip over-modeled detail. If you used atlas_unwrap, the hardware lives in the right swatch (UV.x>0.83),
# so this deletes exactly that geometry, leaving the flat shell to be painted. Use BMESH — setting
# poly.select in object mode does NOT reliably carry into edit-mode delete (it can nuke the whole mesh).
# ----------------------------------------------------------------------------------------------------
def strip_faces_by_uv_x(obj, threshold=0.83):
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    to_del = [f for f in bm.faces
              if (sum(l[uvl].uv.x for l in f.loops) / len(f.loops)) > threshold]
    bmesh.ops.delete(bm, geom=to_del, context='FACES')
    bm.to_mesh(me); bm.free()
    return len(me.polygons)


def smart_unwrap_single(obj, island_margin=0.006):
    """Fresh full unwrap of one object (use after stripping, to repack the flat shell into 0-1)."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    if obj.mode != 'OBJECT':
        op(bpy.ops.object.mode_set, mode='OBJECT')
    op(bpy.ops.object.mode_set, mode='EDIT')
    op(bpy.ops.mesh.select_all, action='SELECT')
    op(bpy.ops.uv.smart_project, island_margin=island_margin, area_weight=1.0,
       correct_aspect=True, scale_to_bounds=False)
    op(bpy.ops.object.mode_set, mode='OBJECT')


# ----------------------------------------------------------------------------------------------------
# Exports — OBJ+MTL (for the painter) to the gitignored source dir, GLB (runtime) to resources/,
# and the UV-layout PNG template the artist paints over. SIZE is the LOW-RES pixel target (see SKILL.md).
# ----------------------------------------------------------------------------------------------------
def export_template(obj, path, size=256, opacity=0.7):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    op(bpy.ops.object.mode_set, mode='EDIT')
    op(bpy.ops.mesh.select_all, action='SELECT')
    op(bpy.ops.uv.export_layout, filepath=path, size=(size, size), opacity=opacity, mode='PNG')
    op(bpy.ops.object.mode_set, mode='OBJECT')

def export_obj_glb(obj, obj_path, glb_path):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=True, export_uv=True,
        export_normals=True, export_materials=True, apply_modifiers=True,
        forward_axis='NEGATIVE_Z', up_axis='Y')                       # matches glTF/Godot Y-up
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format='GLB', use_selection=True,
        export_apply=True, export_yup=True, export_cameras=False, export_lights=False,
        export_texcoords=True, export_normals=True)


# ----------------------------------------------------------------------------------------------------
# VERIFY UVs — slap a UV_GRID checker on everything (emission, so lighting can't hide it) and render.
# Uniform SQUARES across a surface = consistent density, no stretching. Stretched rectangles = bad UVs.
# Restore material_override = None afterwards. "Make sure the textures match the UVs" lives here.
# ----------------------------------------------------------------------------------------------------
def uv_checker_setup():
    img = bpy.data.images.get("UVCheck") or bpy.data.images.new("UVCheck", 1024, 1024)
    img.generated_type = 'UV_GRID'; img.source = 'GENERATED'
    mat = bpy.data.materials.get("UVCheckMat") or bpy.data.materials.new("UVCheckMat")
    mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
    tex.interpolation = 'Closest'; tex.extension = 'REPEAT'
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    bpy.context.view_layer.material_override = mat
    bpy.context.scene.view_settings.view_transform = 'Standard'
    return mat
