# ASCENT PIECES — the wash-ascent slice's remaining modeled needs (director's
# queue, 2026-07-28): the SURGE WATER as a real modeled sheet (the flood must
# read as rising water, not a glow change), the CHANNEL COLLAR that closes the
# trough seams like real pipe-run joints, and the DRUM SHELL — the reservoir the
# coil climbs around, returning as modeled architecture. Same laws as every
# concept piece: chamfered hard-surface assembly, palette-authored flat
# materials, no primitives reach the engine (everything is baked ArrayMesh).
# Included by build_archetype_pieces.py after scaffold.py.

def build_water_surface():
    """The surge sheet: a chunky stepped water plane sized to ride OVER the
    water_channel slab (2.4 x 1.3). Blocky wave strips with foam flecks — the
    same pixel-water grammar as the channel's baked snaking water, but a full
    covering sheet the wash raises and drops. Emissive water material; the
    chunk drives visibility and height from the scheduler."""
    bm = _bmesh.new()
    M_WATER, M_FOAM = 0, 1
    for k in range(8):                                     # stepped wave strips
        wx = -1.05 + (k + 0.5) * 2.1 / 8.0
        wz = 0.03 + 0.014 * math.sin(k * 2.1)
        _bev_box(bm, (wx, 0.0, wz), (0.285, 1.26, 0.055), M_WATER, bevel=0.006)
    for (fx, fy) in ((-0.85, 0.35), (-0.2, -0.45), (0.45, 0.15), (0.95, -0.25),
                     (0.1, 0.55), (-0.55, -0.1)):
        _bev_box(bm, (fx, fy, 0.068), (0.11, 0.08, 0.02), M_FOAM, bevel=0.004)
    return _hs_finish("WaterSurface", bm, [
        _flat_mat("as_water_m", CH("water"), emit=CH("water"), emit_strength=1.7,
                  rough=0.25),
        _flat_mat("as_foam_m", CH("foam"), emit=_dim(CH("foam"), 0.9),
                  emit_strength=0.9, rough=0.5),
    ])


def build_channel_collar():
    """The joint collar: a bolted clamp band straddling two channel segments'
    meeting rims — side clamp plates, top flanges over the long rails, a strap
    under the slab, bolt studs. Real pipe-run infrastructure; one per seam."""
    bm = _bmesh.new()
    M_DARK, M_RUST = 0, 1
    _bev_box(bm, (0, 0, 0.03), (0.3, 1.52, 0.06), M_RUST, bevel=0.012)   # under-strap
    for sy in (-0.72, 0.72):                                              # side clamp plates
        _bev_box(bm, (0, sy, 0.2), (0.3, 0.09, 0.4), M_DARK, bevel=0.015)
        for bz in (0.1, 0.3):
            hs_bolts(bm, (0, sy * 1.01, bz), 0.0, 1, M_RUST, bolt_r=0.026,
                     bolt_h=0.035, axis='Y')
    for sy in (-0.62, 0.62):                                              # flanges over the rails
        _bev_box(bm, (0, sy, 0.35), (0.3, 0.17, 0.055), M_DARK, bevel=0.012)
        hs_bolts(bm, (0, sy, 0.39), 0.0, 1, M_RUST, bolt_r=0.024, bolt_h=0.03)
    return _hs_finish("ChannelCollar", bm, [
        _flat_mat("as_collar_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("as_collar_rust_m", CH("rust"), rough=0.85),
    ])


def build_drum_shell():
    """The reservoir drum, one 90-degree shell: riveted plate courses climbing
    well above the wall band, built as tangential chord plates (the blocky
    pixel grammar) with alternating course radii, stud rivets on the seams,
    and a recessed crown lip. Two placements ring the slice; the coil finally
    curves around SOMETHING again."""
    bm = _bmesh.new()
    M_IRON, M_RUST = 0, 1
    segs = 24
    courses = ((0.0, 3.2, 6.42), (3.2, 6.2, 6.5), (6.2, 9.0, 6.42), (9.0, 11.2, 6.3))
    for si in range(segs):
        a = (math.pi * 0.5) * (si + 0.5) / segs
        for ci, (z0, z1, rad) in enumerate(courses):
            _bev_box_r(bm, (rad * math.cos(a), rad * math.sin(a), (z0 + z1) * 0.5),
                       (0.45, 0.17, (z1 - z0) - 0.08),
                       M_RUST if (si + ci) % 5 == 0 else M_IRON,
                       rot=(0.0, 0.0, a + math.pi * 0.5), bevel=0.02)
        if si % 2 == 0:                                    # rivet studs on course seams
            for (z0, _z1, rad) in courses[1:]:
                _bev_box_r(bm, (6.58 * math.cos(a), 6.58 * math.sin(a), z0 + 0.04),
                           (0.07, 0.07, 0.07), M_RUST,
                           rot=(0.0, 0.0, a + math.pi * 0.5), bevel=0.01)
    return _hs_finish("DrumShell", bm, [
        _flat_mat("as_drum_iron_m", _dim(CH("iron_dark"), 0.85), rough=0.7),
        _flat_mat("as_drum_rust_m", _dim(CH("rust"), 0.85), rough=0.9),
    ])


# ---- THE PIPE TILE SET (director, 2026-07-28: "an actual pipes system") ------
# A modular connector vocabulary on a ONE-METRE cell, CELL-CENTERED (GridMap
# places item origins at cell centers): every piece's ports end in a bolted
# FLANGE at the cell face, so any assembly shows real jointing at every seam.
# One elbow covers every orthogonal pair ("from above to left" included) via
# GridMap's 24 orientations; the auto-tiler (scripts/game/world/pipe_grid.gd)
# picks piece + orientation from each cell's neighbour mask. Canonical ports
# (GODOT frame): straight ±X · elbow +X,+Y · tee ±X,+Y · cross ±X,±Y · end +X.
# (Blender Z here becomes Godot +Y on export.)

_PIPE_R = 0.15
_FLANGE_R = 0.22

def _pipe_mats():
    return [_flat_mat("pp_steel_m", CH("pipe_joint"), rough=0.55),
            _flat_mat("pp_rust_m", CH("rust"), rough=0.85),
            _flat_mat("pp_dark_m", CH("iron_dark"), rough=0.6)]

def _pipe_flange(bm, face_center, axis):
    hs_prism(bm, face_center, _FLANGE_R, _FLANGE_R, 0.06, 1, sides=8,
             bevel=0.015, axis=axis)
    hs_bolts(bm, face_center, 0.185, 4, 2, bolt_r=0.024, bolt_h=0.04, axis=axis)

def _pipe_arm(bm, axis, sign):
    if axis == 'X':
        hs_prism(bm, (sign * 0.26, 0, 0), _PIPE_R, _PIPE_R, 0.5, 0, sides=8,
                 bevel=0.02, axis='X')
        _pipe_flange(bm, (sign * 0.45, 0, 0), 'X')
    else:
        hs_prism(bm, (0, 0, sign * 0.26), _PIPE_R, _PIPE_R, 0.5, 0, sides=8,
                 bevel=0.02, axis='Z')
        _pipe_flange(bm, (0, 0, sign * 0.45), 'Z')

def _pipe_corner(bm):
    _bev_box(bm, (0, 0, 0), (0.36, 0.36, 0.36), 2, bevel=0.05)

def build_pipe_straight():
    """Two ports ±X; the workhorse run tile."""
    bm = _bmesh.new()
    hs_prism(bm, (0, 0, 0), _PIPE_R, _PIPE_R, 1.0, 0, sides=8, bevel=0.02, axis='X')
    _pipe_flange(bm, (-0.45, 0, 0), 'X')
    _pipe_flange(bm, (0.45, 0, 0), 'X')
    return _hs_finish("PipeStraight", bm, _pipe_mats())

def build_pipe_elbow():
    """Ports +X and UP (Godot +Y): the one bend — 24 orientations cover every
    above-to-left, left-to-forward, any orthogonal pair."""
    bm = _bmesh.new()
    _pipe_arm(bm, 'X', 1)
    _pipe_arm(bm, 'Z', 1)
    _pipe_corner(bm)
    return _hs_finish("PipeElbow", bm, _pipe_mats())

def build_pipe_tee():
    """Ports ±X and UP."""
    bm = _bmesh.new()
    _pipe_arm(bm, 'X', 1)
    _pipe_arm(bm, 'X', -1)
    _pipe_arm(bm, 'Z', 1)
    _pipe_corner(bm)
    return _hs_finish("PipeTee", bm, _pipe_mats())

def build_pipe_cross():
    """Ports ±X and ±UP (a planar four-way)."""
    bm = _bmesh.new()
    for ax, sg in (('X', 1), ('X', -1), ('Z', 1), ('Z', -1)):
        _pipe_arm(bm, ax, sg)
    _pipe_corner(bm)
    return _hs_finish("PipeCross", bm, _pipe_mats())

def build_pipe_end():
    """One port +X, dead-ended in a bolted blind flange."""
    bm = _bmesh.new()
    _pipe_arm(bm, 'X', 1)
    hs_prism(bm, (-0.04, 0, 0), 0.24, 0.24, 0.09, 1, sides=8, bevel=0.018, axis='X')
    hs_bolts(bm, (-0.09, 0, 0), 0.16, 5, 2, bolt_r=0.024, bolt_h=0.045, axis='X')
    return _hs_finish("PipeEnd", bm, _pipe_mats())

def build_pipe_straight_banded():
    """A straight with service collars — run variation."""
    bm = _bmesh.new()
    hs_prism(bm, (0, 0, 0), _PIPE_R, _PIPE_R, 1.0, 0, sides=8, bevel=0.02, axis='X')
    _pipe_flange(bm, (-0.45, 0, 0), 'X')
    _pipe_flange(bm, (0.45, 0, 0), 'X')
    for bx in (-0.16, 0.16):
        hs_prism(bm, (bx, 0, 0), 0.19, 0.19, 0.09, 1, sides=8, bevel=0.015, axis='X')
    return _hs_finish("PipeStraightBanded", bm, _pipe_mats())

def build_pipe_straight_valve():
    """A straight with an inline valve wheel — the run's rare punctuation."""
    bm = _bmesh.new()
    hs_prism(bm, (0, 0, 0), _PIPE_R, _PIPE_R, 1.0, 0, sides=8, bevel=0.02, axis='X')
    _pipe_flange(bm, (-0.45, 0, 0), 'X')
    _pipe_flange(bm, (0.45, 0, 0), 'X')
    hs_prism(bm, (0, 0, 0.2), 0.06, 0.06, 0.24, 2, sides=6, bevel=0.01, axis='Z')
    hs_torus(bm, (0, 0, 0.34), 0.15, 0.032, 1, major_segs=10, minor_segs=5, axis='Z')
    return _hs_finish("PipeStraightValve", bm, _pipe_mats())


# ---- FAUNA BODIES + REMAINING VOCABULARY (contact-sheet pass, 2026-07-28) -----
# The Sapscrap body is built TO ITS CANON CARD (fauna_image_prompts.md): a low
# disc, three hooked palps in C3 symmetry around a recessed central mouth-pit,
# deep red-violet matte chitin (the iron-enterobactin complex color), stub-legs
# hidden beneath, and ONLY the chelating clamps sharply rendered. The palp-tip
# tell material is emissive-capable (one palp brightens toward magenta before
# the clamp) — the Enemy drives that state; the body just carries the material.

def CF(role):
    return C("fauna", role)

def build_sapscrap_body():
    bm = _bmesh.new()
    M_CHITIN, M_PLATE, M_CLAMP, M_TELL = 0, 1, 2, 3
    # the low disc: faceted chitin dome, wider at the skirt
    hs_prism(bm, (0, 0, 0.17), 0.30, 0.36, 0.20, M_CHITIN, sides=9, bevel=0.03)
    hs_prism(bm, (0, 0, 0.325), 0.16, 0.30, 0.13, M_PLATE, sides=9, bevel=0.025)
    # the recessed central mouth-pit (read from the game's high camera)
    hs_prism(bm, (0, 0, 0.40), 0.085, 0.11, 0.05, M_CLAMP, sides=6, bevel=0.01)
    for i in range(3):
        a = math.tau * i / 3.0
        ca, sa = math.cos(a), math.sin(a)
        # stub-leg hidden beneath, one per palp segment
        hs_prism(bm, (0.16 * ca, 0.16 * sa, 0.05), 0.05, 0.06, 0.10, M_CHITIN,
                 sides=6, bevel=0.01)
        # palp segment A: out and slightly down from the skirt
        _bev_box_r(bm, (0.42 * ca, 0.42 * sa, 0.20), (0.30, 0.13, 0.11), M_PLATE,
                   rot=(0.0, 0.18, a), bevel=0.02)
        # palp segment B: the forward hook, curling DOWN toward the grab
        _bev_box_r(bm, (0.60 * ca, 0.60 * sa, 0.16), (0.20, 0.10, 0.09), M_PLATE,
                   rot=(0.0, 0.42, a), bevel=0.018)
        # the chelating clamp: two sharp pincer wedges opening sideways at
        # fixture height — the only crisp feature on the body (canon card)
        for jaw in (-1, 1):
            _bev_box_r(bm, (0.73 * ca - 0.045 * sa * jaw, 0.73 * sa + 0.045 * ca * jaw,
                            0.085), (0.13, 0.026, 0.045), M_TELL if jaw > 0 else M_CLAMP,
                       rot=(0.0, 0.18, a + 0.12 * jaw), bevel=0.008)
    return _hs_finish("SapscrapBody", bm, [
        _flat_mat("fa_ss_chitin_m", CF("sapscrap_chitin"), rough=0.85),
        _flat_mat("fa_ss_plate_m", CF("sapscrap_plate"), rough=0.8),
        _flat_mat("fa_ss_clamp_m", CF("sapscrap_clamp"), rough=0.45),
        _flat_mat("fa_ss_tell_m", CF("sapscrap_clamp"), emit=CF("sapscrap_tell"),
                  emit_strength=0.35, rough=0.45),
    ])


def build_drum_crown():
    """The drum's crown: a 90-degree rim lip riding the shell top — chord plates
    with a rolled bead, stud rivets, the recessed maintenance ring."""
    bm = _bmesh.new()
    M_IRON, M_RUST = 0, 1
    segs = 24
    for si in range(segs):
        a = (math.pi * 0.5) * (si + 0.5) / segs
        _bev_box_r(bm, (6.5 * math.cos(a), 6.5 * math.sin(a), 0.28),
                   (0.45, 0.22, 0.56), M_IRON, rot=(0.0, 0.0, a + math.pi * 0.5),
                   bevel=0.025)
        _bev_box_r(bm, (6.56 * math.cos(a), 6.56 * math.sin(a), 0.60),
                   (0.46, 0.14, 0.12), M_RUST, rot=(0.0, 0.0, a + math.pi * 0.5),
                   bevel=0.03)
        if si % 3 == 1:
            _bev_box_r(bm, (6.66 * math.cos(a), 6.66 * math.sin(a), 0.30),
                       (0.08, 0.08, 0.08), M_RUST, rot=(0.0, 0.0, a + math.pi * 0.5),
                       bevel=0.012)
    return _hs_finish("DrumCrown", bm, [
        _flat_mat("as_crown_iron_m", _dim(CH("iron_dark"), 0.9), rough=0.65),
        _flat_mat("as_crown_rust_m", CH("rust"), rough=0.85),
    ])


def build_pipe_bracket():
    """The pipe run's wall stand-off: back plate, arm, half-clamp around the
    one-metre module's pipe radius, bolts — the dressing that grounds a wall run."""
    bm = _bmesh.new()
    M_DARK, M_RUST = 0, 1
    _bev_box(bm, (0, 0.14, 0), (0.2, 0.05, 0.2), M_DARK, bevel=0.012)      # back plate
    hs_bolts(bm, (0, 0.15, 0), 0.075, 4, 1, bolt_r=0.02, bolt_h=0.03, axis='Y')
    _bev_box(bm, (0, 0.02, 0), (0.09, 0.2, 0.09), M_DARK, bevel=0.015)     # arm
    hs_torus(bm, (0, -0.10, 0), 0.17, 0.035, M_RUST, major_segs=10,
             minor_segs=5, axis='Y')                                        # the clamp ring
    return _hs_finish("PipeBracket", bm, [
        _flat_mat("as_bracket_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("as_bracket_rust_m", CH("rust"), rough=0.85),
    ])


def build_cage_lamp():
    """The amber caged work lamp — the crew's ordinary light, distinct from the
    red bar signage: hook stem, bar cage, warm emissive core."""
    bm = _bmesh.new()
    M_DARK, M_AMBER = 0, 1
    _bev_box(bm, (0, 0, 0.46), (0.05, 0.05, 0.16), M_DARK, bevel=0.01)      # stem
    hs_prism(bm, (0, 0, 0.37), 0.10, 0.10, 0.035, M_DARK, sides=8, bevel=0.008)
    hs_prism(bm, (0, 0, 0.12), 0.095, 0.095, 0.03, M_DARK, sides=8, bevel=0.008)
    for i in range(4):                                                       # cage bars
        a = math.tau * i / 4.0
        _bev_box_r(bm, (0.095 * math.cos(a), 0.095 * math.sin(a), 0.245),
                   (0.022, 0.022, 0.24), M_DARK, rot=(0.0, 0.0, a), bevel=0.005)
    hs_prism(bm, (0, 0, 0.245), 0.055, 0.055, 0.17, M_AMBER, sides=6, bevel=0.01)
    return _hs_finish("CageLamp", bm, [
        _flat_mat("as_cage_dark_m", CH("iron_dark"), rough=0.6),
        _flat_mat("as_cage_amber_m", _dim(CH("lamp"), 0.5), emit=CH("lamp"),
                  emit_strength=1.6, rough=0.4),
    ])


# ---- SIDE-CHANNEL VARIATIONS (director: "more variations of the side channel
# ---- part") — the trough section re-rolled with different snake curves, bank
# ---- stagger, and patch layouts, so a run never repeats one silhouette.

def _channel_variant(name, snake_phase, snake_amp, patches, grates, wheel_side):
    bm = _bmesh.new()
    M_DARK, M_RUST, M_WOOD, M_WATER, M_FOAM, M_HEX = 0, 1, 2, 3, 4, 5
    _bev_box(bm, (0, 0, 0.13), (2.4, 1.3, 0.26), M_DARK, bevel=0.02)
    for sy in (-0.62, 0.62):
        _bev_box(bm, (0, sy, 0.28), (2.4, 0.12, 0.07), M_RUST, bevel=0.015)
        for bx in (-0.95, -0.35, 0.35, 0.95):
            hs_bolts(bm, (bx, sy, 0.32), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.03)
    for sx in (-1.17, 1.17):
        _bev_box(bm, (sx, 0, 0.28), (0.12, 1.3, 0.07), M_RUST, bevel=0.015)
    for (px, py, pw, pd) in patches:
        for k in range(3):
            _bev_box(bm, (px, py - pd / 2 + (k + 0.5) * pd / 3, 0.285),
                     (pw, pd / 3 - 0.015, 0.05), M_WOOD, bevel=0.01)
    for (gx, gy) in grates:
        _bev_box(bm, (gx, gy, 0.27), (0.7, 0.42, 0.03), M_DARK, bevel=0.008)
        _hex_holes(bm, [(gx + dx, gy + dy, 0.285) for (dx, dy) in
                        _honeycomb(0, 0, 5, 3, 0.13)], 0.05, 0.015, M_HEX)
    for k in range(9):
        t = k / 8.0
        wx = -1.05 + t * 2.1
        wy = snake_amp * math.sin(t * math.tau * 0.75 + snake_phase)
        _bev_box(bm, (wx, wy, 0.255), (0.3, 0.46, 0.05), M_WATER, bevel=0.006)
        if k % 2 == 1:
            for side in (-1, 1):
                _bev_box(bm, (wx + 0.06 * side, wy + side * 0.3, 0.29),
                         (0.22, 0.09, 0.09), M_RUST if k % 4 else M_DARK, bevel=0.012)
        if k % 3 == 2:
            _bev_box(bm, (wx, wy - 0.1, 0.285), (0.1, 0.08, 0.02), M_FOAM, bevel=0.004)
    hs_torus(bm, (0.85 * wheel_side, -0.66, 0.14), 0.09, 0.02, M_RUST,
             major_segs=10, minor_segs=5, axis='Y')
    hs_prism(bm, (0.85 * wheel_side, -0.63, 0.14), 0.03, 0.03, 0.08, M_DARK,
             sides=6, bevel=0.008, axis='Y')
    return _hs_finish(name, bm, [
        _flat_mat("cp_wc_dark_m2" + name, CH("iron_dark"), rough=0.6),
        _flat_mat("cp_wc_rust_m2" + name, CH("rust"), rough=0.8),
        _flat_mat("cp_wood_m2" + name, CH("wood"), rough=0.85),
        _flat_mat("cp_wc_water_m2" + name, _dim(CH("water"), 0.75), emit=CH("water"),
                  emit_strength=0.85, rough=0.22),
        _flat_mat("cp_wc_foam_m2" + name, CH("foam"), emit=_dim(CH("foam"), 0.8),
                  emit_strength=0.8, rough=0.5),
        _flat_mat("cp_wc_hex_m2" + name, _dim(CH("iron_dark"), 0.6), rough=0.7),
    ])

def build_water_channel_b():
    """Variant B: inverted snake, single long plank patch, grate at the far end."""
    return _channel_variant("WaterChannelB", math.pi, 0.31,
        [(-0.55, -0.35, 0.95, 0.4)], [(0.85, 0.4)], -1)

def build_water_channel_c():
    """Variant C: tight shallow snake, twin small patches, twin grates, wheel left."""
    return _channel_variant("WaterChannelC", math.pi * 0.5, 0.18,
        [(-0.95, 0.42, 0.5, 0.38), (0.35, -0.44, 0.55, 0.36)],
        [(-0.25, -0.05), (1.0, 0.35)], 1)


# ---- HELICAL WATER BANDS (director, 2026-07-28: "the water being tiled looks
# ---- strange... two different appearances") ----------------------------------
# Wash water is no longer a grid of rigid sheets: each band is ONE piece of
# helical water baked along the canonical arc (KTHETA/KCLIMB mirror
# channels_arc.gd), spanning exactly ONE unit of s, so bands tile mouth-to-
# mouth around the coil with the climb built in. The deck band spans the whole
# walkway's radii; the trough band spans the channel's water line. Both wear
# the SAME water material as the trough's baked snake — one appearance.

_ARC_KTHETA = 0.0907    # radians of sweep per unit s (channels_arc.gd)
_ARC_KCLIMB = 0.1333    # height climbed per unit s

def _water_band_mats(name):
    return [_flat_mat("as_wash_water_m" + name, _dim(CH("water"), 0.75),
                      emit=CH("water"), emit_strength=0.85, rough=0.22),
            _flat_mat("as_wash_foam_m" + name, CH("foam"),
                      emit=_dim(CH("foam"), 0.8), emit_strength=0.8, rough=0.5)]

def _water_band(name, r_in, r_out, sign, seed=0):
    """One 1-s helical band from Blender angle 0 toward sign*KTHETA: stepped
    chord plates (the pixel-water grammar) riding the baked climb, foam flecks
    on a SEEDED deterministic scatter — three seeds ship per radius family so
    adjacent placed bands never share a constellation (the tiling audit caught
    one hardcoded six-fleck layout repeating verbatim mouth-to-mouth). `sign`
    sets bake handedness so the PLACED band climbs WITH the helix — the
    chunk's datum probe verifies it, never eyes."""
    import random as _rnd
    rng = _rnd.Random(1097 + seed * 131 + int(r_in * 7.0))
    bm = _bmesh.new()
    M_WATER, M_FOAM = 0, 1
    r_mid = (r_in + r_out) * 0.5
    steps = 8
    # _bev_box_r sizes are FULL extents, and under rot z = a + pi/2 the box's
    # local X runs TANGENTIALLY (the drum's chord-plate convention): each step
    # is a thin tangential chord spanning the FULL radial width, overlapping
    # its neighbours slightly so the surface never slits.
    t_full = r_out * _ARC_KTHETA / steps * 1.12
    r_full = r_out - r_in
    for k in range(steps):
        frac = (k + 0.5) / steps
        a = sign * _ARC_KTHETA * frac
        wz = frac * _ARC_KCLIMB + 0.03 + 0.012 * math.sin(k * 2.3 + seed * 1.7)
        _bev_box_r(bm, (r_mid * math.cos(a), r_mid * math.sin(a), wz),
                   (t_full, r_full, 0.07), M_WATER,
                   rot=(0.0, 0.0, a + math.pi * 0.5), bevel=0.006)
    # foam: mixed CHIPS and elongated FLOW STREAKS (long axis tangential —
    # the water's direction), jittered per seed, kept off the band edges
    for _f in range(5 + rng.randrange(3)):
        fr = rng.uniform(0.1, 0.9)
        fa = rng.uniform(0.06, 0.94)
        if rng.random() < 0.38:
            size = (rng.uniform(0.34, 0.55), rng.uniform(0.05, 0.075), 0.024)
        else:
            size = (rng.uniform(0.1, 0.24), rng.uniform(0.08, 0.17), 0.03)
        a = sign * _ARC_KTHETA * fa
        rr = r_in + (r_out - r_in) * fr
        wz = fa * _ARC_KCLIMB + 0.075
        _bev_box_r(bm, (rr * math.cos(a), rr * math.sin(a), wz),
                   size, M_FOAM,
                   rot=(0.0, 0.0, a + math.pi * 0.5), bevel=0.004)
    return _hs_finish(name, bm, _water_band_mats(name))

def build_water_band_deck():
    """The surge: one s-unit of murky wash water covering the WHOLE walkway."""
    return _water_band("WaterBandDeck", 7.2, 14.9, -1.0)

def build_water_band_trough():
    """The channel's own risen water line — same material, same grammar."""
    return _water_band("WaterBandTrough", 15.05, 16.15, -1.0)

def build_water_band_deck_b():
    """Deck water band, foam constellation B."""
    return _water_band("WaterBandDeckB", 7.2, 14.9, -1.0, seed=1)

def build_water_band_deck_c():
    """Deck water band, foam constellation C."""
    return _water_band("WaterBandDeckC", 7.2, 14.9, -1.0, seed=2)

def build_water_band_trough_b():
    """Trough water band, foam constellation B."""
    return _water_band("WaterBandTroughB", 15.05, 16.15, -1.0, seed=1)

def build_water_band_trough_c():
    """Trough water band, foam constellation C."""
    return _water_band("WaterBandTroughC", 15.05, 16.15, -1.0, seed=2)



# ---- THE SLUICE BED (director, 2026-07-29: "parts underneath the channel
# ---- streams should look like sluices or the bottoms of pipes, not wood") ---
# The floor IS the danger read: every deck tile inside a wash section's span is
# this iron sluice bed; wood planks exist only on safe ground. Same 2.0 m
# tile-module family as deck_planks/deck_grate. NOTE: chain-bootstrap geometry —
# flagged for interactive Blender refinement per the model-in-Blender rule.

def build_deck_sluice():
    """A wash-section SLUICE BED tile: a shallow concave iron channel bottom —
    stepped side skirts descending from flush walk-edges to a recessed center
    drain lane with slot cuts, wear-polished flow streaks along X (the water's
    direction), bolted edge rails, rust at the waterline steps."""
    bm = _bmesh.new()
    M_IRON, M_RUST, M_DARK, M_SLOT = 0, 1, 2, 3
    for sy in (-0.94, 0.94):                                       # edge rails, flush with plank height
        _bev_box(bm, (0, sy, 0.045), (2.0, 0.12, 0.09), M_IRON, bevel=0.02)
        for bx in (-0.8, -0.27, 0.27, 0.8):
            hs_bolts(bm, (bx, sy, 0.095), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.025)
    for (off, z, mat) in ((0.665, 0.05, M_RUST), (0.38, 0.028, M_IRON)):
        for sgn in (-1, 1):                                        # stepped skirts down to the bed
            _bev_box(bm, (0, sgn * off, z), (2.0, 0.22, 0.05), mat, bevel=0.012)
    _bev_box(bm, (0, 0, 0.012), (2.0, 0.55, 0.024), M_DARK, bevel=0.01)   # the bed floor
    for k in range(5):                                             # drain slot cuts down the center
        _bev_box(bm, (-0.8 + k * 0.4, 0, 0.02), (0.22, 0.09, 0.012), M_SLOT, bevel=0.004)
    for k in range(4):                                             # flow-polish streaks along X
        _bev_box(bm, (-0.5 + k * 0.34, 0.18 - 0.12 * (k % 2), 0.026), (0.5, 0.05, 0.008),
                 M_IRON, bevel=0.004)
    return _hs_finish("DeckSluice", bm, [
        _flat_mat("as_sluice_iron_m", _dim(CH("iron"), 0.85), rough=0.5),
        _flat_mat("as_sluice_rust_m", CH("rust"), rough=0.85),
        _flat_mat("as_sluice_dark_m", _dim(CH("iron_dark"), 0.8), rough=0.65),
        _flat_mat("as_sluice_slot_m", _dim(CH("iron_dark"), 0.35), rough=0.9)])

def _sluice_shell(bm, M_IRON, M_RUST, M_DARK):
    """The shared sluice carcass: edge rails + bolts, stepped skirts, bed
    floor. Variants differ only in slots, streaks, and wear."""
    for sy in (-0.94, 0.94):
        _bev_box(bm, (0, sy, 0.045), (2.0, 0.12, 0.09), M_IRON, bevel=0.02)
        for bx in (-0.8, -0.27, 0.27, 0.8):
            hs_bolts(bm, (bx, sy, 0.095), 0.0, 1, M_DARK, bolt_r=0.022, bolt_h=0.025)
    for (off, z, mat) in ((0.665, 0.05, M_RUST), (0.38, 0.028, M_IRON)):
        for sgn in (-1, 1):
            _bev_box(bm, (0, sgn * off, z), (2.0, 0.22, 0.05), mat, bevel=0.012)
    _bev_box(bm, (0, 0, 0.012), (2.0, 0.55, 0.024), M_DARK, bevel=0.01)

def build_deck_sluice_b():
    """Sluice bed variation B: slots off-pitch with one CLOGGED (a rust wad
    sits in it), streaks re-phased and one doubled — the lane that carries
    more debris."""
    bm = _bmesh.new()
    M_IRON, M_RUST, M_DARK, M_SLOT = 0, 1, 2, 3
    _sluice_shell(bm, M_IRON, M_RUST, M_DARK)
    for k in range(4):
        _bev_box(bm, (-0.72 + k * 0.47, 0.04, 0.02), (0.26, 0.09, 0.012), M_SLOT, bevel=0.004)
    _bev_box(bm, (-0.72 + 1 * 0.47, 0.04, 0.03), (0.2, 0.07, 0.022), M_RUST, bevel=0.006)
    for (kx, ky, kl) in ((-0.62, -0.16, 0.6), (0.05, 0.22, 0.42), (0.42, -0.1, 0.36), (0.78, 0.14, 0.5)):
        _bev_box(bm, (kx, ky, 0.026), (kl, 0.05, 0.008), M_IRON, bevel=0.004)
    _bev_box(bm, (-0.2, -0.14, 0.028), (0.34, 0.045, 0.008), M_IRON, bevel=0.004)
    return _hs_finish("DeckSluiceB", bm, [
        _flat_mat("as_sluice_iron_mB", _dim(CH("iron"), 0.85), rough=0.5),
        _flat_mat("as_sluice_rust_mB", CH("rust"), rough=0.85),
        _flat_mat("as_sluice_dark_mB", _dim(CH("iron_dark"), 0.8), rough=0.65),
        _flat_mat("as_sluice_slot_mB", _dim(CH("iron_dark"), 0.35), rough=0.9)])

def build_deck_sluice_c():
    """Sluice bed variation C: a bolted REPAIR PLATE over the bed's left
    third (the crews patched this one), three slots crowding the right, a
    chipped skirt step, streaks sparse."""
    bm = _bmesh.new()
    M_IRON, M_RUST, M_DARK, M_SLOT = 0, 1, 2, 3
    _sluice_shell(bm, M_IRON, M_RUST, M_DARK)
    _bev_box(bm, (-0.55, 0, 0.03), (0.75, 0.5, 0.02), M_IRON, bevel=0.01)
    for (px, py) in ((-0.86, -0.18), (-0.86, 0.18), (-0.24, -0.18), (-0.24, 0.18)):
        hs_bolts(bm, (px, py, 0.045), 0.0, 1, M_DARK, bolt_r=0.018, bolt_h=0.02)
    for k in range(3):
        _bev_box(bm, (0.28 + k * 0.34, -0.02, 0.02), (0.2, 0.09, 0.012), M_SLOT, bevel=0.004)
    _bev_box(bm, (0.62, 0.665, 0.05), (0.5, 0.2, 0.048), M_DARK, bevel=0.01)
    for (kx, ky, kl) in ((0.3, 0.18, 0.44), (0.72, -0.16, 0.38)):
        _bev_box(bm, (kx, ky, 0.026), (kl, 0.05, 0.008), M_IRON, bevel=0.004)
    return _hs_finish("DeckSluiceC", bm, [
        _flat_mat("as_sluice_iron_mC", _dim(CH("iron"), 0.85), rough=0.5),
        _flat_mat("as_sluice_rust_mC", CH("rust"), rough=0.85),
        _flat_mat("as_sluice_dark_mC", _dim(CH("iron_dark"), 0.8), rough=0.65),
        _flat_mat("as_sluice_slot_mC", _dim(CH("iron_dark"), 0.35), rough=0.9)])
