"""Silhouette gates for the Ferrule actions (run with SYSTEM python).

Renders key frames through the live Blender session with ONE fixed side
camera (fit at rest, wide margin, no ground - re-fitting per frame or a floor
in the alpha saturates the bbox and every ratio reads 1.00), then measures
alpha bounding boxes with PIL and asserts the MOTION of the state machine:

  compress : the perch must RAISE the silhouette and HOLD it (the tell)
  spring   : starts from the perch, stays high mid-flight, then the TOP of
             the silhouette DESCENDS onto the landing (strike from above)
  latch    : recovers to the rest silhouette

Pixel-diff guards pass on any motion including the wrong one; only ratio
gates caught the perch that dug downward instead of rearing.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "skills", "creature-pipeline"))
import blend
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "gates_fer")
RIG = "Ferrule_Rig"

FRAMES = [  # (action, frame, tag)
    ("Ferrule_Idle", 1, "rest"),
    ("Ferrule_Compress", 1, "c1"),
    ("Ferrule_Compress", 14, "c14"),
    ("Ferrule_Compress", 18, "c18"),
    ("Ferrule_Spring", 1, "s1"),
    ("Ferrule_Spring", 8, "s8"),
    ("Ferrule_Spring", 12, "s12"),
    ("Ferrule_Spring", 19, "s19"),
    ("Ferrule_Latch", 1, "t1"),
    ("Ferrule_Latch", 22, "t22"),
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
d = Vector((1.0, -0.12, 0.12)).normalized()   # true side: body runs along Y
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
            "top": y0, "bot": y1}


r = blend.call(RENDER % {"out": OUT, "rig": RIG, "frames": FRAMES})
if r.get("status") != "ok":
    raise SystemExit("render failed: %s" % r.get("message"))

b = {tag: alpha_box(tag) for _, _, tag in FRAMES}
rest = b["rest"]

checks = {
    # compress: the C coil REARS the silhouette up, GATHERS the footprint
    # back, and HOLDS
    "compress_raise": b["c18"]["h"] / b["c1"]["h"] >= 1.50,
    "compress_gathers": b["c18"]["w"] / rest["w"] <= 0.90,
    "compress_holds": abs(b["c18"]["h"] - b["c14"]["h"]) <= 0.03 * rest["h"],
    # spring: chained start == the held perch
    "spring_chains": abs(b["s1"]["h"] - b["c18"]["h"]) <= 0.06 * rest["h"],
    # strike from ABOVE: still high mid-flight, then the top descends.
    # Measured as a RETENTION RATIO of the perch raise (>= 70 percent at
    # f8) so the gate survives perch retuning - an absolute pixel allowance
    # broke the moment the director deepened the coil. Demanding much more
    # than ~70 forces a fully-reared forward glide: the raise lives in the
    # antisymmetric pitches, and the forward throw must blend some out.
    "spring_stays_high": (rest["top"] - b["s8"]["top"])
                         >= 0.70 * (rest["top"] - b["s1"]["top"]),
    "spring_descends": (b["s12"]["top"] - b["s8"]["top"]) >= 0.10 * rest["h"],
    # landed extended: longer than at rest
    "spring_extends": b["s19"]["w"] / rest["w"] >= 1.06,
    # landed ON the ground, not through it
    "spring_lands_on_ground": b["s19"]["bot"] <= rest["bot"] + 0.06 * rest["h"],
    # latch: seizes from the landed pose, recovers to rest
    "latch_chains": abs(b["t1"]["h"] - b["s19"]["h"]) <= 0.06 * rest["h"],
    "latch_recovers": abs(b["t22"]["h"] - rest["h"]) <= 0.08 * rest["h"],
}

report = {"boxes": {k: {kk: round(vv, 1) for kk, vv in v.items()}
                    for k, v in b.items()},
          "checks": checks, "passed": all(checks.values())}
print(json.dumps(report, indent=1))
if not report["passed"]:
    sys.exit(1)
