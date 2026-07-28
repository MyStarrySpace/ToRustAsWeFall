# World Biota Placeholder Kit

This folder contains intentionally replaceable, world-scale flora and fauna silhouettes. They are
not the potted houseplants from Peris's simulation and they do not own gameplay logic.

The deterministic source is
`tools/asset_sources/biota_placeholder_kit_source.tscn`; bake its portable OBJ/MTL/PNG outputs with:

```powershell
..\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/bake_biota_placeholder_assets.gd
```

Set `BIOTA_ASSET` to `seefern`, `hushbloom`, `scarpet`, or `sapscrap` to rebake only one silhouette.
Open the resulting OBJ beside its linked PNG in Blockbench or another DCC tool. Hand-painted texture
edits are intentionally external; rebaking replaces a generated paint template only when requested.

Runtime callers should use `BiotaPlaceholderCatalog` and keep collision, interaction, authoritative
state, and animation in their gameplay wrapper. Signal meshes are separate material families so glow
can be driven without recoloring the whole organism.
