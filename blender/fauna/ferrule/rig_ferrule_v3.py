"""Rig Ferrule v3: one bone per section, rigid full-weight binds, four actions.

Skeleton philosophy (the reusable pattern):
  - Every mesh SECTION gets its own bone; every vertex of that section is
    painted to that bone at weight 1.0. Stone plates never deform - they
    articulate at seams - so rigid binds are correct, cheap, and replay-safe.
  - The spine chain follows the SURVEYED arch, so each bone's local +Y runs
    along the body curve: translating on +Y telescopes the body (the slinky),
    which keeps per-bone rotations tiny. Rotation compounds down a chain;
    translation does not.
  - Leaf bones (mouth, jaws, tail tip, hands) rotate freely - nothing inherits
    from them, so that is where the expressive swing lives.
"""
import bpy
import math
from mathutils import Vector

RIG = "Ferrule_Rig"
ROOT = "FerruleRoot"
FPS = 24
H = 1.55

# --------------------------------------------------------------- the skeleton
# (name, parent, head(x rearward, y up), tail(x, y)) in survey units.
BONES = [
    ("Ferrule_Anchor",        None,                    (2.150, 0.330), (1.804, 0.331)),
    ("Ferrule_Bone_Rear",     "Ferrule_Anchor",        (1.804, 0.331), (1.550, 0.286)),
    ("Ferrule_Bone_Haunch",   "Ferrule_Bone_Rear",     (1.550, 0.286), (1.330, 0.705)),
    ("Ferrule_Bone_ArchFall", "Ferrule_Bone_Haunch",   (1.330, 0.705), (0.993, 0.852)),
    ("Ferrule_Bone_ArchApex", "Ferrule_Bone_ArchFall", (0.993, 0.852), (0.684, 0.679)),
    ("Ferrule_Bone_ArchRise", "Ferrule_Bone_ArchApex", (0.684, 0.679), (0.435, 0.480)),
    ("Ferrule_Bone_Neck",     "Ferrule_Bone_ArchRise", (0.580, 0.575), (0.435, 0.480)),
    ("Ferrule_Bone_Head",     "Ferrule_Bone_Neck",     (0.435, 0.480), (0.280, 0.230)),
    ("Ferrule_Bone_Mouth",    "Ferrule_Bone_Head",     (0.280, 0.230), (0.130, 0.170)),
    ("Ferrule_Bone_Jaw_F",    "Ferrule_Bone_ArchRise", (0.844, 0.660), (0.789, 0.372)),
    ("Ferrule_Bone_Jaw_R",    "Ferrule_Bone_ArchFall", (1.133, 0.670), (1.188, 0.382)),
    ("Ferrule_Bone_Arm_L",    "Ferrule_Bone_ArchRise", (0.600, 0.500), (0.512, 0.408)),
    ("Ferrule_Bone_Hand_L",   "Ferrule_Bone_Arm_L",    (0.512, 0.408), (0.470, 0.360)),
    ("Ferrule_Bone_Arm_R",    "Ferrule_Bone_ArchRise", (0.600, 0.500), (0.512, 0.408)),
    ("Ferrule_Bone_Hand_R",   "Ferrule_Bone_Arm_R",    (0.512, 0.408), (0.470, 0.360)),
    ("Ferrule_Bone_Tail_01",  "Ferrule_Bone_Rear",     (2.115, 0.300), (2.245, 0.260)),
    ("Ferrule_Bone_Tail_02",  "Ferrule_Bone_Tail_01",  (2.245, 0.260), (2.355, 0.215)),
    ("Ferrule_Bone_Tail_03",  "Ferrule_Bone_Tail_02",  (2.355, 0.215), (2.470, 0.165)),
]
SIDE_X = {"Ferrule_Bone_Arm_L": -0.258, "Ferrule_Bone_Hand_L": -0.275,
          "Ferrule_Bone_Arm_R": 0.258, "Ferrule_Bone_Hand_R": 0.275}

# --------------------------------------------------- section -> bone painting
BIND = {
    "Ferrule_RearAnchor": "Ferrule_Bone_Rear",
    "Ferrule_Haunch": "Ferrule_Bone_Haunch",
    "Ferrule_Segment_ArchFall": "Ferrule_Bone_ArchFall",
    "Ferrule_Segment_ArchApex": "Ferrule_Bone_ArchApex",
    "Ferrule_Segment_ArchRise": "Ferrule_Bone_ArchRise",
    "Ferrule_Neck": "Ferrule_Bone_Neck",
    "Ferrule_HeadCrest": "Ferrule_Bone_Head",
    "Ferrule_HeadBase": "Ferrule_Bone_Head",
    "Ferrule_HeadPad_F": "Ferrule_Bone_Head",
    "Ferrule_HeadPad_R": "Ferrule_Bone_Head",
    "Ferrule_Mouth": "Ferrule_Bone_Mouth",
    "Ferrule_SignalTeeth": "Ferrule_Bone_Mouth",
    "Ferrule_MouthVoid": "Ferrule_Bone_Mouth",
    "Ferrule_Jaw_F": "Ferrule_Bone_Jaw_F",
    "Ferrule_Jaw_F_SignalTip": "Ferrule_Bone_Jaw_F",
    "Ferrule_Jaw_R": "Ferrule_Bone_Jaw_R",
    "Ferrule_Jaw_R_SignalTip": "Ferrule_Bone_Jaw_R",
    "Ferrule_Arm_L": "Ferrule_Bone_Arm_L",
    "Ferrule_Arm_L_Hand": "Ferrule_Bone_Hand_L",
    "Ferrule_Arm_R": "Ferrule_Bone_Arm_R",
    "Ferrule_Arm_R_Hand": "Ferrule_Bone_Hand_R",
    "Ferrule_Tail_01": "Ferrule_Bone_Tail_01",
    "Ferrule_Tail_02": "Ferrule_Bone_Tail_02",
    "Ferrule_Tail_03": "Ferrule_Bone_Tail_03",
}

SPINE = ["Ferrule_Bone_Rear", "Ferrule_Bone_Haunch", "Ferrule_Bone_ArchFall",
         "Ferrule_Bone_ArchApex", "Ferrule_Bone_ArchRise", "Ferrule_Bone_Neck",
         "Ferrule_Bone_Head"]
TAIL = ["Ferrule_Bone_Tail_01", "Ferrule_Bone_Tail_02", "Ferrule_Bone_Tail_03"]
JAWS = ["Ferrule_Bone_Jaw_F", "Ferrule_Bone_Jaw_R"]
ARMS = ["Ferrule_Bone_Arm_L", "Ferrule_Bone_Arm_R"]
HANDS = ["Ferrule_Bone_Hand_L", "Ferrule_Bone_Hand_R"]


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
        if act.name.startswith('Ferrule_'):
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
        sx = SIDE_X.get(name, 0.0)
        b.head = (sx * H, hd[0] * H, hd[1] * H)
        b.tail = (sx * H, tl[0] * H, tl[1] * H)
        if parent:
            b.parent = made[parent]
            # NEVER connect: Blender ignores pose translation on connected
            # bones, which silently kills the slinky's translation channel.
            b.use_connect = False
        made[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")

    unbound = []
    for o in meshes:
        bone = BIND.get(o.name)
        if bone is None:
            unbound.append(o.name)
            continue
        o.vertex_groups.clear()
        vg = o.vertex_groups.new(name=bone)
        vg.add(range(len(o.data.vertices)), 1.0, "REPLACE")
        o.parent = rig
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                o.modifiers.remove(m)
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    return rig, unbound


# ------------------------------------------------------------------- actions

def key(pb, frame, loc=None, rot=None):
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)
    if rot is not None:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = rot
        pb.keyframe_insert("rotation_euler", frame=frame)


def R(x=0.0, y=0.0, z=0.0):
    return (math.radians(x), math.radians(y), math.radians(z))


def clear_pose(rig):
    for pb in rig.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)


def new_action(rig, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots):
        rig.animation_data.action_slot = act.slots[0]
    return act


SPINE_ORDER = SPINE

# The three key poses of the attack cycle, per spine bone: (pull, drop, pitch).
# PERCH rears the forequarter high (the telegraph); LAND is the strike's
# arrival - extended low and forward. Numbers were tuned by live probes.
PERCH = {
    # the coil is a C SHAPE (director): the head curls over toward the rear
    # while the rear tucks under, the whole footprint gathering back - the
    # curl lives in the compounding pitches (head+neck+rise ~50 degrees,
    # arch negatives deepened), the gather in the ~25 percent deeper pulls
    # the FULL BACKBEND (director: overshoot - the whole body bends
    # backwards and the head travels back PAST the body). Every segment
    # rotates rearward with the SAME sign, so the rotations COMPOUND down
    # the chain (~130 degrees accumulated at the head) - the "unroll"
    # behaviour that antisymmetric arch pitches normally suppress is the
    # entire point here. Pulls stay moderate: under big parent rotations
    # the child frames are swung, and the rotations dominate the shape.
    # (per-bone signs matter: the arch-side bones' POSITIVE pitch folds
    # their tips forward-down - uniform positives collapsed the whole chain
    # into a flat pile. The arch keeps its shaping negatives; the entire
    # 130-degree compounding lives in the rise->neck->head hook.)
    # the COLUMN itself leans past vertical rearward via the haunch (-38:
    # PROBED - negative haunch pitch tips the whole downstream column rear,
    # +0.5 units at the apex per 20 degrees), and the head hook wraps over
    # from there - the previous version reared but leaned FORWARD of
    # vertical, so only the head recurved
    "Ferrule_Bone_Rear":     (-0.090, 0.00, 0.0),
    "Ferrule_Bone_Haunch":   (-0.080, -0.030, -38.0),
    "Ferrule_Bone_ArchFall": (-0.200, -0.180, -14.0),
    "Ferrule_Bone_ArchApex": (-0.240, -0.260, -10.0),
    "Ferrule_Bone_ArchRise": (-0.260, -0.300, 30.0),
    "Ferrule_Bone_Neck":     (-0.300, -0.160, 45.0),
    "Ferrule_Bone_Head":     (-0.320, -0.060, 50.0),
}
LAND = {
    # composed from the PROBED bone axes, not guessed: on the Neck/Head
    # bones local +Y (pull) points mostly DOWN-forward and negative local Z
    # (drop) points forward-UP, so the old big head pulls buried the landed
    # pose below the floor (gate_ferrule.py caught it). Forward reach comes
    # from the arch bones; the neck/head negative drops cancel the descent
    # so the head arrives AT the ground. Extended ~25 percent (a more
    # PRONOUNCED spring out of the deeper C coil), drops rebalanced to hold
    # the ground line.
    "Ferrule_Bone_Rear":     (0.00, 0.00, 0.0),
    "Ferrule_Bone_Haunch":   (0.06, 0.00, 0.0),
    "Ferrule_Bone_ArchFall": (0.155, 0.00, 1.0),
    "Ferrule_Bone_ArchApex": (0.155, -0.025, 1.0),
    "Ferrule_Bone_ArchRise": (0.150, -0.050, 1.0),
    "Ferrule_Bone_Neck":     (0.120, -0.145, 1.0),
    "Ferrule_Bone_Head":     (0.100, -0.165, 2.0),
}


def pose_spine(P, table, frame, scale=1.0, lag=0.0):
    """Key a spine pose. `lag` staggers each bone's key along the chain
    (SPINE is ordered rear -> head, so positive lag makes the pose travel
    rearward-first and negative lag head-first). A slinky's motion is
    inherently sequential - keying every bone on the same frame reads as a
    rigid block sliding, not a body moving."""
    for i, bn in enumerate(SPINE):
        if bn not in table:
            continue
        pull, drop, pitch = table[bn]
        key(P[bn], int(round(frame + i * lag)),
            loc=(0.0, pull * scale, drop * scale), rot=R(x=pitch * scale))


def author(rig):
    if rig.animation_data is None:
        rig.animation_data_create()
    made = []
    P = rig.pose.bones

    # ---- Idle (64f loop): breathing swell travelling up the spine, tail
    # sway carrying the wave out, pincer drift. Every phase-offset cycle is
    # SAMPLED as a sine across the loop plus one key a full period past the
    # end - wrapping key POSITIONS with a modulo leaves the F-curve clamped
    # at the boundary, which froze the tail solid and popped the seam.
    clear_pose(rig)
    new_action(rig, "Ferrule_Idle")
    two_pi = 2.0 * math.pi

    def loop_sine(f, ph):
        return math.sin(two_pi * ((f - 1 - ph) % 64) / 64.0)

    for i, bn in enumerate(SPINE):
        amp = 0.020 + 0.008 * i
        for f in range(1, 66, 8):
            s = loop_sine(f, i * 7)
            key(P[bn], f, loc=(0.0, amp * s, 0.0), rot=R(x=0.8 * s))
    for i, bn in enumerate(TAIL):
        for f in range(1, 66, 8):
            s = loop_sine(f, 6 * (i + 1))
            key(P[bn], f, rot=R(z=7.0 * s * (i + 1), x=2.5 * s))
    for bn, ph in ((JAWS[0], 0), (JAWS[1], 20)):
        for f in range(1, 66, 8):
            key(P[bn], f, rot=R(x=6.0 * loop_sine(f, ph)))
    for bn, sgn in ((HANDS[0], 1), (HANDS[1], -1)):
        for f in range(1, 66, 8):
            s = loop_sine(f, 12)
            key(P[bn], f, rot=R(x=9.0 * s, z=5.0 * s * sgn))
    for f, sg in ((1, 0.0), (28, 1.0), (56, 0.0), (64, 0.0)):
        key(P["Ferrule_Bone_Mouth"], f, rot=R(x=-4.0 * sg))
    made.append("Ferrule_Idle")

    # ---- Compress = TELEGRAPH (18f): the coil GATHERS rear-first, the head
    # rears last, then the perch holds - a wave rolling up the body, not a
    # block popping into place.
    clear_pose(rig)
    new_action(rig, "Ferrule_Compress")
    pose_spine(P, PERCH, 1, scale=0.0)
    pose_spine(P, PERCH, 6, scale=0.90, lag=1.0)    # rear gathers f6, head f12
    pose_spine(P, PERCH, 9, scale=1.025, lag=0.67)  # arrive OVER the perch...
    pose_spine(P, PERCH, 13, scale=1.0, lag=0.33)   # ...and settle back onto it
    pose_spine(P, PERCH, 16, scale=1.012)           # a breath through the hold
    pose_spine(P, PERCH, 18, scale=1.0)             # held exact: spring starts here
    for bn, sgn, ph in ((JAWS[0], 1.0, 0), (JAWS[1], -1.0, 2)):
        key(P[bn], 1, rot=R())
        key(P[bn], 12 + ph, rot=R(x=-20.0 * sgn))  # front pincer spreads first
        key(P[bn], 15 + ph, rot=R(x=-23.0 * sgn))  # slight overshoot...
        key(P[bn], 18, rot=R(x=-22.0 * sgn))       # ...settles into the hold
    for i, bn in enumerate(TAIL):
        key(P[bn], 1, rot=R())
        key(P[bn], 10 + 2 * i, rot=R(x=21.0 + 7.0 * i))  # curl travels outward
        key(P[bn], 15 + 2 * i, rot=R(x=26.0 + 7.0 * i))  # the C closes at the rear
        key(P[bn], 18, rot=R(x=24.0 + 7.0 * i))
    # the little limbs pull BACK and APART in the coil (director): a hard
    # rearward fold plus an opposing lateral spread, hands splaying wider
    # amplitudes are HUGE on purpose: at this camera the lateral axis
    # projects at ~0.2x, so a modest spread is sub-pixel on screen
    for j, (bn, hn) in enumerate(zip(ARMS, HANDS)):
        sgn = -1.0 if j == 0 else 1.0
        key(P[bn], 1, rot=R())
        key(P[bn], 13 + j, rot=R(x=-47.0, z=27.0 * sgn))
        key(P[bn], 18, rot=R(x=-45.0, z=26.0 * sgn))
        key(P[hn], 1, rot=R())
        key(P[hn], 14 + j, rot=R(x=-36.0, z=21.0 * sgn))
        key(P[hn], 18, rot=R(x=-34.0, z=20.0 * sgn))
    key(P["Ferrule_Bone_Mouth"], 1, rot=R())
    key(P["Ferrule_Bone_Mouth"], 13, rot=R(x=-15.5))   # gape leads a touch...
    key(P["Ferrule_Bone_Mouth"], 18, rot=R(x=-14.0))   # ...relaxes into the hold
    made.append("Ferrule_Compress")

    # ---- Spring = STRIKE (20f): one loaded beat, an EXPLOSIVE release (the
    # rear half reaches flight in 2 frames), the head hanging HIGH until a
    # 2-frame fall that hits at FULL SPEED on f11 - cushioning happens
    # after contact, never before - then the arch PILES IN behind the
    # planted head while the tail whips through and decays.
    clear_pose(rig)
    new_action(rig, "Ferrule_Spring")
    pose_spine(P, PERCH, 1, scale=1.0)
    pose_spine(P, PERCH, 2, scale=1.0)             # one beat on the loaded coil
    pose_spine(P, PERCH, 3, scale=1.10, lag=0.3)   # the dig, rear-first
    for i, bn in enumerate(SPINE):
        pp, pd, pr = PERCH[bn]
        lp, ld, lr = LAND[bn]
        if i < 4:
            # rear half EXPLODES forward through the PULL channel ONLY: the
            # drop channel AND the perch pitches keep ~full value, because
            # the arch's height lives in those antisymmetric pitches and
            # every downstream bone rides on them - unwinding either one
            # collapses the whole forequarter mid-flight
            key(P[bn], 5, loc=(0.0, lp * 0.55 + pp * 0.15, pd * 0.95),
                rot=R(x=pr * 0.80 + lr * 0.08))
            # and HOLD that flight pose until the head plants - without this
            # key the curve starts easing toward the f13-17 pile-in arrival
            # right away and the arch sags out of the pounce by f8
            key(P[bn], 10, loc=(0.0, lp * 0.70 + pp * 0.08, pd * 0.92),
                rot=R(x=pr * 0.75 + lr * 0.10))
        else:
            # head-side bones hold the perch height until late - keyed at
            # BOTH f8 and f9 so the curve cannot start easing down early;
            # the whole drop then lives in f9->f11
            key(P[bn], 8, loc=(0.0, lp * 0.30 + pp * 0.25, pd * 1.0),
                rot=R(x=pr * 0.95 + lr * 0.03))
            key(P[bn], 9, loc=(0.0, lp * 0.38 + pp * 0.22, pd * 0.98),
                rot=R(x=pr * 0.90 + lr * 0.05))
    # the head's whole drop is two frames: mid-fall f10, contact f11 at
    # peak velocity, overshoot-squash f12, back f14
    hd = P["Ferrule_Bone_Head"]
    lp, ld, lr = LAND["Ferrule_Bone_Head"]
    pp, pd, pr = PERCH["Ferrule_Bone_Head"]
    key(hd, 10, loc=(0.0, lp * 0.75, pd * 0.45), rot=R(x=lr * 0.6))
    key(hd, 11, loc=(0.0, lp * 1.09, ld * 1.09), rot=R(x=lr * 1.5))
    key(hd, 12, loc=(0.0, lp * 1.0, ld * 1.10), rot=R(x=lr * 1.9))   # pressed in
    key(hd, 14, loc=(0.0, lp, ld), rot=R(x=lr))
    nk = P["Ferrule_Bone_Neck"]
    nlp, nld, nlr = LAND["Ferrule_Bone_Neck"]
    key(nk, 11, loc=(0.0, nlp * 1.05, nld * 1.05), rot=R(x=nlr * 1.4))
    key(nk, 13, loc=(0.0, nlp, nld), rot=R(x=nlr))
    # the arch PILES IN behind the planted head: a rear-travelling cascade
    # of arrivals, each overshooting its landing with an extra pitch bump
    for i, bn in enumerate(SPINE[:5]):             # Rear..ArchRise
        blp, bld, blr = LAND[bn]
        arrive = 17 - i                            # ArchRise f13 ... Rear f17
        key(P[bn], arrive, loc=(0.0, blp * 1.15, bld * 1.15),
            rot=R(x=blr + 2.0))
        key(P[bn], min(19, arrive + 2), loc=(0.0, blp, bld), rot=R(x=blr))
    pose_spine(P, LAND, 20, scale=1.0)             # held exact: latch takes over
    for bn, sgn, ph in ((JAWS[0], 1.0, 0), (JAWS[1], -1.0, 1)):
        key(P[bn], 1, rot=R(x=-22.0 * sgn))
        key(P[bn], 9, rot=R(x=-26.0 * sgn))        # spread widest just before impact
        key(P[bn], 11 + ph, rot=R(x=-6.0 * sgn))   # snap in AT the strike
        key(P[bn], 14 + ph, rot=R(x=-10.5 * sgn))  # recoil open
        key(P[bn], 17 + ph, rot=R(x=-7.5 * sgn))
        key(P[bn], 20, rot=R(x=-8.0 * sgn))
    for i, bn in enumerate(TAIL):
        key(P[bn], 1, rot=R(x=24.0 + 7.0 * i))         # chained from the C coil
        key(P[bn], 5 + i, rot=R(x=27.0 + 7.5 * i))     # dragged up by the launch
        key(P[bn], 10 + i, rot=R(x=-24.0 - 7.0 * i))   # whip travels outward
        key(P[bn], 14 + 2 * i, rot=R(x=9.0 + 4.0 * i))  # follow-through past zero
        key(P[bn], 18 + i, rot=R(x=-7.0 - 2.0 * i))    # decaying return
        key(P[bn], 20, rot=R(x=-4.0))
    key(P["Ferrule_Bone_Mouth"], 1, rot=R(x=-14.0))
    key(P["Ferrule_Bone_Mouth"], 9, rot=R(x=-16.0))
    key(P["Ferrule_Bone_Mouth"], 11, rot=R(x=8.0))
    key(P["Ferrule_Bone_Mouth"], 13, rot=R(x=2.0))
    key(P["Ferrule_Bone_Mouth"], 16, rot=R(x=5.5))
    key(P["Ferrule_Bone_Mouth"], 20, rot=R(x=4.0))
    made.append("Ferrule_Spring")

    # ---- Latch = SEIZE + RECOVER (22f): the weight leans INTO the bite, the
    # pincers scissor asynchronously, then the rear pulls back up first and
    # the head releases last.
    clear_pose(rig)
    new_action(rig, "Ferrule_Latch")
    pose_spine(P, LAND, 1, scale=1.0)
    # The MASS sells the bite - but the head/neck LAND vectors are nearly
    # FLAT-forward, so scaling the pose can never press DOWN (it read as a
    # 0.5px tick). The clamps are their own transients through the PROBED
    # down-forward pull channel plus nose pitch; only the arch uses the
    # scaled pose passes.
    arch_t = {k: v for k, v in LAND.items()
              if k not in ("Ferrule_Bone_Head", "Ferrule_Bone_Neck")}
    pose_spine(P, arch_t, 5, scale=1.10, lag=-0.4)
    pose_spine(P, arch_t, 8, scale=0.97, lag=-0.4)   # draw back off the grip
    pose_spine(P, arch_t, 11, scale=1.09, lag=-0.3)
    pose_spine(P, arch_t, 14, scale=1.0, lag=-0.3)
    hd2 = P["Ferrule_Bone_Head"]
    nk2 = P["Ferrule_Bone_Neck"]
    hlp, hld, hlr = LAND["Ferrule_Bone_Head"]
    nlp, nld, nlr = LAND["Ferrule_Bone_Neck"]
    for f0, depth in ((4, 1.0), (10, 0.85)):         # two clamp beats
        key(hd2, f0 - 2, loc=(0.0, hlp - 0.012, hld), rot=R(x=hlr - 1.0))
        key(hd2, f0, loc=(0.0, hlp + 0.060 * depth, hld),
            rot=R(x=hlr + 4.5 * depth))
        key(hd2, f0 + 3, loc=(0.0, hlp + 0.012, hld), rot=R(x=hlr + 1.0))
        key(nk2, f0, loc=(0.0, nlp + 0.038 * depth, nld),
            rot=R(x=nlr + 3.0 * depth))
        key(nk2, f0 + 3, loc=(0.0, nlp, nld), rot=R(x=nlr))
    # recovery ORDER is the read: the haunch rises over FOUR frames (its
    # LAND values are zero - pose scale cannot move it) while the head
    # HOLDS its grip until f17 and releases last, the mid-arch easing off
    # in between and the tail dragging into the rise
    key(hd2, 17, loc=(0.0, hlp, hld), rot=R(x=hlr))
    key(nk2, 16, loc=(0.0, nlp, nld), rot=R(x=nlr))
    mid_t = {k: v for k, v in LAND.items()
             if k in ("Ferrule_Bone_ArchFall", "Ferrule_Bone_ArchApex",
                      "Ferrule_Bone_ArchRise")}
    pose_spine(P, mid_t, 15, scale=0.6, lag=0.8)
    # the REAR ANCHOR is the big unoccluded mass the player reads as "the
    # rear" - Bone_Rear must lift too (its LAND values are zeros; world-up
    # in its local frame is PROBED as (0, -0.174, -0.985)). The haunch
    # rides on it as a child, so its own transient shrinks accordingly,
    # keeping its nose-down pitch to reshape the rump outline.
    rear = P["Ferrule_Bone_Rear"]

    def rear_up(u):
        return (0.0, -0.174 * u, -0.985 * u)

    key(rear, 13, loc=(0.0, 0.0, 0.0))
    key(rear, 15, loc=rear_up(0.075))
    key(rear, 17, loc=rear_up(0.125))
    key(rear, 19, loc=rear_up(0.070))
    key(rear, 21, loc=rear_up(0.025))
    hnch = P["Ferrule_Bone_Haunch"]
    key(hnch, 13, loc=(0.0, 0.04, 0.0), rot=R())
    key(hnch, 15, loc=(0.0, 0.070, 0.0), rot=R(x=3.5))
    key(hnch, 17, loc=(0.0, 0.100, 0.0), rot=R(x=6.5))
    key(hnch, 19, loc=(0.0, 0.055, 0.0), rot=R(x=3.0))
    key(hnch, 21, loc=(0.0, 0.020, 0.0), rot=R(x=1.0))
    pose_spine(P, LAND, 22, scale=0.0)             # exact rest
    for bn, sgn, ph in ((JAWS[0], 1.0, 0), (JAWS[1], -1.0, 2)):
        key(P[bn], 1, rot=R(x=-8.0 * sgn))
        key(P[bn], 4 + ph, rot=R(x=31.0 * sgn))    # front pincer bites first
        key(P[bn], 7 + ph, rot=R(x=26.0 * sgn))    # grip eases a hair
        key(P[bn], 10 + ph, rot=R(x=28.0 * sgn))   # re-clamps: a working grip
        key(P[bn], 15 + ph, rot=R(x=10.0 * sgn))
        key(P[bn], 22, rot=R())
    key(P["Ferrule_Bone_Mouth"], 1, rot=R(x=4.0))
    key(P["Ferrule_Bone_Mouth"], 5, rot=R(x=12.0))
    key(P["Ferrule_Bone_Mouth"], 11, rot=R(x=9.0))
    key(P["Ferrule_Bone_Mouth"], 18, rot=R(x=2.0))
    key(P["Ferrule_Bone_Mouth"], 22, rot=R())
    for i, bn in enumerate(TAIL):
        key(P[bn], 1, rot=R(x=-4.0))
        key(P[bn], 5 + 2 * i, rot=R(x=9.0 + 3.0 * i))   # tension travels outward
        key(P[bn], 11 + 2 * i, rot=R(x=5.0 + 2.0 * i))
        key(P[bn], 16 + i, rot=R(x=-15.0 - 4.0 * i))    # drags as the rear lifts
        key(P[bn], 22, rot=R())
    made.append("Ferrule_Latch")

    clear_pose(rig)
    rig.animation_data.action = None
    return made


rig, unbound = build_rig()
actions = author(rig)
bpy.context.view_layer.update()
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
result = {
    "bones": len(rig.data.bones),
    "actions": actions,
    "meshes": len(meshes),
    "unbound": unbound,
    "fully_weighted": all(len(o.vertex_groups) == 1 for o in meshes),
}
