# STRUCTURAL SCAFFOLDING + TILEABLE CONSTRUCTIONS — exec-included after
# concept_pass1.py (uses the hard-surface kit + _bev_box_r). The level's decks
# and walls should read as BUILT and SUPPORTED: trusses hang under walkways,
# legs carry piers, pipes run in racks, railings guard edges, wall panels tile.
# Every piece is TILEABLE along X at a 2.0 m module unless noted; assembly law
# applies (chamfers, bolts at joints, feet/plates, open pipe bores).

def build_scaffold_truss():
    """A 2.0 m under-deck TRUSS BAY: top and bottom chords, end verticals, two
    diagonal braces meeting at gusset plates with bolts. Hung beneath a walkway
    (placer offsets it down); tiles end-to-end along the deck run."""
    bm = _bmesh.new()
    M_DARK, M_RUST = 0, 1
    for z in (0.06, 1.14):                                                     # chords
        _bev_box(bm, (0, 0, z), (2.0, 0.13, 0.12), M_DARK, bevel=0.015)
    for sx in (-0.94, 0.94):                                                   # end verticals
        _bev_box(bm, (sx, 0, 0.6), (0.12, 0.12, 1.0), M_DARK, bevel=0.015)
    _bev_box_r(bm, (-0.45, 0, 0.6), (1.18, 0.09, 0.09), M_RUST,
               rot=(0.0, -0.72, 0.0), bevel=0.012)                             # diagonal
    _bev_box_r(bm, (0.45, 0, 0.6), (1.18, 0.09, 0.09), M_RUST,
               rot=(0.0, 0.72, 0.0), bevel=0.012)                              # diagonal
    for sx in (-0.94, 0.0, 0.94):                                              # gussets + bolts
        for z in (0.06, 1.14):
            _bev_box(bm, (sx, -0.08, z), (0.2, 0.04, 0.2), M_RUST, bevel=0.008)
            hs_bolts(bm, (sx, -0.1, z), 0.055, 4, M_DARK, bolt_r=0.02,
                     bolt_h=0.03, axis='Y', phase=math.pi / 4)
    return _hs_finish("ScaffoldTruss", bm, [
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])


def build_scaffold_leg():
    """A 3.2 m support LEG: bolted foot plate, chamfered column, a collar flange
    at mid-height, stub brace arms, and a top saddle plate that meets the deck."""
    bm = _bmesh.new()
    M_DARK, M_RUST = 0, 1
    _bev_box(bm, (0, 0, 0.04), (0.56, 0.56, 0.08), M_RUST, bevel=0.015)        # foot plate
    hs_bolts(bm, (0, 0, 0.08), 0.21, 4, M_DARK, phase=math.pi / 4)
    hs_prism(bm, (0, 0, 1.62), 0.11, 0.14, 3.1, M_DARK, sides=8, bevel=0.02)   # column
    hs_prism(bm, (0, 0, 1.6), 0.18, 0.18, 0.08, M_RUST, sides=8, bevel=0.012)  # collar flange
    hs_bolts(bm, (0, 0, 1.65), 0.15, 6, M_DARK, bolt_r=0.02, bolt_h=0.03)
    for a in (0.0, math.pi / 2, math.pi, 3 * math.pi / 2):                     # stub brace arms
        _bev_box_r(bm, (0.3 * math.cos(a), 0.3 * math.sin(a), 2.6),
                   (0.5, 0.07, 0.07), M_RUST, rot=(0.0, 0.0, a), bevel=0.01)
    _bev_box(bm, (0, 0, 3.16), (0.6, 0.6, 0.08), M_DARK, bevel=0.015)          # saddle plate
    hs_bolts(bm, (0, 0, 3.2), 0.23, 4, M_RUST, phase=math.pi / 4)
    return _hs_finish("ScaffoldLeg", bm, [
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])


def build_railing_run():
    """A 2.0 m RAILING segment: three chamfered posts on bolted feet, a top rail,
    a mid rail, and a kick plate at the deck. Tiles along walkway edges."""
    bm = _bmesh.new()
    M_DARK, M_WOOD = 0, 1
    for sx in (-0.95, 0.0, 0.95):                                              # posts + feet
        _bev_box(bm, (sx, 0, 0.5), (0.09, 0.09, 0.94), M_DARK, bevel=0.012)
        _bev_box(bm, (sx, 0, 0.025), (0.16, 0.16, 0.05), M_DARK, bevel=0.008)
        hs_bolts(bm, (sx, 0, 0.05), 0.055, 2, M_DARK, bolt_r=0.016,
                 bolt_h=0.025, phase=math.pi / 2)
    _bev_box(bm, (0, 0, 0.99), (2.06, 0.12, 0.09), M_WOOD, bevel=0.015)        # top rail (worn wood)
    _bev_box(bm, (0, 0, 0.58), (2.02, 0.07, 0.06), M_DARK, bevel=0.01)         # mid rail
    _bev_box(bm, (0, 0, 0.09), (2.02, 0.05, 0.14), M_DARK, bevel=0.008)        # kick plate
    return _hs_finish("RailingRun", bm, [
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rail_wood_m", _dim(CH("wood"), 0.85), rough=0.85)])


def build_pipe_rack():
    """A 2.0 m PIPE RACK segment: two U-posts carrying three pipe runs with OPEN
    bores at the module ends, held by bolted straps. The Plumbing Power Project's
    veins, racked. Tiles end-to-end so runs read continuous."""
    bm = _bmesh.new()
    M_DARK, M_PIPE, M_RUST = 0, 1, 2
    for sx in (-0.85, 0.85):                                                   # U-posts
        _bev_box(bm, (sx, 0, 0.62), (0.12, 0.12, 1.2), M_DARK, bevel=0.015)
        _bev_box(bm, (sx, 0, 0.03), (0.3, 0.24, 0.06), M_RUST, bevel=0.01)     # feet
    heights = (0.42, 0.78, 1.12)
    radii = (0.09, 0.07, 0.055)
    for (hz, r) in zip(heights, radii):
        hs_prism(bm, (0, 0.02, hz), r, r, 2.0, M_PIPE, sides=10, bevel=0.012, axis='X')
        for sx in (-1.0, 1.0):                                                 # open bores at ends
            hs_tube(bm, (sx, 0.02, hz), r + 0.015, r * 0.62, 0.06, M_DARK, sides=10, axis='X')
        for sx in (-0.85, 0.85):                                               # straps + bolts
            _bev_box(bm, (sx, 0.02, hz + r * 0.5), (0.1, 0.2, 0.05), M_RUST, bevel=0.008)
            hs_bolts(bm, (sx, -0.08, hz), 0.0, 1, M_DARK, bolt_r=0.016, bolt_h=0.025, axis='Y')
    return _hs_finish("PipeRack", bm, [
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_pipe_m", CH("pipe"), rough=0.55),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])


def build_wall_panel_tile():
    """A 2.0 x 2.4 TILEABLE riveted wall panel (faces -Y): plate, edge frame,
    one cross seam, rivet rows on the frame lines. Butts seamlessly in X."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_RUST = 0, 1, 2
    _bev_box(bm, (0, 0.1, 1.2), (2.0, 0.2, 2.4), M_IRON, bevel=0.02)           # the plate
    for sx in (-0.97, 0.97):                                                   # vertical frame ribs
        _bev_box(bm, (sx, -0.02, 1.2), (0.07, 0.08, 2.4), M_DARK, bevel=0.01)
    for z in (0.05, 2.35):                                                     # horizontal frame ribs
        _bev_box(bm, (0, -0.02, z), (2.0, 0.08, 0.09), M_DARK, bevel=0.01)
    _bev_box(bm, (0, -0.015, 1.28), (2.0, 0.06, 0.06), M_RUST, bevel=0.008)    # cross seam
    for sx in (-0.7, 0.0, 0.7):                                                # rivet rows
        for z in (0.24, 1.28, 2.18):
            hs_bolts(bm, (sx, -0.06, z), 0.0, 1, M_RUST, bolt_r=0.02,
                     bolt_h=0.035, axis='Y')
    return _hs_finish("WallPanelTile", bm, [
        _flat_mat("sc_iron_m", CH("iron"), rough=0.6),
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])


# ---- TILE VARIATIONS (director: pieces fit a tile-size space and carry
# ---- variations). All on the 2.0 m module; a GridMap or grid-snapped placer
# ---- alternates them so no two neighbouring cells read stamped.

def build_deck_planks_b():
    """Plank tile variation B: different board rhythm, a crosswise repair patch."""
    b = Builder()
    pitch = 0.27 + 0.015
    y0 = -3 * pitch
    order = ["deck_wood_worn", "deck_wood", "deck_wood", "deck_wood_worn",
             "deck_wood", "deck_wood_worn", "deck_wood"]
    for i in range(7):
        lift = 0.01 if i in (2, 4) else 0.0
        b.box((0, y0 + i * pitch, 0.04 + lift), (2.0, 0.27, 0.08), order[i])
    b.box((0.3, 0, 0.09), (0.3, 1.4, 0.05), "deck_wood")          # crosswise repair board
    for sx in (-0.82, 0.82):
        b.box((sx, 0, 0.075), (0.07, 1.98, 0.03), "grate_iron")
    b.box((-0.5, y0 + 1 * pitch, 0.084), (0.26, 0.15, 0.01), "deck_wood_worn")
    return b.finish("DeckPlanksB")


def build_deck_planks_c():
    """Plank tile variation C: one board MISSING — the dark underdeck shows, a
    strap bridges the gap (the worn corner of the walkway)."""
    b = Builder()
    pitch = 0.27 + 0.015
    y0 = -3 * pitch
    for i in range(7):
        if i == 4:
            continue                                              # the missing board
        part = "deck_wood" if i % 2 == 0 else "deck_wood_worn"
        b.box((0, y0 + i * pitch, 0.04), (2.0, 0.27, 0.08), part)
    b.box((0, y0 + 4 * pitch, 0.012), (2.0, 0.27, 0.024), "grate_iron")   # dark underdeck
    b.box((-0.35, y0 + 4 * pitch, 0.075), (0.34, 0.3, 0.035), "grate_iron")  # bridging strap
    for sx in (-0.82, 0.82):
        b.box((sx, 0, 0.075), (0.07, 1.98, 0.03), "grate_iron")
    return b.finish("DeckPlanksC")


def build_deck_grate_b():
    """Grate tile variation B: one corner cell BROKEN — bars gone, a dark hole
    with a bent bar sagging into it."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_HOLE = 0, 1, 2
    _bev_box(bm, (0, 0, 0.006), (1.8, 1.8, 0.012), M_HOLE, bevel=0.006)
    for sy in (-0.95, 0.95):
        _bev_box(bm, (0, sy, 0.05), (2.0, 0.1, 0.1), M_DARK, bevel=0.015)
    for sx in (-0.95, 0.95):
        _bev_box(bm, (sx, 0, 0.05), (0.1, 1.8, 0.1), M_DARK, bevel=0.015)
    for t in (-0.72, -0.48, -0.24, 0.0, 0.24, 0.48, 0.72):
        # upper bars skip the broken corner (x>0.3, y>0.3)
        if t < 0.3:
            _bev_box(bm, (0, t, 0.07), (1.8, 0.05, 0.05), M_IRON, bevel=0.008)
        else:
            _bev_box(bm, (-0.35, t, 0.07), (1.1, 0.05, 0.05), M_IRON, bevel=0.008)
        _bev_box(bm, (t, -0.2, 0.035), (0.05, 1.4, 0.05), M_IRON, bevel=0.008)
    _bev_box_r(bm, (0.55, 0.62, 0.03), (0.62, 0.045, 0.045), M_IRON,
               rot=(0.35, 0.0, 0.4), bevel=0.006)                 # the sagging bent bar
    return _hs_finish("DeckGrateB", bm, [
        _flat_mat("sc_iron_m", CH("iron"), rough=0.6),
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_hole_m", _dim(CH("iron_dark"), 0.25), rough=0.95)])


def build_wall_panel_tile_b():
    """Wall tile variation B: a riveted PATCH PLATE over the lower corner and a
    lower cross seam — a repaired panel."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_RUST = 0, 1, 2
    _bev_box(bm, (0, 0.1, 1.2), (2.0, 0.2, 2.4), M_IRON, bevel=0.02)
    for sx in (-0.97, 0.97):
        _bev_box(bm, (sx, -0.02, 1.2), (0.07, 0.08, 2.4), M_DARK, bevel=0.01)
    for z in (0.05, 2.35):
        _bev_box(bm, (0, -0.02, z), (2.0, 0.08, 0.09), M_DARK, bevel=0.01)
    _bev_box(bm, (0, -0.015, 0.75), (2.0, 0.06, 0.06), M_RUST, bevel=0.008)   # low seam
    _bev_box(bm, (0.52, -0.05, 0.52), (0.8, 0.05, 0.7), M_RUST, bevel=0.012)  # patch plate
    for (px, pz) in ((0.2, 0.24), (0.84, 0.24), (0.2, 0.8), (0.84, 0.8)):
        hs_bolts(bm, (px, -0.085, pz), 0.0, 1, M_DARK, bolt_r=0.02, bolt_h=0.035, axis='Y')
    for sx in (-0.7, 0.0):
        for z in (0.24, 1.28, 2.18):
            hs_bolts(bm, (sx, -0.06, z), 0.0, 1, M_RUST, bolt_r=0.02, bolt_h=0.035, axis='Y')
    return _hs_finish("WallPanelTileB", bm, [
        _flat_mat("sc_iron_m", CH("iron"), rough=0.6),
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])


def build_wall_panel_tile_c():
    """Wall tile variation C: two vertical sub-panels, a rust drip streak, and a
    denser rivet spine — the aged panel."""
    bm = _bmesh.new()
    M_IRON, M_DARK, M_RUST = 0, 1, 2
    for (px, pw) in ((-0.5, 0.94), (0.5, 0.94)):
        _bev_box(bm, (px, 0.1, 1.2), (pw, 0.2, 2.4), M_IRON, bevel=0.02)
    _bev_box(bm, (0, -0.02, 1.2), (0.1, 0.09, 2.4), M_DARK, bevel=0.01)       # centre spine
    for sx in (-0.97, 0.97):
        _bev_box(bm, (sx, -0.02, 1.2), (0.07, 0.08, 2.4), M_DARK, bevel=0.01)
    for z in (0.05, 2.35):
        _bev_box(bm, (0, -0.02, z), (2.0, 0.08, 0.09), M_DARK, bevel=0.01)
    _bev_box(bm, (-0.55, -0.028, 1.55), (0.09, 0.045, 1.5), M_RUST, bevel=0.006)  # drip streak
    for z in (0.3, 0.62, 0.94, 1.26, 1.58, 1.9, 2.16):
        hs_bolts(bm, (0, -0.075, z), 0.0, 1, M_RUST, bolt_r=0.018, bolt_h=0.032, axis='Y')
    return _hs_finish("WallPanelTileC", bm, [
        _flat_mat("sc_iron_m", CH("iron"), rough=0.6),
        _flat_mat("sc_dark_m", CH("iron_dark"), rough=0.65),
        _flat_mat("sc_rust_m", CH("rust"), rough=0.8)])
