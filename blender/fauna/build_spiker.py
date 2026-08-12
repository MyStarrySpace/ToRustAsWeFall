# SPIKER — the rooted turret, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_spiker.py
#
# Built against the director's sheets, which are the authority:
#   .../concept/fauna/spiker-affordance-concept-01.png  (and -02, -03)
#   .../concept/fauna/spiker-turnaround-concept-01.png
#
# IT IS A TREE. A tall pale trunk standing on a tripod of buttress roots, carrying
# a crown of thick blunt dendritic branches — that shape is the whole silhouette,
# and the black thumbnail on every sheet is a trunk with arms. A squat cone wearing
# a shuttlecock of upswept needles is a different animal; the canon calls the
# apical stalk "the read", and a build without one has omitted the only thing a
# player identifies it by at distance.
#
# THE SEAMS ARE PAINTED, THE BRANCHES ARE MODELLED. The pale plates are divided by
# fine teal veins running along every facet edge — repetition, and therefore drawn.
# The root filaments spidering across the floor are repetition too, so they are one
# alpha card lying on the ground, never a hundred modelled tubes: at gameplay
# distance modelled filaments alias into fuzz while a drawn mat stays crisp.
#
# THE BREAK IS A STATE, SO IT IS RIGGED. The damaged panel shows the trunk snapped
# and leaning, its base burst into rubble with rust staining, some crown branches
# sheared to jagged stumps and the rest drooping. Every part of that is a pose of
# the same body — house law forbids swapping in a second, broken one.

import bpy
import bmesh
import importlib
import math
import os
import sys

from mathutils import Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)
import paintlib as pl  # noqa: E402
importlib.reload(pl)
from paintlib import rig  # noqa: E402
importlib.reload(rig)
from paintlib import graft  # noqa: E402
importlib.reload(graft)

SRC = os.path.join(BL, "fauna")
TEX_DIR = os.path.join(SRC, "textures")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "spiker.gltf")
for d in (TEX_DIR, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

TRUNK_H = 1.52             # to the crown junction; the tree reads over a wall
TRUNK_R0 = 0.175           # where the buttresses let go of it
TRUNK_R1 = 0.105           # at the neck below the crown
HUB_R = 0.225              # the junction the crown leaves from
BUTTRESS = 3               # the tripod the sheet stands it on
BUTT_R = 0.52
BUTT_H = 0.46
BRANCHES = 7
BRANCH_SEG = 3
SIGNAL = 0                 # the branch that carries the charge
ROOT_MAT_R = 1.15          # the drawn filament mat
SIDES = 9
UV_SCALE = 1.0


class Rng:
    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)

    def f(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((self.s >> 11) & ((1 << 53) - 1)) / float(1 << 53)

    def between(self, a, b):
        return a + (b - a) * self.f()


# ---------------------------------------------------------------- textures ----
def _write_png(name, size, fn):
    path = os.path.join(TEX_DIR, name)
    img = bpy.data.images.new(name, size, size, alpha=True)
    px = [0.0] * (size * size * 4)
    for y in range(size):
        for x in range(size):
            r, g, b, a = fn(x, y, size)
            i = (y * size + x) * 4
            px[i], px[i + 1], px[i + 2], px[i + 3] = r, g, b, a
    img.pixels = px
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def _cellf(x, y, size, cell):
    """Distance to the nearest two scattered points, for a plate pattern.

    The seams follow the cell walls, which is what makes the body read as PLATES
    with veins between them rather than as a cracked texture: a wall is where two
    plates meet, so it can only be found by asking about the second-nearest."""
    cx, cy = x / cell, y / cell
    best, second = 9e9, 9e9
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            gx, gy = int(math.floor(cx)) + dx, int(math.floor(cy)) + dy
            h = ((gx * 73856093) ^ (gy * 19349663)) & 0xFFFFFF
            px = gx + ((h & 0xFF) / 255.0)
            py = gy + (((h >> 8) & 0xFF) / 255.0)
            d = math.hypot(cx - px, cy - py)
            if d < best:
                second, best = best, d
            elif d < second:
                second = d
    return best, second - best


def _bone(x, y, size):
    """Pale bone plates with teal veins in the seams between them."""
    _d, wall = _cellf(x, y, size, 7.0)
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    if wall < 0.055:
        return (0.36 + 0.08 * n, 0.63 + 0.09 * n, 0.60 + 0.08 * n, 1.0)   # vein
    v = 0.80 + 0.10 * n
    return (v, v * 0.985, v * 0.93, 1.0)


def _charge(x, y, size):
    return (0.42, 0.96, 0.92, 1.0)


def _rubble(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
    n = (h % 100) / 100.0
    if (h >> 8) % 5 == 0:
        return (0.40 + 0.07 * n, 0.21 + 0.05 * n, 0.12, 1.0)              # rust
    v = 0.55 + 0.12 * n
    return (v, v * 0.97, v * 0.90, 1.0)


def _rootmat(x, y, size):
    """The filament mat: thin roots spidering outward, DRAWN. Alpha everywhere the
    ground shows through, which is nearly all of it."""
    c = (size - 1) * 0.5
    dx, dy = (x - c) / max(1.0, c), (y - c) / max(1.0, c)
    r = math.hypot(dx, dy)
    if r > 0.99 or r < 0.02:
        return (0.0, 0.0, 0.0, 0.0)
    a = math.atan2(dy, dx)
    # a bundle of roots per sector, each wandering as it goes out
    sector = 13.0
    k = math.floor(a / math.tau * sector + 0.5)
    centre = (k / sector) * math.tau
    wob = 0.055 * math.sin(r * 17.0 + k * 2.1) + 0.03 * math.sin(r * 31.0 - k)
    off = abs(((a - centre + math.pi) % math.tau) - math.pi - wob)
    width = 0.028 * (1.0 - r * 0.55)
    branch = off < width or (r > 0.45 and abs(off - 0.075 * r) < width * 0.6)
    if not branch:
        return (0.0, 0.0, 0.0, 0.0)
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    v = (0.74 + 0.10 * n) * (1.0 - r * 0.35)
    return (v, v * 0.98, v * 0.92, 1.0)


def material(name, image, emit=None, cutout=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
    if cutout:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return mat


# ---------------------------------------------------------------- geometry ----
def tube_bm(pts, radii, sides=SIDES, seed=0, cap=True):
    """A lofted tube through a polyline. Rings are oriented on the running
    direction so a branch bends at its knuckles instead of shearing."""
    rng = Rng(seed)
    bm = bmesh.new()
    rows = []
    for i, (pt, r) in enumerate(zip(pts, radii)):
        if i == 0:
            d = (Vector(pts[1]) - Vector(pts[0])).normalized()
        elif i == len(pts) - 1:
            d = (Vector(pts[-1]) - Vector(pts[-2])).normalized()
        else:
            d = ((Vector(pts[i + 1]) - Vector(pts[i])).normalized()
                 + (Vector(pts[i]) - Vector(pts[i - 1])).normalized()).normalized()
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        ring = []
        for k in range(sides):
            a = math.tau * k / sides
            jr = 1.0 + rng.between(-0.06, 0.06)
            ring.append(bm.verts.new((q @ Vector((math.cos(a) * r * jr,
                                                  math.sin(a) * r * jr, 0.0)))
                                     + Vector(pt)))
        rows.append(ring)
    for i in range(len(rows) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    if cap:
        bm.faces.new(tuple(reversed(rows[0])))
        bm.faces.new(tuple(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _trunk_pt(t):
    return (0.0, 0.0, BUTT_H + t * (TRUNK_H - BUTT_H))


def _branch_dir(i):
    a = math.tau * i / BRANCHES + 0.35
    return Vector((math.cos(a), math.sin(a), 0.0))


def _branch_pt(i, s):
    """Out and UP, with the elbow the sheet puts at about a third of the way."""
    d = _branch_dir(i)
    rng = Rng(500 + i * 31)
    reach = 0.78 * rng.between(0.86, 1.14)
    rise = 0.40 * rng.between(0.75, 1.2)
    out = reach * s
    up = rise * math.sin(s * 1.5)
    return (d.x * out, d.y * out, TRUNK_H + up)


def append_bm(obj, bm, material_index):
    me = bpy.data.meshes.new("_add")
    bm.to_mesh(me)
    bm.free()
    base_p = len(obj.data.polygons)
    verts = [v.co.copy() for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    bpy.data.meshes.remove(me)
    work = bmesh.new()
    work.from_mesh(obj.data)
    made = [work.verts.new(co) for co in verts]
    work.verts.ensure_lookup_table()
    for p in polys:
        work.faces.new(tuple(made[i] for i in p))
    v0 = len(obj.data.vertices)
    work.to_mesh(obj.data)
    work.free()
    for p in obj.data.polygons[base_p:]:
        p.material_index = material_index
    return v0, len(obj.data.vertices)


def box_uv(mesh, scale=UV_SCALE):
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        i, j = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[i] / scale, co[j] / scale)


TRUNK_RANGE = [0, 0]
BUTT_RANGES = []
BRANCH_RANGES = {}
EMIT_RANGE = [0, 0]
RUBBLE_RANGE = [0, 0]
ROOTMAT_RANGE = [0, 0]


def build_spiker():
    coll = bpy.context.scene.collection
    # ONE bmesh for the whole body. The trunk is the HOST and everything that
    # grows off it is grafted INTO it at a shared ring, so the tree is a single
    # welded surface rather than a trunk with parts parked against it.
    # THE TRUNK FLARES INTO A CROWN HUB before the branches leave it. Seven
    # apertures of 7 cm radius want a metre of circumference and a 10 cm trunk
    # offers 66 cm, so grafted straight onto the shaft they overlap each other and
    # eat the topology between them. The sheet flares the junction for the same
    # reason a real tree does: that is where seven limbs have to fit.
    t_stations = [0.0, 0.25, 0.5, 0.72, 0.88, 1.0]
    t_radii = [TRUNK_R0, 0.150, 0.128, 0.112, 0.140, HUB_R]
    body = tube_bm([_trunk_pt(t) for t in t_stations], t_radii, seed=7)

    # THE TRIPOD, grafted low on the shaft and curving down to the floor.
    for b in range(BUTTRESS):
        a = math.tau * b / BUTTRESS + 0.5
        d = Vector((math.cos(a), math.sin(a), 0.0))
        seat = graft.surface_hit(body, (0.0, 0.0, BUTT_H * 1.15), tuple(d))
        if seat is None:
            raise RuntimeError("buttress %d could not find the trunk" % b)
        pts = [tuple(seat),
               (d.x * BUTT_R * 0.45, d.y * BUTT_R * 0.45, BUTT_H * 0.62),
               (d.x * BUTT_R * 0.86, d.y * BUTT_R * 0.86, BUTT_H * 0.14),
               (d.x * BUTT_R, d.y * BUTT_R, 0.005)]
        graft.graft_polyline(body, tuple(d), 0.085, pts,
                             [0.085, 0.105, 0.075, 0.045], segments=7)

    # THE CROWN, grafted at the junction. Each branch leaves the trunk through its
    # own aperture, so a branch has a shoulder instead of a butt joint.
    for i in range(BRANCHES):
        pts = [_branch_pt(i, s / float(BRANCH_SEG)) for s in range(BRANCH_SEG + 1)]
        # THE APERTURE IS HORIZONTAL even though the branch rises. Fired along the
        # branch's own heading the ray leaves through the hub's TOP CAP and the cut
        # lands on a face nearly perpendicular to it, which opens nothing. A limb
        # leaves a trunk through its flank and turns upward afterwards, so the hole
        # is cut in the flank and the polyline does the rising.
        heading = (Vector(pts[1]) - Vector(pts[0]))
        flank = Vector((heading.x, heading.y, 0.0)).normalized()
        seat = graft.surface_hit(body, (0.0, 0.0, TRUNK_H - 0.05), tuple(flank))
        if seat is None:
            raise RuntimeError("branch %d could not find the trunk" % i)
        path = [tuple(seat)] + [tuple(p) for p in pts[1:]]
        graft.graft_polyline(body, tuple(flank), 0.062, path,
                             [0.062, 0.062, 0.055, 0.048], segments=7)

    graft.assert_welded(body, "Spiker body")

    me = bpy.data.meshes.new("SpikerRigged")
    body.to_mesh(me)
    body.free()
    obj = bpy.data.objects.new("SpikerRigged", me)
    coll.objects.link(obj)
    TRUNK_RANGE[0], TRUNK_RANGE[1] = 0, len(obj.data.vertices)

    bone = material("SpikerBone", _write_png("spiker_bone.png", 96, _bone))
    charge = material("SpikerCharge", _write_png("spiker_charge.png", 8, _charge), emit=5.0)
    rubble = material("SpikerRubble", _write_png("spiker_rubble.png", 48, _rubble))
    rootmat = material("SpikerRoots", _write_png("spiker_roots.png", 128, _rootmat),
                       cutout=True)
    for m in (bone, charge, rubble, rootmat):
        obj.data.materials.append(m)
    I_BONE, I_CHARGE, I_RUBBLE, I_ROOT = range(4)

    # the emitter at the crown's heart, parked dark
    EMIT_RANGE[0], EMIT_RANGE[1] = append_bm(
        obj, tube_bm([(0.0, 0.0, TRUNK_H - 0.03), (0.0, 0.0, TRUNK_H + 0.10)],
                     [0.075, 0.045], sides=7, seed=9), I_CHARGE)

    # the rubble the break bursts the foot into, modelled at full size and parked
    # at nothing so the atlas gives it texels
    r0 = len(obj.data.vertices)
    rng = Rng(4242)
    for c in range(7):
        a = math.tau * c / 7 + 0.2
        rr = BUTT_R * rng.between(0.35, 0.95)
        p = (math.cos(a) * rr, math.sin(a) * rr, 0.055 * rng.between(0.6, 1.4))
        chunk = bmesh.new()
        bmesh.ops.create_icosphere(chunk, subdivisions=1,
                                   radius=0.085 * rng.between(0.6, 1.3))
        for v in chunk.verts:
            v.co = Vector((v.co.x, v.co.y, v.co.z * 0.55)) + Vector(p)
        bmesh.ops.recalc_face_normals(chunk, faces=chunk.faces)
        append_bm(obj, chunk, I_RUBBLE)
    RUBBLE_RANGE[0], RUBBLE_RANGE[1] = r0, len(obj.data.vertices)

    # THE FILAMENT MAT: one drawn card, never a hundred modelled roots
    mat_bm = bmesh.new()
    quad = [mat_bm.verts.new(p) for p in (
        (-ROOT_MAT_R, -ROOT_MAT_R, 0.004), (ROOT_MAT_R, -ROOT_MAT_R, 0.004),
        (ROOT_MAT_R, ROOT_MAT_R, 0.004), (-ROOT_MAT_R, ROOT_MAT_R, 0.004))]
    mat_bm.faces.new(tuple(quad))
    bmesh.ops.recalc_face_normals(mat_bm, faces=mat_bm.faces)
    ROOTMAT_RANGE[0], ROOTMAT_RANGE[1] = append_bm(obj, mat_bm, I_ROOT)

    box_uv(obj.data)
    # the root card must sample its own art across the whole quad, not the body's
    # triplanar projection, or the mat renders as one flat swatch
    uv = obj.data.uv_layers["UVMap"]
    for p in obj.data.polygons:
        if p.vertices[0] < ROOTMAT_RANGE[0]:
            continue
        for li in p.loop_indices:
            co = obj.data.vertices[obj.data.loops[li].vertex_index].co
            uv.data[li].uv = ((co.x / ROOT_MAT_R) * 0.5 + 0.5,
                              (co.y / ROOT_MAT_R) * 0.5 + 0.5)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.data.validate()
    obj.data.update()
    return obj


# -------------------------------------------------------------------- rig ----
def spiker_chains():
    """The trunk as a chain so it can lean and snap, a chain per branch so a
    branch can stir, point, droop or shear, the emitter, and the rubble."""
    chains = [{"prefix": "trunk",
               "points": [(0.0, 0.0, 0.0), _trunk_pt(0.34), _trunk_pt(0.7),
                          _trunk_pt(1.0)]}]
    for b in range(BUTTRESS):
        a = math.tau * b / BUTTRESS + 0.5
        d = Vector((math.cos(a), math.sin(a), 0.0))
        chains.append({"prefix": "butt%d" % b, "parent": "trunk_0",
                       "points": [(0.0, 0.0, BUTT_H * 0.9),
                                  (d.x * BUTT_R, d.y * BUTT_R, 0.005)]})
    for i in range(BRANCHES):
        pts = [_branch_pt(i, s / float(BRANCH_SEG)) for s in range(BRANCH_SEG + 1)]
        chains.append({"prefix": "br%d" % i, "parent": "trunk_2", "points": pts})
    chains.append({"prefix": "emit", "parent": "trunk_2",
                   "points": [(0.0, 0.0, TRUNK_H - 0.03), (0.0, 0.0, TRUNK_H + 0.10)]})
    chains.append({"prefix": "rubble", "parent": "trunk_0",
                   "points": [(0.0, 0.0, 0.0), (0.0, 0.0, 0.09)]})
    chains.append({"prefix": "roots", "parent": "trunk_0",
                   "points": [(0.0, 0.0, 0.002), (0.0, 0.0, 0.05)]})
    return chains


def weight_by_tag(obj, arm):
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    tagged = {}
    for b, (v0, v1) in enumerate(BUTT_RANGES):
        for i in range(v0, v1):
            tagged[i] = "butt%d_0" % b
    for key, (v0, v1) in BRANCH_RANGES.items():
        bi, seg = key[2:].split("_")
        for i in range(v0, v1):
            tagged[i] = "br%s_%s" % (bi, seg)
    for i in range(EMIT_RANGE[0], EMIT_RANGE[1]):
        tagged[i] = "emit_0"
    for i in range(RUBBLE_RANGE[0], RUBBLE_RANGE[1]):
        tagged[i] = "rubble_0"
    for i in range(ROOTMAT_RANGE[0], ROOTMAT_RANGE[1]):
        tagged[i] = "roots_0"
    for v in obj.data.vertices:
        name = tagged.get(v.index)
        if name is None:
            # The shaft, split between its own bones by height so it can bend.
            # FOUR chain points make THREE bones, numbered from zero — counting
            # from one hands the lowest run of the trunk to trunk_1, leaves
            # trunk_0 weighted to nothing, and the rig gate calls it dead. The
            # bone still animates through every clip; it simply moves no geometry,
            # which is invisible in a render and in the build log alike.
            t = max(0.0, min(0.999, (v.co.z - BUTT_H) / max(1e-6, TRUNK_H - BUTT_H)))
            name = "trunk_%d" % min(2, int(t * 3))
        groups[name].add([v.index], 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


piece = build_spiker()
arm = rig.build_armature("Spiker", spiker_chains())
# BY POSITION, not by index. A graft deletes host faces and takes their orphaned
# vertices with them, so every range recorded during the build describes a mesh
# that no longer exists by the time weights are assigned.
_LOOSE = {}
for _i in range(RUBBLE_RANGE[0], RUBBLE_RANGE[1]):
    _LOOSE[_i] = "rubble_0"
for _i in range(ROOTMAT_RANGE[0], ROOTMAT_RANGE[1]):
    _LOOSE[_i] = "roots_0"
for _i in range(EMIT_RANGE[0], EMIT_RANGE[1]):
    _LOOSE[_i] = "emit_0"
graft.weight_nearest(piece, arm, overrides=_LOOSE,
                     groups_for=set(b.name for b in arm.data.bones)
                     - {"rubble_0", "roots_0", "emit_0"})

DARK, LIT, GLARE = 0.001, 1.0, 1.45
BRANCH_KEYS = ["br%d_%d" % (i, s) for i in range(BRANCHES) for s in range(BRANCH_SEG)]


def _pose(**over):
    out = {"trunk_0": 1.0, "trunk_1": (0.0, 0.0, 0.0), "trunk_2": (0.0, 0.0, 0.0),
           "emit_0": DARK, "rubble_0": 0.001, "roots_0": 1.0}
    for b in range(BUTTRESS):
        out["butt%d_0" % b] = 1.0
    for key in BRANCH_KEYS:
        out[key] = (0.0, 0.0, 0.0)
    out.update(over)
    return out


def _stir(amount):
    return dict((k, (amount * (0.5 + 0.5 * ((i * 7) % 3) / 2.0), 0.0, 0.0))
                for i, k in enumerate(BRANCH_KEYS))


# LOCK: the crown stirs and the branches come round toward what it has seen.
rig.clip(arm, "spiker_lock", [
    (0.0, _pose()),
    (0.5, _pose(**_stir(0.10))),
])
# CHARGE: the emitter climbs while the crown holds its aim — the whole window the
# player is given to break the sightline.
rig.clip(arm, "spiker_charge", [
    (0.0, _pose(emit_0=DARK, **_stir(0.10))),
    (0.5, _pose(emit_0=0.5, **_stir(0.12))),
    (1.1, _pose(emit_0=LIT, **_stir(0.14))),
])
rig.clip(arm, "spiker_discharge", [
    (0.0, _pose(emit_0=LIT, **_stir(0.14))),
    (0.09, _pose(emit_0=GLARE, **_stir(0.05))),
    (0.5, _pose(emit_0=DARK, **_stir(0.10))),
])
# SEVER: the sightline goes and the charge dies where it stood.
rig.clip(arm, "spiker_sever", [
    (0.0, _pose(emit_0=LIT, **_stir(0.14))),
    (0.3, _pose()),
])

# BREAK: the damaged read. The trunk gives way and leans, the foot bursts into
# rubble, the outer segments of three branches shear off to leave jagged stumps,
# and everything still attached droops. It holds on the last pose, because a
# wrecked turret does not stand back up.
SHEARED = {}
for _i in (1, 3, 5):
    SHEARED["br%d_2" % _i] = 0.001
DROOP = dict((k, (0.30 + 0.10 * ((i * 5) % 3), 0.0, 0.05 * (1 if i % 2 else -1)))
             for i, k in enumerate(BRANCH_KEYS))
rig.clip(arm, "spiker_break", [
    (0.0, _pose()),
    (0.18, _pose(trunk_1=(0.10, 0.0, 0.03), emit_0=0.3)),
    (0.55, _pose(trunk_1=(0.26, 0.0, 0.07), trunk_2=(0.14, 0.0, 0.0),
                 rubble_0=0.7, **dict(DROOP, **SHEARED))),
    (1.2, _pose(trunk_1=(0.34, 0.0, 0.09), trunk_2=(0.18, 0.0, 0.0),
                rubble_0=1.0, **dict(DROOP, **SHEARED))),
    (1.9, _pose(trunk_1=(0.34, 0.0, 0.09), trunk_2=(0.18, 0.0, 0.0),
                rubble_0=1.0, **dict(DROOP, **SHEARED))),
])
rig.park(arm, _pose())

report = rig.validate(piece, arm)
print("[RIG] Spiker %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("spiker rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "spiker.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: spiker -> %s ===" % GLTF)
