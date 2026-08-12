"""Pixel-probe the maw cavity (run with SYSTEM python).

Renders the live Sapscrap head-on and samples the maw centre's mean RGB. A
face-count guard alone once passed while the gullet rendered PURPLE (a null
material slot after the boolean bake shifted every index), and once while the
bore was carved as an INTERNAL cavity (boolean operand displaced by the root
offset) - only rendered pixels prove the mouth reads as a dark hole.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "skills", "creature-pipeline"))
import blend
from PIL import Image

SCRATCH = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(SCRATCH, "probe_maw.png")

RENDER = '''
import bpy, math, os
from mathutils import Vector

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 420
scene.render.resolution_y = 420
scene.render.film_transparent = True
for o in list(bpy.data.objects):
    if o.type in {"CAMERA", "LIGHT"} or o.name.startswith("Ground"):
        bpy.data.objects.remove(o, do_unlink=True)

rig = bpy.data.objects.get("Sapscrap_Rig")
if rig and rig.animation_data:
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

cam_data = bpy.data.cameras.new("ProbeCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = span * 1.4
cam = bpy.data.objects.new("ProbeCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
d = Vector((0.0, -1.0, 0.10)).normalized()   # head-on at the maw (-y)
cam.location = center + d * span * 3
cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

sun = bpy.data.lights.new("ProbeSun", type="SUN")
sun.energy = 4.0
so = bpy.data.objects.new("ProbeSun", sun)
scene.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(-25))

scene.render.filepath = %(out)r
bpy.ops.render.render(write_still=True)
result = {"span": round(span, 3)}
'''

r = blend.call(RENDER % {"out": OUT})
if r.get("status") != "ok":
    raise SystemExit("render failed: %s" % r.get("message"))

img = Image.open(OUT).convert("RGBA")
w, h = img.size
# the maw fills the frame centre in this head-on fit; sample a centre disc
cx, cy = w // 2, int(h * 0.52)
rad = int(w * 0.08)
px = img.load()
vals = []
for dx in range(-rad, rad + 1, 2):
    for dy in range(-rad, rad + 1, 2):
        p = px[cx + dx, cy + dy]
        if p[3] > 200:
            vals.append(p[:3])
if len(vals) < 50:
    raise SystemExit("maw probe: only %d opaque samples" % len(vals))
mean = [sum(c[i] for c in vals) / len(vals) for i in range(3)]
report = {"samples": len(vals), "mean_rgb": [round(m, 1) for m in mean]}
print(json.dumps(report))
if max(mean) > 80.0:
    sys.exit("maw centre is NOT dark: mean RGB %s" % report["mean_rgb"])
