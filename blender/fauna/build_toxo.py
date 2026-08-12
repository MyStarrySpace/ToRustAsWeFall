# TOXO — the dead-zone filler, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_toxo.py
#
# The roster: "Toxos | failed-zone filler, common in dead zones | Toxoplasma
# gondii tachyzoite; THE CRESCENT BODY carries an APICAL CONOID invasion complex |
# Weak in a straight fight, thrives only where the local immune system already
# failed, so a cluster of them mostly tells you where you are | THE CONOID EXTENDS
# BEFORE A FEEBLE PIERCE. Easy to kill, easy to ignore."
#
# The transition is the conoid EXTENDING. That is the only warning a Toxo gives
# and the only reason to look at one, so it is the thing the body is built around:
# the crescent rests with the invasion complex pulled back inside its apical
# shoulder, pushes it out over a full beat, jabs once, and puts it away.
#
# It is the weakest thing on the roster and arrives in numbers, so it is cheap:
# one crescent of limb segments, a stout mineral apex, and the conoid's fibre cone
# drawn on a single card rather than modeled fibre by fibre.

import bpy
import importlib
import json
import math
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BL = os.path.join(ROOT, "blender")
if BL not in sys.path:
    sys.path.insert(0, BL)
import paintlib as pl
importlib.reload(pl)
from paintlib import Builder
from paintlib import rig
importlib.reload(rig)

SRC = os.path.join(BL, "fauna")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "fauna")
GLTF = os.path.join(OUT_DIR, "toxo.gltf")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

PAL = json.load(open(os.path.join(ROOT, "to-rust-as-we-fall", "data", "palettes",
                                  "level_palettes.json"), encoding="utf-8"))


def C(level, role):
    node = PAL[level]
    for part in role.split("/"):
        node = node[part]
    h = node.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def CS(role): return C("species", role)
def CH(role): return C("channels", role)
def _dim(c, f): return tuple(v * f for v in c)


# Nine segments rather than five because the spent panel is a tight ROUNDED ball,
# and a five-link chain closing on itself is a pentagon however hard it is bent.
# The count sets both the mesh subdivisions and the bones that deform them, so
# they stay equal and the bones-never-exceed-subdivisions law holds.
BODY_SEG = 9
BODY_SIDES = 5
DROPS = 9                  # the ring of shed fluid a deflating envelope leaves
DROP_START = 0               # segments along the crescent; one bone each
CONOID_SEG = 2             # the modeled apex: collar, then the cone off it
BODY_LEN = 0.56            # posterior point to apical shoulder, along +Y
BOW = 0.11                 # the crescent's sideways bow
BODY_Z = 0.088             # the belly rides the ground at the body's fattest
ARCH = 0.055               # the ends lift clear, the way a crescent lies
CONOID_MESH = 0.09         # how far the mineral apex reaches when extended
CONOID_REACH = 0.28        # how far the drawn fibre cone reaches
FIBRES = 3                 # fibre columns drawn across the cone
SPOKES = 5                 # spokes in the pierce discharge
BODY_START = []
CON_A_START = 0
CON_B_START = 0
PIERCE_START = 0


def _body_pt(t):
    """A point on the crescent's axis, posterior end (t=0) to apical end (t=1).
    The bow carries it sideways and the arch lifts both ends off the floor."""
    return ((math.sin(math.pi * t) - 0.5) * BOW,
            -BODY_LEN * 0.5 + BODY_LEN * t,
            BODY_Z + (1.0 - math.sin(math.pi * t)) * ARCH)


def _body_r(t):
    """Fattest at the middle, tapering to a point behind and to a BLUNT shoulder
    in front. The shoulder is what the conoid mounts on: an apex tapered to a
    needle leaves the invasion complex nothing to come out of."""
    return 0.014 + 0.068 * (math.sin(math.pi * t) ** 0.8) + 0.030 * (t ** 3)


def _apex_dir():
    """The heading the conoid travels, taken from the crescent's own tangent at
    the apical end and flattened. A level apex line keeps the drawn fibre cone in
    the same plane as the apex it grows from."""
    tip, back = _body_pt(1.0), _body_pt(0.9)
    dx, dy = tip[0] - back[0], tip[1] - back[1]
    n = math.hypot(dx, dy)
    return (dx / n, dy / n, 0.0)


def _apex_pt(d):
    """A point d metres out along the apex line from the apical shoulder."""
    tip = _body_pt(1.0)
    dr = _apex_dir()
    return (tip[0] + dr[0] * d, tip[1] + dr[1] * d, tip[2])


# A flat card's length runs along its own +Y, so this is the turn that lays it on
# the apex line: Rz maps (0,1,0) to (-sin, cos), which is the heading.
APEX_YAW = math.atan2(-_apex_dir()[0], _apex_dir()[1])


def _fibre_art(tile, isl, px_per_m):
    """The conoid's fibre cone: a spiral of tubulin fibres flaring off the collar
    and closing on the apical point. Drawn, because a fibre field is repetition —
    modeled one fibre at a time it aliases into a smear at the distance a Toxo is
    ever seen from, while a drawn one keeps its stripes."""
    ph, pw = tile.shape[:2]
    pale = _dim(CS("resolution_root_pale"), 1.02)
    mid = _dim(CS("resolution_root_pale"), 0.6)
    ring = _dim(CS("flure_bronze"), 1.15)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    base_rows = max(1, int(0.035 * px_per_m))
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)          # 0 = the collar, 1 = the point
        half = cx * (1.0 - 0.9 * t) * (0.55 + 0.45 * min(1.0, t * 4.0))
        for x in range(pw):
            d = x - cx
            if abs(d) > half:
                continue
            tile[row, x, 3] = 1.0
            if row < base_rows:               # the polar ring the fibres seat in
                tile[row, x, :3] = ring
                continue
            # Fibre columns are counted across the wedge's OWN width, so they
            # converge with it; the offset along the length is the twist.
            u = d / max(0.5, half)
            fib = int((u * 0.5 + 0.5) * FIBRES + t * 1.5)
            tile[row, x, :3] = pale if fib % 2 == 0 else mid


def _pierce_art(tile, isl, px_per_m):
    """The discharge at the point of the pierce: a short spoked splat. Small and
    sparse, because the strike it marks is a feeble one and a generous flash would
    promise damage the Toxo cannot do."""
    ph, pw = tile.shape[:2]
    core = _dim(CH("lamp_red"), 1.0)
    edge = _dim(CH("lamp_red"), 0.5)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            a = math.atan2(dy, dx)
            reach = 0.26 + 0.3 * (0.5 + 0.5 * math.cos(a * SPOKES))
            if r > reach:
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = core if r < reach * 0.45 else edge


FIBRE_ART = pl.register_card_art("toxo_fibre", _fibre_art)
PIERCE_ART = pl.register_card_art("toxo_pierce", _pierce_art)

pl.register_parts({
    # Drab on purpose: the roster's Toxo is easy to ignore, and a creature that
    # lights itself has already stopped being ignorable.
    "tx_body":   {"rgb": _dim(CS("gasafoetida_stalk"), 1.15)},
    "tx_conoid": {"rgb": _dim(CS("flure_bronze"), 0.9)},
    "tx_fibre":  {"rgb": _dim(CS("resolution_root_pale"), 0.95)},
    # The only light on the whole creature, and only while the jab lands.
    "tx_pierce": {"rgb": _dim(CH("lamp_red"), 0.9), "emit": _dim(CH("lamp_red"), 0.9)},
    # what a body losing pressure puts on the floor around itself
    "tx_drop":   {"rgb": _dim(CS("gasafoetida_stalk"), 0.82)},
}, emit_strength={"tx_pierce": 1.6})


def build_toxo():
    """A crescent of tapered segments carrying a mineral apex, with the conoid's
    fibre cone and its discharge drawn on cards at the apex line."""
    b = Builder()
    global CON_A_START, CON_B_START, PIERCE_START
    # ONE tube through every station rather than a limb per segment. Chained
    # limbs orient their rings to their own axes, so on a curve they meet in
    # different planes and share no vertices — the crescent was cut at all eight
    # joints and opened along them as soon as a pose bent it.
    BODY_START.append(len(b.bm.verts))
    _ts = [i / float(BODY_SEG) for i in range(BODY_SEG + 1)]
    b.tube([_body_pt(t) for t in _ts], [_body_r(t) for t in _ts], "tx_body",
           sides=BODY_SIDES)
    CON_A_START = len(b.bm.verts)
    b.limb(_apex_pt(0.0), _apex_pt(CONOID_MESH * 0.5), 0.042, 0.034, "tx_conoid",
           sides=6)
    CON_B_START = len(b.bm.verts)
    b.limb(_apex_pt(CONOID_MESH * 0.5), _apex_pt(CONOID_MESH), 0.034, 0.01,
           "tx_conoid", sides=6)
    # The fibre cone reaches well past the modeled apex, so its base rows sit
    # inside the collar and no seam shows where the drawing takes over.
    b.card(_apex_pt(0.5 * (0.04 + CONOID_REACH)), (0.14, CONOID_REACH - 0.04),
           "tx_fibre", axis='Z', art=FIBRE_ART, rot=(0.0, 0.0, APEX_YAW))
    # THE DROPLETS the melt sheds, modelled at full size and parked at nothing.
    # Shed parts are keyframed detachables, never simulation — the sheet rings the
    # collapsed body with them and they are the difference between a corpse that
    # deflated and one that merely lay down.
    global DROP_START
    DROP_START = len(b.bm.verts)
    def _h(i, salt):
        """Deterministic scatter. A corpse whose fluid lands somewhere new on every
        build cannot be compared against the last render."""
        n = ((i * 73856093) ^ (salt * 19349663)) & 0xFFFFFF
        return (n % 1000) / 1000.0

    for d in range(DROPS):
        a = math.tau * d / DROPS + 0.4
        rr = 0.22 + 0.26 * _h(d, 3)
        seat = _body_pt(0.15 + 0.7 * _h(d, 7))
        b.ngon_prism((seat[0] + math.cos(a) * rr, seat[1] + math.sin(a) * rr),
                     0.014 + 0.010 * _h(d, 11), 0.020 + 0.012 * _h(d, 13),
                     0.013, "tx_drop", sides=6, z0=0.004)
    PIERCE_START = len(b.bm.verts)
    for axis in ('Z', 'Y'):                  # crossed, so the splat reads all round
        b.card(_apex_pt(0.25), (0.28, 0.28), "tx_pierce", axis=axis, art=PIERCE_ART)
    return b.finish("ToxoRigged")


def toxo_chains():
    """A chain along the crescent so the body can coil and lunge, a short chain
    for the apex so the conoid travels out of it, and the discharge on its own."""
    chains = [{"prefix": "body",
               "points": [_body_pt(i / float(BODY_SEG)) for i in range(BODY_SEG + 1)]}]
    chains.append({"prefix": "conoid", "parent": "body_%d" % (BODY_SEG - 1),
                   "points": [_apex_pt(CONOID_MESH * i / float(CONOID_SEG))
                              for i in range(CONOID_SEG + 1)]})
    chains.append({"prefix": "pierce", "parent": "conoid_%d" % (CONOID_SEG - 1),
                   "points": [_apex_pt(0.24), _apex_pt(0.31)]})
    # the shed fluid rides its own bone, off the BODY's root rather than the apex,
    # so it stays on the floor while the crescent above it flattens
    chains.append({"prefix": "drop", "parent": "body_0",
                   "points": [(0.0, 0.0, 0.004), (0.0, 0.0, 0.05)]})
    return chains


piece = build_toxo()
pl.texture_object(piece, OBJX, px_per_m=48.0, painted_dir=PAINTED)
arm = rig.build_armature("Toxo", toxo_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')
# The crescent is the STRUCTURE and holds its own bones: weighted to the apex it
# would swing every time the conoid moved.
# The tube is one run of rings, so a bone claims the ring at its TIP; the root
# ring travels with the first bone. Ring r occupies BODY_SIDES consecutive
# vertices from the tube's base index.
_base = BODY_START[0]
for i in range(BODY_SEG):
    _lo = _base + (0 if i == 0 else (i + 1) * BODY_SIDES)
    _hi = _base + (i + 2) * BODY_SIDES
    rig.assign_exclusive_weights(piece, "body_%d" % i, range(_lo, _hi))
rig.assign_exclusive_weights(piece, "conoid_0", range(CON_A_START, CON_B_START))
# the outer cone and the fibre card travel together, as one invasion complex
rig.assign_exclusive_weights(piece, "conoid_1", range(CON_B_START, DROP_START))
rig.assign_exclusive_weights(piece, "drop_0", range(DROP_START, PIERCE_START))
rig.assign_exclusive_weights(piece, "pierce_0",
                             range(PIERCE_START, len(piece.data.vertices)))

# RETRACTED is the rest state and what a Toxo looks like for almost all of its
# life: the conoid collapsed back into the apical shoulder, the discharge shut.
# Scaling the collar carries the cone and the fibre card in with it, which is what
# makes the withdrawal one motion instead of three parts sliding apart.
RETRACTED = {"conoid_0": 0.12, "conoid_1": 1.0, "pierce_0": 0.001,
             "drop_0": 0.001}
EXTENDED = dict(RETRACTED, conoid_0=1.0)
# The crescent draws itself together behind the extension and straightens through
# the jab, so the tell is legible from the whole body and not just its tip.
def _curl(total, lead=0.30):
    """A body pose bent by `total` radians overall, whatever the segment count.

    chain_wave takes a PER-JOINT amount, so a pose written that way changes shape
    the moment the chain gets longer — every existing bend deepens in proportion.
    Quoting the total instead pins the shape to the animal rather than to the
    topology, and the conversion happens in one place.
    """
    return rig.chain_wave("body", BODY_SEG,
                          total / (BODY_SEG * (1.0 - lead * 0.5)), lead=lead)


FLAT = _curl(0.0)
COILED = _curl(0.35, lead=0.45)
LUNGED = _curl(-0.19, lead=0.45)
HALF_COIL = dict((k, (v[0] * 0.5, 0.0, 0.0)) for k, v in COILED.items())

# EXTEND: the warning. A full beat of the conoid travelling out, which is the
# window the roster gives for walking away from something this weak.
rig.clip(arm, "toxo_extend", [
    (0.0, dict(RETRACTED, **FLAT)),
    (0.35, dict(RETRACTED, conoid_0=0.45, **HALF_COIL)),
    (1.0, dict(EXTENDED, **COILED)),
])
# PIERCE: the jab and the withdrawal. The conoid punches the last of its travel,
# the discharge shows for a moment, and the crescent puts everything away.
rig.clip(arm, "toxo_pierce", [
    (0.0, dict(EXTENDED, **COILED)),
    (0.10, dict(EXTENDED, conoid_1=1.22, **LUNGED)),
    (0.15, dict(EXTENDED, conoid_1=1.22, **LUNGED)),
    (0.20, dict(EXTENDED, conoid_1=1.22, pierce_0=1.0, **LUNGED)),
    (0.29, dict(EXTENDED, conoid_1=1.05, **LUNGED)),
    (0.75, dict(RETRACTED, **FLAT)),
])
# RETRACT: a Toxo that extended and lost whatever it was aimed at stands down
# without ever striking, back to the state it spends its life in.
rig.clip(arm, "toxo_retract", [
    (0.0, dict(EXTENDED, **COILED)),
    (0.6, dict(RETRACTED, **FLAT)),
])
# CURL: the defeated read the sheet asks for. A crescent already bends one way,
# so defeat is that same bend taken past where the living body ever takes it —
# the shape closing on itself rather than a new posture, which keeps the distant
# silhouette readable as the SAME animal. The conoid goes further in than
# RETRACTED ever puts it: withdrawn is a thing the body is doing, and this is the
# body stopping. It holds on the last pose so a corpse lies still.
CURLED = _curl(1.31, lead=0.25)
# Curling a chain about its own base swings the far end UP, and a corpse that
# rears is not reading as a corpse. The base pitches down by about what the curl
# lifts, so the crescent closes toward the floor instead of away from it.
CURLED["body_0"] = (-0.34, 0.0, 0.05)
DEAD = dict(RETRACTED, conoid_0=0.05, conoid_1=0.88)
rig.clip(arm, "toxo_curl", [
    (0.0, dict(RETRACTED, **FLAT)),
    (0.20, dict(RETRACTED, conoid_0=0.09, **HALF_COIL)),
    (0.80, dict(DEAD, **CURLED)),
    (1.35, dict(DEAD, **CURLED)),
])

# TUCK: the spent read, which the sheet draws as its own panel beside the
# defeated one — a tight rounded ball with the apex carried DOWN AND UNDER and
# the crescent's open C shut to a small round hole. It is not toxo_curl with a
# tighter number: curl stops the body and holds it stopped, while this is a
# living animal folded away, so the aperture closes to a hole rather than to
# nothing and the fibres draw in instead of going slack. Two panels, two clips.
TUCKED = _curl(5.0, lead=0.30)
# The apex has to end up beneath the coil, not beside it, so the base pitches
# down harder than the curl's — enough that the hook's own bend carries the tip
# under the body rather than out past it.
TUCKED["body_0"] = (-0.55, 0.0, 0.08)
SPENT = dict(RETRACTED, conoid_0=0.22, conoid_1=0.58)
rig.clip(arm, "toxo_tuck", [
    (0.0, dict(RETRACTED, **FLAT)),
    (0.45, dict(RETRACTED, conoid_0=0.55, **HALF_COIL)),
    (1.10, dict(SPENT, **TUCKED)),
    (2.40, dict(SPENT, **TUCKED)),
])

# MELT: the death panel, which is a COLLAPSE and not a tighter curl. The envelope
# loses pressure and slumps into a low spread dome — the crescent's section going
# flat while its footprint widens, the apex laying over onto the ground with the
# nucleus still visible inside it. The other two closings stay distinct from it
# and from each other: toxo_curl stops the body with its section preserved, and
# toxo_tuck folds a living one away.
#
# The body bones run ALONG the crescent, so their local Y is its length and the
# two axes that have to give are the other two. Squashing local Y would shorten
# the animal rather than deflate it.
def _melt(amount):
    out = {}
    for i in range(BODY_SEG):
        f = 0.55 + 0.45 * (i / float(max(1, BODY_SEG - 1)))   # the tail goes first
        flat = 1.0 - 0.72 * amount * f
        wide = 1.0 + 0.46 * amount * f
        out["body_%d" % i] = {"scale": (wide, 1.0, flat)}
    return out


MELTED = dict(_melt(1.0))
MELTED.update(_curl(0.51, lead=0.3))
MELTED["body_0"] = (-0.24, 0.0, 0.04)
rig.clip(arm, "toxo_melt", [
    (0.0, dict(RETRACTED, **FLAT)),
    (0.35, dict(RETRACTED, conoid_0=0.09, **_melt(0.30))),
    (1.0, dict(DEAD, **dict(_melt(0.72), **{"body_0": (-0.16, 0.0, 0.03)}))),
    (1.8, dict(DEAD, drop_0=0.7, **MELTED)),
    (2.5, dict(DEAD, drop_0=1.0, **MELTED)),   # a corpse holds still, the fluid stays
])

# The REST the sheets actually draw: a closed comma, the tail hooked back under
# the body, and the conoid OUT. The build parked on RETRACTED with an uncurled
# body, which is a shallow open banana with its tooling withdrawn — a pose no
# drawn panel on either sheet shows. Same mistake as a fern resting with its eyes
# already lit: the state the player sees all the time was the one state the
# reference never draws.
RESTING = dict(EXTENDED)
RESTING.update(_curl(2.6, lead=0.25))
# Curling a chain about its own base swings the far end UP, and the sheet's hook
# closes toward the ground, so the base pitches down by about what the curl lifts.
RESTING["body_0"] = (-0.30, 0.0, 0.04)
rig.park(arm, dict(RESTING))

report = rig.validate(piece, arm, {"body": BODY_SEG, "conoid": CONOID_SEG})
print("[RIG] Toxo %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("toxo rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "toxo.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: toxo -> %s ===" % GLTF)
