# Generic BlockBench hand-off for EXISTING assets: split any GLTF/GLB/blend/OBJ
# into one OBJ + MTL + texture per top-level object, ready to import and paint.
# Textures ride along via path_mode COPY (embedded gltf textures included), so
# the output folder is self-contained.
#
#   blender.exe -b --python blender/export_paintables.py -- \
#       --in to-rust-as-we-fall/resources/models/elevator/bridge.glb \
#       [--out blender/elevator/obj-exports]        (default: blender/<area>/obj-exports
#                                                    when --in is under resources/models/<area>/,
#                                                    else <input dir>/obj-exports)
#   --joined      export everything as ONE obj instead of per top-level object
#
# For PROCEDURAL sources (generators, creature grammar), don't use this — call
# paintlib.texture_object + export_obj from the generator script itself so the
# pieces get paintable per-face UV islands. This tool preserves EXISTING UVs and
# textures untouched; it only splits and packages.

import bpy
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from paintlib import all_mesh_children, export_obj

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = {"--in": None, "--out": None}
joined = "--joined" in argv
for i, a in enumerate(argv):
    if a in opts and i + 1 < len(argv):
        opts[a] = argv[i + 1]
if not opts["--in"]:
    raise SystemExit("usage: blender -b --python export_paintables.py -- --in <asset> [--out <dir>] [--joined]")

src = os.path.abspath(opts["--in"])
if opts["--out"]:
    out_dir = os.path.abspath(opts["--out"])
else:
    norm = src.replace("\\", "/")
    marker = "/resources/models/"
    if marker in norm:
        area = norm.split(marker, 1)[1].split("/", 1)[0]
        repo = norm.split("/to-rust-as-we-fall/", 1)[0]
        out_dir = os.path.join(repo, "blender", area, "obj-exports")
    else:
        out_dir = os.path.join(os.path.dirname(src), "obj-exports")
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(src)[1].lower()
if ext in (".gltf", ".glb"):
    bpy.ops.import_scene.gltf(filepath=src)
elif ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src)
elif ext == ".obj":
    bpy.ops.wm.obj_import(filepath=src)
else:
    raise SystemExit("unsupported input: %s" % ext)

roots = [ob for ob in bpy.data.objects
         if ob.parent is None and all_mesh_children([ob])]
if not roots:
    raise SystemExit("no mesh objects found in %s" % src)

# Embedded (packed) textures never survive an OBJ export — write each one to the
# output dir and file-back the image so the MTL gets its map_Kd and the texture
# ships beside the OBJ.
for img in bpy.data.images:
    if img.packed_file is not None and img.size[0] > 0:
        img.filepath_raw = os.path.join(out_dir, "%s.png" % img.name.replace(".", "_"))
        img.file_format = "PNG"
        img.save()

if joined:
    name = os.path.splitext(os.path.basename(src))[0]
    export_obj(roots, os.path.join(out_dir, name + ".obj"))
else:
    used = set()
    for root in roots:
        name = root.name.replace(".", "_")
        while name in used:
            name += "_"
        used.add(name)
        export_obj([root], os.path.join(out_dir, name + ".obj"))
print("[HANDOFF] %d piece(s) -> %s" % (1 if joined else len(roots), out_dir))
