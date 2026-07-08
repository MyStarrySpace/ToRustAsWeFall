# Android export

The main game is set up to export an Android `.apk`, mirroring the proven `level-sketch/` pipeline (a debug
keystore + the prebuilt export template — **no** full gradle/SDK build). Everything is configured; the one
piece that has to be installed once per Godot version is the **Android export template**.

## Status / prerequisites (already in place)

- **Export preset** — `export_presets.cfg` (preset `Android`): `com.trawf.torustaswefall`, `arm64-v8a`,
  `gradle_build/use_gradle_build=false`, signed with the shared debug keystore
  `C:/Users/quest/AppData/Roaming/Godot/keystores/debug.keystore`. Output: `build/trawf.apk`.
- **SDK + JDK** — configured in the 4.7 editor settings (`editor_settings-4.7.tres`):
  `android_sdk_path = C:/Users/quest/android-dev/sdk`, `java_sdk_path = .../jdk-17.0.19+10`. A dry-run export
  finds the SDK fine.
- **Mobile project settings** — `display/window/handheld/orientation = 4` (sensor-landscape) and
  `input_devices/pointing/emulate_mouse_from_touch = true` (so a tap hits menu/HUD buttons + the builder).

## The one missing piece: the 4.7 export template

Only the **4.6.1** templates are installed; the game is 4.7, so the 4.7 Android template
(`~/AppData/Roaming/Godot/export_templates/4.7.stable/android_release.apk`) is needed. A headless export
otherwise fails with exactly that path. Install it **once**:

- In the editor: **Editor ▸ Manage Export Templates ▸ Download and Install** (matches the running 4.7 build), or
- Download `Godot_v4.7-stable_export_templates.tpz` from the Godot 4.7 release and let the editor install it.

## Build

From the repo root (with the 4.7 console binary), after the template is installed:

```bash
./Godot_v4.7-stable_win64_console.exe --headless --path "to-rust-as-we-fall" \
    --export-debug "Android" build/trawf.apk
```

`adb install -r to-rust-as-we-fall/build/trawf.apk` to sideload, or use the editor's one-click deploy.

## Touch controls (what works on a phone)

- **Menus + HUD buttons** — tap (Control buttons + emulate-mouse-from-touch).
- **Level Builder** — one finger paints with the current brush; **two fingers pan + pinch-zoom** (the
  level-sketch model). Erase = the Erase brush + tap. Guarded by `--test-builder-touch`.
- **Game camera** — **two-finger pan + pinch-zoom** (`game_camera.gd`); single-finger stays gameplay.

**Follow-up (not done):** a full RTS touch scheme for the main GAME's single-finger interaction (tap-to-move vs
tap-to-select without the emulated-mouse ambiguity) is a larger task — the builder + camera gestures cover the
primary mobile use (sketch a level, walk it). See `[[camera_mobile_gestures]]` for the twist-rotate gesture TODO.
