# SIGNFORM PIECES — how the districts name themselves.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_signform_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/signforms.png names
# four, and each one is a different institution's idea of how to be addressed:
#
#   (1) institutional-project wall-plaque      The PLUMBING POWER PROJECT
#   (2) government-aspirational arch-banner    The OPEN FILES INITIATIVE
#   (3) corporate-rebrand hanging sign         The HYPELINES
#   (4) picturesque-community monument-plaque  The GREENFIELDS COLLECTIVE
#
# THE NAMES ARE CANON and set verbatim: each has its own district plate in
# reference-images/architecture/. So does the monument's small print — EST. 2417,
# PLOT 7B, IRRIGATION: OFFLINE. That last line is the whole story of the piece: a
# community that carved its founding date in stone and cannot water its plot.
#
# The four forms are the argument. A project bolts a plaque to a wall, a
# government arches a lit banner over the street, a rebrand hangs a glossy oval
# off a bracket, and a collective raises a headstone with flowers at its foot.
# Nobody chose the same shape, which is the point of drawing them on one sheet.
#
# What is modelled and what is drawn:
#   MODELLED  frames, posts, the arch, the bracket and its chains, the monument
#             and its trough. Silhouette is how you tell them apart at distance.
#   DRAWN     every letter, the arch's lit cobbling, the oval's gloss, the
#             monument's crack field, the rust running out of all of it.

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
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "architecture")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

TEAL = (0.286, 0.376, 0.376)
TEAL_D = (0.196, 0.267, 0.271)
TEAL_L = (0.376, 0.475, 0.463)
STONE = (0.812, 0.796, 0.729)
STONE_D = (0.639, 0.624, 0.565)
RUST = (0.463, 0.243, 0.129)
AMBER = (0.898, 0.792, 0.376)
AMBER_D = (0.612, 0.510, 0.208)
INK = (0.153, 0.259, 0.192)
GLOSS = (0.180, 0.353, 0.243)
PALE = (0.788, 0.855, 0.769)
LEAF = (0.427, 0.541, 0.325)


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _centered(tile, lines, rgb, top, gap=7, scale=1, emit=None):
    """Set a block of lines centred, laid out bottom-first so the card's flipped
    V axis delivers them in reading order."""
    ph, pw = tile.shape[:2]
    for i, (text, sc) in enumerate(reversed(lines)):
        w = text_width(text, sc)
        draw_text(tile, text, max(1, (pw - w) // 2), top + i * gap, rgb,
                  scale=sc, emit=emit)


def _plaque_art(tile, isl, px_per_m):
    """(1) The project plaque: incised letters on a pale ground inside a ruled
    border, with the rust that has crept in from its fixings."""
    ph, pw = tile.shape[:2]
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = STONE
            tile[y, x, 3] = 1.0
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 7:
                tile[y, x, :3] = _dim(STONE, 0.86)
    for inset in (2, 4):                       # the ruled border
        for x in range(inset, pw - inset):
            tile[inset, x, :3] = STONE_D
            tile[ph - 1 - inset, x, :3] = STONE_D
        for y in range(inset, ph - inset):
            tile[y, inset, :3] = STONE_D
            tile[y, pw - 1 - inset, :3] = STONE_D
    lines = [("THE", 1), ("PLUMBING", 2), ("POWER", 2), ("PROJECT", 1)]
    _centered(tile, lines, INK, int(ph * 0.16), gap=int(ph * 0.16))
    for x in range(int(pw * 0.3), int(pw * 0.7)):   # the rule under the name
        tile[int(ph * 0.14), x, :3] = INK
    for (cx, cy) in ((6, 6), (pw - 7, 6), (6, ph - 7), (pw - 7, ph - 7)):
        tile[cy, cx, :3] = _dim(RUST, 0.9)


def _banner_art(tile, isl, px_per_m):
    """(2) The government banner: lettering over a lit cobble field. The cobbles
    are the repetition and the light behind them is what the sheet is selling."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    pitch = max(4, int(0.09 * ph))
    for y in range(ph):
        for x in range(pw):
            row = y // pitch
            ox = (pitch * 0.5) if (row % 2) else 0.0
            cxp = (math.floor((x - ox) / pitch) + 0.5) * pitch + ox
            cyp = (row + 0.5) * pitch
            d = ((x - cxp) ** 2 + (y - cyp) ** 2) ** 0.5 / (pitch * 0.5)
            col = AMBER if d < 0.82 else AMBER_D
            tile[y, x, :3] = col
            tile[y, x, 3] = 1.0
            if emit is not None:
                emit[y, x] = _dim(col, 0.75)
    ink = _dim(INK, 0.7)
    lines = [("THE", 1), ("OPEN FILES", 2), ("INITIATIVE", 1)]
    _centered(tile, lines, ink, int(ph * 0.18), gap=int(ph * 0.24))
    # LETTERING ON A LIT PANEL HAS TO STOP THE LIGHT. The glow is written per
    # pixel, so dark ink over a still-emitting ground washes straight out — the
    # name was barely legible on a banner whose whole job is being read from
    # across a street. The emit is cut wherever a letter sits, which is also what
    # actually happens: the paint is opaque and the lamp is behind it.
    if emit is not None:
        for y in range(ph):
            for x in range(pw):
                if abs(tile[y, x, 0] - ink[0]) < 1e-4                         and abs(tile[y, x, 1] - ink[1]) < 1e-4:
                    emit[y, x] = (0.0, 0.0, 0.0)


def _oval_art(tile, isl, px_per_m):
    """(3) The rebrand: a glossy green oval, a highlight across its top, and the
    little plant mark the company put under its name."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / (pw * 0.48), (y - cy) / (ph * 0.46)
            r = (dx * dx + dy * dy) ** 0.5
            if r > 1.0:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = GLOSS if r < 0.92 else _dim(TEAL_D, 0.9)
            if 0.30 < r < 0.66 and dy < -0.25:      # the gloss band
                tile[y, x, :3] = _dim(GLOSS, 1.5)
    lines = [("THE", 1), ("HYPELINES", 2)]
    _centered(tile, lines, PALE, int(ph * 0.30), gap=int(ph * 0.22))
    # the plant mark: a stem with two leaves, small enough to be a logo
    mx, my = int(cx), int(ph * 0.26)
    for k in range(5):
        if 0 <= my - k < ph:
            tile[my - k, mx, :3] = PALE
    for (dx, dy) in ((-2, -2), (-3, -3), (2, -2), (3, -3), (-2, -4), (2, -4)):
        px, py = mx + dx, my + dy
        if 0 <= px < pw and 0 <= py < ph and tile[py, px, 3] > 0:
            tile[py, px, :3] = PALE


def _monument_art(tile, isl, px_per_m):
    """(4) The community monument: carved names over a cracked face, and the
    small print the collective keeps up to date. IRRIGATION: OFFLINE is the whole
    story of the piece and it is set exactly as the sheet writes it."""
    ph, pw = tile.shape[:2]
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = STONE
            tile[y, x, 3] = 1.0
    # the crack field: a few walks across the face, branching as they go
    def crack(x, y, ang, life):
        for _ in range(life):
            x += math.cos(ang); y += math.sin(ang)
            if not (0 <= x < pw and 0 <= y < ph):
                return
            ang += math.sin((x + y) * 0.21) * 0.22
            tile[int(y), int(x), :3] = STONE_D
            h = (int(x) * 26699) ^ (int(y) * 92083)
            if (h & 0xFF) < 3 and life > 24:
                crack(x, y, ang + 0.9, life // 2)
    for k in range(5):
        crack(pw * (0.1 + 0.2 * k), 0.0, math.pi * 0.5 + (k - 2) * 0.2, int(ph))
    lines = [("THE", 1), ("GREENFIELDS", 2), ("COLLECTIVE", 2), ("EST. 2417", 1)]
    _centered(tile, lines, INK, int(ph * 0.30), gap=int(ph * 0.14))
    small = [("PLOT 7B", 1), ("IRRIGATION: OFFLINE", 1)]
    _centered(tile, small, _dim(INK, 1.2), int(ph * 0.10), gap=int(ph * 0.08))


PLAQUE = pl.register_card_art("signform_plaque", _plaque_art)
BANNER = pl.register_card_art("signform_banner", _banner_art)
OVAL = pl.register_card_art("signform_oval", _oval_art)
MONUMENT = pl.register_card_art("signform_monument", _monument_art)

pl.register_parts({
    "sf_frame": {"rgb": TEAL},
    "sf_frame_d": {"rgb": TEAL_D},
    "sf_frame_l": {"rgb": TEAL_L},
    "sf_stone": {"rgb": STONE},
    "sf_plaque": {"rgb": STONE},
    "sf_banner": {"rgb": AMBER, "emit": _dim(AMBER, 0.75)},
    "sf_oval": {"rgb": GLOSS},
    "sf_leaf": {"rgb": LEAF},
}, emit_strength={"sf_banner": 2.4})


def build_wall_plaque():
    """(1) A plaque bolted flat to a wall, which is what a project does."""
    b = Builder()
    frame = ((0.0, 0.0, 0.0), (0.84, 0.09, 1.02))
    b.box(*frame[:2], "sf_frame")
    inner = ((0.0, -0.045, 0.0), (0.70, 0.03, 0.88))
    b.box(*inner[:2], "sf_plaque")
    b.face_card(inner[0], inner[1], (0.68, 0.86), "sf_plaque", face='-Y',
                art=PLAQUE)
    for sx in (-0.36, 0.36):
        for sz in (-0.45, 0.45):
            b.box((sx, -0.05, sz), (0.06, 0.04, 0.06), "sf_frame_l")
    return b.finish("SignformWallPlaque")


def build_arch_banner():
    """(2) A lit banner arched over the street on two posts, which is what a
    government does."""
    b = Builder()
    for sgn in (-1.0, 1.0):
        b.box((sgn * 0.86, 0.0, 0.72), (0.20, 0.20, 1.44), "sf_frame")
        b.box((sgn * 0.86, 0.0, 0.06), (0.28, 0.28, 0.12), "sf_frame_d")
        b.box((sgn * 0.86, 0.0, 1.46), (0.24, 0.24, 0.10), "sf_frame_l")
    # the arch: panels stepping over the gap
    steps = 7
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        x0, x1 = -0.86 + 1.72 * t0, -0.86 + 1.72 * t1
        z0 = 1.50 + math.sin(t0 * math.pi) * 0.34
        z1 = 1.50 + math.sin(t1 * math.pi) * 0.34
        b.limb((x0, 0.0, z0), (x1, 0.0, z1), 0.11, 0.11, "sf_frame", sides=4)
    panel = ((0.0, -0.06, 1.62), (1.44, 0.05, 0.50))
    b.box(*panel[:2], "sf_banner")
    b.face_card(panel[0], panel[1], (1.40, 0.46), "sf_banner", face='-Y',
                art=BANNER)
    return b.finish("SignformArchBanner")


def build_hanging_oval():
    """(3) A glossy oval swinging off a bracket, which is what a rebrand does."""
    b = Builder()
    b.box((-0.52, 0.0, 0.52), (0.16, 0.16, 1.04), "sf_frame")
    b.box((0.0, 0.0, 0.98), (1.10, 0.10, 0.10), "sf_frame_l")
    b.limb((-0.46, 0.0, 0.86), (-0.10, 0.0, 0.98), 0.05, 0.04, "sf_frame_d",
           sides=4)
    for x in (-0.28, 0.30):                   # the chains
        b.limb((x, 0.0, 0.94), (x, 0.0, 0.70), 0.014, 0.014, "sf_frame_d",
               sides=4)
    oval = ((0.0, 0.0, 0.40), (0.92, 0.07, 0.58))
    b.box(*oval[:2], "sf_oval")
    b.face_card(oval[0], oval[1], (0.90, 0.56), "sf_oval", face='-Y', art=OVAL)
    return b.finish("SignformHangingOval")


def build_monument_plaque():
    """(4) A headstone with a planting trough at its foot, which is what a
    community does — and the trough is where the sheet puts its flowers."""
    b = Builder()
    b.box((0.0, 0.0, 0.72), (1.02, 0.16, 1.32), "sf_stone")
    # the arched head, stepped
    for i in range(5):
        t = (i + 1) / 6.0
        w = 1.02 * math.sqrt(max(0.0, 1.0 - t * t))
        b.box((0.0, 0.0, 1.38 + i * 0.09), (w, 0.16, 0.09), "sf_stone")
    face = ((0.0, -0.09, 0.80), (0.82, 0.03, 1.12))
    b.box(*face[:2], "sf_plaque")
    b.face_card(face[0], face[1], (0.80, 1.10), "sf_plaque", face='-Y',
                art=MONUMENT)
    b.box((0.0, -0.14, 0.10), (1.22, 0.34, 0.20), "sf_frame_d")   # the trough
    b.box((0.0, -0.14, 0.21), (1.10, 0.26, 0.04), "sf_leaf")
    return b.finish("SignformMonument")


PIECES = []
for fn, px in ((build_wall_plaque, 128.0), (build_arch_banner, 128.0),
               (build_hanging_oval, 128.0), (build_monument_plaque, 128.0)):
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[FORM] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 2.6

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "signform_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "signform_pieces.gltf"))
print("=== DONE: signform pieces -> %s ===" % OUT_DIR)
