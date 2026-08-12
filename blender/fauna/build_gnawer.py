# GNAWER — the pursuit pack hunter, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_gnawer.py
#
# The roster: "Gnawers | pursuit pack, common in Zone 3 | gingipains, heme-pigmented
# proteases | Packs of two to four that hunt by metabolic signature. THE BITE LANDS
# INSIDE AN ENZYME CLOUD that adds damage-over-time, and the corpse stays briefly
# caustic | THE HAZE SWELLS FORWARD RIGHT BEFORE THE BITE."
#
# So the transition is the cloud, not the animal. A player who has to guess when a
# bite is coming can only learn the range by being bitten in it; a cloud that
# reaches out past the jaw draws the line on the floor first, and the whole
# counterplay is stepping back out of it while it grows.
#
# The pigment is the biology it is drawn from: gingipains are heme-scavenging
# proteases, so the jaw, the pores that secrete and the cloud they make all wear
# the same blood-dark red, and the lean hide stays drab around them.

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
GLTF = os.path.join(OUT_DIR, "gnawer.gltf")
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


LEGS = 4                   # a lean quadruped: it runs the player down
HAZE_STATIONS = 3          # cloud stations, each further from the jaw than the last
JAW_OPEN = 0.5             # the gape, in radians at the hinge

# The body runs along Y with the head at -Y, so "forward" is -Y for every part of
# it and the cloud stations simply march further out along that axis.
# LOW-SLUNG. Every view on the sheet puts a DEEP torso close to the ground with
# the legs sprawling out to the sides — the animal is wider than it is tall and it
# reads as armour dragged along the floor. The build stood it up on clear legs
# under a shallow body, which is a different animal walking through the same room.
# EVERY NUMBER BELOW IS FROM THE SEAM CONTRACT — docs/GNAWER_SEAM_CONTRACT.md —
# derived from the turnaround by measurement and stress-tested before use. The
# contract's frame has +Y forward; this build has -Y forward, so Y is mirrored in.
# The old constants made an animal 0.95 long and 0.315 tall; the sheet's is 0.833
# long and 0.410 tall, which is why the rendered side aspect measured 1.44 against
# the sheet's 2.03.
REAR = (0.0, 0.310, 0.210)          # dorsal_ridge_tail_tip
SHOULDER = (0.0, -0.035, 0.410)     # dorsal_ridge_crest — the animal's high point
HEAD_BASE = (0.0, -0.300, 0.210)    # neck seam
MUZZLE = (0.0, -0.512, 0.149)       # snout tip, the leftmost lit pixel of side-L
# THE JAW IS THE ANIMAL'S ONLY DISTANCE TELL, so it hangs and it is pale. On the
# sheet a heavy bone-coloured slab swings well BELOW the chest under a dark plum
# body — it is what the silhouette is built around and the one thing a player
# reads before anything else resolves. It was running nearly level, dropping under
# three centimetres across its whole length, at six centimetres of radius and
# painted a dimmed vein-red: a small dark cone tucked under the snout, invisible
# against the body it hangs off.
JAW_HINGE = (0.0, -0.346, 0.146)    # isolated by COLOUR mask, not silhouette: the
JAW_TIP = (0.0, -0.470, 0.045)      # mandible is the only cream mass on the animal

# Every vertex on the piece belongs to exactly one bone: a span opens with the
# bone that owns it and closes when the next one opens. Weighting a whole creature
# off contiguous spans is what keeps a leg from picking up its neighbour's bone,
# which is the failure automatic weights make on four limbs standing this close.
SPANS = []


def _own(b, bone):
    """Open a weight span — everything built after this belongs to `bone`."""
    SPANS.append((bone, len(b.bm.verts)))


def _hip(i):
    """Where a leg leaves the body: the front pair under the shoulders, the rear
    pair under the haunch. Low and close in, because the sprawl happens at the
    KNEE — a leg that goes straight down from a wide hip is a tall animal with its
    feet apart, not a low one with its elbows out."""
    sx = -1.0 if (i % 2 == 0) else 1.0
    return ((sx * 0.164, -0.200, 0.240) if i < 2      # shoulder_ring_*
            else (sx * 0.158, 0.205, 0.240))          # hip_ring_*


def _knee(i):
    """Between the seam and the ankle, and only slightly proud of the straight line.

    This carried the knee to 3.20x the hip's X at Z 0.265 — nearly as wide as the
    FOOT and high up — so the silhouette reached its full width at knee height and
    then held it flat. That is the flat-topped shoulder boom: measured, the front
    band profile peaked at 100% at 40% down and fell to 71% at the feet, where the
    sheet climbs monotonically to 100% AT the feet. A T where the sheet is a
    triangle. The contract's limb travels 0.164 -> 0.220 in X over 0.175 in Z, so
    the widening is gentle and CONTINUOUS all the way down."""
    hx, hy, hz = _hip(i)
    ax, ay, az = _foot(i)
    t = 0.52
    return (hx + (ax - hx) * t * 1.06,     # a touch proud of the straight line
            hy + (ay - hy) * t,
            hz + (az - hz) * t)


def _foot(i):
    sx = -1.0 if (i % 2 == 0) else 1.0
    # The ankle rings from the contract. The feet still plant outside the body —
    # that is what carries the band profile to 100% at the very bottom — but the
    # width now ARRIVES there rather than at the knee.
    return ((sx * 0.220, -0.138, 0.065) if i < 2      # ankle_fore_*
            else (sx * 0.176, 0.283, 0.075))          # ankle_hind_*


def _haze_at(k):
    """A cloud station, standing out in front of the jaw. Lighting them in order
    is what carries the swell FORWARD instead of blooming in place — the player
    reads the reach growing toward them, and that reach is the warning."""
    return (0.0, -0.70 - 0.16 * k, 0.375)


def _haze_size(k):
    return 0.34 + 0.13 * k


def _haze_art(tile, isl, px_per_m):
    """The enzyme cloud, drawn: a field of droplets is repetition, and repetition
    is a texture. Its edge softens by STIPPLE rather than by a fade — alpha here is
    on or off, so a soft boundary is made of holes, and holes keep their bite at
    32 px per metre where a gradient turns to mush."""
    ph, pw = tile.shape[:2]
    hot = CH("lamp_red")
    mid = _dim(CS("scarpet_senesce"), 0.95)
    deep = CH("vein_ridge")
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx = (x - cx) / max(1.0, cx)
            dy = (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
            n = (h % 100) / 100.0
            if r > 0.96:
                continue
            # the further out, the more of the droplet field is missing
            keep = 1.0 if r < 0.42 else (0.7 if r < 0.68 else 0.34)
            if n > keep:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = hot if r < 0.28 else (mid if r < 0.62 else deep)


def _pore_art(tile, isl, px_per_m):
    """The secreting pores along the flank, where the cloud comes from. A pore
    field repeats, so it is drawn on one card: a staggered grid of pits ringed in
    heme pigment, everything between them transparent so the hide shows through."""
    ph, pw = tile.shape[:2]
    # NOT A GLYPH, AND NOT RED. This drew each pore as the five texels
    # (0,0) (1,0) (-1,0) (0,1) (0,-1) — which is a PLUS SIGN — in vein_ridge
    # (#5c1c1f, hue 357) on vein_bark (#331214, hue 356). Measured on the render
    # that printed roughly ten separately countable crosses in one flank patch,
    # 305 pixels at hue 359-0, and it was the loudest thing on the animal.
    #
    # The sheet has NO red at all: every warm pixel on it is hue 9-30 ochre, it is
    # thin seam-work rather than marks, and it totals 0.07% of the turnaround side
    # view. So a pore is now ONE dark texel with a single ochre high-side neighbour
    # — a pit, not a cross — keyed to rust (#42210f, hue 21), which sits inside
    # the sheet's own warm band.
    ring = CH("rust")
    pit = _dim(CH("rust"), 0.55)
    tile[:, :, 3] = 0.0
    pitch = max(4, int(round(0.085 * px_per_m)))
    for gy in range(1, ph, pitch):
        row = gy // pitch
        for gx in range(1 + (pitch // 2) * (row % 2), pw, pitch):
            for dx, dy, col in ((0, 0, pit), (0, -1, ring)):
                x, y = gx + dx, gy + dy
                if 0 <= x < pw and 0 <= y < ph:
                    tile[y, x, 3] = 1.0
                    tile[y, x, :3] = col


HAZE_ART = pl.register_card_art("gnawer_haze", _haze_art)
PORE_ART = pl.register_card_art("gnawer_pore", _pore_art)

pl.register_parts({
    "gn_hide": {"rgb": _dim(CS("root_bark"), 0.85)},
    "gn_jaw":  {"rgb": _dim(CS("resolution_root_pale"), 1.16)},
    "gn_fang": {"rgb": CS("resolution_root_pale")},
    # THE SHEET HAS NO RED. The pore field was keyed to a vein red and printed
    # bold saturated glyphs in rows across the flank and back — the loudest thing
    # on a creature whose colour story is oxidised brown over bone.
    "gn_pore": {"rgb": _dim(CS("root_bark"), 1.25)},
    # THE SHEET HAS NO RED ON THIS ANIMAL. Its eye is a small pale specular set
    # under the hood, not a lamp — and a lamp is what the build had, bright enough
    # to be the first thing read on a creature whose whole silhouette is the tell.
    "gn_eye":  {"rgb": _dim(CS("resolution_root_pale"), 1.25)},
    # the chunky bone-tan feet every view ends its limbs with
    "gn_foot": {"rgb": _dim(CS("resolution_root_pale"), 1.1)},
    "gn_plate": {"rgb": _dim(CS("root_bark"), 1.05)},
    # The cloud is the only thing on the animal that grows. It is authored at full
    # size so the atlas allots it texels, and its bones are parked shut instead.
    "gn_haze": {"rgb": _dim(CS("scarpet_senesce"), 0.9), "emit": CH("lamp_red")},
}, emit_strength={"gn_haze": 1.8})


def build_gnawer():
    """A lean four-legged body under a heavy jaw, with the cloud standing off the
    muzzle where the bite lands."""
    b = Builder()
    _own(b, "body_0")
    # A DEEP torso, not a lean one: the sheet's body is far thicker than its
    # ground clearance, which is most of what makes it read as armoured.
    b.limb(REAR, SHOULDER, 0.145, 0.165, "gn_hide", sides=7)
    b.limb((0.0, 0.46, 0.27), REAR, 0.04, 0.125, "gn_hide", sides=5)
    b.limb(SHOULDER, HEAD_BASE, 0.125, 0.108, "gn_hide", sides=7)
    # THE SHOULDER HUMP and the BACKSWEPT SCAPULAR BLADES. Every view carries a
    # raised mass over the shoulders with two angular plates sweeping up and back
    # off it — the animal's whole upper outline, and the build had none of it.
    b.ngon_prism((0.0, -0.16), 0.135, 0.175, 0.085, "gn_plate", sides=6,
                 z0=0.375)
    # SCAPULAR, and they sweep BACK. Rooted at the neck and thrown up in a V they
    # are head-horns, which is a different animal; the sheet grows them off the
    # SHOULDER mass and lays them back along the spine, barely above the hump.
    for sx in (-1.0, 1.0):
        b.limb((sx * 0.105, -0.13, 0.435), (sx * 0.165, 0.175, 0.455),
               0.070, 0.020, "gn_plate", sides=4)
    for sx in (-1.0, 1.0):                     # the pore field, proud of the flank
        b.card((sx * 0.168, 0.02, 0.315), (0.40, 0.19), "gn_pore", axis='Y',
               art=PORE_ART, rot=(0.0, 0.0, sx * math.pi * 0.5))

    _own(b, "head_0")
    b.limb(HEAD_BASE, MUZZLE, 0.118, 0.078, "gn_hide", sides=6)
    # THE HOOD: a wide faceted plate flaring over the skull and out past it, which
    # is the first shape the sheet reads and the reason the head looks armoured
    # rather than merely large.
    b.ngon_prism((0.0, -0.455), 0.150, 0.186, 0.034, "gn_plate", sides=5,
                 z0=0.345)
    for sx in (-1.0, 1.0):
        b.ngon_prism((sx * 0.055, -0.50), 0.011, 0.015, 0.018, "gn_eye", sides=5,
                     z0=0.352)
        b.limb((sx * 0.032, -0.60, 0.34), (sx * 0.032, -0.605, 0.318),
               0.013, 0.004, "gn_fang", sides=5)

    _own(b, "jaw_0")
    b.limb(JAW_HINGE, JAW_TIP, 0.105, 0.072, "gn_jaw", sides=6)
    for sx in (-1.0, 1.0):
        b.limb((sx * 0.030, -0.55, 0.312), (sx * 0.030, -0.555, 0.336),
               0.013, 0.004, "gn_fang", sides=5)

    for i in range(LEGS):
        # ONE welded tube from hip to ankle. Two chained limbs meet at the knee in
        # different planes and share no vertices, so the leg opens along that joint
        # exactly when a pose bends it.
        _own(b, "leg%d_0" % i)
        hip, knee, foot = _hip(i), _knee(i), _foot(i)
        b.tube([hip, knee], [0.078, 0.058], "gn_hide", sides=6, cap_end=False)
        _own(b, "leg%d_1" % i)
        b.tube([knee, foot], [0.058, 0.044], "gn_hide", sides=6, cap_start=False)
        # THE FOOT. Every view ends a limb in a chunky bone-tan pad with blocky
        # splayed toes, and the build simply stopped the leg in mid-air with no
        # foot geometry and nothing pale below the body at all.
        fx, fy, fz = foot
        b.ngon_prism((fx, fy), 0.062, 0.055, 0.042, "gn_foot", sides=6,
                     z0=0.0)
        base = math.atan2(fx, fy)
        for t in (-0.55, 0.0, 0.55):
            a = base + t
            b.limb((fx, fy, 0.020),
                   (fx + math.sin(a) * 0.062, fy + math.cos(a) * 0.062, 0.012),
                   0.024, 0.014, "gn_foot", sides=4)

    for k in range(HAZE_STATIONS):
        _own(b, "haze%d_0" % k)
        c = _haze_at(k)
        s = _haze_size(k)
        b.card(c, (s, s), "gn_haze", axis='Z', art=HAZE_ART)
        b.card(c, (s, s), "gn_haze", axis='Y', art=HAZE_ART)
    return b.finish("GnawerRigged")


def gnawer_chains():
    """The spine carries the head, the head carries the jaw AND the cloud — so a
    Gnawer that turns takes its cloud with it and the reach stays in front of the
    teeth wherever the teeth are pointed. A leg is two bones, hip to knee to foot."""
    chains = [
        {"prefix": "body", "points": [REAR, SHOULDER]},
        {"prefix": "head", "parent": "body_0", "points": [HEAD_BASE, MUZZLE]},
        {"prefix": "jaw", "parent": "head_0", "points": [JAW_HINGE, JAW_TIP]},
    ]
    for i in range(LEGS):
        chains.append({"prefix": "leg%d" % i, "parent": "body_0",
                       "points": [_hip(i), _knee(i), _foot(i)]})
    for k in range(HAZE_STATIONS):
        cx, cy, cz = _haze_at(k)
        # the bone's head sits AT the card's centre, so scaling it grows the cloud
        # about itself instead of sliding it off the muzzle
        chains.append({"prefix": "haze%d" % k, "parent": "head_0",
                       "points": [(cx, cy, cz), (cx, cy - 0.08, cz)]})
    return chains


piece = build_gnawer()
pl.texture_object(piece, OBJX, px_per_m=48.0, painted_dir=PAINTED)
arm = rig.build_armature("Gnawer", gnawer_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')
for _i, (_bone, _start) in enumerate(SPANS):
    _end = SPANS[_i + 1][1] if _i + 1 < len(SPANS) else len(piece.data.vertices)
    rig.assign_exclusive_weights(piece, _bone, range(_start, _end))

GONE, FULL = 0.001, 1.0
# IDLE is the state the player meets first: a pack animal standing there with its
# mouth shut and no cloud at all. A haze already showing at rest is a warning
# nobody gets, because there is nothing left for it to change into.
IDLE = {"body_0": (0.0, 0.0, 0.0), "head_0": (0.0, 0.0, 0.0), "jaw_0": (0.0, 0.0, 0.0)}
for _i in range(LEGS):
    IDLE["leg%d_0" % _i] = (0.0, 0.0, 0.0)
    IDLE["leg%d_1" % _i] = (0.0, 0.0, 0.0)
for _k in range(HAZE_STATIONS):
    IDLE["haze%d_0" % _k] = GONE


def _crouch(pose, amount):
    """Shoulders down over braced front legs. The body loading the bite is what
    keeps the cloud attached to an animal rather than floating in front of one."""
    out = dict(pose)
    out["body_0"] = (amount * 0.35, 0.0, 0.0)
    for i in range(LEGS):
        lead = 1.0 if i < 2 else -0.55
        out["leg%d_0" % i] = (amount * lead, 0.0, 0.0)
        out["leg%d_1" % i] = (-amount * lead * 0.6, 0.0, 0.0)
    return out


def _cloud(pose, scale):
    """Every station at one size — the cloud held, rather than travelling."""
    out = dict(pose)
    for k in range(HAZE_STATIONS):
        out["haze%d_0" % k] = scale
    return out


# HAZE: the warning. The stations light from the jaw outward, so what the player
# watches is the reach growing toward them while the gape opens behind it. This is
# the window to step back out of, and it runs long enough to be a decision.
haze_poses = [(0.0, dict(IDLE))]
lit = dict(IDLE)
for _k in range(HAZE_STATIONS):
    lit = _crouch(lit, 0.05 + 0.05 * _k)
    lit["haze%d_0" % _k] = FULL
    lit["jaw_0"] = (JAW_OPEN * (0.35 + 0.25 * _k), 0.0, 0.0)
    haze_poses.append((0.45 + 0.42 * _k, dict(lit)))
PRIMED = dict(lit, jaw_0=(JAW_OPEN, 0.0, 0.0))
haze_poses.append((1.55, dict(PRIMED)))
rig.clip(arm, "gnawer_haze", haze_poses)

# BITE: the jaw snaps through a cloud at full reach, the body drives off the rear
# legs, and then both settle. The clip carries its own cloud from the parked pose
# so an ambush bite still lands inside one.
rig.clip(arm, "gnawer_bite", [
    (0.0, dict(IDLE)),
    (0.08, _cloud(dict(_crouch(IDLE, 0.16), jaw_0=(JAW_OPEN, 0.0, 0.0)), FULL)),
    (0.2, _cloud(dict(_crouch(IDLE, -0.14), jaw_0=(-0.06, 0.0, 0.0)), 1.25)),
    (0.55, _cloud(dict(IDLE, jaw_0=(0.05, 0.0, 0.0)), 0.45)),
    (1.0, dict(IDLE)),
])
rig.park(arm, dict(IDLE))

report = rig.validate(piece, arm, dict(("leg%d" % i, 2) for i in range(LEGS)))
print("[RIG] Gnawer %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("gnawer rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "gnawer.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: gnawer -> %s ===" % GLTF)
