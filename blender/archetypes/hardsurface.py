# HARD-SURFACE KIT + REWORKED MECHANICAL PIECES — exec-included by
# build_archetype_pieces.py AFTER organic_v2.py (shares _flat_mat/_bev_box/etc.),
# OVERRIDING the painted-primitive builders for the mechanical props.
#
# THE LAW (director): a prop must read as something MADE — assembled from parts —
# never shapes slapped together. The kit encodes the machining vocabulary:
#   - CHAMFER everything: every helper bevels its edges (light catching chamfers
#     is the single strongest "manufactured" cue).
#   - ASSEMBLY LOGIC: parts join through visible connections — flanges with bolt
#     rings, brackets, straps, hinge knuckles — and everything stands on explicit
#     feet or mounts. Nothing floats; nothing butt-joints bare.
#   - RECESSED ACTIVE FACES: screens, signs, membranes sit INSIDE frames, never
#     painted onto a slab.
#   - OPEN BORES: a pipe end is a tube you can see into, not a capped cylinder.
# Colors: palette authority only (_flat_mat converts sRGB->linear).

# The modelling vocabulary itself lives in paintlib.meshkit, shared with every
# district's piece file so a channels prop and a stacks prop are built the same way.
from paintlib.meshkit import (
    _srgb_lin, _flat_mat, _skin_growth, _stud_spheres, _bev_box, _torus_xz,
    _hs_axis, _hs_tag, hs_prism, hs_tube, hs_torus, hs_bolts, hs_frame,
    hs_inset_panel, hs_sphere, _hs_finish, _bev_box_r, _hex_holes, _honeycomb,
)
import bmesh as _bmesh
import zlib as _zlib
import random as _random

def build_pipe():
    """A pipe SEGMENT that reads as plumbing hardware: an open-bored barrel with
    bolted flanges at both ends, seated on two cradle saddles with foot plates,
    a valve boss + spoked wheel on the crown. Assembly, not a capped cylinder."""
    bm = _bmesh.new()
    M_PIPE, M_DARK, M_RUST = 0, 1, 2
    hs_prism(bm, (0, 0, 0.62), 0.26, 0.26, 1.3, M_PIPE, sides=12, bevel=0.02, axis='X')
    for sx in (-0.72, 0.72):
        hs_tube(bm, (sx, 0, 0.62), 0.30, 0.19, 0.12, M_DARK, sides=12, axis='X')
        hs_prism(bm, (sx * 0.9, 0, 0.62), 0.36, 0.36, 0.08, M_RUST, sides=12,
                 bevel=0.018, axis='X')
        hs_bolts(bm, (sx * 0.9 + (0.05 if sx > 0 else -0.05), 0, 0.62), 0.30, 6,
                 M_DARK, axis='X')
    for sx in (-0.4, 0.4):                                     # cradle saddles + feet
        _bev_box(bm, (sx, 0, 0.28), (0.14, 0.5, 0.24), M_DARK, bevel=0.02)
        _bev_box(bm, (sx, 0, 0.05), (0.2, 0.6, 0.1), M_RUST, bevel=0.02)
    hs_prism(bm, (0.1, 0, 0.94), 0.07, 0.09, 0.14, M_DARK, sides=8, bevel=0.015)
    hs_torus(bm, (0.1, 0, 1.05), 0.13, 0.028, M_RUST, major_segs=10, minor_segs=6, axis='Z')
    for i in range(4):                                         # wheel spokes
        a = math.tau * i / 4.0
        _bev_box(bm, (0.1 + 0.065 * math.cos(a), 0.065 * math.sin(a), 1.05),
                 (abs(0.13 * math.cos(a)) + 0.03, abs(0.13 * math.sin(a)) + 0.03, 0.03),
                 M_RUST, bevel=0.008)
    return _hs_finish("Pipe", bm, [
        _flat_mat("hs_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("hs_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("hs_rust_m", CH("rust"), rough=0.8)])


def build_terminal():
    """A data terminal that reads as a MANUFACTURED cabinet: chamfered chassis on
    four feet, the terminal-green screen RECESSED in its frame, a keyboard shelf
    with a lip, side heat ribs, and a cable boss into the floor."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_SCREEN = 0, 1, 2
    for (sx, sy) in ((-0.18, -0.14), (0.18, -0.14), (-0.18, 0.14), (0.18, 0.14)):
        _bev_box(bm, (sx, sy, 0.04), (0.09, 0.09, 0.08), M_IRON, bevel=0.012)
    _bev_box(bm, (0, 0, 0.66), (0.5, 0.4, 1.16), M_DARK, bevel=0.025)      # chassis
    hs_inset_panel(bm, (0, -0.21, 0.96), (0.4, 0.05, 0.34), 0.05, 0.035,
                   M_IRON, M_SCREEN, bevel=0.012)                          # recessed screen
    _bev_box(bm, (0, -0.26, 0.72), (0.42, 0.14, 0.05), M_IRON, bevel=0.014)  # keyboard shelf
    _bev_box(bm, (0, -0.325, 0.735), (0.42, 0.02, 0.035), M_DARK, bevel=0.008)  # shelf lip
    for i in range(3):                                                     # heat ribs
        _bev_box(bm, (0.265, 0, 0.55 + i * 0.16), (0.03, 0.3, 0.05), M_IRON, bevel=0.008)
    hs_prism(bm, (0.12, 0.23, 0.18), 0.05, 0.05, 0.3, M_IRON, sides=8,
             bevel=0.012, axis='Y')                                        # cable boss
    hs_bolts(bm, (0, -0.201, 1.21), 0.0, 1, M_DARK, bolt_r=0.02, bolt_h=0.03, axis='Y')
    return _hs_finish("Terminal", bm, [
        _flat_mat("hs_term_dark_m", _dim(CH("iron_dark"), 0.9), rough=0.62),
        _flat_mat("hs_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_screen_m", _dim(CG("terminal_green"), 0.5), CG("terminal_green"), 1.4)])


# ---- fan-out reworks (drafted against the kit + exemplars, verified) --------------------

def build_junction():
    """A pipe junction MANIFOLD for the Channels plumbing (~0.9 m): a chamfered
    central boss riding a pedestal on a bolted base plate, with three stub
    lines (both X sides + front) that each leave through a bolted flange and
    end in an OPEN bore mouth — every joint is flanged, so it reads assembled."""
    bm = _bmesh.new()
    M_PIPE, M_DARK, M_RUST = 0, 1, 2
    _bev_box(bm, (0, 0, 0.035), (0.66, 0.66, 0.07), M_RUST, bevel=0.018)     # base plate
    hs_bolts(bm, (0, 0, 0.075), 0.40, 4, M_DARK, bolt_r=0.03, bolt_h=0.06,
             phase=math.tau / 8)                                             # corner bolts
    _bev_box(bm, (0, 0, 0.23), (0.28, 0.28, 0.34), M_DARK, bevel=0.02)       # pedestal
    _bev_box(bm, (0, 0, 0.62), (0.5, 0.5, 0.5), M_PIPE, bevel=0.03)          # central boss
    for sx in (-1, 1):                                                       # side lines (X)
        hs_prism(bm, (sx * 0.36, 0, 0.62), 0.15, 0.15, 0.26, M_PIPE, sides=12,
                 bevel=0.018, axis='X')
        hs_prism(bm, (sx * 0.46, 0, 0.62), 0.2, 0.2, 0.06, M_RUST, sides=12,
                 bevel=0.015, axis='X')                                      # stub flange
        hs_bolts(bm, (sx * 0.50, 0, 0.62), 0.17, 4, M_DARK, axis='X')
        hs_tube(bm, (sx * 0.53, 0, 0.62), 0.17, 0.11, 0.12, M_DARK, sides=12, axis='X')
    hs_prism(bm, (0, -0.36, 0.62), 0.15, 0.15, 0.26, M_PIPE, sides=12,
             bevel=0.018, axis='Y')                                          # front line (-Y)
    hs_prism(bm, (0, -0.46, 0.62), 0.2, 0.2, 0.06, M_RUST, sides=12,
             bevel=0.015, axis='Y')
    hs_bolts(bm, (0, -0.50, 0.62), 0.17, 4, M_DARK, axis='Y')
    hs_tube(bm, (0, -0.53, 0.62), 0.17, 0.11, 0.12, M_DARK, sides=12, axis='Y')
    hs_prism(bm, (0, 0, 0.885), 0.11, 0.11, 0.05, M_RUST, sides=8, bevel=0.012)  # access cap
    hs_bolts(bm, (0, 0, 0.91), 0.0, 1, M_DARK, bolt_r=0.024, bolt_h=0.04)        # cap stud
    return _hs_finish("Junction", bm, [
        _flat_mat("hs_junc_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("hs_junc_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("hs_junc_rust_m", CH("rust"), rough=0.8)])

def build_class_gate():
    """A checkpoint CLASS GATE (~2.5 m) — the clearance-scan street furniture of
    the Tag Day queues — that reads as INSTALLED: two chamfered posts bolted down
    on foot plates, a channel lintel seated over the post tops, five hex bars
    socketed into boss blocks at floor and lintel, and the amber clearance
    indicator recessed in its bezel on the lintel face."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_AMBER = 0, 1, 2
    for sx in (-0.9, 0.9):                                     # posts on bolted foot plates
        _bev_box(bm, (sx, 0, 0.035), (0.34, 0.34, 0.07), M_IRON, bevel=0.015)
        hs_bolts(bm, (sx, 0, 0.07), 0.13, 4, M_DARK, phase=math.pi / 4.0)
        _bev_box(bm, (sx, 0, 1.22), (0.16, 0.16, 2.3), M_DARK, bevel=0.025)
    _bev_box(bm, (0, 0, 2.37), (2.0, 0.2, 0.24), M_IRON, bevel=0.02)   # lintel channel over posts
    for bx in (-0.6, -0.3, 0.0, 0.3, 0.6):                     # bars seated in socket bosses
        _bev_box(bm, (bx, 0, 0.10), (0.1, 0.1, 0.2), M_IRON, bevel=0.01)
        hs_prism(bm, (bx, 0, 1.125), 0.03, 0.03, 1.9, M_DARK, sides=6, bevel=0.008)
        _bev_box(bm, (bx, 0, 2.15), (0.1, 0.1, 0.2), M_IRON, bevel=0.01)
    hs_inset_panel(bm, (0, -0.1, 2.37), (0.3, 0.06, 0.12), 0.03, 0.03,
                   M_IRON, M_AMBER, bevel=0.01)                # recessed clearance indicator
    return _hs_finish("ClassGate", bm, [
        _flat_mat("hs_gate_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_gate_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_gate_amber_m", _dim(CG("warning_amber"), 0.6),
                  CG("warning_amber"), 1.6)])

def build_shortcut_gate():
    """A one-way shortcut hatch (~1.6 m): an iron jamb frame stud-bolted at the
    corners, the WOOD door leaf RECESSED inside it, two hinge knuckles with pins
    riding the left jamb edge, and a wooden drop-bar seated in two U-brackets
    whose seats reach back through the reveal and root in the leaf — barred from
    this side, shoved open from the other. Reads as ASSEMBLED: studs pin the
    frame, knuckles carry the leaf, the bar rests in visible bracket seats that
    tie back to the door face."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_WOOD = 0, 1, 2
    hs_frame(bm, (0, 0, 0.75), 1.3, 1.5, 0.14, 0.18, M_IRON, bevel=0.02)   # jamb frame, base z=0
    for (sx, sz) in ((-0.58, 0.07), (0.58, 0.07), (-0.58, 1.43), (0.58, 1.43)):
        hs_bolts(bm, (sx, -0.1, sz), 0.0, 1, M_DARK, bolt_r=0.024, bolt_h=0.05,
                 axis='Y')                                                 # corner studs pin the joints
    hs_inset_panel(bm, (0, 0, 0.75), (1.06, 0.1, 1.26), 0.07, 0.035,
                   M_IRON, M_WOOD, bevel=0.015)                            # recessed wood leaf
    for hz in (0.4, 1.1):                                                  # hinge knuckles + pins
        hs_prism(bm, (-0.65, -0.09, hz), 0.045, 0.045, 0.14, M_DARK, sides=8,
                 bevel=0.012, axis='Z')
        hs_bolts(bm, (-0.65, -0.09, hz + 0.09), 0.0, 1, M_DARK, bolt_r=0.02,
                 bolt_h=0.05, axis='Z')
    _bev_box(bm, (0.28, -0.16, 0.78), (0.9, 0.07, 0.1), M_WOOD, bevel=0.015)  # drop-bar
    for xb in (0.15, 0.55):                          # U-brackets: seat rooted in the leaf + 2 cheeks
        _bev_box(bm, (xb, -0.1, 0.71), (0.12, 0.25, 0.05), M_IRON, bevel=0.01)
        _bev_box(bm, (xb, -0.115, 0.78), (0.12, 0.03, 0.14), M_IRON, bevel=0.008)
        _bev_box(bm, (xb, -0.205, 0.78), (0.12, 0.03, 0.14), M_IRON, bevel=0.008)
    return _hs_finish("ShortcutGate", bm, [
        _flat_mat("hs_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("hs_wood_m", CH("wood"), rough=0.9)])

def build_hide_slot():
    """A concealment alcove — the hard-surface CONCEAL_FULL tight hide (the
    detection system's shelter tier, kin to the Capbage flora hide): an iron
    shell ASSEMBLED hollow — two full-height side columns, a crown, a plinth,
    and a back slab on two rust foot skids — so the deep framed recess on -Y
    opens into a REAL cavity whose near-black back panel swallows light; a worn
    rust sill plate at the lip floor, bolted seam columns flanking the frame,
    and vent rib boxes at the crown. The darkness inside is the feature."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_RUST, M_VOID = 0, 1, 2, 3
    for sx in (-0.36, 0.36):                                   # foot skids
        _bev_box(bm, (sx, 0, 0.05), (0.26, 0.78, 0.10), M_RUST, bevel=0.015)
    # shell (1.1 x 0.7 x 2.0 overall) is assembled HOLLOW — a solid box would
    # occlude the recess panel; the cavity makes the darkness real
    _bev_box(bm, (0, 0.25, 1.10), (1.1, 0.2, 2.0), M_IRON, bevel=0.025)      # back slab
    for sx in (-0.44, 0.44):                                                 # side columns
        _bev_box(bm, (sx, -0.05, 1.10), (0.22, 0.6, 2.0), M_IRON, bevel=0.025)
    _bev_box(bm, (0, -0.05, 1.975), (0.66, 0.6, 0.25), M_IRON, bevel=0.025)  # crown
    _bev_box(bm, (0, -0.05, 0.245), (0.66, 0.6, 0.29), M_IRON, bevel=0.025)  # plinth
    hs_inset_panel(bm, (0, -0.36, 1.12), (0.9, 0.08, 1.7), 0.12, 0.3,
                   M_DARK, M_VOID, bevel=0.02)                 # deep light-swallowing slot
    _bev_box(bm, (0, -0.385, 0.41), (0.92, 0.17, 0.05), M_RUST, bevel=0.01)  # worn sill
    for sx in (-0.485, 0.485):                                 # bolt seam columns
        hs_bolts(bm, (sx, -0.37, 1.10), 0.78, 2, M_DARK, axis='Y', phase=math.pi / 2)
        hs_bolts(bm, (sx, -0.37, 1.10), 0.30, 2, M_DARK, axis='Y', phase=math.pi / 2)
    for sx in (-1.0, 1.0):                                     # crown vent rib boxes
        _bev_box(bm, (sx * 0.56, 0, 1.92), (0.06, 0.30, 0.16), M_DARK, bevel=0.01)
        for dz in (-0.04, 0.04):
            _bev_box(bm, (sx * 0.60, 0, 1.92 + dz), (0.04, 0.24, 0.03), M_RUST, bevel=0.008)
    return _hs_finish("HideSlot", bm, [
        _flat_mat("hs_hide_iron_m", CH("iron"), rough=0.6),
        _flat_mat("hs_hide_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_hide_rust_m", CH("rust"), rough=0.85),
        _flat_mat("hs_hide_void_m", _dim(CH("iron_dark"), 0.35), rough=0.95)])

def build_forage_cache():
    """A forage CACHE — a lidded supply basin stashed along the corridor forage
    routes: an octagonal chamfered drum collared by an open rim ring at the
    mouth, its lid resting AJAR on the rim so the teal preservation shimmer
    glows up through the crescent gap. It reads as ASSEMBLED: two bolted side
    straps and a bolted front hasp block bind rim to body, and four corner
    foot pads peek from under the drum base."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_TEAL = 0, 1, 2
    for (sx, sy) in ((-0.38, -0.38), (0.38, -0.38), (-0.38, 0.38), (0.38, 0.38)):
        _bev_box(bm, (sx, sy, 0.04), (0.16, 0.16, 0.08), M_IRON, bevel=0.012)  # corner foot pads
    hs_prism(bm, (0, 0, 0.25), 0.55, 0.55, 0.5, M_DARK, sides=8, bevel=0.02)   # basin drum
    hs_tube(bm, (0, 0, 0.5), 0.58, 0.5, 0.08, M_IRON, sides=8)                 # rim collar, open mouth
    hs_prism(bm, (0, 0, 0.53), 0.48, 0.48, 0.02, M_TEAL, sides=8, bevel=0.008)  # shimmer disc just under the mouth
    hs_prism(bm, (0.38, 0, 0.6), 0.54, 0.54, 0.06, M_DARK, sides=8, bevel=0.02)  # lid slid WIDE ajar — the teal crescent shows
    _bev_box(bm, (0.3, 0, 0.655), (0.2, 0.06, 0.05), M_IRON, bevel=0.01)       # lid handle bar
    for sx in (-0.55, 0.55):                                                   # side straps, a bolt each
        _bev_box(bm, (sx, 0, 0.25), (0.06, 0.16, 0.5), M_IRON, bevel=0.012)
        hs_bolts(bm, (sx * 1.06, 0, 0.42), 0.0, 1, M_DARK, bolt_r=0.024,
                 bolt_h=0.05, axis='X')
    _bev_box(bm, (0, -0.55, 0.46), (0.14, 0.12, 0.14), M_IRON, bevel=0.014)    # front hasp block
    hs_bolts(bm, (0, -0.62, 0.46), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.04, axis='Y')
    return _hs_finish("ForageCache", bm, [
        _flat_mat("hs_cache_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_cache_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_cache_teal_m", _dim(CH("porthole_glass"), 0.8),
                  CH("porthole_glass"), 2.4)])

def build_water_control():
    """A channels (Plumbing Power Project) water-control valve column that reads
    as INSTALLED plumbing gear: a bolted-down square base plate, a chamfered
    octagonal valve column carrying a bolted flange collar at mid-height, a
    spoked hand-wheel on a hub crown, and the water-level gauge RECESSED in its
    frame on a mounting pad seated against the column's -Y face."""
    bm = _bmesh.new()
    M_DARK, M_RUST, M_IRON, M_GAUGE = 0, 1, 2, 3
    _bev_box(bm, (0, 0, 0.03), (0.5, 0.5, 0.06), M_IRON, bevel=0.02)       # base plate
    hs_bolts(bm, (0, 0, 0.06), 0.283, 4, M_DARK, phase=math.pi / 4)        # corner bolts
    hs_prism(bm, (0, 0, 0.485), 0.12, 0.15, 0.85, M_DARK, sides=8, bevel=0.02)  # column
    hs_prism(bm, (0, 0, 0.485), 0.18, 0.18, 0.06, M_IRON, sides=8, bevel=0.015)  # flange collar
    hs_bolts(bm, (0, 0, 0.515), 0.15, 6, M_DARK, bolt_r=0.022, bolt_h=0.045)  # collar bolt ring
    hs_prism(bm, (0, 0, 1.01), 0.055, 0.07, 0.20, M_RUST, sides=8, bevel=0.012)  # wheel hub
    hs_torus(bm, (0, 0, 1.10), 0.19, 0.03, M_RUST, major_segs=12, minor_segs=6, axis='Z')
    for i in range(4):                                                     # wheel spokes
        a = math.tau * i / 4.0
        _bev_box(bm, (0.095 * math.cos(a), 0.095 * math.sin(a), 1.10),
                 (abs(0.19 * math.cos(a)) + 0.035, abs(0.19 * math.sin(a)) + 0.035, 0.028),
                 M_RUST, bevel=0.008)
    hs_bolts(bm, (0, 0, 1.11), 0.0, 1, M_DARK, bolt_r=0.024, bolt_h=0.04)  # hub cap nut
    _bev_box(bm, (0, -0.125, 0.70), (0.16, 0.08, 0.16), M_IRON, bevel=0.012)  # gauge mounting pad
    hs_inset_panel(bm, (0, -0.185, 0.70), (0.14, 0.05, 0.14), 0.03, 0.025,
                   M_IRON, M_GAUGE, bevel=0.012)                           # recessed gauge
    hs_bolts(bm, (0, -0.21, 0.755), 0.0, 1, M_DARK, bolt_r=0.014, bolt_h=0.025, axis='Y')
    return _hs_finish("WaterControl", bm, [
        _flat_mat("hs_wc_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("hs_wc_rust_m", CH("rust"), rough=0.8),
        _flat_mat("hs_wc_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_wc_gauge_m", _dim(CH("water"), 0.8), CH("water"), 1.4)])

def build_membrane():
    """An organic GATE held in a MACHINE frame (~1.5 m): the living membrane —
    a faint-glowing teal disc — sits RECESSED behind the front rim of a bolted
    upright iron ring, which is clamped by two chamfered A-feet (splayed base
    block + grip leg, each pinned with a stud) standing on a base plate. The
    biology is the panel; everything holding it reads as assembled ironwork."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_MEM = 0, 1, 2
    hs_torus(bm, (0, 0, 0.75), 0.55, 0.07, M_IRON, major_segs=16, minor_segs=8,
             axis='Y')                                                     # upright ring
    hs_bolts(bm, (0, -0.08, 0.75), 0.55, 8, M_DARK, axis='Y')              # front-face bolt ring
    hs_prism(bm, (0, -0.025, 0.75), 0.5, 0.5, 0.03, M_MEM, sides=12,
             bevel=0.01, axis='Y')                                         # membrane, 0.03 behind ring front
    for sx in (-0.42, 0.42):                                               # A-feet: base block + grip leg
        _bev_box(bm, (sx, 0, 0.14), (0.16, 0.34, 0.18), M_DARK, bevel=0.02)
        _bev_box(bm, (sx, 0, 0.42), (0.12, 0.16, 0.5), M_DARK, bevel=0.02)
        hs_bolts(bm, (math.copysign(0.48, sx), 0, 0.40), 0.0, 1, M_DARK,
                 bolt_r=0.02, bolt_h=0.04, axis='X')                       # grip stud into the ring
    _bev_box(bm, (0, 0, 0.025), (1.1, 0.5, 0.05), M_DARK, bevel=0.02)      # base plate
    return _hs_finish("Membrane", bm, [
        _flat_mat("hs_gate_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_gate_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_membrane_m", _dim(CH("water_deep"), 1.1), CH("water_deep"), 0.5)])

def build_porthole():
    """A drum PORTHOLE (upright, faces -Y, mounts on a wall): the channels'
    glass-and-rust viewing hardware. Reads as ASSEMBLED marine plumbing — a
    bolted rim torus over a wall-plane backing flange, the emissive glass disc
    RECESSED inside the rim, a 4-spoke dogging wheel on a spindle boss proud of
    the face, hinge lugs right / latch lug left carrying the swing."""
    bm = _bmesh.new()
    M_RUST, M_DARK, M_GLASS = 0, 1, 2
    hs_tube(bm, (0, 0.05, 0.75), 0.64, 0.5, 0.05, M_DARK, sides=16, axis='Y')   # backing flange at the wall plane
    hs_torus(bm, (0, 0, 0.75), 0.5, 0.09, M_RUST, major_segs=16, minor_segs=8,
             axis='Y')                                                          # rim drum
    hs_prism(bm, (0, 0.04, 0.75), 0.44, 0.44, 0.03, M_GLASS, sides=16,
             bevel=0.01, axis='Y')                                              # glass disc recessed +Y into the rim
    hs_bolts(bm, (0, -0.08, 0.75), 0.5, 8, M_DARK, axis='Y',
             phase=math.pi / 8.0)                                               # rim bolt ring, staggered off the spokes
    hs_prism(bm, (0, -0.06, 0.75), 0.035, 0.035, 0.2, M_DARK, sides=8,
             bevel=0.01, axis='Y')                                              # spindle boss: wheel joins the glass plane
    hs_prism(bm, (0, -0.16, 0.75), 0.07, 0.07, 0.1, M_RUST, sides=8,
             bevel=0.015, axis='Y')                                             # wheel hub, proud on -Y
    _bev_box(bm, (0, -0.15, 0.75), (0.6, 0.035, 0.04), M_RUST, bevel=0.008)     # spoke bar
    _bev_box(bm, (0, -0.15, 0.75), (0.6, 0.035, 0.04), M_RUST,
             rot_y=math.pi / 2.0, bevel=0.008)                                  # crossing spoke bar -> 4 spokes
    hs_bolts(bm, (0, -0.215, 0.75), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.035,
             axis='Y')                                                          # axle stud on the hub
    _bev_box(bm, (0.58, 0, 0.87), (0.12, 0.18, 0.1), M_DARK, bevel=0.015)       # upper hinge lug
    _bev_box(bm, (0.58, 0, 0.63), (0.12, 0.18, 0.1), M_DARK, bevel=0.015)       # lower hinge lug
    _bev_box(bm, (-0.58, 0, 0.75), (0.12, 0.18, 0.1), M_DARK, bevel=0.015)      # latch lug
    return _hs_finish("Porthole", bm, [
        _flat_mat("hs_rust_m", CH("rust"), rough=0.8),
        _flat_mat("hs_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("hs_porthole_glass_m", _dim(CH("porthole_glass"), 0.6),
                  CH("porthole_glass"), 1.6)])

def build_deck_grate():
    """A walkway DECK GRATE — the Channels' standard 2.0 m TILE-MODULE floor inset (Plumbing Power
    Project walkways run over open water): a bolted iron frame around a woven
    two-layer bar grid RECESSED below the tread line, a near-black pit plate
    underneath so the drop reads, corner plates studded at every joint, and a
    lift-handle U-bracket on each end. Assembled flooring, never a textured tile."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_PIT = 0, 1, 2
    for sy in (-0.94, 0.94):                                        # frame bars along X
        _bev_box(bm, (0, sy, 0.06), (2.0, 0.12, 0.12), M_IRON, bevel=0.02)
    for sx in (-0.94, 0.94):                                        # frame bars along Y, butted between
        _bev_box(bm, (sx, 0, 0.06), (0.12, 1.76, 0.12), M_IRON, bevel=0.02)
    for (sx, sy) in ((-0.925, -0.925), (0.925, -0.925), (-0.925, 0.925), (0.925, 0.925)):
        _bev_box(bm, (sx, sy, 0.13), (0.15, 0.15, 0.02), M_IRON, bevel=0.008)  # corner joint plate
        hs_bolts(bm, (sx, sy, 0.155), 0.0, 1, M_DARK, bolt_r=0.024, bolt_h=0.03)
    _bev_box(bm, (0, 0, 0.01), (1.82, 1.82, 0.02), M_PIT, bevel=0.008)         # pit under-plate
    for i in range(8):                                              # woven grid, top 0.04 below frame
        p = -0.735 + i * 0.21
        _bev_box(bm, (0, p, 0.055), (1.84, 0.05, 0.05), M_DARK, bevel=0.01)    # upper layer along X
        _bev_box(bm, (p, 0, 0.035), (0.05, 1.84, 0.05), M_DARK, bevel=0.01)    # lower layer along Y
    for sy in (-0.94, 0.94):                                        # lift-handle U-brackets
        for px in (-0.09, 0.09):
            _bev_box(bm, (px, sy, 0.145), (0.035, 0.035, 0.05), M_DARK, bevel=0.008)
        _bev_box(bm, (0, sy, 0.1775), (0.215, 0.035, 0.035), M_DARK, bevel=0.008)
    return _hs_finish("DeckGrate", bm, [
        _flat_mat("hs_grate_iron_m", CH("iron"), rough=0.6),
        _flat_mat("hs_grate_dark_m", CH("iron_dark"), rough=0.7),
        _flat_mat("hs_grate_pit_m", _dim(CH("iron_dark"), 0.35), rough=0.9)])

def build_portal_console():
    """The portal-side control console (~1.3 m): the pedestal that keys a
    PortalPad's transit ring. Reads as ASSEMBLED plant hardware: a stud-bolted
    plinth, a collared column carrying the head cabinet, the portal-purple
    status screen RECESSED inside its iron frame, and two glanded cable runs
    that elbow through ball joints and drop into the floor."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_SCREEN = 0, 1, 2
    _bev_box(bm, (0, 0, 0.125), (0.55, 0.45, 0.25), M_DARK, bevel=0.025)     # base plinth
    for (sx, sy) in ((-0.21, -0.16), (0.21, -0.16), (-0.21, 0.16), (0.21, 0.16)):
        hs_bolts(bm, (sx, sy, 0.25), 0.0, 1, M_IRON, bolt_r=0.024, bolt_h=0.04)
    _bev_box(bm, (0, 0, 0.28), (0.34, 0.3, 0.06), M_IRON, bevel=0.014)       # column base collar
    _bev_box(bm, (0, 0, 0.575), (0.26, 0.22, 0.65), M_DARK, bevel=0.025)     # column
    _bev_box(bm, (0, 0, 0.895), (0.32, 0.28, 0.06), M_IRON, bevel=0.014)     # head mount collar
    _bev_box(bm, (0, 0, 1.1), (0.5, 0.3, 0.4), M_DARK, bevel=0.025)          # head box
    hs_inset_panel(bm, (0, -0.16, 1.1), (0.4, 0.05, 0.3), 0.05, 0.035,
                   M_IRON, M_SCREEN, bevel=0.012)                            # recessed screen
    for sx in (-0.12, 0.12):                                                 # twin cable runs out the back
        hs_prism(bm, (sx, 0.17, 1.05), 0.055, 0.055, 0.06, M_DARK, sides=8,
                 bevel=0.012, axis='Y')                                      # exit gland
        hs_prism(bm, (sx, 0.27, 1.05), 0.035, 0.035, 0.26, M_IRON, sides=8,
                 bevel=0.01, axis='Y')                                       # horizontal run
        hs_sphere(bm, (sx, 0.4, 1.05), 0.06, M_DARK)                         # elbow ball joint
        hs_prism(bm, (sx, 0.4, 0.525), 0.035, 0.035, 1.05, M_IRON, sides=8,
                 bevel=0.01)                                                 # drop into the ball, down to floor
        hs_prism(bm, (sx, 0.4, 0.02), 0.06, 0.06, 0.04, M_DARK, sides=8,
                 bevel=0.01)                                                 # floor gland foot
    return _hs_finish("PortalConsole", bm, [
        _flat_mat("hs_pcon_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_pcon_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_pcon_screen_m", _dim(CG("portal_transit"), 0.5),
                  CG("portal_transit"), 1.5)])

def build_portal_pad_rings():
    """The floor pad for the runtime PortalPad (the channels transit grammar):
    a TURNED stack of concentric chamfered discs — iron outer ring, dark step,
    a portal_transit NEON GROOVE ring inlaid in its top, inner step, centre
    boss — visibly held together by six studs around the outer ring, four
    radial seam bars strapping the disc joint, and one crown stud. Low
    (~0.32 m tall, ~2.3 m across), flat on the ground."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_NEON = 0, 1, 2
    hs_prism(bm, (0, 0, 0.025), 1.15, 1.15, 0.05, M_IRON, sides=24, bevel=0.015)   # outer disc, base z=0
    hs_prism(bm, (0, 0, 0.08), 0.95, 0.95, 0.06, M_DARK, sides=24, bevel=0.015)    # step disc, top 0.11
    hs_tube(bm, (0, 0, 0.088), 0.78, 0.70, 0.05, M_NEON, sides=24)  # neon inlay, rim a hair proud (coplanar tops z-fight)
    hs_prism(bm, (0, 0, 0.1475), 0.55, 0.55, 0.075, M_DARK, sides=24, bevel=0.015)  # inner step
    hs_prism(bm, (0, 0, 0.235), 0.30, 0.30, 0.10, M_IRON, sides=24, bevel=0.02)    # centre boss
    hs_bolts(bm, (0, 0, 0.285), 0.0, 1, M_DARK, bolt_r=0.04, bolt_h=0.06)          # crown stud
    hs_bolts(bm, (0, 0, 0.05), 1.05, 6, M_DARK, phase=math.tau / 24)  # outer studs, phased off the bars
    for i in range(4):   # seam bars strapping the step joint to the rim (cardinals: axis-aligned sizes, the wheel-spoke idiom)
        a = math.tau * i / 4.0
        _bev_box(bm, (1.0 * math.cos(a), 1.0 * math.sin(a), 0.0675),
                 (abs(0.25 * math.cos(a)) + 0.05, abs(0.25 * math.sin(a)) + 0.05, 0.035),
                 M_DARK, bevel=0.008)
    return _hs_finish("PortalPadRings", bm, [
        _flat_mat("hs_padring_iron_m", CH("iron"), rough=0.6),
        _flat_mat("hs_padring_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("hs_padring_neon_m", _dim(CG("portal_transit"), 0.6),
                  CG("portal_transit"), 1.5)])

def build_ball_joint_pipe():
    """A ball-jointed pipe run for the Channels' scavenged plumbing: three thin
    segments zig-zag low along the wall through sphere joints, every junction
    sleeved by a clamp collar, a short riser carries its joint on top, and two
    bolted bracket feet cradle the run off the floor. Couplings, not a bent
    cylinder — and the far end is an open bore you can see into."""
    bm = _bmesh.new()
    M_PIPE, M_JOINT, M_DARK = 0, 1, 2
    hs_tube(bm, (-1.15, 0.0, 0.15), 0.095, 0.055, 0.10, M_DARK, sides=12, axis='X')  # open mouth
    hs_prism(bm, (-0.75, 0.0, 0.15), 0.07, 0.07, 0.70, M_PIPE, sides=10, bevel=0.012, axis='X')
    hs_prism(bm, (-0.40, 0.21, 0.15), 0.07, 0.07, 0.42, M_PIPE, sides=10, bevel=0.012, axis='Y')  # jog to wall
    hs_prism(bm, (0.30, 0.42, 0.15), 0.07, 0.07, 1.40, M_PIPE, sides=10, bevel=0.012, axis='X')
    hs_prism(bm, (1.00, 0.42, 0.385), 0.07, 0.07, 0.47, M_PIPE, sides=10, bevel=0.012)  # riser
    for jc in ((-0.40, 0.0, 0.15), (-0.40, 0.42, 0.15), (1.00, 0.42, 0.15),
               (1.00, 0.42, 0.62)):                                # sphere joints at every bend
        hs_sphere(bm, jc, 0.13, M_JOINT)
    for (cc, ax) in (((-0.55, 0.0, 0.15), 'X'), ((-0.40, 0.15, 0.15), 'Y'),
                     ((-0.40, 0.27, 0.15), 'Y'), ((-0.25, 0.42, 0.15), 'X'),
                     ((0.85, 0.42, 0.15), 'X'), ((1.00, 0.42, 0.30), 'Z'),
                     ((1.00, 0.42, 0.47), 'Z')):                   # clamp collar where pipe meets sphere
        hs_tube(bm, cc, 0.09, 0.068, 0.04, M_DARK, sides=12, axis=ax)
    for (fx, fy) in ((-0.85, 0.0), (0.45, 0.42)):                  # bracket feet + stud bolts
        _bev_box(bm, (fx, fy, 0.06), (0.14, 0.20, 0.12), M_DARK, bevel=0.015)
        hs_bolts(bm, (fx, fy - 0.10, 0.04), 0.0, 1, M_DARK, bolt_r=0.024, bolt_h=0.05, axis='Y')
    return _hs_finish("BallJointPipe", bm, [
        _flat_mat("hs_bjp_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("hs_bjp_joint_m", CH("pipe_joint"), rough=0.4),
        _flat_mat("hs_bjp_dark_m", CH("iron_dark"), rough=0.6)])

def build_red_bar_lamp():
    """A red bar sconce — the channels' lamp_red service light. Reads as FIXTURE
    HARDWARE, not a glowing stick: the emissive tube is a separate part seated
    in saddle notches on two bolted wall brackets, sheltered under a
    riser-mounted drip hood whose conduit stub feeds a junction box."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_LAMP = 0, 1, 2
    for sx in (-0.5, 0.5):
        _bev_box(bm, (sx, -0.05, 0.05), (0.1, 0.1, 0.1), M_IRON, bevel=0.018)      # wall bracket
        hs_bolts(bm, (sx, -0.101, 0.05), 0.0, 1, M_DARK, bolt_r=0.022,
                 bolt_h=0.04, axis='Y')                                            # face stud
        _bev_box(bm, (sx * 0.92, -0.08, 0.125), (0.1, 0.09, 0.05), M_IRON,
                 bevel=0.012)                                                      # saddle notch
        _bev_box(bm, (sx, -0.05, 0.17), (0.06, 0.08, 0.14), M_DARK, bevel=0.012)   # hood riser
    hs_prism(bm, (0, -0.08, 0.16), 0.05, 0.05, 0.9, M_LAMP, sides=12,
             bevel=0.01, axis='X')                                                 # lamp tube in its notches
    _bev_box(bm, (0, -0.085, 0.245), (1.08, 0.17, 0.035), M_DARK, bevel=0.014)     # drip hood
    _bev_box(bm, (0, -0.16, 0.22), (1.08, 0.02, 0.03), M_DARK, bevel=0.006)        # drip lip under front edge
    hs_prism(bm, (0.18, -0.085, 0.28), 0.03, 0.03, 0.06, M_DARK, sides=8,
             bevel=0.008, axis='Z')                                                # conduit stub off hood top
    _bev_box(bm, (0.18, -0.085, 0.305), (0.09, 0.08, 0.045), M_IRON, bevel=0.01)   # junction box
    hs_bolts(bm, (0.18, -0.126, 0.305), 0.0, 1, M_DARK, bolt_r=0.016,
             bolt_h=0.03, axis='Y')                                                # box cover stud
    return _hs_finish("RedBarLamp", bm, [
        _flat_mat("hs_lamp_iron_m", CH("iron"), rough=0.55),
        _flat_mat("hs_lamp_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_lamp_red_m", _dim(CH("lamp_red"), 0.45), CH("lamp_red"), 1.8)])

def build_reservoir_platform():
    """A reservoir service platform from the Channels (the Plumbing Power Project):
    an octagonal chamfered deck wearing a bolted collar rim, an access hatch
    RECESSED flush inside its coaming ring (two hinge lugs + a handle stud), and a
    bolted-flange feed pipe leaving the deck side through a ball joint to an OPEN
    mouth seated on its own foot. Every join is declared — collar seats ON the
    deck, flange bolts TO it, the pipe ends in a bore, nothing butt-joints bare."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_PIPE, M_JOINT = 0, 1, 2, 3
    hs_prism(bm, (0, 0, 0.16), 0.85, 0.88, 0.32, M_IRON, sides=8, bevel=0.025)     # deck (chunky, wider at the waterline)
    hs_tube(bm, (0, 0, 0.355), 0.92, 0.82, 0.09, M_DARK, sides=16)                 # rim collar on deck top
    hs_bolts(bm, (0, 0, 0.41), 0.87, 4, M_DARK, phase=math.pi / 8.0)               # four rim bolts
    hs_tube(bm, (0, 0, 0.06), 0.88, 0.8, 0.12, M_DARK, sides=16)                   # waterline skirt
    hs_prism(bm, (0, 0, 0.41), 0.28, 0.33, 0.18, M_IRON, sides=8, bevel=0.02)       # centre housing
    hx, hy = 0.0, 0.0                                                               # hatch rides the housing top
    hs_tube(bm, (hx, hy, 0.51), 0.2, 0.165, 0.05, M_DARK, sides=8)                 # coaming frame, proud
    hs_prism(bm, (hx, hy, 0.49), 0.155, 0.155, 0.03, M_DARK, sides=8, bevel=0.01)  # hatch lid, sunk flush
    for sx in (-0.09, 0.09):                                                       # hinge lugs
        _bev_box(bm, (hx + sx, hy + 0.18, 0.52), (0.05, 0.08, 0.05), M_DARK, bevel=0.01)
    hs_bolts(bm, (hx, hy - 0.12, 0.52), 0.0, 1, M_DARK, bolt_r=0.03, bolt_h=0.06)  # handle stud
    hs_prism(bm, (1.2, 0, 0.11), 0.062, 0.062, 1.2, M_PIPE, sides=10, bevel=0.012, axis='X')  # feed run (thin, low)
    hs_prism(bm, (0.87, 0, 0.13), 0.12, 0.12, 0.07, M_DARK, sides=10, bevel=0.015, axis='X')  # deck-edge flange
    hs_bolts(bm, (0.91, 0, 0.13), 0.09, 4, M_DARK, axis='X')                       # flange bolts
    hs_sphere(bm, (1.86, 0, 0.11), 0.085, M_JOINT)                                 # elbow ball joint
    hs_prism(bm, (1.86, 0, -0.06), 0.058, 0.058, 0.26, M_PIPE, sides=10, bevel=0.01)  # down-elbow INTO the water

    return _hs_finish("ReservoirPlatform", bm, [
        _flat_mat("hs_resv_iron_m", CH("iron"), rough=0.6),
        _flat_mat("hs_resv_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("hs_resv_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("hs_resv_joint_m", CH("pipe_joint"), rough=0.5)])

