# Asset Tools

## Display-backed capture and playthrough tools

Do not raw-launch a GUI Godot binary for an automated capture, movie render,
test, persona run, or approval playthrough on a Windows desktop. Godot clamps
ordinary top-level startup positions back onto a monitor before a tool script
runs, so `--position 20000,20000` and a later `OffscreenWindow.park()` can still
flash the game in the bottom-right corner. `Start-Process -WindowStyle Hidden`
only hides the console wrapper; it does not isolate the GUI engine it starts.

Required automated gameplay validation must run from the repository root via
`scripts/test-gate.ps1`. That launcher creates the reviewed never-shown native
owner before starting the GUI engine, passes the owner with `--wid`, and audits
the render window for its whole lifetime. Standalone screenshot scripts under
`tools/capture_*.gd`, `tools/cap_*.gd`, and automated movie scripts have no
equivalent Windows launcher yet. Run them on an isolated display host (for
example Linux/Xvfb), not directly on a person's Windows desktop.

`tools/record_playthrough.ps1` is an attended human-recording tool and therefore
opens a visible game window. On Windows it requires `-AllowVisibleWindow`.
`tools/render_playthrough.ps1` also fails closed on Windows unless that explicit
visible-window opt-in is supplied; neither PowerShell script is valid automated
test or persona evidence.

## Blockbench-ready generated assets

New unique 3D visuals must follow [`docs/ASSET_AUTHORING_STANDARD.md`](../docs/ASSET_AUTHORING_STANDARD.md). The Cleanstreets exporter turns tooling-only construction scenes into UV-mapped `.obj + .mtl + .png` model kits used by thin Godot gameplay wrappers:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script tools/bake_cleanstreets_assets.gd
```

Open any exported OBJ under `resources/models/cleanstreets/` in Blockbench and paint its adjacent PNG. Re-run the baker only when intentionally regenerating the model and template, because it replaces the generated paint sheets.

## glTF sidecar material wiring

Use `gltf_wire_material_sidecars.py` after re-exporting a Crocotile `.gltf`. Crocotile rewrites the material table, so previously wired emissive and normal textures can disappear even when the sidecar PNG files are still beside the base textures. This tool reconnects sidecars by naming convention.

Example:

```powershell
python tools\gltf_wire_material_sidecars.py `
  resources\models\aster-sim\room\aster-sim-room-hi-res.gltf `
  --emissive-factor "#9bd7ff" `
  --emissive-strength 2.5 `
  --normal-scale 1.0 `
  --fail-on-no-changes
```

By default, each base texture looks for `*_emissive.png`, `*_normals.png`, and `*_normal.png`. Use `--dry-run` to check what would be reconnected without editing the GLTF.

## glTF emissive masks from palette colors

Use `gltf_emissive_from_color.py` when an asset uses a flat palette color to mark lights, screens, signs, or other glowing details. The tool scans each material's base-color texture, writes a black emissive mask where only matching pixels are lit, and wires that mask back into the `.gltf`.

Example:

```powershell
python tools\gltf_emissive_from_color.py `
  resources\models\aster-sim\room\aster-sim-room-hi-res.gltf `
  --color "#fcfffa" `
  --emit-color "#fcfffa" `
  --factor-color "#9bd7ff" `
  --strength 2.5
```

Useful options:

- `--color "#RRGGBB"` can be repeated to make several palette colors glow in one mask.
- `--tolerance 8` catches near-matches from anti-aliasing or texture compression. Leave it at `0` for exact palette colors.
- `--material NAME` or `--material 0` limits the edit to specific materials.
- `--emit-color "#RRGGBB"` writes a different glow color into the emissive mask. By default, matched pixels keep their source color.
- `--factor-color "#RRGGBB"` tints the material emissive factor. Use this for glow color direction, such as a cool blue over a pale emissive mask.
- `--dry-run` reports what would change without writing PNGs or editing the glTF.

Commit both the changed `.gltf` and the generated `*_emissive.png`. After changing model assets, run:

```powershell
..\Godot_v4.6.1-stable_win64_console.exe --headless --path . -- --test-scene-load
```
