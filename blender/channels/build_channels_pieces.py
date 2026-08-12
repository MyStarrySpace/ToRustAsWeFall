# CHANNELS PIECES — the Plumbing Power Project's styling of the shared vocabulary.
#
# THE LAW (director, 2026-08-10): an ARCHETYPE is the abstract gameplay noun the
# generator places — water_control, class_gate, hide_slot, moving_platform. A
# DISTRICT styles it. The Channels render those nouns as rusted hydraulic hardware
# and dead-flora leavings; the Stacks will render the SAME nouns as drawer-stack
# furniture. So there is ONE pieces file per district — this one — and never a new
# file per prop batch (three scattered channels files is what earned the ruling).
#
# What belongs here: the channels styling of archetype nouns, the channels set
# pieces, and the channels dressing register. What does NOT: scene builds (a room,
# a stretch, the helix) — those stay in their own scripts and INSTANCE these
# pieces. The modelling vocabulary itself lives in paintlib.meshkit, shared with
# every other district so a channels prop and a stacks prop are built the same way.
#
# The piece GEOMETRY the wash-relay helix also places (the drum stack, the sector
# gates and their sign bands, fins, rails, crates, ledges…) lives in the shared
# channels_parts module, so this sheet and build_wash_dressing.py cut every piece
# from ONE source. Pieces authored only here stay here until a second script wants
# them.
#
# Run:  blender.exe -b --python blender/channels/build_channels_pieces.py
#       (Blender 5.1 — 4.2 cannot read the 5.x blends and renders the default cube)
# Outputs (game-ready, committed):
#   to-rust-as-we-fall/resources/models/channels/channels_pieces.gltf (+bin/tex)
# Source (gitignored):
#   blender/channels/channels_pieces.blend      — the inspectable labeled sheet
#   blender/channels/obj-exports/<Piece>.obj    — BlockBench hand-off
#   blender/channels/painted/<Piece>_tex.png    — hand-paint drop, wins on rebuild
#   C:/tmp/channels_cards/<Piece>.png           — per-piece eyeball cards

import bpy
import importlib
import math
import mathutils
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
SRC = os.path.join(BL, "channels")
for _p in (BL, SRC):
    if _p not in sys.path:
        sys.path.insert(0, _p)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder, DETAIL_SCREEN
from paintlib.painters import paint_wood_grain, paint_metal_panel
from paintlib import meshkit as mk
importlib.reload(mk)
# The shared modelling vocabulary under its bare names, because the exec-included
# builder files below were written against them.
from paintlib.meshkit import (
    _bmesh, _flat_mat, _hs_finish, _hs_tag, _bev_box, _bev_box_r, _stud_spheres,
    _skin_growth, hs_prism, hs_tube, hs_torus, hs_bolts, hs_frame, hs_inset_panel,
    hs_sphere, _hex_holes, _honeycomb, _hs_axis, _srgb_lin,
)
import channels_parts
importlib.reload(channels_parts)
# C as well as its rows: the exec-included builder files reach for the raw
# palette function (the Sapscrap body reads the fauna row through it).
from channels_parts import C, CH, CG, CS, _dim

OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
GLTF = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "channels",
                    "channels_pieces.gltf")
CARDS = r"C:\tmp\channels_cards"
for d in (OBJX, PAINTED, os.path.dirname(GLTF), CARDS):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

# The palette authority (data/palettes/level_palettes.json) and every channels part
# are registered by the shared module — never a hard-coded rgb, never a second copy
# of the register.
channels_parts.register()


def _grate_art(tile, isl, px_per_m):
    """The woven bar field, DRAWN. Repetition is a texture, never geometry: a
    modeled bar lattice aliases into mush at gameplay distance while a drawn one
    stays crisp, and the detail stays where an artist can edit it.

    Two layers read as woven — the upper run brighter, the lower run in shadow —
    over transparent holes that ARE the drop. Bar pitch is authored in METRES and
    converted here, so the tile is correct at any card size at 1 m = 32 px."""
    ph, pw = tile.shape[:2]
    pitch = max(4, int(round(0.21 * px_per_m)))      # bar centres, 21 cm apart
    bar = max(1, int(round(0.05 * px_per_m)))        # bar width, 5 cm
    iron = isl["rgb"]
    upper = tuple(min(1.0, c * 1.18) for c in iron)  # catches the light
    lower = tuple(c * 0.62 for c in iron)            # the layer beneath
    edge = tuple(c * 0.34 for c in iron)             # the bar's own shadow line

    tile[:, :, 3] = 0.0                              # holes first; bars are added
    for start in range(0, ph + pitch, pitch):        # LOWER run (along X)
        for row in range(start, min(start + bar, ph)):
            if 0 <= row < ph:
                tile[row, :, :3] = lower
                tile[row, :, 3] = 1.0
    for start in range(0, pw + pitch, pitch):        # UPPER run (along Y), on top
        for col in range(start, min(start + bar, pw)):
            if 0 <= col < pw:
                tile[:, col, :3] = upper
                tile[:, col, 3] = 1.0
    # one dark texel down each bar's trailing side: the weave reads as two layers
    for start in range(0, pw + pitch, pitch):
        col = start + bar
        if 0 <= col < pw:
            solid = tile[:, col - 1, 3] > 0.5
            tile[solid, col, :3] = edge
            tile[solid, col, 3] = 1.0
    for start in range(0, ph + pitch, pitch):
        row = start + bar
        if 0 <= row < ph:
            keep = tile[row, :, 3] < 0.5             # never overwrite the upper run
            tile[row, keep, :3] = edge
            tile[row, keep, 3] = 1.0
    tile[0, :, :3] = edge                            # the tile's own rim, so a
    tile[ph - 1, :, :3] = edge                       # grate never floats free of
    tile[:, 0, :3] = edge                            # its frame
    tile[:, pw - 1, :3] = edge
    for band in (tile[0, :], tile[ph - 1, :], tile[:, 0], tile[:, pw - 1]):
        band[:, 3] = 1.0


GRATE_ART = pl.register_card_art("grate_weave", _grate_art)


# ============================================================================
# PORTAL FIXTURES — docs/PORTALS.md (director-ratified 2026-07-25)
# A portal is TWO fixtures plus the lens: the ARCH (an upright ring whose
# APERTURE is the opening; dark when dormant, the runtime PortalLens fills it
# when live) and the PAD RING (the flat, clickable ground ring where the queue
# forms). Purple = local transit; the emissive lives only in the neon channels.
# Art direction: FLAT clean forms, detail carried by the low-res pixel atlas,
# hand-paintable through the painted/ round-trip.
# ============================================================================

def build_portal_arch():
    """THE ARCH: an upright machined ring on a mounting yoke. The aperture is a
    real OPENING ringed by the purple neon channel; a near-black void slab sits
    a hand-depth behind the front plane (the dormant read — the runtime lens
    replaces it when the pair is live). Clean silhouettes; segment seams,
    bolts, and wear belong to the pixel atlas, not the mesh."""
    b = Builder()
    zc = 1.72                                       # aperture centre height
    # the ring: outer housing (paintlib annulus lies upright, facing -Y —
    # built for exactly this); 20 sides reads machined at pixel res
    b.annulus((0, 0, zc), 1.52, 1.14, 0.34, "portal_iron", sides=20)
    # the neon channel lining the aperture
    b.annulus((0, 0.02, zc), 1.14, 1.02, 0.24, "portal_neon", sides=20)
    # the dormant void: a thin near-solid slab recessed behind the front plane
    b.annulus((0, 0.12, zc), 1.02, 0.008, 0.03, "portal_void", sides=20)
    # keystone cap at the apex — the one block that says "assembled, not cast"
    b.box((0, 0, zc + 1.66), (0.52, 0.42, 0.30), "portal_iron_lt")
    # mounting yoke: two pylons gripping the ring's lower quarters
    for sx in (-1.0, 1.0):
        b.box((sx * 1.28, 0, 0.62), (0.34, 0.46, 1.24), "portal_iron", skip=("bottom",))
        b.box((sx * 1.28, 0, 1.32), (0.40, 0.52, 0.16), "portal_dark")   # clamp collar
    # base skid: one low slab; the chamfer look is painted, not modeled
    b.box((0, 0, 0.10), (3.10, 0.86, 0.20), "portal_iron", skip=("bottom",))
    b.box((0, 0, 0.235), (2.70, 0.70, 0.07), "portal_dark")
    # conduit run: the power feed from the right pylon down the base rear —
    # a modeled square duct, never a chain of spheres
    b.box((1.28, 0.28, 0.42), (0.16, 0.14, 0.64), "portal_rust")
    b.box((0.55, 0.28, 0.155), (1.62, 0.14, 0.13), "portal_rust")
    return b.finish("PortalArch")


def build_portal_pad_ring():
    """THE PAD RING: the flat ground fixture the queue forms on — stepped
    concentric courses (outer iron ring, RECESSED purple neon ring, dark inner
    ring, raised centre boss). Low (0.27 at the boss), wide (2.5); the trefoil
    and bolt detail are texture work."""
    b = Builder()
    b.ngon_prism((0, 0), 1.25, 1.27, 0.10, "portal_iron", sides=24, z0=0.0)      # outer course
    b.ngon_prism((0, 0), 0.97, 0.97, 0.08, "portal_neon", sides=24, z0=0.0)      # recessed neon ring
    b.ngon_prism((0, 0), 0.80, 0.80, 0.12, "portal_dark", sides=24, z0=0.0)      # inner ring
    b.ngon_prism((0, 0), 0.34, 0.38, 0.15, "portal_iron", sides=12, z0=0.12)     # centre boss
    return b.finish("PortalPadRing")


# ============================================================================
# WALKWAY DECK GRATE — the district's 2 m tile-module floor inset. Plumbing
# Power Project walkways run over open water, so the drop has to read.
# ============================================================================

def build_deck_grate():
    """The Channels' standard 2 m grate tile. STRUCTURE is modeled — the bolted
    frame, the corner joint plates, the lift-handle brackets, and the near-black
    pit plate that sells the drop. The woven bar field is DRAWN: one card wearing
    a transparent pixel-art texture, because a modeled lattice costs hundreds of
    triangles to alias into mush at gameplay distance, while the drawn weave stays
    crisp and stays editable. Base z=0; the tread line sits at 0.12."""
    b = Builder()
    for sy in (-0.94, 0.94):                                     # frame bars along X
        b.box((0, sy, 0.06), (2.0, 0.12, 0.12), "portal_iron")
    for sx in (-0.94, 0.94):                                     # frame bars along Y
        b.box((sx, 0, 0.06), (0.12, 1.76, 0.12), "portal_iron")
    for (sx, sy) in ((-0.925, -0.925), (0.925, -0.925), (-0.925, 0.925), (0.925, 0.925)):
        b.box((sx, sy, 0.13), (0.15, 0.15, 0.02), "portal_iron_lt")   # corner joint plate
    b.box((0, 0, 0.01), (1.82, 1.82, 0.02), "grate_pit")              # the pit under-plate
    # the weave itself: ONE card, recessed below the tread line like the bars were
    b.card((0, 0, 0.055), (1.84, 1.84), "grate_iron", axis='Z', art=GRATE_ART)
    for sy in (-0.94, 0.94):                                     # lift-handle U-brackets
        for px in (-0.09, 0.09):
            b.box((px, sy, 0.145), (0.035, 0.035, 0.05), "portal_dark")
        b.box((0, sy, 0.1775), (0.215, 0.035, 0.035), "portal_dark")
    return b.finish("DeckGrate")


# ============================================================================
# THE WARNING-LEAVINGS REGISTER — what a damaging route WEARS.
# The route-class law (design-laws.md) requires a damaging route to write its
# danger in the world, not only on a board. This world's "bones" are DEAD FLORA:
# no taxonomy contains skeletons, but flora_taxonomy.md's ambient register gives
# vine skeletons ("flora in rigor: the shape persists, but the life is gone") and
# the GDD's flure dying states give the corpse that still baits siderophores.
# The leavings are the ecology telling the truth — that is why they warn.
# ============================================================================

def build_vine_skeleton():
    """Flora in rigor: a dead rope-vine collapsed in an unmaintained corridor —
    one arm still reaching the way it grew, snapped short mid-air; the rest
    slumped in a slack S on the floor with shed segment stubs nobody cleared.
    Built at the LIVE Climbvine's gauge, because the read is "that species,
    dead": same rope thickness, same periodic knuckles, so the silhouette is
    recognised before the palette says it died. Nothing emits. Ground piece."""
    # ONE connected body — chains weld at shared points (the skin grammar).
    slump = [(0.62, -0.26, 0.070, 0.070), (0.34, -0.40, 0.062, 0.062),
             (0.04, -0.34, 0.076, 0.076), (-0.26, -0.44, 0.058, 0.058),
             (-0.52, -0.30, 0.066, 0.066)]              # resting ON the floor: z = radius
    reach = [slump[2], (0.16, -0.18, 0.30, 0.052),
             (0.12, -0.02, 0.62, 0.064), (0.04, 0.06, 0.92, 0.046),
             (-0.02, 0.10, 1.16, 0.058)]                 # swollen break at the snap
    chains = [slump, reach]
    chains.append([reach[1], (0.38, -0.12, 0.34, 0.034), (0.50, -0.14, 0.40, 0.018)])
    chains.append([slump[4], (-0.70, -0.16, 0.050, 0.050),
                   (-0.82, -0.04, 0.034, 0.034)])        # snapped continuation, trailing off
    ob = mk.skin_growth("VineSkeleton", chains, decimate=0.3, jitter=0.008, sub_levels=2)
    fiber = mk.flat_mat("cp_vine_fiber", _dim(CS("climbvine_fiber"), 0.68), rough=0.95)
    knuckle = mk.flat_mat("cp_vine_knuckle", _dim(CS("climbvine_fiber"), 0.52), rough=0.95)
    litter = mk.flat_mat("cp_vine_litter", _dim(CS("climbvine_fiber"), 0.42), rough=0.95)
    for m in (fiber, knuckle, litter):
        ob.data.materials.append(m)
    knuckles = [(0.12, -0.02, 0.62, 0.115), (-0.02, 0.10, 1.16, 0.098),
                (0.16, -0.18, 0.30, 0.092), (0.04, -0.34, 0.112, 0.112),
                (0.34, -0.40, 0.088, 0.088), (0.62, -0.26, 0.100, 0.100),
                (-0.26, -0.44, 0.086, 0.086), (-0.70, -0.16, 0.078, 0.078)]
    mk.stud_spheres(ob, [(x, y, z, r, 1, 0.8) for (x, y, z, r) in knuckles])
    grips = []
    for (kx, ky, kz, kr) in knuckles[:4]:                # grip-roots splayed dead
        for d in (-1.0, 1.0):
            grips.append((kx + d * kr * 1.0, ky + 0.03, max(kz - kr * 0.5, 0.03),
                          0.032, 2, 1.0))
    grips.append((0.50, -0.14, 0.036, 0.036, 2, 1.0))    # shed knuckle shells
    grips.append((-0.38, -0.18, 0.030, 0.030, 2, 1.0))
    mk.stud_spheres(ob, grips)
    ob["no_atlas"] = 1
    return ob


def build_dead_flure():
    """The flora-past-saving beat (GDD 8.8 dying states): a flure collapses from
    the core OUTWARD — the stem folds over, the petal collar hangs instead of
    fanning, the sheen grays to dull bronze, the core dries dark and cracked.
    Three petals lie where they dropped; the basal rosette wilts flat. The one
    thing still faintly alive is the ground dust: the contracted root system
    keeps pulsing a weak iron-attractant, so a dead flure still BAITS
    siderophores — which is exactly the warning the piece is placed to carry."""
    stem = [(0.0, 0.0, 0.0, 0.05), (0.03, 0.01, 0.15, 0.024),
            (0.10, 0.02, 0.30, 0.030), (0.20, 0.03, 0.42, 0.017),
            (0.30, 0.04, 0.48, 0.024)]                   # folded over, apex low
    chains = [stem]
    chains.append([stem[1], (-0.09, -0.05, 0.18, 0.011), (-0.13, -0.07, 0.2, 0.006)])
    ob = mk.skin_growth("DeadFlure", chains, decimate=0.22, jitter=0.012, sub_levels=2)
    stem_m = mk.flat_mat("cp_df_stem", _dim(CS("scarpet_green"), 0.55), rough=0.9)
    bronze = mk.flat_mat("cp_df_bronze", _dim(CS("flure_bronze"), 0.62), rough=0.85)
    throat = mk.flat_mat("cp_df_throat", _dim(CS("flure_bronze"), 0.38), rough=0.9)
    core = mk.flat_mat("cp_df_core", _dim(CS("flure_core"), 0.18), rough=0.95)
    rosette = mk.flat_mat("cp_df_rosette", _dim(CS("scarpet_green"), 0.38), rough=0.9)
    dust = mk.flat_mat("cp_df_dust", _dim(CS("flure_bronze"), 0.55),
                       _dim(CS("flure_bronze"), 0.5), 0.3)
    for m in (stem_m, bronze, throat, core, rosette, dust):
        ob.data.materials.append(m)
    bm = mk._bmesh.new()
    bm.from_mesh(ob.data)
    n0 = len(bm.faces)                                   # the throat, hanging mouth-down
    ret = mk._bmesh.ops.create_cone(bm, cap_ends=True, segments=9,
                                    radius1=0.028, radius2=0.10, depth=0.18)
    mtx = (mathutils.Matrix.Translation((0.36, 0.05, 0.30))
           @ mathutils.Matrix.Rotation(2.75, 4, 'Y'))
    mk._bmesh.ops.transform(bm, matrix=mtx, verts=ret["verts"])
    mk.hs_tag(bm, n0, 2)
    for i in range(6):                                   # petals hang around the head
        a = i * math.pi * 2.0 / 6.0 + 0.3
        length = 0.26 if i % 2 == 0 else 0.21
        rc = 0.10
        mk.bev_box_r(bm, (0.36 + rc * math.cos(a) * 0.5, 0.05 + rc * math.sin(a),
                          0.30 - length * 0.35), (0.10, 0.015, length), 1,
                     rot=(2.6, 0.0, a + math.pi / 2.0), bevel=0.007)
    for (px, py, pa) in ((0.52, -0.16, 0.4), (0.20, 0.24, 1.9), (0.58, 0.14, 2.8)):
        mk.bev_box_r(bm, (px, py, 0.012), (0.11, 0.017, 0.24), 1,
                     rot=(1.57, 0.0, pa), bevel=0.006)    # fallen petals, flat
    for i in range(6):                                   # rosette wilted nearly flat
        a = i * math.pi / 3.0 + 0.26
        mk.bev_box_r(bm, (0.16 * math.cos(a), 0.16 * math.sin(a), 0.028),
                     (0.085, 0.013, 0.28), 4,
                     rot=(1.48, 0.0, a + math.pi / 2.0), bevel=0.006)
    bm.to_mesh(ob.data)
    bm.free()
    mk.stud_spheres(ob, [(0.42, 0.05, 0.16, 0.042, 3, 0.7),   # dried core, spilled at the mouth
                         (0.50, 0.07, 0.022, 0.022, 3, 0.7),  # a shed core shard
                         (0.18, 0.10, 0.010, 0.024, 5, 0.35),  # the faint last-pulse dust
                         (-0.14, -0.14, 0.010, 0.02, 5, 0.35),
                         (0.34, -0.20, 0.010, 0.022, 5, 0.35),
                         (0.05, 0.26, 0.010, 0.018, 5, 0.35),
                         (0.56, -0.06, 0.010, 0.02, 5, 0.35)])
    ob["no_atlas"] = 1
    return ob


# ============================================================================
# FEATURE VOCABULARY — the district's own reads (biomes.gd channels theme:
# "valve bank", "flow strip", "open channel trough").
# ============================================================================

def build_valve_bank():
    """A VALVE BANK: one manifold header on two legs, three risers, their
    handwheels staggered where different hands left them; the far riser's wheel
    is GONE — a bare stem the maintenance class never came back for. A low
    water-glow indicator lens ties the bank into the lit flow language the
    trough speaks. Pipe-kit radii and materials, so a bank reads as kin to the
    runs it meters. Base z=0 at the leg feet."""
    bm = mk._bmesh.new()
    M_STEEL, M_RUST, M_DARK, M_GLOW = 0, 1, 2, 3
    for lx in (-0.52, 0.52):                             # the legs
        mk.hs_prism(bm, (lx, 0, 0.29), 0.05, 0.06, 0.58, M_DARK, sides=8, bevel=0.012)
        mk.hs_prism(bm, (lx, 0, 0.02), 0.11, 0.13, 0.04, M_DARK, sides=8, bevel=0.01)
    mk.hs_prism(bm, (0, 0, 0.62), 0.13, 0.13, 1.44, M_STEEL, sides=8,
                bevel=0.02, axis='X')                    # the header manifold
    for fx in (-0.72, 0.72):                             # flanges with their bolt rings
        mk.hs_prism(bm, (fx, 0, 0.62), 0.22, 0.22, 0.06, M_RUST, sides=8,
                    bevel=0.015, axis='X')
        mk.hs_bolts(bm, (fx, 0, 0.62), 0.185, 4, M_DARK, bolt_r=0.024, bolt_h=0.04,
                    axis='X')
    wheels = ((-0.40, 0.36, 0.15), (0.0, 0.30, 0.125), (0.40, 0.33, 0.0))
    for (rx, rise, wheel_r) in wheels:
        mk.hs_prism(bm, (rx, 0, 0.62 + rise * 0.5 + 0.1), 0.055, 0.055, rise, M_STEEL,
                    sides=6, bevel=0.01)                 # riser stem
        mk.hs_prism(bm, (rx, 0, 0.72 + rise), 0.035, 0.035, 0.07, M_RUST, sides=6,
                    bevel=0.008)                         # the spindle nut
        if wheel_r > 0.0:
            mk.hs_torus(bm, (rx, 0, 0.74 + rise), wheel_r, 0.028, M_RUST,
                        major_segs=10, minor_segs=5, axis='Z')
    mk.hs_prism(bm, (0.18, -0.16, 0.62), 0.075, 0.075, 0.1, M_DARK, sides=8,
                bevel=0.01, axis='Y')                    # gauge housing, face out
    mk.hs_prism(bm, (0.18, -0.225, 0.62), 0.05, 0.05, 0.03, M_GLOW, sides=8,
                bevel=0.006, axis='Y')                   # the lit indicator lens
    mk.bev_box(bm, (-0.45, 0.0, 0.008), (0.34, 0.26, 0.016), M_RUST, bevel=0.004)
    return mk.hs_finish("ValveBank", bm, [                # the drip stain under the flange
        mk.flat_mat("cp_vb_steel", CH("pipe_joint"), rough=0.55),
        mk.flat_mat("cp_vb_rust", CH("rust"), rough=0.85),
        mk.flat_mat("cp_vb_dark", CH("iron_dark"), rough=0.6),
        mk.flat_mat("cp_vb_glow", _dim(CH("water"), 0.7), CH("water"), 0.9),
    ])





# The nine registered parts the six Builder-based props need. Seventeen of the
# twenty-three read the palette straight through CH()/_dim and need none of this;
# only DeckPlanks, DoorIronband, GateSign, BrokenPier and the two plank variants
# pass part NAMES, and a missing part is a KeyError at build time rather than a
# quiet fallback.
pl.register_parts({
    "arch_iron":      {"rgb": CH("iron")},
    "arch_dark":      {"rgb": CH("iron_dark")},
    "deck_wood":      {"rgb": CH("wood"), "family": "wood"},
    "deck_wood_worn": {"rgb": _dim(CH("wood"), 0.78), "family": "wood"},
    "grate_iron":     {"rgb": _dim(CH("iron_dark"), 0.9)},
    "door_wood":      {"rgb": _dim(CH("wood"), 0.9), "family": "wood"},
    "door_iron":      {"rgb": CH("iron_dark")},
    "sign_red":       {"rgb": _dim(CH("lamp_red"), 0.4), "emit": _dim(CH("lamp_red"), 0.95)},
    "water_glow":     {"rgb": _dim(CH("water"), 0.75), "emit": CH("water")},
}, emit_strength={"sign_red": 0.6, "water_glow": 2.0})

# The detail painters those props tag faces with.
D_WOOD = pl.register_detail("ch_wood_grain", paint_wood_grain)
D_PANEL = pl.register_detail("ch_metal_panel", paint_metal_panel)

# ---- the wash/ascent props ---------------------------------------------------------------
# These are CHANNELS props — the reservoir drum, the pipe kit, the water bands, the
# sluice decks — that were being built by the archetype chain because that is where
# they were first written. They belong to the district, so the district builds them.
#
# The file is EXEC-INCLUDED, not copied: one definition of every piece, and moving
# ownership does not fork the source. `CF` (the fauna palette row) is defined inside
# it for the Sapscrap body.
_AP = os.path.join(ROOT, "blender", "archetypes", "ascent_pieces.py")
exec(compile(open(_AP, encoding="utf-8").read(), _AP, "exec"))

ASCENT_BUILDERS = [
    build_water_surface,
    build_channel_collar,
    build_drum_shell,
    build_pipe_straight,
    build_pipe_elbow,
    build_pipe_tee,
    build_pipe_cross,
    build_pipe_end,
    build_pipe_straight_banded,
    build_pipe_straight_valve,
    build_sapscrap_body,
    build_drum_crown,
    build_pipe_bracket,
    build_cage_lamp,
    build_water_channel_b,
    build_water_channel_c,
    build_water_band_deck,
    build_water_band_trough,
    build_water_band_deck_b,
    build_water_band_deck_c,
    build_water_band_trough_b,
    build_water_band_trough_c,
    build_deck_sluice,
    build_deck_sluice_b,
    build_deck_sluice_c,
]


# ---- the rest of the district's dressing --------------------------------------------------
# ORDER IS THE TRAP. build_porthole / red_bar_lamp / portal_console / ball_joint_pipe
# are overridden in hardsurface.py, and vein_trunk / wall_tracery / biolume_cluster /
# water_channel / reservoir_platform again in concept_pass1.py. Exec'ing a subset, or
# these out of order, silently ships an earlier shelved version of a piece that looks
# almost right — which is exactly how the portal family wore a rejected read for weeks.
for _mod in ("organic_v2.py", "hardsurface.py", "concept_pass1.py", "scaffold.py"):
    _path = os.path.join(ROOT, "blender", "archetypes", _mod)
    exec(compile(open(_path, encoding="utf-8").read(), _path, "exec"))

def build_deck_planks():
    """Concept plates 3/4: the walkway deck SECTION — a 2 x 2 m field of seven
    planks running along X with open ~1.5 cm gaps, alternating fresh and worn
    boards, two sitting a centimetre proud (foot-traffic unevenness), and two
    thin iron nail strips crossing near the ends. Tileable by placement; base
    z=0, walking surface ~0.09."""
    b = Builder()
    pitch = 0.27 + 0.015                                       # plank width + gap
    y0 = -3 * pitch                                            # centre the 7-board field
    for i in range(7):
        lift = 0.01 if i in (1, 5) else 0.0                    # the proud boards
        part = "deck_wood" if i % 2 == 0 else "deck_wood_worn"
        b.box((0, y0 + i * pitch, 0.04 + lift), (2.0, 0.27, 0.08), part)
    for sx in (-0.82, 0.82):                                   # nail strips near the ends
        b.box((sx, 0, 0.075), (0.07, 1.98, 0.03), "grate_iron")
    b.box((0.45, y0 + 2 * pitch, 0.084), (0.22, 0.14, 0.01), "deck_wood_worn")   # scuff patch
    b.box((-0.55, y0 + 4 * pitch, 0.084), (0.3, 0.16, 0.01), "deck_wood_worn")   # scuff patch
    return b.finish("DeckPlanks")


def build_door_ironband():
    """Plate 3 background door: one of the colour-banded sector doors set into
    the dark perimeter wall (docs/CHANNELS_CONCEPT.md — the wordless sector
    signage), this one strapped in IRON: a heavy 1.6 x 2.6 frame around a
    recessed wood slab, three riveted bands, a stub handle. Faces -Y; base z=0."""
    b = Builder()
    for sx in (-0.71, 0.71):                                            # frame posts
        b.box((sx, 0, 1.21), (0.18, 0.18, 2.42), "door_iron", detail=D_PANEL)
    b.box((0, 0, 2.51), (1.6, 0.18, 0.18), "door_iron", detail=D_PANEL)  # lintel
    b.box((0, 0.02, 1.1), (1.2, 0.1, 2.2), "door_wood", detail=D_WOOD)   # recessed slab
    for bz in (0.45, 1.25, 2.05):                                       # strap bands, proud of the slab
        b.box((0, -0.03, bz), (1.28, 0.08, 0.12), "door_iron")          # ends bite into the posts
        for sx in (-0.45, 0.45):                                        # rivet heads on each band
            b.box((sx, -0.08, bz), (0.07, 0.05, 0.07), "door_iron")
    b.box((0.48, -0.05, 1.05), (0.09, 0.07, 0.14), "door_iron")         # handle seated into the slab
    return b.finish("DoorIronband")


def build_gate_sign():
    """Concept plate 4: the red DOT-MATRIX sign hung over the gate — an iron frame
    around the perforated red readout, the thin cyan neon under-strip beneath it,
    and two mount tabs reaching up to the lintel. Faces -Y (Godot +Z after export);
    back hugs y=0, z spans 0 to ~1.5."""
    b = Builder()
    b.box((0, -0.06, 0.75), (2.3, 0.12, 1.3), "door_iron")                        # sign frame
    b.box((0, -0.13, 0.75), (2.1, 0.05, 1.1), "sign_red", detail=DETAIL_SCREEN)   # dot-matrix face, proud
    b.box((0, -0.12, 0.04), (2.1, 0.05, 0.08), "water_glow")                      # cyan neon under-strip, base at z=0
    for sx in (-0.85, 0.85):                                                      # strip hangers
        b.box((sx, -0.10, 0.09), (0.10, 0.06, 0.10), "arch_dark")
    for sx in (-0.8, 0.8):                                                        # lintel mount tabs
        b.box((sx, -0.05, 1.46), (0.16, 0.10, 0.16), "arch_dark")
    for (px, pz) in ((-1.1, 0.15), (1.1, 0.15), (-1.1, 1.35), (1.1, 1.35)):
        b.box((px, -0.13, pz), (0.06, 0.05, 0.06), "arch_iron")                   # corner bolts
    return b.finish("GateSign")


def build_broken_pier():
    """Concept plate 2 (prop audit #15): the BROKEN-PLANK pier edge over the pit —
    deck planks flush at the walkway side but SNAPPED at staggered lengths so the
    far ends read jagged over the drop, splinter stubs still hanging past the
    breaks, one plank sagged off the last intact grate beam. Pit side is +X;
    base z=0 at the support beam."""
    b = Builder()
    b.box((-0.78, 0, 0.07), (0.18, 1.5, 0.14), "grate_iron")         # last intact support beam
    planks = [  # (y, length, sag) — all flush at x=-0.9; snapped ends stagger toward the pit
        (-0.54, 1.8, 0.0), (-0.27, 1.35, 0.0), (0.0, 1.6, 0.0),
        (0.27, 1.1, 0.04), (0.54, 1.5, 0.0),
    ]
    for i, (py, ln, sag) in enumerate(planks):
        part = "deck_wood" if i % 2 == 0 else "deck_wood_worn"       # alternating wear
        b.box((-0.9 + ln * 0.5, py, 0.18 - sag), (ln, 0.26, 0.08), part)
    b.box((0.58, -0.27, 0.17), (0.18, 0.1, 0.06), "deck_wood_worn")  # splinters float just
    b.box((0.34, 0.27, 0.12), (0.18, 0.1, 0.06), "deck_wood_worn")   # past the short breaks
    return b.finish("BrokenPier")

DRESSING_BUILDERS = [
    build_scaffold_truss,
    build_scaffold_leg,
    build_railing_run,
    build_pipe_rack,
    build_wall_panel_tile,
    build_deck_planks_b,
    build_deck_planks_c,
    build_deck_grate_b,
    build_wall_panel_tile_b,
    build_wall_panel_tile_c,
    build_vein_trunk,
    build_wall_tracery,
    build_biolume_cluster,
    build_water_channel,
    build_reservoir_platform,
    build_porthole,
    build_red_bar_lamp,
    build_portal_console,
    build_ball_joint_pipe,
    build_deck_planks,
    build_door_ironband,
    build_gate_sign,
    build_broken_pier,
]

# ---- build + texture + labeled sheet ------------------------------------------------------
# The sheet shows the WHOLE district: the pieces authored above, then every piece the
# shared module owns (the ones the wash-relay helix places).
BUILDERS = [
    build_portal_arch, build_portal_pad_ring, build_deck_grate,
    build_vine_skeleton, build_dead_flure, build_valve_bank,
] + ASCENT_BUILDERS + DRESSING_BUILDERS + list(channels_parts.BUILDERS)
PX_OVERRIDES = dict(channels_parts.PX_OVERRIDES)
PX_OVERRIDES.update({"GateSign": 48.0, "RedBarLamp": 64.0,
                     "PortalConsole": 48.0, "BallJointPipe": 48.0,
                     "Porthole": 48.0, "BiolumeCluster": 64.0})

PIECES = {}
COLS = 4
SPACING = 4.2
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
sun.color = (0.9, 0.92, 1.0)
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (0.9, 0.25, 0.5)
scene.collection.objects.link(so)
fill = bpy.data.lights.new("Fill", 'SUN')
fill.energy = 0.7
fill.color = (0.7, 0.75, 0.9)
fo = bpy.data.objects.new("Fill", fill)
fo.rotation_euler = (1.2, -0.4, 2.6)
scene.collection.objects.link(fo)
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.11, 0.13, 1)
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = 32
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

# ---- the saved .blend IS the inspectable asset sheet (the director opens this) ------------
for name, ob in PIECES.items():
    curve = bpy.data.curves.new("LabelC_" + name, type='FONT')
    curve.body = name
    curve.size = 0.3
    curve.align_x = 'CENTER'
    label = bpy.data.objects.new("Label_" + name, curve)
    label.location = (ob.location.x, ob.location.y - 1.9, 0.02)
    label.rotation_euler = (0.35, 0.0, 0.0)          # tilted up toward the sheet camera
    scene.collection.objects.link(label)
cx = (COLS - 1) * SPACING / 2.0
cy = -((len(BUILDERS) - 1) // COLS) * SPACING / 2.0
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
cam.location = (cx, cy - 14.0, 11.0)
cam.rotation_euler = (mathutils.Vector((cx, cy, 0.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
scene.render.filepath = r"C:\tmp\channels_pieces_sheet.png"
try:
    bpy.ops.render.render(write_still=True)
except Exception:
    pass

bpy.ops.file.pack_all()                              # textures travel INSIDE the .blend
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "channels_pieces.blend"))
pl.export_gltf(list(PIECES.values()), GLTF)
print("=== DONE: %d channels pieces -> %s ===" % (len(PIECES), GLTF))
