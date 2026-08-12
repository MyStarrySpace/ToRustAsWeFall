# REDACTOR — the invisible enforcer, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_redactor.py
#
# Built against the director's sheets, which are the authority:
#   .../concept/fauna/redactors-revealed-v2.png
#   .../concept/fauna/redactors-cloaked-v2.png
#
# The two sheets are nearly two animals, and the encounter IS the change between
# them, so one rig carries both.
#
# REVEALED: a long low segmented arthropod. A PALE crystalline carapace — the
# lightest mass in the frame — faceted into plates that step down its length,
# with big amber orbs glowing THROUGH the shell, largest over the abdomen and
# diminishing toward the head. Six long thin jointed legs, knees carried high and
# each ending in a fine claw. It has a facing: the body tapers to a head with one
# lit point at its tip.
#
# CLOAKED: a tall curved sickle-shard standing against a wall, wearing the WALL
# and not itself, point on the floor. The roster: it "drifts cloaked as a slice of
# wall and strikes targets that never see it", and "Seefern light or an overlay
# forces it visible (so does a hit landing)".
#
# So cloaked is this same body FOLDED — stood on end, legs drawn in along it, and
# every amber light shut. It rests there, because drifting cloaked is its ordinary
# condition and one that spawned standing has spent its stealth before the player
# arrived.
#
# The orbs are DRAWN. They repeat, and they are glows seen through a shell rather
# than bodies in their own right; what holds the form — carapace, legs — is mesh.

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
importlib.reload(rig)

SRC = os.path.join(BL, "fauna")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "redactor.gltf")
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


LEGS = 6
LEG_SEG = 3                # femur, tibia, foot — the sheet carries two joints
LEG_SIDES = 6
SIDES = 8
BODY_Z = 0.30              # the body rides this far off the ground
# Rear to head. Every other span is a thin SEAM, which is what steps the plates
# down the length without a second body to do it.
BODY_STATIONS = [
    (0.50, 0.075), (0.38, 0.132), (0.355, 0.130), (0.22, 0.148), (0.195, 0.146),
    (0.06, 0.145), (0.035, 0.142), (-0.10, 0.130), (-0.125, 0.127), (-0.26, 0.105),
    (-0.285, 0.102), (-0.42, 0.070), (-0.56, 0.022),
]
SEAM_SPANS = {1, 3, 5, 7, 9}
BODY_BONES = 4

# x, y, size — biggest over the abdomen, falling off toward the head
ORBS = [
    (-0.075, 0.33, 0.115), (0.075, 0.33, 0.105),
    (-0.082, 0.16, 0.130), (0.082, 0.16, 0.120),
    (-0.072, -0.01, 0.104), (0.072, -0.01, 0.098),
    (-0.056, -0.17, 0.078), (0.056, -0.17, 0.073),
    (0.0, -0.32, 0.062),
]

BODY_START = 0
ORB_START = []
LEG_RINGS = []
TIP_START = 0


def _body_r(y):
    """The carapace radius at any point down the body, read off the station table
    rather than guessed — the legs and the orbs both have to sit ON this surface
    and a typed height puts them inside it or floating over it."""
    ys = [s[0] for s in BODY_STATIONS]
    for i in range(len(ys) - 1):
        if ys[i] >= y >= ys[i + 1]:
            t = (ys[i] - y) / max(1e-6, ys[i] - ys[i + 1])
            return BODY_STATIONS[i][1] * (1 - t) + BODY_STATIONS[i + 1][1] * t
    return BODY_STATIONS[0][1] if y > ys[0] else BODY_STATIONS[-1][1]


def _leg_y(i):
    """Six legs on the front two-thirds, three a side, as the sheet ranks them."""
    return (-0.30, -0.14, 0.02)[i % 3]


def _leg_side(i):
    return -1.0 if i < 3 else 1.0


def _leg_path(i):
    """Out through its socket, up to a high knee, then down to a fine claw on the
    floor. The sheet carries the knees ABOVE the body, which is most of why the
    animal reads as a walker rather than a slug, and it draws a dark knuckle where
    each limb leaves the shell — so the socket is the tube's FIRST SPAN rather
    than a collar parked over the join, and the claw is the tube's own taper
    rather than a separate barb stuck on the end."""
    s, y = _leg_side(i), _leg_y(i)
    r = _body_r(y)
    return ([(s * r * 0.72, y, BODY_Z),                # rooted inside the shell
             (s * r * 1.05, y + 0.01, BODY_Z + 0.02),  # the socket knuckle
             (s * 0.30, y + 0.04, BODY_Z + 0.14),      # knee, carried high
             (s * 0.46, y + 0.06, BODY_Z - 0.10),      # ankle
             (s * 0.52, y + 0.07, 0.012)],             # the claw on the floor
            [0.044, 0.038, 0.030, 0.021, 0.006],
            ["rd_seam", "rd_leg", "rd_leg", "rd_leg"])


def _orb_art(tile, isl, px_per_m):
    """One amber orb seen THROUGH the shell: a hot core falling off to a browned
    edge, with the shell's own facets crossing it. It is a glow behind glass, not
    a lamp stuck on the outside, so the rim stays cool and the light never reaches
    the card's edge."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    r = min(pw, ph) * 0.5
    hot = CS("flure_core")
    warm = CH("lamp")
    deep = _dim(CH("rust"), 1.2)
    glass = _dim(CH("rim_light"), 0.62)
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2) / max(1e-6, r)
            if d > 1.0:
                continue
            tile[y, x, 3] = 1.0
            if d > 0.86:
                tile[y, x, :3] = glass       # the shell closing over the orb
                continue
            # facets: a coarse cell grid so the orb reads as cut, not painted
            fx, fy = int(x / 2.6), int(y / 2.6)
            h = ((fx * 73856093) ^ (fy * 19349663)) & 0xFF
            near = max(0.0, 1.0 - d * 1.05)
            base = hot if near > 0.55 else (warm if (h & 1) else deep)
            tile[y, x, :3] = _dim(base, 0.55 + 0.62 * near + 0.06 * (h & 3))
            if emit is not None:
                emit[y, x] = _dim(base, 0.25 + 0.95 * near)


ORB_ART = pl.register_card_art("rd_orb", _orb_art)

pl.register_parts({
    # PALE crystalline — the lightest mass in the frame. The old build had this
    # inverted to near-black, which is the whole reason the reveal read as nothing.
    "rd_cara": {"rgb": _dim(CH("rim_light"), 1.04)},
    "rd_seam": {"rgb": _dim(CH("biolume_stem"), 0.86)},
    "rd_leg": {"rgb": _dim(CH("biolume_stem"), 1.0)},
    "rd_orb": {"rgb": CH("lamp"), "emit": CH("lamp")},
    "rd_tip": {"rgb": CS("flure_core"), "emit": _dim(CS("flure_core"), 1.2)},
}, emit_strength={"rd_orb": 1.7, "rd_tip": 3.6})


def build_redactor():
    """A long plated body, six grafted legs, the orbs drawn through the shell, and
    the one lit point at the head."""
    global BODY_START, TIP_START
    b = Builder()

    # THE CARAPACE — one swept run, plates and seams as SPANS of it. Stacked
    # prisms would abut without sharing vertices and the shell would stand open
    # along every ring the moment the cloak folded it.
    BODY_START = len(b.bm.verts)
    pts = [(0.0, y, BODY_Z) for (y, _r) in BODY_STATIONS]
    radii = [r for (_y, r) in BODY_STATIONS]
    parts = ["rd_seam" if i in SEAM_SPANS else "rd_cara"
             for i in range(len(BODY_STATIONS) - 1)]
    b.tube(pts, radii, parts, sides=SIDES, cap_start=True, cap_end=True)

    # THE ORBS — drawn, lying on the shell's back.
    for (ox, oy, osz) in ORBS:
        ORB_START.append(len(b.bm.verts))
        oz = BODY_Z + _body_r(oy) * 0.80
        b.card((ox, oy, oz), (osz, osz), "rd_orb", axis='Z', art=ORB_ART)

    # THE LEGS — one welded tube each, socket to claw, rooted inside the shell so
    # the junction is covered by its own knuckle.
    #
    # These are NOT grafted, and that is a pipeline gap rather than a choice.
    # `graft.aperture` cuts the host, which both invalidates the carapace's paint
    # group and leaves its own zipper faces belonging to no group at all — so a
    # correctly welded limb comes out with no UV island and samples whatever the
    # atlas left behind. Until graft and the atlas compose, a socketed tube is the
    # honest build: the join is a designed knuckle the sheet draws, not an overlap
    # hidden by an opaque material.
    for i in range(LEGS):
        path, rads, lparts = _leg_path(i)
        LEG_RINGS.append(len(b.bm.verts))
        b.tube(path, rads, lparts, sides=LEG_SIDES, cap_start=False, cap_end=True)

    TIP_START = len(b.bm.verts)
    b.ngon_prism((0.0, -0.585), 0.008, 0.030, 0.05, "rd_tip", sides=6,
                 z0=BODY_Z - 0.025)
    return b.finish("RedactorRigged")


def redactor_chains():
    """The body is a chain so it can FOLD into the shard — a single bone could
    stand it on end but never curve it, and the sheet's cloaked form is a sickle.
    Each leg hangs off the body bone nearest its root; each orb gets a bone so its
    light can be shut without hiding the shell it sits on."""
    ys = [s[0] for s in BODY_STATIONS]
    spine = []
    for k in range(BODY_BONES + 1):
        t = k / float(BODY_BONES)
        spine.append((0.0, ys[0] + (ys[-1] - ys[0]) * t, BODY_Z))
    chains = [{"prefix": "cara", "points": spine}]

    def _near(y):
        best, bi = 1e9, 0
        for k in range(BODY_BONES):
            cy = (spine[k][1] + spine[k + 1][1]) * 0.5
            if abs(cy - y) < best:
                best, bi = abs(cy - y), k
        return "cara_%d" % bi

    for i in range(LEGS):
        path, _r, _p = _leg_path(i)
        y = _leg_y(i)
        # four points, three bones: femur, tibia, foot. The socket station is the
        # femur's root, so a bone never outnumbers the spans it has to deform.
        chains.append({"prefix": "leg%d" % i, "parent": _near(y),
                       "points": [path[0], path[2], path[3], path[4]]})
    for j, (ox, oy, _s) in enumerate(ORBS):
        oz = BODY_Z + _body_r(oy) * 0.80
        chains.append({"prefix": "orb%d" % j, "parent": _near(oy),
                       "points": [(ox, oy, oz - 0.04), (ox, oy, oz)]})
    chains.append({"prefix": "tip", "parent": "cara_%d" % (BODY_BONES - 1),
                   "points": [(0.0, -0.585, BODY_Z - 0.025),
                              (0.0, -0.64, BODY_Z + 0.02)]})
    return chains


piece = build_redactor()
pl.texture_object(piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
arm = rig.build_armature("Redactor", redactor_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')

# THE CARAPACE is one run of rings; a body bone takes the stations that fall
# within its own stretch, so the crease between two of them lands on a plate span
# rather than on one of the thin seams, which cannot carry a fold.
ys = [s[0] for s in BODY_STATIONS]
_edges = [ys[0] + (ys[-1] - ys[0]) * (k / float(BODY_BONES))
          for k in range(BODY_BONES + 1)]
for k in range(BODY_BONES):
    lo_i = 0 if k == 0 else next(i for i, y in enumerate(ys) if y <= _edges[k])
    hi_i = len(ys) if k == BODY_BONES - 1 else next(
        i for i, y in enumerate(ys) if y <= _edges[k + 1])
    rig.assign_exclusive_weights(piece, "cara_%d" % k,
                                 range(BODY_START + lo_i * SIDES,
                                       BODY_START + hi_i * SIDES))
for j, start in enumerate(ORB_START):
    end = ORB_START[j + 1] if j + 1 < len(ORB_START) else LEG_RINGS[0]
    rig.assign_exclusive_weights(piece, "orb%d_0" % j, range(start, end))
# Five rings a leg. The femur takes the socket and the hip, the tibia the knee,
# the foot the ankle and the claw — so both creases land on a full-length span and
# neither falls on the short socket, which could not carry a fold.
for i, start in enumerate(LEG_RINGS):
    end = LEG_RINGS[i + 1] if i + 1 < len(LEG_RINGS) else TIP_START
    rig.assign_exclusive_weights(piece, "leg%d_0" % i,
                                 range(start, start + 2 * LEG_SIDES))
    rig.assign_exclusive_weights(piece, "leg%d_1" % i,
                                 range(start + 2 * LEG_SIDES,
                                       start + 3 * LEG_SIDES))
    rig.assign_exclusive_weights(piece, "leg%d_2" % i,
                                 range(start + 3 * LEG_SIDES, end))
rig.assign_exclusive_weights(piece, "tip_0",
                             range(TIP_START, len(piece.data.vertices)))

OUT, LIT = 0.001, 1.0

# CLOAKED — the rest state. Stood on its head end, curved into the sickle the
# sheet leans on a wall, legs drawn in along the body, every light shut.
# The point goes DOWN — the sheet stands the shard on its tip against the wall,
# and a negative pitch is what carries the head end to the floor.
cloaked = {"cara_0": (-1.62, 0.0, 0.0), "tip_0": OUT}
for k in range(1, BODY_BONES):
    cloaked["cara_%d" % k] = (0.16, 0.0, 0.05)       # the shard's curve
for i in range(LEGS):
    s = _leg_side(i)
    # A limb pointing along +X swings to lie along the body under a POSITIVE turn
    # about Z, and one pointing along -X under a negative one — so the sign
    # follows the side. Getting it backwards splays all six outward into a crown,
    # which is the one silhouette a thing pretending to be a wall cannot have.
    # Folding alone is not enough: the femur lies along the body but the knee and
    # ankle bends carry the limb back out again, and six of those crossing the
    # shard is exactly the silhouette this state exists to avoid. So the leg
    # RETRACTS as it folds — the femur's scale carries the whole chain in, which
    # is what leaves a clean edge for the thing to pass as a slice of wall.
    cloaked["leg%d_0" % i] = {"rot": (0.0, 0.0, s * 1.62), "scale": (0.34,) * 3}
    cloaked["leg%d_1" % i] = {"rot": (0.0, 0.0, s * 0.90)}
    cloaked["leg%d_2" % i] = {"rot": (0.0, 0.0, s * 0.55)}
for j in range(len(ORBS)):
    cloaked["orb%d_0" % j] = OUT

# REVEALED — it drops onto its legs and every orb comes up.
revealed = {"cara_0": (0.0, 0.0, 0.0), "tip_0": LIT}
for k in range(1, BODY_BONES):
    revealed["cara_%d" % k] = (0.0, 0.0, 0.0)
for i in range(LEGS):
    revealed["leg%d_0" % i] = (0.0, 0.0, 0.0)
    revealed["leg%d_1" % i] = (0.0, 0.0, 0.0)
    revealed["leg%d_2" % i] = (0.0, 0.0, 0.0)
for j in range(len(ORBS)):
    revealed["orb%d_0" % j] = LIT


def _norm_pose_value(v):
    """A pose entry is a rotation triple, a uniform scale, or a dict of both.
    Interpolating between two of them means putting all three forms in the same
    shape first."""
    if isinstance(v, dict):
        return (tuple(v.get("rot", (0.0, 0.0, 0.0))),
                tuple(v.get("scale", (1.0, 1.0, 1.0))))
    if isinstance(v, (tuple, list)):
        return (tuple(v), (1.0, 1.0, 1.0))
    return ((0.0, 0.0, 0.0), (float(v),) * 3)


def _lerp_pose(a, b, t):
    out = {}
    for k, va in a.items():
        (ra, sa), (rb, sb) = _norm_pose_value(va), _norm_pose_value(b[k])
        out[k] = {"rot": tuple(ra[n] + (rb[n] - ra[n]) * t for n in range(3)),
                  "scale": tuple(sa[n] + (sb[n] - sa[n]) * t for n in range(3))}
    return out


def _orbs_upto(pose, n):
    """The lights coming up from the head backward, so the reveal has a direction
    and the player's eye is walked toward the end that bites."""
    out = dict(pose)
    order = sorted(range(len(ORBS)), key=lambda j: ORBS[j][1])
    for rank, j in enumerate(order):
        out["orb%d_0" % j] = LIT if rank < n else OUT
    return out


# REVEAL: the wall comes off the wall. A whole beat, because this IS the encounter
# — a snap would spend it before the player had seen what happened.
rig.clip(arm, "redactor_reveal", [
    (0.0, dict(cloaked)),
    (0.25, _orbs_upto(_lerp_pose(cloaked, revealed, 0.35), 2)),
    (0.55, _orbs_upto(_lerp_pose(cloaked, revealed, 0.75), 6)),
    (0.85, dict(revealed)),
])
# CLOAK: it folds back up and the lights go out ahead of the fold, so the last
# thing the player loses is the shape, not the glow.
rig.clip(arm, "redactor_cloak", [
    (0.0, dict(revealed)),
    (0.30, _orbs_upto(_lerp_pose(revealed, cloaked, 0.25), 4)),
    (0.95, dict(cloaked)),
])
rig.park(arm, dict(cloaked))

report = rig.validate(piece, arm,
                      dict([("leg%d" % i, LEG_SEG) for i in range(LEGS)]))
print("[RIG] Redactor %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("redactor rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "redactor.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: redactor -> %s ===" % GLTF)
