# Rising water and moving-platform archetype

This document owns the design model and generation guidance for surfaces whose movement changes
navigation. Runtime code should contain executable state, validation, and authority contracts, not
design explanations exposed as string-valued APIs.

## Causal model

The master state for a rising-water crossing is the ordered water-state index. Each authored state
independently selects water height, platform height, floor walkability, platform walkability, and
the surfaces caught by the water.

The intended player prediction is: the next committed water state selects the traversable map.
Failure tests that prediction visibly. A body caught below the committed waterline follows the
current to an authored recovery vertex. The evidence is the water height, platform height, physical
motion window, and resulting route topology.

The moving-platform layer is more general than water. The same relationship applies to piston
lifts, translating platforms, and rotating arms: when a platform transform changes, occupants move
with it and routes depending on its cells are recomputed against the new topology.

## Runtime boundary

The runtime receives concrete data and executes it:

- `water_states`: two or more ordered state dictionaries;
- `rota`: state indices and dwell durations;
- `telegraph_lead`: when hazard feedback begins;
- `platform_motion_lead`: when the physical surface begins moving;
- floor bounds, safe cells, moving-platform cells, recovery cells, and sweep parameters;
- paired data/render waypoint paths for platform passengers.

Waypoint paths make the carrier mechanism-neutral. Two points describe a piston or linear lift.
Sampled arc points describe a rotating platform. Gameplay code validates and follows those points;
it does not need prose declaring which motif they represent.

## Route-change rule

Before a platform begins moving, record active routes whose remaining cells intersect its surface.
A character currently on the surface becomes a passenger, even if they were partway through a
route. At the topology commit, the passenger lands at the platform endpoint and the saved route is
replanned to its original destination. Approaching routes that depended on changed cells are also
replanned. Automatic schedules and manual controls enter through this same transition boundary.

Hazard warning and physical motion use separate clocks. This permits an early diegetic warning
while route feasibility is calculated from the exact later motion window.

## Procedural-generation inputs

The grid-rectangle builder needs:

- grid origin and cell size;
- inclusive floor minimum and maximum cells;
- inclusive moving-platform minimum and maximum cells;
- at least one recovery cell per party member;
- an ordered water-state list and a rota referencing valid state indices.

Generation rejects duplicate platform cells, invalid state indices, non-increasing water
elevations, missing recovery capacity, and recovery cells that are not safe. Generated recovery
vertices must remain connected to playable topology rather than becoming unreachable failure sinks.

## Basin composition

The Balancing Basin is one authored composition of this archetype. Its familiar low, middle, and
high states are a preset, not an engine limit. Future authored or generated crossings may use any
number of ordered states without adding runtime branches.
