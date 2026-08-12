"""Rig the Sapscrap v2: merged body -> REGION weights, and the crouch-jump
attack cycle.

The shell mesh now CONTAINS the limb and horn sleeves (boolean-unioned), so it
cannot take a single bone. Each vertex is classified by region: inside a limb
capsule AND outside the body ellipsoid -> that arm's bone; likewise the horn;
everything else -> the body bone. Still rigid 1.0 weights per vertex.

Attack cycle (the gameplay states, poses CHAIN so the runtime can sequence
them without pops):
  Idle   = camp loop (breath, claw knead, horn sway)
  Windup = TELEGRAPH: all three limbs retract against the body, the mass
           squashes down and leans back; ends HELD in the crouch.
  Lunge  = STRIKE: from the crouch it JUMPS forward - airborne stretch, limbs
           swinging forward - and lands extended; ends held.
  Bite   = SEIZE + RECOVER: from the landed pose the maw chews twice, then
           everything returns to rest.

World-space intent is converted through each bone's rest matrix instead of
hand-guessed local values (roll conventions flipped signs on the Ferrule).
Blender space here: +y rearward, maw faces -y, +z up.
"""
import bpy
import math
from mathutils import Vector

RIG = "Sapscrap_Rig"
ROOT = "SapscrapRoot"
FPS = 24
# THE BODY IS THE ONE SOURCE OF ITS OWN SHAPE. This file used to restate H,
# SHELL_R, on_shell and every limb endpoint, so moving a nub in the builder left
# the bones pointing at where the nub had been — the claws would have animated
# off geometry that was no longer under them. Import instead, and the two cannot
# drift apart.
import sys as _sys
import os as _os
_SAP_DIR = _os.path.dirname(_os.path.abspath(__file__))
if _SAP_DIR not in _sys.path:
    _sys.path.insert(0, _SAP_DIR)
import build_sapscrap as _B

H = _B.H
SHELL_R = _B.SHELL_R
on_shell = _B.on_shell

LIMB_BASE_P = {s: Vector(_B.LIMB_BASE(s)) for s in (-1.0, 1.0)}
LIMB_TIP = {s: Vector(_B.LIMB_TIP(s)) for s in (-1.0, 1.0)}
HORN_BASE_P = Vector(_B.on_shell(*_B.HORN_BASE, sink=0.10))
HORN_TIP = Vector(_B.HORN_TIP)


def _claw_end(kind, tip):
    """Where the claw on this nub finishes — read off the claw's own steps, so a
    hand bone always spans the claw it drives."""
    dx, dy, dz = _B.claw_reach(kind)
    return (tip.x + dx, tip.y + dy, tip.z + dz)

BONES = [
    ("Sapscrap_Anchor",       None,                  (0.0, 0.25, 0.02), (0.0, 0.05, 0.02)),
    # the body bone is WORLD-VERTICAL so its pose scale maps to world axes
    # (local Y = along bone = world Z): a diagonal pose scale on a tilted
    # bone squashes along the tilt and the crouch barely reads.
    ("Sapscrap_Bone_Body",    "Sapscrap_Anchor",     (0.0, 0.05, 0.02), (0.0, 0.05, 0.42)),
    ("Sapscrap_Bone_Mouth",   "Sapscrap_Bone_Body",  (0.0, -0.25, 0.41), (0.0, -0.48, 0.41)),
    ("Sapscrap_Bone_Arm_L",   "Sapscrap_Bone_Body",  tuple(LIMB_BASE_P[-1.0]), tuple(LIMB_TIP[-1.0])),
    ("Sapscrap_Bone_Hand_L",  "Sapscrap_Bone_Arm_L", tuple(LIMB_TIP[-1.0]), _claw_end(-1.0, LIMB_TIP[-1.0])),
    ("Sapscrap_Bone_Arm_R",   "Sapscrap_Bone_Body",  tuple(LIMB_BASE_P[1.0]), tuple(LIMB_TIP[1.0])),
    ("Sapscrap_Bone_Hand_R",  "Sapscrap_Bone_Arm_R", tuple(LIMB_TIP[1.0]), _claw_end(1.0, LIMB_TIP[1.0])),
    ("Sapscrap_Bone_Horn",    "Sapscrap_Bone_Body",  tuple(HORN_BASE_P), tuple(HORN_TIP)),
    ("Sapscrap_Bone_HornClaw", "Sapscrap_Bone_Horn", tuple(HORN_TIP), _claw_end("horn", HORN_TIP)),
]

BIND = {
    "Sapscrap_Mouth_Ring": "Sapscrap_Bone_Mouth",
    "Sapscrap_Teeth": "Sapscrap_Bone_Mouth",
    "Sapscrap_MouthVoid": "Sapscrap_Bone_Mouth",
}



def t_eff(co):
    """Effective ellipsoid parameter of the DEFORMED shell (with its bulge);
    > ~1.0 means the vertex sits outside the body proper (i.e. on a sleeve)."""
    cz = SHELL_R[2] * H
    top = cz * 2.0
    t = max(0.0, min(1.0, co.z / top))
    bulge = 1.0 + 0.13 * math.exp(-((t - 0.40) / 0.26) ** 2) - 0.11 * (t ** 2)
    dx = co.x / (SHELL_R[0] * H * bulge)
    dy = co.y / (SHELL_R[1] * H * bulge)
    dz = (co.z - cz) / (SHELL_R[2] * H)
    return (dx * dx + dy * dy + dz * dz) ** 0.5


def near_capsule(co, a, b, radius):
    ab = b - a
    t = max(0.0, min(1.3, (co - a).dot(ab) / ab.length_squared))
    return (co - (a + ab * t)).length <= radius


ARMS = ["Sapscrap_Bone_Arm_L", "Sapscrap_Bone_Arm_R"]
HANDS = ["Sapscrap_Bone_Hand_L", "Sapscrap_Bone_Hand_R"]
LIMB_LEAVES = ARMS + ["Sapscrap_Bone_Horn"]

# Where each claw finishes, from the claw's own step table. The claws are part of
# the shell now, so the hand bones have to find them by POSITION -- there is no
# separate object left to bind by name.
CLAW_END = {s: Vector(_claw_end(s, LIMB_TIP[s])) for s in (-1.0, 1.0)}
HORN_CLAW_END = Vector(_claw_end("horn", HORN_TIP))


def shell_region(co):
    if t_eff(co) > 0.97:
        # the claw first: it lies BEYOND the sleeve tip, and it belongs to the
        # hand bone rather than the arm that carries it
        for s in (-1.0, 1.0):
            if near_capsule(co, LIMB_TIP[s], CLAW_END[s], 0.13):
                return HANDS[0] if s < 0 else HANDS[1]
        if near_capsule(co, HORN_TIP, HORN_CLAW_END, 0.12):
            return "Sapscrap_Bone_HornClaw"
        for s in (-1.0, 1.0):
            if near_capsule(co, LIMB_BASE_P[s], LIMB_TIP[s], 0.17):
                return ARMS[0] if s < 0 else ARMS[1]
        if near_capsule(co, HORN_BASE_P, HORN_TIP, 0.15):
            return "Sapscrap_Bone_Horn"
    return "Sapscrap_Bone_Body"


def build_rig():
    scene = bpy.context.scene
    scene.render.fps = FPS
    root = bpy.data.objects[ROOT]
    coll = root.users_collection[0]
    meshes = [o for o in coll.objects if o.type == "MESH"]

    # idempotent: purge any previous rig + its actions, so re-authoring
    # poses does NOT require a full scene rebuild (a second run used to
    # create Rig.001 and orphan the renderer)
    for o in list(bpy.data.objects):
        if o.type == "ARMATURE" and o.name.startswith(RIG):
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.armatures):
        if a.users == 0:
            bpy.data.armatures.remove(a)
    for act in list(bpy.data.actions):
        if act.name.startswith('Sapscrap_'):
            act.use_fake_user = False
            if act.users == 0:
                bpy.data.actions.remove(act)

    for o in meshes:
        off = Vector(o.location)
        if off.length > 1e-9:
            for v in o.data.vertices:
                v.co = v.co + off
            o.location = (0.0, 0.0, 0.0)
        o.data.update()

    arm_data = bpy.data.armatures.new(RIG)
    rig = bpy.data.objects.new(RIG, arm_data)
    coll.objects.link(rig)
    rig.parent = root
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    made = {}
    for name, parent, hd, tl in BONES:
        b = eb.new(name)
        b.head = hd
        b.tail = tl
        if parent:
            b.parent = made[parent]
            b.use_connect = False
        made[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")

    region_counts = {}
    unbound = []
    for o in meshes:
        o.vertex_groups.clear()
        if o.name == "Sapscrap_Segment_Shell":
            groups = {}
            for i, v in enumerate(o.data.vertices):
                bone = shell_region(v.co)
                groups.setdefault(bone, []).append(i)
            for bone, ids in groups.items():
                vg = o.vertex_groups.new(name=bone)
                vg.add(ids, 1.0, "REPLACE")
                region_counts[bone] = len(ids)
        else:
            bone = BIND.get(o.name)
            if bone is None:
                unbound.append(o.name)
                continue
            vg = o.vertex_groups.new(name=bone)
            vg.add(range(len(o.data.vertices)), 1.0, "REPLACE")
        o.parent = rig
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                o.modifiers.remove(m)
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    if unbound:
        raise RuntimeError("unbound meshes: %s" % unbound)
    for bone in ARMS:
        if region_counts.get(bone, 0) < 20:
            raise RuntimeError("region weighting caught only %d verts for %s"
                               % (region_counts.get(bone, 0), bone))
    if region_counts.get("Sapscrap_Bone_Horn", 0) < 12:
        raise RuntimeError("horn region caught only %d verts"
                           % region_counts.get("Sapscrap_Bone_Horn", 0))
    return rig, region_counts


# ---- pose authoring through rest matrices --------------------------------

def key(pb, frame, loc=None, rot=None, scale=None):
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)
    if rot is not None:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = rot
        pb.keyframe_insert("rotation_euler", frame=frame)
    if scale is not None:
        pb.scale = scale
        pb.keyframe_insert("scale", frame=frame)


def R(x=0.0, y=0.0, z=0.0):
    return (math.radians(x), math.radians(y), math.radians(z))


def clear_pose(rig):
    for pb in rig.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def new_action(rig, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots):
        rig.animation_data.action_slot = act.slots[0]
    return act


def local_loc(pb, world_v):
    """Armature-space direction -> this bone's pose-location vector."""
    M = pb.bone.matrix_local.to_3x3()
    return tuple(M.inverted() @ Vector(world_v))


def rotx_sign(pb, world_dir):
    """Sign of pose rot-x that moves the bone TIP along world_dir."""
    M = pb.bone.matrix_local.to_3x3()
    ax = M @ Vector((1.0, 0.0, 0.0))
    r = Vector(pb.bone.tail_local) - Vector(pb.bone.head_local)
    return 1.0 if ax.cross(r).dot(Vector(world_dir)) > 0.0 else -1.0


def pose_named(P, table, frame, blend=1.0, lag=None):
    """Apply a named pose table {bone: (world_loc, tipdir, deg, scale)}.
    `lag` ({bone: +frames}) staggers arrivals so the body leads and the
    limbs follow - simultaneous arrival on every bone reads as a machine
    snapping between poses, not a mass moving."""
    for bn, (wloc, tipdir, deg, scl) in table.items():
        pb = P[bn]
        f = frame + (lag.get(bn, 0) if lag else 0)
        loc = None
        if wloc is not None:
            loc = tuple(c * blend for c in local_loc(pb, wloc))
        rot = None
        if tipdir is not None and deg:
            sgn = rotx_sign(pb, tipdir)
            rot = R(x=sgn * deg * blend)
        scale = None
        if scl is not None:
            scale = tuple(1.0 + (c - 1.0) * blend for c in scl)
        key(pb, f, loc=loc, rot=rot, scale=scale)


# the body leads every move; jaws, arms, then claws trail behind it
LAG_TRAIL = {
    "Sapscrap_Bone_Body": 0,
    "Sapscrap_Bone_Mouth": 1,
    "Sapscrap_Bone_Arm_L": 2,
    "Sapscrap_Bone_Arm_R": 2,
    "Sapscrap_Bone_Hand_L": 4,
    "Sapscrap_Bone_Hand_R": 4,
    "Sapscrap_Bone_Horn": 3,
    "Sapscrap_Bone_HornClaw": 5,
}


def make_tables():
    """CROUCH = windup's end / lunge's start. LANDED = lunge's end / bite's
    start. tipdir is the WORLD direction the bone tip should move."""
    CROUCH = {
        # squash down + shuffle back + lean back (nose swings up)
        "Sapscrap_Bone_Body":   ((0.0, 0.11, -0.045), (0.0, 0.90, 0.20), 9.0,
                                 (1.10, 0.78, 1.10)),
        # all three limbs retract against the body
        "Sapscrap_Bone_Arm_L":  (None, (0.0, 0.65, 0.76), 34.0, None),
        "Sapscrap_Bone_Arm_R":  (None, (0.0, 0.65, 0.76), 34.0, None),
        "Sapscrap_Bone_Hand_L": (None, (0.0, 0.80, 0.60), 26.0, None),
        "Sapscrap_Bone_Hand_R": (None, (0.0, 0.80, 0.60), 26.0, None),
        "Sapscrap_Bone_Horn":   (None, (0.0, 0.70, -0.71), 24.0, None),
        "Sapscrap_Bone_HornClaw": (None, (0.0, 0.60, -0.80), 18.0, None),
        # maw puckers shut in the crouch
        "Sapscrap_Bone_Mouth":  ((0.0, 0.030, 0.0), None, 0.0, None),
    }
    LANDED = {
        # landed forward of rest, mass stretched back out
        "Sapscrap_Bone_Body":   ((0.0, -0.15, 0.01), (0.0, -0.95, -0.30), 4.0,
                                 (0.98, 1.03, 0.98)),
        # limbs swung FORWARD past rest, claws splayed at the target
        "Sapscrap_Bone_Arm_L":  (None, (0.0, -0.80, -0.45), 24.0, None),
        "Sapscrap_Bone_Arm_R":  (None, (0.0, -0.80, -0.45), 24.0, None),
        "Sapscrap_Bone_Hand_L": (None, (0.0, -0.85, -0.40), 18.0, None),
        "Sapscrap_Bone_Hand_R": (None, (0.0, -0.85, -0.40), 18.0, None),
        # the forward-facing horn STABS forward-down at the target
        "Sapscrap_Bone_Horn":   (None, (0.0, -0.72, -0.69), 16.0, None),
        "Sapscrap_Bone_HornClaw": (None, (0.0, -0.78, -0.63), 13.0, None),
        # maw driven at the target
        "Sapscrap_Bone_Mouth":  ((0.0, -0.055, 0.0), None, 0.0, None),
    }
    return CROUCH, LANDED


def author(rig):
    if rig.animation_data is None:
        rig.animation_data_create()
    P = rig.pose.bones
    CROUCH, LANDED = make_tables()
    made = []

    # ---- Idle (64f loop): breath, claw knead, horn sway ------------------
    clear_pose(rig)
    new_action(rig, "Sapscrap_Idle")
    body = P["Sapscrap_Bone_Body"]
    # asymmetric breath: quick inhale, long exhale - a symmetric sine reads
    # like a metronome, not a lung
    for f, s in ((1, 0.0), (12, 1.0), (34, 0.0), (50, -0.7), (64, 0.0)):
        key(body, f, loc=tuple(c * s for c in local_loc(body, (0.0, 0.008, 0.0))),
            scale=(1.0 + 0.010 * s, 1.0 - 0.012 * s, 1.0 + 0.010 * s))
    # phase-offset limb cycles are SAMPLED as sines across the whole loop
    # (including a key one period past the end) - wrapping key POSITIONS with
    # a modulo leaves the F-curve clamped at the boundary, so the loop
    # popped at the seam every 2.6s
    def loop_sine(pb, amp_x, ph, amp_z=0.0, sgn=1.0):
        for f in range(1, 66, 8):
            s = math.sin(2.0 * math.pi * ((f - 1 - ph) % 64) / 64.0)
            key(pb, f, rot=(math.radians(sgn * amp_x * s), 0.0,
                            math.radians(amp_z * s)))
    for bn, ph in ((ARMS[0], 0), (ARMS[1], 24)):
        loop_sine(P[bn], 3.0, ph, sgn=rotx_sign(P[bn], (0.0, 0.5, 0.85)))
    for bn, ph in ((HANDS[0], 8), (HANDS[1], 32)):
        loop_sine(P[bn], 4.5, ph, sgn=rotx_sign(P[bn], (0.0, 0.6, 0.8)))
    hc = P["Sapscrap_Bone_HornClaw"]
    loop_sine(hc, 6.0, 8, amp_z=3.0, sgn=rotx_sign(hc, (0.0, 0.6, -0.8)))
    for f, s in ((1, 0.0), (28, 1.0), (56, 0.0), (64, 0.0)):
        key(P["Sapscrap_Bone_Mouth"], f,
            loc=tuple(c * s for c in local_loc(P["Sapscrap_Bone_Mouth"], (0.0, 0.006, 0.0))))
    made.append("Sapscrap_Idle")

    # ---- Windup = TELEGRAPH (18f): the limbs FLARE a beat, then the mass
    # sinks back - ROCKING onto one flank and recentring as it shuffles -
    # while each limb retracts with its OWN character: the left arm one
    # smooth fold, the right arm a two-stage stutter pull, the horn folding
    # past its mark and settling. The held crouch takes one slow breath.
    clear_pose(rig)
    new_action(rig, "Sapscrap_Windup")
    pose_named(P, CROUCH, 1, blend=0.0)
    for bn in ARMS + HANDS:
        pb = P[bn]
        key(pb, 3, rot=R(x=rotx_sign(pb, LANDED[bn][1]) * 5.0))  # anticipation flare
    # THE SIDE ROCK: a sphere's silhouette is invariant under rotation about
    # its centre, so the rock is sold through the channels that actually
    # project at this camera - the dark MAW DISC sweeping (big yaw), the
    # shell decals rotating (big roll), and a real weight-shift translation
    # with an alternating dip. Keys sit between the pose passes (f9/f12
    # zero the yaw/roll and recentre the shuffle for free).
    body = P["Sapscrap_Bone_Body"]
    bsgn = rotx_sign(body, CROUCH["Sapscrap_Bone_Body"][1])
    bdeg = CROUCH["Sapscrap_Bone_Body"][2]
    bwloc = CROUCH["Sapscrap_Bone_Body"][0]

    def rock_key(f, frac, yaw, roll, sway, dip):
        base = local_loc(body, (bwloc[0] * frac + sway,
                                bwloc[1] * frac, bwloc[2] * frac + dip))
        key(body, f, loc=base,
            rot=(math.radians(bsgn * bdeg * frac), math.radians(yaw),
                 math.radians(roll)))

    rock_key(4, 0.30, 9.0, -10.0, 0.040, -0.012)   # onto the right flank
    rock_key(7, 0.65, -6.0, 6.5, -0.026, -0.008)   # across to the left
    rock_key(10, 0.95, 2.5, -2.5, 0.012, -0.003)   # a last small sway
    pose_named(P, CROUCH, 9, blend=0.90, lag=LAG_TRAIL)   # body sinks first
    pose_named(P, CROUCH, 12, blend=1.0, lag=LAG_TRAIL)   # limbs fold in behind
    # per-limb retract characters, layered between the pose passes
    aL, aR = P[ARMS[0]], P[ARMS[1]]
    key(aL, 7, rot=R(x=rotx_sign(aL, CROUCH[ARMS[0]][1]) * CROUCH[ARMS[0]][2] * 0.75))
    csR = rotx_sign(aR, CROUCH[ARMS[1]][1]) * CROUCH[ARMS[1]][2]
    key(aR, 6, rot=R(x=csR * 0.55))
    key(aR, 8, rot=R(x=csR * 0.62))               # the pause in the stutter
    # the horn's character is a DELAYED SNAP. Its flare must aim UP (the
    # generic flare uses the LANDED direction, which for the forward-facing
    # horn points DOWN and read as the fold starting at frame 1): it rears
    # skyward and HOLDS while the arms fold, then whips in over three
    # frames with a big fold-past and a visible comeback.
    horn = P["Sapscrap_Bone_Horn"]
    hc_s = rotx_sign(horn, CROUCH["Sapscrap_Bone_Horn"][1])
    hc_d = CROUCH["Sapscrap_Bone_Horn"][2]
    up_h = rotx_sign(horn, (0.0, -0.30, 0.95))
    key(horn, 3, rot=R(x=up_h * 6.0))
    key(horn, 8, rot=R(x=up_h * 7.0))             # still reared while arms fold
    key(horn, 10, rot=R(x=hc_s * hc_d * 0.45))
    key(horn, 13, rot=R(x=hc_s * hc_d * 1.30))    # folds well past its mark...
    hclaw = P["Sapscrap_Bone_HornClaw"]
    up_c = rotx_sign(hclaw, (0.0, -0.30, 0.95))
    key(hclaw, 3, rot=R(x=up_c * 4.0))
    key(hclaw, 9, rot=R(x=up_c * 4.5))
    key(hclaw, 12, rot=R(x=rotx_sign(hclaw, CROUCH["Sapscrap_Bone_HornClaw"][1])
                         * CROUCH["Sapscrap_Bone_HornClaw"][2] * 0.5))
    key(hclaw, 14, rot=R(x=rotx_sign(hclaw, CROUCH["Sapscrap_Bone_HornClaw"][1])
                         * CROUCH["Sapscrap_Bone_HornClaw"][2] * 1.35))
    key(P["Sapscrap_Bone_Body"], 15, scale=(1.082, 0.805, 1.082))   # inhale...
    pose_named(P, CROUCH, 18, blend=1.0)          # ...held exact: lunge starts here
    made.append("Sapscrap_Windup")

    # ---- Lunge = STRIKE (18f): fast launch, the mass stretches along the
    # arc while the limbs trail, hard landing squash -> rebound -> settle,
    # claws whipping through past the target and coming back.
    clear_pose(rig)
    new_action(rig, "Sapscrap_Lunge")
    pose_named(P, CROUCH, 1, blend=1.0)
    pose_named(P, CROUCH, 3, blend=1.08)          # dig deeper
    body = P["Sapscrap_Bone_Body"]
    lb = LANDED["Sapscrap_Bone_Body"]
    fwd = rotx_sign(body, (0.0, -0.95, -0.30))
    # the rise is a PARABOLA that keeps travelling forward: leg-drive f4,
    # motion-stretched climb f5, apex f7 (still moving), accelerating fall f9
    key(body, 4, loc=local_loc(body, (0.0, -0.015, 0.045)),
        rot=R(x=fwd * 1.5), scale=(0.99, 1.02, 0.99))
    key(body, 5, loc=local_loc(body, (0.0, -0.040, 0.125)),
        rot=R(x=fwd * 3.0), scale=(0.94, 1.13, 0.94))
    key(body, 7, loc=local_loc(body, (0.0, -0.085, 0.165)),
        rot=R(x=fwd * 3.0), scale=(0.95, 1.10, 0.95))
    key(body, 9, loc=local_loc(body, (0.0, -0.130, 0.055)),
        scale=(0.99, 1.04, 0.99))
    # impact f10: a real squash HELD a frame, a visible rebound, and a
    # diminishing settle instead of a one-frame stop
    key(body, 10, loc=tuple(c for c in local_loc(body, lb[0])),
        rot=R(x=rotx_sign(body, lb[1]) * lb[2]), scale=(1.10, 0.86, 1.10))
    key(body, 11, scale=(1.08, 0.88, 1.08))
    key(body, 13, scale=(0.965, 1.075, 0.965))
    key(body, 15, scale=(1.006, 0.995, 1.006))
    key(body, 17, scale=lb[3])
    # claws stay FOLDED through the flight, then SNAP forward - the whole
    # crouch-to-overshoot sweep lands in two frames (director: snappier) -
    # staggered left-leads-right, hands after arms, decaying to the set
    for bn in ARMS + HANDS:
        pb = P[bn]
        cs = rotx_sign(pb, CROUCH[bn][1])
        ls = rotx_sign(pb, LANDED[bn][1])
        c_deg, l_deg = CROUCH[bn][2], LANDED[bn][2]
        trail = (0 if bn in ARMS else 2) + (0 if bn.endswith("_L") else 1)
        key(pb, 6 + trail, rot=R(x=cs * c_deg * 0.85))    # still folded aloft
        key(pb, 9 + trail, rot=R(x=cs * c_deg * 0.55))    # barely unwinding
        key(pb, 11 + trail, rot=R(x=ls * l_deg * 1.25))   # SNAP through
        key(pb, 13 + trail, rot=R(x=ls * l_deg * 0.90))   # recover...
        key(pb, 15 + trail, rot=R(x=ls * l_deg))          # ...and set
    # the forward horn holds its fold, then STABS with the same snap and
    # decays over the settle
    for bn in ("Sapscrap_Bone_Horn", "Sapscrap_Bone_HornClaw"):
        pb = P[bn]
        ls = rotx_sign(pb, LANDED[bn][1])
        key(pb, 6, rot=R(x=rotx_sign(pb, CROUCH[bn][1]) * CROUCH[bn][2] * 0.8))
        key(pb, 9, rot=R(x=rotx_sign(pb, CROUCH[bn][1]) * CROUCH[bn][2] * 0.5))
        key(pb, 11, rot=R(x=ls * LANDED[bn][2] * 1.30))
        key(pb, 13, rot=R(x=ls * LANDED[bn][2] * 0.88))
        key(pb, 15, rot=R(x=ls * LANDED[bn][2] * 1.05))
        key(pb, 17, rot=R(x=ls * LANDED[bn][2]))
    m = P["Sapscrap_Bone_Mouth"]
    key(m, 1, loc=local_loc(m, (0.0, 0.030, 0.0)))
    key(m, 7, loc=local_loc(m, (0.0, -0.020, 0.0)))
    key(m, 11, loc=local_loc(m, (0.0, -0.068, 0.0)))      # jaws lead the arrival
    key(m, 13, loc=local_loc(m, (0.0, -0.050, 0.0)))
    key(m, 15, loc=local_loc(m, (0.0, -0.058, 0.0)))
    pose_named(P, LANDED, 18, blend=1.0)          # held exact: bite takes over
    made.append("Sapscrap_Lunge")

    # ---- Bite = SEIZE + RECOVER (22f): two chews with the mass rocking
    # into each one a beat behind the jaws, then a staggered release - jaws
    # first, body next, limbs last.
    clear_pose(rig)
    new_action(rig, "Sapscrap_Bite")
    pose_named(P, LANDED, 1, blend=1.0)
    m = P["Sapscrap_Bone_Mouth"]
    body = P["Sapscrap_Bone_Body"]
    lb = LANDED["Sapscrap_Bone_Body"]
    key(body, 2, scale=(1.008, 0.99, 1.008))       # residual landing settle
    for f0 in (3, 10):                             # two chews that SNAP shut
        # still three-quarters open one frame out, contact at peak speed,
        # a held contact frame, then a slower re-open than the close
        key(m, f0, loc=local_loc(m, (0.0, -0.042, 0.0)))
        key(m, f0 + 1, loc=local_loc(m, (0.0, -0.118, 0.0)))
        key(m, f0 + 2, loc=local_loc(m, (0.0, -0.112, 0.0)))
        key(m, f0 + 5, loc=local_loc(m, (0.0, -0.030, 0.0)))
        # the mass jolts WITH the clench, not a beat later
        key(body, f0 + 1, loc=local_loc(body, (0.0, lb[0][1] - 0.030,
                                               lb[0][2] - 0.010)),
            scale=(1.012, 1.015, 1.012))
        key(body, f0 + 4, loc=local_loc(body, lb[0]), scale=lb[3])
    for bn, sgn in ((ARMS[0], 1.0), (ARMS[1], -1.0)):
        pb = P[bn]
        base = rotx_sign(pb, LANDED[bn][1]) * LANDED[bn][2]
        key(pb, 5, rot=(math.radians(base * 1.12), 0.0, math.radians(5.0 * sgn)))
        key(pb, 12, rot=(math.radians(base * 0.92), 0.0, math.radians(3.0 * sgn)))
    # release wave, never faster than a chew: jaws ease off, the mass rocks
    # back, limbs unfold last with a trailing drift into the rest pose
    key(m, 15, loc=local_loc(m, (0.0, -0.030, 0.0)))
    key(m, 18, loc=local_loc(m, (0.0, -0.008, 0.0)))
    key(m, 20, loc=(0.0, 0.0, 0.0))
    key(body, 17, loc=tuple(c * 0.45 for c in local_loc(body, lb[0])),
        scale=tuple(1.0 + (c - 1.0) * 0.45 for c in lb[3]))
    key(body, 20, loc=(0.0, 0.0, 0.0), rot=R(), scale=(1.0, 1.0, 1.0))
    for bn in ARMS:
        pb = P[bn]
        key(pb, 16, rot=R(x=rotx_sign(pb, LANDED[bn][1]) * LANDED[bn][2] * 0.55))
        key(pb, 19, rot=R())
    for bn in HANDS + ["Sapscrap_Bone_Horn", "Sapscrap_Bone_HornClaw"]:
        pb = P[bn]
        key(pb, 17, rot=R(x=rotx_sign(pb, LANDED[bn][1]) * LANDED[bn][2] * 0.5))
        key(pb, 20, rot=R(x=rotx_sign(pb, LANDED[bn][1]) * LANDED[bn][2] * 0.06))
    pose_named(P, LANDED, 22, blend=0.0)           # exact rest
    made.append("Sapscrap_Bite")

    clear_pose(rig)
    rig.animation_data.action = None
    return made


rig, region_counts = build_rig()
actions = author(rig)
bpy.context.view_layer.update()
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
result = {
    "bones": len(rig.data.bones),
    "actions": actions,
    "meshes": len(meshes),
    "region_counts": region_counts,
    "fully_weighted": all(len(o.vertex_groups) >= 1 for o in meshes),
}
