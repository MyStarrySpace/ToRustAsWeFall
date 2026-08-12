# STACKS PIECES — The Open Files Initiative's styling of the shared vocabulary.
#
# THE LAW (director, 2026-08-10): an ARCHETYPE is the abstract gameplay noun the
# generator places; a DISTRICT styles it. The Plumbing Power Project renders
# `terminal` as rusted hydraulic hardware; the Open Files renders the SAME noun as
# a paper-and-index reading kiosk. Nothing about the generator changes — only the
# geometry a content id resolves to. This file is the second district, and the
# proof the split works: it adds one entry to ArchetypePieceLibrary.DISTRICT_PIECES
# and nothing else.
#
# THE DISTRICT (GDD 4.4): "The Open Files Initiative" (shelters 6-7; vernacular
# "the Open Files", "Open") — data terminals. Government-aspirational naming over a
# project that succeeded and was captured: the files ARE open, and open is exactly
# how a records office becomes a surveillance archive. Its declared vocabulary
# (biomes.gd stacks theme) is drawer-stack spires, archive canyons and service
# catwalks; scan arches, terminal kiosks and live drawer bands. Tanglers haunt it
# because this is where thinking used to happen.
#
# THE LOOK: dry paper and dead storage under one cold cyan index light. Where the
# Channels are wet iron, the Open Files are dust and card stock — the only living
# colour is the light the system shines on what it is currently reading.
#
# Repetition is DRAWN, never modelled: a drawer wall is one card wearing pixel art,
# not ninety modelled drawer fronts. Scale is the house scale, 1 m = 32 px.
#
# Run:  blender.exe -b --python blender/stacks/build_stacks_pieces.py
#       (Blender 5.1 — 4.2 cannot read the 5.x blends and renders the default cube)
# Outputs (game-ready, committed):
#   to-rust-as-we-fall/resources/models/stacks/stacks_pieces.gltf (+bin/tex)
# Source (gitignored):
#   blender/stacks/stacks_pieces.blend        — the inspectable labeled sheet
#   blender/stacks/obj-exports/<Piece>.obj    — BlockBench hand-off
#   blender/stacks/painted/<Piece>_tex.png    — hand-paint drop, wins on rebuild
#   C:/tmp/stacks_cards/<Piece>.png           — per-piece eyeball cards

import bpy
import importlib
import json
import math
import mathutils
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder, DETAIL_SCREEN
from paintlib.painters import paint_wood_grain, paint_metal_panel

SRC = os.path.join(BL, "stacks")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
GLTF = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "stacks",
                    "stacks_pieces.gltf")
CARDS = r"C:\tmp\stacks_cards"
for d in (OBJX, PAINTED, os.path.dirname(GLTF), CARDS):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

# ---- palette authority -------------------------------------------------------------------
PAL = json.load(open(os.path.join(ROOT, "to-rust-as-we-fall", "data", "palettes",
                                  "level_palettes.json"), encoding="utf-8"))


def C(level, role):
    node = PAL[level]
    for part in role.split("/"):
        node = node[part]
    h = node.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def CT(role): return C("stacks", role)          # this district's row
def CG(role): return C("_global", role)
def _dim(c, f): return tuple(v * f for v in c)


# ---- card art ----------------------------------------------------------------------------

def _drawer_wall_art(tile, isl, px_per_m):
    """A DRAWER WALL, drawn. Ninety modelled drawer fronts would be ninety boxes
    that alias into grey mush at the distance this is played from; drawn, the
    grid stays crisp and an artist can repaint which cells are live.

    Each cell is a card-stock face with a dark seam, a pull bar, and a label
    slot. A few cells run OPEN — the front recessed to black — because a wall
    where nothing is ever pulled reads as wallpaper, not as storage in use. Cell
    pitch is authored in metres, so the grid is honest at any card size."""
    ph, pw = tile.shape[:2]
    paper = CT("paper")
    face = _dim(paper, 0.72)
    seam = _dim(CT("structure"), 0.55)
    pull = _dim(paper, 0.42)
    void = _dim(CT("ground"), 0.5)
    cw = max(4, int(round(0.30 * px_per_m)))     # a 30 cm drawer front
    chh = max(3, int(round(0.22 * px_per_m)))    # 22 cm tall
    tile[:, :, :3] = seam
    tile[:, :, 3] = 1.0
    cols = max(1, pw // cw)
    rows = max(1, ph // chh)
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw, r * chh
            x1, y1 = min(pw, x0 + cw - 1), min(ph, y0 + chh - 1)
            if x1 - x0 < 2 or y1 - y0 < 2:
                continue
            # a deterministic scatter of pulled-open cells; never wall-clock random
            openish = ((r * 7 + c * 13 + (r * c) % 5) % 17) == 0
            tile[y0 + 1:y1, x0 + 1:x1, :3] = void if openish else face
            if openish:
                continue
            mid = (y0 + y1) // 2
            bar0 = x0 + 1 + (x1 - x0 - 1) // 4
            bar1 = x1 - (x1 - x0 - 1) // 4
            tile[mid, bar0:bar1, :3] = pull            # the pull bar
            if y1 - y0 >= 5:                           # the label slot above it
                tile[y0 + 2, x0 + 2:x0 + 2 + max(1, (x1 - x0) // 2), :3] = paper


def _live_band_art(tile, isl, px_per_m):
    """A LIVE DRAWER BAND (biomes.gd stacks feature vocabulary): the strip of cyan
    the system lights along the drawers it is currently reading. Cold index light
    over dark backing, dashed by cell so it reads as addressing rows of storage
    rather than as a neon tube. Transparent between dashes — the band is light on
    a wall, not a solid moulding."""
    ph, pw = tile.shape[:2]
    lit = CT("index_light")
    dim = _dim(lit, 0.35)
    dash = max(2, int(round(0.24 * px_per_m)))
    gap = max(1, int(round(0.06 * px_per_m)))
    tile[:, :, 3] = 0.0
    x = 0
    while x < pw:
        seg = min(dash, pw - x)
        tile[:, x:x + seg, :3] = lit
        tile[:, x:x + seg, 3] = 1.0
        if ph >= 3:                                    # a dimmer lip top and bottom
            tile[0, x:x + seg, :3] = dim
            tile[ph - 1, x:x + seg, :3] = dim
        x += seg + gap


DRAWER_WALL = pl.register_card_art("stacks_drawer_wall", _drawer_wall_art)
LIVE_BAND = pl.register_card_art("stacks_live_band", _live_band_art)

D_WOOD = pl.register_detail("stacks_wood", paint_wood_grain)
D_PANEL = pl.register_detail("stacks_panel", paint_metal_panel)

pl.register_parts({
    "of_ground":    {"rgb": CT("ground"), "family": "speckled"},
    "of_structure": {"rgb": CT("structure")},
    "of_frame":     {"rgb": _dim(CT("structure"), 1.35)},
    "of_rust":      {"rgb": CT("rust")},
    "of_paper":     {"rgb": CT("paper"), "family": "wood"},
    "of_card":      {"rgb": _dim(CT("paper"), 0.82)},
    "of_index":     {"rgb": _dim(CT("index_light"), 0.30), "emit": CT("index_light")},
    "of_screen":    {"rgb": _dim(CT("index_light"), 0.22), "emit": _dim(CT("index_light"), 0.9)},
    "of_dark":      {"rgb": _dim(CT("ground"), 0.6)},
}, emit_strength={"of_index": 1.9, "of_screen": 1.3})


# ============================================================================
# THE ARCHETYPES, IN THE OPEN FILES' LANGUAGE
# Same gameplay nouns the generator places everywhere; this is what they look
# like in a records office that never stopped recording.
# ============================================================================

def build_terminal():
    """Archetype `terminal`, as a READING KIOSK: a card-stock desk on a steel
    frame with the index screen recessed into its hood, a paper tray that still
    has stock in it, and the cyan reading strip along the desk edge that tells
    you the machine is awake. The Channels' terminal is a flow console; this is
    the same verb wearing the district that made information a public work."""
    b = Builder()
    b.box((0, 0, 0.06), (0.86, 0.62, 0.12), "of_dark", skip=("bottom",))       # foot slab
    for sx in (-0.34, 0.34):                                                   # frame legs
        b.box((sx, 0, 0.42), (0.09, 0.5, 0.6), "of_frame")
    b.box((0, 0, 0.76), (0.9, 0.66, 0.1), "of_paper", detail=D_WOOD)           # the desk
    b.box((0, 0.24, 0.9), (0.9, 0.14, 0.2), "of_structure", detail=D_PANEL)    # the hood
    b.box((0, 0.15, 0.9), (0.66, 0.02, 0.16), "of_screen", detail=DETAIL_SCREEN)
    b.box((0, -0.2, 0.83), (0.44, 0.2, 0.04), "of_card")                       # paper tray
    b.card((0, -0.335, 0.79), (0.9, 0.06), "of_index", axis='Y', art=LIVE_BAND)
    return b.finish("Terminal")


def build_barrier():
    """Archetype `barrier`, as a DRAWER STACK: the district blocks a way with
    storage, because storage is what it has. A steel carcass with its drawer wall
    DRAWN on the face, a live band across the middle rank, and a kick plate. Two
    metres of records standing where a fence would be anywhere else."""
    b = Builder()
    b.box((0, 0, 0.07), (1.9, 0.56, 0.14), "of_dark", skip=("bottom",))        # plinth
    b.box((0, 0, 1.05), (1.9, 0.5, 1.9), "of_structure", detail=D_PANEL)       # carcass
    for sx in (-0.93, 0.93):                                                   # corner posts
        b.box((sx, 0, 1.05), (0.08, 0.54, 1.9), "of_frame")
    b.card((0, -0.255, 1.05), (1.74, 1.8), "of_card", axis='Y', art=DRAWER_WALL)
    b.card((0, -0.262, 1.02), (1.74, 0.07), "of_index", axis='Y', art=LIVE_BAND)
    b.box((0, 0, 2.04), (1.98, 0.58, 0.08), "of_frame")                        # cap rail
    return b.finish("Barrier")


def build_carry_gear():
    """Archetype `carry_gear`, as a FILE CASE: the thing a worker here carries is
    documents. A banded card-stock case with a steel handle, a stencilled label
    panel, and one index tab still lit from whatever last read it."""
    b = Builder()
    b.box((0, 0, 0.16), (0.62, 0.38, 0.32), "of_card", detail=D_WOOD)          # the case
    for sy in (-0.13, 0.13):                                                   # binding bands
        b.box((0, sy, 0.16), (0.64, 0.05, 0.33), "of_rust")
    b.box((0, 0, 0.335), (0.5, 0.3, 0.02), "of_paper")                         # lid stock
    b.box((0, -0.2, 0.2), (0.26, 0.02, 0.1), "of_structure")                   # label panel
    b.box((0, 0, 0.4), (0.22, 0.05, 0.05), "of_frame")                         # handle
    b.box((0.22, -0.2, 0.26), (0.07, 0.02, 0.05), "of_index")                  # the lit tab
    return b.finish("CarryGear")


def build_junction():
    """Archetype `junction`, as an INDEX POST: where the Channels branch pipes,
    the Open Files branch references. A column of card racks on a steel post, its
    arms pointing the ways the catalogue goes, one live band around the collar."""
    b = Builder()
    b.ngon_prism((0, 0), 0.22, 0.26, 0.08, "of_dark", sides=8)                 # base
    b.ngon_prism((0, 0), 0.09, 0.1, 1.5, "of_frame", sides=8, z0=0.08)         # the post
    for i, a in enumerate((0.5, 2.6, 4.4)):                                    # catalogue arms
        dx, dy = math.sin(a), math.cos(a)
        z = 0.62 + i * 0.32
        b.box((dx * 0.28, dy * 0.28, z), (0.42, 0.16, 0.1), "of_card",
              detail=D_WOOD, skip=())
        b.box((dx * 0.44, dy * 0.44, z + 0.06), (0.16, 0.1, 0.015), "of_paper")
    b.ngon_prism((0, 0), 0.13, 0.13, 0.07, "of_index", sides=8, z0=1.44)       # collar light
    b.ngon_prism((0, 0), 0.15, 0.12, 0.1, "of_structure", sides=8, z0=1.51)    # cap
    return b.finish("Junction")


# ============================================================================
# THE DISTRICT'S OWN FEATURE VOCABULARY (biomes.gd stacks theme)
# ============================================================================

def build_scan_arch():
    """SCAN ARCH — the throat every file (and every worker) passes through. Two
    posts, a lintel of reading heads, and the cyan curtain of index light hanging
    in the opening: drawn, so the light reads as a scanned plane rather than a
    slab of glowing plastic. This is the district's whole thesis as one prop —
    the files are open, and so is everyone who walks through here."""
    b = Builder()
    for sx in (-1.0, 1.0):
        b.box((sx, 0, 0.09), (0.44, 0.6, 0.18), "of_dark", skip=("bottom",))   # foot
        b.box((sx, 0, 1.2), (0.28, 0.42, 2.4), "of_structure", detail=D_PANEL)
        b.box((sx, -0.22, 1.2), (0.1, 0.03, 2.0), "of_index")                  # post strip
    b.box((0, 0, 2.52), (2.3, 0.46, 0.26), "of_structure", detail=D_PANEL)     # lintel
    for hx in (-0.6, -0.2, 0.2, 0.6):                                          # reading heads
        b.box((hx, -0.2, 2.44), (0.14, 0.1, 0.12), "of_frame")
        b.box((hx, -0.255, 2.44), (0.08, 0.02, 0.06), "of_screen")
    b.card((0, 0, 1.3), (1.72, 2.2), "of_index", axis='Y', art=LIVE_BAND)      # the scan curtain
    return b.finish("ScanArch")


def build_drawer_spire():
    """DRAWER-STACK SPIRE — the district's building vocabulary at prop scale: a
    freestanding column of drawers, four faces of DRAWN wall, banded where the
    system is reading. Archive canyons are built by standing several of these in
    a row, which is the point of a piece rather than a bespoke model."""
    b = Builder()
    b.box((0, 0, 0.1), (1.15, 1.15, 0.2), "of_dark", skip=("bottom",))
    b.box((0, 0, 1.75), (1.0, 1.0, 3.1), "of_structure", detail=D_PANEL)
    for sx in (-0.5, 0.5):
        b.box((sx, 0, 1.75), (0.07, 1.06, 3.1), "of_frame")
    for (cy, yaw) in ((-0.505, 0.0), (0.505, math.pi)):
        b.card((0, cy, 1.75), (0.86, 2.9), "of_card", axis='Y',
               art=DRAWER_WALL, rot=(0.0, 0.0, yaw))
        b.card((0, cy - 0.006 if cy < 0 else cy + 0.006, 1.2), (0.86, 0.08),
               "of_index", axis='Y', art=LIVE_BAND, rot=(0.0, 0.0, yaw))
    b.box((0, 0, 3.36), (1.2, 1.2, 0.12), "of_frame")                          # cornice
    return b.finish("DrawerSpire")


# ============================================================================
# THE FIXTURES EVERY DISTRICT NEEDS
# Floor, wall, rail, door, lamp, sign. The Channels style all six already; a
# district that cannot tile its own floor borrows the Channels' wet deck and
# stops being the Open Files. Repetition here is DRAWN — a floor is one plane
# with tiles painted on it, never a grid of modelled slabs.
# ============================================================================

def _floor_tile_art(tile, isl, px_per_m):
    """The reading-room floor: pressed card tiles laid in a grid, gone dark down
    the middle where eighty years of trolleys wore a lane between the stacks. The
    wear is the environmental storytelling — it says where people actually walked,
    which is not where the plan said they would."""
    ph, pw = tile.shape[:2]
    # Two close tones, not a checkerboard. A records office floor is quiet — the
    # eye should land on the drawers and the pools of lamp light, never on the
    # floor pattern, and a high-contrast chequer turns the room into a diner.
    base = CT("ground")
    warm = _dim(CT("ground"), 1.16)
    seam = _dim(CT("ground"), 0.68)
    worn = _dim(CT("ground"), 0.82)
    rust = _dim(CT("rust"), 0.55)
    cell = max(4, int(round(0.5 * px_per_m)))       # 50 cm tiles

    def h2(x, y, sd):
        n = (x * 73856093) ^ (y * 19349663) ^ (sd * 83492791)
        n = (n ^ (n >> 13)) & 0xFFFFFFF
        return (n % 1000) / 1000.0

    cx = (pw - 1) * 0.5
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            gx, gy = x // cell, y // cell
            checker = (gx + gy) % 2 == 0
            col = list(base if checker else warm)
            # the worn traffic lane, widest at the middle of the run
            lane = 1.0 - min(1.0, abs(x - cx) / max(1.0, cx * 0.42))
            if lane > 0.25 and h2(x, y, 3) < 0.25 + 0.55 * lane:
                col = list(worn)
            if h2(x, y, 11) > 0.995:                # flecks of iron bleed
                col = list(rust)
            if x % cell == 0 or y % cell == 0:      # the grout
                col = list(seam)
            tile[y, x, :3] = col


def _index_wall_art(tile, isl, px_per_m):
    """The wall of a records office: steel index plates bolted in courses, each
    carrying its range card. Bolts and cards are painted, not modelled, because a
    wall's job is to repeat and geometry that repeats is geometry wasted."""
    ph, pw = tile.shape[:2]
    plate = CT("structure")
    plate_d = _dim(CT("structure"), 0.78)
    bolt = _dim(CT("structure"), 1.45)
    card = CT("paper")
    # Plates are SMALL. Sized like drawer fronts the wall stops reading as a wall
    # and starts reading as a chest of drawers standing against one.
    course = max(4, int(round(0.24 * px_per_m)))
    width = max(4, int(round(0.34 * px_per_m)))
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            row = y // course
            tile[y, x, :3] = plate if row % 2 == 0 else plate_d
    seam_c = _dim(CT("structure"), 0.5)
    for ry in range(0, ph, course):                 # the course seams
        tile[ry, :, :3] = seam_c
    for rx in range(0, pw, width):                  # and the vertical joints
        tile[:, rx, :3] = seam_c
    for ry in range(0, ph, course):
        for rx in range(0, pw, width):
            by, bx = ry + 1, rx + 1
            if by < ph and bx < pw:                 # a bolt at each plate corner
                tile[by, bx, :3] = bolt
            if bx + width - 2 < pw and by < ph:
                tile[by, bx + width - 2, :3] = bolt
            # A range card on only some plates: every plate labelled reads as
            # wallpaper, and a records office labels the courses it is working.
            if ((ry // course) * 5 + (rx // width) * 3) % 4 != 0:
                continue
            cy0, cy1 = ry + course // 2, ry + course // 2 + max(1, course // 4)
            cx0, cx1 = rx + 2, rx + max(3, width - 3)
            if cy1 < ph and cx1 < pw:               # the range card in its holder
                tile[cy0:cy1, cx0:cx1, :3] = card


FLOOR_TILE = pl.register_card_art("stacks_floor_tile", _floor_tile_art)
INDEX_WALL = pl.register_card_art("stacks_index_wall", _index_wall_art)


def build_floor_tile():
    """Archetype `deck_planks`, as READING-ROOM FLOOR: one 2 m plane of drawn card
    tiling on a thin sub-floor lip, so a room is tiled by repeating a piece."""
    b = Builder()
    b.box((0, 0, -0.03), (2.0, 2.0, 0.06), "of_dark", skip=("top",))
    b.card((0, 0, 0.005), (2.0, 2.0), "of_ground", axis='Z', art=FLOOR_TILE)
    return b.finish("FloorTile")


def build_wall_panel_tile():
    """Archetype `wall_panel_tile`, as INDEX PLATING: a 2 m run of the wall a
    records office is actually made of, drawn on one plane against a backing slab."""
    b = Builder()
    b.box((0, 0.05, 1.25), (2.0, 0.1, 2.5), "of_structure", detail=D_PANEL)
    b.card((0, -0.002, 1.25), (2.0, 2.5), "of_frame", axis='Y', art=INDEX_WALL)
    return b.finish("WallPanelTile")


def build_railing_run():
    """Archetype `railing_run`, as GALLERY RAIL: the Open Files reads its drawers
    from balconies, so its rail is a working handrail with a card lip along the
    top — you set the file you are holding down on it while you find the next."""
    b = Builder()
    b.box((0, 0, 1.02), (2.0, 0.05, 0.06), "of_frame")             # the top rail
    b.box((0, 0, 1.08), (2.0, 0.16, 0.02), "of_card", detail=D_WOOD)  # the card lip
    b.box((0, 0, 0.6), (2.0, 0.035, 0.04), "of_structure")         # mid rail
    for sx in (-0.9, -0.3, 0.3, 0.9):
        b.box((sx, 0, 0.5), (0.06, 0.06, 1.0), "of_structure", detail=D_PANEL)
        b.box((sx, 0, 0.02), (0.16, 0.16, 0.04), "of_dark")        # the foot plate
    return b.finish("RailingRun")


def build_records_door():
    """Archetype `door_ironband`, as a RECORDS DOOR: a heavy leaf banded like the
    Channels' but carrying what this district puts on a door instead of rivets —
    the range it closes over, on a card in a brass holder, and a slot to return
    files through when the room is locked."""
    b = Builder()
    b.box((0, 0, 1.05), (1.1, 0.12, 2.1), "of_card", detail=D_WOOD)
    for z in (0.35, 1.05, 1.75):                                   # the bands
        b.box((0, -0.005, z), (1.14, 0.14, 0.11), "of_frame", detail=D_PANEL)
    b.box((0, -0.07, 1.5), (0.44, 0.02, 0.2), "of_paper")          # the range card
    b.box((0, -0.075, 1.5), (0.48, 0.015, 0.24), "of_frame")       # its holder
    b.box((0, -0.06, 0.72), (0.42, 0.03, 0.06), "of_dark")         # the return slot
    b.ngon_prism((0.42, -0.09), 0.035, 0.035, 0.12, "of_frame", sides=8, z0=0.98)
    return b.finish("RecordsDoor")


def build_reading_lamp():
    """Archetype `cage_lamp`, as a READING LAMP: the same caged bulb the Channels
    hang in a wet corridor, but shaded downward over a desk. A records office
    lights the PAPER and leaves the room dim, which is why the district reads as
    pools of light between dark canyons."""
    b = Builder()
    b.ngon_prism((0, 0), 0.11, 0.09, 0.03, "of_dark", sides=10, z0=0.0)   # ceiling plate
    b.box((0, 0, 0.2), (0.03, 0.03, 0.4), "of_structure")                 # the drop
    b.ngon_prism((0, 0), 0.06, 0.22, 0.16, "of_frame", sides=10, z0=0.4)  # the shade
    b.ngon_prism((0, 0), 0.2, 0.19, 0.02, "of_index", sides=10, z0=0.55)  # the lit mouth
    for i in range(4):                                                    # the cage
        a = i * math.tau / 4.0 + 0.4
        b.box((math.sin(a) * 0.18, math.cos(a) * 0.18, 0.5), (0.016, 0.016, 0.2),
              "of_structure")
    return b.finish("ReadingLamp")


def build_department_sign():
    """Archetype `gate_sign`, as a DEPARTMENT BOARD: what a public records office
    hangs where a corridor divides — the department, its range, and the lit strip
    that says the index behind this door is still being read."""
    b = Builder()
    b.box((0, 0, 1.6), (1.5, 0.07, 0.52), "of_structure", detail=D_PANEL)
    b.box((0, -0.045, 1.66), (1.34, 0.02, 0.3), "of_paper")            # the board face
    b.box((0, -0.05, 1.42), (1.34, 0.02, 0.09), "of_index")            # the lit range strip
    for sx in (-0.62, 0.62):                                           # the hangers
        b.box((sx, 0.04, 2.0), (0.05, 0.05, 0.36), "of_frame")
    b.box((0, 0.04, 2.19), (1.5, 0.06, 0.06), "of_frame")              # the cross bar
    return b.finish("DepartmentSign")


# ---- build + texture + labeled sheet ------------------------------------------------------
BUILDERS = [
    build_terminal, build_barrier, build_carry_gear, build_junction,
    build_scan_arch, build_drawer_spire,
    build_floor_tile, build_wall_panel_tile, build_railing_run,
    build_records_door, build_reading_lamp, build_department_sign,
]
PX_OVERRIDES = {"CarryGear": 48.0, "Terminal": 48.0,
                "ReadingLamp": 64.0, "DepartmentSign": 48.0,
                "RecordsDoor": 48.0}

PIECES = {}
COLS = 3
SPACING = 4.4
for i, fn in enumerate(BUILDERS):
    ob = fn()
    PIECES[ob.name] = ob
    if not ob.get("no_atlas"):
        pl.texture_object(ob, OBJX, px_per_m=PX_OVERRIDES.get(ob.name, 32.0),
                          painted_dir=PAINTED)
        pl.export_obj([ob], os.path.join(OBJX, ob.name + ".obj"))
    ob.location = ((i % COLS) * SPACING, -(i // COLS) * SPACING, 0.0)

# ---- lighting + per-piece eyeball cards ---------------------------------------------------
sun = bpy.data.lights.new("Sun", 'SUN')
sun.energy = 2.4
sun.color = (0.96, 0.94, 0.88)
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (0.9, 0.25, 0.5)
scene.collection.objects.link(so)
fill = bpy.data.lights.new("Fill", 'SUN')
fill.energy = 0.7
fill.color = (0.72, 0.8, 0.95)
fo = bpy.data.objects.new("Fill", fill)
fo.rotation_euler = (1.2, -0.4, 2.6)
scene.collection.objects.link(fo)
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.09, 0.10, 1)
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = 34
cam = bpy.data.objects.new("Cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
for _eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try:
        scene.render.engine = _eng
        break
    except Exception:
        pass
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_x = 480
scene.render.resolution_y = 480
for name, ob in PIECES.items():
    for other in PIECES.values():
        other.hide_render = other is not ob
    bb = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
    ctr = sum(bb, mathutils.Vector((0, 0, 0))) / 8.0
    rad = max((v - ctr).length for v in bb)
    look = mathutils.Vector((0.8, -1.0, 0.55)).normalized()
    cam.location = ctr + look * (rad * 2.3 + 0.5)
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(CARDS, name + ".png")
    bpy.ops.render.render(write_still=True)
for ob in PIECES.values():
    ob.hide_render = False

# ---- the saved .blend IS the inspectable asset sheet --------------------------------------
for name, ob in PIECES.items():
    curve = bpy.data.curves.new("LabelC_" + name, type='FONT')
    curve.body = name
    curve.size = 0.3
    curve.align_x = 'CENTER'
    label = bpy.data.objects.new("Label_" + name, curve)
    label.location = (ob.location.x, ob.location.y - 2.1, 0.02)
    label.rotation_euler = (0.35, 0.0, 0.0)
    scene.collection.objects.link(label)
cx = (COLS - 1) * SPACING / 2.0
cy = -((len(BUILDERS) - 1) // COLS) * SPACING / 2.0
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
cam.location = (cx, cy - 13.0, 10.0)
cam.rotation_euler = (mathutils.Vector((cx, cy, 1.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
scene.render.filepath = r"C:\tmp\stacks_pieces_sheet.png"
try:
    bpy.ops.render.render(write_still=True)
except Exception:
    pass

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "stacks_pieces.blend"))
pl.export_gltf(list(PIECES.values()), GLTF)
print("=== DONE: %d stacks pieces -> %s ===" % (len(PIECES), GLTF))
