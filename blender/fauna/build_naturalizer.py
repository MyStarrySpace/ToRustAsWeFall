# NATURALIZER — the enforcement patrol, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_naturalizer.py
#
# Built against the director's sheets, which are the authority:
#   .../concept/fauna/naturalizers-v2.png  (and naturalizers.png)
#
# Both sheets draw the same animal: a broad ground-hugging quadruped, wider than
# it is tall, wearing a slate-blue faceted carapace whose panels are WINDOWS onto
# packed fields of glowing amber granules. Four short splayed legs ending in pale
# bone-tan claws. A tapered snout carrying a gold ring, and at its end the one
# bright point the whole animal is built around.
#
# The roster names its tell exactly: "Granules pack toward one bright point before
# the strike." The sheets say where that point is — the lit snout tip — and where
# the granules live before they get there: the shell windows. So the tell is a
# WAVE. The fields go out back-to-front and the tip comes up as they do, which
# reads as the light travelling forward through the animal and arriving at the
# thing it is about to touch. It is short, because naturalizer.gd holds the windup
# for 0.35 s and no longer.
#
# The granule fields are DRAWN. Each is a couple of hundred packed spheres on the
# sheet, and modelling that spends triangles to get a worse read at gameplay
# distance; what holds the form — the carapace, the legs, the snout — stays mesh.

import bpy
import importlib
import json
import math
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder
from paintlib import rig
from paintlib import graft
from mathutils import Vector
importlib.reload(rig)

SRC = os.path.join(BL, "fauna")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "naturalizer.gltf")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

PAL = json.load(open(os.path.join(ROOT, "to-rust-as-we-fall", "data", "palettes",
                                  "level_palettes.json"), encoding="utf-8"))


def C(level, role):
    node = PAL[level]
    for part in role.split("/"):
        node = node[part]
    h = node.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def CS(role): return C("species", role)
def CH(role): return C("channels", role)
def _dim(c, f): return tuple(min(1.0, v * f) for v in c)


# The animal is WIDER THAN TALL — that is the first thing the sheet says and the
# thing the old build had backwards, so it is stated as a ratio and not a guess.
SHELL_R = 0.46             # the carapace at its widest
SHELL_FLOOR = 0.17         # underside; the legs carry it this far off the ground
SHELL_TOP = 0.55           # crown of the dome
SIDES = 9                  # faceted, not smooth — the sheet's plates read as flats
LEGS = 4
FIELDS = 9                 # granule windows in the shell. Five, ranked along one
                           # arc, put every window on one flank and left the other
                           # side of the carapace bare — the sheet sets them over
                           # the WHOLE shell
SNOUT_Y = -0.44            # where the snout leaves the shell
SNOUT_TIP = -0.78

FIELD_START = []
LEG_START = []
SNOUT_START = 0
TIP_START = 0


SHELL_RINGS = [(SHELL_FLOOR, SHELL_R * 0.94), (SHELL_FLOOR + 0.09, SHELL_R),
               (SHELL_FLOOR + 0.185, SHELL_R * 0.978),
               (SHELL_FLOOR + 0.205, SHELL_R * 0.970),
               (SHELL_FLOOR + 0.30, SHELL_R * 0.76), (SHELL_TOP, SHELL_R * 0.40)]


def _shell_r(z):
    """The carapace radius at height `z`, read off the rings the shell is lofted
    from. Windows used to sit at a radius typed in by hand — 0.50 to 0.56 of
    SHELL_R — while the shell at their height is 0.76 to 0.98 of it, so they were
    INSIDE the body and surfaced only where the dome curved past them. That is why
    they read edge-on as needle slivers crossing the plate seams."""
    if z <= SHELL_RINGS[0][0]:
        return SHELL_RINGS[0][1]
    for (z0, r0), (z1, r1) in zip(SHELL_RINGS, SHELL_RINGS[1:]):
        if z <= z1:
            t = (z - z0) / (z1 - z0) if z1 > z0 else 0.0
            return r0 + (r1 - r0) * t
    return SHELL_RINGS[-1][1]


GOLDEN = math.pi * (3.0 - math.sqrt(5.0))


def _shell_normal(a, z):
    """The carapace's outward normal at azimuth `a`, height `z`."""
    dz = 0.03
    slope = (_shell_r(z + dz) - _shell_r(z - dz)) / (2.0 * dz)
    theta = math.atan2(-slope, 1.0)
    ct, st = math.cos(theta), math.sin(theta)
    return (math.sin(a) * ct, math.cos(a) * ct, st)


def _lie_on_shell(a, z):
    """The Euler that lays an axis='Z' card flat on the carapace at azimuth `a`.

    Builder.card builds the quad in the XY plane and rotates it by Rz @ Ry @ Rx,
    so its normal comes out (cos rz * sin ry, sin rz * sin ry, cos ry). Setting
    that equal to a surface normal at azimuth `a` and elevation `theta` gives
    ry = pi/2 - theta and rz = pi/2 - a. Passing (0, theta, a) instead — which is
    the obvious guess and the one I made — points every card somewhere arbitrary,
    which is why they rendered as slivers standing off the shell.
    """
    dz = 0.03
    slope = (_shell_r(z + dz) - _shell_r(z - dz)) / (2.0 * dz)
    theta = math.atan2(-slope, 1.0)          # the normal's rise above horizontal
    return (0.0, math.pi * 0.5 - theta, math.pi * 0.5 - a)


def _field_at(k):
    """Where a granule window sits on the carapace, and which way it faces.

    Both sheets put windows over the WHOLE shell — the bed bounding box spans
    about 95% of body height and width, wrapping the crown, down both flanks and
    round the rear skirt, each isolated by a band of blue. Ranked along one arc
    near the crown, the measured band profile was 24/59/61/40/13/9/9/6/0/0: the
    entire lower shell, the front dome and both flanks below the mid-line carried
    nothing, and the windows piled into one overlapping amber mass. Heights now
    run the shell's useful span and the golden angle throws successive windows to
    opposite sides.
    """
    if k == FIELDS - 1:
        return ((0.0, -SHELL_R * 0.10, SHELL_TOP - 0.055), (0.0, 0.0, 0.0),
                True, (0.0, 0.0, 1.0))
    ring = FIELDS - 1
    t = (k + 0.5) / ring
    z = SHELL_TOP - 0.085 - t * (SHELL_TOP - SHELL_FLOOR - 0.145)
    a = GOLDEN * k + 0.35
    rr = _shell_r(z) * 0.965              # just proud of the skin, not floating
    return ((math.sin(a) * rr, math.cos(a) * rr, z), _lie_on_shell(a, z),
            False, _shell_normal(a, z))


def _hip(i):
    a = math.tau * (i + 0.5) / LEGS + math.pi * 0.25
    return (math.sin(a) * SHELL_R * 0.80, math.cos(a) * SHELL_R * 0.72, SHELL_FLOOR + 0.04)


def _knee(i):
    a = math.tau * (i + 0.5) / LEGS + math.pi * 0.25
    return (math.sin(a) * SHELL_R * 1.22, math.cos(a) * SHELL_R * 1.02, SHELL_FLOOR - 0.05)


def _foot(i):
    a = math.tau * (i + 0.5) / LEGS + math.pi * 0.25
    return (math.sin(a) * SHELL_R * 1.34, math.cos(a) * SHELL_R * 1.12, 0.028)


def _make_granule_art(seed):
    """One shell window: packed amber beads behind a dark rim.

    Two things had to change from the first version, both named by the audit.

    The beads sat on a rigid axis-aligned lattice — `int(x / 3)` — and took their
    colour from a per-cell hash, so alternating light and dark cells in square rows
    read as a woven CHECKERBOARD however round each cell was shaded. Rows are now
    offset half a cell like real packing, each bead centre is jittered off its
    lattice point, and the colour spread is much narrower with a bright HIGHLIGHT
    texel doing the work instead. At 19x21 texels a bead is about 3 across and a
    1-texel highlight is perfectly drawable, which is what the sheet shows.

    And every window was the SAME stamp — the eight islands were byte-identical, so
    the shell read as a repeated decal rather than an organism. Each window now
    takes its own seed, which moves the packing, shifts the hot centre off middle,
    and varies the lozenge's aspect, the way no two beds match on either sheet.
    """
    rs = (seed * 2654435761) & 0xFFFFFFFF

    def _rand(n):
        h = (n * 2246822519 ^ rs) & 0xFFFFFFFF
        h = (h ^ (h >> 13)) * 3266489917 & 0xFFFFFFFF
        return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

    def _granule_art(tile, isl, px_per_m):
        ph, pw = tile.shape[:2]
        emit = isl.get("emit") if isinstance(isl, dict) else None
        cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
        # each bed its own shape and its own bright spot, never the same twice
        rx = pw * (0.42 + 0.06 * _rand(1))
        ry = ph * (0.42 + 0.06 * _rand(2))
        hx, hy = (_rand(3) - 0.5) * 0.5, (_rand(4) - 0.5) * 0.5
        hot = CS("flure_core")
        warm = CH("lamp")
        deep = _dim(CH("rust"), 1.15)
        rim = _dim(CH("iron_dark"), 1.4)
        tile[:, :, 3] = 0.0

        # THROW the beads, do not rank them. A jittered lattice is still a
        # lattice: staggering odd rows and nudging each centre a quarter-cell only
        # took the 3-px repeat from 0.498 to 0.429, so the weave survived. Beads
        # are dart-thrown against a minimum separation instead, which is what
        # packing actually looks like and what kills the row-and-column read.
        beads = []
        tries = 0
        while len(beads) < 44 and tries < 900:
            tries += 1
            bxn = _rand(tries * 7 + 21) * pw
            byn = _rand(tries * 13 + 37) * ph
            u, v = (bxn - cx) / rx, (byn - cy) / ry
            if u * u + v * v > 0.86:
                continue
            if any((bxn - ox) ** 2 + (byn - oy) ** 2 < 4.4 for ox, oy, _ in beads):
                continue
            beads.append((bxn, byn, _rand(tries * 5 + 3)))

        for y in range(ph):
            for x in range(pw):
                u, v = (x - cx) / rx, (y - cy) / ry
                d = u * u + v * v
                if d > 1.0:
                    continue                  # outside the lozenge: the card is cut
                tile[y, x, 3] = 1.0
                if d > 0.80:
                    # THE LIP IS LIT BY THE FIELD IT CLOSES OVER. On both sheets
                    # each bed throws warm light onto its own window rim; the mask
                    # used to stop dead at the bed silhouette and cut to pure
                    # black here, so the one place the glow was supposed to show
                    # was the one place carrying no emission at all. The lip takes
                    # a warm value falling off outward to the card edge.
                    edge = (d - 0.80) / 0.20
                    tile[y, x, :3] = _dim(rim, 1.0 + 0.30 * (1.0 - edge))
                    if emit is not None:
                        emit[y, x] = _dim(warm, 0.34 * (1.0 - edge) ** 2)
                    continue
                best, bx, by, bt = 1e9, 0.0, 0.0, 0.0
                for ox, oy, t in beads:
                    dd = (x - ox) ** 2 + (y - oy) ** 2
                    if dd < best:
                        best, bx, by, bt = dd, ox, oy, t
                r = math.sqrt(best)
                bead = max(0.0, 1.0 - r / 1.55)
                near = max(0.0, 1.0 - ((u - hx) ** 2 + (v - hy) ** 2) * 1.15)
                if bead <= 0.0:
                    tile[y, x, :3] = _dim(deep, 0.55)   # the shadow between beads
                    if emit is not None:
                        emit[y, x] = _dim(deep, 0.10)
                    continue
                base = hot if bt > 0.72 else (warm if bt > 0.30 else deep)
                lit = 0.52 + 0.40 * near + 0.34 * bead
                # ONE highlight texel per bead, up and left of its centre, which is
                # what makes a disc read as a sphere at this size
                if x - bx < 0.05 and y - by < 0.05 and bead > 0.30:
                    lit += 0.45
                tile[y, x, :3] = _dim(base, min(1.6, lit))
                if emit is not None:
                    emit[y, x] = _dim(base, 0.30 + 0.70 * near + 0.50 * bead)

    return _granule_art


# one stamp per window, so no two beds are identical
GRAN_ARTS = [pl.register_card_art("nz_granules_%d" % i, _make_granule_art(i))
             for i in range(FIELDS)]

pl.register_parts({
    # slate-blue plate, the sheet's dominant value and the LIGHTEST mass in frame
    "nz_shell": {"rgb": _dim(CH("pipe_joint"), 1.16)},
    "nz_shell_d": {"rgb": _dim(CH("pipe_joint"), 0.82)},
    "nz_seam": {"rgb": _dim(CH("iron_dark"), 1.3)},
    "nz_leg": {"rgb": _dim(CH("pipe_joint"), 0.72)},
    "nz_claw": {"rgb": CS("resolution_root_pale")},
    "nz_field": {"rgb": CH("lamp"), "emit": CH("lamp")},
    # the gold band and the bright point the granules pack toward
    "nz_ring": {"rgb": CS("flure_core"), "emit": CS("flure_core")},
    "nz_tip": {"rgb": CS("flure_core"), "emit": _dim(CS("flure_core"), 1.25)},
    # the beds GLOW on the sheet, throwing warm light onto their own window rims
}, emit_strength={"nz_field": 3.0, "nz_ring": 2.2, "nz_tip": 4.0})


def build_naturalizer():
    """A broad plated quadruped: dome, four splayed legs, and a snout that ends in
    the one light it carries."""
    global SNOUT_START, TIP_START
    b = Builder()

    # THE CARAPACE — a low faceted dome, wider than tall. Stacked rings rather
    # than a sphere: the sheet's shell is plates meeting at hard edges, and a
    # smooth dome would read as the wrong material at any distance.
    # ONE swept dome, not a stack of prisms. Stacked prisms abut without sharing
    # vertices and the shell stands open along every ring — which is the defect
    # this project spent a day pulling out of the Toxo and the Hidra, and which I
    # walked straight back into here by reaching for the familiar primitive.
    # The seam the sheet runs round the plates is a SPAN of the same tube, so the
    # banding costs a material change rather than a second body.
    shell_z = [SHELL_FLOOR, SHELL_FLOOR + 0.09, SHELL_FLOOR + 0.185,
               SHELL_FLOOR + 0.205, SHELL_FLOOR + 0.30, SHELL_TOP]
    shell_r = [SHELL_R * 0.94, SHELL_R, SHELL_R * 0.978, SHELL_R * 0.970,
               SHELL_R * 0.76, SHELL_R * 0.40]
    b.tube([(0.0, 0.0, z) for z in shell_z], shell_r,
           ["nz_shell_d", "nz_shell", "nz_seam", "nz_shell", "nz_shell"],
           sides=SIDES, cap_start=True, cap_end=True)

    # THE WINDOWS ARE APERTURES, and the field inside them is DRAWN.
    #
    # Both sheets sink every bed in a socket behind a raised rim; laid on the
    # skin as a bare card it reads as a decal stuck to the shell. So the shell is
    # actually OPENED at each field — `aperture()` cuts it and hands back a clean
    # ring — and the ring is bridged inward to a smaller one, which is the socket
    # wall the player reads as the rim. That is the modeled half.
    #
    # The granule field itself stays a CARD, sitting at the socket floor: it is
    # repetition, and repetition is drawn, never modeled. What holds the form is
    # the socket; what repeats is the pixel art inside it.
    SOCKET_R = 0.105
    SOCKET_DEPTH = 0.030
    cut = 0
    for k in range(FIELDS):
        c, rot, apex, nrm = _field_at(k)
        if not apex:
            # A graft does not only DELETE host faces, it rebuilds the ones round
            # its cut into the zipper — so a large part of the shell comes back as
            # new faces belonging to no paint group and carrying no part id. Left
            # alone they read as part id 0, which is simply whatever sits first in
            # PARTS, and eight sockets turned this whole carapace chair-pink.
            # Tag everything the graft made as shell, at the call site, where the
            # host material is actually known.
            before = set(b.bm.faces)
            rim = graft.aperture(b.bm, c, nrm, SOCKET_R, 12)
            if rim is not None:
                cut += 1
                n = Vector(nrm).normalized()
                floor_ring = graft.ring(b.bm, tuple(Vector(c) - n * SOCKET_DEPTH),
                                        nrm, SOCKET_R * 0.86, 12)
                graft.bridge(b.bm, rim, floor_ring)
                c = tuple(Vector(c) - n * (SOCKET_DEPTH * 0.72))
            b._tag([f for f in b.bm.faces if f not in before], "nz_shell")
        FIELD_START.append(len(b.bm.verts))
        b.card(c, (0.30 if apex else 0.20, 0.22), "nz_field", axis='Z',
               art=GRAN_ARTS[k], rot=rot)
    print("[NZ] %d window sockets cut into the shell" % cut)

    # THE LEGS — one welded tube each, hip through knee to foot, then the pale
    # splayed claws the sheet ends every limb with.
    for i in range(LEGS):
        LEG_START.append(len(b.bm.verts))
        pts = [_hip(i), _knee(i), _foot(i)]
        b.tube(pts, [0.075, 0.058, 0.046], "nz_leg", sides=6)
        fx, fy, fz = _foot(i)
        base = math.atan2(fx, fy)
        # THREE BLUNT TOES. They used to taper 0.022 to 0.010 — points, which at
        # any distance the player actually sees this animal from are a couple of
        # pixels and simply are not there. The sheet does not draw points: each
        # foot is three CHUNKY faceted blocks, nearly as thick as they are long,
        # and they read as a foot from across a room. Their base width was already
        # about right against the leg; it was the taper that threw the mass away.
        for t in (-0.46, 0.0, 0.46):          # three toes, splayed
            a = base + t
            b.limb((fx, fy, fz), (fx + math.sin(a) * 0.090,
                                  fy + math.cos(a) * 0.090, 0.012),
                   0.030, 0.023, "nz_claw", sides=4)

    # THE SNOUT — a taper off the front of the shell, its gold band, and the tip.
    SNOUT_START = len(b.bm.verts)
    # The snout runs all the way to its point in SHELL material. The light is a
    # separate body sitting at that point, because the bright thing is parked out
    # of existence at rest — and parking the point itself would leave the animal
    # with its nose cut off whenever it was not about to strike.
    b.tube([(0.0, SNOUT_Y, SHELL_FLOOR + 0.16),
            (0.0, (SNOUT_Y + SNOUT_TIP) * 0.5, SHELL_FLOOR + 0.095),
            (0.0, SNOUT_TIP, SHELL_FLOOR + 0.035)],
           [0.155, 0.088, 0.026], "nz_shell", sides=7, cap_start=False)
    b.annulus((0.0, SNOUT_Y - 0.09, SHELL_FLOOR + 0.135), 0.118, 0.096, 0.024,
              "nz_ring", sides=SIDES)
    TIP_START = len(b.bm.verts)
    b.ngon_prism((0.0, SNOUT_TIP - 0.01), 0.010, 0.038, 0.055, "nz_tip",
                 sides=6, z0=SHELL_FLOOR + 0.010)
    return b.finish("NaturalizerRigged")


def naturalizer_chains():
    """The body carries everything. Each leg is its own two-bone chain, the snout
    hangs off the front, and every granule window gets a bone of its own so the
    wave can put them out one at a time."""
    chains = [{"prefix": "body", "points": [(0.0, 0.0, 0.0),
                                            (0.0, 0.0, SHELL_FLOOR + 0.16)]}]
    for i in range(LEGS):
        chains.append({"prefix": "leg%d" % i, "parent": "body_0",
                       "points": [_hip(i), _knee(i), _foot(i)]})
    for k in range(FIELDS):
        c, _rot, _apex, _n = _field_at(k)
        chains.append({"prefix": "field%d" % k, "parent": "body_0",
                       "points": [(c[0], c[1], c[2] - 0.05), c]})
    chains.append({"prefix": "snout", "parent": "body_0",
                   "points": [(0.0, SNOUT_Y, SHELL_FLOOR + 0.16),
                              (0.0, SNOUT_TIP + 0.05, SHELL_FLOOR + 0.045)]})
    chains.append({"prefix": "tip", "parent": "snout_0",
                   "points": [(0.0, SNOUT_TIP + 0.02, SHELL_FLOOR + 0.015),
                              (0.0, SNOUT_TIP - 0.04, SHELL_FLOOR + 0.075)]})
    return chains


piece = build_naturalizer()
pl.texture_object(piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
arm = rig.build_armature("Naturalizer", naturalizer_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')

# the shell itself is the body; everything after it is claimed by its own bone
rig.assign_exclusive_weights(piece, "body_0", range(0, FIELD_START[0]))
for k, start in enumerate(FIELD_START):
    end = FIELD_START[k + 1] if k + 1 < len(FIELD_START) else LEG_START[0]
    rig.assign_exclusive_weights(piece, "field%d_0" % k, range(start, end))
# A leg's tube lays its rings down consecutively; the thigh bone takes the hip and
# knee rings and the shin takes the foot ring and the toes with it, so the crease
# sits at the knee where the animal actually bends.
LEG_SIDES = 6
for i, start in enumerate(LEG_START):
    end = LEG_START[i + 1] if i + 1 < len(LEG_START) else SNOUT_START
    knee_v = start + 2 * LEG_SIDES
    rig.assign_exclusive_weights(piece, "leg%d_0" % i, range(start, knee_v))
    rig.assign_exclusive_weights(piece, "leg%d_1" % i, range(knee_v, end))
rig.assign_exclusive_weights(piece, "snout_0", range(SNOUT_START, TIP_START))
rig.assign_exclusive_weights(piece, "tip_0",
                             range(TIP_START, len(piece.data.vertices)))

# A patrolling Naturalizer carries its windows lit and its point DARK. The tip is
# the only thing that changes value, so it has to start with nowhere to go but up.
OUT, LIT = 0.001, 1.0
patrol = {"tip_0": OUT}
for k in range(FIELDS):
    patrol["field%d_0" % k] = LIT

# PACK: the fields go out back-to-front and the point comes up behind them, which
# is the light travelling forward through the animal to the thing it is about to
# touch. Rear-most first, so the wave has a direction a player can read.
packed = {"tip_0": LIT}
for k in range(FIELDS):
    packed["field%d_0" % k] = OUT


def _wave(t):
    """The fields part-way out: everything below `t` has gone dark."""
    out = {}
    for k in range(FIELDS):
        out["field%d_0" % k] = OUT if k < t else LIT
    return out


rig.clip(arm, "naturalizer_pack", [
    (0.0, dict(patrol)),
    (0.12, dict(_wave(2), tip_0=0.35)),
    (0.24, dict(_wave(4), tip_0=0.72)),
    (0.35, dict(packed)),
])
# STRIKE: the point discharges into whatever it flagged, and the shell refills.
rig.clip(arm, "naturalizer_strike", [
    (0.0, dict(packed)),
    (0.10, dict(packed, tip_0=2.4)),
    (0.50, dict(patrol)),
])
# STAND DOWN: the tag came back coherent, or the target left reach. The light goes
# back into the shell the way it came, which is how a player reads "not any more".
rig.clip(arm, "naturalizer_standdown", [
    (0.0, dict(packed)),
    (0.30, dict(_wave(2), tip_0=0.30)),
    (0.60, dict(patrol)),
])
rig.park(arm, dict(patrol))

report = rig.validate(piece, arm, dict([("leg%d" % i, 2) for i in range(LEGS)]))
print("[RIG] Naturalizer %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("naturalizer rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "naturalizer.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: naturalizer -> %s ===" % GLTF)
