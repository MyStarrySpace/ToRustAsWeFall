"""Render full animation frame sequences for the live creature.

Reads ANIM_CONFIG from a sidecar json (rig name, actions with frame ranges and
step, output dir). Side-view ortho camera, transparent background, 640px.
"""
import bpy
import json
import math
import os
from mathutils import Vector

CFG = json.load(open(os.path.join(os.path.dirname(__file__) if "__file__" in dir() else
                     "c:/Users/quest/Programming/Games/ToRustAsWeFall/blender/fauna/sapscrap",
                     "anim_config.json")))

OUT = CFG["out"]
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
scene.render.resolution_y = 448
scene.render.film_transparent = True

for o in list(bpy.data.objects):
    if o.type in {"CAMERA", "LIGHT"} or o.name.startswith("Ground"):
        bpy.data.objects.remove(o, do_unlink=True)


def _animated_envelope(rig, sweeps, meshes):
    """World bbox across ALL animated frames - fitting the camera to the
    REST pose clipped the C coil at the frame top and let the tail whip
    leave a sliver-streak at the frame edge."""
    dg = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for act_name, frames in sweeps:
        act = bpy.data.actions.get(act_name)
        if act is None:
            continue
        rig.animation_data.action = act
        if hasattr(act, "slots") and len(act.slots):
            rig.animation_data.action_slot = act.slots[0]
        for f in frames:
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            for o in meshes:
                ev = o.evaluated_get(dg)
                for c in ev.bound_box:
                    v = ev.matrix_world @ Vector(c)
                    lo = Vector((min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z)))
                    hi = Vector((max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z)))
    rig.animation_data.action = None
    return lo, hi

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
_rig_fit = bpy.data.objects[CFG["rig"]]
if _rig_fit.animation_data is None:
    _rig_fit.animation_data_create()
lo, hi = _animated_envelope(_rig_fit, [
    (a["name"], range(a["start"], a["end"] + 1))
    for a in CFG["actions"]
], meshes)
center = (lo + hi) * 0.5
span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(
    span * CFG.get("envelope_margin", 1.12),
    (hi.z - lo.z) * CFG.get("envelope_margin", 1.12)
    * (scene.render.resolution_x / scene.render.resolution_y))
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
az = math.radians(CFG.get("azimuth", 78))
el = math.radians(CFG.get("elevation", 12))
d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
cam.location = center + d * span * 3
cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

key = bpy.data.lights.new("Key", type="SUN")
key.energy = 4.6
ko = bpy.data.objects.new("Key", key)
scene.collection.objects.link(ko)
ko.rotation_euler = (math.radians(52), 0, math.radians(38))
fill = bpy.data.lights.new("Fill", type="SUN")
fill.energy = 0.8
fo = bpy.data.objects.new("Fill", fill)
scene.collection.objects.link(fo)
fo.rotation_euler = (math.radians(66), 0, math.radians(-125))

rig = bpy.data.objects[CFG["rig"]]
if rig.animation_data is None:
    rig.animation_data_create()

written = 0
for act_cfg in CFG["actions"]:
    act = bpy.data.actions[act_cfg["name"]]
    rig.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots):
        rig.animation_data.action_slot = act.slots[0]
    short = act_cfg["short"]
    for f in range(act_cfg["start"], act_cfg["end"] + 1, act_cfg.get("step", 1)):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT, "%s_%03d.png" % (short, f))
        bpy.ops.render.render(write_still=True)
        written += 1

rig.animation_data.action = None
result = {"written": written, "out": OUT}
