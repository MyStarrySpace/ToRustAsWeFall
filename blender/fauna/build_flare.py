# FLARE — the granulocyte that vents, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_flare.py
#
# Built against the director's sheets, which are the authority:
#   to-rust-as-we-fall/reference-images/concept/fauna/flare-affordance-concept-01.png
#   to-rust-as-we-fall/reference-images/concept/fauna/flare-turnaround-concept-01.png
#
# EVERYTHING IS INSIDE A CLOSED BALL. Every panel of the sheet draws one
# translucent faceted envelope with the four-lobed nucleus suspended at its centre
# and three classes of granule floating around it. The old build had the nucleus
# as four dark chimneys standing on the ROOF of a stacked-frustum lamp — the same
# inside-out error the Meeb's food-cups shipped, and the Crust's pores after it.
#
# THE ENVELOPE IS A STIPPLED CUTOUT, NOT A BLENDED SURFACE. The sheet's membrane
# is translucent and the pipeline is alpha-MASK only, because blended shells sort
# badly here and vanish in the preview. A dithered mask is how low-res pixel art
# has always carried translucency: at this texel size the holes read as a milky
# skin you can see organelles through, and it sorts like any opaque surface.
#
# THE BURST DOES NOT CONSUME IT. The brief is explicit — "the post-burst state
# remains alive, deflated, and visibly recovering. Avoid implying that the burst
# consumes or kills the organism." The old burst ended on a UNIFORM membrane scale
# of 0.35: the whole creature shrank to a third of itself and held the shape it
# started with, which reads as eaten. The sheet's fourth panel is an envelope
# COLLAPSED AND TORN, spread flat on the ground with its granules spilled out
# around it and the nucleus still lit inside — so the spend is a squash with a
# spread, and there is a recovery clip that re-inflates it.

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

SRC = os.path.join(BL, "fauna")
TEX_DIR = os.path.join(SRC, "textures")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "flare.gltf")
for d in (TEX_DIR, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

BODY_R = 0.28              # the envelope
LOBES = 4                  # the multi-lobed nucleus the cell is named for
LOBE_R = BODY_R * 0.26
CLASSES = 3                # three granule classes, as drawn
SEATS = 4                  # spill bones per class
UV_SCALE = 1.0

# Radius and count per class: big olive, medium gold, small dark. Numbers come
# straight off the sheet, where the small dark ones are much the most numerous.
CLASS_SPEC = [
    {"r": BODY_R * 0.135, "n": 1, "part": 0},
    {"r": BODY_R * 0.105, "n": 2, "part": 1},
    {"r": BODY_R * 0.058, "n": 4, "part": 2},
]


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


_BAYER = [
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
]


def _envelope(x, y, size):
    """Pale amber, holed on an ordered dither so the inside shows through.

    An ordered matrix rather than random noise: random holes crawl and sparkle as
    the camera moves, and at this texel size a stable dither reads as a milky skin
    while a noisy one reads as damage.

    The CELL SIZE is what decides whether it reads as skin or as wire. At the 32
    px/m base a dither cell is over a centimetre across on a 56 cm body — some
    eighteen texels the whole way round — and the envelope came out a wire basket
    with the organelles rattling inside it. A membrane is close detail, which the
    art direction allows up to 128 px/m; the coverage ratio is unchanged, only the
    weave is fine enough to fuse.
    """
    # AN 8x8 MATRIX, NOT A 4x4. Coverage is the same; what changes is how
    # obvious the lattice is. A four-wide cell repeats often enough that the eye
    # assembles it into a woven mesh — the envelope reads as fabric stretched over
    # the organelles instead of a skin you are seeing through. Eight steps put the
    # repeat far enough apart to fuse into a haze at the same texel size.
    keep = _BAYER[y % 8][x % 8] < 36       # ~56% skin, ~44% open
    if not keep:
        return (0.0, 0.0, 0.0, 0.0)
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.88 + 0.09 * n, 0.80 + 0.08 * n, 0.55 + 0.07 * n, 1.0)


def _nucleus(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.82 + 0.09 * n, 0.53 + 0.07 * n, 0.55 + 0.06 * n, 1.0)


def _core(x, y, size):
    return (1.0, 0.86, 0.52, 1.0)


def _gran_a(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.70 + 0.09 * n, 0.74 + 0.08 * n, 0.32 + 0.06 * n, 1.0)


def _gran_b(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.88 + 0.08 * n, 0.72 + 0.07 * n, 0.30 + 0.06 * n, 1.0)


def _gran_c(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.36 + 0.07 * n, 0.31 + 0.06 * n, 0.42 + 0.07 * n, 1.0)


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
    bsdf.inputs["Roughness"].default_value = 0.8
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
def _lobe_at(k):
    """Four lobes in a clover around the centre, which is what the sheet draws —
    not a row and not a ring."""
    a = math.tau * k / LOBES + 0.4
    lift = LOBE_R * (0.42 if k % 2 else -0.42)
    return Vector((math.cos(a) * LOBE_R * 0.80, math.sin(a) * LOBE_R * 0.80, lift))


def _seat_at(cls, i):
    """Where one granule seat sits inside the envelope: out of the nucleus's way
    and off the skin, spread by class so the three sizes interleave rather than
    banding."""
    rng = Rng(9001 + cls * 131 + i * 17)
    # A GRANULE IS SUSPENDED IN THE ENVELOPE, so its SKIN has to clear the
    # membrane and not just its centre. The seat allowed a centre out to 0.80 of
    # the body radius, the spill jitter pushed it another 0.16 of that, and then
    # the granule's own radius carried it past the surface — the largest class
    # reached 1.06 and sat outside as an opaque nub, with one breaking the
    # outline. The cap is solved backwards from where the skin must stop.
    r_rel = CLASS_SPEC[cls]["r"] / BODY_R
    far = (0.94 - r_rel) / 1.16
    for _ in range(200):
        d = Vector((rng.between(-1, 1), rng.between(-1, 1), rng.between(-1, 1)))
        if d.length < 1e-3:
            continue
        d.normalize()
        r = BODY_R * rng.between(0.34, far)
        p = d * r
        if p.length > LOBE_R * 2.1:
            return p
    return Vector((0.0, 0.0, BODY_R * 0.6))


def ico_bm(centre, radius, seed, subdiv=1, squash=1.0):
    rng = Rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * rng.between(0.9, 1.1),
                       v.co.y * rng.between(0.9, 1.1),
                       v.co.z * rng.between(0.9, 1.1) * squash)) + Vector(centre)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


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


# The tear is at ONE point, and the same point every time, so the shed reads as a
# vent rather than a burst — and so two renders of it can be compared.
VENT_SEAT = 5
SHED = 11                  # granules the vent leaves on the floor
SHED_RANGE = [0, 0]
MEMB_RANGE = [0, 0]
NUC_RANGE = [0, 0]
CORE_RANGE = [0, 0]
SEAT_RANGES = {}


def build_flare():
    coll = bpy.context.scene.collection
    me = bpy.data.meshes.new("FlareRigged")
    # the envelope IS the body: everything else is appended inside it
    ico_bm((0, 0, BODY_R * 0.94), BODY_R, 31, subdiv=2).to_mesh(me)
    obj = bpy.data.objects.new("FlareRigged", me)
    coll.objects.link(obj)
    MEMB_RANGE[0], MEMB_RANGE[1] = 0, len(obj.data.vertices)

    env = material("FlareEnvelope", _write_png("flare_envelope.png", 112, _envelope),
                   cutout=True)
    nuc = material("FlareNucleus", _write_png("flare_nucleus.png", 32, _nucleus))
    core = material("FlareCore", _write_png("flare_core.png", 8, _core), emit=4.0)
    ga = material("FlareGranuleA", _write_png("flare_gran_a.png", 24, _gran_a))
    gb = material("FlareGranuleB", _write_png("flare_gran_b.png", 24, _gran_b))
    gc = material("FlareGranuleC", _write_png("flare_gran_c.png", 24, _gran_c))
    for m in (env, nuc, core, ga, gb, gc):
        obj.data.materials.append(m)
    I_ENV, I_NUC, I_CORE, I_GA, I_GB, I_GC = range(6)
    GRAN_MAT = [I_GA, I_GB, I_GC]

    lift = Vector((0.0, 0.0, BODY_R * 0.94))
    n0 = len(obj.data.vertices)
    for k in range(LOBES):
        append_bm(obj, ico_bm(_lobe_at(k) + lift, LOBE_R, 41 + k * 7), I_NUC)
    NUC_RANGE[0], NUC_RANGE[1] = n0, len(obj.data.vertices)
    # THE LIGHT WHERE THE LOBES MEET, on its own bone so it can be OFF. The
    # roster calls an untriggered Flare inert, and a bomb sitting there already
    # bright has spent the two or three seconds everyone nearby was owed — so the
    # core is modelled at full size for the atlas and parked at nothing, exactly
    # the way every other warning in this project is held back.
    CORE_RANGE[0], CORE_RANGE[1] = append_bm(obj, ico_bm(lift, LOBE_R * 0.34, 61),
                                             I_CORE)

    SEAT_RANGES.clear()
    for cls, spec in enumerate(CLASS_SPEC):
        for i in range(SEATS):
            seat = _seat_at(cls, i)
            v0 = len(obj.data.vertices)
            for j in range(spec["n"]):
                jitter = Vector((0.0, 0.0, 0.0)) if j == 0 else _seat_at(cls, i) * 0.16
                append_bm(obj, ico_bm(seat + lift + jitter, spec["r"],
                                      700 + cls * 53 + i * 11 + j), GRAN_MAT[cls])
            SEAT_RANGES["gran%d_%d" % (cls, i)] = (v0, len(obj.data.vertices),
                                                   tuple(seat + lift))

    # WHAT IT LOST, on the floor. The seat bones move the granules the body still
    # holds; nothing was laying down the ones that left, so the vent streamed into
    # empty air and the spent panel had no debris under it. These are modelled at
    # full size and parked at nothing, shed over the back half of the collapse —
    # keyframed detachables, never simulation — and they fall on the TEAR'S side,
    # because a directional vent that scattered its spill evenly would undo the
    # thing the direction was for.
    v0 = len(obj.data.vertices)
    vent_dir = _seat_at(0, VENT_SEAT % SEATS)
    vent_dir = Vector((vent_dir.x, vent_dir.y, 0.0))
    if vent_dir.length < 1e-4:
        vent_dir = Vector((1.0, 0.0, 0.0))
    vent_dir.normalize()
    side = Vector((-vent_dir.y, vent_dir.x, 0.0))
    for d in range(SHED):
        h = ((d * 73856093) ^ 19349663) & 0xFFFFFF
        f0 = (h % 1000) / 1000.0
        f1 = ((h >> 10) % 1000) / 1000.0
        f2 = ((h >> 20) % 1000) / 1000.0
        out = BODY_R * (0.95 + 1.75 * f0)
        lat = BODY_R * (f1 - 0.5) * 1.15
        p = vent_dir * out + side * lat + Vector((0.0, 0.0, 0.016))
        cls = d % CLASSES
        append_bm(obj, ico_bm(tuple(p), CLASS_SPEC[cls]["r"] * (0.8 + 0.4 * f2),
                              900 + d * 17), GRAN_MAT[cls])
    SHED_RANGE[0], SHED_RANGE[1] = v0, len(obj.data.vertices)

    box_uv(obj.data)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.data.validate()
    obj.data.update()
    return obj


# -------------------------------------------------------------------- rig ----
def flare_chains():
    """The membrane that swells, the nucleus inside it, and ONE BONE PER GRANULE
    SEAT running from the body's centre out to that seat.

    The seat bones are what make the spill possible at all. Shed parts are
    keyframed detachables, never simulation, and a pose bone here carries no
    translation — so a bone aimed AT the granule moves it outward when scaled and
    drops it when rotated, which is the spill the sheet's fourth panel draws.
    """
    lift = (0.0, 0.0, BODY_R * 0.94)
    chains = [{"prefix": "memb", "points": [(0.0, 0.0, 0.0), lift]}]
    chains.append({"prefix": "nuc", "parent": "memb_0",
                   "points": [lift, (0.0, 0.0, BODY_R * 0.94 + LOBE_R)]})
    # the shed rides the MEMBRANE'S root, not a seat: it is on the floor and stays
    # there while the envelope above it collapses
    chains.append({"prefix": "shed", "parent": "memb_0",
                   "points": [(0.0, 0.0, 0.012), (0.0, 0.0, 0.07)]})
    chains.append({"prefix": "core", "parent": "nuc_0",
                   "points": [lift, (0.0, 0.0, BODY_R * 0.94 + LOBE_R * 0.5)]})
    for cls in range(CLASSES):
        for i in range(SEATS):
            key = "gran%d_%d" % (cls, i)
            seat = SEAT_RANGES[key][2]
            chains.append({"prefix": key, "parent": "memb_0",
                           "points": [lift, seat]})
    return chains


def weight_by_tag(obj, arm):
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    tagged = {}
    for i in range(NUC_RANGE[0], NUC_RANGE[1]):
        tagged[i] = "nuc_0"
    for i in range(CORE_RANGE[0], CORE_RANGE[1]):
        tagged[i] = "core_0"
    for i in range(SHED_RANGE[0], SHED_RANGE[1]):
        tagged[i] = "shed_0"
    for key, (v0, v1, _seat) in SEAT_RANGES.items():
        for i in range(v0, v1):
            tagged[i] = "%s_0" % key
    for v in obj.data.vertices:
        groups[tagged.get(v.index, "memb_0")].add([v.index], 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


piece = build_flare()
arm = rig.build_armature("Flare", flare_chains())
weight_by_tag(piece, arm)

GRAN_KEYS = ["gran%d_%d_0" % (c, i) for c in range(CLASSES) for i in range(SEATS)]


def _pose(**over):
    out = {"memb_0": 1.0, "nuc_0": 1.0, "core_0": 0.001, "shed_0": 0.001}
    for key in GRAN_KEYS:
        out[key] = 1.0
    out.update(over)
    return out


# THE MEMBRANE BONE RUNS UP THE BODY, so its LOCAL Y is world Z and the axis that
# has to collapse is the middle number. Written (1.58, 1.52, 0.15) the envelope
# squashed a horizontal axis and grew TALLER — a lozenge standing on end where the
# sheet draws a torn sheet lying flat. Same trap the Meeb's dome sat in; the only
# defence is to name which axis is which every time a non-uniform scale is written.
def _flat(x, tall, y):
    return {"scale": (x, tall, y)}


def _spill(amount, drop):
    """The granules leaving through ONE TEAR, not seeping out all round.

    The sheet's inset draws the envelope pulled into a thin nozzle at a single
    torn point with granules streaming away along a filament — a directional vent.
    Pushing every seat outward by its own share gave a uniform sprinkle, which
    reads as a body dissolving everywhere at once instead of one that split in a
    particular place. Seats near the tear travel far and swing toward it; seats on
    the far side barely move, because nothing is pushing them anywhere.
    """
    out = {}
    n = float(max(1, len(GRAN_KEYS)))
    for k, key in enumerate(GRAN_KEYS):
        # how far round the ring this seat sits from the tear, 0 at it, 1 opposite
        away = abs(((k - VENT_SEAT) % len(GRAN_KEYS)) / n * 2.0 - 1.0)
        near = 1.0 - away
        reach = amount * (0.25 + 1.35 * near * near)
        out[key] = {"scale": 1.0 + reach,
                    "rot": (drop * (0.25 + 0.75 * near),
                            0.0, drop * 0.45 * near * (1 if k % 2 else -1))}
    return out


# PRIME: the wind-up. The envelope swells and the nucleus lights from its centre
# outward — the warning is the light inside a body that is getting bigger.
rig.clip(arm, "flare_prime", [
    (0.0, _pose()),
    (0.5, _pose(memb_0=1.16, nuc_0=1.10, core_0=0.55)),
    (1.0, _pose(memb_0=1.42, nuc_0=1.30, core_0=1.0)),
])

# BURST: the flash itself.
rig.clip(arm, "flare_burst", [
    (0.0, _pose(memb_0=1.42, nuc_0=1.30, core_0=1.0)),
    (0.10, _pose(memb_0=1.62, nuc_0=1.55, core_0=1.6)),
    (0.22, _pose(memb_0=1.30, nuc_0=1.20, core_0=1.1)),
])

# SPENT: what the burst LEAVES, which is not a smaller Flare. The envelope loses
# pressure and collapses — flat and spread, not shrunk — and the granules spill
# out of it and settle around the body. The nucleus stays lit: the brief forbids
# reading the burst as consuming the organism, and a dark nucleus would say it had.
rig.clip(arm, "flare_spent", [
    (0.0, _pose(memb_0=1.30, nuc_0=1.20, core_0=1.1)),
    (0.35, _pose(memb_0=_flat(1.30, 0.52, 1.30), nuc_0=1.05, core_0=0.9,
                 **_spill(0.45, 0.34))),
    (0.9, _pose(memb_0=_flat(1.52, 0.20, 1.48), nuc_0=0.92, core_0=0.8,
                shed_0=0.55, **_spill(1.15, 0.80))),
    (1.5, _pose(memb_0=_flat(1.62, 0.13, 1.56), nuc_0=0.90, core_0=0.75,
                shed_0=1.0, **_spill(1.45, 0.98))),
])

# RECOVER: "visibly recovering". The envelope takes its pressure back and draws
# its granules in with it, ending where an inert Flare stands — which is the whole
# reason the spend is a squash rather than a shrink: there is a body left to
# re-inflate.
rig.clip(arm, "flare_recover", [
    (0.0, _pose(memb_0=_flat(1.62, 0.13, 1.56), nuc_0=0.90, core_0=0.75,
                shed_0=1.0, **_spill(1.45, 0.98))),
    (1.2, _pose(memb_0=_flat(1.24, 0.62, 1.22), nuc_0=0.95, core_0=0.35,
                shed_0=0.75, **_spill(0.52, 0.40))),
    (2.4, _pose()),
])

# SETTLE: a Flare that wound up and never fired, standing back down.
rig.clip(arm, "flare_settle", [
    (0.0, _pose(memb_0=1.42, nuc_0=1.30, core_0=1.0)),
    (1.1, _pose()),
])
rig.park(arm, _pose())

report = rig.validate(piece, arm)
print("[RIG] Flare %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("flare rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "flare.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: flare -> %s ===" % GLTF)
