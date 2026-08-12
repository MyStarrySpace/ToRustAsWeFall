# BUILDING MATERIALS — the surface library the procedural architecture wears.
#
# Blender 5.1 only:  blender.exe -b --python blender/materials/build_building_materials.py
#
# THE SHEET IS THE BRIEF. reference-images/architecture/sheets/materials_decay.png
# names ten materials and seven decay overlays, and it draws the overlays ON a
# base rather than beside it -- which is the whole design. A surface in this world
# is a material plus what has happened to it, so the two are authored as separate
# tiles and combined at draw time. Ten bases and seven overlays give seventy
# readable surfaces out of seventeen files, and the alternative -- baking every
# combination -- gives seventy files nobody can edit, because fixing the rust
# would mean repainting it ten times.
#
# WHY THIS EXISTS AT ALL: the buildings are drawn procedurally in Godot and every
# surface on them was a flat albedo colour. There was nowhere for an artist to put
# a brush.
#
# Outputs, committed and game-ready:
#   to-rust-as-we-fall/resources/materials/building/base_<nn>_<name>.png   (RGB)
#   to-rust-as-we-fall/resources/materials/building/decay_<nn>_<name>.png  (RGBA)
#
# HAND-PAINTING: drop a file of the same name into blender/materials/painted/ and
# it wins on the next build, the same round-trip every other paintable area uses.
# The generated tile stays as the starting point to paint over.

import bpy
import math
import os
import sys

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)

SRC = os.path.join(BL, "materials")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "materials", "building")
for d in (PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

# One tile is two metres of wall at the project's 32 px/m, which is the scale
# every other drawn surface in the game is authored at.
PX_PER_M = 32
TILE_M = 4.0
TILE = int(PX_PER_M * TILE_M)          # 128

# The sheet's palette: a verdigris facility metal going to ferric red.
TEAL = (0.286, 0.376, 0.376)
TEAL_D = (0.196, 0.267, 0.271)
TEAL_L = (0.376, 0.475, 0.463)
BRASS = (0.510, 0.427, 0.271)
BRASS_D = (0.361, 0.298, 0.184)
RUST = (0.463, 0.243, 0.129)
RUST_L = (0.596, 0.325, 0.169)
BONE = (0.788, 0.776, 0.694)
BONE_D = (0.612, 0.596, 0.518)
FLESH = (0.663, 0.404, 0.353)
FLESH_D = (0.478, 0.278, 0.243)
CHAR = (0.114, 0.098, 0.086)
MOULD = (0.855, 0.847, 0.804)
DARK = (0.055, 0.059, 0.063)


def _rng(seed):
    """A deterministic stream. Every tile has to rebuild identically or a painted
    override stops lining up with the thing it was painted over."""
    state = [seed & 0xFFFFFFFF]

    def nxt():
        state[0] = (1103515245 * state[0] + 12345) & 0x7FFFFFFF
        return state[0] / float(0x7FFFFFFF)
    return nxt


def _fill(tile, rgb):
    tile[:, :, 0], tile[:, :, 1], tile[:, :, 2] = rgb


def _grain(tile, seed, amount=0.05):
    """The tooth every painted surface in this game has. Without it a tile reads
    as vector art the moment it is next to anything else."""
    r = _rng(seed)
    for y in range(tile.shape[0]):
        for x in range(tile.shape[1]):
            k = 1.0 + (r() - 0.5) * 2.0 * amount
            tile[y, x, :3] = np.clip(tile[y, x, :3] * k, 0.0, 1.0)


def _line(tile, x0, y0, x1, y1, rgb, width=1):
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    h, w = tile.shape[:2]
    for i in range(steps):
        t = i / float(max(1, steps - 1))
        cx, cy = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
        for dy in range(-(width // 2), width - width // 2):
            for dx in range(-(width // 2), width - width // 2):
                x, y = (cx + dx) % w, (cy + dy) % h
                tile[y, x, :3] = rgb


def _rivets(tile, rgb_hi, rgb_lo, inset=4, step=None):
    """Rivet heads round the edge of a panel, wrapping the tile so a wall of them
    keeps its rhythm across the seam."""
    h, w = tile.shape[:2]
    step = step or (w // 6)
    for x in range(inset, w, step):
        for y in (inset, h - 1 - inset):
            tile[y % h, x % w, :3] = rgb_hi
            tile[(y + 1) % h, x % w, :3] = rgb_lo
    for y in range(inset, h, step):
        for x in (inset, w - 1 - inset):
            tile[y % h, x % w, :3] = rgb_hi
            tile[y % h, (x + 1) % w, :3] = rgb_lo


# ---------------------------------------------------------------- the ten bases

def base_riveted_panel(tile):
    """(1) riveted facility-metal panel-seam. The default wall of the whole
    facility, and the surface every decay overlay on the sheet is drawn over."""
    _fill(tile, TEAL)
    h, w = tile.shape[:2]
    _line(tile, 0, h // 2, w - 1, h // 2, TEAL_D, 2)      # the panel seams
    _line(tile, w // 2, 0, w // 2, h - 1, TEAL_D, 2)
    _line(tile, 0, h // 2 + 2, w - 1, h // 2 + 2, TEAL_L, 1)
    _line(tile, w // 2 + 2, 0, w // 2 + 2, h - 1, TEAL_L, 1)
    _rivets(tile, TEAL_L, TEAL_D)
    _grain(tile, 11, 0.06)


def base_diamond_plate(tile):
    """(2) deck-metal diamond-plate. Repetition, so it is drawn: a modelled
    diamond field would alias into mush at the distance a deck is read from."""
    _fill(tile, TEAL_D)
    h, w = tile.shape[:2]
    pitch = max(6, w // 12)
    for gy in range(0, h, pitch):
        for gx in range(0, w, pitch):
            ox = (pitch // 2) if (gy // pitch) % 2 else 0
            cx, cy = (gx + ox) % w, gy
            for i in range(pitch // 3):
                _line(tile, cx - i, cy + i, cx + i, cy + i, TEAL_L, 1)
                _line(tile, cx - i, cy - i, cx + i, cy - i, TEAL, 1)
    _grain(tile, 23, 0.05)


def base_crosshatch_grating(tile):
    """(3) crosshatch grating. The sheet shows THROUGH it, so the gaps are real
    alpha -- a grate is one plane wearing a drawn lattice, never modelled bars."""
    tile[:, :, :3] = DARK
    tile[:, :, 3] = 0.0
    h, w = tile.shape[:2]
    pitch = max(10, w // 6)               # coarse: the sheet's holes are big
    for k in range(-h, w + h, pitch):
        for t in range(h):
            for x in (k + t, k - t):          # both diagonals, woven
                xx = x % w
                tile[t, xx, :3] = BRASS
                tile[t, xx, 3] = 1.0
                tile[t, (xx + 1) % w, :3] = BRASS_D
                tile[t, (xx + 1) % w, 3] = 1.0
    _grain(tile, 31, 0.07)


def base_membrane(tile):
    """(4) smooth-layered translucent basement-membrane. Cell-boundary webbing
    over a pale wash: the softest surface in the set and the one that reads as
    tissue rather than fabric."""
    _fill(tile, BONE)
    h, w = tile.shape[:2]
    r = _rng(47)
    seeds = [(r() * w, r() * h) for _ in range(9)]
    for y in range(h):
        for x in range(w):
            best = second = 1e9
            for (sx, sy) in seeds:
                dx = min(abs(x - sx), w - abs(x - sx))
                dy = min(abs(y - sy), h - abs(y - sy))
                d = dx * dx + dy * dy
                if d < best:
                    best, second = d, best
                elif d < second:
                    second = d
            edge = (second ** 0.5 - best ** 0.5)
            if edge < 1.6:
                tile[y, x, :3] = BONE_D
            elif edge < 3.0:
                tile[y, x, :3] = np.clip(np.array(BONE) * 0.94, 0, 1)
    _grain(tile, 53, 0.04)


def base_myelin_cabling(tile):
    """(5) myelin-wrap nerve-fascicle cabling. Bundled runs with the wrap banding
    across them -- the banding is the repetition, so it is pixels."""
    _fill(tile, BONE_D)
    h, w = tile.shape[:2]
    cables = 5
    cw = w // cables
    for c in range(cables):
        x0 = c * cw
        for y in range(h):
            wob = int(math.sin((y / float(h)) * math.tau * 1.5 + c) * cw * 0.18)
            for x in range(x0 + 1, x0 + cw - 1):
                xx = (x + wob) % w
                edge = min(x - x0, x0 + cw - x) / float(cw * 0.5)
                col = BONE if edge > 0.45 else BONE_D
                if (y + c * 3) % 7 == 0:          # the myelin banding
                    col = BRASS_D
                tile[y, xx, :3] = col
    _grain(tile, 67, 0.05)


def base_tissue_substrate(tile):
    """(6) pinkish tissue-substrate with vessel grooves."""
    _fill(tile, FLESH)
    h, w = tile.shape[:2]
    r = _rng(71)
    for _ in range(7):
        x, y = r() * w, r() * h
        ang = r() * math.tau
        for step in range(int(h * 1.2)):
            x = (x + math.cos(ang)) % w
            y = (y + math.sin(ang)) % h
            ang += (r() - 0.5) * 0.28
            tile[int(y), int(x), :3] = FLESH_D
            tile[int(y), int(x - 1) % w, :3] = np.clip(np.array(FLESH) * 1.1, 0, 1)
    _grain(tile, 73, 0.07)


def base_fish_scale(tile):
    """(7) overlapping fish-scale shingle."""
    _fill(tile, TEAL_D)
    h, w = tile.shape[:2]
    pitch = max(8, w // 8)
    for row in range(-1, h // (pitch // 2) + 1):
        cy = row * (pitch // 2)
        ox = (pitch // 2) if row % 2 else 0
        for col in range(-1, w // pitch + 1):
            cx = col * pitch + ox
            for a in range(0, 180):
                th = math.radians(a)
                for rr in range(pitch // 2):
                    x = int(cx + math.cos(th) * rr) % w
                    y = int(cy + math.sin(th) * rr) % h
                    edge = rr / float(max(1, pitch // 2))
                    tile[y, x, :3] = TEAL_L if edge > 0.86 else (
                        TEAL if edge > 0.4 else TEAL_D)
    _grain(tile, 83, 0.05)


def base_vine_tracery(tile):
    """(8) raised whiplash vine-rib tracery."""
    _fill(tile, TEAL_D)
    h, w = tile.shape[:2]
    r = _rng(89)
    for c in range(9):                              # whipping ribs, close-packed
        amp = 0.06 + 0.06 * r()
        freq = 1.0 + 2.0 * r()
        phase = r() * math.tau
        for y in range(h):
            t = y / float(h)
            x = int((c / 9.0 + amp * math.sin(t * math.tau * freq + phase)) * w) % w
            for d in (-1, 0, 1):
                tile[y, (x + d) % w, :3] = BRASS if d == 0 else BRASS_D
    for _ in range(16):                             # the curl-overs that tie them
        cx, cy, rad = r() * w, r() * h, 5 + r() * 9
        for a in range(0, 330, 3):
            th = math.radians(a)
            x = int(cx + math.cos(th) * rad) % w
            y = int(cy + math.sin(th) * rad * 0.7) % h
            tile[y, x, :3] = BRASS_D
    _grain(tile, 97, 0.05)


def base_voronoi_screen(tile):
    """(9) open Voronoi cellular mesh-screen. Open, so it carries real alpha."""
    tile[:, :, :3] = DARK
    tile[:, :, 3] = 0.0
    h, w = tile.shape[:2]
    r = _rng(101)
    seeds = [(r() * w, r() * h) for _ in range(40)]
    for y in range(h):
        for x in range(w):
            best = second = 1e9
            for (sx, sy) in seeds:
                dx = min(abs(x - sx), w - abs(x - sx))
                dy = min(abs(y - sy), h - abs(y - sy))
                d = dx * dx + dy * dy
                if d < best:
                    best, second = d, best
                elif d < second:
                    second = d
            gap = second ** 0.5 - best ** 0.5
            if gap < 1.5:
                tile[y, x, :3] = BRASS if gap < 0.8 else BRASS_D
                tile[y, x, 3] = 1.0
    _grain(tile, 103, 0.06)


def base_honeycomb(tile):
    """(10) raised rounded-hexagon honeycomb relief."""
    _fill(tile, TEAL_D)
    h, w = tile.shape[:2]
    rad = max(6, w // 10)
    dy = int(rad * 1.5)
    for row in range(-1, h // dy + 2):
        for col in range(-1, w // int(rad * 1.732) + 2):
            cx = col * rad * 1.732 + (rad * 0.866 if row % 2 else 0)
            cy = row * dy
            for a in range(0, 360, 2):
                th = math.radians(a)
                for k in (0.82, 0.9, 1.0):
                    x = int(cx + math.cos(th) * rad * k) % w
                    y = int(cy + math.sin(th) * rad * k) % h
                    tile[y, x, :3] = TEAL_L if k > 0.95 else TEAL
    _grain(tile, 107, 0.05)


BASES = [
    ("riveted_panel", base_riveted_panel),
    ("diamond_plate", base_diamond_plate),
    ("crosshatch_grating", base_crosshatch_grating),
    ("basement_membrane", base_membrane),
    ("myelin_cabling", base_myelin_cabling),
    ("tissue_substrate", base_tissue_substrate),
    ("fish_scale_shingle", base_fish_scale),
    ("vine_rib_tracery", base_vine_tracery),
    ("voronoi_screen", base_voronoi_screen),
    ("honeycomb_relief", base_honeycomb),
]


# ------------------------------------------------------- the seven decay layers
# Each writes RGBA where alpha is COVERAGE: how much of this has happened here.
# Nothing here knows what it is sitting on, which is what lets seven files dress
# ten materials.

def decay_bleed_streaks(tile):
    """(1) ferric-red bleed-streaks. Runs downward from fixings and seams."""
    r = _rng(211)
    h, w = tile.shape[:2]
    for _ in range(14):
        x = int(r() * w)
        top = int(r() * h * 0.4)
        length = int(h * (0.3 + 0.6 * r()))
        width = 1 + int(r() * 2)
        for y in range(top, top + length):
            fade = 1.0 - (y - top) / float(length)
            for d in range(width):
                xx = (x + d) % w
                tile[y % h, xx, :3] = RUST_L if d == 0 else RUST
                tile[y % h, xx, 3] = max(tile[y % h, xx, 3], 0.85 * fade)


def decay_oxide_dust(tile):
    """(2) settled oxide dust. Lies on upward faces, so it is denser at the top
    of a tile and sparse below."""
    r = _rng(223)
    h, w = tile.shape[:2]
    for y in range(h):
        settle = (1.0 - y / float(h)) ** 1.6
        for x in range(w):
            if r() > settle * 0.55:
                continue
            tile[y, x, :3] = RUST
            tile[y, x, 3] = 0.3 + 0.35 * r()


def decay_char_crust(tile):
    """(3) char-burn crust. A burnt patch with a crusted, broken edge."""
    r = _rng(227)
    h, w = tile.shape[:2]
    cx, cy = w * 0.5, h * 0.5
    for y in range(h):
        for x in range(w):
            dx = min(abs(x - cx), w - abs(x - cx)) / (w * 0.5)
            dy = min(abs(y - cy), h - abs(y - cy)) / (h * 0.5)
            d = (dx * dx + dy * dy) ** 0.5
            edge = 0.72 + 0.3 * r()
            if d > edge:
                continue
            tile[y, x, :3] = CHAR if r() > 0.25 else (0.18, 0.14, 0.11)
            tile[y, x, 3] = min(1.0, 0.55 + 0.5 * (1.0 - d))


def decay_membrane_corrosion(tile):
    """(4) weeping membrane corrosion. Wet vertical seepage, paler and greener
    than rust, gathering where it runs."""
    r = _rng(229)
    h, w = tile.shape[:2]
    for _ in range(9):
        x = int(r() * w)
        for y in range(h):
            x = (x + (1 if r() > 0.5 else -1)) % w
            for d in range(2):
                xx = (x + d) % w
                tile[y, xx, :3] = (0.435, 0.478, 0.325)
                tile[y, xx, 3] = max(tile[y, xx, 3], 0.25 + 0.45 * (y / float(h)))


def decay_collapse_cracking(tile):
    """(5) collapse-scar cracking. Structural, so the cracks BRANCH rather than
    scatter -- that is what makes a wall read as having failed under load."""
    r = _rng(233)
    h, w = tile.shape[:2]

    def crack(x, y, ang, life):
        for _ in range(life):
            x = (x + math.cos(ang)) % w
            y = (y + math.sin(ang)) % h
            ang += (r() - 0.5) * 0.5
            tile[int(y), int(x), :3] = (0.09, 0.08, 0.08)
            tile[int(y), int(x), 3] = 0.9
            if r() < 0.02 and life > 14:
                crack(x, y, ang + (r() - 0.5) * 2.2, life // 2)

    for _ in range(4):
        crack(r() * w, r() * h, r() * math.tau, int(h * 0.9))


def decay_candid_mat(tile):
    """(6) white candid fungal mat. The colony, which is a canon organism -- the
    same white mat the Candid grows, so a wall wearing this is telling the player
    which corridor it is."""
    r = _rng(239)
    h, w = tile.shape[:2]
    for _ in range(11):
        cx, cy, rad = r() * w, r() * h, 4 + r() * 9
        for a in range(0, 360, 4):
            th = math.radians(a)
            for k in range(int(rad)):
                if r() > 0.7:
                    continue
                x = int(cx + math.cos(th) * k) % w
                y = int(cy + math.sin(th) * k) % h
                tile[y, x, :3] = MOULD if r() > 0.3 else (0.686, 0.678, 0.639)
                tile[y, x, 3] = max(tile[y, x, 3], 0.8 - 0.5 * (k / max(1.0, rad)))


def decay_molten_drip(tile):
    """(7) desaturated rust-brown molten drip-crust. Ran while hot and set, so it
    hangs in tongues from a horizon rather than streaking the whole face."""
    r = _rng(241)
    h, w = tile.shape[:2]
    horizon = int(h * 0.28)
    for x in range(w):
        tile[0:horizon, x, :3] = (0.310, 0.212, 0.157)
        tile[0:horizon, x, 3] = 0.9
    for _ in range(18):
        x = int(r() * w)
        drop = horizon + int(r() * h * 0.45)
        wid = 1 + int(r() * 3)
        for y in range(horizon, drop):
            for d in range(wid):
                xx = (x + d) % w
                tile[y % h, xx, :3] = (0.361, 0.243, 0.180)
                tile[y % h, xx, 3] = 0.85
        for d in range(wid + 1):                      # the bead at the tip
            tile[drop % h, (x + d - 1) % w, :3] = (0.420, 0.290, 0.212)
            tile[drop % h, (x + d - 1) % w, 3] = 0.95


DECAYS = [
    ("bleed_streaks", decay_bleed_streaks),
    ("oxide_dust", decay_oxide_dust),
    ("char_crust", decay_char_crust),
    ("membrane_corrosion", decay_membrane_corrosion),
    ("collapse_cracking", decay_collapse_cracking),
    ("candid_mat", decay_candid_mat),
    ("molten_drip", decay_molten_drip),
]


# ------------------------------------------------------------------------ write

def _save(name, arr):
    """Write through Blender's image API, and let a hand-painted file of the same
    name in painted/ win instead."""
    override = os.path.join(PAINTED, name)
    path = os.path.join(OUT_DIR, name)
    if os.path.exists(override):
        img = bpy.data.images.load(override, check_existing=False)
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        bpy.data.images.remove(img)
        print("  [painted] %s" % name)
        return "painted"
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    flipped = arr[::-1, :, :]              # Blender's origin is bottom-left
    img.pixels = flipped.reshape(-1).tolist()
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)
    return "generated"


def main():
    made = 0
    print("=== building materials: %d bases x %d decays ===" % (len(BASES), len(DECAYS)))
    for i, (name, fn) in enumerate(BASES):
        arr = np.zeros((TILE, TILE, 4), dtype=np.float32)
        arr[:, :, 3] = 1.0
        fn(arr)
        _save("base_%02d_%s.png" % (i + 1, name), arr)
        made += 1
    for i, (name, fn) in enumerate(DECAYS):
        arr = np.zeros((TILE, TILE, 4), dtype=np.float32)
        fn(arr)
        _save("decay_%02d_%s.png" % (i + 1, name), arr)
        made += 1
    print("=== DONE: %d tiles -> %s ===" % (made, OUT_DIR))


main()
