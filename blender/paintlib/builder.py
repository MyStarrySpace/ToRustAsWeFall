# The faceted mesh kit: clean-topology primitives with per-face part/detail tags.
# Butting faces are never created (skip=...), rings always close their loop, and
# every face carries the part id the painter later fills.

import bmesh
import bmesh as _bmesh
import bpy
import json
import math
import mathutils

from .palette import PART_IDS, DETAIL_NONE


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.part_layer = self.bm.faces.layers.int.new("part")
        self.detail_layer = self.bm.faces.layers.int.new("detail")
        # every primitive call records a PAINT GROUP so the unwrap can lay its
        # faces out contiguously (the BlockBench-style unfolded box / strip)
        self.groups = []

    def _tag(self, faces, part, detail=DETAIL_NONE):
        pid = PART_IDS[part]
        for f in faces:
            f[self.part_layer] = pid
            f[self.detail_layer] = detail

    def box(self, center, size, part, skip=(), detail=DETAIL_NONE):
        """Axis-aligned box. skip: iterable of face names to omit ('top','bottom',
        '+x','-x','+y','-y') so butting faces are never created (clean topology)."""
        cx, cy, cz = center
        sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        v = {}
        for dx in (-1, 1):
            for dy in (-1, 1):
                for dz in (-1, 1):
                    v[(dx, dy, dz)] = self.bm.verts.new((cx + dx * sx, cy + dy * sy, cz + dz * sz))
        quads = {
            "top":    [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
            "bottom": [(-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)],
            "+x":     [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
            "-x":     [(-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)],
            "+y":     [(1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)],
            "-y":     [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
        }
        faces = []
        made = {}
        for name, keys in quads.items():
            if name in skip:
                continue
            f = self.bm.faces.new([v[k] for k in keys])
            faces.append(f)
            made[name] = f
        self._tag(faces, part, detail)
        self.groups.append({
            "kind": "box", "part": part, "detail": detail,
            "size": (size[0], size[1], size[2]),
            "center": (cx, cy, cz),
            "faces": made,
            "corners": {vert: key for key, vert in v.items()},
        })
        return faces

    def tapered_box(self, center, top_size, bot_size, height, part, skip=(),
                    detail=DETAIL_NONE, z0=None):
        """Box whose top rect differs from its bottom rect (plush bodies, pointy
        ears). Same six-face topology and paint-group layout as box()."""
        cx, cy, cz = center
        z0 = (cz - height / 2.0) if z0 is None else z0
        tw, td = top_size[0] / 2.0, top_size[1] / 2.0
        bw, bd = bot_size[0] / 2.0, bot_size[1] / 2.0
        v = {}
        for dx in (-1, 1):
            for dy in (-1, 1):
                v[(dx, dy, -1)] = self.bm.verts.new((cx + dx * bw, cy + dy * bd, z0))
                v[(dx, dy, 1)] = self.bm.verts.new((cx + dx * tw, cy + dy * td, z0 + height))
        quads = {
            "top":    [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
            "bottom": [(-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)],
            "+x":     [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
            "-x":     [(-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)],
            "+y":     [(1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)],
            "-y":     [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
        }
        faces = []
        made = {}
        for name, keys in quads.items():
            if name in skip:
                continue
            f = self.bm.faces.new([v[k] for k in keys])
            faces.append(f)
            made[name] = f
        self._tag(faces, part, detail)
        self.groups.append({
            "kind": "box", "part": part, "detail": detail,
            "size": (max(top_size[0], bot_size[0]), max(top_size[1], bot_size[1]), height),
            "center": (center[0], center[1], center[2]),
            "faces": made,
            "corners": {vert: key for key, vert in v.items()},
        })
        return faces

    def ngon_prism(self, center, r_top, r_bot, height, part, sides=8, cap_top=True,
                   cap_bottom=True, detail=DETAIL_NONE, z0=None):
        """Regular prism / tapered cup. center=(x,y), z0=base height."""
        cx, cy = center
        z0 = 0.0 if z0 is None else z0
        bot = [self.bm.verts.new((cx + r_bot * math.cos(2 * math.pi * i / sides),
                                  cy + r_bot * math.sin(2 * math.pi * i / sides), z0))
               for i in range(sides)]
        top = [self.bm.verts.new((cx + r_top * math.cos(2 * math.pi * i / sides),
                                  cy + r_top * math.sin(2 * math.pi * i / sides), z0 + height))
               for i in range(sides)]
        faces = []
        side_faces = []
        for i in range(sides):
            j = (i + 1) % sides   # close the loop — never leave a gap
            f = self.bm.faces.new([bot[i], bot[j], top[j], top[i]])
            faces.append(f)
            side_faces.append(f)
        cap_t = cap_b = None
        if cap_top:
            cap_t = self.bm.faces.new(list(reversed(top)))
            faces.append(cap_t)
        if cap_bottom:
            cap_b = self.bm.faces.new(bot)
            faces.append(cap_b)
        self._tag(faces, part, detail)
        corners = {}
        for i, vert in enumerate(bot):
            corners[vert] = ("bot", i)
        for i, vert in enumerate(top):
            corners[vert] = ("top", i)
        self.groups.append({
            "kind": "prism", "part": part, "detail": detail,
            "center": (cx, cy, z0 + height * 0.5),
            "sides": sides, "r_top": r_top, "r_bot": r_bot, "height": height,
            "side_faces": side_faces, "cap_top": cap_t, "cap_bottom": cap_b,
            "corners": corners,
        })
        return faces

    def annulus(self, center, r_out, r_in, depth, part, sides=24,
                detail=DETAIL_NONE, front=0.0):
        """Full closed ring (portal frames and kin): outer wall, inner wall,
        front + back rings. The ring lies in the XZ plane facing -Y (Godot +Z
        after the y-up export)."""
        cx, cy, cz = center
        def ring(r, y):
            pts = []
            for i in range(sides):
                a = 2 * math.pi * i / sides
                pts.append(self.bm.verts.new((cx + r * math.cos(a), cy + y, cz + r * math.sin(a))))
            return pts
        of, ob_ = ring(r_out, front), ring(r_out, front + depth)
        if_, ib_ = ring(r_in, front), ring(r_in, front + depth)
        faces = []
        strips = {"outer": [], "inner": [], "front": [], "back": []}
        for i in range(sides):
            j = (i + 1) % sides
            strips["outer"].append(self.bm.faces.new([of[i], of[j], ob_[j], ob_[i]]))
            strips["inner"].append(self.bm.faces.new([ib_[i], ib_[j], if_[j], if_[i]]))
            strips["front"].append(self.bm.faces.new([if_[i], if_[j], of[j], of[i]]))
            strips["back"].append(self.bm.faces.new([ob_[i], ob_[j], ib_[j], ib_[i]]))
        for lst in strips.values():
            faces.extend(lst)
        self._tag(faces, part, detail)
        corners = {}
        for ring_name, ring_verts in (("of", of), ("ob", ob_), ("if", if_), ("ib", ib_)):
            for i, vert in enumerate(ring_verts):
                corners[vert] = (ring_name, i)
        self.groups.append({
            "kind": "annulus", "part": part, "detail": detail,
            "center": (center[0], center[1], center[2]),
            "sides": sides, "r_out": r_out, "r_in": r_in, "depth": depth,
            "strips": strips, "corners": corners,
        })
        return faces

    def disc(self, center, r, part, sides=24, detail=DETAIL_NONE, flip=False):
        cx, cy, cz = center
        pts = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            pts.append(self.bm.verts.new((cx + r * math.cos(a), cy, cz + r * math.sin(a))))
        ring_order = list(pts)
        if flip:
            pts = list(reversed(pts))
        f = self.bm.faces.new(pts)
        self._tag([f], part, detail)
        self.groups.append({
            "kind": "disc", "part": part, "detail": detail,
            "center": (center[0], center[1], center[2]), "r": r,
            "face": f, "corners": {vert: i for i, vert in enumerate(ring_order)},
        })
        return [f]

    def limb(self, p0, p1, r0, r1, part, sides=5, detail=DETAIL_NONE,
             cap_start=True, cap_end=True):
        """A tapered segment running from p0 to p1 — a branch, a filament, a limb.

        `ngon_prism` only grows along +Z, so anything on a diagonal has to be
        built upright and then laid onto its own axis. Placing prisms along a
        diagonal without turning them leaves a row of little vertical drums
        floating where the limb should be, which is what a creature's arm looks
        like before someone notices."""
        a = mathutils.Vector(p0)
        b = mathutils.Vector(p1)
        axis = b - a
        length = axis.length
        if length <= 0.0:
            return
        n0 = len(self.bm.verts)
        self.ngon_prism((0.0, 0.0), r1, r0, length, part, sides=sides,
                        cap_top=cap_end, cap_bottom=cap_start, detail=detail, z0=0.0)
        made = list(self.bm.verts[n0:])
        rot = axis.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        _bmesh.ops.transform(self.bm, matrix=mathutils.Matrix.Translation(a) @ rot,
                             verts=made)

    def tube(self, points, radii, part, sides=5, detail=DETAIL_NONE,
             cap_start=True, cap_end=True):
        """ONE continuous tube through `points` — a body, a stem, a tentacle.

        A chain of `limb` calls is not this. Each limb orients its rings to its
        OWN axis, so where two of them meet on a curve their rings sit in
        different planes and share no vertices: the surface is cut at every
        joint. It looks whole while the thing is straight and opens along every
        seam the moment it bends, which is exactly when a rigged body is being
        looked at. Here the rings are swept along the path and stitched, so the
        joint between two stations is a shared edge loop and the body is one
        manifold surface that a bone chain can bend as far as the pose asks.

        `radii` is one radius per point. Ring twist is carried along the path
        rather than recomputed per segment, so the quads stay untwisted through
        a bend.

        `part` is one name for the whole run, or ONE NAME PER SPAN when the body
        changes material along its length — a chain of links whose joints are a
        darker recess than the swells between them. The rings stay shared either
        way; only the paint groups divide, one per contiguous run of a name. That
        division is safe because UVs are per-LOOP, so the ring where two
        materials meet can hold a different corner key in each group without
        either of them tearing.
        """
        pts = [mathutils.Vector(p) for p in points]
        if len(pts) < 2 or len(radii) != len(pts):
            return
        rows = len(pts) - 1
        row_parts = [part] * rows if isinstance(part, str) else list(part)
        if len(row_parts) != rows:
            raise ValueError("tube: %d parts for %d spans" % (len(row_parts), rows))
        n0 = len(self.bm.verts)
        up = mathutils.Vector((0.0, 0.0, 1.0))
        first = (pts[1] - pts[0]).normalized()
        if abs(first.dot(up)) > 0.99:
            up = mathutils.Vector((0.0, 1.0, 0.0))
        ref = (up - first * up.dot(first)).normalized()
        rings = []
        for i, p in enumerate(pts):
            if i == 0:
                tan = (pts[1] - pts[0]).normalized()
            elif i == len(pts) - 1:
                tan = (pts[-1] - pts[-2]).normalized()
            else:
                tan = (pts[i + 1] - pts[i - 1]).normalized()
            # carry the reference across the bend instead of re-deriving it, or
            # the ring flips wherever the path passes the pole of whatever fixed
            # up-vector was used, and the tube wrings itself out at that station
            ref = (ref - tan * ref.dot(tan))
            if ref.length < 1e-6:
                ref = mathutils.Vector((1.0, 0.0, 0.0))
                ref = (ref - tan * ref.dot(tan))
            ref.normalize()
            side = tan.cross(ref).normalized()
            ring = []
            for k in range(sides):
                a = 2.0 * math.pi * k / sides
                off = ref * (math.cos(a) * radii[i]) + side * (math.sin(a) * radii[i])
                ring.append(self.bm.verts.new(p + off))
            rings.append(ring)
        side_faces = []
        for i in range(len(rings) - 1):
            row = []
            for k in range(sides):
                k2 = (k + 1) % sides
                row.append(self.bm.faces.new((rings[i][k], rings[i][k2],
                                              rings[i + 1][k2], rings[i + 1][k])))
            side_faces.append(row)
        cap_a = self.bm.faces.new(list(reversed(rings[0]))) if cap_start else None
        cap_b = self.bm.faces.new(list(rings[-1])) if cap_end else None
        for r, row in enumerate(side_faces):
            self._tag(row, row_parts[r], detail)
        if cap_a is not None:
            self._tag([cap_a], row_parts[0], detail)
        if cap_b is not None:
            self._tag([cap_b], row_parts[-1], detail)
        seg_len = [(pts[i + 1] - pts[i]).length for i in range(rows)]
        # one paint group per contiguous run of a material; the mesh itself is
        # never divided, so the rings stay shared across the boundary
        r0 = 0
        while r0 < rows:
            r1 = r0 + 1
            while r1 < rows and row_parts[r1] == row_parts[r0]:
                r1 += 1
            span = pts[r0:r1 + 1]
            corners = {}
            for g in range(r0, r1 + 1):
                for k, vert in enumerate(rings[g]):
                    corners[vert] = ("ring", g - r0, k)
            self.groups.append({
                "kind": "tube", "part": row_parts[r0], "detail": detail,
                "center": [sum(p[i] for p in span) / float(len(span))
                           for i in range(3)],
                "corners": corners,
                "sides": sides, "rows": r1 - r0,
                "seg_len": seg_len[r0:r1],
                "radii": list(radii[r0:r1 + 1]),
                "side_faces": side_faces[r0:r1],
                "cap_start": cap_a if (r0 == 0 and cap_a is not None) else None,
                "cap_end": cap_b if (r1 == rows and cap_b is not None) else None,
            })
            r0 = r1
        self.bm.verts.index_update()
        self.bm.verts.ensure_lookup_table()
        return list(self.bm.verts[n0:])

    def face_card(self, box_center, box_size, size, part, face='-Y', art=0,
                  lift=0.012, rot=(0.0, 0.0, 0.0), segments=1, detail=DETAIL_NONE):
        """A card placed just PROUD of one face of a box, rather than at a point.

        Cards are positioned by their centre, so dressing a solid means working
        out where its surface is and offsetting by half its depth — and getting
        that wrong buries the card inside the solid, where it is both occluded
        and unlit. It reads as a black hole rather than as a missing texture,
        which is why it survives review: it looks like a decision.

        Pass the box this card dresses and which face it sits on, and the
        placement is derived instead of guessed.
        """
        cx, cy, cz = box_center
        sx, sy, sz = box_size
        offs = {
            '-Y': ((cx, cy - sy * 0.5 - lift, cz), 'Y'),
            '+Y': ((cx, cy + sy * 0.5 + lift, cz), 'Y'),
            '-Z': ((cx, cy, cz - sz * 0.5 - lift), 'Z'),
            '+Z': ((cx, cy, cz + sz * 0.5 + lift), 'Z'),
        }
        if face not in offs:
            raise ValueError("face_card: face must be one of %s" % sorted(offs))
        centre, axis = offs[face]
        # a card on an underside or a back face has to be turned to look outward,
        # or it is backfacing exactly where it needs to be seen
        flip = face in ('-Z', '+Y')
        return self.card(centre, size, part, axis=axis, art=art, rot=rot,
                         detail=detail, flip=flip, segments=segments)

    def shell(self, centre, radius, azimuth, half_width, z0, z1, part,
              segments=3, art=0, detail=DETAIL_NONE, bulge=1.0):
        """A card BENT around a dome — the leaf-shell of a thing that closes.

        Emitted with the same two-verts-per-row layout a flat card uses, so
        `rig.card_rows` and `rig.weight_chain_strip` address it unchanged and a
        species can swap its cards for shells without touching its rig. The rows
        climb a meridian of the sphere at `centre`, and each row's pair sits
        `half_width` either side of `azimuth` ON that sphere, so a ring of these
        closes into a dome instead of a fan of flat planes standing in a circle.

        A shelter is a form, so it is a mesh; only what repeats on it is drawn.
        """
        cx, cy, cz = centre
        verts = []
        # THE ATLAS ADDRESSES A CARD BY (row, column) and looks those keys up in
        # the group's `corners`. A shell that ships an empty map packs nothing and
        # dies in the UV pass, which is what an empty one did — the layout is the
        # contract, not the geometry.
        corner_keys = {}
        for r in range(segments + 1):
            f = r / float(segments)
            z = z0 + (z1 - z0) * f
            dz = (z - cz) / max(1e-6, radius)
            ring_r = radius * math.sqrt(max(0.0, 1.0 - dz * dz)) * bulge
            row = []
            for col, sgn in enumerate((-1.0, 1.0)):
                a = azimuth + sgn * half_width
                v = self.bm.verts.new(
                    (cx + math.cos(a) * ring_r, cy + math.sin(a) * ring_r, z))
                corner_keys[v] = (r, col)
                row.append(v)
            verts.append(row)
        faces = []
        for r in range(segments):
            faces.append(self.bm.faces.new(
                (verts[r][0], verts[r][1], verts[r + 1][1], verts[r + 1][0])))
        self._tag(faces, part, detail)
        self.groups.append({
            "kind": "card", "part": part, "detail": detail, "art": art,
            "center": (cx, cy, (z0 + z1) * 0.5),
            "size": (half_width * 2.0 * radius, abs(z1 - z0)),
            "axis": 'Y', "segments": segments,
            "faces": faces, "face": faces[0],
            "corners": corner_keys,
        })
        return faces

    def card(self, center, size, part, axis='Y', art=0, rot=(0.0, 0.0, 0.0),
             detail=DETAIL_NONE, flip=False, segments=1):
        """A single flat quad whose TEXTURE carries the form — the grate drawn as
        pixel art, a leaf, a fern frond. Repetition is drawn, never modeled: a
        modeled bar field aliases into mush at gameplay distance while a drawn one
        stays crisp, and the detail stays where an artist can edit it.

        size is (width, height) in metres; axis is the card's facing normal
        ('Y' upright facing -Y like annulus/disc, 'Z' lying flat like a floor
        grate). `art` is a `register_card_art` id: the painter that draws this
        card's RGBA, whose transparent texels become the silhouette. Scale is
        fixed at 1 m = 32 px, so a 2 m grate tile draws into 64x64.

        `segments` splits the card along its LENGTH into that many quads. A quad
        has four corners and cannot fold, so anything that will be rigged — a leaf
        that folds along its rachis, a frond that droops — needs segments for a
        bone chain to have something to move. The card is still painted as ONE
        image; segmenting changes how it MOVES, never where its detail lives."""
        cx, cy, cz = center
        w, h = size[0] / 2.0, size[1] / 2.0
        segments = max(1, int(segments))
        m = None
        if rot != (0.0, 0.0, 0.0):
            # Rotated about the card's own centre, so a fan of fronds keeps every
            # card a clean rectangle in UV space no matter where it points.
            rx, ry, rz = rot
            m = (mathutils.Matrix.Rotation(rz, 3, 'Z')
                 @ mathutils.Matrix.Rotation(ry, 3, 'Y')
                 @ mathutils.Matrix.Rotation(rx, 3, 'X'))

        def place(u, v):
            local = (mathutils.Vector((u, 0.0, v)) if axis != 'Z'
                     else mathutils.Vector((u, v, 0.0)))
            if m is not None:
                local = m @ local
            return self.bm.verts.new((cx + local.x, cy + local.y, cz + local.z))

        rows = []                      # one pair of verts per division, base -> tip
        corner_keys = {}
        for r in range(segments + 1):
            v = -h + (2.0 * h) * (r / float(segments))
            left, right = place(-w, v), place(w, v)
            rows.append((left, right))
            corner_keys[left] = (r, 0)
            corner_keys[right] = (r, 1)
        faces = []
        for i in range(segments):
            l0, r0 = rows[i]
            l1, r1 = rows[i + 1]
            ring = [l0, r0, r1, l1]
            faces.append(self.bm.faces.new(list(reversed(ring)) if flip else ring))
        self._tag(faces, part, detail)
        self.groups.append({
            "kind": "card", "part": part, "detail": detail, "art": art,
            "center": (cx, cy, cz), "size": (size[0], size[1]), "axis": axis,
            "segments": segments, "faces": faces, "face": faces[0],
            "corners": corner_keys,
        })
        return faces

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.faces.index_update()
        self.bm.verts.index_update()
        # serialize the paint groups against final face/vert indices; recalc may
        # flip windings but never reorders faces or verts
        # A GRAFT DELETES FACES, and every group here holds live BMFace refs, so
        # serializing one whose faces were cut away used to raise ReferenceError
        # and take the whole build down. That is why aperture() and the atlas have
        # never composed, and why welded limbs were unreachable.
        #
        # A group's layout is STRUCTURAL — a tube lays out rows of a known length,
        # a box its six named quads — so a group that has lost faces cannot simply
        # be pruned and unwrapped anyway; the rows would misalign and the piece
        # would sample the wrong texels, which is worse than not unwrapping it.
        # Such a group is dropped whole, and its survivors fall through to the
        # per-face path below with every other face the graft created.
        def _alive(f):
            return getattr(f, "is_valid", True)

        def _group_faces(g):
            out = []
            for key in ("side_faces", "faces"):
                v = g.get(key)
                if isinstance(v, dict):
                    out += list(v.values())
                elif isinstance(v, list):
                    for item in v:
                        out += item if isinstance(item, list) else [item]
            for key in ("face", "cap_top", "cap_bottom", "cap_start", "cap_end"):
                if g.get(key) is not None:
                    out.append(g[key])
            for v in (g.get("strips") or {}).values():
                out += list(v)
            return [f for f in out if f is not None]

        # A cut face keeps its SLOT, marked -1. Dropping the whole group was the
        # first fix and it was too coarse: an aperture in a plated shell threw the
        # entire shell onto the flat per-face path and lost its plate detail. The
        # layouts derive position from the slot INDEX, not from the length of the
        # face list, so a hole costs nothing structurally — the row is laid out as
        # it always was and the missing seat is skipped.
        def _fid(f):
            return f.index if (f is not None and _alive(f)) else -1

        wounded = sum(1 for g in self.groups
                      for f in _group_faces(g) if not _alive(f))
        if wounded:
            print("[ATLAS] %d face(s) cut from paint groups by a graft; their "
                  "seats are held open and the rest of each group keeps its "
                  "layout" % wounded)

        serial = []
        for g in self.groups:
            s = {"kind": g["kind"], "part": g["part"], "detail": g["detail"]}
            if "center" in g:
                s["center"] = list(g["center"])
            if g["kind"] == "box":
                s["size"] = list(g["size"])
                s["faces"] = {n: _fid(f) for n, f in g["faces"].items() if _alive(f)}
            elif g["kind"] == "prism":
                s.update(sides=g["sides"], r_top=g["r_top"], r_bot=g["r_bot"],
                         height=g["height"],
                         side_faces=[_fid(f) for f in g["side_faces"]],
                         cap_top=_fid(g["cap_top"]),
                         cap_bottom=_fid(g["cap_bottom"]))
            elif g["kind"] == "annulus":
                s.update(sides=g["sides"], r_out=g["r_out"], r_in=g["r_in"],
                         depth=g["depth"],
                         strips={k: [_fid(f) for f in v] for k, v in g["strips"].items()})
            elif g["kind"] == "tube":
                s.update(sides=g["sides"], rows=g["rows"],
                         seg_len=list(g["seg_len"]), radii=list(g["radii"]),
                         side_faces=[[_fid(f) for f in row]
                                     for row in g["side_faces"]],
                         cap_start=_fid(g["cap_start"]),
                         cap_end=_fid(g["cap_end"]))
            elif g["kind"] == "disc":
                s.update(r=g["r"], face=_fid(g["face"]))
            elif g["kind"] == "card":
                s.update(size=list(g["size"]), axis=g["axis"], art=g["art"],
                         segments=g["segments"],
                         faces=[_fid(f) for f in g["faces"]],
                         face=_fid(g["face"]))
            s["corners"] = {str(vert.index): list(key) if isinstance(key, tuple) else key
                            for vert, key in g["corners"].items()
                            if getattr(vert, "is_valid", True)}
            serial.append(s)

        # EVERY FACE MUST BELONG TO AN ISLAND. Whatever a graft created — the
        # zipper aperture() lays round its cut, the quads bridge() builds between
        # two rings — belongs to no group, and a face in no group carries no UV
        # and samples whatever happens to sit at (0,0) in the atlas. Each one gets
        # its own small island keyed off the part id already stored on the face,
        # so it paints flat in its own colour instead of sampling garbage. Flat is
        # the honest result for a zipper band; it is also the project's own look.
        covered = set()
        for s in serial:
            # the annulus keeps its faces under "strips", and leaving that key out
            # of this sweep reclassified every ring face as loose — they then got
            # redundant per-face islands ON TOP of a perfectly good group layout,
            # which is how a piece that grafts nothing ended up rebuilding
            # differently. Any kind that stores faces under a new key must be added
            # here or it will be quietly re-unwrapped.
            for v in (s.get("strips") or {}).values():
                covered.update(v)
            for key in ("faces", "side_faces"):
                v = s.get(key)
                if isinstance(v, dict):
                    covered.update(v.values())
                elif isinstance(v, list):
                    for item in v:
                        covered.update(item if isinstance(item, list) else [item])
            for key in ("face", "cap_top", "cap_bottom", "cap_start", "cap_end"):
                if isinstance(s.get(key), int) and s[key] >= 0:
                    covered.add(s[key])
        from .palette import PART_IDS
        by_id = {i: n for n, i in PART_IDS.items()}

        def _inherited_part(f):
            """What a graft-created face should be painted.

            aperture() and bridge() build faces without touching the part layer,
            so every one of them reads back as id 0 — and id 0 is simply whatever
            happens to be FIRST in PARTS. Eight sockets cut into the Naturalizer
            turned its whole shell chair-pink that way. A face the graft made grew
            out of the host, so it takes the host's part: walk its edges to a
            neighbour that belongs to a real paint group and copy that.
            """
            for e in f.edges:
                for nb in e.link_faces:
                    if nb is not f and nb.index in covered:
                        return nb[self.part_layer]
            return f[self.part_layer]

        loose = 0
        for f in self.bm.faces:
            if f.index in covered:
                continue
            loose += 1
            c = f.calc_center_median()
            r = max((v.co - c).length for v in f.verts)
            serial.append({
                "kind": "disc", "part": by_id.get(_inherited_part(f),
                                                  next(iter(PART_IDS))),
                "detail": f[self.detail_layer], "center": [c.x, c.y, c.z],
                "r": r, "face": f.index,
                "corners": {str(v.index): i for i, v in enumerate(f.verts)}})
        if loose:
            print("[ATLAS] %d face(s) outside every paint group given their own "
                  "island" % loose)

        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        ob["paint_groups"] = json.dumps(serial)
        bpy.context.collection.objects.link(ob)
        return ob
