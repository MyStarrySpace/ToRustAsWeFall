# Export both halves of the pipeline: game-ready GLTF into resources/, and the
# BlockBench hand-off (one OBJ + MTL + texture per piece) into an area's
# obj-exports/ dir. path_mode COPY carries each material's texture along, so a
# hand-off folder is always self-contained.

import bpy
import os


def all_mesh_children(obs):
    out = []
    for ob in obs:
        if ob.type == "MESH":
            out.append(ob)
        out.extend(all_mesh_children(list(ob.children)))
    return out


def _select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
        for c in all_mesh_children([ob]):
            c.select_set(True)


def export_gltf(objs, path):
    """Game-ready GLTF_SEPARATE (textures emitted beside the gltf) — the runtime
    format under to-rust-as-we-fall/resources/models/."""
    _select(objs)
    kw = dict(filepath=path, export_format="GLTF_SEPARATE", export_yup=True,
              export_apply=True, export_image_format="AUTO")
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    if "use_selection" in props:
        kw["use_selection"] = True
    else:
        kw["export_selected_objects"] = True
    bpy.ops.export_scene.gltf(**kw)
    print("[EXPORT]", path)


def export_obj(objs, path, with_materials=True):
    """One OBJ (+MTL + copied textures) — the BlockBench hand-off, or a
    material-less mesh for prop scenes that supply their own material."""
    _select(objs)
    bpy.ops.wm.obj_export(
        filepath=path, export_selected_objects=True, up_axis="Y",
        forward_axis="NEGATIVE_Z", export_materials=with_materials,
        path_mode="COPY")
    print("[EXPORT]", path)
