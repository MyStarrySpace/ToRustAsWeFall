# CHANNELS PARTS — the ONE place the Plumbing Power Project's piece geometry lives.
#
# THE LAW (director, 2026-08-10): one district piece file owns ALL of that
# district's piece geometry. A build script BUILDS or PLACES; it never carries a
# private copy of a piece. So the palette authority, the part register, the
# channels-specific area painters, the shape datums a piece is cut from, and every
# builder def live HERE, and the two channels scripts import them:
#
#   build_channels_pieces.py   the labeled asset SHEET + channels_pieces.gltf
#   build_wash_dressing.py     the helix PLACEMENT + channels_dressing.gltf
#
# What does NOT live here: placement datums (lanes, s-spans, keep-outs), scene
# builds, and the export/render tails — those belong to the script that places.
#
# Usage (the caller reloads paintlib first, then):
#   import channels_parts
#   channels_parts.register()                       # parts + detail painters
#   pieces = channels_parts.build_all()             # {name: object}
#   channels_parts.texture_all(pieces, OBJX, PAINTED)
#
# PIECES pipeline: paintlib Builder (blender/paintlib/, see
# skills/paintable-exports/SKILL.md) — clean-topology boxes/prisms/annuli, per-object
# hand-paintable textures. Axis law: box/ngon_prism/tapered_box are Z-up;
# annulus/disc are UPRIGHT (ring axis = local Y — portal-frame native). Flat rings
# are squat prisms. Detail (rivet courses, portholes, gate panels) lives in
# PAINTERS, not geometry — flat forms + pixel art, never over-modeled.

import functools
import json
import math
import os
import random
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)

import paintlib as pl
from paintlib import Builder, DETAIL_SCREEN
# The shared material language (wood/crates/sheet metal/barrels/trusses + the
# v-up and lift-on-dark laws) lives in paintlib.painters; only the CHANNELS-
# specific painters (drum skin, gate face) are authored below.
from paintlib.painters import (shade as _shade, lift as _lift, shadow as _shadow,
                               face_rng as _face_rng, role_fill as _role_fill,
                               paint_wood_grain as _paint_wood_grain,
                               paint_crate_face as _paint_crate_face,
                               paint_metal_panel as _paint_metal_panel,
                               paint_barrel as _paint_barrel,
                               paint_truss as _paint_truss)

# ---- THE PALETTE AUTHORITY (docs/LEVEL_PALETTES.md): every colour below traces to
# data/palettes/level_palettes.json — never a hard-coded rgb again. CH() is this
# district's row; a stacks_parts file differs from this one almost entirely by
# reading its own row. ----
PAL = json.load(open(os.path.join(ROOT, "to-rust-as-we-fall", "data", "palettes",
                                  "level_palettes.json"), encoding="utf-8"))


def C(level, role):
    node = PAL[level]
    for part in role.split("/"):
        node = node[part]
    h = node.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def CH(role): return C("channels", role)
def CG(role): return C("_global", role)
def CS(role): return C("species", role)     # canon flora colours, district-independent
def _dim(c, f): return tuple(v * f for v in c)


PORTAL_PURPLE = CG("portal_transit")        # PORTALS.md: local-transit purple

# ---- SHAPE datums: the dimensions a PIECE is cut from (the lanes and s-spans that
# say WHERE a piece stands stay with the placement script) --------------------------------
DRUM_R = 3.45
DRUM_BOTTOM = -2.0
DRUM_NECK_Y0 = 3.0
DRUM_NECK_Y1 = 7.6
DRUM_TOP = 16.5
GATE_W = 4.6
GATE_H = 6.6
WALL_FIN_H = 9.0
WALL_FIN_W = 1.7
SHAFT_R = 26.0
LEDGE_LANE_W = 3.6

# The nine section identities the gate signs wear (their s-spans are placement data).
SECTION_TYPES = ("flush", "current", "jet", "plate", "sluice", "patrol", "lure", "basin",
                 "double_plate")
SEC_COLORS = {t: CH("sections/" + t) for t in SECTION_TYPES}


# ---- the part palette (paintlib) --------------------------------------------------------
_registered = False


def register():
    """Register every channels part with paintlib. Idempotent — a script that both
    builds pieces and places them may call it more than once."""
    global _registered
    if _registered:
        return
    _registered = True
    pl.register_parts({
        "grate_iron":     {"rgb": (0.13, 0.125, 0.14)},   # the drawn bar field
        "grate_pit":      {"rgb": (0.045, 0.042, 0.05)},  # the dark under the holes
        "portal_iron":    {"rgb": (0.14, 0.135, 0.16)},   # machined housing
        "portal_iron_lt": {"rgb": (0.20, 0.19, 0.23)},    # rim/wear highlight courses
        "portal_dark":    {"rgb": (0.075, 0.07, 0.09)},   # recesses, yoke shadow faces
        "portal_rust":    {"rgb": (0.30, 0.17, 0.10)},    # weathering bands
        "portal_neon":    {"rgb": (0.22, 0.17, 0.40), "emit": PORTAL_PURPLE},
        "portal_void":    {"rgb": (0.035, 0.025, 0.05)},  # the dormant aperture
    }, emit_strength={"portal_neon": 2.2})
    pl.register_parts({
        "drum_iron":   {"rgb": CH("iron")},
        "drum_flange": {"rgb": CH("rust")},
        "drum_rail":   {"rgb": CH("iron")},
        "drum_water":  {"rgb": CH("water_deep"), "emit": CH("water")},
        "rim_glow":    {"rgb": CH("rim_light"), "emit": CH("rim_light")},
        "gate_body":   {"rgb": CH("iron_dark")},
        "gate_frame":  {"rgb": CH("ground"), "family": "speckled"},
        "fin_dark":    {"rgb": CH("iron_dark")},
        "shaft_wall":  {"rgb": CH("ground")},
        "pipe_metal":  {"rgb": CH("pipe"), "family": "panel"},
        "rail_dark":   {"rgb": CH("iron_dark"), "family": "panel"},
        "crate_wood":  {"rgb": _dim(CH("wood"), 0.65), "family": "wood"},
        "crate_dark":  {"rgb": _dim(CH("wood"), 0.45), "family": "wood"},
        "barrel_iron": {"rgb": CH("pipe")},
        "wood_plank":  {"rgb": CH("wood"), "family": "wood"},
        "stem_dark":   {"rgb": CH("stem_dead")},
        "truss_rust":  {"rgb": CH("rust")},
        "moss_pad":    {"rgb": CH("moss"), "emit": CH("flora")},
        "sprig_teal":  {"rgb": CH("moss"), "emit": CH("flora")},
        "lamp_amber":  {"rgb": CH("lamp"), "emit": CG("warning_amber")},
    }, emit_strength={"drum_water": 0.5, "rim_glow": 1.6, "moss_pad": 0.35,
                      "sprig_teal": 1.6, "lamp_amber": 2.2})
    for _t, _c in SEC_COLORS.items():
        pl.register_parts({"gsign_" + _t: {"rgb": _c, "emit": _c}},
                          emit_strength={"gsign_" + _t: 0.55})


# ---- area detail painters (pixel detail lives HERE, never in geometry) ------------------
def _paint_drum_wall(tile, mask, base, isl, px_per_m):
    """Riveted plate courses on the drum skin; portholes on the quarter staves
    only (one per segment made a polka-dot ring); seep streaks run DOWN."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    seg = int(isl.get("seg") or 0)
    rng = _face_rng(isl, "drum%d" % seg)
    course = max(4, int(round(1.15 * px_per_m)))          # DRUM_COURSE in texels
    for row in range(course, ph - 1, course):             # course line + rivet dots
        tile[row, :] = _shadow(base, 0.45)
        for x in range(2, max(3, pw - 2), max(3, min(course // 2, max(2, pw // 2)))):
            tile[min(row + 1, ph - 1), min(x, pw - 1)] = _lift(base, 0.3)
    if seg % 2 == 0 and pw > 6:                           # seam on alternating staves,
        x = 2 + (seg * 5) % max(1, pw - 4)                # never a bar per segment edge
        tile[1:-1, min(x, pw - 1)] = _shadow(base, 0.35)
    for _ in range(1 + pw // 10):                         # seep streaks fall from high rows
        x = rng.randrange(1, max(2, pw - 1))
        y_top = ph - 2 - rng.randrange(0, max(1, ph // 3))
        tile[max(1, y_top - rng.randrange(4, 12)):y_top, x] = _shadow(base, 0.45)
    if seg % 4 == 1 and ph > 12 and pw > 12:              # porthole, upper third
        cy, cx = (2 * ph) // 3, pw // 2
        r = min(max(3, course // 2), cy - 1, cx - 1, ph - cy - 2, pw - cx - 2)
        for yy in range(cy - r, cy + r + 1):
            for xx in range(cx - r, cx + r + 1):
                d2 = (yy - cy) ** 2 + (xx - cx) ** 2
                if d2 <= r * r:
                    tile[yy, xx] = CH("water_deep") if d2 <= (r - 1) ** 2 \
                        else CH("rust")


def _paint_gate_face(tile, mask, base, isl, px_per_m):
    """Dark slab door: frame border, plate courses, rust bleeding DOWN from the top."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    rng = _face_rng(isl, "gate")
    if ph < 6 or pw < 6:
        return
    tile[0:2, :] = _shadow(base, 0.5); tile[-2:, :] = _shadow(base, 0.5)
    tile[:, 0:2] = _shadow(base, 0.5); tile[:, -2:] = _shadow(base, 0.5)
    for row in range(ph // 4, ph - 2, max(3, ph // 4)):
        tile[row, 2:-2] = _shadow(base, 0.38)
    rust = _dim(CH("rust"), 0.85)
    for x in range(2, pw - 2):
        depth = rng.randrange(2, max(3, ph // 3))
        for k in range(depth):
            y = ph - 3 - k
            if y < 2:
                break
            tile[y, x] = _shade(rust, 1.0 - 0.4 * k / depth)


DETAIL_DRUMWALL = pl.register_detail("drum_wall", _paint_drum_wall)
DETAIL_GATEFACE = pl.register_detail("gate_face", _paint_gate_face)
DETAIL_WOODGRAIN = pl.register_detail("wood_grain", _paint_wood_grain)
DETAIL_CRATE = pl.register_detail("crate_face", _paint_crate_face)
DETAIL_METALPANEL = pl.register_detail("metal_panel", _paint_metal_panel)
DETAIL_BARREL = pl.register_detail("barrel_body", _paint_barrel)
DETAIL_TRUSS = pl.register_detail("truss_wash", _paint_truss)


# ---- unique pieces (Builder; Z-up local; deck pieces: +X tangent, +Y radial-out) --------
def build_drum_lower():
    b = Builder()
    b.ngon_prism((0, 0), DRUM_R, DRUM_R, DRUM_NECK_Y0 - DRUM_BOTTOM, "drum_iron",
                 sides=16, cap_bottom=False, detail=DETAIL_DRUMWALL)
    return b.finish("DrumLower")

def build_drum_upper():
    b = Builder()
    b.ngon_prism((0, 0), DRUM_R, DRUM_R, DRUM_TOP - DRUM_NECK_Y1, "drum_iron",
                 sides=16, cap_top=False, cap_bottom=False, detail=DETAIL_DRUMWALL)
    return b.finish("DrumUpper")

def build_drum_neck():
    b = Builder()
    h = DRUM_NECK_Y1 - DRUM_NECK_Y0
    b.ngon_prism((0, 0), 1.62, 1.62, 0.34, "drum_flange", sides=12, z0=-0.34)
    b.ngon_prism((0, 0), 1.62, 1.62, 0.34, "drum_flange", sides=12, z0=h)
    b.ngon_prism((0, 0), 0.85, 0.85, h, "pipe_metal", sides=10,
                 cap_top=False, cap_bottom=False)
    for k in range(4):
        ang = math.tau * (k + 0.5) / 4.0
        b.box((math.cos(ang) * 1.05, math.sin(ang) * 1.05, h / 2.0),
              (0.22, 0.22, h - 0.4), "truss_rust")
    return b.finish("DrumNeck")

def build_drum_crown():
    """Z-up half of the wash drum's crown: reservoir water, rail posts, the collar.
    Named WashDrumCrown because the archetype library already ships a larger,
    unrelated DrumCrown — two pieces may not answer to one name."""
    b = Builder()
    b.ngon_prism((0, 0), DRUM_R - 0.18, DRUM_R - 0.18, 0.06, "drum_water", sides=16, z0=-0.58)
    b.ngon_prism((0, 0), 1.02, 1.02, 0.22, "drum_flange", sides=10, z0=0.12)
    for k in range(8):
        ang = math.tau * k / 8.0
        b.box((math.cos(ang) * DRUM_R, math.sin(ang) * DRUM_R, 0.52),
              (0.08, 0.08, 0.85), "drum_rail")
    return b.finish("WashDrumCrown")

def build_gate_slab():
    b = Builder()
    b.box((0, 0, GATE_H / 2.0), (GATE_W, 0.55, GATE_H), "gate_body", detail=DETAIL_GATEFACE)
    for sx in (-1, 1):
        b.box((sx * (GATE_W / 2.0 + 0.25), -0.1, GATE_H / 2.0 + 0.2),
              (0.5, 0.8, GATE_H + 0.8), "gate_frame")
    b.box((0, -0.1, GATE_H + 0.45), (GATE_W + 1.0, 0.8, 0.6), "gate_frame")
    return b.finish("GateSlab")

def build_gate_sign(t):
    b = Builder()
    b.box((0, 0, 0.85), (GATE_W * 0.72, 0.16, GATE_H * 0.26), "gsign_" + t)
    return b.finish("GateSign_" + t)

def build_fin():
    b = Builder()
    b.box((0, 0, WALL_FIN_H / 2.0), (WALL_FIN_W, 0.5, WALL_FIN_H), "fin_dark",
          detail=DETAIL_METALPANEL)
    b.box((0.9, -0.35, WALL_FIN_H / 2.0 - 0.2), (0.26, 0.26, WALL_FIN_H - 1.2), "pipe_metal")
    return b.finish("Fin")

def build_shaft_panel():
    b = Builder()
    b.box((0, 0, 7.0), (math.tau * SHAFT_R / 24.0 * 1.03, 0.6, 14.0), "shaft_wall",
          detail=DETAIL_METALPANEL)
    return b.finish("ShaftPanel")

def build_term_panel():
    b = Builder()
    b.box((0, 0, 0.3), (0.9, 0.12, 0.6), "screen", detail=DETAIL_SCREEN)
    return b.finish("TermPanel")

def build_rail_seg():
    b = Builder()
    b.box((0, 0, 0.45), (0.07, 0.07, 0.9), "rail_dark")
    b.box((0, 0, 0.88), (1.75, 0.05, 0.05), "rail_dark")
    return b.finish("RailSeg")

def build_rim_rib():
    b = Builder()
    b.box((0, 0, -0.72), (1.8, 0.06, 1.1), "fin_dark")
    b.box((1.4, 0.04, -1.6), (0.28, 0.05, 2.2), "truss_rust")
    return b.finish("RimRib")

def build_crate(name, sz, part):
    b = Builder()
    b.box((0, 0, sz / 2.0), (sz, sz, sz), part, detail=DETAIL_CRATE)
    return b.finish(name)

def build_barrel():
    b = Builder()
    b.ngon_prism((0, 0), 0.26, 0.26, 0.66, "barrel_iron", sides=10, detail=DETAIL_BARREL)
    return b.finish("Barrel")

def build_shrine():
    b = Builder()
    b.box((0, 0, 0.09), (0.7, 0.5, 0.18), "crate_dark", detail=DETAIL_CRATE)
    b.box((0.12, 0.0, 0.26), (0.34, 0.3, 0.16), "crate_wood", detail=DETAIL_CRATE)
    b.box((-0.14, 0.1, 0.32), (0.1, 0.1, 0.36), "screen", detail=DETAIL_SCREEN)
    return b.finish("Shrine")

def build_moss_tuft():
    b = Builder()
    b.ngon_prism((0, 0), 0.58, 0.62, 0.04, "moss_pad", sides=10, cap_bottom=False)
    rng = random.Random(733)
    for k in range(3):
        h = 0.4 + rng.random() * 0.45
        b.ngon_prism((rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.2)), 0.02, 0.05, h,
                     "sprig_teal", sides=5)
    return b.finish("MossTuft")

def build_truss_rib():
    b = Builder()
    b.box((0, 0, 0), (0.24, 6.5, 0.5), "truss_rust", detail=DETAIL_TRUSS)
    return b.finish("TrussRib")

def build_truss_post():
    b = Builder()
    b.box((0, 0, 0.5), (0.14, 0.14, 1.0), "rail_dark")
    b.box((0, 0, 1.12), (0.18, 0.18, 0.22), "lamp_amber")
    return b.finish("TrussPost")

def build_valve_wheel():
    """Annulus-native: an UPRIGHT wheel facing local -Y; spokes cross in the ring's
    XZ plane. Mount with rz = atan2(-cos a, -sin a) to face radially at angle a."""
    b = Builder()
    b.annulus((0, 0, 0), 0.30, 0.20, 0.07, "truss_rust", sides=10)
    b.box((0, 0.005, 0), (0.44, 0.05, 0.05), "truss_rust")
    b.box((0, 0.005, 0), (0.05, 0.05, 0.44), "truss_rust")
    return b.finish("ValveWheel")

def build_wood_plank():
    b = Builder()
    b.box((0, 0, 0.025), (1.35, 1.7, 0.05), "wood_plank", detail=DETAIL_WOODGRAIN)
    return b.finish("WoodPlank")

def build_flure_ledge():
    b = Builder()
    b.box((0, 0, -0.13), (3.0, LEDGE_LANE_W, 0.24), "wood_plank", detail=DETAIL_WOODGRAIN)
    for sx in (-0.9, 0.9):
        b.box((sx, -0.4, -0.5), (0.2, LEDGE_LANE_W * 0.7, 0.16), "rail_dark")
    for sx, sy in ((-2.0, 0.2), (1.9, 0.5), (2.4, 0.8)):
        b.box((sx, sy, -0.24), (0.75, 1.1, 0.1), "wood_plank", detail=DETAIL_WOODGRAIN)
    rng = random.Random(62)
    for k in range(6):
        h = 0.35 + rng.random() * 0.5
        b.ngon_prism((rng.uniform(-0.7, 0.7), rng.uniform(-1.4, -0.4)), 0.018, 0.03, h,
                     "stem_dark", sides=5)
    return b.finish("FlureLedge")

def build_pad_ledge():
    b = Builder()
    b.box((0, 0, -0.13), (1.6, LEDGE_LANE_W, 0.24), "wood_plank", detail=DETAIL_WOODGRAIN)
    b.box((0, -0.4, -0.5), (0.2, LEDGE_LANE_W * 0.7, 0.16), "rail_dark")
    b.box((1.35, -0.65, -0.22), (0.7, 1.0, 0.1), "wood_plank", detail=DETAIL_WOODGRAIN)
    return b.finish("PadLedge")


# ---- the register: every piece this district owns, as zero-arg builders -----------------
# (the glow annulus CrownRings was cut: the runtime continuous crown TUBE, plate 1,
# replaced the dashed ring)
BUILDERS = [
    build_drum_lower, build_drum_upper, build_drum_neck, build_drum_crown,
    build_gate_slab,
] + [functools.partial(build_gate_sign, t) for t in SECTION_TYPES] + [
    build_fin, build_shaft_panel, build_term_panel, build_rail_seg, build_rim_rib,
    functools.partial(build_crate, "CrateA", 0.55, "crate_wood"),
    functools.partial(build_crate, "CrateB", 0.72, "crate_dark"),
    build_barrel, build_shrine, build_moss_tuft,
    build_truss_rib, build_truss_post, build_valve_wheel,
    build_wood_plank, build_flure_ledge, build_pad_ledge,
]

# Texel density per piece; anything unlisted paints at 32 px/m.
PX_OVERRIDES = {"DrumLower": 12.0, "DrumUpper": 12.0, "GateSlab": 16.0, "ShaftPanel": 8.0,
                "WashDrumCrown": 16.0, "FlureLedge": 24.0, "PadLedge": 24.0,
                "TrussRib": 24.0}


def build_all():
    """Build every piece into the current scene. Returns {name: object}."""
    pieces = {}
    for fn in BUILDERS:
        ob = fn()
        pieces[ob.name] = ob
    return pieces


def texture_all(pieces, objx, painted):
    """Paint + UV every built piece at its authored texel density; painted/ wins."""
    for name, ob in pieces.items():
        pl.texture_object(ob, objx, px_per_m=PX_OVERRIDES.get(name, 32.0),
                          painted_dir=painted)
