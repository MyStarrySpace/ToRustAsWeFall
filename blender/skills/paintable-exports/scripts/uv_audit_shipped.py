"""UV gate, SHIPPING half — audit the committed assets, not the .blend.

The blend-side audit proves the builder is correct. This proves what actually
ships is, which is a different question the hard way: a packer fix makes every
source correct while the committed .gltf keeps whatever UVs it was baked with,
and nothing in the build or the tests notices. Two assets sat stale for weeks
exactly that way.

Reads TEXCOORD_0 straight out of each .gltf at the resolution of the texture that
gltf actually references, and applies the same metric as the blend-side gate:
hard overlap (two faces claiming one texel) and islands closer than the gutter.
Plain python, no Blender, so it can run as a repo test.

    python uv_audit_shipped.py <repo_root>            # sweep resources/models
    python uv_audit_shipped.py <repo_root> --json out.json
"""

import base64
import json
import os
import struct
import sys

MIN_GUTTER_TEXELS = 2
COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
COMPONENT_FMT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


def _png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(33)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def _read_accessor(gltf, base_dir, index, buffers):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    buf_idx = view.get("buffer", 0)
    if buf_idx not in buffers:
        uri = gltf["buffers"][buf_idx].get("uri", "")
        if uri.startswith("data:"):
            buffers[buf_idx] = base64.b64decode(uri.split(",", 1)[1])
        else:
            with open(os.path.join(base_dir, uri), "rb") as fh:
                buffers[buf_idx] = fh.read()
    blob = buffers[buf_idx]
    ncomp = COMPONENT_COUNT[acc["type"]]
    csize = COMPONENT_SIZE[acc["componentType"]]
    fmt = COMPONENT_FMT[acc["componentType"]]
    stride = view.get("byteStride") or (ncomp * csize)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        off = start + i * stride
        out.append(struct.unpack_from("<" + fmt * ncomp, blob, off))
    return out


def _point_in_poly(px, py, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        if (poly[i][1] > py) != (poly[j][1] > py):
            xint = (poly[j][0] - poly[i][0]) * (py - poly[i][1]) / \
                   ((poly[j][1] - poly[i][1]) or 1e-12) + poly[i][0]
            if px < xint:
                inside = not inside
        j = i
    return inside


def audit_gltf(path, min_gutter=MIN_GUTTER_TEXELS):
    base_dir = os.path.dirname(path)
    with open(path, encoding="utf-8") as fh:
        gltf = json.load(fh)
    buffers = {}
    rows = []
    mesh_nodes = {}
    for node in gltf.get("nodes", []):
        if "mesh" in node:
            mesh_nodes.setdefault(node["mesh"], node.get("name", "?"))
    for mi, mesh in enumerate(gltf.get("meshes", [])):
        name = mesh_nodes.get(mi, mesh.get("name", "mesh%d" % mi))
        for prim in mesh.get("primitives", []):
            attrs = prim.get("attributes", {})
            if "TEXCOORD_0" not in attrs:
                continue                      # flat-palette piece: no atlas by design
            res = 0
            mat_idx = prim.get("material")
            if mat_idx is not None:
                mat = gltf["materials"][mat_idx]
                tex_i = (mat.get("pbrMetallicRoughness", {})
                            .get("baseColorTexture", {}).get("index"))
                if tex_i is not None:
                    img = gltf["images"][gltf["textures"][tex_i]["source"]]
                    uri = img.get("uri", "")
                    if uri and not uri.startswith("data:"):
                        size = _png_size(os.path.join(base_dir, uri))
                        if size:
                            res = size[0]
            if not res:
                continue                      # embedded/unknown texture: not auditable here
            uvs = _read_accessor(gltf, base_dir, attrs["TEXCOORD_0"], buffers)
            idx = _read_accessor(gltf, base_dir, prim["indices"], buffers) \
                if "indices" in prim else [(i,) for i in range(len(uvs))]
            tris = [(idx[i][0], idx[i + 1][0], idx[i + 2][0])
                    for i in range(0, len(idx) - 2, 3)]
            cover = {}
            for tri in tris:
                poly = [uvs[v] for v in tri]
                us = [p[0] for p in poly]
                vs = [p[1] for p in poly]
                for gx in range(max(0, int(min(us) * res) - 1),
                                min(res, int(max(us) * res) + 2)):
                    for gy in range(max(0, int(min(vs) * res) - 1),
                                    min(res, int(max(vs) * res) + 2)):
                        if _point_in_poly((gx + 0.5) / res, (gy + 0.5) / res, poly):
                            cover.setdefault((gx, gy), set()).add(tri)
            # union-find the triangles into islands by shared uv position
            parent = {t: t for t in tris}

            def find(a):
                while parent[a] != a:
                    parent[a] = parent[parent[a]]
                    a = parent[a]
                return a
            by_uv = {}
            for tri in tris:
                for v in tri:
                    by_uv.setdefault((round(uvs[v][0], 6), round(uvs[v][1], 6)),
                                     []).append(tri)
            for group in by_uv.values():
                for other in group[1:]:
                    ra, rb = find(group[0]), find(other)
                    if ra != rb:
                        parent[rb] = ra
            isl_of = {t: find(t) for t in tris}
            hard = 0
            cells = {}
            for cell, tset in cover.items():
                ids = {isl_of[t] for t in tset}
                if len(ids) > 1:
                    hard += 1
                cells[cell] = ids
            near = set()
            for (gx, gy), ids in cells.items():
                for dx in range(-min_gutter, min_gutter + 1):
                    for dy in range(-min_gutter, min_gutter + 1):
                        other = cells.get((gx + dx, gy + dy))
                        if not other:
                            continue
                        for a in ids:
                            for b in other:
                                if a != b:
                                    near.add((min(a, b), max(a, b)))
            status = "HARD_OVERLAP" if hard else ("ZERO_GUTTER" if near else "ok")
            rows.append({"asset": os.path.basename(path), "piece": name, "res": res,
                         "islands": len(set(isl_of.values())),
                         "hard_overlap_texels": hard,
                         "island_pairs_under_min_gutter": len(near),
                         "status": status})
    return rows


def sweep(root, min_gutter=MIN_GUTTER_TEXELS):
    models = os.path.join(root, "to-rust-as-we-fall", "resources", "models")
    rows = []
    for dirpath, _dirs, files in os.walk(models):
        for fname in files:
            if fname.endswith(".gltf"):
                rows.extend(audit_gltf(os.path.join(dirpath, fname), min_gutter))
    bad = [r for r in rows if r["status"] != "ok"]
    if not rows:
        # A sweep that found nothing has not cleared anything. Reporting PASS here
        # makes a mistyped root, a moved directory, or an invocation through the
        # wrong interpreter look exactly like a clean repo.
        return {"audited": rows, "failing": bad, "verdict": "EMPTY",
                "problem": "no .gltf found under %s" % models}
    return {"audited": rows, "failing": bad, "verdict": "FAIL" if bad else "PASS"}


if __name__ == "__main__":
    repo = sys.argv[1] if len(sys.argv) > 1 else "."
    report = sweep(repo)
    if report["verdict"] == "EMPTY":
        print("SHIPPED UV AUDIT EMPTY — %s" % report["problem"])
        print("usage: python uv_audit_shipped.py <repo_root> [--json out.json]")
        sys.exit(2)
    for row in report["failing"]:
        print("FAIL %-28s %-22s res=%-5d islands=%-3d hard=%-4d pairs=%d"
              % (row["asset"], row["piece"], row["res"], row["islands"],
                 row["hard_overlap_texels"], row["island_pairs_under_min_gutter"]))
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
    print("SHIPPED UV AUDIT %s — %d meshes audited, %d failing"
          % (report["verdict"], len(report["audited"]), len(report["failing"])))
