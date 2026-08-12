# AGHORA PIECES — the bazaar's own vocabulary.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_aghora_pieces.py
#
# THE PLATE IS THE BRIEF: reference-images/architecture/aghora/aghora_market_gate.png.
# The market gate was the piece this district still owed.
#
# Aghora is the same construction as everywhere else in this world and a
# completely different SURFACE. The facility districts are verdigris metal with
# green terminal readouts; Aghora is that metal drowned in violet and magenta
# neon, with warm amber spilling out of every stall behind it. So the archetypes
# do not change — an arch is an arch — and the district styles them, which is
# exactly what a district pieces file is for.
#
# Three pieces, and they are chosen because together they make the plate read:
#   market_gate    the horseshoe arch with its neon ring and lotus keystone
#   neon_sign      the lit box sign, in the several names the plate hangs
#   stall_awning   the striped canopy over every stall under the arch
#
# THE NAMES ARE THE PLATE'S: AGHORA EXCHANGE, LOTUS NO.7 TEAHOUSE, VEILWEAVE
# SILKS, SENSATION SELECTED, BLISS BREW, EXPERIENCE EVERYTHING. They are set
# verbatim for the same reason the facility placards are — someone wrote them.
#
# What is modelled and what is drawn:
#   MODELLED  the arch ring and its jambs, the sign boxes, the awning frames.
#   DRAWN     the neon tube, every letter, the lotus mark, the awning's stripes,
#             the grime. All of it repeats and none of it moves.

import bpy
import importlib
import math
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder
import signtext
importlib.reload(signtext)
from signtext import draw_text, text_width

SRC = os.path.join(BL, "architecture")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "aghora")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

# The plate's palette: the same tired metal, lit by things that want your money.
METAL = (0.243, 0.278, 0.298)
METAL_D = (0.153, 0.176, 0.196)
METAL_L = (0.353, 0.388, 0.404)
NEON = (0.847, 0.361, 0.898)          # the magenta the arch is ringed in
NEON_D = (0.541, 0.204, 0.612)
VIOLET = (0.600, 0.400, 0.898)
AMBER = (0.949, 0.702, 0.376)
RUST = (0.463, 0.243, 0.129)
CANVAS = (0.478, 0.286, 0.290)
CANVAS_L = (0.836, 0.780, 0.686)

GATE_R = 1.45              # the arch's inner radius
GATE_T = 0.34              # how thick the ring is
SIGN_W, SIGN_H = 0.88, 0.42
# The canopy drops 0.30 m over its 0.70 m reach, so the stripes face the street
# rather than the sky — a flat sheet shows a passer-by nothing but its edge.
AWNING_TILT = 0.38


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _grime(tile, base, seed=0x51):
    ph, pw = tile.shape[:2]
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = base
            tile[y, x, 3] = 1.0
            h = ((x * 73856093) ^ (y * 19349663) ^ seed) & 0xFF
            if h < 13:
                tile[y, x, :3] = _dim(RUST, 0.8)
            elif h > 244:
                tile[y, x, :3] = _dim(base, 1.25)


def _lotus(tile, cx, cy, rad, rgb, emit=None):
    """The mark this district brands everything with. Six petals off a centre —
    small, because it is a logo and it is on every sign on the plate."""
    ph, pw = tile.shape[:2]
    for k in range(6):
        a = math.tau * k / 6.0 - math.pi * 0.5
        for t in range(int(rad)):
            f = t / max(1.0, rad - 1)
            wob = math.sin(f * math.pi) * rad * 0.30
            for s in (-1, 1):
                px = int(cx + math.cos(a) * t + math.cos(a + math.pi * 0.5) * wob * s)
                py = int(cy + math.sin(a) * t + math.sin(a + math.pi * 0.5) * wob * s)
                if 0 <= px < pw and 0 <= py < ph:
                    tile[py, px, :3] = rgb
                    tile[py, px, 3] = 1.0
                    if emit is not None:
                        emit[py, px] = rgb


def _gate_ring_detail(tile, mask, base, isl, px_per_m):
    """The arch face: worn metal with the neon tube running its inner edge and
    the lotus set at the crown. The tube is the thing the eye follows, so it is
    drawn bright and continuous rather than modelled as a hundred segments."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    for y in range(ph):
        for x in range(pw):
            tile[y, x] = base
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 13:
                tile[y, x] = _dim(RUST, 0.8)
    # the tube runs along ONE side of every ring segment, so following the arch
    # round draws a continuous line of neon on its inner edge
    for y in range(ph):
        band = y / max(1.0, ph - 1.0)
        for x in range(pw):
            if band < 0.15:
                tile[y, x] = NEON if band < 0.09 else NEON_D
                if emit is not None:
                    emit[y, x] = NEON if band < 0.09 else _dim(NEON_D, 0.7)
            elif band < 0.20:
                tile[y, x] = _dim(METAL_L, 1.05)
            elif 0.78 < band < 0.85:
                tile[y, x] = METAL_L


def _neon_sign_art(name_lines):
    """A lit box sign. The plate hangs a dozen of these and every one is a name
    somebody chose, so they are set as written."""
    def paint(tile, isl, px_per_m):
        ph, pw = tile.shape[:2]
        emit = isl.get("emit") if isinstance(isl, dict) else None
        for y in range(ph):
            for x in range(pw):
                edge = min(x, y, pw - 1 - x, ph - 1 - y)
                if edge < 2:
                    tile[y, x, :3] = METAL_D
                    tile[y, x, 3] = 1.0
                    continue
                tile[y, x, :3] = _dim(NEON_D, 0.36)
                tile[y, x, 3] = 1.0
                if emit is not None:
                    emit[y, x] = _dim(NEON_D, 0.30)
        gap = max(7, int(ph / (len(name_lines) + 0.8)))
        top = max(3, (ph - gap * len(name_lines)) // 2 + 2)
        for i, line in enumerate(reversed(name_lines)):
            w = text_width(line)
            draw_text(tile, line, max(1, (pw - w) // 2), top + i * gap, NEON,
                      emit=emit)
        _lotus(tile, pw * 0.5, ph - 5, 3.0, VIOLET, emit)
    return paint


def _awning_art(tile, isl, px_per_m):
    """The stall canopy: broad stripes, sagging between its ribs, lit warm from
    underneath by whatever is being sold under it."""
    ph, pw = tile.shape[:2]
    stripe = max(3, int(pw * 0.145))
    for y in range(ph):
        warm = 1.0 + 0.35 * (y / max(1.0, ph - 1.0))       # the light beneath
        for x in range(pw):
            base = CANVAS if (x // stripe) % 2 else CANVAS_L
            tile[y, x, :3] = _dim(base, warm)
            tile[y, x, 3] = 1.0
            h = ((x * 26699) ^ (y * 92083)) & 0xFF
            if h < 9:
                tile[y, x, :3] = _dim(RUST, 0.85)
    for x in range(0, pw, stripe):                          # the rib shadows
        for y in range(ph):
            if 0 <= x < pw:
                tile[y, x, :3] = _dim(tile[y, x, :3], 0.82)


GATE_DETAIL = pl.register_detail("aghora_gate_ring", _gate_ring_detail)
def _keystone_art(tile, isl, px_per_m):
    """The lotus at the crown of the arch, lit."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = _dim(METAL_D, 1.1)
            tile[y, x, 3] = 1.0
    _lotus(tile, pw * 0.5, ph * 0.5, max(4.0, min(pw, ph) * 0.34), VIOLET, emit)


AWNING_ART = pl.register_card_art("aghora_awning", _awning_art)
KEYSTONE_ART = pl.register_card_art("aghora_keystone", _keystone_art)

SIGNS = (
    ("AghoraExchange", ["AGHORA", "EXCHANGE"]),
    ("LotusTeahouse", ["LOTUS NO.7", "TEAHOUSE"]),
    ("VeilweaveSilks", ["VEILWEAVE", "SILKS"]),
    ("SensationSelected", ["SENSATION", "SELECTED"]),
    ("BlissBrew", ["BLISS", "BREW"]),
    ("ExperienceEverything", ["EXPERIENCE", "EVERYTHING"]),
)
SIGN_ARTS = {nm: pl.register_card_art("aghora_sign_" + nm, _neon_sign_art(lines))
             for nm, lines in SIGNS}

pl.register_parts({
    "ag_metal": {"rgb": METAL},
    "ag_metal_d": {"rgb": METAL_D},
    "ag_metal_l": {"rgb": METAL_L},
    "ag_gate": {"rgb": METAL, "emit": _dim(NEON, 0.8)},
    "ag_sign": {"rgb": _dim(NEON_D, 0.36), "emit": NEON},
    "ag_canvas": {"rgb": CANVAS},
}, emit_strength={"ag_gate": 2.6, "ag_sign": 3.0})


def build_market_gate():
    """The horseshoe arch the bazaar runs under: a ringed opening on two heavy
    jambs, the neon carried round its inner edge."""
    b = Builder()
    steps = 13
    for i in range(steps):
        a0 = math.pi * (i / steps)
        a1 = math.pi * ((i + 1) / steps)
        # a HORSESHOE, not a semicircle: the plate's arch tucks back in below
        # its widest point, which is what makes it read as a keyhole
        def pt(a):
            r = GATE_R * (1.0 + 0.10 * math.sin(a) - 0.06)
            return (math.cos(a) * r, 0.0, 1.15 + math.sin(a) * r)
        p0, p1 = pt(a0), pt(a1)
        b.limb(p0, p1, GATE_T * 0.5, GATE_T * 0.5, "ag_gate", sides=6,
               detail=GATE_DETAIL)
    # the lotus keystone: a small plate at the crown, which is where the plate
    # puts the mark and the only place a flat card belongs on an arch
    key = ((0.0, -GATE_T * 0.5 - 0.02, 1.15 + GATE_R * 1.06), (0.34, 0.05, 0.34))
    b.box(*key[:2], "ag_gate")
    b.face_card(key[0], key[1], (0.32, 0.32), "ag_gate", face='-Y',
                art=KEYSTONE_ART)
    for sgn in (-1.0, 1.0):                    # the jambs it stands on
        b.box((sgn * GATE_R * 1.02, 0.0, 0.58), (0.42, 0.42, 1.16), "ag_metal")
        b.box((sgn * GATE_R * 1.02, 0.0, 0.07), (0.52, 0.52, 0.14), "ag_metal_d")
        b.box((sgn * GATE_R * 1.02, 0.0, 1.20), (0.48, 0.48, 0.10), "ag_metal_l")
    return b.finish("AghoraMarketGate")


def build_neon_sign(nm):
    """One lit box sign, hung off its bracket."""
    def build():
        b = Builder()
        box = ((0.0, 0.0, 0.0), (SIGN_W, 0.09, SIGN_H))
        b.box(*box[:2], "ag_sign")
        b.face_card(box[0], box[1], (SIGN_W * 0.94, SIGN_H * 0.90), "ag_sign",
                    face='-Y', art=SIGN_ARTS[nm])
        arm_z = SIGN_H * 0.5 + 0.13
        b.box((0.0, 0.31, arm_z), (0.09, 0.04, 0.20), "ag_metal_d")  # wall pad
        b.limb((0.0, 0.30, arm_z), (0.0, -0.02, arm_z), 0.018, 0.015,
               "ag_metal_d", sides=4)                # the arm off the wall
        for sx in (-SIGN_W * 0.34, SIGN_W * 0.34):   # hangers to the top edge
            b.limb((sx, 0.0, arm_z - 0.01), (sx, 0.0, SIGN_H * 0.5 - 0.01),
                   0.012, 0.012, "ag_metal_d", sides=4)
        b.limb((-SIGN_W * 0.36, 0.0, arm_z), (SIGN_W * 0.36, 0.0, arm_z),
               0.013, 0.013, "ag_metal_d", sides=4)  # the spreader they hang on
        return b.finish("AghoraSign" + nm)
    return build


def build_stall_awning():
    """The canopy over a stall: a sloping striped sheet on a light frame."""
    b = Builder()
    b.card((0.0, -0.35, 0.715), (1.20, 0.76), "ag_canvas", axis='Z',
           art=AWNING_ART, rot=(AWNING_TILT, 0.0, 0.0))
    b.box((0.0, 0.0, 0.86), (1.30, 0.07, 0.08), "ag_metal_l")   # the wall rail
    b.box((0.0, -0.70, 0.56), (1.26, 0.06, 0.06), "ag_metal_d")  # the front bar
    for sx in (-0.58, 0.58):
        b.limb((sx, 0.0, 0.84), (sx, -0.70, 0.56), 0.03, 0.025, "ag_metal",
               sides=4)
        b.limb((sx, -0.70, 0.56), (sx, -0.70, 0.0), 0.028, 0.032, "ag_metal",
               sides=5)
    return b.finish("AghoraStallAwning")


BUILDERS = [(build_market_gate, 48.0), (build_stall_awning, 64.0)]
for nm, _lines in SIGNS:
    BUILDERS.append((build_neon_sign(nm), 128.0))

PIECES = []
for fn, px in BUILDERS:
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[AGH] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 3.4

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "aghora_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "aghora_pieces.gltf"))
print("=== DONE: aghora pieces -> %s ===" % OUT_DIR)
