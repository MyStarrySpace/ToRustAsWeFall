# HIDRA — the infrastructure mimic, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_hidra.py
#
# Roster: "Hidras | infrastructure ambush, mid | hydroxamate siderophores; THE
# SEGMENTED HELIX is the iron-cage propeller geometry | Sits disguised as cabling
# and ambush-cuts unscanned movement; nasty as a surprise, ordinary once spotted |
# Reveal it first (Seefern light, or Aster's or Tyreg's overlay). After the unspool
# it is a readable melee threat you can walk around or burn."
#
# Its transition is the UNSPOOL. Coiled, it is a loop of cable on a conduit and the
# player walks past it; run out, it is a long bladed body anyone can see and route
# around — the entire encounter is that one change of state, so the change is the
# animation. The coil lets go from the TAIL forward, the three-fold blades roll
# outward segment by segment as the body straightens, and the cutting head opens
# last. A player who watches the far end still coming can read how long is left.
#
# The body is the molecule it is drawn from: three hydroxamate arms wrapping an
# iron atom in a propeller, that octahedron repeated down a chain. So the segment
# is the unit — pinched at its joints, three blades in C3 at its middle, each
# segment's blades phased a little further round than the one behind it, which is
# what makes a straight body still read as a helix.

import bpy
import mathutils
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
importlib.reload(rig)

SRC = os.path.join(BL, "fauna")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "hidra.gltf")
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
def _dim(c, f): return tuple(v * f for v in c)


SEG = 20                   # body links — enough to wind three full turns
SEG_LEN = 0.078
TURNS = 3.0                # how many times it goes round its core
CORE_R = 0.045             # the conduit run it winds along and passes for
CORE_LEN = 1.25
BODY_LEN = SEG * SEG_LEN
R_JOINT = 0.026            # pinched between links, so the coil reads as segmented
R_SEG = 0.036              # no thicker than the conduit it lies against
# The axis stands a blade's reach off the substrate: a segment whose C3 phase puts
# a fin straight down needs the room, and a fin buried in the floor is a third of
# the species' silhouette gone.
TRUNK_Z = 0.20
TWIST_PER_SEG = 0.42       # the propeller phase advancing down the chain
BASE_PHASE = 0.35
STRIP_W = 0.10
HEAD_LEN = 0.24
HEAD_R = 0.062

# A HELIX IS CURVATURE PLUS TORSION, and the second one is what was missing: bend
# alone winds a flat spiral that stacks on itself, and the body ends up bunched at
# one end of the conduit instead of running its length. The pair below is solved
# from the coil the card draws -- radius just clear of the core, TURNS turns over
# CORE_LEN -- so the link length the body actually has arrives where it should.
_HELIX_C = CORE_LEN / (math.tau * TURNS)          # pitch per radian of turn
_HELIX_R = 0.052                                  # riding just off the conduit
_HELIX_D = _HELIX_R ** 2 + _HELIX_C ** 2
BEND = (_HELIX_R / _HELIX_D) * SEG_LEN            # curvature over one link
TWIST = (_HELIX_C / _HELIX_D) * SEG_LEN           # torsion over one link
RISE = 0.0
# A helix's tangent never points along its own axis: it leans off it by the pitch
# angle. Without that lead-in on the first link the coil is built correctly and
# then runs away from the conduit at 38 degrees, which is a helix beside the
# cable rather than around it.
_HELIX_LEAD = math.atan2(_HELIX_R, _HELIX_C)

BODY_SIDES = 6
BODY_START = 0
CORE_START = 0
CUT_START = 0
SKIN_START = 0


def _spine(i):
    """A joint on the body's axis. The body is BUILT STRAIGHT: the coil is a pose,
    not geometry, so one mesh serves both the disguise and the run-out threat."""
    return (0.0, i * SEG_LEN, TRUNK_Z)


def _body_stations():
    """Every station of the ONE run that is the animal, tail cap to cutting tip.

    Three stations to a link — the pinch, the collar, the swell — then the head's
    crown and its tip. The head is not a separate part: it stands on _spine(SEG),
    which is a station of this same list, so the neck is a ring rather than a
    place where two pieces happen to meet.
    """
    pts = [_spine(0)]
    radii = [R_JOINT * 0.9]
    parts = []
    for i in range(SEG):
        y0 = _spine(i)[1]
        pts += [(0.0, y0 + SEG_LEN * 0.16, TRUNK_Z),
                (0.0, y0 + SEG_LEN * 0.55, TRUNK_Z),
                _spine(i + 1)]
        radii += [R_JOINT, R_SEG, R_JOINT * 0.9]
        # the dark recess into the link, then the link swelling to arm-thick and
        # pinching again — the material changes but the surface does not break
        parts += ["hd_recess", "hd_body", "hd_body"]
    neck = _spine(SEG)[1]
    pts += [(0.0, neck + 0.09, TRUNK_Z), (0.0, neck + HEAD_LEN, TRUNK_Z)]
    radii += [HEAD_R, 0.012]
    parts += ["hd_head", "hd_head"]
    return pts, radii, parts


def _ring(r):
    """First vertex of station `r`. One tube lays its rings down consecutively,
    so a station is BODY_SIDES verts at a fixed stride."""
    return BODY_START + BODY_SIDES * r


def _skin_art(tile, isl, px_per_m):
    """The cable read, drawn down the spine: a near-black recess at every joint,
    worn plate sheen between them, and the PINHOLE EYES the species carries one or
    two to a segment. Joints and eyes repeat the whole metre and a half of body, so
    both are pixels. Row 0 is the tail, the last row the head."""
    ph, pw = tile.shape[:2]
    # ENT-011 is pale, and the strip is most of what the eye lands on: painting it
    # bronze-over-black made the animal read dark whatever the body parts said.
    sheen = _dim(CS("resolution_root_pale"), 1.2)
    plate = CS("resolution_root_pale")
    plate_d = _dim(CS("resolution_root_pale"), 0.82)
    recess = _dim(CS("resolution_root_pale"), 0.52)
    eye = _dim(CH("iron_dark"), 1.2)
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))
    for row in range(ph):
        seg_t = (row / max(1.0, ph - 1.0)) * SEG
        frac = seg_t - math.floor(seg_t)
        joint = not (0.16 < frac < 0.84)
        half = (pw * 0.5) * (0.55 if joint else 0.94)
        for x in range(pw):
            if abs(x - mid) > half:
                continue
            tile[row, x, 3] = 1.0
            if joint:
                tile[row, x, :3] = recess
            elif x == mid:
                tile[row, x, :3] = sheen            # the specular line of a cable
            else:
                h = ((x * 73856093) ^ (row * 19349663)) & 0xFFFF
                tile[row, x, :3] = plate if h % 4 else plate_d
    # The eyes sit off the midline and alternate sides, so a column of them reads
    # as an animal watching rather than as a seam down a pipe.
    for s in range(SEG):
        for (at, side) in ((0.38, -1), (0.66, 1)):
            row = int(round(((s + at) / float(SEG)) * (ph - 1)))
            col = mid + side * max(1, pw // 4)
            if 0 <= row < ph and 0 <= col < pw and tile[row, col, 3] > 0.0:
                tile[row, col, :3] = eye


SKIN_ART = pl.register_card_art("hidra_skin", _skin_art)

pl.register_parts({
    "hd_body":   {"rgb": CS("resolution_root_pale")},
    "hd_recess": {"rgb": _dim(CS("resolution_root_pale"), 0.78)},
    "hd_skin":   {"rgb": _dim(CS("resolution_root_pale"), 0.9)},
    "hd_head":   {"rgb": _dim(CS("resolution_root_pale"), 0.95)},
    # The core it winds around: the conduit run it is pretending to be part of.
    "hd_core":   {"rgb": _dim(CS("resolution_root_pale"), 0.84)},
    # The hooks it cuts with. Dark, small, and at the ends only -- the card gives
    # it no lit edge, and the roster gives it no tell of its own: being SEEN is
    # the whole event, which is why it is a reveal-gate rather than a fight.
    "hd_hook":   {"rgb": _dim(CH("iron_dark"), 1.1)},
})


def build_hidra():
    """A pale segmented helix wound round a straight core, hooked at either end.

    Card ENT-011 is the whole brief: a smooth coil lying along a conduit run,
    pale, with no lit edge and no armour -- something you walk past. What was here
    before was a bronze worm wearing three blades per segment in C3, which is the
    SAPSCRAP's geometry (its body is the siderophore's C3 symmetry); a Hidra is
    the hydroxamate iron-cage propeller, and a propeller is what a helix is."""
    b = Builder()
    global BODY_START, CUT_START, SKIN_START, CORE_START
    CORE_START = len(b.bm.verts)
    # The conduit runs along the coil's OWN axis, which is not the axis the body
    # is authored on: a helix's tangent leans off its axis by the pitch angle, so
    # a body built straight up +Y winds around a line tilted by that much. Laying
    # the conduit down that line is what puts the animal ON the cable instead of
    # beside it -- and the angle is read off the same curvature-and-torsion pair
    # the coil is built from, so the two cannot drift apart.
    ax, ay = math.sin(_HELIX_LEAD), math.cos(_HELIX_LEAD)
    b.limb((-ax * 0.12, -ay * 0.12, TRUNK_Z),
           (ax * CORE_LEN, ay * CORE_LEN, TRUNK_Z),
           CORE_R, CORE_R, "hd_core", sides=8)
    # ONE swept run from the tail cap to the cutting tip. A limb orients its
    # rings to its own axis, so where two of them met on this helix their rings
    # sat in different planes and shared no vertices — the body was cut at all
    # sixty-one joints and stood open along every one of them in the coiled pose
    # it ships in. Swept and stitched, each joint is a shared edge loop.
    BODY_START = len(b.bm.verts)
    _pts, _radii, _parts = _body_stations()
    b.tube(_pts, _radii, _parts, sides=BODY_SIDES,
           cap_start=True, cap_end=True)
    neck = _spine(SEG)
    CUT_START = len(b.bm.verts)
    # the hook at the head, and its twin back at the tail: two small dark barbs,
    # which is all the card gives it
    b.limb((0.0, neck[1] + HEAD_LEN * 0.55, TRUNK_Z),
           (0.028, neck[1] + HEAD_LEN * 0.92, TRUNK_Z + 0.016),
           0.012, 0.004, "hd_hook", sides=4)
    SKIN_START = len(b.bm.verts)
    # One row per segment, riding the crest of the body: the strip's own recess
    # bands land on the joints, which is where the rows sit.
    b.card((0.0, BODY_LEN * 0.5, TRUNK_Z + R_SEG + 0.003), (STRIP_W, BODY_LEN),
           "hd_skin", axis='Z', art=SKIN_ART, segments=SEG)
    return b.finish("HidraRigged")


def hidra_chains():
    """A bone per body segment, so the unspool TRAVELS the body — a coil released
    everywhere at once is a shape change, not a movement, and the travel is what
    the player reads time off. The head leads it; the cutting blades open last."""
    neck = _spine(SEG)
    return [
        # The conduit run is its own bone and never moves: what unspools is the
        # animal, and the thing it was pretending to belong to stays put.
        {"prefix": "core",
         "points": [(-math.sin(_HELIX_LEAD) * 0.12, -math.cos(_HELIX_LEAD) * 0.12, TRUNK_Z),
                    (math.sin(_HELIX_LEAD) * CORE_LEN, math.cos(_HELIX_LEAD) * CORE_LEN, TRUNK_Z)]},
        {"prefix": "helix", "points": [_spine(i) for i in range(SEG + 1)]},
        {"prefix": "head", "parent": "helix_%d" % (SEG - 1),
         "points": [neck, (0.0, neck[1] + HEAD_LEN, TRUNK_Z)]},
        {"prefix": "cut", "parent": "head_0",
         "points": [(0.0, neck[1] + 0.06, TRUNK_Z),
                    (0.0, neck[1] + 0.2, TRUNK_Z)]},
    ]


piece = build_hidra()
pl.texture_object(piece, OBJX, px_per_m=48.0, painted_dir=PAINTED)
arm = rig.build_armature("Hidra", hidra_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')
rig.assign_exclusive_weights(piece, "core_0", range(CORE_START, BODY_START))
# Exclusive weights put the whole crease between two bones on ONE span, so which
# span it lands on is the decision. A bone takes its own joint, pinch and swell —
# rings 3i to 3i+2 — which leaves the crease on the swell-to-next-joint span, the
# longest in the link at 0.45 of its length. Claiming the ring at the bone's TIP
# instead would drop it on the 12 mm pinch, where a 33 degree bend folds the quad
# back through itself.
for i in range(SEG):
    rig.assign_exclusive_weights(piece, "helix_%d" % i,
                                 range(_ring(3 * i), _ring(3 * i + 3)))
# the head is the last three stations of the same run, so the neck creases on a
# long span too
rig.assign_exclusive_weights(piece, "head_0", range(_ring(3 * SEG), CUT_START))
rig.assign_exclusive_weights(piece, "cut_0", range(CUT_START, SKIN_START))
# The spine strip has one row per segment, weighted row by row, so it bends with
# the body it is drawn on instead of riding one bone and shearing off the coil.
rig.weight_chain_strip(piece, "helix", rig.card_rows(SKIN_START, SEG))

RUN_BEND = 0.14            # the slack undulation left in a body that has run out
RUN_TWIST = 0.10
HIDDEN, OPEN = 0.001, 1.0


def _coiled(f, lead=0.0):
    """The body `f` of the way wound. `lead` holds the coil at the HEAD while the
    tail lets go, which is the direction a Hidra comes out of its disguise."""
    out = {}
    for i in range(SEG):
        t = i / float(max(1, SEG - 1))
        k = max(0.0, min(1.0, f + lead * t))
        out["helix_%d" % i] = (RISE * k, TWIST * k, BEND * k)
    return out


def _runout():
    """Run out along the substrate: one slack undulation down the length, the
    blades rolled outward. This is the readable threat the roster promises."""
    out = {}
    for i in range(SEG):
        out["helix_%d" % i] = (0.0, RUN_TWIST,
                               RUN_BEND * math.sin(math.tau * i / float(SEG)))
    return out


# COILED is the rest state and the disguise: wound tight against the conduit, head
# tucked into the coil, no cutting edge showing anywhere on it.
coiled = dict(_coiled(1.0), head_0=(0.0, 0.0, 0.62), cut_0=HIDDEN)
runout = dict(_runout(), head_0=(-0.16, 0.0, 0.0), cut_0=OPEN)

rig.clip(arm, "hidra_unspool", [
    (0.0, dict(coiled)),
    (0.4, dict(_coiled(0.74, lead=0.26), head_0=(0.0, 0.0, 0.5), cut_0=HIDDEN)),
    (0.95, dict(_coiled(0.3, lead=0.45), head_0=(-0.1, 0.0, 0.2), cut_0=OPEN)),
    (1.5, dict(runout)),
])
# RECOIL: it gives the reveal back. The edge goes away first, then the body winds
# in, and what is left on the conduit is cabling again.
rig.clip(arm, "hidra_recoil", [
    (0.0, dict(runout)),
    (0.55, dict(_coiled(0.4, lead=0.3), head_0=(0.0, 0.0, 0.3), cut_0=HIDDEN)),
    (1.3, dict(coiled)),
])
rig.park(arm, dict(coiled))

# LAY THE CONDUIT ON THE COIL BY MEASURING IT, NOT BY DERIVING IT.
#
# Where a pose-built helix's axis ends up depends on bone-frame conventions, and
# deriving it from the curvature-and-torsion pair put the cable at 38 degrees to
# the animal three times running. The coil is right there once the armature is
# parked, so the axis is READ off the deformed body -- centroid plus the dominant
# direction of the spread -- and the core is moved onto it. Retune the coil and
# the cable follows by construction.
_deps = bpy.context.evaluated_depsgraph_get()
_eval = piece.evaluated_get(_deps)
# the COIL only: rings 0..3*SEG, i.e. everything up to the neck. The head rides
# past the end of the helix and would drag the measured axis off it.
_coords = [piece.matrix_world @ v.co
           for v in _eval.data.vertices[BODY_START:_ring(3 * SEG + 1)]]
if _coords:
    _n = float(len(_coords))
    _mid = mathutils.Vector((sum(c.x for c in _coords) / _n,
                             sum(c.y for c in _coords) / _n,
                             sum(c.z for c in _coords) / _n))
    # the dominant direction, by power iteration on the covariance
    _axis = mathutils.Vector((0.0, 1.0, 0.0))
    for _ in range(24):
        _acc = mathutils.Vector((0.0, 0.0, 0.0))
        for c in _coords:
            d = c - _mid
            _acc += d * d.dot(_axis)
        if _acc.length > 1e-9:
            _axis = _acc.normalized()
    _ts = [(c - _mid).dot(_axis) for c in _coords]
    _t0, _t1 = min(_ts) - 0.09, max(_ts) + 0.09
    _core_verts = piece.data.vertices[CORE_START:BODY_START]
    _old_a = mathutils.Vector((0.0, -0.12, TRUNK_Z))
    _old_b = mathutils.Vector((0.0, CORE_LEN, TRUNK_Z))
    _new_a, _new_b = _mid + _axis * _t0, _mid + _axis * _t1
    _from = (_old_b - _old_a)
    _to = (_new_b - _new_a)
    _rot = _from.normalized().rotation_difference(_to.normalized()).to_matrix().to_4x4()
    _scale = _to.length / max(1e-6, _from.length)
    for _v in _core_verts:
        _local = _v.co - _old_a
        _v.co = _new_a + (_rot @ (_local * _scale))
    print("[HIDRA] conduit measured onto the coil: axis=(%.2f, %.2f, %.2f) len=%.2f"
          % (_axis.x, _axis.y, _axis.z, _to.length))

report = rig.validate(piece, arm, {"helix": SEG})
print("[RIG] Hidra %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("hidra rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "hidra.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: hidra -> %s ===" % GLTF)
