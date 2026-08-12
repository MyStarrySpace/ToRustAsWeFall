# Joining parts of a body at a SHARED EDGE LOOP.
#
# The rule this exists to serve (asset-pipeline.md): two parts of one body meet at
# ONE ring of vertices that both of them own — not near each other, not overlapping,
# the same loop. Everything else is a floating part and reads as one the moment the
# camera moves.
#
# What it replaces, and why neither worked:
#
#   Appending interpenetrating geometry. An opaque material hides the intersection
#   from a render and from nothing else. The silhouette still shows two objects, the
#   normals disagree along the crossing, and no gate in this project reports it.
#
#   Boolean UNION. It merges the two VOLUMES and leaves the two SURFACES crossing
#   inside the result. That is exactly why the Sapscrap's claws read as clipping
#   THROUGH its arms rather than growing out of them.
#
# The order is MEASURE, DELINEATE, OPEN, BUILD, WELD, UNWRAP, VERIFY. This module
# owns OPEN, WELD and VERIFY; measuring and delineating are the caller's job,
# because only the caller knows where the part belongs.

import bmesh
import math

from mathutils import Vector


def surface_hit(bm, origin, direction, inward=True):
    """MEASURE: where the host's skin actually is along `direction`.

    Returns the farthest intersection walking out from `origin`, so a lump or an
    inner wall does not stop the search early. None if the ray misses.

    Tested TRIANGLE BY TRIANGLE, never against a face's own plane. The kit jitters
    its ring vertices, which makes every quad slightly non-planar, and a
    point-in-polygon test against one plane then rejects perfectly good hits — it
    did so for two of four cardinal directions out of the middle of a tube, which
    reads as an aperture that "missed the host" when the host is all around it.

    This exists because placing a part from a typed coordinate is how a mouth ends
    up floating 3 cm off a body: the number was right for the shape the host had
    when it was written.
    """
    d = Vector(direction).normalized()
    o = Vector(origin)
    best = None
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        for i in range(1, len(vs) - 1):
            a, b, c = vs[0], vs[i], vs[i + 1]
            e1, e2 = b - a, c - a
            pv = d.cross(e2)
            det = e1.dot(pv)
            if abs(det) < 1e-12:
                continue
            inv = 1.0 / det
            tv = o - a
            u = tv.dot(pv) * inv
            if u < -1e-7 or u > 1.0 + 1e-7:
                continue
            qv = tv.cross(e1)
            v = d.dot(qv) * inv
            if v < -1e-7 or u + v > 1.0 + 1e-7:
                continue
            t = e2.dot(qv) * inv
            if t <= 1e-5:
                continue
            if best is None or t > best[0]:
                best = (t, o + d * t)
    return None if best is None else best[1]


def ring(bm, centre, normal, radius, segments, roll=0.0):
    """A clean ring of `segments` verts, ready to be welded to or built from."""
    d = Vector(normal).normalized()
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    c = Vector(centre)
    out = []
    for i in range(segments):
        a = math.tau * i / segments + roll
        out.append(bm.verts.new(
            (q @ Vector((math.cos(a) * radius, math.sin(a) * radius, 0.0))) + c))
    bm.verts.ensure_lookup_table()
    return out


def _boundary_loops(bm):
    """Every boundary as an ORDERED vertex ring, walked along its open edges.

    Ordered by traversal rather than by angle: a hole cut through a lumpy host is
    not convex about its own centre, and sorting such a rim by angle interleaves
    vertices from opposite sides of a notch.
    """
    edges = [e for e in bm.edges if len(e.link_faces) == 1]
    nbr = {}
    for e in edges:
        a, b = e.verts
        nbr.setdefault(a, []).append(b)
        nbr.setdefault(b, []).append(a)
    seen, loops = set(), []
    for start in list(nbr.keys()):
        if start in seen:
            continue
        loop, cur, prev = [start], start, None
        seen.add(start)
        while True:
            nxt = None
            for cand in nbr.get(cur, []):
                if cand is not prev and cand not in seen:
                    nxt = cand
                    break
            if nxt is None:
                break
            loop.append(nxt)
            seen.add(nxt)
            prev, cur = cur, nxt
        if len(loop) >= 3:
            loops.append(loop)
    return loops


def _unwrapped(verts, centre, normal):
    """Angles about the aperture axis, made monotonically increasing over one turn
    so a merge can compare positions on the two rings without wraparound cases."""
    d = Vector(normal).normalized()
    q = d.to_track_quat("Z", "Y").to_matrix().inverted()
    raw = []
    for v in verts:
        rel = v.co - Vector(centre)
        local = q @ (rel - d * rel.dot(d))
        raw.append(math.atan2(local.y, local.x))
    out = [raw[0]]
    for a in raw[1:]:
        prev = out[-1]
        while a < prev - 1e-9:
            a += math.tau
        out.append(a)
    return out


def _zipper(bm, rag, clean, centre, normal):
    """Tile the annulus between a ragged rim and a clean ring.

    The classic two-pointer merge: at each step advance whichever ring is behind
    in angle and emit the triangle that closes the gap. It produces exactly
    len(rag) + len(clean) triangles and leaves NO hole, which a per-sector fan does
    not — that was the first attempt and it left thirty-six open edges and two
    islands, which is to say it was not a join at all.
    """
    m, n = len(rag), len(clean)
    ra = _unwrapped(rag, centre, normal)
    ca = _unwrapped(clean, centre, normal)
    # start both rings at a common angular origin so the merge does not open with
    # a triangle that spans most of the ring
    off = min(range(n), key=lambda i: abs(((ca[i] - ra[0] + math.pi) % math.tau) - math.pi))
    clean = clean[off:] + clean[:off]
    ca = _unwrapped(clean, centre, normal)
    i = j = 0
    made = 0
    while i < m or j < n:
        take_rag = j >= n or (i < m and (ra[(i + 1) % m] + (math.tau if i + 1 >= m else 0.0))
                              <= (ca[(j + 1) % n] + (math.tau if j + 1 >= n else 0.0)))
        if take_rag:
            tri = (rag[i % m], rag[(i + 1) % m], clean[j % n])
            i += 1
        else:
            tri = (rag[i % m], clean[(j + 1) % n], clean[j % n])
            j += 1
        try:
            bm.faces.new(tri)
            made += 1
        except ValueError:
            pass
    return made


def aperture(bm, centre, normal, radius, segments, depth=None, roll=0.0):
    """OPEN: cut a hole in the host and hand back a CLEAN ring on its rim.

    Faces whose centres fall inside the cylinder are removed, which leaves a rim of
    whatever vertices the host happened to have there; a clean `segments`-vertex
    ring is laid on the aperture circle and the rim is zippered onto it. The caller
    then builds the part FROM the ring that comes back, so the two parts share it
    by construction rather than by coincidence.

    Returns the ring (ordered), or None if the cut removed nothing — an aperture
    that missed the host is worth failing on rather than carrying on with a part
    attached to empty space.
    """
    d = Vector(normal).normalized()
    c = Vector(centre)
    # A SHALLOW BAND AROUND THE APERTURE PLANE, never a long cylinder. Given a
    # generous reach the cut travels the whole way through the host and opens a
    # second hole out the far side — on a 0.5 m sphere a reach of 0.96 removed the
    # back of it, and the graft then reported open edges a metre from the mouth it
    # was supposed to be making. An aperture opens the near shell and nothing else.
    band = radius * 1.25 if depth is None else depth

    def _crosses(f):
        """Does this face INTERSECT the aperture, rather than merely sit inside it?

        A face-centre test alone only works while the host's faces are smaller than
        the hole. Grafting a 3 cm toe onto a strand whose faces are 6 by 18 cm, no
        centre lands inside the cylinder, nothing is deleted, and the graft reports
        that it missed a host it is standing on. A face the aperture passes through
        must go even if its centre is somewhere else entirely; the ragged hole that
        leaves is exactly what the zipper is for.
        """
        rel = f.calc_center_median() - c
        along = rel.dot(d)
        if abs(along) <= band and (rel - d * along).length <= radius:
            return True
        for v in f.verts:
            r2 = v.co - c
            a2 = r2.dot(d)
            if abs(a2) <= band and (r2 - d * a2).length <= radius:
                return True
        # the aperture's own axis, run through the face
        vs = [v.co for v in f.verts]
        for i in range(1, len(vs) - 1):
            a, b, cc = vs[0], vs[i], vs[i + 1]
            e1, e2 = b - a, cc - a
            pv = d.cross(e2)
            det = e1.dot(pv)
            if abs(det) < 1e-12:
                continue
            inv = 1.0 / det
            tv = c - a
            u = tv.dot(pv) * inv
            if u < -1e-7 or u > 1.0 + 1e-7:
                continue
            qv = tv.cross(e1)
            vv = d.dot(qv) * inv
            if vv < -1e-7 or u + vv > 1.0 + 1e-7:
                continue
            if abs(e2.dot(qv) * inv) <= band * 3.0:
                return True
        return False

    doomed = [f for f in bm.faces if _crosses(f)]
    if not doomed:
        return None
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # the rim this cut opened: the boundary loop nearest the aperture, ignoring any
    # the host already carried
    best, best_d = None, 1e18
    for loop in _boundary_loops(bm):
        mid = sum((v.co for v in loop), Vector((0, 0, 0))) / len(loop)
        dist = (mid - c).length
        if dist < best_d:
            best, best_d = loop, dist
    if best is None:
        return None

    clean = ring(bm, c, d, radius, segments, roll=roll)
    _zipper(bm, best, clean, c, d)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return clean


def bridge(bm, ring_a, ring_b, flip=False):
    """WELD: a quad strip between two rings of equal length.

    They are matched INDEX to index, so both rings must be generated with the same
    winding and roll — which they are when both come from `ring()` or from an
    `aperture()` the part was built out of.
    """
    if len(ring_a) != len(ring_b):
        raise ValueError("bridge needs equal rings (%d vs %d)"
                         % (len(ring_a), len(ring_b)))
    n = len(ring_a)
    faces = []
    for i in range(n):
        j = (i + 1) % n
        quad = (ring_a[i], ring_a[j], ring_b[j], ring_b[i])
        if flip:
            quad = tuple(reversed(quad))
        try:
            faces.append(bm.faces.new(quad))
        except ValueError:
            pass
    return faces


def graft_tube(bm, centre, normal, radius, stations, segments=12, roll=0.0):
    """OPEN + BUILD + WELD in one call: a tube growing OUT OF the host.

    `stations` is [(offset_along_normal, radius), ...] beyond the aperture. The
    tube's first ring IS the aperture's ring, so there is no seam to cross — one
    surface, from the host's skin to the tube's end.
    """
    base = aperture(bm, centre, normal, radius, segments, roll=roll)
    if base is None:
        raise RuntimeError("aperture at %s missed the host" % (tuple(centre),))
    d = Vector(normal).normalized()
    c = Vector(centre)
    prev = base
    for (offset, r) in stations:
        nxt = ring(bm, c + d * offset, d, r, segments, roll=roll)
        bridge(bm, prev, nxt)
        prev = nxt
    cap = bm.faces.new(tuple(prev))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return prev, cap


def graft_polyline(bm, normal, radius, points, radii, segments=12, roll=0.0,
                   centre=None, cap=True):
    """OPEN + BUILD + WELD along an arbitrary path.

    `graft_tube` runs straight out along the aperture normal, which is fine for a
    spout and wrong for anything that bends — a buttress curving down to the floor,
    a branch with a knuckle. Here the caller hands over the whole polyline and the
    first ring of it IS the aperture's ring, so a curved part is welded on exactly
    the same terms as a straight one.
    """
    c = Vector(points[0]) if centre is None else Vector(centre)
    base = aperture(bm, c, normal, radius, segments, roll=roll)
    if base is None:
        raise RuntimeError("aperture at %s missed the host" % (tuple(c),))
    prev = base
    for i in range(1, len(points)):
        p = Vector(points[i])
        if i == len(points) - 1:
            d = (p - Vector(points[i - 1])).normalized()
        else:
            d = ((Vector(points[i + 1]) - p).normalized()
                 + (p - Vector(points[i - 1])).normalized()).normalized()
        nxt = ring(bm, p, d, radii[i], segments, roll=roll)
        bridge(bm, prev, nxt)
        prev = nxt
    made = None
    if cap:
        try:
            made = bm.faces.new(tuple(prev))
        except ValueError:
            made = None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return prev, made


def weight_nearest(obj, arm, groups_for=None, overrides=None):
    """Weight every vertex to the bone whose SEGMENT it lies nearest.

    Grafting deletes host faces, and deleting faces takes their orphaned vertices
    with them — so any index range recorded while building describes a mesh that
    no longer exists by the time the weights are assigned. Distance to a bone's
    head-tail segment does not care what the indices did.
    """
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    made = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    segs = []
    for b in arm.data.bones:
        if groups_for is not None and b.name not in groups_for:
            continue
        segs.append((b.name, Vector(b.head_local), Vector(b.tail_local)))
    if not segs:
        raise RuntimeError("no bones offered to weight against")
    fixed = dict(overrides or {})
    for v in obj.data.vertices:
        # DELIBERATELY SEPARATE PARTS ARE TAGGED, not inferred. Shed rubble and a
        # ground card are not grafted to anything and have no shared ring, so the
        # nearest bone to them is whatever body part happens to be closest — which
        # leaves their own bones weighted to nothing and the rig gate calls those
        # dead. Nearest-bone is for the WELDED body; anything loose says so.
        if v.index in fixed:
            made[fixed[v.index]].add([v.index], 1.0, 'REPLACE')
            continue
        p = v.co
        best, best_d = None, 1e18
        for (name, h, t) in segs:
            ab = t - h
            denom = ab.length_squared
            u = 0.0 if denom < 1e-12 else max(0.0, min(1.0, (p - h).dot(ab) / denom))
            d = (p - (h + ab * u)).length
            if d < best_d:
                best, best_d = name, d
        made[best].add([v.index], 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm
    return made


def seams_from(bm, rings):
    """Mark the graft rings as UV SEAMS.

    A graft is where two shells meet, which makes it the one place a seam costs
    nothing; a seam anywhere else cuts a surface that reads as continuous. Called
    before the unwrap, which must be the LAST thing that happens to the mesh —
    every UV made before a graft describes a mesh that no longer exists.
    """
    wanted = set()
    for r in rings:
        for i in range(len(r)):
            wanted.add(frozenset((r[i].index, r[(i + 1) % len(r)].index)))
    marked = 0
    for e in bm.edges:
        if frozenset((e.verts[0].index, e.verts[1].index)) in wanted:
            e.seam = True
            marked += 1
    return marked


def seal_stragglers(bm, sides=8):
    """Close the few tiny holes a zipper can leave behind.

    The merge skips any triangle bmesh rejects as duplicate or degenerate, which
    on a real host is a handful out of hundreds — three, on the Sapscrap's maw.
    Sealed here rather than by loosening the verify, because a body with three
    open edges is still a body with a hole in it and the check should keep saying
    so until the hole is gone.
    """
    edges = [e for e in bm.edges if len(e.link_faces) == 1]
    if not edges:
        return 0
    bmesh.ops.holes_fill(bm, edges=edges, sides=sides)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return len(edges)


def weld_report(bm, expect_open=0, expect_islands=1):
    """VERIFY: what a joined body must be able to say about itself."""
    open_edges = [e for e in bm.edges if len(e.link_faces) == 1]
    nonmanifold = [e for e in bm.edges if len(e.link_faces) > 2]

    # islands, by walking faces through shared edges
    seen, islands = set(), 0
    for f in bm.faces:
        if f.index in seen:
            continue
        islands += 1
        stack = [f]
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            for e in cur.edges:
                for nb in e.link_faces:
                    if nb.index not in seen:
                        seen.add(nb.index)
                        stack.append(nb)
    # WINDING. Two faces sharing a manifold edge must traverse it in OPPOSITE
    # directions; when they traverse it the same way one of them is inside out.
    # Nothing above can see this — a reversed face has identical edge topology, so
    # every count here is unchanged — and a flipped face is invisible in a solid
    # render from the outside while showing as a hole from the other side. It is
    # one of the defects the red-shell hole test was built to find; this catches it
    # per-piece at build time instead.
    flipped = 0
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        dirs = []
        for f in e.link_faces:
            for l in f.loops:
                if l.edge is e:
                    dirs.append(l.vert is e.verts[0])
                    break
        if len(dirs) == 2 and dirs[0] == dirs[1]:
            flipped += 1

    # AN UNWELDED SEAM. Two rings sitting in the same place but never joined read
    # as welded to the eye and to a render, and the counts above can miss them
    # whenever the caller's expected open-edge total already allows boundaries.
    # A vertex on a boundary that is coincident with ANOTHER boundary vertex is
    # the signature: welded geometry shares one vertex, it does not have two at
    # the same coordinate.
    boundary = set()
    for e in open_edges:
        boundary.add(e.verts[0])
        boundary.add(e.verts[1])
    buckets, coincident = {}, 0
    for v in boundary:
        key = (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))
        if key in buckets:
            coincident += 1
        else:
            buckets[key] = True

    problems = []
    if flipped:
        problems.append("%d edges join faces of OPPOSITE winding — a part is "
                        "inside out" % flipped)
    if coincident:
        problems.append("%d boundary vertices sit on top of another boundary "
                        "vertex — rings were placed together, not welded"
                        % coincident)
    if len(open_edges) != expect_open:
        problems.append("open edges: %d (expected %d)" % (len(open_edges), expect_open))
    if nonmanifold:
        problems.append("non-manifold edges: %d" % len(nonmanifold))
    if islands != expect_islands:
        problems.append("islands: %d (expected %d) — parts did not join"
                        % (islands, expect_islands))
    return {"verdict": "PASS" if not problems else "FAIL",
            "flipped_edges": flipped, "coincident_boundary": coincident,
            "open_edges": len(open_edges), "nonmanifold": len(nonmanifold),
            "islands": islands, "problems": problems}


def assert_welded(bm, label, expect_open=0, expect_islands=1):
    r = weld_report(bm, expect_open=expect_open, expect_islands=expect_islands)
    print("[GRAFT] %s %s islands=%d open=%d nonmanifold=%d"
          % (label, r["verdict"], r["islands"], r["open_edges"], r["nonmanifold"]))
    if r["verdict"] != "PASS":
        raise RuntimeError("%s is not one welded body: %s" % (label, "; ".join(r["problems"])))
    return r
