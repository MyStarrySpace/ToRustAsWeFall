# Wash-relay concept-plate DRESSING — the Blender-editable source for the wash_relay
# detail pass, built on the SYSTEMIC pipelines:
#
#   LAYOUT   every placement goes through a SURVEY MANIFEST with typed KEEP-OUTS and a
#            loud validate() (the BuildingSurvey discipline: reconcile before meshing —
#            a placement that intrudes on walkable cells / branch spurs / transit zones
#            FAILS THE BUILD with a named violation, never ships silently).
#   PIECES   channels_parts — the district's ONE piece file. It owns the palette
#            authority, the part register, the area painters, the shape datums and
#            every builder; this script only PLACES what it hands back. A piece
#            geometry edit belongs there, never here.
#   UV/TEX   BlockBench treatment via paintlib: per-face islands on pixel boundaries,
#            half-texel inset, edge-bleed, painted starter atlas; obj-exports/ hands
#            every piece to BlockBench, painted/<Piece>_tex.png WINS on rebuild.
#            Detail (rivet courses, portholes, gate panels) lives in PAINTERS, not
#            geometry — flat forms + pixel art, never over-modeled.
#
# Survey + reconciliation are mirrored from scripts/fragments/chunks/wash_relay_dressing.gd
# (the runtime loader) — keep the two in LOCKSTEP; helix params MUST match channels_arc.gd.
# Runtime contracts preserved: Fall_S<i>_<k> / Foam_S<i>_<k> node names; sign text and the
# two beat lights are the loader's.
#
# Run:  blender.exe -b --python build_wash_dressing.py
# Outputs: wash_dressing.blend (editable master), obj-exports/*.obj+png (BlockBench),
#          resources/models/channels/channels_dressing.glb (committed).
import bpy, math, mathutils, sys, importlib, os, random

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
SRC = os.path.join(BL, "channels")
for _p in (BL, SRC):
    if _p not in sys.path: sys.path.insert(0, _p)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar
import paintlib as pl
importlib.reload(pl)
import channels_parts; importlib.reload(channels_parts)
# The district's piece file is the authority for colour, parts and shape: this script
# imports the datums it PLACES against and never re-derives one.
from channels_parts import (CH, CG, _dim, SECTION_TYPES,
                            DRUM_R, DRUM_BOTTOM, DRUM_NECK_Y0, DRUM_NECK_Y1, DRUM_TOP,
                            GATE_W, GATE_H, WALL_FIN_H, WALL_FIN_W, SHAFT_R, LEDGE_LANE_W)

OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
# paintlib export_gltf writes GLTF_SEPARATE — the asset IS the .gltf (+.bin+textures);
# a .glb filepath here would leave a stale .glb the game silently keeps loading.
GLB = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "channels", "channels_dressing.gltf")
os.makedirs(OBJX, exist_ok=True)
os.makedirs(PAINTED, exist_ok=True)
os.makedirs(os.path.dirname(GLB), exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

# ---- ChannelsArc helix params — MUST match scripts/game/world/channels_arc.gd EXACTLY ----
A0 = 0.0; KTHETA = 0.0907; R0 = 11.0; Y0 = 1.0; KCLIMB = 0.1333; LANE_HALF = 4.0
def apos(s, lane=0.0):
    ang = A0 + s * KTHETA; rad = R0 + lane
    return (rad * math.cos(ang), Y0 + s * KCLIMB, rad * math.sin(ang))
def hang(s): return A0 + s * KTHETA
def hyaw(s): return hang(s) + math.pi / 2
def c2b(p): return (p[0], -p[2], p[1])

# ---- THE SURVEY (MUST match wash_relay_dressing.gd) ----
# WHERE things stand. The dimensions they are CUT from (drum radius, gate leaf, fin,
# shaft, ledge width) belong to channels_parts and are imported above.
S_MIN, S_MAX = -1.0, 87.0
RIM_LANE = 4.45; INNER_RIM_LANE = -4.4
WHEEL_FACE_S = 3.0
PIPE_LANES = [2.6, 3.4]; PIPE_DROPS = [-0.85, -1.3]; PIPE_THICK = 0.34; PIPE_STEP = 3.0
FALL_LANE = 4.55; FALL_DROP = 5.2; FALL_SEG = 2.0
WALL_LANE = 12.0; WALL_SKIP_S = (33.0, 47.0)
GATE_LANE = 12.6; GATE_SLUICE_LANE = 14.6
FLURE_LEDGE_S = 62.5; LEDGE_LANE_C = -5.45
FLURE_POS_LANE = -6.4; PAD_LEDGE_S = 1.6; PAD_POS_LANE = -6.2
SECTION_SPANS = [(6, 11), (14, 19), (22, 27), (30, 35), (38, 41), (46, 53), (56, 61),
                 (64, 71), (74, 79)]
SECTIONS = [(t, s0, s1) for t, (s0, s1) in zip(SECTION_TYPES, SECTION_SPANS)]
GAP_MIDS = [12.5, 28.5, 54.5, 62.5, 72.5]          # branch spurs (non-transit gaps)

# ---- RESERVATIONS: the keep-out table every placement is validated against --------------
# (name, s0, s1, lane0, lane1, y0, y1, why) with y = band ABOVE the local deck surface.
# flush/groundcover placements are exempt from the walkable-surface keep-outs only.
KEEPOUTS = [
    ("WALK_DECK",  S_MIN, S_MAX, -4.02, 4.02, 0.08, 3.0, "the main walkable ribbon"),
    ("SLUICE_MOUTH_A", 35.0, 38.0, 3.4, 12.1, -1.0, 4.0, "sluice mouth deck (chunk-owned)"),
    ("SLUICE_MOUTH_B", 42.0, 45.1, 3.4, 12.1, -1.0, 4.0, "sluice mouth deck (chunk-owned)"),
    ("SLUICE_PIPE", 35.0, 45.0, 11.5, 13.6, -1.5, 4.0, "outer pipe visual bulge"),
    ("PRESSURE",   19.6, 26.4, -10.5, -3.4, -1.0, 4.0, "pressure room + portals (chunk-owned)"),
    ("DRAIN",      78.8, 83.7, 3.4, 10.0, -1.0, 4.0, "drain loop (chunk-owned)"),
]
for _m in GAP_MIDS:
    KEEPOUTS.append(("BRANCH_%g" % _m, _m - 1.55, _m + 1.55, 3.4, 10.05, 0.08, 3.0,
                     "branch spur walkable"))
for _bs0, _bs1 in ((61.75, 63.25), (0.75, 2.45)):
    KEEPOUTS.append(("BEAT_%g" % _bs0, _bs0, _bs1, -7.45, -3.4, 0.08, 3.0,
                     "story-beat ledge walkable"))
KEEPOUTS.append(("NECK_GARDEN", 40.0, 45.0, -10.1, -7.2, -1.0, 4.0,
                 "curecumin portal pocket (chunk-owned)"))

_manifest = []
_violations = []

def _claim(name, s, lane, y_base, s_half, height, lane_half, flush=False):
    """Record one placement's survey claim: centred on (s, lane), vertical band
    [y_base, y_base+height] above the local deck. Checked against every keep-out."""
    e = {"name": name, "s0": s - s_half, "s1": s + s_half,
         "lane0": lane - lane_half, "lane1": lane + lane_half,
         "y0": y_base, "y1": y_base + height, "flush": flush}
    _manifest.append(e)
    for (kn, ks0, ks1, kl0, kl1, ky0, ky1, why) in KEEPOUTS:
        if e["flush"] and kn.startswith(("WALK", "BRANCH", "BEAT")):
            continue
        if e["s1"] > ks0 and e["s0"] < ks1 and e["lane1"] > kl0 and e["lane0"] < kl1 \
                and e["y1"] > ky0 and e["y0"] < ky1:
            _violations.append("%s intrudes on %s (%s)" % (name, kn, why))

def _claim_ring(name, r_inner, in_sluice_zone=False):
    """Perimeter pieces (gates/fins/wall) must stand beyond every gameplay reach:
    branch tips r 21, drain ledge r 20.3; the sluice transit bulge reaches r ~24."""
    floor_r = 24.4 if in_sluice_zone else 22.4
    if r_inner < floor_r:
        _violations.append("%s ring radius %.1f under the %.1f floor" % (name, r_inner, floor_r))

def validate_survey():
    if _violations:
        for v in _violations:
            print("  VIOLATION: " + v)
        raise RuntimeError("survey validation failed: %d violations" % len(_violations))
    print("=== SURVEY: %d placements, 0 violations ===" % len(_manifest))

# ---- the district's pieces: built + textured by channels_parts, placed below ------------
channels_parts.register()
PIECES = channels_parts.build_all()
channels_parts.texture_all(PIECES, OBJX, PAINTED)
# The masters are build scaffolding here -- only their COPIES ship. Move them off
# their own names so a placement that wants the clean name gets it instead of
# Blender's `.001` (which is how FlureLedge.001 / PadLedge.001 reached the export).
for _piece_name, _master in PIECES.items():
    _master.name = "%s_master" % _piece_name

# ---- placement (linked instances; every one CLAIMED in the survey manifest) --------------
_placed = []
def _inst(piece, name):
    ob = PIECES[piece].copy()            # linked mesh -> shared UVs + texture
    ob.name = name
    scene.collection.objects.link(ob)
    _placed.append(ob)
    return ob

def place_deck(piece, name, s, lane, y_base, s_half, height, lane_half,
               flush=False, rz_extra=0.0):
    """Deck-frame placement: piece local +X = tangent, +Y = radial-out, base at y_base
    above the local deck surface. Claims its survey band."""
    ob = _inst(piece, name)
    p = apos(s, lane)
    ob.location = c2b((p[0], p[1] + y_base, p[2]))
    ob.rotation_euler = (0.0, 0.0, -hyaw(s) + rz_extra)
    _claim(name, s, lane, y_base, s_half, height, lane_half, flush)
    return ob

def place_world(piece, name, loc_game, rot=(0.0, 0.0, 0.0)):
    ob = _inst(piece, name)
    ob.location = c2b(loc_game)
    ob.rotation_euler = rot
    return ob

def radial_wheel_rz(a):
    """rz that points an annulus-native (local -Y facing) wheel's axis radially at angle a."""
    return math.atan2(-math.cos(a), -math.sin(a))

# The drum stack (world-axis object; its clearances are the ring/beat-ledge laws)
place_world("DrumLower", "Drum_lower", (0.0, DRUM_BOTTOM, 0.0))
place_world("DrumNeck", "Drum_neck", (0.0, DRUM_NECK_Y0, 0.0))
place_world("DrumUpper", "Drum_upper", (0.0, DRUM_NECK_Y1, 0.0))
place_world("WashDrumCrown", "Drum_crown", (0.0, DRUM_TOP, 0.0))
wang = hang(WHEEL_FACE_S)
ww = place_world("ValveWheel", "Drum_wheel_window",
                 (math.cos(wang) * (DRUM_R + 0.06), 1.7, math.sin(wang) * (DRUM_R + 0.06)),
                 (0.0, 0.0, radial_wheel_rz(wang)))
ww.scale = (1.7, 1.7, 1.7)
for vi, (vang, vy) in enumerate([(0.7, 2.2), (3.6, 10.4)]):
    place_world("ValveWheel", "Drum_valve_%d" % vi,
                (math.cos(vang) * (DRUM_R + 0.06), vy, math.sin(vang) * (DRUM_R + 0.06)),
                (0.0, 0.0, radial_wheel_rz(vang)))

# Sector gates + lit sign bands (perimeter ring law; numerals are runtime Label3Ds)
GATE_S_NUDGE = {3: -0.9}   # the plate gate steps down-s so its frame clears the tunnel bulge
for i, (t, x0, x1) in enumerate(SECTIONS):
    mid = (x0 + x1) / 2.0 + GATE_S_NUDGE.get(i, 0.0)
    lane = GATE_SLUICE_LANE if t == "sluice" else GATE_LANE
    in_sz = WALL_SKIP_S[0] < mid < WALL_SKIP_S[1]
    place_deck("GateSlab", "Gate_slab_%d" % i, mid, lane, -1.2,
               GATE_W / 2.0 + 0.5, GATE_H + 1.4, 0.8)
    place_deck("GateSign_" + t, "Gate_sign_%d" % i, mid, lane - 0.32,
               GATE_H * 0.62 - 1.2, GATE_W * 0.36, GATE_H * 0.26, 0.1)
    _claim_ring("Gate_slab_%d" % i, R0 + lane - 0.8, in_sz)

# Pilaster fins + terminals between gates
gate_mids = [(x0 + x1) / 2.0 for (_t, x0, x1) in SECTIONS]
s = 4.0; idx = 0; fi = 0
while s <= 84.0:
    near_gate = any(abs(s - gm) < 3.4 for gm in gate_mids)
    if (s < WALL_SKIP_S[0] or s > WALL_SKIP_S[1]) and not near_gate:
        place_deck("Fin", "Fin_%d" % fi, s, WALL_LANE, -3.5, WALL_FIN_W / 2.0 + 0.6,
                   WALL_FIN_H, 0.5)
        _claim_ring("Fin_%d" % fi, R0 + WALL_LANE - 0.5, False)
        if idx % 3 == 1:
            place_deck("TermPanel", "Fin_term_%d" % fi, s - 0.6, WALL_LANE - 0.4, 1.6,
                       0.45, 0.6, 0.06)
        idx += 1; fi += 1
    s += 7.3

# The enclosing shaft-wall band (static world ring — not helix-following)
for k in range(24):
    ang = math.tau * k / 24.0
    ob = _inst("ShaftPanel", "ShaftBand_%d" % k)
    ob.location = c2b((math.cos(ang) * SHAFT_R, -2.5, math.sin(ang) * SHAFT_R))
    ob.rotation_euler = (0.0, 0.0, -(ang + math.pi / 2))
    _claim_ring("ShaftBand_%d" % k, SHAFT_R - 0.3, False)

# Rim rails — only spans where nothing exits outward, segmented to track the arc
ri = 0
for (rs0, rs1) in ((-0.5, 4.6), (19.8, 21.4), (84.4, 86.6)):
    n = max(1, int(math.ceil((rs1 - rs0) / 1.7)))
    for k in range(n):
        sc = rs0 + (rs1 - rs0) * (k + 0.5) / n
        place_deck("RailSeg", "Rail_%d" % ri, sc, RIM_LANE, 0.0, 0.9, 1.0, 0.06)
        ri += 1

# Rim understructure ribs + drips (skipped where transit owns the rim — the mouths and
# the drain loop; the survey keep-outs are the authority on those spans)
RIB_SKIP = ((34.0, 45.6), (77.6, 84.2))
s = S_MIN + 1.5; k = 0
while s < S_MAX - 1.0:
    if not any(a <= s <= b for (a, b) in RIB_SKIP):
        place_deck("RimRib", "RimRib_%d" % k, s, 4.42, -2.7, 1.0, 2.6, 0.06)
    s += 4.5; k += 1

# (No signage boards — director ruling 2026-07-25: decorative text/placards read as
# noise in play. Sector identity is the gates' color bands, wordless.)

# Branch pier trusses: ribs BELOW deck; furniture past the walkable spur tip at lane
# 10.45 (the survey caught the v1 bug that parked posts ON walkable spur cells at 9.6)
for bi, mid in enumerate(GAP_MIDS):
    for ridx, soff in enumerate((-1.1, 0.0, 1.1)):
        place_deck("TrussRib", "Truss_rib_%d_%d" % (bi, ridx), mid + soff, 6.75, -0.7,
                   0.12, 0.5, 3.25)
    place_deck("TrussPost", "Truss_post_%d" % bi, mid - 1.15, 10.45, 0.0, 0.1, 1.25, 0.1)
    wp = apos(mid + 1.15, 10.45)
    wob = place_world("ValveWheel", "Truss_wheel_%d" % bi, (wp[0], wp[1] + 1.05, wp[2]),
                      (0.0, 0.0, radial_wheel_rz(hang(mid + 1.15))))
    _claim("Truss_wheel_%d" % bi, mid + 1.15, 10.45, 0.7, 0.2, 0.7, 0.2)

# Deck valve wheels at alternating section thresholds (inner rim, off-walkable)
for wi, (t, x0, x1) in enumerate(SECTIONS):
    if wi % 2 == 0 or wi == 1: continue   # wi 1: x1+1.8 lands inside the pressure gap
    place_deck("TrussPost", "DeckValve_post_%d" % wi, x1 + 1.8, INNER_RIM_LANE, 0.0,
               0.1, 1.25, 0.1)
    vp = apos(x1 + 1.8, INNER_RIM_LANE)
    place_world("ValveWheel", "DeckValve_wheel_%d" % wi, (vp[0], vp[1] + 1.05, vp[2]),
                (0.0, 0.0, radial_wheel_rz(hang(x1 + 1.8))))
    _claim("DeckValve_wheel_%d" % wi, x1 + 1.8, INNER_RIM_LANE, 0.7, 0.2, 0.7, 0.2)

# Props: crates/barrels/shrines on the rim strips
rng = random.Random(727)
for gi, gmid in enumerate([12.5, 28.5, 54.5, 72.5]):   # NOT 62.5 — that's the flure ledge
    for k in range(2 + rng.randrange(2)):
        piece = "CrateA" if k % 2 == 0 else "CrateB"
        place_deck(piece, "Crate_%d_%d" % (gi, k), gmid + rng.uniform(-0.9, 0.9),
                   INNER_RIM_LANE - rng.uniform(0.0, 0.2), 0.0, 0.36, 0.72, 0.36)
for k in range(2):
    place_deck("Barrel", "Barrel_%d" % k, 85.3 + k * 0.7, RIM_LANE - 0.1, 0.0, 0.3, 0.7, 0.3)
for si_, shrine_s in enumerate((1.2, 84.6)):
    place_deck("Shrine", "Shrine_%d" % si_, shrine_s, RIM_LANE - 0.05, 0.0, 0.4, 0.6, 0.3)

# Flora tufts on the rims (groundcover: thin walk-through growth)
for fi_, (fs, lane) in enumerate([(10.0, INNER_RIM_LANE), (33.0, INNER_RIM_LANE),
                                  (58.0, INNER_RIM_LANE), (76.0, INNER_RIM_LANE)]):
    place_deck("MossTuft", "Moss_%d" % fi_, fs, lane, 0.0, 0.65, 0.9, 0.65, flush=True)

# The wooden slat patch — FLUSH deck overlay on the 53..56 gap (plate: aged plank arc)
wi = 0
for arc_k in range(2):
    sc = 53.9 + arc_k * 1.3
    for row in range(4):
        place_deck("WoodPlank", "WoodPatch_%d" % wi, sc, -2.7 + row * 1.8, 0.005,
                   0.7, 0.06, 0.87, flush=True)
        wi += 1

# Story-beat ledges (the portal arch is a runtime PortalFixtures child of the pad)
place_deck("FlureLedge", "FlureLedge", FLURE_LEDGE_S, LEDGE_LANE_C, -0.13,
           2.5, 1.2, LEDGE_LANE_W / 2.0, flush=True)
place_deck("PadLedge", "PadLedge", PAD_LEDGE_S, LEDGE_LANE_C, -0.13,
           1.5, 0.6, LEDGE_LANE_W / 2.0, flush=True)

# ---- runtime-contract + organic parts stay plain grammar boxes --------------------------
g = Grammar()
M_PLAIN = {}
def plain_mat(n, c, e=None, es=0.0):
    if n in M_PLAIN: return M_PLAIN[n]
    M = bpy.data.materials.new(n); M.use_nodes = True
    bnode = M.node_tree.nodes.get("Principled BSDF")
    bnode.inputs["Base Color"].default_value = (*c, 1)
    bnode.inputs["Roughness"].default_value = 0.7
    if e:
        bnode.inputs["Emission Color"].default_value = (*e, 1)
        bnode.inputs["Emission Strength"].default_value = es
    M_PLAIN[n] = M
    return M
MP_PIPE = plain_mat("PlainPipe", CH("pipe"))
MP_FALL = plain_mat("PlainFall", CH("water"), CH("water"), 1.2)
MP_FOAM = plain_mat("PlainFoam", CH("foam"), CH("water"), 3.0)
MP_WET = plain_mat("PlainWet", CH("water_deep"), _dim(CH("water"), 0.55), 0.5)
MP_VINE = plain_mat("PlainVine", CH("stem_dead"))
MP_LEAF = plain_mat("PlainLeaf", CH("moss"), CH("flora"), 1.5)
MP_LAMP = plain_mat("PlainLamp", CH("lamp"), CG("warning_amber"), 3.0)
MP_PORTAL = plain_mat("PlainPortal", _dim(CG("portal_route"), 0.7), CG("portal_route"), 4.0)
def hbox(name, s, lane, w_tan, h, w_rad, y_off, m):
    p = apos(s, lane)
    g.pbox(name, p[0], p[1] + y_off, p[2], w_tan, h, w_rad, hyaw(s), m)
def harc(name, s0, s1, lane0, lane1, thick, m, drop=0.0):
    L = abs(s1 - s0); n = max(1, int(round(L / 1.1))); lmid = (lane0 + lane1) / 2.0
    lw = abs(lane1 - lane0) or 0.05
    for k in range(n):
        sa = s0 + (s1 - s0) * k / n; sb = s0 + (s1 - s0) * (k + 1) / n; smid = (sa + sb) / 2.0
        p = apos(smid, lmid); chord = (R0 + lmid) * abs(sb - sa) * KTHETA * 1.12
        g.pbox("%s_%d" % (name, k), p[0], p[1] - drop - thick / 2.0, p[2], chord, thick, lw,
               hyaw(smid), m, "floor")
# under-deck service pipes
for pi_, lane in enumerate(PIPE_LANES):
    drop = PIPE_DROPS[pi_]; s = S_MIN; k = 0
    while s < S_MAX:
        hbox("Underpipe_%d_%d" % (pi_, k), s + PIPE_STEP * 0.5, lane,
             PIPE_STEP * 1.22, PIPE_THICK, PIPE_THICK, drop, MP_PIPE)
        s += PIPE_STEP; k += 1
# the cadence-slaved outfalls (Fall_S / Foam_S names are the RUNTIME CONTRACT) + wet sheen
for i, (_t, x0, x1) in enumerate(SECTIONS):
    n = max(1, int(math.ceil((x1 - x0) / FALL_SEG)))
    for k in range(n):
        sc = x0 + (x1 - x0) * (k + 0.5) / n
        hbox("Fall_S%d_%d" % (i, k), sc, FALL_LANE, (x1 - x0) / n * 1.06, FALL_DROP, 0.14,
             -FALL_DROP * 0.5 - 0.1, MP_FALL)
        hbox("Foam_S%d_%d" % (i, k), sc, FALL_LANE - 0.12, (x1 - x0) / n * 1.02, 0.16, 0.3,
             0.14, MP_FOAM)
    hbox("Fall_S%d_b0" % i, (x0 + x1) / 2.0, FALL_LANE + 0.28, (x1 - x0) * 0.7,
         FALL_DROP + 2.2, 0.16, -(FALL_DROP + 2.2) * 0.5 - 0.6, MP_FALL)
    # No Wet_S sheen films: the wet read comes from the runtime material pass
    # (roughness/metallic + reflection probe), not a self-glowing deck skin.
# The hanging glow-vine and the pad motes were cut with the invented-elements
# purge (prop audit): no plate hangs a lit vine here, and the portal draws the
# eye by being a real lit assembly, not by floating sparks.

# ---- validate BEFORE meshing the grammar + exporting -------------------------------------
validate_survey()
gi_issues = g.validate()
print("=== GRAMMAR: %d issues ===" % len(gi_issues))
_pre_grammar = set(scene.collection.objects)
g.emit(scene)
_grammar_objs = [o for o in scene.collection.objects
                 if o.type == 'MESH' and o not in _pre_grammar]

# ---- preview render (scratchpad only), save master, export -------------------------------
OUT_PNG = os.environ.get("WD_PREVIEW", "")
if OUT_PNG:
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.07, 0.09, 1)
    sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 1.7; sun.color = (0.55, 0.62, 0.88)
    so = bpy.data.objects.new("Sun", sun); so.rotation_euler = (0.9, 0.2, 0.6)
    scene.collection.objects.link(so)
    cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 24
    cam = bpy.data.objects.new("Cam", cam_d); scene.collection.objects.link(cam); scene.camera = cam
    loc = mathutils.Vector((34, -34, 26)); tgt = mathutils.Vector((0, 0, 7))
    cam.location = loc; cam.rotation_euler = (tgt - loc).to_track_quat('-Z', 'Y').to_euler()
    for _eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
        try: scene.render.engine = _eng; break
        except Exception: pass
    scene.render.resolution_x = 1200; scene.render.resolution_y = 800
    scene.render.image_settings.file_format = 'PNG'; scene.render.filepath = OUT_PNG
    try: bpy.ops.render.render(write_still=True)
    except Exception as ex: print("render skipped:", ex)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "wash_dressing.blend"))
# The .blend keeps the master pieces (that's what makes it editable); the EXPORT ships
# only what was PLACED plus the grammar's own boxes. An unplaced master would otherwise
# ride into the game as a duplicate stack of geometry at the origin.
all_objs = [o for o in _placed if o.type == 'MESH'] + _grammar_objs
pl.export_gltf(all_objs, GLB)
print("=== DONE: %d unique pieces, %d placed objects, glb=%s ===" %
      (len(PIECES), len(all_objs), os.path.exists(GLB)))
