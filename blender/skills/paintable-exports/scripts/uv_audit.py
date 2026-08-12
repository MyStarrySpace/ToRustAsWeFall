# UV AUDIT — the gate every modeled piece passes before it ships.
#
# Two failures matter and neither is visible in a render:
#   HARD OVERLAP    two faces claim the same texel. Painting one paints the other;
#                   the atlas cannot be hand-edited at all.
#   ZERO GUTTER     two islands merely touch. No overlap, but they share edge
#                   texels the moment the painter dilates or a mip is generated,
#                   so colour bleeds across a seam that looks fine in the viewport.
# Both are found by rasterizing UVs AT THE PIECE'S REAL ATLAS RESOLUTION — an audit
# at some convenient 1024 will pass pieces that bleed at their actual 128.
#
# Run headless against a saved .blend, or through the MCP `execute` transport
# against the live file:
#   blender.exe -b <file>.blend --python uv_audit.py -- --res 512 --json out.json
# Objects with no UV layer are reported, not failed: flat-material pieces
# (ob["no_atlas"]) legitimately carry no atlas.

import json
import sys

import bmesh
import bpy

DEFAULT_RES = 512
# A gutter this many texels or wider is healthy. One texel of separation is the
# minimum that survives bilinear sampling; two survives one mip level.
MIN_GUTTER_TEXELS = 2


def _islands(bm, uvl):
    """Faces grouped into UV islands by shared UV position (union-find)."""
    key_faces = {}
    for f in bm.faces:
        for l in f.loops:
            uv = l[uvl].uv
            key_faces.setdefault((round(uv.x, 6), round(uv.y, 6)), set()).add(f.index)
    parent = {f.index: f.index for f in bm.faces}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for fs in key_faces.values():
        fl = list(fs)
        for other in fl[1:]:
            ra, rb = find(fl[0]), find(other)
            if ra != rb:
                parent[rb] = ra
    groups = {}
    for f in bm.faces:
        groups.setdefault(find(f.index), []).append(f.index)
    return groups


def _point_in_poly(px, py, uvs):
    inside = False
    j = len(uvs) - 1
    for i in range(len(uvs)):
        if (uvs[i].y > py) != (uvs[j].y > py):
            xint = (uvs[j].x - uvs[i].x) * (py - uvs[i].y) / \
                   ((uvs[j].y - uvs[i].y) or 1e-12) + uvs[i].x
            if px < xint:
                inside = not inside
        j = i
    return inside


def _base_colour_image(mat):
    """The image feeding a material's Base Color, following the link rather than
    guessing from the node list."""
    if not mat or not mat.use_nodes:
        return None
    for node in mat.node_tree.nodes:
        if node.type != 'BSDF_PRINCIPLED':
            continue
        inp = node.inputs.get("Base Color")
        if not inp or not inp.links:
            continue
        src = inp.links[0].from_node
        while src and src.type != 'TEX_IMAGE':
            nxt = None
            for i in src.inputs:
                if i.links:
                    nxt = i.links[0].from_node
                    break
            src = nxt
        if src and src.type == 'TEX_IMAGE' and src.image:
            return src.image.name
    return None


def _distinct_images(ob):
    """The distinct BASE COLOUR images the object samples. One means a packed
    atlas. Counting every image node instead counts an emissive or normal sidecar
    as a second texture, which reads a perfectly good single-atlas piece as
    multi-texture and quietly switches this audit off for it — four of the six
    atlas fauna carry an _emissive.png and were skipped that way."""
    names = set()
    for slot in ob.material_slots:
        nm = _base_colour_image(slot.material)
        if nm:
            names.add(nm)
    return names


def audit_object(ob, res=DEFAULT_RES, min_gutter=MIN_GUTTER_TEXELS):
    # Audit at the piece's OWN atlas size. One convenient resolution across a mixed
    # library audits a 32px cup at 16x its real density and reports it clean.
    # texture_object stamps the size it chose; fall back to the sweep's default.
    res = int(ob.get("atlas_px", res))
    me = ob.data
    if not me.uv_layers:
        return {"name": ob.name, "status": "no_uv_layer",
                "note": "flat-material piece (no_atlas) or an unwrap was skipped"}
    # NO BLANKET SKIP. An earlier version of this returned early for any piece
    # that was not a single packed atlas, and that was an escape hatch: a piece
    # folded onto itself was confirmed RED, then passed by adding one extra
    # base-colour image, and passed again by setting ob["no_atlas"]. A gate with a
    # bypass is worse than no gate, because it reports the bypass as a PASS.
    #
    # The two families need no special case once the measurement is keyed by
    # MATERIAL. Overlap only means anything between faces sampling the SAME image,
    # so material-keyed counting is simply the correct measurement: for a single
    # atlas it is what the test always did, and for a material-per-part piece it
    # stops counting parts against each other. What genuinely cannot be judged is
    # a TILING material, where UVs run outside 0..1 and repeats are the intent —
    # that is excluded per material, and named, not waved through per piece.
    imgs = _distinct_images(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    groups = _islands(bm, uvl)
    face_island = {}
    for i, (_root, faces) in enumerate(sorted(groups.items())):
        for fi in faces:
            face_island[fi] = i

    cover = {}
    folds = {}                  # (material, texel) -> how many FACES cover it
    outside = 0
    tiling = set()              # materials whose UVs leave 0..1, so repeats are
                                # intended and stacking is not a defect
    for f in bm.faces:
        for l in f.loops:
            uv = l[uvl].uv
            if not (-1e-4 <= uv.x <= 1.0001 and -1e-4 <= uv.y <= 1.0001):
                tiling.add(f.material_index)
                break
    for f in bm.faces:
        uvs = [l[uvl].uv for l in f.loops]
        us = [uv.x for uv in uvs]
        vs = [uv.y for uv in uvs]
        if f.material_index in tiling:
            # A tiling material repeats on purpose: running outside 0..1 is the
            # mechanism, faces landing on the same texel are different repeats of
            # the same noise, and a gutter between islands would do nothing. None
            # of the three measures below can say anything true about it, so it
            # contributes to none of them — and it is NAMED in tiling_materials so
            # the exclusion is visible rather than silent.
            continue
        if min(us) < -1e-4 or max(us) > 1.0001 or min(vs) < -1e-4 or max(vs) > 1.0001:
            outside += 1
        for gx in range(max(0, int(min(us) * res) - 1), min(res, int(max(us) * res) + 2)):
            for gy in range(max(0, int(min(vs) * res) - 1), min(res, int(max(vs) * res) + 2)):
                if _point_in_poly((gx + 0.5) / res, (gy + 0.5) / res, uvs):
                    mi = f.material_index
                    cover.setdefault((mi, gx, gy), set()).add(face_island[f.index])
                    folds.setdefault((mi, gx, gy), []).append(f.index)
    # Between DIFFERENT islands, which is what this test always measured...
    hard = sum(1 for v in cover.values() if len(v) > 1)
    # ...and within ONE island, which it never did. `cover` holds a SET of island
    # indices per texel, so a shell folded onto itself contributes the same index
    # twice and reads as clean. That is not a corner case: it is the ordinary
    # failure of a bad unwrap, and it is the one that makes a piece unpaintable.
    # Proof this needed writing: stacking EVERY face of a real piece onto one
    # circle in UV space — total overlap, full area — was reported "ok".
    # TWO FACES SHARING AN EDGE ARE ADJACENT, NOT FOLDED. A texel centre landing
    # exactly on their shared edge tests inside BOTH under an even-odd point-in-poly
    # rule, and counting that as a fold is a false alarm that scales with mesh
    # density — triangulating a shell took an apparent 4 folds to 115 purely this
    # way. Only faces that share NO edge can really be folded onto each other.
    adjacent = {}
    for e in bm.edges:
        fs = [f.index for f in e.link_faces]
        for a in fs:
            for b in fs:
                if a != b:
                    adjacent.setdefault(a, set()).add(b)
    folded = 0
    for owners in folds.values():
        if len(owners) < 2:
            continue
        uniq = sorted(set(owners))
        if any(uniq[j] not in adjacent.get(uniq[i], ())
               for i in range(len(uniq)) for j in range(i + 1, len(uniq))):
            folded += 1
    near = {}
    # Reach must EQUAL the required gutter, not sit one under it: at reach =
    # min_gutter - 1 the scan sees only zero-gap adjacency, so a 1-texel gap reads
    # clean while still failing the "survives one mip level" standard this constant
    # exists to enforce. That off-by-one is why annulus rows at +1 passed for months.
    reach = min_gutter
    for (mi, gx, gy), isl in cover.items():
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                other = cover.get((mi, gx + dx, gy + dy))
                if not other:
                    continue
                for a in isl:
                    for b in other:
                        if a != b:
                            k = (min(a, b), max(a, b))
                            near[k] = near.get(k, 0) + 1
    bm.free()

    status = "ok"
    if folded:
        status = "SELF_OVERLAP"
    if hard:
        status = "HARD_OVERLAP"
    elif near:
        status = "ZERO_GUTTER"
    elif outside:
        status = "UV_OUT_OF_BOUNDS"
    return {
        "name": ob.name,
        "status": status,
        "res": res,
        "islands": len(groups),
        "covered_texels": len(cover),
        "folded_texels": folded,
        "images": sorted(imgs),
        "tiling_materials": sorted(tiling),
        "coverage_pct": round(100.0 * len(cover) / float(res * res), 2),
        "hard_overlap_texels": hard,
        "island_pairs_under_min_gutter": len(near),
        "faces_outside_0_1": outside,
        "worst_pairs": sorted(({"islands": list(k), "texels": v} for k, v in near.items()),
                              key=lambda d: -d["texels"])[:8],
    }


def audit_all(res=DEFAULT_RES, min_gutter=MIN_GUTTER_TEXELS):
    rows = [audit_object(o, res, min_gutter)
            for o in bpy.data.objects if o.type == 'MESH']
    bad = [r for r in rows
           if r.get("status") in ("HARD_OVERLAP", "SELF_OVERLAP", "ZERO_GUTTER",
                                  "UV_OUT_OF_BOUNDS")]
    return {"res": res, "min_gutter_texels": min_gutter,
            "audited": rows, "failing": bad, "verdict": "FAIL" if bad else "PASS"}


# `result` is the MCP return contract; the __main__ block is the headless path.
result = audit_all()

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    res = DEFAULT_RES
    out = ""
    if "--res" in argv:
        res = int(argv[argv.index("--res") + 1])
    if "--json" in argv:
        out = argv[argv.index("--json") + 1]
    result = audit_all(res)
    text = json.dumps(result, indent=2)
    if out:
        open(out, "w", encoding="utf-8").write(text)
    print(text)
    print("UV AUDIT %s (%d failing)" % (result["verdict"], len(result["failing"])))
