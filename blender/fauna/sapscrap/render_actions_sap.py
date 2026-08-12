"""Render key poses from each Ferrule action so the motion can be eyeballed."""
import bpy
import math
import os
from mathutils import Vector

OUT = r"C:/Users/quest/AppData/Local/Temp/claude/c--Users-quest-Programming-Games-ToRustAsWeFall/18c1e86c-18aa-4699-8d3a-19dc6c3242a3/scratchpad/actions_sap"
os.makedirs(OUT, exist_ok=True)

POSES = {
    "Sapscrap_Idle": [1, 16, 48],
    "Sapscrap_Windup": [1, 9, 16],
    "Sapscrap_Lunge": [1, 5, 9, 18],
    "Sapscrap_Bite": [1, 4, 8, 20],
}

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 560
scene.render.film_transparent = True
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.93, 0.91, 0.88, 1.0)
bg.inputs[1].default_value = 0.30

for n in ("Cam", "Key", "Fill", "Ground"):
    o = bpy.data.objects.get(n)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        v = o.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z)))
        hi = Vector((max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z)))
center = (lo + hi) * 0.5
span = max((hi - lo).x, (hi - lo).y, (hi - lo).z)

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = span * 1.55
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
d = Vector((1.0, 0.0, 0.16)).normalized()      # pure side, slight lift
cam.location = center + d * span * 3
cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

key = bpy.data.lights.new("Key", type="SUN")
key.energy = 4.4
ko = bpy.data.objects.new("Key", key)
scene.collection.objects.link(ko)
ko.rotation_euler = (math.radians(54), 0, math.radians(40))
fill = bpy.data.lights.new("Fill", type="SUN")
fill.energy = 0.7
fo = bpy.data.objects.new("Fill", fill)
scene.collection.objects.link(fo)
fo.rotation_euler = (math.radians(66), 0, math.radians(-120))



rig = bpy.data.objects["Sapscrap_Rig"]
if rig.animation_data is None:
    rig.animation_data_create()

written = []
for action_name, frames in POSES.items():
    act = bpy.data.actions[action_name]
    rig.animation_data.action = act
    # Blender 5.x action slots: without an explicit slot the action can
    # silently not evaluate and every frame renders the rest pose.
    if hasattr(act, "slots") and len(act.slots):
        rig.animation_data.action_slot = act.slots[0]
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        path = os.path.join(OUT, "%s_%02d.png" % (action_name.replace("Sapscrap_", "").lower(), f))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        written.append(os.path.basename(path))

rig.animation_data.action = None
result = {"written": written}
