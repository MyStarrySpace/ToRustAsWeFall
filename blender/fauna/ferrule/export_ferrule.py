"""Repeatably export the saved Ferrule master to the Godot runtime folder.

Run from the repository root:

    blender.exe --background blender/fauna/ferrule/ferrule.blend \
        --python blender/fauna/ferrule/export_ferrule.py

This is deliberately export-only. The editable geometry, rig, materials, UVs,
and animation actions live in ``ferrule.blend``.
"""

import json
from pathlib import Path

import bpy


ROOT_NAME = "FerruleRoot"
REQUIRED_ACTIONS = {
    "Ferrule_Idle",
    "Ferrule_Compress",
    "Ferrule_Spring",
    "Ferrule_Latch",
}
EXPECTED_MESH_COUNT = 17


def descendants(root):
    result = [root]
    pending = list(root.children)
    while pending:
        child = pending.pop(0)
        result.append(child)
        pending.extend(child.children)
    return result


blend_path = Path(bpy.data.filepath).resolve()
if not blend_path.name.lower().endswith(".blend"):
    raise SystemExit("Open ferrule.blend before running export_ferrule.py")

repository_root = blend_path.parents[3]
output_dir = (
    repository_root
    / "to-rust-as-we-fall"
    / "resources"
    / "models"
    / "fauna"
    / "ferrule"
)
output_dir.mkdir(parents=True, exist_ok=True)

root = bpy.data.objects.get(ROOT_NAME)
if root is None:
    raise SystemExit(f"Missing required export root: {ROOT_NAME}")

export_objects = descendants(root)
mesh_objects = [obj for obj in export_objects if obj.type == "MESH"]
if len(mesh_objects) != EXPECTED_MESH_COUNT:
    raise SystemExit(
        f"Expected {EXPECTED_MESH_COUNT} Ferrule meshes, found {len(mesh_objects)}"
    )
for obj in mesh_objects:
    if not obj.data.uv_layers or len(obj.data.uv_layers.active.data) == 0:
        raise SystemExit(f"Mesh has no exportable UV map: {obj.name}")

action_names = {action.name for action in bpy.data.actions}
missing_actions = REQUIRED_ACTIONS - action_names
if missing_actions:
    raise SystemExit(
        "Missing required Ferrule actions: " + ", ".join(sorted(missing_actions))
    )

bpy.ops.object.select_all(action="DESELECT")
for obj in export_objects:
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = root

output_path = output_dir / "ferrule.gltf"
bpy.ops.export_scene.gltf(
    filepath=str(output_path),
    check_existing=False,
    export_format="GLTF_SEPARATE",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_texcoords=True,
    export_normals=True,
    # The asset has no normal maps, so tangent export only adds noise and causes
    # warnings on the intentionally low-poly n-gons.
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

with output_path.open("r", encoding="utf-8") as handle:
    exported = json.load(handle)
non_opaque = [
    material.get("name", "<unnamed>")
    for material in exported.get("materials", [])
    if material.get("alphaMode", "OPAQUE") != "OPAQUE"
]
if non_opaque:
    raise SystemExit(
        "Ferrule materials must export opaque: " + ", ".join(non_opaque)
    )

images = exported.get("images", [])
textures = exported.get("textures", [])
image_index = next(
    (
        index
        for index, image in enumerate(images)
        if image.get("uri") == "ferrule_signal_emissive.png"
    ),
    -1,
)
texture_index = next(
    (
        index
        for index, texture in enumerate(textures)
        if texture.get("source") == image_index
    ),
    -1,
)
signal_material = next(
    (
        material
        for material in exported.get("materials", [])
        if material.get("name") == "FerruleSignal"
    ),
    {},
)
if signal_material.get("emissiveTexture", {}).get("index") != texture_index:
    raise SystemExit("FerruleSignal lost its external emissive texture binding")

print(
    "[FERRULE EXPORT] "
    f"{len(mesh_objects)} meshes, {len(REQUIRED_ACTIONS)} actions -> {output_path}"
)
