"""Silhouette gates for the Sapscrap actions (run with SYSTEM python).

Renders key frames of each action through the live Blender session with ONE
fixed side camera (fit at rest, wide margin, no ground plane - a re-fit per
frame or a floor in the alpha saturates the bbox and every ratio reads 1.00),
then measures alpha bounding boxes with PIL and asserts the MOTION:

  windup : height must SQUASH down, silhouette must shift REARWARD
  lunge  : airborne bottom must RISE mid-flight; landed frame must sit
           FORWARD of the crouch and back near full height
  bite   : final frame must be back at the rest silhouette

The rear direction in image space is CALIBRATED from the windup itself (its
rearward shuffle is a design constant), so no camera-axis guessing.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "skills", "creature-pipeline"))
import blend
from PIL import Image

SCRATCH = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(SCRATCH, "gates_sap")
RIG = "Sapscrap_Rig"

FRAMES = [  # (action, frame, tag)
    ("Sapscrap_Idle", 1, "rest"),
    ("Sapscrap_Windup", 1, "w1"),
    ("Sapscrap_Windup", 18, "w18"),
    ("Sapscrap_Lunge", 1, "l1"),
    ("Sapscrap_Lunge", 7, "l7"),
    ("Sapscrap_Lunge", 13, "l13"),
    ("Sapscrap_Bite", 1, "b1"),
    ("Sapscrap_Bite", 22, "b22"),
]

RENDER = '''
import bpy, math, os
from mathutils import Vector

OUT = %(out)r
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 560
scene.render.resolution_y = 420
scene.render.film_transparent = True

for o in list(bpy.data.objects):
    if o.type in {"CAMERA", "LIGHT"} or o.name.startswith("Ground"):
        bpy.data.objects.remove(o, do_unlink=True)

rig = bpy.data.objects[%(rig)r]
if rig.animation_data is None:
    rig.animation_data_create()
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        v = o.matrix_world @ Vector(c)
        lo = Vector(map(min, lo, v)); hi = Vector(map(max, hi, v))
center = (lo + hi) * 0.5
span = max(hi - lo)

cam_data = bpy.data.cameras.new("GateCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = span * 1.9
cam = bpy.data.objects.new("GateCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
d = Vector((1.0, 0.0, 0.12)).normalized()
cam.location = center + d * span * 3
cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

sun = bpy.data.lights.new("GateSun", type="SUN")
sun.energy = 4.0
so = bpy.data.objects.new("GateSun", sun)
scene.collection.objects.link(so)
so.rotation_euler = (math.radians(55), 0, math.radians(30))

for act_name, frame, tag in %(frames)r:
    act = bpy.data.actions[act_name]
    rig.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots):
        rig.animation_data.action_slot = act.slots[0]
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    scene.render.filepath = os.path.join(OUT, tag + ".png")
    bpy.ops.render.render(write_still=True)
rig.animation_data.action = None
result = {"rendered": len(%(frames)r)}
'''


def alpha_box(tag):
    img = Image.open(os.path.join(OUT, tag + ".png")).convert("RGBA")
    box = img.getchannel("A").getbbox()
    if box is None:
        raise SystemExit("gate: %s renders EMPTY" % tag)
    x0, y0, x1, y1 = box
    return {"h": y1 - y0, "w": x1 - x0, "cx": (x0 + x1) / 2.0,
            "top": y0, "bot": y1, "x0": x0, "x1": x1}


r = blend.call(RENDER % {"out": OUT, "rig": RIG, "frames": FRAMES})
if r.get("status") != "ok":
    raise SystemExit("render failed: %s" % r.get("message"))

b = {tag: alpha_box(tag) for _, _, tag in FRAMES}
rest = b["rest"]

# calibrate: image-x sign of the windup's rearward shuffle
rear_sign = 1.0 if b["w18"]["cx"] > b["w1"]["cx"] else -1.0

checks = {
    # windup: squash >= 10 percent, silhouette shifts rearward
    "windup_squash": b["w18"]["h"] / b["w1"]["h"] <= 0.90,
    "windup_rearward": (b["w18"]["cx"] - b["w1"]["cx"]) * rear_sign
                       >= 0.03 * rest["w"],
    # lunge: chained start == windup's held end (same squashed height)
    "lunge_chains": abs(b["l1"]["h"] - b["w18"]["h"]) <= 0.06 * rest["h"],
    # airborne: the belly leaves the ground
    "lunge_airborne": (b["l1"]["bot"] - b["l7"]["bot"]) >= 0.05 * rest["h"],
    # landed: forward of the crouch by a real jump, and back near height
    "lunge_forward": (b["l1"]["cx"] - b["l13"]["cx"]) * rear_sign
                     >= 0.10 * rest["w"],
    "lunge_unsquash": b["l13"]["h"] / b["l1"]["h"] >= 1.12,
    # bite: recovers to the rest silhouette
    "bite_recover_h": abs(b["b22"]["h"] - rest["h"]) <= 0.08 * rest["h"],
    "bite_recover_x": abs(b["b22"]["cx"] - rest["cx"]) <= 0.06 * rest["w"],
}

report = {"boxes": {k: {kk: round(vv, 1) for kk, vv in v.items()}
                    for k, v in b.items()},
          "rear_sign": rear_sign, "checks": checks,
          "passed": all(checks.values())}
print(json.dumps(report, indent=1))
if not report["passed"]:
    sys.exit(1)
