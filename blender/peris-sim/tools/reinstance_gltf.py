"""
reinstance_gltf.py v2 — Restore GPU instancing in a glTF/OBJ that lost it.

Blockbench round-trips (and OBJ exports) destroy mesh-instancing: every "copy"
of a leaf becomes a separate Mesh datablock even though they're topologically
identical. This tool detects topology groups (same vertex / edge / face
counts) and collapses each group to one canonical mesh.

v2 changes vs v1:
- Uses Kabsch/SVD (Procrustes) to recover per-instance ROTATION, not just
  centroid+scale. v1 lost leaf orientation; v2 preserves it.
- Re-binds materials to texture PNGs from the plant's subfolder
  (plants/{plant_name}/{TexName}.png) when found.
- Sets all texture node interpolation to 'Closest' so the exported glTF
  uses NEAREST filtering (correct for pixel-art textures, no blur).

USE THIS ONLY WHEN:
- You did NOT manually edit individual leaf/flower shapes
- Per-instance variation in the input is just generator noise (different
  positions, rotations, scales of the same underlying template)

If you actually want each leaf to have a unique sculpted shape, use the
'identical' match mode instead (only collapses bit-identical meshes).

USAGE (from Blender Python console or scripted run):
    import sys
    sys.path.append('blender/peris-sim/tools')
    import reinstance_gltf as ri
    ri.reinstance_file(
        in_path='peace_lily.obj',
        out_path='peace_lily_instanced.gltf',
        match='topology',
        texture_search_dirs=['plants/peace_lily'],
    )

match modes:
  'identical'        — strict: meshes must be geometrically identical (no
                       transform recovery needed)
  'topology'         — anything with the same vert/edge/face counts (best
                       instancing ratio; Procrustes recovers transform)
"""

import bpy
import hashlib
import os
import math
from mathutils import Vector, Matrix
from collections import defaultdict

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def _topology_signature(mesh):
    if not mesh.vertices:
        return None
    face_sizes = sorted(len(p.vertices) for p in mesh.polygons)
    return ('topo', len(mesh.vertices), len(mesh.edges), len(mesh.polygons), tuple(face_sizes))


def _identical_signature(mesh, precision=4):
    if not mesh.vertices:
        return None
    c = sum((v.co for v in mesh.vertices), Vector()) / len(mesh.vertices)
    dists = sorted(round((v.co - c).length, precision) for v in mesh.vertices)
    edge_lens = sorted(
        round((mesh.vertices[e.vertices[0]].co - mesh.vertices[e.vertices[1]].co).length, precision)
        for e in mesh.edges
    )
    face_sizes = sorted(len(p.vertices) for p in mesh.polygons)
    key = ('ident', len(mesh.vertices), len(mesh.edges), len(mesh.polygons),
           tuple(dists), tuple(edge_lens), tuple(face_sizes))
    return hashlib.md5(str(key).encode()).hexdigest()


def _procrustes_transform(canonical_verts, this_verts):
    """Find uniform scale s, rotation R (3x3), translation t such that:
        this_verts[i] ≈ s * R @ canonical_verts[i] + t

    Both arrays must be Nx3, same N, with corresponding indices (which is the
    case when both meshes came from the same generator template).

    Returns (s, R_matrix, t_vector). R_matrix is a mathutils.Matrix(3x3),
    t_vector is a mathutils.Vector.
    """
    if not HAS_NUMPY:
        # Fallback: scale + translation only (no rotation recovery)
        c_centroid = sum((Vector(v) for v in canonical_verts), Vector()) / len(canonical_verts)
        t_centroid = sum((Vector(v) for v in this_verts), Vector()) / len(this_verts)
        c_centered = [Vector(v) - c_centroid for v in canonical_verts]
        t_centered = [Vector(v) - t_centroid for v in this_verts]
        c_norm = math.sqrt(sum(v.length_squared for v in c_centered))
        t_norm = math.sqrt(sum(v.length_squared for v in t_centered))
        s = (t_norm / c_norm) if c_norm > 1e-9 else 1.0
        R = Matrix.Identity(3)
        t = t_centroid - R @ c_centroid * s
        return s, R, t

    C = np.array(canonical_verts, dtype=np.float64)
    T = np.array(this_verts, dtype=np.float64)
    c_centroid = C.mean(axis=0)
    t_centroid = T.mean(axis=0)
    C_c = C - c_centroid
    T_c = T - t_centroid

    # Uniform scale
    c_norm = np.sqrt((C_c ** 2).sum())
    t_norm = np.sqrt((T_c ** 2).sum())
    s = (t_norm / c_norm) if c_norm > 1e-9 else 1.0

    # Scale-normalized canonical, then rotation via Kabsch
    C_scaled = C_c * s
    H = C_scaled.T @ T_c  # 3x3 cross-covariance
    U, _, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1.0, 1.0, d])
    R = Vt.T @ D @ U.T  # 3x3 rotation matrix

    # Translation: t_centroid - s * R @ c_centroid
    R_mat = Matrix((tuple(R[0]), tuple(R[1]), tuple(R[2])))
    t = Vector(t_centroid) - R_mat @ (Vector(c_centroid) * s)
    return s, R_mat, t


def _candidate_texture_names(img_name):
    """Return a list of filename candidates for an image, in priority order.

    Strips common debug/prefix patterns and tries multiple suffixes.
    """
    # Base name without extension
    base = img_name
    if base.lower().endswith('.png'):
        base = base[:-4]

    candidates = [base]
    # Strip common debug prefixes I've used during development
    for prefix in ['tex_audit_jas_', 'tex_audit_pothos_', 'tex_audit_',
                    'tex_debug_', 'debug_']:
        if base.startswith(prefix):
            candidates.append(base[len(prefix):])
    # Also try removing any trailing _NNN suffix (e.g. PotTex.001 -> PotTex)
    if '.' in base:
        parts = base.rsplit('.', 1)
        if parts[1].isdigit():
            candidates.append(parts[0])
    return [c + '.png' for c in candidates]


def _set_textures_nearest_and_relink(texture_search_dirs, verbose=False):
    """Set every ShaderNodeTexImage to 'Closest' interpolation. Rename images
    to strip dev prefixes (tex_audit_*, debug_*), then relink to PNGs found
    in any of `texture_search_dirs`.

    Renaming is critical: the image's name becomes the filename in the
    exported glTF, so without renaming the export writes 'tex_audit_jas_*.png'
    instead of the clean 'JasmineLeafTex.png' the user expects.
    """
    # STEP 1: Rename images to strip dev prefixes (CRITICAL — affects glTF output filename)
    rename_prefixes = ['tex_audit_jas_', 'tex_audit_pothos_', 'tex_audit_',
                        'tex_debug_', 'debug_']
    renamed = []
    for img in bpy.data.images:
        if img.name in ('Render Result', 'Viewer Node'):
            continue
        new_name = img.name
        for prefix in rename_prefixes:
            if new_name.startswith(prefix):
                new_name = new_name[len(prefix):]
                break
        if new_name != img.name:
            renamed.append((img.name, new_name))
            img.name = new_name

    # STEP 2: Relink each image to the subfolder PNG by clean name match
    n_relinked = 0
    n_missing = []
    for img in bpy.data.images:
        if img.name in ('Render Result', 'Viewer Node'):
            continue
        candidates = _candidate_texture_names(img.name)
        found_path = None
        for d in texture_search_dirs:
            for cand in candidates:
                path = os.path.join(d, cand)
                if os.path.exists(path):
                    found_path = path
                    break
            if found_path: break
        if found_path:
            img.filepath = found_path
            img.source = 'FILE'
            try:
                img.reload()
            except Exception:
                pass
            n_relinked += 1
        elif texture_search_dirs:
            n_missing.append((img.name, candidates))

    # STEP 3: Set all texture nodes to Closest (nearest filter for pixel art)
    n_set = 0
    for mat in bpy.data.materials:
        if not mat.node_tree: continue
        for node in mat.node_tree.nodes:
            if node.bl_idname == 'ShaderNodeTexImage':
                node.interpolation = 'Closest'
                n_set += 1

    if verbose:
        if renamed:
            print(f"  Renamed {len(renamed)} images to strip prefixes:")
            for old, new in renamed[:5]:
                print(f"    '{old}' → '{new}'")
        print(f"  Set {n_set} texture nodes to Closest; relinked {n_relinked} images")
        if n_missing:
            print(f"  WARNING: {len(n_missing)} images not found in search dirs:")
            for name, cands in n_missing[:5]:
                print(f"    {name} (tried: {cands})")
    return n_set, n_relinked


def reinstance(mesh_objects, match='topology', verbose=True):
    """Deduplicate meshes. For matching groups, replace with canonical and
    bake the per-instance transform (uniform scale + rotation + translation)
    into the Object's transform via Procrustes alignment.
    """
    if not HAS_NUMPY and verbose:
        print("WARNING: numpy not available — Procrustes rotation recovery disabled. "
              "Leaves may face the wrong direction. Install numpy for proper handling.")

    # First pass: group by signature
    obj_sigs = []
    for obj in mesh_objects:
        if obj.type != 'MESH' or not obj.data.vertices:
            obj_sigs.append((obj, None))
            continue
        if match == 'topology':
            sig = _topology_signature(obj.data)
        elif match == 'identical':
            sig = _identical_signature(obj.data)
        else:
            raise ValueError(f"unknown match mode {match!r}")
        obj_sigs.append((obj, sig))

    groups = defaultdict(list)
    for obj, sig in obj_sigs:
        if sig is not None:
            groups[sig].append(obj.name)

    if verbose:
        print(f"\nMatch mode: {match!r}")
        for sig, names in sorted(groups.items(), key=lambda kv: -len(kv[1])):
            if len(names) > 1:
                sample = ', '.join(names[:3])
                more = '...' if len(names) > 3 else ''
                print(f"  ×{len(names)}: {sample}{more}")

    # Second pass: deduplicate
    sig_canonical = {}  # sig -> (Mesh, [vertex coords list])
    n_replaced = 0
    for obj, sig in obj_sigs:
        if sig is None:
            continue
        if sig not in sig_canonical:
            verts = [tuple(v.co) for v in obj.data.vertices]
            sig_canonical[sig] = (obj.data, verts)
            continue

        canonical_mesh, canonical_verts = sig_canonical[sig]
        if obj.data == canonical_mesh:
            continue

        # Extract this object's verts before swapping the data
        this_verts = [tuple(v.co) for v in obj.data.vertices]

        # Compute the transform that maps canonical-mesh-space to this-mesh-space
        # This transform, when applied to the object, makes the canonical mesh
        # render at the same world position as the old mesh did.
        # ASSUMES: obj.matrix_world was effectively identity (true for OBJ imports
        # and Blockbench-exported glTFs where transforms are baked into vertices).
        s, R, t = _procrustes_transform(canonical_verts, this_verts)

        if match == 'identical':
            s = 1.0  # identical match: no scale, just translation; R should be identity

        # Compose 4x4 transform: T * R * S
        # transform maps canonical_verts → this_verts in mesh-local space
        local_transform = Matrix.Translation(t) @ R.to_4x4() @ Matrix.Scale(s, 4)

        # New matrix_world: old_matrix_world @ local_transform
        new_matrix_world = obj.matrix_world @ local_transform

        # Decompose explicitly into loc/rot/scale and set those properties
        # (relying on matrix_world setter for decomposition can be unreliable)
        loc, rot, scale = new_matrix_world.decompose()
        obj.location = loc
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = rot
        obj.scale = scale

        old_data = obj.data
        obj.data = canonical_mesh
        if old_data.users == 0:
            bpy.data.meshes.remove(old_data)
        n_replaced += 1

    n_unique = len(sig_canonical)
    return n_replaced, n_unique, dict(groups)


def _find_view3d_override():
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                for region in area.regions:
                    if region.type == 'WINDOW':
                        return {'screen': screen, 'area': area, 'region': region}
    return None


def reinstance_file(in_path, out_path, match='topology',
                     texture_search_dirs=None, verbose=True):
    """Import any mesh file → reinstance → export as glTF.

    in_path: .gltf / .glb / .obj
    out_path: .gltf (separate format — writes .gltf + .bin + texture .pngs)
    match: 'topology' or 'identical'
    texture_search_dirs: list of directories to look for texture PNGs by name.
                         Materials will be relinked if found.
    """
    if texture_search_dirs is None:
        texture_search_dirs = []

    # Clear current scene without losing 3D viewport
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                        bpy.data.armatures, bpy.data.curves):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)

    override = _find_view3d_override()
    if override is None:
        raise RuntimeError("No 3D viewport found — open Blender with default UI")

    ext = in_path.lower().rsplit('.', 1)[-1]
    with bpy.context.temp_override(**override):
        if ext == 'gltf' or ext == 'glb':
            bpy.ops.import_scene.gltf(filepath=in_path)
        elif ext == 'obj':
            bpy.ops.wm.obj_import(filepath=in_path)
        else:
            raise ValueError(f"unsupported input format: {ext}")

    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    if not mesh_objects:
        raise RuntimeError(f"no mesh objects in {in_path}")
    n_before = len(set(o.data.name for o in mesh_objects))

    # Texture fix-up: nearest + relink
    _set_textures_nearest_and_relink(texture_search_dirs, verbose=verbose)

    n_replaced, n_unique, groups = reinstance(mesh_objects, match=match, verbose=verbose)

    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    with bpy.context.temp_override(**override):
        bpy.ops.object.select_all(action='DESELECT')
        for o in mesh_objects:
            o.select_set(True)
        bpy.context.view_layer.objects.active = mesh_objects[0]
        bpy.ops.export_scene.gltf(
            filepath=out_path,
            export_format='GLTF_SEPARATE',
            export_apply=False,
            export_yup=True,
            export_image_format='AUTO',
            # CRITICAL: don't copy textures; reference originals by relative path
            # so the gltf points to plants/{name}/*.png instead of writing duplicates
            export_keep_originals=True,
        )

    if verbose:
        mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
        n_after = len(set(o.data.name for o in mesh_objects))
        print(f"\n{in_path}")
        print(f"  {len(mesh_objects)} objects: {n_before} → {n_after} unique meshes "
              f"(instancing ratio {len(mesh_objects)/max(1,n_after):.2f}×)")
        print(f"  → {out_path}")

    return n_replaced, n_unique
