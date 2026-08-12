"""splice_pot_soil.py

Splice the Blockbench-edited Pot and Soil mesh + textures from
`<plant>/<plant>.gltf` into `<plant>_instanced.gltf`, dropping the Saucer.

Why: Blockbench export (the per-plant subfolder file) carries the user's
manual edits to the pot/soil mesh and textures, but loses the foliage
instancing. The `_instanced.gltf` has the proper instancing and clean
texture URIs but uses the un-edited pot/soil.

This tool takes the best of both: it keeps the instanced foliage from the
`_instanced.gltf`, and replaces its Pot + Soil mesh data + textures with
the Blockbench-edited versions. Saucer is removed.

Run:  python3 splice_pot_soil.py <plant_name> [--root <models-root>]
e.g.  python3 splice_pot_soil.py boston_fern

Writes:
  <plant>/PotTex.png, <plant>/SoilTex.png    (overwritten)
  <plant>_instanced.gltf                       (overwritten in-place)
  <plant>_instanced.bin                        (overwritten in-place)
"""
import sys, os, json, base64, struct, argparse

# ---------------------------------------------------------------------------
# glTF accessor component-type sizes
COMPONENT_TYPE_SIZE = {
    5120: 1,  # BYTE
    5121: 1,  # UNSIGNED_BYTE
    5122: 2,  # SHORT
    5123: 2,  # UNSIGNED_SHORT
    5125: 4,  # UNSIGNED_INT
    5126: 4,  # FLOAT
}
TYPE_COMPONENT_COUNT = {
    'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4,
    'MAT2': 4, 'MAT3': 9, 'MAT4': 16,
}

def accessor_byte_length(accessor):
    cs = COMPONENT_TYPE_SIZE[accessor['componentType']]
    cc = TYPE_COMPONENT_COUNT[accessor['type']]
    return cs * cc * accessor['count']


def load_gltf_and_buffer(path):
    """Returns (gltf_dict, buffer_bytes) for any glTF (URI .bin or embedded data: URI)."""
    with open(path) as f:
        g = json.load(f)
    base_dir = os.path.dirname(path)
    # Combine all buffers (glTF allows multiple; here we expect 1)
    bufs = []
    for buf in g['buffers']:
        uri = buf.get('uri', '')
        if uri.startswith('data:'):
            _header, b64 = uri.split(',', 1)
            bufs.append(base64.b64decode(b64))
        elif uri:
            with open(os.path.join(base_dir, uri), 'rb') as f:
                bufs.append(f.read())
        else:
            raise RuntimeError("Buffer without URI (.glb?) not supported here")
    if len(bufs) != 1:
        raise RuntimeError(f"Expected exactly 1 buffer, got {len(bufs)}")
    return g, bufs[0]


def extract_accessor_bytes(gltf, buffer_bytes, accessor_idx):
    """Returns the raw bytes for a given accessor (handling bufferView offsets and stride)."""
    acc = gltf['accessors'][accessor_idx]
    view = gltf['bufferViews'][acc['bufferView']]
    offset = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    length = accessor_byte_length(acc)
    stride = view.get('byteStride', 0)
    if stride == 0:
        # Tightly packed
        return buffer_bytes[offset:offset + length]
    # Strided: pull out the relevant chunk per element and concat
    element_size = COMPONENT_TYPE_SIZE[acc['componentType']] * TYPE_COMPONENT_COUNT[acc['type']]
    chunks = []
    for i in range(acc['count']):
        s = offset + i * stride
        chunks.append(buffer_bytes[s:s + element_size])
    return b''.join(chunks)


def find_node_by_name(gltf, name):
    for i, n in enumerate(gltf.get('nodes', [])):
        if n.get('name') == name:
            return i
    return None


# ---------------------------------------------------------------------------
def splice(plant, root):
    bb_path = os.path.join(root, plant, f"{plant}.gltf")  # Blockbench export (subfolder)
    inst_path = os.path.join(root, f"{plant}_instanced.gltf")
    inst_bin_path = os.path.join(root, f"{plant}_instanced.bin")
    if not os.path.exists(bb_path):
        raise SystemExit(f"Blockbench gltf not found: {bb_path}")
    if not os.path.exists(inst_path):
        raise SystemExit(f"Instanced gltf not found: {inst_path}")

    print(f"BB:        {bb_path}")
    print(f"Instanced: {inst_path}")

    bb, bb_buf = load_gltf_and_buffer(bb_path)
    inst, inst_buf = load_gltf_and_buffer(inst_path)

    # ----- (1) Extract embedded Blockbench Pot + Soil PNG and write to disk
    # In Blockbench export, materials are indexed in node order: node "Pot" uses
    # mesh 0 -> material X -> texture -> image. Look it up properly.
    def find_image_for_mesh(g, mesh_idx):
        mesh = g['meshes'][mesh_idx]
        mat_idx = mesh['primitives'][0]['material']
        mat = g['materials'][mat_idx]
        tex_idx = mat['pbrMetallicRoughness']['baseColorTexture']['index']
        img_idx = g['textures'][tex_idx]['source']
        return img_idx

    def save_embedded(img, out_path):
        uri = img['uri']
        if not uri.startswith('data:'):
            print(f"  [skip] not embedded: {out_path}")
            return False
        data = base64.b64decode(uri.split(',', 1)[1])
        with open(out_path, 'wb') as f:
            f.write(data)
        print(f"  wrote {out_path}  ({len(data)} bytes)")
        return True

    pot_node_bb = find_node_by_name(bb, 'Pot')
    soil_node_bb = find_node_by_name(bb, 'Soil')
    if pot_node_bb is None or soil_node_bb is None:
        raise SystemExit("Blockbench gltf missing 'Pot' or 'Soil' node")

    pot_mesh_bb = bb['nodes'][pot_node_bb]['mesh']
    soil_mesh_bb = bb['nodes'][soil_node_bb]['mesh']

    pot_img_idx = find_image_for_mesh(bb, pot_mesh_bb)
    soil_img_idx = find_image_for_mesh(bb, soil_mesh_bb)

    print("Writing Blockbench-embedded textures to disk...")
    save_embedded(bb['images'][pot_img_idx], os.path.join(root, plant, 'PotTex.png'))
    save_embedded(bb['images'][soil_img_idx], os.path.join(root, plant, 'SoilTex.png'))

    # ----- (2) Pull positions/normals/uvs/indices for BB Pot and Soil
    def grab_mesh_data(g, buf, mesh_idx):
        prim = g['meshes'][mesh_idx]['primitives'][0]
        out = {}
        for attr_name in ('POSITION', 'NORMAL', 'TEXCOORD_0'):
            acc_idx = prim['attributes'].get(attr_name)
            if acc_idx is None:
                continue
            acc = g['accessors'][acc_idx]
            out[attr_name] = {
                'data': extract_accessor_bytes(g, buf, acc_idx),
                'componentType': acc['componentType'],
                'type': acc['type'],
                'count': acc['count'],
                'min': acc.get('min'),
                'max': acc.get('max'),
            }
        if 'indices' in prim:
            acc_idx = prim['indices']
            acc = g['accessors'][acc_idx]
            out['INDICES'] = {
                'data': extract_accessor_bytes(g, buf, acc_idx),
                'componentType': acc['componentType'],
                'type': acc['type'],
                'count': acc['count'],
            }
        return out

    pot_data = grab_mesh_data(bb, bb_buf, pot_mesh_bb)
    soil_data = grab_mesh_data(bb, bb_buf, soil_mesh_bb)

    # Compute min/max for POSITION accessors if missing (glTF requires them).
    import struct as _struct
    def vec3_minmax(raw):
        n = len(raw) // 12
        mn = [float('inf')] * 3
        mx = [float('-inf')] * 3
        for i in range(n):
            x, y, z = _struct.unpack_from('<fff', raw, i * 12)
            mn[0], mn[1], mn[2] = min(mn[0], x), min(mn[1], y), min(mn[2], z)
            mx[0], mx[1], mx[2] = max(mx[0], x), max(mx[1], y), max(mx[2], z)
        return mn, mx

    for d in (pot_data, soil_data):
        p = d.get('POSITION')
        if p and (p['min'] is None or p['max'] is None):
            p['min'], p['max'] = vec3_minmax(p['data'])

    # ----- (3) Append BB Pot + Soil data to instanced .bin, build new accessors
    new_buf = bytearray(inst_buf)

    def append_view(raw, target=None):
        # Pad to 4-byte alignment (glTF requirement for many accessor types)
        while len(new_buf) % 4 != 0:
            new_buf.append(0)
        offset = len(new_buf)
        new_buf.extend(raw)
        view = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(raw)}
        if target is not None:
            view['target'] = target  # 34962=ARRAY_BUFFER, 34963=ELEMENT_ARRAY_BUFFER
        inst['bufferViews'].append(view)
        return len(inst['bufferViews']) - 1

    def add_accessor(view_idx, comp_type, type_, count, mn=None, mx=None):
        acc = {'bufferView': view_idx, 'componentType': comp_type, 'count': count, 'type': type_}
        if mn is not None: acc['min'] = mn
        if mx is not None: acc['max'] = mx
        inst['accessors'].append(acc)
        return len(inst['accessors']) - 1

    def build_primitive(data, material_idx):
        attrs = {}
        for attr_name in ('POSITION', 'NORMAL', 'TEXCOORD_0'):
            if attr_name not in data: continue
            d = data[attr_name]
            view_idx = append_view(d['data'], target=34962)
            acc_idx = add_accessor(view_idx, d['componentType'], d['type'], d['count'], d.get('min'), d.get('max'))
            attrs[attr_name] = acc_idx
        prim = {'attributes': attrs, 'material': material_idx}
        if 'INDICES' in data:
            d = data['INDICES']
            view_idx = append_view(d['data'], target=34963)
            acc_idx = add_accessor(view_idx, d['componentType'], d['type'], d['count'])
            prim['indices'] = acc_idx
        return prim

    # ----- (4) Find Pot, Saucer, Soil nodes in instanced; locate their meshes
    inst_pot_node = find_node_by_name(inst, 'Pot')
    inst_saucer_node = find_node_by_name(inst, 'Saucer')
    inst_soil_node = find_node_by_name(inst, 'Soil')

    if inst_pot_node is None or inst_soil_node is None:
        raise SystemExit("Instanced gltf missing 'Pot' or 'Soil' node")

    pot_mesh_inst = inst['nodes'][inst_pot_node]['mesh']
    soil_mesh_inst = inst['nodes'][inst_soil_node]['mesh']

    # The Pot/Soil materials in the instanced gltf already point to the right
    # texture URI (boston_fern/PotTex.png, boston_fern/SoilTex.png), so we just
    # rebuild the mesh primitives with the new mesh data and reuse the material.
    pot_mat = inst['meshes'][pot_mesh_inst]['primitives'][0]['material']
    soil_mat = inst['meshes'][soil_mesh_inst]['primitives'][0]['material']

    new_pot_prim = build_primitive(pot_data, pot_mat)
    new_soil_prim = build_primitive(soil_data, soil_mat)

    inst['meshes'][pot_mesh_inst] = {'name': 'Pot', 'primitives': [new_pot_prim]}
    inst['meshes'][soil_mesh_inst] = {'name': 'Soil', 'primitives': [new_soil_prim]}

    # ----- (5) Delete the Saucer node from the scene root (but leave mesh+mat
    # in arrays — removing them would require remapping every accessor/material
    # index downstream). The unreferenced data adds negligible weight and is
    # harmless: Godot won't instantiate orphan meshes.
    if inst_saucer_node is not None:
        for scene in inst['scenes']:
            if inst_saucer_node in scene['nodes']:
                scene['nodes'].remove(inst_saucer_node)
        print(f"Removed Saucer node (index {inst_saucer_node}) from scene root")
    else:
        print("No Saucer node found (already absent)")

    # ----- (6) Update buffer byte length
    inst['buffers'][0]['byteLength'] = len(new_buf)
    inst['buffers'][0]['uri'] = f"{plant}_instanced.bin"

    # ----- (7) Write outputs
    with open(inst_bin_path, 'wb') as f:
        f.write(new_buf)
    with open(inst_path, 'w') as f:
        json.dump(inst, f, indent=2)
    print(f"Wrote {inst_path} ({os.path.getsize(inst_path)} bytes)")
    print(f"Wrote {inst_bin_path} ({len(new_buf)} bytes)")
    print(f"Buffer grew by {len(new_buf) - len(inst_buf)} bytes")


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('plant', help='Plant name, e.g. boston_fern')
    ap.add_argument('--root', default='/sessions/inspiring-eloquent-bohr/mnt/to-rust-as-we-fall/resources/models/peris-sim/plants',
                    help='Plants folder root')
    args = ap.parse_args()
    splice(args.plant, args.root)
