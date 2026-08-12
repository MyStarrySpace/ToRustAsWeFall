"""Ferrule master build: seven stacked plates from one arch generator.

Blender space: +X right, +Y rearward (mouth at -Y), +Z up, ground Z=0.
Exported with export_yup, so glTF z = -blender_y: the mouth lands at +Z, which is
the forward axis the runtime wrapper and verifier expect.
"""
import bpy
import math
import os

COLLECTION = "Ferrule"
ROOT = "FerruleRoot"

TEX_DIR = "c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/resources/models/fauna/ferrule_v2"
UV_SCALE = 3.05          # metres per UV unit -> chunky pixel-art texel density
ROOT_Y_OFFSET = -2.344   # puts the mouth at glTF +2.38 like the shipped asset

# Concept-ratio fit (front W/H 1.486, side L/H 2.112) inside the contract
# bounds: applied to every vertex and station at build time.
SCALE_X, SCALE_Y, SCALE_Z = 1.218, 0.834, 0.933


# ---------------------------------------------------------------- scene setup

def wipe():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for act in list(bpy.data.actions):
        act.use_fake_user = False
        bpy.data.actions.remove(act)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures,
                  bpy.data.actions, bpy.data.collections):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    coll = bpy.data.collections.get(COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(coll)
    return coll


def _image(filename):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.get(filename)
    if img is None:
        img = bpy.data.images.load(path, check_existing=True)
    else:
        img.filepath = path
        img.reload()
    img.name = filename
    return img


def textured_material(name, albedo_file, emissive_file=None, emit_strength=1.15):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-260, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.78
    bsdf.inputs["Metallic"].default_value = 0.0

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-620, 120)
    tex.image = _image(albedo_file)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if emissive_file:
        etex = nt.nodes.new("ShaderNodeTexImage")
        etex.location = (-620, -240)
        etex.image = _image(emissive_file)
        etex.interpolation = "Closest"
        nt.links.new(etex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return mat


# ------------------------------------------------------------------- UV maps

def box_uv(mesh, scale=UV_SCALE):
    """Dominant-axis box projection. The atlas tiles, so plates stay seamless."""
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        i, j = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[i] / scale, co[j] / scale)


def unit_uv(mesh, inset=0.06):
    """Map every face across the whole sheet - used for signal and mouth parts."""
    uv = mesh.uv_layers.new(name="UVMap")
    lo, hi = inset, 1.0 - inset
    corners = [(lo, lo), (hi, lo), (hi, hi), (lo, hi)]
    for poly in mesh.polygons:
        for k, li in enumerate(poly.loop_indices):
            uv.data[li].uv = corners[k % 4]


def new_object(name, verts, faces, mat, coll, parent=None, uv="box"):
    verts = [(x * SCALE_X, y * SCALE_Y, z * SCALE_Z) for (x, y, z) in verts]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    (box_uv if uv == "box" else unit_uv)(mesh)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    if parent is not None:
        obj.parent = parent
    return obj


# ------------------------------------------------------------ arch generator

def superellipse(t, a, b, expo):
    """Top half of a superellipse: t in [0, pi], returns (x, z)."""
    c, s = math.cos(t), math.sin(t)
    k = 2.0 / expo
    return a * math.copysign(abs(c) ** k, c), b * (abs(s) ** k)


def build_arch(name, cfg, mat, coll, parent):
    """One armour plate: a superelliptic arch band swept along Y with a forward
    lean, a crown-heavy depth profile, and two feet that toe inward."""
    W, H = cfg["outer_w"], cfg["outer_h"]
    bw, bh = cfg["bore_w"], cfg["bore_h"]
    D, lean = cfg["depth"], cfg["lean"]
    expo = cfg.get("expo", 3.0)
    n_arc = cfg.get("arc_stations", 13)
    depth_min = cfg.get("depth_min", 0.90)
    depth_pow = cfg.get("depth_pow", 0.85)
    foot_flare = cfg.get("foot_flare", 0.22)
    foot_frac = cfg.get("foot_frac", 0.38)
    foot_depth = cfg.get("foot_depth", -0.22)

    rings = []
    for i in range(n_arc):
        t = math.pi * i / (n_arc - 1)
        ox, oz = superellipse(t, W * 0.5, H, expo)
        ix, iz = superellipse(t, bw * 0.5, bh, expo)
        # The bore is widest near half height and pinches toward the floor.
        pinch = cfg.get("bore_pinch", 0.97)
        ix *= pinch + (1.0 - pinch) * min(1.0, (iz / bh) / 0.5 if bh else 1.0)

        h = oz / H
        ground = max(0.0, 1.0 - oz / (foot_frac * H))
        # Waist-then-flare: the flank narrows below the shoulder, then the foot
        # splays back out at the floor - the trapezoid stance the front reads.
        ox *= 1.0 - cfg.get("waist", 0.07) * (1.0 - h) ** 1.5
        ox *= 1.0 + foot_flare * ground * ground
        foot_x = cfg.get("foot_x")
        if foot_x is not None:
            g = ground ** 1.5
            ox = (1.0 - g) * ox + g * math.copysign(foot_x, ox)

        depth = D * (depth_min + (1.0 - depth_min) * (h ** depth_pow))
        depth *= 1.0 + foot_depth * ground * ground
        depth *= 1.0 - cfg.get("crown_taper", 0.40) * (h ** 4)
        y_mid = -lean * h + cfg.get("foot_back", 0.0) * ground * ground

        nx, nz = ox - ix, oz - iz
        nlen = math.hypot(nx, nz) or 1.0
        nx, nz = nx / nlen, nz / nlen
        crest = cfg.get("crest", 0.22) * depth
        y_f, y_b = y_mid - depth * 0.5, y_mid + depth * 0.5
        rings.append([
            (ox, y_f, oz),
            (ox + nx * crest, y_mid, oz + nz * crest),
            (ox, y_b, oz),
            (ix, y_b, iz),
            (ix - nx * crest * 0.45, y_mid, iz - nz * crest * 0.45),
            (ix, y_f, iz),
        ])

    per = 6
    verts, faces = [], []
    for ring in rings:
        verts.extend(ring)
    for i in range(n_arc - 1):
        a, b = i * per, (i + 1) * per
        for k in range(per):
            k2 = (k + 1) % per
            faces.append([a + k, b + k, b + k2, a + k2])
    faces.append(list(range(per - 1, -1, -1)))
    last = (n_arc - 1) * per
    faces.append(list(range(last, last + per)))

    obj = new_object(name, verts, faces, mat, coll, parent)
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


# -------------------------------------------------------------------- mouth

MOUTH_PROFILE = [
    (-0.19, 1.00), (-0.45, 0.76), (-0.51, 0.57), (-0.53, 0.44),
    (-0.49, 0.33), (-0.48, 0.21), (-0.39, 0.08), (-0.35, 0.00),
    (-0.20, 0.00), (-0.16, 0.13), (-0.06, 0.20), (0.06, 0.20),
    (0.16, 0.13), (0.20, 0.00), (0.35, 0.00), (0.39, 0.08),
    (0.48, 0.21), (0.49, 0.33), (0.53, 0.44), (0.51, 0.57),
    (0.45, 0.76), (0.19, 1.00),
]

# Seven stations closing to a small rounded snout: a wide flat front cap was
# reading as an abrupt slab where the face should turn.
MOUTH_SECTIONS = [
    (-0.50, 0.20, 0.34),
    (-0.42, 0.44, 0.26),
    (-0.30, 0.68, 0.22),
    (-0.12, 0.90, 0.20),
    (0.10, 1.00, 0.18),
    (0.32, 0.96, 0.10),
    (0.50, 0.80, 0.02),
]


def build_mouth(cfg, mat, coll, parent):
    W, H, D = cfg["outer_w"], cfg["outer_h"], cfg["depth"]
    n = len(MOUTH_PROFILE)
    verts, faces = [], []
    for y_frac, scale, lift in MOUTH_SECTIONS:
        for px, pz in MOUTH_PROFILE:
            verts.append((px * W * scale, y_frac * D, pz * H * scale + lift * H))
    for s in range(len(MOUTH_SECTIONS) - 1):
        a, b = s * n, (s + 1) * n
        for k in range(n):
            k2 = (k + 1) % n
            faces.append([a + k, b + k, b + k2, a + k2])
    faces.append(list(range(n - 1, -1, -1)))
    tail = (len(MOUTH_SECTIONS) - 1) * n
    faces.append(list(range(tail, tail + n)))
    obj = new_object("Ferrule_Mouth", verts, faces, mat, coll, parent)
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


def build_mouth_void(cfg, mat, coll, parent):
    """The dark capture cavity recessed under the mouth's paired lobes."""
    W, H, D = cfg["outer_w"], cfg["outer_h"], cfg["depth"]
    hw, top = 0.19 * W, 0.21 * H
    y0, y1 = -0.08 * D, 0.34 * D
    verts = [
        (-hw, y0, 0.004), (hw, y0, 0.004), (hw, y0, top), (-hw, y0, top),
        (-hw * 0.82, y1, 0.004), (hw * 0.82, y1, 0.004),
        (hw * 0.82, y1, top * 0.86), (-hw * 0.82, y1, top * 0.86),
    ]
    faces = [[0, 1, 2, 3], [4, 7, 6, 5], [0, 3, 7, 4], [1, 5, 6, 2],
             [3, 2, 6, 7], [0, 4, 5, 1]]
    obj = new_object("Ferrule_MouthVoid", verts, faces, mat, coll, parent, uv="unit")
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


def build_fangs(cfg, mat, coll, parent):
    """Six lime chelation tips in three pairs, hanging clear of the aperture."""
    W, H, D = cfg["outer_w"], cfg["outer_h"], cfg["depth"]
    pairs = [(0.155, 0.275, 0.060), (0.280, 0.200, 0.040), (0.380, 0.140, 0.026)]
    verts, faces = [], []
    for fx, fl, fw in pairs:
        for side in (-1, 1):
            cx, half, top = side * fx * W, fw * W, fl * H
            base = len(verts)
            verts.extend([
                (cx - half, -0.26 * D, top), (cx + half, -0.26 * D, top),
                (cx + half, -0.12 * D, top), (cx - half, -0.12 * D, top),
                (cx - half * 0.24, -0.24 * D, 0.0), (cx + half * 0.24, -0.24 * D, 0.0),
                (cx + half * 0.24, -0.14 * D, 0.0), (cx - half * 0.24, -0.14 * D, 0.0),
            ])
            for k in range(4):
                k2 = (k + 1) % 4
                faces.append([base + k, base + 4 + k, base + 4 + k2, base + k2])
            faces.append([base + 3, base + 2, base + 1, base])
            faces.append([base + 4, base + 5, base + 6, base + 7])
    obj = new_object("Ferrule_ChelationTips", verts, faces, mat, coll, parent, uv="unit")
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


# --------------------------------------------------------------- rear anchor

# Half-profile of the rear seen from the front, ground to crest: straight
# flank, angled shoulder, sloped roof to a narrow crest - the trapezoid lobes
# the concept paints, not a smooth dome arc.
REAR_PROFILE = [
    (1.00, 0.00), (1.02, 0.16), (0.98, 0.38), (0.90, 0.58),
    (0.74, 0.78), (0.50, 0.92), (0.22, 1.00),
]


def build_rear(cfg, mat, coll, parent):
    W, H, D = cfg["outer_w"], cfg["outer_h"], cfg["depth"]
    sections = cfg["sections"]
    half = [(xf, zf) for xf, zf in REAR_PROFILE]
    ring_profile = [(-xf, zf) for xf, zf in half] + [(xf, zf) for xf, zf in reversed(half)]
    n_arc = len(ring_profile)
    verts, faces = [], []
    for y_frac, wide, tall in sections:
        for xf, zf in ring_profile:
            verts.append((W * 0.5 * wide * xf, y_frac * D, H * tall * zf))
    per = n_arc
    for s in range(len(sections) - 1):
        a, b = s * per, (s + 1) * per
        for i in range(per - 1):
            faces.append([a + i, b + i, b + i + 1, a + i + 1])
    faces.append(list(range(per - 1, -1, -1)))
    tail = (len(sections) - 1) * per
    faces.append(list(range(tail, tail + per)))

    # The belly touches ground mid-span; the corners lift away from it.
    sag = cfg.get("base_sag", 0.032) * H
    base = len(verts)
    for y_frac, wide, _tall in sections:
        hw = W * 0.5 * wide
        verts.extend([(-hw, y_frac * D, sag), (0.0, y_frac * D, 0.0), (hw, y_frac * D, sag)])
    for i in range(len(sections) - 1):
        a, b = base + i * 3, base + (i + 1) * 3
        faces.append([a, a + 1, b + 1, b])
        faces.append([a + 1, a + 2, b + 2, b + 1])

    obj = new_object("Ferrule_RearAnchor", verts, faces, mat, coll, parent)
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


def build_vents(cfg, mat, coll, parent):
    W, H, D = cfg["outer_w"], cfg["outer_h"], cfg["depth"]
    front = cfg["sections"][0]
    y = front[0] * D - 0.012
    half_w = 0.5 * W * front[1]
    verts, faces = [], []
    for side in (-1, 1):
        cx, half = side * half_w * 0.912, half_w * 0.136
        base = len(verts)
        verts.extend([
            (cx - half, y, 0.005 * H), (cx + half, y, 0.005 * H),
            (cx + half * 0.55, y, 0.072 * H), (cx - half * 0.55, y, 0.072 * H),
        ])
        faces.append([base, base + 1, base + 2, base + 3])
    obj = new_object("Ferrule_SignalVents", verts, faces, mat, coll, parent, uv="unit")
    obj.location.y = cfg["station_y"] * SCALE_Y
    return obj


# ------------------------------------------------------------------- the spec

MOUTH = dict(outer_w=0.76, outer_h=0.70, depth=0.80, station_y=0.36)

SEGMENTS = [
    dict(name="Ferrule_Segment_01", outer_w=0.850, outer_h=0.720, bore_w=0.406,
         bore_h=0.329, depth=0.34, station_y=0.62, lean=0.13, foot_back=0.11,
         expo=2.25, arc_stations=14),
    dict(name="Ferrule_Segment_02", outer_w=0.965, outer_h=0.950, bore_w=0.499,
         bore_h=0.450, depth=0.38, station_y=0.88, lean=0.16, foot_back=0.13,
         expo=2.32, arc_stations=14),
    dict(name="Ferrule_Segment_03", outer_w=1.081, outer_h=1.090, bore_w=0.604,
         bore_h=0.527, depth=0.42, station_y=1.14, lean=0.19, foot_back=0.15,
         expo=2.40, arc_stations=13),
    dict(name="Ferrule_Segment_04", outer_w=1.218, outer_h=1.320, bore_w=0.664,
         bore_h=0.670, depth=0.47, station_y=1.40, lean=0.22, foot_back=0.17,
         expo=3.00, arc_stations=17),
    dict(name="Ferrule_Segment_05", outer_w=1.470, outer_h=1.550, bore_w=0.906,
         bore_h=0.856, depth=0.54, station_y=1.68, lean=0.25, foot_back=0.19,
         expo=3.20, arc_stations=18),
]

REAR = dict(outer_w=1.840, outer_h=1.560, depth=2.640, station_y=2.460, expo=2.5,
            sections=[
                (-0.50, 0.60, 0.86), (-0.32, 0.85, 0.96), (-0.15, 1.00, 1.00),
                (0.06, 0.95, 0.92), (0.26, 0.82, 0.74), (0.40, 0.60, 0.46),
                (0.50, 0.26, 0.14),
            ])


def main():
    coll = wipe()
    body = textured_material("FerruleBody", "ferrule_body.png")
    void = textured_material("FerruleMouthVoid", "ferrule_mouth.png")
    signal = textured_material("FerruleSignal", "ferrule_signal.png",
                               "ferrule_signal_emissive.png")

    root = bpy.data.objects.new(ROOT, None)
    coll.objects.link(root)
    root.location.y = ROOT_Y_OFFSET

    build_mouth(MOUTH, body, coll, root)
    build_mouth_void(MOUTH, void, coll, root)
    build_fangs(MOUTH, signal, coll, root)
    for cfg in SEGMENTS:
        build_arch(cfg["name"], cfg, body, coll, root)
    build_rear(REAR, body, coll, root)
    build_vents(REAR, signal, coll, root)

    bpy.context.view_layer.update()
    meshes = [o for o in coll.objects if o.type == "MESH"]
    return {
        "meshes": len(meshes),
        "names": sorted(o.name for o in meshes),
        "polys": sum(len(o.data.polygons) for o in meshes),
        "uv_ok": all(len(o.data.uv_layers) > 0 for o in meshes),
        "materials": sorted({m.name for o in meshes for m in o.data.materials}),
    }


result = main()
