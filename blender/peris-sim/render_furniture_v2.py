# Preview renders of the furniture_v2 set: lays the pieces out on a grid and
# renders two angles to renders/ for eyeballing. Never saves the blend.
import bpy
import math
import os

SRC = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(SRC, "renders")

bpy.ops.wm.open_mainfile(filepath=os.path.join(SRC, "furniture_v2.blend"))

roots = [ob for ob in bpy.data.objects
         if ob.parent is None and not ob.name.startswith("Monos")]
monos = [ob for ob in bpy.data.objects
         if ob.parent is None and ob.name.startswith("Monos")]

# spread the peris pieces on a grid (they were all built at origin)
roots.sort(key=lambda o: o.name)
cols = 5
for i, ob in enumerate(roots):
    ob.location.x = (i % cols) * 2.2 - 4.4
    ob.location.y = (i // cols) * 2.2
    if ob.name == "Portal":
        ob.location.z = 1.6
# park the monos room far away
for ob in monos:
    ob.location.x += 60

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1100
scene.eevee.taa_render_samples = 16

world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.25, 0.28, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
scene.world = world

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
bpy.context.collection.objects.link(sun)

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cam)
scene.camera = cam

def aim(loc, target):
    cam.location = loc
    d = (bpy.mathutils_vector(target) if False else None)
    from mathutils import Vector
    direction = Vector(target) - Vector(loc)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

aim((0.0, -11.0, 8.5), (0.0, 2.0, 0.8))
scene.render.filepath = os.path.join(OUT, "v2_grid_front.png")
bpy.ops.render.render(write_still=True)

aim((9.0, -8.0, 5.0), (0.0, 2.0, 0.8))
scene.render.filepath = os.path.join(OUT, "v2_grid_side.png")
bpy.ops.render.render(write_still=True)

# monos room look-in (through the open front)
for ob in monos:
    ob.location.x -= 60
for ob in roots:
    ob.location.y += 60
aim((0.0, -7.5, 2.6), (0.0, 2.8, 1.6))
scene.render.filepath = os.path.join(OUT, "v2_monos_room.png")
bpy.ops.render.render(write_still=True)
print("[RENDER] done")
