# Building Generation

The foundation for **procedural generation of the world's organic architecture and biology**.
A growing library of standalone, parametric GENERATORS, each producing one reusable organic form
with **LOD built in** (NEAR = real 3D mesh, FAR = a single flat plane + texture impostor).

Built for the project's low-poly + pixel-texture PS2 register. Runs in a **live Blender over the
socket** (`python /c/tmp/blsend.py < script.py`, Blender open with the Lab MCP add-on on `:9876`) —
not `--background`. Each generator renders its own demo to `C:\tmp` and saves a `.blend`; verify by
Reading the PNG.

## Philosophy

- **A generator is a pure, deterministic function of its params → object(s).** Seeded; uses the
  hash `helpers.h01(index)`, never `randf()`/wall-clock — so output is replayable and tweakable.
- **LOD by scale, always.** Ship BOTH `build_X(...)` (near, real geometry) and `build_X_far(...)`
  (far, one textured quad carrying the same read). Never mass-instance heavy geometry — a distant
  thing is an impostor. (This is the same rule the Paranucleus monomer-conveyance decision landed on.)
- **Faceted low-poly + pixel/procedural textures**, box-projected or generated-coord (no UV unwrap).
- **Self-contained + reusable.** Import the module and call `build_*`; the `if __name__` demo block
  only runs the showcase render.

## The generators

### `gen_voronoi_holemesh.py` — cellular hole-mesh
The membrane-pore / basement-membrane / cell-wall look: a plane seeded with points → Voronoi cells →
cell edges thickened into a **welded organic web with real holes**.
- `build_holemesh(size, density, thickness, height, merge, merge_start, shape, seed, mat)` — NEAR.
  Delaunay (`mathutils.geometry.delaunay_2d_cdt`, no SciPy) → circumcenters → cell polygons (shared
  verts) → `bmesh.ops.wireframe` → `solidify`. `merge` (0–1) fuses cells past `merge_start` (fraction
  of size) into larger openings. `shape` = `'square'` | `'disc'`.
- `build_holemesh_far(size, density, thickness, base)` — FAR. Flat plane + Voronoi-edge shader
  (`DISTANCE_TO_EDGE` → Map Range → alpha holes).
- **Use for:** membrane-pore windows/walls, filtration membranes, basement-membrane histology panels,
  any cellular/porous surface.

### `gen_building.py` — parametric whole-building generator (the §3 knob taxonomy)
The composition layer: assembles a complete hero building from the
`ARCHITECTURE_FABLE_BUILD_SPEC.md` §3 knobs. A building is a **preset dict** (see
`PLUMBING`): shell profile lathe with lobed-column feet (`Shell` — `lobe_n/amp/top/sharp`,
per-az `radial()/surf()/normal()` used by every wall-mounted part), spiral trough-ramp
(helix sweep: channel + emissive fluid + mesh parapet + rust ribs + brackets + wall entry),
capsule slit windows, valve wheels, wall-hugging pipe, sign (FONT text), hooded entry +
console, fluid-spill niche/steps/pool, flanking piers, cupola, roof clutter. In-Blender
deterministic 32px/m pixel tiles (`p_shingle/p_metal/p_rust/p_grate/p_paving` — no PIL),
box-projected, palette-locked (muted teal + ferric rust + terminal green `#5ce87f`).
- `build_building(P, M)` — NEAR. Returns `(objects, light_specs, shell)`. ~6k verts.
- `build_building_far(P, M, tex_res)` — FAR. Builds NEAR, snapshots it from the front
  azimuth (transparent film, ortho), deletes it, returns ONE shadeless emission×alpha quad.
- Acceptance target: `reference-images/architecture/plumbing_power_project.png` (§4.3) —
  matched via render-compare iteration + a 4-judge critique workflow.
- **Shells shipped:** `spiral_organic_mass` (lobed lathe drum — PLUMBING) and
  `drawer_stack_monolith` (OPEN_FILES: a radial ring of tapered rack-fins with bone edge
  ribs, emissive SERVER-RACK channels between them — `p_rack` LED tile — canted stepped
  tips as the crown, pierced grille ovals, cyan lit-tunnel portal with scan bar, glowing
  green sign, kiosks/lamps/bollards on a plinth apron). Switch the demo's `ACTIVE` preset
  (PLUMBING / OPEN_FILES); render lands at `C:\tmp\bldg_<name>.png`.
- **Use for:** all ten §4 hero archetypes — add a preset per archetype; new shells/crowns
  extend the same part vocabulary.

### `bld_kit.py` + `gen_building_sheets.py` — the §3 PARTS KIT + element sheets
Every §3 knob OPTION is a parametric part builder in `bld_kit.py`, matched against the
reference sheets in `reference-images/architecture/sheets/` (windows / doors / crowns /
projections / columns / signage / signforms / materials_decay): 7 window types, 5 doors,
7 crowns, 7 projections, 6 structural columns, 4 signage registers + 5 sign-forms +
district emblems, ~20 pixel-tile painters incl. 7 decay overlays. Style rules baked in:
BONE-CREAM structural members, teal panel infill, backlit membrane/hex-cell panes, moss
tufts, bolt studs, seam-seeded rust. Conventions: wall parts build in local X=width /
Y=up / Z=out frames (ALL offsets baked into verts; sub-objects share one place(loc, n));
freestanding parts build Z-up at origin. Dispatch tables (`WINDOWS/DOORS/CROWNS/
PROJECTIONS/STRUCTURES/SIGN_REGISTERS/SIGN_FORMS`) map option name -> builder;
`gen_building.build_building` consumes them via preset keys `kit_windows/kit_door/
kit_projections/kit_crown/kit_structures` (each spec = {type, az, h, out?} mounted on the
Shell). `gen_building_sheets.py` renders every variant as a labeled row to
`C:\tmp\kitsheet_*.png`.
GOTCHA (hex tiles): a lattice-seeded Voronoi tile must have NO duplicate seeds under the
%T wrap — duplicates make d2-d1==0 and flood the tile with edge colour. Use an exact
offset-brick lattice (T divisible by cell size).

### `gen_blob_mass.py` — blobby mass-of-spheres
The amyloid-aggregate / soft biological cluster: clustered spheres fused into a lumpy mass.
- `build_blob_mass(count, cluster_r, size_min, size_max, resolution, squash, seed, mat, faceted)` —
  NEAR. Metaballs polygonised into one blob mesh (`new_from_object` on the evaluated depsgraph).
- `build_blob_far(count, cluster_r, ..., seed, base, upright)` — FAR. Flat plane + a lumpy blob
  **alpha silhouette** (sum-of-gaussians of the projected cluster).
- **Use for:** amyloid aggregates (see the Paranucleus), Candid fungal colonies, blobby masses.

## Run

```
python /c/tmp/blsend.py < blender/skills/building-generation/gen_voronoi_holemesh.py
python /c/tmp/blsend.py < blender/skills/building-generation/gen_blob_mass.py
```

Renders `C:\tmp\gen_voronoi_demo.png` / `gen_blob_demo.png`. `helpers.py` holds the shared
deterministic/faceted/LOD/demo utilities new generators should import.

## Adding a new generator (the contract)

1. Deterministic: hash an index via `helpers.h01`, never `randf`.
2. Provide a NEAR `build_X` **and** a FAR `build_X_far` impostor from the **same params**.
3. Faceted (`use_smooth=False`); keep vert count low; box-projected / generated-coord textures.
4. EEVEE-Next alpha via `helpers.alpha_flags(mat)` (the old `blend_method` was removed in 4.2+).
5. Params on the call signature; a `if __name__ ... : True` demo block that renders a near-vs-far sheet.
6. Document it in this file (form, `build_*` signature, "use for").

## Roadmap (this is the foundation — later phases)

- **More generators:** tube/pipe network, branching fractal mass, cilia/frond field, tiled facade
  panels, twisted-conduit/myelin wrap, membrane bilayer with pores.
- **Composition layer:** assemble whole buildings from these generators + `spatial_grammar.py`
  (relational placement) — driven by the `ARCHITECTURE_DESIGN.md` parameter taxonomy (each §3 knob → a
  generator call).
- **Auto-LOD:** bake the FAR impostor texture directly from the NEAR render instead of hand-authoring.
- **Godot hook:** export GLBs to `resources/models/`, bind via `RoomModelBinder`.

## See also

- `blender/spatial_grammar.py` — relational placement (slab/wall/recess/on_wall/row) for composition.
- `blender/skills/low-poly/` — faceted primitives; `blender/skills/pixel-atlas-texturing/` — the tile atlas.
- `to-rust-as-we-fall/ARCHITECTURE_DESIGN.md` — the parts taxonomy these generators feed.
