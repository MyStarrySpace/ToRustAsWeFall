# COLUMN PIECES — what the architecture stands on.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_column_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/columns.png names
# six — branching tree-column, mushroom-canopy column, waisted load pier,
# clustered buttress-fin, vine-ribs wall webbing, open strut-truss elevated
# conduit.
#
# All six share one surface: a cell-patterned masonry that covers every shaft.
# That is a DETAIL PAINTER on the faces rather than a card, because it dresses a
# solid the way the Crust's pore array dresses its plate — a card would have to
# float in front of the shaft and would peel at every corner.
#
# What is modelled and what is drawn:
#   MODELLED  plinths, shafts, caps, the Y-branches, the fins, the conduit tube.
#             These hold the load, and the silhouette is the whole read.
#   DRAWN     the cell masonry, the canopy's webbing, the vine ribs, the arcade
#             of little arches crowning the tree-column, the conduit's panes.
#             Every one of those is a form that repeats tens of times.
#
# Outputs, committed and game-ready:
#   to-rust-as-we-fall/resources/models/architecture/column_pieces.gltf

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
LEAF = (0.427, 0.541, 0.325)

H = 3.2                    # a standard column, floor to cap
SHAFT_R = 0.24
PLINTH = 0.52


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _cell_masonry(tile, mask, base, isl, px_per_m):
    """The surface every shaft on the sheet wears: a lattice of cells with pale
    ribs between them and rust bleeding out of the joints.

    A detail painter, not a card. This dresses a SOLID -- a card carrying it would
    have to hover in front of the shaft and would peel off at every corner and
    every taper. The Crust's pore array is dressed the same way, for the reason."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    rib = _dim(BONE, 0.94)
    rib_d = _dim(BONE_D, 0.88)
    pitch = max(5, int(0.34 * px_per_m))
    for y in range(ph):
        for x in range(pw):
            # hex-ish cells: offset every other row, then measure to the nearest
            # cell centre and call the space between two of them a rib
            row = y // pitch
            ox = (pitch * 0.5) if (row % 2) else 0.0
            cxp = (math.floor((x - ox) / pitch) + 0.5) * pitch + ox
            cyp = (row + 0.5) * pitch
            d = max(abs(x - cxp) / (pitch * 0.5), abs(y - cyp) / (pitch * 0.5))
            if d > 0.86:
                tile[y, x] = rib if ((x + y) % 3) else rib_d
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 9:                                   # rust out of the joints
                tile[y, x] = _dim(RUST, 0.85 + 0.3 * (h / 9.0))


CELL = pl.register_detail("column_cell_masonry", _cell_masonry)


def _webbing_art(tile, isl, px_per_m):
    """The canopy's underside: a cellular web thinning outward from the stem, the
    way the sheet draws the mushroom column's ribs spreading into its disc."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 0.0
    seeds = []
    for ring, count in ((0.38, 7), (0.72, 13)):
        for k in range(count):
            a = math.tau * k / count + ring
            seeds.append((cx + math.cos(a) * rad * ring, cy + math.sin(a) * rad * ring))
    seeds.append((cx, cy))
    for y in range(ph):
        for x in range(pw):
            dx, dy = x - cx, y - cy
            r = (dx * dx + dy * dy) ** 0.5 / rad
            if r > 1.0:
                continue
            best = second = 1e9
            for (sx, sy) in seeds:
                d = (x - sx) ** 2 + (y - sy) ** 2
                if d < best:
                    best, second = d, best
                elif d < second:
                    second = d
            gap = second ** 0.5 - best ** 0.5
            if gap < max(1.6, rad * 0.055) or r < 0.14:
                tile[y, x, 3] = 1.0
                tile[y, x, :3] = BONE if gap < rad * 0.03 else BONE_D


def _vine_rib_art(tile, isl, px_per_m):
    """The wall webbing: ribs branching over the panel with leaf breaking out of
    them. Both the ribs and the leaf repeat across metres of wall, so both are
    pixels."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 0.0

    def draw(x, y, ang, life, width):
        for _ in range(life):
            x += math.cos(ang)
            y += math.sin(ang)
            if not (0 <= x < pw and 0 <= y < ph):
                return
            ang += math.sin((x + y) * 0.11) * 0.09
            for w in range(-width, width + 1):
                xx = int(x + w)
                if 0 <= xx < pw:
                    tile[int(y), xx, 3] = 1.0
                    tile[int(y), xx, :3] = BONE if abs(w) < width else BONE_D
            h = (int(x) * 26699) ^ (int(y) * 92083)
            if (h & 0xFF) < 4 and life > 30:
                draw(x, y, ang + (0.7 if (h & 0x100) else -0.7), life // 2,
                     max(0, width - 1))
            if (h & 0xFF00) >> 8 < 6:                # leaf off the rib
                ly, lx = int(y), int(x + (2 if (h & 1) else -2))
                if 0 <= lx < pw:
                    tile[ly, lx, 3] = 1.0
                    tile[ly, lx, :3] = LEAF

    for k in range(3):
        draw(pw * (0.2 + 0.3 * k), 0.0, math.pi * 0.5 + (k - 1) * 0.16,
             int(ph * 1.1), 2)


def _pane_art(tile, isl, px_per_m):
    """The conduit's glazing: hexagonal panes in their leading, the same cell the
    honeycomb window uses because it is the same building."""
    ph, pw = tile.shape[:2]
    pitch = max(5, int(0.28 * px_per_m))
    for y in range(ph):
        for x in range(pw):
            row = y // pitch
            ox = (pitch * 0.5) if (row % 2) else 0.0
            cxp = (math.floor((x - ox) / pitch) + 0.5) * pitch + ox
            cyp = (row + 0.5) * pitch
            d = max(abs(x - cxp) / (pitch * 0.5), abs(y - cyp) / (pitch * 0.5))
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = _dim(BONE, 0.8) if d > 0.82 else (0.686, 0.741, 0.612)


WEB_ART = pl.register_card_art("column_canopy_web", _webbing_art)
VINE_ART = pl.register_card_art("column_vine_ribs", _vine_rib_art)
PANE_ART = pl.register_card_art("column_conduit_panes", _pane_art)

pl.register_parts({
    "cl_shaft": {"rgb": TEAL},
    "cl_rib": {"rgb": BONE_D},
    "cl_cap": {"rgb": TEAL_L},
    "cl_plinth": {"rgb": TEAL_D},
    "cl_web": {"rgb": BONE},
    "cl_pane": {"rgb": (0.686, 0.741, 0.612)},
})


def _plinth(b, w=PLINTH):
    b.box((0, 0, 0.09), (w, w, 0.18), "cl_plinth")
    b.box((0, 0, 0.22), (w * 0.86, w * 0.86, 0.09), "cl_cap")


def build_tree_column():
    """(1) A shaft that splits into branches and carries an open arcade."""
    b = Builder()
    _plinth(b)
    b.ngon_prism((0, 0), SHAFT_R * 0.82, SHAFT_R, H * 0.42, "cl_shaft", sides=8,
                 z0=0.26, detail=CELL)
    # the branches: two pairs leaning out and back in, which is the sheet's Y
    for sgn in (-1.0, 1.0):
        b.limb((sgn * SHAFT_R * 0.4, 0, H * 0.42 + 0.26),
               (sgn * SHAFT_R * 1.7, 0, H * 0.70), 0.075, 0.055, "cl_rib", sides=6)
        b.limb((sgn * SHAFT_R * 1.7, 0, H * 0.70),
               (sgn * SHAFT_R * 0.9, 0, H * 0.88), 0.055, 0.05, "cl_rib", sides=6)
        b.limb((sgn * SHAFT_R * 0.4, 0, H * 0.42 + 0.26),
               (sgn * SHAFT_R * 0.5, 0, H * 0.88), 0.05, 0.045, "cl_rib", sides=6)
    # the crowning arcade: a ring of little piers under a rim
    for k in range(10):
        a = math.tau * k / 10.0
        b.box((math.cos(a) * SHAFT_R * 1.5, math.sin(a) * SHAFT_R * 1.5, H * 0.95),
              (0.055, 0.055, H * 0.13), "cl_rib")
    b.annulus((0, 0, H * 1.02), SHAFT_R * 1.75, SHAFT_R * 1.45, 0.09,
              "cl_cap", sides=20)
    return b.finish("ColumnTree")


def build_mushroom_column():
    """(2) A waisted shaft flaring into the canopy, webbed underneath."""
    b = Builder()
    _plinth(b)
    steps = 7
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        r0 = SHAFT_R * (1.0 - 0.45 * math.sin(t0 * math.pi * 0.85))
        r1 = SHAFT_R * (1.0 - 0.45 * math.sin(t1 * math.pi * 0.85))
        b.ngon_prism((0, 0), r1, r0, (H * 0.72) / steps, "cl_shaft", sides=10,
                     z0=0.26 + t0 * H * 0.72, cap_top=False, cap_bottom=(i == 0),
                     detail=CELL)
    b.ngon_prism((0, 0), SHAFT_R * 2.5, SHAFT_R * 0.62, H * 0.14, "cl_shaft",
                 sides=14, z0=0.26 + H * 0.72, detail=CELL)
    b.ngon_prism((0, 0), SHAFT_R * 2.6, SHAFT_R * 2.5, 0.07, "cl_cap", sides=14,
                 z0=0.26 + H * 0.86)
    # the webbing UNDER the flare, facing down at whoever walks beneath it
    b.card((0, 0, 0.26 + H * 0.72 - 0.025), (SHAFT_R * 4.7, SHAFT_R * 4.7),
           "cl_web", axis='Z', art=WEB_ART, flip=True)
    return b.finish("ColumnMushroom")


def build_load_pier():
    """(3) The plain one: a waisted pier under a square cap."""
    b = Builder()
    _plinth(b, PLINTH * 1.05)
    steps = 6
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        r0 = SHAFT_R * (1.0 - 0.22 * math.sin(t0 * math.pi))
        r1 = SHAFT_R * (1.0 - 0.22 * math.sin(t1 * math.pi))
        b.ngon_prism((0, 0), r1, r0, (H * 0.80) / steps, "cl_shaft", sides=8,
                     z0=0.26 + t0 * H * 0.80, cap_top=False, cap_bottom=(i == 0),
                     detail=CELL)
    b.box((0, 0, 0.26 + H * 0.83), (PLINTH * 0.98, PLINTH * 0.98, 0.11), "cl_cap")
    b.box((0, 0, 0.26 + H * 0.89), (PLINTH * 0.82, PLINTH * 0.82, 0.07), "cl_shaft")
    return b.finish("ColumnLoadPier")


def build_buttress_fin():
    """(4) A cluster of fins, the tall middle one flanked by shorter pairs."""
    b = Builder()
    _plinth(b, PLINTH * 1.2)
    fins = ((0.0, 1.0, 0.10), (-0.20, 0.78, 0.075), (0.20, 0.78, 0.075),
            (-0.34, 0.58, 0.06), (0.34, 0.58, 0.06))
    for (x, hh, w) in fins:
        top = 0.26 + H * 0.86 * hh
        b.box((x, 0, (0.26 + top) * 0.5), (w * 2.0, 0.16, top - 0.26), "cl_shaft",
              detail=CELL)
        b.limb((x, 0, top), (x, 0, top + 0.20), w, 0.012, "cl_rib", sides=5)
    return b.finish("ColumnButtressFin")


def build_vine_wall():
    """(5) A wall panel under its webbing of ribs."""
    b = Builder()
    b.box((0, 0, H * 0.45), (1.15, 0.16, H * 0.90), "cl_shaft", detail=CELL)
    b.card((0, -0.09, H * 0.45), (1.10, H * 0.88), "cl_web", axis='Y', art=VINE_ART)
    b.box((0, 0, 0.06), (1.28, 0.22, 0.12), "cl_plinth")
    b.box((0, 0, H * 0.92), (1.28, 0.22, 0.10), "cl_cap")
    return b.finish("ColumnVineWall")


def build_strut_conduit():
    """(6) A Y-strut carrying the glazed conduit overhead."""
    b = Builder()
    _plinth(b)
    b.ngon_prism((0, 0), SHAFT_R * 0.7, SHAFT_R * 0.95, H * 0.44, "cl_shaft",
                 sides=8, z0=0.26, detail=CELL)
    for sgn in (-1.0, 1.0):
        b.limb((sgn * SHAFT_R * 0.3, 0, 0.26 + H * 0.44),
               (sgn * SHAFT_R * 2.1, 0, 0.26 + H * 0.68), 0.075, 0.055,
               "cl_rib", sides=6)
    b.box((0, 0, 0.26 + H * 0.70), (SHAFT_R * 4.6, 0.22, 0.09), "cl_cap")
    # the conduit itself, lying across the strut
    # the conduit lies ACROSS the strut, so it is built upright then laid down
    b.limb((-SHAFT_R * 2.2, 0.0, 0.26 + H * 0.78),
           (SHAFT_R * 2.2, 0.0, 0.26 + H * 0.78),
           SHAFT_R * 1.15, SHAFT_R * 1.15, "cl_pane", sides=12)
    return b.finish("ColumnStrutConduit")


PIECES = []
for fn, px in ((build_tree_column, 32.0), (build_mushroom_column, 32.0),
               (build_load_pier, 32.0), (build_buttress_fin, 32.0),
               (build_vine_wall, 48.0), (build_strut_conduit, 32.0)):
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[COL] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 2.4

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "column_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "column_pieces.gltf"))
print("=== DONE: column pieces -> %s ===" % OUT_DIR)
