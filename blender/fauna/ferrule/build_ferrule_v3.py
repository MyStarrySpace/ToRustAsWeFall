"""Ferrule v3 - arched stance, built from the surveyed silhouette.

Every station below is a MEASURED landmark from survey_v3.py against the middle
panel of ferrule-pyoverdine-structure-to-attack-silhouette-01.png, in units of
silhouette height with the origin on the ground under the nose. Forms are laid
out onto those points; nothing here is eyeballed except the width axis, which
the side-view source cannot show.

Blender space: +X right, +Y rearward (mouth at -Y), +Z up, ground Z=0.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector

COLLECTION = "FerruleV3"
ROOT = "FerruleRoot"
TEX_DIR = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
           "resources/models/fauna/ferrule_v3")

H = 1.55                 # silhouette height in metres -> length 2.159*H = 3.35
UV_SCALE = 3.05
ROOT_Y_OFFSET = -2.34

# ----------------------------------------------------------- measured survey
# name: (x rearward, y up, x-extent, y-extent) in silhouette-height units
STATIONS = {
    "head":      (0.3425, 0.2659, 0.564, 0.430),
    "arch_rise": (0.6843, 0.6789, 0.343, 0.581),
    "arch_apex": (0.9927, 0.8524, 0.384, 0.291),
    "arch_fall": (1.3295, 0.7047, 0.422, 0.606),
    "haunch":    (1.5495, 0.2858, 0.322, 0.509),
    "rear":      (1.8044, 0.3306, 0.644, 0.772),
}
ARCH_APEX_POINT = (0.917, 0.9965)
ARCH_VOID_CLEAR = 0.8131          # underside clearance: keep the arch open
GROUND_CONTACTS = [(0.0796, 0.5087), (1.5156, 2.1592)]
MOUTH_LIME = (0.3717, 0.0402, 0.1003, 0.0554)
ARM_TIPS = [(0.7888, 0.3723), (1.1877, 0.3824)]

WIDTH = 0.86             # body half-breadth scale (side view cannot measure it)
KNIT = 1.15              # oversize so adjacent masses interpenetrate into one body


# --------------------------------------------------------------- scene setup

def wipe():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for act in list(bpy.data.actions):
        act.use_fake_user = False
        bpy.data.actions.remove(act)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures,
                  bpy.data.collections):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    coll = bpy.data.collections.get(COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(coll)
    return coll


def _image(filename):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.get(filename)
    if img is None:
        img = bpy.data.images.load(path, check_existing=True)
    else:
        img.filepath = path
        img.reload()
    img.name = filename
    return img


def material(name, albedo, emissive=None, strength=1.15):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.80
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-620, 120)
    tex.image = _image(albedo)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emissive:
        et = nt.nodes.new("ShaderNodeTexImage")
        et.location = (-620, -240)
        et.image = _image(emissive)
        et.interpolation = "Closest"
        nt.links.new(et.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def box_uv(mesh, scale=UV_SCALE):
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        i, j = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[i] / scale, co[j] / scale)


def unit_uv(mesh, inset=0.08):
    uv = mesh.uv_layers.new(name="UVMap")
    lo, hi = inset, 1.0 - inset
    corners = [(lo, lo), (hi, lo), (hi, hi), (lo, hi)]
    for poly in mesh.polygons:
        for k, li in enumerate(poly.loop_indices):
            uv.data[li].uv = corners[k % 4]


# ------------------------------------------------------------ chunk generator

class Rng:
    """Deterministic LCG so a rebuild reproduces every facet exactly."""

    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)

    def f(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((self.s >> 11) & ((1 << 53) - 1)) / float(1 << 53)

    def between(self, a, b):
        return a + (b - a) * self.f()


def chunk(name, center, size, seed, mat, coll, parent, rings=3, radial=5,
          jitter=0.13, squash_bottom=None, uv="box"):
    """A faceted stone mass: the convex hull of a jittered ellipsoid cloud.

    This is the concept's visual grammar - irregular angular boulders with big
    flat faces - rather than a smooth primitive.
    """
    rng = Rng(seed)
    pts = []
    for i in range(1, rings + 1):
        phi = math.pi * i / (rings + 1)
        rz = math.cos(phi)
        rr = math.sin(phi)
        n = max(3, int(radial * rr + 0.5) + 2)
        for k in range(n):
            th = 2.0 * math.pi * k / n + rng.between(-0.16, 0.16)
            j = 1.0 + rng.between(-jitter, jitter)
            x = rr * math.cos(th) * j
            y = rr * math.sin(th) * j
            z = rz * (1.0 + rng.between(-jitter * 0.6, jitter * 0.6))
            pts.append((x, y, z))
    pts.append((0, 0, 1.0 + rng.between(-0.05, 0.05)))
    pts.append((0, 0, -1.0 - rng.between(-0.05, 0.05)))

    bm = bmesh.new()
    for p in pts:
        bm.verts.new((p[0] * size[0] * 0.5, p[1] * size[1] * 0.5, p[2] * size[2] * 0.5))
    bm.verts.ensure_lookup_table()
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(26.0),
                             verts=bm.verts, edges=bm.edges)
    if squash_bottom is not None:
        for v in bm.verts:
            if v.co.z < squash_bottom:
                v.co.z = squash_bottom
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    mesh.update()
    (box_uv if uv == "box" else unit_uv)(mesh)

    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.parent = parent
    obj.location = center
    return obj


def wedge(name, verts, faces, mat, coll, parent, uv="unit"):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    (box_uv if uv == "box" else unit_uv)(mesh)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.parent = parent
    return obj


def P(x, y):
    """Survey point -> Blender (Y rearward, Z up), metres."""
    return (x * H, y * H)


# ------------------------------------------------------------------- the body

def build():
    coll = wipe()
    body = material("FerruleBody", "ferrule_body.png")
    signal = material("FerruleSignal", "ferrule_signal.png", "ferrule_signal_emissive.png")
    void = material("FerruleMouthVoid", "ferrule_mouth.png")

    root = bpy.data.objects.new(ROOT, None)
    coll.objects.link(root)
    root.location.y = ROOT_Y_OFFSET

    made = []

    # Head cluster: three masses filling the measured head bbox, seated on the
    # ground contact run 0.080-0.509.
    hx, hy, hw, hh = STATIONS["head"]
    for nm, (ox, oy, sx, sz, sd) in {
        "Ferrule_Mouth":     (0.190, 0.250, 0.36, 0.36, 1.02),
        "Ferrule_HeadBase":  (0.340, 0.225, 0.52, 0.32, 1.14),
        "Ferrule_HeadCrest": (0.440, 0.470, 0.38, 0.42, 1.00),
        "Ferrule_Neck":      (0.580, 0.575, 0.32, 0.44, 0.74),
    }.items():
        y, z = P(ox, oy)
        made.append(chunk(nm, (0.0, y, z),
                          (sd * WIDTH * H * KNIT, sx * H * KNIT, sz * H * KNIT),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll, parent=root,
                          squash_bottom=-(z - 0.140 * H)))

    # The two measured foot pads the head rides on.
    for nm, (px, pw_) in {
        "Ferrule_HeadPad_F": (0.185, 0.210),
        "Ferrule_HeadPad_R": (0.478, 0.078),
    }.items():
        y, z = P(px, 0.105)
        made.append(chunk(nm, (0.0, y, z),
                          (0.86 * WIDTH * H, pw_ * H * 1.05, 0.245 * H),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll, parent=root,
                          rings=3, radial=6, jitter=0.15, squash_bottom=-z))

    # Arch: three masses over the measured apex, clear of the ground.
    for nm, key, sd in (("Ferrule_Segment_ArchRise", "arch_rise", 0.66),
                        ("Ferrule_Segment_ArchApex", "arch_apex", 0.70),
                        ("Ferrule_Segment_ArchFall", "arch_fall", 0.74)):
        x, yv, ex, ez = STATIONS[key]
        y, z = P(x, yv)
        made.append(chunk(nm, (0.0, y, z),
                          (sd * WIDTH * H * KNIT, ex * H * KNIT, ez * H * KNIT),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll, parent=root))

    # Haunch + the bulky rear, both seated on ground contact run 1.516-2.159.
    for nm, key, sd in (("Ferrule_Haunch", "haunch", 0.78),
                        ("Ferrule_RearAnchor", "rear", 1.16)):
        x, yv, ex, ez = STATIONS[key]
        y, z = P(x, yv)
        made.append(chunk(nm, (0.0, y, z),
                          (sd * WIDTH * H * KNIT, ex * H * KNIT, ez * H * KNIT),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll, parent=root,
                          squash_bottom=-z))

    # The two lime-tipped pendants are a PINCER PAIR, not side limbs: they sit
    # in the sagittal plane, tips level and confronting, and they are what
    # closes on the iron core in panel 3 of the source sheet.
    for i, (tx, ty) in enumerate(ARM_TIPS):
        nm = "Ferrule_Jaw_%s" % ("F" if i == 0 else "R")
        lean = 0.055 if i == 0 else -0.055          # each leans toward the other
        y, z = P(tx + lean, ty + 0.135)
        made.append(chunk(nm, (0.0, y, z),
                          (0.34 * WIDTH * H, 0.17 * H, 0.34 * H),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll,
                          parent=root, rings=3, radial=5, jitter=0.14))
        ty2, tz2 = P(tx, ty)
        made.append(chunk(nm + "_SignalTip", (0.0, ty2, tz2 - 0.02 * H),
                          (0.30 * WIDTH * H, 0.13 * H, 0.17 * H),
                          seed=(hash(nm) & 0xffff) + 7, mat=signal, coll=coll,
                          parent=root, rings=3, radial=5, jitter=0.10, uv="unit"))

    # Two little stubby arms - vestigial folded manipulators tucked against the
    # forequarters, well clear of the ground.
    for side in (-1, 1):
        nm = "Ferrule_Arm_%s" % ("L" if side < 0 else "R")
        y, z = P(0.600, 0.500)
        made.append(chunk(nm, (side * 0.30 * WIDTH * H, y, z),
                          (0.20 * WIDTH * H, 0.20 * H, 0.16 * H),
                          seed=hash(nm) & 0xffff, mat=body, coll=coll, parent=root,
                          rings=3, radial=5, jitter=0.13))
        y2, z2 = P(0.512, 0.408)
        made.append(chunk(nm + "_Hand", (side * 0.32 * WIDTH * H, y2, z2),
                          (0.15 * WIDTH * H, 0.13 * H, 0.12 * H),
                          seed=(hash(nm) & 0xffff) + 11, mat=body, coll=coll,
                          parent=root, rings=3, radial=4, jitter=0.11))

    # A little tail carrying on past the bulky end.
    rx, ry, rex, rez = STATIONS["rear"]
    tail_root = rx + rex * 0.42
    for i, (fx, fs) in enumerate(((0.04, 0.50), (0.13, 0.34), (0.21, 0.19))):
        y, z = P(tail_root + fx, 0.300 - i * 0.040)
        nm = "Ferrule_Tail_%02d" % (i + 1)
        made.append(chunk(nm, (0.0, y, z),
                          (fs * WIDTH * H * KNIT, (0.24 - i * 0.035) * H * KNIT,
                           fs * 1.05 * H * KNIT),
                          seed=(hash(nm) & 0xffff), mat=body, coll=coll, parent=root,
                          rings=3, radial=6, jitter=0.16))

    # Teeth: the measured lime chevron, hung in the recess between the pads.
    mx, my, mw, mh = MOUTH_LIME
    verts, faces = [], []
    n_teeth = 5
    for k in range(n_teeth):
        f = (k + 0.5) / n_teeth - 0.5
        cx = f * 1.02 * WIDTH * H
        taper = 1.0 - 0.40 * abs(f) * 2.0
        root_y, root_z = P(mx + f * 0.045, 0.245)
        tip_y, tip_z = P(mx + f * 0.045 - 0.030, 0.008)
        hw_t = 0.062 * H * taper
        dep = 0.068 * H * taper
        base = len(verts)
        verts.extend([
            (cx - hw_t, root_y - dep, root_z), (cx + hw_t, root_y - dep, root_z),
            (cx + hw_t, root_y + dep, root_z), (cx - hw_t, root_y + dep, root_z),
            (cx - hw_t * 0.18, tip_y - dep * 0.28, tip_z),
            (cx + hw_t * 0.18, tip_y - dep * 0.28, tip_z),
            (cx + hw_t * 0.18, tip_y + dep * 0.28, tip_z),
            (cx - hw_t * 0.18, tip_y + dep * 0.28, tip_z),
        ])
        for q in range(4):
            q2 = (q + 1) % 4
            faces.append([base + q, base + 4 + q, base + 4 + q2, base + q2])
        faces.append([base + 3, base + 2, base + 1, base])
        faces.append([base + 4, base + 5, base + 6, base + 7])
    made.append(wedge("Ferrule_SignalTeeth", verts, faces, signal, coll, root))

    # The dark gape the teeth hang from.
    y, z = P(mx, 0.235)
    gw, gd, gh = 0.62 * H, 0.10 * H, 0.24 * H
    verts = [(-gw / 2, y - gd, z - gh / 2), (gw / 2, y - gd, z - gh / 2),
             (gw / 2, y - gd, z + gh / 2), (-gw / 2, y - gd, z + gh / 2),
             (-gw / 2 * 0.8, y + gd, z - gh / 2), (gw / 2 * 0.8, y + gd, z - gh / 2),
             (gw / 2 * 0.8, y + gd, z + gh / 2 * 0.85),
             (-gw / 2 * 0.8, y + gd, z + gh / 2 * 0.85)]
    faces = [[0, 1, 2, 3], [4, 7, 6, 5], [0, 3, 7, 4], [1, 5, 6, 2],
             [3, 2, 6, 7], [0, 4, 5, 1]]
    made.append(wedge("Ferrule_MouthVoid", verts, faces, void, coll, root))

    # Nothing may pierce the floor plane.
    for o in coll.objects:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            wz = o.location.z + v.co.z
            if wz < 0.0:
                v.co.z -= wz
        o.data.update()

    bpy.context.view_layer.update()
    meshes = [o for o in coll.objects if o.type == "MESH"]
    xs, ys, zs = [], [], []
    for o in meshes:
        for c in o.bound_box:
            v = o.matrix_world @ Vector(c)
            xs.append(v.x); ys.append(v.y); zs.append(v.z)
    return {
        "meshes": len(meshes),
        "polys": sum(len(o.data.polygons) for o in meshes),
        "uv_ok": all(len(o.data.uv_layers) > 0 for o in meshes),
        "bounds_m": {"w": round(max(xs) - min(xs), 3),
                     "l": round(max(ys) - min(ys), 3),
                     "h": round(max(zs) - min(zs), 3)},
        "L_over_H": round((max(ys) - min(ys)) / (max(zs) - min(zs)), 3),
        "min_z": round(min(zs), 4),
    }


result = build()
