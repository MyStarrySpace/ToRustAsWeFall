# DOOR PIECES — the ways through, and every one of them MOVES.
#
# Blender 5.1 only:  blender.exe -b --python blender/architecture/build_door_pieces.py
#
# THE SHEET IS THE BRIEF: reference-images/architecture/sheets/crowns.png (it
# holds the doors, whatever the filename says) names five, and names a STATE for
# four of them — "iris-membrane pore (dilates open)", "cycling dwelling-slab door
# (mid-cycle)", "tag-reader scan-arch (cyan-white scan-bar)", "single-file toll-
# meter gate", "heavy sealed blast-bulkhead".
#
# A state change is an ANIMATION, so each of these ships with an armature and the
# transition its label describes. A door drawn open and a door drawn shut are two
# pictures; what the player watches is the dilating, the cycling, the sweep of the
# scan bar and the turnstile coming round.
#
# What is modelled and what is drawn:
#   MODELLED  frames, jambs, the slab, the bulkhead's dogs and wheel, the
#             turnstile arms, the iris petals. These move, and a bone has to have
#             something to move.
#   DRAWN     the nodule ring around every frame, the membrane's radial fibres,
#             the slab's stonework, the terminal panels and their green text, the
#             bulkhead's plating. All of it repeats and none of it moves alone.
#
# One gltf per rigged subject: NLA_TRACKS samples every selected armature over
# every clip, so several rigs in one file give each door the others' bones.

import bpy
import importlib
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

SRC = os.path.join(BL, "architecture")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
OUT_DIR = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "architecture")
for d in (OBJX, PAINTED, OUT_DIR):
    os.makedirs(d, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True)

TEAL = (0.286, 0.376, 0.376)
TEAL_D = (0.196, 0.267, 0.271)
TEAL_L = (0.376, 0.475, 0.463)
BONE = (0.812, 0.796, 0.714)
BONE_D = (0.612, 0.600, 0.529)
STONE = (0.694, 0.667, 0.596)
RUST = (0.463, 0.243, 0.129)
GREEN = (0.361, 0.910, 0.498)
CYAN = (0.545, 0.949, 0.918)
MOSS = (0.400, 0.494, 0.302)

W, HT = 1.10, 2.05           # a door's opening
IRIS_PETALS = 12


def _dim(c, f):
    return tuple(min(1.0, v * f) for v in c)


def _nodule_ring_art(tile, isl, px_per_m):
    """The ring of bone nodules every frame on this sheet wears, with moss in the
    joints. Drawn once and used by all five, because it is the thing that makes
    them read as the same building's doors."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 1.0
    pitch = max(4, int(0.16 * ph))
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = TEAL
            row = y // pitch
            ox = (pitch * 0.5) if (row % 2) else 0.0
            cxp = (math.floor((x - ox) / pitch) + 0.5) * pitch + ox
            cyp = (row + 0.5) * pitch
            d = ((x - cxp) ** 2 + (y - cyp) ** 2) ** 0.5 / (pitch * 0.42)
            if d < 1.0:
                tile[y, x, :3] = _dim(BONE, 1.0 - 0.28 * d)
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 11:
                tile[y, x, :3] = _dim(RUST, 0.9)
            elif h > 246 and y > ph * 0.7:
                tile[y, x, :3] = MOSS


def _membrane_art(tile, isl, px_per_m):
    """The iris membrane: fibres running from the slit out to the rim. They are
    what makes the dilation read — the eye follows the radial lines opening."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 0.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / rad, (y - cy) / rad
            r = (dx * dx + dy * dy) ** 0.5
            if r > 1.0:
                continue
            a = math.atan2(dy, dx)
            tile[y, x, 3] = 1.0
            fib = abs(math.cos(a * 26.0))
            base = _dim(BONE, 0.96 - 0.16 * r)
            tile[y, x, :3] = _dim(base, 0.86) if fib > 0.72 else base
            if r > 0.94:
                tile[y, x, :3] = BONE_D


def _stone_slab_art(tile, isl, px_per_m):
    """The dwelling slab: coursed blocks with rust weeping down the joints."""
    ph, pw = tile.shape[:2]
    tile[:, :, 3] = 1.0
    course = max(5, int(0.13 * ph))
    for y in range(ph):
        row = y // course
        ox = (pw * 0.33) if (row % 2) else 0.0
        for x in range(pw):
            tile[y, x, :3] = STONE
            block = (x + ox) % max(6, int(pw * 0.42))
            if y % course < 1 or block < 1:
                tile[y, x, :3] = _dim(STONE, 0.72)
            h = ((x * 26699) ^ (y * 92083)) & 0xFF
            if h < 10:
                tile[y, x, :3] = _dim(RUST, 0.85)
            elif h > 250:
                tile[y, x, :3] = _dim(STONE, 1.1)


def _terminal_art(tile, isl, px_per_m):
    """A jamb terminal: dark glass with green readout. Illegible on purpose — it
    is a texture of information, and the words of this world are not mine."""
    ph, pw = tile.shape[:2]
    emit = isl.get("emit") if isinstance(isl, dict) else None
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            tile[y, x, :3] = (0.055, 0.070, 0.063)
    for row in range(2, ph - 2, 3):
        for x in range(2, pw - 2):
            h = ((x * 26699) ^ (row * 92083)) & 0xFF
            if h > 150:
                continue
            tile[row, x, :3] = GREEN
            if emit is not None:
                emit[row, x] = GREEN


def _bulkhead_art(tile, isl, px_per_m):
    """The blast door: radial ribs off a central boss, with the dog-bolts round
    its rim. All of it repeats, so all of it is pixels."""
    ph, pw = tile.shape[:2]
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    rad = min(cx, cy)
    tile[:, :, 3] = 1.0
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / rad, (y - cy) / rad
            r = (dx * dx + dy * dy) ** 0.5
            a = math.atan2(dy, dx)
            tile[y, x, :3] = STONE
            if abs(math.cos(a * 5.0)) > 0.955 and 0.16 < r < 0.92:
                tile[y, x, :3] = _dim(STONE, 0.74)          # a rib
            for band in (0.42, 0.74):
                if abs(r - band) < 0.035:
                    tile[y, x, :3] = _dim(STONE, 0.8)
            if r < 0.15:
                tile[y, x, :3] = _dim(BONE_D, 0.95)         # the boss
            if 0.86 < r < 0.94 and abs(math.cos(a * 8.0)) > 0.88:
                tile[y, x, :3] = _dim(BONE, 0.9)            # the dogs
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFF
            if h < 12:
                tile[y, x, :3] = _dim(RUST, 0.85)


NODULE = pl.register_card_art("door_nodule_ring", _nodule_ring_art)
MEMB = pl.register_card_art("door_membrane", _membrane_art)
SLAB = pl.register_card_art("door_stone_slab", _stone_slab_art)
TERM = pl.register_card_art("door_terminal", _terminal_art)
BULK = pl.register_card_art("door_bulkhead", _bulkhead_art)

pl.register_parts({
    "dr_frame": {"rgb": TEAL},
    "dr_frame_d": {"rgb": TEAL_D},
    "dr_frame_l": {"rgb": TEAL_L},
    "dr_memb": {"rgb": BONE},
    "dr_slab": {"rgb": STONE},
    "dr_term": {"rgb": (0.055, 0.070, 0.063), "emit": GREEN},
    "dr_scan": {"rgb": CYAN, "emit": CYAN},
    "dr_bulk": {"rgb": STONE},
}, emit_strength={"dr_term": 2.4, "dr_scan": 4.0})


def _frame(b):
    """The jambs and head every door on this sheet shares."""
    for sgn in (-1.0, 1.0):
        j = ((sgn * (W * 0.5 + 0.11), 0.0, HT * 0.5), (0.22, 0.30, HT))
        b.box(*j[:2], "dr_frame")
        b.face_card(j[0], j[1], (0.20, HT * 0.96), "dr_frame", face='-Y',
                    art=NODULE)
    head = ((0.0, 0.0, HT + 0.11), (W + 0.44, 0.30, 0.22))
    b.box(*head[:2], "dr_frame")
    b.face_card(head[0], head[1], (W + 0.40, 0.20), "dr_frame", face='-Y',
                art=NODULE)
    b.box((0.0, 0.0, -0.06), (W + 0.44, 0.34, 0.12), "dr_frame_d")


def build_iris_pore():
    """(1) The pore, and the petals that dilate it open."""
    b = Builder()
    _frame(b)
    starts = []
    for i in range(IRIS_PETALS):
        a = math.tau * i / IRIS_PETALS
        starts.append(len(b.bm.verts))
        # each petal reaches from the rim toward the centre; opening swings it back
        b.card((math.cos(a) * W * 0.26, -0.02, HT * 0.5 + math.sin(a) * W * 0.26),
               (W * 0.34, W * 0.52), "dr_memb", axis='Y', art=MEMB,
               rot=(0.0, 0.0, a))
    return b.finish("DoorIrisPore"), starts


def build_slab_door():
    """(2) The dwelling slab, caught mid-cycle."""
    b = Builder()
    _frame(b)
    start = len(b.bm.verts)
    slab = ((0.0, -0.02, HT * 0.5), (W * 0.94, 0.14, HT * 0.94))
    b.box(*slab[:2], "dr_slab")
    b.face_card(slab[0], slab[1], (W * 0.88, HT * 0.88), "dr_slab", face='-Y',
                art=SLAB)
    term = ((W * 0.5 + 0.12, -0.12, HT * 0.62), (0.13, 0.05, 0.30))
    b.box(*term[:2], "dr_term")
    b.face_card(term[0], term[1], (0.11, 0.26), "dr_term", face='-Y', art=TERM)
    return b.finish("DoorSlab"), start


def build_scan_arch():
    """(3) The tag-reader: an open arch and the bar that sweeps it."""
    b = Builder()
    _frame(b)
    start = len(b.bm.verts)
    b.box((0.0, -0.04, HT * 0.52), (W * 0.98, 0.06, 0.05), "dr_scan")
    term = ((-W * 0.5 - 0.12, -0.12, HT * 0.44), (0.13, 0.05, 0.34))
    b.box(*term[:2], "dr_term")
    b.face_card(term[0], term[1], (0.11, 0.30), "dr_term", face='-Y', art=TERM)
    return b.finish("DoorScanArch"), start


def build_toll_gate():
    """(4) The toll meter: its sign, and the turnstile that lets one through."""
    b = Builder()
    _frame(b)
    sign = ((0.0, -0.10, HT * 0.80), (W * 0.86, 0.07, HT * 0.30))
    b.box(*sign[:2], "dr_term")
    b.face_card(sign[0], sign[1], (W * 0.80, HT * 0.26), "dr_term", face='-Y',
                art=TERM)
    b.ngon_prism((0, 0), 0.06, 0.08, HT * 0.44, "dr_frame_l", sides=8, z0=0.0)
    start = len(b.bm.verts)
    for k in range(3):                       # the turnstile arms
        a = math.tau * k / 3.0
        b.limb((0.0, 0.0, HT * 0.42),
               (math.cos(a) * W * 0.40, math.sin(a) * W * 0.40, HT * 0.42),
               0.035, 0.028, "dr_frame_l", sides=5)
    return b.finish("DoorTollGate"), start


def build_blast_bulkhead():
    """(5) The sealed bulkhead, and the wheel that unseals it."""
    b = Builder()
    _frame(b)
    start = len(b.bm.verts)
    door = ((0.0, -0.03, HT * 0.5), (W * 0.94, 0.17, HT * 0.92))
    b.box(*door[:2], "dr_bulk")
    b.face_card(door[0], door[1], (W * 0.88, HT * 0.86), "dr_bulk", face='-Y',
                art=BULK)
    wheel_start = len(b.bm.verts)
    b.annulus((0.0, -0.14, HT * 0.5), 0.20, 0.15, 0.05, "dr_frame_l", sides=16)
    for k in range(4):
        a = math.tau * k / 4.0
        b.limb((0.0, -0.14, HT * 0.5),
               (math.cos(a) * 0.18, -0.14, HT * 0.5 + math.sin(a) * 0.18),
               0.022, 0.018, "dr_frame_l", sides=4)
    return b.finish("DoorBlastBulkhead"), (start, wheel_start)


# ---------------------------------------------------------------- build and rig
SPECS = []

iris, iris_starts = build_iris_pore()
SPECS.append(("iris_pore", iris, 48.0, ("iris", iris_starts)))
slab, slab_start = build_slab_door()
SPECS.append(("slab_door", slab, 48.0, ("slab", slab_start)))
arch, arch_start = build_scan_arch()
SPECS.append(("scan_arch", arch, 48.0, ("scan", arch_start)))
toll, toll_start = build_toll_gate()
SPECS.append(("toll_gate", toll, 48.0, ("toll", toll_start)))
bulk, bulk_starts = build_blast_bulkhead()
SPECS.append(("blast_bulkhead", bulk, 48.0, ("bulk", bulk_starts)))

for name, piece, px, _kind in SPECS:
    pl.texture_object(piece, OBJX, px_per_m=px, painted_dir=PAINTED)
    print("[DOOR] built %s: %d verts, %d polys"
          % (piece.name, len(piece.data.vertices), len(piece.data.polygons)))


def rig_iris(piece, starts):
    """Twelve petals, one bone each — the dilation is each petal swinging back
    toward its own rim, which is what an iris does and what a scale on the whole
    membrane could never look like."""
    chains = []
    for i in range(IRIS_PETALS):
        a = math.tau * i / IRIS_PETALS
        base = (math.cos(a) * W * 0.52, 0.0, HT * 0.5 + math.sin(a) * W * 0.52)
        tip = (math.cos(a) * W * 0.05, 0.0, HT * 0.5 + math.sin(a) * W * 0.05)
        chains.append({"prefix": "petal%d" % i, "points": [base, tip]})
    chains.insert(0, {"prefix": "frame",
                      "points": [(0.0, 0.0, 0.0), (0.0, 0.0, HT + 0.22)]})
    arm = rig.build_armature("DoorIris", chains)
    rig.bind(piece, arm, kind='ARMATURE_NAME')
    rig.assign_exclusive_weights(piece, "frame_0", range(0, starts[0]))
    ends = starts[1:] + [len(piece.data.vertices)]
    for i, (s0, s1) in enumerate(zip(starts, ends)):
        rig.assign_exclusive_weights(piece, "petal%d_0" % i, range(s0, s1))
    shut = {"petal%d_0" % i: (0.0, 0.0, 0.0) for i in range(IRIS_PETALS)}
    open_ = {"petal%d_0" % i: (0.0, 0.0, -1.05) for i in range(IRIS_PETALS)}
    rig.clip(arm, "iris_dilate", [(0.0, dict(shut)), (1.1, dict(open_))])
    rig.clip(arm, "iris_close", [(0.0, dict(open_)), (1.3, dict(shut))])
    rig.park(arm, dict(shut))
    return arm


def rig_single(piece, start, name, bone_pts, clips):
    """One moving part on one bone: the slab, the scan bar, the turnstile."""
    chains = [{"prefix": "frame", "points": [(0.0, 0.0, 0.0), (0.0, 0.0, HT + 0.22)]},
              {"prefix": name, "points": bone_pts}]
    arm = rig.build_armature("Door" + name.capitalize(), chains)
    rig.bind(piece, arm, kind='ARMATURE_NAME')
    rig.assign_exclusive_weights(piece, "frame_0", range(0, start))
    rig.assign_exclusive_weights(piece, name + "_0",
                                 range(start, len(piece.data.vertices)))
    for cname, poses in clips:
        rig.clip(arm, cname, poses)
    rig.park(arm, clips[0][1][0][1])
    return arm


ARMS = {}
ARMS["iris_pore"] = rig_iris(iris, iris_starts)
ARMS["slab_door"] = rig_single(
    slab, slab_start, "slab", [(0.0, 0.0, 0.0), (0.0, 0.0, HT)],
    [("slab_cycle_open", [(0.0, {"slab_0": 1.0}), (1.4, {"slab_0": 0.06})]),
     ("slab_cycle_shut", [(0.0, {"slab_0": 0.06}), (1.6, {"slab_0": 1.0})])])
ARMS["scan_arch"] = rig_single(
    arch, arch_start, "scan", [(0.0, 0.0, HT * 0.10), (0.0, 0.0, HT * 0.95)],
    # A SWEEP HAS TO MOVE. This clip opened and closed on the same pose, so the
    # scan bar sat still for a second and a half and called it a scan. The bar
    # tilts through the opening instead: the bone runs up the arch, so rotating it
    # about X carries the bar down the doorway and back, which is a plane sweeping
    # whatever stands in it.
    [("scan_sweep", [(0.0, {"scan_0": (-0.55, 0.0, 0.0)}),
                     (0.9, {"scan_0": (0.55, 0.0, 0.0)}),
                     (1.8, {"scan_0": (-0.55, 0.0, 0.0)})])])
ARMS["toll_gate"] = rig_single(
    toll, toll_start, "toll", [(0.0, 0.0, HT * 0.42), (0.0, 0.0, HT * 0.62)],
    [("toll_admit", [(0.0, {"toll_0": (0.0, 0.0, 0.0)}),
                     (1.2, {"toll_0": (0.0, 2.094, 0.0)})])])
ARMS["blast_bulkhead"] = rig_single(
    bulk, bulk_starts[0], "bulk", [(0.0, 0.0, HT * 0.5), (0.0, -0.6, HT * 0.5)],
    [("bulk_unseal", [(0.0, {"bulk_0": (0.0, 0.0, 0.0)}),
                      (2.0, {"bulk_0": (0.0, 2.4, 0.0)})]),
     ("bulk_seal", [(0.0, {"bulk_0": (0.0, 2.4, 0.0)}),
                    (2.2, {"bulk_0": (0.0, 0.0, 0.0)})])])

for name, piece, _px, _k in SPECS:
    arm = ARMS[name]
    report = rig.validate(piece, arm)
    print("[RIG] %-16s %s bones=%d dead=%s orphans=%d"
          % (name, report["verdict"], report["bones"],
             report["dead_bones"] or "none", report["orphan_verts"]))
    if report["verdict"] != "PASS":
        raise SystemExit("%s rig does not deform: %s" % (name, report["problems"]))

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "door_pieces.blend"))
for name, piece, _px, _k in SPECS:
    rig.export_rigged_gltf([piece, ARMS[name]],
                           os.path.join(OUT_DIR, "door_%s.gltf" % name))
    print("[DOOR] exported door_%s.gltf" % name)
print("=== DONE: door pieces -> %s ===" % OUT_DIR)
