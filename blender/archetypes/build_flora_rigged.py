# RIGGED FLORA — the tendable species whose STATE CHANGES ARE ANIMATIONS.
#
# THE LAW (director, 2026-08-10): when a plant changes state the player watches it
# change. The specs are written that way and say so out loud — a Seefern tended is
# "the vein-glow brightens progressively from base to tip following her touch, the
# eye-markings opening as she works", and "the visible progression of eye-openings
# tells the player when it's complete"; a Hushbloom that fires has "the leaflets
# folded inward IN A WAVE along each rachis". The animation IS the progress bar.
# Swapping two bodies throws away the only thing that communicates.
#
# So each species here ships ONE body with an ARMATURE and real weights, plus the
# named clips for its transitions. Godot gets an AnimationPlayer and plays a clip
# by name; it never poses bones itself, and it never waits on a clip — the clip is
# cosmetic, the scheduler owns when a state actually commits.
#
# Run:  blender.exe -b --python blender/archetypes/build_flora_rigged.py
#       (Blender 5.1 only)
# Outputs (game-ready, committed):
#   to-rust-as-we-fall/resources/models/flora/flora_rigged.gltf (+bin/tex)

import bmesh as _bmesh
import bpy
import importlib
import json
import math

from mathutils import Vector
import mathutils
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
importlib.reload(rig)

SRC = os.path.join(BL, "archetypes")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
FLORA_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "flora")


def gltf_for(species):
    """One gltf PER SPECIES. NLA_TRACKS mode samples every selected armature over
    every clip, so several rigs in one file give each species' animations constant
    rest-pose tracks for all the others' bones — weight the file down, and warn in
    the engine for every track a single-species body cannot resolve."""
    return os.path.join(FLORA_DIR, "flora_%s.gltf" % species)


for d in (OBJX, PAINTED, FLORA_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

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
def _dim(c, f): return tuple(v * f for v in c)


# ---- the leaf card's art (the comb, its pulvini, and the flash) ---------------------------

def _hushbloom_leaf_art(tile, isl, px_per_m):
    """The compound leaf: a dark rachis carrying bright paired leaflets, with the
    swollen PULVINUS at each attachment — the affordance, the swelling that says
    these leaflets fold before the player has ever triggered one. The pulvini are
    written into the card's EMISSIVE plane as well, because the tending flash at
    the end of the clip brightens exactly them: the plant lights up along the
    points that do the work."""
    ph, pw = tile.shape[:2]
    emit = isl["emit"]
    rachis = _dim(CS("hushbloom_stem"), 0.55)
    rachis_d = _dim(CS("hushbloom_stem"), 0.32)
    # THE LEAFLETS ARE THE DARK PART AND THE PULVINI ARE THE PALE ONE. Both were
    # hushbloom_bloom — the leaflet tissue painted in the colour of the beads it
    # is supposed to contrast against — so once the card stopped being a solid
    # slab there was nothing left to see: cut foliage in the background's own
    # value reads as no foliage at all. The sheet is dark olive leaflets carrying
    # a row of pale lilac pulvini, and the beads only mean anything against
    # leaflets darker than they are.
    leaflet = _dim(CS("seefern_leaf"), 0.72)
    leaflet_d = _dim(CS("seefern_leaf"), 0.44)
    pulv = CS("hushbloom_bloom")
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))
    # A PINNATE FROND IS MOSTLY AIR. The blade used to be painted full-card-width
    # down every row — leaflets as marks on a solid rectangle — on the reasoning
    # that strokes over transparency have nothing to sit on. The result was a card
    # roughly four-fifths opaque, which renders as a slab however many texels it is
    # given and whatever the material does, and which is what made me spend days
    # doubting the cutout pipeline that was working the whole time.
    #
    # The sheet draws a thin rachis carrying separate paired leaflets with daylight
    # between them. So the leaflets ARE the tissue: each pair is a wedge a few rows
    # deep, and the rows between pairs stay empty.
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)
        half = max(0.8, (pw * 0.055) * (1.0 - 0.35 * t))
        for x in range(pw):
            if abs(x - mid) > half:
                continue
            tile[row, x, 3] = 1.0
            tile[row, x, :3] = rachis_d if abs(x - mid) > half * 0.6 else rachis

    pairs = max(4, min(12, int(round(0.5 + ph / max(2.0, 0.055 * px_per_m)))))
    pitch = ph / float(pairs)
    # Leaflets take most of the pitch and the gap is what is left. Cut too thin
    # they read as a ladder of marks rather than foliage — the plant swung from a
    # solid slab to something you can see the far side of, and the sheet is neither.
    depth = max(2, int(round(pitch * 0.72)))
    for p in range(pairs):
        t = (p + 0.5) / float(pairs)
        row0 = int(round(t * (ph - 1)))
        span = int(round((pw * 0.5) * (0.92 - 0.40 * t)))
        if span < 2:
            continue
        for dr in range(depth):
            row = row0 + dr - depth // 2
            if not (0 <= row < ph):
                continue
            # each leaflet narrows along its own length, so a pair reads as two
            # blades rather than one bar across the card
            taper = 1.0 - abs(dr - (depth - 1) * 0.5) / max(1.0, depth * 0.7)
            reach = max(1, int(round(span * (0.62 + 0.38 * taper))))
            for side in (-1, 1):
                for k in range(1, reach + 1):
                    col = mid + side * k
                    if not (0 <= col < pw):
                        continue
                    tile[row, col, 3] = 1.0
                    tile[row, col, :3] = leaflet if k < reach - 1 else leaflet_d
        # the pulvinus bead at the pair's junction, which is the state tell
        for side in (-1, 1):
            pc = mid + side
            if 0 <= pc < pw and 0 <= row0 < ph:
                tile[row0, pc, :3] = pulv
                tile[row0, pc, 3] = 1.0
    if ph >= 2:
        tile[ph - 1, mid, :3] = pulv
        tile[ph - 1, mid, 3] = 1.0


HUSH_LEAF = pl.register_card_art("rigged_hushbloom_leaf", _hushbloom_leaf_art)

pl.register_parts({
    # No part-level glow: the light on this plant is the PULVINI, which the card
    # painter writes per pixel. Lighting the whole leaf lifts its olive tissue to
    # the leaflets' value and the comb stops reading.
    "rh_leaf":  {"rgb": _dim(CS("hushbloom_bloom"), 0.62)},
    # the arching stems and the claw prongs: pale grey-lilac, the palest thing on
    # the plant, which is what lets the dark leaflets read against them
    "rh_stem":  {"rgb": _dim(CS("hushbloom_stem"), 1.35)},
    "rh_soil":  {"rgb": _dim(CH("ground"), 0.7), "family": "speckled"},
    "rh_sprig": {"rgb": _dim(CS("scarpet_blade"), 0.85)},
    # The tending FLASH: a small bright card that lives scaled to nothing and snaps
    # open on the last beat of the tend clip. glTF animates node transforms, not
    # material properties, so a flash is expressed as something that CHANGES SIZE.
    "rh_flash": {"rgb": CS("hushbloom_bloom"), "emit": CS("hushbloom_bloom")},
}, emit_strength={"rh_leaf": 1.0, "rh_flash": 4.0})


# ---- the piece ---------------------------------------------------------------------------

HB_STEMS = 5          # arching fronds; the silhouette is three or four from any side
HB_ROOTS = 6          # the splayed claw crown it stands on
SEGMENTS = 4          # enough joints for the fold to travel as a wave, not a hinge
FLASH_VERT_START = 0  # set while building; the flash's verts are the mesh's tail
LEAF_VERT_START = []  # per stem: where its card's rows begin in the mesh
STEM_VERT_START = []  # per stem: where the stem's own tube begins
ROOT_VERT_START = 0


def _hb_stem_pt(i, f):
    """A point along stem `i`, fraction `f` from the crown to the tip.

    The stem ARCHES: it leaves the crown steeply, straightens, and leans outward
    near the tip. That curve is the plant's whole posture — the sheet's silhouette
    is three or four arcs springing from a dark mound, and a straight card fanned
    from a disc cannot make it at any angle.
    """
    a = math.tau * i / HB_STEMS + 0.35
    r = 0.60 * (f ** 1.45)
    z = 0.07 + 0.80 * math.sin(f * 1.32)
    return (math.sin(a) * r, math.cos(a) * r, z)


def _hb_root_pt(k, f):
    """One claw prong, out along the floor and curling down at its end."""
    a = math.tau * k / HB_ROOTS + 0.8
    r = 0.34 * f
    z = 0.055 - 0.045 * (f ** 2.2)
    return (math.sin(a) * r, math.cos(a) * r, z)


def build_hushbloom_rigged():
    """The comb-leaf stun plant: a splayed claw-root crown, arching segmented
    stems out of it, and one pinnate leaf card riding each stem.

    The division of labour is the pipeline's: the crown and the stems HOLD THE
    FORM so they are modelled, and the paired leaflets and the pulvini beads
    running along each rachis are repetition, so they are drawn on the card. What
    stood here before was eight opaque cards springing out of a flat soil disc —
    no crown, no stems, and therefore none of the sheet's posture.
    """
    global FLASH_VERT_START, ROOT_VERT_START
    b = Builder()
    b.ngon_prism((0, 0), 0.17, 0.23, 0.05, "rh_soil", sides=9)

    ROOT_VERT_START = len(b.bm.verts)
    for k in range(HB_ROOTS):
        for j in range(3):
            p0 = _hb_root_pt(k, j / 3.0)
            p1 = _hb_root_pt(k, (j + 1) / 3.0)
            b.limb(p0, p1, 0.036 - 0.008 * j, 0.030 - 0.008 * j, "rh_stem", sides=5)

    for i in range(HB_STEMS):
        STEM_VERT_START.append(len(b.bm.verts))
        for j in range(SEGMENTS):
            p0 = _hb_stem_pt(i, j / float(SEGMENTS))
            p1 = _hb_stem_pt(i, (j + 1) / float(SEGMENTS))
            b.limb(p0, p1, 0.030 - 0.004 * j, 0.026 - 0.004 * j, "rh_stem", sides=5)

    for i in range(HB_STEMS):
        # the leaf rides its stem: cut along the chord it spans, so the card's rows
        # and the stem's joints fold together instead of against each other
        base = Vector(_hb_stem_pt(i, 0.10))
        tip = Vector(_hb_stem_pt(i, 1.0))
        mid = (base + tip) * 0.5
        span = (tip - base)
        L = span.length
        a = math.atan2(span.x, span.y)
        tilt = math.acos(max(-1.0, min(1.0, span.z / max(L, 1e-6))))
        LEAF_VERT_START.append(len(b.bm.verts))
        # NARROW. A frond is a rachis with small paired leaflets, and at nearly half
        # its own length the card stops being foliage and becomes a slab that hides
        # the stem carrying it — the stems are the posture and the posture is the
        # read.
        b.card(tuple(mid), (L * 0.26, L * 0.94), "rh_leaf", axis='Y', art=HUSH_LEAF,
               rot=(tilt, 0.0, a), segments=SEGMENTS)

    FLASH_VERT_START = len(b.bm.verts)
    b.card((0, 0, 0.30), (0.62, 0.62), "rh_flash", axis='Z')
    b.card((0, 0, 0.30), (0.62, 0.62), "rh_flash", axis='Y')
    return b.finish("HushbloomRigged")


def leaf_chains():
    """A chain up each stem, and one bone for the crown that never moves."""
    chains = [{"prefix": "crown", "points": [(0.0, 0.0, 0.0), (0.0, 0.0, 0.06)]}]
    for i in range(HB_STEMS):
        pts = [_hb_stem_pt(i, s / float(SEGMENTS)) for s in range(SEGMENTS + 1)]
        chains.append({"prefix": "leaf%d" % i, "parent": "crown_0", "points": pts})
    chains.append({"prefix": "flash", "parent": "crown_0",
                   "points": [(0.0, 0.0, 0.26), (0.0, 0.0, 0.34)]})
    return chains


LEAVES = [None] * HB_STEMS      # the clips index by stem; the tuple data is gone


piece = build_hushbloom_rigged()
# 96 px/m, not 48. A frond card is about 23 cm across, which at the base rate is
# ELEVEN texels — too few to draw paired leaflets with alpha between them, so the
# art fills what it can and the card renders as a solid slab with bars. Measured
# on the built atlas: 2.5% of it transparent, where a plant made of cut foliage
# should be nearly half. The art direction allows flora up to 96 and close detail
# to 128; this is the cheapest end of that.
pl.texture_object(piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)

arm = rig.build_armature("Hushbloom", leaf_chains())
# NAME-only bind: it creates the groups and the modifier and guesses nothing.
# Every weight below is computed from topology we already know, because the
# automatic pass loses tip bones among eight strips crowded into one rosette --
# they come out weighted to nothing and deform nothing while still animating.
rig.bind(piece, arm, kind='ARMATURE_NAME')
# each stem's TUBE, split between that stem's bones by which segment built it —
# one limb per joint, so no bone is left deforming nothing
for si, start in enumerate(STEM_VERT_START):
    end = STEM_VERT_START[si + 1] if si + 1 < len(STEM_VERT_START) else LEAF_VERT_START[0]
    per = max(1, (end - start) // SEGMENTS)
    for j in range(SEGMENTS):
        lo = start + j * per
        hi = start + (j + 1) * per if j + 1 < SEGMENTS else end
        rig.assign_exclusive_weights(piece, "leaf%d_%d" % (si, j), range(lo, hi))
# and the CARD riding it, row by row against the same chain
for li, start in enumerate(LEAF_VERT_START):
    rig.weight_chain_strip(piece, "leaf%d" % li, rig.card_rows(start, SEGMENTS))
flash_verts = range(FLASH_VERT_START, len(piece.data.vertices))
rig.assign_exclusive_weights(piece, "flash_0", flash_verts)
# THE CROWN IS THE GROUND THE PLANT STANDS ON. It holds the mound and the claw
# prongs and it never moves, so it gets its own bone rather than riding a stem's
# base — hung off a stem, the roots would sway every time the plant folded.
rig.assign_exclusive_weights(piece, "crown_0", range(0, STEM_VERT_START[0]))

# ---- the clips ---------------------------------------------------------------------------
# TRIGGER: the leaflets fold inward in a WAVE along each rachis — each bone lags
# the one before it, which is the fold the spec describes and the thing a single
# uniform rotation cannot express. Fast, because firing is fast.
FOLD = 1.15
trigger = [
    (0.0, {}),
    (0.18, {k: (v[0] * 0.55, v[1], v[2])
            for li in range(len(LEAVES))
            for k, v in rig.chain_wave("leaf%d" % li, SEGMENTS, FOLD).items()}),
    (0.42, {k: v
            for li in range(len(LEAVES))
            for k, v in rig.chain_wave("leaf%d" % li, SEGMENTS, FOLD).items()}),
]
for _t, _b in trigger:
    _b["flash_0"] = 0.001
rig.clip(arm, "hushbloom_trigger", trigger)

# RECHARGE: the same wave run backwards and SLOWLY — the spec's recharging plant is
# "still folded but the pulvini are slowly re-inflating", so the leaves come back
# last, not first.
recharge = [
    (0.0, {k: v
           for li in range(len(LEAVES))
           for k, v in rig.chain_wave("leaf%d" % li, SEGMENTS, FOLD).items()}),
    (1.8, {k: (v[0] * 0.62, v[1], v[2])
           for li in range(len(LEAVES))
           for k, v in rig.chain_wave("leaf%d" % li, SEGMENTS, FOLD).items()}),
    (3.0, {}),
]
for _t, _b in recharge:
    _b["flash_0"] = 0.001
rig.clip(arm, "hushbloom_recharge", recharge)

# TEND: Peris works along each leaf and the leaflets OPEN as she goes — the plant
# lifts and spreads a little past its rest pose, then settles. The BRIGHT FLASH at
# the end is the completion signal; it is the last beat of the clip so the player
# reads "done" from the plant instead of from a meter.
lift = {}
for li in range(len(LEAVES)):
    lift.update(rig.chain_wave("leaf%d" % li, SEGMENTS, -0.28, lead=0.6))
SHUT, OPEN = 0.001, 1.0
lift_shut = dict(lift)
lift_shut["flash_0"] = SHUT
tend = [
    (0.0, {"flash_0": SHUT}),
    (1.6, lift_shut),
    (2.05, {"flash_0": SHUT}),          # still dark right up to the finish
    (2.15, {"flash_0": OPEN}),          # THE FLASH: tending is complete
    (2.40, {"flash_0": SHUT}),
]
rig.clip(arm, "hushbloom_tend", tend)
# A plant that has played nothing stands CHARGED, leaflets fanned as modelled, with
# the tending flare shut.
rig.park(arm, {"flash_0": SHUT})

# ---- the rig gate --------------------------------------------------------------------------
# Two failures look identical in a static render and in the build log: a bone
# weighted to nothing (it animates and deforms nothing) and a vertex in no group
# (it stays behind and tears the mesh). The density rule is the third: a chain may
# not carry more bones than the geometry it deforms has subdivisions, or the extra
# rotation is averaged away rather than gained.
report = rig.validate(piece, arm,
                      {"leaf%d" % i: SEGMENTS for i in range(len(LEAVES))})
print("[RIG] %s bones=%d dead=%s orphan_verts=%d min_verts_per_bone=%d"
      % (report["verdict"], report["bones"], report["dead_bones"] or "none",
         report["orphan_verts"], report["min_verts_per_bone"]))
for problem in report["problems"]:
    print("[RIG]   %s" % problem)
if report["verdict"] != "PASS":
    raise SystemExit("rig does not deform: %s" % "; ".join(report["problems"]))


# ============================================================================
# SEEFERN — the fern-LANTERN. Its tending is the clearest case in the roster:
# "the vein-glow brightens progressively from base to tip following her touch,
# the eye-markings opening as she works", and "the visible progression of
# eye-openings tells the player when it is complete". That progression is a wave
# travelling up each frond, and it IS the completion signal.
# ============================================================================

SF_FRONDS = [(0.25, 0.10, 0.70, 0.20), (1.15, 0.30, 0.60, 0.185),
             (2.05, 0.36, 0.55, 0.175), (2.95, 0.40, 0.50, 0.165),
             (3.85, 0.34, 0.58, 0.18), (4.75, 0.26, 0.64, 0.19),
             (5.60, 0.52, 0.30, 0.10)]
SF_SEGMENTS = 8            # A FIDDLEHEAD IS A SPIRAL, and four joints can bend but
                          # cannot coil — the tip needs several in a row to turn
                          # through most of a full turn. Eight rows, eight bones:
                          # exactly at the law's ceiling and no further, since past
                          # that the extra joints share rows and average away.
SF_VERT_START = []
SF_EYE_START = []
SF_EYE_SEGS = (1, 3, 5)    # where along each frond an eye patch sits


def _seefern_eye_art(tile, isl, px_per_m):
    """A pair of eye-markings on transparency. Only the rings are opaque, because
    this layer sits ON the blade — anything else it paints would hide the leaf."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0
    ring = CS("seefern_vein_core")
    pupil = _dim(CS("seefern_leaf"), 0.30)
    cx = (pw - 1) * 0.5
    for e in range(2):
        ey = (ph - 1) * (0.30 + 0.40 * e)
        rad = max(1.6, pw * 0.20)
        for y in range(ph):
            for x in range(pw):
                d = math.hypot(x - cx, y - ey)
                if d > rad:
                    continue
                tile[y, x, 3] = 1.0
                tile[y, x, :3] = pupil if d < rad * 0.45 else ring
SF_FLASH_START = 0


def _seefern_frond_art_rigged(tile, isl, px_per_m):
    """The frond as card ENT-014 draws it: a CONTINUOUS near-shadow blade carrying
    a lit vein network and the ring EYE-MARKINGS that give the species its name.

    The blade is a dark mass first and the light sits on top of it — veins branching
    off a bright midrib, and open rings along them. Painting the veins as loose
    strokes on transparency instead loses the dark body, and the plant comes out a
    bundle of bright ribbons with nothing to read the light against.

    The eyes are RINGS, not points: a dark pupil inside a lit rim. They are what the
    spec makes the progress read when Peris works ("the eye-markings opening as she
    works"), so they have to be legible as eyes at a glance."""
    ph, pw = tile.shape[:2]
    emit = isl["emit"]
    tissue = CS("seefern_leaf")
    tissue_d = _dim(CS("seefern_leaf"), 0.6)
    vein = CS("seefern_vein")
    core = CS("seefern_vein_core")
    pupil = _dim(CS("seefern_leaf"), 0.25)
    tile[:, :, 3] = 0.0
    mid = (pw - 1) * 0.5

    def blade_half(t):
        # a spearhead: widest a third of the way up, drawn to a point at the tip
        if t < 0.32:
            k = t / 0.32
            return (pw * 0.5) * (0.35 + 0.65 * k)
        k = (t - 0.32) / 0.68
        return (pw * 0.5) * (1.0 - 0.96 * k * k)

    # 1. the dark body
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)
        half = blade_half(t)
        for x in range(pw):
            d = abs(x - mid)
            if d > half:
                continue
            tile[row, x, 3] = 1.0
            tile[row, x, :3] = tissue if d < half * 0.72 else tissue_d

    # 2. the midrib, and veins branching off it toward the blade's edge
    for row in range(ph):
        c = int(round(mid))
        if 0 <= c < pw and tile[row, c, 3] > 0.0:
            tile[row, c, :3] = core
            emit[row, c] = vein
    pitch = max(4, int(round(0.12 * px_per_m)))
    eyes = []
    for row in range(pitch, ph - 1, pitch):
        t = row / max(1.0, ph - 1.0)
        half = blade_half(t)
        reach = int(round(half * 0.62))
        if reach < 2:
            continue
        for side in (-1, 1):
            for k in range(1, reach + 1):
                # the vein rises as it runs out, so it reads as a branch not a bar
                r2 = row - int(round(k * 0.5))
                col = int(round(mid + side * k))
                if 0 <= r2 < ph and 0 <= col < pw and tile[r2, col, 3] > 0.0:
                    tile[r2, col, :3] = vein
                    emit[r2, col] = _dim(vein, 0.9)
            # An eye needs a texel of tissue between its rim and the midrib, or the
            # two lit shapes touch and the pair reads as one bright rung across
            # the blade. A frond card is 9-11 px wide at this density, so where
            # there is no room the marking is simply left off that row.
            ex = mid + side * max(3.0, reach * 0.8)
            if abs(ex - mid) >= 3 and 0 <= int(round(ex)) < pw:
                eyes.append((row - int(round(reach * 0.5)), int(round(ex))))

    # 3. the eyes: a dark pupil with a lit rim on its four sides only. A full 3x3
    # ring spends two more texels per side than a blade this narrow has to give.
    for (ey, ex) in eyes:
        if not (0 <= ey < ph and 0 <= ex < pw) or tile[ey, ex, 3] <= 0.0:
            continue
        for (dy, dx) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ry, rx = ey + dy, ex + dx
            if 0 <= ry < ph and 0 <= rx < pw and tile[ry, rx, 3] > 0.0:
                tile[ry, rx, :3] = core
                emit[ry, rx] = vein
        tile[ey, ex, :3] = pupil                      # the eye is OPEN: dark inside
        emit[ey, ex] = (0.0, 0.0, 0.0)


SF_ART = pl.register_card_art("rigged_seefern_frond", _seefern_frond_art_rigged)
SF_EYE_ART = pl.register_card_art("rigged_seefern_eye", _seefern_eye_art)

pl.register_parts({
    # No part-level emission: the LIGHT on this plant is its vein network and its
    # eyes, which the card painter writes into the emissive plane per pixel. A
    # glow applied to the whole blade lifts the near-shadow tissue to the same
    # value as the veins and the frond reads as a bright ribbon.
    "sf_blade": {"rgb": CS("seefern_leaf")},
    "sf_pad": {"rgb": _dim(CH("moss"), 0.8)},
    "sf_flash": {"rgb": CS("seefern_vein_core"), "emit": CS("seefern_vein")},
    # the eye-markings, on their own emissive layer so an untended fern can be dark
    "sf_eye": {"rgb": CS("seefern_vein_core"), "emit": CS("seefern_vein_core")},
    # A WILD FERN IS NOT WEARING ITS COMPLETION SIGNAL. The blade carried an
    # emission strength of its own, so every frond's veins and eye-markings glowed
    # on a plant nobody had touched — the sheet's third panel is specifically an
    # UNTENDED fern whose markings are present but dark, and a tell that is already
    # showing is a tell nobody gets. The markings stay painted, because they are
    # anatomy; only the light comes off them, and the tending flare remains the
    # thing that says the work took.
}, emit_strength={"sf_flash": 4.0, "sf_eye": 3.2})


def build_seefern_rigged():
    """Seven fronds fanning from a modelled mossy pad, each a SEGMENTED card so a
    bone chain can lift it as Peris works along it. The pad is what the fern
    stands on and never moves."""
    b = Builder()
    b.ngon_prism((0, 0), 0.26, 0.30, 0.06, "sf_pad", sides=9)
    for (a, tilt, L, W) in SF_FRONDS:
        rr = math.sin(tilt) * L * 0.5
        zc = 0.06 + math.cos(tilt) * L * 0.5
        SF_VERT_START.append(len(b.bm.verts))
        b.card((math.sin(a) * rr, math.cos(a) * rr, zc), (W * 1.15, L),
               "sf_blade", axis='Y', art=SF_ART, rot=(tilt, 0.0, a),
               segments=SF_SEGMENTS)
    # THE EYES ON THEIR OWN LAYER. Painted into the blade they are lit from the
    # moment the fern exists, so an untended one wears the signal that says it was
    # worked — the same law the Flare's inert core and the Meeb's shut cups answer.
    # Each patch rides a bone PARENTED into its frond's chain: the parent carries
    # the bend, so the eyes travel with the leaf, and the bone's own scale parks
    # them, so they can be dark. That is the Meeb's maw arrangement exactly.
    SF_EYE_START.clear()
    for fi, (a, tilt, L, W) in enumerate(SF_FRONDS):
        for k, seg in enumerate(SF_EYE_SEGS):
            f = (seg + 0.5) / float(SF_SEGMENTS)
            r = math.sin(tilt) * L * f
            z = 0.06 + math.cos(tilt) * L * f
            SF_EYE_START.append(len(b.bm.verts))
            b.card((math.sin(a) * r, math.cos(a) * r, z),
                   (W * 0.62, L / SF_SEGMENTS * 0.9), "sf_eye", axis='Y',
                   art=SF_EYE_ART, rot=(tilt, 0.0, a))
    global SF_FLASH_START
    SF_FLASH_START = len(b.bm.verts)
    b.card((0, 0, 0.42), (0.54, 0.54), "sf_flash", axis='Z')
    b.card((0, 0, 0.42), (0.54, 0.54), "sf_flash", axis='Y')
    return b.finish("SeefernRigged")


def seefern_chains():
    chains = []
    for fi, (a, tilt, L, W) in enumerate(SF_FRONDS):
        pts = []
        for s2 in range(SF_SEGMENTS + 1):
            f = s2 / float(SF_SEGMENTS)
            r = math.sin(tilt) * L * f
            z = 0.06 + math.cos(tilt) * L * f
            pts.append((math.sin(a) * r, math.cos(a) * r, z))
        chains.append({"prefix": "frond%d" % fi, "points": pts})
    for fi, (a, tilt, L, W) in enumerate(SF_FRONDS):
        for k, seg in enumerate(SF_EYE_SEGS):
            f = (seg + 0.5) / float(SF_SEGMENTS)
            r = math.sin(tilt) * L * f
            z = 0.06 + math.cos(tilt) * L * f
            chains.append({"prefix": "eye%d_%d" % (fi, k),
                           "parent": "frond%d_%d" % (fi, seg),
                           "points": [(math.sin(a) * r, math.cos(a) * r, z),
                                      (math.sin(a) * r, math.cos(a) * r, z + 0.05)]})
    chains.append({"prefix": "sfflash", "points": [(0.0, 0.0, 0.38), (0.0, 0.0, 0.46)]})
    return chains


# A CARD NEEDS TEXELS TO PUT GAPS IN. Measured across the built atlases, a plant
# whose foliage is genuinely cut from cards lands near a fifth of its atlas
# transparent — the Scarpet does, at 20%. The species raised here were at 0.7% to
# 3.7%, which is not foliage with holes in it; it is a card whose leaflets are so
# crowded the painter fills the whole rectangle and the plant renders as a slab.
# The art direction allows flora up to 96 and close detail to 128.
sf_piece = build_seefern_rigged()
pl.texture_object(sf_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
sf_arm = rig.build_armature("Seefern", seefern_chains())
rig.bind(sf_piece, sf_arm, kind='ARMATURE_NAME')
for fi, start in enumerate(SF_VERT_START):
    rig.weight_chain_strip(sf_piece, "frond%d" % fi,
                           rig.card_rows(start, SF_SEGMENTS))
_eye_i = 0
for _fi in range(len(SF_FRONDS)):
    for _k in range(len(SF_EYE_SEGS)):
        _start = SF_EYE_START[_eye_i]
        _end = (SF_EYE_START[_eye_i + 1] if _eye_i + 1 < len(SF_EYE_START)
                else SF_FLASH_START)
        rig.assign_exclusive_weights(sf_piece, "eye%d_%d_0" % (_fi, _k),
                                     range(_start, _end))
        _eye_i += 1
rig.assign_exclusive_weights(sf_piece, "sfflash_0",
                             range(SF_FLASH_START, len(sf_piece.data.vertices)))
rig.assign_exclusive_weights(sf_piece, "frond0_0", range(0, SF_VERT_START[0]))

# TEND: the work travels BASE TO TIP, exactly as the spec describes her hands
# moving, and the fern finishes standing prouder than it started. The flash is the
# last beat: the eye-openings have reached the tips and the tending is complete.
SF_SHUT, SF_OPEN = 0.001, 1.0


def _sf_eyes(lit_through):
    """The eye-markings open in a WAVE from base to tip, which the spec calls the
    completion signal — a plant that lit them all at once would say the work was
    finished before it was. `lit_through` is how far up each frond the wave has
    reached, in patches."""
    out = {}
    for fi in range(len(SF_FRONDS)):
        for k in range(len(SF_EYE_SEGS)):
            out["eye%d_%d_0" % (fi, k)] = SF_OPEN if k < lit_through else SF_SHUT
    return out


SF_EYES_DARK = _sf_eyes(0)
# chain_wave turns EVERY bone by its amount, so a chain's total curvature scales
# with how many bones it has. The frond went from four joints to eight to make a
# fiddlehead possible, which silently doubled the bend in every pose already
# written and folded the crown into a knot. Angles authored against four joints
# are held to that by dividing the amount, so raising the subdivision buys detail
# without rewriting every clip.
SF_WAVE = 4.0 / SF_SEGMENTS
SF_SURVIVOR = 0            # the frond that stays up when the rest go


def _sf_crook(fi, amount):
    """The fiddlehead: the last three joints of a frond coiling over.

    Concentrated at the TIP rather than spread down the blade — a crook is a
    spiral at the end of something straight, and rolling the whole frond evenly
    gives an arc, which is a different plant. The three joints together turn
    through about three quarters of a full turn at amount=1.
    """
    out = {}
    for k, turn in enumerate((0.34, 0.46, 0.58)):
        out["frond%d_%d" % (fi, SF_SEGMENTS - 3 + k)] = (turn * amount, 0.0, 0.0)
    return out


SF_CROOKED = {}
for _fi in range(len(SF_FRONDS)):
    SF_CROOKED.update(_sf_crook(_fi, 1.0))
sf_lift = {}
for fi in range(len(SF_FRONDS)):
    sf_lift.update(rig.chain_wave("frond%d" % fi, SF_SEGMENTS, -0.30 * SF_WAVE, lead=0.55))
sf_half = dict((k, (v[0] * 0.5, v[1], v[2])) for k, v in sf_lift.items())
sf_tend = [
    (0.0, dict(sfflash_0=SF_SHUT)),
    (1.2, dict(sf_half, sfflash_0=SF_SHUT)),
    (2.6, dict(sf_lift, **dict(SF_CROOKED, sfflash_0=SF_SHUT))),
    (2.72, dict(sf_lift, **dict(SF_CROOKED, sfflash_0=SF_OPEN))),
    (3.1, dict(sf_lift, **dict(SF_CROOKED, sfflash_0=SF_SHUT))),
]
# the wave travels while the fronds lift, so the two read as one action
sf_tend = [(t, dict(pose, **_sf_eyes(lit)))
           for (t, pose), lit in zip(sf_tend, (0, 1, 2, 3, 3))]
rig.clip(sf_arm, "seefern_tend", sf_tend)

# WILT: damaged fronds dim and fold down and stay down. Slow, because dying is not
# an event. ONE FROND IS SPARED. The sheet's fourth panel is not an empty clump —
# it is a stand of dead brown fronds with a single green one still up and still
# lit among them, which is what says the plant can be brought back rather than
# replaced. A uniform droop reads as a corpse.
sf_droop = {}
for fi in range(len(SF_FRONDS)):
    if fi == SF_SURVIVOR:
        continue
    sf_droop.update(rig.chain_wave("frond%d" % fi, SF_SEGMENTS, 0.55 * SF_WAVE, lead=0.2))
sf_droop.update(_sf_crook(SF_SURVIVOR, 1.0))
# the survivor keeps its eyes; everything that died closes them
sf_wilt_eyes = dict(SF_EYES_DARK)
for _k in range(len(SF_EYE_SEGS)):
    sf_wilt_eyes["eye%d_%d_0" % (SF_SURVIVOR, _k)] = SF_OPEN
rig.clip(sf_arm, "seefern_wilt", [
    (0.0, dict(SF_EYES_DARK, sfflash_0=SF_SHUT)),
    (2.2, dict(sf_droop, **dict(sf_wilt_eyes, sfflash_0=SF_SHUT)))])
# A fern nobody has worked stands wild, fronds as modelled, tending flare shut.
rig.park(sf_arm, dict(SF_EYES_DARK, sfflash_0=SF_SHUT))

sf_report = rig.validate(sf_piece, sf_arm,
                         dict(("frond%d" % i, SF_SEGMENTS) for i in range(len(SF_FRONDS))))
print("[RIG] Seefern %s bones=%d dead=%s orphans=%d"
      % (sf_report["verdict"], sf_report["bones"],
         sf_report["dead_bones"] or "none", sf_report["orphan_verts"]))
if sf_report["verdict"] != "PASS":
    raise SystemExit("seefern rig does not deform: %s" % sf_report["problems"])


# ============================================================================
# CAPBAGE — the tight hide. Its silhouette priority is "dense head of overlapping
# leaves with a visible CAVITY at the apex ... the cavity tells the player
# shelter", and the sealed state folds those leaves inward "via pulvini at the
# base of each leaf" into a tight near-spherical head whose surface is NOT smooth:
# "individual leaf-overlap remains visible as fine textural seam-lines".
#
# So the leaves are cards (broad blades with cream ribs, drawn), each rigged with
# its own chain, and SEALING is the animation that closes them over the cavity.
# The spec even prices it: 1-2 s sealed when tended, 2-3 s when wild, and the wild
# plant "opens prematurely sometimes".
# ============================================================================

# "A large DENSE head of overlapping concentric leaf layers" — density is the read,
# so the tiers carry enough leaves to overlap their neighbours rather than showing
# gaps between them, and each leaf is broad rather than strap-like.
# TEN SHELLS, NOT TWENTY-NINE. The sheet's closed head is divided by cream seams
# into about ten broad panels and its open head peels back the same ten; built as
# three tiers of small blunt flaps the plant read as a hop cone rather than a
# cabbage. Each shell's azimuth is (pi / count), so cutting the count is what
# makes them broad — the head still closes because they are cut from the dome.
CB_TIERS = [                       # (count, ring radius, height, leaf length, tilt)
    (6, 0.46, 0.22, 0.80, 1.16),   # outer, tips reaching the ground when splayed
    (4, 0.30, 0.60, 0.62, 0.52),   # inner ring cupping the cavity
]
CB_SEGMENTS = 3
# the dome the shells are bent around: a Capbage sealed IS this sphere
CB_DOME_C = (0.0, 0.0, 0.46)
CB_DOME_R = 0.54
CB_LEAVES = []                     # (prefix, vert_start, ring_r, z, tilt, azimuth)
CB_FLASH_START = 0
CB_CORE_START = 0


def _capbage_leaf_art(tile, isl, px_per_m):
    """A broad waxy leaf blade: deep green body, a prominent CREAM midrib running
    its length with side ribs branching off it, and a paler edge where the light
    catches the wax. The ribs are the spec's "prominent cream-colored veins" and
    they are what make the sealed head read as overlapping leaves rather than a
    smooth dome, since every seam on the closed plant is one of these edges."""
    ph, pw = tile.shape[:2]
    body = _dim(CH("moss"), 0.55)
    body_d = _dim(CH("moss"), 0.34)
    rib = CS("resolution_root_pale")
    rib_d = _dim(CS("resolution_root_pale"), 0.62)
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))
    for row in range(ph):
        t = row / float(max(1, ph - 1))
        half = (pw * 0.5) * (0.55 + 0.45 * math.sin(math.pi * min(1.0, t * 1.12)))
        lo = max(0, int(round(mid - half)))
        hi = min(pw - 1, int(round(mid + half)))
        if hi <= lo:
            continue
        tile[row, lo:hi + 1, :3] = body
        tile[row, lo:hi + 1, 3] = 1.0
        tile[row, lo, :3] = body_d                 # the leaf's own edge line
        tile[row, hi, :3] = body_d
        tile[row, mid, :3] = rib                   # the cream midrib
    step = max(2, int(round(0.09 * px_per_m)))
    for row in range(1, ph - 1, step):             # side ribs branching off it
        t = row / float(max(1, ph - 1))
        reach = int(round((pw * 0.5) * (0.5 + 0.42 * math.sin(math.pi * t))))
        for side in (-1, 1):
            for k in range(1, max(1, reach)):
                col = mid + side * k
                r2 = row + (k // 3)
                if 0 <= col < pw and 0 <= r2 < ph and tile[r2, col, 3] > 0.5:
                    tile[r2, col, :3] = rib_d


def _capbage_rosette_art(tile, isl, px_per_m):
    """One flat lobed leaf of the basal rosette, seen from above. The sheet lays a
    ring of these out on the substrate under the head; the lobed outline is the
    whole read, and it belongs in the ALPHA rather than in geometry — a modelled
    lobe would cost a mesh per leaf for a shape the silhouette already carries."""
    ph, pw = tile.shape[:2]
    body = _dim(CH("moss"), 0.60)
    body_d = _dim(CH("moss"), 0.40)
    rib = _dim(CS("resolution_root_pale"), 1.02)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            u = (x - cx) / max(1.0, cx)
            v = (y - cy) / max(1.0, cy)
            # a leaf tapering to a tip, with lobes cut along both margins
            span = 1.0 - abs(v) ** 1.6
            lobe = 0.86 + 0.14 * math.cos(v * math.pi * 5.0)
            if span <= 0.0 or abs(u) > span * lobe:
                continue
            tile[y, x, 3] = 1.0
            if abs(u) < 0.09:
                tile[y, x, :3] = rib               # the cream midrib
            else:
                h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
                tile[y, x, :3] = body if (h & 3) else body_d


CB_ART = pl.register_card_art("rigged_capbage_leaf", _capbage_leaf_art)
CB_ROSETTE_ART = pl.register_card_art("rigged_capbage_rosette",
                                      _capbage_rosette_art)

pl.register_parts({
    "cb_leaf": {"rgb": _dim(CH("moss"), 0.55)},
    "cb_stem": {"rgb": _dim(CH("moss"), 0.32)},
    "cb_void": {"rgb": _dim(CH("ground"), 0.12)},
    "cb_flash": {"rgb": CS("resolution_root_pale"), "emit": CH("flora")},
    # the pale drum inside the head and the crystal standing on it — the thing the
    # eye lands on the moment the shells part, and the reason an open Capbage
    # reads as offering something rather than merely being ajar
    "cb_core": {"rgb": _dim(CS("resolution_root_pale"), 1.06)},
    "cb_flower": {"rgb": _dim(CS("seefern_vein_core"), 0.99)},
    "cb_pod": {"rgb": _dim(CH("moss"), 0.44)},
}, emit_strength={"cb_flash": 3.2})


def build_capbage_rigged():
    """The closet-scale head: a short thick stem, the dark cavity it wraps, and
    three concentric tiers of leaf cards that fold over it. The stem and the void
    are geometry — one is the thing it stands on, the other is the hole the player
    reads as a doorway — and every leaf is a segmented card so it can curl."""
    b = Builder()
    b.ngon_prism((0, 0), 0.20, 0.26, 0.22, "cb_stem", sides=9)
    # the cavity: a dark cup sunk INSIDE the leaf dome. It has to sit below the
    # inner tier's tips or it reads as a column standing above the plant instead
    # of the recess the spec calls a doorway.
    # THE CAVITY IS THE PLANT. A Capbage is a tight hide — a character gets INSIDE
    # it — and the sheet's silhouette is a dome with a hole through it, the hollow
    # read as negative space. This was a solid prism 40 cm tall standing in the
    # dead centre: the shelter filled in with a post, so the one thing the species
    # exists for could not be seen from any angle. It is the chamber's FLOOR now,
    # low enough that the shells enclose air above it.
    b.ngon_prism((0, 0), 0.24, 0.26, 0.09, "cb_void", sides=10, z0=0.18)
    # THE LEAVES ARE SHELLS, not flat cards. A Capbage closes into a sphere and
    # opens into a rosette around a cavity a character climbs into; a ring of flat
    # planes standing in a circle can neither close nor enclose anything, which is
    # why the plant read as a jumble with a post in the middle of it. Each leaf is
    # bent around the dome it belongs to, and carries the same two-verts-per-row
    # layout a card does, so the rig and the weighting are untouched.
    for ti, (count, ring_r, z, L, tilt) in enumerate(CB_TIERS):
        for i in range(count):
            a = (math.tau * i / count) + (0.4 if count % 2 else 0.0)
            z1 = min(CB_DOME_C[2] + CB_DOME_R * 0.985, z + L)
            CB_LEAVES.append(("cb%d" % len(CB_LEAVES), len(b.bm.verts),
                              ring_r, z, tilt, a, z, z1))
            b.shell(CB_DOME_C, CB_DOME_R, a, (math.pi / count) * 0.92,
                    z, z1, "cb_leaf", segments=CB_SEGMENTS, art=CB_ART,
                    bulge=1.0 + 0.05 * ti)
    global CB_FLASH_START, CB_CORE_START
    CB_FLASH_START = len(b.bm.verts)
    b.card((0, 0, 1.02), (0.66, 0.66), "cb_flash", axis='Z')
    b.card((0, 0, 1.02), (0.66, 0.66), "cb_flash", axis='Y')

    # WHAT THE OPEN HEAD SHOWS. All three of these are drawn on every panel of the
    # sheet and none of them existed: the head opened onto nothing, the plant
    # ended in mid-air with bare ground under it, and the silhouette's own base
    # was missing.
    CB_CORE_START = len(b.bm.verts)
    # the pale receptacle: a flat-topped drum standing in the cavity
    b.ngon_prism((0.0, 0.0), 0.185, 0.225, 0.10, "cb_core", sides=11, z0=0.40)
    # the crystalline flower on top of it, a small upright star
    for k in range(7):
        a = math.tau * k / 7 + 0.2
        b.limb((math.cos(a) * 0.014, math.sin(a) * 0.014, 0.50),
               (math.cos(a) * 0.058, math.sin(a) * 0.058, 0.565),
               0.017, 0.005, "cb_flower", sides=4)
    b.ngon_prism((0.0, 0.0), 0.024, 0.040, 0.045, "cb_flower", sides=6, z0=0.495)
    # the basal rosette: flat lobed leaves lying ON the substrate, drawn because a
    # lobed outline is silhouette detail and a modelled one would cost a mesh per
    # leaf for a shape the alpha carries
    for k in range(7):
        a = math.tau * k / 7 + 0.35
        b.card((math.cos(a) * 0.60, math.sin(a) * 0.60, 0.016), (0.62, 0.42),
               "cb_leaf", axis='Z', art=CB_ROSETTE_ART, rot=(0.0, 0.0, a))
    # and the ring of teardrop pods tucked under the skirt
    for k in range(9):
        a = math.tau * k / 9 + 0.15
        b.ngon_prism((math.cos(a) * 0.40, math.sin(a) * 0.40), 0.030, 0.052,
                     0.105, "cb_pod", sides=6, z0=0.0)
    return b.finish("CapbageRigged")


def capbage_chains():
    chains = []
    # the chain climbs the SAME meridian the shell was cut on, so the rest pose
    # matches the geometry instead of a straight line through the middle of it
    for (prefix, _start, ring_r, z, tilt, a, z0, z1) in CB_LEAVES:
        pts = []
        for s2 in range(CB_SEGMENTS + 1):
            f = s2 / float(CB_SEGMENTS)
            zz = z0 + (z1 - z0) * f
            dz = (zz - CB_DOME_C[2]) / CB_DOME_R
            r = CB_DOME_R * math.sqrt(max(0.0, 1.0 - dz * dz))
            pts.append((math.cos(a) * r, math.sin(a) * r, zz))
        chains.append({"prefix": prefix, "points": pts})
    chains.append({"prefix": "cbflash", "points": [(0.0, 0.0, 0.98), (0.0, 0.0, 1.06)]})
    # The receptacle, the flower, the rosette and the pods stand STILL while the
    # head works. cb0_0 is a leaf's own bone, so hanging them there would swing
    # the plant's centre every time that one shell moved.
    chains.append({"prefix": "cbcore", "points": [(0.0, 0.0, 0.0), (0.0, 0.0, 0.62)]})
    return chains


cb_piece = build_capbage_rigged()
pl.texture_object(cb_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
cb_arm = rig.build_armature("Capbage", capbage_chains())
rig.bind(cb_piece, cb_arm, kind='ARMATURE_NAME')
for (prefix, start, _r, _z, _t, _a, _z0, _z1) in CB_LEAVES:
    rig.weight_chain_strip(cb_piece, prefix, rig.card_rows(start, CB_SEGMENTS))
rig.assign_exclusive_weights(cb_piece, "cbflash_0",
                             range(CB_FLASH_START, CB_CORE_START))
rig.assign_exclusive_weights(cb_piece, "cbcore_0",
                             range(CB_CORE_START, len(cb_piece.data.vertices)))
rig.assign_exclusive_weights(cb_piece, "cb0_0", range(0, CB_LEAVES[0][1]))

CB_SHUT, CB_OPEN = 0.001, 1.0
# SEAL: every leaf curls inward over the cavity, the inner ring leading because it
# is already cupping it. The curl travels along each leaf rather than hinging at
# its base, which is what "folded inward via pulvini" looks like.
cb_splayed = {}
for li, (prefix, _s, _r, _z, _t, _a, _z0, _z1) in enumerate(CB_LEAVES):
    tier = 0 if li < CB_TIERS[0][0] else 1
    # bring each tier from its resting tilt up past vertical so the tips converge
    # over the apex; the outer skirt travels furthest because it starts lowest
    # THE REST POSE IS NOW THE SEALED SPHERE. These angles hauled FLAT cards up
    # from a splayed rest and over the apex; applied to shells that already lie on
    # the dome they throw the head open instead of shutting it. Sealing is a
    # tightening now — the shells draw together over a cavity they are already
    # cupping — and it is the OPENING that has to travel, which is the state this
    # plant is actually read by.
    # THE SHELLS ARE CUT FROM THE DOME, so zero rotation IS the sealed head — the
    # geometry cannot be authored any other way and still close. But the spec says
    # an unused Capbage stands SPLAYED OPEN, so the poses invert around it: resting
    # splays the shells outward and sealing brings them home to the dome. Building
    # them splayed instead would mean cutting them from a shape the plant is never
    # in, and they would not meet when it shut.
    # SMALL. A flat card standing splayed had to swing most of a right angle per
    # joint to reach the apex; a shell already lying on the dome only has to lean
    # off it. Carrying the old magnitudes over rotated each shell through more
    # than a half turn and scattered the head into confetti.
    # THE OUTER SKIRT PEELS, THE INNER RING BARELY MOVES. Opening every tier by
    # roughly the same angle loosens the head evenly and the tips still meet over
    # the top, which is a loose head and not a doorway. The sheet lays the outer
    # shells well back off a wide mouth while the innermost ones only lean — the
    # cavity is made by the DIFFERENCE between the tiers, not by the total.
    # A SHELL SWINGS ON ITS HINGE; IT DOES NOT CURL. chain_wave turns every joint,
    # which rolls each shell up like a scroll — the tip travels a long way but ends
    # pointing back over the mouth it was supposed to uncover, and past a certain
    # angle the whole head just scatters. A leaf that opens a shelter pivots at its
    # BASE and stays straight, so the base bone takes almost all of the rotation
    # and the two above it only relax.
    # THE INNER RING OPENS MOST, NOT THE SKIRT. The mouth is at the TOP, so it is
    # the inner tier — the one cupping the cavity at z=0.78 — that has to lean off
    # the apex to uncover it, while the outer skirt stays up to be the bowl's wall.
    # Peeling the skirt hardest does the opposite: it throws the bottom open while
    # the inner shells still meet over the mouth, which is a loose head with no
    # aperture, and that is what shipped.
    #
    # The sign matters as much as the split. The shells are cut FROM the dome, so a
    # NEGATIVE rotation tightens them back onto the sphere they came from; only a
    # positive one lifts them off it. It was negative, which is why a pose the
    # comments correctly described as splaying open produced a sealed head.
    amount = (0.42, 1.05)[tier]
    cb_splayed[prefix + "_0"] = (amount, 0.0, 0.0)
    for _sg in range(1, CB_SEGMENTS):
        cb_splayed["%s_%d" % (prefix, _sg)] = (amount * 0.12, 0.0, 0.0)
# part-way home from splayed, and the slip a wild one makes on the way
cb_part = dict((k, (v[0] * 0.45, v[1], v[2])) for k, v in cb_splayed.items())
cb_ease = dict((k, (v[0] * 0.70, v[1], v[2])) for k, v in cb_splayed.items())

# Tended: 1-2 s, the spec's fast seal. It "holds the seal as long as threats remain".
rig.clip(cb_arm, "capbage_seal", [
    (0.0, dict(cb_splayed, cbflash_0=CB_SHUT)),
    (0.55, dict(cb_part, cbflash_0=CB_SHUT)),
    (1.25, dict(cbflash_0=CB_SHUT)),          # home to the dome: the sealed head
])
# Wild: 2-3 s and it "opens prematurely sometimes" -- the slow seal shudders back
# part-way before it finally holds.
rig.clip(cb_arm, "capbage_seal_wild", [
    (0.0, dict(cb_splayed, cbflash_0=CB_SHUT)),
    (1.1, dict(cb_part, cbflash_0=CB_SHUT)),
    (1.7, dict(cb_ease, cbflash_0=CB_SHUT)),   # the premature slip the spec names
    (2.8, dict(cbflash_0=CB_SHUT)),
])
# OPEN: the head parts again and the cavity reads as a doorway.
rig.clip(cb_arm, "capbage_open", [
    (0.0, dict(cbflash_0=CB_SHUT)),                       # sealed
    (0.9, dict(cb_splayed, cbflash_0=CB_SHUT)),           # and parted to a doorway
])
# TEND: "the leaves visibly thicken, additional inner leaf-layers grow inward, and
# the cavity becomes more clearly defined" -- the leaves flex open a little past
# rest and settle, and the flash closes the work.
cb_flex = {}
for (prefix, _s, _r, _z, _t, _a, _z0, _z1) in CB_LEAVES:
    cb_flex.update(rig.chain_wave(prefix, CB_SEGMENTS, -0.20, lead=0.5))
cb_flex = dict((k, (cb_splayed[k][0] + v[0], v[1], v[2])) for k, v in cb_flex.items())
# tending works the plant in its OPEN state, so it flexes a little past the splay
# and settles back to it rather than to the dome
rig.clip(cb_arm, "capbage_tend", [
    (0.0, dict(cb_splayed, cbflash_0=CB_SHUT)),
    (1.5, dict(cb_flex, cbflash_0=CB_SHUT)),
    (2.15, dict(cb_splayed, cbflash_0=CB_SHUT)),
    (2.28, dict(cb_splayed, cbflash_0=CB_OPEN)),
    (2.6, dict(cb_splayed, cbflash_0=CB_SHUT)),
])
# A Capbage nobody is using stands SPLAYED OPEN — the state the spec reads as
# holding nothing — with the tending flare shut.
rig.park(cb_arm, dict(cb_splayed, cbflash_0=CB_SHUT))

cb_report = rig.validate(cb_piece, cb_arm,
                         dict((p, CB_SEGMENTS) for (p, _s, _r, _z, _t, _a, _z0, _z1) in CB_LEAVES))
print("[RIG] Capbage %s bones=%d dead=%s orphans=%d"
      % (cb_report["verdict"], cb_report["bones"],
         cb_report["dead_bones"] or "none", cb_report["orphan_verts"]))
if cb_report["verdict"] != "PASS":
    raise SystemExit("capbage rig does not deform: %s" % cb_report["problems"])


# ============================================================================
# SCARPET — the two-tone moss carpet. Its tending is the one transition in the
# roster that is not a fold: "Peris kneels at the patch edge and presses her palms
# flat against the moss, working outward in slow circular motions ... The carpet
# visibly EXPANDS during tending", and "the visible expansion of the patch
# boundary tells the player when work is paying off".
#
# So the carpet GROWS. A patch bone scales the whole mat outward, and each pillow
# tuft rides its own bone so the body of the carpet spreads with the boundary
# rather than the mat stretching under a static fringe.
# ============================================================================

# Every tuft stands well inside the mat's ragged alpha boundary (which never draws
# closer in than 0.62 of the half-extent), because a tuft past the edge reads as a
# stray weed floating beside the carpet rather than part of its body.
def _sc_tufts():
    """The clumps that give the carpet a SURFACE. Card ENT-015 shows a shaggy bed
    with real relief, not a decal: a handful of strands over a painted mat reads as
    moss printed on the floor, so the patch is crowded with short clumps at mixed
    heights and angles. Placed from a hash rather than by hand — the pattern has to
    be irregular to read as growth, and identical on every rebuild."""
    out = []
    # DENSE, because the SHEET is dense. The turnaround shows the pad packed with
    # bushy tufts shoulder to shoulder over most of its surface; sixteen clumps put
    # sparse specks on a bare plate, which is what the render actually looked like.
    #
    # This was sparse on purpose, citing the brief — "never a mound", "avoid dense
    # lawn grass", let the pale substrate show. That prose and the drawing disagree,
    # and the drawing wins: the docs were the springboards that GENERATED the sheet,
    # not a specification of it. The brief's real point survives at this density
    # anyway — the tufts are still discrete clumps at mixed heights with crust
    # visible between them, not a continuous mown lawn.
    rings = ((0.0, 3, 0.0), (0.11, 7, 0.35), (0.20, 11, 0.12),
             (0.28, 14, 0.55), (0.35, 10, 0.28))
    for (radius, count, phase) in rings:
        for i in range(count):
            a = math.tau * i / count + phase
            h = ((i * 73856093) ^ (int(radius * 1000) * 19349663)) & 0xFFFF
            jitter = ((h % 100) / 100.0 - 0.5) * 0.06
            px = math.cos(a) * (radius + jitter)
            py = math.sin(a) * (radius + jitter) * 0.84
            # SMALL, so the crust shows between them. At a quarter of the patch's
            # own width each clump abuts its neighbours and the sixteen of them
            # tile into a continuous lawn — which is the one thing the brief rules
            # out ("never a mound", "avoid dense lawn grass") and which also hides
            # the pale plate substrate the sprigs are supposed to be standing on.
            width = 0.11 + ((h >> 4) % 100) / 100.0 * 0.09
            yaw = ((h >> 8) % 628) / 100.0
            out.append((px, py, width, yaw))
    return out


SC_TUFTS = _sc_tufts()
SC_MAT_SEGMENTS = 1
SC_MAT_START = 0
SC_TUFT_START = []
SC_FLASH_START = 0


def _scarpet_mat_art_rigged(tile, isl, px_per_m):
    """Living moss worked through with the rust scars of metabolised iron, and the
    bleached substrate showing where the moss has finished. The boundary is ragged
    because a rug that ends in a straight line reads as a decal laid on the floor
    rather than something that grew there."""
    ph, pw = tile.shape[:2]
    green = CS("scarpet_blade")
    green_d = CS("scarpet_blade_deep")
    rust = CS("scarpet_senesce")
    rust_d = _dim(CS("scarpet_senesce"), 0.55)
    bleach = _dim(CS("resolution_root_pale"), 1.14)
    bleach_d = _dim(CS("resolution_root_pale"), 0.94)

    def h2(x, y, sd):
        n = (x * 73856093) ^ (y * 19349663) ^ (sd * 83492791)
        n = (n ^ (n >> 13)) & 0xFFFFFFF
        return (n % 1000) / 1000.0

    def smooth(x, y, cell, sd):
        gx, gy = x // cell, y // cell
        fx, fy = (x % cell) / cell, (y % cell) / cell
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        a, b = h2(gx, gy, sd), h2(gx + 1, gy, sd)
        c, d = h2(gx, gy + 1, sd), h2(gx + 1, gy + 1, sd)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    cell = max(3, int(round(0.22 * px_per_m)))
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / cx, (y - cy) / cy
            r = (dx * dx + dy * dy) ** 0.5
            if r > 0.62 + 0.34 * smooth(x, y, cell * 2, 5):
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            worked = smooth(x, y, cell, 1)
            fleck = h2(x, y, 9)
            # THE SUBSTRATE IS THE GROUND THE EYE READS FIRST, and the moss is
            # what grows in patches on it. The proportions were the other way
            # round — moss over two thirds of the mat with bare crust rarest of
            # all — which is why the carpet read as a solid green bed whatever was
            # done to the clumps standing on it. The sheet is a bone-pale plate
            # crust with green and rust worked through it in zones.
            if worked > 0.72:
                col = green if fleck > 0.42 else green_d
            elif worked > 0.52:
                col = rust if fleck > 0.35 else rust_d
            else:
                col = bleach if fleck > 0.30 else bleach_d
            tile[y, x, :3] = col


def _scarpet_tuft_art_rigged(tile, isl, px_per_m):
    """The carpet seen edge-on — the spec puts its body 5-10 cm off the substrate,
    so a few of these keep it from reading as a decal painted on the floor."""
    _scarpet_sprigs(tile, CS("scarpet_blade"), CS("scarpet_blade_deep"))


def _scarpet_rust_art(tile, isl, px_per_m):
    """The same growth gone over to oxide. The sheet stands its rust sprigs up
    beside the green ones at roughly equal presence and lets them take the patch
    over entirely as it senesces; printing rust as flecks on the mat instead
    leaves a plant that can only ever be green."""
    _scarpet_sprigs(tile, CS("scarpet_senesce"), _dim(CS("scarpet_senesce"), 0.72))


def _scarpet_sprigs(tile, tip, deep):
    """FORKED sprigs, not a cushion. The sheet's growth is fine branching stems
    with the crust plainly visible between them; filling every column solid from
    the base gives a pillow, and a row of pillows merges into one green mass with
    no substrate showing anywhere."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0

    def stem(x0, y0, ang, length, depth):
        n = max(2, int(length))
        for i in range(n):
            t = i / float(n - 1)
            x = int(round(x0 + math.cos(ang) * length * t))
            y = int(round(y0 + math.sin(ang) * length * t))
            for ox in (0, 1):
                px = x + ox
                if 0 <= px < pw and 0 <= y < ph:
                    tile[y, px, 3] = 1.0
                    tile[y, px, :3] = tip if t > 0.55 else deep
        if depth <= 0:
            return
        bx = x0 + math.cos(ang) * length * 0.62
        by = y0 + math.sin(ang) * length * 0.62
        for sgn in (-1.0, 1.0):
            stem(bx, by, ang + sgn * 0.62, length * 0.52, depth - 1)

    count = max(3, pw // 6)
    for s in range(count):
        x0 = (s + 0.5) * pw / float(count) + ((s * 29) % 5) - 2
        stem(x0, 0.0, math.pi * 0.5 + (((s * 17) % 7) - 3) * 0.09,
             ph * (0.62 + 0.055 * ((s * 13) % 5)), 2)


def _scarpet_flash_art(tile, isl, px_per_m):
    """The completion flare, drawn rather than modelled. A bare quad reads as a
    lit card standing over the plant; what sells a flash is that it has no edge,
    so the alpha falls to nothing well before the card does and the brightest
    pixels sit in a small core with pixel-art spokes running out of it."""
    ph, pw = tile.shape[:2]
    core = _dim(CH("flora"), 1.0)
    warm = CS("scarpet_blade")
    emit = isl.get("emit") if isinstance(isl, dict) else None
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            ang = math.atan2(dy, dx)
            spoke = abs(math.cos(ang * 4.0)) ** 6
            reach = 0.34 + 0.60 * spoke
            if r > reach:
                tile[y, x, 3] = 0.0
                continue
            k = 1.0 - (r / reach)
            k = k * k
            # Quantised so the falloff steps like the rest of the pixel art
            # instead of reading as a smooth engine-made gradient.
            k = round(k * 5.0) / 5.0
            if k <= 0.0:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = [core[i] * k + warm[i] * (1.0 - k) for i in range(3)]
            if emit is not None:
                emit[y, x] = [core[i] * k for i in range(3)]


SC_MAT_ART = pl.register_card_art("rigged_scarpet_mat", _scarpet_mat_art_rigged)
SC_TUFT_ART = pl.register_card_art("rigged_scarpet_tuft", _scarpet_tuft_art_rigged)
SC_RUST_ART = pl.register_card_art("rigged_scarpet_rust", _scarpet_rust_art)
SC_FLASH_ART = pl.register_card_art("rigged_scarpet_flash", _scarpet_flash_art)

pl.register_parts({
    # THE SUBSTRATE IS THE PALE THING AND THE SPRIGS STAND ON IT. Both were
    # scarpet_blade — the mat painted the same green as the moss growing out of
    # it — so the carpet read as one solid green mass where the sheet draws a
    # bone-pale plate crust with sparse clumps on top. Same inversion the Crust
    # shipped: the ground under a growth has to be lighter than the growth, or
    # there is nothing for the growth to read against.
    "sc_mat": {"rgb": _dim(CS("resolution_root_pale"), 1.18)},
    "sc_moss": {"rgb": CS("scarpet_blade")},
    "sc_rust": {"rgb": CS("scarpet_senesce")},
    "sc_slab": {"rgb": _dim(CS("resolution_root_pale"), 0.86)},
    "sc_flash": {"rgb": CS("scarpet_blade"), "emit": CH("flora")},
}, emit_strength={"sc_flash": 3.0})


def build_scarpet_rigged():
    """One drawn carpet plus a low ring of pillow tufts, all riding a patch bone so
    the whole thing can grow outward from its centre."""
    b = Builder()
    global SC_MAT_START, SC_FLASH_START
    SC_MAT_START = len(b.bm.verts)
    # THE SUBSTRATE IS A SLAB. Every panel draws interlocking plates with real
    # thickness and a stepped rim whose depth you can see; a zero-thickness quad
    # leaves the growth standing on a decal. The polygonal edge is the plate
    # boundary, which is what steps the rim at this poly count.
    b.ngon_prism((0.0, 0.0), 0.66, 0.60, 0.055, "sc_slab", sides=17, z0=0.0)
    b.card((0, 0, 0.070), (1.36, 1.14), "sc_mat", axis='Z', art=SC_MAT_ART,
           segments=SC_MAT_SEGMENTS)
    for ti, (px, py, w, yaw) in enumerate(SC_TUFTS):
        SC_TUFT_START.append(len(b.bm.verts))
        rusty = (ti % 3) == 2
        b.card((px, py, 0.145), (w, 0.17), "sc_rust" if rusty else "sc_moss",
               axis='Y', art=SC_RUST_ART if rusty else SC_TUFT_ART,
               rot=(0.0, 0.0, yaw))
    # The flare lies FLAT just over the moss: what completes is the patch, so the
    # whole patch lights. A pair of crossed billboards standing over it reads as a
    # lit card someone planted in the carpet.
    SC_FLASH_START = len(b.bm.verts)
    b.card((0, 0, 0.07), (1.7, 1.5), "sc_flash", axis='Z', art=SC_FLASH_ART)
    return b.finish("ScarpetRigged")


def scarpet_chains():
    """ONE patch bone standing at the centre of the carpet, with every tuft riding
    it. Growth here is uniform — the whole boundary moves outward together — so a
    chain of row bones would be wrong twice over: each would scale about its own
    head and tear the mat into strips, and the carpet would grow along its length
    instead of outward from where Peris is kneeling."""
    chains = [{"prefix": "patch", "points": [(0.0, 0.0, 0.012), (0.0, 0.0, 0.34)]}]
    for ti, (px, py, w, yaw) in enumerate(SC_TUFTS):
        chains.append({"prefix": "tuft%d" % ti, "parent": "patch_0",
                       "points": [(px, py, 0.012), (px, py, 0.17)]})
    chains.append({"prefix": "scflash", "parent": "patch_0",
                   "points": [(0.0, 0.0, 0.07), (0.0, 0.0, 0.30)]})
    return chains


sc_piece = build_scarpet_rigged()
pl.texture_object(sc_piece, OBJX, px_per_m=32.0, painted_dir=PAINTED)
sc_arm = rig.build_armature("Scarpet", scarpet_chains())
rig.bind(sc_piece, sc_arm, kind='ARMATURE_NAME')
rig.assign_exclusive_weights(sc_piece, "patch_0",
                             range(SC_MAT_START, SC_TUFT_START[0]))
for ti, start in enumerate(SC_TUFT_START):
    end = SC_TUFT_START[ti + 1] if ti + 1 < len(SC_TUFT_START) else SC_FLASH_START
    rig.assign_exclusive_weights(sc_piece, "tuft%d_0" % ti, range(start, end))
rig.assign_exclusive_weights(sc_piece, "scflash_0",
                             range(SC_FLASH_START, len(sc_piece.data.vertices)))

SC_SHUT, SC_OPEN = 0.001, 1.0
# The carpet as MODELLED is the wild patch, because that is what a rest pose can
# be: a bone rests at scale 1.0, so whatever the mesh was built at is what a plant
# nobody has touched looks like. Tending therefore grows the patch ABOVE its
# authored size rather than starting below it — a clip that opened small would
# snap every placed Scarpet inward on its first frame and then spend eight seconds
# returning it to exactly the size it already was, which is no visible change at
# all across a tending.
SC_WILD, SC_TENDED = 1.0, 1.43
# Scaling the patch bone carries the tufts riding it outward, so the body of the
# carpet spreads with its boundary and no tuft has to be animated by hand.
sc_wild = {"patch_0": SC_WILD, "scflash_0": SC_SHUT}
sc_mid = {"patch_0": 1.23, "scflash_0": SC_SHUT}
sc_tended = {"patch_0": SC_TENDED, "scflash_0": SC_SHUT}
# The spec times the work at 8-10 s and makes the expanding boundary the progress
# read, so the clip spans it; a caller that tends faster scales the playback
# instead of getting a different animation.
rig.clip(sc_arm, "scarpet_tend", [
    (0.0, sc_wild),
    (4.0, sc_mid),
    (7.6, sc_tended),
    (7.9, dict(sc_tended, scflash_0=SC_OPEN)),   # the boundary has finished moving
    (8.4, dict(sc_tended, scflash_0=SC_SHUT)),
])
# WITHER: SENESCENCE IS A COLOUR TURN AT CONSTANT FOOTPRINT. The sheet's senescent
# panel is the same pad at the same size with every sprig gone rust — the ground
# it holds does not change, only what is standing on it. Drawing the patch bone in
# to 0.72 said the opposite: the moss retreating, which is what the TENDING clip
# runs backwards. The pad holds its extent and the sprigs settle instead, and the
# green-to-rust turn belongs to the card's own art, selected engine-side, because
# a colour is not a transform and a second body is not a state.
sc_settle = dict((("tuft%d_0" % ti), 0.86) for ti in range(len(SC_TUFTS)))
rig.clip(sc_arm, "scarpet_wither", [
    (0.0, sc_wild),
    (3.2, dict(sc_settle, patch_0=SC_WILD, scflash_0=SC_SHUT)),
])

# BURN: fire takes a REGION, not the patch. The damaged panel is a charred core
# with green sprigs still standing around the fringe — that is what tells a player
# the stretch can be crossed at its edge and reclaimed later. Every tuft already
# carries its own bone, so the clip is simply a matter of asking the inner ones to
# go and leaving the rest alone; a whole-patch collapse would erase the fringe that
# carries the whole read.
_SC_CORE = 0.42          # of the patch's half-extent
sc_burn = {}
for _ti, (_px, _py, _w, _yaw) in enumerate(SC_TUFTS):
    _r = math.hypot(_px, _py)
    sc_burn["tuft%d_0" % _ti] = 0.001 if _r < _SC_CORE else 0.92
rig.clip(sc_arm, "scarpet_burn", [
    (0.0, sc_wild),
    (0.5, dict((k, min(1.0, v * 1.15)) for k, v in sc_burn.items())),
    (1.6, dict(sc_burn, patch_0=SC_WILD, scflash_0=SC_SHUT)),
    (2.4, dict(sc_burn, patch_0=SC_WILD, scflash_0=SC_SHUT)),
])
# Park the armature where a plant nobody has tended stands: full wild patch, and
# the completion flare shut.
rig.park(sc_arm, {"patch_0": SC_WILD, "scflash_0": SC_SHUT})

sc_report = rig.validate(sc_piece, sc_arm, {"patch": SC_MAT_SEGMENTS})
print("[RIG] Scarpet %s bones=%d dead=%s orphans=%d"
      % (sc_report["verdict"], sc_report["bones"],
         sc_report["dead_bones"] or "none", sc_report["orphan_verts"]))
if sc_report["verdict"] != "PASS":
    raise SystemExit("scarpet rig does not deform: %s" % sc_report["problems"])


# ============================================================================
# FLURE — the iron decoy, and the one plant whose state change the game already
# drives. Its spec is a collapse: "a dying flure collapses from the CORE OUTWARD.
# The petals lose their metallic sheen first... The central core dries and cracks.
# The root system contracts." Card ENT-016 shows the two ends of it — tended
# stands upright under an open bronze trumpet, spent has the stem kinked over and
# the funnel hanging off the bend.
#
# So the stem is a CHAIN that folds, and the petals ride the rim on their own
# bones so they can shut after it. The pleating that makes a trumpet read as a
# trumpet is drawn on the petal cards, never modelled: nine petals is form, the
# ribs inside each one are repetition.
# ============================================================================

FL_PETALS = 9
FL_PETAL_SEG = 3          # enough rows for a petal to curl rather than hinge
FL_STEM_SEG = 3           # the stem's kink travels down these
FL_LEAVES = 6
FL_STEM_START = []
FL_PETAL_START = []
FL_LEAF_START = []
FL_CORE_START = 0
FL_FLASH_START = 0
FL_STEM_Z = [0.0, 0.26, 0.48, 0.66]
FL_TILT = 0.62            # the petals fan OUT into a trumpet, as the card shows
FL_BLADE_TILT = 1.30      # the rosette lies almost flat on the substrate
FL_BLADE_SEG = 2
FL_RIM_R = 0.125


def _fl_petal_base(a):
    """Where a petal springs from the throat rim."""
    return (math.sin(a) * FL_RIM_R, math.cos(a) * FL_RIM_R, 0.84)


def _flure_petal_art(tile, isl, px_per_m):
    """One petal of the trumpet: a bronze wedge, narrow at the throat and wide at
    the rim, pleated down its length and toothed along the top edge. Nine of these
    overlap into a continuous funnel wall, which is what the card shows — the
    petals are the form, the pleating inside each is the repetition, and repetition
    is drawn. The ribs stay close in value: a hard dark rib reads as a GAP between
    petals and breaks the wall back into separate prongs."""
    ph, pw = tile.shape[:2]
    bronze = CS("flure_bronze")
    rib = _dim(CS("flure_bronze"), 0.82)
    lit = _dim(CS("flure_bronze"), 1.2)
    burn = _dim(CS("flure_bronze"), 0.5)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    tooth = max(1, int(round(pw / 7.0)))
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)              # 0 at the throat, 1 at the rim
        half = cx * (0.30 + 0.70 * t)
        for x in range(pw):
            d = abs(x - cx)
            if d > half:
                continue
            # the rim is TOOTHED across its width; cutting per row instead would
            # notch a V down the middle of every petal
            if t > 0.9 and ((x // tooth) % 2) == 0:
                continue
            tile[row, x, 3] = 1.0
            k = int(d / max(1.0, half / 3.5))
            col = rib if k % 2 else bronze
            if d < half * 0.14:
                col = lit                          # the light down the petal's spine
            if t > 0.86 and ((x + row) % 4) == 0:
                col = burn                         # scorch near the rim
            tile[row, x, :3] = col


def _flure_blade_art(tile, isl, px_per_m):
    """A basal rosette blade — dark, keeled, with the rust flecking that says this
    plant is pulling iron out of the substrate it sits in."""
    ph, pw = tile.shape[:2]
    dark = _dim(CS("scarpet_blade_deep"), 0.72)
    deep = _dim(CS("scarpet_blade_deep"), 0.46)
    rust = _dim(CS("flure_core"), 0.6)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)
        half = max(1.0, cx * (1.0 - 0.72 * t * t))
        for x in range(pw):
            d = abs(x - cx)
            if d > half:
                continue
            tile[row, x, 3] = 1.0
            col = deep if d > half * 0.55 else dark
            if d < half * 0.12:
                col = dark
            h = ((x * 73856093) ^ (row * 19349663)) & 0xFFFFFF
            if (h % 100) < 2:                   # iron scars, scattered not striped
                col = rust
            tile[row, x, :3] = col


FL_PETAL_ART = pl.register_card_art("rigged_flure_petal", _flure_petal_art)
FL_BLADE_ART = pl.register_card_art("rigged_flure_blade", _flure_blade_art)

pl.register_parts({
    "fl_stem":  {"rgb": CS("scarpet_green")},
    "fl_petal": {"rgb": CS("flure_bronze")},
    "fl_blade": {"rgb": _dim(CS("scarpet_green"), 0.6)},
    "fl_core":  {"rgb": _dim(CS("flure_core"), 0.7), "emit": CS("flure_core")},
    "fl_flash": {"rgb": CS("flure_core"), "emit": CS("flure_core")},
}, emit_strength={"fl_core": 1.4, "fl_flash": 3.4})


def build_flure_rigged():
    """Waist-high: a stem of stacked segments under a throat cone, nine drawn
    petals fanned around it, a glowing filament core, and a splayed basal rosette."""
    b = Builder()
    global FL_CORE_START, FL_FLASH_START
    for i in range(FL_STEM_SEG):
        FL_STEM_START.append(len(b.bm.verts))
        z0, z1 = FL_STEM_Z[i], FL_STEM_Z[i + 1]
        # Each segment ends a little fatter than the next begins, so the seam the
        # stack cannot avoid reads as the NODE a stem actually swells at rather
        # than as a join between two pipes.
        r0 = 0.05 - 0.008 * i
        r1 = 0.05 - 0.008 * (i + 1)
        b.ngon_prism((0, 0), r1, r0, (z1 - z0) * 0.86, "fl_stem", sides=7, z0=z0,
                     cap_top=False, cap_bottom=(i == 0))
        b.ngon_prism((0, 0), r1, r1 * 1.24, (z1 - z0) * 0.14, "fl_stem", sides=7,
                     z0=z0 + (z1 - z0) * 0.86, cap_top=(i == FL_STEM_SEG - 1))
    # the throat the petals spring from rides the stem's last segment
    b.ngon_prism((0, 0), 0.135, 0.05, 0.2, "fl_petal", sides=FL_PETALS, z0=0.66)
    for i in range(FL_PETALS):
        a = i * math.tau / FL_PETALS
        length = 0.3 if i % 2 == 0 else 0.25
        bx, by, bz = _fl_petal_base(a)
        rr = math.sin(FL_TILT) * length * 0.5
        FL_PETAL_START.append(len(b.bm.verts))
        b.card((bx + math.sin(a) * rr, by + math.cos(a) * rr,
                bz + math.cos(FL_TILT) * length * 0.5),
               (0.23, length), "fl_petal", axis='Y', art=FL_PETAL_ART,
               rot=(FL_TILT, 0.0, a), segments=FL_PETAL_SEG)
    for i in range(FL_LEAVES):
        a = i * math.tau / FL_LEAVES + 0.26
        rr = math.sin(FL_BLADE_TILT) * 0.34 * 0.5
        FL_LEAF_START.append(len(b.bm.verts))
        b.card((math.sin(a) * (0.05 + rr), math.cos(a) * (0.05 + rr),
                0.03 + math.cos(FL_BLADE_TILT) * 0.34 * 0.5),
               (0.21, 0.34), "fl_blade", axis='Y', art=FL_BLADE_ART,
               rot=(FL_BLADE_TILT, 0.0, a), segments=FL_BLADE_SEG)
    FL_CORE_START = len(b.bm.verts)
    b.ngon_prism((0, 0), 0.03, 0.05, 0.07, "fl_core", sides=6, z0=0.83)
    FL_FLASH_START = len(b.bm.verts)
    b.card((0, 0, 0.9), (0.66, 0.66), "fl_flash", axis='Z')
    b.card((0, 0, 0.9), (0.66, 0.66), "fl_flash", axis='Y')
    return b.finish("FlureRigged")


def flure_chains():
    """The stem is one chain so its fold travels down it; every petal, blade and
    the core get their own bone so the collapse can run core-outward."""
    chains = [{"prefix": "stem",
               "points": [(0.0, 0.0, z) for z in FL_STEM_Z]}]
    # ONE POINT PER CARD ROW. A strip is weighted row by row, so a chain with
    # fewer joints than the card has rows leaves its top rows weighted to names no
    # bone answers to — they export onto the exporter's static neutral bone and
    # stay behind while the rest of the petal folds away.
    for i in range(FL_PETALS):
        a = i * math.tau / FL_PETALS
        length = 0.3 if i % 2 == 0 else 0.25
        bx, by, bz = _fl_petal_base(a)
        pts = []
        for sgi in range(FL_PETAL_SEG + 1):
            f = sgi / float(FL_PETAL_SEG)
            pts.append((bx + math.sin(a) * math.sin(FL_TILT) * length * f,
                        by + math.cos(a) * math.sin(FL_TILT) * length * f,
                        bz + math.cos(FL_TILT) * length * f))
        chains.append({"prefix": "petal%d" % i,
                       "parent": "stem_%d" % (FL_STEM_SEG - 1), "points": pts})
    for i in range(FL_LEAVES):
        a = i * math.tau / FL_LEAVES + 0.26
        pts = []
        for sgi in range(FL_BLADE_SEG + 1):
            f = sgi / float(FL_BLADE_SEG)
            r = 0.05 + math.sin(FL_BLADE_TILT) * 0.34 * f
            pts.append((math.sin(a) * r, math.cos(a) * r,
                        0.03 + math.cos(FL_BLADE_TILT) * 0.34 * f))
        chains.append({"prefix": "blade%d" % i, "points": pts})
    chains.append({"prefix": "core", "parent": "stem_%d" % (FL_STEM_SEG - 1),
                   "points": [(0.0, 0.0, 0.83), (0.0, 0.0, 0.93)]})
    chains.append({"prefix": "flflash", "parent": "stem_%d" % (FL_STEM_SEG - 1),
                   "points": [(0.0, 0.0, 0.86), (0.0, 0.0, 0.96)]})
    return chains


fl_piece = build_flure_rigged()
pl.texture_object(fl_piece, OBJX, px_per_m=48.0, painted_dir=PAINTED)
fl_arm = rig.build_armature("Flure", flure_chains())
rig.bind(fl_piece, fl_arm, kind='ARMATURE_NAME')
# the stem's stacked rings, one bone each, then the throat rides the top ring
for i, start in enumerate(FL_STEM_START):
    end = FL_STEM_START[i + 1] if i + 1 < len(FL_STEM_START) else FL_PETAL_START[0]
    rig.assign_exclusive_weights(fl_piece, "stem_%d" % i, range(start, end))
for i, start in enumerate(FL_PETAL_START):
    rig.weight_chain_strip(fl_piece, "petal%d" % i, rig.card_rows(start, FL_PETAL_SEG))
for i, start in enumerate(FL_LEAF_START):
    rig.weight_chain_strip(fl_piece, "blade%d" % i,
                           rig.card_rows(start, FL_BLADE_SEG))
rig.assign_exclusive_weights(fl_piece, "core_0", range(FL_CORE_START, FL_FLASH_START))
rig.assign_exclusive_weights(fl_piece, "flflash_0",
                             range(FL_FLASH_START, len(fl_piece.data.vertices)))

FL_SHUT, FL_OPEN = 0.001, 1.0
# TEND: the trumpet opens wider and the core swells. The plant as modelled is the
# WILD flure, so tending moves away from rest rather than toward it.
fl_open = {}
for i in range(FL_PETALS):
    fl_open["petal%d_0" % i] = (-0.34, 0.0, 0.0)
fl_tended = dict(fl_open, core_0=1.35, flflash_0=FL_SHUT)
rig.clip(fl_arm, "flure_tend", [
    (0.0, {"flflash_0": FL_SHUT}),
    (2.2, fl_tended),
    (2.45, dict(fl_tended, flflash_0=FL_OPEN)),
    (2.8, dict(fl_tended, flflash_0=FL_SHUT)),
])
# SPEND: the collapse, and it runs CORE OUTWARD as the spec says. The core dries
# first, the petals shut over it, the stem kinks at its top joint and carries the
# whole head over, and the rosette goes down last.
fl_spent = {"core_0": 0.35, "flflash_0": FL_SHUT}
for i in range(FL_PETALS):
    fl_spent["petal%d_0" % i] = (0.95 if i % 2 == 0 else 1.1, 0.0, 0.0)
for i in range(FL_LEAVES):
    fl_spent["blade%d_0" % i] = (0.24, 0.0, 0.0)
# The card holds the lower stem near vertical and folds it sharply just under the
# head. chain_wave is the rachis helper — it leads at the BASE and lags toward the
# tip, which bows the whole plant from the ground instead.
fl_kink = dict(fl_spent)
fl_kink.update({"stem_0": (0.04, 0.0, 0.0),
                "stem_1": (0.11, 0.0, 0.0),
                "stem_2": (0.62, 0.0, 0.0)})
rig.clip(fl_arm, "flure_spend", [
    (0.0, {"core_0": 1.0, "flflash_0": FL_SHUT}),
    (0.7, {"core_0": 0.35, "flflash_0": FL_SHUT}),          # the core dries first
    (1.6, fl_spent),                                        # the petals shut over it
    (3.0, fl_kink),                                         # the stem gives way
])
# A flure nobody has touched stands WILD: upright, trumpet open, flare shut.
rig.park(fl_arm, {"flflash_0": FL_SHUT})

# The STEM is declared too. It sits exactly at budget — 3 bones over FL_STEM_SEG
# subdivisions — so it passes today; declaring it is what stops a later change to
# either number from breaking the density law silently. An undeclared chain is not
# checked at all, and validate reports PASS either way.
fl_report = rig.validate(fl_piece, fl_arm,
                         dict([("petal%d" % i, FL_PETAL_SEG) for i in range(FL_PETALS)]
                              + [("blade%d" % i, 2) for i in range(FL_LEAVES)]
                              + [("stem", FL_STEM_SEG)]))
print("[RIG] Flure %s bones=%d dead=%s orphans=%d"
      % (fl_report["verdict"], fl_report["bones"],
         fl_report["dead_bones"] or "none", fl_report["orphan_verts"]))
if fl_report["verdict"] != "PASS":
    raise SystemExit("flure rig does not deform: %s" % fl_report["problems"])


# ============================================================================
# GASAFOETIDA — the repellent-pod umbellifer, and the roster's only plant with an
# IDLE transition: "the cluster's breathing motion is visible at close range", so
# standing still is itself something the player can read.
#
# Its other two states are both spec'd as sequences. Tending "produces a held
# pod", and the pods are SEROTINOUS — resin-sealed cones that "combust
# serotinously when ignited, ejecting flaming projectiles IN SEQUENCE", the
# lodgepole-pine behaviour the taxonomy names outright. So a pod is its own bone:
# it can breathe, it can be taken, and it can go off in its turn, leaving the
# charred stump card ENT-019_combusted shows still sitting on the umbel.
# ============================================================================

GA_PODS = 6               # a centre cone and five around it, as the card counts them
GA_STALK_SEG = 3
GA_LEAF_SEG = 2
# BIG ENOUGH TO BE A ROSETTE. At 0.30 and 0.24 these read as hair-thin wireframe
# strands round the stalk's foot; the sheet plants the column in a LUSH rosette of
# feathery fronds that reach out roughly as far as the stalk's lower third is tall
# and overlap each other into a skirt. Same failure as the Climbvine's rootlets and
# the Scarpet's tufts — correct structure, correct count, built below the size at
# which any of it reads. Cards are drawn at half their length wide, so lengthening
# broadens them too.
GA_LEAF_WHORLS = ((0.30, 8, 0.62), (0.50, 7, 0.50))   # (height, count, length)
GA_STALK_Z = [0.0, 0.38, 0.76, 1.08]
GA_UMBEL_Z = 1.08
GA_STALK_START = []
GA_POD_START = []
GA_LEAF_START = []
GA_RESIN_START = 0
GA_FLASH_START = 0
GA_CROWN = 3               # scales closing each pod's mouth
GA_SEAL_START = []
GA_CROWN_START = []
GA_BUD_START = []
GA_BUDS = 7
GA_POD_TOP = GA_UMBEL_Z + 0.20


def _ga_crown_seat(i, k):
    """Base and tip of one crown scale. The three lean together over the pod's
    mouth like the leaves of a bud; swinging them out is what OPENS it."""
    px, py = _ga_pod_at(i)
    a = math.tau * k / GA_CROWN + 0.4 + i * 0.3
    return ((px + math.cos(a) * 0.026, py + math.sin(a) * 0.026, GA_POD_TOP - 0.01),
            (px + math.cos(a) * 0.005, py + math.sin(a) * 0.005, GA_POD_TOP + 0.042))


def _ga_pod_at(i):
    """Where pod `i` stands on the umbel: one in the middle, the rest around it."""
    if i == 0:
        return (0.0, 0.0)
    a = math.tau * (i - 1) / (GA_PODS - 1) + 0.3
    return (math.cos(a) * 0.135, math.sin(a) * 0.135)


def _gasafoetida_leaf_art(tile, isl, px_per_m):
    """A pinnate comb-toothed leaf: a dark rachis with paired teeth stepping down
    it. The teeth are the repetition and they are drawn — a whorl of modelled
    leaflets would spend triangles to produce a worse read, and the comb is the
    silhouette the card is recognisable by."""
    ph, pw = tile.shape[:2]
    rachis = _dim(CS("gasafoetida_stalk"), 1.15)
    rachis_d = _dim(CS("gasafoetida_stalk"), 0.7)
    tooth = _dim(CS("gasafoetida_stalk"), 1.45)
    tooth_d = CS("gasafoetida_stalk")
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))
    for row in range(ph):
        tile[row, mid, :3] = rachis if row % 3 else rachis_d
        tile[row, mid, 3] = 1.0
    # DENSE PINNAE, not a comb. These were single-pixel rows at up to eleven
    # intervals, so the frond was a bare rachis with a few bars across it — at the
    # old hair-thin size that read as a wireframe speck, and once the fronds were
    # lengthened it read as a TV aerial. The sheet's fronds are feathery: pinnae
    # packed closely enough to fill the frond's own silhouette, tapering to a
    # curled tip. A pinna every OTHER row, staggered left and right so the two
    # sides interleave the way a real frond's do, fills it without turning it into
    # a solid blade.
    step = 2
    for row in range(0, ph, step):
        t = row / float(max(1, ph - 1))
        reach = int(round((pw * 0.5) * (1.0 - 0.55 * t * t)))
        if reach < 1:
            continue
        stagger = (row // step) % 2
        for side in (-1, 1):
            # one side runs a touch longer than the other on alternating rows,
            # which is what keeps the edge feathery instead of razor-straight
            end = reach - (1 if (stagger == (0 if side < 0 else 1)) else 0)
            for k in range(1, max(1, end) + 1):
                col = mid + side * k
                if 0 <= col < pw:
                    tile[row, col, :3] = tooth if k < end else tooth_d
                    tile[row, col, 3] = 1.0


def _gasafoetida_scale_detail(tile, mask, base, isl, px_per_m):
    """Overlapping cone scales, DRAWN.

    Every view of the sheet gives these pods an artichoke skin — rows of scales
    lapping over each other, each one lighter across its face and dark where the
    row below tucks under it. The build made the pods smooth prisms, so the crown
    read as six plain eggs. Scales are repetition, and the alpha-card law puts
    repetition in the texture: modelling a hundred lapping plates would spend
    triangles to produce a worse read, and at this size they would alias to mush.
    """
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    rows = max(3, int(round(ph / 4.0)))
    step = max(2, ph // rows)
    wide = max(3, pw // 6)          # narrower plates: six round a pod, not four
    for r, y in enumerate(range(0, ph, step)):
        off = (wide // 2) * (r % 2)          # every other row laps half a scale over
        for x0 in range(-off, pw, wide):
            # the shadow line the scale below tucks into
            if 0 <= y < ph:
                tile[y, max(0, x0):min(pw, x0 + wide)] = _dim(base, 0.62)
            # the scale face, brightest just under its own top edge
            for k in range(1, step):
                yy = y + k
                if not (0 <= yy < ph):
                    continue
                lit = 1.16 - 0.30 * (k / float(max(1, step - 1)))
                tile[yy, max(0, x0 + 1):min(pw, x0 + wide - 1)] = _dim(base, lit)
                # THE SIDE SEAM. Without it every scale in a row shares one
                # gradient and they merge into a horizontal BAND — which is what
                # the first attempt produced: a banded egg, not an artichoke. A
                # dark column at each scale's edge is what separates one plate
                # from its neighbour and lets the staggered rows read as lapping.
                if 0 <= x0 < pw:
                    tile[yy, x0] = _dim(base, 0.58)


GA_SCALE = pl.register_detail("gasafoetida_scale", _gasafoetida_scale_detail)
GA_LEAF_ART = pl.register_card_art("rigged_gasafoetida_leaf", _gasafoetida_leaf_art)

pl.register_parts({
    "ga_stalk": {"rgb": CS("gasafoetida_stalk")},
    "ga_umbel": {"rgb": _dim(CS("gasafoetida_stalk"), 1.3)},
    "ga_pod":   {"rgb": CS("gasafoetida_pod"),
                 "emit": _dim(CS("gasafoetida_pod"), 0.55)},
    # The resin that seals a serotinous cone, and weeps at the stalk's wound-point:
    # the tell that says this plant reacts to fire.
    "ga_resin": {"rgb": _dim(CS("flure_core"), 0.85), "emit": CS("flure_core")},
    "ga_char":  {"rgb": _dim(CS("gasafoetida_stalk"), 0.25)},
    "ga_bud":   {"rgb": _dim(CS("gasafoetida_stalk"), 1.55)},
    "ga_leaf":  {"rgb": CS("gasafoetida_stalk")},
    "ga_flash": {"rgb": CS("gasafoetida_pod"), "emit": CS("flure_core")},
}, emit_strength={"ga_pod": 0.8, "ga_resin": 1.4, "ga_flash": 3.2})


def build_gasafoetida_rigged():
    """Stalk-with-pinecones-on-top, which is the species' silhouette law: one tall
    stalk to a flat umbel carrying six resin-capped pods, over two whorls of drawn
    pinnate leaves. A charred stump sits under every pod, hidden inside it until
    the pod goes."""
    b = Builder()
    global GA_FLASH_START
    for i in range(GA_STALK_SEG):
        GA_STALK_START.append(len(b.bm.verts))
        z0, z1 = GA_STALK_Z[i], GA_STALK_Z[i + 1]
        r0 = 0.072 - 0.011 * i
        r1 = 0.072 - 0.011 * (i + 1)
        b.ngon_prism((0, 0), r1, r0, (z1 - z0) * 0.88, "ga_stalk", sides=8, z0=z0,
                     cap_top=False, cap_bottom=(i == 0))
        b.ngon_prism((0, 0), r1, r1 * 1.2, (z1 - z0) * 0.12, "ga_stalk", sides=8,
                     z0=z0 + (z1 - z0) * 0.88, cap_top=(i == GA_STALK_SEG - 1))
    b.ngon_prism((0, 0), 0.23, 0.2, 0.05, "ga_umbel", sides=9, z0=GA_UMBEL_Z)
    for i in range(GA_PODS):                       # the char each pod hides
        px, py = _ga_pod_at(i)
        b.ngon_prism((px, py), 0.05, 0.062, 0.035, "ga_char", sides=6,
                     z0=GA_UMBEL_Z + 0.05)
    # A POD IS A HOLLOW VESSEL, not a cone. The sheet's pod studies show it three
    # ways on purpose: sealed, bored open into a resin-lipped cup, and cut away to
    # prove the shell is empty. Built as one solid truncated cone there is nothing
    # for a crown to open ONTO, and "the crown bores open" has nowhere to happen.
    for i in range(GA_PODS):
        px, py = _ga_pod_at(i)
        GA_POD_START.append(len(b.bm.verts))
        b.ngon_prism((px, py), 0.082, 0.055, 0.055, "ga_pod", sides=7,
                     z0=GA_UMBEL_Z + 0.05, cap_top=False, detail=GA_SCALE)
        b.ngon_prism((px, py), 0.060, 0.082, 0.060, "ga_pod", sides=7,
                     z0=GA_UMBEL_Z + 0.105, cap_top=False, cap_bottom=False,
                     detail=GA_SCALE)
        b.ngon_prism((px, py), 0.032, 0.060, 0.035, "ga_pod", sides=7,
                     z0=GA_UMBEL_Z + 0.165, cap_top=False, cap_bottom=False,
                     detail=GA_SCALE)
        # THE RESIN SEALS IT, AND A SEAL OVERHANGS. A serotinous cone is shut
        # until fire opens it, so an idle pod must not show its cavity — and this
        # plug was a cone narrowing UPWARD, which cannot close a mouth wider than
        # its own top. Seen from above it left a ring of open cavity around itself
        # and every pod wore a black bored-out hole, the one read the sheet keeps
        # for after the burn. It widens upward now, so it caps the mouth like a
        # lid instead of sitting in it like a stopper.
        b.ngon_prism((px, py), 0.040, 0.030, 0.020, "ga_resin", sides=7,
                     z0=GA_POD_TOP - 0.006)
        # AND IT WEEPS. On every view of the sheet the resin does not just cap the
        # cone, it RUNS — gold beads swelling over the lip and down the flank, and
        # that drip is the crown's whole read at a glance. The build sealed each pod
        # with a flat lid and put its only drip at the stalk's wound, so the crown
        # was six tan caps. Two runs per pod, at different lengths so they do not
        # read as a machined pattern, tapering as a drip does.
        for d in range(2):
            da = math.tau * (d * 0.5 + 0.17) + i * 0.9
            run = 0.055 + 0.030 * ((i + d) % 3) / 2.0
            b.limb((px + math.cos(da) * 0.030,
                    py + math.sin(da) * 0.030, GA_POD_TOP - 0.004),
                   (px + math.cos(da) * 0.034,
                    py + math.sin(da) * 0.034, GA_POD_TOP - 0.004 - run),
                   0.013, 0.006, "ga_resin", sides=5)
    # THE CAVITY FLOOR, on its own bone and PARKED OUT OF EXISTENCE.
    #
    # The pod's own walls are pale, so an open mouth does not read as a hole — the
    # black hole down every idle pod was this one near-black plate, sitting in the
    # line of sight through the mouth. Capping the mouth over it does not work
    # either; what the sheet wants is simply for the cavity not to be there yet.
    # It is what the crown bores ONTO, so it arrives when the crown parts and is
    # absent until then, on the same parked-scale grammar the Seefern's eye cards
    # and the Naturalizer's granule windows use.
    for i in range(GA_PODS):
        px, py = _ga_pod_at(i)
        GA_SEAL_START.append(len(b.bm.verts))
        b.disc((px, py, GA_POD_TOP - 0.055), 0.030, "ga_char", sides=7)

    # THE CROWN SCALES, one bone each, leaning together over the mouth.
    for i in range(GA_PODS):
        for k in range(GA_CROWN):
            base, tip = _ga_crown_seat(i, k)
            GA_CROWN_START.append(len(b.bm.verts))
            b.limb(base, tip, 0.019, 0.007, "ga_pod", sides=5)
    # THE BUDS the charred plant comes back with, modelled at full size and parked
    # at nothing so the atlas allots them texels.
    for k in range(GA_BUDS):
        a = math.tau * k / GA_BUDS + 0.2
        r = 0.20 if k % 2 else 0.135
        GA_BUD_START.append(len(b.bm.verts))
        b.limb((math.cos(a) * r, math.sin(a) * r, GA_UMBEL_Z + 0.03),
               (math.cos(a) * (r + 0.03), math.sin(a) * (r + 0.03),
                GA_UMBEL_Z + 0.10), 0.016, 0.004, "ga_bud", sides=5)
    for (wz, count, length) in GA_LEAF_WHORLS:
        for i in range(count):
            a = math.tau * i / count + (0.4 if wz > 0.4 else 0.0)
            # RISING, not lying flat. At 1.16 rad the fronds splay almost
            # horizontally and — once lengthened — read as flat scaffolding combs
            # sticking out of the stalk's foot. The sheet's rosette rises steeply
            # and arcs outward, so the skirt reads as growth rather than as
            # something propped against the plant. The upper whorl stands a little
            # straighter than the lower, which is what gives the rosette its layers.
            tilt = 0.78 if wz > 0.4 else 0.92
            rr = math.sin(tilt) * length * 0.5
            GA_LEAF_START.append(len(b.bm.verts))
            b.card((math.sin(a) * (0.06 + rr), math.cos(a) * (0.06 + rr),
                    wz + math.cos(tilt) * length * 0.5),
                   (length * 0.5, length), "ga_leaf", axis='Y', art=GA_LEAF_ART,
                   rot=(tilt, 0.0, a), segments=GA_LEAF_SEG)
    global GA_RESIN_START
    GA_RESIN_START = len(b.bm.verts)
    b.ngon_prism((0.055, 0.015), 0.02, 0.032, 0.05, "ga_resin", sides=5, z0=0.44)
    GA_FLASH_START = len(b.bm.verts)
    b.card((0, 0, GA_UMBEL_Z + 0.24), (0.62, 0.62), "ga_flash", axis='Z')
    b.card((0, 0, GA_UMBEL_Z + 0.24), (0.62, 0.62), "ga_flash", axis='Y')
    return b.finish("GasafoetidaRigged")


def gasafoetida_chains():
    """The stalk is one chain; every pod gets a bone of its own, because the whole
    point of a serotinous cluster is that the pods go one after another."""
    chains = [{"prefix": "stalk", "points": [(0.0, 0.0, z) for z in GA_STALK_Z]}]
    for i in range(GA_PODS):
        px, py = _ga_pod_at(i)
        chains.append({"prefix": "pod%d" % i, "parent": "stalk_%d" % (GA_STALK_SEG - 1),
                       "points": [(px, py, GA_UMBEL_Z + 0.05),
                                  (px, py, GA_UMBEL_Z + 0.23)]})
    for i in range(GA_PODS):
        px, py = _ga_pod_at(i)
        chains.append({"prefix": "seal%d" % i, "parent": "pod%d_0" % i,
                       "points": [(px, py, GA_POD_TOP - 0.002),
                                  (px, py, GA_POD_TOP + 0.03)]})
    for i in range(GA_PODS):
        for k in range(GA_CROWN):
            base, tip = _ga_crown_seat(i, k)
            chains.append({"prefix": "crown%d_%d" % (i, k), "parent": "pod%d_0" % i,
                           "points": [base, tip]})
    chains.append({"prefix": "bud", "parent": "stalk_%d" % (GA_STALK_SEG - 1),
                   "points": [(0.0, 0.0, GA_UMBEL_Z + 0.03),
                              (0.0, 0.0, GA_UMBEL_Z + 0.12)]})
    li = 0
    for (wz, count, length) in GA_LEAF_WHORLS:
        for i in range(count):
            a = math.tau * i / count + (0.4 if wz > 0.4 else 0.0)
            tilt = 1.16
            pts = []
            for sgi in range(GA_LEAF_SEG + 1):
                f = sgi / float(GA_LEAF_SEG)
                r = 0.06 + math.sin(tilt) * length * f
                pts.append((math.sin(a) * r, math.cos(a) * r,
                            wz + math.cos(tilt) * length * f))
            chains.append({"prefix": "gleaf%d" % li, "points": pts})
            li += 1
    chains.append({"prefix": "gaflash", "parent": "stalk_%d" % (GA_STALK_SEG - 1),
                   "points": [(0.0, 0.0, GA_UMBEL_Z + 0.2), (0.0, 0.0, GA_UMBEL_Z + 0.3)]})
    return chains


ga_piece = build_gasafoetida_rigged()
pl.texture_object(ga_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
ga_arm = rig.build_armature("Gasafoetida", gasafoetida_chains())
rig.bind(ga_piece, ga_arm, kind='ARMATURE_NAME')
# the stalk's rings and the umbel and its char ride the stalk chain
for i, start in enumerate(GA_STALK_START):
    end = GA_STALK_START[i + 1] if i + 1 < len(GA_STALK_START) else GA_POD_START[0]
    rig.assign_exclusive_weights(ga_piece, "stalk_%d" % i, range(start, end))
for i, start in enumerate(GA_POD_START):
    end = GA_POD_START[i + 1] if i + 1 < len(GA_POD_START) else GA_SEAL_START[0]
    rig.assign_exclusive_weights(ga_piece, "pod%d_0" % i, range(start, end))
for i, start in enumerate(GA_SEAL_START):
    end = GA_SEAL_START[i + 1] if i + 1 < len(GA_SEAL_START) else GA_CROWN_START[0]
    rig.assign_exclusive_weights(ga_piece, "seal%d_0" % i, range(start, end))
for j, start in enumerate(GA_CROWN_START):
    end = GA_CROWN_START[j + 1] if j + 1 < len(GA_CROWN_START) else GA_BUD_START[0]
    rig.assign_exclusive_weights(ga_piece, "crown%d_%d_0" % (j // GA_CROWN, j % GA_CROWN),
                                 range(start, end))
rig.assign_exclusive_weights(ga_piece, "bud_0", range(GA_BUD_START[0], GA_LEAF_START[0]))
for i, start in enumerate(GA_LEAF_START):
    rig.weight_chain_strip(ga_piece, "gleaf%d" % i,
                           rig.card_rows(start, GA_LEAF_SEG))
# the resin weeping at the wound-point rides the stalk segment it sits on
rig.assign_exclusive_weights(ga_piece, "stalk_1", range(GA_RESIN_START, GA_FLASH_START))
rig.assign_exclusive_weights(ga_piece, "gaflash_0",
                             range(GA_FLASH_START, len(ga_piece.data.vertices)))

GA_SHUT, GA_OPEN = 0.001, 1.0
GA_GONE = 0.001
# BREATHE: the idle. The cluster swells and settles in a slow wave around the
# umbel, which is the "breathing motion visible at close range" — the one thing a
# player can read off this plant without touching it.
GA_CROWN_KEYS = ["crown%d_%d_0" % (i, k) for i in range(GA_PODS) for k in range(GA_CROWN)]
# the cavity is ABSENT until something bores the pod open
GA_SEALED, GA_BORED = 0.001, 1.0
ga_rest = {"bud_0": 0.001}
ga_swell = {"bud_0": 0.001}
for i in range(GA_PODS):
    ga_rest["pod%d_0" % i] = 1.0
    ga_swell["pod%d_0" % i] = 1.0 + (0.09 if i % 2 == 0 else 0.05)
    # no cavity while the cone is shut, which is what serotinous means
    ga_rest["seal%d_0" % i] = GA_SEALED
    ga_swell["seal%d_0" % i] = GA_SEALED
for _key in GA_CROWN_KEYS:
    ga_rest[_key] = (0.0, 0.0, 0.0)
    ga_swell[_key] = (0.0, 0.0, 0.0)


def _ga_crown(amount):
    """Every scale swung outward by its own share, so the mouth opens like a
    calyx rather than a hatch."""
    out = {}
    for j, key in enumerate(GA_CROWN_KEYS):
        out[key] = (amount * (0.82 + 0.18 * ((j * 5) % 3) / 2.0), 0.0,
                    amount * 0.12 * (1 if j % 2 else -1))
    return out
def _ga_bored():
    """The cavity the crown has bored ONTO, now that there is one."""
    return dict(("seal%d_0" % i, GA_BORED) for i in range(GA_PODS))


rig.clip(ga_arm, "gasafoetida_breathe", [
    (0.0, dict(ga_rest, gaflash_0=GA_SHUT)),
    (1.9, dict(ga_swell, gaflash_0=GA_SHUT)),
    (3.8, dict(ga_rest, gaflash_0=GA_SHUT)),
])
# TEND: the cluster works up a pod and offers it, and the flare says it took.
rig.clip(ga_arm, "gasafoetida_tend", [
    (0.0, dict(ga_rest, gaflash_0=GA_SHUT)),
    (1.8, dict(ga_swell, gaflash_0=GA_SHUT)),
    (2.15, dict(ga_swell, gaflash_0=GA_OPEN)),
    (2.5, dict(ga_rest, gaflash_0=GA_SHUT)),
])
# OPEN: the crown bores apart into a resin-lipped cup. This is the sheet's central
# pod study and the affordance a player acts on — the pod has to be visibly OPEN
# before anything can be taken out of it, and a cluster that jumps from sealed to
# empty never shows the moment it was offering something.
rig.clip(ga_arm, "gasafoetida_open", [
    (0.0, dict(ga_rest, gaflash_0=GA_SHUT)),
    (0.6, dict(ga_rest, gaflash_0=GA_SHUT, **_ga_crown(0.45))),
    # the cavity appears once the crown has parted far enough to have bored in
    (0.9, dict(ga_rest, gaflash_0=GA_SHUT, **dict(_ga_crown(0.78), **_ga_bored()))),
    (1.3, dict(ga_rest, gaflash_0=GA_SHUT, **dict(_ga_crown(1.05), **_ga_bored()))),
])
# RECOVER: the charred crown puts out green buds on the plate rim and up the
# stalk. The roster's whole point about this plant is that fire is not the end of
# it, and a burnt cluster with nothing coming back says the opposite.
# A burnt cluster's pods are scaled away entirely, so its cavities are moot — and
# saying they are BORED here breaks the chain: combust ends with them absent and
# recover would open with them present, which is a clip starting from a pose the
# plant was never in.
ga_burnt = dict(ga_rest, **_ga_crown(1.05))
for _i in range(GA_PODS):
    ga_burnt["pod%d_0" % _i] = GA_GONE
rig.clip(ga_arm, "gasafoetida_recover", [
    (0.0, dict(ga_burnt, gaflash_0=GA_SHUT, bud_0=0.001)),
    (1.6, dict(ga_burnt, gaflash_0=GA_SHUT, bud_0=0.45)),
    (3.2, dict(ga_burnt, gaflash_0=GA_SHUT, bud_0=1.0)),
])
# HARVEST: one pod leaves with whoever picked it, and the char under it shows.
# It opens on the OPEN pose, because a pod is taken out of a cup that is already
# standing open — the crown does not part and the pod vanish in the same beat.
rig.clip(ga_arm, "gasafoetida_harvest", [
    (0.0, dict(ga_rest, gaflash_0=GA_SHUT, **_ga_crown(1.05))),
    (0.55, dict(ga_rest, pod0_0=GA_GONE, gaflash_0=GA_SHUT, **_ga_crown(1.05))),
])
# COMBUST: serotinous. The pods go one after another rather than together — the
# spec says "ejecting flaming projectiles IN SEQUENCE", and a cluster that emptied
# in a single frame would be one bang instead of the popcorn Peris names it for.
ga_burn = [(0.0, dict(ga_rest, gaflash_0=GA_SHUT))]
gone = dict(ga_rest)
for i in range(GA_PODS):
    t = 0.35 + 0.28 * i
    gone = dict(gone)
    gone["pod%d_0" % i] = 1.22                     # the resin seal bulges first
    ga_burn.append((t, dict(gone, gaflash_0=GA_SHUT)))
    gone = dict(gone)
    gone["pod%d_0" % i] = GA_GONE                  # then it goes
    ga_burn.append((t + 0.14, dict(gone, gaflash_0=GA_SHUT)))
rig.clip(ga_arm, "gasafoetida_combust", ga_burn)
# A cluster nobody has touched stands full, pods sealed, flare shut.
rig.park(ga_arm, dict(ga_rest, gaflash_0=GA_SHUT))

# The STALK likewise: 3 bones over GA_STALK_SEG, at budget and now checked.
ga_report = rig.validate(ga_piece, ga_arm,
                         dict([("gleaf%d" % i, 2) for i in range(len(GA_LEAF_START))]
                              + [("stalk", GA_STALK_SEG)]))
print("[RIG] Gasafoetida %s bones=%d dead=%s orphans=%d"
      % (ga_report["verdict"], ga_report["bones"],
         ga_report["dead_bones"] or "none", ga_report["orphan_verts"]))
if ga_report["verdict"] != "PASS":
    raise SystemExit("gasafoetida rig does not deform: %s" % ga_report["problems"])


# ============================================================================
# GAS POD — what a tended Gasafoetida hands you. The taxonomy makes it a real
# object with a life of its own: "tend produces a held pod that emits repellent
# gas; while emitting, all enemies in proximity are repelled until the gas runs
# out", and the game already speaks of a Gasafoetida pod as a held item with its
# own properties.
#
# Cards ENT-019_held_pod and _spent_pod are the two ends: a pale ovoid whose
# resin nozzle is bright amber and puffing while it works, and the same pod with
# that nozzle burnt dark and nothing coming out. So the amber seal is a cap that
# goes, revealing the char modelled underneath it — the same reveal the cluster's
# pods use — and the gas is drawn puffs that rise while it emits.
# ============================================================================

GP_PUFFS = 3
GP_RINGS = 6
GP_LEN = 0.135


def _gp_radius(z):
    """The pod's half-width at height z: an ellipse, so both ends close."""
    t = min(1.0, max(0.0, z / GP_LEN)) * 2.0 - 1.0
    return 0.008 + 0.048 * math.sqrt(max(0.0, 1.0 - t * t))


def _gp_tip(p):
    """A point taken through the same rotation the body gets."""
    v = mathutils.Vector(p)
    v.rotate(mathutils.Matrix.Rotation(math.pi * 0.5, 3, 'Y'))
    return (v.x, v.y, v.z)


GP_BODY_START = 0
GP_CAP_START = 0
GP_PUFF_START = []


def _gaspod_puff_art(tile, isl, px_per_m):
    """A puff of the repellent: a soft blob with a ragged edge, thinning outward.
    Gas is repetition and motion, so it is drawn — a modelled cloud is triangles
    spent on something that should read as barely-there."""
    ph, pw = tile.shape[:2]
    pale = _dim(CS("gasafoetida_pod"), 1.25)
    mid_c = _dim(CS("gasafoetida_pod"), 0.95)
    thin = _dim(CS("gasafoetida_pod"), 0.7)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
            edge = 0.62 + 0.3 * ((h % 100) / 100.0)
            if r > edge:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = pale if r < 0.3 else (mid_c if r < 0.5 else thin)


GP_PUFF_ART = pl.register_card_art("rigged_gaspod_puff", _gaspod_puff_art)

pl.register_parts({
    "gp_body": {"rgb": _dim(CS("gasafoetida_pod"), 1.12)},
    "gp_seal": {"rgb": _dim(CS("flure_core"), 0.9), "emit": CS("flure_core")},
    "gp_char": {"rgb": _dim(CS("gasafoetida_stalk"), 0.22)},
    "gp_gas":  {"rgb": _dim(CS("gasafoetida_pod"), 1.2)},
}, emit_strength={"gp_seal": 1.5})


def build_gaspod_rigged():
    """A fist-sized ovoid lying on its side, its resin nozzle at one end over the
    char the nozzle burns down to, and the gas it vents."""
    b = Builder()
    global GP_BODY_START, GP_CAP_START
    GP_BODY_START = len(b.bm.verts)
    # Stacked rings whose radii follow an ellipse, so the profile closes at both
    # ends into an ovoid. `ngon_prism` takes r_top BEFORE r_bot: giving a bottom
    # cone the wide radius on top pinches the waist into an undercut and leaves
    # the barrel's own cap standing proud of it.
    for i in range(GP_RINGS):
        z0 = GP_LEN * i / float(GP_RINGS)
        z1 = GP_LEN * (i + 1) / float(GP_RINGS)
        b.ngon_prism((0, 0), _gp_radius(z1), _gp_radius(z0), z1 - z0, "gp_body",
                     sides=10, z0=z0, cap_top=(i == GP_RINGS - 1), cap_bottom=(i == 0))
    # the char the nozzle leaves behind, modelled under the seal that hides it
    b.ngon_prism((0, 0), 0.016, 0.024, 0.022, "gp_char", sides=6, z0=GP_LEN - 0.004)
    GP_CAP_START = len(b.bm.verts)
    b.ngon_prism((0, 0), 0.015, 0.026, 0.03, "gp_seal", sides=6, z0=GP_LEN - 0.004)
    for i in range(GP_PUFFS):
        GP_PUFF_START.append(len(b.bm.verts))
        b.card((0.0, 0.0, GP_LEN + 0.06 + 0.07 * i),
               (0.075 + 0.022 * i, 0.075 + 0.022 * i), "gp_gas", axis='Y',
               art=GP_PUFF_ART)
    # Card ENT-019_held_pod draws the pod LYING DOWN. It is authored along Z
    # because that is the axis a prism stack grows on, then tipped so its long
    # axis is horizontal; the bones are tipped by the same matrix.
    _bmesh.ops.rotate(b.bm, verts=b.bm.verts[:], cent=(0.0, 0.0, 0.0),
                      matrix=mathutils.Matrix.Rotation(math.pi * 0.5, 3, 'Y'))
    return b.finish("GasPodRigged")


def gaspod_chains():
    """The pod is held, so its BODY never deforms — only the seal that burns away
    and the puffs that rise get bones."""
    chains = [{"prefix": "pod",
               "points": [_gp_tip((0.0, 0.0, 0.0)), _gp_tip((0.0, 0.0, GP_LEN))]}]
    chains.append({"prefix": "seal", "parent": "pod_0",
                   "points": [_gp_tip((0.0, 0.0, GP_LEN - 0.004)),
                              _gp_tip((0.0, 0.0, GP_LEN + 0.03))]})
    for i in range(GP_PUFFS):
        z = GP_LEN + 0.06 + 0.07 * i
        chains.append({"prefix": "puff%d" % i, "parent": "pod_0",
                       "points": [_gp_tip((0.0, 0.0, z)),
                                  _gp_tip((0.0, 0.0, z + 0.06))]})
    return chains


gp_piece = build_gaspod_rigged()
pl.texture_object(gp_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
gp_arm = rig.build_armature("GasPod", gaspod_chains())
rig.bind(gp_piece, gp_arm, kind='ARMATURE_NAME')
rig.assign_exclusive_weights(gp_piece, "pod_0", range(GP_BODY_START, GP_CAP_START))
rig.assign_exclusive_weights(gp_piece, "seal_0", range(GP_CAP_START, GP_PUFF_START[0]))
for i, start in enumerate(GP_PUFF_START):
    end = GP_PUFF_START[i + 1] if i + 1 < len(GP_PUFF_START) else len(gp_piece.data.vertices)
    rig.assign_exclusive_weights(gp_piece, "puff%d_0" % i, range(start, end))

GP_SHUT = 0.001
gp_quiet = {"seal_0": 1.0}
for i in range(GP_PUFFS):
    gp_quiet["puff%d_0" % i] = GP_SHUT
# EMIT: the pod works. Puffs swell in turn and let go, so the venting reads as a
# rhythm rather than a cloud that is simply switched on.
gp_emit = [(0.0, dict(gp_quiet))]
for i in range(GP_PUFFS):
    t = 0.3 + 0.45 * i
    gp_emit.append((t, dict(gp_quiet, **{"puff%d_0" % i: 1.0})))
    gp_emit.append((t + 0.4, dict(gp_quiet, **{"puff%d_0" % i: GP_SHUT})))
gp_emit.append((0.3 + 0.45 * GP_PUFFS + 0.2, dict(gp_quiet)))
rig.clip(gp_arm, "gaspod_emit", gp_emit)
# SPEND: the gas runs out and the resin seal burns down to the char under it.
rig.clip(gp_arm, "gaspod_spend", [
    (0.0, dict(gp_quiet)),
    (0.5, dict(gp_quiet, seal_0=0.55)),
    (1.1, dict(gp_quiet, seal_0=GP_SHUT)),
])
# A pod nobody has used is sealed and quiet.
rig.park(gp_arm, dict(gp_quiet))

gp_report = rig.validate(gp_piece, gp_arm)
print("[RIG] GasPod %s bones=%d dead=%s orphans=%d"
      % (gp_report["verdict"], gp_report["bones"],
         gp_report["dead_bones"] or "none", gp_report["orphan_verts"]))
if gp_report["verdict"] != "PASS":
    raise SystemExit("gaspod rig does not deform: %s" % gp_report["problems"])


# ============================================================================
# CLIMBVINE CUTTING — the section a tended vine gives up, and the third held tool
# the taxonomy names beside the Gasafoetida pod: "held tools (Climbvine sections,
# Gasafoetida pods, Hushbloom samples) cache as inventory expansion". The library
# has the growing plant and never had the cutting.
#
# Cards ENT-020_harvested and _deployed are the same object doing the only thing
# it does: carried it lies in a lazy curve, slung between two anchors it SAGS into
# a catenary. So the rope is a chain of rings and the sag is a clip — and because
# a vine's body is what holds its form, the body stays a mesh; only what repeats
# along it would ever be drawn.
# ============================================================================

VC_SEGS = 8               # rings along the rope; bones = VC_SEGS - 1
VC_LEN = 1.25
VC_R = 0.042
VC_NODES = (1, 3, 5, 7)   # which rings swell into a node
VC_START = []
VC_SPUR_START = 0


def _vc_ring_z(i):
    return VC_LEN * i / float(VC_SEGS - 1)


def _vc_radius(i):
    """A node swells; the internode between two of them is the thinner rope."""
    return VC_R * (1.5 if i in VC_NODES else 1.0)


pl.register_parts({
    "vc_bark":  {"rgb": _dim(CS("resolution_root_pale"), 1.06)},
    "vc_node":  {"rgb": CS("resolution_root_pale")},
    "vc_spur":  {"rgb": _dim(CS("resolution_root_pale"), 0.82)},
    "vc_cut":   {"rgb": _dim(CS("resolution_root_pale"), 0.72)},
})


def build_vinecut_rigged():
    """A cut length of rope-vine: rings along its length so it can bend, swollen
    at its nodes, spurred where the radicles grip, and cleanly cut at one end."""
    b = Builder()
    global VC_SPUR_START
    for i in range(VC_SEGS - 1):
        VC_START.append(len(b.bm.verts))
        z0, z1 = _vc_ring_z(i), _vc_ring_z(i + 1)
        b.ngon_prism((0, 0), _vc_radius(i + 1), _vc_radius(i), z1 - z0,
                     "vc_node" if (i in VC_NODES or i + 1 in VC_NODES) else "vc_bark",
                     sides=8, z0=z0, cap_top=False, cap_bottom=(i == 0))
    # the cut face: the tell that says this length was TAKEN, not grown to an end
    b.ngon_prism((0, 0), _vc_radius(VC_SEGS - 1) * 0.98, _vc_radius(VC_SEGS - 1),
                 0.012, "vc_cut", sides=8, z0=VC_LEN)
    VC_SPUR_START = len(b.bm.verts)
    for i in VC_NODES:                        # the radicles that gripped the slope
        for k in range(3):
            a = k * math.tau / 3.0 + i * 0.7
            r = _vc_radius(i)
            b.box((math.sin(a) * r * 0.9, math.cos(a) * r * 0.9, _vc_ring_z(i)),
                  (0.016, 0.016, 0.03), "vc_spur")
    # Card ENT-020_harvested lays the cutting DOWN. It is authored along Z because
    # that is the axis a ring stack grows on, then tipped so it lies along X; the
    # bones take the same matrix.
    _bmesh.ops.rotate(b.bm, verts=b.bm.verts[:], cent=(0.0, 0.0, 0.0),
                      matrix=mathutils.Matrix.Rotation(math.pi * 0.5, 3, 'Y'))
    return b.finish("VineCutRigged")


def vinecut_chains():
    """ONE chain down the rope, a point per ring, so the sag travels its length
    instead of hinging at a joint."""
    return [{"prefix": "vine",
             "points": [_gp_tip((0.0, 0.0, _vc_ring_z(i))) for i in range(VC_SEGS)]}]


vc_piece = build_vinecut_rigged()
pl.texture_object(vc_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
vc_arm = rig.build_armature("VineCut", vinecut_chains())
rig.bind(vc_piece, vc_arm, kind='ARMATURE_NAME')
for i, start in enumerate(VC_START):
    end = VC_START[i + 1] if i + 1 < len(VC_START) else VC_SPUR_START
    rig.assign_exclusive_weights(vc_piece, "vine_%d" % i, range(start, end))
# every spur rides the ring it grew from
_spur_verts = list(range(VC_SPUR_START, len(vc_piece.data.vertices)))
_per_spur = max(1, len(_spur_verts) // (len(VC_NODES) * 3))
for ni, node in enumerate(VC_NODES):
    bone = "vine_%d" % min(node, VC_SEGS - 2)
    lo = VC_SPUR_START + ni * 3 * _per_spur
    hi = lo + 3 * _per_spur
    rig.assign_exclusive_weights(vc_piece, bone, range(lo, min(hi, len(vc_piece.data.vertices))))

# CARRIED is how the cutting rests: a lazy curve, the shape a coil of rope keeps.
# A cut length of rope does not lie straight. The curve is PARKED, so it is what
# the piece rests in, and both clips open on the same pose — a clip that started
# straight would snap the cutting flat on its first frame.
vc_carry = {}
for i in range(VC_SEGS - 1):
    vc_carry["vine_%d" % i] = (0.0, 0.0, 0.22 if i % 2 == 0 else -0.16)
# SLUNG: tied between two anchors it hangs in a catenary — the near half turns
# down hard and the far half comes back up, which is the shape card ENT-020
# _deployed draws between its two blocks.
vc_sag = {}
for i in range(VC_SEGS - 1):
    t = i / float(VC_SEGS - 2)
    vc_sag["vine_%d" % i] = (0.55 - 1.1 * t, 0.0, 0.04)
rig.clip(vc_arm, "vinecut_sling", [(0.0, dict(vc_carry)), (1.1, dict(vc_sag))])
rig.clip(vc_arm, "vinecut_gather", [(0.0, dict(vc_sag)), (0.9, dict(vc_carry))])
rig.park(vc_arm, dict(vc_carry))

vc_report = rig.validate(vc_piece, vc_arm, {"vine": VC_SEGS - 1})
print("[RIG] VineCut %s bones=%d dead=%s orphans=%d"
      % (vc_report["verdict"], vc_report["bones"],
         vc_report["dead_bones"] or "none", vc_report["orphan_verts"]))
if vc_report["verdict"] != "PASS":
    raise SystemExit("vinecut rig does not deform: %s" % vc_report["problems"])


# ============================================================================
# HUSHBLOOM SAMPLE — the last of the three held tools the taxonomy names, and the
# one with no card of its own, so its form is taken entirely from the plant it is
# cut from rather than invented: one rachis of the comb leaf, its paired leaflets
# and the swollen pulvini that do the folding, cut clean at the base.
#
# It behaves the way the plant does. "Hushbloom samples triggered by movement
# during character entry would stun whichever character entered" — so a sample
# that is jostled folds and fires, the same wave along the rachis the growing
# plant uses, and afterwards its leaflets sit open and spent.
# ============================================================================

HS_SEGMENTS = 4
HS_LEN = 0.34
HS_START = 0
HS_STEM_START = 0
HS_FLASH_START = 0

pl.register_parts({
    "hs_cut": {"rgb": _dim(CS("hushbloom_stem"), 0.5)},
    "hs_burst": {"rgb": CS("hushbloom_bloom"), "emit": CS("hushbloom_bloom")},
}, emit_strength={"hs_burst": 3.6})


def build_sample_rigged():
    """One cut rachis: the same drawn comb the plant wears, on a short stub that
    reads as taken, with the release it lets go of."""
    b = Builder()
    global HS_START, HS_STEM_START, HS_FLASH_START
    HS_STEM_START = len(b.bm.verts)
    b.ngon_prism((0, 0), 0.009, 0.014, 0.05, "hs_cut", sides=6, z0=0.0)
    HS_START = len(b.bm.verts)
    b.card((0, 0, 0.05 + HS_LEN * 0.5), (HS_LEN * 0.46, HS_LEN), "rh_leaf",
           axis='Y', art=HUSH_LEAF, segments=HS_SEGMENTS)
    HS_FLASH_START = len(b.bm.verts)
    b.card((0, 0, 0.05 + HS_LEN * 0.45), (0.3, 0.3), "hs_burst", axis='Z')
    b.card((0, 0, 0.05 + HS_LEN * 0.45), (0.3, 0.3), "hs_burst", axis='Y')
    # a sample lies down in a hand or a cache, like the pod and the cutting
    _bmesh.ops.rotate(b.bm, verts=b.bm.verts[:], cent=(0.0, 0.0, 0.0),
                      matrix=mathutils.Matrix.Rotation(math.pi * 0.5, 3, 'Y'))
    return b.finish("SampleRigged")


def sample_chains():
    """A chain up the rachis so the fold travels it, and the release on its own."""
    pts = []
    for i in range(HS_SEGMENTS + 1):
        pts.append(_gp_tip((0.0, 0.0, 0.05 + HS_LEN * i / float(HS_SEGMENTS))))
    chains = [{"prefix": "rachis", "points": pts}]
    chains.append({"prefix": "hsflash", "parent": "rachis_0",
                   "points": [_gp_tip((0.0, 0.0, 0.05 + HS_LEN * 0.45)),
                              _gp_tip((0.0, 0.0, 0.05 + HS_LEN * 0.45 + 0.08))]})
    return chains


hs_piece = build_sample_rigged()
pl.texture_object(hs_piece, OBJX, px_per_m=48.0, painted_dir=PAINTED)
hs_arm = rig.build_armature("Sample", sample_chains())
rig.bind(hs_piece, hs_arm, kind='ARMATURE_NAME')
rig.weight_chain_strip(hs_piece, "rachis", rig.card_rows(HS_START, HS_SEGMENTS))
rig.assign_exclusive_weights(hs_piece, "rachis_0", range(HS_STEM_START, HS_START))
rig.assign_exclusive_weights(hs_piece, "hsflash_0",
                             range(HS_FLASH_START, len(hs_piece.data.vertices)))

HS_SHUT, HS_OPEN = 0.001, 1.0
# FIRE: jostled, the sample folds along its rachis and lets the burst go — the
# same wave the growing plant uses, because it is the same leaf.
hs_fold = rig.chain_wave("rachis", HS_SEGMENTS, 0.62, lead=0.35)
rig.clip(hs_arm, "sample_fire", [
    (0.0, {"hsflash_0": HS_SHUT}),
    (0.28, dict(hs_fold, hsflash_0=HS_SHUT)),
    (0.36, dict(hs_fold, hsflash_0=HS_OPEN)),
    (0.7, dict(hs_fold, hsflash_0=HS_SHUT)),
])
# SPENT: the leaflets settle back open with nothing left to give.
rig.clip(hs_arm, "sample_spent", [
    (0.0, dict(hs_fold, hsflash_0=HS_SHUT)),
    (1.4, {"hsflash_0": HS_SHUT}),
])
# A sample nobody has jostled is charged: leaflets open, nothing let go.
rig.park(hs_arm, {"hsflash_0": HS_SHUT})

hs_report = rig.validate(hs_piece, hs_arm, {"rachis": HS_SEGMENTS})
print("[RIG] Sample %s bones=%d dead=%s orphans=%d"
      % (hs_report["verdict"], hs_report["bones"],
         hs_report["dead_bones"] or "none", hs_report["orphan_verts"]))
if hs_report["verdict"] != "PASS":
    raise SystemExit("sample rig does not deform: %s" % hs_report["problems"])

# ============================================================================
# CLIMBVINE - the seventh tendable species, and the one the roster describes by
# what it GRIPS: "the adventitious-root clusters at each node are the affordance
# signal - small dense bundles of dark hair-like rootlets, splayed outward to
# brace against the substrate. Players read the rootlets as 'this vine grips'".
# The rootlets are therefore the piece; the rope is only what they hold on to.
#
# A dense bundle of hair-like rootlets is exactly the case the alpha-card law was
# written for. Modelled, the hairs alias into mush at the distance the player has
# to read a slope from; drawn, the bundle stays crisp. So the rootlets are cards
# and the fibre striation running along the rope is a drawn surface, while the
# rope itself stays a mesh, because a vine's body is what holds its form.
#
# It is authored running UP a substrate standing behind it at -Y. A Climbvine
# only ever grows on an incline, so the plant's own frame is the slope it grips,
# and a level turns the whole plant onto whatever gradient it has.
#
# Rest is the UNTENDED plant: a level places a vine that has held its slope for
# years, and the readied section is the state the player produces by tending.
# ============================================================================

CV_RINGS = 10
CV_LEN = 3.0
CV_R = 0.05
# A NODE IS A SWELLING BETWEEN SMOOTH RUNS, so it only exists if some rings are
# NOT one. Flagging every interior ring gave all eight the same 1.42 multiplier,
# which is not a knuckled rope — it is a uniformly fatter smooth one, and the
# swollen node carrying its rootlet whorl is this species' whole identity. Widely
# spaced, as the brief says, with internodes between them for the eye to measure
# the swelling against.
# SIX, not three. The flush has to travel ALONG the vine — the tended read is
# leaf arriving in sequence rather than switching on everywhere — so there have to
# be enough whorls in a row to show a sequence at all. Three could not, and the
# guard that counts them is the thing that said so. They sit in pairs with a bare
# ring between each pair, which keeps the internodes the swelling is measured
# against while giving the flush somewhere to travel.
CV_NODES = (1, 2, 4, 5, 7, 8)
# LONG ENOUGH AND MANY ENOUGH TO BE THE SILHOUETTE. Rendered against the sheet the
# vine read as a bare peeled stick with a few dark specks where the whorls should
# be — and the specks were the rootlets, built at 0.12 against a stalk of radius
# 0.05. A rootlet barely longer than the stalk is thick cannot carry a spray. On
# the turnaround each node throws five to eight curling rootlets reaching several
# times the node's own diameter, and that spray IS what the eye reads as "this
# vine grips"; the rope is only what they hold on to. Three stubs could never say
# it however correct the node spacing was.
CV_ROOT_LEN = 0.34
CV_ROOT_W = 0.14
# AROUND the stalk, not fanned across one side of it. A 97-degree arc put every
# rootlet on the same flank and the whorl read as a comb rather than a collar; on
# the turnaround they radiate both ways around the node. The arc is still centred
# on the substrate side — the vine is authored gripping something behind it — but
# it now wraps far enough that the near and far rootlets read as one ring.
CV_ROOT_ANGLES = tuple(math.pi * 0.5 - 2.10 + i * (4.20 / 6.0) for i in range(7))
CV_LEAVES_PER = 3
CV_LEAF_LEN = 0.19
CV_LEAF_W = 0.13
CV_START = []
CV_ROOT_START = []
CV_LEAF_START = []
CV_FLASH_START = 0


def _cv_z(i):
    return CV_LEN * i / float(CV_RINGS - 1)


def _cv_x(i):
    """A grown vine wanders. The meander is small enough to keep the rope reading
    as one run and large enough that it never reads as extruded pipe."""
    return math.sin(i * 0.9) * 0.07


def _cv_radius(i):
    """Thick at the old base, thinner toward the fresh end, swollen at a node."""
    taper = 1.0 - 0.3 * (i / float(CV_RINGS - 1))
    return CV_R * taper * (1.42 if i in CV_NODES else 1.0)


def _cv_node_center(node):
    return (_cv_x(node), 0.0, _cv_z(node))


def _cv_leaf_art(tile, isl, px_per_m):
    """One leaf of a tended vine's flush: a pointed oval with a midrib, drawn at
    the scale the rest of the world is drawn at, so a vine that has been worked
    reads green from across a corridor and reads as leaves up close."""
    ph, pw = tile.shape[:2]
    leaf = CS("climbvine_leaf")
    leaf_d = _dim(CS("climbvine_leaf"), 0.72)
    leaf_l = _dim(CS("climbvine_leaf"), 1.22)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)
        # widest a third along, drawn to a point at the tip and a stalk at the base
        half = cx * math.sin(math.pi * min(1.0, t ** 0.7)) * 0.98
        if t < 0.14:
            half = min(half, cx * 0.2)
        for x in range(pw):
            d = abs(x - cx)
            if d > max(0.5, half):
                continue
            tile[row, x, 3] = 1.0
            if d < 0.9 and t > 0.12:
                tile[row, x, :3] = leaf_l          # the midrib catching light
            else:
                tile[row, x, :3] = leaf if ((x + row) % 5) else leaf_d


def _cv_rootlet_art(tile, isl, px_per_m):
    """A bundle of hair-like rootlets fanning out of the node at the card's base.

    Hair reads by its GAPS. Pack the strands and the run-fill that keeps each one
    connected merges them into a solid chip, which is a plastic bracket rather
    than a root bundle — so the bundle is deliberately sparse, matted only at the
    crown it grew out of, and ragged at the ends because a root stops where it
    stopped growing."""
    ph, pw = tile.shape[:2]
    dark = CS("climbvine_node")
    mid = _dim(CS("climbvine_node"), 1.9)
    pale = _dim(CS("climbvine_fiber"), 0.6)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    hairs = max(4, pw // 3)
    for k in range(hairs):
        lean = ((k + 0.5) / hairs - 0.5) * 2.0
        h = ((k * 26699) ^ ((k + 3) * 92083)) & 0xFFFFFF
        reach = int((0.55 + 0.45 * ((h % 100) / 100.0)) * (ph - 1)) + 1
        prev = int(round(cx))
        for row in range(reach):
            t = row / max(1.0, ph - 1.0)
            xi = int(round(cx + lean * (0.1 + 0.9 * t) * cx * 0.95))
            t_col = dark if t < 0.22 else (mid if t < 0.7 else pale)
            lo, hi = (prev, xi) if prev <= xi else (xi, prev)
            for x in range(lo, hi + 1):
                if 0 <= x < pw:
                    tile[row, x, 3] = 1.0
                    tile[row, x, :3] = t_col
            prev = xi
    # the matted crown the whole bundle leaves the stem from, so the tuft has
    # somewhere to have grown out of
    crown = max(1, int(ph * 0.1))
    for row in range(crown):
        for x in range(pw):
            if abs(x - cx) <= cx * (0.62 - 0.42 * (row / float(crown))):
                tile[row, x, 3] = 1.0
                tile[row, x, :3] = dark


def _cv_flash_art(tile, isl, px_per_m):
    """The completion flare over the worked node, drawn so it has no edge: the
    alpha is gone well before the card is, and the bright core throws pixel-art
    spokes rather than a smooth engine gradient."""
    ph, pw = tile.shape[:2]
    core = _dim(CS("climbvine_fiber"), 1.3)
    warm = CS("climbvine_fiber")
    emit = isl.get("emit") if isinstance(isl, dict) else None
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            spoke = abs(math.cos(math.atan2(dy, dx) * 3.0)) ** 6
            reach = 0.3 + 0.62 * spoke
            if r > reach:
                tile[y, x, 3] = 0.0
                continue
            k = round(((1.0 - r / reach) ** 2) * 5.0) / 5.0
            if k <= 0.0:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = [core[i] * k + warm[i] * (1.0 - k) for i in range(3)]
            if emit is not None:
                emit[y, x] = [core[i] * k for i in range(3)]


def _cv_bark_detail(tile, mask, base, isl, px_per_m):
    """The fibrous rope texture: long parallel fibres running the length of the
    internode, which is the second half of the affordance - a surface drawn as
    cordage says climbable before any rootlet is close enough to read."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    lit = _dim(base, 1.22)
    dim = _dim(base, 0.74)
    for x in range(pw):
        h = ((x * 73856093) ^ 0x9E3779B9) & 0xFFFF
        if h % 3 == 0:
            continue
        shade_col = lit if h % 3 == 1 else dim
        run = 2 + (h % 5)
        for y in range(ph):
            if ((y // run) + (h >> 4)) % 3 == 0:
                continue
            tile[y, x] = shade_col


CV_ROOT_ART = pl.register_card_art("rigged_climbvine_rootlets", _cv_rootlet_art)
CV_LEAF_ART = pl.register_card_art("rigged_climbvine_leaf", _cv_leaf_art)
CV_FLASH_ART = pl.register_card_art("rigged_climbvine_flash", _cv_flash_art)
CV_BARK = pl.register_detail("climbvine_bark", _cv_bark_detail)

pl.register_parts({
    "cv_bark":  {"rgb": CS("climbvine_fiber")},
    "cv_node":  {"rgb": CS("climbvine_node")},
    "cv_fresh": {"rgb": CS("climbvine_fiber")},
    "cv_root":  {"rgb": CS("climbvine_node")},
    "cv_leaf":  {"rgb": CS("climbvine_leaf")},
    "cv_flare": {"rgb": CS("climbvine_fiber"), "emit": CS("climbvine_fiber")},
}, emit_strength={"cv_flare": 3.4})


def build_climbvine_rigged():
    """A rope of internodes running up its slope, swollen where the nodes grip,
    each node wearing a drawn bundle of rootlets, and the flare that says a
    tending finished."""
    b = Builder()
    global CV_FLASH_START
    for i in range(CV_RINGS - 1):
        CV_START.append(len(b.bm.verts))
        z0, z1 = _cv_z(i), _cv_z(i + 1)
        fresh = i >= CV_RINGS - 2
        b.limb((_cv_x(i), 0.0, z0), (_cv_x(i + 1), 0.0, z1),
               _cv_radius(i), _cv_radius(i + 1),
               "cv_fresh" if fresh else "cv_bark", sides=8, detail=CV_BARK,
               cap_start=(i == 0), cap_end=(i == CV_RINGS - 2))
    for node in CV_NODES:
        CV_ROOT_START.append(len(b.bm.verts))
        nx, _ny, nz = _cv_node_center(node)
        phase = node * 0.37
        for c, ry0 in enumerate(CV_ROOT_ANGLES):
            ry = ry0 + phase + (c - 1) * 0.11
            reach = CV_ROOT_LEN * (0.8 + 0.2 * ((node + c) % 3))
            out = (math.sin(ry), math.cos(ry))
            b.card((nx + out[0] * reach * 0.5, -CV_R * 0.55,
                    nz + out[1] * reach * 0.5),
                   (CV_ROOT_W, reach), "cv_root", axis='Y',
                   art=CV_ROOT_ART, rot=(0.0, ry, 0.0))
    for node in CV_NODES:
        CV_LEAF_START.append(len(b.bm.verts))
        nx, _ny, nz = _cv_node_center(node)
        for k in range(CV_LEAVES_PER):
            # a sprig leaves the node fanned forward off the wall, so the leaves
            # are seen face-on rather than edge-on against the substrate
            ry = (k - 1) * 0.85 + (node % 3) * 0.3
            out = (math.sin(ry), math.cos(ry))
            b.card((nx + out[0] * CV_LEAF_LEN * 0.5, CV_R * 0.9,
                    nz + out[1] * CV_LEAF_LEN * 0.5),
                   (CV_LEAF_W, CV_LEAF_LEN), "cv_leaf", axis='Y', art=CV_LEAF_ART,
                   rot=(0.0, ry, 0.0))
    CV_FLASH_START = len(b.bm.verts)
    fx, _fy, fz = _cv_node_center(CV_NODES[-1])
    b.card((fx, CV_R * 1.5, fz + CV_LEN * 0.06), (0.4, 0.4), "cv_flare",
           axis='Y', art=CV_FLASH_ART)
    return b.finish("ClimbvineRigged")


def climbvine_chains():
    """One chain up the rope, a point per ring, so a bend travels its length; a
    bone per rootlet CLUSTER, because a cluster grips and lets go as one thing
    and a chain would only tear it into strips."""
    chains = [{"prefix": "vine",
               "points": [(_cv_x(i), 0.0, _cv_z(i)) for i in range(CV_RINGS)]}]
    for n, node in enumerate(CV_NODES):
        nx, _ny, nz = _cv_node_center(node)
        chains.append({"prefix": "root%d" % n,
                       "parent": "vine_%d" % min(node, CV_RINGS - 2),
                       "points": [(nx, 0.0, nz), (nx, -0.15, nz)]})
    for n, node in enumerate(CV_NODES):
        nx, _ny, nz = _cv_node_center(node)
        chains.append({"prefix": "leaf%d" % n,
                       "parent": "vine_%d" % min(node, CV_RINGS - 2),
                       "points": [(nx, CV_R * 0.9, nz),
                                  (nx, CV_R * 0.9 + 0.06, nz)]})
    fx, _fy, fz = _cv_node_center(CV_NODES[-1])
    chains.append({"prefix": "flash", "parent": "vine_%d" % (CV_RINGS - 2),
                   "points": [(fx, CV_R * 1.5, fz + CV_LEN * 0.06),
                              (fx, CV_R * 1.5, fz + CV_LEN * 0.06 + 0.05)]})
    return chains


cv_piece = build_climbvine_rigged()
# The rootlet bundle is the plant's whole affordance and the player reads it
# from a hand's distance while harvesting, so the piece is drawn at the close
# range the spec asks for. At 48 a cluster card is ten texels across and a
# hair cannot be a hair; at 96 the strands have gaps between them, which is
# the only thing that makes a bundle read as hair rather than as a chip.
pl.texture_object(cv_piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
cv_arm = rig.build_armature("Climbvine", climbvine_chains())
rig.bind(cv_piece, cv_arm, kind='ARMATURE_NAME')
for i, start in enumerate(CV_START):
    end = CV_START[i + 1] if i + 1 < len(CV_START) else CV_ROOT_START[0]
    rig.assign_exclusive_weights(cv_piece, "vine_%d" % i, range(start, end))
for n, start in enumerate(CV_ROOT_START):
    end = CV_ROOT_START[n + 1] if n + 1 < len(CV_ROOT_START) else CV_LEAF_START[0]
    rig.assign_exclusive_weights(cv_piece, "root%d_0" % n, range(start, end))
for n, start in enumerate(CV_LEAF_START):
    end = CV_LEAF_START[n + 1] if n + 1 < len(CV_LEAF_START) else CV_FLASH_START
    rig.assign_exclusive_weights(cv_piece, "leaf%d_0" % n, range(start, end))
rig.assign_exclusive_weights(cv_piece, "flash_0",
                             range(CV_FLASH_START, len(cv_piece.data.vertices)))

CV_GONE = 0.001
CV_WORKED = len(CV_NODES) - 1          # she works the node nearest the fresh end
CV_READY = "vine_%d" % (CV_RINGS - 2)  # the internode above it is what she readies
cv_held = {}
for n in range(len(CV_NODES)):
    cv_held["root%d_0" % n] = 1.0
for i in range(CV_RINGS - 1):
    cv_held["vine_%d" % i] = 1.0
cv_held["vine_0"] = (0.0, 0.0, 0.0)
cv_held["flash_0"] = CV_GONE
for n in range(len(CV_NODES)):
    cv_held["leaf%d_0" % n] = CV_GONE

# TEND: "she works at one specific node, encouraging the rootlet cluster there and
# the inter-node section above it to thicken... the next vine to harvest visibly
# readies - its fibres thicken, the section becomes more prominently rope-like."
# Seven seconds, inside the 6-8 the spec asks for, and it ends in the flare.
CV_WORKED_ROOT = "root%d_0" % CV_WORKED
cv_readied = dict(cv_held)
cv_readied[CV_WORKED_ROOT] = 1.34
cv_readied[CV_READY] = 1.45
for n in range(len(CV_NODES)):
    cv_readied["leaf%d_0" % n] = 1.0
cv_half = dict(cv_held)
cv_half[CV_WORKED_ROOT] = 1.18
cv_half[CV_READY] = 1.16
# the flush travels: the sprigs nearest the worked node are out first
for n in range(len(CV_NODES)):
    cv_half["leaf%d_0" % n] = 1.0 if n >= len(CV_NODES) - 3 else CV_GONE
cv_lit = dict(cv_readied)
cv_lit["flash_0"] = 1.0
rig.clip(cv_arm, "climbvine_tend", [
    (0.0, dict(cv_held)),
    (3.0, cv_half),
    (6.2, dict(cv_readied)),
    (6.6, cv_lit),
    (7.0, dict(cv_readied)),
])
# HARVEST: the readied section comes off and the plant is back to unreadied. The
# cluster keeps what the tending built - taking a length does not undo it.
cv_taken = dict(cv_held)
cv_taken[CV_WORKED_ROOT] = 1.34
for n in range(len(CV_NODES)):
    cv_taken["leaf%d_0" % n] = 1.0
rig.clip(cv_arm, "climbvine_harvest", [
    (0.0, dict(cv_readied)),
    (0.7, cv_taken),
])
# DEATH: "the rootlets pulling away from the substrate, the inter-node sections
# drying out and thinning. On full death, the vine drops off the surface entirely
# and lies on the ground." So the grip goes first, then the body, then it falls.
cv_dying = dict(cv_held)
for n in range(len(CV_NODES)):
    cv_dying["root%d_0" % n] = (0.75, 0.0, 0.0)
    cv_dying["leaf%d_0" % n] = CV_GONE
for i in range(CV_RINGS - 1):
    cv_dying["vine_%d" % i] = 0.72
cv_dying["vine_0"] = (0.0, 0.0, 0.0)
cv_fallen = dict(cv_dying)
cv_fallen["vine_0"] = (-1.15, 0.0, 0.0)
rig.clip(cv_arm, "climbvine_wither", [
    (0.0, dict(cv_held)),
    (1.4, cv_dying),
    (2.4, cv_fallen),
])
rig.park(cv_arm, dict(cv_held))

cv_report = rig.validate(cv_piece, cv_arm, {"vine": CV_RINGS - 1})
print("[RIG] Climbvine %s bones=%d dead=%s orphans=%d"
      % (cv_report["verdict"], cv_report["bones"],
         cv_report["dead_bones"] or "none", cv_report["orphan_verts"]))
if cv_report["verdict"] != "PASS":
    raise SystemExit("climbvine rig does not deform: %s" % cv_report["problems"])


# ============================================================================
# MOTHER FLURE - "one specimen in the entire game, encountered once", and the
# holder of its canonical moment: "the central body responds to care for the
# first time in decades. Petals unfurl, internal structures light, smaller
# offshoots throughout the chamber illuminate in cascading sequence."
#
# Card ENT-021 ships her in exactly two frames and they are the two states the
# spec names. DORMANT: the trumpet collapsed and slumped off the head of the
# stalk, grey, with the offshoots around the chamber unlit. BLOOMED: the same
# trumpet opened flat and radiant, every offshoot lit, haze in the air.
#
# So the piece is built as ONE organism rather than a prop and a light: a stalk
# out of root lobes, a ring of petals that actually fold, and the offshoots on
# their own root-fingers -- because the spec's point is that they are the same
# plant. "The connectedness of the root system becomes visible" is a statement
# about geometry, and the cascade is what proves it: each offshoot lights after
# the one before, so the player watches the signal travel her roots.
#
# She rests DORMANT. It is "the default state on entry", it is what the chamber
# has held for decades, and "if the player skips tending her, she remains in the
# pre-bloom dormant state for the rest of the game" -- a Mother who spawned
# bloomed would have spent the only moment she has.
# ============================================================================

MF_PETALS = 15
MF_PETAL_SEG = 3
MF_STALK_Z = [0.0, 0.7, 1.45, 2.15]
MF_HEAD_Z = 2.15
MF_OFFSHOOTS = 6
MF_HAZE = 5
# the sphere the crown's flutes are cut from: centred ABOVE the head so the rings
# widen on the way up and the wall flares instead of closing
MF_BELL_C = (0.0, 0.0, 3.32)
MF_BELL_R = 1.02
MF_LOBE_START = 0
MF_ROOTS = 14                      # the prop-root skirt she stands on
MF_BLADES = 4                      # the splayed triangular blade-leaves
MF_STALK_START = []
MF_CALYX_START = 0
MF_PETAL_START = []
MF_CORE_START = 0
MF_OFF_START = []
MF_GLOW_START = []
MF_HAZE_START = []
MF_FLASH_START = 0
MF_VEIN_START = 0
MF_VEIN_SPAN = 6.6         # out past the furthest offshoot


def _mf_vein_art(tile, isl, px_per_m):
    """Her network, drawn: a trace running out to each offshoot, forking as it
    goes. Everything between the traces is alpha, so the chamber floor shows
    through and the mat reads as veins in the ground rather than a rug of light."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0
    hot = CS("flure_core")
    warm = _dim(CS("flure_core"), 0.62)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    heads = [a for (_r, a) in MF_OFF_AT]
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            rr = (dx * dx + dy * dy) ** 0.5
            if rr > 0.98 or rr < 0.03:
                continue
            th = math.atan2(dy, dx)
            near = 9.0
            for k, a in enumerate(heads):
                wob = 0.10 * math.sin(rr * 9.0 + k * 2.3) + 0.05 * math.sin(rr * 21.0 - k)
                d = abs(((th - a - wob + math.pi) % math.tau) - math.pi)
                near = min(near, d)
                # a fork peeling off each main run once it is well clear of her
                if rr > 0.42:
                    near = min(near, abs(d - 0.20 * (rr - 0.42)))
            width = 0.030 * (1.0 - rr * 0.35)
            if near > width:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = hot if near < width * 0.45 else warm


MF_VEIN_ART = pl.register_card_art("rigged_mf_vein", _mf_vein_art)

# Around her, at the radius the card puts them, each on a root-finger reaching
# back to the lobes she grew them from.
MF_OFF_AT = [(2.45, 0.35), (1.9, 1.5), (2.7, 2.7), (2.2, 3.9), (2.9, 4.9),
             (2.05, 5.7)]


def _mf_off_xy(i):
    r, a = MF_OFF_AT[i]
    return (math.sin(a) * r, math.cos(a) * r)


def _mf_petal_base(a):
    """Where a petal springs from the calyx rim."""
    return (math.sin(a) * 0.42, math.cos(a) * 0.42, MF_HEAD_Z + 0.34)


def _mf_petal_art(tile, isl, px_per_m):
    """One wall-segment of her trumpet, drawn to the same wedge the species uses:
    narrow at the throat, wide at the rim, pleated down its length, toothed along
    the top edge. Nine overlap into one continuous funnel -- the petals are the
    form, the pleating is the repetition, and the ribs stay close in value because
    a hard dark rib reads as a GAP and breaks the wall back into prongs.

    What is hers rather than the species': she has been shut in a sealed room for
    decades, so the wall has greyed over and "faint traces of the rust-red the
    species had in life" survive only in the deepest crevices -- the rib troughs,
    where nothing reached them."""
    ph, pw = tile.shape[:2]
    grey = _dim(CS("root_worn"), 0.86)
    grey_d = _dim(CS("root_worn"), 0.66)
    crevice = _dim(CS("flure_bronze"), 0.78)
    spine = _dim(CS("root_worn"), 1.06)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    tooth = max(1, int(round(pw / 7.0)))
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)              # 0 at the throat, 1 at the rim
        half = cx * (0.3 + 0.7 * t)
        for x in range(pw):
            d = abs(x - cx)
            if d > half:
                continue
            if t > 0.95 and ((x // tooth) % 2) == 0:
                continue                           # the rim, toothed across
            tile[row, x, 3] = 1.0
            k = int(d / max(1.0, half / 4.0))
            col = grey_d if k % 2 else grey
            if k % 2 and t < 0.72:
                col = crevice                      # the life still down in the pleat
            if d < half * 0.13:
                col = spine
            tile[row, x, :3] = col


def _mf_glow_art(tile, isl, px_per_m):
    """What an offshoot lighting looks like: a soft round throw with no edge, so
    an unlit one is a plant and a lit one is a plant with light coming out of it
    rather than a disc pasted over the scene."""
    ph, pw = tile.shape[:2]
    core = _dim(CS("flure_core"), 1.25)
    warm = CS("flure_bronze")
    emit = isl.get("emit") if isinstance(isl, dict) else None
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            if r > 1.0:
                tile[y, x, 3] = 0.0
                continue
            k = round(((1.0 - r) ** 1.6) * 5.0) / 5.0
            if k <= 0.0:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = [core[i] * k + warm[i] * (1.0 - k) for i in range(3)]
            if emit is not None:
                emit[y, x] = [core[i] * k for i in range(3)]


def _mf_haze_art(tile, isl, px_per_m):
    """The phytosiderophore haze: "the air in the chamber filling with reddish
    dust". Dust is drawn, never modelled and never a particle system -- a field
    of sparse motes thinning upward, so it reads as air with something in it."""
    ph, pw = tile.shape[:2]
    dust = CS("flure_bronze")
    dust_d = _dim(CS("flure_bronze"), 0.6)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    for y in range(ph):
        # densest low and thinning as it rises, and thinning to nothing at the
        # sides as well: a card whose motes stop on a straight vertical line
        # publishes its own rectangle, and then the air has edges
        thin = 1.0 - (y / max(1.0, ph - 1.0))
        for x in range(pw):
            across = 1.0 - min(1.0, abs(x - cx) / max(1.0, cx))
            h = ((x * 26699) ^ (y * 92083) ^ ((x * y) & 0xFF)) & 0xFFFF
            if (h % 100) > (3.0 + 24.0 * thin) * (across ** 1.5):
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = dust if (h % 3) else dust_d


def _mf_flash_art(tile, isl, px_per_m):
    """The completion flare over the crown. Hers is the longest tending in the
    game, so the signal that it took is drawn wide, with the same quantised
    falloff the rest of the pixel art steps in."""
    ph, pw = tile.shape[:2]
    core = _dim(CS("flure_core"), 1.35)
    warm = CS("flure_bronze")
    emit = isl.get("emit") if isinstance(isl, dict) else None
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            spoke = abs(math.cos(math.atan2(dy, dx) * 4.5)) ** 5
            reach = 0.32 + 0.64 * spoke
            if r > reach:
                tile[y, x, 3] = 0.0
                continue
            k = round(((1.0 - r / reach) ** 2) * 5.0) / 5.0
            if k <= 0.0:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = [core[i] * k + warm[i] * (1.0 - k) for i in range(3)]
            if emit is not None:
                emit[y, x] = [core[i] * k for i in range(3)]


MF_PETAL_ART = pl.register_card_art("rigged_mother_petal", _mf_petal_art)
MF_GLOW_ART = pl.register_card_art("rigged_mother_glow", _mf_glow_art)
MF_HAZE_ART = pl.register_card_art("rigged_mother_haze", _mf_haze_art)
MF_FLASH_ART = pl.register_card_art("rigged_mother_flash", _mf_flash_art)

pl.register_parts({
    # THREE VALUES, and two of them are green. The sheet gives her a sage stalk,
    # olive blade-leaves at the foot and cool mauve-grey flutes; every part here
    # was keyed to a warm bronze or a bark brown, so the whole plant came out one
    # temperature and none of it was the colour she actually is.
    "mf_lobe":  {"rgb": CS("root_bark")},
    "mf_root":  {"rgb": _dim(CS("root_worn"), 0.78)},
    "mf_blade": {"rgb": CS("gasafoetida_stalk")},
    "mf_stalk": {"rgb": CS("hushbloom_stem")},
    "mf_calyx": {"rgb": _dim(CS("flure_bronze"), 0.72)},
    "mf_petal": {"rgb": CS("flure_bronze")},
    "mf_core":  {"rgb": CS("flure_core"), "emit": CS("flure_core")},
    "mf_glow":  {"rgb": CS("flure_core"), "emit": CS("flure_core")},
    "mf_haze":  {"rgb": CS("flure_bronze")},
    "mf_flare": {"rgb": CS("flure_core"), "emit": CS("flure_core")},
    # THE NETWORK. Her clonal veins run the floor of the chamber out to every
    # offshoot, dark while she is dormant and lit all the way when she blooms —
    # the sheet shows the traces igniting BEFORE the crown does. They are
    # repetition spidering over a surface, so they are drawn on one mat rather
    # than modelled as tubes, exactly like the Spiker's root field.
    "mf_vein":  {"rgb": CS("flure_core"), "emit": CS("flure_core")},
}, emit_strength={"mf_core": 2.4, "mf_glow": 3.2, "mf_flare": 4.0})


def build_mother_flure_rigged():
    """The organism: root lobes and their fingers, the stalk, the calyx and its
    ring of petals, the core inside, six offshoots wearing their own throw, the
    haze they raise, and the flare that says the tending took."""
    b = Builder()
    global MF_LOBE_START, MF_CALYX_START, MF_CORE_START, MF_FLASH_START
    MF_LOBE_START = len(b.bm.verts)
    # ROOT LOBES: broad and low, and the roots STOP being roots well before they
    # reach anything. They used to run the whole way out to each offshoot as
    # twenty-centimetre limbs — six thick arms radiating from a hub, which is the
    # spoked wheel the audit saw, and which no view of the sheet contains.
    #
    # They were doing that because the network had to be "legible as geometry
    # rather than implied". It does not any more: the network is drawn on its own
    # mat, which is what the alpha-card law asks for — a thing that repeats across
    # a surface is painted, and only what holds the FORM stays a mesh. What holds
    # her form is her footing, so the roots are footing now: short, thick where
    # they leave the lobe, gone by a third of the way out, and the veins carry on
    # from where they end.
    # HER FOOTING IS AN OPEN SPLAY, not a plate. Every view stands her on a skirt
    # of thin woody prop-roots running down and outward with daylight between
    # them, and three or four big triangular blade-leaves splayed among them. A
    # solid lobe disc with five stubs on it is a pedestal: it reads as something
    # she was mounted on rather than something she grew.
    b.ngon_prism((0, 0), 0.24, 0.30, 0.16, "mf_lobe", sides=11, z0=0.0)
    for k in range(MF_ROOTS):
        a = math.tau * k / MF_ROOTS + 0.21
        reach = 0.80 + 0.34 * ((k * 5) % 3) / 2.0
        mid = 0.46 + 0.10 * ((k * 7) % 3)
        b.tube([(math.cos(a) * 0.14, math.sin(a) * 0.14, 0.40),
                (math.cos(a) * mid, math.sin(a) * mid, 0.19),
                (math.cos(a) * reach, math.sin(a) * reach, 0.010)],
               [0.034, 0.019, 0.008], "mf_root", sides=5, cap_start=False)
    for k in range(MF_BLADES):
        a = math.tau * k / MF_BLADES + 0.62
        b.limb((math.cos(a) * 0.20, math.sin(a) * 0.20, 0.44),
               (math.cos(a) * 1.10, math.sin(a) * 1.10, 0.016),
               0.150, 0.014, "mf_blade", sides=3)
    for i in range(len(MF_STALK_Z) - 1):
        MF_STALK_START.append(len(b.bm.verts))
        z0, z1 = MF_STALK_Z[i], MF_STALK_Z[i + 1]
        r0 = 0.255 - 0.022 * i
        r1 = 0.255 - 0.022 * (i + 1)
        span = z1 - z0
        b.ngon_prism((0, 0), r1, r0, span * 0.87, "mf_stalk", sides=9, z0=z0,
                     cap_top=False, cap_bottom=(i == 0))
        b.ngon_prism((0, 0), r1, r1 * 1.2, span * 0.13, "mf_stalk", sides=9,
                     z0=z0 + span * 0.87, cap_top=False)
    MF_CALYX_START = len(b.bm.verts)
    b.ngon_prism((0, 0), 0.44, 0.2, 0.36, "mf_calyx", sides=MF_PETALS, z0=MF_HEAD_Z)
    for i in range(MF_PETALS):
        a = i * math.tau / MF_PETALS
        length = 0.99 if i % 2 == 0 else 0.9
        bx, by, bz = _mf_petal_base(a)
        tilt = 0.62
        rr = math.sin(tilt) * length * 0.5
        MF_PETAL_START.append(len(b.bm.verts))
        # A TRUMPET, not a fan of blades. The flutes are cut from a sphere centred
        # ABOVE the head, so each one's ring radius GROWS as it rises and the
        # fifteen of them meet edge to edge into a continuous wall.
        #
        # NO WEDGE ART. The painter cuts a petal silhouette out of a rectangle
        # with alpha around it, which is exactly right for a flat card standing
        # alone and exactly wrong here: the shell already IS the wedge, so the art
        # cut it back down into the blade it was supposed to stop being.
        # THE AZIMUTH CONVENTIONS DIFFER and have to be reconciled here. This
        # species places everything at (sin a, cos a) — clockwise from +Y — while
        # Builder.shell lays its ring at (cos A, sin A), the ordinary
        # anticlockwise-from-+X. Passed the raw angle each flute lands mirrored
        # about the 45-degree line from the bone that drives it, so the dormant
        # curl swings it somewhere it was never meant to go and the crown bunches
        # to one side. A = pi/2 - a is the same direction in the other convention.
        b.shell(MF_BELL_C, MF_BELL_R, math.pi * 0.5 - a,
                (math.pi / MF_PETALS) * 0.97,
                bz + 0.04, bz + 0.04 + length * 0.86, "mf_petal",
                segments=MF_PETAL_SEG)
    MF_CORE_START = len(b.bm.verts)
    b.ngon_prism((0, 0), 0.12, 0.2, 0.2, "mf_core", sides=8, z0=MF_HEAD_Z + 0.3)
    # THE OFFSHOOTS: small trumpets of the same plant, each with its own throw.
    for i in range(MF_OFFSHOOTS):
        ox, oy = _mf_off_xy(i)
        h = 0.42 + 0.12 * (i % 3)
        MF_OFF_START.append(len(b.bm.verts))
        b.ngon_prism((ox, oy), 0.07, 0.11, h, "mf_stalk", sides=6, z0=0.0)
        b.ngon_prism((ox, oy), 0.24, 0.08, 0.17, "mf_petal", sides=7, z0=h)
        b.ngon_prism((ox, oy), 0.06, 0.09, 0.06, "mf_calyx", sides=6, z0=h + 0.13)
    for i in range(MF_OFFSHOOTS):
        ox, oy = _mf_off_xy(i)
        h = 0.42 + 0.12 * (i % 3)
        MF_GLOW_START.append(len(b.bm.verts))
        b.card((ox, oy, h + 0.2), (0.62, 0.62), "mf_glow", axis='Y', art=MF_GLOW_ART)
    for i in range(MF_HAZE):
        a = i * math.tau / MF_HAZE + 0.4
        r = 1.5 + 0.5 * (i % 3)
        MF_HAZE_START.append(len(b.bm.verts))
        b.card((math.sin(a) * r, math.cos(a) * r, 1.15), (1.5, 2.1), "mf_haze",
               axis='Y', art=MF_HAZE_ART, rot=(0.0, 0.0, a))
    global MF_VEIN_START
    MF_VEIN_START = len(b.bm.verts)
    b.card((0, 0, 0.012), (MF_VEIN_SPAN, MF_VEIN_SPAN), "mf_vein", axis='Z',
           art=MF_VEIN_ART)
    MF_FLASH_START = len(b.bm.verts)
    b.card((0, 0, MF_HEAD_Z + 0.55), (2.6, 2.6), "mf_flare", axis='Z',
           art=MF_FLASH_ART)
    b.card((0, 0, MF_HEAD_Z + 0.55), (2.6, 2.6), "mf_flare", axis='Y',
           art=MF_FLASH_ART)
    return b.finish("MotherFlureRigged")


def mother_flure_chains():
    """The stalk is one chain so a stir travels it; every petal is a chain so it
    can UNFURL rather than hinge; each offshoot and each throw gets one bone,
    because a cascade is a matter of WHEN they move, not of anything travelling
    through them."""
    chains = [{"prefix": "stalk",
               "points": [(0.0, 0.0, z) for z in MF_STALK_Z]}]
    for i in range(MF_PETALS):
        a = i * math.tau / MF_PETALS
        length = 0.99 if i % 2 == 0 else 0.9
        bx, by, bz = _mf_petal_base(a)
        tilt = 0.62
        pts = []
        for sgi in range(MF_PETAL_SEG + 1):
            f = sgi / float(MF_PETAL_SEG)
            pts.append((bx + math.sin(a) * math.sin(tilt) * length * f,
                        by + math.cos(a) * math.sin(tilt) * length * f,
                        bz + math.cos(tilt) * length * f))
        chains.append({"prefix": "petal%d" % i, "parent": "stalk_2", "points": pts})
    chains.append({"prefix": "calyx", "parent": "stalk_2",
                   "points": [(0.0, 0.0, MF_HEAD_Z), (0.0, 0.0, MF_HEAD_Z + 0.36)]})
    chains.append({"prefix": "core", "parent": "stalk_2",
                   "points": [(0.0, 0.0, MF_HEAD_Z + 0.3),
                              (0.0, 0.0, MF_HEAD_Z + 0.5)]})
    for i in range(MF_OFFSHOOTS):
        ox, oy = _mf_off_xy(i)
        h = 0.42 + 0.12 * (i % 3)
        chains.append({"prefix": "off%d" % i,
                       "points": [(ox, oy, 0.0), (ox, oy, h + 0.2)]})
        chains.append({"prefix": "glow%d" % i, "parent": "off%d_0" % i,
                       "points": [(ox, oy, h + 0.2), (ox, oy, h + 0.35)]})
    for i in range(MF_HAZE):
        a = i * math.tau / MF_HAZE + 0.4
        r = 1.5 + 0.5 * (i % 3)
        chains.append({"prefix": "haze%d" % i,
                       "points": [(math.sin(a) * r, math.cos(a) * r, 0.1),
                                  (math.sin(a) * r, math.cos(a) * r, 2.2)]})
    chains.append({"prefix": "mflash", "parent": "stalk_2",
                   "points": [(0.0, 0.0, MF_HEAD_Z + 0.55),
                              (0.0, 0.0, MF_HEAD_Z + 0.75)]})
    # the network gets its own bone so it can be dark while she is, and light
    # BEFORE the crown does — the sheet ignites the floor first
    chains.append({"prefix": "vein", "points": [(0.0, 0.0, 0.01), (0.0, 0.0, 0.09)]})
    return chains


mf_piece = build_mother_flure_rigged()
pl.texture_object(mf_piece, OBJX, px_per_m=32.0, painted_dir=PAINTED)
mf_arm = rig.build_armature("MotherFlure", mother_flure_chains())
rig.bind(mf_piece, mf_arm, kind='ARMATURE_NAME')
# the lobes and their fingers ride the stalk's base; they are her footing
rig.assign_exclusive_weights(mf_piece, "stalk_0", range(MF_LOBE_START, MF_STALK_START[0]))
for i, start in enumerate(MF_STALK_START):
    end = MF_STALK_START[i + 1] if i + 1 < len(MF_STALK_START) else MF_CALYX_START
    rig.assign_exclusive_weights(mf_piece, "stalk_%d" % i, range(start, end))
rig.assign_exclusive_weights(mf_piece, "calyx_0", range(MF_CALYX_START, MF_PETAL_START[0]))
for i, start in enumerate(MF_PETAL_START):
    rig.weight_chain_strip(mf_piece, "petal%d" % i, rig.card_rows(start, MF_PETAL_SEG))
rig.assign_exclusive_weights(mf_piece, "core_0", range(MF_CORE_START, MF_OFF_START[0]))
for i, start in enumerate(MF_OFF_START):
    end = MF_OFF_START[i + 1] if i + 1 < len(MF_OFF_START) else MF_GLOW_START[0]
    rig.assign_exclusive_weights(mf_piece, "off%d_0" % i, range(start, end))
for i, start in enumerate(MF_GLOW_START):
    end = MF_GLOW_START[i + 1] if i + 1 < len(MF_GLOW_START) else MF_HAZE_START[0]
    rig.assign_exclusive_weights(mf_piece, "glow%d_0" % i, range(start, end))
for i, start in enumerate(MF_HAZE_START):
    end = MF_HAZE_START[i + 1] if i + 1 < len(MF_HAZE_START) else MF_VEIN_START
    rig.assign_exclusive_weights(mf_piece, "haze%d_0" % i, range(start, end))
rig.assign_exclusive_weights(mf_piece, "vein_0",
                             range(MF_VEIN_START, MF_FLASH_START))
rig.assign_exclusive_weights(mf_piece, "mflash_0",
                             range(MF_FLASH_START, len(mf_piece.data.vertices)))

MF_SHUT, MF_LIT = 0.001, 1.0
# DORMANT is the rest pose: petals shut over the throat, the head carried off the
# top of the stalk the way the card slumps it, core down to nothing, every
# offshoot dark, no haze, no flare.
mf_dormant = {
    "calyx_0": 1.0,
    "core_0": 0.06,
    "mflash_0": MF_SHUT,
    # SHE STANDS UP. Every drawn view has her erect on a vertical stalk; a 30
    # degree lean at the top carried the head off its own axis, so the dormant
    # plant read as one already spent rather than one waiting. What droops when
    # she is dormant is the CROWN closing over the core, not the stalk giving way.
    "stalk_0": (0.02, 0.0, 0.0),
    "stalk_1": (0.05, 0.0, 0.0),
    "stalk_2": (0.09, 0.0, 0.0),
}
for i in range(MF_PETALS):
    mf_dormant["petal%d_0" % i] = (0.86 if i % 2 == 0 else 0.95, 0.0, 0.0)
    mf_dormant["petal%d_1" % i] = (0.34, 0.0, 0.0)
    mf_dormant["petal%d_2" % i] = (0.26, 0.0, 0.0)
for i in range(MF_OFFSHOOTS):
    mf_dormant["off%d_0" % i] = 1.0
    mf_dormant["glow%d_0" % i] = MF_SHUT
mf_dormant["vein_0"] = MF_SHUT
for i in range(MF_HAZE):
    mf_dormant["haze%d_0" % i] = MF_SHUT

# TEND: "the offshoots throughout the chamber slowly brighten in cascading
# sequence -- a Flure across the room responds, then another, then another."
# Thirteen seconds, inside the 12-15 the spec asks for, and the cascade is
# written as what it is: one offshoot per beat, in order, around her.
mf_tend_poses = [(0.0, dict(mf_dormant))]
for i in range(MF_OFFSHOOTS):
    beat = 1.6 + 1.55 * i
    lit = dict(mf_dormant)
    for j in range(i + 1):
        lit["glow%d_0" % j] = MF_LIT
    mf_tend_poses.append((beat, lit))
mf_awake = dict(mf_dormant)
for j in range(MF_OFFSHOOTS):
    mf_awake["glow%d_0" % j] = MF_LIT
mf_awake["core_0"] = 0.7                      # she stirs, but has not opened yet
mf_awake["stalk_2"] = (0.4, 0.0, 0.0)
mf_tend_poses.append((13.0, mf_awake))
rig.clip(mf_arm, "mother_flure_tend", mf_tend_poses)

# BLOOM: the climax. "Petals unfurl, internal structures light, smaller offshoots
# throughout the chamber illuminate in cascading sequence. Phytosiderophore haze
# rises from every offshoot simultaneously." The head comes up off the stalk, the
# petals open out, the core swells, the haze rises, and the flare fires last.
mf_open = dict(mf_awake)
mf_open.update({"stalk_0": (0.0, 0.0, 0.0), "stalk_1": (0.0, 0.0, 0.0),
                "stalk_2": (0.0, 0.0, 0.0), "core_0": 1.5, "calyx_0": 1.12})
for i in range(MF_PETALS):
    mf_open["petal%d_0" % i] = (-0.62, 0.0, 0.0)
    mf_open["petal%d_1" % i] = (-0.22, 0.0, 0.0)
    mf_open["petal%d_2" % i] = (-0.14, 0.0, 0.0)
for i in range(MF_HAZE):
    mf_open["haze%d_0" % i] = MF_LIT
mf_rising = dict(mf_awake)
mf_rising.update({"stalk_1": (0.05, 0.0, 0.0), "stalk_2": (0.18, 0.0, 0.0),
                  "core_0": 1.0})
# THE FLOOR LIGHTS FIRST. On the sheet the traces are already running before the
# crown is anything but pale — the network is how she reaches the chamber, so a
# bloom that starts at the head has the causality backwards.
rig.clip(mf_arm, "mother_flure_bloom", [
    (0.0, dict(mf_awake, vein_0=MF_SHUT)),
    (0.9, dict(mf_awake, vein_0=0.45)),      # the traces run out to the offshoots
    (1.6, dict(mf_rising, vein_0=0.8)),      # the head comes up after them
    (3.4, dict(mf_open, vein_0=MF_LIT, mflash_0=MF_SHUT)),   # the trumpet opens
    (3.8, dict(mf_open, vein_0=MF_LIT, mflash_0=MF_LIT)),
    (4.6, dict(mf_open, vein_0=MF_LIT, mflash_0=MF_SHUT)),   # and the network holds
])

# POST-BLOOM: what the chamber looks like for the rest of the game. The brief
# holds the haze "in the air at low intensity" rather than letting it fall, so
# this is not a return to dormant — the trumpet stays open and the traces stay
# lit, and only the haze settles back to a fraction of its climax. Without this
# the bloom's last key leaves every haze card at full and the chamber reads as
# though the moment never ended.
mf_settled = dict(mf_open)
for i in range(MF_HAZE):
    mf_settled["haze%d_0" % i] = MF_SHUT + (MF_LIT - MF_SHUT) * 0.35
mf_settled["core_0"] = 1.28
rig.clip(mf_arm, "mother_flure_post_bloom", [
    (0.0, dict(mf_open, vein_0=MF_LIT, mflash_0=MF_SHUT)),
    (2.2, dict(mf_settled, vein_0=MF_LIT, mflash_0=MF_SHUT)),  # the haze settles
    (6.0, dict(mf_settled, vein_0=MF_LIT, mflash_0=MF_SHUT)),  # and it stays
])
rig.park(mf_arm, dict(mf_dormant))

mf_report = rig.validate(mf_piece, mf_arm,
                         dict([("petal%d" % i, MF_PETAL_SEG)
                               for i in range(MF_PETALS)]))
print("[RIG] MotherFlure %s bones=%d dead=%s orphans=%d"
      % (mf_report["verdict"], mf_report["bones"],
         mf_report["dead_bones"] or "none", mf_report["orphan_verts"]))
if mf_report["verdict"] != "PASS":
    raise SystemExit("mother flure rig does not deform: %s" % mf_report["problems"])


bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "flora_rigged.blend"))
for _species, _mesh, _armature in (("hushbloom", piece, arm),
                                   ("seefern", sf_piece, sf_arm),
                                   ("capbage", cb_piece, cb_arm),
                                   ("scarpet", sc_piece, sc_arm),
                                   ("flure", fl_piece, fl_arm),
                                   ("gasafoetida", ga_piece, ga_arm),
                                   ("gaspod", gp_piece, gp_arm),
                                   ("climbvine", cv_piece, cv_arm),
                                   ("mother_flure", mf_piece, mf_arm),
                                   ("vinecut", vc_piece, vc_arm),
                                   ("sample", hs_piece, hs_arm)):
    rig.export_rigged_gltf([_mesh, _armature], gltf_for(_species))
    print("[RIG] exported %s -> %s" % (_species, os.path.basename(gltf_for(_species))))
print("=== DONE: rigged flora, one gltf per species in %s ===" % FLORA_DIR)
