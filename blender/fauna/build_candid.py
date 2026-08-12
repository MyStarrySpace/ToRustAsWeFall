# CANDID — the colony zone, rigged. Blender 5.1 only:
#   blender.exe -b --python blender/fauna/build_candid.py
#
# The roster builds this one out of layers and then takes them away one at a time:
# "*Candida* biofilm, in three strata (yeast carpet, pseudohyphal chains, hyphal
# canopy)", and "Fire burns the canopy down a layer, and sustained Scarpet tending
# outcompetes and retreats it." So the colony is three strata that go in order,
# and burning it is a state the player can read off the floor rather than a number
# somewhere.
#
# "Bleached flooring is the warning", so the pale ring it leaves in the substrate
# is part of the piece — it is how a corridor tells you what it is before you
# stand in it.
#
# Built against the director's sheets, which are the authority:
#   .../concept/fauna/candid-affordance-concept-01.png (and the turnaround)
#
# They draw the three strata precisely, and none of them was a flat card:
#   CARPET  a BERM of rounded buds with real height, whose scalloped rim is the
#           colony's outline along the ground.
#   CHAINS  BEADED columns — pearl-strings of budded cells — densely ranked, and
#           the beading shows in the silhouette, so it is the columns' own form.
#   CANOPY  a flat DENDRITIC ROOF of branching filaments lying ACROSS the top and
#           overhanging the front rim. Not uprights.
# And the whole colony is BONE-WHITE, palest at the halo, warming only where the
# skirt falls into shadow.

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
GLTF = os.path.join(OUT_DIR, "candid.gltf")
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


SPAN = 1.7
CHAINS = 17                # the sheet ranks them shoulder to shoulder.
                           # ADDING COLUMNS DOES NOT ADD STRIPS — measured. The
                           # silhouette shows 12 distinct strips at 17 columns
                           # over three radii and only 10 at 27 over four,
                           # because columns at different radii overlap in
                           # projection and merge the gaps that made them
                           # countable. The sheet's 18 comes from ONE dense arc
                           # with daylight between neighbours, not from more
                           # bodies. Do not raise this number to chase the count.
BEADS = 5                  # budded cells stacked up one column
CANOPY = 8
RIM_BUDS = 22              # the berm's scalloped edge, which IS the outline
BERM_Z = 0.16
BLEACH_START = 0
CARPET_START = 0
CHAIN_START = []
CANOPY_START = []


def _ring_at(k, count, radius, phase):
    a = math.tau * k / count + phase
    return (math.sin(a) * radius, math.cos(a) * radius * 0.82)


def _bleach_art(tile, isl, px_per_m):
    """The warning: flooring the colony has bleached, palest where it has been
    colonised longest. Drawn, because a stain is the definition of something that
    should never be geometry."""
    ph, pw = tile.shape[:2]
    # Bleached means PALER THAN THE FLOOR — and paler than the COLONY, which is
    # the part that went wrong. When the strata were repainted bone-white this
    # painter kept its own mid-tan, so the halo came out the warmest and DARKEST
    # material in the piece, measured below the body it rings. The sheet makes it
    # the palest thing in the frame; a stain that reads darker than what stains it
    # is not a warning, it is a shadow.
    pale = _mix(_WHITE, _TAN, 0.02)
    mid = _mix(_WHITE, _TAN, 0.22)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            dx, dy = (x - cx) / max(1.0, cx), (y - cy) / max(1.0, cy)
            r = (dx * dx + dy * dy) ** 0.5
            h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
            edge = 0.72 + 0.26 * ((h % 100) / 100.0)
            if r > edge:
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            tile[y, x, :3] = pale if r < 0.5 else mid


def _strand_art(tile, isl, px_per_m):
    """A pseudohyphal chain seen edge-on: budded cells end to end, which is what
    makes the middle stratum read as chains rather than as more carpet."""
    ph, pw = tile.shape[:2]
    body = _dim(CS("gasafoetida_pod"), 1.05)
    body_d = _dim(CS("gasafoetida_pod"), 0.7)
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    for row in range(ph):
        t = row / max(1.0, ph - 1.0)
        half = max(0.6, cx * (0.85 - 0.35 * t))
        seg = (row // max(1, int(0.045 * px_per_m))) % 2
        for x in range(pw):
            if abs(x - cx) > half:
                continue
            tile[row, x, 3] = 1.0
            tile[row, x, :3] = body if seg == 0 else body_d


def _dendrite_art(tile, isl, px_per_m):
    """The hyphal canopy seen from ABOVE: filaments branching out of a centre in a
    star, thin enough to see the colony through. Drawn, because a lattice of
    branches is repetition — modelled it would spend triangles to alias into mush
    at gameplay distance, and this way it stays crisp and an artist can edit it."""
    ph, pw = tile.shape[:2]
    pale = _mix(_WHITE, _TAN, 0.10)
    mid = _mix(_WHITE, _TAN, 0.34)
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    tile[:, :, 3] = 0.0

    def stroke(x0, y0, ang, length, width, col):
        n = max(2, int(length))
        for i in range(n):
            t = i / float(n - 1)
            x = x0 + math.cos(ang) * length * t
            y = y0 + math.sin(ang) * length * t
            w = max(0.5, width * (1.0 - 0.55 * t))
            iw = int(w)
            for oy in range(-iw, iw + 1):
                for ox in range(-iw, iw + 1):
                    px, py = int(round(x)) + ox, int(round(y)) + oy
                    if 0 <= px < pw and 0 <= py < ph:
                        tile[py, px, 3] = 1.0
                        tile[py, px, :3] = col

    arms = 7
    reach = min(cx, cy) * 0.94
    for a in range(arms):
        ang = math.tau * a / arms + 0.35
        stroke(cx, cy, ang, reach, 1.6, pale)
        # side branches, each shorter than the arm it leaves — the dendritic read
        for f in (0.34, 0.56, 0.76):
            bx = cx + math.cos(ang) * reach * f
            by = cy + math.sin(ang) * reach * f
            for sgn in (-1.0, 1.0):
                stroke(bx, by, ang + sgn * 0.85, reach * (0.30 - 0.07 * f),
                       1.1, mid)
    for a in range(arms):                      # the node each arm leaves from
        ang = math.tau * a / arms + 0.35
        stroke(cx, cy, ang, reach * 0.10, 2.2, pale)


BLEACH_ART = pl.register_card_art("candid_bleach", _bleach_art)
DENDRITE_ART = pl.register_card_art("candid_dendrite", _dendrite_art)

STRAND_ART = pl.register_card_art("candid_strand", _strand_art)

def _mix(a, b, t):
    """Bone-white is a WARM near-white and the palette carries no such role: the
    cool near-white and the mid tan mixed give it, and mixing beats dimming
    because dimming a cool white only makes a cool grey."""
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


_WHITE = CS("seefern_vein_core")
_TAN = CS("resolution_root_pale")
BONE = _mix(_WHITE, _TAN, 0.30)
BONE_D = _mix(_WHITE, _TAN, 0.62)

pl.register_parts({
    # THE COLONY IS THE PALEST MASS IN THE FRAME and the halo paler still. The
    # build had every stratum keyed to an olive-yellow pod colour borrowed from
    # another species, so the one value the sheet never uses was the only one it
    # had.
    "cd_bleach": {"rgb": _mix(_WHITE, _TAN, 0.10)},
    "cd_carpet": {"rgb": BONE},
    "cd_bud":    {"rgb": _mix(_WHITE, _TAN, 0.20)},
    "cd_chain":  {"rgb": BONE},
    "cd_chain_d": {"rgb": BONE_D},
    "cd_canopy": {"rgb": _mix(_WHITE, _TAN, 0.16)},
})


def build_candid():
    """Halo, bud berm, beaded colonnade, dendritic roof — in that order, because
    the weight ranges are read off where each stratum starts."""
    global BLEACH_START, CARPET_START
    b = Builder()

    # THE HALO — the bleached flooring, and the palest thing in the piece.
    BLEACH_START = len(b.bm.verts)
    b.card((0, 0, 0.004), (SPAN * 1.72, SPAN * 1.46), "cd_bleach", axis='Z',
           art=BLEACH_ART)

    # THE BERM — a low mound of buds with real height. It was a zero-thickness
    # ground card, so the colony stood ON a decal rather than IN a mass, and the
    # scalloped outline the sheet's silhouette panel is mostly made of did not
    # exist at all. One swept dome carries the body; a ring of buds around its rim
    # carries the scallop, which is silhouette and therefore has to be geometry.
    # NOTHING HERE IS MACHINED. There is not one straight edge, flat cap or cut
    # groove anywhere on this creature's sheets, and the first rebuild gave it all
    # three: a thirteen-sided outline that read as facets, a mid-station that read
    # as a turned groove, and flat-topped hexagonal cylinders standing in for
    # buds. A yeast colony is round things piled on round things.
    # THERE IS NO PLATE. The swept dome under the buds was itself the machined
    # pedestal the audit kept finding: a turned rim, a stepped flange and
    # concentric incised lines, none of which exist anywhere on either sheet. Both
    # put the bud mass DIRECTLY on the flat ragged crust, and the columns rise out
    # of that mass rather than terminating on a plate — the load path is crust ->
    # buds -> columns -> canopy, and a plate breaks it in the middle.
    #
    # So the buds ARE the mound. Removing the dome and leaving them scattered on
    # top of it would have left the colony flat; they have to pile.
    CARPET_START = len(b.bm.verts)
    # A FIELD OF BUDS, NOT A RING OF THEM. The sheet packs them across the whole
    # footprint two and three deep — the deck it leaves is never bare, and the
    # colonnade rises THROUGH the field rather than standing on an empty plate.
    # Ringing the rim alone scallops the outline and leaves a plaza behind it.
    _bud = 0
    for band, (frac, count, scale) in enumerate((
            (0.985, RIM_BUDS, 0.94),      # the rim: this band carries the scallop
            (0.865, 20, 1.00),
            (0.735, 18, 1.00),
            (0.600, 15, 0.98),
            (0.460, 12, 0.94),
            (0.315, 9, 0.90),
            (0.165, 5, 0.86))):
        for k in range(count):
            _bud += 1
            a = math.tau * k / count + 0.3 + band * 0.7
            rr = SPAN * 0.445 * frac * (1.0 + 0.050 * (((k * 5) % 3) - 1))
            bx, by = math.sin(a) * rr, math.cos(a) * rr * 0.86
            # THE BUDS PILE. The mound's height is the depth of the bed, not a
            # dome beneath it, so each station carries two or three stacked and
            # the whole heap swells toward the middle the way the sheet's does.
            crown = BERM_Z * (1.0 - frac * frac) * 1.15
            deep = 2 if frac > 0.90 else 3
            for layer in range(deep):
                jx = bx * (1.0 + 0.035 * (layer - 1))
                jy = by * (1.0 + 0.035 * (layer - 1))
                bz = 0.010 + crown * (layer / float(deep)) + 0.055 * layer
                h = 0.092 * scale * (1.0 - 0.10 * layer)
                s = scale * (1.0 - 0.09 * layer)
                # SIX SIDES AND THREE RINGS. A bud is four or five pixels at
                # gameplay distance, so a nine-sided four-ring sweep spends
                # geometry nothing can resolve — and there are hundreds of them.
                # At nine sides this piece came to 11k verts, several times the
                # heaviest creature in the set, which is a poor trade for a
                # roundness no camera will ever see.
                b.tube([(jx, jy, bz - 0.030 + h * t) for t in (0.0, 0.42, 1.0)],
                       [0.020 * s, 0.058 * s, 0.020 * s], "cd_bud", sides=6)

    # THE COLONNADE — beaded columns, each ONE welded tube whose radius pinches
    # and swells per cell. A column of pearls is not a striped bar: the beading is
    # in the sheet's silhouette, so it belongs to the column's own form and cannot
    # be painted on.
    for k in range(CHAINS):
        px, py = _ring_at(k, CHAINS, SPAN * (0.20 + 0.13 * (k % 3)), 0.4)
        CHAIN_START.append(len(b.bm.verts))
        base = BERM_Z - 0.02
        top = base + 0.20 + 0.035 * (k % 3)
        pts, radii, parts = [], [], []
        rows = BEADS * 2
        for i in range(rows + 1):
            t = i / float(rows)
            pts.append((px, py, base + (top - base) * t))
            radii.append(0.030 if i % 2 == 0 else 0.017)
        for i in range(rows):
            parts.append("cd_chain" if i % 2 == 0 else "cd_chain_d")
        b.tube(pts, radii, parts, sides=6, cap_start=False, cap_end=True)

    # THE ROOF — flat dendritic cards ACROSS the top, not uprights, and reaching
    # past the rim so the colony overhangs its own edge the way the sheet's does.
    for k in range(CANOPY):
        rr = SPAN * (0.10 if k == 0 else (0.26 + 0.12 * (k % 3)))
        px, py = _ring_at(k, CANOPY, rr, 1.2)
        CANOPY_START.append(len(b.bm.verts))
        size = SPAN * (0.62 if k == 0 else 0.46)
        b.card((px, py, BERM_Z + 0.21 + 0.012 * (k % 3)), (size, size),
               "cd_canopy", axis='Z', art=DENDRITE_ART,
               rot=(0.0, 0.0, k * 0.9 + 0.4))
    return b.finish("CandidRigged")


def candid_chains():
    """A bone per stratum, so fire can take them off in the order the roster
    burns them, and one for the colony's own spread."""
    # THE STAIN IS NOT AN ANCESTOR OF THE COLONY. It carries the bleached flooring,
    # which is a record of where the growth has BEEN — that is what makes "bleached
    # flooring is the warning" a warning rather than a health bar. Parented under
    # it, the three strata dragged the stain along with them, and the retreat clip
    # shrank a permanent floor mark every time tending pushed the colony back. The
    # comment beside the weighting always said the stain never moves; the hierarchy
    # quietly said otherwise, and nothing in a render could show the difference.
    chains = [{"prefix": "colony", "points": [(0.0, 0.0, 0.0), (0.0, 0.0, 0.34)]}]
    for name, z in (("carpet", 0.03), ("chain", 0.12), ("canopy", 0.3)):
        chains.append({"prefix": name,
                       "points": [(0.0, 0.0, z), (0.0, 0.0, z + 0.09)]})
    return chains


piece = build_candid()
pl.texture_object(piece, OBJX, px_per_m=96.0, painted_dir=PAINTED)
arm = rig.build_armature("Candid", candid_chains())
rig.bind(piece, arm, kind='ARMATURE_NAME')
# the bleached flooring is the STAIN and never moves with the colony's strata
rig.assign_exclusive_weights(piece, "colony_0", range(BLEACH_START, CARPET_START))
rig.assign_exclusive_weights(piece, "carpet_0", range(CARPET_START, CHAIN_START[0]))
rig.assign_exclusive_weights(piece, "chain_0", range(CHAIN_START[0], CANOPY_START[0]))
rig.assign_exclusive_weights(piece, "canopy_0",
                             range(CANOPY_START[0], len(piece.data.vertices)))

GONE = 0.001
full = {"carpet_0": 1.0, "chain_0": 1.0, "canopy_0": 1.0, "colony_0": 1.0}
# BURN: fire takes the canopy off, then the chains. One layer at a time, in that
# order, which is the whole reason the roster phrases it "down a layer".
rig.clip(arm, "candid_burn_canopy", [
    (0.0, dict(full)),
    (0.6, dict(full, canopy_0=GONE)),
])
rig.clip(arm, "candid_burn_chains", [
    (0.0, dict(full, canopy_0=GONE)),
    (0.6, dict(full, canopy_0=GONE, chain_0=GONE)),
])
# RETREAT: sustained tending outcompetes it, and the colony draws in as a whole
# rather than losing a stratum.
# The strata draw in TOGETHER, named one by one now that none of them hangs off
# the stain. colony_0 holds its extent through the retreat, which is the point.
rig.clip(arm, "candid_retreat", [
    (0.0, dict(full)),
    (2.2, dict(full, carpet_0=0.55, chain_0=0.55, canopy_0=0.55)),
])
# REGROW: unattended, it comes back up through its strata in the same order.
rig.clip(arm, "candid_regrow", [
    (0.0, dict(full, canopy_0=GONE, chain_0=GONE)),
    (1.1, dict(full, canopy_0=GONE)),
    (2.2, dict(full)),
])
rig.park(arm, dict(full))

report = rig.validate(piece, arm)
print("[RIG] Candid %s bones=%d dead=%s orphans=%d"
      % (report["verdict"], report["bones"],
         report["dead_bones"] or "none", report["orphan_verts"]))
if report["verdict"] != "PASS":
    raise SystemExit("candid rig does not deform: %s" % report["problems"])

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "candid.blend"))
rig.export_rigged_gltf([piece, arm], GLTF)
print("=== DONE: candid -> %s ===" % GLTF)
