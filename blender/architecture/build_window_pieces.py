# WINDOW PIECES — the apertures the procedural architecture punches into its walls.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_window_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/windows.png names
# seven — membrane-pore, capillary-slit pair, balcony-bay, drawer-window band,
# rolling shutter, honeycomb cell, rose aperture + vent. This file starts with the
# rose aperture and its vent, because they are the pair that decides whether the
# grammar is right: almost everything about a rose window is REPETITION, and if
# the repetition is drawn rather than modelled the rest of the sheet follows.
#
# What is modelled and what is drawn, per the alpha-card law:
#   MODELLED   the frame ring, the sill, the hub, the vent's rim and hub. These
#              hold the form and catch the light, and there are few of them.
#   DRAWN      the radial tracery and the glazing between it, the vent's louvres.
#              A rose window has twenty-odd spokes; modelled they alias into a
#              grey smear at the distance a facade is read from, and drawn they
#              stay crisp. The pane is one card wearing the whole rose.
#
# Outputs, committed and game-ready:
#   to-rust-as-we-fall/resources/models/architecture/window_pieces.gltf
#
# HAND-PAINTING: drop <Piece>_tex.png into blender/architecture/painted/ and it
# wins on the next build, the round-trip every paintable area uses.

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

SRC = os.path.join(BL, "architecture")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "architecture")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

# The sheet's palette is the facility's own verdigris metal going to ferric red,
# with bone-pale glazing behind it.
TEAL = (0.286, 0.376, 0.376)
TEAL_D = (0.196, 0.267, 0.271)
TEAL_L = (0.376, 0.475, 0.463)
BONE = (0.812, 0.796, 0.714)
BONE_D = (0.596, 0.584, 0.514)
RUST = (0.463, 0.243, 0.129)
BRASS = (0.510, 0.427, 0.271)
DARK = (0.075, 0.082, 0.086)

ROSE_R = 0.62              # the aperture's outer radius
ROSE_SPOKES = 16           # the sheet counts about sixteen radiating bars
VENT_R = 0.26
VENT_BLADES = 8


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _rose_pane_art(tile, isl, px_per_m):
    """The whole rose, drawn: radial tracery over pale glazing, an inner ring of
    lobes, and a hub. Sixteen spokes and their cusps are repetition, and the card
    is where repetition belongs -- modelled, this many bars smear into grey at the
    distance a facade is read from, and each one costs geometry to look worse."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / rad, (y - cy) / rad
            r = (dx * dx + dy * dy) ** 0.5
            if r > 1.0:
                continue
            a = math.atan2(dy, dx)
            tile[y, x, 3] = 1.0
            # the glazing behind everything, lighter toward the middle
            glass = BONE if r < 0.62 else _dim(BONE, 0.92)
            tile[y, x, :3] = glass
            # the spokes
            spoke = abs(math.cos(a * ROSE_SPOKES * 0.5))
            if spoke > 0.955 and r > 0.16:
                tile[y, x, :3] = BRASS if (x + y) % 3 else _dim(BRASS, 0.8)
            # two concentric bands the tracery hangs off
            for band in (0.42, 0.78):
                if abs(r - band) < 0.035:
                    tile[y, x, :3] = _dim(BRASS, 0.86)
            # the lobed inner ring: petals between every other spoke
            if 0.2 < r < 0.42:
                lobe = math.cos(a * ROSE_SPOKES * 0.25)
                if abs(lobe) > 0.86:
                    tile[y, x, :3] = _dim(BRASS, 0.94)
            if r < 0.13:                      # the hub
                tile[y, x, :3] = _dim(BRASS, 1.06) if r < 0.09 else _dim(BRASS, 0.78)
            if r > 0.965:                     # seated into its frame
                tile[y, x, :3] = _dim(BRASS, 0.6)


def _vent_louvre_art(tile, isl, px_per_m):
    """The vent's blades. The sheet draws a small wheel of them with the dark
    behind showing through, so the gaps are ALPHA -- a vent you cannot see into
    is a plate."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / rad, (y - cy) / rad
            r = (dx * dx + dy * dy) ** 0.5
            if r > 1.0:
                continue
            a = math.atan2(dy, dx) + r * 0.9          # swept, so the blades curve
            blade = abs(math.cos(a * VENT_BLADES * 0.5))
            if r < 0.18:
                tile[y, x, :3] = _dim(BRASS, 0.95)
                tile[y, x, 3] = 1.0
            elif blade > 0.55 or r > 0.9:
                tile[y, x, :3] = BRASS if blade > 0.8 else _dim(BRASS, 0.76)
                tile[y, x, 3] = 1.0


ROSE_ART = pl.register_card_art("window_rose_pane", _rose_pane_art)
VENT_ART = pl.register_card_art("window_vent_louvres", _vent_louvre_art)

pl.register_parts({
    "wn_frame": {"rgb": TEAL},
    "wn_frame_d": {"rgb": TEAL_D},
    "wn_frame_l": {"rgb": TEAL_L},
    "wn_sill": {"rgb": _dim(TEAL_D, 0.9)},
    "wn_rose": {"rgb": BONE},
    "wn_vent": {"rgb": BRASS},
    "wn_drip": {"rgb": RUST},
    "wn_shutter": {"rgb": _dim(BRASS, 0.62)},
})


def build_rose_aperture():
    """A circular aperture: a stepped frame ring, the drawn rose seated in it, a
    keystone at the crown and the sill it sits on."""
    b = Builder()
    # An aperture stands IN a wall, so everything here is built upright in the XZ
    # plane facing -Y, which is the frame annulus() already works in.
    # Two rings, so the reveal has visible depth rather than reading as a decal.
    b.annulus((0, 0, 0), ROSE_R, ROSE_R * 0.90, 0.12, "wn_frame", sides=28)
    b.annulus((0, -0.05, 0), ROSE_R * 0.94, ROSE_R * 0.84, 0.06, "wn_frame_l",
              sides=28)
    b.annulus((0, 0.03, 0), ROSE_R * 1.07, ROSE_R * 0.99, 0.08, "wn_frame_d",
              sides=28)
    # the pane: ONE card carrying the entire rose
    b.card((0, 0.02, 0), (ROSE_R * 1.82, ROSE_R * 1.82), "wn_rose", axis='Y',
           art=ROSE_ART)
    # the keystone at the crown, and the sill it sits on
    b.box((0.0, 0.0, ROSE_R * 1.04), (0.17, 0.15, 0.14), "wn_frame_l")
    b.box((0.0, 0.0, -ROSE_R * 1.06), (ROSE_R * 1.5, 0.15, 0.11), "wn_sill")
    b.box((0.0, 0.02, -ROSE_R * 1.14), (ROSE_R * 1.64, 0.10, 0.06), "wn_frame_d")
    return b.finish("WindowRoseAperture")


def build_rose_vent():
    """The little vent that rides beside the rose: a rim, drawn louvres, and the
    rust that has run out of it down the wall."""
    b = Builder()
    b.annulus((0, 0, 0), VENT_R, VENT_R * 0.82, 0.09, "wn_vent", sides=20)
    b.card((0, 0.02, 0), (VENT_R * 1.66, VENT_R * 1.66), "wn_vent", axis='Y',
           art=VENT_ART)
    # the drip the sheet paints under it: a vent is where a wall gets stained
    b.box((0.0, 0.03, -VENT_R * 1.4), (VENT_R * 0.5, 0.03, VENT_R * 0.9),
          "wn_drip")
    return b.finish("WindowRoseVent")


# ---------------------------------------------------------------- the other six
# Each is the same split: what holds the form is modelled, what repeats is drawn.
# The sheet is generous with repetition -- membrane lobes, capillary glazing,
# gothic tracery, shutter corrugation, honeycomb panes, a bank of drawer fronts --
# and every one of those is a card.

MEMBRANE_R = 0.44
SLIT_H = 1.05
BAY_W, BAY_H = 0.62, 1.15
BAND_W, BAND_H = 1.15, 0.78
SHUTTER_W, SHUTTER_H = 0.66, 1.20
COMB_R = 0.42


def _membrane_art(tile, isl, px_per_m):
    """The pore's pane: fat pale lobes packed inside a rim, divided by the dark
    webbing between them. It is a cell seen down a lens, which is why the lobes
    are round and crowded rather than laid out on a grid."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 0.0
    lobes = []
    for k in range(6):
        a = math.tau * k / 6.0 + 0.35
        lobes.append((math.cos(a) * rad * 0.46, math.sin(a) * rad * 0.46, rad * 0.30))
    lobes.append((0.0, 0.0, rad * 0.26))
    for y in range(ph):
        for x in range(pw):
            dx, dy = x - cx, y - cy
            r = (dx * dx + dy * dy) ** 0.5 / rad
            if r > 1.0:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = _dim(BONE_D, 0.62)         # the webbing behind
            for (lx, ly, lr) in lobes:
                d = ((dx - lx) ** 2 + (dy - ly) ** 2) ** 0.5
                if d < lr:
                    lit = 1.0 - (d / lr) * 0.32
                    tile[y, x, :3] = _dim(BONE, lit)
                    break
            if r > 0.93:
                tile[y, x, :3] = _dim(BRASS, 0.8)


def _slit_art(tile, isl, px_per_m):
    """One capillary slit: a tall pale channel with the vessel banding across it,
    narrowing at both ends the way a capillary does."""
    ph, pw = tile.shape[:2]
    cx = (pw - 1) * 0.5
    tile[:, :, 3] = 0.0
    for y in range(ph):
        t = y / max(1.0, ph - 1.0)
        half = cx * (0.30 + 0.70 * math.sin(math.pi * min(1.0, max(0.0, t))) ** 0.6)
        for x in range(pw):
            if abs(x - cx) > half:
                continue
            tile[y, x, 3] = 1.0
            edge = abs(x - cx) / max(0.6, half)
            col = BONE if edge < 0.72 else _dim(BONE_D, 0.9)
            if (y % max(3, int(0.09 * ph))) == 0:        # the banding
                col = _dim(BRASS, 0.86)
            tile[y, x, :3] = col


def _tracery_art(tile, isl, px_per_m):
    """The gothic head both the bay and the shutter wear: a pointed arch with
    cusped lights under it. Drawn, because tracery is the definition of a form
    that repeats and would cost a hundred bars to model badly."""
    ph, pw = tile.shape[:2]
    cx = (pw - 1) * 0.5
    tile[:, :, 3] = 0.0
    rib = max(1.5, pw * 0.055)                    # the mouldings, drawn BOLD
    for y in range(ph):
        # row 0 is the SILL end of the card and the last row is the crown, so the
        # arch has to narrow as y rises
        t = y / max(1.0, ph - 1.0)
        half = cx * math.sqrt(max(0.0, 1.0 - t * t))   # a true arch, not a wedge
        if half < 0.8:
            continue
        for x in range(pw):
            d = abs(x - cx)
            if d > half:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = _dim(BONE, 0.96)          # the light behind it
            if d > half - rib:                          # the arch itself
                tile[y, x, :3] = _dim(BRASS, 0.82)
        if t < 0.62:                                   # three lights under the head
            for k in (-1, 0, 1):
                mx = cx + k * (half * 0.62)
                for xx in range(int(mx - rib * 0.5), int(mx + rib * 0.5) + 1):
                    if 0 <= xx < pw and tile[y, xx, 3] > 0.0:
                        tile[y, xx, :3] = _dim(BRASS, 0.82)
        if 0.62 <= t < 0.72:                           # the springing course
            for xx in range(pw):
                if tile[y, xx, 3] > 0.0:
                    tile[y, xx, :3] = _dim(BRASS, 0.7)


def _corrugation_art(tile, isl, px_per_m):
    """A rolling shutter: horizontal slats all the way down, rusted where the
    water runs. Slats are repetition and belong on the card; the surround they
    roll inside is what gets modelled."""
    ph, pw = tile.shape[:2]
    pitch = max(3, int(0.05 * ph))
    for y in range(ph):
        k = y % pitch
        base = RUST if (y // pitch) % 5 == 0 else _dim(BRASS, 0.62)
        for x in range(pw):
            tile[y, x, 3] = 1.0
            if k == 0:
                tile[y, x, :3] = _dim(base, 0.55)         # the shadow line
            elif k == 1:
                tile[y, x, :3] = _dim(base, 1.22)         # the crest
            else:
                h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
                tile[y, x, :3] = base if h > 40 else _dim(base, 0.86)


def _drawer_art(tile, isl, px_per_m):
    """The drawer band: fronts with their pull handles, and the terminal strip
    between them. The green is the project's own readout green, and the text is
    illegible on purpose -- it is a texture of information, not a message."""
    ph, pw = tile.shape[:2]
    green = (0.361, 0.910, 0.498)
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = TEAL
    band_lo, band_hi = int(ph * 0.40), int(ph * 0.62)
    for y in range(ph):
        for x in range(pw):
            if band_lo <= y < band_hi:
                tile[y, x, :3] = DARK
                # rows of illegible readout
                if (y - band_lo) % 4 in (1, 2) and (x // 2 + y) % 7 > 2 and x % 11 < 7:
                    tile[y, x, :3] = green
                continue
            row = 0 if y < band_lo else 1
            col = int(x / (pw / 3.0))
            # the seam around each drawer front
            fx = x - col * (pw / 3.0)
            fy = y if row == 0 else y - band_hi
            fh = band_lo if row == 0 else ph - band_hi
            if fx < 2 or fx > (pw / 3.0) - 3 or fy < 2 or fy > fh - 3:
                tile[y, x, :3] = TEAL_D
            elif abs(fy - fh * 0.5) < 1.6 and abs(fx - (pw / 6.0)) < pw / 22.0:
                tile[y, x, :3] = _dim(BRASS, 1.05)        # the pull handle
            h = ((x * 26699) ^ (y * 92083)) & 0xFF
            if h < 12:
                tile[y, x, :3] = _dim(RUST, 0.9)


def _honeycomb_art(tile, isl, px_per_m):
    """Hexagonal panes in their leading. Same law as the rose: the cells repeat,
    so they are pixels rather than a hundred little frames."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    cell = rad * 0.42
    centres = []
    row = -4
    while row <= 4:
        col = -4
        while col <= 4:
            ox = (cell * 0.5) if (row % 2) else 0.0
            centres.append((cx + col * cell + ox, cy + row * cell * 0.866))
            col += 1
        row += 1
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx), (y - cy)
            if (dx * dx + dy * dy) ** 0.5 > rad:
                continue
            best = second = 1e9
            for (sx, sy) in centres:
                d = (x - sx) ** 2 + (y - sy) ** 2
                if d < best:
                    best, second = d, best
                elif d < second:
                    second = d
            tile[y, x, 3] = 1.0
            gap = second ** 0.5 - best ** 0.5
            lead = max(1.4, rad * 0.045)
            tile[y, x, :3] = _dim(BRASS, 0.8) if gap < lead else _dim(BONE, 0.98)


MEMBRANE_ART = pl.register_card_art("window_membrane", _membrane_art)
SLIT_ART = pl.register_card_art("window_capillary_slit", _slit_art)
TRACERY_ART = pl.register_card_art("window_tracery", _tracery_art)
SHUTTER_ART = pl.register_card_art("window_shutter", _corrugation_art)
DRAWER_ART = pl.register_card_art("window_drawer_band", _drawer_art)
COMB_ART = pl.register_card_art("window_honeycomb", _honeycomb_art)


def build_membrane_pore():
    """(1) An oval port studded round its rim, with the lobed membrane inside."""
    b = Builder()
    b.annulus((0, 0, 0), MEMBRANE_R, MEMBRANE_R * 0.86, 0.12, "wn_frame", sides=22)
    b.card((0, 0.02, 0), (MEMBRANE_R * 1.72, MEMBRANE_R * 1.72), "wn_rose",
           axis='Y', art=MEMBRANE_ART)
    for k in range(10):                       # the studs the sheet rings it with
        a = math.tau * k / 10.0 + 0.2
        b.box((math.cos(a) * MEMBRANE_R * 1.02, 0.0, math.sin(a) * MEMBRANE_R * 1.02),
              (0.05, 0.09, 0.05), "wn_frame_l")
    return b.finish("WindowMembranePore")


def build_capillary_slits():
    """(2) Two tall slits on the forked stem that carries them."""
    b = Builder()
    for sgn in (-1.0, 1.0):
        x = sgn * 0.13
        b.box((x, 0.0, 0.10), (0.17, 0.11, SLIT_H), "wn_frame")
        b.card((x, -0.062, 0.10), (0.11, SLIT_H * 0.86), "wn_rose", axis='Y',
               art=SLIT_ART)
    # the fork: the two slits run down into one stem and a footing
    b.box((0.0, 0.0, -SLIT_H * 0.46), (0.30, 0.12, 0.22), "wn_frame_d")
    b.box((0.0, 0.0, -SLIT_H * 0.62), (0.40, 0.14, 0.12), "wn_sill")
    return b.finish("WindowCapillarySlits")


def build_balcony_bay():
    """(3) An arched bay with its tracery head, on the planter balcony the sheet
    hangs under it."""
    b = Builder()
    b.box((0.0, 0.0, 0.0), (BAY_W, 0.13, BAY_H), "wn_frame")
    b.card((0.0, -0.072, BAY_H * 0.22), (BAY_W * 0.82, BAY_H * 0.62), "wn_rose",
           axis='Y', art=TRACERY_ART)
    for sgn in (-1.0, 1.0):                   # the jambs
        b.box((sgn * BAY_W * 0.47, 0.01, 0.0), (0.09, 0.15, BAY_H), "wn_frame_l")
    # the balcony: a bowl on corbels, which is what the bay actually sits on
    b.ngon_prism((0.0, 0.0), BAY_W * 0.56, BAY_W * 0.44, 0.22, "wn_sill", sides=12,
                 z0=-BAY_H * 0.5 - 0.22)
    for k in range(5):
        a = math.pi * (0.15 + 0.175 * k)
        b.box((math.cos(a) * BAY_W * 0.42, math.sin(a) * 0.10,
               -BAY_H * 0.5 - 0.30), (0.07, 0.07, 0.16), "wn_frame_d")
    return b.finish("WindowBalconyBay")


def build_drawer_band():
    """(4) A bank of drawer fronts with the terminal strip through the middle."""
    b = Builder()
    b.box((0.0, 0.0, 0.0), (BAND_W, 0.16, BAND_H), "wn_frame")
    b.card((0.0, -0.086, 0.0), (BAND_W * 0.94, BAND_H * 0.92), "wn_rose", axis='Y',
           art=DRAWER_ART)
    b.box((0.0, 0.02, BAND_H * 0.54), (BAND_W * 1.04, 0.18, 0.07), "wn_frame_l")
    b.box((0.0, 0.02, -BAND_H * 0.54), (BAND_W * 1.04, 0.18, 0.07), "wn_sill")
    return b.finish("WindowDrawerBand")


def build_rolling_shutter():
    """(5) The shutter, part rolled down inside its arched surround."""
    b = Builder()
    b.box((0.0, 0.0, 0.0), (SHUTTER_W, 0.14, SHUTTER_H), "wn_frame")
    # the slats, drawn, stopping short so the opening under them reads
    b.card((0.0, -0.076, SHUTTER_H * 0.12), (SHUTTER_W * 0.80, SHUTTER_H * 0.66),
           "wn_shutter", axis='Y', art=SHUTTER_ART)
    b.card((0.0, -0.082, SHUTTER_H * 0.40), (SHUTTER_W * 0.78, SHUTTER_H * 0.26),
           "wn_rose", axis='Y', art=TRACERY_ART)
    b.box((0.0, 0.05, -SHUTTER_H * 0.19), (SHUTTER_W * 0.34, 0.06, 0.05),
          "wn_frame_l")                        # the pull rail
    for sgn in (-1.0, 1.0):
        b.box((sgn * SHUTTER_W * 0.46, 0.01, 0.0), (0.08, 0.16, SHUTTER_H),
              "wn_frame_l")
    b.box((0.0, 0.02, -SHUTTER_H * 0.54), (SHUTTER_W * 1.10, 0.18, 0.08), "wn_sill")
    return b.finish("WindowRollingShutter")


def build_honeycomb_cell():
    """(6) The octagonal cell over its planter."""
    b = Builder()
    b.annulus((0, 0, 0), COMB_R, COMB_R * 0.87, 0.13, "wn_frame", sides=8)
    b.card((0, 0.02, 0), (COMB_R * 1.66, COMB_R * 1.66), "wn_rose", axis='Y',
           art=COMB_ART)
    b.ngon_prism((0.0, 0.0), COMB_R * 0.80, COMB_R * 0.62, 0.20, "wn_sill",
                 sides=8, z0=-COMB_R - 0.20)
    b.box((0.0, 0.0, -COMB_R - 0.24), (COMB_R * 1.5, 0.16, 0.07), "wn_frame_d")
    return b.finish("WindowHoneycombCell")


PIECES = []
for fn, px in ((build_rose_aperture, 48.0), (build_rose_vent, 64.0),
               (build_membrane_pore, 96.0), (build_capillary_slits, 128.0),
               (build_balcony_bay, 96.0), (build_drawer_band, 96.0),
               (build_rolling_shutter, 96.0), (build_honeycomb_cell, 96.0)):
    piece = fn()
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    PIECES.append(piece)
    print("[WIN] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))

# lay them out side by side so the saved master reads like the sheet it came from
_x = 0.0
for _p in PIECES:
    _p.location.x = _x
    _x += 1.9

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "window_pieces.blend"))
pl.export_gltf(PIECES, os.path.join(OUT_DIR, "window_pieces.gltf"))
print("=== DONE: window pieces -> %s ===" % OUT_DIR)
