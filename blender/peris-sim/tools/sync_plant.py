"""sync_plant.py

Reusable Blender script that brings a plant .blend file from "Blender-generated
+ Blockbench-edited" state to "game-ready export source" state in one pass.

For each plant:
  1. Import Blockbench-edited .gltf (if it exists) and SWAP its Pot + Soil
     meshes into the original Pot and Soil objects (keeping the original
     materials and texture references).
  2. Delete the Saucer object + its mesh + material + image.
  3. Repoint Pot/Soil/foliage texture filepaths to absolute paths in the GAME
     folder so the exported .gltf has clean relative URIs like
     `<plant>/PotTex.png`.
  4. For each *group* of foliage objects (e.g. Leaf_000..Leaf_NNN, FrondCard_*,
     Vine_*, etc.), find duplicates by topology, recover per-instance
     transform via SVD/Umeyama Procrustes, write transform as
     object.matrix_world, and collapse to a single shared Mesh datablock.
     This is what makes the export use real glTF instancing.
  5. Save .blend as v(N+1).
  6. Export glTF SEPARATE to game folder.

Usage from execute_blender_code:

    import sys
    sys.path.insert(0, r"C:\\Users\\quest\\Programming\\Games\\ToRustAsWeFall\\blender\\peris-sim\\tools")
    import importlib, sync_plant; importlib.reload(sync_plant)
    sync_plant.sync(
        plant="calathea",
        blend_in=r"C:\\...\\stylized_plant_calathea_v11.blend",
        blend_out=r"C:\\...\\stylized_plant_calathea_v12.blend",
        blockbench_gltf=r"C:\\...\\to-rust-as-we-fall\\...\\calathea\\calathea.gltf",
        game_plants_dir=r"C:\\...\\to-rust-as-we-fall\\resources\\models\\peris-sim\\plants",
        export_path=r"C:\\...\\plants\\calathea_instanced.gltf",
        # Optional: explicit per-plant foliage groups by name prefix. If
        # omitted, sync_plant auto-detects groups of >=4 objects whose names
        # share a common `<Prefix>_NNN` pattern.
        foliage_prefixes=["Leaf", "Petiole"],
    )

The script is idempotent w.r.t. .blend objects: running it twice should produce
the same output as running it once.
"""
from __future__ import annotations
import bpy
import os
import re
import numpy as np
from collections import defaultdict
from mathutils import Matrix


# ---------------------------------------------------------------------------
# Umeyama Procrustes: t + s*R @ P[i] ≈ Q[i], uniform scale + rotation + translation
# ---------------------------------------------------------------------------
def umeyama_procrustes(P, Q):
    P = np.asarray(P, dtype=np.float64)
    Q = np.asarray(Q, dtype=np.float64)
    n = P.shape[0]
    mu_P = P.mean(axis=0)
    mu_Q = Q.mean(axis=0)
    Pc = P - mu_P
    Qc = Q - mu_Q
    Sigma = (Qc.T @ Pc) / n
    U, D, Vt = np.linalg.svd(Sigma)
    S = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        S[2, 2] = -1
    R = U @ S @ Vt
    var_P = (Pc ** 2).sum() / n
    s = float(np.trace(np.diag(D) @ S) / var_P) if var_P > 1e-12 else 1.0
    t = mu_Q - s * R @ mu_P
    return s, R, t


# ---------------------------------------------------------------------------
# Phase 1: Blockbench Pot/Soil swap
# ---------------------------------------------------------------------------
def _world_z_top(obj):
    """Highest world-space z value of any vertex on obj."""
    mw = obj.matrix_world
    return max((mw @ v.co).z for v in obj.data.vertices)


def _bbox_dims(obj):
    """World-space (width_x, depth_y, height_z) bounding box of obj.data."""
    mw = obj.matrix_world
    xs, ys, zs = [], [], []
    for v in obj.data.vertices:
        w = mw @ v.co
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
    return (max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs))


def swap_pot_soil_from_blockbench(blockbench_gltf):
    """Import the Blockbench gltf, locate its Pot and Soil meshes, swap them
    into the existing 'Pot' and 'Soil' objects, then delete the imported
    objects + materials + images.

    AUTO-RESCALE: Blockbench's default project settings scale imported OBJs by
    14/16 = 0.875 (the Minecraft block convention). After mesh swap, the new
    Pot/Soil come out 0.875× the original size. We detect the per-axis scale
    ratio from old vs new Pot bounding box and apply the inverse to the swapped
    mesh data, so the new Pot occupies exactly the original Pot's bounding box.

    Returns the (rescaled) soil-top z delta.
    """
    # Record old Pot bounding box BEFORE swap
    pot_bbox_old = None
    if "Pot" in bpy.data.objects:
        pot_bbox_old = _bbox_dims(bpy.data.objects["Pot"])
    soil_z_old = None
    if "Soil" in bpy.data.objects:
        soil_z_old = _world_z_top(bpy.data.objects["Soil"])
    elif "Pot" in bpy.data.objects:
        soil_z_old = _world_z_top(bpy.data.objects["Pot"])
    before_objs = set(bpy.data.objects.keys())
    before_mats = set(bpy.data.materials.keys())
    before_imgs = set(bpy.data.images.keys())
    bpy.ops.import_scene.gltf(filepath=blockbench_gltf)
    imported_objs = sorted(set(bpy.data.objects.keys()) - before_objs)
    imported_mats = sorted(set(bpy.data.materials.keys()) - before_mats)
    imported_imgs = sorted(set(bpy.data.images.keys()) - before_imgs)

    def find_imported(base):
        for n in imported_objs:
            if n.split(".")[0] == base:
                return bpy.data.objects[n]
        return None

    imp_pot = find_imported("Pot")
    imp_soil = find_imported("Soil")

    swapped_object_names = []  # track for rescale pass

    def swap(orig_name, src_obj, mat_name):
        if src_obj is None:
            print(f"  [warn] No {orig_name} in Blockbench export — keeping original")
            return
        orig = bpy.data.objects.get(orig_name)
        if orig is None:
            print(f"  [warn] No {orig_name} in .blend — skipping swap")
            return
        new_mesh = src_obj.data
        orig.data = new_mesh
        new_mesh.name = orig_name
        new_mesh.materials.clear()
        if mat_name in bpy.data.materials:
            new_mesh.materials.append(bpy.data.materials[mat_name])
            for p in new_mesh.polygons:
                p.material_index = 0
        swapped_object_names.append(orig_name)
        print(f"  Swapped {orig_name} mesh: {len(new_mesh.vertices)} verts, "
              f"{len(new_mesh.polygons)} polys")

    swap("Pot", imp_pot, "PotMat")
    swap("Soil", imp_soil, "SoilMat")

    # ALSO swap any other named singleton objects that exist in BOTH the .blend
    # and the Blockbench export. The convention: any uniquely-named object
    # (NOT matching <Prefix>_NNN) that exists in both gets its mesh swapped
    # from the Blockbench version. This covers Trunk_Main on the jade, and any
    # future named singletons.
    # Anything else named in both files gets its mesh swapped too (e.g.
    # Trunk_Main on jade). Skip "support" objects like PlantBase that shouldn't
    # be touched by the Blockbench round-trip.
    SINGLETON_DENY = {"Pot", "Soil", "PlantBase", "Floor"}
    bb_singleton_objs = {}
    for n in imported_objs:
        base = n.split(".")[0]
        if base in SINGLETON_DENY:
            continue
        if _NAME_PATTERN.match(base):
            continue  # skip <Prefix>_NNN — handled by Procrustes later
        bb_singleton_objs.setdefault(base, bpy.data.objects[n])
    for base, src_obj in bb_singleton_objs.items():
        if base not in bpy.data.objects:
            continue
        orig = bpy.data.objects[base]
        orig_mats = [m.name for m in orig.data.materials] if orig.data.materials else []
        mat_name = orig_mats[0] if orig_mats else None
        swap(base, src_obj, mat_name)

    # Delete all imported objects
    for n in imported_objs:
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    # Delete imported materials and images (Material_0..N, Image_0..N)
    for nm in imported_mats:
        if nm in bpy.data.materials:
            bpy.data.materials.remove(bpy.data.materials[nm], do_unlink=True)
    for nm in imported_imgs:
        if nm in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[nm], do_unlink=True)
    # Rename Pot.001/Soil.001 mesh datablocks if they exist
    for nm_old, nm_new in [("Pot.001", "Pot"), ("Soil.001", "Soil")]:
        if nm_old in bpy.data.meshes:
            bpy.data.meshes[nm_old].name = nm_new

    # --- Auto-rescale to match original Pot dimensions ---------------------
    if pot_bbox_old is not None and "Pot" in bpy.data.objects:
        pot_bbox_new = _bbox_dims(bpy.data.objects["Pot"])
        # Per-axis ratio old/new — if it's roughly uniform, scale the Pot+Soil
        # mesh data by that factor along all axes.
        ratios = [old/new if new > 1e-6 else 1.0
                  for old, new in zip(pot_bbox_old, pot_bbox_new)]
        avg_ratio = sum(ratios) / 3
        max_dev = max(abs(r - avg_ratio) for r in ratios)
        if abs(avg_ratio - 1.0) > 0.01 and max_dev < 0.02:
            print(f"  Pot bbox before swap: {pot_bbox_old}, after: {pot_bbox_new}")
            print(f"  Per-axis ratios old/new: {tuple(round(r,4) for r in ratios)}")
            print(f"  Auto-rescaling all swapped meshes by {avg_ratio:.4f}× to match original dimensions: {swapped_object_names}")
            # Scale mesh vertex data in place for every swapped mesh — they all
            # came from the same Blockbench export at the same 0.875× shrink.
            for obj_name in swapped_object_names:
                if obj_name not in bpy.data.objects: continue
                me = bpy.data.objects[obj_name].data
                for v in me.vertices:
                    v.co *= avg_ratio
        elif max_dev >= 0.02:
            print(f"  WARN: per-axis ratios non-uniform: {ratios} — not auto-rescaling")
        else:
            print(f"  Pot dimensions match (avg ratio {avg_ratio:.4f}) — no rescale needed")

    # Compute new soil top and report delta to caller
    soil_z_new = None
    if "Soil" in bpy.data.objects:
        soil_z_new = _world_z_top(bpy.data.objects["Soil"])
    elif "Pot" in bpy.data.objects:
        soil_z_new = _world_z_top(bpy.data.objects["Pot"])
    if soil_z_old is not None and soil_z_new is not None:
        delta = soil_z_new - soil_z_old
        print(f"  Soil top z: {soil_z_old:.3f} -> {soil_z_new:.3f}  (delta {delta:+.3f})")
        return delta
    return 0.0


# ---------------------------------------------------------------------------
# Phase 2: Saucer delete
# ---------------------------------------------------------------------------
def delete_saucer():
    if "Saucer" in bpy.data.objects:
        obj = bpy.data.objects["Saucer"]
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        print("  Deleted Saucer object")
    for nm in ("SaucerMat",):
        if nm in bpy.data.materials:
            bpy.data.materials.remove(bpy.data.materials[nm], do_unlink=True)
    for nm in ("SaucerTex",):
        if nm in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[nm], do_unlink=True)


# ---------------------------------------------------------------------------
# Phase 3: Repoint texture filepaths to absolute paths in game folder
# ---------------------------------------------------------------------------
def repoint_textures(plant, game_plants_dir):
    """For every image data-block, if a same-named .png exists in
    <game_plants_dir>/<plant>/, repoint the filepath to that absolute path."""
    plant_dir = os.path.join(game_plants_dir, plant)
    if not os.path.isdir(plant_dir):
        print(f"  [warn] No game folder {plant_dir} — skipping texture repoint")
        return
    candidates = {f.lower(): f for f in os.listdir(plant_dir) if f.endswith(".png")}
    for img in list(bpy.data.images):
        # Use image NAME (matching .png filename) to look up the on-disk file
        wanted = img.name if img.name.endswith(".png") else f"{img.name}.png"
        match = candidates.get(wanted.lower())
        if not match:
            continue
        abs_path = os.path.join(plant_dir, match)
        if img.packed_file:
            try: img.unpack(method='REMOVE')
            except Exception: pass
        img.filepath = abs_path
        img.filepath_raw = abs_path
        img.source = 'FILE'
        img.reload()
        print(f"  Repointed image {img.name} -> {abs_path}")


# ---------------------------------------------------------------------------
# Phase 4: Procrustes-collapse foliage instances
# ---------------------------------------------------------------------------
_NAME_PATTERN = re.compile(r"^([A-Za-z][A-Za-z]*)_(\d+)$")

def detect_foliage_groups(min_group_size=4):
    """Group mesh objects by `<Prefix>_NNN` name pattern. Returns dict prefix
    -> list of objects, only including groups of >= min_group_size."""
    groups = defaultdict(list)
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        m = _NAME_PATTERN.match(o.name)
        if not m:
            continue
        prefix = m.group(1)
        groups[prefix].append(o)
    return {p: sorted(objs, key=lambda o: o.name)
            for p, objs in groups.items() if len(objs) >= min_group_size}


def _world_positions(obj):
    """N×3 array of vertex positions in WORLD space (object.matrix_world applied)."""
    mw = np.array(obj.matrix_world)  # 4×4
    R = mw[:3, :3]
    t = mw[:3, 3]
    local = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)  # N×3
    return (R @ local.T).T + t  # N×3 world


def collapse_foliage_group(objects, label="", residual_threshold=0.10):
    """Collapse a group of foliage objects to share ONE Mesh datablock.

    For each non-canonical object, find the rigid+uniform-scale transform that
    maps the canonical mesh (in its local space) to the WORLD positions of the
    target object's current vertices. Write that as the target's new
    matrix_world, then repoint the target's data pointer at the canonical mesh.

    Why world-space target: instances can have placement either (a) baked into
    mesh vertex positions while object.matrix_world stays identity (boston_fern
    case), or (b) all-identical meshes with placement on object.matrix_world
    (jasmine Bud/Flower case). Comparing in WORLD space handles both.

    If the worst per-object residual would exceed `residual_threshold` (meters),
    ABORT the collapse for this group — the meshes aren't truly rigid copies
    of one canonical shape and forcing them to share a single mesh would
    introduce visible geometric drift (gaps between leaves and stems, etc.).
    Better to keep N unique meshes and lose instancing.
    """
    if len(objects) < 2:
        return {"label": label, "skipped": "single", "count": len(objects)}

    canonical = objects[0]
    canonical_mesh = canonical.data
    # Canonical's CURRENT world placement stays as it is — we never modify it.
    # P_canon = canonical local vertices (these become the shared mesh).
    P_canon = np.array([v.co[:] for v in canonical_mesh.vertices], dtype=np.float64)
    # However: if canonical itself has a non-identity matrix_world, we need to
    # account for that when reconstructing other objects' positions. Specifically,
    # the new shared mesh is the canonical's LOCAL mesh, and we want each other
    # object's world space to look right. The most robust path: solve
    #   target_world ≈ T_new @ P_canon
    # where target_world is the OTHER object's current world-space vertices.
    # Then T_new is what we set as the other object's matrix_world.
    # The canonical itself keeps its existing matrix_world (it owns the mesh, no
    # remapping needed).
    canonical_world = _world_positions(canonical)

    canon_sig = (len(canonical_mesh.vertices), len(canonical_mesh.polygons))
    skipped_topology = []
    worst_residual = 0.0
    worst_obj = None
    planned = []  # (object, M, scale, residual) per candidate

    for o in objects[1:]:
        sig = (len(o.data.vertices), len(o.data.polygons))
        if sig != canon_sig:
            skipped_topology.append((o.name, sig))
            continue
        Q_world = _world_positions(o)
        s, R, t = umeyama_procrustes(P_canon, Q_world)
        M = np.eye(4)
        M[:3, :3] = s * R
        M[:3, 3] = t
        Q_pred = (s * (R @ P_canon.T)).T + t
        residual = float(np.sqrt(((Q_world - Q_pred) ** 2).sum(axis=1).max()))
        if residual > worst_residual:
            worst_residual = residual
            worst_obj = o.name
        planned.append((o, M, s, residual))

    # Decide: apply or abort? If even ONE per-object residual is too large,
    # the objects aren't rigid copies of canonical — collapsing would visibly
    # drift those vertices (gaps between leaves and stems, etc.). Abort.
    if worst_residual > residual_threshold:
        return {
            "label": label,
            "group_size": len(objects),
            "collapsed": 0,
            "ABORTED": True,
            "reason": f"worst residual {worst_residual:.3f} m > threshold {residual_threshold} m",
            "worst_obj": worst_obj,
            "skipped_topology": skipped_topology,
            "worst_residual_m": worst_residual,
        }

    # All residuals OK — apply the collapse
    for o, M, _s, _r in planned:
        o.matrix_world = Matrix(M.tolist())
        o.data = canonical_mesh

    return {
        "label": label,
        "group_size": len(objects),
        "collapsed": len(planned),
        "skipped_topology": skipped_topology,
        "worst_residual_m": worst_residual,
        "worst_obj": worst_obj,
        "scale_range": (min(s for _, _, s, _ in planned), max(s for _, _, s, _ in planned))
                        if planned else None,
    }


# ---------------------------------------------------------------------------
# Phase 5: Save + export
# ---------------------------------------------------------------------------
def save_and_export(blend_out, export_path, include_object_filter=None):
    """Save .blend, then export to glTF with the right export flags. Selects
    Pot, Soil, and every mesh object whose name starts with a known foliage
    prefix (or matches include_object_filter callback)."""
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)
    print(f"  Saved {blend_out}")

    # Select objects to export: every MESH object EXCEPT a small deny-list.
    # Previously this only included Pot/Soil + <Prefix>_NNN groups, which
    # accidentally excluded singleton parts like Trunk_Main on the jade.
    DENY = {"Floor", "PlantBase"}
    bpy.ops.object.select_all(action='DESELECT')
    n_sel = 0
    first_selected = None
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        if o.name in DENY:
            continue
        if include_object_filter and not include_object_filter(o.name):
            continue
        o.select_set(True); n_sel += 1
        if first_selected is None: first_selected = o
    # glTF exporter requires an active object even when use_selection=True
    if first_selected is not None:
        bpy.context.view_layer.objects.active = first_selected
    print(f"  Selected {n_sel} objects for export (active={first_selected.name if first_selected else None})")

    # Find a 3D Viewport area to override the context with — required because
    # the gltf addon dereferences `bpy.context.active_object` and it can be
    # AttributeError in the bare MCP-script context.
    override = {}
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                for region in area.regions:
                    if region.type == 'WINDOW':
                        override = {"window": window, "screen": window.screen,
                                    "area": area, "region": region,
                                    "scene": bpy.context.scene,
                                    "active_object": first_selected,
                                    "selected_objects": [o for o in bpy.context.scene.objects if o.select_get()]}
                        break
                if override: break
            if override: break
        if override: break

    if override:
        with bpy.context.temp_override(**override):
            bpy.ops.export_scene.gltf(
                filepath=export_path, use_selection=True,
                export_format='GLTF_SEPARATE', export_image_format='AUTO',
                export_keep_originals=True, export_apply=False, export_yup=True,
                export_animations=False, export_skins=False, export_morph=False,
                export_lights=False, export_cameras=False,
            )
    else:
        # No viewport found — try the bare call (will work in normal Blender sessions)
        bpy.ops.export_scene.gltf(
            filepath=export_path, use_selection=True,
            export_format='GLTF_SEPARATE', export_image_format='AUTO',
            export_keep_originals=True, export_apply=False, export_yup=True,
            export_animations=False, export_skins=False, export_morph=False,
            export_lights=False, export_cameras=False,
        )
    print(f"  Exported {export_path} ({os.path.getsize(export_path)} bytes)")


# ---------------------------------------------------------------------------
# End-to-end driver
# ---------------------------------------------------------------------------
def sync(plant, blend_in, blend_out, game_plants_dir, export_path,
         blockbench_gltf=None, foliage_prefixes=None, min_group_size=4):
    """Run the full sync pipeline for one plant.

    Args:
      plant: short name, e.g. "calathea"
      blend_in: absolute path to the input .blend
      blend_out: absolute path to write the output .blend
      game_plants_dir: e.g. ".../resources/models/peris-sim/plants"
      export_path: absolute path for the output .gltf
      blockbench_gltf: optional absolute path to Blockbench-edited .gltf
      foliage_prefixes: optional list of explicit foliage prefixes to collapse.
        If None, auto-detect any <Prefix>_NNN group of size >= min_group_size.
    """
    print(f"\n=== sync_plant: {plant} ===")
    print(f"  Opening {blend_in}")
    bpy.ops.wm.open_mainfile(filepath=blend_in)

    if blockbench_gltf and os.path.exists(blockbench_gltf):
        print(f"  Blockbench gltf: {blockbench_gltf}")
        soil_delta = swap_pot_soil_from_blockbench(blockbench_gltf)
        # NOTE: previously this also translated all foliage by `soil_delta` to
        # "follow" the new (usually shorter) pot. That turned out to introduce
        # MORE visual problems than it solved — some plants (pilea, peace_lily)
        # have leaves that hang below their attachment point, so moving the
        # whole rig down pushed them below the pot rim. Now we leave foliage
        # in its original world position. If the Blockbench pot is much shorter
        # than the procedural one, the user should adjust the pot in Blockbench
        # to match the original soil-top height, OR manually move foliage in
        # the .blend before running this script.
        if abs(soil_delta) > 1e-4:
            print(f"  Soil-top changed by {soil_delta:+.3f} m — foliage NOT auto-translated."
                  f" Adjust the Blockbench pot's height if foliage looks misaligned.")
    else:
        print("  No Blockbench gltf — skipping Pot/Soil swap")

    delete_saucer()
    repoint_textures(plant, game_plants_dir)

    # Detect foliage groups
    if foliage_prefixes:
        groups = {p: sorted([o for o in bpy.data.objects
                             if _NAME_PATTERN.match(o.name) and
                             _NAME_PATTERN.match(o.name).group(1) == p],
                             key=lambda o: o.name)
                  for p in foliage_prefixes}
        groups = {p: g for p, g in groups.items() if len(g) >= 2}
    else:
        groups = detect_foliage_groups(min_group_size=min_group_size)

    print(f"  Foliage groups detected: {[(p, len(g)) for p, g in groups.items()]}")

    collapse_stats = []
    for prefix, objs in groups.items():
        stats = collapse_foliage_group(objs, label=prefix)
        collapse_stats.append(stats)
        print(f"  Collapsed {prefix}: {stats}")

    # Purge orphan mesh datablocks after collapses
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

    save_and_export(blend_out, export_path)
    strip_spurious_normal_textures(export_path)
    fix_texture_import_files(os.path.join(game_plants_dir, plant))

    return {
        "plant": plant,
        "blend_out": blend_out,
        "export_path": export_path,
        "collapse_stats": collapse_stats,
    }


# ---------------------------------------------------------------------------
# Phase 6: Strip spurious normalTexture from materials
# ---------------------------------------------------------------------------
def strip_spurious_normal_textures(gltf_path):
    """Blender 5.1's gltf exporter adds a normalTexture entry to materials with
    HASHED blend + alpha link, even when there is NO normal map node in the
    source material. This causes Godot to import the same image as a normal
    map (.import file gets `compress/normal_map=1`), destroying its appearance.
    Strip the bogus normalTexture entries here so each material only declares
    the base color it actually uses.
    """
    import json as _json
    with open(gltf_path) as f:
        g = _json.load(f)
    changed = 0
    for m in g.get('materials', []):
        if 'normalTexture' in m:
            del m['normalTexture']
            changed += 1
    if changed:
        with open(gltf_path, 'w') as f:
            _json.dump(g, f, indent='\t')
        print(f"  Stripped {changed} spurious normalTexture entries from {gltf_path}")


def fix_texture_import_files(plant_dir):
    """For each *.png.import in the plant subfolder, if it has
    `compress/normal_map=1` or `roughness/mode=1`, reset to standard albedo
    settings. Godot may have inferred normal-map intent from the gltf's
    (bogus) normalTexture references."""
    import re
    fixed = 0
    for fn in os.listdir(plant_dir):
        if not fn.endswith('.png.import'):
            continue
        p = os.path.join(plant_dir, fn)
        with open(p) as f:
            text = f.read()
        new_text = text
        new_text = re.sub(r'compress/normal_map=1', 'compress/normal_map=0', new_text)
        new_text = re.sub(r'roughness/mode=1', 'roughness/mode=0', new_text)
        new_text = re.sub(r'roughness/src_normal="[^"]*"', 'roughness/src_normal=""', new_text)
        if new_text != text:
            with open(p, 'w') as f:
                f.write(new_text)
            fixed += 1
            print(f"  Fixed {fn}")
    if fixed:
        print(f"  Fixed {fixed} .png.import files in {plant_dir}")
