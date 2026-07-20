# Infrastructure Construction Catalog

This catalog extends the district architecture as connective tissue: buildings that receive, transform,
buffer, recover, and distribute things. They use the same measure-first process as the hero buildings:

1. Declare a canonical envelope in metres.
2. Declare a repeatable construction module and bay count.
3. Survey datums, plan, profile, doors, and typed service sockets.
4. Build visible construction detail only from that survey.
5. Bake the complete seed specimen to UV-mapped OBJ/MTL/PNG for DCC editing.

## Canonical schedule

| Structure | Envelope | Module | Bays | Role | Inputs | Outputs |
| --- | --- | --- | ---: | --- | --- | --- |
| Fabrication Hall | 4.2 x 5.4 x 4.0 m | 1.05 m | 4 | Transform | metal stock, electricity, process water | fabricated goods, wastewater |
| Bonded Warehouse | 4.4 x 6.2 x 4.2 m | 1.10 m | 4 | Buffer | fabricated goods, inventory data | freight |
| Reclamation Works | 4.10 m diameter x 5.5 m | 0.78 m | 8 | Recover | wastewater, electricity | process water |
| Distribution Substation | 4.0 x 4.8 x 4.0 m | 0.80 m | 5 | Distribute | grid power | electricity, data |

Dimensions are width x height x depth. Seeded variants scale the surveyed envelope coherently; service
ports are normalized construction coordinates resolved onto the resulting wall profile, not copied
absolute positions.

## Causal composition

The procedural landmark grammar can constrain a second infrastructure pick by compatible ports. Exact
commodity types currently support these local loops:

- Distribution Substation -> Fabrication Hall or Reclamation Works: `electricity`.
- Fabrication Hall -> Bonded Warehouse: `fabricated_goods`.
- Fabrication Hall -> Reclamation Works: `wastewater`.
- Reclamation Works -> Fabrication Hall: `process_water`.
- Distribution Substation -> Bonded Warehouse: `data`.

The resulting `infrastructure_links` are planning data. They do not create a solid pipe across a street;
a theme can express the link as overhead conduit, underground utility, freight staging, or a causal
overlay without changing navigation. Inputs are marked by cold scanner-blue facade lights and outputs
by terminal green, giving the player a consistent read of flow direction.

## Portable editing

Canonical outputs live under `resources/models/generated-architecture/<kind>/` and contain:

- `<kind>_seed_0.obj` — UV-mapped portable model;
- `<kind>_seed_0.mtl` — external material reference;
- `<kind>_seed_0.png` — external atlas texture;
- `<kind>_seed_0.asset.json` — deterministic source, seed, atlas, and contract evidence.

Rebake one edited construction seed with:

```powershell
$env:BUILDING = "fabrication_hall"
$env:SEED = "0"
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/bake_building_kit.gd
```

Verify the measurement and composition contracts with:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/verify_infrastructure_catalog.gd
```
