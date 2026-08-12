"""Per-part UV islands for the Ferrule v3, plus a face manifest for painting.

Organic forms get unwrapped islands, not the tiling level atlas: each mesh is
smart-projected into its own allocated cell of the sheet, so texels belong to
THIS creature's surfaces and the painter can shade per face.

Writes uv_manifest.json: for every face of every body/signal mesh, its UV
polygon (sheet space), its world normal z, its world height, and its island id.
"""
import bpy
import json
import math
from mathutils import Vector

OUT = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/"
       "blender/fauna/ferrule/uv_manifest.json")

BODY_MAT = "FerruleBody"
SIGNAL_MAT = "FerruleSignal"
CELL_MARGIN = 0.012


def grid_for(n):
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    return cols, rows


def smart_project(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0),
                             island_margin=0.02,
                             correct_aspect=True,
                             scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def remap_to_cell(mesh, cell, cols, rows):
    cx, cy = cell % cols, cell // cols
    u0 = cx / cols + CELL_MARGIN
    v0 = cy / rows + CELL_MARGIN
    du = 1.0 / cols - 2 * CELL_MARGIN
    dv = 1.0 / rows - 2 * CELL_MARGIN
    uv = mesh.uv_layers.active
    for d in uv.data:
        d.uv = (u0 + d.uv[0] * du, v0 + d.uv[1] * dv)


def collect(obj, island, manifest, heights):
    mesh = obj.data
    uv = mesh.uv_layers.active
    mw = obj.matrix_world
    for poly in mesh.polygons:
        n = (mw.to_3x3() @ poly.normal).normalized()
        z = (mw @ mesh.vertices[mesh.loops[poly.loop_start].vertex_index].co).z
        zs = [(mw @ mesh.vertices[mesh.loops[li].vertex_index].co).z
              for li in poly.loop_indices]
        pts = [list(uv.data[li].uv) for li in poly.loop_indices]
        manifest.append({
            "island": island,
            "object": obj.name,
            "uv": [[round(u, 5), round(v, 5)] for u, v in pts],
            "nz": round(n.z, 4),
            "ny": round(n.y, 4),
            "wz": round(sum(zs) / len(zs), 4),
        })
        heights.append(sum(zs) / len(zs))


def run():
    coll = bpy.data.collections["FerruleV3"]
    body_objs = []
    signal_objs = []
    for o in coll.objects:
        if o.type != "MESH":
            continue
        mats = {m.name for m in o.data.materials if m}
        if BODY_MAT in mats:
            body_objs.append(o)
        elif SIGNAL_MAT in mats:
            signal_objs.append(o)
    body_objs.sort(key=lambda o: o.name)
    signal_objs.sort(key=lambda o: o.name)

    manifest = {"body": [], "signal": [], "cells": {}}
    heights = []

    cols, rows = grid_for(len(body_objs))
    for i, o in enumerate(body_objs):
        smart_project(o)
        remap_to_cell(o.data, i, cols, rows)
        collect(o, i, manifest["body"], heights)
        manifest["cells"][o.name] = {"sheet": "body", "cell": i,
                                     "cols": cols, "rows": rows}

    scols, srows = grid_for(len(signal_objs))
    for i, o in enumerate(signal_objs):
        smart_project(o)
        remap_to_cell(o.data, i, scols, srows)
        collect(o, i, manifest["signal"], heights)
        manifest["cells"][o.name] = {"sheet": "signal", "cell": i,
                                     "cols": scols, "rows": srows}

    manifest["body_grid"] = [cols, rows]
    manifest["signal_grid"] = [scols, srows]
    manifest["z_range"] = [round(min(heights), 4), round(max(heights), 4)]
    with open(OUT, "w") as fh:
        json.dump(manifest, fh)
    return {
        "body_meshes": len(body_objs),
        "signal_meshes": len(signal_objs),
        "body_grid": [cols, rows],
        "faces": len(manifest["body"]) + len(manifest["signal"]),
    }


result = run()
