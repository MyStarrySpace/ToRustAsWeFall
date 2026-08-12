# ORGANIC GROWTH BUILDERS v2 — executed by build_archetype_pieces.py (exec-include,
# AFTER the palette helpers), OVERRIDING the v1 primitive-stack builders.
#
# THE ALGORITHM (director's spec): organic branches are authored as MEASUREMENT
# SPHERES — chains of (x, y, z, radius) points forming a skeleton graph; chains
# that share a point WELD into junctions — and the actual FACES are generated as
# one CONNECTED surface over that skeleton (Blender Skin modifier), smoothed
# (Subsurf), then decimated back to chunky flat-shaded game facets. Never
# intersecting primitives pretending to be a growth.
#
# Every color routes through the palette authority (CH()/CG()/_dim from the host
# script) — the palette law. Pieces built here set ob["no_atlas"] = 1: they carry
# flat palette materials and skip the atlas texture pass.
# The modelling vocabulary itself lives in paintlib.meshkit, shared with every
# district's piece file so a channels prop and a stacks prop are built the same way.
from paintlib.meshkit import (
    _srgb_lin, _flat_mat, _skin_growth, _stud_spheres, _bev_box, _torus_xz,
    _hs_axis, _hs_tag, hs_prism, hs_tube, hs_torus, hs_bolts, hs_frame,
    hs_inset_panel, hs_sphere, _hs_finish, _bev_box_r, _hex_holes, _honeycomb,
)
import bmesh as _bmesh
import zlib as _zlib
import random as _random


def build_vein_trunk():
    """Concept plate 3 hero organic: the vein-trunk as a CONNECTED growth — a
    skeleton of measurement spheres skinned into one surface: gnarled spine,
    welded side branches, root flare gripping the ground, glowing bulbs budding
    at the roots (docs/concept-prompts/plumbing_power_project.md #VeinTrunk)."""
    spine = [(0.00, 0.05, 0.00, 0.30), (0.07, 0.10, 0.50, 0.24),
             (-0.05, 0.06, 1.00, 0.21), (0.06, 0.09, 1.50, 0.18),
             (-0.04, 0.07, 2.00, 0.15), (0.03, 0.09, 2.50, 0.12),
             (0.12, 0.11, 2.95, 0.08), (0.20, 0.13, 3.35, 0.045)]
    chains = [spine]
    chains.append([spine[3], (0.33, 0.06, 1.68, 0.08), (0.55, 0.08, 1.98, 0.055),
                   (0.70, 0.10, 2.30, 0.03)])
    chains.append([spine[2], (-0.30, 0.02, 1.15, 0.07), (-0.52, 0.05, 1.42, 0.04)])
    chains.append([spine[5], (-0.25, 0.04, 2.68, 0.05), (-0.40, 0.06, 2.98, 0.028)])
    for (dx, dy) in ((0.42, 0.14), (-0.46, 0.08), (0.24, -0.36), (-0.28, -0.32), (0.04, 0.44)):
        chains.append([spine[0], (dx, 0.05 + dy, 0.05, 0.11),
                       (dx * 1.45, 0.05 + dy * 1.45, 0.02, 0.05)])
    ob = _skin_growth("VeinTrunk", chains, decimate=0.10)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    for m in (bark, blue, violet):
        ob.data.materials.append(m)
    _stud_spheres(ob, [
        (0.30, -0.16, 0.14, 0.13, 1, 0.8), (-0.27, -0.20, 0.11, 0.10, 2, 0.8),
        (0.05, -0.28, 0.13, 0.11, 1, 0.8), (-0.10, -0.24, 0.28, 0.08, 2, 0.8),
        (0.16, -0.10, 1.70, 0.055, 1, 0.9), (-0.09, -0.08, 2.42, 0.05, 2, 0.9),
        (0.22, 0.02, 0.55, 0.09, 0, 0.9), (-0.20, 0.0, 1.32, 0.08, 0, 0.9),
        (0.16, 0.02, 2.18, 0.065, 0, 0.9)])          # last three: bark nodules
    ob["no_atlas"] = 1
    return ob


def build_wall_tracery():
    """Concept plates 1/3: the wall panel CLAIMED by the vein system — one
    connected growth over an iron plate: three climbing trunks, two pointed
    arches (chains bending through arch points, skinned smooth), connector
    veins, root spread, biolume buds at the junctions."""
    plate_h = 3.2
    y = -0.02                                        # growth half-embedded in the plate front
    left = [(-1.05, y, 0.0, 0.13), (-1.0, y, 0.55, 0.115), (-1.08, y, 1.1, 0.10),
            (-1.02, y, 1.65, 0.09), (-1.06, y, 2.2, 0.07), (-1.03, y, 2.6, 0.05)]
    mid = [(0.0, y, 0.0, 0.17), (0.05, y, 0.6, 0.15), (-0.04, y, 1.2, 0.135),
           (0.03, y, 1.8, 0.115), (-0.02, y, 2.4, 0.09), (0.02, y, 2.95, 0.06)]
    right = [(1.05, y, 0.0, 0.13), (1.01, y, 0.55, 0.115), (1.07, y, 1.1, 0.10),
             (1.03, y, 1.65, 0.09), (1.06, y, 2.2, 0.07), (1.04, y, 2.55, 0.05)]
    chains = [left, mid, right]
    chains.append([left[3], (-0.88, y, 2.08, 0.075), (-0.68, y, 2.42, 0.065),
                   (-0.52, y, 2.62, 0.055), (-0.36, y, 2.44, 0.065),
                   (-0.16, y, 2.1, 0.075), mid[3]])
    chains.append([mid[3], (0.16, y, 2.1, 0.075), (0.36, y, 2.44, 0.065),
                   (0.52, y, 2.62, 0.055), (0.68, y, 2.42, 0.065),
                   (0.88, y, 2.08, 0.075), right[3]])
    chains.append([left[1], (-0.6, y, 0.72, 0.06), (-0.25, y, 0.55, 0.055), mid[1]])
    chains.append([mid[2], (0.45, y, 1.05, 0.055), (0.78, y, 1.18, 0.05), right[2]])
    chains.append([left[0], (-1.35, y, 0.08, 0.07), (-1.45, y, 0.02, 0.04)])
    chains.append([right[0], (1.35, y, 0.08, 0.07), (1.45, y, 0.02, 0.04)])
    chains.append([mid[0], (0.3, y, 0.06, 0.09), (0.5, y, 0.02, 0.045)])
    chains.append([mid[0], (-0.3, y, 0.06, 0.09), (-0.5, y, 0.02, 0.045)])
    ob = _skin_growth("WallTracery", chains, decimate=0.12)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    iron = _flat_mat("tracery_plate_m", CH("iron_dark"), rough=0.7)
    for m in (bark, blue, violet, iron):
        ob.data.materials.append(m)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    _bev_box(bm, (0.0, 0.11, plate_h / 2.0), (3.0, 0.22, plate_h), 3, bevel=0.02)
    bm.to_mesh(ob.data)
    bm.free()
    _stud_spheres(ob, [
        (-0.52, -0.12, 2.62, 0.07, 1, 0.85), (0.52, -0.12, 2.62, 0.06, 2, 0.85),
        (-0.25, -0.12, 0.58, 0.075, 2, 0.85), (0.78, -0.12, 1.2, 0.065, 1, 0.85),
        (-1.06, -0.12, 1.55, 0.06, 1, 0.85), (0.04, -0.12, 1.82, 0.05, 2, 0.85),
        (0.05, -0.1, 0.95, 0.08, 0, 0.9), (-1.02, -0.1, 0.8, 0.065, 0, 0.9)])
    ob["no_atlas"] = 1
    return ob


def build_biolume_cluster():
    """Concept plates 1/3/4: the cluster as one organism — a skinned mycelium
    (root mound with stems branching from a shared root point) budding glowing
    caps, plus two angular crystal shards (crystals are legitimately faceted)."""
    root = (0.0, 0.0, 0.03, 0.12)
    caps = [(-0.14, 0.06, 0.26, 0.10, 1), (0.08, -0.10, 0.34, 0.12, 2),
            (0.16, 0.12, 0.20, 0.08, 1), (-0.02, 0.16, 0.16, 0.07, 2),
            (0.02, -0.02, 0.44, 0.13, 1), (0.20, -0.16, 0.14, 0.07, 2)]
    chains = []
    for (cx, cy, cz, cr, _mi) in caps:
        chains.append([root, (cx * 0.6, cy * 0.6, cz * 0.55, 0.045), (cx, cy, cz - 0.02, 0.028)])
    for (dx, dy) in ((0.3, 0.1), (-0.28, 0.14), (0.05, -0.32), (-0.15, -0.25)):
        chains.append([root, (dx, dy, 0.02, 0.06)])
    ob = _skin_growth("BiolumeCluster", chains, decimate=0.34, jitter=0.012, sub_levels=2)
    bark = _flat_mat("vein_bark_m", CH("vein_bark"))
    blue = _flat_mat("biolume_blue_m", _dim(CH("biolume_blue"), 0.62), CH("biolume_blue"), 1.4)
    violet = _flat_mat("biolume_violet_m", _dim(CH("biolume_violet"), 0.62), CH("biolume_violet"), 1.4)
    for m in (bark, blue, violet):
        ob.data.materials.append(m)
    studs = [(cx, cy, cz + 0.02, cr * 0.8, mi, 0.5) for (cx, cy, cz, cr, mi) in caps]
    _stud_spheres(ob, studs)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for (px, py, h, r, mi, tilt) in ((-0.24, -0.12, 0.42, 0.075, 1, 0.28),
                                     (0.26, 0.02, 0.32, 0.06, 2, -0.22)):
        ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=5,
                                     radius1=r, radius2=0.012, depth=h)
        mat = (mathutils.Matrix.Translation((px, py, h / 2.0))
               @ mathutils.Matrix.Rotation(tilt, 4, 'X'))
        _bmesh.ops.transform(bm, matrix=mat, verts=ret["verts"])
        for f in set(f for v in ret["verts"] for f in v.link_faces):
            f.material_index = mi
            f.smooth = False
    bm.to_mesh(ob.data)
    bm.free()
    ob["no_atlas"] = 1
    return ob


def build_portal_ring_ornate():
    """Concept plate 2 hero (docs/concept-prompts/plumbing_power_project.md):
    the curecumin portal BODY as real machining — a faceted iron torus, an inner
    PURPLE neon ring (portal law; dormant portals use the plain 'portal' piece),
    beveled greeble blocks aligned radially around the rim, and a beveled mount.
    The live lens/garden view stays a separate gameplay object."""
    z_c = 1.55
    mesh = bpy.data.meshes.new("PortalRingOrnate_m")
    bm = _bmesh.new()
    _torus_xz(bm, 1.05, 0.20, 12, 8, 0, z_c=z_c)                  # the machined ring
    _torus_xz(bm, 0.84, 0.055, 24, 8, 2, y_off=-0.10, z_c=z_c)    # the neon, proud of the face
    for i in range(12):                                           # radial greeble blocks
        a = math.tau * i / 12.0
        big = (i % 3 == 0)
        r = 1.05 + (0.18 if big else 0.11)
        size = (0.30, 0.38, 0.30) if big else (0.20, 0.30, 0.22)
        _bev_box(bm, (r * math.cos(a), 0.0, z_c + r * math.sin(a)), size, 1,
                 rot_y=-a, bevel=0.03)
    _bev_box(bm, (0.0, 0.0, z_c + 1.32), (0.26, 0.44, 0.22), 1, bevel=0.03)   # crown lug
    for sx in (-0.5, 0.5):                                        # mount legs to the ground
        _bev_box(bm, (sx, 0.0, 0.42), (0.30, 0.42, 0.84), 0, bevel=0.03)
    _bev_box(bm, (0.0, 0.0, 0.10), (1.6, 0.55, 0.20), 1, bevel=0.03)          # base slab
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("PortalRingOrnate", mesh)
    scene.collection.objects.link(ob)
    iron = _flat_mat("portal_iron_m", CH("iron"), rough=0.6)
    greeble = _flat_mat("portal_greeble_m", _dim(CH("iron"), 1.25), rough=0.55)
    neon = _flat_mat("portal_neon_m", _dim(CG("portal_transit"), 0.6),
                     CG("portal_transit"), 1.5)
    for m in (iron, greeble, neon):
        ob.data.materials.append(m)
    ob["no_atlas"] = 1
    return ob
