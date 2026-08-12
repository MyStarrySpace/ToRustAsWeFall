# CONCEPT PASS 1 — pieces rebuilt AGAINST THE DIRECTOR'S GENERATED REFERENCES
# (five plates received 2026-07-27: portal+console, pad rings, water channel,
# reservoir platform interior, flow terminal). Exec-included AFTER hardsurface.py;
# overrides the blind-built versions. Decomposition notes live with each builder —
# the reference is the spec, the card render is the acceptance test.
#
# New vocabulary the plates demanded: HEX grates/vents (never square mesh),
# wood-core-in-iron-straps construction, segmented masonry rings, ball-segmented
# cable arcs, emblem/crest bosses. Rotation-capable block for wedges and tilted
# console faces.

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



# DIRECTOR'S RULING (2026-07-29): the reference-plate re-reads of the PORTAL
# FAMILY are SHELVED — the ring read as "a flower of rectangles cut into wood",
# the pads as wood wedges, and the console's ball-segment cable arcs as "wires
# that are just a bunch of spheres". The earlier STANDALONE HARD-SURFACE
# versions (organic_v2's faceted iron torus ring, hardsurface's turned-disc
# pads + console) are the keepers. These defs are renamed off the build names
# so exec order can never silently promote them again; kept for reference.
def _shelved_plate_portal_ring_ornate():
    """REFERENCE plate A: the curecumin portal is a SEGMENTED MASONRY RING set
    into a heavy WOODEN plank frame — stepped posts, a crest block at the apex —
    standing on a stone step platform. The bore holds a recessed near-black
    void (the live lens is a separate gameplay object; portal law: dormant =
    dark, active glow is PURPLE). Ring segments joint with visible studs."""
    bm = _bmesh.new()
    M_WOOD, M_WOODD, M_IRON, M_RUST, M_NEON, M_VOID = 0, 1, 2, 3, 4, 5
    zc = 1.7
    for i in range(11):                                           # plank back wall
        px = -1.25 + i * 0.25
        _bev_box(bm, (px, 0.24, 1.62), (0.23, 0.14, 3.0), M_WOOD if i % 3 else M_WOODD,
                 bevel=0.015)
    for sx in (-1.45, 1.45):                                      # heavy posts
        _bev_box(bm, (sx, 0.1, 1.55), (0.3, 0.34, 3.1), M_WOODD, bevel=0.025)
        _bev_box(bm, (sx, 0.1, 3.02), (0.38, 0.4, 0.18), M_WOOD, bevel=0.02)   # capitals
    _bev_box(bm, (0, 0.12, 3.22), (2.6, 0.3, 0.22), M_WOOD, bevel=0.02)        # crown beam
    _bev_box(bm, (0, 0.04, 3.42), (0.52, 0.34, 0.34), M_WOODD, bevel=0.02)     # crest block
    hs_bolts(bm, (0, -0.14, 3.42), 0.1, 3, M_RUST, bolt_r=0.03, bolt_h=0.04,
             axis='Y', phase=math.pi / 2)                                      # crest emblem studs
    for i in range(12):                                           # the segmented masonry ring
        a = math.tau * i / 12.0
        big = (i % 2 == 0)
        # VOUSSOIRS: each block's long axis lies TANGENT to the ring (local X maps
        # to (cos t, 0, -sin t) under a Y-rotation, so t = -a - pi/2 hits the
        # tangent) — chord-length blocks close into a continuous polygonal ring.
        # The old rot=-a pointed every block radially: rectangles sticking OUT.
        _bev_box_r(bm, (0.97 * math.cos(a), -0.02, zc + 0.97 * math.sin(a)),
                   (0.54, 0.3 if big else 0.26, 0.34 if big else 0.3), M_IRON,
                   rot=(0.0, -a - math.pi / 2.0, 0.0), bevel=0.03)
        ja = a + math.tau / 24.0                                  # joint studs between segments
        hs_bolts(bm, (1.0 * math.cos(ja), -0.18, zc + 1.0 * math.sin(ja)), 0.0, 1,
                 M_RUST, bolt_r=0.03, bolt_h=0.04, axis='Y')
    hs_torus(bm, (0, -0.06, zc), 0.78, 0.055, M_RUST, major_segs=16, minor_segs=6)  # bore lip
    hs_torus(bm, (0, -0.1, zc), 0.72, 0.05, M_NEON, major_segs=20, minor_segs=6)   # purple ring, proud
    hs_prism(bm, (0, 0.06, zc), 0.86, 0.86, 0.1, M_VOID, sides=20, bevel=0.0,
             axis='Y')                                            # the dark void, recessed deep
    _bev_box(bm, (0, -0.3, 0.09), (2.4, 1.3, 0.18), M_IRON, bevel=0.02)        # stone steps
    _bev_box(bm, (0, -0.42, 0.24), (1.9, 1.0, 0.14), M_RUST, bevel=0.02)
    return _hs_finish("PortalRingOrnate", bm, [
        _flat_mat("cp_wood_m", CH("wood"), rough=0.85),
        _flat_mat("cp_woodd_m", _dim(CH("wood"), 0.7), rough=0.9),
        _flat_mat("cp_iron_m", CH("iron"), rough=0.6),
        _flat_mat("cp_rust_m", CH("rust"), rough=0.8),
        _flat_mat("cp_neon_m", _dim(CG("portal_transit"), 0.6), CG("portal_transit"), 2.6),
        _flat_mat("cp_void_m", _dim(CG("portal_transit"), 0.04), rough=0.98)])


def _shelved_plate_portal_console():
    """REFERENCE plate A: the portal console is a carved PEDESTAL — paneled
    column wearing an emblem, a TILTED head with the purple glyph screen and a
    button row — with two BALL-SEGMENTED cable arcs vertebrae-ing from its base
    into the floor."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_SCREEN, M_CABLE, M_RUST = 0, 1, 2, 3, 4
    _bev_box(bm, (0, 0, 0.1), (0.62, 0.52, 0.2), M_DARK, bevel=0.02)           # plinth
    hs_bolts(bm, (0, -0.26, 0.1), 0.0, 1, M_RUST, bolt_r=0.024, bolt_h=0.04, axis='Y')
    _bev_box(bm, (0, 0, 0.62), (0.38, 0.32, 0.85), M_DARK, bevel=0.02)         # column
    hs_inset_panel(bm, (0, -0.16, 0.62), (0.3, 0.05, 0.6), 0.05, 0.03,
                   M_IRON, M_DARK, bevel=0.012)                                # paneled front
    hs_torus(bm, (0, -0.2, 0.72), 0.07, 0.018, M_RUST, major_segs=10,
             minor_segs=5)                                                     # emblem ring
    hs_bolts(bm, (0, -0.21, 0.6), 0.05, 3, M_RUST, bolt_r=0.016, bolt_h=0.03,
             axis='Y', phase=math.pi / 2)                                      # emblem trefoil
    _bev_box(bm, (0, 0, 1.09), (0.46, 0.4, 0.1), M_IRON, bevel=0.015)          # collar
    _bev_box_r(bm, (0, 0.02, 1.32), (0.56, 0.3, 0.36), M_DARK,
               rot=(-0.28, 0.0, 0.0), bevel=0.02)                              # tilted head
    _bev_box_r(bm, (0, -0.19, 1.36), (0.44, 0.05, 0.26), M_IRON,
               rot=(-0.28, 0.0, 0.0), bevel=0.01)                              # screen bezel
    _bev_box_r(bm, (0, -0.2, 1.36), (0.38, 0.045, 0.2), M_SCREEN,
               rot=(-0.28, 0.0, 0.0), bevel=0.006)                             # the glyph screen
    _bev_box_r(bm, (0, -0.245, 1.175), (0.34, 0.04, 0.05), M_IRON,
               rot=(-0.28, 0.0, 0.0), bevel=0.008)                             # button row bar
    for (sy, arc_r) in ((-0.08, 0.52), (0.08, 0.62)):             # ball-segment cable arcs
        for k in range(8):
            t = k / 7.0
            ang = t * math.pi / 2.0
            x = -0.18 - arc_r * math.sin(ang)
            z = 0.52 - (0.52 - 0.05) * (1 - math.cos(ang))
            hs_sphere(bm, (x, sy, max(z, 0.055)), 0.055 - 0.008 * t, M_CABLE, subdiv=1)
        _bev_box(bm, (-0.18 - arc_r, sy, 0.035), (0.12, 0.1, 0.07), M_RUST, bevel=0.01)
    return _hs_finish("PortalConsole", bm, [
        _flat_mat("cp_con_dark_m", _dim(CH("iron_dark"), 0.9), rough=0.65),
        _flat_mat("cp_con_iron_m", CH("iron"), rough=0.55),
        _flat_mat("cp_con_screen_m", _dim(CG("portal_transit"), 0.55), CG("portal_transit"), 2.0),
        _flat_mat("cp_con_cable_m", _dim(CG("portal_transit"), 0.25), rough=0.5),
        _flat_mat("cp_con_rust_m", CH("rust"), rough=0.8)])


def _shelved_plate_portal_pad_rings():
    """REFERENCE plate B: the pad is a TURNED assembly read outward-in — a ring
    of radial WOOD WEDGES, a bolted iron ring, a bright purple neon groove, a
    second iron ring, a thinner inner neon, and a raised centre boss carrying
    the trefoil emblem."""
    bm = _bmesh.new()
    M_WOOD, M_IRON, M_DARK, M_NEON, M_RUST = 0, 1, 2, 3, 4
    for i in range(20):                                           # radial wood wedge ring
        a = math.tau * i / 20.0
        # each wedge fills its full sector minus a seam (sector at r=1.28 is
        # ~0.40 wide) so the surround reads as a continuous plank ring with
        # joints — 0.29-wide wedges left gaps and read as separated teeth
        _bev_box_r(bm, (1.28 * math.cos(a), 1.28 * math.sin(a), 0.045),
                   (0.36, 0.385, 0.09), M_WOOD, rot=(0.0, 0.0, a), bevel=0.015)
    hs_prism(bm, (0, 0, 0.05), 1.13, 1.13, 0.1, M_DARK, sides=24, bevel=0.015)   # outer iron ring
    hs_bolts(bm, (0, 0, 0.105), 1.04, 12, M_RUST, bolt_r=0.024, bolt_h=0.035)
    hs_tube(bm, (0, 0, 0.075), 0.97, 0.88, 0.055, M_NEON, sides=24)              # bright neon groove
    hs_prism(bm, (0, 0, 0.06), 0.84, 0.84, 0.12, M_IRON, sides=24, bevel=0.015)  # mid ring
    hs_bolts(bm, (0, 0, 0.125), 0.76, 8, M_RUST, bolt_r=0.02, bolt_h=0.03)
    hs_tube(bm, (0, 0, 0.09), 0.66, 0.61, 0.05, M_NEON, sides=24)                # thin inner neon
    hs_prism(bm, (0, 0, 0.075), 0.56, 0.56, 0.15, M_DARK, sides=24, bevel=0.015) # inner disc
    hs_prism(bm, (0, 0, 0.19), 0.32, 0.38, 0.14, M_IRON, sides=16, bevel=0.02)   # centre boss
    hs_bolts(bm, (0, 0, 0.225), 0.12, 3, M_RUST, bolt_r=0.03, bolt_h=0.04,
             phase=math.pi / 2)                                                  # trefoil emblem
    return _hs_finish("PortalPadRings", bm, [
        _flat_mat("cp_wood_m", CH("wood"), rough=0.85),
        _flat_mat("cp_pad_iron_m", CH("iron"), rough=0.55),
        _flat_mat("cp_pad_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("cp_pad_neon_m", _dim(CG("portal_transit"), 0.6), CG("portal_transit"), 1.6),
        _flat_mat("cp_pad_rust_m", CH("rust"), rough=0.8)])


def build_water_channel():
    """REFERENCE plate C: a deck SECTION the water has cut through — riveted
    rust frame, plank walkway patches and HEX-GRATE panels for decking, the
    cyan water snaking between staggered stacked-block banks, foam flecks, a
    valve wheel and gauge on the side face."""
    bm = _bmesh.new()
    M_DARK, M_RUST, M_WOOD, M_WATER, M_FOAM, M_HEX = 0, 1, 2, 3, 4, 5
    _bev_box(bm, (0, 0, 0.13), (2.4, 1.3, 0.26), M_DARK, bevel=0.02)             # slab body
    for (sx, sy, w, d) in ((-0.02, 0.0, 2.4, 0.12), (-0.02, 0.0, 0.12, 1.3)):    # frame bars run
        pass
    for sy in (-0.62, 0.62):                                                     # long frame rails
        _bev_box(bm, (0, sy, 0.28), (2.4, 0.12, 0.07), M_RUST, bevel=0.015)
        for bx in (-0.95, -0.35, 0.35, 0.95):
            hs_bolts(bm, (bx, sy, 0.32), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.03)
    for sx in (-1.17, 1.17):                                                     # end rails
        _bev_box(bm, (sx, 0, 0.28), (0.12, 1.3, 0.07), M_RUST, bevel=0.015)
    for (px, py, pw, pd) in ((-0.85, 0.38, 0.6, 0.42), (0.75, -0.42, 0.75, 0.38)):
        for k in range(3):                                                       # plank patches
            _bev_box(bm, (px, py - pd / 2 + (k + 0.5) * pd / 3, 0.285),
                     (pw, pd / 3 - 0.015, 0.05), M_WOOD, bevel=0.01)
    for (gx, gy) in ((-0.75, -0.4), (0.8, 0.42)):                                # hex grate patches
        _bev_box(bm, (gx, gy, 0.27), (0.7, 0.42, 0.03), M_DARK, bevel=0.008)
        _hex_holes(bm, [(gx + dx, gy + dy, 0.285) for (dx, dy) in
                        _honeycomb(0, 0, 5, 3, 0.13)], 0.05, 0.015, M_HEX)
    for k in range(9):                                                           # the snaking water
        t = k / 8.0
        wx = -1.05 + t * 2.1
        wy = 0.26 * math.sin(t * math.tau * 0.75)
        _bev_box(bm, (wx, wy, 0.255), (0.3, 0.46, 0.05), M_WATER, bevel=0.006)
        if k % 2 == 0:                                                           # staggered banks
            for side in (-1, 1):
                _bev_box(bm, (wx + 0.06 * side, wy + side * 0.3, 0.29),
                         (0.22, 0.09, 0.09), M_RUST if k % 4 else M_DARK, bevel=0.012)
        if k % 3 == 1:
            _bev_box(bm, (wx, wy + 0.1, 0.285), (0.1, 0.08, 0.02), M_FOAM, bevel=0.004)
    hs_torus(bm, (-0.7, -0.66, 0.14), 0.09, 0.02, M_RUST, major_segs=10,
             minor_segs=5, axis='Y')                                             # side valve wheel
    hs_prism(bm, (-0.7, -0.63, 0.14), 0.03, 0.03, 0.08, M_DARK, sides=6,
             bevel=0.008, axis='Y')
    hs_prism(bm, (0.9, -0.66, 0.18), 0.07, 0.07, 0.04, M_FOAM, sides=10,
             bevel=0.006, axis='Y')                                              # gauge face
    return _hs_finish("WaterChannel", bm, [
        _flat_mat("cp_wc_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("cp_wc_rust_m", CH("rust"), rough=0.8),
        _flat_mat("cp_wood_m", CH("wood"), rough=0.85),
        _flat_mat("cp_wc_water_m", _dim(CH("water"), 0.75), CH("water"), 0.85,
                  rough=0.22),
        _flat_mat("cp_wc_foam_m", CH("foam"), _dim(CH("foam"), 0.8), 0.8),
        _flat_mat("cp_wc_hex_m", _dim(CH("iron_dark"), 0.3), rough=0.9)])


def build_reservoir_platform():
    """REFERENCE plate D: the platform in the drum — a chunky octagonal caisson
    of riveted rust panels with corner strap braces, a central HEX grate in a
    hex coaming, rivet rings on the top face, and the flanged feed pipe running
    off horizontally through a ball joint to an open mouth (as the plate shows)."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_PIPE, M_JOINT, M_RUST, M_HEX = 0, 1, 2, 3, 4, 5
    hs_tube(bm, (0, 0, 0.06), 0.88, 0.8, 0.12, M_DARK, sides=16)                 # waterline skirt
    hs_prism(bm, (0, 0, 0.16), 0.85, 0.88, 0.32, M_RUST, sides=8, bevel=0.025)   # caisson body
    hs_tube(bm, (0, 0, 0.345), 0.9, 0.8, 0.07, M_DARK, sides=8)                  # top rim band
    for i in range(8):                                                           # corner strap braces
        a = math.tau * (i + 0.5) / 8.0
        _bev_box_r(bm, (0.84 * math.cos(a), 0.84 * math.sin(a), 0.2),
                   (0.1, 0.09, 0.34), M_DARK, rot=(0.0, 0.0, a), bevel=0.012)
    hs_bolts(bm, (0, 0, 0.335), 0.68, 16, M_DARK, bolt_r=0.02, bolt_h=0.025)     # top rivet ring
    hs_prism(bm, (0, 0, 0.33), 0.3, 0.3, 0.05, M_DARK, sides=6, bevel=0.01)      # hex coaming
    hs_prism(bm, (0, 0, 0.345), 0.24, 0.24, 0.04, M_HEX, sides=6, bevel=0.0)     # the hex grate void
    _hex_holes(bm, [(dx, dy, 0.365) for (dx, dy) in _honeycomb(0, 0, 3, 3, 0.11)],
               0.04, 0.012, M_DARK)
    hs_bolts(bm, (0, 0, 0.36), 0.27, 6, M_RUST, bolt_r=0.018, bolt_h=0.025)
    hs_prism(bm, (1.2, 0, 0.13), 0.062, 0.062, 1.2, M_PIPE, sides=10,
             bevel=0.012, axis='X')                                              # feed run
    hs_prism(bm, (0.87, 0, 0.13), 0.12, 0.12, 0.07, M_DARK, sides=10,
             bevel=0.015, axis='X')                                              # deck-edge flange
    hs_bolts(bm, (0.91, 0, 0.13), 0.09, 4, M_DARK, axis='X')
    hs_sphere(bm, (1.86, 0, 0.13), 0.1, M_JOINT)                                 # ball joint
    hs_prism(bm, (2.12, 0, 0.13), 0.062, 0.062, 0.4, M_PIPE, sides=10,
             bevel=0.012, axis='X')
    hs_tube(bm, (2.36, 0, 0.13), 0.085, 0.05, 0.1, M_DARK, sides=10, axis='X')   # open mouth
    return _hs_finish("ReservoirPlatform", bm, [
        _flat_mat("cp_rp_iron_m", CH("iron"), rough=0.55),
        _flat_mat("cp_rp_dark_m", CH("iron_dark"), rough=0.62),
        _flat_mat("cp_rp_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("cp_rp_joint_m", CH("pipe_joint"), rough=0.42),
        _flat_mat("cp_rp_rust_m", CH("rust"), rough=0.82),
        _flat_mat("cp_rp_hex_m", _dim(CH("iron_dark"), 0.3), rough=0.9)])


def build_terminal():
    """REFERENCE plate E: the flow terminal — a WOOD-CORE column wearing bolted
    iron corner straps and a hex vent, on a base plate with skid feet; the head
    unit carries the terminal-green matrix screen on a SLOPED face, a small hex
    vent and a red indicator; a thin drain pipe with brass fittings runs from
    the column down into a floor drain plate."""
    bm = _bmesh.new()
    M_DARK, M_IRON, M_WOOD, M_SCREEN, M_RED, M_BRASS, M_HEX = 0, 1, 2, 3, 4, 5, 6
    _bev_box(bm, (0, 0, 0.04), (0.62, 0.52, 0.08), M_DARK, bevel=0.015)          # base plate
    for sy in (-0.2, 0.2):
        _bev_box(bm, (0, sy, 0.015), (0.7, 0.1, 0.03), M_IRON, bevel=0.008)      # skid feet
    _bev_box(bm, (0, 0, 0.62), (0.3, 0.26, 1.1), M_WOOD, bevel=0.012)            # wood core
    for (sx, sy) in ((-0.16, -0.14), (0.16, -0.14), (-0.16, 0.14), (0.16, 0.14)):
        _bev_box(bm, (sx, sy, 0.62), (0.07, 0.07, 1.1), M_DARK, bevel=0.012)     # corner straps
    for hz in (0.32, 0.95):                                                      # strap bands + bolts
        _bev_box(bm, (0, 0, hz), (0.4, 0.32, 0.07), M_IRON, bevel=0.01)
        for sx in (-0.17, 0.17):
            hs_bolts(bm, (sx, -0.17, hz), 0.0, 1, M_DARK, bolt_r=0.018,
                     bolt_h=0.03, axis='Y')
    _bev_box(bm, (0, -0.145, 0.62), (0.2, 0.03, 0.24), M_IRON, bevel=0.008)      # vent bezel
    _hex_holes(bm, [(dx, -0.165, 0.62 + dz) for (dx, dz) in _honeycomb(0, 0, 3, 3, 0.055)],
               0.02, 0.02, M_HEX, axis='Y')                                      # hex vent
    _bev_box(bm, (0, 0, 1.28), (0.46, 0.4, 0.22), M_IRON, bevel=0.018)           # head base
    _bev_box_r(bm, (0, -0.03, 1.47), (0.5, 0.34, 0.26), M_DARK,
               rot=(-0.32, 0.0, 0.0), bevel=0.018)                               # sloped head
    _bev_box_r(bm, (0, -0.185, 1.5), (0.4, 0.04, 0.15), M_IRON,
               rot=(-0.32, 0.0, 0.0), bevel=0.008)                               # screen bezel
    _bev_box_r(bm, (0, -0.195, 1.5), (0.34, 0.035, 0.11), M_SCREEN,
               rot=(-0.32, 0.0, 0.0), bevel=0.005)                               # green matrix screen
    _bev_box_r(bm, (0.13, -0.22, 1.395), (0.06, 0.03, 0.05), M_RED,
               rot=(-0.32, 0.0, 0.0), bevel=0.005)                               # red indicator
    _hex_holes(bm, [(dx - 0.1, -0.215, 1.4 + dz) for (dx, dz) in _honeycomb(0, 0, 2, 2, 0.05)],
               0.018, 0.02, M_HEX, axis='Y')                                     # head vent
    hs_prism(bm, (-0.2, -0.17, 0.35), 0.028, 0.028, 0.62, M_DARK, sides=8,
             bevel=0.006)                                                        # drain pipe drop
    for fz in (0.55, 0.18):
        hs_prism(bm, (-0.2, -0.17, fz), 0.042, 0.042, 0.05, M_BRASS, sides=8,
                 bevel=0.006)                                                    # brass fittings
    _bev_box(bm, (-0.2, -0.17, 0.02), (0.2, 0.18, 0.04), M_IRON, bevel=0.008)    # drain plate
    _hex_holes(bm, [(-0.2 + dx, -0.17 + dy, 0.04) for (dx, dy) in _honeycomb(0, 0, 2, 2, 0.06)],
               0.022, 0.015, M_HEX)
    return _hs_finish("Terminal", bm, [
        _flat_mat("cp_t_dark_m", _dim(CH("iron_dark"), 0.9), rough=0.65),
        _flat_mat("cp_t_iron_m", CH("iron"), rough=0.55),
        _flat_mat("cp_t_wood_m", _dim(CH("wood"), 0.85), rough=0.9),
        _flat_mat("cp_t_screen_m", _dim(CG("terminal_green"), 0.5), CG("terminal_green"), 1.3),
        _flat_mat("cp_t_red_m", _dim(CH("lamp_red"), 0.5), CH("lamp_red"), 1.8),
        _flat_mat("cp_t_brass_m", _dim(CG("warning_amber"), 0.55), rough=0.5),
        _flat_mat("cp_t_hex_m", _dim(CH("iron_dark"), 0.3), rough=0.9)])


# ---- plates F + G (received mid-pass): the shelter diorama and the DEFINITIVE
# ---- organics reference — fat linked-bead trunk, vascular WEB (not arches),
# ---- biolume colony in the roots. Overrides the organic_v2 versions.

def build_vein_trunk():
    """REFERENCE plate G: the trunk is a chain of FAT LINKED LOBES. The skinned
    core carries LARGE overlapping stud-lobes along the spine — studs survive
    decimation, so the bead read is guaranteed (subsurf+decimate smooths radius
    alternation on the core itself away). Roots flare wide; the biolume colony
    nests in them."""
    spine = [(0.00, 0.06, 0.00, 0.20), (0.05, 0.09, 0.60, 0.16),
             (-0.03, 0.07, 1.20, 0.14), (0.04, 0.10, 1.80, 0.12),
             (0.00, 0.08, 2.40, 0.10), (0.12, 0.12, 2.95, 0.07),
             (0.20, 0.14, 3.30, 0.04)]
    chains = [spine]
    chains.append([spine[3], (-0.36, 0.06, 1.95, 0.08), (-0.56, 0.09, 2.12, 0.05),
                   (-0.7, 0.11, 2.3, 0.035)])
    chains.append([spine[1], (0.34, 0.05, 0.78, 0.09), (0.55, 0.08, 0.95, 0.05),
                   (0.68, 0.1, 1.12, 0.035)])
    chains.append([spine[4], (-0.26, 0.05, 2.55, 0.06), (-0.42, 0.08, 2.7, 0.035)])
    for (dx, dy) in ((0.5, 0.16), (-0.54, 0.1), (0.28, -0.42), (-0.32, -0.38), (0.04, 0.5)):
        chains.append([spine[0], (dx * 0.7, 0.06 + dy * 0.7, 0.08, 0.13),
                       (dx, 0.06 + dy, 0.02, 0.055)])
    ob = _skin_growth("VeinTrunk", chains, decimate=0.16)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    for m in (bark, blue, violet):
        ob.data.materials.append(m)
    lobes = [(0.0, 0.06, 0.18, 0.34), (0.08, 0.1, 0.52, 0.28), (-0.04, 0.07, 0.86, 0.31),
             (0.06, 0.1, 1.22, 0.24), (-0.05, 0.06, 1.56, 0.27), (0.04, 0.1, 1.92, 0.2),
             (0.0, 0.08, 2.26, 0.22), (0.09, 0.11, 2.6, 0.16), (0.16, 0.12, 2.92, 0.17),
             (0.34, 0.06, 0.84, 0.1), (0.55, 0.08, 1.0, 0.07),
             (-0.37, 0.07, 1.98, 0.09), (-0.57, 0.1, 2.16, 0.06)]
    _stud_spheres(ob, [(x, y, z, r, 0, 0.88) for (x, y, z, r) in lobes])
    _stud_spheres(ob, [
        (0.3, -0.18, 0.12, 0.13, 1, 0.8), (-0.27, -0.22, 0.1, 0.1, 2, 0.8),
        (0.07, -0.3, 0.11, 0.12, 1, 0.8), (-0.11, -0.26, 0.26, 0.08, 2, 0.8),
        (0.2, -0.24, 0.3, 0.06, 1, 0.8), (-0.02, -0.32, 0.07, 0.05, 2, 0.8),
        (0.4, -0.1, 0.24, 0.05, 2, 0.8)])
    ob["no_atlas"] = 1
    return ob


def build_wall_tracery():
    """REFERENCE plate G: the wall is CLAIMED by a vascular WEB — not arches: a
    fat bead-trunk descends off-centre, a second lighter trunk beside it, and
    thin bead-chain tendrils wander across the riveted panel in every direction.
    Biolume buds at the junctions; rivet rows on the plate itself."""
    y = -0.02
    main = [(-0.5, y, 0.0, 0.20), (-0.42, y, 0.5, 0.10), (-0.55, y, 1.0, 0.18),
            (-0.44, y, 1.5, 0.09), (-0.52, y, 2.0, 0.15), (-0.42, y, 2.5, 0.08),
            (-0.48, y, 2.95, 0.11)]
    second = [(0.6, y, 0.0, 0.13), (0.52, y, 0.55, 0.07), (0.62, y, 1.1, 0.11),
              (0.55, y, 1.65, 0.06), (0.6, y, 2.1, 0.08)]
    chains = [main, second]
    tendrils = [
        [main[1], (-0.9, y, 0.7, 0.07), (-1.2, y, 0.95, 0.045), (-1.38, y, 1.2, 0.06)],
        [main[3], (-0.85, y, 1.7, 0.05), (-1.15, y, 1.95, 0.03), (-1.35, y, 2.25, 0.04)],
        [main[5], (-0.7, y, 2.7, 0.045), (-1.0, y, 2.9, 0.028)],
        [main[2], (-0.15, y, 1.15, 0.055), (0.15, y, 1.3, 0.03), second[2]],
        [main[4], (-0.1, y, 2.2, 0.05), (0.2, y, 2.35, 0.03), second[4]],
        [second[1], (0.9, y, 0.75, 0.045), (1.2, y, 0.95, 0.028), (1.38, y, 1.2, 0.04)],
        [second[3], (0.9, y, 1.85, 0.04), (1.18, y, 2.05, 0.026), (1.36, y, 2.3, 0.035)],
        [main[0], (-0.15, y, 0.15, 0.06), (0.2, y, 0.06, 0.035), second[0]],
    ]
    chains.extend(tendrils)
    ob = _skin_growth("WallTracery", chains, decimate=0.18)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    plate = _flat_mat("cp_wt_plate_m", CH("iron_dark"), rough=0.7)
    rust = _flat_mat("cp_rust_m", CH("rust"), rough=0.8)
    for m in (bark, blue, violet, plate, rust):
        ob.data.materials.append(m)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    _bev_box(bm, (0.0, 0.11, 1.6), (3.0, 0.22, 3.2), 3, bevel=0.02)          # the riveted panel
    for px in (-1.3, -0.65, 0.0, 0.65, 1.3):                                 # rivet rows
        for pz in (0.16, 3.04):
            n0 = len(bm.faces)
            ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=6,
                                         radius1=0.022, radius2=0.018, depth=0.04)
            mtx = (mathutils.Matrix.Translation((px, -0.005, pz))
                   @ mathutils.Matrix.Rotation(-math.pi / 2.0, 4, 'X'))
            _bmesh.ops.transform(bm, matrix=mtx, verts=ret["verts"])
            _hs_tag(bm, n0, 4)
    bm.to_mesh(ob.data)
    bm.free()
    _stud_spheres(ob, [
        (-0.5, -0.16, 1.02, 0.07, 1, 0.85), (0.6, -0.14, 1.12, 0.06, 2, 0.85),
        (-1.36, -0.1, 1.22, 0.05, 2, 0.85), (0.05, -0.12, 1.28, 0.05, 1, 0.85),
        (-0.5, -0.14, 2.02, 0.06, 1, 0.85), (1.36, -0.09, 2.28, 0.045, 2, 0.85),
        (-0.48, -0.13, 0.4, 0.055, 0, 0.9), (0.58, -0.11, 1.9, 0.05, 0, 0.9)])
    ob["no_atlas"] = 1
    return ob


def build_biolume_cluster():
    """REFERENCE plate G (root colony): a denser mushroom colony — nine caps of
    mixed sizes crowding a shared mycelium, two small crystal shards, one
    connected skinned base."""
    root = (0.0, 0.0, 0.03, 0.12)
    caps = [(-0.14, 0.06, 0.26, 0.09, 1), (0.08, -0.10, 0.34, 0.11, 2),
            (0.16, 0.12, 0.20, 0.07, 1), (-0.02, 0.16, 0.16, 0.06, 2),
            (0.02, -0.02, 0.44, 0.12, 1), (0.20, -0.16, 0.14, 0.06, 2),
            (-0.22, -0.08, 0.18, 0.055, 1), (-0.08, -0.18, 0.12, 0.045, 2),
            (0.26, 0.0, 0.1, 0.04, 1)]
    chains = []
    for (cx, cy, cz, cr, _mi) in caps:
        chains.append([root, (cx * 0.6, cy * 0.6, cz * 0.55, 0.04), (cx, cy, cz - 0.02, 0.025)])
    for (dx, dy) in ((0.3, 0.1), (-0.28, 0.14), (0.05, -0.32), (-0.15, -0.25)):
        chains.append([root, (dx, dy, 0.02, 0.055)])
    ob = _skin_growth("BiolumeCluster", chains, decimate=0.34, jitter=0.012, sub_levels=2)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    for m in (bark, blue, violet):
        ob.data.materials.append(m)
    _stud_spheres(ob, [(cx, cy, cz + 0.02, cr * 0.85, mi, 0.5) for (cx, cy, cz, cr, mi) in caps])
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for (px, py, h, r, mi, tilt) in ((-0.24, -0.12, 0.38, 0.065, 1, 0.28),
                                     (0.27, 0.05, 0.28, 0.05, 2, -0.24)):
        ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=5,
                                     radius1=r, radius2=0.012, depth=h)
        mtx = (mathutils.Matrix.Translation((px, py, h / 2.0))
               @ mathutils.Matrix.Rotation(tilt, 4, 'X'))
        _bmesh.ops.transform(bm, matrix=mtx, verts=ret["verts"])
        for f in set(f for v in ret["verts"] for f in v.link_faces):
            f.material_index = mi
            f.smooth = False
    bm.to_mesh(ob.data)
    bm.free()
    ob["no_atlas"] = 1
    return ob



# ---- the SHELTER as a ROOM (director: "a whole ass room with decorations and
# ---- personality, not just an awning and a bed") — plate F scaled up: enclosing
# ---- walls, a skylight gap in the sloped roof with GOD-RAY shafts falling on
# ---- the sleeping corner, shelf plants, care-banners, props, warm light core.

def _ray_mat(name, rgb, alpha=0.12, strength=1.2):
    """A stylized light-shaft material: translucent, faintly emissive. The god
    ray is a MESH (the classic stylized shaft), not an engine volumetric."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*_srgb_lin(rgb), 1.0)
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Emission Color"].default_value = (*_srgb_lin(rgb), 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    for attr, val in (("surface_render_method", 'BLENDED'), ("blend_method", 'BLEND')):
        try:
            setattr(m, attr, val)
        except Exception:
            pass
    m.use_backface_culling = True
    return m


def build_shelter():
    """REFERENCE plate F, reworked to canon: a MAINTENANCE WORKER'S FORMER
    DWELLING — the room says who lived here: a tool board and spare valve
    wheels, a hose coil, a caged work lamp, one abandoned dead-stem pot on the
    shelf; the bedroll corner under the skylight god-rays. No flowers (the
    forget-me-nots have not appeared yet at this point in the story), no
    banners — the warmth is the worker's lamp and wood against dark iron."""
    bm = _bmesh.new()
    (M_WOOD, M_WOODD, M_DARK, M_IRON, M_MOSS, M_AMBER, M_RED,
     M_HEX, M_RUST) = 0, 1, 2, 3, 4, 5, 6, 7, 8
    _bev_box(bm, (0, 0.1, 0.07), (3.6, 3.2, 0.14), M_DARK, bevel=0.015)          # ground slab
    for k in range(8):                                                           # plank deck
        _bev_box(bm, (0, -1.05 + k * 0.34, 0.17), (3.4, 0.31, 0.06),
                 M_WOOD if k % 2 else M_WOODD, bevel=0.01)
    _bev_box(bm, (-0.2, -1.62, 0.1), (1.0, 0.26, 0.06), M_WOODD, bevel=0.01)     # steps
    _bev_box(bm, (-0.2, -1.8, 0.05), (1.0, 0.24, 0.05), M_WOOD, bevel=0.01)
    _hex_holes(bm, [(1.35 + dx, -1.35 + dy, 0.15) for (dx, dy) in _honeycomb(0, 0, 3, 2, 0.12)],
               0.046, 0.02, M_HEX)                                               # front hex grate
    for (px, pw) in ((-1.2, 1.15), (0.0, 1.15), (1.2, 1.15)):                    # iron back wall
        _bev_box(bm, (px, 1.52, 1.4), (pw, 0.16, 2.6), M_IRON, bevel=0.02)
    for px in (-1.6, -0.6, 0.6, 1.6):
        for pz in (0.35, 2.5):
            hs_bolts(bm, (px, 1.43, pz), 0.0, 1, M_RUST, bolt_r=0.024, bolt_h=0.04, axis='Y')
    hs_torus(bm, (0.95, 1.42, 2.0), 0.3, 0.05, M_RUST, major_segs=12, minor_segs=6)   # vent rim
    _hex_holes(bm, [(0.95 + dx, 1.44, 2.0 + dz) for (dx, dz) in _honeycomb(0, 0, 4, 4, 0.12)],
               0.048, 0.03, M_HEX, axis='Y')
    hs_prism(bm, (1.62, 1.35, 1.3), 0.06, 0.06, 2.4, M_DARK, sides=8, bevel=0.01)     # wall pipe
    hs_sphere(bm, (1.62, 1.35, 2.52), 0.09, M_DARK, subdiv=1)
    hs_prism(bm, (1.45, 1.35, 2.58), 0.05, 0.05, 0.35, M_DARK, sides=8, bevel=0.01, axis='X')
    _bev_box(bm, (1.62, 1.28, 0.9), (0.08, 0.08, 0.08), M_RED, bevel=0.006)      # red indicator
    for k in range(5):                                                           # planked left wall
        _bev_box(bm, (-1.72, 0.1, 0.32 + k * 0.32), (0.14, 3.0, 0.3),
                 M_WOODD if k % 2 else M_WOOD, bevel=0.012)
    # the worker's TOOL BOARD on the back wall
    _bev_box(bm, (-0.75, 1.42, 1.75), (0.9, 0.06, 0.8), M_WOODD, bevel=0.012)
    _bev_box(bm, (-1.05, 1.37, 1.9), (0.07, 0.05, 0.4), M_IRON, bevel=0.006)     # wrench shaft
    _bev_box(bm, (-1.05, 1.37, 2.13), (0.16, 0.05, 0.09), M_IRON, bevel=0.006)   # wrench jaw
    hs_torus(bm, (-0.75, 1.38, 1.85), 0.13, 0.022, M_RUST, major_segs=10,
             minor_segs=5)                                                       # spare wheel on peg
    _bev_box(bm, (-0.45, 1.37, 1.95), (0.06, 0.05, 0.35), M_WOODD, bevel=0.006)  # hammer handle
    _bev_box(bm, (-0.45, 1.37, 2.15), (0.18, 0.06, 0.1), M_DARK, bevel=0.006)    # hammer head
    # shelf: spare fittings + ONE abandoned dead-stem pot
    for sy in (-0.5, 0.7):
        _bev_box(bm, (-1.55, sy, 1.72), (0.2, 0.06, 0.06), M_DARK, bevel=0.006)
    _bev_box(bm, (-1.5, 0.1, 1.78), (0.34, 1.5, 0.05), M_WOOD, bevel=0.01)
    hs_prism(bm, (-1.5, -0.35, 1.85), 0.08, 0.08, 0.06, M_RUST, sides=10, bevel=0.008)  # flange
    hs_prism(bm, (-1.5, -0.15, 1.85), 0.06, 0.06, 0.09, M_IRON, sides=10, bevel=0.008)  # fitting
    hs_sphere(bm, (-1.5, 0.15, 1.86), 0.055, M_DARK, subdiv=1)                   # joint ball spare
    _bev_box(bm, (-1.5, 0.45, 1.86), (0.08, 0.08, 0.14), M_RUST, bevel=0.008)    # oil can
    hs_prism(bm, (-1.46, 0.5, 1.96), 0.014, 0.014, 0.07, M_RUST, sides=6, bevel=0.0)  # its spout
    hs_prism(bm, (-1.5, 0.78, 1.87), 0.075, 0.06, 0.12, M_RUST, sides=8, bevel=0.008)  # the pot
    n0 = len(bm.faces)
    ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=5,
                                 radius1=0.012, radius2=0.004, depth=0.22)
    _bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation((-1.5, 0.78, 2.03)),
                         verts=ret["verts"])
    _hs_tag(bm, n0, M_WOODD)                                                     # the dead stem
    # roof with the skylight gap + god rays
    for sy in (-1.55, 1.55):
        _bev_box(bm, (0, sy, 2.6 - (0.12 if sy < 0 else -0.12)), (3.6, 0.14, 0.12),
                 M_WOODD, bevel=0.012)
    for k in range(9):
        if k in (5, 6):
            continue
        _bev_box_r(bm, (-0.05, -1.35 + k * 0.34, 2.72 + (k - 4) * 0.048),
                   (3.7, 0.32, 0.06), M_WOOD if k % 2 else M_WOODD,
                   rot=(0.14, 0.0, 0.0), bevel=0.01)
    for (ox, t) in ((-0.3, 0.0), (0.25, 0.35), (0.7, 0.7)):
        _bev_box_r(bm, (0.55 + ox * 0.4, 0.45 - t * 0.2, 1.55),
                   (0.34 - t * 0.12, 0.5, 2.5), 9,
                   rot=(0.22, 0.0, 0.18), bevel=0.0)
    # sleeping corner under the rays
    _bev_box(bm, (0.85, 0.75, 0.34), (1.5, 1.1, 0.22), M_WOODD, bevel=0.015)
    _bev_box(bm, (0.85, 0.75, 0.55), (1.1, 0.65, 0.18), M_MOSS, bevel=0.045)
    _bev_box(bm, (1.25, 0.75, 0.62), (0.28, 0.5, 0.12), M_WOOD, bevel=0.03)
    hs_prism(bm, (0.28, 0.75, 0.58), 0.1, 0.1, 0.45, M_MOSS, sides=8,
             bevel=0.02, axis='Y')
    _bev_box(bm, (-0.05, 0.95, 0.3), (0.5, 0.5, 0.5), M_WOODD, bevel=0.02)       # crate table
    _bev_box(bm, (-0.05, 0.85, 0.585), (0.12, 0.12, 0.07), M_AMBER, bevel=0.008) # cup with brew
    hs_sphere(bm, (0.12, 1.05, 0.61), 0.1, M_IRON, subdiv=1)                     # worker's helmet
    # the CAGED work lamp, hanging mid-room
    _bev_box(bm, (0, 0.2, 2.42), (0.7, 0.05, 0.05), M_DARK, bevel=0.008)
    hs_prism(bm, (0, 0.2, 2.2), 0.012, 0.012, 0.4, M_DARK, sides=4, bevel=0.0)
    _bev_box(bm, (0, 0.2, 1.92), (0.14, 0.14, 0.22), M_AMBER, bevel=0.015)
    for ci in range(3):                                                          # the cage bars
        ca = math.tau * ci / 3.0
        _bev_box(bm, (0.09 * math.cos(ca), 0.2 + 0.09 * math.sin(ca), 1.92),
                 (0.02, 0.02, 0.26), M_DARK, bevel=0.0)
    _bev_box(bm, (0, 0.2, 2.06), (0.2, 0.2, 0.05), M_DARK, bevel=0.008)
    # floor props: leaning spare wheels, hose coil, bucket, barrel, crates
    for (wx, wr) in ((-1.35, 0.24), (-1.02, 0.19)):
        hs_torus(bm, (wx, 1.28, wr + 0.14), wr, 0.03, M_RUST, major_segs=12,
                 minor_segs=5, axis='Y')                                         # leaning wheels
    for hz in (0.08, 0.14, 0.2):
        hs_torus(bm, (-1.15, -0.9, hz), 0.22 - 0.01 * hz * 10, 0.035, M_MOSS,
                 major_segs=10, minor_segs=5, axis='Z')                          # hose coil
    hs_prism(bm, (-0.6, -1.35, 0.22), 0.13, 0.1, 0.24, M_IRON, sides=10, bevel=0.01)  # bucket
    hs_prism(bm, (1.45, 0.2, 0.4), 0.24, 0.28, 0.55, M_WOODD, sides=10, bevel=0.02)   # barrel
    for hz in (0.25, 0.55):
        hs_torus(bm, (1.45, 0.2, hz), 0.27, 0.02, M_DARK, major_segs=10, minor_segs=4, axis='Z')
    _bev_box(bm, (1.45, -0.9, 0.44), (0.55, 0.55, 0.55), M_WOODD, bevel=0.02)    # crates
    _bev_box(bm, (1.38, -0.83, 0.9), (0.4, 0.4, 0.38), M_WOOD, bevel=0.018)
    return _hs_finish("Shelter", bm, [
        _flat_mat("cp_shr_wood_m", CH("wood"), rough=0.85),
        _flat_mat("cp_shr_woodd_m", _dim(CH("wood"), 0.72), rough=0.9),
        _flat_mat("cp_shr_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("cp_shr_iron_m", CH("iron"), rough=0.6),
        _flat_mat("cp_shr_moss_m", _dim(CH("moss"), 0.9), rough=0.9),
        _flat_mat("cp_shr_amber_m", _dim(CG("warning_amber"), 0.7), CG("warning_amber"), 2.2),
        _flat_mat("cp_shr_red_m", _dim(CH("lamp_red"), 0.5), CH("lamp_red"), 1.6),
        _flat_mat("cp_shr_hex_m", _dim(CH("iron_dark"), 0.3), rough=0.9),
        _flat_mat("cp_shr_rust_m", CH("rust"), rough=0.8),
        _ray_mat("cp_shr_ray_m", _dim(CG("warning_amber"), 1.0), 0.12, 1.1)])
