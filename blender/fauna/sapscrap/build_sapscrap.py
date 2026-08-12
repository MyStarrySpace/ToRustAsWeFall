"""Sapscrap v2 - one merged body, socketed limbs, organic collar, curved fangs.

Revision of the surveyed build (see survey_sapscrap.py for the numbers):
  - The limb and horn SLEEVES are boolean-UNIONED into the shell: one continuous
    body mesh. Their root rings sink INTO the surface so each junction reads as
    a recessed socket, not an onion bulge.
  - Claws overlap into their sleeve tips - no disc gap at the wrist.
  - The maw collar is a lofted rolled LIP with seeded jitter - organic, not a
    machined cone.
  - Teeth are two-segment curved fangs with varied lengths.

Rigging note: because the sleeves are merged, the shell mesh is weighted by
REGION in rig_sapscrap.py (body / arm L / arm R / horn capsules), all still
rigid 1.0 weights.

Blender space: +X right, +Y rearward (maw faces -Y), +Z up, ground Z=0.
"""
import bpy
import bmesh
import importlib
import math
import os
import sys
from mathutils import Vector, Matrix

_BL = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "..", ".."))
if _BL not in sys.path:
    sys.path.insert(0, _BL)
from paintlib import graft  # noqa: E402
importlib.reload(graft)

COLLECTION = "Sapscrap"
ROOT = "SapscrapRoot"
TEX_DIR = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
           "resources/models/fauna/sapscrap")

H = 0.95
UV_SCALE = 2.2
ROOT_Y_OFFSET = -0.30

SHELL_R = (0.415, 0.470, 0.460)
_dz = (0.435 - 0.460) / 0.460
MAW_SURF_Y = -0.470 * math.sqrt(max(0.0, 1.0 - _dz * _dz))
MAW_C = (0.0, MAW_SURF_Y, 0.435)
MAW_OUTER = 0.295
MAW_THROAT = 0.190
N_TEETH = 13
LIMB_ATTACH_Z = 0.42
CLAW_SPLAY = 0.60


def LIMB_BASE(sgn):
    return (sgn * 0.30 * H, -0.24 * H, LIMB_ATTACH_Z * H)


def LIMB_TIP(sgn):
    return (sgn * CLAW_SPLAY * H, -0.32 * H, 0.13 * H)


# the dorsal limb FACES FORWARD like the front pair (director): the sleeve
# tips up-forward off the crown and its claw hooks forward-down
HORN_BASE = (0.0, 0.06 * H, SHELL_R[2] * H * 1.60)
HORN_TIP = (0.0, -0.38 * H, 0.90 * H)


class Rng:
    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)

    def f(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((self.s >> 11) & ((1 << 53) - 1)) / float(1 << 53)

    def between(self, a, b):
        return a + (b - a) * self.f()


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


def _image(fn):
    path = os.path.join(TEX_DIR, fn)
    img = bpy.data.images.get(fn)
    if img is None:
        img = bpy.data.images.load(path, check_existing=True)
    else:
        img.filepath = path
        img.reload()
    img.name = fn
    return img


def material(name, albedo):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.82
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-620, 120)
    tex.image = _image(albedo)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
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


def finish(bm, name, mat, coll, parent, loc=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    mesh.update()
    box_uv(mesh)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.parent = parent
    obj.location = loc
    return obj


def on_shell(px, py, pz, sink=0.0):
    """Project a body-local point onto the sagged shell ellipsoid; positive
    sink pushes INSIDE the surface (socket recess)."""
    cx, cy, cz = 0.0, 0.0, SHELL_R[2] * H
    dx, dy, dz = px - cx, py - cy, pz - cz
    rx, ry, rz = SHELL_R[0] * H, SHELL_R[1] * H, SHELL_R[2] * H
    t = (dx * dx / (rx * rx) + dy * dy / (ry * ry) + dz * dz / (rz * rz)) ** 0.5
    if t < 1e-9:
        return (px, py, pz)
    k = (1.0 - sink / max(rx, ry, rz)) / t
    return (cx + dx * k, cy + dy * k, cz + dz * k)


def limb_bm(base_pt, tip_pt, radii, kind, seed, sink=0.10):
    """A WHOLE LIMB as one lofted tube: nub and claw sharing their rings.

    The claw used to be its own tube overlapping the nub's, boolean-unioned in.
    A boolean joins the volumes but leaves the two surfaces crossing each other,
    so the claw reads as clipping THROUGH the arm rather than growing out of it —
    which is exactly what it is doing.

    Here the claw's first ring IS the nub's last ring. The stations continue
    along the claw's own polyline from the point the nub stops at, so there is no
    seam to cross: one surface, from the shell to the claw's point.

    The radii swell before the wrist and taper after it, which is the bulge the
    reference draws at the end of each nub — the shape that lets the limb be
    SHORT and still read as an arm with a hand on it.
    """
    rng = Rng(seed)
    base = Vector(on_shell(*base_pt, sink=sink))
    tip = Vector(tip_pt)
    NS = 9

    # the nub's own run: base to tip, swelling to a bulge just short of the wrist
    pts = []
    rr = []
    n_seg = len(radii) - 1
    for i, r in enumerate(radii):
        pts.append(base.lerp(tip, i / float(n_seg)))
        rr.append(r)

    # and then the claw, continuing from the SAME point the nub ended on
    claw_radii = ([0.056 * H, 0.034 * H, 0.016 * H, 0.007 * H] if kind == "horn"
                  else [0.062 * H, 0.042 * H, 0.020 * H, 0.008 * H])
    p = tip
    for dv, r in zip(claw_steps(kind), claw_radii):
        p = p + Vector(dv) * rng.between(0.95, 1.05)
        pts.append(p)
        rr.append(r)

    bm = bmesh.new()
    rows = []
    for i, (pt, r) in enumerate(zip(pts, rr)):
        if i == 0:
            d = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            d = (pts[-1] - pts[-2]).normalized()
        else:
            d = ((pts[i + 1] - pts[i]).normalized()
                 + (pts[i] - pts[i - 1]).normalized()).normalized()
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        ring = []
        for k in range(NS):
            a = 2.0 * math.pi * k / NS
            jr = 1.0 + rng.between(-0.04, 0.04)
            local = Vector((math.cos(a) * r * jr, math.sin(a) * r * jr, 0.0))
            ring.append(bm.verts.new((q @ local) + pt))
        rows.append(ring)
    for i in range(len(rows) - 1):
        for k in range(NS):
            k2 = (k + 1) % NS
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    bm.faces.new(tuple(reversed(rows[0])))
    bm.faces.new(tuple(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def taper_segment(bm, p0, p1, r0, r1, seg=6):
    d = (p1 - p0)
    ln = d.length
    q = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    t = bmesh.new()
    bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r0, radius2=r1, depth=ln)
    for v in t.verts:
        v.co.z += ln * 0.5
        v.co = q @ v.co
        v.co += p0
    me = bpy.data.meshes.new("_s")
    t.to_mesh(me)
    t.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def bake_boolean(obj, other_mesh, op):
    """Apply one boolean op against a temp object and bake it down.

    The operand object gets obj's WORLD transform: booleans evaluate operands
    in world space, so an operand left at the origin lands displaced by obj's
    parent offset in local space (every sleeve and the maw cutter once drifted
    0.30 rearward this way - floating horn, internal maw cavity, orphan claws).
    """
    tmp = bpy.data.objects.new("_boolop", other_mesh)
    obj.users_collection[0].objects.link(tmp)
    bpy.context.view_layer.update()
    tmp.matrix_world = obj.matrix_world.copy()
    mod = obj.modifiers.new("B", "BOOLEAN")
    mod.operation = op
    mod.object = tmp
    mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    baked = bpy.data.meshes.new_from_object(ev)
    obj.modifiers.remove(mod)
    obj.data = baked
    bpy.data.objects.remove(tmp, do_unlink=True)


def build_body(mat, void_mat, coll, parent):
    """The merged body: sagged faceted shell + UNIONed limb and horn sleeves,
    then the maw carved in and its bore painted dark."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    rngj = Rng(777)
    for v in bm.verts:
        v.co *= 1.0 + (rngj.f() - 0.5) * 0.06
    for v in bm.verts:
        v.co.x *= SHELL_R[0] * H
        v.co.y *= SHELL_R[1] * H
        v.co.z *= SHELL_R[2] * H
        v.co.z += SHELL_R[2] * H
    top = SHELL_R[2] * H * 2.0
    for v in bm.verts:
        t = max(0.0, min(1.0, v.co.z / top))
        bulge = 1.0 + 0.13 * math.exp(-((t - 0.40) / 0.26) ** 2) - 0.11 * (t ** 2)
        v.co.x *= bulge
        v.co.y *= bulge
        if v.co.z < 0.055 * H:
            v.co.z = 0.055 * H * (0.35 + 0.65 * (v.co.z / (0.055 * H)))
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(10.0),
                             verts=bm.verts, edges=bm.edges)

    obj = finish(bm, "Sapscrap_Segment_Shell", mat, coll, parent)

    # ---- UNION the sleeves: one continuous body -------------------------
    sleeves = bmesh.new()
    for sgn in (-1.0, 1.0):
        # the profile BULGES at 0.155 before necking to the wrist: that swelling
        # is what the reference puts at the end of each nub
        sb = limb_bm(LIMB_BASE(sgn), LIMB_TIP(sgn),
                     [0.130 * H, 0.118 * H, 0.155 * H, 0.092 * H],
                     sgn, seed=91 if sgn < 0 else 92)
        me = bpy.data.meshes.new("_sl")
        sb.to_mesh(me)
        sb.free()
        sleeves.from_mesh(me)
        bpy.data.meshes.remove(me)
    hb = limb_bm(HORN_BASE, HORN_TIP, [0.115 * H, 0.105 * H, 0.138 * H],
                 "horn", seed=93)
    me = bpy.data.meshes.new("_h")
    hb.to_mesh(me)
    hb.free()
    sleeves.from_mesh(me)
    bpy.data.meshes.remove(me)
    sl_mesh = bpy.data.meshes.new("_sleeves")
    sleeves.to_mesh(sl_mesh)
    sleeves.free()
    bake_boolean(obj, sl_mesh, "UNION")



    # ---- the maw: ONE aperture, lip out of it and throat into it ----------
    #
    # MEASURED ON THE INTACT SHELL. A boolean carve eats the outer skin first, so
    # anything measuring afterwards finds the pocket's BACK WALL and seats the
    # mouth deep inside the head — which is exactly what happened attempting this
    # against the live file. Cut once, then grow both directions from the ring the
    # cut leaves, so the lip and the throat share the body's own edge loop.
    work = bmesh.new()
    work.from_mesh(obj.data)
    work.normal_update()
    AX = Vector((0.0, -1.0, 0.0))
    zc = MAW_C[2] * H
    seat = graft.surface_hit(work, (0.0, 0.25 * H, zc), tuple(AX))
    if seat is None:
        raise RuntimeError("the maw could not find the shell to open")
    n = N_TEETH * 2
    # ONE CHAIN, never a branch. The aperture's ring already carries the zipper
    # that ties it to the skin, so bridging BOTH a lip and a throat off it gives
    # every edge on that ring three faces — twenty-six non-manifold edges, which
    # is a mouth that no longer describes a surface. A real mouth is one continuous
    # run: skin, out over the lip's crest, back to the rim, and down the throat.
    # So the hole is cut at the LIP'S outer extent and the profile does the rest.
    mouth = graft.aperture(work, tuple(seat), tuple(AX), MAW_THROAT * H * 1.62, n)
    if mouth is None:
        raise RuntimeError("the maw aperture opened nothing")

    PROFILE = [
        (1.44, 0.030),      # out of the skin and forward
        (1.22, 0.064),
        (1.06, 0.054),      # over the crest, turning back toward the throat
        (1.00, 0.018),      # the rim itself
        (0.92, -0.10 * H),  # and in
        (0.66, -0.26 * H),
        (0.34, -0.44 * H),
        (0.12, -0.58 * H),
    ]
    prev = mouth
    for (mult, off) in PROFILE:
        nxt = graft.ring(work, tuple(Vector(seat) + AX * off), tuple(AX),
                         MAW_THROAT * H * mult, n)
        graft.bridge(work, prev, nxt, flip=True)
        prev = nxt
    work.faces.new(tuple(prev))
    bmesh.ops.recalc_face_normals(work, faces=work.faces)
    graft.seal_stragglers(work)
    graft.assert_welded(work, "Sapscrap shell")

    work.to_mesh(obj.data)
    work.free()
    box_uv(obj.data)
    for poly in obj.data.polygons:
        poly.use_smooth = False

    # ---- bore walls get the void material -------------------------------
    for i in reversed(range(len(obj.data.materials))):
        if obj.data.materials[i] is None:
            obj.data.materials.pop(index=i)
    obj.data.materials.append(void_mat)
    void_idx = next(i for i, m in enumerate(obj.data.materials) if m == void_mat)
    # THE THROAT'S OWN WALLS, taken from where the graft actually put them rather
    # than from the cutter that no longer exists. The band runs from the rim back
    # to the gullet, and the radius is the throat's, not the lip's — paint the lip
    # dark and the mouth stops reading as a hole in a face and starts reading as a
    # black ring drawn on one.
    cz = MAW_C[2] * H
    y_lo, y_hi = seat.y - 0.01 * H, seat.y + 0.62 * H
    lit = 0
    for pl in obj.data.polygons:
        c = pl.center
        if math.hypot(c.x, c.z - cz) < MAW_THROAT * H * 1.10 and y_lo < c.y < y_hi:
            pl.material_index = void_idx
            lit += 1
    if not 6 <= lit <= 220:
        raise RuntimeError("bore selection looks wrong: %d faces" % lit)

    # one continuous body: the union must leave NO disjoint islands
    parent_of = list(range(len(obj.data.vertices)))

    def find(a):
        while parent_of[a] != a:
            parent_of[a] = parent_of[parent_of[a]]
            a = parent_of[a]
        return a

    for e in obj.data.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent_of[a] = b
    islands = len({find(i) for i in range(len(obj.data.vertices))})


    if islands != 1:
        raise RuntimeError("shell has %d islands - a boolean drifted" % islands)
    return obj


def build_gullet_cap(void_mat, coll, parent):
    cap = bmesh.new()
    bmesh.ops.create_circle(cap, cap_ends=True, segments=N_TEETH * 2, radius=0.06 * H)
    rot = Matrix.Rotation(math.radians(-90.0), 4, "X")
    for v in cap.verts:
        v.co = rot @ v.co
    return finish(cap, "Sapscrap_MouthVoid", void_mat, coll, parent,
                  loc=(0.0, MAW_C[1] * H + 0.60 * H, MAW_C[2] * H))


def build_collar(mat, coll, parent):
    """The maw lip as a lofted ROLLED cross-section: rooted on the shell, it
    swells, crests, and rolls back toward the throat. Seeded jitter keeps it
    organic instead of machined."""
    rng = Rng(4141)
    n = N_TEETH * 2
    # THE LIP HAS TO GROW OUT OF THE BODY, NOT SIT ON IT. This began at the bore's
    # own radius already standing 0.115 proud of the shell, so the maw met the
    # body on a hard circular step and read as a ring bolted to a head. The
    # profile now starts WIDE and FLUSH -- on the shell surface, well outside the
    # bore -- and only lifts once it is under way, so the body flows into the lip
    # across a band instead of meeting it at an edge.
    profile = [
        (1.62, 0.000),
        (1.38, 0.018),
        (1.18, 0.062),
        (1.04, 0.108),
        (1.06, 0.040),
        (1.01, -0.022),
        (0.87, -0.058),
        (0.73, -0.034),
        (0.67, 0.018),
    ]
    rings = []
    for rf, yo in profile:
        ring = []
        for k in range(n):
            a = 2.0 * math.pi * k / n
            jr = 1.0 + rng.between(-0.035, 0.035)
            x = math.cos(a) * MAW_OUTER * H * rf * jr
            z = math.sin(a) * MAW_OUTER * H * rf * jr + MAW_C[2] * H
            sy = on_shell(x, MAW_C[1] * H, z, sink=0.0)[1]
            ring.append((x, sy + yo * H + rng.between(-0.006, 0.006) * H, z))
        rings.append(ring)
    bm = bmesh.new()
    vrows = [[bm.verts.new(p) for p in ring] for ring in rings]
    for r in range(len(vrows) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((vrows[r][k], vrows[r][k2],
                          vrows[r + 1][k2], vrows[r + 1][k]))
    return finish(bm, "Sapscrap_Mouth_Ring", mat, coll, parent)


def build_teeth(mat, coll, parent):
    """Curved two-segment fangs, varied lengths, roots sunk into the collar."""
    rng = Rng(2727)
    bm = bmesh.new()
    r_ring = MAW_THROAT * H * 1.12
    for k in range(N_TEETH):
        a = 2.0 * math.pi * k / N_TEETH + math.pi / N_TEETH
        cx, cz = math.cos(a) * r_ring, math.sin(a) * r_ring
        inward = Vector((-math.cos(a), 0.0, -math.sin(a)))
        length = 0.085 * H * rng.between(0.85, 1.15)
        root = Vector((cx, 0.020 * H, cz))
        mid = root + Vector((0.0, -length * 0.45, 0.0)) + inward * (length * 0.18)
        tip = mid + Vector((0.0, -length * 0.55, 0.0)) + inward * (length * 0.42)
        r0 = 0.030 * H * rng.between(0.9, 1.1)
        taper_segment(bm, root, mid, r0, r0 * 0.55, seg=6)
        taper_segment(bm, mid, tip, r0 * 0.55, r0 * 0.10, seg=6)
    return finish(bm, "Sapscrap_Teeth", mat, coll, parent,
                  loc=(0.0, MAW_C[1] * H + 0.010 * H, MAW_C[2] * H))


def claw_steps(kind):
    """The claw's segment displacements, in build order. ONE definition, used to
    build the claw and to place the bone that drives it — a second copy of these
    numbers anywhere is a claw that animates off its own geometry."""
    if kind == "horn":
        return [(0.0, -0.070 * H, 0.050 * H), (0.0, -0.078 * H, 0.010 * H),
                (0.0, -0.055 * H, -0.038 * H), (0.0, -0.028 * H, -0.030 * H)]
    sgn = kind
    return [(sgn * 0.070 * H, -0.030 * H, -0.075 * H),
            (sgn * 0.030 * H, -0.045 * H, -0.070 * H),
            (-sgn * 0.045 * H, -0.045 * H, -0.030 * H),
            (-sgn * 0.030 * H, -0.020 * H, -0.008 * H)]


def claw_reach(kind):
    """Where a claw ENDS relative to the sleeve tip it grows from."""
    dx = sum(v[0] for v in claw_steps(kind))
    dy = sum(v[1] for v in claw_steps(kind))
    dz = sum(v[2] for v in claw_steps(kind))
    return (dx, dy, dz)


def claw_bm(kind, base_pt, tip_pt, seed):
    """The claw at a nub's tip, as ONE manifold loft to be unioned into the body.

    It used to be its own object merely overlapping the sleeve, which reads as
    exactly what it was: two parts pushed into each other, with a seam at the
    wrist from every angle that catches it. A limb is one continuous piece.

    It is a single closed tube for the reason sleeve_bm already gives: a stack of
    overlapping cones self-intersects, and the EXACT solver refuses to union it —
    the first attempt at this left twelve loose segments floating beside the body.
    So the claw's steps become stations on a polyline and the rings between them
    are bridged, exactly as a sleeve is.
    """
    rng = Rng(seed)
    base = Vector(on_shell(*base_pt, sink=0.10))
    tip = Vector(tip_pt)
    axis = (tip - base).normalized()
    radii = ([0.056 * H, 0.034 * H, 0.016 * H, 0.007 * H] if kind == "horn"
             else [0.062 * H, 0.042 * H, 0.020 * H, 0.008 * H])
    # start seated INSIDE the sleeve so the union has something to bite on
    pts = [tip - axis * 0.085 * H]
    rr = [0.092 * H]
    p = pts[0]
    for dv, r in zip(claw_steps(kind), radii):
        p = p + Vector(dv) * rng.between(0.95, 1.05)
        pts.append(p)
        rr.append(r)

    NS = 8
    bm = bmesh.new()
    rows = []
    for i, (pt, r) in enumerate(zip(pts, rr)):
        if i == 0:
            d = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            d = (pts[-1] - pts[-2]).normalized()
        else:
            d = ((pts[i + 1] - pts[i]).normalized()
                 + (pts[i] - pts[i - 1]).normalized()).normalized()
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        ring = []
        for k in range(NS):
            a = 2.0 * math.pi * k / NS
            local = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
            ring.append(bm.verts.new((q @ local) + pt))
        rows.append(ring)
    for i in range(len(rows) - 1):
        for k in range(NS):
            k2 = (k + 1) % NS
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    bm.faces.new(tuple(reversed(rows[0])))
    bm.faces.new(tuple(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def main():
    coll = wipe()
    shell = material("SapscrapShell", "sapscrap_shell.png")
    claw = material("SapscrapClaw", "sapscrap_claw.png")
    void = material("SapscrapMouthVoid", "sapscrap_mouth.png")

    root = bpy.data.objects.new(ROOT, None)
    coll.objects.link(root)
    root.location.y = ROOT_Y_OFFSET

    build_body(shell, void, coll, root)
    # THE LIP AND THE GULLET ARE PART OF THE SHELL NOW. They were separate objects
    # sharing no vertex with the body: an open-ended funnel whose outer rim measured
    # 0.45 m across, floating in front of a head that had no mouth hole in it at
    # all. Both are grown from the aperture's own ring inside build_body, so there
    # is nothing left for them to float against.
    build_teeth(claw, coll, root)
    # the claws are part of the shell now, unioned in by build_body

    for o in coll.objects:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            wz = o.location.z + v.co.z
            if wz < 0.0:
                v.co.z -= wz
        o.data.update()

    bpy.context.view_layer.update()

    # THE LIMBS MUST BE ONE PIECE. The old check proved three separate claw
    # objects were touching the body; a single island proves they are it.
    sh = bpy.data.objects["Sapscrap_Segment_Shell"]
    seen = set()
    groups = 0
    adj = {}
    for poly in sh.data.polygons:
        vs = list(poly.vertices)
        for a in vs:
            adj.setdefault(a, set()).update(vs)
    for start in adj:
        if start in seen:
            continue
        groups += 1
        stack = [start]
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            stack.extend(adj[n] - seen)
    if groups != 1:
        raise RuntimeError("the body is %d islands - a claw did not merge" % groups)

    meshes = [o for o in coll.objects if o.type == "MESH"]
    zmin = min((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
    if zmin > 1e-4:
        for o in meshes:
            for v in o.data.vertices:
                v.co.z -= zmin
            o.data.update()
    bpy.context.view_layer.update()
    xs, ys, zs = [], [], []
    for o in meshes:
        for cnr in o.bound_box:
            v = o.matrix_world @ Vector(cnr)
            xs.append(v.x); ys.append(v.y); zs.append(v.z)
    w, l, h = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
    return {"meshes": len(meshes), "names": sorted(o.name for o in meshes),
            "polys": sum(len(o.data.polygons) for o in meshes),
            "bounds_m": {"w": round(w, 3), "l": round(l, 3), "h": round(h, 3)},
            "min_z": round(min(zs), 4)}


result = main()
