"""Save the Ferrule master and export it game-ready beside its paint sheets."""
import bpy
import json
import os

MASTER = "c:/Users/quest/Programming/Games/ToRustAsWeFall/blender/fauna/ferrule/ferrule_v3.blend"
OUT_DIR = "c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/resources/models/fauna/ferrule_v3"
ROOT_NAME = "FerruleRoot"
REQUIRED_ACTIONS = {"Ferrule_Idle", "Ferrule_Compress", "Ferrule_Spring", "Ferrule_Latch"}


def descendants(root):
    out, pending = [root], list(root.children)
    while pending:
        c = pending.pop(0)
        out.append(c)
        pending.extend(c.children)
    return out


for name in ("Ground", "Cam", "Key", "Fill"):
    o = bpy.data.objects.get(name)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.wm.save_as_mainfile(filepath=MASTER, copy=True)

root = bpy.data.objects.get(ROOT_NAME)
if root is None:
    raise SystemExit("missing export root")
export_objects = descendants(root)
mesh_objects = [o for o in export_objects if o.type == "MESH"]
for o in mesh_objects:
    if not o.data.uv_layers or len(o.data.uv_layers.active.data) == 0:
        raise SystemExit("mesh has no UVs: %s" % o.name)

missing = REQUIRED_ACTIONS - {a.name for a in bpy.data.actions}
if missing:
    raise SystemExit("missing actions: %s" % sorted(missing))

os.makedirs(OUT_DIR, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for o in export_objects:
    o.hide_set(False)
    o.select_set(True)
bpy.context.view_layer.objects.active = root

out_path = os.path.join(OUT_DIR, "ferrule.gltf")
bpy.ops.export_scene.gltf(
    filepath=out_path,
    check_existing=False,
    export_format="GLTF_SEPARATE",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_texcoords=True,
    export_normals=True,
    export_tangents=False,
    export_materials="EXPORT",
    export_image_format="AUTO",
    export_keep_originals=True,
    export_skins=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_cameras=False,
    export_lights=False,
)

with open(out_path, "r", encoding="utf-8") as fh:
    doc = json.load(fh)

acc = doc["accessors"]
lo = [1e9] * 3
hi = [-1e9] * 3
for m in doc["meshes"]:
    for p in m["primitives"]:
        a = acc[p["attributes"]["POSITION"]]
        if "min" in a:
            for k in range(3):
                lo[k] = min(lo[k], a["min"][k])
                hi[k] = max(hi[k], a["max"][k])

result = {
    "path": out_path,
    "meshes": len(doc.get("meshes", [])),
    "materials": [m.get("name") for m in doc.get("materials", [])],
    "animations": sorted(a.get("name") for a in doc.get("animations", [])),
    "skins": len(doc.get("skins", [])),
    "images": sorted(i.get("uri") for i in doc.get("images", [])),
    "buffer_uri": doc["buffers"][0].get("uri"),
    "non_opaque": [m.get("name") for m in doc.get("materials", [])
                   if m.get("alphaMode", "OPAQUE") != "OPAQUE"],
    "gltf_bounds_xyz": [round(hi[k] - lo[k], 3) for k in range(3)],
    "gltf_min": [round(v, 3) for v in lo],
    "gltf_max": [round(v, 3) for v in hi],
}
if result["non_opaque"]:
    raise SystemExit("non-opaque materials exported: %s"
                     % result["non_opaque"])

