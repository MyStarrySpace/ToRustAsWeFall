# ARCHETYPE PIECE LIBRARY — visual BODIES for the generation content vocabulary
# (data/generation/content_palette.json): one paintlib piece per STRUCTURES key
# (15) plus the three flora with real generated runtime bindings (capbage,
# scarpet, hushbloom).
#
# THE HONESTY LAW (GeneratedNodeRuntimeRegistry): these are bodies, never verbs.
# A piece carries NO interaction promise — consumers attach a piece where the
# noun's gameplay contract already exists (an authored mechanic, or a content id
# the runtime registry binds). The dormant Portal piece is dark (docs/PORTALS.md:
# a portal only glows when it works, and then only red/purple/blue).
#
# Pipelines (same as build_wash_dressing.py): paintlib Builder pieces, per-piece
# BlockBench atlases (obj-exports/ + painted/ round-trip), shared painters from
# paintlib.painters, palette authority from data/palettes/level_palettes.json
# (channels row baked for v1 — re-emit per district later). Axis law: box/
# tapered_box/ngon_prism are Z-up; annulus/disc are UPRIGHT (axis local Y).
#
# Run:  blender.exe -b --python build_archetype_pieces.py
# Outputs: archetype_pieces.blend, obj-exports/*.obj+png,
#          resources/models/archetypes/archetype_pieces.gltf (committed),
#          C:/tmp/archetype_pieces_sheet.png (eyeball contact sheet).
import bpy, math, mathutils, sys, importlib, os, json, functools

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path: sys.path.insert(0, BL)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder, DETAIL_SCREEN
from paintlib.painters import (paint_wood_grain, paint_crate_face, paint_metal_panel,
                               paint_barrel, paint_truss)

SRC = os.path.join(BL, "archetypes")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
GLTF = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "archetypes",
                    "archetype_pieces.gltf")
os.makedirs(OBJX, exist_ok=True)
os.makedirs(PAINTED, exist_ok=True)
os.makedirs(os.path.dirname(GLTF), exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

# ---- palette authority ------------------------------------------------------------------
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
def CS(role): return C("species", role)   # canonical flora colors, district-independent
def _dim(c, f): return tuple(v * f for v in c)

pl.register_parts({
    "arch_iron":    {"rgb": CH("iron")},
    "arch_dark":    {"rgb": CH("iron_dark")},
    "arch_rust":    {"rgb": CH("rust")},
    "arch_pipe":    {"rgb": CH("pipe")},
    "arch_wood":    {"rgb": CH("wood"), "family": "wood"},
    "arch_ground":  {"rgb": CH("ground"), "family": "speckled"},
    "arch_moss":    {"rgb": CH("moss"), "emit": CH("flora")},
    "arch_lamp":    {"rgb": CH("lamp"), "emit": CG("warning_amber")},
    "bed_cloth":    {"rgb": _dim(CH("lamp"), 0.7)},
    "membrane_pane": {"rgb": _dim(CH("water_deep"), 1.15), "emit": CH("water_deep")},
    # CANON flora colors (flora_taxonomy.md): Hushbloom is pale lavender/white and
    # NODDING; healthy Scarpet is faint greenish-brown with rust scar patches (the
    # two-tone carpet); Capbage seals over a DARK hollow with faint seam glow.
    "capbage_leaf": {"rgb": _dim(CH("moss"), 0.9)},
    "capbage_seam": {"rgb": _dim(CH("flora"), 0.4), "emit": _dim(CH("flora"), 0.8)},
    "capbage_cavity": {"rgb": _dim(CH("ground"), 0.5)},
    "scarpet_green": {"rgb": CS("scarpet_green"), "family": "speckled"},
    "scarpet_rust": {"rgb": _dim(CH("rust"), 0.8), "family": "speckled"},
    "root_bark":    {"rgb": CS("root_bark")},
    "root_worn":    {"rgb": CS("root_worn")},
    "hushbloom_stem": {"rgb": CS("hushbloom_stem")},
    "hushbloom_bloom": {"rgb": CS("hushbloom_bloom"), "emit": CS("hushbloom_bloom")},
    # the seven remaining species (canon: flora_taxonomy.md + flora_image_prompts.md)
    "flure_bronze":  {"rgb": CS("flure_bronze")},
    "flure_core":    {"rgb": _dim(CS("flure_core"), 0.7), "emit": CS("flure_core")},
    "seefern_leaf":  {"rgb": CS("seefern_leaf")},
    # The frond CARD: its blade, rachis and eye-marks are drawn by the card
    # painter, so the part only supplies the base colour it builds from.
    "seefern_blade": {"rgb": CS("seefern_leaf")},
    # Card parts: the painter draws the form, so the part is only the base colour
    # it builds from. Scarpet's mat and its pillow tufts, Hushbloom's compound leaf.
    "scarpet_mat":   {"rgb": CS("scarpet_blade")},
    "scarpet_moss":  {"rgb": CS("scarpet_blade")},
    "hushbloom_leaf": {"rgb": _dim(CS("hushbloom_bloom"), 0.62)},
    "hushbloom_soil": {"rgb": _dim(CH("ground"), 0.7), "family": "speckled"},
    "hushbloom_sprig": {"rgb": _dim(CS("scarpet_blade"), 0.85)},
    # The pad the fern stands on: damp growth, not a light source — the fern's
    # glow belongs to the vasculature drawn on its blades.
    "seefern_pad":   {"rgb": _dim(CH("moss"), 0.8)},
    "seefern_vein":  {"rgb": _dim(CS("seefern_vein"), 0.5), "emit": CS("seefern_vein")},
    "climbvine_fiber": {"rgb": CS("climbvine_fiber")},
    "climbvine_node": {"rgb": CS("climbvine_node")},
    "gasafoetida_stalk": {"rgb": CS("gasafoetida_stalk")},
    "gasafoetida_pod": {"rgb": CS("gasafoetida_pod"), "emit": _dim(CS("gasafoetida_pod"), 0.6)},
    "fmn_blue":      {"rgb": CS("forget_me_not_blue"), "emit": _dim(CS("forget_me_not_blue"), 0.5)},
    "res_root":      {"rgb": CS("resolution_root_pale")},
    # Channels organic-overgrowth + sheet build-out parts (docs/CHANNELS_CONCEPT.md
    # prop audit). EVERY color routes through the palette authority
    # (data/palettes/level_palettes.json) — never a hard-coded rgb (the palette law).
    "vein_bark":     {"rgb": CH("vein_bark")},
    "vein_ridge":    {"rgb": CH("vein_ridge")},
    "biolume_stem":  {"rgb": CH("biolume_stem")},
    "biolume_blue":  {"rgb": _dim(CH("biolume_blue"), 0.62), "emit": CH("biolume_blue")},
    "biolume_violet": {"rgb": _dim(CH("biolume_violet"), 0.62), "emit": CH("biolume_violet")},
    "porthole_frame": {"rgb": _dim(CH("rust"), 0.9)},
    "porthole_water": {"rgb": _dim(CH("porthole_glass"), 0.85), "emit": CH("porthole_glass")},
    # Sheet build-out parts (concept plates → docs/CHANNELS_CONCEPT.md prop audit).
    # Portal colours obey the portal law: RED/PURPLE/BLUE only, gold = Curecumin item.
    "deck_wood":     {"rgb": CH("wood"), "family": "wood"},
    "deck_wood_worn": {"rgb": _dim(CH("wood"), 0.78), "family": "wood"},
    "grate_iron":    {"rgb": _dim(CH("iron_dark"), 0.9)},
    "door_wood":     {"rgb": _dim(CH("wood"), 0.9), "family": "wood"},
    "door_iron":     {"rgb": CH("iron_dark")},
    "lamp_red":      {"rgb": _dim(CH("lamp_red"), 0.45), "emit": CH("lamp_red")},
    "sign_red":      {"rgb": _dim(CH("lamp_red"), 0.4), "emit": _dim(CH("lamp_red"), 0.95)},
    "portal_iron":   {"rgb": CH("iron")},
    "portal_greeble": {"rgb": _dim(CH("iron"), 1.25)},
    "portal_neon":   {"rgb": _dim(CG("portal_transit"), 0.6), "emit": CG("portal_transit")},
    "screen_purple": {"rgb": _dim(CG("portal_transit"), 0.45), "emit": _dim(CG("portal_transit"), 0.9)},
    "pipe_joint":    {"rgb": CH("pipe_joint")},
    "water_glow":    {"rgb": _dim(CH("water"), 0.75), "emit": CH("water")},
    "water_foam":    {"rgb": CH("foam"), "emit": _dim(CH("foam"), 0.95)},
}, emit_strength={"arch_moss": 0.25, "arch_lamp": 1.8, "membrane_pane": 0.15,
                  "capbage_seam": 0.5, "hushbloom_bloom": 0.35,
                  "flure_core": 1.2,
                  "seefern_vein": 1.4, "gasafoetida_pod": 0.2, "fmn_blue": 0.3,
                  "biolume_blue": 1.1, "biolume_violet": 1.1, "porthole_water": 1.6,
                  "lamp_red": 1.8, "sign_red": 0.6, "portal_neon": 2.2,
                  "screen_purple": 1.3, "water_glow": 2.0, "water_foam": 1.2})

def _paint_seefern_blade(tile, mask, base, isl, px_per_m):
    """CANON affordance (flora_image_prompts): each leaflet carries an EYE-MARK —
    a darker oval at its center ringed by the brighter vein — stacked along the
    blade. The eye-markings are Seefern's vision-extension signal, readable on
    first sight."""
    ph, pw = tile.shape[:2]
    tile[:, :] = base
    if ph < 10 or pw < 5:
        return
    vein = CS("seefern_vein")
    dark = tuple(v * 0.35 for v in CS("seefern_leaf"))
    cx = pw // 2
    step = max(6, ph // 6)
    for y in range(step // 2 + 1, ph - 2, step):
        for (dy, dx) in ((0, -2), (0, 2), (-1, -1), (-1, 1), (1, -1), (1, 1), (2, 0), (-2, 0)):
            yy, xx = y + dy, cx + dx
            if 0 <= yy < ph and 0 <= xx < pw:
                tile[yy, xx] = vein               # the bright vein ring (rounded diamond)
        tile[y, cx] = dark                        # the eye's dark center

D_SEEFERN = pl.register_detail("seefern_eye", _paint_seefern_blade)
D_WOOD = pl.register_detail("arch_wood_grain", paint_wood_grain)
D_CRATE = pl.register_detail("arch_crate", paint_crate_face)
D_PANEL = pl.register_detail("arch_metal_panel", paint_metal_panel)
D_BARREL = pl.register_detail("arch_barrel", paint_barrel)
D_TRUSS = pl.register_detail("arch_truss", paint_truss)

# ---- the pieces (each ≤ ~1.6m footprint — branch-pad / node-socket scale) ----------------
def build_barrier():
    """Endo's repair boundary: two posts, three membrane slats, the middle one torn."""
    b = Builder()
    for sx in (-0.55, 0.55):
        b.box((sx, 0, 0.65), (0.16, 0.16, 1.3), "arch_dark", detail=D_PANEL)
    b.box((0, 0, 1.05), (1.26, 0.06, 0.18), "arch_rust", detail=D_TRUSS)
    b.box((-0.38, 0, 0.7), (0.5, 0.06, 0.18), "arch_rust", detail=D_TRUSS)   # torn middle
    b.box((0.44, 0, 0.7), (0.38, 0.06, 0.18), "arch_rust", detail=D_TRUSS)
    b.box((0, 0, 0.35), (1.26, 0.06, 0.18), "arch_rust", detail=D_TRUSS)
    return b.finish("Barrier")

def build_carry_gear():
    """Harness rack: posts + rail, hanging straps, a pack leaning at the foot."""
    b = Builder()
    for sx in (-0.5, 0.5):
        b.box((sx, 0, 0.75), (0.12, 0.12, 1.5), "arch_wood", detail=D_WOOD)
    b.box((0, 0, 1.45), (1.2, 0.1, 0.1), "arch_wood", detail=D_WOOD)
    for sx in (-0.3, 0.05, 0.35):
        b.box((sx, 0.02, 1.2), (0.09, 0.1, 0.4), "arch_rust")
    b.box((0.3, 0.22, 0.26), (0.42, 0.28, 0.52), "arch_dark", detail=D_CRATE)
    return b.finish("CarryGear")

def build_class_gate():
    """Tiered clearance gate: frame, inner bars, the tier lamp on the lintel."""
    b = Builder()
    for sx in (-0.7, 0.7):
        b.box((sx, 0, 0.95), (0.2, 0.2, 1.9), "arch_dark", detail=D_PANEL)
    b.box((0, 0, 1.95), (1.7, 0.22, 0.24), "arch_dark", detail=D_PANEL)
    for sx in (-0.35, 0.0, 0.35):
        b.box((sx, 0, 0.92), (0.06, 0.06, 1.8), "arch_iron")
    b.box((0, 0, 2.16), (0.3, 0.18, 0.18), "arch_lamp")
    return b.finish("ClassGate")

def build_forage_cache():
    """The lysate cradle: a low basin with a soft-lit well and side straps."""
    b = Builder()
    b.ngon_prism((0, 0), 0.62, 0.55, 0.38, "arch_dark", sides=8, detail=D_PANEL)
    b.ngon_prism((0, 0), 0.4, 0.4, 0.07, "arch_moss", sides=8, z0=0.32)
    for sx in (-0.6, 0.6):
        b.box((sx, 0, 0.2), (0.08, 0.3, 0.4), "arch_rust", detail=D_TRUSS)
    return b.finish("ForageCache")

def build_hide_slot():
    """A cover pocket that READS: lighter iron shell open toward -Y, dark inner
    void, roof lip, worn threshold — never a featureless black slab."""
    b = Builder()
    b.box((0, 0.32, 0.75), (1.3, 0.24, 1.5), "arch_iron", detail=D_PANEL)
    for sx in (-0.62, 0.62):
        b.box((sx, 0.05, 0.7), (0.22, 0.7, 1.4), "arch_iron", detail=D_PANEL)
    b.tapered_box((0, 0.02, 1.44), (1.46, 0.5), (1.46, 0.86), 0.12, "arch_iron")
    b.box((0, 0.28, 0.7), (1.02, 0.1, 1.3), "arch_dark")          # the pocket's dark void
    b.box((0, -0.28, 0.03), (1.2, 0.5, 0.06), "arch_ground")      # worn threshold
    return b.finish("HideSlot")

def build_junction():
    """Pipe manifold: hub drum, three radial stubs, a top nub."""
    b = Builder()
    b.ngon_prism((0, 0), 0.45, 0.45, 0.9, "arch_pipe", sides=8, detail=D_BARREL)
    for (cx, cy, sx, sy) in ((0.6, 0, 0.6, 0.26), (-0.6, 0, 0.6, 0.26), (0, 0.6, 0.26, 0.6)):
        b.box((cx, cy, 0.45), (sx, sy, 0.26), "arch_pipe")
    b.ngon_prism((0, 0), 0.18, 0.18, 0.2, "arch_rust", sides=8, z0=0.9)
    return b.finish("Junction")

def build_membrane():
    """A stretched tissue pane in an upright ring frame on two feet."""
    b = Builder()
    b.annulus((0, 0, 0.85), 0.75, 0.56, 0.12, "arch_iron", sides=12)
    b.disc((0, 0.01, 0.85), 0.56, "membrane_pane", sides=12)
    for sx in (-0.45, 0.45):
        b.box((sx, 0, 0.12), (0.2, 0.34, 0.24), "arch_iron", detail=D_PANEL)
    return b.finish("Membrane")

def build_pipe():
    """A pipe RUN, not a bench: octagonal-read tube (chamfered top and bottom)
    raised on saddles with a visible gap, collar flanges, a top tap."""
    b = Builder()
    b.box((0, 0, 0.56), (1.6, 0.30, 0.22), "arch_pipe", detail=D_BARREL)
    b.tapered_box((0, 0, 0.715), (1.6, 0.16), (1.6, 0.30), 0.09, "arch_pipe")
    b.tapered_box((0, 0, 0.405), (1.6, 0.30), (1.6, 0.16), 0.09, "arch_pipe")
    for sx in (-0.74, 0.74):
        b.box((sx, 0, 0.56), (0.10, 0.44, 0.44), "arch_rust", detail=D_TRUSS)
    for sx in (-0.4, 0.4):
        b.box((sx, 0, 0.18), (0.16, 0.3, 0.36), "arch_dark", detail=D_PANEL)
    b.ngon_prism((0, 0), 0.09, 0.09, 0.22, "arch_rust", sides=6, z0=0.75)
    return b.finish("Pipe")

def build_portal():
    """A DORMANT portal that still reads PORTAL: pad + a dark standing ring (the
    contract's arch silhouette, unlit). No glow — a dead portal is dark by law;
    the live look belongs to PortalPad + PortalFixtures."""
    b = Builder()
    b.ngon_prism((0, 0), 0.85, 0.85, 0.12, "portal_frame", sides=12)
    b.ngon_prism((0, 0), 0.68, 0.68, 0.08, "portal_surface", sides=12, z0=0.1)
    b.annulus((0, 0, 1.05), 0.62, 0.48, 0.14, "portal_frame", sides=12)
    for sx in (-0.58, 0.58):
        b.box((sx, 0, 0.32), (0.16, 0.2, 0.4), "arch_dark")
    return b.finish("Portal")

def build_root_slide():
    """CANON (GDD): a horizontal Mother-Flure ROOT section — living root lobes
    worn smooth on top into a slide lane, never carpentry."""
    b = Builder()
    b.tapered_box((0, 0, 0.26), (1.7, 0.5), (1.7, 0.72), 0.52, "root_bark")
    b.tapered_box((0.15, 0.42, 0.18), (1.3, 0.3), (1.3, 0.46), 0.36, "root_bark")
    b.box((0, -0.02, 0.5), (1.6, 0.4, 0.05), "root_worn")
    b.ngon_prism((-0.75, 0.1), 0.16, 0.2, 0.6, "root_bark", sides=6)
    b.ngon_prism((0.8, -0.15), 0.1, 0.14, 0.1, "arch_moss", sides=6)
    return b.finish("RootSlide")

def build_shelter():
    """A rest lean-to that reads REST, not a table: tall back wall, stepped
    skillion roof, a bedroll on the ground under it."""
    b = Builder()
    b.box((0, 0.38, 0.8), (1.7, 0.12, 1.6), "arch_dark", detail=D_PANEL)
    for (px, py) in ((-0.75, -0.3), (0.75, -0.3)):
        b.box((px, py, 0.58), (0.12, 0.12, 1.16), "arch_wood", detail=D_WOOD)
    b.box((0, -0.05, 1.2), (1.8, 0.85, 0.08), "arch_wood", detail=D_WOOD)
    b.box((0, 0.28, 1.44), (1.8, 0.5, 0.08), "arch_wood", detail=D_WOOD)
    b.box((0, -0.15, 0.14), (0.6, 1.0, 0.26), "bed_cloth")
    return b.finish("Shelter")

def build_shortcut_gate():
    """A crawl hatch left ajar: square frame, offset flap, latch nub."""
    b = Builder()
    for sx in (-0.5, 0.5):
        b.box((sx, 0, 0.55), (0.14, 0.2, 1.1), "arch_dark", detail=D_PANEL)
    b.box((0, 0, 1.12), (1.14, 0.2, 0.14), "arch_dark")
    b.box((0, 0, 0.06), (1.14, 0.2, 0.12), "arch_dark")
    b.box((0.14, 0.18, 0.56), (0.78, 0.06, 0.9), "arch_rust", detail=D_PANEL)
    b.box((-0.42, 0.12, 0.6), (0.08, 0.1, 0.08), "arch_iron")
    return b.finish("ShortcutGate")

def build_terminal():
    """A console: pedestal, tilted screen slab, side conduit. Aster's verb lives
    on the consumer's Interactable, never here."""
    b = Builder()
    b.box((0, 0, 0.45), (0.5, 0.4, 0.9), "arch_dark", detail=D_PANEL)
    b.tapered_box((0, -0.05, 1.06), (0.55, 0.3), (0.55, 0.42), 0.32, "arch_dark")
    b.box((0, -0.14, 1.14), (0.44, 0.08, 0.3), "screen", detail=DETAIL_SCREEN)
    b.box((0.32, 0.1, 0.45), (0.08, 0.08, 0.9), "arch_pipe")
    return b.finish("Terminal")

def build_water_control():
    """A valve stand: floor flange, riser, the wheel crossing an upright ring."""
    b = Builder()
    b.ngon_prism((0, 0), 0.3, 0.34, 0.08, "arch_dark", sides=8)
    b.ngon_prism((0, 0), 0.14, 0.14, 1.0, "arch_pipe", sides=8, z0=0.08)
    b.annulus((0, 0, 1.16), 0.3, 0.2, 0.07, "arch_rust", sides=10)
    b.box((0, 0.005, 1.16), (0.44, 0.05, 0.05), "arch_rust")
    b.box((0, 0.005, 1.16), (0.05, 0.05, 0.44), "arch_rust")
    return b.finish("WaterControl")

def build_workbench():
    """A work table: planked top, legs, tool board, vice block."""
    b = Builder()
    b.box((0, 0, 0.84), (1.4, 0.7, 0.08), "arch_wood", detail=D_WOOD)
    for (px, py) in ((-0.6, -0.25), (0.6, -0.25), (-0.6, 0.25), (0.6, 0.25)):
        b.box((px, py, 0.4), (0.1, 0.1, 0.8), "arch_wood")
    b.box((0, 0.32, 1.35), (1.4, 0.06, 0.85), "arch_dark", detail=D_CRATE)
    for sx in (-0.45, -0.1, 0.3):
        b.box((sx, 0.27, 1.4), (0.08, 0.06, 0.22), "arch_iron")
    b.box((-0.5, -0.15, 0.98), (0.2, 0.24, 0.2), "arch_iron", detail=D_PANEL)
    return b.finish("Workbench")

def build_capbage():
    """CANON (flora_taxonomy Capbage entry): a closet-scale head of overlapping
    waxy leaf tiers around a HOLLOW — the apex is a dark open cavity, and the
    luminescence is a faint seam line between tiers, never a glowing core."""
    b = Builder()
    b.ngon_prism((0, 0), 0.22, 0.28, 0.16, "capbage_leaf", sides=8)            # short thick stem
    b.ngon_prism((0, 0), 0.64, 0.5, 0.5, "capbage_leaf", sides=8, z0=0.14)     # lower tier flares
    b.ngon_prism((0, 0), 0.66, 0.66, 0.05, "capbage_seam", sides=8, z0=0.62)   # seam glow line
    b.ngon_prism((0, 0), 0.42, 0.64, 0.5, "capbage_leaf", sides=8, z0=0.66)    # upper tier closes
    b.ngon_prism((0, 0), 0.34, 0.4, 0.16, "capbage_leaf", sides=8, z0=1.14)    # apex lip
    b.ngon_prism((0, 0), 0.28, 0.28, 0.03, "capbage_cavity", sides=8, z0=1.13) # the dark hollow
    return b.finish("Capbage")

def build_scarpet():
    """CANON: low spreading carpet, faint greenish-brown when healthy, with rust
    scar patches — the two-tone read (CONCEAL_MEDIUM)."""
    b = Builder()
    b.box((0, 0, 0.025), (1.1, 0.9, 0.05), "scarpet_green")
    b.box((0.35, 0.3, 0.045), (0.7, 0.6, 0.04), "scarpet_rust")
    b.box((-0.32, -0.24, 0.04), (0.5, 0.4, 0.035), "scarpet_rust")
    return b.finish("Scarpet")

def build_hushbloom():
    """CANON: a small NODDING flower on a slender stem — petals folded inward
    around the core, pale lavender/white, the glow a whisper (teal belongs to
    Seefern, the trumpet silhouette to Flure)."""
    b = Builder()
    b.ngon_prism((0, 0), 0.03, 0.05, 0.62, "hushbloom_stem", sides=5)
    b.tapered_box((0.08, 0, 0.665), (0.14, 0.08), (0.05, 0.05), 0.09, "hushbloom_stem")
    b.tapered_box((0.16, 0, 0.52), (0.3, 0.3), (0.12, 0.12), 0.24, "hushbloom_bloom")
    for (px, py) in ((-0.18, 0.05), (0.14, -0.14), (0.05, 0.18)):
        b.box((px, py, 0.05), (0.26, 0.12, 0.05), "hushbloom_stem")
    return b.finish("Hushbloom")

def build_flure():
    """CANON (Flure dedicated entry): waist-high, RADIAL iron-bronze petals with
    metallic sheen around a central core of iron-attractant sensory filaments."""
    b = Builder()
    b.ngon_prism((0, 0), 0.05, 0.09, 0.45, "climbvine_fiber", sides=6)          # stem
    b.ngon_prism((0, 0), 0.52, 0.16, 0.14, "flure_bronze", sides=10, z0=0.42)   # petal collar flares
    b.ngon_prism((0, 0), 0.4, 0.5, 0.08, "flure_bronze", sides=10, z0=0.34)     # under-petal droop
    for (px, py) in ((0.42, 0), (-0.42, 0), (0, 0.42), (0, -0.42)):
        b.tapered_box((px, py, 0.55), (0.3, 0.16), (0.16, 0.2), 0.06, "flure_bronze")
    b.ngon_prism((0, 0), 0.13, 0.16, 0.2, "flure_core", sides=8, z0=0.5)        # filament core
    for (px, py) in ((0.07, 0.05), (-0.06, 0.08), (0.02, -0.09)):
        b.box((px, py, 0.74), (0.03, 0.03, 0.1), "flure_core")                  # filament tips
    return b.finish("Flure")

def build_seefern():
    """CANON: fern fronds as VASCULATURE-AS-LANTERN — dark blades carrying bright
    teal glowing veins (the species that owns teal)."""
    b = Builder()
    for (px, py, h, w) in ((-0.22, 0.05, 0.95, 0.26), (0.1, -0.1, 1.15, 0.3), (0.3, 0.15, 0.8, 0.22)):
        b.tapered_box((px, py, h / 2.0), (0.05, 0.04), (w, 0.06), h, "seefern_leaf",
                      detail=D_SEEFERN)
        b.box((px, py - 0.035, h / 2.0), (0.05, 0.015, h * 0.86), "seefern_vein")
    b.ngon_prism((0, 0), 0.3, 0.34, 0.08, "arch_moss", sides=8)                 # rooted pad
    return b.finish("Seefern")

def build_climbvine():
    """CANON: a rope-like vine with dark adventitious-root GRIP NODES, growing
    across an INCLINED surface (Climbvine only grows on slopes)."""
    b = Builder()
    b.tapered_box((0, 0.1, 0.5), (1.5, 0.2), (1.5, 1.1), 1.0, "arch_ground")    # the incline
    for i in range(5):                                                          # rope climbs the NEAR slope
        z = 0.12 + i * 0.2
        y = -0.5 + i * 0.19
        b.box((0.06 * (1 if i % 2 else -1), y, z), (0.14, 0.3, 0.1), "climbvine_fiber")
        if i % 2 == 0:
            b.box((0.06, y - 0.1, z + 0.04), (0.24, 0.14, 0.12), "climbvine_node")  # grip-root cluster
    return b.finish("Climbvine")

def build_gasafoetida():
    """CANON: the affordance is HANGING GAS-PODS — arched stalks each carrying a
    drop-shaped pod (serotinous cluster; faint queasy sheen, no bright glow)."""
    b = Builder()
    b.ngon_prism((0, 0), 0.18, 0.24, 0.14, "gasafoetida_stalk", sides=7)        # base clump
    for (px, py, h) in ((-0.2, 0.05, 0.85), (0.12, -0.12, 1.0), (0.25, 0.18, 0.7)):
        b.ngon_prism((px, py), 0.035, 0.055, h, "gasafoetida_stalk", sides=5)
        b.box((px + 0.12, py, h), (0.28, 0.05, 0.05), "gasafoetida_stalk")      # arm arches out
        b.tapered_box((px + 0.24, py, h - 0.17), (0.1, 0.1), (0.2, 0.2), 0.26,
                      "gasafoetida_pod")                                        # pod hangs, fat-bottomed
    return b.finish("Gasafoetida")

def build_forget_me_nots():
    """CANON: small blue flowers in a low untended cluster — the quiet care
    signal in shelter corners."""
    b = Builder()
    b.ngon_prism((0, 0), 0.26, 0.3, 0.06, "arch_moss", sides=8)                 # leaf pad
    for (px, py, h) in ((-0.12, 0.04, 0.22), (0.02, -0.1, 0.3), (0.12, 0.1, 0.26),
                        (0.2, -0.04, 0.2), (-0.04, 0.14, 0.24)):
        b.ngon_prism((px, py), 0.012, 0.02, h, "hushbloom_stem", sides=4)
        b.box((px, py, h + 0.03), (0.08, 0.08, 0.06), "fmn_blue")               # tiny bloom
    return b.finish("ForgetMeNots")

def build_resolution_roots():
    """CANON (Inflammashunt-only): pale roots rising from floor CRACKS, their
    underground filaments running toward the dormant Chelators."""
    b = Builder()
    b.box((0, 0, 0.03), (1.3, 1.0, 0.06), "arch_ground")                        # cracked floor patch
    b.box((0.1, 0, 0.065), (0.9, 0.05, 0.02), "arch_dark")                      # the crack
    b.box((-0.25, 0.2, 0.065), (0.05, 0.55, 0.02), "arch_dark")
    for (px, py, h) in ((0.25, 0.02, 0.4), (-0.2, 0.24, 0.3), (0.0, -0.05, 0.5)):
        b.tapered_box((px, py, h / 2.0 + 0.06), (0.05, 0.05), (0.14, 0.14), h, "res_root")
    b.box((0.3, -0.35, 0.05), (0.55, 0.06, 0.03), "res_root")                   # surface filament run
    b.box((-0.4, 0.3, 0.05), (0.06, 0.4, 0.03), "res_root")
    return b.finish("ResolutionRoots")

def build_mother_flure():
    """CANON: the Mother Flure is a unique INDIVIDUAL — this body is one root
    SECTION of her system: massive worn root lobes, a bronze petal stump (her
    Flure identity), and the dormant small blue blooms at the root edges."""
    b = Builder()
    b.tapered_box((0, 0, 0.3), (1.7, 0.55), (1.7, 0.85), 0.6, "root_bark")
    b.tapered_box((0.2, 0.5, 0.19), (1.2, 0.3), (1.2, 0.5), 0.38, "root_bark")
    b.ngon_prism((-0.6, -0.1), 0.34, 0.42, 0.5, "root_bark", sides=8, z0=0.55)  # rising stump
    b.ngon_prism((-0.6, -0.1), 0.46, 0.2, 0.12, "flure_bronze", sides=10, z0=1.0)  # petal collar
    b.ngon_prism((-0.6, -0.1), 0.1, 0.13, 0.12, "flure_core", sides=8, z0=1.06)    # dim core
    for (px, py, pz) in ((0.75, 0.25, 0.62), (0.3, -0.28, 0.62), (-0.15, 0.62, 0.4)):
        b.box((px, py, pz), (0.07, 0.07, 0.05), "fmn_blue")                     # dormant blue blooms
    return b.finish("MotherFlure")



def build_porthole():
    """Concept plate 3: the drum porthole ASSEMBLY — an octagonal riveted frame
    standing proud of the plate, a cross-spoke wheel, and the bright teal water
    window. Faces -Y (Godot +Z after export); origin at the ring centre's base."""
    b = Builder()
    b.annulus((0, 0.0, 0.75), 0.62, 0.44, 0.14, "porthole_frame", sides=8)
    # window normal must face -Y WITH the frame front (Godot +Z out of the drum) —
    # flip=True pointed it inward and Godot's backface cull rendered the window dark
    b.disc((0, 0.04, 0.75), 0.45, "porthole_water", sides=8)             # the lit window
    b.box((0, 0.03, 0.75), (0.86, 0.05, 0.07), "porthole_frame")          # spoke: horizontal
    b.box((0, 0.03, 0.75), (0.07, 0.05, 0.86), "porthole_frame")          # spoke: vertical
    b.ngon_prism((0, 0.0), 0.09, 0.09, 0.06, "porthole_frame", sides=8, z0=0.72)  # hub boss
    for i in range(8):                                                    # rivets on the face ring
        a = math.tau * (i + 0.5) / 8.0
        b.box((0.53 * math.cos(a), -0.04, 0.75 + 0.53 * math.sin(a)), (0.06, 0.05, 0.06),
              "porthole_frame")
    return b.finish("Porthole")


def build_deck_grate():
    """Concept plates 3/4 (prop audit row 7): the deck's metal GRATE inset — a
    1.5 m square mesh panel sunk into the plank floor. Riveted-read outer frame,
    a two-layer bar lattice with square holes between, and a dark pit under the
    mesh so the grate reads DEPTH, not a painted tile. Base at z=0, top ~0.1."""
    b = Builder()
    b.box((0, 0, 0.005), (1.3, 1.3, 0.01), "arch_dark")               # dark pit under the mesh
    for sy in (-0.7, 0.7):                                            # frame: long rails
        b.box((0, sy, 0.05), (1.5, 0.1, 0.1), "grate_iron")
    for sx in (-0.7, 0.7):                                            # frame: side rails butt in
        b.box((sx, 0, 0.05), (0.1, 1.3, 0.1), "grate_iron")
    for t in (-0.47, -0.28, -0.09, 0.09, 0.28, 0.47):
        b.box((0, t, 0.07), (1.3, 0.05, 0.05), "arch_iron")          # upper layer runs X
        b.box((t, 0, 0.035), (0.05, 1.3, 0.05), "arch_iron")          # lower layer runs Y
    return b.finish("DeckGrate")



def build_red_bar_lamp():
    """Concept plates 1/4 (prop audit row 13): the horizontal RED bar lamp mounted
    over doorways — a lit lamp_red core bar gripped by two square iron end
    brackets under a wider dark rain hood. Wall prop: back hugs y=0, faces -Y;
    base z=0, ~1.1 wide, ~0.3 tall."""
    b = Builder()
    for sx in (-0.5, 0.5):                                          # end brackets, 0.1 sq
        b.box((sx, -0.05, 0.09), (0.10, 0.10, 0.18), "door_iron")
        b.box((sx, -0.105, 0.09), (0.05, 0.02, 0.05), "arch_iron")  # bolt boss on the face
    b.box((0, -0.05, 0.10), (0.90, 0.08, 0.10), "lamp_red")         # the lit core bar
    b.box((0, -0.065, 0.22), (1.14, 0.13, 0.08), "arch_dark")       # hood, proud of the bar
    b.box((0, -0.125, 0.185), (1.14, 0.025, 0.035), "arch_dark")    # drip lip under the hood nose
    b.ngon_prism((0.35, -0.05), 0.03, 0.03, 0.05, "arch_pipe", sides=6, z0=0.26)  # feed conduit
    return b.finish("RedBarLamp")


def build_portal_console():
    """Plate 2 (prop audit #4, wave 2): the side console beside the Curecumin
    portal — dark pedestal, iron neck, the purple screen proud on the front,
    cable stubs out the back toward the ring. Body only: the override verb
    lives on the consumer's Interactable, never here."""
    b = Builder()
    b.box((0, 0, 0.45), (0.5, 0.4, 0.9), "arch_dark", detail=D_PANEL)   # base pedestal
    b.box((0, -0.05, 1.07), (0.4, 0.3, 0.35), "door_iron")              # neck, front flush with the pedestal
    b.box((0, -0.19, 1.0), (0.46, 0.08, 0.34), "screen_purple",
          detail=DETAIL_SCREEN)                                         # lit screen, proud of -Y
    for sx in (-0.12, 0.12):                                            # cable stubs to the portal
        b.box((sx, 0.22, 0.55), (0.08, 0.12, 0.08), "pipe_joint")
    return b.finish("PortalConsole")

def build_portal_pad_rings():
    """Concept plate 2 (prop audit row 4: "concentric-ring pad"): the ground pad
    in front of the Curecumin portal — nested flat rings stepping UP to a centre
    boss, one thin purple neon ring pooling glow on the deck (portal law: purple
    is a live-portal colour; the dead rings stay plain iron). All rings rise from
    z0=0 — the steps come from height alone, tallest at the centre."""
    b = Builder()
    b.ngon_prism((0, 0), 1.15, 1.15, 0.045, "portal_iron", sides=24)  # outer rim plate
    b.ngon_prism((0, 0), 0.95, 0.95, 0.055, "arch_dark", sides=24)
    b.ngon_prism((0, 0), 0.75, 0.75, 0.065, "portal_neon", sides=24)  # the thin glow ring
    b.ngon_prism((0, 0), 0.55, 0.55, 0.075, "arch_dark", sides=24)
    b.ngon_prism((0, 0), 0.30, 0.30, 0.09, "portal_iron", sides=24)   # centre boss
    return b.finish("PortalPadRings")

def build_ball_joint_pipe():
    """Concept plate 2 (prop audit row 12, portal dressing): the ball-joint pipe
    run — pipes with BLUE-METAL SPHERICAL JOINTS snaking organically. A low run
    zigzagging along a wall: every direction change happens INSIDE a fat ball
    knuckle (the joint swallows both butt ends), never a welded elbow. Back lane
    hugs y≈0; one short riser with a knuckle on top where the run once climbed;
    the whole thing sits just off the floor on two dark feet."""
    b = Builder()
    b.box((-0.91, -0.24, 0.17), (0.58, 0.14, 0.14), "arch_pipe")   # out-lane segment
    b.box((-0.30, -0.08, 0.17), (0.64, 0.14, 0.14), "arch_pipe")   # jogs back to the wall lane
    b.box((0.34, -0.24, 0.17), (0.64, 0.14, 0.14), "arch_pipe")    # snakes out again
    b.box((0.93, -0.08, 0.17), (0.54, 0.14, 0.14), "arch_pipe")    # tail returns to the wall
    for bx in (-0.62, 0.02, 0.66):                                 # the blue ball knuckles sit
        b.ngon_prism((bx, -0.16), 0.14, 0.14, 0.24, "pipe_joint",  # BETWEEN the lanes — one
                     sides=8, z0=0.05)                             # ball covers both pipe ends
    b.box((1.12, -0.08, 0.45), (0.14, 0.14, 0.56), "arch_pipe")    # short riser off the tail
    b.ngon_prism((1.12, -0.08), 0.14, 0.14, 0.24, "pipe_joint", sides=8, z0=0.70)  # top knuckle
    b.box((-0.30, -0.08, 0.17), (0.10, 0.18, 0.18), "arch_rust")   # wall-strap clamp band
    for (fx, fy) in ((-0.85, -0.24), (0.93, -0.08)):               # feet keep the run just
        b.box((fx, fy, 0.05), (0.12, 0.12, 0.10), "arch_dark")     # off the floor
    return b.finish("BallJointPipe")

def build_water_channel():
    """Concept plates 1/4 (prop audit row 9): a WATER CHANNEL deck section — the
    cyan channel-water snaking bright through the grate floor, the water itself
    the light source. The audit's law: irregular organic-edged glow sunk into
    the deck, never a neat rectangular strip. Tileable 2.0 x 1.0 ground piece."""
    b = Builder()
    b.box((0, 0, 0.06), (2.0, 1.0, 0.12), "arch_dark")                # channel bed
    # three overlapping glow slabs at staggered heights: their union wanders
    # left-back to right-front, so the pool EDGE reads organic, never one rectangle
    b.box((-0.35, 0.05, 0.098), (1.15, 0.62, 0.05), "water_glow")
    b.box((0.42, -0.08, 0.102), (1.05, 0.55, 0.05), "water_glow")
    b.box((0.02, 0.10, 0.106), (0.80, 0.70, 0.05), "water_glow")
    for (px, py, s) in ((-0.6, 0.12, 0.07), (0.15, -0.2, 0.05), (0.55, 0.02, 0.06),
                        (-0.15, 0.28, 0.05), (0.8, -0.15, 0.07)):     # foam speckles
        b.box((px, py, 0.13), (s, s * 0.7, 0.024), "water_foam")
    for sy in (-0.46, 0.46):                                          # grate lip bars
        b.box((0, sy, 0.12), (2.0, 0.08, 0.08), "grate_iron")
    return b.finish("WaterChannel")

def build_reservoir_platform():
    """Prop audit #14, plate 1: the small octagonal service platform standing out
    in the drum's water — riveted iron deck with a proud rim ring, a shut access
    hatch, and the feed pipe running off one side toward the drum wall. Base z=0:
    at placement the deck rides just clear of the water line."""
    b = Builder()
    b.ngon_prism((0, 0), 0.80, 0.85, 0.22, "arch_iron", sides=8, detail=D_PANEL)  # the deck
    b.ngon_prism((0, 0), 0.88, 0.88, 0.06, "door_iron", sides=8, z0=0.16)         # rim ring
    b.ngon_prism((0, 0), 0.58, 0.58, 0.015, "arch_rust", sides=8, z0=0.22)        # foot-worn ring
    b.box((-0.18, 0.10, 0.26), (0.44, 0.44, 0.08), "arch_dark", detail=D_PANEL)   # access hatch
    b.box((-0.18, -0.10, 0.315), (0.18, 0.05, 0.05), "arch_iron")                 # hatch handle
    b.box((-0.18, 0.30, 0.30), (0.32, 0.06, 0.05), "arch_dark")                   # hinge spine
    # feed pipe off the +X side, riding just above the water
    b.box((1.55, 0, 0.10), (1.6, 0.16, 0.16), "arch_pipe", detail=D_BARREL)
    b.ngon_prism((0.86, 0), 0.13, 0.13, 0.26, "pipe_joint", sides=8)              # deck-edge joint
    b.ngon_prism((2.28, 0), 0.11, 0.11, 0.22, "pipe_joint", sides=8)              # far collar
    b.ngon_prism((1.55, 0), 0.05, 0.05, 0.10, "arch_rust", sides=6, z0=0.18)      # mid-run tap
    for i in (1, 3, 5, 7):                                                        # rim cleats
        a = math.tau * i / 8.0
        b.box((0.80 * math.cos(a), 0.80 * math.sin(a), 0.235), (0.10, 0.10, 0.05), "door_iron")
    return b.finish("ReservoirPlatform")


# ---- ORGANIC v2 (director's algorithm): branches are authored as MEASUREMENT
# ---- SPHERES (skeleton chains of position+radius, welded at junctions) and the
# ---- faces are generated as ONE CONNECTED surface (skin -> subsurf -> decimate
# ---- to chunky game facets); the portal is real modeling (faceted torus +
# ---- beveled radial greebles). Defined in organic_v2.py; pieces there set
# ---- ob["no_atlas"] and carry flat palette materials.
_V2 = os.path.join(SRC, "organic_v2.py")
exec(compile(open(_V2, encoding="utf-8").read(), _V2, "exec"))

# ---- HARD-SURFACE REWORKS: mechanical props rebuilt as ASSEMBLED machines
# ---- (chamfers, flanges + bolt rings, feet, recessed faces, open bores) —
# ---- hardsurface.py OVERRIDES the painted-primitive builders it redefines.
_HS = os.path.join(SRC, "hardsurface.py")
exec(compile(open(_HS, encoding="utf-8").read(), _HS, "exec"))

# ---- CONCEPT PASS 1: pieces rebuilt AGAINST the director's generated reference
# ---- plates (the reference is the spec; the card render is the acceptance test).
_CP1 = os.path.join(SRC, "concept_pass1.py")
exec(compile(open(_CP1, encoding="utf-8").read(), _CP1, "exec"))

# ---- CONCEPT FLORA: the tendable species rebuilt against their ENT cards.
_CF = os.path.join(SRC, "concept_flora.py")
exec(compile(open(_CF, encoding="utf-8").read(), _CF, "exec"))

# ---- The structural scaffolding and tileable constructions moved to the CHANNELS
# ---- district file with the rest of that district's dressing; it execs the same
# ---- scaffold.py, so there is still one definition of each piece.

# ---- The wash/ascent props moved to the CHANNELS district file: they are that
# ---- district's dressing, and an archetype set has no business holding one
# ---- district's props. blender/channels/build_channels_pieces.py execs the same
# ---- ascent_pieces.py, so there is still exactly one definition of each.

# ---- build + texture + grid layout -------------------------------------------------------
def build_moving_platform():
    """Structures key `moving_platform` (runtime moving_platform_3d.gd: a deck that
    steps between authored transforms on the scheduler and carries whoever stands
    on it). The body reads as a thing that MOVES before it ever moves: the deck
    rides CLEAR of the ground on a visible piston with a rotation collar, and the
    two boarding edges wear hazard cleats while the other two carry a low kerb --
    a lip you can see over, never a wall that hides the deck you are meant to
    stand on. Base z=0 at the piston foot; deck top ~0.9."""
    b = Builder()
    b.ngon_prism((0, 0), 0.34, 0.40, 0.10, "arch_dark", sides=8)                  # splayed foot plate
    b.ngon_prism((0, 0), 0.19, 0.22, 0.56, "arch_pipe", sides=12, z0=0.09,
                 detail=D_BARREL)                                                 # the piston, in the open
    b.ngon_prism((0, 0), 0.26, 0.26, 0.09, "pipe_joint", sides=12, z0=0.63)       # rotation collar
    b.box((0, 0, 0.80), (1.5, 1.5, 0.16), "arch_iron", detail=D_PANEL)            # the deck plate
    b.box((0, 0, 0.885), (1.20, 1.20, 0.02), "arch_rust")                         # foot-worn centre
    for sy in (-0.70, 0.70):                                                      # kerbed edges: a lip,
        b.box((0, sy, 0.95), (1.5, 0.10, 0.14), "door_iron")                      # not a wall
    for sx in (-0.71, 0.71):                                                      # open boarding edges
        b.box((sx, 0, 0.885), (0.10, 1.34, 0.025), "arch_lamp")                   # hazard cleat strip
    for (cx, cy) in ((-0.60, -0.60), (0.60, -0.60), (-0.60, 0.60), (0.60, 0.60)):
        b.box((cx, cy, 0.70), (0.16, 0.16, 0.06), "arch_dark")                    # under-deck corner pads
    return b.finish("MovingPlatform")

def build_rising_water_crossing():
    """Structures key `rising_water_crossing` (spec rising_water_crossing_spec.gd:
    a bowl that floods on a schedule and a road of FLOAT cells that ride the water
    up). The body is one float-road section: a timber deck lashed over four sealed
    buoy drums, tie rings at the corners for the next section along, and the wet
    stain the water leaves round each drum when the bowl is down. The floats sit
    UNDER the deck where they hold it up. Base z=0 at the drum bottoms, so a
    placement sits the piece where the water WILL be."""
    b = Builder()
    for (dx, dy) in ((-0.60, -0.36), (0.60, -0.36), (-0.60, 0.36), (0.60, 0.36)):
        b.ngon_prism((dx, dy), 0.25, 0.27, 0.50, "arch_rust", sides=12,
                     detail=D_BARREL)                                             # the sealed float
        b.ngon_prism((dx, dy), 0.28, 0.28, 0.09, "water_glow", sides=12, z0=0.05) # wet line stain
        b.ngon_prism((dx, dy), 0.26, 0.26, 0.04, "door_iron", sides=12, z0=0.46)  # drum cap
    b.box((0, 0, 0.56), (1.7, 1.15, 0.12), "arch_wood", detail=D_WOOD)            # the deck boards
    for sy in (-0.36, 0.36):                                                      # lashing straps over
        b.box((0, sy, 0.56), (1.74, 0.09, 0.15), "arch_iron")                     # the floats
    b.box((0, 0, 0.625), (1.40, 0.16, 0.02), "arch_rust")                         # worn centre lane
    for (cx, cy) in ((-0.78, -0.48), (0.78, -0.48), (-0.78, 0.48), (0.78, 0.48)):
        b.ngon_prism((cx, cy), 0.07, 0.07, 0.09, "pipe_joint", sides=8, z0=0.62)  # tie rings
    return b.finish("RisingWaterCrossing")


BUILDERS = [
    build_barrier, build_carry_gear, build_class_gate, build_forage_cache,
    build_hide_slot, build_junction, build_membrane, build_pipe, build_portal,
    build_root_slide, build_shelter, build_shortcut_gate, build_terminal,
    build_water_control, build_workbench,
    build_capbage, build_scarpet, build_hushbloom,
    # STATE VARIANTS — the tending loop's whole visible payoff. Each is one more
    # node in the same gltf (`<Piece>__<state>`); the default state keeps the bare
    # name, so nothing that already asks for a piece has to change.
    functools.partial(build_seefern, "wild"),
    functools.partial(build_seefern, "stressed"),
    functools.partial(build_scarpet, "wild"),
    functools.partial(build_scarpet, "senescent"),
    functools.partial(build_hushbloom, "triggered"),
    functools.partial(build_hushbloom, "recharging"),
    build_flure, build_seefern, build_climbvine, build_gasafoetida,
    build_forget_me_nots, build_resolution_roots, build_mother_flure,
     build_deck_grate,      build_portal_ring_ornate,    build_portal_pad_rings,    build_moving_platform, build_rising_water_crossing,
]
PX_OVERRIDES = {"Capbage": 48.0, "Hushbloom": 48.0, "WaterControl": 48.0,
                "ForageCache": 48.0, "Flure": 48.0, "Seefern": 48.0,
                "ForgetMeNots": 64.0, "Gasafoetida": 48.0,
                "BiolumeCluster": 64.0, "Porthole": 48.0,
                "GateSign": 48.0, "RedBarLamp": 64.0, "PortalConsole": 48.0,
                "BallJointPipe": 48.0}
PIECES = {}
COLS = 6
SPACING = 3.8   # wide enough for the 3 m wall/portal pieces
for i, fn in enumerate(BUILDERS):
    ob = fn()
    PIECES[ob.name] = ob
    if not ob.get("no_atlas"):
        pl.texture_object(ob, OBJX, px_per_m=PX_OVERRIDES.get(ob.name, 32.0),
                          painted_dir=PAINTED)
    ob.location = ((i % COLS) * SPACING, -(i // COLS) * SPACING, 0.0)

# ---- contact sheet render ----------------------------------------------------------------
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 2.4; sun.color = (0.9, 0.92, 1.0)
so = bpy.data.objects.new("Sun", sun); so.rotation_euler = (0.9, 0.25, 0.5)
scene.collection.objects.link(so)
fill = bpy.data.lights.new("Fill", 'SUN'); fill.energy = 0.7; fill.color = (0.7, 0.75, 0.9)
fo = bpy.data.objects.new("Fill", fill); fo.rotation_euler = (1.2, -0.4, 2.6)
scene.collection.objects.link(fo)
world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.11, 0.13, 1)
cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 32
cam = bpy.data.objects.new("Cam", cam_d)
scene.collection.objects.link(cam); scene.camera = cam
cx = (COLS - 1) * SPACING / 2.0
cy = -((len(BUILDERS) - 1) // COLS) * SPACING / 2.0
cam.location = (cx, cy - 23.5, 20.5)
cam.rotation_euler = (mathutils.Vector((cx, cy, 0.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
for _eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try: scene.render.engine = _eng; break
    except Exception: pass
scene.render.resolution_x = 1600; scene.render.resolution_y = 900
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = r"C:\tmp\archetype_pieces_sheet.png"
try: bpy.ops.render.render(write_still=True)
except Exception:
    W = bpy.context.window_manager.windows[0]
    A = [a for a in W.screen.areas if a.type == 'VIEW_3D'][0]
    Rg = [r for r in A.regions if r.type == 'WINDOW'][0]
    with bpy.context.temp_override(window=W, area=A, region=Rg):
        bpy.ops.render.render(write_still=True)

# ---- per-piece ASSET CARDS (composed into the labeled asset sheet by
# ---- compose_asset_sheet.py with system-python PIL — Blender's python has none) ----
CARD_DIR = r"C:\tmp\asset_cards"
os.makedirs(CARD_DIR, exist_ok=True)
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
    scene.render.filepath = os.path.join(CARD_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
for ob in PIECES.values():
    ob.hide_render = False

# ---- make the saved .blend THE inspectable asset sheet (the director opens this;
# ---- requires Blender 5.1 — 4.2 cannot read 5.x files and falls back to the cube) ----
for name, ob in PIECES.items():
    curve = bpy.data.curves.new("LabelC_" + name, type='FONT')
    curve.body = name
    curve.size = 0.3
    curve.align_x = 'CENTER'
    label = bpy.data.objects.new("Label_" + name, curve)
    label.location = (ob.location.x, ob.location.y - 1.72, 0.02)
    label.rotation_euler = (0.35, 0.0, 0.0)          # tilted up toward the sheet camera
    scene.collection.objects.link(label)
bpy.ops.file.pack_all()                              # textures travel INSIDE the .blend
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
cam.location = (cx, cy - 23.5, 20.5)                 # re-frame the whole grid (the card
cam.rotation_euler = (mathutils.Vector((cx, cy, 0.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()  # pass left it on the last piece)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "archetype_pieces.blend"))
pl.export_gltf(list(PIECES.values()), GLTF)
print("=== DONE: %d pieces -> %s ===" % (len(PIECES), GLTF))
