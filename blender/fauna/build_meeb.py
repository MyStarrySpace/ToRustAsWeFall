# MEEB — the slow pursuer, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_meeb.py
#
# Built against the director's sheets, which are the authority:
#   to-rust-as-we-fall/reference-images/concept/fauna/meeb-affordance-concept-01.png
#   to-rust-as-we-fall/reference-images/concept/fauna/meeb-turnaround-concept-01.png
#
# The roster: "free-living amoebae (Naegleria); THE MANY FOOD-CUPS are the feeding
# apparatus. Inexorable, not fast. Flows at anything and dissolves it with a
# food-cup. A CUP DILATES AND BRIGHTENS BEFORE THE SUCTION. Sidestep its line,
# stun the lunge."
#
# THE FOOD-CUPS ARE HOLES BORED INTO THE BODY. The turnaround is unambiguous: each
# cup is a wide circular shaft sunk into the mass behind a thin raised lip, and the
# silhouette thumbnail reads as a lumpy block PIERCED by them. An earlier build had
# them as cones standing off the surface, which is the same word for the opposite
# shape — an animal covered in nozzles rather than one that is all mouth. So the
# cups are cut with a real boolean and the shaft walls carry their own dark
# material, because a bore that is not darker than the skin reads as a sticker.
#
# The organelles are GEOMETRY, not paint. On the turnaround the nucleus and the
# vacuoles bulge the membrane visibly and catch their own light at the silhouette's
# edge — they are lumps under a skin, not marks on it. Modelling them as domes
# standing proud of the body gets that read with an opaque material, which also
# sidesteps the transparency the sheet's translucency would otherwise ask for: the
# pipeline is alpha-MASK only and blended surfaces sort badly here.
#
# It rests with every cup DARK. The cups are anatomy and stay visible as open
# shafts, because the roster wants a player to recognise the thing on sight; the
# LIGHT is the warning, and a warning already showing is a warning nobody gets.

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
GLTF = os.path.join(OUT_DIR, "meeb.gltf")
for d in (TEX_DIR, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

H = 0.52                    # small-dog-sized, per the brief
BODY_R = 0.22               # NOT as wide as it is tall. Measured orthographically
                            # against the turnaround, the build came out front
                            # W/H 1.47 where the sheet is 1.03 — 43% too wide, a
                            # squat box where the sheet has a settled but upright
                            # mass. H stays 0.52 because that is the brief's stated
                            # small-dog size, so the width is what gives.
RINGS = 9
SIDES = 13
CUPS = 6
CUP_R = 0.077               # a third of the body's width, as drawn
SHAFT_DEPTH = 0.139          # how far a bore reaches in behind its mouth. It has
                            # to EXCEED CUP_DEPTH: set shallower, the deepest part
                            # of every shaft — the floor included — falls outside
                            # the wall test and keeps the pale membrane material,
                            # so each crater renders BRIGHTER than the skin around
                            # it, which is the exact inverse of a bored well
CUP_DEPTH = 0.110            # the shafts stop well short of the core: driven to
                            # the centre they interpenetrate each other there, and
                            # overlapping tubes are what breaks the EXACT solver
FOOT_COUNT = 4
UV_SCALE = 1.0


class Rng:
    """Deterministic — a body that reshuffles its lumps every build cannot be
    compared against the last render, and every revision becomes a guess."""

    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)

    def f(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((self.s >> 11) & ((1 << 53) - 1)) / float(1 << 53)

    def between(self, a, b):
        return a + (b - a) * self.f()


# ---------------------------------------------------------------- textures ----
def _write_png(name, size, fn):
    """Paint one small albedo and save it. Low-res on purpose: the art direction is
    flat forms carrying low-res pixel detail, and a smooth texture on one creature
    reads as the wrong asset in a scene of pixelated ones."""
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


def _membrane(x, y, size):
    """Pale sage, mottled, with the reddish-brown residue patches the sheet shows
    scattered through it — digested material sitting under the skin."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
    n = (h % 100) / 100.0
    base = (0.62 + 0.08 * n, 0.68 + 0.07 * n, 0.52 + 0.06 * n)
    blot = ((x // 2 * 83492791) ^ (y // 2 * 2971215073)) & 0xFFFF
    if blot % 61 == 0:
        return (0.44 + 0.05 * n, 0.26 + 0.04 * n, 0.19, 1.0)   # residue, sparse
    if blot % 7 == 0:
        base = (base[0] * 0.95, base[1] * 0.97, base[2] * 0.94)
    return (base[0], base[1], base[2], 1.0)


def _bore(x, y, size):
    """The shaft wall, LIT AT THE MOUTH AND DARK AT THE THROAT.

    This was one flat dark colour with a little noise, and a flat colour inside a
    hole reads as an oval STICKER on the skin — which is exactly what the cups look
    like on the contact card. On the sheet you can see INTO each crater: the near
    wall catches light just inside the rim and falls away to black at the blind end,
    and that fall is the entire reason the cup reads as bored rather than painted.
    The bore island is a tube side-strip, so its rows run along the shaft's DEPTH —
    a gradient down the rows is a gradient down the hole."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    t = y / max(1.0, size - 1.0)          # 0 at the mouth, 1 at the blind end
    lit = 1.55 * (1.0 - t) ** 1.6 + 0.22  # bright just inside the rim, then gone
    return (min(1.0, (0.13 + 0.05 * n) * lit),
            min(1.0, (0.20 + 0.06 * n) * lit),
            min(1.0, (0.13 + 0.04 * n) * lit), 1.0)


def _nucleus(x, y, size):
    # Sampled off the turnaround, where the nucleus runs about 1.00 : 1.04 : 0.69
    # — red and green level with each other, a lighter khaki of the body's own
    # hue. Green pushed above red instead (it was 1.00 : 1.27 : 0.60) and the
    # lump read as a chunk of lime sitting on the animal rather than part of it.
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.60 + 0.08 * n, 0.62 + 0.08 * n, 0.41 + 0.07 * n, 1.0)


def _vacuole(x, y, size):
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.84 + 0.08 * n, 0.76 + 0.07 * n, 0.56 + 0.06 * n, 1.0)


def _enzyme(x, y, size):
    c = (size - 1) * 0.5
    dx, dy = (x - c) / max(1.0, c), (y - c) / max(1.0, c)
    r = math.hypot(dx, dy)
    if r > 0.98:
        return (0.0, 0.0, 0.0, 0.0)
    if r < 0.34:
        return (1.0, 0.96, 0.62, 1.0)
    if r < 0.70:
        return (0.98, 0.82, 0.30, 1.0)
    return (0.82, 0.58, 0.16, 1.0)


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
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
        mat.blend_method = 'BLEND'
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return mat


# ---------------------------------------------------------------- geometry ----
def _cup_dir(k):
    """Cup 0 faces -Y, the direction the creature is aimed along: the tell has to
    belong to the line it is closing. The rest are spread over the body in two
    bands so the field of them reads as scattered rather than as a belt."""
    if k == 0:
        return Vector((0.0, -1.0, 0.18)).normalized()
    if k == 1:
        # This cup's rim shows over the crown from a raised camera, and TILT IS NOT
        # THE LEVER — measured, not assumed. Sky enclosed by the silhouette went
        # 917 px at +0.12, 1087 at -0.16 (forward, clearly worse) and 928 at +0.40,
        # where the top blob merely splits in two and the flank blobs grow. A
        # near-vertical mouth on a domed body seen from above shows its far rim;
        # that is the shape, not a misaim. Do not tune this number again.
        return Vector((0.05, 0.12, 1.0)).normalized()          # the one on top
    a = math.tau * (k - 2) / float(CUPS - 2) + 0.55
    lift = 0.55 if (k % 2) else -0.10
    return Vector((math.cos(a), math.sin(a), lift)).normalized()


# EVERYTHING IS MEASURED FROM THE BODY'S CENTRE, never from the origin. The lathe
# is built standing on z=0, so the origin is the FLOOR under the animal: a cup
# aimed sideways from there grazes the bottom rim instead of piercing the flank,
# and the boolean quietly cuts nothing at all.
CENTRE = Vector((0.0, 0.0, H * 0.52))


def _inside(p):
    """Is a point inside the lathe? The bore, the lip and the glow all need to
    know where the skin actually is, and for a profile like this one there is no
    closed form worth trusting."""
    if p.z < 0.0 or p.z > H:
        return False
    return math.hypot(p.x, p.y) < _profile(p.z / H)


def _surface_dist(d, hi=1.4):
    """How far along `d` the skin sits, from CENTRE. Bisected against _inside so
    it works for a cup aimed out the top — where the surface is the cap and the
    radial equation has no solution — exactly as well as for one aimed sideways."""
    lo = 0.0
    if not _inside(CENTRE):
        return _profile(0.5)
    while hi - lo > 1e-4:
        mid = (lo + hi) * 0.5
        if _inside(CENTRE + d * mid):
            lo = mid
        else:
            hi = mid
    return lo


def _profile(t):
    """Radius down the body: a rounded mass that is widest just below the middle
    and flares again at the floor, which is what gives the sheet its blocky,
    settled read instead of an egg standing on end."""
    r = math.sin(math.pi * (0.16 + 0.74 * t))
    return BODY_R * (0.62 + 0.52 * r) * (1.0 + 0.22 * max(0.0, 0.18 - t) / 0.18)


def body_bm():
    """The mass, as a lathe closed with a fan at each pole.

    Both ends are fans through a single vertex, never a big n-gon cap. A 13-gon
    bottom stops being planar the moment the feet pull four of its corners
    outward, and a non-planar self-intersecting n-gon is precisely what makes the
    EXACT solver return an EMPTY mesh — the cups then fail to cut with no error
    beyond a body that has quietly become nothing.
    """
    rng = Rng(4407)
    bm = bmesh.new()
    rows = []
    for i in range(1, RINGS - 1):
        t = i / float(RINGS - 1)
        z = t * H
        base_r = _profile(t)
        ring = []
        for k in range(SIDES):
            a = math.tau * k / SIDES
            # low-frequency lumps: the membrane is not a lathe, it is a bag
            lump = 1.0 + 0.10 * math.sin(a * 3.0 + t * 4.1) + 0.06 * math.sin(a * 5.0 - t * 2.3)
            r = base_r * lump * rng.between(0.985, 1.015)
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rows.append(ring)
    for i in range(len(rows) - 1):
        for k in range(SIDES):
            k2 = (k + 1) % SIDES
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    top = bm.verts.new((0.0, 0.0, H))
    bottom = bm.verts.new((0.0, 0.0, 0.0))
    for k in range(SIDES):
        k2 = (k + 1) % SIDES
        bm.faces.new((rows[-1][k], rows[-1][k2], top))
        bm.faces.new((rows[0][k2], rows[0][k], bottom))

    # THE FEET. The sheet stands it on short spreading flanges, not on a flat
    # bottom — the thing flows, and a flat base would say it was set down. Each
    # vertex moves AT MOST ONCE: a corner claimed by two neighbouring feet used to
    # be pushed twice and ended up half a body-width out on its own.
    base = rows[0]
    moved = set()
    for f in range(FOOT_COUNT):
        a = math.tau * f / FOOT_COUNT + 0.4
        d = Vector((math.cos(a), math.sin(a), 0.0))
        near = sorted(range(SIDES),
                      key=lambda k: -(Vector(base[k].co).normalized().dot(d)))
        taken = 0
        for k in near:
            if k in moved:
                continue
            base[k].co = base[k].co + d * 0.075 * rng.between(0.85, 1.1)
            base[k].co.z -= 0.010
            moved.add(k)
            taken += 1
            if taken == 3:
                break
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def cutter_bm(k):
    """ONE bore's cutter. Deliberately not all six in a single mesh: driven deep
    enough to matter, the six shafts meet near the middle of the body, and a
    cutter whose parts intersect each other makes EXACT return an EMPTY mesh with
    no error at all. Cut one at a time and a failure names the cup that caused it.
    """
    bm = bmesh.new()
    d = _cup_dir(k)
    surf = _surface_dist(d)
    outside = CENTRE + d * (surf + 0.10)
    inside = CENTRE + d * (surf - CUP_DEPTH)
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    rows = []
    for step, rr in ((0.0, CUP_R), (1.0, CUP_R * 0.72)):
        p = outside.lerp(inside, step)
        # the shaft narrows as it goes in: a food-cup is a sac, not a pipe
        rows.append([bm.verts.new((q @ Vector((math.cos(math.tau * i / 16) * rr,
                                               math.sin(math.tau * i / 16) * rr, 0.0))) + p)
                     for i in range(16)])
    for i in range(16):
        j = (i + 1) % 16
        bm.faces.new((rows[0][i], rows[0][j], rows[1][j], rows[1][i]))
    bm.faces.new(tuple(reversed(rows[0])))
    bm.faces.new(tuple(rows[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bake_boolean(obj, other_mesh, op):
    """Apply one boolean against a temp object and bake it down. The operand takes
    obj's WORLD transform: booleans evaluate operands in world space, so an operand
    left at the origin lands displaced in local space."""
    tmp = bpy.data.objects.new("_boolop", other_mesh)
    obj.users_collection[0].objects.link(tmp)
    bpy.context.view_layer.update()
    tmp.matrix_world = obj.matrix_world.copy()
    mod = obj.modifiers.new("B", "BOOLEAN")
    mod.operation = op
    mod.object = tmp
    mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.remove(mod)
    obj.data = baked
    bpy.data.objects.remove(tmp, do_unlink=True)


def box_uv(mesh, scale=UV_SCALE):
    """Triplanar, applied AFTER the boolean — the cut invents faces nobody laid
    out, and any UV made before it is gone with the mesh it was made on."""
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        i, j = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[i] / scale, co[j] / scale)


def append_bm(obj, bm, material_index):
    """Add loose geometry to a finished object without welding or booleaning it.

    The lips and the organelles interpenetrate the body on purpose: every material
    here is opaque, so an intersection is invisible, and a union would be a dozen
    more EXACT ops on a shell that has already been cut six times."""
    me = bpy.data.meshes.new("_add")
    bm.to_mesh(me)
    bm.free()
    base_v = len(obj.data.vertices)
    base_p = len(obj.data.polygons)
    verts = [v.co.copy() for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    bpy.data.meshes.remove(me)
    work = bmesh.new()
    work.from_mesh(obj.data)
    new_verts = [work.verts.new(co) for co in verts]
    work.verts.ensure_lookup_table()
    for p in polys:
        work.faces.new(tuple(new_verts[i] for i in p))
    work.to_mesh(obj.data)
    work.free()
    for p in obj.data.polygons[base_p:]:
        p.material_index = material_index
    return base_v, base_p


def lips_bm():
    """The thin raised rim each bore wears on the sheet. It is what keeps the cup
    from reading as a hole punched in a bag: a real mouth has a lip."""
    bm = bmesh.new()
    for k in range(CUPS):
        d = _cup_dir(k)
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        # FLUSH, NOT PROUD. The sheet draws a thin rim sitting in the membrane —
        # the cup is bored INTO the body and the lip is the thickness of the skin
        # around the hole. Standing it 28 mm off the surface turns every mouth
        # into a free hoop and puts a fin on the silhouette at each flank, which
        # is the opposite of a hole.
        # THE LIP FOLLOWS THE SKIN. Laid on a flat plane through the mouth, a ring
        # of radius 1.11 * CUP_R has its rim standing off a CURVED body — the
        # surface falls away from the axis faster than the plane does — so the
        # mouth reads as a free hoop with daylight between it and the membrane.
        # Each vertex is placed at the body's own surface along ITS OWN direction
        # instead, which is the measure-the-host rule applied per vertex.
        def _lip_ring(rr, lift):
            ring = []
            for i in range(16):
                off = q @ Vector((math.cos(math.tau * i / 16) * rr,
                                  math.sin(math.tau * i / 16) * rr, 0.0))
                dirv = (CENTRE + d * _surface_dist(d) + off - CENTRE)
                dirv.normalize()
                # SUNK, not skimmed. The sixteen rim directions fan out around the
                # cup axis and each meets the skin at its own distance, so on a
                # body this lumpy a 10 mm inset left some of the ring proud: the
                # top cup floated a rim 13 mm clear of a crown ending at z=0.506.
                # A generous inset embeds the whole ring however the surface runs
                # under it, and the lip is meant to sit flush, so burying it
                # slightly costs nothing.
                ring.append(bm.verts.new(
                    CENTRE + dirv * (_surface_dist(dirv) - 0.034 + lift)))
            return ring

        rows = [_lip_ring(CUP_R * 1.11, 0.0), _lip_ring(CUP_R * 1.04, 0.009)]
        inner = [_lip_ring(CUP_R * 0.99, 0.009), _lip_ring(CUP_R * 0.99, 0.0)]
        loops = [rows[0], rows[1], inner[0], inner[1]]
        for a, b in ((0, 1), (1, 2), (2, 3)):
            for i in range(16):
                j = (i + 1) % 16
                bm.faces.new((loops[a][i], loops[a][j], loops[b][j], loops[b][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ico_bm(centre, radius, seed):
    """One organelle: a faceted lump. Low subdivision on purpose — the sheet's
    masses are large and faceted, and a smooth ball would be the only round thing
    on the model."""
    rng = Rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co = v.co * rng.between(0.88, 1.12) + Vector(centre)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


GLOW_RANGES = []            # (v_start, v_end) per cup, filled during the build
LIP_RANGE = [0, 0]          # the rims, recorded so their standoff can be measured
                            # WITHOUT the organelles, which stand proud by design
                            # and swamped the only number I had for this


def _shaft_clearance(p, radius):
    """Smallest gap between a sphere at `p` and any bore's shaft. Negative means
    the lump has grown into a mouth."""
    worst = 1e9
    for k in range(CUPS):
        d = _cup_dir(k)
        surf = _surface_dist(d)
        a = CENTRE + d * (surf - CUP_DEPTH)          # the shaft's blind end
        b = CENTRE + d * (surf + 0.10)               # its mouth, and past it
        ab = b - a
        t = max(0.0, min(1.0, (Vector(p) - a).dot(ab) / ab.length_squared))
        gap = (Vector(p) - (a + ab * t)).length - (CUP_R + radius)
        worst = min(worst, gap)
    return worst


_PLACED = []                # (centre, radius) per organelle already seated, so a
                            # later one can be kept off the ones before it


def _clear_of_placed(p, radius, margin=0.03):
    """True when a lump at `p` would not crowd one already seated."""
    for q, r in _PLACED:
        if (Vector(p) - q).length < radius + r + margin:
            return False
    return True


def _organelle_seat(radius, seed, zlo=0.18, zhi=1.0):
    """A seat for one lump: just under the skin, and clear of every shaft.

    Candidate directions are scored by how far they stay from the bores, so the
    lumps settle into the gaps between mouths the way the turnaround draws them.
    """
    rng = Rng(seed)
    best, best_gap = None, -1e9
    for _ in range(400):
        # ANY seat that clears is taken, and the first one wins. Scoring 400
        # candidates and keeping the argmax looks careful and is the reason every
        # bead ended up in the same place: the best-clearing spot on this body is
        # the same spot whatever the seed, so nine beads with nine seeds piled
        # into one patch of crown and read as a row of spikes. Spread comes from
        # accepting a good-enough seat, plus a separation test against what is
        # already placed.
        # The band the lump is allowed to sit in. Letting a seat swing below the
        # skirt hides it entirely; letting it swing to vertical puts it on the
        # crown among the cups. The turnaround places them differently — the
        # nucleus low and lateral, the beads scattered high — so each caller
        # names its own band rather than sharing one.
        d = Vector((rng.between(-1, 1), rng.between(-1, 1), rng.between(zlo, zhi)))
        if d.length < 1e-3:
            continue
        d.normalize()
        # Standing 0.45 * radius proud of the skin along its own seat normal is
        # deliberate: on the turnaround these are lumps swelling the membrane
        # from within, not inclusions buried under it.
        p = CENTRE + d * (_surface_dist(d) - radius * 0.55)
        gap = _shaft_clearance(p, radius)
        if gap > best_gap:
            best, best_gap = p, gap
        if gap >= 0.004 and _clear_of_placed(p, radius):
            _PLACED.append((Vector(p), radius))
            return tuple(p)
    if best_gap < 0.004:
        raise RuntimeError("no clear seat for a %.3f organelle (gap %.4f)"
                           % (radius, best_gap))
    _PLACED.append((Vector(best), radius))
    return tuple(best)


def build_meeb():
    coll = bpy.context.scene.collection
    bm = body_bm()
    me = bpy.data.meshes.new("MeebRigged")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("MeebRigged", me)
    coll.objects.link(obj)

    membrane = material("MeebMembrane", _write_png("meeb_membrane.png", 48, _membrane))
    bore = material("MeebBore", _write_png("meeb_bore.png", 32, _bore))
    nuc = material("MeebNucleus", _write_png("meeb_nucleus.png", 32, _nucleus))
    vac = material("MeebVacuole", _write_png("meeb_vacuole.png", 32, _vacuole))
    enz = material("MeebEnzyme", _write_png("meeb_enzyme.png", 32, _enzyme), emit=3.0)
    for m in (membrane, bore, nuc, vac, enz):
        obj.data.materials.append(m)
    I_MEM, I_BORE, I_NUC, I_VAC, I_ENZ = range(5)

    for k in range(CUPS):
        before = len(obj.data.polygons)
        bake_boolean(obj, _to_mesh(cutter_bm(k), "_cut%d" % k), "DIFFERENCE")
        if len(obj.data.polygons) <= before:
            raise RuntimeError("cup %d did not open the shell (%d faces)"
                               % (k, len(obj.data.polygons)))

    # THE SHAFT WALLS TAKE THE DARK MATERIAL. Selected geometrically, because the
    # boolean invents the faces and no index survives it.
    lit = 0
    for p in obj.data.polygons:
        c = p.center
        for k in range(CUPS):
            d = _cup_dir(k)
            rel = c - CENTRE
            along = rel.dot(d)
            radial = (rel - d * along).length
            # A SHAFT WALL LIES INSIDE THE SHAFT, which needs a floor as well as a
            # ceiling. Testing only that a face sits nearer than the surface lets
            # every face on the FAR SIDE of the body qualify — its projection
            # along this cup's axis is large and NEGATIVE, so any of them that
            # happen to fall near the axis line get painted the dark bore colour.
            # That is where the flat dark panels across the outer skin came from,
            # on a creature whose sheet is one uniform pale membrane.
            # AND THE FACE MUST BE INSIDE THE BODY. Bounding the projection
            # along a cup's axis is necessary but not sufficient: a face out on
            # the OUTER SKIN can still fall inside that window and take the dark
            # material, which is where the flat dark panels across the membrane
            # came from. A shaft wall is by definition beneath the surface, so
            # ask that directly, in the face's OWN direction rather than the
            # cup's — measuring against the host instead of against an axis.
            # A SHAFT WALL NEVER FACES OUTWARD. This is the test that actually
            # discriminates, and it needs no ray at all: a bore wall looks in
            # toward its own axis or along it, so any face whose normal points
            # away from the body's centre is skin, whatever else is true of it.
            #
            # The previous guard asked whether the face sat inside the surface
            # along its OWN direction, which bisects the lathe for a crossing —
            # and on a LUMPY body a ray that grazes a lump returns a far
            # crossing, so a face genuinely out on the skin measured as
            # comfortably inside. It reported zero offenders while twenty-two
            # dark panels sat on the membrane.
            surf = _surface_dist(d)
            outward = p.normal.dot(rel.normalized()) if rel.length > 1e-6 else 1.0
            if (radial < CUP_R * 1.02
                    and surf - SHAFT_DEPTH < along < surf * 1.02
                    and outward < 0.30):
                p.material_index = I_BORE
                lit += 1
                break
    if lit < CUPS * 4:
        raise RuntimeError("shaft-wall selection found only %d faces" % lit)

    # append_bm here returns (vert_start, POLY_start) — not a vertex range, which
    # is worth stating because the same helper in build_flare.py returns a vertex
    # range and the two are easy to confuse.
    _lip_v0 = len(obj.data.vertices)
    append_bm(obj, lips_bm(), I_MEM)
    LIP_RANGE[0], LIP_RANGE[1] = _lip_v0, len(obj.data.vertices)
    obj["lip_range"] = list(LIP_RANGE)

    # THE ORGANELLES, as lumps under the skin — one big nucleus riding high on a
    # flank and smaller vacuoles scattered around it, all of them BETWEEN the
    # bores. Their seats are derived from the cup directions rather than typed in:
    # a hand-picked coordinate that happens to clear six shafts stops clearing
    # them the moment a cup angle changes, and the failure is a nucleus visible
    # down the throat of a mouth, which no test and no rest-pose render reports.
    # LATERAL, and low. On the turnaround the nucleus is a flank bulge sitting
    # around mid-body, clearly below the cup rims — it breaks the silhouette
    # sideways, never over the crown. Seated in the old full upper band it came
    # out near-vertical, cresting z=0.577 against a body ending at 0.506.
    append_bm(obj, ico_bm(_organelle_seat(0.077, 11, zlo=-0.10, zhi=0.35),
                          0.077, 77), I_NUC)
    # The beads ride the FLANKS, not the crown. Sharing the nucleus' old full
    # upper band packed them against the rim, where they broke the silhouette as
    # a row of cream spikes; the turnaround scatters them down the sides and over
    # the shoulder as small flush lumps, several visible from any angle. The band
    # stops AT the equator — swung below it, a bead clears the skirt's flare and
    # hangs under the animal in open air.
    for i in range(9):
        append_bm(obj, ico_bm(_organelle_seat(0.029, 23 + i * 13,
                                              zlo=0.02, zhi=0.62),
                              0.029, 131 + i * 7), I_VAC)

    # The enzyme light lives INSIDE each shaft, so a lit cup glows out of its hole.
    # Each disc is appended on its own and its vertex range RECORDED, because the
    # bone that parks it dark cannot be inferred from position: the disc sits in
    # front of the shaft's far wall, on the same side of the surface as the cup
    # bone, and a position test hands it to the cup — which parks it at full size
    # across the mouth. Every bore then reads as a pale disc pasted on the skin
    # instead of a hole, and nothing in the rig gate or the render pipeline says so.
    GLOW_RANGES.clear()
    for k in range(CUPS):
        d = _cup_dir(k)
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        p = CENTRE + d * (_surface_dist(d) - 0.075)
        r = CUP_R * 0.92
        glow = bmesh.new()
        ring = [glow.verts.new((q @ Vector((math.cos(math.tau * i / 12) * r,
                                            math.sin(math.tau * i / 12) * r, 0.0))) + p)
                for i in range(12)]
        glow.faces.new(tuple(ring))
        bmesh.ops.recalc_face_normals(glow, faces=glow.faces)
        v0, _ = append_bm(obj, glow, I_ENZ)
        GLOW_RANGES.append((v0, len(obj.data.vertices)))

    box_uv(obj.data)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.data.validate()
    obj.data.update()
    return obj


def _to_mesh(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


# -------------------------------------------------------------------- rig ----
def meeb_chains():
    """The low mass and what gathers above it, then a bone per cup so any one of
    them can be the one that opens, each carrying its own light."""
    chains = [{"prefix": "body",
               "points": [(0.0, 0.0, 0.0), (0.0, 0.0, H * 0.42), (0.0, 0.0, H)]}]
    for k in range(CUPS):
        d = _cup_dir(k)
        mouth = CENTRE + d * _surface_dist(d)
        chains.append({"prefix": "cup%d" % k, "parent": "body_0",
                       "points": [tuple(CENTRE + d * (_surface_dist(d) * 0.30)),
                                  tuple(mouth)]})
        chains.append({"prefix": "maw%d" % k, "parent": "cup%d_0" % k,
                       "points": [tuple(mouth), tuple(mouth + d * 0.06)]})
    return chains


def weight_by_region(obj, arm):
    """Weights assigned by POSITION, never by vertex index.

    The boolean rebuilds the mesh from scratch, so the index ranges a Builder-based
    body could rely on describe nothing afterwards. Every vertex asks which cup's
    shaft it belongs to and, failing that, which band of the body it sits in."""
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {}
    for bone in arm.data.bones:
        groups[bone.name] = obj.vertex_groups.new(name=bone.name)
    dome_z = H * 0.42
    tagged = {}
    for k, (v0, v1) in enumerate(GLOW_RANGES):
        for i in range(v0, v1):
            tagged[i] = "maw%d_0" % k
    for v in obj.data.vertices:
        if v.index in tagged:
            groups[tagged[v.index]].add([v.index], 1.0, 'REPLACE')
            continue
        co = v.co
        rel = co - CENTRE
        owner = None
        best = 1e9
        for k in range(CUPS):
            d = _cup_dir(k)
            along = rel.dot(d)
            radial = (rel - d * along).length
            if radial < CUP_R * 1.30 and along > _surface_dist(d) * 0.45:
                # inside a shaft or on its lip: the closer the mouth, the more it
                # belongs to the maw that lights rather than the cup that opens
                if radial < best:
                    best, owner = radial, "cup%d_0" % k
        if owner is None:
            owner = "body_1" if co.z > dome_z else "body_0"
        groups[owner].add([v.index], 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


piece = build_meeb()
arm = rig.build_armature("Meeb", meeb_chains())
weight_by_region(piece, arm)

# A cup scales about its buried throat: SHUT pulls the lip back flush with the
# skin, OPEN pushes it clear of the body, WIDE is the suction.
SHUT, OPEN, WIDE = 0.92, 1.22, 1.42
DARK, LIT, GLARE = 0.001, 1.0, 1.35
FEEDING = 0

rest = {"body_0": 1.0, "body_1": (0.0, 0.0, 0.0)}
for _k in range(CUPS):
    rest["cup%d_0" % _k] = SHUT
    rest["maw%d_0" % _k] = DARK


def _pose(**over):
    """A full pose off the rest condition, so no clip ever opens on a bone it
    forgot to state and no cup is left standing open from an earlier beat."""
    out = dict(rest)
    out.update(over)
    return out


# CUP and FEED, ONE PAIR PER MOUTH. The rig grows a bone per cup precisely so any
# one of them can be the one that opens, and the sheet's whole identity is mouths
# aimed in different directions — so a Meeb closing on someone standing off its
# left flank has to show the tell on the cup that faces them. Authored for cup 0
# alone (which is what shipped first), five of the six bone pairs were never
# touched by any clip: the creature could only ever warn, and only ever strike,
# straight ahead. The player sidesteps the LINE, and there are six of them.
#
# `meeb_cup` / `meeb_feed` stay as the forward pair, because a caller with no
# direction in mind wants the one aimed down the walk.
def _lean(k, amount):
    """The mass leans over the cup that is opening. Cup 0 is aimed at -Y so it
    pitches forward; the others lean along their own heading, which is what makes
    the tell readable from the body and not just from the lit hole."""
    d = _cup_dir(k)
    return (d.y * -amount, d.x * amount, 0.0)


for _k in range(CUPS):
    _open = dict(("cup%d_0" % _k, OPEN) for _ in (0,))
    rig.clip(arm, "meeb_cup_%d" % _k, [
        (0.0, _pose()),
        (0.45, _pose(body_1=_lean(_k, 0.10),
                     **{"cup%d_0" % _k: 1.02, "maw%d_0" % _k: 0.35})),
        (1.2, _pose(body_1=_lean(_k, 0.18),
                    **{"cup%d_0" % _k: OPEN, "maw%d_0" % _k: LIT})),
    ])
    rig.clip(arm, "meeb_feed_%d" % _k, [
        (0.0, _pose(body_1=_lean(_k, 0.18),
                    **{"cup%d_0" % _k: OPEN, "maw%d_0" % _k: LIT})),
        (0.12, _pose(body_1=_lean(_k, 0.30),
                     **{"cup%d_0" % _k: WIDE, "maw%d_0" % _k: GLARE})),
        (0.55, _pose(body_1=_lean(_k, 0.08),
                     **{"cup%d_0" % _k: 0.98, "maw%d_0" % _k: 0.4})),
        (0.95, _pose()),
    ])

# The warning. One cup widens and lights while the mass leans over it, and every
# other cup stays shut and dark — the player is being told which way the suction
# will come, which is the only thing that makes sidestepping a choice. Slow,
# because the roster's word for the creature is inexorable, not fast.
rig.clip(arm, "meeb_cup", [
    (0.0, _pose()),
    (0.45, _pose(body_1=_lean(FEEDING, 0.10), cup0_0=1.02, maw0_0=0.35)),
    (1.2, _pose(body_1=_lean(FEEDING, 0.18), cup0_0=OPEN, maw0_0=LIT)),
])
# The suction, and then back to rest. It opens on the pose the warning leaves the
# body in, so the two play as one movement rather than a snap.
rig.clip(arm, "meeb_feed", [
    (0.0, _pose(body_1=_lean(FEEDING, 0.18), cup0_0=OPEN, maw0_0=LIT)),
    (0.12, _pose(body_1=_lean(FEEDING, 0.30), cup0_0=WIDE, maw0_0=GLARE)),
    (0.55, _pose(body_1=_lean(FEEDING, 0.08), cup0_0=0.98, maw0_0=0.4)),
    (0.95, _pose()),
])

# COLLAPSE: the death read — "collapses to a puddle". An amoeba carries no
# skeleton, so a dead one does not fall over: it stops holding itself in, and what
# was holding it in was the only thing making it a shape. Nothing about the spread
# is symmetric; scaled concentrically it lands as a disc with a hard rim, which
# reads as a plate. So the mass SLUMPS forward, spreads wider across than along,
# and each cup slackens by its own amount. It stays dark throughout: the glow was
# the warning, and a corpse that still warns is telling the player to keep away
# from a thing that cannot reach them.
def _slack(k):
    return 0.74 + 0.13 * ((k * 7) % 5)


CUP_SLACK = dict(("cup%d_0" % k, _slack(k)) for k in range(CUPS))
rig.clip(arm, "meeb_collapse", [
    (0.0, _pose()),
    (0.22, _pose(body_0={"scale": (1.05, 0.88, 1.02)},
                 body_1={"scale": (1.10, 0.66, 1.06), "rot": (0.22, 0.0, 0.05)})),
    (0.85, _pose(body_0={"scale": (1.22, 0.38, 1.06), "rot": (0.04, 0.0, 0.05)},
                 body_1={"scale": (1.44, 0.17, 1.20), "rot": (0.46, 0.05, 0.09)},
                 **CUP_SLACK)),
    (1.6, _pose(body_0={"scale": (1.34, 0.23, 1.12), "rot": (0.05, 0.0, 0.06)},
                body_1={"scale": (1.52, 0.09, 1.28), "rot": (0.58, 0.07, 0.10)},
                **CUP_SLACK)),
])
rig.park(arm, _pose())

# This piece is NOT packed into one atlas: it drives a material per part off its
# own small tiling noise, so its UVs run outside 0..1 on purpose and two parts may
# sit on the same texel of DIFFERENT images. Say so, rather than leaving the UV
# gate to measure overlap that cannot mean anything here.
piece["no_atlas"] = True

report = rig.validate(piece, arm)
print("[RIG] Meeb %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("meeb rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "meeb.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: meeb -> %s ===" % GLTF)
