---
name: game-asset-tracing
description: Before changing any game asset (model, texture, material), trace which file the game scene ACTUALLY loads. Don't assume the obviously-named file is the one in use — combined/baked exports often shadow individual sources, caches go stale, and source paths get re-pointed during round-trips through external tools. Use this skill any time the user reports "asset X is wrong" in a game project (Godot, Unity, Unreal, Bevy).
---

# game-asset-tracing

This skill exists because I once spent a full session updating
`calathea_instanced.gltf` (and 8 other plant glTFs) plus their textures, only
to discover at the end that the game scene actually loads a SINGLE COMBINED
`peris-sim.gltf` containing all 9 plants with auto-named textures
(`peris-sim_7.png` … `peris-sim_19.png`). Every fix I shipped was invisible
to the running game. The user — rightfully — got frustrated.

The mistake was simple: I assumed file naming reflected file usage. It
doesn't. Always verify.

## Mandatory first step when user reports "asset X is wrong"

**Before changing ANY file**, find out which file the game scene actually
references. Don't trust naming conventions. Don't trust the most recently
modified file. Don't trust the file I worked on last time.

### Trace chain (Godot)

```
scene.tscn          → grep for "ext_resource" entries
  → resource.gltf   → grep image URIs and material refs
    → texture.png   → confirm this is the file in question
```

Concrete steps:

1. **Find the scene(s) the user means.** "In my game" is ambiguous. Either
   ask or grep. For a "Peris's room" issue:
   ```python
   for f in find_files('*.tscn', root=project_root):
       if grep('peris', f) or grep('plant', f): print(f)
   ```

2. **Open the scene file and list its `ext_resource` lines.** This is
   ground truth — these are the resources Godot actually loads.

3. **For each resource path, recursively trace its dependencies**:
   - If it's a `.gltf` / `.glb` / `.scn`: read the JSON / inspect the
     `_subresources` and `dest_files` in its `.import` sidecar
   - If it's a `.tscn` / `.tres`: parse `ext_resource` lines again
   - Stop when you reach the texture/mesh file the user is complaining about

4. **Only then** decide what file to modify.

### Trace chain (Unity)

`.unity` scene file → `m_PrefabInstance` / `m_Materials` GUIDs → .meta
files in `Library/metadata/` → actual asset paths.

### Trace chain (Unreal)

`.umap` → asset paths in `.uasset` references → `Content/.../Texture.uasset`.

### Trace chain (Bevy / generic Rust)

grep `asset_server.load(` calls in `.rs` source for the path. Or check
`Cargo.toml` / `manifest.toml` for asset folders.

## Likely shadowing patterns to specifically check for

These are the ones that bit me:

1. **Combined/baked exports** that shadow individual files. A scene named
   "peris-sim" might load `peris-sim.gltf` (combined) instead of
   `plants/calathea_instanced.gltf` (individual). The combined file was
   probably exported from a single "garden scene" .blend, not the per-plant
   .blends. Texture names inside get auto-generated (`peris-sim_10.png`,
   `_peris-sim.png`) — they look like garbage but they ARE the loaded
   textures.

2. **`.obj` shadowing `.gltf`**. Same base name, both imported by the
   engine, scene references the `.obj` via its own `.import` sidecar — your
   `.gltf` edits don't apply.

3. **Stale engine caches**. Even after you update the source, the engine
   may serve a baked cache from `<project>/.godot/imported/*.scn` (Godot),
   `Library/` (Unity), `DerivedDataCache/` (Unreal), etc.

4. **Auto-renamed textures during glTF export**. Blender's glTF exporter
   sometimes auto-names extracted images to `<scene>_N.png`. If textures
   went through Blender → glTF → Blockbench → glTF, the original names
   like `CalLeafTex.png` get lost. Don't search for the original name —
   search for the actual loaded image by inspecting the .gltf's images
   array.

5. **Absolute paths in .mtl**. Wavefront `.mtl` files exported by Blender
   often contain absolute paths to the developer's local texture folder
   (e.g. `C:/Users/.../blender/peris-sim/textures/.../LeafTex.png`).
   The engine might load these directly or ignore them depending on
   importer settings.

## What to say to the user before making changes

After tracing, before doing anything destructive, state explicitly:

> "Your scene `peris_room.tscn` loads `peris-sim.gltf` (1.4 MB combined
> model). The calathea leaf texture inside it is `peris-sim_14.png` (1684
> bytes), not `calathea/CalLeafTex.png`. Want me to (a) update the
> combined glTF in-place, (b) regenerate the combined glTF from your
> individual plant glTFs, or (c) point the scene at the individual glTFs
> instead?"

The user picks the approach. Don't unilaterally rewrite the wrong file.

## Anti-pattern: assuming based on naming

What I did wrong, in order:

1. Saw `calathea_instanced.gltf` and `calathea.obj` in the plants folder
2. Assumed those were what the game loads
3. Spent hours updating them, the .mtl, the cached .scn, the .import
   sidecars
4. Never once opened a `.tscn` file to verify

What I should have done:

1. `grep -r calathea **/*.tscn` (or equivalent in Python)
2. See zero matches → the calathea isn't loaded by name
3. `grep -r peris-sim **/*.tscn` → find `peris_room.tscn` loads `peris-sim.gltf`
4. Inspect `peris-sim.gltf` → see the textures are `peris-sim_*.png`
5. Tell the user what's actually loaded
6. Get permission for the fix approach

Total time saved: most of a session.

## Quick verification script

Drop this in any Python-capable environment to trace from scene to texture:

```python
import os, re, json
def trace(scene_tscn, root):
    """Print every asset referenced (transitively) from a .tscn scene."""
    seen = set()
    def visit(path, depth=0):
        if path in seen: return
        seen.add(path)
        print("  " * depth + path)
        if not os.path.exists(path):
            print("  " * depth + "  (MISSING)")
            return
        if path.endswith(('.tscn', '.tres', '.import')):
            with open(path) as f:
                for line in f:
                    m = re.search(r'res://([^"]+)', line)
                    if m:
                        rel = m.group(1)
                        visit(os.path.join(root, rel), depth + 1)
        elif path.endswith(('.gltf',)):
            with open(path) as f:
                gltf = json.load(f)
            for img in gltf.get('images', []):
                uri = img.get('uri')
                if uri:
                    visit(os.path.join(os.path.dirname(path), uri), depth + 1)
    visit(scene_tscn)

# Usage:
# trace('C:/.../scenes/tutorial/peris_room.tscn', 'C:/.../to-rust-as-we-fall')
```

Run this BEFORE making any asset edits. The output is the only ground
truth that matters.
