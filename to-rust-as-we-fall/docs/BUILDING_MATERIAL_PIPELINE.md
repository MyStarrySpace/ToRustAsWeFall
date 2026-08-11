# Building materials — the pipeline, and what has to happen before a wall wears it

The architecture is drawn procedurally in GDScript. Its surfaces are now backed by drawn tiles under
`resources/materials/building/`, composed by `building_surface.gdshader` and handed out by
`BuildingMaterialLibrary`. Ten materials and seven decay overlays, from
`reference-images/architecture/sheets/materials_decay.png`, giving seventy surfaces out of seventeen
files. Both layers are hand-paintable: drop a file of the same name into `blender/materials/painted/`
and it wins on the next build.

**Nothing in the game wears it yet, and that is deliberate.** Three things have to be settled first,
and each of them turns a naive swap into a visible or a gameplay-level regression.

## 1. The batched geometry has the WRONG UVs, not missing ones

`level_decorator.gd` accumulates architecture into MultiMesh batches off one shared unit `BoxMesh`.
That mesh does carry UV0 — Godot's 3x2 per-face box atlas — and no UV2. Two consequences:

- Every face would sample a **1/3 x 1/2 crop** of the tile stretched across the whole face.
- The UVs are normalised **per box, not per metre**. One `trim` batch spans a 227 m drain race and a
  0.055 m curb; a single `uv_scale` cannot serve both, and the texel density between them differs by
  orders of magnitude.

So a material swap today renders something BROKEN rather than nothing, which is the worse failure —
it looks like a bug in the art instead of an unfinished wiring step.

Emitting metric UVs would mean giving up the MultiMesh batching, which is the whole contract. The
route that survives instancing is a **world-space coordinate source** in the shader
(`MODEL_MATRIX * VERTEX`, density from a `tiles_per_m` uniform), which fixes the crop and the density
together and needs no geometry change. Add it as a second branch, default off, so the existing path
is untouched.

**Unresolved, flag before committing to it:** alpha under a triplanar blend. `ALPHA = base.a` with a
scissor threshold assumes ONE projection; blending three will scissor unevenly at box edges on the
open materials (`base_03_crosshatch_grating`, `base_09_voronoi_screen`). Take alpha from the
dominant axis, or gate the triplanar path to solid bases first. The tiles also import without
mipmaps, by pixel-art intent — a long corridor viewed down its length will alias, so capture a
down-corridor frame before converting more batches.

## 2. A library ShaderMaterial silently opts a wall OUT of camera occlusion

`camera_occlusion_manager.gd` `_wrap()` returns null for **any** ShaderMaterial, by design — water,
outlines and fog encode behaviour a wrapper cannot reconstruct. The decoration batches dissolve in
front of the player today *only because they are plain StandardMaterial3Ds*.

Give a batch a library ShaderMaterial and it stops dissolving: that wall goes solid between the
camera and the player. This is a gameplay regression, not a rendering one, and no current test
covers it.

Whatever the fix (carrying the occlusion cut into `building_surface.gdshader` and marking the
material occlusion-aware is one option), `tools/verify_preview_decoration_occlusion.gd` has to change
in the same commit: its predicate is currently "is wrapped", and it must become "participates in the
dissolve".

## 3. Roles the library does not map

`ROLE_BASE` answers `mass`, `trim`, `service`, `inset`, `rust` and the biological set. The decorator
also batches `glow`, `dark` and `leaf`, which are **not** surfaces this library should dress — a glow
strip is not riveted panelling. `has_role()` exists so an adopter can tell a real answer from the
wall-shaped fallback; use it, and leave the unmapped batches alone.

## Already fixed, recorded so it is not reintroduced

A missing overlay used to bleach the wall. Leaving `decay_tex` unset does not mean "no overlay" —
Godot supplies an opaque white texture, the coverage reads 1.0, and the surface mixes toward white.
A mistyped decay id produced a clean white wall. `surface()` now forces the wear to zero when the
overlay is absent, and `--test-building-materials` fails if that guard is removed.
