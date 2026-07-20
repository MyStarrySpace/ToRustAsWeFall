# Generated 3D Asset Inventory

This inventory separates final authored visuals from live visualization geometry. Final visuals follow
`editable_3d_v1`: portable model, external texture, deterministic source/bake, and a thin Godot gameplay
wrapper. Runtime geometry is allowed only when its shape represents changing state rather than an art asset.

## Portable generated catalogs

| Family | Portable source | Runtime owner | Repeatable source | Status |
| --- | --- | --- | --- | --- |
| Channels pump house | `resources/models/generated-biomes/channels_pump_house/` | `generated_channels_pump_house.tscn` | `biome_landmarks_source.tscn` + `bake_authored_asset_catalog.gd` | External OBJ/MTL/PNG |
| Stacks archive spire | `resources/models/generated-biomes/stacks_archive_spire/` | `generated_stacks_archive_spire.tscn` | same catalog | External OBJ/MTL/PNG |
| Garden root pavilion | `resources/models/generated-biomes/garden_root_pavilion/` | `generated_garden_root_pavilion.tscn` | same catalog | External OBJ/MTL/PNG |
| Deadzone chembrane ruin | `resources/models/generated-biomes/deadzone_chembrane_ruin/` | `generated_deadzone_chembrane_ruin.tscn` | same catalog | External OBJ/MTL/PNG |
| Cleanstreets pavilion and stud lane | `resources/models/cleanstreets/` | Cleanstreets theme scenes | `cleanstreets_landmarks_source.tscn` + `bake_cleanstreets_assets.gd` | External OBJ/MTL/PNG |
| Canonical district architecture | `resources/models/generated-architecture/<kind>/` | Parametric architecture builders | `architecture_showcase.tscn` + `bake_building_kit.gd` | 21 complete seed-0 kits |

The canonical architecture catalog includes `plumbing_power`, `honeycomb_cooperative`, `beacon_hill`,
`open_files`, `hypelines`, `greenfields`, `ancourage`, `bulwark_wharf`, `cleanstreets`, `zone3`,
`tiered_hall`, `tiered_terrace`, `aghora_exchange`, `aghora_stack`, `locas_watchtower`,
`nutech_facility`, `facility_checkpoint`, `fabrication_hall`, `bonded_warehouse`, `reclamation_works`,
and `distribution_substation`. Each kit includes the final body, entrances, lattice,
ledges, pipes, and district-specific details—not only the old base massing. The `.asset.json` beside each
kit records its seed and UV bake evidence.

To bake the canonical catalog or a deterministic variant:

```powershell
$env:BUILDING = "all"       # or one canonical kind
$env:SEED = "0"
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_building_kit.gd
```

Seeded variants are parametric outputs, not manually duplicated scenes. Bake the seed before taking a
variant into a DCC editor. Authored biome gameplay landmarks use external model wrappers; procedural
architecture preview/generation code remains the deterministic construction source for arbitrary seeds.

## Peris room asset inventory

| Zone | Assets | Portable location |
| --- | --- | --- |
| Shell source | floor, walls, room envelope, bench, and retired couch geometry | `resources/models/peris-sim/peris-sim.gltf` |
| Furniture source | portal, kiosk, retired plant stand, armchair, coffee table, bookshelf, rug, wall art and small decor | `resources/models/peris-sim/peris-furniture.gltf` |
| Plants | nine individually editable plant models | `resources/models/peris-sim/plants/` |
| Care props | watering can, wellness terminal, strike notice, labeled logbook console, field kit, and reusable plant table | `resources/models/peris-sim/props/` |
| Portal view | connected-room shell and Monos figure | `resources/models/peris-sim/portal_room/` |

The room layout lives in `scenes/tutorial/peris_sim.tscn`, not in scripted coordinates. Floor-plan
positions snap to 0.5 m; furniture yaw snaps to 90 degrees. Wall-mounted assets snap along their wall
axis and retain only the shallow wall-clearance inset on the perpendicular axis.

The organized plan is intentional character writing:

- West wall: portal and wellness administration.
- North wall: bench, painting, and bookshelf records; the purple couch is retired from the live layout.
- Center: one coffee/care surface with an open circulation lane around it.
- South row: nine independently interactable plants, each on its own 0.5 m-grid-authored portable table.
- East side: the labeled logbook is beside the shifted bookshelf; the strike notice is separated from Plant9.

`verify_peris_room_assets.gd` checks real post-import AABBs, not only marker centers. This prevents a
large plant canopy or odd DCC pivot from clipping furniture while still appearing grid-valid.

## Permitted runtime geometry

These are state visualizations rather than authored props and should remain procedural:

- movement path ribbons, final-position pills, targeting and rally previews;
- hover/selection grids, room measurement grids, causal links, and debug overlays;
- outline shells, particles, damage indicators, and other transient feedback;
- viewport-backed portal and monitor quads whose texture is a live render target;
- invisible collision, navigation, trigger, and test volumes.

If one of these becomes a fixed decorative object, it leaves this exception list and must be exported.

## Programmatic scene audit

The remaining high-concentration scripts are tracked by role rather than treated as automatically
compliant. `act1_sequence.gd`, `elevator_sequence.gd`, `leaving_facility_sequence.gd`,
`aster_sim_sequence.gd`, and `tag_day_sequence.gd` still mix authored set dressing with transient
feedback. Fixed set dressing in those files is the next wrapper migration queue; live encounter volumes,
path feedback, and animation surfaces remain permitted runtime geometry. New fixed visuals may not be
added to that queue: they must start as portable assets under `resources/models/`.

## Verification

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_generated_asset_contract.gd
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_peris_room_assets.gd
```

The generated-asset guard requires every biome definition to declare its portable model list, ensures
runtime landmark scenes contain external meshes instead of visible scene primitives, and verifies all
21 canonical architecture manifests. `verify_infrastructure_catalog.gd` additionally seed-sweeps the
four typed infrastructure surveys and checks their supply-chain compatibility. The Peris guard checks UV-bearing imported props,
layout contracts, furniture clearance, individual plant-table support and canopy clearance, retired
composition visibility, and a non-intersecting portal glow/live-view depth gap.
