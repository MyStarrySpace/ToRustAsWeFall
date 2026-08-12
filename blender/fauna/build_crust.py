# CRUST — the wall-fused wax colony, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_crust.py
#
# Built against the director's sheets, which are the authority:
#   to-rust-as-we-fall/reference-images/concept/fauna/crust-affordance-concept-01.png
#   to-rust-as-we-fall/reference-images/concept/fauna/crust-turnaround-concept-01.png
#
# The roster: a wax mat fused into broken masonry. One contiguous pore band dilates
# and vents caustic gas, which takes a LANE and not the wall — the player is meant
# to route around the bad span. Only fire clears a stretch, and it grows back.
#
# THE PORES ARE CRATERS BORED INTO THE MAT. Same inversion the Meeb shipped: the
# sheet draws deep hexagonal wells whose inner walls you can see, lit on the upper
# lip and shadowed below, and the old build grew them as cones FLARING OUTWARD
# from the surface — five funnels standing 4.4 cm proud of the face. Nothing
# protrudes from the mat in any panel of the sheet, including the dilated one,
# where the cells glow from inside their wells.
#
# THE BOUNDARY IS ONE FUNCTION AND THE GEOMETRY OBEYS IT. The old mat was a
# rectangle whose ragged outline lived only in the alpha of a card mounted in
# FRONT of it, so the player saw a square panel with a torn sticker on it — and
# the brief's avoid-list opens with "a rectangular machine panel". `_margin_r`
# drives the solid and the paint alike; a card may never be a different shape from
# the thing it dresses.
#
# THE MAT IS THE BRIGHTEST THING ON THE WALL. Pale bone-cream, read as a light
# shape against dark blue-grey masonry, holes dark, and a THIN red oxide seam at
# the fusion boundary. The old palette was inverted — a dark brown slab with the
# only pale note hidden in a sub-texel ring inside each pore — so the warning
# vapour and the mat it warns about were the same hue at 90% of the same value.

import bpy
import bmesh
import importlib
import json
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
GLTF = os.path.join(OUT_DIR, "crust.gltf")
for d in (TEX_DIR, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

SPAN_W = 1.34              # wide enough to deny a wall-hugging lane
SPAN_H = 1.02
RX, RZ = SPAN_W * 0.5, SPAN_H * 0.5
DEPTH = 0.24               # the centre's relief off the wall: a LENS, not a board
LAYERS = 4                 # stacked laminae — the torn margin shows their edges
LAMINA_STEP = 0.035        # how far each lamina pulls in. Small on purpose: the
                           # plateau is what the honeycomb lives on, so every
                           # centimetre the steps eat is a ring of cells the mat
                           # cannot carry, and the sheet's field covers nearly the
                           # whole face
SEG = 72                   # boundary resolution
PITCH = 0.148              # one cell per ~15 cm: ~9 across, as drawn
CELL_R = PITCH * 0.40      # circumradius; the rest of the pitch is SEPTUM, and
                           # the septum is the pale ridge the whole read rests on.
                           # Measured against the sheet, the openings want about
                           # 0.8 of the pitch across corners and 0.72 gave a cream
                           # plate with isolated dots rather than a honeycomb. It
                           # cannot simply be opened up, though: at 0.44 the walls
                           # thin to 2 cm and the wells run together into one
                           # ragged cavity, so this sits between the two.
UV_SCALE = 1.0

# The vent is a CONTIGUOUS cluster left of centre — about a third of the span.
# Scattered across opposite corners of the lattice (which is what shipped) there
# is no un-vented span left, so the "visible bad band" cannot be routed around and
# the whole colony becomes the hazard.
VENT_CELLS = [(-2, 0), (-1, 0), (-2, 1), (-1, 1), (-3, 1), (-2, -1)]

BAND_H = 0.42
BAND_SEG = 3
BAND_Y = -0.30


class Rng:
    def __init__(self, seed):
        self.s = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)

    def f(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((self.s >> 11) & ((1 << 53) - 1)) / float(1 << 53)

    def between(self, a, b):
        return a + (b - a) * self.f()


# ------------------------------------------------------------- the boundary ----
def _margin_r(theta):
    """The ragged lobed edge, as a multiplier on the base ellipse.

    ONE function, used by the solid, by the paint, and by the margin lumps, so the
    geometry's bumps land on the texture's bumps. Deterministic: a colony whose
    outline reshuffles every build cannot be compared against the last render.
    """
    return (1.0
            + 0.16 * math.sin(theta * 3.0 + 0.7)
            + 0.10 * math.sin(theta * 5.0 - 1.9)
            + 0.06 * math.sin(theta * 8.0 + 2.6)
            - 0.05 * math.sin(theta * 2.0 + 0.3))


def _boundary_pt(j, scale=1.0):
    th = math.tau * j / SEG
    m = _margin_r(th) * scale
    return (math.cos(th) * RX * m, math.sin(th) * RZ * m)


def _radial_t(x, z):
    """0 at the centre, 1 on the boundary. What "how far out is this" means."""
    th = math.atan2(z / max(RZ, 1e-6), x / max(RX, 1e-6))
    m = _margin_r(th)
    d = math.hypot(x / RX, z / RZ)
    return d / max(m, 1e-6)


# ONE profile, shared by the solid and by the cutters that bore into it. Described
# twice they drift apart silently: a smooth lens formula against a stepped plateau
# put every cutter's mouth a few millimetres BEHIND the real surface, so most
# cells never opened and the ones that did were shallow nicks.
_SCALES = [1.0 - LAMINA_STEP * i for i in range(LAYERS + 1)]
_DEPTHS = [-DEPTH * (i / float(LAYERS)) for i in range(LAYERS + 1)]


def _front_y(x, z):
    """Where the mat's face actually is at (x, z) — a broad flat plateau that
    steps up to the wall through its laminae near the rim."""
    t = _radial_t(x, z)
    for i in range(LAYERS, -1, -1):
        if t <= _SCALES[i]:
            return _DEPTHS[i]
    return 0.0


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


def _wax(x, y, size):
    """Pale bone-cream — the brightest thing in frame, which is the whole point of
    the value structure. Mottled, because old wax is layered, not moulded."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
    n = (h % 100) / 100.0
    v = 0.80 + 0.11 * n
    return (v, v * 0.955, v * 0.815, 1.0)


def _pore(x, y, size):
    """Inside a well: THE SAME WAX, IN SHADOW — not a different, darker substance.

    Measured against the sheet, a cell interior sits at about 0.69 of the skin's
    value, with the upper inner wall catching light and the floor falling away
    beneath it. Painted as a near-black hole the interior came out at 0.19 of the
    skin, five times too dark, and the field stopped reading as wells sunk into
    wax and started reading as dots printed on it. A hole is dark BECAUSE less
    light reaches it, so it keeps the hue of what it is cut into.
    """
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    # v runs down the tube: lit under the upper lip, darkest at the floor
    t = y / max(1.0, size - 1.0)
    shade = 0.80 - 0.30 * t
    v = (0.80 + 0.11 * n) * shade
    return (v, v * 0.955, v * 0.815, 1.0)


def _rust(x, y, size):
    """The fusion seam: a real red oxide. #42210f is a brown at that luminance and
    read as near-black on the wall, which is why the seam vanished."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.52 + 0.10 * n, 0.20 + 0.06 * n, 0.11 + 0.04 * n, 1.0)


def _acid(x, y, size):
    """The vapour and the lit cell interiors: luminous yellow-green, the most
    saturated thing on the wall and nowhere near the mat's hue."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    n = (h % 100) / 100.0
    return (0.72 + 0.10 * n, 0.90 + 0.08 * n, 0.26 + 0.08 * n, 1.0)


def _scar(x, y, size):
    """Iron-stained masonry behind the mat, so burning a region exposes stained
    wall rather than empty space — without it the burn clip has no payoff."""
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
    n = (h % 100) / 100.0
    if (h >> 8) % 29 == 0:
        return (0.31 + 0.06 * n, 0.16 + 0.04 * n, 0.10, 1.0)
    v = 0.20 + 0.07 * n
    return (v, v * 1.02, v * 1.10, 1.0)


def _haze(x, y, size):
    c = (size - 1) * 0.5
    dx, dy = (x - c) / max(1.0, c), (y - c) / max(1.0, c)
    r = math.hypot(dx, dy)
    h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
    if r > 0.95 or (h % 100) / 100.0 > (1.0 - r) * 1.7:
        return (0.0, 0.0, 0.0, 0.0)
    return (0.74, 0.88, 0.30, 1.0)


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
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
    if cutout or emit is not None:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return mat


# ---------------------------------------------------------------- geometry ----
def mat_bm():
    """The lens, as a STAIRCASE of stacked laminae.

    Each layer is a smaller boundary sitting further off the wall, so the profile
    is centre-thick and the margin exposes three or four layer edges — which is
    what the hero's torn lower-right lobe draws. One closed manifold: the boolean
    that bores the cells has to run on it, and nested overlapping solids are what
    makes EXACT give up.
    """
    bm = bmesh.new()
    # A PLATEAU that steps down only near the rim, never a ziggurat. Taking the
    # radius from 1.0 at the wall to 0.32 at the face leaves the honeycomb crowded
    # onto a small front terrace, and every cell near its edge is cut by a step
    # into a ragged blob instead of a hexagon. The sheet's mat is broad and
    # thick-faced; the stacked laminae show at the TORN MARGIN and nowhere else.
    scales, depths = _SCALES, _DEPTHS

    rings = []
    profile = [(depths[0], scales[0])]
    for i in range(1, LAYERS + 1):
        profile.append((depths[i], scales[i - 1]))    # the vertical rise
        profile.append((depths[i], scales[i]))        # the lamina's exposed face
    for (y, sc) in profile:
        rings.append([bm.verts.new((_boundary_pt(j, sc)[0], y, _boundary_pt(j, sc)[1]))
                      for j in range(SEG)])
    for i in range(len(rings) - 1):
        for j in range(SEG):
            j2 = (j + 1) % SEG
            bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
    # THE FRONT FACE GETS CONCENTRIC RINGS, not one fan out to a hub. A fan across
    # a 72-sided boundary makes triangles a third of the mat long, and their
    # centres land inside the cell seats — so the geometric well-wall selection
    # paints them dark and the mat wears a radial black star. Rings also give the
    # boolean quads to cut instead of slivers.
    face_rings = [rings[-1]]
    inner = _SCALES[-1]
    for step in (0.72, 0.50, 0.28):
        sc = inner * step / 0.72 if step != 0.72 else inner * 0.72
        face_rings.append([bm.verts.new((_boundary_pt(j, sc)[0], depths[-1],
                                         _boundary_pt(j, sc)[1])) for j in range(SEG)])
    for i in range(len(face_rings) - 1):
        for j in range(SEG):
            j2 = (j + 1) % SEG
            bm.faces.new((face_rings[i][j], face_rings[i][j2],
                          face_rings[i + 1][j2], face_rings[i + 1][j]))
    front = bm.verts.new((0.0, depths[-1], 0.0))
    back = bm.verts.new((0.0, 0.0, 0.0))
    for j in range(SEG):
        j2 = (j + 1) % SEG
        bm.faces.new((face_rings[-1][j], face_rings[-1][j2], front))
        bm.faces.new((rings[0][j2], rings[0][j], back))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _cell_xz(q, r):
    """Hex packing in axial coordinates."""
    return (PITCH * (q + r * 0.5), PITCH * r * (3.0 ** 0.5) * 0.5)


def cells():
    """Every cell that fits inside the mat, with margin so none straddles the rim."""
    out = []
    span = int(SPAN_W / PITCH) + 2
    for r in range(-span, span + 1):
        for q in range(-span, span + 1):
            x, z = _cell_xz(q, r)
            # A cell is only admitted if its whole RIM clears the plateau —
            # a centre inside the flat face is not enough, and a cell that
            # overhangs the first lamina is bored across a step and comes out a
            # ragged notch rather than a hexagon.
            if _radial_t(x, z) < _SCALES[-1] - CELL_R / min(RX, RZ):
                out.append((q, r, x, z))
    return out


def cells_bm():
    """Every well in ONE cutter. Unlike the Meeb's converging shafts these are
    separated by septa and never touch, so a single boolean is safe — and it is a
    single boolean rather than forty bakes."""
    bm = bmesh.new()
    for (_q, _r, x, z) in cells():
        fy = _front_y(x, z)
        y_out = fy - 0.04                       # start clear of the surface
        y_in = fy * 0.26                        # stop short: a well has a floor
        # A CHAMFERED MOUTH. The sheet wants openings about 0.8 of the pitch with
        # the septum a narrow PALE RIDGE between them — but simply growing the
        # bore to reach that thins the wall along its whole depth, and this build
        # has already met that failure: past a point the wells run together into
        # one ragged cavity. So the width is bought only where it is seen. The
        # cutter flares at the surface and drops to the shaft radius just inside,
        # which narrows the crest the eye reads while the wall between two shafts
        # keeps the full thickness below it. That is also what puts each well in
        # shadow under its own lip, which is how the sheet draws them.
        inward = 1.0 if y_in > y_out else -1.0
        # The wide station has to sit AT the surface, not above it. Put it only
        # at y_out and the cutter has already tapered by the time it reaches the
        # face — the mouth comes out barely 6% wider instead of 22%, which is a
        # chamfer that exists everywhere except where it is seen.
        stations = ((y_out, CELL_R * 1.22),
                    (fy, CELL_R * 1.22),
                    (fy + inward * 0.022, CELL_R),
                    (y_in, CELL_R * 0.80))
        rows = []
        for y, rr in stations:
            rows.append([bm.verts.new((x + math.cos(math.tau * i / 6 + 0.26) * rr, y,
                                       z + math.sin(math.tau * i / 6 + 0.26) * rr))
                         for i in range(6)])
        for k in range(len(rows) - 1):
            for i in range(6):
                j = (i + 1) % 6
                bm.faces.new((rows[k][i], rows[k][j], rows[k + 1][j], rows[k + 1][i]))
        bm.faces.new(tuple(reversed(rows[0])))
        bm.faces.new(tuple(rows[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bake_boolean(obj, other_mesh, op):
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
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        i, j = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[i] / scale, co[j] / scale)


def append_bm(obj, bm, material_index):
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
    made = [work.verts.new(co) for co in verts]
    work.verts.ensure_lookup_table()
    for p in polys:
        work.faces.new(tuple(made[i] for i in p))
    work.to_mesh(obj.data)
    work.free()
    for p in obj.data.polygons[base_p:]:
        p.material_index = material_index
    return base_v, len(obj.data.vertices)


GLOW_RANGES = []
SCAR_RANGE = [0, 0]
BAND_RANGES = []


def build_crust():
    coll = bpy.context.scene.collection
    me = bpy.data.meshes.new("CrustRigged")
    mat_bm().to_mesh(me)
    obj = bpy.data.objects.new("CrustRigged", me)
    coll.objects.link(obj)

    wax = material("CrustWax", _write_png("crust_wax.png", 48, _wax))
    pore = material("CrustPore", _write_png("crust_pore.png", 32, _pore))
    rust = material("CrustRust", _write_png("crust_rust.png", 32, _rust))
    acid = material("CrustAcid", _write_png("crust_acid.png", 32, _acid), emit=3.2)
    scar = material("CrustScar", _write_png("crust_scar.png", 48, _scar))
    haze = material("CrustHaze", _write_png("crust_haze.png", 32, _haze), cutout=True)
    for m in (wax, pore, rust, acid, scar, haze):
        obj.data.materials.append(m)
    I_WAX, I_PORE, I_RUST, I_ACID, I_SCAR, I_HAZE = range(6)

    before = len(obj.data.polygons)
    bake_boolean(obj, _to_mesh(cells_bm(), "_cells"), "DIFFERENCE")
    if len(obj.data.polygons) <= before:
        raise RuntimeError("the pores did not bore into the mat (%d faces)"
                           % len(obj.data.polygons))

    # THE WELL WALLS ARE DARK. Selected geometrically — the boolean invents these
    # faces and no index survives it. A bore no darker than the skin reads as a
    # printed hex pattern rather than a field of craters.
    seats = [(x, z) for (_q, _r, x, z) in cells()]
    bored = 0
    for p in obj.data.polygons:
        c = p.center
        for (x, z) in seats:
            if math.hypot(c.x - x, c.z - z) >= CELL_R * 1.05:
                continue
            # BEING NEAR A SEAT IS NOT ENOUGH — the septum lip and any face on the
            # mat's front plane pass that test too. A well wall is the geometry
            # that lies DEEPER than the face does here (y runs negative outward),
            # which is the only thing that distinguishes a hole from the skin
            # around it.
            if c.y <= _front_y(x, z) + 0.004:
                continue
            p.material_index = I_PORE
            bored += 1
            break
    if bored < len(seats) * 4:
        raise RuntimeError("well-wall selection found only %d faces for %d cells"
                           % (bored, len(seats)))

    # THE SEAM IS THIN AND RED. A wide rust ZONE is not a seam; only the faces
    # riding the outermost boundary take it.
    for p in obj.data.polygons:
        if p.material_index != I_WAX:
            continue
        c = p.center
        # A SEAM, NOT A BAND. _SCALES steps the plateau at 1.0, .965, .93, .895
        # and .86, so a 0.93 threshold catches the outer THREE laminae — every
        # rise, every exposed face and the boundary wall — and the oxide came out
        # six to ten times the share of the piece the sheet gives it. Above the
        # second step it takes only the outermost rise and the wall it stands on.
        if _radial_t(c.x, c.z) > 0.972:
            p.material_index = I_RUST

    # THE SCAR BEHIND THE MAT, so a burned region exposes stained wall.
    scar_bm = bmesh.new()
    ring = [scar_bm.verts.new((_boundary_pt(j, 1.03)[0], 0.004, _boundary_pt(j, 1.03)[1]))
            for j in range(SEG)]
    hub = scar_bm.verts.new((0.0, 0.004, 0.0))
    for j in range(SEG):
        scar_bm.faces.new((ring[j], ring[(j + 1) % SEG], hub))
    bmesh.ops.recalc_face_normals(scar_bm, faces=scar_bm.faces)
    SCAR_RANGE[0], SCAR_RANGE[1] = append_bm(obj, scar_bm, I_SCAR)

    # THE LIT CELLS. One emissive disc down each VENT cell's well, so the dilated
    # band glows from inside its holes exactly as the sheet draws it, and the rest
    # of the mat stays dark and passable.
    GLOW_RANGES.clear()
    vent_seats = []
    for (q, r, x, z) in cells():
        if (q, r) not in VENT_CELLS:
            continue
        vent_seats.append((x, z))
        fy = _front_y(x, z)
        g = bmesh.new()
        rr = CELL_R * 0.84
        disc = [g.verts.new((x + math.cos(math.tau * i / 6 + 0.26) * rr, fy * 0.42,
                             z + math.sin(math.tau * i / 6 + 0.26) * rr))
                for i in range(6)]
        g.faces.new(tuple(reversed(disc)))
        bmesh.ops.recalc_face_normals(g, faces=g.faces)
        GLOW_RANGES.append(append_bm(obj, g, I_ACID))
    if len(GLOW_RANGES) < 4:
        raise RuntimeError("the vent cluster found only %d cells" % len(GLOW_RANGES))

    # THE HAZE TAKES A LANE, NOT THE WALL. Sized and centred on the cluster it
    # comes out of: spanning the full plate there is no un-vented lane left, and
    # the roster's promise that the bad band can be routed around is broken.
    cx = sum(s[0] for s in vent_seats) / float(len(vent_seats))
    cz = sum(s[1] for s in vent_seats) / float(len(vent_seats))
    band_w = SPAN_W * 0.42
    BAND_RANGES.clear()
    for i in range(BAND_SEG):
        f = (i + 1) / float(BAND_SEG)
        b = bmesh.new()
        hw, hh = band_w * 0.5 * (0.7 + 0.3 * f), BAND_H * 0.5
        y = BAND_Y * f
        quad = [b.verts.new(p) for p in (
            (cx - hw, y, cz - hh), (cx + hw, y, cz - hh),
            (cx + hw, y, cz + hh), (cx - hw, y, cz + hh))]
        b.faces.new(tuple(reversed(quad)))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        BAND_RANGES.append(append_bm(obj, b, I_HAZE))

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
# THE MAT IS PARTITIONED so a region can burn away while the rest survives. The
# old rig carried ONE plate bone, so `crust_burn` could only scale the whole
# colony to nothing: a regional burn was not merely unauthored, it was unriggable,
# and there was no remnant left to read as a scar. The sheet's damaged panel keeps
# two honeycomb clusters standing on either side of the burned-out span.
REGIONS = ["left", "mid", "right"]
REGION_X = {"left": -RX * 0.62, "mid": 0.0, "right": RX * 0.62}


def crust_chains():
    chains = [{"prefix": "mat", "points": [(0.0, 0.0, 0.0), (0.0, 0.006, 0.0)]}]
    for name in REGIONS:
        chains.append({"prefix": name, "parent": "mat_0",
                       "points": [(REGION_X[name], 0.0, 0.0),
                                  (REGION_X[name], -DEPTH, 0.0)]})
    chains.append({"prefix": "vent", "parent": "mid_0",
                   "points": [(0.0, -DEPTH * 0.4, 0.0), (0.0, -DEPTH * 0.8, 0.0)]})
    for i in range(BAND_SEG):
        parent = "vent_0" if i == 0 else "band%d_0" % (i - 1)
        chains.append({"prefix": "band%d" % i, "parent": parent,
                       "points": [(0.0, BAND_Y * (i / float(BAND_SEG)) - 0.01, 0.0),
                                  (0.0, BAND_Y * ((i + 1) / float(BAND_SEG)), 0.0)]})
    return chains


def _region_for(x):
    """Which third of the mat a vertex belongs to. Split on x so a burned region
    is a contiguous span of wall and not a scatter of holes."""
    if x < -RX * 0.28:
        return "left_0"
    if x > RX * 0.28:
        return "right_0"
    return "mid_0"


def weight_by_region(obj, arm):
    """By POSITION, never by index — the boolean rebuilds the mesh from scratch."""
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    tagged = {}
    for i in range(SCAR_RANGE[0], SCAR_RANGE[1]):
        tagged[i] = "mat_0"            # the scar survives the burn, so it is the parent's
    for (v0, v1) in GLOW_RANGES:
        for i in range(v0, v1):
            tagged[i] = "vent_0"
    for k, (v0, v1) in enumerate(BAND_RANGES):
        for i in range(v0, v1):
            tagged[i] = "band%d_0" % k
    for v in obj.data.vertices:
        name = tagged.get(v.index) or _region_for(v.co.x)
        groups[name].add([v.index], 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


piece = build_crust()
arm = rig.build_armature("Crust", crust_chains())
weight_by_region(piece, arm)

ON, OFF = 1.0, 0.001
LIT = 1.0


def _pose(**over):
    out = {"mat_0": 1.0, "vent_0": OFF}
    for name in REGIONS:
        out["%s_0" % name] = 1.0
    for i in range(BAND_SEG):
        out["band%d_0" % i] = OFF
    out.update(over)
    return out


# DILATE: the warning. The cluster's wells light from inside and the vapour climbs
# off them a segment at a time, so the hazard grows into its lane rather than
# appearing whole. The mat itself never moves — the tell is the light.
rig.clip(arm, "crust_dilate", [
    (0.0, _pose()),
    (0.35, _pose(vent_0=0.45)),
    (0.7, _pose(vent_0=LIT)),
    (1.0, _pose(vent_0=LIT, band0_0=ON)),
    (1.3, _pose(vent_0=LIT, band0_0=ON, band1_0=ON)),
    (1.7, _pose(vent_0=LIT, band0_0=ON, band1_0=ON, band2_0=ON)),
])

# BURN: fire clears a STRETCH. One region flakes to the stained wall behind it and
# the other two hold — the sheet's damaged panel is not an absent colony, it is a
# burned-out span with honeycomb still standing either side of it. The vapour dies
# with the region that was making it.
rig.clip(arm, "crust_burn", [
    (0.0, _pose(vent_0=LIT, band0_0=ON, band1_0=ON, band2_0=ON)),
    (0.3, _pose(left_0=0.82, vent_0=0.4)),
    (0.8, _pose(left_0=0.35)),
    (1.3, _pose(left_0=OFF)),
])

# REGROW: "and it grows back." The honest reverse of the burn, which is only
# honest now that the burn is regional — reversing a whole-colony collapse would
# be the mat popping back into existence rather than a margin creeping across.
rig.clip(arm, "crust_regrow", [
    (0.0, _pose(left_0=OFF)),
    (1.4, _pose(left_0=0.42)),
    (2.6, _pose()),
])
rig.park(arm, _pose())

report = rig.validate(piece, arm)
print("[RIG] Crust %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("crust rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "crust.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: crust -> %s ===" % GLTF)
