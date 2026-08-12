# PROJECTION PIECES — everything the architecture sticks out over the street.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_projection_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/doors.png (its
# contents are projections, whatever the filename says) names seven — taut
# translucent veined membrane-awning, rust-streaked faceted metal slat-canopy,
# cantilevered balcony slab with post-rail, signage bracket-arm with hanging
# backlit sign, slanted anti-homeless no-stand ledge, small faceted curved
# entry-hood over a single door, and the large elevated tubular transit-viaduct
# carrying lit traffic along its top.
#
# Four of the seven hang off the SAME gothic bracket -- a triangle of circles in
# tracery. Drawing it once and reusing it is the point: it is what makes the set
# read as one building rather than seven props.
#
# What is modelled and what is drawn:
#   MODELLED  brackets, slabs, posts, the hood shell, the viaduct tube, the sign
#             plate. Silhouette is the read, and these are what cast it.
#   DRAWN     the bracket tracery, the awning membrane and its veins, the canopy
#             slats, the rail's circles, the sign's glyphs and backlight, the
#             hood's facets, the viaduct's window ring. Every one repeats.
#
# Cards are placed with Builder.face_card, which derives the offset from the box
# it dresses. Placing them by hand buried three of them inside their own geometry
# earlier in this sheet's sibling files.

import bpy
import importlib
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
AMBER = (0.882, 0.780, 0.451)


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _tracery_bracket_art(tile, isl, px_per_m):
    """The bracket four of these hang from: a triangle filled with a ring of
    circles in tracery, thinning as the bracket tapers away from the wall.

    Drawn once, used four times. The circles are the repetition and the triangle
    is the silhouette, so the triangle is the card's own alpha and the circles are
    pixels inside it."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0
    rings = []
    for k in range(6):
        t = k / 5.0
        rings.append((pw * (0.18 + 0.62 * t), ph * (0.78 - 0.58 * t),
                      max(2.0, pw * (0.15 - 0.075 * t))))
    for y in range(ph):
        for x in range(pw):
            # the bracket's own wedge: full at the wall, tapering outward
            if y > ph * (0.18 + 0.72 * (x / max(1.0, pw - 1.0))):
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = _dim(TEAL_L, 0.95)
            for (rx, ry, rr) in rings:
                d = ((x - rx) ** 2 + (y - ry) ** 2) ** 0.5
                if d < rr * 0.62:
                    tile[y, x, 3] = 0.0                 # the hole in the tracery
                elif d < rr:
                    tile[y, x, :3] = BONE_D             # its moulding
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 10 and tile[y, x, 3] > 0.0:
                tile[y, x, :3] = _dim(RUST, 0.9)


def _membrane_art(tile, isl, px_per_m):
    """The awning: taut lobes of translucent membrane with the veins between
    them, and the drips that have run off its edge."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 1.0
    cols, rows = 4, 2
    for y in range(ph):
        for x in range(pw):
            u = (x / max(1.0, pw - 1.0)) * cols
            v = (y / max(1.0, ph - 1.0)) * rows
            fu, fv = u - math.floor(u), v - math.floor(v)
            d = max(abs(fu - 0.5), abs(fv - 0.5)) * 2.0
            if d > 0.86:
                tile[y, x, :3] = BONE_D                 # the vein between lobes
            else:
                lit = 1.0 - 0.22 * d
                tile[y, x, :3] = _dim(BONE, lit)
    # the drips: they hang off the LAST row, which is the awning's outer edge
    for x in range(pw):
        h = ((x * 26699) ^ 0x5bd1) & 0xFF
        if h > 46:
            continue
        for y in range(ph - 1, max(0, ph - 2 - (h % 5)), -1):
            tile[y, x, :3] = _dim(RUST, 0.85)


def _slat_art(tile, isl, px_per_m):
    """The canopy's slats, rust running down the joints between them."""
    ph, pw = tile.shape[:2]
    pitch = max(3, int(0.16 * pw))
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            k = x % pitch
            base = TEAL if (x // pitch) % 3 else _dim(TEAL, 0.9)
            if k == 0:
                tile[y, x, :3] = _dim(TEAL_D, 0.8)
            elif k == 1:
                tile[y, x, :3] = TEAL_L
            else:
                tile[y, x, :3] = base
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 14:
                tile[y, x, :3] = _dim(RUST, 0.8 + 0.4 * (h / 14.0))


def _rail_art(tile, isl, px_per_m):
    """The post-rail: a run of rings between its posts, which is repetition and
    has holes, so it is a card and the holes are alpha."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0
    cy = (ph - 1) * 0.5
    rad = ph * 0.36
    count = max(3, int(pw / (rad * 2.1)))
    for y in range(ph):
        for x in range(pw):
            if y < ph * 0.14 or y > ph * 0.86:
                tile[y, x, 3] = 1.0                     # the top and bottom rails
                tile[y, x, :3] = TEAL_L
                continue
            for k in range(count):
                cxp = (k + 0.5) * (pw / float(count))
                d = ((x - cxp) ** 2 + (y - cy) ** 2) ** 0.5
                if rad * 0.72 < d < rad:
                    tile[y, x, 3] = 1.0
                    tile[y, x, :3] = TEAL if (x + y) % 3 else BONE_D


def _sign_art(tile, isl, px_per_m):
    """The hanging sign: a lit plate with glyphs on it. The glyphs are deliberately
    illegible -- this is a texture of writing, not a message, and inventing words
    for a world whose language nobody has written is worse than leaving it as
    light."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            edge = min(x, y, pw - 1 - x, ph - 1 - y)
            if edge < 2:
                tile[y, x, :3] = _dim(TEAL_D, 0.9)
                continue
            tile[y, x, :3] = _dim(AMBER, 0.55)
            if emit is not None:
                emit[y, x] = _dim(AMBER, 0.5)
    # a column of glyph blocks down the middle
    gx = pw * 0.5
    step = max(4, int(ph * 0.11))
    for row in range(2, ph - 4, step):
        for dy in range(min(step - 2, 4)):
            for dx in range(-int(pw * 0.22), int(pw * 0.22)):
                h = ((dx * 26699) ^ ((row + dy) * 92083)) & 0xFF
                if h > 150:
                    continue
                xx = int(gx + dx)
                if 2 <= xx < pw - 2 and row + dy < ph - 2:
                    tile[row + dy, xx, :3] = GREEN
                    if emit is not None:
                        emit[row + dy, xx] = GREEN


def _facet_art(tile, isl, px_per_m):
    """The entry hood's shell: faceted cells, paler where the light catches the
    crown of the curve."""
    ph, pw = tile.shape[:2]
    pitch = max(4, int(0.17 * pw))
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            row = y // pitch
            ox = (pitch * 0.5) if (row % 2) else 0.0
            cxp = (math.floor((x - ox) / pitch) + 0.5) * pitch + ox
            cyp = (row + 0.5) * pitch
            d = max(abs(x - cxp) / (pitch * 0.5), abs(y - cyp) / (pitch * 0.5))
            crown = 1.0 - abs((y / max(1.0, ph - 1.0)) - 0.3) * 0.5
            tile[y, x, :3] = (_dim(BONE_D, 0.9) if d > 0.84
                              else _dim(BONE, crown))


def _viaduct_art(tile, isl, px_per_m):
    """The viaduct's flank: a ring of lit ports with the traffic showing through
    them. The ports repeat the length of the span, so they are pixels."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    tile[:, :, 3] = 1.0
    cy = (ph - 1) * 0.5
    rad = ph * 0.33
    count = max(3, int(pw / (rad * 2.4)))
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = TEAL
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 12:
                tile[y, x, :3] = _dim(RUST, 0.85)
    for k in range(count):
        cxp = (k + 0.5) * (pw / float(count))
        for y in range(ph):
            for x in range(pw):
                d = ((x - cxp) ** 2 + (y - cy) ** 2) ** 0.5
                if d < rad * 0.74:
                    tile[y, x, :3] = _dim(AMBER, 0.95)
                    if emit is not None:
                        emit[y, x] = _dim(AMBER, 0.8)
                elif d < rad:
                    tile[y, x, :3] = BONE_D


BRACKET_ART = pl.register_card_art("proj_bracket_tracery", _tracery_bracket_art)
MEMB_ART = pl.register_card_art("proj_membrane", _membrane_art)
SLAT_ART = pl.register_card_art("proj_slats", _slat_art)
RAIL_ART = pl.register_card_art("proj_rail_rings", _rail_art)
SIGN_ART = pl.register_card_art("proj_sign", _sign_art)
FACET_ART = pl.register_card_art("proj_facets", _facet_art)
VIA_ART = pl.register_card_art("proj_viaduct_ports", _viaduct_art)

pl.register_parts({
    "pj_stone": {"rgb": TEAL},
    "pj_stone_d": {"rgb": TEAL_D},
    "pj_stone_l": {"rgb": TEAL_L},
    "pj_bracket": {"rgb": TEAL_L},
    "pj_memb": {"rgb": BONE},
    "pj_slat": {"rgb": TEAL},
    "pj_rail": {"rgb": TEAL_L},
    "pj_sign": {"rgb": _dim(AMBER, 0.55), "emit": _dim(AMBER, 0.5)},
    "pj_facet": {"rgb": BONE},
    "pj_via": {"rgb": TEAL, "emit": _dim(AMBER, 0.7)},
}, emit_strength={"pj_sign": 2.6, "pj_via": 2.0})

BRACKET = (0.62, 0.06, 0.62)      # the shared bracket's card size


def _bracket(b, x, z, flip=1.0):
    """One gothic bracket against the wall, carrying whatever projects."""
    b.card((x, 0.0, z), (BRACKET[0], BRACKET[2]), "pj_bracket", axis='Y',
           art=BRACKET_ART, rot=(0.0, 0.0, 0.0 if flip > 0 else math.pi))


def build_membrane_awning():
    """(1) A membrane stretched over two brackets, dripping off its lip."""
    b = Builder()
    for x in (-0.46, 0.46):
        _bracket(b, x, 0.0)
    slab = ((0.0, -0.34, 0.30), (1.24, 0.72, 0.05))
    b.box(*slab[:2], "pj_stone")
    b.face_card(slab[0], slab[1], (1.16, 0.66), "pj_memb", face='+Z',
                art=MEMB_ART)
    b.box((0.0, 0.0, 0.36), (1.32, 0.10, 0.09), "pj_stone_l")
    return b.finish("ProjMembraneAwning")


def build_slat_canopy():
    """(2) A sloping run of slats on its brackets."""
    b = Builder()
    for x in (-0.46, 0.46):
        _bracket(b, x, 0.0)
    slab = ((0.0, -0.32, 0.22), (1.20, 0.70, 0.06))
    b.box(*slab[:2], "pj_slat")
    b.face_card(slab[0], slab[1], (1.14, 0.64), "pj_slat", face='+Z', art=SLAT_ART)
    b.box((0.0, -0.66, 0.19), (1.24, 0.07, 0.10), "pj_stone_d")
    b.box((0.0, 0.0, 0.30), (1.30, 0.10, 0.09), "pj_stone_l")
    return b.finish("ProjSlatCanopy")


def build_balcony_slab():
    """(3) A cantilevered slab with the ring rail along its edge."""
    b = Builder()
    for x in (-0.5, 0.5):
        _bracket(b, x, -0.12)
    b.box((0.0, -0.36, 0.10), (1.30, 0.76, 0.09), "pj_stone")
    rail = ((0.0, -0.72, 0.30), (1.30, 0.05, 0.34))
    b.box(*rail[:2], "pj_rail")
    b.face_card(rail[0], rail[1], (1.26, 0.32), "pj_rail", face='-Y', art=RAIL_ART)
    for x in (-0.62, 0.0, 0.62):
        b.box((x, -0.72, 0.30), (0.07, 0.09, 0.36), "pj_stone_l")
    return b.finish("ProjBalconySlab")


def build_sign_bracket():
    """(4) The arm, and the lit sign hanging off it on its chains."""
    b = Builder()
    _bracket(b, 0.0, 0.30)
    b.box((0.26, -0.02, 0.56), (0.72, 0.09, 0.09), "pj_stone_l")
    for x in (0.10, 0.50):                       # the chains
        b.limb((x, -0.02, 0.52), (x, -0.02, 0.30), 0.012, 0.012, "pj_stone_d",
               sides=4)
    plate = ((0.30, -0.02, 0.04), (0.40, 0.05, 0.52))
    b.box(*plate[:2], "pj_sign")
    b.face_card(plate[0], plate[1], (0.36, 0.48), "pj_sign", face='-Y',
                art=SIGN_ART)
    return b.finish("ProjSignBracket")


def build_nostand_ledge():
    """(5) The anti-homeless ledge: a bracket carrying a slope too steep to sit
    on. It is dressed like everything else here, which is the point -- hostile
    architecture in this world is civic furniture, not an obvious trap."""
    b = Builder()
    _bracket(b, 0.0, 0.0)
    # the slope: a wide flat beam running from the wall DOWN and out, steep
    # enough that nothing rests on it. limb takes two points, so the angle is
    # stated rather than faked with a stack of boxes.
    for i in range(5):
        x = -0.34 + i * 0.17
        b.limb((x, -0.02, 0.38), (x, -0.46, 0.10), 0.055, 0.045, "pj_stone",
               sides=4)
    b.box((0.0, -0.02, 0.40), (0.92, 0.12, 0.07), "pj_stone_l")
    b.box((0.0, -0.48, 0.07), (0.92, 0.09, 0.06), "pj_stone_d")
    return b.finish("ProjNoStandLedge")


def build_entry_hood():
    """(6) A faceted hood curving out over a single door."""
    b = Builder()
    b.box((0.0, 0.0, 1.02), (0.86, 0.12, 2.04), "pj_stone")
    b.box((0.0, -0.10, 0.92), (0.60, 0.08, 1.72), "pj_stone_d")
    # THE HOOD IS THE CURVE. Each facet is a flat panel spanning the door's full
    # width, stepped around a quarter turn: out from the wall at the top, down at
    # the front. Six of them read as a curve and each one still catches its own
    # light, which is what "faceted" is for.
    steps = 6
    r = 0.44
    base_z = 1.84
    for i in range(steps):
        a0 = (math.pi * 0.5) * (i / steps)
        a1 = (math.pi * 0.5) * ((i + 1) / steps)
        y0, z0 = -math.sin(a0) * r, base_z + math.cos(a0) * r
        y1, z1 = -math.sin(a1) * r, base_z + math.cos(a1) * r
        my, mz = (y0 + y1) * 0.5, (z0 + z1) * 0.5
        seg = math.hypot(y1 - y0, z1 - z0)
        # the panel: thin along the arc, full width across the door
        b.box((0.0, my, mz), (0.92, max(0.05, abs(y1 - y0) + 0.05),
                              max(0.05, abs(z1 - z0) + 0.05)), "pj_facet")
    # the ribs that carry the facets, one down each side of the arc
    for sgn in (-1.0, 1.0):
        for i in range(steps):
            a0 = (math.pi * 0.5) * (i / steps)
            a1 = (math.pi * 0.5) * ((i + 1) / steps)
            b.limb((sgn * 0.47, -math.sin(a0) * r, base_z + math.cos(a0) * r),
                   (sgn * 0.47, -math.sin(a1) * r, base_z + math.cos(a1) * r),
                   0.05, 0.05, "pj_stone_l", sides=4)
    b.box((0.0, 0.0, 0.05), (1.02, 0.22, 0.10), "pj_stone_d")
    return b.finish("ProjEntryHood")


def build_transit_viaduct():
    """(7) The elevated conduit, on its pier, with the traffic lit inside."""
    b = Builder()
    b.ngon_prism((0, 0), 0.22, 0.34, 1.60, "pj_stone", sides=8, z0=0.0)
    for sgn in (-1.0, 1.0):
        b.limb((sgn * 0.12, 0.0, 1.55), (sgn * 0.52, 0.0, 2.02), 0.07, 0.05,
               "pj_stone_l", sides=5)
    tube = ((0.0, 0.0, 2.24), (2.30, 0.44, 0.44))
    b.box(*tube[:2], "pj_via")
    b.face_card(tube[0], tube[1], (2.24, 0.40), "pj_via", face='-Y', art=VIA_ART)
    b.box((0.0, 0.0, 2.50), (2.36, 0.50, 0.07), "pj_stone_l")
    b.box((0.0, 0.0, 1.98), (2.36, 0.50, 0.07), "pj_stone_d")
    return b.finish("ProjTransitViaduct")


PIECES = []
for fn, px in ((build_membrane_awning, 64.0), (build_slat_canopy, 64.0),
               (build_balcony_slab, 64.0), (build_sign_bracket, 96.0),
               (build_nostand_ledge, 64.0), (build_entry_hood, 64.0),
               (build_transit_viaduct, 48.0)):
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[PRJ] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 2.6

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "projection_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "projection_pieces.gltf"))
print("=== DONE: projection pieces -> %s ===" % OUT_DIR)
