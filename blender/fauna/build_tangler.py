# TANGLER — the paired tau strands, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_tangler.py
#
# Built against the director's sheets, which are the authority:
#   .../concept/fauna/tangler-affordance-concept-01.png
#   .../concept/fauna/tangler-turnaround-concept-01.png
#
# IT HAS NO BODY. That is the whole design: two thick strands wound around each
# other and arched into a hoop, standing on hooked feet at either end, and nothing
# else. The silhouette on the sheet is an arch you could walk under. A solid drum
# with two glowing eyes carrying the strands as trim is a different creature
# entirely — it invents a head for something whose canon is that it is only ever
# a tangle.
#
# THE STRANDS ARE THE MASS AND THEY ARE MODELLED, because they hold the form. The
# scale pattern and the pale seam ridge running along each strand are repetition,
# so they are painted. The violet at the striking tips is the only light on it,
# and it lives at the hook — the roster's tell is the hook coming for you.
#
# DEATH IS THE HELIX LETTING GO. Canon: "On death, the helix unwinds entirely, the
# two strands lying flat against the substrate in a tangled pile." The sheet draws
# it with the mid-section broken and shedding violet crystal shards. Shed parts are
# keyframed detachables, never simulation.

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
GLTF = os.path.join(OUT_DIR, "tangler.gltf")
for d in (TEX_DIR, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

STRANDS = 2                # PAIRED, which is what tau makes
SEG = 9                    # joints along each strand
SPAN = 1.30                # foot to foot: an arch a character walks under
ARCH_H = 0.86
TWIST = 2.1                # turns the pair makes over the span
STRAND_R = 0.072
TIP_SEG = 3                # the free whip past the arch's far foot
FEET = 3                   # hooked toes per foot
SHARDS = 9
SIDES = 7
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


def _scale_skin(x, y, size):
    """Pale olive plating with a lighter seam. The scales are the repetition and
    they are drawn — a modelled scale per plate would alias into mush at the
    distance this thing is fought from."""
    cx, cy = x / 6.0, y / 7.0
    fx, fy = cx - math.floor(cx), cy - math.floor(cy)
    if int(math.floor(cy)) % 2:
        fx = (fx + 0.5) % 1.0
    edge = min(fx, 1.0 - fx, fy, 1.0 - fy)
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    if edge < 0.10:
        v = 0.46 + 0.07 * n
        return (v, v * 0.98, v * 0.78, 1.0)
    v = 0.66 + 0.13 * n
    return (v, v * 0.96, v * 0.70, 1.0)


def _hook_glow(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.80 + 0.10 * n, 0.66 + 0.09 * n, 0.98, 1.0)


def _shard(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.62 + 0.12 * n, 0.44 + 0.10 * n, 0.86, 1.0)


def material(name, image, emit=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.84
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
    return mat


# ---------------------------------------------------------------- geometry ----
def _spine(t):
    """The arch the pair runs along: up off one foot, over, down to the other."""
    x = (t - 0.5) * SPAN
    z = ARCH_H * math.sin(math.pi * min(1.0, max(0.0, t))) ** 0.85
    return Vector((x, 0.0, z))


def _strand_pt(s, i, n=SEG):
    """One strand's station i: the arch, offset around it by the twist. The two
    strands are the SAME curve half a turn apart, which is what makes them read as
    wound around each other rather than merely side by side."""
    t = i / float(n)
    base = _spine(t)
    a = TWIST * math.tau * t + math.pi * s
    # the offset frame: the arch runs in x-z, so the winding rides y and the
    # arch's own normal
    d = (_spine(min(1.0, t + 0.02)) - _spine(max(0.0, t - 0.02)))
    if d.length < 1e-5:
        d = Vector((1.0, 0.0, 0.0))
    d.normalize()
    side = Vector((0.0, 1.0, 0.0))
    up = d.cross(side).normalized()
    r = STRAND_R * 1.15
    return base + side * (math.cos(a) * r) + up * (math.sin(a) * r)


def tube_bm(pts, radii, sides=SIDES, seed=0):
    rng = Rng(seed)
    bm = bmesh.new()
    rows = []
    for i, (pt, r) in enumerate(zip(pts, radii)):
        p = Vector(pt)
        if i == 0:
            d = (Vector(pts[1]) - p).normalized()
        elif i == len(pts) - 1:
            d = (p - Vector(pts[-2])).normalized()
        else:
            d = ((Vector(pts[i + 1]) - p).normalized()
                 + (p - Vector(pts[i - 1])).normalized()).normalized()
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        ring = []
        for k in range(sides):
            a = math.tau * k / sides
            jr = 1.0 + rng.between(-0.05, 0.05)
            ring.append(bm.verts.new((q @ Vector((math.cos(a) * r * jr,
                                                  math.sin(a) * r * jr, 0.0))) + p))
        rows.append(ring)
    for i in range(len(rows) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    bm.faces.new(tuple(reversed(rows[0])))
    bm.faces.new(tuple(rows[-1]))
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


SEG_RANGES = {}
FOOT_RANGES = {}
HOOK_RANGES = {}
SHARD_RANGE = [0, 0]


def _foot_toe(s, end, k):
    """A hooked toe: out from the strand's last station, down, and curled back."""
    anchor = _strand_pt(s, 0 if end == 0 else SEG)
    a = math.tau * k / FEET + (0.4 if end else 1.9) + s * 0.8
    # SPLAYED ACROSS THE ARCH, not along it. The arch already spans X; toes that
    # also reach along X only make it wider, and lengthening them took the front
    # aspect to 1.49 against the sheet's 0.90-1.09 while fixing the side. Biasing
    # the splay toward Y buys the depth without the width.
    d = Vector((math.cos(a) * (0.20 if end else -0.20), math.sin(a), 0.0)).normalized()
    # LONG TENDRILS, not stubs. Measured orthographically against the turnaround,
    # the build came out side L/H 0.44 where every one of the sheet's four views is
    # 0.90-1.09 — the arch is right across its span but far too SHALLOW front to
    # back. The sheet's hooked legs are long, reaching out about as far as the arch
    # stands tall and splaying fore and aft, which is what gives the animal the same
    # silhouette from every angle. At 0.32 of reach they were stubs under the arch's
    # feet and contributed almost no depth.
    return [tuple(anchor),
            tuple(anchor + d * 0.34 + Vector((0, 0, -0.24))),
            tuple(anchor + d * 0.58 + Vector((0, 0, -0.47))),
            tuple(anchor + d * 0.78 + Vector((0, 0, -0.40)))]


def _strand_path(s):
    """One strand END TO END: the arch, then the whip it runs on into, then the
    hook. Lofted as a SINGLE polyline, so every joint along it is an interior edge
    loop instead of the seam between two sleeves that merely share an axis."""
    pts = [_strand_pt(s, i) for i in range(SEG + 1)]
    radii = [STRAND_R] * (SEG + 1)
    d = (pts[-1] - pts[-2]).normalized()
    p = pts[-1]
    for k in range(TIP_SEG):
        p = p + d * 0.20 + Vector((0.0, 0.05 * (1 if s else -1), -0.06 * k))
        pts.append(p)
        radii.append(STRAND_R * (0.82 - 0.16 * k))
    p = p + d * 0.10 + Vector((0, 0, 0.07))
    pts.append(p)
    radii.append(STRAND_R * 0.30)
    p = p + d * 0.05 + Vector((0, 0, 0.09))
    pts.append(p)
    radii.append(STRAND_R * 0.15)
    return [tuple(x) for x in pts], radii


def build_tangler():
    coll = bpy.context.scene.collection
    strands = []
    for s in range(STRANDS):
        pts, radii = _strand_path(s)
        strands.append(tube_bm(pts, radii, seed=1 + s * 7))

    # THE TOES ARE GRAFTED, each through its own aperture in the strand's flank.
    for s in range(STRANDS):
        bm = strands[s]
        for end in (0, 1):
            for k in range(FEET):
                path = [Vector(p) for p in _foot_toe(s, end, k)]
                heading = path[1] - path[0]
                flank = Vector((heading.x, heading.y, 0.0))
                if flank.length < 1e-5:
                    flank = Vector((1.0, 0.0, 0.0))
                flank.normalize()
                # FIRE FROM INSIDE THE TUBE, not from its very end. The last
                # station lies exactly in the end ring's plane, so a ray cast from
                # there leaves through the cap at t=0 and is discarded as a
                # grazing hit — the aperture then reports that it "missed the
                # host" while sitting in the middle of it.
                inside = _strand_pt(s, 0.8 if end == 0 else SEG - 0.8)
                seat = graft.surface_hit(bm, tuple(inside), tuple(flank))
                if seat is None:
                    raise RuntimeError("toe %d/%d/%d found no strand" % (s, end, k))
                graft.graft_polyline(bm, tuple(flank), 0.030,
                                     [tuple(seat)] + [tuple(p) for p in path[1:]],
                                     [0.030, 0.028, 0.020, 0.013], segments=5)
        # TWO ISLANDS IS CORRECT HERE. The pair is wound around each other and
        # never touches — the sheet is explicit — so each strand is welded to
        # itself and to nothing else.
        graft.assert_welded(bm, "Tangler strand %d" % s)

    me = bpy.data.meshes.new("TanglerRigged")
    strands[0].to_mesh(me)
    obj = bpy.data.objects.new("TanglerRigged", me)
    coll.objects.link(obj)

    skin = material("TanglerSkin", _write_png("tangler_skin.png", 96, _scale_skin))
    glow = material("TanglerHook", _write_png("tangler_hook.png", 16, _hook_glow),
                    emit=4.0)
    shard = material("TanglerShard", _write_png("tangler_shard.png", 16, _shard),
                     emit=2.2)
    for m in (skin, glow, shard):
        obj.data.materials.append(m)
    I_SKIN, I_GLOW, I_SHARD = range(3)

    append_bm(obj, strands[1], I_SKIN)

    # the hooks take the lit material by POSITION, since the loft that carries them
    # is continuous and there is no separate object to point at any more
    for s in range(STRANDS):
        pts, _r = _strand_path(s)
        tip = Vector(pts[-1])
        for p in obj.data.polygons:
            if (p.center - tip).length < 0.13:
                p.material_index = I_GLOW

    # the crystal it sheds where the helix breaks: loose by nature, tagged as such
    v0 = len(obj.data.vertices)
    rng = Rng(808)
    mid = _spine(0.5)
    for c in range(SHARDS):
        a = math.tau * c / SHARDS + 0.3
        rr = rng.between(0.10, 0.42)
        p = mid + Vector((math.cos(a) * rr, math.sin(a) * rr, -ARCH_H * 0.86))
        chunk = bmesh.new()
        bmesh.ops.create_icosphere(chunk, subdivisions=0,
                                   radius=0.038 * rng.between(0.55, 1.35))
        for v in chunk.verts:
            v.co = Vector((v.co.x, v.co.y, v.co.z * 0.7)) + p
        bmesh.ops.recalc_face_normals(chunk, faces=chunk.faces)
        append_bm(obj, chunk, I_SHARD)
    SHARD_RANGE[0], SHARD_RANGE[1] = v0, len(obj.data.vertices)

    # UNWRAP LAST, after every graft and every append
    box_uv(obj.data)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.data.validate()
    obj.data.update()
    return obj


# -------------------------------------------------------------------- rig ----
def tangler_chains():
    chains = []
    for s in range(STRANDS):
        chains.append({"prefix": "fil%d" % s,
                       "points": [tuple(_strand_pt(s, i)) for i in range(SEG + 1)]})
        tail = _strand_pt(s, SEG)
        d = (tail - _strand_pt(s, SEG - 1)).normalized()
        pts = [tuple(tail)]
        p = tail
        for k in range(TIP_SEG):
            p = p + d * 0.20 + Vector((0.0, 0.05 * (1 if s else -1), -0.06 * k))
            pts.append(tuple(p))
        chains.append({"prefix": "whip%d" % s, "parent": "fil%d_%d" % (s, SEG - 1),
                       "points": pts})
        chains.append({"prefix": "hook%d" % s, "parent": "whip%d_%d" % (s, TIP_SEG - 1),
                       "points": [tuple(p), tuple(p + d * 0.13 + Vector((0, 0, 0.15)))]})
        for end in (0, 1):
            for k in range(FEET):
                pts = _foot_toe(s, end, k)
                chains.append({"prefix": "toe%d_%d_%d" % (s, end, k),
                               "parent": "fil%d_%d" % (s, 0 if end == 0 else SEG - 1),
                               "points": pts})
    chains.append({"prefix": "shard", "points": [tuple(_spine(0.5)),
                                                 tuple(_spine(0.5) + Vector((0, 0, 0.1)))]})
    return chains


def weight_by_tag(obj, arm):
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    tagged = {}
    for key, (v0, v1) in SEG_RANGES.items():
        for i in range(v0, v1):
            tagged[i] = key if key.startswith("whip") else key
    for key, (v0, v1) in HOOK_RANGES.items():
        for i in range(v0, v1):
            tagged[i] = key
    for key, (v0, v1) in FOOT_RANGES.items():
        for i in range(v0, v1):
            tagged[i] = key
    for i in range(SHARD_RANGE[0], SHARD_RANGE[1]):
        tagged[i] = "shard_0"
    missing = 0
    for v in obj.data.vertices:
        name = tagged.get(v.index)
        if name is None or name not in groups:
            name = "fil0_0"
            missing += 1
        groups[name].add([v.index], 1.0, 'REPLACE')
    if missing:
        print("[WARN] %d verts fell back to fil0_0" % missing)
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


piece = build_tangler()
arm = rig.build_armature("Tangler", tangler_chains())
graft.weight_nearest(
    piece, arm,
    overrides=dict((i, "shard_0") for i in range(SHARD_RANGE[0], SHARD_RANGE[1])),
    groups_for=set(b.name for b in arm.data.bones) - {"shard_0"})

FIL_KEYS = ["fil%d_%d" % (s, i) for s in range(STRANDS) for i in range(SEG)]
WHIP_KEYS = ["whip%d_%d" % (s, i) for s in range(STRANDS) for i in range(TIP_SEG)]
HOOK_KEYS = ["hook%d_0" % s for s in range(STRANDS)]
TOE_KEYS = ["toe%d_%d_%d_0" % (s, e, k)
            for s in range(STRANDS) for e in (0, 1) for k in range(FEET)]
DARK, LIT = 0.001, 1.0


def _pose(**over):
    out = {"shard_0": 0.001}
    for k in FIL_KEYS + WHIP_KEYS + TOE_KEYS:
        out[k] = (0.0, 0.0, 0.0)
    for k in HOOK_KEYS:
        out[k] = DARK
    out.update(over)
    return out


def _wave(keys, amount, lead=0.4):
    out = {}
    for i, k in enumerate(keys):
        f = 1.0 - lead * (i / float(max(1, len(keys) - 1)))
        out[k] = (amount * f, 0.0, 0.0)
    return out


# UNCOIL: the arch loosens and the whips come round, hooks lighting as they do.
rig.clip(arm, "tangler_uncoil", [
    (0.0, _pose()),
    (0.4, _pose(**dict(_wave(WHIP_KEYS, 0.14), **dict((k, 0.4) for k in HOOK_KEYS)))),
    (0.9, _pose(**dict(_wave(WHIP_KEYS, 0.30), **dict((k, LIT) for k in HOOK_KEYS)))),
])
# SNAP: the strike. The whips lash out and the hooks flare at the end of it.
rig.clip(arm, "tangler_snap", [
    (0.0, _pose(**dict(_wave(WHIP_KEYS, 0.30), **dict((k, LIT) for k in HOOK_KEYS)))),
    (0.10, _pose(**dict(_wave(WHIP_KEYS, -0.34), **dict((k, 1.5) for k in HOOK_KEYS)))),
    (0.45, _pose(**dict(_wave(WHIP_KEYS, 0.16), **dict((k, 0.5) for k in HOOK_KEYS)))),
])
rig.clip(arm, "tangler_recoil", [
    (0.0, _pose(**dict(_wave(WHIP_KEYS, 0.16), **dict((k, 0.5) for k in HOOK_KEYS)))),
    (0.7, _pose()),
])

# UNWIND: the death. The helix lets go entirely and both strands come down flat
# against the substrate, the arch flattening out of the silhouette while the
# broken middle sheds its crystal. It holds on the last pose — a tangle that has
# stopped does not gather itself back up.
# The bones are BUILT along the arch, so their rest pose already carries its
# curvature. Adding a positive wave curls the hoop tighter and stands it up on
# end; laying it down means CANCELLING that curvature — roughly the arch's own
# per-joint angle, backwards — and then pitching each root over so the straightened
# strand comes to the floor instead of pointing off it.
_ARCH_PER_JOINT = math.pi / float(SEG)
FLAT = dict(_wave(FIL_KEYS, -_ARCH_PER_JOINT * 1.05, lead=0.10),
            **_wave(WHIP_KEYS, -0.12))
for _s in range(STRANDS):
    FLAT["fil%d_0" % _s] = (-1.95, 0.0, 0.16 * (1 if _s else -1))
SPRAWL = dict(FLAT, **dict((k, (0.55, 0.0, 0.20 * (1 if i % 2 else -1)))
                           for i, k in enumerate(TOE_KEYS)))
rig.clip(arm, "tangler_unwind", [
    (0.0, _pose()),
    (0.3, _pose(**dict(_wave(FIL_KEYS, 0.12, lead=0.15),
                       **dict((k, 0.7) for k in HOOK_KEYS)))),
    (0.9, _pose(shard_0=0.6, **dict(FLAT, **dict((k, 0.3) for k in HOOK_KEYS)))),
    (1.6, _pose(shard_0=1.0, **dict(SPRAWL, **dict((k, DARK) for k in HOOK_KEYS)))),
    (2.3, _pose(shard_0=1.0, **dict(SPRAWL, **dict((k, DARK) for k in HOOK_KEYS)))),
])
rig.park(arm, _pose())

report = rig.validate(piece, arm)
print("[RIG] Tangler %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("tangler rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "tangler.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: tangler -> %s ===" % GLTF)
