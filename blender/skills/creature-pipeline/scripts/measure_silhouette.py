"""ORTHOGRAPHIC silhouette measurement — the creature acceptance test.

Two earlier attempts at this were wrong and both flattered the model:

  * Rendering a turnaround and measuring the image. The camera is PERSPECTIVE and
    its distance is fitted to object radius, so the projected aspect is not the
    orthographic aspect a concept turnaround carries. It reported a side aspect of
    0.84 on a body whose real length/height was 2.00 against the sheet's 2.03.
  * Taking raw mesh bounds. A creature carries geometry authored at full size and
    PARKED SHUT — the Gnawer's enzyme cloud — which is invisible in rest and
    dominates the bounding box: 1.794 long against a body spanning 0.822.

So: evaluate the mesh through the depsgraph WITH the armature in its park pose,
which is exactly what the player sees standing still, and project that. No camera
is involved, so there is no perspective to get wrong.

    blender -b <file>.blend --python measure_silhouette.py -- [--bands N]

Prints the front (X across Z) and side (Y across Z) aspects and band profiles, in
the same form a concept sheet is measured in, so the two are directly comparable.
"""
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BANDS = int(argv[argv.index("--bands") + 1]) if "--bands" in argv else 10

# A PARKED bone is one the rest pose collapses — the Gnawer's cloud bones are
# scaled shut so the cloud is invisible until it grows. Vertices owned by such a
# bone are not part of the silhouette the player sees, and including them is what
# made the body measure 1.494 long against a 0.822 contract. Find them by pose
# scale, not by name, so this works for any species that parks anything.
PARK_EPS = 0.15
parked_bones = set()
for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
    for pb in arm.pose.bones:
        s = pb.matrix_basis.to_scale()
        if min(abs(s.x), abs(s.y), abs(s.z)) < PARK_EPS:
            parked_bones.add(pb.name)
if parked_bones:
    print("MEASURE excluding %d parked bone(s): %s"
          % (len(parked_bones), ", ".join(sorted(parked_bones))))

bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for ob in bpy.data.objects:
    if ob.type != 'MESH':
        continue
    drop = set()
    if parked_bones:
        gi = {g.index: g.name for g in ob.vertex_groups}
        for v in ob.data.vertices:
            best, bestw = None, 0.0
            for g in v.groups:
                if g.weight > bestw:
                    best, bestw = gi.get(g.group), g.weight
            if best in parked_bones:
                drop.add(v.index)
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    m = ob.matrix_world
    if len(me.vertices) == len(ob.data.vertices):
        pts += [m @ v.co for i, v in enumerate(me.vertices) if i not in drop]
    else:
        pts += [m @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    if drop:
        print("MEASURE dropped %d vert(s) owned by parked bones" % len(drop))

if not pts:
    print("MEASURE no mesh"); raise SystemExit

xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
W, L, H = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
print("MEASURE evaluated(park)  width(X)=%.3f  length(Y)=%.3f  height(Z)=%.3f" % (W, L, H))
print("MEASURE front aspect W/H = %.2f" % (W / H))
print("MEASURE side  aspect L/H = %.2f" % (L / H))

z0, z1 = min(zs), max(zs)
for axis, vals, span, label in (("X", xs, W, "front"), ("Y", ys, L, "side ")):
    prof = []
    for k in range(BANDS):
        lo = z0 + (z1 - z0) * k / float(BANDS)
        hi = z0 + (z1 - z0) * (k + 1) / float(BANDS)
        sel = [v for v, p in zip(vals, pts) if lo <= p.z <= hi]
        prof.append(int(round(100.0 * (max(sel) - min(sel)) / span)) if len(sel) > 1 else 0)
    # top -> bottom, to match how a sheet is read
    print("MEASURE %s band profile (top->bottom): %s"
          % (label, " ".join("%3d" % p for p in prof[::-1])))
