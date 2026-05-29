# Script Layout

Keep reusable gameplay code in category folders so scenes do not become the only source of structure.

- `game/ai`: enemy, NPC, and AI behavior scripts.
- `game/characters`: player and character-control helpers.
- `game/mechanics`: reusable gameplay mechanics, solvers, and simulation helpers.
- `game/objects`: interactables, items, flora definitions, physics objects, and object feedback scripts.
- `game/world`: grid, zone, portal, gate, hub, and world-structure scripts.
- `system/core`: global runtime state, command events, and event logs.
- `system/persistence`: save and journal/autoload persistence code.
- `system/random`: deterministic RNG and stream registries.
- `system/scenes`: scene manager and scene-trigger dispatch.
- `system/simulation`: scheduler-driven survival, flora, and time simulation systems.
- `fragments`: puzzle-fragment catalog and runner code.
- `ui`: HUD, dialogue, camera, and tutorial prompt scripts.
- `tutorial`: authored tutorial sequence scripts that orchestrate reusable systems.

If a new script could be reused outside a specific scene, prefer one of the shared folders above instead of adding it beside the scene sequence.
