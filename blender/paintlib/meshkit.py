# MESH KIT — the shared modelling vocabulary every district's piece file builds with.
#
# Two grammars live here, both producing chunky flat-shaded game facets:
#   ORGANIC GROWTH (director's algorithm): a branch is authored as MEASUREMENT
#   SPHERES — chains of (x, y, z, radius) whose shared points WELD into junctions —
#   and the faces are generated as ONE CONNECTED surface over that skeleton
#   (Skin -> Subsurf -> Decimate). Never intersecting primitives pretending to be
#   a growth.
#   HARD SURFACE: a prop reads as something MADE. Every helper chamfers its edges,
#   parts join through visible connections (flanges with bolt rings, brackets,
#   straps), active faces are RECESSED into frames, and a pipe end is an open bore
#   you can see into.
#
# Colours never appear here: a piece's palette is the DISTRICT's business, passed
# in as rgb. `_flat_mat` converts sRGB palette hexes to Blender's LINEAR sockets
# once, for everyone (feeding sRGB straight in washes every dark tone pale).
#
# Pieces built from the flat-material helpers set ob["no_atlas"] = 1: they carry
# palette materials directly and skip the atlas texture pass.

import bmesh as _bmesh
import bpy
import math
import mathutils
import random as _random
import zlib as _zlib

__all__ = (
    "srgb_lin", "flat_mat", "skin_growth", "stud_spheres", "bev_box", "torus_xz",
    "hs_axis", "hs_tag", "hs_prism", "hs_tube", "hs_torus", "hs_bolts", "hs_frame",
    "hs_inset_panel", "hs_sphere", "hs_finish", "bev_box_r", "hex_holes", "honeycomb",
)

def _srgb_lin(c):
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def _flat_mat(name, rgb, emit=None, emit_strength=2.0, rough=0.85):
    """Palette hexes are sRGB; Blender's Base Color / Emission sockets are LINEAR —
    feeding sRGB floats straight in washes every dark tone pale (the mauve-trunk
    bug). Convert here, once, for all flat-material pieces."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*_srgb_lin(rgb), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*_srgb_lin(emit), 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return m


def _skin_growth(name, chains, decimate=0.10, jitter=0.02, sub_levels=2):
    """Skeleton spheres -> connected surface. chains: [[(x,y,z,r), ...], ...];
    identical coordinates weld (that's how a branch joins its trunk)."""
    rng = _random.Random(_zlib.crc32(name.encode()))
    mesh = bpy.data.meshes.new(name + "_m")
    bm = _bmesh.new()
    vmap = {}
    radii = []
    for chain in chains:
        prev = None
        for (x, y, z, r) in chain:
            key = (round(x, 4), round(y, 4), round(z, 4))
            if key in vmap:
                v = vmap[key]
            else:
                jx = rng.uniform(-jitter, jitter)
                jy = rng.uniform(-jitter, jitter)
                v = bm.verts.new((x + jx, y + jy, z))
                vmap[key] = v
                radii.append(r)
            if prev is not None and prev is not v:
                try:
                    bm.edges.new((prev, v))
                except ValueError:
                    pass                     # edge already exists (shared segment)
            prev = v
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.modifiers.new("Skin", 'SKIN')
    sub = ob.modifiers.new("Sub", 'SUBSURF')
    sub.levels = sub_levels
    dec = ob.modifiers.new("Dec", 'DECIMATE')
    dec.ratio = decimate
    for i, sv in enumerate(ob.data.skin_vertices[0].data):
        r = radii[i] if i < len(radii) else 0.05
        sv.radius = (r, r)
    ob.data.skin_vertices[0].data[0].use_root = True
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    ob.modifiers.clear()
    old = ob.data
    ob.data = baked
    bpy.data.meshes.remove(old)
    for p in baked.polygons:
        p.use_smooth = False
    return ob


def _stud_spheres(ob, studs):
    """Bud emissive/organ spheres onto a baked growth: [(x,y,z,r,mat_i,squash)]."""
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for (x, y, z, r, mi, squash) in studs:
        ret = _bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        for v in ret["verts"]:
            v.co.z *= squash
            v.co += mathutils.Vector((x, y, z))
        faces = set(f for v in ret["verts"] for f in v.link_faces)
        for f in faces:
            f.material_index = mi
            f.smooth = False
    bm.to_mesh(ob.data)
    bm.free()


def _bev_box(bm, center, size, mat_i, rot_y=0.0, bevel=0.025):
    """A beveled block (real chamfers catch the light — the anti-'raw primitive').
    rot_y aligns it radially. Material is tagged by face-table position: the bevel
    op DELETES the original corner verts, so holding vert refs across it dies with
    'BMesh data has been removed' — every face from the pre-call count onward is
    this box's geometry, bevelled or not."""
    n_before = len(bm.faces)
    ret = _bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat = (mathutils.Matrix.Translation(mathutils.Vector(center))
           @ mathutils.Matrix.Rotation(rot_y, 4, 'Y')
           @ mathutils.Matrix.Diagonal(mathutils.Vector(size)).to_4x4())
    _bmesh.ops.transform(bm, matrix=mat, verts=verts)
    edges = list(set(e for v in verts for e in v.link_edges))
    _bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type='OFFSET',
                     segments=1, profile=0.5, affect='EDGES', clamp_overlap=True)
    bm.faces.ensure_lookup_table()
    for f in bm.faces[n_before:]:
        f.material_index = mat_i
        f.smooth = False


def _torus_xz(bm, major_r, minor_r, major_segs, minor_segs, mat_i, y_off=0.0, z_c=0.0):
    """A faceted torus lying in the XZ plane (ring axis = Y, the upright portal
    convention: faces -Y -> Godot +Z). Low segment counts = the machined look."""
    rings = []
    for i in range(major_segs):
        a = math.tau * i / major_segs
        ring = []
        for j in range(minor_segs):
            b = math.tau * j / minor_segs
            rr = major_r + minor_r * math.cos(b)
            ring.append(bm.verts.new((rr * math.cos(a), y_off + minor_r * math.sin(b),
                                      z_c + rr * math.sin(a))))
        rings.append(ring)
    for i in range(major_segs):
        r0 = rings[i]
        r1 = rings[(i + 1) % major_segs]
        for j in range(minor_segs):
            k = (j + 1) % minor_segs
            f = bm.faces.new((r0[j], r0[k], r1[k], r1[j]))
            f.material_index = mat_i
            f.smooth = False


# ---- the pieces --------------------------------------------------------------------------

def _hs_axis(axis):
    if axis == 'Z':
        return mathutils.Matrix.Identity(4)
    if axis == 'Y':
        return mathutils.Matrix.Rotation(-math.pi / 2.0, 4, 'X')
    return mathutils.Matrix.Rotation(math.pi / 2.0, 4, 'Y')      # 'X'


def _hs_tag(bm, n_before, mat_i):
    bm.faces.ensure_lookup_table()
    for f in bm.faces[n_before:]:
        f.material_index = mat_i
        f.smooth = False


def hs_prism(bm, center, r_top, r_bot, h, mat_i, sides=8, bevel=0.02, axis='Z'):
    """Chamfered cylinder/prism along `axis`. sides<=12 chamfers every edge (the
    machined-facet look); more sides chamfer only the cap rims."""
    n0 = len(bm.faces)
    ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=sides,
                                 radius1=r_bot, radius2=r_top, depth=h)
    verts = ret["verts"]
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ _hs_axis(axis)
    _bmesh.ops.transform(bm, matrix=m, verts=verts)
    if bevel > 0.0:
        edges = list(set(e for v in verts for e in v.link_edges))
        if sides > 12:
            ax = (m.to_3x3() @ mathutils.Vector((0, 0, 1))).normalized()
            edges = [e for e in edges
                     if any(abs(f.normal.dot(ax)) > 0.7 for f in e.link_faces)]
        _bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type='OFFSET',
                         segments=1, profile=0.5, affect='EDGES', clamp_overlap=True)
    _hs_tag(bm, n0, mat_i)


def hs_tube(bm, center, r_out, r_in, h, mat_i, sides=12, axis='Z'):
    """An OPEN tube (visible bore): outer wall, inner wall, two flat rims."""
    n0 = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ _hs_axis(axis)
    rings = {}
    for (tag, r, z) in (("ot", r_out, h / 2), ("ob", r_out, -h / 2),
                        ("it", r_in, h / 2), ("ib", r_in, -h / 2)):
        ring = []
        for i in range(sides):
            a = math.tau * i / sides
            co = m @ mathutils.Vector((r * math.cos(a), r * math.sin(a), z))
            ring.append(bm.verts.new(co))
        rings[tag] = ring
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((rings["ob"][i], rings["ob"][j], rings["ot"][j], rings["ot"][i]))
        bm.faces.new((rings["it"][i], rings["it"][j], rings["ib"][j], rings["ib"][i]))
        bm.faces.new((rings["ot"][i], rings["ot"][j], rings["it"][j], rings["it"][i]))
        bm.faces.new((rings["ib"][i], rings["ib"][j], rings["ob"][j], rings["ob"][i]))
    _hs_tag(bm, n0, mat_i)


def hs_torus(bm, center, major_r, minor_r, mat_i, major_segs=12, minor_segs=8, axis='Y'):
    """Faceted torus; axis is the ring's rotational axis (a wheel lying flat has
    axis 'Z'; an upright portal/wheel facing -Y has axis 'Y')."""
    n0 = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ _hs_axis(axis)
    rings = []
    for i in range(major_segs):
        a = math.tau * i / major_segs
        ring = []
        for j in range(minor_segs):
            b = math.tau * j / minor_segs
            rr = major_r + minor_r * math.cos(b)
            co = m @ mathutils.Vector((rr * math.cos(a), rr * math.sin(a),
                                       minor_r * math.sin(b)))
            ring.append(bm.verts.new(co))
        rings.append(ring)
    for i in range(major_segs):
        r0, r1 = rings[i], rings[(i + 1) % major_segs]
        for j in range(minor_segs):
            k = (j + 1) % minor_segs
            bm.faces.new((r0[j], r0[k], r1[k], r1[j]))
    _hs_tag(bm, n0, mat_i)


def hs_bolts(bm, center, ring_r, count, mat_i, bolt_r=0.028, bolt_h=0.05,
             axis='Z', phase=0.0):
    """A bolt ring — the assembly cue at every flange/frame joint."""
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ _hs_axis(axis)
    for i in range(count):
        a = phase + math.tau * i / count
        co = m @ mathutils.Vector((ring_r * math.cos(a), ring_r * math.sin(a), 0.0))
        n0 = len(bm.faces)
        ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=6,
                                     radius1=bolt_r, radius2=bolt_r * 0.82, depth=bolt_h)
        bmat = mathutils.Matrix.Translation(co) @ _hs_axis(axis)
        _bmesh.ops.transform(bm, matrix=bmat, verts=ret["verts"])
        _hs_tag(bm, n0, mat_i)


def hs_frame(bm, center, w, h, bar, depth, mat_i, bevel=0.02):
    """A rectangular frame (facing -Y): four chamfered bars around an opening."""
    cx, cy, cz = center
    _bev_box(bm, (cx, cy, cz + h / 2 - bar / 2), (w, depth, bar), mat_i, bevel=bevel)
    _bev_box(bm, (cx, cy, cz - h / 2 + bar / 2), (w, depth, bar), mat_i, bevel=bevel)
    _bev_box(bm, (cx - w / 2 + bar / 2, cy, cz), (bar, depth, h - 2 * bar), mat_i, bevel=bevel)
    _bev_box(bm, (cx + w / 2 - bar / 2, cy, cz), (bar, depth, h - 2 * bar), mat_i, bevel=bevel)


def hs_inset_panel(bm, center, size, lip, recess, mat_frame, mat_panel, bevel=0.02):
    """A framed RECESSED panel facing -Y: the active face sits INSIDE its frame."""
    cx, cy, cz = center
    w, d, h = size
    hs_frame(bm, (cx, cy, cz), w, h, lip, d, mat_frame, bevel=bevel)
    _bev_box(bm, (cx, cy + recess, cz), (w - 2 * lip + 0.02, d * 0.5, h - 2 * lip + 0.02),
             mat_panel, bevel=min(bevel, 0.012))


def hs_sphere(bm, center, r, mat_i, subdiv=2):
    n0 = len(bm.faces)
    ret = _bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    _bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation(mathutils.Vector(center)),
                         verts=ret["verts"])
    _hs_tag(bm, n0, mat_i)


def _hs_finish(name, bm, mats):
    mesh = bpy.data.meshes.new(name + "_m")
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    for mt in mats:
        ob.data.materials.append(mt)
    ob["no_atlas"] = 1
    return ob


# ---- exemplar reworks (the idiom the other pieces follow) --------------------------------


def _bev_box_r(bm, center, size, mat_i, rot=(0.0, 0.0, 0.0), bevel=0.02):
    """_bev_box with full rotation (rx, ry, rz) — radial wedges (rz), tilted
    console faces (rx). Material tagged by face-table position (bevel deletes
    the original verts)."""
    n0 = len(bm.faces)
    ret = _bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rx, ry, rz = rot
    m = (mathutils.Matrix.Translation(mathutils.Vector(center))
         @ mathutils.Matrix.Rotation(rz, 4, 'Z')
         @ mathutils.Matrix.Rotation(ry, 4, 'Y')
         @ mathutils.Matrix.Rotation(rx, 4, 'X')
         @ mathutils.Matrix.Diagonal(mathutils.Vector(size)).to_4x4())
    _bmesh.ops.transform(bm, matrix=m, verts=verts)
    if bevel > 0.0:
        edges = list(set(e for v in verts for e in v.link_edges))
        _bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type='OFFSET',
                         segments=1, profile=0.5, affect='EDGES', clamp_overlap=True)
    _hs_tag(bm, n0, mat_i)


def _hex_holes(bm, centers, r, h, mat_i, axis='Z'):
    """Hexagonal hole read: near-black hex plugs sunk into a panel (the plates
    use honeycomb mesh everywhere square grids would have gone)."""
    for c in centers:
        hs_prism(bm, c, r, r, h, mat_i, sides=6, bevel=0.0, axis=axis)


def _honeycomb(cx, cy, cols, rows, pitch):
    """Honeycomb centre offsets in a plane (returned as (dx, dy) pairs)."""
    out = []
    for j in range(rows):
        for i in range(cols):
            out.append((cx + (i - (cols - 1) / 2.0) * pitch + (pitch / 2.0 if j % 2 else 0.0),
                        cy + (j - (rows - 1) / 2.0) * pitch * 0.87))
    return out


# Public names. The underscore-prefixed originals stay so the archetype chain's
# existing builders keep reading exactly as they were written.
srgb_lin = _srgb_lin
flat_mat = _flat_mat
skin_growth = _skin_growth
stud_spheres = _stud_spheres
bev_box = _bev_box
torus_xz = _torus_xz
hs_axis = _hs_axis
hs_tag = _hs_tag
hs_finish = _hs_finish
bev_box_r = _bev_box_r
hex_holes = _hex_holes
honeycomb = _honeycomb
