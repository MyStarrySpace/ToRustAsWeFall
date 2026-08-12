"""Render orthographic Ferrule presentation views without changing the source asset.

Run with Blender 5.1:
  blender --background ferrule.blend --python render_views.py

The helper modifies only the in-memory scene and never saves the .blend or exports geometry.
"""

import math
import os

import bpy
from mathutils import Vector


ASSET_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(ASSET_DIR, "previews")


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def reset_rig_to_rest():
    rig = bpy.data.objects.get("FerruleRig")
    if rig is None:
        raise RuntimeError("FerruleRig was not found in the open blend file")
    if rig.animation_data is not None:
        rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def make_render_collection():
    collection = bpy.data.collections.new("FERRULE_RENDER_ONLY")
    bpy.context.scene.collection.children.link(collection)
    return collection


def link_only(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name, color, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def add_area_light(collection, name, location, energy, size, color, target):
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light_obj = bpy.data.objects.new(name, light_data)
    collection.objects.link(light_obj)
    light_obj.location = location
    point_at(light_obj, target)
    return light_obj


def configure_scene(collection):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = scene.world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.075, 0.08, 0.075, 1.0)
    background.inputs["Strength"].default_value = 0.7

    ground_material = make_material("FerruleRenderGround", (0.16, 0.17, 0.155), 0.93)
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "FerruleRenderGround"
    link_only(ground, collection)
    ground.data.materials.append(ground_material)

    camera_data = bpy.data.cameras.new("FerruleRenderCamera")
    camera_data.type = "ORTHO"
    camera_data.lens = 55.0
    camera = bpy.data.objects.new("FerruleRenderCamera", camera_data)
    collection.objects.link(camera)
    scene.camera = camera

    target = (0.0, 0.0, 0.92)
    add_area_light(collection, "FerruleRenderKey", (-4.5, -4.8, 7.0), 1250.0, 4.5,
                   (0.86, 1.0, 0.72), target)
    add_area_light(collection, "FerruleRenderFill", (5.0, -1.0, 4.0), 780.0, 5.0,
                   (0.58, 0.68, 0.82), target)
    add_area_light(collection, "FerruleRenderRim", (1.0, 5.5, 6.0), 1050.0, 4.0,
                   (1.0, 0.78, 0.42), target)
    return camera


def render_view(camera, name, location, target, ortho_scale):
    camera.location = location
    point_at(camera, target)
    camera.data.ortho_scale = ortho_scale
    bpy.context.scene.render.filepath = os.path.join(OUTPUT_DIR, f"ferrule_{name}.png")
    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED_{name.upper()}={bpy.context.scene.render.filepath}")


def main():
    if os.path.basename(bpy.data.filepath).lower() != "ferrule.blend":
        raise RuntimeError("Open ferrule.blend before running this helper")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    reset_rig_to_rest()
    collection = make_render_collection()
    camera = configure_scene(collection)

    # Blender -Y corresponds to Godot +Z after glTF conversion.
    views = [
        # The seven-part rebuild is a much tighter 3.34 m resting coil than
        # the previous long blockout.  These scales keep every silhouette in
        # frame while using the presentation canvas instead of leaving the
        # model stranded in the center.
        ("front", (0.0, -8.0, 1.05), (0.0, -0.20, 0.88), 2.38),
        ("side", (8.0, 0.0, 1.55), (0.0, -0.68, 0.82), 4.15),
        ("back", (0.0, 8.0, 1.18), (0.0, 0.15, 0.90), 2.45),
        ("three_quarter", (6.2, -7.2, 3.65), (0.0, -0.38, 0.80), 4.10),
    ]
    for name, location, target, scale in views:
        render_view(camera, name, location, target, scale)

    print("FERRULE_VIEWS_COMPLETE")


if __name__ == "__main__":
    main()
