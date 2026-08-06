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
| World biota placeholders | `resources/models/shared/biota_placeholders/` | `BiotaPlaceholderCatalog` + thin prop wrappers | `biota_placeholder_kit_source.tscn` + `bake_biota_placeholder_assets.gd` | 3 flora + 1 fauna silhouettes, external OBJ/MTL/PNG |

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

## Authored fauna assets

| Fauna | Portable source | Runtime wrapper | Editable source | Motion-ready structure |
| --- | --- | --- | --- | --- |
| Ferrule | `resources/models/fauna/ferrule/` | `scenes/props/biota/ferrule_visual.tscn` | `../blender/fauna/ferrule/ferrule.blend` | 17 named mesh parts, 7 rigid rig pivots, and idle/compress/spring/latch clips |

The Ferrule visual carries the approved mobile, mouth-first slinky silhouette. Its body, mouth void,
fluorescent signal, and signal-emissive paint sheets stay external and independently replaceable. The
wrapper exposes forward, mouth-impact, and rear-anchor sockets but deliberately owns no collision or
enemy authority. This asset does not by itself promote `ferrules` beyond placeholder gameplay support.

Re-export the saved master from the repository root without rebuilding its geometry:

```powershell
blender.exe --background blender/fauna/ferrule/ferrule.blend --python blender/fauna/ferrule/export_ferrule.py
```

## World biota placeholder inventory

This bounded starter kit supplies world-scale, intentionally replaceable presenters where an
interaction currently has only a ball, box, or runtime-only SDF preview. It does not replace Peris's
potted houseplants and does not own gameplay behavior.

| Key | Readable silhouette / tell | Portable families |
| --- | --- | --- |
| `flora/seefern` | upright fan with three luminous vision tips | `seefern_body`, `seefern_signal` |
| `flora/hushbloom` | low leaves and a charged nodding rosette | `hushbloom_body`, `hushbloom_signal` |
| `flora/scarpet` | ankle-high woven runner network | `scarpet` |
| `fauna/sapscrap` | C3 three-palp body, clamp tips, one raised luminous palp | `sapscrap_body`, `sapscrap_signal` |

Runtime systems discover these scenes through `BiotaPlaceholderCatalog`; collision, interactions,
animation, authority, and save state remain in the owning flora or enemy wrapper. The split signal
families let live state change glow without replacing or recoloring the organism's body.

To rebake the whole kit or one model:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_biota_placeholder_assets.gd
$env:BIOTA_ASSET = "seefern"
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_biota_placeholder_assets.gd
Remove-Item Env:BIOTA_ASSET
```

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

## Mother Flure mechanism inventory

| Mechanism | Portable source | Runtime wrapper | Live-state presenter |
| --- | --- | --- | --- |
| Portal hardware | `resources/models/mother-flure/portal_frame/` | `scenes/props/mother_flure/portal_frame.tscn` | The luminous lens remains a procedural state surface; both fixed and remote frames use the external ring model. |
| Two-hand Mother Gear | `resources/models/mother-flure/mother_gear/` | `scenes/props/mother_flure/mother_gear.tscn` | Ground, carried, and installed states instantiate the same `mother_gear_v1` visual identity. |
| Rings chembrane | `resources/models/mother-flure/rings_membrane/` | `scenes/props/mother_flure/rings_membrane.tscn` | The external ribbed membrane lifts with the saved gate-opening progress; collision follows authoritative phase. |

All three are baked from `tools/asset_sources/mother_flure_mechanisms_source.tscn` by the shared
catalog. To rebake only this family without overwriting unrelated hand-edited catalog assets:

```powershell
$env:ASSET_FAMILY = "mother-flure/"
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_authored_asset_catalog.gd
Remove-Item Env:ASSET_FAMILY
```

`verify_mother_flure_visual_assets.gd` checks each OBJ/MTL/PNG triplet, imported UVs, thin wrappers,
runtime instancing, dynamic-lens classification, shared gear identity, and physical membrane lift.

## Inflammashunt salvage inventory

| Mechanism | Portable source | Runtime wrapper | Repeatable source |
| --- | --- | --- | --- |
| Resolution Catalyst | `resources/models/inflammashunt/resolution_catalyst/` | `scenes/props/inflammashunt/resolution_catalyst.tscn` | `tools/asset_sources/inflammashunt_device_source.tscn` + `tools/bake_inflammashunt_device_asset.gd` |

The sealed housing contains the same `inflammashunt_resolution_catalyst_v1` visual identity that moves
into a character's hand after the exact source-item claim. The lid and interaction wrapper remain
gameplay geometry; the distinctive catalyst body is an external, UV-mapped OBJ/MTL/PNG kit. Rebake it
without touching other catalog assets with:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_inflammashunt_device_asset.gd
```

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
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_mother_flure_visual_assets.gd
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_biota_placeholder_assets.gd
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_biota_gameplay_presenters.gd
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_ferrule_model.gd
```

The generated-asset guard requires every biome definition to declare its portable model list, ensures
runtime landmark scenes contain external meshes instead of visible scene primitives, and verifies all
21 canonical architecture manifests. `verify_infrastructure_catalog.gd` additionally seed-sweeps the
four typed infrastructure surveys and checks their supply-chain compatibility. The Peris guard checks UV-bearing imported props,
layout contracts, furniture clearance, individual plant-table support and canopy clearance, retired
composition visibility, and a non-intersecting portal glow/live-view depth gap.
The biota gameplay-presenter guard additionally verifies that production Scarpet and Hushbloom
wrappers instance the catalog meshes, preserve collision and concealment semantics, and isolate
state-driven Hushbloom signal materials per organism.
