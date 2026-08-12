# SIGNAGE PIECES — what the facility tells you, in its own words.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_signage_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/signage.png names
# five — regulatory placards, sector designator, status readout board, floor toll
# projection, district emblems.
#
# THE WORDS ARE GIVEN AND THEY ARE USED VERBATIM. Elsewhere on this project I drew
# illegible glyph-texture on a hanging sign, on the grounds that inventing words
# for a language nobody has written is worse than leaving it as light. That still
# holds where nothing is written — but here the sheet writes them, so they are
# canon and they get set exactly: NO LOITERING / NO SITTING / NO RESTING, STANDING
# ONLY BEYOND THIS POINT, KEEP AISLE CLEAR, VIOLATORS WILL BE CITED, and a status
# board reporting on PORE CLAMP, HONEYCOMB, FLOW VALVE and VENT SEAL — which are
# the very pieces the windows and doors sheets build. The facility is monitoring
# its own hardware, and that is worth not paraphrasing.
#
# Text is drawn with a 3x5 bitmap font at the project's pixel scale. Letters are
# the most repetitive thing on any of these sheets, so of course they are pixels.

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
BONE = (0.812, 0.796, 0.714)
BONE_D = (0.612, 0.600, 0.529)
RUST = (0.463, 0.243, 0.129)
GREEN = (0.361, 0.910, 0.498)
GREEN_D = (0.180, 0.500, 0.271)
DARK = (0.043, 0.055, 0.051)


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


from signtext import FONT, draw_text, text_width          # noqa: F401

def _plate_ground(tile, base, rusty=True):
    ph, pw = tile.shape[:2]
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = base
            tile[y, x, 3] = 1.0
            if not rusty:
                continue
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 14:
                tile[y, x, :3] = _dim(RUST, 0.8 + 0.4 * (h / 14.0))
    for x in range(pw):                       # the plate's edge
        tile[0, x, :3] = _dim(base, 0.7)
        tile[ph - 1, x, :3] = _dim(base, 1.2)
    for y in range(ph):
        tile[y, 0, :3] = _dim(base, 0.7)
        tile[y, pw - 1, :3] = _dim(base, 1.2)


def _placard_art(lines):
    def paint(tile, isl, px_per_m):
        ph, pw = tile.shape[:2]
        _plate_ground(tile, TEAL_D)
        n = len(lines)
        block = n * 6 - 1
        top = max(1, (ph - block) // 2)
        for i, line in enumerate(reversed(lines)):
            w = text_width(line)
            draw_text(tile, line, max(1, (pw - w) // 2), top + i * 6, BONE)
        for (cx, cy) in ((2, 2), (pw - 4, 2), (2, ph - 6), (pw - 4, ph - 6)):
            tile[cy, cx, :3] = _dim(BONE, 0.8)      # the fixing screws
    return paint


def _designator_art(tile, isl, px_per_m):
    """The sector numeral, embossed: a big glyph with a lit top edge and a dark
    bottom, which is what makes it read as raised rather than painted on."""
    ph, pw = tile.shape[:2]
    _plate_ground(tile, TEAL)
    scale = max(2, min(pw // 5, ph // 7))
    w = text_width("6", scale)
    x0 = (pw - w) // 2 + scale
    y0 = (ph - 5 * scale) // 2
    draw_text(tile, "6", x0 + 1, y0 + 1, _dim(TEAL_D, 0.6), scale=scale)
    draw_text(tile, "6", x0, y0, BONE, scale=scale)
    draw_text(tile, "6", x0 - 1, y0 - 1, _dim(BONE, 1.15), scale=scale)


STATUS_LINES = [
    "LINE STATUS",
    "",
    "PORE CLAMP  P01 OK",
    "PORE CLAMP  P02 FAIL",
    "PORE CLAMP  P03 SEALED",
    "HONEYCOMB   H01 OK",
    "HONEYCOMB   H02 OK",
    "FLOW VALVE  V01 OK",
    "FLOW VALVE  V02 WARN",
    "VENT SEAL   X01 OK",
    "",
    "LAST UPDATE 14:37:22",
]


def _status_art(tile, isl, px_per_m):
    """The readout board. The lines are the sheet's own, and they name the pieces
    the other sheets build -- the facility is monitoring its own hardware, which
    is worth setting exactly rather than paraphrasing."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = DARK
            tile[y, x, 3] = 1.0
            if y % 3 == 0:                    # the scanline of a live screen
                tile[y, x, :3] = _dim(DARK, 1.5)
    top = 2
    ordered = list(reversed(STATUS_LINES))
    for i, line in enumerate(ordered):
        y = top + i * 6
        if y + 5 >= ph:
            break
        if not line:
            continue
        head = (line == STATUS_LINES[0] or line == STATUS_LINES[-1])
        col = GREEN if head else _dim(GREEN, 0.85)
        draw_text(tile, line, 2, y, col, emit=emit)
        if line == STATUS_LINES[0]:           # the rule under the heading
            for x in range(2, pw - 2):
                tile[y - 2, x, :3] = GREEN_D
                if emit is not None:
                    emit[y - 2, x] = GREEN_D


def _toll_projection_art(tile, isl, px_per_m):
    """The floor projection: light, not paint. It is drawn on its own alpha so the
    floor shows through wherever the projector is not throwing anything."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    tile[:, :, 3] = 0.0
    # the bracket corners the sheet frames it with
    for (sx, sy) in ((1, 1), (pw - 12, 1), (1, ph - 12), (pw - 12, ph - 12)):
        for k in range(10):
            for (px, py) in ((sx + k, sy), (sx, sy + k)):
                if 0 <= px < pw and 0 <= py < ph:
                    tile[py, px, :3] = GREEN
                    tile[py, px, 3] = 1.0
                    if emit is not None:
                        emit[py, px] = GREEN
    # CREDIT TOLL reads above the figure and SINGLE FILE below it, so with the
    # half-turn they are placed the other way up here
    draw_text(tile, "CREDIT TOLL", max(1, (pw - text_width("CREDIT TOLL")) // 2),
              int(ph * 0.80), GREEN, emit=emit)
    draw_text(tile, "SINGLE FILE", max(1, (pw - text_width("SINGLE FILE")) // 2),
              int(ph * 0.14), GREEN, emit=emit)
    # the walking figure, and the dashed lane it is told to keep to
    cx = pw // 2
    body = [(0, -6), (0, -5), (-1, -4), (0, -4), (1, -4), (0, -3), (0, -2),
            (-1, -1), (1, -1), (-1, 0), (1, 0)]
    cy = int(ph * 0.48)
    for (dx, dy) in body:
        px, py = cx + dx, cy + dy
        if 0 <= px < pw and 0 <= py < ph:
            tile[py, px, :3] = GREEN
            tile[py, px, 3] = 1.0
            if emit is not None:
                emit[py, px] = GREEN
    for side in (-1, 1):
        x = cx + side * int(pw * 0.22)
        for y in range(int(ph * 0.34), int(ph * 0.70), 4):
            for dy in range(2):
                if 0 <= y + dy < ph and 0 <= x < pw:
                    tile[y + dy, x, :3] = _dim(GREEN, 0.8)
                    tile[y + dy, x, 3] = 1.0
                    if emit is not None:
                        emit[y + dy, x] = _dim(GREEN, 0.8)


EMBLEMS = ("shield", "trefoil", "star", "flower")


def _emblem_art(tile, isl, px_per_m):
    """The four district emblems on one plate: a crowned shield, a trefoil of
    hexagons, a four-point star, and the smiling flower marked HPP. Four panels
    on one card, because they are always shown as a set."""
    ph, pw = tile.shape[:2]
    _plate_ground(tile, TEAL_D)
    cell = pw // 4
    for i, kind in enumerate(EMBLEMS):
        ox = i * cell
        for y in range(2, ph - 2):            # the panel divider
            tile[y, ox, :3] = _dim(TEAL_D, 0.65)
        cx, cy = ox + cell // 2, ph // 2
        rad = min(cell, ph) * 0.28
        for y in range(ph):
            for x in range(ox + 2, min(pw, ox + cell - 1)):
                dx, dy = (x - cx) / rad, (y - cy) / rad
                r = (dx * dx + dy * dy) ** 0.5
                a = math.atan2(dy, dx)
                on = False
                if kind == "shield":
                    on = abs(dx) < 0.72 and -0.9 < dy < 0.55 + 0.5 * (1 - abs(dx))
                    if dy < -0.75 and abs(dx) < 0.5:
                        on = True             # the crown
                elif kind == "trefoil":
                    for (hx, hy) in ((0.0, -0.42), (-0.38, 0.28), (0.38, 0.28)):
                        if max(abs(dx - hx) * 1.15, abs(dy - hy)) < 0.30:
                            on = True
                elif kind == "star":
                    on = r < 0.95 * abs(math.cos(a * 2.0)) ** 0.5
                else:
                    on = r < 0.34
                    for k in range(8):        # the petals
                        pa = math.tau * k / 8.0
                        if ((dx - math.cos(pa) * 0.52) ** 2
                                + (dy - math.sin(pa) * 0.52) ** 2) ** 0.5 < 0.26:
                            on = True
                if on:
                    tile[y, x, :3] = BONE if (x + y) % 5 else BONE_D
        if kind == "flower":
            draw_text(tile, "HPP", cx - text_width("HPP") // 2, 3, BONE_D)


PLACARDS = (
    ("NoLoitering", ["NO LOITERING", "NO SITTING", "NO RESTING"], (0.62, 0.34)),
    ("StandingOnly", ["STANDING ONLY", "BEYOND", "THIS POINT >"], (0.74, 0.42)),
    ("KeepAisleClear", ["KEEP AISLE", "CLEAR"], (0.52, 0.28)),
    ("ViolatorsCited", ["VIOLATORS", "WILL BE", "CITED"], (0.46, 0.32)),
)

ARTS = {}
for nm, lines, _sz in PLACARDS:
    ARTS[nm] = pl.register_card_art("sign_placard_" + nm, _placard_art(lines))
DESIG_ART = pl.register_card_art("sign_designator", _designator_art)
STATUS_ART = pl.register_card_art("sign_status_board", _status_art)
TOLL_ART = pl.register_card_art("sign_toll_projection", _toll_projection_art)
EMBLEM_ART = pl.register_card_art("sign_district_emblems", _emblem_art)

pl.register_parts({
    "sg_plate": {"rgb": TEAL_D},
    "sg_frame": {"rgb": TEAL},
    "sg_frame_l": {"rgb": TEAL_L},
    "sg_screen": {"rgb": DARK, "emit": GREEN},
    "sg_proj": {"rgb": GREEN, "emit": GREEN},
}, emit_strength={"sg_screen": 2.2, "sg_proj": 3.0})


def build_placards():
    """(1) The regulatory set, on one board so a level can hang them together."""
    b = Builder()
    x = 0.0
    for nm, _lines, (w, h) in PLACARDS:
        plate = ((x, 0.0, 0.0), (w, 0.05, h))
        b.box(*plate[:2], "sg_plate")
        b.face_card(plate[0], plate[1], (w * 0.96, h * 0.94), "sg_plate",
                    face='-Y', art=ARTS[nm])
        x += w + 0.12
    return b.finish("SignPlacards")


def build_sector_designator():
    """(2) The numeral plate."""
    b = Builder()
    plate = ((0.0, 0.0, 0.0), (0.62, 0.07, 0.92))
    b.box(*plate[:2], "sg_frame")
    b.face_card(plate[0], plate[1], (0.58, 0.88), "sg_frame", face='-Y',
                art=DESIG_ART)
    return b.finish("SignSectorDesignator")


def build_status_board():
    """(3) The readout, in its bolted frame."""
    b = Builder()
    b.box((0.0, 0.0, 0.0), (1.05, 0.09, 1.20), "sg_frame")
    screen = ((0.0, -0.03, 0.0), (0.90, 0.04, 1.02))
    b.box(*screen[:2], "sg_screen")
    b.face_card(screen[0], screen[1], (0.88, 1.00), "sg_screen", face='-Y',
                art=STATUS_ART)
    for sx in (-0.46, 0.46):
        for sz in (-0.54, 0.54):
            b.box((sx, -0.04, sz), (0.05, 0.04, 0.05), "sg_frame_l")
    return b.finish("SignStatusBoard")


def build_toll_projection():
    """(4) The projection on the floor. It lies FLAT and it is light, so it has
    no plate behind it -- a projection with a backing board is a poster."""
    b = Builder()
    b.card((0.0, 0.0, 0.0), (0.86, 1.15), "sg_proj", axis='Z', art=TOLL_ART)
    return b.finish("SignTollProjection")


def build_district_emblems():
    """(5) The four emblems on their run of panels."""
    b = Builder()
    plate = ((0.0, 0.0, 0.0), (1.36, 0.07, 0.44))
    b.box(*plate[:2], "sg_plate")
    b.face_card(plate[0], plate[1], (1.32, 0.40), "sg_plate", face='-Y',
                art=EMBLEM_ART)
    return b.finish("SignDistrictEmblems")


PIECES = []
for fn, px in ((build_placards, 128.0), (build_sector_designator, 96.0),
               (build_status_board, 128.0), (build_toll_projection, 128.0),
               (build_district_emblems, 128.0)):
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[SIGN] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 2.6

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "signage_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "signage_pieces.gltf"))
print("=== DONE: signage pieces -> %s ===" % OUT_DIR)
