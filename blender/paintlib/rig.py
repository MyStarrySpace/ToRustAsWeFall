# RIG — armatures, weights and clips for pieces whose STATE CHANGES ARE ANIMATIONS.
#
# THE LAW (director, 2026-08-10): when a thing changes state, the player WATCHES it
# change. Not two bodies swapped, not a repaint, not a flipbook. The specs make the
# transition the readable thing — a Seefern's eye-markings "opening as she works"
# is what "tells the player when it's complete", a Hushbloom's leaflets fold "in a
# wave along each rachis" — so the animation IS the progress bar, and swapping
# endpoints throws away the only thing that communicates.
#
# What lives here: bone chains along the parts that bend, real weights (a chain
# falls off smoothly along its length instead of hinging at one joint), actions
# keyframed into named clips, and the export that carries skin + clips into the
# gltf so Godot gets an AnimationPlayer.
#
# What does NOT live here: timing decisions. A clip is COSMETIC — the data layer
# owns the state and the scheduler owns when it commits, so nothing may gate a
# state change on a clip finishing (the fast-forward invariance law).
#
# Two rules a caller has to respect:
#   1. A card must be SUBDIVIDED to bend (`Builder.card(..., segments=N)`); a quad
#      has four corners and no amount of rigging will fold it.
#   2. Bones are authored in the piece's own space, base -> tip, so a chain's rest
#      pose matches the geometry it was cut from.

import bpy
import json
import mathutils
import os
import time


_EXPORT_RETRIES = 6
_EXPORT_BACKOFF = 0.4


def _ensure_object_mode():
    if bpy.context.object is not None and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')


def build_armature(name, chains, collection=None):
    """Create an armature from `chains`, a list of bone chains. Each chain is
    {"prefix": str, "points": [(x, y, z), ...]} — one bone per consecutive pair,
    parented head-to-tail so a rotation at the base carries the whole chain.

    A chain may also carry {"parent": "<bone name>"}, which parents its base bone
    to an earlier chain's bone WITHOUT connecting them, so the two keep their own
    heads. That is how a part rides a body it is not continuous with: scaling the
    parent carries the child's offset with it, so a patch that grows takes the
    things standing on it along instead of sliding out from under them.

    Points are in the piece's own space, base first. Returns the armature object."""
    _ensure_object_mode()
    arm_data = bpy.data.armatures.new(name + "_arm")
    arm = bpy.data.objects.new(name + "_Armature", arm_data)
    (collection or bpy.context.scene.collection).objects.link(arm)

    prev_active = bpy.context.view_layer.objects.active
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    made = {}
    for chain in chains:
        prefix = chain["prefix"]
        pts = [mathutils.Vector(p) for p in chain["points"]]
        parent = None
        riding = chain.get("parent")
        for i in range(len(pts) - 1):
            eb = arm_data.edit_bones.new("%s_%d" % (prefix, i))
            eb.head = pts[i]
            eb.tail = pts[i + 1]
            if parent is not None:
                eb.parent = parent
                eb.use_connect = True
            elif riding:
                eb.parent = arm_data.edit_bones[riding]
                eb.use_connect = False
            parent = eb
            made[eb.name] = True
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = prev_active
    return arm


def bind(mesh_ob, arm, kind='ARMATURE_AUTO'):
    """Parent `mesh_ob` to `arm` with WEIGHTS. Automatic weights compute falloff
    from bone envelopes, which is what makes a chain bend smoothly along its length
    instead of snapping at a joint — the whole reason to rig rather than to hinge.
    Falls back to envelope weights on the rare mesh auto-weighting refuses (a mesh
    with loose or non-manifold parts), because a bound-but-stiff piece still
    animates while an unbound one silently does not move at all."""
    _ensure_object_mode()
    bpy.ops.object.select_all(action='DESELECT')
    mesh_ob.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type=kind)
    except RuntimeError:
        bpy.ops.object.select_all(action='DESELECT')
        mesh_ob.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.parent_set(type='ARMATURE_ENVELOPE')
        print("[RIG] %s: auto weights refused, bound by envelope" % mesh_ob.name)
    bpy.ops.object.select_all(action='DESELECT')
    return mesh_ob


def clip(arm, name, poses, fps=24.0):
    """Keyframe one named clip onto `arm`.

    `poses` is [(time_seconds, {bone_name: (rx, ry, rz)}), ...] in bone-local
    Euler radians. Bones absent from a pose hold whatever the previous pose set,
    so a chain's wave is written as the few poses that matter rather than a full
    per-bone table. Returns the action, named so the gltf clip carries the name."""
    _ensure_object_mode()
    scene = bpy.context.scene
    scene.render.fps = int(fps)
    if arm.animation_data is None:
        arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    # Start every clip from REST, scale included. The armature is left standing in
    # whatever the previous clip finished on, so a bone the new clip does not
    # mention at t=0 would be keyed at the old clip's value and the transition
    # would open by snapping to a pose the body was never in.
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    for (t, bones) in poses:
        frame = max(1, int(round(t * fps)))
        for bone_name, value in bones.items():
            pb = arm.pose.bones.get(bone_name)
            if pb is None:
                continue
            # a bare number is a uniform SCALE (that is how a flash is written);
            # a triple is an Euler rotation; a dict carries either or both, and is
            # the only way to write a NON-UNIFORM scale. A body that collapses
            # needs one: going flat while spreading out is a single motion in two
            # axes, and a uniform scale can only say "smaller".
            if isinstance(value, dict):
                if "scale" in value:
                    sv = value["scale"]
                    pb.scale = ((float(sv),) * 3 if isinstance(sv, (int, float))
                                else tuple(float(v) for v in sv))
                if "rot" in value:
                    pb.rotation_euler = mathutils.Euler(tuple(value["rot"]), 'XYZ')
            elif isinstance(value, (int, float)):
                pb.scale = (float(value), float(value), float(value))
            else:
                pb.rotation_euler = mathutils.Euler(value, 'XYZ')
        # key EVERY bone at every pose time: a bone left unkeyed interpolates from
        # whatever the next pose says, which turns a held pose into a slow drift
        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
            pb.keyframe_insert(data_path="scale", frame=frame)
    scene.frame_end = max(scene.frame_end,
                          max(1, int(round(poses[-1][0] * fps))) if poses else 1)
    # Push to an NLA track and clear the active slot. An armature holds only ONE
    # active action, and the glTF exporter's ACTIONS mode ships that one — so a
    # rig authored with several clips silently exports with only its last, and the
    # rest are simply missing from the game. NLA tracks carry them all.
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    track.mute = True                 # stacked strips must not blend into each other
    arm.animation_data.action = None
    return action


def park(arm, bones):
    """Leave `arm` standing in a pose, so the EXPORTED rest is that pose.

    A bone's rest scale is 1.0 by construction, and a glTF joint carries whatever
    pose the armature is left in — so anything a clip only ever hides is fully
    visible on a body that has not played anything yet. A flash card is the case
    that matters: it is authored at its visual size, because the atlas packer
    allots texels by physical size and a card shrunk in the mesh would come out
    with no artwork to show. Its bone is parked shut instead.

    A parked pose does not stay put on its own. The glTF exporter steps the scene
    frame to sample the NLA, and every armature in the file is evaluated at each
    of those frames — so exporting one subject can leave ANOTHER standing on the
    last frame of its own clips, and that armature ships wearing a pose nobody
    authored as its idle. The pose is therefore REMEMBERED here and re-applied by
    `export_rigged_gltf` immediately before the file is written.

    `bones` is {bone_name: scale_float | (rx, ry, rz)}, matching `clip` poses.
    Call it AFTER the clips: they leave the armature on their own last pose."""
    _ensure_object_mode()

    def _ser(v):
        if isinstance(v, dict):
            return dict((k, list(sv) if not isinstance(sv, (int, float)) else sv)
                        for k, sv in v.items())
        return list(v) if not isinstance(v, (int, float)) else v

    arm["_parked_pose"] = json.dumps(
        dict((k, _ser(v)) for k, v in bones.items()))
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    for bone_name, value in bones.items():
        pb = arm.pose.bones.get(bone_name)
        if pb is None:
            raise KeyError("park: no bone %r on %s" % (bone_name, arm.name))
        # The same three forms `clip` takes. A rest pose that could be written for
        # a clip but not for the park is a rest pose you cannot actually hold —
        # anything needing both a turn and a retraction had to be split in two.
        if isinstance(value, dict):
            if "scale" in value:
                sv = value["scale"]
                pb.scale = ((float(sv),) * 3 if isinstance(sv, (int, float))
                            else tuple(float(v) for v in sv))
            if "rot" in value:
                pb.rotation_euler = mathutils.Euler(tuple(value["rot"]), 'XYZ')
        elif isinstance(value, (int, float)):
            pb.scale = (float(value),) * 3
        else:
            pb.rotation_euler = mathutils.Euler(value, 'XYZ')


def chain_wave(prefix, count, amount, lead=0.35):
    """A pose dict for one chain folding as a WAVE — each bone lags the one before
    it, which is how the real thing folds (the spec's "folded inward in a wave
    along each rachis") and what a single uniform rotation cannot express."""
    out = {}
    for i in range(count):
        falloff = 1.0 - lead * (i / float(max(1, count - 1)))
        out["%s_%d" % (prefix, i)] = (amount * falloff, 0.0, 0.0)
    return out


def _restand_parked(objs):
    """Put every parked armature in `objs` back on its idle pose.

    The exporter's NLA sampling walks the scene frame, which drives every
    armature in the file — including ones already exported and ones not being
    exported at all. Without this, what ships as a body's rest depends on the
    order the pieces were written in.
    """
    seen = set()
    for ob in objs:
        for cand in [ob] + list(getattr(ob, "children_recursive", [])):
            if cand.type != 'ARMATURE' or cand.name in seen:
                continue
            seen.add(cand.name)
            raw = cand.get("_parked_pose")
            if raw:
                park(cand, json.loads(raw))


def export_rigged_gltf(objs, path):
    """Game-ready GLTF_SEPARATE carrying SKINS and CLIPS, so Godot imports an
    AnimationPlayer with the transitions on it. Armatures are exported alongside
    the meshes they deform; a mesh whose armature is missing from the selection
    exports unskinned and silently stops moving."""
    _ensure_object_mode()
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
        for child in ob.children_recursive:
            child.select_set(True)
        for mod in getattr(ob, "modifiers", []):
            if mod.type == 'ARMATURE' and mod.object is not None:
                mod.object.select_set(True)
    kw = dict(filepath=path, export_format="GLTF_SEPARATE", export_yup=True,
              export_apply=False,          # apply=True would flatten the armature away
              export_image_format="AUTO",
              export_animations=True, export_skins=True,
              export_animation_mode="NLA_TRACKS",
              # Ship the armature as it STANDS, not as it rests. A joint's rest
              # scale is 1.0 by construction, so anything a clip only ever hides —
              # a flash card, which must be authored at full size for the atlas to
              # allot it any texels — is fully visible on a body that has played
              # nothing. `park()` is what leaves the armature in its idle pose, and
              # this is what carries that pose into the file.
              export_rest_position_armature=False)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kw = {k: v for k, v in kw.items() if k in props or k == "filepath"}
    if "use_selection" in props:
        kw["use_selection"] = True
    elif "export_selected_objects" in props:
        kw["export_selected_objects"] = True
    # Write to a FRESH file rather than over a live one. A GLTF_SEPARATE export
    # rewrites the .gltf and its .bin in place, and replacing a file that another
    # process is holding open — an engine that has it imported, a scanner reading
    # it the instant it lands — fails partway with an OSError and leaves whichever
    # buffers already went out on disk paired with a stale header.
    stem = os.path.splitext(path)[0]
    for doomed in (path, stem + ".bin"):
        for _ in range(_EXPORT_RETRIES):
            if not os.path.exists(doomed):
                break
            try:
                os.remove(doomed)
                break
            except OSError:
                time.sleep(_EXPORT_BACKOFF)
    _restand_parked(objs)
    last = None
    for attempt in range(_EXPORT_RETRIES):
        try:
            _restand_parked(objs)   # a failed attempt samples the NLA all the same
            bpy.ops.export_scene.gltf(**kw)
            print("[EXPORT rigged]", path)
            return
        except (OSError, RuntimeError) as err:
            last = err
            time.sleep(_EXPORT_BACKOFF)
    raise RuntimeError("gltf export kept failing for %s: %s" % (path, last))


def assign_exclusive_weights(mesh_ob, bone_name, vert_indices):
    """Weight-paint `vert_indices` to `bone_name` ALONE, clearing whatever the
    automatic pass gave them. Automatic weights work from proximity, so a small
    part sitting in the middle of a plant picks up every bone around it and moves
    when it should sit still. Anything whose motion is its own — a flash, a shed
    leaf, a lid — has to be told which bone owns it."""
    groups = {vg.name: vg for vg in mesh_ob.vertex_groups}
    if bone_name not in groups:
        groups[bone_name] = mesh_ob.vertex_groups.new(name=bone_name)
    idx = list(vert_indices)
    for name, vg in groups.items():
        if name == bone_name:
            vg.add(idx, 1.0, 'REPLACE')
        else:
            vg.remove(idx)


def scale_pulse(bone_name, small=0.001, big=1.0):
    """Pose helpers for a bone that HIDES by being scaled to nothing and appears by
    snapping open — how a flash is expressed inside a skinned clip, since glTF
    animates node transforms and not material properties."""
    return ({bone_name: small}, {bone_name: big})


# Weight below this is treated as noise: it moves a vertex by a sub-pixel amount
# and is usually automatic weighting bleeding across a gap it should not cross.
LIVE_WEIGHT = 0.02


def validate(mesh_ob, arm, segments_by_prefix=None):
    """Prove the rig actually DEFORMS. Two failures look identical to a build log
    and identical in a static render, and both ship silently:

    A DEAD BONE — a bone with no vertices weighted to it. It rotates through the
    clip and moves nothing at all. Automatic weighting produces these whenever a
    bone's envelope catches no geometry, which is common the moment several chains
    crowd the same space and one of them loses.

    AN ORPHAN VERTEX — a vertex in no group. It ignores every bone and stays
    behind while the rest of the piece moves, tearing the mesh open.

    Also checks the DENSITY rule: a chain may not carry more bones than the thing
    it deforms has subdivisions. Past that point the extra joints have no distinct
    rows to move, so the rotation they were given is averaged away — the detail is
    not gained, it is compressed out.

    `segments_by_prefix` maps a chain prefix to the subdivision count it drives.
    Returns a report dict; `problems` empty means the rig deforms."""
    me = mesh_ob.data
    groups = {vg.index: vg.name for vg in mesh_ob.vertex_groups}
    bone_names = [b.name for b in arm.data.bones]

    live = {name: 0 for name in bone_names}
    orphans = 0
    stranded = 0
    phantom = set()
    for v in me.vertices:
        total = 0.0
        for g in v.groups:
            name = groups.get(g.group)
            if name is None:
                continue
            if g.weight < LIVE_WEIGHT:
                continue
            # Weight only counts toward "this vertex moves" when the group is a
            # BONE. A group named after a bone that does not exist takes the
            # weight and deforms nothing: the exporter sweeps those vertices onto
            # its own static neutral bone, where they sit still while the rest of
            # the piece moves — an orphan wearing a group name.
            if name in live:
                total += g.weight
                live[name] += 1
            else:
                phantom.add(name)
        if total <= 0.0:
            if v.groups:
                stranded += 1
            else:
                orphans += 1

    problems = []

    # IS IT BOUND AT ALL. Everything below reads vertex groups and bone names as
    # two independent lists and cross-checks them BY NAME, which says nothing
    # about whether the mesh is attached to the armature. Removing the armature
    # modifier outright, or leaving it in place with .object = None, produced a
    # byte-identical PASS on a real piece while a posed depsgraph showed all 6216
    # vertices frozen and every bone moving nothing. That is total rig failure
    # reported as success — and it is the exact case this function's own docstring
    # says it exists to prevent. Name-matching also passes a mesh bound to the
    # WRONG armature, so compare identity, not names.
    bound = None
    for mod in getattr(mesh_ob, "modifiers", []):
        if mod.type == 'ARMATURE' and mod.object is not None:
            bound = mod.object
            break
    if bound is None:
        problems.append("the mesh is not bound to any armature — it has no "
                        "ARMATURE modifier with an object, so nothing it is "
                        "weighted to can move it")
    elif bound is not arm:
        problems.append("the mesh is bound to %r, not to the armature being "
                        "validated (%r)" % (bound.name, arm.name))
    dead = sorted(n for n, c in live.items() if c == 0)
    if dead:
        problems.append("dead bones (weighted to nothing, so they animate but "
                        "deform nothing): %s" % ", ".join(dead))
    if orphans:
        problems.append("%d vertices belong to no bone and will not move" % orphans)
    if stranded:
        problems.append("%d vertices are weighted ONLY to groups that are not bones "
                        "(%s) — they export onto the static neutral bone and tear "
                        "away from the piece"
                        % (stranded, ", ".join(sorted(phantom)[:6])))

    over = []
    misspelled = []
    for prefix, segs in (segments_by_prefix or {}).items():
        count = len([n for n in bone_names if n.startswith(prefix + "_")])
        # A PREFIX THAT MATCHES NOTHING IS A TYPO, NOT A PASS. count==0 is never
        # greater than segs, so a chain declared as 'leafs' against bones named
        # 'leaf_0..' silently switched this rule OFF for that chain — the one-letter
        # error reads as compliance. Declaring a chain that does not exist is now a
        # failure in its own right.
        if count == 0:
            misspelled.append("%s (declared %d subdivisions, matches no bone)"
                              % (prefix, segs))
        elif count > segs:
            over.append("%s has %d bones over %d subdivisions" % (prefix, count, segs))
    if misspelled:
        problems.append("declared chain prefix matches no bone, so its density was "
                        "never checked: %s" % "; ".join(misspelled))
    if over:
        problems.append("more bones than subdivisions, so the extra rotation is "
                        "averaged away: %s" % "; ".join(over))

    # Chains nobody declared are UNCHECKED by the density rule. Not a failure —
    # most rigs declare nothing and forcing it would break every build — but it is
    # reported so "validate passed" cannot be mistaken for "the density law holds".
    chains = {}
    for n in bone_names:
        if "_" in n:
            chains[n.rsplit("_", 1)[0]] = chains.get(n.rsplit("_", 1)[0], 0) + 1
    declared = set(segments_by_prefix or {})
    undeclared = sorted(c for c, k in chains.items() if k > 1 and c not in declared)

    return {"bones": len(bone_names), "dead_bones": dead,
            "orphan_verts": orphans,
            "undeclared_chains": undeclared,
            "min_verts_per_bone": min(live.values()) if live else 0,
            "problems": problems,
            "verdict": "FAIL" if problems else "PASS"}


def _armature_bones(mesh_ob):
    """Bone names of the armature deforming `mesh_ob`, or None when it has none."""
    for mod in getattr(mesh_ob, "modifiers", []):
        if mod.type == 'ARMATURE' and mod.object is not None:
            return set(b.name for b in mod.object.data.bones)
    return None


def weight_chain_strip(mesh_ob, prefix, row_verts, tip_bias=0.5):
    """Weight a SUBDIVIDED strip to its bone chain by hand, row by row.

    Automatic weights work from envelope proximity, which is a guess. On a fan of
    similar strips crowded together the guess fails quietly and specifically: a
    tip bone catches no vertices and becomes a DEAD bone that rotates through the
    whole clip while deforming nothing. The topology here is known exactly — row r
    of the strip sits between bone r-1 and bone r — so the weights are computed,
    not guessed, and every bone is guaranteed a share.

    `row_verts` is one list of vertex indices per division, base row first. Bone
    count is len(row_verts) - 1, which is the density rule holding by construction:
    a strip can never end up with more bones than it has subdivisions."""
    bones = len(row_verts) - 1
    if bones < 1:
        return
    names = ["%s_%d" % (prefix, i) for i in range(bones)]
    # Every name here MUST be a real bone. A strip with more rows than its chain
    # has joints would otherwise mint groups nobody drives, and weight taken by a
    # group that is not a bone is weight thrown away: the exporter parks those
    # vertices on its static neutral bone and they stay behind while the piece
    # moves. Refuse it at the source, where the mismatch is one number.
    known = _armature_bones(mesh_ob)
    if known is not None:
        missing = [n for n in names if n not in known]
        if missing:
            raise KeyError(
                "weight_chain_strip(%r): %d rows need %d bones, but %s do not exist "
                "— give the chain %d points, one per row"
                % (prefix, len(row_verts), bones, ", ".join(missing), len(row_verts)))
    groups = {}
    for name in names:
        groups[name] = (mesh_ob.vertex_groups.get(name)
                        or mesh_ob.vertex_groups.new(name=name))
    for r, verts in enumerate(row_verts):
        idx = list(verts)
        # clear whatever a previous automatic pass left on this row
        for vg in mesh_ob.vertex_groups:
            vg.remove(idx)
        if r == 0:                                  # the base rides its first bone
            groups[names[0]].add(idx, 1.0, 'REPLACE')
        elif r == bones:                            # the tip rides the last
            groups[names[bones - 1]].add(idx, 1.0, 'REPLACE')
        else:
            # a shared row blends the two bones meeting there, which is what makes
            # the bend a curve instead of a hinge
            groups[names[r - 1]].add(idx, 1.0 - tip_bias, 'REPLACE')
            groups[names[r]].add(idx, tip_bias, 'REPLACE')


def card_rows(start_index, segments):
    """Vertex-index rows for one `Builder.card(..., segments=N)`, base row first.
    The builder emits its rows in order, two verts per row, so a card's rows are
    exactly this — no searching the mesh for them."""
    return [[start_index + 2 * r, start_index + 2 * r + 1] for r in range(segments + 1)]
