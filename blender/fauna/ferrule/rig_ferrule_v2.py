"""Rig the Ferrule as a rigid-plate chain and author its four actions.

The armature is a single chain running rear -> mouth, so each bone's local +Y
points toward the mouth. Translating a bone along its own Y therefore telescopes
every plate ahead of it: that one axis is the whole slinky motion model.
Each plate binds rigidly (one vertex group, weight 1) so the armour stays stone.
"""
import bpy
import math
from mathutils import Vector

RIG = "Ferrule_Rig"
ROOT = "FerruleRoot"
FPS = 24

# (bone, head_y, tail_y) running from the tail end forward to the snout.
CHAIN = [
    ("Ferrule_Anchor", 2.543, 2.051),
    ("Ferrule_Bone_Rear", 2.051, 1.401),
    ("Ferrule_Bone_Segment_05", 1.401, 1.167),
    ("Ferrule_Bone_Segment_04", 1.167, 0.951),
    ("Ferrule_Bone_Segment_03", 0.951, 0.734),
    ("Ferrule_Bone_Segment_02", 0.734, 0.517),
    ("Ferrule_Bone_Segment_01", 0.517, 0.300),
    ("Ferrule_Bone_Mouth", 0.300, -0.050),
]

BIND = {
    "Ferrule_Mouth": "Ferrule_Bone_Mouth",
    "Ferrule_MouthVoid": "Ferrule_Bone_Mouth",
    "Ferrule_ChelationTips": "Ferrule_Bone_Mouth",
    "Ferrule_Segment_01": "Ferrule_Bone_Segment_01",
    "Ferrule_Segment_02": "Ferrule_Bone_Segment_02",
    "Ferrule_Segment_03": "Ferrule_Bone_Segment_03",
    "Ferrule_Segment_04": "Ferrule_Bone_Segment_04",
    "Ferrule_Segment_05": "Ferrule_Bone_Segment_05",
    "Ferrule_RearAnchor": "Ferrule_Bone_Rear",
    "Ferrule_SignalVents": "Ferrule_Bone_Rear",
}

# The five plates plus the mouth, ordered rear -> front, for travelling waves.
WAVE = ["Ferrule_Bone_Segment_05", "Ferrule_Bone_Segment_04",
        "Ferrule_Bone_Segment_03", "Ferrule_Bone_Segment_02",
        "Ferrule_Bone_Segment_01", "Ferrule_Bone_Mouth"]


def bake_transforms(objs):
    """Fold each plate's station offset into its vertices so the bind is clean."""
    for o in objs:
        off = Vector(o.location)
        if off.length > 1e-9:
            for v in o.data.vertices:
                v.co = v.co + off
            o.location = (0.0, 0.0, 0.0)
        o.data.update()


def build_rig():
    scene = bpy.context.scene
    scene.render.fps = FPS
    root = bpy.data.objects[ROOT]
    coll = root.users_collection[0]

    meshes = [o for o in coll.objects if o.type == "MESH"]
    bake_transforms(meshes)

    arm_data = bpy.data.armatures.new(RIG)
    rig = bpy.data.objects.new(RIG, arm_data)
    coll.objects.link(rig)
    rig.parent = root

    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    previous = None
    for name, hy, ty in CHAIN:
        eb = arm_data.edit_bones.new(name)
        eb.head = (0.0, hy, 0.0)
        eb.tail = (0.0, ty, 0.0)
        eb.roll = 0.0
        if previous is not None:
            eb.parent = previous
            eb.use_connect = True
        previous = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    for o in meshes:
        bone = BIND[o.name]
        vg = o.vertex_groups.new(name=bone)
        vg.add(range(len(o.data.vertices)), 1.0, "REPLACE")
        o.parent = rig
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    return rig


# ------------------------------------------------------------------- actions

def key(pb, frame, loc=None, rot_x=None):
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)
    if rot_x is not None:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler.x = rot_x
        pb.keyframe_insert("rotation_euler", frame=frame)


def new_action(rig, name, end):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    action.frame_range  # touch
    return action


def clear_pose(rig):
    for pb in rig.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)


def author_actions(rig):
    if rig.animation_data is None:
        rig.animation_data_create()
    made = []

    # --- Idle: a slow swell travelling rear -> mouth, plates breathing on the axis.
    clear_pose(rig)
    act = new_action(rig, "Ferrule_Idle", 64)
    for i, bone in enumerate(WAVE):
        pb = rig.pose.bones[bone]
        phase = i * 8
        amp = 0.012 + 0.004 * i
        for f, s in ((1, 0.0), (16, 1.0), (32, 0.0), (48, -1.0), (64, 0.0)):
            fr = ((f + phase - 1) % 64) + 1
            key(pb, fr, loc=(0.0, amp * s, 0.0), rot_x=math.radians(0.4 * s))
    made.append(act.name)

    # --- Compress: the chain telescopes back onto the anchor and humps up.
    clear_pose(rig)
    act = new_action(rig, "Ferrule_Compress", 18)
    for i, bone in enumerate(WAVE):
        pb = rig.pose.bones[bone]
        pull = -(0.045 + 0.022 * i)
        key(pb, 1, loc=(0.0, 0.0, 0.0), rot_x=0.0)
        key(pb, 12, loc=(0.0, pull * 0.82, 0.0), rot_x=math.radians(-0.65 - 0.26 * i))
        key(pb, 18, loc=(0.0, pull, 0.0), rot_x=math.radians(-0.9 - 0.35 * i))
    made.append(act.name)

    # --- Spring: release, drive the mouth forward, overshoot, settle.
    clear_pose(rig)
    act = new_action(rig, "Ferrule_Spring", 20)
    for i, bone in enumerate(WAVE):
        pb = rig.pose.bones[bone]
        pull = -(0.045 + 0.022 * i)
        push = 0.030 + 0.020 * i
        lead = i                       # the wave releases rear-first
        key(pb, 1, loc=(0.0, pull, 0.0), rot_x=math.radians(-0.9 - 0.35 * i))
        key(pb, 4 + lead, loc=(0.0, push, 0.0), rot_x=math.radians(0.9 + 0.30 * i))
        key(pb, 11 + lead, loc=(0.0, push * 0.28, 0.0), rot_x=math.radians(-0.35))
        key(pb, 20, loc=(0.0, 0.0, 0.0), rot_x=0.0)
    made.append(act.name)

    # --- Latch: the mouth pitches down, the tips drive in, then a short recoil.
    clear_pose(rig)
    act = new_action(rig, "Ferrule_Latch", 22)
    mouth = rig.pose.bones["Ferrule_Bone_Mouth"]
    key(mouth, 1, loc=(0.0, 0.0, 0.0), rot_x=0.0)
    key(mouth, 5, loc=(0.0, -0.030, 0.0), rot_x=math.radians(7.0))
    key(mouth, 9, loc=(0.0, 0.055, 0.0), rot_x=math.radians(-15.0))
    key(mouth, 13, loc=(0.0, 0.040, 0.0), rot_x=math.radians(-12.0))
    key(mouth, 22, loc=(0.0, 0.0, 0.0), rot_x=0.0)
    for i, bone in enumerate(WAVE[:-1]):
        pb = rig.pose.bones[bone]
        key(pb, 1, loc=(0.0, 0.0, 0.0), rot_x=0.0)
        key(pb, 9, loc=(0.0, 0.014 * (i + 1) * 0.4, 0.0), rot_x=math.radians(0.5))
        key(pb, 22, loc=(0.0, 0.0, 0.0), rot_x=0.0)
    made.append(act.name)

    clear_pose(rig)
    rig.animation_data.action = None
    return made


rig = build_rig()
actions = author_actions(rig)
bpy.context.view_layer.update()

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
result = {
    "bones": len(rig.data.bones),
    "bone_names": [b.name for b in rig.data.bones],
    "actions": actions,
    "meshes": len(meshes),
    "bound": all(len(o.vertex_groups) == 1 and o.modifiers for o in meshes),
}
