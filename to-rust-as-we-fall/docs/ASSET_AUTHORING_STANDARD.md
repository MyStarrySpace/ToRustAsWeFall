# Editable 3D Asset Standard

Every new environment prop, building, fixture, creature, or other unique 3D visual must ship as an editable art asset, not only as geometry embedded in a Godot scene or constructed by a runtime script.

## Required deliverables

For each new 3D visual:

1. Store a portable source under `resources/models/<area-or-system>/<asset>/`. Preferred formats are `.gltf`/`.glb`; `.obj + .mtl + .png` is the standard for generated or box-modelled assets and opens directly in Blockbench.
2. Give every visible surface UV coordinates and keep its texture image external. A material color alone is not a retextureable asset.
3. Use a Godot `.tscn` as a thin wrapper for collision, scripts, lights, audio, labels, sockets, and gameplay metadata. Unique visible geometry belongs in the external model.
4. Keep model-space units in metres, Y up, and the asset origin at its placement pivot. Apply transforms before export when practical.
5. Group texture/material families deliberately. Multiple portable mesh parts are acceptable when they preserve distinct metal, emissive, glass, or damage treatments.
6. Include a repeatable bake/export tool when the source is generated. Re-running it must be deterministic; hand-painted texture edits should be preserved separately or intentionally copied forward.

Primitive meshes are still appropriate for invisible collision/debug volumes and clearly marked temporary blockout work. They are not the final source for a unique visible object.

## Blockbench-ready generated assets

Use `scripts/generation/uv_atlas_baker.gd` to turn generated `ArrayMesh` geometry into an OBJ kit with box-projected UVs and an external paint template:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script tools/bake_cleanstreets_assets.gd
```

The resulting `.obj` is the geometry source, `.mtl` binds the texture, and `.png` is the paintable atlas. Open the OBJ in Blockbench, repaint the linked PNG, and save/export without changing the Godot gameplay wrapper. Construction recipes used only for deterministic baking live under `tools/asset_sources/`; they must never be instantiated by runtime scenes.

The repository-wide generated catalogs and their runtime/dynamic classification are listed in
`docs/GENERATED_3D_ASSET_INVENTORY.md`. Generator changes must update that inventory and pass:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_generated_asset_contract.gd
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_peris_room_assets.gd
```

## Review checklist

- The external model loads independently of its gameplay scene.
- Every triangle has UVs; no unique visible mesh is a scene-local `BoxMesh`, `CylinderMesh`, or script-only mesh.
- Texture changes appear in Godot without rebuilding gameplay logic.
- Collision and interaction state remain legible after the visual asset is replaced or retextured.
